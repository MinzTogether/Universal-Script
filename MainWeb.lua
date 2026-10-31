--// ##########################################################################################
--// ##                                                                                      ##
--// ##   MANDATORY: USE ENGLISH (US) ONLY IN THIS FILE                                      ##
--// ##   Every comment, UI text, message and name here MUST be written in English (US).     ##
--// ##   Never add any other language to this file. Keep it English (US) on every edit.     ##
--// ##                                                                                      ##
--// ##########################################################################################

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
-- The GUI lives in CoreGui, or in PlayerGui when the executor cannot write to CoreGui (see ROOT) -> clean up both places
do
    local roots = { CoreGui }
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then roots[#roots + 1] = playerGui end
    for _, root in ipairs(roots) do
        for _, name in ipairs({ "ElyseraUI", "ElyseraCover", "ElyseraFpsOverlay" }) do
            local old = root:FindFirstChild(name)
            if old then pcall(old.Destroy, old) end
        end
    end
end

--// ================= MAIN THEME =================
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

-- Mount the GUI: prefer CoreGui; fall back to PlayerGui when the executor cannot write to CoreGui.
-- GuiRoot is where the GUI really lives: modules mount their own GUI (cover, ESP...) into ctx.GuiRoot,
-- while ctx.CoreGui stays the real CoreGui service (used to find RobloxGui...).
local GuiRoot = CoreGui
do
    local okParent = pcall(function() ScreenGui.Parent = CoreGui end)
    if not okParent or ScreenGui.Parent ~= CoreGui then
        GuiRoot = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
        assert(GuiRoot, "[Elysera] No place to mount the GUI (neither CoreGui nor PlayerGui is usable)")
        ScreenGui.Parent = GuiRoot
        warn("[Elysera] Cannot write to CoreGui, using PlayerGui")
    end
end

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

-- Theme: tweens of color properties that are RUNNING are recorded so Settings.lua (Theme part) can snap them to the new theme's target color
-- when the theme changes mid-tween (otherwise the tween would pull the property back to the old theme's color when it ends).
local liveColorTweens = setmetatable({}, { __mode = "k" }) -- [tween] = { inst, props }
local tween
do
    -- A TweenInfo never changes after creation, so one object is shared per (style, direction, duration) set.
    -- Hover/press effects create a tween on EVERY event; this cache avoids allocating a new TweenInfo each time.
    local infoCache, infoCount = {}, 0 -- [style][direction][duration] = TweenInfo
    local function infoFor(time, style, dir)
        local byStyle = infoCache[style]
        if not byStyle then byStyle = {}; infoCache[style] = byStyle end
        local byDir = byStyle[dir]
        if not byDir then byDir = {}; byStyle[dir] = byDir end
        local info = byDir[time]
        if not info then
            if infoCount >= 128 then -- durations computed at runtime could grow the cache forever: past the limit, clear it and start over
                infoCache, infoCount = {}, 0
                byDir = {}
                infoCache[style] = { [dir] = byDir }
            end
            info = TweenInfo.new(time, style, dir)
            byDir[time] = info
            infoCount += 1
        end
        return info
    end

    function tween(inst, time, props, style, dir)
        local t = TweenService:Create(inst, infoFor(time, style or EASE_QUAD, dir or DIR_OUT), props)
        for k in pairs(props) do
            if k == "Color" or string.sub(k, -6) == "Color3" then
                liveColorTweens[t] = { inst, props }
                t.Completed:Once(function() liveColorTweens[t] = nil end)
                break
            end
        end
        t:Play()
        return t
    end
end
-- Cancel running color tweens and set the target values directly; translate(Color3) returns a new Color3 or nil (keep as is)
local function settleColorTweens(translate)
    for t, rec in pairs(liveColorTweens) do
        liveColorTweens[t] = nil
        t:Cancel()
        for k, v in pairs(rec[2]) do
            if typeof(v) == "Color3" then v = translate(v) or v end
            rec[1][k] = v
        end
    end
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

--// ---- Data folder: workspace/Elysera/ ----
-- Every .json file of the script and its modules lives in this folder (nothing is scattered in the workspace root).
-- Modules receive the dataPath function through ctx. If the executor has no folder support, dataPath returns the plain file name as before.
local dataPath
do
    local DATA_FOLDER = "Elysera"
    -- Old .json files in the workspace root: move them into the new folder once so saved data is not lost
    local LEGACY_FILES = {
        "Elysera_Settings.json", "Elysera_Fps.json", "Elysera_Waypoints.json", "Elysera_Servers.json",
        "L-scr.json", "L-scr.bak.json", "L-scr.state.json",
    }

    local canFolder = canFS
        and typeof(isfolder) == "function"
        and typeof(makefolder) == "function"

    local function ensureFolder()
        if not canFolder then return false end
        local ok, ready = pcall(function()
            if not isfolder(DATA_FOLDER) then makefolder(DATA_FOLDER) end
            return isfolder(DATA_FOLDER)
        end)
        return ok and ready == true
    end

    local useFolder = ensureFolder()

    dataPath = function(name)
        if not useFolder then return name end
        ensureFolder() -- recreate the folder if it was deleted while running
        return DATA_FOLDER .. "/" .. name
    end

    if useFolder then
        for _, name in ipairs(LEGACY_FILES) do
            pcall(function()
                local target = dataPath(name)
                if isfile(name) and not isfile(target) then
                    local body = readfile(name)
                    writefile(target, body)
                    if readfile(target) == body and typeof(delfile) == "function" then
                        delfile(name)
                    end
                end
            end)
        end
    end
end

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
        local path = dataPath(SAVE_FILE)
        if isfile(path) then
            return HttpService:JSONDecode(readfile(path))
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
            fpsMode = ScreenGui:GetAttribute("FpsMode"), -- selected FPS Profile mode (not applied automatically on load)
            theme = ScreenGui:GetAttribute("Theme") or Saved.theme, -- id of the theme in use (Settings.lua applies it on load)
            autoExecute = Saved.autoExecute == true, -- Auto Execute (see the AUTO EXECUTE section); the queue_on_teleport code reads this key again on the new server
        }
        pcall(writefile, dataPath(SAVE_FILE), HttpService:JSONEncode(data))
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

-- Icons drawn from SVG data (viewBox 48x48, stroke 4, round caps and joins)
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
    -- Endless spinning border: paused while the UI is hidden so no property is updated every frame for nothing
    local spin = TweenService:Create(Gradient, TweenInfo.new(2, EASE_LINEAR, DIR_IN, -1), { Rotation = 360 })
    spin:Play()
    MainUI:GetPropertyChangedSignal("Visible"):Connect(function()
        if MainUI.Visible then spin:Play() else spin:Pause() end
    end)

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

local OVERLAY_TRANSPARENCY = 0.45 -- 0 = solid black, 1 = fully transparent

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

-- yesToken is the NAME of the Yes button's color token ("Danger", "AccentPink"...), not a Color3:
-- the color is looked up from Theme every time it is needed (hover/leave), so it stays correct after a theme change.
local function createDialog(name, title, message, yesToken, yesText, noText)
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

    -- soft gradient background: PanelAlt (top) -> Panel (bottom)
    -- (placed on its own Frame, because a UIGradient on a CanvasGroup would also tint the text and buttons inside)
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

    -- gradient border: purple -> the box's accent color
    local BoxStroke = stroke(Box, WHITE, 1.5)
    new("UIGradient", {
        Color = ColorSequence.new(Theme.AccentPurple, Theme[yesToken]),
        Rotation = 45,
    }, BoxStroke)

    -- accent bar at the top
    local Accent = new("Frame", {
        Size = UDim2.new(1, 0, 0, 3),
        BackgroundColor3 = WHITE,
        BorderSizePixel = 0,
        ZIndex = 52,
    }, Box)
    new("UIGradient", {
        Color = ColorSequence.new(Theme.AccentPurple, Theme[yesToken]),
    }, Accent)

    -- title
    label(Box, {
        Size = UDim2.new(1, -32, 0, 20),
        Position = UDim2.fromOffset(16, 16),
        Text = string.upper(title),
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = Theme.Sakura,
        ZIndex = 52,
    })

    -- message
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

    -- divider line
    new("Frame", {
        Size = UDim2.new(1, -32, 0, 1),
        Position = UDim2.new(0, 16, 1, -60),
        BackgroundColor3 = Theme.Border,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ZIndex = 52,
    }, Box)

    -- bgToken / textToken are token NAMES; Theme[...] is looked up again on hover/leave (colors are not captured at creation time)
    local function button(text, pos, bgToken, textToken, outlined)
        local Btn = new("TextButton", {
            Size = UDim2.new(0.5, -22, 0, 34),
            Position = pos,
            BackgroundColor3 = Theme[bgToken],
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Theme[textToken],
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
                tween(Btn, 0.15, { BackgroundColor3 = Theme[bgToken]:Lerp(WHITE, 0.15) })
            end
        end)
        Btn.MouseLeave:Connect(function()
            if outlined then
                tween(Btn, 0.15, { BackgroundColor3 = Theme[bgToken], TextColor3 = Theme[textToken] })
                if S then tween(S, 0.15, { Color = Theme.Border }) end
            else
                tween(Btn, 0.15, { BackgroundColor3 = Theme[bgToken] })
            end
        end)
        return Btn
    end

    local Yes = button(yesText or "Yes", UDim2.new(0, 16, 1, -46), yesToken, "Background")
    local No  = button(noText or "No", UDim2.new(1, -16, 1, -46), "PanelAlt", "Text", true)
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

local CloseDialog = createDialog("ConfirmBox", "Close script", "You want to close this script?", "Danger")
local ResetDialog = createDialog("NotBox2", "Reset UI", "Do you want to reset UI?", "AccentPink")
-- NotBoxDe (Script tab): confirms deleting a function; its message is reassigned every time it opens
local DeleteDialog = createDialog("NotBoxDe", "Delete function", "Do you want to delete this function?", "Danger", "Yes, Delete", "Cancel")

--// ================= OPEN / CLOSE ANIMATION =================
local isOpen = false
local fadeTween
local ScriptDialog -- NotBoxA (Script tab), created in the SCRIPT TAB section
local ThemeAPI     -- Theme API returned by the Settings.lua module (Settings tab); closeUI uses it to close the dropdown list

local function fadeMainUI(time, target, dir)
    if fadeTween then fadeTween:Cancel() end
    fadeTween = tween(MainUI, time, { GroupTransparency = target }, EASE_QUAD, dir)
    return fadeTween
end

-- Forces the visible tab to repaint. Assigned in the TAB SYSTEM section; declared here so openUI and the UI kit can call it.
local repaintContent = function() end

local function openUI()
    isOpen = true
    MainUI.Visible = true
    fadeMainUI(POPUP_TIME, 0, DIR_OUT)
    repaintContent() -- the tab was last drawn while the UI was hidden: make sure it is painted when the UI appears
end

local function closeUI()
    isOpen = false
    if CloseDialog.Box.Visible then CloseDialog.hide() end
    if ResetDialog.Box.Visible then ResetDialog.hide() end
    if DeleteDialog.Box.Visible then DeleteDialog.hide() end
    if ScriptDialog and ScriptDialog.Box.Visible then ScriptDialog.hide() end
    if ThemeAPI and ThemeAPI.isListOpen() then ThemeAPI.hideList() end -- close the Theme list + release the UI lock
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
-- Closing the script = unloading it for good: Auto Execute is turned off too, so the script does not come back after the next teleport
local function unloadUI()
    if Saved.autoExecute == true then
        Saved.autoExecute = false
        saveSettings()
    end
    ScreenGui:Destroy()
end
CloseDialog.Yes.MouseButton1Click:Connect(unloadUI)

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

-- The tab that is shown when the script loads for the first time (must match a CreateTab name below)
local DEFAULT_TAB = "Status & Server"

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

-- Highlight style of the tab list: purple -> pink background fading from left to right + an accent bar on the left
-- (different from Player Info: a bright purple border that runs around)
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

-- Some devices drop the cached render of a CanvasGroup when another overlay (a dropdown list, a collapsible section)
-- appears or disappears, and every function in the panel vanishes until the next touch. Changing GroupTransparency by an
-- invisible amount for a moment makes the engine redraw the group, exactly like that touch does.
do
    local repaintToken = 0
    repaintContent = function()
        task.defer(function()
            local data = activeTab and TabData[activeTab]
            local content = data and data.content
            if not content or not content.Parent or not content.Visible then return end
            if content.GroupTransparency ~= 0 then return end -- a fade is running: it already repaints the group
            repaintToken += 1
            local token = repaintToken
            content.GroupTransparency = 0.004
            task.wait(0.06)
            if token == repaintToken and content.GroupTransparency == 0.004 then
                content.GroupTransparency = 0
            end
        end)
    end
end

-- instant = true: no animation (used for the default tab on first load, so the UI opens with that tab fully shown)
local function selectTab(name, instant)
    local data = TabData[name]
    if not data or activeTab == name then return end
    local previous = activeTab
    activeTab = name
    switchToken += 1
    local token = switchToken

    if instant then
        for tabName, t in pairs(TabData) do
            local selected = tabName == name
            cancelContentTween(t.content)
            t.btn.BackgroundTransparency = 1
            t.btn.TextColor3 = selected and Theme.Sakura or Theme.SubText
            t.pad.PaddingLeft = UDim.new(0, selected and TAB_TEXT_PAD_ACTIVE or TAB_TEXT_PAD)
            t.content.Visible = selected
            if selected then
                t.content.GroupTransparency = 0
                t.contentPad.PaddingTop = UDim.new(0, CONTENT_EDGE)
            end
        end
        TabPill.Position = UDim2.fromOffset(0, data.index * (TAB_HEIGHT + TAB_GAP))
        TabPill.Visible = true
        return
    end

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

    -- The default tab is selected explicitly once every tab exists (see DEFAULT_TAB), not by creation order
    return Content
end

--// ================= THEME: REFRESH STATE COLORS =================
-- Settings.lua (Theme part) calls this AFTER it has changed the Theme table and remapped the colors in the UI tree.
-- Remapping by color value is not enough for state-dependent parts (ToggleKnobOn is excluded from the remap),
-- so the right color is set again for the current state. Placed AFTER TAB SYSTEM because it needs TabData / activeTab.
local function refreshStateColors()
    -- Tabs: selected = Sakura, the rest = SubText
    for tabName, t in pairs(TabData) do
        t.btn.TextColor3 = (tabName == activeTab) and Theme.Sakura or Theme.SubText
    end

    -- Switches (every Switch with a Toggled Attribute): ON = AccentPink + ToggleKnobOn knob, OFF = ToggleTrackOff + Text knob
    -- Text on an accent background (Attribute OnAccent = true): always ToggleKnobOn so it has enough contrast on the accent gradient
    for _, d in ipairs(ScreenGui:GetDescendants()) do
        if d:IsA("TextButton") and type(d:GetAttribute("Toggled")) == "boolean" then
            local on = d:GetAttribute("Toggled")
            d.BackgroundColor3 = on and Theme.AccentPink or Theme.ToggleTrackOff
            local knob = d:FindFirstChildOfClass("Frame")
            if knob then knob.BackgroundColor3 = on and Theme.ToggleKnobOn or Theme.Text end
        elseif d:GetAttribute("OnAccent") == true and (d:IsA("TextLabel") or d:IsA("TextButton")) then
            d.TextColor3 = Theme.ToggleKnobOn
        end
    end

    -- Resize mode / Maximize: icons + window border
    drawIcon(ResizeIcon, "resize", resizeMode and Theme.AccentPink or Theme.Text, Theme.PanelAlt)
    drawIcon(MaximizeIcon, isMaximized and "restore" or "maximize", Theme.Text, Theme.PanelAlt)
    MainUIStroke.Color = resizeMode and Theme.AccentPink or Theme.Border
end

--// ================= FUNCTION ELEMENT BUILDERS =================
-- opts.initial = true: created already ON (no event is fired; the module applies its own initial state).
-- Returns: Switch, setState, api
--   setState(value, silent): silent = true -> only updates the visuals + the "Toggled" Attribute, and does not call the functions
--                            registered through api.onChanged (raw GetAttributeChangedSignal listeners still receive it).
--   api.get()          -> current state
--   api.onChanged(fn)  -> fn(on) on every state change; returns { Disconnect }
-- The old call style CreateToggleOption(parent, title, height) with Switch, setState still works exactly as before.
local function CreateToggleOption(parent, title, height, opts)
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
    local listeners = {} -- functions registered through api.onChanged
    Switch:SetAttribute("Toggled", false)

    -- Paint the current state; animated = false -> set directly (used for the initial state)
    local function paint(animated)
        local trackColor = state and Theme.AccentPink or Theme.ToggleTrackOff
        local knobProps = {
            Position = state and UDim2.new(1, -(pxH - 2), 0, 2) or UDim2.fromOffset(2, 2),
            BackgroundColor3 = state and Theme.ToggleKnobOn or Theme.Text,
        }
        SwitchGradient.Enabled = state
        if animated then
            tween(Switch, 0.18, { BackgroundColor3 = trackColor })
            tween(Knob, 0.18, knobProps)
        else
            Switch.BackgroundColor3 = trackColor
            for k, v in pairs(knobProps) do Knob[k] = v end
        end
    end

    local function setState(value, silent)
        value = value and true or false
        if state == value then return end
        state = value
        Switch:SetAttribute("Toggled", state)
        paint(true)
        if not silent then
            for _, fn in ipairs(listeners) do task.spawn(fn, state) end
        end
    end

    if opts and opts.initial then
        state = true
        Switch:SetAttribute("Toggled", true)
        paint(false)
    end

    Switch.MouseButton1Click:Connect(function()
        if uiLocked then return end
        setState(not state)
    end)

    local api = {
        get = function() return state end,
        onChanged = function(fn)
            listeners[#listeners + 1] = fn
            return {
                Disconnect = function()
                    for i, f in ipairs(listeners) do
                        if f == fn then table.remove(listeners, i) break end
                    end
                end,
            }
        end,
    }
    return Switch, setState, api
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

-- holdTime: seconds the feedback text stays (default 1.2); math.huge = keep until the next flash. color: overrides the text color.
-- Only the NEWEST flash is reverted, so an old flash never wipes the text of a newer one.
local function flashButtonFeedback(Btn, defaultText, feedbackText, isError, holdTime, color)
    local token = (Btn:GetAttribute("FlashToken") or 0) + 1
    Btn:SetAttribute("FlashToken", token)
    Btn.Text = feedbackText
    Btn.TextColor3 = color or (isError and Theme.Danger or Theme.Sakura)
    if holdTime == math.huge then return end
    task.delay(holdTime or 1.2, function()
        if Btn:GetAttribute("FlashToken") ~= token then return end
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
        local released = false
        local function done()
            if released then return end
            released = true
            task.delay(1.2, function() busy = false end)
        end
        -- If fn errors before calling done(), the lock must still be released, otherwise the button stays stuck busy for the rest of the session
        local ok, err = pcall(fn, done)
        if not ok then
            warn("[Elysera] " .. tostring(err))
            done()
        end
    end
end

--// ================= SHARED UI KIT (ctx.UI) =================
-- Identical UI pieces that used to be duplicated in Local.lua / FPS.lua / Script.lua now live in one place;
-- modules get them through ctx.UI. The "winbox" dropdown of each tab is kept separate because every tab's look currently differs.
local UI = {}
do
    -- Default TextLabel of the UI kit: Gotham font, Theme.Text color, left-aligned
    local function uiLabel(parent, props)
        props.BackgroundTransparency = 1
        props.Font = props.Font or Enum.Font.Gotham
        props.TextColor3 = props.TextColor3 or Theme.Text
        props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
        return new("TextLabel", props, parent)
    end

    -- A UIStroke on text outlines the TEXT by default (Contextual); these strokes are meant for frames, so Border mode is forced
    function UI.BorderStroke(inst, color, thickness)
        local s = stroke(inst, color, thickness)
        s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        return s
    end

    -- Write a string to the clipboard with the executor's function (each executor names it differently). Returns true if it worked
    function UI.CopyText(text)
        local fn = (typeof(setclipboard) == "function" and setclipboard)
            or (typeof(toclipboard) == "function" and toclipboard)
            or (typeof(set_clipboard) == "function" and set_clipboard)
            or (typeof(Clipboard) == "table" and typeof(Clipboard.set) == "function" and Clipboard.set)
            or (typeof(syn) == "table" and typeof(syn.write_clipboard) == "function" and syn.write_clipboard)
        if not fn then return false end
        return (pcall(fn, text))
    end

    -- Down arrow drawn from two bars rotated ±45° (rotate the Holder: 0 = down, -90 = right)
    -- Returns: Holder, setColor(color)
    function UI.CreateChevron(parent, props, color, len, thick)
        len, thick = len or 8, thick or 2
        props.BackgroundTransparency = 1
        local Holder = new("Frame", props, parent)

        local dx = len * 0.3536 -- half the horizontal width of a bar rotated by 45 degrees
        local bars = {}
        for i, rot in ipairs({ 45, -45 }) do
            bars[i] = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, (i == 1) and -dx or dx, 0.5, 0),
                Size = UDim2.fromOffset(len, thick),
                Rotation = rot,
                BackgroundColor3 = color or Theme.SubText,
                BorderSizePixel = 0,
            }, Holder)
            corner(bars[i], thick / 2)
        end

        return Holder, function(c)
            for _, b in ipairs(bars) do b.BackgroundColor3 = c end
        end
    end

    -- Collapsible group: title + subtitle line, accent bar on the left, an "N on" pill when a switch inside is on.
    -- opts: { subtitle = "what is inside", collapsed = true }
    -- Returns api: { Body, trackSwitch(handle), track(switch) }
    --   trackSwitch(handle): a BindToggle handle (Local.lua), counted through handle.onChanged
    --   track(switch):       a Switch from CreateToggleOption (FPS.lua), counted through the "Toggled" Attribute
    function UI.CreateSection(parent, title, order, opts)
        opts = opts or {}
        local open = not opts.collapsed
        local activeCount = 0
        local api = {}

        local Root = new("Frame", {
            Name = "Section_" .. title,
            LayoutOrder = order,
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
        }, parent)
        list(Root, 6)

        local Header = new("TextButton", {
            Name = "Header",
            LayoutOrder = 0,
            Size = UDim2.new(1, 0, 0, 52),
            Text = "",
            BackgroundColor3 = Theme.Header,
            BorderSizePixel = 0,
            AutoButtonColor = false,
        }, Root)
        corner(Header, 8)
        UI.BorderStroke(Header)

        -- Accent bar on the left: pink when anything in the group is on
        local Bar = new("Frame", {
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 8, 0.5, 0),
            Size = UDim2.fromOffset(3, 26),
            BackgroundColor3 = Theme.Border,
            BorderSizePixel = 0,
        }, Header)
        corner(Bar, 2)

        uiLabel(Header, {
            Position = UDim2.fromOffset(20, 8),
            Size = UDim2.new(1, -118, 0, 20),
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = title,
        })
        uiLabel(Header, {
            Position = UDim2.fromOffset(20, 28),
            Size = UDim2.new(1, -118, 0, 16),
            TextSize = 11,
            TextColor3 = Theme.SubText,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Text = opts.subtitle or "",
        })

        -- "N on" pill
        local Pill = new("Frame", {
            Name = "ActivePill",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -40, 0.5, 0),
            Size = UDim2.fromOffset(46, 20),
            BackgroundColor3 = WHITE, -- the gradient multiplies the background color, so it stays white
            BorderSizePixel = 0,
            Visible = false,
        }, Header)
        corner(Pill, 10)
        new("UIGradient", { Color = ColorSequence.new(Theme.AccentPurple, Theme.AccentPink) }, Pill)
        local PillText = uiLabel(Pill, {
            Size = UDim2.fromScale(1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 11,
            TextColor3 = Theme.ToggleKnobOn,
            TextXAlignment = Enum.TextXAlignment.Center,
            Text = "",
        })
        PillText:SetAttribute("OnAccent", true) -- refreshStateColors keeps the text readable on every theme

        local Chevron, setChevronColor = UI.CreateChevron(Header, {
            Name = "Chevron",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(1, -24, 0.5, 0),
            Size = UDim2.fromOffset(20, 20),
        }, Theme.SubText, 10, 2)

        local Body = new("Frame", {
            Name = "Body",
            LayoutOrder = 1,
            BackgroundTransparency = 1,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(1, 0, 0, 0),
        }, Root)
        list(Body, 6)

        local function render(animate)
            Body.Visible = open
            local rot = open and 0 or -90
            local barColor = (activeCount > 0) and Theme.AccentPink or Theme.Border
            if animate then
                tween(Chevron, 0.15, { Rotation = rot })
                tween(Bar, 0.15, { BackgroundColor3 = barColor })
            else
                Chevron.Rotation = rot
                Bar.BackgroundColor3 = barColor
            end
            setChevronColor(open and Theme.Text or Theme.SubText)
            Pill.Visible = activeCount > 0
            PillText.Text = activeCount .. " on"
        end

        Header.MouseEnter:Connect(function()
            tween(Header, 0.12, { BackgroundColor3 = Theme.Header:Lerp(Theme.Border, 0.35) })
        end)
        Header.MouseLeave:Connect(function()
            tween(Header, 0.12, { BackgroundColor3 = Theme.Header })
        end)
        Header.Activated:Connect(function()
            if uiLocked then return end
            open = not open
            render(true)
            repaintContent() -- the tab just changed size: make sure its panel is repainted
        end)

        -- Attach a BindToggle handle so the title counts how many features are on
        function api.trackSwitch(handle)
            handle.onChanged(function(on)
                activeCount = math.max(0, activeCount + (on and 1 or -1))
                render(true)
            end)
        end

        -- Count every switch of the group so the title shows how many are on
        function api.track(switch)
            local was = switch:GetAttribute("Toggled") == true
            if was then
                activeCount += 1
                render(false)
            end
            switch:GetAttributeChangedSignal("Toggled"):Connect(function()
                local on = switch:GetAttribute("Toggled") == true
                if on == was then return end -- e.g. an Attribute just created with the value false: not a state change
                was = on
                activeCount = math.max(0, activeCount + (on and 1 or -1))
                render(true)
            end)
        end

        render(false)
        api.Body = Body
        return api
    end
end

--// ================= REMOTE MODULE LOADER =================
-- The modules (Status_Server.lua, Local.lua, Script.lua, FPS.lua, Settings.lua) are downloaded from GitHub (raw)
-- and run with loadstring; they are no longer read from the executor's workspace folder.
-- The .json files (Elysera_Settings.json, ...) live in the workspace/Elysera/ folder (see "Data folder" above).
--
-- Loader resilience:
--   * MODULE_REF selects a branch / tag / commit SHA. It follows the main branch by default; to pin a version, set it to
--     "refs/tags/<tag>" or a 40-character commit SHA -> a broken commit pushed to main does not affect users.
--   * A module that initializes without errors is saved to Elysera/cache_<file name>. Next time, if the download fails, or the
--     new copy has a syntax error / fails to initialize, the loader uses that saved copy.
--   * With no fallback copy, the tab shows an error card with a Retry button instead of staying empty.
-- All loader helpers sit inside the do...end block below (saves locals of the main chunk, limit 200);
-- only mountModule is left outside.
-- Loader information handed to modules through ctx.Loader:
--   ref, files, bootUrl / bootCode (Auto Execute uses them to reload Elysera after a teleport),
--   sources[file] = "web" | "cache" | "error" (shown by Diagnostics in the Settings tab)
local Loader = { sources = {} }
local mountModule
do
    local MODULE_BASE    = "https://raw.githubusercontent.com/MinzTogether/Universal-Script/"
    local MODULE_REF     = "refs/heads/main"
    local MODULE_FILES   = { "Status_Server.lua", "Local.lua", "Script.lua", "FPS.lua", "Settings.lua" }
    local MODULE_TIMEOUT = 20 -- maximum total seconds to wait for all modules to download
    -- The main file (this very file) in the same repo + ref. Auto Execute reloads it after every teleport:
    -- if you host the file somewhere else, fix BOOT_FILE (or Loader.bootCode below) accordingly.
    local BOOT_FILE      = "MainWeb.lua"

    local MODULE_URLS = {}
    for _, file in ipairs(MODULE_FILES) do
        MODULE_URLS[file] = MODULE_BASE .. MODULE_REF .. "/" .. file
    end

    Loader.ref = MODULE_REF
    Loader.files = MODULE_FILES
    Loader.bootUrl = MODULE_BASE .. MODULE_REF .. "/" .. BOOT_FILE
    Loader.bootCode = ("loadstring(game:HttpGet(%q))()"):format(Loader.bootUrl)

    -- Download the content of a URL: prefer game:HttpGet, fall back to request / http_request / syn.request
    local function httpGet(url)
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and type(body) == "string" and body ~= "" then
            if body:match("^%s*404: Not Found") then error("404 Not Found", 0) end
            return body
        end
        local reason = ok and "empty response" or tostring(body)

        local req = (typeof(request) == "function" and request)
            or (typeof(http_request) == "function" and http_request)
            or (typeof(syn) == "table" and typeof(syn.request) == "function" and syn.request)
        if req then
            local ok2, res = pcall(req, { Url = url, Method = "GET" })
            if ok2 and type(res) == "table" then
                if res.StatusCode == 200 and type(res.Body) == "string" and res.Body ~= "" then
                    return res.Body
                end
                reason = "HTTP " .. tostring(res.StatusCode)
            else
                reason = tostring(res)
            end
        end
        error(reason, 0)
    end

    -- Download all 5 modules at the same time right from the start; running them (init) still follows the original order in the blocks below
    local moduleJobs = {}
    local moduleDeadline = os.clock() + MODULE_TIMEOUT
    local function startDownload(file)
        local job = { done = false }
        moduleJobs[file] = job
        task.spawn(function()
            job.ok, job.result = pcall(httpGet, MODULE_URLS[file])
            job.done = true
        end)
        return job
    end
    for _, file in ipairs(MODULE_FILES) do startDownload(file) end

    -- Wait until one module has downloaded, then return its source. deadline: latest os.clock() time (default: the shared deadline set at startup)
    local function readModule(file, deadline)
        local job = assert(moduleJobs[file], "no URL declared for module: " .. file)
        while not job.done do
            if os.clock() > (deadline or moduleDeadline) then
                error("timed out while downloading " .. MODULE_URLS[file], 0)
            end
            task.wait()
        end
        if not job.ok then
            error("download failed " .. MODULE_URLS[file] .. " (" .. tostring(job.result) .. ")", 0)
        end
        return job.result
    end

    -- Saved copy of the most recent good run: Elysera/cache_<file name> (skipped when the executor has no file system)
    local function cacheName(file) return dataPath("cache_" .. file) end

    local function readCache(file)
        if not canFS then return nil end
        local ok, src = pcall(function()
            local path = cacheName(file)
            if isfile(path) then return readfile(path) end
        end)
        if ok and type(src) == "string" and src ~= "" then return src end
        return nil
    end

    local function writeCache(file, src)
        if not canFS then return end
        pcall(writefile, cacheName(file), src)
    end

    -- Compile the module source and run the top of the file to get the init function. Returns init, or nil + the reason
    local function compileModule(file, src)
        local chunk, err = loadstring(src, "=" .. file)
        if not chunk then return nil, "syntax error: " .. tostring(err) end
        local ok, init = pcall(chunk)
        if not ok then return nil, "error while loading the file: " .. tostring(init) end
        if type(init) ~= "function" then return nil, "the module did not return an init function" end
        return init
    end

    -- Remove the half-built module UI from the tab (keep the tab's UIPadding / UIListLayout)
    local function clearTab(tab)
        for _, child in ipairs(tab:GetChildren()) do
            if not (child:IsA("UIPadding") or child:IsA("UIListLayout")) then
                child:Destroy()
            end
        end
    end

    -- Error card in the tab: the reason + a Retry button (download again and rebuild the tab) + a Copy error button
    local function showModuleError(tab, file, message, retry)
        local text = tostring(message)
        if #text > 280 then text = text:sub(1, 277) .. "..." end

        local Card = CreateCard(tab, "ModuleError_" .. file, 12, 14, 14)
        label(Card, {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 20),
            Text = "Failed to load " .. file,
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Danger,
        })
        label(Card, {
            LayoutOrder = 2,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Text = text,
            Font = Enum.Font.Gotham,
            TextSize = 13,
            TextWrapped = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextColor3 = Theme.SubText,
        })

        local Row = new("Frame", {
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
        }, Card)
        local RetryBtn = CreateStyledButton(Row, "Retry", 80)
        local CopyBtn = CreateStyledButton(Row, "Copy error", 100)
        CopyBtn.Position = UDim2.new(1, -88, 0.5, 0)

        CopyBtn.MouseButton1Click:Connect(function()
            if uiLocked then return end
            local ok = UI.CopyText(file .. ": " .. tostring(message))
            flashButtonFeedback(CopyBtn, "Copy error", ok and "Copied" or "Failed", not ok)
        end)

        local retrying = false
        RetryBtn.MouseButton1Click:Connect(function()
            if uiLocked or retrying then return end
            retrying = true
            flashButtonFeedback(RetryBtn, "Retry", "Loading...", false, math.huge)
            task.spawn(retry)
        end)
    end

    -- Build a tab from a module. build(init) runs the tab's setup and throws an error if it breaks.
    -- Order of attempts: fresh download -> cached copy of the most recent good run -> error card (with a Retry button).
    function mountModule(file, tab, build, isRetry)
        if isRetry then startDownload(file) end
        local deadline = isRetry and (os.clock() + MODULE_TIMEOUT) or nil
        local problems = {}
        local function note(msg) problems[#problems + 1] = msg end

        local fresh
        local okFetch, got = pcall(readModule, file, deadline)
        if okFetch then fresh = got else note(tostring(got)) end

        local function attempt(src, from)
            local init, why = compileModule(file, src)
            if not init then note(from .. ": " .. why) return false end
            local okBuild, berr = pcall(build, init)
            if not okBuild then note(from .. ": error during initialization: " .. tostring(berr)) return false end
            return true
        end

        if fresh and attempt(fresh, "fresh download") then
            if readCache(file) ~= fresh then writeCache(file, fresh) end -- only a copy that ran well is saved
            Loader.sources[file] = "web"
            return true
        end

        local cached = readCache(file)
        if cached and cached ~= fresh then
            clearTab(tab) -- discard what the new copy half-built
            if attempt(cached, "cached copy") then
                warn(("[Elysera] %s: using the saved copy of the most recent good run (%s)"):format(file, problems[1] or "?"))
                Loader.sources[file] = "cache"
                return true
            end
        end

        clearTab(tab)
        local message = table.concat(problems, " | ")
        warn("[Elysera] Could not load " .. file .. ": " .. message)
        Loader.sources[file] = "error"
        showModuleError(tab, file, message, function()
            clearTab(tab)
            mountModule(file, tab, build, true)
        end)
        return false
    end
end

--// ================= AUTO EXECUTE (reload Elysera after a teleport) =================
-- queue_on_teleport queues a piece of code that runs on the next server after a teleport (Server Hop, Rejoin, Spam Join...).
-- That code re-reads the settings file and only loads Elysera while the switch is still ON, so turning the switch off takes effect
-- even when the code is already queued. Every time Elysera finishes loading on a new server it queues itself again (the settings file
-- is needed to remember the switch). The mechanism lives in the core so it still works even when the Settings tab fails to load; Settings.lua only builds the switch.
local AutoExec = {}
do
    local queued = false -- queue only once per session (avoids duplicating the code when toggled on/off many times)

    local function queueFn()
        return (typeof(queue_on_teleport) == "function" and queue_on_teleport)
            or (typeof(queueonteleport) == "function" and queueonteleport)
            or (typeof(syn) == "table" and typeof(syn.queue_on_teleport) == "function" and syn.queue_on_teleport)
            or (typeof(fluxus) == "table" and typeof(fluxus.queue_on_teleport) == "function" and fluxus.queue_on_teleport)
            or nil
    end

    -- nil when usable, otherwise a short reason
    function AutoExec.reason()
        if not queueFn() then return "no queue_on_teleport" end
        if not canFS then return "needs file access" end
        if type(Loader.bootCode) ~= "string" then return "no boot script" end
        return nil
    end

    function AutoExec.supported() return AutoExec.reason() == nil end
    function AutoExec.isOn() return Saved.autoExecute == true end

    -- Code that runs on the new server. __ElyseraBoot prevents running twice on the same server (executors keep the queue for a long time)
    local function payload()
        return ([[
if not game:IsLoaded() then game.Loaded:Wait() end
local env = getgenv and getgenv() or _G
if env.__ElyseraBoot == game.JobId then return end
local ok, data = pcall(function()
    return game:GetService("HttpService"):JSONDecode(readfile(%q))
end)
if ok and type(data) == "table" and data.autoExecute == true then
    env.__ElyseraBoot = game.JobId
    local okRun, err = pcall(function() %s end)
    if not okRun then warn("[Elysera] Auto Execute failed: " .. tostring(err)) end
end]]):format(dataPath(SAVE_FILE), Loader.bootCode)
    end

    function AutoExec.queue()
        if queued then return true end
        local fn = queueFn()
        if not fn or AutoExec.reason() then return false end
        queued = (pcall(fn, payload()))
        return queued
    end

    -- Turn on/off and save. Returns true, or false + the reason when the executor does not support it
    function AutoExec.set(on)
        on = on and true or false
        if on then
            local why = AutoExec.reason()
            if why then return false, why end
        end
        Saved.autoExecute = on
        saveSettings()
        if on then AutoExec.queue() end
        return true
    end
end

--// ================= TABS =================
local StatusServerTab = CreateTab("Status & Server")
local LocalTab        = CreateTab("Local")
local FPSTab          = CreateTab("FPS")
local ScriptTab       = CreateTab("Script")
local SettingsTab     = CreateTab("Settings")

-- First load: open on the default tab ("Status & Server") right away, before any module is mounted, so it is the
-- selected tab whatever order the modules finish loading in (and even when a module fails to load)
selectTab(DEFAULT_TAB, true)

--// ================= SHARED CTX FOR MODULES =================
-- One shared table replaces 5 hand-assembled tables: every module receives its own ctx (only Tab is added) that points back to this table through __index,
-- so every module gets every helper and never has to rewrite what ctx is missing.
local makeCtx
do
    local Shared = {
        Theme = Theme, ScreenGui = ScreenGui, GuiRoot = GuiRoot, CoreGui = CoreGui, MainUI = MainUI,
        LocalPlayer = LocalPlayer, Players = Players, RunService = RunService, UserInputService = UserInputService,
        Workspace = Workspace, HttpService = HttpService, TeleportService = TeleportService,
        UI_NAME = UI_NAME, canFS = canFS, dataPath = dataPath, Saved = Saved, saveSettings = saveSettings,
        WHITE = WHITE, CENTER = CENTER, ANCHOR_CENTER = ANCHOR_CENTER,
        EASE_QUAD = EASE_QUAD, EASE_BACK = EASE_BACK, DIR_IN = DIR_IN, DIR_OUT = DIR_OUT,
        BUBBLE_IN_TIME = BUBBLE_IN_TIME, BUBBLE_OUT_TIME = BUBBLE_OUT_TIME,
        FADE_IN_TIME = FADE_IN_TIME, FADE_OUT_TIME = FADE_OUT_TIME, CONTENT_EDGE = CONTENT_EDGE,
        new = new, corner = corner, stroke = stroke, padding = padding, list = list, label = label,
        tween = tween, pressScale = pressScale, drawIcon = drawIcon, setOverlay = setOverlay,
        FunctionScroll = FunctionScroll, DeleteDialog = DeleteDialog, fadeMainUI = fadeMainUI,
        refreshStateColors = refreshStateColors, settleColorTweens = settleColorTweens,
        CreateCard = CreateCard, CreateInfoRow = CreateInfoRow, CreateStyledButton = CreateStyledButton,
        CreateToggleOption = CreateToggleOption, flashButtonFeedback = flashButtonFeedback,
        flashStrokeError = flashStrokeError, bindBoxFocus = bindBoxFocus, guarded = guarded,
        UI = UI, Loader = Loader, AutoExecute = AutoExec, repaintContent = repaintContent,
        requestClose = function() -- opens the "Close script" dialog (same flow as the close button in the top bar)
            if uiLocked then return end
            CloseDialog.show()
        end,
        isOpen = function() return isOpen end,
        isLocked = function() return uiLocked end,
        setLocked = function(v) uiLocked = v end,
    }

    function makeCtx(tab)
        return setmetatable({ Tab = tab }, { __index = Shared })
    end
end

local Elysera -- public API table, assigned in the EXPOSED API section (Settings' Retry needs to update Elysera.Themes)

--// ================= SCRIPT TAB =================
-- The tab's code lives in its own file, loaded from GitHub: Script.lua
-- The module returns ScriptDialog (declared up in the OPEN / CLOSE section so closeUI can use it)
mountModule("Script.lua", ScriptTab, function(init)
    ScriptDialog = init(makeCtx(ScriptTab))
end)

--// ================= STATUS & SERVER TAB =================
-- The tab's code lives in its own file, loaded from GitHub: Status_Server.lua
mountModule("Status_Server.lua", StatusServerTab, function(init)
    init(makeCtx(StatusServerTab))
end)

--// ================= LOCAL TAB =================
-- The tab's code lives in its own file, loaded from GitHub: Local.lua
mountModule("Local.lua", LocalTab, function(init)
    init(makeCtx(LocalTab))
end)

--// ================= FPS TAB =================
-- The tab's code lives in its own file, loaded from GitHub: FPS.lua
mountModule("FPS.lua", FPSTab, function(init)
    init(makeCtx(FPSTab))
end)

--// ================= SETTINGS TAB =================
-- The tab's code lives in its own file, loaded from GitHub: Settings.lua (Anti Chat, Auto Execute, Theme, Diagnostics)
-- Loaded LAST so the first theme application (the saved theme) also covers the tabs above.
-- If it cannot be downloaded or fails -> the Settings tab shows an error card (Retry) and the UI keeps running with the default theme.
-- The module returns the Theme API (ThemeAPI is declared up in the OPEN / CLOSE section so closeUI can use it)
mountModule("Settings.lua", SettingsTab, function(init)
    ThemeAPI = init(makeCtx(SettingsTab))
    if Elysera then Elysera.Themes = ThemeAPI.Themes end -- only happens on Retry (during the first load Elysera does not exist yet)
end)

-- Auto Execute was on last time: queue it right away (even when the Settings tab failed to load)
if AutoExec.isOn() and AutoExec.supported() then AutoExec.queue() end

--// ================= EXPOSED API =================
Elysera = {
    ScreenGui = ScreenGui,
    Theme = Theme,
    Open = openUI,
    Close = closeUI,
    CreateTab = CreateTab,
    CreateToggleOption = CreateToggleOption,
    CreateSectionLabel = CreateSectionLabel,
    SelectTab = selectTab,
    Unload = unloadUI,       -- unload Elysera for good (same as the close script button) and turn Auto Execute off
    AutoExecute = AutoExec,  -- supported() / isOn() / set(on) / reason()

    -- Theme (provided by Settings.lua; if the module cannot be loaded, SetTheme returns false)
    Themes = ThemeAPI and ThemeAPI.Themes or {},
    SetTheme = function(id)
        if not ThemeAPI then return false, "Settings.lua has not been loaded" end
        return ThemeAPI.SetTheme(id)
    end,
    GetTheme = function()
        if not ThemeAPI then return "sakura", "Elysera Sakura" end
        return ThemeAPI.GetTheme()
    end,
    OnThemeChanged = function(fn)
        if not ThemeAPI then return function() end end
        return ThemeAPI.OnThemeChanged(fn)
    end,
}

--// ================= INITIAL STATE =================
openUI()

return Elysera
