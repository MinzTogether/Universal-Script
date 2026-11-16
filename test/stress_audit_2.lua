dofile("/tmp/test_inspect/boot_env.lua")

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
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
local sLight = Harness.new("SpotLight", { Enabled = true, Shadows = true }, testPart)
local surfLight = Harness.new("SurfaceLight", { Enabled = true, Shadows = true }, testPart)
local pEmitter = Harness.new("ParticleEmitter", { Enabled = true, Rate = 50 }, testPart)
local smoke = Harness.new("Smoke", { Enabled = true }, testPart)
local fire = Harness.new("Fire", { Enabled = true }, testPart)
local sparkles = Harness.new("Sparkles", { Enabled = true }, testPart)
local trail = Harness.new("Trail", { Enabled = true }, testPart)
local beam = Harness.new("Beam", { Enabled = true }, testPart)
local hl = Harness.new("Highlight", { Enabled = true }, testPart)
local sound = Harness.new("Sound", { Volume = 0.8 }, Workspace)
local soundGroup = Harness.new("SoundGroup", { Volume = 0.9 }, game:GetService("SoundService"))

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

print("=== CHECK 1: JUMP_CFG Snapshot Integrity with UseJumpPower = false ===")
local hum = game:GetService("Players").LocalPlayer.Character.Humanoid
hum.UseJumpPower = false
hum.JumpPower = 50
hum.JumpHeight = 7.2

local localTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Local")
local jumpSwitch, jumpBox
for _, d in ipairs(localTab:GetDescendants()) do
    if d:IsA("TextLabel") and d.Text == "Jump Boost" then
        local row = d.Parent
        jumpSwitch = row:FindFirstChildOfClass("TextButton")
        jumpBox = row:FindFirstChildOfClass("TextBox")
        break
    end
end
jumpBox.Text = "120"
Harness.flush()
click(jumpSwitch)
Harness.advance(0.5, 1/30)
print("After enabling Jump Boost (120): UseJumpPower=", hum.UseJumpPower, "JumpPower=", hum.JumpPower)
-- Simulate game script touching UseJumpPower = false while JumpPower is still 120:
hum.UseJumpPower = false
Harness.flush()
Harness.advance(0.5, 1/30)
print("After external game script set UseJumpPower=false: UseJumpPower=", hum.UseJumpPower, "JumpPower=", hum.JumpPower)
-- Turn OFF Jump Boost and check if JumpPower restores to 50 or stays stuck at 120!
click(jumpSwitch)
Harness.advance(0.5, 1/30)
print("After disabling Jump Boost: UseJumpPower=", hum.UseJumpPower, "JumpPower=", hum.JumpPower, "(Expected JumpPower=50!)")

print("=== CHECK 2: FPS Profile QualityLevel when Automatic (0) ===")
local fpsTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_FPS")
local renderSettings = settings().Rendering
print("Initial QualityLevel:", renderSettings.QualityLevel.Name, renderSettings.QualityLevel.Value)
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
    if item:IsA("TextButton") and item.Text == "Performance" then
        click(item)
        break
    end
end
Harness.advance(0.2, 1/30)
click(profileSwitch)
Harness.advance(0.5, 1/30)
print("QualityLevel in Performance mode (when started from Automatic):", renderSettings.QualityLevel.Name)
print("Part Material in Performance mode:", testPart.Material.Name, "Reflectance:", testPart.Reflectance)
print("PointLight Enabled in Performance mode:", pLight.Enabled, "Shadows:", pLight.Shadows)

click(profileArrow)
Harness.advance(0.2, 1/30)
for _, item in ipairs(modeList:GetDescendants()) do
    if item:IsA("TextButton") and item.Text == "Extreme" then
        click(item)
        break
    end
end
Harness.advance(0.5, 1/30)
print("QualityLevel in Extreme mode:", renderSettings.QualityLevel.Name)
print("Part Material in Extreme mode:", testPart.Material.Name, "GlassPart Material:", glassPart.Material.Name)

click(profileSwitch)
Harness.advance(0.5, 1/30)
print("After disabling FPS Profile -> QualityLevel:", renderSettings.QualityLevel.Name,
    "Part Material:", testPart.Material.Name, "Reflectance:", testPart.Reflectance,
    "PointLight Enabled:", pLight.Enabled, "Shadows:", pLight.Shadows)
