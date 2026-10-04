--// ================= SERVICES =================
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players          = game:GetService("Players")
local CoreGui          = game:GetService("CoreGui")
local HttpService      = game:GetService("HttpService")
local RunService       = game:GetService("RunService")
local TeleportService  = game:GetService("TeleportService")
local Workspace        = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

--// ================= CLEANUP PREVIOUS INSTANCE =================
if CoreGui:FindFirstChild("ElyseraUI") then
    CoreGui.ElyseraUI:Destroy()
end
if CoreGui:FindFirstChild("ElyseraCover") then
    CoreGui.ElyseraCover:Destroy()
end

--// ================= THEME =================
local Theme = {
    Background     = Color3.fromRGB(29, 21, 52),    -- #1D1534 main background
    Panel          = Color3.fromRGB(33, 21, 58),    -- #21153A cards, buttons, dialogs
    PanelAlt       = Color3.fromRGB(37, 25, 66),    -- #251942 sidebar, tab / function panels
    Header         = Color3.fromRGB(49, 32, 75),    -- #31204B top bar, highlight tab
    Border         = Color3.fromRGB(84, 53, 128),   -- #543580 purple border
    AccentPink     = Color3.fromRGB(243, 99, 225),  -- #F363E1 primary accent
    AccentPurple   = Color3.fromRGB(175, 88, 249),  -- #AF58F9 neon purple
    Sakura         = Color3.fromRGB(255, 183, 213), -- #FFB7D5 selected tab text
    Text           = Color3.fromRGB(226, 190, 250), -- #E2BEFA primary text
    SubText        = Color3.fromRGB(191, 157, 238), -- #BF9DEE secondary text
    Danger         = Color3.fromRGB(247, 118, 142), -- #F7768E close / danger
    ToggleTrackOff = Color3.fromRGB(71, 48, 112),   -- #473070 switch track (off)
    ToggleKnobOn   = Color3.fromRGB(255, 255, 255), -- #FFFFFF switch knob (on)
}

--// ================= CONFIG =================
local UI_NAME             = "Elysera"
local UI_W, UI_H          = 650, 420
local MIN_UI_W, MIN_UI_H  = 420, 260
local TOGGLE_SIZE         = 50
local POPUP_TIME          = 0.25
local CLOSE_TIME          = 0.20
local TOPBAR_HEIGHT       = 40
local SAVE_FILE           = "Elysera_Settings.json"
local SAVE_DELAY          = 0.3

local MARGIN_EDGE         = 8
local MARGIN_GAP          = 10
local TAB_PANEL_WIDTH     = 150
local HIGHLIGHT_HEIGHT    = 56
local HIGHLIGHT_GAP       = 8

local CENTER        = UDim2.fromScale(0.5, 0.5)
local ANCHOR_CENTER = Vector2.new(0.5, 0.5)
local EASE_QUAD     = Enum.EasingStyle.Quad
local EASE_QUINT    = Enum.EasingStyle.Quint
local EASE_BACK     = Enum.EasingStyle.Back
local EASE_LINEAR   = Enum.EasingStyle.Linear
local DIR_IN        = Enum.EasingDirection.In
local DIR_OUT       = Enum.EasingDirection.Out

local uiLocked = false

--// ================= ROOT =================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ElyseraUI"
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 10
ScreenGui.Parent = CoreGui

