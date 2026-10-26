-- DailyService (ModuleScript, ServerScriptService.Services.DailyService)
-- Login streak (PRD "Daily reasons to come back"): the first join of each UTC day pays
-- $1,000 x streak day, up to $7,000 on day 7 and every day after while the streak holds. Missing a
-- day resets to day 1. Reaching day 7 unlocks the streak-only paint (player attribute
-- "Unlock_Streak7", saved in data.flags.streak7).
-- Saved in data.daily = { last = day number, streak = n }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local DailyService = {}

local PER_DAY = 1000
local MAX_DAY = 7

local function today()
	return math.floor(os.time() / 86400)
end

local function onLoaded(player, data)
	data.daily = data.daily or {}
	data.flags = data.flags or {}
	if data.flags.streak7 then
		player:SetAttribute("Unlock_Streak7", true)
	end
	local day = today()
	local last = data.daily.last
	if last and last >= day then -- already paid today (>= also covers a server clock a little behind)
		player:SetAttribute("Streak", data.daily.streak or 1)
		return
	end
	local streak = (last == day - 1) and ((data.daily.streak or 0) + 1) or 1
	data.daily.last = day
	data.daily.streak = streak
	player:SetAttribute("Streak", streak)
	local cash = PER_DAY * math.min(streak, MAX_DAY)
	EconomyService.AddCash(player, cash, "daily:day" .. math.min(streak, MAX_DAY))
	local unlocked = false
	if streak >= MAX_DAY and not data.flags.streak7 then
		data.flags.streak7 = true
		player:SetAttribute("Unlock_Streak7", true)
		unlocked = true
	end
	DataService.SaveNow(player)
	Remotes.Event("DailyReward"):FireClient(player, {
		Streak = streak, Cash = cash, Next = PER_DAY * math.min(streak + 1, MAX_DAY), Unlocked = unlocked,
	})
end

function DailyService.Init()
	Remotes.Event("DailyReward")
	DataService.OnLoaded(function(player, data)
		-- Wait until they've pressed PLAY (HasPicked) so the reward isn't hidden behind the title screen.
		for _ = 1, 120 do
			if player:GetAttribute("HasPicked") or player.Parent ~= Players then
				break
			end
			task.wait(0.5)
		end
		if player.Parent == Players then
			onLoaded(player, data)
		end
	end)
end

return DailyService
