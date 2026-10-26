-- PrisonService (ModuleScript, ServerScriptService.Services.PrisonService)
-- Saltmarsh Prison. Arrested players become Prisoners and spawn in the walled yard.
--   * Release timer: 45 s + 15 s per heat star, 2 minutes at most (attribute ReleaseAt, server time).
--   * Breakout: pry open the vent in the yard's south wall (hold 5 s). It stays open 8 s, so others
--     can follow. Anyone who makes it off the island is free, and Wanted again (2 stars).
--   * Leaving and rejoining doesn't end a sentence: the release time is kept by UserId for this server
--     (TeamService puts a rejoining prisoner back in the yard, PrisonService.Rejoined) and saved in the
--     profile as data.jailUntil (os.time) for any other server (checked when the save loads).
-- The prison island spans x -1750..-1100, z 1000..1700; the moat surrounds it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local TeamService = require(ServerScriptService.Services.TeamService)
local HeatService = require(ServerScriptService.Services.HeatService)

local PrisonService = {}

local ISLAND = { xMin = -1760, xMax = -1090, zMin = 990, zMax = 1710 }
local VENT_HOLD = 5
local VENT_OPEN = 8
local VENT_COOLDOWN = 20

local notify, feed, brokeOut

-- The saved sentence end (data.jailUntil, os.time seconds) so a prisoner can't rejoin another server
-- to walk free. DataService is required lazily: it's started after this module is loaded.
local function saveJail(player, seconds)
	local ok, DataService = pcall(require, ServerScriptService.Services.DataService)
	local data = ok and DataService.Get(player)
	if data then
		data.jailUntil = seconds and (os.time() + math.ceil(seconds)) or nil
	end
end

-- A prisoner can only "break out" after their prison character has actually stood on the island
-- (right after an arrest the old character is still wherever they were caught).
local seenOnIsland = {} -- [player] = true

-- Prisoners who left mid-sentence: [userId] = their ReleaseAt (server time). Time away still counts.
local leftJail = {}

local function now()
	return Workspace:GetServerTimeNow()
end

-- Called by TeamService when a player joins, after it has made them a Civilian: someone who left
-- during a sentence goes straight back to the yard for the time that's left.
function PrisonService.Rejoined(player)
	local releaseAt = leftJail[player.UserId]
	leftJail[player.UserId] = nil
	if not releaseAt or releaseAt - now() < 1 then
		return
	end
	seenOnIsland[player] = nil
	player:SetAttribute("ReleaseAt", releaseAt)
	player:SetAttribute("HasPicked", true) -- they picked a side before; no role picker in prison
	saveJail(player, releaseAt - now())
	-- The Prisoner team decides the spawn; respawn only if a character already loaded elsewhere.
	TeamService.SetSide(player, "Prisoner", player.Character ~= nil)
end

function PrisonService.Jail(player, heat)
	local seconds = math.min(120, 45 + 15 * (heat or 1))
	seenOnIsland[player] = nil
	player:SetAttribute("ReleaseAt", now() + seconds)
	saveJail(player, seconds)
	TeamService.SetSide(player, "Prisoner", true)
end

function PrisonService.Release(player)
	player:SetAttribute("ReleaseAt", nil)
	saveJail(player, nil)
	TeamService.SetSide(player, "Civilian", true)
	notify:FireClient(player, "Released")
end

local function onIsland(pos)
	return pos.X > ISLAND.xMin and pos.X < ISLAND.xMax and pos.Z > ISLAND.zMin and pos.Z < ISLAND.zMax
end

local function breakout(player)
	player:SetAttribute("ReleaseAt", nil)
	saveJail(player, nil)
	TeamService.SetSide(player, "Civilian", false) -- keep the character where it is
	HeatService.Add(player, 2, "breakout")
	player:SetAttribute("Breakouts", (player:GetAttribute("Breakouts") or 0) + 1)
	brokeOut:FireClient(player)
	feed:FireAllClients("Breakout", { Name = player.DisplayName })
end

local function hookVent()
	local vent = Workspace.City:FindFirstChild("PrisonVent", true)
	if not vent then
		warn("[PrisonService] no PrisonVent found")
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VentPrompt"
	prompt.ActionText = "Pry open"
	prompt.ObjectText = "Vent"
	prompt.HoldDuration = VENT_HOLD
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = vent
	local holdStart = {}
	local openUntil = 0
	local cooldownUntil = 0
	prompt.PromptButtonHoldBegan:Connect(function(p)
		holdStart[p] = os.clock()
	end)
	prompt.Triggered:Connect(function(p)
		local began = holdStart[p]
		holdStart[p] = nil
		if p:GetAttribute("Side") ~= "Prisoner" or not began or os.clock() - began < VENT_HOLD - 0.4 then
			return
		end
		local t = os.clock()
		if t < cooldownUntil then
			notify:FireClient(p, "VentJammed")
			return
		end
		openUntil = t + VENT_OPEN
		cooldownUntil = t + VENT_COOLDOWN
		vent.CanCollide = false
		vent.Transparency = 0.85
		vent:SetAttribute("Open", true)
		task.delay(VENT_OPEN, function()
			if os.clock() >= openUntil - 0.05 then
				vent.CanCollide = true
				vent.Transparency = 0
				vent:SetAttribute("Open", false)
			end
		end)
	end)
end

function PrisonService.Init()
	notify = Remotes.Event("Notify")
	feed = Remotes.Event("Feed")
	brokeOut = Remotes.Event("BrokeOut")
	hookVent()
	-- A sentence saved in another server (the player left prison there): serve the rest here.
	local ok, DataService = pcall(require, ServerScriptService.Services.DataService)
	if ok and DataService.OnLoaded then
		DataService.OnLoaded(function(player, data)
			local left = (tonumber(data.jailUntil) or 0) - os.time()
			if left < 1 then
				data.jailUntil = nil
				return
			end
			if player:GetAttribute("Side") == "Prisoner" then
				return -- already sent back by Rejoined (same server)
			end
			seenOnIsland[player] = nil
			player:SetAttribute("ReleaseAt", now() + math.min(left, 120))
			player:SetAttribute("HasPicked", true)
			TeamService.SetSide(player, "Prisoner", player.Character ~= nil)
		end)
	end
	Players.PlayerRemoving:Connect(function(p)
		seenOnIsland[p] = nil
		local releaseAt = p:GetAttribute("ReleaseAt")
		if p:GetAttribute("Side") == "Prisoner" and typeof(releaseAt) == "number" and releaseAt > now() then
			leftJail[p.UserId] = releaseAt
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local t = now()
			for _, p in ipairs(Players:GetPlayers()) do
				if p:GetAttribute("Side") == "Prisoner" then
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
					local releaseAt = p:GetAttribute("ReleaseAt") or 0
					if t >= releaseAt then
						seenOnIsland[p] = nil
						PrisonService.Release(p)
					elseif root and onIsland(root.Position) then
						seenOnIsland[p] = true
					elseif root and seenOnIsland[p] then
						seenOnIsland[p] = nil
						breakout(p)
					end
				end
			end
		end
	end)
end

return PrisonService
