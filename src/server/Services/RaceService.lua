-- RaceService (ModuleScript, ServerScriptService.Services.RaceService)
-- Street races as solo time trials (Config.Activities.Races).
--   * Drive onto a race start pad in your own car (not wanted, not on a phone mission or a taxi / courier
--     shift) and press E ("Race"). A refusal says why (Notify). The prompt is the client's word, so the
--     server checks the car really is at the pad (START_REACH) before it moves anything.
--   * Your car is lined up and held (anchored) for a 3-second countdown, then the clock runs. The hold
--     belongs to that one countdown (holds[car]): it ends when the countdown does or when the race is
--     cancelled during it, and an older countdown's timer can never let go of a newer one's car.
--   * Checkpoints must be passed in order, within Config.Activities.CheckRadius studs (or the race's own
--     Radius). The server checks 10 times a second, and tests the whole stretch driven since the last
--     check, so a fast car can't skip through a checkpoint between two checks.
--   * The client draws the way (ActivityClient: guide line, checkpoint rings with chevron signs, turn
--     cues) from the same checkpoint list; it only needs "Countdown" { Id, StartAt } and
--     "Checkpoint" { Index } from here.
--   * Finish: reward + a bonus for beating par; personal bests are saved; the server leaderboard
--     (top 5 per race) lives in ReplicatedStorage attributes "RaceBoard_<Id>" (ActivityClient shows it
--     over each start pad).
--   * Cancelled if you get out, become wanted, lose the car, or take longer than 2.5 x par.
--   * A finish faster than the route could be driven at 1.3 x the car's top speed is rejected.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Activities = require(ReplicatedStorage.Shared.Config.Activities)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local DataService = require(ServerScriptService.Services.DataService)
local VehicleGuard = require(ServerScriptService.Services.VehicleGuard)

local RaceService = {}

local CHECK_RADIUS = Activities.CheckRadius or 32
local COUNTDOWN = 3
local MAX_STEP = 80 -- studs between two checks; more than that is a teleport, not driving
-- How far from the pad's centre a car may be when "Race" is pressed: the prompt only shows with the
-- driver within 30 studs of it; a long car's own middle and lag take the rest.
local START_REACH = 60

local racesById = {}
local active = {} -- [player] = { race, car, index, startAt, lengthStuds, lastPos }
local boards = {} -- [raceId] = { {name, time} }
local holds = setmetatable({}, { __mode = "k" }) -- [car] = startAt of the countdown that holds it anchored
local raceEvent

local function now()
	return Workspace:GetServerTimeNow()
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function routeLength(race)
	local len, prev = 0, race.Start
	for _, c in ipairs(race.Checkpoints) do
		len += (flat(c) - flat(prev)).Magnitude
		prev = c
	end
	return len
end

-- Did the car pass within `radius` of the checkpoint on its way from `from` to `to` (flat positions)?
-- `from` is nil on the first check, and ignored after a jump too long to be driving.
local function reached(from, to, cp, radius)
	if (to - cp).Magnitude <= radius then
		return true
	end
	if not from then
		return false
	end
	local step = to - from
	local len2 = step:Dot(step)
	if len2 < 1e-4 or len2 > MAX_STEP * MAX_STEP then
		return false
	end
	local t = math.clamp((cp - from):Dot(step) / len2, 0, 1)
	return (from + step * t - cp).Magnitude <= radius
end

