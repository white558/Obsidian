local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

local CommandBar = {
    Enabled = false,
    Keybind = Enum.KeyCode.K,
    Modifier = Enum.KeyCode.LeftControl,
    Library = nil,
}

function CommandBar:Init(Library)
    self.Library = Library

    local protectgui = protectgui or (syn and syn.protect_gui) or function() end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "CommandBar"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.IgnoreGuiInset = true
    protectgui(ScreenGui)
    ScreenGui.Parent = CoreGui

    -- AnchorPoint (0.5, 0) = grows DOWNWARD, searchbox stays at top
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Parent = ScreenGui
    MainFrame.AnchorPoint = Vector2.new(0.5, 0)
    MainFrame.Position = UDim2.new(0.5, 0, 0.22, 0)
    MainFrame.Size = UDim2.new(0, 420, 0, 45)
    MainFrame.BackgroundColor3 = Library.Scheme.BackgroundColor
    MainFrame.BorderSizePixel = 0
    MainFrame.ClipsDescendants = true
    MainFrame.Visible = false

    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, Library.CornerRadius or 4)
    UICorner.Parent = MainFrame

    local UIStroke = Instance.new("UIStroke")
    UIStroke.Parent = MainFrame
    UIStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    UIStroke.Color = Library.Scheme.OutlineColor
    UIStroke.Thickness = 1

    local SearchBox = Instance.new("TextBox")
    SearchBox.Name = "SearchBox"
    SearchBox.Parent = MainFrame
    SearchBox.BackgroundTransparency = 1
    SearchBox.Position = UDim2.new(0, 15, 0, 0)
    SearchBox.Size = UDim2.new(1, -30, 0, 45)
    SearchBox.Font = Enum.Font.Code
    SearchBox.PlaceholderText = "Search toggles, options, buttons..."
    SearchBox.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
    SearchBox.Text = ""
    SearchBox.TextColor3 = Library.Scheme.FontColor
    SearchBox.TextSize = 14
    SearchBox.TextXAlignment = Enum.TextXAlignment.Left
    SearchBox.ClearTextOnFocus = false

    local ResultsFrame = Instance.new("ScrollingFrame")
    ResultsFrame.Name = "ResultsFrame"
    ResultsFrame.Parent = MainFrame
    ResultsFrame.BackgroundTransparency = 1
    ResultsFrame.Position = UDim2.new(0, 0, 0, 45)
    ResultsFrame.Size = UDim2.new(1, 0, 1, -45)
    ResultsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    ResultsFrame.ScrollBarThickness = 2
    ResultsFrame.ScrollBarImageColor3 = Library.Scheme.AccentColor
    ResultsFrame.BorderSizePixel = 0
    ResultsFrame.ScrollingDirection = Enum.ScrollingDirection.Y

    local UIListLayout = Instance.new("UIListLayout")
    UIListLayout.Parent = ResultsFrame
    UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder

    -- State
    local selectedIndex = 0
    local currentButtons = {}  -- TextButton refs in order
    local recentChanges = {}   -- {Name, Element, Type} up to 6
    local subMode = nil        -- "slider" | "input" | "keypicking" | "dropdown" when a result was clicked

    local ActiveTweens = {}
    local function StopTweens()
        for _, t in pairs(ActiveTweens) do
            if t and t.PlaybackState == Enum.PlaybackState.Playing then t:Cancel() end
        end
        ActiveTweens = {}
    end

    -- ──────────────────────────────────────────────
    -- Value display helpers
    -- ──────────────────────────────────────────────
    local function GetValueString(match)
        local el = match.Element
        local t  = match.Type

        if t == "Toggle" then
            return el.Value and "ON" or "OFF"

        elseif t == "Slider" then
            local s = tostring(el.Value)
            if el.Suffix then s = s .. el.Suffix end
            if el.Prefix then s = el.Prefix .. s end
            return s

        elseif t == "Input" then
            local v = tostring(el.Value or "")
            return v == "" and '""' or v

        elseif t == "Dropdown" then
            if el.Multi then
                local parts = {}
                for k, active in pairs(el.Value or {}) do
                    if active then table.insert(parts, k) end
                end
                return #parts > 0 and table.concat(parts, ", ") or "None"
            else
                return tostring(el.Value or "None")
            end

        elseif t == "KeyPicker" then
            return tostring(el.DisplayValue or el.Value or "None")

        elseif t == "Button" then
            return ""
        end

        return ""
    end

    -- ──────────────────────────────────────────────
    -- UI helpers
    -- ──────────────────────────────────────────────
    local function SetSelected(idx)
        selectedIndex = idx
        for i, btn in ipairs(currentButtons) do
            if i == idx then
                btn.BackgroundTransparency = 0.75
                btn.TextColor3 = Library.Scheme.AccentColor
            else
                btn.BackgroundTransparency = i % 2 == 0 and 0.95 or 1
                btn.TextColor3 = Library.Scheme.FontColor
            end
        end
        -- scroll to selected
        if currentButtons[idx] then
            local itemY = (idx - 1) * 30
            ResultsFrame.CanvasPosition = Vector2.new(0, math.max(0, itemY - 60))
        end
    end

    local function ResizeFrame(resultCount)
        local shown = math.min(resultCount, 6)
        local h = 45 + shown * 30
        StopTweens()
        local t = TweenService:Create(MainFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 420, 0, h)
        })
        table.insert(ActiveTweens, t)
        t:Play()
    end

    -- ──────────────────────────────────────────────
    -- Inline editing (slider / input / keypicking)
    -- ──────────────────────────────────────────────

    -- Shows an extra row below a result button for text entry
    local function ShowInlineInput(btn, match, onSubmit)
        -- Remove old inline if any
        local old = ResultsFrame:FindFirstChild("__InlineInput")
        if old then old:Destroy() end

        local InlineRow = Instance.new("Frame")
        InlineRow.Name = "__InlineInput"
        InlineRow.Size = UDim2.new(1, 0, 0, 30)
        InlineRow.BackgroundColor3 = Library.Scheme.DarkColor or Library.Scheme.BackgroundColor
        InlineRow.BackgroundTransparency = 0.5
        InlineRow.BorderSizePixel = 0
        InlineRow.LayoutOrder = btn.LayoutOrder + 0.5
        InlineRow.Parent = ResultsFrame

        -- force it right after the clicked btn by reordering
        -- easier: just re-parent after btn
        InlineRow.LayoutOrder = btn.LayoutOrder
        btn.LayoutOrder = btn.LayoutOrder - 1

        local Box = Instance.new("TextBox")
        Box.Parent = InlineRow
        Box.BackgroundTransparency = 1
        Box.Position = UDim2.new(0, 15, 0, 0)
        Box.Size = UDim2.new(1, -15, 1, 0)
        Box.Font = Enum.Font.Code
        Box.TextSize = 13
        Box.TextColor3 = Library.Scheme.AccentColor
        Box.PlaceholderColor3 = Color3.fromRGB(100,100,100)
        Box.TextXAlignment = Enum.TextXAlignment.Left
        Box.ClearTextOnFocus = false

        if match.Type == "Slider" then
            Box.PlaceholderText = ("Enter value (%d – %d)"):format(match.Element.Min, match.Element.Max)
            Box.Text = tostring(match.Element.Value)
        elseif match.Type == "Input" then
            Box.PlaceholderText = "Enter text..."
            Box.Text = tostring(match.Element.Value or "")
        end

        ResizeFrame(#currentButtons + 1)
        task.wait()
        Box:CaptureFocus()

        Box.FocusLost:Connect(function(enter)
            if enter then onSubmit(Box.Text) end
            InlineRow:Destroy()
            ResizeFrame(#currentButtons)
            subMode = nil
        end)
    end

    -- Replaces result list with dropdown values for selection
    local function ShowDropdownPicker(match, onClose)
        local el = match.Element
        subMode = "dropdown"

        for _, c in pairs(ResultsFrame:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
        end
        currentButtons = {}
        selectedIndex = 0

        local values = el.Values or {}
        ResultsFrame.CanvasSize = UDim2.new(0, 0, 0, #values * 30)
        ResizeFrame(#values)

        for i, val in ipairs(values) do
            local isActive = el.Multi and (el.Value[val] == true) or (el.Value == val)

            local Btn = Instance.new("TextButton")
            Btn.Parent = ResultsFrame
            Btn.LayoutOrder = i
            Btn.Size = UDim2.new(1, 0, 0, 30)
            Btn.BackgroundTransparency = i % 2 == 0 and 0.95 or 1
            Btn.BackgroundColor3 = Color3.new(1,1,1)
            Btn.BorderSizePixel = 0
            Btn.Font = Enum.Font.Code
            Btn.TextSize = 14
            Btn.TextXAlignment = Enum.TextXAlignment.Left
            Btn.TextColor3 = isActive and Library.Scheme.AccentColor or Library.Scheme.FontColor
            Btn.Text = ("  %s%s"):format(el.Multi and (isActive and "[x] " or "[ ] ") or "", val)

            table.insert(currentButtons, Btn)

            Btn.MouseButton1Click:Connect(function()
                if el.Multi then
                    local newVal = {}
                    for k, v in pairs(el.Value) do newVal[k] = v end
                    newVal[val] = not newVal[val]
                    el:SetValue(newVal)
                else
                    el:SetValue(val)
                end
                -- update recent
                local found = false
                for _, r in ipairs(recentChanges) do
                    if r.Element == el then found = true break end
                end
                if not found then
                    table.insert(recentChanges, 1, match)
                    if #recentChanges > 6 then table.remove(recentChanges) end
                end
                if not el.Multi then onClose() end
                -- refresh button text for multi
                if el.Multi then
                    local stillActive = el.Value[val] == true
                    Btn.Text = ("  [%s] %s"):format(stillActive and "x" or " ", val)
                    Btn.TextColor3 = stillActive and Library.Scheme.AccentColor or Library.Scheme.FontColor
                end
            end)
        end
    end

    -- ──────────────────────────────────────────────
    -- Toggle visibility
    -- ──────────────────────────────────────────────
    local function ToggleVisibility(state)
        self.Enabled = state
        StopTweens()

        if state then
            MainFrame.Visible = true
            MainFrame.Size = UDim2.new(0, 420, 0, 45)
            SearchBox.Text = ""
            subMode = nil
            selectedIndex = 0
            task.wait()
            SearchBox:CaptureFocus()
        else
            local t = TweenService:Create(MainFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, 420, 0, 45)
            })
            table.insert(ActiveTweens, t)
            t:Play()
            t.Completed:Connect(function()
                if not self.Enabled then MainFrame.Visible = false end
            end)
            SearchBox:ReleaseFocus()
        end
    end

    -- ──────────────────────────────────────────────
    -- Build result rows
    -- ──────────────────────────────────────────────
    local function BuildRows(matches)
        for _, c in pairs(ResultsFrame:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
        end
        currentButtons = {}
        selectedIndex = 0
        subMode = nil

        ResultsFrame.CanvasSize = UDim2.new(0, 0, 0, #matches * 30)
        ResizeFrame(#matches)

        for i, match in ipairs(matches) do
            local valStr = GetValueString(match)
            local label  = match.Name .. (valStr ~= "" and ("  →  " .. valStr) or "")
            local typeTag = " (" .. match.Type .. ")"

            local Btn = Instance.new("TextButton")
            Btn.Parent = ResultsFrame
            Btn.LayoutOrder = i
            Btn.Size = UDim2.new(1, 0, 0, 30)
            Btn.BackgroundTransparency = i % 2 == 0 and 0.95 or 1
            Btn.BackgroundColor3 = Color3.new(1,1,1)
            Btn.BorderSizePixel = 0
            Btn.Font = Enum.Font.Code
            Btn.TextSize = 13
            Btn.TextColor3 = Library.Scheme.FontColor
            Btn.TextXAlignment = Enum.TextXAlignment.Left
            Btn.Text = "  " .. label .. typeTag

            table.insert(currentButtons, Btn)

            Btn.MouseEnter:Connect(function()
                SetSelected(i)
            end)

            Btn.MouseButton1Click:Connect(function()
                local el = match.Element
                local t  = match.Type

                if t == "Toggle" then
                    el:SetValue(not el.Value)
                    Btn.Text = "  " .. match.Name .. "  →  " .. GetValueString(match) .. typeTag

                elseif t == "Button" then
                    if type(el.Func) == "function" then el.Func() end
                    ToggleVisibility(false)
                    return

                elseif t == "Slider" then
                    ShowInlineInput(Btn, match, function(text)
                        local num = tonumber(text)
                        if num then
                            el:SetValue(num)
                            Btn.Text = "  " .. match.Name .. "  →  " .. GetValueString(match) .. typeTag
                        end
                    end)
                    subMode = "slider"

                elseif t == "Input" then
                    ShowInlineInput(Btn, match, function(text)
                        el:SetValue(text)
                        Btn.Text = "  " .. match.Name .. "  →  " .. GetValueString(match) .. typeTag
                    end)
                    subMode = "input"

                elseif t == "Dropdown" then
                    ShowDropdownPicker(match, function()
                        ToggleVisibility(false)
                    end)
                    return

                elseif t == "KeyPicker" then
                    subMode = "keypicking"
                    Btn.Text = "  " .. match.Name .. "  →  [press a key...]"
                    Btn.TextColor3 = Library.Scheme.AccentColor

                    local conn
                    conn = UserInputService.InputBegan:Connect(function(input, gp)
                        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
                        local keyName = input.KeyCode.Name
                        el:SetValue({keyName, el.Mode})
                        Btn.Text = "  " .. match.Name .. "  →  " .. GetValueString(match) .. typeTag
                        Btn.TextColor3 = Library.Scheme.FontColor
                        subMode = nil
                        conn:Disconnect()
                    end)
                end

                -- track recent (not buttons)
                if t ~= "Button" then
                    for idx, r in ipairs(recentChanges) do
                        if r.Element == match.Element then
                            table.remove(recentChanges, idx)
                            break
                        end
                    end
                    table.insert(recentChanges, 1, match)
                    if #recentChanges > 6 then table.remove(recentChanges) end
                end
            end)
        end
    end

    -- ──────────────────────────────────────────────
    -- Search
    -- ──────────────────────────────────────────────
    local function BuildResults(query)
        if query == "" then
            if #recentChanges > 0 then
                BuildRows(recentChanges)
            else
                for _, c in pairs(ResultsFrame:GetChildren()) do
                    if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
                end
                currentButtons = {}
                ResizeFrame(0)
            end
            return
        end

        local q = query:lower()
        local matches = {}

        for idx, el in pairs(Library.Toggles or {}) do
            local label = tostring(el.Text or idx)
            if label:lower():find(q, 1, true) or tostring(idx):lower():find(q, 1, true) then
                table.insert(matches, {Name = label, Element = el, Type = "Toggle"})
            end
        end

        for idx, el in pairs(Library.Options or {}) do
            local label = tostring(el.Text or idx)
            if label:lower():find(q, 1, true) or tostring(idx):lower():find(q, 1, true) then
                table.insert(matches, {Name = label, Element = el, Type = el.Type or "Option"})
            end
        end

        for idx, el in pairs(Library.Buttons or {}) do
            local label = tostring(el.Text or idx)
            if label:lower():find(q, 1, true) or tostring(idx):lower():find(q, 1, true) then
                table.insert(matches, {Name = label, Element = el, Type = "Button"})
            end
        end

        table.sort(matches, function(a, b) return a.Name < b.Name end)
        BuildRows(matches)
    end

    -- ──────────────────────────────────────────────
    -- Input handling
    -- ──────────────────────────────────────────────
    UserInputService.InputBegan:Connect(function(input, gp)
        -- toggle open/close
        if input.KeyCode == self.Keybind then
            local modOk = not self.Modifier or UserInputService:IsKeyDown(self.Modifier)
            if modOk then ToggleVisibility(not self.Enabled) end
            return
        end

        if not self.Enabled then return end

        -- close on outside click
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            local pos  = input.Position
            local aPos = MainFrame.AbsolutePosition
            local aSz  = MainFrame.AbsoluteSize
            if pos.X < aPos.X or pos.X > aPos.X + aSz.X or pos.Y < aPos.Y or pos.Y > aPos.Y + aSz.Y then
                ToggleVisibility(false)
            end
            return
        end

        -- keypicking mode swallows next key
        if subMode == "keypicking" then return end

        -- arrow keys + enter
        if input.KeyCode == Enum.KeyCode.Escape then
            ToggleVisibility(false)

        elseif input.KeyCode == Enum.KeyCode.Down then
            local next = math.min(selectedIndex + 1, #currentButtons)
            if next < 1 then next = 1 end
            SetSelected(next)

        elseif input.KeyCode == Enum.KeyCode.Up then
            local prev = math.max(selectedIndex - 1, 1)
            SetSelected(prev)

        elseif input.KeyCode == Enum.KeyCode.Return then
            if selectedIndex > 0 and currentButtons[selectedIndex] then
                -- fire the click signal directly via stored connection
                local btn = currentButtons[selectedIndex]
                btn.MouseButton1Click:Fire()
            end
        end
    end)

    SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        if subMode then return end
        BuildResults(SearchBox.Text)
    end)

    -- on open, show recents if any
    ToggleVisibility(false) -- ensure hidden on init
end

return CommandBar
