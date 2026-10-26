-- TeamService (ModuleScript, ServerScriptService.Services.TeamService)
-- Civilians (default, free roam), Cops (an optional job) and Prisoners. Everyone joins as a citizen:
-- there is no role choice at join. The first-join title screen (TeamUI) has one PLAY button, which
-- sends RequestTeam("Civilian"): that sets HasPicked (= "past the title screen"; TutorialService,
-- DailyService, FriendsService, InteractClient, HUDController and TutorialClient wait for it) and, as
-- the side is already Civilian, changes nothing else (no respawn). A prisoner who left mid-sentence and
-- rejoined never sees it (PrisonService.Rejoined sends them back and sets HasPicked).
-- Police duty is taken from the phone (PHONE > JOBS: GO ON DUTY / GO OFF DUTY = RequestTeam "Cop" /
-- "Civilian"). Switching is allowed when: not a prisoner, no heat, not on cooldown, and for cops,
-- the cop cap (about 1 cop per 2 robbers) has room; a refusal comes back as a Notify toast. Switching
-- respawns you at your side's spawn with that side's starter car waiting on a pad (back on free roam,
-- a home owner's respawn goes home: HousingService).
-- TeamService.IsFreeRoaming(player): a Civilian who isn't wanted and isn't inside their home (only then
-- does FriendsService move a friend who just arrived to stand beside them).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeamsService = game:GetService("Teams")

local TeamsConfig = require(ReplicatedStorage.Shared.Config.Teams)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local VehicleService = require(ServerScriptService.Services.VehicleService)

local TeamService = {}

local teamBySide = {}
local lastSwitch = {} -- [userId] = os.clock()
local lastRequest = {} -- [userId] = os.clock(), spam guard

local function ensureTeams()
	for _, t in ipairs(TeamsConfig.List) do
		local team = TeamsService:FindFirstChild(t.TeamName)
		if not team then
			team = Instance.new("Team")
			team.Name = t.TeamName
			team.Parent = TeamsService
		end
		team.TeamColor = t.Color
		team.AutoAssignable = false
		teamBySide[t.Side] = team
	end
end

function TeamService.GetSide(player)
	return player:GetAttribute("Side") or "Civilian"
end

-- Free roam, not wanted, not inside a home (HousingService's InHome). Prisoners are never Civilians.
function TeamService.IsFreeRoaming(player)
	return TeamService.GetSide(player) == "Civilian" and (player:GetAttribute("Heat") or 0) <= 0
		and player:GetAttribute("InHome") ~= true
end

function TeamService.Count(side)
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if TeamService.GetSide(p) == side then
			n += 1
		end
	end
	return n
end

-- Move a player to a side. Their car goes away (cars belong to a side) and, if respawn, they reload.
function TeamService.SetSide(player, side, respawn)
	local team = teamBySide[side]
	if not team then
		return
	end
	player:SetAttribute("Side", side)
	player.Team = team
	VehicleService.Despawn(player.UserId)
	if respawn then
		player:LoadCharacter()
	end
end

local function reject(player, key)
	Remotes.Event("Notify"):FireClient(player, key)
end

function TeamService.Init()
	ensureTeams()
	local requestTeam = Remotes.Event("RequestTeam")

	requestTeam.OnServerEvent:Connect(function(player, side)
		local now = os.clock()
		if lastRequest[player.UserId] and now - lastRequest[player.UserId] < 1 then
			return
		end
		lastRequest[player.UserId] = now
		if side ~= "Civilian" and side ~= "Cop" then
			return
		end
		local current = TeamService.GetSide(player)
		local firstPick = player:GetAttribute("HasPicked") ~= true
		player:SetAttribute("HasPicked", true)
		if side == current then
			return
		end
		if current == "Prisoner" then
			return reject(player, "TeamInPrison")
		end
		if (player:GetAttribute("Heat") or 0) > 0 then
			return reject(player, "TeamHasHeat")
		end
		if not firstPick and lastSwitch[player.UserId] and now - lastSwitch[player.UserId] < TeamsConfig.SwitchCooldown then
			return reject(player, "TeamCooldown")
		end
		if side == "Cop" and TeamService.Count("Cop") >= TeamsConfig.MaxCops(#Players:GetPlayers()) then
			return reject(player, "CopsFull")
		end
		lastSwitch[player.UserId] = now
		TeamService.SetSide(player, side, true)
	end)

	local function onPlayer(player)
		player:SetAttribute("Side", "Civilian")
		player:SetAttribute("HasPicked", false)
		player.Team = teamBySide.Civilian
		-- Left mid-sentence and came back? Straight back to prison (required here, not at the top:
		-- PrisonService requires this module).
		require(ServerScriptService.Services.PrisonService).Rejoined(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		if not p:GetAttribute("Side") then
			onPlayer(p)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwitch[player.UserId] = nil
		lastRequest[player.UserId] = nil
	end)

	-- If cops end up over the cap (robbers left), nobody is forced off; new cops just can't join.
end

return TeamService
