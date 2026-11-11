--// ##########################################################################################
--// ##                                                                                      ##
--// ##   MANDATORY: USE ENGLISH (US) ONLY IN THIS FILE                                      ##
--// ##   Every comment, UI text, message and name here MUST be written in English (US).     ##
--// ##   Never add any other language to this file. Keep it English (US) on every edit.     ##
--// ##                                                                                      ##
--// ##########################################################################################

--// ================= FPS TAB (module) =================

return function(ctx)
    local FPSTab, Theme, ScreenGui = ctx.Tab, ctx.Theme, ctx.ScreenGui
    local LocalPlayer, CoreGui, MainUI = ctx.LocalPlayer, ctx.CoreGui, ctx.MainUI
    local GuiRoot = ctx.GuiRoot or CoreGui
    local UI = assert(ctx.UI, "FPS.lua needs ctx.UI")
    local Saved, saveSettings = ctx.Saved, ctx.saveSettings
    local ANCHOR_CENTER = ctx.ANCHOR_CENTER
    local EASE_QUAD, DIR_IN, DIR_OUT = ctx.EASE_QUAD, ctx.DIR_IN, ctx.DIR_OUT
    local new, corner, stroke, padding = ctx.new, ctx.corner, ctx.stroke, ctx.padding
    local list, label, tween, pressScale = ctx.list, ctx.label, ctx.tween, ctx.pressScale
    local FunctionScroll, CreateToggleOption = ctx.FunctionScroll, ctx.CreateToggleOption
    local isLocked, setLocked = ctx.isLocked, ctx.setLocked

    local Players          = ctx.Players or game:GetService("Players")
    local RunService       = ctx.RunService or game:GetService("RunService")
    local UserInputService = ctx.UserInputService or game:GetService("UserInputService")
    local Lighting         = game:GetService("Lighting")
    local StarterGui       = game:GetService("StarterGui")
    local SoundService     = game:GetService("SoundService")
    local TextService      = game:GetService("TextService")
    local Stats            = game:GetService("Stats")

    local function setProp(inst, prop, value)
        return pcall(function() inst[prop] = value end)
    end

    --// ================= LIFECYCLE =================
    local destroyed = false
    local teardown = {}
    local function onDestroy(fn) teardown[#teardown + 1] = fn end

    ScreenGui.Destroying:Connect(function()
        destroyed = true
        for _, fn in ipairs(teardown) do pcall(fn) end
    end)

    --// ================= SAVED CHOICES =================
    local Prefs = {}
    do
        local FILE = "Elysera_Fps.json"
        local data = UI.ReadJson(FILE) or {}
        local queued = false

        function Prefs.get(key) return data[key] end

        function Prefs.pick(key, allowed, default)
            for _, v in ipairs(allowed) do
                if data[key] == v then return v end
            end
            return default
        end

        function Prefs.set(key, value)
            data[key] = value
            if queued then return end
            queued = true
            task.delay(0.3, function()
                queued = false
                UI.WriteJson(FILE, data)
            end)
        end
    end

    --// ================= FPS CAP =================
    local FpsCap = {}
    do
        local COVER_CAP = 15
        local canSet = typeof(setfpscap) == "function"
        local original
        if typeof(getfpscap) == "function" then
            local ok, v = pcall(getfpscap)
            if ok and type(v) == "number" and v > 0 then original = v end
        end

        local userCap, coverCap, afkCap, engaged

        local function apply()
            if not canSet then return end
            local cap = userCap
            if coverCap and (not cap or coverCap < cap) then cap = coverCap end
            if afkCap and (not cap or afkCap < cap) then cap = afkCap end
            if cap then
                engaged = true
                pcall(setfpscap, cap)
            elseif engaged then
                engaged = false
                pcall(setfpscap, original or 60)
            end
        end

        function FpsCap.supported() return canSet end
        function FpsCap.getUser() return userCap end
        function FpsCap.setUser(fps) userCap = fps; apply() end
        function FpsCap.setCover(on) coverCap = (on and (original or userCap)) and COVER_CAP or nil; apply() end
        function FpsCap.setAfk(on) afkCap = on and COVER_CAP or nil; apply() end
        function FpsCap.restore() userCap, coverCap, afkCap = nil, nil, nil; apply() end
    end

    --// ================= MODE SELECTOR (toggle + dropdown) =================
    local createChevron = UI.CreateChevron
    local createSection = UI.CreateSection
    local createModeRow
    do
        local POP_GAP, ITEM_H, POP_PAD = 4, 30, 4
        local BOX_H, ARROW_W, GAP = 26, 28, 6
        local BOX_MIN_W, BOX_MAX_W = 96, 220
        local ROW_TOP = 50

        local function textWidth(text)
            local ok, size = pcall(TextService.GetTextSize, TextService, text, 13,
                Enum.Font.GothamBold, Vector2.new(1000, 100))
            return ok and size.X or #text * 8
        end

        local PopBlocker = new("TextButton", {
            Name = "ModeBlocker",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            Visible = false,
            ZIndex = 15,
        }, MainUI)

        local PopList = new("Frame", {
            Name = "ModeList",
            AnchorPoint = Vector2.new(1, 0),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            Visible = false,
            ZIndex = 16,
        }, MainUI)
        corner(PopList, 10)
        stroke(PopList)

        local PopItems = new("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            ZIndex = 16,
        }, PopList)
        padding(PopItems, POP_PAD, POP_PAD, POP_PAD, POP_PAD)
        list(PopItems, 2)

        local Popup = { open = false, owner = nil, token = 0 }

        local function closePopup()
            if not Popup.open then return end
            Popup.open = false
            Popup.token = Popup.token + 1
            local token = Popup.token
            PopBlocker.Visible = false
            local owner = Popup.owner
            Popup.owner = nil
            if owner then owner.onClosed() end
            tween(PopList, 0.1, { Size = UDim2.fromOffset(PopList.AbsoluteSize.X, 0) }, EASE_QUAD, DIR_IN).Completed:Connect(function()
                if Popup.token == token then PopList.Visible = false end
            end)
        end

        local function openPopup(api)
            if Popup.open or isLocked() then return end
            for _, c in ipairs(PopItems:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end

            local current, maxW = api.getMode(), 0
            for i, m in ipairs(api.modes) do
                maxW = math.max(maxW, textWidth(m))
                local selected = (m == current)
                local Item = new("TextButton", {
                    LayoutOrder = i,
                    Size = UDim2.new(1, 0, 0, ITEM_H),
                    BackgroundColor3 = Theme.Header,
                    BackgroundTransparency = selected and 0 or 1,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = m,
                    Font = Enum.Font.GothamBold,
                    TextSize = 13,
                    TextColor3 = selected and Theme.Sakura or Theme.Text,
                    ZIndex = 17,
                }, PopItems)
                corner(Item, 6)
                if not selected then
                    Item.MouseEnter:Connect(function() tween(Item, 0.12, { BackgroundTransparency = 0.5 }) end)
                    Item.MouseLeave:Connect(function() tween(Item, 0.12, { BackgroundTransparency = 1 }) end)
                end
                Item.Activated:Connect(function()
                    closePopup()
                    api.select(m)
                end)
            end

            local n = #api.modes
            local w = math.max(maxW + 32, 110)
            local h = n * ITEM_H + (n - 1) * 2 + POP_PAD * 2

            local mp, ms = MainUI.AbsolutePosition, MainUI.AbsoluteSize
            local ap, asz = api.Frame.AbsolutePosition, api.Frame.AbsoluteSize
            local x = (ap.X + asz.X) - mp.X
            local y = (ap.Y + asz.Y) - mp.Y + POP_GAP
            if y + h > ms.Y - 6 then y = (ap.Y - mp.Y) - POP_GAP - h end
            y = math.max(y, 4)

            Popup.open, Popup.owner = true, api
            Popup.token = Popup.token + 1
            PopBlocker.Visible = true

            PopList.Size = UDim2.fromOffset(w, 0)
            PopList.Position = UDim2.fromOffset(x, y)
            PopList.Visible = true
            tween(PopList, 0.12, { Size = UDim2.fromOffset(w, h) }, EASE_QUAD, DIR_OUT)
            api.onOpened()
        end

        PopBlocker.Activated:Connect(closePopup)
        FunctionScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(closePopup)
        MainUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(closePopup)
        MainUI:GetPropertyChangedSignal("Visible"):Connect(function()
            if not MainUI.Visible then closePopup() end
        end)
        FPSTab:GetPropertyChangedSignal("Visible"):Connect(function()
            if not FPSTab.Visible then closePopup() end
        end)
        onDestroy(function()
            closePopup()
            PopBlocker:Destroy()
            PopList:Destroy()
        end)

        function createModeRow(parent, title, modes, default, onSelect, hints)
            local Switch, setState = CreateToggleOption(parent, title, ROW_TOP + 34)
            local Frame = Switch.Parent
            Switch.AnchorPoint = Vector2.new(1, 0)
            Switch.Position = UDim2.new(1, -12, 0, (ROW_TOP - 24) / 2)
            local Title = Frame:FindFirstChildOfClass("TextLabel")
            if Title then Title.Size = UDim2.new(1, -80, 0, ROW_TOP) end

            local current = default
            local function boxWidth(text)
                return math.clamp(textWidth(text) + 2 * (ARROW_W + GAP), BOX_MIN_W, BOX_MAX_W)
            end

            local Box = new("Frame", {
                Name = "ModeBox",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, ROW_TOP - 4),
                Size = UDim2.fromOffset(boxWidth(current), BOX_H),
                BackgroundColor3 = Theme.Header,
                BorderSizePixel = 0,
            }, Frame)
            corner(Box, 6)
            stroke(Box)

            local Hint = hints and label(Frame, {
                Name = "Hint",
                Position = UDim2.fromOffset(14, ROW_TOP - 4),
                Size = UDim2.new(1, -(boxWidth(current) + 36), 0, BOX_H),
                Font = Enum.Font.Gotham,
                Text = hints[current] or hints.default or "",
                TextSize = 11,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })

            local ModeText = label(Box, {
                Size = UDim2.fromScale(1, 1),
                Text = current,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })

            local ArrowBtn = new("TextButton", {
                Name = "Arrow",
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -2, 0.5, 0),
                Size = UDim2.fromOffset(ARROW_W, BOX_H - 4),
                BackgroundTransparency = 1,
                Text = "",
                AutoButtonColor = false,
            }, Box)
            pressScale(ArrowBtn, 0.9)

            local Chev = createChevron(ArrowBtn, {
                AnchorPoint = ANCHOR_CENTER,
                Position = UDim2.new(0.5, 0, 0.5, -0.5),
                Size = UDim2.fromOffset(12, 12),
            }, Theme.SubText, 7, 2)

            local api = { Frame = Frame, Switch = Switch, setState = setState, modes = modes }
            function api.getMode() return current end
            function api.setMode(m)
                if m == current then return end
                current = m
                ModeText.Text = m
                tween(Box, 0.15, { Size = UDim2.fromOffset(boxWidth(m), BOX_H) })
                if Hint then
                    Hint.Text = hints[m] or hints.default or ""
                    tween(Hint, 0.15, { Size = UDim2.new(1, -(boxWidth(m) + 36), 0, BOX_H) })
                end
            end
            function api.select(m)
                if m == current then return end
                api.setMode(m)
                if onSelect then onSelect(m) end
            end
            function api.onOpened() tween(Chev, 0.15, { Rotation = 180 }) end
            function api.onClosed() tween(Chev, 0.15, { Rotation = 0 }) end

            ArrowBtn.Activated:Connect(function()
                if not isLocked() then openPopup(api) end
            end)
            return api
        end
    end

    --// ================= SECTIONS =================
    local Optimize  = createSection(FPSTab, "Optimize", 2, { subtitle = "FPS profile, cap, distant players" })
    local ScreenSec = createSection(FPSTab, "Screen", 3, {
        subtitle = "White, black, AFK mode and idle saver", collapsed = true,
    })
    local Interface = createSection(FPSTab, "Interface", 4, {
        subtitle = "Overlay, mute audio, notifications, chat", collapsed = true,
    })

    local switches = {}
    local function addToggle(section, Switch, setState)
        section.track(Switch)
        switches[#switches + 1] = { Switch = Switch, set = setState }
    end

    --// ================= WHITE / BLACK SCREEN & AFK MODE =================
    local Cover = new("ScreenGui", {
        Name = "ElyseraCover",
        DisplayOrder = 5,
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Enabled = false,
    }, GuiRoot)
    local CoverFrame = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        BackgroundColor3 = Color3.new(0, 0, 0),
    }, Cover)

    local WhiteSwitch, setWhite = CreateToggleOption(ScreenSec.Body, "White Screen")
    WhiteSwitch.Parent.LayoutOrder = 1
    local BlackSwitch, setBlack = CreateToggleOption(ScreenSec.Body, "Black Screen")
    BlackSwitch.Parent.LayoutOrder = 2
    local AfkSwitch, setAfk = CreateToggleOption(ScreenSec.Body, "AFK Mode")
    AfkSwitch.Parent.LayoutOrder = 3
    addToggle(ScreenSec, WhiteSwitch, setWhite)
    addToggle(ScreenSec, BlackSwitch, setBlack)
    addToggle(ScreenSec, AfkSwitch, setAfk)

    local coverActive, autoCover = false, false
    local afkIdledConn

    local function refreshScreen()
        local white = WhiteSwitch:GetAttribute("Toggled") == true
        local black = BlackSwitch:GetAttribute("Toggled") == true
        local afk   = AfkSwitch:GetAttribute("Toggled") == true
        local on = white or black or afk or autoCover
        if on then
            CoverFrame.BackgroundColor3 = (white and not afk) and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
        end
        Cover.Enabled = on
        if on ~= coverActive then
            coverActive = on
            pcall(function() RunService:Set3dRenderingEnabled(not on) end)
            FpsCap.setCover(on)
        end
    end

    WhiteSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if WhiteSwitch:GetAttribute("Toggled") then
            setBlack(false)
            setAfk(false)
        end
        refreshScreen()
    end)
    BlackSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if BlackSwitch:GetAttribute("Toggled") then setWhite(false) end
        refreshScreen()
    end)
    AfkSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        local on = AfkSwitch:GetAttribute("Toggled") == true
        if afkIdledConn then afkIdledConn:Disconnect(); afkIdledConn = nil end
        if on then
            setWhite(false)
            FpsCap.setAfk(true)
            afkIdledConn = UI.BindAntiAfk()
        else
            FpsCap.setAfk(false)
        end
        refreshScreen()
    end)

    local Screen = {}
    function Screen.setAuto(on)
        if autoCover == on then return end
        autoCover = on
        refreshScreen()
    end

    onDestroy(function()
        if afkIdledConn then afkIdledConn:Disconnect(); afkIdledConn = nil end
        if coverActive then
            coverActive = false
            pcall(function() RunService:Set3dRenderingEnabled(true) end)
        end
        Cover:Destroy()
        FpsCap.restore()
    end)

    --// ================= IDLE SAVER =================
    local Saver = {}
    local SAVER_MODES = { "After 1 min", "After 3 min", "After 5 min", "After 10 min" }
    do
        local conns, run, lastInput, covered = {}, 0, os.clock(), false
        local COUNTS = {
            [Enum.UserInputType.MouseMovement] = true,
            [Enum.UserInputType.MouseWheel] = true,
            [Enum.UserInputType.Touch] = true,
            [Enum.UserInputType.Gamepad1] = true,
        }

        local function wake()
            lastInput = os.clock()
            if covered then
                covered = false
                Screen.setAuto(false)
            end
        end

        function Saver.stop()
            run = run + 1
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            if covered then
                covered = false
                Screen.setAuto(false)
            end
        end

        function Saver.start(seconds)
            Saver.stop()
            local my = run
            lastInput = os.clock()
            conns[1] = UserInputService.InputBegan:Connect(wake)
            conns[2] = UserInputService.InputChanged:Connect(function(input)
                if COUNTS[input.UserInputType] then wake() end
            end)
            task.spawn(function()
                while run == my and not destroyed do
                    task.wait(1)
                    if run ~= my then break end
                    if #UserInputService:GetKeysPressed() > 0 then
                        wake()
                    elseif not covered and os.clock() - lastInput >= seconds then
                        covered = true
                        Screen.setAuto(true)
                    end
                end
            end)
        end

        function Saver.seconds(modeText)
            return (tonumber(string.match(modeText, "(%d+)")) or 3) * 60
        end

        onDestroy(Saver.stop)
    end

    --// ================= MUTE AUDIO =================
    local MuteAudio = {}
    do
        local active = false
        local savedMaster
        local savedVolumes = setmetatable({}, { __mode = "k" })
        local conns = {}

        local function muteInst(inst)
            if inst:IsA("Sound") or inst:IsA("SoundGroup") then
                if savedVolumes[inst] == nil then savedVolumes[inst] = inst.Volume end
                setProp(inst, "Volume", 0)
            end
        end

        function MuteAudio.enable()
            if active then return end
            active = true
            pcall(function()
                local ugs = UserSettings():GetService("UserGameSettings")
                if savedMaster == nil then savedMaster = ugs.MasterVolume end
                ugs.MasterVolume = 0
            end)
            for _, root in ipairs({ SoundService, workspace }) do
                for _, d in ipairs(root:GetDescendants()) do muteInst(d) end
                conns[#conns + 1] = root.DescendantAdded:Connect(muteInst)
            end
        end

        function MuteAudio.disable()
            if not active then return end
            active = false
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            if savedMaster ~= nil then
                pcall(function() UserSettings():GetService("UserGameSettings").MasterVolume = savedMaster end)
                savedMaster = nil
            end
            for inst, vol in pairs(savedVolumes) do
                if inst.Parent then setProp(inst, "Volume", vol) end
            end
            table.clear(savedVolumes)
        end

        onDestroy(MuteAudio.disable)
    end

    --// ================= HIDE DISTANT PLAYERS =================
    local CullPlayers = {}
    local CULL_MODES = { "Beyond 50m", "Beyond 100m", "Beyond 200m", "Beyond 350m" }
    do
        local active, runId, maxDist = false, 0, 100
        local hiddenChars = setmetatable({}, { __mode = "k" }) -- [char] = restoreFn

        local function restoreChar(char)
            local restore = hiddenChars[char]
            if restore then
                hiddenChars[char] = nil
                restore()
            end
        end

        local function hideChar(char)
            if not hiddenChars[char] then
                hiddenChars[char] = UI.HideCharacter(char)
            end
        end

        function CullPlayers.parseDist(text) return tonumber(string.match(text, "(%d+)")) or 100 end
        function CullPlayers.setDist(d) maxDist = d end

        function CullPlayers.stop()
            active = false
            runId = runId + 1
            for char in pairs(hiddenChars) do restoreChar(char) end
        end

        function CullPlayers.start(d)
            maxDist = d or maxDist
            if active then return end
            active = true
            runId = runId + 1
            local my = runId
            task.spawn(function()
                while active and runId == my and not destroyed do
                    local cam = workspace.CurrentCamera
                    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                    local origin = (myRoot and myRoot.Position) or (cam and cam.CFrame.Position)
                    if origin then
                        for _, p in ipairs(Players:GetPlayers()) do
                            if p ~= LocalPlayer and p.Character then
                                local c = p.Character
                                local r = c:FindFirstChild("HumanoidRootPart")
                                if r then
                                    if (r.Position - origin).Magnitude > maxDist then
                                        hideChar(c)
                                    else
                                        restoreChar(c)
                                    end
                                end
                            end
                        end
                    end
                    task.wait(0.4)
                end
            end)
        end

        onDestroy(CullPlayers.stop)
    end

    --// ================= HIDE CHAT & PLAYER LIST =================
    local HideUi = {}
    do
        local TYPES = { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Chat }
        local hiddenByUs, active = {}, false

        function HideUi.enable()
            if active then return end
            active = true
            for _, t in ipairs(TYPES) do
                local ok, was = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, t)
                if ok and was then
                    hiddenByUs[#hiddenByUs + 1] = t
                    pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, false)
                end
            end
        end

        function HideUi.disable()
            if not active then return end
            active = false
            for _, t in ipairs(hiddenByUs) do
                pcall(StarterGui.SetCoreGuiEnabled, StarterGui, t, true)
            end
            table.clear(hiddenByUs)
        end

        onDestroy(HideUi.disable)
    end

    --// ================= REMOVE NOTIFICATION =================
    local Notif = {}
    do
        local NOTIF_WORDS = {
            notification = true, notifications = true, notif = true, toast = true,
            announcement = true, announce = true, notice = true,
        }
        local nameCache = {}

        local function isNotifName(name)
            local hit = nameCache[name]
            if hit == nil then
                hit = false
                local spaced = name:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2"):gsub("[^%w]+", " ")
                for word in string.gmatch(string.lower(spaced), "%S+") do
                    if NOTIF_WORDS[word] then hit = true; break end
                end
                nameCache[name] = hit
            end
            return hit
        end

        local state
        do
            local okEnv, env = pcall(function() return getgenv() end)
            env = okEnv and env or _G
            state = env.__ElyseraNotif
            if not state then
                state = { on = false, hooked = false }
                env.__ElyseraNotif = state
            end
        end

        local function installHook()
            if state.hooked then return end
            if typeof(hookfunction) ~= "function" or typeof(newcclosure) ~= "function"
                or typeof(checkcaller) ~= "function" then
                return
            end
            local old
            local ok, res = pcall(hookfunction, StarterGui.SetCore, newcclosure(function(self, name, ...)
                if state.on and name == "SendNotification" and self == StarterGui and not checkcaller() then
                    return
                end
                return old(self, name, ...)
            end))
            if ok and res then old, state.hooked = res, true end
        end

        local hidden = setmetatable({}, { __mode = "k" })
        local conns = {}
        local active, run = false, 0

        local function hideGui(inst, prop)
            if hidden[inst] then return end
            local rec = { prop = prop, orig = inst[prop] }
            hidden[inst] = rec
            setProp(inst, prop, false)
            rec.conn = inst:GetPropertyChangedSignal(prop):Connect(function()
                if inst[prop] then setProp(inst, prop, false) end
            end)
        end

        local function scanGui(inst)
            if not active or not isNotifName(inst.Name) then return end
            local prop = (inst:IsA("ScreenGui") and "Enabled") or (inst:IsA("GuiObject") and "Visible")
            if not prop or inst:FindFirstChildWhichIsA("TextBox", true) then return end
            hideGui(inst, prop)
        end

        function Notif.enable()
            if active then return end
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if not pg then return end
            active = true
            run = run + 1
            local myRun = run
            installHook()
            state.on = true

            pcall(function()
                local rg = CoreGui:FindFirstChild("RobloxGui")
                local frame = rg and rg:FindFirstChild("NotificationFrame")
                if frame then hideGui(frame, "Visible") end
            end)

            conns[#conns + 1] = pg.DescendantAdded:Connect(function(d) task.defer(scanGui, d) end)
            task.spawn(function()
                local items = pg:GetDescendants()
                for i = 1, #items do
                    if run ~= myRun then return end
                    scanGui(items[i])
                    if i % 150 == 0 then task.wait() end
                end
            end)
        end

        function Notif.disable()
            if not active then return end
            active = false
            run = run + 1
            state.on = false
            for _, c in ipairs(conns) do c:Disconnect() end
            table.clear(conns)
            for inst, rec in pairs(hidden) do
                if rec.conn then rec.conn:Disconnect() end
                setProp(inst, rec.prop, rec.orig)
            end
            table.clear(hidden)
            table.clear(nameCache)
        end
    end

    --// ================= OPTIMIZER =================
    local MODES = { "Balanced", "Performance", "Extreme" }
    local Ctl = { mode = "Balanced", enabled = false }
    local reconcile
    do
        local Opt = {
            snapshot = setmetatable({}, { __mode = "k" }),
            conns = {},
            routes = {},
            partHandlers = {},
            runId = 0,
            restoring = false,
            watching = false,
            needRescan = false,
        }

        local hiddenOk
        local function hiddenAvailable()
            if hiddenOk == nil then
                hiddenOk = false
                if typeof(gethiddenproperty) == "function" and typeof(sethiddenproperty) == "function" then
                    local ok, v = pcall(gethiddenproperty, Lighting, "Technology")
                    hiddenOk = ok and v ~= nil
                end
            end
            return hiddenOk
        end

        local function probe(inst, prop, value, hidden)
            local cur = hidden and gethiddenproperty(inst, prop) or inst[prop]
            if cur == value then return false end
            local now
            if hidden then
                sethiddenproperty(inst, prop, value)
                now = gethiddenproperty(inst, prop)
            else
                inst[prop] = value
                now = inst[prop]
            end
            return true, cur, now
        end

        local function capture(inst, prop, value, hidden)
            if Opt.restoring then Opt.needRescan = true; return end
            local ok, changed, prev, now = pcall(probe, inst, prop, value, hidden)
            if not ok or not changed then return end
            local rec = Opt.snapshot[inst]
            if not rec then rec = {}; Opt.snapshot[inst] = rec end
            local e = rec[prop]
            if e then e[2] = now else rec[prop] = { prev, now, hidden } end
        end

        local function revert(inst, prop, e)
            local cur = e[3] and gethiddenproperty(inst, prop) or inst[prop]
            if cur ~= e[2] then return end
            if e[3] then sethiddenproperty(inst, prop, e[1]) else inst[prop] = e[1] end
        end

        local partCache = {}
        local function isPart(inst)
            local cn = inst.ClassName
            local v = partCache[cn]
            if v == nil then v = inst:IsA("BasePart"); partCache[cn] = v end
            return v
        end

        local function register(key, handler)
            if key == "BasePart" then
                Opt.partHandlers[#Opt.partHandlers + 1] = handler
                return
            end
            local hs = Opt.routes[key]
            if not hs then hs = {}; Opt.routes[key] = hs end
            hs[#hs + 1] = handler
        end

        local function addConn(conn) Opt.conns[#Opt.conns + 1] = conn end
        local function hasHandlers() return next(Opt.routes) ~= nil or #Opt.partHandlers > 0 end
        local function wants(inst) return Opt.routes[inst.ClassName] ~= nil or (#Opt.partHandlers > 0 and isPart(inst)) end

        local function route(inst)
            local hs = Opt.routes[inst.ClassName]
            if hs then for i = 1, #hs do hs[i](inst) end end
            if #Opt.partHandlers > 0 and isPart(inst) then
                for i = 1, #Opt.partHandlers do Opt.partHandlers[i](inst) end
            end
        end

        local SCAN_BUDGET = 0.002
        local function scan(root, myRun)
            local stack, top, visited = { root }, 1, 0
            local char = LocalPlayer.Character
            local t0 = os.clock()
            while top > 0 do
                local inst = stack[top]
                stack[top] = nil
                top = top - 1
                if inst ~= char then
                    if wants(inst) then pcall(route, inst) end
                    local kids = inst:GetChildren()
                    for i = 1, #kids do
                        top = top + 1
                        stack[top] = kids[i]
                    end
                end
                visited = visited + 1
                if visited % 64 == 0 and os.clock() - t0 >= (coverActive and 0.006 or SCAN_BUDGET) then
                    RunService.Heartbeat:Wait()
                    if myRun ~= Opt.runId then return end
                    char = LocalPlayer.Character
                    t0 = os.clock()
                end
            end
        end

        local queue, qHead, qTail, pump = {}, 1, 0, nil
        local DRAIN_BUDGET, QUEUE_CAP, RESCAN_GAP = 0.0015, 10000, 5
        local lastRescan = 0

        local function stopPump()
            if pump then pump:Disconnect(); pump = nil end
        end

        local function clearQueue()
            table.clear(queue)
            qHead, qTail = 1, 0
            stopPump()
        end

        local function drain()
            local t0 = os.clock()
            while qHead <= qTail do
                local inst = queue[qHead]
                queue[qHead] = nil
                qHead = qHead + 1
                local char = LocalPlayer.Character
                if inst.Parent and not (char and inst:IsDescendantOf(char)) then pcall(route, inst) end
                if os.clock() - t0 >= DRAIN_BUDGET then return end
            end
            qHead, qTail = 1, 0
            stopPump()
            if Opt.needRescan and hasHandlers() and os.clock() - lastRescan >= RESCAN_GAP then
                Opt.needRescan = false
                lastRescan = os.clock()
                task.spawn(scan, workspace, Opt.runId)
            end
        end

        local function enqueue(inst)
            if qTail - qHead + 1 >= QUEUE_CAP then Opt.needRescan = true; return end
            qTail = qTail + 1
            queue[qTail] = inst
            if not pump then pump = RunService.Heartbeat:Connect(drain) end
        end

        local function watchWorkspace()
            if Opt.watching then return end
            Opt.watching = true
            addConn(workspace.DescendantAdded:Connect(function(inst)
                if Opt.restoring then Opt.needRescan = true elseif wants(inst) then enqueue(inst) end
            end))
        end

        local RESTORE_BUDGET = 0.004
        function Opt.restore(sync)
            Opt.restoring = true
            Opt.runId = Opt.runId + 1
            for _, c in ipairs(Opt.conns) do pcall(c.Disconnect, c) end
            table.clear(Opt.conns)
            table.clear(Opt.routes)
            table.clear(Opt.partHandlers)
            clearQueue()
            Opt.watching, Opt.needRescan = false, false

            local t0 = os.clock()
            for inst, rec in pairs(Opt.snapshot) do
                for prop, e in pairs(rec) do pcall(revert, inst, prop, e) end
                Opt.snapshot[inst] = nil
                if not sync and os.clock() - t0 >= RESTORE_BUDGET then
                    task.wait()
                    t0 = os.clock()
                end
            end
            Opt.restoring = false
        end

        local Features = {}
        local EFFECT_LEVEL = {
            BlurEffect = 1, DepthOfFieldEffect = 1, SunRaysEffect = 1, BloomEffect = 1,
            ColorCorrectionEffect = 3,
        }
        local LIGHT_CLASSES = { "PointLight", "SpotLight", "SurfaceLight" }
        local COSMETIC_CLASSES = { "Smoke", "Fire", "Sparkles", "Trail", "Beam" }
        local KEEP_MATERIAL = {
            [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true,
            [Enum.Material.Neon] = true, [Enum.Material.Water] = true,
        }

        function Features.quality(spec)
            local okR, rendering = pcall(function() return settings().Rendering end)
            if not okR or not rendering then return end
            local cur = rendering.QualityLevel.Value
            local target
            if cur == 0 then
                if not (spec.force and spec.cap) then return end
                target = spec.cap
            else
                target = math.clamp(cur - (spec.delta or 0), 1, cur)
                if spec.cap then target = math.min(target, spec.cap) end
            end
            capture(rendering, "QualityLevel", Enum.QualityLevel:FromValue(target))
        end

        function Features.lighting(level)
            capture(Lighting, "GlobalShadows", false)
            if level >= 2 then
                capture(Lighting, "ShadowSoftness", 0)
                capture(Lighting, "EnvironmentDiffuseScale", 0)
                capture(Lighting, "EnvironmentSpecularScale", 0)
                local terrain = workspace:FindFirstChildOfClass("Terrain")
                local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
                if clouds then capture(clouds, "Enabled", false) end
            end
            if level >= 3 then
                for _, child in ipairs(Lighting:GetChildren()) do
                    if child:IsA("Atmosphere") then
                        capture(child, "Density", 0)
                        capture(child, "Haze", 0)
                        capture(child, "Glare", 0)
                    end
                end
                if hiddenAvailable() then
                    capture(Lighting, "Technology", Enum.Technology.Compatibility, true)
                end
            end
        end

        local function watchCamera(handle)
            local camConn
            local function attach(cam)
                if camConn then camConn:Disconnect(); camConn = nil end
                if not cam then return end
                for _, c in ipairs(cam:GetChildren()) do handle(c) end
                camConn = cam.ChildAdded:Connect(handle)
            end
            attach(workspace.CurrentCamera)
            local changed = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
                attach(workspace.CurrentCamera)
            end)
            return {
                Disconnect = function()
                    changed:Disconnect()
                    if camConn then camConn:Disconnect(); camConn = nil end
                end,
            }
        end

        function Features.postFx(level)
            local function handle(inst)
                local need = EFFECT_LEVEL[inst.ClassName]
                if need and level >= need then capture(inst, "Enabled", false) end
            end
            for _, c in ipairs(Lighting:GetChildren()) do handle(c) end
            addConn(Lighting.ChildAdded:Connect(handle))
            addConn(watchCamera(handle))

            for _, class in ipairs(LIGHT_CLASSES) do
                register(class, function(l)
                    if level >= 2 then capture(l, "Enabled", false) else capture(l, "Shadows", false) end
                end)
            end
            if level >= 2 then
                register("Highlight", function(h) capture(h, "Enabled", false) end)
            end
        end

        function Features.terrain(level)
            local terrain = workspace:FindFirstChildOfClass("Terrain")
            if not terrain then return end
            capture(terrain, "WaterWaveSize", 0)
            capture(terrain, "WaterWaveSpeed", 0)
            if level >= 2 then
                capture(terrain, "WaterReflectance", 0)
                if hiddenAvailable() then capture(terrain, "Decoration", false, true) end
            end
        end

        function Features.particles(spec)
            local scale = spec.rate
            register("ParticleEmitter", function(pe)
                local rate = pe.Rate
                if rate > 0 then capture(pe, "Rate", math.min(rate, math.max(1, rate * scale))) end
            end)
            if spec.cosmetic then
                for _, class in ipairs(COSMETIC_CLASSES) do
                    register(class, function(inst) capture(inst, "Enabled", false) end)
                end
            end
        end

        function Features.parts(tier)
            register("BasePart", function(p)
                if p.ClassName == "Terrain" then return end
                if p.Reflectance > 0 then capture(p, "Reflectance", 0) end
                if p.ClassName == "MeshPart" then
                    capture(p, "RenderFidelity", Enum.RenderFidelity.Performance)
                end
                if tier >= 2 and not KEEP_MATERIAL[p.Material] then
                    capture(p, "Material", Enum.Material.SmoothPlastic)
                end
            end)
        end

        local ORDER = { "quality", "lighting", "postFx", "terrain", "particles", "parts" }
        local PROFILES = {
            Balanced = {
                quality = { delta = 4 }, lighting = 1, postFx = 1, terrain = 1, parts = 1,
                particles = { rate = 0.5 },
            },
            Performance = {
                quality = { cap = 3 }, lighting = 2, postFx = 2, terrain = 1, parts = 1,
                particles = { rate = 0.2, cosmetic = true },
            },
            Extreme = {
                quality = { cap = 1, force = true }, lighting = 3, postFx = 3, terrain = 2, parts = 2,
                particles = { rate = 0.1, cosmetic = true },
            },
        }

        local function applyProfile(name)
            local spec = PROFILES[name]
            if not spec then return end
            for _, key in ipairs(ORDER) do
                local level = spec[key]
                if level then pcall(Features[key], level) end
            end
            if hasHandlers() then
                watchWorkspace()
                task.spawn(scan, workspace, Opt.runId)
            end
        end

        local dirty, working, worker = false, false, nil
        function reconcile()
            dirty = true
            if working then return end
            working = true
            worker = task.spawn(function()
                while dirty and not destroyed do
                    dirty = false
                    local ok, err = pcall(function()
                        Opt.restore(false)
                        if Ctl.enabled then applyProfile(Ctl.mode) end
                    end)
                    if not ok then
                        Opt.restoring = false
                        warn("[FPS] profile update failed: " .. tostring(err))
                    end
                end
                working = false
            end)
        end

        onDestroy(function()
            dirty = false
            if worker then pcall(task.cancel, worker) end
            Opt.restoring = false
            Opt.restore(true)
        end)
    end

    --// ================= PERFORMANCE METER =================
    local function statusEntry(text, token)
        return setmetatable({ text = text }, {
            __index = function(_, key)
                if key == "color" then return Theme[token] end
            end,
        })
    end
    local STATUS = {
        smooth = statusEntry("Smooth", "Sakura"),
        fair   = statusEntry("Fair", "AccentPurple"),
        low    = statusEntry("Low", "Danger"),
    }

    local Meter = { fps = 0, avg = 0, low1 = 0, ms = 0, ping = nil, mem = nil, listeners = {} }
    do
        local beat
        local wanted = {}
        local frames, elapsed, lastSlow = 0, 0, -1
        local frameFpsWindow, winIdx = {}, 0
        local MAX_WINDOW = 300

        local function readPing()
            local ok, v = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
            if ok and type(v) == "number" and v > 0 then return v end
            local ok2, p = pcall(function() return LocalPlayer:GetNetworkPing() * 2000 end)
            if ok2 and type(p) == "number" and p > 0 then return p end
            return nil
        end

        local function readMemory()
            local ok, v = pcall(function() return Stats:GetTotalMemoryUsageMb() end)
            return (ok and type(v) == "number") and v or nil
        end

        local function computeWindowStats()
            local n = #frameFpsWindow
            if n == 0 then Meter.avg, Meter.low1 = Meter.fps, Meter.fps; return end
            local sum = 0
            local sorted = table.clone(frameFpsWindow)
            for i = 1, n do sum = sum + sorted[i] end
            table.sort(sorted)
            local k = math.max(1, math.ceil(n * 0.01))
            local lowSum = 0
            for i = 1, k do lowSum = lowSum + sorted[i] end
            Meter.avg = sum / n
            Meter.low1 = lowSum / k
        end

        local function onBeat(dt)
            if dt > 1 or dt <= 0 then frames, elapsed = 0, 0; return end
            frames = frames + 1
            elapsed = elapsed + dt
            winIdx = (winIdx % MAX_WINDOW) + 1
            frameFpsWindow[winIdx] = 1 / dt
            if elapsed < 0.5 then return end

            Meter.fps = frames / elapsed
            Meter.ms = elapsed / frames * 1000
            frames, elapsed = 0, 0
            computeWindowStats()

            local now = os.clock()
            if now - lastSlow >= 1 then
                lastSlow = now
                Meter.ping, Meter.mem = readPing(), readMemory()
            end
            for i = 1, #Meter.listeners do pcall(Meter.listeners[i], Meter) end
        end

        function Meter.want(key, on)
            wanted[key] = on or nil
            local want = not destroyed and next(wanted) ~= nil
            if want and not beat then
                frames, elapsed, lastSlow, winIdx = 0, 0, -1, 0
                table.clear(frameFpsWindow)
                beat = RunService.Heartbeat:Connect(onBeat)
            elseif not want and beat then
                beat:Disconnect()
                beat = nil
            end
        end

        function Meter.level(fps)
            local cap = FpsCap.getUser()
            local smooth = cap and math.min(50, cap * 0.85) or 50
            local low = cap and math.min(30, cap * 0.5) or 30
            if fps >= smooth then return "smooth" end
            if fps >= low then return "fair" end
            return "low"
        end

        onDestroy(function() Meter.want("card", false); Meter.want("overlay", false) end)
    end

    local function hex(color) return color:ToHex() end
    local function rounded(n) return math.floor(n + 0.5) end
    local function formatMemory(mb)
        if mb >= 1024 then return string.format("%.1f GB", mb / 1024) end
        return rounded(mb) .. " MB"
    end

    --// ================= PERFORMANCE MONITOR CARD =================
    do
        local BARS = 40
        local hist = {}

        local Card = new("Frame", {
            Name = "Monitor",
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
        }, FPSTab)
        corner(Card, 8)
        stroke(Card)
        padding(Card, 14, 14, 12, 12)
        list(Card, 10)

        local Top = new("Frame", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundTransparency = 1,
        }, Card)
        local Big = label(Top, {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            RichText = true,
            Text = "--",
            TextSize = 34,
            TextColor3 = Theme.Sakura,
            TextXAlignment = Enum.TextXAlignment.Left,
        })

        local Chip = new("Frame", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(0, 24),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Sakura,
            BackgroundTransparency = 0.82,
            BorderSizePixel = 0,
        }, Top)
        corner(Chip, 12)
        local ChipStroke = stroke(Chip, Theme.Sakura)
        ChipStroke.Transparency = 0.5
        padding(Chip, 12, 12, 0, 0)
        local ChipText = label(Chip, {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "Measuring",
            TextSize = 12,
            TextColor3 = Theme.Sakura,
            TextXAlignment = Enum.TextXAlignment.Center,
        })

        local StatsRow = new("Frame", {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 34),
            BackgroundTransparency = 1,
        }, Card)
        list(StatsRow, 0, { FillDirection = Enum.FillDirection.Horizontal })

        local function stat(order, caption)
            local Col = new("Frame", {
                LayoutOrder = order,
                Size = UDim2.new(1 / 4, 0, 1, 0),
                BackgroundTransparency = 1,
            }, StatsRow)
            label(Col, {
                Size = UDim2.new(1, 0, 0, 14),
                Font = Enum.Font.Gotham,
                Text = caption,
                TextSize = 11,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
            })
            return label(Col, {
                Position = UDim2.fromOffset(0, 15),
                Size = UDim2.new(1, 0, 0, 18),
                Text = "--",
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
            })
        end
        local AvgLowVal = stat(1, "Avg / 1% Low")
        local FrameVal  = stat(2, "Frame time")
        local PingVal   = stat(3, "Ping")
        local MemVal    = stat(4, "Memory")

        local Graph = new("Frame", {
            Name = "Graph",
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, 46),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            ClipsDescendants = true,
        }, Card)
        corner(Graph, 6)
        stroke(Graph)
        local Plot = new("Frame", {
            Name = "Plot",
            Position = UDim2.fromOffset(4, 4),
            Size = UDim2.new(1, -8, 1, -8),
            BackgroundTransparency = 1,
        }, Graph)

        local bars = {}
        for i = 1, BARS do
            bars[i] = new("Frame", {
                Name = "Bar",
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new((i - 1) / BARS, 0, 1, 0),
                Size = UDim2.new(1 / BARS, -1, 0, 0),
                BackgroundColor3 = Theme.Sakura,
                BorderSizePixel = 0,
                Visible = false,
            }, Plot)
        end
        local Guide = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Theme.Border,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = 2,
        }, Plot)

        local function drawGraph()
            local n, top = #hist, 60
            for i = 1, n do
                if hist[i] > top then top = hist[i] end
            end
            top = math.ceil(top / 30) * 30
            for i = 1, BARS do
                local v = hist[n - (BARS - i)]
                local bar = bars[i]
                if v then
                    bar.Visible = true
                    bar.Size = UDim2.new(1 / BARS, -1, math.clamp(v / top, 0.04, 1), 0)
                    bar.BackgroundColor3 = STATUS[Meter.level(v)].color
                else
                    bar.Visible = false
                end
            end
            Guide.Position = UDim2.new(0, 0, 1 - 30 / top, 0)
        end

        local function setChip(text, color)
            ChipText.Text = text
            ChipText.TextColor3 = color
            Chip.BackgroundColor3 = color
            ChipStroke.Color = color
        end

        local function render(m)
            PingVal.Text = m.ping and (rounded(m.ping) .. " ms") or "--"
            MemVal.Text = m.mem and formatMemory(m.mem) or "--"

            if coverActive then
                Big.Text = string.format('<font color="#%s">OFF</font><font size="13" color="#%s"> rendering</font>',
                    hex(Theme.SubText), hex(Theme.SubText))
                AvgLowVal.Text = "--"
                FrameVal.Text = "--"
                setChip("Saving power", Theme.SubText)
                return
            end

            local fps = m.fps
            local status = STATUS[Meter.level(fps)]
            Big.Text = string.format('<font color="#%s">%d</font><font size="13" color="#%s"> FPS</font>',
                hex(status.color), rounded(fps), hex(Theme.SubText))
            AvgLowVal.Text = string.format("%d / %d", rounded(m.avg), rounded(m.low1))
            FrameVal.Text = string.format("%.1f ms", m.ms)
            setChip(status.text, status.color)

            hist[#hist + 1] = fps
            if #hist > BARS then table.remove(hist, 1) end
            drawGraph()
        end

        Meter.listeners[#Meter.listeners + 1] = function(m)
            if Card.Parent and FPSTab.Visible then render(m) end
        end

        local function refresh()
            local want = not destroyed and FPSTab.Visible and MainUI.Visible
            if want then table.clear(hist) end
            Meter.want("card", want)
        end
        FPSTab:GetPropertyChangedSignal("Visible"):Connect(refresh)
        MainUI:GetPropertyChangedSignal("Visible"):Connect(refresh)
        refresh()
    end

    --// ================= FPS OVERLAY =================
    local Overlay = {}
    do
        local px, py = 0.5, 0.01
        local saved = Prefs.get("overlay")
        if type(saved) == "table" then
            local x, y = tonumber(saved.x), tonumber(saved.y)
            if x and y and x == x and y == y then
                px, py = math.clamp(x, 0, 1), math.clamp(y, 0, 1)
            end
        end

        local Gui = new("ScreenGui", {
            Name = "ElyseraFpsOverlay",
            DisplayOrder = 6,
            IgnoreGuiInset = true,
            ResetOnSpawn = false,
            ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
            Enabled = false,
        }, GuiRoot)

        local Pill = new("Frame", {
            Name = "Pill",
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.fromScale(px, py),
            Size = UDim2.fromOffset(0, 26),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundColor3 = Theme.Panel,
            BackgroundTransparency = 0.1,
            BorderSizePixel = 0,
            Active = true,
        }, Gui)
        corner(Pill, 13)
        stroke(Pill)
        padding(Pill, 12, 12, 0, 0)

        local Text = label(Pill, {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            RichText = true,
            Text = "",
            TextSize = 12,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Center,
        })

        local function render(m)
            local sub = hex(Theme.SubText)
            if coverActive then
                local ram = m.mem and string.format(' <font color="#%s">·</font> %s', sub, formatMemory(m.mem)) or ""
                Text.Text = string.format('<font color="#%s">Rendering off</font>%s', sub, ram)
                return
            end
            local status = STATUS[Meter.level(m.fps)]
            local text = string.format(
                '<font color="#%s">%d</font> FPS <font color="#%s">·</font> Avg %d <font color="#%s">·</font> 1%% %d',
                hex(status.color), rounded(m.fps), sub, rounded(m.avg), sub, rounded(m.low1)
            )
            if m.ping then text = text .. string.format(' <font color="#%s">·</font> %d ms', sub, rounded(m.ping)) end
            if m.mem then text = text .. string.format(' <font color="#%s">·</font> %s', sub, formatMemory(m.mem)) end
            Text.Text = text
        end

        Meter.listeners[#Meter.listeners + 1] = function(m)
            if Gui.Enabled then render(m) end
        end

        local function settle()
            local vp, size, pos = Gui.AbsoluteSize, Pill.AbsoluteSize, Pill.AbsolutePosition
            if vp.X <= 0 or vp.Y <= 0 then return end
            local cx = math.clamp(pos.X + size.X / 2, size.X / 2, math.max(size.X / 2, vp.X - size.X / 2))
            local ty = math.clamp(pos.Y, 0, math.max(0, vp.Y - size.Y))
            px, py = cx / vp.X, ty / vp.Y
            Pill.Position = UDim2.fromScale(px, py)
            Prefs.set("overlay", { x = px, y = py })
        end

        local dragMoveConn, dragEndConn
        local function stopDrag()
            if dragMoveConn then dragMoveConn:Disconnect(); dragMoveConn = nil end
            if dragEndConn then dragEndConn:Disconnect(); dragEndConn = nil end
        end

        Pill.InputBegan:Connect(function(input)
            local kind = input.UserInputType
            if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
            stopDrag()
            local vp = Gui.AbsoluteSize
            local startInput = input.Position
            local startAbsX = Pill.AbsolutePosition.X + Pill.AbsoluteSize.X / 2
            local startAbsY = Pill.AbsolutePosition.Y
            dragMoveConn = UserInputService.InputChanged:Connect(function(i)
                if i.UserInputType == Enum.UserInputType.MouseMovement or i == input then
                    if vp.X <= 0 or vp.Y <= 0 then return end
                    local d = i.Position - startInput
                    local curAbsX = startAbsX + d.X
                    local curAbsY = startAbsY + d.Y
                    Pill.Position = UDim2.new(curAbsX / vp.X, 0, curAbsY / vp.Y, 0)
                end
            end)
            dragEndConn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    stopDrag()
                    settle()
                end
            end)
        end)

        function Overlay.setEnabled(on)
            Gui.Enabled = on
            Meter.want("overlay", on)
        end

        onDestroy(function()
            stopDrag()
            Gui:Destroy()
        end)
    end

    --// ================= OPTIMIZE ROWS =================
    local startMode = "Balanced"
    for _, m in ipairs(MODES) do
        if Saved.fpsMode == m then startMode = m end
    end
    Ctl.mode = startMode
    ScreenGui:SetAttribute("FpsMode", startMode)

    local Profile = createModeRow(Optimize.Body, "FPS Profile", MODES, startMode, function(m)
        Ctl.mode = m
        ScreenGui:SetAttribute("FpsMode", m)
        saveSettings()
        if Ctl.enabled then reconcile() end
    end, {
        Balanced = "Shadows and blur effects off",
        Performance = "Also lights and effects off",
        Extreme = "Lowest quality, flat materials",
    })
    Profile.Frame.LayoutOrder = 1
    Profile.Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
        Ctl.enabled = Profile.Switch:GetAttribute("Toggled") == true
        reconcile()
    end)
    addToggle(Optimize, Profile.Switch, Profile.setState)

    local CAP_MODES = { "30 FPS", "60 FPS", "90 FPS", "120 FPS", "144 FPS", "Unlimited" }
    local function parseFps(text)
        if text == "Unlimited" then return 999 end
        return tonumber(string.match(text, "^(%d+)"))
    end

    local CapRow
    CapRow = createModeRow(Optimize.Body, "FPS Cap", CAP_MODES, Prefs.pick("cap", CAP_MODES, "60 FPS"), function(m)
        Prefs.set("cap", m)
        if CapRow.Switch:GetAttribute("Toggled") then FpsCap.setUser(parseFps(m)) end
    end, { default = "Lower cap saves battery and heat", Unlimited = "No limit, uses more power" })
    CapRow.Frame.LayoutOrder = 2
    CapRow.Frame.Visible = FpsCap.supported()
    CapRow.Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if CapRow.Switch:GetAttribute("Toggled") then
            FpsCap.setUser(parseFps(CapRow.getMode()))
        else
            FpsCap.setUser(nil)
        end
    end)
    addToggle(Optimize, CapRow.Switch, CapRow.setState)

    local AUTO_MODES = { "Below 20 FPS", "Below 30 FPS", "Below 40 FPS" }
    local AutoRow
    AutoRow = createModeRow(Optimize.Body, "Auto Boost", AUTO_MODES, Prefs.pick("auto", AUTO_MODES, "Below 30 FPS"),
        function(m) Prefs.set("auto", m) end, { default = "Profile turns on if FPS stays low" })
    AutoRow.Frame.LayoutOrder = 3
    addToggle(Optimize, AutoRow.Switch, AutoRow.setState)
    do
        local LOW_SECONDS = 6
        local lowSince

        local function limit()
            local v = tonumber(string.match(AutoRow.getMode(), "(%d+)")) or 30
            local cap = FpsCap.getUser()
            return cap and math.min(v, cap * 0.7) or v
        end

        Meter.listeners[#Meter.listeners + 1] = function(m)
            if not AutoRow.Switch:GetAttribute("Toggled") then return end
            if coverActive or Ctl.enabled or m.fps >= limit() then
                lowSince = nil
                return
            end
            local now = os.clock()
            lowSince = lowSince or now
            if now - lowSince >= LOW_SECONDS then
                lowSince = nil
                Profile.setState(true)
                AutoRow.setState(false)
            end
        end

        local function sync()
            lowSince = nil
            local armed = AutoRow.Switch:GetAttribute("Toggled") == true
            local profileOn = Profile.Switch:GetAttribute("Toggled") == true
            Meter.want("auto", armed and not profileOn)
        end
        AutoRow.Switch:GetAttributeChangedSignal("Toggled"):Connect(sync)
        Profile.Switch:GetAttributeChangedSignal("Toggled"):Connect(sync)
    end

    local CullRow
    CullRow = createModeRow(Optimize.Body, "Hide Distant Players", CULL_MODES,
        Prefs.pick("cull", CULL_MODES, "Beyond 100m"),
        function(m)
            Prefs.set("cull", m)
            CullPlayers.setDist(CullPlayers.parseDist(m))
        end, { default = "Hides characters further than range" })
    CullRow.Frame.LayoutOrder = 4
    CullRow.Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if CullRow.Switch:GetAttribute("Toggled") then
            CullPlayers.start(CullPlayers.parseDist(CullRow.getMode()))
        else
            CullPlayers.stop()
        end
    end)
    addToggle(Optimize, CullRow.Switch, CullRow.setState)

    --// ================= SCREEN ROWS =================
    local SaverRow
    SaverRow = createModeRow(ScreenSec.Body, "Idle Saver", SAVER_MODES, Prefs.pick("saver", SAVER_MODES, "After 3 min"),
        function(m)
            Prefs.set("saver", m)
            if SaverRow.Switch:GetAttribute("Toggled") then Saver.start(Saver.seconds(m)) end
        end, { default = "Black screen and low FPS when idle" })
    SaverRow.Frame.LayoutOrder = 4
    SaverRow.Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if SaverRow.Switch:GetAttribute("Toggled") then
            Saver.start(Saver.seconds(SaverRow.getMode()))
        else
            Saver.stop()
        end
    end)
    addToggle(ScreenSec, SaverRow.Switch, SaverRow.setState)

    --// ================= INTERFACE ROWS =================
    local OverlaySwitch, setOverlay = CreateToggleOption(Interface.Body, "FPS Overlay")
    OverlaySwitch.Parent.LayoutOrder = 1
    OverlaySwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        Overlay.setEnabled(OverlaySwitch:GetAttribute("Toggled") == true)
    end)
    addToggle(Interface, OverlaySwitch, setOverlay)

    local MuteSwitch, setMute = CreateToggleOption(Interface.Body, "Mute Audio")
    MuteSwitch.Parent.LayoutOrder = 2
    MuteSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if MuteSwitch:GetAttribute("Toggled") then MuteAudio.enable() else MuteAudio.disable() end
    end)
    addToggle(Interface, MuteSwitch, setMute)

    local NotifSwitch, setNotif = CreateToggleOption(Interface.Body, "Remove Notification")
    NotifSwitch.Parent.LayoutOrder = 3
    NotifSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if NotifSwitch:GetAttribute("Toggled") then Notif.enable() else Notif.disable() end
    end)
    onDestroy(Notif.disable)
    addToggle(Interface, NotifSwitch, setNotif)

    local HideSwitch, setHide = CreateToggleOption(Interface.Body, "Hide Chat & Player List")
    HideSwitch.Parent.LayoutOrder = 4
    HideSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if HideSwitch:GetAttribute("Toggled") then HideUi.enable() else HideUi.disable() end
    end)
    addToggle(Interface, HideSwitch, setHide)

    --// ================= RESET ALL =================
    UI.CreateResetButton(FPSTab, 5, function()
        local n = 0
        for _, t in ipairs(switches) do
            if t.Switch:GetAttribute("Toggled") == true then
                n = n + 1
                t.set(false)
            end
        end
        return n
    end)
end
