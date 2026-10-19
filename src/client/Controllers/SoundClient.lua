-- SoundClient (ModuleScript, StarterPlayerScripts.Controllers.SoundClient)
-- Everything you hear (IDs in Config.Sounds). All sounds are created locally on this device.
--   SoundClient.Play(name, where)  one-shot: where = nil (flat), a Vector3 or a BasePart (3D)
--   SoundClient.SetDistrict(key)    DistrictClient: which district you're in (ambience mix), nil = unknown
--   * Engines: every driven car (players and AI) hums, pitch rising with speed; loops further away
--     than they can be heard are stopped.
--   * Sirens: AI patrols that are chasing someone, and player cop cars with the siren on (H).
--   * Horn: civilians press H; everyone nearby hears it (car attribute HonkAt, VehicleService).
--   * Your car: tyre squeal when sliding, nitro whoosh, door thunk, splash when it sinks (not boats).
--   * Heist alarms ring at a site while its AlarmUntil time runs.
--   * Rain and thunder in storms; surf and gulls at the beach; a city hum downtown (mixed per district).
--   * Event music: any part in Workspace.Events with a MusicId attribute (an Id from Config.Sounds.Radio,
--     set by EventService) plays that track locally as a 3D loop (Music volume).
--   * Car radio: three stations (Config.Sounds.Radio) while you drive. V or the RADIO pill cycles
--     Neon FM -> Palm 99 -> Gator Radio -> off.
--   * Moments: cash, stamps, cuffs, taser zaps, race beeps, UI clicks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local player = Players.LocalPlayer

local SoundClient = {}

local PINK = Color3.fromRGB(255, 62, 165)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

local flat -- folder for 2D sounds
local anchorPart -- invisible anchored part holding one-shot 3D attachments

local function effect(name)
	return Sounds.Effects[name]
end

local function newSound(name, parent)
	local def = effect(name)
	if not def or def.Id == 0 then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxassetid://" .. def.Id
	s.Volume = def.Volume or 0.5
	s.Looped = def.Looped == true
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 25
	s.RollOffMaxDistance = 400
	s.SoundGroup = require(script.Parent:WaitForChild("SettingsClient")).Group("Effects")
	s.Parent = parent
	return s
end

local function ensureFolders()
	if not flat then
		flat = Instance.new("Folder")
		flat.Name = "NCSounds"
		flat.Parent = SoundService
	end
	if not anchorPart or not anchorPart.Parent then
		anchorPart = Instance.new("Part")
		anchorPart.Name = "NCSoundAnchor"
		anchorPart.Anchored = true
		anchorPart.CanCollide = false
		anchorPart.CanQuery = false
		anchorPart.CanTouch = false
		anchorPart.Transparency = 1
		anchorPart.Size = Vector3.new(1, 1, 1)
		anchorPart.CFrame = CFrame.new()
		anchorPart.Parent = Workspace.CurrentCamera
	end
end

function SoundClient.Play(name, where, volumeScale)
	ensureFolders()
	local parent = flat
	if typeof(where) == "Vector3" then
		local att = Instance.new("Attachment")
		att.WorldPosition = where
		att.Parent = anchorPart
		parent = att
	elseif typeof(where) == "Instance" and where:IsA("BasePart") then
		parent = where
	end
	local s = newSound(name, parent)
	if not s then
		return nil
	end
	s.Looped = false
	if volumeScale then
		s.Volume *= volumeScale
	end
	s:Play()
	task.delay(12, function()
		s:Destroy()
		if parent ~= flat and parent ~= where and parent.Parent then
			parent:Destroy()
		end
	end)
	return s
end

------------------------------------------------------------------ cars: engines, sirens, horns

local tracked = setmetatable({}, { __mode = "k" }) -- [car] = { engine, siren, honkConn }

local function trackCar(car)
	local chassis = car.PrimaryPart
	if tracked[car] or not chassis then
		return
	end
	local rec = {}
	rec.engine = newSound("EngineLoop", chassis)
	if car:GetAttribute("Police") then
		rec.siren = newSound("Siren", chassis)
		if rec.siren then
			rec.siren.RollOffMaxDistance = 700
		end
	end
	rec.honkConn = car:GetAttributeChangedSignal("HonkAt"):Connect(function()
		SoundClient.Play("Horn", chassis)
	end)
	tracked[car] = rec
end

local function updateCars()
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return
	end
	for _, car in ipairs(vehicles:GetChildren()) do
		if car:IsA("Model") and car.PrimaryPart then
			trackCar(car)
		end
	end
