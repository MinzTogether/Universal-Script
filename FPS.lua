--// ================= FPS TAB (module) =================
-- File này được script chính (test.lua) nạp vào và gọi với 1 bảng ctx
-- chứa các hàm/biến dùng chung của UI.

return function(ctx)
    local FPSTab              = ctx.Tab

    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local LocalPlayer         = ctx.LocalPlayer
    local CoreGui             = ctx.CoreGui
    local MainUI              = ctx.MainUI
    local Saved               = ctx.Saved
    local saveSettings        = ctx.saveSettings

    local ANCHOR_CENTER       = ctx.ANCHOR_CENTER
    local CENTER              = ctx.CENTER
    local EASE_QUAD           = ctx.EASE_QUAD
    local DIR_IN              = ctx.DIR_IN
    local DIR_OUT             = ctx.DIR_OUT

    local new                 = ctx.new
    local corner              = ctx.corner
    local stroke              = ctx.stroke
    local padding             = ctx.padding
    local list                = ctx.list
    local label               = ctx.label
    local tween               = ctx.tween
    local pressScale          = ctx.pressScale

    local FunctionScroll      = ctx.FunctionScroll
    local CreateInfoRow       = ctx.CreateInfoRow
    local CreateStyledButton  = ctx.CreateStyledButton
    local CreateToggleOption  = ctx.CreateToggleOption
    local flashButtonFeedback = ctx.flashButtonFeedback
    local isLocked            = ctx.isLocked  -- đọc uiLocked của file chính
    local setLocked           = ctx.setLocked -- gán uiLocked của file chính

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

    --// ---------- FPS System ----------
    -- Profile (applyProfile / restoreState), đo FPS (fpsMonitor), nút thắt (detectBottleneck)
    -- và Auto Profile. Gói trong function riêng + xpcall: không thêm local vào scope ngoài
    -- (scope này đã gần giới hạn 200 local) và lỗi ở đây không làm hỏng phần còn lại của script.
    xpcall(function()
        local Stats       = game:GetService("Stats")
        local TextService = game:GetService("TextService")

        local function renderingOff()
            return WhiteSwitch:GetAttribute("Toggled") == true
                or BlackSwitch:GetAttribute("Toggled") == true
        end

        ------------------------------------------------------------------ CORE
        local Perf = {
            snapshot     = setmetatable({}, { __mode = "k" }), -- weak key: part bị xóa tự được GC
            conns        = {},   -- connection do hệ thống tối ưu tạo ra (restoreState ngắt hết)
            routes       = {},   -- ClassName -> { handler, ... }
            partHandlers = {},   -- handler cho mọi BasePart
            runId        = 0,    -- đổi mỗi lần restore: các vòng lặp/quét nền tự thoát
            restoring    = false,
            busy         = false,
            profile      = nil,
        }

        --// captureState: ghi giá trị gốc (chỉ lần đầu) rồi áp giá trị mới
        local function probe(inst, prop, value, hidden)
            local cur
            if hidden then cur = gethiddenproperty(inst, prop) else cur = inst[prop] end
            if cur == value then return nil end
            if hidden then sethiddenproperty(inst, prop, value) else inst[prop] = value end
            return cur
        end

        local function captureState(inst, prop, newValue, hidden)
            if Perf.restoring then return false end
            local ok, prev = pcall(probe, inst, prop, newValue, hidden)
            if not ok or prev == nil then return false end -- lỗi hoặc không đổi gì

            local rec = Perf.snapshot[inst]
            if not rec then
                rec = {}
                Perf.snapshot[inst] = rec
            end
            local e = rec[prop]
            if e then
                e.set = newValue -- áp lần 2: giữ nguyên e.orig
            else
                rec[prop] = { orig = prev, set = newValue, hidden = hidden or false }
            end
            return true
        end

        --// restoreState / restoreOne: hoàn tác từ snapshot
        local RESTORE_BUDGET = 0.004 -- 4 ms mỗi frame

        local function revert(inst, prop, e)
            local cur
            if e.hidden then cur = gethiddenproperty(inst, prop) else cur = inst[prop] end
            if cur ~= e.set then return false end -- game/script khác đã đổi -> không ghi đè
            if e.hidden then sethiddenproperty(inst, prop, e.orig) else inst[prop] = e.orig end
            return true
        end

        local function restoreOne(inst, prop)
            local rec = Perf.snapshot[inst]
            local e = rec and rec[prop]
            if not e then return false end
            local ok, done = pcall(revert, inst, prop, e)
            rec[prop] = nil
            return ok and done
        end

        local function restoreState(opts)
            if Perf.restoring then return nil end
            local sync = opts and opts.sync
            Perf.restoring = true
            Perf.runId += 1 -- hủy scan / vòng lặp nền
            for _, c in ipairs(Perf.conns) do c:Disconnect() end
            table.clear(Perf.conns)
            Perf.clearQueue()
            table.clear(Perf.routes)
            table.clear(Perf.partHandlers)

            local restored, skipped = 0, 0
            local started = os.clock()
            local t0 = started
            for inst, rec in pairs(Perf.snapshot) do
                for prop, e in pairs(rec) do
                    local ok, done = pcall(revert, inst, prop, e)
                    if ok and done then restored += 1 else skipped += 1 end
                    rec[prop] = nil
                end
                Perf.snapshot[inst] = nil
                if not sync and os.clock() - t0 >= RESTORE_BUDGET then
                    task.wait()
                    t0 = os.clock()
                end
            end

            if not (opts and opts.keepProfile) then Perf.profile = nil end
            Perf.restoring = false
            return { restored = restored, skipped = skipped, ms = (os.clock() - started) * 1000 }
        end

        ------------------------------------------------- ROUTER / SCAN / WATCH
        local partCache = {}
        local function isPartClass(inst)
            local cn = inst.ClassName
            local v = partCache[cn]
            if v == nil then
                v = inst:IsA("BasePart")
                partCache[cn] = v
            end
            return v
        end

        function Perf.register(key, handler)
            if key == "BasePart" then
                table.insert(Perf.partHandlers, handler)
            else
                local hs = Perf.routes[key]
                if not hs then
                    hs = {}
                    Perf.routes[key] = hs
                end
                table.insert(hs, handler)
            end
        end

        function Perf.hasHandlers()
            return next(Perf.routes) ~= nil or #Perf.partHandlers > 0
        end

        function Perf.wants(inst)
            return Perf.routes[inst.ClassName] ~= nil
                or (#Perf.partHandlers > 0 and isPartClass(inst))
        end

        function Perf.route(inst)
            local hs = Perf.routes[inst.ClassName]
            if hs then
                for i = 1, #hs do hs[i](inst) end
            end
            if #Perf.partHandlers > 0 and isPartClass(inst) then
                for i = 1, #Perf.partHandlers do Perf.partHandlers[i](inst) end
            end
        end

        --// scanWorkspaceChunked: quét theo ngân sách ms/frame, hủy được qua runId
        local function scanWorkspaceChunked(root, myRun, budgetMs)
            local budget = (budgetMs or 2) / 1000
            local char = LocalPlayer.Character
            local stack, top, visited, t0 = { root }, 1, 0, os.clock()
            while top > 0 do
                local inst = stack[top]
                stack[top] = nil
                top -= 1
                if inst ~= char then -- không đụng nhân vật của mình
                    if Perf.wants(inst) then pcall(Perf.route, inst) end
                    local kids = inst:GetChildren()
                    for i = 1, #kids do
                        top += 1
                        stack[top] = kids[i]
                    end
                end
                visited += 1
                if visited % 64 == 0 and os.clock() - t0 >= budget then
                    RunService.Heartbeat:Wait()
                    if myRun ~= Perf.runId then return false, visited end
                    t0 = os.clock()
                end
            end
            return true, visited
        end

        --// watchNewInstances: 1 listener, lọc theo class, xử lý qua hàng đợi có ngân sách
        local queue, qh, qt, pump = {}, 1, 0, nil
        local DRAIN_BUDGET = 0.0015 -- 1.5 ms mỗi frame
        local QUEUE_CAP    = 20000

        local function drain()
            local t0 = os.clock()
            while qh <= qt do
                local inst = queue[qh]
                queue[qh] = nil
                qh += 1
                if inst.Parent then pcall(Perf.route, inst) end -- có thể đã bị hủy
                if os.clock() - t0 >= DRAIN_BUDGET then return end
            end
            qh, qt = 1, 0
            if pump then
                pump:Disconnect()
                pump = nil -- rảnh thì không tốn chi phí
            end
        end

        local function enqueue(inst)
            if qt - qh >= QUEUE_CAP then return end
            qt += 1
            queue[qt] = inst
            if not pump then pump = RunService.Heartbeat:Connect(drain) end
        end

        function Perf.clearQueue()
            table.clear(queue)
            qh, qt = 1, 0
            if pump then
                pump:Disconnect()
                pump = nil
            end
        end

        local function watchNewInstances()
            local conn = workspace.DescendantAdded:Connect(function(inst)
                if Perf.restoring then return end
                if Perf.wants(inst) then enqueue(inst) end
            end)
            table.insert(Perf.conns, conn)
        end

        ------------------------------------------------------------- FEATURES
        local F = {}

        --// setQualityLevel: chỉ hạ, theo bước (delta) hoặc trần (cap)
        F.quality = function(spec)
            local ok, rendering = pcall(function() return settings().Rendering end)
            if not ok or not rendering then return nil end
            local cur = rendering.QualityLevel.Value -- 0 = Automatic, 1..21
            if cur == 0 then return nil end          -- không suy ra được bậc

            local target = cur - (spec.delta or 0)
            if spec.cap then target = math.min(target, spec.cap) end
            target = math.clamp(target, 1, cur)      -- chỉ hạ, không nâng
            if target == cur then return nil end

            local okSet = captureState(rendering, "QualityLevel", Enum.QualityLevel:FromValue(target))
            return okSet and target or nil
        end

        --// optimizeLighting: 0 | 1 | 2 | 3
        F.lighting = function(level)
            if level >= 1 then
                captureState(Lighting, "GlobalShadows", false)
            end
            if level >= 2 then
                captureState(Lighting, "ShadowSoftness", 0)
                captureState(Lighting, "EnvironmentDiffuseScale", 0)
                captureState(Lighting, "EnvironmentSpecularScale", 0)
                local terrain = workspace:FindFirstChildOfClass("Terrain")
                local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
                if clouds then captureState(clouds, "Enabled", false) end
            end
            if level >= 3 then
                for _, child in ipairs(Lighting:GetChildren()) do -- Lighting là cây nhỏ
                    if child:IsA("Atmosphere") then
                        captureState(child, "Density", 0)
                        captureState(child, "Haze", 0)
                        captureState(child, "Glare", 0)
                    end
                end
                -- Thử nghiệm: hidden property, lỗi đã được pcall trong captureState
                captureState(Lighting, "Technology", Enum.Technology.Compatibility, true)
            end
        end

        --// reduceVisualEffects: 0 | 1 | 2 | 3
        local EFFECT_LEVEL = { -- class -> mức tối thiểu để tắt
            BlurEffect = 1, DepthOfFieldEffect = 1, SunRaysEffect = 1, BloomEffect = 1,
            ColorCorrectionEffect = 3,
        }
        local LIGHT_CLASSES = { "PointLight", "SpotLight", "SurfaceLight" }

        local function isOwned(inst) -- không đụng vào object của script này
            return inst:GetAttribute("ElyseraOwned") == true or inst:IsDescendantOf(CoreGui)
        end

        F.postFx = function(level)
            local function handleEffect(inst)
                local need = EFFECT_LEVEL[inst.ClassName]
                if need and level >= need then captureState(inst, "Enabled", false) end
            end

            local roots = { Lighting }
            if workspace.CurrentCamera then table.insert(roots, workspace.CurrentCamera) end
            for _, root in ipairs(roots) do
                for _, c in ipairs(root:GetChildren()) do handleEffect(c) end
                table.insert(Perf.conns, root.ChildAdded:Connect(handleEffect)) -- cây nhỏ nên rẻ
            end

            table.insert(Perf.conns, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
                local cam = workspace.CurrentCamera
                if not cam then return end
                for _, c in ipairs(cam:GetChildren()) do handleEffect(c) end
                table.insert(Perf.conns, cam.ChildAdded:Connect(handleEffect))
            end))

            if level >= 1 then
                for _, class in ipairs(LIGHT_CLASSES) do
                    Perf.register(class, function(l)
                        if isOwned(l) then return end
                        if level >= 2 then
                            captureState(l, "Enabled", false)
                        else
                            captureState(l, "Shadows", false)
                        end
                    end)
                end
            end
            if level >= 2 then
                Perf.register("Highlight", function(h)
                    if not isOwned(h) then captureState(h, "Enabled", false) end
                end)
            end
        end

        --// optimizeTerrainWater: 0 | 1 | 2
        F.terrain = function(level)
            local terrain = workspace:FindFirstChildOfClass("Terrain")
            if not terrain then return end
            if level >= 1 then
                captureState(terrain, "WaterWaveSize", 0)
                captureState(terrain, "WaterWaveSpeed", 0)
            end
            if level >= 2 then
                captureState(terrain, "WaterReflectance", 0)
                captureState(terrain, "Decoration", false, true) -- hidden property
            end
        end

        --// limitParticles: { rateScale, budget?, cosmetic? }
        local function emitterPos(pe)
            local p = pe.Parent
            if not p then return nil end
            if p:IsA("BasePart") then return p.Position end
            if p:IsA("Attachment") then return p.WorldPosition end
            return nil
        end

        F.particles = function(spec)
            local myRun = Perf.runId
            local emitters = setmetatable({}, { __mode = "k" }) -- registry yếu

            Perf.register("ParticleEmitter", function(pe)
                emitters[pe] = true
                if pe.Rate > 0 then
                    captureState(pe, "Rate", math.min(pe.Rate, math.max(1, pe.Rate * spec.rateScale)))
                end
            end)

            if spec.cosmetic then
                for _, class in ipairs({ "Smoke", "Fire", "Sparkles", "Trail", "Beam" }) do
                    Perf.register(class, function(inst) captureState(inst, "Enabled", false) end)
                end
            end

            if spec.budget then
                task.spawn(function()
                    local idx, ds, es = {}, {}, {} -- mảng dùng lại, tránh rác GC
                    local n = 0
                    while myRun == Perf.runId do
                        task.wait(n > 2000 and 2 or 1)
                        if myRun ~= Perf.runId then break end
                        local cam = workspace.CurrentCamera
                        if cam then
                            local origin = cam.CFrame.Position
                            n = 0
                            for pe in pairs(emitters) do
                                if pe.Parent then
                                    n += 1
                                    local pos = emitterPos(pe)
                                    es[n] = pe
                                    ds[n] = pos and (pos - origin).Magnitude or 0 -- không rõ vị trí = coi là gần
                                    idx[n] = n
                                end
                            end
                            for i = #idx, n + 1, -1 do
                                idx[i], es[i], ds[i] = nil, nil, nil
                            end
                            table.sort(idx, function(a, b) return ds[a] < ds[b] end)
                            for rank = 1, n do
                                local pe = es[idx[rank]]
                                if rank <= spec.budget then
                                    restoreOne(pe, "Enabled")
                                else
                                    captureState(pe, "Enabled", false)
                                end
                            end
                        end
                    end
                end)
            end
        end

        --// optimizeParts: 0 | 1 | 2
        local KEEP_MATERIAL = { -- vật liệu có ý nghĩa nhìn thấy/gameplay
            [Enum.Material.Glass] = true, [Enum.Material.ForceField] = true,
            [Enum.Material.Neon] = true,  [Enum.Material.Water] = true,
        }

        F.parts = function(tier)
            local shadowsOn = Lighting.GlobalShadows -- optimizeLighting chạy trước (xem ORDER)
            Perf.register("BasePart", function(p)
                if p:IsA("Terrain") then return end
                local ch = LocalPlayer.Character
                if ch and p:IsDescendantOf(ch) then return end

                if p.Reflectance > 0 then captureState(p, "Reflectance", 0) end
                if p.ClassName == "MeshPart" then
                    captureState(p, "RenderFidelity", Enum.RenderFidelity.Performance)
                end
                if shadowsOn then captureState(p, "CastShadow", false) end
                if tier >= 2 and not KEEP_MATERIAL[p.Material] then
                    captureState(p, "Material", Enum.Material.SmoothPlastic)
                end
            end)
        end

        -------------------------------------------------------- detectBottleneck
        local function detectBottleneck(seconds)
            local sums = { gpu = 0, cpuR = 0, sim = 0, phys = 0, ft = 0, dt = 0 }
            local n = 0
            local c = RunService.Heartbeat:Connect(function(dt)
                local ok, g, cr, hb, ph, ft = pcall(function()
                    return Stats.RenderGPUFrameTime, Stats.RenderCPUFrameTime,
                        Stats.HeartbeatTime, Stats.PhysicsStepTime, Stats.FrameTime
                end)
                if not (ok and g and cr and hb and ph and ft) then return end
                sums.gpu += g
                sums.cpuR += cr
                sums.sim += hb
                sums.phys += ph
                sums.ft += ft
                sums.dt += dt
                n += 1
            end)
            task.wait(seconds or 3)
            c:Disconnect()
            if n < 10 or sums.ft <= 0 then return { kind = "UNKNOWN", detail = {} } end

            -- Hiệu chuẩn đơn vị (giây hay mili-giây) bằng dt thực tế
            local k = (sums.dt / n * 1000) / (sums.ft / n)
            k = (k > 100) and 1000 or 1
            local frameMs = sums.dt / n * 1000
            local d = {
                gpu = sums.gpu / n * k, cpuRender = sums.cpuR / n * k,
                sim = sums.sim / n * k, phys = sums.phys / n * k, frameMs = frameMs,
            }

            local best, kind = 0, "UNKNOWN"
            for key, tag in pairs({ gpu = "GPU", cpuRender = "CPU_RENDER", sim = "SIM", phys = "PHYSICS" }) do
                if d[key] > best then best, kind = d[key], tag end
            end
            if best < frameMs * 0.6 then kind = "UNKNOWN" end -- không có thành phần nào áp đảo
            return { kind = kind, detail = d }
        end

        ------------------------------------------------------------ applyProfile
        local ORDER = { "quality", "lighting", "postFx", "terrain", "particles", "parts" }
        local Profiles = {
            Balanced = {
                quality = { delta = 4 }, lighting = 1, postFx = 1, terrain = 1, parts = 1,
                particles = { rateScale = 0.5, budget = 150 },
            },
            Performance = {
                quality = { cap = 3 }, lighting = 2, postFx = 2, terrain = 2, parts = 1,
                particles = { rateScale = 0.2, budget = 60, cosmetic = true },
                partsIfGpu = 2, -- đổi Material chỉ khi detectBottleneck xác nhận nghẽn GPU
            },
            Extreme = { -- dùng các mức thử nghiệm (lighting/postFx mức 3, Material)
                quality = { cap = 1 }, lighting = 3, postFx = 3, terrain = 2, parts = 2,
                particles = { rateScale = 0.1, budget = 30, cosmetic = true },
            },
        }

        local function applyProfile(name, custom)
            local spec = (name == "Custom") and custom or Profiles[name]
            if not spec then return false, "unknown profile" end
            if Perf.busy then return false, "busy" end

            Perf.busy = true
            pcall(restoreState, { keepProfile = true })
            local myRun = Perf.runId

            if spec.partsIfGpu and not renderingOff() then
                -- đo trên trạng thái gốc (vừa restore); chỉ bật bậc Material khi GPU là nút thắt
                local okD, b = pcall(detectBottleneck, 2)
                if okD and b.kind == "GPU" then
                    local copy = {}
                    for k, v in pairs(spec) do copy[k] = v end
                    copy.parts = spec.partsIfGpu
                    spec = copy
                end
            end

            for _, feature in ipairs(ORDER) do
                local level = spec[feature]
                if level and level ~= 0 then
                    local ok, err = pcall(F[feature], level) -- 1 feature lỗi không hỏng cả profile
                    if not ok then warn("[Elysera] " .. feature .. ": " .. tostring(err)) end
                end
            end

            if Perf.hasHandlers() then
                watchNewInstances() -- bật trước để không sót object mới khi đang quét
                task.spawn(scanWorkspaceChunked, workspace, myRun)
            end

            Perf.profile = name
            Perf.busy = false
            return true
        end

        ------------------------------------------------------------- fpsMonitor
        local Monitor = {}
        do
            local N = 360
            local ring, head, filled, conn = table.create(N, 0), 0, 0, nil

            local function summarize(list, n)
                if n < 10 then return nil end
                local tmp, sum = table.create(n, 0), 0
                for i = 1, n do
                    tmp[i] = list[i]
                    sum += list[i]
                end
                table.sort(tmp)
                local p95 = tmp[math.max(1, math.ceil(n * 0.95))]
                local k = math.max(1, math.floor(n * 0.01))
                local worst = 0
                for i = n - k + 1, n do worst += tmp[i] end
                return {
                    fps = n / sum, avgMs = sum / n * 1000, p95Ms = p95 * 1000,
                    low1 = k / worst, frames = n,
                }
            end

            function Monitor.start()
                if conn then return end
                conn = RunService.Heartbeat:Connect(function(dt)
                    head = head % N + 1
                    ring[head] = dt
                    if filled < N then filled += 1 end
                end)
            end

            function Monitor.stop()
                if conn then
                    conn:Disconnect()
                    conn = nil
                end
            end

            function Monitor.snapshot(frames)
                local n = math.min(frames or filled, filled)
                local samples = table.create(n, 0)
                for i = 1, n do samples[i] = ring[(head - i) % N + 1] end -- n frame gần nhất
                return summarize(samples, n)
            end

            function Monitor.measure(seconds)
                local samples = {}
                local c = RunService.Heartbeat:Connect(function(dt) samples[#samples + 1] = dt end)
                task.wait(seconds)
                c:Disconnect()
                return summarize(samples, #samples)
            end
        end

        ---------------------------------------------- MODE LIST (popup dùng chung)
        local POP_GAP, ITEM_H, POP_PAD = 4, 30, 4

        local function textWidth(text)
            local ok, v = pcall(function()
                return TextService:GetTextSize(text, 13, Enum.Font.GothamBold, Vector2.new(1000, 100)).X
            end)
            return ok and v or (#text * 8)
        end

        -- Lớp chặn trong suốt: vô hiệu hóa UI (không làm mờ) và bắt chạm ra ngoài list
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

        -- Theme giống MainUI: nền Background + viền Border
        local PopList = new("CanvasGroup", {
            Name = "ModeList",
            AnchorPoint = Vector2.new(1, 0),
            Size = UDim2.fromOffset(120, 40),
            BackgroundColor3 = Theme.Background,
            BorderSizePixel = 0,
            GroupTransparency = 1,
            Visible = false,
            ZIndex = 16,
        }, MainUI)
        corner(PopList, 10)
        stroke(PopList)
        padding(PopList, POP_PAD, POP_PAD, POP_PAD, POP_PAD)
        list(PopList, 2)

        local Popup = { open = false, owner = nil, token = 0, lockedUI = false }

        local function closePopup()
            if not Popup.open then return end
            Popup.open = false
            Popup.token += 1
            local tk = Popup.token
            PopBlocker.Visible = false
            if Popup.lockedUI then
                setLocked(false)
                Popup.lockedUI = false
            end
            local owner = Popup.owner
            Popup.owner = nil
            if owner then owner.onClosed() end
            tween(PopList, 0.1, { GroupTransparency = 1 }, EASE_QUAD, DIR_IN).Completed:Connect(function()
                if Popup.token == tk then PopList.Visible = false end
            end)
        end

        local function openPopup(api)
            if Popup.open or isLocked() then return end

            for _, c in ipairs(PopList:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end

            local current = api.getMode()
            local maxW = 0
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
                }, PopList)
                corner(Item, 6)
                Item.MouseEnter:Connect(function()
                    if not selected then tween(Item, 0.12, { BackgroundTransparency = 0.5 }) end
                end)
                Item.MouseLeave:Connect(function()
                    if not selected then tween(Item, 0.12, { BackgroundTransparency = 1 }) end
                end)
                Item.Activated:Connect(function()
                    closePopup()
                    api.select(m)
                end)
            end

            local n = #api.modes
            local w = math.max(maxW + 32, 110)
            local h = n * ITEM_H + (n - 1) * 2 + POP_PAD * 2

            -- Mở ngay dưới function; viền phải thẳng hàng với viền phải của function
            local mp, ms = MainUI.AbsolutePosition, MainUI.AbsoluteSize
            local ap, asz = api.Frame.AbsolutePosition, api.Frame.AbsoluteSize
            local x = (ap.X + asz.X) - mp.X
            local y = (ap.Y + asz.Y) - mp.Y + POP_GAP
            if y + h > ms.Y - 6 then -- không đủ chỗ phía dưới -> mở phía trên
                y = (ap.Y - mp.Y) - POP_GAP - h
            end
            y = math.max(y, 4)

            Popup.open = true
            Popup.owner = api
            Popup.token += 1
            setLocked(true)
            Popup.lockedUI = true
            PopBlocker.Visible = true

            PopList.Size = UDim2.fromOffset(w, h)
            PopList.Position = UDim2.fromOffset(x, y - 4)
            PopList.GroupTransparency = 1
            PopList.Visible = true
            tween(PopList, 0.12, { GroupTransparency = 0, Position = UDim2.fromOffset(x, y) }, EASE_QUAD, DIR_OUT)
            api.onOpened()
        end

        PopBlocker.Activated:Connect(closePopup) -- chạm ngoài list -> ẩn list
        FunctionScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(closePopup)
        MainUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(closePopup)
        MainUI:GetPropertyChangedSignal("Visible"):Connect(function()
            if not MainUI.Visible then closePopup() end
        end)

        --// Function có chọn mode: [tiêu đề ... toggle] / [winbox (tên mode + nút ▾)] căn phải
        local function CreateModeFunction(parent, title, modes, default, onSelect)
            local H_TOP, H_BOX = 50, 34
            local BOX_H, ARROW_W, GAP = 26, 28, 6

            local Switch, setState = CreateToggleOption(parent, title, H_TOP + H_BOX)
            local Frame = Switch.Parent
            -- toggle bật/tắt ở góc phải trên, tiêu đề ở dòng trên
            Switch.AnchorPoint = Vector2.new(1, 0)
            Switch.Position = UDim2.new(1, -12, 0, (H_TOP - 24) / 2)
            local Title = Frame:FindFirstChildOfClass("TextLabel")
            if Title then Title.Size = UDim2.new(1, -80, 0, H_TOP) end

            local current = default
            local function boxWidth(text)
                return textWidth(text) + 2 * (ARROW_W + GAP) -- nội dung ở giữa, đối xứng với vùng nút
            end

            local Box = new("Frame", {
                Name = "ModeBox",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -12, 0, H_TOP - 4),
                Size = UDim2.fromOffset(boxWidth(current), BOX_H),
                BackgroundColor3 = Theme.Header,
                BorderSizePixel = 0,
            }, Frame)
            corner(Box, 6)
            stroke(Box)

            local ModeText = label(Box, {
                Size = UDim2.fromScale(1, 1),
                Text = current,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Center,
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

            -- mũi tên chỉ xuống: 2 thanh xoay ±45°
            local Chev = new("Frame", {
                AnchorPoint = ANCHOR_CENTER,
                Position = CENTER,
                Size = UDim2.fromOffset(12, 12),
                BackgroundTransparency = 1,
            }, ArrowBtn)
            for _, side in ipairs({ -1, 1 }) do
                local bar = new("Frame", {
                    AnchorPoint = ANCHOR_CENTER,
                    Position = UDim2.fromOffset(6 + side * 2.5, 5.5),
                    Size = UDim2.fromOffset(7, 2),
                    Rotation = -side * 45,
                    BackgroundColor3 = Theme.SubText,
                    BorderSizePixel = 0,
                }, Chev)
                corner(bar, 1)
            end

            local api = { Frame = Frame, Switch = Switch, setState = setState, modes = modes }
            function api.getMode() return current end
            function api.setMode(m)
                if m == current then return end
                current = m
                ModeText.Text = m
                tween(Box, 0.15, { Size = UDim2.fromOffset(boxWidth(m), BOX_H) })
            end
            function api.select(m)
                if m == current then return end
                api.setMode(m)
                if onSelect then onSelect(m) end
            end
            function api.onOpened() tween(Chev, 0.15, { Rotation = 180 }) end
            function api.onClosed() tween(Chev, 0.15, { Rotation = 0 }) end

            ArrowBtn.Activated:Connect(function()
                if isLocked() then return end
                openPopup(api)
            end)
            return api
        end

        ------------------------------------------------------------- FPS UI
        -- 4: đồng hồ FPS
        local MonRow, MonLeft = CreateInfoRow(FPSTab, "FPS")
        MonRow.LayoutOrder = 4
        MonLeft.Size = UDim2.new(1, 0, 1, 0) -- hàng này không có nút bên phải
        local Readout = label(MonLeft, {
            LayoutOrder = 2,
            Size = UDim2.new(1, -44, 1, 0),
            Text = "...",
            TextSize = 13,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })

        Monitor.start()
        task.spawn(function()
            while ScreenGui.Parent do
                task.wait(0.5)
                if FPSTab.Visible and MainUI.Visible then -- chỉ cập nhật khi tab đang hiển thị
                    if renderingOff() then
                        Readout.Text = "Rendering OFF"
                    else
                        local m = Monitor.snapshot(60) -- ~1 giây gần nhất
                        if m then
                            Readout.Text = string.format("%.0f FPS · %.1f ms · p95 %.0f", m.fps, m.avgMs, m.p95Ms)
                        end
                    end
                end
            end
        end)

        -- 5: FPS Profile (toggle + chọn mode)
        local MODES = { "Balanced", "Performance", "Extreme", "Custom" }
        local startMode = "Balanced"
        for _, m in ipairs(MODES) do
            if Saved.fpsMode == m then startMode = m end
        end
        local Ctl = { mode = startMode, enabled = false }
        local baseline -- số liệu FPS trước khi áp profile (để Benchmark so sánh)
        ScreenGui:SetAttribute("FpsMode", startMode) -- saveSettings đọc giá trị này
        local customOn = {}
        local customRows = {}
        local CUSTOM_DEFS = { -- bật = mức của profile Performance cho feature đó
            { "quality",   "Quality Level",    { cap = 3 } },
            { "lighting",  "Lighting",         2 },
            { "postFx",    "Visual Effects",   2 },
            { "terrain",   "Terrain & Water",  2 },
            { "particles", "Particles",        { rateScale = 0.2, budget = 60, cosmetic = true } },
            { "parts",     "Part Material",    2 },
        }

        local dirty, running = false, false
        local function reconcile()
            dirty = true
            if running then return end
            running = true
            task.spawn(function()
                while dirty do
                    dirty = false
                    local ok, err = pcall(function()
                        if Ctl.enabled then
                            if Perf.profile == nil then
                                baseline = (not renderingOff()) and Monitor.snapshot(180) or nil
                            end
                            local spec
                            if Ctl.mode == "Custom" then
                                spec = {}
                                for _, def in ipairs(CUSTOM_DEFS) do
                                    if customOn[def[1]] then spec[def[1]] = def[3] end
                                end
                            end
                            local applied, why = applyProfile(Ctl.mode, spec)
                            if not applied then warn("[Elysera] FPS profile: " .. tostring(why)) end
                        else
                            restoreState()
                            baseline = nil
                        end
                    end)
                    if not ok then warn("[Elysera] FPS profile: " .. tostring(err)) end
                end
                running = false
            end)
        end

        local function refreshCustomRows()
            for _, row in ipairs(customRows) do row.Visible = (Ctl.mode == "Custom") end
        end

        local Profile = CreateModeFunction(FPSTab, "FPS Profile", MODES, startMode, function(m)
            Ctl.mode = m
            ScreenGui:SetAttribute("FpsMode", m)
            saveSettings()
            refreshCustomRows()
            if Ctl.enabled then reconcile() end
        end)
        Profile.Frame.LayoutOrder = 5

        Profile.Switch:GetAttributeChangedSignal("Toggled"):Connect(function()
            local v = Profile.Switch:GetAttribute("Toggled") == true
            if v == Ctl.enabled then return end -- thay đổi do code (Auto) đã được xử lý
            Ctl.enabled = v
            reconcile()
        end)

        -- 6..11: các toggle của Custom (chỉ hiện khi chọn Custom)
        for i, def in ipairs(CUSTOM_DEFS) do
            local key = def[1]
            local Sw = CreateToggleOption(FPSTab, def[2])
            Sw.Parent.LayoutOrder = 5 + i
            Sw.Parent.Visible = false
            customRows[i] = Sw.Parent
            Sw:GetAttributeChangedSignal("Toggled"):Connect(function()
                customOn[key] = Sw:GetAttribute("Toggled") == true
                if Ctl.enabled and Ctl.mode == "Custom" then reconcile() end
            end)
        end

        refreshCustomRows()

        -- Đổi profile bằng code (Auto Profile): cập nhật winbox + toggle rồi áp
        local function setProfile(mode, enabled)
            if mode then
                Profile.setMode(mode)
                Ctl.mode = mode
                refreshCustomRows()
            end
            Ctl.enabled = enabled and true or false
            Profile.setState(Ctl.enabled)
            reconcile()
        end

        -- 12: Benchmark (đo 5 giây; nếu đã bật profile thì hiện chênh lệch so với trước khi bật)
        local BenchRow, BenchLeft = CreateInfoRow(FPSTab, "Benchmark")
        BenchRow.LayoutOrder = 12
        local BenchBtn = CreateStyledButton(BenchRow, "Run", 70)
        local BenchResult = label(BenchLeft, {
            LayoutOrder = 2,
            Size = UDim2.new(1, -86, 1, 0),
            Text = "",
            TextSize = 13,
            TextColor3 = Theme.Sakura,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        local benching = false
        BenchBtn.Activated:Connect(function()
            if isLocked() or benching then return end
            if renderingOff() then
                BenchResult.Text = "Rendering OFF"
                return
            end
            benching = true
            BenchBtn.Text, BenchBtn.TextColor3 = "Working...", Theme.SubText
            task.spawn(function()
                local ok, r = pcall(Monitor.measure, 5)
                if ok and r then
                    if baseline and Perf.profile then
                        BenchResult.Text = string.format("%.0f FPS (%+.0f) · p95 %+.1f ms",
                            r.fps, r.fps - baseline.fps, r.p95Ms - baseline.p95Ms)
                    else
                        BenchResult.Text = string.format("%.0f FPS · p95 %.1f ms", r.fps, r.p95Ms)
                    end
                else
                    BenchResult.Text = "N/A"
                end
                flashButtonFeedback(BenchBtn, "Run", (ok and r) and "Done!" or "Failed", not (ok and r))
                task.delay(1.2, function() benching = false end)
            end)
        end)

        -- 13: Bottleneck
        local BtlRow, BtlLeft = CreateInfoRow(FPSTab, "Bottleneck")
        BtlRow.LayoutOrder = 13
        local BtlBtn = CreateStyledButton(BtlRow, "Detect", 70)
        local BtlResult = label(BtlLeft, {
            LayoutOrder = 2,
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            Text = "",
            TextSize = 14,
            TextColor3 = Theme.Sakura,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        local BTL_TEXT = { GPU = "GPU", CPU_RENDER = "CPU", SIM = "Script", PHYSICS = "Physics", UNKNOWN = "N/A" }
        local detecting = false
        BtlBtn.Activated:Connect(function()
            if isLocked() or detecting then return end
            detecting = true
            BtlBtn.Text, BtlBtn.TextColor3 = "Working...", Theme.SubText
            task.spawn(function()
                local ok, r = pcall(detectBottleneck, 3)
                local kind = (ok and not renderingOff() and r.kind) or "UNKNOWN"
                BtlResult.Text = BTL_TEXT[kind] or "N/A"
                flashButtonFeedback(BtlBtn, "Detect", ok and "Done!" or "Failed", not ok)
                task.delay(1.2, function() detecting = false end)
            end)
        end)

        -- 14: Auto Profile (opt-in): tự tăng/giảm một bậc theo p95, có hysteresis + cooldown
        local Auto = { on = false }
        function Auto.enable()
            if Auto.on then return end
            Auto.on = true
            task.spawn(function()
                local targetMs, cooldown = 1000 / 45, 30
                local bad, good, changes, lastChange = 0, 0, 0, 0
                while Auto.on and ScreenGui.Parent do
                    task.wait(5)
                    if not (Auto.on and ScreenGui.Parent) then break end
                    local m = Monitor.snapshot(300)
                    if m and not renderingOff() and not Perf.busy and not Popup.open
                        and os.clock() - lastChange > cooldown and changes < 4 then
                        local lvl = (not Ctl.enabled) and 0
                            or (Ctl.mode == "Extreme" and 3 or (Ctl.mode == "Performance" and 2 or 1))
                        if m.p95Ms > targetMs * 1.3 then
                            bad += 1
                            good = 0
                        elseif m.p95Ms < targetMs * 0.8 then
                            good += 1
                            bad = 0
                        else
                            bad, good = 0, 0
                        end

                        if bad >= 3 and lvl < 2 then
                            local b = detectBottleneck(3)
                            if b.kind ~= "SIM" and b.kind ~= "PHYSICS" then
                                setProfile(lvl == 0 and "Balanced" or "Performance", true)
                                lastChange, changes = os.clock(), changes + 1
                            end
                            bad = 0
                        elseif good >= 6 and lvl > 0 and lvl <= 2 then
                            if lvl == 2 then setProfile("Balanced", true) else setProfile(nil, false) end
                            lastChange, changes = os.clock(), changes + 1
                            good = 0
                        end
                    end
                end
            end)
        end
        function Auto.disable() Auto.on = false end

        local AutoSwitch = CreateToggleOption(FPSTab, "Auto Profile")
        AutoSwitch.Parent.LayoutOrder = 14
        AutoSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
            if AutoSwitch:GetAttribute("Toggled") then Auto.enable() else Auto.disable() end
        end)

        -- Cleanup: trả lại mọi thay đổi khi script bị gỡ / nạp lại
        ScreenGui.Destroying:Connect(function()
            Auto.on = false
            Monitor.stop()
            pcall(restoreState, { sync = true })
        end)
    end, function(err)
        warn("[Elysera] FPS system lỗi: " .. tostring(err))
    end)

    --// ---------- Cleanup ----------
    ScreenGui.Destroying:Connect(function()
        notifOn = false
        set3D(true)
        disableNotifBlock()
        Cover:Destroy()
    end)
end
