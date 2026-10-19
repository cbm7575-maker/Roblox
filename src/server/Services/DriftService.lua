-- DriftService (ModuleScript, ServerScriptService.Services.DriftService)
-- The drift zone on Lighthouse Key (part Workspace.Activities.DriftZone).
-- Scored on the server 10 times a second while you drive inside the zone:
--   * Drifting = moving over 30 studs/s with the car sliding 15-80 degrees off its nose.
--   * Points += 10 x speed x sin(slide angle) x combo multiplier per second; the multiplier climbs
--     x1 -> x5 the longer you keep drifting (a clean 3 s drift is roughly 900 points, about $36).
--   * The chain ends after 0.8 s without drifting, leaving the zone, or a big crash (lost 40% speed):
--     you're paid $1 per PointsPerDollar points, at most MaxChainPay a chain; the XP is capped the same
--     way (the score sent to ProgressService never exceeds what the cash cap pays for). Best chain is saved.
--   * Daily allowance (Config.Activities.Drift): the first DailyFull dollars each UTC day pay in full,
--     then AfterShare of the cash and XP (saved in data.flags.driftDay = { day, paid }).
--   * Circling on the spot (handbrake donuts: every position of the last CircleSeconds within
--     CircleRadius studs) scores nothing, so holding gas + handbrake + full lock can't farm.
-- The client shows DriftScore / DriftCombo (player attributes); DriftEvent { Score, Pay, Best, Reason,
-- Reduced } when a chain is paid (Reduced = part of it was past today's full-pay allowance).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Activities = require(ReplicatedStorage.Shared.Config.Activities)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local DataService = require(ServerScriptService.Services.DataService)
local DailyService = require(ServerScriptService.Services.DailyService)

local DriftService = {}

local CFG = Activities.Drift
local TICK = 0.1
local MIN_SPEED = 30
local MIN_ANGLE, MAX_ANGLE = math.rad(15), math.rad(80)
local BREAK_AFTER = 0.8
local SAMPLE_EVERY = 0.5 -- seconds between position samples for the circling check

local chains = {} -- [player] = { score, combo, driftTime, idle, lastSpeed }
local trails = {} -- [player] = { list = { Vector3 }, at = os.clock() of the last sample }
local driftEvent

local function inZone(zone, pos)
	local rel = zone.CFrame:PointToObjectSpace(pos)
	return math.abs(rel.X) <= zone.Size.X / 2 and math.abs(rel.Z) <= zone.Size.Z / 2 and rel.Y < 20 and rel.Y > -5
end

-- Split a chain's full pay into what today's allowance pays in full and the reduced rest.
-- Returns the cash to pay and how much of the full-rate allowance it used.
function DriftService.Split(full, paidToday)
	local room = math.max(0, CFG.DailyFull - paidToday)
	local fullPart = math.min(full, room)
	local rest = full - fullPart
	return fullPart + math.floor(rest * CFG.AfterShare), fullPart
end

-- Remember where the car has been while moving fast (one sample every SAMPLE_EVERY s, kept for
-- CircleSeconds) and say whether it's circling on the spot: at least ~4 s of fast samples in the
-- window, all within CircleRadius of their middle. Parked or slow time adds no samples (old ones just
-- expire), so stopping in the zone never blocks a real drift.
local function circling(player, pos, fast)
	local tr = trails[player]
	if not tr then
		tr = { list = {}, at = 0, circling = false }
		trails[player] = tr
	end
	local t = os.clock()
	if t - tr.at < SAMPLE_EVERY then
		return tr.circling
	end
	tr.at = t
	local list = tr.list
	while list[1] and t - list[1].t > CFG.CircleSeconds do
		table.remove(list, 1)
	end
	if fast then
		table.insert(list, { p = Vector3.new(pos.X, 0, pos.Z), t = t })
	end
	tr.circling = false
	local n = #list
	if n >= math.ceil(0.6 * CFG.CircleSeconds / SAMPLE_EVERY) then
		local mid = Vector3.zero
		for _, s in ipairs(list) do
			mid += s.p
		end
		mid /= n
		tr.circling = true
		for _, s in ipairs(list) do
			if (s.p - mid).Magnitude > CFG.CircleRadius then
				tr.circling = false
				break
			end
		end
	end
	return tr.circling
end

local function bank(player, c, reason)
	chains[player] = nil
	player:SetAttribute("DriftScore", nil)
	player:SetAttribute("DriftCombo", nil)
	local score = math.floor(c.score)
	if score < 100 then
		return
	end
	-- Cash and XP are capped by the same chain limit.
	local cappedScore = math.min(score, CFG.MaxChainPay * CFG.PointsPerDollar)
	local full = math.floor(cappedScore / CFG.PointsPerDollar)
	local pay, scale = full, 1
	local data = DataService.Get(player)
	local best = false
	if data then
		local day = DailyService.DayRecord(data, "driftDay")
		local paid = type(day.paid) == "number" and day.paid or 0
		local used
		pay, used = DriftService.Split(full, paid)
		day.paid = paid + used
		scale = full > 0 and pay / full or 1
		data.drift = data.drift or 0
		if score > data.drift then
			data.drift = score
			best = true
		end
	end
	EconomyService.AddCash(player, pay, "drift")
	require(ServerScriptService.Services.ProgressService).Event(player, "Drift", cappedScore, scale)
	driftEvent:FireClient(player, { Score = score, Pay = pay, Best = best, Reason = reason, Reduced = pay < full })
end

local function tick(zone)
	for _, player in ipairs(Players:GetPlayers()) do
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local car = hum and hum.SeatPart and hum.SeatPart.Name == "DriverSeat" and hum.SeatPart.Parent -- drivers only (not passengers)
		local chassis = car and car.PrimaryPart
		local c = chains[player]
		if not chassis or not car:GetAttribute("NCVehicle") or not inZone(zone, chassis.Position) then
			-- The circling trail is kept (its samples expire on their own), so circling across the
			-- zone's edge can't reset it.
			if c then
				bank(player, c, "left")
			end
		else
			local vel = chassis.AssemblyLinearVelocity
			local flatVel = Vector3.new(vel.X, 0, vel.Z)
			local speed = flatVel.Magnitude
			local look = Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z)
			local angle = 0
			if speed > 1 and look.Magnitude > 0.1 then
				angle = math.acos(math.clamp(flatVel.Unit:Dot(look.Unit), -1, 1))
			end
			-- Donuts on the spot don't count as drifting (the trail spans chains, so restarting doesn't help).
			local spinning = circling(player, chassis.Position, speed > MIN_SPEED)
			local drifting = speed > MIN_SPEED and angle >= MIN_ANGLE and angle <= MAX_ANGLE and not spinning
			if drifting then
				c = c or { score = 0, combo = 1, driftTime = 0, idle = 0, lastSpeed = speed }
				chains[player] = c
				-- A big crash ends the chain.
				if speed < c.lastSpeed * 0.6 and c.lastSpeed > 60 then
					bank(player, c, "crash")
				else
					c.idle = 0
					c.driftTime += TICK
					c.combo = math.min(5, 1 + math.floor(c.driftTime / 2))
					c.score += speed * math.sin(angle) * TICK * c.combo * 10
					c.lastSpeed = speed
					player:SetAttribute("DriftScore", math.floor(c.score))
					player:SetAttribute("DriftCombo", c.combo)
				end
			elseif c then
				c.idle += TICK
				c.lastSpeed = speed
				if c.idle >= BREAK_AFTER then
					bank(player, c, "ended")
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
			task.wait(TICK)
			local ok, err = pcall(tick, zone)
			if not ok then
				warn("[DriftService] " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		chains[p] = nil
		trails[p] = nil
	end)
end

return DriftService
