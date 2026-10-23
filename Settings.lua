--// ============================================================================
--//  Settings.lua  -  module cho tab "Settings" của Elysera MainUI
--//
--//  Gồm 2 chức năng (A tách từ MainLocal.lua, B gộp từ Theme.lua):
--//    A) Anti Chat   công tắc chặn gửi tin nhắn chat (LayoutOrder = 1)
--//    B) Theme       hàng "Theme" + danh sách thả xuống để đổi bảng màu (LayoutOrder = 2)
--//
--//  Đặt file này cạnh các module khác (Script.lua, Status_Server.lua, Local.lua, FPS.lua).
--//  MainLocal.lua nạp bằng readModule("Settings.lua") + init({...}) ở CUỐI (sau FPS TAB), để lần áp theme
--//  đầu tiên (theme đã lưu) bao trùm cả các tab ở trên. Theme.lua cũ đã gộp vào file này, không nạp riêng nữa.
--//
--//  Cách hoạt động của Theme (phương án C trong báo cáo, không dựng lại UI):
--//    1) Dựng bảng ánh xạ  "màu của Theme hiện tại" -> "màu theme mới"  theo từng token.
--//    2) Ghi màu mới vào bảng Theme TẠI CHỖ (cùng tham chiếu mà các module đang giữ).
--//    3) Chốt các tween màu đang chạy dở, rồi quét cây ElyseraUI, thay các thuộc tính màu khớp chính xác
--//       (kể cả từng keypoint UIGradient).
--//    4) Chạy refreshStateColors() của core (tab đang chọn, công tắc, Resize mode...).
--//    5) Đặt Attribute "Theme" trên ScreenGui, lưu cấu hình, gọi các listener onChanged.
--//
--//  API Theme (init trả về, MainLocal.lua gán vào ThemeAPI):
--//    Themes                 danh sách { id, name, mode, colors }
--//    SetTheme(id)           -> true | false, lỗi
--//    GetTheme()             -> id, tên
--//    OnThemeChanged(fn)     fn(id, Theme, entry); trả về hàm huỷ đăng ký
--//    Stats                  { scanned, changed, ms } của lần remap gần nhất
--//    isListOpen(), hideList()  dành riêng cho core (closeUI đóng danh sách đang mở)
--//
--//  Quy ước: Instance có Attribute NoTheme = true (cả nhánh con) bị remap bỏ qua.
--//  Quy tắc bảng màu: đủ 13 token; 12 token (trừ ToggleKnobOn) khác nhau từng đôi một và
--//  không phải #FFFFFF / #000000 (trắng là nền của các khung gradient, đen là lớp phủ).
--// ============================================================================

