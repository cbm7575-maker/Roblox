-- TutorialService (ModuleScript, ServerScriptService.Services.TutorialService)
-- The first-session guide (Config.Tutorial). Progress is the saved number data.flags.tutorial,
-- mirrored to the player attribute "TutorialStep" (0 = not started ... #Steps = finished).
--   * The client reports the steps it can see (opened the phone, sat in its car); the server checks
--     what it can (the bag for "rob", banking for the last step) and only ever moves forward by one.
--   * Finishing pays a one-time welcome bonus.
-- Remote: TutorialStep(step) client -> server; "Skip" (string) ends it early without the bonus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local TutorialService = {}

local function current(player)
	local data = DataService.Get(player)
	if not data then
		return nil, nil
	end
	data.flags = data.flags or {}
	return data.flags.tutorial or 0, data
end

local Telemetry = require(ServerScriptService.Services.Telemetry)

-- Onboarding funnel: 1 Joined, 2 PickedSide, then 3.. the tutorial steps.
local FUNNEL_OFFSET = 2

local function set(player, data, step)
	data.flags.tutorial = step
	player:SetAttribute("TutorialStep", step)
	Telemetry.Funnel(player, FUNNEL_OFFSET + step, "Tutorial_" .. Tutorial.Steps[step].Id)
	if step >= #Tutorial.Steps and not data.flags.tutorialPaid then
		data.flags.tutorialPaid = true
		EconomyService.AddCash(player, Tutorial.Bonus, "tutorial")
		Remotes.Event("TutorialDone"):FireClient(player, Tutorial.Bonus)
	end
end

-- Try to complete step `step` (1-based: finishing step 1 moves progress from 0 to 1).
local function advance(player, step, fromServer)
	local done, data = current(player)
	if not data or step ~= done + 1 or step > #Tutorial.Steps then
		return
	end
	local def = Tutorial.Steps[step]
	if def.ServerOnly and not fromServer then
		return
	end
	if def.Id == "rob" and (player:GetAttribute("Carried") or 0) <= 0 and not fromServer then
		return
	end
	set(player, data, step)
end

function TutorialService.Advance(player, stepId)
	for i, def in ipairs(Tutorial.Steps) do
		if def.Id == stepId then
			advance(player, i, true)
			return
		end
	end
end

function TutorialService.Init()
	Remotes.Event("TutorialDone") -- create it now: clients wait for it at start-up
	Remotes.Event("TutorialStep").OnServerEvent:Connect(function(player, step)
		if not RateLimit.Allow(player, "Tutorial", 2, 4) then
			return
		end
		if step == "Skip" then
			local _, data = current(player)
			if data then
				data.flags.tutorial = #Tutorial.Steps
				data.flags.tutorialPaid = true -- skipping forfeits the bonus
				player:SetAttribute("TutorialStep", #Tutorial.Steps)
			end
			return
		end
		if type(step) == "number" then
			advance(player, math.floor(step), false)
		end
	end)
	EconomyService.OnBanked(function(player)
		TutorialService.Advance(player, "bank")
	end)
	DataService.OnLoaded(function(player)
		local done = current(player)
		player:SetAttribute("TutorialStep", done or 0)
		if (done or 0) == 0 then
			Telemetry.Funnel(player, 1, "Joined")
			local conn
			conn = player:GetAttributeChangedSignal("HasPicked"):Connect(function()
				if player:GetAttribute("HasPicked") then
					conn:Disconnect()
					Telemetry.Funnel(player, 2, "PickedSide")
				end
			end)
		end
	end)
end

return TutorialService
