-- CollectibleService (ModuleScript, ServerScriptService.Services.CollectibleService)
-- The Gus hunt: hidden Gus the Gator figurines all over Port Solana (spots in Config.Collectibles).
--   * Start-up: each spot is re-checked with a raycast (dry, flat ground between Y -1 and 12, room
--     above it) and nudged along a spiral (5-40 studs) to the nearest clear point; a spot with no
--     room is skipped with a warn (fix its X/Z in the config). The search runs a few checks per frame.
--   * Workspace.Collectibles (Folder) holds one atomic Model per figurine, named by its Id
--     (attributes Id, District, Pos = Vector3 of the ground point): the Gator art mesh on a small
--     neon pedestal, a soft light and a ProximityPrompt ("Pick up", hold 0.5 s). Every player sees
--     every figurine; CollectibleClient hides the ones you already found.
--   * A pick-up is server-checked (character within 14 studs, not found before, RateLimit) and pays
--     Collectibles.Cash, plus Collectibles.DistrictBonus for the last one in a district. Finding all
--     of them sets Unlock_GusHunter (the Gator Green paint in Config.Garage) and posts on the Coast Feed.
--   Saved: data.found = { [id] = true }, data.flags.gusHunter.
--   Player attributes: GusFound (count), GusTotal (#Config.Collectibles.Spots), GusFoundIds
--     ("G01,G07,..." in config order), Unlock_GusHunter.
--   Remote to the finder: GusFound { Id, Count, Total, District, DistrictCount, DistrictTotal,
--     DistrictDone, AllDone, Cash (total paid for this find), Bonus (the district part of Cash) }.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Collectibles = require(ReplicatedStorage.Shared.Config.Collectibles)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local ProgressService = require(ServerScriptService.Services.ProgressService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local CollectibleService = {}

local TOTAL = #Collectibles.Spots
local REACH = 14 -- server-side pick-up distance (the prompt itself reaches 10)
local UNLOCK_ATTR = "Unlock_" .. Collectibles.Unlock

-- Placement
local RAY_TOP = 120
local RAY_BOTTOM = -20
local MIN_Y, MAX_Y = -1, 12
local FLAT = 0.4 -- the pedestal's edge points must be within this of the centre height
local EDGE = 1.8 -- how far out those edge points are
local CLEAR = Vector3.new(5, 6, 5) -- room the figurine needs above the ground
local CLEAR_LIFT = 0.45 -- the room box starts this far above the ground point
local CHECKS_PER_FRAME = 10
local EXCLUDE_FOLDERS = { "Vehicles", "Collectibles", "Events", "Smoke", "Spikes", "NPCs", "Roadblocks" }

-- Look
local GATOR_SCALE = 1.6
local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local DARK = Color3.fromRGB(18, 14, 30)
local GATOR_GREEN = Color3.fromRGB(70, 170, 80)
local BELLY = Color3.fromRGB(190, 225, 140)

local folder, gusFound, feed

------------------------------------------------------------------ placement

-- Points to try around a spot, nearest first: rings 5, 10 ... 40 studs out, each ring turned a
-- little (golden angle) so the points spiral instead of lining up.
local SPIRAL = {}
do
	local ring = 0
	for r = 5, 40, 5 do
		local n = math.max(8, math.floor(2 * math.pi * r / 5 + 0.5))
		for i = 0, n - 1 do
			local a = ring * 2.39996 + i * 2 * math.pi / n
			table.insert(SPIRAL, Vector2.new(math.cos(a) * r, math.sin(a) * r))
		end
		ring += 1
	end
end
local EDGES = { Vector2.new(EDGE, 0), Vector2.new(-EDGE, 0), Vector2.new(0, EDGE), Vector2.new(0, -EDGE) }

-- Folders and characters the placement rays and the room check never count.
local function excludeList()
	local list = {}
	for _, name in ipairs(EXCLUDE_FOLDERS) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

-- First surface straight down at (x, z). Invisible non-solid parts (trigger zones) are passed through.
local function castDown(x, z, params)
	local top = RAY_TOP
	for _ = 1, 6 do
		local hit = Workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, RAY_BOTTOM - top, 0), params)
		if not hit then
			return nil
		end
		local inst = hit.Instance
		if inst ~= Workspace.Terrain and inst:IsA("BasePart") and not inst.CanCollide and inst.Transparency >= 0.9 then
			top = hit.Position.Y - 0.05
		else
			return hit
		end
	end
	return nil
end

local function isGround(hit, roads)
	if not hit then
		return false
	end
	local y = hit.Position.Y
	if y < MIN_Y or y > MAX_Y or hit.Material == Enum.Material.Water or hit.Instance.Name == "Water" then
		return false
	end
	return not (roads and hit.Instance:IsDescendantOf(roads)) -- never on a road
end

