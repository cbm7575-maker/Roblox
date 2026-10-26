-- WorldService (ModuleScript, ServerScriptService.Services.WorldService)
-- Time of day and weather for Port Solana.
--   * A 14-minute day in three acts (ACTS): 5 minutes of daylight (6:00-16:00: the high-noon stretch
--     9:30-14:00 goes by fastest, so most of the day is spent in the long-shadow morning and afternoon
--     light the city looks best in), a long 3 min 20 s golden
--     hour and sunset (16:00-18:48: the look the city is built around), then 5 min 40 s of neon night.
--     Servers start at 16:12, so a new player's first minutes run golden hour -> sunset -> neon night.
--     Workspace attribute IsNight; heists pay 25% more at night (HeistService reads it).
--   * Lighting looks (Look 3.0) are keyed to the clock and blended: clear day, golden hour (long warm
--     light), sunset (orange-pink sky), dusk (the sun is down: a bright pink magic hour while the neon
--     and the street lamps come on), neon night (purple haze, strong bloom), pink dawn.
--     At this latitude the sun is on the horizon at about 18:00. Between then and full night nothing
--     lights the streets but the sky, so DUSK lifts the exposure and the ambient light, and IsNight
--     (the lamps and the neon) starts at 18:24: without both, a new player's second and third minutes
--     were spent in near-black streets.
--   * Rain storms: every few minutes there's a chance of a 2-3 minute Florida downpour
--     (Workspace attribute Raining). Wet roads mean less grip (CarPhysics reads it). The client draws
--     the rain and lightning (SkyClient), and switches the city's neon and street lamps on at night.
-- Lighting.LightingStyle (Realistic) is set in the place file (the Look3 tool does it).

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local WorldService = {}

-- { from hour, to hour, seconds }: how long each stretch of the clock takes (30 = 6:00 the next morning).
local ACTS = {
	{ 6, 9.5, 110 },
	{ 9.5, 14, 70 },
	{ 14, 16, 120 },
	{ 16, 18.8, 200 },
	{ 18.8, 30, 340 },
}
local START_CLOCK = 16.2
local STORM_CHECK = 240 -- seconds between storm rolls
local STORM_CHANCE = 0.3

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function ensure(className, name)
	local obj = Lighting:FindFirstChild(name) or Instance.new(className)
	obj.Name = name
	obj.Parent = Lighting
	return obj
end

