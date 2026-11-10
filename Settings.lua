--// ##########################################################################################
--// ##                                                                                      ##
--// ##   MANDATORY: USE ENGLISH (US) ONLY IN THIS FILE                                      ##
--// ##   Every comment, UI text, message and name here MUST be written in English (US).     ##
--// ##   Never add any other language to this file. Keep it English (US) on every edit.     ##
--// ##                                                                                      ##
--// ##########################################################################################

--// ============================================================================
--//  Settings.lua  -  module for the "Settings" tab of the Elysera MainUI
--//
--//  Features:
--//    A) Anti Chat              switch that blocks sending chat messages (LayoutOrder = 1)
--//    C) Auto Execute           switch that reloads Elysera after a teleport (LayoutOrder = 2)
--//    E) Auto Load Last Session switch that restores active toggles on startup (LayoutOrder = 3)
--//    F) Reduce Motion          switch that disables animations and spinning borders (LayoutOrder = 4)
--//    G) UI Scale & Keybind     phone-friendly scale presets + customizable menu keybind (LayoutOrder = 5, 6)
--//    B) Theme                  "Theme" row + dropdown list to change the color palette (LayoutOrder = 7)
--//    H) Config & Version       Export/Import/Reset config + Version & Check for Updates (LayoutOrder = 8, 9)
--//    D) Diagnostics            executor capabilities, module sources, Copy report, Unload (LayoutOrder = 10)
--// ============================================================================

