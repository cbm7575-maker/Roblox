-- SkyClient (ModuleScript, StarterPlayerScripts.Controllers.SkyClient)
-- Client-side weather: while Workspace attribute Raining is true, rain streaks fall around the camera
-- (one emitter on a local part that follows the camera, so it costs the same anywhere in the city)
-- and lightning flashes now and then (not inside a home, player attribute InHome). Day/night lighting
-- itself is set by the server (WorldService).
-- Night windows: glass strips (parts named "Window") glow, and building facades (Look 2.0, Textures
-- named "Facade") near the camera get a glowing overlay where about 40% of the windows are lit.
-- Traffic signals (Restyle's TrafficSignal models) cycle green / amber / red, one axis at a time
-- (the shared cycle in Util.Signals, which ambient traffic obeys too).
-- Night neon (Look 3.0): building trims tagged "NightNeon" are dark metal by day and glow in their
-- NeonColor attribute after dark; street lamps tagged "NightLamp" switch on in their LampColor; shop
-- windows tagged "NightShop" throw warm light onto the sidewalk (not in Performance mode). Any Light
-- inside them follows. All local-only. At dusk they come on block by block, outward from downtown
-- (AmbienceClient.DuskWave); at dawn they go off together.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Textures = require(ReplicatedStorage.Shared.Config.Textures)
local Signals = require(ReplicatedStorage.Shared.Util.Signals)
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local SkyClient = {}

local rainPart, emitter
local nextFlash = 0

local function build()
	rainPart = Instance.new("Part")
	rainPart.Name = "RainCloud"
	rainPart.Anchored = true
	rainPart.CanCollide = false
	rainPart.CanQuery = false
	rainPart.CanTouch = false
	rainPart.Transparency = 1
	rainPart.Size = Vector3.new(120, 1, 120)
	rainPart.Parent = Workspace.CurrentCamera
	emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Rain"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 220, 255))
	emitter.LightEmission = 0.3
	emitter.Transparency = NumberSequence.new(0.35)
	emitter.Size = NumberSequence.new(0.18)
	emitter.Squash = NumberSequence.new(-3) -- stretch into streaks
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Speed = NumberRange.new(110, 130)
	emitter.Lifetime = NumberRange.new(0.6, 0.8)
	emitter.Rate = 0
	emitter.Parent = rainPart
end

local function setRain(on)
	emitter.Rate = on and 900 or 0
	if on then
		NotifyController.Show("A Florida storm rolls in. Wet roads, careful on the corners!", Color3.fromRGB(34, 225, 255))
	end
end

-- Night windows: about 30% of window strips glow softly after dark (local-only changes).
local windows = {} -- [part] = { Material, Color }: its own look, as the server built it
local lit = false
local WARM = { Color3.fromRGB(255, 196, 120), Color3.fromRGB(255, 150, 200), Color3.fromRGB(150, 210, 255) }

local function windowLit(part)
	-- Stable per window: hash its position so the same windows light every night.
	local p = part.Position
	local h = math.abs(math.floor(p.X * 7.3 + p.Y * 3.1 + p.Z * 5.7)) % 100
	return h < 30, WARM[h % #WARM + 1]
end

local function setWindow(part, on)
	if on then
		local yes, color = windowLit(part)
		if yes then
			part.Material = Enum.Material.Neon
			part.Color = color:Lerp(Color3.new(0, 0, 0), 0.72)
			return
		end
	end
	-- Not glowing: the window's own look back, not one dark glass for every window. The prison's pale
	-- barred panes turned dark blue after their first night and stayed that way, so the bars were lost.
	local own = windows[part]
	if own then
		part.Material = own[1]
		part.Color = own[2]
	end
end

-- Facade night lights. Textures are always shaded by the scene lighting, so lit windows drawn on a
-- Texture stay dark at night. A SurfaceGui with LightInfluence 0 glows instead, but costs more, so
-- only faces near the camera get one (a pool that follows you), and none in Performance mode.
local GLOW_RANGE = 320 -- studs from the camera
local GLOW_PPS = 4 -- SurfaceGui pixels per stud
local facades = {} -- [Texture "Facade"] = its SurfaceGui "NightGlow" while one is shown, else false

local function performanceMode()
	local ok, Settings = pcall(require, script.Parent:FindFirstChild("SettingsClient"))
	return ok and Settings and Settings.Get and Settings.Get("Performance") == true
end

local function makeGlow(facade)
	local image = Textures.NightFor[facade.Texture]
	local p = facade.Parent
	if not image or not p or not p:IsA("BasePart") then
		return nil
	end
	local front = facade.Face == Enum.NormalId.Front or facade.Face == Enum.NormalId.Back
	local w, h = front and p.Size.X or p.Size.Z, p.Size.Y
	local tileU, tileV = Textures.BayWidth * 4, Textures.FloorHeight * 3
	-- A stable pattern per face: shift the 4 x 3 bay tile by a whole number of bays.
	local hash = math.abs(math.floor(p.Position.X * 3.7 + p.Position.Z * 5.3 + facade.Face.Value * 11))
	local ou = (facade.OffsetStudsU + (hash % 4) * Textures.BayWidth) % tileU
	local ov = (facade.OffsetStudsV + (hash % 3) * Textures.FloorHeight) % tileV
	local gui = Instance.new("SurfaceGui")
	gui.Name = "NightGlow"
	gui.Face = facade.Face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = GLOW_PPS
	gui.LightInfluence = 0
	gui.Brightness = 1.1 -- the night look already lifts exposure (WorldService)
	gui.ClipsDescendants = true
	gui.MaxDistance = GLOW_RANGE + 60
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Image = image
	img.ScaleType = Enum.ScaleType.Tile
	img.TileSize = UDim2.fromOffset(tileU * GLOW_PPS, tileV * GLOW_PPS)
	-- Start one tile up-left and cover the face plus a tile, so the offset lines up with the day windows.
	img.Position = UDim2.fromOffset((ou - tileU) * GLOW_PPS, (ov - tileV) * GLOW_PPS)
	img.Size = UDim2.fromOffset((w + tileU * 2) * GLOW_PPS, (h + tileV * 2) * GLOW_PPS)
	img.Parent = gui
	gui.Parent = p
	return gui
end

local function dropGlow(facade)
	local g = facades[facade]
	if g then
		g:Destroy()
	end
	if facades[facade] ~= nil then
		facades[facade] = false
	end
end

-- Is the camera in front of this face? (+16 studs of slack so a face is lit before you round a corner.)
-- Faces pointing away can never be seen, so they get no glow.
local function faceSeen(facade, p, cam)
	local n = Vector3.FromNormalId(facade.Face) -- local-space normal; only side faces carry Facades
	local half = math.abs(n.X) * p.Size.X / 2 + math.abs(n.Z) * p.Size.Z / 2
	return p.CFrame:PointToObjectSpace(cam):Dot(n) > half - 16
end

-- Every second at night: glow for facades within range of the camera and facing it, none otherwise.
local function updateGlows()
	if not lit or performanceMode() then
		for facade, g in pairs(facades) do
			if g then
				dropGlow(facade)
			end
		end
		return
	end
	local cam = Workspace.CurrentCamera.CFrame.Position
	for facade, g in pairs(facades) do
		local p = facade.Parent
		if not p or not facade:IsDescendantOf(Workspace) then
			if g then
				g:Destroy()
			end
			facades[facade] = nil
		else
			local near = (p.Position - cam).Magnitude < GLOW_RANGE + math.max(p.Size.X, p.Size.Z) / 2
				and faceSeen(facade, p, cam)
			if near and not g then
				facades[facade] = makeGlow(facade) or false
			elseif not near and g then
				dropGlow(facade)
			end
		end
	end
end

local function track(inst)
	if inst:IsA("BasePart") and inst.Name == "Window" then
		-- (remembered before we change anything; kept if we already know this window)
		windows[inst] = windows[inst] or { inst.Material, inst.Color }
		if lit then
			setWindow(inst, true)
		end
	elseif inst:IsA("Texture") and inst.Name == "Facade" then
		if facades[inst] == nil then
			facades[inst] = false -- updateGlows adds its glow when it's night and near
		end
	end
end

local function watchWindows()
	local city = Workspace:WaitForChild("City", 30)
	if not city then
		return
	end
	for _, d in ipairs(city:GetDescendants()) do
		track(d)
	end
	city.DescendantAdded:Connect(track)
	city.DescendantRemoving:Connect(function(inst)
		-- A window streaming out goes in its own look: if the same part streams back in, what we
		-- remember for it then must not be last night's glow.
		if windows[inst] then
			setWindow(inst, false)
		end
		windows[inst] = nil
		if facades[inst] ~= nil then
			dropGlow(inst)
			facades[inst] = nil
		end
	end)
	local function refresh()
		local night = Workspace:GetAttribute("IsNight") == true
		if night == lit then
			return
		end
		lit = night
		for part in pairs(windows) do
			setWindow(part, night)
		end
		updateGlows()
	end
	refresh()
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(refresh)
	while true do
		task.wait(1)
		updateGlows()
	end
end

-- Night neon and street lamps (tags from the Look3 tool).
local TRIM_DAY = Color3.fromRGB(58, 60, 66)
local LAMP_OFF = Color3.fromRGB(226, 226, 220)

local GLOW_TAGS = { "NightNeon", "NightLamp", "NightShop" }

local function setGlow(part, tag, night)
	if not part:IsA("BasePart") then
		return
	end
	local lamp = tag == "NightLamp"
	if tag == "NightShop" then
		-- Only its light changes; phones in Performance mode skip these (hundreds of extra lights).
		night = night and not performanceMode()
	else
		local color = part:GetAttribute(lamp and "LampColor" or "NeonColor")
		if night and typeof(color) == "Color3" then
			part.Material = Enum.Material.Neon
			part.Color = color
		else
			part.Material = lamp and Enum.Material.SmoothPlastic or Enum.Material.Metal
			part.Color = lamp and LAMP_OFF or TRIM_DAY
		end
	end
	for _, l in ipairs(part:GetChildren()) do
		if l:IsA("Light") then
			l.Enabled = night
		end
	end
end

local function watchNeon()
	local function isNight()
		return Workspace:GetAttribute("IsNight") == true
	end
	for _, tag in ipairs(GLOW_TAGS) do
		-- Parts streaming in later take the current state right away.
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(part)
			setGlow(part, tag, isNight())
		end)
	end
	-- Dusk: the lights come on block by block, outward from downtown, over about 6 s
	-- (AmbienceClient.DuskWave, timings in Config.Ambience.Dusk). Dawn, joining at night, or no
	-- AmbienceClient: all at once.
	local waves = {} -- stop functions of the waves still running
	local function refresh(joining)
		local night = isNight()
		for _, stop in ipairs(waves) do
			stop()
		end
		table.clear(waves)
		local ambience = nil
		if night and joining ~= true then
			local ok, found = pcall(require, script.Parent:FindFirstChild("AmbienceClient"))
			if ok and type(found) == "table" and type(found.DuskWave) == "function" then
				ambience = found
			end
		end
		for _, tag in ipairs(GLOW_TAGS) do
			local parts = CollectionService:GetTagged(tag)
			if ambience then
				table.insert(waves, ambience.DuskWave(parts, function(part)
					setGlow(part, tag, true)
				end))
			else
				for _, part in ipairs(parts) do
					setGlow(part, tag, night)
				end
			end
		end
	end
	refresh(true)
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		refresh(false)
	end)
