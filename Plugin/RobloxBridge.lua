local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Port = tonumber(plugin:GetSetting("Port")) or 4949
local State = { Found = false, Place = "", Project = "", Folder = "", Creating = false, Dump = nil }
local Busy, Probing = false, false

local Green, Yellow, Red = Color3.fromRGB(70, 170, 90), Color3.fromRGB(220, 170, 40), Color3.fromRGB(225, 80, 80)

local function Theme(Color) return settings().Studio.Theme:GetColor(Color) end
local function make(Class, Props, Parent)
	local O = Instance.new(Class)
	for K, V in pairs(Props) do O[K] = V end
	O.Parent = Parent
	return O
end

-- ===== HTTP =====
local function Get(Path)
	local Ok, R = pcall(HttpService.GetAsync, HttpService, "http://localhost:" .. Port .. Path)
	if not Ok then return nil end
	local Ok2, D = pcall(HttpService.JSONDecode, HttpService, R)
	if Ok2 then return D end
	return nil
end

local function Post(Path, Body)
	local Ok, R = pcall(HttpService.PostAsync, HttpService, "http://localhost:" .. Port .. Path,
		HttpService:JSONEncode(Body or {}), Enum.HttpContentType.ApplicationJson)
	if not Ok then return nil, tostring(R) end
	local Ok2, D = pcall(HttpService.JSONDecode, HttpService, R)
	return Ok2 and D or {}, nil
end

local function PlaceInfo() return { PlaceId = game.PlaceId, UniverseId = game.GameId } end

-- ===== UI =====
local Widget = plugin:CreateDockWidgetPluginGui("RobloxBridge",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 300, 300, 240, 160))
Widget.Title = "RobloxBridge"
local Toggle = plugin:CreateToolbar("RobloxBridge"):CreateButton("RobloxBridge", "Открыть панель RobloxBridge", "")
Toggle.ClickableWhenViewportHidden = true
Toggle.Click:Connect(function() Widget.Enabled = not Widget.Enabled end)

local Root = make("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0,
	BackgroundColor3 = Theme(Enum.StudioStyleGuideColor.MainBackground) }, Widget)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, Root)
make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, Root)

local function Label(Order)
	return make("TextLabel", { LayoutOrder = Order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.SourceSans, TextSize = 14, Text = "",
		TextColor3 = Theme(Enum.StudioStyleGuideColor.MainText) }, Root)
end

local Status, DumpLine = Label(1), Label(2)
local Action = make("TextButton", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 28), Visible = false, BorderSizePixel = 0,
	Font = Enum.Font.SourceSans, TextSize = 14, Text = "",
	BackgroundColor3 = Theme(Enum.StudioStyleGuideColor.Button),
	TextColor3 = Theme(Enum.StudioStyleGuideColor.ButtonText) }, Root)
local PortLink = make("TextButton", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
	Font = Enum.Font.SourceSans, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Color3.fromRGB(90, 160, 255), Text = "" }, Root)
local PortBox = make("TextBox", { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 24), Visible = false, ClearTextOnFocus = false,
	Font = Enum.Font.SourceSans, TextSize = 14, Text = "", PlaceholderText = "Порт (1024–65535), Enter",
	BackgroundColor3 = Theme(Enum.StudioStyleGuideColor.InputFieldBackground),
	TextColor3 = Theme(Enum.StudioStyleGuideColor.MainText) }, Root)

local function Render()
	local Dim = Theme(Enum.StudioStyleGuideColor.DimmedText)
	Action.Visible = false
	DumpLine.Text = ""
	PortLink.Visible = not State.Found
	PortLink.Text = "Изменить порт (сейчас " .. Port .. ")"
	if State.Found then PortBox.Visible = false end

	if not State.Found then
		Status.Text = "Поиск сервера RobloxBridge (порт " .. Port .. ")…"
		Status.TextColor3 = Dim
		return
	end

	local P, Dump = State.Place, State.Dump
	if P == "noDump" then
		Status.Text = "✖ Нужен файл дампа API. В окне RobloxBridge нажмите «Скачать на GitHub», скачайте файл и выберите его."
		Status.TextColor3 = Red
	elseif P == "local" then
		Status.Text = "Плейс не опубликован. File → Publish to Roblox (можно приватным)."
		Status.TextColor3 = Yellow
	elseif P == "noProject" then
		if State.Creating then
			Status.Text = "Выберите папку в окне RobloxBridge…"
			Status.TextColor3 = Dim
		else
			Status.Text = "Проект для этой игры не открыт."
			Status.TextColor3 = Dim
			Action.Text = "Создать проект для этой игры"
			Action.Visible = true
		end
	elseif P == "otherGame" then
		Status.Text = "Открыт проект «" .. State.Project .. "», но это другая игра. Закройте или смените проект в приложении."
		Status.TextColor3 = Red
	elseif P == "newPlace" then
		Status.Text = "Проект «" .. State.Project .. "»: этого плейса в нём ещё нет."
		Status.TextColor3 = Yellow
		Action.Text = "Добавить этот плейс в проект"
		Action.Visible = true
	elseif P == "ready" then
		Status.Text = "✔ Проект «" .. State.Project .. "», папка плейса: Places/" .. State.Folder
		Status.TextColor3 = Green
	end

	if Probing and State.ProbeText then
		DumpLine.Text = State.ProbeText
		DumpLine.TextColor3 = Dim
	elseif State.ProbeError then
		DumpLine.Text = State.ProbeError
		DumpLine.TextColor3 = Red
	elseif Dump then
		local Marks = { ok = "✔ ", checking = "… " }
		local Colors = { ok = Green, checking = Dim, missing = Red, broken = Red }
		DumpLine.Text = (Marks[Dump.state] or "⚠ ") .. tostring(Dump.message)
			.. "\nStudio: " .. tostring(Dump.studio)
			.. "\nДамп принят для: " .. tostring(Dump.dumpStudio)
			.. "\nХеш файла: " .. tostring(Dump.hash)
			.. ", классов " .. tostring(Dump.classes) .. ", свойств " .. tostring(Dump.props)
		DumpLine.TextColor3 = Colors[Dump.state] or Yellow
	end
