dofile("/tmp/test_inspect/boot_env.lua")

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")

local Elysera = loadLuauFile("/tmp/test_inspect/extracted/MainWeb.lua")()
Harness.flush()
Harness.advance(2.0, 1/30)

local function click(btn)
    Harness.signal(btn, "MouseButton1Down"):_fire()
    Harness.signal(btn, "MouseButton1Up"):_fire()
    Harness.signal(btn, "MouseButton1Click"):_fire()
    Harness.signal(btn, "Activated"):_fire()
    Harness.flush()
end

-- ============================================================================
-- AUDIT 3A: ESP HIGHLIGHT_BUDGET = 31 Overflow when a player's root is unparented
-- ============================================================================
print("=== CHECK 3A: ESP Highlight Budget (31 limit) & Root Unparent Edge Case ===")
-- Create 34 dummy players (total 36 other players with Alice & Bob)
local extraPlayers = {}
for i = 1, 34 do
    local p = Harness.new("Player", { Name = "Bot" .. i, UserId = 2000 + i, DisplayName = "Bot" .. i }, Players)
    local char = Harness.makeCharacter("Bot" .. i, i * 3, 5, 0)
    Harness.rawSet(p, "Character", char)
    table.insert(extraPlayers, p)
    Harness.signal(Players, "PlayerAdded"):_fire(p)
end
Harness.flush()

local localTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Local")
local espSwitch
for _, d in ipairs(localTab:GetDescendants()) do
    if d:IsA("TextLabel") and d.Text == "Esp Player" then
        espSwitch = d.Parent:FindFirstChildOfClass("TextButton")
        break
    end
end
click(espSwitch)
Harness.advance(1.0, 1/30)

local espFolder = gethui():FindFirstChild("ElyseraESP") or CoreGui:FindFirstChild("ElyseraESP")
local function countHighlights()
    local hl, box = 0, 0
    for _, c in ipairs(espFolder:GetChildren()) do
        if c.ClassName == "Highlight" then hl = hl + 1
        elseif c.ClassName == "BoxHandleAdornment" then box = box + 1 end
    end
    return hl, box
end
local hl1, box1 = countHighlights()
print("With 36 other players -> Highlights:", hl1, "Boxes:", box1, "(Max allowed Highlights = 31)")

-- Now unparent 3 close players' HumanoidRootPart without firing CharacterRemoving (e.g. ragdoll/falling into void destroy of HRP)
for i = 1, 3 do
    local hrp = extraPlayers[i].Character:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.Parent = nil end
end
-- Move distant players closer so rebalance swaps highlights
for i = 30, 34 do
    local hrp = extraPlayers[i].Character:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.Position = Vector3.new(1, 5, 0) end
end
Harness.advance(1.0, 1/30)
local hl2, box2 = countHighlights()
print("After 3 HRPs unparented & rebalance -> Highlights:", hl2, "Boxes:", box2, "(BUG if Highlights > 31!)")

click(espSwitch)
Harness.advance(0.5, 1/30)
for _, p in ipairs(extraPlayers) do p:Destroy() end
Harness.flush()

-- ============================================================================
-- AUDIT 3B: Full Bright vs FPS Profile Property Contention & Restoration
-- ============================================================================
print("=== CHECK 3B: Full Bright + FPS Profile Cross-Module Contention ===")
Lighting.Brightness = 1.5
Lighting.GlobalShadows = true
Lighting.FogEnd = 500

local fbSwitch
for _, d in ipairs(localTab:GetDescendants()) do
    if d:IsA("TextLabel") and d.Text == "Full Bright" then
        fbSwitch = d.Parent:FindFirstChildOfClass("TextButton")
        break
    end
end
-- Select "Performance" mode on Full Bright (which sets GlobalShadows = false, FogEnd = 100000)
local fbStack = fbSwitch.Parent.Parent
local fbModeHit = fbStack.ModeRow.ModeWinbox.Hit
click(fbModeHit)
Harness.advance(0.1, 1/30)
local ddLayer = Elysera.ScreenGui:FindFirstChild("ModeDropdownLayer")
for _, item in ipairs(ddLayer.Panel:GetChildren()) do
    if item:IsA("TextButton") and item.Text == "Performance" then
        click(item)
        break
    end
end
Harness.advance(0.1, 1/30)

local fpsTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_FPS")
local profileSwitch
for _, d in ipairs(fpsTab:GetDescendants()) do
    if d:IsA("TextLabel") and d.Text == "FPS Profile" then
        profileSwitch = d.Parent:FindFirstChildOfClass("TextButton")
        break
    end
end

-- Step 1: Enable FPS Profile first (sets GlobalShadows = false)
click(profileSwitch)
Harness.advance(0.3, 1/30)
print("1. FPS Profile ON -> GlobalShadows:", Lighting.GlobalShadows)
-- Step 2: Enable Full Bright (Performance) while FPS Profile is already ON
click(fbSwitch)
Harness.advance(0.3, 1/30)
print("2. Full Bright ON -> GlobalShadows:", Lighting.GlobalShadows, "FogEnd:", Lighting.FogEnd)
-- Step 3: Disable FPS Profile first, then disable Full Bright
click(profileSwitch)
Harness.advance(0.3, 1/30)
print("3. FPS Profile OFF (Full Bright still ON) -> GlobalShadows:", Lighting.GlobalShadows)
click(fbSwitch)
Harness.advance(0.3, 1/30)
print("4. Both OFF -> GlobalShadows:", Lighting.GlobalShadows, "FogEnd:", Lighting.FogEnd, "Brightness:", Lighting.Brightness)

-- Now test the reverse order:
-- Step 1: Enable FPS Profile first
click(profileSwitch)
Harness.advance(0.3, 1/30)
-- Step 2: Enable Full Bright (Performance)
click(fbSwitch)
Harness.advance(0.3, 1/30)
-- Step 3: Disable Full Bright FIRST, then Disable FPS Profile!
click(fbSwitch)
Harness.advance(0.3, 1/30)
print("5. Reverse: Full Bright OFF first -> GlobalShadows:", Lighting.GlobalShadows)
click(profileSwitch)
Harness.advance(0.3, 1/30)
print("6. Reverse: Both OFF -> GlobalShadows:", Lighting.GlobalShadows, "(Expected true!)")

-- Now test: Enable Full Bright (Performance) FIRST, then FPS Profile (Extreme), then disable Full Bright FIRST, then disable FPS Profile!
Lighting.GlobalShadows = true
Lighting.FogEnd = 500
click(fbSwitch)
Harness.advance(0.3, 1/30)
click(profileSwitch)
Harness.advance(0.3, 1/30)
click(fbSwitch) -- Full Bright restores GlobalShadows = true while FPS Profile is still ON!
Harness.advance(0.3, 1/30)
print("7. FB ON -> FPS ON -> FB OFF (FPS still ON!) -> GlobalShadows:", Lighting.GlobalShadows, "(Expected false while FPS Profile is ON!)")
click(profileSwitch)
Harness.advance(0.3, 1/30)

-- ============================================================================
-- AUDIT 3C: Freecam + Character Respawn / Death while Freecam is ON!
-- ============================================================================
print("=== CHECK 3C: Freecam + Character Respawn Edge Case ===")
local freecamSwitch
for _, d in ipairs(localTab:GetDescendants()) do
    if d:IsA("TextLabel") and d.Text == "Freecam" then
        freecamSwitch = d.Parent:FindFirstChildOfClass("TextButton")
        break
    end
end
local lp = Players.LocalPlayer
local oldChar = lp.Character
local oldRoot = oldChar.HumanoidRootPart
print("Before Freecam: oldRoot.Anchored =", oldRoot.Anchored, "CameraSubject =", Workspace.CurrentCamera.CameraSubject)
click(freecamSwitch)
Harness.advance(0.3, 1/30)
print("Freecam ON: oldRoot.Anchored =", oldRoot.Anchored, "CameraType =", Workspace.CurrentCamera.CameraType.Name)

-- Now simulate player respawning while Freecam is ON!
local newChar = Harness.makeCharacter("Tester", 20, 5, 20)
oldChar.Parent = nil
Harness.rawSet(lp, "Character", newChar)
Harness.signal(lp, "CharacterAdded"):_fire(newChar)
-- In Roblox, when a character respawns, default camera scripts set CameraSubject to newChar.Humanoid,
-- OR what happens when Freecam is turned OFF after respawn?
Harness.advance(0.3, 1/30)
click(freecamSwitch)
Harness.advance(0.3, 1/30)
print("After respawn & Freecam OFF -> CameraSubject:", Workspace.CurrentCamera.CameraSubject,
    "Is CameraSubject in newChar?", Workspace.CurrentCamera.CameraSubject == newChar.Humanoid,
    "Camera.CFrame.Position:", Workspace.CurrentCamera.CFrame.Position,
    "New root Position:", newChar.HumanoidRootPart.Position)

