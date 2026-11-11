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

local function Card(Parent, Order)
	local F = make("Frame", { LayoutOrder = Order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY,
		BorderSizePixel = 0, BackgroundColor3 = C.Card }, Parent)
	Corner(F, 8)
	make("UIStroke", { Color = C.Line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, F)
	Pad(F, 10, 10, 10, 10)
	List(F, 6)
	return F
end

local function Button(Parent, Order, Str, Style, Size)
	local B = make("TextButton", { LayoutOrder = Order, Size = Size or UDim2.new(1, 0, 0, Style == "link" and 22 or 30),
		BorderSizePixel = 0, AutoButtonColor = false, TextWrapped = true, TextSize = 14, Text = Str,
		Font = Style == "primary" and Enum.Font.SourceSansBold or Enum.Font.SourceSans,
		BackgroundColor3 = Style == "primary" and C.Accent or C.Btn,
		TextColor3 = Style == "primary" and White or (Style == "link" and Blue or C.BtnText) }, Parent)
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
		if Body then Json = HttpService:JSONEncode(Body); Req.Body = Json end
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

	-- ===== Схема, значения =====
	local Schema, SchemaHash
	local PropCache, DefCache = {}, {}

	local SkipProp = { Name = true, Source = true, UniqueId = true, HistoryId = true, SourceAssetId = true,
		ScriptGuid = true, Color3uint8 = true, BrickColor = true }
	local Simple = { bool = true, int = true, float = true, double = true, int64 = true, string = true, Content = true,
		Vector2 = true, Vector3 = true, UDim = true, UDim2 = true, Color3 = true, CFrame = true, Rect = true, NumberRange = true }
	local function Supported(T) return Simple[T] or string.sub(T, 1, 5) == "Enum:" end
	local function GetProp(I, N) return I[N] end

	local function R(X)
		if X ~= X or X == math.huge or X == -math.huge then return 0 end
		local V = math.floor(X * 1000 + 0.5) / 1000
		if V == 0 then return 0 end
		return V
	end

	local function Enc(T, V)
		if T == "bool" then return { t = "b", v = V }
		elseif T == "int" or T == "float" or T == "double" or T == "int64" then return { t = "n", v = R(V) }
		elseif T == "string" then return { t = "s", v = V }
		elseif T == "Content" then
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

	local function PropsOf(Class)
		local Cached = PropCache[Class]
		if Cached then return Cached end
		local Map, Cur, Guard = {}, Class, 0
		while Cur and Cur ~= "" and Guard < 40 do
			local Info = Schema.Classes[Cur]
			if not Info then break end
			for N, T in pairs(Info.Props) do
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
			if not Ch:IsA("PartOperation") then table.insert(Items, Ch) end
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

	-- ===== Сериализация Studio =====
	local Counter = 0
	local function Node(Inst, Path, Ign, Skipped)
		Counter += 1
		if Counter % 200 == 0 then task.wait() end
		local Class = Inst.ClassName
		local N = { c = Class, n = Inst.Name }
		local Info = PropsOf(Class)
		local Def = DefaultsOf(Class)

		local P, Any = {}, false
		for _, E in ipairs(Info.list) do
			local Ok, V = pcall(GetProp, Inst, E[1])
			if Ok and V ~= nil then
				local Ok2, Val = pcall(Enc, E[2], V)
				if Ok2 and Val and not (Def and Def.sig[E[1]] == Sig(Val)) then
					P[E[1]] = Val
					Any = true
				end
			end
		end
		if Inst:IsA("LuaSourceContainer") then
			local Ok, S = pcall(GetProp, Inst, "Source")
			if Ok then P.Source = { t = "s", v = S }; Any = true end
		end
		if Any then N.p = P end
		for _, T in ipairs(Info.unsup) do Skipped[T] = (Skipped[T] or 0) + 1 end

		local A, AnyA = {}, false
		for K, V in pairs(Inst:GetAttributes()) do
			local E = EncAttr(V)
			if E then A[K] = E; AnyA = true end
		end
		if AnyA then N.a = A end

		local Tags = Inst:GetTags()
		if #Tags > 0 then table.sort(Tags); N.g = Tags end

		local Out = {}
		for _, K in ipairs(Kids(Inst, Path)) do
			if not Ign[K[1]] then table.insert(Out, Node(K[2], K[1], Ign, Skipped)) end
		end
		if #Out > 0 then N.k = Out end
		return N
	end

	local function Collect(Cfg)
		Counter = 0
		local Ign = {}
		for _, P in ipairs(Cfg.ignore or {}) do Ign[P] = true end
		local Svc, Skipped = {}, {}
		for _, Name in ipairs(Cfg.services or {}) do
			local S = game:FindService(Name)
			if S then Svc[Name] = Node(S, Name, Ign, Skipped) end
		end
		return Svc, Skipped
	end

	-- Режет по детям сервиса на части <= CHUNK и отправляет. Возвращает ответ на последнюю часть.
	local SetInfo
	local function Send(Route, Svc, Skipped, Extra)
		local Session = HttpService:GenerateGUID(false)
		local Parts, Names = {}, {}
		for N in pairs(Svc) do table.insert(Names, N) end
		table.sort(Names)
		for _, N in ipairs(Names) do
			local S = Svc[N]
			local Group, Size, First = {}, 0, true
			local function Flush()
				local Copy = { c = S.c, n = S.n, k = Group }
				if First then Copy.p, Copy.a, Copy.g = S.p, S.a, S.g end
				table.insert(Parts, { [N] = Copy })
				Group, Size, First = {}, 0, false
			end
			for _, K in ipairs(S.k or {}) do
				local L = #HttpService:JSONEncode(K)
				if L > CHUNK then error("Объект «" .. tostring(K.n) .. "» в " .. N .. " слишком большой для передачи (> " .. CHUNK .. " байт)", 0) end
				if Size + L > CHUNK and #Group > 0 then Flush() end
				table.insert(Group, K)
				Size += L
			end
			Flush()
		end

		local Total, LastResp = #Parts, nil
		for I, Body in ipairs(Parts) do
			local Req = { services = Body }
			if I == Total then
				Req.skipped = Skipped
				for K, V in pairs(Extra or {}) do Req[K] = V end
			end
			if Total > 1 then SetInfo("Отправка: часть " .. I .. "/" .. Total) end
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
		elseif T == "string" or T == "Content" then return S
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
		local Out, Map = {}, nil
		for _, Op in ipairs(Ops) do
			local Info = Schema.Classes[Op.class]
			if Op.op == "create" then
				if not Info then
					table.insert(Out, "x " .. Op.path .. ": класса " .. Op.class .. " нет в схеме, не создастся")
				elseif Info.NotCreatable or Info.Service then
					table.insert(Out, "x " .. Op.path .. ": класс " .. Op.class .. " нельзя создать")
				else
					CheckProps(Op, Out)
				end
			elseif Op.op == "set" then
				if Info then CheckProps(Op, Out) end
			elseif Op.op == "delete" then
				if Op.class == "Terrain" then
					table.insert(Out, "x " .. Op.path .. ": Terrain не удаляется")
				else
					Map = Map or Index(Cfg)
					local I = Map[Op.path]
					if I and I:FindFirstChildWhichIsA("PartOperation", true) then
						table.insert(Out, "! " .. Op.path .. ": внутри есть Union/Negate (геометрия не сохраняется), они удалятся без возможности восстановить из файлов")
					end
				end
			end
		end
		return Out
	end

	-- ===== Применение =====
	local function SetProps(Inst, Op, Errs, J)
		local Types = PropsOf(Op.class).types
		local function Keep(K)
			if not J then return end
			local Ok, Old = pcall(GetProp, Inst, K)
			if Ok then table.insert(J, function() Inst[K] = Old end) end
		end
		for _, P in ipairs(Op.set or {}) do
			local K = P.k
			if K == "Source" then
				Keep(K)
				local Ok, E = pcall(function() Inst.Source = P.v end)
				if not Ok then table.insert(Errs, Op.path .. ".Source: " .. tostring(E)) end
			else
				local T = Types[K]
				if not T or SkipProp[K] or not Supported(T) then
					table.insert(Errs, Op.path .. "." .. K .. ": нет в схеме, пропущено")
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
			if not Def then
				table.insert(Errs, Op.path .. "." .. K .. ": нельзя вернуть к умолчанию (сервис)")
			elseif Def.raw[K] == nil then
				table.insert(Errs, Op.path .. "." .. K .. ": нет значения по умолчанию")
			else
				Keep(K)
				local Ok, E = pcall(function() Inst[K] = Def.raw[K] end)
				if not Ok then table.insert(Errs, Op.path .. "." .. K .. ": " .. tostring(E)) end
			end
		end
		for _, P in ipairs(Op.attrs or {}) do
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

	local function ApplyOps(Ops, Cfg)
		local Map = Index(Cfg)
		local Created, Changed, Deleted, Skipped = 0, 0, 0, 0
		local Errs, Failed, J = {}, {}, {}

		local Ok, Err = pcall(function()
			for _, Op in ipairs(Ops) do
				if Op.op == "create" then
					local ParentPath = string.match(Op.path, "^(.*)/[^/]*$")
					local Parent = ParentPath and Map[ParentPath]
					local Info = Schema.Classes[Op.class]
					if ParentPath and Failed[ParentPath] then
						Failed[Op.path] = true
						Skipped += 1
					elseif not Parent then
						Failed[Op.path] = true
						table.insert(Errs, Op.path .. ": не найден родитель")
					elseif not Info or Info.NotCreatable or Info.Service then
						Failed[Op.path] = true
						table.insert(Errs, Op.path .. ": класс " .. Op.class .. " нельзя создать")
					else
						local Ok2, I = pcall(Instance.new, Op.class)
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
						SetProps(I, Op, Errs, J)
						Changed += 1
					else
						table.insert(Errs, Op.path .. ": объект не найден в Studio")
					end
				elseif Op.op == "delete" then
					local I = Map[Op.path]
					if not I then
						table.insert(Errs, Op.path .. ": объект не найден в Studio")
					elseif Op.class == "Terrain" then
						table.insert(Errs, Op.path .. ": Terrain не удаляется")
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
			Call("/report" .. Q(), { text = LastText, kind = Kind, canApply = Pending ~= nil, canUndo = UndoJ ~= nil, lines = LastLines }, true)
		end)
	end

	-- ===== Карточка «Синхронизация» =====
	local SyncCard = Card(Root, 2)
	SyncCard.Visible = false
	Text(SyncCard, 1, "Синхронизация", { Bold = true, Size = 15 })

	local BtnRow = make("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, SyncCard)
	List(BtnRow, 6, Enum.FillDirection.Horizontal)
	local PullBtn = Button(BtnRow, 1, "⬆ Pull", "normal", UDim2.new(0.5, -3, 1, 0))
	local PushBtn = Button(BtnRow, 2, "⬇ Push", "primary", UDim2.new(0.5, -3, 1, 0))
	Text(SyncCard, 3, "Pull: Studio → файлы · Push: файлы → Studio", { Color = C.Dim, Size = 12 })

	local AutoBtn = Button(SyncCard, 4, "", "link")
	local ApplyBtn = Button(SyncCard, 5, "✔ Применить", "primary")
	local UndoBtn = Button(SyncCard, 6, "↩ Отменить применение", "normal")

	local InfoBox = make("Frame", { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BorderSizePixel = 0,
		BackgroundColor3 = C.Input, Visible = false }, SyncCard)
	Corner(InfoBox, 6)
	local InfoBar = make("Frame", { Position = UDim2.new(0, 0, 0, 4), Size = UDim2.new(0, 3, 1, -8), BorderSizePixel = 0,
		BackgroundColor3 = Blue }, InfoBox)
	Corner(InfoBar, 2)
	local InfoLabel = Text(InfoBox, 1, "", { Size = 14 })
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
		PushBtn.Text = AutoApply and "⬆ Push" or "⬆ Предпросмотр"
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

	-- ===== Карточка «Изменения» =====
	local ChangesCard = Card(Root, 4)
	ChangesCard.Visible = false
	local ChangesHead = Text(ChangesCard, 1, "", { Rich = true, Bold = true, Size = 15 })
	local ListFrame = make("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AutoY, BorderSizePixel = 0,
		BackgroundColor3 = C.Input }, ChangesCard)
	Corner(ListFrame, 6)
	Pad(ListFrame, 6, 8, 6, 8)
	List(ListFrame, 2)

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
		Report()
	end

	-- ===== Операции =====
	local function Prepare()
		if RunService:IsRunning() then error("Остановите игру (Play) перед синхронизацией", 0) end
		local Ok, E = LoadSchema()
		if not Ok then error("Схема: " .. tostring(E), 0) end
		local Cfg, E2 = Call("/config" .. Q())
		if E2 then error(E2, 0) end
		return Cfg
	end

	local function DoPull()
		local Cfg = Prepare()
		local Svc, Skipped = Collect(Cfg)
		local D, E = Send("/pull", Svc, Skipped)
		if E then error(E, 0) end
		SetUndo(nil)
		SetPending(nil)
		SetInfo(D.text or "Готово", Green)
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
		task.spawn(function()
			local Ok, Err = pcall(Fn)
			if not Ok then
				SetInfo("✖ " .. tostring(Err), Red)
				warn("RobloxBridge: " .. tostring(Err))
				Note({ "Плагин: " .. tostring(Err) })
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
		if Inst.Parent == game then return Inst.Name end
		if not Inst.Parent or Inst:IsA("PartOperation") then return nil end
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
			A.Status = "Не синхронизируется: вне сервисов или внутри Union/Negate"
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
			A.Status, A.Color = "Terrain: сохраняются только свойства", Green
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
		local D, E = Call("/settings" .. Q(), { autoSplit = Data.autoSplit, services = Data.services, ignore = New })
		if E then error(E, 0) end
		SetPending(nil)
		SetInfo((Has and "Объект снова синхронизируется: " or "Объект исключён из синхронизации: ") .. A.Path
			.. ". Чтобы изменения попали в файлы, сделайте Pull.", Green)
		ShowObject(true)
	end

	Click(SplitBtn, function() Run("Вынос", function() SplitAction(true) end) end)
	Click(UnsplitBtn, function() Run("Возврат", function() SplitAction(false) end) end)
	Click(IgnoreBtn, function() Run("Правило", IgnoreAction) end)

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

	local SvcCard = Card(SRoot, 3)
	Text(SvcCard, 1, "Сервисы", { Bold = true, Size = 15 })
	Text(SvcCard, 2, "По одному в строке. Сервисы вне списка не синхронизируются.", { Color = C.Dim, Size = 13 })
	local SvcBox = Box(SvcCard, 3, 150, true)

	local IgnCard = Card(SRoot, 4)
	Text(IgnCard, 1, "Игнорировать", { Bold = true, Size = 15 })
	Text(IgnCard, 2, "Пути объектов вместе с потомками, по одному в строке, например Workspace/Camera.", { Color = C.Dim, Size = 13 })
	local IgnBox = Box(IgnCard, 3, 70, true)

	local SaveBtn = Button(SRoot, 5, "Сохранить настройки", "primary", UDim2.new(1, 0, 0, 32))
	local StatL = Text(SRoot, 6, "", { Color = C.Dim, Size = 13 })

	local SplCard = Card(SRoot, 7)
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
		SvcBox.Text = table.concat(D.services or {}, "\n")
		IgnBox.Text = table.concat(D.ignore or {}, "\n")
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
		local D, E = Call("/settings" .. Q(), { autoSplit = N, services = Svc, ignore = SplitLines(IgnBox.Text) })
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
		end
	end
end