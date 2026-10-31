local Value = {
	Plugin = {
		Name = "RobloxBridge"
	}
}

local Toolbar = plugin:CreateToolbar(Value.Plugin.Name)
local ToggleButton = Toolbar:CreateButton(Value.Plugin.Name, "Переключить окно " .. Value.Plugin.Name, "")

local Widget = plugin:CreateDockWidgetPluginGui(Value.Plugin.Name .. "Widget", DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false, false,
	300, 400, 250, 200
))
Widget.Title = Value.Plugin.Name

-- ----------------------------------------------------------------------

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(1, 0, 1, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = Widget

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 40)
TitleBar.Position = UDim2.new(0, 0, 0, 0)
TitleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, 0, 1, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "RobloxBridge"
TitleLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
TitleLabel.Font = Enum.Font.SourceSansBold
TitleLabel.TextSize = 20
TitleLabel.Parent = TitleBar

local ContentFrame = Instance.new("Frame")
ContentFrame.Size = UDim2.new(1, 0, 1, -40)
ContentFrame.Position = UDim2.new(0, 0, 0, 40)
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent = MainFrame

-- ----------------------------------------------------------------------

ToggleButton.Click:Connect(function()
	Widget.Enabled = not Widget.Enabled
end)

Widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	ToggleButton:SetActive(Widget.Enabled)
end)