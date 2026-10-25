-- VehicleVisuals (ModuleScript, StarterPlayerScripts.Controllers.VehicleVisuals)
-- Local-only looks for the cars around the camera (everything here is made on this device):
--   * Wheels of cars this player is NOT driving spin and follow the road (DriveController animates
--     your own). Parked cars skip their wheel rays; beyond 160 studs wheels spin without rays.
--   * Damage: light smoke once a car's Health is below 35, darker smoke with sparks below 15, and a
--     crash sound when a nearby car (not your own: DriveController) takes a hit.
--   * Police light bars flash while the siren is on (or while an AI patrol chases someone), also on
--     the parked cars of police roadblocks (Workspace.Roadblocks).
--   * Brake lights brighten while a car slows down hard.
--   * Prompts: "Drive" only on your own car (or the hot car you stole) while it's empty; "Ride" for the
--     owner's crewmates and Roblox friends on the same side (never prisoners) while any passenger seat
--     is free (both local-only toggles; VehicleService checks again). Friendship is looked up once per
--     player in the background (Player:IsFriendsWith yields), never inside the prompt loop.
--   Getting out (F / EXIT) is DriveController's, for drivers and passengers alike.
-- Cheap on purpose: cars within 350 studs, at most 30 updates a second, each car's parts looked up
-- once, one shared ray filter, prompts 10 times a second.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local VehicleVisuals = {}

local WHEELS = { "FL", "FR", "RL", "RR" }
local RANGE = 350
local RAY_RANGE = 160 -- beyond this, wheels spin at their rest height (no rays)
local SOUND_RANGE = 220
local STEP = 1 / 30
local PROMPT_STEP = 0.1
local SMOKE_HEALTH, HEAVY_HEALTH = 35, 15
local BRAKE_DECEL = 30 -- studs/s^2 of slowing that lights the brake lights
local BRAKE_HOLD = 0.25 -- seconds they stay lit (no flicker)
local FLASH_RATE = 6 -- light bar swaps per second
local TAIL_RUN = Color3.fromRGB(205, 28, 44)
local TAIL_BRAKE = Color3.fromRGB(255, 85, 100)
local BAR_COLORS = { LightBarRed = Color3.fromRGB(255, 40, 60), LightBarBlue = Color3.fromRGB(40, 120, 255) }
local BLACK = Color3.new(0, 0, 0)

-- [car] = cached parts and visual state. Records never reference the car itself (weak keys).
local cache = setmetatable({}, { __mode = "k" })
local accum, promptAccum = 0, 0

-- [userId] = true / false once known (nil = not asked yet, false while the lookup runs).
local friendOf = {}
local function isFriend(userId)
	local known = friendOf[userId]
	if known == nil then
		friendOf[userId] = false
		task.spawn(function()
			local ok, res = pcall(player.IsFriendsWith, player, userId)
			if ok then
				friendOf[userId] = res == true
			else
				task.delay(30, function()
					if friendOf[userId] == false then
						friendOf[userId] = nil -- the web call failed: ask again later
					end
				end)
			end
		end)
		return false
	end
	return known
end

-- One shared filter for every wheel ray: cars and smoke clouds never hold a wheel up.
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
local function refreshFilter()
	params.FilterDescendantsInstances = { Workspace:FindFirstChild("Vehicles"), Workspace:FindFirstChild("Smoke") }
end

