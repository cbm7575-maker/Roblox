-- DriftService (ModuleScript, ServerScriptService.Services.DriftService)
-- The drift zone on Lighthouse Key (part Workspace.Activities.DriftZone, 190 x 340 studs).
-- How to drift (CarPhysics): steer and tap the handbrake to swing the tail out, then stay on the
-- throttle and keep steering to hold the slide.
-- Scored on the server 10 times a second while you drive inside the zone:
--   * Drifting = moving over 30 studs/s with the car sliding 12-80 degrees off its nose (the same
--     test as CarPhysics' phys.Drifting, so the client's DRIFT tag and the score agree).
--   * Points += speed x sin(slide angle) x combo multiplier per second; the multiplier climbs
--     x1 -> x5 the longer you keep drifting (one more every 2 s). In the starter car a held slide is
--     about 50 points a second at x1: 3 s is ~170 points, 8 s ~900 ($36), 20 s ~3,700 ($150).
--     (It was 10 x that while a drift could only last a second. Now that a slide can be held for as
--     long as you like, the old rate would pay about $2,700 a minute and a rank a minute.)
--   * The chain ends after 0.8 s without drifting, leaving the zone, or a big crash (the car's own
--     velocity fell by 40% in a tick from over 60 studs/s): 50+ points are paid at $1 per 25 points
--     (max $600 a chain). Best chain is saved. The DriftEvent remote tells the client (ActivityClient
--     stamps "DRIFT!" with the points and the cash; Reason "left" / "ended" / "crash" / "max").
--   * A chain is full at 15,000 points ($600; about 70 s of unbroken sliding in the starter car, 45 s in
--     the fastest): it banks itself there (Reason "max"), and no new chain starts until the driver has
--     driven 0.8 s in a row without drifting. A slide can be held forever, so without this one held
--     donut (or taped-down keys) would send unlimited points to XP, goals and the saved best.
--   * Scoring speed is the car's reported velocity, capped by how far the chassis really moved lately
--     and by the car's top speed with nitro (the driver's device owns the physics, so velocity can be
--     faked). The crash test uses the reported velocity alone: a replication hiccup freezes the
--     measured distance for a moment, which must not read as a crash (and ignoring it gains nothing).
-- Player attributes: DriftScore / DriftCombo while a chain is running (the client shows them), and
-- InDriftZone = true while they are driving a car inside the zone (nil otherwise; the client shows the
-- how-to banner from it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local DataService = require(ServerScriptService.Services.DataService)

local DriftService = {}

local TICK = 0.1
local MIN_SPEED = 30
local MIN_ANGLE, MAX_ANGLE = math.rad(12), math.rad(80)
local POINT_RATE = 1 -- points per second for each stud/s of sideways-ish speed (x combo)
local Activities = require(ReplicatedStorage.Shared.Config.Activities)
local MIN_BANK = Activities.Drift.MinScore -- a chain shorter than this pays nothing (ActivityClient shows the same rule)
local BREAK_AFTER = 0.8
local POINTS_PER_DOLLAR = Activities.Drift.PointsPerDollar
local MAX_PAYOUT = Activities.Drift.MaxPayout
local MAX_CHAIN = MAX_PAYOUT * POINTS_PER_DOLLAR -- 15,000: past this a chain pays nothing more, so it banks here
local WINDOW = 0.3 -- seconds of chassis positions used to measure real speed

local chains = {} -- [player] = { score, combo, driftTime, idle, lastReported }
local rest = {} -- [player] = seconds of not drifting (in a row) still needed after a full chain before a new one
local track = {} -- [player] = { car, samples = { { pos, t } } } recent chassis positions in the zone
local driftEvent

local function inZone(zone, pos)
	local rel = zone.CFrame:PointToObjectSpace(pos)
	return math.abs(rel.X) <= zone.Size.X / 2 and math.abs(rel.Z) <= zone.Size.Z / 2 and rel.Y < 20 and rel.Y > -5
end

local function bank(player, c, reason)
	chains[player] = nil
	player:SetAttribute("DriftScore", nil)
	player:SetAttribute("DriftCombo", nil)
	local score = math.floor(c.score)
	if score < MIN_BANK then
		return
	end
	local pay = math.min(MAX_PAYOUT, math.floor(score / POINTS_PER_DOLLAR))
	EconomyService.AddCash(player, pay, "drift")
	require(game:GetService("ServerScriptService").Services.ProgressService).Event(player, "Drift", score)
	local data = DataService.Get(player)
	local best = false
	if data then
		data.drift = data.drift or 0
		if score > data.drift then
			data.drift = score
			best = true
		end
	end
	driftEvent:FireClient(player, { Score = score, Pay = pay, Best = best, Reason = reason })
end

-- The most speed this car can honestly have: how fast the chassis really moved over the last WINDOW
-- (with a little slack for replication jitter), never above its top speed with nitro.
local function realSpeedCap(player, car, chassis, t)
	local tr = track[player]
	if not tr or tr.car ~= car then
		tr = { car = car, samples = {} }
		track[player] = tr
	end
	local list = tr.samples
	table.insert(list, { pos = chassis.Position, t = t })
	-- Keep the newest sample that is at least WINDOW old as the start of the measurement.
	while #list > 2 and t - list[2].t >= WINDOW do
		table.remove(list, 1)
	end
	local first = list[1]
	local span = t - first.t
	if span < 0.05 then
		return 0 -- just arrived: nothing to measure yet
	end
	local moved = chassis.Position - first.pos
	local measured = Vector3.new(moved.X, 0, moved.Z).Magnitude / span
	if measured ~= measured then
		return 0 -- NaN position
	end
	local top = (car:GetAttribute("MaxSpeed") or 150) * (car:GetAttribute("NitroSpeed") or 1.2)
	return math.min(measured * 1.25 + 8, top)
end

-- InDriftZone = true while this player drives a car inside the zone, nil otherwise (only written
-- when it changes).
local function setInZone(player, inside)
	local value = inside and true or nil
	if player:GetAttribute("InDriftZone") ~= value then
		player:SetAttribute("InDriftZone", value)
	end
end

local function tick(zone, dt)
	local t = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local car = hum and hum.SeatPart and hum.SeatPart.Name == "DriverSeat" and hum.SeatPart.Parent -- drivers only (not passengers)
		local chassis = car and car.PrimaryPart
		local c = chains[player]
		-- (car and chassis are false or nil when the player isn't a driver)
		local inside = chassis and car:GetAttribute("NCVehicle") == true and inZone(zone, chassis.Position) or false
		setInZone(player, inside)
		if not inside then
			track[player] = nil
			rest[player] = nil
			if c then
				bank(player, c, "left")
			end
		else
			local vel = chassis.AssemblyLinearVelocity
			local flatVel = Vector3.new(vel.X, 0, vel.Z)
			-- What the car says about itself: only the crash test trusts it (see the header).
			local reported = flatVel.Magnitude
			if reported ~= reported then
				reported = 0 -- NaN velocity
			end
			local speed = math.min(reported, realSpeedCap(player, car, chassis, t))
			if speed ~= speed then
				speed = 0
			end
			local look = Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z)
			local angle = 0
			if speed > 1 and look.Magnitude > 0.1 then
				angle = math.acos(math.clamp(flatVel.Unit:Dot(look.Unit), -1, 1))
			end
			local drifting = speed > MIN_SPEED and angle >= MIN_ANGLE and angle <= MAX_ANGLE
			if drifting and rest[player] then
				-- Still the slide whose chain just filled up: nothing until they straighten up for a moment.
				rest[player] = BREAK_AFTER
			elseif drifting then
				c = c or { score = 0, combo = 1, driftTime = 0, idle = 0, lastReported = reported }
				chains[player] = c
				-- A big crash ends the chain.
				if reported < c.lastReported * 0.6 and c.lastReported > 60 then
					bank(player, c, "crash")
				else
					c.idle = 0
					c.driftTime += dt
					c.combo = math.min(5, 1 + math.floor(c.driftTime / 2))
					c.score = math.min(MAX_CHAIN, c.score + speed * math.sin(angle) * dt * c.combo * POINT_RATE)
					c.lastReported = reported
					if c.score >= MAX_CHAIN then
						rest[player] = BREAK_AFTER
						bank(player, c, "max")
					else
						player:SetAttribute("DriftScore", math.floor(c.score))
						player:SetAttribute("DriftCombo", c.combo)
					end
				end
			else
				if c then
					c.idle += dt
					c.lastReported = reported
					if c.idle >= BREAK_AFTER then
						bank(player, c, "ended")
					end
				end
				local need = rest[player]
				if need then
					rest[player] = need > dt and need - dt or nil
				end
			end
		end
	end
end

function DriftService.Init()
	driftEvent = Remotes.Event("DriftEvent")
	local zone = Workspace:WaitForChild("Activities"):WaitForChild("DriftZone", 10)
	if not zone then
		warn("[DriftService] no DriftZone")
		return
	end
	task.spawn(function()
		while true do
			local dt = math.min(task.wait(TICK), 0.5) -- real time since the last tick (capped after a hitch)
			local ok, err = pcall(tick, zone, dt)
			if not ok then
				warn("[DriftService] " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		chains[p] = nil
		rest[p] = nil
		track[p] = nil
	end)
end

return DriftService