-- Looks. Numbers are plain values or Color3s; every field blends between neighbouring keys.
-- DAY (Look 4.0, 2026-10-15): warm sun, crisp dark-grey shadows (a low EnvDiffuse and a warm, bright
-- OutdoorAmbient keep the deep blue sky from turning shaded asphalt navy: checked in play at 15:30 in a
-- downtown street's shadow), saturated colour and a blue haze that gives the skyline depth.
local DAY = {
	Brightness = 3.6, Exposure = -0.05, EnvDiffuse = 0.2, Ambient = rgb(80, 76, 76), OutdoorAmbient = rgb(210, 200, 196),
	SunTint = rgb(255, 228, 188), AtmoColor = rgb(196, 212, 232), AtmoDecay = rgb(112, 138, 178), AtmoDensity = 0.33,
	AtmoHaze = 1.9, Glare = 0.5, Tint = rgb(255, 242, 224), Saturation = 0.24, Contrast = 0.18, Bloom = 0.5,
	BloomThreshold = 1.45, Clouds = rgb(255, 255, 255),
}
local GOLDEN = {
	Brightness = 3.4, Exposure = 0.1, EnvDiffuse = 0.25, Ambient = rgb(80, 66, 60), OutdoorAmbient = rgb(200, 176, 160),
	SunTint = rgb(255, 196, 136), AtmoColor = rgb(242, 206, 168), AtmoDecay = rgb(200, 142, 104), AtmoDensity = 0.31,
	AtmoHaze = 1.8, Glare = 0.6, Tint = rgb(255, 236, 210), Saturation = 0.2, Contrast = 0.2, Bloom = 0.55,
	BloomThreshold = 1.4, Clouds = rgb(255, 220, 186),
}
local SUNSET = {
	Brightness = 2.2, Exposure = 0.6, EnvDiffuse = 0.6, Ambient = rgb(94, 72, 80), OutdoorAmbient = rgb(190, 150, 146),
	SunTint = rgb(255, 164, 104), AtmoColor = rgb(255, 168, 120), AtmoDecay = rgb(232, 118, 92), AtmoDensity = 0.36,
	AtmoHaze = 2, Glare = 0.9, Tint = rgb(255, 226, 204), Saturation = 0.2, Contrast = 0.18, Bloom = 0.7,
	BloomThreshold = 1.35, Clouds = rgb(255, 170, 150),
}
local DUSK = {
	Brightness = 1.8, Exposure = 0.75, EnvDiffuse = 0.6, Ambient = rgb(86, 66, 96), OutdoorAmbient = rgb(164, 134, 152),
	SunTint = rgb(255, 170, 150), AtmoColor = rgb(236, 150, 150), AtmoDecay = rgb(150, 80, 130), AtmoDensity = 0.36,
	AtmoHaze = 2, Glare = 0.3, Tint = rgb(255, 230, 230), Saturation = 0.18, Contrast = 0.14, Bloom = 0.75,
	BloomThreshold = 1.3, Clouds = rgb(240, 150, 160),
}
local NIGHT = {
	Brightness = 1.6, Exposure = 0.5, EnvDiffuse = 0.3, Ambient = rgb(56, 52, 84), OutdoorAmbient = rgb(96, 90, 136),
	SunTint = rgb(170, 180, 255), AtmoColor = rgb(92, 70, 150), AtmoDecay = rgb(32, 20, 72), AtmoDensity = 0.34,
	AtmoHaze = 1.8, Glare = 0, Tint = rgb(228, 216, 255), Saturation = 0.18, Contrast = 0.15, Bloom = 0.75,
	BloomThreshold = 1.3, Clouds = rgb(60, 50, 90),
}
local DAWN = {
	Brightness = 2.2, Exposure = 0.1, EnvDiffuse = 0.4, Ambient = rgb(60, 52, 66), OutdoorAmbient = rgb(126, 110, 122),
	SunTint = rgb(255, 190, 170), AtmoColor = rgb(255, 196, 176), AtmoDecay = rgb(200, 130, 150), AtmoDensity = 0.34,
	AtmoHaze = 1.9, Glare = 0.7, Tint = rgb(255, 234, 228), Saturation = 0.12, Contrast = 0.14, Bloom = 0.6,
	BloomThreshold = 1.4, Clouds = rgb(255, 190, 180),
}
-- { hour, look }, in order.
local KEYS = {
	{ 0, NIGHT }, { 4.8, NIGHT }, { 6.2, DAWN }, { 8, DAY }, { 15.5, DAY }, { 17.2, GOLDEN }, { 17.9, SUNSET },
	{ 18.5, DUSK }, { 19.4, NIGHT }, { 24, NIGHT },
}

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- The two looks either side of this hour and how far between them.
local function lookAt(clock)
	for i = 1, #KEYS - 1 do
		local a, b = KEYS[i], KEYS[i + 1]
		if clock >= a[1] and clock <= b[1] then
			return a[2], b[2], (clock - a[1]) / math.max(b[1] - a[1], 1e-3)
		end
	end
	return NIGHT, NIGHT, 0
end

local function apply(clock, rain)
	local a, b, t = lookAt(clock)
	local function num(key)
		return lerp(a[key], b[key], t)
	end
	local function col(key)
		return a[key]:Lerp(b[key], t)
	end
	local atmo = ensure("Atmosphere", "Atmosphere")
	local cc = ensure("ColorCorrectionEffect", "NeonGrade")
	local bloom = ensure("BloomEffect", "NeonBloom")
	Lighting.Brightness = num("Brightness") * (rain and 0.75 or 1)
	Lighting.ExposureCompensation = num("Exposure")
	Lighting.EnvironmentDiffuseScale = num("EnvDiffuse")
	Lighting.Ambient = col("Ambient")
	Lighting.OutdoorAmbient = col("OutdoorAmbient")
	Lighting.ColorShift_Top = col("SunTint")
	atmo.Color = col("AtmoColor")
	atmo.Decay = col("AtmoDecay")
	atmo.Density = num("AtmoDensity") + (rain and 0.12 or 0)
	atmo.Haze = num("AtmoHaze") + (rain and 1 or 0)
	atmo.Glare = rain and 0 or num("Glare")
	atmo.Offset = 0.3
	cc.TintColor = col("Tint")
	cc.Saturation = num("Saturation") - (rain and 0.1 or 0)
	cc.Contrast = num("Contrast")
	bloom.Intensity = num("Bloom")
	bloom.Size = 28
	bloom.Threshold = num("BloomThreshold") -- in the day only really bright things (neon, sun glints) bloom
	local clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Cover = rain and 0.85 or 0.6
		clouds.Density = rain and 0.9 or 0.5
		clouds.Color = rain and col("Clouds"):Lerp(rgb(120, 124, 132), 0.5) or col("Clouds")
	end
end

-- 0 in full daylight, 1 in full night, with ramps at dusk (17.9-18.9: half way, 18:24, is when the
-- lamps and the neon come on, just after the sun has gone) and dawn (4.8-6.4).
local function nightnessAt(clock)
	if clock >= 18.9 or clock < 4.8 then
		return 1
	elseif clock >= 17.9 then
		return (clock - 17.9) / 1
	elseif clock < 6.4 then
		return 1 - (clock - 4.8) / 1.6
	end
	return 0
end

local cycle = 0
for _, act in ipairs(ACTS) do
	cycle += act[3]
end

-- Seconds into the cycle -> clock hour (0-24).
local function clockAt(seconds)
	local s = seconds % cycle
	for _, act in ipairs(ACTS) do
		if s <= act[3] then
			return (act[1] + (act[2] - act[1]) * (s / act[3])) % 24
		end
		s -= act[3]
	end
	return 6
end

-- Clock hour -> seconds into the cycle (to start the server at START_CLOCK).
local function secondsAt(clock)
	local s = 0
	local c = clock < 6 and clock + 24 or clock
	for _, act in ipairs(ACTS) do
		if c <= act[2] then
			return s + act[3] * (c - act[1]) / (act[2] - act[1])
		end
		s += act[3]
	end
	return 0
end

function WorldService.IsNight()
	return Workspace:GetAttribute("IsNight") == true
end

-- Studio testing (DebugService): pin the clock or the weather. nil = back to normal.
WorldService.Override = { Clock = nil, Rain = nil }

function WorldService.Init()
	if not Workspace.Terrain:FindFirstChildOfClass("Clouds") then
		Instance.new("Clouds").Parent = Workspace.Terrain
	end
	-- The sun's path: rises at 6:00 and sets at 18:00 whatever this is, but the higher the latitude the lower
	-- it rides at midday (72 degrees here, against 87 at a true South Florida 26), so noon still casts the
	-- long shadows that give the streets shape (Look 4.0).
	Lighting.GeographicLatitude = 41
	Lighting.EnvironmentSpecularScale = 1
	local elapsed = secondsAt(START_CLOCK)
	local lastApply = -1
	local nextStormRoll = elapsed + STORM_CHECK
	local stormUntil = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local clock = WorldService.Override.Clock or clockAt(elapsed)
		Lighting.ClockTime = clock
		if elapsed - lastApply > 0.5 then
			lastApply = elapsed
			local night = nightnessAt(clock) > 0.5
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
			apply(clock, raining)
		end
	end)
end

return WorldService
