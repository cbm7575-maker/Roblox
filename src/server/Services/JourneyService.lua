-- JourneyService (ModuleScript, ServerScriptService.Services.JourneyService)
-- "Road to the Coast" (Config.Journey): the goal chains that carry new players on after the tutorial,
-- one goal at a time on TutorialClient's NEXT pill, each paying a small cash reward.
--   * New players only: a save that loads brand new (tutorial not started, no XP on either side) gets
--     data.flags.journey = { civ, cop = goals done; civP, copP = progress on the current goal;
--     civId, copId = the next goal's Id; seen = police actions already done; off = hidden }.
--     Saves from before this shipped never get one, so veterans never see the goals. The tutorial's
--     save is moved to its current step order first (TutorialService.Migrate), whatever the order
--     the services' load listeners run in.
--   * Mirrored to the player attributes JourneyStep / JourneyProgress (free roam) and JourneyCopStep /
--     JourneyCopProgress (police); all nil for players without goals or who hid them. JourneyHidden
--     is true while a player's goals are hidden.
--   * The free-roam chain waits until the tutorial is finished or skipped (data.flags.tutorial); the
--     police chain runs from the first shift. Only the current goal of each chain counts anything.
--   * Progress comes from ProgressService events (ProgressService.OnEvent), matched on the goal's Kind
--     (and Min: the heist's tier). Some goals also count as done from what the save shows: rank goals,
--     Paint / BuyCar / BuyHome (a painted car, a bought car, a home), BuyGun (a gun in data.gear.guns,
--     CombatService: Coast Arms sets the "Guns" attribute after a purchase, which brings the check),
--     Heist (a big heist in BigHeists, which crewmates who helped get too) and the police actions that
--     need a wanted robber (TaserHit, SpikeHit, Arrest: remembered in `seen` when they happen early).
--     Checked on load, after every event, and when the rank, owned cars, car styles, guns, home, big
--     heists or tutorial step change.
--   * A finished goal pays its Reward (EconomyService.AddCash, reason "journey:<Id>"), is logged
--     (free roam: onboarding funnel step 7 on, after TutorialService's 1-6; police: custom event
--     JourneyCop_<Id>) and fires JourneyDone { Cop, Index, Total, Reward } to the player for the stamp.
--   * The save keeps a count of goals done. It also keeps the next goal's Id, and on load the count
--     follows that Id if an update put new goals before it (Config.Journey: never reorder goals). A
--     chain with no next Id was finished: it stays finished when goals are added (its count goes to the
--     list's end), so a new goal never comes round for players who were done.
-- Remote: JourneyStep("Hide") client -> server hides the goals (the pill's X, tapped twice);
--   JourneyStep("Show") brings them back where they were (for a button in PHONE > GOALS).
-- JourneyService.Reset(player) starts the goals over (testing with an old save, from the command bar).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Journey = require(ReplicatedStorage.Shared.Config.Journey)
local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Heists = require(ReplicatedStorage.Shared.Config.Heists)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local ProgressService = require(ServerScriptService.Services.ProgressService)
local TutorialService = require(ServerScriptService.Services.TutorialService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local JourneyService = {}

-- Onboarding funnel: TutorialService logs 1 Joined, 2 PickedSide and 3.. its steps; the goals follow.
local FUNNEL_START = 2 + #Tutorial.Steps

local CHAINS = {
	{ key = "civ", progress = "civP", id = "civId", list = Journey.Civ, stepAttr = "JourneyStep",
		progressAttr = "JourneyProgress" },
	{ key = "cop", progress = "copP", id = "copId", list = Journey.Cop, stepAttr = "JourneyCopStep",
		progressAttr = "JourneyCopProgress" },
}

local RANK_KINDS = { CivRank = true, CopRank = true }

-- Police actions that need a wanted robber (there are no AI robbers): one that happens before its goal
-- comes up is remembered, and the goal completes as soon as it's reached.
local REMEMBER = { TaserHit = true, SpikeHit = true, Arrest = true }

-- Player attributes whose change can finish a goal without an event (see stateDone). "Custom_<car>"
-- (a car's paint, glow and rims, GarageService) is matched by its prefix.
local WATCH = { CivRank = true, CopRank = true, OwnedCars = true, Home = true, BigHeists = true, TutorialStep = true,
	Guns = true }

local doneRemote

local function fresh()
	return { civ = 0, cop = 0, civP = 0, copP = 0, civId = Journey.Civ[1].Id, copId = Journey.Cop[1].Id }
end

-- The player's goals and save, or nil when they have none (or hid them).
local function journey(player)
	local data = DataService.Get(player)
	local j = data and data.flags and data.flags.journey
	if type(j) ~= "table" or j.off then
		return nil, nil
	end
	return j, data
end

-- The goal a chain is on, or nil: chain finished, or free roam still in the tutorial.
local function currentDef(data, j, chain)
	if chain.key == "civ" and (data.flags.tutorial or 0) < #Tutorial.Steps then
		return nil
	end
	return chain.list[(j[chain.key] or 0) + 1]
end

local function mirror(player, j)
	for _, chain in ipairs(CHAINS) do
		player:SetAttribute(chain.stepAttr, j and (j[chain.key] or 0) or nil)
		player:SetAttribute(chain.progressAttr, j and (j[chain.progress] or 0) or nil)
	end
end

-- Goals the save can show done without an event: a rank reached, a painted car, a bought car or home
-- (bought before the goal came up, or while a purchase event went missing), a big heist, or a police
-- action that happened before its goal came up.
local function stateDone(player, data, j, def)
	if def.Goal == 1 and not def.Min and type(j.seen) == "table" and j.seen[def.Kind] then
		return true
	end
	if RANK_KINDS[def.Kind] then
		return (player:GetAttribute(def.Kind) or 1) >= def.Goal
	elseif def.Kind == "Paint" then
		for _, c in pairs(data.custom or {}) do
			if type(c) == "table" and (c.paint or 0) > 0 then
				return true
			end
		end
	elseif def.Kind == "BuyCar" then
		for id, owned in pairs(data.owned or {}) do
			local car = Vehicles.ById[id]
			if owned and car and (car.Price or 0) > 0 then -- starter cars cost nothing
				return true
			end
		end
	elseif def.Kind == "BuyHome" then
		return data.home ~= nil
	elseif def.Kind == "BuyGun" then
		-- Any citizen gun bought at Coast Arms (or the old Stun Blaster, which CombatService turns into the
		-- Pistol when the save loads).
		local gear = data.gear
		if type(gear) == "table" then
			if gear.blaster == true then
				return true
			end
			for _, owned in pairs(type(gear.guns) == "table" and gear.guns or {}) do
				if owned == true then
					return true
				end
			end
		end
	elseif def.Kind == "Tune" then
		-- A stage or an exhaust bought before this goal came up (GarageService's data.custom[car]).
		for _, c in pairs(data.custom or {}) do
			if type(c) == "table" then
				if type(c.exhausts) == "table" and next(c.exhausts) ~= nil then
					return true
				end
				if type(c.tune) == "table" then
					for _, stage in pairs(c.tune) do
						if type(stage) == "number" and stage > 0 then
							return true
						end
					end
				end
			end
		end
	elseif def.Kind == "Heist" and (def.Min or 1) <= Heists.BigTier then
		-- HeistService's saved BigHeists: the robber of a Coastal Bank / Sea Dream job, and the crewmates
		-- who helped nearby (they get no Heist event of their own). No goal asks for a bigger heist.
		return (player:GetAttribute("BigHeists") or 0) > 0
	end
	return false
end

local function complete(player, j, chain)
	local index = (j[chain.key] or 0) + 1
	local def = chain.list[index]
	j[chain.key] = index
	j[chain.progress] = 0
	local nextDef = chain.list[index + 1]
	j[chain.id] = nextDef and nextDef.Id or nil
	EconomyService.AddCash(player, def.Reward or 0, "journey:" .. def.Id)
	if chain.key == "civ" then
		Telemetry.Funnel(player, FUNNEL_START + index, "Journey_" .. def.Id)
	else
		Telemetry.Custom(player, "JourneyCop_" .. def.Id, index)
	end
	doneRemote:FireClient(player, { Cop = chain.key == "cop", Index = index, Total = #chain.list, Reward = def.Reward or 0 })
end

-- Finish every goal the save already shows done (a chain can move on several at once), then mirror.
local function check(player)
	local j, data = journey(player)
	if not j then
		return
	end
	for _, chain in ipairs(CHAINS) do
		local def = currentDef(data, j, chain)
		while def and stateDone(player, data, j, def) do
			complete(player, j, chain)
			def = currentDef(data, j, chain)
		end
	end
	mirror(player, j)
end

-- A ProgressService event: counts toward the current goal of each chain whose Kind it is.
local function onEvent(player, kind, amount)
	local j, data = journey(player)
	if not j then
		return
	end
	amount = tonumber(amount) or 1
	if REMEMBER[kind] then
		j.seen = type(j.seen) == "table" and j.seen or {}
		j.seen[kind] = true
	end
	for _, chain in ipairs(CHAINS) do
		local def = currentDef(data, j, chain)
		if def and def.Kind == kind and (not def.Min or amount >= def.Min) then
			-- One per event (a race finished over par reports 0), or the points themselves (Sum).
			local add = def.Sum and math.max(0, math.floor(amount)) or 1
			j[chain.progress] = math.min(def.Goal, (j[chain.progress] or 0) + add)
			if j[chain.progress] >= def.Goal then
				complete(player, j, chain)
			end
		end
	end
	check(player) -- also finishes a remembered police action whose goal just came up
end

-- If an update put new goals before a player's next goal, put their count where that goal is now (the
-- new ones before it are skipped, unpaid). A chain with no next goal was finished: it stays finished
-- (a goal added since must not come round, nor one already done move up into the gap).
local function followIds(j)
	for _, chain in ipairs(CHAINS) do
		local id = j[chain.id]
		if type(id) == "string" then
			for i, def in ipairs(chain.list) do
				if def.Id == id then
					-- (Same goal, new place in the list: its progress so far stays.)
					j[chain.key] = i - 1
					break
				end
			end
		elseif id == nil and (j[chain.key] or 0) > 0 and (j[chain.key] or 0) < #chain.list then
			j[chain.key] = #chain.list
			j[chain.progress] = 0
		end
	end
end

function JourneyService.Reset(player)
	local data = DataService.Get(player)
	if not data then
		return
	end
	data.flags = data.flags or {}
	data.flags.journey = fresh()
	player:SetAttribute("JourneyHidden", nil)
	check(player)
end

function JourneyService.Init()
	doneRemote = Remotes.Event("JourneyDone")
	Remotes.Event("JourneyStep").OnServerEvent:Connect(function(player, action)
		if not RateLimit.Allow(player, "Journey", 1, 2) or (action ~= "Hide" and action ~= "Show") then
			return
		end
		local data = DataService.Get(player)
		local j = data and data.flags and data.flags.journey
		if type(j) ~= "table" then
			return -- never had goals (a veteran): nothing to hide or show
		end
		if action == "Hide" and not j.off then
			j.off = true
			mirror(player, nil)
			player:SetAttribute("JourneyHidden", true)
			Telemetry.Custom(player, "JourneyHidden", j.civ or 0)
		elseif action == "Show" and j.off then
			j.off = nil
			player:SetAttribute("JourneyHidden", nil)
			Telemetry.Custom(player, "JourneyShown", j.civ or 0)
			check(player)
		end
	end)
	ProgressService.OnEvent(onEvent)
	DataService.OnLoaded(function(player, data)
		TutorialService.Migrate(data) -- data.flags.tutorial in the current step order before the check below
		local xp = data.xp or {}
		if data.flags.journey == nil and (data.flags.tutorial or 0) == 0 and (xp.civilian or 0) == 0
			and (xp.cop or 0) == 0 then
			data.flags.journey = fresh()
		end
		local j = data.flags.journey
		if type(j) == "table" then
			followIds(j)
			player:SetAttribute("JourneyHidden", j.off and true or nil)
		end
		player.AttributeChanged:Connect(function(name)
			if WATCH[name] or string.sub(name, 1, 7) == "Custom_" or string.sub(name, 1, 5) == "Tune_" then
				check(player)
			end
		end)
		mirror(player, (journey(player)))
		check(player)
	end)
end

return JourneyService
