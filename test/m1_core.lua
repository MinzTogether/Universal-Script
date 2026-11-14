local RealOs = os
local realTypeof = typeof
local VT = 0

Harness = { errors = {}, warns = {}, files = {}, teleports = {}, clipboard = "", T0 = 1700000000, genv = {}, calls = {} }
H = Harness

typeof = function(v)
    if type(v) == "table" then
        local mt = getmetatable(v)
        local ty = mt and rawget(mt, "__type")
        if ty then return ty end
    end
    return realTypeof(v)
end

os = setmetatable({
    clock = function() return VT end,
    time = function(t) if t then return RealOs.time(t) end return Harness.T0 + math.floor(VT) end,
}, { __index = RealOs })
time = function() return VT end
tick = function() return Harness.T0 + VT end
elapsedTime = function() return VT end

warn = function(...)
    local parts = table.pack(...)
    for i = 1, parts.n do parts[i] = tostring(parts[i]) end
    local msg = table.concat(parts, " ", 1, parts.n)
    table.insert(Harness.warns, msg)
    print("[warn] " .. msg)
end

local timers, deferred, timerSeq = {}, {}, 0
local cancelled = setmetatable({}, { __mode = "k" })

local function report(co, err)
    local msg = tostring(err)
    table.insert(Harness.errors, msg)
    print("[THREAD ERROR] " .. msg)
end

local function resume(co, ...)
    if cancelled[co] or coroutine.status(co) ~= "suspended" then return end
    local ok, err = coroutine.resume(co, ...)
    if not ok then report(co, err) end
end

local function toThread(f)
    if type(f) == "thread" then return f end
    return coroutine.create(f)
end

task = {
    spawn = function(f, ...)
        local co = toThread(f)
        resume(co, ...)
        return co
    end,
    defer = function(f, ...)
        local co = toThread(f)
        table.insert(deferred, { co = co, args = table.pack(...) })
        return co
    end,
    delay = function(t, f, ...)
        local co = toThread(f)
        timerSeq += 1
        table.insert(timers, { at = VT + (t or 0), seq = timerSeq, co = co, args = table.pack(...) })
        return co
    end,
    wait = function(t)
        local co = coroutine.running()
        local started = VT
        timerSeq += 1
        table.insert(timers, { at = VT + (t or 1 / 30), seq = timerSeq, co = co, args = table.pack() })
        coroutine.yield()
        return VT - started, VT
    end,
    cancel = function(co)
        cancelled[co] = true
        for i = #timers, 1, -1 do if timers[i].co == co then table.remove(timers, i) end end
        for i = #deferred, 1, -1 do if deferred[i].co == co then table.remove(deferred, i) end end
        if co ~= coroutine.running() then pcall(coroutine.close, co) end
    end,
    synchronize = function() end,
    desynchronize = function() end,
}

function Harness.flush()
    local guard = 0
    while #deferred > 0 do
        guard += 1
        if guard > 200000 then
            table.insert(Harness.errors, "deferred queue runaway")
            print("[HARNESS] deferred queue runaway")
            deferred = {}
            break
        end
        local item = table.remove(deferred, 1)
        resume(item.co, table.unpack(item.args, 1, item.args.n))
    end
end

local frameHooks = {}
function Harness.onFrame(fn) table.insert(frameHooks, fn) end

function Harness.step(dt)
    VT += dt
    table.sort(timers, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.seq < b.seq
    end)
    while timers[1] and timers[1].at <= VT + 1e-9 do
        local t = table.remove(timers, 1)
        resume(t.co, table.unpack(t.args, 1, t.args.n))
    end
    for _, fn in ipairs(frameHooks) do fn(dt) end
    Harness.flush()
end

function Harness.advance(seconds, dt)
    dt = dt or 1 / 30
    local n = math.max(1, math.floor(seconds / dt + 0.5))
    for _ = 1, n do Harness.step(dt) end
end

function Harness.now() return VT end

local SignalMT = { __type = "RBXScriptSignal" }
SignalMT.__index = SignalMT
local ConnMT = { __type = "RBXScriptConnection" }
ConnMT.__index = ConnMT