--// ================= UTILITY =================
local Connections = {}
local function track(conn)
    Connections[#Connections + 1] = conn
    return conn
end

ScreenGui.Destroying:Connect(function()
    for _, c in ipairs(Connections) do c:Disconnect() end
end)

local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do inst[k] = v end
    inst.Parent = parent
    return inst
end

local function corner(inst, radius)
    return new("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, inst)
end

local function stroke(inst, color, thickness)
    return new("UIStroke", { Color = color or Theme.Border, Thickness = thickness or 1 }, inst)
end

local function padding(inst, left, right, top, bottom)
    return new("UIPadding", {
        PaddingLeft   = UDim.new(0, left or 0),
        PaddingRight  = UDim.new(0, right or 0),
        PaddingTop    = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
    }, inst)
end

local function list(inst, gap, props)
    props = props or {}
    props.SortOrder = Enum.SortOrder.LayoutOrder
    props.Padding = UDim.new(0, gap or 0)
    return new("UIListLayout", props, inst)
end

local function label(parent, props)
    props.BackgroundTransparency = 1
    props.Font = props.Font or Enum.Font.GothamBold
    return new("TextLabel", props, parent)
end

local function tween(inst, time, props, style, dir)
    local t = TweenService:Create(inst, TweenInfo.new(time, style or EASE_QUAD, dir or DIR_OUT), props)
    t:Play()
    return t
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

local function makeDraggable(handle, target, onEnd, onClick, threshold)
    threshold = threshold or 0
    local dragging, moved, dragStart, startPos

    handle.InputBegan:Connect(function(input)
        if uiLocked or not isPress(input) then return end
        dragging, moved = true, false
        dragStart, startPos = input.Position, target.Position

        input.Changed:Connect(function()
            if input.UserInputState ~= Enum.UserInputState.End then return end
            if dragging then
                if moved then
                    if onEnd then onEnd() end
                elseif onClick and not uiLocked then
                    onClick()
                end
            end
            dragging = false
        end)
    end)

    track(UserInputService.InputChanged:Connect(function(input)
        if uiLocked then dragging = false return end
        if not dragging or not isMove(input) then return end
        local delta = input.Position - dragStart
        if not moved and delta.Magnitude > threshold then moved = true end
        if moved then
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))
end

local function pressScale(btn, downScale)
    local scale = new("UIScale", {}, btn)
    local function release()
        tween(scale, 0.2, { Scale = 1 }, EASE_BACK, DIR_OUT)
    end
    btn.MouseButton1Down:Connect(function()
        if uiLocked then return end
        tween(scale, 0.08, { Scale = downScale })
    end)
    btn.MouseButton1Up:Connect(release)
    btn.MouseLeave:Connect(release)
end

--// ================= SAVED SETTINGS (position / size) =================
local canFS = typeof(writefile) == "function"
    and typeof(readfile) == "function"
    and typeof(isfile) == "function"

local function num(v, default)
    return (type(v) == "number" and v == v and math.abs(v) < 1e6) and v or default
end

local function getViewport()
    local camera = Workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function loadSettings()
    if not canFS then return {} end
    local ok, data = pcall(function()
        if isfile(SAVE_FILE) then
            return HttpService:JSONDecode(readfile(SAVE_FILE))
        end
    end)
    return (ok and type(data) == "table") and data or {}
end

local Saved = loadSettings()
local viewport0 = getViewport()

local curW = math.clamp(num(Saved.w, UI_W), MIN_UI_W, math.max(MIN_UI_W, viewport0.X))
local curH = math.clamp(num(Saved.h, UI_H), MIN_UI_H, math.max(MIN_UI_H, viewport0.Y))

local maxOffX = math.max(0, (viewport0.X - curW) / 2)
local maxOffY = math.max(0, (viewport0.Y - curH) / 2)
local uiPosition = UDim2.new(
    0.5, math.clamp(num(Saved.uiX, 0), -maxOffX, maxOffX),
    0.5, math.clamp(num(Saved.uiY, 0), -maxOffY, maxOffY)
)

local DEFAULT_TOGGLE_POS = UDim2.new(0, 20, 0.5, -TOGGLE_SIZE / 2)
local togglePosition = DEFAULT_TOGGLE_POS
if type(Saved.toggle) == "table" then
    local xs, xo = num(Saved.toggle[1], 0), num(Saved.toggle[2], 20)
    local ys, yo = num(Saved.toggle[3], 0.5), num(Saved.toggle[4], -TOGGLE_SIZE / 2)
    local absX = viewport0.X * xs + xo
    local absY = viewport0.Y * ys + yo
    xo += math.clamp(absX, 0, math.max(0, viewport0.X - TOGGLE_SIZE)) - absX
    yo += math.clamp(absY, 0, math.max(0, viewport0.Y - TOGGLE_SIZE)) - absY
    togglePosition = UDim2.new(xs, xo, ys, yo)
end

local ToggleButton
local saveQueued = false
local function saveSettings()
    if not canFS or saveQueued then return end
    saveQueued = true
    task.delay(SAVE_DELAY, function()
        saveQueued = false
        local t = ToggleButton and ToggleButton.Position or togglePosition
        local data = {
            w = curW, h = curH,
            uiX = uiPosition.X.Offset, uiY = uiPosition.Y.Offset,
            toggle = { t.X.Scale, t.X.Offset, t.Y.Scale, t.Y.Offset },
            fpsMode = ScreenGui:GetAttribute("FpsMode"), -- mode FPS Profile đã chọn (không tự áp khi nạp)
        }
        pcall(writefile, SAVE_FILE, HttpService:JSONEncode(data))
    end)
end

--// ================= FLOATING TOGGLE BUTTON =================
ToggleButton = new("TextButton", {
    Name = "MG_Toggle",
    Size = UDim2.fromOffset(TOGGLE_SIZE, TOGGLE_SIZE),
    Position = togglePosition,
    BackgroundColor3 = Theme.Panel,
    Text = "",
    AutoButtonColor = false,
}, ScreenGui)
corner(ToggleButton, 14)
stroke(ToggleButton)

do
    local ICON_PX = 32
    local unit = ICON_PX / 48
    local V = Vector2.new

    local Holder = new("Frame", {
        Name = "Icon",
        AnchorPoint = ANCHOR_CENTER,
        Position = CENTER,
        Size = UDim2.fromOffset(ICON_PX, ICON_PX),
        BackgroundTransparency = 1,
    }, ToggleButton)

    local function segment(a, b, thick, color)
        local d, mid = b - a, (a + b) / 2
        corner(new("Frame", {
            AnchorPoint = ANCHOR_CENTER,
            Position = UDim2.fromOffset(mid.X, mid.Y),
            Size = UDim2.fromOffset(d.Magnitude + thick, thick),
            Rotation = math.deg(math.atan2(d.Y, d.X)),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, Holder), thick / 2)
    end

    local function roundPath(pts, r)
        if r <= 0 or #pts < 3 then return pts end
        local out = { pts[1] }
        for i = 2, #pts - 1 do
            local P, A, B = pts[i], pts[i - 1], pts[i + 1]
            local p1 = P + (A - P).Unit * r
            local p2 = P + (B - P).Unit * r
            for step = 0, 5 do
                local t = step / 5
                table.insert(out, p1:Lerp(P, t):Lerp(P:Lerp(p2, t), t))
            end
        end
        table.insert(out, pts[#pts])
        return out
    end

    local function drawPath(pts, radius, width, color, inner)
        pts = roundPath(pts, radius)
        local mapped = {}
        for i, p in ipairs(pts) do
            if inner then p = p * 0.55 + V(10.8, 10.8) end
            mapped[i] = p * unit
        end
        local thick = (inner and width * 0.55 or width) * unit
        for i = 1, #mapped - 1 do
            segment(mapped[i], mapped[i + 1], thick, color)
        end
    end

    local F, S = Theme.AccentPurple, Theme.AccentPink

    drawPath({ V(4, 34), V(4, 44), V(14, 44) }, 0, 4, F)
    drawPath({ V(34, 44), V(44, 44), V(44, 34) }, 0, 4, F)
    drawPath({ V(34, 4), V(44, 4), V(44, 14) }, 0, 4, F)
    drawPath({ V(14, 4), V(4, 4), V(4, 14) }, 0, 4, F)

    drawPath({ V(20, 15), V(24, 19), V(28, 15) }, 0, 6, S, true)
    drawPath({ V(24, 19), V(24, 4), V(44, 4), V(44, 19) }, 4, 6, S, true)
    drawPath({ V(28, 33), V(24, 29), V(20, 33) }, 0, 6, S, true)
    drawPath({ V(24, 29), V(24, 44), V(4, 44), V(4, 29) }, 4, 6, S, true)
    drawPath({ V(33, 20), V(29, 24), V(33, 28) }, 0, 6, S, true)
    drawPath({ V(29, 24), V(44, 24), V(44, 44), V(29, 44) }, 4, 6, S, true)
    drawPath({ V(15, 28), V(19, 24), V(15, 20) }, 0, 6, S, true)
    drawPath({ V(19, 24), V(4, 24), V(4, 4), V(19, 4) }, 4, 6, S, true)
end

--// ================= MAIN WINDOW =================
local MainUI = new("CanvasGroup", {
    Name = "MG_Main",
    AnchorPoint = ANCHOR_CENTER,
    Position = uiPosition,
    Size = UDim2.fromOffset(curW, curH),
    GroupTransparency = 1,
    BackgroundColor3 = Theme.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Visible = false,
}, ScreenGui)
corner(MainUI, 12)
local MainUIStroke = stroke(MainUI)

--// ---- Top bar ----
local TopBar = new("Frame", {
    Name = "TopBar",
    Size = UDim2.new(1, 0, 0, TOPBAR_HEIGHT),
    BackgroundColor3 = Theme.Header,
    BorderSizePixel = 0,
    Active = true,
}, MainUI)
corner(TopBar, 12)

new("Frame", {
    Size = UDim2.new(1, 0, 0, 12),
    Position = UDim2.new(0, 0, 1, -12),
    BackgroundColor3 = Theme.Header,
    BorderSizePixel = 0,
}, TopBar)

new("Frame", {
    Size = UDim2.new(1, 0, 0, 2),
    Position = UDim2.new(0, 0, 1, -2),
    BackgroundColor3 = Theme.AccentPink,
    BorderSizePixel = 0,
    ZIndex = 2,
}, TopBar)

label(TopBar, {
    Size = UDim2.new(1, -180, 1, 0),
    Position = UDim2.fromOffset(16, 0),
    Text = UI_NAME,
    TextSize = 18,
    TextColor3 = Theme.AccentPink,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 2,
})

--// ---- Topbar icons ----
local TOPBAR_BTN_SIZE   = 26
local TOPBAR_BTN_GAP    = 6
local TOPBAR_BTN_MARGIN = 8
local ICON_SIZE         = 14

local function iconBar(holder, w, h, color, rotation)
    return corner(new("Frame", {
        AnchorPoint = ANCHOR_CENTER,
        Position = CENTER,
        Size = UDim2.fromOffset(w, h),
        Rotation = rotation or 0,
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, holder), 1)
end

local function iconBox(holder, size, color, radius, thickness, pos, fill)
    local f = new("Frame", {
        AnchorPoint = ANCHOR_CENTER,
        Position = pos or CENTER,
        Size = UDim2.fromOffset(size, size),
        BackgroundColor3 = fill,
        BackgroundTransparency = fill and 0 or 1,
        BorderSizePixel = 0,
    }, holder)
    corner(f, radius)
    stroke(f, color, thickness)
end

local Icons = {}

function Icons.minimize(h, c)
    iconBar(h, ICON_SIZE, 1.5, c)
end

function Icons.maximize(h, c)
    iconBox(h, ICON_SIZE, c, 3, 1.4)
end

function Icons.restore(h, c, bg)
    iconBox(h, ICON_SIZE - 4, c, 2, 1.3, UDim2.new(0.5, 2, 0.5, -2), bg)
    iconBox(h, ICON_SIZE - 4, c, 2, 1.3, UDim2.new(0.5, -2, 0.5, 2), bg)
end

function Icons.close(h, c)
    iconBar(h, ICON_SIZE + 2, 1.5, c, 45)
    iconBar(h, ICON_SIZE + 2, 1.5, c, -45)
end

function Icons.resize(h, c)
    iconBox(h, ICON_SIZE, c, 3, 1.4)
    iconBar(h, ICON_SIZE * 0.95, 1.5, c, -45)
end

function Icons.reset(h, c)
    local Ring = new("Frame", {
        AnchorPoint = ANCHOR_CENTER,
        Position = CENTER,
        Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
        BackgroundTransparency = 1,
    }, h)
    corner(Ring, 100)
    new("UIGradient", {
        Rotation = 45,
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0.00, 1),
            NumberSequenceKeypoint.new(0.22, 1),
            NumberSequenceKeypoint.new(0.23, 0),
            NumberSequenceKeypoint.new(1.00, 0),
        }),
    }, stroke(Ring, c, 1.5))

    for _, r in ipairs({
        { UDim2.fromOffset(0, 0),   UDim2.fromOffset(1.5, 5) },
        { UDim2.fromOffset(0, 3.5), UDim2.fromOffset(5, 1.5) },
    }) do
        corner(new("Frame", {
            Position = r[1], Size = r[2],
            BackgroundColor3 = c, BorderSizePixel = 0,
        }, h), 1)
    end
end

-- Icon vẽ theo SVG (viewBox 48x48, nét 4, đầu/khớp bo tròn)
local function svgStroke(h, pts, color, closed)
    local unit  = h.Size.X.Offset / 48
    local thick = 4 * unit
    local n = #pts
    for i = 1, closed and n or n - 1 do
        local a, b = pts[i] * unit, pts[i % n + 1] * unit
        local d, mid = b - a, (a + b) / 2
        corner(new("Frame", {
            AnchorPoint = ANCHOR_CENTER,
            Position = UDim2.fromOffset(mid.X, mid.Y),
            Size = UDim2.fromOffset(d.Magnitude + thick, thick),
            Rotation = math.deg(math.atan2(d.Y, d.X)),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, h), thick / 2)
    end
end

function Icons.delete(h, c)
    local V = Vector2.new
    svgStroke(h, { V(8, 8), V(40, 40) }, c)
    svgStroke(h, { V(8, 40), V(40, 8) }, c)
end

function Icons.play(h, c)
    local V = Vector2.new
    svgStroke(h, {
        V(15, 24), V(15, 11.876), V(25.5, 17.938),
        V(36, 24), V(25.5, 30.062), V(15, 36.124),
    }, c, true)
end

local function drawIcon(holder, kind, color, bgColor)
    holder:ClearAllChildren()
    Icons[kind](holder, color, bgColor)
end

local function createTopbarButton(kind, order, iconColor)
    iconColor = iconColor or Theme.Text
    local xOffset = -(TOPBAR_BTN_MARGIN + TOPBAR_BTN_SIZE * order + TOPBAR_BTN_GAP * (order - 1))

    local Btn = new("TextButton", {
        Size = UDim2.fromOffset(TOPBAR_BTN_SIZE, TOPBAR_BTN_SIZE),
        Position = UDim2.new(1, xOffset, 0.5, -TOPBAR_BTN_SIZE / 2),
        BackgroundColor3 = Theme.PanelAlt,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
    }, TopBar)
    corner(Btn, 6)

    local IconHolder = new("Frame", {
        Name = "Icon",
        AnchorPoint = ANCHOR_CENTER,
        Position = CENTER,
        Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
        BackgroundTransparency = 1,
        ZIndex = 3,
    }, Btn)

    drawIcon(IconHolder, kind, iconColor, Theme.PanelAlt)
    return Btn, IconHolder
end

local CloseBtn                     = createTopbarButton("close", 1, Theme.Danger)
local MaximizeBtn, MaximizeIcon    = createTopbarButton("maximize", 2)
local MinimizeBtn                  = createTopbarButton("minimize", 3)
local ResizeBtn, ResizeIcon        = createTopbarButton("resize", 4)
local ResetBtn                     = createTopbarButton("reset", 5)

--// ---- Body ----
local Body = new("Frame", {
    Name = "Body",
    Size = UDim2.new(1, 0, 1, -TOPBAR_HEIGHT),
    Position = UDim2.fromOffset(0, TOPBAR_HEIGHT),
    BackgroundTransparency = 1,
}, MainUI)

local FunctionPanel = new("Frame", {
    Name = "FunctionPanel",
    Position = UDim2.fromOffset(MARGIN_EDGE + TAB_PANEL_WIDTH + MARGIN_GAP, MARGIN_EDGE),
    Size = UDim2.new(1, -(MARGIN_EDGE + TAB_PANEL_WIDTH + MARGIN_GAP + MARGIN_EDGE), 1, -(MARGIN_EDGE * 2)),
    BackgroundColor3 = Theme.PanelAlt,
    BorderSizePixel = 0,
}, Body)
corner(FunctionPanel, 8)
stroke(FunctionPanel)

local FunctionScroll = new("ScrollingFrame", {
    Name = "FunctionScroll",
    Size = UDim2.new(1, -8, 1, -8),
    Position = UDim2.fromOffset(4, 4),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 5,
    ScrollBarImageColor3 = Theme.AccentPink,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, FunctionPanel)
list(FunctionScroll, 10)
padding(FunctionScroll, 4, 4)

local TabColumn = new("Frame", {
    Name = "TabColumn",
    Position = UDim2.fromOffset(MARGIN_EDGE, MARGIN_EDGE),
    Size = UDim2.new(0, TAB_PANEL_WIDTH, 1, -(MARGIN_EDGE * 2)),
    BackgroundTransparency = 1,
}, Body)

local TabPanel = new("Frame", {
    Name = "TabPanel",
    Size = UDim2.new(1, 0, 1, -(HIGHLIGHT_HEIGHT + HIGHLIGHT_GAP)),
    BackgroundColor3 = Theme.PanelAlt,
    BorderSizePixel = 0,
}, TabColumn)
corner(TabPanel, 8)
stroke(TabPanel)

local TabScroll = new("ScrollingFrame", {
    Name = "TabScroll",
    Size = UDim2.new(1, -8, 1, -8),
    Position = UDim2.fromOffset(4, 4),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = Theme.AccentPink,
    CanvasSize = UDim2.new(),
}, TabPanel)
padding(TabScroll, 3, 3, 3, 3)

--// ---- Highlight tab (player info) ----
local HighlightTab = new("Frame", {
    Name = "HighlightTab",
    AnchorPoint = Vector2.new(0, 1),
    Position = UDim2.fromScale(0, 1),
    Size = UDim2.new(1, 0, 0, HIGHLIGHT_HEIGHT),
    BackgroundColor3 = Theme.Header,
    BorderSizePixel = 0,
}, TabColumn)
corner(HighlightTab, 8)

do
    local HighlightStroke = stroke(HighlightTab, Theme.AccentPurple, 2)
    local Gradient = new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0.00, 1),
            NumberSequenceKeypoint.new(0.04, 0),
            NumberSequenceKeypoint.new(0.14, 0),
            NumberSequenceKeypoint.new(0.20, 1),
            NumberSequenceKeypoint.new(0.50, 1),
            NumberSequenceKeypoint.new(0.54, 0),
            NumberSequenceKeypoint.new(0.64, 0),
            NumberSequenceKeypoint.new(0.70, 1),
            NumberSequenceKeypoint.new(1.00, 1),
        }),
    }, HighlightStroke)
    TweenService:Create(Gradient, TweenInfo.new(2, EASE_LINEAR, DIR_IN, -1), { Rotation = 360 }):Play()

    local Avatar = new("ImageLabel", {
        Size = UDim2.fromOffset(32, 32),
        Position = UDim2.new(0, 8, 0.5, -16),
        BackgroundColor3 = Theme.Panel,
        ScaleType = Enum.ScaleType.Crop,
        ZIndex = 2,
    }, HighlightTab)
    corner(Avatar, 16)
    stroke(Avatar)

    local TextHolder = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 48, 0.5, 0),
        Size = UDim2.new(1, -56, 0, 32),
        BackgroundTransparency = 1,
        ZIndex = 2,
    }, HighlightTab)
    list(TextHolder, 0, { VerticalAlignment = Enum.VerticalAlignment.Center })

    label(TextHolder, {
        LayoutOrder = 1,
        Size = UDim2.new(1, 0, 0, 18),
        Text = LocalPlayer.DisplayName,
        TextSize = 13,
        TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 2,
    })
    label(TextHolder, {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, 14),
        Text = "@" .. LocalPlayer.Name,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 2,
    })

    task.spawn(function()
        local ok, content = pcall(Players.GetUserThumbnailAsync, Players,
            LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
        if ok and content then Avatar.Image = content end
    end)
end

--// ================= DRAG SUPPORT =================
local isMaximized = false

local function commitUIState()
    if isMaximized then return end
    local p = MainUI.Position
    uiPosition = UDim2.new(0.5, p.X.Offset, 0.5, p.Y.Offset)
    curW, curH = MainUI.Size.X.Offset, MainUI.Size.Y.Offset
    saveSettings()
end

makeDraggable(TopBar, MainUI, commitUIState)

local OVERLAY_TRANSPARENCY = 0.45 -- 0 = đen đặc, 1 = trong suốt hoàn toàn

local InteractionBlocker = new("Frame", {
    Name = "InteractionBlocker",
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Active = true,
    Visible = false,
    ZIndex = 20,
}, MainUI)

--// ================= DIALOGS =================
local DIALOG_SIZE     = UDim2.fromOffset(310, 160)
local BUBBLE_IN_TIME  = 0.3
local FADE_IN_TIME    = BUBBLE_IN_TIME * 2
local BUBBLE_OUT_TIME = BUBBLE_IN_TIME * 0.7
local FADE_OUT_TIME   = BUBBLE_OUT_TIME / 3

local WHITE = Color3.new(1, 1, 1)
local overlayTween

local function setOverlay(on)
    if overlayTween then overlayTween:Cancel() end
    if on then
        InteractionBlocker.Visible = true
        overlayTween = tween(InteractionBlocker, FADE_IN_TIME, { BackgroundTransparency = OVERLAY_TRANSPARENCY }, EASE_QUAD, DIR_OUT)
    else
        overlayTween = tween(InteractionBlocker, BUBBLE_OUT_TIME, { BackgroundTransparency = 1 }, EASE_QUAD, DIR_IN)
        overlayTween.Completed:Connect(function(state)
            if state == Enum.PlaybackState.Completed then
                InteractionBlocker.Visible = false
            end
        end)
    end
end

local function createDialog(name, title, message, yesColor, yesText, noText)
    local Box = new("CanvasGroup", {
        Name = name,
        Visible = false,
        AnchorPoint = ANCHOR_CENTER,
        Position = CENTER,
        Size = UDim2.new(),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        ZIndex = 51,
    }, ScreenGui)
    corner(Box, 12)

    -- nền chuyển sắc nhẹ: PanelAlt (trên) -> Panel (dưới)
    -- (đặt trên Frame riêng, vì UIGradient trên CanvasGroup sẽ nhuộm luôn cả chữ và nút bên trong)
    Box.BackgroundTransparency = 1
    local Bg = new("Frame", {
        Name = "Bg",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
        ZIndex = 51,
    }, Box)
    corner(Bg, 12)
    new("UIGradient", {
        Color = ColorSequence.new(Theme.PanelAlt, Theme.Panel),
        Rotation = 90,
    }, Bg)

    -- viền gradient tím -> màu nhấn của hộp
    local BoxStroke = stroke(Box, WHITE, 1.5)
    new("UIGradient", {
        Color = ColorSequence.new(Theme.AccentPurple, yesColor),
        Rotation = 45,
    }, BoxStroke)

    -- thanh accent phía trên
    local Accent = new("Frame", {
        Size = UDim2.new(1, 0, 0, 3),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
        ZIndex = 52,
    }, Box)
    new("UIGradient", {
        Color = ColorSequence.new(Theme.AccentPurple, yesColor),
    }, Accent)

    -- tiêu đề
    label(Box, {
        Size = UDim2.new(1, -32, 0, 20),
        Position = UDim2.fromOffset(16, 16),
        Text = string.upper(title),
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Sakura,
        ZIndex = 52,
    })

    -- nội dung
    local MessageLabel = label(Box, {
        Size = UDim2.new(1, -32, 0, 44),
        Position = UDim2.fromOffset(16, 40),
        Text = message,
        TextSize = 16,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextColor3 = Theme.Text,
        ZIndex = 52,
    })

    -- đường kẻ phân cách
    new("Frame", {
        Size = UDim2.new(1, -32, 0, 1),
        Position = UDim2.new(0, 16, 1, -60),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ZIndex = 52,
    }, Box)

    local function button(text, pos, bg, textColor, outlined)
        local Btn = new("TextButton", {
            Size = UDim2.new(0.5, -22, 0, 34),
            Position = pos,
            BackgroundColor3 = bg,
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = textColor,
            AutoButtonColor = false,
            ZIndex = 52,
        }, Box)
        corner(Btn, 8)
        local S = outlined and stroke(Btn, Theme.Border, 1) or nil
        pressScale(Btn, 0.95)

        Btn.MouseEnter:Connect(function()
            if outlined then
                tween(Btn, 0.15, { BackgroundColor3 = Theme.Header, TextColor3 = Theme.Sakura })
                if S then tween(S, 0.15, { Color = Theme.AccentPurple }) end
            else
                tween(Btn, 0.15, { BackgroundColor3 = bg:Lerp(WHITE, 0.15) })
            end
        end)
        Btn.MouseLeave:Connect(function()
            if outlined then
                tween(Btn, 0.15, { BackgroundColor3 = bg, TextColor3 = textColor })
                if S then tween(S, 0.15, { Color = Theme.Border }) end
            else
                tween(Btn, 0.15, { BackgroundColor3 = bg })
            end
        end)
        return Btn
    end

    local Yes = button(yesText or "Yes", UDim2.new(0, 16, 1, -46), yesColor, Theme.Background)
    local No  = button(noText or "No", UDim2.new(1, -16, 1, -46), Theme.PanelAlt, Theme.Text, true)
    No.AnchorPoint = Vector2.new(1, 0)

    local hideToken = 0

    local function show()
        hideToken += 1
        setOverlay(true)
        Box.Visible = true
        Box.GroupTransparency = 1
        Box.Size = UDim2.new()
        tween(Box, BUBBLE_IN_TIME, { Size = DIALOG_SIZE }, EASE_QUAD, DIR_OUT)
        tween(Box, FADE_IN_TIME, { GroupTransparency = 0 }, EASE_QUAD, DIR_OUT)
    end

    local function hide()
        hideToken += 1
        local token = hideToken
        setOverlay(false)
        local sizeTween = tween(Box, BUBBLE_OUT_TIME, { Size = UDim2.new() }, EASE_QUAD, DIR_IN)
        tween(Box, FADE_OUT_TIME, { GroupTransparency = 1 }, EASE_QUAD, DIR_IN)
        sizeTween.Completed:Connect(function(state)
            if state ~= Enum.PlaybackState.Completed or token ~= hideToken then return end
            Box.Visible = false
        end)
    end

    No.MouseButton1Click:Connect(hide)
    return { Box = Box, Yes = Yes, Message = MessageLabel, show = show, hide = hide }
end

local CloseDialog = createDialog("ConfirmBox", "Close script", "You want to close this script?", Theme.Danger)
local ResetDialog = createDialog("NotBox2", "Reset UI", "Do you want to reset UI?", Theme.AccentPink)
-- NotBoxDe (tab Script): xác nhận xoá function, nội dung được gán lại mỗi lần mở
local DeleteDialog = createDialog("NotBoxDe", "Delete function", "Do you want to delete this function?", Theme.Danger, "Yes, Delete", "Cancel")

--// ================= OPEN / CLOSE ANIMATION =================
local isOpen = false
local fadeTween
local ScriptDialog -- NotBoxA (tab Script), được tạo ở phần SCRIPT TAB

local function fadeMainUI(time, target, dir)
    if fadeTween then fadeTween:Cancel() end
    fadeTween = tween(MainUI, time, { GroupTransparency = target }, EASE_QUAD, dir)
    return fadeTween
end

local function openUI()
    isOpen = true
    MainUI.Visible = true
    fadeMainUI(POPUP_TIME, 0, DIR_OUT)
end

local function closeUI()
    isOpen = false
    if CloseDialog.Box.Visible then CloseDialog.hide() end
    if ResetDialog.Box.Visible then ResetDialog.hide() end
    if DeleteDialog.Box.Visible then DeleteDialog.hide() end
    if ScriptDialog and ScriptDialog.Box.Visible then ScriptDialog.hide() end
    fadeMainUI(CLOSE_TIME, 1, DIR_IN).Completed:Connect(function(state)
        if state == Enum.PlaybackState.Completed and not isOpen then
            MainUI.Visible = false
        end
    end)
end

makeDraggable(ToggleButton, ToggleButton, saveSettings, function()
    if isOpen then closeUI() else openUI() end
end, 5)

--// ---- Minimize ----
MinimizeBtn.MouseButton1Click:Connect(function()
    if uiLocked then return end
    if isOpen then closeUI() end
end)

--// ---- Maximize / Restore ----
local preMaxSize, preMaxPos

local function toggleMaximize()
    if isMaximized then
        isMaximized = false
        drawIcon(MaximizeIcon, "maximize", Theme.Text, Theme.PanelAlt)
        tween(MainUI, 0.25, { Size = preMaxSize, Position = preMaxPos }, EASE_QUAD, DIR_OUT)
    else
        preMaxSize, preMaxPos = MainUI.Size, MainUI.Position
        isMaximized = true
        drawIcon(MaximizeIcon, "restore", Theme.Text, Theme.PanelAlt)
        local viewport = getViewport()
        tween(MainUI, 0.25, {
            Size = UDim2.fromOffset(viewport.X, viewport.Y),
            Position = CENTER,
        }, EASE_QUAD, DIR_OUT)
    end
end

MaximizeBtn.MouseButton1Click:Connect(function()
    if uiLocked then return end
    toggleMaximize()
end)

--// ---- Close ----
CloseBtn.MouseButton1Click:Connect(function()
    if uiLocked then return end
    CloseDialog.show()
end)
CloseDialog.Yes.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

--// ---- Reset ----
local function resetLayout()
    if isMaximized then
        isMaximized = false
        drawIcon(MaximizeIcon, "maximize", Theme.Text, Theme.PanelAlt)
    end

    curW, curH = UI_W, UI_H
    uiPosition = CENTER

    local props = { Position = uiPosition }
    if isOpen then props.Size = UDim2.fromOffset(curW, curH) end
    tween(MainUI, 0.2, props, EASE_QUAD, DIR_OUT)
    tween(ToggleButton, 0.2, { Position = DEFAULT_TOGGLE_POS }, EASE_QUAD, DIR_OUT)

    saveSettings()
end

ResetBtn.MouseButton1Click:Connect(function()
    if uiLocked then return end
    ResetDialog.show()
end)
ResetDialog.Yes.MouseButton1Click:Connect(function()
    resetLayout()
    ResetDialog.hide()
end)

--// ================= RESIZE MODE =================
local RESIZE_HANDLE_SIZE = 18
local resizeMode = false
local resizeDragCorner
local resizeFixedX, resizeFixedY = 0, 0

local CORNER_ANCHORS = {
    TL = Vector2.new(0, 0),
    TR = Vector2.new(1, 0),
    BL = Vector2.new(0, 1),
    BR = Vector2.new(1, 1),
}
local ResizeHandles = {}

local function updateResizeHandlePositions()
    local pos, size = MainUI.AbsolutePosition, MainUI.AbsoluteSize
    for cornerName, handle in pairs(ResizeHandles) do
        local a = CORNER_ANCHORS[cornerName]
        handle.Position = UDim2.fromOffset(pos.X + size.X * a.X, pos.Y + size.Y * a.Y)
    end
end

for cornerName, anchor in pairs(CORNER_ANCHORS) do
    local Handle = new("Frame", {
        Name = "ResizeHandle",
        AnchorPoint = ANCHOR_CENTER,
        Size = UDim2.fromOffset(RESIZE_HANDLE_SIZE, RESIZE_HANDLE_SIZE),
        BackgroundColor3 = Theme.AccentPink,
        BorderSizePixel = 0,
        Visible = false,
        Active = true,
        ZIndex = 100,
    }, ScreenGui)
    corner(Handle, 6)
    stroke(Handle, Theme.Text, 1.5)
    ResizeHandles[cornerName] = Handle

    local Grip = new("TextButton", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 101,
    }, Handle)

    Grip.InputBegan:Connect(function(input)
        if not resizeMode or not isPress(input) then return end

        local pos, size = MainUI.AbsolutePosition, MainUI.AbsoluteSize
        resizeFixedX = pos.X + size.X * (1 - anchor.X)
        resizeFixedY = pos.Y + size.Y * (1 - anchor.Y)
        resizeDragCorner = cornerName

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End and resizeDragCorner == cornerName then
                resizeDragCorner = nil
                commitUIState()
            end
        end)
    end)
