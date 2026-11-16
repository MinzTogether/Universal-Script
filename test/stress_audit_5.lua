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
-- AUDIT 5A: Status_Server.lua - isValidJobId accepts bogus short hex strings like "a-b-c-d-e"
-- ============================================================================
print("=== CHECK 5A: Status_Server.lua JobId Validation & Server Hopper ===")
local statusTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Status & Server")
local hopperCard = statusTab:FindFirstChild("ServerHopper")
local hopperBox = hopperCard:FindFirstChildOfClass("TextBox")
local joinRow = hopperCard:FindFirstChild("Join JobId") or hopperCard:GetChildren()[5]
local joinBtn
for _, d in ipairs(hopperCard:GetDescendants()) do
    if d:IsA("TextButton") and d.Text == "Join" then joinBtn = d break end
end

local beforeTeleports = #Harness.teleports
hopperBox.Text = "a-b-c-d-e"
Harness.flush()
click(joinBtn)
Harness.advance(0.2, 1/30)
print("Teleport count after joining bogus 'a-b-c-d-e':", #Harness.teleports - beforeTeleports,
    "Last teleport jobId:", Harness.teleports[#Harness.teleports] and Harness.teleports[#Harness.teleports].jobId,
    "(BUG: 'a-b-c-d-e' accepted as a valid UUID JobId!)")

-- Wait for PENDING_TIMEOUT (10s) to clear teleportPending
Harness.advance(10.5, 1/30)

-- Test URL-encoded join link with Invalid %ZZ escape in parseJoinInput!
print("=== CHECK 5B: Status_Server.lua URL-encoded link & Server Hop HTTP Failures ===")
hopperBox.Text = "https://www.roblox.com/games/1818?gameInstanceId=11111111-2222-3333-4444-555555555555"
Harness.flush()
click(joinBtn)
Harness.advance(10.5, 1/30)
print("Valid URL join teleported to:", Harness.teleports[#Harness.teleports].jobId)

-- Test Server Hop buttons when HTTP returns 429, 500, malformed JSON, empty list, and when TeleportFails = true!
local hopBtns = {}
for _, d in ipairs(statusTab:GetDescendants()) do
    if d:IsA("TextButton") and d.Text == "Hop" then
        table.insert(hopBtns, d)
    end
end
print("Found Hop buttons:", #hopBtns)

-- Case 1: Normal hop
click(hopBtns[1])
Harness.advance(2.0, 1/30)
print("After Hop[1] (Random) -> Button text:", hopBtns[1].Text, "Teleports:", #Harness.teleports)
Harness.advance(10.5, 1/30)

-- Case 2: Teleport fails on every attempt (HOP_MAX_ATTEMPTS = 3)
Harness.teleportFails = true
click(hopBtns[2])
Harness.advance(5.0, 1/30)
print("After Hop[2] (Least) with teleportFails=true -> Button text:", hopBtns[2].Text)
Harness.teleportFails = false
Harness.advance(2.0, 1/30)

-- Case 3: HTTP 429 Rate Limit
local origHandler = Harness.requestHandler
Harness.requestHandler = function(opts)
    return { Success = false, StatusCode = 429, StatusMessage = "Too Many Requests", Body = "" }
end
click(hopBtns[3])
Harness.advance(2.0, 1/30)
print("After Hop[3] (Ping) with HTTP 429 -> Button text:", hopBtns[3].Text)
Harness.requestHandler = origHandler
Harness.advance(2.0, 1/30)

-- ============================================================================
-- AUDIT 5C: Waypoints in Local.lua - Max 15 limit, NaN/Inf, Malformed Import, Duplicate Names
-- ============================================================================
print("=== CHECK 5C: Waypoints Boundary & Import Validation ===")
local localTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Local")
local wpCard
for _, d in ipairs(localTab:GetDescendants()) do
    if d.Name == "Waypoints" and d:IsA("Frame") then wpCard = d break end
end
local wpInput, wpSaveBtn, wpExportBtn, wpImportBtn
for _, d in ipairs(wpCard:GetDescendants()) do
    if d:IsA("TextBox") and d.PlaceholderText == "Name or exported JSON" then wpInput = d end
    if d:IsA("TextLabel") and d.Text == "Save here" then wpSaveBtn = d.Parent end
    if d:IsA("TextButton") and d.Text == "Export" then wpExportBtn = d end
    if d:IsA("TextButton") and d.Text == "Import" then wpImportBtn = d end
end

-- Try importing waypoints with NaN/Inf or huge numbers (1e308) or non-finite numbers via JSON!
-- Wait: in Waypoints ImportBtn (Local.lua:2645-2673):
-- Does ImportBtn check for math.abs(p.x) == math.huge or p.x ~= p.x or math.abs(p.x) > 1e7, or r = NaN?!
wpInput.Text = '{"format":"Elysera-Waypoints","points":[{"n":"HugePoint","x":1e308,"y":1e308,"z":1e308,"r":1e308}]}'
Harness.flush()
click(wpImportBtn)
Harness.advance(0.5, 1/30)

-- Let's check if "HugePoint" was imported and what happens when we click "Go" on it!
local goBtn
for _, d in ipairs(wpCard:GetDescendants()) do
    if d:IsA("TextLabel") and d.Text == "Go" then goBtn = d.Parent break end
end
print("Was HugePoint (1e308, r=1e308) imported? goBtn found:", goBtn ~= nil)
if goBtn then
    click(goBtn)
    Harness.advance(0.2, 1/30)
    local root = game:GetService("Players").LocalPlayer.Character.HumanoidRootPart
    print("After clicking Go on HugePoint -> root.Position:", root.Position, "root.CFrame:", root.CFrame)
end

print("Errors:", #Harness.errors, "Warns:", #Harness.warns)
for i, e in ipairs(Harness.errors) do print("ERR", i, e) end
for i, w in ipairs(Harness.warns) do print("WARN", i, w) end
