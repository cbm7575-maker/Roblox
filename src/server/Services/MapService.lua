-- MapService (ModuleScript, ServerScriptService.Services.MapService)
-- Tells every client where things are, so the phone's GPS and the minimap work even for places that
-- aren't streamed in yet.
--   ReplicatedStorage attribute "Places": JSON list of { n = name, k = kind label, c = category, x, z, id }.
--     Categories: "Activity" (races, stunts, drift, taxi), "Service" (hideout, chop shop, spray, fence,
--     police), "Heist" (every heist site; id = the site's name in Workspace.Heists).
--   ReplicatedStorage attribute "OpenHeists": comma list of heist site names robbable right now
--     (refreshed every 2 seconds from the site attributes HeistService sets).
--   ReplicatedStorage attribute "MapShapes": JSON { t = ground tiles, b = building footprints }, each
--     { x, z, sx, sz, yaw (degrees), c = colour index into MAP_COLORS on the client } for the minimap.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Activities = require(ReplicatedStorage.Shared.Config.Activities)
local Heists = require(ReplicatedStorage.Shared.Config.Heists)

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
	local function add(name, kind, category, p, id)
		if p then
			table.insert(places, { n = name, k = kind, c = category, x = math.floor(p.X), z = math.floor(p.Z), id = id })
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
			local def = Heists.Types[site:GetAttribute("HeistId")]
			local label = def and def.Display or site.Name
			if def and def.Display == "ATM" then
				label = "ATM " .. site.Name:gsub("ATM", "#")
			end
			add(label, def and ("Tier " .. def.Tier .. " heist") or "Heist", "Heist", pos(site), site.Name)
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
	return { t = tiles, b = buildings }
end

function MapService.Init()
	ReplicatedStorage:SetAttribute("Places", HttpService:JSONEncode(collect()))
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(shapes())
	end)
	if ok then
		ReplicatedStorage:SetAttribute("MapShapes", encoded)
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
