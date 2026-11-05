-- DataService (ModuleScript, ServerScriptService.Services.DataService)
-- Saves each player's progress in a DataStore (one record per player, key "p_<UserId>").
--   * Load with retries and a session lock (a record another server touched in the last 5 minutes is
--     retried for about 20 s, so that server's last save can land, then taken over), autosave every
--     60 s, save once on leave or on shutdown (a failed leave save is retried for about half a minute).
--   * Before the place is published (Studio without API access) it falls back to memory, so testing
--     still works; a Studio session then starts everyone fresh. ReplicatedStorage attribute SavesOff
--     says which (true = memory only, false = really saving), so HUDController can tell the tester.
--   * Carried cash is never saved: leaving with a full bag is like getting caught.
-- Saved: cash, look (hat/mask), stats, owned cars and car customisations (garage, phase 4), XP and
-- ranks (phase 4), daily streak (phase 4), one-time flags.
-- Stats (STATS) live on the player as attributes while playing (e.g. "Heists", and "BigHeists": the
-- Coastal Bank / Sea Dream jobs that unlock the heist-locked cars) and are copied back on every save.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local EconomyService = require(ServerScriptService.Services.EconomyService)

local DataService = {}

local VERSION = 1
local AUTOSAVE = 60
local LOCK_TIMEOUT = 300
local LOCK_TRIES = 6 -- load attempts while another server holds the lock; the last one takes it over
local LOCK_WAIT = 4 -- seconds between them
local LEAVE_RETRIES = { 5, 10, 15 } -- seconds before each extra try of a leave save that failed
local STATS = { "Heists", "Escapes", "Arrests", "TimesCaught", "Breakouts", "CarsBoosted", "Evasions", "RacesWon", "BigHeists" }

local store
local memory = {} -- fallback when DataStores are unavailable
local useMemory = false
local profiles = {} -- [player] = data table
local leaving = setmetatable({}, { __mode = "k" }) -- [player] = true once their last save has started
local jobId = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))

local function default()
	return {
		version = VERSION,
		cash = 0,
		look = { hat = "none", mask = "none" },
		stats = {},
		owned = {},
		custom = {},
		xp = { civilian = 0, cop = 0 },
		daily = {},
		flags = {},
		races = {}, -- [raceId] = best time in seconds
		stunts = {}, -- [stuntId] = true once completed
		gear = { guns = {}, armor = 0 }, -- owned guns ([id] = true) and body armor 0-100 (CombatService)
		-- Empire (BusinessService): [businessId] = { level, register, lifetime, jobsDone, boughtAt }, and the
		-- Empire XP. Old saves get these two from migrate() below, so they load with no businesses.
		businesses = {},
		empireXP = 0,
	}
end

-- Fill in anything missing (older records, new fields).
local function migrate(data)
	local base = default()
	for k, v in pairs(base) do
		if data[k] == nil then
			data[k] = v
		end
	end
	data.version = VERSION
	return data
end

local function retry(fn, tries)
	local lastErr
	for i = 1, tries or 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(i)
	end
	return false, lastErr
end

local function key(player)
	return "p_" .. player.UserId
end

local function load(player)
	if useMemory then
		return migrate(memory[key(player)] or default())
	end
	for attempt = 1, LOCK_TRIES do
		local stolen = attempt == LOCK_TRIES
		local lockedElsewhere = false
		local ok, result = retry(function()
			return store:UpdateAsync(key(player), function(old)
				old = old or default()
				local lock = old.lock
				if lock and lock.job ~= jobId and os.time() - (lock.time or 0) < LOCK_TIMEOUT and not stolen then
					lockedElsewhere = true
					return nil -- leave it alone for now
				end
				old.lock = { job = jobId, time = os.time() }
				return old
			end)
		end)
		if not ok then
			warn("[DataService] load failed for " .. player.Name .. ": " .. tostring(result))
			return nil
		end
		if not lockedElsewhere then
			return migrate(result)
		end
		task.wait(LOCK_WAIT)
	end
	return nil
end

-- Give the lock back without writing anything else (a player who left while their save was loading).
local function unlock(player)
	pcall(function()
		store:UpdateAsync(key(player), function(old)
			if old and old.lock and old.lock.job == jobId then
				old.lock = nil
				return old
			end
			return nil
		end)
	end)
end

-- Pull the live values (player attributes) into the profile.
local function collect(player, data)
	data.cash = EconomyService.GetCash(player)
	data.look = { hat = player:GetAttribute("LookHat") or "none", mask = player:GetAttribute("LookMask") or "none" }
	for _, s in ipairs(STATS) do
		data.stats[s] = player:GetAttribute(s) or data.stats[s] or 0
	end
	return data
end

