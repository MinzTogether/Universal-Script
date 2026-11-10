--// ##########################################################################################
--// ##                                                                                      ##
--// ##   MANDATORY: USE ENGLISH (US) ONLY IN THIS FILE                                      ##
--// ##   Every comment, UI text, message and name here MUST be written in English (US).     ##
--// ##   Never add any other language to this file. Keep it English (US) on every edit.     ##
--// ##                                                                                      ##
--// ##########################################################################################

--// ================= LOCAL TAB (module) =================
-- Loaded by the main script (MainWeb.lua / MainLocal.lua) and called with a ctx table of shared UI helpers
-- (ctx.UI = shared UI kit: border stroke, chevron, collapsible section).
--
-- File structure:
--   Core     : shared foundation (input parsing, toggle binding, character lifecycle, fly input, teleport history)
--              + shared UI pieces (toggle row, status badge, presets, mode dropdown, button, input; sections come from ctx.UI)
--   Features : Movement (Speed, Jump Boost, Gravity, Infinite Jump, Noclip, Fly)
--              Teleport (Click Teleport, Position XYZ / Copy, Waypoints with Rename + Export/Import, Players) + Quick actions
--              Camera (Field of View, Max Zoom, Min Zoom, Freecam), Visual (ESP, Hide Players, Full Bright, Time of Day)
--              Safety (Anti AFK, Anti Void), Reset All
-- Grouped into 2 tables to stay under Luau's limit of 200 locals per chunk.

