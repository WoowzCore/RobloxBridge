-- Обби: таблица очков (Stage), чекпоинты, убивающие детали,
-- двигающиеся платформы и вращающиеся перекладины.
-- Всё настраивается тегами и атрибутами деталей в Workspace/Obby.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local checkpoints = {}

-- Чекпоинты: тег "Checkpoint", атрибут Stage
for _, part in CollectionService:GetTagged("Checkpoint") do
	local n = part:GetAttribute("Stage")
	checkpoints[n] = part
	part.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		local stats = player and player:FindFirstChild("leaderstats")
		if stats and n > stats.Stage.Value then
			stats.Stage.Value = n
		end
	end)
end

-- Лава и килл-блоки: тег "Kill"
for _, part in CollectionService:GetTagged("Kill") do
	part.Touched:Connect(function(hit)
		local humanoid = hit.Parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = 0
		end
	end)
end

-- Игроки: leaderstats и возврат на последний чекпоинт после смерти
local function onPlayer(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local stage = Instance.new("IntValue")
	stage.Name = "Stage"
	stage.Parent = stats
	stats.Parent = player

	player.CharacterAdded:Connect(function(character)
		local cp = checkpoints[stage.Value]
		if cp then
			character:WaitForChild("HumanoidRootPart")
			character:PivotTo(cp.CFrame + Vector3.new(0, 4, 0))
		end
	end)
end
Players.PlayerAdded:Connect(onPlayer)
for _, player in Players:GetPlayers() do
	onPlayer(player)
end

-- Двигающиеся платформы: тег "Mover", атрибуты Offset (Vector3) и Time (сек в одну сторону)
for _, part in CollectionService:GetTagged("Mover") do
	local info = TweenInfo.new(part:GetAttribute("Time") or 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(part, info, { Position = part.Position + part:GetAttribute("Offset") }):Play()
end

-- Вращающиеся перекладины: тег "Spinner", атрибут Speed (градусы в секунду)
local spinners = CollectionService:GetTagged("Spinner")
RunService.Heartbeat:Connect(function(dt)
	for _, part in spinners do
		part.CFrame *= CFrame.Angles(0, math.rad(part:GetAttribute("Speed")) * dt, 0)
	end
end)