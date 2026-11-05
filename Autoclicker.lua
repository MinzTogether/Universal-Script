if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HOLD_DEFAULT = 1200
local TP_Y = 2514
local Y_LOW = 1674
local Y_HIGH = 3354
local CAM_HEIGHT = 30
local SETTLE_TIME = 0.5
local ENTER_DELAY = 3
local LOOP_WAIT = 25 * 60
local TARGET_SIZE = 80
local CLICK_OFFSET_X = 37
local CLICK_OFFSET_Y = 58
local clickOffset = Vector2.new(CLICK_OFFSET_X, CLICK_OFFSET_Y)

local GRID_X0, GRID_Z0, GRID_STEP, GRID_N = 1520, -155, 4, 13
local GRID_POINTS = {}
for j = 0, GRID_N - 1 do
    for i = 0, GRID_N - 1 do
        table.insert(GRID_POINTS, { GRID_X0 + i * GRID_STEP, GRID_Z0 + j * GRID_STEP })
    end
end
local POINT_COUNT = #GRID_POINTS

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
        local c3 = B64_LOOKUP[data:sub(i + 2, i + 2)]
        local c4 = B64_LOOKUP[data:sub(i + 3, i + 3)]
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
    warn("[Autoclicker] Không tải được ảnh mục tiêu, dùng vòng vẽ bằng code: " .. tostring(asset))
    return nil
end

local THEME = {
    panelTop = Color3.fromRGB(27, 32, 46),
    panelBottom = Color3.fromRGB(16, 19, 28),
    surface = Color3.fromRGB(22, 26, 38),
    field = Color3.fromRGB(35, 41, 58),
    line = Color3.fromRGB(55, 63, 87),
    text = Color3.fromRGB(236, 240, 248),
    soft = Color3.fromRGB(190, 199, 217),
    dim = Color3.fromRGB(139, 149, 172),
    faint = Color3.fromRGB(96, 106, 130),
    ink = Color3.fromRGB(14, 17, 25),
    go = Color3.fromRGB(52, 211, 153),
    stop = Color3.fromRGB(244, 96, 108),
    warn = Color3.fromRGB(255, 188, 72),
    ring = Color3.fromRGB(230, 57, 70),
    mapDone = Color3.fromRGB(72, 146, 196),
}

local MODE_ORDER = { "GRID", "HOLD", "CLICK" }
local MODE_INDEX = { GRID = 1, HOLD = 2, CLICK = 3 }
local MODE_NAMES = { GRID = "Grid", HOLD = "Hold", CLICK = "Click" }
local MODE_COLORS = {
    GRID = Color3.fromRGB(96, 190, 255),
    HOLD = Color3.fromRGB(184, 148, 255),
    CLICK = Color3.fromRGB(255, 188, 72),
}

local PANEL_W, PANEL_H = 324, 224
local MINI_W, MINI_H = 240, 44
local HEADER_H = 44
local PAGE_Y, PAGE_H = 44, 122
local PAD = 14
local MAP_SIZE = 98

local mode = "GRID"
local clicking = false
local holding = false
local holdPos = nil
local holdSession = 0
local holdSeconds = HOLD_DEFAULT
local gridIndex = 1
local clickCount = 0
local minimized = false
local setupOpen = false
local camLocked = false
local uiScale = 1
local dockX, dockY = 12, 76
local targetX, targetY = 0, 0
local activeToast = nil
local pulsing = false

local connections = {}
local ui = {}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function create(className, props, parent)
    local instance = Instance.new(className)
    for key, value in pairs(props) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

local function addCorner(parent, radius)
    return create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function addPill(parent)
    return create("UICorner", { CornerRadius = UDim.new(1, 0) }, parent)
end

local function addStroke(parent, color, thickness)
    return create("UIStroke", {
        Color = color,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, parent)
end

local function makeLabel(parent, props)
    local merged = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium,
        TextColor3 = THEME.text,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for key, value in pairs(props) do
        merged[key] = value
    end
    return create("TextLabel", merged, parent)
end

local function makeButton(parent, props)
    local merged = {
        AutoButtonColor = false,
        BorderSizePixel = 0,
        BackgroundColor3 = THEME.field,
        Font = Enum.Font.GothamBold,
        TextColor3 = THEME.text,
        TextSize = 13,
        Text = "",
    }
    for key, value in pairs(props) do
        merged[key] = value
    end
    return create("TextButton", merged, parent)
end

local function makeBox(parent, props)
    local box = create("TextBox", {
        Name = props.Name,
        Position = props.Position,
        Size = props.Size,
        BackgroundColor3 = THEME.field,
        BorderSizePixel = 0,
        TextColor3 = THEME.text,
        PlaceholderColor3 = THEME.faint,
        PlaceholderText = props.Placeholder or "",
        Font = Enum.Font.RobotoMono,
        TextSize = 13,
        ClearTextOnFocus = true,
        Text = props.Text or "",
        TextXAlignment = Enum.TextXAlignment.Center,
    }, parent)
    addCorner(box, 8)
    local boxStroke = addStroke(box, THEME.line, 1)
    connect(box.Focused, function()
        boxStroke.Color = MODE_COLORS[mode]
    end)
    connect(box.FocusLost, function()
        boxStroke.Color = THEME.line
    end)
    return box
end

local function iconBar(parent, width, height, rotation, color)
    local bar = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(width, height),
        Rotation = rotation,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, parent)
    addCorner(bar, 1)
    return bar
end

local function iconSquare(parent, size, color)
    local square = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, parent)
    addCorner(square, 2)
    addStroke(square, color, 2)
    return square
