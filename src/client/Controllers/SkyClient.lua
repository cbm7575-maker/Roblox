-- SkyClient (ModuleScript, StarterPlayerScripts.Controllers.SkyClient)
-- Client-side weather: while Workspace attribute Raining is true, rain streaks fall around the camera
-- (one emitter on a local part that follows the camera, so it costs the same anywhere in the city)
-- and lightning flashes now and then. Day/night lighting itself is set by the server (WorldService).

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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
local windows = {} -- [part] = true
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
	part.Material = Enum.Material.Glass
	part.Color = Color3.fromRGB(40, 56, 84)
end

local function track(inst)
	if inst:IsA("BasePart") and inst.Name == "Window" then
		windows[inst] = true
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
		for part in pairs(windows) do
			setWindow(part, night)
		end
	end
	refresh()
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(refresh)
end

function SkyClient.Init()
	build()
	task.spawn(watchWindows)
	setRain(Workspace:GetAttribute("Raining") == true)
	Workspace:GetAttributeChangedSignal("Raining"):Connect(function()
		setRain(Workspace:GetAttribute("Raining") == true)
	end)
	RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		rainPart.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 45, 0))
		-- Lightning: a quick double flash every 8-20 seconds during storms.
		if Workspace:GetAttribute("Raining") and os.clock() > nextFlash then
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
