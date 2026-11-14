local CD = CLASSDATA
local infoCache = {}
local STATE = setmetatable({}, { __mode = "k" })
local InstanceMT = { __type = "Instance" }
local ClassMethods, ClassGet, ClassSet, ClassInit = {}, {}, {}, {}
local VIEWPORT = Vector2.new(1280, 720)
Harness.STATE = STATE
Harness.viewport = VIEWPORT

local function classInfo(cls)
    local info = infoCache[cls]
    if info then return info end
    if not CD[cls] then return nil end
    info = { name = cls, isA = {}, props = {}, events = {}, methods = {}, chain = {} }
    local c = cls
    while c do
        local d = CD[c]
        if not d then break end
        info.isA[c] = true
        table.insert(info.chain, c)
        for k, v in pairs(d.r) do if info.props[k] == nil then info.props[k] = v end end
        for _, e in ipairs(d.e) do info.events[e] = true end
        for _, m in ipairs(d.m) do info.methods[m] = true end
        c = d.p
    end
    infoCache[cls] = info
    return info
end

local DEFAULT_NAMED = {
    Visible = true, Enabled = true, Interactable = true, ScrollingEnabled = true, ZIndex = 1, Scale = 1, Thickness = 1,
    TextSize = 14, ScrollBarThickness = 12, BorderSizePixel = 1, MaxTextSize = 100, MinTextSize = 1, LineHeight = 1,
    FieldOfView = 70, ClearTextOnFocus = true, ResetOnSpawn = true, Archivable = true, Health = 100, MaxHealth = 100,
    WalkSpeed = 16, JumpPower = 50, JumpHeight = 7.2, UseJumpPower = true, HipHeight = 2, CursorPosition = -1,
    SelectionStart = -1, Volume = 0.5, Brightness = 2, MaxVisibleGraphemes = -1, RootPriority = 0, Gravity = 196.2,
    FallenPartsDestroyHeight = -500, MaxPlayers = 12, CanCollide = true, Mass = 1, MaxForce = 0, MaxCanvasSize = 0,
    Ambient = Color3.fromRGB(70, 70, 70), OutdoorAmbient = Color3.fromRGB(70, 70, 70), ClockTime = 14, ExposureCompensation = 0,
    FogEnd = 100000, FogStart = 0, GlobalShadows = true, ShadowSoftness = 0.2, Size = nil,
    TextColor3 = Color3.new(0, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), BorderColor3 = Color3.new(0, 0, 0),
    PlaceholderColor3 = Color3.fromRGB(178, 178, 178), CanvasSize = UDim2.new(0, 0, 2, 0),
    CameraMaxZoomDistance = 128, CameraMinZoomDistance = 0.5, MasterVolume = 1, SavedQualityLevel = 0, ViewportSize = Vector2.new(1280, 720),
    Size3 = nil, DisplayOrder = 0, Offset = 0, SoundId = "", Looped = false, PlaybackSpeed = 1, TimePosition = 0,
    HealthDisplayDistance = 100, NameDisplayDistance = 100, DisplayDistanceType = nil,
}

local ENUM_DEFAULT = {
    AutomaticSize = "None", SortOrder = "LayoutOrder", FillDirection = "Vertical", HorizontalAlignment = "Left",
    VerticalAlignment = "Top", TextXAlignment = "Center", TextYAlignment = "Center", ScrollingDirection = "XY",
    ZIndexBehavior = "Sibling", Font = "SourceSans", ApplyStrokeMode = "Contextual", SizeConstraint = "RelativeXY",
    MouseBehavior = "Default", CameraType = "Custom", Material = "Plastic", AutomaticCanvasSize = "None",
    ScrollBarInset = "None", TextTruncate = "None", TextDirection = "Auto", BorderMode = "Outline", Style = "Custom",
    VerticalScrollBarPosition = "Right", Technology = "ShadowMap", RenderFidelity = "Automatic", QualityLevel = "Automatic",
    PlaybackState = "Begin", RunContext = "Legacy", LineJoinMode = "Round", StartCorner = "TopLeft", SelectionBehaviorUp = "Escape",
    ResamplerMode = "Default", ScaleType = "Stretch", GuiState = "Idle", InputSink = "Sink", Limits = nil,
}