return function(D)
    --// ================= DEPS (from MainWeb.lua / MainLocal.lua) =================
    local Theme        = D.Theme
    local ScreenGui    = D.ScreenGui
    local MainUI       = D.MainUI
    local Tab          = D.Tab
    local CoreGui      = D.CoreGui
    local GuiRoot      = D.GuiRoot or CoreGui   -- where the GUI is really mounted (CoreGui, or PlayerGui as a fallback)
    local LocalPlayer  = D.LocalPlayer
    local HttpService  = D.HttpService or game:GetService("HttpService")
    local Saved        = D.Saved or {}
    local saveSettings = D.saveSettings or function() end
    local dataPath     = D.dataPath or function(name) return name end

    local new, corner, stroke, padding = D.new, D.corner, D.stroke, D.padding
    local list, label, tween, pressScale = D.list, D.label, D.tween, D.pressScale
    local CreateToggleOption, CreateCard = D.CreateToggleOption, D.CreateCard
    local CreateInfoRow, CreateStyledButton = D.CreateInfoRow, D.CreateStyledButton
    local flashButtonFeedback = D.flashButtonFeedback
    local flashStrokeError, bindBoxFocus = D.flashStrokeError, D.bindBoxFocus
    local UI, Loader, AutoExec = D.UI, D.Loader or {}, D.AutoExecute
    local showToast    = D.Toast or (UI and UI.Toast) or function() end
    local requestClose = D.requestClose

    local EASE_QUAD, EASE_BACK = D.EASE_QUAD, D.EASE_BACK
    local DIR_IN, DIR_OUT      = D.DIR_IN, D.DIR_OUT
    local ANCHOR_CENTER        = D.ANCHOR_CENTER

    local isOpen, isLocked, setLocked = D.isOpen, D.isLocked, D.setLocked
    local fadeMainUI                  = D.fadeMainUI
    local refreshStateColors          = D.refreshStateColors or function() end

    --// =====================================================================
    --// PART A. ANTI CHAT  (split out of MainLocal.lua)
    --// =====================================================================
    do (function()
        local function setProp(inst, prop, value)
            pcall(function() inst[prop] = value end)
        end

        --// ---------- Anti Chat ----------
        local TextChatService = game:GetService("TextChatService")

        local AntiChatSwitch = CreateToggleOption(Tab, "Anti Chat")
        AntiChatSwitch.Parent.LayoutOrder = 1

        local antiChatOn    = false
        local chatHooked    = false
        local antiChatConns = {}
        local antiChatBoxes = {}
        local chatBarConfig, chatBarOriginal

        -- Block messages sent from scripts (game or executor) at the __namecall / hookfunction level.
        -- The hook cannot be removed, so the antiChatOn flag is used: with the toggle off, the hook only passes calls through.
        local function isChatCall(self, method)
            if typeof(self) ~= "Instance" then return false end
            if method == "FireServer" then
                return self.ClassName == "RemoteEvent" and self.Name == "SayMessageRequest"
            elseif method == "SendAsync" then
                return self.ClassName == "TextChannel"
            elseif method == "Chat" then
                return self == LocalPlayer
            end
            return false
        end

        local function installChatHook()
            if chatHooked then return end

            if hookmetamethod and getnamecallmethod and newcclosure then
                pcall(function()
                    local old
                    old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                        if antiChatOn and isChatCall(self, getnamecallmethod()) then
                            return
                        end
                        return old(self, ...)
                    end))
                    chatHooked = true
                end)
            end

            -- Also catch calls made as remote.FireServer(remote, ...) / channel.SendAsync(channel, ...)
            if hookfunction and newcclosure then
                pcall(function()
                    local tmp = Instance.new("RemoteEvent")
                    local fn = tmp.FireServer
                    pcall(tmp.Destroy, tmp)
                    local oldFire
                    oldFire = hookfunction(fn, newcclosure(function(self, ...)
                        if antiChatOn and isChatCall(self, "FireServer") then return end
                        return oldFire(self, ...)
                    end))
                    chatHooked = true
                end)
                pcall(function()
                    local tmp = Instance.new("TextChannel")
                    local fn = tmp.SendAsync
                    pcall(tmp.Destroy, tmp)
                    local oldSend
                    oldSend = hookfunction(fn, newcclosure(function(self, ...)
                        if antiChatOn and isChatCall(self, "SendAsync") then return end
                        return oldSend(self, ...)
                    end))
                    chatHooked = true
                end)
            end
        end

        -- Block at the interface level. Legacy chat window: the ChatBar cannot get focus -> nothing can be typed or sent
        local function blockLegacyChatBar(box)
            if antiChatBoxes[box] then return end
            antiChatBoxes[box] = true
            if box:IsFocused() then box:ReleaseFocus() end
            table.insert(antiChatConns, box.Focused:Connect(function()
                box:ReleaseFocus()
            end))
        end

        local function scanLegacyChat(inst)
            if inst.Name == "ChatBar" and inst:IsA("TextBox") then
                blockLegacyChatBar(inst)
            end
        end

        local function disableAntiChat()
            antiChatOn = false
            for _, c in ipairs(antiChatConns) do c:Disconnect() end
            table.clear(antiChatConns)
            table.clear(antiChatBoxes)

            if chatBarConfig then
                if chatBarOriginal ~= nil then
                    setProp(chatBarConfig, "Enabled", chatBarOriginal)
                end
                chatBarConfig, chatBarOriginal = nil, nil
            end
        end

        local function enableAntiChat()
            disableAntiChat()
            antiChatOn = true
            installChatHook()

            -- New chat window (TextChatService): turn off the message input bar
            pcall(function()
                local cfg = TextChatService:FindFirstChildOfClass("ChatInputBarConfiguration")
                if cfg then
                    chatBarConfig, chatBarOriginal = cfg, cfg.Enabled
                    cfg.Enabled = false
                    table.insert(antiChatConns, cfg:GetPropertyChangedSignal("Enabled"):Connect(function()
                        if cfg.Enabled then setProp(cfg, "Enabled", false) end
                    end))
                end
            end)

            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if pg then
                local chatGui = pg:FindFirstChild("Chat")
                if chatGui then
                    for _, d in ipairs(chatGui:GetDescendants()) do scanLegacyChat(d) end
                end
                table.insert(antiChatConns, pg.DescendantAdded:Connect(scanLegacyChat))
            end
        end

        AntiChatSwitch:GetAttributeChangedSignal("Toggled"):Connect(function()
            if AntiChatSwitch:GetAttribute("Toggled") then
                enableAntiChat()
            else
                disableAntiChat()
            end
        end)

        --// ---------- Cleanup ----------
        ScreenGui.Destroying:Connect(function()
            disableAntiChat()
        end)
    end)() end

    --// =====================================================================
    --// PART B. THEME  (merged from Theme.lua)
    --// =====================================================================
    local DEFAULT_ID = "sakura"
    local THEMES, byId, currentId, stats, onChanged, applyTheme, closeList, listOpen
    do (function()
    local V2          = Vector2.new
    local TextService = game:GetService("TextService")

    local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

    --// ================= CONFIG =================
    local HEAL        = true   -- automatically "heal" leftover old colors (see makeLookup)
    local FADE_OUT_T  = 0.12   -- fade out
    local FADE_IN_T   = 0.22   -- fade back in
    local FADE_ALPHA  = 0.55   -- transparency at the faintest point (the remap runs here)
    local YIELD_EVERY = 700    -- batching: yield one frame after this many Instances (only while the UI is visible)

    local WIN_H, ARROW_ZONE      = 28, 26         -- winbox is 28 tall; the arrow button zone is 26
    local WIN_MIN_W, WIN_MAX_W   = 112, 190
    local ITEM_H, ITEM_GAP, LIST_PAD = 34, 4, 4
    local LIST_MIN_W, LIST_MAX_ROWS  = 200, 6
    local LIST_OPEN_T, LIST_CLOSE_T  = 0.15, 0.12
    local Z_CATCHER, Z_LIST          = 25, 30     -- above InteractionBlocker (20), below the dialogs (51)

    --// =====================================================================
    --// 1. THEME DATA
    --// =====================================================================
    local TOKENS = {
        "Background", "Panel", "PanelAlt", "Header", "Border",
        "AccentPink", "AccentPurple", "Sakura", "Text", "SubText",
        "Danger", "ToggleTrackOff", "ToggleKnobOn",
    }
    local KNOB = "ToggleKnobOn" -- excluded from the remap (may be pure white/black), handled by refreshStateColors

    local RAW = {
        { id = "sakura", name = "Elysera Sakura", mode = "dark", snapshot = true },
        { id = "ocean", name = "Midnight Ocean", mode = "dark", colors = {
            Background = "0D1D2F", Panel = "0E1F33", PanelAlt = "10243B", Header = "122A45", Border = "1F4775",
            AccentPink = "2FB9F7", AccentPurple = "4F7DFF", Sakura = "A8E9FF", Text = "D3E8FA", SubText = "8FB2D6",
            Danger = "FF6F8A", ToggleTrackOff = "1C3F68", ToggleKnobOn = "FFFFFF",
        } },
        { id = "emerald", name = "Emerald Forest", mode = "dark", colors = {
            Background = "11261D", Panel = "132920", PanelAlt = "153025", Header = "19382B", Border = "2B5F49",
            AccentPink = "34D399", AccentPurple = "7BD66B", Sakura = "C6F8E0", Text = "D6F3E4", SubText = "8FBCA6",
            Danger = "FF7B7B", ToggleTrackOff = "265441", ToggleKnobOn = "07140D",
        } },
        { id = "crimson", name = "Crimson Ember", mode = "dark", colors = {
            Background = "261013", Panel = "2A1115", PanelAlt = "301318", Header = "38171D", Border = "5F2730",
            AccentPink = "FF6B4A", AccentPurple = "E8334F", Sakura = "FFC9B8", Text = "F6DAD3", SubText = "C79A93",
            Danger = "FF5C8A", ToggleTrackOff = "54222B", ToggleKnobOn = "FFFFFF",
        } },
        { id = "sunset", name = "Golden Sunset", mode = "dark", colors = {
            Background = "261A0F", Panel = "291C10", PanelAlt = "2F2112", Header = "382716", Border = "5E4124",
            AccentPink = "FFB020", AccentPurple = "FF7A33", Sakura = "FFE0A3", Text = "F4E5CD", SubText = "C2A783",
            Danger = "FF5D5D", ToggleTrackOff = "533A20", ToggleKnobOn = "1A130C",
        } },
        { id = "lagoon", name = "Coral Lagoon", mode = "dark", colors = {
            Background = "0F272B", Panel = "102A2F", PanelAlt = "133036", Header = "16393F", Border = "26606B",
            AccentPink = "FF7F8A", AccentPurple = "FFA06B", Sakura = "FFDDD2", Text = "D5EEEE", SubText = "8FBDBF",
            Danger = "FF5470", ToggleTrackOff = "21555F", ToggleKnobOn = "FFFFFF",
        } },
        { id = "arctic", name = "Arctic Frost", mode = "dark", colors = {
            Background = "1B222A", Panel = "1D242E", PanelAlt = "222A35", Header = "28313E", Border = "435369",
            AccentPink = "8BD3F0", AccentPurple = "7C9CFF", Sakura = "D4F0FB", Text = "E1E9F2", SubText = "9DAEC4",
            Danger = "F2788C", ToggleTrackOff = "3B4A5D", ToggleKnobOn = "0F151D",
        } },
        { id = "carbon", name = "Carbon Mono", mode = "dark", colors = {
            Background = "212123", Panel = "232325", PanelAlt = "29292B", Header = "303033", Border = "515156",
            AccentPink = "E4E4E4", AccentPurple = "A0A0A0", Sakura = "F5F5F5", Text = "D6D6D6", SubText = "A3A3A3",
            Danger = "FF6B7A", ToggleTrackOff = "47474C", ToggleKnobOn = "121212",
        } },
        { id = "matrix", name = "Neon Matrix", mode = "dark", colors = {
            Background = "09150D", Panel = "0A170E", PanelAlt = "0C1A11", Header = "0E1F14", Border = "2A5A40",
            AccentPink = "1AFF9C", AccentPurple = "19D3FF", Sakura = "B6FFE0", Text = "CFF7E2", SubText = "7FBF9F",
            Danger = "FF5577", ToggleTrackOff = "1F4A30", ToggleKnobOn = "03110A",
        } },
        { id = "porcelain", name = "Porcelain Day", mode = "light", colors = {
            Background = "F5F1FB", Panel = "FBF9FE", PanelAlt = "ECE6F7", Header = "DFD5F1", Border = "B9A7DB",
            AccentPink = "C0267A", AccentPurple = "9A74F8", Sakura = "8E0F50", Text = "2D1B4E", SubText = "65558A",
            Danger = "BE1F43", ToggleTrackOff = "CDC1E4", ToggleKnobOn = "FFFFFF",
        } },
        { id = "aurora", name = "Aurora Veil", mode = "dark", colors = {
            Background = "0D0E1E", Panel = "0F1022", PanelAlt = "121329", Header = "191B3B", Border = "323776",
            AccentPink = "4DF0C2", AccentPurple = "8F7CFF", Sakura = "C9FFEF", Text = "E3E9FF", SubText = "9BA7D8",
            Danger = "FF6F91", ToggleTrackOff = "292D60", ToggleKnobOn = "08101C",
        } },
        { id = "cyber", name = "Cyber Neon", mode = "dark", colors = {
            Background = "0E091D", Panel = "100A21", PanelAlt = "140D29", Header = "1D133C", Border = "3E2880",
            AccentPink = "FF2E97", AccentPurple = "00E5FF", Sakura = "FFE45E", Text = "EFE9FF", SubText = "A99BD6",
            Danger = "FF5A36", ToggleTrackOff = "35226D", ToggleKnobOn = "0B0716",
        } },
        { id = "royal", name = "Royal Gold", mode = "dark", colors = {
            Background = "101023", Panel = "111227", PanelAlt = "15152E", Header = "1C1E3F", Border = "343674",
            AccentPink = "F5C451", AccentPurple = "F08A5D", Sakura = "FFE8A8", Text = "ECEBFA", SubText = "A7A6CF",
            Danger = "FF6B7D", ToggleTrackOff = "2B2C5F", ToggleKnobOn = "100E1F",
        } },
        { id = "oled", name = "Obsidian OLED", mode = "dark", colors = {
            Background = "07080B", Panel = "0A0C10", PanelAlt = "0E1117", Header = "161B25", Border = "34405A",
            AccentPink = "4C8DFF", AccentPurple = "A15CFF", Sakura = "C4DAFF", Text = "E6ECF7", SubText = "97A3BA",
            Danger = "FF5E7A", ToggleTrackOff = "2A3348", ToggleKnobOn = "FFFFFF",
        } },
        { id = "matcha", name = "Matcha Moss", mode = "dark", colors = {
            Background = "14180F", Panel = "171B10", PanelAlt = "1C2114", Header = "2A311E", Border = "4C5936",
            AccentPink = "B8E04A", AccentPurple = "6FCB7A", Sakura = "E4F7B0", Text = "E6EBD6", SubText = "A2AE8A",
            Danger = "FF7B63", ToggleTrackOff = "3E492D", ToggleKnobOn = "0D1108",
        } },
        { id = "rosegold", name = "Rose Gold Noir", mode = "dark", colors = {
            Background = "1E1715", Panel = "211917", PanelAlt = "271E1B", Header = "362926", Border = "5A453F",
            AccentPink = "E9A68C", AccentPurple = "C98BA0", Sakura = "FFD9C9", Text = "F3E3DD", SubText = "BE9F98",
            Danger = "F0605D", ToggleTrackOff = "4B3A34", ToggleKnobOn = "1A0F0D",
        } },
        { id = "dusk", name = "Dusk Pastel", mode = "dark", colors = {
            Background = "1D1D2B", Panel = "1F1F2E", PanelAlt = "232334", Header = "2D2D43", Border = "4B4B71",
            AccentPink = "F2A7C8", AccentPurple = "8DB8FF", Sakura = "FFD6E8", Text = "E4E6F8", SubText = "A9ADCF",
            Danger = "FF8A8A", ToggleTrackOff = "3F3F5F", ToggleKnobOn = "15162A",
        } },
        { id = "latte", name = "Latte Cream", mode = "light", colors = {
            Background = "F6F1E9", Panel = "FBF8F4", PanelAlt = "F2E9DE", Header = "EADDCC", Border = "C6AC8B",
            AccentPink = "A4561C", AccentPurple = "B8742A", Sakura = "5E2F0E", Text = "3A2618", SubText = "75604C",
            Danger = "B3261E", ToggleTrackOff = "D7C5AD", ToggleKnobOn = "FFFFFF",
        } },
        { id = "mint", name = "Mint Breeze", mode = "light", colors = {
            Background = "EDF7F3", Panel = "F8FCFA", PanelAlt = "E3F2EC", Header = "D1EAE0", Border = "9CC9B6",
            AccentPink = "0A7F62", AccentPurple = "119A88", Sakura = "07533F", Text = "12302A", SubText = "4B6B60",
            Danger = "C0304B", ToggleTrackOff = "C3DFD3", ToggleKnobOn = "FFFFFF",
        } },
        { id = "sky", name = "Sky Cloud", mode = "light", colors = {
            Background = "EBF2F9", Panel = "F7FAFD", PanelAlt = "DFE9F6", Header = "CBDCF0", Border = "9FBADB",
            AccentPink = "1B66E3", AccentPurple = "4F7DF0", Sakura = "0B3A8A", Text = "112440", SubText = "4A6286",
            Danger = "C4283F", ToggleTrackOff = "C4D4E9", ToggleKnobOn = "FFFFFF",
        } },
        { id = "quartz", name = "Rose Quartz", mode = "light", colors = {
            Background = "FAEFF2", Panel = "FEFBFC", PanelAlt = "F6E4E9", Header = "F0D0D8", Border = "DAA9B6",
            AccentPink = "C2255C", AccentPurple = "E0558A", Sakura = "7D1237", Text = "3A1220", SubText = "7A4A5B",
            Danger = "C2410C", ToggleTrackOff = "E8C9D1", ToggleKnobOn = "FFFFFF",
        } },
        { id = "paper", name = "Paper Ink", mode = "light", colors = {
            Background = "F1F1F3", Panel = "FAFAFA", PanelAlt = "E9E9EC", Header = "DCDCE0", Border = "B5B5C0",
            AccentPink = "2B2B33", AccentPurple = "6B6B78", Sakura = "0C0C10", Text = "1D1D24", SubText = "5E5E6B",
            Danger = "C62828", ToggleTrackOff = "CDCDD5", ToggleKnobOn = "FFFFFF",
        } },
    }

    local function hex(h)
        return Color3.fromRGB(
            tonumber(h:sub(1, 2), 16),
            tonumber(h:sub(3, 4), 16),
            tonumber(h:sub(5, 6), 16))
    end

    local function colorKey(c)
        return math.floor(c.R * 255 + 0.5) * 65536
            + math.floor(c.G * 255 + 0.5) * 256
            + math.floor(c.B * 255 + 0.5)
    end

    local function validatePalette(p)
        if type(p) ~= "table" then return false, "not a table" end
        local seen = {}
        for _, k in ipairs(TOKENS) do
            local c = p[k]
            if typeof(c) ~= "Color3" then
                return false, "token " .. k .. " is missing or is not a Color3"
            end
            if k ~= KNOB then
                local key = colorKey(c)
                if key == 0xFFFFFF or key == 0x000000 then
                    return false, "token " .. k .. " must not be #FFFFFF or #000000"
                end
                if seen[key] then
                    return false, "token " .. k .. " has the same color as " .. seen[key]
                end
                seen[key] = k
            end
        end
        return true
    end

    local function buildThemes()
        local out = {}
        for _, raw in ipairs(RAW) do
            local colors = {}
            for _, k in ipairs(TOKENS) do
                if raw.snapshot then
                    colors[k] = Theme[k]
                elseif raw.colors[k] then
                    colors[k] = hex(raw.colors[k])
                end
            end
            local ok, why = validatePalette(colors)
            if ok then
                out[#out + 1] = { id = raw.id, name = raw.name, mode = raw.mode, colors = colors }
            else
                warn("[Elysera/Theme] Skipping theme '" .. tostring(raw.id) .. "': " .. tostring(why))
            end
        end
        return out
    end

    THEMES = buildThemes()
    byId = {}
    for _, t in ipairs(THEMES) do byId[t.id] = t end
    assert(byId[DEFAULT_ID], "Settings.lua: missing default theme '" .. DEFAULT_ID .. "'")

    local function buildHealIndex(themes)
        local role, ambiguous = {}, {}
        for _, t in ipairs(themes) do
            for _, k in ipairs(TOKENS) do
                if k ~= KNOB then
                    local key = colorKey(t.colors[k])
                    if role[key] and role[key] ~= k then
                        ambiguous[key] = true
                    else
                        role[key] = k
                    end
                end
            end
        end
        for key in pairs(ambiguous) do role[key] = nil end
        return role
    end
    local healRole = HEAL and buildHealIndex(THEMES) or {}

    --// =====================================================================
    --// 2. ENGINE
    --// =====================================================================
    currentId = DEFAULT_ID
    local applying, pendingId, pendingOpts = false, nil, nil
    stats = { scanned = 0, changed = 0, ms = 0 }

    local function noop() end
    local refreshItems, updateWinbox = noop, noop
    closeList = noop

    local holds, prevLocked = 0, false
    local function hold()
        if holds == 0 then
            prevLocked = isLocked()
            setLocked(true)
        end
        holds = holds + 1
    end
    local function release()
        if holds == 0 then return end
        holds = holds - 1
        if holds == 0 then setLocked(prevLocked) end
    end

    local listeners = {}
    function onChanged(fn)
        if type(fn) ~= "function" then return noop end
        listeners[#listeners + 1] = fn
        return function()
            for i = #listeners, 1, -1 do
                if listeners[i] == fn then
                    table.remove(listeners, i)
                    break
                end
            end
        end
    end
    local function fire(entry)
        local snapshot = {}
        for i = 1, #listeners do snapshot[i] = listeners[i] end
        for i = 1, #snapshot do
            local ok, err = pcall(snapshot[i], entry.id, Theme, entry)
            if not ok then warn("[Elysera/Theme] onChanged error: " .. tostring(err)) end
        end
    end

    local function buildColorMap(from, to)
        local map = {}
        for _, k in ipairs(TOKENS) do
            if k ~= KNOB then map[colorKey(from[k])] = to[k] end
        end
        return map
    end

    local function makeLookup(map, target)
        return function(c)
            local key = colorKey(c)
            local v = map[key]
            if v then return v end
            local role = healRole[key]
            if role then return target[role] end
            return nil
        end
    end

    local function remapSequence(seq, lookup)
        local kps, out, changed = seq.Keypoints, {}, false
        for i = 1, #kps do
            local kp = kps[i]
            local nc = lookup(kp.Value)
            if nc and nc ~= kp.Value then
                changed = true
                out[i] = ColorSequenceKeypoint.new(kp.Time, nc)
            else
                out[i] = kp
            end
        end
        if changed then return ColorSequence.new(out) end
        return nil
    end

    local BG   = { "BackgroundColor3", "BorderColor3" }
    local TXT  = { "BackgroundColor3", "BorderColor3", "TextColor3", "TextStrokeColor3" }
    local IMG  = { "BackgroundColor3", "BorderColor3", "ImageColor3" }
    local PROPS = {
        Frame          = BG,
        CanvasGroup    = BG,
        ScrollingFrame = { "BackgroundColor3", "BorderColor3", "ScrollBarImageColor3" },
        TextLabel      = TXT,
        TextButton     = TXT,
        TextBox        = { "BackgroundColor3", "BorderColor3", "TextColor3", "TextStrokeColor3", "PlaceholderColor3" },
        ImageLabel     = IMG,
        ImageButton    = IMG,
        ViewportFrame  = IMG,
        UIStroke       = { "Color" },
    }

    local function remapInstance(inst, lookup)
        local n = 0
        local class = inst.ClassName
        local props = PROPS[class]
        if props then
            for i = 1, #props do
                local prop = props[i]
                local cur = inst[prop]
                local nc = lookup(cur)
                if nc and nc ~= cur then
                    inst[prop] = nc
                    n = n + 1
                end
            end
        elseif class == "UIGradient" then
            local seq = remapSequence(inst.Color, lookup)
            if seq then
                inst.Color = seq
                n = n + 1
            end
        end
        return n
    end

    local function gather(inst, out)
        if inst:GetAttribute("NoTheme") then return end
        out[#out + 1] = inst
        local kids = inst:GetChildren()
        for i = 1, #kids do gather(kids[i], out) end
    end

    local function remapTree(roots, lookup, yieldEvery)
        local nodes = {}
        for _, r in ipairs(roots) do gather(r, nodes) end
        local changed = 0
        for i = 1, #nodes do
            local ok, n = pcall(remapInstance, nodes[i], lookup)
            if ok then changed = changed + n end
            if yieldEvery and i % yieldEvery == 0 then task.wait() end
        end
        return #nodes, changed
    end

    local EXTRA_ROOTS = { "ElyseraCover", "ElyseraFpsOverlay" }

    local function getRoots()
        local roots = { ScreenGui }
        local containers = { GuiRoot }
        if CoreGui and CoreGui ~= GuiRoot then containers[#containers + 1] = CoreGui end
        for _, container in ipairs(containers) do
            for _, name in ipairs(EXTRA_ROOTS) do
                local okG, gui = pcall(container.FindFirstChild, container, name)
                if okG and gui then roots[#roots + 1] = gui end
            end
        end
        return roots
    end

    local function commit(entry, opts)
        local t0 = os.clock()
        local lookup = makeLookup(buildColorMap(Theme, entry.colors), entry.colors)

        for _, k in ipairs(TOKENS) do Theme[k] = entry.colors[k] end
        currentId = entry.id

        if D.settleColorTweens then
            local okS, errS = pcall(D.settleColorTweens, lookup)
            if not okS then warn("[Elysera/Theme] settleColorTweens error: " .. tostring(errS)) end
        end

        local scanned, changed = remapTree(getRoots(), lookup, opts.yieldEvery)

        ScreenGui:SetAttribute("Theme", entry.id)
        Saved.theme = entry.id

        local ok, err = pcall(refreshStateColors)
        if not ok then warn("[Elysera/Theme] refreshStateColors error: " .. tostring(err)) end
        pcall(refreshItems)
        pcall(updateWinbox)

        stats.scanned, stats.changed, stats.ms = scanned, changed, (os.clock() - t0) * 1000
        if not opts.noSave then saveSettings() end
        fire(entry)
    end

    local function drainPending()
        local nextId, nextOpts = pendingId, pendingOpts
        pendingId, pendingOpts = nil, nil
        if nextId and nextId ~= currentId then applyTheme(nextId, nextOpts) end
    end

    function applyTheme(id, opts)
        opts = opts or {}
        local entry = byId[id]
        if not entry then return false, "Theme does not exist: " .. tostring(id) end

        if applying then
            pendingId, pendingOpts = id, opts
            return true
        end
        if id == currentId and not opts.force then return true end

        local animate = opts.animate ~= false and not Saved.reduceMotion and isOpen() and MainUI.Visible
        closeList(true)

        if not animate then
            applying = true
            local ok, err = pcall(commit, entry, opts)
            applying = false
            if not ok then warn("[Elysera/Theme] Error while applying '" .. id .. "': " .. tostring(err)) end
            drainPending()
            return ok, err
        end

        applying = true
        hold()
        task.spawn(function()
            local ok, err = pcall(function()
                fadeMainUI(FADE_OUT_T, FADE_ALPHA, DIR_OUT)
                task.wait(FADE_OUT_T)
            end)
            if not ok then warn("[Elysera/Theme] Error while fading out: " .. tostring(err)) end

            ok, err = pcall(commit, entry, { noSave = opts.noSave, yieldEvery = YIELD_EVERY })
            if not ok then warn("[Elysera/Theme] Error while applying '" .. id .. "': " .. tostring(err)) end

            ok, err = pcall(function()
                if isOpen() then fadeMainUI(FADE_IN_T, 0, DIR_OUT) end
            end)
            if not ok then warn("[Elysera/Theme] Error while fading back in: " .. tostring(err)) end

            applying = false
            release()
            drainPending()
        end)
        return true
    end

    --// =====================================================================
    --// 3. INTERFACE (Theme row + dropdown list)
    --// =====================================================================
    local function measure(text, size)
        local ok, v = pcall(TextService.GetTextSize, TextService, text, size,
            Enum.Font.GothamBold, V2(1000, 100))
        if ok and v then return v.X end
        return #text * size * 0.6
    end

    local function drawLine(parent, a, b, thick, color)
        local d, mid = b - a, (a + b) / 2
        local f = new("Frame", {
            AnchorPoint = ANCHOR_CENTER,
            Position = UDim2.fromOffset(mid.X, mid.Y),
            Size = UDim2.fromOffset(d.Magnitude + thick, thick),
            Rotation = math.deg(math.atan2(d.Y, d.X)),
            BackgroundColor3 = color,
            BorderSizePixel = 0,
        }, parent)
        corner(f, thick / 2)
        return f
    end

    local function pressItem(btn, downScale)
        local scale = new("UIScale", {}, btn)
        local function up() tween(scale, 0.2, { Scale = 1 }, EASE_BACK, DIR_OUT) end
        btn.MouseButton1Down:Connect(function() tween(scale, 0.08, { Scale = downScale }) end)
        btn.MouseButton1Up:Connect(up)
        btn.MouseLeave:Connect(up)
    end

    local Row, Winbox, WinLabel, Arrow, ArrowBars
    local Catcher, List, ListScroll, ListScrollPad, ListStroke
    local items = {}
    local titleW, listW = 50, LIST_MIN_W
    local listToken = 0
    listOpen = false
    local lastRight, lastTop, lastFlip, lastW, lastH = 0, 0, false, 0, 0

    local DOTS_W  = 4 * 10 + 3 * 3
    local DOTS_X  = 12
    local NAME_X  = DOTS_X + DOTS_W + 9
    local RIGHT_Z = 28

    function updateWinbox()
        if not Winbox then return end
        local entry = byId[currentId]
        WinLabel.Text = entry.name
        local w = clamp(math.ceil(measure(entry.name, 13)) + 20 + ARROW_ZONE, WIN_MIN_W, WIN_MAX_W)
        local rowW = Row.AbsoluteSize.X
        if rowW > 0 then
            w = math.min(w, math.max(64, rowW - 14 - titleW - 8 - 12))
        end
        Winbox.Size = UDim2.fromOffset(w, WIN_H)
    end

    local function setArrow(open)
        if not Arrow then return end
        tween(Arrow, 0.2, { Rotation = open and 180 or 0 }, EASE_QUAD, DIR_OUT)
        local col = open and Theme.Sakura or Theme.SubText
        for _, bar in ipairs(ArrowBars) do tween(bar, 0.15, { BackgroundColor3 = col }) end
    end

    function refreshItems()
        for id, it in pairs(items) do
            local sel = (id == currentId)
            it.btn.BackgroundTransparency = sel and 0 or 1
            it.name.TextColor3 = sel and Theme.Sakura or Theme.Text
            it.bar.Visible = sel
            it.check.Visible = sel
        end
    end

    local function repaintTab()
        local fn = D.repaintContent
        if fn then fn() end
    end

    local function positionList()
        local rp = Row.AbsolutePosition - MainUI.AbsolutePosition
        local rs = Row.AbsoluteSize
        local n = #THEMES
        local fullH = n * ITEM_H + (n - 1) * ITEM_GAP + LIST_PAD * 2
        local maxH  = LIST_MAX_ROWS * ITEM_H + (LIST_MAX_ROWS - 1) * ITEM_GAP + LIST_PAD * 2
        local minH  = 3 * ITEM_H + 2 * ITEM_GAP + LIST_PAD * 2

        local below = MainUI.AbsoluteSize.Y - (rp.Y + rs.Y + 6) - 8
        local above = rp.Y - 6 - 8
        local flip, room = false, below
        if below < minH and above > below then flip, room = true, above end

        local h = math.max(ITEM_H + LIST_PAD * 2, math.min(fullH, maxH, room))
        local top = flip and (rp.Y - 6 - h) or (rp.Y + rs.Y + 6)

        ListScrollPad.PaddingRight = UDim.new(0, fullH > h and 6 or 0)
        lastRight, lastTop, lastFlip = rp.X + rs.X, top, flip
        lastW, lastH = math.min(listW, rs.X), h
    end

    local function placeList()
        List.AnchorPoint = Vector2.new(1, lastFlip and 1 or 0)
        List.Position = UDim2.fromOffset(lastRight, lastFlip and (lastTop + lastH) or lastTop)
        ListScroll.AnchorPoint = Vector2.new(0, lastFlip and 1 or 0)
        ListScroll.Position = UDim2.fromScale(0, lastFlip and 1 or 0)
        ListScroll.Size = UDim2.new(1, 0, 0, lastH - LIST_PAD * 2)
    end

    local function openList()
        if listOpen or applying or not List or isLocked() then return end
        listOpen = true
        listToken = listToken + 1
        hold()
        refreshItems()
        positionList()
        placeList()

        List.Size = UDim2.fromOffset(lastW, 0)
        List.BackgroundTransparency = 1
        ListStroke.Transparency = 1
        List.Visible = true
        Catcher.Visible = true
        tween(List, LIST_OPEN_T, {
            Size = UDim2.fromOffset(lastW, lastH),
            BackgroundTransparency = 0,
        }, EASE_QUAD, DIR_OUT)
        tween(ListStroke, LIST_OPEN_T, { Transparency = 0 }, EASE_QUAD, DIR_OUT)
        setArrow(true)
        repaintTab()
    end

    function closeList(instant)
        if not listOpen then return end
        listOpen = false
        listToken = listToken + 1
        local token = listToken
        release()
        Catcher.Visible = false
        setArrow(false)

        if instant then
            List.Visible = false
            repaintTab()
            return
        end
        local t = tween(List, LIST_CLOSE_T, {
            Size = UDim2.fromOffset(lastW, 0),
            BackgroundTransparency = 1,
        }, EASE_QUAD, DIR_IN)
        tween(ListStroke, LIST_CLOSE_T, { Transparency = 1 }, EASE_QUAD, DIR_IN)
        t.Completed:Connect(function(state)
            if state == Enum.PlaybackState.Completed and token == listToken then
                List.Visible = false
                repaintTab()
            end
        end)
    end

    local function pick(id)
        if id == currentId then
            closeList(false)
        else
            applyTheme(id, { animate = true })
        end
    end

    local function createListItem(entry, index)
        local Item = new("TextButton", {
            Name = "Theme_" .. entry.id,
            LayoutOrder = index,
            Size = UDim2.new(1, 0, 0, ITEM_H),
            BackgroundColor3 = Theme.Header,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
        }, ListScroll)
        corner(Item, 6)
        pressItem(Item, 0.97)

        local Bar = new("Frame", {
            Name = "AccentBar",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 4, 0.5, 0),
            Size = UDim2.fromOffset(3, 18),
            BackgroundColor3 = Theme.AccentPink,
            BorderSizePixel = 0,
            Visible = false,
        }, Item)
        corner(Bar, 2)

        local Dots = new("Frame", {
            Name = "Swatch",
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, DOTS_X, 0.5, 0),
            Size = UDim2.fromOffset(DOTS_W, 10),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        }, Item)
        Dots:SetAttribute("NoTheme", true)
        list(Dots, 3, {
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
        })
        local c = entry.colors
        for i, key in ipairs({ "Background", "AccentPink", "AccentPurple", "Text" }) do
            local dot = new("Frame", {
                LayoutOrder = i,
                Size = UDim2.fromOffset(10, 10),
                BackgroundColor3 = c[key],
                BorderSizePixel = 0,
            }, Dots)
            corner(dot, 5)
            if key == "Background" then stroke(dot, c.Border, 1) end
        end

        local NameLabel = label(Item, {
            Name = "Name",
            Position = UDim2.fromOffset(NAME_X, 0),
            Size = UDim2.new(1, -(NAME_X + RIGHT_Z), 1, 0),
            Text = entry.name,
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })

        local Check = new("Frame", {
            Name = "Check",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Visible = false,
        }, Item)
        drawLine(Check, V2(2, 7.5), V2(5.5, 11), 1.8, Theme.AccentPink)
        drawLine(Check, V2(5.5, 11), V2(12, 3.5), 1.8, Theme.AccentPink)

        Item.MouseEnter:Connect(function()
            if entry.id ~= currentId then tween(Item, 0.12, { BackgroundTransparency = 0.5 }) end
        end)
        Item.MouseLeave:Connect(function()
            if entry.id ~= currentId then tween(Item, 0.12, { BackgroundTransparency = 1 }) end
        end)
        Item.MouseButton1Click:Connect(function() pick(entry.id) end)

        items[entry.id] = { btn = Item, name = NameLabel, bar = Bar, check = Check }
    end

    local function createList()
        Catcher = new("TextButton", {
            Name = "ThemeListCatcher",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
            Visible = false,
            ZIndex = Z_CATCHER,
        }, MainUI)
        Catcher.MouseButton1Click:Connect(function() closeList(false) end)

        local widest = 0
        for _, t in ipairs(THEMES) do widest = math.max(widest, measure(t.name, 13)) end
        listW = math.max(LIST_MIN_W, math.ceil(widest) + NAME_X + RIGHT_Z + LIST_PAD * 2 + 8)

        List = new("Frame", {
            Name = "ThemeList",
            Visible = false,
            Active = true,
            ClipsDescendants = true,
            AnchorPoint = Vector2.new(1, 0),
            Size = UDim2.fromOffset(listW, 120),
            BackgroundColor3 = Theme.Panel,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = Z_LIST,
        }, MainUI)
        corner(List, 8)
        ListStroke = stroke(List, Theme.Border, 1)
        ListStroke.Transparency = 1
        padding(List, LIST_PAD, LIST_PAD, LIST_PAD, LIST_PAD)

        ListScroll = new("ScrollingFrame", {
            Name = "Items",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.AccentPink,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ScrollingDirection = Enum.ScrollingDirection.Y,
        }, List)
        list(ListScroll, ITEM_GAP)
        ListScrollPad = padding(ListScroll, 0, 0)

        for index, entry in ipairs(THEMES) do createListItem(entry, index) end

        MainUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            if listOpen then
                positionList()
                placeList()
                List.Size = UDim2.fromOffset(lastW, lastH)
            end
        end)
    end

    local function createThemeRow()
        Row = new("Frame", {
            Name = "ThemeRow",
            LayoutOrder = 7,
            Size = UDim2.new(1, 0, 0, 50),
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
        }, Tab)
        corner(Row, 8)
        stroke(Row)

        titleW = math.ceil(measure("Theme", 15)) + 2
        label(Row, {
            Name = "Title",
            Size = UDim2.new(0, titleW, 1, 0),
            Position = UDim2.fromOffset(14, 0),
            Text = "Theme",
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Text,
        })

        Winbox = new("TextButton", {
            Name = "Winbox",
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.fromOffset(WIN_MIN_W, WIN_H),
            BackgroundColor3 = Theme.Header,
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Text = "",
        }, Row)
        corner(Winbox, 6)
        stroke(Winbox, Theme.Border, 1).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        pressScale(Winbox, 0.97)

        WinLabel = label(Winbox, {
            Name = "Name",
            Size = UDim2.fromScale(1, 1),
            Text = "",
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        padding(WinLabel, 20, 20)

        Arrow = new("Frame", {
            Name = "Arrow",
            AnchorPoint = ANCHOR_CENTER,
            Position = UDim2.new(1, -ARROW_ZONE / 2, 0.5, 0),
            Size = UDim2.fromOffset(ARROW_ZONE, ARROW_ZONE),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        }, Winbox)
        ArrowBars = {
            drawLine(Arrow, V2(8.5, 10.5), V2(13, 15), 1.8, Theme.SubText),
            drawLine(Arrow, V2(13, 15), V2(17.5, 10.5), 1.8, Theme.SubText),
        }

        Winbox.MouseEnter:Connect(function()
            if isLocked() then return end
            tween(Winbox, 0.15, { BackgroundColor3 = Theme.Border })
        end)
        Winbox.MouseLeave:Connect(function()
            tween(Winbox, 0.15, { BackgroundColor3 = Theme.Header })
        end)
        Winbox.MouseButton1Click:Connect(function()
            if listOpen then closeList(false) else openList() end
        end)

        Row:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateWinbox)
        updateWinbox()
    end

    --// =====================================================================
    --// 4. INIT + API
    --// =====================================================================
    local savedId = Saved.theme
    if type(savedId) == "string" and savedId ~= currentId and byId[savedId] then
        local ok, err = pcall(applyTheme, savedId, { animate = false, noSave = true })
        if not ok then warn("[Elysera/Theme] Could not apply the saved theme: " .. tostring(err)) end
    end
    ScreenGui:SetAttribute("Theme", currentId)

    local okUI, errUI = pcall(function()
        createList()
        createThemeRow()
        refreshItems()
    end)
    if not okUI then warn("[Elysera/Theme] Could not build the Theme row: " .. tostring(errUI)) end
    end)() end

    --// =====================================================================
    --// PART C. AUTO EXECUTE, AUTO LOAD LAST SESSION, REDUCE MOTION, UI SCALE, KEYBIND
    --// =====================================================================
    local setAutoExecSwitch, setAutoLoadSwitch, setReduceMotionSwitch, refreshScaleUI, refreshKeyUI
    do (function()
        local function addSubtitle(row, titleText, subText)
            for _, child in ipairs(row:GetChildren()) do
                if child:IsA("TextLabel") and child.Text == titleText then
                    child.Position = UDim2.fromOffset(14, 8)
                    child.Size = UDim2.new(1, -80, 0, 22)
                end
            end
            return label(row, {
                Position = UDim2.fromOffset(14, 31),
                Size = UDim2.new(1, -80, 0, 16),
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextColor3 = Theme.SubText,
                Text = subText,
            })
        end

        if AutoExec and CreateToggleOption then
            pcall(function()
                local reason = AutoExec.reason()
                local startOn = AutoExec.isOn() and reason == nil
                local Switch, setState, toggleApi = CreateToggleOption(Tab, "Auto Execute", 56, { initial = startOn })
                setAutoExecSwitch = setState
                Switch.Parent.LayoutOrder = 2
                local Sub = addSubtitle(Switch.Parent, "Auto Execute", "")
                local function showReason(why)
                    if why then
                        Sub.Text = "Not supported: " .. why
                        Sub.TextColor3 = Theme.Danger
                    else
                        Sub.Text = "Reload Elysera and active toggles after server hop"
                        Sub.TextColor3 = Theme.SubText
                    end
                end
                showReason(reason)

                toggleApi.onChanged(function(on)
                    local ok, why = AutoExec.set(on)
                    if on and not ok then
                        showReason(why)
                        task.defer(setState, false, true)
                    end
                end)
            end)
        end

        -- Auto Load Last Session
        pcall(function()
            local Switch, setState, toggleApi = CreateToggleOption(Tab, "Auto Load Last Session", 56, {
                initial = Saved.autoLoadSession == true,
            })
            setAutoLoadSwitch = setState
            Switch.Parent.LayoutOrder = 3
            addSubtitle(Switch.Parent, "Auto Load Last Session", "Restore active toggles from your last session on startup")
            toggleApi.onChanged(function(on)
                Saved.autoLoadSession = on == true
                saveSettings()
            end)
        end)

        -- Reduce Motion
        pcall(function()
            local Switch, setState, toggleApi = CreateToggleOption(Tab, "Reduce Motion", 56, {
                initial = Saved.reduceMotion == true,
            })
            setReduceMotionSwitch = setState
            Switch.Parent.LayoutOrder = 4
            addSubtitle(Switch.Parent, "Reduce Motion", "Instant transitions and pause continuous animations")
            toggleApi.onChanged(function(on)
                if D.setReduceMotion then
                    D.setReduceMotion(on)
                else
                    Saved.reduceMotion = on == true
                    saveSettings()
                end
            end)
        end)

        -- UI Scale (phone-friendly presets)
        pcall(function()
            local SCALES = { 0.75, 0.85, 1.0, 1.15, 1.25 }
            local ScaleCard = CreateCard(Tab, "UIScaleCard", 10, 14, 14)
            ScaleCard.LayoutOrder = 5

            local Top = new("Frame", {
                LayoutOrder = 1,
                Size = UDim2.new(1, 0, 0, 20),
                BackgroundTransparency = 1,
            }, ScaleCard)
            label(Top, {
                Size = UDim2.new(0.6, 0, 1, 0),
                Text = "UI Scale",
                TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = Theme.Text,
            })
            local ScaleVal = label(Top, {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.fromScale(1, 0),
                Size = UDim2.new(0.4, 0, 1, 0),
                Text = "100%",
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Right,
                TextColor3 = Theme.AccentPink,
            })

            local ChipRow = new("Frame", {
                LayoutOrder = 2,
                Size = UDim2.new(1, 0, 0, 28),
                BackgroundTransparency = 1,
            }, ScaleCard)
            list(ChipRow, 6, { FillDirection = Enum.FillDirection.Horizontal })

            local chips = {}
            refreshScaleUI = function()
                local cur = (D.getUIScale and D.getUIScale()) or Saved.uiScale or 1
                ScaleVal.Text = math.floor(cur * 100 + 0.5) .. "%"
                for _, c in ipairs(chips) do
                    local active = math.abs(c.scale - cur) < 0.02
                    c.btn.TextColor3 = active and Theme.Sakura or Theme.Text
                    c.stroke.Color = active and Theme.AccentPink or Theme.Border
                end
            end

            for i, s in ipairs(SCALES) do
                local Btn = new("TextButton", {
                    LayoutOrder = i,
                    Size = UDim2.new(1 / #SCALES, -5, 1, 0),
                    BackgroundColor3 = Theme.Header,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = math.floor(s * 100 + 0.5) .. "%",
                    Font = Enum.Font.GothamBold,
                    TextSize = 12,
                    TextColor3 = Theme.Text,
                }, ChipRow)
                corner(Btn, 6)
                local st = UI.BorderStroke(Btn)
                pressScale(Btn, 0.95)
                chips[i] = { scale = s, btn = Btn, stroke = st }
                Btn.Activated:Connect(function()
                    if isLocked() then return end
                    if D.setUIScale then D.setUIScale(s) else Saved.uiScale = s; saveSettings() end
                    refreshScaleUI()
                end)
            end
            refreshScaleUI()
        end)

        -- Menu Keybind
        pcall(function()
            local KeyFrame, KeyLeft = CreateInfoRow(Tab, "Menu Keybind")
            KeyFrame.LayoutOrder = 6
            label(KeyLeft, {
                LayoutOrder = 2,
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = "· Backspace to clear",
                Font = Enum.Font.Gotham,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = Theme.SubText,
            })
            local KeyBtn = CreateStyledButton(KeyFrame, "RightShift", 104)
            refreshKeyUI = function()
                local k = (D.getToggleKey and D.getToggleKey()) or Saved.toggleKey or ""
                KeyBtn.Text = (k ~= "") and k or "None"
                KeyBtn.TextColor3 = Theme.Text
            end
            refreshKeyUI()

            KeyBtn.Activated:Connect(function()
                if isLocked() or not D.captureToggleKey then return end
                KeyBtn.Text = "Press key..."
                KeyBtn.TextColor3 = Theme.Sakura
                D.captureToggleKey(function(newKey)
                    KeyBtn.Text = (newKey ~= "") and newKey or "None"
                    KeyBtn.TextColor3 = Theme.Text
                    showToast("Menu keybind: " .. ((newKey ~= "") and newKey or "None"), "info", { duration = 1.8 })
                end)
            end)
        end)
    end)() end

    --// =====================================================================
    --// PART E. CONFIG (Export / Import / Reset) & VERSION / CHECK UPDATE
    --// =====================================================================
    do (function()
        local EXTRA_FILES = { "Elysera_Fps.json", "Elysera_Waypoints.json", "L-scr.state.json" }

        pcall(function()
            local CfgCard = CreateCard(Tab, "ConfigCard", 12, 14, 14)
            CfgCard.LayoutOrder = 8

            label(CfgCard, {
                LayoutOrder = 1,
                Size = UDim2.new(1, 0, 0, 20),
                Text = "Configuration",
                TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = Theme.Text,
            })

            local CfgBox = new("TextBox", {
                LayoutOrder = 2,
                Size = UDim2.new(1, 0, 0, 32),
                BackgroundColor3 = Theme.PanelAlt,
                BorderSizePixel = 0,
                Text = "",
                PlaceholderText = "Paste exported config JSON (or leave empty to use clipboard)",
                PlaceholderColor3 = Theme.SubText,
                ClearTextOnFocus = false,
                Font = Enum.Font.Gotham,
                TextSize = 13,
                TextColor3 = Theme.Text,
                TextXAlignment = Enum.TextXAlignment.Left,
                ClipsDescendants = true,
            }, CfgCard)
            corner(CfgBox, 6)
            local CfgStroke = UI.BorderStroke(CfgBox)
            padding(CfgBox, 10, 10)
            if bindBoxFocus then bindBoxFocus(CfgBox, CfgStroke) end

            local ActionRow = new("Frame", {
                LayoutOrder = 3,
                Size = UDim2.new(1, 0, 0, 30),
                BackgroundTransparency = 1,
            }, CfgCard)
            list(ActionRow, 8, { FillDirection = Enum.FillDirection.Horizontal })

            local function actionBtn(text, order, isDanger)
                local B = new("TextButton", {
                    LayoutOrder = order,
                    Size = UDim2.new(1 / 3, -6, 1, 0),
                    BackgroundColor3 = Theme.Header,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Text = text,
                    Font = Enum.Font.GothamBold,
                    TextSize = 13,
                    TextColor3 = isDanger and Theme.Danger or Theme.Text,
                }, ActionRow)
                corner(B, 6)
                UI.BorderStroke(B)
                pressScale(B, 0.95)
                return B
            end

            local ExportBtn = actionBtn("Export", 1, false)
            local ImportBtn = actionBtn("Import", 2, false)
            local ResetCfgBtn = actionBtn("Reset", 3, true)

            ExportBtn.Activated:Connect(function()
                if isLocked() then return end
                local filesData = {}
                if D.canFS then
                    for _, f in ipairs(EXTRA_FILES) do
                        pcall(function()
                            local p = dataPath(f)
                            if isfile(p) then filesData[f] = HttpService:JSONDecode(readfile(p)) end
                        end)
                    end
                end
                local payload = {
                    format = "Elysera-Config",
                    version = D.VERSION or "2.5.0",
                    settings = {
                        theme = currentId,
                        uiScale = (D.getUIScale and D.getUIScale()) or Saved.uiScale,
                        reduceMotion = Saved.reduceMotion == true,
                        toggleKey = Saved.toggleKey,
                        autoExecute = Saved.autoExecute == true,
                        autoLoadSession = Saved.autoLoadSession == true,
                        fpsMode = ScreenGui:GetAttribute("FpsMode") or Saved.fpsMode,
                        toggles = Saved.toggles,
                        localCfg = Saved.localCfg,
                    },
                    files = filesData,
                }
                local ok, json = pcall(HttpService.JSONEncode, HttpService, payload)
                if not ok then
                    flashButtonFeedback(ExportBtn, "Export", "Failed", true)
                    return
                end
                if D.canFS then pcall(writefile, dataPath("Elysera_Config_Backup.json"), json) end
                local copied = UI.CopyText(json)
                CfgBox.Text = json
                flashButtonFeedback(ExportBtn, "Export", copied and "Copied!" or "Ready", false)
                showToast(copied and "Config exported to clipboard" or "Config exported to box", "success")
            end)

            ImportBtn.Activated:Connect(function()
                if isLocked() then return end
                local raw = CfgBox.Text:match("^%s*(.-)%s*$")
                if raw == "" and typeof(getclipboard) == "function" then
                    local okC, clip = pcall(getclipboard)
                    if okC and type(clip) == "string" then raw = clip:match("^%s*(.-)%s*$") end
                end
                local okDec, data = pcall(HttpService.JSONDecode, HttpService, raw)
                if not okDec or type(data) ~= "table" or data.format ~= "Elysera-Config" or type(data.settings) ~= "table" then
                    if flashStrokeError then flashStrokeError(CfgStroke) end
                    flashButtonFeedback(ImportBtn, "Import", "Invalid", true)
                    showToast("Invalid configuration JSON", "error")
                    return
                end

                local s = data.settings
                if type(s.uiScale) == "number" and D.setUIScale then D.setUIScale(s.uiScale) end
                if type(s.reduceMotion) == "boolean" then
                    if D.setReduceMotion then D.setReduceMotion(s.reduceMotion) end
                    if setReduceMotionSwitch then setReduceMotionSwitch(s.reduceMotion, true) end
                end
                if type(s.toggleKey) == "string" and D.setToggleKey then D.setToggleKey(s.toggleKey) end
                if type(s.autoLoadSession) == "boolean" then
                    Saved.autoLoadSession = s.autoLoadSession
                    if setAutoLoadSwitch then setAutoLoadSwitch(s.autoLoadSession, true) end
                end
                if type(s.autoExecute) == "boolean" and AutoExec then
                    AutoExec.set(s.autoExecute)
                    if setAutoExecSwitch then setAutoExecSwitch(AutoExec.isOn(), true) end
                end
                if type(s.localCfg) == "table" then Saved.localCfg = s.localCfg end
                if type(s.toggles) == "table" then Saved.toggles = s.toggles end
                if type(s.theme) == "string" and byId[s.theme] then applyTheme(s.theme, { animate = false }) end

                if D.canFS and type(data.files) == "table" then
                    for _, f in ipairs(EXTRA_FILES) do
                        if type(data.files[f]) == "table" then
                            pcall(function() writefile(dataPath(f), HttpService:JSONEncode(data.files[f])) end)
                        end
                    end
                end
                saveSettings()
                if refreshScaleUI then refreshScaleUI() end
                if refreshKeyUI then refreshKeyUI() end
                CfgBox.Text = ""
                flashButtonFeedback(ImportBtn, "Import", "Imported!", false)
                showToast("Configuration imported", "success")
            end)

            local resetArmedUntil = 0
            ResetCfgBtn.Activated:Connect(function()
                if isLocked() then return end
                if os.clock() >= resetArmedUntil then
                    resetArmedUntil = os.clock() + 3
                    flashButtonFeedback(ResetCfgBtn, "Reset", "Tap again", true, 3)
                    return
                end
                resetArmedUntil = 0
                if D.resetAllToggles then D.resetAllToggles() end
                if D.setUIScale then D.setUIScale(1) end
                if D.setReduceMotion then D.setReduceMotion(false) end
                if D.setToggleKey then D.setToggleKey("RightShift") end
                Saved.autoLoadSession = false
                Saved.localCfg = {}
                if setAutoLoadSwitch then setAutoLoadSwitch(false, true) end
                if setReduceMotionSwitch then setReduceMotionSwitch(false, true) end
                if D.resetLayout then D.resetLayout() end
                applyTheme(DEFAULT_ID, { animate = false })
                if refreshScaleUI then refreshScaleUI() end
                if refreshKeyUI then refreshKeyUI() end
                saveSettings()
                flashButtonFeedback(ResetCfgBtn, "Reset", "Reset!", false)
                showToast("Configuration reset to defaults", "info")
            end)
        end)

        -- Version & Check Update
        pcall(function()
            local ver = D.VERSION or Loader.version or "2.5.0"
            local VerFrame, VerLeft = CreateInfoRow(Tab, "Version")
            VerFrame.LayoutOrder = 9
            local VerStatus = label(VerLeft, {
                LayoutOrder = 2,
                Size = UDim2.new(0, 0, 1, 0),
                AutomaticSize = Enum.AutomaticSize.X,
                Text = "v" .. ver,
                TextSize = 14,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextColor3 = Theme.AccentPink,
            })
            local CheckBtn = CreateStyledButton(VerFrame, "Check Update", 104)
            local checking = false
            CheckBtn.Activated:Connect(function()
                if isLocked() or checking then return end
                if not Loader.httpGet or not Loader.bootUrl then
                    flashButtonFeedback(CheckBtn, "Check Update", "No HTTP", true)
                    return
                end
                checking = true
                flashButtonFeedback(CheckBtn, "Check Update", "Checking...", false, math.huge, Theme.SubText)
                task.spawn(function()
                    local ok, body = pcall(Loader.httpGet, Loader.bootUrl)
                    checking = false
                    if not ok or type(body) ~= "string" then
                        flashButtonFeedback(CheckBtn, "Check Update", "Failed", true)
                        showToast("Could not check for updates", "error")
                        return
                    end
                    local remoteVer = body:match('VERSION%s*=%s*"([^"]+)"')
                    if not remoteVer or remoteVer == ver then
                        VerStatus.Text = "v" .. ver .. " (Up to date)"
                        flashButtonFeedback(CheckBtn, "Check Update", "Up to date", false)
                        showToast("Elysera v" .. ver .. " is up to date", "success")
                    else
                        VerStatus.Text = "v" .. ver .. " -> v" .. remoteVer
                        VerStatus.TextColor3 = Theme.Sakura
                        flashButtonFeedback(CheckBtn, "Check Update", "v" .. remoteVer .. " out!", false, 3)
                        showToast("Update available: v" .. remoteVer, "warn", { duration = 4 })
                    end
                end)
            end)
        end)
    end)() end

    --// =====================================================================
    --// PART D. DIAGNOSTICS
    --// =====================================================================
    if UI and UI.CreateSection and CreateInfoRow and CreateStyledButton then
        local okD, errD = pcall(function()
            local Section = UI.CreateSection(Tab, "Diagnostics", 10, {
                subtitle = "Executor features and loaded modules",
                collapsed = true,
            })
            local Body = Section.Body

            local function isFn(v) return typeof(v) == "function" end

            local caps = {
                { title = "File access", affects = "Settings, scripts, cache",
                  ok = D.canFS == true },
                { title = "HTTP request", affects = "Server Hop",
                  ok = (typeof(syn) == "table" and isFn(syn.request)) or isFn(http_request) or isFn(request)
                      or (typeof(http) == "table" and isFn(http.request))
                      or (typeof(fluxus) == "table" and isFn(fluxus.request)) },
                { title = "Clipboard", affects = "Copy buttons",
                  ok = isFn(setclipboard) or isFn(toclipboard) or isFn(set_clipboard)
                      or (typeof(Clipboard) == "table" and isFn(Clipboard.set))
                      or (typeof(syn) == "table" and isFn(syn.write_clipboard)) },
                { title = "Clipboard read", affects = "Script import", ok = isFn(getclipboard) },
                { title = "loadstring", affects = "Script run", ok = isFn(loadstring) },
                { title = "Chat hook", affects = "Anti Chat",
                  ok = (isFn(hookmetamethod) and isFn(getnamecallmethod) and isFn(newcclosure))
                      or (isFn(hookfunction) and isFn(newcclosure)) },
                { title = "Notify hook", affects = "Remove Notification",
                  ok = isFn(hookfunction) and isFn(newcclosure) and isFn(checkcaller) },
                { title = "FPS cap", affects = "FPS Cap", ok = isFn(setfpscap) },
                { title = "Hidden props", affects = "FPS Profile",
                  ok = isFn(gethiddenproperty) and isFn(sethiddenproperty) },
                { title = "Queue on teleport", affects = "Auto Execute",
                  ok = isFn(queue_on_teleport) or isFn(queueonteleport)
                      or (typeof(syn) == "table" and isFn(syn.queue_on_teleport))
                      or (typeof(fluxus) == "table" and isFn(fluxus.queue_on_teleport)) },
            }

            local execName = "Unknown"
            if isFn(identifyexecutor) then
                local ok, name, ver = pcall(identifyexecutor)
                if ok and name then execName = tostring(name) .. (ver and (" " .. tostring(ver)) or "") end
            end

            local function addRow(title, affects)
                local Frame = CreateInfoRow(Body, title)
                local Left = Frame:FindFirstChild("Left")
                if Left then
                    Left.Size = UDim2.new(1, -158, 1, 0)
                    if affects then
                        label(Left, {
                            LayoutOrder = 2,
                            Size = UDim2.new(0, 0, 1, 0),
                            AutomaticSize = Enum.AutomaticSize.X,
                            Text = "· " .. affects,
                            Font = Enum.Font.Gotham,
                            TextSize = 12,
                            TextXAlignment = Enum.TextXAlignment.Left,
                            TextColor3 = Theme.SubText,
                        })
                    end
                end
                local Value = label(Frame, {
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, 0, 0.5, 0),
                    Size = UDim2.fromOffset(150, 24),
                    Text = "--",
                    TextSize = 15,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    TextColor3 = Theme.AccentPink,
                })
                return Frame, Value
            end

            local _, execValue = addRow("Executor")
            execValue.Text = execName

            for _, cap in ipairs(caps) do
                local _, value = addRow(cap.title, cap.affects)
                value.Text = cap.ok and "Yes" or "No"
                value.TextColor3 = cap.ok and Theme.AccentPink or Theme.Danger
            end

            local _, modValue = addRow("Modules", "web / cache / error")
            local function refreshModules()
                local web, cache, err = 0, 0, 0
                for _, file in ipairs(Loader.files or {}) do
                    local src = Loader.sources and Loader.sources[file]
                    if src == "web" then web = web + 1 elseif src == "cache" then cache = cache + 1 elseif src == "error" then err = err + 1 end
                end
                local parts = {}
                if web > 0 then parts[#parts + 1] = web .. " web" end
                if cache > 0 then parts[#parts + 1] = cache .. " cache" end
                if err > 0 then parts[#parts + 1] = err .. " error" end
                modValue.Text = (#parts > 0) and table.concat(parts, ", ") or "--"
                modValue.TextColor3 = (err > 0 and Theme.Danger) or (cache > 0 and Theme.AccentPurple) or Theme.AccentPink
            end
            refreshModules()
            Tab:GetPropertyChangedSignal("Visible"):Connect(function()
                if Tab.Visible then refreshModules() end
            end)

            local function buildReport()
                local out = { "Elysera diagnostics v" .. tostring(D.VERSION or "2.5.0"), "Executor: " .. execName }
                for _, cap in ipairs(caps) do
                    out[#out + 1] = cap.title .. ": " .. (cap.ok and "yes" or "no")
                end
                local src = {}
                for _, file in ipairs(Loader.files or {}) do
                    src[#src + 1] = file .. "=" .. tostring(Loader.sources and Loader.sources[file] or "?")
                end
                out[#out + 1] = "Modules (" .. tostring(Loader.ref or "?") .. "): " .. table.concat(src, ", ")
                out[#out + 1] = "GUI root: " .. GuiRoot.Name
                out[#out + 1] = "PlaceId: " .. tostring(game.PlaceId)
                return table.concat(out, "\n")
            end

            local CopyFrame = CreateInfoRow(Body, "Copy report")
            local CopyBtn = CreateStyledButton(CopyFrame, "Copy", 70)
            CopyBtn.MouseButton1Click:Connect(function()
                if isLocked() then return end
                local ok = UI.CopyText(buildReport())
                flashButtonFeedback(CopyBtn, "Copy", ok and "Copied" or "Failed", not ok)
            end)

            if requestClose then
                local UnloadFrame = CreateInfoRow(Body, "Unload Elysera")
                local UnloadLeft = UnloadFrame:FindFirstChild("Left")
                if UnloadLeft then
                    label(UnloadLeft, {
                        LayoutOrder = 2,
                        Size = UDim2.new(0, 0, 1, 0),
                        AutomaticSize = Enum.AutomaticSize.X,
                        Text = "· also turns Auto Execute off",
                        Font = Enum.Font.Gotham,
                        TextSize = 12,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextColor3 = Theme.SubText,
                    })
                end
                local UnloadBtn = CreateStyledButton(UnloadFrame, "Unload", 80)
                UnloadBtn.TextColor3 = Theme.Danger
                UnloadBtn.MouseButton1Click:Connect(function()
                    if isLocked() then return end
                    requestClose()
                end)
            end
        end)
        if not okD then warn("[Elysera/Settings] Could not build Diagnostics: " .. tostring(errD)) end
    end

    ScreenGui.Destroying:Connect(function() closeList(true) end)

    local metaList = {}
    for i, t in ipairs(THEMES) do
        local colors = {}
        for k, v in pairs(t.colors) do colors[k] = v end
        metaList[i] = { id = t.id, name = t.name, mode = t.mode, colors = colors }
    end

    return {
        Themes         = metaList,
        SetTheme       = function(id) return applyTheme(id, { animate = true }) end,
        GetTheme       = function() local e = byId[currentId] return e.id, e.name end,
        OnThemeChanged = onChanged,
        Stats          = stats,
        isListOpen     = function() return listOpen end,
        hideList       = function() closeList(true) end,
    }
end
