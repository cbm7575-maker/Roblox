-- Look4 (ModuleScript, ServerStorage.Tools.Look4). Studio-only "Look 4.0" world dressing for Port Solana: the
-- layer that makes a sun-drenched coast city in a big open-world game feel lived in. Image billboards over the
-- streets, worn roads, and tall royal palms along the boulevards. Every ad, name and slogan on the images is
-- the game's own invention; this file only places them.
--
-- The game runs it at every server start (CityDressingService, with the images in Config.Textures and
-- ServerStorage.Props.TallPalm), after the services that build lots it keeps clear of. It can also be run in
-- Edit mode to preview, after CityGen, ArtGen, Restyle and Look3 (it reads what they built), from the
-- command bar (then Clear it again, or the server start would find a second set as obstacles):
--
--   print(require(game.ServerStorage.Tools.Look4).Run({
--       Billboards = { "rbxassetid://111", "rbxassetid://222", ... },  -- ad images, 2:1 (1024 x 512)
--       Decals = {                                                     -- road wear images (RGBA, 512 x 512)
--           Crack = { ... }, Oil = { ... }, Patch = { ... }, Manhole = { ... }, Drain = { ... }, Skid = { ... },
--       },
--       PalmTemplate = game.ServerStorage.ArtAssets.RoyalPalm,  -- a Model or MeshPart: a tall royal palm,
--                                                               -- upright, pivot at the trunk base
--       Counts = { TallPalms = 200 },                           -- optional: any key of K.Counts below
--       Seed = 20261015,                                        -- optional: another seed, another city
--   }))
--   print(require(game.ServerStorage.Tools.Look4).Clear())    -- takes everything Look4 made out again
--
-- (After editing this file in Studio, require a fresh copy: require(game.ServerStorage.Tools.Look4:Clone()).
-- In an edit session a plain require keeps returning the first version it loaded.)
--
-- Everything Look4 makes lives in ONE folder, Workspace.City.Art.Look4, with the subfolders Billboards, Decals
-- (one folder per decal kind) and TallPalms. Run calls Clear first, so it can be run again; it is deterministic
-- (Random.new(Seed) per pass), so the same city comes out every time. A missing image list or template only
-- skips that pass. Each pass runs protected: one that fails says so in the summary and the Output window.
--
--   * Billboards (about 36). Rooftop boards on mid-rise roofs (a DecoBuilding's Body / Tier, or a docks
--     Warehouse, whose top is 30..88 studs up) whose roof edge faces a road within 40 studs: two steel legs,
--     back struts, a catwalk, a 24 x 12 board angled square to the road and two lamps on arms under it.
--     Pole boards beside Highway1, the causeway and the avenues: one thick pole, the board's bottom 28..34
--     studs up, double-sided, set square to the road so both directions of traffic read one face. The ad is a
--     Decal on the board's face (so the lamps really light it at night). Lamps are tagged "NightLamp" with a
--     LampColor attribute and carry a SpotLight that starts off: SkyClient lights them after dark. Boards are
--     spread over the districts with streets (round robin), never in the prison island, at most two along the
--     highway's Glades stretch, and never the same image twice within 400 studs. All parts anchored; only the
--     board casts a shadow; the structure collides, the small details don't.
--   * Road decals (about 900). Thin invisible carrier parts (0.05 thick, their bottom 0.02 above the asphalt,
--     no collisions, queries or touches) with a Decal on Top. Manholes in lane centres of city streets every
--     120..200 studs; drains at the kerb edge (where Look3 built a kerb) every 80..120 studs along a downtown,
--     marina or beach street, the side alternating; cracks spread along all paved roads, oil mostly on
--     the approaches to crossings and in lane centres (where cars idle), patches square to the road here and
--     there, skid marks along lanes near crossings, and a few on the Lighthouse Key drift pad. Never on
--     crosswalks, lane dashes, centre lines or parking bays, never on piers, trails or the prison road, and
--     the whole decal must sit on asphalt (the causeway's concrete counts). Each kind sits at its own height
--     (0.01 apart); decals at one height never overlap, so no two coplanar decals flicker.
--   * Tall palms (about 220). Rows on the sidewalk 2.8 studs in from the kerb line (walkers keep to 5 studs
--     out: PedClient) along the beach road (Highway1's straight run beside Flamingo Beach), PalmBlvd, SolanaAve,
--     MarinaRow and the causeway's land end, one every 26..34 studs, clear of crossings, crosswalks, driveways,
--     bus stops, hydrants, signals, street lights, existing palms and billboards (6 studs from any of them),
--     anything solid at the trunk (a 4 x 20 x 4 box), anything solid in the crown (as far out as the
--     template's own crown reaches: no fronds through a facade), home plots, heist sites, the Big Score lots,
--     spawn pads and apartment tower entrances. The template is scaled to 38..46 studs with a random turn
--     about the upright (it keeps the turn its pivot has in the template), casts shadows, and only its trunk
--     collides (a part named "...Trunk..." at most 2.4 thick), or else a thin invisible collision cylinder
--     stands in for it. Scripts inside a template are never copied. When there
--     are more spots than the cap, whole blocks are planted (each road keeps its share), never every other tree.
--
-- Keep-outs, worked out from the place and the shared configs every run:
--   Housing.List      each home's plot (110 x 70) plus the verge in front of it, out to the street
--   Heists.BigScore   the depot and reserve rects (+12 studs)
--   Workspace.Heists  every heist part (+20 studs); Workspace.Spawns and Activities pads (+20 studs)
--   runtime lots      the showrooms and lots services build at start-up (RUNTIME_LOTS, as Restyle has them)
--   Apartments.Pick   every tower ApartmentService could pick (its MinTop / MinRoof / Areas / no hotel sign
--                     rules): nothing on or near its roof, and 50 studs in front of the middle of every facade
--                     kept clear (its street door goes on one of them at start-up)
-- Obstacles come from an index of every part in Workspace.City (and other loose Workspace folders), not only
-- spatial queries: most street furniture is CanQuery = false, which GetPartBoundsInBox can't see.
--
-- Cost: under Counts.Parts (3000) new parts in all (boards first, then decals, then palms take what is left;
-- raised Counts are cut down to fit). About 100
-- SpotLights, all off by day (Counts.BoardLights = false keeps the lamps' glow but drops the lights).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Look4 = {}

-- A shared config module, or nil (a missing one only turns its keep-outs off, with a warning).
local function config(name)
	local ok, mod = pcall(function()
		return require(ReplicatedStorage.Shared.Config[name])
	end)
	if ok and type(mod) == "table" then
		return mod
	end
	warn("[Look4] Config." .. name .. " unavailable: " .. tostring(mod))
	return nil
end

local Heists = config("Heists")
local Housing = config("Housing")
local Apartments = config("Apartments")
local Ambience = config("Ambience")

local K = {
	Seed = 20261015,
	Folder = "Look4",

	-- What Run makes (opts.Counts overrides any of these).
	Counts = {
		RoofBillboards = 20, -- on mid-rise roofs facing a road
		PoleBillboards = 16, -- double-sided, on one tall pole beside the highway, the causeway and the avenues
		TallPalms = 220, -- royal palms along the boulevards (also held under Parts)
		Crack = 260, -- road wear, spread by length over the paved roads...
		Oil = 150,
		Patch = 80,
		Skid = 60,
		DriftSkid = 20, -- ...and skid marks on the Lighthouse Key drift pad (Skid images)
		ManholeEvery = { 120, 200 }, -- studs between manholes along a city street (lane centres)
		DrainEvery = { 80, 120 }, -- studs between kerb drains along a city street (the side alternates)
		MaxDecals = 900, -- every decal together; the wear decals give way to manholes and drains
		Parts = 3000, -- every part Look4 makes
		BoardLights = true, -- a SpotLight in each board lamp (false: the lamps still glow after dark)
	},

	-- Billboards
	Board = Vector3.new(24, 12, 0.8), -- the ad face, 2:1 like the images
	RoofMin = 30, -- roof tops (studs above the ground) that can carry a board...
	RoofMax = 88, -- ...and below this (towers from Config.Apartments.Pick.MinTop up are penthouses)
	RoofReach = 40, -- a road within this many studs straight out from the roof edge
	RoofInset = 4.5, -- the board stands this far in from the roof edge (its lamps end 0.55 inside it)
	RoofLift = { 5, 8 }, -- the legs hold the board's bottom this far above the roof
	RoofBrace = 5, -- the back struts reach this far behind the legs (when the roof is deep enough)
	RoofMinLen = 27, -- roof edge length needed
	RoofMinDepth = 7, -- roof depth needed behind that edge
	RoofGap = 150, -- studs between two rooftop boards
	PoleHeight = { 28, 34 }, -- the board's bottom edge above the ground
	PoleOff = { 14, 19 }, -- the pole's distance out from the road edge
	PoleStep = 55, -- studs between the spots tried along a road
	PoleYaw = 8, -- degrees of random turn off square
	PoleJunction = 30, -- studs clear of a crossing road (corners keep their signals and crosswalks)
	PoleGap = 320, -- studs between two pole boards
	BoardGap = 150, -- studs between any two Look4 boards
	OldBoardGap = 140, -- studs from Look3's text billboards
	GladesPoles = 2, -- pole boards along the highway's Glades stretch, at most (the swamp stays wild)
	SameImageGap = 400, -- never the same ad within this many studs
	Lamp = { Angle = 95, Range = 15, Brightness = 2 },
	BoardAreas = { Downtown = true, Marina = true, Beach = true, Docks = true, Hills = true, Key = true, Glades = true },

	-- Road decals
	DecalTypes = { "Crack", "Oil", "Patch", "Manhole", "Drain", "Skid" },
	DecalSize = { Crack = { 6, 16 }, Oil = { 3, 8 }, Patch = { 6, 14 }, Skid = { 10, 22 } },
	SkidWide = { 3.6, 5 }, -- skid marks run along the image's height (top to bottom): stretched along the lane
	ManholeSize = 3.5,
	-- The drain grate as seen: along the kerb x across (the image's width runs along the kerb). A Decal
	-- stretches its whole image over the face, and the grate fills only 480 x 260 px in the middle of its
	-- 512 x 512 tile, so the carrier is that square tile (DrainTile) round the grate: a 3 x 1.5 carrier
	-- squashed the grate (and its lettering) to half its depth.
	DrainSize = { 3, 1.625 },
	DrainTile = 3.2,
	CarrierThick = 0.05,
	CarrierGap = 0.02, -- carrier bottom above the asphalt
	-- Each kind's own height over the asphalt. Decals at one height never overlap at all (two coplanar decals
	-- flicker); decals at different heights may overlap at their edges (D.free).
	DecalLift = { Patch = 0, Crack = 0.01, Oil = 0.02, Skid = 0.03, DriftSkid = 0.03, Manhole = 0.04, Drain = 0.04 },
	OilAtJunction = 0.6, -- share of the oil on the approaches to a crossing
	SkidAtJunction = 0.5,
	PaintMargin = 0.8, -- studs kept from crosswalks, lane dashes, centre lines and bay lines
	Wear = { Downtown = 1, Marina = 1, Docks = 1.2, Beach = 0.8, Hills = 0.6, Key = 0.6, Glades = 0.35, Sea = 0.5, Island = 0 },
	WearDefault = 0.4,
	DrainAreas = { Downtown = true, Marina = true, Beach = true }, -- (the docks get more cracks instead: K.Wear)

	-- Tall palms
	PalmHeight = { 38, 46 },
	PalmIn = 2.8, -- trunk centre this far in from the road edge
	PalmStep = { 26, 34 },
	PalmSlide = 4, -- after a blocked spot, try again this much further on
	PalmTrunk = 2, -- half size of the trunk box (4 x 20 x 4)
	PalmBox = 20,
	PalmClear = 6, -- studs from street furniture, driveways, crosswalks and other palms
	PalmJunction = 12, -- studs clear of a crossing road along the kerb
	CrownHalf = 5, -- the least crown half size checked (P.info measures the template's own reach)
	CrownFit = 0.85, -- share of the template's measured crown reach that must be clear (frond tips droop below the band)
	CrownY = { 32, 47 }, -- the crown's height band, above the palm's foot
	PalmSink = 0.15,
	PalmPoint = 1.2, -- an existing palm's trunk, as an obstacle (its mesh box is mostly fronds)
	Collider = { Height = 12, Width = 1.8 },
	-- A template trunk thicker than this gets the thin collider instead: a trunk 2.8 out from the road edge
	-- must end before 4 (PedClient's walkers, 2 studs wide, keep to 5 out).
	TrunkMaxWidth = 2.4,
	PalmRoads = { PalmBlvd = true, SolanaAve = true, MarinaRow = true, Causeway = true },
	PalmAreas = { Downtown = true, Marina = true, Beach = true, Docks = true, Hills = true, Key = true },
	LandMin = -1.2, -- dry land: the ground under a palm or pole is no lower than this

	-- Roads (CityGen names)
	RoadKind = {
		Highway1 = "highway", SolanaAve = "avenue", PalmBlvd = "avenue", Causeway = "causeway",
		Street = "street", MarinaRow = "street", MarinaLink = "street", KeyLoop = "street",
	},
	NoRoad = { Pier = true, FerrisPier = true, GladesTrail = true, PrisonBridge = true, PrisonRoad = true },
	RoadProbeY = -0.3, -- a road part is 1 stud thick with its top at 0.1: a level ray here hits its side
	Urban = { Downtown = true, Marina = true, Beach = true, Docks = true, Hills = true },

	-- The obstacle index
	Cell = 32,
	BigCells = 1600,
	FlatTop = 1, -- parts whose top is below this lie on the ground (paving, driveways, lawns)
	Paint = { Crosswalk = true, LaneDash = true, Line = true, BayLine = true, Stall = true, DriftEdge = true },
	Furniture = {
		Hydrant = true, TrashCan = true, NewsBox = true, Bench = true, PlazaBench = true, TrafficSignal = true,
		StreetLight = true, BusStop = true, Billboard = true, LampPost = true, Bin = true, MailPost = true,
		Mailbox = true, SignPost = true, Driveway = true, Planter = true, Umbrella = true, LifeguardTower = true,
		Pylon = true, FlagPole = true, BenchBase = true, TaxiStand = true,
	},
	FlatOk = { Sidewalk = true, Paving = true, Lawn = true, PlazaLawn = true, Grass = true, Sand = true, Pavement = true },
	BuildingModels = { DecoBuilding = true, House = true },
	BuildingParts = { Warehouse = true, RoofTrim = true, RollUpDoor = true, RollerDoor = true, Shop = true },
	BuildingFolders = { "Buildings", "Infill", "BlockFill" },

	-- Keep-outs: per use, the margin round each kind of lot (a kind left out is ignored for that use).
	Margin = {
		palm = { home = 0, bigscore = 12, heist = 20, pad = 20, runtime = 4, tower = 0 },
		board = { home = 4, bigscore = 12, heist = 20, pad = 20, runtime = 8, tower = 0 },
		decal = { heist = 2, pad = 2 },
	},
	MaxMargin = 20,
	HomeLot = { X = 62, Front = 100, Back = 42 }, -- lot space: x -62..62, z -100 (the street side)..42
	TowerDoor = { Half = 22, Out = 50 }, -- per facade: 44 wide, 50 out (DoorRoom 28 x 9, RoadReach 45)
	-- { x0, x1, z0, z1 }: lots services build on at start-up (keep in step with Restyle's RUNTIME_LOTS)
	RuntimeLots = {
		{ -210, -90, -543, -457 }, -- the car showroom downtown
		{ 1668, 1700, 975, 1110 }, -- the boat showroom dock
		{ -278, -218, -354, -306 }, -- the taser shop
		{ 545, 695, 725, 835 }, -- the car meet lot
		{ 537, 583, 617, 663 }, -- the courier depot
	},
	-- Workspace folders whose parts are keep-out lots (not obstacles), and their kind
	WorkspaceLots = {
		Heists = "heist", Spawns = "pad", Activities = "pad", BigScore = "bigscore",
		Homes = "runtime", Dealerships = "runtime", Shops = "runtime", Apartments = "runtime",
	},

	Col = {
		Steel = Color3.fromRGB(66, 70, 76),
		Grate = Color3.fromRGB(84, 88, 94),
		Board = Color3.fromRGB(28, 30, 34),
		Concrete = Color3.fromRGB(170, 168, 162),
		LampDay = Color3.fromRGB(226, 226, 220), -- SkyClient's unlit lamp colour
		LampLit = Color3.fromRGB(255, 232, 196),
		Bark = Color3.fromRGB(120, 104, 86),
	},
}

-- Run state (U.setup fills it in).
local S = {}

-- Helpers: 2D boxes, the grids, roads, parts ----------------------------------------------------------------

local U = {}

function U.unit2(x, z)
	local m = math.sqrt(x * x + z * z)
	if m < 1e-6 then
		return 1, 0
	end
	return x / m, z / m
end

function U.dist(x1, z1, x2, z2)
	return math.sqrt((x1 - x2) ^ 2 + (z1 - z2) ^ 2)
end

-- A box on the map: centre (x, z), unit axis u = (ux, uz) with half size hx, and v = (-uz, ux) with half size hz.
function U.obb(x, z, ux, uz, hx, hz)
	return { x = x, z = z, ux = ux, uz = uz, hx = hx, hz = hz }
end

-- The same box as a part of size (2 hx, _, 2 hz) turned by CFrame.Angles(0, yaw, 0).
function U.yawObb(x, z, yaw, hx, hz)
	return U.obb(x, z, math.cos(yaw), -math.sin(yaw), hx, hz)
end

-- A box in a frame's own x (hx) and z (hz), for a frame with an upright Y axis.
function U.obbFrame(cf, hx, hz)
	local ux, uz = U.unit2(cf.RightVector.X, cf.RightVector.Z)
	return U.obb(cf.X, cf.Z, ux, uz, hx, hz)
end

function U.grow(o, m)
	return U.obb(o.x, o.z, o.ux, o.uz, o.hx + m, o.hz + m)
end

function U.proj(o, ax, az)
	return o.hx * math.abs(o.ux * ax + o.uz * az) + o.hz * math.abs(-o.uz * ax + o.ux * az)
end

-- Separating-axis test for two boxes on the map.
function U.overlap(a, b)
	local dx, dz = b.x - a.x, b.z - a.z
	local axes = { a.ux, a.uz, -a.uz, a.ux, b.ux, b.uz, -b.uz, b.ux }
	for k = 1, 7, 2 do
		local ax, az = axes[k], axes[k + 1]
		if math.abs(dx * ax + dz * az) > U.proj(a, ax, az) + U.proj(b, ax, az) then
			return false
		end
	end
	return true
end

function U.corners(o)
	local vx, vz = -o.uz, o.ux
	local list = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			table.insert(list, Vector3.new(o.x + o.ux * o.hx * sx + vx * o.hz * sz, 0, o.z + o.uz * o.hx * sx + vz * o.hz * sz))
		end
	end
	return list
end

-- Half the vertical extent of a box with this CFrame and size.
function U.extentY(cf, s)
	return math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
end

-- A part's footprint on the map and its height range: box, y0, y1.
function U.partBox(p)
	local cf, s = p.CFrame, p.Size
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	if math.abs(u.Y) > 0.985 then
		local ux, uz = U.unit2(r.X, r.Z)
		return U.obb(cf.X, cf.Z, ux, uz, s.X / 2, s.Z / 2), cf.Y - s.Y / 2, cf.Y + s.Y / 2
	elseif math.abs(r.Y) > 0.985 then -- an upright cylinder: its X axis points up
		local ux, uz = U.unit2(u.X, u.Z)
		return U.obb(cf.X, cf.Z, ux, uz, s.Y / 2, s.Z / 2), cf.Y - s.X / 2, cf.Y + s.X / 2
	elseif math.abs(l.Y) > 0.985 then
		local ux, uz = U.unit2(r.X, r.Z)
		return U.obb(cf.X, cf.Z, ux, uz, s.X / 2, s.Y / 2), cf.Y - s.Z / 2, cf.Y + s.Z / 2
	end
	local ex = math.abs(r.X) * s.X / 2 + math.abs(u.X) * s.Y / 2 + math.abs(l.X) * s.Z / 2
	local ez = math.abs(r.Z) * s.X / 2 + math.abs(u.Z) * s.Y / 2 + math.abs(l.Z) * s.Z / 2
	local ey = U.extentY(cf, s)
	return U.obb(cf.X, cf.Z, 1, 0, ex, ez), cf.Y - ey, cf.Y + ey
end

-- Every corner of a box lies on the top of part R, at least `inset` in from its edges.
function U.inside(R, o, inset)
	for _, c in ipairs(U.corners(o)) do
		local rel = R.CFrame:PointToObjectSpace(Vector3.new(c.X, R.Position.Y, c.Z))
		if math.abs(rel.X) > R.Size.X / 2 - inset or math.abs(rel.Z) > R.Size.Z / 2 - inset then
			return false
		end
	end
	return true
end

-- Grids of items { o = box, y0, y1, kind, name } on K.Cell-stud cells (huge items sit in a list of their own).
function U.grid()
	return { cells = {}, big = {}, q = 0 }
end

function U.key(i, j)
	return (i + 4096) * 16384 + (j + 4096)
end

function U.add(g, item)
	local o = item.o
	local ex = o.hx * math.abs(o.ux) + o.hz * math.abs(o.uz)
	local ez = o.hx * math.abs(o.uz) + o.hz * math.abs(o.ux)
	local C = K.Cell
	local i0, i1 = math.floor((o.x - ex) / C), math.floor((o.x + ex) / C)
	local j0, j1 = math.floor((o.z - ez) / C), math.floor((o.z + ez) / C)
	if (i1 - i0 + 1) * (j1 - j0 + 1) > K.BigCells then
		table.insert(g.big, item)
		return
	end
	for i = i0, i1 do
		for j = j0, j1 do
			local key = U.key(i, j)
			local list = g.cells[key]
			if not list then
				list = {}
				g.cells[key] = list
			end
			table.insert(list, item)
		end
	end
end

-- The first item overlapping box o within heights y0..y1. accept(item) -> false (skip it), true, or a margin
-- (studs the box grows by for that item); reach = the largest margin accept can give.
function U.find(g, o, y0, y1, accept, reach)
	g.q += 1
	local stamp = g.q
	local r = reach or 0
	local ex = o.hx * math.abs(o.ux) + o.hz * math.abs(o.uz) + r
	local ez = o.hx * math.abs(o.uz) + o.hz * math.abs(o.ux) + r
	local function try(item)
		if item.stamp == stamp then
			return false
		end
		item.stamp = stamp
		if item.y1 < y0 or item.y0 > y1 then
			return false
		end
		local m = 0
		if accept then
			m = accept(item)
			if not m then
				return false
			end
			if m == true then
				m = 0
			end
		end
		if m > 0 then
			return U.overlap(item.o, U.grow(o, m))
		end
		return U.overlap(item.o, o)
	end
	for _, item in ipairs(g.big) do
		if try(item) then
			return item
		end
	end
	local C = K.Cell
	for i = math.floor((o.x - ex) / C), math.floor((o.x + ex) / C) do
		for j = math.floor((o.z - ez) / C), math.floor((o.z + ez) / C) do
			local list = g.cells[U.key(i, j)]
			if list then
				for _, item in ipairs(list) do
					if try(item) then
						return item
					end
				end
			end
		end
	end
	return nil
end

-- Is box o inside a keep-out lot for this use ("palm", "board" or "decal")?
function U.lotHit(use, o)
	local margins = K.Margin[use]
	return U.find(S.lots, o, -math.huge, math.huge, function(item)
		local m = margins[item.kind]
		if m == nil then
			return false
		end
		return m
	end, K.MaxMargin) ~= nil
end

-- Config.Ambience's area key at a spot (the first rectangle wins; open water east of the land is Sea).
function U.area(x, z)
	for _, d in ipairs(S.districts) do
		local r = d.Rect
		if x >= r[1] and x <= r[2] and z >= r[3] and z <= r[4] then
			return d.Area
		end
	end
	local sea = Ambience and Ambience.Sea
	if sea and x >= sea.X0 and x <= sea.X1 and z >= sea.Z0 and z <= sea.Z1 then
		return sea.Area
	end
	return nil
end

-- The first ground, road or kerb straight below (x, z), or nil.
function U.ground(x, z)
	return Workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -160, 0), S.rayGround)
end

-- A point of road line L: t studs along it, lat studs out to its +n side.
function U.at(L, t, lat)
	return Vector3.new(L.dx * t + L.nx * (L.off + lat), 0, L.dz * t + L.nz * (L.off + lat))
end

-- The yaw of CFrame.Angles(0, yaw, 0) whose LookVector runs along line L (its RightVector is then L's +n).
function U.roadYaw(L)
	return math.atan2(-L.dx, -L.dz)
end

-- Lane centres (lateral offsets): two lanes each way from 50 studs wide (TrafficClient), else one.
function U.lanes(L)
	if L.w >= 50 then
		return { -L.w * 3 / 8, -L.w / 8, L.w / 8, L.w * 3 / 8 }
	end
	return { -L.w / 4, L.w / 4 }
end

-- The crossing of line L within (its half width + pad) of t, or nil.
function U.nearJunction(L, t, pad)
	for _, c in ipairs(L.cross) do
		if math.abs(t - c.t) < c.w / 2 + pad then
			return c
		end
	end
	return nil
end

function U.shuffle(list, rng)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- A list of the arguments that aren't nil.
function U.some(...)
	local out = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if v then
			table.insert(out, v)
		end
	end
	return out
end

-- Image ids from a list: strings as given ("rbxassetid://..."), bare numbers made into asset ids.
function U.idList(list)
	local out = {}
	if type(list) ~= "table" then
		return out
	end
	for _, v in ipairs(list) do
		if type(v) == "number" then
			table.insert(out, "rbxassetid://" .. tostring(math.floor(v)))
		elseif type(v) == "string" and v ~= "" then
			if string.match(v, "^%d+$") then
				v = "rbxassetid://" .. v
			end
			table.insert(out, v)
		end
	end
	return out
end

-- { min, max } from a Counts entry, or the defaults.
function U.range(v, a, b)
	if type(v) == "table" and tonumber(v[1]) and tonumber(v[2]) then
		return math.min(v[1], v[2]), math.max(v[1], v[2])
	end
	return a, b
end

-- Sort Instances by where they stand (x, then z, then name): the same order on every run.
function U.sortByPos(list)
	local at = {}
	for _, inst in ipairs(list) do
		local p = Vector3.zero
		if inst:IsA("Model") then
			p = inst:GetPivot().Position
		elseif inst:IsA("BasePart") then
			p = inst.Position
		end
		at[inst] = p
	end
	table.sort(list, function(a, b)
		local pa, pb = at[a], at[b]
		if pa.X ~= pb.X then
			return pa.X < pb.X
		end
		if pa.Z ~= pb.Z then
			return pa.Z < pb.Z
		end
		return a.Name < b.Name
	end)
	return list
end

-- A DecoBuilding's highest Body / Tier part and the height of its top (as ApartmentService reads it).
function U.topOf(model)
	local top, topY = nil, -math.huge
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and (p.Name == "Body" or p.Name == "Tier") then
			local y = p.Position.Y + p.Size.Y / 2
			if y > topY then
				top, topY = p, y
			end
		end
	end
	return top, topY
end

-- The four upright faces of a box part: outward normal n, half depth along n, half length along a.
function U.faces(cf, s)
	local lx, lz = U.unit2(cf.LookVector.X, cf.LookVector.Z)
	local rx, rz = U.unit2(cf.RightVector.X, cf.RightVector.Z)
	return {
		{ nx = lx, nz = lz, hd = s.Z / 2, hl = s.X / 2, ax = rx, az = rz }, -- the front (a DecoBuilding faces its street)
		{ nx = -lx, nz = -lz, hd = s.Z / 2, hl = s.X / 2, ax = rx, az = rz },
		{ nx = rx, nz = rz, hd = s.X / 2, hl = s.Z / 2, ax = lx, az = lz },
		{ nx = -rx, nz = -rz, hd = s.X / 2, hl = s.Z / 2, ax = lx, az = lz },
	}
end

function U.isPalm(name)
	return name == "Palm" or name == "PalmTree" or (string.len(name) > 4 and string.sub(name, -4) == "Palm")
end

-- A road a building can face: anything but the wooden piers.
function U.isDriveRoad(inst)
	return inst.Name ~= "Pier" and inst.Name ~= "FerrisPier" and inst.Material ~= Enum.Material.WoodPlanks
end

-- A road a decal can lie on: asphalt (or the causeway's concrete), not a pier, trail or the prison road.
function U.isPaveRoad(inst)
	if K.NoRoad[inst.Name] or inst.Material == Enum.Material.WoodPlanks then
		return false
	end
	return inst.Material == Enum.Material.Asphalt or inst.Name == "Causeway"
end

function U.part(parent, name, size, cf, color, material, solid)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.CanTouch = false
	p.CanCollide = solid == true -- first: CanQuery can only go off once CanCollide is off
	p.CanQuery = solid == true
	p.Parent = parent
	S.parts += 1
	return p
end

-- An upright cylinder standing on `base`.
function U.cyl(parent, name, base, height, width, color, material, solid)
	local p = U.part(parent, name, Vector3.new(height, width, width),
		CFrame.new(base.X, base.Y + height / 2, base.Z) * CFrame.Angles(0, 0, math.pi / 2), color, material, solid)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A thin bar from point a to point b.
function U.rod(parent, name, a, b, thick, color)
	return U.part(parent, name, Vector3.new(thick, thick, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, Enum.Material.Metal, false)
end

-- Setup: the obstacle index, the keep-out lots, the road lines ---------------------------------------------

-- What a part is to the placers: "paint" (markings on the road), "palm", "furn" (street furniture), "bld",
-- "solid", or nil (not an obstacle: kerbs, hidden placeholders, invisible helpers).
function U.classify(p, landmark)
	local name = p.Name
	if K.Paint[name] then
		return "paint"
	end
	if name == "Kerb" then
		return nil
	end
	if p.Transparency >= 0.99 and not p.CanCollide then
		return nil
	end
	local parent = p.Parent
	local pm = (parent and parent:IsA("Model")) and parent.Name or ""
	local grand = parent and parent.Parent
	local gm = (grand and grand:IsA("Model")) and grand.Name or ""
	if U.isPalm(name) or U.isPalm(pm) then
		return "palm"
	end
	if K.Furniture[name] or K.Furniture[pm] or K.Furniture[gm] then
		return "furn"
	end
	if landmark or K.BuildingModels[pm] or K.BuildingParts[name] then
		return "bld"
	end
	return "solid"
end

function U.addPart(p, kind)
	local o, y0, y1 = U.partBox(p)
	if o.hx > 400 and o.hz > 400 then
		return -- a slab the size of a district (a stray baseplate): no obstacle at this scale
	end
	if kind == "palm" then
		-- A palm is its trunk at street level (6 studs kept from it) and a crown up top; a mesh palm's box is
		-- mostly fronds, so the trunk is a small square at its middle.
		local trunk = string.find(string.lower(p.Name), "trunk") ~= nil
		local whole = not (p.Parent and p.Parent:IsA("Model") and U.isPalm(p.Parent.Name))
		if whole or trunk then
			U.add(S.obs, { o = U.obb(o.x, o.z, 1, 0, K.PalmPoint, K.PalmPoint), y0 = y0, y1 = y0 + 14, kind = "furn", name = p.Name })
		end
		if not trunk then
			U.add(S.obs, { o = o, y0 = y0, y1 = y1, kind = "crown", name = p.Name })
		end
		return
	end
	if kind == "solid" and y1 < K.FlatTop then
		kind = "flat"
	end
	U.add(S.obs, { o = o, y0 = y0, y1 = y1, kind = kind, name = p.Name })
end

-- Every part of Workspace.City (but the ground, roads and map walls) and of other loose Workspace folders.
function U.index()
	S.obs = U.grid()
	S.oldBoards = {}
	local seenBoard = {}
	local roots = {}
	for _, c in ipairs(S.city:GetChildren()) do
		if c ~= S.ground and c ~= S.roads and c.Name ~= "Walls" then
			table.insert(roots, c)
		end
	end
	for _, c in ipairs(Workspace:GetChildren()) do
		if c ~= S.city and c ~= Workspace.Terrain and not K.WorkspaceLots[c.Name]
			and (c:IsA("Folder") or c:IsA("Model") or c:IsA("BasePart")) then
			table.insert(roots, c)
		end
	end
	local n = 0
	for _, root in ipairs(roots) do
		local landmark = root.Name == "Landmarks"
		local list = root:GetDescendants()
		if root:IsA("BasePart") then
			table.insert(list, root)
		end
		for _, d in ipairs(list) do
			if d:IsA("BasePart") and not (S.skip and (d == S.skip or d:IsDescendantOf(S.skip))) then
				local kind = U.classify(d, landmark)
				if kind then
					U.addPart(d, kind)
					n += 1
				end
				local board = d.Parent
				if board and board:IsA("Model") and board.Name == "Billboard" and not seenBoard[board] then
					seenBoard[board] = true
					table.insert(S.oldBoards, board:GetPivot().Position)
				end
			end
		end
	end
	return n
end

-- Keep-out lots (see the header).
function U.buildLots()
	S.lots = U.grid()
	local function add(o, kind)
		U.add(S.lots, { o = o, y0 = -math.huge, y1 = math.huge, kind = kind })
	end
	-- Home plots and the verge in front of each, out to its street.
	local h = K.HomeLot
	for _, home in ipairs(Housing and Housing.List or {}) do
		if typeof(home.Position) == "Vector3" and typeof(home.Facing) == "Vector3" then
			local frame = CFrame.lookAt(home.Position, home.Position + home.Facing)
			add(U.obbFrame(frame * CFrame.new(0, 0, (h.Back - h.Front) / 2), h.X, (h.Back + h.Front) / 2), "home")
		end
	end
	-- The Big Score's two lots (real rects, worked out by Config.Heists).
	local big = Heists and Heists.BigScore
	if big then
		for _, key in ipairs({ "DepotRect", "ReserveRect" }) do
			local r = big[key]
			if type(r) == "table" and #r == 4 then
				add(U.obb((r[1] + r[2]) / 2, (r[3] + r[4]) / 2, 1, 0, math.abs(r[2] - r[1]) / 2, math.abs(r[4] - r[3]) / 2), "bigscore")
			end
		end
	end
	for _, r in ipairs(K.RuntimeLots) do
		add(U.obb((r[1] + r[2]) / 2, (r[3] + r[4]) / 2, 1, 0, (r[2] - r[1]) / 2, (r[4] - r[3]) / 2), "runtime")
	end
	-- Gameplay parts: heist sites, spawn and service pads, activities (CanQuery = false: no query sees them).
	for name, kind in pairs(K.WorkspaceLots) do
		local f = Workspace:FindFirstChild(name)
		for _, d in ipairs(f and f:GetDescendants() or {}) do
			if d:IsA("BasePart") then
				local o = U.partBox(d)
				add(o, kind)
			end
		end
	end
	-- Apartment towers ApartmentService could pick (Config.Apartments.Pick): every facade's middle stays clear
	-- out to RoadReach, since its street door goes on one of them at start-up.
	S.towers = 0
	local pick = Apartments and Apartments.Pick or {}
	local minTop = pick.MinTop or 90
	local minRoof = pick.MinRoof or 56
	for _, folderName in ipairs(pick.Folders or K.BuildingFolders) do
		local f = S.art:FindFirstChild(folderName)
		for _, m in ipairs(f and f:GetChildren() or {}) do
			local body = m:IsA("Model") and m.Name == "DecoBuilding" and not m:FindFirstChild("Sign") and m:FindFirstChild("Body")
			if body and body:IsA("BasePart") then
				local top, topY = U.topOf(m)
				local area = U.area(body.Position.X, body.Position.Z)
				if top and topY >= minTop - 0.5 and math.min(top.Size.X, top.Size.Z) >= minRoof - 0.5
					and (not pick.Areas or pick.Areas[area or ""]) then
					S.towers += 1
					local door = K.TowerDoor
					for _, face in ipairs(U.faces(body.CFrame, body.Size)) do
						local cx = body.Position.X + face.nx * (face.hd + door.Out / 2)
						local cz = body.Position.Z + face.nz * (face.hd + door.Out / 2)
						add(U.obb(cx, cz, face.ax, face.az, door.Half, door.Out / 2), "tower")
					end
				end
			end
		end
	end
end

-- A crossing of line L by road piece s, recorded as { t, w } on L (T-junctions count too).
function U.addCrossing(L, s)
	local half = (s.t1 - s.t0) / 2
	local ax, az = s.cx - s.dx * half, s.cz - s.dz * half
	local bx, bz = s.cx + s.dx * half, s.cz + s.dz * half
	local da = ax * L.nx + az * L.nz - L.off
	local db = bx * L.nx + bz * L.nz - L.off
	local px, pz
	if (da <= 0 and db >= 0) or (da >= 0 and db <= 0) then
		if da == db then
			return
		end
		local f = da / (da - db)
		px, pz = ax + (bx - ax) * f, az + (bz - az) * f
	else
		local reach = L.w / 2 + 2
		if math.abs(da) <= reach and math.abs(da) <= math.abs(db) then
			px, pz = ax, az
		elseif math.abs(db) <= reach then
			px, pz = bx, bz
		else
			return
		end
	end
	local t = px * L.dx + pz * L.dz
	if t < L.t0 - 2 or t > L.t1 + 2 then
		return
	end
	for _, c in ipairs(L.cross) do
		if math.abs(c.t - t) < 8 then
			c.w = math.max(c.w, s.w)
			return
		end
	end
	table.insert(L.cross, { t = t, w = s.w, name = s.name })
end

-- Road lines: the pieces of Workspace.City.Roads joined into straight runs (same name, same line), each with
-- its crossings. A line runs along (dx, dz); points are dir * t + n * (off + lateral), n = (-dz, dx).
function U.buildLines()
	local segs = {}
	for _, p in ipairs(S.roads:GetChildren()) do
		if p:IsA("BasePart") then
			local dx, dz = U.unit2(p.CFrame.LookVector.X, p.CFrame.LookVector.Z)
			if dx < -1e-4 or (math.abs(dx) <= 1e-4 and dz < 0) then
				dx, dz = -dx, -dz
			end
			-- CityGen lengthens each piece by half its width so joints overlap: undo that.
			local len = math.max(0, p.Size.Z - p.Size.X * 0.5)
			local nx, nz = -dz, dx
			local off = p.Position.X * nx + p.Position.Z * nz
			local tc = p.Position.X * dx + p.Position.Z * dz
			table.insert(segs, {
				name = p.Name, w = p.Size.X, dx = dx, dz = dz, nx = nx, nz = nz, off = off,
				t0 = tc - len / 2, t1 = tc + len / 2, cx = p.Position.X, cz = p.Position.Z, mat = p.Material,
				key = string.format("%s|%d|%d|%d", p.Name, math.floor(dx * 1000 + 0.5), math.floor(dz * 1000 + 0.5), math.floor(off + 0.5)),
			})
		end
	end
	table.sort(segs, function(a, b)
		if a.key ~= b.key then
			return a.key < b.key
		end
		return a.t0 < b.t0
	end)
	S.lines = {}
	local cur = nil
	for _, s in ipairs(segs) do
		if cur and cur.key == s.key and s.t0 <= cur.t1 + 3 then
			cur.t1 = math.max(cur.t1, s.t1)
			cur.w = math.max(cur.w, s.w)
		else
			cur = {
				key = s.key, name = s.name, w = s.w, dx = s.dx, dz = s.dz, nx = s.nx, nz = s.nz, off = s.off,
				t0 = s.t0, t1 = s.t1, mat = s.mat, cross = {},
				kind = K.RoadKind[s.name] or ((s.mat == Enum.Material.Asphalt) and "street" or "other"),
				usable = not K.NoRoad[s.name] and s.mat ~= Enum.Material.WoodPlanks,
			}
			table.insert(S.lines, cur)
		end
		s.line = cur
	end
	for _, L in ipairs(S.lines) do
		for _, s in ipairs(segs) do
			if s.line ~= L then
				local turn = math.abs(L.dx * s.dz - L.dz * s.dx)
				-- (the next piece of a bending road is a continuation, not a crossing)
				if turn > 0.17 and not (s.name == L.name and turn < 0.5) then
					U.addCrossing(L, s)
				end
			end
		end
		table.sort(L.cross, function(a, b)
			return a.t < b.t
		end)
	end
	return #S.lines
end

function U.setup(city, opts)
	S.city = city
	S.art = city:FindFirstChild("Art")
	S.ground = city:FindFirstChild("Ground")
	S.roads = city:FindFirstChild("Roads")
	S.paint = S.art:FindFirstChild("RoadPaint") -- Look3's kerbs and lane dashes
	S.skip = typeof(opts.PalmTemplate) == "Instance" and opts.PalmTemplate or nil
	S.parts, S.lights = 0, 0
	S.faces, S.boardSpots = {}, {}
	S.decalSub, S.decalCount = {}, {}
	S.dec = U.grid() -- every decal's middle (70 % of its box)
	S.decLevel = {} -- [lift] = a grid of the whole boxes of the decals at that height
	S.decals, S.decalCap = 0, math.huge
	S.districts = (Ambience and Ambience.Districts) or {}
	S.beachX = 1000 -- the beach's west edge: the beach road runs along it
	for _, d in ipairs(S.districts) do
		if d.Area == "Beach" then
			S.beachX = d.Rect[1]
			break
		end
	end
	S.rayGround = RaycastParams.new()
	S.rayGround.FilterType = Enum.RaycastFilterType.Include
	S.rayGround.FilterDescendantsInstances = U.some(S.ground, S.roads, S.paint)
	S.rayLand = RaycastParams.new()
	S.rayLand.FilterType = Enum.RaycastFilterType.Include
	S.rayLand.FilterDescendantsInstances = { S.ground }
	S.rayRoads = RaycastParams.new()
	S.rayRoads.FilterType = Enum.RaycastFilterType.Include
	S.rayRoads.FilterDescendantsInstances = { S.roads }
	S.rayPaint = RaycastParams.new()
	S.rayPaint.FilterType = Enum.RaycastFilterType.Include
	S.rayPaint.FilterDescendantsInstances = U.some(S.paint)
	S.overRoads = OverlapParams.new()
	S.overRoads.FilterType = Enum.RaycastFilterType.Include
	S.overRoads.FilterDescendantsInstances = { S.roads }
	local indexed = U.index()
	U.buildLots()
	U.buildLines()
	-- Look4's own folder, made after the index so nothing of it is in there.
	S.root = Instance.new("Folder")
	S.root.Name = K.Folder
	S.boardsF = Instance.new("Folder")
	S.boardsF.Name = "Billboards"
	S.boardsF.Parent = S.root
	S.decalsF = Instance.new("Folder")
	S.decalsF.Name = "Decals"
	S.decalsF.Parent = S.root
	S.palmsF = Instance.new("Folder")
	S.palmsF.Name = "TallPalms"
	S.palmsF.Parent = S.root
	S.root.Parent = S.art
	-- Queries for "anything there that a query can see": all but the ground, roads, kerbs and Look4 itself.
	local exclude = U.some(S.ground, S.roads, S.paint, S.root, Workspace.Terrain, S.skip)
	S.overAny = OverlapParams.new()
	S.overAny.FilterType = Enum.RaycastFilterType.Exclude
	S.overAny.FilterDescendantsInstances = exclude
	S.rayView = RaycastParams.new()
	S.rayView.FilterType = Enum.RaycastFilterType.Exclude
	S.rayView.FilterDescendantsInstances = exclude
	return string.format("index: %d parts, %d road lines, %d tower entrances kept clear", indexed, #S.lines, S.towers)
end

-- Billboards ------------------------------------------------------------------------------------------------

local B = {}

-- Everything but road paint and flat ground cover gets in a board's way.
function B.blocks(item)
	return item.kind ~= "paint" and item.kind ~= "flat"
end

-- A lamp under a board (tag "NightLamp"): a pale lens by day; SkyClient lights it in LampColor after dark and
-- switches its SpotLight on.
function B.lamp(parent, pos, aim, lit)
	local lamp = U.part(parent, "BoardLamp", Vector3.new(1.2, 0.6, 0.8), CFrame.lookAt(pos, aim), K.Col.LampDay, Enum.Material.SmoothPlastic, false)
	lamp:SetAttribute("LampColor", K.Col.LampLit)
	CollectionService:AddTag(lamp, "NightLamp")
	if lit then
		local l = Instance.new("SpotLight")
		l.Name = "BoardLight"
		l.Face = Enum.NormalId.Front
		l.Angle = K.Lamp.Angle
		l.Range = K.Lamp.Range
		l.Brightness = K.Lamp.Brightness
		l.Color = K.Col.LampLit
		l.Shadows = false
		l.Enabled = false
		l.Parent = lamp
		S.lights += 1
	end
	return lamp
end

-- An ad face on a board (its image is chosen once every board stands: B.assign).
function B.face(board, face, pos)
	local d = Instance.new("Decal")
	d.Name = "Ad"
	d.Face = face
	d.Color3 = Color3.new(1, 1, 1)
	d.Transparency = 0
	d.Parent = board
	table.insert(S.faces, { decal = d, x = pos.X, z = pos.Z })
end

-- Is a candidate far enough from the boards taken so far (and from Look3's text billboards)?
function B.spaced(c, anyGap, poleGap)
	for _, s in ipairs(S.boardSpots) do
		local d = U.dist(s.x, s.z, c.pos.X, c.pos.Z)
		if d < anyGap or (poleGap and s.pole and d < poleGap) then
			return false
		end
	end
	for _, p in ipairs(S.oldBoards) do
		if U.dist(p.X, p.Z, c.pos.X, c.pos.Z) < K.OldBoardGap then
			return false
		end
	end
	return true
end

-- Up to `want` candidates, district by district in turn (each district's list shuffled), each one passing
-- ok(c). Taken ones are remembered in S.boardSpots.
function B.pick(cands, want, rng, ok)
	local byArea, areas = {}, {}
	for _, c in ipairs(cands) do
		local a = c.area or "?"
		if not byArea[a] then
			byArea[a] = {}
			table.insert(areas, a)
		end
		table.insert(byArea[a], c)
	end
	table.sort(areas)
	for _, a in ipairs(areas) do
		U.shuffle(byArea[a], rng)
	end
	local taken, cursor = {}, {}
	local moved = true
	while #taken < want and moved do
		moved = false
		for _, a in ipairs(areas) do
			if #taken < want then
				local list = byArea[a]
				local i = cursor[a] or 1
				while i <= #list do
					local c = list[i]
					i += 1
					if ok(c) then
						table.insert(taken, c)
						table.insert(S.boardSpots, { x = c.pos.X, z = c.pos.Z, pole = c.G ~= nil })
						moved = true
						break
					end
				end
				cursor[a] = i
			end
		end
	end
	return taken
end

-- Rooftop boards ----------------------------------------------------------------------------------------------

-- The checks for one rooftop board: F = the frame on the roof (origin RoofInset in from the edge, LookVector
-- out over the edge toward the road). Returns the candidate, or nil.
function B.roofCheck(m, R, F, top, lift, brace, gap)
	local back = math.max(1.5, 0.95 + brace + 0.35) -- the legs (or the struts' feet) behind the board
	local front = -3.95 -- the lamps in front of it
	local centre = F * CFrame.new(0, 0, (front + back) / 2)
	local o = U.obbFrame(centre, K.Board.X / 2 + 0.5, (back - front) / 2)
	if not U.inside(R, o, 0.3) then
		return nil
	end
	local y0, y1 = top + 0.15, top + lift + K.Board.Y + 0.6
	if U.find(S.obs, o, y0, y1, B.blocks) or U.lotHit("board", o) then
		return nil
	end
	local box = centre * CFrame.new(0, (y0 + y1) / 2 - top, 0)
	if #Workspace:GetPartBoundsInBox(box, Vector3.new(K.Board.X + 1, y1 - y0, back - front), S.overAny) > 0 then
		return nil
	end
	-- Nothing between the board and its road.
	local boardPos = (F * CFrame.new(0, lift + K.Board.Y / 2, -0.6)).Position
	if Workspace:Raycast(boardPos, F.LookVector * (gap + K.RoofInset + 2), S.rayView) then
		return nil
	end
	return {
		F = F, lift = lift, brace = brace, top = top, pos = boardPos, obb = o, y0 = y0, y1 = y1,
		area = U.area(boardPos.X, boardPos.Z),
	}
end

-- A rooftop board on roof part R (top at `top`): the edges with a road in front, nearest first, the middle
-- of the edge first, then a little to either side.
function B.roofFace(m, R, top, rng)
	local cf = R.CFrame
	local open = {}
	for _, f in ipairs(U.faces(cf, R.Size)) do
		if f.hl * 2 >= K.RoofMinLen and f.hd * 2 >= K.RoofMinDepth then
			local ex, ez = cf.X + f.nx * f.hd, cf.Z + f.nz * f.hd
			local hit = Workspace:Raycast(Vector3.new(ex + f.nx * 0.5, K.RoadProbeY, ez + f.nz * 0.5),
				Vector3.new(f.nx, 0, f.nz) * K.RoofReach, S.rayRoads)
			if hit and U.isDriveRoad(hit.Instance) then
				table.insert(open, { f = f, gap = hit.Distance, ex = ex, ez = ez })
			end
		end
	end
	table.sort(open, function(a, b)
		return a.gap < b.gap
	end)
	for _, e in ipairs(open) do
		local f = e.f
		local slide = math.max(0, f.hl - K.Board.X / 2 - 1.2)
		local offsets = { 0 }
		if slide > 2 then
			table.insert(offsets, slide * 0.55)
			table.insert(offsets, -slide * 0.55)
		end
		-- Struts as long as the roof allows (their feet 0.5 in from its far edge), else none: a tiered roof
		-- leaves only a strip between its edge and the tier.
		local brace = math.clamp(f.hd * 2 - K.RoofInset - 0.95 - 0.35 - 0.5, 0, K.RoofBrace)
		local braces = { brace }
		if brace > 0 then
			table.insert(braces, 0)
		end
		for _, lat in ipairs(offsets) do
			local lift = rng:NextNumber(K.RoofLift[1], K.RoofLift[2])
			local origin = Vector3.new(e.ex - f.nx * K.RoofInset + f.ax * lat, top, e.ez - f.nz * K.RoofInset + f.az * lat)
			local F = CFrame.lookAt(origin, origin + Vector3.new(f.nx, 0, f.nz))
			for _, b in ipairs(braces) do
				local c = B.roofCheck(m, R, F, top, lift, b, e.gap)
				if c then
					return c
				end
			end
		end
	end
	return nil
end

-- The rooftop candidate of one building (a DecoBuilding or a docks Warehouse), or nil.
function B.roofSpot(m, rng)
	local roofs = {}
	local topY = -math.huge
	if m:IsA("Model") and m.Name == "DecoBuilding" then
		if m:FindFirstChild("Sign") then
			return nil -- a hotel keeps its crown sign to itself
		end
		for _, p in ipairs(m:GetChildren()) do
			if p:IsA("BasePart") and (p.Name == "Body" or p.Name == "Tier") then
				table.insert(roofs, p)
				topY = math.max(topY, p.Position.Y + p.Size.Y / 2)
			end
		end
	elseif m:IsA("BasePart") and m.Name == "Warehouse" then
		roofs = { m }
		topY = m.Position.Y + m.Size.Y / 2
	end
	if #roofs == 0 or topY >= S.roofMax then
		return nil -- (a tower: ApartmentService's penthouses go up there)
	end
	local where = U.area(roofs[1].Position.X, roofs[1].Position.Z)
	if not K.BoardAreas[where or ""] or where == "Glades" then
		return nil
	end
	table.sort(roofs, function(a, b)
		return a.Position.Y + a.Size.Y / 2 > b.Position.Y + b.Size.Y / 2
	end)
	for _, R in ipairs(roofs) do
		local top = R.Position.Y + R.Size.Y / 2
		if top >= K.RoofMin and top < S.roofMax and math.abs(R.CFrame.UpVector.Y) > 0.99 then
			local c = B.roofFace(m, R, top, rng)
			if c then
				return c
			end
		end
	end
	return nil
end

function B.roofSpots(rng)
	local list = {}
	for _, folderName in ipairs(K.BuildingFolders) do
		local f = S.art:FindFirstChild(folderName)
		for _, m in ipairs(U.sortByPos(f and f:GetChildren() or {})) do
			local c = B.roofSpot(m, rng)
			if c then
				table.insert(list, c)
			end
		end
	end
	return list
end

-- Two steel legs with back struts, the board in its frame, a catwalk along its foot and two lamps on arms.
function B.buildRoof(c, lit)
	local m = Instance.new("Model")
	m.Name = "RoofBillboard"
	local F, lift = c.F, c.lift
	local cy = lift + K.Board.Y / 2
	local board = U.part(m, "AdBoard", K.Board, F * CFrame.new(0, cy, 0), K.Col.Board, Enum.Material.SmoothPlastic, true)
	board.CastShadow = true
	U.part(m, "AdFrame", Vector3.new(K.Board.X + 0.8, K.Board.Y + 0.8, 0.6), F * CFrame.new(0, cy, 0), K.Col.Steel, Enum.Material.Metal, false)
	local legH = lift + K.Board.Y - 1
	for _, x in ipairs({ -8, 8 }) do
		U.part(m, "BoardLeg", Vector3.new(0.9, legH, 0.9), F * CFrame.new(x, legH / 2, 0.95), K.Col.Steel, Enum.Material.Metal, true)
		if c.brace >= 1.5 then
			U.rod(m, "BoardBrace", F * Vector3.new(x, 0.2, 0.95 + c.brace), F * Vector3.new(x, lift + 3, 0.95), 0.5, K.Col.Steel)
		end
	end
	U.part(m, "Catwalk", Vector3.new(K.Board.X, 0.3, 2.2), F * CFrame.new(0, lift - 0.15, -1.55), K.Col.Grate, Enum.Material.DiamondPlate, true)
	local aim = (F * CFrame.new(0, cy, 0)).Position
	for _, x in ipairs({ -6, 6 }) do
		U.part(m, "LampArm", Vector3.new(0.3, 0.3, 0.7), F * CFrame.new(x, lift - 0.3, -2.95), K.Col.Steel, Enum.Material.Metal, false)
		B.lamp(m, (F * CFrame.new(x, lift - 0.3, -3.4)).Position, aim, lit)
	end
	B.face(board, Enum.NormalId.Front, aim)
	m.Parent = S.boardsF
	U.add(S.obs, { o = c.obb, y0 = c.y0, y1 = c.y1, kind = "solid", name = "Look4Board" })
	return m
end

-- Pole boards ---------------------------------------------------------------------------------------------------

-- One spot beside line L, t studs along it on `side`. The front face looks back along the road at the traffic
-- coming up this side (right-hand traffic); the back face serves the other direction.
function B.poleCheck(L, t, side, rng)
	local off = L.w / 2 + rng:NextNumber(K.PoleOff[1], K.PoleOff[2])
	local H = rng:NextNumber(K.PoleHeight[1], K.PoleHeight[2])
	local turn = math.rad(rng:NextNumber(-K.PoleYaw, K.PoleYaw))
	local p = U.at(L, t, side * off)
	local area = U.area(p.X, p.Z)
	if not K.BoardAreas[area or ""] then
		return nil
	end
	if (area == "Glades" and L.kind ~= "highway") or (L.kind == "avenue" and not K.Urban[area]) then
		return nil
	end
	if U.nearJunction(L, t, K.PoleJunction) then
		return nil
	end
	local hit = U.ground(p.X, p.Z)
	if not hit or not hit.Instance:IsDescendantOf(S.ground) or hit.Position.Y < K.LandMin then
		return nil
	end
	local gy = hit.Position.Y
	local fx, fz = -L.dx * side, -L.dz * side
	local cs, sn = math.cos(turn), math.sin(turn)
	fx, fz = fx * cs - fz * sn, fx * sn + fz * cs
	local base = Vector3.new(p.X, gy, p.Z)
	local G = CFrame.lookAt(base, base + Vector3.new(fx, 0, fz))
	local board = U.obbFrame(G, K.Board.X / 2 + 0.6, 3.9) -- the board with its catwalks and lamps
	local pole = U.obb(p.X, p.Z, 1, 0, 1.8, 1.8)
	if U.lotHit("board", board) or U.lotHit("board", pole) then
		return nil
	end
	-- Beside the road, never over one (another road under the board included).
	if #Workspace:GetPartBoundsInBox(G, Vector3.new(K.Board.X + 1.2, 6, 7.8), S.overRoads) > 0 then
		return nil
	end
	local top = gy + H + K.Board.Y + 0.6
	if U.find(S.obs, pole, gy + 0.3, gy + H, B.blocks)
		or U.find(S.obs, U.obb(p.X, p.Z, 1, 0, 2, 2), gy - 1, gy + 0.9, function(item)
			-- (a driveway is street furniture, kind "furn", but lies flat: 0.14 high, under the check above)
			return (item.kind == "flat" and not K.FlatOk[item.name]) or item.name == "Driveway"
		end)
		or U.find(S.obs, board, gy + H - 1.5, top, B.blocks) then
		return nil
	end
	if #Workspace:GetPartBoundsInBox(G * CFrame.new(0, H + K.Board.Y / 2 - 0.5, 0), Vector3.new(K.Board.X + 1.2, K.Board.Y + 3, 7.8), S.overAny) > 0
		or #Workspace:GetPartBoundsInBox(CFrame.new(p.X, gy + H / 2 + 0.6, p.Z), Vector3.new(3, H - 1, 3), S.overAny) > 0 then
		return nil
	end
	return {
		G = G, H = H, gy = gy, area = area, obb = board, pole = pole, y0 = gy + H - 1.5, y1 = top,
		pos = (G * CFrame.new(0, H + K.Board.Y / 2, 0)).Position,
	}
end

function B.poleSpots(rng)
	local list = {}
	for _, L in ipairs(S.lines) do
		if L.usable and (L.kind == "highway" or L.kind == "causeway" or L.kind == "avenue") and L.t1 - L.t0 > 80 then
			for _, side in ipairs({ -1, 1 }) do
				local t = L.t0 + 40 + rng:NextNumber(0, 30)
				while t < L.t1 - 40 do
					local c = B.poleCheck(L, t, side, rng)
					if c then
						table.insert(list, c)
					end
					t += K.PoleStep + rng:NextNumber(-10, 10)
				end
			end
		end
	end
	return list
end

-- A concrete footing, one thick pole, a bracket under the board, the board in its frame, a catwalk and two
-- lamps on each side.
function B.buildPole(c, lit)
	local m = Instance.new("Model")
	m.Name = "PoleBillboard"
	local G, H = c.G, c.H
	local cy = H + K.Board.Y / 2
	U.part(m, "BoardFooting", Vector3.new(3.6, 1.2, 3.6), G * CFrame.new(0, 0.45, 0), K.Col.Concrete, Enum.Material.Concrete, true)
	U.cyl(m, "BoardPole", G.Position, H - 0.8, 2.2, K.Col.Steel, Enum.Material.Metal, true)
	-- (0.9 deep: the catwalks start 0.45 either side of the board, and their tops are level with the bracket's)
	U.part(m, "BoardBracket", Vector3.new(K.Board.X - 2, 0.8, 0.9), G * CFrame.new(0, H - 0.4, 0), K.Col.Steel, Enum.Material.Metal, true)
	local board = U.part(m, "AdBoard", K.Board, G * CFrame.new(0, cy, 0), K.Col.Board, Enum.Material.SmoothPlastic, true)
	board.CastShadow = true
	U.part(m, "AdFrame", Vector3.new(K.Board.X + 0.8, K.Board.Y + 0.8, 0.6), G * CFrame.new(0, cy, 0), K.Col.Steel, Enum.Material.Metal, false)
	local aim = (G * CFrame.new(0, cy, 0)).Position
	for _, z in ipairs({ -1, 1 }) do
		U.part(m, "Catwalk", Vector3.new(K.Board.X, 0.3, 2.2), G * CFrame.new(0, H - 0.15, 1.55 * z), K.Col.Grate, Enum.Material.DiamondPlate, true)
		for _, x in ipairs({ -6, 6 }) do
			U.part(m, "LampArm", Vector3.new(0.3, 0.3, 0.7), G * CFrame.new(x, H - 0.3, 2.95 * z), K.Col.Steel, Enum.Material.Metal, false)
			B.lamp(m, (G * CFrame.new(x, H - 0.3, 3.4 * z)).Position, aim, lit)
		end
	end
	B.face(board, Enum.NormalId.Front, aim)
	B.face(board, Enum.NormalId.Back, aim)
	m.Parent = S.boardsF
	U.add(S.obs, { o = c.pole, y0 = c.gy, y1 = c.gy + c.H, kind = "solid", name = "Look4Board" })
	U.add(S.obs, { o = c.obb, y0 = c.y0, y1 = c.y1, kind = "solid", name = "Look4Board" })
	return m
end

-- Images: each face takes the least-used image with no twin within SameImageGap; when none is free (too few
-- images), the one whose nearest twin is furthest away. Returns how many faces had to break the rule.
function B.assign(images, rng)
	local spots, used = {}, {}
	local clash = 0
	for _, f in ipairs(S.faces) do
		local best, bestScore = images[1], -math.huge
		for _, id in ipairs(images) do
			local near = math.huge
			for _, q in ipairs(spots[id] or {}) do
				near = math.min(near, U.dist(q[1], q[2], f.x, f.z))
			end
			local score
			if near >= K.SameImageGap then
				score = 1e9 - (used[id] or 0) * 1e6 + rng:NextNumber()
			else
				score = near + rng:NextNumber()
			end
			if score > bestScore then
				best, bestScore = id, score
			end
		end
		if bestScore < 1e8 then
			clash += 1
		end
		f.decal.Texture = best
		used[best] = (used[best] or 0) + 1
		spots[best] = spots[best] or {}
		table.insert(spots[best], { f.x, f.z })
	end
	return clash
end

function B.run(opts, C, seed)
	local images = U.idList(opts.Billboards)
	if #images == 0 then
		return "billboards: skipped (opts.Billboards has no image ids)"
	end
	local rng = Random.new(seed)
	local lit = C.BoardLights ~= false
	local pick = Apartments and Apartments.Pick or {}
	S.roofMax = math.min(K.RoofMax, (pick.MinTop or 90) - 0.5)
	-- (a rooftop board is 12 parts, a pole board 15: both kinds together stay under Counts.Parts)
	local budget = tonumber(C.Parts) or 3000
	local roofs = B.pick(B.roofSpots(rng), math.min(math.floor(C.RoofBillboards or 0), math.floor(budget / 12)), rng, function(c)
		return B.spaced(c, K.RoofGap, nil)
	end)
	for _, c in ipairs(roofs) do
		B.buildRoof(c, lit)
	end
	local glades = 0
	local poles = B.pick(B.poleSpots(rng), math.min(math.floor(C.PoleBillboards or 0), math.floor(math.max(0, budget - S.parts) / 15)), rng, function(c)
		if c.area == "Glades" and glades >= K.GladesPoles then
			return false
		end
		if not B.spaced(c, K.BoardGap, K.PoleGap) then
			return false
		end
		if c.area == "Glades" then
			glades += 1
		end
		return true
	end)
	for _, c in ipairs(poles) do
		B.buildPole(c, lit)
	end
	local clash = B.assign(images, rng)
	local per, names = {}, {}
	for _, list in ipairs({ roofs, poles }) do
		for _, c in ipairs(list) do
			local a = c.area or "?"
			if not per[a] then
				per[a] = 0
				table.insert(names, a)
			end
			per[a] += 1
		end
	end
	table.sort(names)
	local spread = {}
	for _, a in ipairs(names) do
		table.insert(spread, a .. " " .. per[a])
	end
	return string.format("billboards: %d rooftop + %d pole (%d ad faces from %d images%s; %s)", #roofs, #poles, #S.faces, #images,
		clash > 0 and string.format(", %d faces could not keep %d studs from a twin", clash, K.SameImageGap) or "",
		table.concat(spread, ", "))
end

-- Road decals ---------------------------------------------------------------------------------------------------

local D = {}

function D.folder(name)
	local f = S.decalSub[name]
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = S.decalsF
		S.decalSub[name] = f
	end
	return f
end

function D.total()
	local n = 0
	for _, v in pairs(S.decalCount) do
		n += v
	end
	return n
end

-- The asphalt top under the whole decal (its corners and middle), or nil when any of it is off a paved road.
function D.onRoad(o)
	local top = -math.huge
	local pts = U.corners(o)
	table.insert(pts, Vector3.new(o.x, 0, o.z))
	for _, c in ipairs(pts) do
		local hit = Workspace:Raycast(Vector3.new(c.X, 6, c.Z), Vector3.new(0, -12, 0), S.rayRoads)
		if not hit or not U.isPaveRoad(hit.Instance) or hit.Normal.Y < 0.99 then
			return nil
		end
		top = math.max(top, hit.Position.Y)
	end
	return top
end

function D.blocks(item)
	if item.kind == "paint" then
		return K.PaintMargin
	end
	if item.kind == "crown" then
		return false
	end
	return 0.3
end

-- Nothing lying on the road there (markings, pads, ramps, parked cars), no gameplay pad, no other decal's
-- middle (decals at different heights may only overlap at their edges), and no decal at all at the same
-- height (two coplanar decals flicker where they overlap).
function D.free(o, top, skipLots, kind)
	if S.decals >= S.decalCap then
		return false -- the part budget (Counts.Parts) is spent
	end
	if U.find(S.obs, o, top - 0.6, top + 2.5, D.blocks, K.PaintMargin) then
		return false
	end
	if not skipLots and U.lotHit("decal", o) then
		return false
	end
	if U.find(S.dec, U.obb(o.x, o.z, o.ux, o.uz, o.hx * 0.7, o.hz * 0.7), -math.huge, math.huge) then
		return false
	end
	local level = S.decLevel[K.DecalLift[kind] or 0]
	if level and U.find(level, o, -math.huge, math.huge) then
		return false
	end
	return true
end

-- A decal on a thin invisible carrier: box o (from U.yawObb with this yaw), carrier bottom 0.02 above `top`.
-- `tile` (optional, same middle and yaw): a carrier bigger than what shows, for an image with a transparent
-- border (the drain); o is then only the part that shows, which is what the checks and the grids use.
function D.place(kind, o, yaw, top, id, tile)
	local c = tile or o
	local p = Instance.new("Part")
	p.Name = kind
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(c.hx * 2, K.CarrierThick, c.hz * 2)
	p.CFrame = CFrame.new(c.x, top + K.CarrierGap + K.CarrierThick / 2 + (K.DecalLift[kind] or 0), c.z) * CFrame.Angles(0, yaw, 0)
	local d = Instance.new("Decal")
	d.Name = "Wear"
	d.Face = Enum.NormalId.Top
	d.Texture = id
	d.Color3 = Color3.new(1, 1, 1)
	d.Transparency = 0
	d.Parent = p
	p.Parent = D.folder((kind == "DriftSkid") and "Skid" or kind)
	S.parts += 1
	S.decals += 1
	S.decalCount[kind] = (S.decalCount[kind] or 0) + 1
	U.add(S.dec, { o = U.obb(o.x, o.z, o.ux, o.uz, o.hx * 0.7, o.hz * 0.7), y0 = -math.huge, y1 = math.huge, kind = kind })
	local lift = K.DecalLift[kind] or 0
	S.decLevel[lift] = S.decLevel[lift] or U.grid()
	U.add(S.decLevel[lift], { o = o, y0 = -math.huge, y1 = math.huge, kind = kind })
end

function D.try(kind, o, yaw, ids, rng, tile)
	local top = D.onRoad(o)
	if top and D.free(o, top, false, kind) then
		D.place(kind, o, yaw, top, ids[rng:NextInteger(1, #ids)], tile)
		return true
	end
	return false
end

-- Manholes: lane centres of city streets and avenues, every `every` studs, lanes taking turns.
function D.manholes(rng, ids, every)
	local lo, hi = U.range(every, 120, 200)
	local half = K.ManholeSize / 2
	for _, L in ipairs(S.lines) do
		if L.usable and L.mat == Enum.Material.Asphalt and (L.kind == "street" or L.kind == "avenue") then
			local lanes = U.lanes(L)
			local k = 1
			local t = L.t0 + rng:NextNumber(20, 90)
			while t < L.t1 - 10 do
				for _, dt in ipairs({ 0, 6, -6, 12 }) do
					local tt = t + dt
					local p = U.at(L, tt, lanes[k])
					if K.Urban[U.area(p.X, p.Z) or ""] and not U.nearJunction(L, tt, half + 2) then
						local yaw = rng:NextNumber(0, math.pi * 2)
						if D.try("Manhole", U.yawObb(p.X, p.Z, yaw, half, half), yaw, ids, rng) then
							k = k % #lanes + 1
							break
						end
					end
				end
				t += rng:NextNumber(lo, hi)
			end
		end
	end
end

-- Is there one of Look3's kerbs beside line L at t on `side`?
function D.kerbAt(L, t, side)
	if not S.paint then
		return false
	end
	local p = U.at(L, t, side * (L.w / 2 + 1.5))
	local hit = Workspace:Raycast(Vector3.new(p.X, 4, p.Z), Vector3.new(0, -8, 0), S.rayPaint)
	return hit ~= nil and hit.Instance.Name == "Kerb"
end

-- Drains: at the kerb edge of the city's busier streets, every `every` studs, the side alternating.
function D.drains(rng, ids, every)
	local lo, hi = U.range(every, 80, 120)
	local along, across = K.DrainSize[1] / 2, K.DrainSize[2] / 2
	local tile = K.DrainTile / 2
	for _, L in ipairs(S.lines) do
		if L.usable and L.mat == Enum.Material.Asphalt and L.kind ~= "causeway" then
			local side = (rng:NextNumber() < 0.5) and -1 or 1
			local yaw = U.roadYaw(L) + math.pi / 2 -- the carrier's X (the image's width) along the kerb
			local t = L.t0 + rng:NextNumber(10, 60)
			while t < L.t1 - 6 do
				for _, dt in ipairs({ 0, 5, -5 }) do
					local tt = t + dt
					-- (the grate 0.2 from the kerb; the square tile's transparent rim tucks under the kerb)
					local p = U.at(L, tt, side * (L.w / 2 - across - 0.2))
					if K.DrainAreas[U.area(p.X, p.Z) or ""] and not U.nearJunction(L, tt, along + 3) and D.kerbAt(L, tt, side)
						and D.try("Drain", U.yawObb(p.X, p.Z, yaw, along, across), yaw, ids, rng, U.yawObb(p.X, p.Z, yaw, tile, tile)) then
						break
					end
				end
				side = -side
				t += rng:NextNumber(lo, hi)
			end
		end
	end
end

-- The paved lines, weighted by length, for the wear decals.
function D.prepare()
	S.wearLines, S.wearTotal = {}, 0
	for _, L in ipairs(S.lines) do
		if L.usable and (L.mat == Enum.Material.Asphalt or L.name == "Causeway") and L.t1 - L.t0 > 20 then
			S.wearTotal += L.t1 - L.t0
			table.insert(S.wearLines, { L = L, acc = S.wearTotal })
		end
	end
end

function D.sample(rng)
	local list = S.wearLines
	if #list == 0 then
		return nil, nil
	end
	local r = rng:NextNumber(0, S.wearTotal)
	local lo, hi = 1, #list
	while lo < hi do
		local mid = (lo + hi) // 2
		if list[mid].acc < r then
			lo = mid + 1
		else
			hi = mid
		end
	end
	local L = list[lo].L
	return L, L.t0 + rng:NextNumber(0, L.t1 - L.t0)
end

-- Where on the approach to one of L's crossings (cars wait there), or nil.
function D.approach(L, rng, near, far)
	if #L.cross == 0 then
		return nil
	end
	local c = L.cross[rng:NextInteger(1, #L.cross)]
	local dir = (rng:NextNumber() < 0.5) and -1 or 1
	return c.t + dir * (c.w / 2 + rng:NextNumber(near, far))
end

-- Size, turn and place of one wear decal on line L near t: { t, lat, sx, sz, yaw } or nil.
function D.shape(kind, L, t, rng)
	local half = L.w / 2
	local lanes = U.lanes(L)
	local roadYaw = U.roadYaw(L)
	local s = { t = t }
	local size = K.DecalSize[kind]
	if kind == "Crack" then
		s.sx = rng:NextNumber(size[1], size[2])
		s.sz = s.sx * rng:NextNumber(0.7, 1)
		s.yaw = rng:NextNumber(0, math.pi * 2)
		local room = half - math.max(s.sx, s.sz) / 2 - 0.3
		if room <= 0 then
			return nil
		end
		s.lat = rng:NextNumber(-room, room)
	elseif kind == "Oil" then
		s.sx = rng:NextNumber(size[1], size[2])
		s.sz = s.sx * rng:NextNumber(0.75, 1)
		s.yaw = rng:NextNumber(0, math.pi * 2)
		s.lat = lanes[rng:NextInteger(1, #lanes)] + rng:NextNumber(-1.2, 1.2)
		if rng:NextNumber() < K.OilAtJunction then
			s.t = D.approach(L, rng, 5, 45) or t
		end
	elseif kind == "Patch" then
		s.sx = rng:NextNumber(size[1], size[2])
		s.sz = s.sx * rng:NextNumber(1, 1.6)
		local quarter = (rng:NextNumber() < 0.5) and 0 or math.pi / 2
		s.yaw = roadYaw + quarter + math.rad(rng:NextNumber(-4, 4))
		local room = half - math.max(s.sx, s.sz) / 2 - 0.3
		if room <= 0 then
			return nil
		end
		s.lat = rng:NextNumber(-room, room)
	elseif kind == "Skid" then
		s.sz = rng:NextNumber(size[1], size[2]) -- along the lane
		s.sx = rng:NextNumber(K.SkidWide[1], K.SkidWide[2])
		s.yaw = roadYaw + math.rad(rng:NextNumber(-14, 14))
		s.lat = lanes[rng:NextInteger(1, #lanes)] + rng:NextNumber(-1, 1)
		if math.abs(s.lat) + s.sx / 2 > half - 0.3 then
			return nil
		end
		if rng:NextNumber() < K.SkidAtJunction then
			s.t = D.approach(L, rng, 8, 60) or t
		end
	else
		return nil
	end
	if s.t < L.t0 or s.t > L.t1 then
		return nil
	end
	return s
end

function D.wear(kind, n, ids, rng)
	local placed, tries = 0, 0
	while placed < n and tries < n * 12 do
		tries += 1
		local L, t = D.sample(rng)
		if not L then
			return placed
		end
		local s = D.shape(kind, L, t, rng)
		if s then
			local p = U.at(L, s.t, s.lat)
			local weight = K.Wear[U.area(p.X, p.Z) or ""] or K.WearDefault
			if rng:NextNumber() < weight and D.try(kind, U.yawObb(p.X, p.Z, s.yaw, s.sx / 2, s.sz / 2), s.yaw, ids, rng) then
				placed += 1
			end
		end
	end
	return placed
end

-- Skid marks on the Lighthouse Key drift pad (Workspace.Activities.DriftZone), clear of its edge lines.
function D.drift(n, ids, rng)
	local acts = Workspace:FindFirstChild("Activities")
	local pad = acts and acts:FindFirstChild("DriftZone")
	if not pad or not pad:IsA("BasePart") or n <= 0 then
		return 0
	end
	local top = pad.Position.Y + pad.Size.Y / 2
	local placed, tries = 0, 0
	while placed < n and tries < n * 8 do
		tries += 1
		local p = pad.CFrame * Vector3.new(rng:NextNumber(-pad.Size.X / 2 + 14, pad.Size.X / 2 - 14), 0,
			rng:NextNumber(-pad.Size.Z / 2 + 14, pad.Size.Z / 2 - 14))
		local yaw = rng:NextNumber(0, math.pi * 2)
		local o = U.yawObb(p.X, p.Z, yaw, rng:NextNumber(K.SkidWide[1], K.SkidWide[2]) / 2, rng:NextNumber(12, 24) / 2)
		if D.free(o, top, true, "DriftSkid") then
			D.place("DriftSkid", o, yaw, top, ids[rng:NextInteger(1, #ids)])
			placed += 1
		end
	end
	return placed
end

function D.run(opts, C, seed)
	local src = type(opts.Decals) == "table" and opts.Decals or {}
	local ids = {}
	local any = false
	for _, kind in ipairs(K.DecalTypes) do
		ids[kind] = U.idList(src[kind])
		if #ids[kind] > 0 then
			any = true
		end
	end
	if not any then
		return "road decals: skipped (opts.Decals has no image ids)"
	end
	local rng = Random.new(seed)
	D.prepare()
	-- Every decal is a carrier part: all of them together stay within MaxDecals and the parts left under Parts.
	S.decalCap = math.max(0, math.min(tonumber(C.MaxDecals) or 900, (tonumber(C.Parts) or 3000) - S.parts))
	if #ids.Manhole > 0 then
		D.manholes(rng, ids.Manhole, C.ManholeEvery)
	end
	if #ids.Drain > 0 then
		D.drains(rng, ids.Drain, C.DrainEvery)
	end
	-- The wear decals share what is left, each kind in proportion.
	local room = math.max(0, S.decalCap - D.total())
	local order = { "Patch", "Crack", "Oil", "Skid" }
	local want, sum = {}, 0
	for _, kind in ipairs(order) do
		want[kind] = (#ids[kind] > 0) and math.max(0, tonumber(C[kind]) or 0) or 0
		sum += want[kind]
	end
	local drift = (#ids.Skid > 0) and math.max(0, tonumber(C.DriftSkid) or 0) or 0
	sum += drift
	local scale = (sum > room and sum > 0) and room / sum or 1
	for _, kind in ipairs(order) do
		if want[kind] > 0 then
			D.wear(kind, math.floor(want[kind] * scale + 0.5), ids[kind], rng)
		end
	end
	if drift > 0 then
		D.drift(math.floor(drift * scale + 0.5), ids.Skid, rng)
	end
	local parts = {}
	for _, kind in ipairs({ "Manhole", "Drain", "Crack", "Oil", "Patch", "Skid", "DriftSkid" }) do
		local n = S.decalCount[kind] or 0
		local why = ""
		if kind ~= "DriftSkid" and #ids[kind] == 0 then
			why = " (no images)"
		end
		table.insert(parts, string.format("%s %d%s", string.lower(kind), n, why))
	end
	return string.format("road decals: %d (%s)", D.total(), table.concat(parts, ", "))
end

-- Tall palms ----------------------------------------------------------------------------------------------------

local P = {}

-- The template: its height, how many parts a palm costs, whether its own trunk can be the collider, the
-- turn its pivot has as it stands (kept when planting: an upright palm whose pivot is turned, such as a
-- cylinder trunk set as its PrimaryPart, stays upright), and how far its crown reaches out from the trunk.
function P.info(tpl)
	local cf, size
	if tpl:IsA("Model") then
		cf, size = tpl:GetBoundingBox()
	else
		cf, size = tpl.CFrame, tpl.Size
	end
	local h = U.extentY(cf, size) * 2
	if h < 1 then
		return nil
	end
	local scale = (K.PalmHeight[1] + K.PalmHeight[2]) / 2 / h
	local pivot = tpl:GetPivot()
	-- The crown's reach on the map from the pivot (the trunk), at the mean planted size.
	local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
	local ex = math.abs(r.X) * size.X / 2 + math.abs(u.X) * size.Y / 2 + math.abs(l.X) * size.Z / 2
	local ez = math.abs(r.Z) * size.X / 2 + math.abs(u.Z) * size.Y / 2 + math.abs(l.Z) * size.Z / 2
	local reach = math.max(math.abs(cf.X - pivot.X) + ex, math.abs(cf.Z - pivot.Z) + ez) * scale
	local list = tpl:GetDescendants()
	if tpl:IsA("BasePart") then
		table.insert(list, tpl)
	end
	local parts, trunks, thin = 0, 0, true
	for _, d in ipairs(list) do
		if d:IsA("BasePart") then
			parts += 1
			if tpl:IsA("Model") and string.find(string.lower(d.Name), "trunk") then
				trunks += 1
				-- a trunk's thickness: the middle of its three sizes (a cylinder lies along X), at the tallest size
				local dims = { d.Size.X, d.Size.Y, d.Size.Z }
				table.sort(dims)
				if dims[2] * K.PalmHeight[2] / h > K.TrunkMaxWidth then
					thin = false
				end
			end
		end
	end
	local useTrunk = trunks > 0 and thin
	return {
		inst = tpl, height = h, parts = parts + ((useTrunk and 0) or 1), useTrunk = useTrunk,
		rot = pivot.Rotation, crown = math.max(K.CrownHalf, reach * K.CrownFit),
	}
end

-- Which palm row a road line is, or nil.
function P.family(L)
	if L.name == "Highway1" then
		if math.abs(L.dx) < 0.02 then
			local mid = U.at(L, (L.t0 + L.t1) / 2, 0)
			if math.abs(mid.X - S.beachX) < 10 then
				return "BeachRoad" -- the highway's straight run along Flamingo Beach
			end
		end
		return nil
	end
	if K.PalmRoads[L.name] then
		return L.name
	end
	return nil
end

-- Which block of line L a spot is on (counted between its crossings).
function P.segment(L, t)
	local n = 0
	for _, c in ipairs(L.cross) do
		if c.t < t then
			n += 1
		end
	end
	return n
end

function P.nearFurniture(item)
	return item.kind == "furn" or (item.kind == "paint" and item.name == "Crosswalk")
end

function P.trunkSolid(item)
	return item.kind == "solid" or item.kind == "bld" or item.kind == "furn"
end

function P.crownSolid(item)
	return item.kind == "solid" or item.kind == "bld" or item.kind == "furn" or item.kind == "crown"
end

function P.flatBlocks(item)
	return item.kind == "flat" and not K.FlatOk[item.name]
end

-- One palm spot on the sidewalk of line L at t on `side`: { x, y, z } or nil. crownHalf = how far the
-- template's crown reaches out from its trunk (P.info): nothing solid in that square at crown height.
function P.test(L, t, side, crownHalf)
	local p = U.at(L, t, side * (L.w / 2 + K.PalmIn))
	if not K.PalmAreas[U.area(p.X, p.Z) or ""] then
		return nil
	end
	local trunk = U.obb(p.X, p.Z, L.nx, L.nz, K.PalmTrunk, K.PalmTrunk)
	if U.lotHit("palm", trunk) then
		return nil
	end
	-- On a kerb or the ground (not a road), over dry land.
	local hit = U.ground(p.X, p.Z)
	if not hit or not (hit.Instance.Name == "Kerb" or hit.Instance:IsDescendantOf(S.ground)) then
		return nil
	end
	local land = Workspace:Raycast(Vector3.new(p.X, 40, p.Z), Vector3.new(0, -80, 0), S.rayLand)
	if not land or land.Position.Y < K.LandMin then
		return nil
	end
	local gy = hit.Position.Y
	-- No crossing road within PalmJunction studs along this kerb.
	local frame = CFrame.lookAt(Vector3.new(p.X, gy + 1, p.Z), Vector3.new(p.X + L.dx, gy + 1, p.Z + L.dz))
	for _, r in ipairs(Workspace:GetPartBoundsInBox(frame, Vector3.new(K.PalmTrunk * 2 + 2, 4, K.PalmJunction * 2), S.overRoads)) do
		local rx, rz = U.unit2(r.CFrame.LookVector.X, r.CFrame.LookVector.Z)
		if math.abs(L.dx * rz - L.dz * rx) > 0.17 then
			return nil
		end
	end
	if U.find(S.obs, U.grow(trunk, K.PalmClear), -math.huge, math.huge, P.nearFurniture)
		or U.find(S.obs, trunk, gy + 0.5, gy + K.PalmBox, P.trunkSolid)
		or U.find(S.obs, trunk, gy - 1, gy + 0.6, P.flatBlocks) then
		return nil
	end
	if #Workspace:GetPartBoundsInBox(CFrame.new(p.X, gy + 0.5 + K.PalmBox / 2, p.Z), Vector3.new(K.PalmTrunk * 2, K.PalmBox, K.PalmTrunk * 2), S.overAny) > 0 then
		return nil
	end
	local half = math.max(K.CrownHalf, crownHalf or 0)
	local crown = U.obb(p.X, p.Z, L.nx, L.nz, half, half)
	if U.find(S.obs, crown, gy + K.CrownY[1], gy + K.CrownY[2], P.crownSolid) then
		return nil -- (fronds through a facade, a billboard or a sign)
	end
	return { x = p.X, y = gy, z = p.Z }
end

function P.spots(rng, crownHalf)
	local list = {}
	for li, L in ipairs(S.lines) do
		local family = L.usable and P.family(L)
		if family then
			for _, side in ipairs({ -1, 1 }) do
				local t = L.t0 + rng:NextNumber(6, 22)
				while t < L.t1 - 4 do
					local spot = P.test(L, t, side, crownHalf)
					if spot then
						spot.family = family
						spot.block = li .. ":" .. P.segment(L, t)
						table.insert(list, spot)
						t += rng:NextNumber(K.PalmStep[1], K.PalmStep[2])
					else
						t += K.PalmSlide
					end
				end
			end
		end
	end
	return list
end

-- At most `cap` spots: whole blocks (both sides of a road between two crossings), each road keeping its share.
function P.choose(cands, cap, rng)
	if #cands <= cap then
		return cands
	end
	local blocks, order, fam = {}, {}, {}
	for _, c in ipairs(cands) do
		local b = blocks[c.block]
		if not b then
			b = { family = c.family, list = {} }
			blocks[c.block] = b
			table.insert(order, b)
		end
		table.insert(b.list, c)
		fam[c.family] = (fam[c.family] or 0) + 1
	end
	U.shuffle(order, rng)
	local quota = {}
	for f, n in pairs(fam) do
		quota[f] = math.floor(cap * n / #cands)
	end
	local chosen, used = {}, {}
	local taken = 0
	local function take(b)
		used[b] = true
		taken += #b.list
		for _, c in ipairs(b.list) do
			table.insert(chosen, c)
		end
	end
	for _, b in ipairs(order) do
		if quota[b.family] >= #b.list then
			quota[b.family] -= #b.list
			take(b)
		end
	end
	for _, b in ipairs(order) do
		if not used[b] and taken + #b.list <= cap then
			take(b)
		end
	end
	return chosen
end

-- One palm: the template scaled to 38..46 studs, turned at random about the upright, its foot on the spot.
-- (Its pivot keeps the turn it has in the template: PivotTo with a bare yaw would lay a palm on its side
-- whose pivot is turned, e.g. a Model whose PrimaryPart is a cylinder trunk, or a MeshPart stood up by
-- its CFrame.)
function P.plant(info, c, rng)
	local height = rng:NextNumber(K.PalmHeight[1], K.PalmHeight[2])
	local spin = CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * info.rot
	local scale = height / info.height
	local clone = info.inst:Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- a template never brings scripts along
		end
	end
	local bottom
	if clone:IsA("Model") then
		clone:ScaleTo(clone:GetScale() * scale)
		clone:PivotTo(spin)
		local cf, size = clone:GetBoundingBox()
		bottom = cf.Y - U.extentY(cf, size)
	else
		local po = clone.PivotOffset
		clone.Size = clone.Size * scale
		clone.PivotOffset = CFrame.new(po.Position * scale) * po.Rotation
		clone:PivotTo(spin)
		bottom = clone.Position.Y - U.extentY(clone.CFrame, clone.Size)
	end
	clone:PivotTo(CFrame.new(c.x, c.y - bottom - K.PalmSink, c.z) * spin)
	local list = clone:GetDescendants()
	if clone:IsA("BasePart") then
		table.insert(list, clone)
	end
	for _, d in ipairs(list) do
		if d:IsA("BasePart") then
			local solid = info.useTrunk and string.find(string.lower(d.Name), "trunk") ~= nil
			d.Anchored = true
			d.CastShadow = true
			d.CanTouch = false
			d.CanCollide = solid
			d.CanQuery = solid
			S.parts += 1
		end
	end
	local holder = Instance.new("Model")
	holder.Name = "TallPalm"
	clone.Parent = holder
	if not info.useTrunk then
		local col = U.cyl(holder, "TrunkCollider", Vector3.new(c.x, c.y, c.z), K.Collider.Height, K.Collider.Width, K.Col.Bark, Enum.Material.Wood, true)
		col.Transparency = 1
	end
	holder.Parent = S.palmsF
	return holder
end

function P.run(opts, C, seed)
	local tpl = opts.PalmTemplate
	if typeof(tpl) ~= "Instance" or not (tpl:IsA("Model") or tpl:IsA("BasePart")) then
		return "tall palms: skipped (opts.PalmTemplate is not a Model or MeshPart)"
	end
	local info = P.info(tpl)
	if not info then
		return "tall palms: skipped (PalmTemplate has no size)"
	end
	local rng = Random.new(seed)
	local cands = P.spots(rng, info.crown)
	local room = math.floor(((tonumber(C.Parts) or 3000) - S.parts) / math.max(1, info.parts))
	local cap = math.max(0, math.min(math.floor(tonumber(C.TallPalms) or 0), room))
	local chosen = P.choose(cands, cap, rng)
	local plantRng = Random.new(seed + 1)
	local planted, failed = 0, 0
	local firstError = nil
	local fams = {}
	for _, c in ipairs(chosen) do
		local ok, err = pcall(P.plant, info, c, plantRng)
		if ok then
			planted += 1
			fams[c.family] = (fams[c.family] or 0) + 1
		else
			failed += 1
			firstError = firstError or tostring(err)
		end
	end
	local names = {}
	for f in pairs(fams) do
		table.insert(names, f)
	end
	table.sort(names)
	local spread = {}
	for _, f in ipairs(names) do
		table.insert(spread, f .. " " .. fams[f])
	end
	local note = ""
	if failed > 0 then
		note = string.format("; %d failed: %s", failed, string.sub(firstError, 1, 120))
	end
	return string.format("tall palms: %d planted of %d free spots (cap %d, %d parts each, %s collider, crown kept %.1f studs clear; %s)%s",
		planted, #cands, cap, info.parts, info.useTrunk and "template trunk" or "thin", info.crown, table.concat(spread, ", "), note)
end

-- API -------------------------------------------------------------------------------------------------------

-- Takes out everything Look4 made (Workspace.City.Art.Look4: every folder of that name, should an undo or
-- a pasted copy have left two; one left behind would be indexed as obstacles and doubled up).
function Look4.Clear()
	local city = Workspace:FindFirstChild("City")
	local art = city and city:FindFirstChild("Art")
	local n, folders = 0, 0
	for _, old in ipairs(art and art:GetChildren() or {}) do
		if old.Name == K.Folder then
			folders += 1
			for _, d in ipairs(old:GetDescendants()) do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			old:Destroy()
		end
	end
	if folders == 0 then
		return "Look4: nothing to clear"
	end
	return string.format("Look4: cleared %d parts", n)
end

-- opts: { Billboards = { ids }, Decals = { Crack, Oil, Patch, Manhole, Drain, Skid = { ids } },
--         PalmTemplate = Model | MeshPart, Counts = { overrides of K.Counts }, Seed = number }
function Look4.Run(opts)
	opts = type(opts) == "table" and opts or {}
	local city = Workspace:FindFirstChild("City")
	if not city or not city:FindFirstChild("Art") or not city:FindFirstChild("Roads") or not city:FindFirstChild("Ground") then
		return "Look4: Workspace.City needs Art, Roads and Ground (run CityGen, ArtGen, Restyle and Look3 first)"
	end
	local started = os.clock()
	Look4.Clear()
	local C = {}
	for k, v in pairs(K.Counts) do
		C[k] = v
	end
	if type(opts.Counts) == "table" then
		for k, v in pairs(opts.Counts) do
			C[k] = v
		end
	end
	local seed = math.floor(tonumber(opts.Seed) or K.Seed)
	local ready, info = xpcall(U.setup, debug.traceback, city, opts)
	if not ready then
		warn("[Look4] setup failed: " .. tostring(info))
		Look4.Clear()
		return "Look4: setup FAILED (see Output) " .. string.sub(tostring(info), 1, 200)
	end
	local lines = { info }
	local phases = { { "billboards", B.run, 0 }, { "road decals", D.run, 100 }, { "tall palms", P.run, 200 } }
	for _, phase in ipairs(phases) do
		local ok, msg = xpcall(phase[2], debug.traceback, opts, C, seed + phase[3])
		if ok then
			table.insert(lines, msg)
		else
			warn("[Look4] " .. phase[1] .. " failed: " .. tostring(msg))
			table.insert(lines, phase[1] .. ": FAILED (see Output) " .. string.sub(tostring(msg), 1, 160))
		end
	end
	table.insert(lines, string.format("%d new parts, %d lights, %.1f s", S.parts, S.lights, os.clock() - started))
	return "Look4: " .. table.concat(lines, "; ")
end

return Look4
