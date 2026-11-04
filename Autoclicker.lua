-- Autoclicker (+ Hold + Grid TP)
-- use this in your favorite executor: Delta, Fluxus, Codex, Seliware and others.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- [MỚI] Thời gian giữ mặc định: 1200 giây = 20 phút (đổi được ngay trong ô "Hold (s)" trên UI)
local HOLD_DEFAULT = 1200

-- [MỚI] Cấu hình chế độ GRID (tự TP theo bảng toạ độ 13x13 + giữ chuột)
local TP_Y        = 2514   -- độ cao khi TP tới mỗi điểm
local Y_LOW       = 1674   -- chạm (<=) mức này thì sang điểm tiếp theo
local Y_HIGH      = 3354   -- chạm (>=) mức này thì sang điểm tiếp theo
local CAM_HEIGHT  = 15     -- camera đặt cao hơn nhân vật bao nhiêu stud (nhìn thẳng xuống)
local SETTLE_TIME = 0.5    -- chờ sau khi TP trước khi ấn giữ (giây)
local ENTER_DELAY = 1      -- chờ sau khi gọi Mining (vào minigame) rồi mới TP tới điểm 1 (giây)
local LOOP_WAIT   = 25 * 60 -- chờ sau khi LeaveMining rồi mới bắt đầu vòng mới (giây) = 25 phút
local TARGET_SIZE = 80     -- kích thước ảnh mục tiêu trên màn hình (px). Tâm ảnh = điểm click/ấn giữ
-- [FIX LỆCH CHUỘT] Độ lệch cố định giữa toạ độ GỬI cho VirtualInputManager và vị trí con trỏ THẬT trên màn hình (đơn vị: px GUI).
--   Đo từ ảnh chụp: gửi click đúng tâm ảnh thì con trỏ rơi lệch lên-trái ~(37, 58) => cộng bù lại để con trỏ rơi ĐÚNG tâm ảnh.
--   Chỉnh nhanh ngay trong game bằng ô "Offset X / Y" trên bảng điều khiển: con trỏ còn nằm TRÊN-TRÁI tâm => TĂNG số; nằm DƯỚI-PHẢI tâm => GIẢM số; 0 / 0 = tắt bù.
local CLICK_OFFSET_X = 37
local CLICK_OFFSET_Y = 58
local clickOffset = Vector2.new(CLICK_OFFSET_X, CLICK_OFFSET_Y) -- giá trị đang dùng (ô Offset X / Y trong game sửa biến này)

-- Bảng toạ độ theo đúng thứ tự STT trong file Excel: Z từ -155 -> -107, mỗi hàng X từ 1520 -> 1568, bước 4 (169 điểm)
local GRID_X0, GRID_Z0, GRID_STEP, GRID_N = 1520, -155, 4, 13
local GRID_POINTS = {}
for j = 0, GRID_N - 1 do
    for i = 0, GRID_N - 1 do
        table.insert(GRID_POINTS, { GRID_X0 + i * GRID_STEP, GRID_Z0 + j * GRID_STEP })
    end
end

-- [MỚI] Ảnh mục tiêu (PNG 240x240, nhúng dạng base64). Tâm giao điểm 2 đường thẳng = tâm ảnh = điểm click/ấn giữ
local TARGET_FILE = "Sp1ngTarget_v1.png"
local TARGET_PNG_B64 = [==[
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
]==]

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_LOOKUP = {}
for i = 1, #B64_CHARS do
    B64_LOOKUP[B64_CHARS:sub(i, i)] = i - 1
end

local function base64Decode(data)
    data = data:gsub("[^%w%+/=]", "")
    local out, n = {}, 0
    for i = 1, #data, 4 do
        local c1 = B64_LOOKUP[data:sub(i, i)]
        local c2 = B64_LOOKUP[data:sub(i + 1, i + 1)]
        local c3 = B64_LOOKUP[data:sub(i + 2, i + 2)] -- nil nếu là '='
        local c4 = B64_LOOKUP[data:sub(i + 3, i + 3)] -- nil nếu là '='
        local v = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
        n = n + 1
        out[n] = string.char(math.floor(v / 65536) % 256)
        if c3 then
            n = n + 1
            out[n] = string.char(math.floor(v / 256) % 256)
            if c4 then
                n = n + 1
                out[n] = string.char(v % 256)
            end
        end
    end
    return table.concat(out)