end

-- Traffic signals: 14 s green, 3 s amber, then the other axis gets its turn (Util.Signals). Lamps are local-only.
local signalLamps = {} -- [lamp] = { axis, colour, on colour }
local function trackSignal(inst)
	if inst:IsA("BasePart") and inst.Name == "Lamp" and inst.Parent and inst.Parent.Name == "TrafficSignal" then
		local colour = inst:GetAttribute("Colour")
		local on = colour == "Red" and Color3.fromRGB(255, 40, 40) or colour == "Green" and Color3.fromRGB(40, 255, 110)
			or Color3.fromRGB(255, 176, 0)
		local info = { inst.Parent:GetAttribute("Axis"), colour, on }
		signalLamps[inst] = info
		return info
	end
	return nil
end

local function applyLamp(lamp, info, axis, amber)
	local want = info[1] == axis and (amber and "Amber" or "Green") or "Red"
	local on = info[2] == want
	lamp.Material = on and Enum.Material.Neon or Enum.Material.SmoothPlastic
	lamp.Color = on and info[3] or info[3]:Lerp(Color3.new(0, 0, 0), 0.75)
end

local lastPhase
local function updateSignals()
	local axis, amber = Signals.Phase()
	local key = axis .. tostring(amber)
	if key == lastPhase then
		return
	end
	lastPhase = key
	for lamp, info in pairs(signalLamps) do
		if lamp.Parent then
			applyLamp(lamp, info, axis, amber)
		else
			signalLamps[lamp] = nil
		end
	end