function ConnMT.Disconnect(self)
    self.Connected = false
    local sig = self._sig
    if sig then
        for i, c in ipairs(sig._conns) do
            if c == self then table.remove(sig._conns, i) break end
        end
    end
end
ConnMT.disconnect = ConnMT.Disconnect

function Harness.newSignal(name)
    return setmetatable({ _conns = {}, _name = name }, SignalMT)
end

function SignalMT.Connect(self, fn)
    if type(fn) ~= "function" then error("Attempt to connect failed: Passed value is not a function", 2) end
    local c = setmetatable({ Connected = true, _sig = self, _fn = fn }, ConnMT)
    table.insert(self._conns, c)
    return c
end
SignalMT.connect = SignalMT.Connect

function SignalMT.Once(self, fn)
    local c
    c = self:Connect(function(...)
        c:Disconnect()
        fn(...)
    end)
    return c
end

function SignalMT.Wait(self)
    local co = coroutine.running()
    local c
    c = self:Connect(function(...)
        c:Disconnect()
        resume(co, ...)
    end)
    return coroutine.yield()
end

function SignalMT._fire(self, ...)
    if #self._conns == 0 then return end
    local args = table.pack(...)
    for _, c in ipairs(table.clone(self._conns)) do
        table.insert(deferred, {
            co = coroutine.create(function()
                if c.Connected then c._fn(table.unpack(args, 1, args.n)) end
            end),
            args = { n = 0 },
        })
    end
end

function SignalMT._disconnectAll(self)
    for _, c in ipairs(table.clone(self._conns)) do c.Connected = false end
    self._conns = {}
end

local V2MT = { __type = "Vector2" }
local V3MT = { __type = "Vector3" }
local V2M, V3M = {}, {}

local function V2(x, y) return setmetatable({ X = x, Y = y }, V2MT) end
local function V3(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V3MT) end

V2MT.__index = function(v, k)
    if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y) end
    if k == "Unit" then
        local m = math.sqrt(v.X * v.X + v.Y * v.Y)
        if m == 0 then return V2(0, 0) end
        return V2(v.X / m, v.Y / m)
    end
    local m = V2M[k]
    if m then return m end
    error(tostring(k) .. " is not a valid member of Vector2", 2)
end
V2MT.__newindex = function() error("Vector2 is immutable", 2) end
V2MT.__add = function(a, b) return V2(a.X + b.X, a.Y + b.Y) end
V2MT.__sub = function(a, b) return V2(a.X - b.X, a.Y - b.Y) end
V2MT.__mul = function(a, b)
    if type(a) == "number" then return V2(a * b.X, a * b.Y) end
    if type(b) == "number" then return V2(a.X * b, a.Y * b) end
    return V2(a.X * b.X, a.Y * b.Y)
end
V2MT.__div = function(a, b)
    if type(b) == "number" then return V2(a.X / b, a.Y / b) end
    return V2(a.X / b.X, a.Y / b.Y)
end
V2MT.__unm = function(a) return V2(-a.X, -a.Y) end
V2MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
V2MT.__tostring = function(a) return a.X .. ", " .. a.Y end
function V2M.Lerp(a, b, t) return V2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t) end
function V2M.Dot(a, b) return a.X * b.X + a.Y * b.Y end
function V2M.Cross(a, b) return a.X * b.Y - a.Y * b.X end
function V2M.Max(a, b) return V2(math.max(a.X, b.X), math.max(a.Y, b.Y)) end
function V2M.Min(a, b) return V2(math.min(a.X, b.X), math.min(a.Y, b.Y)) end
function V2M.Abs(a) return V2(math.abs(a.X), math.abs(a.Y)) end
function V2M.Floor(a) return V2(math.floor(a.X), math.floor(a.Y)) end
function V2M.Ceil(a) return V2(math.ceil(a.X), math.ceil(a.Y)) end