end

local function onMainUIRectChanged()
    if resizeMode then updateResizeHandlePositions() end
end
MainUI:GetPropertyChangedSignal("AbsolutePosition"):Connect(onMainUIRectChanged)
MainUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(onMainUIRectChanged)

track(UserInputService.InputChanged:Connect(function(input)
    if not resizeMode or not resizeDragCorner or not isMove(input) then return end

    local mouseX, mouseY = input.Position.X, input.Position.Y
    local newW = math.max(MIN_UI_W, math.abs(mouseX - resizeFixedX))
    local newH = math.max(MIN_UI_H, math.abs(mouseY - resizeFixedY))

    local movingX = resizeFixedX + (mouseX >= resizeFixedX and 1 or -1) * newW
    local movingY = resizeFixedY + (mouseY >= resizeFixedY and 1 or -1) * newH
    local viewport = getViewport()

    MainUI.Size = UDim2.fromOffset(newW, newH)
    MainUI.Position = UDim2.new(
        0.5, (resizeFixedX + movingX) / 2 - viewport.X * 0.5,
        0.5, (resizeFixedY + movingY) / 2 - viewport.Y * 0.5
    )
    updateResizeHandlePositions()
end))

local function setResizeMode(enabled)
    resizeMode = enabled
    uiLocked = enabled
    resizeDragCorner = nil
    drawIcon(ResizeIcon, "resize", enabled and Theme.AccentPink or Theme.Text, Theme.PanelAlt)
    tween(MainUIStroke, 0.2, {
        Color = enabled and Theme.AccentPink or Theme.Border,
        Thickness = enabled and 2 or 1,
    })
    for _, h in pairs(ResizeHandles) do h.Visible = enabled end
    if enabled then updateResizeHandlePositions() end