end

local function addPressFeedback(button, radius)
    local shade = create("Frame", {
        Name = "Shade",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, button)
    addCorner(shade, radius)
    connect(button.InputBegan, function(input)
        local inputType = input.UserInputType
        if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
            shade.BackgroundTransparency = 0.8
            local changed
            changed = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    shade.BackgroundTransparency = 1
                    if changed then
                        changed:Disconnect()
                    end
                end
            end)
        end
    end)
end

local function makeDraggable(handles, getOrigin, onMove, canDrag)
    local dragging = false
    local dragInput = nil
    local dragStart = nil
    local origin = nil

    for _, handle in ipairs(handles) do
        connect(handle.InputBegan, function(input)
            if canDrag and not canDrag() then
                return
            end
            local inputType = input.UserInputType
            if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch then
                dragging = true
                dragInput = input
                dragStart = input.Position
                origin = getOrigin()
                local changed
                changed = input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        if dragInput == input then
                            dragging = false
                            dragInput = nil
                        end
                        if changed then
                            changed:Disconnect()
                        end
                    end
                end)
            end
        end)
    end

    connect(UserInputService.InputChanged, function(input)
        if not dragging then
            return
        end
        local inputType = input.UserInputType
        if inputType == Enum.UserInputType.MouseMovement or (inputType == Enum.UserInputType.Touch and input == dragInput) then
            local delta = input.Position - dragStart
            onMove(origin, delta)
        end
    end)

    return function()
        dragging = false
        dragInput = nil
    end
end

local function formatTime(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
end

local function isRunning()
    return clicking or holding
end

local oldGui = playerGui:FindFirstChild("Sp1ngAutoClicker")
if oldGui then
    oldGui:Destroy()
end

ui.gui = Instance.new("ScreenGui")
ui.gui.Name = "Sp1ngAutoClicker"
ui.gui.ResetOnSpawn = false
ui.gui.DisplayOrder = 10000
ui.gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ui.gui.IgnoreGuiInset = true
pcall(function()
    ui.gui.ScreenInsets = Enum.ScreenInsets.None
end)
ui.gui.Parent = playerGui

local function screenSize()
    local size = ui.gui.AbsoluteSize
    if size.X > 0 and size.Y > 0 then
        return size
    end
    local camera = workspace.CurrentCamera
    if camera then
        return camera.ViewportSize
    end
    return Vector2.new(1280, 720)
end

local function clampToScreen(x, y, width, height)
    local screen = screenSize()
    local maxX = math.max(0, screen.X - width)
    local maxY = math.max(0, screen.Y - height)
    return math.floor(math.clamp(x, 0, maxX) + 0.5), math.floor(math.clamp(y, 0, maxY) + 0.5)
end

local function buildTarget()
    local screen = screenSize()
    targetX = math.floor(screen.X / 2 - TARGET_SIZE / 2)
    targetY = math.floor(screen.Y * 0.4)
    local image = loadTargetImage()
    local target
    if image then
        target = create("ImageLabel", {
            Name = "Target",
            Image = image,
            ScaleType = Enum.ScaleType.Stretch,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Active = true,
            Size = UDim2.fromOffset(TARGET_SIZE, TARGET_SIZE),
            Position = UDim2.fromOffset(targetX, targetY),
        }, ui.gui)
    else
        target = create("Frame", {
            Name = "Target",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Active = true,
            Size = UDim2.fromOffset(TARGET_SIZE, TARGET_SIZE),
            Position = UDim2.fromOffset(targetX, targetY),
        }, ui.gui)
        local ring = create("Frame", {
            Name = "Ring",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, -6, 1, -6),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        }, target)
        addPill(ring)
        addStroke(ring, THEME.ring, 2)
        create("Frame", {
            Name = "LineH",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(1, -10, 0, 1),
            BackgroundColor3 = THEME.text,
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
        }, target)
        create("Frame", {
            Name = "LineV",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.new(0, 1, 1, -10),
            BackgroundColor3 = THEME.text,
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
        }, target)
    end
    addPill(target)
    ui.targetStroke = addStroke(target, MODE_COLORS.GRID, 2)
    ui.target = target
end

