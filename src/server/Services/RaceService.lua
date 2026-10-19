-- RaceService (ModuleScript, ServerScriptService.Services.RaceService)
-- Street races as solo time trials (Config.Activities.Races).
--   * Drive onto a race start pad in your own car (not wanted) and press E ("Race").
--   * Your car is lined up and held for a 3-second countdown, then the clock runs.
--   * Checkpoints must be passed in order (within 32 studs); the server tracks them 10 times a second.
--   * Finish: reward + a bonus for beating par; personal bests are saved; the server leaderboard
--     (top 5 per race) lives in ReplicatedStorage attributes "RaceBoard_<Id>".
--   * Only the first finish of each race per UTC day pays in full (saved in data.flags.raceDay); later
--     finishes pay Activities.RaceRepeatShare (cash and XP), and the same race can't be restarted for
--     Activities.RaceCooldown seconds after a finish (toast "RaceCooldown").
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
local DailyService = require(ServerScriptService.Services.DailyService)
local VehicleGuard = require(ServerScriptService.Services.VehicleGuard)

local RaceService = {}

local CHECK_RADIUS = 32
local COUNTDOWN = 3

local racesById = {}
local active = {} -- [player] = { race, car, index, startAt, lengthStuds }
local boards = {} -- [raceId] = { {name, time} }
local lastFinish = {} -- [player] = { [raceId] = os.clock() of the last finish }
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

local function ownCar(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local car = seat and seat.Parent
	if car and seat.Name == "DriverSeat" and car:GetAttribute("OwnerUserId") == player.UserId and car.PrimaryPart then
		return car
	end
	return nil
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
	lastFinish[player] = lastFinish[player] or {}
	lastFinish[player][race.Id] = os.clock()
	local reward = race.Reward + (time <= race.Par and race.ParBonus or 0)
	local data = DataService.Get(player)
	local best
	local newBest = false
	local first = false -- no save loaded: repeat pay
	if data then
		data.races = data.races or {}
		best = data.races[race.Id]
		if not best or time < best then
			data.races[race.Id] = time
			newBest = true
		end
		-- Full pay once per race per UTC day.
		local day = DailyService.DayRecord(data, "raceDay")
		day.done = type(day.done) == "table" and day.done or {}
		first = not day.done[race.Id]
		day.done[race.Id] = true
	end
	local share = first and 1 or Activities.RaceRepeatShare
	reward = math.floor(reward * share)
	EconomyService.AddCash(player, reward, "race:" .. race.Id)
	require(game:GetService("ServerScriptService").Services.ProgressService).Event(player, "RaceFinish", time <= race.Par and 1 or 0, share)
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
		Repeat = not first,
	})
end

local function start(player, race)
	if not RateLimit.Allow(player, "RaceStart", 0.5, 1) then
		return
	end
	if active[player] or player:GetAttribute("Side") ~= "Civilian" or (player:GetAttribute("Heat") or 0) > 0 then
		return
	end
	local last = lastFinish[player] and lastFinish[player][race.Id]
	if last and os.clock() - last < Activities.RaceCooldown then
		Remotes.Event("Notify"):FireClient(player, "RaceCooldown")
		return
	end
	local car = ownCar(player)
	if not car or (car:GetAttribute("Boat") == true) ~= (race.Boat == true) then
		Remotes.Event("Notify"):FireClient(player, race.Boat and "RaceNeedBoat" or "RaceNeedCar")
		return
	end
	local chassis = car.PrimaryPart
	local startPos = Vector3.new(race.Start.X, race.Boat and 1 or 3.2, race.Start.Z)
	VehicleGuard.Allow(car, COUNTDOWN + 2)
	chassis:SetNetworkOwner(nil)
	car:PivotTo(CFrame.lookAt(startPos, startPos + race.Heading))
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	chassis.Anchored = true
	local startAt = now() + COUNTDOWN
	active[player] = { race = race, car = car, index = 1, startAt = startAt, lengthStuds = routeLength(race) }
	player:SetAttribute("RacingId", race.Id)
	raceEvent:FireClient(player, "Countdown", { Id = race.Id, StartAt = startAt })
	task.delay(COUNTDOWN, function()
		if car.Parent then
			chassis.Anchored = false
			local occupant = car.DriverSeat.Occupant
			if occupant and occupant.Parent == player.Character then
				chassis:SetNetworkOwner(player)
			end
		end
	end)
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
			if (flat(chassis.Position) - flat(cp)).Magnitude <= CHECK_RADIUS then
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
			prompt.Triggered:Connect(function(player)
				start(player, race)
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
		lastFinish[p] = nil
	end)
end

return RaceService