local function ownCar(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local car = seat and seat.Parent
	if car and seat.Name == "DriverSeat" and car:GetAttribute("OwnerUserId") == player.UserId and car.PrimaryPart then
		return car
	end
	return nil
end

-- Let go of a car held for the countdown that was to end at `startAt`, and hand it back to its driver.
-- Only the countdown that holds the car may do it: when a race is cancelled and started again within
-- the three seconds, the first countdown's timer must not free the car before the second one's GO
-- (a head start on the clock).
local function release(player, car, startAt)
	if holds[car] ~= startAt then
		return
	end
	holds[car] = nil
	local chassis = car.PrimaryPart
	if not chassis or not chassis:IsDescendantOf(Workspace) then
		return -- the car is gone (despawned, sunk)
	end
	chassis.Anchored = false
	local seat = car:FindFirstChild("DriverSeat")
	local occupant = seat and seat.Occupant
	if occupant and occupant.Parent == player.Character then
		chassis:SetNetworkOwner(player)
	end
end

local function stop(player, reason)
	local r = active[player]
	if not r then
		return
	end
	active[player] = nil
	player:SetAttribute("RacingId", nil)
	if reason then
		raceEvent:FireClient(player, "Cancelled", { Reason = reason })
	end
	-- Cancelled during the countdown: the car is free at once, not when the three seconds are up. A
	-- driver who gets back in would find it stuck, and sitting down hands the car to its driver
	-- (VehicleService), which an anchored part refuses with an error. (After GO this does nothing.)
	release(player, r.car, r.startAt)
end

local function publishBoard(raceId)
	ReplicatedStorage:SetAttribute("RaceBoard_" .. raceId, HttpService:JSONEncode(boards[raceId] or {}))
end

local function finish(player, r)
	local time = now() - r.startAt
	local race = r.race
	stop(player, nil)
	-- Sanity check: nobody drives the route faster than 1.3 x their car's top speed.
	local fastest = r.lengthStuds / ((r.car:GetAttribute("MaxSpeed") or 150) * 1.3)
	if time < fastest then
		warn(string.format("[RaceService] rejected %s on %s: %.2fs < %.2fs", player.Name, race.Id, time, fastest))
		raceEvent:FireClient(player, "Cancelled", { Reason = "Invalid" })
		return
	end
	local reward = race.Reward + (time <= race.Par and race.ParBonus or 0)
	local data = DataService.Get(player)
	local best
	local newBest = false
	if data then
		data.races = data.races or {}
		best = data.races[race.Id]
		if not best or time < best then
			data.races[race.Id] = time
			newBest = true
		end
	end
	EconomyService.AddCash(player, reward, "race:" .. race.Id)
	require(game:GetService("ServerScriptService").Services.ProgressService).Event(player, "RaceFinish", time <= race.Par and 1 or 0)
	player:SetAttribute("RacesWon", (player:GetAttribute("RacesWon") or 0) + 1)
	-- Server leaderboard (top 5, one entry per player).
	local board = boards[race.Id] or {}
	local found = false
	for _, e in ipairs(board) do
		if e.name == player.DisplayName then
			found = true
			e.time = math.min(e.time, time)
		end
	end
	if not found then
		table.insert(board, { name = player.DisplayName, time = time })
	end
	table.sort(board, function(a, b)
		return a.time < b.time
	end)
	while #board > 5 do
		table.remove(board)
	end
	boards[race.Id] = board
	publishBoard(race.Id)
	raceEvent:FireClient(player, "Finished", {
		Id = race.Id, Time = time, Par = race.Par, Reward = reward, NewBest = newBest, Best = newBest and time or best,
	})
end

local function start(player, race, padPos)
	if not RateLimit.Allow(player, "RaceStart", 0.5, 1) then
		return
	end
	if active[player] then
		return
	end
	local notify = Remotes.Event("Notify")
	if player:GetAttribute("Side") ~= "Civilian" then
		notify:FireClient(player, "ActivityCivOnly")
		return
	elseif (player:GetAttribute("Heat") or 0) > 0 then
		notify:FireClient(player, "ActivityWanted")
		return
	elseif player:GetAttribute("Mission") or player:GetAttribute("JobKind") or player:GetAttribute("BigScore") then
		-- One thing at a time (MissionService refuses races the same way). A taxi / courier shift would
		-- keep running under the race, and both share ActivityClient's ring.
		notify:FireClient(player, "MissionBusy")
		return
	end
	local car = ownCar(player)
	if not car or (car:GetAttribute("Boat") == true) ~= (race.Boat == true) then
		notify:FireClient(player, race.Boat and "RaceNeedBoat" or "RaceNeedCar")
		return
	end
	local chassis = car.PrimaryPart
	-- A cheater can fire the prompt from anywhere on the map, and the next lines move the car (and
	-- whoever rides in it) to the start: the car has to be at the pad already. Nobody honest is ever
	-- this far away (the prompt would not show), so there is nothing to tell them.
	-- ("not <=" so a NaN position, which compares false with everything, is refused too)
	if not ((flat(chassis.Position) - flat(padPos)).Magnitude <= START_REACH) then
		return
	end
	local startPos = Vector3.new(race.Start.X, race.Boat and 1 or 3.2, race.Start.Z)
	VehicleGuard.Allow(car, COUNTDOWN + 2)
	-- (stop() frees a cancelled countdown's car at once, so nothing should hold it here; the ownership
	-- call below errors on an anchored part, so make sure. Only this file ever anchors a car.)
	chassis.Anchored = false
	chassis:SetNetworkOwner(nil)
	car:PivotTo(CFrame.lookAt(startPos, startPos + race.Heading))
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	chassis.Anchored = true
	local startAt = now() + COUNTDOWN
	holds[car] = startAt
	active[player] = { race = race, car = car, index = 1, startAt = startAt, lengthStuds = routeLength(race) }
	player:SetAttribute("RacingId", race.Id)
	raceEvent:FireClient(player, "Countdown", { Id = race.Id, StartAt = startAt })
	task.delay(COUNTDOWN, release, player, car, startAt)
end

local function tick()
	local t = now()
	for player, r in pairs(active) do
		local car = r.car
		local chassis = car.PrimaryPart
		if player.Parent ~= Players then
			active[player] = nil
		elseif not car.Parent or not chassis then
			stop(player, "CarLost")
		elseif ownCar(player) ~= car then
			stop(player, "LeftCar")
		elseif (player:GetAttribute("Heat") or 0) > 0 then
			stop(player, "Wanted")
		elseif t > r.startAt + r.race.Par * 2.5 then
			stop(player, "TooSlow")
		elseif t >= r.startAt then
			local cp = r.race.Checkpoints[r.index]
			local pos = flat(chassis.Position)
			if pos.X ~= pos.X or pos.Z ~= pos.Z then
				pos = r.lastPos -- a NaN position (broken physics): wait for a real one
			end
			if pos then
				local hit = reached(r.lastPos, pos, flat(cp), r.race.Radius or CHECK_RADIUS)
				r.lastPos = pos
				if hit then
					r.index += 1
					if r.index > #r.race.Checkpoints then
						finish(player, r)
					else
						raceEvent:FireClient(player, "Checkpoint", { Index = r.index })
					end
				end
			end
		end
	end
end

function RaceService.Init()
	raceEvent = Remotes.Event("RaceEvent")
	for _, race in ipairs(Activities.Races) do
		racesById[race.Id] = race
		local pad = Workspace.Activities:FindFirstChild("RaceStart_" .. race.Id)
		if pad then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "RacePrompt"
			prompt.ActionText = "Race"
			prompt.ObjectText = race.Name
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 30
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonA
			prompt.Parent = pad
			-- Where the prompt really is (the pad CityGen built; Start itself if the pad is not a part).
			local padPos = pad:IsA("BasePart") and pad.Position or race.Start
			prompt.Triggered:Connect(function(player)
				start(player, race, padPos)
			end)
		end
		publishBoard(race.Id)
	end
	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[RaceService] " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		active[p] = nil
	end)
end

return RaceService