Vector2 = {
    new = function(x, y) return V2(x or 0, y or 0) end,
    zero = V2(0, 0),
    one = V2(1, 1),
    xAxis = V2(1, 0),
    yAxis = V2(0, 1),
}

V3MT.__index = function(v, k)
    if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
    if k == "Unit" then
        local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
        if m == 0 then return V3(0, 0, 0) end
        return V3(v.X / m, v.Y / m, v.Z / m)
    end
    local m = V3M[k]
    if m then return m end
    error(tostring(k) .. " is not a valid member of Vector3", 2)
end
V3MT.__newindex = function() error("Vector3 is immutable", 2) end
V3MT.__add = function(a, b) return V3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3MT.__sub = function(a, b) return V3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3MT.__mul = function(a, b)
    if type(a) == "number" then return V3(a * b.X, a * b.Y, a * b.Z) end
    if type(b) == "number" then return V3(a.X * b, a.Y * b, a.Z * b) end
    return V3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3MT.__div = function(a, b)
    if type(b) == "number" then return V3(a.X / b, a.Y / b, a.Z / b) end
    return V3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3MT.__unm = function(a) return V3(-a.X, -a.Y, -a.Z) end
V3MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3MT.__tostring = function(a) return a.X .. ", " .. a.Y .. ", " .. a.Z end
function V3M.Lerp(a, b, t) return V3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
function V3M.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3M.Cross(a, b) return V3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function V3M.Max(a, b) return V3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)) end
function V3M.Min(a, b) return V3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)) end
function V3M.Abs(a) return V3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z)) end
function V3M.FuzzyEq(a, b, e) e = e or 1e-5 return math.abs(a.X - b.X) <= e and math.abs(a.Y - b.Y) <= e and math.abs(a.Z - b.Z) <= e end

Vector3 = {
    new = function(x, y, z) return V3(x or 0, y or 0, z or 0) end,
    zero = V3(0, 0, 0),
    one = V3(1, 1, 1),
    xAxis = V3(1, 0, 0),
    yAxis = V3(0, 1, 0),
    zAxis = V3(0, 0, 1),
}

local CFMT = { __type = "CFrame" }
local CFM = {}

local function CF(x, y, z, R) return setmetatable({ X = x, Y = y, Z = z, R = R }, CFMT) end
local IDENT = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function matMul(a, b)
    local r = {}
    for i = 0, 2 do
        for j = 0, 2 do
            r[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[3 + j + 1] + a[i * 3 + 3] * b[6 + j + 1]
        end
    end
    return r
end

local function matVec(a, x, y, z)
    return a[1] * x + a[2] * y + a[3] * z, a[4] * x + a[5] * y + a[6] * z, a[7] * x + a[8] * y + a[9] * z
end

local function transpose(a)
    return { a[1], a[4], a[7], a[2], a[5], a[8], a[3], a[6], a[9] }
end

local function rotX(a) local c, s = math.cos(a), math.sin(a) return { 1, 0, 0, 0, c, -s, 0, s, c } end
local function rotY(a) local c, s = math.cos(a), math.sin(a) return { c, 0, s, 0, 1, 0, -s, 0, c } end
local function rotZ(a) local c, s = math.cos(a), math.sin(a) return { c, -s, 0, s, c, 0, 0, 0, 1 } end

local function toQuat(R)
    local tr = R[1] + R[5] + R[9]
    local w, x, y, z
    if tr > 0 then
        local s = math.sqrt(tr + 1) * 2
        w = 0.25 * s
        x = (R[8] - R[6]) / s
        y = (R[3] - R[7]) / s
        z = (R[4] - R[2]) / s
    elseif R[1] > R[5] and R[1] > R[9] then
        local s = math.sqrt(1 + R[1] - R[5] - R[9]) * 2
        w = (R[8] - R[6]) / s
        x = 0.25 * s
        y = (R[2] + R[4]) / s
        z = (R[3] + R[7]) / s
    elseif R[5] > R[9] then
        local s = math.sqrt(1 + R[5] - R[1] - R[9]) * 2
        w = (R[3] - R[7]) / s
        x = (R[2] + R[4]) / s
        y = 0.25 * s
        z = (R[6] + R[8]) / s
    else
        local s = math.sqrt(1 + R[9] - R[1] - R[5]) * 2
        w = (R[4] - R[2]) / s
        x = (R[3] + R[7]) / s
        y = (R[6] + R[8]) / s
        z = 0.25 * s
    end
    return w, x, y, z
end

local function fromQuat(w, x, y, z)
    local n = math.sqrt(w * w + x * x + y * y + z * z)
    if n == 0 then return { 1, 0, 0, 0, 1, 0, 0, 0, 1 } end
    w, x, y, z = w / n, x / n, y / n, z / n
    return {
        1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w),
        2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w),
        2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y),
    }