local function enumDefault(propName, enumName)
    local pref = ENUM_DEFAULT[propName]
    local et = Enum[enumName]
    if pref and et._items[pref] then return et._items[pref] end
    return et._list[1]
end

local function defaultFor(st, key, ptype)
    local named = DEFAULT_NAMED[key]
    if named ~= nil then return named end
    local t = ptype:gsub("%?$", "")
    if t == "boolean" then return false end
    if t == "number" then return 0 end
    if t == "string" then return "" end
    if t == "Color3" then return Color3.new(1, 1, 1) end
    if t == "Vector2" then return Vector2.new(0, 0) end
    if t == "Vector3" then return Vector3.new(0, 0, 0) end
    if t == "UDim2" then return UDim2.new(0, 0, 0, 0) end
    if t == "UDim" then return UDim.new(0, 0) end
    if t == "CFrame" then return CFrame.new() end
    if #t > 4 and t:sub(1, 4) == "Enum" and ENUMDATA[t:sub(5)] then return enumDefault(key, t:sub(5)) end
    return nil
end

local function fullName(inst)
    local parts = {}
    local cur = inst
    while cur do
        local st = STATE[cur]
        if st.cls == "DataModel" then break end
        table.insert(parts, 1, st.name)
        cur = st.parent
    end
    return table.concat(parts, ".")
end

local function getSignal(inst, key)
    local st = STATE[inst]
    local sig = st.signals[key]
    if not sig then
        sig = Harness.newSignal(key)
        st.signals[key] = sig
    end
    return sig
end

local function notifyProp(inst, key)
    local st = STATE[inst]
    local s = st.signals["prop:" .. key]
    if s then s:_fire() end
    local ch = st.signals.Changed
    if ch then ch:_fire(key) end
end

local function typeOk(ptype, value)
    local optional = ptype:sub(-1) == "?"
    local t = optional and ptype:sub(1, -2) or ptype
    if t == "any" then return true end
    if value == nil then
        if optional then return true end
        if CD[t] then return true end
        return false
    end
    local vt = typeof(value)
    if t == "boolean" or t == "number" or t == "string" then return vt == t end
    if t == "Color3" or t == "UDim2" or t == "UDim" or t == "Vector2" or t == "Vector3" or t == "CFrame" or t == "ColorSequence" or t == "NumberSequence" or t == "NumberRange" then
        return vt == t
    end
    if #t > 4 and t:sub(1, 4) == "Enum" and ENUMDATA[t:sub(5)] then
        return vt == "EnumItem" and value.EnumType.Name == t:sub(5)
    end
    if CD[t] then
        return vt == "Instance" and STATE[value].info.isA[t] == true
    end
    return true
end

local function describeType(ptype)
    local t = ptype:gsub("%?$", "")
    if t:sub(1, 4) == "Enum" and #t > 4 then return "Enum." .. t:sub(5) end
    return t
end

local function descendants(inst, out)
    out = out or {}
    for _, c in ipairs(STATE[inst].children) do
        table.insert(out, c)
        descendants(c, out)
    end
    return out
end

local function isAncestorOf(a, b)
    local cur = STATE[b].parent
    while cur do
        if cur == a then return true end
        cur = STATE[cur].parent
    end
    return false
end

local function ancestorsOf(inst)
    local out = {}
    local cur = STATE[inst].parent
    while cur do
        table.insert(out, cur)
        cur = STATE[cur].parent
    end
    return out
end

