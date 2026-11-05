-- PoliceHeliClient (ModuleScript, StarterPlayerScripts.Controllers.PoliceHeliClient)
-- Draws the police helicopters PoliceHeliService flies. The server moves one invisible part per
-- helicopter (Workspace.PoliceAir, "PoliceHeli"); this device builds the look and glides it after that
-- part (FOLLOW), so it flies smoothly whatever the network does:
--   * navy and white with POLICE down both sides, a spinning main and tail rotor (forward is -Z);
--   * a red and a blue beacon flashing in turn, a white strobe on the fin;
--   * the rotor's chop (Config.Ambience.Sounds.Rotor, louder and closer than the news helicopter's, on
--     the Effects slider);
--   * at night (Workspace attribute IsNight), a searchlight: on whoever it is after while it can see
--     them (attribute Lock), else sweeping round where it lost them (attribute Aim). Off once it leaves.
--     Performance mode keeps the beam but drops the SpotLight on the ground.
-- Every part is anchored and untouchable (no collisions, rays, touches or shadows) and all of them move
-- with one BulkMoveTo a frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage.Shared.Util.Theme)

local PoliceHeliClient = {}

local FOLLOW = 8 -- per second: how quickly the look catches up with the server's part
local SNAP = 300 -- studs: further off than this it jumps there (it has only just appeared)
local ROTOR_SPIN, TAIL_SPIN = 21, 40 -- radians/s
local FLASH = 0.3 -- seconds each beacon is lit in turn
local AIM_FOLLOW = 4 -- per second: how quickly the searchlight swings onto its new spot
local BEAM_DROP = 30 -- studs the SpotLight hangs over the lit spot

local NAVY = Color3.fromRGB(22, 30, 58)
local WHITE = Color3.fromRGB(236, 238, 242)
local DARK = Color3.fromRGB(40, 42, 48)
local GLASS = Color3.fromRGB(40, 52, 72)
local RED = Color3.fromRGB(255, 40, 50)
local BLUE = Color3.fromRGB(40, 110, 255)
local LAMP = Color3.fromRGB(225, 236, 255)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- stands a Cylinder (axis X) upright
local NEON = Enum.Material.Neon
local PLAIN = Enum.Material.SmoothPlastic

local looks = {} -- [server part] = rig
local looksFolder
local moveParts, moveCFrames = {}, {}
local Settings -- SettingsClient, found on first use (false = not there)

local function settings()
	if Settings == nil then
		local module = script.Parent:FindFirstChild("SettingsClient")
		local ok, found = false, nil
		if module then
			ok, found = pcall(require, module)
		end
		Settings = ok and type(found) == "table" and found or false
	end
	return Settings or nil
end

local function performanceMode()
	local s = settings()
	if s and type(s.Get) == "function" then
		local ok, v = pcall(s.Get, "Performance")
		return ok and v == true
	end
	return false
end

local function effectsGroup()
	local s = settings()
	if s and type(s.Group) == "function" then
		local ok, group = pcall(s.Group, "Effects")
		if ok and typeof(group) == "Instance" and group:IsA("SoundGroup") then
			return group
		end
	end
	return nil
end

