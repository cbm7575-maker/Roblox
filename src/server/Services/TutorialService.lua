-- TutorialService (ModuleScript, ServerScriptService.Services.TutorialService)
-- The first-session guide (Config.Tutorial). Progress is saved by step Id: data.flags.tutorialSteps
-- ({ car = true, ... }), and data.flags.tutorialDone = true once it's finished or skipped.
--   * v1 saves (a step NUMBER in data.flags.tutorial, for the old order) are migrated once: finished
--     stays finished; "phone" and "car" carry over. A v1 "rob" doesn't: bags are never saved.
--   * The server checks what it can: a bag (rob), the heat clearing with the bag still full (escape),
--     banking (bank, which also proves rob and escape). The client reports "car" (re-checked here:
--     sitting in a driver seat) and "phone".
--   * Steps done early count. If the bag empties before it's banked (arrested, left the game), rob and
--     escape are undone, so the guide never says "bank your bag" with an empty bag.
--   * Finishing pays a one-time welcome bonus; skipping forfeits it.
-- Player attributes: TutorialStep (Id of the step to do now, or "done"), TutorialSteps (comma list of
--   done Ids), TutorialChase (true from a tutorial player's first heat until they bank or the tutorial
--   ends, otherwise nil: AIPoliceService sends a gentle chaser).
-- Remote: TutorialStep(id) client -> server ("car" / "phone"); "Skip" ends it early.
-- Funnel (Telemetry.Funnel): 1 Joined, 2 PickedSide, then 2 + i = "Tutorial_<Id>" for step i of
--   Config.Tutorial, logged in order as the guide moves past each step (data.flags.tutorialFunnel).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local TutorialService = {}

local FUNNEL_OFFSET = 2 -- funnel steps 1 Joined and 2 PickedSide come first
local CLIENT_STEPS = { car = true, phone = true }
local NO_HEAT_GRACE = 12 -- a bag and still no heat after this long (a quiet car boost): escape counts

local pending = {} -- [player] = true while an evaluate is scheduled
local robbedAt = {} -- [player] = os.clock() when "rob" counted
local sawHeat = {} -- [player] = true once wanted after robbing
local lostBag = {} -- [player] = true: tell them to rob again once they're free
local notify