end

CFMT.__index = function(cf, k)
    local R = cf.R
    if k == "Position" then return V3(cf.X, cf.Y, cf.Z) end
    if k == "RightVector" then return V3(R[1], R[4], R[7]) end
    if k == "UpVector" then return V3(R[2], R[5], R[8]) end
    if k == "LookVector" then return V3(-R[3], -R[6], -R[9]) end
    if k == "Rotation" then return CF(0, 0, 0, R) end
    local m = CFM[k]
    if m then return m end
    error(tostring(k) .. " is not a valid member of CFrame", 2)
end
CFMT.__newindex = function() error("CFrame is immutable", 2) end
CFMT.__mul = function(a, b)
    if typeof(b) == "CFrame" then
        local x, y, z = matVec(a.R, b.X, b.Y, b.Z)
        return CF(a.X + x, a.Y + y, a.Z + z, matMul(a.R, b.R))
    end
    local x, y, z = matVec(a.R, b.X, b.Y, b.Z)
    return V3(a.X + x, a.Y + y, a.Z + z)
end
CFMT.__add = function(a, b) return CF(a.X + b.X, a.Y + b.Y, a.Z + b.Z, a.R) end
CFMT.__sub = function(a, b) return CF(a.X - b.X, a.Y - b.Y, a.Z - b.Z, a.R) end
CFMT.__eq = function(a, b)
    if a.X ~= b.X or a.Y ~= b.Y or a.Z ~= b.Z then return false end
    for i = 1, 9 do if a.R[i] ~= b.R[i] then return false end end
    return true
end
CFMT.__tostring = function(a) return a.X .. ", " .. a.Y .. ", " .. a.Z end

function CFM.Inverse(a)
    local Rt = transpose(a.R)
    local x, y, z = matVec(Rt, -a.X, -a.Y, -a.Z)
    return CF(x, y, z, Rt)
end
function CFM.ToWorldSpace(a, b) return a * b end
function CFM.ToObjectSpace(a, b) return CFM.Inverse(a) * b end
function CFM.PointToWorldSpace(a, v) return a * v end
function CFM.PointToObjectSpace(a, v) return CFM.Inverse(a) * v end
function CFM.VectorToWorldSpace(a, v) return V3(matVec(a.R, v.X, v.Y, v.Z)) end
function CFM.VectorToObjectSpace(a, v) return V3(matVec(transpose(a.R), v.X, v.Y, v.Z)) end
function CFM.ToOrientation(a)
    local R = a.R
    return math.asin(math.clamp(-R[6], -1, 1)), math.atan2(R[3], R[9]), math.atan2(R[4], R[5])
end
function CFM.ToEulerAnglesYXZ(a) return CFM.ToOrientation(a) end
function CFM.ToEulerAnglesXYZ(a)
    local R = a.R
    return math.atan2(-R[6], R[9]), math.asin(math.clamp(R[3], -1, 1)), math.atan2(-R[2], R[1])
end
function CFM.GetComponents(a)
    local R = a.R
    return a.X, a.Y, a.Z, R[1], R[2], R[3], R[4], R[5], R[6], R[7], R[8], R[9]