-- ============================================================================
-- AUDIT 3D: Time of Day (TIME_CFG) with value = 24 vs 0 and Original Preset
-- ============================================================================
print("=== CHECK 3D: Time of Day Boundary (24 vs 0) & Original Preset ===")
Lighting.ClockTime = 14
local todSwitch, todBox, todStack
for _, d in ipairs(localTab:GetDescendants()) do
    if d:IsA("TextLabel") and d.Text == "Time of Day" then
        local row = d.Parent
        todSwitch = row:FindFirstChildOfClass("TextButton")
        todBox = row:FindFirstChildOfClass("TextBox")
        todStack = row.Parent
        break
    end
end
print("Prefilled Time of Day Box.Text:", todBox.Text)
todBox.Text = "24"
Harness.flush()
click(todSwitch)
Harness.advance(0.3, 1/30)
print("Time of Day ON with 24 -> Lighting.ClockTime:", Lighting.ClockTime)
-- Now what if user clicks "Original" preset chip while Time of Day is ON?
for _, chip in ipairs(todStack.Presets:GetChildren()) do
    if chip:IsA("TextButton") and chip.Text == "Original" then
        click(chip)
        break
    end
end
Harness.advance(0.3, 1/30)
print("After clicking Original preset -> Box.Text:", todBox.Text, "Lighting.ClockTime:", Lighting.ClockTime)
click(todSwitch)
Harness.advance(0.3, 1/30)

-- ============================================================================
-- AUDIT 3E: Script.lua Syntax Highlighter & Editor / Execution Edge Cases
-- ============================================================================
print("=== CHECK 3E: Script.lua Syntax Highlighter & Execution Edge Cases ===")
Elysera.SelectTab("Script")
Harness.advance(0.3, 1/30)
local scriptTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Script")
local addBtn = scriptTab.FunctionPanel1.AddButton
click(addBtn)
Harness.advance(0.3, 1/30)

local notBoxA = Elysera.ScreenGui:FindFirstChild("NotBoxA")
local nameBox, codeBox
for _, d in ipairs(notBoxA:GetDescendants()) do
    if d:IsA("TextBox") then
        if d.MultiLine then codeBox = d else nameBox = d end
    end
end

-- Test syntax highlighter with tricky inputs:
local trickyCodes = {
    "--[[ unclosed block comment <font color='red'>",
    "[==[ unclosed long string & < >",
    '"unclosed quote \\\nlocal x = 0x1F + 123.45.67',
    "-- single line comment\nlocal a = 'hello \\' world'\nreturn function() error('cleanup boom') end",
}
for idx, tc in ipairs(trickyCodes) do
    codeBox.Text = tc
    Harness.flush()
end
nameBox.Text = "   Test\0\n\tScript   "
Harness.flush()
-- Save the script
local saveBtn
for _, d in ipairs(notBoxA:GetDescendants()) do
    if d:IsA("TextButton") and d.Text == "Save" then saveBtn = d break end
end
click(saveBtn)
Harness.advance(0.5, 1/30)

-- Run the saved script (which returns a cleanup function that errors on stop!)
local scriptRow = scriptTab.FunctionPanel2:FindFirstChildWhichIsA("Frame")
for _, c in ipairs(scriptTab.FunctionPanel2:GetChildren()) do
    if c.Name:match("^Script_") then scriptRow = c break end
end
print("Created script row:", scriptRow and scriptRow.Name)
-- Find play button (rightOffset = 0)
local playBtn
for _, c in ipairs(scriptRow:GetChildren()) do
    if c:IsA("TextButton") and c.Position.X.Offset == 0 then playBtn = c break end
end
click(playBtn) -- Starts script -> returns cleanup function -> enters running_long
Harness.advance(0.5, 1/30)
click(playBtn) -- Stops script -> calls cleanup function which errors!
Harness.advance(0.5, 1/30)

print("Errors so far:", #Harness.errors, "Warns so far:", #Harness.warns)
