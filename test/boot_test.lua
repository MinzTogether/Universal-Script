dofile("/tmp/test_inspect/m0_schema.lua")
loadLuauFile("/tmp/test_inspect/extracted/test/m1_core.lua")()
loadLuauFile("/tmp/test_inspect/extracted/test/m2_instance.lua")()
loadLuauFile("/tmp/test_inspect/extracted/test/m3_env.lua")()

-- Also define TextBox focus methods on Harness if not defined in m3_env:
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
    local f = assert(io.open(dir .. name, "rb"))
    Harness.files[name] = f:read("*a")
    f:close()
end

local Elysera = loadLuauFile(dir .. "MainWeb.lua")()
Harness.flush()
Harness.advance(2.0, 1/30)
print("Boot completed! Errors:", #Harness.errors, "Warns:", #Harness.warns)
for i, e in ipairs(Harness.errors) do print("ERR", i, e) end
for i, w in ipairs(Harness.warns) do print("WARN", i, w) end
print("Elysera Version:", Elysera and Elysera.Version)
print("Loaded modules:")
for k, v in pairs(Elysera and Elysera.Themes or {}) do
    print("  Theme", k, v.id, v.name, v.mode)
end