-- Look up a car's parts once (again after a second if some hadn't streamed in yet).
local function partsOf(car, now)
	local chassis = car.PrimaryPart
	if not chassis then
		return nil
	end
	local rec = cache[car]
	if rec and rec.chassis == chassis and (rec.complete or now < rec.retryAt) then
		return rec
	end
	rec = rec or { spin = 0, settled = false, brakeOn = nil, brakeUntil = 0, flash = nil, smoke = nil }
	rec.chassis = chassis
	local seat = car:FindFirstChild("DriverSeat")
	local pseat = car:FindFirstChild("PassengerSeat")
	rec.seat, rec.pseat = seat, pseat
	rec.prompt = seat and seat:FindFirstChild("DrivePrompt")
	rec.ride = pseat and pseat:FindFirstChild("RidePrompt")
	rec.pseats = {}
	for _, d in ipairs(car:GetChildren()) do
		if d:IsA("Seat") and (d:GetAttribute("Passenger") or d.Name == "PassengerSeat") then
			table.insert(rec.pseats, d)
		end
	end
	rec.rest = car:GetAttribute("RestLength") or 1.4
	rec.radius = car:GetAttribute("WheelRadius") or 1.2
	local complete = seat ~= nil
	rec.wheels = {}
	for _, name in ipairs(WHEELS) do
		local att = chassis:FindFirstChild("Wheel" .. name)
		local wheel = car:FindFirstChild("Wheel" .. name)
		local hub = wheel and wheel:FindFirstChild("Hub")
		if att and att:IsA("Attachment") and hub and hub:IsA("Motor6D") and wheel:IsA("BasePart") then
			table.insert(rec.wheels, {
				att = att,
				hub = hub,
				attY = att.Position.Y,
				r = wheel.Size.Y / 2, -- the visual wheel's own radius (mesh bodies differ from the physics one)
				baseY = (wheel:GetAttribute("Offset") or hub.C0.Position).Y,
			})
		elseif not car:GetAttribute("Boat") then
			complete = false
		end
	end
	rec.tails, rec.bars = {}, {}
	for _, d in ipairs(car:GetChildren()) do
		if d:IsA("BasePart") then
			if d.Name == "Taillight" and d.Transparency < 1 then
				table.insert(rec.tails, d)
			elseif BAR_COLORS[d.Name] then
				table.insert(rec.bars, d)
			end
		end
	end
	rec.brakeOn, rec.flash = nil, nil -- repaint the new parts
	rec.complete = complete
	rec.retryAt = now + 1
	cache[car] = rec
	return rec
end

local function updatePrompts(car, rec)
	local prompt = rec.prompt
	if prompt and prompt.Parent then
		local mine = car:GetAttribute("OwnerUserId") == player.UserId or car:GetAttribute("ThiefUserId") == player.UserId
		local show = rec.seat.Occupant == nil and mine
		if prompt.Enabled ~= show then
			prompt.Enabled = show
		end
	end
	local ride = rec.ride
	if ride and ride.Parent then
		local owner = Players:GetPlayerByUserId(car:GetAttribute("OwnerUserId") or 0)
		local show = false
		local me = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if owner and owner ~= player and me and me.SeatPart == nil then
			local side = player:GetAttribute("Side")
			local crew = player:GetAttribute("Crew")
			if side ~= "Prisoner" and side == owner:GetAttribute("Side")
				and ((crew ~= nil and owner:GetAttribute("Crew") == crew) or isFriend(owner.UserId)) then
				for _, s in ipairs(rec.pseats) do
					if s.Occupant == nil and not s:GetAttribute("NPCRider") then
						show = true
						break
					end
				end
			end
		end
		if ride.Enabled ~= show then
			ride.Enabled = show
		end
	end
end

