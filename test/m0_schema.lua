
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
