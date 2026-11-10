--// ##########################################################################################
--// ##                                                                                      ##
--// ##   MANDATORY: USE ENGLISH (US) ONLY IN THIS FILE                                      ##
--// ##   Every comment, UI text, message and name here MUST be written in English (US).     ##
--// ##   Never add any other language to this file. Keep it English (US) on every edit.     ##
--// ##                                                                                      ##
--// ##########################################################################################

--// ================= STATUS & SERVER TAB (module) =================
-- This file is loaded by the main script (MainLocal.lua / MainWeb.lua) and called with a ctx table
-- containing the shared UI functions/variables.
--
-- Server tools:
--   * Join JobId   : the input box accepts a bare JobId or a link with gameInstanceId (roblox://..., https://www.roblox.com/games/...)
--   * Copy Join Link, Rejoin Server, Auto Rejoin on Kick
--   * Previous Server & Recent Servers (up to 10 servers stored in Elysera_Servers.json)
--   * Server Hop / Less People / Best Ping + Server Browser with Join button (reusing collectServers)

return function(ctx)
    local StatusServerTab     = ctx.Tab

    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local CoreGui             = ctx.CoreGui
    local LocalPlayer         = ctx.LocalPlayer
    local TeleportService     = ctx.TeleportService
    local HttpService         = ctx.HttpService
    local UI                  = assert(ctx.UI, "Status_Server.lua needs ctx.UI: update MainWeb.lua / MainLocal.lua to the new core")
    local showToast           = ctx.Toast or UI.Toast or function() end
    local Players             = game:GetService("Players")
    local Stats               = game:GetService("Stats")
    local GuiService          = game:GetService("GuiService")

    local new                 = ctx.new
    local corner              = ctx.corner
    local stroke              = ctx.stroke
    local padding             = ctx.padding
    local list                = ctx.list
    local label               = ctx.label

    local CreateInfoRow       = ctx.CreateInfoRow
    local CreateCard          = ctx.CreateCard
    local CreateStyledButton  = ctx.CreateStyledButton
    local CreateToggleOption  = ctx.CreateToggleOption
    local flashButtonFeedback = ctx.flashButtonFeedback
    local flashStrokeError    = ctx.flashStrokeError
    local bindBoxFocus        = ctx.bindBoxFocus
    local guarded             = ctx.guarded
    local isLocked            = ctx.isLocked -- replaces the main file's uiLocked variable
    local canFS               = ctx.canFS == true
    local dataPath            = ctx.dataPath or function(name) return name end

    --// ---------- Config ----------
    local SPAM_JOIN_DELAY  = 1.5  -- seconds between two Spam Join attempts (grows automatically after repeated errors)
    local PENDING_TIMEOUT  = 10   -- after this many seconds the previous teleport counts as finished/expired
    local HOP_WAIT_RESULT  = 6    -- wait at most this many seconds to see whether the teleport gets rejected
    local HOP_MAX_ATTEMPTS = 3    -- maximum number of servers to try per Hop
    local PAGE_DELAY       = 0.3  -- pause between API pages to avoid HTTP 429

    local ScriptStartTime = os.time() -- os.clock() is CPU time, not real time

    --// ---------- Utilities ----------
    local function formatTime(seconds)
        if type(seconds) ~= "number" then return "--" end
        seconds = math.max(0, math.floor(seconds))
        return string.format("%dh%dm%ds", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60)
    end

    -- Shared clipboard helper from the core UI kit (tries every executor's clipboard function); true when copied
    local copyToClipboard = UI.CopyText

    -- A Roblox JobId is always a GUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    local function isValidJobId(jobId)
        return type(jobId) == "string"
            and jobId:match("^%x+%-%x+%-%x+%-%x+%-%x+$") ~= nil
    end

    -- The Join box accepts a bare JobId or a link with gameInstanceId:
    --   roblox://experiences/start?placeId=123&gameInstanceId=<JobId>
    --   https://www.roblox.com/games/start?placeId=123&gameInstanceId=<JobId>
    --   https://www.roblox.com/games/123/Game-Name?gameInstanceId=<JobId>   (including the encoded forms %3D, %26...)
    -- Returns jobId, placeId (nil when the link does not state it), or nil, nil, reason ("Invalid" | "Private")
    local function parseJoinInput(raw)
        if type(raw) ~= "string" then return nil, nil, "Invalid" end
        local text = raw:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        text = text:gsub("[%s\"']", ""):lower()
        if text == "" then return nil, nil, "Invalid" end
        if isValidJobId(text) then return text, nil end
        -- private server links use a code, so there is no JobId to teleport to directly
        if text:find("privateserverlinkcode=", 1, true) then return nil, nil, "Private" end

        local jobId = text:match("gameinstanceid=([%x%-]+)")
        if not isValidJobId(jobId) then return nil, nil, "Invalid" end
        local placeId = text:match("placeid=(%d+)") or text:match("/games/(%d+)")
        return jobId, tonumber(placeId)
    end

    --// ---------- Shared teleport state ----------
    -- teleportPending = true right after a teleport was requested and the result is not known yet.
    -- If it succeeds, the client leaves the server (the script stops); if it fails,
    -- TeleportInitFailed reports back and we unlock again.
    local teleportPending = false
    local pendingToken    = 0
    local failStreak      = 0

    local function markPending()
        teleportPending = true
        pendingToken = pendingToken + 1
        local token = pendingToken
        task.delay(PENDING_TIMEOUT, function()
            if pendingToken == token then teleportPending = false end
        end)
    end

    local failedConn = TeleportService.TeleportInitFailed:Connect(function(player)
        if player ~= LocalPlayer then return end
        pendingToken = pendingToken + 1
        teleportPending = false
        failStreak = failStreak + 1
    end)

    ScreenGui.Destroying:Connect(function()
        failedConn:Disconnect()
    end)

    -- Returns ok, reason (short, fits a 70px button). placeId = nil: use the current place
    local function joinServer(jobId, placeId)
        if not isValidJobId(jobId) then return false, "Invalid" end
        if jobId == game.JobId then return false, "Same" end
        if teleportPending then return false, "Busy" end
        local ok = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, placeId or game.PlaceId, jobId, LocalPlayer)
        if not ok then return false, "Failed" end
        markPending()
        return true
    end

    --// ---------- Server history (for "Previous Server" & "Recent Servers") ----------
    -- Every time Elysera runs on a server, record (place, JobId, time) in the file so it is remembered after the teleport.
    local HISTORY_FILE, HISTORY_MAX = "Elysera_Servers.json", 10
    local history = {} -- newest first: { place = number, id = string, t = os.time() }

    local function loadHistory()
        if not canFS then return end
        local ok, data = pcall(function()
            local path = dataPath(HISTORY_FILE)
            if isfile(path) then return HttpService:JSONDecode(readfile(path)) end
        end)
        if not (ok and type(data) == "table" and type(data.history) == "table") then return end
        for _, e in ipairs(data.history) do
            if type(e) == "table" and type(e.place) == "number" and isValidJobId(e.id) and type(e.t) == "number" then
                history[#history + 1] = { place = e.place, id = e.id, t = e.t }
                if #history >= HISTORY_MAX then break end
            end
        end
    end

    local function saveHistory()
        if not canFS then return end
        pcall(function()
            writefile(dataPath(HISTORY_FILE), HttpService:JSONEncode({ v = 1, history = history }))
        end)
    end

    local function recordCurrentServer()
        local id = game.JobId
        if not isValidJobId(id) then return end
        for i = #history, 1, -1 do
            if history[i].id == id then table.remove(history, i) end -- one record per server, moved to the top
        end
        table.insert(history, 1, { place = game.PlaceId, id = id, t = os.time() })
        while #history > HISTORY_MAX do table.remove(history) end
        saveHistory()
    end

    -- The most recent server of this game that is not the current server
    local function previousServer()
        for _, e in ipairs(history) do
            if e.place == game.PlaceId and e.id ~= game.JobId then return e end
        end
        return nil
    end

    local function formatAgo(t)
        local d = math.max(0, os.time() - t)
        if d < 60 then return "<1m ago" end
        if d < 3600 then return math.floor(d / 60) .. "m ago" end
        if d < 86400 then return math.floor(d / 3600) .. "h ago" end
        return math.floor(d / 86400) .. "d ago"
    end

    loadHistory()
    recordCurrentServer()

    --// ---------- Continuously updating info rows ----------
    local liveRows = {}

    local function CreateLiveRow(parent, title, getText)
        local Frame = CreateInfoRow(parent, title)

        -- Value takes 110px on the right; shrink Left (default -90) so the title does not overlap Value
        local Left = Frame:FindFirstChild("Left")
        if Left then Left.Size = UDim2.new(1, -118, 1, 0) end

        local Value = label(Frame, {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(110, 24),
            Text = "--",
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextColor3 = Theme.AccentPink,
        })

        table.insert(liveRows, { Value = Value, get = getText })
        return Frame
    end

    local function refreshLiveRows()
        for _, row in ipairs(liveRows) do
            local ok, txt = pcall(row.get)
            if ok and type(txt) == "string" and row.Value.Text ~= txt then
                row.Value.Text = txt
            end
        end
    end

    local function CreateCopyRow(parent, title, getText, showValue)
        local Frame, Left = CreateInfoRow(parent, title)

        if showValue then
            label(Left, {
                LayoutOrder = 2,
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = getText(),
                TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = Theme.AccentPink,
            })
        end

        local Btn = CreateStyledButton(Frame, "Copy", 70)
        Btn.Activated:Connect(guarded(function(done)
            local text = getText()
            local ok = text ~= "" and copyToClipboard(text)
            flashButtonFeedback(Btn, "Copy", ok and "Copied!" or "Failed", not ok)
            done()
        end))
        return Frame
    end

    CreateLiveRow(StatusServerTab, "Timer", function()
        return formatTime(os.time() - ScriptStartTime)
    end)

    -- time() = seconds since the client entered this server (resets when teleporting to another server)
    CreateLiveRow(StatusServerTab, "Time Played", function()
        return formatTime(time())
    end)

    CreateLiveRow(StatusServerTab, "Players", function()
        return string.format("%d/%d", #Players:GetPlayers(), Players.MaxPlayers)
    end)

    local pingItem
    pcall(function()
        pingItem = Stats.Network.ServerStatsItem["Data Ping"]
    end)
    CreateLiveRow(StatusServerTab, "Ping", function()
        if not pingItem then return "--" end
        return string.format("%d ms", math.floor(pingItem:GetValue() + 0.5))
    end)

    local isOpen = ctx.isOpen or function() return true end
    local MainUI = ctx.MainUI
    local function tabShowing()
        return isOpen() and StatusServerTab.Visible
    end
    local function windowVisible()
        return StatusServerTab.Visible and (not MainUI or MainUI.Visible)
    end

    local liveRun = 0
    local function startLiveLoop()
        liveRun = liveRun + 1
        local myRun = liveRun -- an old loop (if still alive) exits by itself on its next check
        task.spawn(function()
            while ScreenGui.Parent and myRun == liveRun and windowVisible() do
                if isOpen() then refreshLiveRows() end
                task.wait(0.5)
            end
        end)
    end

    local function onVisibilityChanged()
        if tabShowing() then refreshLiveRows() end
        if windowVisible() then startLiveLoop() end
    end
    StatusServerTab:GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged)
    if MainUI then MainUI:GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged) end
    onVisibilityChanged()

    CreateCopyRow(StatusServerTab, "PlaceID", function() return tostring(game.PlaceId) end, true)

    --// ---------- Server Hopper ----------
    do (function()
        local Card = CreateCard(StatusServerTab, "ServerHopper", 12, 14, 12)

        label(Card, {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 20),
            Text = "Server Hopper",
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Text,
        })

        local Box = new("TextBox", {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "",
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClipsDescendants = true,
        }, Card)
        corner(Box, 6)
        local BoxStroke = stroke(Box)
        padding(Box, 10, 10)

        local Placeholder = label(Box, {
            Size = UDim2.fromScale(1, 1),
            Text = "Paste a JobId or join link here",
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.SubText,
            TextTransparency = 0.5,
        })

        local function refreshPlaceholder()
            Placeholder.Visible = Box.Text == "" and not Box:IsFocused()
        end

        bindBoxFocus(Box, BoxStroke, refreshPlaceholder, function()
            Box.Text = (Box.Text:gsub("^%s+", ""):gsub("%s+$", ""))
            refreshPlaceholder()
        end)
        Box:GetPropertyChangedSignal("Text"):Connect(refreshPlaceholder)

        -- Returns jobId, placeId, reason (see parseJoinInput); empty box -> nil, nil, "Empty"
        local function getTarget()
            if (Box.Text:gsub("%s", "")) == "" then return nil, nil, "Empty" end
            return parseJoinInput(Box.Text)
        end

        -- Join JobId
        local JoinFrame = CreateInfoRow(Card, "Join JobId", 40)
        JoinFrame.LayoutOrder = 3
        JoinFrame.BackgroundColor3 = Theme.PanelAlt

        local JoinBtn = CreateStyledButton(JoinFrame, "Join", 70)
        local joinBusy = false
        JoinBtn.Activated:Connect(function()
            if isLocked() or joinBusy then return end
            local jobId, placeId, why = getTarget()
            if not jobId then
                flashStrokeError(BoxStroke)
                flashButtonFeedback(JoinBtn, "Join", why or "Invalid", true, 0.8)
                return
            end

            local ok, reason = joinServer(jobId, placeId)
            if not ok then
                if reason == "Invalid" or reason == "Same" then
                    flashStrokeError(BoxStroke)
                end
                flashButtonFeedback(JoinBtn, "Join", reason or "Failed", true, 0.8)
                return
            end

            joinBusy = true
            flashButtonFeedback(JoinBtn, "Join", "Joining...", false)
            task.delay(1.2, function() joinBusy = false end)
        end)

        -- Spam Join
        local Switch, setSpamState = CreateToggleOption(Card, "Spam Join", 40, { noSession = true })
        Switch.Parent.LayoutOrder = 4
        Switch.Parent.BackgroundColor3 = Theme.PanelAlt

        local runId = 0

        local function stopSpam()
            setSpamState(false)
        end

        Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
            runId = runId + 1
            if not Switch:GetAttribute("Toggled") then return end

            -- JobId empty / wrong / same as the current server: report the error and switch off, do not run a pointless loop
            local firstId = getTarget()
            if not firstId or firstId == game.JobId then
                flashStrokeError(BoxStroke)
                stopSpam()
                return
            end

            failStreak = 0
            local myRun = runId
            task.spawn(function()
                while Switch:GetAttribute("Toggled") and myRun == runId and ScreenGui.Parent do
                    local jobId, placeId = getTarget()
                    if not jobId or jobId == game.JobId then
                        flashStrokeError(BoxStroke)
                        stopSpam()
                        break
                    end

                    if not isLocked() then
                        joinServer(jobId, placeId) -- skips itself if the previous teleport has no result yet
                    end

                    -- on consecutive errors, back off gradually so Roblox does not rate-limit us
                    task.wait(SPAM_JOIN_DELAY + math.min(failStreak, 5) * 0.5)
                end
            end)
        end)
    end)() end

    CreateCopyRow(StatusServerTab, "Copy Server JobId", function() return game.JobId end, false)

    -- Link that opens this server directly (paste it into someone else's Join box, or open it in a browser with Roblox installed)
    CreateCopyRow(StatusServerTab, "Copy Join Link", function()
        if game.JobId == "" then return "" end
        return ("roblox://experiences/start?placeId=%d&gameInstanceId=%s"):format(game.PlaceId, game.JobId)
    end, false)

    --// ---------- Rejoin & Auto Rejoin on Kick ----------
    local function doRejoin()
        if teleportPending then return false end
        local ok = pcall(function()
            if game.JobId == "" then
                TeleportService:Teleport(game.PlaceId, LocalPlayer)
            else
                TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
            end
        end)
        if ok then markPending() end
        return ok
    end

    do (function()
        local Frame = CreateInfoRow(StatusServerTab, "Rejoin Server")
        local RejoinBtn = CreateStyledButton(Frame, "Rejoin", 70)
        RejoinBtn.Activated:Connect(guarded(function(done)
            local ok = doRejoin()
            flashButtonFeedback(RejoinBtn, "Rejoin", ok and "Rejoining..." or "Failed", not ok)
            done()
        end))
    end)() end

    -- Auto Rejoin when kicked or disconnected
    do (function()
        local KickSwitch = CreateToggleOption(StatusServerTab, "Auto Rejoin on Kick")
        local kickConns = {}
        local rejoining = false

        local function triggerAutoRejoin()
            if rejoining or not KickSwitch:GetAttribute("Toggled") then return end
            rejoining = true
            showToast("Disconnected - auto rejoining...", "warn", { duration = 4 })
            task.spawn(function()
                while KickSwitch:GetAttribute("Toggled") and ScreenGui.Parent do
                    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
                    task.wait(2.5)
                end
                rejoining = false
            end)
        end

        local function stopAutoRejoin()
            rejoining = false
            for _, c in ipairs(kickConns) do c:Disconnect() end
            table.clear(kickConns)
        end

        local function startAutoRejoin()
            stopAutoRejoin()
            pcall(function()
                kickConns[#kickConns + 1] = GuiService.ErrorMessageChanged:Connect(function(msg)
                    if type(msg) == "string" and msg ~= "" then triggerAutoRejoin() end
                end)
            end)
            pcall(function()
                local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
                local overlay = promptGui and promptGui:FindFirstChild("promptOverlay")
                if overlay then
                    if overlay:FindFirstChild("ErrorPrompt") then triggerAutoRejoin() end
                    kickConns[#kickConns + 1] = overlay.ChildAdded:Connect(function(child)
                        if child.Name == "ErrorPrompt" then triggerAutoRejoin() end
                    end)
                end
            end)
        end

        KickSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
            if KickSwitch:GetAttribute("Toggled") then startAutoRejoin() else stopAutoRejoin() end
        end)
        ScreenGui.Destroying:Connect(stopAutoRejoin)
    end)() end

    --// ---------- Previous Server & Recent Servers (up to 10) ----------
    do (function()
        local Frame, Left = CreateInfoRow(StatusServerTab, "Previous Server")
        local AgoLabel = label(Left, {
            LayoutOrder = 2,
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.AccentPink,
        })
        local function describe()
            local prev = previousServer()
            return prev and formatAgo(prev.t) or "--"
        end
        AgoLabel.Text = describe()
        table.insert(liveRows, { Value = AgoLabel, get = describe }) -- "x ago" is updated by the same live loop

        local Btn = CreateStyledButton(Frame, "Join", 70)
        Btn.Activated:Connect(guarded(function(done)
            local prev = previousServer()
            if not prev then
                flashButtonFeedback(Btn, "Join", "None", true, 0.8)
                done()
                return
            end
            local ok, reason = joinServer(prev.id, prev.place)
            flashButtonFeedback(Btn, "Join", ok and "Joining..." or (reason or "Failed"), not ok)
            done()
        end))

        -- Recent Servers section (renders the saved history list up to 10 entries)
        local RecentSec = UI.CreateSection(StatusServerTab, "Recent Servers", 0, {
            subtitle = ("Last %d visited servers in history"):format(#history),
            collapsed = true,
        })
        for idx, entry in ipairs(history) do
            local isCurrent = (entry.id == game.JobId)
            local shortId = entry.id:sub(1, 8) .. "..."
            local Row, RLeft = CreateInfoRow(RecentSec.Body, ("#%d · %s"):format(idx, shortId), 42)
            local SubL = label(RLeft, {
                LayoutOrder = 2,
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = isCurrent and "Current" or formatAgo(entry.t),
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = isCurrent and Theme.Sakura or Theme.SubText,
            })
            if not isCurrent then
                table.insert(liveRows, { Value = SubL, get = function() return formatAgo(entry.t) end })
                local JBtn = CreateStyledButton(Row, "Join", 64)
                JBtn.Activated:Connect(guarded(function(done)
                    local ok, reason = joinServer(entry.id, entry.place)
                    flashButtonFeedback(JBtn, "Join", ok and "Joining..." or (reason or "Failed"), not ok)
                    done()
                end))
            else
                local CBtn = CreateStyledButton(Row, "Copy", 64)
                CBtn.Activated:Connect(guarded(function(done)
                    local ok = copyToClipboard(entry.id)
                    flashButtonFeedback(CBtn, "Copy", ok and "Copied!" or "Failed", not ok)
                    done()
                end))
            end
        end
    end)() end

    --// ---------- Server Hop & Server Browser ----------
    do (function()
        local failedJobIds = {} -- servers that were tried and rejected; never picked again

        local function httpRequest(url)
            local fn = (syn and syn.request) or http_request or request
                or (http and http.request) or (fluxus and fluxus.request)
            if not fn then return nil, "No HTTP" end

            local ok, res = pcall(fn, { Url = url, Method = "GET" })
            if not ok or type(res) ~= "table" then return nil, "Failed" end

            local code = res.StatusCode
            if code == 429 then return nil, "Limited" end
            if type(code) == "number" and (code < 200 or code >= 300) then return nil, "Failed" end

            if type(res.Body) == "string" then return res.Body end
            return nil, "Failed"
        end

        local function isUsable(srv)
            return type(srv) == "table"
                and type(srv.id) == "string"
                and srv.id ~= game.JobId
                and not failedJobIds[srv.id]
                and type(srv.playing) == "number"
                and type(srv.maxPlayers) == "number"
                and srv.playing < srv.maxPlayers
        end

        -- sortOrder: 1 = fewest players first (Asc), 2 = most players first (Desc)
        -- Stop early once there are enough candidates (`enough`) to save requests.
        local function collectServers(sortOrder, maxPages, enough, accept)
            local listOut, cursor, lastErr = {}, "", nil

            for page = 1, maxPages do
                local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%d&limit=100")
                    :format(game.PlaceId, sortOrder)
                if cursor ~= "" then url = url .. ("&cursor=" .. HttpService:UrlEncode(cursor)) end

                local body, err = httpRequest(url)
                if not body then
                    lastErr = err
                    break
                end

                local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
                if not ok or type(data) ~= "table" or type(data.data) ~= "table" then
                    lastErr = "Failed"
                    break
                end

                for _, srv in ipairs(data.data) do
                    if isUsable(srv) and accept(srv) then
                        table.insert(listOut, srv)
                    end
                end

                if #listOut >= enough then break end

                cursor = data.nextPageCursor
                if type(cursor) ~= "string" or cursor == "" then break end
                if page < maxPages then task.wait(PAGE_DELAY) end
            end

            return listOut, lastErr
        end

        -- shuffle the first n elements of the list
        local function shuffle(arr, n)
            for i = math.min(n, #arr), 2, -1 do
                local j = math.random(1, i)
                arr[i], arr[j] = arr[j], arr[i]
            end
        end

        -- mode: "random" | "least" (fewest players) | "ping" (lowest ping)
        local function pickServers(mode)
            if mode == "ping" then
                local listOut, err = collectServers(2, 5, 200, function(srv)
                    return type(srv.ping) == "number" and srv.ping > 0
                        and srv.playing <= math.max(0, srv.maxPlayers - 2)
                end)
                table.sort(listOut, function(a, b)
                    if a.ping ~= b.ping then return a.ping < b.ping end
                    return (type(a.fps) == "number" and a.fps or 0) > (type(b.fps) == "number" and b.fps or 0)
                end)
                return listOut, err
            end

            if mode == "least" then
                local listOut, err = collectServers(1, 2, 20, function(srv)
                    return srv.playing >= 1
                end)
                table.sort(listOut, function(a, b) return a.playing < b.playing end)
                shuffle(listOut, 5)
                return listOut, err
            end

            -- Random hop: avoid nearly full servers (they easily fail with GameFull)
            local listOut, err = collectServers(2, 5, 30, function(srv)
                return srv.playing <= math.max(0, srv.maxPlayers - 2)
            end)
            shuffle(listOut, #listOut)
            return listOut, err
        end

        -- Returns true while teleporting, or false + a short reason
        local function hopServer(mode)
            failedJobIds = {} -- every Hop press starts fresh: do not let the list of failed servers grow forever
            local candidates, err = pickServers(mode)
            if #candidates == 0 then return false, err or "No server" end

            local tried = 0
            for _, srv in ipairs(candidates) do
                if tried >= HOP_MAX_ATTEMPTS then break end
                tried = tried + 1

                local ok, reason = joinServer(srv.id)
                if not ok then
                    if reason == "Busy" then return false, "Busy" end
                    failedJobIds[srv.id] = true
                else
                    -- wait to see whether Roblox rejects it (server full / closed...)
                    for _ = 1, math.ceil(HOP_WAIT_RESULT / 0.2) do
                        if not teleportPending then break end
                        task.wait(0.2)
                    end
                    if teleportPending then return true end -- still teleporting: counts as success
                    failedJobIds[srv.id] = true             -- rejected: try the next server
                end
            end

            return false, "Failed"
        end

        local function bindHopButton(title, mode)
            local Frame = CreateInfoRow(StatusServerTab, title)
            local Btn = CreateStyledButton(Frame, "Hop", 70)
            Btn.Activated:Connect(guarded(function(done)
                flashButtonFeedback(Btn, "Hop", "Finding...", false, math.huge, Theme.SubText)
                task.spawn(function()
                    local ok, result, reason = pcall(hopServer, mode)
                    if ok and result then
                        flashButtonFeedback(Btn, "Hop", "Hopping...", false)
                    else
                        flashButtonFeedback(Btn, "Hop", (ok and reason) or "Failed", true)
                    end
                    done()
                end)
            end))
        end

        bindHopButton("Server Hop", "random")
        bindHopButton("Server Hop With Less People", "least")
        bindHopButton("Server Hop With Best Ping", "ping")

        --// ---------- Server Browser (reuses collectServers) ----------
        local BrowserSec = UI.CreateSection(StatusServerTab, "Server Browser", 0, {
            subtitle = "Browse public servers and join directly",
            collapsed = true,
        })
        local ControlRow, ControlLeft = CreateInfoRow(BrowserSec.Body, "Public Servers", 44)
        local SortBtn = CreateStyledButton(ControlRow, "Ping", 68)
        SortBtn.Position = UDim2.new(1, -76, 0.5, 0)
        local RefreshBtn = CreateStyledButton(ControlRow, "Refresh", 70)

        local ListFrame = new("Frame", {
            Name = "BrowserList",
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, BrowserSec.Body)
        list(ListFrame, 6)

        local StatusHint = label(ControlLeft, {
            LayoutOrder = 2,
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "Tap Refresh",
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.SubText,
        })

        local SORTS = { "Ping", "Least", "Most" }
        local sortIdx = 1
        local cachedServers = {}

        local function renderBrowser()
            for _, c in ipairs(ListFrame:GetChildren()) do
                if c:IsA("Frame") then c:Destroy() end
            end
            local mode = SORTS[sortIdx]
            table.sort(cachedServers, function(a, b)
                if mode == "Ping" then
                    local pa = type(a.ping) == "number" and a.ping or 9999
                    local pb = type(b.ping) == "number" and b.ping or 9999
                    if pa ~= pb then return pa < pb end
                elseif mode == "Least" then
                    if a.playing ~= b.playing then return a.playing < b.playing end
                else
                    if a.playing ~= b.playing then return a.playing > b.playing end
                end
                return tostring(a.id) < tostring(b.id)
            end)

            local count = math.min(#cachedServers, 15)
            for i = 1, count do
                local srv = cachedServers[i]
                local pingTxt = type(srv.ping) == "number" and (math.floor(srv.ping + 0.5) .. "ms") or "--"
                local fpsTxt = type(srv.fps) == "number" and (math.floor(srv.fps + 0.5) .. "fps") or "--"
                local title = string.format("%d/%d players", srv.playing, srv.maxPlayers)
                local Row, Left = CreateInfoRow(ListFrame, title, 40)
                Row.LayoutOrder = i
                label(Left, {
                    LayoutOrder = 2,
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = string.format("· %s · %s", pingTxt, fpsTxt),
                    Font = Enum.Font.Gotham,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextColor3 = Theme.AccentPink,
                })
                local JBtn = CreateStyledButton(Row, "Join", 64)
                JBtn.Activated:Connect(guarded(function(done)
                    local ok, reason = joinServer(srv.id)
                    flashButtonFeedback(JBtn, "Join", ok and "Joining..." or (reason or "Failed"), not ok)
                    done()
                end))
            end
        end

        SortBtn.Activated:Connect(function()
            if isLocked() then return end
            sortIdx = sortIdx % #SORTS + 1
            SortBtn.Text = SORTS[sortIdx]
            if #cachedServers > 0 then renderBrowser() end
        end)

        RefreshBtn.Activated:Connect(guarded(function(done)
            flashButtonFeedback(RefreshBtn, "Refresh", "Loading...", false, math.huge, Theme.SubText)
            StatusHint.Text = "Fetching..."
            task.spawn(function()
                failedJobIds = {}
                local order = (SORTS[sortIdx] == "Least") and 1 or 2
                local servers, err = collectServers(order, 2, 30, function(srv)
                    return srv.playing >= 1
                end)
                cachedServers = servers
                if #servers > 0 then
                    StatusHint.Text = #servers .. " found"
                    renderBrowser()
                    flashButtonFeedback(RefreshBtn, "Refresh", "Loaded", false)
                else
                    StatusHint.Text = err or "No servers"
                    renderBrowser()
                    flashButtonFeedback(RefreshBtn, "Refresh", err or "Empty", true)
                end
                done()
            end)
        end))
    end)() end
end
