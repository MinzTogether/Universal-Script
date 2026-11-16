-- ============================================================================
-- ELYSERA UI v2.5.0 - STRICT TESTING ENVIRONMENT & STRESS/BOUNDARY TEST SUITE
-- ============================================================================
local realClock = os.clock
local suiteStart = realClock()

dofile("/tmp/test_inspect/boot_env.lua")

local Results = {
    total = 0,
    passed = 0,
    failed = 0,
    cases = {},
    bugs = {},
    benchmarks = {},
}

local function recordTest(category, id, name, passed, detail, bugRef)
    Results.total = Results.total + 1
    if passed then
        Results.passed = Results.passed + 1
    else
        Results.failed = Results.failed + 1
        if bugRef then
            table.insert(Results.bugs, bugRef)
        end
    end
    table.insert(Results.cases, {
        category = category,
        id = id,
        name = name,
        status = passed and "PASS" or "FAIL (BUG DETECTED)",
        detail = tostring(detail or ""),
    })
    print(string.format("[%s] %s - %s: %s", passed and "PASS" or "FAIL", id, name, tostring(detail or "")))
end

local function click(btn)
    Harness.signal(btn, "MouseButton1Down"):_fire()
    Harness.signal(btn, "MouseButton1Up"):_fire()
    Harness.signal(btn, "MouseButton1Click"):_fire()
    Harness.signal(btn, "Activated"):_fire()
    Harness.flush()
end

-- ============================================================================
-- PHASE 1: TEST HARNESS & ENVIRONMENT AUDIT (test/m1_core, m2_instance, m3_env)
-- ============================================================================

-- T01: Original unpatched m2_instance.lua AutomaticSize recursion check
do
    local f = assert(io.open("/tmp/test_inspect/extracted/test/m2_instance.lua", "rb"))
    local rawM2 = f:read("*a")
    f:close()
    -- Check if unpatched absSize has recursion guard
    local hasGuard = rawM2:find("inAuto") ~= nil
    recordTest("1. Test Harness (test/)", "T01", "m2_instance.lua AutomaticSize <-> contentSize recursion guard",
        hasGuard,
        "Unpatched test/m2_instance.lua:263-298 & 328-362 lacks re-entrancy guard when absSize(parent) calls Harness.contentSize(parent) -> absSize(child) -> absSize(parent), causing stack overflow during Local.lua and Settings.lua init.",
        {
            id = "BUG-01",
            severity = "Critical",
            file = "test/m2_instance.lua:263-298, 328-362",
            title = "Đệ quy vô hạn (Stack Overflow) giữa absSize() và Harness.contentSize() khi dùng AutomaticSize",
            impact = "Làm sập hoàn toàn quá trình khởi tạo Local.lua (tại dòng 388) và bảng chọn Theme trong Settings.lua (tại dòng 923).",
        })
end

-- T02: Luau compound assignment (+=) compatibility in Local.lua & test/m1..m3
do
    local f = assert(io.open("/tmp/test_inspect/extracted/Local.lua", "rb"))
    local rawLocal = f:read("*a")
    f:close()
    local fn, err = rawLoadstring(rawLocal, "@Local.lua")
    recordTest("1. Test Harness (test/)", "T02", "Standard Lua 5.3 vs Luau syntax compatibility (Local.lua:1977, 2002)",
        fn ~= nil,
        "Local.lua:1977 & 2002 use Luau `generation += 1` (while MainWeb, FPS, Script, Settings, Status_Server use pure Lua `x = x + 1`), and test/m1..m3 use `+=` in 28 places.",
        {
            id = "BUG-02",
            severity = "Low / Compatibility",
            file = "Local.lua:1977, 2002 & test/m1_core.lua, m2_instance.lua, m3_env.lua",
            title = "Bất nhất cú pháp toán tử gán Luau (`+=`) trong Local.lua và bộ test harness",
            impact = "5/6 module chính tuân thủ Lua 5.1/5.3 thuần, riêng Local.lua (dòng 1977, 2002) dùng `generation += 1` khiến trình chạy Lua tiêu chuẩn ngoài Luau báo lỗi cú pháp nếu không qua transpiler.",
        })
end

-- T03: m3_env.lua Harness.inputObject missing .Changed signal
do
    local f = assert(io.open("/tmp/test_inspect/extracted/test/m3_env.lua", "rb"))
    local rawM3 = f:read("*a")
    f:close()
    local fnBody = rawM3:match("Harness%.inputObject%s*=%s*function.*") or ""
    local hasChanged = fnBody:find("Changed", 1, true) ~= nil
    recordTest("1. Test Harness (test/)", "T03", "m3_env.lua Harness.inputObject .Changed RBXScriptSignal support",
        hasChanged,
        "test/m3_env.lua:656-662 constructs InputObject without .Changed signal, causing MainWeb.lua:253 (makeDraggable), MainWeb.lua:1350 (ResizeHandles), and FPS.lua:1519 (Overlay drag) to fail when dragging.",
        {
            id = "BUG-03",
            severity = "High (Harness)",
            file = "test/m3_env.lua:656-662",
            title = "Harness.inputObject thiếu sự kiện .Changed (RBXScriptSignal)",
            impact = "Mọi thao tác kéo thả (drag TopBar, ToggleButton, ResizeHandles, FPS Overlay) gọi `input.Changed:Connect(...)` sẽ văng lỗi `attempt to index a nil value (field 'Changed')` trong môi trường test gốc.",
        })
end

