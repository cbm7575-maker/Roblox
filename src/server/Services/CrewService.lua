-- CrewService (ModuleScript, ServerScriptService.Services.CrewService)
-- Crews: up to 4 players who play together (PRD "Crew" phone app + crew bonus).
--   * Invite from the phone's CREW app; the other player gets an ACCEPT / NO card (60 s to answer).
--   * Crewmates see each other's name tags through walls and on the minimap (CrewClient).
--   * Crew bonus: +20% heist cash when a crewmate is within 150 studs (HeistService asks CrewBonus).
--   * Friend bonus: +10% heist cash while any Roblox friend is in the server (attribute FriendBonus).
--   * Crewmates can ride in each other's cars (VehicleService passenger seat checks SameCrew).
-- State: player attribute "Crew" = crew id (string), ReplicatedStorage attribute "Crews" = JSON
-- { [crewId] = { userIds } } so every client can draw tags.
-- Remotes: RequestCrew(action, targetUserId) with action "Invite" | "Accept" | "Decline" | "Leave";
--          CrewInvite (server -> client) { FromUserId, FromName }.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local CrewService = {}

local MAX_CREW = 4
local INVITE_SECONDS = 60
local BONUS_RANGE = 150
CrewService.CrewBonus = 0.2
CrewService.FriendBonus = 0.1

local crews = {} -- [crewId] = { members = { player, ... } }
local invites = {} -- [targetPlayer] = { from = player, crewId = id or nil, at = os.clock() }
local nextId = 0
local notify, inviteEvent

local function publish()
	local out = {}
	for id, crew in pairs(crews) do
		local ids = {}
		for _, p in ipairs(crew.members) do
			table.insert(ids, p.UserId)
		end
		out[id] = ids
	end
	ReplicatedStorage:SetAttribute("Crews", HttpService:JSONEncode(out))
end

function CrewService.CrewOf(player)
	local id = player:GetAttribute("Crew")
	return id and crews[id] or nil
end

function CrewService.SameCrew(a, b)
	local id = a:GetAttribute("Crew")
	return id ~= nil and id == b:GetAttribute("Crew")
end

local function leave(player)
	local id = player:GetAttribute("Crew")
	local crew = id and crews[id]
	player:SetAttribute("Crew", nil)
	player:SetAttribute("CrewPos", nil)
	if not crew then
		return
	end
	local i = table.find(crew.members, player)
	if i then
		table.remove(crew.members, i)
	end
	for _, p in ipairs(crew.members) do
		notify:FireClient(p, "CrewLeft")
	end
	if #crew.members <= 1 then
		for _, p in ipairs(crew.members) do
			p:SetAttribute("Crew", nil)
		end
		crews[id] = nil
	end
	publish()
end

local function join(player, crewId)
	local crew = crews[crewId]
	if player:GetAttribute("Crew") == crewId then
		return true
	end
	if not crew or #crew.members >= MAX_CREW then
		return false
	end
	if player:GetAttribute("Crew") then
		leave(player)
	end
	table.insert(crew.members, player)
	player:SetAttribute("Crew", crewId)
	for _, p in ipairs(crew.members) do
		notify:FireClient(p, "CrewJoined")
	end
	publish()
	Telemetry.Custom(player, "CrewJoined", #crew.members)
	return true
end

local function create(leader)
	nextId += 1
	local id = "c" .. nextId
	crews[id] = { members = { leader } }
	leader:SetAttribute("Crew", id)
	return id
end

-- Heist bonus multiplier for this player right now (crew nearby, friend in server).
function CrewService.BonusFor(player)
	local bonus = 0
	local crew = CrewService.CrewOf(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if crew and root then
		for _, p in ipairs(crew.members) do
			local r = p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if r and (r.Position - root.Position).Magnitude <= BONUS_RANGE then
				bonus += CrewService.CrewBonus
				break
			end
		end
	end
	if player:GetAttribute("FriendBonus") then
		bonus += CrewService.FriendBonus
	end
	return bonus
end

local function onRequest(player, action, targetUserId)
	if not RateLimit.Allow(player, "Crew", 2, 4) or type(action) ~= "string" then
		return
	end
	if action == "Invite" then
		local target = type(targetUserId) == "number" and Players:GetPlayerByUserId(targetUserId)
		if not target or target == player then
			return
		end
		if CrewService.SameCrew(player, target) then
			return
		end
		local crew = CrewService.CrewOf(player)
		if crew and #crew.members >= MAX_CREW then
			notify:FireClient(player, "CrewFull")
			return
		end
		local pending = invites[target]
		if pending and os.clock() - pending.at < INVITE_SECONDS then
			notify:FireClient(player, "CrewInvitePending")
			return
		end
		invites[target] = { from = player, at = os.clock() }
		inviteEvent:FireClient(target, { FromUserId = player.UserId, FromName = player.DisplayName })
		notify:FireClient(player, "CrewInviteSent")
	elseif action == "Accept" or action == "Decline" then
		local pending = invites[player]
		invites[player] = nil
		if not pending or os.clock() - pending.at > INVITE_SECONDS or not pending.from.Parent then
			return
		end
		if action == "Decline" then
			notify:FireClient(pending.from, "CrewDeclined")
			return
		end
		if CrewService.SameCrew(player, pending.from) then
			return -- crossed invites: already together
		end
		local id = pending.from:GetAttribute("Crew") or create(pending.from)
		if not join(player, id) then
			notify:FireClient(player, "CrewFull")
		end
	elseif action == "Leave" then
		leave(player)
	end
end

-- Friend bonus: any Roblox friend in the same server.
local function checkFriends(player)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local ok, isFriend = pcall(player.IsFriendsWith, player, other.UserId)
			if ok and isFriend then
				player:SetAttribute("FriendBonus", true)
				other:SetAttribute("FriendBonus", true)
			end
		end
	end
end

local function recheckFriendBonus()
	for _, p in ipairs(Players:GetPlayers()) do
		local any = false
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= p then
				local ok, isFriend = pcall(p.IsFriendsWith, p, other.UserId)
				if ok and isFriend then
					any = true
					break
				end
			end
		end
		p:SetAttribute("FriendBonus", any or nil)
	end
end

function CrewService.Init()
	notify = Remotes.Event("Notify")
	inviteEvent = Remotes.Event("CrewInvite")
	Remotes.Event("RequestCrew").OnServerEvent:Connect(onRequest)
	Players.PlayerAdded:Connect(function(p)
		task.spawn(checkFriends, p)
	end)
	Players.PlayerRemoving:Connect(function(p)
		leave(p)
		invites[p] = nil
		for target, inv in pairs(invites) do
			if inv.from == p then
				invites[target] = nil
			end
		end
		task.defer(recheckFriendBonus)
	end)
	publish()
	-- Crewmates stream out when far away, so publish each crew member's position (player attribute
	-- "CrewPos" = "x,z") for the minimap.
	task.spawn(function()
		while true do
			task.wait(1.5)
			for _, crew in pairs(crews) do
				for _, p in ipairs(crew.members) do
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					p:SetAttribute("CrewPos", root and string.format("%d,%d", root.Position.X, root.Position.Z) or nil)
				end
			end
		end
	end)
end

return CrewService