-- The ground point at (x, z) if a figurine fits there: dry, flat, off the road, with room above.
local function check(x, z, params, overlap, excludes, roads)
	local hit = castDown(x, z, params)
	if not isGround(hit, roads) or hit.Normal.Y < 0.85 then
		return nil
	end
	local y = hit.Position.Y
	for _, e in ipairs(EDGES) do
		local h = castDown(x + e.X, z + e.Y, params)
		if not isGround(h, roads) or math.abs(h.Position.Y - y) > FLAT then
			return nil -- a rail, a narrow ledge or a step
		end
	end
	local filter = table.clone(excludes)
	table.insert(filter, hit.Instance)
	table.insert(filter, Workspace.Terrain)
	overlap.FilterDescendantsInstances = filter
	local pos = Vector3.new(x, y, z)
	local box = CFrame.new(pos + Vector3.new(0, CLEAR_LIFT + CLEAR.Y / 2, 0))
	for _, p in ipairs(Workspace:GetPartBoundsInBox(box, CLEAR, overlap)) do
		if p.CanCollide or p.Transparency < 0.9 then
			return nil
		end
	end
	return pos
end

-- Where the figurine for `spot` goes (the spot itself, or the nearest clear point), or nil.
-- Yields: checks run CHECKS_PER_FRAME at a time.
local function findPlace(spot)
	local excludes = excludeList()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludes
	params.IgnoreWater = false
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	local city = Workspace:FindFirstChild("City")
	local roads = city and city:FindFirstChild("Roads")
	local pos = check(spot.X, spot.Z, params, overlap, excludes, roads)
	if pos then
		return pos, 0
	end
	for i, o in ipairs(SPIRAL) do
		if i % CHECKS_PER_FRAME == 0 then
			task.wait()
		end
		pos = check(spot.X + o.X, spot.Z + o.Y, params, overlap, excludes, roads)
		if pos then
			return pos, o.Magnitude
		end
	end
	return nil
end

------------------------------------------------------------------ the figurine

