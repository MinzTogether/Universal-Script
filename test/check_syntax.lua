local files = {
    "/tmp/test_inspect/extracted/test/m1_core.lua",
    "/tmp/test_inspect/extracted/test/m2_instance.lua",
    "/tmp/test_inspect/extracted/test/m3_env.lua",
    "/tmp/test_inspect/extracted/MainWeb.lua",
    "/tmp/test_inspect/extracted/FPS.lua",
    "/tmp/test_inspect/extracted/Local.lua",
    "/tmp/test_inspect/extracted/Script.lua",
    "/tmp/test_inspect/extracted/Settings.lua",
    "/tmp/test_inspect/extracted/Status_Server.lua",
}
for _, f in ipairs(files) do
    local fn, err = loadfile(f)
    if fn then
        print("OK syntax:", f)
    else
        print("ERR syntax:", f, err)
    end
end
