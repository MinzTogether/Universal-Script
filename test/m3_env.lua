local CD = CLASSDATA
local STATE = Harness.STATE
for _, m in ipairs({ "HttpGet", "HttpPost", "HttpGetAsync" }) do table.insert(CD.DataModel.m, m) end

local function V3n(x, y, z) return Vector3.new(x, y, z) end

local game_ = Harness.new("DataModel")
STATE[game_].name = "Game"
Harness.rawSet(game_, "JobId", "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d")
Harness.rawSet(game_, "PlaceId", 1818)
Harness.rawSet(game_, "GameId", 2929)
game = game_

local services = {}
local function service(name)
    local svc = services[name]
    if svc then return svc end
    if not CD[name] then error("'" .. tostring(name) .. "' is not a valid Service name", 3) end
    svc = Harness.new(name)
    svc.Parent = game_
    services[name] = svc
    return svc
end
Harness.service = service

Harness.defineMethods("ServiceProvider", {
    GetService = function(self, name) return service(name) end,
    FindService = function(self, name) return services[name] end,
})
Harness.defineMethods("DataModel", {
    IsLoaded = function() return true end,
    HttpGet = function(self, url)
        local name = tostring(url):match("([^/]+)$") or ""
        name = name:gsub("%?.*$", "")
        local body = Harness.files[name]
        if body == nil then error("HTTP 404 (Not Found)", 2) end
        Harness.calls["HttpGet:" .. name] = (Harness.calls["HttpGet:" .. name] or 0) + 1
        return body
    end,
})

local Players = service("Players")
local Workspace = service("Workspace")
local RunService = service("RunService")
local UIS = service("UserInputService")
local Lighting = service("Lighting")
local StarterGui = service("StarterGui")
local CoreGui = service("CoreGui")
local TweenService = service("TweenService")
local HttpService = service("HttpService")
local TeleportService = service("TeleportService")
local TextService = service("TextService")
local GuiService = service("GuiService")
local Stats = service("Stats")
local SoundService = service("SoundService")
local TextChatService = service("TextChatService")
local VirtualUser = service("VirtualUser")
workspace = Workspace

local Terrain = Harness.new("Terrain", { Name = "Terrain" }, Workspace)
local Camera = Harness.new("Camera", { Name = "Camera", FieldOfView = 70 }, Workspace)
Workspace.CurrentCamera = Camera
Harness.camera = Camera

Harness.defineSet("BasePart", {
    Position = function(inst, st, value)
        local cf = st.props.CFrame or CFrame.new()
        Harness.rawSet(inst, "CFrame", CFrame.new(value.X, value.Y, value.Z) * cf.Rotation)
        return true
    end,
})
Harness.defineGet("BasePart", {
    Position = function(inst, st)
        local cf = st.props.CFrame or CFrame.new()
        return cf.Position
    end,
})
Harness.defineSet("Humanoid", {
    Health = function(inst, st, value)
        local max = st.props.MaxHealth or 100
        value = math.clamp(value, 0, max)
        local old = st.props.Health
        if old == nil then old = 100 end
        Harness.rawSet(inst, "Health", value)
        if old ~= value then
            Harness.signal(inst, "HealthChanged"):_fire(value)
            if value <= 0 and old > 0 then Harness.signal(inst, "Died"):_fire() end
        end
        return true
    end,
})
Harness.defineMethods("Humanoid", {
    GetState = function(self) return Enum.HumanoidStateType.Running end,
    ChangeState = function(self, state) Harness.calls["Humanoid:ChangeState"] = state return nil end,
    SetStateEnabled = function() end,
    GetStateEnabled = function() return true end,
    Move = function() end,
    TakeDamage = function(self, n) self.Health = self.Health - n end,
})
Harness.defineMethods("Model", {
    GetBoundingBox = function(self)
        local root = STATE[self].props.PrimaryPart or self:FindFirstChildWhichIsA("BasePart", true)
        local cf = root and root.CFrame or CFrame.new()
        return cf, V3n(4, 5, 2)
    end,
    GetPivot = function(self)
        local root = self:FindFirstChildWhichIsA("BasePart", true)
        return root and root.CFrame or CFrame.new()
    end,
    PivotTo = function(self, cf)
        local root = self:FindFirstChildWhichIsA("BasePart", true)
        if root then root.CFrame = cf end
    end,
    GetExtentsSize = function() return V3n(4, 5, 2) end,
})
Harness.defineMethods("BasePart", {
    GetMass = function() return 1 end,
    GetNetworkOwner = function() return nil end,
    CanCollideWith = function() return true end,
    GetTouchingParts = function() return {} end,
    ApplyImpulse = function() end,
})

