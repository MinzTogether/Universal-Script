--// ================= STATUS & SERVER TAB (module) =================
-- File này được script chính (MainLocal.lua / MainWeb.lua) nạp vào và gọi với 1 bảng ctx
-- chứa các hàm/biến dùng chung của UI.
--
-- Công cụ server:
--   * Join JobId   : ô nhập nhận JobId trần hoặc link có gameInstanceId (roblox://..., https://www.roblox.com/games/...)
--   * Copy Join Link, Rejoin Server
--   * Previous Server : quay lại server gần nhất đã có Elysera chạy (lịch sử lưu trong Elysera_Servers.json;
--                       bật Auto Execute ở Settings để Elysera tự chạy lại và ghi tiếp sau mỗi lần teleport)
--   * Server Hop / Less People / Best Ping (ping và fps do API danh sách server trả kèm)

return function(ctx)
    local StatusServerTab     = ctx.Tab

    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local LocalPlayer         = ctx.LocalPlayer
    local TeleportService     = ctx.TeleportService
    local HttpService         = ctx.HttpService
    local Players             = game:GetService("Players")
    local Stats               = game:GetService("Stats")

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
    local isLocked            = ctx.isLocked -- thay cho biến uiLocked của file chính
    local canFS               = ctx.canFS == true
    local dataPath            = ctx.dataPath or function(name) return name end

    --// ---------- Cấu hình ----------
    local SPAM_JOIN_DELAY  = 1.5  -- giây giữa 2 lần Spam Join (tự tăng khi bị lỗi liên tiếp)
    local PENDING_TIMEOUT  = 10   -- sau bấy nhiêu giây coi như teleport trước đó đã xong/hết hạn
    local HOP_WAIT_RESULT  = 6    -- chờ tối đa bấy nhiêu giây xem teleport có bị từ chối không
    local HOP_MAX_ATTEMPTS = 3    -- số server thử tối đa cho mỗi lần Hop
    local PAGE_DELAY       = 0.3  -- nghỉ giữa các trang API để tránh 429

    local ScriptStartTime = os.time() -- os.clock() là CPU time, không phải thời gian thực

    --// ---------- Tiện ích ----------
    local function formatTime(seconds)
        if type(seconds) ~= "number" then return "--" end
        seconds = math.max(0, math.floor(seconds))
        return string.format("%dh%dm%ds", seconds // 3600, seconds % 3600 // 60, seconds % 60)
    end

    local function copyToClipboard(text)
        local fn = setclipboard or toclipboard or set_clipboard
            or (Clipboard and Clipboard.set)
            or (syn and syn.write_clipboard)
        if not fn then return false end
        return (pcall(fn, text))
    end

    -- JobId của Roblox luôn có dạng GUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    local function isValidJobId(jobId)
        return type(jobId) == "string"
            and jobId:match("^%x+%-%x+%-%x+%-%x+%-%x+$") ~= nil
    end

    -- Ô Join chấp nhận JobId trần hoặc link có gameInstanceId:
    --   roblox://experiences/start?placeId=123&gameInstanceId=<JobId>
    --   https://www.roblox.com/games/start?placeId=123&gameInstanceId=<JobId>
    --   https://www.roblox.com/games/123/Ten-Game?gameInstanceId=<JobId>   (cả dạng đã mã hoá %3D, %26...)
    -- Trả về jobId, placeId (nil nếu link không nêu), hoặc nil, nil, lý do ("Invalid" | "Private")
    local function parseJoinInput(raw)
        if type(raw) ~= "string" then return nil, nil, "Invalid" end
        local text = raw:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
        text = text:gsub("[%s\"']", ""):lower()
        if text == "" then return nil, nil, "Invalid" end
        if isValidJobId(text) then return text, nil end
        -- link server riêng tư đi bằng mã, không có JobId để teleport trực tiếp
        if text:find("privateserverlinkcode=", 1, true) then return nil, nil, "Private" end

        local jobId = text:match("gameinstanceid=([%x%-]+)")
        if not isValidJobId(jobId) then return nil, nil, "Invalid" end
        local placeId = text:match("placeid=(%d+)") or text:match("/games/(%d+)")
        return jobId, tonumber(placeId)
    end

    --// ---------- Trạng thái teleport dùng chung ----------
    -- teleportPending = true khi vừa gọi teleport và chưa biết kết quả.
    -- Nếu thành công, client sẽ rời server (script dừng); nếu thất bại,
    -- TeleportInitFailed sẽ báo về và ta mở khoá lại.
    local teleportPending = false
    local pendingToken    = 0
    local failStreak      = 0

    local function markPending()
        teleportPending = true
        pendingToken += 1
        local token = pendingToken
        task.delay(PENDING_TIMEOUT, function()
            if pendingToken == token then teleportPending = false end
        end)
    end

    local failedConn = TeleportService.TeleportInitFailed:Connect(function(player)
        if player ~= LocalPlayer then return end
        pendingToken += 1
        teleportPending = false
        failStreak += 1
    end)

    ScreenGui.Destroying:Connect(function()
        failedConn:Disconnect()
    end)

    -- Trả về ok, lý do (ngắn, vừa nút 70px). placeId = nil: dùng place hiện tại
    local function joinServer(jobId, placeId)
        if not isValidJobId(jobId) then return false, "Invalid" end
        if jobId == game.JobId then return false, "Same" end
        if teleportPending then return false, "Busy" end
        local ok = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, placeId or game.PlaceId, jobId, LocalPlayer)
        if not ok then return false, "Failed" end
        markPending()
        return true
    end

    --// ---------- Lịch sử server (cho "Previous Server") ----------
    -- Mỗi lần Elysera chạy ở một server thì ghi lại (place, JobId, thời điểm) vào file để còn nhớ sau khi teleport.
    local HISTORY_FILE, HISTORY_MAX = "Elysera_Servers.json", 10
    local history = {} -- mới nhất trước: { place = number, id = string, t = os.time() }

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
            if history[i].id == id then table.remove(history, i) end -- một bản ghi / server, đưa lên đầu
        end
        table.insert(history, 1, { place = game.PlaceId, id = id, t = os.time() })
        while #history > HISTORY_MAX do table.remove(history) end
        saveHistory()
    end

    -- Server gần nhất của game này mà không phải server hiện tại
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

    loadHistory()
    recordCurrentServer()

    --// ---------- Các dòng thông tin cập nhật liên tục ----------
    local liveRows = {}

    local function CreateLiveRow(parent, title, getText)
        local Frame = CreateInfoRow(parent, title)

        -- Value chiếm 110px bên phải; thu hẹp Left (mặc định -90) để title không chồng lên Value
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

    -- time() = số giây kể từ khi client vào server này (reset khi teleport sang server khác)
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

    -- 1 vòng lặp duy nhất cho tất cả các dòng live (thay vì mỗi dòng 1 vòng).
    -- Chỉ cập nhật khi UI đang mở và tab này đang hiện; mở lại UI / quay về tab này thì cập nhật ngay.
    -- (Core cũ không truyền isOpen -> coi như luôn mở, hành vi như trước.)
    local isOpen = ctx.isOpen or function() return true end
    local function tabShowing()
        return isOpen() and StatusServerTab.Visible
    end
    task.spawn(function()
        while ScreenGui.Parent do
            if tabShowing() then refreshLiveRows() end
            task.wait(0.5)
        end
    end)
    StatusServerTab:GetPropertyChangedSignal("Visible"):Connect(function()
        if tabShowing() then refreshLiveRows() end
    end)
    if ctx.MainUI then
        ctx.MainUI:GetPropertyChangedSignal("Visible"):Connect(function()
            if tabShowing() then refreshLiveRows() end
        end)
    end

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

        -- Trả về jobId, placeId, lý do (xem parseJoinInput); ô rỗng -> nil, nil, "Empty"
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

            -- JobId rỗng / sai / trùng server hiện tại: báo lỗi và tự tắt, không chạy vòng lặp vô ích
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
                        joinServer(jobId, placeId) -- tự bỏ qua nếu teleport trước đó chưa có kết quả
                    end

                    -- lỗi liên tiếp thì giãn dần để khỏi bị Roblox giới hạn
                    task.wait(SPAM_JOIN_DELAY + math.min(failStreak, 5) * 0.5)
                end
            end)
        end)
    end

    CreateCopyRow(StatusServerTab, "Copy Server JobId", function() return game.JobId end, false)

    -- Link mở thẳng server này (dán vào ô Join của người khác, hoặc mở bằng trình duyệt có cài Roblox)
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

    --// ---------- Previous Server ----------
    do
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
        table.insert(liveRows, { Value = AgoLabel, get = describe }) -- "x ago" cập nhật cùng vòng lặp live

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
        local failedJobIds = {} -- server đã thử mà bị từ chối, không chọn lại

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

        -- sortOrder: 1 = ít người trước (Asc), 2 = đông người trước (Desc)
        -- Dừng sớm khi đã đủ `enough` ứng viên để bớt request.
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

        -- xáo trộn n phần tử đầu của list
        local function shuffle(list, n)
            for i = math.min(n, #list), 2, -1 do
                local j = math.random(1, i)
                list[i], list[j] = list[j], list[i]
            end
        end

        -- mode: "random" | "least" (ít người) | "ping" (ping thấp nhất)
        local function pickServers(mode)
            if mode == "ping" then
                -- API danh sách server trả kèm ping và fps của từng server. Dò tối đa 5 trang (500 server, đông người
                -- trước), bỏ server chưa có ping và server gần đầy; ping bằng nhau thì ưu tiên fps cao hơn.
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
                -- Asc: server ít người nằm ở các trang đầu. Bỏ server 0 người (thường sắp đóng).
                local list, err = collectServers(1, 2, 20, function(srv)
                    return srv.playing >= 1
                end)
                table.sort(list, function(a, b) return a.playing < b.playing end)
                shuffle(list, 5) -- xáo 5 server ít người nhất để nhiều người dùng khỏi đụng nhau
                return list, err
            end

            -- Hop ngẫu nhiên: tránh server gần đầy (dễ bị GameFull)
            local list, err = collectServers(2, 5, 30, function(srv)
                return srv.playing <= math.max(0, srv.maxPlayers - 2)
            end)
            shuffle(list, #list)
            return list, err
        end

        -- Trả về true nếu đang teleport, hoặc false + lý do ngắn
        local function hopServer(mode)
            failedJobIds = {} -- mỗi lần bấm Hop là một lần mới: không để danh sách server lỗi tích tụ vô hạn
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
                    -- chờ xem Roblox có từ chối không (server đầy / đã đóng...)
                    for _ = 1, math.ceil(HOP_WAIT_RESULT / 0.2) do
                        if not teleportPending then break end
                        task.wait(0.2)
                    end
                    if teleportPending then return true end -- vẫn đang teleport: coi như thành công
                    failedJobIds[srv.id] = true             -- bị từ chối: thử server kế tiếp
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
    end
end