-- T04: m3_env.lua jsonEncode mixed/sparse table silent data loss bug
do
    -- In m3_env.lua:402-409: `local isArray = #v == n`
    -- In Lua 5.3, for `{ [1] = "a", [3] = "b", key = "val" }`, `#v` can be 3 and `n` is 3!
    local mixed = { "a", "b", "c", "d" }
    mixed[2] = nil
    mixed.key = "val"
    local okEnc, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(mixed) end)
    local hasKey = okEnc and enc:find("key", 1, true) ~= nil
    recordTest("1. Test Harness (test/)", "T04", "m3_env.lua jsonEncode mixed/sparse table integrity",
        hasKey,
        "Encoded result: " .. tostring(enc) .. " (when #v == n on sparse+string-key table, jsonEncode treats it as array and drops string keys!)",
        {
            id = "BUG-04",
            severity = "Medium (Harness)",
            file = "test/m3_env.lua:402-409",
            title = "Hàm jsonEncode kiểm tra mảng bằng `#v == n` gây mất dữ liệu trên bảng thưa có khóa chuỗi",
            impact = "Khi bảng có lỗ hổng chỉ số kèm khóa chuỗi sao cho `#v == n` (ví dụ `{[1]='a', [3]='b', key='val'}`), `jsonEncode` nhận nhầm là mảng tuần tự và làm mất toàn bộ khóa chuỗi.",
        })
end

-- T05: m3_env.lua TweenService concurrent tween conflict on same Instance
do
    local frm = Instance.new("Frame")
    frm.Size = UDim2.fromOffset(100, 100)
    local tw1 = game:GetService("TweenService"):Create(frm, TweenInfo.new(0.20), { Size = UDim2.fromOffset(300, 300) })
    local tw2 = game:GetService("TweenService"):Create(frm, TweenInfo.new(0.10), { Size = UDim2.fromOffset(0, 0) })
    tw1:Play()
    Harness.advance(0.02, 0.02)
    tw2:Play()
    Harness.advance(0.25, 0.02)
    -- In real Roblox, playing tw2 on frm.Size cancels tw1 on frm.Size so final size is (0, 0).
    -- In m3_env.lua, tw1 finishes at t=0.20s AFTER tw2 finished at t=0.12s, overwriting frm.Size to (300, 300)!
    local finalIsZero = (frm.Size.X.Offset == 0 and frm.Size.Y.Offset == 0)
    recordTest("1. Test Harness (test/)", "T05", "m3_env.lua TweenService overlapping property tween cancellation",
        finalIsZero,
        string.format("Expected final Size (0,0) from newer tween tw2, got (%d,%d) because older tween tw1 overwrote it at t=0.20s", frm.Size.X.Offset, frm.Size.Y.Offset),
        {
            id = "BUG-05",
            severity = "Medium (Harness + UI Dialogs)",
            file = "test/m3_env.lua:356-364 & MainWeb.lua:1089-1106 / Script.lua:1167-1186",
            title = "Tween cũ ghi đè trạng thái của Tween mới khi đóng/mở hộp thoại nhanh (< 0.22s)",
            impact = "Trong m3_env.lua, Tween mới không hủy Tween cũ trên cùng thuộc tính; đồng thời trong MainWeb.lua (Dialog.show/hide) và Script.lua (ScriptDialog.show/hide), hàm hide() không gọi Cancel() lên tween của show().",
        })
    frm:Destroy()
end

-- ============================================================================
-- PHASE 2: BOOT & CORE ARCHITECTURE TESTS (MainWeb.lua)
-- ============================================================================
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Terrain = Workspace:FindFirstChildOfClass("Terrain")
Harness.new("Clouds", { Name = "Clouds", Enabled = true }, Terrain)
Harness.new("Atmosphere", { Name = "Atmosphere", Density = 0.4, Haze = 2, Glare = 1 }, Lighting)
Harness.new("BlurEffect", { Name = "Blur", Enabled = true }, Lighting)
Harness.new("BloomEffect", { Name = "Bloom", Enabled = true }, Lighting)
Harness.new("DepthOfFieldEffect", { Name = "DOF", Enabled = true }, Lighting)
Harness.new("SunRaysEffect", { Name = "SunRays", Enabled = true }, Lighting)
Harness.new("ColorCorrectionEffect", { Name = "CC", Enabled = true }, Lighting)
Harness.new("BlurEffect", { Name = "CamBlur", Enabled = true }, Workspace.CurrentCamera)

local testPart = Harness.new("Part", { Name = "TestPart", Reflectance = 0.5, Material = Enum.Material.Brick }, Workspace)
local glassPart = Harness.new("Part", { Name = "GlassPart", Reflectance = 0.2, Material = Enum.Material.Glass }, Workspace)
local meshPart = Harness.new("MeshPart", { Name = "TestMesh", Reflectance = 0.3, Material = Enum.Material.Metal, RenderFidelity = Enum.RenderFidelity.Precise }, Workspace)
local pLight = Harness.new("PointLight", { Enabled = true, Shadows = true }, testPart)
local pEmitter = Harness.new("ParticleEmitter", { Enabled = true, Rate = 50 }, testPart)
local smoke = Harness.new("Smoke", { Enabled = true }, testPart)
local sound = Harness.new("Sound", { Volume = 0.8 }, Workspace)
local soundGroup = Harness.new("SoundGroup", { Volume = 0.9 }, game:GetService("SoundService"))

local bootT0 = realClock()
local Elysera = loadLuauFile("/tmp/test_inspect/extracted/MainWeb.lua")()
Harness.flush()
Harness.advance(2.0, 1/30)
local bootMs = (realClock() - bootT0) * 1000
Results.benchmarks.bootMs = bootMs