local function worldToViewport(cam, pos)
    local rel = cam.CFrame:PointToObjectSpace(pos)
    local depth = -rel.Z
    local fov = math.rad(cam.FieldOfView)
    local h = math.tan(fov / 2)
    local vp = Harness.viewport
    local aspect = vp.X / vp.Y
    local nx = depth ~= 0 and rel.X / (depth * h * aspect) or 0
    local ny = depth ~= 0 and rel.Y / (depth * h) or 0
    return V3n((0.5 + nx * 0.5) * vp.X, (0.5 - ny * 0.5) * vp.Y, depth), depth > 0 and math.abs(nx) <= 1 and math.abs(ny) <= 1
end
Harness.defineMethods("Camera", {
    WorldToViewportPoint = function(self, pos) return worldToViewport(self, pos) end,
    WorldToScreenPoint = function(self, pos) return worldToViewport(self, pos) end,
    ViewportPointToRay = function(self, x, y)
        local vp = Harness.viewport
        local h = math.tan(math.rad(self.FieldOfView) / 2)
        local nx, ny = (x / vp.X - 0.5) * 2, (0.5 - y / vp.Y) * 2
        local dir = self.CFrame:VectorToWorldSpace(V3n(nx * h * vp.X / vp.Y, ny * h, -1)).Unit
        return { Origin = self.CFrame.Position, Direction = dir }
    end,
    ScreenPointToRay = function(self, x, y)
        local cam = self
        return Harness.service("Workspace").CurrentCamera:ViewportPointToRay(x, y)
    end,
    GetRenderCFrame = function(self) return self.CFrame end,
})
Harness.defineMethods("Workspace", {
    Raycast = function(self, origin, direction, params)
        Harness.calls["Workspace:Raycast"] = (Harness.calls["Workspace:Raycast"] or 0) + 1
        return Harness.raycastResult
    end,
    GetServerTimeNow = function() return os.time() end,
})

local function makePart(name, x, y, z, parent)
    local p = Harness.new("Part", { Name = name, Size = V3n(2, 2, 1), CFrame = CFrame.new(x, y, z) }, parent)
    return p
end

local function makeCharacter(name, x, y, z)
    local model = Harness.new("Model", { Name = name })
    local hum = Harness.new("Humanoid", { Name = "Humanoid" }, model)
    local root = makePart("HumanoidRootPart", x, y, z, model)
    makePart("Head", x, y + 1.5, z, model)
    model.PrimaryPart = root
    Harness.rawSet(hum, "FloorMaterial", Enum.Material.Plastic)
    model.Parent = Workspace
    return model
end
Harness.makeCharacter = makeCharacter

local PlayerModuleStub = { GetControls = function() return { GetMoveVector = function() return Vector3.new(0, 0, 0) end, Enable = function() end, Disable = function() end } end }
Harness.moduleValues = setmetatable({}, { __mode = "k" })

local function makePlayer(name, userId, x, z)
    local plr = Harness.new("Player", { Name = name, UserId = userId, DisplayName = name }, Players)
    local gui = Harness.new("PlayerGui", { Name = "PlayerGui" }, plr)
    local scripts = Harness.new("PlayerScripts", { Name = "PlayerScripts" }, plr)
    local pm = Harness.new("ModuleScript", { Name = "PlayerModule" }, scripts)
    Harness.moduleValues[pm] = PlayerModuleStub
    local char = makeCharacter(name, x, 5, z)
    Harness.rawSet(plr, "Character", char)
    return plr
end

local localPlayer = makePlayer("Tester", 1001, 0, 0)
Harness.rawSet(Players, "LocalPlayer", localPlayer)
Harness.rawSet(Players, "MaxPlayers", 12)
Harness.localPlayer = localPlayer
Harness.others = { makePlayer("Alice", 1002, 10, 0), makePlayer("Bob", 1003, 50, 50) }
Camera.CameraSubject = localPlayer.Character.Humanoid
Camera.CFrame = CFrame.new(0, 8, 14) * CFrame.Angles(math.rad(-15), 0, 0)