local function buildPanel()
    local full = create("Frame", {
        Name = "Panel",
        Size = UDim2.fromOffset(PANEL_W, PANEL_H),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Active = true,
    }, ui.gui)
    addCorner(full, 14)
    addStroke(full, THEME.line, 1)
    create("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(THEME.panelTop, THEME.panelBottom),
    }, full)
    ui.fullScale = create("UIScale", { Scale = 1 }, full)
    ui.full = full

    local header = create("Frame", {
        Name = "Header",
        Size = UDim2.fromOffset(PANEL_W, HEADER_H),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, full)

    ui.statusDot = create("Frame", {
        Name = "Dot",
        Position = UDim2.fromOffset(PAD, 18),
        Size = UDim2.fromOffset(8, 8),
        BackgroundColor3 = THEME.dim,
        BorderSizePixel = 0,
    }, header)
    addPill(ui.statusDot)

    makeLabel(header, {
        Name = "Title",
        Position = UDim2.fromOffset(PAD + 18, 6),
        Size = UDim2.fromOffset(130, 18),
        Text = "Autoclicker",
        Font = Enum.Font.GothamBold,
        TextSize = 15,
    })
    makeLabel(header, {
        Name = "Credit",
        Position = UDim2.fromOffset(PAD + 18, 24),
        Size = UDim2.fromOffset(130, 13),
        Text = "by MinzTogether",
        TextSize = 11,
        TextColor3 = THEME.dim,
    })

    ui.dragZone = create("Frame", {
        Name = "DragZone",
        Size = UDim2.fromOffset(190, HEADER_H),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Active = true,
    }, header)

    ui.setupBtn = makeButton(header, {
        Name = "Setup",
        Position = UDim2.fromOffset(196, 9),
        Size = UDim2.fromOffset(52, 26),
        Text = "Setup",
        Font = Enum.Font.GothamMedium,
        TextSize = 12,
        TextColor3 = THEME.soft,
    })
    addPill(ui.setupBtn)
    ui.setupStroke = addStroke(ui.setupBtn, THEME.line, 1)
    addPressFeedback(ui.setupBtn, 13)

    ui.minBtn = makeButton(header, {
        Name = "Minimize",
        Position = UDim2.fromOffset(254, 9),
        Size = UDim2.fromOffset(26, 26),
    })
    addPill(ui.minBtn)
    iconBar(ui.minBtn, 10, 2, 0, THEME.soft)
    addPressFeedback(ui.minBtn, 13)

    ui.closeBtn = makeButton(header, {
        Name = "Close",
        Position = UDim2.fromOffset(286, 9),
        Size = UDim2.fromOffset(26, 26),
    })
    addPill(ui.closeBtn)
    iconBar(ui.closeBtn, 12, 2, 45, THEME.soft)
    iconBar(ui.closeBtn, 12, 2, -45, THEME.soft)
    addPressFeedback(ui.closeBtn, 13)

    local track = create("Frame", {
        Name = "Progress",
        Position = UDim2.fromOffset(0, HEADER_H - 3),
        Size = UDim2.fromOffset(PANEL_W, 3),
        BackgroundColor3 = THEME.line,
        BorderSizePixel = 0,
    }, full)
    ui.fill = create("Frame", {
        Name = "Fill",
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = THEME.dim,
        BorderSizePixel = 0,
    }, track)

    ui.runPage = create("Frame", {
        Name = "RunPage",
        Position = UDim2.fromOffset(0, PAGE_Y),
        Size = UDim2.fromOffset(PANEL_W, PAGE_H),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, full)

    ui.modePill = makeLabel(ui.runPage, {
        Name = "Mode",
        Position = UDim2.fromOffset(PAD, 14),
        Size = UDim2.fromOffset(88, 20),
        BackgroundTransparency = 0,
        BackgroundColor3 = THEME.field,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = "Grid mode",
    })
    addPill(ui.modePill)
    ui.modeStroke = addStroke(ui.modePill, MODE_COLORS.GRID, 1)

    ui.stateLabel = makeLabel(ui.runPage, {
        Name = "State",
        Position = UDim2.fromOffset(PAD, 40),
        Size = UDim2.fromOffset(188, 26),
        Font = Enum.Font.GothamBold,
        TextSize = 20,
        Text = "Idle",
    })
    ui.detailLabel = makeLabel(ui.runPage, {
        Name = "Detail",
        Position = UDim2.fromOffset(PAD, 68),
        Size = UDim2.fromOffset(188, 16),
        TextColor3 = THEME.soft,
        Text = "",
    })
    ui.hintLabel = makeLabel(ui.runPage, {
        Name = "Hint",
        Position = UDim2.fromOffset(PAD, 94),
        Size = UDim2.fromOffset(188, 16),
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = THEME.dim,
        Text = "",
    })

    ui.mapFrame = create("Frame", {
        Name = "Map",
        Position = UDim2.fromOffset(PANEL_W - PAD - MAP_SIZE, 12),
        Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE),
        BackgroundColor3 = THEME.surface,
        BorderSizePixel = 0,
    }, ui.runPage)
    addCorner(ui.mapFrame, 8)
    addStroke(ui.mapFrame, THEME.line, 1)

    ui.cellHolder = create("Frame", {
        Name = "Cells",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, ui.mapFrame)
    ui.cells = {}
    for i = 1, POINT_COUNT do
        local col = (i - 1) % GRID_N
        local row = math.floor((i - 1) / GRID_N)
        ui.cells[i] = create("Frame", {
            Name = "Cell" .. i,
            Position = UDim2.fromOffset(4 + col * 7, 4 + row * 7),
            Size = UDim2.fromOffset(6, 6),
            BackgroundColor3 = THEME.line,
            BorderSizePixel = 0,
        }, ui.cellHolder)
    end

    ui.readoutValue = makeLabel(ui.mapFrame, {
        Name = "ReadoutValue",
        Position = UDim2.fromOffset(0, 28),
        Size = UDim2.fromOffset(MAP_SIZE, 26),
        Font = Enum.Font.RobotoMono,
        TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = "",
        Visible = false,
    })
    ui.readoutCaption = makeLabel(ui.mapFrame, {
        Name = "ReadoutCaption",
        Position = UDim2.fromOffset(0, 56),
        Size = UDim2.fromOffset(MAP_SIZE, 14),
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = THEME.dim,
        TextXAlignment = Enum.TextXAlignment.Center,
        Text = "",
        Visible = false,
    })

    ui.setupPage = create("Frame", {
        Name = "SetupPage",
        Position = UDim2.fromOffset(0, PAGE_Y),
        Size = UDim2.fromOffset(PANEL_W, PAGE_H),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
    }, full)

    local seg = create("Frame", {
        Name = "Modes",
        Position = UDim2.fromOffset(PAD, 10),
        Size = UDim2.fromOffset(PANEL_W - PAD * 2, 34),
        BackgroundColor3 = THEME.field,
        BorderSizePixel = 0,
    }, ui.setupPage)
    addCorner(seg, 10)
    addStroke(seg, THEME.line, 1)
    ui.indicator = create("Frame", {
        Name = "Indicator",
        Position = UDim2.new(0, 3, 0, 3),
        Size = UDim2.new(1 / 3, -6, 1, -6),
        BackgroundColor3 = MODE_COLORS.GRID,
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
    }, seg)
    addCorner(ui.indicator, 8)
    ui.indicatorStroke = addStroke(ui.indicator, MODE_COLORS.GRID, 1)
    ui.segButtons = {}
    for index, name in ipairs(MODE_ORDER) do
        ui.segButtons[name] = makeButton(seg, {
            Name = name,
            Position = UDim2.new((index - 1) / 3, 0, 0, 0),
            Size = UDim2.new(1 / 3, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = MODE_NAMES[name],
            TextColor3 = THEME.dim,
        })
    end

    local function makeRow(name, y)
        return create("Frame", {
            Name = name,
            Position = UDim2.fromOffset(0, y),
            Size = UDim2.fromOffset(PANEL_W, 28),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        }, ui.setupPage)
    end

    ui.gridRow = makeRow("GridRow", 54)
    makeLabel(ui.gridRow, {
        Position = UDim2.fromOffset(PAD, 0),
        Size = UDim2.fromOffset(110, 28),
        Text = "Start point",
        TextColor3 = THEME.soft,
    })
    ui.idxBox = makeBox(ui.gridRow, {
        Name = "StartPoint",
        Position = UDim2.fromOffset(130, 0),
        Size = UDim2.fromOffset(64, 28),
        Text = "1",
        Placeholder = "1",
    })
    makeLabel(ui.gridRow, {
        Position = UDim2.fromOffset(204, 0),
        Size = UDim2.fromOffset(100, 28),
        Text = "of " .. POINT_COUNT,
        TextColor3 = THEME.dim,
    })

    ui.holdRow = makeRow("HoldRow", 54)
    ui.holdRow.Visible = false
    makeLabel(ui.holdRow, {
        Position = UDim2.fromOffset(PAD, 0),
        Size = UDim2.fromOffset(110, 28),
        Text = "Hold for",
        TextColor3 = THEME.soft,
    })
    ui.holdBox = makeBox(ui.holdRow, {
        Name = "HoldSeconds",
        Position = UDim2.fromOffset(130, 0),
        Size = UDim2.fromOffset(64, 28),
        Text = tostring(HOLD_DEFAULT),
        Placeholder = tostring(HOLD_DEFAULT),
    })
    makeLabel(ui.holdRow, {
        Position = UDim2.fromOffset(204, 0),
        Size = UDim2.fromOffset(100, 28),
        Text = "seconds",
        TextColor3 = THEME.dim,
    })

    ui.clickRow = makeRow("ClickRow", 54)
    ui.clickRow.Visible = false
    makeLabel(ui.clickRow, {
        Position = UDim2.fromOffset(PAD, 0),
        Size = UDim2.fromOffset(PANEL_W - PAD * 2, 28),
        Text = "Clicks once per frame at the ring",
        TextColor3 = THEME.soft,
    })

    local offsetRow = makeRow("OffsetRow", 90)
    makeLabel(offsetRow, {
        Position = UDim2.fromOffset(PAD, 0),
        Size = UDim2.fromOffset(46, 28),
        Text = "Offset",
        TextColor3 = THEME.soft,
    })

    local function makeStepper(x, axis, initial)
        makeLabel(offsetRow, {
            Position = UDim2.fromOffset(x, 0),
            Size = UDim2.fromOffset(12, 28),
            Text = axis,
            Font = Enum.Font.GothamBold,
            TextColor3 = THEME.dim,
        })
        local minus = makeButton(offsetRow, {
            Name = axis .. "Minus",
            Position = UDim2.fromOffset(x + 14, 0),
            Size = UDim2.fromOffset(26, 28),
        })
        addCorner(minus, 8)
        iconBar(minus, 10, 2, 0, THEME.soft)
        addPressFeedback(minus, 8)
        local box = makeBox(offsetRow, {
            Name = axis .. "Offset",
            Position = UDim2.fromOffset(x + 42, 0),
            Size = UDim2.fromOffset(42, 28),
            Text = tostring(initial),
            Placeholder = "0",
        })
        local plus = makeButton(offsetRow, {
            Name = axis .. "Plus",
            Position = UDim2.fromOffset(x + 86, 0),
            Size = UDim2.fromOffset(26, 28),
        })
        addCorner(plus, 8)
        iconBar(plus, 10, 2, 0, THEME.soft)
        iconBar(plus, 2, 10, 0, THEME.soft)
        addPressFeedback(plus, 8)
        return box, minus, plus
    end

    ui.offXBox, ui.offXMinus, ui.offXPlus = makeStepper(62, "X", CLICK_OFFSET_X)
    ui.offYBox, ui.offYMinus, ui.offYPlus = makeStepper(184, "Y", CLICK_OFFSET_Y)

    ui.startBtn = makeButton(full, {
        Name = "Start",
        Position = UDim2.fromOffset(PAD, 174),
        Size = UDim2.fromOffset(143, 38),
        Text = "Start",
        TextSize = 14,
    })
    addCorner(ui.startBtn, 11)
    addPressFeedback(ui.startBtn, 11)

    ui.stopBtn = makeButton(full, {
        Name = "Stop",
        Position = UDim2.fromOffset(PAD + 143 + 10, 174),
        Size = UDim2.fromOffset(143, 38),
        Text = "Stop",
        TextSize = 14,
    })
    addCorner(ui.stopBtn, 11)
    addPressFeedback(ui.stopBtn, 11)
end

local function buildMini()
    local mini = create("Frame", {
        Name = "Mini",
        Size = UDim2.fromOffset(MINI_W, MINI_H),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Active = true,
        Visible = false,
    }, ui.gui)
    addCorner(mini, 12)
    addStroke(mini, THEME.line, 1)
    create("UIGradient", {
        Rotation = 90,
        Color = ColorSequence.new(THEME.panelTop, THEME.panelBottom),
    }, mini)
    ui.miniScale = create("UIScale", { Scale = 1 }, mini)
    ui.mini = mini

    ui.miniDot = create("Frame", {
        Name = "Dot",
        Position = UDim2.fromOffset(PAD, 18),
        Size = UDim2.fromOffset(8, 8),
        BackgroundColor3 = THEME.dim,
        BorderSizePixel = 0,
    }, mini)
    addPill(ui.miniDot)

    ui.miniLabel = makeLabel(mini, {
        Name = "State",
        Position = UDim2.fromOffset(PAD + 16, 0),
        Size = UDim2.fromOffset(98, MINI_H - 3),
        Text = "Idle",
    })

    ui.miniDrag = create("Frame", {
        Name = "DragZone",
        Size = UDim2.fromOffset(128, MINI_H),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Active = true,
    }, mini)

    ui.miniToggle = makeButton(mini, {
        Name = "Toggle",
        Position = UDim2.fromOffset(132, 9),
        Size = UDim2.fromOffset(58, 26),
        Text = "Start",
        TextSize = 12,
    })
    addPill(ui.miniToggle)
    addPressFeedback(ui.miniToggle, 13)

    ui.miniExpand = makeButton(mini, {
        Name = "Expand",
        Position = UDim2.fromOffset(MINI_W - 12 - 26, 9),
        Size = UDim2.fromOffset(26, 26),
    })
    addPill(ui.miniExpand)
    iconSquare(ui.miniExpand, 10, THEME.soft)
    addPressFeedback(ui.miniExpand, 13)

    local track = create("Frame", {
        Name = "Progress",
        Position = UDim2.fromOffset(14, MINI_H - 4),
        Size = UDim2.fromOffset(MINI_W - 28, 3),
        BackgroundColor3 = THEME.line,
        BorderSizePixel = 0,
    }, mini)
    ui.miniFill = create("Frame", {
        Name = "Fill",
        Size = UDim2.fromScale(0, 1),
        BackgroundColor3 = THEME.dim,
        BorderSizePixel = 0,
    }, track)
end

local function panelSize()
    if minimized then
        return Vector2.new(MINI_W * uiScale, MINI_H * uiScale)
    end
    return Vector2.new(PANEL_W * uiScale, PANEL_H * uiScale)
end

local function placePanel(x, y)
    dockX, dockY = x, y
    local position = UDim2.fromOffset(x, y)
    ui.full.Position = position
    ui.mini.Position = position
end

local function placeTarget(x, y)
    targetX, targetY = x, y
    ui.target.Position = UDim2.fromOffset(x, y)
end

local function applyScale()
    local screen = screenSize()
    uiScale = math.clamp(math.min(screen.X / 760, screen.Y / 440), 0.7, 1)
    ui.fullScale.Scale = uiScale
    ui.miniScale.Scale = uiScale
end

local function keepOnScreen()
    local size = panelSize()
    placePanel(clampToScreen(dockX, dockY, size.X, size.Y))
    placeTarget(clampToScreen(targetX, targetY, TARGET_SIZE, TARGET_SIZE))
end

local function notify(title, body, tone, duration)
    if activeToast then
        activeToast:Destroy()
        activeToast = nil
    end
    local toast = create("Frame", {
        Name = "Toast",
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, -72),
        Size = UDim2.fromOffset(276, 56),
        BackgroundColor3 = THEME.panelTop,
        BorderSizePixel = 0,
    }, ui.gui)
    addCorner(toast, 12)
    addStroke(toast, THEME.line, 1)
    local accent = create("Frame", {
        Name = "Accent",
        Position = UDim2.fromOffset(12, 14),
        Size = UDim2.fromOffset(4, 28),
        BackgroundColor3 = tone or THEME.go,
        BorderSizePixel = 0,
    }, toast)
    addPill(accent)
    makeLabel(toast, {
        Name = "Title",
        Position = UDim2.fromOffset(26, 9),
        Size = UDim2.fromOffset(240, 18),
        Text = title,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
    })
    makeLabel(toast, {
        Name = "Body",
        Position = UDim2.fromOffset(26, 28),
        Size = UDim2.fromOffset(240, 16),
        Text = body,
        TextColor3 = THEME.dim,
    })
    activeToast = toast
    TweenService:Create(toast, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0, 14),
    }):Play()
    task.delay(duration or 3.5, function()
        if activeToast ~= toast or not toast.Parent then
            return
        end
        activeToast = nil
        local tween = TweenService:Create(toast, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, 0, 0, -72),
        })
        tween.Completed:Connect(function()
            toast:Destroy()
        end)
        tween:Play()
    end)
