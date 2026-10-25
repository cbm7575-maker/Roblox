-- MapService (ModuleScript, ServerScriptService.Services.MapService)
-- Tells every client where things are, so the phone's GPS and the minimap work even for places that
-- aren't streamed in yet.
--   ReplicatedStorage attribute "Places": JSON list of { n = name, k = kind label, c = category, x, z, id }.
--     Categories: "Activity" (races, stunts, drift, taxi), "Service" (hideout, chop shop, spray, fence,
--     police, the gun store), "Heist" (every heist site; id = the site's name in Workspace.Heists).
--     Heist entries also carry (from Config.Heists): HeistId (type key), Tier (1-3), MinRank (civilian
--     rank needed, 1 = anyone) and NeedsPrep (true when a prep job must be done first), so the
--     tutorial can pick a beginner heist.
--   ReplicatedStorage attribute "OpenHeists": comma list of heist site names robbable right now
--     (refreshed every 2 seconds from the site attributes HeistService sets).
--   ReplicatedStorage attribute "MapShapes": JSON { t = ground tiles, b = building footprints }, each
--     { x, z, sx, sz, yaw (degrees), c = colour index into MAP_COLORS on the client } for the minimap.
--   ReplicatedStorage attribute "Districts": JSON list of { n = district name (the Workspace.City.Ground
--     part's name, e.g. "SolanaHeights"), x, z, sx, sz, r = yaw (degrees) }, one per ground tile, so
--     DistrictClient knows where you are even where the ground hasn't streamed in.
--   ReplicatedStorage attribute "HangoutSpots": JSON list of { x, y, z, r = yaw (degrees, the way the
--     ped faces), k = "sit" | "lie" | "stand", g = group ("Bench", "BusStop", "Lounger", "Plaza",
--     "CarMeet") } where PedClient seats its stationary hangout pedestrians. y is the seat or bed top
--     (sit, lie) or the ground (stand). Built from the benches, bus stops and loungers in
--     Workspace.City.Art, the Solana Plaza fountain and the car meet lot.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Activities = require(ReplicatedStorage.Shared.Config.Activities)
local Heists = require(ReplicatedStorage.Shared.Config.Heists)
local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)

local MapService = {}

local SERVICE_NAMES = {
	Hideout = "Hideout",
	ChopShop = "Chop Shop",
	SprayAndGo = "Spray & Go",
	PoliceLot = "Police HQ",
}

local SERVICE_KINDS = {
	Hideout = "Bank your bag, change clothes",
	ChopShop = "Deliver boosted cars",
	SprayAndGo = "New paint, lose a star",
	PoliceLot = "Police station",
}

local function pos(inst)
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

local function collect()
	local places = {}
	local function add(name, kind, category, p, id, extra)
		if p then
			local entry = { n = name, k = kind, c = category, x = math.floor(p.X), z = math.floor(p.Z), id = id }
			for key, value in pairs(extra or {}) do
				entry[key] = value
			end
			table.insert(places, entry)
		end
	end
	for _, race in ipairs(Activities.Races or {}) do
		add(race.Name, "Street race", "Activity", race.Start)
	end
	for _, stunt in ipairs(Activities.Stunts or {}) do
		add(stunt.Name, "Stunt jump", "Activity", stunt.Ramp)
	end
	local acts = Workspace:FindFirstChild("Activities")
	if acts then
		add("Drift Zone", "Drift scoring", "Activity", acts:FindFirstChild("DriftZone") and pos(acts.DriftZone))
		add("Taxi Stand", "Taxi job", "Activity", acts:FindFirstChild("TaxiStand") and pos(acts.TaxiStand))
		add("Car Meet", "Show your ride · every 8 min", "Activity", acts:FindFirstChild("CarMeet") and pos(acts.CarMeet))
		add("Courier Depot", "Delivery job", "Activity", acts:FindFirstChild("CourierDepot") and pos(acts.CourierDepot))
	end
	-- The gun store (WeaponService builds it): the GPS point is just outside its door.
	local city = Workspace:FindFirstChild("City")
	local landmarks = city and city:FindFirstChild("Landmarks")
	if landmarks and landmarks:FindFirstChild("ShorelineArms") then
		local store = Weapons.Store
		local door = CFrame.new(store.Position) * CFrame.Angles(0, math.rad(store.Yaw or 0), 0) * CFrame.new(0, 0, -16)
		add(store.Name, store.Kind, "Service", door.Position)
	end
	local spawns = Workspace:FindFirstChild("Spawns")
	if spawns then
		for key, name in pairs(SERVICE_NAMES) do
			local inst = spawns:FindFirstChild(key)
			add(name, SERVICE_KINDS[key], "Service", inst and pos(inst))
		end
	end
	local sites = Workspace:FindFirstChild("Heists")
	if sites then
		for _, site in ipairs(sites:GetChildren()) do
			local heistId = site:GetAttribute("HeistId")
			local def = Heists.Types[heistId]
			local label = def and def.Display or site.Name
			if def and def.Display == "ATM" then
				label = "ATM " .. site.Name:gsub("ATM", "#")
			end
			local extra = def and {
				HeistId = heistId,
				Tier = def.Tier or 1,
				MinRank = def.MinRank or 1,
				NeedsPrep = def.Prep ~= nil,
			} or nil
			add(label, def and ("Tier " .. def.Tier .. " heist") or "Heist", "Heist", pos(site), site.Name, extra)
		end
	end
	return places
end

-- Ground material -> minimap colour key (MinimapClient has the palette).
local GROUND_KEYS = {
	[Enum.Material.Grass] = "grass", [Enum.Material.Sand] = "sand", [Enum.Material.Concrete] = "concrete",
	[Enum.Material.WoodPlanks] = "wood",
}

local function shapes()
	local tiles, buildings = {}, {}
	local function rect(list, cf, sx, sz, key)
		local _, yaw = cf:ToEulerAnglesYXZ()
		table.insert(list, {
			math.floor(cf.X), math.floor(cf.Z), math.floor(sx), math.floor(sz), math.floor(math.deg(yaw)), key,
		})
	end
	local city = Workspace:FindFirstChild("City")
	local ground = city and city:FindFirstChild("Ground")
	if ground then
		for _, p in ipairs(ground:GetChildren()) do
			if p:IsA("BasePart") then
				rect(tiles, p.CFrame, p.Size.X, p.Size.Z, GROUND_KEYS[p.Material] or "grass")
			end
		end
	end
	local art = city and city:FindFirstChild("Art")
	local folder = art and art:FindFirstChild("Buildings")
	if folder then
		for _, m in ipairs(folder:GetChildren()) do
			if m:IsA("Model") then
				local cf, size = m:GetBoundingBox()
				if size.X >= 14 and size.Z >= 14 and size.Y >= 10 then
					rect(buildings, cf, size.X, size.Z, "building")
				end
			end
		end
	end
	local landmarks = city and city:FindFirstChild("Landmarks")
	if landmarks and landmarks:FindFirstChild("ShorelineArms") then
		-- The gun store's walls (WeaponService draws them 30 x 22 around this point of its lot).
		local store = Weapons.Store
		local lot = CFrame.new(store.Position) * CFrame.Angles(0, math.rad(store.Yaw or 0), 0)
		rect(buildings, lot * CFrame.new(0, 0, 1), 30, 22, "building")
	end
	return { t = tiles, b = buildings }
end

local function districts()
	local list = {}
	local city = Workspace:FindFirstChild("City")
	local ground = city and city:FindFirstChild("Ground")
	for _, p in ipairs(ground and ground:GetChildren() or {}) do
		-- District tiles are plain Parts; the ShoreSlope wedges along the beach are not districts.
		if p.ClassName == "Part" and p.Name ~= "ShoreSlope" then
			local _, yaw = p.CFrame:ToEulerAnglesYXZ()
			table.insert(list, {
				n = p.Name, x = math.floor(p.Position.X), z = math.floor(p.Position.Z),
				sx = math.floor(p.Size.X), sz = math.floor(p.Size.Z), r = math.floor(math.deg(yaw) + 0.5),
			})
		end
	end
	return list
end

------------------------------------------------------------------ hangout spots (PedClient)

local SKIP_UNDER = { Prison = true, ChopShop_Garage = true } -- no idle peds inside these
local PLAZA_CENTER = Vector3.new(-15, 0, -250) -- Solana Plaza fountain (fallback if the art is missing)

local function round1(n)
	return math.floor(n * 10 + 0.5) / 10
end

local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 0.01 and f.Unit or Vector3.new(0, 0, -1)
end

local function skipped(inst)
	local p = inst.Parent
	while p and p ~= Workspace do
		if SKIP_UNDER[p.Name] then
			return true
		end
		p = p.Parent
	end
	return false
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include

local function groundY(p, fallback)
	local hit = Workspace:Raycast(Vector3.new(p.X, p.Y + 20, p.Z), Vector3.new(0, -60, 0), groundParams)
	return hit and hit.Position.Y or fallback
end

local function hangouts()
	local spots = {}
	local function add(p, facing, kind, group)
		local f = flat(facing)
		-- CFrame.Angles(0, yaw, 0) looks along f.
		local yaw = math.deg(math.atan2(-f.X, -f.Z))
		table.insert(spots, { x = round1(p.X), y = round1(p.Y), z = round1(p.Z), r = math.floor(yaw + 0.5), k = kind, g = group })
	end
	-- The long horizontal axis of a part, in world space.
	local function longAxis(part)
		return part.Size.X >= part.Size.Z and part.CFrame.RightVector or part.CFrame.LookVector
	end
	local city = Workspace:FindFirstChild("City")
	local acts = Workspace:FindFirstChild("Activities")
	local include: { Instance } = { Workspace.Terrain }
	if city then
		table.insert(include, city)
	end
	if acts then
		table.insert(include, acts)
	end
	groundParams.FilterDescendantsInstances = include
	local art = city and city:FindFirstChild("Art")
	if art then
		for _, m in ipairs(art:GetDescendants()) do
			if not m:IsA("Model") or skipped(m) then
				continue
			end
			if m.Name == "Bench" or m.Name == "BusStop" then
				local seat = m:FindFirstChild("Seat")
				local back = m:FindFirstChild("Back") or m:FindFirstChild("Glass")
				if seat and seat:IsA("BasePart") then
					local facing = back and back:IsA("BasePart") and (seat.Position - back.Position) or seat.CFrame.LookVector
					local top = seat.Position.Y + seat.Size.Y / 2
					local axis = flat(longAxis(seat))
					local long = math.max(seat.Size.X, seat.Size.Z)
					local spread = long >= 7 and 2 or (long >= 5 and 1.5 or 0)
					for _, s in ipairs(spread > 0 and { -1, 1 } or { 0 }) do
						local p = seat.Position + axis * spread * s
						add(Vector3.new(p.X, top, p.Z), facing, "sit", m.Name)
					end
				end
			elseif m.Name == "Lounger" then
				local bed = m:FindFirstChild("Bed")
				local back = m:FindFirstChild("Back")
				if bed and bed:IsA("BasePart") and back and back:IsA("BasePart") then
					-- "facing" for a lounger is the way the head points (toward the backrest).
					local top = bed.Position.Y + bed.Size.Y / 2
					add(Vector3.new(bed.Position.X, top, bed.Position.Z), back.Position - bed.Position, "lie", "Lounger")
				end
			end
		end
	end
	-- Solana Plaza: a ring of people around the fountain, facing it.
	local plaza = art and art:FindFirstChild("SolanaPlaza", true)
	local fountain = plaza and plaza:FindFirstChild("Fountain")
	local centre = fountain and fountain:IsA("BasePart") and fountain.Position or PLAZA_CENTER
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + 0.2
		local p = Vector3.new(centre.X + math.cos(a) * 18, 0, centre.Z + math.sin(a) * 18)
		add(Vector3.new(p.X, groundY(p, 0.1), p.Z), centre - p, "stand", "Plaza")
	end
	-- Car meet spectators: behind each show spot (out of the way of cars driving in), facing it.
	local lot = acts and acts:FindFirstChild("CarMeet")
	if lot then
		local lotPos = pos(lot)
		for _, spot in ipairs(lot:GetChildren()) do
			if spot:IsA("BasePart") and spot.Name == "ShowSpot" and lotPos then
				local toAisle = lotPos.Z > spot.Position.Z and 1 or -1
				for _, dx in ipairs({ -4, 4 }) do
					local p = spot.Position + Vector3.new(dx, 0, -toAisle * (spot.Size.Z / 2 + 2))
					add(Vector3.new(p.X, groundY(p, 0.3), p.Z), Vector3.new(0, 0, toAisle), "stand", "CarMeet")
				end
			end
		end
	end
	return spots
end

function MapService.Init()
	ReplicatedStorage:SetAttribute("Places", HttpService:JSONEncode(collect()))
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(shapes())
	end)
	if ok then
		ReplicatedStorage:SetAttribute("MapShapes", encoded)
	end
	local okD, districtList = pcall(function()
		return HttpService:JSONEncode(districts())
	end)
	if okD then
		ReplicatedStorage:SetAttribute("Districts", districtList)
	end
	local okH, spots = pcall(function()
		return HttpService:JSONEncode(hangouts())
	end)
	if okH then
		ReplicatedStorage:SetAttribute("HangoutSpots", spots)
	else
		warn("[MapService] hangout spots: " .. tostring(spots))
	end
	task.spawn(function()
		while true do
			local open = {}
			local sites = Workspace:FindFirstChild("Heists")
			if sites then
				for _, site in ipairs(sites:GetChildren()) do
					if site:GetAttribute("Robbable") then
						table.insert(open, site.Name)
					end
				end
			end
			table.sort(open)
			local s = table.concat(open, ",")
			if ReplicatedStorage:GetAttribute("OpenHeists") ~= s then
				ReplicatedStorage:SetAttribute("OpenHeists", s)
			end
			task.wait(2)
		end
	end)
end

return MapService