end

ResizeBtn.MouseButton1Click:Connect(function()
    setResizeMode(not resizeMode)
end)

--// ================= TAB SYSTEM =================
local TAB_HEIGHT          = 34
local TAB_GAP             = 6
local TAB_TEXT_PAD        = 14
local TAB_TEXT_PAD_ACTIVE = 18
local TAB_BAR_HEIGHT      = 20

local CONTENT_EDGE     = 2
local CONTENT_FADE_OUT = 0.12
local CONTENT_FADE_IN  = 0.22
local CONTENT_SLIDE    = 10

local TabData = {}
local tabCount = 0
local activeTab
local switchToken = 0
local ContentTweens = {}

local TabPill = new("Frame", {
    Name = "TabPill",
    Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
    BackgroundColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 0,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 1,
}, TabScroll)
corner(TabPill, 6)

-- Kiểu highlight của tab list: nền tím -> hồng mờ dần từ trái sang phải + thanh accent bên trái
-- (khác với Player Info: viền tím sáng chạy vòng quanh)
new("UIGradient", {
    Color = ColorSequence.new(Theme.AccentPurple, Theme.AccentPink),
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0.00, 0.55),
        NumberSequenceKeypoint.new(0.60, 0.85),
        NumberSequenceKeypoint.new(1.00, 1.00),
    }),
}, TabPill)