end

local function setProgress(ratio, color)
    local size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
    ui.fill.Size = size
    ui.fill.BackgroundColor3 = color
    ui.miniFill.Size = size
    ui.miniFill.BackgroundColor3 = color
end

local function setStatus(state, detail, short, ratio, tone)
    ui.stateLabel.Text = state
    ui.detailLabel.Text = detail
    ui.miniLabel.Text = short
    ui.statusDot.BackgroundColor3 = tone
    ui.miniDot.BackgroundColor3 = tone
    setProgress(ratio, tone)
end

local cellStates = {}

local function renderMap(done, current)
    for i = 1, POINT_COUNT do
        local wanted = 0
        if i == current then
            wanted = 2
        elseif i <= done then
            wanted = 1
        end
        if cellStates[i] ~= wanted then
            cellStates[i] = wanted
            local cell = ui.cells[i]
            if wanted == 2 then
                cell.BackgroundColor3 = THEME.text
            elseif wanted == 1 then
                cell.BackgroundColor3 = THEME.mapDone
            else
                cell.BackgroundColor3 = THEME.line
            end
        end
    end
end

local function setReadout(value, caption)
    ui.readoutValue.Text = value
    ui.readoutCaption.Text = caption
end

local function styleAction(button, lit, color)
    if lit then
        button.BackgroundColor3 = color
        button.TextColor3 = THEME.ink
    else
        button.BackgroundColor3 = THEME.field
        button.TextColor3 = THEME.faint
    end