end

local function carAudio()
	local camPos = Workspace.CurrentCamera.CFrame.Position
	for car, rec in pairs(tracked) do
		local chassis = car.PrimaryPart
		if not car.Parent or not chassis then
			if rec.honkConn then
				rec.honkConn:Disconnect()
			end
			tracked[car] = nil
			continue
		end
		local driven = car:GetAttribute("DriverUserId") ~= nil or car:GetAttribute("AIPolice") == true
		local speed = chassis.AssemblyLinearVelocity.Magnitude
		local maxSpeed = car:GetAttribute("MaxSpeed") or 150
		if rec.engine then
			-- Too far away to hear: don't keep the loop running.
			local audible = (chassis.Position - camPos).Magnitude < rec.engine.RollOffMaxDistance
			if driven and audible then
				rec.engine.PlaybackSpeed = 0.75 + 0.85 * math.min(speed / maxSpeed, 1.2)
				rec.engine.Volume = (effect("EngineLoop").Volume or 0.5) * (0.55 + 0.45 * math.min(speed / maxSpeed, 1))
				if not rec.engine.IsPlaying then
					rec.engine:Play()
				end
			elseif rec.engine.IsPlaying then
				rec.engine:Stop()
			end
		end
		if rec.siren then
			local on = car:GetAttribute("Siren") == true or (car:GetAttribute("AIPolice") == true and car:GetAttribute("AITarget") ~= nil)
			on = on and (chassis.Position - camPos).Magnitude < rec.siren.RollOffMaxDistance
			if on and not rec.siren.IsPlaying then
				rec.siren:Play()
			elseif not on and rec.siren.IsPlaying then
				rec.siren:Stop()
			end
		end
	end
end

------------------------------------------------------------------ your own car

local skid, lastNitro, lastSeat, sankFor = nil, false, nil, 0

local function ownCarAudio(dt)
	local DriveController = require(script.Parent.DriveController)
	local status = DriveController.Status
	local car = status.Driving and status.Car
	local chassis = car and car.PrimaryPart
	-- Tyre squeal: sliding sideways at speed.
	local sliding = false
	if chassis then
		local vel = chassis.AssemblyLinearVelocity
		local side = math.abs(vel:Dot(chassis.CFrame.RightVector))
		sliding = side > 16 and vel.Magnitude > 25
	end
	if sliding then
		if not skid then
			skid = newSound("Skid", chassis)
			if skid then
				skid:Play()
			end
		end
	elseif skid then
		skid:Destroy()
		skid = nil
	end
	-- Nitro whoosh on the rising edge.
	if status.NitroActive and not lastNitro and chassis then
		SoundClient.Play("Nitro", chassis)
	end
	lastNitro = status.NitroActive
	-- Door thunk getting in or out.
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat ~= lastSeat and (seat and seat.Name == "DriverSeat" or lastSeat and lastSeat.Name == "DriverSeat") then
		SoundClient.Play("Door", (seat or lastSeat))
	end
	lastSeat = seat
	-- Splash when your car hits the water (boats sit in it all the time).
	if chassis and chassis.Position.Y < 0.5 and not car:GetAttribute("Boat") then
		sankFor += dt
		if sankFor > 0 and sankFor - dt <= 0 then
			SoundClient.Play("Splash", chassis.Position)
		end
	else
		sankFor = 0
	end
end

------------------------------------------------------------------ heist alarms

local alarms = {} -- [site] = sound

local function updateAlarms()
	local sites = Workspace:FindFirstChild("Heists")
	if not sites then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for _, site in ipairs(sites:GetChildren()) do
		local ringing = (site:GetAttribute("AlarmUntil") or 0) > now
		local s = alarms[site]
		if ringing and not s then
			local part = site:IsA("Model") and (site.PrimaryPart or site:FindFirstChildWhichIsA("BasePart", true)) or site
			if part and part:IsA("BasePart") then
				s = newSound("Alarm", part)
				if s then
					s.RollOffMaxDistance = 500
					s:Play()
					alarms[site] = s
				end
			end
		elseif not ringing and s then
			s:Destroy()
			alarms[site] = nil
		end
	end
end

------------------------------------------------------------------ weather and ambience

