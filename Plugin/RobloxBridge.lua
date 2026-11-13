local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Selection = game:GetService("Selection")

local Port = tonumber(plugin:GetSetting("Port")) or 4949
local State = { Found = false, Place = "", Project = "", Folder = "", Creating = false, Dump = nil }
local Busy, Probing = false, false
local OnCommand

local Green, Yellow, Red = Color3.fromRGB(70, 170, 90), Color3.fromRGB(220, 170, 40), Color3.fromRGB(225, 80, 80)
local Orange, Blue, White = Color3.fromRGB(240, 130, 40), Color3.fromRGB(90, 160, 255), Color3.new(1, 1, 1)

-- ===== Тема и компоненты =====
local Studio = settings().Studio
local SG = Enum.StudioStyleGuideColor
local function Theme(Color) return Studio.Theme:GetColor(Color) end

local C = {
	Bg = function() return Theme(SG.MainBackground) end,
	Text = function() return Theme(SG.MainText) end,
	Dim = function() return Theme(SG.DimmedText) end,
	Card = function() return Theme(SG.MainBackground):Lerp(Theme(SG.MainText), 0.05) end,
	Line = function() return Theme(SG.Border) end,
	Btn = function() return Theme(SG.Button) end,
	BtnText = function() return Theme(SG.ButtonText) end,
	Input = function() return Theme(SG.InputFieldBackground) end,
	InputLine = function() return Theme(SG.InputFieldBorder) end,
	Accent = function() return Theme(SG.MainButton) end,
}
local function Dim() return C.Dim() end

-- Свойства, заданные функцией, перекрашиваются при смене темы
local Themed = {}
local function Bind(O, Prop, Fn)
	O[Prop] = Fn()
	if not Themed[O] then
		Themed[O] = {}
		O.Destroying:Connect(function() Themed[O] = nil end)
	end
	table.insert(Themed[O], { Prop, Fn })
end
Studio.ThemeChanged:Connect(function()
	for O, List in pairs(Themed) do
		for _, T in ipairs(List) do pcall(function() O[T[1]] = T[2]() end) end
	end
end)

local function make(Class, Props, Parent)
	local O = Instance.new(Class)
	for K, V in pairs(Props) do
		if type(V) == "function" then Bind(O, K, V) else O[K] = V end
	end
	O.Parent = Parent
	return O
end

local AutoY, Left, Top = Enum.AutomaticSize.Y, Enum.TextXAlignment.Left, Enum.TextYAlignment.Top

local function Corner(P, R) return make("UICorner", { CornerRadius = UDim.new(0, R or 6) }, P) end
local function Pad(P, T, R, B, L)
	return make("UIPadding", { PaddingTop = UDim.new(0, T), PaddingRight = UDim.new(0, R), PaddingBottom = UDim.new(0, B), PaddingLeft = UDim.new(0, L) }, P)
end
local function List(P, Gap, Dir)
	return make("UIListLayout", { Padding = UDim.new(0, Gap), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = Dir or Enum.FillDirection.Vertical }, P)
end

local function Text(Parent, Order, Str, Opt)
	Opt = Opt or {}
	return make("TextLabel", { LayoutOrder = Order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY,
		BackgroundTransparency = 1, TextWrapped = true, RichText = Opt.Rich == true,
		TextXAlignment = Left, TextYAlignment = Top,
		Font = Opt.Bold and Enum.Font.SourceSansBold or (Opt.Code and Enum.Font.Code or Enum.Font.SourceSans),
		TextSize = Opt.Size or 14, Text = Str, TextColor3 = Opt.Color or C.Text }, Parent)
end

-- Текст, который можно выделить и скопировать (Ctrl+C)
local function SelText(Parent, Order, Str, Opt)
	Opt = Opt or {}
	return make("TextBox", { LayoutOrder = Order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY,
		BackgroundTransparency = 1, BorderSizePixel = 0, TextEditable = false, ClearTextOnFocus = false,
		MultiLine = true, TextWrapped = true, TextXAlignment = Left, TextYAlignment = Top,
		Font = Opt.Code and Enum.Font.Code or Enum.Font.SourceSans, TextSize = Opt.Size or 14,
		Text = Str, TextColor3 = Opt.Color or C.Text }, Parent)
end

local function Card(Parent, Order)
	local F = make("Frame", { LayoutOrder = Order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY,
		BorderSizePixel = 0, BackgroundColor3 = C.Card }, Parent)
	Corner(F, 8)
	make("UIStroke", { Color = C.Line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, F)
	Pad(F, 10, 10, 10, 10)
	List(F, 6)
	return F
end

local PullColor, PushColor = Color3.fromRGB(45, 105, 190), Color3.fromRGB(40, 145, 80)

local function Button(Parent, Order, Str, Style, Size)
	local Solid = Style == "primary" or Style == "pull" or Style == "push"
	local Fill = Style == "pull" and PullColor or Style == "push" and PushColor
		or (Style == "primary" and C.Accent or C.Btn)
	local B = make("TextButton", { LayoutOrder = Order, Size = Size or UDim2.new(1, 0, 0, Style == "link" and 22 or 30),
		BorderSizePixel = 0, AutoButtonColor = false, TextWrapped = true, TextSize = 14, Text = Str,
		Font = Solid and Enum.Font.SourceSansBold or Enum.Font.SourceSans,
		BackgroundColor3 = Fill,
		TextColor3 = Solid and White or (Style == "link" and Blue or C.BtnText) }, Parent)
	if Style == "link" then
		B.BackgroundTransparency = 1
		B.TextXAlignment = Left
	else
		Corner(B, 6)
		B.MouseEnter:Connect(function() if B.Active then B.BackgroundTransparency = 0.18 end end)
		B.MouseLeave:Connect(function() B.BackgroundTransparency = B.Active and 0 or 0.6 end)
	end
	return B
end

local function Enable(B, On)
	B.Active = On
	B.TextTransparency = On and 0 or 0.55
	if B.BackgroundTransparency < 1 then B.BackgroundTransparency = On and 0 or 0.6 end
end

local function Click(B, Fn)
	B.MouseButton1Click:Connect(function() if B.Active then Fn() end end)
end

local function Box(Parent, Order, Height, Multi)
	local T = make("TextBox", { LayoutOrder = Order, Size = UDim2.new(1, 0, 0, Height), ClearTextOnFocus = false,
		MultiLine = Multi, TextWrapped = Multi, Font = Enum.Font.Code, TextSize = 13, BorderSizePixel = 0,
		TextXAlignment = Left, TextYAlignment = Multi and Top or Enum.TextYAlignment.Center, Text = "",
		BackgroundColor3 = C.Input, TextColor3 = C.Text, PlaceholderColor3 = C.Dim }, Parent)
	Corner(T, 6)
	make("UIStroke", { Color = C.InputLine, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, T)
	Pad(T, 4, 6, 4, 6)
	return T
end

local function HexOf(Col)
	return string.format("#%02X%02X%02X", math.floor(Col.R * 255 + 0.5), math.floor(Col.G * 255 + 0.5), math.floor(Col.B * 255 + 0.5))
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

-- ===== Главное окно =====
local Widget = plugin:CreateDockWidgetPluginGui("RobloxBridge",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 520, 260, 200))
Widget.Title = "RobloxBridge"
local Toggle = plugin:CreateToolbar("RobloxBridge"):CreateButton("RobloxBridge", "Открыть панель RobloxBridge", "")
Toggle.ClickableWhenViewportHidden = true
Toggle.Click:Connect(function() Widget.Enabled = not Widget.Enabled end)

local Root = make("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, CanvasSize = UDim2.new(),
	AutomaticCanvasSize = AutoY, ScrollBarThickness = 6, ScrollingDirection = Enum.ScrollingDirection.Y,
	BackgroundColor3 = C.Bg }, Widget)
List(Root, 8)
Pad(Root, 8, 12, 10, 8)

-- Карточка статуса
local StatusCard = Card(Root, 1)
local Row0 = make("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, StatusCard)
local Dot = make("Frame", { Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 2, 0.5, -5), BorderSizePixel = 0,
	BackgroundColor3 = C.Dim() }, Row0)
Corner(Dot, 5)
local StatusTitle = make("TextLabel", { Position = UDim2.new(0, 20, 0, 0), Size = UDim2.new(1, -20, 1, 0),
	BackgroundTransparency = 1, Font = Enum.Font.SourceSansBold, TextSize = 16, TextXAlignment = Left,
	TextTruncate = Enum.TextTruncate.AtEnd, Text = "", TextColor3 = C.Text }, Row0)
local StatusSub = Text(StatusCard, 2, "", { Color = C.Dim, Size = 13 })
local Action = Button(StatusCard, 3, "", "primary")
Action.Visible = false
local PortLink = Button(StatusCard, 4, "", "link")
PortLink.TextSize = 13
local PortBox = Box(StatusCard, 5, 28, false)
PortBox.Visible = false
PortBox.PlaceholderText = "Порт (1024–65535), Enter"
local DumpBtn = make("TextButton", { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY,
	BackgroundTransparency = 1, AutoButtonColor = false, TextWrapped = true, TextXAlignment = Left, TextYAlignment = Top,
	Font = Enum.Font.SourceSans, TextSize = 12, Text = "", Visible = false, TextColor3 = C.Dim }, StatusCard)

local DumpOpen = false

local function SetStatus(Col, Title, Sub)
	Dot.BackgroundColor3 = Col
	StatusTitle.Text = Title
	StatusSub.Text = Sub or ""
	StatusSub.Visible = (Sub or "") ~= ""
end

local function RenderDump()
	local Dump = State.Dump
	DumpBtn.Visible = false
	if not State.Found then return end
	if Probing and State.ProbeText then
		DumpBtn.Text = State.ProbeText
		DumpBtn.TextColor3 = Dim()
	elseif State.ProbeError then
		DumpBtn.Text = State.ProbeError
		DumpBtn.TextColor3 = Red
	elseif Dump then
		local Marks = { ok = "✔ ", checking = "… " }
		local Colors = { ok = Green, checking = Dim(), missing = Red, broken = Red }
		local T = (DumpOpen and "▾ " or "▸ ") .. "API-дамп: " .. (Marks[Dump.state] or "⚠ ") .. tostring(Dump.message)
		if DumpOpen then
			T ..= "\nStudio: " .. tostring(Dump.studio)
				.. "\nДамп принят для: " .. tostring(Dump.dumpStudio)
				.. "\nХеш файла: " .. tostring(Dump.hash)
				.. ", классов " .. tostring(Dump.classes) .. ", свойств " .. tostring(Dump.props)
		end
		DumpBtn.Text = T
		DumpBtn.TextColor3 = Colors[Dump.state] or Yellow
	else
		return
	end
	DumpBtn.Visible = true
end
DumpBtn.MouseButton1Click:Connect(function()
	DumpOpen = not DumpOpen
	RenderDump()
end)

local function Render()
	Action.Visible = false
	PortLink.Visible = not State.Found
	PortLink.Text = "Изменить порт (сейчас " .. Port .. ")"
	if State.Found then PortBox.Visible = false end

	if not State.Found then
		SetStatus(Dim(), "Ищу приложение…", "Сервер RobloxBridge на порту " .. Port .. ". Запустите приложение.")
		RenderDump()
		return
	end

	local P = State.Place
	if P == "noDump" then
		SetStatus(Red, "Нужен API-дамп", "В окне RobloxBridge нажмите «GitHub», скачайте файл и выберите его через «Выбрать файл…».")
	elseif P == "local" then
		SetStatus(Yellow, "Плейс не опубликован", "File → Publish to Roblox (можно приватным).")
	elseif P == "noProject" then
		if State.Creating then
			SetStatus(Dim(), "Создание проекта", "Выберите папку в окне RobloxBridge…")
		else
			SetStatus(Yellow, "Проект не открыт", "Для этой игры ещё нет проекта.")
			Action.Text = "Создать проект для этой игры"
			Action.Visible = true
		end
	elseif P == "otherGame" then
		SetStatus(Red, "Другая игра", "Открыт проект «" .. State.Project .. "» от другой игры. Закройте или смените проект в приложении.")
	elseif P == "newPlace" then
		SetStatus(Yellow, "Новый плейс", "В проекте «" .. State.Project .. "» этого плейса ещё нет.")
		Action.Text = "Добавить этот плейс в проект"
		Action.Visible = true
	elseif P == "ready" then
		SetStatus(Green, "Подключено", "Проект «" .. State.Project .. "» · Places/" .. State.Folder)
	else
		SetStatus(Dim(), "Подключено", "")
	end
	RenderDump()
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
			local function CheckProps(Inst, ClassName, Cls)
				for Prop in pairs(Cls.Props) do
					Checked += 1
					local Ok3, E = pcall(function() return Inst[Prop] end)
					if not Ok3 and string.find(tostring(E), "is not a valid member", 1, true) then
						Miss(ClassName .. "." .. Prop)
					end
				end
			end

			for _, ClassName in ipairs(ProbeClasses) do
				local Cls = Schema.Classes[ClassName]
				if not Cls then
					Miss(ClassName)
				else
					local Ok2, I = pcall(Instance.new, ClassName)
					if Ok2 then
						CheckProps(I, ClassName, Cls)
						I:Destroy()
					else
						Miss(ClassName)
					end
				end
				Step(ClassName)
			end

			for _, ServiceName in ipairs(ProbeServices) do
				local Cls = Schema.Classes[ServiceName]
				local Svc = game:FindService(ServiceName)
				if Cls and Svc then CheckProps(Svc, ServiceName, Cls) end
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
	if D and D.cmd and OnCommand then OnCommand(D.cmd) end
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