end

local function applyTargetLook()
    if isRunning() then
        ui.targetStroke.Color = THEME.go
    else
        ui.targetStroke.Color = MODE_COLORS[mode]
    end
end

local function setPulse(on)
    if on == pulsing then
        return
    end
    pulsing = on
    for _, tween in ipairs(ui.pulses) do
        if on then
            tween:Play()
        else
            tween:Cancel()
        end
    end
    if not on then
        ui.statusDot.BackgroundTransparency = 0
        ui.miniDot.BackgroundTransparency = 0
    end
end

local function refreshControls()
    local running = isRunning()
    styleAction(ui.startBtn, not running, THEME.go)
    styleAction(ui.stopBtn, running, THEME.stop)
    ui.miniToggle.Text = running and "Stop" or "Start"
    styleAction(ui.miniToggle, true, running and THEME.stop or THEME.go)
    for _, button in pairs(ui.segButtons) do
        button.TextTransparency = running and 0.55 or 0
    end
    ui.hintLabel.Text = running and "Stop to move the ring." or "Drag the ring to aim."
    applyTargetLook()
    setPulse(running)
end

local function refreshIdle()
    if isRunning() then
        return
    end
    local detail
    if mode == "GRID" then
        detail = string.format("Next: point %d of %d", gridIndex, POINT_COUNT)
        renderMap(gridIndex - 1, gridIndex)
    elseif mode == "HOLD" then
        detail = "Holds for " .. formatTime(holdSeconds)
        setReadout(formatTime(holdSeconds), "hold time")
    else
        detail = "Every frame at the ring"
        setReadout(tostring(clickCount), "clicks")
    end
    setStatus("Idle", detail, "Idle", 0, THEME.dim)