Harness.defineMethods("Players", {
    GetPlayers = function(self)
        local out = {}
        for _, c in ipairs(self:GetChildren()) do
            if c.ClassName == "Player" then table.insert(out, c) end
        end
        return out
    end,
    GetPlayerFromCharacter = function(self, model)
        for _, p in ipairs(self:GetPlayers()) do
            if p.Character == model then return p end
        end
        return nil
    end,
    GetPlayerByUserId = function(self, id)
        for _, p in ipairs(self:GetPlayers()) do
            if p.UserId == id then return p end
        end
        return nil
    end,
    GetUserThumbnailAsync = function(self, userId, thumbType, size)
        return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150", true
    end,
})
Harness.defineMethods("Player", {
    GetMouse = function(self) return { Hit = CFrame.new(), Target = nil, X = 640, Y = 360 } end,
    Kick = function(self, msg) Harness.calls["Player:Kick"] = msg end,
})
Harness.defineMethods("VirtualUser", {
    CaptureController = function() Harness.calls["VirtualUser:CaptureController"] = (Harness.calls["VirtualUser:CaptureController"] or 0) + 1 end,
    ClickButton2 = function() Harness.calls["VirtualUser:ClickButton2"] = (Harness.calls["VirtualUser:ClickButton2"] or 0) + 1 end,
})

local bound = {}
Harness.defineMethods("RunService", {
    IsStudio = function() return false end,
    IsClient = function() return true end,
    IsServer = function() return false end,
    IsRunning = function() return true end,
    Set3dRenderingEnabled = function(self, on) Harness.render3d = on end,
    BindToRenderStep = function(self, name, priority, fn) bound[name] = fn end,
    UnbindFromRenderStep = function(self, name) bound[name] = nil end,
})
Harness.render3d = true
Harness.onFrame(function(dt)
    RunService.RenderStepped:_fire(dt)
    for _, fn in pairs(bound) do task.spawn(fn, dt) end
    RunService.Stepped:_fire(Harness.now(), dt)
    RunService.Heartbeat:_fire(dt)
end)

Harness.keysDown = {}
Harness.mouse = Vector2.new(640, 360)
Harness.defineMethods("UserInputService", {
    GetKeysPressed = function() return table.clone(Harness.keysDown) end,
    IsKeyDown = function(self, key)
        for _, k in ipairs(Harness.keysDown) do if k.KeyCode == key then return true end end
        return false
    end,
    IsMouseButtonPressed = function() return false end,
    GetMouseLocation = function() return Harness.mouse end,
    GetFocusedTextBox = function() return Harness.focusedTextBox end,
    GetLastInputType = function() return Enum.UserInputType.Keyboard end,
    GetNavigationGamepads = function() return {} end,
    GetMouseDelta = function() return Vector2.new(0, 0) end,
})
Harness.rawSet(UIS, "KeyboardEnabled", true)
Harness.rawSet(UIS, "MouseEnabled", true)
Harness.rawSet(UIS, "TouchEnabled", false)
Harness.rawSet(UIS, "GamepadEnabled", false)

local coreEnabled, cores = {}, {}
Harness.cores = cores
Harness.defineMethods("StarterGui", {
    GetCoreGuiEnabled = function(self, t)
        local v = coreEnabled[t.Name]
        if v == nil then return true end
        return v
    end,
    SetCoreGuiEnabled = function(self, t, v) coreEnabled[t.Name] = v end,
    SetCore = function(self, name, value)
        cores[name] = value
        Harness.calls["StarterGui:SetCore:" .. tostring(name)] = (Harness.calls["StarterGui:SetCore:" .. tostring(name)] or 0) + 1
    end,
    GetCore = function(self, name) return cores[name] end,
})

