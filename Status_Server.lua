--// ================= STATUS & SERVER TAB (module) =================
-- File này được script chính (test.lua) nạp vào và gọi với 1 bảng ctx
-- chứa các hàm/biến dùng chung của UI.

return function(ctx)
    local StatusServerTab     = ctx.Tab

    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local LocalPlayer         = ctx.LocalPlayer
    local TeleportService     = ctx.TeleportService
    local HttpService         = ctx.HttpService

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

    local ScriptStartClock = os.clock()

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

    local function joinServer(jobId)
        if not jobId or jobId == "" or jobId == game.JobId then return false end
        return (pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, jobId, LocalPlayer))
    end

    local function CreateTimerRow(parent, title, getSeconds)
        local Frame = CreateInfoRow(parent, title)

        local Value = label(Frame, {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(110, 24),
            Text = formatTime(getSeconds()),
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextColor3 = Theme.AccentPink,
        })

        task.spawn(function()
            while ScreenGui.Parent do
                local ok, secs = pcall(getSeconds)
                if ok then
                    local txt = formatTime(secs)
                    if Value.Text ~= txt then Value.Text = txt end
                end
                task.wait(0.25)
            end
        end)

        return Frame
    end

    local function CreateCopyRow(parent, title, text, valueLabel)
        local Frame, Left = CreateInfoRow(parent, title)

        if valueLabel then
            label(Left, {
                LayoutOrder = 2,
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = text,
                TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = Theme.AccentPink,
            })
        end

        local Btn = CreateStyledButton(Frame, "Copy", 70)
        Btn.Activated:Connect(guarded(function(done)
            local ok = copyToClipboard(text)
            flashButtonFeedback(Btn, "Copy", ok and "Copied!" or "Failed", not ok)
            done()
        end))
        return Frame
    end

    CreateTimerRow(StatusServerTab, "Timer", function()
        return os.clock() - ScriptStartClock
    end)

    -- time() = số giây kể từ khi client vào server này (reset khi teleport sang server khác)
    CreateTimerRow(StatusServerTab, "Time Played", function()
        return time()
    end)

    CreateCopyRow(StatusServerTab, "PlaceID", tostring(game.PlaceId), true)

    do
        local SPAM_JOIN_DELAY = 0.25

        local Card = CreateCard(StatusServerTab, "ServerHoper", 12, 14, 12)

        label(Card, {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 20),
            Text = "Server Hoper",
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
            Text = "Paste your JobId here",
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

        local function getJobId()
            return (Box.Text:gsub("[%s\"']", ""))
        end

        local JoinFrame = CreateInfoRow(Card, "Join JobId", 40)
        JoinFrame.LayoutOrder = 3
        JoinFrame.BackgroundColor3 = Theme.PanelAlt

        local JoinBtn = CreateStyledButton(JoinFrame, "Join", 70)
        local joinBusy = false
        JoinBtn.Activated:Connect(function()
            if isLocked() or joinBusy then return end
            local jobId = getJobId()
            if jobId == "" or jobId == game.JobId then
                flashStrokeError(BoxStroke)
                flashButtonFeedback(JoinBtn, "Join", jobId == "" and "Empty" or "Same", true, 0.8)
                return
            end
            joinBusy = true
            local ok = joinServer(jobId)
            flashButtonFeedback(JoinBtn, "Join", ok and "Joining..." or "Failed", not ok)
            task.delay(1.2, function() joinBusy = false end)
        end)

        local Switch = CreateToggleOption(Card, "Spam Join", 40)
        Switch.Parent.LayoutOrder = 4
        Switch.Parent.BackgroundColor3 = Theme.PanelAlt

        local runId = 0
        Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
            runId += 1
            if not Switch:GetAttribute("Toggled") then return end

            if getJobId() == "" then flashStrokeError(BoxStroke) end
            local myRun = runId
            task.spawn(function()
                while Switch:GetAttribute("Toggled") and myRun == runId and ScreenGui.Parent do
                    joinServer(getJobId())
                    task.wait(SPAM_JOIN_DELAY)
                end
            end)
        end)
    end

    CreateCopyRow(StatusServerTab, "Copy Server JobId", game.JobId, false)

    do
        local Frame = CreateInfoRow(StatusServerTab, "Rejoin Server")
        local RejoinBtn = CreateStyledButton(Frame, "Rejoin", 70)
        RejoinBtn.Activated:Connect(guarded(function(done)
            local ok = pcall(function()
                if game.JobId == "" then
                    TeleportService:Teleport(game.PlaceId, LocalPlayer)
                else
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
                end
            end)
            flashButtonFeedback(RejoinBtn, "Rejoin", ok and "Rejoining..." or "Failed", not ok)
            done()
        end))
    end

    do
        local function httpRequest(url)
            local fn = (syn and syn.request) or http_request or request
                or (http and http.request) or (fluxus and fluxus.request)
            if not fn then return nil, "no http function" end
            local ok, res = pcall(fn, { Url = url, Method = "GET" })
            if not ok then return nil, res end
            if type(res) == "table" and type(res.Body) == "string" then
                return res.Body
            end
            return nil, "bad response"
        end

        local function fetchPublicServers()
            local servers, cursor = {}, ""
            for _ = 1, 5 do
                local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=2&limit=100"):format(game.PlaceId)
                if cursor ~= "" then url ..= "&cursor=" .. HttpService:UrlEncode(cursor) end

                local body = httpRequest(url)
                if not body then break end

                local ok, data = pcall(HttpService.JSONDecode, HttpService, body)
                if not ok or type(data) ~= "table" or type(data.data) ~= "table" then break end

                for _, srv in ipairs(data.data) do
                    table.insert(servers, srv)
                end

                if data.nextPageCursor and data.nextPageCursor ~= "" then
                    cursor = data.nextPageCursor
                else
                    break
                end
            end
            return servers
        end

        local function pickServerJobId(pickLeast)
            local candidates = {}
            for _, srv in ipairs(fetchPublicServers()) do
                if srv.id and srv.id ~= game.JobId
                    and type(srv.playing) == "number" and type(srv.maxPlayers) == "number"
                    and srv.playing < srv.maxPlayers then
                    table.insert(candidates, srv)
                end
            end
            if #candidates == 0 then return nil end

            if pickLeast then
                table.sort(candidates, function(a, b) return a.playing < b.playing end)
                return candidates[1].id
            end
            return candidates[math.random(1, #candidates)].id
        end

        local function bindHopButton(title, pickLeast)
            local Frame = CreateInfoRow(StatusServerTab, title)
            local Btn = CreateStyledButton(Frame, "Hop", 70)
            Btn.Activated:Connect(guarded(function(done)
                Btn.Text, Btn.TextColor3 = "Finding...", Theme.SubText
                task.spawn(function()
                    local ok, jobId = pcall(pickServerJobId, pickLeast)
                    if ok and jobId then
                        joinServer(jobId)
                        flashButtonFeedback(Btn, "Hop", "Hopping...", false)
                    else
                        flashButtonFeedback(Btn, "Hop", "Failed", true)
                    end
                    done()
                end)
            end))
        end

        bindHopButton("Server Hop", false)
        bindHopButton("Server Hop With Less People", true)
    end
end