end

local function setPage(open)
    setupOpen = open
    local color = MODE_COLORS[mode]
    ui.runPage.Visible = not open
    ui.setupPage.Visible = open
    ui.setupBtn.Text = open and "Done" or "Setup"
    ui.setupBtn.TextColor3 = open and color or THEME.soft
    ui.setupStroke.Color = open and color or THEME.line
end

local function applyMode()
    local color = MODE_COLORS[mode]
    ui.modePill.Text = MODE_NAMES[mode] .. " mode"
    ui.modePill.TextColor3 = color
    ui.modeStroke.Color = color
    ui.indicator.BackgroundColor3 = color
    ui.indicatorStroke.Color = color
    for name, button in pairs(ui.segButtons) do
        button.TextColor3 = name == mode and color or THEME.dim
    end
    TweenService:Create(ui.indicator, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new((MODE_INDEX[mode] - 1) / 3, 3, 0, 3),
    }):Play()
    ui.gridRow.Visible = mode == "GRID"
    ui.holdRow.Visible = mode == "HOLD"
    ui.clickRow.Visible = mode == "CLICK"
    ui.cellHolder.Visible = mode == "GRID"
    ui.readoutValue.Visible = mode ~= "GRID"
    ui.readoutCaption.Visible = mode ~= "GRID"
    setPage(setupOpen)
    applyTargetLook()
    refreshIdle()
end

local function setMode(name)
    if isRunning() or name == mode then
        return
    end
    mode = name
    applyMode()
end

local function setMinimized(value)
    minimized = value
    ui.full.Visible = not value
    ui.mini.Visible = value
    keepOnScreen()
end

local function readGridIndex()
    local n = tonumber(ui.idxBox.Text)
    if n and n == n then
        gridIndex = math.clamp(math.floor(n), 1, POINT_COUNT)
    end
    ui.idxBox.Text = tostring(gridIndex)
    return gridIndex
end

local function setGridIndex(n)
    gridIndex = n
    ui.idxBox.Text = tostring(n)
end

local function readHoldDuration()
    local n = tonumber(ui.holdBox.Text)
    if n and n == n and n >= 1 and n < math.huge then
        holdSeconds = math.floor(n)
    end
    ui.holdBox.Text = tostring(holdSeconds)
    return holdSeconds
end

local function applyOffset()
    local x = tonumber(ui.offXBox.Text)
    local y = tonumber(ui.offYBox.Text)
    if not (x and x == x and math.abs(x) <= 500) then
        x = clickOffset.X
    end
    if not (y and y == y and math.abs(y) <= 500) then
        y = clickOffset.Y
    end
    clickOffset = Vector2.new(x, y)
    ui.offXBox.Text = tostring(x)
    ui.offYBox.Text = tostring(y)