Harness.defineMethods("TextService", {
    GetTextSize = function(self, text, size, font, bounds)
        local w = (utf8.len(text) or #text) * size * 0.5
        local lines = 1
        local _, nl = text:gsub("\n", "")
        lines += nl
        if bounds and bounds.X > 0 and w > bounds.X then
            lines = math.max(lines, math.ceil(w / bounds.X))
            w = bounds.X
        end
        return Vector2.new(w, lines * size)
    end,
})

Harness.defineMethods("GuiService", {
    GetErrorMessage = function() return Harness.errorMessage or "" end,
    GetGuiInset = function() return Vector2.new(0, 36), Vector2.new(0, 0) end,
})

local net = Harness.new("Folder", { Name = "Network" }, Stats)
local ssi = Harness.new("Folder", { Name = "ServerStatsItem" }, net)
local ping = Harness.new("StatsItem", { Name = "Data Ping" }, ssi)
Harness.defineMethods("StatsItem", { GetValue = function() return Harness.ping or 42 end })

Harness.new("ChatInputBarConfiguration", { Name = "ChatInputBarConfiguration" }, TextChatService)
local channels = Harness.new("Folder", { Name = "TextChannels" }, TextChatService)
Harness.new("TextChannel", { Name = "RBXGeneral" }, channels)

Harness.defineMethods("TeleportService", {
    Teleport = function(self, placeId, player)
        table.insert(Harness.teleports, { kind = "Teleport", placeId = placeId })
        if Harness.teleportFails then
            Harness.signal(self, "TeleportInitFailed"):_fire(player, Enum.TeleportResult.Failure, "mock failure", placeId, nil)
        end
    end,
    TeleportToPlaceInstance = function(self, placeId, jobId, player)
        table.insert(Harness.teleports, { kind = "Instance", placeId = placeId, jobId = jobId })
        if Harness.teleportFails then
            Harness.signal(self, "TeleportInitFailed"):_fire(player, Enum.TeleportResult.GameFull, "mock full", placeId, nil)
        end
    end,
})

Harness.defineMethods("TweenService", {
    Create = function(self, inst, info, goal)
        if typeof(inst) ~= "Instance" then error("Unable to cast value to Object", 2) end
        if typeof(info) ~= "TweenInfo" then error("Unable to cast value to TweenInfo", 2) end
        local st = STATE[inst]
        for k, v in pairs(goal) do
            if st.info.props[k] == nil then error(tostring(k) .. " is not a valid property name.", 2) end
        end
        local tw = Harness.new("Tween")
        local tst = STATE[tw]
        tst.tween = { inst = inst, info = info, goal = goal, token = 0 }
        return tw
    end,
})
local function finishTween(tw, token)
    local tst = STATE[tw]
    local t = tst.tween
    if t.token ~= token or tst.props.PlaybackState ~= Enum.PlaybackState.Playing then return end
    for k, v in pairs(t.goal) do
        local ok, err = pcall(function() t.inst[k] = v end)
        if not ok then
            table.insert(Harness.errors, "tween apply failed: " .. tostring(err))
            print("[THREAD ERROR] tween apply failed: " .. tostring(err))
        end
    end
    Harness.rawSet(tw, "PlaybackState", Enum.PlaybackState.Completed)
    Harness.signal(tw, "Completed"):_fire(Enum.PlaybackState.Completed)
end
Harness.defineMethods("Tween", {
    Play = function(self)
        local tst = STATE[self]
        local t = tst.tween
        t.token += 1
        local token = t.token
        Harness.rawSet(self, "PlaybackState", Enum.PlaybackState.Playing)
        task.delay(math.max(t.info.Time, 0) + (t.info.DelayTime or 0), function() finishTween(self, token) end)
    end,
    Cancel = function(self)
        local tst = STATE[self]
        if tst.props.PlaybackState == Enum.PlaybackState.Playing or tst.props.PlaybackState == Enum.PlaybackState.Paused then
            tst.tween.token += 1
            Harness.rawSet(self, "PlaybackState", Enum.PlaybackState.Cancelled)
            Harness.signal(self, "Completed"):_fire(Enum.PlaybackState.Cancelled)
        end
    end,
    Pause = function(self)
        local tst = STATE[self]
        tst.tween.token += 1
        Harness.rawSet(self, "PlaybackState", Enum.PlaybackState.Paused)
    end,
    Destroy = nil,
})

local function jsonEscape(s)
    return (s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n"
        elseif c == "\r" then return "\\r" elseif c == "\t" then return "\\t" end
        return string.format("\\u%04x", c:byte())
    end))
end

local function jsonEncode(v, depth)
    depth = depth or 0
    if depth > 100 then error("Cannot convert deeply nested table to JSON") end
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then error("Can't convert number to JSON") end
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return string.format("%.14g", v)
    end
    if t == "string" then return '"' .. jsonEscape(v) .. '"' end
    if t == "table" then
        local n = 0
        for _ in pairs(v) do n += 1 end
        if n == 0 then return "[]" end
        local isArray = #v == n
        local parts = {}
        if isArray then
            for i = 1, n do table.insert(parts, jsonEncode(v[i], depth + 1)) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do
            if type(k) ~= "string" then error("Can't convert table with non-string key to JSON") end
            table.insert(keys, k)
        end
        table.sort(keys)
        for _, k in ipairs(keys) do table.insert(parts, '"' .. jsonEscape(k) .. '":' .. jsonEncode(v[k], depth + 1)) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    error("Can't convert " .. t .. " to JSON")
