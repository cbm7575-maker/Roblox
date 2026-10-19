-- WorldService (ModuleScript, ServerScriptService.Services.WorldService)
-- Time of day and weather for Port Solana.
--   * A 12-minute day: 8 minutes of daylight, 4 minutes of neon night (ClockTime 18.5 -> 5.5).
--     Workspace attribute IsNight; heists pay 25% more at night (HeistService reads it).
--   * Lighting presets blend between day (warm, pastel haze) and night (purple, neon bloom).
--   * Rain storms: every few minutes there's a chance of a 2-3 minute Florida downpour
--     (Workspace attribute Raining). Wet roads mean less grip (CarPhysics reads it). The client draws
--     the rain and lightning (SkyClient).
-- Lighting.LightingStyle (Realistic) isn't scriptable: set it once in Studio (Lighting properties).

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldService = {}

local DAY_LENGTH = 720 -- seconds for a full 24 h
local DAYLIGHT_SHARE = 8 / 12
local STORM_CHECK = 240 -- seconds between storm rolls
local STORM_CHANCE = 0.3

local function ensure(className, name)
	local obj = Lighting:FindFirstChild(name) or Instance.new(className)
	obj.Name = name
	obj.Parent = Lighting
	return obj
end

local DAY = {
	Brightness = 2.4, Ambient = Color3.fromRGB(120, 110, 130), OutdoorAmbient = Color3.fromRGB(160, 140, 160),
	AtmoColor = Color3.fromRGB(255, 205, 195), AtmoDecay = Color3.fromRGB(130, 100, 170), AtmoDensity = 0.26, AtmoHaze = 1.1,
	Tint = Color3.fromRGB(255, 246, 240), Saturation = 0.12, Contrast = 0.05, BloomIntensity = 0.6,
}
local NIGHT = {
	Brightness = 0.9, Ambient = Color3.fromRGB(70, 50, 110), OutdoorAmbient = Color3.fromRGB(80, 60, 130),
	AtmoColor = Color3.fromRGB(120, 70, 170), AtmoDecay = Color3.fromRGB(40, 20, 80), AtmoDensity = 0.32, AtmoHaze = 1.6,
	Tint = Color3.fromRGB(220, 200, 255), Saturation = 0.25, Contrast = 0.12, BloomIntensity = 1.1,
}

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function apply(nightness, rain)
	local atmo = ensure("Atmosphere", "Atmosphere")
	local cc = ensure("ColorCorrectionEffect", "NeonGrade")
	local bloom = ensure("BloomEffect", "NeonBloom")
	Lighting.Brightness = lerp(DAY.Brightness, NIGHT.Brightness, nightness) * (rain and 0.75 or 1)
	Lighting.Ambient = DAY.Ambient:Lerp(NIGHT.Ambient, nightness)
	Lighting.OutdoorAmbient = DAY.OutdoorAmbient:Lerp(NIGHT.OutdoorAmbient, nightness)
	atmo.Color = DAY.AtmoColor:Lerp(NIGHT.AtmoColor, nightness)
	atmo.Decay = DAY.AtmoDecay:Lerp(NIGHT.AtmoDecay, nightness)
	atmo.Density = lerp(DAY.AtmoDensity, NIGHT.AtmoDensity, nightness) + (rain and 0.12 or 0)
	atmo.Haze = lerp(DAY.AtmoHaze, NIGHT.AtmoHaze, nightness) + (rain and 1 or 0)
	cc.TintColor = DAY.Tint:Lerp(NIGHT.Tint, nightness)
	cc.Saturation = lerp(DAY.Saturation, NIGHT.Saturation, nightness) - (rain and 0.1 or 0)
	cc.Contrast = lerp(DAY.Contrast, NIGHT.Contrast, nightness)
	bloom.Intensity = lerp(DAY.BloomIntensity, NIGHT.BloomIntensity, nightness)
	bloom.Size = 28
	bloom.Threshold = 1.4
end

-- 0 in full daylight, 1 in full night, smooth ramps at dusk (17-19.5) and dawn (4.5-7).
local function nightnessAt(clock)
	if clock >= 19.5 or clock < 4.5 then
		return 1
	elseif clock >= 17 then
		return (clock - 17) / 2.5
	elseif clock < 7 then
		return 1 - (clock - 4.5) / 2.5
	end
	return 0
end

function WorldService.IsNight()
	return Workspace:GetAttribute("IsNight") == true
end

-- Studio testing (DebugService): pin the clock or the weather. nil = back to normal.
WorldService.Override = { Clock = nil, Rain = nil }

function WorldService.Init()
	local startClock = 15
	local elapsed = 0
	local lastApply = 0
	local nextStormRoll = STORM_CHECK
	local stormUntil = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		-- Map real time to clock time: daylight (6:00-18:30) takes DAYLIGHT_SHARE of the cycle.
		local cyclePos = ((elapsed / DAY_LENGTH) + (startClock - 6) / 24) % 1
		local clock
		local dayHours = 12.5
		if cyclePos < DAYLIGHT_SHARE then
			clock = 6 + dayHours * (cyclePos / DAYLIGHT_SHARE)
		else
			clock = (18.5 + (24 - dayHours) * ((cyclePos - DAYLIGHT_SHARE) / (1 - DAYLIGHT_SHARE))) % 24
		end
		clock = WorldService.Override.Clock or clock
		Lighting.ClockTime = clock
		if elapsed - lastApply > 0.5 then
			lastApply = elapsed
			local nightness = nightnessAt(clock)
			local night = nightness > 0.5
			if Workspace:GetAttribute("IsNight") ~= night then
				Workspace:SetAttribute("IsNight", night)
			end
			-- Weather
			local raining = elapsed < stormUntil
			if elapsed > nextStormRoll then
				nextStormRoll = elapsed + STORM_CHECK
				if not raining and math.random() < STORM_CHANCE then
					stormUntil = elapsed + math.random(120, 180)
					raining = true
				end
			end
			if WorldService.Override.Rain ~= nil then
				raining = WorldService.Override.Rain
			end
			if Workspace:GetAttribute("Raining") ~= raining then
				Workspace:SetAttribute("Raining", raining)
			end
			apply(nightness, raining)
		end
	end)
end

return WorldService
