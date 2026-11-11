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

-- ===== Pull / Push / Diff =====
do
	local History = game:GetService("ChangeHistoryService")
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

	-- Возвращает (данные, ошибка). Ошибки сервера (400/409/500) приходят с текстом.
	local function Call(Path, Body)
		local Req = { Url = Base() .. Path, Method = Body and "POST" or "GET", Headers = { ["Content-Type"] = "application/json" } }
		if DebugOn then Req.Headers["X-Bridge-Debug"] = "1" end
		local Json
		if Body then Json = HttpService:JSONEncode(Body); Req.Body = Json end
		local T0 = os.clock()
		if DebugOn then
			print("[Bridge] → " .. Req.Method .. " " .. Path .. " (" .. (Json and #Json or 0) .. " байт)" .. (Json and ("\n" .. Cut(Json)) or ""))
		end
		local Ok, R = pcall(HttpService.RequestAsync, HttpService, Req)
		if not Ok then
			if DebugOn then print("[Bridge] ← ошибка: " .. tostring(R)) end
			return nil, "нет связи с приложением: " .. tostring(R)
		end
		if DebugOn then
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
		local C = PropCache[Class]
		if C then return C end
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
		C = { list = {}, types = Map, unsup = {} }
		local Names = {}
		for N in pairs(Map) do
			if not SkipProp[N] then table.insert(Names, N) end
		end
		table.sort(Names)
		for _, N in ipairs(Names) do
			local T = Map[N]
			if Supported(T) then table.insert(C.list, { N, T }) else table.insert(C.unsup, T) end
		end
		PropCache[Class] = C
		return C
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
		local List = {}
		for _, C in ipairs(Inst:GetChildren()) do
			if not C:IsA("PartOperation") then table.insert(List, C) end
		end
		table.sort(List, function(A, B)
			if A.Name ~= B.Name then return A.Name < B.Name end
			return A.ClassName < B.ClassName
		end)
		local Res, Prev, Dup = {}, nil, 0
		for _, C in ipairs(List) do
			if C.Name == Prev then Dup += 1 else Dup = 1; Prev = C.Name end
			local Key = Esc(C.Name) .. (Dup > 1 and ("~" .. Dup) or "")
			table.insert(Res, { Path == "" and Key or (Path .. "/" .. Key), C })
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

		local Total, Last = #Parts, nil
		for I, Body in ipairs(Parts) do
			local Req = { services = Body }
			if I == Total then
				Req.skipped = Skipped
				for K, V in pairs(Extra or {}) do Req[K] = V end
			end
			if Total > 1 then SetInfo("Отправка: часть " .. I .. "/" .. Total) end
			local D, E = Call(Route .. Q() .. "&session=" .. Session .. "&part=" .. I .. "&parts=" .. Total, Req)
			if E then return D, E end
			Last = D
		end
		return Last
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
	local function SetProps(Inst, Op, Errs)
		local Types = PropsOf(Op.class).types
		for _, P in ipairs(Op.set or {}) do
			local K = P.k
			if K == "Source" then
				local Ok, E = pcall(function() Inst.Source = P.v end)
				if not Ok then table.insert(Errs, Op.path .. ".Source: " .. tostring(E)) end
			else
				local T = Types[K]
				if not T or SkipProp[K] or not Supported(T) then
					table.insert(Errs, Op.path .. "." .. K .. ": нет в схеме, пропущено")
				else
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
				local Ok, E = pcall(function() Inst[K] = Def.raw[K] end)
				if not Ok then table.insert(Errs, Op.path .. "." .. K .. ": " .. tostring(E)) end
			end
		end
		for _, P in ipairs(Op.attrs or {}) do
			local Ok, E = pcall(function() Inst:SetAttribute(P.k, DecAttr(P.v, P.f)) end)
			if not Ok then table.insert(Errs, Op.path .. " $" .. P.k .. ": " .. tostring(E)) end
		end
		for _, K in ipairs(Op.adel or {}) do Inst:SetAttribute(K, nil) end
		if Op.tags then
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
		local Errs, Failed = {}, {}

		local Rec = History:TryBeginRecording("Bridge Push")
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
							SetProps(I, Op, Errs)
							I.Parent = Parent
							Map[Op.path] = I
							Created += 1
						end
					end
				elseif Op.op == "set" then
					local I = Map[Op.path]
					if I then
						SetProps(I, Op, Errs)
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
						I:Destroy()
						local Prefix = Op.path .. "/"
						for K in pairs(Map) do
							if K == Op.path or string.sub(K, 1, #Prefix) == Prefix then Map[K] = nil end
						end
						Deleted += 1
					end
				end
			end
		end)
		if Rec then History:FinishRecording(Rec, Enum.FinishRecordingOperation.Commit) end
		if not Ok then table.insert(Errs, "Прервано: " .. tostring(Err)) end
		return Created, Changed, Deleted, Skipped, Errs
	end

	-- ===== Интерфейс: ряд кнопок + информация + окно diff =====
	local function Dim() return Theme(Enum.StudioStyleGuideColor.DimmedText) end
	local Orange = Color3.fromRGB(240, 130, 40)

	local Row = make("Frame", { LayoutOrder = 10, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Visible = false }, Root)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, Row)

	local function Btn(Order, Text)
		return make("TextButton", { LayoutOrder = Order, Size = UDim2.new(1 / 3, -3, 1, 0), BorderSizePixel = 0,
			Font = Enum.Font.SourceSans, TextSize = 13, TextWrapped = true, Text = Text,
			BackgroundColor3 = Theme(Enum.StudioStyleGuideColor.Button),
			TextColor3 = Theme(Enum.StudioStyleGuideColor.ButtonText) }, Row)
	end
	local PullBtn = Btn(1, "Pull: Studio → файлы")
	local PreBtn = Btn(2, "Push: предпросмотр")
	local ApplyBtn = Btn(3, "Применить")

	local InfoLabel = make("TextLabel", { LayoutOrder = 11, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.SourceSans, TextSize = 14, Text = "",
		TextColor3 = Theme(Enum.StudioStyleGuideColor.MainText), Visible = false }, Root)

	local LinesFrame = make("ScrollingFrame", { LayoutOrder = 14, Size = UDim2.new(1, 0, 0, 200), BorderSizePixel = 0,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 8, Visible = false,
		BackgroundColor3 = Theme(Enum.StudioStyleGuideColor.InputFieldBackground) }, Root)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, LinesFrame)

	SetInfo = function(Text, Color)
		InfoLabel.Text = Text
		InfoLabel.TextColor3 = Color or Theme(Enum.StudioStyleGuideColor.MainText)
	end

	local function ShowLines(Lines)
		for _, C in ipairs(LinesFrame:GetChildren()) do
			if C:IsA("TextLabel") then C:Destroy() end
		end
		local Colors = { ["+"] = Green, ["-"] = Red, ["~"] = Yellow, ["x"] = Dim(), ["!"] = Orange }
		for I, T in ipairs(Lines) do
			local Text = T
			if I > MAXSHOW then Text = "… ещё строк: " .. (#Lines - MAXSHOW) .. " (полностью — в логе приложения)" end
			local Mark = string.sub(Text, 1, 1)
			local Col = Colors[Mark] or (Mark == " " and Dim()) or Theme(Enum.StudioStyleGuideColor.MainText)
			make("TextLabel", { LayoutOrder = I, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.Code, TextSize = 13, Text = Text, TextColor3 = Col }, LinesFrame)
			if I > MAXSHOW then break end
		end
	end

	local Working, Pending = false, nil
	local function SetPending(P)
		Pending = P
		ApplyBtn.TextTransparency = P and 0 or 0.6
	end
	SetPending(nil)

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
		SetPending(nil)
		SetInfo(D.text or "Готово", Green)
		ShowLines(D.lines or {})
	end

	local function DoPreview()
		local Cfg = Prepare()
		local Svc, Skipped = Collect(Cfg)
		local D, E = Send("/push", Svc, Skipped)
		if E then error(E, 0) end
		local C = D.counts
		local Total = C.created + C.changed + C.deleted
		local Lines = {}
		for _, L in ipairs(D.lines or {}) do table.insert(Lines, L) end
		local Warn = Classify(D.ops or {}, Cfg)
		for _, L in ipairs(Warn) do table.insert(Lines, L) end
		if #Warn > 0 then Note(Warn) end
		if Total == 0 then
			SetPending(nil)
			SetInfo("Push: изменений нет", Green)
		else
			SetPending({ token = D.token })
			SetInfo("Push, предпросмотр: создастся " .. C.created .. ", изменится " .. C.changed .. ", удалится " .. C.deleted
				.. ". Нажмите «Применить».", Yellow)
		end
		ShowLines(Lines)
	end

	local function DoApply()
		local P = Pending
		local Cfg = Prepare()
		local Svc, Skipped = Collect(Cfg)
		local D, E = Send("/push", Svc, Skipped, { apply = true, token = P.token })
		SetPending(nil)
		if E then error(E, 0) end
		local Created, Changed, Deleted, Skip, Errs = ApplyOps(D.ops or {}, Cfg)
		local Text = "Применено: создано " .. Created .. ", изменено " .. Changed .. ", удалено " .. Deleted
		if Skip > 0 then Text ..= ", пропущено вложенных " .. Skip end
		if #Errs > 0 then Text ..= ", ошибок " .. #Errs end
		local Lines = {}
		for _, L in ipairs(Errs) do table.insert(Lines, "x " .. L) end
		SetInfo(Text .. ". Ctrl+Z откатывает. Сделайте предпросмотр заново.", #Errs > 0 and Yellow or Green)
		ShowLines(Lines)
		local Log = { Text }
		for I = 1, math.min(#Lines, 40) do table.insert(Log, Lines[I]) end
		Note(Log)
	end

	local function Run(Title, Fn)
		if Working or not State.Found or State.Place ~= "ready" then return end
		Working = true
		SetInfo(Title .. "…", Dim())
		task.spawn(function()
			local Ok, Err = pcall(Fn)
			if not Ok then
				SetInfo("✖ " .. tostring(Err), Red)
				warn("RobloxBridge: " .. tostring(Err))
				Note({ "Плагин: " .. tostring(Err) })
			end
			Working = false
		end)
	end

	PullBtn.MouseButton1Click:Connect(function() Run("Pull", DoPull) end)
	PreBtn.MouseButton1Click:Connect(function() Run("Push: предпросмотр", DoPreview) end)
	ApplyBtn.MouseButton1Click:Connect(function()
		if not Pending then return end
		Run("Применяю", DoApply)
	end)

	-- ===== Вынос объектов в отдельные файлы =====
	local Selection = game:GetService("Selection")

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

	local function SplitAction(On)
		local Cfg = Prepare()
		local Sel = Selection:Get()
		if #Sel ~= 1 then error("Выберите в Explorer один объект", 0) end
		local Path = PathOf(Sel[1])
		if not Path then error("Не удалось определить путь выбранного объекта", 0) end
		local Root, Found = string.match(Path, "^[^/]+"), false
		for _, S in ipairs(Cfg.services or {}) do
			if S == Root then Found = true end
		end
		if not Found then error("Сервис " .. Root .. " не входит в Services", 0) end
		local D, E = Call((On and "/split" or "/unsplit") .. Q(), { path = Path })
		if E then error(E, 0) end
		SetPending(nil)
		SetInfo(D.text or "Готово", D.warn and Yellow or Green)
		ShowLines(D.lines or {})
	end

	local Row2 = make("Frame", { LayoutOrder = 12, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Visible = false }, Root)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, Row2)
	local function Btn2(Order, Text)
		return make("TextButton", { LayoutOrder = Order, Size = UDim2.new(0.5, -2, 1, 0), BorderSizePixel = 0,
			Font = Enum.Font.SourceSans, TextSize = 13, TextWrapped = true, Text = Text,
			BackgroundColor3 = Theme(Enum.StudioStyleGuideColor.Button),
			TextColor3 = Theme(Enum.StudioStyleGuideColor.ButtonText) }, Row2)
	end
	local SplitBtn = Btn2(1, "Вынести выделенный в файл")
	local UnsplitBtn = Btn2(2, "Вернуть в общий файл")
	SplitBtn.MouseButton1Click:Connect(function() Run("Вынос", function() SplitAction(true) end) end)
	UnsplitBtn.MouseButton1Click:Connect(function() Run("Возврат", function() SplitAction(false) end) end)

	-- ===== Отладка запросов =====
	local DebugBtn = make("TextButton", { LayoutOrder = 13, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
		Font = Enum.Font.SourceSans, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(90, 160, 255), Text = "", Visible = false }, Root)
	local function RefreshDebug()
		DebugBtn.Text = "Отладка запросов: " .. (DebugOn and "вкл (Output плагина + лог приложения)" or "выкл")
	end
	DebugBtn.MouseButton1Click:Connect(function()
		DebugOn = not DebugOn
		plugin:SetSetting("Debug", DebugOn)
		RefreshDebug()
	end)
	RefreshDebug()

	task.spawn(function()
		while true do
			local Show = State.Found and State.Place == "ready"
			Row.Visible, Row2.Visible, InfoLabel.Visible, LinesFrame.Visible = Show, Show, Show, Show
			DebugBtn.Visible = State.Found
			task.wait(0.5)
		end
	end)
	
		-- ===== Окно настроек плейса =====
	local SW = plugin:CreateDockWidgetPluginGui("RobloxBridgeSettings",
		DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, true, 380, 560, 300, 300))
	SW.Title = "RobloxBridge: настройки плейса"

	local SRoot = make("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 8,
		BackgroundColor3 = Theme(Enum.StudioStyleGuideColor.MainBackground) }, SW)
	make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, SRoot)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 8) }, SRoot)

	local function SText(Order, Text, Color, Size)
		return make("TextLabel", { LayoutOrder = Order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.SourceSans, TextSize = Size or 13, Text = Text,
			TextColor3 = Color or Theme(Enum.StudioStyleGuideColor.MainText) }, SRoot)
	end
	local function SBox(Order, Height, Multi)
		return make("TextBox", { LayoutOrder = Order, Size = UDim2.new(1, 0, 0, Height), ClearTextOnFocus = false,
			MultiLine = Multi, TextWrapped = Multi, Font = Enum.Font.Code, TextSize = 13, BorderSizePixel = 0,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
			BackgroundColor3 = Theme(Enum.StudioStyleGuideColor.InputFieldBackground),
			TextColor3 = Theme(Enum.StudioStyleGuideColor.MainText) }, SRoot)
	end
	local function SBtn(Order, Text)
		return make("TextButton", { LayoutOrder = Order, Size = UDim2.new(1, 0, 0, 28), BorderSizePixel = 0,
			Font = Enum.Font.SourceSans, TextSize = 14, Text = Text,
			BackgroundColor3 = Theme(Enum.StudioStyleGuideColor.Button),
			TextColor3 = Theme(Enum.StudioStyleGuideColor.ButtonText) }, SRoot)
	end

	local InfoL = SText(1, "", Dim())
	SText(2, "Автовынос в отдельные файлы", nil, 15)
	SText(3, "Если объект вместе со всеми вложенными занимает в .bridge больше N строк (1 строка = 1 объект со свойствами), "
		.. "он сам выносится в отдельный файл Scene/<путь>.bridge. По умолчанию 500. 0 — выключить: тогда выносите только вы "
		.. "кнопкой «Вынести выделенный». При N > 0 объект длиннее N строк нельзя вернуть в общий файл: он вынесется снова. "
		.. "Новое значение применится при следующем Pull.", Dim())
	local AutoBox = SBox(4, 24, false)
	SText(5, "Сервисы (по одному в строке). Сервисы вне списка не синхронизируются.", nil, 15)
	local SvcBox = SBox(6, 150, true)
	SText(7, "Игнорировать (пути объектов вместе с потомками, по одному в строке, например Workspace/Camera)", nil, 15)
	local IgnBox = SBox(8, 70, true)
	local SaveBtn = SBtn(9, "Сохранить настройки")
	local StatL = SText(10, "", Dim())
	SText(11, "Вынесено в отдельные файлы (клик по пути — выделить в Explorer)", nil, 15)
	local SplitsFrame = make("Frame", { LayoutOrder = 12, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1 }, SRoot)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, SplitsFrame)
	local ReloadBtn = SBtn(13, "Обновить")

	local function SStatus(Text, Color)
		StatL.Text = Text
		StatL.TextColor3 = Color or Theme(Enum.StudioStyleGuideColor.MainText)
	end

	local function Do(Fn)
		if Working then return end
		Working = true
		task.spawn(function()
			local Ok, Err = pcall(Fn)
			if not Ok then SStatus("✖ " .. tostring(Err), Red) end
			Working = false
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
		InfoL.Text = "PlaceId " .. tostring(D.placeId) .. ", создан " .. tostring(D.created)
		AutoBox.Text = tostring(D.autoSplit)
		SvcBox.Text = table.concat(D.services or {}, "\n")
		IgnBox.Text = table.concat(D.ignore or {}, "\n")
		for _, C in ipairs(SplitsFrame:GetChildren()) do
			if C:IsA("Frame") or C:IsA("TextLabel") then C:Destroy() end
		end
		local List = D.splits or {}
		if #List == 0 then
			make("TextLabel", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.SourceSans, TextSize = 13,
				Text = "(ничего не вынесено)", TextColor3 = Dim() }, SplitsFrame)
		end
		for I, S in ipairs(List) do
			local RowF = make("Frame", { LayoutOrder = I, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 }, SplitsFrame)
			make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder }, RowF)
			local Name = make("TextButton", { LayoutOrder = 1, Size = UDim2.new(1, -84, 1, 0), BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Code, TextSize = 12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Text = S.path .. (S.exists and ("  (" .. S.lines .. " стр.)") or "  (файла нет!)"),
				TextColor3 = S.exists and Theme(Enum.StudioStyleGuideColor.MainText) or Red }, RowF)
			local Back = make("TextButton", { LayoutOrder = 2, Size = UDim2.new(0, 80, 1, 0), BorderSizePixel = 0,
				Font = Enum.Font.SourceSans, TextSize = 13, Text = "Вернуть",
				BackgroundColor3 = Theme(Enum.StudioStyleGuideColor.Button),
				TextColor3 = Theme(Enum.StudioStyleGuideColor.ButtonText) }, RowF)
			Name.MouseButton1Click:Connect(function()
				local Inst = Find(S.path)
				if Inst then Selection:Set({ Inst }) else SStatus("Объект не найден в Studio: " .. S.path, Yellow) end
			end)
			Back.MouseButton1Click:Connect(function()
				Do(function()
					local R, E = Call("/unsplit" .. Q(), { path = S.path })
					if E then error(E, 0) end
					SStatus(R.text or "Готово", R.warn and Yellow or Green)
					Load()
				end)
			end)
		end
	end

	Load = function()
		local D, E = Call("/settings" .. Q())
		if E then error(E, 0) end
		Fill(D)
	end

	local function Lines(Text)
		local R = {}
		for L in string.gmatch(Text, "[^\r\n]+") do
			local T = string.match(L, "^%s*(.-)%s*$")
			if T ~= "" then table.insert(R, T) end
		end
		return R
	end

	local function DoSave()
		local N = tonumber(AutoBox.Text)
		if not N or N < 0 or N ~= math.floor(N) then error("Автовынос: нужно целое число, 0 или больше", 0) end
		local Svc = Lines(SvcBox.Text)
		if #Svc == 0 then error("Список сервисов не может быть пустым", 0) end
		local Bad = {}
		for _, S in ipairs(Svc) do
			if not pcall(game.GetService, game, S) then table.insert(Bad, S) end
		end
		if #Bad > 0 then error("Нет такого сервиса в Studio: " .. table.concat(Bad, ", "), 0) end
		local D, E = Call("/settings" .. Q(), { autoSplit = N, services = Svc, ignore = Lines(IgnBox.Text) })
		if E then error(E, 0) end
		SStatus((D.text or "Готово") .. ". Чтобы изменения попали в файлы, сделайте Pull.", Green)
		Fill(D)
	end

	SaveBtn.MouseButton1Click:Connect(function() Do(DoSave) end)
	ReloadBtn.MouseButton1Click:Connect(function() Do(Load) end)

	local SetBtn = make("TextButton", { LayoutOrder = 9, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1,
		Font = Enum.Font.SourceSans, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(90, 160, 255), Text = "⚙ Настройки плейса…", Visible = false }, Root)
	SetBtn.MouseButton1Click:Connect(function()
		SW.Enabled = true
		Do(Load)
	end)
	task.spawn(function()
		while true do
			SetBtn.Visible = State.Found and State.Place == "ready"
			task.wait(0.5)
		end
	end)
end