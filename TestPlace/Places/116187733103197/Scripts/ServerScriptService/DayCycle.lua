-- ggeropjnrtnrsthnrwighoerity9w5gviwet4yb 4wyb w45y

--// Day/Night Cycle, @Shyfoox
--// Put this script in ServerScriptService

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

--// Easy settings
local DayTime = 800
local NightTime = DayTime / 2

local DuskTime = DayTime * 0.15
local DawnTime = DayTime * 0.15
local FadeTime = math.max(1, DayTime * 0.03)

local NormalAmbient = Color3.fromRGB(140, 140, 140)

--// Find or create effects
local Atmosphere = Lighting:FindFirstChild("Atmosphere") or Instance.new("Atmosphere")
Atmosphere.Parent = Lighting

local Bloom = Lighting:FindFirstChild("Bloom") or Instance.new("BloomEffect")
Bloom.Name = "Bloom"
Bloom.Parent = Lighting

local SunRays = Lighting:FindFirstChild("SunRays") or Instance.new("SunRaysEffect")
SunRays.Name = "SunRays"
SunRays.Parent = Lighting

local ColorCorrection = Lighting:FindFirstChild("ColorCorrection") or Instance.new("ColorCorrectionEffect")
ColorCorrection.Name = "ColorCorrection"
ColorCorrection.Parent = Lighting

--// Starting lighting
Lighting.ClockTime = 7

local function tween(obj, time, info)
	local newTween = TweenService:Create(
		obj,
		TweenInfo.new(time, Enum.EasingStyle.Linear),
		info
	)

	newTween:Play()
	return newTween
end

local function makeDay()
	tween(Lighting, FadeTime, {
		Ambient = NormalAmbient,
		OutdoorAmbient = NormalAmbient,
		Brightness = 2.4,
		ExposureCompensation = 0.05,
		ColorShift_Top = Color3.fromRGB(255, 245, 230),
		ColorShift_Bottom = Color3.fromRGB(255, 250, 240),
		ShadowSoftness = 0.3
	})

	tween(Atmosphere, FadeTime, {
		Color = Color3.fromRGB(220, 235, 255),
		Decay = Color3.fromRGB(120, 170, 255),
		Density = 0.22,
		Haze = 1.15,
		Glare = 0.2
	})

	tween(Bloom, FadeTime, {
		Intensity = 0.12,
		Size = 38,
		Threshold = 1
	})

	tween(SunRays, FadeTime, {
		Intensity = 0.08,
		Spread = 0.9
	})

	tween(ColorCorrection, FadeTime, {
		Brightness = 0,
		Contrast = 0.07,
		Saturation = 0.1
	})
end

local function makeDusk()
	tween(Lighting, FadeTime, {
		Ambient = NormalAmbient,
		OutdoorAmbient = NormalAmbient,
		Brightness = 2,
		ExposureCompensation = 0,
		ColorShift_Top = Color3.fromRGB(255, 190, 125),
		ColorShift_Bottom = Color3.fromRGB(255, 135, 90)
	})

	tween(Atmosphere, FadeTime, {
		Color = Color3.fromRGB(255, 180, 140),
		Decay = Color3.fromRGB(255, 130, 95),
		Density = 0.3,
		Haze = 2,
		Glare = 0.35
	})

	tween(Bloom, FadeTime, {
		Intensity = 0.15,
		Size = 45,
		Threshold = 0.95
	})

	tween(SunRays, FadeTime, {
		Intensity = 0.12,
		Spread = 0.9
	})

	tween(ColorCorrection, FadeTime, {
		Brightness = 0,
		Contrast = 0.1,
		Saturation = 0.18
	})
end

local function makeNight()
	tween(Lighting, FadeTime, {
		Ambient = NormalAmbient,
		OutdoorAmbient = NormalAmbient,
		Brightness = 1.35,
		ExposureCompensation = -0.15,
		ColorShift_Top = Color3.fromRGB(55, 75, 135),
		ColorShift_Bottom = Color3.fromRGB(25, 35, 75)
	})

	tween(Atmosphere, FadeTime, {
		Color = Color3.fromRGB(75, 95, 150),
		Decay = Color3.fromRGB(25, 35, 65),
		Density = 0.5,
		Haze = 3.2,
		Glare = 0
	})

	tween(Bloom, FadeTime, {
		Intensity = 0.08,
		Size = 34,
		Threshold = 1.1
	})

	tween(SunRays, FadeTime, {
		Intensity = 0.02,
		Spread = 1
	})

	tween(ColorCorrection, FadeTime, {
		Brightness = -0.02,
		Contrast = 0.1,
		Saturation = -0.05
	})
end

local function makeDawn()
	tween(Lighting, FadeTime, {
		Ambient = NormalAmbient,
		OutdoorAmbient = NormalAmbient,
		Brightness = 1.8,
		ExposureCompensation = 0,
		ColorShift_Top = Color3.fromRGB(255, 200, 150),
		ColorShift_Bottom = Color3.fromRGB(255, 160, 120)
	})

	tween(Atmosphere, FadeTime, {
		Color = Color3.fromRGB(255, 205, 170),
		Decay = Color3.fromRGB(255, 150, 110),
		Density = 0.32,
		Haze = 2.2,
		Glare = 0.25
	})

	tween(Bloom, FadeTime, {
		Intensity = 0.13,
		Size = 42,
		Threshold = 1
	})

	tween(SunRays, FadeTime, {
		Intensity = 0.1,
		Spread = 0.95
	})

	tween(ColorCorrection, FadeTime, {
		Brightness = 0,
		Contrast = 0.09,
		Saturation = 0.15
	})
end

while true do
	-- Day
	makeDay()
	tween(Lighting, DayTime, {
		ClockTime = 17
	})
	task.wait(DayTime)

	-- Dusk / sunset
	makeDusk()
	tween(Lighting, DuskTime, {
		ClockTime = 19
	})
	task.wait(DuskTime)

	-- Night
	makeNight()
	tween(Lighting, NightTime, {
		ClockTime = 5
	})
	task.wait(NightTime)

	-- Dawn / sunrise
	makeDawn()
	tween(Lighting, DawnTime, {
		ClockTime = 7
	})
	task.wait(DawnTime)
end