end

local function jsonDecode(s)
    local pos = 1
    local function fail(msg) error("Can't parse JSON: " .. msg .. " at " .. pos) end
    local function skip() pos = s:find("[^ \n\r\t]", pos) or #s + 1 end
    local parseValue
    local function parseString()
        local out = {}
        pos += 1
        while true do
            local c = s:sub(pos, pos)
            if c == "" then fail("unterminated string") end
            if c == '"' then pos += 1 break end
            if c == "\\" then
                local e = s:sub(pos + 1, pos + 1)
                local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ["/"] = "/", ["\\"] = "\\", ['"'] = '"' }
                if e == "u" then
                    local hex = s:sub(pos + 2, pos + 5)
                    if not hex:match("^%x%x%x%x$") then fail("bad unicode escape") end
                    table.insert(out, utf8.char(tonumber(hex, 16)))
                    pos += 6
                elseif map[e] then
                    table.insert(out, map[e])
                    pos += 2
                else
                    fail("bad escape")
                end
            else
                table.insert(out, c)
                pos += 1
            end
        end
        return table.concat(out)
    end
    parseValue = function()
        skip()
        local c = s:sub(pos, pos)
        if c == "{" then
            pos += 1
            local obj = {}
            skip()
            if s:sub(pos, pos) == "}" then pos += 1 return obj end
            while true do
                skip()
                if s:sub(pos, pos) ~= '"' then fail("expected key") end
                local k = parseString()
                skip()
                if s:sub(pos, pos) ~= ":" then fail("expected ':'") end
                pos += 1
                obj[k] = parseValue()
                skip()
                local d = s:sub(pos, pos)
                pos += 1
                if d == "}" then break end
                if d ~= "," then fail("expected ',' or '}'") end
            end
            return obj
        elseif c == "[" then
            pos += 1
            local arr, n = {}, 0
            skip()
            if s:sub(pos, pos) == "]" then pos += 1 return arr end
            while true do
                n += 1
                arr[n] = parseValue()
                skip()
                local d = s:sub(pos, pos)
                pos += 1
                if d == "]" then break end
                if d ~= "," then fail("expected ',' or ']'") end
            end
            return arr
        elseif c == '"' then
            return parseString()
        elseif s:sub(pos, pos + 3) == "true" then pos += 4 return true
        elseif s:sub(pos, pos + 4) == "false" then pos += 5 return false
        elseif s:sub(pos, pos + 3) == "null" then pos += 4 return nil
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
            if not num or num == "" then fail("unexpected character") end
            pos += #num
            return tonumber(num)
        end
    end
    local v = parseValue()
    skip()
    if pos <= #s then fail("trailing characters") end
    return v
end
Harness.jsonEncode, Harness.jsonDecode = jsonEncode, jsonDecode

local guidCounter = 0
Harness.defineMethods("HttpService", {
    JSONEncode = function(self, v) return jsonEncode(v) end,
    JSONDecode = function(self, s)
        if type(s) ~= "string" then error("Unable to cast value to string", 2) end
        return jsonDecode(s)
    end,
    GenerateGUID = function(self, wrap)
        guidCounter += 1
        local g = string.format("%08X-0000-4000-8000-%012X", guidCounter, 0xABCDEF + guidCounter)
        if wrap == false then return g end
        return "{" .. g .. "}"
    end,
    UrlEncode = function(self, s)
        return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
    end,
})

local FILES, FOLDERS = {}, {}
Harness.fs, Harness.folders = FILES, FOLDERS
local function parentOf(path) return path:match("^(.*)/[^/]*$") end
isfolder = function(p) return FOLDERS[p] == true end
makefolder = function(p) FOLDERS[p] = true end
isfile = function(p) return FILES[p] ~= nil end
readfile = function(p)
    local v = FILES[p]
    if v == nil then error("readfile: file '" .. tostring(p) .. "' does not exist", 2) end
    return v
end
writefile = function(p, content)
    if type(content) ~= "string" then error("writefile: content must be a string", 2) end
    local parent = parentOf(p)
    if parent and not FOLDERS[parent] then error("writefile: folder '" .. parent .. "' does not exist", 2) end
    FILES[p] = content
end
delfile = function(p) FILES[p] = nil end
listfiles = function(folder)
    local out = {}
    for p in pairs(FILES) do if parentOf(p) == folder then table.insert(out, p) end end
    table.sort(out)
    return out