end

local function nudgeOffset(axis, amount)
    applyOffset()
    local x, y = clickOffset.X, clickOffset.Y
    if axis == "X" then
        x = math.clamp(x + amount, -500, 500)
    else
        y = math.clamp(y + amount, -500, 500)
    end
    clickOffset = Vector2.new(x, y)
    ui.offXBox.Text = tostring(x)
    ui.offYBox.Text = tostring(y)
end

local function getTargetCenter()
    return ui.target.AbsolutePosition + (ui.target.AbsoluteSize / 2)
end

local function getTargetPos()
    return getTargetCenter() + clickOffset
end

local function setTargetSolid(solid)
    if not solid then
        ui.cancelTargetDrag()
        ui.target.Active = false
        ui.full.Active = false
        return
    end
    task.delay(0.2, function()
        if not isRunning() then
            ui.target.Active = true
            ui.full.Active = true
        end
    end)
end

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

local function getHRP()
    local char = player.Character
    if not char then
        return nil
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hrp and hum and hum.Health > 0 then
        return hrp
    end
    return nil
end

local function lockCamera()
    if camLocked then
        return
    end
    local camera = workspace.CurrentCamera
    if not camera then
        return
    end
    camLocked = true
    camera.CameraType = Enum.CameraType.Scriptable
    pcall(function()
        RunService:UnbindFromRenderStep("Sp1ngTopDownCam")
    end)
    RunService:BindToRenderStep("Sp1ngTopDownCam", Enum.RenderPriority.Camera.Value + 1, function()
        local hrp = getHRP()
        if hrp then
            camera.CFrame = CFrame.new(hrp.Position + Vector3.new(0, CAM_HEIGHT, 0)) * CFrame.Angles(-math.pi / 2, 0, 0)
        end
    end)
end

local function unlockCamera()
    if not camLocked then
        return
    end
    camLocked = false
    pcall(function()
        RunService:UnbindFromRenderStep("Sp1ngTopDownCam")
    end)
    local camera = workspace.CurrentCamera
    if camera then
        camera.CameraType = Enum.CameraType.Custom
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            camera.CameraSubject = hum
        end
    end
end

local function stopAll()
    clicking = false
    if holding then
        releaseHold()
    end
    holdSession = holdSession + 1
    unlockCamera()
    setTargetSolid(true)
    refreshControls()
    refreshIdle()
end

local function startHold()
    local duration = readHoldDuration()
    holding = true
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
            setStatus(
                "Holding",
                "Releases in " .. formatTime(remaining),
                "Holding " .. formatTime(remaining),
                1 - remaining / duration,
                MODE_COLORS.HOLD
            )
            setReadout(formatTime(remaining), "left")
            task.wait(0.5)
        end
        if holding and session == holdSession then
            stopAll()
            notify("Hold finished", "Mouse button released", THEME.go)
        end
    end)
end

local function enterMining()
    local ok, err = pcall(function()
        local Event = game:GetService("ReplicatedStorage").Remotes.Minigames.Mining
        Event:InvokeServer()
    end)
    if not ok then
        warn("[GRID] Mining:InvokeServer lỗi: " .. tostring(err))
        notify("Could not enter mining", "Open the console (F9) for details.", THEME.warn, 4)
    end
end

local function leaveMining()
    local ok, err = pcall(function()
        local Event = game:GetService("ReplicatedStorage").Services.Minigame.MiningGameNetwork.LeaveMining
        Event:FireServer()
    end)
    if not ok then
        warn("[GRID] LeaveMining:FireServer lỗi: " .. tostring(err))
        notify("Could not leave mining", "Open the console (F9) for details.", THEME.warn, 4)
    end
end

local function showMining(idx, y)
    local fraction
    if y < TP_Y then
        fraction = (TP_Y - y) / (TP_Y - Y_LOW)
    else
        fraction = (y - TP_Y) / (Y_HIGH - TP_Y)
    end
    fraction = math.clamp(fraction, 0, 1)
    setStatus(
        "Mining",
        string.format("Point %d of %d, Y %d", idx, POINT_COUNT, math.floor(y)),
        string.format("Mining %d/%d", idx, POINT_COUNT),
        (idx - 1 + fraction) / POINT_COUNT,
        MODE_COLORS.GRID
    )
end