local PillBar = new("Frame", {
    Name = "AccentBar",
    AnchorPoint = Vector2.new(0, 0.5),
    Position = UDim2.new(0, 6, 0.5, 0),
    Size = UDim2.fromOffset(3, TAB_BAR_HEIGHT),
    BackgroundColor3 = Theme.AccentPink,
    BorderSizePixel = 0,
}, TabPill)
corner(PillBar, 2)
local PillBarGlow = stroke(PillBar, Theme.AccentPink, 3)
PillBarGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
PillBarGlow.Transparency = 0.75

local function cancelContentTween(content)
    local t = ContentTweens[content]
    if t then
        t:Cancel()
        ContentTweens[content] = nil
    end
end

local function selectTab(name)
    if activeTab == name then return end
    local previous = activeTab
    activeTab = name
    switchToken += 1
    local token = switchToken

    for tabName, t in pairs(TabData) do
        local selected = tabName == name
        tween(t.btn, 0.2, {
            BackgroundTransparency = 1,
            TextColor3 = selected and Theme.Sakura or Theme.SubText,
        })
        tween(t.pad, 0.25, {
            PaddingLeft = UDim.new(0, selected and TAB_TEXT_PAD_ACTIVE or TAB_TEXT_PAD),
        }, EASE_QUINT, DIR_OUT)
    end

    local target = UDim2.fromOffset(0, TabData[name].index * (TAB_HEIGHT + TAB_GAP))
    if TabPill.Visible then
        tween(TabPill, 0.25, { Position = target }, EASE_QUINT, DIR_OUT)
        tween(PillBar, 0.1, { Size = UDim2.fromOffset(3, 8) }).Completed:Once(function()
            tween(PillBar, 0.25, { Size = UDim2.fromOffset(3, TAB_BAR_HEIGHT) }, EASE_BACK, DIR_OUT)
        end)
    else
        TabPill.Position = target
        TabPill.Visible = true
    end

    for tabName, t in pairs(TabData) do
        if tabName ~= name and tabName ~= previous then
            cancelContentTween(t.content)
            t.content.Visible = false
        end
    end

    local newContent, pad = TabData[name].content, TabData[name].contentPad

    local function fadeIn()
        if token ~= switchToken then return end
        cancelContentTween(newContent)

        if not newContent.Visible then
            newContent.GroupTransparency = 1
            pad.PaddingTop = UDim.new(0, CONTENT_EDGE + CONTENT_SLIDE)
            newContent.Visible = true
        end

        ContentTweens[newContent] = tween(newContent, CONTENT_FADE_IN, { GroupTransparency = 0 }, EASE_QUAD, DIR_OUT)
        tween(pad, CONTENT_FADE_IN, { PaddingTop = UDim.new(0, CONTENT_EDGE) }, EASE_QUINT, DIR_OUT)
    end

    local oldContent = previous and TabData[previous].content
    if oldContent and oldContent.Visible then
        cancelContentTween(oldContent)
        local fade = tween(oldContent, CONTENT_FADE_OUT, { GroupTransparency = 1 }, EASE_QUAD, DIR_IN)
        ContentTweens[oldContent] = fade
        fade.Completed:Connect(function(state)
            if state ~= Enum.PlaybackState.Completed then return end
            oldContent.Visible = false
            ContentTweens[oldContent] = nil
            fadeIn()
        end)
    else
        fadeIn()
    end