end

-- Ghi ảnh ra file của executor rồi lấy asset (cần writefile + getcustomasset). Không hỗ trợ -> trả nil, dùng 🎯 như cũ
local function loadTargetImage()
    local ok, asset = pcall(function()
        local getAsset = getcustomasset or getsynasset
        if not (writefile and getAsset) then
            error("executor không hỗ trợ writefile/getcustomasset")
        end
        if not (isfile and isfile(TARGET_FILE)) then
            writefile(TARGET_FILE, base64Decode(TARGET_PNG_B64))
        end
        return getAsset(TARGET_FILE)
    end)
    if ok and type(asset) == "string" and asset ~= "" then
        return asset
    end
    warn("[Autoclicker] Không tải được ảnh mục tiêu, dùng 🎯: " .. tostring(asset))
    return nil
end

-- 1. Notification initiale
local notifGui = Instance.new("ScreenGui")
notifGui.Name = "Sp1ngNotification"
notifGui.ResetOnSpawn = false
notifGui.Parent = playerGui

local notifFrame = Instance.new("Frame")
notifFrame.Size = UDim2.new(0, 240, 0, 65)
notifFrame.Position = UDim2.new(1, -250, 0, 20)
notifFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
notifFrame.BorderSizePixel = 0
notifFrame.Parent = notifGui

local notifCorner = Instance.new("UICorner")
notifCorner.CornerRadius = UDim.new(0, 8)
notifCorner.Parent = notifFrame

local notifStroke = Instance.new("UIStroke")
notifStroke.Color = Color3.fromRGB(0, 255, 120)
notifStroke.Thickness = 1.5
notifStroke.Parent = notifFrame

local notifTitle = Instance.new("TextLabel")
notifTitle.Size = UDim2.new(1, -15, 0, 25)
notifTitle.Position = UDim2.new(0, 10, 0, 8)
notifTitle.BackgroundTransparency = 1
notifTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
notifTitle.TextSize = 14
notifTitle.Font = Enum.Font.GothamBold
notifTitle.TextXAlignment = Enum.TextXAlignment.Left
notifTitle.Text = "auto click"
notifTitle.Parent = notifFrame

local notifSub = Instance.new("TextLabel")
notifSub.Size = UDim2.new(1, -15, 0, 20)
notifSub.Position = UDim2.new(0, 10, 0, 33)
notifSub.BackgroundTransparency = 1
notifSub.TextColor3 = Color3.fromRGB(0, 255, 120)
notifSub.TextSize = 12
notifSub.Font = Enum.Font.Gotham
notifSub.TextXAlignment = Enum.TextXAlignment.Left
notifSub.Text = "made by sp1ng"
notifSub.Parent = notifFrame

-- Disparition de la notification après 4 secondes
task.delay(4, function()
    if notifGui then notifGui:Destroy() end
end)

-- [MỚI] Chạy lại script thì xoá GUI cũ (sự kiện Destroying bên dưới sẽ tự nhả chuột nếu đang giữ)
local oldGui = playerGui:FindFirstChild("Sp1ngAutoClicker")
if oldGui then oldGui:Destroy() end