local function part(parent, name, size, cf, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false -- car suspension rays and cameras pass straight through
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- An upright disc (Roblox cylinders run along X): `height` tall, its bottom `y` above `base`.
local function disc(parent, name, base, y, height, diameter, color, material)
	local p = part(parent, name, Vector3.new(height, diameter, diameter),
		base * CFrame.new(0, y + height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Stand-in when ServerStorage.ArtAssets.Gator is missing: a chunky little part gator in shades.
-- `stand` is the pedestal top (facing the figurine's way); returns the body part.
local function partGator(parent, stand)
	local function at(x, y, z)
		return stand * CFrame.new(x, y, z)
	end
	local body = part(parent, "Gus", Vector3.new(2, 1.3, 2.2), at(0, 0.65, 0.2), GATOR_GREEN)
	body.CastShadow = true
	part(parent, "Head", Vector3.new(1.7, 1.1, 1.3), at(0, 0.95, -1.4), GATOR_GREEN)
	part(parent, "Snout", Vector3.new(1.3, 0.6, 1), at(0, 0.7, -2.4), BELLY)
	part(parent, "Tail", Vector3.new(0.9, 0.6, 1.2), at(0, 0.3, 1.8), GATOR_GREEN)
	for _, side in ipairs({ -0.45, 0.45 }) do
		local eye = part(parent, "Eye", Vector3.new(0.5, 0.5, 0.5), at(side, 1.6, -1.6), Color3.new(1, 1, 1))
		eye.Shape = Enum.PartType.Ball
	end
	part(parent, "Shades", Vector3.new(1.6, 0.35, 0.15), at(0, 1.6, -1.92), DARK, Enum.Material.Glass)
	return body
end

local function build(spot, index, pos)
	local model = Instance.new("Model")
	model.Name = spot.Id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the whole figurine streams in at once
	model:SetAttribute("Id", spot.Id)
	model:SetAttribute("District", spot.District)
	model:SetAttribute("Pos", pos)

	local yaw = Random.new(index * 7919):NextNumber(0, 2 * math.pi) -- the same in every server
	local base = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	-- Pedestal: a pink neon rim under a dark plinth with a cyan neon top.
	local glow = disc(model, "Glow", base, 0.02, 0.3, 4.4, PINK, Enum.Material.Neon)
	local plinth = disc(model, "Base", base, 0.1, 0.5, 3.8, DARK)
	disc(model, "Top", base, 0.6, 0.08, 3.2, CYAN, Enum.Material.Neon)
	local stand = base * CFrame.new(0, 0.68, 0)

	local assets = ServerStorage:FindFirstChild("ArtAssets")
	local template = assets and assets:FindFirstChild("Gator")
	local body
	if template and template:IsA("BasePart") then
		body = template:Clone()
		body.Name = "Gus"
		body.Anchored = true
		body.CanCollide = false
		body.CanTouch = false
		body.CanQuery = false
		body.Size = body.Size * GATOR_SCALE
		body.CFrame = stand * CFrame.new(0, body.Size.Y / 2, 0)
		body.Parent = model
	else
		body = partGator(model, stand)
	end

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 120, 200)
	light.Range = 7
	light.Brightness = 0.7
	light.Shadows = false
	light.Parent = glow

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GusPrompt"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = "Gus figurine"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = body
	prompt.Triggered:Connect(function(player)
		local ok, err = pcall(CollectibleService.TryPickUp, player, spot, pos)
		if not ok then
			warn("[CollectibleService] pick-up failed: " .. tostring(err))
		end
	end)

	model.PrimaryPart = plinth
	model.Parent = folder
	return model
end

------------------------------------------------------------------ progress

-- Count, comma list (config order) and the district's count for a player's found set.
local function tally(found, district)
	local count, ids, inDistrict = 0, {}, 0
	for _, s in ipairs(Collectibles.Spots) do
		if found[s.Id] then
			count += 1
			table.insert(ids, s.Id)
			if s.District == district then
				inDistrict += 1
			end
		end
	end
	return count, table.concat(ids, ","), inDistrict
end

local function publish(player, data)
	local found = data.found or {}
	local count, ids = tally(found)
	player:SetAttribute("GusFoundIds", ids) -- first: the client's detector waits for GusTotal
	player:SetAttribute("GusFound", count)
	player:SetAttribute("GusTotal", TOTAL)
	data.flags = data.flags or {}
	if count >= TOTAL and TOTAL > 0 then
		data.flags.gusHunter = true
	end
	if data.flags.gusHunter then
		player:SetAttribute(UNLOCK_ATTR, true)
	end
	return count
end

-- Server-checked pick-up (the prompt's Triggered). Public so tests can call it.
function CollectibleService.TryPickUp(player, spot, pos)
	if not RateLimit.Allow(player, "GusPickUp", 2) then
		return false
	end
	local data = DataService.Get(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not data or not (root and root:IsA("BasePart")) then
		return false
	end
	if (root.Position - pos).Magnitude > REACH then
		return false
	end
	data.found = data.found or {}
	if data.found[spot.Id] then
		return false
	end
	data.found[spot.Id] = true

	local count, _, districtCount = tally(data.found, spot.District)
	local districtTotal = #Collectibles.ByDistrict[spot.District]
	local districtDone = districtCount >= districtTotal -- this find completed it (it was missing before)
	local allDone = count >= TOTAL
	local cash = EconomyService.AddCash(player, Collectibles.Cash, "collectible:" .. spot.Id)
	local bonus = 0
	if districtDone then
		local key = string.gsub(spot.District, "%s", "")
		bonus = EconomyService.AddCash(player, Collectibles.DistrictBonus, "collectible:district_" .. key)
	end
	publish(player, data) -- sets Unlock_GusHunter and the saved flag on the last one

	gusFound:FireClient(player, {
		Id = spot.Id,
		Count = count,
		Total = TOTAL,
		District = spot.District,
		DistrictCount = districtCount,
		DistrictTotal = districtTotal,
		DistrictDone = districtDone,
		AllDone = allDone,
		Cash = cash + bonus,
		Bonus = bonus,
	})
	Telemetry.Custom(player, "Collectible", count)
	if allDone then
		Telemetry.Custom(player, "Collectible_All", TOTAL)
		feed:FireAllClients("EventDone", { Name = player.DisplayName, Text = "found all " .. TOTAL .. " Gus figurines" })
	end
	if districtDone then
		task.spawn(DataService.SaveNow, player) -- milestones are worth a save right away
	end
	-- After the remote, so the GUS FOUND stamp queues before any RANK UP stamp.
	local ok, err = pcall(ProgressService.Event, player, "Collectible", 1)
	if not ok then
		warn("[CollectibleService] XP: " .. tostring(err))
	end
	return true
end

------------------------------------------------------------------ start-up

local function placeAll()
	local placed, nudged = 0, 0
	for index, spot in ipairs(Collectibles.Spots) do
		local ok, pos, moved = pcall(findPlace, spot)
		if not ok then
			warn("[CollectibleService] " .. spot.Id .. ": " .. tostring(pos))
		elseif not pos then
			warn(string.format("[CollectibleService] no clear ground within 40 studs of %s (%d, %d); figurine skipped. "
				.. "Fix its X/Z in Config.Collectibles.", spot.Id, spot.X, spot.Z))
		else
			local built, err = pcall(build, spot, index, pos)
			if built then
				placed += 1
				if moved and moved > 0 then
					nudged += 1
				end
			else
				warn("[CollectibleService] " .. spot.Id .. " build failed: " .. tostring(err))
			end
		end
		folder:SetAttribute("Placed", placed)
		task.wait() -- one spot per frame at least
	end
	print(string.format("[CollectibleService] %d/%d Gus figurines placed (%d nudged off their spot)", placed, TOTAL, nudged))
end

function CollectibleService.Init()
	gusFound = Remotes.Event("GusFound")
	feed = Remotes.Event("Feed")
	folder = Workspace:FindFirstChild("Collectibles")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Collectibles"
		folder.Parent = Workspace
	end
	folder:SetAttribute("Total", TOTAL)
	folder:SetAttribute("Placed", 0)

	DataService.OnLoaded(function(player, data)
		if player.Parent == Players then
			publish(player, data)
		end
	end)

	task.spawn(function()
		task.wait(2) -- let the services after this one build their props first (car meet lot, etc.)
		placeAll()
	end)
end

return CollectibleService