local rain, waves, city
local nextGull = 0
local district -- DistrictClient's key for where you are (nil until it knows)
-- Per district: how much city hum and surf to mix in (on top of the beach-distance surf).
local DISTRICT_MIX = {
	SolanaHeights = { city = 1, surf = 0 },
	PalmHills = { city = 0.55, surf = 0 },
	RustwaterDocks = { city = 0.7, surf = 0.15 },
	MarinaRow = { city = 0.45, surf = 0.35 },
	FlamingoBeach = { city = 0.2, surf = 0 },
	GatorGlades = { city = 0, surf = 0 },
	SaltmarshIsland = { city = 0.05, surf = 0.2 },
	LighthouseKey = { city = 0, surf = 0.6 },
}
local mix = { city = 0, surf = 0 }

function SoundClient.SetDistrict(key)
	district = key
end

local function setLoop(sound, volume)
	sound.Volume = volume
	if volume > 0.01 and not sound.IsPlaying then
		sound:Play()
	elseif volume <= 0.01 and sound.IsPlaying then
		sound:Stop()
	end
end

local function ambience()
	local cam = Workspace.CurrentCamera.CFrame.Position
	-- Rain
	local raining = Workspace:GetAttribute("Raining") == true
	if raining and not rain.IsPlaying then
		rain:Play()
	elseif not raining and rain.IsPlaying then
		rain:Stop()
	end
	-- Surf: strongest on the beach (x 1100-1600) and Lighthouse Key, fading inland.
	local beach = math.clamp((cam.X - 950) / 350, 0, 1)
	if cam.Z > 800 or cam.Z < -2000 then
		beach *= 0.3
	end
	-- City hum within ~700 studs of downtown, or by district once DistrictClient knows where you are.
	local d = (Vector3.new(cam.X, 0, cam.Z) - Vector3.new(0, 0, -250)).Magnitude
	local c = math.clamp(1 - (d - 300) / 400, 0, 1)
	local m = district and DISTRICT_MIX[district]
	if m then
		c = math.max(m.city, c * 0.5)
		beach = math.max(beach, m.surf)
	end
	-- Ease between mixes so district borders don't jump.
	mix.city += (c - mix.city) * 0.35
	mix.surf += (beach - mix.surf) * 0.35
	setLoop(waves, (effect("Waves").Volume or 0.4) * mix.surf)
	if mix.surf > 0.5 and os.clock() > nextGull then
		nextGull = os.clock() + math.random(14, 30)
		SoundClient.Play("Seagulls", nil, 0.7)
	end
	setLoop(city, (effect("CityAmbience").Volume or 0.25) * mix.city)
end

------------------------------------------------------------------ event music (EventService)

local music = {} -- [part] = sound
local musicParts = {} -- [part] = true: Workspace.Events parts with a MusicId (kept by signals, never rescanned)
local watchedEvents

local function watchEvents()
	local events = Workspace:FindFirstChild("Events")
	if not events or events == watchedEvents then
		return
	end
	watchedEvents = events
	local function consider(d)
		if d:IsA("BasePart") and d:GetAttribute("MusicId") ~= nil then
			musicParts[d] = true
		end
	end
	for _, d in ipairs(events:GetDescendants()) do
		consider(d)
	end
	events.DescendantAdded:Connect(consider)
	events.DescendantRemoving:Connect(function(d)
		musicParts[d] = nil
	end)
end

local function updateMusic()
	for part, sound in pairs(music) do
		if not part.Parent or not sound.Parent or part:GetAttribute("MusicId") == nil then
			sound:Destroy()
			music[part] = nil
		end
	end
	watchEvents()
	for d in pairs(musicParts) do
		local id = d.Parent and d:GetAttribute("MusicId")
		if type(id) == "number" and not music[d] then
			local s = Instance.new("Sound")
			s.Name = "EventMusic"
			s.SoundId = "rbxassetid://" .. id
			s.Looped = true
			s.Volume = 0.5
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = 30
			s.RollOffMaxDistance = 220
			s.SoundGroup = require(script.Parent:WaitForChild("SettingsClient")).Group("Music")
			s.Parent = d
			s:Play()
			music[d] = s
		end
	end
end

------------------------------------------------------------------ radio

local radio, radioPill
local station = 1 -- index into Sounds.Radio; #Sounds.Radio + 1 = off
local trackIndex = {}

local function stationName()
	local s = Sounds.Radio[station]
	return s and s.Name or "RADIO OFF"
end