-- ===== Pull / Push / Diff =====
do
	local CHUNK, MAXSHOW = 500000, 120

	local function Base() return "http://localhost:" .. Port end
	local function Q()
		return "?place=" .. game.PlaceId .. "&universe=" .. game.GameId .. "&studio=" .. HttpService:UrlEncode(version())
	end

	local DebugOn = plugin:GetSetting("Debug") == true
	local function Cut(S)
		S = tostring(S)
		if #S > 300 then return string.sub(S, 1, 300) .. "…" end
		return S
	end

	local function Call(Path, Body, Quiet)
		local Dbg = DebugOn and not Quiet
		local Req = { Url = Base() .. Path, Method = Body and "POST" or "GET", Headers = { ["Content-Type"] = "application/json" } }
		if Dbg then Req.Headers["X-Bridge-Debug"] = "1" end
		local Json
		if Body then
			local OkJ, Res = pcall(HttpService.JSONEncode, HttpService, Body)
			if not OkJ then return nil, "не удалось упаковать запрос " .. Path .. " в JSON: " .. tostring(Res) end
			Json = Res
			Req.Body = Json
		end
		local T0 = os.clock()
		if Dbg then
			print("[Bridge] → " .. Req.Method .. " " .. Path .. " (" .. (Json and #Json or 0) .. " байт)" .. (Json and ("\n" .. Cut(Json)) or ""))
		end
		local Ok, R = pcall(HttpService.RequestAsync, HttpService, Req)
		if not Ok then
			if Dbg then print("[Bridge] ← ошибка: " .. tostring(R)) end
			return nil, "нет связи с приложением: " .. tostring(R)
		end
		if Dbg then
			print("[Bridge] ← " .. R.StatusCode .. ", " .. #R.Body .. " байт, " .. math.floor((os.clock() - T0) * 1000) .. " мс\n" .. Cut(R.Body))
		end
		local Ok2, D = pcall(HttpService.JSONDecode, HttpService, R.Body)
		if not Ok2 then D = nil end
		if not R.Success then return D, (D and D.error) or ("HTTP " .. R.StatusCode) end
		return D or {}, nil
	end

	local function Note(Lines)
		Call("/note" .. Q(), { lines = Lines })
	end

	-- ===== Прогресс и остановка =====
	local Prog = { cancel = false, locked = false, label = "", total = 0, done = 0, t0 = 0, st0 = 0,
		msg = "Остановлено пользователем", nest = false }
	;(function()
		local Fr = make("Frame", { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY,
			BackgroundTransparency = 1, Visible = false }, StatusCard)
		List(Fr, 4)
		local Lbl = Text(Fr, 1, "", { Size = 13 })
		local Back = make("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 8), BorderSizePixel = 0,
			BackgroundColor3 = C.Input }, Fr)
		Corner(Back, 4)
		local Bar = make("Frame", { Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0, BackgroundColor3 = PullColor }, Back)
		Corner(Bar, 4)
		local Sub = Text(Fr, 3, "", { Size = 12, Color = C.Dim })
		local Stop = Button(Fr, 4, "⏹ Остановить", "normal")

		local function Fmt(S)
			S = math.floor(S + 0.5)
			if S < 60 then return S .. " с" end
			if S < 3600 then return (S // 60) .. " мин " .. (S % 60) .. " с" end
			return (S // 3600) .. " ч " .. ((S % 3600) // 60) .. " мин"
		end

		local function Draw()
			local Total, Done, Now = Prog.total, Prog.done, os.clock()
			local Head = Prog.label
			if Total > 0 then
				Head ..= string.format(": %d / %d (%d%%)", Done, Total, math.min(100, math.floor(Done / Total * 100)))
				Bar.Size = UDim2.new(math.clamp(Done / Total, 0, 1), 0, 1, 0)
				Bar.BackgroundTransparency = 0
			else
				Bar.Size = UDim2.new(1, 0, 1, 0)
				Bar.BackgroundTransparency = 0.65
			end
			local Info = "Прошло " .. Fmt(Now - Prog.t0)
			local El = Now - Prog.st0
			if Total > 0 and Done > 0 and El > 2 then
				Info ..= " · осталось ~" .. Fmt(El / Done * math.max(0, Total - Done))
			end
			Lbl.Text = Head
			Sub.Text = Info
			Stop.Visible = not Prog.locked
		end

		Click(Stop, function()
			Prog.cancel = true
			Stop.Text = "Останавливаю…"
			Enable(Stop, false)
		end)

		function Prog.Start()
			Prog.cancel, Prog.locked = false, false
			Prog.label, Prog.total, Prog.done = "Подготовка", 0, 0
			Prog.t0 = os.clock()
			Prog.st0 = Prog.t0
			Stop.Text = "⏹ Остановить"
			Enable(Stop, true)
			Draw()
			Fr.Visible = true
		end
		-- Locked = true: этап нельзя прервать (кнопка скрывается)
		function Prog.Stage(Label, Total, Locked)
			if Prog.cancel and not Locked then error(Prog.msg, 0) end
			Prog.label, Prog.total, Prog.done = Label, Total or 0, 0
			Prog.locked = Locked == true
			Prog.st0 = os.clock()
		end
		function Prog.Step(Done)
			Prog.done = Done
			if Prog.cancel and not Prog.locked then error(Prog.msg, 0) end
		end
		function Prog.End() Fr.Visible = false end

		local LastRep = 0
		task.spawn(function()
			while true do
				if Fr.Visible then
					Draw()
					if Prog.Hook and os.clock() - LastRep > 1.5 then
						LastRep = os.clock()
						Prog.Hook(Lbl.Text .. " · " .. Sub.Text)
					end
				end
				task.wait(0.25)
			end
		end)
	end)()

	-- ===== Схема, значения =====
	local Schema, SchemaHash
	local PropCache, DefCache = {}, {}

	local SkipProp = { Name = true, Source = true, UniqueId = true, HistoryId = true, SourceAssetId = true,
		ScriptGuid = true, Color3uint8 = true, BrickColor = true, InitialSize = true }
	local Simple = { bool = true, int = true, float = true, double = true, int64 = true, string = true, Content = true, ContentId = true,
		Vector2 = true, Vector3 = true, UDim = true, UDim2 = true, Color3 = true, CFrame = true, Rect = true, NumberRange = true,
		Ref = true, Font = true, BrickColor = true, NumberSequence = true, ColorSequence = true, Vector3int16 = true,
		PhysicalProperties = true, Faces = true, Axes = true }
	local function Supported(T) return Simple[T] or string.sub(T, 1, 5) == "Enum:" end
	local function GetProp(I, N) return I[N] end

	local function R(X)
		if X ~= X or X == math.huge or X == -math.huge then return 0 end
		if math.abs(X) > 1e12 then return X end
		local V = math.floor(X * 1000 + 0.5) / 1000
		if V == 0 then return 0 end
		return V
	end

	local RevPath
	local function Enc(T, V)
		if T == "bool" then return { t = "b", v = V }
		elseif T == "int" or T == "float" or T == "double" or T == "int64" then return { t = "n", v = R(V) }
		elseif T == "string" then return { t = "s", v = V }
		elseif T == "Content" or T == "ContentId" then
			local U = V
			if typeof(V) ~= "string" then U = V.Uri end
			return { t = "ct", v = U or "" }
		elseif string.sub(T, 1, 5) == "Enum:" then return { t = "e", v = V.Name }
		elseif T == "Vector2" then return { t = "v2", v = { R(V.X), R(V.Y) } }
		elseif T == "Vector3" then return { t = "v3", v = { R(V.X), R(V.Y), R(V.Z) } }
		elseif T == "UDim" then return { t = "u", v = { R(V.Scale), V.Offset } }
		elseif T == "UDim2" then return { t = "u2", v = { R(V.X.Scale), V.X.Offset, R(V.Y.Scale), V.Y.Offset } }
		elseif T == "Rect" then return { t = "rc", v = { R(V.Min.X), R(V.Min.Y), R(V.Max.X), R(V.Max.Y) } }
		elseif T == "NumberRange" then return { t = "nr", v = { R(V.Min), R(V.Max) } }
		elseif T == "Color3" then
			return { t = "c3", v = { math.floor(V.R * 255 + 0.5), math.floor(V.G * 255 + 0.5), math.floor(V.B * 255 + 0.5) } }
		elseif T == "Ref" then
			local P = typeof(V) == "Instance" and RevPath(V)
			if not P then return nil end
			return { t = "ref", v = P }
		elseif T == "Font" then
			local Name = string.match(V.Family, "^rbxasset://fonts/families/(.+)%.json$") or V.Family
			return { t = "ft", v = Name .. "|" .. V.Weight.Name .. "|" .. V.Style.Name }
		elseif T == "BrickColor" then return { t = "bc", v = V.Name }
		elseif T == "Vector3int16" then return { t = "v3i", v = { V.X, V.Y, V.Z } }
		elseif T == "PhysicalProperties" then
			return { t = "pp", v = table.concat({ R(V.Density), R(V.Friction), R(V.Elasticity), R(V.FrictionWeight), R(V.ElasticityWeight) }, ",") }
		elseif T == "NumberSequence" then
			local P = {}
			for I, K in ipairs(V.Keypoints) do
				local E = R(K.Envelope)
				P[I] = R(K.Time) .. ":" .. R(K.Value) .. (E ~= 0 and (":" .. E) or "")
			end
			return { t = "ns", v = table.concat(P, ",") }
		elseif T == "ColorSequence" then
			local P = {}
			for I, K in ipairs(V.Keypoints) do P[I] = R(K.Time) .. ":" .. HexOf(K.Value) end
			return { t = "cs", v = table.concat(P, ",") }
		elseif T == "Faces" or T == "Axes" then
			local P = {}
			for _, N in ipairs(T == "Faces" and { "Top", "Bottom", "Left", "Right", "Back", "Front" } or { "X", "Y", "Z" }) do
				if V[N] then table.insert(P, N) end
			end
			return { t = T == "Faces" and "fc" or "ax", v = #P > 0 and table.concat(P, ",") or "None" }
		elseif T == "CFrame" then
			local RX, RY, RZ = V:ToEulerAnglesXYZ()
			return { t = "cf", v = { R(V.X), R(V.Y), R(V.Z), R(math.deg(RX)), R(math.deg(RY)), R(math.deg(RZ)) } }
		end
		return nil
	end

	local AttrT = { Vector2 = "Vector2", Vector3 = "Vector3", Color3 = "Color3", UDim2 = "UDim2" }
	local function EncAttr(V)
		local T = typeof(V)
		if T == "boolean" then return { t = "b", v = V }
		elseif T == "number" then return { t = "n", v = R(V) }
		elseif T == "string" then return { t = "s", v = V }
		elseif AttrT[T] then return Enc(AttrT[T], V) end
		return nil
	end

	local function Sig(E)
		local V = E.v
		if type(V) == "table" then
			local P = {}
			for I, X in ipairs(V) do P[I] = tostring(X) end
			return E.t .. ":" .. table.concat(P, ",")
		end
		return E.t .. ":" .. tostring(V)
	end

	local ExtraProps = {
		WeldConstraint = { Part0 = "Ref", Part1 = "Ref" },
		Fire = { Heat = "float" },
		Smoke = { Opacity = "float", RiseVelocity = "float" },
		Sound = { SoundId = "Content" },
		UICorner = { CornerRadius = "UDim" },
		Humanoid = { Health = "float" },
		MeshPart = { CollisionFidelity = "Enum:CollisionFidelity" },
		TrussPart = { Style = "Enum:Style" },
		BasePart = { CustomPhysicalProperties = "PhysicalProperties" },
		SpawnLocation = { TeamColor = "BrickColor" },
		BrickColorValue = { Value = "BrickColor" },
		ParticleEmitter = { Color = "ColorSequence", Size = "NumberSequence", Transparency = "NumberSequence", Squash = "NumberSequence" },
		Beam = { Color = "ColorSequence", Transparency = "NumberSequence" },
		Trail = { Color = "ColorSequence", Transparency = "NumberSequence", WidthScale = "NumberSequence" },
		UIGradient = { Color = "ColorSequence", Transparency = "NumberSequence" },
		TextLabel = { FontFace = "Font" },
		TextButton = { FontFace = "Font" },
		TextBox = { FontFace = "Font" },
		Handles = { Faces = "Faces" },
		ArcHandles = { Axes = "Axes" },
	}

	local function PropsOf(Class)
		local Cached = PropCache[Class]
		if Cached then return Cached end
		local Map, Cur, Guard = {}, Class, 0
		while Cur and Cur ~= "" and Guard < 40 do
			for N, T in pairs(ExtraProps[Cur] or {}) do
				if Map[N] == nil then Map[N] = T end
			end
			local Info = Schema.Classes[Cur]
			if not Info then break end
			for N, T in pairs(Info.Props or {}) do
				if Map[N] == nil then Map[N] = T end
			end
			Cur = Info.Super
			Guard += 1
		end
		local Res = { list = {}, types = Map, unsup = {} }
		local Names = {}
		for N in pairs(Map) do
			if not SkipProp[N] then table.insert(Names, N) end
		end
		table.sort(Names)
		for _, N in ipairs(Names) do
			local T = Map[N]
			if Supported(T) then table.insert(Res.list, { N, T }) else table.insert(Res.unsup, T) end
		end
		PropCache[Class] = Res
		return Res
	end

	-- Значения по умолчанию через Instance.new (только для классов, которые реально встретились). false — нельзя (сервисы).
	local function DefaultsOf(Class)
		local D = DefCache[Class]
		if D ~= nil then return D end
		D = false
		local Info = Schema.Classes[Class]
		if Info and not Info.NotCreatable and not Info.Service then
			local Ok, I = pcall(Instance.new, Class)
			if Ok then
				D = { sig = {}, raw = {} }
				for N, T in pairs(PropsOf(Class).types) do
					local Ok2, V = pcall(GetProp, I, N)
					if Ok2 and V ~= nil then
						D.raw[N] = V
						if Supported(T) and not SkipProp[N] then
							local Ok3, E = pcall(Enc, T, V)
							if Ok3 and E then D.sig[N] = Sig(E) end
						end
					end
				end
				I:Destroy()
			end
		end
		DefCache[Class] = D
		return D
	end

	local function LoadSchema()
		local H = State.Dump and State.Dump.hash
		if Schema and SchemaHash == H then return true end
		local D, E = Call("/schema")
		if E or not D or not D.Classes then return false, E or "схема не получена" end
		Schema, SchemaHash = D, H
		PropCache, DefCache = {}, {}
		return true
	end

	-- ===== Пути (те же правила, что на сервере) =====
	local function Esc(S) return (string.gsub(string.gsub(S, "%%", "%%25"), "/", "%%2F")) end

	local function Kids(Inst, Path)
		local Items = {}
		for _, Ch in ipairs(Inst:GetChildren()) do
			if Ch.ClassName ~= "TouchTransmitter" and Ch.Name ~= "RobloxBridge_Pins" then table.insert(Items, Ch) end
		end
		table.sort(Items, function(A, B)
			if A.Name ~= B.Name then return A.Name < B.Name end
			return A.ClassName < B.ClassName
		end)
		local Res, Prev, Dup = {}, nil, 0
		for _, Ch in ipairs(Items) do
			if Ch.Name == Prev then Dup += 1 else Dup = 1; Prev = Ch.Name end
			local Key = Esc(Ch.Name) .. (Dup > 1 and ("~" .. Dup) or "")
			table.insert(Res, { Path == "" and Key or (Path .. "/" .. Key), Ch })
		end
		return Res
	end

	local function Index(Cfg)
		local Map, N = {}, 0
		local function Walk(Inst, Path)
			Map[Path] = Inst
			N += 1
			if N % 500 == 0 then task.wait() end
			for _, K in ipairs(Kids(Inst, Path)) do Walk(K[2], K[1]) end
		end
		for _, Name in ipairs(Cfg.services or {}) do
			local S = game:FindService(Name)
			if S then Walk(S, Name) end
		end
		return Map
	end

	-- Объект → путь (для ссылок). Строится лениво, один раз на Pull. Цели в Ignore и вне сервисов дают nil.
	local RefCfg, Rev, RefIgn = nil, nil, {}
	RevPath = function(Inst)
		if not RefCfg then return nil end
		if not Rev then
			Rev = {}
			for P, I in pairs(Index(RefCfg)) do Rev[I] = P end
		end
		local P = Rev[Inst]
		if not P then return nil end
		local Acc = ""
		for Seg in string.gmatch(P, "[^/]+") do
			Acc = Acc == "" and Seg or (Acc .. "/" .. Seg)
			if RefIgn[Acc] then return nil end
		end
		return P
	end

	-- ===== Юнионы: геометрия =====
	local Geo = { store = {}, got = {}, known = nil, ok = false,
		Classes = { UnionOperation = true, NegateOperation = true, IntersectOperation = true } }
	do
		local OkS, SS = pcall(game.GetService, game, "SerializationService")
		local OkE, ES = pcall(game.GetService, game, "EncodingService")
		Geo.ok = OkS and OkE

		local function Hash(Buf)
			local Len = buffer.len(Buf)
			local H1, H2 = 2166136261, (5381 + Len) % 4294967296
			for I = 0, Len - 1 do
				local B = buffer.readu8(Buf, I)
				local X = bit32.bxor(H1, B)
				H1 = (X * 403 + bit32.lshift(X, 24)) % 4294967296   -- X * 16777619 mod 2^32 без потери точности
				H2 = bit32.bxor((H2 * 33) % 4294967296, B)
			end
			return string.format("%08x%08x", H1, H2)
		end

		-- хеш геометрии юниона (и запоминает буфер для загрузки на сервер)
		function Geo.Of(Inst)
			if not Geo.ok then return nil end
			local C = Inst:Clone()
			if not C then return nil end
			C:ClearAllChildren()
			for K in pairs(C:GetAttributes()) do C:SetAttribute(K, nil) end
			for _, T in ipairs(C:GetTags()) do C:RemoveTag(T) end
			C.Name = "U"
			C.Color = Color3.fromRGB(163, 162, 165)
			C.Material = Enum.Material.Plastic
			C.Transparency = 0
			C.Anchored = false
			C:PivotTo(CFrame.new())
			local Buf = SS:SerializeInstancesAsync({ C })
			C:Destroy()
			local H = Hash(Buf)
			Geo.store[H] = Buf
			return H
		end

		function Geo.OpHash(Op)
			if not Geo.Classes[Op.class] then return nil end
			for _, A in ipairs(Op.attrs or {}) do
				if A.k == "_geo" then return A.v end
			end
			return nil
		end

		-- какие геометрии уже есть на сервере (тихо; для предпросмотра)
		function Geo.Refresh()
			Geo.known = nil
			local D, E = Call("/geo/list" .. Q(), nil, true)
			if E or not D then return end
			Geo.known = {}
			for _, H in ipairs(D.hashes or {}) do Geo.known[H] = true end
		end

		-- Pull: залить новые геометрии. Возвращает сколько залито
		function Geo.Upload()
			local All = {}
			for H in pairs(Geo.store) do table.insert(All, H) end
			if #All == 0 then return 0 end
			if not Geo.ok then error("SerializationService/EncodingService недоступны в этой Studio", 0) end
			local D, E = Call("/geo/list" .. Q())
			if E then error(E, 0) end
			local Have = {}
			for _, H in ipairs(D.hashes or {}) do Have[H] = true end
			local Need = {}
			for _, H in ipairs(All) do
				if not Have[H] then table.insert(Need, H) end
			end
			table.sort(Need)
			if #Need > 0 then Prog.Stage("Загрузка геометрии юнионов", #Need) end
			local Batch, Size, Sent = {}, 0, 0
			local function Flush()
				if #Batch == 0 then return end
				local _, E2 = Call("/geo/put" .. Q(), { items = Batch })
				if E2 then error(E2, 0) end
				Sent += #Batch
				Batch, Size = {}, 0
			end
			for I, H in ipairs(Need) do
				Prog.Step(I - 1)
				local Z = ES:CompressBuffer(Geo.store[H], Enum.CompressionAlgorithm.Zstd, 3)
				local B64 = buffer.tostring(ES:Base64Encode(Z))
				if Size + #B64 > 300000 and #Batch > 0 then Flush() end
				table.insert(Batch, { h = H, d = B64 })
				Size += #B64
			end
			Flush()
			return Sent
		end

		-- Push: скачать геометрии, нужные операциям
		function Geo.Fetch(Ops)
			Geo.got = {}
			local Need, Seen = {}, {}
			for _, Op in ipairs(Ops) do
				local H = Geo.OpHash(Op)
				if H and not Seen[H] then Seen[H] = true; table.insert(Need, H) end
			end
			if #Need == 0 then return end
			if not Geo.ok then error("SerializationService/EncodingService недоступны в этой Studio", 0) end
			Prog.Stage("Загрузка геометрии юнионов", #Need)
			for I = 1, #Need, 20 do
				Prog.Step(I - 1)
				local Part = { table.unpack(Need, I, math.min(I + 19, #Need)) }
				local D, E = Call("/geo/get" .. Q(), { hashes = Part })
				if E then error(E, 0) end
				for _, It in ipairs(D.items or {}) do
					local Raw = ES:DecompressBuffer(ES:Base64Decode(buffer.fromstring(It.d)), Enum.CompressionAlgorithm.Zstd)
					Geo.got[It.h] = Raw
				end
			end
		end

		-- новый юнион из файла геометрии. Size из операции убираем: он уже внутри геометрии
		function Geo.Make(H, Op)
			local Raw = Geo.got[H]
			if not Raw then error("геометрия " .. H .. " не получена с сервера", 0) end
			local U = SS:DeserializeInstancesAsync(Raw)[1]
			if not U or not U:IsA("PartOperation") then error("в файле геометрии " .. H .. " не юнион", 0) end
			if Op and Op.set then
				local Keep = {}
				for _, P in ipairs(Op.set) do
					if P.k ~= "Size" then table.insert(Keep, P) end
				end
				Op.set = Keep
			end
			return U
		end
	end

	-- ===== Сериализация Studio =====
	-- Значения, которые JSON не принимает: nan/inf и строки с неверным UTF-8
	local function CleanStr(S)
		if utf8.len(S) then return S, false end
		local Out, Pos = {}, 1
		while Pos <= #S do
			local L, B = utf8.len(S, Pos)
			if L then table.insert(Out, string.sub(S, Pos)); break end
			table.insert(Out, string.sub(S, Pos, B - 1))
			table.insert(Out, "?")
			Pos = B + 1
		end
		return table.concat(Out), true
	end

	local function Fix(V)
		local T = type(V)
		if T == "number" then
			if V ~= V or V == math.huge or V == -math.huge then return 0, true end
			return V, false
		elseif T == "string" then
			return CleanStr(V)
		elseif T == "table" then
			local Changed = false
			for I, X in ipairs(V) do
				local Y, Ch = Fix(X)
				if Ch then V[I] = Y; Changed = true end
			end
			return V, Changed
		end
		return V, false
	end

	local Counter, FixWarn = 0, 0
	local FixKey = "значения исправлены (nan/inf/не UTF-8)"
	local function Fixed(Skipped, Where)
		Skipped[FixKey] = (Skipped[FixKey] or 0) + 1
		FixWarn += 1
		if FixWarn <= 20 then warn("[Bridge] исправлено значение (nan/inf или неверный UTF-8): " .. Where) end
	end

	local function Node(Inst, Path, Ign, Skipped)
		Counter += 1
		if Counter == 1 then FixWarn = 0 end
		Prog.Step(Counter)
		if Counter % 200 == 0 then task.wait() end
		local Class = Inst.ClassName
		local Nm, NmBad = CleanStr(Inst.Name)
		if NmBad then Fixed(Skipped, Path .. " (имя)") end
		local N = { c = Class, n = Nm }
		local Info = PropsOf(Class)
		local Def = DefaultsOf(Class)

		local P, Any = {}, false
		for _, E in ipairs(Info.list) do
			local Ok, V = pcall(GetProp, Inst, E[1])
			if Ok and V ~= nil then
				local Ok2, Val = pcall(Enc, E[2], V)
				if Ok2 and Val then
					local FV, Bad = Fix(Val.v)
					if Bad then Val.v = FV; Fixed(Skipped, Path .. "." .. E[1]) end
					if not (Def and Def.sig[E[1]] == Sig(Val)) then
						P[E[1]] = Val
						Any = true
					end
				end
			end
		end
		if Inst:IsA("LuaSourceContainer") then
			local Ok, S = pcall(GetProp, Inst, "Source")
			if Ok then
				local S2, Bad = CleanStr(S)
				if Bad then Fixed(Skipped, Path .. ".Source") end
				P.Source = { t = "s", v = S2 }
				Any = true
			end
		end
		if Any then N.p = P end
		for _, T in ipairs(Info.unsup) do Skipped[T] = (Skipped[T] or 0) + 1 end

		local A, AnyA = {}, false
		for K, V in pairs(Inst:GetAttributes()) do
			local E = EncAttr(V)
			if E then
				local FV, Bad = Fix(E.v)
				if Bad then E.v = FV; Fixed(Skipped, Path .. " $" .. K) end
				A[K] = E
				AnyA = true
			end
		end

		if Inst:IsA("PartOperation") then
			local Ok, H = pcall(Geo.Of, Inst)
			if Ok and H then
				A._geo = { t = "s", v = H }
				AnyA = true
			else
				Skipped["юнион без геометрии"] = (Skipped["юнион без геометрии"] or 0) + 1
			end
		end

		if AnyA then N.a = A end

		local Tags = Inst:GetTags()
		if #Tags > 0 then
			for I, T in ipairs(Tags) do
				local T2, Bad = CleanStr(T)
				if Bad then Tags[I] = T2; Fixed(Skipped, Path .. " #тег") end
			end
			table.sort(Tags)
			N.g = Tags
		end

		local Out = {}
		for _, K in ipairs(Kids(Inst, Path)) do
			if not Ign[K[1]] then table.insert(Out, Node(K[2], K[1], Ign, Skipped)) end
		end
		if #Out > 0 then N.k = Out end
		return N
	end

	local function Collect(Cfg)
		Geo.store = {}
		Counter = 0
		local Ign = {}
		for _, P in ipairs(Cfg.ignore or {}) do Ign[P] = true end
		RefCfg, Rev, RefIgn = Cfg, nil, Ign
		local Total = 0
		for _, Name in ipairs(Cfg.services or {}) do
			local S = game:FindService(Name)
			if S then Total += #S:GetDescendants() + 1 end
		end
		Prog.Stage("Чтение сцены", Total)
		local Svc, Skipped = {}, {}
		for _, Name in ipairs(Cfg.services or {}) do
			local S = game:FindService(Name)
			if S then Svc[Name] = Node(S, Name, Ign, Skipped) end
		end
		if DebugOn and Svc.Workspace then
			for _, K in ipairs(Svc.Workspace.k or {}) do
				print("[Bridge] Workspace/" .. K.n .. " (" .. K.c .. "), вложенных: " .. (K.k and #K.k or 0))
			end
		end
		return Svc, Skipped
	end

	-- Режет по детям сервиса на части <= CHUNK и отправляет. Возвращает ответ на последнюю часть.
	local SetInfo
	local function Send(Route, Svc, Skipped, Extra)
		local Session = HttpService:GenerateGUID(false)
		local LIMIT = CHUNK * 0.8   -- запас на оценку размера и «скелет» предков
		local Self, Tot, Seen = {}, {}, 0
		local Up = {}

		local function NodePath(N)
			local P = {}
			while N do table.insert(P, 1, N.n); N = Up[N] end
			return table.concat(P, "/")
		end
		local function Why(N)
			for _, Fld in ipairs({ "p", "a" }) do
				for K, E in pairs(N[Fld] or {}) do
					if not pcall(HttpService.JSONEncode, HttpService, E) then
						local Ok, S = pcall(Sig, E)
						return (Fld == "a" and "атрибут $" or "свойство ") .. K .. " = " .. (Ok and S or "?")
					end
				end
			end
			return "имя, тег или класс объекта"
		end
		local function Measure(N)
			local Ok, Js = pcall(HttpService.JSONEncode, HttpService, { c = N.c, n = N.n, p = N.p, a = N.a, g = N.g })
			if not Ok then
				error("Не удаётся упаковать «" .. NodePath(N) .. "» в JSON: " .. Why(N) .. " (" .. tostring(Js) .. ")", 0)
			end
			local Own = #Js + 2
			local Sum = Own
			for _, K in ipairs(N.k or {}) do
				Up[K] = N
				Sum += Measure(K) + 1
			end
			Self[N], Tot[N] = Own, Sum
			Seen += 1
			if Seen % 300 == 0 then Prog.Step(Seen); task.wait() end
			return Sum
		end

		Prog.Stage("Подготовка к отправке", Counter)

		local Names = {}
		for N in pairs(Svc) do table.insert(Names, N) end
		table.sort(Names)

		local Parts, Used, Stack, SvcName = {}, {}, {}, ""
		local Cur, CurList, CurDeep, CurSize, Emitted

		local function StackSize()
			local T = 0
			for _, S in ipairs(Stack) do
				T += Used[S] and (60 + #S.n * 2) or (Self[S] + 20)
			end
			return T
		end
		local function PathText(Nd)
			local P = {}
			for _, S in ipairs(Stack) do table.insert(P, S.n) end
			table.insert(P, Nd.n)
			return table.concat(P, "/")
		end
		local function Flush()
			if Cur then table.insert(Parts, { [SvcName] = Cur }) end
			Cur, CurList, CurDeep = nil, nil, nil
		end
		-- новый пакет: цепочка предков (в продолжении — с пометкой m)
		local function Open()
			CurSize = StackSize()
			Emitted = true
			local Prev
			for I, S in ipairs(Stack) do
				local Cp = { c = S.c, n = S.n, k = {} }
				if Used[S] then
					if I > 1 then Cp.m = true end
				else
					Cp.p, Cp.a, Cp.g = S.p, S.a, S.g
					Used[S] = true
				end
				if Prev then table.insert(Prev.k, Cp) else Cur = Cp end
				Prev = Cp
			end
			CurList, CurDeep = Prev.k, Stack[#Stack]
		end

		local function Place(Nd)
			local T = Tot[Nd]
			if T + StackSize() <= LIMIT then
				if Cur and (CurDeep ~= Stack[#Stack] or CurSize + T > LIMIT) then Flush() end
				if not Cur then Open() end
				table.insert(CurList, Nd)
				CurSize += T + 1
				return
			end
			if not Prog.nest then
				error("Объект «" .. PathText(Nd) .. "» слишком большой для передачи (> " .. math.floor(LIMIT)
					.. " байт). Нужна версия приложения с делением больших объектов на пакеты.", 0)
			end
			if not Nd.k or #Nd.k == 0 or Self[Nd] + StackSize() > LIMIT then
				error("Объект «" .. PathText(Nd) .. "» нельзя разделить: он сам (свойства или код скрипта) занимает "
					.. Self[Nd] .. " байт при лимите пакета " .. math.floor(LIMIT)
					.. ". Добавьте его в «Игнорировать» или вынесите код скрипта в файл.", 0)
			end
			Flush()
			table.insert(Stack, Nd)
			for _, K in ipairs(Nd.k) do Place(K) end
			Flush()
			table.remove(Stack)
		end

		for _, N in ipairs(Names) do
			local S = Svc[N]
			SvcName, Stack, Emitted = N, { S }, false
			Measure(S)
			for _, K in ipairs(S.k or {}) do Place(K) end
			if not Emitted then Open() end
			Flush()
		end

		local Total, LastResp = #Parts, nil
		Prog.Stage("Отправка на сервер, пакетов: " .. Total, Total)
		for I, Body in ipairs(Parts) do
			local Req = { services = Body }
			if I == Total then
				Req.skipped = Skipped
				for K, V in pairs(Extra or {}) do Req[K] = V end
				Prog.Stage("Сервер обрабатывает данные", 0, true)
			else
				Prog.Step(I - 1)
			end
			local D, E = Call(Route .. Q() .. "&session=" .. Session .. "&part=" .. I .. "&parts=" .. Total, Req)
			if E then return D, E end
			LastResp = D
		end
		return LastResp
	end

	-- ===== Разбор значений из файла =====
	local function Nums(S, N)
		local L = {}
		for X in string.gmatch(S, "[^,]+") do
			local V = tonumber(X)
			if not V then error("не число: " .. X, 0) end
			table.insert(L, V)
		end
		if N and #L ~= N then error("ожидалось чисел: " .. N .. ", получено " .. #L, 0) end
		return L
	end

	local function Hex(S)
		local Rr, G, B = string.match(S, "^#(%x%x)(%x%x)(%x%x)$")
		if not Rr then error("цвет должен быть #RRGGBB: " .. S, 0) end
		return Color3.fromRGB(tonumber(Rr, 16), tonumber(G, 16), tonumber(B, 16))
	end

	local function Dec(T, S, F)
		if F == "f" then error("ссылки пока не поддерживаются", 0) end
		if T == "bool" then
			if S == "true" then return true elseif S == "false" then return false end
			error("ожидалось true/false: " .. S, 0)
		elseif T == "int" or T == "float" or T == "double" or T == "int64" then
			return tonumber(S) or error("не число: " .. S, 0)
		elseif T == "string" or T == "Content" or T == "ContentId" then return S
		elseif string.sub(T, 1, 5) == "Enum:" then
			local Item = Enum[string.sub(T, 6)]:FromName(S)
			if not Item then error("нет значения «" .. S .. "» у " .. T, 0) end
			return Item
		elseif T == "Vector2" then local L = Nums(S, 2); return Vector2.new(L[1], L[2])
		elseif T == "Vector3" then local L = Nums(S, 3); return Vector3.new(L[1], L[2], L[3])
		elseif T == "UDim" then local L = Nums(S, 2); return UDim.new(L[1], L[2])
		elseif T == "UDim2" then local L = Nums(S, 4); return UDim2.new(L[1], L[2], L[3], L[4])
		elseif T == "Rect" then local L = Nums(S, 4); return Rect.new(L[1], L[2], L[3], L[4])
		elseif T == "NumberRange" then local L = Nums(S, 2); return NumberRange.new(L[1], L[2])
		elseif T == "Color3" then return Hex(S)
		elseif T == "Font" then
			local Fam, W, St = string.match(S, "^(.-)|(%w+)|(%w+)$")
			if not Fam then error("шрифт: Семья|Вес|Стиль, получено: " .. S, 0) end
			if not string.find(Fam, "://", 1, true) then Fam = "rbxasset://fonts/families/" .. Fam .. ".json" end
			local Wt, Sty = Enum.FontWeight:FromName(W), Enum.FontStyle:FromName(St)
			if not Wt or not Sty then error("нет веса/стиля шрифта: " .. W .. "/" .. St, 0) end
			return Font.new(Fam, Wt, Sty)
		elseif T == "BrickColor" then
			local B = BrickColor.new(S)
			if B.Name ~= S then error("нет BrickColor «" .. S .. "» (имя с учётом регистра)", 0) end
			return B
		elseif T == "Vector3int16" then local L = Nums(S, 3); return Vector3int16.new(L[1], L[2], L[3])
		elseif T == "PhysicalProperties" then local L = Nums(S, 5); return PhysicalProperties.new(L[1], L[2], L[3], L[4], L[5])
		elseif T == "NumberSequence" or T == "ColorSequence" then
			local Ks = {}
			for Item in string.gmatch(S, "[^,]+") do
				if T == "NumberSequence" then
					local L = {}
					for X in string.gmatch(Item, "[^:]+") do table.insert(L, tonumber(X) or error("не число: " .. X, 0)) end
					if #L == 2 then table.insert(Ks, NumberSequenceKeypoint.new(L[1], L[2]))
					elseif #L == 3 then table.insert(Ks, NumberSequenceKeypoint.new(L[1], L[2], L[3]))
					else error("точка кривой: время:значение[:разброс], получено: " .. Item, 0) end
				else
					local Tm, Hx = string.match(Item, "^([^:]+):(#%x%x%x%x%x%x)$")
					if not Tm or not tonumber(Tm) then error("точка цвета: время:#RRGGBB, получено: " .. Item, 0) end
					table.insert(Ks, ColorSequenceKeypoint.new(tonumber(Tm), Hex(Hx)))
				end
			end
			return T == "NumberSequence" and NumberSequence.new(Ks) or ColorSequence.new(Ks)
		elseif T == "Faces" or T == "Axes" then
			local Items = {}
			if S ~= "None" then
				for N in string.gmatch(S, "[^,]+") do
					local E = (T == "Faces" and Enum.NormalId or Enum.Axis):FromName(N)
					if not E then error("нет «" .. N .. "» у " .. T, 0) end
					table.insert(Items, E)
				end
			end
			return (T == "Faces" and Faces or Axes).new(table.unpack(Items))
		elseif T == "CFrame" then
			local PS, RS = string.match(S, "^([^|]*)|?(.*)$")
			local P = Nums(PS, 3)
			local CF = CFrame.new(P[1], P[2], P[3])
			if RS ~= "" then
				local A = Nums(RS, 3)
				CF = CF * CFrame.Angles(math.rad(A[1]), math.rad(A[2]), math.rad(A[3]))
			end
			return CF
		end
		error("тип не поддерживается: " .. T, 0)
	end

	local function DecAttr(S, F)
		if F == "f" then error("ссылки в атрибутах не поддерживаются", 0) end
		if F == "s" then return S end
		if S == "true" then return true elseif S == "false" then return false end
		local N = tonumber(S)
		if N then return N end
		if string.sub(S, 1, 1) == "#" then return Hex(S) end
		local L = Nums(S)
		if #L == 2 then return Vector2.new(L[1], L[2]) end
		if #L == 3 then return Vector3.new(L[1], L[2], L[3]) end
		if #L == 4 then return UDim2.new(L[1], L[2], L[3], L[4]) end
		error("неизвестное значение атрибута: " .. S, 0)
	end

	-- ===== Предпросмотр: что не получится применить =====
	local function CheckProps(Op, Out)
		local Types = PropsOf(Op.class).types
		for _, P in ipairs(Op.set or {}) do
			local T = Types[P.k]
			if P.k ~= "Source" and (not T or SkipProp[P.k] or not Supported(T)) then
				table.insert(Out, "x " .. Op.path .. "." .. P.k .. ": " .. (T and ("тип " .. T .. " не поддерживается") or "нет в схеме") .. ", будет пропущено")
			end
		end
	end

	local function Classify(Ops, Cfg)
		local Out = {}
		for _, Op in ipairs(Ops) do
			local Info = Schema.Classes[Op.class]
			local GH = Geo.OpHash(Op)
			if Op.op == "create" then
				if not Info then
					table.insert(Out, "x " .. Op.path .. ": класса " .. Op.class .. " нет в схеме, не создастся")
				elseif Geo.Classes[Op.class] then
					local H = Geo.OpHash(Op)
					if not H then
						table.insert(Out, "x " .. Op.path .. ": у юниона нет $_geo, геометрии не будет")
					elseif not Geo.ok then
						table.insert(Out, "x " .. Op.path .. ": SerializationService/EncodingService недоступны, юнион не создастся")
					elseif Geo.known and not Geo.known[H] then
						table.insert(Out, "x " .. Op.path .. ": файла Geometry/" .. H .. ".union нет, юнион не создастся")
					else
						CheckProps(Op, Out)
					end
				elseif not Info or Info.Service or (Info.NotCreatable and not GH) then
					table.insert(Out, "x " .. Op.path .. ": класс " .. Op.class .. " нельзя создать")
				else
					CheckProps(Op, Out)
				end
			elseif Op.op == "set" then
				if Info then CheckProps(Op, Out) end
				if Geo.OpHash(Op) then
					table.insert(Out, "! " .. Op.path .. ": геометрия юниона отличается от файла, юнион будет заменён (ссылки на него, например WeldConstraint, потеряются)")
				end
			elseif Op.op == "delete" then
				if Op.class == "Terrain" or Op.class == "Camera" then
					table.insert(Out, "x " .. Op.path .. ": Terrain/Camera не удаляются")
				end
			end
		end
		return Out
	end

	-- ===== Применение =====
	local Defer = {}
	local function SetProps(Inst, Op, Errs, J)
		local Types = PropsOf(Op.class).types
		local Attrs = {}
		for _, P in ipairs(Op.attrs or {}) do
			if P.k ~= "_geo" then table.insert(Attrs, P) end
		end
		local function Keep(K)
			if not J then return end
			local Ok, Old = pcall(GetProp, Inst, K)
			if Ok then table.insert(J, function() Inst[K] = Old end) end
		end
		local Ordered = {}
		for _, P in ipairs(Op.set or {}) do
			if P.k ~= "Health" then table.insert(Ordered, P) end
		end
		for _, P in ipairs(Op.set or {}) do
			if P.k == "Health" then table.insert(Ordered, P) end   -- после MaxHealth
		end
		for _, P in ipairs(Ordered) do
			local K = P.k
			if K == "Source" then
				Keep(K)
				local Ok, E = pcall(function() Inst.Source = P.v end)
				if not Ok then table.insert(Errs, Op.path .. ".Source: " .. tostring(E)) end
			else
				local T = Types[K]
				if not T or SkipProp[K] or not Supported(T) then
					table.insert(Errs, Op.path .. "." .. K .. ": нет в схеме, пропущено")
				elseif P.f == "f" and T == "Ref" then
					Keep(K)
					table.insert(Defer, { Inst, K, P.v, Op.path })
				else
					Keep(K)
					local Ok, E = pcall(function()
						local V = Dec(T, P.v, P.f)
						local Ok2, E2 = pcall(function() Inst[K] = V end)
						if not Ok2 then
							if T == "Content" then Inst[K] = Content.fromUri(P.v) else error(E2, 0) end
						end
					end)
					if not Ok then table.insert(Errs, Op.path .. "." .. K .. ": " .. tostring(E)) end
				end
			end
		end
		for _, K in ipairs(Op.reset or {}) do
			local Def = DefaultsOf(Op.class)
			if Types[K] == "Ref" or Types[K] == "PhysicalProperties" then
				Keep(K)
				local Ok, E = pcall(function() Inst[K] = nil end)
				if not Ok then table.insert(Errs, Op.path .. "." .. K .. ": " .. tostring(E)) end
			elseif not Def then
				table.insert(Errs, Op.path .. "." .. K .. ": нельзя вернуть к умолчанию (сервис)")
			elseif Def.raw[K] == nil then
				table.insert(Errs, Op.path .. "." .. K .. ": нет значения по умолчанию")
			else
				Keep(K)
				local Ok, E = pcall(function() Inst[K] = Def.raw[K] end)
				if not Ok then table.insert(Errs, Op.path .. "." .. K .. ": " .. tostring(E)) end
			end
		end
		for _, P in ipairs(Attrs) do
			if J then
				local Old = Inst:GetAttribute(P.k)
				table.insert(J, function() Inst:SetAttribute(P.k, Old) end)
			end
			local Ok, E = pcall(function() Inst:SetAttribute(P.k, DecAttr(P.v, P.f)) end)
			if not Ok then table.insert(Errs, Op.path .. " $" .. P.k .. ": " .. tostring(E)) end
		end
		for _, K in ipairs(Op.adel or {}) do
			if J then
				local Old = Inst:GetAttribute(K)
				table.insert(J, function() Inst:SetAttribute(K, Old) end)
			end
			Inst:SetAttribute(K, nil)
		end
		if Op.tags then
			if J then
				local Old = Inst:GetTags()
				table.insert(J, function()
					for _, T in ipairs(Inst:GetTags()) do Inst:RemoveTag(T) end
					for _, T in ipairs(Old) do Inst:AddTag(T) end
				end)
			end
			local Want = {}
			for _, T in ipairs(Op.tags) do Want[T] = true end
			for _, T in ipairs(Inst:GetTags()) do
				if not Want[T] then Inst:RemoveTag(T) end
			end
			for T in pairs(Want) do Inst:AddTag(T) end
		end
	end

	function Geo.Replace(Old, Op, H, Errs, J)
		local New = Geo.Make(H, Op)
		for _, E in ipairs(PropsOf(Op.class).list) do
			if E[1] ~= "Size" then
				local Ok, V = pcall(GetProp, Old, E[1])
				if Ok and V ~= nil then pcall(function() New[E[1]] = V end) end
			end
		end
		for K, V in pairs(Old:GetAttributes()) do New:SetAttribute(K, V) end
		for _, T in ipairs(Old:GetTags()) do New:AddTag(T) end
		New.Name = Old.Name
		SetProps(New, Op, Errs, nil)
		local Par, Moved = Old.Parent, {}
		for _, Ch in ipairs(Old:GetChildren()) do
			table.insert(Moved, Ch)
			Ch.Parent = New
		end
		New.Parent = Par
		Old.Parent = nil
		table.insert(J, function()
			New.Parent = nil
			for _, Ch in ipairs(Moved) do Ch.Parent = Old end
			Old.Parent = Par
		end)
		return New
	end

	local function ApplyOps(Ops, Cfg)
		Defer = {}
		Prog.Stage("Поиск объектов в Studio", 0)
		local Map = Index(Cfg)
		local Created, Changed, Deleted, Skipped = 0, 0, 0, 0
		local Errs, Failed, J = {}, {}, {}
		Prog.Stage("Применение изменений", #Ops)
		local TY = os.clock()

		local Ok, Err = pcall(function()
			for OpI, Op in ipairs(Ops) do
				Prog.Step(OpI - 1)
				if os.clock() - TY > 0.1 then task.wait(); TY = os.clock() end
				if Op.op == "create" then
					local ParentPath = string.match(Op.path, "^(.*)/[^/]*$")
					local Parent = ParentPath and Map[ParentPath]
					local Info = Schema.Classes[Op.class]
					local GH = Geo.OpHash(Op)
					if ParentPath and Failed[ParentPath] then
						Failed[Op.path] = true
						Skipped += 1
					elseif not Parent then
						Failed[Op.path] = true
						table.insert(Errs, Op.path .. ": не найден родитель")
					elseif not Info or Info.Service or (Info.NotCreatable and not GH) then
						Failed[Op.path] = true
						table.insert(Errs, Op.path .. ": класс " .. Op.class .. " нельзя создать")
					else
						local Ok2, I
						if GH then
							Ok2, I = pcall(Geo.Make, GH, Op)
						else
							Ok2, I = pcall(Instance.new, Op.class)
						end
						if not Ok2 then
							Failed[Op.path] = true
							table.insert(Errs, Op.path .. ": " .. tostring(I))
						else
							I.Name = Op.name
							SetProps(I, Op, Errs, nil)
							I.Parent = Parent
							table.insert(J, function() I:Destroy() end)
							Map[Op.path] = I
							Created += 1
						end
					end
				elseif Op.op == "set" then
					local I = Map[Op.path]
					if I then
						local H = Geo.OpHash(Op)
						if H and I:IsA("PartOperation") then
							local Ok4, New = pcall(Geo.Replace, I, Op, H, Errs, J)
							if Ok4 then
								Map[Op.path] = New
							else
								table.insert(Errs, Op.path .. ": замена юниона не удалась: " .. tostring(New))
							end
						else
							SetProps(I, Op, Errs, J)
						end
						Changed += 1
					else
						table.insert(Errs, Op.path .. ": объект не найден в Studio")
					end
				elseif Op.op == "delete" then
					local I = Map[Op.path]
					if not I then
						table.insert(Errs, Op.path .. ": объект не найден в Studio")
					elseif Op.class == "Terrain" or Op.class == "Camera" then
						table.insert(Errs, Op.path .. ": Terrain/Camera не удаляются")
					else
						local Par = I.Parent
						I.Parent = nil   -- не Destroy: нужен для отмены
						table.insert(J, function() I.Parent = Par end)
						local Prefix = Op.path .. "/"
						for K in pairs(Map) do
							if K == Op.path or string.sub(K, 1, #Prefix) == Prefix then Map[K] = nil end
						end
						Deleted += 1
					end
				end
			end
			
			for _, D in ipairs(Defer) do
				local Target = Map[D[3]]
				if not Target then
					table.insert(Errs, D[4] .. "." .. D[2] .. ": цель не найдена в Studio: " .. D[3])
				else
					local Ok3, E3 = pcall(function() D[1][D[2]] = Target end)
					if not Ok3 then table.insert(Errs, D[4] .. "." .. D[2] .. ": " .. tostring(E3)) end
				end
			end
		end)
		if not Ok then table.insert(Errs, "Прервано: " .. tostring(Err)) end
		return Created, Changed, Deleted, Skipped, Errs, J
	end

	-- ===== Состояние синхронизации + отчёт приложению =====
	local Working, Pending, UndoJ = false, nil, nil
	local PreviewLines = {}
	local AutoApply = plugin:GetSetting("AutoApply") ~= false
	local HasLines = false
	local LastText, LastColor, LastLines, Scheduled = "", nil, {}, false

	local function Report()
		if Scheduled then return end
		Scheduled = true
		task.defer(function()
			Scheduled = false
			local Kind = "info"
			if LastColor == Green then Kind = "ok"
			elseif LastColor == Yellow then Kind = "warn"
			elseif LastColor == Red then Kind = "err" end
			local TS = State.TS or {}
			Call("/report" .. Q(), { text = LastText, kind = Kind, canApply = Pending ~= nil, canUndo = UndoJ ~= nil,
				tApply = TS.Apply and TS.Apply() or false, tUndo = TS.Undo and TS.Undo() or false, lines = LastLines }, true)
		end)
	end

	-- ===== Карточка «Синхронизация» =====
	local SyncCard = Card(Root, 2)
	SyncCard.Visible = false
	Text(SyncCard, 1, "Синхронизация", { Bold = true, Size = 15 })

	local BtnRow = make("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1 }, SyncCard)
	List(BtnRow, 6, Enum.FillDirection.Horizontal)
	local PullBtn = Button(BtnRow, 1, "", "pull", UDim2.new(0.5, -3, 1, 0))
	local PushBtn = Button(BtnRow, 2, "", "push", UDim2.new(0.5, -3, 1, 0))
	PullBtn.RichText, PushBtn.RichText = true, true
	PullBtn.Text = '<b>Studio → файлы</b>\n<font size="11">Pull · сохранить</font>'

	local AutoBtn = Button(SyncCard, 4, "", "link")
	local ApplyBtn = Button(SyncCard, 5, "✔ Применить", "primary")
	local UndoBtn = Button(SyncCard, 6, "↩ Отменить применение", "normal")

	local InfoBox = make("Frame", { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BorderSizePixel = 0,
		BackgroundColor3 = C.Input, Visible = false }, SyncCard)
	Corner(InfoBox, 6)
	local InfoBar = make("Frame", { Position = UDim2.new(0, 0, 0, 4), Size = UDim2.new(0, 3, 1, -8), BorderSizePixel = 0,
		BackgroundColor3 = Blue }, InfoBox)
	Corner(InfoBar, 2)
	local InfoLabel = SelText(InfoBox, 1, "", { Size = 14 })
	Pad(InfoLabel, 6, 8, 6, 12)

	local function RefreshButtons()
		Enable(PullBtn, not Working)
		Enable(PushBtn, not Working)
		ApplyBtn.Visible = Pending ~= nil
		Enable(ApplyBtn, not Working)
		UndoBtn.Visible = UndoJ ~= nil
		Enable(UndoBtn, not Working)
	end
	local function RefreshAuto()
		AutoBtn.Text = (AutoApply and "☑ " or "☐ ") .. "Применять сразу после проверки"
		PushBtn.Text = '<b>Файлы → Studio</b>\n<font size="11">Push · '
			.. (AutoApply and "применить" or "предпросмотр") .. '</font>'
	end
	RefreshAuto()
	Click(AutoBtn, function()
		AutoApply = not AutoApply
		plugin:SetSetting("AutoApply", AutoApply)
		RefreshAuto()
	end)

	local function SetPending(P)
		Pending = P
		RefreshButtons()
	end
	local function SetUndo(J)
		UndoJ = J
		RefreshButtons()
	end
	SetPending(nil)
	SetUndo(nil)

	SetInfo = function(Str, Color)
		InfoLabel.Text = Str
		InfoLabel.TextColor3 = C.Text()
		InfoBar.BackgroundColor3 = Color or Blue
		InfoBox.Visible = Str ~= ""
		LastText, LastColor, LastLines = Str, Color, {}
		Report()
	end
	
	Prog.Hook = function(Str) SetInfo(Str, Dim()) end

	-- ===== Карточка «Изменения» =====
	local ChangesCard = Card(Root, 4)
	ChangesCard.Visible = false
	local ChangesHead = Text(ChangesCard, 1, "", { Rich = true, Bold = true, Size = 15 })
	local CopyBtn = Button(ChangesCard, 2, "", "link")
	CopyBtn.TextSize = 13
	local ListFrame = make("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BorderSizePixel = 0,
		BackgroundColor3 = C.Input }, ChangesCard)
	Corner(ListFrame, 6)
	Pad(ListFrame, 6, 8, 6, 8)
	List(ListFrame, 2)

	-- Режим копирования: весь список одним выделяемым текстом
	local CopyBox = Box(ChangesCard, 4, 0, true)
	CopyBox.AutomaticSize = AutoY
	CopyBox.TextEditable = false
	CopyBox.Visible = false
	local CopyMode, AllLines = false, {}
	local function RefreshCopy()
		CopyBtn.Text = CopyMode and "◂ Обычный (цветной) вид" or "Выделить и скопировать текст"
		ListFrame.Visible = not CopyMode
		CopyBox.Visible = CopyMode
		if CopyMode then
			local T = {}
			for I = 1, math.min(#AllLines, 2000) do T[I] = AllLines[I] end
			CopyBox.Text = table.concat(T, "\n")
		end
	end
	Click(CopyBtn, function()
		CopyMode = not CopyMode
		RefreshCopy()
	end)
	RefreshCopy()

	local function ShowLines(Lines)
		for _, Ch in ipairs(ListFrame:GetChildren()) do
			if Ch:IsA("TextLabel") then Ch:Destroy() end
		end
		local Cols = { ["+"] = Green, ["-"] = Red, ["~"] = Yellow, ["x"] = Dim(), ["!"] = Orange }
		local Order, Cnt = { "+", "~", "-", "x", "!" }, {}
		for I, T in ipairs(Lines) do
			local Mark = string.sub(T, 1, 1)
			Cnt[Mark] = (Cnt[Mark] or 0) + 1
			if I <= MAXSHOW then
				local Col = Cols[Mark] or (Mark == " " and Dim()) or C.Text()
				make("TextLabel", { LayoutOrder = I, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY,
					BackgroundTransparency = 1, TextWrapped = true, TextXAlignment = Left, TextYAlignment = Top,
					Font = Enum.Font.Code, TextSize = 13, Text = T, TextColor3 = Col }, ListFrame)
			end
		end
		if #Lines > MAXSHOW then
			make("TextLabel", { LayoutOrder = MAXSHOW + 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY,
				BackgroundTransparency = 1, TextWrapped = true, TextXAlignment = Left, Font = Enum.Font.SourceSans,
				TextSize = 13, Text = "… ещё строк: " .. (#Lines - MAXSHOW) .. " (полностью — в логе приложения)",
				TextColor3 = Dim() }, ListFrame)
		end
		local Chips = {}
		for _, M in ipairs(Order) do
			if Cnt[M] then
				table.insert(Chips, string.format('<font color="%s">%s%d</font>', HexOf(Cols[M]), M, Cnt[M]))
			end
		end
		ChangesHead.Text = "Изменения   " .. table.concat(Chips, "  ")
		HasLines = #Lines > 0
		ChangesCard.Visible = HasLines and State.Found and State.Place == "ready"
		LastLines = Lines
		AllLines = Lines
		RefreshCopy()
		Report()
	end

	-- ===== Операции =====
	local function Prepare()
		if RunService:IsRunning() then error("Остановите игру (Play) перед синхронизацией", 0) end
		local Ok, E = LoadSchema()
		if not Ok then error("Схема: " .. tostring(E), 0) end
		local Cfg, E2 = Call("/config" .. Q())
		if E2 then error(E2, 0) end
		Prog.nest = Cfg.nest == true
		return Cfg
	end

	local function DoPull()
		local Cfg = Prepare()
		local Svc, Skipped = Collect(Cfg)
		local GN = Geo.Upload()
		local D, E = Send("/pull", Svc, Skipped)
		if E then error(E, 0) end
		SetUndo(nil)
		SetPending(nil)
		SetInfo((D.text or "Готово") .. (GN > 0 and (". Новых геометрий юнионов: " .. GN) or ""), Green)
		ShowLines(D.lines or {})
	end

	-- Возвращает true, если есть что применять
	local function DoPreview()
		local Cfg = Prepare()
		local Svc, Skipped = Collect(Cfg)
		local D, E = Send("/push", Svc, Skipped)
		if E then error(E, 0) end
		local Cn = D.counts
		local Total = Cn.created + Cn.changed + Cn.deleted
		PreviewLines = {}
		local Lines = {}
		for _, L in ipairs(D.lines or {}) do
			table.insert(Lines, L)
			table.insert(PreviewLines, L)
		end
		Geo.Refresh()
		local Warn = Classify(D.ops or {}, Cfg)
		for _, L in ipairs(Warn) do table.insert(Lines, L) end
		if #Warn > 0 then Note(Warn) end
		if Total == 0 then
			SetPending(nil)
			SetInfo("Push: изменений нет", Green)
		else
			SetPending({ token = D.token })
			SetInfo("Предпросмотр: создастся " .. Cn.created .. ", изменится " .. Cn.changed .. ", удалится " .. Cn.deleted
				.. ". Нажмите «Применить».", Yellow)
		end
		ShowLines(Lines)
		return Total > 0, Cn.deleted
	end

	local function DoApply()
		local P = Pending
		if not P then error("Нечего применять: сначала сделайте предпросмотр", 0) end
		local Cfg = Prepare()
		local Svc, Skipped = Collect(Cfg)
		local D, E = Send("/push", Svc, Skipped, { apply = true, token = P.token })
		SetPending(nil)
		if E then error(E, 0) end
		Geo.Fetch(D.ops or {})
		local Created, Changed, Deleted, Skip, Errs, J = ApplyOps(D.ops or {}, Cfg)
		SetUndo(J)
		local Str = "Применено: создано " .. Created .. ", изменено " .. Changed .. ", удалено " .. Deleted
		if Skip > 0 then Str ..= ", пропущено вложенных " .. Skip end
		if #Errs > 0 then Str ..= ", ошибок " .. #Errs end
		local ErrLines, Lines = {}, {}
		for _, L in ipairs(PreviewLines) do table.insert(Lines, L) end
		for _, L in ipairs(Errs) do
			table.insert(ErrLines, "x " .. L)
			table.insert(Lines, "x " .. L)
		end
		SetInfo(Str .. ". Если что-то не так — «Отменить применение».", #Errs > 0 and Yellow or Green)
		ShowLines(Lines)
		local Log = { Str }
		for I = 1, math.min(#ErrLines, 40) do table.insert(Log, ErrLines[I]) end
		Note(Log)
	end

	local function DoUndo()
		local J = UndoJ
		if not J then error("Нечего отменять", 0) end
		local Fails = 0
		for I = #J, 1, -1 do
			if not pcall(J[I]) then Fails += 1 end
		end
		SetUndo(nil)
		SetPending(nil)
		local Str = "Отменено действий: " .. #J .. (Fails > 0 and (", не удалось: " .. Fails) or "") .. ". Сделайте предпросмотр заново."
		SetInfo(Str, Fails > 0 and Yellow or Green)
		ShowLines({})
		Note({ Str })
	end

	local function Run(Title, Fn)
		if Working or not State.Found or State.Place ~= "ready" then return end
		Working = true
		RefreshButtons()
		SetInfo(Title .. "…", Dim())
		Prog.Start()
		task.spawn(function()
			local Ok, Err = pcall(Fn)
			Prog.End()
			if not Ok then
				if tostring(Err) == Prog.msg then
					SetInfo("⏹ " .. Title .. ": остановлено вами. Файлы сцены и Studio не изменены.", Yellow)
				else
					SetInfo("✖ " .. tostring(Err), Red)
					warn("RobloxBridge: " .. tostring(Err))
					Note({ "Плагин: " .. tostring(Err) })
				end
			end
			Working = false
			RefreshButtons()
		end)
	end

	Click(PullBtn, function() Run("Pull", DoPull) end)
	local DeleteGuard = 10
	Click(PushBtn, function()
		Run(AutoApply and "Push" or "Push: предпросмотр", function()
			local Has, Del = DoPreview()
			if Has and AutoApply then
				if Del > DeleteGuard then
					SetInfo("Удалится объектов: " .. Del .. " — это много. Проверьте список и нажмите «Применить».", Orange)
				else
					DoApply()
				end
			end
		end)
	end)
	Click(ApplyBtn, function()
		if not Pending then return end
		Run("Применяю", DoApply)
	end)
	Click(UndoBtn, function() Run("Отмена", DoUndo) end)

	-- ===== Объект: информация о выделенном и действия =====
	-- Путь объекта по тем же правилам, что на сервере (~2 у одинаковых братьев, %2F)
	local function PathOf(Inst)
		if Inst.Parent == game then return Inst.ClassName end
		if not Inst.Parent then return nil end
		local PP = PathOf(Inst.Parent)
		if not PP then return nil end
		for _, K in ipairs(Kids(Inst.Parent, PP)) do
			if K[2] == Inst then return K[1] end
		end
		return nil
	end

	-- Кэш настроек плейса (сервисы, игнор, вынесенное); обновляется раз в 8 с или принудительно
	local Cache = { Data = nil, Time = -100 }
	local function Refresh(Force)
		if not Force and Cache.Data and os.clock() - Cache.Time < 8 then return true end
		local D, E = Call("/settings" .. Q(), nil, true)
		if E or not D then return false end
		Cache.Data, Cache.Time = D, os.clock()
		return true
	end

	local function Under(Path, Rule)
		return Path == Rule or string.sub(Path, 1, #Rule + 1) == Rule .. "/"
	end

	local Current, SelToken = nil, 0
	local ShowObject

	local ObjCard = Card(Root, 3)
	ObjCard.Visible = false
	Text(ObjCard, 1, "Объект", { Bold = true, Size = 15 })
	local ObjTitle = Text(ObjCard, 2, "", { Bold = true })
	local ObjPath = Text(ObjCard, 3, "", { Code = true, Size = 12, Color = C.Dim })
	local ObjStatus = Text(ObjCard, 4, "", { Size = 13 })
	local ObjExtra = Text(ObjCard, 5, "", { Size = 12, Color = C.Dim })
	local ObjRow = make("Frame", { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, ObjCard)
	List(ObjRow, 6, Enum.FillDirection.Horizontal)
	local SplitBtn = Button(ObjRow, 1, "Вынести в файл", "normal", UDim2.new(0.5, -3, 1, 0))
	local UnsplitBtn = Button(ObjRow, 2, "Вернуть в общий", "normal", UDim2.new(0.5, -3, 1, 0))
	local IgnoreBtn = Button(ObjCard, 7, "Не синхронизировать", "normal")
	local ObjHint = Text(ObjCard, 8, "", { Size = 12, Color = C.Dim })

	local function Analyze(Sel)
		local A = { Can = {}, Color = Dim(), Extra = "", Hint = "" }
		if #Sel == 0 then A.Title, A.Status = "Ничего не выделено", "Выделите объект в Explorer"; return A end
		if #Sel > 1 then A.Title, A.Status = "Выделено объектов: " .. #Sel, "Выберите один объект"; return A end
		local Inst = Sel[1]
		A.Title = Inst.ClassName .. " · «" .. Inst.Name .. "»"
		local Path = PathOf(Inst)
		if not Path then
			A.Status = "Не синхронизируется: вне синхронизируемых сервисов"
			return A
		end
		A.Path = Path
		local Data = Cache.Data
		if not Data then A.Status = "Нет данных от приложения…"; return A end

		local Extra = {}
		local Ok, N = pcall(function() return #Inst:GetDescendants() end)
		if Ok and N > 0 then table.insert(Extra, "Вложенных объектов: " .. N) end
		if Inst:IsA("LuaSourceContainer") then
			local Ok2, S = pcall(GetProp, Inst, "Source")
			if Ok2 then
				local _, Nl = string.gsub(S, "\n", "")
				table.insert(Extra, "Скрипт: " .. (Nl + 1) .. " строк")
			end
		end
		A.Extra = table.concat(Extra, " · ")

		local RootName, InServices = string.match(Path, "^[^/]+"), false
		for _, S in ipairs(Data.services or {}) do
			if S == RootName then InServices = true end
		end
		if not InServices then
			A.Status, A.Color = "Сервис «" .. RootName .. "» не входит в синхронизацию", Yellow
			A.Hint = "Добавьте сервис в «Настройки плейса»."
			return A
		end

		for _, Rule in ipairs(Data.ignore or {}) do
			if Path == Rule then
				A.Status, A.Ignored = "Игнорируется (есть в списке «Игнорировать»)", true
				A.Can.ignore = true
				return A
			elseif Under(Path, Rule) then
				A.Status = "Игнорируется вместе с «" .. Rule .. "»"
				A.Hint = "Правило стоит на родителе: снимите его там или в настройках."
				return A
			end
		end

		if Inst.Parent == game then
			A.Status, A.Color = "Сервис синхронизируется", Green
			A.Hint = "Сервис целиком убирается в «Настройки плейса»."
			return A
		end
		if Inst.ClassName == "Terrain" then
			A.Status, A.Color = "Terrain: свойства и вложенные объекты (Clouds и др.) синхронизируются", Green
			return A
		end

		for _, S in ipairs(Data.splits or {}) do
			if S.path == Path then
				if S.exists then
					A.Status, A.Color = "Вынесен в отдельный файл (" .. tostring(S.lines) .. " стр.)", Blue
				else
					A.Status, A.Color = "Вынесен, но файла нет!", Red
					A.Hint = "Нажмите «Вернуть в общий» или уберите запись кнопкой ✕ в настройках плейса."
				end
				A.Can.unsplit = true
				return A
			end
		end

		local Inside
		for _, S in ipairs(Data.splits or {}) do
			if Under(Path, S.path) then Inside = S.path end
		end
		A.Status = Inside and ("Синхронизируется, внутри вынесенного «" .. Inside .. "»") or "Синхронизируется"
		A.Color = Green
		A.Can.split, A.Can.ignore = true, true
		return A
	end

	local function ApplyObj()
		local A = Current or { Can = {} }
		Enable(SplitBtn, not Working and A.Can.split == true)
		Enable(UnsplitBtn, not Working and A.Can.unsplit == true)
		Enable(IgnoreBtn, not Working and A.Can.ignore == true)
		IgnoreBtn.Text = A.Ignored and "Синхронизировать снова" or "Не синхронизировать"
	end
	ApplyObj()

	-- кнопки объекта обновляются вместе с остальными (Working меняется в Run/Do)
	local BaseRefresh = RefreshButtons
	RefreshButtons = function()
		BaseRefresh()
		ApplyObj()
	end

	ShowObject = function(Force)
		SelToken += 1
		local My = SelToken
		task.delay(Force and 0 or 0.25, function()
			if My ~= SelToken then return end
			if #Selection:Get() == 1 then Refresh(Force) end
			if My ~= SelToken then return end
			local A = Analyze(Selection:Get())
			Current = A
			ObjTitle.Text = A.Title or ""
			ObjPath.Text = A.Path or ""
			ObjPath.Visible = A.Path ~= nil
			ObjStatus.Text = A.Status or ""
			ObjStatus.TextColor3 = A.Color
			ObjExtra.Text = A.Extra
			ObjExtra.Visible = A.Extra ~= ""
			ObjHint.Text = A.Hint
			ObjHint.Visible = A.Hint ~= ""
			ApplyObj()
		end)
	end
	Selection.SelectionChanged:Connect(function() ShowObject(false) end)

	local function SplitAction(On)
		local A = Current
		if not A or not A.Path then error("Выберите в Explorer один объект", 0) end
		Prepare()
		local D, E = Call((On and "/split" or "/unsplit") .. Q(), { path = A.Path })
		if E then error(E, 0) end
		SetPending(nil)
		SetInfo(D.text or "Готово", D.warn and Yellow or Green)
		ShowLines(D.lines or {})
		ShowObject(true)
	end

	local function IgnoreAction()
		local A = Current
		if not A or not A.Path then error("Выберите в Explorer один объект", 0) end
		if not Refresh(true) then error("Нет данных от приложения", 0) end
		local Data = Cache.Data
		local New, Has = {}, false
		for _, P in ipairs(Data.ignore or {}) do
			if P == A.Path then Has = true else table.insert(New, P) end
		end
		if not Has then table.insert(New, A.Path) end
		local D, E = Call("/settings" .. Q(), { autoSplit = Data.autoSplit, services = Data.services, ignore = New, scriptExt = Data.scriptExt, inlineLines = Data.inlineLines, terrainFile = Data.terrainFile })
		if E then error(E, 0) end
		SetPending(nil)
		SetInfo((Has and "Объект снова синхронизируется: " or "Объект исключён из синхронизации: ") .. A.Path
			.. ". Чтобы изменения попали в файлы, сделайте Pull.", Green)
		ShowObject(true)
	end

	Click(SplitBtn, function() Run("Вынос", function() SplitAction(true) end) end)
	Click(UnsplitBtn, function() Run("Возврат", function() SplitAction(false) end) end)
	Click(IgnoreBtn, function() Run("Правило", IgnoreAction) end)

	-- ===== Террейн (в отдельной функции: у Lua лимит 200 локальных переменных) =====
	;(function()
		local TB64 = 300000
		local Air = Enum.Material.Air
		local HasES, ES = pcall(game.GetService, game, "EncodingService")
		if not HasES then ES = nil end
		local TKey = "TerrainRegion" .. game.PlaceId
		local TJournal, TPendingN = nil, nil

		-- ---------- байты ----------
		local function NewW() return { b = buffer.create(65536), n = 0 } end
		local function Ensure(W, N)
			local Need, Cap = W.n + N, buffer.len(W.b)
			if Need > Cap then
				while Cap < Need do Cap *= 2 end
				local NB = buffer.create(Cap)
				buffer.copy(NB, 0, W.b, 0, W.n)
				W.b = NB
			end
		end
		local function PutB(W, V) Ensure(W, 1); buffer.writeu8(W.b, W.n, V); W.n += 1 end
		local function PutN(W, V, N)
			V = V % (256 ^ N)
			for _ = 1, N do PutB(W, V % 256); V = V // 256 end
		end
		local function PutS(W, S) Ensure(W, #S); buffer.writestring(W.b, W.n, S); W.n += #S end
		local function GetB(Rd) local V = buffer.readu8(Rd.b, Rd.p); Rd.p += 1; return V end
		local function GetN(Rd, N, Signed)
			local V, M = 0, 1
			for _ = 1, N do V += GetB(Rd) * M; M *= 256 end
			if Signed and V >= M / 2 then V -= M end
			return V
		end

		-- ---------- палитра материалов ----------
		local function NewPal()
			local Items = Enum.Material:GetEnumItems()
			table.sort(Items, function(A, B) return A.Value < B.Value end)
			local P = { names = {}, idx = {} }
			for _, It in ipairs(Items) do
				P.idx[It] = #P.names
				table.insert(P.names, It.Name)
			end
			return P
		end
		local function PalFromNames(Names)
			local P = { names = {}, idx = {} }
			for I, N in ipairs(Names) do
				P.names[I] = N
				local Ok, It = pcall(function() return Enum.Material[N] end)
				if Ok and It then P.idx[It] = I - 1 end
			end
			return P
		end
		local function IdxOf(P, Mat)
			local I = P.idx[Mat]
			if I then return I end
			I = #P.names
			if I > 255 then error("Слишком много материалов в палитре", 0) end
			table.insert(P.names, Mat.Name)
			P.idx[Mat] = I
			return I
		end
		local function ItemsOf(P)
			local T = {}
			for It, I in pairs(P.idx) do T[I + 1] = It end
			return T
		end

		-- ---------- кусок 16x16x16 <-> RLE-строка ----------
		local Scratch = buffer.create(16384)
		local function PutRun(N, Key, Run)
			buffer.writeu8(Scratch, N, Key // 256)
			buffer.writeu8(Scratch, N + 1, Key % 256)
			N += 2
			local V = Run - 1
			while V >= 128 do
				buffer.writeu8(Scratch, N, V % 128 + 128)
				N += 1
				V //= 128
			end
			buffer.writeu8(Scratch, N, V)
			return N + 1
		end

		-- nil, если в куске один воздух
		local function EncChunk(M, O, Pal)
			local N, Any, Key, Run = 0, false, -1, 0
			local PI = Pal.idx
			for I = 1, 16 do
				local MI, OI = M[I], O[I]
				for J = 1, 16 do
					local MJ, OJ = MI[J], OI[J]
					for K = 1, 16 do
						local Mat = MJ[K]
						local Oc = 0
						if Mat ~= Air then
							Oc = math.floor(OJ[K] * 255 + 0.5)
							Any = true
						end
						local K2 = (PI[Mat] or IdxOf(Pal, Mat)) * 256 + Oc
						if K2 == Key then
							Run += 1
						else
							if Run > 0 then N = PutRun(N, Key, Run) end
							Key, Run = K2, 1
						end
					end
				end
			end
			N = PutRun(N, Key, Run)
			if not Any then return nil end
			return buffer.readstring(Scratch, 0, N)
		end

		local function Blank()
			local M, O = {}, {}
			for I = 1, 16 do
				M[I], O[I] = {}, {}
				for J = 1, 16 do
					M[I][J], O[I][J] = table.create(16, Air), table.create(16, 0)
				end
			end
			return M, O
		end

		local function DecChunk(S, Items)
			local M, O = Blank()
			if not S then return M, O end
			local Buf, Pos, Len, Cnt = buffer.fromstring(S), 0, #S, 0
			while Pos < Len do
				local Mat = Items[buffer.readu8(Buf, Pos) + 1] or Air
				local Oc = buffer.readu8(Buf, Pos + 1) / 255
				Pos += 2
				local V, Mul = 0, 1
				while true do
					local B = buffer.readu8(Buf, Pos)
					Pos += 1
					V += (B % 128) * Mul
					Mul *= 128
					if B < 128 then break end
				end
				for _ = 0, V do
					local K, J, I = Cnt % 16 + 1, (Cnt // 16) % 16 + 1, Cnt // 256 + 1
					M[I][J][K] = Mat
					O[I][J][K] = Oc
					Cnt += 1
				end
			end
			if Cnt ~= 4096 then error("Поврежден кусок террейна в файле (вокселей " .. Cnt .. ")", 0) end
			return M, O
		end

		local function WriteChunk(P, Data, Items)
			local Lo = Vector3.new(P[1] * 64, P[2] * 64, P[3] * 64)
			local M, O = DecChunk(Data, Items)
			workspace.Terrain:WriteVoxels(Region3.new(Lo, Lo + Vector3.new(64, 64, 64)), 4, M, O)
		end

		local function CK(X, Y, Z) return X .. "," .. Y .. "," .. Z end

		-- ---------- область ----------
		local function RegionText(Rg)
			return string.format("%d,%d,%d  %d,%d,%d", Rg[1], Rg[2], Rg[3], Rg[4], Rg[5], Rg[6])
		end

		local function RegionsText(Regs)
			local T = {}
			for I, Rg in ipairs(Regs) do T[I] = RegionText(Rg) end
			return table.concat(T, "\n")
		end

		local function ParseRegion(S)
			local N = {}
			for X in string.gmatch(S, "%-?%d+%.?%d*") do table.insert(N, tonumber(X)) end
			if #N ~= 6 then error("нужно 6 чисел «x0,y0,z0  x1,y1,z1»", 0) end
			local Rg = {}
			for A = 1, 3 do
				local Lo, Hi = math.min(N[A], N[A + 3]), math.max(N[A], N[A + 3])
				Rg[A] = math.floor(Lo / 64) * 64
				Rg[A + 3] = math.max(math.ceil(Hi / 64) * 64, Rg[A] + 64)
				if Rg[A] < -128000 or Rg[A + 3] > 128000 then error("выходит за ±128000 (граница террейна Roblox)", 0) end
			end
			return Rg
		end

		-- Несколько областей: по одной на строке. Пересекаться нельзя.
		local function ParseRegions(S)
			local Res = {}
			for Line in string.gmatch(S, "[^\r\n]+") do
				if string.find(Line, "%d") then
					local Ok, Rg = pcall(ParseRegion, Line)
					if not Ok then error("Область №" .. (#Res + 1) .. ": " .. tostring(Rg), 0) end
					table.insert(Res, Rg)
				end
			end
			if #Res == 0 then error("Задайте хотя бы одну область", 0) end
			for I = 1, #Res do
				for J = I + 1, #Res do
					local A, B = Res[I], Res[J]
					if A[1] < B[4] and B[1] < A[4] and A[2] < B[5] and B[2] < A[5] and A[3] < B[6] and B[3] < A[6] then
						error("Области №" .. I .. " и №" .. J .. " пересекаются. Разделите их или объедините в одну.", 0)
					end
				end
			end
			return Res
		end

		-- Читает террейн всех областей. Возвращает Data[ключ] = RLE-строка, Pos[ключ] = {cx,cy,cz}, Edge, Total
		local function AnySolid(M)
			for I = 1, 16 do
				local MI = M[I]
				for J = 1, 16 do
					local MJ = MI[J]
					for K = 1, 16 do
						if MJ[K] ~= Air then return true end
					end
				end
			end
			return false
		end

		-- Читает террейн всех областей. Возвращает Data[ключ] = RLE-строка, Pos[ключ] = {cx,cy,cz}, Edge, Total
		local function ScanRegion(Regs, Pal, Label)
			local Terr = workspace.Terrain
			local function Covered(X, Y, Z)
				for _, Rg in ipairs(Regs) do
					if X >= Rg[1] // 64 and X < Rg[4] // 64 and Y >= Rg[2] // 64 and Y < Rg[5] // 64
						and Z >= Rg[3] // 64 and Z < Rg[6] // 64 then return true end
				end
				return false
			end
			local Total = 0
			for _, Rg in ipairs(Regs) do
				Total += ((Rg[4] - Rg[1]) // 64) * ((Rg[5] - Rg[2]) // 64) * ((Rg[6] - Rg[3]) // 64)
			end
			local Data, Pos, Edge, Done = {}, {}, 0, 0
			local TY = os.clock()
			Prog.Stage(Label, Total)

			-- есть ли террейн в соседнем куске (с запоминанием)
			local Nb = {}
			local function NbHas(X, Y, Z)
				local Key = CK(X, Y, Z)
				local V = Nb[Key]
				if V == nil then
					local Lo = Vector3.new(X * 64, Y * 64, Z * 64)
					V = AnySolid((Terr:ReadVoxels(Region3.new(Lo, Lo + Vector3.new(64, 64, 64)), 4)))
					Nb[Key] = V
				end
				return V
			end

			-- воксели на внешней грани, если за гранью нет другой области, но там есть террейн
			local function EdgeCount(M, CX, CY, CZ)
				local N = 0
				for F = 1, 6 do
					local A = (F - 1) % 3 + 1
					local Dir = F > 3 and 1 or -1
					local NX = CX + (A == 1 and Dir or 0)
					local NY = CY + (A == 2 and Dir or 0)
					local NZ = CZ + (A == 3 and Dir or 0)
					if not Covered(NX, NY, NZ) then
						local Face = Dir > 0 and 16 or 1
						local Cnt = 0
						for P = 1, 16 do
							for Q = 1, 16 do
								local V
								if A == 1 then V = M[Face][P][Q]
								elseif A == 2 then V = M[P][Face][Q]
								else V = M[P][Q][Face] end
								if V ~= Air then Cnt += 1 end
							end
						end
						if Cnt > 0 and NbHas(NX, NY, NZ) then N += Cnt end
					end
				end
				return N
			end

			for _, Rg in ipairs(Regs) do
				for CX = Rg[1] // 64, Rg[4] // 64 - 1 do
					for CY = Rg[2] // 64, Rg[5] // 64 - 1 do
						for CZ = Rg[3] // 64, Rg[6] // 64 - 1 do
							local Lo = Vector3.new(CX * 64, CY * 64, CZ * 64)
							local M, O = Terr:ReadVoxels(Region3.new(Lo, Lo + Vector3.new(64, 64, 64)), 4)
							Edge += EdgeCount(M, CX, CY, CZ)
							local S = EncChunk(M, O, Pal)
							if S then
								local K = CK(CX, CY, CZ)
								Data[K] = S
								Pos[K] = { CX, CY, CZ }
							end
							Done += 1
							Prog.Step(Done)
							if os.clock() - TY > 0.05 then
								task.wait()
								TY = os.clock()
							end
						end
					end
				end
			end
			return Data, Pos, Edge, Total
		end

		-- ---------- файл (RBT2: список областей; RBT1 читается как одна область) ----------
		local function BuildFile(Regs, Pal, Data, Pos)
			local W = NewW()
			PutS(W, "RBT2")
			PutN(W, #Regs, 2)
			for _, Rg in ipairs(Regs) do
				for I = 1, 6 do PutN(W, Rg[I], 4) end
			end
			PutN(W, #Pal.names, 2)
			for _, N in ipairs(Pal.names) do PutB(W, #N); PutS(W, N) end
			local Keys = {}
			for K in pairs(Data) do table.insert(Keys, K) end
			table.sort(Keys, function(A, B)
				local PA, PB = Pos[A], Pos[B]
				if PA[1] ~= PB[1] then return PA[1] < PB[1] end
				if PA[2] ~= PB[2] then return PA[2] < PB[2] end
				return PA[3] < PB[3]
			end)
			PutN(W, #Keys, 4)
			for _, K in ipairs(Keys) do
				local P, D = Pos[K], Data[K]
				PutN(W, P[1], 2); PutN(W, P[2], 2); PutN(W, P[3], 2)
				PutN(W, #D, 2)
				PutS(W, D)
			end
			local Out = buffer.create(W.n)
			buffer.copy(Out, 0, W.b, 0, W.n)
			return Out
		end

		local function ParseFile(Buf)
			local Magic = buffer.len(Buf) >= 4 and buffer.readstring(Buf, 0, 4) or ""
			if Magic ~= "RBT1" and Magic ~= "RBT2" then
				error("Файл террейна: неизвестный формат", 0)
			end
			local Rd = { b = Buf, p = 4 }
			local Regions = {}
			local RN = Magic == "RBT2" and GetN(Rd, 2) or 1
			for RI = 1, RN do
				local Reg = {}
				for I = 1, 6 do Reg[I] = GetN(Rd, 4, true) end
				Regions[RI] = Reg
			end
			local Names = {}
			for I = 1, GetN(Rd, 2) do
				local L = GetB(Rd)
				Names[I] = buffer.readstring(Buf, Rd.p, L)
				Rd.p += L
			end
			local Data, Pos = {}, {}
			for _ = 1, GetN(Rd, 4) do
				local Cx, Cy, Cz = GetN(Rd, 2, true), GetN(Rd, 2, true), GetN(Rd, 2, true)
				local L = GetN(Rd, 2)
				local K = CK(Cx, Cy, Cz)
				Data[K] = buffer.readstring(Buf, Rd.p, L)
				Rd.p += L
				Pos[K] = { Cx, Cy, Cz }
			end
			return { regions = Regions, names = Names, data = Data, pos = Pos }
		end

		-- ---------- передача ----------
		local function Upload(Buf)
			Prog.Stage("Террейн: сжатие файла", 0, true)
			task.wait()
			local Z = ES:CompressBuffer(Buf, Enum.CompressionAlgorithm.Zstd, 3)
			local B64 = buffer.tostring(ES:Base64Encode(Z))
			local Parts = math.max(1, math.ceil(#B64 / TB64))
			local Session = HttpService:GenerateGUID(false)
			Prog.Stage("Террейн: отправка файла", Parts)
			for I = 1, Parts do
				Prog.Step(I - 1)
				local _, E = Call("/terrain/put" .. Q() .. "&session=" .. Session .. "&part=" .. I .. "&parts=" .. Parts,
					{ data = string.sub(B64, (I - 1) * TB64 + 1, I * TB64) })
				if E then error(E, 0) end
			end
			return buffer.len(Z)
		end

		local function Download()
			Prog.Stage("Террейн: загрузка файла", 0)
			local Got, Parts, I = {}, 1, 1
			while I <= Parts do
				local D, E = Call("/terrain/get" .. Q() .. "&part=" .. I)
				if E then error(E, 0) end
				Parts = D.parts
				Got[I] = D.data
				Prog.total = Parts
				Prog.Step(I)
				I += 1
			end
			Prog.Stage("Террейн: распаковка", 0, true)
			task.wait()
			local Raw = ES:Base64Decode(buffer.fromstring(table.concat(Got)))
			return ES:DecompressBuffer(Raw, Enum.CompressionAlgorithm.Zstd)
		end

		-- ---------- действия ----------
		local function NeedReady()
			if RunService:IsRunning() then error("Остановите игру (Play) перед синхронизацией", 0) end
			if not ES then error("EncodingService недоступен в этой Studio", 0) end
		end

		local RegionBox

		local function TerrainPull()
			NeedReady()
			local Regs = ParseRegions(RegionBox.Text)
			RegionBox.Text = RegionsText(Regs)
			plugin:SetSetting(TKey, RegionBox.Text)
			local Pal = NewPal()
			local Data, Pos, Edge, Total = ScanRegion(Regs, Pal, "Террейн: чтение")
			local N = 0
			for _ in pairs(Data) do N += 1 end
			Prog.Stage("Террейн: упаковка", 0, true)
			task.wait()
			local Size = Upload(BuildFile(Regs, Pal, Data, Pos))
			TPendingN = nil
			local Str = string.format("Террейн сохранён: областей %d, кусков с данными %d из %d, файл %d КБ", #Regs, N, Total, Size // 1024)
			local Lines = {}
			if Edge > 0 then
				Str ..= ". Террейн упирается в границу области"
				Lines[1] = "! Вокселей на границе области: " .. Edge .. ". Террейн, вероятно, продолжается дальше — расширьте область и повторите Pull."
			end
			SetInfo(Str, Edge > 0 and Yellow or Green)
			ShowLines(Lines)
			Note({ Str })
		end

		local function Compare()
			local F = ParseFile(Download())
			local Pal = PalFromNames(F.names)
			local Cur, CPos = ScanRegion(F.regions, Pal, "Террейн: чтение")
			local Res = { f = F, cur = Cur, cpos = CPos, pal = Pal, change = {}, add = 0, mod = 0, del = 0 }
			for K, D in pairs(F.data) do
				if Cur[K] ~= D then
					table.insert(Res.change, K)
					if Cur[K] then Res.mod += 1 else Res.add += 1 end
				end
			end
			for K in pairs(Cur) do
				if F.data[K] == nil then
					table.insert(Res.change, K)
					Res.del += 1
				end
			end
			table.sort(Res.change)
			return Res
		end

		local function TerrainPreview()
			NeedReady()
			local Res = Compare()
			TPendingN = nil
			local Total = #Res.change
			if Total == 0 then
				SetInfo("Террейн: изменений нет (областей в файле: " .. #Res.f.regions .. ")", Green)
				ShowLines({})
				return
			end
			TPendingN = { add = Res.add, mod = Res.mod, del = Res.del }
			local Lines = {}
			for I, K in ipairs(Res.change) do
				if I > 60 then break end
				local P = Res.f.pos[K] or Res.cpos[K]
				local Mark = Res.f.data[K] == nil and "-" or (Res.cur[K] and "~" or "+")
				Lines[I] = string.format("%s Террейн, кусок 64 ст. с угла (%d, %d, %d)", Mark, P[1] * 64, P[2] * 64, P[3] * 64)
			end
			if Total > 60 then table.insert(Lines, "  … ещё кусков: " .. (Total - 60)) end
			SetInfo(string.format("Террейн, предпросмотр: добавится %d, изменится %d, очистится %d кусков. Сохраните плейс и нажмите «Применить террейн».",
				Res.add, Res.mod, Res.del), Yellow)
			ShowLines(Lines)
		end

		local function TerrainApply()
			if not TPendingN then error("Сначала «Террейн: Push» (предпросмотр)", 0) end
			NeedReady()
			local Res = Compare()
			if Res.add ~= TPendingN.add or Res.mod ~= TPendingN.mod or Res.del ~= TPendingN.del then
				TPendingN = nil
				error("Террейн или файл изменились после предпросмотра. Повторите Push.", 0)
			end
			local Items = ItemsOf(Res.pal)
			local Journal = { items = Items, list = {} }
			local TY = os.clock()
			Prog.Stage("Террейн: запись кусков", #Res.change)
			local Ok, Err = pcall(function()
				for I, K in ipairs(Res.change) do
					Prog.Step(I - 1)
					local P = Res.f.pos[K] or Res.cpos[K]
					table.insert(Journal.list, { P, Res.cur[K] })
					WriteChunk(P, Res.f.data[K], Items)
					if os.clock() - TY > 0.05 then
						task.wait()
						TY = os.clock()
					end
				end
			end)
			TJournal = Journal
			TPendingN = nil
			if not Ok then error("Прервано: " .. tostring(Err) .. ". «Отменить террейн» вернёт уже записанное.", 0) end
			local Str = string.format("Террейн применён: записано кусков %d (добавлено %d, изменено %d, очищено %d)",
				#Res.change, Res.add, Res.mod, Res.del)
			SetInfo(Str .. ". Можно «Отменить террейн».", Green)
			ShowLines({})
			Note({ Str })
		end

		local function TerrainUndoRun()
			local J = TJournal
			if not J then error("Нечего отменять", 0) end
			Prog.Stage("Террейн: возврат", #J.list, true)
			local TY = os.clock()
			for I = #J.list, 1, -1 do
				WriteChunk(J.list[I][1], J.list[I][2], J.items)
				Prog.done = #J.list - I + 1
				if os.clock() - TY > 0.05 then task.wait(); TY = os.clock() end
			end
			TJournal = nil
			TPendingN = nil
			SetInfo("Террейн возвращён: кусков " .. #J.list, Green)
			ShowLines({})
		end

		-- ===== Рамки областей, маркеры, автопоиск =====
		local RegionViz = { Folder = nil, Ads = {}, Count = 0 }
		local RedrawViz   -- задаётся ниже
		local VizOn, PinOn = false, false

		local function RegionColor(I)
			return Color3.fromHSV(((I - 1) * 0.618034) % 1, 0.65, 1)
		end

		local function VizRegion(Text)
			local N = {}
			for V in string.gmatch(Text or "", "%-?%d+%.?%d*") do
				N[#N + 1] = tonumber(V)
			end
			if #N < 6 then return nil end
			local function Lo(A) return math.floor(A / 64) * 64 end
			local function Hi(A) return math.ceil(A / 64) * 64 end
			local Mn = Vector3.new(Lo(math.min(N[1], N[4])), Lo(math.min(N[2], N[5])), Lo(math.min(N[3], N[6])))
			local Mx = Vector3.new(Hi(math.max(N[1], N[4])), Hi(math.max(N[2], N[5])), Hi(math.max(N[3], N[6])))
			return Mn, Mx
		end

		-- { Mn, Mx, цвет } для каждой строки поля
		local function VizRegions(Text)
			local Res = {}
			for Line in string.gmatch(Text or "", "[^\r\n]+") do
				local Mn, Mx = VizRegion(Line)
				if Mn then table.insert(Res, { Mn, Mx, RegionColor(#Res + 1) }) end
			end
			return Res
		end

		-- пересечение коробок {x0,y0,z0,x1,y1,z1} (касание не считается)
		local function Cross(A, B)
			return A[1] < B[4] and B[1] < A[4] and A[2] < B[5] and B[2] < A[5] and A[3] < B[6] and B[3] < A[6]
		end

		-- 13 коробок на область: заливка + 12 рёбер
		local function VizBoxes(Mn, Mx)
			local Size, Mid = Mx - Mn, (Mn + Mx) / 2
			local T = math.clamp(math.max(Size.X, Size.Y, Size.Z) / 300, 2, 40)
			local L = { { Mid, Size } }
			for _, Y in ipairs({ Mn.Y, Mx.Y }) do
				for _, Z in ipairs({ Mn.Z, Mx.Z }) do
					L[#L + 1] = { Vector3.new(Mid.X, Y, Z), Vector3.new(Size.X, T, T) }
				end
			end
			for _, X in ipairs({ Mn.X, Mx.X }) do
				for _, Z in ipairs({ Mn.Z, Mx.Z }) do
					L[#L + 1] = { Vector3.new(X, Mid.Y, Z), Vector3.new(T, Size.Y, T) }
				end
				for _, Y in ipairs({ Mn.Y, Mx.Y }) do
					L[#L + 1] = { Vector3.new(X, Y, Mid.Z), Vector3.new(T, T, Size.Z) }
				end
			end
			return L
		end

		function RegionViz.Clear()
			if RegionViz.Folder then RegionViz.Folder:Destroy() end
			RegionViz.Folder, RegionViz.Ads, RegionViz.Count = nil, {}, 0
		end

		-- Рисует рамки. Если число областей то же — обновляет на месте (без мигания)
		function RegionViz.Show(Rgns)
			local Bad = {}
			for I = 1, #Rgns do
				for J = I + 1, #Rgns do
					local A, B = Rgns[I], Rgns[J]
					if Cross({ A[1].X, A[1].Y, A[1].Z, A[2].X, A[2].Y, A[2].Z }, { B[1].X, B[1].Y, B[1].Z, B[2].X, B[2].Y, B[2].Z }) then
						Bad[I], Bad[J] = true, true
					end
				end
			end
			if not RegionViz.Folder or RegionViz.Count ~= #Rgns then
				RegionViz.Clear()
				local Ok, Gui = pcall(function() return game:GetService("CoreGui") end)
				if not Ok then return false end
				local F = Instance.new("Folder")
				F.Name = "RobloxBridge_Region"
				for _ = 1, #Rgns do
					for K = 1, 13 do
						local A = Instance.new("BoxHandleAdornment")
						A.Adornee = workspace.Terrain
						A.ZIndex = 1
						A.AlwaysOnTop = K > 1
						A.Transparency = K == 1 and 0.94 or 0.1
						A.Parent = F
						table.insert(RegionViz.Ads, A)
					end
				end
				F.Parent = Gui
				RegionViz.Folder, RegionViz.Count = F, #Rgns
			end
			for I, Rgn in ipairs(Rgns) do
				local Col = Bad[I] and Color3.fromRGB(255, 60, 60) or Rgn[3]
				for K, Bx in ipairs(VizBoxes(Rgn[1], Rgn[2])) do
					local A = RegionViz.Ads[(I - 1) * 13 + K]
					A.Size = Bx[2]
					A.CFrame = CFrame.new(Bx[1])
					A.Color3 = Col
				end
			end
			return true
		end

		-- ===== Маркеры: 8 углов (кубы), 6 граней (шары), центр (большой шар) =====
		-- Папка с Archivable=false: в файл плейса не сохраняется, плагин её не синхронизирует (см. Kids).
		local Pins = { Folder = nil, Regs = {}, Unsaved = false, LastMove = 0, Conf = "" }
		local FaceNames = { "грань -X", "грань -Y", "грань -Z", "грань +X", "грань +Y", "грань +Z" }

		local function Snap64(V) return math.floor(V / 64 + 0.5) * 64 end

		-- положения 15 маркеров по сырым границам B: углы 1-8, грани 9-14, центр 15
		local function MarkerSpots(B)
			local Mid = { (B[1] + B[4]) / 2, (B[2] + B[5]) / 2, (B[3] + B[6]) / 2 }
			local L = {}
			for C = 1, 8 do
				local X, Y, Z = (C - 1) % 2, ((C - 1) // 2) % 2, (C - 1) // 4
				L[C] = Vector3.new(B[1 + 3 * X], B[2 + 3 * Y], B[3 + 3 * Z])
			end
			for F = 1, 6 do
				local A = (F - 1) % 3 + 1
				local V = { Mid[1], Mid[2], Mid[3] }
				V[A] = F > 3 and B[A + 3] or B[A]
				L[8 + F] = Vector3.new(V[1], V[2], V[3])
			end
			L[15] = Vector3.new(Mid[1], Mid[2], Mid[3])
			return L
		end

		function Pins.Clear()
			local Had = Pins.Folder ~= nil
			local F = Pins.Folder
			Pins.Folder, Pins.Regs = nil, {}   -- это же останавливает цикл слежения
			if F then F:Destroy() end
			if Had and Pins.Unsaved then
				Pins.Unsaved = false
				plugin:SetSetting(TKey, RegionBox.Text)
			end
		end

		-- ставит маркеры области по её границам (то, что уже на месте, не трогает)
		function Pins.Place(R)
			local L = MarkerSpots(R.b)
			for K, P in ipairs(R.parts) do
				if (P.Position - L[K]).Magnitude > 0.01 then P.Position = L[K] end
				R.exp[P] = P.Position
			end
		end

		-- размер маркера от расстояния до камеры: всегда небольшой
		function Pins.Scale()
			local Cam = workspace.CurrentCamera
			if not Cam then return end
			local CP = Cam.CFrame.Position
			for _, R in ipairs(Pins.Regs) do
				for K, P in ipairs(R.parts) do
					local S = math.clamp((CP - P.Position).Magnitude * 0.025, 2, 400)
					if K == 15 then S *= 1.5 end
					if math.abs(P.Size.X - S) > S * 0.15 then
						P.Size = Vector3.new(S, S, S)
						local Ad = P:FindFirstChildOfClass("BoxHandleAdornment")
						if Ad then Ad.Size = Vector3.new(S, S, S) end
					end
				end
			end
		end

		-- итоговые области (с прилипанием к 64): поле, рамки, предупреждение о пересечении
		function Pins.Apply(Silent)
			local Rgns, Lines, Boxes = {}, {}, {}
			for I, R in ipairs(Pins.Regs) do
				local B, Rb = R.b, {}
				for A = 1, 3 do
					local Lo, Hi = Snap64(math.min(B[A], B[A + 3])), Snap64(math.max(B[A], B[A + 3]))
					if Hi - Lo < 64 then Hi = Lo + 64 end
					Rb[A], Rb[A + 3] = Lo, Hi
				end
				Boxes[I] = Rb
				Rgns[I] = { Vector3.new(Rb[1], Rb[2], Rb[3]), Vector3.new(Rb[4], Rb[5], Rb[6]), R.col }
				Lines[I] = RegionText(Rb)
			end
			RegionBox.Text = table.concat(Lines, "\n")
			if VizOn then RegionViz.Show(Rgns) end
			local Hits = {}
			for I = 1, #Boxes do
				for J = I + 1, #Boxes do
					if Cross(Boxes[I], Boxes[J]) then table.insert(Hits, "№" .. I .. " и №" .. J) end
				end
			end
			local Key = table.concat(Hits, ", ")
			if Key ~= Pins.Conf then
				Pins.Conf = Key
				if Key ~= "" then
					SetInfo("Области пересекаются: " .. Key .. ". Рамки красные. Раздвиньте их, иначе Pull не сработает.", Yellow)
				elseif not Silent then
					SetInfo("Пересечений нет.", Blue)
				end
			end
		end

		-- читает, что сдвинул пользователь, и пересчитывает границы
		function Pins.Sync()
			local Any = false
			for _, R in ipairs(Pins.Regs) do
				local Moved, N = {}, 0
				for K, P in ipairs(R.parts) do
					if (P.Position - R.exp[P]).Magnitude > 0.01 then
						Moved[P] = K
						N += 1
					end
				end
				if N > 0 then
					Any = true
					local B, CP = R.b, R.parts[15]
					if Moved[CP] then
						-- двигали центр: сдвигаем область целиком
						local D = CP.Position - R.exp[CP]
						local V = { D.X, D.Y, D.Z }
						for A = 1, 3 do
							B[A] += V[A]
							B[A + 3] += V[A]
						end
					else
						for P, K in pairs(Moved) do
							local Pos = P.Position
							if K <= 8 then
								local X, Y, Z = (K - 1) % 2, ((K - 1) // 2) % 2, (K - 1) // 4
								B[1 + 3 * X], B[2 + 3 * Y], B[3 + 3 * Z] = Pos.X, Pos.Y, Pos.Z
							elseif K <= 14 then
								local F = K - 8
								local A = (F - 1) % 3 + 1
								B[F > 3 and A + 3 or A] = A == 1 and Pos.X or (A == 2 and Pos.Y or Pos.Z)
							end
						end
					end
					Pins.Place(R)
				end
			end
			if Any then
				Pins.Apply()
				Pins.LastMove = os.clock()
				Pins.Unsaved = true
			end
		end

		function Pins.Show(Rgns)
			Pins.Clear()
			local Fold = Instance.new("Folder")
			Fold.Name = "RobloxBridge_Pins"
			Fold.Archivable = false
			Pins.Regs, Pins.Conf = {}, ""
			for I, Rg in ipairs(Rgns) do
				local R = { b = { Rg[1].X, Rg[1].Y, Rg[1].Z, Rg[2].X, Rg[2].Y, Rg[2].Z }, parts = {}, exp = {}, col = Rg[3] }
				for K = 1, 15 do
					local P = Instance.new("Part")
					P.Name = "Область " .. I .. " · " .. (K <= 8 and ("угол " .. K) or (K <= 14 and FaceNames[K - 8] or "центр (двигать целиком)"))
					P.Shape = K <= 8 and Enum.PartType.Block or Enum.PartType.Ball
					P.Size = Vector3.new(8, 8, 8)
					P.Anchored = true
					P.CanCollide, P.CanTouch, P.CastShadow = false, false, false
					P.Material = Enum.Material.Neon
					P.Color = Rg[3]
					P.Transparency = 0.15
					P.Archivable = false
					local Ad = Instance.new("BoxHandleAdornment")   -- виден сквозь террейн
					Ad.Adornee = P
					Ad.Size = P.Size
					Ad.AlwaysOnTop = true
					Ad.ZIndex = 2
					Ad.Transparency = 0.55
					Ad.Color3 = Rg[3]
					Ad.Parent = P
					P.Parent = Fold
					R.parts[K] = P
				end
				R.exp = {}
				Pins.Regs[I] = R
				Pins.Place(R)
			end
			Fold.Parent = workspace
			Pins.Folder = Fold
			Pins.Scale()
			if Pins.Regs[1] then Selection:Set({ Pins.Regs[1].parts[15] }) end
			task.spawn(function()
				local N = 0
				while Pins.Folder == Fold do
					N += 1
					local Ok, E = pcall(Pins.Sync)
					if not Ok then warn("RobloxBridge: маркеры: " .. tostring(E)) end
					if N % 5 == 0 then pcall(Pins.Scale) end
					if Pins.Unsaved and os.clock() - Pins.LastMove > 0.6 then
						Pins.Unsaved = false
						plugin:SetSetting(TKey, RegionBox.Text)
					end
					task.wait(0.05)
				end
			end)
		end

		plugin.Unloading:Connect(RegionViz.Clear)
		plugin.Unloading:Connect(Pins.Clear)

		RedrawViz = function()
			if not VizOn then return end
			local Rgns = VizRegions(RegionBox.Text)
			if #Rgns == 0 then RegionViz.Clear() return end
			RegionViz.Show(Rgns)
		end

		-- текст областей изменился снаружи (кнопки, автопоиск, ввод)
		local function RegionsChanged()
			plugin:SetSetting(TKey, RegionBox.Text)
			RedrawViz()
			if PinOn then Pins.Show(VizRegions(RegionBox.Text)) end
		end

		-- ===== Автопоиск областей =====
		-- Куски 64 студа, мир ±128000 → индексы -2000..1999
		local function PK(X, Y, Z) return ((X + 2048) * 4096 + (Y + 2048)) * 4096 + (Z + 2048) end
		local function UnPK(K) return K // 16777216 - 2048, (K // 4096) % 4096 - 2048, K % 4096 - 2048 end

		local function HasTerrain(CX, CY, CZ)
			local Lo = Vector3.new(CX * 64, CY * 64, CZ * 64)
			return AnySolid((workspace.Terrain:ReadVoxels(Region3.new(Lo, Lo + Vector3.new(64, 64, 64)), 4)))
		end

		-- коробки в индексах кусков, границы включительно
		local function Meet(A, B)
			return A[1] <= B[4] and B[1] <= A[4] and A[2] <= B[5] and B[2] <= A[5] and A[3] <= B[6] and B[3] <= A[6]
		end
		local function BoxOf(L)
			local B = { math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge }
			for _, K in ipairs(L) do
				local X, Y, Z = UnPK(K)
				if X < B[1] then B[1] = X end
				if Y < B[2] then B[2] = Y end
				if Z < B[3] then B[3] = Z end
				if X > B[4] then B[4] = X end
				if Y > B[5] then B[5] = Y end
				if Z > B[6] then B[6] = Z end
			end
			return B
		end
		local function Union(A, B)
			return { math.min(A[1], B[1]), math.min(A[2], B[2]), math.min(A[3], B[3]),
				math.max(A[4], B[4]), math.max(A[5], B[5]), math.max(A[6], B[6]) }
		end

		-- Лучший разрез группы плоскостью между слоями кусков (по лучшей оси). nil, если выгода мала.
		local function BestCut(G)
			local B = G.box
			local Vol = (B[4] - B[1] + 1) * (B[5] - B[2] + 1) * (B[6] - B[3] + 1)
			local Co = { {}, {}, {} }
			for I, K in ipairs(G.list) do
				Co[1][I], Co[2][I], Co[3][I] = UnPK(K)
			end
			local Best, BestTotal = nil, Vol
			for Ax = 1, 3 do
				if B[Ax + 3] > B[Ax] then
					local O1, O2 = Ax % 3 + 1, (Ax + 1) % 3 + 1
					local Sl, Ls = {}, {}
					for I = 1, #G.list do
						local V, A1, A2 = Co[Ax][I], Co[O1][I], Co[O2][I]
						local S = Sl[V]
						if not S then
							Sl[V] = { A1, A1, A2, A2 }
							Ls[#Ls + 1] = V
						else
							if A1 < S[1] then S[1] = A1 end
							if A1 > S[2] then S[2] = A1 end
							if A2 < S[3] then S[3] = A2 end
							if A2 > S[4] then S[4] = A2 end
						end
					end
					table.sort(Ls)
					local N = #Ls
					if N >= 2 then
						local Suf = {}
						local A1, B1, A2, B2 = math.huge, -math.huge, math.huge, -math.huge
						for I = N, 2, -1 do
							local S = Sl[Ls[I]]
							A1, B1 = math.min(A1, S[1]), math.max(B1, S[2])
							A2, B2 = math.min(A2, S[3]), math.max(B2, S[4])
							Suf[I] = (Ls[N] - Ls[I] + 1) * (B1 - A1 + 1) * (B2 - A2 + 1)
						end
						A1, B1, A2, B2 = math.huge, -math.huge, math.huge, -math.huge
						for I = 1, N - 1 do
							local S = Sl[Ls[I]]
							A1, B1 = math.min(A1, S[1]), math.max(B1, S[2])
							A2, B2 = math.min(A2, S[3]), math.max(B2, S[4])
							local Tot = (Ls[I] - Ls[1] + 1) * (B1 - A1 + 1) * (B2 - A2 + 1) + Suf[I + 1]
							if Tot < BestTotal then
								BestTotal = Tot
								Best = { Ax = Ax, At = Ls[I] }
							end
						end
					end
				end
			end
			if Best and Vol - BestTotal >= 0.2 * Vol and Vol - BestTotal >= 16 then return Best end
			return nil
		end

		local function TerrainAuto()
			NeedReady()
			local Terr = workspace.Terrain
			local OldText = RegionBox.Text
			local OkR, Regs = pcall(ParseRegions, OldText)
			if not OkR then Regs = {} end

			-- области из поля в индексах кусков (включительно)
			local Cb, Total = {}, 0
			for _, Rg in ipairs(Regs) do
				local B = { Rg[1] // 64, Rg[2] // 64, Rg[3] // 64, Rg[4] // 64 - 1, Rg[5] // 64 - 1, Rg[6] // 64 - 1 }
				table.insert(Cb, B)
				Total += (B[4] - B[1] + 1) * (B[5] - B[2] + 1) * (B[6] - B[3] + 1)
			end
			local function InRegs(X, Y, Z)
				for _, B in ipairs(Cb) do
					if X >= B[1] and X <= B[4] and Y >= B[2] and Y <= B[5] and Z >= B[3] and Z <= B[6] then return true end
				end
				return false
			end

			local Occ, Queue, Seen, N = {}, {}, {}, 0   -- куски с данными / очередь роста / проверенные вне областей
			local Done, TY = 0, os.clock()
			local function Pulse()
				Done += 1
				Prog.Step(Done)
				if os.clock() - TY > 0.05 then
					task.wait()
					TY = os.clock()
				end
			end
			-- проверить кусок вне областей; если там террейн — запомнить
			local function Try(X, Y, Z)
				if X < -2000 or X > 1999 or Y < -2000 or Y > 1999 or Z < -2000 or Z > 1999 then return end
				local K = PK(X, Y, Z)
				if Occ[K] or Seen[K] or InRegs(X, Y, Z) then return end
				Seen[K] = true
				if HasTerrain(X, Y, Z) then
					Occ[K] = true
					N += 1
					Queue[#Queue + 1] = K
				end
				Pulse()
			end

			-- 1. читаем области из поля
			Prog.Stage("Террейн: поиск, чтение областей", Total)
			Done = 0
			for _, B in ipairs(Cb) do
				for X = B[1], B[4] do
					for Y = B[2], B[5] do
						for Z = B[3], B[6] do
							if HasTerrain(X, Y, Z) then
								local K = PK(X, Y, Z)
								Occ[K] = true
								N += 1
								Queue[#Queue + 1] = K
							end
							Pulse()
						end
					end
				end
			end

			-- 2. камера, то, на что она смотрит, выделенное
			Prog.Stage("Террейн: поиск рядом с камерой и выделенным", 0)
			Done = 0
			local Spots = {}
			local Cam = workspace.CurrentCamera
			if Cam then
				local CF = Cam.CFrame
				table.insert(Spots, CF.Position)
				local Pr = RaycastParams.new()
				Pr.FilterType = Enum.RaycastFilterType.Exclude
				Pr.FilterDescendantsInstances = Pins.Folder and { Pins.Folder } or {}
				local OkRay, Res = pcall(function() return workspace:Raycast(CF.Position, CF.LookVector * 20000, Pr) end)
				if OkRay and Res and Res.Instance == Terr then table.insert(Spots, Res.Position) end
			end
			for _, S in ipairs(Selection:Get()) do
				if S:IsA("BasePart") then
					table.insert(Spots, S.Position)
				elseif S:IsA("Model") then
					table.insert(Spots, S:GetPivot().Position)
				end
			end
			for _, P in ipairs(Spots) do
				local PX, PY, PZ = math.floor(P.X / 64), math.floor(P.Y / 64), math.floor(P.Z / 64)
				for DX = -2, 2 do
					for DY = -2, 2 do
						for DZ = -2, 2 do Try(PX + DX, PY + DY, PZ + DZ) end
					end
				end
			end

			-- 3. рост: идём по соседям найденных кусков, пока террейн не кончится
			Prog.Stage("Террейн: поиск, рост за пределы областей", 0)
			Done = 0
			local Head = 1
			while Head <= #Queue do
				local X, Y, Z = UnPK(Queue[Head])
				Head += 1
				for DX = -1, 1 do
					for DY = -1, 1 do
						for DZ = -1, 1 do
							if DX ~= 0 or DY ~= 0 or DZ ~= 0 then Try(X + DX, Y + DY, Z + DZ) end
						end
					end
				end
				Pulse()
				if Head % 50 == 0 then Prog.label = "Террейн: поиск, найдено кусков с данными: " .. N end
			end
			if N == 0 then
				error("Террейн не найден. Задайте грубую область вокруг него, либо подлетите камерой и посмотрите на террейн (или выделите деталь рядом) и повторите.", 0)
			end

			-- 4. связные острова
			Prog.Stage("Террейн: разбиение на области", 0)
			Done = 0
			local Mark, Groups = {}, {}
			for K in pairs(Occ) do
				if not Mark[K] then
					Mark[K] = true
					local L, I = { K }, 1
					while I <= #L do
						local X, Y, Z = UnPK(L[I])
						I += 1
						for DX = -1, 1 do
							for DY = -1, 1 do
								for DZ = -1, 1 do
									local NK = PK(X + DX, Y + DY, Z + DZ)
									if Occ[NK] and not Mark[NK] then
										Mark[NK] = true
										L[#L + 1] = NK
									end
								end
							end
						end
						Pulse()
					end
					table.insert(Groups, { list = L, box = BoxOf(L) })
				end
			end

			-- 5. острова с пересекающимися коробками объединяем
			local Merged = true
			while Merged do
				Merged = false
				for I = 1, #Groups do
					for J = I + 1, #Groups do
						if Meet(Groups[I].box, Groups[J].box) then
							local GI, GJ = Groups[I], Groups[J]
							table.move(GJ.list, 1, #GJ.list, #GI.list + 1, GI.list)
							GI.box = Union(GI.box, GJ.box)
							table.remove(Groups, J)
							Merged = true
							break
						end
					end
					if Merged then break end
					Pulse()
				end
			end

			-- 6. режем каждую группу плоскостью там, где это экономит объём (максимум 32 области)
			local MaxRegs = 32
			local Work, Final = Groups, {}
			while #Work > 0 do
				local G = table.remove(Work)
				local Cut = (#Final + #Work + 1 < MaxRegs) and BestCut(G) or nil
				if Cut then
					local L1, L2 = {}, {}
					for _, K in ipairs(G.list) do
						local V = select(Cut.Ax, UnPK(K))
						if V <= Cut.At then L1[#L1 + 1] = K else L2[#L2 + 1] = K end
					end
					Work[#Work + 1] = { list = L1, box = BoxOf(L1) }
					Work[#Work + 1] = { list = L2, box = BoxOf(L2) }
				else
					Final[#Final + 1] = G
				end
				Pulse()
			end

			-- 7. в студы (без запаса: граница проверяется точно), сортировка
			local Items, Vol = {}, 0
			for _, G in ipairs(Final) do
				local B = G.box
				local V = (B[4] - B[1] + 1) * (B[5] - B[2] + 1) * (B[6] - B[3] + 1)
				Vol += V
				table.insert(Items, { r = { B[1] * 64, B[2] * 64, B[3] * 64, (B[4] + 1) * 64, (B[5] + 1) * 64, (B[6] + 1) * 64 },
					n = #G.list, v = V })
			end
			table.sort(Items, function(A, B)
				if A.r[1] ~= B.r[1] then return A.r[1] < B.r[1] end
				if A.r[2] ~= B.r[2] then return A.r[2] < B.r[2] end
				return A.r[3] < B.r[3]
			end)
			local Out = {}
			for I, It in ipairs(Items) do Out[I] = It.r end
			local NewText = RegionsText(Out)
			local OkP, ErrP = pcall(ParseRegions, NewText)
			if not OkP then error("Автопоиск дал некорректные области: " .. tostring(ErrP), 0) end

			local Lines = {}
			for I, It in ipairs(Items) do
				table.insert(Lines, string.format("  Область №%d: кусков с данными %d из %d (%d%%)", I, It.n, It.v, math.floor(It.n / It.v * 100)))
			end
			if string.find(OldText, "%d") then
				table.insert(Lines, "  Прежние области (скопируйте, если нужны):")
				for L in string.gmatch(OldText, "[^\r\n]+") do table.insert(Lines, "  " .. L) end
			end
			RegionBox.Text = NewText
			RegionsChanged()
			SetInfo(string.format("Найдено: областей %d, кусков с данными %d (всего в областях %d кусков). Проверьте рамки и нажмите «Studio → файл».",
				#Out, N, Vol), Green)
			ShowLines(Lines)
		end

		-- ---------- карточка ----------
		local TC = Card(Root, 6)
		TC.Visible = false
		Text(TC, 1, "Террейн", { Bold = true, Size = 15 })
		Text(TC, 2, "Отдельно от обычного Pull/Push. Области в студах «x0,y0,z0  x1,y1,z1», по одной на строке, округляются до 64, пересекаться не могут. Файл задаётся в «Настройки плейса → Файл террейна».",
			{ Color = C.Dim, Size = 12 })
		RegionBox = Box(TC, 3, 64, true)
		RegionBox.PlaceholderText = "x0,y0,z0  x1,y1,z1\n(следующая область — с новой строки)"
		RegionBox.Text = plugin:GetSetting(TKey) or "-512,-256,-512  512,256,512"
		local TFind = Button(TC, 4, "🔍 Найти области автоматически", "normal")
		local TSel = Button(TC, 5, "Область из выделенного (заменить)", "link")
		local TAdd = Button(TC, 6, "＋ Добавить область из выделенного", "link")
		local PinBtn = Button(TC, 7, "✋ Двигать области мышью", "link")
		local VizBtn = Button(TC, 8, "👁 Показать области", "link")

		Click(VizBtn, function()
			VizOn = not VizOn
			VizBtn.Text = VizOn and "👁 Скрыть области" or "👁 Показать области"
			if VizOn then RedrawViz() else RegionViz.Clear() end
		end)

		Click(PinBtn, function()
			PinOn = not PinOn
			PinBtn.Text = PinOn and "✋ Готово (убрать маркеры)" or "✋ Двигать области мышью"
			if PinOn then
				local Rgns = VizRegions(RegionBox.Text)
				if #Rgns == 0 then
					PinOn = false
					PinBtn.Text = "✋ Двигать области мышью"
					SetInfo("Нет областей: задайте их цифрами, из выделенного или кнопкой автопоиска.", Yellow)
					return
				end
				VizOn = true
				VizBtn.Text = "👁 Скрыть области"
				Pins.Show(Rgns)
				RedrawViz()
				SetInfo("У каждой области свой цвет. Кубы — углы, шарики — грани (меняют размер), большой шар в центре двигает область целиком. "
					.. "Тяните инструментом Move; рамка и цифры прилипают к сетке 64. Пересечения подсвечиваются красным. "
					.. "Маркеры лежат в Workspace/RobloxBridge_Pins: если маркер внутри террейна, выберите его там.", Blue)
			else
				Pins.Clear()
			end
		end)

		RegionBox.FocusLost:Connect(RegionsChanged)

		local TRow = make("Frame", { LayoutOrder = 9, Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1 }, TC)
		List(TRow, 6, Enum.FillDirection.Horizontal)
		local TPull = Button(TRow, 1, "", "pull", UDim2.new(0.5, -3, 1, 0))
		local TPush = Button(TRow, 2, "", "push", UDim2.new(0.5, -3, 1, 0))
		TPull.RichText, TPush.RichText = true, true
		TPull.Text = '<b>Studio → файл</b>\n<font size="11">Террейн · сохранить</font>'
		TPush.Text = '<b>Файл → Studio</b>\n<font size="11">Террейн · предпросмотр</font>'
		local TApply = Button(TC, 10, "✔ Применить террейн", "primary")
		local TUndoBtn = Button(TC, 11, "↩ Отменить террейн", "normal")

		local function TerrainButtons()
			Enable(TFind, not Working)
			Enable(TSel, not Working)
			Enable(TAdd, not Working)
			Enable(PinBtn, not Working)
			Enable(TPull, not Working)
			Enable(TPush, not Working)
			TApply.Visible = TPendingN ~= nil
			Enable(TApply, not Working)
			TUndoBtn.Visible = TJournal ~= nil
			Enable(TUndoBtn, not Working)
		end
		local PrevRefresh = RefreshButtons
		RefreshButtons = function()
			PrevRefresh()
			TerrainButtons()
		end
		TerrainButtons()

		State.T = {
			Pull = function() Run("Террейн: Pull", TerrainPull) end,
			Push = function() Run("Террейн: Push", TerrainPreview) end,
			Apply = function() Run("Террейн: применяю", TerrainApply) end,
			Undo = function() Run("Террейн: отмена", TerrainUndoRun) end,
			Auto = function() Run("Террейн: поиск областей", TerrainAuto) end,
		}
		State.TS = {
			Apply = function() return TPendingN ~= nil end,
			Undo = function() return TJournal ~= nil end,
		}
		Click(TFind, State.T.Auto)
		Click(TPull, State.T.Pull)
		Click(TPush, State.T.Push)
		Click(TApply, State.T.Apply)
		Click(TUndoBtn, State.T.Undo)

		-- область вокруг выделенной детали/модели; nil, если ничего подходящего не выделено
		local function SelRegion()
			local S = Selection:Get()[1]
			local CF, Sz
			if S and S:IsA("BasePart") then CF, Sz = S.CFrame, S.Size
			elseif S and S:IsA("Model") then CF, Sz = S:GetBoundingBox()
			else SetInfo("Выделите деталь или модель вокруг террейна", Yellow); return nil end
			local H = Sz / 2
			local function Ext(A)
				return math.abs(CF.RightVector[A]) * H.X + math.abs(CF.UpVector[A]) * H.Y + math.abs(CF.LookVector[A]) * H.Z
			end
			local P, EX, EY, EZ = CF.Position, Ext("X"), Ext("Y"), Ext("Z")
			return string.format("%d,%d,%d  %d,%d,%d", math.floor(P.X - EX), math.floor(P.Y - EY), math.floor(P.Z - EZ),
				math.ceil(P.X + EX), math.ceil(P.Y + EY), math.ceil(P.Z + EZ)), S.Name
		end

		Click(TSel, function()
			local Line, Name = SelRegion()
			if not Line then return end
			RegionBox.Text = Line
			RegionsChanged()
			SetInfo("Область взята из «" .. Name .. "». При Pull она округлится наружу до 64 студов.", Blue)
		end)

		Click(TAdd, function()
			local Line, Name = SelRegion()
			if not Line then return end
			local Old = string.match(RegionBox.Text, "^%s*(.-)%s*$")
			RegionBox.Text = Old == "" and Line or (Old .. "\n" .. Line)
			RegionsChanged()
			SetInfo("Добавлена область из «" .. Name .. "». При Pull она округлится наружу до 64 студов.", Blue)
		end)

		task.spawn(function()
			while true do
				TC.Visible = State.Found and State.Place == "ready"
				task.wait(0.5)
			end
		end)
	end)()

	-- ===== Карточка «Инструменты» =====
	local ToolsCard = Card(Root, 5)
	ToolsCard.Visible = false
	Text(ToolsCard, 1, "Инструменты", { Bold = true, Size = 15 })
	local SetBtn = Button(ToolsCard, 2, "⚙ Настройки плейса…", "link")
	local DebugBtn = Button(ToolsCard, 3, "", "link")
	DebugBtn.TextSize = 13

	local function RefreshDebug()
		DebugBtn.Text = "Отладка запросов: " .. (DebugOn and "вкл (Output плагина + лог приложения)" or "выкл")
	end
	Click(DebugBtn, function()
		DebugOn = not DebugOn
		plugin:SetSetting("Debug", DebugOn)
		RefreshDebug()
	end)
	RefreshDebug()

	local WasReady = false
	task.spawn(function()
		while true do
			local Show = State.Found and State.Place == "ready"
			SyncCard.Visible = Show
			ChangesCard.Visible = Show and HasLines
			ObjCard.Visible = Show
			SetBtn.Visible = Show
			ToolsCard.Visible = State.Found
			if Show and not WasReady then ShowObject(true) end
			WasReady = Show
			task.wait(0.5)
		end
	end)

	-- ===== Окно настроек плейса =====
	local SW = plugin:CreateDockWidgetPluginGui("RobloxBridgeSettings",
		DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 380, 580, 300, 300))
	SW.Title = "RobloxBridge: настройки плейса"

	local SRoot = make("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = AutoY, ScrollBarThickness = 6, BackgroundColor3 = C.Bg }, SW)
	List(SRoot, 8)
	Pad(SRoot, 8, 12, 10, 8)

	local InfoL = Text(SRoot, 1, "", { Color = C.Dim, Size = 13 })

	local AutoCard = Card(SRoot, 2)
	Text(AutoCard, 1, "Автовынос в отдельные файлы", { Bold = true, Size = 15 })
	Text(AutoCard, 2, "Если объект вместе со всеми вложенными занимает в .bridge больше N строк (1 строка = 1 объект со свойствами), "
		.. "он сам выносится в отдельный файл Scene/<путь>.bridge. По умолчанию 500. 0 — выключить: тогда выносите только вы "
		.. "кнопкой «Вынести в файл». При N > 0 объект длиннее N строк нельзя вернуть в общий файл: он вынесется снова. "
		.. "Новое значение применится при следующем Pull.", { Color = C.Dim, Size = 13 })
	local AutoBox = Box(AutoCard, 3, 28, false)

	local Scr = { Card = Card(SRoot, 4) }
	Text(Scr.Card, 1, "Скрипты", { Bold = true, Size = 15 })
	Text(Scr.Card, 2, "Расширение НОВЫХ скриптов: luau (по умолчанию) или lua. Уже существующие файлы не переименовываются и "
		.. "остаются как есть.", { Color = C.Dim, Size = 13 })
	Scr.Ext = Box(Scr.Card, 3, 28, false)
	Text(Scr.Card, 4, "Новый скрипт короче N строк остаётся кодом (@code) в .bridge, длиннее выносится в файл. "
		.. "По умолчанию 8, 0 — всегда в файл (0–200).", { Color = C.Dim, Size = 13 })
	Scr.Inl = Box(Scr.Card, 5, 28, false)

	local SvcCard = Card(SRoot, 3)
	Text(SvcCard, 1, "Сервисы", { Bold = true, Size = 15 })
	Text(SvcCard, 2, "По одному в строке. Сервисы вне списка не синхронизируются.", { Color = C.Dim, Size = 13 })
	local SvcBox = Box(SvcCard, 3, 150, true)

	local IgnCard = Card(SRoot, 5)
	Text(IgnCard, 1, "Игнорировать", { Bold = true, Size = 15 })
	Text(IgnCard, 2, "Пути объектов вместе с потомками, по одному в строке, например Workspace/Camera.", { Color = C.Dim, Size = 13 })
	local IgnBox = Box(IgnCard, 3, 70, true)

	local TerrCard = Card(SRoot, 6)
	Text(TerrCard, 1, "Файл террейна", { Bold = true, Size = 15 })
	Text(TerrCard, 2, "Путь к файлу вокселей: относительно папки плейса, с ../ или полный. По умолчанию Terrain.voxels. "
		.. "Старый файл при смене пути не переносится: перенесите его сами или сделайте «Террейн: Pull» заново.",
		{ Color = C.Dim, Size = 13 })
	local TerrBox = Box(TerrCard, 3, 28, false)

	local SaveBtn = Button(SRoot, 7, "Сохранить настройки", "primary", UDim2.new(1, 0, 0, 32))
	local StatL = Text(SRoot, 8, "", { Color = C.Dim, Size = 13 })

	local SplCard = Card(SRoot, 9)
	Text(SplCard, 1, "Вынесено в отдельные файлы", { Bold = true, Size = 15 })
	Text(SplCard, 2, "Клик по пути — выделить в Explorer. «Вернуть» — вернуть в общий файл. ✕ — убрать только запись (для «фантомов»), объекты и файлы не трогаются.", { Color = C.Dim, Size = 13 })
	local SplitsFrame = make("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY,
		BackgroundTransparency = 1 }, SplCard)
	List(SplitsFrame, 2)
	local ReloadBtn = Button(SplCard, 4, "Обновить", "normal")

	local function SStatus(Str, Color)
		StatL.Text = Str
		StatL.TextColor3 = Color or C.Text()
	end

	local function Do(Fn)
		if Working then return end
		Working = true
		RefreshButtons()
		task.spawn(function()
			local Ok, Err = pcall(Fn)
			if not Ok then SStatus("✖ " .. tostring(Err), Red) end
			Working = false
			RefreshButtons()
		end)
	end

	-- Объект по пути (спуск по уровням, без обхода всего дерева)
	local function Find(PathStr)
		local Inst, Acc = nil, ""
		for Seg in string.gmatch(PathStr, "[^/]+") do
			if Acc == "" then
				Inst, Acc = game:FindService(Seg), Seg
			else
				if not Inst then return nil end
				local Want, Found = Acc .. "/" .. Seg, nil
				for _, K in ipairs(Kids(Inst, Acc)) do
					if K[1] == Want then Found = K[2]; break end
				end
				Inst, Acc = Found, Want
			end
		end
		return Inst
	end

	local Load
	local function Fill(D)
		InfoL.Text = "PlaceId " .. tostring(D.placeId) .. " · создан " .. tostring(D.created)
		AutoBox.Text = tostring(D.autoSplit)
		Scr.Ext.Text = tostring(D.scriptExt or "luau")
		Scr.Inl.Text = tostring(D.inlineLines or 8)
		SvcBox.Text = table.concat(D.services or {}, "\n")
		IgnBox.Text = table.concat(D.ignore or {}, "\n")
		TerrBox.Text = tostring(D.terrainFile or "Terrain.voxels")
		for _, Ch in ipairs(SplitsFrame:GetChildren()) do
			if Ch:IsA("Frame") or Ch:IsA("TextLabel") then Ch:Destroy() end
		end
		local Items = D.splits or {}
		if #Items == 0 then
			make("TextLabel", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
				TextXAlignment = Left, Font = Enum.Font.SourceSans, TextSize = 13,
				Text = "(ничего не вынесено)", TextColor3 = Dim() }, SplitsFrame)
		end
		for I, S in ipairs(Items) do
			local RowF = make("Frame", { LayoutOrder = I, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1 }, SplitsFrame)
			List(RowF, 4, Enum.FillDirection.Horizontal)
			local Name = Button(RowF, 1, S.path .. (S.exists and ("  (" .. S.lines .. " стр.)") or "  (файла нет!)"),
				"link", UDim2.new(1, -112, 1, 0))
			Name.Font = Enum.Font.Code
			Name.TextSize = 12
			Name.TextWrapped = false
			Name.TextTruncate = Enum.TextTruncate.AtEnd
			Name.TextColor3 = S.exists and C.Text() or Red
			local Back = Button(RowF, 2, "Вернуть", "normal", UDim2.new(0, 74, 1, 0))
			local Del = Button(RowF, 3, "✕", "normal", UDim2.new(0, 30, 1, 0))
			Click(Name, function()
				local Inst = Find(S.path)
				if Inst then Selection:Set({ Inst }) else SStatus("Объект не найден в Studio: " .. S.path, Yellow) end
			end)
			Click(Back, function()
				Do(function()
					local Rs, E = Call("/unsplit" .. Q(), { path = S.path })
					if E then error(E, 0) end
					SStatus(Rs.text or "Готово", Rs.warn and Yellow or Green)
					Load()
					ShowObject(true)
				end)
			end)
			Click(Del, function()
				Do(function()
					local Rs, E = Call("/split/forget" .. Q(), { path = S.path })
					if E then error(E, 0) end
					SStatus(Rs.text or "Запись убрана", Green)
					Load()
					ShowObject(true)
				end)
			end)
		end
	end

	Load = function()
		local D, E = Call("/settings" .. Q())
		if E then error(E, 0) end
		Fill(D)
	end

	local function SplitLines(Str)
		local Res = {}
		for L in string.gmatch(Str, "[^\r\n]+") do
			local T = string.match(L, "^%s*(.-)%s*$")
			if T ~= "" then table.insert(Res, T) end
		end
		return Res
	end

	local function DoSave()
		local N = tonumber(AutoBox.Text)
		if not N or N < 0 or N ~= math.floor(N) then error("Автовынос: нужно целое число, 0 или больше", 0) end
		local Svc = SplitLines(SvcBox.Text)
		if #Svc == 0 then error("Список сервисов не может быть пустым", 0) end
		local Bad = {}
		for _, S in ipairs(Svc) do
			if not pcall(game.GetService, game, S) then table.insert(Bad, S) end
		end
		if #Bad > 0 then error("Нет такого сервиса в Studio: " .. table.concat(Bad, ", "), 0) end
		local Ext = string.lower(string.gsub(Scr.Ext.Text, "^%s*%.?(.-)%s*$", "%1"))
		if Ext ~= "lua" and Ext ~= "luau" then error("Расширение скриптов: lua или luau", 0) end
		local Inl = tonumber(Scr.Inl.Text)
		if not Inl or Inl < 0 or Inl > 200 or Inl ~= math.floor(Inl) then error("Строк в @code: целое число 0–200", 0) end
		local TF = string.match(TerrBox.Text, "^%s*(.-)%s*$")
		local D, E = Call("/settings" .. Q(), { autoSplit = N, services = Svc, ignore = SplitLines(IgnBox.Text), scriptExt = Ext, inlineLines = Inl, terrainFile = TF })
		if E then error(E, 0) end
		SStatus((D.text or "Готово") .. ". Чтобы изменения попали в файлы, сделайте Pull.", Green)
		ShowObject(true)
		Fill(D)
	end

	Click(SaveBtn, function() Do(DoSave) end)
	Click(ReloadBtn, function() Do(Load) end)
	Click(SetBtn, function()
		SW.Enabled = true
		Do(Load)
	end)

	-- ===== Команды из приложения =====
	OnCommand = function(Cmd)
		if Working then
			SetInfo("Плагин занят, команда «" .. Cmd .. "» пропущена", Yellow)
			return
		end
		if Cmd == "pull" then
			Run("Pull", DoPull)
		elseif Cmd == "preview" then
			Run("Push: предпросмотр", DoPreview)
		elseif Cmd == "undo" then
			if not UndoJ then
				SetInfo("Нечего отменять", Yellow)
				return
			end
			Run("Отмена", DoUndo)
		elseif Cmd == "apply" then
			if not Pending then
				SetInfo("Нечего применять: сначала сделайте предпросмотр", Yellow)
				return
			end
			Run("Применяю", DoApply)
		elseif Cmd == "terrain-pull" then State.T.Pull()
		elseif Cmd == "terrain-push" then State.T.Push()
		elseif Cmd == "terrain-apply" then State.T.Apply()
		elseif Cmd == "terrain-undo" then State.T.Undo()
		end
	end
end