-- 2. UI Principale de l'Autoclicker avec cible déplaçable
decalGui = Instance.new("ScreenGui")
decalGui.Name = "Sp1ngAutoClicker"
decalGui.ResetOnSpawn = false
-- [FIX LỆCH CLICK] Cho ScreenGui phủ kín màn hình, KHÔNG chừa inset (thanh topbar + tai thỏ/viền an toàn).
-- Nguyên nhân cũ: AbsolutePosition tính theo gốc GUI (đã trừ inset) còn VirtualInputManager nhận toạ độ MÀN HÌNH THẬT
--   => click ảo bị lệch lên-trái đúng bằng inset (trên máy bạn ~36px ngang, ~57px dọc) nên không trúng tâm vòng tròn.
-- Bỏ inset thì AbsolutePosition == toạ độ màn hình thật => click rơi đúng tâm.
-- [FIX 2] Bỏ inset vẫn CHƯA đủ trên máy này: engine còn dịch click ảo lên-trái ~(37, 58) px.
--   => đã cộng bù trong getTargetPos() bằng clickOffset (chỉnh bằng CLICK_OFFSET_X/Y hoặc ô Offset X / Y).
-- Thứ tự quan trọng: đặt IgnoreGuiInset trước, ScreenInsets sau để None là giá trị cuối cùng.
decalGui.IgnoreGuiInset = true
pcall(function() decalGui.ScreenInsets = Enum.ScreenInsets.None end) -- client cũ chưa có ScreenInsets thì bỏ qua
decalGui.Parent = playerGui

-- Bouton cible à glisser (Draggable target)
-- [ĐỔI] Dùng ảnh thay cho 🎯; tâm nút (AbsolutePosition + AbsoluteSize/2) = tâm ảnh = điểm click/ấn giữ
local targetImage = loadTargetImage()
local targetSize = targetImage and TARGET_SIZE or 50
local targetBtn
-- [FIX] Dùng ImageLabel/TextLabel (không phải *Button) + thuộc tính Active để bật/tắt việc "nuốt" input:
--   click ảo giờ rơi đúng TÂM vòng tròn, nếu vòng tròn là nút thì chính nó sẽ chặn cú click, game không nhận được.
--   Lúc rảnh Active = true (kéo thả được); lúc đang chạy Active = false (click xuyên qua xuống game) - xem setTargetSolid().
if targetImage then
    targetBtn = Instance.new("ImageLabel")
    targetBtn.Image = targetImage
    targetBtn.ScaleType = Enum.ScaleType.Stretch
    targetBtn.BackgroundTransparency = 1 -- giữ phần trong suốt của ảnh
else
    targetBtn = Instance.new("TextLabel") -- dự phòng: như bản cũ
    targetBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    targetBtn.Text = "🎯"
    targetBtn.TextSize = 22
end
targetBtn.Active = true
targetBtn.Size = UDim2.new(0, targetSize, 0, targetSize)
targetBtn.Position = UDim2.new(0.5, -targetSize / 2, 0.4, 0)
targetBtn.Parent = decalGui

local targetCorner = Instance.new("UICorner")
targetCorner.CornerRadius = UDim.new(1, 0)
targetCorner.Parent = targetBtn

local targetStroke = Instance.new("UIStroke")
targetStroke.Color = Color3.fromRGB(0, 255, 120)
targetStroke.Thickness = 2
targetStroke.Parent = targetBtn

-- Panneau de contrôle (Start / Stop)
-- [ĐỔI] Panel rộng 260 (cũ 160) để chứa thêm nút MODE, ô Hold (s) và dòng trạng thái
local controlFrame = Instance.new("Frame")
controlFrame.Size = UDim2.new(0, 260, 0, 126) -- [ĐỔI] 95 -> 126 để chứa hàng Offset X / Y
controlFrame.Position = UDim2.new(0.5, -130, 0.6, 0)
controlFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
controlFrame.BorderSizePixel = 0
controlFrame.Parent = decalGui

local controlCorner = Instance.new("UICorner")
controlCorner.CornerRadius = UDim.new(0, 10)
controlCorner.Parent = controlFrame

local controlStroke = Instance.new("UIStroke")
controlStroke.Color = Color3.fromRGB(50, 50, 50)
controlStroke.Thickness = 1
controlStroke.Parent = controlFrame

