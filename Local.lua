--// ================= LOCAL TAB (module) =================
-- File này được script chính (test.lua) nạp vào và gọi với 1 bảng ctx
-- chứa các hàm/biến dùng chung của UI.

return function(ctx)
    local LocalTab            = ctx.Tab

    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local LocalPlayer         = ctx.LocalPlayer

    local Players             = ctx.Players
    local RunService          = ctx.RunService
    local UserInputService    = ctx.UserInputService
    local Workspace           = ctx.Workspace
    local CoreGui             = ctx.CoreGui

    local new                 = ctx.new
    local corner              = ctx.corner
    local stroke              = ctx.stroke
    local padding             = ctx.padding
    local list                = ctx.list

    local CreateCard          = ctx.CreateCard
    local CreateToggleOption  = ctx.CreateToggleOption
    local flashStrokeError    = ctx.flashStrokeError
    local bindBoxFocus        = ctx.bindBoxFocus

    local LocalCleanups = {}
    ScreenGui.Destroying:Connect(function()
        for _, fn in ipairs(LocalCleanups) do pcall(fn) end
    end)

    local function getHumanoid()
        local c = LocalPlayer.Character
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    local function getRoot()
        local c = LocalPlayer.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    local function sanitizeNumber(s)
        s = s:gsub("[^%d%.]", "")
        local dot = s:find(".", 1, true)
        if dot then
            s = s:sub(1, dot) .. (s:sub(dot + 1):gsub("%.", ""))
        end
        return s:sub(1, 7)
    end

    local function readNumber(Box, maxValue)
        local n = tonumber(Box.Text)
        return n and math.clamp(n, 0, maxValue) or nil
    end

    local function BindToggle(Switch, onFn, offFn)
        Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
            if Switch:GetAttribute("Toggled") then onFn() else offFn() end
        end)
        table.insert(LocalCleanups, offFn)
    end

    local function CreateToggleWithBox(parent, title, labelWidth)
        local Switch = CreateToggleOption(parent, title, 50)
        local Frame = Switch.Parent
        Frame:FindFirstChildOfClass("TextLabel").Size = UDim2.new(0, labelWidth, 1, 0)

        local Box = new("TextBox", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 14 + labelWidth + 6, 0.5, 0),
            Size = UDim2.new(1, -(14 + labelWidth + 6 + 70), 0, 30),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "Value",
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = Theme.Text,
            ClipsDescendants = true,
        }, Frame)
        corner(Box, 6)
        local BoxStroke = stroke(Box)

        new("UISizeConstraint", {
            MinSize = Vector2.new(48, 0),
            MaxSize = Vector2.new(110, math.huge),
        }, Box)

        Box:GetPropertyChangedSignal("Text"):Connect(function()
            local clean = sanitizeNumber(Box.Text)
            if clean ~= Box.Text then Box.Text = clean end
        end)
        bindBoxFocus(Box, BoxStroke)

        return Switch, Box, function() flashStrokeError(BoxStroke) end
    end

    local function formatValue(v)
        return tostring(math.floor(v * 100 + 0.5) / 100)
    end

    -- Lấy giá trị hiện tại của Humanoid tại thời điểm chạy script và điền vào textbox
    local function prefillBox(Box, getValue)
        task.spawn(function()
            local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
            local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
            if not hum then return end
            local ok, v = pcall(getValue, hum)
            if ok and type(v) == "number" and v == v and Box.Parent and Box.Text == "" then
                Box.Text = formatValue(v)
            end
        end)
    end

    local function CreateHumanoidBoost(title, labelWidth, maxValue, snapshot, apply, restore, getValue)
        local Switch, Box, flashError = CreateToggleWithBox(LocalTab, title, labelWidth)
        local conn
        local original = setmetatable({}, { __mode = "k" })

        if getValue then prefillBox(Box, getValue) end

        local function stop()
            if conn then conn:Disconnect() conn = nil end
            for hum, st in pairs(original) do
                if hum.Parent then restore(hum, st) end
                original[hum] = nil
            end
        end

        local function start()
            if conn then return end
            if not readNumber(Box, maxValue) then flashError() end
            conn = RunService.Heartbeat:Connect(function()
                local hum = getHumanoid()
                if not hum then return end
                local v = readNumber(Box, maxValue)
                local st = original[hum]
                if not v then
                    if st then
                        restore(hum, st)
                        original[hum] = nil
                    end
                    return
                end
                if not st then original[hum] = snapshot(hum) end
                apply(hum, v)
            end)
        end

        BindToggle(Switch, start, stop)
    end

    --// ---------------- Speed ----------------
    CreateHumanoidBoost("Speed", 60, 1000,
        function(hum) return hum.WalkSpeed end,
        function(hum, v) if hum.WalkSpeed ~= v then hum.WalkSpeed = v end end,
        function(hum, ws) hum.WalkSpeed = ws end,
        function(hum) return hum.WalkSpeed end
    )

    --// ---------------- Jump Boost ----------------
    CreateHumanoidBoost("Jump Boost", 96, 1000,
        function(hum)
            return { use = hum.UseJumpPower, power = hum.JumpPower, height = hum.JumpHeight }
        end,
        function(hum, v)
            if not hum.UseJumpPower then hum.UseJumpPower = true end
            if hum.JumpPower ~= v then hum.JumpPower = v end
        end,
        function(hum, st)
            hum.JumpPower = st.power
            hum.JumpHeight = st.height
            hum.UseJumpPower = st.use
        end,
        function(hum)
            if hum.UseJumpPower then return hum.JumpPower end
            -- Game dùng JumpHeight -> quy đổi sang JumpPower tương đương
            return math.sqrt(2 * Workspace.Gravity * hum.JumpHeight)
        end
    )

    --// ---------------- Infinite Jump ----------------
    do
        local Switch = CreateToggleOption(LocalTab, "Infinite Jump", 50)
        local conn

        local function stop()
            if conn then conn:Disconnect() conn = nil end
        end

        local function start()
            if conn then return end
            conn = UserInputService.JumpRequest:Connect(function()
                local hum = getHumanoid()
                if hum and hum.Health > 0 then
                    hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end)
        end

        BindToggle(Switch, start, stop)
    end

    --// ---------------- Noclip ----------------
    do
        local Switch = CreateToggleOption(LocalTab, "Noclip", 50)
        local conn
        local changed = setmetatable({}, { __mode = "k" })

        local function stop()
            if conn then conn:Disconnect() conn = nil end
            for part in pairs(changed) do
                if part.Parent then part.CanCollide = true end
                changed[part] = nil
            end
        end

        local function start()
            if conn then return end
            conn = RunService.Stepped:Connect(function()
                local char = LocalPlayer.Character
                if not char then return end
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        changed[part] = true
                        part.CanCollide = false
                    end
                end
            end)
        end

        BindToggle(Switch, start, stop)
    end

    --// ---------------- Fly ----------------
    do
        local FLY_DEFAULT_SPEED = 60
        local FLY_MAX_SPEED = 1000
        local Switch, SpeedBox = CreateToggleWithBox(LocalTab, "Fly", 40)
        SpeedBox.PlaceholderText = tostring(FLY_DEFAULT_SPEED)
        local conn, jumpConn, bv, bg
        local controls
        local upUntil = 0

        local function resolveControls()
            if controls ~= nil then return end
            controls = false
            pcall(function()
                local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
                local pm = scripts and scripts:FindFirstChild("PlayerModule")
                if pm then controls = require(pm:WaitForChild("ControlModule", 2)) end
            end)
        end

        local function getMoveVector(typing)
            if controls then
                local ok, v = pcall(function() return controls:GetMoveVector() end)
                if ok and typeof(v) == "Vector3" then return v end
            end
            local x, z = 0, 0
            if not typing then
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then z -= 1 end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then z += 1 end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then x -= 1 end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then x += 1 end
            end
            return Vector3.new(x, 0, z)
        end

        local function stop()
            if conn then conn:Disconnect() conn = nil end
            if jumpConn then jumpConn:Disconnect() jumpConn = nil end
            if bv then bv:Destroy() bv = nil end
            if bg then bg:Destroy() bg = nil end
            local hum = getHumanoid()
            if hum then hum.PlatformStand = false end
        end

        local function start()
            if conn then return end
            resolveControls()

            jumpConn = UserInputService.JumpRequest:Connect(function()
                upUntil = os.clock() + 0.25
            end)

            conn = RunService.RenderStepped:Connect(function()
                local root, hum, cam = getRoot(), getHumanoid(), Workspace.CurrentCamera
                if not root or not hum or not cam or hum.Health <= 0 then return end

                if not bv or bv.Parent ~= root then
                    if bv then bv:Destroy() end
                    bv = new("BodyVelocity", { MaxForce = Vector3.one * 1e9, Velocity = Vector3.zero }, root)
                end
                if not bg or bg.Parent ~= root then
                    if bg then bg:Destroy() end
                    bg = new("BodyGyro", { MaxTorque = Vector3.one * 1e9, P = 9e4, D = 1e3 }, root)
                end
                hum.PlatformStand = true

                local typing = UserInputService:GetFocusedTextBox() ~= nil
                local cf = cam.CFrame
                local move = getMoveVector(typing)
                local dir = cf.RightVector * move.X - cf.LookVector * move.Z

                if not typing then
                    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
                    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
                        or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
                        dir -= Vector3.yAxis
                    end
                end
                if os.clock() < upUntil then dir += Vector3.yAxis end
                if dir.Magnitude > 1 then dir = dir.Unit end

                local speed = readNumber(SpeedBox, FLY_MAX_SPEED) or FLY_DEFAULT_SPEED
                bv.Velocity = dir * speed

                local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
                if look.Magnitude > 0.001 then
                    bg.CFrame = CFrame.lookAt(root.Position, root.Position + look)
                end
            end)
        end

        BindToggle(Switch, start, stop)
    end

    --// ---------------- Full Bright ----------------
    do
        local Lighting = game:GetService("Lighting")
        local Switch = CreateToggleOption(LocalTab, "Full Bright", 50)

        -- Gom mọi thứ vào 1 bảng để không tốn thêm local (Luau giới hạn 200 local / chunk)
        local FB = {
            props = { "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "GlobalShadows", "FogEnd" },
            applied = {},
            conns = {},
        }

        local function lift(c, floor)
            return Color3.new(math.max(c.R, floor), math.max(c.G, floor), math.max(c.B, floor))
        end

        -- Giá trị Full Bright tính từ giá trị gốc: chỉ làm sáng thêm, không bao giờ tối hơn map gốc
        FB.target = {
            Brightness           = function(o) return math.max(o, 2) end,
            Ambient              = function(o) return lift(o, 0.6) end,
            OutdoorAmbient       = function(o) return lift(o, 0.5) end,
            ExposureCompensation = function(o) return math.max(o, 0.3) end,
            GlobalShadows        = function() return false end,
            FogEnd               = function(o) return math.max(o, 100000) end,
        }

        function FB.read(prop)
            local ok, v = pcall(function() return Lighting[prop] end)
            if ok then return v end
        end

        function FB.apply(prop)
            local target = FB.target[prop](FB.original[prop])
            pcall(function() Lighting[prop] = target end)
            FB.applied[prop] = FB.read(prop)
        end

        -- Game (hoặc tính năng khác) đổi Lighting khi đang bật: coi giá trị đó là "gốc" mới rồi áp lại Full Bright
        function FB.onChanged(prop)
            if not FB.original then return end
            local current = FB.read(prop)
            if current == nil or current == FB.applied[prop] then return end
            FB.original[prop] = current
            FB.apply(prop)
        end

        local function stop()
            if not FB.original then return end
            for prop, c in pairs(FB.conns) do
                c:Disconnect()
                FB.conns[prop] = nil
            end
            if FB.boostConn then FB.boostConn:Disconnect() FB.boostConn = nil end
            for prop, v in pairs(FB.original) do
                pcall(function() Lighting[prop] = v end)
            end
            FB.original, FB.applied = nil, {}
        end

        local function start()
            if FB.original then return end
            FB.original = {}
            for _, prop in ipairs(FB.props) do
                local v = FB.read(prop)
                if v ~= nil then FB.original[prop] = v end
            end
            for prop in pairs(FB.original) do
                FB.apply(prop)
                FB.conns[prop] = Lighting:GetPropertyChangedSignal(prop):Connect(function()
                    FB.onChanged(prop)
                end)
            end
            -- Boost Fps tắt GlobalShadows / đặt FogEnd: ghi nhận đó là giá trị gốc mới để tắt Full Bright không hoàn tác Boost
            FB.boostConn = ScreenGui:GetAttributeChangedSignal("LightingBoosted"):Connect(function()
                if not FB.original then return end
                if FB.original.GlobalShadows ~= nil then FB.original.GlobalShadows = false end
                if FB.original.FogEnd ~= nil then FB.original.FogEnd = 9e9 end
            end)
        end

        BindToggle(Switch, start, stop)
    end

    --// ---------------- Esp Player (+ Esp Team Player) ----------------
    do
        local WHITE = Color3.fromRGB(255, 255, 255)
        local GREEN = Color3.fromRGB(60, 255, 90)
        local RED   = Color3.fromRGB(255, 60, 60)

        local Card = CreateCard(LocalTab, "EspPlayer", 10, 10, 10)

        local Switch = CreateToggleOption(Card, "Esp Player", 40)
        Switch.Parent.LayoutOrder = 1
        Switch.Parent.BackgroundColor3 = Theme.PanelAlt

        local Holder = new("Frame", {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundTransparency = 1,
        }, Card)
        padding(Holder, 18)

        local TeamSwitch = CreateToggleOption(Holder, "Esp Team Player", 40)
        TeamSwitch.Parent.BackgroundColor3 = Theme.PanelAlt

        local teamMode = false
        TeamSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
            teamMode = TeamSwitch:GetAttribute("Toggled")
        end)

        local entries = {}
        local folder, conn, removingConn

        local function destroyEntry(p)
            local e = entries[p]
            if not e then return end
            e.hl:Destroy()
            e.bb:Destroy()
            entries[p] = nil
        end

        local function makeLine(parent, order)
            return new("TextLabel", {
                LayoutOrder = order,
                Size = UDim2.new(1, 0, 0, 16),
                BackgroundTransparency = 1,
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextColor3 = WHITE,
                TextStrokeColor3 = Color3.new(0, 0, 0),
                TextStrokeTransparency = 0.25,
                Text = "",
            }, parent)
        end

        local function buildEntry(p, char)
            local hum = char:FindFirstChildOfClass("Humanoid")
            local root = char:FindFirstChild("HumanoidRootPart")
            if not hum or not root then return nil end

            local hl = new("Highlight", {
                Name = "ESP_" .. p.Name,
                Adornee = char,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                FillTransparency = 1,
                OutlineTransparency = 0,
                OutlineColor = WHITE,
            }, folder)

            local bb = new("BillboardGui", {
                Name = "ESPInfo_" .. p.Name,
                Adornee = char:FindFirstChild("Head") or root,
                AlwaysOnTop = true,
                LightInfluence = 0,
                Size = UDim2.fromOffset(170, 48),
                StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0),
            }, folder)
            list(bb, 0, { VerticalAlignment = Enum.VerticalAlignment.Bottom })

            local nameLine = makeLine(bb, 1)
            local distLine = makeLine(bb, 2)
            local hpLine   = makeLine(bb, 3)

            nameLine.Text = p.DisplayName ~= p.Name
                and (p.DisplayName .. " (@" .. p.Name .. ")")
                or p.DisplayName

            local e = {
                char = char, hum = hum, root = root, hl = hl, bb = bb,
                nameLine = nameLine, distLine = distLine, hpLine = hpLine,
                color = WHITE, dist = nil, hp = nil,
            }
            entries[p] = e
            return e
        end

        local function update()
            local cam = Workspace.CurrentCamera
            local myRoot = getRoot()
            local origin = myRoot and myRoot.Position or (cam and cam.CFrame.Position) or Vector3.zero

            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    local char = p.Character
                    local e = entries[p]
                    if e and e.char ~= char then destroyEntry(p) e = nil end
                    if char and not e then e = buildEntry(p, char) end

                    if e then
                        local alive = e.root.Parent ~= nil and e.hum.Health > 0
                        e.hl.Enabled = alive
                        e.bb.Enabled = alive

                        if alive then
                            local color = WHITE
                            if teamMode then
                                local same = LocalPlayer.Team ~= nil and p.Team == LocalPlayer.Team
                                color = same and GREEN or RED
                            end
                            if e.color ~= color then
                                e.color = color
                                e.hl.OutlineColor = color
                                e.nameLine.TextColor3 = color
                                e.distLine.TextColor3 = color
                            end

                            local d = math.floor((e.root.Position - origin).Magnitude + 0.5)
                            if e.dist ~= d then
                                e.dist = d
                                e.distLine.Text = d .. "m"
                            end

                            local hp = math.floor(e.hum.Health + 0.5)
                            local maxHp = math.max(1, math.floor(e.hum.MaxHealth + 0.5))
                            local key = hp * 100000 + maxHp
                            if e.hp ~= key then
                                e.hp = key
                                e.hpLine.Text = string.format("HP: %d/%d", hp, maxHp)
                                e.hpLine.TextColor3 = RED:Lerp(GREEN, math.clamp(hp / maxHp, 0, 1))
                            end
                        end
                    end
                end
            end
        end

        local function stop()
            if conn then conn:Disconnect() conn = nil end
            if removingConn then removingConn:Disconnect() removingConn = nil end
            for p in pairs(entries) do destroyEntry(p) end
            if folder then folder:Destroy() folder = nil end
        end

        local function start()
            if conn then return end
            folder = new("Folder", { Name = "ElyseraESP" }, CoreGui)
            removingConn = Players.PlayerRemoving:Connect(destroyEntry)
            conn = RunService.RenderStepped:Connect(update)
        end

        BindToggle(Switch, start, stop)
    end
end