end

local function CreateTab(name)
    tabCount += 1
    local index = tabCount - 1
    TabScroll.CanvasSize = UDim2.fromOffset(0, tabCount * (TAB_HEIGHT + TAB_GAP) - TAB_GAP + 6)

    local Btn = new("TextButton", {
        Name = "Tab_" .. name,
        AnchorPoint = ANCHOR_CENTER,
        Position = UDim2.new(0.5, 0, 0, index * (TAB_HEIGHT + TAB_GAP) + TAB_HEIGHT / 2),
        Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
        BackgroundColor3 = Theme.Header,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = name,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false,
        TextWrapped = true,
        ZIndex = 2,
    }, TabScroll)
    corner(Btn, 6)
    local Pad = padding(Btn, TAB_TEXT_PAD, 8)
    pressScale(Btn, 0.97)

    Btn.MouseEnter:Connect(function()
        if uiLocked or activeTab == name then return end
        tween(Btn, 0.15, { BackgroundTransparency = 0.5, TextColor3 = Theme.Text })
        tween(Pad, 0.15, { PaddingLeft = UDim.new(0, TAB_TEXT_PAD + 2) })
    end)
    Btn.MouseLeave:Connect(function()
        if activeTab == name then return end
        tween(Btn, 0.15, { BackgroundTransparency = 1, TextColor3 = Theme.SubText })
        tween(Pad, 0.15, { PaddingLeft = UDim.new(0, TAB_TEXT_PAD) })
    end)
    Btn.MouseButton1Click:Connect(function()
        if uiLocked then return end
        selectTab(name)
    end)

    local Content = new("CanvasGroup", {
        Name = "TabContent_" .. name,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        GroupTransparency = 1,
        Visible = false,
    }, FunctionScroll)
    local ContentPad = padding(Content, CONTENT_EDGE, CONTENT_EDGE, CONTENT_EDGE, CONTENT_EDGE)
    list(Content, 10)

    TabData[name] = { index = index, btn = Btn, pad = Pad, content = Content, contentPad = ContentPad }

    if tabCount == 1 then selectTab(name) end
    return Content