-- One anchored, untouchable part; offset = its place relative to the helicopter's root.
local function addPart(rig, name, size, offset, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or PLAIN
	p.Parent = rig.model
	local i = #rig.parts + 1
	rig.parts[i] = p
	rig.offsets[i] = offset
	return p, i
end

-- POLICE on one side of the white band.
local function label(part, face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Police" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 1
	gui.MaxDistance = 900
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.FontFace = Theme.Font.Display
	text.TextColor3 = NAVY
	text.Text = "POLICE"
	text.Parent = gui
	gui.Parent = part
end

local function beacon(rig, name, offset, color)
	local p = addPart(rig, name, Vector3.new(0.7, 0.45, 0.7), offset, color, NEON)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 16
	light.Brightness = 3
	light.Shadows = false
	light.Parent = p
	return { part = p, light = light }
end

local function rotorSound(body)
	local ok, Ambience = pcall(require, ReplicatedStorage.Shared.Config.Ambience)
	local def = ok and type(Ambience) == "table" and type(Ambience.Sounds) == "table" and Ambience.Sounds.Rotor
	if type(def) ~= "table" or type(def.Id) ~= "number" or def.Id <= 0 then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = "Rotor"
	s.SoundId = "rbxassetid://" .. def.Id
	s.Volume = 0.55 -- (the news helicopter's is 0.26, up at 240 studs: this one is low and after you)
	s.Looped = true
	local region = def.Region
	if type(region) == "table" and type(region[1]) == "number" and type(region[2]) == "number" and region[2] > region[1] then
		local range = NumberRange.new(region[1], region[2])
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = range
		s.LoopRegion = range
	end
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 70
	s.RollOffMaxDistance = 1100
	s.SoundGroup = effectsGroup()
	s.Parent = body
	s:Play()
	return s
end

-- The helicopter's look for one server part (forward is -Z, the root at the cabin's middle).
local function build(server)
	local rig = { server = server, parts = {}, offsets = {}, model = Instance.new("Model"), spin = 0 }
	rig.model.Name = "PoliceHelicopter"
	local body = addPart(rig, "Body", Vector3.new(5.4, 4.8, 10.5), CFrame.new(), NAVY)
	local band = addPart(rig, "Band", Vector3.new(5.5, 2, 10.6), CFrame.new(0, -0.4, 0), WHITE)
	label(band, Enum.NormalId.Left)
	label(band, Enum.NormalId.Right)
	local nose = addPart(rig, "Nose", Vector3.new(4.6, 3.8, 3), CFrame.new(0, 0.2, -6.2), GLASS, Enum.Material.Glass)
	nose.Transparency = 0.2
	addPart(rig, "Belly", Vector3.new(5.5, 1, 10.6), CFrame.new(0, -2, 0), DARK)
	addPart(rig, "Boom", Vector3.new(1.3, 1.3, 11.5), CFrame.new(0, 0.9, 10.8), NAVY)
	addPart(rig, "BoomBand", Vector3.new(1.35, 0.5, 6), CFrame.new(0, 0.9, 9), WHITE)
	addPart(rig, "Fin", Vector3.new(0.35, 3.8, 2.3), CFrame.new(0, 2.7, 16), NAVY)
	addPart(rig, "Stabiliser", Vector3.new(4.6, 0.25, 1.4), CFrame.new(0, 1, 15), NAVY)
	for _, x in ipairs({ -2.6, 2.6 }) do
		addPart(rig, "Skid", Vector3.new(0.45, 0.45, 11.5), CFrame.new(x, -3.8, 0), DARK)
	end
	for _, z in ipairs({ -3, 3 }) do
		addPart(rig, "Strut", Vector3.new(5.6, 0.35, 0.35), CFrame.new(0, -3.2, z), DARK)
	end
	addPart(rig, "Mast", Vector3.new(0.8, 1.3, 0.8), CFrame.new(0, 3, 0), DARK)
	local disc = addPart(rig, "RotorDisc", Vector3.new(0.1, 36, 36), CFrame.new(0, 3.7, 0) * UPRIGHT, DARK, nil, Enum.PartType.Cylinder)
	disc.Transparency = 0.93
	local _, a = addPart(rig, "RotorA", Vector3.new(36, 0.18, 1.1), CFrame.new(0, 3.7, 0), DARK)
	local _, b = addPart(rig, "RotorB", Vector3.new(1.1, 0.18, 36), CFrame.new(0, 3.7, 0), DARK)
	local _, t = addPart(rig, "TailRotor", Vector3.new(0.15, 3.8, 0.5), CFrame.new(0.85, 1.6, 16.6), DARK)
	rig.rotorA, rig.rotorB, rig.tailRotor = a, b, t
	rig.rotorBase, rig.tailBase = rig.offsets[a], rig.offsets[t]
	rig.red = beacon(rig, "BeaconRed", CFrame.new(-1.2, 2.55, 3.4), RED)
	rig.blue = beacon(rig, "BeaconBlue", CFrame.new(1.2, 2.55, 3.4), BLUE)
	rig.strobe = addPart(rig, "Strobe", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 4.7, 16.9), WHITE, NEON)

	-- The searchlight: a lamp under the nose, a beam down to an invisible spot that carries the SpotLight.
	local lamp = addPart(rig, "Searchlight", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, -2.9, -4), DARK, nil, Enum.PartType.Ball)
	local from = Instance.new("Attachment")
	from.Name = "Lamp"
	from.Position = Vector3.new(0, -0.6, 0)
	from.Parent = lamp
	local spot = Instance.new("Part")
	spot.Name = "SearchlightSpot"
	spot.Size = Vector3.new(1, 1, 1)
	spot.Transparency = 1
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanQuery = false
	spot.CanTouch = false
	spot.CastShadow = false
	spot.Parent = rig.model
	local ground = Instance.new("Attachment")
	ground.Name = "Ground"
	ground.Position = Vector3.new(0, -BEAM_DROP, 0)
	ground.Parent = spot
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Range = BEAM_DROP + 20
	light.Angle = 50
	light.Brightness = 5
	light.Color = LAMP
	light.Shadows = false
	light.Enabled = false
	light.Parent = spot
	local beam = Instance.new("Beam")
	beam.Name = "Searchlight"
	beam.Attachment0 = from
	beam.Attachment1 = ground
	beam.Width0 = 1.4
	beam.Width1 = 18
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(LAMP)
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.9) })
	beam.Enabled = false
	beam.Parent = lamp
	rig.spot, rig.spotLight, rig.beam = spot, light, beam

	rig.sound = rotorSound(body)
	-- In place before it is shown (never a frame at the world's origin).
	rig.cf = server.CFrame
	for i, part in ipairs(rig.parts) do
		part.CFrame = rig.cf * rig.offsets[i]
	end
	rig.model.Parent = looksFolder
	return rig
end

local function drop(server)
	local rig = looks[server]
	if rig then
		looks[server] = nil
		rig.model:Destroy()
	end
end

local function add(server)
	if server:IsA("BasePart") and server.Name == "PoliceHeli" and not looks[server] then
		looks[server] = build(server)
	end
end

-- Where the searchlight should land: on the target while it is on them, else its sweep point.
local function aimGoal(server)
	if server:GetAttribute("Lock") == true then
		local who = Players:GetPlayerByUserId(server:GetAttribute("AITarget") or 0)
		local root = who and who.Character and who.Character:FindFirstChild("HumanoidRootPart")
		if root then
			return root.Position
		end
	end
	local aim = server:GetAttribute("Aim")
	return typeof(aim) == "Vector3" and aim or nil
end

local function frame(dt)
	local n = 0
	local clock = os.clock()
	local night = Workspace:GetAttribute("IsNight") == true
	local perf = performanceMode()
	local redOn = (clock % (FLASH * 2)) < FLASH
	local strobeOn = (clock % 1.1) < 0.08
	for server, rig in pairs(looks) do
		if not server.Parent then
			drop(server)
			continue
		end
		local goal = server.CFrame
		if not rig.cf or (rig.cf.Position - goal.Position).Magnitude > SNAP then
			rig.cf = goal
		else
			rig.cf = rig.cf:Lerp(goal, 1 - math.exp(-dt * FOLLOW))
		end
		local cf = rig.cf
		rig.spin += dt
		rig.offsets[rig.rotorA] = rig.rotorBase * CFrame.Angles(0, rig.spin * ROTOR_SPIN, 0)
		rig.offsets[rig.rotorB] = rig.rotorBase * CFrame.Angles(0, rig.spin * ROTOR_SPIN + math.pi / 2, 0)
		rig.offsets[rig.tailRotor] = rig.tailBase * CFrame.Angles(rig.spin * TAIL_SPIN, 0, 0)
		for i, part in ipairs(rig.parts) do
			n += 1
			moveParts[n] = part
			moveCFrames[n] = cf * rig.offsets[i]
		end

		-- Beacons: red, blue, red... and the fin's white blink.
		if rig.redOn ~= redOn then
			rig.redOn = redOn
			rig.red.part.Transparency = redOn and 0 or 0.7
			rig.red.light.Enabled = redOn
			rig.blue.part.Transparency = redOn and 0.7 or 0
			rig.blue.light.Enabled = not redOn
		end
		if rig.strobeOn ~= strobeOn then
			rig.strobeOn = strobeOn
			rig.strobe.Transparency = strobeOn and 0 or 1
		end

		-- The searchlight (night only, and not once it is leaving).
		local aim = night and server:GetAttribute("Leaving") ~= true and aimGoal(server) or nil
		if aim then
			rig.aim = rig.aim and rig.aim:Lerp(aim, 1 - math.exp(-dt * AIM_FOLLOW)) or aim
			n += 1
			moveParts[n] = rig.spot
			moveCFrames[n] = CFrame.new(rig.aim + Vector3.new(0, BEAM_DROP, 0))
		else
			rig.aim = nil -- (it comes back on right where it should be, not where it was left)
		end
		local beamOn = aim ~= nil
		if rig.beam.Enabled ~= beamOn then
			rig.beam.Enabled = beamOn
		end
		local lampOn = beamOn and not perf
		if rig.spotLight.Enabled ~= lampOn then
			rig.spotLight.Enabled = lampOn
		end
	end
	for i = #moveParts, n + 1, -1 do
		moveParts[i], moveCFrames[i] = nil, nil -- (last frame's extras: a helicopter that has gone)
	end
	if n > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function watch(air)
	air.ChildAdded:Connect(add)
	air.ChildRemoved:Connect(drop)
	for _, child in ipairs(air:GetChildren()) do
		add(child)
	end
end

function PoliceHeliClient.Init()
	looksFolder = Instance.new("Folder")
	looksFolder.Name = "PoliceHeliLooks"
	looksFolder.Parent = Workspace
	local air = Workspace:FindFirstChild("PoliceAir")
	if air then
		watch(air)
	else
		local conn
		conn = Workspace.ChildAdded:Connect(function(child)
			if child.Name == "PoliceAir" and child:IsA("Folder") then
				conn:Disconnect()
				watch(child)
			end
		end)
	end
	local warned = false
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(frame, dt)
		if not ok and not warned then
			warned = true -- (once: an error here would repeat every frame)
			warn("[PoliceHeliClient] " .. tostring(err))
		end
	end)
end

return PoliceHeliClient
