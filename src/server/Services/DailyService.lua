-- DailyService (ModuleScript, ServerScriptService.Services.DailyService)
-- Login streak (PRD "Daily reasons to come back"): the first join of each UTC day pays
-- $1,000 x streak day, up to $7,000 on day 7 and every day after while the streak holds. Missing a
-- day resets to day 1. Reaching day 7 unlocks the streak-only paint (player attribute
-- "Unlock_Streak7", saved in data.flags.streak7).
-- Saved in data.daily = { last = day number, streak = n }.
-- Paid once the save has loaded AND the client says it listens (remote DailyReady from ShopClient),
-- or 60 s after the load, so the DAY N STREAK stamp is never fired before anyone can show it.
-- Shared day helpers for other services (all clock-skew safe: a record only rolls over when the day
-- number is GREATER than the saved one, so a server clock a little behind never pays a day twice):
--   DailyService.Today()               UTC day number
--   DailyService.DayRecord(data, key)  data.flags[key] = { day = today, ... }, a fresh table each new day

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

DailyService.Today = today

function DailyService.DayRecord(data, key)
	data.flags = data.flags or {}
	local rec = data.flags[key]
	local day = today()
	if type(rec) ~= "table" or type(rec.day) ~= "number" or rec.day < day then
		rec = { day = day }
		data.flags[key] = rec
	end
	return rec
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
	-- ShopClient fires DailyReady once it listens for DailyReward (it starts late in ClientMain's
	-- order): paying before that would lose the streak stamp. No word within 60 s: pay anyway.
	local ready = {} -- [player] = true once their client listens
	local waiting = {} -- [player] = data, loaded and waiting for the client
	Remotes.Event("DailyReady").OnServerEvent:Connect(function(player)
		if ready[player] then
			return
		end
		ready[player] = true
		local data = waiting[player]
		waiting[player] = nil
		if data then
			onLoaded(player, data)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		ready[player], waiting[player] = nil, nil
	end)
	DataService.OnLoaded(function(player, data)
		if ready[player] then
			onLoaded(player, data)
			return
		end
		waiting[player] = data
		task.delay(60, function()
			if waiting[player] == data and player.Parent == Players then
				waiting[player] = nil
				onLoaded(player, data)
			end
		end)
	end)
end

return DailyService