end
function CFM.Lerp(a, b, t)
    local w1, x1, y1, z1 = toQuat(a.R)
    local w2, x2, y2, z2 = toQuat(b.R)
    local dot = w1 * w2 + x1 * x2 + y1 * y2 + z1 * z2
    if dot < 0 then w2, x2, y2, z2, dot = -w2, -x2, -y2, -z2, -dot end
    local w, x, y, z
    if dot > 0.9995 then
        w, x, y, z = w1 + (w2 - w1) * t, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, z1 + (z2 - z1) * t
    else
        local th = math.acos(dot)
        local s1, s2 = math.sin((1 - t) * th) / math.sin(th), math.sin(t * th) / math.sin(th)
        w, x, y, z = w1 * s1 + w2 * s2, x1 * s1 + x2 * s2, y1 * s1 + y2 * s2, z1 * s1 + z2 * s2
    end
    return CF(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t, fromQuat(w, x, y, z))
end
function CFM.FuzzyEq(a, b, e)
    e = e or 1e-5
    if math.abs(a.X - b.X) > e or math.abs(a.Y - b.Y) > e or math.abs(a.Z - b.Z) > e then return false end
    for i = 1, 9 do if math.abs(a.R[i] - b.R[i]) > e then return false end end
    return true
end
function CFM.Orthonormalize(a) return a end

local function lookAt(at, target, up)
    up = up or V3(0, 1, 0)
    local z = at - target
    if z.Magnitude == 0 then return CF(at.X, at.Y, at.Z, IDENT) end
    z = z.Unit
    local x = up:Cross(z)
    if x.Magnitude < 1e-8 then
        x = V3(0, 0, 1):Cross(z)
        if x.Magnitude < 1e-8 then x = V3(1, 0, 0) end
    end
    x = x.Unit
    local y = z:Cross(x)
    return CF(at.X, at.Y, at.Z, { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z })
end

CFrame = {
    new = function(a, b, c, ...)
        if a == nil then return CF(0, 0, 0, IDENT) end
        if typeof(a) == "Vector3" then
            if typeof(b) == "Vector3" then return lookAt(a, b) end
            return CF(a.X, a.Y, a.Z, IDENT)
        end
        local rest = table.pack(...)
        if rest.n == 0 then return CF(a, b, c, IDENT) end
        if rest.n == 4 then return CF(a, b, c, fromQuat(rest[4], rest[1], rest[2], rest[3])) end
        return CF(a, b, c, { rest[1], rest[2], rest[3], rest[4], rest[5], rest[6], rest[7], rest[8], rest[9] })
    end,
    lookAt = lookAt,
    Angles = function(rx, ry, rz) return CF(0, 0, 0, matMul(matMul(rotX(rx or 0), rotY(ry or 0)), rotZ(rz or 0))) end,
    fromOrientation = function(rx, ry, rz) return CF(0, 0, 0, matMul(matMul(rotY(ry or 0), rotX(rx or 0)), rotZ(rz or 0))) end,
    fromEulerAnglesXYZ = function(rx, ry, rz) return CF(0, 0, 0, matMul(matMul(rotX(rx or 0), rotY(ry or 0)), rotZ(rz or 0))) end,
    identity = CF(0, 0, 0, IDENT),
}

local C3MT = { __type = "Color3" }
local C3M = {}
local function C3(r, g, b) return setmetatable({ R = r, G = g, B = b }, C3MT) end
C3MT.__index = function(c, k)
    local m = C3M[k]
    if m then return m end
    error(tostring(k) .. " is not a valid member of Color3", 2)
end
C3MT.__newindex = function() error("Color3 is immutable", 2) end
C3MT.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
C3MT.__tostring = function(c) return c.R .. ", " .. c.G .. ", " .. c.B end
function C3M.ToHex(c)
    local function h(v) return string.format("%02x", math.floor(math.clamp(v, 0, 1) * 255 + 0.5)) end
    return h(c.R) .. h(c.G) .. h(c.B)
end
function C3M.Lerp(a, b, t) return C3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end
function C3M.ToHSV(c)
    local mx, mn = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
    local d = mx - mn
    local h = 0
    if d ~= 0 then
        if mx == c.R then h = ((c.G - c.B) / d) % 6
        elseif mx == c.G then h = (c.B - c.R) / d + 2
        else h = (c.R - c.G) / d + 4 end
        h = h / 6
    end
    return h, (mx == 0) and 0 or d / mx, mx
