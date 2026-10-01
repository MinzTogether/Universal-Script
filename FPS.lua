--// ================= FPS TAB (module) =================
-- File này được script chính (MainUI.lua) nạp vào và gọi với 1 bảng ctx
-- chứa các hàm/biến dùng chung của UI.
--
-- Cấu trúc:
--   1. Hạ tầng      : Snapshot, Queue, Monitor, Profiles
--   2. Tính năng    : Lighting, PostFX, Particles, Lights, Materials, Terrain,
--                     QualityLevel, PlayerLOD (đăng ký vào Profiles)
--   3. Tự động hóa  : Dynamic (Auto Performance), CoverEco
--   4. UI           : White/Black Screen, Remove Notification, FPS Monitor,
--                     Boost Fps (dropdown), Auto Performance, Benchmark

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
    local isLocked            = ctx.isLocked or function() return false end -- thay cho biến uiLocked của file chính

    local RunService        = game:GetService("RunService")
    local Lighting          = game:GetService("Lighting")
    local StarterGui        = game:GetService("StarterGui")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Players           = game:GetService("Players")
    local Stats             = game:GetService("Stats")
    local CollectionService = game:GetService("CollectionService")
    local TweenService      = game:GetService("TweenService")

    -- Link PNG (tùy chọn) cho nút mũi tên của dropdown. Để trống = dùng ký tự ▼.
    -- Điền link raw của Arrow.png / arrow2.png sau khi upload lên GitHub.
    local ARROW_DOWN_URL = ""   -- mũi tên chỉ xuống (trạng thái đóng)
    local ARROW_UP_URL   = ""   -- mũi tên chỉ lên  (trạng thái mở); trống = xoay mũi tên xuống 180 độ

    local function setProp(inst, prop, value)
        pcall(function() inst[prop] = value end)
    end

    local function tw(inst, time, props)
        TweenService:Create(inst, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
    end

    --// =====================================================================
    --// 1. HẠ TẦNG
    --// =====================================================================

    --// ---------- SnapshotManager ----------
    local Snapshot = {}
    local buckets  = {}  -- [tag] = { props = weak{[inst]={[prop]={goc}}}, parents = {}, hidden = {} }

    local function bucket(tag)
        local b = buckets[tag]
        if not b then
            b = { props = setmetatable({}, { __mode = "k" }), parents = {}, hidden = {} }
            buckets[tag] = b
        end
        return b
    end

    -- Đặt thuộc tính và nhớ giá trị gốc (chỉ nhớ lần đầu tiên)
    function Snapshot.set(tag, inst, prop, value)
        local okRead, current = pcall(function() return inst[prop] end)
        if not okRead then return false end
        local props = bucket(tag).props
        local rec = props[inst]
        if not rec then rec = {}; props[inst] = rec end
        if rec[prop] == nil then rec[prop] = { current } end -- hộp {x} để lưu được cả false/nil
        if type(value) == "function" then value = value(rec[prop][1]) end
        return (pcall(function() inst[prop] = value end))
    end

    -- Thuộc tính ẩn (cần executor hỗ trợ)
    function Snapshot.setHidden(tag, inst, prop, value)
        if not (gethiddenproperty and sethiddenproperty) then return false end
        local ok, current = pcall(gethiddenproperty, inst, prop)
        if not ok then return false end
        local hidden = bucket(tag).hidden
        hidden[inst] = hidden[inst] or {}
        if hidden[inst][prop] == nil then hidden[inst][prop] = { current } end
        return (pcall(sethiddenproperty, inst, prop, value))
    end

    -- Thay cho Destroy(): gỡ khỏi cây nhưng nhớ chỗ cũ để gắn lại
    function Snapshot.detach(tag, inst)
        local parents = bucket(tag).parents
        if parents[inst] ~= nil then return end
        parents[inst] = inst.Parent or false
        pcall(function() inst.Parent = nil end)
    end

    function Snapshot.restore(tag)
        local b = buckets[tag]
        if not b then return 0 end
        buckets[tag] = nil -- đặt nil trước để các lần set() mới tạo bucket mới
        local n = 0
        for inst, rec in pairs(b.props) do
            for prop, box in pairs(rec) do
                pcall(function() inst[prop] = box[1] end)
            end
            n += 1
            if n % 300 == 0 then task.wait() end
        end
        for inst, parent in pairs(b.parents) do
            if parent and parent:IsDescendantOf(game) then
                pcall(function() inst.Parent = parent end)
            end
        end
        for inst, rec in pairs(b.hidden) do
            for prop, box in pairs(rec) do
                if sethiddenproperty then pcall(sethiddenproperty, inst, prop, box[1]) end
            end
        end
        return n
    end

    function Snapshot.restoreAll()
        local tags = {}
        for tag in pairs(buckets) do tags[#tags + 1] = tag end
        for _, tag in ipairs(tags) do Snapshot.restore(tag) end
    end

    function Snapshot.count(tag)
        local b = buckets[tag]
        if not b then return 0 end
        local n = 0
        for _ in pairs(b.props) do n += 1 end
        for _ in pairs(b.parents) do n += 1 end
        return n
    end

    --// ---------- FrameBudgetQueue ----------
    local Queue = {}
    local lanes, order = {}, {}
    local pending, budget = 0, 0.002 -- 2 ms mỗi frame
    local queueConn
    local idleCallbacks = {}

    local function getLane(fn)
        local lane = lanes[fn]
        if not lane then
            lane = { fn = fn, list = {}, head = 1, tail = 0 }
            lanes[fn] = lane
            order[#order + 1] = lane
        end
        return lane
    end

    local function queueStep(dt)
        -- frame đang chậm (<40 FPS) thì nhường thêm cho render
        local slice = (dt > 1 / 40) and budget * 0.5 or budget
        local deadline = os.clock() + slice
        for _, lane in ipairs(order) do
            while lane.head <= lane.tail do
                local item = lane.list[lane.head]
                lane.head += 1
                pending -= 1
                pcall(lane.fn, item)
                if os.clock() >= deadline then return end
            end
            if lane.tail > 0 then lane.list, lane.head, lane.tail = {}, 1, 0 end
        end
        if pending <= 0 then
            pending = 0
            if queueConn then queueConn:Disconnect(); queueConn = nil end
            local cbs = idleCallbacks
            idleCallbacks = {}
            for _, cb in ipairs(cbs) do task.defer(cb) end
        end
    end

    local function queueStart()
        if not queueConn then queueConn = RunService.Heartbeat:Connect(queueStep) end
    end

    function Queue.push(fn, item)
        local lane = getLane(fn)
        lane.tail += 1
        lane.list[lane.tail] = item
        pending += 1
        queueStart()
    end

    -- list thuộc quyền Queue sau khi gọi (không sao chép để tiết kiệm RAM)
    function Queue.pushList(fn, list)
        local lane = getLane(fn)
        if lane.head > lane.tail then
            lane.list, lane.head, lane.tail = list, 1, #list
        else
            for _, v in ipairs(list) do
                lane.tail += 1
                lane.list[lane.tail] = v
            end
        end
        pending += #list
        queueStart()
    end

    function Queue.drop(fn)
        local lane = lanes[fn]
        if lane then
            pending -= math.max(0, lane.tail - lane.head + 1)
            lane.list, lane.head, lane.tail = {}, 1, 0
        end
    end

    function Queue.whenIdle(cb)
        if pending <= 0 then task.defer(cb) else idleCallbacks[#idleCallbacks + 1] = cb end
    end

    function Queue.setBudget(ms) budget = math.clamp(ms, 0.5, 8) / 1000 end
    function Queue.pending() return pending end

    function Queue.destroy()
        if queueConn then queueConn:Disconnect(); queueConn = nil end
        table.clear(lanes); table.clear(order); table.clear(idleCallbacks)
        pending = 0
    end

    --// ---------- FPSMonitor ----------
    local Monitor = {}
    local SAMPLES = 300 -- số frame giữ lại
    local buf, count, idx = table.create(SAMPLES, 0), 0, 0
    local monConn, onUpdate, acc = nil, nil, 0

    local function compute()
        local n = count
        if n < 10 then return nil end
        local sorted, sum = table.create(n, 0), 0
        for i = 1, n do
            sorted[i] = buf[i]
            sum += buf[i]
        end
        table.sort(sorted)
        local avg = sum / n
        local p99 = sorted[math.max(1, math.ceil(n * 0.99))]
        local mem = 0
        pcall(function() mem = Stats:GetTotalMemoryUsageMb() end)
        return {
            fps = 1 / avg, avgMs = avg * 1000,
            p99Ms = p99 * 1000, low1Fps = 1 / p99,
            memMb = mem, samples = n,
        }
    end

    function Monitor.snapshot() return compute() end
    function Monitor.reset() count, idx, acc = 0, 0, 0 end

    function Monitor.start(callback)
        if callback then onUpdate = callback end
        if monConn then return end
        monConn = RunService.Heartbeat:Connect(function(dt)
            idx = idx % SAMPLES + 1
            buf[idx] = dt
            if count < SAMPLES then count += 1 end
            acc += dt
            if acc >= 0.5 then -- cập nhật 2 lần/giây
                acc = 0
                if onUpdate then onUpdate(compute()) end
            end
        end)
    end

    function Monitor.stop()
        if monConn then monConn:Disconnect(); monConn = nil end
        onUpdate = nil
    end

    function Monitor.benchmark(seconds, callback)
        local wasRunning = monConn ~= nil
        if not wasRunning then Monitor.start() end
        Monitor.reset()
        task.delay(seconds, function()
            local result = compute()
            if not wasRunning then Monitor.stop() end
            callback(result)
        end)
    end

    function Monitor.compare(before, after)
        if not (before and after) then return "N/A" end
        return string.format("FPS %.0f -> %.0f | frame %.1f -> %.1f ms | 1%% low %.0f -> %.0f",
            before.fps, after.fps, before.avgMs, after.avgMs, before.low1Fps, after.low1Fps)
    end

    --// ---------- PerformanceProfiles ----------
    local Profiles = {}
    local features, byClass = {}, {}
    local levels, conns = {}, {} -- levels[name] = 1..3 (nil = tắt)
    local currentName = "Quality"
    local applying, pendingProfile = false, nil

    local PRESETS = {
        Quality     = {},
        Balanced    = { Lighting = 1, PostFX = 1, Particles = 1, Lights = 1, Materials = 1,
                        Terrain = 1, QualityLevel = 1 },
        Performance = { Lighting = 2, PostFX = 2, Particles = 2, Lights = 2, Materials = 2,
                        Terrain = 2, QualityLevel = 2, PlayerLOD = 1 },
        Ultra       = { Lighting = 3, PostFX = 3, Particles = 3, Lights = 3, Materials = 3,
                        Terrain = 3, QualityLevel = 3, PlayerLOD = 2 },
    }
    local PROFILE_ORDER = { "Quality", "Balanced", "Performance", "Ultra" }

    function Profiles.register(name, feature)
        feature.Name = name
        features[name] = feature
        for className in pairs(feature.Classes or {}) do
            byClass[className] = byClass[className] or {}
            table.insert(byClass[className], feature)
        end
    end

    -- Hàm cố định dùng làm "lane" cho Queue
    local function dispatch(inst)
        local list = byClass[inst.ClassName]
        if not list then return end
        for _, f in ipairs(list) do
            local lv = levels[f.Name]
            if lv then f.Handle(inst, lv) end
        end
    end

    local function onAdded(inst)
        if byClass[inst.ClassName] then Queue.push(dispatch, inst) end
    end

    local function syncListeners()
        local need = false
        for name in pairs(levels) do
            if features[name].Classes then
                need = true
                break
            end
        end
        if need and not conns.ws then
            conns.ws = workspace.DescendantAdded:Connect(onAdded)
            conns.lt = Lighting.DescendantAdded:Connect(onAdded)
        elseif not need then
            for k, c in pairs(conns) do c:Disconnect(); conns[k] = nil end
        end
    end

    -- trả về true nếu cần quét lại scene
    local function setLevel(name, level)
        local f = features[name]
        if not f then return false end
        level = level or 0
        if (levels[name] or 0) == level then return false end
        if levels[name] then f.Restore() end -- về gốc trước khi áp mức mới
        levels[name] = level > 0 and level or nil
        if level > 0 and f.Apply then f.Apply(level) end
        return level > 0 and f.Classes ~= nil
    end

    local function rescan()
        Queue.pushList(dispatch, workspace:GetDescendants()) -- đã gồm Camera
        Queue.pushList(dispatch, Lighting:GetDescendants())
    end

    function Profiles.setFeature(name, level)
        local needScan = setLevel(name, level)
        syncListeners()
        if needScan then rescan() end
    end

    local function applyOnce(profileName)
        local preset = PRESETS[profileName]
        currentName = profileName
        local needScan = false
        for name in pairs(features) do
            if setLevel(name, preset[name]) then needScan = true end
        end
        syncListeners()
        if needScan then rescan() end
    end

    -- Có thể yield (Restore dùng task.wait) -> gọi trong task.spawn.
    -- Nếu đang áp một profile mà có yêu cầu mới thì xếp hàng, chạy lại sau.
    function Profiles.apply(profileName)
        if not PRESETS[profileName] then return false end
        if applying then
            pendingProfile = profileName
            return true
        end
        applying = true
        local name = profileName
        while name do
            pendingProfile = nil
            local ok, err = pcall(applyOnce, name)
            if not ok then warn("[Elysera] Profile error: " .. tostring(err)) end
            if Profiles.onChanged then pcall(Profiles.onChanged, currentName) end
            name = pendingProfile
        end
        applying = false
        return true
    end

    function Profiles.restore()
        Profiles.apply("Quality")
        Queue.drop(dispatch)
    end

    function Profiles.current() return currentName, table.clone(levels) end

    --// =====================================================================
    --// 2. TÍNH NĂNG TỐI ƯU (đăng ký vào Profiles)
    --// =====================================================================

    -- Hiệu ứng của chính nhân vật mình, hoặc có tag "KeepFX", thì giữ nguyên
    local function isProtectedFX(inst)
        local char = LocalPlayer.Character
        if char and inst:IsDescendantOf(char) then return true end
        return CollectionService:HasTag(inst, "KeepFX")
    end

    --// ---------- LightingOptimizer ----------
    do
        local TAG = "Lighting"
        local F = {} -- không có Classes: chỉ đổi thuộc tính toàn cục

        function F.Apply(level)
            Snapshot.set(TAG, Lighting, "ShadowSoftness", 0)
            if level >= 2 then
                Snapshot.set(TAG, Lighting, "GlobalShadows", false)
            end
            if level >= 3 then
                Snapshot.set(TAG, Lighting, "EnvironmentDiffuseScale", 0)
                Snapshot.set(TAG, Lighting, "EnvironmentSpecularScale", 0)
                Snapshot.setHidden(TAG, Lighting, "Technology", Enum.Technology.Compatibility)
            end
            ScreenGui:SetAttribute("LightingBoosted", os.clock()) -- báo cho Full Bright (tab Local)
        end

        function F.Restore()
            Snapshot.restore(TAG)
            ScreenGui:SetAttribute("LightingBoosted", os.clock())
        end

        Profiles.register("Lighting", F)
    end

    --// ---------- PostEffectsController ----------
    do
        local TAG = "PostFX"
        local CLASS_LEVEL = {
            BlurEffect = 1, DepthOfFieldEffect = 1, SunRaysEffect = 1,
            BloomEffect = 2, Clouds = 2,
            ColorCorrectionEffect = 3, Atmosphere = 3,
        }
        -- Hiệu ứng game cần giữ (điền tên khi phát hiện cần thiết)
        local KEEP_NAMES = {}

        local F = { Classes = {} }
        for className in pairs(CLASS_LEVEL) do F.Classes[className] = true end

        function F.Handle(inst, level)
            local need = CLASS_LEVEL[inst.ClassName]
            if not need or need > level or KEEP_NAMES[inst.Name] then return end

            if inst.ClassName == "Atmosphere" then
                Snapshot.set(TAG, inst, "Density", 0)
                Snapshot.set(TAG, inst, "Haze", 0)
                Snapshot.set(TAG, inst, "Glare", 0)
            else
                Snapshot.set(TAG, inst, "Enabled", false)
            end
        end

        function F.Restore() Snapshot.restore(TAG) end

        Profiles.register("PostFX", F)
    end

    --// ---------- ParticleBudget ----------
    do
        local TAG = "Particles"
        local CLASS_LEVEL = {
            ParticleEmitter = 1,
            Smoke = 2, Fire = 2, Sparkles = 2, Trail = 2, Beam = 2, Explosion = 2,
        }
        local RATE_FACTOR = { 0.5, 0.25 } -- mức 1, mức 2 (mức 3: tắt hẳn)

        local F = { Classes = {} }
        for className in pairs(CLASS_LEVEL) do F.Classes[className] = true end

        function F.Handle(inst, level)
            local class = inst.ClassName
            local need = CLASS_LEVEL[class]
            if not need or need > level or isProtectedFX(inst) then return end

            if class == "ParticleEmitter" then
                if level >= 3 then
                    Snapshot.set(TAG, inst, "Enabled", false)
                else
                    local f = RATE_FACTOR[level]
                    Snapshot.set(TAG, inst, "Rate", function(orig) return orig * f end)
                end
            elseif class == "Explosion" then
                Snapshot.set(TAG, inst, "Visible", false)
            else
                Snapshot.set(TAG, inst, "Enabled", false)
            end
        end

        function F.Restore() Snapshot.restore(TAG) end

        Profiles.register("Particles", F)
    end

    --// ---------- Lights (giữ tương đương bản cũ: tắt PointLight/SpotLight/SurfaceLight) ----------
    do
        local TAG = "Lights"
        local F = { Classes = { PointLight = true, SpotLight = true, SurfaceLight = true } }

        function F.Handle(inst, level)
            if isProtectedFX(inst) then return end
            if level >= 2 then
                Snapshot.set(TAG, inst, "Enabled", false)
            else
                Snapshot.set(TAG, inst, "Shadows", false)
            end
        end

        function F.Restore() Snapshot.restore(TAG) end

        Profiles.register("Lights", F)
    end

    --// ---------- MaterialLite ----------
    do
        local TAG = "Materials"
        local KEEP_MATERIAL = {
            [Enum.Material.Glass] = true,
            [Enum.Material.Neon] = true,
            [Enum.Material.ForceField] = true,
        }

        local F = {
            Classes = {
                Part = true, MeshPart = true, UnionOperation = true, WedgePart = true,
                CornerWedgePart = true, TrussPart = true, SpawnLocation = true,
                Seat = true, VehicleSeat = true, SpecialMesh = true,
                Decal = true, Texture = true, SurfaceAppearance = true,
            },
        }

        local function isCharacterPart(inst)
            local model = inst:FindFirstAncestorOfClass("Model")
            return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
        end

        function F.Handle(inst, level)
            if isCharacterPart(inst) then return end
            local class = inst.ClassName

            if class == "Decal" or class == "Texture" or class == "SurfaceAppearance" then
                if level >= 3 then Snapshot.detach(TAG, inst) end
                return
            end
            if class == "SpecialMesh" then
                if level >= 3 then Snapshot.set(TAG, inst, "TextureId", "") end
                return
            end

            -- Còn lại là BasePart
            Snapshot.set(TAG, inst, "Reflectance", 0)
            Snapshot.set(TAG, inst, "CastShadow", false)
            if level >= 2 then
                if not KEEP_MATERIAL[inst.Material] then
                    Snapshot.set(TAG, inst, "Material", Enum.Material.SmoothPlastic)
                end
                if class == "MeshPart" then
                    Snapshot.set(TAG, inst, "RenderFidelity", Enum.RenderFidelity.Performance)
                    if level >= 3 then Snapshot.set(TAG, inst, "TextureID", "") end
                end
            end
        end

        function F.Restore() Snapshot.restore(TAG) end

        Profiles.register("Materials", F)
    end

    --// ---------- TerrainWaterLite ----------
    do
        local TAG = "Terrain"
        local F = {}

        function F.Apply(level)
            local terrain = workspace:FindFirstChildOfClass("Terrain")
            if not terrain then return end

            Snapshot.set(TAG, terrain, "WaterWaveSize", 0)
            Snapshot.set(TAG, terrain, "WaterWaveSpeed", 0)
            if level >= 2 then
                Snapshot.set(TAG, terrain, "WaterReflectance", 0)
            end
            if level >= 3 then
                Snapshot.setHidden(TAG, terrain, "Decoration", false)
            end
        end

        function F.Restore() Snapshot.restore(TAG) end

        Profiles.register("Terrain", F)
    end

    --// ---------- QualityLevelController ----------
    local QualityFeature
    do
        local TAG = "Quality"
        local rendering = settings().Rendering
        local MAP = {
            [1] = Enum.QualityLevel.Level05,
            [2] = Enum.QualityLevel.Level03,
            [3] = Enum.QualityLevel.Level01,
        }

        local F = {}

        function F.Apply(level)
            local target = MAP[level]
            if target then Snapshot.set(TAG, rendering, "QualityLevel", target) end
        end

        -- n = 1..21 (Level01 .. Level21)
        function F.SetCustom(n)
            n = math.clamp(math.floor(n), 1, 21)
            local item = Enum.QualityLevel[string.format("Level%02d", n)]
            if item then Snapshot.set(TAG, rendering, "QualityLevel", item) end
        end

        function F.Restore() Snapshot.restore(TAG) end

        QualityFeature = F
        Profiles.register("QualityLevel", F)
    end

    --// ---------- PlayerLOD ----------
    do
        local CONFIG = {
            [1] = { acc = 100 },            -- ẩn phụ kiện khi xa hơn 100 studs
            [2] = { acc = 60, body = 200 }, -- ẩn phụ kiện >60, ẩn thân >200 studs
        }
        local cache = setmetatable({}, { __mode = "k" }) -- [char] = { acc, body, accHidden, bodyHidden, stamp }
        local runId = 0

        local function build(char, old)
            local acc, body = {}, {}
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("BasePart") then
                    if d:FindFirstAncestorOfClass("Accessory") then
                        acc[#acc + 1] = d
                    else
                        body[#body + 1] = d
                    end
                end
            end
            return {
                acc = acc, body = body, stamp = os.clock(),
                accHidden = old and old.accHidden or false,
                bodyHidden = old and old.bodyHidden or false,
            }
        end

        local function setLTM(parts, v)
            for _, p in ipairs(parts) do
                pcall(function() p.LocalTransparencyModifier = v end)
            end
        end

        local function tick(cfg)
            local myChar = LocalPlayer.Character
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            if not myRoot then return end

            for _, plr in ipairs(Players:GetPlayers()) do
                local char = plr ~= LocalPlayer and plr.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    local e = cache[char]
                    if not e or os.clock() - e.stamp > 10 then
                        e = build(char, e)
                        cache[char] = e
                        if e.accHidden then setLTM(e.acc, 1) end
                        if e.bodyHidden then setLTM(e.body, 1) end
                    end
                    local d = (hrp.Position - myRoot.Position).Magnitude
                    local hideAcc = d > cfg.acc
                    local hideBody = cfg.body ~= nil and d > cfg.body
                    if hideAcc ~= e.accHidden then
                        setLTM(e.acc, hideAcc and 1 or 0)
                        e.accHidden = hideAcc
                    end
                    if hideBody ~= e.bodyHidden then
                        setLTM(e.body, hideBody and 1 or 0)
                        e.bodyHidden = hideBody
                    end
                end
            end
        end

        local F = {}

        function F.Apply(level)
            runId += 1
            local id, cfg = runId, CONFIG[math.min(level, 2)]
            task.spawn(function()
                while id == runId do
                    pcall(tick, cfg)
                    task.wait(0.5)
                end
            end)
        end

        function F.Restore()
            runId += 1 -- dừng vòng lặp
            for _, e in pairs(cache) do
                if e.accHidden then setLTM(e.acc, 0) end
                if e.bodyHidden then setLTM(e.body, 0) end
            end
            table.clear(cache)
        end

        Profiles.register("PlayerLOD", F)
    end

    --// =====================================================================
    --// 3. WHITE SCREEN / BLACK SCREEN  (+ CoverEcoMode)
    --// =====================================================================
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

    -- CoverEcoMode: hạ FPS cap khi đang che màn hình để tiết kiệm CPU/GPU
    local CoverEco = {}
    do
        local ECO_CAP = 20         -- FPS cap khi đang che màn hình
        local RESTORE_DEFAULT = 60 -- dùng khi executor không có getfpscap
        local prevCap

        function CoverEco.set(enabled)
            if not setfpscap then return end
            if enabled then
                if prevCap == nil then
                    local ok, cap = pcall(function() return getfpscap and getfpscap() end)
                    prevCap = (ok and type(cap) == "number") and cap or RESTORE_DEFAULT
                end
                pcall(setfpscap, ECO_CAP)
            elseif prevCap ~= nil then
                pcall(setfpscap, prevCap)
                prevCap = nil
            end
        end
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
            CoverEco.set(true)
        else
            Cover.Enabled = false
            set3D(true)
            CoverEco.set(false)
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

    --// =====================================================================
    --// 4. REMOVE NOTIFICATION  (NotificationScanLite)
    --// =====================================================================
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
    local hiddenGuis   = {} -- [inst] = { prop, value, conn, dead }
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
        if hiddenGuis[inst] then return end
        local prop
        if inst:IsA("ScreenGui") then
            prop = "Enabled"
        elseif inst:IsA("GuiObject") then
            prop = "Visible"
        else
            return
        end

        local rec = { prop = prop, value = inst[prop] }
        rec.conn = inst:GetPropertyChangedSignal(prop):Connect(function()
            if notifOn and inst[prop] then setProp(inst, prop, false) end
        end)
        rec.dead = inst.Destroying:Connect(function() -- GUI bị hủy -> tự dọn
            rec.conn:Disconnect()
            rec.dead:Disconnect()
            hiddenGuis[inst] = nil
        end)
        hiddenGuis[inst] = rec
        setProp(inst, prop, false)
    end

    -- Hàm cố định để dùng làm lane trong Queue
    local function scanNotif(inst)
        if inst:IsA("Message") then
            pcall(function() inst:Destroy() end)
        elseif (inst:IsA("GuiObject") or inst:IsA("ScreenGui")) and isNotifName(inst.Name) then
            hideGui(inst)
        end
    end

    local function muteRemote(inst)
        if not getconnections then return end
        if not (inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")) then return end
        if not isNotifName(inst.Name) then return end
        notifRemotes[inst] = true
        local ok, list = pcall(getconnections, inst.OnClientEvent)
        if not ok or type(list) ~= "table" then return end
        for _, c in ipairs(list) do
            if not mutedRemotes[c] then
                mutedRemotes[c] = true
                pcall(function() c:Disable() end)
            end
        end
    end

    local function onGuiAdded(d)
        if notifOn and (d:IsA("GuiObject") or d:IsA("ScreenGui") or d:IsA("Message")) then
            Queue.push(scanNotif, d)
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
            Queue.pushList(scanNotif, pg:GetDescendants())
            table.insert(notifConns, pg.DescendantAdded:Connect(onGuiAdded))
        end

        -- Message cũ thường nằm trực tiếp trong workspace
        Queue.pushList(scanNotif, workspace:GetChildren())
        table.insert(notifConns, workspace.ChildAdded:Connect(function(d)
            if notifOn and d:IsA("Message") then Queue.push(scanNotif, d) end
        end))

        Queue.pushList(muteRemote, ReplicatedStorage:GetDescendants())
        table.insert(notifConns, ReplicatedStorage.DescendantAdded:Connect(function(d)
            if not notifOn then return end
            Queue.push(muteRemote, d)
            task.delay(1, muteRemote, d)
        end))

        task.spawn(function()
            while notifOn and myRun == notifRun and ScreenGui.Parent do
                for r in pairs(notifRemotes) do muteRemote(r) end
                task.wait(5)
            end
        end)
    end

    local function disableNotifBlock()
        for _, c in ipairs(notifConns) do c:Disconnect() end
        table.clear(notifConns)
        Queue.drop(scanNotif)
        Queue.drop(muteRemote)

        for inst, rec in pairs(hiddenGuis) do
            rec.conn:Disconnect()
            rec.dead:Disconnect()
            setProp(inst, rec.prop, rec.value)
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

    --// =====================================================================
    --// 5. DYNAMIC PERFORMANCE (Auto Performance)
    --// =====================================================================
    local Dynamic = {}
    do
        local STEPS = { "Quality", "Balanced", "Performance", "Ultra" }
        local CFG = {
            lowFps = 45, highFps = 75,   -- ngưỡng hạ / nâng
            downAfter = 6, upAfter = 25, -- giây phải duy trì liên tục
            cooldown = 15,               -- giây tối thiểu giữa 2 lần đổi profile
            minIdx = 1, maxIdx = 3,      -- không tự lên Ultra
        }
        Dynamic.config = CFG

        local running, runId, stepIdx = false, 0, 1

        function Dynamic.start(startProfile)
            if running then return end
            running = true
            runId += 1
            local id = runId
            for i, name in ipairs(STEPS) do
                if name == startProfile then stepIdx = i end
            end
            Monitor.start()

            task.spawn(function()
                local below, above, lastChange = nil, nil, 0
                local lastUp, upBlockedUntil = -1e9, 0

                local function go(newIdx)
                    stepIdx = newIdx
                    Profiles.apply(STEPS[stepIdx])
                    Monitor.reset()
                    below, above, lastChange = nil, nil, os.clock()
                end

                while running and id == runId do
                    task.wait(1)
                    local s = (not Cover.Enabled) and Monitor.snapshot() or nil
                    if s then
                        local now = os.clock()
                        if s.fps < CFG.lowFps then
                            below = below or now
                            above = nil
                        elseif s.fps > CFG.highFps then
                            above = above or now
                            below = nil
                        else
                            below, above = nil, nil
                        end

                        if now - lastChange >= CFG.cooldown then
                            if below and now - below >= CFG.downAfter and stepIdx < CFG.maxIdx then
                                if now - lastUp < 60 then upBlockedUntil = now + 120 end
                                go(stepIdx + 1)
                            elseif above and now - above >= CFG.upAfter
                                and stepIdx > CFG.minIdx and now >= upBlockedUntil then
                                lastUp = now
                                go(stepIdx - 1)
                            end
                        end
                    end
                end
            end)
        end

        function Dynamic.stop()
            running = false
            runId += 1
        end
    end

    --// =====================================================================
    --// 6. UI
    --// =====================================================================

    -- Label phụ (căn phải) đặt trong hàng CreateInfoRow
    local function infoLabel(parent, rightOffset)
        rightOffset = rightOffset or 0
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1
        l.AnchorPoint = Vector2.new(1, 0.5)
        l.Position = UDim2.new(1, -rightOffset, 0.5, 0)
        l.Size = UDim2.new(1, -rightOffset - 110, 1, 0)
        l.Font = Enum.Font.GothamMedium
        l.TextSize = 12
        l.TextColor3 = Theme.SubText
        l.TextXAlignment = Enum.TextXAlignment.Right
        l.TextWrapped = true
        l.TextTruncate = Enum.TextTruncate.AtEnd
        l.Text = ""
        l.Parent = parent
        return l
    end

    --// ---------- FPS Monitor ----------
    do
        local Row = CreateInfoRow(FPSTab, "FPS Monitor")
        Row.LayoutOrder = 4
        local Label = infoLabel(Row, 0)
        Label.Text = "..."

        Monitor.start(function(s)
            if not s or not FPSTab.Visible then return end
            if Cover.Enabled then
                Label.Text = "Screen covered (eco)"
            else
                Label.Text = string.format("%d FPS | %.1f ms | 1%% %d | %d MB",
                    math.floor(s.fps + 0.5), s.avgMs, math.floor(s.low1Fps + 0.5), math.floor(s.memMb + 0.5))
            end
        end)
    end

    --// ---------- Dropdown (winbox + danh sách mode) ----------
    local AutoSwitch, setAuto -- khai báo trước vì dropdown cần dùng khi người dùng chọn mode

    local function loadIcon(url, fileName)
        if url == "" or not (writefile and getcustomasset) then return nil end
        local ok, asset = pcall(function()
            local path = "Elysera_" .. fileName
            if not (isfile and isfile(path)) then writefile(path, game:HttpGet(url)) end
            return getcustomasset(path)
        end)
        return ok and asset or nil
    end

    local function CreateDropdownRow(title, layoutOrder, modes, default, onSelect)
        local BOX_W, ITEM_H, LIST_W, GAP = 130, 32, 150, 6
        local LIST_H = #modes * ITEM_H + (#modes - 1) * 2 + 8

        local Row = CreateInfoRow(FPSTab, title)
        Row.LayoutOrder = layoutOrder

        -- winbox: hiện mode đang chọn + mũi tên căn lề phải
        local Box = Instance.new("TextButton")
        Box.AnchorPoint = Vector2.new(1, 0.5)
        Box.Position = UDim2.new(1, 0, 0.5, 0)
        Box.Size = UDim2.fromOffset(BOX_W, 28)
        Box.BackgroundColor3 = Theme.Header
        Box.BorderSizePixel = 0
        Box.AutoButtonColor = false
        Box.Text = ""
        Box.Parent = Row
        Instance.new("UICorner", Box).CornerRadius = UDim.new(0, 6)
        local BoxStroke = Instance.new("UIStroke", Box)
        BoxStroke.Color = Theme.Border
        BoxStroke.Thickness = 1

        local ModeLabel = Instance.new("TextLabel")
        ModeLabel.BackgroundTransparency = 1
        ModeLabel.Position = UDim2.fromOffset(10, 0)
        ModeLabel.Size = UDim2.new(1, -34, 1, 0)
        ModeLabel.Font = Enum.Font.GothamBold
        ModeLabel.TextSize = 13
        ModeLabel.TextColor3 = Theme.Text
        ModeLabel.TextXAlignment = Enum.TextXAlignment.Left
        ModeLabel.TextTruncate = Enum.TextTruncate.AtEnd
        ModeLabel.Text = default
        ModeLabel.Parent = Box

        -- mũi tên (ký tự ▼; thay bằng PNG nếu có link ở đầu file)
        local Arrow = Instance.new("TextLabel")
        Arrow.BackgroundTransparency = 1
        Arrow.AnchorPoint = Vector2.new(1, 0.5)
        Arrow.Position = UDim2.new(1, -6, 0.5, 0)
        Arrow.Size = UDim2.fromOffset(18, 18)
        Arrow.Font = Enum.Font.GothamBold
        Arrow.TextSize = 11
        Arrow.TextColor3 = Theme.SubText
        Arrow.Text = "▼"
        Arrow.Parent = Box

        local ArrowImg, downAsset, upAsset
        task.spawn(function()
            downAsset = loadIcon(ARROW_DOWN_URL, "arrow_down.png")
            upAsset = loadIcon(ARROW_UP_URL, "arrow_up.png")
            if downAsset and Box.Parent then
                ArrowImg = Instance.new("ImageLabel")
                ArrowImg.BackgroundTransparency = 1
                ArrowImg.AnchorPoint = Arrow.AnchorPoint
                ArrowImg.Position = Arrow.Position
                ArrowImg.Size = Arrow.Size
                ArrowImg.Image = downAsset
                ArrowImg.ImageColor3 = Theme.SubText
                ArrowImg.ScaleType = Enum.ScaleType.Fit
                ArrowImg.Parent = Box
                Arrow.Visible = false
            end
        end)

        local open = false
        local function setArrow(isOpen)
            if ArrowImg then
                if upAsset then
                    ArrowImg.Image = isOpen and upAsset or downAsset
                    tw(ArrowImg, 0.15, { Rotation = 0 })
                else
                    tw(ArrowImg, 0.15, { Rotation = isOpen and 180 or 0 })
                end
            else
                tw(Arrow, 0.15, { Rotation = isOpen and 180 or 0 })
            end
            tw(BoxStroke, 0.15, { Color = isOpen and Theme.AccentPurple or Theme.Border })
        end

        -- lớp chặn: vô hiệu hóa UI (không làm mờ), chạm ra ngoài list sẽ đóng list
        local Blocker = Instance.new("TextButton")
        Blocker.Name = "ModeListBlocker"
        Blocker.Size = UDim2.fromScale(1, 1)
        Blocker.BackgroundTransparency = 1
        Blocker.BorderSizePixel = 0
        Blocker.Text = ""
        Blocker.AutoButtonColor = false
        Blocker.Active = true
        Blocker.Visible = false
        Blocker.ZIndex = 200
        Blocker.Parent = ScreenGui

        -- danh sách mode (đè lên UI, cùng theme MainUI)
        local List = Instance.new("Frame")
        List.Name = "ModeList"
        List.BackgroundColor3 = Theme.PanelAlt
        List.BorderSizePixel = 0
        List.ClipsDescendants = true
        List.Visible = false
        List.Size = UDim2.fromOffset(LIST_W, 0)
        List.ZIndex = 201
        List.Parent = ScreenGui
        Instance.new("UICorner", List).CornerRadius = UDim.new(0, 8)
        local ListStroke = Instance.new("UIStroke", List)
        ListStroke.Color = Theme.Border
        ListStroke.Thickness = 1
        local ListPad = Instance.new("UIPadding", List)
        ListPad.PaddingLeft, ListPad.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
        ListPad.PaddingTop, ListPad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
        local ListLayout = Instance.new("UIListLayout", List)
        ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        ListLayout.Padding = UDim.new(0, 2)

        local selected = default
        local items = {}

        local function styleItems()
            for name, item in pairs(items) do
                local isSel = name == selected
                item.BackgroundTransparency = isSel and 0 or 1
                item.TextColor3 = isSel and Theme.Sakura or Theme.Text
            end
        end

        local function closeList()
            if not open then return end
            open = false
            Blocker.Visible = false -- bật lại UI ngay
            setArrow(false)
            tw(List, 0.12, { Size = UDim2.fromOffset(LIST_W, 0) })
            task.delay(0.13, function()
                if not open then List.Visible = false end
            end)
        end

        local function openList()
            if open or isLocked() then return end
            open = true

            -- list nằm ngay dưới hàng chức năng: cạnh phải list thẳng hàng cạnh phải hàng
            local rowPos, rowSize = Row.AbsolutePosition, Row.AbsoluteSize
            local origin, screen = ScreenGui.AbsolutePosition, ScreenGui.AbsoluteSize
            local x = math.max(0, rowPos.X + rowSize.X - LIST_W - origin.X)
            local y = rowPos.Y + rowSize.Y + GAP - origin.Y
            if y + LIST_H > screen.Y then -- hết chỗ phía dưới thì mở lên phía trên
                y = rowPos.Y - GAP - LIST_H - origin.Y
            end

            List.Position = UDim2.fromOffset(x, y)
            List.Size = UDim2.fromOffset(LIST_W, 0)
            List.Visible = true
            Blocker.Visible = true
            styleItems()
            setArrow(true)
            tw(List, 0.15, { Size = UDim2.fromOffset(LIST_W, LIST_H) })
        end

        for i, name in ipairs(modes) do
            local item = Instance.new("TextButton")
            item.LayoutOrder = i
            item.Size = UDim2.new(1, 0, 0, ITEM_H)
            item.BackgroundColor3 = Theme.Header
            item.BackgroundTransparency = 1
            item.BorderSizePixel = 0
            item.AutoButtonColor = false
            item.Font = Enum.Font.GothamBold
            item.TextSize = 13
            item.TextXAlignment = Enum.TextXAlignment.Left
            item.TextColor3 = Theme.Text
            item.Text = name
            item.ZIndex = 202
            item.Parent = List
            Instance.new("UICorner", item).CornerRadius = UDim.new(0, 6)
            local pad = Instance.new("UIPadding", item)
            pad.PaddingLeft = UDim.new(0, 10)
            items[name] = item

            item.MouseEnter:Connect(function()
                if name ~= selected then
                    item.BackgroundTransparency = 0.5
                    item.TextColor3 = Theme.Text
                end
            end)
            item.MouseLeave:Connect(function() styleItems() end)
            item.Activated:Connect(function()
                local changed = name ~= selected
                selected = name
                ModeLabel.Text = name
                styleItems()
                closeList()
                if changed and onSelect then onSelect(name) end
            end)
        end
        styleItems()

        Box.Activated:Connect(function()
            if open then closeList() else openList() end
        end)
        Blocker.Activated:Connect(closeList)

        -- đóng list nếu tab bị ẩn hoặc hàng chức năng bị di chuyển (cuộn/đổi kích thước)
        FPSTab:GetPropertyChangedSignal("Visible"):Connect(function()
            if not FPSTab.Visible then closeList() end
        end)
        Row:GetPropertyChangedSignal("AbsolutePosition"):Connect(closeList)

        return {
            -- đổi mode hiển thị mà không gọi onSelect (dùng khi Auto Performance tự đổi mode)
            set = function(name)
                if items[name] then
                    selected = name
                    ModeLabel.Text = name
                    styleItems()
                end
            end,
            close = closeList,
        }
    end

    --// ---------- Boost Fps (dropdown chọn profile) ----------
    local BoostDropdown = CreateDropdownRow("Boost Fps", 5, PROFILE_ORDER, "Quality", function(name)
        if AutoSwitch and AutoSwitch:GetAttribute("Toggled") then setAuto(false) end -- chọn tay thì tắt Auto
        task.spawn(Profiles.apply, name)
    end)

    -- Auto Performance có thể đổi mode -> cập nhật winbox
    Profiles.onChanged = function(name) BoostDropdown.set(name) end

    --// ---------- Auto Performance ----------
    AutoSwitch, setAuto = CreateToggleOption(FPSTab, "Auto Performance")
    AutoSwitch.Parent.LayoutOrder = 6
    AutoSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
        if AutoSwitch:GetAttribute("Toggled") then
            Dynamic.start((Profiles.current()))
        else
            Dynamic.stop()
        end
    end)

    --// ---------- Benchmark ----------
    do
        local Row = CreateInfoRow(FPSTab, "Benchmark")
        Row.LayoutOrder = 7
        local RunBtn = CreateStyledButton(Row, "Run", 70)
        local Result = infoLabel(Row, 80)
        Result.Text = "Run on Quality first"

        local baseline
        local busy = false
        RunBtn.Activated:Connect(function()
            if isLocked() or busy then return end
            local onQuality = (Profiles.current()) == "Quality"
            if not onQuality and not baseline then
                Result.Text = "Run on Quality first"
                return
            end
            if Cover.Enabled then
                Result.Text = "Turn off screen cover first"
                return
            end
            busy = true
            RunBtn.Text, RunBtn.TextColor3 = "Wait...", Theme.SubText
            Result.Text = "Measuring 5s..."
            Monitor.benchmark(5, function(res)
                if not res then
                    Result.Text = "Not enough samples"
                elseif onQuality then
                    baseline = res
                    Result.Text = string.format("Baseline: %d FPS | %.1f ms | 1%% %d",
                        math.floor(res.fps + 0.5), res.avgMs, math.floor(res.low1Fps + 0.5))
                else
                    Result.Text = Monitor.compare(baseline, res)
                end
                flashButtonFeedback(RunBtn, "Run", res and "Done!" or "Failed", res == nil)
                task.delay(1.2, function() busy = false end)
            end)
        end)
    end

    --// ---------- Cleanup ----------
    ScreenGui.Destroying:Connect(function()
        notifOn = false
        Dynamic.stop()
        Monitor.stop()
        CoverEco.set(false)
        set3D(true)
        disableNotifBlock()
        Cover:Destroy()
        task.spawn(function()
            Profiles.restore()
            Snapshot.restoreAll()
            Queue.destroy()
        end)
    end)
end
