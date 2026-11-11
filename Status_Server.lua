--// ##########################################################################################
--// ##                                                                                      ##
--// ##   MANDATORY: USE ENGLISH (US) ONLY IN THIS FILE                                      ##
--// ##   Every comment, UI text, message and name here MUST be written in English (US).     ##
--// ##   Never add any other language to this file. Keep it English (US) on every edit.     ##
--// ##                                                                                      ##
--// ##########################################################################################

--// ================= STATUS & SERVER TAB (module) =================

return function(ctx)
    local StatusServerTab     = ctx.Tab
    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local CoreGui             = ctx.CoreGui
    local LocalPlayer         = ctx.LocalPlayer
    local TeleportService     = ctx.TeleportService
    local HttpService         = ctx.HttpService
    local UI                  = assert(ctx.UI, "Status_Server.lua needs ctx.UI")
    local showToast           = ctx.Toast or UI.Toast or function() end
    local Players             = ctx.Players or game:GetService("Players")
    local Stats               = game:GetService("Stats")
    local GuiService          = game:GetService("GuiService")

    local new, corner, stroke, padding, list, label = ctx.new, ctx.corner, ctx.stroke, ctx.padding, ctx.list, ctx.label
    local CreateInfoRow, CreateCard = ctx.CreateInfoRow, ctx.CreateCard
    local CreateStyledButton, CreateToggleOption = ctx.CreateStyledButton, ctx.CreateToggleOption
    local flashButtonFeedback, flashStrokeError = ctx.flashButtonFeedback, ctx.flashStrokeError
    local bindBoxFocus, guarded, isLocked = ctx.bindBoxFocus, ctx.guarded, ctx.isLocked

    --// ---------- Config ----------
    local SPAM_JOIN_DELAY  = 1.5
    local PENDING_TIMEOUT  = 10
    local HOP_WAIT_RESULT  = 6
    local HOP_MAX_ATTEMPTS = 3
    local PAGE_DELAY       = 0.3

    local ScriptStartTime  = os.time()
    local copyToClipboard  = UI.CopyText
    local formatAgo        = UI.FormatAgo

    local function formatTime(seconds)
        if type(seconds) ~= "number" then return "--" end
        seconds = math.max(0, math.floor(seconds))
        return string.format("%dh%dm%ds", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60)
    end

    local function isValidJobId(jobId)
        return type(jobId) == "string" and jobId:match("^%x+%-%x+%-%x+%-%x+%-%x+$") ~= nil
    end

    local function parseJoinInput(raw)
        if type(raw) ~= "string" then return nil, nil, "Invalid" end
        local text = raw:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        text = text:gsub("[%s\"']", ""):lower()
        if text == "" then return nil, nil, "Invalid" end
        if isValidJobId(text) then return text, nil end
        if text:find("privateserverlinkcode=", 1, true) then return nil, nil, "Private" end

        local jobId = text:match("gameinstanceid=([%x%-]+)")
        if not isValidJobId(jobId) then return nil, nil, "Invalid" end
        local placeId = text:match("placeid=(%d+)") or text:match("/games/(%d+)")
        return jobId, tonumber(placeId)
    end

    --// ---------- Shared teleport state ----------
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

    local function joinServer(jobId, placeId)
        if not isValidJobId(jobId) then return false, "Invalid" end
        if jobId == game.JobId then return false, "Same" end
        if teleportPending then return false, "Busy" end
        local ok = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, placeId or game.PlaceId, jobId, LocalPlayer)
        if not ok then return false, "Failed" end
        markPending()
        return true
    end

    --// ---------- Server history ----------
    local HISTORY_FILE, HISTORY_MAX = "Elysera_Servers.json", 10
    local history = {}

    do
        local data = UI.ReadJson(HISTORY_FILE)
        if data and type(data.history) == "table" then
            for _, e in ipairs(data.history) do
                if type(e) == "table" and type(e.place) == "number" and isValidJobId(e.id) and type(e.t) == "number" then
                    history[#history + 1] = { place = e.place, id = e.id, t = e.t }
                    if #history >= HISTORY_MAX then break end
                end
            end
        end
        local id = game.JobId
        if isValidJobId(id) then
            for i = #history, 1, -1 do
                if history[i].id == id then table.remove(history, i) end
            end
            table.insert(history, 1, { place = game.PlaceId, id = id, t = os.time() })
            while #history > HISTORY_MAX do table.remove(history) end
            UI.WriteJson(HISTORY_FILE, { v = 1, history = history })
        end
    end

    local function previousServer()
        for _, e in ipairs(history) do
            if e.place == game.PlaceId and e.id ~= game.JobId then return e end
        end
        return nil
    end

    --// ---------- Live & copy rows ----------
    local liveRows = {}

    local function CreateLiveRow(parent, title, getText)
        local Frame = CreateInfoRow(parent, title)
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

        liveRows[#liveRows + 1] = { Value = Value, get = getText }
        return Frame
    end

    local function refreshLiveRows()
        for _, row in ipairs(liveRows) do
            local parent = row.Value.Parent
            local holder = parent and parent.Parent
            if holder and holder.Visible ~= false then
                local ok, txt = pcall(row.get)
                if ok and type(txt) == "string" and row.Value.Text ~= txt then
                    row.Value.Text = txt
                end
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

    CreateLiveRow(StatusServerTab, "Timer", function() return formatTime(os.time() - ScriptStartTime) end)
    CreateLiveRow(StatusServerTab, "Time Played", function() return formatTime(time()) end)
    CreateLiveRow(StatusServerTab, "Players", function()
        return string.format("%d/%d", #Players:GetPlayers(), Players.MaxPlayers)
    end)

    local pingItem
    pcall(function() pingItem = Stats.Network.ServerStatsItem["Data Ping"] end)
    CreateLiveRow(StatusServerTab, "Ping", function()
        if not pingItem then return "--" end
        return string.format("%d ms", math.floor(pingItem:GetValue() + 0.5))
    end)

    local isOpen = ctx.isOpen or function() return true end
    local MainUI = ctx.MainUI
    local function windowVisible()
        return StatusServerTab.Visible and (not MainUI or MainUI.Visible)
    end

    local liveRun = 0
    local function onVisibilityChanged()
        if isOpen() and StatusServerTab.Visible then refreshLiveRows() end
        if windowVisible() then
            liveRun = liveRun + 1
            local myRun = liveRun
            task.spawn(function()
                while ScreenGui.Parent and myRun == liveRun and windowVisible() do
                    if isOpen() then refreshLiveRows() end
                    task.wait(0.5)
                end
            end)
        end
    end
    StatusServerTab:GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged)
    if MainUI then MainUI:GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged) end
    onVisibilityChanged()

    CreateCopyRow(StatusServerTab, "PlaceID", function() return tostring(game.PlaceId) end, true)

    --// ---------- Server Hopper ----------
    do
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
            Box.Text = UI.Trim(Box.Text)
            refreshPlaceholder()
        end)
        Box:GetPropertyChangedSignal("Text"):Connect(refreshPlaceholder)

        local function getTarget()
            if UI.Trim(Box.Text) == "" then return nil, nil, "Empty" end
            return parseJoinInput(Box.Text)
        end

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
                if reason == "Invalid" or reason == "Same" then flashStrokeError(BoxStroke) end
                flashButtonFeedback(JoinBtn, "Join", reason or "Failed", true, 0.8)
                return
            end

            joinBusy = true
            flashButtonFeedback(JoinBtn, "Join", "Joining...", false)
            task.delay(1.2, function() joinBusy = false end)
        end)

        local Switch, setSpamState = CreateToggleOption(Card, "Spam Join", 40, { noSession = true })
        Switch.Parent.LayoutOrder = 4
        Switch.Parent.BackgroundColor3 = Theme.PanelAlt

        local runId = 0
        Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
            runId = runId + 1
            if not Switch:GetAttribute("Toggled") then return end

            local firstId = getTarget()
            if not firstId or firstId == game.JobId then
                flashStrokeError(BoxStroke)
                setSpamState(false)
                return
            end

            failStreak = 0
            local myRun = runId
            task.spawn(function()
                while Switch:GetAttribute("Toggled") and myRun == runId and ScreenGui.Parent do
                    local jobId, placeId = getTarget()
                    if not jobId or jobId == game.JobId then
                        flashStrokeError(BoxStroke)
                        setSpamState(false)
                        break
                    end
                    if not isLocked() then joinServer(jobId, placeId) end
                    task.wait(SPAM_JOIN_DELAY + math.min(failStreak, 5) * 0.5)
                end
            end)
        end)
    end

    CreateCopyRow(StatusServerTab, "Copy Server JobId", function() return game.JobId end, false)
    CreateCopyRow(StatusServerTab, "Copy Join Link", function()
        if game.JobId == "" then return "" end
        return ("roblox://experiences/start?placeId=%d&gameInstanceId=%s"):format(game.PlaceId, game.JobId)
    end, false)

    --// ---------- Rejoin & Auto Rejoin on Kick ----------
    do
        local Frame = CreateInfoRow(StatusServerTab, "Rejoin Server")
        local RejoinBtn = CreateStyledButton(Frame, "Rejoin", 70)
        RejoinBtn.Activated:Connect(guarded(function(done)
            local ok = not teleportPending and pcall(function()
                if game.JobId == "" then
                    TeleportService:Teleport(game.PlaceId, LocalPlayer)
                else
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                end
            end)
            if ok then markPending() end
            flashButtonFeedback(RejoinBtn, "Rejoin", ok and "Rejoining..." or "Failed", not ok)
            done()
        end))

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
    end

    --// ---------- Previous Server & Recent Servers ----------
    do
        local Frame, Left = CreateInfoRow(StatusServerTab, "Previous Server")
        local function describePrev()
            local prev = previousServer()
            return prev and formatAgo(prev.t) or "--"
        end
        local AgoLabel = label(Left, {
            LayoutOrder = 2,
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = describePrev(),
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.AccentPink,
        })
        liveRows[#liveRows + 1] = { Value = AgoLabel, get = describePrev }

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

        local RecentSec = UI.CreateSection(StatusServerTab, "Recent Servers", 0, {
            subtitle = ("Last %d visited servers in history"):format(#history),
            collapsed = true,
        })
        for idx, entry in ipairs(history) do
            local isCurrent = (entry.id == game.JobId)
            local Row, RLeft = CreateInfoRow(RecentSec.Body, ("#%d · %s..."):format(idx, entry.id:sub(1, 8)), 42)
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
                liveRows[#liveRows + 1] = { Value = SubL, get = function() return formatAgo(entry.t) end }
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
    end

    --// ---------- Server Hop & Server Browser ----------
    do
        local failedJobIds = {}
        local httpRequest = UI.HttpRequest

        local function isUsable(srv)
            return type(srv) == "table"
                and type(srv.id) == "string"
                and srv.id ~= game.JobId
                and not failedJobIds[srv.id]
                and type(srv.playing) == "number"
                and type(srv.maxPlayers) == "number"
                and srv.playing < srv.maxPlayers
        end

        local function collectServers(sortOrder, maxPages, enough, accept)
            local listOut, cursor, lastErr = {}, "", nil
            for page = 1, maxPages do
                local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%d&limit=100")
                    :format(game.PlaceId, sortOrder)
                if cursor ~= "" then url = url .. ("&cursor=" .. HttpService:UrlEncode(cursor)) end

                local body, err = httpRequest(url)
                if not body then lastErr = err; break end

                local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
                if not ok or type(data) ~= "table" or type(data.data) ~= "table" then
                    lastErr = "Failed"
                    break
                end

                for _, srv in ipairs(data.data) do
                    if isUsable(srv) and accept(srv) then
                        listOut[#listOut + 1] = srv
                    end
                end
                if #listOut >= enough then break end

                cursor = data.nextPageCursor
                if type(cursor) ~= "string" or cursor == "" then break end
                if page < maxPages then task.wait(PAGE_DELAY) end
            end
            return listOut, lastErr
        end

        local function shuffle(arr, n)
            for i = math.min(n, #arr), 2, -1 do
                local j = math.random(1, i)
                arr[i], arr[j] = arr[j], arr[i]
            end
        end

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
            elseif mode == "least" then
                local listOut, err = collectServers(1, 2, 20, function(srv) return srv.playing >= 1 end)
                table.sort(listOut, function(a, b) return a.playing < b.playing end)
                shuffle(listOut, 5)
                return listOut, err
            end

            local listOut, err = collectServers(2, 5, 30, function(srv)
                return srv.playing <= math.max(0, srv.maxPlayers - 2)
            end)
            shuffle(listOut, #listOut)
            return listOut, err
        end

        local function hopServer(mode)
            failedJobIds = {}
            local candidates, err = pickServers(mode)
            if #candidates == 0 then return false, err or "No server" end

            for tried = 1, math.min(#candidates, HOP_MAX_ATTEMPTS) do
                local srv = candidates[tried]
                local ok, reason = joinServer(srv.id)
                if not ok then
                    if reason == "Busy" then return false, "Busy" end
                    failedJobIds[srv.id] = true
                else
                    for _ = 1, math.ceil(HOP_WAIT_RESULT / 0.2) do
                        if not teleportPending then break end
                        task.wait(0.2)
                    end
                    if teleportPending then return true end
                    failedJobIds[srv.id] = true
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

            for i = 1, math.min(#cachedServers, 15) do
                local srv = cachedServers[i]
                local pingTxt = type(srv.ping) == "number" and (math.floor(srv.ping + 0.5) .. "ms") or "--"
                local fpsTxt = type(srv.fps) == "number" and (math.floor(srv.fps + 0.5) .. "fps") or "--"
                local Row, Left = CreateInfoRow(ListFrame, string.format("%d/%d players", srv.playing, srv.maxPlayers), 40)
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
                local servers, err = collectServers(order, 2, 30, function(srv) return srv.playing >= 1 end)
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
    end
end