-- Returns saved, cancelled (another server owns the record: trying again won't help).
-- again = a retry of a leave save: its values were already collected.
local function save(player, release, again)
	local data = profiles[player]
	if not data then
		return
	end
	if not again then
		collect(player, data)
	end
	if useMemory then
		memory[key(player)] = data
		return true
	end
	local cancelled = false
	local ok, err = retry(function()
		cancelled = false
		store:UpdateAsync(key(player), function(old)
			if old and old.lock and old.lock.job ~= jobId then
				cancelled = true
				return nil -- another server owns this record now; don't clobber it
			end
			-- Decided as it's written: a save that lands after the player's last save started (an
			-- autosave or SaveNow in flight, or retried) must not lock the record again, or their next
			-- join waits for the lock to be taken over.
			local keepLock = not release and not leaving[player]
			data.lock = keepLock and { job = jobId, time = os.time() } or nil
			return data
		end)
	end)
	if not ok then
		warn("[DataService] save failed for " .. player.Name .. ": " .. tostring(err))
	elseif cancelled then
		warn("[DataService] save skipped for " .. player.Name .. ": another server holds the lock")
	end
	-- Only a real write counts (ProcessReceipt relies on this).
	return ok and not cancelled, ok and cancelled
end

-- The last save of a player who is leaving (or of everyone at shutdown): once per player, retried a few
-- times if the DataStore is down for a moment, then the profile is dropped.
local function saveAndRelease(player)
	if leaving[player] or not profiles[player] then
		return
	end
	leaving[player] = true -- the autosave loop must not re-take the lock mid-release
	local saved, cancelled = save(player, true)
	for _, seconds in ipairs(LEAVE_RETRIES) do
		if saved or cancelled then
			break
		end
		task.wait(seconds)
		saved, cancelled = save(player, true, true)
	end
	if not saved and not cancelled then
		warn("[DataService] gave up saving " .. player.Name .. " after " .. (#LEAVE_RETRIES + 1) .. " tries")
	end
	profiles[player] = nil
end

-- Push the saved values onto the player (attributes and leaderstats).
local function apply(player, data)
	EconomyService.SetCash(player, data.cash or 0)
	player:SetAttribute("LookHat", data.look and data.look.hat or "none")
	player:SetAttribute("LookMask", data.look and data.look.mask or "none")
	for _, s in ipairs(STATS) do
		player:SetAttribute(s, data.stats[s] or 0)
	end
end

function DataService.Get(player)
	return profiles[player]
end

function DataService.IsLoaded(player)
	return profiles[player] ~= nil
end

-- fn(player, data) runs once each player's save has loaded (right away for players already loaded).
-- Use this instead of polling: a load can take a while when the last server didn't release its lock.
local loadedListeners = {}
function DataService.OnLoaded(fn)
	table.insert(loadedListeners, fn)
	for player, data in pairs(profiles) do
		task.spawn(fn, player, data)
	end
end

function DataService.SaveNow(player)
	return save(player, false)
end

function DataService.Init()
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore("NeonCoast_Players_v1")
	end)
	store = ok and s or nil
	if not store then
		useMemory = true
	elseif RunService:IsStudio() then
		-- Unpublished places can't reach DataStores; test once and fall back to memory.
		local probe = pcall(function()
			store:GetAsync("probe")
		end)
		useMemory = not probe
	end
	if useMemory then
		warn("[DataService] DataStores unavailable - using memory; progress won't persist. In Studio: publish the"
			.. " place and turn on Game Settings > Security > Enable Studio Access to API Services.")
	end
	-- Clients show a one-time "progress isn't saved" note when this is true (HUDController).
	ReplicatedStorage:SetAttribute("SavesOff", useMemory)

	local function onPlayer(player)
		local data = load(player)
		if player.Parent ~= Players then
			if data and not useMemory then
				unlock(player) -- left while it loaded: nothing changed, so just give the lock back
			end
			return
		end
		if not data then
			-- Never play on a blank profile that could overwrite real progress.
			player:Kick("Couldn't load your save right now. Please rejoin in a minute!")
			return
		end
		profiles[player] = data
		apply(player, data)
		player:SetAttribute("DataLoaded", true)
		for _, fn in ipairs(loadedListeners) do
			task.spawn(fn, player, data)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, p)
	end

	Players.PlayerRemoving:Connect(saveAndRelease)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for player in pairs(profiles) do
				if not leaving[player] and player.Parent == Players then
					task.spawn(save, player, false)
				end
			end
		end
	end)

	-- Shutdown: PlayerRemoving may already be saving some of these; saveAndRelease starts each player's
	-- last save only once (two writes to one key within 6 s would queue the second), and a profile is
	-- dropped once its save is done, so waiting for the table to empty waits for all of them.
	game:BindToClose(function()
		for player in pairs(profiles) do
			task.spawn(saveAndRelease, player)
		end
		local waited = 0
		while next(profiles) ~= nil and waited < 27 do
			waited += task.wait(0.5)
		end
	end)
end

return DataService