return function(ctx)
    local LocalTab         = ctx.Tab
    local Theme            = ctx.Theme
    local ScreenGui        = ctx.ScreenGui
    local LocalPlayer      = ctx.LocalPlayer

    local Players          = ctx.Players
    local RunService       = ctx.RunService
    local UserInputService = ctx.UserInputService
    local Workspace        = ctx.Workspace
    local CoreGui          = ctx.CoreGui
    local GuiRoot          = ctx.GuiRoot or CoreGui   -- where the UI is mounted (CoreGui, or PlayerGui as a fallback)
    local UI               = assert(ctx.UI, "Local.lua needs ctx.UI: update MainWeb.lua / MainLocal.lua to the new core")
    local showToast        = ctx.Toast or UI.Toast or function() end
    local Saved            = ctx.Saved or {}
    local saveSettings     = ctx.saveSettings or function() end
    local Lighting         = game:GetService("Lighting")
    local TextService      = game:GetService("TextService")
    local TweenService     = game:GetService("TweenService")

    local new, corner, stroke, padding, list = ctx.new, ctx.corner, ctx.stroke, ctx.padding, ctx.list

    local CreateCard         = ctx.CreateCard
    local CreateToggleOption = ctx.CreateToggleOption   -- returns Switch, setState
    local flashStrokeError   = ctx.flashStrokeError
    local bindBoxFocus       = ctx.bindBoxFocus
    local isLocked           = ctx.isLocked or function() return false end
    local coreTween          = ctx.tween

    if type(Saved.localCfg) ~= "table" then Saved.localCfg = {} end

    local Core, Features = {}, {}

    -- In-world ESP colors only (all UI colors come from Theme)
    local WHITE = Color3.fromRGB(255, 255, 255)
    local GREEN = Color3.fromRGB(60, 255, 90)
    local RED   = Color3.fromRGB(255, 60, 60)

    -- Token names, resolved on every lookup so the badge colors follow theme changes
    local BADGE_TOKENS = { active = "AccentPink", waiting = "AccentPurple", invalid = "Danger" }
    local BADGE_COLORS = setmetatable({}, {
        __index = function(_, state)
            local token = BADGE_TOKENS[state]
            return token and Theme[token]
        end,
    })

    -- Enlarged "·" separator (RichText); labels that use it must have RichText = true
    Core.DOT = ' <font size="22"><b>·</b></font> '

    --// =====================================================
    --//  FOUNDATION (Core)
    --// =====================================================

    function Core.GetHumanoid()
        local c = LocalPlayer.Character
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    function Core.GetRoot()
        local c = LocalPlayer.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    --// ---------- Parse numeric input box ----------
    function Core.SanitizeNumber(s)
        s = s:gsub("[^%d%.]", "")
        local dot = s:find(".", 1, true)
        if dot then
            s = s:sub(1, dot) .. (s:sub(dot + 1):gsub("%.", ""))
        end
        return s:sub(1, 7)
    end

    function Core.FormatValue(v)
        return tostring(math.floor(v * 100 + 0.5) / 100)
    end

    function Core.ParseNumericInput(rawText, opts)
        opts = opts or {}
        local clean = Core.SanitizeNumber(rawText or "")
        if clean == "" then
            return { status = "empty", effective = opts.default }
        end
        local n = tonumber(clean)
        if clean == "." or not n or n ~= n then
            return { status = "invalid", effective = opts.default }
        end
        local eff = math.clamp(n, 0, opts.max or math.huge)
        return {
            status = (eff ~= n) and "clamped" or "ok",
            value = n,
            effective = eff,
            text = Core.FormatValue(eff),
        }
    end

    --// ---------- BindToggle: shared contract for every feature ----------
    local features = {}

    function Core.BindToggle(Switch, Set, cfg)
        local active = false
        local listeners = {}
        local handle = {}

        local function notify()
            for _, fn in ipairs(listeners) do pcall(fn, active) end
        end

        local function doStart()
            if active then return end
            active = true
            local ok, res = pcall(cfg.start)
            if not ok or res == false then
                if not ok then warn("[Local] start error:", res) end
                pcall(cfg.stop)
                active = false
                Set(false)
                if not ok and cfg.badge then cfg.badge.set("invalid", "Startup error") end
                return
            end
            notify()
        end

        local function doStop()
            if not active then return end
            active = false
            pcall(cfg.stop)
            notify()
        end

        Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
            if Switch:GetAttribute("Toggled") then doStart() else doStop() end
        end)

        function handle.isOn() return active end
        function handle.onChanged(fn) listeners[#listeners + 1] = fn end
        function handle.stop()
            Set(false)
            doStop()
        end

        features[#features + 1] = { handle = handle, onReset = cfg.onReset }
        return handle
    end

    function Core.ResetAll()
        pcall(Core.CloseDropdown)
        local n = 0
        for i = #features, 1, -1 do
            local f = features[i]
            if f.handle.isOn() then n = n + 1 end
            pcall(f.handle.stop)
            if f.onReset then pcall(f.onReset) end
        end
        return n
    end

    function Core.Register(handle, onReset)
        features[#features + 1] = { handle = handle, onReset = onReset }
    end

    Core.hooks = {}
    function Core.OnDestroy(fn)
        Core.hooks[#Core.hooks + 1] = fn
    end

    --// ---------- TrackCharacter: tracks the character lifecycle ----------
    function Core.TrackCharacter(player, onChar, opts)
        local onDied = opts and opts.onDied
        local token, cleanup, diedConn = 0, nil, nil

        local function runCleanup()
            if diedConn then diedConn:Disconnect() diedConn = nil end
            local fn = cleanup
            cleanup = nil
            if fn then pcall(fn) end
        end

        local function handle(char)
            token = token + 1
            local my = token
            runCleanup()
            local hum = char:WaitForChild("Humanoid", 10)
            local root = char:WaitForChild("HumanoidRootPart", 10)
            if my ~= token or not hum or not root or not char.Parent then return end
            local ok, fn = pcall(onChar, char, hum, root)
            if not ok then
                warn("[Local] TrackCharacter:", fn)
                return
            end
            cleanup = (type(fn) == "function") and fn or nil
            if onDied then
                diedConn = hum.Died:Connect(function()
                    if my == token then runCleanup() end
                end)
            end
        end

        local added = player.CharacterAdded:Connect(function(c) task.spawn(handle, c) end)
        local removing = player.CharacterRemoving:Connect(function()
            token = token + 1
            runCleanup()
        end)
        if player.Character then task.spawn(handle, player.Character) end

        return {
            destroy = function()
                token = token + 1
                added:Disconnect()
                removing:Disconnect()
                runCleanup()
            end,
        }
    end

    --// ---------- Flight controls: read input (fly in the camera direction) ----------
    local controlModule, controlLoading = nil, false

    function Core.LoadControls()
        if controlModule or controlLoading then return end
        controlLoading = true
        task.spawn(function()
            for _ = 1, 10 do
                local ok, m = pcall(function()
                    local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
                    local pm = scripts and scripts:FindFirstChild("PlayerModule")
                    local cm = pm and pm:FindFirstChild("ControlModule")
                    return cm and require(cm)
                end)
                if ok and m then
                    controlModule = m
                    break
                end
                task.wait(1)
            end
            controlLoading = false
        end)
    end

    function Core.ReadFlyDirection(upUntil)
        if UserInputService:GetFocusedTextBox() then return Vector3.zero end

        local move
        if controlModule then
            local ok, v = pcall(controlModule.GetMoveVector, controlModule)
            if ok and typeof(v) == "Vector3" then move = v end
        end
        if not move then
            local x, z = 0, 0
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then z = z - 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then z = z + 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then x = x - 1 end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then x = x + 1 end
            move = Vector3.new(x, 0, z)
        end

        local dir = Vector3.zero
        local cam = Workspace.CurrentCamera
        if cam then
            local cf = cam.CFrame
            dir = cf.RightVector * move.X - cf.LookVector * move.Z
        end

        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
            or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
            dir = dir - Vector3.yAxis
        end
        if os.clock() < upUntil then dir = dir + Vector3.yAxis end

        if dir.Magnitude > 1 then dir = dir.Unit end
        return dir
    end

    --// =====================================================
    --//  SHARED UI
    --// =====================================================

    function Core.CreateToggleRow(parent, title)
        local Switch, Set = CreateToggleOption(parent, title, 50)
        local Row = Switch.Parent

        local Stack = new("Frame", {
            Name = "Stack",
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
        }, parent)
        list(Stack, 4)

        Row.Parent = Stack
        Row.LayoutOrder = 1
        return {
            Switch = Switch,
            Set = Set,
            Row = Row,
            Label = Row:FindFirstChildOfClass("TextLabel"),
            Stack = Stack,
        }
    end

    function Core.CreateStatusBadge(row)
        local Line = new("Frame", {
            Name = "Status",
            LayoutOrder = 2,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 16),
            Visible = false,
        }, row.Stack)

        local Dot = new("Frame", {
            Position = UDim2.fromOffset(14, 4),
            Size = UDim2.fromOffset(8, 8),
            BackgroundColor3 = Theme.SubText,
            BorderSizePixel = 0,
        }, Line)
        corner(Dot, 4)

        local Text = new("TextLabel", {
            Position = UDim2.fromOffset(28, 0),
            Size = UDim2.new(1, -34, 1, 0),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            RichText = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextColor3 = Theme.SubText,
            Text = "",
        }, Line)

        local api = {}
        local state, curText = "off", nil
        local flashText, flashColor, flashToken = nil, nil, 0

        local function render()
            if flashText then
                Line.Visible = true
                Dot.BackgroundColor3 = flashColor
                Text.Text = flashText
                return
            end
            if state == "off" then
                Line.Visible = false
                return
            end
            Line.Visible = true
            Dot.BackgroundColor3 = BADGE_COLORS[state] or Theme.SubText
            Text.Text = curText or ""
        end

        function api.set(s, text)
            if state == s and curText == text then return end
            state, curText = s, text
            render()
        end

        function api.flash(text, seconds, s)
            flashToken = flashToken + 1
            local my = flashToken
            flashText, flashColor = text, BADGE_COLORS[s or "waiting"] or Theme.SubText
            render()
            task.delay(seconds or 3, function()
                if my == flashToken then
                    flashText = nil
                    render()
                end
            end)
        end

        return api
    end

    function Core.CreateToggleWithBox(parent, title, opts)
        opts = opts or {}
        local R = Core.CreateToggleRow(parent, title)
        local Row, Label = R.Row, R.Label
        local boxH = UserInputService.TouchEnabled and 34 or 30
        local savedVal = type(Saved.localCfg[title]) == "string" and Saved.localCfg[title] or ""

        local Box = new("TextBox", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 100, 0.5, 0),
            Size = UDim2.new(1, -176, 0, boxH),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = savedVal,
            PlaceholderText = opts.placeholder or "Value",
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = Theme.Text,
            ClipsDescendants = true,
        }, Row)
        corner(Box, 6)
        local BoxStroke = stroke(Box)

        new("UISizeConstraint", {
            MinSize = Vector2.new(48, 0),
            MaxSize = Vector2.new(110, math.huge),
        }, Box)

        local labelW = TextService:GetTextSize(Label.Text, Label.TextSize, Label.Font, Vector2.new(1000, 50)).X + 4
        Label.TextTruncate = Enum.TextTruncate.AtEnd

        local function relayout()
            local rowW = Row.AbsoluteSize.X
            local stacked = rowW > 0 and rowW < 300
            local lw = labelW
            if rowW > 0 then lw = math.min(labelW, math.max(40, rowW * 0.45)) end

            Label.Position = UDim2.new(0, 14, 0, stacked and 4 or 0)
            Label.Size = stacked and UDim2.new(0, lw, 0, 32) or UDim2.new(0, lw, 1, 0)
            if stacked then
                Row.Size = UDim2.new(Row.Size.X.Scale, Row.Size.X.Offset, 0, 76)
                Box.AnchorPoint = Vector2.new(0, 0)
                Box.Position = UDim2.new(0, 14, 0, 40)
                Box.Size = UDim2.new(1, -(14 + 70 + 6), 0, boxH)
            else
                Row.Size = UDim2.new(Row.Size.X.Scale, Row.Size.X.Offset, 0, 50)
                Box.AnchorPoint = Vector2.new(0, 0.5)
                Box.Position = UDim2.new(0, 14 + lw + 6, 0.5, 0)
                Box.Size = UDim2.new(1, -(14 + lw + 6 + 70), 0, boxH)
            end
        end
        relayout()
        Row:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

        Box:GetPropertyChangedSignal("Text"):Connect(function()
            local clean = Core.SanitizeNumber(Box.Text)
            if clean ~= Box.Text then Box.Text = clean end
            if not R.prefilling then
                Saved.localCfg[title] = Box.Text ~= "" and Box.Text or nil
                saveSettings()
            end
        end)
        bindBoxFocus(Box, BoxStroke)
        Box.FocusLost:Connect(function()
            local r = Core.ParseNumericInput(Box.Text, { max = opts.max })
            if (r.status == "ok" or r.status == "clamped") and Box.Text ~= r.text then
                Box.Text = r.text
            end
        end)

        R.Box = Box
        R.flashError = function() flashStrokeError(BoxStroke) end
        return R
    end

    function Core.CreatePresetRow(row, presets, opts)
        local getOriginal = opts and opts.getOriginal

        local Bar = new("Frame", {
            Name = "Presets",
            LayoutOrder = 3,
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
        }, row.Stack)
        padding(Bar, 14, 14, 0, 4)
        list(Bar, 6, { FillDirection = Enum.FillDirection.Horizontal, Wraps = true })

        local function valueOf(p)
            local v = p.value
            if type(v) ~= "function" then return v end
            local ok, r = pcall(v, getOriginal and getOriginal() or nil)
            return ok and r or nil
        end

        local chips = {}
        for i, p in ipairs(presets) do
            local chip = new("TextButton", {
                LayoutOrder = i,
                Size = UDim2.fromOffset(52, 32),
                Text = p.label,
                RichText = true,
                BackgroundColor3 = Theme.PanelAlt,
                BorderSizePixel = 0,
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = Theme.Text,
            }, Bar)
            corner(chip, 6)
            chips[i] = { btn = chip, stroke = stroke(chip), preset = p }

            chip.Activated:Connect(function()
                if isLocked() then return end
                local v = valueOf(p)
                if v then row.Box.Text = Core.FormatValue(v) end
            end)
        end

        local api = {}
        function api.markActive(effective)
            for _, c in ipairs(chips) do
                local v = valueOf(c.preset)
                local on = not c.preset.noHighlight and effective ~= nil and v ~= nil and math.abs(v - effective) < 0.005
                c.btn.TextColor3 = on and Theme.Sakura or Theme.Text
                c.stroke.Color = on and Theme.AccentPink or Theme.Border
            end
        end
        return api
    end

    local DD = { layer = nil, panel = nil, close = nil }
    local DD_GAP, DD_ITEM_H, DD_ARROW_W = 5, 32, 26
    local DD_SIZE, DD_LIST_SIZE = 13, 14

    function Core.CloseDropdown()
        if DD.close then DD.close() end
    end

    do (function()
        local MainUI, FunctionScroll = ctx.MainUI, ctx.FunctionScroll
        if MainUI then
            MainUI:GetPropertyChangedSignal("Visible"):Connect(function()
                if not MainUI.Visible then Core.CloseDropdown() end
            end)
            MainUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() Core.CloseDropdown() end)
        end
        if FunctionScroll then
            FunctionScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function() Core.CloseDropdown() end)
        end
    end)() end

    local function ensureDropdownLayer()
        if DD.layer and DD.layer.Parent then return DD.layer end

        local layer = new("Frame", {
            Name = "ModeDropdownLayer",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Visible = false,
            ZIndex = 100,
        }, ScreenGui)

        local blocker = new("TextButton", {
            Name = "Blocker",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 100,
        }, layer)
        blocker.Activated:Connect(function() Core.CloseDropdown() end)

        local panel = new("Frame", {
            Name = "Panel",
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            Active = true,
            ZIndex = 101,
        }, layer)
        corner(panel, 8)
        stroke(panel)
        list(panel, 2)
        padding(panel, 4, 4, 4, 4)

        DD.layer, DD.panel = layer, panel
        return layer
    end

    local function measureText(text, size)
        return TextService:GetTextSize(text, size, Enum.Font.Gotham, Vector2.new(1000, 28)).X
    end

    function Core.CreateModeDropdown(parent, modes, startIndex, onSelect)
        local index = startIndex or 1

        local Winbox = new("Frame", {
            Name = "ModeWinbox",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -14, 0.5, 0),
            Size = UDim2.fromOffset(100, 28),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
        }, parent)
        corner(Winbox, 6)
        stroke(Winbox)

        local Label = new("TextLabel", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            TextSize = DD_SIZE,
            TextColor3 = Theme.Text,
            Text = "",
        }, Winbox)

        UI.CreateChevron(Winbox, {
            Name = "Arrow",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(1, -DD_ARROW_W / 2, 0.5, -0.5),
            Size = UDim2.fromOffset(12, 12),
        }, Theme.SubText, 7, 2)

        local Hit = new("TextButton", {
            Name = "Hit",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 3,
        }, Winbox)

        local function setIndex(i, silent)
            index = i
            local m = modes[i]
            Label.Text = m.label
            Winbox.Size = UDim2.fromOffset(math.max(84, measureText(m.label, DD_SIZE) + 2 * (DD_ARROW_W + 6)), 28)
            if not silent and onSelect then onSelect(m, i) end
        end

        local function close()
            if DD.layer then DD.layer.Visible = false end
            DD.close = nil
        end

        local function open()
            if isLocked() then return end
            Core.CloseDropdown()
            local layer = ensureDropdownLayer()
            local panel = DD.panel

            for _, c in ipairs(panel:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end

            local maxW = 0
            for i, m in ipairs(modes) do
                maxW = math.max(maxW, measureText(m.label, DD_LIST_SIZE))
                local selected = (i == index)
                local item = new("TextButton", {
                    LayoutOrder = i,
                    Size = UDim2.new(1, 0, 0, DD_ITEM_H),
                    BackgroundColor3 = Theme.Text,
                    BackgroundTransparency = selected and 0.88 or 1,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = m.label,
                    Font = selected and Enum.Font.GothamBold or Enum.Font.Gotham,
                    TextSize = DD_LIST_SIZE,
                    TextColor3 = selected and Theme.Sakura or Theme.Text,
                    ZIndex = 102,
                }, panel)
                corner(item, 6)
                item.Activated:Connect(function()
                    close()
                    setIndex(i)
                end)
            end

            local tb = UserInputService:GetFocusedTextBox()
            if tb then tb:ReleaseFocus() end

            layer.Visible = true
            local lp, ls = layer.AbsolutePosition, layer.AbsoluteSize
            local ap, as = Winbox.AbsolutePosition, Winbox.AbsoluteSize

            local w = math.max(as.X, maxW + 32)
            local h = #modes * DD_ITEM_H + (#modes - 1) * 2 + 8
            local x = ap.X + as.X - lp.X
            local below = ap.Y + as.Y - lp.Y + DD_GAP
            local above = ap.Y - lp.Y - DD_GAP

            if below + h > ls.Y - 6 and above - h >= 6 then
                panel.AnchorPoint = Vector2.new(1, 1)
                panel.Position = UDim2.fromOffset(x, above)
            else
                panel.AnchorPoint = Vector2.new(1, 0)
                panel.Position = UDim2.fromOffset(x, below)
            end
            panel.Size = UDim2.fromOffset(w, h)
            DD.close = close
        end

        Hit.Activated:Connect(open)
        setIndex(index, true)
    end

    Core.BorderStroke = UI.BorderStroke

    local tweenInfos = {}
    function Core.Tween(inst, time, props)
        if coreTween then return coreTween(inst, time, props) end
        local info = tweenInfos[time]
        if not info then
            info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            tweenInfos[time] = info
        end
        TweenService:Create(inst, info, props):Play()
    end

    function Core.Label(parent, props)
        props.BackgroundTransparency = 1
        props.Font = props.Font or Enum.Font.Gotham
        props.TextColor3 = props.TextColor3 or Theme.Text
        props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
        return new("TextLabel", props, parent)
    end

    function Core.Trim(s)
        return (s:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    function Core.ClipText(s, maxChars)
        local ok, cut = pcall(utf8.offset, s, maxChars + 1)
        if ok and cut then return s:sub(1, cut - 1) end
        return s
    end

    function Core.EscapeRich(s)
        return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
    end

    --// ---------- Teleport: shared by Click TP, Position XYZ, Waypoints and Players ----------
    Core.History = { cf = nil, listeners = {} }

    function Core.TeleportTo(cf)
        local root = Core.GetRoot()
        if not root then return false end
        Core.History.cf = root.CFrame
        root.CFrame = cf
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        for _, fn in ipairs(Core.History.listeners) do pcall(fn) end
        return true
    end

    function Core.GoBack()
        local target = Core.History.cf
        if not target then return false end
        return Core.TeleportTo(target)
    end

    function Core.CreateButton(parent, text, opts)
        opts = opts or {}
        local accent = opts.variant == "accent"
        local restText = accent and Theme.ToggleKnobOn or Theme.Text

        local Btn = new("TextButton", {
            Name = opts.name or "Button",
            AnchorPoint = opts.anchor,
            Position = opts.position,
            LayoutOrder = opts.order or 0,
            Size = opts.size or UDim2.fromOffset(70, 28),
            BackgroundColor3 = accent and WHITE or Theme.Header,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = accent and "" or text,
            RichText = true,
            Font = Enum.Font.GothamBold,
            TextSize = opts.textSize or 13,
            TextColor3 = restText,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, parent)
        corner(Btn, opts.radius or 6)

        local BtnStroke
        local Caption = Btn
        if accent then
            new("UIGradient", { Color = ColorSequence.new(Theme.AccentPurple, Theme.AccentPink) }, Btn)
            Caption = new("TextLabel", {
                Name = "Caption",
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                Text = text,
                RichText = true,
                Font = Enum.Font.GothamBold,
                TextSize = opts.textSize or 13,
                TextColor3 = restText,
                TextTruncate = Enum.TextTruncate.AtEnd,
            }, Btn)
            Caption:SetAttribute("OnAccent", true)
        else
            BtnStroke = Core.BorderStroke(Btn)
        end
        local Scale = new("UIScale", { Scale = 1 }, Btn)

        local api = { Button = Btn }
        local enabled, hovered = true, false
        local baseText, flashToken = text, 0
        local activeStyle = false
        local function textColorNow()
            if accent then return Theme.ToggleKnobOn end
            return activeStyle and Theme.Sakura or Theme.Text
        end

        local function paint()
            if accent then
                local t = enabled and (hovered and 0.15 or 0) or 0.55
                Core.Tween(Btn, 0.12, { BackgroundTransparency = t })
            else
                local c = (enabled and hovered) and Theme.Border or Theme.Header
                Core.Tween(Btn, 0.12, { BackgroundColor3 = c })
            end
        end

        Btn.MouseEnter:Connect(function()
            hovered = true
            paint()
        end)
        Btn.MouseLeave:Connect(function()
            hovered = false
            paint()
            Core.Tween(Scale, 0.1, { Scale = 1 })
        end)
        Btn.MouseButton1Down:Connect(function()
            if enabled then Core.Tween(Scale, 0.08, { Scale = 0.95 }) end
        end)
        Btn.MouseButton1Up:Connect(function()
            Core.Tween(Scale, 0.12, { Scale = 1 })
        end)

        function api.onClick(fn)
            Btn.Activated:Connect(function()
                if isLocked() or not enabled then return end
                fn()
            end)
        end

        function api.setText(t)
            baseText = t
            flashToken = flashToken + 1
            Caption.Text = t
            Caption.TextColor3 = textColorNow()
        end

        function api.setEnabled(on)
            enabled = on and true or false
            Caption.TextTransparency = enabled and 0 or 0.5
            if BtnStroke then BtnStroke.Transparency = enabled and 0 or 0.5 end
            paint()
        end

        function api.setActive(on)
            if accent then return end
            activeStyle = on and true or false
            Caption.TextColor3 = textColorNow()
            BtnStroke.Color = on and Theme.AccentPink or Theme.Border
        end

        function api.flash(t, seconds, isError)
            flashToken = flashToken + 1
            local my = flashToken
            Caption.Text = t
            if not accent then Caption.TextColor3 = isError and Theme.Danger or Theme.Sakura end
            task.delay(seconds or 1.2, function()
                if my == flashToken and Btn.Parent then
                    Caption.Text = baseText
                    Caption.TextColor3 = textColorNow()
                end
            end)
        end

        return api
    end

    Core.CreateChevron = UI.CreateChevron
    Core.CreateSectionGroup = UI.CreateSection

    function Core.CreateInput(parent, placeholder, opts)
        opts = opts or {}
        local Box = new("TextBox", {
            Name = "Input",
            AnchorPoint = opts.anchor,
            Position = opts.position,
            LayoutOrder = opts.order or 0,
            Size = opts.size or UDim2.new(1, 0, 0, UserInputService.TouchEnabled and 34 or 30),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = placeholder,
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClipsDescendants = true,
        }, parent)
        corner(Box, 6)
        local BoxStroke = Core.BorderStroke(Box)
        padding(Box, 10, 10)
        bindBoxFocus(Box, BoxStroke)
        return Box, BoxStroke
    end

    function Core.CreateNote(parent, props)
        props.TextSize = props.TextSize or 12
        props.TextXAlignment = Enum.TextXAlignment.Right
        props.TextColor3 = Theme.SubText
        props.TextTruncate = Enum.TextTruncate.AtEnd
        local L = Core.Label(parent, props)
        local base, token = "", 0
        local api = { Label = L }

        function api.setBase(text)
            base = text
            token = token + 1
            L.Text = text
            L.TextColor3 = Theme.SubText
        end

        function api.flash(text, isError, seconds)
            token = token + 1
            local my = token
            L.Text = text
            L.TextColor3 = isError and Theme.Danger or Theme.Sakura
            task.delay(seconds or 1.8, function()
                if my == token and L.Parent then
                    L.Text = base
                    L.TextColor3 = Theme.SubText
                end
            end)
        end

        return api
    end

    --// =====================================================
    --//  FEATURES
    --// =====================================================

    --// ---------------- Boost: one value on one instance (Speed, Jump, Gravity, FOV, Max Zoom, Min Zoom, Time of Day) ----------------
    Core.Boost = { reapply = 30, window = 1, step = 0.2 }

    Core.Watchdog = { checks = {}, conn = nil, acc = 0 }

    function Core.Watchdog.add(check)
        local W = Core.Watchdog
        W.checks[check] = true
        if W.conn then return end
        W.acc = 0
        W.conn = RunService.Heartbeat:Connect(function(dt)
            W.acc = W.acc + dt
            if W.acc < Core.Boost.step then return end
            W.acc = 0
            for fn in pairs(W.checks) do pcall(fn) end
        end)
    end

    function Core.Watchdog.remove(check)
        local W = Core.Watchdog
        W.checks[check] = nil
        if W.conn and next(W.checks) == nil then
            W.conn:Disconnect()
            W.conn = nil
        end
    end

    Core.OnDestroy(function()
        local W = Core.Watchdog
        table.clear(W.checks)
        if W.conn then W.conn:Disconnect() W.conn = nil end
    end)

    function Features.CreateTargetBoost(parent, cfg)
        local row = Core.CreateToggleWithBox(parent, cfg.title, { max = cfg.max })
        local badge = Core.CreateStatusBadge(row)
        local snaps = setmetatable({}, { __mode = "k" })
        local current, watchConn, presetApi
        local sigs = {}
        local active = false
        local applying = false
        local parsed = { status = "empty" }
        local budget = { n = 0, t = 0 }
        local onExternal

        local function reparse()
            parsed = Core.ParseNumericInput(row.Box.Text, { max = cfg.max })
            if cfg.min and parsed.effective and parsed.effective < cfg.min then
                parsed.effective, parsed.status = cfg.min, "clamped"
            end
        end
        reparse()

        local function getOriginal()
            local t = cfg.getTarget()
            if not t then return nil end
            local st = snaps[t]
            if st ~= nil then return cfg.fromSnapshot(st) end
            local ok, v = pcall(cfg.getValue, t)
            if ok and type(v) == "number" then return v end
            return nil
        end

        local function showActive(v)
            local word = (parsed.status == "clamped") and "Capped" or "Running"
            badge.set("active", word .. Core.DOT .. Core.FormatValue(v))
        end

        local function applyValue(t, v)
            applying = true
            local ok, err = pcall(cfg.apply, t, v)
            applying = false
            if not ok then error(err, 0) end
            task.defer(function()
                if t == current and not applying and parsed.effective == v and not cfg.isApplied(t, v) then
                    onExternal(t)
                end
            end)
        end

        local function applyTo(t)
            local v = parsed.effective
            if not v then
                if snaps[t] ~= nil then
                    pcall(cfg.restore, t, snaps[t])
                    snaps[t] = nil
                end
                badge.set("paused", "Waiting for value")
                return
            end
            if snaps[t] == nil then snaps[t] = cfg.snapshot(t) end
            applyValue(t, v)
            showActive(v)
        end

        local function takeBudget()
            local now, B = os.clock(), Core.Boost
            if now - budget.t >= B.window then
                budget.t, budget.n = now, 0
            end
            if budget.n >= B.reapply then return false end
            budget.n = budget.n + 1
            return true
        end

        function onExternal(t)
            if applying or t ~= current or snaps[t] == nil then return end
            local v = parsed.effective
            if not v or cfg.isApplied(t, v) then return end

            snaps[t] = cfg.snapshot(t)
            if not takeBudget() then
                badge.set("paused", "Overridden by game")
                return
            end
            applyValue(t, v)
            showActive(v)
        end

        local function unbind()
            for _, s in ipairs(sigs) do s:Disconnect() end
            table.clear(sigs)
            local t = current
            current = nil
            if t and snaps[t] ~= nil then
                pcall(cfg.restore, t, snaps[t])
                snaps[t] = nil
            end
        end

        local function attach()
            local t = cfg.getTarget()
            if t and t == current and #sigs > 0 then
                applyTo(t)
                return
            end
            unbind()
            if not t then
                badge.set("waiting", "Waiting for " .. (cfg.waitFor or "target"))
                return
            end
            budget.n, budget.t = 0, 0
            current = t
            applyTo(t)
            for _, prop in ipairs(cfg.props) do
                sigs[#sigs + 1] = t:GetPropertyChangedSignal(prop):Connect(function()
                    onExternal(t)
                end)
            end
        end

        local function check()
            if not active then return end
            local t = cfg.getTarget()
            if t ~= current then
                attach()
            elseif t then
                onExternal(t)
            end
        end

        local function start()
            reparse()
            if parsed.effective == nil then
                badge.flash("Enter a valid value", 2.5, "invalid")
                row.flashError()
                return false
            end
            active = true
            attach()
            if cfg.watch then watchConn = cfg.watch(attach) end
            Core.Watchdog.add(check)
        end

        local function stop()
            active = false
            Core.Watchdog.remove(check)
            if watchConn then watchConn:Disconnect() watchConn = nil end
            unbind()
            badge.set("off")
        end

        local function fillFrom(t)
            local ok, v = pcall(cfg.getValue, t)
            if ok and type(v) == "number" and v == v and v < 1e6 and row.Box.Parent and row.Box.Text == "" then
                row.prefilling = true
                row.Box.Text = Core.FormatValue(v)
                row.prefilling = false
                reparse()
            end
        end

        local function prefill()
            local t = cfg.getTarget()
            if t then
                fillFrom(t)
            elseif cfg.waitTarget then
                task.spawn(function()
                    local waited = cfg.waitTarget()
                    if waited then fillFrom(waited) end
                end)
            end
        end
        prefill()

        row.Box:GetPropertyChangedSignal("Text"):Connect(function()
            reparse()
            if presetApi then presetApi.markActive(parsed.effective) end
            if active and current then applyTo(current) end
        end)

        local handle = Core.BindToggle(row.Switch, row.Set, {
            start = start,
            stop = stop,
            badge = badge,
            onReset = function()
                row.Box.Text = ""
                prefill()
            end,
        })

        presetApi = Core.CreatePresetRow(row, cfg.presets, { getOriginal = getOriginal })
        presetApi.markActive(parsed.effective)
        return handle
    end

    local function waitHumanoid()
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        if not char then return nil end
        return char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
    end

    local function watchHumanoid(cb)
        local token = 0
        local function onChar(char)
            token = token + 1
            local my = token
            task.spawn(function()
                if char:WaitForChild("Humanoid", 10) and my == token and char.Parent then cb() end
            end)
        end
        local conn = LocalPlayer.CharacterAdded:Connect(onChar)
        local char = LocalPlayer.Character
        if char and not char:FindFirstChildOfClass("Humanoid") then onChar(char) end
        return {
            Disconnect = function()
                token = token + 1
                conn:Disconnect()
            end,
        }
    end

    local function humanoidCfg(cfg)
        cfg.waitFor = "character"
        cfg.getTarget = Core.GetHumanoid
        cfg.watch = watchHumanoid
        cfg.waitTarget = waitHumanoid
        return cfg
    end

    local function originalPreset()
        return { label = "Original", noHighlight = true, value = function(o) return o end }
    end

    local function boostPresets(maxValue)
        return {
            originalPreset(),
            { label = '<font size="20">×</font>2',  value = function(o) return o and o * 2 end },
            { label = '<font size="20">×</font>4',  value = function(o) return o and o * 4 end },
            { label = "Max", value = maxValue },
        }
    end

    local SPEED_CFG = humanoidCfg({
        title = "Speed", max = 1000,
        props = { "WalkSpeed" },
        snapshot = function(hum) return hum.WalkSpeed end,
        apply = function(hum, v) if hum.WalkSpeed ~= v then hum.WalkSpeed = v end end,
        restore = function(hum, ws) hum.WalkSpeed = ws end,
        getValue = function(hum) return hum.WalkSpeed end,
        isApplied = function(hum, v) return math.abs(hum.WalkSpeed - v) < 1e-3 end,
        fromSnapshot = function(st) return st end,
        presets = boostPresets(1000),
    })

    local JUMP_CFG = humanoidCfg({
        title = "Jump Boost", max = 1000,
        props = { "JumpPower", "UseJumpPower" },
        snapshot = function(hum)
            return { use = hum.UseJumpPower, power = hum.JumpPower, height = hum.JumpHeight }
        end,
        apply = function(hum, v)
            if not hum.UseJumpPower then hum.UseJumpPower = true end
            if hum.JumpPower ~= v then hum.JumpPower = v end
        end,
        restore = function(hum, st)
            hum.JumpPower = st.power
            hum.JumpHeight = st.height
            hum.UseJumpPower = st.use
        end,
        getValue = function(hum)
            if hum.UseJumpPower then return hum.JumpPower end
            return math.sqrt(2 * Workspace.Gravity * hum.JumpHeight)
        end,
        isApplied = function(hum, v)
            return hum.UseJumpPower and math.abs(hum.JumpPower - v) < 1e-3
        end,
        fromSnapshot = function(st)
            if st.use then return st.power end
            return math.sqrt(2 * Workspace.Gravity * st.height)
        end,
        presets = boostPresets(1000),
    })

    --// ---------------- Infinite Jump ----------------
    function Features.CreateInfiniteJump(parent)
        local Switch, Set = CreateToggleOption(parent, "Infinite Jump", 50)
        local conn

        return Core.BindToggle(Switch, Set, {
            start = function()
                conn = UserInputService.JumpRequest:Connect(function()
                    local hum = Core.GetHumanoid()
                    if hum and hum.Health > 0 then
                        hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    end
                end)
            end,
            stop = function()
                if conn then conn:Disconnect() conn = nil end
            end,
        })
    end

    --// ---------------- Noclip ----------------
    function Features.CreateNoclip(parent)
        local row = Core.CreateToggleRow(parent, "Noclip")
        local badge = Core.CreateStatusBadge(row)
        local tracker

        local function start()
            badge.set("waiting", "Waiting for character")
            tracker = Core.TrackCharacter(LocalPlayer, function(char)
                local parts, original, conns = {}, {}, {}

                local function add(inst)
                    if inst:IsA("BasePart") and original[inst] == nil then
                        original[inst] = inst.CanCollide
                        parts[#parts + 1] = inst
                    end
                end
                for _, d in ipairs(char:GetDescendants()) do add(d) end
                conns[1] = char.DescendantAdded:Connect(add)

                conns[2] = RunService.Stepped:Connect(function()
                    for i = #parts, 1, -1 do
                        local p = parts[i]
                        if p.Parent then
                            if p.CanCollide then p.CanCollide = false end
                        else
                            table.remove(parts, i)
                            original[p] = nil
                        end
                    end
                end)
                badge.set("active", "Running")

                return function()
                    for _, c in ipairs(conns) do c:Disconnect() end
                    for p, was in pairs(original) do
                        if p.Parent then p.CanCollide = was end
                    end
                end
            end)
        end

        local function stop()
            if tracker then tracker.destroy() tracker = nil end
            badge.set("off")
        end

        return Core.BindToggle(row.Switch, row.Set, { start = start, stop = stop, badge = badge })
    end

    --// ---------------- Fly ----------------
    function Features.CreateFly(parent)
        local DEFAULT, MAX = 60, 1000
        local row = Core.CreateToggleWithBox(parent, "Fly", { placeholder = tostring(DEFAULT), max = MAX })
        local badge = Core.CreateStatusBadge(row)
        local upUntil = 0
        local vel = Vector3.zero
        local active, seated = false, false
        local tracker, jumpConn, brakeConn
        local parsed = { status = "empty", effective = DEFAULT }

        local function updateBadge()
            if parsed.status == "ok" then
                badge.set("active", "Flying" .. Core.DOT .. Core.FormatValue(parsed.effective))
            elseif parsed.status == "clamped" then
                badge.set("active", "Capped" .. Core.DOT .. Core.FormatValue(parsed.effective))
            else
                badge.set("active", "Using default " .. DEFAULT)
            end
        end

        local function reparse()
            parsed = Core.ParseNumericInput(row.Box.Text, { max = MAX, default = DEFAULT })
            if active and not seated then updateBadge() end
        end
        row.Box:GetPropertyChangedSignal("Text"):Connect(reparse)
        reparse()

        local function start()
            active, seated = true, false
            reparse()
            badge.set("waiting", "Waiting for character")

            jumpConn = UserInputService.JumpRequest:Connect(function()
                upUntil = os.clock() + 0.25
            end)
            brakeConn = UserInputService.InputBegan:Connect(function(i, gp)
                if not gp and i.KeyCode == Enum.KeyCode.X then vel = Vector3.zero end
            end)
            Core.LoadControls()

            tracker = Core.TrackCharacter(LocalPlayer, function(_, hum, root)
                local snap = { platformStand = hum.PlatformStand, autoRotate = hum.AutoRotate }

                local att = new("Attachment", { Name = "ElyseraFlyAtt" }, root)
                local lv = new("LinearVelocity", {
                    Name = "ElyseraFlyLV",
                    Attachment0 = att,
                    RelativeTo = Enum.ActuatorRelativeTo.World,
                    MaxForce = 1e9,
                    VectorVelocity = Vector3.zero,
                }, root)
                local ao = new("AlignOrientation", {
                    Name = "ElyseraFlyAO",
                    Mode = Enum.OrientationAlignmentMode.OneAttachment,
                    Attachment0 = att,
                    RigidityEnabled = false,
                    MaxTorque = 1e9,
                    Responsiveness = 50,
                }, root)
                hum.PlatformStand = true
                hum.AutoRotate = false
                vel = Vector3.zero
                seated = false
                updateBadge()
                local lastVel, lastLook = vel, nil

                local conn = RunService.RenderStepped:Connect(function(dt)
                    if hum.Health <= 0 or not root.Parent then return end

                    if hum.SeatPart then
                        if not seated then
                            seated = true
                            vel = Vector3.zero
                            lastVel = vel
                            lv.VectorVelocity = vel
                            badge.set("paused", "Seated")
                        end
                        return
                    elseif seated then
                        seated = false
                        updateBadge()
                    end

                    local speed = parsed.effective or DEFAULT
                    local dir = Core.ReadFlyDirection(upUntil)
                    vel = vel:Lerp(dir * speed, math.clamp(dt / 0.12, 0, 1))
                    if dir == Vector3.zero and vel.Magnitude < 0.05 then vel = Vector3.zero end
                    if vel ~= lastVel then
                        lastVel = vel
                        lv.VectorVelocity = vel
                    end

                    local cam = Workspace.CurrentCamera
                    if cam then
                        local look = cam.CFrame.LookVector
                        look = Vector3.new(look.X, 0, look.Z)
                        if look.Magnitude > 0.001 and look ~= lastLook then
                            lastLook = look
                            ao.CFrame = CFrame.lookAt(Vector3.zero, look)
                        end
                    end
                end)

                return function()
                    conn:Disconnect()
                    lv:Destroy()
                    ao:Destroy()
                    att:Destroy()
                    if hum.Parent then
                        hum.PlatformStand = snap.platformStand
                        hum.AutoRotate = snap.autoRotate
                    end
                end
            end, { onDied = true })
        end

        local function stop()
            active, seated = false, false
            if jumpConn then jumpConn:Disconnect() jumpConn = nil end
            if brakeConn then brakeConn:Disconnect() brakeConn = nil end
            if tracker then tracker.destroy() tracker = nil end
            vel = Vector3.zero
            badge.set("off")
        end

        local handle = Core.BindToggle(row.Switch, row.Set, {
            start = start,
            stop = stop,
            badge = badge,
            onReset = function() row.Box.Text = "" end,
        })

        Core.CreatePresetRow(row, {
            { label = "30",  value = 30 },
            { label = "60",  value = 60 },
            { label = "120", value = 120 },
            { label = "250", value = 250 },
        })
        return handle
    end

    --// ---------------- Freecam ----------------
    function Features.CreateFreecam(parent)
        local DEFAULT, MAX = 60, 1000
        local row = Core.CreateToggleWithBox(parent, "Freecam", { placeholder = tostring(DEFAULT), max = MAX })
        local badge = Core.CreateStatusBadge(row)
        local parsed = { status = "empty", effective = DEFAULT }
        local active = false
        local conns = {}
        local camSnap, rootSnap
        local camPos, yaw, pitch = Vector3.zero, 0, 0
        local upUntil = 0

        local function updateBadge()
            local spd = Core.FormatValue(parsed.effective or DEFAULT)
            badge.set("active", "Freecam" .. Core.DOT .. spd .. " (drag to look)")
        end

        local function reparse()
            parsed = Core.ParseNumericInput(row.Box.Text, { max = MAX, default = DEFAULT })
            if active then updateBadge() end
        end
        row.Box:GetPropertyChangedSignal("Text"):Connect(reparse)
        reparse()

        local function stop()
            active = false
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
            if camSnap then
                local cam = Workspace.CurrentCamera
                if cam then
                    pcall(function()
                        cam.CameraType = camSnap.type
                        if camSnap.subject and camSnap.subject.Parent then
                            cam.CameraSubject = camSnap.subject
                        end
                        cam.CFrame = camSnap.cf
                    end)
                end
                camSnap = nil
            end
            if rootSnap and rootSnap.root and rootSnap.root.Parent then
                rootSnap.root.Anchored = rootSnap.anchored
            end
            rootSnap = nil
            badge.set("off")
        end

        local function start()
            local cam = Workspace.CurrentCamera
            if not cam then return false end
            active = true
            reparse()
            Core.LoadControls()

            local rx, ry = cam.CFrame:ToOrientation()
            pitch, yaw = rx, ry
            camPos = cam.CFrame.Position
            camSnap = { type = cam.CameraType, subject = cam.CameraSubject, cf = cam.CFrame }
            cam.CameraType = Enum.CameraType.Scriptable

            local root = Core.GetRoot()
            if root then
                rootSnap = { root = root, anchored = root.Anchored }
                root.Anchored = true
            end

            conns[1] = UserInputService.JumpRequest:Connect(function()
                upUntil = os.clock() + 0.25
            end)
            conns[2] = UserInputService.InputBegan:Connect(function(i, gp)
                if not gp and i.UserInputType == Enum.UserInputType.MouseButton2 then
                    pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition end)
                end
            end)
            conns[3] = UserInputService.InputEnded:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseButton2 then
                    pcall(function() UserInputService.MouseBehavior = Enum.MouseBehavior.Default end)
                end
            end)
            conns[4] = UserInputService.InputChanged:Connect(function(i, gp)
                if gp then return end
                if i.UserInputType == Enum.UserInputType.MouseMovement
                    and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
                    yaw = yaw - (i.Delta.X * 0.005)
                    pitch = math.clamp(pitch - i.Delta.Y * 0.005, -1.5, 1.5)
                elseif i.UserInputType == Enum.UserInputType.Touch then
                    yaw = yaw - (i.Delta.X * 0.006)
                    pitch = math.clamp(pitch - i.Delta.Y * 0.006, -1.5, 1.5)
                end
            end)
            conns[5] = RunService.RenderStepped:Connect(function(dt)
                local c = Workspace.CurrentCamera
                if not c then return end
                if c.CameraType ~= Enum.CameraType.Scriptable then
                    c.CameraType = Enum.CameraType.Scriptable
                end
                local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
                c.CFrame = CFrame.new(camPos) * rot
                local dir = Core.ReadFlyDirection(upUntil)
                local speed = parsed.effective or DEFAULT
                camPos = camPos + (dir * speed * dt)
                c.CFrame = CFrame.new(camPos) * rot
            end)
            updateBadge()
        end

        local handle = Core.BindToggle(row.Switch, row.Set, {
            start = start,
            stop = stop,
            badge = badge,
            onReset = function() row.Box.Text = "" end,
        })

        Core.CreatePresetRow(row, {
            { label = "30",  value = 30 },
            { label = "60",  value = 60 },
            { label = "120", value = 120 },
            { label = "250", value = 250 },
        })
        return handle
    end

    --// ---------------- Full Bright ----------------
    local FB_MODES = {
        { id = "bright", label = "Bright" },
        { id = "fog",    label = "Bright + no fog" },
        { id = "perf",   label = "Performance" },
    }

    local function liftColor(c, floor)
        return Color3.new(math.max(c.R, floor), math.max(c.G, floor), math.max(c.B, floor))
    end

    local function fullBrightProps(modeId)
        local props = {
            Brightness           = function(b) return math.max(b, 2) end,
            Ambient              = function(c) return liftColor(c, 0.6) end,
            OutdoorAmbient       = function(c) return liftColor(c, 0.5) end,
            ExposureCompensation = function(e) return math.max(e, 0.3) end,
        }
        if modeId == "fog" or modeId == "perf" then
            props.FogEnd = function(f) return math.max(f, 100000) end
        end
        if modeId == "perf" then
            props.GlobalShadows = function() return false end
        end
        return props
    end

    function Features.CreateFullBright(parent)
        local row = Core.CreateToggleRow(parent, "Full Bright")
        local badge = Core.CreateStatusBadge(row)

        local ModeRow = new("Frame", {
            Name = "ModeRow",
            LayoutOrder = 3,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 36),
        }, row.Stack)

        local startIdx = tonumber(Saved.localCfg["FullBrightMode"]) or 1
        if not FB_MODES[startIdx] then startIdx = 1 end
        local mode = FB_MODES[startIdx]
        local handle

        local claim, base, last, conns = nil, {}, {}, {}
        local writing = false

        local function write(p)
            local v = claim[p](base[p])
            if Lighting[p] ~= v then
                writing = true
                Lighting[p] = v
                writing = false
            end
            last[p] = Lighting[p]
        end

        local function giveBack(p)
            local c = conns[p]
            if c then c:Disconnect() conns[p] = nil end
            local b = base[p]
            base[p], last[p] = nil, nil
            if b ~= nil and Lighting[p] ~= b then Lighting[p] = b end
        end

        local function apply()
            local props = fullBrightProps(mode.id)
            if claim then
                for p in pairs(claim) do
                    if not props[p] then giveBack(p) end
                end
            end
            claim = props
            for p in pairs(props) do
                if not conns[p] then
                    base[p] = Lighting[p]
                    conns[p] = Lighting:GetPropertyChangedSignal(p):Connect(function()
                        if writing or not claim or not claim[p] then return end
                        local now = Lighting[p]
                        if now == last[p] then return end
                        base[p] = now
                        write(p)
                    end)
                end
                write(p)
            end
            badge.set("active", mode.label)
        end

        local function release()
            if claim then
                for p in pairs(claim) do giveBack(p) end
                claim = nil
            end
            badge.set("off")
        end

        handle = Core.BindToggle(row.Switch, row.Set, { start = apply, stop = release, badge = badge })

        Core.CreateModeDropdown(ModeRow, FB_MODES, startIdx, function(m, idx)
            mode = m
            Saved.localCfg["FullBrightMode"] = idx
            saveSettings()
            if handle.isOn() then apply() end
        end)
        return handle
    end

    --// ---------------- ESP ----------------
    function Features.CreateEspOptions(Card, onChange)
        local opts = {
            teamMode = false,
            occluded = false,
            hide = { name = false, dist = false, hp = false, team = false },
        }
        local items = {}
        local order = 2

        local function bind(lbl, apply)
            local Holder = new("Frame", {
                LayoutOrder = order,
                Size = UDim2.new(1, 0, 0, 40),
                BackgroundTransparency = 1,
            }, Card)
            order = order + 1
            padding(Holder, 18)

            local sw, set = CreateToggleOption(Holder, lbl, 40)
            sw.Parent.BackgroundColor3 = Theme.PanelAlt
            sw:GetAttributeChangedSignal("Toggled"):Connect(function()
                apply(sw:GetAttribute("Toggled") == true)
                onChange(opts)
            end)

            local Dim = new("Frame", {
                Size = UDim2.fromScale(1, 1),
                BackgroundColor3 = Color3.new(0, 0, 0),
                BackgroundTransparency = 0.5,
                BorderSizePixel = 0,
                Active = true,
                ZIndex = 50,
            }, Holder)
            corner(Dim, 8)

            items[#items + 1] = { set = set, dim = Dim }
        end

        bind("Esp Team Player", function(on) opts.teamMode = on end)
        bind("Hide Name",       function(on) opts.hide.name = on end)
        bind("Hide Distance",   function(on) opts.hide.dist = on end)
        bind("Hide HP",         function(on) opts.hide.hp = on end)
        bind("Hide Team",       function(on) opts.hide.team = on end)
        bind("Only when visible", function(on) opts.occluded = on end)

        local ui = {}
        function ui.setEnabled(enabled)
            for _, it in ipairs(items) do it.dim.Visible = not enabled end
        end
        function ui.reset()
            for _, it in ipairs(items) do it.set(false) end
        end
        return opts, ui
    end

    function Features.CreateEspController(opts)
        local HIGHLIGHT_BUDGET = 31
        local entries, trackers, conns, folder, stopLoop = {}, {}, {}, nil, nil
        local hlCount, stopping = 0, false
        local syncAll

        local function teamColor(p)
            if not opts.teamMode then return WHITE end
            local mine, theirs = LocalPlayer.Team, p.Team
            if not mine or not theirs then return WHITE end
            return (mine == theirs) and GREEN or RED
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

        local function setOutlineColor(e, color)
            if e.useHl then e.outline.OutlineColor = color else e.outline.Color3 = color end
        end

        local function applyStyle(e)
            local h = opts.hide
            e.nameLine.Visible = not h.name
            e.distLine.Visible = not h.dist
            e.hpLine.Visible = not h.hp
            e.teamLine.Visible = (not h.team) and e.teamLine.Text ~= ""
            e.bb.Enabled = e.nameLine.Visible or e.distLine.Visible
                or e.hpLine.Visible or e.teamLine.Visible
            e.bb.AlwaysOnTop = not opts.occluded
            if e.useHl then
                e.outline.DepthMode = opts.occluded and Enum.HighlightDepthMode.Occluded
                    or Enum.HighlightDepthMode.AlwaysOnTop
            else
                e.outline.AlwaysOnTop = not opts.occluded
            end
        end

        local function refreshColor(p, e)
            local color = teamColor(p)
            setOutlineColor(e, color)
            e.nameLine.TextColor3 = color
            e.distLine.TextColor3 = color
            e.teamLine.TextColor3 = color
            e.teamLine.Text = p.Team and p.Team.Name or ""
            applyStyle(e)
        end

        local function refreshHp(e)
            local hp = math.floor(math.min(e.hum.Health, 1e9) + 0.5)
            local maxHp = math.max(1, math.floor(math.min(e.hum.MaxHealth, 1e9) + 0.5))
            if e.hp ~= hp or e.maxHp ~= maxHp then
                e.hp, e.maxHp = hp, maxHp
                e.hpLine.Text = string.format("HP: %d/%d", hp, maxHp)
                e.hpLine.TextColor3 = RED:Lerp(GREEN, math.clamp(hp / maxHp, 0, 1))
            end
        end

        local function makeOutline(p, e, asHighlight)
            if asHighlight then
                return new("Highlight", {
                    Name = "ESP_" .. p.Name,
                    Adornee = e.char,
                    DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
                    FillTransparency = 1,
                    OutlineTransparency = 0,
                    OutlineColor = WHITE,
                }, folder)
            end
            local boxCf, boxSize = e.char:GetBoundingBox()
            return new("BoxHandleAdornment", {
                Name = "ESPBox_" .. p.Name,
                Adornee = e.root,
                CFrame = e.root.CFrame:ToObjectSpace(boxCf),
                Size = boxSize,
                Transparency = 0.75,
                Color3 = WHITE,
                AlwaysOnTop = true,
                ZIndex = 1,
            }, folder)
        end

        local function setOutlineMode(p, e, asHighlight)
            if not folder or (e.outline and e.useHl == asHighlight) then return end
            if e.outline then
                e.outline:Destroy()
                if e.useHl then hlCount = hlCount - 1 end
            end
            e.useHl = asHighlight
            e.outline = makeOutline(p, e, asHighlight)
            if asHighlight then hlCount = hlCount + 1 end
            refreshColor(p, e)
        end

        local function buildVisuals(p, e)
            local char = e.char
            e.bb = new("BillboardGui", {
                Name = "ESPInfo_" .. p.Name,
                Adornee = char:FindFirstChild("Head") or e.root,
                AlwaysOnTop = true,
                LightInfluence = 0,
                Size = UDim2.fromOffset(170, 64),
                StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0),
            }, folder)
            list(e.bb, 0, { VerticalAlignment = Enum.VerticalAlignment.Bottom })

            e.nameLine = makeLine(e.bb, 1)
            e.teamLine = makeLine(e.bb, 2)
            e.distLine = makeLine(e.bb, 3)
            e.hpLine   = makeLine(e.bb, 4)

            e.nameLine.Text = p.DisplayName ~= p.Name
                and (p.DisplayName .. " (@" .. p.Name .. ")")
                or p.DisplayName
        end

        local function destroyVisuals(e)
            if e.outline then
                if e.useHl then hlCount = hlCount - 1 end
                e.outline:Destroy()
                e.outline = nil
            end
            if e.bb then e.bb:Destroy() e.bb = nil end
        end

        local function countEntries()
            local n = 0
            for _ in pairs(entries) do n = n + 1 end
            return n
        end

        local function getOrigin()
            local cam = Workspace.CurrentCamera
            local myRoot = Core.GetRoot()
            return myRoot and myRoot.Position or (cam and cam.CFrame.Position) or Vector3.zero
        end

        local function rebalance()
            if not folder then return end
            if countEntries() <= HIGHLIGHT_BUDGET then
                for p, e in pairs(entries) do setOutlineMode(p, e, true) end
                return
            end
            local origin = getOrigin()
            local ranked = {}
            for p, e in pairs(entries) do
                if e.root.Parent then
                    local d = (e.root.Position - origin).Magnitude
                    ranked[#ranked + 1] = { p = p, e = e, key = e.useHl and d * 0.9 or d }
                end
            end
            table.sort(ranked, function(a, b) return a.key < b.key end)
            for i, it in ipairs(ranked) do
                setOutlineMode(it.p, it.e, i <= HIGHLIGHT_BUDGET)
            end
        end

        local function track(p)
            if p == LocalPlayer or trackers[p] then return end
            trackers[p] = Core.TrackCharacter(p, function(char, hum, root)
                local e = { char = char, hum = hum, root = root, dist = nil, hp = nil, maxHp = nil }
                buildVisuals(p, e)
                entries[p] = e
                setOutlineMode(p, e, hlCount < HIGHLIGHT_BUDGET)
                refreshHp(e)

                local c1 = hum.HealthChanged:Connect(function() refreshHp(e) end)
                local c2 = hum:GetPropertyChangedSignal("MaxHealth"):Connect(function() refreshHp(e) end)
                local c3 = p:GetPropertyChangedSignal("Team"):Connect(function() refreshColor(p, e) end)
                return function()
                    c1:Disconnect()
                    c2:Disconnect()
                    c3:Disconnect()
                    destroyVisuals(e)
                    entries[p] = nil
                    if not stopping then syncAll() end
                end
            end, { onDied = true })
        end

        local function updateDistances()
            local origin = getOrigin()
            for _, e in pairs(entries) do
                if e.distLine and e.root.Parent then
                    local d = math.floor((e.root.Position - origin).Magnitude + 0.5)
                    if e.dist ~= d then
                        e.dist = d
                        e.distLine.Text = d .. "m"
                    end
                end
            end
        end

        local function syncLoop()
            local needed = folder ~= nil
                and ((not opts.hide.dist) or countEntries() > HIGHLIGHT_BUDGET)
            if not needed then
                if stopLoop then stopLoop() stopLoop = nil end
            elseif not stopLoop then
                local alive = true
                stopLoop = function() alive = false end
                task.spawn(function()
                    local ticks = 0
                    while alive do
                        if not opts.hide.dist then pcall(updateDistances) end
                        ticks = ticks + 1
                        if ticks % 4 == 0 then pcall(rebalance) end
                        task.wait(0.125)
                    end
                end)
            end
        end

        syncAll = function()
            rebalance()
            syncLoop()
        end

        local C = {}

        function C.start()
            if folder then return end
            folder = new("Folder", { Name = "ElyseraESP" }, GuiRoot)
            for _, p in ipairs(Players:GetPlayers()) do track(p) end
            conns[1] = Players.PlayerAdded:Connect(track)
            conns[2] = Players.PlayerRemoving:Connect(function(p)
                if trackers[p] then
                    trackers[p].destroy()
                    trackers[p] = nil
                end
            end)
            conns[3] = LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
                for p, e in pairs(entries) do refreshColor(p, e) end
            end)
            syncAll()
        end

        function C.stop()
            stopping = true
            if stopLoop then stopLoop() stopLoop = nil end
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            for p, t in pairs(trackers) do
                t.destroy()
                trackers[p] = nil
            end
            if folder then folder:Destroy() folder = nil end
            hlCount, stopping = 0, false
        end

        function C.refreshStyle()
            if not folder then return end
            for p, e in pairs(entries) do refreshColor(p, e) end
            syncLoop()
            if not opts.hide.dist then updateDistances() end
        end

        return C
    end

    function Features.CreateEsp(parent)
        local Card = CreateCard(parent, "EspPlayer", 10, 10, 10)

        local Switch, Set = CreateToggleOption(Card, "Esp Player", 40)
        Switch.Parent.LayoutOrder = 1
        Switch.Parent.BackgroundColor3 = Theme.PanelAlt

        local controller
        local opts, ui = Features.CreateEspOptions(Card, function()
            if controller then controller.refreshStyle() end
        end)
        controller = Features.CreateEspController(opts)
        ui.setEnabled(false)

        return Core.BindToggle(Switch, Set, {
            start = function()
                controller.start()
                ui.setEnabled(true)
            end,
            stop = function()
                controller.stop()
                ui.setEnabled(false)
            end,
            onReset = ui.reset,
        })
    end

    --// ---------------- Camera / Gravity / Time of Day (same engine: Features.CreateTargetBoost) ----------------
    local FOV_CFG = {
        title = "Field of View", max = 120, min = 1, waitFor = "camera",
        props = { "FieldOfView" },
        getTarget = function() return Workspace.CurrentCamera end,
        watch = function(cb)
            return Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(cb)
        end,
        snapshot = function(cam) return cam.FieldOfView end,
        apply = function(cam, v) if math.abs(cam.FieldOfView - v) > 1e-3 then cam.FieldOfView = v end end,
        restore = function(cam, fov) cam.FieldOfView = fov end,
        getValue = function(cam) return cam.FieldOfView end,
        isApplied = function(cam, v) return math.abs(cam.FieldOfView - v) < 1e-3 end,
        fromSnapshot = function(st) return st end,
        presets = {
            originalPreset(),
            { label = "90",  value = 90 },
            { label = "105", value = 105 },
            { label = "120", value = 120 },
        },
    }

    local ZOOM_CFG = {
        title = "Max Zoom", max = 1000, waitFor = "player",
        props = { "CameraMaxZoomDistance" },
        getTarget = function() return LocalPlayer end,
        snapshot = function(p) return p.CameraMaxZoomDistance end,
        apply = function(p, v) if p.CameraMaxZoomDistance ~= v then p.CameraMaxZoomDistance = v end end,
        restore = function(p, z) p.CameraMaxZoomDistance = z end,
        getValue = function(p) return p.CameraMaxZoomDistance end,
        isApplied = function(p, v) return math.abs(p.CameraMaxZoomDistance - v) < 1e-3 end,
        fromSnapshot = function(st) return st end,
        presets = boostPresets(1000),
    }

    local MIN_ZOOM_CFG = {
        title = "Min Zoom", max = 1000, min = 0.5, waitFor = "player",
        props = { "CameraMinZoomDistance" },
        getTarget = function() return LocalPlayer end,
        snapshot = function(p) return p.CameraMinZoomDistance end,
        apply = function(p, v) if p.CameraMinZoomDistance ~= v then p.CameraMinZoomDistance = v end end,
        restore = function(p, z) p.CameraMinZoomDistance = z end,
        getValue = function(p) return p.CameraMinZoomDistance end,
        isApplied = function(p, v) return math.abs(p.CameraMinZoomDistance - v) < 1e-3 end,
        fromSnapshot = function(st) return st end,
        presets = {
            originalPreset(),
            { label = "0.5", value = 0.5 },
            { label = "5",   value = 5 },
            { label = "15",  value = 15 },
        },
    }

    local TIME_CFG = {
        title = "Time of Day", max = 24, min = 0, waitFor = "lighting",
        props = { "ClockTime" },
        getTarget = function() return Lighting end,
        snapshot = function(l) return l.ClockTime end,
        apply = function(l, v)
            local ct = v % 24
            if math.abs(l.ClockTime - ct) > 1e-3 then l.ClockTime = ct end
        end,
        restore = function(l, ct) l.ClockTime = ct end,
        getValue = function(l) return l.ClockTime end,
        isApplied = function(l, v) return math.abs(l.ClockTime - (v % 24)) < 1e-2 end,
        fromSnapshot = function(st) return st end,
        presets = {
            originalPreset(),
            { label = "Dawn",  value = 6 },
            { label = "Noon",  value = 12 },
            { label = "Dusk",  value = 18 },
            { label = "Night", value = 0 },
        },
    }

    local GRAVITY_CFG = {
        title = "Gravity", max = 500, waitFor = "workspace",
        props = { "Gravity" },
        getTarget = function() return Workspace end,
        snapshot = function(w) return w.Gravity end,
        apply = function(w, v) if math.abs(w.Gravity - v) > 1e-3 then w.Gravity = v end end,
        restore = function(w, g) w.Gravity = g end,
        getValue = function(w) return w.Gravity end,
        isApplied = function(w, v) return math.abs(w.Gravity - v) < 1e-3 end,
        fromSnapshot = function(st) return st end,
        presets = {
            originalPreset(),
            { label = '<font size="20">×</font>0.5',  value = function(o) return o and o * 0.5 end },
            { label = '<font size="20">×</font>0.25', value = function(o) return o and o * 0.25 end },
            { label = "Zero", value = 0 },
        },
    }

    --// ---------------- Anti AFK ----------------
    function Features.CreateAntiAfk(parent)
        local row = Core.CreateToggleRow(parent, "Anti AFK")
        local badge = Core.CreateStatusBadge(row)
        local conn, resets = nil, 0

        local function start()
            local VirtualUser = game:GetService("VirtualUser")
            resets = 0
            conn = LocalPlayer.Idled:Connect(function()
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.zero)
                end)
                resets = resets + 1
                badge.set("active", "Idle timer reset" .. Core.DOT .. resets .. (resets == 1 and " time" or " times"))
            end)
            badge.set("active", "Protected from idle kick")
        end

        local function stop()
            if conn then conn:Disconnect() conn = nil end
            badge.set("off")
        end

        return Core.BindToggle(row.Switch, row.Set, { start = start, stop = stop, badge = badge })
    end

    --// ---------------- Anti Void ----------------
    function Features.CreateAntiVoid(parent)
        local row = Core.CreateToggleRow(parent, "Anti Void")
        local badge = Core.CreateStatusBadge(row)
        local tracker, rescues = nil, 0

        local function voidLine()
            local h = Workspace.FallenPartsDestroyHeight
            if h ~= h or h < -10000 then h = -10000 end
            return h + 80
        end

        local function showStatus()
            badge.set("active", rescues == 0 and "Watching"
                or ("Rescued " .. rescues .. (rescues == 1 and " time" or " times")))
        end

        local function start()
            rescues = 0
            badge.set("waiting", "Waiting for character")
            tracker = Core.TrackCharacter(LocalPlayer, function(_, hum, root)
                local safe, lastSample, cooldown = nil, 0, 0
                if hum.FloorMaterial ~= Enum.Material.Air then safe = root.CFrame end
                showStatus()

                local conn = RunService.Heartbeat:Connect(function()
                    if hum.Health <= 0 or not root.Parent then return end
                    local now = os.clock()
                    if root.Position.Y < voidLine() then
                        if safe and now >= cooldown then
                            cooldown = now + 1
                            root.CFrame = safe + Vector3.new(0, 4, 0)
                            root.AssemblyLinearVelocity = Vector3.zero
                            root.AssemblyAngularVelocity = Vector3.zero
                            rescues = rescues + 1
                            showStatus()
                        end
                    elseif now - lastSample > 0.2 then
                        lastSample = now
                        if hum.FloorMaterial ~= Enum.Material.Air then safe = root.CFrame end
                    end
                end)
                return function() conn:Disconnect() end
            end, { onDied = true })
        end

        local function stop()
            if tracker then tracker.destroy() tracker = nil end
            badge.set("off")
        end

        return Core.BindToggle(row.Switch, row.Set, { start = start, stop = stop, badge = badge })
    end

    --// ---------------- Click Teleport ----------------
    function Features.CreateClickTp(parent)
        local row = Core.CreateToggleRow(parent, "Click Teleport")
        local badge = Core.CreateStatusBadge(row)
        local conns = {}
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.IgnoreWater = true

        local hasTouch, hasKeys = UserInputService.TouchEnabled, UserInputService.KeyboardEnabled
        local hint = (hasTouch and not hasKeys) and "Tap the ground to teleport"
            or (hasTouch and "Ctrl + click or tap the ground" or "Hold Ctrl + click to teleport")

        local function teleportAlong(ray)
            local char, hum, root = LocalPlayer.Character, Core.GetHumanoid(), Core.GetRoot()
            if not (char and hum and root) or hum.Health <= 0 then
                badge.flash("No character to move", 1.5, "invalid")
                return
            end
            params.FilterDescendantsInstances = { char }
            local hit = Workspace:Raycast(ray.Origin, ray.Direction * 3000, params)
            if not hit then return end

            local lift = math.max(hum.HipHeight + root.Size.Y / 2, 3)
            local push = Vector3.new(hit.Normal.X, 0, hit.Normal.Z) * 1.5
            local pos = hit.Position + push + Vector3.new(0, lift, 0)
            local facing = root.CFrame - root.CFrame.Position
            if Core.TeleportTo(CFrame.new(pos) * facing) then
                badge.flash("Teleported", 1, "active")
            end
        end

        local function ctrlDown()
            return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
                or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
        end

        local function start()
            conns[1] = UserInputService.InputBegan:Connect(function(input, processed)
                if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 or not ctrlDown() then
                    return
                end
                local cam = Workspace.CurrentCamera
                if not cam then return end
                local m = UserInputService:GetMouseLocation()
                teleportAlong(cam:ViewportPointToRay(m.X, m.Y))
            end)
            if hasTouch then
                conns[2] = UserInputService.TouchTapInWorld:Connect(function(pos, processedByUI)
                    if processedByUI then return end
                    local cam = Workspace.CurrentCamera
                    if not cam then return end
                    teleportAlong(cam:ScreenPointToRay(pos.X, pos.Y))
                end)
            end
            badge.set("active", hint)
        end

        local function stop()
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            badge.set("off")
        end

        return Core.BindToggle(row.Switch, row.Set, { start = start, stop = stop, badge = badge })
    end

    --// ---------------- Hide Players ----------------
    function Features.CreateHidePlayers(parent)
        local row = Core.CreateToggleRow(parent, "Hide Players")
        local badge = Core.CreateStatusBadge(row)
        local trackers, conns, hidden = {}, {}, 0

        local function status()
            if hidden == 0 then
                badge.set("active", "Active")
            else
                badge.set("active", "Hiding " .. hidden .. (hidden == 1 and " player" or " players"))
            end
        end

        local function track(p)
            if p == LocalPlayer or trackers[p] then return end
            trackers[p] = Core.TrackCharacter(p, function(char, hum)
                local parts, decals = {}, {}
                local nameMode = hum.DisplayDistanceType

                local function hide(inst)
                    if inst:IsA("BasePart") then
                        if parts[inst] == nil then parts[inst] = inst.LocalTransparencyModifier end
                        inst.LocalTransparencyModifier = 1
                    elseif inst:IsA("Decal") then
                        if decals[inst] == nil then decals[inst] = inst.Transparency end
                        inst.Transparency = 1
                    end
                end

                hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                for _, d in ipairs(char:GetDescendants()) do hide(d) end
                local added = char.DescendantAdded:Connect(hide)

                hidden = hidden + 1
                status()
                return function()
                    added:Disconnect()
                    for inst, orig in pairs(parts) do
                        if inst.Parent then inst.LocalTransparencyModifier = orig end
                    end
                    for inst, t in pairs(decals) do
                        if inst.Parent then inst.Transparency = t end
                    end
                    if hum.Parent then hum.DisplayDistanceType = nameMode end
                    hidden = math.max(0, hidden - 1)
                    status()
                end
            end)
        end

        local function start()
            hidden = 0
            for _, p in ipairs(Players:GetPlayers()) do track(p) end
            conns[1] = Players.PlayerAdded:Connect(track)
            conns[2] = Players.PlayerRemoving:Connect(function(p)
                local t = trackers[p]
                if t then
                    t.destroy()
                    trackers[p] = nil
                end
            end)
            status()
        end

        local function stop()
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            for p, t in pairs(trackers) do
                t.destroy()
                trackers[p] = nil
            end
            hidden = 0
            badge.set("off")
        end

        return Core.BindToggle(row.Switch, row.Set, { start = start, stop = stop, badge = badge })
    end

    --// ---------------- Quick actions: Back / Unstuck / Respawn ----------------
    function Features.CreateQuickActions(parent, order)
        local Card = CreateCard(parent, "QuickActions", 10, 12, 12)
        Card.LayoutOrder = order

        Core.Label(Card, {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 16),
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            TextColor3 = Theme.SubText,
            Text = "QUICK ACTIONS",
        })

        local Grid = new("Frame", {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundTransparency = 1,
        }, Card)
        new("UIGridLayout", {
            CellSize = UDim2.new(1 / 3, -6, 1, 0),
            CellPadding = UDim2.fromOffset(9, 0),
            SortOrder = Enum.SortOrder.LayoutOrder,
            FillDirectionMaxCells = 3,
        }, Grid)

        local back    = Core.CreateButton(Grid, "Back",    { order = 1, textSize = 13, radius = 8 })
        local unstuck = Core.CreateButton(Grid, "Unstuck", { order = 2, textSize = 13, radius = 8 })
        local respawn = Core.CreateButton(Grid, "Respawn", { order = 3, textSize = 13, radius = 8 })

        back.setEnabled(Core.History.cf ~= nil)
        Core.History.listeners[#Core.History.listeners + 1] = function()
            back.setEnabled(Core.History.cf ~= nil)
        end
        back.onClick(function()
            if not Core.GoBack() then back.flash("No character", 1.2, true) end
        end)

        unstuck.onClick(function()
            local root, hum = Core.GetRoot(), Core.GetHumanoid()
            if not (root and hum) then
                unstuck.flash("No character", 1.2, true)
                return
            end
            hum.Sit = false
            root.CFrame = root.CFrame + Vector3.new(0, 8, 0)
            root.AssemblyLinearVelocity = Vector3.zero
            hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            unstuck.flash("Done", 1)
        end)

        local armedUntil = 0
        respawn.onClick(function()
            if os.clock() >= armedUntil then
                armedUntil = os.clock() + 2
                respawn.flash("Tap again", 2, true)
                return
            end
            armedUntil = 0
            local char, hum = LocalPlayer.Character, Core.GetHumanoid()
            if not char then
                respawn.flash("No character", 1.2, true)
                return
            end
            if hum then hum.Health = 0 end
            pcall(function() char:BreakJoints() end)
        end)

        return Card
    end

    --// ---------------- Position (Teleport to XYZ & Copy Position) ----------------
    function Features.CreatePositionCard(parent)
        local Card = CreateCard(parent, "PositionXYZ", 12, 12, 12)

        local Header = new("Frame", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundTransparency = 1,
        }, Card)
        local PosLabel = Core.Label(Header, {
            Size = UDim2.new(1, -90, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "XYZ: --",
        })
        local CopyBtn = Core.CreateButton(Header, "Copy XYZ", {
            anchor = Vector2.new(1, 0.5),
            position = UDim2.new(1, 0, 0.5, 0),
            size = UDim2.fromOffset(82, 26),
            textSize = 12,
        })

        local InputRow = new("Frame", {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundTransparency = 1,
        }, Card)
        local Box, BoxStroke = Core.CreateInput(InputRow, "X, Y, Z (e.g. 120, 50, -30)", {
            size = UDim2.new(1, -76, 1, 0),
        })
        local TpBtn = Core.CreateButton(InputRow, "TP", {
            anchor = Vector2.new(1, 0.5),
            position = UDim2.new(1, 0, 0.5, 0),
            size = UDim2.fromOffset(68, 34),
            variant = "accent",
            radius = 6,
        })

        local function currentXyzText()
            local root = Core.GetRoot()
            if not root then return nil end
            local p = root.Position
            return string.format("%d, %d, %d", math.floor(p.X + 0.5), math.floor(p.Y + 0.5), math.floor(p.Z + 0.5))
        end

        CopyBtn.onClick(function()
            local txt = currentXyzText()
            if not txt then
                CopyBtn.flash("No char", 1.2, true)
                return
            end
            local ok = UI.CopyText(txt)
            CopyBtn.flash(ok and "Copied!" or "Failed", 1.2, not ok)
        end)

        local function parseXYZ(s)
            local nums = {}
            for tok in tostring(s or ""):gmatch("[%+%-]?%d+%.?%d*") do
                local n = tonumber(tok)
                if n and n == n and math.abs(n) < 1e7 then
                    nums[#nums + 1] = n
                end
            end
            if #nums >= 3 then return nums[1], nums[2], nums[3] end
            return nil
        end

        local function doTpXYZ()
            local x, y, z = parseXYZ(Box.Text)
            if not x then
                flashStrokeError(BoxStroke)
                TpBtn.flash("Invalid", 1.2, true)
                return
            end
            local root = Core.GetRoot()
            if not root then
                TpBtn.flash("No char", 1.2, true)
                return
            end
            local facing = root.CFrame - root.CFrame.Position
            if Core.TeleportTo(CFrame.new(x, y, z) * facing) then
                TpBtn.flash("Done", 1)
            end
        end

        TpBtn.onClick(doTpXYZ)
        Box.FocusLost:Connect(function(enter)
            if enter and not isLocked() then doTpXYZ() end
        end)

        task.spawn(function()
            while ScreenGui.Parent do
                if LocalTab.Visible then
                    local txt = currentXyzText()
                    PosLabel.Text = "XYZ: " .. (txt or "--")
                end
                task.wait(0.4)
            end
        end)

        return Card
    end

    --// ---------------- Waypoints (with Rename + Export/Import) ----------------
    function Features.CreateWaypoints(parent)
        local dataPath = ctx.dataPath or function(name) return name end
        local FILE, MAX = dataPath("Elysera_Waypoints.json"), 15
        local HttpService = game:GetService("HttpService")
        local canFS = typeof(readfile) == "function" and typeof(writefile) == "function" and typeof(isfile) == "function"
        local placeKey = tostring(game.PlaceId)

        local store = {}
        if canFS then
            pcall(function()
                if isfile(FILE) then
                    local data = HttpService:JSONDecode(readfile(FILE))
                    if type(data) == "table" then store = data end
                end
            end)
        end

        local points = {}
        if type(store[placeKey]) == "table" then
            for _, p in ipairs(store[placeKey]) do
                if #points < MAX and type(p) == "table"
                    and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number" then
                    points[#points + 1] = {
                        n = Core.ClipText(tostring(p.n or "Point"), 24),
                        x = p.x, y = p.y, z = p.z,
                        r = tonumber(p.r) or 0,
                    }
                end
            end
        end
        store[placeKey] = points

        local saveQueued = false
        local function save()
            if not canFS or saveQueued then return end
            saveQueued = true
            task.delay(0.4, function()
                saveQueued = false
                pcall(function() writefile(FILE, HttpService:JSONEncode(store)) end)
            end)
        end

        local Card = CreateCard(parent, "Waypoints", 12, 12, 12)

        local Header = new("Frame", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1,
        }, Card)
        Core.Label(Header, {
            Size = UDim2.new(0.5, 0, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 15,
            Text = "Waypoints",
        })
        local note = Core.CreateNote(Header, {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.fromScale(1, 0),
            Size = UDim2.new(0.5, 0, 1, 0),
        })

        local InputRow = new("Frame", {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundTransparency = 1,
        }, Card)
        local Box, BoxStroke = Core.CreateInput(InputRow, "Name or exported JSON", {
            size = UDim2.new(1, -96, 1, 0),
        })
        local SaveBtn = Core.CreateButton(InputRow, "Save here", {
            anchor = Vector2.new(1, 0.5),
            position = UDim2.new(1, 0, 0.5, 0),
            size = UDim2.fromOffset(88, 34),
            variant = "accent",
            radius = 6,
        })

        -- Export / Import bar for waypoints
        local ToolRow = new("Frame", {
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundTransparency = 1,
        }, Card)
        list(ToolRow, 8, { FillDirection = Enum.FillDirection.Horizontal })
        local ExportBtn = Core.CreateButton(ToolRow, "Export", {
            order = 1,
            size = UDim2.new(0.5, -4, 1, 0),
            textSize = 12,
        })
        local ImportBtn = Core.CreateButton(ToolRow, "Import", {
            order = 2,
            size = UDim2.new(0.5, -4, 1, 0),
            textSize = 12,
        })

        local List = new("Frame", {
            LayoutOrder = 4,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, Card)
        list(List, 6)

        local Empty = Core.Label(List, {
            LayoutOrder = 0,
            Size = UDim2.new(1, 0, 0, 32),
            TextSize = 12,
            TextColor3 = Theme.SubText,
            TextWrapped = true,
            Text = "No waypoints yet. Stand where you want to come back to and tap Save here. Tap a waypoint name to rename it.",
        })

        if not canFS then
            Core.Label(Card, {
                LayoutOrder = 5,
                Size = UDim2.new(1, 0, 0, 28),
                TextSize = 11,
                TextColor3 = Theme.SubText,
                TextWrapped = true,
                Text = "This executor has no file access, so waypoints are kept only until you leave the game.",
            })
        end

        local rebuild

        local function makeRow(p)
            local Row = new("Frame", {
                Name = "Waypoint",
                LayoutOrder = #points - table.find(points, p) + 1,
                Size = UDim2.new(1, 0, 0, 42),
                BackgroundColor3 = Theme.PanelAlt,
                BorderSizePixel = 0,
            }, List)
            corner(Row, 6)
            stroke(Row)

            -- Editable waypoint name (tap or click to rename inline)
            local NameBox = new("TextBox", {
                Position = UDim2.fromOffset(10, 4),
                Size = UDim2.new(1, -104, 0, 20),
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ClearTextOnFocus = false,
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                Text = p.n,
            }, Row)
            NameBox.FocusLost:Connect(function()
                local nextName = Core.ClipText(Core.Trim(NameBox.Text), 24)
                if nextName == "" then
                    NameBox.Text = p.n
                    return
                end
                if nextName ~= p.n then
                    p.n = nextName
                    NameBox.Text = nextName
                    save()
                    note.flash("Renamed to " .. nextName)
                end
            end)

            Core.Label(Row, {
                Position = UDim2.fromOffset(10, 23),
                Size = UDim2.new(1, -104, 0, 14),
                TextSize = 11,
                TextColor3 = Theme.SubText,
                Text = string.format("%d, %d, %d", math.floor(p.x + 0.5), math.floor(p.y + 0.5), math.floor(p.z + 0.5)),
            })

            local go = Core.CreateButton(Row, "Go", {
                anchor = Vector2.new(1, 0.5),
                position = UDim2.new(1, -44, 0.5, 0),
                size = UDim2.fromOffset(44, 26),
                variant = "accent",
            })
            local del = Core.CreateButton(Row, "×", {
                anchor = Vector2.new(1, 0.5),
                position = UDim2.new(1, -8, 0.5, 0),
                size = UDim2.fromOffset(30, 26),
                textSize = 18,
            })
            del.Button.TextColor3 = Theme.Danger

            go.onClick(function()
                local cf = CFrame.new(p.x, p.y, p.z) * CFrame.Angles(0, math.rad(p.r), 0)
                if Core.TeleportTo(cf) then
                    note.flash("Teleported to " .. p.n)
                else
                    note.flash("No character", true)
                end
            end)
            del.onClick(function()
                local idx = table.find(points, p)
                if idx then table.remove(points, idx) end
                save()
                rebuild()
                note.flash("Deleted " .. p.n)
            end)
        end

        rebuild = function()
            for _, c in ipairs(List:GetChildren()) do
                if c.Name == "Waypoint" then c:Destroy() end
            end
            for _, p in ipairs(points) do makeRow(p) end
            Empty.Visible = (#points == 0)
            note.setBase(#points .. "/" .. MAX)
        end

        local function saveHere()
            local root = Core.GetRoot()
            if not root then
                note.flash("No character", true)
                return
            end
            if #points >= MAX then
                note.flash("Limit reached (" .. MAX .. ")", true)
                return
            end
            local name = Core.ClipText(Core.Trim(Box.Text), 24)
            if name == "" then
                local taken = {}
                for _, p in ipairs(points) do taken[p.n] = true end
                local n = 1
                while taken["Point " .. n] do n = n + 1 end
                name = "Point " .. n
            end
            local pos = root.Position
            local _, yaw = root.CFrame:ToOrientation()
            for _, v in ipairs({ pos.X, pos.Y, pos.Z, yaw }) do
                if v ~= v or math.abs(v) == math.huge then
                    note.flash("Invalid position", true)
                    return
                end
            end
            points[#points + 1] = { n = name, x = pos.X, y = pos.Y, z = pos.Z, r = math.deg(yaw) }
            Box.Text = ""
            save()
            rebuild()
            note.flash("Saved " .. name)
        end

        ExportBtn.onClick(function()
            if #points == 0 then
                note.flash("Nothing to export", true)
                return
            end
            local ok, json = pcall(HttpService.JSONEncode, HttpService, {
                format = "Elysera-Waypoints",
                placeId = game.PlaceId,
                points = points,
            })
            if not ok then
                note.flash("Export failed", true)
                return
            end
            local copied = UI.CopyText(json)
            if not copied then Box.Text = json end
            ExportBtn.flash(copied and "Copied!" or "In box", 1.2)
            note.flash(copied and "Copied to clipboard" or "Copied to input box")
        end)

        ImportBtn.onClick(function()
            local raw = Core.Trim(Box.Text)
            if raw == "" and typeof(getclipboard) == "function" then
                local okC, clip = pcall(getclipboard)
                if okC and type(clip) == "string" then raw = Core.Trim(clip) end
            end
            local okDec, data = pcall(HttpService.JSONDecode, HttpService, raw)
            local listIn = (okDec and type(data) == "table") and (data.points or data) or nil
            if type(listIn) ~= "table" then
                flashStrokeError(BoxStroke)
                note.flash("Invalid waypoint JSON", true)
                return
            end
            local added = 0
            for _, p in ipairs(listIn) do
                if #points >= MAX then break end
                if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number" then
                    points[#points + 1] = {
                        n = Core.ClipText(tostring(p.n or "Point"), 24),
                        x = p.x, y = p.y, z = p.z,
                        r = tonumber(p.r) or 0,
                    }
                    added = added + 1
                end
            end
            if added == 0 then
                note.flash("No waypoints imported", true)
                return
            end
            Box.Text = ""
            save()
            rebuild()
            ImportBtn.flash("+" .. added, 1.2)
            note.flash("Imported " .. added .. " waypoint(s)")
        end)

        SaveBtn.onClick(saveHere)
        Box.FocusLost:Connect(function(enter)
            if enter and not isLocked() then saveHere() end
        end)

        rebuild()
        return Card
    end

    --// ---------------- Players: find, teleport, view ----------------
    function Features.CreatePlayers(parent)
        local ROWS = 6
        local Card = CreateCard(parent, "PlayersCard", 12, 12, 12)

        local Header = new("Frame", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
        }, Card)
        local Title = Core.Label(Header, {
            Size = UDim2.new(1, -72, 1, 0),
            Font = Enum.Font.GothamBold,
            TextSize = 15,
            RichText = true,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = "Players",
        })
        local StopTop = Core.CreateButton(Header, "Stop", {
            anchor = Vector2.new(1, 0.5),
            position = UDim2.new(1, 0, 0.5, 0),
            size = UDim2.fromOffset(64, 24),
            variant = "accent",
            textSize = 12,
        })
        StopTop.Button.Visible = false

        local Search = Core.CreateInput(Card, "Search players", { order = 2, size = UDim2.new(1, 0, 0, 32) })

        local List = new("Frame", {
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
        }, Card)
        list(List, 6)
        local Empty = Core.Label(List, {
            LayoutOrder = 0,
            Size = UDim2.new(1, 0, 0, 24),
            TextSize = 12,
            TextColor3 = Theme.SubText,
            Text = "",
            Visible = false,
        })
        local More = Core.Label(Card, {
            LayoutOrder = 4,
            Size = UDim2.new(1, 0, 0, 16),
            TextSize = 11,
            TextColor3 = Theme.SubText,
            Text = "",
            Visible = false,
        })

        local Hud = new("Frame", {
            Name = "ViewHud",
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 56),
            Size = UDim2.fromOffset(0, 38),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            Visible = false,
            ZIndex = 30,
        }, ScreenGui)
        corner(Hud, 19)
        stroke(Hud, Theme.AccentPink, 1.5)
        padding(Hud, 16, 6, 0, 0)
        list(Hud, 10, {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
        })
        local HudText = Core.Label(Hud, {
            LayoutOrder = 1,
            Size = UDim2.fromOffset(0, 38),
            AutomaticSize = Enum.AutomaticSize.X,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            RichText = true,
            ZIndex = 31,
            Text = "",
        })
        local HudStop = Core.CreateButton(Hud, "Stop", {
            order = 2,
            size = UDim2.fromOffset(60, 26),
            variant = "accent",
            radius = 13,
            textSize = 12,
        })
        HudStop.Button.ZIndex = 31

        local viewing, othersCount = nil, 0
        local viewConns, listeners = {}, {}
        local savedSubject, viewToken = nil, 0
        local rows, refreshQueued = {}, false
        local refresh

        local lastOn = false
        local function notify()
            local on = viewing ~= nil
            if on == lastOn then return end
            lastOn = on
            for _, fn in ipairs(listeners) do pcall(fn, on) end
        end

        local function renderTitle()
            if viewing then
                local text = '<font color="#' .. Theme.Sakura:ToHex() .. '">Viewing</font>'
                    .. Core.DOT .. Core.EscapeRich(viewing.DisplayName)
                Title.Text, HudText.Text = text, text
            else
                Title.Text = "Players" .. Core.DOT .. othersCount
            end
            StopTop.Button.Visible = viewing ~= nil
            Hud.Visible = viewing ~= nil
        end

        ScreenGui:GetAttributeChangedSignal("Theme"):Connect(function() renderTitle() end)

        local function stopView(keepCamera)
            if not viewing then return end
            viewing = nil
            viewToken = viewToken + 1
            for _, c in ipairs(viewConns) do c:Disconnect() end
            table.clear(viewConns)
            if not keepCamera then
                local cam = Workspace.CurrentCamera
                if cam then
                    local subject = savedSubject
                    if not (subject and subject.Parent) then subject = Core.GetHumanoid() end
                    if subject then cam.CameraSubject = subject end
                end
            end
            savedSubject = nil
            renderTitle()
            refresh()
            notify()
        end

        local function startView(p)
            local cam = Workspace.CurrentCamera
            if not cam or p.Parent ~= Players then return end
            if viewing then
                for _, c in ipairs(viewConns) do c:Disconnect() end
                table.clear(viewConns)
            else
                savedSubject = cam.CameraSubject
            end
            viewing = p
            viewToken = viewToken + 1
            local my = viewToken

            local function point()
                task.spawn(function()
                    local char = p.Character
                    local hum = char and (char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5))
                    if my ~= viewToken or not hum then return end
                    local c = Workspace.CurrentCamera
                    if c then c.CameraSubject = hum end
                end)
            end
            point()

            viewConns[1] = p.CharacterAdded:Connect(point)
            viewConns[2] = LocalPlayer.CharacterAdded:Connect(function()
                stopView(true)
            end)
            viewConns[3] = Players.PlayerRemoving:Connect(function(who)
                if who == p then stopView() end
            end)
            viewConns[4] = cam:GetPropertyChangedSignal("CameraSubject"):Connect(function()
                local mine = Core.GetHumanoid()
                if mine and cam.CameraSubject == mine then stopView(true) end
            end)

            renderTitle()
            refresh()
            notify()
        end

        local function teleportToPlayer(p)
            local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if not root then return false end
            return Core.TeleportTo(root.CFrame * CFrame.new(0, 0, 4))
        end

        local function makeRow(i)
            local Row = new("Frame", {
                Name = "PlayerRow",
                LayoutOrder = i,
                Size = UDim2.new(1, 0, 0, 42),
                BackgroundColor3 = Theme.PanelAlt,
                BorderSizePixel = 0,
                Visible = false,
            }, List)
            corner(Row, 6)
            stroke(Row)

            local nameL = Core.Label(Row, {
                Position = UDim2.fromOffset(10, 5),
                Size = UDim2.new(1, -132, 0, 18),
                Font = Enum.Font.GothamBold,
                TextSize = 13,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            local userL = Core.Label(Row, {
                Position = UDim2.fromOffset(10, 23),
                Size = UDim2.new(1, -132, 0, 14),
                TextSize = 11,
                TextColor3 = Theme.SubText,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            local tp = Core.CreateButton(Row, "TP", {
                anchor = Vector2.new(1, 0.5),
                position = UDim2.new(1, -8, 0.5, 0),
                size = UDim2.fromOffset(44, 26),
                variant = "accent",
            })
            local view = Core.CreateButton(Row, "View", {
                anchor = Vector2.new(1, 0.5),
                position = UDim2.new(1, -58, 0.5, 0),
                size = UDim2.fromOffset(54, 26),
            })

            local r = { frame = Row, name = nameL, user = userL, view = view, tp = tp, player = nil }
            tp.onClick(function()
                if not r.player then return end
                if not teleportToPlayer(r.player) then tp.flash("!", 1, true) end
            end)
            view.onClick(function()
                local p = r.player
                if not p then return end
                if viewing == p then stopView() else startView(p) end
            end)
            rows[i] = r
            return r
        end

        refresh = function()
            refreshQueued = false
            local q = Core.Trim(Search.Text):lower()
            local found, total = {}, 0
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Parent == Players then
                    total = total + 1
                    local dn = p.DisplayName:lower()
                    if q == "" or dn:find(q, 1, true) or p.Name:lower():find(q, 1, true) then
                        found[#found + 1] = { p = p, key = dn }
                    end
                end
            end
            table.sort(found, function(a, b)
                local av, bv = a.p == viewing, b.p == viewing
                if av ~= bv then return av end
                if a.key ~= b.key then return a.key < b.key end
                return a.p.UserId < b.p.UserId
            end)
            othersCount = total

            local shown = math.min(#found, ROWS)
            for i = 1, ROWS do
                local r = rows[i]
                if i <= shown then
                    r = r or makeRow(i)
                    local p = found[i].p
                    local on = (p == viewing)
                    r.player = p
                    r.name.Text = p.DisplayName
                    r.user.Text = "@" .. p.Name
                    r.view.setText(on and "Stop" or "View")
                    r.view.setActive(on)
                    r.frame.Visible = true
                elseif r then
                    r.player = nil
                    r.frame.Visible = false
                end
            end

            Empty.Visible = (#found == 0)
            if #found == 0 then
                Empty.Text = (total == 0) and "No other players in this server." or "No player matches your search."
            end
            More.Visible = (#found > shown)
            if #found > shown then
                More.Text = string.format("Showing %d of %d · type a name to find the rest", shown, #found)
            end
            renderTitle()
        end

        local function queueRefresh()
            if refreshQueued then return end
            refreshQueued = true
            task.defer(refresh)
        end

        StopTop.onClick(function() stopView() end)
        HudStop.onClick(function() stopView() end)

        local conns = {
            Players.PlayerAdded:Connect(queueRefresh),
            Players.PlayerRemoving:Connect(function() task.delay(0.25, queueRefresh) end),
            Search:GetPropertyChangedSignal("Text"):Connect(queueRefresh),
        }
        Core.OnDestroy(function()
            for _, c in ipairs(conns) do c:Disconnect() end
        end)

        local handle = {
            isOn = function() return viewing ~= nil end,
            stop = function() stopView() end,
            onChanged = function(fn) listeners[#listeners + 1] = fn end,
        }
        Core.Register(handle)

        refresh()
        return handle
    end

    --// ---------------- Reset All ----------------
    function Features.CreateResetAll(parent, order)
        local btn = new("TextButton", {
            LayoutOrder = order,
            Size = UDim2.new(1, 0, 0, 40),
            Text = "Reset All",
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Theme.Text,
        }, parent)
        corner(btn, 8)
        stroke(btn)

        local token = 0
        btn.Activated:Connect(function()
            if isLocked() then return end
            local n = Core.ResetAll()
            token = token + 1
            local my = token
            btn.Text = (n > 0) and ("Reset " .. n .. (n == 1 and " feature" or " features")) or "Nothing to reset"
            task.delay(1.5, function()
                if my == token and btn.Parent then btn.Text = "Reset All" end
            end)
        end)
        return btn
    end

    --// =====================================================
    --//  BUILD UI
    --// =====================================================
    Features.CreateQuickActions(LocalTab, 1)

    local Movement = Core.CreateSectionGroup(LocalTab, "Movement", 2, {
        subtitle = "Speed, jump, gravity, noclip, fly",
    })
    local Teleport = Core.CreateSectionGroup(LocalTab, "Teleport", 3, {
        subtitle = "Click teleport, XYZ, waypoints, players", collapsed = true,
    })
    local Camera = Core.CreateSectionGroup(LocalTab, "Camera", 4, {
        subtitle = "Field of view, zoom distance, freecam", collapsed = true,
    })
    local Visual = Core.CreateSectionGroup(LocalTab, "Visual", 5, {
        subtitle = "ESP, hide players, full bright, time of day", collapsed = true,
    })
    local Safety = Core.CreateSectionGroup(LocalTab, "Safety", 6, {
        subtitle = "Anti AFK and Anti Void", collapsed = true,
    })

    Movement.trackSwitch(Features.CreateTargetBoost(Movement.Body, SPEED_CFG))
    Movement.trackSwitch(Features.CreateTargetBoost(Movement.Body, JUMP_CFG))
    Movement.trackSwitch(Features.CreateTargetBoost(Movement.Body, GRAVITY_CFG))
    Movement.trackSwitch(Features.CreateInfiniteJump(Movement.Body))
    Movement.trackSwitch(Features.CreateNoclip(Movement.Body))
    Movement.trackSwitch(Features.CreateFly(Movement.Body))

    Teleport.trackSwitch(Features.CreateClickTp(Teleport.Body))
    Features.CreatePositionCard(Teleport.Body)
    Features.CreateWaypoints(Teleport.Body)
    Teleport.trackSwitch(Features.CreatePlayers(Teleport.Body))

    Camera.trackSwitch(Features.CreateTargetBoost(Camera.Body, FOV_CFG))
    Camera.trackSwitch(Features.CreateTargetBoost(Camera.Body, ZOOM_CFG))
    Camera.trackSwitch(Features.CreateTargetBoost(Camera.Body, MIN_ZOOM_CFG))
    Camera.trackSwitch(Features.CreateFreecam(Camera.Body))

    Visual.trackSwitch(Features.CreateEsp(Visual.Body))
    Visual.trackSwitch(Features.CreateHidePlayers(Visual.Body))
    Visual.trackSwitch(Features.CreateFullBright(Visual.Body))
    Visual.trackSwitch(Features.CreateTargetBoost(Visual.Body, TIME_CFG))

    Safety.trackSwitch(Features.CreateAntiAfk(Safety.Body))
    Safety.trackSwitch(Features.CreateAntiVoid(Safety.Body))

    Features.CreateResetAll(LocalTab, 7)

    -- GUI destroyed: reuse the Reset All path to clean everything up, then release global connections
    ScreenGui.Destroying:Connect(function()
        Core.ResetAll()
        for _, fn in ipairs(Core.hooks) do pcall(fn) end
    end)
end