-- The saved progress, migrating a v1 save the first time. Returns flags, steps (nil before the load).
local function progress(player)
	local data = DataService.Get(player)
	if not data then
		return nil, nil
	end
	data.flags = data.flags or {}
	local f = data.flags
	if type(f.tutorialSteps) ~= "table" then
		local steps = {}
		local old = tonumber(f.tutorial) or 0
		if old >= #Tutorial.OldOrder or f.tutorialPaid then
			f.tutorialDone = true
		else
			for i = 1, math.min(old, 2) do -- v1 order: phone, car, rob, bank
				steps[Tutorial.OldOrder[i]] = true
			end
		end
		f.tutorialSteps = steps
		-- v1 already logged funnel steps 3 .. 2 + old under its own names: don't log those numbers again.
		f.tutorialFunnel = f.tutorialFunnel or math.floor(math.clamp(old, 0, #Tutorial.Steps))
	end
	return f, f.tutorialSteps
end

local function currentIndex(steps)
	for i, def in ipairs(Tutorial.Steps) do
		if not steps[def.Id] then
			return i
		end
	end
	return nil
end

local function setAttr(player, name, value)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

local function setChase(player, on)
	setAttr(player, "TutorialChase", on or nil)
end

local function finish(player, f, skipped)
	f.tutorialDone = true
	f.tutorial = #Tutorial.OldOrder -- an older server reading this save sees "finished" too
	setChase(player, false)
	if skipped then
		f.tutorialPaid = true
		Telemetry.Custom(player, "TutorialSkipped", f.tutorialFunnel or 0)
	elseif not f.tutorialPaid then
		f.tutorialPaid = true
		EconomyService.AddCash(player, Tutorial.Bonus, "tutorial")
		Remotes.Event("TutorialDone"):FireClient(player, Tutorial.Bonus)
	end
end

-- Log the funnel for the steps the guide has moved past, finish when all are done, mirror attributes.
local function publish(player)
	local f, steps = progress(player)
	if not f then
		return
	end
	if not f.tutorialDone then
		local idx = currentIndex(steps)
		local passed = (idx or (#Tutorial.Steps + 1)) - 1
		for i = (f.tutorialFunnel or 0) + 1, passed do
			Telemetry.Funnel(player, FUNNEL_OFFSET + i, "Tutorial_" .. Tutorial.Steps[i].Id)
		end
		f.tutorialFunnel = math.max(f.tutorialFunnel or 0, passed)
		if not idx then
			finish(player, f, false)
		end
	end
	local list = {}
	for _, def in ipairs(Tutorial.Steps) do
		if f.tutorialDone or steps[def.Id] then
			table.insert(list, def.Id)
		end
	end
	local idx = not f.tutorialDone and currentIndex(steps)
	setAttr(player, "TutorialSteps", table.concat(list, ","))
	setAttr(player, "TutorialStep", idx and Tutorial.Steps[idx].Id or "done")
end

local function credit(player, id)
	local f, steps = progress(player)
	if not f or f.tutorialDone or steps[id] then
		return false
	end
	steps[id] = true
	if id == "rob" then
		robbedAt[player], sawHeat[player] = os.clock(), nil
	end
	return true
end

local schedule

-- Re-check the bag and heat (runs a moment after they change, so a bank or an arrest has settled).
local function evaluate(player)
	local f, steps = progress(player)
	if not f then
		return
	end
	if f.tutorialDone then
		setChase(player, false)
		return
	end
	local side = player:GetAttribute("Side")
	local carried = player:GetAttribute("Carried") or 0
	local heat = player:GetAttribute("Heat") or 0
	if side == "Civilian" and carried > 0 and not steps.rob then
		credit(player, "rob")
	end
	if steps.rob and not steps.bank then
		if carried <= 0 then
			-- The bag was emptied before banking (arrest, rejoin): rob again rather than "bank nothing".
			-- Say so only if the bar was talking about the bag (and the player is past the role picker).
			local idx = currentIndex(steps)
			local about = idx and (Tutorial.Steps[idx].Id == "escape" or Tutorial.Steps[idx].Id == "bank")
			steps.rob, steps.escape = nil, nil
			robbedAt[player], sawHeat[player] = nil, nil
			if about and player:GetAttribute("HasPicked") then
				lostBag[player] = true
			end
		elseif heat > 0 then
			sawHeat[player] = true
		elseif side == "Civilian" and not steps.escape then
			local since = os.clock() - (robbedAt[player] or 0)
			if sawHeat[player] or since >= NO_HEAT_GRACE then
				credit(player, "escape")
			else
				task.delay(NO_HEAT_GRACE - since + 0.2, schedule, player)
			end
		end
	end
	if lostBag[player] and side == "Civilian" then
		lostBag[player] = nil
		notify:FireClient(player, "TutorialBagLost")
	end
	if steps.bank then
		setChase(player, false)
	elseif heat > 0 and side == "Civilian" then
		setChase(player, true)
	elseif side == "Cop" then
		setChase(player, false)
	end
	publish(player)
end

schedule = function(player, delay)
	if pending[player] then
		return
	end
	pending[player] = true
	task.delay(delay or 0.5, function()
		pending[player] = nil
		if player.Parent == Players then
			local ok, err = pcall(evaluate, player)
			if not ok then
				warn("[TutorialService] " .. tostring(err))
			end
		end
	end)
end

local function inDriverSeat(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local vehicles = Workspace:FindFirstChild("Vehicles")
	return seat ~= nil and seat:IsA("VehicleSeat") and seat.Name == "DriverSeat" and vehicles ~= nil
		and seat:IsDescendantOf(vehicles)
end

-- Complete a step from another service (TutorialService.Advance(player, "rob")).
function TutorialService.Advance(player, stepId)
	local known = false
	for _, def in ipairs(Tutorial.Steps) do
		known = known or def.Id == stepId
	end
	if known and credit(player, stepId) then
		publish(player)
	end
end

function TutorialService.Init()
	notify = Remotes.Event("Notify")
	Remotes.Event("TutorialDone") -- create it now: clients wait for it at start-up
	Remotes.Event("TutorialStep").OnServerEvent:Connect(function(player, step)
		if not RateLimit.Allow(player, "Tutorial", 2, 4) or type(step) ~= "string" then
			return
		end
		local f = progress(player)
		if not f or f.tutorialDone then
			return
		end
		if step == "Skip" then
			finish(player, f, true)
			publish(player)
			return
		end
		if not CLIENT_STEPS[step] or player:GetAttribute("Side") == "Prisoner" then
			return
		end
		if step == "car" and not inDriverSeat(player) then
			return
		end
		if credit(player, step) then
			publish(player)
		end
	end)
	EconomyService.OnBanked(function(player)
		local f, steps = progress(player)
		if not f or f.tutorialDone then
			return
		end
		-- Banking a bag proves the robbery and the getaway too.
		steps.rob, steps.escape, steps.bank = true, true, true
		lostBag[player] = nil
		setChase(player, false)
		publish(player)
	end)
	DataService.OnLoaded(function(player)
		local f, steps = progress(player)
		if not f then
			return
		end
		for _, name in ipairs({ "Carried", "Heat", "Side" }) do
			player:GetAttributeChangedSignal(name):Connect(function()
				schedule(player)
			end)
		end
		publish(player)
		schedule(player)
		if not f.tutorialDone and next(steps) == nil then
			Telemetry.Funnel(player, 1, "Joined")
			if player:GetAttribute("HasPicked") then -- picked before the save finished loading
				Telemetry.Funnel(player, 2, "PickedSide")
				return
			end
			local conn
			conn = player:GetAttributeChangedSignal("HasPicked"):Connect(function()
				if player:GetAttribute("HasPicked") then
					conn:Disconnect()
					Telemetry.Funnel(player, 2, "PickedSide")
				end
			end)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		pending[player], robbedAt[player], sawHeat[player], lostBag[player] = nil, nil, nil, nil
	end)
end

return TutorialService
