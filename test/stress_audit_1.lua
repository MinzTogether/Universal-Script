dofile("/tmp/test_inspect/m0_schema.lua")
CLASSDATA.Player.r.CameraMaxZoomDistance = "number"
CLASSDATA.Player.r.CameraMinZoomDistance = "number"
CLASSDATA.TextLabel.r.TextSelectable = "boolean"
CLASSDATA.TextButton.r.TextSelectable = "boolean"

loadLuauFile("/tmp/test_inspect/extracted/test/m1_core.lua")()
local f = assert(io.open("/tmp/test_inspect/extracted/test/m2_instance.lua", "rb"))
local m2_src = f:read("*a")
f:close()
m2_src = m2_src:gsub(
    "local function absSize%(inst%)",
    "local inAuto = {}\nlocal function absSize(inst)"
)
m2_src = m2_src:gsub(
    "elseif auto and auto%.Name ~= \"None\" then",
    "elseif auto and auto.Name ~= \"None\" and not inAuto[inst] then\n        inAuto[inst] = true"
)
m2_src = m2_src:gsub(
    "if auto%.Name == \"Y\" or auto%.Name == \"XY\" then y = math%.max%(y, cs%.Y%) end\n    end",
    "if auto.Name == \"Y\" or auto.Name == \"XY\" then y = math.max(y, cs.Y) end\n        inAuto[inst] = nil\n    end"
)
assert(loadstring(m2_src, "@m2_instance.lua"))()
loadLuauFile("/tmp/test_inspect/extracted/test/m3_env.lua")()

local origInputObject = Harness.inputObject
Harness.inputObject = function(inputType, state, extra)
    local o = origInputObject(inputType, state, extra)
    o.Changed = o.Changed or Harness.newSignal("InputObject.Changed")
    return o
end

Harness.defineMethods("TextBox", {
    CaptureFocus = function(self)
        Harness.focusedTextBox = self
        Harness.signal(self, "Focused"):_fire()
    end,
    ReleaseFocus = function(self, enterPressed)
        if Harness.focusedTextBox == self then Harness.focusedTextBox = nil end
        Harness.signal(self, "FocusLost"):_fire(enterPressed or false, nil)
    end,
    IsFocused = function(self)
        return Harness.focusedTextBox == self
    end,
})
Harness.defineMethods("Player", {
    GetNetworkPing = function(self) return (Harness.ping or 42) / 1000 end,
})
Harness.defineMethods("Stats", {
    GetTotalMemoryUsageMb = function(self) return Harness.memoryMb or 512 end,
})

local dir = "/tmp/test_inspect/extracted/"
for _, name in ipairs({ "MainWeb.lua", "Status_Server.lua", "Local.lua", "Script.lua", "FPS.lua", "Settings.lua" }) do
    local fh = assert(io.open(dir .. name, "rb"))
    Harness.files[name] = fh:read("*a")
    fh:close()
end

-- Create Elysera folder so file operations work!
makefolder("Elysera")

local Elysera = loadLuauFile(dir .. "MainWeb.lua")()
Harness.flush()
Harness.advance(2.0, 1/30)

local function findButtonByText(root, txt)
    for _, d in ipairs(root:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("TextLabel")) and d.Text == txt then
            if d:IsA("TextButton") then return d end
            if d.Parent and d.Parent:IsA("TextButton") then return d.Parent end
        end
    end
    return nil
end

local function click(btn)
    assert(btn, "Button not found")
    Harness.signal(btn, "MouseButton1Down"):_fire()
    Harness.signal(btn, "MouseButton1Up"):_fire()
    Harness.signal(btn, "MouseButton1Click"):_fire()
    Harness.signal(btn, "Activated"):_fire()
    Harness.flush()
end

-- 1. Test Tab switching across all 5 tabs + custom tab creation
print("--- TEST 1: Tab Switching & Custom Tabs ---")
for _, tname in ipairs({ "Status & Server", "Local", "FPS", "Script", "Settings" }) do
    Elysera.SelectTab(tname)
    Harness.advance(0.3, 1/30)
end

-- 2. Test Theme switching across all 22 themes + invalid themes + active color tweens
print("--- TEST 2: Theme Switching Stress ---")
local themeChangedCount = 0
local unsubTheme = Elysera.OnThemeChanged(function(id, th, entry)
    themeChangedCount = themeChangedCount + 1
end)
for _, th in ipairs(Elysera.Themes) do
    local ok, err = Elysera.SetTheme(th.id)
    assert(ok, "SetTheme failed for " .. tostring(th.id) .. ": " .. tostring(err))
    Harness.advance(0.05, 1/30)
end
local okBad, errBad = Elysera.SetTheme("nonexistent_theme")
print("Invalid theme result:", okBad, errBad)
unsubTheme()
print("Theme changed callbacks fired:", themeChangedCount)

-- 3. Test all toggles in LocalTab, FPSTab, StatusServerTab, SettingsTab!
print("--- TEST 3: Toggling All Switches On & Off ---")
local allSwitches = {}
for _, d in ipairs(Elysera.ScreenGui:GetDescendants()) do
    if d:IsA("TextButton") and type(d:GetAttribute("Toggled")) == "boolean" then
        table.insert(allSwitches, d)
    end
end
print("Found toggle switches:", #allSwitches)
for i, sw in ipairs(allSwitches) do
    local lbl = sw.Parent and sw.Parent:FindFirstChildOfClass("TextLabel")
    local name = lbl and lbl.Text or sw.Parent.Name
    click(sw)
    Harness.advance(0.25, 1/30)
    print(string.format("  Toggle ON [%d] %s -> Toggled=%s, Errors=%d, Warns=%d",
        i, name, tostring(sw:GetAttribute("Toggled")), #Harness.errors, #Harness.warns))
end

-- Step simulation for 5 seconds while all features are active!
Harness.advance(5.0, 1/30)
print("After 5s with all toggles ON -> Errors:", #Harness.errors, "Warns:", #Harness.warns)

-- Turn all switches off
for i, sw in ipairs(allSwitches) do
    if sw:GetAttribute("Toggled") == true then
        click(sw)
        Harness.advance(0.1, 1/30)
    end
end
Harness.advance(2.0, 1/30)
print("After turning all toggles OFF -> Errors:", #Harness.errors, "Warns:", #Harness.warns)
for i, e in ipairs(Harness.errors) do print("ERR", i, e) end
for i, w in ipairs(Harness.warns) do print("WARN", i, w) end
