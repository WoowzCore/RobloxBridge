local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Value = {
	Name = "RobloxBridge",
	DefaultPort = 4949,
	PingInterval = 3,
}

local function make(ClassName, Props, Parent)
	local Obj = Instance.new(ClassName)
	for Key, Val in pairs(Props) do
		Obj[Key] = Val
	end
	Obj.Parent = Parent
	return Obj
end

local Toolbar = plugin:CreateToolbar(Value.Name)
local ToggleButton = Toolbar:CreateButton(Value.Name, "Переключить окно " .. Value.Name, "")

local Widget = plugin:CreateDockWidgetPluginGui(Value.Name .. "Widget", DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false, false,
	300, 400, 250, 200
))
Widget.Title = Value.Name

-- ----------------------------------------------------------------------
-- Состояние

local CurrentPort = plugin:GetSetting("Port") or Value.DefaultPort
local IsPinging = false
local LastPingClock = 0

local function getServerUrl()
	return "http://localhost:" .. tostring(CurrentPort)
end

local function getPlaceInfo()
	return {
		PlaceId = game.PlaceId,
		UniverseId = game.GameId,
		PlaceName = game.Name,
		RobloxVersion = version(),
	}
end

-- ----------------------------------------------------------------------
-- Интерфейс

local MainFrame = make("Frame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = Color3.fromRGB(30, 30, 35),
	BorderSizePixel = 0,
}, Widget)

local TitleBar = make("Frame", {
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundColor3 = Color3.fromRGB(20, 20, 24),
	BorderSizePixel = 0,
}, MainFrame)

make("TextLabel", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Text = Value.Name,
	TextColor3 = Color3.fromRGB(240, 240, 240),
	Font = Enum.Font.SourceSansBold,
	TextSize = 20,
}, TitleBar)

local Content = make("Frame", {
	Size = UDim2.new(1, 0, 1, -40),
	Position = UDim2.new(0, 0, 0, 40),
	BackgroundTransparency = 1,
}, MainFrame)

make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, Content)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	PaddingTop = UDim.new(0, 10),
}, Content)

-- Статус сервера (виден всегда)

local StatusRow = make("Frame", {
	Size = UDim2.new(1, 0, 0, 18),
	BackgroundTransparency = 1,
	LayoutOrder = 1,
}, Content)

local StatusDot = make("Frame", {
	Size = UDim2.fromOffset(10, 10),
	Position = UDim2.new(0, 0, 0, 4),
	BackgroundColor3 = Color3.fromRGB(200, 60, 60),
	BorderSizePixel = 0,
}, StatusRow)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, StatusDot)

local StatusText = make("TextLabel", {
	Size = UDim2.new(1, -18, 1, 0),
	Position = UDim2.new(0, 18, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.SourceSans,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(220, 220, 220),
	TextXAlignment = Enum.TextXAlignment.Left,
}, StatusRow)

local ChangePortButton = make("TextButton", {
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	Text = "Изменить порт",
	Font = Enum.Font.SourceSans,
	TextSize = 12,
	TextColor3 = Color3.fromRGB(120, 170, 255),
	TextXAlignment = Enum.TextXAlignment.Left,
	AutoButtonColor = false,
	LayoutOrder = 2,
}, Content)

local PortInput = make("TextBox", {
	Size = UDim2.new(1, 0, 0, 24),
	BackgroundColor3 = Color3.fromRGB(45, 45, 52),
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.SourceSans,
	TextSize = 14,
	Text = tostring(CurrentPort),
	ClearTextOnFocus = false,
	Visible = false,
	LayoutOrder = 3,
}, Content)

-- Блок проекта (виден только когда сервер найден)

local ProjectFrame = make("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Visible = false,
	LayoutOrder = 4,
}, Content)

make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, ProjectFrame)

local InfoLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Font = Enum.Font.SourceSansBold,
	TextSize = 15,
	TextColor3 = Color3.fromRGB(240, 240, 240),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	LayoutOrder = 1,
}, ProjectFrame)

local WarnLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Font = Enum.Font.SourceSans,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	LayoutOrder = 2,
}, ProjectFrame)

local CreateButton = make("TextButton", {
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = Color3.fromRGB(46, 125, 50),
	Text = "Создать проект из этого плейса",
	Font = Enum.Font.SourceSansBold,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0,
	LayoutOrder = 3,
}, ProjectFrame)

