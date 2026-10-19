-- SkyClient (ModuleScript, StarterPlayerScripts.Controllers.SkyClient)
-- Client-side weather: while Workspace attribute Raining is true, rain streaks fall around the camera
-- (one emitter on a local part that follows the camera, so it costs the same anywhere in the city;
-- lighter in Performance mode) and lightning flashes now and then. Day/night lighting itself is set
-- by the server (WorldService).
-- Night windows: about 30% of the "Window" parts in Workspace.City glow after dark. Each window's own
-- colour and material are remembered and put back at dawn, and the switch is spread over several
-- frames (there are ~2,000 windows).
-- Event props (EventService, Workspace.Events), animated here so the server doesn't stream every frame:
--   attribute Spin = radians/s   the part turns around its own X axis (a Cylinder's axis)
--   attribute Disco = true       a neon part that cycles through party colours

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local SkyClient = {}

local RAIN_RATE, RAIN_RATE_PERF = 480, 160 -- particles per second
local WINDOWS_PER_FRAME = 120

local rainPart, emitter
local raining = false
local nextFlash = 0

local function performance()
	local settings = script.Parent:FindFirstChild("SettingsClient")
	return settings ~= nil and require(settings).Get("Performance") == true
end

local function build()
	rainPart = Instance.new("Part")
	rainPart.Name = "RainCloud"
	rainPart.Anchored = true
	rainPart.CanCollide = false
	rainPart.CanQuery = false
	rainPart.CanTouch = false
	rainPart.Transparency = 1
	rainPart.Size = Vector3.new(110, 1, 110)
	rainPart.Parent = Workspace.CurrentCamera
	emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Rain"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 220, 255))
	emitter.LightEmission = 0.3
	emitter.Transparency = NumberSequence.new(0.3)
	emitter.Size = NumberSequence.new(0.22)
	emitter.Squash = NumberSequence.new(-3) -- stretch into streaks
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Speed = NumberRange.new(110, 130)
	emitter.Lifetime = NumberRange.new(0.55, 0.7)
	emitter.Rate = 0
	emitter.Parent = rainPart
end

local function applyRainRate()
	emitter.Rate = raining and (performance() and RAIN_RATE_PERF or RAIN_RATE) or 0
end

local function setRain(on)
	local was = raining
	raining = on
	applyRainRate()
	if on and not was then
		NotifyController.Show("A Florida storm rolls in. Wet roads, careful on the corners!", Color3.fromRGB(34, 225, 255))
	end
end

------------------------------------------------------------------ night windows

local windows = {} -- [part] = { color, material } (its own look, to put back by day)
local lit = false
local queue = {} -- windows still to restyle after a day/night switch
local WARM = { Color3.fromRGB(255, 196, 120), Color3.fromRGB(255, 150, 200), Color3.fromRGB(150, 210, 255) }
local NIGHT_GLASS = Color3.fromRGB(40, 56, 84)

local function windowLit(part)
	-- Stable per window: hash its position so the same windows light every night.
	local p = part.Position
	local h = math.abs(math.floor(p.X * 7.3 + p.Y * 3.1 + p.Z * 5.7)) % 100
	return h < 30, WARM[h % #WARM + 1]
end

local function setWindow(part, on)
	local own = windows[part]
	if not own then
		return
	end
	if on then
		local yes, color = windowLit(part)
		if yes then
			part.Material = Enum.Material.Neon
			part.Color = color:Lerp(Color3.new(0, 0, 0), 0.72)
		else
			part.Material = Enum.Material.Glass
			part.Color = NIGHT_GLASS
		end
	else
		part.Material = own.material
		part.Color = own.color
	end
end

local function track(inst)
	if inst:IsA("BasePart") and inst.Name == "Window" and not windows[inst] then
		windows[inst] = { color = inst.Color, material = inst.Material }
		if lit then
			setWindow(inst, true)
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
		windows[inst] = nil
	end)
	local function refresh()
		local night = Workspace:GetAttribute("IsNight") == true
		if night == lit then
			return
		end
		lit = night
		-- Restyle a batch per frame (see Heartbeat below) instead of every window at once.
		table.clear(queue)
		for part in pairs(windows) do
			table.insert(queue, part)
		end
	end
	refresh()
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(refresh)
	RunService.Heartbeat:Connect(function()
		for _ = 1, math.min(#queue, WINDOWS_PER_FRAME) do
			local part = table.remove(queue)
			if part and part.Parent then
				setWindow(part, lit)
			end
		end
	end)
end

------------------------------------------------------------------ event props

local spinners = {} -- [part] = true
local discos = {} -- [part] = phase
local DISCO = {
	Color3.fromRGB(255, 62, 165), Color3.fromRGB(34, 225, 255), Color3.fromRGB(110, 242, 196),
	Color3.fromRGB(255, 214, 10), Color3.fromRGB(190, 120, 255),
}

local function watchProp(inst)
	if not inst:IsA("BasePart") then
		return
	end
	if type(inst:GetAttribute("Spin")) == "number" then
		spinners[inst] = true
	end
	if inst:GetAttribute("Disco") == true then
		discos[inst] = math.random() * #DISCO
	end
end

local function watchEvents()
	local events = Workspace:WaitForChild("Events", 60)
	if not events then
		return
	end
	for _, d in ipairs(events:GetDescendants()) do
		watchProp(d)
	end
	events.DescendantAdded:Connect(watchProp)
	events.DescendantRemoving:Connect(function(inst)
		spinners[inst] = nil
		discos[inst] = nil
	end)
end

local function animateProps(dt)
	for part in pairs(spinners) do
		local rate = part:GetAttribute("Spin")
		if part.Parent and type(rate) == "number" then
			part.CFrame *= CFrame.Angles(rate * dt, 0, 0)
		else
			spinners[part] = nil
		end
	end
	local t = os.clock() * 1.6
	for part, phase in pairs(discos) do
		if part.Parent then
			local x = (t + phase) % #DISCO
			local i = math.floor(x)
			part.Color = DISCO[i + 1]:Lerp(DISCO[(i + 1) % #DISCO + 1], x - i)
		else
			discos[part] = nil
		end
	end
end

function SkyClient.Init()
	build()
	task.spawn(watchWindows)
	task.spawn(watchEvents)
	setRain(Workspace:GetAttribute("Raining") == true)
	Workspace:GetAttributeChangedSignal("Raining"):Connect(function()
		setRain(Workspace:GetAttribute("Raining") == true)
	end)
	-- Performance mode can change any time in SETTINGS.
	task.spawn(function()
		while true do
			task.wait(2)
			applyRainRate()
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		rainPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 45, 0))
		animateProps(dt)
		-- Lightning: a quick double flash every 8-20 seconds during storms.
		if raining and os.clock() > nextFlash then
			nextFlash = os.clock() + math.random(8, 20)
			task.spawn(function()
				local cc = Lighting:FindFirstChild("NeonGrade")
				if not cc or not cc:IsA("ColorCorrectionEffect") then
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
