--// ================= SCRIPT TAB (module) =================
-- File này được script chính (test.lua) nạp vào và gọi với 1 bảng ctx
-- chứa các hàm/biến dùng chung của UI. Trả về ScriptDialog để file chính
-- dùng khi đóng UI (closeUI).

return function(ctx)
    local ScriptTab           = ctx.Tab

    local Theme               = ctx.Theme
    local ScreenGui           = ctx.ScreenGui
    local HttpService         = ctx.HttpService
    local UI_NAME             = ctx.UI_NAME
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
    local CreateStyledButton  = ctx.CreateStyledButton
    local flashStrokeError    = ctx.flashStrokeError
    local bindBoxFocus        = ctx.bindBoxFocus
    local isLocked            = ctx.isLocked -- thay cho biến uiLocked của file chính

    local SCRIPT_FILE = "L-scr.json"
    local ScriptList  = {}

    local function saveScriptList()
        if not canFS then return false end
        return (pcall(writefile, SCRIPT_FILE, HttpService:JSONEncode(ScriptList)))
    end

    local function loadScriptList()
        if not canFS then return end
        local ok, data = pcall(function()
            if isfile(SCRIPT_FILE) then
                return HttpService:JSONDecode(readfile(SCRIPT_FILE))
            end
        end)
        if not ok or type(data) ~= "table" then return end
        for _, item in ipairs(data) do
            if type(item) == "table" and type(item.name) == "string" and type(item.script) == "string" then
                ScriptList[#ScriptList + 1] = { name = item.name, script = item.script }
            end
        end
    end

    local function tintIcon(holder, color)
        for _, child in ipairs(holder:GetChildren()) do
            if child:IsA("Frame") then child.BackgroundColor3 = color end
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
        drawIcon(Holder, kind, iconColor, Theme.Header)

        Btn.MouseEnter:Connect(function()
            if isLocked() then return end
            tween(Btn, 0.15, { BackgroundColor3 = Theme.Border })
        end)
        Btn.MouseLeave:Connect(function()
            tween(Btn, 0.15, { BackgroundColor3 = Theme.Header })
        end)
        return Btn, Holder
    end

    --// ---- NotBoxA: nhập tên + nội dung script ----
    local function createScriptDialog()
        local ACCENT = Theme.AccentPink
        local SIZE   = UDim2.fromOffset(330, 290)

        local Box = new("CanvasGroup", {
            Name = "NotBoxA",
            Visible = false,
            AnchorPoint = ANCHOR_CENTER,
            Position = CENTER,
            Size = UDim2.new(),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            GroupTransparency = 1,
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

        label(Box, {
            Size = UDim2.new(1, -32, 0, 20),
            Position = UDim2.fromOffset(16, 14),
            Text = "ADD SCRIPT",
            TextSize = 13,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Sakura,
            ZIndex = 52,
        })

        local function fieldLabel(text, y)
            label(Box, {
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
        fieldLabel("Script Name", 42)
        local NameBox = new("TextBox", {
            Position = UDim2.fromOffset(16, 62),
            Size = UDim2.new(1, -32, 0, 32),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "Enter your name script here",
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

        -- TextBoxA2: Script (nằm trong khung cuộn để script dài vẫn xem được)
        fieldLabel("Script", 102)
        local CodeHolder = new("ScrollingFrame", {
            Position = UDim2.fromOffset(16, 122),
            Size = UDim2.new(1, -32, 0, 96),
            BackgroundColor3 = Theme.PanelAlt,
            BorderSizePixel = 0,
            ScrollBarThickness = 4,
            ScrollBarImageColor3 = Theme.AccentPink,
            CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            ZIndex = 52,
        }, Box)
        corner(CodeHolder, 6)
        local CodeStroke = stroke(CodeHolder)

        local CodeBox = new("TextBox", {
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            PlaceholderText = "Enter your script here",
            PlaceholderColor3 = Theme.SubText,
            ClearTextOnFocus = false,
            MultiLine = true,
            TextWrapped = true,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            ZIndex = 53,
        }, CodeHolder)
        padding(CodeBox, 8, 8, 6, 6)
        new("UISizeConstraint", { MinSize = Vector2.new(0, 96) }, CodeBox)
        bindBoxFocus(CodeBox, CodeStroke)

        new("Frame", {
            Size = UDim2.new(1, -32, 0, 1),
            Position = UDim2.new(0, 16, 1, -60),
            BackgroundColor3 = Theme.Border,
            BackgroundTransparency = 0.5,
            BorderSizePixel = 0,
            ZIndex = 52,
        }, Box)

        local function option(text, pos, bg, textColor, outlined)
            local Btn = new("TextButton", {
                Size = UDim2.new(0.5, -22, 0, 34),
                Position = pos,
                BackgroundColor3 = bg,
                Text = text,
                Font = Enum.Font.GothamBold,
                TextSize = 14,
                TextColor3 = textColor,
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
                    tween(Btn, 0.15, { BackgroundColor3 = bg:Lerp(WHITE, 0.15) })
                end
            end)
            Btn.MouseLeave:Connect(function()
                if outlined then
                    tween(Btn, 0.15, { BackgroundColor3 = bg, TextColor3 = textColor })
                    tween(S, 0.15, { Color = Theme.Border })
                else
                    tween(Btn, 0.15, { BackgroundColor3 = bg })
                end
            end)
            return Btn
        end

        local Save   = option("Save", UDim2.new(0, 16, 1, -46), ACCENT, Theme.Background)
        local Cancel = option("Cancel", UDim2.new(1, -16, 1, -46), Theme.PanelAlt, Theme.Text, true)
        Cancel.AnchorPoint = Vector2.new(1, 0)

        local hideToken = 0

        local function show()
            hideToken += 1
            setOverlay(true)
            Box.Visible = true
            Box.GroupTransparency = 1
            Box.Size = UDim2.new()
            tween(Box, BUBBLE_IN_TIME, { Size = SIZE }, EASE_QUAD, DIR_OUT)
            tween(Box, FADE_IN_TIME, { GroupTransparency = 0 }, EASE_QUAD, DIR_OUT)
        end

        local function hide()
            hideToken += 1
            local token = hideToken
            NameBox:ReleaseFocus()
            CodeBox:ReleaseFocus()
            setOverlay(false)
            local sizeTween = tween(Box, BUBBLE_OUT_TIME, { Size = UDim2.new() }, EASE_QUAD, DIR_IN)
            tween(Box, FADE_OUT_TIME, { GroupTransparency = 1 }, EASE_QUAD, DIR_IN)
            sizeTween.Completed:Connect(function(state)
                if state ~= Enum.PlaybackState.Completed or token ~= hideToken then return end
                Box.Visible = false
            end)
        end

        Cancel.MouseButton1Click:Connect(hide)

        return {
            Box = Box, show = show, hide = hide,
            Save = Save, Cancel = Cancel,
            NameBox = NameBox, NameStroke = NameStroke,
            CodeBox = CodeBox, CodeStroke = CodeStroke,
        }
    end

    local ScriptDialog = createScriptDialog()

    do
        -- Function panel 1: ghim phía trên, không khung / không viền
        local Pinned = new("Frame", {
            Name = "FunctionPanel1",
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 36),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        }, ScriptTab)
        padding(Pinned, 4, 0)

        label(Pinned, {
            Size = UDim2.new(1, -80, 1, 0),
            Text = "Other Script",
            TextSize = 15,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextColor3 = Theme.Text,
        })
        local AddBtn = CreateStyledButton(Pinned, "+ Add", 70) -- ButtonA

        -- Function panel 2: danh sách function tạo từ NotBoxA (khung cuộn riêng, "Other Script" ở trên luôn đứng yên)
        local ListPanel = new("ScrollingFrame", {
            Name = "FunctionPanel2",
            LayoutOrder = 2,
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
        padding(ListPanel, 2, 8, 2, 2) -- chừa chỗ cho viền UIStroke của hàng (ScrollingFrame cắt phần viền lòi ra ngoài) + thanh cuộn

        -- Chiều cao khung danh sách = phần còn lại của FunctionScroll sau khi trừ hàng ghim -> tab Script không cuộn ngoài
        local PINNED_HEIGHT, TAB_LIST_GAP = 36, 10
        local function fitListPanel()
            local h = FunctionScroll.AbsoluteSize.Y - CONTENT_EDGE * 2 - PINNED_HEIGHT - TAB_LIST_GAP - 2
            ListPanel.Size = UDim2.new(1, 0, 0, math.max(80, h))
        end
        FunctionScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitListPanel)
        fitListPanel()

        -- NotBoxDe: hàng đang chờ xác nhận xoá
        local pendingDelete -- { entry = ..., row = ... }

        DeleteDialog.Yes.MouseButton1Click:Connect(function()
            local target = pendingDelete
            pendingDelete = nil
            DeleteDialog.hide()
            if not target then return end
            local idx = table.find(ScriptList, target.entry)
            if idx then table.remove(ScriptList, idx) end
            saveScriptList()
            if target.row.Parent then target.row:Destroy() end
        end)

        local rowOrder = 0
        local function CreateScriptRow(entry)
            rowOrder += 1
            local Row, Left = CreateInfoRow(ListPanel, entry.name)
            Row.Name = "Script_" .. rowOrder
            Row.LayoutOrder = rowOrder

            Left.Size = UDim2.new(1, -76, 1, 0)
            local Title = Left:FindFirstChild("Title")
            Title.AutomaticSize = Enum.AutomaticSize.None
            Title.Size = UDim2.new(1, 0, 1, 0)
            Title.TextTruncate = Enum.TextTruncate.AtEnd

            local PLAY_COLOR, DELETE_COLOR = Theme.AccentPink, Theme.Danger
            local ExecBtn, ExecIcon = CreateIconButton(Row, "play", 0, PLAY_COLOR)
            local DelBtn = CreateIconButton(Row, "delete", 34, DELETE_COLOR)

            ExecBtn.MouseButton1Click:Connect(function()
                if isLocked() then return end
                task.spawn(function()
                    local fn, err
                    if typeof(loadstring) == "function" then
                        fn, err = loadstring(entry.script)
                    else
                        err = "loadstring is not available"
                    end
                    local ok = fn ~= nil
                    if fn then ok, err = pcall(fn) end
                    if not ok then
                        warn(("[%s] Script '%s' error: %s"):format(UI_NAME, entry.name, tostring(err)))
                    end
                    tintIcon(ExecIcon, ok and Theme.Sakura or Theme.Danger)
                    task.delay(1, function()
                        if ExecIcon.Parent then tintIcon(ExecIcon, PLAY_COLOR) end
                    end)
                end)
            end)

            DelBtn.MouseButton1Click:Connect(function()
                if isLocked() then return end
                pendingDelete = { entry = entry, row = Row }
                local name = entry.name
                if #name > 30 then name = name:sub(1, 30) .. "..." end
                DeleteDialog.Message.Text = ('Do you want to delete "%s"?'):format(name)
                DeleteDialog.show()
            end)
        end

        loadScriptList()
        for _, entry in ipairs(ScriptList) do CreateScriptRow(entry) end

        AddBtn.MouseButton1Click:Connect(function()
            if isLocked() then return end
            ScriptDialog.show()
        end)

        -- Options 1: Save
        ScriptDialog.Save.MouseButton1Click:Connect(function()
            local name = ScriptDialog.NameBox.Text:match("^%s*(.-)%s*$")
            local code = ScriptDialog.CodeBox.Text
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

            local entry = { name = name, script = code }
            ScriptList[#ScriptList + 1] = entry
            saveScriptList()
            CreateScriptRow(entry)

            ScriptDialog.NameBox.Text = ""
            ScriptDialog.CodeBox.Text = ""
            ScriptDialog.hide()
        end)
    end

    return ScriptDialog
end