local function startGrid()
    local idx = readGridIndex()

    holding = true
    holdSession = holdSession + 1
    local session = holdSession
    local function alive()
        return holding and session == holdSession
    end

    task.spawn(function()
        while alive() do
            setStatus("Entering", "Opening the mining minigame", "Entering", 0, THEME.warn)
            renderMap(idx - 1, idx)
            enterMining()
            local t0 = os.clock()
            while alive() and os.clock() - t0 < ENTER_DELAY do
                task.wait(0.1)
            end
            if not alive() then
                break
            end

            while alive() and idx <= POINT_COUNT do
                local hrp = getHRP()
                while alive() and not hrp do
                    setStatus(
                        "Respawn",
                        "Waiting for your character",
                        "Respawn",
                        (idx - 1) / POINT_COUNT,
                        THEME.warn
                    )
                    task.wait(0.3)
                    hrp = getHRP()
                end
                if not alive() then
                    break
                end

                mouseUp()
                local pt = GRID_POINTS[idx]
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
                hrp.CFrame = CFrame.new(pt[1], TP_Y, pt[2])
                setGridIndex(idx)
                renderMap(idx - 1, idx)
                showMining(idx, TP_Y)

                lockCamera()
                task.wait(SETTLE_TIME)
                if not alive() then
                    break
                end

                holdPos = getTargetPos()
                local p = holdPos
                pcall(function()
                    VirtualInputManager:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 1)
                end)

                local reached = false
                while alive() do
                    local h = getHRP()
                    if not h then
                        break
                    end
                    local y = h.Position.Y
                    showMining(idx, y)
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
            if not alive() then
                break
            end

            mouseUp()
            unlockCamera()
            leaveMining()
            idx = 1
            setGridIndex(1)
            renderMap(POINT_COUNT, 0)
            notify("Cycle complete", "Next run in " .. formatTime(LOOP_WAIT), THEME.go)

            local endTime = os.time() + LOOP_WAIT
            while alive() do
                local remaining = endTime - os.time()
                if remaining <= 0 then
                    break
                end
                setStatus(
                    "Cooldown",
                    "Next cycle in " .. formatTime(remaining),
                    "Cooldown " .. formatTime(remaining),
                    1 - remaining / LOOP_WAIT,
                    THEME.warn
                )
                task.wait(0.5)
            end
        end
    end)
end

local function startClicking()
    clicking = true
    clickCount = 0
    holdSession = holdSession + 1
    local session = holdSession
    setStatus("Clicking", "Every frame at the ring", "Clicking", 1, MODE_COLORS.CLICK)
    setReadout("0", "clicks")
    task.spawn(function()
        while clicking and session == holdSession do
            setReadout(tostring(clickCount), "clicks")
            task.wait(0.25)
        end
    end)
end

local function startRun()
    if isRunning() then
        return
    end
    setTargetSolid(false)
    setPage(false)
    if mode == "GRID" then
        startGrid()
    elseif mode == "HOLD" then
        startHold()
    else
        startClicking()
    end
    refreshControls()
end

local function bindEvents()
    connect(ui.startBtn.MouseButton1Click, startRun)
    connect(ui.stopBtn.MouseButton1Click, stopAll)
    connect(ui.miniToggle.MouseButton1Click, function()
        if isRunning() then
            stopAll()
        else
            startRun()
        end
    end)
    connect(ui.setupBtn.MouseButton1Click, function()
        setPage(not setupOpen)
    end)
    connect(ui.minBtn.MouseButton1Click, function()
        setMinimized(true)
    end)
    connect(ui.miniExpand.MouseButton1Click, function()
        setMinimized(false)
    end)
    connect(ui.closeBtn.MouseButton1Click, function()
        ui.gui:Destroy()
    end)

    for name, button in pairs(ui.segButtons) do
        connect(button.MouseButton1Click, function()
            setMode(name)
        end)
    end

    connect(ui.idxBox.FocusLost, function()
        readGridIndex()
        refreshIdle()
    end)
    connect(ui.holdBox.FocusLost, function()
        readHoldDuration()
        refreshIdle()
    end)
    connect(ui.offXBox.FocusLost, applyOffset)
    connect(ui.offYBox.FocusLost, applyOffset)
    connect(ui.offXMinus.MouseButton1Click, function()
        nudgeOffset("X", -1)
    end)
    connect(ui.offXPlus.MouseButton1Click, function()
        nudgeOffset("X", 1)
    end)
    connect(ui.offYMinus.MouseButton1Click, function()
        nudgeOffset("Y", -1)
    end)
    connect(ui.offYPlus.MouseButton1Click, function()
        nudgeOffset("Y", 1)
    end)

    ui.cancelTargetDrag = makeDraggable({ ui.target }, function()
        return Vector2.new(targetX, targetY)
    end, function(origin, delta)
        placeTarget(clampToScreen(origin.X + delta.X, origin.Y + delta.Y, TARGET_SIZE, TARGET_SIZE))
    end, function()
        return not isRunning()
    end)

    makeDraggable({ ui.dragZone, ui.miniDrag }, function()
        return Vector2.new(dockX, dockY)
    end, function(origin, delta)
        local size = panelSize()
        placePanel(clampToScreen(origin.X + delta.X, origin.Y + delta.Y, size.X, size.Y))
    end)

    connect(ui.gui:GetPropertyChangedSignal("AbsoluteSize"), function()
        applyScale()
        keepOnScreen()
    end)

    connect(RunService.RenderStepped, function()
        if clicking then
            local absPos = getTargetPos()
            clickCount = clickCount + 1
            pcall(function()
                VirtualInputManager:SendMouseButtonEvent(absPos.X, absPos.Y, 0, true, game, 1)
                task.wait()
                VirtualInputManager:SendMouseButtonEvent(absPos.X, absPos.Y, 0, false, game, 1)
            end)
        end
    end)

    ui.gui.Destroying:Connect(function()
        clicking = false
        if holding then
            releaseHold()
        end
        holdSession = holdSession + 1
        unlockCamera()
        setPulse(false)
        for _, connection in ipairs(connections) do
            connection:Disconnect()
        end
    end)
end

buildTarget()
buildPanel()
buildMini()

ui.pulses = {}
for _, dot in ipairs({ ui.statusDot, ui.miniDot }) do
    table.insert(ui.pulses, TweenService:Create(
        dot,
        TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        { BackgroundTransparency = 0.65 }
    ))
end

applyScale()
local initialSize = panelSize()
placePanel(clampToScreen(dockX, dockY, initialSize.X, initialSize.Y))
bindEvents()
applyMode()
refreshControls()
notify("Autoclicker", "made by MinzTogether", THEME.go, 4)