local function setParent(inst, newParent)
    local st = STATE[inst]
    if st.destroyed then error("The Parent property of " .. st.name .. " is locked because the current thread cannot access it", 3) end
    if newParent ~= nil and typeof(newParent) ~= "Instance" then
        error("Unable to assign property Parent. Object expected, got " .. typeof(newParent), 3)
    end
    if newParent == st.parent then return end
    if newParent ~= nil and (newParent == inst or isAncestorOf(inst, newParent)) then
        error("Attempt to set " .. fullName(inst) .. " as its own ancestor", 3)
    end
    local old = st.parent
    if old then
        local ost = STATE[old]
        for i, c in ipairs(ost.children) do
            if c == inst then table.remove(ost.children, i) break end
        end
        local subtree = { inst }
        descendants(inst, subtree)
        if ost.signals.ChildRemoved then ost.signals.ChildRemoved:_fire(inst) end
        for _, a in ipairs({ old, table.unpack(ancestorsOf(old)) }) do
            local s = STATE[a].signals.DescendantRemoving
            if s then for _, d in ipairs(subtree) do s:_fire(d) end end
        end
    end
    st.parent = newParent
    local subtree = { inst }
    descendants(inst, subtree)
    if newParent then
        local pst = STATE[newParent]
        table.insert(pst.children, inst)
        if pst.signals.ChildAdded then pst.signals.ChildAdded:_fire(inst) end
        for _, a in ipairs({ newParent, table.unpack(ancestorsOf(newParent)) }) do
            local s = STATE[a].signals.DescendantAdded
            if s then for _, d in ipairs(subtree) do s:_fire(d) end end
        end
    end
    for _, d in ipairs(subtree) do
        local s = STATE[d].signals.AncestryChanged
        if s then s:_fire(inst, newParent) end
    end
    notifyProp(inst, "Parent")
end

local function createInstance(cls)
    local info = classInfo(cls)
    if not info then error('Unable to create an Instance of type "' .. tostring(cls) .. '"', 3) end
    local inst = setmetatable({}, InstanceMT)
    STATE[inst] = {
        cls = cls, info = info, name = cls, parent = nil, children = {}, props = {}, attrs = {},
        signals = {}, destroyed = false, tags = {},
    }
    for _, c in ipairs(info.chain) do
        local init = ClassInit[c]
        if init then init(inst, STATE[inst]) end
    end
    return inst
end

local function findHook(info, tbl, key)
    for _, c in ipairs(info.chain) do
        local t = tbl[c]
        if t and t[key] then return t[key] end
    end
    return nil
end

local function ownScale(inst)
    for _, c in ipairs(STATE[inst].children) do
        local cs = STATE[c]
        if cs.cls == "UIScale" then return cs.props.Scale or 1 end
    end
    return 1
end

local function accScale(inst)
    local s = 1
    local cur = inst
    while cur do
        s = s * ownScale(cur)
        cur = STATE[cur].parent
    end
    return s
end

local function propOf(inst, key)
    local st = STATE[inst]
    local v = st.props[key]
    if v ~= nil then return v end
    local ptype = st.info.props[key]
    if ptype then return defaultFor(st, key, ptype) end
    return nil
end

local textBounds

local function absSize(inst)
    local st = STATE[inst]
    local isA = st.info.isA
    if isA.ScreenGui or isA.LayerCollector then
        if st.parent == nil then return Vector2.new(0, 0) end
        return VIEWPORT
    end
    if not isA.GuiObject then return Vector2.new(0, 0) end
    local p = st.parent
    if not p then return Vector2.new(0, 0) end
    local pst = STATE[p]
    if not (pst.info.isA.GuiObject or pst.info.isA.LayerCollector) then return Vector2.new(0, 0) end
    local psz = absSize(p)
    local size = propOf(inst, "Size")
    local pacc = 1
    do
        local cur = p
        while cur do
            pacc = pacc * ownScale(cur)
            cur = STATE[cur].parent
        end
    end
    local x = psz.X * size.X.Scale + size.X.Offset * pacc
    local y = psz.Y * size.Y.Scale + size.Y.Offset * pacc
    local auto = propOf(inst, "AutomaticSize")
    if auto and auto.Name ~= "None" and textBounds and (isA.TextLabel or isA.TextButton or isA.TextBox) then
        local tb = textBounds(inst, x)
        if auto.Name == "X" or auto.Name == "XY" then x = math.max(x, tb.X) end
        if auto.Name == "Y" or auto.Name == "XY" then y = math.max(y, tb.Y) end
    elseif auto and auto.Name ~= "None" then
        local cs = Harness.contentSize(inst)
        if auto.Name == "X" or auto.Name == "XY" then x = math.max(x, cs.X) end
        if auto.Name == "Y" or auto.Name == "XY" then y = math.max(y, cs.Y) end
    end
    local own = ownScale(inst)
    return Vector2.new(math.max(x * own, 0), math.max(y * own, 0))