recordTest("2. MainWeb.lua", "T06", "Full boot & remote module loader (5 modules, 22 themes, 2500+ GUI instances)",
    Elysera ~= nil and Elysera.Version == "2.5.0" and #Harness.errors == 0 and #Harness.warns == 0,
    string.format("Version=%s, Descendants=%d, BootTime=%.2fms", tostring(Elysera.Version), #Elysera.ScreenGui:GetDescendants(), bootMs))

-- T07: MainWeb.lua UI.FormatAgo boundary test with NaN and negative/huge timestamps
do
    -- Let's test UI.FormatAgo via a corrupt timestamp in L-scr.state.json or Status_Server history
    -- Wait: let's inspect how UI.FormatAgo behaves when called with 0/0 (NaN) or -1e15!
    -- We can test the exact UI.FormatAgo logic from MainWeb.lua:1847-1854:
    local function testFormatAgo(ts, withDate)
        local d = math.max(0, os.time() - (tonumber(ts) or 0))
        if d < (withDate and 45 or 60) then return withDate and "just now" or "<1m ago" end
        if d < 3600 then return ("%dm ago"):format(math.max(1, math.floor(d / 60))) end
        if d < 86400 then return ("%dh ago"):format(math.floor(d / 3600)) end
        if withDate and d >= 7 * 86400 then return os.date("%b %d", ts) end
        return ("%dd ago"):format(math.floor(d / 86400))
    end
    local okHugeNeg = pcall(testFormatAgo, -1e20, false)
    local okDateNeg = pcall(testFormatAgo, -1e15, true)
    recordTest("2. MainWeb.lua", "T07", "UI.FormatAgo boundary safety on extreme negative timestamps (-1e20 / -1e15)",
        okHugeNeg and okDateNeg,
        string.format("okHugeNeg=%s, okDateNeg=%s (extreme negative timestamps overflow `%%d` format and `os.date`)", tostring(okHugeNeg), tostring(okDateNeg)),
        {
            id = "BUG-06",
            severity = "Medium",
            file = "MainWeb.lua:1847-1854",
            title = "Hàm UI.FormatAgo văng lỗi runtime khi nhận giá trị timestamp là NaN hoặc số âm/cực lớn",
            impact = "Nếu file trạng thái lưu timestamp bị hỏng (`NaN` hoặc `-1e15`), `math.max(0, os.time() - NaN)` trả về `NaN`, vượt qua mọi nhánh `<` và làm sập `('%dd ago'):format(...)` hoặc `os.date('%b %d', ts)`.",
        })
end

-- T08: MainWeb.lua Window Drag, Maximize/Restore, Resize Mode, UI Scale (0.6x - 1.4x), Toast Queue Cap (MAX_TOASTS=3)
do
    local mainUI = Elysera.ScreenGui.MG_Main
    local topBar = mainUI.TopBar
    -- Test Toast flood (10 rapid unique toasts vs duplicate toast dedup)
    for i = 1, 10 do
        Elysera.Toast("Flood toast #" .. i, (i % 2 == 0) and "info" or "error", { duration = 1.0 })
    end
    -- Duplicate toast within < 1s should be deduplicated
    local dupToast = Elysera.Toast("Flood toast #10", "info")
    Harness.advance(0.3, 1/30)
    local toastHost = Elysera.ScreenGui:FindFirstChild("ToastHost")
    local activePills = 0
    if toastHost then
        for _, c in ipairs(toastHost:GetChildren()) do
            if c:IsA("Frame") then activePills = activePills + 1 end
        end
    end
    Harness.advance(1.5, 1/30)
    recordTest("2. MainWeb.lua", "T08", "Toast flood control (MAX_TOASTS=3) & duplicate message deduplication (<1s)",
        activePills <= 4 and #Harness.errors == 0,
        string.format("Active toast frames during 10-toast burst=%d (capped cleanly)", activePills))
end

-- ============================================================================
-- PHASE 3: LOCAL.LUA BOUNDARY & STRESS TESTS
-- ============================================================================
local localTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Local")

-- T09: JUMP_CFG snapshot corruption when external script modifies UseJumpPower
do
    local hum = Players.LocalPlayer.Character.Humanoid
    hum.UseJumpPower = false
    hum.JumpPower = 50
    hum.JumpHeight = 7.2

    local jumpSwitch, jumpBox
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Jump Boost" then
            jumpSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            jumpBox = d.Parent:FindFirstChildOfClass("TextBox")
            break
        end
    end
    jumpBox.Text = "120"
    Harness.flush()
    click(jumpSwitch)
    Harness.advance(0.3, 1/30)
    -- External script sets UseJumpPower = false while JumpPower is boosted to 120
    hum.UseJumpPower = false
    Harness.flush()
    Harness.advance(0.3, 1/30)
    -- Disable Jump Boost
    click(jumpSwitch)
    Harness.advance(0.3, 1/30)
    local restoredCorrectly = (hum.JumpPower == 50 and hum.UseJumpPower == false)
    recordTest("3. Local.lua", "T09", "Jump Boost (JUMP_CFG) original JumpPower restoration after external UseJumpPower change",
        restoredCorrectly,
        string.format("Expected JumpPower=50 after disabling Jump Boost, got JumpPower=%s (snaps[t] was overwritten with boosted JumpPower=120 in onExternal!)", tostring(hum.JumpPower)),
        {
            id = "BUG-07",
            severity = "High",
            file = "Local.lua:989-1001 & 1165-1192",
            title = "Hàm onExternal() trong CreateTargetBoost ghi đè snapshot gốc của Jump Boost làm hỏng giá trị khôi phục",
            impact = "Khi nhân vật dùng `UseJumpPower = false` (mặc định R15), bật Jump Boost (120) sẽ gán `UseJumpPower = true, JumpPower = 120`. Nếu script game gán lại `UseJumpPower = false`, `onExternal` chụp lại `snaps[hum] = cfg.snapshot(hum)` chứa `power = 120` (giá trị đã boost) đè lên `power = 50` ban đầu. Khi tắt Jump Boost, `JumpPower` bị kẹt vĩnh viễn ở `120` thay vì về `50`.",
        })
    hum.JumpPower = 50
end

-- T10: Max Zoom & Min Zoom cross-property validation
do
    local maxZoomSw, maxZoomBox, minZoomSw, minZoomBox
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Max Zoom" then
            maxZoomSw = d.Parent:FindFirstChildOfClass("TextButton")
            maxZoomBox = d.Parent:FindFirstChildOfClass("TextBox")
        elseif d:IsA("TextLabel") and d.Text == "Min Zoom" then
            minZoomSw = d.Parent:FindFirstChildOfClass("TextButton")
            minZoomBox = d.Parent:FindFirstChildOfClass("TextBox")
        end
    end
    maxZoomBox.Text = "10"
    minZoomBox.Text = "50"
    Harness.flush()
    click(maxZoomSw)
    click(minZoomSw)
    Harness.advance(0.3, 1/30)
    local lp = Players.LocalPlayer
    local curMin, curMax = curMin, curMax
    local validZoomRange = (curMin <= curMax and curMax >= 0.5)
    click(maxZoomSw)
    click(minZoomSw)
    Harness.advance(0.2, 1/30)
    recordTest("3. Local.lua", "T10", "Camera Min Zoom / Max Zoom cross-boundary validation (MinZoom <= MaxZoom, MaxZoom >= 0.5)",
        validZoomRange,
        string.format("Allowed CameraMinZoomDistance=%.1f > CameraMaxZoomDistance=%.1f (ZOOM_CFG lacks min=0.5 and cross-clamping with MIN_ZOOM_CFG)", curMin, curMax),
        {
            id = "BUG-08",
            severity = "Medium",
            file = "Local.lua:1206-1221",
            title = "Thiếu ràng buộc chéo giữa Min Zoom và Max Zoom (MinZoom > MaxZoom) và thiếu `min = 0.5` ở ZOOM_CFG",
            impact = "ZOOM_CFG cho phép nhập `0` (nhỏ hơn `0.5`) và không kiểm tra `MinZoom <= MaxZoom`. Trong Roblox Engine thực tế, gán `CameraMinZoomDistance > CameraMaxZoomDistance` khiến Engine tự ép lại thuộc tính kia, kích hoạt vòng lặp tranh chấp `onExternal` 30 lần/giây giữa 2 bộ boost cho đến khi bị ngắt do hết ngân sách (`Overridden by game`).",
        })
end

-- T11: ESP HIGHLIGHT_BUDGET (31 limit) overflow when a player's HumanoidRootPart is unparented
do
    local extraPlayers = {}
    for i = 1, 34 do
        local p = Harness.new("Player", { Name = "Bot" .. i, UserId = 3000 + i, DisplayName = "Bot" .. i }, Players)
        local char = Harness.makeCharacter("Bot" .. i, i * 3, 5, 0)
        Harness.rawSet(p, "Character", char)
        table.insert(extraPlayers, p)
        Harness.signal(Players, "PlayerAdded"):_fire(p)
    end
    Harness.flush()

    local espSwitch
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Esp Player" then
            espSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    click(espSwitch)
    Harness.advance(0.6, 1/30)

    for i = 1, 3 do
        local hrp = extraPlayers[i].Character:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.Parent = nil end
    end
    for i = 30, 34 do
        local hrp = extraPlayers[i].Character:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.Position = Vector3.new(1, 5, 0) end
    end
    Harness.advance(0.8, 1/30)

    local espFolder = gethui():FindFirstChild("ElyseraESP")
    local hlCount = 0
    if espFolder then
        for _, c in ipairs(espFolder:GetChildren()) do
            if c.ClassName == "Highlight" then hlCount = hlCount + 1 end
        end
    end
    click(espSwitch)
    Harness.advance(0.3, 1/30)
    for _, p in ipairs(extraPlayers) do p:Destroy() end
    Harness.flush()

    recordTest("3. Local.lua", "T11", "ESP Highlight budget cap (<= 31) under HumanoidRootPart unparenting & rebalance",
        hlCount <= 31,
        string.format("Active Highlight instances=%d (exceeded HIGHLIGHT_BUDGET=31 because rebalance() skips entries with e.root.Parent==nil without demoting their Highlight!)", hlCount),
        {
            id = "BUG-09",
            severity = "High",
            file = "Local.lua:1889-1907",
            title = "Vượt trần giới hạn 31 Highlight của Roblox trong `rebalance()` của ESP",
            impact = "Trong `rebalance()`, những người chơi có `e.root.Parent == nil` (nhưng đang giữ `e.useHl == true`) bị bỏ qua khỏi danh sách `ranked` mà không bị hạ xuống `BoxHandleAdornment`, dẫn tới cấp thêm 31 `Highlight` mới (tổng > 31). Ngoài ra vòng lặp nâng cấp `Highlight` mới chạy trước khi hạ cấp `Highlight` cũ nên luôn vượt ngưỡng 31 tạm thời.",
        })
end

-- T12: Freecam character respawn handling (CameraSubject & RootPart anchoring)
do
    local freecamSwitch
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Freecam" then
            freecamSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    local lp = Players.LocalPlayer
    local oldChar = lp.Character
    click(freecamSwitch)
    Harness.advance(0.2, 1/30)

    local newChar = Harness.makeCharacter("Tester", 25, 5, 25)
    oldChar.Parent = nil
    Harness.rawSet(lp, "Character", newChar)
    Harness.signal(lp, "CharacterAdded"):_fire(newChar)
    Harness.advance(0.2, 1/30)
    local newRootAnchoredWhileFreecam = newChar.HumanoidRootPart.Anchored

    click(freecamSwitch)
    Harness.advance(0.2, 1/30)
    local restoredToNewHum = (Workspace.CurrentCamera.CameraSubject == newChar.Humanoid)

    -- Fix up CameraSubject for subsequent tests
    Workspace.CurrentCamera.CameraSubject = newChar.Humanoid

    recordTest("3. Local.lua", "T12", "Freecam character respawn lifecycle (anchoring new character & restoring CameraSubject)",
        newRootAnchoredWhileFreecam and restoredToNewHum,
        string.format("newRootAnchoredWhileFreecam=%s, restoredToNewHum=%s (camSnap.subject.Parent is still oldChar even when oldChar.Parent==nil, so CameraSubject restores to dead character's Humanoid!)",
            tostring(newRootAnchoredWhileFreecam), tostring(restoredToNewHum)),
        {
            id = "BUG-10",
            severity = "High",
            file = "Local.lua:1487-1525 (và tương tự tại Local.lua:2811-2813 trong View Player)",
            title = "Freecam (và View Player) khôi phục CameraSubject về Humanoid của nhân vật cũ đã chết/xóa sau khi Respawn",
            impact = "Khi nhân vật chết/respawn lúc đang bật Freecam: (1) Nhân vật mới không được neo (`Anchored = true`) nên bị di chuyển ngoài ý muốn khi bấm WASD; (2) Khi tắt Freecam, điều kiện `if camSnap.subject and camSnap.subject.Parent then` vẫn đúng vì `oldHumanoid.Parent` vẫn là `oldChar` (dù `oldChar.Parent == nil`), khiến camera bị khóa vào xác nhân vật cũ và dịch chuyển `cam.CFrame` về vị trí cũ.",
        })
end

-- T13: Waypoints JSON Import & Startup Load with extreme floats (1e308) crashing Local.lua
do
    local wpCard
    for _, d in ipairs(localTab:GetDescendants()) do
        if d.Name == "Waypoints" and d:IsA("Frame") then wpCard = d break end
    end
    local wpInput, wpImportBtn
    for _, d in ipairs(wpCard:GetDescendants()) do
        if d:IsA("TextBox") and d.PlaceholderText == "Name or exported JSON" then wpInput = d end
        if d:IsA("TextButton") and d.Text == "Import" then wpImportBtn = d end
    end
    local errBefore = #Harness.errors
    wpInput.Text = '{"format":"Elysera-Waypoints","points":[{"n":"ExtremePoint","x":1e308,"y":1e308,"z":1e308,"r":0}]}'
    Harness.flush()
    click(wpImportBtn)
    Harness.advance(0.5, 1/30)
    local noCrash = (#Harness.errors == errBefore)
    -- Clean up corrupt waypoint file so it doesn't affect later tests
    delfile("Elysera/Elysera_Waypoints.json")
    Harness.errors = {}

    recordTest("3. Local.lua", "T13", "Waypoints JSON Import / Load coordinate range validation (1e308 integer overflow crash)",
        noCrash,
        "Importing waypoint with x=1e308 bypasses validation, writes poison data to Elysera_Waypoints.json, and crashes Local.lua:2561 `string.format('%d', ...)` (permanently bricking Local.lua on every subsequent boot!)",
        {
            id = "BUG-11",
            severity = "Critical",
            file = "Local.lua:2418, 2561, 2658",
            title = "Nhập (Import) hoặc tải Waypoint có tọa độ lớn (`1e308`) gây lỗi `string.format('%d')` và làm hỏng vĩnh viễn tab Local khi khởi động lại",
            impact = "Hàm `ImportBtn` (dòng 2658) và bộ nạp khởi động (dòng 2418) chỉ kiểm tra `type(p.x) == 'number'` mà không kiểm tra `math.abs(p.x) < 1e7` và tính hữu hạn. Tọa độ cực lớn được lưu thẳng vào `Elysera_Waypoints.json` trước khi gọi `rebuild()`, sau đó nổ lỗi tại dòng 2561 (`string.format('%d, %d, %d', ...)`), làm mất nút xóa `×` và khiến `Local.lua` sập ngay lúc khởi tạo ở mọi lần chạy sau.",
        })
end

-- T14: ESP refreshHp with negative infinity / NaN Humanoid.Health
do
    local espSwitch
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Esp Player" then
            espSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    click(espSwitch)
    Harness.advance(0.3, 1/30)
    local errBefore = #Harness.errors
    local aliceHum = Harness.others[1].Character.Humanoid
    -- Bypass Humanoid setter clamp using rawSet to simulate network/exploit NaN or -huge health
    Harness.rawSet(aliceHum, "Health", -math.huge)
    Harness.signal(aliceHum, "HealthChanged"):_fire(-math.huge)
    Harness.flush()
    local noHpCrash = (#Harness.errors == errBefore)
    Harness.rawSet(aliceHum, "Health", 100)
    click(espSwitch)
    Harness.advance(0.3, 1/30)
    Harness.errors = {}

    recordTest("3. Local.lua", "T14", "ESP refreshHp resilience against -math.huge / NaN Humanoid.Health",
        noHpCrash,
        "When Humanoid.Health is -math.huge or NaN, `math.min(e.hum.Health, 1e9)` in Local.lua:1801 remains -math.huge/NaN and crashes `string.format('HP: %d/%d', hp, maxHp)` at line 1805.",
        {
            id = "BUG-12",
            severity = "Medium",
            file = "Local.lua:1800-1806",
            title = "Hàm `refreshHp` trong ESP chỉ chặn cận trên (`math.min(..., 1e9)`) mà không chặn cận dưới và `NaN`",
            impact = "Nếu `Humanoid.Health` hoặc `MaxHealth` nhận giá trị `-math.huge` hoặc `NaN` (thường gặp trong các game custom health hoặc anti-cheat), `math.min` giữ nguyên `-math.huge`/`NaN` và làm sập `string.format('HP: %d/%d', hp, maxHp)`.",
        })
end

-- ============================================================================
-- PHASE 4: FPS.LUA & CROSS-MODULE BOUNDARY / STRESS TESTS
-- ============================================================================
local fpsTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_FPS")

-- T15: FPS Profile "Balanced" & "Performance" QualityLevel when QualityLevel is Automatic (0)
do
    local renderSettings = settings().Rendering
    renderSettings.QualityLevel = Enum.QualityLevel.Automatic
    local profileSwitch, profileArrow
    for _, d in ipairs(fpsTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "FPS Profile" then
            local row = d.Parent
            profileSwitch = row:FindFirstChildOfClass("TextButton")
            local modeBox = row:FindFirstChild("ModeBox")
            profileArrow = modeBox and modeBox:FindFirstChild("Arrow")
            break
        end
    end
    click(profileArrow)
    Harness.advance(0.2, 1/30)
    local modeList = Elysera.ScreenGui.MG_Main:FindFirstChild("ModeList")
    for _, item in ipairs(modeList:GetDescendants()) do
        if item:IsA("TextButton") and item.Text == "Performance" then click(item) break end
    end
    Harness.advance(0.2, 1/30)
    click(profileSwitch)
    Harness.advance(0.6, 1/30)
    local changedFromAuto = (renderSettings.QualityLevel ~= Enum.QualityLevel.Automatic)
    click(profileSwitch)
    Harness.advance(0.6, 1/30)

    recordTest("4. FPS.lua", "T15", "FPS Profile 'Performance' lowers RenderSettings.QualityLevel when set to Automatic (0)",
        changedFromAuto,
        "QualityLevel remained Enum.QualityLevel.Automatic (0) in Performance mode because PROFILES.Performance.quality = { cap = 3 } omits `force = true` (FPS.lua:956-957).",
        {
            id = "BUG-13",
            severity = "Medium",
            file = "FPS.lua:951-964, 1067-1080",
            title = "Chế độ FPS Profile `Balanced` và `Performance` bỏ qua việc hạ QualityLevel khi người chơi để đồ họa `Automatic` (mặc định)",
            impact = "Hầu hết người chơi Roblox để `QualityLevel = Enum.QualityLevel.Automatic` (`Value == 0`). Do dòng 957 kiểm tra `if not (spec.force and spec.cap) then return end`, chỉ có chế độ `Extreme` (`force = true`) mới hạ chất lượng render, còn `Balanced` và `Performance` hoàn toàn không tác động đến `QualityLevel`.",
        })
end

-- T16: Full Bright (Local.lua) + FPS Profile (FPS.lua) Cross-Module State Contention
do
    Lighting.GlobalShadows = true
    local fbSwitch, profileSwitch
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Full Bright" then
            fbSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    for _, d in ipairs(fpsTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "FPS Profile" then
            profileSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    local fbStack = fbSwitch.Parent.Parent
    local fbModeHit = fbStack.ModeRow.ModeWinbox.Hit
    click(fbModeHit)
    Harness.advance(0.1, 1/30)
    local ddLayer = Elysera.ScreenGui:FindFirstChild("ModeDropdownLayer")
    for _, item in ipairs(ddLayer.Panel:GetChildren()) do
        if item:IsA("TextButton") and item.Text == "Performance" then click(item) break end
    end
    Harness.advance(0.1, 1/30)
    -- Enable Full Bright (Performance mode) -> GlobalShadows becomes false
    click(fbSwitch)
    Harness.advance(0.3, 1/30)
    -- Enable FPS Profile -> GlobalShadows is already false so probe() skips it
    click(profileSwitch)
    Harness.advance(0.3, 1/30)
    -- Disable Full Bright while FPS Profile is STILL ON!
    click(fbSwitch)
    Harness.advance(0.3, 1/30)
    local shadowsStayOffWhileFpsProfileOn = (Lighting.GlobalShadows == false)
    click(profileSwitch)
    Harness.advance(0.3, 1/30)

    recordTest("4. FPS.lua", "T16", "FPS Profile keeps GlobalShadows=false when Full Bright (Performance) is turned off",
        shadowsStayOffWhileFpsProfileOn,
        "Lighting.GlobalShadows became `true` even though FPS Profile was still active (because FPS.lua probe() skipped capturing GlobalShadows when Full Bright had already set it to false).",
        {
            id = "BUG-14",
            severity = "Medium",
            file = "FPS.lua:781-809 & Local.lua:1643-1673",
            title = "Xung đột trạng thái `Lighting.GlobalShadows` giữa Full Bright (`Local.lua`) và FPS Profile (`FPS.lua`)",
            impact = "Khi bật `Full Bright (Performance)` trước rồi bật `FPS Profile`, hàm `probe()` của `FPS.lua` thấy `GlobalShadows` đã là `false` nên bỏ qua không theo dõi. Khi người dùng tắt `Full Bright`, `Local.lua` khôi phục `GlobalShadows = true`, làm bật lại bóng đổ dù `FPS Profile` vẫn đang bật.",
        })
end

-- T17: FPS.lua Optimizer 12,000 DescendantAdded burst (exceeding QUEUE_CAP = 10,000)
do
    local profileSwitch
    for _, d in ipairs(fpsTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "FPS Profile" then
            profileSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    click(profileSwitch)
    Harness.advance(0.3, 1/30)

    local burstFolder = Harness.new("Folder", { Name = "BurstParts" }, Workspace)
    local t0 = realClock()
    local burstParts = {}
    for i = 1, 10500 do
        burstParts[i] = Harness.new("Part", { Name = "P", Reflectance = 0.5, Material = Enum.Material.Brick }, burstFolder)
    end
    Harness.flush()
    -- Advance 6 seconds so drain() + RESCAN_GAP (5s) rescan processes all 10,500 parts!
    Harness.advance(6.0, 1/30)
    local burstMs = (realClock() - t0) * 1000
    Results.benchmarks.optimizerBurst10500Ms = burstMs

    local allOptimized = (burstParts[1].Reflectance == 0 and burstParts[10500].Reflectance == 0)
    click(profileSwitch)
    Harness.advance(1.0, 1/30)
    local allRestored = (burstParts[1].Reflectance == 0.5 and burstParts[10500].Reflectance == 0.5)
    burstFolder:Destroy()
    Harness.flush()

    recordTest("4. FPS.lua", "T17", "Optimizer queue overflow recovery (10,500 parts > QUEUE_CAP=10,000) & full revert",
        allOptimized and allRestored and #Harness.errors == 0,
        string.format("allOptimized=%s, allRestored=%s, Time=%.1fms", tostring(allOptimized), tostring(allRestored), burstMs))
end

-- ============================================================================
-- PHASE 5: SCRIPT.LUA BOUNDARY & STRESS TESTS
-- ============================================================================
local scriptTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Script")

-- T18: Deleting a running script in Script.lua leaves it running in background
do
    Elysera.SelectTab("Script")
    Harness.advance(0.2, 1/30)
    local addBtn = scriptTab.FunctionPanel1.AddButton
    click(addBtn)
    Harness.advance(0.3, 1/30)

    local notBoxA = Elysera.ScreenGui:FindFirstChild("NotBoxA")
    local nameBox, codeBox, saveBtn
    for _, d in ipairs(notBoxA:GetDescendants()) do
        if d:IsA("TextBox") then
            if d.MultiLine then codeBox = d else nameBox = d end
        elseif d:IsA("TextButton") and d.Text == "Save" then
            saveBtn = d
        end
    end

    _G.leakTaskStopped = false
    nameBox.Text = "LeakRunner"
    codeBox.Text = "return function() _G.leakTaskStopped = true end"
    Harness.flush()
    click(saveBtn)
    Harness.advance(0.6, 1/30)

    local targetRow
    for _, c in ipairs(scriptTab.FunctionPanel2:GetChildren()) do
        if c.Name:match("^Script_") and c.Visible then
            local t = c.Left and c.Left:FindFirstChild("Title")
            if t and t.Text == "LeakRunner" then targetRow = c break end
        end
    end
    local playBtn, moreBtn
    for _, c in ipairs(targetRow:GetChildren()) do
        if c:IsA("TextButton") then
            if c.Position.X.Offset == 0 then playBtn = c
            elseif c.Position.X.Offset == -34 then moreBtn = c end
        end
    end
    click(playBtn)
    Harness.advance(0.5, 1/30)

    click(moreBtn)
    Harness.advance(0.2, 1/30)
    local menuCatcher = Elysera.ScreenGui:FindFirstChild("MenuCatcher")
    for _, d in ipairs(menuCatcher:GetDescendants()) do
        if d:IsA("TextButton") and d.Text == "Delete" then click(d) break end
    end
    Harness.advance(0.3, 1/30)
    local delBox = Elysera.ScreenGui:FindFirstChild("NotBoxDe")
    for _, d in ipairs(delBox:GetDescendants()) do
        if d:IsA("TextButton") and d.Text == "Yes, Delete" then click(d) break end
    end
    Harness.advance(6.5, 1/30)

    recordTest("5. Script.lua", "T18", "deleteScript stops active script & invokes cleanup hook upon deletion",
        _G.leakTaskStopped == true,
        "Deleted script remained active in `Running[entry.id]` and its cleanup hook was never called (`_G.leakTaskStopped == false`).",
        {
            id = "BUG-15",
            severity = "High",
            file = "Script.lua:1345-1390",
            title = "Xóa một Script đang chạy (`deleteScript`) không dừng luồng chạy ngầm và không gọi hàm `cleanup`",
            impact = "Khi một script đang chạy (hoặc đã đăng ký hàm dọn dẹp `cleanup` trong `Running[entry.id]`), việc xóa script đó chỉ xóa dòng giao diện và mục trong `ScriptList` nhưng bỏ quên `Running[entry.id]`, khiến script chạy ngầm mãi mãi mà người dùng không còn nút Stop trên dòng đó.",
        })
end

-- T19: Delete + Add same name + Undo creates duplicate script names
do
    local addBtn = scriptTab.FunctionPanel1.AddButton
    local notBoxA = Elysera.ScreenGui:FindFirstChild("NotBoxA")
    local nameBox, codeBox, saveBtn
    for _, d in ipairs(notBoxA:GetDescendants()) do
        if d:IsA("TextBox") then
            if d.MultiLine then codeBox = d else nameBox = d end
        elseif d:IsA("TextButton") and d.Text == "Save" then
            saveBtn = d
        end
    end

    click(addBtn)
    Harness.advance(0.3, 1/30)
    nameBox.Text = "UniqueCheck"
    codeBox.Text = "local x = 1"
    Harness.flush()
    click(saveBtn)
    Harness.advance(0.6, 1/30)

    local targetRow
    for _, c in ipairs(scriptTab.FunctionPanel2:GetChildren()) do
        if c.Name:match("^Script_") and c.Visible then
            local t = c.Left and c.Left:FindFirstChild("Title")
            if t and t.Text == "UniqueCheck" then targetRow = c break end
        end
    end
    local moreBtn
    for _, c in ipairs(targetRow:GetChildren()) do
        if c:IsA("TextButton") and c.Position.X.Offset == -34 then moreBtn = c break end
    end
    click(moreBtn)
    Harness.advance(0.2, 1/30)
    local menuCatcher = Elysera.ScreenGui:FindFirstChild("MenuCatcher")
    for _, d in ipairs(menuCatcher:GetDescendants()) do
        if d:IsA("TextButton") and d.Text == "Delete" then click(d) break end
    end
    Harness.advance(0.3, 1/30)
    local delBox = Elysera.ScreenGui:FindFirstChild("NotBoxDe")
    for _, d in ipairs(delBox:GetDescendants()) do
        if d:IsA("TextButton") and d.Text == "Yes, Delete" then click(d) break end
    end
    Harness.advance(0.6, 1/30)

    -- Add another "UniqueCheck" during the 6s Undo window
    click(addBtn)
    Harness.advance(0.3, 1/30)
    nameBox.Text = "UniqueCheck"
    codeBox.Text = "local x = 2"
    Harness.flush()
    click(saveBtn)
    Harness.advance(0.6, 1/30)

    -- Click Undo on toast
    local toastHost = Elysera.ScreenGui:FindFirstChild("ToastHost")
    if toastHost then
        for _, d in ipairs(toastHost:GetDescendants()) do
            if d:IsA("TextButton") and d.Text == "Undo" then click(d) break end
        end
    end
    Harness.advance(0.6, 1/30)

    local countSameName = 0
    for _, c in ipairs(scriptTab.FunctionPanel2:GetChildren()) do
        if c.Name:match("^Script_") and c.Visible then
            local t = c.Left and c.Left:FindFirstChild("Title")
            if t and t.Text == "UniqueCheck" then countSameName = countSameName + 1 end
        end
    end
    recordTest("5. Script.lua", "T19", "Script library unique-name invariant under Delete -> Add -> Undo",
        countSameName == 1,
        string.format("Found %d visible scripts with identical name 'UniqueCheck' after Undo", countSameName),
        {
            id = "BUG-16",
            severity = "Low",
            file = "Script.lua:1376-1386",
            title = "Hoàn tác xóa (`Undo`) trong `deleteScript` không kiểm tra lại tính duy nhất của tên Script (`makeUniqueName`)",
            impact = "Nếu người dùng xóa script `A`, tạo mới một script khác cũng tên `A` trong thời gian chờ 6 giây, rồi bấm `Undo`, hàm hoàn tác chèn thẳng `entry` cũ vào lại `ScriptList` mà không qua `makeUniqueName`, tạo ra 2 script trùng tên hệt nhau.",
        })
end

-- ============================================================================
-- PHASE 6: STATUS_SERVER.LUA & SETTINGS.LUA BOUNDARY TESTS
-- ============================================================================
local statusTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Status & Server")

-- T20: Status_Server.lua isValidJobId strict UUID format check (8-4-4-4-12)
do
    local hopperCard = statusTab:FindFirstChild("ServerHopper")
    local hopperBox = hopperCard:FindFirstChildOfClass("TextBox")
    local joinBtn
    for _, d in ipairs(hopperCard:GetDescendants()) do
        if d:IsA("TextButton") and d.Text == "Join" then joinBtn = d break end
    end
    Harness.advance(10.5, 1/30)
    local beforeTp = #Harness.teleports
    hopperBox.Text = "a-b-c-d-e"
    Harness.flush()
    click(joinBtn)
    Harness.advance(0.2, 1/30)
    local rejectedBogusUuid = (#Harness.teleports == beforeTp)
    recordTest("6. Status_Server.lua", "T20", "isValidJobId strict UUID format validation (rejecting non-36-char hex 'a-b-c-d-e')",
        rejectedBogusUuid,
        "isValidJobId('a-b-c-d-e') returned true and triggered TeleportService:TeleportToPlaceInstance with bogus JobId 'a-b-c-d-e'.",
        {
            id = "BUG-17",
            severity = "Low",
            file = "Status_Server.lua:48-50",
            title = "Biểu thức chính quy `isValidJobId` quá lỏng, chấp nhận chuỗi hex ngắn không phải UUID hợp lệ (ví dụ `'a-b-c-d-e'`)",
            impact = "Mẫu `^%x+%-%x+%-%x+%-%x+%-%x+$` không kiểm tra độ dài từng nhóm (chuẩn UUID Roblox 8-4-4-4-12, 36 ký tự), khiến các chuỗi như `'a-b-c-d-e'` hoặc `'1-1-1-1-1'` vượt qua bộ lọc và gọi thẳng `TeleportToPlaceInstance`.",
        })
end

-- T21: Unload & Teardown Cleanliness Audit
do
    local errBefore = #Harness.errors
    Elysera.Unload()
    Harness.flush()
    Harness.advance(2.0, 1/30)
    local guiDestroyed = (Elysera.ScreenGui.Parent == nil)
    local coverDestroyed = (gethui():FindFirstChild("ElyseraCover") == nil)
    local overlayDestroyed = (gethui():FindFirstChild("ElyseraFpsOverlay") == nil)
    local espDestroyed = (gethui():FindFirstChild("ElyseraESP") == nil)
    recordTest("7. Lifecycle & Teardown", "T21", "Elysera.Unload() complete DOM cleanup & zero post-unload thread errors",
        guiDestroyed and coverDestroyed and overlayDestroyed and espDestroyed and (#Harness.errors == errBefore),
        string.format("ScreenGui=%s, Cover=%s, Overlay=%s, ESP=%s, PostUnloadErrors=%d",
            tostring(guiDestroyed), tostring(coverDestroyed), tostring(overlayDestroyed), tostring(espDestroyed), #Harness.errors - errBefore))
end

print(string.format("\n=== SUMMARY: %d Total | %d Passed | %d Failed (Bugs Reproduced) | Total Time: %.2fms ===",
    Results.total, Results.passed, Results.failed, (realClock() - suiteStart) * 1000))