local function animateWheels(rec, dt, dist, vel)
	local chassis = rec.chassis
	local moving = vel.Magnitude > 0.3 or chassis.AssemblyAngularVelocity.Magnitude > 0.3
	local useRays = dist <= RAY_RANGE
	-- Parked: one last update (with rays once it's close enough), then nothing until it moves.
	if not moving and rec.settled and (rec.settledRays or not useRays) then
		return
	end
	rec.settled, rec.settledRays = not moving, useRays
	local cf = chassis.CFrame
	local fwd = vel:Dot(cf.LookVector)
	rec.spin = (rec.spin + fwd / rec.radius * dt) % (math.pi * 2)
	local spinCf = CFrame.Angles(-rec.spin, 0, 0)
	local reach = rec.rest + rec.radius
	local down = -cf.UpVector * reach
	for _, w in ipairs(rec.wheels) do
		local drop = reach - w.r
		if useRays then
			local hit = Workspace:Raycast(w.att.WorldPosition, down, params)
			if hit then
				drop = hit.Distance - w.r
			end
		end
		w.hub.Transform = CFrame.new(0, (w.attY - drop) - w.baseY, 0) * spinCf
	end
end

local function updateBrakeLights(rec, fwdSpeed, dt, now)
	local last = rec.lastFwd
	rec.lastFwd = fwdSpeed
	if #rec.tails == 0 or not last then
		return
	end
	local decel = (last - fwdSpeed) / dt
	rec.decel = (rec.decel or 0) + (decel - (rec.decel or 0)) * 0.5 -- smooth out replication jitter
	if fwdSpeed > 3 and rec.decel > BRAKE_DECEL then
		rec.brakeUntil = now + BRAKE_HOLD
	end
	local on = now < rec.brakeUntil
	if on ~= rec.brakeOn then
		rec.brakeOn = on
		for _, t in ipairs(rec.tails) do
			t.Color = on and TAIL_BRAKE or TAIL_RUN
		end
	end
end

local function updateLightBars(car, rec, now)
	if #rec.bars == 0 then
		return
	end
	local on = car:GetAttribute("Siren") == true or (car:GetAttribute("AIPolice") == true and car:GetAttribute("AITarget") ~= nil)
	local phase = on and math.floor(now * FLASH_RATE) % 2 or -1
	if phase == rec.flash then
		return
	end
	rec.flash = phase
	for _, bar in ipairs(rec.bars) do
		local base = BAR_COLORS[bar.Name]
		local lit = phase == -1 or (phase == 0) == (bar.Name == "LightBarRed")
		bar.Color = lit and base or base:Lerp(BLACK, 0.8)
	end
end

-- Smoke over the bonnet (made the first time a car needs it; rates stay at 8 or less).
local function ensureEmitters(rec)
	if rec.smokeEmitter and rec.smokeEmitter.Parent then
		return
	end
	local size = rec.chassis.Size
	local att = Instance.new("Attachment")
	att.Name = "NCDamageFx"
	att.Position = Vector3.new(0, size.Y / 2 + 0.4, -size.Z / 2 + 2.2)
	att.Parent = rec.chassis
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "DamageSmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Rate = 5
	smoke.Lifetime = NumberRange.new(1.4, 2.4)
	smoke.Speed = NumberRange.new(3, 6)
	smoke.SpreadAngle = Vector2.new(20, 20)
	smoke.Acceleration = Vector3.new(0, 3, 0)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.5) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	smoke.Enabled = false
	smoke.Parent = att
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "DamageSparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Rate = 4
	sparks.Lifetime = NumberRange.new(0.25, 0.45)
	sparks.Speed = NumberRange.new(8, 14)
	sparks.SpreadAngle = Vector2.new(45, 45)
	sparks.Acceleration = Vector3.new(0, -40, 0)
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 214, 120), Color3.fromRGB(255, 138, 61))
	sparks.LightEmission = 1
	sparks.Enabled = false
	sparks.Parent = att
	rec.smokeEmitter, rec.sparkEmitter = smoke, sparks
end

local function setSmoke(rec, level)
	if level == rec.smoke then
		return
	end
	rec.smoke = level
	if level and level > 0 then
		ensureEmitters(rec)
	end
	local smoke, sparks = rec.smokeEmitter, rec.sparkEmitter
	if smoke and sparks then
		smoke.Enabled = level ~= nil and level > 0
		smoke.Rate = level == 2 and 8 or 5
		smoke.Color = ColorSequence.new(level == 2 and Color3.fromRGB(55, 55, 60) or Color3.fromRGB(205, 205, 210))
		sparks.Enabled = level == 2
	end