return function(D)
    --// ================= DEPS (từ MainWeb.lua / MainLocal.lua) =================
    local Theme        = D.Theme
    local ScreenGui    = D.ScreenGui
    local MainUI       = D.MainUI
    local Tab          = D.Tab
    local CoreGui      = D.CoreGui
    local GuiRoot      = D.GuiRoot or CoreGui   -- nơi GUI thực sự được gắn (CoreGui, hoặc PlayerGui khi dự phòng)
    local LocalPlayer  = D.LocalPlayer
    local Saved        = D.Saved or {}
    local saveSettings = D.saveSettings or function() end

    local new, corner, stroke, padding = D.new, D.corner, D.stroke, D.padding
    local list, label, tween, pressScale = D.list, D.label, D.tween, D.pressScale
    local CreateToggleOption = D.CreateToggleOption

    local EASE_QUAD, EASE_BACK = D.EASE_QUAD, D.EASE_BACK
    local DIR_IN, DIR_OUT      = D.DIR_IN, D.DIR_OUT
    local ANCHOR_CENTER        = D.ANCHOR_CENTER

    local isOpen, isLocked, setLocked = D.isOpen, D.isLocked, D.setLocked
    local fadeMainUI                  = D.fadeMainUI
    local refreshStateColors          = D.refreshStateColors or function() end

    --// =====================================================================
    --// PHẦN A. ANTI CHAT  (tách từ MainLocal.lua)
    --// =====================================================================
    do
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

        -- Chặn tin nhắn gửi từ script (game hoặc executor) ở tầng __namecall / hookfunction.
        -- Hook không gỡ được nên dùng cờ antiChatOn: tắt toggle thì hook chỉ đi qua.
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

            -- Bắt thêm trường hợp gọi kiểu remote.FireServer(remote, ...) / channel.SendAsync(channel, ...)
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

        -- Chặn ở giao diện. Khung chat cũ (Legacy): không cho ChatBar nhận focus -> không gõ/gửi được
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

            -- Khung chat mới (TextChatService): tắt thanh nhập tin nhắn
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
    end

    --// =====================================================================
    --// PHẦN B. THEME  (gộp từ Theme.lua)
    --// =====================================================================
    local V2          = Vector2.new
    local TextService = game:GetService("TextService")

    local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

    --// ================= CẤU HÌNH =================
    local DEFAULT_ID  = "sakura"
    local HEAL        = true   -- tự "chữa" màu cũ còn sót (xem makeLookup)
    local FADE_OUT_T  = 0.12   -- mờ xuống
    local FADE_IN_T   = 0.22   -- hiện lại
    local FADE_ALPHA  = 0.55   -- độ mờ tại điểm mờ nhất (remap chạy ở đây)
    local YIELD_EVERY = 700    -- chia lô: nhường 1 frame sau mỗi ngần này Instance (chỉ khi UI đang hiện)

    local WIN_H, ARROW_ZONE      = 28, 26         -- winbox cao 28; vùng nút mũi tên 26
    local WIN_MIN_W, WIN_MAX_W   = 112, 190
    local ITEM_H, ITEM_GAP, LIST_PAD = 34, 4, 4
    local LIST_MIN_W, LIST_MAX_ROWS  = 200, 6
    local LIST_OPEN_T, LIST_CLOSE_T  = 0.15, 0.12
    local Z_CATCHER, Z_LIST          = 25, 30     -- trên InteractionBlocker (20), dưới hộp thoại (51)

    --// =====================================================================
    --// 1. DỮ LIỆU THEME
    --// =====================================================================
    local TOKENS = {
        "Background", "Panel", "PanelAlt", "Header", "Border",
        "AccentPink", "AccentPurple", "Sakura", "Text", "SubText",
        "Danger", "ToggleTrackOff", "ToggleKnobOn",
    }
    local KNOB = "ToggleKnobOn" -- bị loại khỏi remap (được phép trắng/đen thuần), do refreshStateColors lo

    -- Tên token giữ nguyên để không phải sửa các module. AccentPink / AccentPurple / Sakura chỉ là
    -- "vai trò": nhấn chính / nhấn phụ / chữ nhấn, không nhất thiết là màu hồng hay tím.
    local RAW = {
        -- 1. Elysera Sakura: tím neon và hồng sakura (mặc định, = bảng Theme hiện tại của core)
        { id = "sakura", name = "Elysera Sakura", mode = "dark", snapshot = true },
        -- 2. Midnight Ocean: xanh navy sâu, nhấn cyan/azure
        { id = "ocean", name = "Midnight Ocean", mode = "dark", colors = {
            Background = "0D1D2F", Panel = "0E1F33", PanelAlt = "10243B", Header = "122A45", Border = "1F4775",
            AccentPink = "2FB9F7", AccentPurple = "4F7DFF", Sakura = "A8E9FF", Text = "D3E8FA", SubText = "8FB2D6",
            Danger = "FF6F8A", ToggleTrackOff = "1C3F68", ToggleKnobOn = "FFFFFF",
        } },
        -- 3. Emerald Forest: xanh rừng sẫm, nhấn ngọc lục bảo; núm ON tối
        { id = "emerald", name = "Emerald Forest", mode = "dark", colors = {
            Background = "11261D", Panel = "132920", PanelAlt = "153025", Header = "19382B", Border = "2B5F49",
            AccentPink = "34D399", AccentPurple = "7BD66B", Sakura = "C6F8E0", Text = "D6F3E4", SubText = "8FBCA6",
            Danger = "FF7B7B", ToggleTrackOff = "265441", ToggleKnobOn = "07140D",
        } },
        -- 4. Crimson Ember: đỏ than hồng, nhấn vermilion
        { id = "crimson", name = "Crimson Ember", mode = "dark", colors = {
            Background = "261013", Panel = "2A1115", PanelAlt = "301318", Header = "38171D", Border = "5F2730",
            AccentPink = "FF6B4A", AccentPurple = "E8334F", Sakura = "FFC9B8", Text = "F6DAD3", SubText = "C79A93",
            Danger = "FF5C8A", ToggleTrackOff = "54222B", ToggleKnobOn = "FFFFFF",
        } },
        -- 5. Golden Sunset: nâu hổ phách, nhấn vàng–cam; núm ON tối
        { id = "sunset", name = "Golden Sunset", mode = "dark", colors = {
            Background = "261A0F", Panel = "291C10", PanelAlt = "2F2112", Header = "382716", Border = "5E4124",
            AccentPink = "FFB020", AccentPurple = "FF7A33", Sakura = "FFE0A3", Text = "F4E5CD", SubText = "C2A783",
            Danger = "FF5D5D", ToggleTrackOff = "533A20", ToggleKnobOn = "1A130C",
        } },
        -- 6. Coral Lagoon: xanh ngọc thẫm, nhấn san hô
        { id = "lagoon", name = "Coral Lagoon", mode = "dark", colors = {
            Background = "0F272B", Panel = "102A2F", PanelAlt = "133036", Header = "16393F", Border = "26606B",
            AccentPink = "FF7F8A", AccentPurple = "FFA06B", Sakura = "FFDDD2", Text = "D5EEEE", SubText = "8FBDBF",
            Danger = "FF5470", ToggleTrackOff = "21555F", ToggleKnobOn = "FFFFFF",
        } },
        -- 7. Arctic Frost: xám xanh lạnh, nhấn băng nhạt; núm ON tối
        { id = "arctic", name = "Arctic Frost", mode = "dark", colors = {
            Background = "1B222A", Panel = "1D242E", PanelAlt = "222A35", Header = "28313E", Border = "435369",
            AccentPink = "8BD3F0", AccentPurple = "7C9CFF", Sakura = "D4F0FB", Text = "E1E9F2", SubText = "9DAEC4",
            Danger = "F2788C", ToggleTrackOff = "3B4A5D", ToggleKnobOn = "0F151D",
        } },
        -- 8. Carbon Mono: đơn sắc than chì và bạc; núm ON tối
        { id = "carbon", name = "Carbon Mono", mode = "dark", colors = {
            Background = "212123", Panel = "232325", PanelAlt = "29292B", Header = "303033", Border = "515156",
            AccentPink = "E4E4E4", AccentPurple = "A0A0A0", Sakura = "F5F5F5", Text = "D6D6D6", SubText = "A3A3A3",
            Danger = "FF6B7A", ToggleTrackOff = "47474C", ToggleKnobOn = "121212",
        } },
        -- 9. Neon Matrix: gần đen, xanh neon kiểu terminal; núm ON tối
        { id = "matrix", name = "Neon Matrix", mode = "dark", colors = {
            Background = "09150D", Panel = "0A170E", PanelAlt = "0C1A11", Header = "0E1F14", Border = "2A5A40",
            AccentPink = "1AFF9C", AccentPurple = "19D3FF", Sakura = "B6FFE0", Text = "CFF7E2", SubText = "7FBF9F",
            Danger = "FF5577", ToggleTrackOff = "1F4A30", ToggleKnobOn = "03110A",
        } },
        -- 10. Porcelain Day: trắng lavender, nhấn hồng–violet (theme sáng duy nhất)
        { id = "porcelain", name = "Porcelain Day", mode = "light", colors = {
            Background = "F5F1FB", Panel = "FBF9FE", PanelAlt = "ECE6F7", Header = "DFD5F1", Border = "B9A7DB",
            AccentPink = "C0267A", AccentPurple = "9A74F8", Sakura = "8E0F50", Text = "2D1B4E", SubText = "65558A",
            Danger = "BE1F43", ToggleTrackOff = "CDC1E4", ToggleKnobOn = "FFFFFF",
        } },
    }

    local function hex(h)
        return Color3.fromRGB(
            tonumber(h:sub(1, 2), 16),
            tonumber(h:sub(3, 4), 16),
            tonumber(h:sub(5, 6), 16))
    end

    -- khoá số nguyên của một màu: r*65536 + g*256 + b (làm tròn từng kênh về 0..255)
    local function colorKey(c)
        return math.floor(c.R * 255 + 0.5) * 65536
            + math.floor(c.G * 255 + 0.5) * 256
            + math.floor(c.B * 255 + 0.5)
    end

    -- Q1 + Q2 + Q3: đủ 13 token Color3; 12 token khác nhau; không token nào (trừ ToggleKnobOn) là trắng/đen
    local function validatePalette(p)
        if type(p) ~= "table" then return false, "không phải table" end
        local seen = {}
        for _, k in ipairs(TOKENS) do
            local c = p[k]
            if typeof(c) ~= "Color3" then
                return false, "token " .. k .. " thiếu hoặc không phải Color3"
            end
            if k ~= KNOB then
                local key = colorKey(c)
                if key == 0xFFFFFF or key == 0x000000 then
                    return false, "token " .. k .. " không được là #FFFFFF hoặc #000000"
                end
                if seen[key] then
                    return false, "token " .. k .. " trùng màu với " .. seen[key]
                end
                seen[key] = k
            end
        end
        return true
    end

    -- Theme 1 (sakura) lấy từ ảnh chụp bảng Theme hiện tại của core -> giống hệt bản gốc
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
                warn("[Elysera/Theme] Bỏ qua theme '" .. tostring(raw.id) .. "': " .. tostring(why))
            end
        end
        return out
    end

    local THEMES = buildThemes()
    local byId = {}
    for _, t in ipairs(THEMES) do byId[t.id] = t end
    assert(byId[DEFAULT_ID], "Settings.lua: thiếu theme mặc định '" .. DEFAULT_ID .. "'")

    -- Chỉ mục "chữa màu cũ": khoá màu của MỌI theme -> tên token, bỏ khoá mơ hồ (cùng màu nhưng khác vai trò).
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
    local currentId = DEFAULT_ID -- core dựng UI bằng bảng màu mặc định
    local applying, pendingId, pendingOpts = false, nil, nil
    local stats = { scanned = 0, changed = 0, ms = 0 }

    -- Hàm UI khai báo trước (gán ở phần 3); bản rỗng để engine chạy được trước khi dựng UI
    local function noop() end
    local closeList, refreshItems, updateWinbox = noop, noop, noop
    local applyTheme

    -- Khoá UI bằng bộ đếm, nhớ trạng thái khoá trước đó (ví dụ Resize mode đang bật)
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
            if not ok then warn("[Elysera/Theme] onChanged lỗi: " .. tostring(err)) end
        end
    end

    -- khoá màu CŨ (đúng thứ Instance đang giữ = giá trị hiện tại của bảng Theme) -> Color3 MỚI
    local function buildColorMap(from, to)
        local map = {}
        for _, k in ipairs(TOKENS) do
            if k ~= KNOB then map[colorKey(from[k])] = to[k] end
        end
        return map
    end

    -- Trả về hàm tra: Color3 -> Color3 mới | nil (giữ nguyên).
    -- Màu không phải token (trắng, đen, màu Lerp, hard-code) -> nil.
    -- HEAL: màu khớp một token của theme KHÁC (còn sót do closure giữ màu cũ) cũng được đưa về đúng vai trò
    -- trong theme mới; khoá mơ hồ đã bị loại ở buildHealIndex.
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

    -- Thay từng keypoint của ColorSequence; trả về ColorSequence mới hoặc nil nếu không đổi gì
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

    -- Các thuộc tính màu cần xét theo ClassName
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

    -- duyệt cây, bỏ cả nhánh có Attribute NoTheme
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

    -- ScreenGui riêng của Elysera nằm ngoài ScreenGui chính: lớp phủ White/Black Screen và FPS Overlay
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

    -- Áp theme thật sự: ánh xạ -> ghi bảng Theme -> quét -> hook -> lưu -> tín hiệu
    local function commit(entry, opts)
        local t0 = os.clock()
        local lookup = makeLookup(buildColorMap(Theme, entry.colors), entry.colors)

        -- Ghi bảng Theme TRƯỚC khi quét: hover/tween phát sinh giữa chừng đã dùng màu mới
        for _, k in ipairs(TOKENS) do Theme[k] = entry.colors[k] end
        currentId = entry.id

        -- tween màu còn đang chạy sẽ kéo thuộc tính về màu CŨ khi kết thúc: hủy và chốt về màu đích đã dịch sang theme mới
        if D.settleColorTweens then
            local okS, errS = pcall(D.settleColorTweens, lookup)
            if not okS then warn("[Elysera/Theme] settleColorTweens lỗi: " .. tostring(errS)) end
        end

        local scanned, changed = remapTree(getRoots(), lookup, opts.yieldEvery)

        ScreenGui:SetAttribute("Theme", entry.id)
        Saved.theme = entry.id

        local ok, err = pcall(refreshStateColors)
        if not ok then warn("[Elysera/Theme] refreshStateColors lỗi: " .. tostring(err)) end
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

    -- opts: animate (mặc định true, chỉ có hiệu lực khi UI đang hiện), noSave, force
    function applyTheme(id, opts)
        opts = opts or {}
        local entry = byId[id]
        if not entry then return false, "Theme không tồn tại: " .. tostring(id) end

        if applying then -- lần chọn sau được nhận khi lần trước xong
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
            if not ok then warn("[Elysera/Theme] Lỗi khi áp '" .. id .. "': " .. tostring(err)) end
            drainPending()
            return ok, err
        end

        applying = true
        hold() -- giữ khoá UI suốt hiệu ứng để không có thao tác chen vào giữa
        task.spawn(function()
            -- mỗi bước bọc pcall riêng: dù lỗi ở đâu vẫn phải đi tới release(), nếu không UI sẽ bị khoá vĩnh viễn
            local ok, err = pcall(function()
                fadeMainUI(FADE_OUT_T, FADE_ALPHA, DIR_OUT)
                task.wait(FADE_OUT_T)
            end)
            if not ok then warn("[Elysera/Theme] Lỗi khi làm mờ: " .. tostring(err)) end

            ok, err = pcall(commit, entry, { noSave = opts.noSave, yieldEvery = YIELD_EVERY })
            if not ok then warn("[Elysera/Theme] Lỗi khi áp '" .. id .. "': " .. tostring(err)) end

            ok, err = pcall(function()
                if isOpen() then fadeMainUI(FADE_IN_T, 0, DIR_OUT) end
            end)
            if not ok then warn("[Elysera/Theme] Lỗi khi hiện lại: " .. tostring(err)) end

            applying = false
            release()
            drainPending()
        end)
        return true
    end

    --// =====================================================================
    --// 3. GIAO DIỆN (hàng Theme + danh sách thả xuống)
    --// =====================================================================
    local function measure(text, size)
        local ok, v = pcall(TextService.GetTextSize, TextService, text, size,
            Enum.Font.GothamBold, V2(1000, 100))
        if ok and v then return v.X end
        return #text * size * 0.6
    end

    -- đoạn thẳng bo tròn đầu, cùng kỹ thuật với Icons / svgStroke của core
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

    -- nhấn: thu nhỏ nhẹ. Không dùng pressScale của core vì nó bỏ qua khi UI đang khoá,
    -- mà danh sách luôn mở trong lúc UI bị khoá
    local function pressItem(btn, downScale)
        local scale = new("UIScale", {}, btn)
        local function up() tween(scale, 0.2, { Scale = 1 }, EASE_BACK, DIR_OUT) end
        btn.MouseButton1Down:Connect(function() tween(scale, 0.08, { Scale = downScale }) end)
        btn.MouseButton1Up:Connect(up)
        btn.MouseLeave:Connect(up)
    end

    local Row, Winbox, WinLabel, Arrow, ArrowBars
    local Catcher, List, ListScroll, ListScrollPad
    local items = {}
    local titleW, listW = 50, LIST_MIN_W
    local listOpen, listToken = false, 0
    local lastRight, lastTop, lastFlip = 0, 0, false

    local DOTS_W  = 4 * 10 + 3 * 3   -- 4 chấm 10px, khe 3px
    local DOTS_X  = 12
    local NAME_X  = DOTS_X + DOTS_W + 9
    local RIGHT_Z = 28               -- vùng dấu ✓ bên phải mỗi mục

    function updateWinbox()
        if not Winbox then return end
        local entry = byId[currentId]
        WinLabel.Text = entry.name
        -- rộng chữ + 20 + vùng mũi tên; mở rộng về phía trái vì winbox neo sát lề phải
        local w = clamp(math.ceil(measure(entry.name, 13)) + 20 + ARROW_ZONE, WIN_MIN_W, WIN_MAX_W)
        local rowW = Row.AbsoluteSize.X
        if rowW > 0 then -- UI nhỏ nhất: chừa chỗ cho tiêu đề (14 + chữ), khe 8, lề phải 12
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

    -- Vị trí danh sách: mép trên cách đáy hàng 6px, mép phải thẳng hàng mép phải hàng (mở về bên trái).
    -- Cao tối đa 6 mục hoặc phần còn lại trong cửa sổ trừ lề 8px; thiếu chỗ (< 3 mục) thì dùng phía có nhiều chỗ hơn.
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

        List.Size = UDim2.fromOffset(math.min(listW, rs.X), h)
        ListScrollPad.PaddingRight = UDim.new(0, fullH > h and 6 or 0) -- chừa chỗ thanh cuộn
        lastRight, lastTop, lastFlip = rp.X + rs.X, top, flip
    end

    local function openList()
        if listOpen or applying or not List or isLocked() then return end
        listOpen = true
        listToken = listToken + 1
        hold()
        refreshItems()
        positionList()

        local dy = lastFlip and 6 or -6
        List.Position = UDim2.fromOffset(lastRight, lastTop + dy)
        List.GroupTransparency = 1
        List.Visible = true
        Catcher.Visible = true
        tween(List, LIST_OPEN_T, {
            Position = UDim2.fromOffset(lastRight, lastTop),
            GroupTransparency = 0,
        }, EASE_QUAD, DIR_OUT)
        setArrow(true)
    end

    function closeList(instant)
        if not listOpen then return end
        listOpen = false
        listToken = listToken + 1
        local token = listToken
        release() -- hoàn khoá UI
        Catcher.Visible = false
        setArrow(false)

        if instant then
            List.Visible = false
            return
        end
        local t = tween(List, LIST_CLOSE_T, {
            Position = UDim2.fromOffset(lastRight, lastTop + (lastFlip and 6 or -6)),
            GroupTransparency = 1,
        }, EASE_QUAD, DIR_IN)
        t.Completed:Connect(function(state)
            if state == Enum.PlaybackState.Completed and token == listToken then
                List.Visible = false
            end
        end)
    end

    local function pick(id)
        if id == currentId then
            closeList(false) -- chọn lại mục đang chọn: chỉ đóng
        else
            applyTheme(id, { animate = true }) -- tự đóng danh sách rồi mờ -> remap -> hiện lại
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

        -- thanh nhấn bên trái cho mục đang chọn (cùng ngôn ngữ với TabPill)
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

        -- dải 4 chấm xem trước: màu CỐ ĐỊNH của chính theme đó -> gắn NoTheme để remap bỏ qua cả nhánh
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
            if key == "Background" then stroke(dot, c.Border, 1) end -- chấm nền cần viền mới nhìn thấy
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

        -- dấu ✓ vẽ bằng 2 đoạn thẳng (không phụ thuộc font có glyph ✓ hay không)
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
        -- lớp bắt chạm: trong suốt, phủ toàn MainUI, chặn mọi thao tác phía sau; chạm vào là đóng
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

        -- đủ rộng để tên dài nhất không bị cắt, nhưng không vượt quá bề rộng hàng (xem positionList)
        local widest = 0
        for _, t in ipairs(THEMES) do widest = math.max(widest, measure(t.name, 13)) end
        listW = math.max(LIST_MIN_W, math.ceil(widest) + NAME_X + RIGHT_Z + LIST_PAD * 2 + 8)

        List = new("CanvasGroup", {
            Name = "ThemeList",
            Visible = false,
            Active = true, -- chạm vào khoảng trống trong danh sách không bị lớp bắt chạm nuốt mất
            AnchorPoint = Vector2.new(1, 0),
            Size = UDim2.fromOffset(listW, 120),
            BackgroundColor3 = Theme.Panel,
            BorderSizePixel = 0,
            GroupTransparency = 1,
            ZIndex = Z_LIST,
        }, MainUI)
        corner(List, 8)
        stroke(List, Theme.Border, 1)
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

        -- cửa sổ đổi cỡ khi danh sách đang mở -> đặt lại vị trí
        MainUI:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
            if listOpen then
                positionList()
                List.Position = UDim2.fromOffset(lastRight, lastTop)
            end
        end)
    end

    local function createThemeRow()
        Row = new("Frame", {
            Name = "ThemeRow",
            LayoutOrder = 2, -- ngay dưới Anti Chat (LayoutOrder = 1)
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

        -- winbox: hiển thị theme đang chọn, neo sát lề phải
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
        -- TextButton: chế độ Contextual mặc định sẽ viền CHỮ (mà Text rỗng nên mất viền), phải ép viền khung
        stroke(Winbox, Theme.Border, 1).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        pressScale(Winbox, 0.97)

        -- tên theme canh giữa trong toàn bộ chiều ngang winbox; đệm 20 hai bên để không chạm mũi tên
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

        -- mũi tên: 2 đoạn thẳng xoay ±45°, xoay 180° + đổi sang Sakura khi danh sách mở
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
    --// 4. KHỞI TẠO + API
    --// =====================================================================
    -- Theme đã lưu: áp NGAY (không hiệu ứng, UI chưa hiện) trước khi dựng hàng Theme,
    -- nên người dùng không thấy nháy màu và hàng Theme được dựng sẵn bằng màu mới
    local savedId = Saved.theme
    if type(savedId) == "string" and savedId ~= currentId and byId[savedId] then
        local ok, err = pcall(applyTheme, savedId, { animate = false, noSave = true })
        if not ok then warn("[Elysera/Theme] Không áp được theme đã lưu: " .. tostring(err)) end
    end
    ScreenGui:SetAttribute("Theme", currentId) -- id không hợp lệ đã lưu sẽ bị ghi đè bằng id đang dùng

    local okUI, errUI = pcall(function()
        createList()
        createThemeRow()
        refreshItems()
    end)
    if not okUI then warn("[Elysera/Theme] Không dựng được hàng Theme: " .. tostring(errUI)) end

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
        -- dành cho core (closeUI)
        isListOpen     = function() return listOpen end,
        hideList       = function() closeList(true) end,
    }
end