local function playStation()
	local s = Sounds.Radio[station]
	if not s or #s.Tracks == 0 then
		radio:Stop()
		return
	end
	trackIndex[station] = ((trackIndex[station] or math.random(#s.Tracks)) % #s.Tracks) + 1
	local t = s.Tracks[trackIndex[station]]
	radio.SoundId = "rbxassetid://" .. t.Id
	radio.TimePosition = 0
	radio:Play()
	radioPill.Text = "📻 " .. string.upper(s.Name) .. "  ·  " .. t.Name
end

local function nextStation()
	station = station % (#Sounds.Radio + 1) + 1
	SoundClient.Play("Click")
	if Sounds.Radio[station] then
		playStation()
	else
		radio:Stop()
		radioPill.Text = "📻 RADIO OFF"
	end
end

local function buildRadio()
	radio = Instance.new("Sound")
	radio.Name = "Radio"
	radio.Volume = 0.35
	radio.SoundGroup = require(script.Parent:WaitForChild("SettingsClient")).Group("Music")
	radio.Parent = flat
	radio.Ended:Connect(function()
		if Sounds.Radio[station] then
			playStation()
		end
	end)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Radio"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	radioPill = Instance.new("TextButton")
	radioPill.Name = "RadioPill"
	radioPill.AnchorPoint = Vector2.new(0.5, 1)
	radioPill.Position = UDim2.new(0.5, 0, 1, -104) -- above the speed gauge, clear of the steering thumb
	radioPill.Size = UDim2.fromOffset(230, 28)
	radioPill.BackgroundColor3 = DARK
	radioPill.BackgroundTransparency = 0.25
	radioPill.Font = FONT
	radioPill.TextScaled = true
	radioPill.TextColor3 = PINK
	radioPill.TextXAlignment = Enum.TextXAlignment.Center
	radioPill.Visible = false
	radioPill.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = radioPill
	local p = Instance.new("UIPadding")
	p.PaddingLeft, p.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	p.PaddingTop, p.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)
	p.Parent = radioPill
	radioPill.Activated:Connect(nextStation)
end

local wasDriving = false
local function updateRadio()
	local DriveController = require(script.Parent.DriveController)
	local driving = DriveController.Status.Driving
	if driving ~= wasDriving then
		wasDriving = driving
		radioPill.Visible = driving
		if driving and Sounds.Radio[station] then
			playStation()
		elseif not driving then
			radio:Stop()
		end
		if driving and not Sounds.Radio[station] then
			radioPill.Text = "📻 RADIO OFF"
		end
	end
end

------------------------------------------------------------------ init

function SoundClient.Init()
	ensureFolders()
	rain = newSound("Rain", flat)
	waves = newSound("Waves", flat)
	city = newSound("CityAmbience", flat)
	buildRadio()

	-- Moments from the server. Each remote is hooked up in its own thread: WaitForChild on a remote
	-- the server hasn't made yet must never hold up the other controllers.
	local function on(name, fn)
		task.spawn(function()
			Remotes.Event(name).OnClientEvent:Connect(fn)
		end)
	end
	local function cash()
		SoundClient.Play("Cash")
	end
	on("Banked", cash)
	on("BountyEarned", cash)
	on("CashPackGranted", cash)
	on("DailyReward", cash)
	on("HeistResult", cash)
	on("Caught", function()
		SoundClient.Play("Cuffs")
	end)
	on("TaserFx", function(_, target)
		local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if root then -- far-away (streamed-out) tasers stay silent
			SoundClient.Play("Zap", root)
		end
	end)
	on("RaceEvent", function(kind)
		if kind == "Countdown" then
			SoundClient.Play("Countdown")
		elseif kind == "Checkpoint" then
			SoundClient.Play("Checkpoint")
		elseif kind == "Finished" then
			SoundClient.Play("Success")
		end
	end)
	on("Notify", function(key)
		if key == "CarSank" then
			SoundClient.Play("Splash")
		end
	end)
	for _, name in ipairs({ "TutorialDone", "PassGranted", "GarageResult" }) do
		on(name, function()
			SoundClient.Play("Success")
		end)
	end

	-- H: horn for civilians, siren toggle for cops (the server checks and replicates).
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.H then
			Remotes.Event("RequestHorn"):FireServer()
		elseif input.KeyCode == Enum.KeyCode.V then
			if wasDriving then
				nextStation()
			end
		end
	end)

	local lastScan = 0
	RunService.Heartbeat:Connect(function(dt)
		if os.clock() - lastScan > 0.5 then
			lastScan = os.clock()
			updateCars()
			updateAlarms()
			ambience()
			updateMusic()
		end
		carAudio()
		ownCarAudio(dt)
		updateRadio()
	end)
end

return SoundClient
