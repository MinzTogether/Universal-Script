--// ##########################################################################################
--// ##                                                                                      ##
--// ##   MANDATORY: USE ENGLISH (US) ONLY IN THIS FILE                                      ##
--// ##   Every comment, UI text, message and name here MUST be written in English (US).     ##
--// ##   Never add any other language to this file. Keep it English (US) on every edit.     ##
--// ##                                                                                      ##
--// ##########################################################################################

--// ================= SCRIPT TAB (module) =================
-- This file is loaded by the main script (MainWeb.lua / MainLocal.lua) and called with a ctx table
-- containing the shared UI functions/variables. Returns ScriptDialog so the main file
-- can use it when closing the UI (closeUI).
--
-- Library : save / edit / duplicate / pin / export / import / undo delete, search (by name or content) and sort (Added, A-Z, Edited, Recent)
-- Editor  : line numbers and live Lua syntax highlighting
-- Running : Run / Stop (supports returning a cleanup function `return function() ... end`), Output panel, Run clipboard, test run
-- Startup : Auto-run per script (All games or This game only; global pause in the menu); imported scripts must be reviewed before they run

return function(ctx)
    local ScriptTab           = ctx.Tab

    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local HttpService         = ctx.HttpService
    local canFS               = ctx.canFS

    local WHITE               = ctx.WHITE
    local CENTER              = ctx.CENTER
    local ANCHOR_CENTER       = ctx.ANCHOR_CENTER
    local EASE_QUAD           = ctx.EASE_QUAD
    local DIR_IN              = ctx.DIR_IN
    local DIR_OUT             = ctx.DIR_OUT
    local BUBBLE_IN_TIME      = ctx.BUBBLE_IN_TIME
    local BUBBLE_OUT_TIME     = ctx.BUBBLE_OUT_TIME
    local FADE_IN_TIME        = ctx.FADE_IN_TIME
    local FADE_OUT_TIME       = ctx.FADE_OUT_TIME
    local CONTENT_EDGE        = ctx.CONTENT_EDGE

    local new                 = ctx.new
    local corner              = ctx.corner
    local stroke              = ctx.stroke
    local padding             = ctx.padding
    local list                = ctx.list
    local label               = ctx.label
    local tween               = ctx.tween
    local pressScale          = ctx.pressScale
    local drawIcon            = ctx.drawIcon
    local setOverlay          = ctx.setOverlay

    local FunctionScroll      = ctx.FunctionScroll
    local DeleteDialog        = ctx.DeleteDialog

    local CreateInfoRow       = ctx.CreateInfoRow
    local flashStrokeError    = ctx.flashStrokeError
    local bindBoxFocus        = ctx.bindBoxFocus
    local isLocked            = ctx.isLocked -- replaces the main file's uiLocked variable
    local UI                  = assert(ctx.UI, "Script.lua needs ctx.UI: update MainWeb.lua / MainLocal.lua to the new core")
    local showToast           = assert(ctx.Toast or UI.Toast, "Script.lua needs ctx.Toast")

    --// ---- Constants ----
    -- Every file lives in the Elysera folder: dataPath comes from the main script (plain file name if it is missing)
    local dataPath            = ctx.dataPath or function(name) return name end
    local SCRIPT_FILE         = dataPath("L-scr.json")
    local BACKUP_FILE         = dataPath("L-scr.bak.json")
    local SCHEMA_VERSION      = 2
    local EXPORT_FORMAT       = "L-script-export"

    local MAX_NAME_LEN        = 60
    local MAX_SCRIPT_LEN      = 200000
    local MAX_IMPORT_ITEMS    = 200
    local MAX_IMPORT_BYTES    = 2000000
    local UNDO_SECONDS        = 6 -- 0 = delete immediately, no Undo

    local STATE_FILE          = dataPath("L-scr.state.json") -- run info + auto-run switch (small, rewritten often)
    local STARTUP_DELAY       = 1.5                          -- seconds after load before auto-run starts
    local REVIEW_SECONDS      = 5                            -- imported script: a second tap within this window runs it

    local SEARCH_MIN_ITEMS    = 5
    local SEARCH_H            = 30
    local PINNED_HEIGHT       = 36
    local TAB_LIST_GAP        = 10

    --// ---- Module state ----
    local ScriptList = {}                               -- array of v2 entries (plain data only, saved to file)
    local Rows       = {}                               -- [entry.id] = { Row, entry, nameLower, codeLower, refresh }
    local Running    = {}                               -- [entry.id] = { thread, cleanup, startedAt, onState, entry }
    local View       = { query = "", sort = "added" }

    -- forward declarations (assigned in the UI block below)
    local OutputPanel, StatusLabel, SearchRow, SearchBox, EmptyLabel, ScriptDialog
    local applyListView, CreateScriptRow, fitListPanel

    local function shorten(text, n)
        return #text > n and (text:sub(1, n) .. "...") or text
    end

    -- Border stroke from the shared UI kit (MainWeb.lua)
    local borderStroke = UI.BorderStroke

    local function firstLine(text)
        return (tostring(text):match("^[^\r\n]*"))
    end

    -- "just now", "5m ago", "3h ago", "2d ago", then a date
    local function ago(ts)
        local d = os.time() - ts
        if d < 45 then return "just now" end
        if d < 3600 then return ("%dm ago"):format(math.max(1, math.floor(d / 60))) end
        if d < 86400 then return ("%dh ago"):format(math.floor(d / 3600)) end
        if d < 7 * 86400 then return ("%dd ago"):format(math.floor(d / 86400)) end
        return os.date("%b %d", ts)
    end

    -- Token names, resolved on every lookup so the colors follow theme changes
    local function themedColors(tokens)
        return setmetatable({}, {
            __index = function(_, key)
                local token = tokens[key]
                return token and Theme[token]
            end,
        })
    end

    --// ---- Icons / icon buttons ----
    local function tintIcon(holder, color)
        for _, child in ipairs(holder:GetChildren()) do
            if child:IsA("Frame") then child.BackgroundColor3 = color end
        end
    end

    local function drawDots(holder, color)
        for i = 0, 2 do
            corner(new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, (i - 1) * 6),
                Size = UDim2.fromOffset(4, 4),
                BackgroundColor3 = color,
                BorderSizePixel = 0,
            }, holder), 2)
        end
    end

    local function CreateIconButton(parent, kind, rightOffset, iconColor)
        local Btn = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -rightOffset, 0.5, 0),
            Size = UDim2.fromOffset(28, 28),
            BackgroundColor3 = Theme.Header,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
        }, parent)
        corner(Btn, 6)
        stroke(Btn)
        pressScale(Btn, 0.92)

        local Holder = new("Frame", {
            Name = "Icon",
            AnchorPoint = ANCHOR_CENTER,
            Position = CENTER,
            Size = UDim2.fromOffset(18, 18),
            BackgroundTransparency = 1,
        }, Btn)
        if kind == "more" then
            drawDots(Holder, iconColor)
        else
            drawIcon(Holder, kind, iconColor, Theme.Header)
        end

        Btn.MouseEnter:Connect(function()
            if isLocked() then return end
            tween(Btn, 0.15, { BackgroundColor3 = Theme.Border })
        end)
        Btn.MouseLeave:Connect(function()
            tween(Btn, 0.15, { BackgroundColor3 = Theme.Header })
        end)
        return Btn, Holder
    end

    -- Primary button (purple -> pink). A UIGradient tints everything its own object draws, text included,
    -- so the caption is a child label. props: anchor, position, order, name
    local function createAccentButton(parent, text, width, height, props)
        props = props or {}
        local Btn = new("TextButton", {
            Name = props.name or "AccentButton",
            AnchorPoint = props.anchor,
            Position = props.position,
            LayoutOrder = props.order or 0,
            Size = UDim2.fromOffset(width, height),
            BackgroundColor3 = WHITE,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
        }, parent)
        corner(Btn, 6)
        new("UIGradient", { Color = ColorSequence.new(Theme.AccentPurple, Theme.AccentPink) }, Btn)
        local Caption = new("TextLabel", {
            Name = "Caption",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = text,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = Theme.ToggleKnobOn,
        }, Btn)
        Caption:SetAttribute("OnAccent", true) -- refreshStateColors keeps it readable on any theme
        pressScale(Btn, 0.95)
        Btn.MouseEnter:Connect(function()
            if not isLocked() then tween(Btn, 0.15, { BackgroundTransparency = 0.15 }) end
        end)
        Btn.MouseLeave:Connect(function() tween(Btn, 0.15, { BackgroundTransparency = 0 }) end)
        return Btn
    end

    --// ---- createEntry: the single source for creating v2 entries ----
    local function sanitizeName(rawName)
        local s = tostring(rawName or "")
        s = s:gsub("%c+", " ")
        s = s:gsub("%s+", " ")
        s = s:match("^%s*(.-)%s*$")
        local len = utf8.len(s)
        if not len then
            local out, count = {}, 0
            pcall(function()
                for _, cp in utf8.codes(s) do
                    if count >= MAX_NAME_LEN then break end
                    count = count + 1
                    out[#out + 1] = utf8.char(cp)
                end
            end)
            local joined = table.concat(out)
            s = joined ~= "" and joined or s:sub(1, MAX_NAME_LEN)
        elseif len > MAX_NAME_LEN then
            s = s:sub(1, utf8.offset(s, MAX_NAME_LEN + 1) - 1)
        end
        return s
    end

    local function nameTaken(name, exceptId)
        local key = name:lower()
        for _, e in ipairs(ScriptList) do
            if e.id ~= exceptId and e.name:lower() == key then return true end
        end
        return false
    end

    local function makeUniqueName(name, exceptId)
        if not nameTaken(name, exceptId) then return name end
        local n = 2
        while nameTaken(("%s (%d)"):format(name, n), exceptId) do n = n + 1 end
        return ("%s (%d)"):format(name, n)
    end

    local function idTaken(id)
        for _, e in ipairs(ScriptList) do
            if e.id == id then return true end
        end
        return false
    end

    local function createEntry(name, code, base, opts)
        base, opts = base or {}, opts or {}

        name = sanitizeName(name)
        if name == "" then return nil, "empty_name" end
        if type(code) ~= "string" or code:match("^%s*$") then return nil, "empty_script" end
        if #code > MAX_SCRIPT_LEN then return nil, "too_long" end

        local wanted = name
        if not opts.keepName then name = makeUniqueName(name, base.id) end

        local id = base.id
        if type(id) ~= "string" or id == "" or idTaken(id) then
            id = HttpService:GenerateGUID(false)
        end

        local now = os.time()
        return {
            id        = id,
            name      = name,
            script    = code,
            createdAt = tonumber(base.createdAt) or now,
            updatedAt = tonumber(base.updatedAt) or now,
            favorite  = base.favorite == true,
            auto      = (base.auto == true) or nil,                           -- run on startup (all games)
            autoPlace = tonumber(base.autoPlace) or nil,                      -- run on startup (specific game PlaceId)
            review    = (base.review == true or opts.review == true) or nil,  -- imported, not reviewed yet
        }, (name ~= wanted) and "renamed" or nil
    end

    --// ---- Save / load library ----
    local saveLibrary, scheduleSave, readJson, loadLibrary, announceLoad
    do
    local STATUS = {
        saved  = { "Saved",        "SubText" },
        error  = { "Save failed",  "Danger"  },
        memory = { "Session only", "SubText" },
    }

    local function setSaveStatus(state)
        local s = STATUS[state]
        if StatusLabel and s then
            StatusLabel.Text, StatusLabel.TextColor3 = s[1], Theme[s[2]]
        end
    end

    local lastSaved

    function saveLibrary()
        if not canFS then
            setSaveStatus("memory")
            return true, "memory_only"
        end

        local okEnc, json = pcall(HttpService.JSONEncode, HttpService,
            { version = SCHEMA_VERSION, scripts = ScriptList })
        if not okEnc then
            setSaveStatus("error")
            return false, "encode: " .. tostring(json)
        end

        if json == lastSaved then
            setSaveStatus("saved")
            return true
        end

        if lastSaved then pcall(writefile, BACKUP_FILE, lastSaved) end

        local okW, errW = pcall(writefile, SCRIPT_FILE, json)
        if not okW then
            lastSaved = nil
            setSaveStatus("error")
            return false, tostring(errW)
        end

        local okR, back = pcall(readfile, SCRIPT_FILE)
        if not okR or back ~= json then
            lastSaved = nil
            setSaveStatus("error")
            return false, "verify_failed"
        end

        lastSaved = json
        setSaveStatus("saved")
        return true
    end

    local saveQueued = false
    function scheduleSave(delay)
        if saveQueued then return end
        saveQueued = true
        task.delay(delay or 0.4, function()
            saveQueued = false
            local ok, err = saveLibrary()
            if not ok then showToast("Auto-save failed: " .. tostring(err), "error") end
        end)
    end

    function readJson(path)
        local okF, exists = pcall(isfile, path)
        if not okF or not exists then return nil, "missing" end
        local okR, body = pcall(readfile, path)
        if not okR then return nil, "unreadable" end
        local okD, data = pcall(HttpService.JSONDecode, HttpService, body)
        if not okD then return nil, "bad_json", body end
        return data, nil, body
    end

    local function extractItems(data)
        if type(data) ~= "table" then return nil end
        if data.version and type(data.scripts) == "table" then
            return data.scripts, tonumber(data.version) or 1
        end
        return data, 1 -- legacy format: array of { name, script }
    end

    function loadLibrary()
        local report = { status = "ok", loaded = 0, skipped = 0 }
        if not canFS then report.status = "memory_only"; return report end

        local data, why, body = readJson(SCRIPT_FILE)
        if why == "missing" then report.status = "empty"; return report end

        if why then
            if body then
                report.corruptFile = dataPath(("L-scr.corrupt-%d.json"):format(os.time()))
                pcall(writefile, report.corruptFile, body)
            end
            data, why, body = readJson(BACKUP_FILE)
            if why then report.status = "corrupt"; return report end
            report.status = "recovered"
        end

        local items, version = extractItems(data)
        if not items then report.status = "corrupt"; return report end

        if report.status == "ok" then lastSaved = body end

        for _, item in ipairs(items) do
            local entry = type(item) == "table"
                and createEntry(item.name, item.script, item, { keepName = true })
            if entry then
                ScriptList[#ScriptList + 1] = entry
                report.loaded = report.loaded + 1
            else
                report.skipped = report.skipped + 1
            end
        end

        local needSave = report.status == "recovered"
        if version < SCHEMA_VERSION then
            report.migrated = version
            needSave = true
            pcall(function() writefile(dataPath(("L-scr.v%d.bak.json"):format(version)), body) end)
        end
        if needSave then saveLibrary() end
        return report
    end

    function announceLoad(report)
        if report.status == "recovered" then
            showToast("Library was damaged - restored from backup", "warn", { duration = 5 })
        elseif report.status == "corrupt" then
            local kept = report.corruptFile and (" Copy kept: " .. report.corruptFile) or ""
            showToast("Library file is damaged." .. kept, "error", { duration = 6 })
        elseif report.status == "memory_only" then
            setSaveStatus("memory")
        end
        if report.status == "ok" or report.status == "empty" or report.status == "recovered" then
            setSaveStatus("saved")
        end
        if report.skipped > 0 then
            showToast(("%d invalid script(s) were skipped"):format(report.skipped), "warn")
        end
    end

    end
    --// ---- Run info + auto-run switch: its own small file, so a run never rewrites the whole library ----
    local State = { autoRun = true, stats = {} }

    local function loadState()
        if not canFS then return end
        local data = readJson(STATE_FILE)
        if type(data) ~= "table" then return end
        State.autoRun = data.autoRun ~= false
        if type(data.stats) ~= "table" then return end
        for id, s in pairs(data.stats) do
            if type(id) == "string" and type(s) == "table" then
                local ok
                if type(s.ok) == "boolean" then ok = s.ok end
                State.stats[id] = {
                    t  = tonumber(s.t),
                    n  = math.max(0, math.floor(tonumber(s.n) or 0)),
                    ok = ok,
                }
            end
        end
    end

    local stateQueued = false
    local function saveState()
        if not canFS or stateQueued then return end
        stateQueued = true
        task.delay(1, function()
            stateQueued = false
            pcall(function()
                writefile(STATE_FILE, HttpService:JSONEncode({ autoRun = State.autoRun, stats = State.stats }))
            end)
        end)
    end

    local function pruneState()
        local alive, changed = {}, false
        for _, e in ipairs(ScriptList) do alive[e.id] = true end
        for id in pairs(State.stats) do
            if not alive[id] then
                State.stats[id] = nil
                changed = true
            end
        end
        if changed then saveState() end
    end

    local function touchRun(entry)
        if entry.temp then return end
        local s = State.stats[entry.id]
        if not s then
            s = { n = 0 }
            State.stats[entry.id] = s
        end
        s.t, s.n = os.time(), s.n + 1
        saveState()
    end

    local function finishRun(entry, ok)
        if entry.temp then return end
        local s = State.stats[entry.id]
        if s then
            s.ok = ok
            saveState()
        end
    end

    --// ---- compileScript: trial compile, does not run ----
    local compileCache = setmetatable({}, { __mode = "k" })

    local function compileScript(source, chunkName)
        if typeof(loadstring) ~= "function" then
            return false, nil, { kind = "unavailable", message = "loadstring is not available" }
        end
        local safe = ((chunkName or "UserScript"):gsub("[^%w_]", "_"))
        local ok, fn, err = pcall(loadstring, source, "=" .. safe)
        if not ok then
            return false, nil, { kind = "compile", message = tostring(fn) }
        end
        if not fn then
            local text = tostring(err)
            local line, msg = text:match(":(%d+):%s*(.*)$")
            return false, nil, {
                kind = "compile", line = tonumber(line), message = msg or text,
            }
        end
        return true, fn
    end

    local function getCompiled(entry)
        local c = compileCache[entry]
        if c and c.src == entry.script then return true, c.fn end
        local ok, fn, info = compileScript(entry.script, entry.name)
        if ok then compileCache[entry] = { src = entry.script, fn = fn } end
        return ok, fn, info
    end

    local function describe(info)
        return info.line and ("Line %d: %s"):format(info.line, info.message) or info.message
    end

    local pendingSaveAnyway
    local function validateForSave(code)
        local ok, _, info = compileScript(code, "Preview")
        if ok or info.kind == "unavailable" then return true end

        local now = os.clock()
        local p = pendingSaveAnyway
        if p and p.code == code and now < p.expires then
            pendingSaveAnyway = nil
            return true
        end
        pendingSaveAnyway = { code = code, expires = now + 5 }
        return false, describe(info)
    end

    --// ---- runScript / stopScript (supports `return function() ... end` cleanup) ----
    local function logOut(level, name, text)
        if OutputPanel then OutputPanel.append(level, name, text) end
    end

    local function runScript(entry, onState)
        onState = onState or function() end
        if Running[entry.id] then return false, "already_running" end

        local ok, fn, info = getCompiled(entry)
        if not ok then
            local why = describe(info)
            logOut("error", entry.name, "Compile error - " .. why)
            touchRun(entry)
            finishRun(entry, false)
            onState("error", why)
            return false, "compile"
        end

        touchRun(entry)
        local state = { startedAt = os.clock(), onState = onState, entry = entry }
        Running[entry.id] = state
        onState("running")
        task.delay(0.4, function()
            if Running[entry.id] == state then onState("running_long") end
        end)

        state.thread = task.spawn(function()
            local okRun, res = xpcall(fn, function(e)
                return debug.traceback(tostring(e), 2)
            end)
            if Running[entry.id] ~= state then
                if okRun and type(res) == "function" then pcall(res) end
                return
            end
            if okRun and type(res) == "function" then
                -- Script returned a cleanup function: keep state in Running so Stop can invoke it
                state.cleanup = res
                state.thread = nil
                logOut("ok", entry.name,
                    ("Active with cleanup hook (%.2fs)"):format(os.clock() - state.startedAt))
                finishRun(entry, true)
                onState("running_long")
                return
            end
            Running[entry.id] = nil
            if okRun then
                logOut("ok", entry.name,
                    ("Finished in %.2fs"):format(os.clock() - state.startedAt))
                finishRun(entry, true)
                onState("ok")
            else
                logOut("error", entry.name, "Runtime error - " .. tostring(res))
                finishRun(entry, false)
                onState("error", firstLine(res))
            end
        end)
        return true
    end

    local function stopScript(entry)
        local state = Running[entry.id]
        if not state then return false end
        Running[entry.id] = nil
        if state.thread and task.cancel then pcall(task.cancel, state.thread) end
        if type(state.cleanup) == "function" then
            local okC, errC = pcall(state.cleanup)
            if okC then
                logOut("info", entry.name, "Stopped and cleaned up")
            else
                logOut("error", entry.name, "Cleanup error - " .. firstLine(errC))
            end
        else
            logOut("info", entry.name, "Stopped (main thread only)")
        end
        state.onState("idle")
        return true
    end

    local function stopAll()
        local entries = {}
        for _, st in pairs(Running) do entries[#entries + 1] = st.entry end
        for _, e in ipairs(entries) do stopScript(e) end
        return #entries
    end

    ScreenGui.Destroying:Connect(stopAll)

    -- One-off runs of code that is not in the library (test run from the dialog, clipboard)
    local canClipboard = typeof(getclipboard) == "function"
    local canRun = typeof(loadstring) == "function"

    local quickSeq = 0
    local function quickRun(name, code)
        quickSeq = quickSeq + 1
        local entry = { id = "quick-" .. quickSeq, name = name, script = code, temp = true }
        return runScript(entry, function(state, detail)
            if state == "ok" or state == "running_long" then
                showToast("Ran OK", "success", { duration = 1.5 })
            elseif state == "error" then
                showToast(shorten(tostring(detail or "Script failed"), 120), "error")
            end
        end)
    end

    local function readClipboard()
        if not canClipboard then return nil end
        local ok, text = pcall(getclipboard)
        if ok and type(text) == "string" and not text:match("^%s*$") then return text end
        return nil
    end

    local function runClipboard()
        local text = readClipboard()
        if not text then
            showToast("Clipboard is empty", "warn")
        elseif #text > MAX_SCRIPT_LEN then
            showToast("Clipboard text is too large", "error")
        else
            quickRun("Clipboard", text)
        end
    end

    --// ---- Export / import library ----
    local function safeFileName(name)
        local s = (name:gsub("[^%w_%-]+", "_"))
        if s:match("^_*$") then s = "script" end
        return s:sub(1, 30)
    end

    local function exportLibrary(entry)
        local items = entry and { entry } or ScriptList
        if #items == 0 then
            showToast("Nothing to export", "warn")
            return false
        end

        local payload = {
            format = EXPORT_FORMAT, version = 1, exportedAt = os.time(), scripts = {},
        }
        for _, e in ipairs(items) do
            payload.scripts[#payload.scripts + 1] = { name = e.name, script = e.script }
        end
        local okEnc, json = pcall(HttpService.JSONEncode, HttpService, payload)
        if not okEnc then
            showToast("Export failed", "error")
            return false
        end

        local fileName
        if canFS then
            local base = ("L-export-%s-%s"):format(
                entry and safeFileName(entry.name) or "all", os.date("%Y%m%d-%H%M%S"))
            fileName = dataPath(base .. ".json")
            local n = 2
            if typeof(isfile) == "function" then
                while true do
                    local okI, taken = pcall(isfile, fileName)
                    if not okI or not taken then break end
                    fileName = dataPath(("%s-%d.json"):format(base, n))
                    n = n + 1
                end
            end
            if not pcall(writefile, fileName, json) then fileName = nil end
        end
        local copied = UI.CopyText(json)

        if fileName then
            local tail = copied and " (copied)" or ""
            showToast("Exported to " .. fileName .. tail, "success", { duration = 4 })
        elseif copied then
            showToast("Export copied to clipboard", "success")
        else
            showToast("Export needs file access or clipboard", "error")
            return false
        end
        return true, fileName
    end

    local function importLibrary(text)
        text = tostring(text or ""):match("^%s*(.-)%s*$")
        if text == "" then return nil, "Nothing to import" end

        if canFS and #text < 200 and not text:find("[{%[\r\n]") then
            for _, path in ipairs({ dataPath(text), text }) do
                local okF, exists = pcall(isfile, path)
                if okF and exists then
                    local okR, body = pcall(readfile, path)
                    if okR then
                        text = body
                        break
                    end
                end
            end
        end
        if #text > MAX_IMPORT_BYTES then return nil, "Input is too large" end

        local okDec, data = pcall(HttpService.JSONDecode, HttpService, text)
        if not okDec or type(data) ~= "table"
            or data.format ~= EXPORT_FORMAT or type(data.scripts) ~= "table" then
            return nil, "Not a valid exported script file"
        end

        local added, skipped = {}, 0
        for _, item in ipairs(data.scripts) do
            local entry = #added < MAX_IMPORT_ITEMS and type(item) == "table"
                and createEntry(item.name, item.script, nil, { review = true })
            if entry then
                ScriptList[#ScriptList + 1] = entry
                added[#added + 1] = entry
            else
                skipped = skipped + 1
            end
        end
        if #added == 0 then return nil, "No valid scripts found" end

        local ok, err = saveLibrary()
        if not ok then
            for _ = 1, #added do table.remove(ScriptList) end
            return nil, "Save failed: " .. tostring(err)
        end
        for _, entry in ipairs(added) do CreateScriptRow(entry) end
        applyListView()
        return { added = #added, skipped = skipped }
    end

    --// ---- Output panel: run / error history, collapsible ----
    local function createOutputPanel(onResize)
        local HEADER_H, BODY_H, MAX_LINES = 28, 110, 50
        local LEVEL_COLORS = themedColors({ ok = "Sakura", error = "Danger", info = "SubText" })
        local expanded, unread, seq = false, 0, 0
        local plain, labels = {}, {}

        local Panel = new("Frame", {
            Name = "OutputPanel",
            LayoutOrder = 4,
            Size = UDim2.new(1, 0, 0, HEADER_H),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            ClipsDescendants = true,
        }, ScriptTab)
        corner(Panel, 8)
        stroke(Panel)

        local Header = new("TextButton", {
            Size = UDim2.new(1, -110, 0, HEADER_H),
            BackgroundTransparency = 1,
            AutoButtonColor = false,
            Text = "Output",
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, Panel)
        padding(Header, 10, 0)

        local function miniButton(text, rightOffset)
            return new("TextButton", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -rightOffset, 0, 2),
                Size = UDim2.fromOffset(48, HEADER_H - 4),
                BackgroundTransparency = 1,
                Text = text,
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextColor3 = Theme.AccentPink,
            }, Panel)
        end
        local CopyBtn, ClearBtn = miniButton("Copy", 56), miniButton("Clear", 6)

        local Body = new("ScrollingFrame", {
            Position = UDim2.fromOffset(0, HEADER_H),
            Size = UDim2.new(1, 0, 1, -HEADER_H),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.AccentPink,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, Panel)
        new("UIListLayout", {
            Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder,
        }, Body)
        padding(Body, 8, 8, 4, 4)

        local function refreshHeader()
            local bad = unread > 0 and not expanded
            Header.Text = bad and ("Output  -  %d new error(s)"):format(unread) or "Output"
            Header.TextColor3 = bad and Theme.Danger or Theme.SubText
        end

        local function append(level, name, text)
            seq = seq + 1
            local line = ("[%s] %s: %s"):format(os.date("%H:%M:%S"), name, text)
            plain[#plain + 1] = line
            labels[#labels + 1] = new("TextLabel", {
                LayoutOrder = seq,
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Text = line,
                TextWrapped = true,
                TextSelectable = true,
                Font = Enum.Font.Code,
                TextSize = 12,
                TextColor3 = LEVEL_COLORS[level] or Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
            }, Body)
            if #labels > MAX_LINES then
                table.remove(plain, 1)
                table.remove(labels, 1):Destroy()
            end
            if level == "error" and not expanded then unread = unread + 1 end
            refreshHeader()
            task.defer(function()
                Body.CanvasPosition = Vector2.new(0, Body.AbsoluteCanvasSize.Y)
            end)
        end

        local function clear()
            for _, l in ipairs(labels) do l:Destroy() end
            table.clear(labels)
            table.clear(plain)
            unread = 0
            refreshHeader()
        end

        local function toggle()
            expanded = not expanded
            if expanded then unread = 0 end
            refreshHeader()
            tween(Panel, 0.15, {
                Size = UDim2.new(1, 0, 0, expanded and (HEADER_H + BODY_H) or HEADER_H),
            }, EASE_QUAD, DIR_OUT)
        end

        local function copyAll()
            if #plain == 0 then return end
            if UI.CopyText(table.concat(plain, "\n")) then
                showToast("Output copied", "success", { duration = 1.5 })
            else
                showToast("Clipboard is not available", "warn")
            end
        end

        Header.MouseButton1Click:Connect(toggle)
        CopyBtn.MouseButton1Click:Connect(copyAll)
        ClearBtn.MouseButton1Click:Connect(clear)
        if onResize then Panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(onResize) end

        return {
            Frame = Panel, append = append, clear = clear,
            toggle = toggle, copyAll = copyAll,
        }
    end

    -- A name for pasted code: its first comment line, else the file name of the first link in it
    local function guessName(code)
        local c = code:match("^%s*%-%-+[%s/#!]*([^\r\n]+)")
        if c and not c:match("^%[=*%[") then
            c = sanitizeName(c):sub(1, 40)
            if #c >= 3 then return c end
        end
        local url = code:match("https?://[^%s\"'%)]+")
        if url then
            local file = url:gsub("[?#].*$", ""):match("([^/]+)/*$")
            if file then
                file = sanitizeName((file:gsub("%.%w+$", ""):gsub("%%20", " ")))
                if #file >= 3 then return file end
            end
        end
        return nil
    end

    --// ---- Lua Syntax Highlighter (single-pass RichText lexer) ----
    local highlightLua
    do
    local KEYWORDS = {
        ["and"] = true, ["break"] = true, ["continue"] = true, ["do"] = true, ["else"] = true,
        ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true,
        ["if"] = true, ["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true,
        ["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
        ["until"] = true, ["while"] = true,
    }
    local BUILTINS = {
        ["game"] = true, ["workspace"] = true, ["script"] = true, ["task"] = true, ["math"] = true,
        ["string"] = true, ["table"] = true, ["pcall"] = true, ["xpcall"] = true, ["pairs"] = true,
        ["ipairs"] = true, ["tonumber"] = true, ["tostring"] = true, ["print"] = true, ["warn"] = true,
        ["error"] = true, ["Instance"] = true, ["Vector2"] = true, ["Vector3"] = true, ["CFrame"] = true,
        ["Color3"] = true, ["UDim2"] = true, ["Enum"] = true, ["loadstring"] = true, ["typeof"] = true,
    }

    local function escapeRich(s)
        return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
    end

    function highlightLua(src)
        local kwHex  = Theme.AccentPink:ToHex()
        local biHex  = Theme.AccentPurple:ToHex()
        local strHex = Theme.Sakura:ToHex()
        local cmtHex = Theme.SubText:ToHex()
        local out, n, i = {}, #src, 1

        local function span(hexCol, text)
            out[#out + 1] = '<font color="#' .. hexCol .. '">' .. escapeRich(text) .. '</font>'
        end

        while i <= n do
            local c = src:sub(i, i)
            if c == "-" and src:sub(i + 1, i + 1) == "-" then
                local eq = src:match("^%-%-%[(=*)%[", i)
                local close = eq and select(2, src:find("%]" .. eq .. "%]", i + 4 + #eq, true))
                local stop = close or ((src:find("\n", i + 2, true) or (n + 1)) - 1)
                span(cmtHex, src:sub(i, stop))
                i = stop + 1
            elseif c == "[" and src:match("^%[(=*)%[", i) then
                local eq = src:match("^%[(=*)%[", i)
                local _, close = src:find("%]" .. eq .. "%]", i + 2 + #eq, true)
                local stop = close or n
                span(strHex, src:sub(i, stop))
                i = stop + 1
            elseif c == '"' or c == "'" then
                local j = i + 1
                while j <= n do
                    local cj = src:sub(j, j)
                    if cj == "\\" then
                        j = j + 2
                    elseif cj == c or cj == "\n" then
                        if cj == c then j = j + 1 end
                        break
                    else
                        j = j + 1
                    end
                end
                span(strHex, src:sub(i, j - 1))
                i = j
            elseif c:match("[%a_]") then
                local s, e = src:find("^[%w_]+", i)
                local w = src:sub(s, e)
                if KEYWORDS[w] then
                    span(kwHex, w)
                elseif BUILTINS[w] then
                    span(biHex, w)
                else
                    out[#out + 1] = w
                end
                i = e + 1
            elseif c:match("%d") then
                local s, e = src:find("^0x[%da-fA-F]+", i)
                if not s then s, e = src:find("^%d+%.?%d*", i) end
                span(strHex, src:sub(s, e))
                i = e + 1
            else
                out[#out + 1] = escapeRich(c)
                i = i + 1
            end
        end
        return table.concat(out)
    end
    end

    --// ---- NotBoxA: Add / Edit / Import ----
    local function createScriptDialog()
        local ACCENT = Theme.AccentPink
        local GUTTER_W = 28
        local HIGHLIGHT_MAX = 15000
        local TEXT = {
            addTitle = "ADD SCRIPT", editTitle = "EDIT SCRIPT", importTitle = "IMPORT SCRIPTS",
            save = "Save", saveChanges = "Save Changes", import = "Import",
            cancel = "Cancel", discard = "Discard?",
            namePlaceholder = "Enter your name script here",
            codePlaceholder = "Enter your script here",
            importPlaceholder = "Paste exported JSON or a file name",
        }

        local Box = new("Frame", {
            Name = "NotBoxA",
            Visible = false,
            AnchorPoint = ANCHOR_CENTER,
            Position = CENTER,
            Size = UDim2.new(),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ClipsDescendants = true,
            ZIndex = 51,
        }, ScreenGui)
        corner(Box, 12)

        local Bg = new("Frame", {
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = WHITE,
            BorderSizePixel = 0,
            ZIndex = 51,
        }, Box)
        corner(Bg, 12)
        new("UIGradient", { Color = ColorSequence.new(Theme.PanelAlt, Theme.Panel), Rotation = 90 }, Bg)

        new("UIGradient", {
            Color = ColorSequence.new(Theme.AccentPurple, ACCENT),
            Rotation = 45,
        }, stroke(Box, WHITE, 1.5))

        new("UIGradient", {
            Color = ColorSequence.new(Theme.AccentPurple, ACCENT),
        }, new("Frame", {
            Size = UDim2.new(1, 0, 0, 3),
            BackgroundColor3 = WHITE,
            BorderSizePixel = 0,
            ZIndex = 52,
        }, Box))

        local TitleLabel = label(Box, {
            Name = "DialogTitle",
            Size = UDim2.new(1, -32, 0, 20),
            Position = UDim2.fromOffset(16, 14),
            Text = TEXT.addTitle,
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Sakura,
            ZIndex = 52,
        })

        local function fieldLabel(name, text, y)
            return label(Box, {
                Name = name,
                Size = UDim2.new(1, -32, 0, 16),
                Position = UDim2.fromOffset(16, y),
                Text = text,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = Theme.SubText,
                ZIndex = 52,
            })
        end

        -- TextBoxA1: Script Name
        local NameLabel = fieldLabel("NameLabel", "Script Name", 42)
        local NameBox = new("TextBox", {
            Position = UDim2.fromOffset(16, 62),
            Size = UDim2.new(1, -32, 0, 32),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = TEXT.namePlaceholder,
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            ClipsDescendants = true,
            ZIndex = 52,
        }, Box)
        corner(NameBox, 6)
        padding(NameBox, 8, 8)
        local NameStroke = stroke(NameBox)
        bindBoxFocus(NameBox, NameStroke)

        -- TextBoxA2: Script (two-way scrolling frame with line numbers and live syntax highlighting)
        fieldLabel("CodeLabel", "Script", 102)

        local function miniAction(text, rightOffset)
            local B = new("TextButton", {
                Name = text .. "Btn",
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, -rightOffset, 0, 100),
                Size = UDim2.fromOffset(60, 20),
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Text = text,
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                TextColor3 = Theme.AccentPink,
                ZIndex = 53,
            }, Box)
            B.MouseEnter:Connect(function() tween(B, 0.12, { TextColor3 = Theme.Sakura }) end)
            B.MouseLeave:Connect(function() tween(B, 0.12, { TextColor3 = Theme.AccentPink }) end)
            return B
        end
        local PasteBtn = miniAction("Paste", 12)
        local RunBtn   = miniAction("Run", 72)
        local CodeHolder = new("ScrollingFrame", {
            Position = UDim2.fromOffset(16, 122),
            Size = UDim2.new(1, -32, 1, -194),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.AccentPink,
            ScrollingDirection = Enum.ScrollingDirection.XY,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.XY,
            ZIndex = 52,
        }, Box)
        corner(CodeHolder, 6)
        local CodeStroke = stroke(CodeHolder)

        local LineNums = new("TextLabel", {
            Name = "LineNums",
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromOffset(GUTTER_W, 96),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            Text = "1",
            Font = Enum.Font.Code,
            TextSize = 13,
            TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 53,
        }, CodeHolder)
        padding(LineNums, 2, 6, 6, 6)

        local CodeBox = new("TextBox", {
            Position = UDim2.fromOffset(GUTTER_W, 0),
            Size = UDim2.fromOffset(212, 96),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = TEXT.codePlaceholder,
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            MultiLine = true,
            TextWrapped = false,
            Font = Enum.Font.Code,
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextTransparency = 0.999,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 53,
        }, CodeHolder)
        padding(CodeBox, 6, 8, 6, 6)
        bindBoxFocus(CodeBox, CodeStroke)

        local HighlightLabel = new("TextLabel", {
            Name = "SyntaxLayer",
            Position = UDim2.fromOffset(GUTTER_W, 0),
            Size = UDim2.fromOffset(212, 96),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            RichText = true,
            Text = "",
            TextWrapped = false,
            Font = Enum.Font.Code,
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 54,
        }, CodeHolder)
        padding(HighlightLabel, 6, 8, 6, 6)

        local TextService = game:GetService("TextService")
        local HUGE = Vector2.new(1e6, 1e6)
        local lineH
        local caretQueued = false
        local mode = "add"

        local function refreshEditorView()
            local src = CodeBox.Text
            local _, breaks = src:gsub("\n", "")
            local lines = {}
            for i = 1, breaks + 1 do lines[i] = tostring(i) end
            LineNums.Text = table.concat(lines, "\n")

            if mode ~= "import" and src ~= "" and #src <= HIGHLIGHT_MAX then
                CodeBox.TextTransparency = 0.999
                HighlightLabel.Visible = true
                HighlightLabel.Text = highlightLua(src)
            else
                CodeBox.TextTransparency = 0
                HighlightLabel.Visible = false
                HighlightLabel.Text = ""
            end
        end
        CodeBox:GetPropertyChangedSignal("Text"):Connect(refreshEditorView)
        ScreenGui:GetAttributeChangedSignal("Theme"):Connect(refreshEditorView)

        local function moveCaretIntoView()
            caretQueued = false
            pcall(function()
                local cur = CodeBox.CursorPosition
                if cur < 1 then return end
                lineH = lineH or TextService:GetTextSize("A", CodeBox.TextSize, CodeBox.Font, HUGE).Y
                local before = CodeBox.Text:sub(1, cur - 1)
                local lastLine = before:match("([^\n]*)$")
                local _, breaks = before:gsub("\n", "")
                local w = TextService:GetTextSize(lastLine, CodeBox.TextSize, CodeBox.Font, HUGE).X
                local cx, cy = GUTTER_W + 6 + w, 6 + breaks * lineH
                local win, pos = CodeHolder.AbsoluteWindowSize, CodeHolder.CanvasPosition
                local nx, ny = pos.X, pos.Y
                if cx > pos.X + win.X - 16 then
                    nx = cx - win.X + 32
                elseif cx < pos.X then
                    nx = math.max(0, cx - 32)
                end
                if cy + lineH > pos.Y + win.Y - 6 then
                    ny = cy + lineH - win.Y + 12
                elseif cy < pos.Y then
                    ny = math.max(0, cy - 6)
                end
                if nx ~= pos.X or ny ~= pos.Y then
                    CodeHolder.CanvasPosition = Vector2.new(nx, ny)
                end
            end)
        end

        local function followCaret()
            if caretQueued then return end
            caretQueued = true
            task.defer(moveCaretIntoView)
        end
        CodeBox:GetPropertyChangedSignal("CursorPosition"):Connect(followCaret)

        new("Frame", {
            Size = UDim2.new(1, -32, 0, 1),
            Position = UDim2.new(0, 16, 1, -60),
            BackgroundColor3 = Theme.Border,
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            ZIndex = 52,
        }, Box)

        local function option(text, pos, bgToken, textToken, outlined)
            local Btn = new("TextButton", {
                Size = UDim2.new(0.5, -22, 0, 34),
                Position = pos,
                BackgroundColor3 = Theme[bgToken],
                Text = text,
                Font = Enum.Font.GothamBold,
                TextSize = 14,
                TextColor3 = Theme[textToken],
                AutoButtonColor = false,
                ZIndex = 52,
            }, Box)
            corner(Btn, 8)
            local S = outlined and stroke(Btn, Theme.Border, 1) or nil
            pressScale(Btn, 0.95)

            Btn.MouseEnter:Connect(function()
                if outlined then
                    tween(Btn, 0.15, { BackgroundColor3 = Theme.Header, TextColor3 = Theme.Sakura })
                    tween(S, 0.15, { Color = Theme.AccentPurple })
                else
                    tween(Btn, 0.15, { BackgroundColor3 = Theme[bgToken]:Lerp(WHITE, 0.15) })
                end
            end)
            Btn.MouseLeave:Connect(function()
                if outlined then
                    tween(Btn, 0.15, { BackgroundColor3 = Theme[bgToken], TextColor3 = Theme[textToken] })
                    tween(S, 0.15, { Color = Theme.Border })
                else
                    tween(Btn, 0.15, { BackgroundColor3 = Theme[bgToken] })
                end
            end)
            return Btn
        end

        local Save   = option(TEXT.save, UDim2.new(0, 16, 1, -46), "AccentPink", "Background")
        local Cancel = option(TEXT.cancel, UDim2.new(1, -16, 1, -46), "PanelAlt", "Text", true)
        Cancel.AnchorPoint = Vector2.new(1, 0)

        --// Dialog state
        local current = nil
        local baseline = { name = "", code = "" }
        local hideToken, discardUntil, pasteUntil = 0, 0, 0

        local function fitSize()
            local vp = ScreenGui.AbsoluteSize
            return UDim2.fromOffset(math.min(330, vp.X - 24), math.min(290, vp.Y - 24))
        end

        local function isDirty()
            return NameBox.Text ~= baseline.name or CodeBox.Text ~= baseline.code
        end

        local function show(newMode, entry)
            mode, current = newMode or "add", entry
            baseline = { name = entry and entry.name or "", code = entry and entry.script or "" }
            NameBox.Text, CodeBox.Text = baseline.name, baseline.code
            CodeHolder.CanvasPosition = Vector2.new(0, 0)

            local isImport = mode == "import"
            NameBox.Visible = not isImport
            if NameLabel then NameLabel.Visible = not isImport end
            PasteBtn.Visible = canClipboard
            RunBtn.Visible = canRun and not isImport
            PasteBtn.Text, pasteUntil = "Paste", 0
            CodeBox.PlaceholderText = isImport and TEXT.importPlaceholder or TEXT.codePlaceholder
            if TitleLabel then
                TitleLabel.Text = (mode == "edit" and TEXT.editTitle)
                    or (isImport and TEXT.importTitle) or TEXT.addTitle
            end
            Save.Text = (mode == "edit" and TEXT.saveChanges)
                or (isImport and TEXT.import) or TEXT.save
            Cancel.Text, discardUntil = TEXT.cancel, 0

            local target = fitSize()
            local codeW = math.max(120, target.X.Offset - 34 - GUTTER_W)
            CodeBox.Size = UDim2.fromOffset(codeW, 96)
            HighlightLabel.Size = UDim2.fromOffset(codeW, 96)
            refreshEditorView()

            hideToken = hideToken + 1
            setOverlay(true)
            Box.Visible = true
            Box.Size = UDim2.new()
            tween(Box, BUBBLE_IN_TIME, { Size = target }, EASE_QUAD, DIR_OUT)
        end

        local function hide()
            hideToken = hideToken + 1
            local token = hideToken
            NameBox:ReleaseFocus()
            CodeBox:ReleaseFocus()
            local sizeTween = tween(Box, BUBBLE_OUT_TIME, { Size = UDim2.new() }, EASE_QUAD, DIR_IN)
            sizeTween.Completed:Connect(function(state)
                if state ~= Enum.PlaybackState.Completed or token ~= hideToken then return end
                Box.Visible = false
                current = nil
                setOverlay(false)
            end)
        end

        Cancel.MouseButton1Click:Connect(function()
            if not isDirty() or os.clock() < discardUntil then
                hide()
                return
            end
            discardUntil = os.clock() + 3
            Cancel.Text = TEXT.discard
            task.delay(3, function()
                if os.clock() >= discardUntil then Cancel.Text = TEXT.cancel end
            end)
        end)

        NameBox.FocusLost:Connect(function(enterPressed)
            if enterPressed then CodeBox:CaptureFocus() end
        end)

        local function flashMini(btn, text, base)
            btn.Text = text
            task.delay(1.2, function()
                if btn.Text == text then btn.Text = base end
            end)
        end

        PasteBtn.MouseButton1Click:Connect(function()
            local clip = readClipboard()
            if not clip then
                flashMini(PasteBtn, "Empty", "Paste")
                return
            end
            if #clip > MAX_SCRIPT_LEN then
                showToast("Clipboard text is too large", "error")
                return
            end
            if CodeBox.Text ~= "" and os.clock() >= pasteUntil then
                pasteUntil = os.clock() + 3
                PasteBtn.Text = "Replace?"
                task.delay(3, function()
                    if os.clock() >= pasteUntil then PasteBtn.Text = "Paste" end
                end)
                return
            end
            pasteUntil = 0
            CodeBox.Text = clip
            CodeHolder.CanvasPosition = Vector2.new(0, 0)
            if mode ~= "import" and NameBox.Text == "" then
                local guess = guessName(clip)
                if guess then NameBox.Text = guess end
            end
            flashMini(PasteBtn, "Pasted", "Paste")
        end)

        return {
            Box = Box, show = show, hide = hide, isDirty = isDirty,
            getMode = function() return mode end,
            getEntry = function() return current end,
            Save = Save, Cancel = Cancel, PasteBtn = PasteBtn, RunBtn = RunBtn,
            NameBox = NameBox, NameStroke = NameStroke,
            CodeBox = CodeBox, CodeStroke = CodeStroke,
        }
    end

    ScriptDialog = createScriptDialog()

    --// ---- Entry actions: Add / Edit / Import / Delete / Duplicate / Pin / Auto-run ----
    local function openEditDialog(entry)
        if isLocked() then return end
        ScriptDialog.show("edit", entry)
    end

    local function commitEdit(entry, rawName, code)
        local name = makeUniqueName(rawName, entry.id)
        if name == entry.name and code == entry.script then
            ScriptDialog.hide()
            return
        end
        local before = { entry.name, entry.script, entry.updatedAt, entry.review }
        entry.name, entry.script, entry.updatedAt = name, code, os.time()
        entry.review = nil

        local ok, err = saveLibrary()
        if not ok then
            entry.name, entry.script, entry.updatedAt, entry.review = before[1], before[2], before[3], before[4]
            showToast("Save failed: " .. tostring(err), "error")
            return
        end

        Rows[entry.id].refresh()
        applyListView()
        ScriptDialog.hide()
        local msg = name ~= rawName and ('Saved as "%s"'):format(name) or "Saved changes"
        showToast(msg, "success")
    end

    local function commitAdd(name, code)
        local entry, flag = createEntry(name, code)
        if not entry then
            showToast(flag == "too_long" and "Script is too large" or "Invalid script", "error")
            return
        end
        ScriptList[#ScriptList + 1] = entry
        local ok, err = saveLibrary()
        if not ok then
            table.remove(ScriptList)
            showToast("Save failed: " .. tostring(err), "error")
            return
        end
        CreateScriptRow(entry)
        applyListView()
        ScriptDialog.hide()
        local msg = flag == "renamed" and ('Saved as "%s"'):format(entry.name) or "Script saved"
        showToast(msg, "success")
    end

    local EXAMPLE_NAME = "Example: Hello"
    local EXAMPLE_CODE = '-- Shows a notification in the game\n'
        .. 'game:GetService("StarterGui"):SetCore("SendNotification", {\n'
        .. '    Title = "Elysera",\n'
        .. '    Text = "Hello from your first script!",\n'
        .. '    Duration = 4,\n'
        .. '})\n'

    local function addExample()
        local entry = createEntry(EXAMPLE_NAME, EXAMPLE_CODE)
        if not entry then return end
        ScriptList[#ScriptList + 1] = entry
        local ok, err = saveLibrary()
        if not ok then
            table.remove(ScriptList)
            showToast("Save failed: " .. tostring(err), "error")
            return
        end
        CreateScriptRow(entry)
        applyListView()
        showToast("Example added - tap play to try it", "success", { duration = 3 })
    end

    local function commitImport(text)
        local result, err = importLibrary(text)
        if not result then
            flashStrokeError(ScriptDialog.CodeStroke)
            showToast(err, "error")
            return
        end
        ScriptDialog.hide()
        local extra = result.skipped > 0 and (", skipped " .. result.skipped) or ""
        showToast(("Imported %d script(s)%s. Review before running."):format(result.added, extra),
            "success", { duration = 4 })
    end

    local pendingConfirm

    DeleteDialog.Yes.MouseButton1Click:Connect(function()
        local pending = pendingConfirm
        pendingConfirm = nil
        DeleteDialog.hide()
        if pending and DeleteDialog.Message.Text == pending.message then pending.run() end
    end)

    local function askConfirm(message, onYes)
        pendingConfirm = { run = onYes, message = message }
        DeleteDialog.Message.Text = message
        DeleteDialog.show()
    end

    local function deleteScript(entry)
        local idx = table.find(ScriptList, entry)
        if not idx then return false end

        table.remove(ScriptList, idx)
        local ok, err = saveLibrary()
        if not ok then
            table.insert(ScriptList, idx, entry)
            showToast("Could not delete: " .. tostring(err), "error")
            return false
        end

        local rec = Rows[entry.id]
        if rec then rec.Row.Visible = false end
        applyListView()

        local undone = false
        local function finalize()
            if undone then return end
            if rec and rec.Row.Parent then rec.Row:Destroy() end
            Rows[entry.id] = nil
            if State.stats[entry.id] then
                State.stats[entry.id] = nil
                saveState()
            end
        end
        if UNDO_SECONDS <= 0 then finalize(); return true end

        showToast(('Deleted "%s"'):format(shorten(entry.name, 24)), "info", {
            duration = UNDO_SECONDS,
            actionText = "Undo",
            onAction = function()
                table.insert(ScriptList, math.min(idx, #ScriptList + 1), entry)
                local okU, errU = saveLibrary()
                if not okU then
                    undone = true
                    if rec then rec.Row.Visible = true end
                    applyListView()
                    showToast("Restored in memory (save failed, will retry): " .. tostring(errU), "error")
                    scheduleSave()
                    return
                end
                undone = true
                if rec then rec.Row.Visible = true end
                applyListView()
            end,
        })
        task.delay(UNDO_SECONDS + 0.3, finalize)
        return true
    end

    local function duplicateScript(entry)
        local idx = table.find(ScriptList, entry)
        if not idx then return nil end

        local copy = createEntry(entry.name .. " (copy)", entry.script)
        if not copy then
            showToast("Could not duplicate this script", "error")
            return nil
        end

        table.insert(ScriptList, idx + 1, copy)
        local ok, err = saveLibrary()
        if not ok then
            table.remove(ScriptList, idx + 1)
            showToast("Save failed: " .. tostring(err), "error")
            return nil
        end

        CreateScriptRow(copy)
        applyListView()
        showToast(('Duplicated as "%s"'):format(shorten(copy.name, 24)), "success", {
            duration = 4,
            actionText = "Rename",
            onAction = function() openEditDialog(copy) end,
        })
        return copy
    end

    local function toggleFavorite(entry)
        entry.favorite = not entry.favorite
        local rec = Rows[entry.id]
        if rec then rec.refresh() end
        applyListView()
        scheduleSave()
        showToast(entry.favorite and "Pinned to top" or "Unpinned", "info", { duration = 1.5 })
        return entry.favorite
    end

    local function toggleAuto(entry, perGame)
        if perGame then
            if entry.autoPlace == game.PlaceId then
                entry.autoPlace = nil
            else
                entry.autoPlace = game.PlaceId
                entry.auto = nil
            end
        else
            if entry.auto then
                entry.auto = nil
            else
                entry.auto = true
                entry.autoPlace = nil
            end
        end
        local rec = Rows[entry.id]
        if rec then rec.refresh() end
        scheduleSave()
        if entry.autoPlace == game.PlaceId then
            showToast(entry.review and "Auto-runs in this game once reviewed" or "Auto-runs in this game", "info", { duration = 2 })
        elseif entry.auto then
            showToast(entry.review and "Runs on startup once you have reviewed it" or "Runs on startup (all games)",
                "info", { duration = 2 })
        else
            showToast("Auto-run off", "info", { duration = 1.5 })
        end
    end

    local function toggleGlobalAuto()
        State.autoRun = not State.autoRun
        saveState()
        showToast(State.autoRun and "Auto-run is on" or "Auto-run is paused", "info", { duration = 1.8 })
    end

    --// ---- Shared floating menu (row + header) ----
    local MenuCatcher

    local function closeContextMenu()
        if MenuCatcher then
            MenuCatcher:Destroy()
            MenuCatcher = nil
        end
    end

    local function openContextMenu(anchor, items)
        closeContextMenu()
        local ITEM_H, MENU_W, PAD = 34, 174, 4
        local origin, screen = ScreenGui.AbsolutePosition, ScreenGui.AbsoluteSize
        local h = #items * ITEM_H + PAD * 2

        MenuCatcher = new("TextButton", {
            Name = "MenuCatcher",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
            ZIndex = 60,
        }, ScreenGui)
        MenuCatcher.MouseButton1Click:Connect(closeContextMenu)

        local ax = anchor.AbsolutePosition.X - origin.X + anchor.AbsoluteSize.X
        local ay = anchor.AbsolutePosition.Y - origin.Y
        local x = math.max(8, math.min(ax - MENU_W, screen.X - MENU_W - 8))
        local y = ay + anchor.AbsoluteSize.Y + 4
        if y + h > screen.Y - 8 then y = ay - h - 4 end
        y = math.max(8, y)

        local Menu = new("Frame", {
            Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(MENU_W, h),
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            ZIndex = 61,
        }, MenuCatcher)
        corner(Menu, 8)
        stroke(Menu, Theme.Border, 1)
        padding(Menu, PAD, PAD, PAD, PAD)
        local MenuScale = new("UIScale", { Scale = 0.92 }, Menu)
        new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, Menu)

        for i, item in ipairs(items) do
            local Btn = new("TextButton", {
                LayoutOrder = i,
                Size = UDim2.new(1, 0, 0, ITEM_H),
                BackgroundColor3 = Theme.Border,
                BackgroundTransparency = 1,
                AutoButtonColor = false,
                Text = item.text,
                Font = Enum.Font.Gotham,
                TextSize = 13,
                TextColor3 = item.color or Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 62,
            }, Menu)
            corner(Btn, 6)
            padding(Btn, 10, 10)
            Btn.MouseEnter:Connect(function() tween(Btn, 0.1, { BackgroundTransparency = 0.7 }) end)
            Btn.MouseLeave:Connect(function() tween(Btn, 0.1, { BackgroundTransparency = 1 }) end)
            Btn.MouseButton1Click:Connect(function()
                closeContextMenu()
                if not isLocked() then item.run() end
            end)
        end
        tween(MenuScale, 0.12, { Scale = 1 }, EASE_QUAD, DIR_OUT)
    end

    local function buildRowItems(entry)
        return {
            { text = "Edit",      run = function() openEditDialog(entry) end },
            { text = "Duplicate", run = function() duplicateScript(entry) end },
            { text = entry.favorite and "Unpin from top" or "Pin to top",
              run = function() toggleFavorite(entry) end },
            { text = (entry.autoPlace == game.PlaceId) and "Disable game auto-run" or "Auto-run (this game)",
              run = function() toggleAuto(entry, true) end },
            { text = entry.auto and "Disable all-game auto" or "Auto-run (all games)",
              run = function() toggleAuto(entry, false) end },
            { text = "Export",    run = function() exportLibrary(entry) end },
            { text = "Delete", color = Theme.Danger, run = function()
                askConfirm(('Do you want to delete "%s"?'):format(shorten(entry.name, 30)),
                    function() deleteScript(entry) end)
            end },
        }
    end

    local function buildLibraryItems()
        local items = {}
        if canClipboard and canRun then
            items[#items + 1] = { text = "Run clipboard", run = runClipboard }
        end
        items[#items + 1] = { text = "Export all", run = function() exportLibrary() end }
        items[#items + 1] = { text = "Import",     run = function() ScriptDialog.show("import") end }
        items[#items + 1] = { text = State.autoRun and "Auto-run: On" or "Auto-run: Off", run = toggleGlobalAuto }
        if next(Running) then
            items[#items + 1] = { text = "Stop all", color = Theme.Danger, run = stopAll }
        end
        return items
    end

    do
        -- Function panel 1: pinned at the top, no frame / no border
        local Pinned = new("Frame", {
            Name = "FunctionPanel1",
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, PINNED_HEIGHT),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        }, ScriptTab)
        padding(Pinned, 4, 0)

        label(Pinned, {
            Size = UDim2.new(1, -190, 1, 0),
            Text = "Other Script",
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextColor3 = Theme.Text,
        })
        StatusLabel = label(Pinned, {
            Name = "SaveStatus",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -114, 0.5, 0),
            Size = UDim2.fromOffset(72, 16),
            Text = "",
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Right,
            TextColor3 = Theme.SubText,
        })
        local LibMoreBtn = CreateIconButton(Pinned, "more", 78, Theme.SubText)
        local AddBtn = createAccentButton(Pinned, "+ Add", 70, 28, {
            name = "AddButton", anchor = Vector2.new(1, 0.5), position = UDim2.new(1, 0, 0.5, 0),
        })

        local SORT_MODES  = { "added", "name", "edited", "recent" }
        local SORT_LABELS = {
            added = "Sort: Added", name = "Sort: A-Z", edited = "Sort: Edited", recent = "Sort: Recent",
        }

        SearchRow = new("Frame", {
            Name = "SearchRow",
            LayoutOrder = 2,
            Visible = false,
            Size = UDim2.new(1, 0, 0, SEARCH_H),
            BackgroundTransparency = 1,
        }, ScriptTab)

        SearchBox = new("TextBox", {
            Size = UDim2.new(1, -94, 1, 0),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "Search name or code",
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            ClipsDescendants = true,
            Font = Enum.Font.Gotham,
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, SearchRow)
        corner(SearchBox, 6)
        padding(SearchBox, 8, 28)
        bindBoxFocus(SearchBox, stroke(SearchBox))

        local ClearBtn = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -100, 0.5, 0),
            Size = UDim2.fromOffset(24, 24),
            BackgroundTransparency = 1,
            Text = "x",
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            TextColor3 = Theme.SubText,
            Visible = false,
            ZIndex = 2,
        }, SearchRow)
        ClearBtn.MouseButton1Click:Connect(function() SearchBox.Text = "" end)

        local SortBtn = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            Size = UDim2.fromOffset(88, SEARCH_H),
            BackgroundTransparency = 1,
            Text = SORT_LABELS.added,
            Font = Enum.Font.Gotham,
            TextSize = 12,
            TextColor3 = Theme.AccentPink,
        }, SearchRow)

        local ListPanel = new("ScrollingFrame", {
            Name = "FunctionPanel2",
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, 100),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.AccentPink,
            ScrollingDirection = Enum.ScrollingDirection.Y,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, ScriptTab)
        list(ListPanel, 10)
        padding(ListPanel, 2, 8, 2, 2)

        EmptyLabel = new("TextLabel", {
            Name = "EmptyHint",
            LayoutOrder = -1,
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundTransparency = 1,
            Text = "",
            TextWrapped = true,
            Font = Enum.Font.Gotham,
            TextSize = 13,
            TextColor3 = Theme.SubText,
            Visible = false,
        }, ListPanel)

        local EmptyCard = new("Frame", {
            Name = "EmptyCard",
            LayoutOrder = -2,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            Visible = false,
        }, ListPanel)
        corner(EmptyCard, 8)
        stroke(EmptyCard)
        padding(EmptyCard, 16, 16, 16, 16)
        list(EmptyCard, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center })

        label(EmptyCard, {
            LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 32), Text = "{ }", TextSize = 28,
            TextColor3 = Theme.Sakura, TextXAlignment = Enum.TextXAlignment.Center,
        })
        label(EmptyCard, {
            LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 20), Text = "No scripts yet", TextSize = 16,
            TextColor3 = Theme.Text, TextXAlignment = Enum.TextXAlignment.Center,
        })
        label(EmptyCard, {
            LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true, TextColor3 = Theme.SubText,
            TextXAlignment = Enum.TextXAlignment.Center,
            Text = "Paste a script, give it a name and tap Save. Run it any time with the play button.",
        })
        local EmptyActions = new("Frame", {
            LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1,
        }, EmptyCard)
        list(EmptyActions, 10, {
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
        })
        local EmptyAdd = createAccentButton(EmptyActions, "+ Add script", 104, 34, { name = "EmptyAdd", order = 1 })
        local EmptyImport = new("TextButton", {
            Name = "EmptyImport", LayoutOrder = 2, Size = UDim2.fromOffset(76, 34),
            BackgroundColor3 = Theme.Header, BorderSizePixel = 0, AutoButtonColor = false,
            Text = "Import", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Theme.Text,
        }, EmptyActions)
        corner(EmptyImport, 6)
        borderStroke(EmptyImport)
        pressScale(EmptyImport, 0.95)
        local ExampleLink = new("TextButton", {
            Name = "ExampleLink", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 22),
            BackgroundTransparency = 1, AutoButtonColor = false,
            Text = "or add an example", Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Theme.AccentPink,
        }, EmptyCard)

        fitListPanel = function()
            local used = CONTENT_EDGE * 2 + PINNED_HEIGHT + TAB_LIST_GAP + 2
            if SearchRow.Visible then used = used + SEARCH_H + TAB_LIST_GAP end
            if OutputPanel then used = used + OutputPanel.Frame.AbsoluteSize.Y + TAB_LIST_GAP end
            ListPanel.Size = UDim2.new(1, 0, 0, math.max(80, FunctionScroll.AbsoluteSize.Y - used))
        end
        FunctionScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitListPanel)

        local function orderedEntries()
            local arr = table.clone(ScriptList)
            if View.sort == "name" then
                table.sort(arr, function(a, b)
                    local x, y = a.name:lower(), b.name:lower()
                    if x ~= y then return x < y end
                    return a.id < b.id
                end)
            elseif View.sort == "edited" then
                table.sort(arr, function(a, b)
                    if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
                    return a.id < b.id
                end)
            elseif View.sort == "recent" then
                table.sort(arr, function(a, b)
                    local x = State.stats[a.id] and State.stats[a.id].t or 0
                    local y = State.stats[b.id] and State.stats[b.id].t or 0
                    if x ~= y then return x > y end
                    if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
                    return a.id < b.id
                end)
            end
            return arr
        end

        applyListView = function()
            local q = View.query:lower()
            local shown = 0
            for i, entry in ipairs(orderedEntries()) do
                local rec = Rows[entry.id]
                if rec then
                    local match = q == ""
                        or rec.nameLower:find(q, 1, true) ~= nil
                        or (rec.codeLower and rec.codeLower:find(q, 1, true) ~= nil)
                    rec.Row.Visible = match
                    rec.Row.LayoutOrder = (entry.favorite and 0 or 100000) + i
                    if match then shown = shown + 1 end
                end
            end

            EmptyCard.Visible = #ScriptList == 0
            EmptyLabel.Visible = shown == 0 and #ScriptList > 0
            EmptyLabel.Text = ('No scripts match "%s"'):format(View.query)

            local showSearch = #ScriptList >= SEARCH_MIN_ITEMS
            if SearchRow.Visible ~= showSearch then
                SearchRow.Visible = showSearch
                if not showSearch then
                    View.query = ""
                    SearchBox.Text = ""
                end
                fitListPanel()
            end
        end

        SortBtn.MouseButton1Click:Connect(function()
            local i = table.find(SORT_MODES, View.sort) or 1
            View.sort = SORT_MODES[i % #SORT_MODES + 1]
            SortBtn.Text = SORT_LABELS[View.sort]
            applyListView()
        end)

        local searchToken = 0
        SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
            ClearBtn.Visible = SearchBox.Text ~= ""
            searchToken = searchToken + 1
            local token = searchToken
            task.delay(0.15, function()
                if token ~= searchToken then return end
                View.query = SearchBox.Text:match("^%s*(.-)%s*$")
                applyListView()
            end)
        end)
        SearchBox.FocusLost:Connect(function(_, input)
            if input and input.KeyCode == Enum.KeyCode.Escape then SearchBox.Text = "" end
        end)

        CreateScriptRow = function(entry)
            local Row, Left = CreateInfoRow(ListPanel, entry.name)
            Row.Name = "Script_" .. entry.id

            local rowLayout = Left:FindFirstChildOfClass("UIListLayout")
            if rowLayout then rowLayout:Destroy() end
            local Title = Left:FindFirstChild("Title")
            Title.AutomaticSize = Enum.AutomaticSize.None
            Title.Position = UDim2.fromOffset(0, 6)
            Title.Size = UDim2.new(1, 0, 0, 22)
            Title.TextTruncate = Enum.TextTruncate.AtEnd

            local Dot = new("Frame", {
                Position = UDim2.fromOffset(0, 33),
                Size = UDim2.fromOffset(6, 6),
                BackgroundColor3 = Theme.Border,
                BorderSizePixel = 0,
            }, Left)
            corner(Dot, 3)
            local Sub = label(Left, {
                Name = "Sub",
                Position = UDim2.fromOffset(12, 28),
                Size = UDim2.new(1, -12, 0, 16),
                Font = Enum.Font.Gotham,
                Text = "",
                TextSize = 11,
                TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })

            local rowPad = Row:FindFirstChildOfClass("UIPadding")
            local padLeft = rowPad and rowPad.PaddingLeft.Offset or 0
            local FavBar = new("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 3 - padLeft, 0.5, 0),
                Size = UDim2.new(0, 3, 0.6, 0),
                BackgroundColor3 = Theme.AccentPink,
                BorderSizePixel = 0,
                Visible = false,
            }, Row)
            corner(FavBar, 2)

            local AutoPill = new("Frame", {
                Name = "AutoPill",
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -70, 0.5, 0),
                Size = UDim2.fromOffset(44, 18),
                BackgroundColor3 = WHITE,
                BorderSizePixel = 0,
                Visible = false,
            }, Row)
            corner(AutoPill, 9)
            new("UIGradient", { Color = ColorSequence.new(Theme.AccentPurple, Theme.AccentPink) }, AutoPill)
            local AutoText = new("TextLabel", {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                Text = "AUTO",
                Font = Enum.Font.GothamBold,
                TextSize = 10,
                TextColor3 = Theme.ToggleKnobOn,
            }, AutoPill)
            AutoText:SetAttribute("OnAccent", true)

            local ExecBtn, ExecIcon = CreateIconButton(Row, "play", 0, Theme.AccentPink)
            local MoreBtn = CreateIconButton(Row, "more", 34, Theme.SubText)

            local rec = { Row = Row, entry = entry }
            Rows[entry.id] = rec

            local function paintInfo()
                local st = State.stats[entry.id]
                local text, color, dot = "Never run", Theme.SubText, Theme.Border
                if Running[entry.id] then
                    text, color, dot = "Running...", Theme.Sakura, Theme.AccentPink
                elseif entry.review then
                    text, color, dot = "Imported - review before running", Theme.AccentPurple, Theme.AccentPurple
                elseif st and st.t then
                    local runs = (st.n and st.n > 1) and (" - " .. st.n .. " runs") or ""
                    if st.ok == false then
                        text, color, dot = "Failed " .. ago(st.t) .. runs, Theme.Danger, Theme.Danger
                    else
                        text, dot = "Ran " .. ago(st.t) .. runs, Theme.Sakura
                    end
                end
                Sub.Text, Sub.TextColor3, Dot.BackgroundColor3 = text, color, dot
            end
            rec.paintInfo = paintInfo

            function rec.refresh()
                Title.Text = entry.name
                Title.TextColor3 = entry.favorite and Theme.Sakura or Theme.Text
                FavBar.Visible = entry.favorite
                local isGameAuto = (entry.autoPlace == game.PlaceId)
                local hasAuto = (entry.auto == true) or isGameAuto
                AutoPill.Visible = hasAuto
                AutoText.Text = isGameAuto and "GAME" or "AUTO"
                Left.Size = UDim2.new(1, -(76 + (hasAuto and 50 or 0)), 1, 0)
                rec.nameLower = entry.name:lower()
                rec.codeLower = entry.script:lower()
                paintInfo()
            end
            rec.refresh()

            local function showStopIcon(color)
                for _, c in ipairs(ExecIcon:GetChildren()) do c:Destroy() end
                new("Frame", {
                    AnchorPoint = ANCHOR_CENTER,
                    Position = CENTER,
                    Size = UDim2.fromOffset(10, 10),
                    BackgroundColor3 = color,
                    BorderSizePixel = 0,
                }, ExecIcon)
            end

            local function resetPlayIcon()
                for _, c in ipairs(ExecIcon:GetChildren()) do c:Destroy() end
                drawIcon(ExecIcon, "play", Theme.AccentPink, Theme.Header)
            end

            local runVisualSeq = 0
            local function setRunVisual(state)
                runVisualSeq = runVisualSeq + 1
                local seq = runVisualSeq
                if not ExecIcon.Parent then return end
                paintInfo()
                if state == "running" then return end
                if state == "running_long" then
                    showStopIcon(Theme.Danger)
                    return
                end
                resetPlayIcon()
                if state == "ok" or state == "error" then
                    tintIcon(ExecIcon, state == "ok" and Theme.Sakura or Theme.Danger)
                    task.delay(1, function()
                        if seq ~= runVisualSeq then return end
                        if ExecIcon.Parent then tintIcon(ExecIcon, Theme.AccentPink) end
                    end)
                end
            end

            local armedUntil = 0
            function rec.start()
                if entry.review then
                    if os.clock() >= armedUntil then
                        armedUntil = os.clock() + REVIEW_SECONDS
                        showToast("Imported script - read it first. Tap play again to run it.", "warn", {
                            duration = REVIEW_SECONDS,
                            actionText = "Review",
                            onAction = function() openEditDialog(entry) end,
                        })
                        return false, "review"
                    end
                    entry.review = nil
                    armedUntil = 0
                    scheduleSave()
                    rec.refresh()
                end
                return runScript(entry, setRunVisual)
            end

            ExecBtn.MouseButton1Click:Connect(function()
                if isLocked() then return end
                if Running[entry.id] then stopScript(entry); return end
                rec.start()
            end)

            MoreBtn.MouseButton1Click:Connect(function()
                if isLocked() then return end
                openContextMenu(MoreBtn, buildRowItems(entry))
            end)
            return rec
        end

        OutputPanel = createOutputPanel(fitListPanel)
        fitListPanel()

        LibMoreBtn.MouseButton1Click:Connect(function()
            if isLocked() then return end
            openContextMenu(LibMoreBtn, buildLibraryItems())
        end)

        local report = loadLibrary()
        loadState()
        pruneState()
        for _, entry in ipairs(ScriptList) do CreateScriptRow(entry) end
        applyListView()
        announceLoad(report)

        AddBtn.MouseButton1Click:Connect(function()
            if isLocked() then return end
            ScriptDialog.show("add")
        end)

        -- Options 1: Save (Add / Edit / Import)
        ScriptDialog.Save.MouseButton1Click:Connect(function()
            local dialogMode = ScriptDialog.getMode()
            local code = ScriptDialog.CodeBox.Text
            if dialogMode == "import" then
                commitImport(code)
                return
            end

            local name = sanitizeName(ScriptDialog.NameBox.Text)
            local invalid = false
            if name == "" then
                flashStrokeError(ScriptDialog.NameStroke)
                invalid = true
            end
            if code:match("^%s*$") then
                flashStrokeError(ScriptDialog.CodeStroke)
                invalid = true
            end
            if invalid then return end

            if #code > MAX_SCRIPT_LEN then
                flashStrokeError(ScriptDialog.CodeStroke)
                showToast(("Script is too large (max %d characters)"):format(MAX_SCRIPT_LEN), "error")
                return
            end

            local okSyntax, warnText = validateForSave(code)
            if not okSyntax then
                flashStrokeError(ScriptDialog.CodeStroke)
                showToast(warnText .. " - tap Save again to save anyway", "warn", { duration = 5 })
                return
            end

            if dialogMode == "edit" then
                commitEdit(ScriptDialog.getEntry(), name, code)
            else
                commitAdd(name, code)
            end
        end)

        -- Dialog: Run = test run of what is typed (nothing is saved)
        ScriptDialog.RunBtn.MouseButton1Click:Connect(function()
            local code = ScriptDialog.CodeBox.Text
            if code:match("^%s*$") then
                flashStrokeError(ScriptDialog.CodeStroke)
                return
            end
            local name = sanitizeName(ScriptDialog.NameBox.Text)
            local ok, why = quickRun(name ~= "" and name or "Test run", code)
            if not ok and why == "compile" then flashStrokeError(ScriptDialog.CodeStroke) end
        end)

        EmptyAdd.MouseButton1Click:Connect(function()
            if not isLocked() then ScriptDialog.show("add") end
        end)
        EmptyImport.MouseButton1Click:Connect(function()
            if not isLocked() then ScriptDialog.show("import") end
        end)
        ExampleLink.MouseButton1Click:Connect(function()
            if not isLocked() then addExample() end
        end)

        ScriptTab:GetPropertyChangedSignal("Visible"):Connect(function()
            if not ScriptTab.Visible then
                closeContextMenu()
                return
            end
            for _, rec in pairs(Rows) do rec.paintInfo() end
            applyListView()
        end)

        -- Auto-run: start the scripts marked for all games or this game shortly after the UI has loaded
        if State.autoRun then
            local queue = {}
            for _, e in ipairs(ScriptList) do
                if (e.auto == true or e.autoPlace == game.PlaceId) and not e.review then
                    queue[#queue + 1] = e
                end
            end
            if #queue > 0 then
                task.delay(STARTUP_DELAY, function()
                    if not ScreenGui.Parent or not State.autoRun then return end
                    showToast(("Auto-running %d script%s"):format(#queue, #queue == 1 and "" or "s"),
                        "info", { duration = 2 })
                    for _, e in ipairs(queue) do
                        if not ScreenGui.Parent then break end
                        local rec = Rows[e.id]
                        if rec and (e.auto == true or e.autoPlace == game.PlaceId) and not e.review and not Running[e.id] then
                            logOut("info", e.name, "Auto-run on startup")
                            rec.start()
                            task.wait(0.25)
                        end
                    end
                end)
            end
        end
    end

    return ScriptDialog
end
