-- PedService (ModuleScript, ServerScriptService.Services.PedService)
-- Makes a handful of pedestrian looks at start-up (R15 rigs from HumanoidDescriptions: skin tones,
-- pastel "shirts" and "shorts" as body colours) into ReplicatedStorage.PedTemplates. Each client then
-- runs its own pedestrians from these (PedClient), so they cost the server nothing.
--
-- Pedestrian wallets (numbers in Config.Combat.Ped). A pedestrian that is punched or shot falls over,
-- runs off and drops a wallet, all on that player's own device (PedClient). The server can't see any of
-- that, so the money is decided here:
--   Remote PedLoot, client -> server: (position: Vector3), sent when the player reaches a wallet.
--   Remote PedLoot, server -> client: (result: "Paid" | "Empty" | "No", amount: number, stars: number).
--   "Paid" needs all of: a citizen, not passive, alive, on foot, not knocked over or tasered, not in a
--   safe zone or at home (CombatService.IsSafe); a swing or a shot accepted by CombatService in the last
--   25 s (CombatService.LastAggro); standing within 14 studs (flat) of the position, near a street
--   (pedestrians walk beside roads, and run a little way off them when scared); 2.5 s since their last
--   wallet; room in the robbery bag. In a safe zone a toast says why not ("PedLootSafe").
--   A wallet is $15-$90 and goes into the robbery bag (Carried), so it can be lost again. Each one is
--   +1 star through CombatService.CrimeHeat (free "fight" stars: capped at 2, or 3 when the last thing
--   they did was fire a gun).
--   At most $900 per player per 10 minutes (counted from their first wallet, kept by UserId so a
--   rejoin doesn't reset it). After that the answer is "Empty" and a toast says the street has gone quiet.
-- So the most anyone can make this way, cheating or not, is $900 every 10 minutes into a bag they
-- still have to bank while wanted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local PedService = {}

local SKIN = {
	Color3.fromRGB(255, 220, 185), Color3.fromRGB(234, 192, 150), Color3.fromRGB(205, 160, 120),
	Color3.fromRGB(160, 110, 75), Color3.fromRGB(110, 75, 55),
}
local SHIRTS = {
	Color3.fromRGB(255, 120, 190), Color3.fromRGB(110, 242, 196), Color3.fromRGB(255, 214, 10),
	Color3.fromRGB(34, 225, 255), Color3.fromRGB(255, 138, 61), Color3.fromRGB(190, 170, 255),
	Color3.fromRGB(245, 245, 250), Color3.fromRGB(255, 90, 90),
}
local SHORTS = {
	Color3.fromRGB(40, 60, 120), Color3.fromRGB(245, 235, 215), Color3.fromRGB(60, 60, 70),
	Color3.fromRGB(120, 200, 230), Color3.fromRGB(200, 90, 160),
}

local TEMPLATES = 10

local PED = Combat.Ped
-- Studs (flat) from a road's centre line. Was 70 (sidewalks, crossings and a few steps beyond), but a
-- scared or punched pedestrian runs 45 studs off the sidewalk each time: knocked over again out there,
-- their wallet showed its "$" and never paid. 200 covers a walker chased that far a few times over.
local STREET_REACH = 200
local HEIGHT_REACH = 10 -- studs: the wallet and the player are on the same level

local lootRemote, downRemote, notify
-- [player] = { n = knock-downs reported that no wallet has been paid for yet, at = os.clock() of the last }
local downs = {}
local lootRng = Random.new()
local lastPaid = {} -- [player] = os.clock() of their last wallet
local windows = {} -- [UserId] = { start = os.clock() of the first wallet, sum = dollars paid since }
local combatService -- CombatService starts after us: required the first time a wallet is asked for (false = couldn't)

local function combat()
	if combatService == nil then
		local module = ServerScriptService.Services:FindFirstChild("CombatService")
		local ok, result = pcall(require, module)
		combatService = (ok and type(result) == "table" and result.LastAggro ~= nil) and result or false
	end
	return combatService or nil
end

local function finite(v)
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

-- Is this server-time attribute (KnockedUntil, StunnedUntil) still in the future?
local function running(player, name)
	local t = player:GetAttribute(name)
	return type(t) == "number" and t > Workspace:GetServerTimeNow()
end

-- Is this spot within STREET_REACH studs (flat) of a road's centre line? The road graph's nodes sit at
-- y = 0 (AIPoliceService builds it at start-up). No roads known: no pedestrians either.
local function nearStreet(pos)
	local nodes = RoadGraph.Nodes
	local px, pz = pos.X, pos.Z
	local reach2 = STREET_REACH * STREET_REACH
	for i, a in ipairs(nodes) do
		local edges = RoadGraph.Edges[i]
		if edges then
			for j in pairs(edges) do
				local b = nodes[j]
				if i < j and b then
					local abx, abz = b.X - a.X, b.Z - a.Z
					local len2 = abx * abx + abz * abz
					local t = len2 > 0 and math.clamp(((px - a.X) * abx + (pz - a.Z) * abz) / len2, 0, 1) or 0
					local dx, dz = px - (a.X + abx * t), pz - (a.Z + abz * t)
					if dx * dx + dz * dz <= reach2 then
						return true
					end
				end
			end
		end
	end
	return false
end

-- "No": the wallet stays where it is and the client asks again in a moment. (Its own small limit, so
-- a flood of requests isn't answered one for one.)
local function no(player)
	if RateLimit.Allow(player, "PedLootNo", 2, 4) then
		lootRemote:FireClient(player, "No", 0, 0)
	end
end

local function onLoot(player, position)
	if not RateLimit.Allow(player, "PedLoot", 1, 2) or typeof(position) ~= "Vector3" or not finite(position) then
		return no(player)
	end
	local combatSvc = combat()
	if not combatSvc then
		return no(player)
	end
	-- Who may take a wallet at all: a citizen, out in the open, on their feet.
	if player:GetAttribute("Side") ~= "Civilian" or player:GetAttribute("Passive") == true then
		return no(player)
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") or hum.Health <= 0 or hum.SeatPart then
		return no(player)
	end
	if running(player, "KnockedUntil") or running(player, "StunnedUntil") then
		return no(player)
	end
	if combatSvc.IsSafe(player) then
		-- A wallet lying in a safe zone never pays, and nothing said why: say so (now and then, not on
		-- every ask).
		if RateLimit.Allow(player, "PedLootSafeToast", 1 / 8, 1) then
			notify:FireClient(player, "PedLootSafe")
		end
		return no(player)
	end
	-- They have to have swung or fired just now (the server saw that much), close to this spot, on a street.
	local t = os.clock()
	local aggroAt, aggroKind = combatSvc.LastAggro(player)
	if type(aggroAt) ~= "number" or t - aggroAt > PED.AggroWindow then
		return no(player)
	end
	local rel = root.Position - position
	if math.abs(rel.Y) >= HEIGHT_REACH or Vector3.new(rel.X, 0, rel.Z).Magnitude > PED.Range or not nearStreet(position) then
		return no(player)
	end
	if t - (lastPaid[player] or -math.huge) < PED.Gap then
		return no(player)
	end
	-- The 10-minute purse.
	local id = player.UserId
	local window = windows[id]
	if window and t - window.start >= PED.Window then
		window = nil
		windows[id] = nil
	end
	local left = PED.WindowMax - (window and window.sum or 0)
	if left <= 0 then
		lootRemote:FireClient(player, "Empty", 0, 0)
		if RateLimit.Allow(player, "PedsQuietToast", 1 / 30, 1) then
			notify:FireClient(player, "PedsQuiet")
		end
		return
	end
	if EconomyService.GetCarried(player) >= EconomyService.CarryLimit(player) then
		lootRemote:FireClient(player, "No", 0, 0)
		if RateLimit.Allow(player, "PedBagFullToast", 1 / 8, 1) then
			notify:FireClient(player, "DroppedBagFull")
		end
		return
	end
	local amount = math.min(lootRng:NextInteger(PED.Min, PED.Max), left)
	local fits = EconomyService.AddCarried(player, amount, "ped_wallet")
	if fits <= 0 then
		return no(player)
	end
	lastPaid[player] = t
	if not window then
		window = { start = t, sum = 0 }
		windows[id] = window
	end
	window.sum += fits
	-- Every wallet belongs to one pedestrian who went down. PedClient reports each of them as they fall
	-- (onDown counts them); a wallet nobody reported (a tampered client) is counted here instead, so
	-- staying quiet about them never keeps the police away.
	local d = downs[player]
	if d and d.n > 0 and t - d.at <= PED.AggroWindow + PED.WalletLife then
		d.n -= 1
	else
		combatSvc.PedVictim(player)
	end
	-- Owner's rule: the first FreeVictims pedestrians bring no police, so their wallets carry no star.
	-- Nor does the wallet of the next one: knocking that one over has just put the first star on (the
	-- police "start coming"), and a second star in the same breath was too much. From the one after
	-- that, a wallet is a star as it always was.
	local stars = 0
	if combatSvc.PedVictims(player) > (PED.FreeVictims or 0) + 1 then
		stars = combatSvc.CrimeHeat(player, Combat.Heat.PedLoot, "ped_mugged", aggroKind == "Gun")
	end
	lootRemote:FireClient(player, "Paid", fits, stars)
end

-- A pedestrian went down on this player's device (PedClient: a punch or a bullet of theirs). The server
-- can't see pedestrians, so only the COUNT is taken from the client, and only right after a swing or a
-- shot the server itself accepted. CombatService.PedVictim decides what the count means (the police come
-- after the second one).
local function onDown(player)
	if not RateLimit.Allow(player, "PedDown", 2, 4) then
		return
	end
	local combatSvc = combat()
	if not combatSvc or player:GetAttribute("Side") ~= "Civilian" then
		return
	end
	local aggroAt = combatSvc.LastAggro(player)
	local t = os.clock()
	if type(aggroAt) ~= "number" or t - aggroAt > 3 then
		return
	end
	local d = downs[player]
	if not d or t - d.at > PED.AggroWindow + PED.WalletLife then
		d = { n = 0, at = t }
		downs[player] = d
	end
	d.n = math.min(d.n + 1, 8)
	d.at = t
	combatSvc.PedVictim(player)
end

local function buildTemplates()
	local folder = ReplicatedStorage:FindFirstChild("PedTemplates") or Instance.new("Folder")
	folder.Name = "PedTemplates"
	folder.Parent = ReplicatedStorage
	task.spawn(function()
		local rng = Random.new()
		for i = 1, TEMPLATES do
			local ok, model = pcall(function()
				local desc = Instance.new("HumanoidDescription")
				local skin = SKIN[rng:NextInteger(1, #SKIN)]
				local shirt = SHIRTS[rng:NextInteger(1, #SHIRTS)]
				local shorts = SHORTS[rng:NextInteger(1, #SHORTS)]
				desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
				desc.TorsoColor = shirt
				desc.LeftLegColor, desc.RightLegColor = shorts, shorts
				return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
			end)
			if ok and model then
				model.Name = "Ped" .. i
				-- Clients animate them themselves; scripts inside wouldn't run anyway.
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BaseScript") then
						d:Destroy()
					end
				end
				local hum = model:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					hum.WalkSpeed = 7
				end
				model.Parent = folder
			end
		end
	end)
end

function PedService.Init()
	buildTemplates()

	notify = Remotes.Event("Notify")
	lootRemote = Remotes.Event("PedLoot")
	lootRemote.OnServerEvent:Connect(onLoot)
	downRemote = Remotes.Event("PedDown")
	downRemote.OnServerEvent:Connect(onDown)
	Players.PlayerRemoving:Connect(function(player)
		lastPaid[player] = nil
		downs[player] = nil
		-- Purses are kept by UserId (a rejoin mustn't refill one): drop the ones that have run out.
		local t = os.clock()
		for id, window in pairs(windows) do
			if t - window.start >= PED.Window then
				windows[id] = nil
			end
		end
	end)
end

return PedService