end

--// ================= FUNCTION ELEMENT BUILDERS =================
local function CreateToggleOption(parent, title, height)
    local Frame = new("Frame", {
        Size = UDim2.new(1, 0, 0, height or 50),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
    }, parent)
    corner(Frame, 8)
    stroke(Frame)

    label(Frame, {
        Size = UDim2.new(1, -80, 1, 0),
        Position = UDim2.fromOffset(14, 0),
        Text = title,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
    })

    local pxW, pxH, rightOffset = 46, 24, 12
    local Switch = new("TextButton", {
        Size = UDim2.fromOffset(pxW, pxH),
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -rightOffset, 0.5, 0),
        BackgroundColor3 = Theme.ToggleTrackOff,
        Text = "",
        AutoButtonColor = false,
    }, Frame)
    corner(Switch, 12)

    local SwitchGradient = new("UIGradient", {
        Color = ColorSequence.new(Theme.AccentPurple, Theme.AccentPink),
        Enabled = false,
    }, Switch)

    local Knob = new("Frame", {
        Size = UDim2.fromOffset(pxH - 4, pxH - 4),
        Position = UDim2.fromOffset(2, 2),
        BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0,
    }, Switch)
    corner(Knob, 10)

    local state = false
    Switch:SetAttribute("Toggled", false)

    local function setState(value)
        value = value and true or false
        if state == value then return end
        state = value
        Switch:SetAttribute("Toggled", state)

        SwitchGradient.Enabled = state
        tween(Switch, 0.18, { BackgroundColor3 = state and Theme.AccentPink or Theme.ToggleTrackOff })
        tween(Knob, 0.18, {
            Position = state and UDim2.new(1, -(pxH - 2), 0, 2) or UDim2.fromOffset(2, 2),
            BackgroundColor3 = state and Theme.ToggleKnobOn or Theme.Text,
        })
    end

    Switch.MouseButton1Click:Connect(function()
        if uiLocked then return end
        setState(not state)
    end)

    return Switch, setState
end

local function CreateSectionLabel(parent, text)
    return label(parent, {
        Size = UDim2.new(1, 0, 0, 24),
        Text = text,
        TextSize = 13,
        TextColor3 = Theme.SubText,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
end

local function CreateCard(parent, name, padV, padL, padR)
    local Card = new("Frame", {
        Name = name,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
    }, parent)
    corner(Card, 8)
    stroke(Card)
    padding(Card, padL, padR, padV, padV)
    list(Card, 8)
    return Card
end

local function CreateStyledButton(parent, btnText, width)
    local Btn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(width or 70, 28),
        BackgroundColor3 = Theme.Header,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = btnText,
        Font = Enum.Font.GothamBold,
        TextSize = 13,
        TextColor3 = Theme.Text,
    }, parent)
    corner(Btn, 6)
    stroke(Btn)
    pressScale(Btn, 0.95)

    Btn.MouseEnter:Connect(function()
        if uiLocked then return end
        tween(Btn, 0.15, { BackgroundColor3 = Theme.Border })
    end)
    Btn.MouseLeave:Connect(function()
        tween(Btn, 0.15, { BackgroundColor3 = Theme.Header })
    end)

    return Btn
end

local function flashButtonFeedback(Btn, defaultText, feedbackText, isError, holdTime)
    Btn.Text = feedbackText
    Btn.TextColor3 = isError and Theme.Danger or Theme.Sakura
    task.delay(holdTime or 1.2, function()
        Btn.Text = defaultText
        Btn.TextColor3 = Theme.Text
    end)
end

