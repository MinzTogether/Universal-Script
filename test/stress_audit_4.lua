dofile("/tmp/test_inspect/boot_env.lua")

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
-- AUDIT 4A: Deleting a running script does NOT stop it!
-- ============================================================================
print("=== CHECK 4A: Deleting a Running Script in Script.lua ===")
Elysera.SelectTab("Script")
Harness.advance(0.2, 1/30)
local scriptTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Script")
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

_G.bgCounter = 0
nameBox.Text = "InfiniteLoopScript"
codeBox.Text = "task.spawn(function() while true do _G.bgCounter = _G.bgCounter + 1; task.wait(0.1) end end); return function() _G.bgStopped = true end"
Harness.flush()
click(saveBtn)
Harness.advance(0.5, 1/30)

local scriptRow
for _, c in ipairs(scriptTab.FunctionPanel2:GetChildren()) do
    if c.Name:match("^Script_") then scriptRow = c break end
end
local playBtn, moreBtn
for _, c in ipairs(scriptRow:GetChildren()) do
    if c:IsA("TextButton") then
        if c.Position.X.Offset == 0 then playBtn = c
        elseif c.Position.X.Offset == -34 then moreBtn = c end
    end
end

-- Start the script
click(playBtn)
Harness.advance(0.6, 1/30)
print("Script running -> _G.bgCounter:", _G.bgCounter, "_G.bgStopped:", _G.bgStopped)

-- Open context menu -> click Delete -> confirm Yes, Delete
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
-- Wait 7 seconds (past UNDO_SECONDS = 6s so finalize() destroys the row!)
Harness.advance(7.0, 1/30)
local afterDeleteCounter = _G.bgCounter
Harness.advance(1.0, 1/30)
print("After deleting & finalizing script -> _G.bgStopped:", _G.bgStopped,
    "Counter before 1s:", afterDeleteCounter, "Counter after 1s:", _G.bgCounter,
    "(BUG: cleanup was never called and script is still in Running!)")

-- ============================================================================
-- AUDIT 4B: Editing a running script in Script.lua
-- ============================================================================
print("=== CHECK 4B: Duplicate Name via Delete + Add + Undo ===")
click(addBtn)
Harness.advance(0.3, 1/30)
nameBox.Text = "DupTest"
codeBox.Text = "print('v1')"
Harness.flush()
click(saveBtn)
Harness.advance(0.5, 1/30)

local dupRow
for _, c in ipairs(scriptTab.FunctionPanel2:GetChildren()) do
    if c.Name:match("^Script_") then dupRow = c break end
end
for _, c in ipairs(dupRow:GetChildren()) do
    if c:IsA("TextButton") and c.Position.X.Offset == -34 then moreBtn = c break end
end
click(moreBtn)
Harness.advance(0.2, 1/30)
menuCatcher = Elysera.ScreenGui:FindFirstChild("MenuCatcher")
for _, d in ipairs(menuCatcher:GetDescendants()) do
    if d:IsA("TextButton") and d.Text == "Delete" then click(d) break end
end
Harness.advance(0.3, 1/30)
for _, d in ipairs(delBox:GetDescendants()) do
    if d:IsA("TextButton") and d.Text == "Yes, Delete" then click(d) break end
end
Harness.advance(0.3, 1/30)

-- While "DupTest" is in the 6s Undo window, add a new script named "DupTest"
click(addBtn)
Harness.advance(0.3, 1/30)
nameBox.Text = "DupTest"
codeBox.Text = "print('v2')"
Harness.flush()
click(saveBtn)
Harness.advance(0.5, 1/30)

-- Now click "Undo" on the ToastHost!
local toastHost = Elysera.ScreenGui:FindFirstChild("ToastHost")
for _, d in ipairs(toastHost:GetDescendants()) do
    if d:IsA("TextButton") and d.Text == "Undo" then
        click(d)
        break
    end
end
Harness.advance(0.5, 1/30)

-- Count how many visible rows have Title == "DupTest"
local dupCount = 0
for _, c in ipairs(scriptTab.FunctionPanel2:GetChildren()) do
    if c.Name:match("^Script_") and c.Visible then
        local t = c.Left and c.Left:FindFirstChild("Title")
        if t and t.Text == "DupTest" then dupCount = dupCount + 1 end
    end
end
print("Visible scripts with identical name 'DupTest' after Undo:", dupCount, "(Expected 1 unique name, got 2!)")

-- ============================================================================
-- AUDIT 4C: Max Zoom vs Min Zoom Fight Loop in Local.lua
-- ============================================================================
print("=== CHECK 4C: Max Zoom vs Min Zoom Cross-Property Validation ===")
local localTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Local")
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
Harness.advance(0.5, 1/30)
local lp = game:GetService("Players").LocalPlayer
print("LocalPlayer CameraMinZoomDistance:", lp.CameraMinZoomDistance, "CameraMaxZoomDistance:", lp.CameraMaxZoomDistance,
    "(BUG: MinZoom=50 > MaxZoom=10 allowed simultaneously without cross-clamping!)")