end
local function fromHSV(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return C3(v, t, p) elseif i == 1 then return C3(q, v, p) elseif i == 2 then return C3(p, v, t)
    elseif i == 3 then return C3(p, q, v) elseif i == 4 then return C3(t, p, v) else return C3(v, p, q) end
end

Color3 = {
    new = function(r, g, b) return C3(math.clamp(r or 0, 0, 1), math.clamp(g or 0, 0, 1), math.clamp(b or 0, 0, 1)) end,
    fromRGB = function(r, g, b) return C3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end,
    fromHSV = fromHSV,
    fromHex = function(hex)
        hex = tostring(hex):gsub("#", "")
        return C3(tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255)
    end,
}

local UDMT = { __type = "UDim" }
local function UD(s, o) return setmetatable({ Scale = s, Offset = o }, UDMT) end
UDMT.__index = function(_, k) error(tostring(k) .. " is not a valid member of UDim", 2) end
UDMT.__newindex = function() error("UDim is immutable", 2) end
UDMT.__eq = function(a, b) return a.Scale == b.Scale and a.Offset == b.Offset end
UDMT.__add = function(a, b) return UD(a.Scale + b.Scale, a.Offset + b.Offset) end
UDMT.__sub = function(a, b) return UD(a.Scale - b.Scale, a.Offset - b.Offset) end
UDim = { new = function(s, o) return UD(s or 0, o or 0) end }

local U2MT = { __type = "UDim2" }
local U2M = {}
local function U2(xs, xo, ys, yo)
    local t = setmetatable({ X = UD(xs, xo), Y = UD(ys, yo) }, U2MT)
    return t
end
U2MT.__index = function(u, k)
    if k == "Width" then return u.X end
    if k == "Height" then return u.Y end
    local m = U2M[k]
    if m then return m end
    error(tostring(k) .. " is not a valid member of UDim2", 2)
end
U2MT.__newindex = function() error("UDim2 is immutable", 2) end
U2MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
U2MT.__add = function(a, b) return U2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
U2MT.__sub = function(a, b) return U2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset) end
U2MT.__tostring = function(u) return "{" .. u.X.Scale .. ", " .. u.X.Offset .. "}, {" .. u.Y.Scale .. ", " .. u.Y.Offset .. "}" end
function U2M.Lerp(a, b, t)
    local function l(p, q) return p + (q - p) * t end
    return U2(l(a.X.Scale, b.X.Scale), l(a.X.Offset, b.X.Offset), l(a.Y.Scale, b.Y.Scale), l(a.Y.Offset, b.Y.Offset))
end

UDim2 = {
    new = function(a, b, c, d)
        if typeof(a) == "UDim" then return U2(a.Scale, a.Offset, b.Scale, b.Offset) end
        return U2(a or 0, b or 0, c or 0, d or 0)
    end,
    fromOffset = function(x, y) return U2(0, x or 0, 0, y or 0) end,
    fromScale = function(x, y) return U2(x or 0, 0, y or 0, 0) end,
}

local function plainType(name)
    local mt = { __type = name }
    mt.__index = function(_, k) error(tostring(k) .. " is not a valid member of " .. name, 2) end
    return mt
end

local CSKMT, CSMT = plainType("ColorSequenceKeypoint"), plainType("ColorSequence")
ColorSequenceKeypoint = { new = function(t, c) return setmetatable({ Time = t, Value = c }, CSKMT) end }
ColorSequence = {
    new = function(a, b)
        local kps
        if typeof(a) == "Color3" then
            kps = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
        else
            kps = a
        end
        return setmetatable({ Keypoints = kps }, CSMT)
    end,
}
CSMT.__eq = function(a, b)
    if #a.Keypoints ~= #b.Keypoints then return false end
    for i, k in ipairs(a.Keypoints) do
        local o = b.Keypoints[i]
        if k.Time ~= o.Time or k.Value ~= o.Value then return false end
    end
    return true