end

local function watchSignals()
	local city = Workspace:WaitForChild("City", 30)
	if not city then
		return
	end
	for _, d in ipairs(city:GetDescendants()) do
		trackSignal(d)
	end
	city.DescendantAdded:Connect(function(inst)
		local info = trackSignal(inst)
		if info then
			applyLamp(inst, info, Signals.Phase()) -- a streamed-in lamp shows the current phase right away
		end
	end)
	while true do
		updateSignals()
		task.wait(0.2) -- cheap (only acts on a phase change); keeps the lamps in step with the traffic
	end
end

function SkyClient.Init()
	build()
	task.spawn(watchWindows)
	task.spawn(watchSignals)
	task.spawn(watchNeon)
	setRain(Workspace:GetAttribute("Raining") == true)
	Workspace:GetAttributeChangedSignal("Raining"):Connect(function()
		setRain(Workspace:GetAttribute("Raining") == true)
	end)
	RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		rainPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 45, 0))
		-- Lightning: a quick double flash every 8-20 seconds during storms.
		if Workspace:GetAttribute("Raining") and Players.LocalPlayer:GetAttribute("InHome") ~= true and os.clock() > nextFlash then
			nextFlash = os.clock() + math.random(8, 20)
			task.spawn(function()
				local cc = Lighting:FindFirstChild("NeonGrade")
				if not cc then
					return
				end
				task.delay(math.random() * 1.5, function()
					require(script.Parent:WaitForChild("SoundClient")).Play("Thunder", nil, 0.6 + math.random() * 0.4)
				end)
				for _ = 1, 2 do
					local before = cc.Brightness
					cc.Brightness = before + 0.35
					task.wait(0.07)
					cc.Brightness = before
					task.wait(0.12)
				end
			end)
		end
	end)
end

return SkyClient
