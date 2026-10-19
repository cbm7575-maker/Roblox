-- HeatService (ModuleScript, ServerScriptService.Services.HeatService)
-- The wanted system, GTA 6 style: cops only know what they've seen.
--   Heat 1-5 (player attribute "Heat") comes from crimes; only citizens get heat.
--   HeatSpotted = true while a cop (player or AI "eye") can see you: within 250 studs and a clear
--     line of sight. Cops then see your exact position (attribute LastSeen follows you).
--   Not seen for 8 s -> hollow stars: cops only see a search circle around LastSeen.
--   Not seen for 30 + 10 x heat seconds -> heat gone ("You lost the cops!").
--   A heist site with an active alarm is a hot zone: a wanted player within 60 studs is spotted.
--   At 4+ stars LastSeen updates every 20 s even while hollow (the helicopter-style ping).
-- Bounty for arresting someone = $500 per star + 25% of their carried cash.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Disguises = require(ReplicatedStorage.Shared.Config.Disguises)

local HeatService = {}

-- Suspect Card (attributes on the wanted player, shown to cops):
--   SuspectOutfit - their look (hat + mask) when a camera or cop last saw them on foot
--   SuspectCar    - their car and its colour when a cop last saw them driving
-- Changing the look at a wardrobe or respraying the car while unseen clears that clue (DisguiseService).
local COLOR_WORDS = {
	{ "pink", Color3.fromRGB(255, 62, 165) }, { "cyan", Color3.fromRGB(34, 225, 255) },
	{ "purple", Color3.fromRGB(123, 47, 255) }, { "orange", Color3.fromRGB(255, 138, 61) },
	{ "yellow", Color3.fromRGB(255, 214, 10) }, { "mint", Color3.fromRGB(110, 242, 196) },
	{ "white", Color3.fromRGB(240, 240, 245) }, { "black", Color3.fromRGB(22, 22, 28) },
	{ "grey", Color3.fromRGB(128, 128, 136) }, { "red", Color3.fromRGB(220, 40, 50) },
	{ "blue", Color3.fromRGB(40, 70, 200) }, { "green", Color3.fromRGB(70, 150, 70) },
}
function HeatService.ColorWord(c)
	local best, bestD = "grey", math.huge
	for _, w in ipairs(COLOR_WORDS) do
		local o = w[2]
		local d = (c.R - o.R) ^ 2 + (c.G - o.G) ^ 2 + (c.B - o.B) ^ 2
		if d < bestD then
			best, bestD = w[1], d
		end
	end
	return best
end

function HeatService.LookOf(player)
	return Disguises.Describe(player:GetAttribute("LookHat"), player:GetAttribute("LookMask"))
end