local startBtn = Instance.new("TextButton")
startBtn.Size = UDim2.new(0, 110, 0, 35) -- [ĐỔI] 140 -> 110
startBtn.Position = UDim2.new(0, 10, 0, 10)
startBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 90)
startBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
startBtn.TextSize = 14
startBtn.Font = Enum.Font.GothamBold
startBtn.Text = "START"
startBtn.Parent = controlFrame

local startCorner = Instance.new("UICorner")
startCorner.CornerRadius = UDim.new(0, 6)
startCorner.Parent = startBtn

local stopBtn = Instance.new("TextButton")
stopBtn.Size = UDim2.new(0, 110, 0, 35) -- [ĐỔI] 140 -> 110
stopBtn.Position = UDim2.new(0, 10, 0, 52)
stopBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
stopBtn.TextSize = 14
stopBtn.Font = Enum.Font.GothamBold
stopBtn.Text = "STOP"
stopBtn.Parent = controlFrame

local stopCorner = Instance.new("UICorner")
stopCorner.CornerRadius = UDim.new(0, 6)
stopCorner.Parent = stopBtn

-- [MỚI] Nút đổi chế độ: HOLD (giữ chuột) <-> CLICK (click liên tục như bản cũ)
local modeBtn = Instance.new("TextButton")
modeBtn.Size = UDim2.new(0, 120, 0, 26)
modeBtn.Position = UDim2.new(0, 130, 0, 10)
modeBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
modeBtn.TextColor3 = Color3.fromRGB(80, 200, 255)
modeBtn.TextSize = 13
modeBtn.Font = Enum.Font.GothamBold
modeBtn.Text = "MODE: GRID"
modeBtn.Parent = controlFrame

local modeCorner = Instance.new("UICorner")
modeCorner.CornerRadius = UDim.new(0, 6)
modeCorner.Parent = modeBtn

-- [MỚI] Ô nhập thời gian giữ (giây) - chỉ hiện ở chế độ HOLD
local holdLabel = Instance.new("TextLabel")
holdLabel.Size = UDim2.new(0, 56, 0, 22)
holdLabel.Position = UDim2.new(0, 130, 0, 40)
holdLabel.BackgroundTransparency = 1
holdLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
holdLabel.TextSize = 12
holdLabel.Font = Enum.Font.Gotham
holdLabel.TextXAlignment = Enum.TextXAlignment.Left
holdLabel.Text = "Hold (s)"
holdLabel.Visible = false -- [ĐỔI] mặc định là GRID nên ẩn ô Hold
holdLabel.Parent = controlFrame

local holdBox = Instance.new("TextBox")
holdBox.Size = UDim2.new(0, 60, 0, 22)
holdBox.Position = UDim2.new(0, 190, 0, 40)
holdBox.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
holdBox.TextColor3 = Color3.fromRGB(255, 255, 255)
holdBox.PlaceholderText = tostring(HOLD_DEFAULT)
holdBox.ClearTextOnFocus = true
holdBox.TextSize = 13
holdBox.Font = Enum.Font.GothamBold
holdBox.Text = tostring(HOLD_DEFAULT)
holdBox.Visible = false -- [ĐỔI] mặc định là GRID nên ẩn ô Hold
holdBox.Parent = controlFrame

local holdBoxCorner = Instance.new("UICorner")
holdBoxCorner.CornerRadius = UDim.new(0, 6)
holdBoxCorner.Parent = holdBox

-- [MỚI] Ô chọn điểm bắt đầu (chỉ hiện ở chế độ GRID): 1..169, tự cập nhật theo điểm đang chạy để START lại thì chạy tiếp
local idxLabel = Instance.new("TextLabel")
idxLabel.Size = UDim2.new(0, 56, 0, 22)
idxLabel.Position = UDim2.new(0, 130, 0, 40)
idxLabel.BackgroundTransparency = 1
idxLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
idxLabel.TextSize = 12
idxLabel.Font = Enum.Font.Gotham
idxLabel.TextXAlignment = Enum.TextXAlignment.Left
idxLabel.Text = "Point #"
idxLabel.Parent = controlFrame