local function CreateInfoRow(parent, title, height)
    local Frame = new("Frame", {
        Size = UDim2.new(1, 0, 0, height or 50),
        BackgroundColor3 = Theme.Panel,
        BorderSizePixel = 0,
        ClipsDescendants = true,
    }, parent)
    corner(Frame, 8)
    stroke(Frame)
    padding(Frame, 14, 12)

    local Left = new("Frame", {
        Name = "Left",
        Size = UDim2.new(1, -90, 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
    }, Frame)
    list(Left, 8, {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
    })

    label(Left, {
        Name = "Title",
        LayoutOrder = 1,
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = title,
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Text,
    })

    return Frame, Left
end

local function bindBoxFocus(Box, BoxStroke, onFocus, onLost)
    Box.Focused:Connect(function()
        if uiLocked then Box:ReleaseFocus() return end
        tween(BoxStroke, 0.15, { Color = Theme.AccentPurple })
        if onFocus then onFocus() end
    end)
    Box.FocusLost:Connect(function()
        tween(BoxStroke, 0.15, { Color = Theme.Border })
        if onLost then onLost() end
    end)
end

local function flashStrokeError(BoxStroke)
    BoxStroke.Color = Theme.Danger
    tween(BoxStroke, 0.6, { Color = Theme.Border })
end

local function guarded(fn)
    local busy = false
    return function()
        if uiLocked or busy then return end
        busy = true
        fn(function()
            task.delay(1.2, function() busy = false end)
        end)
    end
end

--// ================= TABS =================
local StatusServerTab = CreateTab("Status & Server")
local LocalTab        = CreateTab("Local")
local FPSTab          = CreateTab("FPS")
local ScriptTab       = CreateTab("Script")
local SettingsTab     = CreateTab("Settings")

--// ================= SCRIPT TAB =================
-- Code của tab nằm ở file riêng, nạp từ GitHub: Script.lua
do
    local MODULE_FILE = "Script.lua"
    local MODULE_URL  = "https://raw.githubusercontent.com/MinzTogether/Universal-Script/refs/heads/main/Script.lua"
    local ok, err = pcall(function()
        local src = game:HttpGet(MODULE_URL)
        local init = assert(loadstring(src, "=" .. MODULE_FILE))()
        -- Module trả về ScriptDialog (khai báo sẵn ở phần OPEN / CLOSE để closeUI dùng)
        ScriptDialog = init({
            Tab                = ScriptTab,
            Theme              = Theme,
            ScreenGui          = ScreenGui,
            HttpService        = HttpService,
            UI_NAME            = UI_NAME,
            canFS              = canFS,
            WHITE              = WHITE,
            CENTER             = CENTER,
            ANCHOR_CENTER      = ANCHOR_CENTER,
            EASE_QUAD          = EASE_QUAD,
            DIR_IN             = DIR_IN,
            DIR_OUT            = DIR_OUT,
            BUBBLE_IN_TIME     = BUBBLE_IN_TIME,
            BUBBLE_OUT_TIME    = BUBBLE_OUT_TIME,
            FADE_IN_TIME       = FADE_IN_TIME,
            FADE_OUT_TIME      = FADE_OUT_TIME,
            CONTENT_EDGE       = CONTENT_EDGE,
            new                = new,
            corner             = corner,
            stroke             = stroke,
            padding            = padding,
            list               = list,
            label              = label,
            tween              = tween,
            pressScale         = pressScale,
            drawIcon           = drawIcon,
            setOverlay         = setOverlay,
            FunctionScroll     = FunctionScroll,
            DeleteDialog       = DeleteDialog,
            CreateInfoRow      = CreateInfoRow,
            CreateStyledButton = CreateStyledButton,
            flashStrokeError   = flashStrokeError,
            bindBoxFocus       = bindBoxFocus,
            isLocked           = function() return uiLocked end,
        })
    end)
    if not ok then warn("[Elysera] Không nạp được " .. MODULE_FILE .. ": " .. tostring(err)) end
end

--// ================= STATUS & SERVER TAB =================
-- Code của tab nằm ở file riêng, nạp từ GitHub: Status_Server.lua
do
    local MODULE_FILE = "Status_Server.lua"
    local MODULE_URL  = "https://raw.githubusercontent.com/MinzTogether/Universal-Script/refs/heads/main/Status_Server.lua"
    local ok, err = pcall(function()
        local src = game:HttpGet(MODULE_URL)
        local init = assert(loadstring(src, "=" .. MODULE_FILE))()
        init({
            Tab               = StatusServerTab,
            Theme             = Theme,
            ScreenGui         = ScreenGui,
            LocalPlayer       = LocalPlayer,
            TeleportService   = TeleportService,
            HttpService       = HttpService,
            new               = new,
            corner            = corner,
            stroke            = stroke,
            padding           = padding,
            label             = label,
            CreateInfoRow     = CreateInfoRow,
            CreateCard        = CreateCard,
            CreateStyledButton = CreateStyledButton,
            CreateToggleOption = CreateToggleOption,
            flashButtonFeedback = flashButtonFeedback,
            flashStrokeError  = flashStrokeError,
            bindBoxFocus      = bindBoxFocus,
            guarded           = guarded,
            isLocked          = function() return uiLocked end,
        })
    end)
    if not ok then warn("[Elysera] Không nạp được " .. MODULE_FILE .. ": " .. tostring(err)) end
end

--// ================= LOCAL TAB =================
-- Code của tab nằm ở file riêng, nạp từ GitHub: Local.lua
do
    local MODULE_FILE = "Local.lua"
    local MODULE_URL  = "https://raw.githubusercontent.com/MinzTogether/Universal-Script/refs/heads/main/Local.lua"
    local ok, err = pcall(function()
        local src = game:HttpGet(MODULE_URL)
        local init = assert(loadstring(src, "=" .. MODULE_FILE))()
        init({
            Tab                = LocalTab,
            Theme              = Theme,
            ScreenGui          = ScreenGui,
            LocalPlayer        = LocalPlayer,
            Players            = Players,
            RunService         = RunService,
            UserInputService   = UserInputService,
            Workspace          = Workspace,
            CoreGui            = CoreGui,
            new                = new,
            corner             = corner,
            stroke             = stroke,
            padding            = padding,
            list               = list,
            CreateCard         = CreateCard,
            CreateToggleOption = CreateToggleOption,
            flashStrokeError   = flashStrokeError,
            bindBoxFocus       = bindBoxFocus,
        })
    end)
    if not ok then warn("[Elysera] Không nạp được " .. MODULE_FILE .. ": " .. tostring(err)) end
end

--// ================= FPS TAB =================
do
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

    local AntiChatSwitch = CreateToggleOption(SettingsTab, "Anti Chat")
    AntiChatSwitch.Parent.LayoutOrder = 1

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
            if restored > 0 then
                ScreenGui:SetAttribute("LightingBoosted", os.clock()) -- báo Full Bright (tab Local)
            end
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
            ScreenGui:SetAttribute("LightingBoosted", os.clock()) -- báo Full Bright (tab Local)
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
                uiLocked = false
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
            if Popup.open or uiLocked then return end

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
            uiLocked = true
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
                if uiLocked then return end
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
            if uiLocked or benching then return end
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
            if uiLocked or detecting then return end
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
        disableAntiChat()
        Cover:Destroy()
    end)
end

--// ================= EXPOSED API =================
local Elysera = {
    ScreenGui = ScreenGui,
    Theme = Theme,
    Open = openUI,
    Close = closeUI,
    CreateTab = CreateTab,
    CreateToggleOption = CreateToggleOption,
    CreateSectionLabel = CreateSectionLabel,
    SelectTab = selectTab,
}

--// ================= INITIAL STATE =================
openUI()

return Elysera
