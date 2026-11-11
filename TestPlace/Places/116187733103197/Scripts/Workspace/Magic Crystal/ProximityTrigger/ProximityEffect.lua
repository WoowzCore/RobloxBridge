--!strict
-- ProximityEffect: локальный эффект приближения к кристаллу
-- Показывает подсказку, добавляет частицы и звук, "подпитывает" кристалл

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local trigger = script.Parent :: BasePart
local crystal = trigger.Parent :: Model

local DETECT_RADIUS = 12
local RECHARGE_RATE = 4 -- сколько заряда в секунду игрок даёт кристаллу

local wasNear = false
local ui: ScreenGui? = nil
local prompt: TextLabel? = nil

-- Создаём простую UI-подсказку
local function createHint()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CrystalHintGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "CrystalHint"
	label.Size = UDim2.fromScale(0.4, 0.08)
	label.Position = UDim2.fromScale(0.3, 0.82)
	label.BackgroundColor3 = Color3.fromRGB(20, 15, 40)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.fromRGB(198, 179, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.Text = "✨ Магический кристалл ✨"
	label.Visible = false
	label.Parent = screenGui

	-- Скруглённый угол
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label

	ui = screenGui
	prompt = label
	return label
end

local hint = createHint()

-- Звук "подпитки" (создаём один раз на игрока)
local rechargeSound = Instance.new("Sound")
rechargeSound.SoundId = "rbxassetid://6042053626" -- мягкий магический звук
rechargeSound.Volume = 0.3
rechargeSound.Parent = player:WaitForChild("PlayerGui")

RunService.RenderStepped:Connect(function(dt)
	if not player.Character then
		return
	end
	local root = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local distance = (root.Position - trigger.Position).Magnitude
	local isNear = distance <= DETECT_RADIUS

	-- Подсказка
	if hint then
		if isNear then
			hint.Visible = true
			hint.Text = string.format("✨ Магический кристалл ✨  |  Заряд: %d%%", math.floor(crystal:GetAttribute("Charge") or 0))
		else
			hint.Visible = false
		end
	end

	-- Вход в зону / выход из зоны
	if isNear and not wasNear then
		wasNear = true
		-- Мягкий звон при входе
		rechargeSound:Play()
		-- Лёгкий трях камеры
		local camera = workspace.CurrentCamera
		if camera then
			local orig = camera.CFrame
			TweenService:Create(camera, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
				CFrame = orig * CFrame.new(0, 0, 0) * CFrame.Angles(0.02, 0, 0),
			}):Play()
		end
	elseif not isNear and wasNear then
		wasNear = false
	end

	-- Подпитка кристалла, пока игрок рядом
	if isNear then
		local charge = crystal:GetAttribute("Charge") or 0
		if charge < 100 then
			crystal:SetAttribute("Charge", math.min(100, charge + RECHARGE_RATE * dt))
		end
	end
end)

-- При респавне пересоздаём подсказку
player.CharacterAdded:Connect(function()
	if hint then
		hint.Parent = player:WaitForChild("PlayerGui"):FindFirstChild("CrystalHintGui")
	end
end)