end

setclipboard = function(text) Harness.clipboard = text end
getclipboard = function() return Harness.clipboard end

Harness.requestLog = {}
Harness.requestHandler = function(opts)
    local url = tostring(opts.Url or opts.url or "")
    if url:find("/servers/Public", 1, true) then
        local data = {}
        for i = 1, 25 do
            data[i] = {
                id = string.format("%08x-aaaa-4bbb-8ccc-%012x", 0x1000 + i, 0x2000 + i),
                playing = (i % 11) + 1, maxPlayers = 12, ping = 40 + i * 6, fps = 30 + (i % 30),
            }
        end
        return { Success = true, StatusCode = 200, StatusMessage = "OK", Body = jsonEncode({ data = data }), Headers = {} }
    end
    return { Success = true, StatusCode = 200, StatusMessage = "OK", Body = "{}", Headers = {} }
end
request = function(opts)
    table.insert(Harness.requestLog, opts)
    return Harness.requestHandler(opts)
end
http_request = request

local hui = Harness.new("Folder", { Name = "HiddenUI" })
gethui = function() return hui end
getgenv = function() return Harness.genv end
identifyexecutor = function() return "MockExec", "1.0" end
Harness.queued = {}
queue_on_teleport = function(code) table.insert(Harness.queued, code) end
local fpsCap = 60
setfpscap = function(n) fpsCap = n end
getfpscap = function() return fpsCap end
checkcaller = function() return Harness.callerIsExecutor ~= false end
newcclosure = function(fn) return fn end
Harness.hooks = {}
hookfunction = function(target, hook)
    table.insert(Harness.hooks, { target = target, hook = hook })
    return target
end
hookmetamethod = function(obj, name, hook)
    table.insert(Harness.hooks, { metamethod = name, hook = hook })
    return function(...) return nil end
end
getnamecallmethod = function() return Harness.namecallMethod or "" end

Harness.HIDDEN_DEFAULTS = { Terrain = { Decoration = true } }
local hidden = setmetatable({}, { __mode = "k" })
gethiddenproperty = function(inst, prop)
    local st = STATE[inst]
    if st.info.props[prop] ~= nil then return inst[prop], false end
    local store = hidden[inst]
    if store and store[prop] ~= nil then return store[prop], true end
    local d = Harness.HIDDEN_DEFAULTS[st.cls]
    if d and d[prop] ~= nil then return d[prop], true end
    error("gethiddenproperty: '" .. tostring(prop) .. "' is not a valid property of " .. st.cls, 2)
end
sethiddenproperty = function(inst, prop, value)
    local st = STATE[inst]
    if st.info.props[prop] ~= nil then inst[prop] = value return false end
    local d = Harness.HIDDEN_DEFAULTS[st.cls]
    if not (d and d[prop] ~= nil) then error("sethiddenproperty: '" .. tostring(prop) .. "' is not a valid property of " .. st.cls, 2) end
    hidden[inst] = hidden[inst] or {}
    hidden[inst][prop] = value
    return true
end

local userSettings, userGameSettings, globalSettings
UserSettings = function()
    if not userSettings then
        userSettings = Harness.new("UserSettings")
        userGameSettings = Harness.new("UserGameSettings", { Name = "UserGameSettings" }, userSettings)
        Harness.rawSet(userGameSettings, "MasterVolume", 1)
    end
    return userSettings
end
Harness.defineMethods("UserSettings", {
    GetService = function(self, name)
        if name == "UserGameSettings" then return userGameSettings end
        error("'" .. tostring(name) .. "' is not a valid Service name", 2)
    end,
})
settings = function()
    if not globalSettings then
        globalSettings = Harness.new("GlobalSettings")
        Harness.new("RenderSettings", { Name = "Rendering" }, globalSettings)
    end
    return globalSettings
end

local realRequire = require
require = function(m)
    if typeof(m) == "Instance" then
        local v = Harness.moduleValues[m]
        if v ~= nil then return v end
        error("Attempted to call require with invalid argument(s).", 2)
    end
    return realRequire(m)
end

Harness.inputObject = function(inputType, state, extra)
    local o = {
        UserInputType = inputType, UserInputState = state, KeyCode = Enum.KeyCode.Unknown,
        Position = Vector3.new(Harness.mouse.X, Harness.mouse.Y, 0), Delta = Vector3.new(0, 0, 0),
    }
    for k, v in pairs(extra or {}) do o[k] = v end
    return o
end