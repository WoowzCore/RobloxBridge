--!strict
-- CrystalController: серверная логика магического кристалла
-- Вращает, парит, пульсирует светом и устраивает случайные "вспышки силы"

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local crystal = script.Parent
local core = crystal:WaitForChild("Core") :: BasePart
local tip = crystal:WaitForChild("Crystal Tip") :: BasePart
local shards = crystal:WaitForChild("Shards") :: Model
local aura = core:WaitForChild("Aura") :: PointLight
local sparkles = core:WaitForChild("Sparkles") :: ParticleEmitter
local hum = crystal:WaitForChild("Hum") :: Sound

-- Базовые значения, чтобы анимация была плавной и предсказуемой
local baseCorePos = core.Position
local baseTipPos = tip.Position
local baseAuraBrightness = aura.Brightness

local FLOAT_HEIGHT = 0.6
local FLOAT_SPEED = 1.8
local SPIN_SPEED = 0.8

-- Парение и вращение осколков
local elapsed = 0
RunService.Heartbeat:Connect(function(dt)
	elapsed += dt

	-- Парение ядра и вершины
	local floatOffset = math.sin(elapsed * FLOAT_SPEED) * FLOAT_HEIGHT
	core.CFrame = CFrame.new(baseCorePos + Vector3.new(0, floatOffset, 0)) * CFrame.Angles(0, elapsed * SPIN_SPEED, 0)
	tip.CFrame = CFrame.new(baseTipPos + Vector3.new(0, floatOffset, 0)) * CFrame.Angles(math.sin(elapsed) * 0.2, -elapsed * SPIN_SPEED * 1.3, 0)

	-- Осколки кружат вокруг кристалла
	local shardList = shards:GetChildren()
	for i, shard in ipairs(shardList) do
		if shard:IsA("BasePart") then
			local angle = elapsed * 1.5 + (i - 1) * (math.pi * 2 / #shardList)
			local radius = 2.5
			local yOffset = math.sin(elapsed * 2 + i) * 0.8
			shard.CFrame = CFrame.new(
				baseCorePos + Vector3.new(math.cos(angle) * radius, floatOffset + yOffset, math.sin(angle) * radius)
			) * CFrame.Angles(elapsed * 2, angle, 0)
		end
	end

	-- Пульсация света
	aura.Brightness = baseAuraBrightness + math.sin(elapsed * 2.5) * 1.2
end)

-- Случайные "вспышки силы"
local function triggerSurge()
	local charge = crystal:GetAttribute("Charge") or 100
	local state = crystal:GetAttribute("State")

	-- Кристалл не может вспыхнуть, если уже перегружен
	if state == "surge" then
		return
	end

	crystal:SetAttribute("State", "surge")

	-- Усиливаем свет и частицы
	local surgeTween = TweenService:Create(aura, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {
		Brightness = 12,
		Range = 35,
	})
	surgeTween:Play()

	sparkles.Rate = 80
	sparkles.Speed = NumberRange.new(6, 12)

	-- Звук
	hum.PlaybackSpeed = 1.6
	hum:Play()

	-- Через некоторое время возвращаем всё обратно
	task.delay(1.2, function()
		local calmTween = TweenService:Create(aura, TweenInfo.new(1.5, Enum.EasingStyle.Sine), {
			Brightness = baseAuraBrightness,
			Range = 18,
		})
		calmTween:Play()
		sparkles.Rate = 12
		sparkles.Speed = NumberRange.new(2, 4)
		hum.PlaybackSpeed = 1
		crystal:SetAttribute("State", "idle")
	end)

	-- Тратим заряд
	if charge > 10 then
		crystal:SetAttribute("Charge", charge - 10)
	else
		crystal:SetAttribute("Charge", 0)
	end
end

-- Периодические вспышки
task.spawn(function()
	while true do
		task.wait(math.random(8, 15))
		triggerSurge()
	end
end)

-- Реакция на изменение заряда (например, если игрок "подпитывает" кристалл)
crystal:GetAttributeChangedSignal("Charge"):Connect(function()
	local charge = crystal:GetAttribute("Charge") or 0
	if charge <= 0 then
		-- Разряжен: тускнеет
		TweenService:Create(core, TweenInfo.new(2), { Transparency = 0.6 }):Play()
		TweenService:Create(aura, TweenInfo.new(2), { Brightness = 1 }):Play()
		crystal:SetAttribute("State", "depleted")
	elseif charge >= 90 then
		-- Полон: ярче обычного
		TweenService:Create(core, TweenInfo.new(2), { Transparency = 0.05 }):Play()
		crystal:SetAttribute("State", "idle")
	end
end)

print("[MagicCrystal] Server controller started. Charge =", crystal:GetAttribute("Charge"))