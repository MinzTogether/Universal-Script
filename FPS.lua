--// ================= FPS TAB (module) =================
-- File này được script chính (test.lua) nạp vào và gọi với 1 bảng ctx
-- chứa các hàm/biến dùng chung của UI.

return function(ctx)
    local FPSTab              = ctx.Tab

    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local LocalPlayer         = ctx.LocalPlayer
    local CoreGui             = ctx.CoreGui

    local CreateToggleOption  = ctx.CreateToggleOption
    local CreateInfoRow       = ctx.CreateInfoRow
    local CreateStyledButton  = ctx.CreateStyledButton
    local flashButtonFeedback = ctx.flashButtonFeedback
    local isLocked            = ctx.isLocked -- thay cho biến uiLocked của file chính

    local RunService        = game:GetService("RunService")
    local Lighting          = game:GetService("Lighting")
    local StarterGui        = game:GetService("StarterGui")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local function setProp(inst, prop, value)
        pcall(function() inst[prop] = value end)
    end

    --// ---------- White Screen / Black Screen ----------
    local Cover = Instance.new("ScreenGui")
    Cover.Name = "ElyseraCover"
    Cover.DisplayOrder = 5
    Cover.IgnoreGuiInset = true
    Cover.ResetOnSpawn = false
    Cover.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    Cover.Enabled = false
    Cover.Parent = CoreGui

    local CoverFrame = Instance.new("Frame", Cover)
    CoverFrame.Size = UDim2.new(1, 0, 1, 0)
    CoverFrame.BorderSizePixel = 0
    CoverFrame.BackgroundColor3 = Color3.new(0, 0, 0)

    local function set3D(enabled)
        pcall(function() RunService:Set3dRenderingEnabled(enabled) end)
    end

    local WhiteSwitch, setWhite = CreateToggleOption(FPSTab, "White Screen")
    WhiteSwitch.Parent.LayoutOrder = 1
    local BlackSwitch, setBlack = CreateToggleOption(FPSTab, "Black Screen")
    BlackSwitch.Parent.LayoutOrder = 2

    local function refreshScreen()
        local white = WhiteSwitch:GetAttribute("Toggled")
        local black = BlackSwitch:GetAttribute("Toggled")
        if white or black then
            CoverFrame.BackgroundColor3 = white and Color3.new(1, 1, 1) or Color3.new(0, 0, 0)
            Cover.Enabled = true
            set3D(false)
        else
            Cover.Enabled = false
            set3D(true)
        end
    end

    WhiteSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if WhiteSwitch:GetAttribute("Toggled") then setBlack(false) end
        refreshScreen()
    end)
    BlackSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if BlackSwitch:GetAttribute("Toggled") then setWhite(false) end
        refreshScreen()
    end)

    --// ---------- Remove Notification ----------
    local NOTIF_KEYWORDS = { "notif", "notice", "announce", "toast", "alert" }

    local function isNotifName(name)
        name = string.lower(name)
        for _, kw in ipairs(NOTIF_KEYWORDS) do
            if string.find(name, kw, 1, true) then return true end
        end
        return false
    end

    local NotifSwitch = CreateToggleOption(FPSTab, "Remove Notification")
    NotifSwitch.Parent.LayoutOrder = 3

    local notifOn      = false
    local notifRun     = 0
    local notifConns   = {}
    local hiddenGuis   = {}
    local mutedRemotes = {}
    local notifRemotes = {}
    local hooked       = false

    local function installSetCoreHook()
        if hooked then return end
        hooked = true

        local function isBlocked(self, name)
            return notifOn
                and name == "SendNotification"
                and not checkcaller()
                and typeof(self) == "Instance"
                and self.ClassName == "StarterGui"
        end

        if hookmetamethod and getnamecallmethod and newcclosure and checkcaller then
            pcall(function()
                local old
                old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                    if notifOn and getnamecallmethod() == "SetCore" and isBlocked(self, (...)) then
                        return
                    end
                    return old(self, ...)
                end))
            end)
        end

        if hookfunction and newcclosure and checkcaller then
            pcall(function()
                local old
                old = hookfunction(StarterGui.SetCore, newcclosure(function(self, name, ...)
                    if isBlocked(self, name) then return end
                    return old(self, name, ...)
                end))
            end)
        end
    end

    local function hideGui(inst)
        if hiddenGuis[inst] ~= nil then return end
        local prop
        if inst:IsA("ScreenGui") then
            prop = "Enabled"
        elseif inst:IsA("GuiObject") then
            prop = "Visible"
        else
            return
        end
        hiddenGuis[inst] = { prop = prop, value = inst[prop] }
        setProp(inst, prop, false)
        table.insert(notifConns, inst:GetPropertyChangedSignal(prop):Connect(function()
            if notifOn and inst[prop] then setProp(inst, prop, false) end
        end))
    end

    local function scanGui(inst)
        if (inst:IsA("GuiObject") or inst:IsA("ScreenGui")) and isNotifName(inst.Name) then
            hideGui(inst)
        end
    end

    local function removeLegacyMessage(inst)
        if inst:IsA("Message") then
            pcall(function() inst:Destroy() end)
        end
    end

    local function muteRemote(inst)
        if not getconnections then return end
        if not (inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")) then return end
        if not isNotifName(inst.Name) then return end
        notifRemotes[inst] = true
        local ok, conns = pcall(getconnections, inst.OnClientEvent)
        if not ok or type(conns) ~= "table" then return end
        for _, c in ipairs(conns) do
            if not mutedRemotes[c] then
                mutedRemotes[c] = true
                pcall(function() c:Disable() end)
            end
        end
    end

    local function enableNotifBlock(myRun)
        installSetCoreHook()

        pcall(function()
            local rg = CoreGui:FindFirstChild("RobloxGui")
            local nf = rg and rg:FindFirstChild("NotificationFrame")
            if nf then hideGui(nf) end
        end)

        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then
            for _, d in ipairs(pg:GetDescendants()) do
                scanGui(d)
                removeLegacyMessage(d)
            end
            table.insert(notifConns, pg.DescendantAdded:Connect(function(d)
                if not notifOn then return end
                task.defer(function()
                    scanGui(d)
                    removeLegacyMessage(d)
                end)
            end))
        end

        for _, d in ipairs(workspace:GetChildren()) do
            removeLegacyMessage(d)
        end
        table.insert(notifConns, workspace.DescendantAdded:Connect(function(d)
            if notifOn and d:IsA("Message") then
                task.defer(removeLegacyMessage, d)
            end
        end))

        for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
            muteRemote(d)
        end
        table.insert(notifConns, ReplicatedStorage.DescendantAdded:Connect(function(d)
            if not notifOn then return end
            muteRemote(d)
            task.delay(1, muteRemote, d)
        end))

        task.spawn(function()
            while notifOn and myRun == notifRun and ScreenGui.Parent do
                for r in pairs(notifRemotes) do muteRemote(r) end
                task.wait(2)
            end
        end)
    end

    local function disableNotifBlock()
        for _, c in ipairs(notifConns) do c:Disconnect() end
        table.clear(notifConns)

        for inst, info in pairs(hiddenGuis) do
            setProp(inst, info.prop, info.value)
        end
        table.clear(hiddenGuis)

        for c in pairs(mutedRemotes) do
            pcall(function() c:Enable() end)
        end
        table.clear(mutedRemotes)
        table.clear(notifRemotes)
    end

    NotifSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        notifRun += 1
        notifOn = NotifSwitch:GetAttribute("Toggled")
        if notifOn then
            enableNotifBlock(notifRun)
        else
            disableNotifBlock()
        end
    end)

    --// ---------- Anti Chat ----------
    local TextChatService = game:GetService("TextChatService")

    local AntiChatSwitch = CreateToggleOption(FPSTab, "Anti Chat")
    AntiChatSwitch.Parent.LayoutOrder = 4

    local antiChatOn    = false
    local chatHooked    = false
    local antiChatConns = {}
    local antiChatBoxes = {}
    local chatBarConfig, chatBarOriginal

    -- Chặn tin nhắn gửi từ script (game hoặc executor) ở tầng __namecall / hookfunction.
    -- Hook không gỡ được nên dùng cờ antiChatOn: tắt toggle thì hook chỉ đi qua.
    local function isChatCall(self, method)
        if typeof(self) ~= "Instance" then return false end
        if method == "FireServer" then
            return self.ClassName == "RemoteEvent" and self.Name == "SayMessageRequest"
        elseif method == "SendAsync" then
            return self.ClassName == "TextChannel"
        elseif method == "Chat" then
            return self == LocalPlayer
        end
        return false
    end

    local function installChatHook()
        if chatHooked then return end

        if hookmetamethod and getnamecallmethod and newcclosure then
            pcall(function()
                local old
                old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                    if antiChatOn and isChatCall(self, getnamecallmethod()) then
                        return
                    end
                    return old(self, ...)
                end))
                chatHooked = true
            end)
        end

        -- Bắt thêm trường hợp gọi kiểu remote.FireServer(remote, ...) / channel.SendAsync(channel, ...)
        if hookfunction and newcclosure then
            pcall(function()
                local oldFire
                oldFire = hookfunction(Instance.new("RemoteEvent").FireServer, newcclosure(function(self, ...)
                    if antiChatOn and isChatCall(self, "FireServer") then return end
                    return oldFire(self, ...)
                end))
                chatHooked = true
            end)
            pcall(function()
                local oldSend
                oldSend = hookfunction(Instance.new("TextChannel").SendAsync, newcclosure(function(self, ...)
                    if antiChatOn and isChatCall(self, "SendAsync") then return end
                    return oldSend(self, ...)
                end))
                chatHooked = true
            end)
        end
    end

    -- Chặn ở giao diện. Khung chat cũ (Legacy): không cho ChatBar nhận focus -> không gõ/gửi được
    local function blockLegacyChatBar(box)
        if antiChatBoxes[box] then return end
        antiChatBoxes[box] = true
        if box:IsFocused() then box:ReleaseFocus() end
        table.insert(antiChatConns, box.Focused:Connect(function()
            box:ReleaseFocus()
        end))
    end

    local function scanLegacyChat(inst)
        if inst.Name == "ChatBar" and inst:IsA("TextBox") then
            blockLegacyChatBar(inst)
        end
    end

    local function disableAntiChat()
        antiChatOn = false
        for _, c in ipairs(antiChatConns) do c:Disconnect() end
        table.clear(antiChatConns)
        table.clear(antiChatBoxes)

        if chatBarConfig then
            if chatBarOriginal ~= nil then
                setProp(chatBarConfig, "Enabled", chatBarOriginal)
            end
            chatBarConfig, chatBarOriginal = nil, nil
        end
    end

    local function enableAntiChat()
        disableAntiChat()
        antiChatOn = true
        installChatHook()

        -- Khung chat mới (TextChatService): tắt thanh nhập tin nhắn
        pcall(function()
            local cfg = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
            if cfg then
                chatBarConfig, chatBarOriginal = cfg, cfg.Enabled
                cfg.Enabled = false
                table.insert(antiChatConns, cfg:GetPropertyChangedSignal("Enabled"):Connect(function()
                    if cfg.Enabled then setProp(cfg, "Enabled", false) end
                end))
            end
        end)

        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then
            local chatGui = pg:FindFirstChild("Chat")
            if chatGui then
                for _, d in ipairs(chatGui:GetDescendants()) do scanLegacyChat(d) end
            end
            table.insert(antiChatConns, pg.DescendantAdded:Connect(scanLegacyChat))
        end
    end

    AntiChatSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if AntiChatSwitch:GetAttribute("Toggled") then
            enableAntiChat()
        else
            disableAntiChat()
        end
    end)

    --// ---------- Boost Fps ----------
    local DESTROY = {
        Decal = true, Texture = true, SurfaceAppearance = true,
        ParticleEmitter = true, Trail = true, Beam = true,
        Smoke = true, Fire = true, Sparkles = true,
        Explosion = true, Atmosphere = true,
    }
    local DISABLE = {
        PointLight = true, SpotLight = true, SurfaceLight = true,
        BlurEffect = true, BloomEffect = true, ColorCorrectionEffect = true,
        DepthOfFieldEffect = true, SunRaysEffect = true,
        Clouds = true, Highlight = true,
    }

    local function optimize(inst)
        local class = inst.ClassName
        if DESTROY[class] then
            pcall(function() inst:Destroy() end)
        elseif DISABLE[class] then
            setProp(inst, "Enabled", false)
        elseif class == "SpecialMesh" then
            setProp(inst, "TextureId", "")
        elseif class ~= "Terrain" and inst:IsA("BasePart") then
            setProp(inst, "Material", Enum.Material.SmoothPlastic)
            setProp(inst, "Reflectance", 0)
            setProp(inst, "CastShadow", false)
            if class == "MeshPart" then
                setProp(inst, "TextureID", "")
                setProp(inst, "RenderFidelity", Enum.RenderFidelity.Performance)
            end
        end
    end

    local function boostEnvironment()
        pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)

        setProp(Lighting, "GlobalShadows", false)
        setProp(Lighting, "FogEnd", 9e9)
        ScreenGui:SetAttribute("LightingBoosted", os.clock()) -- báo cho Full Bright (tab Local)
        setProp(Lighting, "ShadowSoftness", 0)
        setProp(Lighting, "EnvironmentDiffuseScale", 0)
        setProp(Lighting, "EnvironmentSpecularScale", 0)
        if sethiddenproperty then
            pcall(sethiddenproperty, Lighting, "Technology", Enum.Technology.Compatibility)
        end

        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            setProp(terrain, "WaterWaveSize", 0)
            setProp(terrain, "WaterWaveSpeed", 0)
            setProp(terrain, "WaterReflectance", 0)
            if sethiddenproperty then
                pcall(sethiddenproperty, terrain, "Decoration", false)
            end
        end
    end

    local boostConn
    local function runBoost()
        boostEnvironment()

        local count = 0
        local function process(list)
            for _, inst in ipairs(list) do
                optimize(inst)
                count += 1
                if count % 400 == 0 then task.wait() end
            end
        end

        process(Lighting:GetDescendants())
        local cam = workspace.CurrentCamera
        if cam then process(cam:GetDescendants()) end
        process(workspace:GetDescendants())

        if not boostConn then
            boostConn = workspace.DescendantAdded:Connect(function(inst)
                task.defer(optimize, inst)
            end)
        end
    end

    do
        local Frame = CreateInfoRow(FPSTab, "Boost Fps")
        Frame.LayoutOrder = 5
        local BoostBtn = CreateStyledButton(Frame, "Boost", 70)
        local busy = false
        BoostBtn.Activated:Connect(function()
            if isLocked() or busy then return end
            busy = true
            BoostBtn.Text, BoostBtn.TextColor3 = "Working...", Theme.SubText
            task.spawn(function()
                local ok = pcall(runBoost)
                flashButtonFeedback(BoostBtn, "Boost", ok and "Done!" or "Failed", not ok)
                task.delay(1.2, function() busy = false end)
            end)
        end)
    end

    --// ---------- Cleanup ----------
    ScreenGui.Destroying:Connect(function()
        notifOn = false
        set3D(true)
        if boostConn then boostConn:Disconnect() end
        disableNotifBlock()
        disableAntiChat()
        Cover:Destroy()
    end)
end