local function noteClues(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local car = hum and hum.SeatPart and hum.SeatPart.Parent
	if car and car.PrimaryPart and car:GetAttribute("NCVehicle") then
		local text = (car:GetAttribute("DisplayName") or car.Name) .. " (" .. HeatService.ColorWord(car.PrimaryPart.Color) .. ")"
		if player:GetAttribute("SuspectCar") ~= text then
			player:SetAttribute("SuspectCar", text)
		end
	else
		local look = HeatService.LookOf(player)
		if player:GetAttribute("SuspectOutfit") ~= look then
			player:SetAttribute("SuspectOutfit", look)
		end
	end
end

local SIGHT_RANGE = 250
local HOLLOW_AFTER = 8
local HOT_ZONE = 60
local PING_EVERY = 20
local CHECK_EVERY = 0.5

local lastSeenAt = {} -- [player] = os.clock()
local lastPing = {} -- [player] = os.clock()
local eyes = {} -- [BasePart] = true: extra eyes (AI police cars)

local notify, feed

local function now()
	return Workspace:GetServerTimeNow()
end

local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart")
end

function HeatService.GetHeat(player)
	return player:GetAttribute("Heat") or 0
end

function HeatService.Bounty(player)
	return 500 * HeatService.GetHeat(player) + math.floor((player:GetAttribute("Carried") or 0) * 0.25)
end

-- A crime was seen (store camera, witness): add heat and mark where it happened.
function HeatService.Add(player, amount, reason)
	if player:GetAttribute("Side") ~= "Civilian" then
		return
	end
	local heat = math.clamp(HeatService.GetHeat(player) + amount, 0, 5)
	player:SetAttribute("Heat", heat)
	lastSeenAt[player] = os.clock()
	local root = rootOf(player)
	if root then
		player:SetAttribute("LastSeen", root.Position)
	end
	player:SetAttribute("HeatReason", reason)
	-- The store camera (or the prison guards) saw what they look like.
	noteClues(player)
end

function HeatService.Clear(player, reason)
	player:SetAttribute("Heat", 0)
	player:SetAttribute("HeatSpotted", false)
	player:SetAttribute("LastSeen", nil)
	player:SetAttribute("SuspectOutfit", nil)
	player:SetAttribute("SuspectCar", nil)
	lastSeenAt[player] = nil
	lastPing[player] = nil
end

-- Drop some heat (disguise change, respray). Reaching 0 counts as losing the cops.
function HeatService.Reduce(player, amount, reason)
	local before = HeatService.GetHeat(player)
	local heat = math.max(0, before - amount)
	if heat == 0 then
		if before > 0 then
			require(game:GetService("ServerScriptService").Services.ProgressService).Event(player, "Escape", before)
		end
		HeatService.Clear(player, reason)
		notify:FireClient(player, "LostTheCops")
	else
		player:SetAttribute("Heat", heat)
	end
end

function HeatService.RegisterEye(part)
	eyes[part] = true
end

function HeatService.UnregisterEye(part)
	eyes[part] = nil
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true

local function canSee(fromPos, target)
	local toTarget = target.Position - fromPos
	if toTarget.Magnitude > SIGHT_RANGE then
		return false
	end
	local hit = Workspace:Raycast(fromPos, toTarget, losParams)
	return hit == nil or hit.Instance:IsDescendantOf(target.Parent)
end

local function tick()
	-- Everything that isn't a wall: characters and cars never block sight.
	local exclude = { Workspace:FindFirstChild("Vehicles") }
	local copEyes = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(exclude, p.Character)
		end
		if p:GetAttribute("Side") == "Cop" then
			local root = rootOf(p)
			if root then
				table.insert(copEyes, root.Position + Vector3.new(0, 2, 0))
			end
		end
	end
	for part in pairs(eyes) do
		if part.Parent then
			table.insert(copEyes, part.Position + Vector3.new(0, 3, 0))
		else
			eyes[part] = nil
		end
	end
	losParams.FilterDescendantsInstances = exclude

	local alarms = {}
	for _, site in ipairs(Workspace.Heists:GetChildren()) do
		if now() < (site:GetAttribute("AlarmUntil") or 0) then
			table.insert(alarms, site:GetPivot().Position)
		end
	end

	local clock = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local heat = HeatService.GetHeat(player)
		local root = heat > 0 and rootOf(player)
		if root then
			local spotted = false
			for _, eye in ipairs(copEyes) do
				if canSee(eye, root) then
					spotted = true
					break
				end
			end
			if not spotted then
				for _, pos in ipairs(alarms) do
					if (root.Position - pos).Magnitude < HOT_ZONE then
						spotted = true
						break
					end
				end
			end
			if spotted then
				lastSeenAt[player] = clock
				player:SetAttribute("LastSeen", root.Position)
				noteClues(player)
				if not player:GetAttribute("HeatSpotted") then
					player:SetAttribute("HeatSpotted", true)
				end
			else
				local since = clock - (lastSeenAt[player] or clock)
				if player:GetAttribute("HeatSpotted") and since > HOLLOW_AFTER then
					player:SetAttribute("HeatSpotted", false)
				end
				if since > 30 + 10 * heat then
					require(game:GetService("ServerScriptService").Services.ProgressService).Event(player, "Escape", heat)
					HeatService.Clear(player, "escaped")
					notify:FireClient(player, "LostTheCops")
					player:SetAttribute("Evasions", (player:GetAttribute("Evasions") or 0) + 1)
					feed:FireAllClients("Escaped", { Name = player.DisplayName })
				elseif heat >= 4 and clock - (lastPing[player] or 0) > PING_EVERY then
					lastPing[player] = clock
					player:SetAttribute("LastSeen", root.Position)
				end
			end
		elseif heat > 0 and player:GetAttribute("Side") ~= "Civilian" then
			HeatService.Clear(player, "role")
		end
	end
end

function HeatService.Init()
	notify = Remotes.Event("Notify")
	feed = Remotes.Event("Feed")
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			local ok, err = pcall(tick)
			if not ok then
				warn("[HeatService] " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastSeenAt[p] = nil
		lastPing[p] = nil
	end)
end

return HeatService