local idxBox = Instance.new("TextBox")
idxBox.Size = UDim2.new(0, 60, 0, 22)
idxBox.Position = UDim2.new(0, 190, 0, 40)
idxBox.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
idxBox.TextColor3 = Color3.fromRGB(255, 255, 255)
idxBox.PlaceholderText = "1"
idxBox.ClearTextOnFocus = true
idxBox.TextSize = 13
idxBox.Font = Enum.Font.GothamBold
idxBox.Text = "1"
idxBox.Parent = controlFrame

local idxBoxCorner = Instance.new("UICorner")
idxBoxCorner.CornerRadius = UDim.new(0, 6)
idxBoxCorner.Parent = idxBox

-- [MỚI] Dòng trạng thái (IDLE / HOLD mm:ss / CLICKING / GRID n/169)
local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 120, 0, 22)
statusLabel.Position = UDim2.new(0, 130, 0, 66)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(0, 255, 120)
statusLabel.TextSize = 12
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = "IDLE"
statusLabel.Parent = controlFrame

-- [MỚI] Hàng chỉnh độ lệch chuột "Offset X / Y": bù cho việc click ảo bị dịch lên-trái. Chỉnh ngay trong game, áp dụng từ lần ấn kế tiếp.
do
    local offLabel = Instance.new("TextLabel")
    offLabel.Size = UDim2.new(0, 110, 0, 22)
    offLabel.Position = UDim2.new(0, 10, 0, 96)
    offLabel.BackgroundTransparency = 1
    offLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    offLabel.TextSize = 12
    offLabel.Font = Enum.Font.Gotham
    offLabel.TextXAlignment = Enum.TextXAlignment.Left
    offLabel.Text = "Offset X / Y"
    offLabel.Parent = controlFrame

    local function makeOffsetBox(xPos, initial)
        local box = Instance.new("TextBox")
        box.Size = UDim2.new(0, 56, 0, 22)
        box.Position = UDim2.new(0, xPos, 0, 96)
        box.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
        box.TextColor3 = Color3.fromRGB(255, 255, 255)
        box.PlaceholderText = "0"
        box.ClearTextOnFocus = true
        box.TextSize = 13
        box.Font = Enum.Font.GothamBold
        box.Text = tostring(initial)
        box.Parent = controlFrame

        local boxCorner = Instance.new("UICorner")
        boxCorner.CornerRadius = UDim.new(0, 6)
        boxCorner.Parent = box
        return box
    end

    local offXBox = makeOffsetBox(130, CLICK_OFFSET_X)
    local offYBox = makeOffsetBox(194, CLICK_OFFSET_Y)

    -- Đọc lại cả 2 ô; nhập sai/để trống thì giữ giá trị trước đó
    local function applyOffset()
        local x = tonumber(offXBox.Text)
        local y = tonumber(offYBox.Text)
        if not (x and x == x and math.abs(x) <= 500) then x = clickOffset.X end
        if not (y and y == y and math.abs(y) <= 500) then y = clickOffset.Y end
        clickOffset = Vector2.new(x, y)
        offXBox.Text = tostring(x)
        offYBox.Text = tostring(y)
    end
    offXBox.FocusLost:Connect(applyOffset)
    offYBox.FocusLost:Connect(applyOffset)
end

-- [MỚI] Trạng thái
local mode = "GRID"                 -- "GRID" (mặc định: TP theo bảng + giữ chuột), "HOLD" (giữ chuột theo giây) hoặc "CLICK" (click liên tục như bản cũ)
local clicking = false              -- đang autoclick (chế độ CLICK)
local holding = false               -- đang giữ chuột (chế độ HOLD)
local holdPos = nil                 -- vị trí đã nhấn xuống, dùng để nhả đúng chỗ
local holdSession = 0               -- đổi mỗi lần start/stop để huỷ bộ đếm giờ cũ
local holdSeconds = HOLD_DEFAULT    -- thời gian giữ hiện tại (giây)