end

-- ===== Проверка дампа в этой Studio (безопасная) =====
-- Только короткий список. Сервисы не создаём, берём уже существующие (FindService).
local ProbeClasses = {
	"Part", "MeshPart", "WedgePart", "SpawnLocation", "Model", "Folder", "Attachment", "Weld", "WeldConstraint",
	"Script", "LocalScript", "ModuleScript", "PointLight", "SpotLight", "Sound", "Decal", "Texture",
	"ScreenGui", "Frame", "TextLabel", "TextButton", "ImageLabel", "UICorner", "UIListLayout",
	"BoolValue", "StringValue", "NumberValue", "ObjectValue",
}
local ProbeServices = { "Workspace", "Lighting", "SoundService", "ReplicatedStorage" }
local ProbeCooldown, LastProbe = 60, -1000

local function Probe()
	if Probing or os.clock() - LastProbe < ProbeCooldown then return end
	Probing = true
	LastProbe = os.clock()

	-- Если прошлая проверка не закончилась (Studio упала), пропускаем и сбрасываем флаг
	if plugin:GetSetting("ProbeBusy") then
		Post("/dump/probe", { Checked = 0, Missing = 0, Classes = 0, Samples = {}, Skipped = true })
		plugin:SetSetting("ProbeBusy", nil)
		State.ProbeText = nil
		Probing = false
		Render()
		return
	end

	task.spawn(function()
		local Ok, Err = pcall(function()
			local Schema = Get("/schema")
			if not Schema then return end
			plugin:SetSetting("ProbeBusy", true)

			local Total = #ProbeClasses + #ProbeServices
			local Done, Checked, Missing, Samples = 0, 0, 0, {}
			local function Miss(S)
				Missing += 1
				if #Samples < 30 then table.insert(Samples, S) end
			end
			local function Step(Name)
				Done += 1
				State.ProbeText = "Проверка дампа: " .. Done .. "/" .. Total .. " (" .. Name .. ")"
				Render()
				task.wait()
			end
			local function CheckProps(Inst, ClassName, C)
				for Prop in pairs(C.Props) do
					Checked += 1
					local Ok3, E = pcall(function() return Inst[Prop] end)
					if not Ok3 and string.find(tostring(E), "is not a valid member", 1, true) then
						Miss(ClassName .. "." .. Prop)
					end
				end
			end

			for _, ClassName in ipairs(ProbeClasses) do
				local C = Schema.Classes[ClassName]
				if not C then
					Miss(ClassName)
				else
					local Ok2, I = pcall(Instance.new, ClassName)
					if Ok2 then
						CheckProps(I, ClassName, C)
						I:Destroy()
					else
						Miss(ClassName)
					end
				end
				Step(ClassName)
			end

			for _, ServiceName in ipairs(ProbeServices) do
				local C = Schema.Classes[ServiceName]
				local Svc = game:FindService(ServiceName)
				if C and Svc then CheckProps(Svc, ServiceName, C) end
				Step(ServiceName)
			end

			plugin:SetSetting("ProbeBusy", nil)
			Post("/dump/probe", { Checked = Checked, Missing = Missing, Classes = Total, Samples = Samples })

			State.ProbeText = nil
			State.ProbeError = nil
		end)
		if not Ok then
			plugin:SetSetting("ProbeBusy", nil)
			State.ProbeText = nil
			State.ProbeError = "✖ Проверка дампа не удалась: " .. tostring(Err)
			warn("RobloxBridge: проверка дампа не удалась: " .. tostring(Err))
		end
		Probing = false
		Render()
	end)
end

-- ===== Пинг =====
local function Tick()
	if Busy then return end
	Busy = true
	local Q = "?place=" .. game.PlaceId .. "&universe=" .. game.GameId .. "&studio=" .. HttpService:UrlEncode(version())
	local D = Get("/ping" .. Q)
	if D then
		State.Found = true
		State.Place = D.place or ""
		State.Project = D.project or ""
		State.Folder = D.folder or ""
		State.Creating = D.creating == true
		State.Dump = D.dump
	else
		State.Found = false
	end
	Render()
	Busy = false
	if D and D.dump and D.dump.probe then Probe() end
end

Action.MouseButton1Click:Connect(function()
	if State.Place == "noProject" then
		Post("/project/create", PlaceInfo())
	elseif State.Place == "newPlace" then
		Post("/place/add", PlaceInfo())
	end
	Tick()
end)

PortLink.MouseButton1Click:Connect(function()
	PortBox.Visible = not PortBox.Visible
	PortBox.Text = tostring(Port)
end)
PortBox.FocusLost:Connect(function(Enter)
	if not Enter then return end
	local N = tonumber(PortBox.Text)
	if N and N >= 1024 and N <= 65535 then
		Port = math.floor(N)
		plugin:SetSetting("Port", Port)
		PortBox.Visible = false
		Tick()
	end
end)

local Last = 0
RunService.Heartbeat:Connect(function()
	if os.clock() - Last >= 3 then
		Last = os.clock()
		task.spawn(Tick)
	end
end)

Render()
task.spawn(Tick)