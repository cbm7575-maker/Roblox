-- RespawnService (ModuleScript, ServerScriptService.Services.RespawnService)
-- Coming back after a death. Roblox's own respawn (5 s after any death, no say in it) is switched off
-- (Players.CharacterAutoLoads = false) and characters are loaded here instead:
--   * on joining, at once (as Roblox did);
--   * after a death (shot dead: CombatService; Esc > Reset; a long fall): the death screen's RESPAWN
--     button (RespawnClient -> remote RequestRespawn) from Combat.Death.RespawnAfter seconds after the
--     death, or by itself after Combat.Death.AutoRespawn;
--   * a player left with no body at all for NO_BODY seconds (one removed without dying) gets one.
-- Where you come back is unchanged: your side's spawn, or inside your home (HousingService). Services
-- that respawn you on purpose (TeamService.SetSide: police duty, prison, release) still call
-- LoadCharacter themselves, often on a dead body (ArrestService: shot dead with police right there is
-- an arrest); this only ever loads a player whose body is dead or missing, and one load at a time. Any
-- load, theirs or ours, takes the old body away first (CharacterRemoving): from then on the death is
-- forgotten, so neither RESPAWN nor the automatic respawn can load a second body on top.
-- Player attribute DiedAt (server time; nil while alive): when the current body died. RespawnClient
-- counts down from it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local RespawnService = {}

local DEATH = Combat.Death
local NO_BODY = 10 -- seconds without any body before one is loaded (longer than a slow avatar load)
local CHECK_EVERY = 0.5
local EARLY = 0.25 -- a RESPAWN press this much before RespawnAfter still counts (its device's clock and ours differ a little)

local diedAt = {} -- [player] = os.clock() their current body died
local noBodySince = {} -- [player] = os.clock() they were first seen with no body
local loading = {} -- [player] = true while a LoadCharacter from here runs
local gone = setmetatable({}, { __mode = "v" }) -- [player] = the body CharacterRemoving took (never marked dead again)

local function load(player)
	if loading[player] or player.Parent ~= Players then
		return
	end
	loading[player] = true
	task.spawn(function()
		local ok, err = pcall(player.LoadCharacter, player)
		loading[player] = nil
		if not ok then
			warn("[RespawnService] " .. player.Name .. ": " .. tostring(err))
		end
	end)
end

local function markDead(player)
	if not diedAt[player] then
		diedAt[player] = os.clock()
		player:SetAttribute("DiedAt", Workspace:GetServerTimeNow())
	end
end

local function onCharacter(player, char)
	diedAt[player] = nil
	noBodySince[player] = nil
	player:SetAttribute("DiedAt", nil)
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 10)
	if not hum or not hum:IsA("Humanoid") then
		return
	end
	hum.Died:Connect(function()
		if player.Character == char and gone[player] ~= char then
			markDead(player)
		end
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	player.CharacterRemoving:Connect(function(char)
		gone[player] = char
		diedAt[player] = nil -- a new body is on its way (whoever asked for it)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

-- Twice a second: the auto-respawn, a death the Died signal missed, and players with no body.
local function check()
	local t = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if not char then
			noBodySince[p] = noBodySince[p] or t
			if t - noBodySince[p] >= NO_BODY then
				load(p)
			end
		else
			noBodySince[p] = nil
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health <= 0 and gone[p] ~= char then
				markDead(p)
			end
			local at = diedAt[p]
			if at and t - at >= DEATH.AutoRespawn then
				load(p)
			end
		end
	end
end

function RespawnService.Init()
	Remotes.Event("RequestRespawn").OnServerEvent:Connect(function(player)
		if not RateLimit.Allow(player, "Respawn", 2, 2) then
			return
		end
		local at = diedAt[player]
		if at and os.clock() - at >= DEATH.RespawnAfter - EARLY then
			load(player)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		onPlayer(player)
		-- (Deferred: every other service's PlayerAdded, TeamService's team among them, runs first.)
		task.defer(function()
			if not player.Character then
				load(player)
			end
		end)
	end)
	-- Already here (Studio's Play starts the player with the server): Roblox loaded them, or check()
	-- does within NO_BODY seconds.
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		diedAt[player] = nil
		noBodySince[player] = nil
		loading[player] = nil
		gone[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			local ok, err = pcall(check)
			if not ok then
				warn("[RespawnService] " .. tostring(err))
			end
		end
	end)
	-- Last: should anything above fail (Main reports it), Roblox's own respawn is still on and nobody
	-- is left without a body.
	Players.CharacterAutoLoads = false
end

return RespawnService