-- Logique de glissement (Drag) pour le bouton cible
local dragging, dragInput, dragStart, startPos
targetBtn.InputBegan:Connect(function(input)
    if holding or clicking then return end -- [MỚI] đang giữ/click thì khoá vị trí mục tiêu (bấm STOP rồi mới kéo được)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = targetBtn.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        targetBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

-- [MỚI] Hàm hỗ trợ
local function formatTime(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

-- Tâm vòng tròn (= giao điểm 2 đường thẳng trong ảnh) theo toạ độ MÀN HÌNH THẬT (chỉ để nhìn / tính toán).
local function getTargetCenter()
    return targetBtn.AbsolutePosition + (targetBtn.AbsoluteSize / 2)
end

-- [FIX LỆCH CHUỘT] Toạ độ gửi cho VirtualInputManager = tâm ảnh + độ lệch bù (clickOffset).
-- Engine dịch click ảo lên-trái đúng bằng độ lệch đó => cộng bù ở đây thì con trỏ chuột rơi ĐÚNG tâm ảnh.
-- MỌI chỗ ấn / nhả / click (START, HOLD, GRID, CLICK) đều lấy toạ độ qua hàm này nên luôn thống nhất.
local function getTargetPos()
    return getTargetCenter() + clickOffset
end

-- [FIX] solid = false: vòng tròn "xuyên thấu" - click/giữ ảo tại tâm sẽ đi thẳng xuống game, không bị vòng tròn chặn
--       solid = true : vòng tròn nhận chạm lại (kéo thả được). Bật lại chậm 0.2s để cú NHẢ chuột ảo cuối cùng
--                      (gửi lúc STOP, xử lý ở khung hình sau) vẫn đi xuyên xuống game, không bị kẹt chuột.
local function setTargetSolid(solid)
    if not solid then
        dragging = false -- huỷ thao tác kéo đang dở (nếu có)
        targetBtn.Active = false
        return
    end
    task.delay(0.2, function()
        if not (clicking or holding) then -- lỡ bấm START lại trong 0.2s thì giữ nguyên xuyên thấu
            targetBtn.Active = true
        end
    end)
end

-- Đọc ô Hold (s); nhập sai/để trống thì giữ lại giá trị trước đó
local function readHoldDuration()
    local n = tonumber(holdBox.Text)
    if n and n == n and n >= 1 and n < math.huge then
        holdSeconds = math.floor(n)
    end
    holdBox.Text = tostring(holdSeconds)
    return holdSeconds
end

holdBox.FocusLost:Connect(function()
    readHoldDuration()
end)

-- [MỚI] Nhả chuột tại đúng vị trí đã nhấn (không đổi cờ holding)
local function mouseUp()
    if holdPos then
        local p = holdPos
        holdPos = nil
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 1)
        end)
    end
end

local function releaseHold()
    holding = false
    mouseUp()
end

-- [MỚI] Lấy HumanoidRootPart của nhân vật đang sống (nil nếu đang chết / chưa respawn)
local function getHRP()
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then
        return hrp
    end
    return nil
end

-- [MỚI] Ghim camera nhìn thẳng xuống, bám theo nhân vật mỗi khung hình
local camLocked = false
local function lockCamera()
    if camLocked then return end
    camLocked = true
    local camera = workspace.CurrentCamera
    camera.CameraType = Enum.CameraType.Scriptable
    pcall(function() RunService:UnbindFromRenderStep("Sp1ngTopDownCam") end)
    RunService:BindToRenderStep("Sp1ngTopDownCam", Enum.RenderPriority.Camera.Value + 1, function()
        local hrp = getHRP()
        if hrp then
            -- xoay -90 độ quanh trục X = nhìn thẳng xuống (+X bên phải màn hình, -Z lên trên)
            camera.CFrame = CFrame.new(hrp.Position + Vector3.new(0, CAM_HEIGHT, 0)) * CFrame.Angles(-math.pi / 2, 0, 0)
        end
    end)
end

