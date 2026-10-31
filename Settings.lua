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
--//  Features (A split out of MainLocal.lua, B merged from Theme.lua, C and D added later, E - H added after that):
--//    A) Anti Chat     switch that blocks sending chat messages (LayoutOrder = 1)
--//    C) Auto Execute  switch that reloads Elysera after a teleport (LayoutOrder = 2; the mechanism lives in the core: ctx.AutoExecute)
--//    E) Restore last session   switch: switches that were on come back on after a server change (LayoutOrder = 3; ctx.Session)
--//    B) Theme         "Theme" row + dropdown list to change the color palette (LayoutOrder = 4)
--//    F) Interface     UI Scale, Reduce Motion, Menu Key (LayoutOrder = 5; the state lives in the core: ctx.UIScale / ctx.Motion / ctx.MenuKey)
--//    G) Config        Export / Import / Reset of the settings (LayoutOrder = 6; the file is written by the core: ctx.Config)
--//    D) Diagnostics   which APIs the executor supports, where each module was loaded from, Copy report, Unload (LayoutOrder = 7)
--//    H) About         version, update check and Reload (LayoutOrder = 8; needs ctx.Loader.version / urls / texts / download, ctx.reloadUI)
--//
--//  E - H need a newer core (MainWeb.lua with ctx.Session, ctx.UIScale, ctx.Motion, ctx.MenuKey, ctx.Config, ctx.Toast, ctx.reloadUI).
--//  With an older core the matching rows are simply not built and everything else works as before.
--//
--//  Put this file next to the other modules (Script.lua, Status_Server.lua, Local.lua, FPS.lua).
--//  MainLocal.lua loads it with readModule("Settings.lua") + init({...}) at the END (after the FPS TAB), so the first theme
--//  application (the saved theme) also covers the tabs above. The old Theme.lua was merged into this file and is no longer loaded separately.
--//
--//  How Theme works (option C in the report, the UI is not rebuilt):
--//    1) Build a mapping table  "current Theme color" -> "new theme color"  for every token.
--//    2) Write the new colors into the Theme table IN PLACE (the same reference the modules are holding).
--//    3) Settle the color tweens that are still running, then sweep the ElyseraUI tree and replace the color properties that match exactly
--//       (including every UIGradient keypoint).
--//    4) Run the core's refreshStateColors() (selected tab, switches, Resize mode...).
--//    5) Set the "Theme" Attribute on the ScreenGui, save the settings, call the onChanged listeners.
--//
--//  Theme API (returned by init, MainLocal.lua assigns it to ThemeAPI):
--//    Themes                 list of { id, name, mode, colors }
--//    SetTheme(id)           -> true | false, error
--//    GetTheme()             -> id, name
--//    OnThemeChanged(fn)     fn(id, Theme, entry); returns the unsubscribe function
--//    Stats                  { scanned, changed, ms } of the most recent remap
--//    isListOpen(), hideList()  reserved for the core (closeUI closes the list that is open)
--//
--//  Convention: an Instance with the Attribute NoTheme = true (the whole subtree) is skipped by the remap.
--//  Palette rules: all 13 tokens present; the 12 tokens (except ToggleKnobOn) differ from each other pairwise and
--//  are not #FFFFFF / #000000 (white is the base of gradient frames, black is the overlay).
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
    local Saved        = D.Saved or {}
    local saveSettings = D.saveSettings or function() end

    local new, corner, stroke, padding = D.new, D.corner, D.stroke, D.padding
    local list, label, tween, pressScale = D.list, D.label, D.tween, D.pressScale
    local CreateToggleOption = D.CreateToggleOption
    local CreateInfoRow, CreateStyledButton = D.CreateInfoRow, D.CreateStyledButton
    local flashButtonFeedback = D.flashButtonFeedback
    local UI, Loader, AutoExec = D.UI, D.Loader or {}, D.AutoExecute
    local requestClose = D.requestClose

    -- Optional services of a newer core (see the header): every feature that needs one is skipped when it is missing
    local Session, UIScaleApi, MotionApi, MenuKeyApi, Config = D.Session, D.UIScale, D.Motion, D.MenuKey, D.Config
    local function toast(message, kind, opts) -- shared toast (ctx.Toast)
        if type(D.Toast) ~= "function" then return end
        local ok, err = pcall(D.Toast, message, kind, opts)
        if not ok then warn("[Elysera/Settings] Toast failed: " .. tostring(err)) end
    end

    local EASE_QUAD, EASE_BACK = D.EASE_QUAD, D.EASE_BACK
    local DIR_IN, DIR_OUT      = D.DIR_IN, D.DIR_OUT
    local ANCHOR_CENTER        = D.ANCHOR_CENTER

    local isOpen, isLocked, setLocked = D.isOpen, D.isLocked, D.setLocked
    local fadeMainUI                  = D.fadeMainUI
    local refreshStateColors          = D.refreshStateColors or function() end

    --// =====================================================================
    --// PART A. ANTI CHAT  (split out of MainLocal.lua)
    --// =====================================================================
    do
        local function setProp(inst, prop, value)
            pcall(function() inst[prop] = value end)
        end

        --// ---------- Anti Chat ----------
        local TextChatService = game:GetService("TextChatService")

        local AntiChatSwitch, setAntiChat, antiChatApi = CreateToggleOption(Tab, "Anti Chat")
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
                    local oldFire
                    oldFire = hookfunction(Instance.new("RemoteEvent").FireServer, newcclosure(function(self, ...)
                        if antiChatOn and isChatCall(self, "FireServer") then return end
                        return oldFire(self, ...)
                    end))
                    chatHooked = true
                end)
                pcall(function()
                    local oldSend
                    oldSend = hookfunction(Instance.new("TextChannel").SendAsync, newcclosure(function(self, ...)
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

        -- "Restore last session": every change is remembered, and the switch comes back ON after a server change.
        -- (set after the handler above exists, so turning it on here really starts Anti Chat)
        if Session and antiChatApi then
            antiChatApi.onChanged(function(on) pcall(Session.set, "settings.antiChat", on) end)
            local okGet, wanted = pcall(Session.get, "settings.antiChat")
            if okGet and wanted == true then setAntiChat(true) end
        end

        --// ---------- Cleanup ----------
        ScreenGui.Destroying:Connect(function()
            disableAntiChat()
        end)
    end

    --// =====================================================================
    --// PART B. THEME  (merged from Theme.lua)
    --// =====================================================================
    local V2          = Vector2.new
    local TextService = game:GetService("TextService")

    local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

    --// ================= CONFIG =================
    local DEFAULT_ID  = "sakura"
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

    -- Token names are kept so the modules need no changes. AccentPink / AccentPurple / Sakura are only
    -- "roles": primary accent / secondary accent / accent text, not necessarily pink or purple.
    local RAW = {
        -- 1. Elysera Sakura: neon purple and sakura pink (default, = the core's current Theme table)
        { id = "sakura", name = "Elysera Sakura", mode = "dark", snapshot = true },
        -- 2. Midnight Ocean: deep navy blue, cyan/azure accents
        { id = "ocean", name = "Midnight Ocean", mode = "dark", colors = {
            Background = "0D1D2F", Panel = "0E1F33", PanelAlt = "10243B", Header = "122A45", Border = "1F4775",
            AccentPink = "2FB9F7", AccentPurple = "4F7DFF", Sakura = "A8E9FF", Text = "D3E8FA", SubText = "8FB2D6",
            Danger = "FF6F8A", ToggleTrackOff = "1C3F68", ToggleKnobOn = "FFFFFF",
        } },
        -- 3. Emerald Forest: dark forest green, emerald accents; dark ON knob
        { id = "emerald", name = "Emerald Forest", mode = "dark", colors = {
            Background = "11261D", Panel = "132920", PanelAlt = "153025", Header = "19382B", Border = "2B5F49",
            AccentPink = "34D399", AccentPurple = "7BD66B", Sakura = "C6F8E0", Text = "D6F3E4", SubText = "8FBCA6",
            Danger = "FF7B7B", ToggleTrackOff = "265441", ToggleKnobOn = "07140D",
        } },
        -- 4. Crimson Ember: glowing-coal red, vermilion accents
        { id = "crimson", name = "Crimson Ember", mode = "dark", colors = {
            Background = "261013", Panel = "2A1115", PanelAlt = "301318", Header = "38171D", Border = "5F2730",
            AccentPink = "FF6B4A", AccentPurple = "E8334F", Sakura = "FFC9B8", Text = "F6DAD3", SubText = "C79A93",
            Danger = "FF5C8A", ToggleTrackOff = "54222B", ToggleKnobOn = "FFFFFF",
        } },
        -- 5. Golden Sunset: amber brown, gold–orange accents; dark ON knob
        { id = "sunset", name = "Golden Sunset", mode = "dark", colors = {
            Background = "261A0F", Panel = "291C10", PanelAlt = "2F2112", Header = "382716", Border = "5E4124",
            AccentPink = "FFB020", AccentPurple = "FF7A33", Sakura = "FFE0A3", Text = "F4E5CD", SubText = "C2A783",
            Danger = "FF5D5D", ToggleTrackOff = "533A20", ToggleKnobOn = "1A130C",
        } },
        -- 6. Coral Lagoon: dark teal, coral accents
        { id = "lagoon", name = "Coral Lagoon", mode = "dark", colors = {
            Background = "0F272B", Panel = "102A2F", PanelAlt = "133036", Header = "16393F", Border = "26606B",
            AccentPink = "FF7F8A", AccentPurple = "FFA06B", Sakura = "FFDDD2", Text = "D5EEEE", SubText = "8FBDBF",
            Danger = "FF5470", ToggleTrackOff = "21555F", ToggleKnobOn = "FFFFFF",
        } },
        -- 7. Arctic Frost: cold blue-gray, pale ice accents; dark ON knob
        { id = "arctic", name = "Arctic Frost", mode = "dark", colors = {
            Background = "1B222A", Panel = "1D242E", PanelAlt = "222A35", Header = "28313E", Border = "435369",
            AccentPink = "8BD3F0", AccentPurple = "7C9CFF", Sakura = "D4F0FB", Text = "E1E9F2", SubText = "9DAEC4",
            Danger = "F2788C", ToggleTrackOff = "3B4A5D", ToggleKnobOn = "0F151D",
        } },
        -- 8. Carbon Mono: monochrome graphite and silver; dark ON knob
        { id = "carbon", name = "Carbon Mono", mode = "dark", colors = {
            Background = "212123", Panel = "232325", PanelAlt = "29292B", Header = "303033", Border = "515156",
            AccentPink = "E4E4E4", AccentPurple = "A0A0A0", Sakura = "F5F5F5", Text = "D6D6D6", SubText = "A3A3A3",
            Danger = "FF6B7A", ToggleTrackOff = "47474C", ToggleKnobOn = "121212",
        } },
        -- 9. Neon Matrix: near black, terminal-style neon green; dark ON knob
        { id = "matrix", name = "Neon Matrix", mode = "dark", colors = {
            Background = "09150D", Panel = "0A170E", PanelAlt = "0C1A11", Header = "0E1F14", Border = "2A5A40",
            AccentPink = "1AFF9C", AccentPurple = "19D3FF", Sakura = "B6FFE0", Text = "CFF7E2", SubText = "7FBF9F",
            Danger = "FF5577", ToggleTrackOff = "1F4A30", ToggleKnobOn = "03110A",
        } },
        -- 10. Porcelain Day: lavender white, pink–violet accents (the first light theme)
        { id = "porcelain", name = "Porcelain Day", mode = "light", colors = {
            Background = "F5F1FB", Panel = "FBF9FE", PanelAlt = "ECE6F7", Header = "DFD5F1", Border = "B9A7DB",
            AccentPink = "C0267A", AccentPurple = "9A74F8", Sakura = "8E0F50", Text = "2D1B4E", SubText = "65558A",
            Danger = "BE1F43", ToggleTrackOff = "CDC1E4", ToggleKnobOn = "FFFFFF",
        } },
        -- ===== Additional themes (11-22): 7 dark + 5 light, modern color combinations =====
        -- 11. Aurora Veil: deep indigo black, mint → aurora purple accents; dark ON knob
        { id = "aurora", name = "Aurora Veil", mode = "dark", colors = {
            Background = "0D0E1E", Panel = "0F1022", PanelAlt = "121329", Header = "191B3B", Border = "323776",
            AccentPink = "4DF0C2", AccentPurple = "8F7CFF", Sakura = "C9FFEF", Text = "E3E9FF", SubText = "9BA7D8",
            Danger = "FF6F91", ToggleTrackOff = "292D60", ToggleKnobOn = "08101C",
        } },
        -- 12. Cyber Neon: purple black, magenta + electric cyan accents, lime-yellow selected text; dark ON knob
        { id = "cyber", name = "Cyber Neon", mode = "dark", colors = {
            Background = "0E091D", Panel = "100A21", PanelAlt = "140D29", Header = "1D133C", Border = "3E2880",
            AccentPink = "FF2E97", AccentPurple = "00E5FF", Sakura = "FFE45E", Text = "EFE9FF", SubText = "A99BD6",
            Danger = "FF5A36", ToggleTrackOff = "35226D", ToggleKnobOn = "0B0716",
        } },
        -- 13. Royal Gold: royal indigo, gold + coral-orange accents; dark ON knob
        { id = "royal", name = "Royal Gold", mode = "dark", colors = {
            Background = "101023", Panel = "111227", PanelAlt = "15152E", Header = "1C1E3F", Border = "343674",
            AccentPink = "F5C451", AccentPurple = "F08A5D", Sakura = "FFE8A8", Text = "ECEBFA", SubText = "A7A6CF",
            Danger = "FF6B7D", ToggleTrackOff = "2B2C5F", ToggleKnobOn = "100E1F",
        } },
        -- 14. Obsidian OLED: near pure black (suits OLED screens), electric blue + UV purple accents
        { id = "oled", name = "Obsidian OLED", mode = "dark", colors = {
            Background = "07080B", Panel = "0A0C10", PanelAlt = "0E1117", Header = "161B25", Border = "34405A",
            AccentPink = "4C8DFF", AccentPurple = "A15CFF", Sakura = "C4DAFF", Text = "E6ECF7", SubText = "97A3BA",
            Danger = "FF5E7A", ToggleTrackOff = "2A3348", ToggleKnobOn = "FFFFFF",
        } },
        -- 15. Matcha Moss: dark olive moss, matcha green + leaf green accents; dark ON knob
        { id = "matcha", name = "Matcha Moss", mode = "dark", colors = {
            Background = "14180F", Panel = "171B10", PanelAlt = "1C2114", Header = "2A311E", Border = "4C5936",
            AccentPink = "B8E04A", AccentPurple = "6FCB7A", Sakura = "E4F7B0", Text = "E6EBD6", SubText = "A2AE8A",
            Danger = "FF7B63", ToggleTrackOff = "3E492D", ToggleKnobOn = "0D1108",
        } },
        -- 16. Rose Gold Noir: warm charcoal, rose gold + mauve accents; dark ON knob
        { id = "rosegold", name = "Rose Gold Noir", mode = "dark", colors = {
            Background = "1E1715", Panel = "211917", PanelAlt = "271E1B", Header = "362926", Border = "5A453F",
            AccentPink = "E9A68C", AccentPurple = "C98BA0", Sakura = "FFD9C9", Text = "F3E3DD", SubText = "BE9F98",
            Danger = "F0605D", ToggleTrackOff = "4B3A34", ToggleKnobOn = "1A0F0D",
        } },
        -- 17. Dusk Pastel: dusk purple-gray, pastel pink + sky blue accents; dark ON knob
        { id = "dusk", name = "Dusk Pastel", mode = "dark", colors = {
            Background = "1D1D2B", Panel = "1F1F2E", PanelAlt = "232334", Header = "2D2D43", Border = "4B4B71",
            AccentPink = "F2A7C8", AccentPurple = "8DB8FF", Sakura = "FFD6E8", Text = "E4E6F8", SubText = "A9ADCF",
            Danger = "FF8A8A", ToggleTrackOff = "3F3F5F", ToggleKnobOn = "15162A",
        } },
        -- 18. Latte Cream: warm milk cream, caramel + coffee accents (light theme)
        { id = "latte", name = "Latte Cream", mode = "light", colors = {
            Background = "F6F1E9", Panel = "FBF8F4", PanelAlt = "F2E9DE", Header = "EADDCC", Border = "C6AC8B",
            AccentPink = "A4561C", AccentPurple = "B8742A", Sakura = "5E2F0E", Text = "3A2618", SubText = "75604C",
            Danger = "B3261E", ToggleTrackOff = "D7C5AD", ToggleKnobOn = "FFFFFF",
        } },
        -- 19. Mint Breeze: mint white, jade + turquoise accents (light theme)
        { id = "mint", name = "Mint Breeze", mode = "light", colors = {
            Background = "EDF7F3", Panel = "F8FCFA", PanelAlt = "E3F2EC", Header = "D1EAE0", Border = "9CC9B6",
            AccentPink = "0A7F62", AccentPurple = "119A88", Sakura = "07533F", Text = "12302A", SubText = "4B6B60",
            Danger = "C0304B", ToggleTrackOff = "C3DFD3", ToggleKnobOn = "FFFFFF",
        } },
        -- 20. Sky Cloud: sky white, azure blue accents (light theme)
        { id = "sky", name = "Sky Cloud", mode = "light", colors = {
            Background = "EBF2F9", Panel = "F7FAFD", PanelAlt = "DFE9F6", Header = "CBDCF0", Border = "9FBADB",
            AccentPink = "1B66E3", AccentPurple = "4F7DF0", Sakura = "0B3A8A", Text = "112440", SubText = "4A6286",
            Danger = "C4283F", ToggleTrackOff = "C4D4E9", ToggleKnobOn = "FFFFFF",
        } },
        -- 21. Rose Quartz: pinkish white, raspberry accents (light theme)
        { id = "quartz", name = "Rose Quartz", mode = "light", colors = {
            Background = "FAEFF2", Panel = "FEFBFC", PanelAlt = "F6E4E9", Header = "F0D0D8", Border = "DAA9B6",
            AccentPink = "C2255C", AccentPurple = "E0558A", Sakura = "7D1237", Text = "3A1220", SubText = "7A4A5B",
            Danger = "C2410C", ToggleTrackOff = "E8C9D1", ToggleKnobOn = "FFFFFF",
        } },
        -- 22. Paper Ink: neutral paper, graphite ink accents (monochrome light theme)
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

    -- integer key of a color: r*65536 + g*256 + b (every channel rounded to 0..255)
    local function colorKey(c)
        return math.floor(c.R * 255 + 0.5) * 65536
            + math.floor(c.G * 255 + 0.5) * 256
            + math.floor(c.B * 255 + 0.5)
    end

    -- Q1 + Q2 + Q3: all 13 Color3 tokens present; the 12 tokens differ from each other; no token (except ToggleKnobOn) is white/black
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

    -- Theme 1 (sakura) is taken from a snapshot of the core's current Theme table -> identical to the original
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

    local THEMES = buildThemes()
    local byId = {}
    for _, t in ipairs(THEMES) do byId[t.id] = t end
    assert(byId[DEFAULT_ID], "Settings.lua: missing default theme '" .. DEFAULT_ID .. "'")

    -- "Heal old colors" index: the color key of EVERY theme -> token name, ambiguous keys dropped (same color but a different role).
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
    local currentId = DEFAULT_ID -- the core builds the UI with the default palette
    local applying, pendingId, pendingOpts = false, nil, nil
    local stats = { scanned = 0, changed = 0, ms = 0 }

    -- UI functions declared ahead (assigned in part 3); no-op versions so the engine can run before the UI is built
    local function noop() end
    local closeList, refreshItems, updateWinbox = noop, noop, noop
    local applyTheme

    -- Lock the UI with a counter, remembering the previous lock state (for example Resize mode being on)
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

    -- Listener
    local listeners = {}
    local function onChanged(fn)
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

    -- OLD color key (exactly what the Instances hold = the current value of the Theme table) -> NEW Color3
    local function buildColorMap(from, to)
        local map = {}
        for _, k in ipairs(TOKENS) do
            if k ~= KNOB then map[colorKey(from[k])] = to[k] end
        end
        return map
    end

    -- Returns the lookup function: Color3 -> new Color3 | nil (keep as is).
    -- A color that is not a token (white, black, a Lerp color, a hard-coded one) -> nil.
    -- HEAL: a color that matches a token of ANOTHER theme (left over because a closure kept the old color) is also moved to its proper role
    -- in the new theme; ambiguous keys were dropped in buildHealIndex.
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

    -- Replace every keypoint of a ColorSequence; returns the new ColorSequence, or nil if nothing changed
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

    -- Color properties to check per ClassName
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

    -- walk the tree, skipping every branch that has the NoTheme Attribute
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

    -- Elysera's own extra ScreenGuis outside the main ScreenGui: the White/Black Screen cover and the FPS Overlay
    local EXTRA_ROOTS = { "ElyseraCover", "ElyseraFpsOverlay" }

    local function getRoots()
        local roots = { ScreenGui }
        local containers = { GuiRoot }
        if CoreGui and CoreGui ~= GuiRoot then containers[#containers + 1] = CoreGui end
        for _, container in ipairs(containers) do
            for _, name in ipairs(EXTRA_ROOTS) do
                local gui = container:FindFirstChild(name)
                if gui then roots[#roots + 1] = gui end
            end
        end
        return roots
    end

    -- Actually apply the theme: map -> write the Theme table -> sweep -> hook -> save -> signal
    local function commit(entry, opts)
        local t0 = os.clock()
        local lookup = makeLookup(buildColorMap(Theme, entry.colors), entry.colors)

        -- Write the Theme table BEFORE sweeping: hover/tweens that start meanwhile already use the new colors
        for _, k in ipairs(TOKENS) do Theme[k] = entry.colors[k] end
        currentId = entry.id

        -- a color tween that is still running would pull the property back to the OLD color when it ends: cancel it and snap to the target color translated to the new theme
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

    -- opts: animate (default true, only effective while the UI is visible), noSave, force
    function applyTheme(id, opts)
        opts = opts or {}
        local entry = byId[id]
        if not entry then return false, "Theme does not exist: " .. tostring(id) end

        if applying then -- the next pick is accepted when the previous one is done
            pendingId, pendingOpts = id, opts
            return true
        end
        if id == currentId and not opts.force then return true end

        local animate = opts.animate ~= false and isOpen() and MainUI.Visible
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
        hold() -- keep the UI locked during the whole effect so no action can slip in between
        task.spawn(function()
            -- every step is wrapped in its own pcall: wherever an error happens we must still reach release(), otherwise the UI would stay locked forever
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

    -- line segment with round caps, same technique as the core's Icons / svgStroke
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

    -- press: shrink slightly. The core's pressScale is not used because it is skipped while the UI is locked,
    -- and the list is always open while the UI is locked
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
    local listOpen, listToken = false, 0
    local lastRight, lastTop, lastFlip, lastW, lastH = 0, 0, false, 0, 0

    local DOTS_W  = 4 * 10 + 3 * 3   -- 4 dots of 10px, 3px gaps
    local DOTS_X  = 12
    local NAME_X  = DOTS_X + DOTS_W + 9
    local RIGHT_Z = 28               -- area of the ✓ mark on the right of every item

    function updateWinbox()
        if not Winbox then return end
        local entry = byId[currentId]
        WinLabel.Text = entry.name
        -- text width + 20 + arrow zone; grows toward the left because the winbox is anchored to the right edge
        local w = clamp(math.ceil(measure(entry.name, 13)) + 20 + ARROW_ZONE, WIN_MIN_W, WIN_MAX_W)
        local zoom = (UIScaleApi and tonumber(UIScaleApi.get())) or 1 -- the row lives in the zoomed body: AbsoluteSize is in screen pixels
        local rowW = Row.AbsoluteSize.X / (zoom > 0 and zoom or 1)
        if rowW > 0 then -- smallest UI: leave room for the title (14 + text), a gap of 8, and a right margin of 12
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

    -- Asks the core to repaint the visible tab (see repaintContent in MainWeb.lua). Optional, so the module still runs with an older core.
    local function repaintTab()
        local fn = D.repaintContent
        if fn then fn() end
    end

    -- List position: the top edge is 6px below the bottom of the row, the right edge lines up with the row's right edge (opens toward the left).
    -- At most 6 items tall, or the space left in the window minus an 8px margin; when there is not enough room (< 3 items), use the side with more room.
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

        ListScrollPad.PaddingRight = UDim.new(0, fullH > h and 6 or 0) -- leave room for the scrollbar
        lastRight, lastTop, lastFlip = rp.X + rs.X, top, flip
        lastW, lastH = math.min(listW, rs.X), h
    end

    -- Put the list at its final rectangle. The list is a plain Frame, not a CanvasGroup: a CanvasGroup nested inside the
    -- MainUI CanvasGroup made the engine drop the cached render of the tab behind it, which hid every function in the
    -- panel until the next touch. The items keep their final size and are only revealed by the clipping of the growing frame.
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

        -- unfold: the frame grows from zero height to its final height while its background fades in
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
        repaintTab() -- an overlay just appeared: make sure the panel behind it stays painted
    end

    function closeList(instant)
        if not listOpen then return end
        listOpen = false
        listToken = listToken + 1
        local token = listToken
        release() -- release the UI lock
        Catcher.Visible = false
        setArrow(false)

        if instant then
            List.Visible = false
            repaintTab()
            return
        end
        -- fold: the frame shrinks back to zero height while its background fades out
        local t = tween(List, LIST_CLOSE_T, {
            Size = UDim2.fromOffset(lastW, 0),
            BackgroundTransparency = 1,
        }, EASE_QUAD, DIR_IN)
        tween(ListStroke, LIST_CLOSE_T, { Transparency = 1 }, EASE_QUAD, DIR_IN)
        t.Completed:Connect(function(state)
            if state == Enum.PlaybackState.Completed and token == listToken then
                List.Visible = false
                repaintTab() -- the overlay is gone: make sure the panel is painted again
            end
        end)
    end

    local function pick(id)
        if id == currentId then
            closeList(false) -- the current item was picked again: just close
        else
            applyTheme(id, { animate = true }) -- closes the list by itself, then fade -> remap -> fade back in
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

        -- accent bar on the left for the selected item (same visual language as the TabPill)
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

        -- strip of 4 preview dots: FIXED colors of that very theme -> tagged NoTheme so the remap skips the whole branch
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
            if key == "Background" then stroke(dot, c.Border, 1) end -- the background dot needs a border to be visible
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

        -- the ✓ mark is drawn with 2 line segments (independent of whether the font has a ✓ glyph)
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
        -- touch catcher: transparent, covers the whole MainUI, blocks every action behind it; touching it closes the list
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

        -- wide enough that the longest name is not cut off, but never wider than the row (see positionList)
        local widest = 0
        for _, t in ipairs(THEMES) do widest = math.max(widest, measure(t.name, 13)) end
        listW = math.max(LIST_MIN_W, math.ceil(widest) + NAME_X + RIGHT_Z + LIST_PAD * 2 + 8)

        List = new("Frame", {
            Name = "ThemeList",
            Visible = false,
            Active = true, -- touching an empty spot in the list is not swallowed by the touch catcher
            ClipsDescendants = true, -- the unfold animation reveals the items by clipping
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

        -- the window changed size while the list is open -> reposition
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
            LayoutOrder = 4, -- below Anti Chat (1), Auto Execute (2) and Restore last session (3); Interface is 5
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

        -- winbox: shows the selected theme, anchored to the right edge
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
        -- TextButton: the default Contextual mode would outline the TEXT (and the Text is empty, so the border would vanish), so the frame border must be forced
        stroke(Winbox, Theme.Border, 1).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        pressScale(Winbox, 0.97)

        -- theme name centered across the whole winbox width; 20px padding on both sides so it never touches the arrow
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

        -- arrow: 2 line segments rotated ±45°, rotated 180° + switched to Sakura while the list is open
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
    -- Saved theme: apply it RIGHT AWAY (no effect, the UI is not visible yet) before building the Theme row,
    -- so the user sees no color flash and the Theme row is built with the new colors from the start
    local savedId = Saved.theme
    if type(savedId) == "string" and savedId ~= currentId and byId[savedId] then
        local ok, err = pcall(applyTheme, savedId, { animate = false, noSave = true })
        if not ok then warn("[Elysera/Theme] Could not apply the saved theme: " .. tostring(err)) end
    end
    ScreenGui:SetAttribute("Theme", currentId) -- an invalid saved id gets overwritten by the id in use

    local okUI, errUI = pcall(function()
        createList()
        createThemeRow()
        refreshItems()
    end)
    if not okUI then warn("[Elysera/Theme] Could not build the Theme row: " .. tostring(errUI)) end

    --// =====================================================================
    --// PART C. AUTO EXECUTE  (the mechanism lives in the core: ctx.AutoExecute; only the switch is built here)
    --// =====================================================================
    if AutoExec and CreateToggleOption then
        local okC, errC = pcall(function()
            local reason = AutoExec.reason()
            local startOn = AutoExec.isOn() and reason == nil
            local Switch, setState, toggleApi = CreateToggleOption(Tab, "Auto Execute", 56, { initial = startOn })
            local Row = Switch.Parent
            Row.LayoutOrder = 2

            -- title + subtitle line (the row is 56 tall to hold 2 lines)
            for _, child in ipairs(Row:GetChildren()) do
                if child:IsA("TextLabel") and child.Text == "Auto Execute" then
                    child.Position = UDim2.fromOffset(14, 8)
                    child.Size = UDim2.new(1, -80, 0, 22)
                end
            end
            local Sub = label(Row, {
                Position = UDim2.fromOffset(14, 31),
                Size = UDim2.new(1, -80, 0, 16),
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextColor3 = Theme.SubText,
                Text = "",
            })
            local function showReason(why)
                if why then
                    Sub.Text = "Not supported: " .. why
                    Sub.TextColor3 = Theme.Danger
                else
                    Sub.Text = "Reload Elysera after teleport (Server Hop, Rejoin)"
                    Sub.TextColor3 = Theme.SubText
                end
            end
            showReason(reason)

            toggleApi.onChanged(function(on)
                local ok, why = AutoExec.set(on)
                if on and not ok then
                    showReason(why)
                    task.defer(setState, false, true) -- put the switch back to OFF (silent: does not call this function again)
                end
            end)
        end)
        if not okC then warn("[Elysera/Settings] Could not build Auto Execute: " .. tostring(errC)) end
    end

    --// =====================================================================
    --// PART D. DIAGNOSTICS  (which APIs the executor supports, where each module was loaded from, Copy report, Unload)
    --// =====================================================================
    if UI and UI.CreateSection and CreateInfoRow and CreateStyledButton then
        local okD, errD = pcall(function()
            local Section = UI.CreateSection(Tab, "Diagnostics", 7, {
                subtitle = "Executor features and loaded modules",
                collapsed = true,
            })
            local Body = Section.Body

            local function isFn(v) return typeof(v) == "function" end

            -- This list matches exactly how each feature probes for APIs (see Status_Server / FPS / Anti Chat above)
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

            -- Row: title (+ "· affected part" in the secondary color) on the left, value on the right
            local function addRow(title, affects)
                local Frame = CreateInfoRow(Body, title)
                local Left = Frame:FindFirstChild("Left")
                if Left then
                    Left.Size = UDim2.new(1, -158, 1, 0) -- Value takes 150px on the right
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

            -- Where each module was loaded from (web = fresh download, cache = copy saved from the most recent good run, error = could not be loaded)
            local _, modValue = addRow("Modules", "web / cache / error")
            local function refreshModules()
                local web, cache, err = 0, 0, 0
                for _, file in ipairs(Loader.files or {}) do
                    local src = Loader.sources and Loader.sources[file]
                    if src == "web" then web += 1 elseif src == "cache" then cache += 1 elseif src == "error" then err += 1 end
                end
                local parts = {}
                if web > 0 then parts[#parts + 1] = web .. " web" end
                if cache > 0 then parts[#parts + 1] = cache .. " cache" end
                if err > 0 then parts[#parts + 1] = err .. " error" end
                modValue.Text = (#parts > 0) and table.concat(parts, ", ") or "--"
                modValue.TextColor3 = (err > 0 and Theme.Danger) or (cache > 0 and Theme.AccentPurple) or Theme.AccentPink
            end
            refreshModules()
            -- Settings is loaded last, so it does not count itself yet when built: update again when the tab opens
            Tab:GetPropertyChangedSignal("Visible"):Connect(function()
                if Tab.Visible then refreshModules() end
            end)

            -- Report to send when support is needed (contains no JobId / UserId)
            local function buildReport()
                local out = { "Elysera diagnostics", "Executor: " .. execName }
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
                    requestClose() -- same "Close script" dialog as the close button in the top bar
                end)
            end
        end)
        if not okD then warn("[Elysera/Settings] Could not build Diagnostics: " .. tostring(errD)) end
    end

    --// =====================================================================
    --// PARTS E - H need a newer core (ctx.Session / UIScale / Motion / MenuKey / Config / Toast / reloadUI / Loader.*).
    --// Every part is built inside its own pcall and only when its service exists, so an older core keeps everything above working.
    --// =====================================================================
    do
        local HttpService      = D.HttpService or game:GetService("HttpService")
        local UserInputService = game:GetService("UserInputService")
        local CreateCard       = D.CreateCard
        local bindBoxFocus     = D.bindBoxFocus
        local flashStrokeError = D.flashStrokeError

        --// ---------- helpers: rows that the core's UI kit does not have ----------
        -- A row with a title and a small second line. `reserve` = width kept free on the right for the buttons.
        local function CreateTwoLineRow(parent, title, subtitle, order, reserve)
            local Frame = new("Frame", {
                LayoutOrder = order or 0,
                Size = UDim2.new(1, 0, 0, 56),
                BackgroundColor3 = Theme.Panel,
                BorderSizePixel = 0,
                ClipsDescendants = true,
            }, parent)
            corner(Frame, 8)
            stroke(Frame)
            padding(Frame, 0, 12) -- right margin for the buttons; the texts below use explicit offsets

            local Title = label(Frame, {
                Position = UDim2.fromOffset(14, 8),
                Size = UDim2.new(1, -(reserve + 22), 0, 22),
                Text = title,
                TextSize = 15,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextColor3 = Theme.Text,
            })
            local Sub = label(Frame, {
                Position = UDim2.fromOffset(14, 31),
                Size = UDim2.new(1, -(reserve + 22), 0, 16),
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextColor3 = Theme.SubText,
                Text = subtitle,
            })
            return Frame, Title, Sub
        end

        -- A switch row with a second line of small text (same layout as Auto Execute). Returns Switch, setState, api, Sub
        local function CreateSubtitleToggle(parent, title, subtitle, order, opts)
            local Switch, setState, api = CreateToggleOption(parent, title, 56, opts)
            local Row = Switch.Parent
            Row.LayoutOrder = order
            for _, child in ipairs(Row:GetChildren()) do
                if child:IsA("TextLabel") and child.Text == title then
                    child.Position = UDim2.fromOffset(14, 8)
                    child.Size = UDim2.new(1, -80, 0, 22)
                end
            end
            local Sub = label(Row, {
                Position = UDim2.fromOffset(14, 31),
                Size = UDim2.new(1, -80, 0, 16),
                Font = Enum.Font.Gotham,
                TextSize = 11,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextColor3 = Theme.SubText,
                Text = subtitle,
            })
            return Switch, setState, api, Sub
        end

        -- A one-line row: the title (+ an optional note in the secondary color) on the left, a value on the right.
        -- Same look as the Diagnostics rows. Returns Frame, Value, Note
        local function addValueRow(parent, title, note, order)
            local Frame = CreateInfoRow(parent, title)
            Frame.LayoutOrder = order or 0
            local Left = Frame:FindFirstChild("Left")
            local Note
            if Left then
                Left.Size = UDim2.new(1, -158, 1, 0) -- the value takes 150px on the right
                if note then
                    Note = label(Left, {
                        LayoutOrder = 2,
                        Size = UDim2.new(0, 0, 1, 0),
                        AutomaticSize = Enum.AutomaticSize.X,
                        Text = note,
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
            return Frame, Value, Note
        end

        -- Button text color that flashButtonFeedback would reset to Theme.Text after its feedback
        local function keepColor(Btn, defaultText, color, afterSeconds)
            task.delay(afterSeconds, function()
                if Btn.Text == defaultText then Btn.TextColor3 = color end
            end)
        end

        --// =====================================================================
        --// PART E. RESTORE LAST SESSION  (the switch only; the store lives in the core: ctx.Session)
        --// =====================================================================
        if Session and type(Session.isEnabled) == "function" and type(Session.setEnabled) == "function" and CreateToggleOption then
            local okE, errE = pcall(function()
                local _, _, api = CreateSubtitleToggle(Tab, "Restore last session", "Switches stay on after Server Hop or Rejoin", 3,
                    { initial = Session.isEnabled() })
                api.onChanged(function(on) Session.setEnabled(on) end)
            end)
            if not okE then warn("[Elysera/Settings] Could not build Restore last session: " .. tostring(errE)) end
        end

        --// =====================================================================
        --// PART F. INTERFACE  (UI Scale, Reduce Motion, Menu Key; the state lives in the core)
        --// =====================================================================
        if UI and UI.CreateSection and CreateStyledButton and CreateToggleOption and (UIScaleApi or MotionApi or MenuKeyApi) then
            local okF, errF = pcall(function()
                local Section = UI.CreateSection(Tab, "Interface", 5, { subtitle = "Zoom, animations and a key for the menu" })
                local Body = Section.Body

                -- UI Scale: zooms the content of the window (the window keeps its size, so dragging and resizing are unchanged)
                if UIScaleApi then
                    local step, lo, hi = UIScaleApi.STEP or 0.05, UIScaleApi.MIN or 0.7, UIScaleApi.MAX or 1.3
                    local Frame = CreateTwoLineRow(Body, "UI Scale",
                        string.format("Zoom the content, %d%% to %d%%", math.floor(lo * 100 + 0.5), math.floor(hi * 100 + 0.5)), 1, 132)
                    local Plus = CreateStyledButton(Frame, "+", 34)
                    local Value = label(Frame, {
                        AnchorPoint = Vector2.new(1, 0.5),
                        Position = UDim2.new(1, -40, 0.5, 0),
                        Size = UDim2.fromOffset(52, 24),
                        Text = "",
                        TextSize = 15,
                        TextXAlignment = Enum.TextXAlignment.Center,
                        TextColor3 = Theme.AccentPink,
                    })
                    local Minus = CreateStyledButton(Frame, "-", 34)
                    Minus.Position = UDim2.new(1, -98, 0.5, 0)

                    local function showScale()
                        Value.Text = string.format("%d%%", math.floor(UIScaleApi.get() * 100 + 0.5))
                    end
                    local function nudge(dir, Btn, symbol)
                        if isLocked() then return end
                        local before = UIScaleApi.get()
                        local ok, after = pcall(UIScaleApi.set, before + dir * step)
                        showScale()
                        if not ok then
                            flashButtonFeedback(Btn, symbol, "Err", true, 0.8)
                        elseif after == before then
                            flashButtonFeedback(Btn, symbol, dir > 0 and "Max" or "Min", true, 0.6)
                        end
                    end
                    Plus.MouseButton1Click:Connect(function() nudge(1, Plus, "+") end)
                    Minus.MouseButton1Click:Connect(function() nudge(-1, Minus, "-") end)
                    showScale()
                end

                -- Reduce Motion: the core's tween helper plays every animation instantly while this is on
                if MotionApi then
                    local Switch, _, api = CreateSubtitleToggle(Body, "Reduce Motion", "Turn off the UI animations", 2,
                        { initial = MotionApi.isReduced() })
                    api.onChanged(function(on) MotionApi.setReduced(on) end)
                    Section.track(Switch)
                end

                -- Menu Key: a key that shows or hides Elysera (the core listens for it). Only useful with a keyboard
                if MenuKeyApi and UserInputService.KeyboardEnabled then
                    local HINT = "Show or hide Elysera with one key"
                    local Frame, _, Sub = CreateTwoLineRow(Body, "Menu Key", HINT, 3, 118)
                    local KeyBtn = CreateStyledButton(Frame, "None", 108)

                    local capturing, capConn, capToken = false, nil, 0
                    -- while listening, the core must not react to the key that is pressed (it would close the menu under our feet)
                    local function pauseHotkey(on)
                        if type(MenuKeyApi.pause) == "function" then pcall(MenuKeyApi.pause, on) end
                    end
                    local function showKey()
                        KeyBtn.Text = MenuKeyApi.get() or "None"
                        KeyBtn.TextColor3 = MenuKeyApi.get() and Theme.AccentPink or Theme.SubText
                    end
                    local function stopCapture()
                        capturing = false
                        capToken += 1
                        if capConn then capConn:Disconnect() capConn = nil end
                        pauseHotkey(false)
                        Sub.Text, Sub.TextColor3 = HINT, Theme.SubText
                        showKey()
                    end
                    local function startCapture()
                        capturing = true
                        capToken += 1
                        local myToken = capToken
                        pauseHotkey(true)
                        KeyBtn.Text, KeyBtn.TextColor3 = "Press a key...", Theme.Sakura
                        Sub.Text = "Esc cancels, Backspace removes the key"
                        capConn = UserInputService.InputBegan:Connect(function(input)
                            if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
                            local code = input.KeyCode
                            if code == Enum.KeyCode.Escape then stopCapture() return end
                            if code == Enum.KeyCode.Backspace then
                                MenuKeyApi.set(nil)
                                stopCapture()
                                return
                            end
                            local ok, accepted, why = pcall(MenuKeyApi.set, code.Name)
                            stopCapture()
                            if not ok or accepted == false then
                                flashButtonFeedback(KeyBtn, KeyBtn.Text, "Not allowed", true, 1.2)
                                keepColor(KeyBtn, KeyBtn.Text, MenuKeyApi.get() and Theme.AccentPink or Theme.SubText, 1.3)
                                if why then toast(tostring(why), "warn") end
                            end
                        end)
                        task.delay(8, function() -- nobody pressed anything: stop listening
                            if capturing and capToken == myToken then stopCapture() end
                        end)
                    end

                    KeyBtn.MouseButton1Click:Connect(function()
                        if isLocked() then return end
                        if capturing then stopCapture() else startCapture() end
                    end)
                    Tab:GetPropertyChangedSignal("Visible"):Connect(function()
                        if not Tab.Visible and capturing then stopCapture() end
                    end)
                    ScreenGui.Destroying:Connect(function()
                        if capConn then capConn:Disconnect() capConn = nil end
                    end)
                    showKey()
                end
            end)
            if not okF then warn("[Elysera/Settings] Could not build Interface: " .. tostring(errF)) end
        end

        --// =====================================================================
        --// PART G. CONFIG  (Export / Import / Reset of the settings; the file is written by the core: ctx.Config)
        --// =====================================================================
        if UI and UI.CreateSection and CreateInfoRow and CreateStyledButton then
            local okG, errG = pcall(function()
                local Section = UI.CreateSection(Tab, "Config", 6, {
                    subtitle = "Export, import or reset your settings",
                    collapsed = true,
                })
                local Body = Section.Body

                local function finite(v) return type(v) == "number" and v == v and math.abs(v) < 1e6 end
                -- What an export / import may carry. Scripts, waypoints, Auto Execute and the session are deliberately not part of it
                local VALID = {
                    theme          = function(v) return type(v) == "string" and byId[v] ~= nil end,
                    uiScale        = function(v) return finite(v) and v >= 0.3 and v <= 3 end,
                    reduceMotion   = function(v) return type(v) == "boolean" end,
                    restoreSession = function(v) return type(v) == "boolean" end,
                    menuKey        = function(v) return type(v) == "string" and #v <= 32 and v:match("^%w*$") ~= nil end,
                    fpsMode        = function(v) return type(v) == "string" and #v <= 32 end,
                    w              = finite, h = finite, uiX = finite, uiY = finite,
                    toggle         = function(v)
                        return type(v) == "table" and #v == 4 and finite(v[1]) and finite(v[2]) and finite(v[3]) and finite(v[4])
                    end,
                }

                -- Export text: the settings as they are right now (the core's snapshot includes the live window layout)
                local function buildExport()
                    local source = Saved
                    if Config and type(Config.snapshot) == "function" then
                        local ok, snap = pcall(Config.snapshot)
                        if ok and type(snap) == "table" then source = snap end
                    end
                    local out = {}
                    for key, valid in pairs(VALID) do
                        if valid(source[key]) then out[key] = source[key] end
                    end
                    return HttpService:JSONEncode({
                        format = "elysera-config",
                        version = 1,
                        app = Loader.version,
                        settings = out,
                    })
                end

                -- Text -> clean settings table. Returns clean, count  or  nil, short reason (fits a 80px button)
                local function parseConfig(text)
                    text = (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
                    if text == "" then return nil, "Empty" end
                    local ok, data = pcall(HttpService.JSONDecode, HttpService, text)
                    if not ok or type(data) ~= "table" then return nil, "Bad JSON" end
                    local source = data
                    if data.format ~= nil then
                        if data.format ~= "elysera-config" or type(data.settings) ~= "table" then return nil, "Invalid" end
                        source = data.settings
                    end
                    local clean, count = {}, 0
                    for key, valid in pairs(VALID) do
                        if source[key] ~= nil and valid(source[key]) then
                            clean[key] = source[key]
                            count += 1
                        end
                    end
                    if count == 0 then return nil, "No data" end
                    return clean, count
                end

                --// ---------- Export ----------
                local ExportFrame, ExportLeft = CreateInfoRow(Body, "Export settings")
                ExportFrame.LayoutOrder = 1
                label(ExportLeft, {
                    LayoutOrder = 2,
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    Text = "· copy as text",
                    Font = Enum.Font.Gotham,
                    TextSize = 12,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextColor3 = Theme.SubText,
                })
                local ExportBtn = CreateStyledButton(ExportFrame, "Copy", 70)
                ExportBtn.MouseButton1Click:Connect(function()
                    if isLocked() then return end
                    local text = buildExport()
                    if UI.CopyText(text) then
                        flashButtonFeedback(ExportBtn, "Copy", "Copied", false)
                        toast("Settings copied. Paste them into Import on another device.", "success")
                        return
                    end
                    -- no clipboard function in this executor: keep a file instead
                    local saved = false
                    if D.canFS and D.dataPath and typeof(writefile) == "function" then
                        saved = pcall(writefile, D.dataPath("Elysera_Config_Export.json"), text)
                    end
                    flashButtonFeedback(ExportBtn, "Copy", saved and "Saved" or "Failed", not saved, 1.5)
                    if saved then toast("No clipboard here. Saved to Elysera/Elysera_Config_Export.json", "info", { duration = 4 }) end
                end)

                --// ---------- Import ----------
                if Config and type(Config.replace) == "function" and CreateCard and bindBoxFocus then
                    local Card = CreateCard(Body, "ImportCard", 12, 14, 12)
                    Card.LayoutOrder = 2
                    label(Card, {
                        LayoutOrder = 1,
                        Size = UDim2.new(1, 0, 0, 20),
                        Text = "Import settings",
                        TextSize = 15,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextColor3 = Theme.Text,
                    })
                    local Box = new("TextBox", {
                        LayoutOrder = 2,
                        Size = UDim2.new(1, 0, 0, 34),
                        BackgroundColor3 = Theme.PanelAlt,
                        BorderSizePixel = 0,
                        Text = "",
                        PlaceholderText = "",
                        ClearTextOnFocus = false,
                        Font = Enum.Font.Gotham,
                        TextSize = 14,
                        TextColor3 = Theme.Text,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        ClipsDescendants = true,
                    }, Card)
                    corner(Box, 6)
                    local BoxStroke = stroke(Box)
                    padding(Box, 10, 10)
                    local Placeholder = label(Box, {
                        Size = UDim2.fromScale(1, 1),
                        Text = "Paste exported settings here",
                        Font = Enum.Font.Gotham,
                        TextSize = 14,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextColor3 = Theme.SubText,
                        TextTransparency = 0.5,
                    })
                    local function refreshPlaceholder()
                        Placeholder.Visible = Box.Text == "" and not Box:IsFocused()
                    end
                    bindBoxFocus(Box, BoxStroke, refreshPlaceholder, refreshPlaceholder)
                    Box:GetPropertyChangedSignal("Text"):Connect(refreshPlaceholder)

                    local BtnRow = new("Frame", {
                        LayoutOrder = 3,
                        Size = UDim2.new(1, 0, 0, 30),
                        BackgroundTransparency = 1,
                    }, Card)
                    local ImportBtn = CreateStyledButton(BtnRow, "Import", 80)
                    if typeof(getclipboard) == "function" then
                        local PasteBtn = CreateStyledButton(BtnRow, "Paste", 70)
                        PasteBtn.Position = UDim2.new(1, -88, 0.5, 0)
                        PasteBtn.MouseButton1Click:Connect(function()
                            if isLocked() then return end
                            local ok, text = pcall(getclipboard)
                            if ok and type(text) == "string" and text ~= "" then
                                Box.Text = text
                                flashButtonFeedback(PasteBtn, "Paste", "Pasted", false, 0.8)
                            else
                                flashButtonFeedback(PasteBtn, "Paste", "Empty", true, 0.8)
                            end
                        end)
                    end

                    local importing = false
                    ImportBtn.MouseButton1Click:Connect(function()
                        if isLocked() or importing then return end
                        local clean, info = parseConfig(Box.Text)
                        if not clean then
                            flashStrokeError(BoxStroke)
                            flashButtonFeedback(ImportBtn, "Import", info, true, 1.2)
                            return
                        end
                        local ok, err = pcall(Config.replace, clean)
                        if not ok then
                            flashButtonFeedback(ImportBtn, "Import", "Failed", true, 1.5)
                            toast("Import failed: " .. tostring(err), "error")
                            return
                        end
                        importing = true
                        flashButtonFeedback(ImportBtn, "Import", "Imported", false, math.huge)
                        toast(("Imported %d settings. Reloading Elysera..."):format(info), "success")
                    end)
                end

                --// ---------- Reset ----------
                if Config and type(Config.reset) == "function" then
                    local ResetFrame, ResetLeft = CreateInfoRow(Body, "Reset settings")
                    ResetFrame.LayoutOrder = 3
                    label(ResetLeft, {
                        LayoutOrder = 2,
                        Size = UDim2.new(0, 0, 1, 0),
                        AutomaticSize = Enum.AutomaticSize.X,
                        Text = "· back to defaults",
                        Font = Enum.Font.Gotham,
                        TextSize = 12,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextColor3 = Theme.SubText,
                    })
                    local ResetBtn = CreateStyledButton(ResetFrame, "Reset", 70)
                    ResetBtn.TextColor3 = Theme.Danger

                    -- first tap arms the button, a second tap within 2.5 seconds resets
                    local armedToken, resetting = 0, false
                    ResetBtn.MouseButton1Click:Connect(function()
                        if isLocked() or resetting then return end
                        if not ResetBtn:GetAttribute("Armed") then
                            ResetBtn:SetAttribute("Armed", true)
                            armedToken += 1
                            local token = armedToken
                            flashButtonFeedback(ResetBtn, "Reset", "Sure?", true, 2.5)
                            keepColor(ResetBtn, "Reset", Theme.Danger, 2.6)
                            task.delay(2.5, function()
                                if armedToken == token then ResetBtn:SetAttribute("Armed", false) end
                            end)
                            return
                        end
                        ResetBtn:SetAttribute("Armed", false)
                        armedToken += 1
                        local ok, err = pcall(Config.reset)
                        if not ok then
                            flashButtonFeedback(ResetBtn, "Reset", "Failed", true, 1.5)
                            keepColor(ResetBtn, "Reset", Theme.Danger, 1.6)
                            toast("Reset failed: " .. tostring(err), "error")
                            return
                        end
                        resetting = true
                        flashButtonFeedback(ResetBtn, "Reset", "Resetting...", false, math.huge)
                        toast("Settings reset. Reloading Elysera...", "success")
                    end)
                end
            end)
            if not okG then warn("[Elysera/Settings] Could not build Config: " .. tostring(errG)) end
        end

        --// =====================================================================
        --// PART H. ABOUT  (version, update check, Reload; the data comes from the core's Loader)
        --// =====================================================================
        if UI and UI.CreateSection and CreateInfoRow and CreateStyledButton and (Loader.version or D.reloadUI or Loader.download) then
            local okH, errH = pcall(function()
                local Section = UI.CreateSection(Tab, "About", 8, { subtitle = "Version and updates", collapsed = true })
                local Body = Section.Body

                local refName = tostring(Loader.ref or ""):match("([^/]+)$")
                local _, VersionValue = addValueRow(Body, "Version", refName and ("· " .. refName) or nil, 1)
                VersionValue.Text = Loader.version and tostring(Loader.version) or "unknown"

                -- Update check: download every module again and compare it with the copy that is running now
                if type(Loader.download) == "function" and type(Loader.urls) == "table" and type(Loader.texts) == "table" then
                    local _, StatusValue, StatusNote = addValueRow(Body, "Updates", nil, 2)
                    StatusValue.Text = "Not checked"
                    local StatusFrame = StatusValue.Parent
                    local CheckBtn = CreateStyledButton(StatusFrame, "Check", 70)
                    -- the value would sit under the button: make room (button 70 + gap 8)
                    StatusValue.Position = UDim2.new(1, -78, 0.5, 0)
                    StatusValue.Size = UDim2.fromOffset(110, 24)
                    local StatusLeft = StatusFrame:FindFirstChild("Left")
                    if StatusLeft then StatusLeft.Size = UDim2.new(1, -196, 1, 0) end

                    local checking = false
                    local function setStatus(text, color)
                        StatusValue.Text = text
                        StatusValue.TextColor3 = color or Theme.AccentPink
                    end

                    local function runCheck()
                        local changed, failed, asked = {}, 0, 0
                        for _, file in ipairs(Loader.files or {}) do
                            local url = Loader.urls[file]
                            if url and Loader.sources and Loader.sources[file] ~= "error" then
                                asked += 1
                                local ok, body = pcall(Loader.download, url)
                                if ok and type(body) == "string" and body ~= "" then
                                    if Loader.texts[file] ~= body then changed[#changed + 1] = file end
                                else
                                    failed += 1
                                end
                            end
                        end
                        -- the core itself (MainWeb.lua) cannot read its own text: compare the VERSION line instead
                        local remoteVersion
                        if Loader.bootUrl and Loader.version then
                            asked += 1
                            local ok, body = pcall(Loader.download, Loader.bootUrl)
                            if ok and type(body) == "string" then
                                remoteVersion = body:match('local VERSION%s*=%s*"([^"]+)"')
                                if remoteVersion and remoteVersion ~= Loader.version then
                                    table.insert(changed, 1, "MainWeb.lua")
                                end
                            else
                                failed += 1
                            end
                        end
                        return changed, failed, asked, remoteVersion
                    end

                    CheckBtn.MouseButton1Click:Connect(function()
                        if isLocked() or checking then return end
                        checking = true
                        setStatus("Checking...", Theme.SubText)
                        flashButtonFeedback(CheckBtn, "Check", "Wait", false, math.huge, Theme.SubText)
                        task.spawn(function()
                            local ok, changed, failed, asked, remoteVersion = pcall(runCheck)
                            checking = false
                            if not ok then
                                setStatus("Failed", Theme.Danger)
                                flashButtonFeedback(CheckBtn, "Check", "Failed", true, 1.5)
                                return
                            end
                            if asked > 0 and failed == asked then
                                setStatus("No connection", Theme.Danger)
                                flashButtonFeedback(CheckBtn, "Check", "Failed", true, 1.5)
                            elseif #changed > 0 then
                                setStatus(#changed .. " update" .. (#changed > 1 and "s" or ""), Theme.Sakura)
                                flashButtonFeedback(CheckBtn, "Check", "Found", false, 1.2)
                                toast("Update available: " .. table.concat(changed, ", ") .. ". Press Reload to apply.", "info", { duration = 6 })
                            else
                                setStatus(failed > 0 and "Up to date*" or "Up to date", Theme.AccentPink)
                                flashButtonFeedback(CheckBtn, "Check", "Done", false, 1.2)
                            end
                        end)
                    end)
                end

                -- Reload: destroys the UI and runs the boot code again (picks up updates and applies a changed config)
                if type(D.reloadUI) == "function" then
                    local ReloadFrame, ReloadLeft = CreateInfoRow(Body, "Reload Elysera")
                    ReloadFrame.LayoutOrder = 3
                    label(ReloadLeft, {
                        LayoutOrder = 2,
                        Size = UDim2.new(0, 0, 1, 0),
                        AutomaticSize = Enum.AutomaticSize.X,
                        Text = "· apply updates",
                        Font = Enum.Font.Gotham,
                        TextSize = 12,
                        TextXAlignment = Enum.TextXAlignment.Left,
                        TextColor3 = Theme.SubText,
                    })
                    local ReloadBtn = CreateStyledButton(ReloadFrame, "Reload", 80)
                    local reloading = false
                    ReloadBtn.MouseButton1Click:Connect(function()
                        if isLocked() or reloading then return end
                        local ok, err = pcall(D.reloadUI)
                        if ok then
                            reloading = true
                            flashButtonFeedback(ReloadBtn, "Reload", "Reloading...", false, math.huge)
                        else
                            flashButtonFeedback(ReloadBtn, "Reload", "Failed", true, 1.5)
                            toast("Reload failed: " .. tostring(err), "error")
                        end
                    end)
                end
            end)
            if not okH then warn("[Elysera/Settings] Could not build About: " .. tostring(errH)) end
        end
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
        -- reserved for the core (closeUI)
        isListOpen     = function() return listOpen end,
        hideList       = function() closeList(true) end,
    }
end