end

local NSKMT, NSMT, NRMT = plainType("NumberSequenceKeypoint"), plainType("NumberSequence"), plainType("NumberRange")
NumberSequenceKeypoint = { new = function(t, v, e) return setmetatable({ Time = t, Value = v, Envelope = e or 0 }, NSKMT) end }
NumberSequence = {
    new = function(a, b)
        local kps
        if type(a) == "number" then
            kps = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
        else
            kps = a
        end
        return setmetatable({ Keypoints = kps }, NSMT)
    end,
}
NumberRange = { new = function(a, b) return setmetatable({ Min = a, Max = b or a }, NRMT) end }

local TIMT = plainType("TweenInfo")
TweenInfo = {
    new = function(time, style, dir, repeatCount, reverses, delay)
        return setmetatable({
            Time = time or 1, EasingStyle = style, EasingDirection = dir,
            RepeatCount = repeatCount or 0, Reverses = reverses or false, DelayTime = delay or 0,
        }, TIMT)
    end,
}

local RPMT = { __type = "RaycastParams" }
RPMT.__index = function(t, k) error(tostring(k) .. " is not a valid member of RaycastParams", 2) end
RPMT.__newindex = function(t, k, v)
    if k ~= "FilterType" and k ~= "FilterDescendantsInstances" and k ~= "IgnoreWater" and k ~= "RespectCanCollide" and k ~= "CollisionGroup" and k ~= "BruteForceAllSlow" then
        error(tostring(k) .. " is not a valid member of RaycastParams", 2)
    end
    rawset(t, k, v)
end
RaycastParams = {
    new = function()
        local p = setmetatable({}, RPMT)
        rawset(p, "FilterDescendantsInstances", {})
        rawset(p, "IgnoreWater", false)
        return p
    end,
}

local EnumItemMT = { __type = "EnumItem" }
EnumItemMT.__index = function(i, k)
    if k == "IsA" then return function(self, n) return self.EnumType.Name == n end end
    error(tostring(k) .. " is not a valid member of EnumItem", 2)
end
EnumItemMT.__tostring = function(i) return "Enum." .. i.EnumType.Name .. "." .. i.Name end
EnumItemMT.__newindex = function() error("EnumItem is read-only", 2) end

local EnumTypeMT = { __type = "Enum" }
local enumTypes = {}

local function makeEnumType(name)
    local list = ENUMDATA[name]
    if not list then return nil end
    local et = setmetatable({ Name = name, _items = {}, _list = {} }, EnumTypeMT)
    for idx, iname in ipairs(list) do
        local value = idx - 1
        local digits = iname:match("^Level(%d+)$")
        if name == "QualityLevel" then
            if iname == "Automatic" then value = 0 elseif digits then value = tonumber(digits) end
        end
        local item = setmetatable({ Name = iname, Value = value, EnumType = et }, EnumItemMT)
        et._items[iname] = item
        table.insert(et._list, item)
    end
    return et
end

EnumTypeMT.__index = function(et, k)
    local item = rawget(et, "_items")[k]
    if item then return item end
    if k == "GetEnumItems" then return function(self) return table.clone(self._list) end end
    if k == "FromValue" then
        return function(self, v)
            for _, it in ipairs(self._list) do if it.Value == v then return it end end
            return nil
        end
    end
    if k == "FromName" then return function(self, n) return self._items[n] end end
    error(tostring(k) .. " is not a valid member of Enum." .. rawget(et, "Name"), 2)
end
EnumTypeMT.__newindex = function() error("Enum is read-only", 2) end
EnumTypeMT.__tostring = function(et) return "Enum." .. rawget(et, "Name") end

Enum = setmetatable({}, {
    __type = "Enums",
    __index = function(t, k)
        local et = enumTypes[k]
        if not et then
            et = makeEnumType(k)
            if not et then error(tostring(k) .. " is not a valid member of Enums", 2) end
            enumTypes[k] = et
        end
        return et
    end,
})