local function unlockCamera()
    if not camLocked then return end
    camLocked = false
    pcall(function() RunService:UnbindFromRenderStep("Sp1ngTopDownCam") end)
    local camera = workspace.CurrentCamera
    camera.CameraType = Enum.CameraType.Custom
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then camera.CameraSubject = hum end
end

-- [MỚI] Dừng tất cả (click + hold) và trả UI về trạng thái chờ
local function stopAll()
    clicking = false
    if holding then
        releaseHold()
    end
    holdSession = holdSession + 1
    unlockCamera() -- [MỚI] trả camera về bình thường
    setTargetSolid(true) -- [FIX] dừng rồi thì vòng tròn kéo thả lại được
    startBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 90)
    statusLabel.Text = "IDLE"
end

-- [MỚI] Bắt đầu giữ chuột: nhấn xuống 1 lần tại 🎯 rồi giữ đến khi hết giờ hoặc bấm STOP
local function startHold()
    local duration = readHoldDuration()
    holding = true -- đặt trước khi nhấn để logic kéo thả ở trên bỏ qua cú nhấn ảo này
    holdSession = holdSession + 1
    local session = holdSession

    holdPos = getTargetPos()
    local p = holdPos
    pcall(function()
        VirtualInputManager:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 1)
    end)

    task.spawn(function()
        local endTime = os.time() + duration
        while holding and session == holdSession do
            local remaining = endTime - os.time()
            if remaining <= 0 then
                break
            end
            statusLabel.Text = "HOLD " .. formatTime(remaining)
            task.wait(0.5)
        end
        if holding and session == holdSession then
            stopAll() -- hết giờ -> tự nhả
        end
    end)
end

-- [MỚI] Vào minigame Mining (đầu mỗi vòng)
local function enterMining()
    local ok, err = pcall(function()
        local Event = game:GetService("ReplicatedStorage").Remotes.Minigames.Mining
        Event:InvokeServer()
    end)
    if not ok then warn("[GRID] Mining:InvokeServer lỗi: " .. tostring(err)) end
end

-- [MỚI] Rời minigame Mining (sau điểm cuối cùng)
local function leaveMining()
    local ok, err = pcall(function()
        local Event = game:GetService("ReplicatedStorage").Services.Minigame.MiningGameNetwork.LeaveMining
        Event:FireServer()
    end)
    if not ok then warn("[GRID] LeaveMining:FireServer lỗi: " .. tostring(err)) end
end

