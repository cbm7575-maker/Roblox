-- RaceService (ModuleScript, ServerScriptService.Services.RaceService)
-- Street races (Config.Activities.Races, rules in Activities.RaceRules) and race challenges between two
-- drivers (Activities.Challenge). The server decides everything; ActivityClient only shows it.
-- STREET RACES
--   * Drive onto a race's start pad in your own car (free roam: not wanted, not on a phone mission, a
--     taxi / courier shift or the Big Score) and press E ("Race"). A refusal says why (Notify). The
--     prompt is the client's word, so the server checks the car really is at the pad (START_REACH).
--   * That opens the race's LOBBY for RaceRules.Lobby seconds (LobbySolo when no other citizen is within
--     twice LobbyShow studs of the pad: a player alone doesn't wait for nobody). It is published as the
--     ReplicatedStorage attributes "RaceLobby_<Id>" (server time it starts) and "RaceLobbyN_<Id>" (how
--     many are in); members carry the player attribute "RaceLobby" (the race's id). ActivityClient shows
--     a banner to the members and to citizens within LobbyShow studs of the pad. Others join by pressing
--     Race on the same pad while it is open (MaxRacers players at most).
--   * When the lobby closes every member is checked again (the same rules, their car within LOBBY_REACH
--     of the pad). The cars are lined up on a starting GRID behind the start, two abreast, facing
--     Heading: one slot per car, and a slot needs road under it (water for a boat) and nothing solid in
--     it, else the next one back is used. They are held (anchored) for the 3-second countdown and let go
--     together. A hold belongs to its countdown (S.holds[car]): it ends at GO, or at once when that racer
--     drops out during the countdown, and an older countdown's timer can never let go of a newer one's.
--     Every teleport of a player's car calls VehicleGuard.Allow first.
--   * NPC racers (RaceRules.NPCs; never on the water): with fewer than Field players, RaceAIService fills
--     the grid up to Field cars, named over their roofs ("RICO"). They count for positions and can win.
--     Their top speed is NPCSpeed x the fastest player car's (a little under a good driver; no nitro),
--     eased off by NPCCatchUp while they lead every player still racing and pushed by as much while they
--     trail them all. They go when the race ends (at most NPC_AFTER seconds after the last player is done).
--   * Laps: a race's Laps (default 1) repeats its checkpoints, so the last one of a lap is the lap line
--     (looped courses only). Par is for the whole race. The client gets Laps in "Countdown".
--   * Checkpoints must be passed in order, within Config.Activities.CheckRadius studs (or the race's own
--     Radius). The server checks 10 times a second and tests the whole stretch driven since the last
--     check, so a fast car can't skip through a checkpoint between two checks. NPCs are checked the same.
--   * Positions: every RANK_EVERY seconds the racers are ranked (finished ones first, in finishing order;
--     then by checkpoints passed; then by the distance to the next one) and each player still racing gets
--     "Position" { Pos, Of } whenever theirs changes.
--   * Pay by place, players only (RaceRules.Pay): 1st Reward (+ ParBonus at or under par), 2nd 60%,
--     3rd 35%, later PayRest. A finish faster than the route could be driven at 1.3 x the car's top
--     speed is rejected ("Cancelled" Invalid). Personal bests (data.races; a multi-lap race keeps its own,
--     "<Id>x<laps>"), the server leaderboard (top 5, ReplicatedStorage attribute "RaceBoard_<Id>") and
--     ProgressService "RaceFinish" for every player who finishes; RacesWon only for a win.
--   * "Finished" { Id, Run, Time, Par, Reward, Bonus, NewBest, Best, Place, Of } to the finisher, then
--     "Standings" { Id, Run, Rows, Final } to every player who has finished, whenever somebody finishes
--     and once more at the end (Final): everyone in order, NPCs too, with their times (DNF for drop-outs).
--     Run tells one run of a race from the next.
--   * Police: heat no longer calls a running street race off (it still keeps you from starting one).
--     With chance SpotChance a race is "spotted": at a random moment SpotFrom..SpotTo of the way through
--     (by par) every player still racing gets a star (HeatService.Add 1, "street_race") and the toast
--     RaceSpotted. The AI police then come as for anyone wanted. Never on the water. Off for now: the
--     owner doesn't want a race to make you wanted (Config.Activities SpotChance = 0).
--   * A player drops out ("Cancelled" { Reason }) if they get out or lose the car, die, are arrested or
--     take longer than 2.5 x par.
-- RACE CHALLENGES: a friendly race between two drivers, anywhere on the roads
--   * Remote "RaceChallenge" ("Challenge", userId?): from the driver's seat of your own car (not a boat),
--     free roam, not busy (no race, lobby, mission, shift or Big Score). It goes to the nearest such driver
--     within Challenge.Reach studs (the one the client names, when that player is one of them). One
--     challenge may wait on a driver, and one from a driver; it lapses after Challenge.Expire seconds.
--     The target gets "Challenge" { FromUserId, FromName, Expires, Rematch } (an ACCEPT / DECLINE card),
--     the challenger "ChallengeSent" { Name, Expires }. A decline or a lapse comes back to the challenger
--     as "ChallengeAnswer" { Name, Answer = "Declined" | "Expired" | "Off" }; "ChallengeGone" closes the
--     target's card.
--   * ("Accept") checks both again (within Challenge.AcceptReach of each other) and builds a route: from
--     the road crossing nearest the two cars (the nearest one ahead of them, if any) to a finish
--     MinLength..MaxLength studs away by road, preferring the way the cars face. Checkpoints every
--     CheckpointEvery studs along it, at every bend of more than 30 degrees, and at the finish, so each leg
--     is one stretch of road (ActivityClient draws the way leg by leg along the roads). Both get
--     "Countdown" { Id, StartAt, Def = the route, Opponent }; the client registers Def like a race. No
--     teleport: both cars are held where they are for the countdown, then let go together.
--   * The first across the line wins ("Finished" { Duel, Win } to them); the other has DUEL_GRACE seconds
--     to finish. Then both get "DuelResult" { Id, Win, Rows, Opponent, OpponentUserId, Rematch } and may
--     press REMATCH for Challenge.Rematch seconds ("RaceChallenge" "Rematch", the rival's userId: a new
--     challenge to that player, the other way round, within AcceptReach). No money, no records, never
--     police. It is off for both if either gets out of the car, dies, is arrested, leaves the game or
--     becomes wanted before anybody has finished.
-- Clean-up on PlayerRemoving and CharacterRemoving (races, lobbies, challenges). Each race's tick runs in
-- a pcall; a race that errors is ended, which lets go of every car it holds.
-- Constants live in K and state in S (fewer top-level locals; see ActivityClient's note).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Activities = require(ReplicatedStorage.Shared.Config.Activities)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local DataService = require(ServerScriptService.Services.DataService)
local VehicleGuard = require(ServerScriptService.Services.VehicleGuard)

local RaceService = {}

local RULES = Activities.RaceRules or {}
local DUEL = Activities.Challenge or {}

local K = {
	CHECK_RADIUS = Activities.CheckRadius or 32,
	COUNTDOWN = 3,
	MAX_STEP = 80, -- studs between two checks; more than that is a teleport, not driving
	-- How far from the pad's centre a car may be when "Race" is pressed: the prompt only shows with the
	-- driver within 30 studs of it; a long car's own middle and lag take the rest.
	START_REACH = 60,
	TICK = 0.1,
	RANK_EVERY = 0.25,
	-- Lobby
	LOBBY = RULES.Lobby or 12,
	LOBBY_SOLO = RULES.LobbySolo or 6,
	LOBBY_SHOW = RULES.LobbyShow or 150,
	LOBBY_REACH = 150, -- studs from the pad a member's car may have wandered when the lobby closes
	MAX_RACERS = RULES.MaxRacers or 6,
	-- The grid: slots two abreast (SIDE studs either side of the start line), rows ROW studs apart.
	GRID_SIDE = 7,
	GRID_ROW = 22,
	BOAT_SIDE = 10,
	BOAT_ROW = 28,
	GRID_SLOTS = 16, -- candidate slots looked at (a blocked one is skipped)
	GRID_BOX = Vector3.new(9, 4.4, 19), -- the room a car needs in a slot (from 1.2 studs over the road)
	CAR_Y = 3.2,
	BOAT_Y = 1,
	-- NPCs
	NPCS = RULES.NPCs ~= false,
	FIELD = RULES.Field or 4,
	NPC_SPEED = RULES.NPCSpeed or 0.94,
	CATCH_UP = RULES.NPCCatchUp or 0.05,
	NPC_AFTER = 20, -- seconds NPCs may keep racing after the last player is done (for the standings)
	NPC_NAMES = { "RICO", "VEE", "DUKE", "NINA", "JAX", "LOLA", "MARCO", "TASHA" },
	NPC_LANES = { 5, 10, 3, 8, 6, 12 }, -- studs right of the race's line, one per NPC (no two on one line)
	-- Pay and police
	PAY = RULES.Pay or { 1, 0.6, 0.35 },
	PAY_REST = RULES.PayRest or 0.15,
	SPOT_CHANCE = RULES.SpotChance or 0.35,
	SPOT_FROM = RULES.SpotFrom or 0.25,
	SPOT_TO = RULES.SpotTo or 0.6,
	-- Challenges
	DUEL_REACH = DUEL.Reach or 80,
	DUEL_ACCEPT = DUEL.AcceptReach or 150,
	DUEL_EXPIRE = DUEL.Expire or 15,
	DUEL_MIN = DUEL.MinLength or 1000,
	DUEL_MAX = DUEL.MaxLength or 1600,
	DUEL_CP_EVERY = DUEL.CheckpointEvery or 200,
	DUEL_REMATCH = DUEL.Rematch or 15,
	DUEL_GRACE = 30, -- seconds the loser has to cross the line after the winner
	DUEL_COOLDOWN = 60, -- seconds before a driver who declined (or didn't answer) may be challenged again by the same player
	DUEL_LEVEL = 30, -- studs: how far ahead along the road one car may be of the other when the challenge is accepted
	DUEL_TURN_COS = math.cos(math.rad(30)), -- a bend sharper than this gets a checkpoint
	DUEL_CP_GAP = 60, -- no regular checkpoint this close before a crossing (a bend's own may sit there)
	DUEL_AHEAD = 220, -- studs: the start crossing is the nearest one ahead of the cars within this
	DUEL_SPEED = 95, -- studs/s: what a duel's par is worked out from (2.5 x par = out of time)
}

local S = {
	racesById = {},
	boards = {}, -- [raceId] = { {name, time} }
	holds = setmetatable({}, { __mode = "k" }), -- [car] = startAt of the countdown that holds it anchored
	lobbies = {}, -- [raceId] = { race, padPos, startsAt, members = { player } }
	lobbyOf = {}, -- [player] = their lobby
	sessions = {}, -- [session] = true: the races running now
	racerOf = {}, -- [player] = their racer in a race running now
	challenges = {}, -- [target] = { from = player, at = os.clock() }
	outgoing = {}, -- [challenger] = target
	rematch = {}, -- [player] = { other = player, untilAt = os.clock() }
	declined = {}, -- [challenger] = { [target] = os.clock() of their NO } (weak keys)
	serial = 0, -- numbers each run of a race ("Run") and each challenge's route id
	rng = Random.new(),
	nextSweep = 0,
	ai = nil, -- RaceAIService once loaded (false if it isn't there)
	raceEvent = nil,
	notify = nil,
}

local function now()
	return Workspace:GetServerTimeNow()
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- The checkpoints of `laps` laps, one after another.
local function expand(checkpoints, laps)
	local out = {}
	for _ = 1, laps do
		for _, cp in ipairs(checkpoints) do
			table.insert(out, cp)
		end
	end
	return out
end

local function routeLength(start, cps)
	local len, prev = 0, start
	for _, c in ipairs(cps) do
		len += (flat(c) - flat(prev)).Magnitude
		prev = c
	end
	return len
end

-- Did the car pass within `radius` of the checkpoint on its way from `from` to `to` (flat positions)?
-- `from` is nil on the first check, and ignored after a jump too long to be driving.
-- Second result: how far along that step (0-1) it came closest to the checkpoint, so a finish can be
-- timed between two checks (a photo finish goes to whoever really crossed first).
local function reached(from, to, cp, radius)
	if from then
		local step = to - from
		local len2 = step:Dot(step)
		if len2 >= 1e-4 and len2 <= K.MAX_STEP * K.MAX_STEP then
			local t = math.clamp((cp - from):Dot(step) / len2, 0, 1)
			if (from + step * t - cp).Magnitude <= radius then
				return true, t
			end
		end
	end
	if (to - cp).Magnitude <= radius then
		return true, 1
	end
	return false, nil
end

-- The player's own car while they sit alive in its driver's seat, else nil.
local function ownCar(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.Health > 0 and hum.SeatPart
	local car = seat and seat.Parent
	if car and seat.Name == "DriverSeat" and car:GetAttribute("OwnerUserId") == player.UserId and car.PrimaryPart then
		return car
	end
	return nil
end

-- RaceAIService (the NPC racers), found on first use. Without it races simply have no NPCs.
local function aiService()
	if S.ai == nil then
		local module = ServerScriptService.Services:FindFirstChild("RaceAIService")
		local ok, found = false, nil
		if module then
			ok, found = pcall(require, module)
		end
		S.ai = ok and type(found) == "table" and found or false
		if not S.ai then
			warn("[RaceService] RaceAIService is missing: races run without NPCs")
		end
	end
	return S.ai or nil
end

-- Why this player can't race now (a Notify key), or nil and their car. boat: the race is on the water.
local function refuse(player, boat)
	if player:GetAttribute("Side") ~= "Civilian" then
		return "ActivityCivOnly", nil
	elseif (player:GetAttribute("Heat") or 0) > 0 then
		return "ActivityWanted", nil
	elseif player:GetAttribute("Mission") or player:GetAttribute("JobKind") or player:GetAttribute("BigScore") then
		-- One thing at a time (MissionService refuses races the same way). A taxi / courier shift would
		-- keep running under the race, and both share ActivityClient's ring.
		return "MissionBusy", nil
	end
	local car = ownCar(player)
	if not car or (car:GetAttribute("Boat") == true) ~= (boat == true) then
		return boat and "RaceNeedBoat" or "RaceNeedCar", nil
	end
	return nil, car
end

------------------------------------------------------------------ holding cars for the countdown

-- Let go of a car held for the countdown that was to end at `startAt`, and hand it back to its driver.
-- Only the countdown that holds the car may do it: when a race is cancelled and started again within
-- the three seconds, the first countdown's timer must not free the car before the second one's GO
-- (a head start on the clock).
local function release(player, car, startAt)
	if not car or S.holds[car] ~= startAt then
		return
	end
	S.holds[car] = nil
	local chassis = car.PrimaryPart
	if not chassis or not chassis:IsDescendantOf(Workspace) then
		return -- the car is gone (despawned, sunk)
	end
	chassis.Anchored = false
	local seat = car:FindFirstChild("DriverSeat")
	local occupant = seat and seat.Occupant
	if player and occupant and occupant.Parent == player.Character then
		pcall(chassis.SetNetworkOwner, chassis, player)
	end
end

-- Hold a player's car still for the countdown that ends at startAt: physics to the server, moved to `cf`
-- first when one is given (the grid; a challenge holds the cars where they are). False if that failed,
-- and then the car is never left anchored.
local function hold(car, cf, startAt)
	local chassis = car.PrimaryPart
	local ok, err = pcall(function()
		VehicleGuard.Allow(car, K.COUNTDOWN + 2)
		-- (a cancelled countdown frees its car at once, so nothing should hold it here; the ownership call
		-- errors on an anchored part, so make sure. Only this file anchors a player's car.)
		chassis.Anchored = false
		chassis:SetNetworkOwner(nil)
		if cf then
			car:PivotTo(cf)
		end
		chassis.AssemblyLinearVelocity = Vector3.zero
		chassis.AssemblyAngularVelocity = Vector3.zero
		chassis.Anchored = true
	end)
	if not ok then
		warn("[RaceService] couldn't hold " .. car:GetFullName() .. ": " .. tostring(err))
		pcall(function()
			chassis.Anchored = false
		end)
		return false
	end
	S.holds[car] = startAt
	return true
end

-- A player's part in a race is over (finished, out, or the race ended): free them and their car.
local function freeHuman(r)
	local p = r.player
	if S.racerOf[p] == r then
		S.racerOf[p] = nil
		p:SetAttribute("RacingId", nil)
	end
	release(p, r.car, r.sess.startAt)
end

------------------------------------------------------------------ boards, standings, pay

local function publishBoard(raceId)
	ReplicatedStorage:SetAttribute("RaceBoard_" .. raceId, HttpService:JSONEncode(S.boards[raceId] or {}))
end

-- The server leaderboard: top 5, one entry per player.
local function addToBoard(raceId, name, time)
	local board = S.boards[raceId] or {}
	local found = false
	for _, e in ipairs(board) do
		if e.name == name then
			found = true
			e.time = math.min(e.time, time)
		end
	end
	if not found then
		table.insert(board, { name = name, time = time })
	end
	table.sort(board, function(a, b)
		return a.time < b.time
	end)
	while #board > 5 do
		table.remove(board)
	end
	S.boards[raceId] = board
	publishBoard(raceId)
end

-- Out of the race (left the car, gone, too slow...). reason = the "Cancelled" Reason the player is told
-- (nil: nothing to tell, e.g. they left the game).
local function dropRacer(r, reason)
	if r.state ~= "racing" then
		return
	end
	r.state = "out"
	r.sess.changed = true
	if r.player then
		freeHuman(r)
		if reason and r.player.Parent == Players then
			S.raceEvent:FireClient(r.player, "Cancelled", { Reason = reason })
		end
	elseif r.bot and S.ai then
		S.ai.Remove(r.bot)
	end
end

local function stateOrder(r)
	return r.state == "done" and 1 or (r.state == "racing" and 2 or 3)
end

-- "Standings" to every player of this run who has finished (see the header).
local function standings(sess, final)
	local order = table.clone(sess.racers)
	table.sort(order, function(x, y)
		local kx, ky = stateOrder(x), stateOrder(y)
		if kx ~= ky then
			return kx < ky
		end
		if kx == 1 then
			return x.place < y.place
		end
		return (x.rankNow or 99) < (y.rankNow or 99)
	end)
	local rows = {}
	for i, r in ipairs(order) do
		rows[i] = {
			Name = r.name,
			Time = r.state == "done" and r.time or nil,
			Out = r.state == "out" or nil,
			Npc = r.bot ~= nil or nil,
			UserId = r.player and r.player.UserId or nil,
		}
	end
	for _, r in ipairs(sess.racers) do
		local p = r.player
		if p and r.state == "done" and p.Parent == Players then
			S.raceEvent:FireClient(p, "Standings", { Id = sess.race.Id, Run = sess.serial, Rows = rows, Final = final == true })
		end
	end
end

-- A player crossed the line of a street race: pay by place, best times, the board (see the header).
local function payStreet(sess, r)
	local player, race, time = r.player, sess.race, r.time
	local underPar = time <= sess.par
	local bonus = r.place == 1 and underPar
	local reward = math.floor(race.Reward * (K.PAY[r.place] or K.PAY_REST) + 0.5) + (bonus and race.ParBonus or 0)
	local data = DataService.Get(player)
	local best
	local newBest = false
	if data then
		data.races = data.races or {}
		best = data.races[sess.pbKey]
		if type(best) ~= "number" or time < best then
			data.races[sess.pbKey] = time
			newBest = true
		end
	end
	EconomyService.AddCash(player, reward, "race:" .. race.Id)
	local okProgress, errProgress = pcall(function()
		require(ServerScriptService.Services.ProgressService).Event(player, "RaceFinish", underPar and 1 or 0)
	end)
	if not okProgress then
		warn("[RaceService] progress: " .. tostring(errProgress))
	end
	if r.place == 1 then
		player:SetAttribute("RacesWon", (player:GetAttribute("RacesWon") or 0) + 1)
	end
	addToBoard(race.Id, player.DisplayName, time)
	S.raceEvent:FireClient(player, "Finished", {
		Id = race.Id, Run = sess.serial, Time = time, Par = sess.par, Reward = reward, Bonus = bonus,
		NewBest = newBest, Best = newBest and time or best, Place = r.place, Of = #sess.racers,
	})
end

-- A player crossed the line of a challenge. The first one has won: tell them now, and tell the other
-- one (still racing) who won; the result card for both comes when the other is done too (stepDuel).
local function duelFinished(sess, r)
	if r.place ~= 1 then
		return
	end
	sess.winnerAt = now()
	local other
	for _, x in ipairs(sess.racers) do
		if x ~= r then
			other = x
		end
	end
	S.raceEvent:FireClient(r.player, "Finished", {
		Id = sess.race.Id, Run = sess.serial, Time = r.time, Duel = true, Win = true, Place = 1, Of = 2,
		Opponent = other and other.name or "?",
	})
	if other and other.state == "racing" and other.player.Parent == Players then
		S.raceEvent:FireClient(other.player, "DuelLead", { Name = r.name, Grace = K.DUEL_GRACE })
	end
end

local function finishRacer(sess, r, t)
	local time = t - sess.startAt
	if r.player then
		-- Sanity check (street races and challenges alike): nobody drives the route faster than 1.3 x
		-- their car's top speed.
		local fastest = sess.lengthStuds / ((r.car:GetAttribute("MaxSpeed") or 150) * 1.3)
		if time < fastest then
			warn(string.format("[RaceService] rejected %s on %s: %.2fs < %.2fs", r.player.Name, sess.race.Id, time, fastest))
			dropRacer(r, "Invalid")
			return
		end
	end
	r.state = "done"
	r.time = time
	sess.places += 1
	r.place = sess.places
	sess.changed = true
	if r.player then
		freeHuman(r)
		if sess.kind == "Duel" then
			duelFinished(sess, r)
		else
			payStreet(sess, r)
		end
	elseif r.bot and S.ai then
		S.ai.Done(r.bot) -- it rolls to a stop past the line and goes with the race
	end
end

-- One check of a racer (player or NPC) at `worldPos` against its next checkpoint.
local function advance(sess, r, worldPos, t)
	local pos = flat(worldPos)
	if pos.X ~= pos.X or pos.Z ~= pos.Z then
		pos = r.lastPos -- a NaN position (broken physics): wait for a real one
	end
	if not pos then
		return
	end
	local cp = sess.cps[r.index]
	local hit, frac = reached(r.lastPos, pos, flat(cp), sess.radius)
	local lastT = r.lastT
	r.lastPos, r.lastT = pos, t
	if not hit then
		return
	end
	r.index += 1
	if r.index > #sess.cps then
		-- Finished somewhere between the last check and this one: stepSession sorts everyone who crossed
		-- this tick by that moment before handing out places (not by their order in the list).
		sess.finishing = sess.finishing or {}
		table.insert(sess.finishing, { r = r, t = (lastT and frac) and lastT + frac * (t - lastT) or t })
	elseif r.player then
		S.raceEvent:FireClient(r.player, "Checkpoint", { Index = r.index })
	elseif r.bot and S.ai then
		S.ai.Target(r.bot, r.index)
	end
end

local function checkHuman(sess, r, t)
	local player, car = r.player, r.car
	local chassis = car.PrimaryPart
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if player.Parent ~= Players then
		dropRacer(r, nil)
	elseif not car.Parent or not chassis then
		dropRacer(r, "CarLost")
	elseif player:GetAttribute("Side") ~= "Civilian" then
		dropRacer(r, player:GetAttribute("Side") == "Prisoner" and "Arrested" or "Invalid")
	elseif not hum or hum.Health <= 0 then
		dropRacer(r, "Died")
	elseif ownCar(player) ~= car then
		dropRacer(r, "LeftCar")
	elseif sess.kind == "Duel" and (player:GetAttribute("Heat") or 0) > 0 then
		dropRacer(r, "Wanted") -- (a street race goes on under heat: see the header)
	elseif t > sess.startAt + sess.par * 2.5 then
		dropRacer(r, "TooSlow")
	elseif t >= sess.startAt then
		advance(sess, r, chassis.Position, t)
	end
end

local function checkBot(sess, r, t)
	local pos = S.ai and S.ai.Position(r.bot)
	if not pos then
		dropRacer(r, nil) -- its car is gone or broke down
	elseif t > sess.startAt + sess.par * 2.5 then
		dropRacer(r, nil)
	elseif t >= sess.startAt then
		advance(sess, r, pos, t)
	end
end

------------------------------------------------------------------ positions

-- NPCs ease off while they lead every player still racing and push while they trail them all
-- (RaceRules.NPCCatchUp): close racing rather than a procession.
local function pace(list)
	local ai = S.ai
	if not ai then
		return
	end
	local first, last
	for i, r in ipairs(list) do
		if r.player and r.state == "racing" then
			first = first or i
			last = i
		end
	end
	for i, r in ipairs(list) do
		if r.bot and r.state == "racing" then
			local f = 1
			if first and i < first then
				f = 1 - K.CATCH_UP
			elseif last and i > last then
				f = 1 + K.CATCH_UP
			end
			ai.SetPace(r.bot, f)
		end
	end
end

local function rank(sess)
	local list = {}
	for _, r in ipairs(sess.racers) do
		if r.state ~= "out" then
			if r.state == "racing" then
				local pos
				if r.player then
					pos = r.car.PrimaryPart and r.car.PrimaryPart.Position
				elseif S.ai then
					pos = S.ai.Position(r.bot)
				end
				local cp = sess.cps[r.index]
				local d = (pos and cp) and (flat(pos) - flat(cp)).Magnitude or math.huge
				r.dist = d == d and d or math.huge -- (NaN would break the sort)
			end
			table.insert(list, r)
		end
	end
	table.sort(list, function(x, y)
		local xd, yd = x.state == "done", y.state == "done"
		if xd ~= yd then
			return xd
		end
		if xd then
			return x.place < y.place
		end
		if x.index ~= y.index then
			return x.index > y.index
		end
		return x.dist < y.dist
	end)
	local of = #list
	for i, r in ipairs(list) do
		r.rankNow = i
		local p = r.player
		if p and r.state == "racing" and p.Parent == Players and (r.sentPos ~= i or r.sentOf ~= of) then
			r.sentPos, r.sentOf = i, of
			S.raceEvent:FireClient(p, "Position", { Pos = i, Of = of })
		end
	end
	pace(list)
end

------------------------------------------------------------------ the end of a race

-- The cops notice the race (see the header): every player still racing gets a star.
local function spot(sess)
	local module = ServerScriptService.Services:FindFirstChild("HeatService")
	local okHeat, HeatService = false, nil
	if module then
		okHeat, HeatService = pcall(require, module)
	end
	for _, r in ipairs(sess.racers) do
		local p = r.player
		if p and r.state == "racing" and p.Parent == Players then
			if okHeat then
				local ok, err = pcall(HeatService.Add, p, 1, "street_race")
				if not ok then
					warn("[RaceService] heat: " .. tostring(err))
				end
			end
			S.notify:FireClient(p, "RaceSpotted")
		end
	end
end

-- Both challengers are done (or one dropped out after the other had won): the result card and REMATCH.
local function duelResult(sess)
	local a, b = sess.racers[1], sess.racers[2]
	local winner = a.place == 1 and a or b
	local loser = winner == a and b or a
	local rows = {}
	for i, r in ipairs({ winner, loser }) do
		rows[i] = { Name = r.name, Time = r.state == "done" and r.time or nil, UserId = r.player.UserId }
	end
	for _, r in ipairs({ a, b }) do
		local other = r == a and b or a
		local p = r.player
		local busy = S.racerOf[p] ~= nil and S.racerOf[p].sess ~= sess -- (already in a new race: no card over it)
		if p.Parent == Players and not busy then
			local here = other.player.Parent == Players
			S.raceEvent:FireClient(p, "DuelResult", {
				Id = sess.race.Id, Run = sess.serial, Win = r == winner, Rows = rows, Opponent = other.name,
				OpponentUserId = other.player.UserId, Rematch = here and K.DUEL_REMATCH or 0,
			})
			if here then
				S.rematch[p] = { other = other.player, untilAt = os.clock() + K.DUEL_REMATCH + 1 }
			end
		end
	end
end

-- The race is over: everyone still in it is let go (cars freed, NPCs removed), last standings sent.
-- Each racer in its own pcall: one failure must never leave somebody else's car anchored.
local function endSession(sess)
	if sess.over then
		return
	end
	sess.over = true
	S.sessions[sess] = nil
	for _, r in ipairs(sess.racers) do
		local ok, err = pcall(function()
			if r.player then
				if r.state == "racing" then
					dropRacer(r, "Ended")
				end
				release(r.player, r.car, sess.startAt) -- (does nothing unless it still holds the car)
			elseif r.bot then
				if r.state == "racing" then
					r.state = "out"
				end
				if S.ai then
					S.ai.Remove(r.bot)
				end
			end
		end)
		if not ok then
			warn("[RaceService] ending a race: " .. tostring(err))
		end
	end
	if sess.kind == "Street" then
		standings(sess, true)
	end
end

local function stepStreet(sess, t)
	if sess.spotAt and t >= sess.spotAt then
		sess.spotAt = nil
		spot(sess)
	end
	local racing, bots, watching = 0, 0, 0
	for _, r in ipairs(sess.racers) do
		if r.player then
			if r.state == "racing" then
				racing += 1
			elseif r.state == "done" and r.player.Parent == Players then
				watching += 1
			end
		elseif r.state == "racing" then
			bots += 1
		end
	end
	if racing == 0 then
		-- Every player is done: the NPCs still out there get a little while to finish (the standings
		-- fill in), unless there's nobody left to see it.
		sess.humansDoneAt = sess.humansDoneAt or t
		if bots == 0 or watching == 0 or t > sess.humansDoneAt + K.NPC_AFTER then
			endSession(sess)
		end
	end
end

local function stepDuel(sess, t)
	local a, b = sess.racers[1], sess.racers[2]
	local won = a.state == "done" or b.state == "done"
	if not won then
		-- One of them dropped out before anybody finished: it's off for the other one too.
		if a.state == "out" and b.state == "racing" then
			dropRacer(b, "Opponent")
		elseif b.state == "out" and a.state == "racing" then
			dropRacer(a, "Opponent")
		end
	elseif sess.winnerAt and t > sess.winnerAt + K.DUEL_GRACE then
		for _, r in ipairs({ a, b }) do
			if r.state == "racing" then
				dropRacer(r, "DuelTimeUp")
			end
		end
	end
	if a.state ~= "racing" and b.state ~= "racing" then
		if won then
			duelResult(sess)
		end
		endSession(sess)
	end
end

-- GO: let every car of the race go together (the countdown's own timer; stepSession is the safety net).
local function releaseSession(sess)
	if sess.released then
		return
	end
	sess.released = true
	for _, r in ipairs(sess.racers) do
		if r.player then
			release(r.player, r.car, sess.startAt)
		elseif r.bot and S.ai and r.state == "racing" then
			S.ai.Release(r.bot)
		end
	end
end

local function stepSession(sess, t)
	if not sess.released and t >= sess.startAt + 0.5 then
		releaseSession(sess)
	end
	for _, r in ipairs(sess.racers) do
		if r.state == "racing" then
			if r.player then
				checkHuman(sess, r, t)
			else
				checkBot(sess, r, t)
			end
		end
	end
	local finishing = sess.finishing
	if finishing then
		sess.finishing = nil
		table.sort(finishing, function(x, y)
			return x.t < y.t
		end)
		for _, f in ipairs(finishing) do
			if f.r.state == "racing" then
				finishRacer(sess, f.r, f.t)
			end
		end
	end
	if sess.kind == "Duel" then
		stepDuel(sess, t)
	else
		stepStreet(sess, t)
	end
	if sess.over then
		return
	end
	if t >= sess.nextRank then
		sess.nextRank = t + K.RANK_EVERY
		rank(sess)
	end
	if sess.changed then
		sess.changed = false
		if sess.kind == "Street" then
			standings(sess, false)
		end
	end
end

local function newSession(kind, race, cps, laps, par)
	S.serial += 1
	return {
		serial = S.serial,
		kind = kind,
		race = race,
		cps = cps,
		laps = laps,
		par = par,
		radius = race.Radius or K.CHECK_RADIUS,
		lengthStuds = routeLength(race.Start, cps),
		racers = {},
		places = 0,
		startAt = now() + K.COUNTDOWN,
		nextRank = 0,
	}
end

local function newRacer(sess, player, car, name)
	local r = { sess = sess, player = player, car = car, name = name, index = 1, state = "racing" }
	table.insert(sess.racers, r)
	return r
end

-- Start the clock: GO in COUNTDOWN seconds (the client counts down from StartAt).
local function run(sess)
	S.sessions[sess] = true
	task.delay(math.max(0, sess.startAt - now()), function() -- (StartAt is what every client counts down to)
		local ok, err = pcall(releaseSession, sess)
		if not ok then
			warn("[RaceService] GO: " .. tostring(err))
		end
	end)
end

------------------------------------------------------------------ street races: lobby and grid

local function publishLobby(race, lobby)
	ReplicatedStorage:SetAttribute("RaceLobby_" .. race.Id, lobby and lobby.startsAt or nil)
	ReplicatedStorage:SetAttribute("RaceLobbyN_" .. race.Id, lobby and #lobby.members or nil)
end

local function leaveLobby(player)
	local lobby = S.lobbyOf[player]
	S.lobbyOf[player] = nil
	player:SetAttribute("RaceLobby", nil)
	if not lobby then
		return
	end
	local i = table.find(lobby.members, player)
	if i then
		table.remove(lobby.members, i)
	end
	if #lobby.members == 0 then
		if S.lobbies[lobby.race.Id] == lobby then
			S.lobbies[lobby.race.Id] = nil
			publishLobby(lobby.race, nil)
		end
	elseif S.lobbies[lobby.race.Id] == lobby then
		publishLobby(lobby.race, lobby)
	end
end

-- Is another citizen near enough to the pad that they might want in (the full lobby time)?
local function othersNear(player, padPos)
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root and p:GetAttribute("Side") == "Civilian" and (flat(root.Position) - flat(padPos)).Magnitude <= K.LOBBY_SHOW * 2 then
			return true
		end
	end
	return false
end

-- Can a car stand at `cf`: road (or water for a boat) under it, nothing that cars bump into in the way?
local function slotFree(cf, boat, overlap, down)
	local at = cf.Position
	local hit = Workspace:Raycast(Vector3.new(at.X, 12, at.Z), Vector3.new(0, -40, 0), down)
	if not hit then
		return false
	end
	if boat then
		if hit.Material ~= Enum.Material.Water then
			return false
		end
	elseif hit.Material == Enum.Material.Water or hit.Position.Y > 4 or hit.Position.Y < -4 then
		return false
	end
	local box = CFrame.new(at.X, (boat and 1 or 0) + 1.2 + K.GRID_BOX.Y / 2, at.Z) * cf.Rotation
	return #Workspace:GetPartBoundsInBox(box, K.GRID_BOX, overlap) == 0
end

-- Up to `want` free grid slots (CFrames, in order: front row first, the right-hand slot first).
-- The entrants' own cars and bodies don't count as in the way: they are all moved onto the grid.
local function gridSlots(race, want, entrants)
	local boat = race.Boat == true
	local head = flat(race.Heading)
	head = head.Magnitude > 0.01 and head.Unit or Vector3.zAxis
	local side = Vector3.new(-head.Z, 0, head.X) -- the right-hand side of travel along `head`
	local y = boat and K.BOAT_Y or K.CAR_Y
	local sideGap = boat and K.BOAT_SIDE or K.GRID_SIDE
	local rowGap = boat and K.BOAT_ROW or K.GRID_ROW
	local ignore = {}
	for _, e in ipairs(entrants) do
		table.insert(ignore, e.car)
		if e.player.Character then
			table.insert(ignore, e.player.Character)
		end
	end
	local acts = Workspace:FindFirstChild("Activities")
	if acts then
		table.insert(ignore, acts) -- (the pad itself)
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = ignore
	pcall(function()
		overlap.RespectCanCollide = true
	end)
	pcall(function()
		overlap.CollisionGroup = "Vehicles" -- only what a car would really hit (no props, no traffic)
	end)
	local downIgnore = table.clone(ignore)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		table.insert(downIgnore, vehicles)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(downIgnore, p.Character)
		end
	end
	local down = RaycastParams.new()
	down.FilterType = Enum.RaycastFilterType.Exclude
	down.FilterDescendantsInstances = downIgnore
	down.IgnoreWater = not boat
	local base = flat(race.Start)
	local out = {}
	for k = 0, K.GRID_SLOTS - 1 do
		if #out >= want then
			break
		end
		local row = k // 2
		local lateral = k % 2 == 0 and 1 or -1
		local p = base - head * (row * rowGap) + side * (lateral * sideGap)
		local pos = Vector3.new(p.X, y, p.Z)
		local cf = CFrame.lookAt(pos, pos + head)
		if slotFree(cf, boat, overlap, down) then
			table.insert(out, cf)
		end
	end
	if #out == 0 then
		-- Nothing passed the check (something odd on the road, or the ground not found): the start itself,
		-- where a lone racer always used to go, so a race can always be started.
		local pos = Vector3.new(base.X, y, base.Z)
		table.insert(out, CFrame.lookAt(pos, pos + head))
	end
	return out
end

-- The lobby has closed: line the entrants (and NPCs) up and start the countdown.
local function startStreet(race, entrants)
	local laps = math.max(1, math.floor(race.Laps or 1))
	local sess = newSession("Street", race, expand(race.Checkpoints, laps), laps, race.Par)
	sess.pbKey = laps > 1 and (race.Id .. "x" .. laps) or race.Id
	local ai = (K.NPCS and race.Boat ~= true) and aiService() or nil
	local npcs = ai and math.max(0, K.FIELD - #entrants) or 0
	local slots = gridSlots(race, #entrants + npcs, entrants)
	local used = 0
	local top = 0
	for _, e in ipairs(entrants) do
		local cf = slots[used + 1]
		if cf then
			used += 1 -- (taken even if the hold fails: the car may already stand on it)
		end
		if not cf then
			S.notify:FireClient(e.player, "RaceGridFull")
		elseif hold(e.car, cf, sess.startAt) then
			local r = newRacer(sess, e.player, e.car, e.player.DisplayName)
			r.grid = used
			S.racerOf[e.player] = r
			e.player:SetAttribute("RacingId", race.Id)
			top = math.max(top, e.car:GetAttribute("MaxSpeed") or 120)
		end
	end
	if #sess.racers == 0 then
		return
	end
	if ai and npcs > 0 then
		local okPlan, legs = pcall(ai.Plan, race.Id .. "x" .. laps, race.Start, sess.cps)
		if not okPlan then
			warn("[RaceService] NPC route: " .. tostring(legs))
			legs = nil
		end
		local names = table.clone(K.NPC_NAMES)
		for i = #names, 2, -1 do
			local j = S.rng:NextInteger(1, i)
			names[i], names[j] = names[j], names[i]
		end
		local cars = {}
		for k = 1, npcs do
			local cf = slots[used + 1]
			if not cf or not legs then
				break
			end
			local okSpawn, bot = pcall(ai.Spawn, {
				CFrame = cf,
				Name = names[k],
				Legs = legs,
				Lane = (race.LineOffset or 0) + K.NPC_LANES[(k - 1) % #K.NPC_LANES + 1],
				Top = top * K.NPC_SPEED * S.rng:NextNumber(0.97, 1.02),
				Avoid = cars,
			})
			if okSpawn and bot then
				used += 1
				local r = newRacer(sess, nil, bot.car, names[k])
				r.bot = bot
				r.grid = used
			elseif not okSpawn then
				warn("[RaceService] NPC: " .. tostring(bot))
			end
		end
	end
	for _, r in ipairs(sess.racers) do
		if r.player then
			S.raceEvent:FireClient(r.player, "Countdown", {
				Id = race.Id, Run = sess.serial, StartAt = sess.startAt, Laps = laps, Of = #sess.racers, Grid = r.grid,
			})
		end
	end
	if race.Boat ~= true and S.rng:NextNumber() < K.SPOT_CHANCE then
		sess.spotAt = sess.startAt + sess.par * S.rng:NextNumber(K.SPOT_FROM, K.SPOT_TO)
	end
	run(sess)
end

local function launch(lobby)
	local race = lobby.race
	local entrants = {}
	for _, p in ipairs(lobby.members) do
		if S.lobbyOf[p] == lobby then
			S.lobbyOf[p] = nil
		end
		if p.Parent == Players then
			p:SetAttribute("RaceLobby", nil)
			local why, car = refuse(p, race.Boat)
			if not why and S.racerOf[p] then
				why = "MissionBusy"
			end
			if why then
				S.notify:FireClient(p, why)
			elseif not ((flat(car.PrimaryPart.Position) - flat(lobby.padPos)).Magnitude <= K.LOBBY_REACH) then
				S.notify:FireClient(p, "RaceLobbyLeft")
			else
				table.insert(entrants, { player = p, car = car })
			end
		end
	end
	if #entrants > 0 then
		startStreet(race, entrants)
	end
end

local function stepLobbies(t)
	for id, lobby in pairs(S.lobbies) do
		if t >= lobby.startsAt then
			S.lobbies[id] = nil
			publishLobby(lobby.race, nil)
			local ok, err = pcall(launch, lobby)
			if not ok then
				warn("[RaceService] starting " .. id .. ": " .. tostring(err))
			end
		end
	end
end

-- "Race" pressed on a start pad: open the lobby, or join the one that is open.
local function onPad(player, race, padPos)
	if not RateLimit.Allow(player, "RaceStart", 0.5, 1) then
		return
	end
	if S.racerOf[player] then
		return
	end
	local lobby = S.lobbies[race.Id]
	if lobby and S.lobbyOf[player] == lobby then
		S.notify:FireClient(player, "RaceLobbyIn")
		return
	end
	local why, car = refuse(player, race.Boat)
	if why then
		S.notify:FireClient(player, why)
		return
	end
	-- A cheater can fire the prompt from anywhere on the map, and the race moves the car (and whoever
	-- rides in it) to the start: the car has to be at the pad already. Nobody honest is ever this far
	-- away (the prompt would not show), so there is nothing to tell them.
	-- ("not <=" so a NaN position, which compares false with everything, is refused too)
	if not ((flat(car.PrimaryPart.Position) - flat(padPos)).Magnitude <= K.START_REACH) then
		return
	end
	if lobby and #lobby.members >= K.MAX_RACERS then
		S.notify:FireClient(player, "RaceLobbyFull")
		return
	end
	if S.lobbyOf[player] then
		leaveLobby(player) -- (another race's lobby: this one instead)
	end
	if not lobby then
		lobby = {
			race = race,
			padPos = padPos,
			members = {},
			startsAt = now() + (othersNear(player, padPos) and K.LOBBY or K.LOBBY_SOLO),
		}
		S.lobbies[race.Id] = lobby
	end
	for _, m in ipairs(lobby.members) do
		S.raceEvent:FireClient(m, "LobbyJoin", { Name = player.DisplayName })
	end
	table.insert(lobby.members, player)
	S.lobbyOf[player] = lobby
	player:SetAttribute("RaceLobby", race.Id)
	publishLobby(race, lobby)
	S.raceEvent:FireClient(player, "Lobby", { Id = race.Id, StartsAt = lobby.startsAt, Count = #lobby.members })
end

------------------------------------------------------------------ race challenges

-- Can this player take part in a challenge right now? Their car, or nil and a Notify key (nil: say nothing).
local function duelReady(p)
	if p.Parent ~= Players then
		return nil, nil
	end
	local why, car = refuse(p, false)
	if why == "RaceNeedCar" or why == "RaceNeedBoat" then
		why = "RaceChallengeNeedCar"
	end
	if why then
		return nil, why
	end
	if p:GetAttribute("InHome") == true or S.racerOf[p] or S.lobbyOf[p] or p:GetAttribute("RacingId") then
		return nil, "MissionBusy"
	end
	return car, nil
end

-- The nearest driver who could race `player` within `reach` studs (only `only`, when given).
local function nearestRival(player, car, reach, only)
	local here = flat(car.PrimaryPart.Position)
	local best, bestD
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and (only == nil or p == only) then
			local theirs = duelReady(p)
			if theirs then
				local d = (flat(theirs.PrimaryPart.Position) - here).Magnitude
				if d <= reach and (not bestD or d < bestD) then
					best, bestD = p, d
				end
			end
		end
	end
	return best
end

-- Forget every challenge to or from `p` (and close the cards). tellFrom: tell a challenger whose target
-- this was that it's off (p left or lost their body), not when p is just starting a race.
local function dropChallenges(p, tellFrom)
	for target, c in pairs(S.challenges) do
		if target == p or c.from == p then
			S.challenges[target] = nil
			if S.outgoing[c.from] == target then
				S.outgoing[c.from] = nil
			end
			if target.Parent == Players then
				S.raceEvent:FireClient(target, "ChallengeGone", {})
			end
			if tellFrom and target == p and c.from ~= p and c.from.Parent == Players then
				S.raceEvent:FireClient(c.from, "ChallengeAnswer", { Name = p.DisplayName, Answer = "Off" })
			end
		end
	end
	S.outgoing[p] = nil
end

-- A route for two cars (see the header): a race definition the client can draw, or nil.
local function duelRoute(chA, chB)
	local nodes, edges = RoadGraph.Nodes, RoadGraph.Edges
	if #nodes < 2 then
		return nil
	end
	local mid = flat((chA.Position + chB.Position) / 2)
	local facing = flat(chA.CFrame.LookVector) + flat(chB.CFrame.LookVector)
	if facing.Magnitude < 0.5 then
		facing = flat(chA.CFrame.LookVector) -- (facing different ways: the challenger's way)
	end
	facing = facing.Magnitude > 0.01 and facing.Unit or Vector3.zAxis
	-- The start: the nearest crossing ahead of the cars, so the race never begins with a U-turn.
	local start, startD
	for i, n in ipairs(nodes) do
		local off = n - mid
		local d = off.Magnitude
		if d <= K.DUEL_AHEAD and off:Dot(facing) >= -10 and (not startD or d < startD) then
			start, startD = i, d
		end
	end
	start = start or RoadGraph.Nearest(mid)
	if not start then
		return nil
	end
	-- Every crossing within MaxLength studs by road (Dijkstra), with the first crossing of the way there.
	local dist, prev, first = { [start] = 0 }, {}, {}
	local open = { [start] = true }
	local steps = 0
	while steps < 5000 do
		steps += 1
		local cur, cd
		for i in pairs(open) do
			if not cd or dist[i] < cd then
				cur, cd = i, dist[i]
			end
		end
		if not cur or cd > K.DUEL_MAX then
			break
		end
		open[cur] = nil
		for nb, len in pairs(edges[cur] or {}) do
			local nd = cd + len
			if nodes[nb] and (not dist[nb] or nd < dist[nb]) then
				dist[nb] = nd
				prev[nb] = cur
				first[nb] = cur == start and nb or first[cur]
				open[nb] = true
			end
		end
	end
	-- The finish: MinLength..MaxLength away, best the way the cars face (out of the start crossing and
	-- overall), with a little luck so the same spot doesn't always give the same race.
	local from = nodes[start]
	local pick, pickScore
	for i, d in pairs(dist) do
		if d >= K.DUEL_MIN and d <= K.DUEL_MAX and first[i] then
			local away = nodes[i] - from
			local hop = nodes[first[i]] - from
			local score = (away.Magnitude > 1 and away.Unit:Dot(facing) or 0)
				+ 1.5 * (hop.Magnitude > 1 and hop.Unit:Dot(facing) or 0) + S.rng:NextNumber() * 0.8
			if not pickScore or score > pickScore then
				pick, pickScore = i, score
			end
		end
	end
	if not pick then
		-- A small corner of the map: the farthest crossing at least 500 studs away will do.
		for i, d in pairs(dist) do
			if d >= 500 and (not pick or d > dist[pick]) then
				pick = i
			end
		end
	end
	if not pick then
		return nil
	end
	local path = {}
	local n = pick
	while n do
		table.insert(path, 1, nodes[n])
		n = prev[n]
	end
	-- Checkpoints (see the header). `since` = studs from the last checkpoint (the cars, at first).
	local cps = {}
	local since = (from - mid).Magnitude
	for i = 2, #path do
		local a, b = path[i - 1], path[i]
		local len = (b - a).Magnitude
		if len > 0.01 then
			local dir = (b - a) / len
			local at = math.max(K.DUEL_CP_EVERY - since, 40)
			local lastAt
			while at < len - K.DUEL_CP_GAP do
				table.insert(cps, a + dir * at)
				lastAt = at
				at += K.DUEL_CP_EVERY
			end
			since = lastAt and (len - lastAt) or (since + len)
		end
		local last = i == #path
		local bend = false
		if not last then
			local d1, d2 = b - a, path[i + 1] - b
			bend = d1.Magnitude > 0.01 and d2.Magnitude > 0.01 and d1.Unit:Dot(d2.Unit) < K.DUEL_TURN_COS
		end
		if last or (bend and since >= 30) then
			table.insert(cps, b)
			since = 0
		end
	end
	if #cps == 0 then
		return nil
	end
	local length = routeLength(mid, cps)
	return {
		Name = "Street Duel",
		Start = mid,
		Heading = facing,
		Checkpoints = cps,
		Par = math.max(20, math.floor(length / K.DUEL_SPEED + 0.5)),
		Reward = 0,
		ParBonus = 0,
		Duel = true,
	}
end

local function startDuel(a, carA, b, carB)
	local def = duelRoute(carA.PrimaryPart, carB.PrimaryPart)
	if not def then
		S.notify:FireClient(a, "RaceChallengeNoRoute")
		S.notify:FireClient(b, "RaceChallengeNoRoute")
		return
	end
	local sess = newSession("Duel", def, def.Checkpoints, 1, def.Par)
	def.Id = "Duel" .. sess.serial
	for _, e in ipairs({ { a, carA }, { b, carB } }) do
		if hold(e[2], nil, sess.startAt) then
			local r = newRacer(sess, e[1], e[2], e[1].DisplayName)
			S.racerOf[e[1]] = r
			e[1]:SetAttribute("RacingId", def.Id)
		end
	end
	if #sess.racers < 2 then
		-- One car couldn't be held: off for both (free the one that was).
		for _, r in ipairs(sess.racers) do
			freeHuman(r)
		end
		S.notify:FireClient(a, "RaceChallengeOff")
		S.notify:FireClient(b, "RaceChallengeOff")
		return
	end
	local shown = {
		Name = def.Name, Start = def.Start, Heading = def.Heading, Checkpoints = def.Checkpoints, Par = def.Par, Duel = true,
	}
	for i, r in ipairs(sess.racers) do
		S.raceEvent:FireClient(r.player, "Countdown", {
			Id = def.Id, Run = sess.serial, StartAt = sess.startAt, Laps = 1, Of = 2, Def = shown,
			Opponent = sess.racers[3 - i].name,
		})
	end
	run(sess)
end

local function sendChallenge(player, rematch, named)
	local car, why = duelReady(player)
	if not car then
		if why then
			S.notify:FireClient(player, why)
		end
		return
	end
	local waiting = S.outgoing[player]
	local c = waiting and S.challenges[waiting]
	if c and c.from == player and os.clock() - c.at < K.DUEL_EXPIRE then
		S.notify:FireClient(player, "RaceChallengeWait")
		return
	end
	local target
	if rematch then
		local last = S.rematch[player]
		if not last or os.clock() > last.untilAt or last.other ~= named then
			return
		end
		target = nearestRival(player, car, K.DUEL_ACCEPT, named)
		if not target then
			S.notify:FireClient(player, "RaceChallengeGone")
			return
		end
	else
		target = (named and nearestRival(player, car, K.DUEL_REACH, named)) or nearestRival(player, car, K.DUEL_REACH, nil)
		if not target then
			S.notify:FireClient(player, "RaceChallengeNoOne")
			return
		end
	end
	local pending = S.challenges[target]
	if pending and os.clock() - pending.at < K.DUEL_EXPIRE then
		S.notify:FireClient(player, "RaceChallengeBusy")
		return
	end
	local no = S.declined[player] and S.declined[player][target]
	if no and os.clock() - no < K.DUEL_COOLDOWN then
		S.notify:FireClient(player, "RaceChallengeCooldown") -- (a NO is a NO for a little while)
		return
	end
	S.challenges[target] = { from = player, at = os.clock() }
	S.outgoing[player] = target
	S.raceEvent:FireClient(target, "Challenge", {
		FromUserId = player.UserId, FromName = player.DisplayName, Expires = K.DUEL_EXPIRE, Rematch = rematch == true,
	})
	S.raceEvent:FireClient(player, "ChallengeSent", { Name = target.DisplayName, Expires = K.DUEL_EXPIRE })
end

local function answer(player, accept, fromUserId)
	local c = S.challenges[player]
	if not c or (type(fromUserId) == "number" and c.from.UserId ~= fromUserId) then
		return -- (an answer to a card that has since been replaced by somebody else's)
	end
	S.challenges[player] = nil
	local from = c.from
	if S.outgoing[from] == player then
		S.outgoing[from] = nil
	end
	if os.clock() - c.at > K.DUEL_EXPIRE + 1 or from.Parent ~= Players then
		return
	end
	if not accept then
		S.declined[from] = S.declined[from] or setmetatable({}, { __mode = "k" })
		S.declined[from][player] = os.clock()
		S.raceEvent:FireClient(from, "ChallengeAnswer", { Name = player.DisplayName, Answer = "Declined" })
		return
	end
	local carB, whyB = duelReady(player)
	local carA, whyA = duelReady(from)
	if not carB or not carA then
		if not carB and whyB then
			S.notify:FireClient(player, whyB)
		elseif not carB then
			S.notify:FireClient(player, "RaceChallengeOff")
		end
		if not carA then
			S.notify:FireClient(player, "RaceChallengeOff")
			if whyA then
				S.notify:FireClient(from, whyA)
			end
		end
		S.raceEvent:FireClient(from, "ChallengeAnswer", { Name = player.DisplayName, Answer = "Off" })
		return
	end
	if not ((flat(carA.PrimaryPart.Position) - flat(carB.PrimaryPart.Position)).Magnitude <= K.DUEL_ACCEPT) then
		S.notify:FireClient(player, "RaceChallengeFar")
		S.notify:FireClient(from, "RaceChallengeFar")
		S.raceEvent:FireClient(from, "ChallengeAnswer", { Name = player.DisplayName, Answer = "Off" })
		return
	end
	-- A fair start: roughly level along the way they face (nobody accepts from a long way up the road).
	local ca, cb = carA.PrimaryPart, carB.PrimaryPart
	local facing = flat(ca.CFrame.LookVector) + flat(cb.CFrame.LookVector)
	facing = facing.Magnitude > 0.5 and facing.Unit or flat(ca.CFrame.LookVector)
	if math.abs((flat(cb.Position) - flat(ca.Position)):Dot(facing)) > K.DUEL_LEVEL then
		S.notify:FireClient(player, "RaceChallengeLevel")
		S.notify:FireClient(from, "RaceChallengeLevel")
		S.raceEvent:FireClient(from, "ChallengeAnswer", { Name = player.DisplayName, Answer = "Off" })
		return
	end
	-- (crossed challenges between the two, or others waiting on them: all off, cards closed)
	dropChallenges(from, false)
	dropChallenges(player, false)
	S.rematch[from], S.rematch[player] = nil, nil
	startDuel(from, carA, player, carB)
end

local function sweepChallenges()
	local t = os.clock()
	for target, c in pairs(S.challenges) do
		if t - c.at > K.DUEL_EXPIRE then
			S.challenges[target] = nil
			if S.outgoing[c.from] == target then
				S.outgoing[c.from] = nil
			end
			-- (no answer counts like a NO: nobody gets the same card again and again)
			S.declined[c.from] = S.declined[c.from] or setmetatable({}, { __mode = "k" })
			S.declined[c.from][target] = t
			if c.from.Parent == Players then
				S.raceEvent:FireClient(c.from, "ChallengeAnswer", { Name = target.DisplayName, Answer = "Expired" })
			end
			if target.Parent == Players then
				S.raceEvent:FireClient(target, "ChallengeGone", {})
			end
		end
	end
	for p, m in pairs(S.rematch) do
		if t > m.untilAt then
			S.rematch[p] = nil
		end
	end
end

local function onChallenge(player, action, userId)
	if not RateLimit.Allow(player, "RaceChallenge", 1, 3) or type(action) ~= "string" then
		return
	end
	if action == "Challenge" or action == "Rematch" then
		local named = type(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
		sendChallenge(player, action == "Rematch", named)
	elseif action == "Accept" or action == "Decline" then
		answer(player, action == "Accept", userId)
	end
end

------------------------------------------------------------------ the loop and clean-up

-- A player left (leaving = true) or lost their body: out of any race, lobby and challenge.
local function forget(p, leaving)
	local r = S.racerOf[p]
	if r then
		dropRacer(r, (not leaving) and "LeftCar" or nil)
	end
	if S.lobbyOf[p] then
		leaveLobby(p)
	end
	dropChallenges(p, true)
	if leaving then
		S.rematch[p] = nil
	end
end

local function tick()
	local t = now()
	stepLobbies(t)
	for sess in pairs(S.sessions) do
		local ok, err = pcall(stepSession, sess, t)
		if not ok then
			warn("[RaceService] " .. tostring(sess.race and sess.race.Id) .. ": " .. tostring(err))
			pcall(endSession, sess) -- (frees every car it holds)
			S.sessions[sess] = nil
		end
	end
	if os.clock() >= S.nextSweep then
		S.nextSweep = os.clock() + 0.5
		sweepChallenges()
	end
end

local function watchCharacter(p)
	p.CharacterRemoving:Connect(function()
		local ok, err = pcall(forget, p, false)
		if not ok then
			warn("[RaceService] " .. tostring(err))
		end
	end)
end

function RaceService.Init()
	S.raceEvent = Remotes.Event("RaceEvent")
	S.notify = Remotes.Event("Notify")
	Remotes.Event("RaceChallenge").OnServerEvent:Connect(function(player, action, userId)
		local ok, err = pcall(onChallenge, player, action, userId)
		if not ok then
			warn("[RaceService] challenge: " .. tostring(err))
		end
	end)
	local acts = Workspace:FindFirstChild("Activities")
	for _, race in ipairs(Activities.Races) do
		S.racesById[race.Id] = race
		local pad = acts and acts:FindFirstChild("RaceStart_" .. race.Id)
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
				local ok, err = pcall(onPad, player, race, padPos)
				if not ok then
					warn("[RaceService] " .. race.Id .. ": " .. tostring(err))
				end
			end)
		end
		publishBoard(race.Id)
	end
	task.spawn(function()
		while true do
			task.wait(K.TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[RaceService] " .. tostring(err))
			end
		end
	end)
	Players.PlayerAdded:Connect(watchCharacter)
	for _, p in ipairs(Players:GetPlayers()) do
		watchCharacter(p) -- (anyone who joined before this service started: Studio)
	end
	Players.PlayerRemoving:Connect(function(p)
		local ok, err = pcall(forget, p, true)
		if not ok then
			warn("[RaceService] " .. tostring(err))
		end
		S.racerOf[p] = nil
		S.lobbyOf[p] = nil
		S.rematch[p] = nil
		S.declined[p] = nil
	end)
end

return RaceService