end

local function playCrash(chassis, scale)
	pcall(function()
		require(script.Parent.SoundClient).Play("Crash", chassis, scale)
	end)
end

-- A roadblock's parked police car (no seats or wheels to animate): just its light bars. Its parts
-- stream in by distance, so look for them again while none are found.
local function visitShell(shell, camPos, now)
	local rec = cache[shell]
	local first = rec and rec.bars[1]
	if not rec or (first and not first:IsDescendantOf(shell)) or (not first and now >= rec.retryAt) then
		rec = rec or {}
		rec.bars = {}
		for _, d in ipairs(shell:GetChildren()) do
			if d:IsA("BasePart") and BAR_COLORS[d.Name] then
				table.insert(rec.bars, d)
			end
		end
		rec.retryAt, rec.flash = now + 1, nil
		cache[shell] = rec
		first = rec.bars[1]
	end
	if first and (first.Position - camPos).Magnitude <= RANGE then
		updateLightBars(shell, rec, now)
	end
end

local function visit(car, dt, camPos, now, doPrompts, myChar)
	local rec = partsOf(car, now)
	if not rec then
		return
	end
	if doPrompts then
		updatePrompts(car, rec)
	end
	local chassis = rec.chassis
	local health = car:GetAttribute("Health") or 100
	local lastHealth = rec.health
	rec.health = health
	local dist = (chassis.Position - camPos).Magnitude
	if dist > RANGE then
		setSmoke(rec, nil) -- out of sight: no particles
		rec.lastFwd = nil
		return
	end
	local occupant = rec.seat and rec.seat.Occupant
	local driving = occupant ~= nil and myChar ~= nil and occupant.Parent == myChar
	local vel = chassis.AssemblyLinearVelocity
	updateBrakeLights(rec, vel:Dot(chassis.CFrame.LookVector), dt, now)
	updateLightBars(car, rec, now)
	setSmoke(rec, health < HEAVY_HEALTH and 2 or (health < SMOKE_HEALTH and 1 or 0))
	-- Someone else's car just took a hit: let it be heard (your own crashes: DriveController).
	if lastHealth and health < lastHealth - 2 and not driving and dist < SOUND_RANGE then
		playCrash(chassis, math.clamp((lastHealth - health) / 30, 0.3, 1))
	end
	if not driving then
		animateWheels(rec, dt, dist, vel)
	end
end

function VehicleVisuals.Init()
	Players.PlayerRemoving:Connect(function(p)
		friendOf[p.UserId] = nil
	end)
	refreshFilter()
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Smoke" or child.Name == "Vehicles" then
			refreshFilter()
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		accum += dt
		if accum < STEP then
			return
		end
		local step = math.min(accum, 0.25)
		accum = 0
		promptAccum += step
		local doPrompts = promptAccum >= PROMPT_STEP
		if doPrompts then
			promptAccum = 0
		end
		local folder = Workspace:FindFirstChild("Vehicles")
		if not folder then
			return
		end
		local camPos = Workspace.CurrentCamera.CFrame.Position
		local now = os.clock()
		local myChar = player.Character
		for _, car in ipairs(folder:GetChildren()) do
			local ok, err = pcall(visit, car, step, camPos, now, doPrompts, myChar)
			if not ok then
				warn("[VehicleVisuals] " .. tostring(err))
			end
		end
		local blocks = Workspace:FindFirstChild("Roadblocks")
		if blocks then
			for _, block in ipairs(blocks:GetChildren()) do
				for _, shell in ipairs(block:GetChildren()) do
					if shell:IsA("Model") and shell:GetAttribute("Siren") ~= nil then
						local ok, err = pcall(visitShell, shell, camPos, now)
						if not ok then
							warn("[VehicleVisuals] " .. tostring(err))
						end
					end
				end
			end
		end
	end)
end

return VehicleVisuals