end

local function absPos(inst)
    local st = STATE[inst]
    local isA = st.info.isA
    if not isA.GuiObject then return Vector2.new(0, 0) end
    local p = st.parent
    if not p then return Vector2.new(0, 0) end
    local pst = STATE[p]
    if not (pst.info.isA.GuiObject or pst.info.isA.LayerCollector) then return Vector2.new(0, 0) end
    local ppos = pst.info.isA.GuiObject and absPos(p) or Vector2.new(0, 0)
    local psz = absSize(p)
    local pos = propOf(inst, "Position")
    local anchor = propOf(inst, "AnchorPoint")
    local sz = absSize(inst)
    local pacc = 1
    do
        local cur = p
        while cur do
            pacc = pacc * ownScale(cur)
            cur = STATE[cur].parent
        end
    end
    return Vector2.new(
        ppos.X + psz.X * pos.X.Scale + pos.X.Offset * pacc - anchor.X * sz.X,
        ppos.Y + psz.Y * pos.Y.Scale + pos.Y.Offset * pacc - anchor.Y * sz.Y
    )
end

function Harness.contentSize(inst)
    local st = STATE[inst]
    local layout
    for _, c in ipairs(st.children) do
        if STATE[c].info.isA.UIListLayout then layout = c break end
    end
    local w, h, n = 0, 0, 0
    local pad = layout and propOf(layout, "Padding").Offset or 0
    local vertical = true
    if layout then
        local fd = propOf(layout, "FillDirection")
        vertical = fd and fd.Name == "Vertical"
    end
    for _, c in ipairs(st.children) do
        local cs = STATE[c]
        if cs.info.isA.GuiObject and propOf(c, "Visible") then
            local sz = absSize(c)
            n += 1
            if vertical then h += sz.Y w = math.max(w, sz.X) else w += sz.X h = math.max(h, sz.Y) end
        end
    end
    if n > 1 then
        if vertical then h += pad * (n - 1) else w += pad * (n - 1) end
    end
    local acc = 1
    for _, c in ipairs(st.children) do
        if STATE[c].info.isA.UIPadding then
            local pd = STATE[c].props
            local function px(u) return u and (u.Offset) or 0 end
            h += px(pd.PaddingTop) + px(pd.PaddingBottom)
            w += px(pd.PaddingLeft) + px(pd.PaddingRight)
        end
    end
    return Vector2.new(w, h)
end

