local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Value = {
	Name = "RobloxBridge",
	DefaultPort = 4949,
	PingInterval = 3,
}

local White = Color3.fromRGB(235, 235, 235)
local Green = Color3.fromRGB(110, 220, 130)
local Yellow = Color3.fromRGB(230, 180, 60)
local Red = Color3.fromRGB(235, 90, 90)

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
local ActionPath = nil -- куда POST-ит кнопка действия

local function getServerUrl()
	return "http://localhost:" .. tostring(CurrentPort)
end

local function getPlaceInfo()
	return {
		PlaceId = game.PlaceId,
		UniverseId = game.GameId,
	}
end

-- ----------------------------------------------------------------------
-- Интерфейс

local MainFrame = make("Frame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = Color3.fromRGB(30, 30, 35),
	BorderSizePixel = 0,
}, Widget)

make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundColor3 = Color3.fromRGB(20, 20, 24),
	BorderSizePixel = 0,
	Text = Value.Name,
	TextColor3 = White,
	Font = Enum.Font.SourceSansBold,
	TextSize = 20,
}, MainFrame)

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
	BorderSizePixel = 0,
}, StatusRow)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, StatusDot)

local StatusText = make("TextLabel", {
	Size = UDim2.new(1, -18, 1, 0),
	Position = UDim2.new(0, 18, 0, 0),
	BackgroundTransparency = 1,
	Font = Enum.Font.SourceSans,
	TextSize = 14,
	TextColor3 = White,
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
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	LayoutOrder = 1,
}, ProjectFrame)

local ActionButton = make("TextButton", {
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = Color3.fromRGB(46, 125, 50),
	Font = Enum.Font.SourceSansBold,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(255, 255, 255),
	BorderSizePixel = 0,
	Visible = false,
	LayoutOrder = 2,
}, ProjectFrame)

-- ----------------------------------------------------------------------
-- Отрисовка по ответу /ping (State == nil, если сервер не найден)

local function setInfo(Text, Color)
	InfoLabel.Text = Text
	InfoLabel.TextColor3 = Color
end

local function setAction(Text, Path)
	ActionButton.Text = Text
	ActionButton.Visible = true
	ActionPath = Path
end

local function render(State)
	ActionButton.Visible = false
	ActionPath = nil

	if not State then
		StatusDot.BackgroundColor3 = Red
		StatusText.Text = ("Поиск сервера (порт %d)..."):format(CurrentPort)
		ProjectFrame.Visible = false
		return
	end

	StatusDot.BackgroundColor3 = Green
	StatusText.Text = ("Подключено (порт %d)"):format(CurrentPort)
	ProjectFrame.Visible = true

	local Place = State.place
	local Project = tostring(State.project)

	if Place == "local" then
		setInfo("⚠ Плейс не опубликован в Roblox. File → Publish to Roblox (можно оставить приватным).", Yellow)
	elseif Place == "noProject" then
		if State.creating then
			setInfo("Выберите папку в окне RobloxBridge...", Yellow)
		else
			setInfo("Для этой игры нет проекта.", White)
			setAction("Создать проект для этой игры", "/project/create")
		end
	elseif Place == "otherGame" then
		setInfo(("⛔ В приложении открыт проект «%s» другой игры. Закройте его в приложении."):format(Project), Red)
	elseif Place == "newPlace" then
		setInfo(("Проект «%s». Этого плейса в нём ещё нет."):format(Project), White)
		setAction("Добавить этот плейс в проект", "/place/add")
	elseif Place == "ready" then
		setInfo(("✔ Проект «%s», папка плейса: Places/%s"):format(Project, tostring(State.folder)), Green)
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
-- Кнопка действия (создать проект / добавить плейс)

ActionButton.MouseButton1Click:Connect(function()
	local Path = ActionPath
	if not Path then return end

	ActionButton.Visible = false
	InfoLabel.Text = "Отправляю запрос..."

	task.spawn(function()
		local Ok, Err = pcall(function()
			HttpService:PostAsync(
				getServerUrl() .. Path,
				HttpService:JSONEncode(getPlaceInfo()),
				Enum.HttpContentType.ApplicationJson
			)
		end)

		if not Ok then
			setInfo("Ошибка: " .. tostring(Err), Red)
		end

		LastPingClock = 0 -- сразу обновить состояние
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