-- ----------------------------------------------------------------------
-- Отрисовка по ответу /ping (State == nil, если сервер не найден)

local Green = Color3.fromRGB(110, 220, 130)
local Yellow = Color3.fromRGB(230, 180, 60)
local Red = Color3.fromRGB(235, 90, 90)

local PlaceMessages = {
	match = { "✔ Плейс совпадает с проектом", Green },
	unbound = { "⚠ Проект не привязан к плейсу (создан до публикации)", Yellow },
	["local"] = { "⚠ Плейс не сохранён в Roblox, привязку проверить нельзя", Yellow },
	sameGame = { "⚠ Это другой плейс той же игры, чем в проекте", Yellow },
	other = { "⛔ Проект привязан к другой игре! Не перезаписывайте файлы", Red },
}

local function render(State)
	if not State then
		StatusDot.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
		StatusText.Text = ("Поиск сервера (порт %d)..."):format(CurrentPort)
		ProjectFrame.Visible = false
		return
	end

	StatusDot.BackgroundColor3 = Color3.fromRGB(60, 200, 90)
	StatusText.Text = ("Подключено (порт %d)"):format(CurrentPort)
	ProjectFrame.Visible = true

	CreateButton.Visible = false
	WarnLabel.Text = ""

	if State.project then
		InfoLabel.Text = "Проект: " .. tostring(State.project)

		local Msg = PlaceMessages[State.place]
		if Msg then
			WarnLabel.Text = Msg[1]
			WarnLabel.TextColor3 = Msg[2]
		end
	elseif State.creating then
		InfoLabel.Text = "Выберите папку в окне RobloxBridge..."
	else
		InfoLabel.Text = "Проект не создан."
		CreateButton.Visible = true
	end
end

render(nil)

-- ----------------------------------------------------------------------
-- Пинг

local function pingServer()
	if IsPinging then return end
	IsPinging = true

	task.spawn(function()
		local Url = ("%s/ping?place=%d&universe=%d"):format(getServerUrl(), game.PlaceId, game.GameId)

		local Ok, Body = pcall(function()
			return HttpService:GetAsync(Url, true)
		end)

		local State = nil
		if Ok then
			local DecodeOk, Decoded = pcall(function()
				return HttpService:JSONDecode(Body)
			end)

			if DecodeOk and type(Decoded) == "table" then
				State = Decoded
			end
		end

		render(State)
		IsPinging = false
	end)
end

RunService.Heartbeat:Connect(function()
	if not Widget.Enabled then return end

	local Now = os.clock()
	if Now - LastPingClock >= Value.PingInterval then
		LastPingClock = Now
		pingServer()
	end
end)

-- ----------------------------------------------------------------------
-- Порт

ChangePortButton.MouseButton1Click:Connect(function()
	PortInput.Visible = not PortInput.Visible
end)

PortInput.FocusLost:Connect(function()
	local Number = tonumber(PortInput.Text)

	if Number and Number >= 1 and Number <= 65535 then
		CurrentPort = math.floor(Number)
		PortInput.Text = tostring(CurrentPort)
		plugin:SetSetting("Port", CurrentPort)

		render(nil)
		LastPingClock = 0
	else
		PortInput.Text = tostring(CurrentPort)
	end
end)

-- ----------------------------------------------------------------------
-- Создание проекта

CreateButton.MouseButton1Click:Connect(function()
	CreateButton.Visible = false
	InfoLabel.Text = "Отправляю запрос..."

	task.spawn(function()
		local Ok, Err = pcall(function()
			HttpService:PostAsync(
				getServerUrl() .. "/project/create",
				HttpService:JSONEncode(getPlaceInfo()),
				Enum.HttpContentType.ApplicationJson
			)
		end)

		if Ok then
			LastPingClock = 0 -- сразу обновить состояние
		else
			InfoLabel.Text = "Ошибка: " .. tostring(Err)
		end
	end)
end)

-- ----------------------------------------------------------------------

ToggleButton.Click:Connect(function()
	Widget.Enabled = not Widget.Enabled
end)

Widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	ToggleButton:SetActive(Widget.Enabled)

	if Widget.Enabled then
		LastPingClock = 0 -- пинг сразу при открытии окна
	end
end)