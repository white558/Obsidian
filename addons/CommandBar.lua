
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

    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Parent = ScreenGui
    MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    MainFrame.Position = UDim2.new(0.5, 0, 0.3, 0)
    MainFrame.Size = UDim2.new(0, 400, 0, 45)
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
    SearchBox.Size = UDim2.new(1, -30, 1, 0)
    SearchBox.Font = Enum.Font.Code
    SearchBox.PlaceholderText = "Search toggles, options, buttons..."
    SearchBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
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

    local UIListLayout = Instance.new("UIListLayout")
    UIListLayout.Parent = ResultsFrame
    UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local ActiveTweens = {}

    local function StopTweens()
        for _, tween in pairs(ActiveTweens) do
            if tween and tween.PlaybackState == Enum.PlaybackState.Playing then
                tween:Cancel()
            end
        end
        ActiveTweens = {}
    end

    local function ToggleVisibility(state)
        self.Enabled = state
        StopTweens()

        if state then
            MainFrame.Visible = true
            MainFrame.Size = UDim2.new(0, 400, 0, 45)
            ResultsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
            SearchBox.Text = ""

            local tween = TweenService:Create(MainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.new(0.5, 0, 0.3, 0)
            })
            table.insert(ActiveTweens, tween)
            tween:Play()

            task.wait()
            SearchBox:CaptureFocus()
        else
            local tween = TweenService:Create(MainFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.new(0.5, 0, 0.25, 0)
            })
            table.insert(ActiveTweens, tween)
            tween:Play()

            tween.Completed:Connect(function()
                if not self.Enabled then
                    MainFrame.Visible = false
                end
            end)

            SearchBox:ReleaseFocus()
        end
    end

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if input.KeyCode == self.Keybind then
            local modifierDown = true
            if self.Modifier then
                modifierDown = UserInputService:IsKeyDown(self.Modifier)
            end
            if modifierDown then
                ToggleVisibility(not self.Enabled)
            end
        end

        if self.Enabled and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            local pos = input.Position
            local aBox = MainFrame.AbsolutePosition
            local aSize = MainFrame.AbsoluteSize
            if pos.X < aBox.X or pos.X > aBox.X + aSize.X or pos.Y < aBox.Y or pos.Y > aBox.Y + aSize.Y then
                ToggleVisibility(false)
            end
        end
    end)

    local function BuildResults(query)
        for _, child in pairs(ResultsFrame:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        if query == "" then
            MainFrame.Size = UDim2.new(0, 400, 0, 45)
            return
        end

        query = query:lower()
        local matches = {}

        -- Toggles: Library.Toggles[Idx] = { Text, Value, Type="Toggle", SetValue }
        for idx, toggle in pairs(Library.Toggles or {}) do
            local label = tostring(toggle.Text or idx)
            if label:lower():find(query, 1, true) or tostring(idx):lower():find(query, 1, true) then
                table.insert(matches, { Name = label, Element = toggle, Type = "Toggle" })
            end
        end

        -- Options: Library.Options[Idx] = Slider/Dropdown/Input/KeyPicker/ColorPicker etc.
        for idx, option in pairs(Library.Options or {}) do
            local label = tostring(option.Text or idx)
            if label:lower():find(query, 1, true) or tostring(idx):lower():find(query, 1, true) then
                table.insert(matches, { Name = label, Element = option, Type = option.Type or "Option" })
            end
        end

        -- Buttons: Library.Buttons[Idx or number] = { Text, Func, Type="Button" }
        for idx, button in pairs(Library.Buttons or {}) do
            local label = tostring(button.Text or idx)
            if label:lower():find(query, 1, true) or tostring(idx):lower():find(query, 1, true) then
                table.insert(matches, { Name = label, Element = button, Type = "Button" })
            end
        end

        table.sort(matches, function(a, b) return a.Name < b.Name end)

        local displayed = math.min(#matches, 6)
        local totalHeight = displayed * 30

        MainFrame.Size = UDim2.new(0, 400, 0, 45 + totalHeight)
        ResultsFrame.CanvasSize = UDim2.new(0, 0, 0, #matches * 30)

        for i, match in ipairs(matches) do
            local Btn = Instance.new("TextButton")
            Btn.Parent = ResultsFrame
            Btn.Size = UDim2.new(1, 0, 0, 30)
            Btn.BackgroundTransparency = i % 2 == 0 and 0.95 or 1
            Btn.BackgroundColor3 = Color3.new(1, 1, 1)
            Btn.BorderSizePixel = 0
            Btn.Text = "  " .. match.Name .. " (" .. match.Type .. ")"
            Btn.Font = Enum.Font.Code
            Btn.TextSize = 14
            Btn.TextColor3 = Library.Scheme.FontColor
            Btn.TextXAlignment = Enum.TextXAlignment.Left

            Btn.MouseEnter:Connect(function()
                Btn.BackgroundTransparency = 0.8
                Btn.TextColor3 = Library.Scheme.AccentColor
            end)

            Btn.MouseLeave:Connect(function()
                Btn.BackgroundTransparency = i % 2 == 0 and 0.95 or 1
                Btn.TextColor3 = Library.Scheme.FontColor
            end)

            Btn.MouseButton1Click:Connect(function()
                local el = match.Element

                if match.Type == "Toggle" then
                    -- Toggles use :SetValue(bool)
                    el:SetValue(not el.Value)

                elseif match.Type == "Button" then
                    -- Buttons store their callback in .Func
                    if type(el.Func) == "function" then
                        el.Func()
                    elseif type(el.Callback) == "function" then
                        el.Callback()
                    end

                else
                    -- Options (Slider, Dropdown, etc.) — just focus/open if possible
                    if type(el.SetValue) == "function" and typeof(el.Value) == "boolean" then
                        el:SetValue(not el.Value)
                    end
                end

                ToggleVisibility(false)
            end)
        end
    end

    SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        BuildResults(SearchBox.Text)
    end)

    SearchBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local firstBtn = ResultsFrame:FindFirstChildOfClass("TextButton")
            if firstBtn then
                for _, conn in pairs(getconnections(firstBtn.MouseButton1Click)) do
                    conn:Fire()
                end
            end
        end
    end)
end

return CommandBar