textBounds = function(inst, availableWidth)
    local text = propOf(inst, "Text") or ""
    local size = propOf(inst, "TextSize") or 14
    local lines = 1
    local _, nl = text:gsub("\n", "")
    lines += nl
    local maxLen = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do maxLen = math.max(maxLen, utf8.len(line) or #line) end
    local w = maxLen * size * 0.5
    local h = lines * size
    if propOf(inst, "TextWrapped") and availableWidth and availableWidth > 0 and w > availableWidth then
        local extra = math.ceil(w / availableWidth)
        h = h * extra
        w = availableWidth
    end
    return Vector2.new(w, h)
end
Harness.textBounds = textBounds

local COMPUTED = {
    AbsoluteSize = function(inst, st) if st.info.isA.GuiBase2d then return absSize(inst) end end,
    AbsolutePosition = function(inst, st) if st.info.isA.GuiBase2d then return absPos(inst) end end,
    AbsoluteRotation = function(inst, st) if st.info.isA.GuiBase2d then return 0 end end,
    AbsoluteContentSize = function(inst, st)
        if st.info.isA.UIGridStyleLayout then return Harness.contentSize(st.parent or inst) end
    end,
    AbsoluteCanvasSize = function(inst, st)
        if st.info.isA.ScrollingFrame then
            local sz, cs = absSize(inst), propOf(inst, "CanvasSize")
            local x, y = sz.X * cs.X.Scale + cs.X.Offset, sz.Y * cs.Y.Scale + cs.Y.Offset
            local auto = propOf(inst, "AutomaticCanvasSize")
            if auto and auto.Name ~= "None" then
                local c = Harness.contentSize(inst)
                if auto.Name == "X" or auto.Name == "XY" then x = math.max(x, c.X) end
                if auto.Name == "Y" or auto.Name == "XY" then y = math.max(y, c.Y) end
            end
            return Vector2.new(x, y)
        end
    end,
    AbsoluteWindowSize = function(inst, st) if st.info.isA.ScrollingFrame then return absSize(inst) end end,
    TextBounds = function(inst, st)
        if st.info.isA.TextLabel or st.info.isA.TextButton or st.info.isA.TextBox then
            return textBounds(inst, absSize(inst).X)
        end
    end,
    ContentText = function(inst, st)
        if st.info.isA.TextLabel or st.info.isA.TextButton or st.info.isA.TextBox then
            local t = propOf(inst, "Text") or ""
            if propOf(inst, "RichText") then t = t:gsub("<[^>]->", "") end
            return t
        end
    end,
    TextFits = function(inst, st)
        if st.info.isA.TextLabel or st.info.isA.TextButton then
            local tb, sz = textBounds(inst, absSize(inst).X), absSize(inst)
            return tb.X <= sz.X and tb.Y <= sz.Y
        end
    end,
    ViewportSize = function(inst, st) if st.cls == "Camera" then return VIEWPORT end end,
}

local IM = {}

function IM.IsA(self, cls) return STATE[self].info.isA[cls] == true end
IM.isA = IM.IsA
function IM.GetChildren(self) return table.clone(STATE[self].children) end
function IM.GetDescendants(self) return descendants(self) end
function IM.GetFullName(self) return fullName(self) end
function IM.GetDebugId(self) return tostring(self) end

function IM.FindFirstChild(self, name, recursive)
    if type(name) ~= "string" then error("Argument 1 missing or nil", 2) end
    for _, c in ipairs(STATE[self].children) do
        if STATE[c].name == name then return c end
    end
    if recursive then
        for _, c in ipairs(STATE[self].children) do
            local r = IM.FindFirstChild(c, name, true)
            if r then return r end
        end
    end
    return nil
end
IM.findFirstChild = IM.FindFirstChild
function IM.FindFirstDescendant(self, name) return IM.FindFirstChild(self, name, true) end
function IM.FindFirstChildOfClass(self, cls)
    for _, c in ipairs(STATE[self].children) do
        if STATE[c].cls == cls then return c end
    end
    return nil
end
function IM.FindFirstChildWhichIsA(self, cls, recursive)
    for _, c in ipairs(STATE[self].children) do
        if STATE[c].info.isA[cls] then return c end
    end
    if recursive then
        for _, c in ipairs(STATE[self].children) do
            local r = IM.FindFirstChildWhichIsA(c, cls, true)
            if r then return r end
        end
    end
    return nil
end
function IM.FindFirstAncestor(self, name)
    for _, a in ipairs(ancestorsOf(self)) do if STATE[a].name == name then return a end end
    return nil
end
function IM.FindFirstAncestorOfClass(self, cls)
    for _, a in ipairs(ancestorsOf(self)) do if STATE[a].cls == cls then return a end end
    return nil
end
function IM.FindFirstAncestorWhichIsA(self, cls)
    for _, a in ipairs(ancestorsOf(self)) do if STATE[a].info.isA[cls] then return a end end
    return nil
end
function IM.IsDescendantOf(self, other) return isAncestorOf(other, self) end
function IM.IsAncestorOf(self, other) return isAncestorOf(self, other) end

function IM.WaitForChild(self, name, timeout)
    local found = IM.FindFirstChild(self, name)
    if found then return found end
    local deadline = Harness.now() + (timeout or 5)
    while Harness.now() < deadline do
        task.wait(0.05)
        found = IM.FindFirstChild(self, name)
        if found then return found end
    end
    return nil
end

function IM.ClearAllChildren(self)
    for _, c in ipairs(table.clone(STATE[self].children)) do IM.Destroy(c) end
end

function IM.Destroy(self)
    local st = STATE[self]
    if st.destroyed then return end
    for _, c in ipairs(table.clone(st.children)) do IM.Destroy(c) end
    if st.parent then
        st.destroyed = false
        setParent(self, nil)
    end
    st.destroyed = true
    if st.signals.Destroying then st.signals.Destroying:_fire() end
    for key, sig in pairs(st.signals) do
        if key ~= "Destroying" then sig:_disconnectAll() end
    end
end
IM.destroy = IM.Destroy
IM.Remove = IM.Destroy

function IM.Clone(self)
    local st = STATE[self]
    local copy = createInstance(st.cls)
    local cst = STATE[copy]
    cst.name = st.name
    for k, v in pairs(st.props) do cst.props[k] = v end
    for k, v in pairs(st.attrs) do cst.attrs[k] = v end
    for _, c in ipairs(st.children) do
        local cc = IM.Clone(c)
        setParent(cc, copy)
    end
    return copy
end

function IM.SetAttribute(self, name, value)
    local st = STATE[self]
    if type(name) ~= "string" or not name:match("^[%w_]+$") or name:sub(1, 3) == "RBX" or #name > 100 then
        error("Attribute name '" .. tostring(name) .. "' is invalid", 2)
    end
    if value ~= nil then
        local t = typeof(value)
        local ok = t == "string" or t == "boolean" or t == "number" or t == "Color3" or t == "Vector2" or t == "Vector3"
            or t == "UDim" or t == "UDim2" or t == "NumberRange" or t == "NumberSequence" or t == "ColorSequence" or t == "CFrame"
        if not ok then error("Unable to set attribute '" .. name .. "': unsupported type " .. t, 2) end
    end
    local old = st.attrs[name]
    st.attrs[name] = value
    if old ~= value then
        local s = st.signals["attr:" .. name]
        if s then s:_fire() end
        local g = st.signals.AttributeChanged
        if g then g:_fire(name) end
    end
end
function IM.GetAttribute(self, name) return STATE[self].attrs[name] end
function IM.GetAttributes(self) return table.clone(STATE[self].attrs) end
function IM.GetAttributeChangedSignal(self, name) return getSignal(self, "attr:" .. name) end

function IM.GetPropertyChangedSignal(self, prop)
    local st = STATE[self]
    if st.info.props[prop] == nil and prop ~= "Name" and prop ~= "Parent" then
        error(tostring(prop) .. " is not a valid property name.", 2)
    end
    return getSignal(self, "prop:" .. prop)
end

function IM.AddTag(self, tag) STATE[self].tags[tag] = true end
function IM.HasTag(self, tag) return STATE[self].tags[tag] == true end
function IM.RemoveTag(self, tag) STATE[self].tags[tag] = nil end
function IM.GetTags(self)
    local out = {}
    for t in pairs(STATE[self].tags) do table.insert(out, t) end
    return out
end

local stubWarned = {}
local function stubMethod(cls, key)
    return function(...)
        local id = cls .. ":" .. key
        Harness.calls[id] = (Harness.calls[id] or 0) + 1
        if not stubWarned[id] then
            stubWarned[id] = true
            print("[mock] unimplemented method " .. id .. " (returns nil)")
        end
        return nil
    end
end

local function invalidMember(inst, key)
    local st = STATE[inst]
    error(string.format('%s is not a valid member of %s "%s"', tostring(key), st.cls, fullName(inst)), 3)
end

InstanceMT.__index = function(inst, key)
    local st = STATE[inst]
    local info = st.info
    if key == "ClassName" then return st.cls end
    if key == "Name" then return st.name end
    if key == "Parent" then return st.parent end
    local ptype = info.props[key]
    if ptype ~= nil then
        local comp = COMPUTED[key]
        if comp then
            local v = comp(inst, st)
            if v ~= nil then return v end
        end
        local hook = findHook(info, ClassGet, key)
        if hook then
            local v = hook(inst, st)
            if v ~= nil then return v end
        end
        local v = st.props[key]
        if v ~= nil then return v end
        v = defaultFor(st, key, ptype)
        if v ~= nil then return v end
        for _, c in ipairs(st.children) do
            if STATE[c].name == key then return c end
        end
        return nil
    end
    if info.events[key] then return getSignal(inst, key) end
    local m = IM[key]
    if m and info.methods[key] then
        local override = findHook(info, ClassMethods, key)
        if override then return override end
        return m
    end
    if info.methods[key] then
        local override = findHook(info, ClassMethods, key)
        if override then return override end
        return stubMethod(st.cls, key)
    end
    for _, c in ipairs(st.children) do
        if STATE[c].name == key then return c end
    end
    invalidMember(inst, key)
end

InstanceMT.__newindex = function(inst, key, value)
    local st = STATE[inst]
    local info = st.info
    if st.destroyed and key == "Parent" then
        if value ~= nil then error("The Parent property of " .. st.name .. " is locked because the current thread cannot access it", 2) end
        return
    end
    if key == "Name" then
        if type(value) ~= "string" then error("Unable to assign property Name. string expected, got " .. typeof(value), 2) end
        if st.name ~= value then st.name = value notifyProp(inst, "Name") end
        return
    end
    if key == "Parent" then setParent(inst, value) return end
    if key == "ClassName" then error("Unable to assign property ClassName. Property is read only", 2) end
    local ptype = info.props[key]
    if ptype == nil then invalidMember(inst, key) end
    if COMPUTED[key] and COMPUTED[key](inst, st) ~= nil and key ~= "CanvasSize" then
        error("Unable to assign property " .. key .. ". Property is read only", 2)
    end
    if not typeOk(ptype, value) then
        error(string.format("Unable to assign property %s. %s expected, got %s", key, describeType(ptype), value == nil and "nil" or typeof(value)), 2)
    end
    local setter = findHook(info, ClassSet, key)
    if setter then
        local handled = setter(inst, st, value)
        if handled then return end
    end
    local old = st.props[key]
    st.props[key] = value
    if old ~= value then notifyProp(inst, key) end
end

InstanceMT.__tostring = function(inst) return STATE[inst].name end

Instance = {
    new = function(cls, parent)
        local inst = createInstance(cls)
        if parent ~= nil then setParent(inst, parent) end
        return inst
    end,
}

function Harness.defineMethods(cls, tbl)
    ClassMethods[cls] = ClassMethods[cls] or {}
    for k, v in pairs(tbl) do ClassMethods[cls][k] = v end
end
function Harness.defineGet(cls, tbl)
    ClassGet[cls] = ClassGet[cls] or {}
    for k, v in pairs(tbl) do ClassGet[cls][k] = v end
end
function Harness.defineSet(cls, tbl)
    ClassSet[cls] = ClassSet[cls] or {}
    for k, v in pairs(tbl) do ClassSet[cls][k] = v end
end
function Harness.defineInit(cls, fn) ClassInit[cls] = fn end

function Harness.new(cls, props, parent)
    local inst = createInstance(cls)
    for k, v in pairs(props or {}) do inst[k] = v end
    if parent then setParent(inst, parent) end
    return inst
end
function Harness.signal(inst, key) return getSignal(inst, key) end
function Harness.state(inst) return STATE[inst] end
function Harness.rawProp(inst, key) return propOf(inst, key) end
function Harness.rawSet(inst, key, value)
    local st = STATE[inst]
    local old = st.props[key]
    st.props[key] = value
    if old ~= value then notifyProp(inst, key) end
end
function Harness.fullName(inst) return fullName(inst) end
function Harness.descendants(inst) return descendants(inst) end
function Harness.isInstance(v) return type(v) == "table" and STATE[v] ~= nil end