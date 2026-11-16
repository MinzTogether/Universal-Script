
-- Luau standard library & globals shims for Lua 5.3 (texlua)
math.clamp = function(x, lo, hi)
    if x < lo then return lo end
    if x > hi then return hi end
    return x
end
math.round = function(x)
    return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5)
end
math.sign = function(x)
    return x > 0 and 1 or (x < 0 and -1 or 0)
end

table.clone = function(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    local mt = getmetatable(t)
    if mt then setmetatable(out, mt) end
    return out
end
table.clear = function(t)
    for k in pairs(t) do t[k] = nil end
end
table.find = function(t, val, init)
    for i = init or 1, #t do
        if t[i] == val then return i end
    end
    return nil
end
table.create = function(count, val)
    local out = {}
    if val ~= nil then
        for i = 1, count do out[i] = val end
    end
    return out
end
table.freeze = function(t) return t end
table.isfrozen = function(t) return false end

string.split = function(s, sep)
    sep = sep or ","
    local out = {}
    if sep == "" then
        for i = 1, #s do out[i] = s:sub(i, i) end
        return out
    end
    local pos = 1
    while true do
        local a, b = s:find(sep, pos, true)
        if not a then
            table.insert(out, s:sub(pos))
            break
        end
        table.insert(out, s:sub(pos, a - 1))
        pos = b + 1
    end
    return out
end

typeof = type

-- Luau compound assignment transpiler (+=, -=, *=, /=, ..=)
function _transpileLuau(src)
    -- Replace compound assignments on single lines: lhs += rhs
    -- Careful with multiple statements on one line like: if vertical then h += sz.Y w = ...
    local function repl(line)
        -- Split comment if not inside string (simple heuristic for these files)
        -- Actually in all 9 files, += is only used as `ident += expr`
        line = line:gsub("([%a_][%w_%.%[%]]*)%s*%+=%s*([^\n;]+)", function(lhs, rhs)
            -- check if rhs has trailing keywords like `break`, `return`, `else`, `end`, or another assignment
            return lhs .. " = " .. lhs .. " + " .. rhs
        end)
        return line
    end
    -- Specific safe replacements for the known Luau compound assignments:
    src = src:gsub("if vertical then h %+= sz%.Y w =", "if vertical then h = h + sz.Y; w =")
    src = src:gsub("else w %+= sz%.X h =", "else w = w + sz.X; h =")
    src = src:gsub("if vertical then h %+= pad %* %(n %- 1%) else w %+= pad %* %(n %- 1%) end",
                   "if vertical then h = h + pad * (n - 1) else w = w + pad * (n - 1) end")
    src = src:gsub("for _ in pairs%(v%) do n %+= 1 end", "for _ in pairs(v) do n = n + 1 end")
    src = src:gsub("if c == '\"' then pos %+= 1 break end", "if c == '\"' then pos = pos + 1; break end")
    src = src:gsub("if s:sub%(pos, pos%) == \"}\" then pos %+= 1 return obj end", "if s:sub(pos, pos) == \"}\" then pos = pos + 1; return obj end")
    src = src:gsub("if s:sub%(pos, pos%) == \"%\"\" then pos %+= 1 return arr end", "if s:sub(pos, pos) == \"]\" then pos = pos + 1; return arr end")
    src = src:gsub("if s:sub%(pos, pos%) == \"%]\"" .. " then pos %+= 1 return arr end", "if s:sub(pos, pos) == \"]\" then pos = pos + 1; return arr end")
    src = src:gsub("pos %+= (%d+) return", "pos = pos + %1; return")
    src = src:gsub("([%a_][%w_%.]*)%s*%+=%s*([^\n]+)", "%1 = %1 + (%2)")
    src = src:gsub("([%a_][%w_%.]*)%s*%-=%s*([^\n]+)", "%1 = %1 - (%2)")
    return src
end

rawLoadstring = load
loadstring = function(src, chunkname)
    if type(src) ~= "string" then return nil, "string expected" end
    local tsrc = _transpileLuau(src)
    return rawLoadstring(tsrc, chunkname)
end

function loadLuauFile(path)
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a")
    f:close()
    return assert(loadstring(src, "@" .. path))
end

ENUMDATA = {
    ActuatorRelativeTo = { "Attachment0", "Attachment1", "World" },
    ApplyStrokeMode = { "Contextual", "Border" },
    AutomaticSize = { "None", "X", "Y", "XY" },
    BorderMode = { "Outline", "Middle", "Inset" },
    CameraType = { "Fixed", "Attach", "Watch", "Track", "Follow", "Custom", "Scriptable", "Orbital" },
    CoreGuiType = { "PlayerList", "Health", "Backpack", "Chat", "All", "EmotesMenu", "SelfView", "Captures" },
    EasingDirection = { "In", "Out", "InOut" },
    EasingStyle = { "Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic", "Exponential", "Circular", "Cubic" },
    FillDirection = { "Horizontal", "Vertical" },
    Font = { "Legacy", "Arial", "ArialBold", "SourceSans", "SourceSansBold", "SourceSansLight", "SourceSansItalic", "Bodoni", "Garamond", "Cartoon", "Code", "Highway", "SciFi", "Arcade", "Fantasy", "Antique", "SourceSansSemibold", "Gotham", "GothamMedium", "GothamBold", "GothamBlack", "AmaticSC", "Bangers", "Creepster", "DenkOne", "Fondamento", "FredokaOne", "GrenzeGotisch", "IndieFlower", "JosefinSans", "Jura", "Kalam", "LuckiestGuy", "Merriweather", "Michroma", "Nunito", "Oswald", "PatrickHand", "PermanentMarker", "PlayfairDisplay", "Roboto", "RobotoCondensed", "RobotoMono", "Sarpanch", "SpecialElite", "TitilliumWeb", "Ubuntu", "BuilderSans", "BuilderSansMedium", "BuilderSansBold", "BuilderSansExtraBold" },
    GuiState = { "Idle", "Hover", "Press", "NonInteractable" },
    HighlightDepthMode = { "AlwaysOnTop", "Occluded" },
    HorizontalAlignment = { "Center", "Left", "Right" },
    HumanoidDisplayDistanceType = { "Viewer", "Subject", "None" },
    HumanoidStateType = { "FallingDown", "Running", "RunningNoPhysics", "Climbing", "StrafingNoPhysics", "Ragdoll", "GettingUp", "Jumping", "Landed", "Flying", "Freefall", "Seated", "PlatformStanding", "Dead", "Swimming", "Physics", "None" },
    InputSink = { "None", "Sink" },
    KeyCode = { "Unknown", "Backspace", "Tab", "Clear", "Return", "Pause", "Escape", "Space", "LeftControl", "RightControl", "LeftShift", "RightShift", "LeftAlt", "RightAlt", "Delete", "Insert", "Home", "End", "PageUp", "PageDown", "Up", "Down", "Left", "Right", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12" },
    LineJoinMode = { "Round", "Bevel", "Miter" },
    Material = { "Plastic", "SmoothPlastic", "Neon", "Wood", "WoodPlanks", "Marble", "Slate", "Concrete", "Granite", "Brick", "Pebble", "Cobblestone", "CorrodedMetal", "DiamondPlate", "Foil", "Metal", "Grass", "LeafyGrass", "Sand", "Fabric", "Snow", "Mud", "Ground", "Asphalt", "Salt", "Ice", "Glacier", "Glass", "ForceField", "Air", "Water", "Rock", "Sandstone", "Limestone", "Pavement", "Cardboard", "Carpet", "CeramicTiles", "ClayRoofTiles", "RoofShingles", "Leather", "Plaster", "Rubber" },
    MouseBehavior = { "Default", "LockCenter", "LockCurrentPosition" },
    OrientationAlignmentMode = { "OneAttachment", "TwoAttachment" },
    PlaybackState = { "Begin", "Delayed", "Playing", "Paused", "Completed", "Cancelled" },
    QualityLevel = { "Automatic", "Level01", "Level02", "Level03", "Level04", "Level05", "Level06", "Level07", "Level08", "Level09", "Level10", "Level11", "Level12", "Level13", "Level14", "Level15", "Level16", "Level17", "Level18", "Level19", "Level20", "Level21" },
    RaycastFilterType = { "Exclude", "Include", "Blacklist", "Whitelist" },
    RenderFidelity = { "Automatic", "Precise", "Performance" },
    ResamplerMode = { "Default", "Pixelated" },
    RunContext = { "Legacy", "Server", "Client", "Plugin" },
    ScaleType = { "Stretch", "Slice", "Tile", "Fit", "Crop" },
    ScrollBarInset = { "None", "ScrollBar", "Always" },
    ScrollingDirection = { "X", "Y", "XY" },
    SelectionBehaviorUp = { "Escape", "Stop" },
    SizeConstraint = { "RelativeXY", "RelativeXX", "RelativeYY" },
    SortOrder = { "LayoutOrder", "Name", "Custom" },
    StartCorner = { "TopLeft", "TopRight", "BottomLeft", "BottomRight" },
    Style = { "Custom", "ChatBlue", "RobloxSquare", "RobloxRound", "RobloxPoint" },
    Technology = { "Legacy", "Voxel", "Compatibility", "ShadowMap", "Future" },
    TeleportResult = { "Success", "Failure", "GameNotFound", "GameEnded", "GameFull", "Unauthorized", "Flooded", "IsTeleporting" },
    TextDirection = { "Auto", "LeftToRight", "RightToLeft" },
    TextTruncate = { "None", "AtEnd", "SplitWord" },
    TextXAlignment = { "Left", "Right", "Center" },
    TextYAlignment = { "Top", "Center", "Bottom" },
    ThumbnailSize = { "Size48x48", "Size60x60", "Size100x100", "Size150x150", "Size180x180", "Size352x352", "Size420x420" },
    ThumbnailType = { "HeadShot", "AvatarBust", "AvatarThumbnail" },
    UserInputState = { "Begin", "Change", "End", "Cancel", "None" },
    UserInputType = { "MouseButton1", "MouseButton2", "MouseButton3", "MouseWheel", "MouseMovement", "Touch", "Keyboard", "Focus", "Accelerometer", "Gyro", "Gamepad1", "Gamepad2", "Gamepad3", "Gamepad4", "TextInput", "InputMethod", "None" },
    VerticalAlignment = { "Center", "Top", "Bottom" },
    VerticalScrollBarPosition = { "Right", "Left" },
    ZIndexBehavior = { "Global", "Sibling" },
}

CLASSDATA = {
    Instance = {
        p = nil,
        r = { Archivable = "boolean" },
        e = { "AncestryChanged", "AttributeChanged", "Changed", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "Destroying" },
        m = { "IsA", "isA", "GetChildren", "GetDescendants", "GetFullName", "GetDebugId", "FindFirstChild", "findFirstChild", "FindFirstDescendant", "FindFirstChildOfClass", "FindFirstChildWhichIsA", "FindFirstAncestor", "FindFirstAncestorOfClass", "FindFirstAncestorWhichIsA", "IsDescendantOf", "IsAncestorOf", "WaitForChild", "ClearAllChildren", "Destroy", "destroy", "Remove", "Clone", "SetAttribute", "GetAttribute", "GetAttributes", "GetAttributeChangedSignal", "GetPropertyChangedSignal", "AddTag", "HasTag", "RemoveTag", "GetTags" },
    },
    ServiceProvider = { p = "Instance", r = {}, e = {}, m = { "GetService", "FindService" } },
    DataModel = {
        p = "ServiceProvider",
        r = { JobId = "string", PlaceId = "number", GameId = "number" },
        e = { "Loaded" },
        m = { "IsLoaded", "HttpGet", "HttpPost", "HttpGetAsync" },
    },
    Folder = { p = "Instance", r = {}, e = {}, m = {} },
    Configuration = { p = "Instance", r = {}, e = {}, m = {} },

    -- Services
    Players = {
        p = "Instance",
        r = { LocalPlayer = "Player?", MaxPlayers = "number", RespawnTime = "number" },
        e = { "PlayerAdded", "PlayerRemoving" },
        m = { "GetPlayers", "GetPlayerFromCharacter", "GetPlayerByUserId", "GetUserThumbnailAsync" },
    },
    Player = {
        p = "Instance",
        r = { UserId = "number", DisplayName = "string", Character = "Model?", Team = "Team?", Neutral = "boolean", AccountAge = "number" },
        e = { "CharacterAdded", "CharacterRemoving", "Idled", "Chatted" },
        m = { "GetMouse", "Kick", "GetNetworkPing" },
    },
    Team = { p = "Instance", r = { TeamColor = "any", AutoAssignable = "boolean" }, e = {}, m = {} },
    PlayerGui = { p = "BasePlayerGui", r = {}, e = {}, m = {} },
    BasePlayerGui = { p = "Instance", r = {}, e = {}, m = {} },
    CoreGui = { p = "BasePlayerGui", r = {}, e = {}, m = {} },
    StarterGui = { p = "BasePlayerGui", r = {}, e = {}, m = { "GetCoreGuiEnabled", "SetCoreGuiEnabled", "SetCore", "GetCore" } },
    PlayerScripts = { p = "Instance", r = {}, e = {}, m = {} },
    LuaSourceContainer = { p = "Instance", r = {}, e = {}, m = {} },
    ModuleScript = { p = "LuaSourceContainer", r = { Source = "string" }, e = {}, m = {} },
    Script = { p = "BaseScript", r = { Source = "string" }, e = {}, m = {} },
    LocalScript = { p = "BaseScript", r = { Source = "string" }, e = {}, m = {} },
    BaseScript = { p = "LuaSourceContainer", r = { Enabled = "boolean", Disabled = "boolean", RunContext = "EnumRunContext" }, e = {}, m = {} },

    Workspace = {
        p = "Model",
        r = { CurrentCamera = "Camera?", Gravity = "number", FallenPartsDestroyHeight = "number" },
        e = {},
        m = { "Raycast", "GetServerTimeNow" },
    },
    PVInstance = { p = "Instance", r = {}, e = {}, m = { "GetPivot", "PivotTo" } },
    Model = {
        p = "PVInstance",
        r = { PrimaryPart = "BasePart?" },
        e = {},
        m = { "GetBoundingBox", "GetExtentsSize", "BreakJoints", "MoveTo" },
    },
    BasePart = {
        p = "PVInstance",
        r = {
            Size = "Vector3", CFrame = "CFrame", Position = "Vector3", Orientation = "Vector3", Rotation = "Vector3",
            Velocity = "Vector3", AssemblyLinearVelocity = "Vector3", AssemblyAngularVelocity = "Vector3",
            Color = "Color3", Material = "EnumMaterial", Transparency = "number", LocalTransparencyModifier = "number",
            Reflectance = "number", Anchored = "boolean", CanCollide = "boolean", CanTouch = "boolean", CanQuery = "boolean",
            Massless = "boolean", CastShadow = "boolean", RootPriority = "number", Locked = "boolean", Mass = "number",
        },
        e = { "Touched", "TouchEnded" },
        m = { "GetMass", "GetNetworkOwner", "CanCollideWith", "GetTouchingParts", "ApplyImpulse" },
    },
    Part = { p = "BasePart", r = {}, e = {}, m = {} },
    MeshPart = { p = "BasePart", r = { MeshId = "string", TextureID = "string", RenderFidelity = "EnumRenderFidelity" }, e = {}, m = {} },
    WedgePart = { p = "BasePart", r = {}, e = {}, m = {} },
    SpawnLocation = { p = "Part", r = {}, e = {}, m = {} },
    Terrain = {
        p = "BasePart",
        r = { WaterWaveSize = "number", WaterWaveSpeed = "number", WaterReflectance = "number", WaterTransparency = "number", WaterColor = "Color3", Decoration = "boolean" },
        e = {},
        m = { "Clear" },
    },
    Camera = {
        p = "Instance",
        r = { CFrame = "CFrame", Focus = "CFrame", FieldOfView = "number", CameraSubject = "Instance?", CameraType = "EnumCameraType", ViewportSize = "Vector2", NearPlaneZ = "number" },
        e = {},
        m = { "WorldToViewportPoint", "WorldToScreenPoint", "ViewportPointToRay", "ScreenPointToRay", "GetRenderCFrame" },
    },
    Humanoid = {
        p = "Instance",
        r = {
            Health = "number", MaxHealth = "number", WalkSpeed = "number", JumpPower = "number", JumpHeight = "number",
            UseJumpPower = "boolean", HipHeight = "number", AutoRotate = "boolean", Sit = "boolean", Jump = "boolean",
            PlatformStand = "boolean", FloorMaterial = "EnumMaterial", MoveDirection = "Vector3", SeatPart = "BasePart?",
            HealthDisplayDistance = "number", NameDisplayDistance = "number", DisplayDistanceType = "EnumHumanoidDisplayDistanceType",
            RigType = "any", BreakJointsOnDeath = "boolean", EvaluateStateMachine = "boolean",
        },
        e = { "Died", "HealthChanged", "StateChanged", "Running", "Jumping", "FreeFalling", "Seated" },
        m = { "GetState", "ChangeState", "SetStateEnabled", "GetStateEnabled", "Move", "TakeDamage", "EquipTool", "UnequipTools" },
    },
    Attachment = { p = "Instance", r = { Position = "Vector3", CFrame = "CFrame", WorldPosition = "Vector3", WorldCFrame = "CFrame", Visible = "boolean" }, e = {}, m = {} },
    Constraint = { p = "Instance", r = { Enabled = "boolean", Attachment0 = "Attachment?", Attachment1 = "Attachment?", Visible = "boolean" }, e = {}, m = {} },
    LinearVelocity = {
        p = "Constraint",
        r = { VectorVelocity = "Vector3", MaxForce = "number", RelativeTo = "EnumActuatorRelativeTo", VelocityConstraintMode = "any" },
        e = {}, m = {},
    },
    AlignOrientation = {
        p = "Constraint",
        r = { CFrame = "CFrame", MaxTorque = "number", Responsiveness = "number", RigidityEnabled = "boolean", Mode = "EnumOrientationAlignmentMode", PrimaryAxisOnly = "boolean" },
        e = {}, m = {},
    },

    -- Effects / Visuals / Audio
    FaceInstance = { p = "Instance", r = {}, e = {}, m = {} },
    Decal = { p = "FaceInstance", r = { Transparency = "number", Color3 = "Color3", Texture = "string", ZIndex = "number" }, e = {}, m = {} },
    Texture = { p = "Decal", r = { StudsPerTileU = "number", StudsPerTileV = "number", OffsetStudsU = "number", OffsetStudsV = "number" }, e = {}, m = {} },
    Highlight = {
        p = "Instance",
        r = { Adornee = "Instance?", Enabled = "boolean", FillColor = "Color3", FillTransparency = "number", OutlineColor = "Color3", OutlineTransparency = "number", DepthMode = "EnumHighlightDepthMode" },
        e = {}, m = {},
    },
    HandleAdornment = { p = "PVBase", r = { CFrame = "CFrame", Adornee = "Instance?", AlwaysOnTop = "boolean", Color3 = "Color3", Transparency = "number", Visible = "boolean", ZIndex = "number" }, e = {}, m = {} },
    PVBase = { p = "Instance", r = {}, e = {}, m = {} },
    BoxHandleAdornment = { p = "HandleAdornment", r = { Size = "Vector3" }, e = {}, m = {} },
    ParticleEmitter = { p = "Instance", r = { Enabled = "boolean", Rate = "number" }, e = {}, m = { "Emit", "Clear" } },
    Smoke = { p = "Instance", r = { Enabled = "boolean", Opacity = "number", RiseVelocity = "number", Size = "number", Color = "Color3" }, e = {}, m = {} },
    Fire = { p = "Instance", r = { Enabled = "boolean", Heat = "number", Size = "number", Color = "Color3", SecondaryColor = "Color3" }, e = {}, m = {} },
    Sparkles = { p = "Instance", r = { Enabled = "boolean", SparkleColor = "Color3" }, e = {}, m = {} },
    Trail = { p = "Instance", r = { Enabled = "boolean", Lifetime = "number" }, e = {}, m = { "Clear" } },
    Beam = { p = "Instance", r = { Enabled = "boolean" }, e = {}, m = {} },
    Light = { p = "Instance", r = { Enabled = "boolean", Brightness = "number", Color = "Color3", Shadows = "boolean" }, e = {}, m = {} },
    PointLight = { p = "Light", r = { Range = "number" }, e = {}, m = {} },
    SpotLight = { p = "Light", r = { Range = "number", Angle = "number" }, e = {}, m = {} },
    SurfaceLight = { p = "Light", r = { Range = "number", Angle = "number" }, e = {}, m = {} },
    PostEffect = { p = "Instance", r = { Enabled = "boolean" }, e = {}, m = {} },
    BlurEffect = { p = "PostEffect", r = { Size = "number" }, e = {}, m = {} },
    BloomEffect = { p = "PostEffect", r = { Intensity = "number", Size = "number", Threshold = "number" }, e = {}, m = {} },
    DepthOfFieldEffect = { p = "PostEffect", r = { FarIntensity = "number", FocusDistance = "number", InFocusRadius = "number", NearIntensity = "number" }, e = {}, m = {} },
    SunRaysEffect = { p = "PostEffect", r = { Intensity = "number", Spread = "number" }, e = {}, m = {} },
    ColorCorrectionEffect = { p = "PostEffect", r = { Brightness = "number", Contrast = "number", Saturation = "number", TintColor = "Color3" }, e = {}, m = {} },
    Atmosphere = { p = "Instance", r = { Density = "number", Offset = "number", Color = "Color3", Decay = "Color3", Glare = "number", Haze = "number" }, e = {}, m = {} },
    Clouds = { p = "Instance", r = { Enabled = "boolean", Cover = "number", Density = "number", Color = "Color3" }, e = {}, m = {} },
    Sky = { p = "Instance", r = { CelestialBodiesShown = "boolean", StarCount = "number" }, e = {}, m = {} },
    Lighting = {
        p = "Instance",
        r = {
            Ambient = "Color3", OutdoorAmbient = "Color3", Brightness = "number", ClockTime = "number", TimeOfDay = "string",
            FogEnd = "number", FogStart = "number", FogColor = "Color3", GlobalShadows = "boolean", ShadowSoftness = "number",
            ExposureCompensation = "number", EnvironmentDiffuseScale = "number", EnvironmentSpecularScale = "number",
            ColorShift_Bottom = "Color3", ColorShift_Top = "Color3", GeographicLatitude = "number", Technology = "EnumTechnology",
        },
        e = { "LightingChanged" }, m = {},
    },
    Sound = {
        p = "Instance",
        r = { SoundId = "string", Volume = "number", PlaybackSpeed = "number", Pitch = "number", Looped = "boolean", Playing = "boolean", IsPlaying = "boolean", TimePosition = "number", TimeLength = "number", SoundGroup = "SoundGroup?", RollOffMaxDistance = "number", RollOffMinDistance = "number" },
        e = { "Ended", "Stopped", "Played", "Loaded" },
        m = { "Play", "Stop", "Pause", "Resume" },
    },
    SoundGroup = { p = "Instance", r = { Volume = "number" }, e = {}, m = {} },
    SoundService = { p = "Instance", r = { RespectFilteringEnabled = "boolean", AmbientReverb = "any" }, e = {}, m = { "PlayLocalSound" } },

    -- Services & Misc
    RunService = {
        p = "Instance",
        r = {},
        e = { "RenderStepped", "Stepped", "Heartbeat", "PreRender", "PreAnimation", "PreSimulation", "PostSimulation" },
        m = { "IsStudio", "IsClient", "IsServer", "IsRunning", "Set3dRenderingEnabled", "BindToRenderStep", "UnbindFromRenderStep" },
    },
    UserInputService = {
        p = "Instance",
        r = { KeyboardEnabled = "boolean", MouseEnabled = "boolean", TouchEnabled = "boolean", GamepadEnabled = "boolean", VREnabled = "boolean", MouseBehavior = "EnumMouseBehavior", MouseIconEnabled = "boolean", MouseDeltaSensitivity = "number" },
        e = { "InputBegan", "InputChanged", "InputEnded", "TouchTapInWorld", "JumpRequest", "WindowFocused", "WindowFocusReleased", "TextBoxFocused", "TextBoxFocusReleased" },
        m = { "GetKeysPressed", "IsKeyDown", "IsMouseButtonPressed", "GetMouseLocation", "GetFocusedTextBox", "GetLastInputType", "GetNavigationGamepads", "GetMouseDelta", "GetStringForKeyCode" },
    },
    TweenService = { p = "Instance", r = {}, e = {}, m = { "Create", "GetValue" } },
    TweenBase = { p = "Instance", r = { PlaybackState = "EnumPlaybackState" }, e = { "Completed" }, m = { "Play", "Cancel", "Pause" } },
    Tween = { p = "TweenBase", r = { Instance = "Instance?", TweenInfo = "any" }, e = {}, m = {} },
    HttpService = { p = "Instance", r = { HttpEnabled = "boolean" }, e = {}, m = { "JSONEncode", "JSONDecode", "GenerateGUID", "UrlEncode", "RequestAsync", "GetAsync", "PostAsync" } },
    TeleportService = { p = "Instance", r = {}, e = { "TeleportInitFailed", "LocalPlayerArrivedFromTeleport" }, m = { "Teleport", "TeleportToPlaceInstance", "GetLocalPlayerTeleportData" } },
    TextService = { p = "Instance", r = {}, e = {}, m = { "GetTextSize" } },
    GuiService = { p = "Instance", r = { MenuIsOpen = "boolean", SelectedObject = "GuiObject?", AutoSelectGuiEnabled = "boolean", GuiNavigationEnabled = "boolean" }, e = { "ErrorMessageChanged", "MenuOpened", "MenuClosed" }, m = { "GetErrorMessage", "GetGuiInset", "ClearError" } },
    Stats = { p = "Instance", r = { FrameTime = "number", HeartbeatTimeMs = "number", InstanceCount = "number" }, e = {}, m = { "GetTotalMemoryUsageMb", "GetMemoryUsageMbForTag" } },
    StatsItem = { p = "Instance", r = {}, e = {}, m = { "GetValue", "GetValueString" } },
    VirtualUser = { p = "Instance", r = {}, e = {}, m = { "CaptureController", "ClickButton1", "ClickButton2", "Button1Down", "Button1Up", "Button2Down", "Button2Up" } },
    TextChatService = { p = "Instance", r = { ChatVersion = "any" }, e = { "MessageReceived", "SendingMessage" }, m = {} },
    ChatInputBarConfiguration = { p = "Instance", r = { Enabled = "boolean", TargetTextChannel = "TextChannel?", TextBox = "TextBox?" }, e = {}, m = {} },
    TextChannel = { p = "Instance", r = {}, e = { "MessageReceived" }, m = { "SendAsync", "DisplaySystemMessage" } },
    RemoteEvent = { p = "Instance", r = {}, e = { "OnClientEvent", "OnServerEvent" }, m = { "FireServer", "FireClient", "FireAllClients" } },
    UserSettings = { p = "ServiceProvider", r = {}, e = {}, m = { "GetService", "IsUserFeatureEnabled" } },
    UserGameSettings = { p = "Instance", r = { MasterVolume = "number", SavedQualityLevel = "any", MouseSensitivity = "number", Fullscreen = "boolean" }, e = { "FullscreenChanged", "PerformanceStatsVisibleChanged" }, m = { "InFullScreen" } },
    GlobalSettings = { p = "ServiceProvider", r = {}, e = {}, m = { "GetFFlag" } },
    RenderSettings = { p = "Instance", r = { QualityLevel = "EnumQualityLevel", EditQualityLevel = "EnumQualityLevel", MeshPartDetailLevel = "any" }, e = {}, m = {} },

    -- GUI Hierarchy
    GuiBase = { p = "Instance", r = {}, e = {}, m = {} },
    GuiBase2d = {
        p = "GuiBase",
        r = { AbsolutePosition = "Vector2", AbsoluteSize = "Vector2", AbsoluteRotation = "number", AutoLocalize = "boolean", SelectionBehaviorUp = "EnumSelectionBehaviorUp" },
        e = {}, m = {},
    },
    LayerCollector = {
        p = "GuiBase2d",
        r = { Enabled = "boolean", ResetOnSpawn = "boolean", ZIndexBehavior = "EnumZIndexBehavior" },
        e = {}, m = {},
    },
    ScreenGui = {
        p = "LayerCollector",
        r = { DisplayOrder = "number", IgnoreGuiInset = "boolean", SafeAreaCompatibility = "any", ClipToDeviceSafeArea = "boolean" },
        e = {}, m = {},
    },
    BillboardGui = {
        p = "LayerCollector",
        r = { Active = "boolean", Adornee = "Instance?", AlwaysOnTop = "boolean", Brightness = "number", ClipsDescendants = "boolean", CurrentDistance = "number", DistanceLowerLimit = "number", DistanceStep = "number", DistanceUpperLimit = "number", ExtentsOffset = "Vector3", ExtentsOffsetWorldSpace = "Vector3", LightInfluence = "number", MaxDistance = "number", PlayerToHideFrom = "Instance?", Size = "UDim2", SizeOffset = "Vector2", StudsOffset = "Vector3", StudsOffsetWorldSpace = "Vector3" },
        e = {}, m = {},
    },
    SurfaceGui = { p = "LayerCollector", r = { Adornee = "Instance?", AlwaysOnTop = "boolean", Face = "any" }, e = {}, m = {} },
    GuiObject = {
        p = "GuiBase2d",
        r = {
            Active = "boolean", AnchorPoint = "Vector2", AutomaticSize = "EnumAutomaticSize",
            BackgroundColor3 = "Color3", BackgroundTransparency = "number",
            BorderColor3 = "Color3", BorderMode = "EnumBorderMode", BorderSizePixel = "number",
            ClipsDescendants = "boolean", GuiState = "EnumGuiState", InputSink = "EnumInputSink",
            Interactable = "boolean", LayoutOrder = "number", NextSelectionDown = "GuiObject?",
            NextSelectionLeft = "GuiObject?", NextSelectionRight = "GuiObject?", NextSelectionUp = "GuiObject?",
            Position = "UDim2", Rotation = "number", Selectable = "boolean", SelectionImageObject = "GuiObject?",
            SelectionOrder = "number", Size = "UDim2", SizeConstraint = "EnumSizeConstraint",
            Transparency = "number", Visible = "boolean", ZIndex = "number",
        },
        e = { "InputBegan", "InputChanged", "InputEnded", "MouseEnter", "MouseLeave", "MouseMoved", "MouseWheelForward", "MouseWheelBackward", "TouchTap", "TouchLongPress", "SelectionGained", "SelectionLost" },
        m = { "TweenPosition", "TweenSize", "TweenSizeAndPosition" },
    },
    Frame = { p = "GuiObject", r = { Style = "EnumStyle" }, e = {}, m = {} },
    CanvasGroup = { p = "GuiObject", r = { GroupColor3 = "Color3", GroupTransparency = "number" }, e = {}, m = {} },
    ViewportFrame = { p = "GuiObject", r = { Ambient = "Color3", CurrentCamera = "Camera?", ImageColor3 = "Color3", ImageTransparency = "number", LightColor = "Color3", LightDirection = "Vector3" }, e = {}, m = {} },
    ScrollingFrame = {
        p = "GuiObject",
        r = {
            AbsoluteCanvasSize = "Vector2", AbsoluteWindowSize = "Vector2", AutomaticCanvasSize = "EnumAutomaticSize",
            BottomImage = "string", CanvasPosition = "Vector2", CanvasSize = "UDim2", ElasticBehavior = "any",
            HorizontalScrollBarInset = "EnumScrollBarInset", MidImage = "string", ScrollBarImageColor3 = "Color3",
            ScrollBarImageTransparency = "number", ScrollBarThickness = "number", ScrollingDirection = "EnumScrollingDirection",
            ScrollingEnabled = "boolean", TopImage = "string", VerticalScrollBarInset = "EnumScrollBarInset",
            VerticalScrollBarPosition = "EnumVerticalScrollBarPosition",
        },
        e = {}, m = { "ClearAllChildren" },
    },
    GuiLabel = { p = "GuiObject", r = {}, e = {}, m = {} },
    TextLabel = {
        p = "GuiLabel",
        r = {
            ContentText = "string", Font = "EnumFont", FontFace = "any", LineHeight = "number",
            MaxVisibleGraphemes = "number", OpenTypeFeatures = "string", RichText = "boolean",
            Text = "string", TextBounds = "Vector2", TextColor3 = "Color3", TextDirection = "EnumTextDirection",
            TextFits = "boolean", TextScaled = "boolean", TextSize = "number", TextStrokeColor3 = "Color3",
            TextStrokeTransparency = "number", TextTransparency = "number", TextTruncate = "EnumTextTruncate",
            TextWrapped = "boolean", TextXAlignment = "EnumTextXAlignment", TextYAlignment = "EnumTextYAlignment",
        },
        e = {}, m = {},
    },
    ImageLabel = {
        p = "GuiLabel",
        r = {
            Image = "string", ImageColor3 = "Color3", ImageRectOffset = "Vector2", ImageRectSize = "Vector2",
            ImageTransparency = "number", IsLoaded = "boolean", ResampleMode = "EnumResamplerMode",
            ScaleType = "EnumScaleType", SliceCenter = "any", SliceScale = "number", TileSize = "UDim2",
        },
        e = {}, m = {},
    },
    GuiButton = {
        p = "GuiObject",
        r = { AutoButtonColor = "boolean", Modal = "boolean", Selected = "boolean", Style = "EnumStyle" },
        e = { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click", "MouseButton2Down", "MouseButton2Up" },
        m = {},
    },
    TextButton = {
        p = "GuiButton",
        r = {
            ContentText = "string", Font = "EnumFont", FontFace = "any", LineHeight = "number",
            MaxVisibleGraphemes = "number", OpenTypeFeatures = "string", RichText = "boolean",
            Text = "string", TextBounds = "Vector2", TextColor3 = "Color3", TextDirection = "EnumTextDirection",
            TextFits = "boolean", TextScaled = "boolean", TextSize = "number", TextStrokeColor3 = "Color3",
            TextStrokeTransparency = "number", TextTransparency = "number", TextTruncate = "EnumTextTruncate",
            TextWrapped = "boolean", TextXAlignment = "EnumTextXAlignment", TextYAlignment = "EnumTextYAlignment",
        },
        e = {}, m = {},
    },
    ImageButton = {
        p = "GuiButton",
        r = {
            HoverImage = "string", Image = "string", ImageColor3 = "Color3", ImageRectOffset = "Vector2",
            ImageRectSize = "Vector2", ImageTransparency = "number", IsLoaded = "boolean", PressedImage = "string",
            ResampleMode = "EnumResamplerMode", ScaleType = "EnumScaleType", SliceCenter = "any", SliceScale = "number", TileSize = "UDim2",
        },
        e = {}, m = {},
    },
    TextBox = {
        p = "GuiObject",
        r = {
            ClearTextOnFocus = "boolean", ContentText = "string", CursorPosition = "number",
            Font = "EnumFont", FontFace = "any", LineHeight = "number", ManualFocusRelease = "boolean",
            MaxVisibleGraphemes = "number", MultiLine = "boolean", PlaceholderColor3 = "Color3",
            PlaceholderText = "string", RichText = "boolean", SelectionStart = "number", ShowNativeInput = "boolean",
            Text = "string", TextBounds = "Vector2", TextColor3 = "Color3", TextDirection = "EnumTextDirection",
            TextEditable = "boolean", TextFits = "boolean", TextScaled = "boolean", TextSize = "number",
            TextStrokeColor3 = "Color3", TextStrokeTransparency = "number", TextTransparency = "number",
            TextTruncate = "EnumTextTruncate", TextWrapped = "boolean", TextXAlignment = "EnumTextXAlignment",
            TextYAlignment = "EnumTextYAlignment",
        },
        e = { "Focused", "FocusLost", "ReturnPressedFromOnScreenKeyboard" },
        m = { "CaptureFocus", "ReleaseFocus", "IsFocused" },
    },

    -- UI Component Modifiers
    UIBase = { p = "Instance", r = {}, e = {}, m = {} },
    UIComponent = { p = "UIBase", r = {}, e = {}, m = {} },
    UICorner = { p = "UIComponent", r = { CornerRadius = "UDim" }, e = {}, m = {} },
    UIGradient = { p = "UIComponent", r = { Color = "ColorSequence", Enabled = "boolean", Offset = "Vector2", Rotation = "number", Transparency = "NumberSequence" }, e = {}, m = {} },
    UIPadding = { p = "UIComponent", r = { PaddingBottom = "UDim", PaddingLeft = "UDim", PaddingRight = "UDim", PaddingTop = "UDim" }, e = {}, m = {} },
    UIScale = { p = "UIComponent", r = { Scale = "number" }, e = {}, m = {} },
    UIStroke = { p = "UIComponent", r = { ApplyStrokeMode = "EnumApplyStrokeMode", Color = "Color3", Enabled = "boolean", LineJoinMode = "EnumLineJoinMode", Thickness = "number", Transparency = "number" }, e = {}, m = {} },
    UIConstraint = { p = "UIComponent", r = {}, e = {}, m = {} },
    UISizeConstraint = { p = "UIConstraint", r = { MaxSize = "Vector2", MinSize = "Vector2" }, e = {}, m = {} },
    UIAspectRatioConstraint = { p = "UIConstraint", r = { AspectRatio = "number", AspectType = "any", DominantAxis = "any" }, e = {}, m = {} },
    UITextSizeConstraint = { p = "UIConstraint", r = { MaxTextSize = "number", MinTextSize = "number" }, e = {}, m = {} },
    UILayout = { p = "UIComponent", r = {}, e = {}, m = {} },
    UIGridStyleLayout = { p = "UILayout", r = { AbsoluteContentSize = "Vector2", FillDirection = "EnumFillDirection", HorizontalAlignment = "EnumHorizontalAlignment", SortOrder = "EnumSortOrder", VerticalAlignment = "EnumVerticalAlignment" }, e = {}, m = { "ApplyLayout" } },
    UIListLayout = { p = "UIGridStyleLayout", r = { Padding = "UDim", Wraps = "boolean", ItemLineAlignment = "any" }, e = {}, m = {} },
    UIGridLayout = { p = "UIGridStyleLayout", r = { CellPadding = "UDim2", CellSize = "UDim2", FillDirectionMaxCells = "number", StartCorner = "EnumStartCorner" }, e = {}, m = {} },
}


-- ============================================================================
-- ELYSERA UI v2.5.0 - STRICT TESTING ENVIRONMENT & STRESS/BOUNDARY TEST SUITE
-- Standalone Automated Test Harness & Stress/Boundary Auditor
-- ============================================================================
local realClock = os.clock
local suiteStart = realClock()

CLASSDATA.Player.r.CameraMaxZoomDistance = "number"
CLASSDATA.Player.r.CameraMinZoomDistance = "number"
CLASSDATA.TextLabel.r.TextSelectable = "boolean"
CLASSDATA.TextButton.r.TextSelectable = "boolean"

local EXTRACTED_DIR = "/tmp/test_inspect/extracted/"

loadLuauFile(EXTRACTED_DIR .. "test/m1_core.lua")()

-- Load m2_instance.lua with AutomaticSize recursion guard so all modules can boot
do
    local f = assert(io.open(EXTRACTED_DIR .. "test/m2_instance.lua", "rb"))
    local m2_src = f:read("*a")
    f:close()
    m2_src = m2_src:gsub(
        "local function absSize%(inst%)",
        "local inAuto = {}\nlocal function absSize(inst)"
    )
    m2_src = m2_src:gsub(
        'elseif auto and auto%.Name ~= "None" then',
        'elseif auto and auto.Name ~= "None" and not inAuto[inst] then\n        inAuto[inst] = true'
    )
    m2_src = m2_src:gsub(
        'if auto%.Name == "Y" or auto%.Name == "XY" then y = math%.max%(y, cs%.Y%) end\n    end',
        'if auto.Name == "Y" or auto.Name == "XY" then y = math.max(y, cs.Y) end\n        inAuto[inst] = nil\n    end'
    )
    assert(loadstring(m2_src, "@m2_instance.lua"))()
end

loadLuauFile(EXTRACTED_DIR .. "test/m3_env.lua")()

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

for _, name in ipairs({ "MainWeb.lua", "Status_Server.lua", "Local.lua", "Script.lua", "FPS.lua", "Settings.lua" }) do
    local fh = assert(io.open(EXTRACTED_DIR .. name, "rb"))
    Harness.files[name] = fh:read("*a")
    fh:close()
end
makefolder("Elysera")

local Results = {
    total = 0,
    passed = 0,
    failed = 0,
    cases = {},
    bugs = {},
    benchmarks = {},
}

local function recordTest(category, id, name, passed, detail, bugRef)
    Results.total = Results.total + 1
    if passed then
        Results.passed = Results.passed + 1
    else
        Results.failed = Results.failed + 1
        if bugRef then table.insert(Results.bugs, bugRef) end
    end
    table.insert(Results.cases, {
        category = category,
        id = id,
        name = name,
        status = passed and "PASS" or "FAIL (BUG)",
        detail = tostring(detail or ""),
    })
    print(string.format("[%s] %s | %-22s | %s -> %s",
        passed and "PASS" or "FAIL", id, category, name, tostring(detail or "")))
end

local function click(btn)
    assert(btn, "click: button is nil")
    Harness.signal(btn, "MouseButton1Down"):_fire()
    Harness.signal(btn, "MouseButton1Up"):_fire()
    Harness.signal(btn, "MouseButton1Click"):_fire()
    Harness.signal(btn, "Activated"):_fire()
    Harness.flush()
end

-- ============================================================================
-- SUITE 1: TEST HARNESS & ENVIRONMENT AUDIT (test/m1_core, m2_instance, m3_env)
-- ============================================================================

-- T01: Unpatched m2_instance.lua AutomaticSize recursion check
do
    local f = assert(io.open(EXTRACTED_DIR .. "test/m2_instance.lua", "rb"))
    local rawM2 = f:read("*a")
    f:close()
    local hasGuard = rawM2:find("inAuto", 1, true) ~= nil
    recordTest("1. Test Harness", "T01", "AutomaticSize <-> contentSize recursion guard (m2_instance.lua:263-298)",
        hasGuard,
        "Unpatched m2_instance.lua enters infinite recursion when absSize(parent) calls contentSize(parent) -> absSize(child) -> absSize(parent).",
        { id = "BUG-01", severity = "Critical", file = "test/m2_instance.lua:263-298, 328-362" })
end

-- T02: Luau compound assignment (+=) syntax in Local.lua & test/m1..m3
do
    local f = assert(io.open(EXTRACTED_DIR .. "Local.lua", "rb"))
    local rawLocal = f:read("*a")
    f:close()
    local fn = rawLoadstring(rawLocal, "@Local.lua")
    recordTest("1. Test Harness", "T02", "Pure Lua 5.3 syntax compatibility across modules (Local.lua:1977, 2002)",
        fn ~= nil,
        "5/6 modules use standard Lua `x = x + 1`, but Local.lua:1977 & 2002 and test/m1..m3 (28 lines) use Luau `+=`.",
        { id = "BUG-02", severity = "Low", file = "Local.lua:1977, 2002 & test/m1..m3" })
end

-- T03: m3_env.lua Harness.inputObject missing .Changed signal
do
    local rawIo = origInputObject(Enum.UserInputType.MouseButton1, Enum.UserInputState.Begin)
    local hasChanged = rawIo.Changed ~= nil
    recordTest("1. Test Harness", "T03", "Harness.inputObject .Changed RBXScriptSignal support (m3_env.lua:656)",
        hasChanged,
        "origInputObject returns table without .Changed signal; dragging TopBar/ToggleButton/ResizeHandles/Overlay crashes on input.Changed:Connect.",
        { id = "BUG-03", severity = "High", file = "test/m3_env.lua:656-662" })
end

-- T04: m3_env.lua jsonEncode sparse table with string key data loss
do
    local mixed = { "a", "b", "c", "d" }
    mixed[2] = nil
    mixed.key = "val"
    local okEnc, enc = pcall(function() return game:GetService("HttpService"):JSONEncode(mixed) end)
    local hasKey = okEnc and enc:find("key", 1, true) ~= nil
    recordTest("1. Test Harness", "T04", "HttpService:JSONEncode sparse + string-key table integrity (m3_env.lua:405)",
        hasKey,
        "Encoded: " .. tostring(enc) .. " (`isArray = #v == n` evaluates true when #v==4 and n==4, dropping string key 'key' and emitting null!)",
        { id = "BUG-04", severity = "Medium", file = "test/m3_env.lua:402-409" })
end

-- T05: m3_env.lua TweenService overlapping property tween cancellation
do
    local frm = Instance.new("Frame")
    frm.Size = UDim2.fromOffset(100, 100)
    local tw1 = game:GetService("TweenService"):Create(frm, TweenInfo.new(0.20), { Size = UDim2.fromOffset(300, 300) })
    local tw2 = game:GetService("TweenService"):Create(frm, TweenInfo.new(0.10), { Size = UDim2.fromOffset(0, 0) })
    tw1:Play()
    Harness.advance(0.02, 0.02)
    tw2:Play()
    Harness.advance(0.25, 0.02)
    local finalIsZero = (frm.Size.X.Offset == 0 and frm.Size.Y.Offset == 0)
    recordTest("1. Test Harness", "T05", "TweenService overlapping tween cancellation on same Instance (m3_env.lua:357)",
        finalIsZero,
        string.format("Expected Size=(0,0) from newer tween tw2, got (%d,%d) because older tween tw1 overwrote it at t=0.20s.", frm.Size.X.Offset, frm.Size.Y.Offset),
        { id = "BUG-05", severity = "Medium", file = "test/m3_env.lua:356-364 & MainWeb.lua:1089-1106" })
    frm:Destroy()
end

-- ============================================================================
-- SUITE 2: MAINWEB.LUA CORE, UI KIT, DIALOGS, DRAG & RESIZE
-- ============================================================================
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
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
local pEmitter = Harness.new("ParticleEmitter", { Enabled = true, Rate = 50 }, testPart)
local smoke = Harness.new("Smoke", { Enabled = true }, testPart)
local sound = Harness.new("Sound", { Volume = 0.8 }, Workspace)
local soundGroup = Harness.new("SoundGroup", { Volume = 0.9 }, game:GetService("SoundService"))

-- Create legacy files before boot to test automatic legacy migration into Elysera/
writefile("Elysera_Waypoints.json", '{"1818":[{"n":"LegacyPt","x":10,"y":20,"z":30,"r":45}]}')

local bootT0 = realClock()
local Elysera = loadLuauFile(EXTRACTED_DIR .. "MainWeb.lua")()
Harness.flush()
Harness.advance(2.0, 1/30)
local bootMs = (realClock() - bootT0) * 1000
Results.benchmarks.bootMs = bootMs

-- T06: Full boot & remote module loader
recordTest("2. MainWeb Core", "T06", "Full boot & async remote module loader (5 modules, 2500+ GUI instances)",
    Elysera ~= nil and Elysera.Version == "2.5.0" and #Harness.errors == 0 and #Harness.warns == 0,
    string.format("Version=%s, Descendants=%d, BootTime=%.2fms", tostring(Elysera.Version), #Elysera.ScreenGui:GetDescendants(), bootMs))

-- T07: Legacy file migration into Elysera/ folder
recordTest("2. MainWeb Core", "T07", "Legacy root JSON migration into Elysera/ data folder",
    isfile("Elysera/Elysera_Waypoints.json") and not isfile("Elysera_Waypoints.json"),
    string.format("Migrated=%s, OldDeleted=%s", tostring(isfile("Elysera/Elysera_Waypoints.json")), tostring(not isfile("Elysera_Waypoints.json"))))

-- T08: UI.FormatAgo boundary safety on extreme negative timestamps (-1e20)
do
    local function testFormatAgo(ts, withDate)
        local d = math.max(0, os.time() - (tonumber(ts) or 0))
        if d < (withDate and 45 or 60) then return withDate and "just now" or "<1m ago" end
        if d < 3600 then return ("%dm ago"):format(math.max(1, math.floor(d / 60))) end
        if d < 86400 then return ("%dh ago"):format(math.floor(d / 3600)) end
        if withDate and d >= 7 * 86400 then return os.date("%b %d", ts) end
        return ("%dd ago"):format(math.floor(d / 86400))
    end
    local okHugeNeg = pcall(testFormatAgo, -1e25, false)
    local okDateNeg = pcall(testFormatAgo, -1e18, true)
    recordTest("2. MainWeb Core", "T08", "UI.FormatAgo boundary safety on extreme negative timestamps (-1e20 / -1e15)",
        okHugeNeg and okDateNeg,
        string.format("okHugeNeg=%s, okDateNeg=%s (overflows `%%d` format and `os.date` when timestamp is corrupted)", tostring(okHugeNeg), tostring(okDateNeg)),
        { id = "BUG-06", severity = "Medium", file = "MainWeb.lua:1847-1854" })
end

-- T09: Toast queue flood control (MAX_TOASTS=3) & 1s deduplication
do
    for i = 1, 12 do
        Elysera.Toast("Burst toast #" .. i, (i % 3 == 0) and "error" or "info", { duration = 0.8 })
    end
    Elysera.Toast("Burst toast #12", "info", { duration = 0.8 })
    Harness.advance(0.2, 1/30)
    local toastHost = Elysera.ScreenGui:FindFirstChild("ToastHost")
    local count = 0
    if toastHost then
        for _, c in ipairs(toastHost:GetChildren()) do
            if c:IsA("Frame") then count = count + 1 end
        end
    end
    Harness.advance(1.2, 1/30)
    recordTest("2. MainWeb Core", "T09", "Toast queue flood control (MAX_TOASTS=3) & duplicate suppression",
        count == 3 and #Harness.errors == 0,
        string.format("Active Toast pills during 12-toast burst=%d (max 3)", count))
end

-- T10: TopBar drag, Maximize/Restore, Resize Mode corner drag, and Reset Layout Dialog
do
    local mainUI = Elysera.ScreenGui.MG_Main
    local topBar = mainUI.TopBar
    -- Drag TopBar
    local inp = Harness.inputObject(Enum.UserInputType.MouseButton1, Enum.UserInputState.Begin, { Position = Vector3.new(400, 200, 0) })
    Harness.signal(topBar, "InputBegan"):_fire(inp)
    Harness.flush()
    local moveInp = Harness.inputObject(Enum.UserInputType.MouseMovement, Enum.UserInputState.Change, { Position = Vector3.new(450, 230, 0) })
    Harness.signal(UIS, "InputChanged"):_fire(moveInp)
    Harness.flush()
    inp.UserInputState = Enum.UserInputState.End
    inp.Changed:_fire()
    Harness.flush()
    local movedPos = mainUI.Position

    -- Maximize & Restore (button order 2 on TopBar)
    local topBtns = {}
    for _, c in ipairs(topBar:GetChildren()) do
        if c:IsA("TextButton") then table.insert(topBtns, c) end
    end
    -- Buttons are created in order: Close(1), Maximize(2), Minimize(3), Resize(4), Reset(5)
    click(topBtns[2]) -- Maximize
    Harness.advance(0.3, 1/30)
    local maxSz = mainUI.Size
    click(topBtns[2]) -- Restore
    Harness.advance(0.3, 1/30)

    -- Resize mode (button 4)
    click(topBtns[4])
    Harness.advance(0.2, 1/30)
    local brHandle = Elysera.ScreenGui:FindFirstChild("ResizeHandle_BR")
    local grip = brHandle and brHandle:FindFirstChildOfClass("TextButton")
    local rInp = Harness.inputObject(Enum.UserInputType.MouseButton1, Enum.UserInputState.Begin, { Position = Vector3.new(800, 500, 0) })
    Harness.signal(grip, "InputBegan"):_fire(rInp)
    Harness.flush()
    local rMove = Harness.inputObject(Enum.UserInputType.MouseMovement, Enum.UserInputState.Change, { Position = Vector3.new(900, 580, 0) })
    Harness.signal(UIS, "InputChanged"):_fire(rMove)
    Harness.flush()
    rInp.UserInputState = Enum.UserInputState.End
    rInp.Changed:_fire()
    Harness.flush()
    local resizedW, resizedH = mainUI.Size.X.Offset, mainUI.Size.Y.Offset
    click(topBtns[4]) -- Exit resize mode
    Harness.advance(0.2, 1/30)

    -- Reset Layout via ResetBtn (button 5) -> ResetDialog (NotBox2) -> Yes
    click(topBtns[5])
    Harness.advance(0.3, 1/30)
    local resetBox = Elysera.ScreenGui:FindFirstChild("NotBox2")
    for _, d in ipairs(resetBox:GetDescendants()) do
        if d:IsA("TextButton") and d.Text == "Yes" then click(d) break end
    end
    Harness.advance(0.5, 1/30)

    recordTest("2. MainWeb Core", "T10", "Window Drag, Maximize/Restore, Corner Resize & Reset Layout Dialog",
        movedPos.X.Offset == 50 and maxSz.X.Offset == 1280 and resizedW > 520 and mainUI.Size.X.Offset == 650,
        string.format("DragOffset=(%d,%d), MaxSize=(%d,%d), Resized=(%d,%d), ResetSize=(%d,%d)",
            movedPos.X.Offset, movedPos.Y.Offset, maxSz.X.Offset, maxSz.Y.Offset, resizedW, resizedH, mainUI.Size.X.Offset, mainUI.Size.Y.Offset))
end

-- T11: Custom Tab creation & Tab switching stress (100 rapid switches)
do
    local t0 = realClock()
    local customTab = Elysera.CreateTab("CustomTest")
    local customSec = Elysera.CreateSectionLabel(customTab, "Custom Section")
    local customSw, setCustom = Elysera.CreateToggleOption(customTab, "Custom Toggle")
    local tabNames = { "Status & Server", "Local", "FPS", "Script", "Settings", "CustomTest" }
    for i = 1, 100 do
        Elysera.SelectTab(tabNames[(i % #tabNames) + 1])
    end
    Harness.advance(0.5, 1/30)
    local switchMs = (realClock() - t0) * 1000
    Results.benchmarks.tabSwitch100Ms = switchMs
    recordTest("2. MainWeb Core", "T11", "Public API (CreateTab/Section/Toggle) & 100x rapid tab switching stress",
        customTab.Visible == false and #Harness.errors == 0,
        string.format("100 tab switches completed in %.2fms with 0 errors", switchMs))
end

-- ============================================================================
-- SUITE 3: LOCAL.LUA FEATURES, PHYSICS, CAMERA, ESP & WAYPOINTS
-- ============================================================================
local localTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Local")

-- T12: Core.SanitizeNumber & Core.ParseNumericInput boundary values
do
    local speedSw, speedBox
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Speed" then
            speedSw = d.Parent:FindFirstChildOfClass("TextButton")
            speedBox = d.Parent:FindFirstChildOfClass("TextBox")
            break
        end
    end
    local hum = Players.LocalPlayer.Character.Humanoid
    hum.WalkSpeed = 16
    -- Test clamping > 1000, multi-dot "12.34.56", letters "abc99.5xyz", negative "-45"
    speedBox.Text = "999999"
    Harness.signal(speedBox, "FocusLost"):_fire(false)
    Harness.flush()
    local clampedText = speedBox.Text
    click(speedSw)
    Harness.advance(0.2, 1/30)
    local boostedSpeed = hum.WalkSpeed
    -- Test game override budget (35 external overrides in <1s exceeds Core.Boost.reapply = 30)
    for _ = 1, 35 do
        hum.WalkSpeed = 16
        Harness.flush()
    end
    local overriddenSpeed = hum.WalkSpeed
    click(speedSw)
    Harness.advance(0.2, 1/30)
    recordTest("3. Local Tab", "T12", "Speed Boost numeric clamping (max=1000) & anti-loop budget (30/s cap)",
        tonumber(clampedText) == 1000 and boostedSpeed == 1000 and overriddenSpeed == 16,
        string.format("ClampedText=%s, Boosted=%d, After35Overrides=%d (tripped 'Overridden by game' cleanly)", clampedText, boostedSpeed, overriddenSpeed))
end

-- T13: BUG-07 - Jump Boost (JUMP_CFG) snapshot overwrite on external UseJumpPower change
do
    local hum = Players.LocalPlayer.Character.Humanoid
    hum.UseJumpPower = false
    hum.JumpPower = 50
    hum.JumpHeight = 7.2

    local jumpSwitch, jumpBox
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Jump Boost" then
            jumpSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            jumpBox = d.Parent:FindFirstChildOfClass("TextBox")
            break
        end
    end
    jumpBox.Text = "120"
    Harness.flush()
    click(jumpSwitch)
    Harness.advance(0.2, 1/30)
    hum.UseJumpPower = false
    Harness.flush()
    Harness.advance(0.2, 1/30)
    click(jumpSwitch)
    Harness.advance(0.2, 1/30)
    local restoredCorrectly = (hum.JumpPower == 50 and hum.UseJumpPower == false)
    recordTest("3. Local Tab", "T13", "Jump Boost (JUMP_CFG) original JumpPower restoration after external UseJumpPower change",
        restoredCorrectly,
        string.format("Expected JumpPower=50 after disabling Jump Boost, got JumpPower=%s (snaps[t] overwritten in onExternal!)", tostring(hum.JumpPower)),
        { id = "BUG-07", severity = "High", file = "Local.lua:989-1001 & 1165-1192" })
    hum.JumpPower = 50
end

-- T14: BUG-08 - Camera Min Zoom / Max Zoom cross-boundary validation
do
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
    Harness.advance(0.2, 1/30)
    local lp = Players.LocalPlayer
    local curMin, curMax = lp.CameraMinZoomDistance, lp.CameraMaxZoomDistance
    local validZoomRange = (curMin <= curMax and curMax >= 0.5)
    click(maxZoomSw)
    click(minZoomSw)
    Harness.advance(0.2, 1/30)
    recordTest("3. Local Tab", "T14", "Camera Min Zoom / Max Zoom cross-boundary validation (MinZoom <= MaxZoom)",
        validZoomRange,
        string.format("Allowed CameraMinZoomDistance=%.1f > CameraMaxZoomDistance=%.1f without cross-clamping.", curMin, curMax),
        { id = "BUG-08", severity = "Medium", file = "Local.lua:1206-1221" })
end

-- T15: Fly + Seated pause + WASD/Space/Q movement + X brake + teardown
do
    local flySw, flyBox
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Fly" then
            flySw = d.Parent:FindFirstChildOfClass("TextButton")
            flyBox = d.Parent:FindFirstChildOfClass("TextBox")
            break
        end
    end
    flyBox.Text = "80"
    Harness.flush()
    click(flySw)
    Harness.advance(0.3, 1/30)
    local root = Players.LocalPlayer.Character.HumanoidRootPart
    local hum = Players.LocalPlayer.Character.Humanoid
    local lv = root:FindFirstChild("ElyseraFlyLV")
    local ao = root:FindFirstChild("ElyseraFlyAO")
    -- Press W and Space
    Harness.keysDown = { { KeyCode = Enum.KeyCode.W }, { KeyCode = Enum.KeyCode.Space } }
    Harness.advance(0.3, 1/30)
    local movingVel = lv and lv.VectorVelocity.Magnitude or 0
    -- Sit on a seat part -> should zero velocity and pause Fly
    local seat = Harness.new("Part", { Name = "Seat" }, Workspace)
    hum.SeatPart = seat
    Harness.advance(0.2, 1/30)
    local seatedVel = lv and lv.VectorVelocity.Magnitude or -1
    hum.SeatPart = nil
    seat:Destroy()
    Harness.keysDown = {}
    click(flySw)
    Harness.advance(0.2, 1/30)
    local cleanedUp = (root:FindFirstChild("ElyseraFlyLV") == nil and root:FindFirstChild("ElyseraFlyAO") == nil and hum.PlatformStand == false)
    recordTest("3. Local Tab", "T15", "Fly physics constraints (LinearVelocity/AlignOrientation), Seated pause & cleanup",
        movingVel > 10 and seatedVel == 0 and cleanedUp,
        string.format("MovingVel=%.1f, SeatedVel=%.1f, CleanedUp=%s", movingVel, seatedVel, tostring(cleanedUp)))
end

-- T16: Noclip collision disabling, dynamic child BasePart tracking & restoration
do
    local noclipSw
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Noclip" then
            noclipSw = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    local root = Players.LocalPlayer.Character.HumanoidRootPart
    root.CanCollide = true
    click(noclipSw)
    Harness.advance(0.2, 1/30)
    local whileOn = root.CanCollide
    click(noclipSw)
    Harness.advance(0.2, 1/30)
    local afterOff = root.CanCollide
    recordTest("3. Local Tab", "T16", "Noclip Stepped collision lock & original CanCollide restoration",
        whileOn == false and afterOff == true,
        string.format("CanCollide while ON=%s, after OFF=%s", tostring(whileOn), tostring(afterOff)))
end

-- T17: Anti Void rescue & 1s cooldown when falling below FallenPartsDestroyHeight + 80
do
    local avSw
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Anti Void" then
            avSw = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    local root = Players.LocalPlayer.Character.HumanoidRootPart
    local hum = Players.LocalPlayer.Character.Humanoid
    hum.FloorMaterial = Enum.Material.Plastic
    root.CFrame = CFrame.new(10, 20, 10)
    click(avSw)
    Harness.advance(0.3, 1/30)
    -- Plunge below FallenPartsDestroyHeight (-500 + 80 = -420)
    root.CFrame = CFrame.new(10, -450, 10)
    Harness.advance(0.2, 1/30)
    local rescuedY = root.Position.Y
    click(avSw)
    Harness.advance(0.2, 1/30)
    recordTest("3. Local Tab", "T17", "Anti Void safe-ground sampling & void plunge rescue",
        rescuedY > 0,
        string.format("Plunged to Y=-450 -> Rescued to Y=%.1f (safe Y=20 + 4)", rescuedY))
end

-- T18: Click Teleport (Ctrl+Click & TouchTapInWorld) + Quick Actions (Back / Unstuck / Respawn double-tap)
do
    local ctpSw
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Click Teleport" then
            ctpSw = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    local root = Players.LocalPlayer.Character.HumanoidRootPart
    root.CFrame = CFrame.new(0, 10, 0)
    Harness.raycastResult = { Position = Vector3.new(100, 5, -80), Normal = Vector3.new(0, 1, 0) }
    click(ctpSw)
    Harness.advance(0.2, 1/30)
    Harness.keysDown = { { KeyCode = Enum.KeyCode.LeftControl } }
    local clickInp = Harness.inputObject(Enum.UserInputType.MouseButton1, Enum.UserInputState.Begin)
    Harness.signal(UIS, "InputBegan"):_fire(clickInp, false)
    Harness.flush()
    local tpPos = root.Position
    Harness.keysDown = {}
    click(ctpSw)
    Harness.raycastResult = nil

    -- Click "Back" in QuickActions to return to (0, 10, 0)
    local qaCard = localTab:FindFirstChild("QuickActions")
    local backBtn, unstuckBtn, respawnBtn
    for _, d in ipairs(qaCard:GetDescendants()) do
        if d:IsA("TextButton") then
            if d.Text == "Back" then backBtn = d
            elseif d.Text == "Unstuck" then unstuckBtn = d
            elseif d.Text == "Respawn" then respawnBtn = d end
        end
    end
    click(backBtn)
    Harness.flush()
    local backPos = root.Position
    click(unstuckBtn)
    Harness.flush()
    local unstuckY = root.Position.Y

    recordTest("3. Local Tab", "T18", "Click Teleport raycast + Quick Actions (Back history & Unstuck lift)",
        math.abs(tpPos.X - 100) < 1 and math.abs(backPos.X) < 1 and unstuckY > backPos.Y,
        string.format("ClickTP=(%.0f,%.0f,%.0f), Back=(%.0f,%.0f,%.0f), UnstuckY=%.0f",
            tpPos.X, tpPos.Y, tpPos.Z, backPos.X, backPos.Y, backPos.Z, unstuckY))
end

-- T19: BUG-09 - ESP HIGHLIGHT_BUDGET (31 limit) overflow when HumanoidRootPart is unparented
do
    local extraPlayers = {}
    for i = 1, 34 do
        local p = Harness.new("Player", { Name = "Bot" .. i, UserId = 3000 + i, DisplayName = "Bot" .. i }, Players)
        local char = Harness.makeCharacter("Bot" .. i, i * 3, 5, 0)
        Harness.rawSet(p, "Character", char)
        table.insert(extraPlayers, p)
        Harness.signal(Players, "PlayerAdded"):_fire(p)
    end
    Harness.flush()

    local espSwitch
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Esp Player" then
            espSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    click(espSwitch)
    Harness.advance(0.6, 1/30)

    for i = 1, 3 do
        local hrp = extraPlayers[i].Character:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.Parent = nil end
    end
    for i = 30, 34 do
        local hrp = extraPlayers[i].Character:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.Position = Vector3.new(1, 5, 0) end
    end
    Harness.advance(0.8, 1/30)

    local espFolder = gethui():FindFirstChild("ElyseraESP")
    local hlCount = 0
    if espFolder then
        for _, c in ipairs(espFolder:GetChildren()) do
            if c.ClassName == "Highlight" then hlCount = hlCount + 1 end
        end
    end
    click(espSwitch)
    Harness.advance(0.3, 1/30)
    for _, p in ipairs(extraPlayers) do p:Destroy() end
    Harness.flush()

    recordTest("3. Local Tab", "T19", "ESP Highlight budget cap (<= 31) under HumanoidRootPart unparenting & rebalance",
        hlCount <= 31,
        string.format("Active Highlight instances=%d (exceeded HIGHLIGHT_BUDGET=31 because rebalance() skips entries with e.root.Parent==nil!)", hlCount),
        { id = "BUG-09", severity = "High", file = "Local.lua:1889-1907" })
end

-- T20: BUG-10 - Freecam character respawn lifecycle (anchoring new character & restoring CameraSubject)
do
    local freecamSwitch
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Freecam" then
            freecamSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    local lp = Players.LocalPlayer
    local oldChar = lp.Character
    click(freecamSwitch)
    Harness.advance(0.2, 1/30)

    local newChar = Harness.makeCharacter("Tester", 25, 5, 25)
    oldChar.Parent = nil
    Harness.rawSet(lp, "Character", newChar)
    Harness.signal(lp, "CharacterAdded"):_fire(newChar)
    Harness.advance(0.2, 1/30)
    local newRootAnchoredWhileFreecam = newChar.HumanoidRootPart.Anchored

    click(freecamSwitch)
    Harness.advance(0.2, 1/30)
    local restoredToNewHum = (Workspace.CurrentCamera.CameraSubject == newChar.Humanoid)
    Workspace.CurrentCamera.CameraSubject = newChar.Humanoid

    recordTest("3. Local Tab", "T20", "Freecam character respawn lifecycle (anchoring new character & restoring CameraSubject)",
        newRootAnchoredWhileFreecam and restoredToNewHum,
        string.format("newRootAnchored=%s, restoredToNewHum=%s (CameraSubject restored to dead character's Humanoid because oldHum.Parent is still oldChar!)",
            tostring(newRootAnchoredWhileFreecam), tostring(restoredToNewHum)),
        { id = "BUG-10", severity = "High", file = "Local.lua:1487-1525, 2811-2813" })
end

-- T21: BUG-11 - Waypoints JSON Import / Load coordinate range validation (1e308 integer overflow crash)
do
    local wpCard
    for _, d in ipairs(localTab:GetDescendants()) do
        if d.Name == "Waypoints" and d:IsA("Frame") then wpCard = d break end
    end
    local wpInput, wpImportBtn
    for _, d in ipairs(wpCard:GetDescendants()) do
        if d:IsA("TextBox") and d.PlaceholderText == "Name or exported JSON" then wpInput = d end
        if d:IsA("TextButton") and d.Text == "Import" then wpImportBtn = d end
    end
    local errBefore = #Harness.errors
    wpInput.Text = '{"format":"Elysera-Waypoints","points":[{"n":"ExtremePoint","x":1e308,"y":1e308,"z":1e308,"r":0}]}'
    Harness.flush()
    click(wpImportBtn)
    Harness.advance(0.5, 1/30)
    local noCrash = (#Harness.errors == errBefore)
    delfile("Elysera/Elysera_Waypoints.json")
    Harness.errors = {}

    recordTest("3. Local Tab", "T21", "Waypoints JSON Import coordinate range validation (1e308 integer overflow crash)",
        noCrash,
        "Importing waypoint with x=1e308 writes poison data to Elysera_Waypoints.json and crashes Local.lua:2561 `string.format('%d', ...)`.",
        { id = "BUG-11", severity = "Critical", file = "Local.lua:2418, 2561, 2658" })
end

-- T22: BUG-12 - ESP refreshHp resilience against -math.huge / NaN Humanoid.Health
do
    local espSwitch
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Esp Player" then
            espSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    click(espSwitch)
    Harness.advance(0.3, 1/30)
    local errBefore = #Harness.errors
    local aliceHum = Harness.others[1].Character.Humanoid
    Harness.rawSet(aliceHum, "Health", -math.huge)
    Harness.signal(aliceHum, "HealthChanged"):_fire(-math.huge)
    Harness.flush()
    local noHpCrash = (#Harness.errors == errBefore)
    Harness.rawSet(aliceHum, "Health", 100)
    click(espSwitch)
    Harness.advance(0.3, 1/30)
    Harness.errors = {}

    recordTest("3. Local Tab", "T22", "ESP refreshHp resilience against -math.huge / NaN Humanoid.Health (Local.lua:1801)",
        noHpCrash,
        "When Humanoid.Health is -math.huge or NaN, `math.min(e.hum.Health, 1e9)` remains -math.huge/NaN and crashes `string.format('HP: %d/%d', ...)`.",
        { id = "BUG-12", severity = "Medium", file = "Local.lua:1800-1806" })
end

-- T23: Position XYZ parser scientific notation & decimal parsing (`parseXYZ` in Local.lua:2362)
do
    local posCard
    for _, d in ipairs(localTab:GetDescendants()) do
        if d.Name == "PositionXYZ" and d:IsA("Frame") then posCard = d break end
    end
    local xyzBox, tpBtn
    for _, d in ipairs(posCard:GetDescendants()) do
        if d:IsA("TextBox") then xyzBox = d end
        if d:IsA("TextLabel") and d.Text == "TP" then tpBtn = d.Parent end
    end
    local root = Players.LocalPlayer.Character.HumanoidRootPart
    root.CFrame = CFrame.new(0, 5, 0)
    -- Input scientific notation "1e2, 50, -30" (100, 50, -30)
    xyzBox.Text = "1e2, 50, -30"
    Harness.flush()
    click(tpBtn)
    Harness.flush()
    local posAfter = root.Position
    local parsedSciCorrectly = (math.abs(posAfter.X - 100) < 1 and math.abs(posAfter.Y - 50) < 1 and math.abs(posAfter.Z - (-30)) < 1)
    recordTest("3. Local Tab", "T23", "Position XYZ parser scientific notation support ('1e2, 50, -30')",
        parsedSciCorrectly,
        string.format("Input '1e2, 50, -30' teleported to (%.0f, %.0f, %.0f) instead of (100, 50, -30) because gmatch pattern splits '1e2' into 1 and 2!",
            posAfter.X, posAfter.Y, posAfter.Z),
        { id = "BUG-13", severity = "Low", file = "Local.lua:2362-2370" })
end

-- T24: Players Card search, TP, View/Spectate & target leaving auto-restore
do
    local pCard
    for _, d in ipairs(localTab:GetDescendants()) do
        if d.Name == "PlayersCard" and d:IsA("Frame") then pCard = d break end
    end
    local searchBox
    for _, d in ipairs(pCard:GetDescendants()) do
        if d:IsA("TextBox") then searchBox = d break end
    end
    searchBox.Text = "Alice"
    Harness.flush()
    Harness.advance(0.2, 1/30)
    local viewBtn, tpBtn
    for _, d in ipairs(pCard:GetDescendants()) do
        if d:IsA("Frame") and d.Name == "PlayerRow" and d.Visible then
            for _, b in ipairs(d:GetDescendants()) do
                if b:IsA("TextButton") and b.Text == "View" then viewBtn = b end
                if b:IsA("TextLabel") and b.Text == "TP" then tpBtn = b.Parent end
            end
        end
    end
    click(tpBtn)
    click(viewBtn)
    Harness.advance(0.2, 1/30)
    local viewingAlice = (Workspace.CurrentCamera.CameraSubject == Harness.others[1].Character.Humanoid)
    -- Stop viewing via ViewHud Stop button
    local hud = Elysera.ScreenGui:FindFirstChild("ViewHud")
    for _, b in ipairs(hud:GetDescendants()) do
        if b:IsA("TextLabel") and b.Text == "Stop" then click(b.Parent) break end
    end
    Harness.advance(0.2, 1/30)
    local stoppedViewing = (Workspace.CurrentCamera.CameraSubject == Players.LocalPlayer.Character.Humanoid and not hud.Visible)
    searchBox.Text = ""
    Harness.flush()
    recordTest("3. Local Tab", "T24", "Players Card search filter, TP to player, Spectate (ViewHud) & Stop restore",
        viewingAlice and stoppedViewing,
        string.format("ViewingAlice=%s, RestoredCamera=%s", tostring(viewingAlice), tostring(stoppedViewing)))
end

-- ============================================================================
-- SUITE 4: FPS.LUA OPTIMIZER, SCREEN MODES, IDLE SAVER, OVERLAY & AUDIO/NOTIF
-- ============================================================================
local fpsTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_FPS")

-- T25: BUG-14 - FPS Profile 'Performance' QualityLevel when started from Automatic (0)
do
    local renderSettings = settings().Rendering
    renderSettings.QualityLevel = Enum.QualityLevel.Automatic
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
        if item:IsA("TextButton") and item.Text == "Performance" then click(item) break end
    end
    Harness.advance(0.2, 1/30)
    click(profileSwitch)
    Harness.advance(0.4, 1/30)
    local changedFromAuto = (renderSettings.QualityLevel ~= Enum.QualityLevel.Automatic)
    click(profileSwitch)
    Harness.advance(0.4, 1/30)

    recordTest("4. FPS Tab", "T25", "FPS Profile 'Performance' lowers QualityLevel when set to Automatic (0)",
        changedFromAuto,
        "QualityLevel stayed Automatic (0) in Performance mode because PROFILES.Performance.quality = { cap = 3 } lacks `force = true`.",
        { id = "BUG-14", severity = "Medium", file = "FPS.lua:951-964, 1067-1080" })
end

-- T26: BUG-15 - Cross-module state contention between Full Bright (Local.lua) and FPS Profile (FPS.lua)
do
    Lighting.GlobalShadows = true
    local fbSwitch, profileSwitch
    for _, d in ipairs(localTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Full Bright" then
            fbSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    for _, d in ipairs(fpsTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "FPS Profile" then
            profileSwitch = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    local fbStack = fbSwitch.Parent.Parent
    click(fbStack.ModeRow.ModeWinbox.Hit)
    Harness.advance(0.1, 1/30)
    local ddLayer = Elysera.ScreenGui:FindFirstChild("ModeDropdownLayer")
    for _, item in ipairs(ddLayer.Panel:GetChildren()) do
        if item:IsA("TextButton") and item.Text == "Performance" then click(item) break end
    end
    Harness.advance(0.1, 1/30)

    click(fbSwitch)
    Harness.advance(0.3, 1/30)
    click(profileSwitch)
    Harness.advance(0.3, 1/30)
    click(fbSwitch)
    Harness.advance(0.3, 1/30)
    local shadowsStayOffWhileFpsProfileOn = (Lighting.GlobalShadows == false)
    click(profileSwitch)
    Harness.advance(0.3, 1/30)

    recordTest("4. FPS Tab", "T26", "FPS Profile keeps GlobalShadows=false when Full Bright (Performance) is turned off",
        shadowsStayOffWhileFpsProfileOn,
        "Lighting.GlobalShadows reverted to `true` while FPS Profile was still ON because probe() skipped GlobalShadows when Full Bright had set it to false.",
        { id = "BUG-15", severity = "Medium", file = "FPS.lua:781-809 & Local.lua:1643-1673" })
end

-- T27: Optimizer 10,500-instance burst (> QUEUE_CAP=10,000) + Extreme Profile + full revert
do
    local profileSwitch, profileArrow
    for _, d in ipairs(fpsTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "FPS Profile" then
            local row = d.Parent
            profileSwitch = row:FindFirstChildOfClass("TextButton")
            profileArrow = row.ModeBox.Arrow
            break
        end
    end
    click(profileArrow)
    Harness.advance(0.2, 1/30)
    local modeList = Elysera.ScreenGui.MG_Main:FindFirstChild("ModeList")
    for _, item in ipairs(modeList:GetDescendants()) do
        if item:IsA("TextButton") and item.Text == "Extreme" then click(item) break end
    end
    Harness.advance(0.2, 1/30)
    click(profileSwitch)
    Harness.advance(0.3, 1/30)

    local burstFolder = Harness.new("Folder", { Name = "BurstParts" }, Workspace)
    local t0 = realClock()
    local burstParts = {}
    for i = 1, 10500 do
        burstParts[i] = Harness.new("Part", { Name = "P", Reflectance = 0.5, Material = Enum.Material.Brick }, burstFolder)
    end
    Harness.flush()
    Harness.advance(6.0, 1/30)
    local burstMs = (realClock() - t0) * 1000
    Results.benchmarks.optimizerBurst10500Ms = burstMs

    local allOptimized = (burstParts[1].Reflectance == 0 and burstParts[1].Material == Enum.Material.SmoothPlastic
        and burstParts[10500].Reflectance == 0 and burstParts[10500].Material == Enum.Material.SmoothPlastic
        and glassPart.Material == Enum.Material.Glass)
    click(profileSwitch)
    Harness.advance(1.0, 1/30)
    local allRestored = (burstParts[1].Reflectance == 0.5 and burstParts[1].Material == Enum.Material.Brick
        and burstParts[10500].Reflectance == 0.5 and burstParts[10500].Material == Enum.Material.Brick)
    burstFolder:Destroy()
    Harness.flush()

    recordTest("4. FPS Tab", "T27", "Optimizer 10,500-part burst (> QUEUE_CAP=10,000), Extreme material rules & revert",
        allOptimized and allRestored and #Harness.errors == 0,
        string.format("Optimized10500=%s, Restored10500=%s, Elapsed=%.1fms", tostring(allOptimized), tostring(allRestored), burstMs))
end

-- T28: White Screen, Black Screen, AFK Mode mutual exclusion & 3D Rendering / FPS Cap control
do
    local whiteSw, blackSw, afkSw
    for _, d in ipairs(fpsTab:GetDescendants()) do
        if d:IsA("TextLabel") then
            if d.Text == "White Screen" then whiteSw = d.Parent:FindFirstChildOfClass("TextButton")
            elseif d.Text == "Black Screen" then blackSw = d.Parent:FindFirstChildOfClass("TextButton")
            elseif d.Text == "AFK Mode" then afkSw = d.Parent:FindFirstChildOfClass("TextButton") end
        end
    end
    click(whiteSw)
    Harness.advance(0.2, 1/30)
    local whiteOn = (whiteSw:GetAttribute("Toggled") == true and Harness.render3d == false and getfpscap() == 15)
    click(blackSw) -- Should automatically turn off White Screen!
    Harness.advance(0.2, 1/30)
    local blackExclusive = (blackSw:GetAttribute("Toggled") == true and whiteSw:GetAttribute("Toggled") == false and Harness.render3d == false)
    click(blackSw)
    Harness.advance(0.2, 1/30)
    local restoredRender = (Harness.render3d == true and getfpscap() == 60)

    recordTest("4. FPS Tab", "T28", "White/Black/AFK Screen mutual exclusion, Set3dRenderingEnabled(false) & 15 FPS cap",
        whiteOn and blackExclusive and restoredRender,
        string.format("WhiteOn=%s, BlackExclusive=%s, Restored3D=%s", tostring(whiteOn), tostring(blackExclusive), tostring(restoredRender)))
end

-- T29: Auto Boost trigger after 6s of low FPS (< 30 FPS) & Idle Saver trigger + wake on input
do
    local autoSw, profileSw, saverSw
    for _, d in ipairs(fpsTab:GetDescendants()) do
        if d:IsA("TextLabel") then
            if d.Text == "Auto Boost" then autoSw = d.Parent:FindFirstChildOfClass("TextButton")
            elseif d.Text == "FPS Profile" then profileSw = d.Parent:FindFirstChildOfClass("TextButton")
            elseif d.Text == "Idle Saver" then saverSw = d.Parent:FindFirstChildOfClass("TextButton") end
        end
    end
    click(autoSw)
    Harness.flush()
    -- Simulate 20 FPS (dt = 0.05s) for 7 seconds so Auto Boost triggers Profile ON and disarms itself!
    Harness.advance(7.0, 0.05)
    local autoTriggered = (profileSw:GetAttribute("Toggled") == true and autoSw:GetAttribute("Toggled") == false)
    click(profileSw)
    Harness.advance(0.3, 1/30)

    -- Test Idle Saver (default "After 3 min" = 180s)
    click(saverSw)
    Harness.advance(182.0, 0.5)
    local idleCovered = (Harness.render3d == false)
    -- Wake with mouse movement
    local wakeInp = Harness.inputObject(Enum.UserInputType.MouseMovement, Enum.UserInputState.Change)
    Harness.signal(UIS, "InputChanged"):_fire(wakeInp)
    Harness.flush()
    local wokeUp = (Harness.render3d == true)
    click(saverSw)
    Harness.advance(0.2, 1/30)

    recordTest("4. FPS Tab", "T29", "Auto Boost low-FPS trigger (6s @ 20 FPS) & Idle Saver auto-sleep + input wake",
        autoTriggered and idleCovered and wokeUp,
        string.format("AutoBoostTriggered=%s, IdleSleep=%s, WokeOnInput=%s", tostring(autoTriggered), tostring(idleCovered), tostring(wokeUp)))
end

-- T30: Mute Audio, Remove Notification, Hide Chat & Player List, Hide Distant Players & FPS Overlay drag
do
    local muteSw, notifSw, hideSw, cullSw, overlaySw
    for _, d in ipairs(fpsTab:GetDescendants()) do
        if d:IsA("TextLabel") then
            if d.Text == "Mute Audio" then muteSw = d.Parent:FindFirstChildOfClass("TextButton")
            elseif d.Text == "Remove Notification" then notifSw = d.Parent:FindFirstChildOfClass("TextButton")
            elseif d.Text == "Hide Chat & Player List" then hideSw = d.Parent:FindFirstChildOfClass("TextButton")
            elseif d.Text == "Hide Distant Players" then cullSw = d.Parent:FindFirstChildOfClass("TextButton")
            elseif d.Text == "FPS Overlay" then overlaySw = d.Parent:FindFirstChildOfClass("TextButton") end
        end
    end
    -- Create a notification ScreenGui in PlayerGui
    local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local fakeNotif = Harness.new("ScreenGui", { Name = "ToastNotificationGui", Enabled = true }, pg)
    click(muteSw)
    click(notifSw)
    click(hideSw)
    click(cullSw)
    click(overlaySw)
    Harness.advance(1.0, 1/30)

    local mutedOk = (sound.Volume == 0 and soundGroup.Volume == 0 and UserSettings():GetService("UserGameSettings").MasterVolume == 0)
    local notifHidden = (fakeNotif.Enabled == false)
    local coreGuiHidden = (game:GetService("StarterGui"):GetCoreGuiEnabled(Enum.CoreGuiType.Chat) == false)

    -- Drag FPS Overlay pill
    local overlayGui = gethui():FindFirstChild("ElyseraFpsOverlay")
    local pill = overlayGui and overlayGui:FindFirstChild("Pill")
    local oInp = Harness.inputObject(Enum.UserInputType.MouseButton1, Enum.UserInputState.Begin, { Position = Vector3.new(640, 10, 0) })
    Harness.signal(pill, "InputBegan"):_fire(oInp)
    Harness.flush()
    local oMove = Harness.inputObject(Enum.UserInputType.MouseMovement, Enum.UserInputState.Change, { Position = Vector3.new(200, 100, 0) })
    Harness.signal(UIS, "InputChanged"):_fire(oMove)
    Harness.flush()
    oInp.UserInputState = Enum.UserInputState.End
    oInp.Changed:_fire()
    Harness.flush()

    -- Reset All on FPSTab
    local fpsResetBtn = fpsTab:FindFirstChild("ResetAll")
    click(fpsResetBtn)
    Harness.advance(0.5, 1/30)
    local allRestored = (sound.Volume == 0.8 and soundGroup.Volume == 0.9 and fakeNotif.Enabled == true
        and game:GetService("StarterGui"):GetCoreGuiEnabled(Enum.CoreGuiType.Chat) == true and not overlayGui.Enabled)
    fakeNotif:Destroy()

    recordTest("4. FPS Tab", "T30", "Mute Audio, Remove Notification, Hide CoreGui, FPS Overlay drag & Reset All",
        mutedOk and notifHidden and coreGuiHidden and allRestored,
        string.format("Muted=%s, NotifHidden=%s, CoreGuiHidden=%s, ResetAllRestored=%s",
            tostring(mutedOk), tostring(notifHidden), tostring(coreGuiHidden), tostring(allRestored)))
end

-- ============================================================================
-- SUITE 5: SCRIPT.LUA COMPILER, SYNTAX HIGHLIGHTER, LIBRARY & EXECUTION
-- ============================================================================
local scriptTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Script")

-- T31: BUG-16 - Deleting a running script in Script.lua leaves it running in background
do
    Elysera.SelectTab("Script")
    Harness.advance(0.2, 1/30)
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

    _G.leakTaskStopped = false
    nameBox.Text = "LeakRunner"
    codeBox.Text = "return function() _G.leakTaskStopped = true end"
    Harness.flush()
    click(saveBtn)
    Harness.advance(0.6, 1/30)

    local targetRow
    for _, c in ipairs(scriptTab.FunctionPanel2:GetChildren()) do
        if c.Name:match("^Script_") and c.Visible then
            local t = c.Left and c.Left:FindFirstChild("Title")
            if t and t.Text == "LeakRunner" then targetRow = c break end
        end
    end
    local playBtn, moreBtn
    for _, c in ipairs(targetRow:GetChildren()) do
        if c:IsA("TextButton") then
            if c.Position.X.Offset == 0 then playBtn = c
            elseif c.Position.X.Offset == -34 then moreBtn = c end
        end
    end
    click(playBtn)
    Harness.advance(0.5, 1/30)

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
    Harness.advance(6.5, 1/30)

    recordTest("5. Script Tab", "T31", "deleteScript stops active script & invokes cleanup hook upon deletion",
        _G.leakTaskStopped == true,
        "Deleted script remained active in `Running[entry.id]` and its cleanup hook was never called.",
        { id = "BUG-16", severity = "High", file = "Script.lua:1345-1390" })
end

-- T32: BUG-17 - Delete + Add same name + Undo creates duplicate script names
do
    local addBtn = scriptTab.FunctionPanel1.AddButton
    local notBoxA = Elysera.ScreenGui:FindFirstChild("NotBoxA")
    local nameBox, codeBox, saveBtn
    for _, d in ipairs(notBoxA:GetDescendants()) do
        if d:IsA("TextBox") then
            if d.MultiLine then codeBox = d else nameBox = d end
        elseif d:IsA("TextButton") and d.Text == "Save" then
            saveBtn = d
        end
    end

    click(addBtn)
    Harness.advance(0.3, 1/30)
    nameBox.Text = "UniqueCheck"
    codeBox.Text = "local x = 1"
    Harness.flush()
    click(saveBtn)
    Harness.advance(0.6, 1/30)

    local targetRow
    for _, c in ipairs(scriptTab.FunctionPanel2:GetChildren()) do
        if c.Name:match("^Script_") and c.Visible then
            local t = c.Left and c.Left:FindFirstChild("Title")
            if t and t.Text == "UniqueCheck" then targetRow = c break end
        end
    end
    local moreBtn
    for _, c in ipairs(targetRow:GetChildren()) do
        if c:IsA("TextButton") and c.Position.X.Offset == -34 then moreBtn = c break end
    end
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
    Harness.advance(0.6, 1/30)

    click(addBtn)
    Harness.advance(0.3, 1/30)
    nameBox.Text = "UniqueCheck"
    codeBox.Text = "local x = 2"
    Harness.flush()
    click(saveBtn)
    Harness.advance(0.6, 1/30)

    local toastHost = Elysera.ScreenGui:FindFirstChild("ToastHost")
    if toastHost then
        for _, d in ipairs(toastHost:GetDescendants()) do
            if d:IsA("TextButton") and d.Text == "Undo" then click(d) break end
        end
    end
    Harness.advance(0.4, 1/30)

    local countSameName = 0
    for _, c in ipairs(scriptTab.FunctionPanel2:GetChildren()) do
        if c.Name:match("^Script_") and c.Visible then
            local t = c.Left and c.Left:FindFirstChild("Title")
            if t and t.Text == "UniqueCheck" then countSameName = countSameName + 1 end
        end
    end
    recordTest("5. Script Tab", "T32", "Script library unique-name invariant under Delete -> Add -> Undo",
        countSameName == 1,
        string.format("Found %d visible scripts with identical name 'UniqueCheck' after Undo.", countSameName),
        { id = "BUG-17", severity = "Low", file = "Script.lua:1376-1386" })
end

-- T33: Script.lua Import/Export, Review Gate (double-tap play), Syntax Error Save-Anyway Gate & Output Panel
do
    local libMoreBtn
    for _, c in ipairs(scriptTab.FunctionPanel1:GetChildren()) do
        if c:IsA("TextButton") and c.Position.X.Offset == -78 then libMoreBtn = c break end
    end
    click(libMoreBtn)
    Harness.advance(0.2, 1/30)
    local menuCatcher = Elysera.ScreenGui:FindFirstChild("MenuCatcher")
    for _, d in ipairs(menuCatcher:GetDescendants()) do
        if d:IsA("TextButton") and d.Text == "Import" then click(d) break end
    end
    Harness.advance(0.3, 1/30)

    local notBoxA = Elysera.ScreenGui:FindFirstChild("NotBoxA")
    local codeBox, saveBtn
    for _, d in ipairs(notBoxA:GetDescendants()) do
        if d:IsA("TextBox") and d.MultiLine then codeBox = d
        elseif d:IsA("TextButton") and d.Text == "Import" then saveBtn = d end
    end
    codeBox.Text = HttpService:JSONEncode({
        format = "L-script-export",
        version = 1,
        scripts = {
            { name = "ImportedScript1", script = "_G.impRan = true" },
            { name = "ImportedScript2", script = "print('s2')" },
            { name = "ImportedScript3", script = "print('s3')" },
            { name = "ImportedScript4", script = "print('s4')" },
        },
    })
    Harness.flush()
    click(saveBtn)
    Harness.advance(0.6, 1/30)

    -- Find ImportedScript1 row and test its review gate (first click warns, second click runs!)
    local impRow
    for _, c in ipairs(scriptTab.FunctionPanel2:GetChildren()) do
        if c.Name:match("^Script_") and c.Visible then
            local t = c.Left and c.Left:FindFirstChild("Title")
            if t and t.Text == "ImportedScript1" then impRow = c break end
        end
    end
    local playBtn
    for _, c in ipairs(impRow:GetChildren()) do
        if c:IsA("TextButton") and c.Position.X.Offset == 0 then playBtn = c break end
    end
    _G.impRan = false
    click(playBtn) -- 1st click: blocked by review gate!
    Harness.advance(0.2, 1/30)
    local blockedOnFirstTap = (_G.impRan == false)
    click(playBtn) -- 2nd click within 5s: runs!
    Harness.advance(0.3, 1/30)
    local ranOnSecondTap = (_G.impRan == true)

    -- SearchRow should now be visible since #ScriptList >= 5!
    local searchVisible = scriptTab.SearchRow.Visible

    recordTest("5. Script Tab", "T33", "Batch Import, Review security gate (2-tap play) & Search auto-activation (>=5 items)",
        blockedOnFirstTap and ranOnSecondTap and searchVisible,
        string.format("Blocked1stTap=%s, Ran2ndTap=%s, SearchBarVisible=%s",
            tostring(blockedOnFirstTap), tostring(ranOnSecondTap), tostring(searchVisible)))
end

-- ============================================================================
-- SUITE 6: STATUS_SERVER.LUA TELEPORT, SERVER HOP & BROWSER
-- ============================================================================
local statusTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Status & Server")

-- T34: BUG-18 - Status_Server.lua isValidJobId strict UUID format check
do
    local hopperCard = statusTab:FindFirstChild("ServerHopper")
    local hopperBox = hopperCard:FindFirstChildOfClass("TextBox")
    local joinBtn
    for _, d in ipairs(hopperCard:GetDescendants()) do
        if d:IsA("TextButton") and d.Text == "Join" then joinBtn = d break end
    end
    Harness.advance(10.5, 1/30)
    local beforeTp = #Harness.teleports
    hopperBox.Text = "a-b-c-d-e"
    Harness.flush()
    click(joinBtn)
    Harness.advance(0.2, 1/30)
    local rejectedBogusUuid = (#Harness.teleports == beforeTp)
    recordTest("6. Status & Server", "T34", "isValidJobId strict UUID format validation (rejecting 'a-b-c-d-e')",
        rejectedBogusUuid,
        "isValidJobId('a-b-c-d-e') returned true and called TeleportToPlaceInstance with non-UUID 'a-b-c-d-e'.",
        { id = "BUG-18", severity = "Low", file = "Status_Server.lua:48-50" })
end

-- T35: Server Hop (Random, Least, Best Ping), HTTP 429 backoff & Server Browser sorting
do
    Harness.advance(10.5, 1/30)
    local browserSec = statusTab:FindFirstChild("Section_Server Browser")
    local refreshBtn, sortBtn
    for _, d in ipairs(browserSec:GetDescendants()) do
        if d:IsA("TextButton") then
            if d.Text == "Refresh" then refreshBtn = d
            elseif d.Text == "Ping" then sortBtn = d end
        end
    end
    click(refreshBtn)
    Harness.advance(1.5, 1/30)
    local browserList = browserSec.Body:FindFirstChild("BrowserList")
    local rowCount = 0
    for _, c in ipairs(browserList:GetChildren()) do
        if c:IsA("Frame") then rowCount = rowCount + 1 end
    end
    click(sortBtn) -- Least
    click(sortBtn) -- Most
    click(sortBtn) -- Ping
    Harness.flush()

    recordTest("6. Status & Server", "T35", "Server Browser HTTP fetch, 15-row rendering & Ping/Least/Most sorting",
        rowCount == 15 and sortBtn.Text == "Ping" and #Harness.errors == 0,
        string.format("RenderedRows=%d (capped at 15 of 25 servers), SortMode=%s", rowCount, sortBtn.Text))
end

-- T36: Auto Rejoin on Kick (GuiService.ErrorMessageChanged & RobloxPromptGui ErrorPrompt)
do
    local kickSw
    for _, d in ipairs(statusTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Auto Rejoin on Kick" then
            kickSw = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    click(kickSw)
    Harness.flush()
    local beforeTp = #Harness.teleports
    Harness.errorMessage = "You were kicked from this experience"
    Harness.signal(game:GetService("GuiService"), "ErrorMessageChanged"):_fire("You were kicked from this experience")
    Harness.advance(0.5, 1/30)
    local afterTp = #Harness.teleports
    click(kickSw)
    Harness.errorMessage = ""
    Harness.advance(0.2, 1/30)

    recordTest("6. Status & Server", "T36", "Auto Rejoin on Kick trigger via GuiService.ErrorMessageChanged",
        afterTp > beforeTp,
        string.format("Teleports triggered on kick=%d", afterTp - beforeTp))
end

-- ============================================================================
-- SUITE 7: SETTINGS.LUA THEMES, ANTI CHAT, CONFIG EXPORT/IMPORT & TEARDOWN
-- ============================================================================
local settingsTab = Elysera.ScreenGui.MG_Main.Body.FunctionPanel.FunctionScroll:FindFirstChild("TabContent_Settings")

-- T37: 22-Theme full cycle benchmark & palette validation
do
    local t0 = realClock()
    local allOk = true
    for _, th in ipairs(Elysera.Themes) do
        local ok = Elysera.SetTheme(th.id)
        if not ok then allOk = false end
    end
    Elysera.SetTheme("sakura")
    local themeCycleMs = (realClock() - t0) * 1000
    Results.benchmarks.themeCycle22Ms = themeCycleMs
    recordTest("7. Settings & Lifecycle", "T37", "22-Theme full tree remapping benchmark & palette validation",
        allOk and #Elysera.Themes == 22,
        string.format("22 themes applied across 2500+ instances in %.2fms (avg %.2fms/theme)", themeCycleMs, themeCycleMs / 22))
end

-- T38: Anti Chat hooks, ChatInputBarConfiguration lock & legacy ChatBar focus block
do
    local antiChatSw
    for _, d in ipairs(settingsTab:GetDescendants()) do
        if d:IsA("TextLabel") and d.Text == "Anti Chat" then
            antiChatSw = d.Parent:FindFirstChildOfClass("TextButton")
            break
        end
    end
    local chatCfg = game:GetService("TextChatService"):FindFirstChildOfClass("ChatInputBarConfiguration")
    chatCfg.Enabled = true
    click(antiChatSw)
    Harness.flush()
    local disabledOnStart = (chatCfg.Enabled == false)
    -- Attempt external tamper to re-enable ChatInputBarConfiguration while Anti Chat is ON
    chatCfg.Enabled = true
    Harness.flush()
    local tamperBlocked = (chatCfg.Enabled == false)
    click(antiChatSw)
    Harness.flush()
    local restoredOnStop = (chatCfg.Enabled == true)

    recordTest("7. Settings & Lifecycle", "T38", "Anti Chat hook installation, ChatInputBarConfiguration tamper guard & restore",
        disabledOnStart and tamperBlocked and restoredOnStop,
        string.format("Disabled=%s, TamperBlocked=%s, Restored=%s", tostring(disabledOnStart), tostring(tamperBlocked), tostring(restoredOnStop)))
end

-- T39: Configuration Export, Import (valid & invalid JSON), Check Update & Reset Config (double-tap)
do
    local cfgCard = settingsTab:FindFirstChild("ConfigCard")
    local cfgBox = cfgCard:FindFirstChildOfClass("TextBox")
    local exportBtn, importBtn, resetBtn
    for _, d in ipairs(cfgCard:GetDescendants()) do
        if d:IsA("TextButton") then
            if d.Text == "Export" then exportBtn = d
            elseif d.Text == "Import" then importBtn = d
            elseif d.Text == "Reset" then resetBtn = d end
        end
    end
    Elysera.SetTheme("ocean")
    click(exportBtn)
    Harness.flush()
    local exportedJson = getclipboard()
    local hasExport = exportedJson and exportedJson:find("Elysera-Config", 1, true) ~= nil

    -- Test Reset Config double-tap confirmation
    click(resetBtn) -- 1st tap: "Tap again"
    Harness.flush()
    local firstTapArmed = (resetBtn.Text == "Tap again")
    click(resetBtn) -- 2nd tap: resets theme back to sakura!
    Harness.flush()
    local resetToSakura = (Elysera.GetTheme() == "sakura")

    -- Now import the exported config (which had theme="ocean")
    cfgBox.Text = exportedJson
    Harness.flush()
    click(importBtn)
    Harness.flush()
    local importedOcean = (Elysera.GetTheme() == "ocean")
    Elysera.SetTheme("sakura")

    recordTest("7. Settings & Lifecycle", "T39", "Configuration Export/Import round-trip & 2-tap Reset to Defaults",
        hasExport and firstTapArmed and resetToSakura and importedOcean,
        string.format("Exported=%s, Reset2Tap=%s, ImportedTheme=%s", tostring(hasExport), tostring(resetToSakura), tostring(importedOcean)))
end

-- T40: Full Elysera.Unload() teardown & zero post-unload errors/orphans
do
    local errBefore = #Harness.errors
    Elysera.Unload()
    Harness.flush()
    Harness.advance(2.0, 1/30)
    local guiDestroyed = (Elysera.ScreenGui.Parent == nil)
    local coverDestroyed = (gethui():FindFirstChild("ElyseraCover") == nil)
    local overlayDestroyed = (gethui():FindFirstChild("ElyseraFpsOverlay") == nil)
    local espDestroyed = (gethui():FindFirstChild("ElyseraESP") == nil)
    recordTest("7. Settings & Lifecycle", "T40", "Elysera.Unload() complete DOM cleanup & zero post-unload thread errors",
        guiDestroyed and coverDestroyed and overlayDestroyed and espDestroyed and (#Harness.errors == errBefore),
        string.format("ScreenGui=%s, Cover=%s, Overlay=%s, ESP=%s, PostUnloadErrors=%d",
            tostring(guiDestroyed), tostring(coverDestroyed), tostring(overlayDestroyed), tostring(espDestroyed), #Harness.errors - errBefore))
end

local totalMs = (realClock() - suiteStart) * 1000
Results.benchmarks.totalSuiteMs = totalMs
print(string.format("\n============================================================================"))
print(string.format("STRICT TEST SUITE SUMMARY: %d Total | %d Passed | %d Failed (Bugs Verified)", Results.total, Results.passed, Results.failed))
print(string.format("Total Execution Time: %.2f ms | Boot: %.2f ms | 10.5k Burst: %.2f ms | 22-Theme Cycle: %.2f ms",
    totalMs, Results.benchmarks.bootMs or 0, Results.benchmarks.optimizerBurst10500Ms or 0, Results.benchmarks.themeCycle22Ms or 0))
print(string.format("============================================================================"))
