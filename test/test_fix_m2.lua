dofile("/tmp/test_inspect/m0_schema.lua")
loadLuauFile("/tmp/test_inspect/extracted/test/m1_core.lua")()

-- Let's inspect m2_instance.lua with recursion guard on AutomaticSize
local f = assert(io.open("/tmp/test_inspect/extracted/test/m2_instance.lua", "rb"))
local m2_src = f:read("*a")
f:close()

-- Inject a re-entrancy guard `inAuto[inst]` around AutomaticSize in absSize
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

local Elysera = loadLuauFile(dir .. "MainWeb.lua")()
Harness.flush()
Harness.advance(2.0, 1/30)
print("Boot completed! Errors:", #Harness.errors, "Warns:", #Harness.warns)
for i, e in ipairs(Harness.errors) do print("ERR", i, e) end
for i, w in ipairs(Harness.warns) do print("WARN", i, w) end
