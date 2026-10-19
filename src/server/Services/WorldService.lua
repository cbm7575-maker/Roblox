-- WorldService (ModuleScript, ServerScriptService.Services.WorldService)
-- Time of day and weather for Port Solana.
--   * A 12-minute day: 8 minutes of daylight, 4 minutes of neon night (ClockTime 18.5 -> 5.5).
--     Workspace attribute IsNight; heists pay 25% more at night (HeistService reads it).
--   * Lighting presets blend between day (warm, pastel haze) and night (purple, neon bloom).
--   * Rain storms: every few minutes there's a chance of a 2-3 minute Florida downpour
--     (Workspace attribute Raining). Wet roads mean less grip (CarPhysics reads it). The client draws
--     the rain and lightning (SkyClient).
-- Lighting.LightingStyle (Realistic) isn't scriptable: set it once in Studio (Lighting properties).
--   WorldService.Clock() -> the current clock hour (0-24).
--   WorldService.SecondsUntil(hour) -> real seconds until the clock next reads `hour` (EventService
--     uses it so night-only moments end at dawn).
-- The clock is written to Lighting.ClockTime about 10 times a second (plenty for a 12-minute day).

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldService = {}

local DAY_LENGTH = 720 -- seconds for a full 24 h
local DAYLIGHT_SHARE = 8 / 12
local STORM_CHECK = 240 -- seconds between storm rolls
local STORM_CHANCE = 0.3
local DAY_HOURS = 12.5 -- daylight runs 6:00-18:30
-- Real seconds per clock hour, by day and by night.
local DAY_RATE = DAY_LENGTH * DAYLIGHT_SHARE / DAY_HOURS
local NIGHT_RATE = DAY_LENGTH * (1 - DAYLIGHT_SHARE) / (24 - DAY_HOURS)
local CLOCK_STEP = 0.1 -- seconds between Lighting.ClockTime writes

local currentClock = 15

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

function WorldService.Clock()
	return currentClock
end

-- Real seconds from clock hour `from` to the next time the clock reads `to` (day and night run at
-- different speeds).
local function secondsBetween(from, to)
	local total, c = 0, from % 24
	local remaining = (to - from) % 24
	for _ = 1, 4 do
		if remaining <= 1e-6 then
			break
		end
		local day = c >= 6 and c < DAY_HOURS + 6
		local boundary = day and DAY_HOURS + 6 or 6
		local toBoundary = (boundary - c) % 24
		local step = math.min(remaining, toBoundary > 1e-6 and toBoundary or 24)
		total += step * (day and DAY_RATE or NIGHT_RATE)
		remaining -= step
		c = (c + step) % 24
	end
	return total
end

function WorldService.SecondsUntil(hour)
	return secondsBetween(currentClock, hour)
end

-- Studio testing (DebugService): pin the clock or the weather. nil = back to normal.
WorldService.Override = { Clock = nil, Rain = nil }

function WorldService.Init()
	local startClock = 15
	local elapsed = 0
	local lastClock = -1
	local lastApply = 0
	local nextStormRoll = STORM_CHECK
	local stormUntil = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed - lastClock < CLOCK_STEP then
			return
		end
		lastClock = elapsed
		-- Map real time to clock time: daylight (6:00-18:30) takes DAYLIGHT_SHARE of the cycle.
		local cyclePos = ((elapsed / DAY_LENGTH) + (startClock - 6) / 24) % 1
		local clock
		if cyclePos < DAYLIGHT_SHARE then
			clock = 6 + DAY_HOURS * (cyclePos / DAYLIGHT_SHARE)
		else
			clock = (DAY_HOURS + 6 + (24 - DAY_HOURS) * ((cyclePos - DAYLIGHT_SHARE) / (1 - DAYLIGHT_SHARE))) % 24
		end
		clock = WorldService.Override.Clock or clock
		currentClock = clock
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
