
dofile("/tmp/test_inspect/m0_schema.lua")
CLASSDATA.Player.r.CameraMaxZoomDistance = "number"
CLASSDATA.Player.r.CameraMinZoomDistance = "number"
CLASSDATA.TextLabel.r.TextSelectable = "boolean"
CLASSDATA.TextButton.r.TextSelectable = "boolean"

loadLuauFile("/tmp/test_inspect/extracted/test/m1_core.lua")()
loadLuauFile("/tmp/test_inspect/m2_instance_patched.lua")()
loadLuauFile("/tmp/test_inspect/extracted/test/m3_env.lua")()

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

local dir = "/tmp/test_inspect/extracted/"
for _, name in ipairs({ "MainWeb.lua", "Status_Server.lua", "Local.lua", "Script.lua", "FPS.lua", "Settings.lua" }) do
    local fh = assert(io.open(dir .. name, "rb"))
    Harness.files[name] = fh:read("*a")
    fh:close()
end
makefolder("Elysera")
