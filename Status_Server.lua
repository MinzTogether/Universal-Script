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
--   * Copy Join Link, Rejoin Server
--   * Auto Rejoin  : after a kick or a disconnect, teleport back automatically (3 second countdown with a Cancel button).
--                    The first rejoin returns to the same server, later ones go to a fresh server, and it stops after 4 rejoins
--                    in 10 minutes (counted across servers) so a ban cannot cause an endless loop.
--                    Turn on Auto Execute in Settings so Elysera runs again on the new server.
--   * Previous Server : go back to the most recent server where Elysera ran (history is stored in Elysera_Servers.json;
--                       turn on Auto Execute in Settings so Elysera runs again and keeps recording after every teleport)
--   * Server Hop / Less People / Best Ping (ping and fps come with the server list API)
--   * Server Browser : list public servers (players, ping, FPS), sort them and join one
--   * Recent Servers : the last 10 servers Elysera ran on, each with a Join button
--
-- Optional services from the core (this module also works when they are missing):
--   ctx.Toast(message, kind, opts)     : shared toast; kind = "info" | "success" | "warn" | "error",
--                                        opts = { duration, actionText, onAction }
--   ctx.Session.get(id) / .set(id, on) : "Restore last session" - remembers switch states across server changes

return function(ctx)
    local StatusServerTab     = ctx.Tab

    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local LocalPlayer         = ctx.LocalPlayer
    local TeleportService     = ctx.TeleportService
    local HttpService         = ctx.HttpService
    local UI                  = assert(ctx.UI, "Status_Server.lua needs ctx.UI: update MainWeb.lua / MainLocal.lua to the new core")
    local Players             = game:GetService("Players")
    local Stats               = game:GetService("Stats")
    local GuiService          = game:GetService("GuiService")
    local MarketplaceService  = game:GetService("MarketplaceService")
    local CoreGui             = ctx.CoreGui or game:GetService("CoreGui")

    local new                 = ctx.new
    local corner              = ctx.corner
    local stroke              = ctx.stroke
    local padding             = ctx.padding
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

    --// ---------- Lifecycle ----------
    -- Every connection that outlives this tab is tracked so it can be dropped when the UI is destroyed, or when the tab
    -- fails halfway through its setup (the loader then retries with a saved copy of this module).
    local alive = true
    local connections = {}

    local function track(conn)
        connections[#connections + 1] = conn
        return conn
    end

    local function shutdown()
        alive = false
        for _, conn in ipairs(connections) do
            pcall(conn.Disconnect, conn)
        end
        connections = {}
    end

    -- Shared toast from the core (ctx.Toast); an older core does not have it, so every call is optional
    local function toast(message, kind, opts)
        if type(ctx.Toast) ~= "function" then return end
        local ok, err = pcall(ctx.Toast, message, kind, opts)
        if not ok then warn("[Elysera/Status] Toast failed: " .. tostring(err)) end
    end

    --// ---------- Config ----------
    local SPAM_JOIN_DELAY  = 1.5  -- seconds between two Spam Join attempts (grows automatically after repeated errors)
    local PENDING_TIMEOUT  = 10   -- after this many seconds the previous teleport counts as finished/expired
    local HOP_WAIT_RESULT  = 6    -- wait at most this many seconds to see whether the teleport gets rejected
    local HOP_MAX_ATTEMPTS = 3    -- maximum number of servers to try per Hop
    local PAGE_DELAY       = 0.3  -- pause between API pages to avoid HTTP 429

    local BROWSER_PAGES    = 5    -- API pages scanned per Server Browser refresh (100 servers per page)
    local BROWSER_ROWS     = 12   -- server rows shown at first; "Show" adds this many again
    local BROWSER_ROWS_MAX = 60   -- never draw more rows than this
    local REJOIN_DELAY     = 3    -- seconds between a disconnect and the teleport (time to cancel)
    local REJOIN_WINDOW    = 600  -- automatic rejoins older than this many seconds are forgotten
    local REJOIN_MAX       = 4    -- maximum automatic rejoins inside that window (protects against ban loops)

    local ScriptStartTime = os.time() -- os.clock() is CPU time, not real time

    --// ---------- Utilities ----------
    local function formatTime(seconds)
        if type(seconds) ~= "number" then return "--" end
        seconds = math.max(0, math.floor(seconds))
        return string.format("%dh%dm%ds", seconds // 3600, seconds % 3600 // 60, seconds % 60)
    end

    -- Shared clipboard helper from the core UI kit (tries every executor's clipboard function); true when copied
    local copyToClipboard = UI.CopyText

    -- A Roblox JobId is always a GUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    local function isValidJobId(jobId)
        return type(jobId) == "string"
            and jobId:match("^%x+%-%x+%-%x+%-%x+%-%x+$") ~= nil
    end

    local function shortId(jobId)
        return type(jobId) == "string" and jobId:sub(1, 8) or "--"
    end

    -- One line of text, cut to `max` characters (UTF-8 safe) with "..." at the end
    local function shorten(text, max)
        text = (tostring(text):gsub("%s+", " "))
        if #text <= max then return text end
        local okCut, cut = pcall(utf8.offset, text, max - 2) -- errors on invalid UTF-8, so keep it in a pcall
        if not okCut then return text:sub(1, max - 3) .. "..." end
        if not cut then return text end -- fewer characters than bytes: it already fits
        return text:sub(1, cut - 1) .. "..."
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
    local lastFail        = { name = nil, at = 0 } -- why the newest teleport was rejected (Enum.TeleportResult name)

    -- Short texts that fit a 70px button
    local FAIL_TEXT = {
        GameFull = "Full", GameEnded = "Closed", GameNotFound = "Closed",
        Unauthorized = "Denied", Flooded = "Wait", IsTeleporting = "Busy", Failure = "Failed",
    }

    local function failText()
        local name = (os.time() - lastFail.at <= 20) and lastFail.name or nil
        return FAIL_TEXT[name] or "Failed"
    end

    local function markPending()
        teleportPending = true
        pendingToken += 1
        local token = pendingToken
        task.delay(PENDING_TIMEOUT, function()
            if pendingToken == token then teleportPending = false end
        end)
    end

    local function onTeleportFailed(player, result)
        if player ~= LocalPlayer then return end
        pendingToken += 1
        teleportPending = false
        failStreak += 1
        local okName, name = pcall(function() return result.Name end)
        lastFail.name = (okName and type(name) == "string") and name or nil
        lastFail.at = os.time()
    end

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

    --// ---------- Saved state: server history, small preferences, rejoin log ----------
    -- One file: { v = 2, history = {...}, prefs = { autoRejoin = bool, browserSort = string }, rejoinLog = { time, ... } }
    -- (a v1 file only had `history`; it loads fine and is upgraded on the next save)
    -- Every time Elysera runs on a server, record (place, JobId, time) so it is remembered after the teleport.
    local STATE_FILE, HISTORY_MAX = "Elysera_Servers.json", 10
    local history   = {} -- newest first: { place = number, id = string, t = os.time() }
    local prefs     = {}
    local rejoinLog = {} -- os.time() of every automatic rejoin (the newest ones; see REJOIN_WINDOW)

    local function loadState()
        if not canFS then return end
        local ok, data = pcall(function()
            local path = dataPath(STATE_FILE)
            if isfile(path) then return HttpService:JSONDecode(readfile(path)) end
        end)
        if not (ok and type(data) == "table") then return end

        if type(data.history) == "table" then
            for _, e in ipairs(data.history) do
                if type(e) == "table" and type(e.place) == "number" and isValidJobId(e.id) and type(e.t) == "number" then
                    history[#history + 1] = { place = e.place, id = e.id, t = e.t }
                    if #history >= HISTORY_MAX then break end
                end
            end
        end
        if type(data.prefs) == "table" then
            if type(data.prefs.autoRejoin) == "boolean" then prefs.autoRejoin = data.prefs.autoRejoin end
            if type(data.prefs.browserSort) == "string" then prefs.browserSort = data.prefs.browserSort end
        end
        if type(data.rejoinLog) == "table" then
            for _, t in ipairs(data.rejoinLog) do
                if type(t) == "number" then rejoinLog[#rejoinLog + 1] = t end
                if #rejoinLog >= 20 then break end
            end
        end
    end

    local function writeState()
        if not canFS then return end
        pcall(function()
            writefile(dataPath(STATE_FILE), HttpService:JSONEncode({
                v = 2, history = history, prefs = prefs, rejoinLog = rejoinLog,
            }))
        end)
    end

    local saveQueued = false
    local function persist() -- coalesces quick changes into one write
        if not canFS or saveQueued then return end
        saveQueued = true
        task.delay(0.3, function()
            saveQueued = false
            writeState()
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
        persist()
    end

    -- Forget every server except the one we are in
    local function clearHistory()
        for i = #history, 1, -1 do
            if history[i].id ~= game.JobId then table.remove(history, i) end
        end
        persist()
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
        if d < 3600 then return (d // 60) .. "m ago" end
        if d < 86400 then return (d // 3600) .. "h ago" end
        return (d // 86400) .. "d ago"
    end

    -- "Restore last session": a switch that was ON before a server change comes back ON.
    -- The core's ctx.Session (when present) owns the policy (the Settings switch); otherwise this module keeps its own copy.
    local function sessionWants(id)
        local Session = ctx.Session
        if type(Session) == "table" and type(Session.get) == "function" then
            local ok, value = pcall(Session.get, "status." .. id)
            return ok and value == true
        end
        return prefs[id] == true
    end

    local function sessionSave(id, on)
        on = on == true
        local Session = ctx.Session
        if type(Session) == "table" and type(Session.set) == "function" then
            pcall(Session.set, "status." .. id, on)
            return
        end
        prefs[id] = on
        persist()
    end

    loadState()
    recordCurrentServer()

    --// ---------- Server list API (shared by Server Hop and the Server Browser) ----------
    local ServerApi = {}
    do
        local failedJobIds = {} -- servers that were tried and rejected; never picked again

        local function httpFunction()
            return (syn and syn.request) or http_request or request
                or (http and http.request) or (fluxus and fluxus.request)
        end

        local function httpRequest(url)
            local fn = httpFunction()
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
        -- Returns list, lastErr (a partial list can come with an error such as "Limited")
        local function collectServers(sortOrder, maxPages, enough, accept)
            local list, cursor, lastErr = {}, "", nil

            for page = 1, maxPages do
                local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=%d&limit=100")
                    :format(game.PlaceId, sortOrder)
                if cursor ~= "" then url ..= "&cursor=" .. HttpService:UrlEncode(cursor) end

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
                        table.insert(list, srv)
                    end
                end

                if #list >= enough then break end

                cursor = data.nextPageCursor
                if type(cursor) ~= "string" or cursor == "" then break end
                if page < maxPages then task.wait(PAGE_DELAY) end
            end

            return list, lastErr
        end

        -- shuffle the first n elements of the list
        local function shuffle(list, n)
            for i = math.min(n, #list), 2, -1 do
                local j = math.random(1, i)
                list[i], list[j] = list[j], list[i]
            end
        end

        -- mode: "random" | "least" (fewest players) | "ping" (lowest ping)
        local function pickServers(mode)
            if mode == "ping" then
                -- The server list API returns the ping and fps of every server. Scan at most 5 pages (500 servers, most players
                -- first), skip servers without a ping and nearly full servers; on equal ping, prefer the higher fps.
                local list, err = collectServers(2, 5, 200, function(srv)
                    return type(srv.ping) == "number" and srv.ping > 0
                        and srv.playing <= math.max(0, srv.maxPlayers - 2)
                end)
                table.sort(list, function(a, b)
                    if a.ping ~= b.ping then return a.ping < b.ping end
                    return (type(a.fps) == "number" and a.fps or 0) > (type(b.fps) == "number" and b.fps or 0)
                end)
                return list, err
            end

            if mode == "least" then
                -- Asc: servers with few players are on the first pages. Skip servers with 0 players (they are usually about to close).
                local list, err = collectServers(1, 2, 20, function(srv)
                    return srv.playing >= 1
                end)
                table.sort(list, function(a, b) return a.playing < b.playing end)
                shuffle(list, 5) -- shuffle the 5 emptiest servers so many users do not collide
                return list, err
            end

            -- Random hop: avoid nearly full servers (they easily fail with GameFull)
            local list, err = collectServers(2, 5, 30, function(srv)
                return srv.playing <= math.max(0, srv.maxPlayers - 2)
            end)
            shuffle(list, #list)
            return list, err
        end

        -- Returns true while teleporting, or false + a short reason
        local function hopServer(mode)
            failedJobIds = {} -- every Hop press starts fresh: do not let the list of failed servers grow forever
            local candidates, err = pickServers(mode)
            if #candidates == 0 then return false, err or "No server" end

            local tried = 0
            for _, srv in ipairs(candidates) do
                if tried >= HOP_MAX_ATTEMPTS then break end
                tried += 1

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

        ServerApi.collect = collectServers
        ServerApi.hop = hopServer
        ServerApi.hasHttp = function() return httpFunction() ~= nil end
        ServerApi.markFailed = function(id) failedJobIds[id] = true end
        ServerApi.isFailed = function(id) return failedJobIds[id] == true end
    end

    --// ---------- Small UI helpers ----------
    -- Value text after the title of an info row (same look as the "Previous Server" age)
    local function valueLabel(Left, text)
        return label(Left, {
            LayoutOrder = 2,
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = text,
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.AccentPink,
        })
    end

    -- Collapsible group from the shared UI kit (a plain card when the core has no UI.CreateSection). Returns the Body frame
    local function makeSection(title, subtitle, order)
        if type(UI.CreateSection) == "function" then
            return UI.CreateSection(StatusServerTab, title, order, { subtitle = subtitle, collapsed = true }).Body
        end
        local Card = CreateCard(StatusServerTab, (title:gsub("%s", "")), 12, 14, 12)
        Card.LayoutOrder = order
        label(Card, {
            LayoutOrder = 0,
            Size = UDim2.new(1, 0, 0, 20),
            Text = title,
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Text,
        })
        return Card
    end

    -- A server row with two lines of text and a Join button. Returns Row, Line1, Line2, Button
    local function CreateServerRow(parent, order, line1, line2, buttonText)
        local Row = new("Frame", {
            LayoutOrder = order,
            Size = UDim2.new(1, 0, 0, 48),
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            ClipsDescendants = true,
        }, parent)
        corner(Row, 8)
        stroke(Row)
        padding(Row, 12, 10)

        local Info = new("Frame", {
            Size = UDim2.new(1, -72, 1, 0),
            BackgroundTransparency = 1,
        }, Row)
        local Line1 = label(Info, {
            Position = UDim2.fromOffset(0, 5),
            Size = UDim2.new(1, 0, 0, 20),
            Text = line1,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextColor3 = Theme.Text,
        })
        local Line2 = label(Info, {
            Position = UDim2.fromOffset(0, 25),
            Size = UDim2.new(1, 0, 0, 16),
            Text = line2,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextColor3 = Theme.SubText,
        })
        local Btn = CreateStyledButton(Row, buttonText, 60)
        return Row, Line1, Line2, Btn
    end

    -- Join button of a server row: Btn shows the progress; onRejected(jobId, text) runs when Roblox rejects the teleport
    local function joinFromList(Btn, jobId, placeId, onRejected)
        local ok, reason = joinServer(jobId, placeId)
        if not ok then
            flashButtonFeedback(Btn, "Join", reason or "Failed", true, 1.2)
            return
        end
        flashButtonFeedback(Btn, "Join", "Joining...", false, math.huge)
        toast("Joining server " .. shortId(jobId) .. "...", "info", { duration = 2 })
        task.spawn(function()
            -- A rejected teleport (full / closed server...) reports back through TeleportInitFailed, which clears teleportPending
            for _ = 1, math.ceil(HOP_WAIT_RESULT / 0.2) do
                if not teleportPending or not alive then break end
                task.wait(0.2)
            end
            if not alive or teleportPending then return end -- still teleporting: the script ends when it works
            local text = failText()
            flashButtonFeedback(Btn, "Join", text, true, 1.5)
            toast("Could not join: " .. text, "warn", { duration = 2.5 })
            if onRejected then onRejected(jobId, text) end
        end)
    end

    --// ---------- Build the tab ----------
    local function build()
        track(ScreenGui.Destroying:Connect(shutdown))
        track(TeleportService.TeleportInitFailed:Connect(onTeleportFailed))

        --// ---------- Continuously updating info rows ----------
        local liveRows, liveHooks = {}, {} -- rows: { Value, get }; hooks: functions that refresh other texts on the same loop

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
            for _, hook in ipairs(liveHooks) do pcall(hook) end
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

        -- A single loop for all live rows (instead of one loop per row).
        -- The loop only runs while the window and this tab are visible (nothing wakes up while hidden); reopening the UI / returning to this tab
        -- updates right away and restarts the loop.
        -- The loop condition uses the Visible property (it has a signal) rather than isOpen(): closing and reopening right while the UI is still
        -- fading out will not stop the loop for good.
        -- (An old core does not pass isOpen -> treated as always open, same behavior as before.)
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
            liveRun += 1
            local myRun = liveRun -- an old loop (if still alive) exits by itself on its next check
            task.spawn(function()
                while alive and ScreenGui.Parent and myRun == liveRun and windowVisible() do
                    if isOpen() then refreshLiveRows() end
                    task.wait(0.5)
                end
            end)
        end

        local function onVisibilityChanged()
            if tabShowing() then refreshLiveRows() end
            if windowVisible() then startLiveLoop() end
        end
        track(StatusServerTab:GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged))
        if MainUI then track(MainUI:GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged)) end
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
            local Switch, setSpamState = CreateToggleOption(Card, "Spam Join", 40)
            Switch.Parent.LayoutOrder = 4
            Switch.Parent.BackgroundColor3 = Theme.PanelAlt

            local runId = 0

            local function stopSpam()
                setSpamState(false)
            end

            Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
                runId += 1
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
                    while Switch:GetAttribute("Toggled") and myRun == runId and alive and ScreenGui.Parent do
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
        end

        CreateCopyRow(StatusServerTab, "Copy Server JobId", function() return game.JobId end, false)

        -- Link that opens this server directly (paste it into someone else's Join box, or open it in a browser with Roblox installed)
        CreateCopyRow(StatusServerTab, "Copy Join Link", function()
            if game.JobId == "" then return "" end
            return ("roblox://experiences/start?placeId=%d&gameInstanceId=%s"):format(game.PlaceId, game.JobId)
        end, false)

        --// ---------- Rejoin ----------
        do
            local Frame = CreateInfoRow(StatusServerTab, "Rejoin Server")
            local RejoinBtn = CreateStyledButton(Frame, "Rejoin", 70)
            RejoinBtn.Activated:Connect(guarded(function(done)
                local ok = false
                if not teleportPending then
                    ok = pcall(function()
                        if game.JobId == "" then
                            TeleportService:Teleport(game.PlaceId, LocalPlayer)
                        else
                            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                        end
                    end)
                    if ok then markPending() end
                end
                flashButtonFeedback(RejoinBtn, "Rejoin", ok and "Rejoining..." or "Failed", not ok)
                done()
            end))
        end

        --// ---------- Auto Rejoin ----------
        do
            local Switch, setState, api = CreateToggleOption(StatusServerTab, "Auto Rejoin", 50)
            if type(api) ~= "table" then
                -- a core without the api table: build the two functions this block needs from the Toggled attribute
                api = {
                    get = function() return Switch:GetAttribute("Toggled") == true end,
                    onChanged = function(fn)
                        return Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
                            fn(Switch:GetAttribute("Toggled") == true)
                        end)
                    end,
                }
            end

            -- Back ON after a server change when "Restore last session" says so (silent: only the visuals change, the
            -- handlers below read api.get() whenever a disconnect happens)
            if sessionWants("autoRejoin") then setState(true, true) end

            api.onChanged(function(on)
                sessionSave("autoRejoin", on)
                if not on then return end
                -- Elysera only keeps running after the rejoin when Auto Execute reloads it on the new server
                local AE = ctx.AutoExecute
                if type(AE) == "table" and type(AE.supported) == "function" and type(AE.isOn) == "function" then
                    local okAE, supported, isOn = pcall(function() return AE.supported(), AE.isOn() end)
                    if okAE and supported and not isOn then
                        toast("Tip: turn on Auto Execute in Settings so Elysera reloads after a rejoin", "info", { duration = 5 })
                    end
                end
            end)

            local rejoinBusy = false

            -- Error code name (Enum.ConnectionError) and message of the error prompt Roblox is showing, if any
            local function readDisconnect()
                local name, message
                pcall(function() name = GuiService:GetErrorCode().Name end)
                pcall(function() message = GuiService:GetErrorMessage() end)
                return type(name) == "string" and name or nil, type(message) == "string" and message or ""
            end

            local NO_REJOIN = { DisconnectDuplicatePlayer = true, DisconnectDuplicateTicket = true } -- the same account joined elsewhere

            -- Is this error prompt a kick / disconnect? (not a failed teleport, an empty "cleared" event, a ban...)
            local function shouldRejoin(name, message)
                local lowered = message:lower()
                if lowered:find("banned", 1, true) then return false end -- a ban cannot be fixed by rejoining
                if name then
                    if NO_REJOIN[name] then return false end
                    return name:sub(1, 10) == "Disconnect"
                end
                -- no error code available: judge by the text of the prompt
                return lowered:find("kick", 1, true) ~= nil
                    or lowered:find("disconnect", 1, true) ~= nil
                    or lowered:find("lost connection", 1, true) ~= nil
                    or lowered:find("shut down", 1, true) ~= nil
                    or lowered:find("shutdown", 1, true) ~= nil
            end

            local function describe(name, message)
                local kicked = name == "DisconnectLuaKick" or message:lower():find("kick", 1, true) ~= nil
                local what = kicked and "Kicked" or "Disconnected"
                if message ~= "" then return what .. ": " .. shorten(message, 80) end
                return what
            end

            -- One teleport try. Returns true when the teleport is under way (Roblox did not reject it within HOP_WAIT_RESULT seconds)
            local function attemptTeleport(sameServer)
                for _ = 1, math.ceil(PENDING_TIMEOUT / 0.2) do -- let a teleport that is already running settle first
                    if not teleportPending then break end
                    task.wait(0.2)
                end
                local ok = pcall(function()
                    if sameServer then
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                    else
                        TeleportService:Teleport(game.PlaceId, LocalPlayer)
                    end
                end)
                if not ok then return false end
                markPending()
                for _ = 1, math.ceil(HOP_WAIT_RESULT / 0.2) do
                    if not teleportPending or not alive then break end
                    task.wait(0.2)
                end
                return teleportPending
            end

            local function runRejoin(name, message)
                -- forget old attempts; too many recent ones (counted across servers) means something keeps kicking us
                local now = os.time()
                local recent = {}
                for _, t in ipairs(rejoinLog) do
                    if type(t) == "number" and t <= now and now - t < REJOIN_WINDOW then recent[#recent + 1] = t end
                end
                rejoinLog = recent
                if #recent >= REJOIN_MAX then
                    toast(("Auto Rejoin paused: %d rejoins in the last %d minutes"):format(#recent, REJOIN_WINDOW // 60),
                        "error", { duration = 6 })
                    return
                end

                -- countdown: Cancel on the toast, or turning the switch off, stops it
                local cancelled = false
                toast(describe(name, message) .. ". Rejoining in " .. REJOIN_DELAY .. "s...", "warn", {
                    duration = REJOIN_DELAY,
                    actionText = "Cancel",
                    onAction = function() cancelled = true end,
                })
                for _ = 1, REJOIN_DELAY * 4 do
                    task.wait(0.25)
                    if cancelled or not alive or not api.get() then return end
                end

                recent[#recent + 1] = os.time()
                writeState() -- saved before leaving: the next server has to see this attempt

                -- The first rejoin goes back to this server. When we were kicked again soon, or the old server is gone, take a fresh one
                local sameServer = #recent == 1 and isValidJobId(game.JobId)
                local started = attemptTeleport(sameServer)
                if not started and sameServer and alive and api.get() then
                    toast("The old server is not available. Joining a new one...", "info", { duration = 3 })
                    started = attemptTeleport(false)
                end
                if not started then
                    toast("Auto Rejoin could not teleport. Try Rejoin Server or Server Hop", "error", { duration = 5 })
                end
            end

            -- promptText: text read from the error prompt itself (used when GuiService has no message)
            local function onDisconnect(promptText)
                if rejoinBusy or not alive or not api.get() then return end
                local name, message = readDisconnect()
                if name == "OK" then name = nil end -- "OK" = GuiService has no error right now
                if message == "" and type(promptText) == "string" then message = promptText end
                if name == nil and message == "" then return end
                if not shouldRejoin(name, message) then return end

                rejoinBusy = true
                task.spawn(function()
                    local ok, err = pcall(runRejoin, name, message)
                    if not ok then warn("[Elysera] Auto Rejoin: " .. tostring(err)) end
                    task.wait(10) -- stay busy a while longer: a teleport that works ends this script, a failed one must not start twice
                    rejoinBusy = false
                end)
            end

            -- Two sources, whichever the executor allows: GuiService fires when Roblox sets the error message ...
            pcall(function()
                track(GuiService.ErrorMessageChanged:Connect(function() onDisconnect(nil) end))
            end)
            -- ... and the error prompt that Roblox adds to CoreGui
            task.spawn(function()
                local overlay
                pcall(function()
                    local promptGui = CoreGui:WaitForChild("RobloxPromptGui", 10)
                    overlay = promptGui and promptGui:WaitForChild("promptOverlay", 10)
                end)
                if not overlay or not alive then return end
                track(overlay.ChildAdded:Connect(function(child)
                    if child.Name ~= "ErrorPrompt" then return end
                    local text
                    pcall(function() text = child.MessageArea.ErrorFrame.ErrorMessage.Text end)
                    task.wait(0.2) -- let GuiService fill in the error code first
                    onDisconnect(text)
                end))
            end)
        end

        --// ---------- Previous Server ----------
        do
            local Frame, Left = CreateInfoRow(StatusServerTab, "Previous Server")
            local AgoLabel = valueLabel(Left, "")
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
        end

        --// ---------- Server Hop ----------
        do
            local function bindHopButton(title, mode)
                local Frame = CreateInfoRow(StatusServerTab, title)
                local Btn = CreateStyledButton(Frame, "Hop", 70)
                Btn.Activated:Connect(guarded(function(done)
                    flashButtonFeedback(Btn, "Hop", "Finding...", false, math.huge, Theme.SubText)
                    task.spawn(function()
                        local ok, result, reason = pcall(ServerApi.hop, mode)
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
        end

        --// ---------- Server Browser ----------
        -- Lists public servers of this game with players, ping and FPS (from the same server list API as Server Hop).
        -- Nothing is requested until the section is opened for the first time (or Refresh is pressed).
        do
            local Body = makeSection("Server Browser", "Pick a server by ping, FPS or player count", 1000)

            -- order = sortOrder of the server list API: 1 = fewest players first, 2 = most players first. "Fewest" needs the
            -- other end of the list, so changing to it loads again; the other three sort what is already loaded.
            local SORTS = {
                { key = "ping",   text = "Ping",   order = 2 },
                { key = "fps",    text = "FPS",    order = 2 },
                { key = "fewest", text = "Fewest", order = 1 },
                { key = "most",   text = "Most",   order = 2 },
            }
            local sortAt = 1
            for i, s in ipairs(SORTS) do
                if s.key == prefs.browserSort then sortAt = i end
            end

            local function finite(v)
                return type(v) == "number" and v == v and math.abs(v) < 1e6
            end
            local function pingOf(s) return (finite(s.ping) and s.ping > 0) and s.ping or math.huge end
            local function fpsOf(s) return finite(s.fps) and s.fps or 0 end

            -- Every comparator ends with the id so the order is total (table.sort rejects inconsistent comparators)
            local COMPARE = {
                ping = function(a, b)
                    if pingOf(a) ~= pingOf(b) then return pingOf(a) < pingOf(b) end
                    if fpsOf(a) ~= fpsOf(b) then return fpsOf(a) > fpsOf(b) end
                    return a.id < b.id
                end,
                fps = function(a, b)
                    if fpsOf(a) ~= fpsOf(b) then return fpsOf(a) > fpsOf(b) end
                    if pingOf(a) ~= pingOf(b) then return pingOf(a) < pingOf(b) end
                    return a.id < b.id
                end,
                fewest = function(a, b)
                    if a.playing ~= b.playing then return a.playing < b.playing end
                    if pingOf(a) ~= pingOf(b) then return pingOf(a) < pingOf(b) end
                    return a.id < b.id
                end,
                most = function(a, b)
                    if a.playing ~= b.playing then return a.playing > b.playing end
                    if pingOf(a) ~= pingOf(b) then return pingOf(a) < pingOf(b) end
                    return a.id < b.id
                end,
            }

            local SortFrame, SortLeft = CreateInfoRow(Body, "Sort by", 40)
            SortFrame.LayoutOrder = 1
            local SortValue = valueLabel(SortLeft, SORTS[sortAt].text)
            local SortBtn = CreateStyledButton(SortFrame, "Change", 70)

            local ListFrame, ListLeft = CreateInfoRow(Body, "Servers", 40)
            ListFrame.LayoutOrder = 2
            local StatusValue = valueLabel(ListLeft, "Not loaded")
            local RefreshBtn = CreateStyledButton(ListFrame, "Refresh", 70)

            local MoreFrame, MoreLeft = CreateInfoRow(Body, "More servers", 40)
            MoreFrame.LayoutOrder = 5000
            MoreFrame.Visible = false
            local MoreValue = valueLabel(MoreLeft, "")
            local MoreBtn = CreateStyledButton(MoreFrame, "Show", 70)

            local function setStatus(text, isError)
                StatusValue.Text = text
                StatusValue.TextColor3 = isError and Theme.Danger or Theme.AccentPink
            end

            local browser = { list = {}, loaded = false, loading = false, shown = BROWSER_ROWS, order = nil, coolUntil = 0 }
            local rows = {}
            local render -- declared first: the Join buttons of the rows call it

            local function buildRow(srv, i)
                local line1 = ("%d/%d players"):format(math.floor(srv.playing), math.floor(srv.maxPlayers))
                if finite(srv.ping) and srv.ping > 0 then
                    line1 = line1 .. (" - %d ms"):format(math.floor(srv.ping + 0.5))
                end
                local line2 = shortId(srv.id)
                if fpsOf(srv) > 0 then
                    line2 = ("%d fps - %s"):format(math.floor(fpsOf(srv) + 0.5), line2)
                end

                local Row, _, _, Btn = CreateServerRow(Body, 100 + i, line1, line2, "Join")
                Btn.Activated:Connect(function()
                    if isLocked() then return end
                    joinFromList(Btn, srv.id, nil, function(id, text)
                        if text == "Full" or text == "Closed" or text == "Denied" then
                            ServerApi.markFailed(id) -- never offered again until the next Hop / refresh
                            task.delay(1.5, function()
                                if alive then render() end
                            end)
                        end
                    end)
                end)
                return Row
            end

            -- Draws the loaded list in the chosen order. Returns how many servers can be shown
            render = function()
                for _, r in ipairs(rows) do r:Destroy() end
                rows = {}

                local view = {}
                for _, srv in ipairs(browser.list) do
                    if not ServerApi.isFailed(srv.id) then view[#view + 1] = srv end
                end
                table.sort(view, COMPARE[SORTS[sortAt].key])

                local count = math.min(#view, browser.shown)
                for i = 1, count do rows[#rows + 1] = buildRow(view[i], i) end

                MoreFrame.Visible = #view > count and count < BROWSER_ROWS_MAX
                MoreValue.Text = count .. "/" .. #view
                return #view
            end

            local function refresh()
                if browser.loading then return end
                if os.time() < browser.coolUntil then
                    flashButtonFeedback(RefreshBtn, "Refresh", "Wait", true, 0.8)
                    return
                end
                if not ServerApi.hasHttp() then
                    setStatus("No HTTP", true)
                    flashButtonFeedback(RefreshBtn, "Refresh", "No HTTP", true, 1.2)
                    return
                end

                browser.loading = true
                setStatus("Loading...", false)
                flashButtonFeedback(RefreshBtn, "Refresh", "Loading...", false, math.huge, Theme.SubText)
                local sort = SORTS[sortAt]
                task.spawn(function()
                    local ok, list, err = pcall(ServerApi.collect, sort.order, BROWSER_PAGES, BROWSER_PAGES * 100, function(srv)
                        return srv.playing >= 1 -- an empty server is usually about to close
                    end)
                    browser.loading = false
                    browser.coolUntil = os.time() + 2
                    if not alive then return end
                    if not ok then list, err = {}, "Failed" end

                    browser.list, browser.order, browser.loaded, browser.shown = list, sort.order, true, BROWSER_ROWS
                    local total = render()
                    if total == 0 then
                        setStatus(err or "None found", err ~= nil)
                    elseif err then
                        setStatus(total .. " (partial)", false)
                    else
                        setStatus(total .. " found", false)
                    end
                    flashButtonFeedback(RefreshBtn, "Refresh", err and "Partial" or "Done", err ~= nil and total == 0, 0.8)
                end)
            end

            SortBtn.Activated:Connect(function()
                if isLocked() then return end
                sortAt = sortAt % #SORTS + 1
                local sort = SORTS[sortAt]
                SortValue.Text = sort.text
                prefs.browserSort = sort.key
                persist()
                if browser.loaded then
                    browser.shown = BROWSER_ROWS
                    render()
                    if browser.order ~= sort.order then refresh() end
                end
            end)

            RefreshBtn.Activated:Connect(function()
                if isLocked() then return end
                refresh()
            end)

            MoreBtn.Activated:Connect(function()
                if isLocked() then return end
                browser.shown = math.min(browser.shown + BROWSER_ROWS, BROWSER_ROWS_MAX)
                render()
            end)

            -- First time the section is opened: load the list
            track(Body:GetPropertyChangedSignal("Visible"):Connect(function()
                if Body.Visible and not browser.loaded and not browser.loading then refresh() end
            end))
        end

        --// ---------- Recent Servers ----------
        -- The history file keeps the last 10 servers Elysera ran on (needs Auto Execute to keep recording after a teleport)
        do
            local Body = makeSection("Recent Servers", "The last servers Elysera ran on", 1001)
            local rows = {}
            local placeNames = {} -- [placeId] = game name, looked up once for places other than this one

            local function placeText(placeId)
                if placeId == game.PlaceId then return "This game" end
                return placeNames[placeId] or ("Place " .. tostring(placeId))
            end

            local function lineText(entry)
                if entry.id == game.JobId then return "This server - joined " .. formatAgo(entry.t) end
                return placeText(entry.place) .. " - " .. formatAgo(entry.t)
            end

            local function refreshTexts()
                for _, r in ipairs(rows) do r.Line1.Text = lineText(r.entry) end
            end

            local EmptyFrame = CreateInfoRow(Body, "No servers recorded yet", 40)
            EmptyFrame.LayoutOrder = 99

            local ClearFrame = CreateInfoRow(Body, "Clear history", 40)
            ClearFrame.LayoutOrder = 5000
            local ClearBtn = CreateStyledButton(ClearFrame, "Clear", 70)

            local function render()
                for _, r in ipairs(rows) do r.Row:Destroy() end
                rows = {}
                for i, entry in ipairs(history) do
                    local Row, Line1, _, Btn = CreateServerRow(Body, 100 + i, lineText(entry), shortId(entry.id), "Join")
                    if entry.id == game.JobId then
                        Btn.Visible = false -- this is where we are
                    else
                        Btn.Activated:Connect(function()
                            if isLocked() then return end
                            joinFromList(Btn, entry.id, entry.place, nil)
                        end)
                    end
                    rows[#rows + 1] = { Row = Row, Line1 = Line1, entry = entry }
                end
                EmptyFrame.Visible = #history == 0
            end
            render()

            -- "x ago" follows the same live loop as the rows at the top (only while the section is open)
            table.insert(liveHooks, function()
                if Body.Visible then refreshTexts() end
            end)

            -- First tap arms the button, a second tap within 2.5 seconds clears the history
            local armedToken = 0
            ClearBtn.Activated:Connect(function()
                if isLocked() then return end
                if not ClearBtn:GetAttribute("Armed") then
                    ClearBtn:SetAttribute("Armed", true)
                    armedToken += 1
                    local token = armedToken
                    flashButtonFeedback(ClearBtn, "Clear", "Sure?", true, 2.5)
                    task.delay(2.5, function()
                        if armedToken == token then ClearBtn:SetAttribute("Armed", false) end
                    end)
                    return
                end
                ClearBtn:SetAttribute("Armed", false)
                armedToken += 1
                clearHistory()
                render()
                flashButtonFeedback(ClearBtn, "Clear", "Cleared", false)
            end)

            -- Game names for the places of other servers in the list (one request per place, a little apart)
            task.spawn(function()
                local seen = {}
                for _, entry in ipairs(history) do
                    if not alive then return end
                    local p = entry.place
                    if p ~= game.PlaceId and not placeNames[p] and not seen[p] then
                        seen[p] = true
                        local ok, info = pcall(function() return MarketplaceService:GetProductInfo(p) end)
                        if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
                            placeNames[p] = shorten(info.Name, 40)
                            if alive then refreshTexts() end
                        end
                        task.wait(0.3)
                    end
                end
            end)
        end
    end

    local okBuild, errBuild = pcall(build)
    if not okBuild then
        shutdown() -- drop everything that was connected, then let the loader know (it retries with the saved copy)
        error(errBuild, 0)
    end
end