-- [MỚI] Chế độ GRID (lặp vô hạn đến khi bấm STOP):
--   Mining:InvokeServer -> chờ 3s -> với mỗi điểm: TP -> ghim camera nhìn xuống -> ấn giữ -> Y chạm Y_LOW/Y_HIGH thì sang điểm kế
--   -> xong điểm cuối: LeaveMining:FireServer -> chờ 25 phút -> vòng mới từ điểm 1
local function startGrid()
    local idx = math.floor(tonumber(idxBox.Text) or 1)
    idx = math.clamp(idx, 1, #GRID_POINTS)
    idxBox.Text = tostring(idx)

    holding = true -- khoá kéo 🎯 trong lúc chạy (bấm STOP rồi mới kéo được)
    holdSession = holdSession + 1
    local session = holdSession
    local function alive() return holding and session == holdSession end

    task.spawn(function()
      while alive() do
        -- [MỚI] 1. vào minigame rồi chờ ENTER_DELAY giây
        statusLabel.Text = "ENTER MINING"
        enterMining()
        local t0 = os.clock()
        while alive() and os.clock() - t0 < ENTER_DELAY do
            task.wait(0.1)
        end
        if not alive() then break end

        -- 2. chạy lần lượt các điểm trong bảng
        while alive() and idx <= #GRID_POINTS do
            -- chờ nhân vật sống (lỡ chết thì đợi respawn rồi TP lại đúng điểm đang làm)
            local hrp = getHRP()
            while alive() and not hrp do
                statusLabel.Text = "WAIT RESPAWN"
                task.wait(0.3)
                hrp = getHRP()
            end
            if not alive() then break end

            -- 2a. nhả chuột (nếu đang giữ) rồi TP tới điểm: x, z theo bảng, y = TP_Y
            mouseUp()
            local pt = GRID_POINTS[idx]
            hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
            hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            hrp.CFrame = CFrame.new(pt[1], TP_Y, pt[2])
            idxBox.Text = tostring(idx)

            -- 2b. ghim camera nhìn thẳng xuống
            lockCamera()
            task.wait(SETTLE_TIME)
            if not alive() then break end

            -- 2c. ấn giữ tại 🎯
            holdPos = getTargetPos()
            local p = holdPos
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 1)
            end)

            -- 2d. giữ cho đến khi Y chạm Y_LOW hoặc Y_HIGH
            local reached = false
            while alive() do
                local h = getHRP()
                if not h then break end -- chết -> vòng ngoài sẽ TP lại điểm này
                local y = h.Position.Y
                statusLabel.Text = string.format("%d/%d Y%d", idx, #GRID_POINTS, math.floor(y))
                if y <= Y_LOW or y >= Y_HIGH then
                    reached = true
                    break
                end
                task.wait(0.1)
            end
            if reached then
                idx = idx + 1
            end
        end
        if not alive() then break end

        -- [MỚI] 3. xong điểm cuối: nhả chuột, trả camera, rời minigame
        mouseUp()
        unlockCamera()
        leaveMining()
        idx = 1
        idxBox.Text = "1"

        -- 4. chờ LOOP_WAIT giây (25 phút) rồi lặp lại từ đầu
        local endTime = os.time() + LOOP_WAIT
        while alive() do
            local remaining = endTime - os.time()
            if remaining <= 0 then break end
            statusLabel.Text = "WAIT " .. formatTime(remaining)
            task.wait(0.5)
        end
      end
    end)
end

-- Logique d'autoclick puissant
startBtn.MouseButton1Click:Connect(function()
    if clicking or holding then return end
    setTargetSolid(false) -- [FIX] click ảo rơi đúng tâm vòng tròn => cho vòng tròn xuyên thấu để game nhận được click
    startBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 45)
    if mode == "GRID" then
        startGrid()
    elseif mode == "HOLD" then
        startHold()
    else
        clicking = true
        statusLabel.Text = "CLICKING"
    end
end)

stopBtn.MouseButton1Click:Connect(function()
    stopAll()
end)

-- [ĐỔI] Đổi chế độ GRID -> HOLD -> CLICK -> GRID (không đổi được khi đang chạy)
modeBtn.MouseButton1Click:Connect(function()
    if clicking or holding then return end
    if mode == "GRID" then
        mode = "HOLD"
        modeBtn.TextColor3 = Color3.fromRGB(0, 255, 120)
    elseif mode == "HOLD" then
        mode = "CLICK"
        modeBtn.TextColor3 = Color3.fromRGB(255, 190, 60)
    else
        mode = "GRID"
        modeBtn.TextColor3 = Color3.fromRGB(80, 200, 255)
    end
    modeBtn.Text = "MODE: " .. mode
    holdLabel.Visible = (mode == "HOLD")
    holdBox.Visible = (mode == "HOLD")
    idxLabel.Visible = (mode == "GRID")
    idxBox.Visible = (mode == "GRID")
end)

RunService.RenderStepped:Connect(function()
    if clicking then
        local absPos = getTargetPos()
        pcall(function()
            VirtualInputManager:SendMouseButtonEvent(absPos.X, absPos.Y, 0, true, game, 1)
            task.wait()
            VirtualInputManager:SendMouseButtonEvent(absPos.X, absPos.Y, 0, false, game, 1)
        end)
    end
end)

-- [MỚI] Nếu GUI bị xoá khi đang giữ thì nhả chuột luôn, tránh bị kẹt nút
decalGui.Destroying:Connect(function()
    clicking = false
    if holding then
        releaseHold()
    end
    holdSession = holdSession + 1
    unlockCamera() -- [MỚI] GUI bị xoá thì trả camera lại bình thường
end)
