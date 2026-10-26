-- HouseBuilder (ModuleScript, ServerScriptService.Services.HouseBuilder)
-- Builds the homes for sale (Config.Housing) from plain parts for HousingService. Every home has its
-- own build, a style module ServerScriptService.Services.Houses.<Style> (home.Style), drawn with the
-- Kit below. The same module draws the home twice, in two modes:
--   * Lot (HouseBuilder.Lot, once at start-up, in Workspace.Homes): the house as the street sees it: a
--     closed shell (walls, roofs, balconies, glass, the garage door), the yard, pool, driveway and the
--     street sign. Dark tinted windows, some showing a warm lit room after dark. Nobody walks in: the
--     front door's prompt (HousingService) buys, tours or takes the owner inside.
--   * Inside (HouseBuilder.Inside, per player, far off the map in Workspace.HomeInteriors): the whole
--     house again with its rooms, stairs, furniture, the garage with one parking bay per GarageSlots
--     and the back yard, behind clear glass, inside a little neighbourhood (Backdrop) so the windows
--     look out on something. Opts.show = a tour's show copy (no wardrobe prompt, a FOR SALE stand and a
--     "Your cars park here" sign).
-- Lot space (Config.Housing): origin at the lot centre on the ground (y = 0), -Z toward the street,
-- +X to the right as you look at the street from the house. A lot is x -55..55, z -35..35; builds stay
-- inside x -60..60, z -40..40 (Look4 keeps x -62..62, z -100..42 clear; ApartmentService keeps 12 studs
-- off every part in Workspace.Homes).
--
-- Look 3.0 / 4.0 (HousingService's old rules, kept): real materials in believable colours, dark tinted
-- glass outside, neon only as thin strips and only after dark (tag "NightNeon", attribute NeonColor:
-- SkyClient lights it), lamps tagged "NightLamp" (LampColor), lights inside tagged parts start off.
-- Small details never collide, can't be queried and cast no shadow (DETAIL); big looks-only pieces cast
-- shadows (SHADE). Everything is anchored and CanTouch is off (seats keep it: you sit by touching).
--
-- Kit coordinates: every method takes lot-space numbers in the kit's frame; K:Sub(x, y, z, yaw) is a
-- child frame turned `yaw` degrees (furniture: its front is -Z, so yaw 0 faces the street, 180 the
-- back, 90 the -X side, -90 the +X side). Box corners are (x0, x1, y0, y1, z0, z1) like HousingService.
-- Furniture methods draw only Inside; K.inside / K.lot / K.show tell a style module which copy it draws.
--
-- What a build hands back (out): model, door (the front door part: HomeDoor prompt on the lot, the exit
-- with LeavePrompt inside), sign (lot: the street sign board), spawn (inside: CFrame for the root),
-- bays ({ cf, pad }), closet, garageTitle / signSub (the garage sign's labels), saleBoard / saleAt (a
-- show copy's FOR SALE stand), cars (Folder for the display cars), water ({ cf, size } world boxes of
-- Terrain water for the pools, inside only: HousingService fills and clears them), parts, lights.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local HouseBuilder = {}

HouseBuilder.STORY = 14 -- studs per floor
HouseBuilder.MAX_LIGHTS = { Lot = 10, Inside = 16 } -- PointLights per build (Shadows off); a style may set
-- K.stats.maxLights for its own build (the Mansion's windowless car collection needs a few more)

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
HouseBuilder.rgb = rgb

-- The Look 3.0 palette HousingService always used, plus a few shared materials' colours.
local P = {
	Dark = rgb(26, 28, 32), -- sign boards, screens
	White = rgb(236, 234, 228), -- painted trim: a real white
	WarmWhite = rgb(238, 232, 222),
	Gold = rgb(255, 214, 10), -- sign small print
	Brass = rgb(176, 140, 72),
	Warm = rgb(255, 214, 170), -- lamplight
	Glass = rgb(52, 62, 70), -- dark tinted glass (outside)
	ClearGlass = rgb(196, 214, 222), -- glass seen from inside
	RoomGlow = rgb(210, 156, 96), -- a lit room through a window after dark
	DarkMetal = rgb(44, 44, 48),
	Steel = rgb(120, 124, 130),
	TrimDay = rgb(58, 60, 66), -- an unlit neon tube by day (SkyClient's day colour)
	LampDay = rgb(226, 226, 220), -- an unlit lamp by day
	Walnut = rgb(92, 64, 44),
	Wood = rgb(110, 80, 56),
	Oak = rgb(190, 160, 120),
	Lawn = rgb(86, 124, 62),
	Hedge = rgb(62, 104, 58),
	Leaf = rgb(70, 112, 60),
	Concrete = rgb(178, 174, 166),
	Paving = rgb(198, 190, 176),
	Asphalt = rgb(62, 62, 66),
	Tile = rgb(176, 92, 62), -- clay roof tiles
	RailGlass = rgb(150, 170, 176),
	PoolTile = rgb(96, 168, 186),
	PoolWater = rgb(54, 150, 170),
	PoolLight = rgb(60, 200, 255),
	Sand = rgb(226, 208, 164),
	Sea = rgb(18, 120, 140),
	Fabric = rgb(122, 118, 112),
	Cream = rgb(230, 222, 204),
	Black = rgb(20, 20, 24),
}
HouseBuilder.P = P

local M = Enum.Material
HouseBuilder.M = M

local FONT = Enum.Font.Oswald -- names and headlines
local SMALL_FONT = Enum.Font.GothamBold -- small print

-- Property sets (applied as they are, like HousingService's).
local DETAIL = { CanCollide = false, CanQuery = false, CastShadow = false }
local SHADE = { CanCollide = false, CanQuery = false }
local GHOST = { CanCollide = true, CanQuery = false, Transparency = 1, CastShadow = false } -- invisible walls
HouseBuilder.DETAIL, HouseBuilder.SHADE, HouseBuilder.GHOST = DETAIL, SHADE, GHOST

-- "$1,200,000"
function HouseBuilder.Money(n)
	local s = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if s:sub(1, 1) == "," then
		s = s:sub(2)
	end
	return "$" .. s
end

-- Which windows show a lit room after dark: a fixed, irregular pattern (6 in every 11).
local function litAt(n)
	return (n * 7) % 11 < 6
end

local function merge(a, b)
	if not a then
		return b
	end
	if not b then
		return a
	end
	local t = table.clone(a)
	for k, v in pairs(b) do
		t[k] = v
	end
	return t
end
HouseBuilder.Merge = merge

local Kit = {}
Kit.__index = Kit

local function newKit(model, frame, mode, home, opts)
	local k = setmetatable({}, Kit)
	k.model = model
	k.parent = model
	k.cf = frame
	k.root = frame
	k.mode = mode
	k.inside = mode == "Inside"
	k.lot = mode == "Lot"
	k.show = opts and opts.show == true or false
	k.home = home
	k.stats = { parts = 0, lights = 0, windows = 0 }
	k.out = { bays = {}, water = {}, model = model }
	k.rng = Random.new(#home.Id * 7919 + (home.Price % 977))
	return k
end

-- A child frame at (x, y, z), turned `yaw` degrees about the upright (its -Z is the new front).
function Kit:Sub(x, y, z, yaw)
	local k = setmetatable(table.clone(self), Kit)
	k.cf = self.cf * CFrame.new(x, y or 0, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	return k
end

-- The same frame; new parts go into the Folder `name` of the model (made once).
function Kit:In(name)
	local k = setmetatable(table.clone(self), Kit)
	local f = self.model:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = self.model
	end
	k.parent = f
	return k
end

-- World CFrame of a point of this frame.
function Kit:World(x, y, z)
	return self.cf * CFrame.new(x, y, z)
end

-- Parts --------------------------------------------------------------------------------------------------

function Kit:Part(class, name, size, cf, color, material, props)
	local p = Instance.new(class)
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if class ~= "Seat" then
		p.CanTouch = false
	end
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = self.parent
	self.stats.parts += 1
	return p
end

-- One part between two corners of this frame (any order).
function Kit:Box(name, x0, x1, y0, y1, z0, z1, color, material, props)
	local size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	if size.X < 0.01 or size.Y < 0.01 or size.Z < 0.01 then
		return nil
	end
	local cf = self.cf * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	return self:Part("Part", name, size, cf, color, material, props)
end

-- Small looks-only box (DETAIL) and a big looks-only box that casts a shadow (SHADE).
function Kit:Deco(name, x0, x1, y0, y1, z0, z1, color, material, props)
	return self:Box(name, x0, x1, y0, y1, z0, z1, color, material, merge(DETAIL, props))
end
function Kit:Shade(name, x0, x1, y0, y1, z0, z1, color, material, props)
	return self:Box(name, x0, x1, y0, y1, z0, z1, color, material, merge(SHADE, props))
end

-- A wedge filling the same corners, its slope falling toward `low`: "-Z" (the default, toward the
-- street), "+Z", "-X" or "+X". (A WedgePart is tall at its +Z back and slopes down to its -Z front.)
function Kit:Wedge(name, x0, x1, y0, y1, z0, z1, color, material, low, props)
	local dx, dy, dz = math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)
	local cf = self.cf * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	local size = Vector3.new(dx, dy, dz)
	if low == "+Z" then
		cf = cf * CFrame.Angles(0, math.pi, 0)
	elseif low == "-X" then
		cf, size = cf * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(dz, dy, dx)
	elseif low == "+X" then
		cf, size = cf * CFrame.Angles(0, -math.pi / 2, 0), Vector3.new(dz, dy, dx)
	end
	return self:Part("WedgePart", name, size, cf, color, material, props)
end

-- An upright cylinder at (x, z) from y0 to y1, d across (Roblox cylinders run along X: turned upright).
function Kit:Cyl(name, x, z, y0, y1, d, color, material, props)
	local cf = self.cf * CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, math.rad(90))
	return self:Part("Part", name, Vector3.new(math.abs(y1 - y0), d, d), cf, color, material,
		merge({ Shape = Enum.PartType.Cylinder }, props))
end

-- A cylinder lying along X or Z (pipes, drums on their side, rolled towels): from a to b at (y, c).
function Kit:Pipe(name, alongX, a, b, y, c, d, color, material, props)
	local mid = (a + b) / 2
	local cf = alongX and self.cf * CFrame.new(mid, y, c) or self.cf * CFrame.new(c, y, mid) * CFrame.Angles(0, math.rad(90), 0)
	return self:Part("Part", name, Vector3.new(math.abs(b - a), d, d), cf, color, material,
		merge({ Shape = Enum.PartType.Cylinder }, props))
end

function Kit:Ball(name, x, y, z, d, color, material, props)
	return self:Part("Part", name, Vector3.new(d, d, d), self.cf * CFrame.new(x, y, z), color, material,
		merge({ Shape = Enum.PartType.Ball }, props))
end

-- A bar from point a to point b, th thick (handrails, rods, legs, wires): looks only unless props say.
function Kit:Bar(name, x0, y0, z0, x1, y1, z1, th, color, material, props)
	local a, b = Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
	local len = (b - a).Magnitude
	local mid = (a + b) / 2
	local cf
	if math.abs((b - a).Unit.Y) > 0.999 then
		cf = CFrame.new(mid) * CFrame.Angles(math.rad(90), 0, 0)
	else
		cf = CFrame.lookAt(mid, b)
	end
	return self:Part("Part", name, Vector3.new(th, th, len), self.cf * cf, color, material, merge(DETAIL, props))
end

-- Neon and lamps -------------------------------------------------------------------------------------------

-- Night-only neon (dark metal by day; SkyClient lights it in NeonColor after dark).
local function nightNeon(p, color)
	p.Material = M.Metal
	p.Color = P.TrimDay
	p:SetAttribute("NeonColor", color)
	CollectionService:AddTag(p, "NightNeon")
	return p
end
HouseBuilder.NightNeon = nightNeon

-- A lamp: a pale shade by day, lit in LampColor after dark.
local function nightLamp(p, color)
	p.Material = M.SmoothPlastic
	p.Color = P.LampDay
	p:SetAttribute("LampColor", color)
	CollectionService:AddTag(p, "NightLamp")
	return p
end
HouseBuilder.NightLamp = nightLamp

-- A thin strip that glows in `color` after dark (no collisions, no shadow).
function Kit:Neon(x0, x1, y0, y1, z0, z1, color)
	local p = self:Deco("Neon", x0, x1, y0, y1, z0, z1, P.TrimDay, M.Metal)
	return p and nightNeon(p, color)
end

-- A PointLight in `part` (no shadows), within the build's cap. In a NightNeon / NightLamp part it starts
-- off (SkyClient switches it); otherwise it is always on (rooms, garages).
function Kit:Light(part, color, range, brightness)
	if not part or self.stats.lights >= (self.stats.maxLights or HouseBuilder.MAX_LIGHTS[self.mode] or 10) then
		return nil
	end
	self.stats.lights += 1
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 1
	l.Shadows = false
	l.Enabled = not (CollectionService:HasTag(part, "NightNeon") or CollectionService:HasTag(part, "NightLamp"))
	l.Parent = part
	return l
end

-- A lamp shade or bulb (NightLamp) with a light that comes on after dark.
function Kit:Lamp(name, x0, x1, y0, y1, z0, z1, color, range, brightness)
	local p = self:Deco(name, x0, x1, y0, y1, z0, z1, P.LampDay, M.SmoothPlastic)
	if not p then
		return nil
	end
	nightLamp(p, color or P.Warm)
	if range then
		self:Light(p, color or P.Warm, range, brightness)
	end
	return p
end

-- An always-on ceiling light: a glowing disc (or strip) under the ceiling at height y.
function Kit:CeilingLight(x, z, y, d, range, brightness, color)
	local disc = self:Part("Part", "CeilingLight", Vector3.new(0.3, d, d), self.cf * CFrame.new(x, y - 0.2, z) * CFrame.Angles(0, 0, math.rad(90)),
		rgb(255, 246, 230), M.Neon, merge(DETAIL, { Shape = Enum.PartType.Cylinder }))
	self:Light(disc, color or P.Warm, range or 30, brightness or 0.6)
	return disc
end

-- Glass ----------------------------------------------------------------------------------------------------

-- A window pane (thin along the way it looks out: `out` = "-Z", "+Z", "-X" or "+X"). On the lot: dark
-- tinted glass, and six in every eleven a little clear with a room panel just inside (dark by day, warm
-- lamplight after dark), so the house reads lived-in at night. Inside: clear glass to look out through.
-- Never named "Window" inside Workspace.City (SkyClient lights those): these are in Workspace.Homes.
function Kit:Window(x0, x1, y0, y1, z0, z1, out, opts)
	opts = opts or {}
	if self.inside then
		return self:Box("Glass", x0, x1, y0, y1, z0, z1, opts.inside or P.ClearGlass, M.Glass,
			{ Transparency = opts.t or 0.62, Reflectance = 0.04, CastShadow = false, CanQuery = false })
	end
	self.stats.windows += 1
	local lit = opts.lit
	if lit == nil then
		lit = litAt(self.stats.windows)
	end
	local glass = self:Box("Window", x0, x1, y0, y1, z0, z1, opts.color or P.Glass, M.Glass,
		{ Reflectance = 0.1, Transparency = lit and 0.45 or 0 })
	if lit then
		-- The panel fills the back of the glass (the inside half), just inside its edges.
		local ax0, ax1 = math.min(x0, x1), math.max(x0, x1)
		local az0, az1 = math.min(z0, z1), math.max(z0, z1)
		local ay0, ay1 = math.min(y0, y1) + 0.06, math.max(y0, y1) - 0.06
		if out == "-Z" then
			ax0, ax1, az0 = ax0 + 0.06, ax1 - 0.06, az0 + (az1 - az0) * 0.5
		elseif out == "+Z" then
			ax0, ax1, az1 = ax0 + 0.06, ax1 - 0.06, az1 - (az1 - az0) * 0.5
		elseif out == "-X" then
			az0, az1, ax0 = az0 + 0.06, az1 - 0.06, ax0 + (ax1 - ax0) * 0.5
		else
			az0, az1, ax1 = az0 + 0.06, az1 - 0.06, ax1 - (ax1 - ax0) * 0.5
		end
		local panel = self:Deco("WindowLight", ax0, ax1, ay0, ay1, az0, az1, P.TrimDay, M.Metal)
		if panel then
			nightNeon(panel, opts.glow or P.RoomGlow)
		end
	end
	return glass
end

-- Walls ----------------------------------------------------------------------------------------------------

-- A straight wall along X at depth z (WallX) or along Z at x (WallZ), centred on that line, `th` thick,
-- running a..b, from y0 to y1. holes = list of { a, b, lo, hi, kind } in the same coordinates as the run:
--   "win"  a window (Kit:Window) with a sill outside (o.sill colour, when given) and o.bars mullions
--   "pane" a glass door or glass wall (Kit:Window, no sill)
--   "door" an open doorway, "none" a hole left for something else (a door part, a garage door)
-- o.out = the outside: "-Z" / "+Z" for WallX, "-X" / "+X" for WallZ. The solid part is cut into as few
-- boxes as the holes allow (bands at every hole's top and bottom, stacked when they match).
local function wallRun(self, alongX, line, a, b, y0, y1, th, color, material, holes, o)
	o = o or {}
	if a > b then
		a, b = b, a
	end
	local h2 = th / 2
	local name = o.name or "Wall"
	local function seg(s0, s1, lo, hi)
		if s1 - s0 < 0.05 or hi - lo < 0.05 then
			return
		end
		if alongX then
			self:Box(name, s0, s1, lo, hi, line - h2, line + h2, color, material, o.props)
		else
			self:Box(name, line - h2, line + h2, lo, hi, s0, s1, color, material, o.props)
		end
	end
	local list = table.clone(holes or {})
	table.sort(list, function(p, q)
		return p[1] < q[1]
	end)
	local ys = { y0, y1 }
	for _, hole in ipairs(list) do
		table.insert(ys, math.clamp(hole[3], y0, y1))
		table.insert(ys, math.clamp(hole[4], y0, y1))
	end
	table.sort(ys)
	local rows = {}
	for i = 1, #ys - 1 do
		local lo, hi = ys[i], ys[i + 1]
		if hi - lo > 0.01 then
			local mid = (lo + hi) / 2
			local free, cursor = {}, a
			for _, hole in ipairs(list) do
				if hole[3] < mid and hole[4] > mid then
					if hole[1] > cursor then
						table.insert(free, { cursor, hole[1] })
					end
					cursor = math.max(cursor, hole[2])
				end
			end
			if cursor < b then
				table.insert(free, { cursor, b })
			end
			local last = rows[#rows]
			local same = last ~= nil and #last.free == #free
			if same then
				for j, iv in ipairs(free) do
					if math.abs(iv[1] - last.free[j][1]) > 0.01 or math.abs(iv[2] - last.free[j][2]) > 0.01 then
						same = false
						break
					end
				end
			end
			if same then
				last.hi = hi
			else
				table.insert(rows, { lo = lo, hi = hi, free = free })
			end
		end
	end
	for _, row in ipairs(rows) do
		for _, iv in ipairs(row.free) do
			seg(iv[1], iv[2], row.lo, row.hi)
		end
	end
	-- Glass in the window and pane holes, on the outer half of the wall; sills and bars outside.
	local outSign = (o.out == "+Z" or o.out == "+X") and 1 or -1
	local out = o.out or (alongX and "-Z" or "-X")
	for _, hole in ipairs(list) do
		local kind = hole[5] or "win"
		local s0, s1, lo, hi = hole[1], hole[2], hole[3], hole[4]
		if kind == "exit" then
			-- An outside door (to a yard or a terrace): shut on the lot (nobody walks into the shell), open
			-- inside the owner's copy, its leaf swung back against the inner face of the wall.
			local leafColor, mat = hole.color or P.Walnut, hole.mat or M.WoodPlanks
			if not self.inside then
				if alongX then
					self:Box("BackDoor", s0, s1, lo, hi, line - h2, line + h2, leafColor, mat)
				else
					self:Box("BackDoor", line - h2, line + h2, lo, hi, s0, s1, leafColor, mat)
				end
			elseif s1 - s0 <= 7 then -- (a wider opening is a sliding door, slid away)
				local inSign = -outSign
				local w = s1 - s0
				if alongX then
					self:Deco("DoorLeaf", s0 - 0.2, s0, lo, hi - 0.2, line + inSign * h2, line + inSign * (h2 + w - 0.4), leafColor, mat)
				else
					self:Deco("DoorLeaf", line + inSign * h2, line + inSign * (h2 + w - 0.4), lo, hi - 0.2, s0 - 0.2, s0, leafColor, mat)
				end
			end
		end
		if kind == "win" or kind == "pane" then
			local g0, g1 = line + outSign * 0.05, line + outSign * math.min(h2, 0.45)
			if alongX then
				self:Window(s0, s1, lo, hi, g0, g1, out, hole.opts)
			else
				self:Window(g0, g1, lo, hi, s0, s1, out, hole.opts)
			end
			local bars = hole.bars or o.bars or 0
			local face0, face1 = line + outSign * h2, line + outSign * (h2 + 0.2)
			for i = 1, bars do
				local m = s0 + (s1 - s0) * i / (bars + 1)
				if alongX then
					self:Deco("Mullion", m - 0.15, m + 0.15, lo, hi, face0, face1, o.frame or P.DarkMetal, M.Metal)
				else
					self:Deco("Mullion", face0, face1, lo, hi, m - 0.15, m + 0.15, o.frame or P.DarkMetal, M.Metal)
				end
			end
			if hole.transom or o.transom then
				local y = lo + (hi - lo) * 0.72
				if alongX then
					self:Deco("Mullion", s0, s1, y - 0.15, y + 0.15, face0, face1, o.frame or P.DarkMetal, M.Metal)
				else
					self:Deco("Mullion", face0, face1, y - 0.15, y + 0.15, s0, s1, o.frame or P.DarkMetal, M.Metal)
				end
			end
			if kind == "win" and o.sill and lo > y0 + 0.5 then
				local f0, f1 = line + outSign * h2, line + outSign * (h2 + 0.6)
				if alongX then
					self:Box("Sill", s0 - 0.4, s1 + 0.4, lo - 0.5, lo, math.min(f0, f1), math.max(f0, f1), o.sill, o.sillMat or M.Concrete, DETAIL)
				else
					self:Box("Sill", math.min(f0, f1), math.max(f0, f1), lo - 0.5, lo, s0 - 0.4, s1 + 0.4, o.sill, o.sillMat or M.Concrete, DETAIL)
				end
			end
			if o.shutters and kind == "win" then
				local f0, f1 = line + outSign * h2, line + outSign * (h2 + 0.25)
				for _, sx in ipairs({ { s0 - 2, s0 - 0.2 }, { s1 + 0.2, s1 + 2 } }) do
					if alongX then
						self:Box("Shutter", sx[1], sx[2], lo, hi, math.min(f0, f1), math.max(f0, f1), o.shutters, M.WoodPlanks, DETAIL)
					else
						self:Box("Shutter", math.min(f0, f1), math.max(f0, f1), lo, hi, sx[1], sx[2], o.shutters, M.WoodPlanks, DETAIL)
					end
				end
			end
		end
	end
end

function Kit:WallX(z, a, b, y0, y1, th, color, material, holes, o)
	wallRun(self, true, z, a, b, y0, y1, th, color, material, holes, o)
end
function Kit:WallZ(x, a, b, y0, y1, th, color, material, holes, o)
	wallRun(self, false, x, a, b, y0, y1, th, color, material, holes, o)
end

-- Four outer walls round x0..x1, z0..z1 (the lines are the walls' middles), each th thick, corners
-- closed. holes = { front = {...}, back = {...}, left = {...}, right = {...} } (absolute x for front and
-- back, absolute z for left and right); false leaves that side out. o as for WallX (out is set per side).
function Kit:Walls4(x0, x1, z0, z1, y0, y1, th, color, material, holes, o)
	holes = holes or {}
	o = o or {}
	local h2 = th / 2
	local function side(key, out)
		local t = table.clone(o)
		t.out = out
		return t
	end
	if holes.front ~= false then
		self:WallX(z0, x0 - h2, x1 + h2, y0, y1, th, color, material, holes.front, side("front", "-Z"))
	end
	if holes.back ~= false then
		self:WallX(z1, x0 - h2, x1 + h2, y0, y1, th, color, material, holes.back, side("back", "+Z"))
	end
	if holes.left ~= false then
		self:WallZ(x0, z0 + h2, z1 - h2, y0, y1, th, color, material, holes.left, side("left", "-X"))
	end
	if holes.right ~= false then
		self:WallZ(x1, z0 + h2, z1 - h2, y0, y1, th, color, material, holes.right, side("right", "+X"))
	end
end

-- Evenly spaced window holes: n of width w along a..b, lo..hi (kind "win").
function HouseBuilder.Row(a, b, n, w, lo, hi, kind, extra)
	local holes = {}
	local gap = ((b - a) - n * w) / (n + 1)
	for i = 1, n do
		local s = a + gap * i + w * (i - 1)
		local hole = { s, s + w, lo, hi, kind or "win" }
		for k, v in pairs(extra or {}) do
			hole[k] = v
		end
		table.insert(holes, hole)
	end
	return holes
end

-- Joins lists of holes.
function HouseBuilder.Holes(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, h in ipairs(list) do
			table.insert(out, h)
		end
	end
	return out
end

-- Floors ---------------------------------------------------------------------------------------------------

-- A slab x0..x1, z0..z1 from y0 to y1 with rectangular holes { x0, x1, z0, z1 } cut out (stairwells,
-- pools), built from as few boxes as the holes allow.
function Kit:Slab(name, x0, x1, y0, y1, z0, z1, color, material, holes, props)
	local ax, bx, az, bz = math.min(x0, x1), math.max(x0, x1), math.min(z0, z1), math.max(z0, z1)
	if not holes or #holes == 0 then
		return self:Box(name, ax, bx, y0, y1, az, bz, color, material, props)
	end
	local xs, zs = { ax, bx }, { az, bz }
	for _, h in ipairs(holes) do
		table.insert(xs, math.clamp(math.min(h[1], h[2]), ax, bx))
		table.insert(xs, math.clamp(math.max(h[1], h[2]), ax, bx))
		table.insert(zs, math.clamp(math.min(h[3], h[4]), az, bz))
		table.insert(zs, math.clamp(math.max(h[3], h[4]), az, bz))
	end
	table.sort(xs)
	table.sort(zs)
	local function solid(cx, cz)
		for _, h in ipairs(holes) do
			if cx > math.min(h[1], h[2]) and cx < math.max(h[1], h[2]) and cz > math.min(h[3], h[4]) and cz < math.max(h[3], h[4]) then
				return false
			end
		end
		return true
	end
	-- Row by row (along z): runs of solid cells; a run the same as the row before grows that box.
	local open = {}
	local function flush(keep, zEnd)
		for key, r in pairs(open) do
			if not keep[key] then
				self:Box(name, r[1], r[2], y0, y1, r[3], zEnd, color, material, props)
				open[key] = nil
			end
		end
	end
	for j = 1, #zs - 1 do
		local za, zb = zs[j], zs[j + 1]
		if zb - za > 0.01 then
			local runs, start = {}, nil
			for i = 1, #xs - 1 do
				local xa, xb = xs[i], xs[i + 1]
				if xb - xa > 0.01 then
					local free = solid((xa + xb) / 2, (za + zb) / 2)
					if free and not start then
						start = xa
					elseif not free and start then
						table.insert(runs, { start, xa })
						start = nil
					end
				end
			end
			if start then
				table.insert(runs, { start, bx })
			end
			local keep = {}
			for _, r in ipairs(runs) do
				keep[r[1] .. "," .. r[2]] = true
			end
			flush(keep, za)
			for _, r in ipairs(runs) do
				local key = r[1] .. "," .. r[2]
				if not open[key] then
					open[key] = { r[1], r[2], za }
				end
			end
		end
	end
	flush({}, bz)
	return nil
end

-- A straight flight of stairs from (x, z) climbing along dir ("+X", "-X", "+Z", "-Z") from y0 to y1, w
-- wide (centred on the start across the climb). Each step rises 1 stud at most (o.tread deep, 1.5 by
-- default) and is solid down to y0 (o.thin = only that thick, for open steel stairs). Returns the run.
function Kit:Stairs(x, z, dir, w, y0, y1, color, material, o)
	o = o or {}
	local rise = y1 - y0
	local n = math.ceil(rise / (o.maxRise or 1) - 1e-6)
	local step = rise / n
	local tread = o.tread or 1.5
	local sx = (dir == "+X" and 1) or (dir == "-X" and -1) or 0
	local sz = (dir == "+Z" and 1) or (dir == "-Z" and -1) or 0
	for i = 1, n do
		local a, b = (i - 1) * tread, i * tread
		local top = y0 + step * i
		local bottom = o.thin and (top - o.thin) or y0
		if sx ~= 0 then
			self:Box("Step", x + sx * a, x + sx * b, bottom, top, z - w / 2, z + w / 2, color, material)
		else
			self:Box("Step", x - w / 2, x + w / 2, bottom, top, z + sz * a, z + sz * b, color, material)
		end
	end
	return n * tread
end

-- A railing along X or Z from (x0, z0) to (x1, z1) on a floor at y, h tall. kind "glass": one glass
-- panel under a metal handrail; "posts": balusters and a top rail; "solid": a low wall with a cap. It
-- collides (you lean on it). o.guard = the top of an invisible wall above it (roof terraces), o.color.
function Kit:Rail(x0, z0, x1, z1, y, h, kind, o)
	o = o or {}
	local alongX = math.abs(z1 - z0) < 0.01
	local color = o.color or P.DarkMetal
	local function span(name, w, lo, hi, c, mat, props)
		if alongX then
			return self:Box(name, x0, x1, lo, hi, z0 - w, z0 + w, c, mat, props)
		end
		return self:Box(name, x0 - w, x0 + w, lo, hi, z0, z1, c, mat, props)
	end
	if kind == "glass" then
		span("GlassRail", 0.15, y, y + h, P.RailGlass, M.Glass, { Transparency = 0.6, Reflectance = 0.1, CanQuery = false, CastShadow = false })
		span("Handrail", 0.25, y + h, y + h + 0.25, color, M.Metal, { CastShadow = false })
	elseif kind == "solid" then
		span("Parapet", 0.4, y, y + h, o.wall or P.White, o.wallMat or M.Plaster)
		span("Cap", 0.55, y + h, y + h + 0.3, o.cap or P.White, M.Concrete, DETAIL)
	else
		span("Rail", 0.2, y + h - 0.3, y + h, color, o.mat or M.Metal, { CastShadow = false })
		local len = alongX and math.abs(x1 - x0) or math.abs(z1 - z0)
		local n = math.max(1, math.floor(len / (o.every or 2)))
		for i = 0, n do
			local t = i / n
			local px, pz = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
			self:Deco("Baluster", px - 0.12, px + 0.12, y, y + h - 0.3, pz - 0.12, pz + 0.12, color, o.mat or M.Metal)
		end
		-- One invisible panel under the rail keeps everyone from slipping between the balusters.
		span("RailGuard", 0.1, y, y + h - 0.3, color, M.SmoothPlastic, GHOST)
	end
	if o.guard then
		span("Guard", 0.1, y + h, o.guard, color, M.SmoothPlastic, GHOST)
	end
end

-- Roofs ----------------------------------------------------------------------------------------------------

-- A pitched roof over x0..x1, z0..z1: an eave slab at height y (o.eave colour, when given), then two
-- clay-tile wedges rising `rise` to a ridge along X (or along Z with o.alongZ). o.props for looks-only
-- roofs on top of a flat slab (SHADE).
function Kit:Gable(x0, x1, y, z0, z1, rise, color, o)
	o = o or {}
	local mat = o.mat or M.ClayRoofTiles
	local base = y
	if o.eave then
		self:Box("Eave", x0, x1, y, y + 0.6, z0, z1, o.eave, o.eaveMat or M.WoodPlanks)
		base = y + 0.6
	end
	if o.alongZ then
		local xm = (x0 + x1) / 2
		self:Wedge("Roof", x0, xm, base, base + rise, z0, z1, color, mat, "-X", o.props)
		self:Wedge("Roof", xm, x1, base, base + rise, z0, z1, color, mat, "+X", o.props)
	else
		local zm = (z0 + z1) / 2
		self:Wedge("Roof", x0, x1, base, base + rise, z0, zm, color, mat, "-Z", o.props)
		self:Wedge("Roof", x0, x1, base, base + rise, zm, z1, color, mat, "+Z", o.props)
	end
end

-- A flat roof slab (named Roof: the minimap draws it) with an optional parapet `ph` tall all round.
function Kit:FlatRoof(x0, x1, y, z0, z1, color, material, ph, pColor, pMat, over)
	over = over or 0
	local ax, bx, az, bz = math.min(x0, x1) - over, math.max(x0, x1) + over, math.min(z0, z1) - over, math.max(z0, z1) + over
	self:Box("Roof", ax, bx, y, y + 1, az, bz, color, material)
	if ph and ph > 0 then
		local t, top = 0.8, y + 1 + ph
		self:Box("Parapet", ax, bx, y + 1, top, az, az + t, pColor, pMat)
		self:Box("Parapet", ax, bx, y + 1, top, bz - t, bz, pColor, pMat)
		self:Box("Parapet", ax, ax + t, y + 1, top, az + t, bz - t, pColor, pMat)
		self:Box("Parapet", bx - t, bx, y + 1, top, az + t, bz - t, pColor, pMat)
	end
end

-- A gable end: a flat triangle in a wall's plane, `th` thick, its base a..b at height y, its apex `rise`
-- above the middle. Along X at depth c (Triangle) or along Z at x = c (TriangleZ). Looks only.
function Kit:Triangle(a, b, y, rise, c, th, color, material)
	local m = (a + b) / 2
	self:Wedge("GableEnd", a, m, y, y + rise, c, c + th, color, material, "-X", SHADE)
	self:Wedge("GableEnd", m, b, y, y + rise, c, c + th, color, material, "+X", SHADE)
end
function Kit:TriangleZ(a, b, y, rise, c, th, color, material)
	local m = (a + b) / 2
	self:Wedge("GableEnd", c, c + th, y, y + rise, a, m, color, material, "-Z", SHADE)
	self:Wedge("GableEnd", c, c + th, y, y + rise, m, b, color, material, "+Z", SHADE)
end

-- Water ----------------------------------------------------------------------------------------------------

-- A pool x0..x1, z0..z1 (multiples of 4, so the Terrain water lines up with its voxel grid) whose deck
-- is at y = 0 of this frame (the yard), `depth` deep. Inside: a tiled basin under the deck (the deck
-- around it must leave this hole) holding real water you can swim in (out.water: HousingService fills
-- it, and clears it with the copy); the edge is a limestone coping. On the lot the city ground can't
-- be dug: a shallow basin with a raised coping and a glass water surface (nobody swims at the lot).
-- o.light = the pool light's colour (after dark), o.tile, o.step (a bench to climb out, default on).
function Kit:Pool(x0, x1, z0, z1, depth, o)
	o = o or {}
	local ax, bx, az, bz = math.min(x0, x1), math.max(x0, x1), math.min(z0, z1), math.max(z0, z1)
	local tile = o.tile or P.PoolTile
	local coping = o.coping or rgb(218, 212, 202)
	local cw = o.copingWidth or 1.2
	if self.inside then
		local d = depth
		self:Box("PoolFloor", ax, bx, -d - 0.6, -d, az, bz, tile, M.CeramicTiles)
		self:Box("PoolWall", ax - 0.6, bx + 0.6, -d - 0.6, 0, az - 0.6, az, tile, M.CeramicTiles)
		self:Box("PoolWall", ax - 0.6, bx + 0.6, -d - 0.6, 0, bz, bz + 0.6, tile, M.CeramicTiles)
		self:Box("PoolWall", ax - 0.6, ax, -d - 0.6, 0, az, bz, tile, M.CeramicTiles)
		self:Box("PoolWall", bx, bx + 0.6, -d - 0.6, 0, az, bz, tile, M.CeramicTiles)
		if o.step ~= false and d > 3 then
			self:Box("PoolStep", ax, ax + 3, -d, -2.4, az, bz, tile, M.CeramicTiles)
			self:Box("PoolStep", ax + 3, ax + 5, -d, -d + 1.6, az, bz, tile, M.CeramicTiles)
		end
		-- Water from the floor up to the deck (snapped to the 4-stud grid in world space).
		local a = self.cf * Vector3.new(ax, -d, az)
		local b = self.cf * Vector3.new(bx, 0, bz)
		local function snap(v)
			return math.floor(v / 4 + 0.5) * 4
		end
		local lo = Vector3.new(snap(math.min(a.X, b.X)), snap(math.min(a.Y, b.Y)), snap(math.min(a.Z, b.Z)))
		local hi = Vector3.new(snap(math.max(a.X, b.X)), snap(math.max(a.Y, b.Y)), snap(math.max(a.Z, b.Z)))
		if hi.X > lo.X and hi.Y > lo.Y and hi.Z > lo.Z then
			table.insert(self.out.water, { cf = CFrame.new((lo + hi) / 2), size = hi - lo })
		end
		if o.light then
			self:Neon(ax + 0.5, bx - 0.5, -d + 1, -d + 1.3, bz - 0.05, bz, o.light)
		end
		local top = 0.25
		self:Box("Coping", ax - cw, bx + cw, 0, top, az - cw, az, coping, M.Limestone)
		self:Box("Coping", ax - cw, bx + cw, 0, top, bz, bz + cw, coping, M.Limestone)
		self:Box("Coping", ax - cw, ax, 0, top, az, bz, coping, M.Limestone)
		self:Box("Coping", bx, bx + cw, 0, top, az, bz, coping, M.Limestone)
	else
		local rim = 1.4
		self:Box("PoolFloor", ax, bx, 0, 0.3, az, bz, tile, M.CeramicTiles)
		self:Box("PoolRim", ax - cw, bx + cw, 0, rim, az - cw, az, coping, M.Limestone)
		self:Box("PoolRim", ax - cw, bx + cw, 0, rim, bz, bz + cw, coping, M.Limestone)
		self:Box("PoolRim", ax - cw, ax, 0, rim, az, bz, coping, M.Limestone)
		self:Box("PoolRim", bx, bx + cw, 0, rim, az, bz, coping, M.Limestone)
		self:Box("PoolWater", ax, bx, 0.3, rim - 0.3, az, bz, P.PoolWater, M.Glass,
			{ Transparency = 0.3, Reflectance = 0.1, CanCollide = false, CanQuery = false, CastShadow = false })
		if o.light then
			self:Neon(ax + 0.5, bx - 0.5, 0.35, 0.5, bz - 0.4, bz - 0.05, o.light)
		end
	end
end

-- Signs ----------------------------------------------------------------------------------------------------

-- Sign text on one face of a part (LightInfluence 0: crisp by day, glowing at night): the title in
-- Oswald, the (optional) sub label in small print. Returns the title and the sub label.
local function signGui(part, face, title, sub, titleColor, subColor, ppx)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppx or 25
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.04, sub and 0.06 or 0.1)
	t.Size = UDim2.fromScale(0.92, sub and 0.52 or 0.8)
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = titleColor or P.White
	t.Text = title
	t.Parent = gui
	local s
	if sub then
		s = Instance.new("TextLabel")
		s.Name = "Sub"
		s.BackgroundTransparency = 1
		s.Position = UDim2.fromScale(0.04, 0.6)
		s.Size = UDim2.fromScale(0.92, 0.34)
		s.Font = SMALL_FONT
		s.TextScaled = true
		s.TextColor3 = subColor or P.Gold
		s.Text = sub
		s.Parent = gui
	end
	gui.Parent = part
	return t, s
end
HouseBuilder.SignGui = signGui

-- A dark board w x h on this frame's front (-Z) face at (x, y, z) with lettering (and an optional neon
-- line along its top after dark). Returns the board, its title and sub label.
function Kit:Board(name, x, y, z, w, h, title, sub, titleColor, trim, props)
	local board = self:Box(name, x - w / 2, x + w / 2, y - h / 2, y + h / 2, z - 0.15, z + 0.15, P.Dark, M.Metal, props or DETAIL)
	local t, s = signGui(board, Enum.NormalId.Front, title, sub, titleColor, P.White)
	if trim then
		self:Neon(x - w / 2, x + w / 2, y + h / 2, y + h / 2 + 0.25, z - 0.15, z + 0.15, trim)
	end
	return board, t, s
end

-- Letters only (an invisible board): a name on a wall or a roof.
function Kit:Letters(x, y, z, w, h, text, color, face)
	local board = self:Box("Letters", x - w / 2, x + w / 2, y - h / 2, y + h / 2, z - 0.1, z + 0.1, P.White, M.SmoothPlastic,
		merge(DETAIL, { Transparency = 1 }))
	signGui(board, face or Enum.NormalId.Front, text, nil, color)
	return board
end

-- A free-standing sign (a show home's FOR SALE stand and its garage sign): a dark board w x h whose
-- bottom is `lift` up, on two slim dark-metal posts with flat feet, a neon line along its top in `trim`
-- (after dark). This frame's origin is the spot on the floor, its front (-Z) the way the board faces.
-- The posts never collide; the board only when `solid` (one that carries a prompt). Returns the board.
function Kit:Stand(w, h, lift, title, sub, titleColor, trim, solid)
	for _, x in ipairs({ -w / 2 + 0.6, w / 2 - 0.6 }) do
		self:Deco("SignPost", x - 0.15, x + 0.15, 0.2, lift + h - 0.2, 0.15, 0.45, P.DarkMetal, M.Metal)
		self:Deco("SignFoot", x - 0.3, x + 0.3, 0, 0.2, -0.9, 1.5, P.DarkMetal, M.Metal)
	end
	local board = self:Box("SignBoard", -w / 2, w / 2, lift, lift + h, -0.15, 0.15, P.Dark, M.Metal, not solid and SHADE or nil)
	self:Neon(-w / 2, w / 2, lift + h, lift + h + 0.25, -0.15, 0.15, trim)
	signGui(board, Enum.NormalId.Front, title, sub, titleColor, P.White)
	return board
end

-- The street sign (lot only): name and price on a dark board between two posts at (x, z), a neon line
-- along its top after dark. HouseClient changes the sub line to YOUR HOME for the owner.
function Kit:StreetSign(x, z, postColor, postMat)
	if not self.lot then
		return nil
	end
	local home = self.home
	local f = self:In("Signs")
	f:Box("SignPost", x - 6.4, x - 5.6, 0.2, 8, z - 0.4, z + 0.4, postColor or P.White, postMat or M.Concrete)
	f:Box("SignPost", x + 5.6, x + 6.4, 0.2, 8, z - 0.4, z + 0.4, postColor or P.White, postMat or M.Concrete)
	local board = f:Box("HomeSign", x - 7, x + 7, 3.4, 8.6, z - 0.3, z + 0.3, P.Dark, M.Metal)
	board:SetAttribute("HomeId", home.Id)
	f:Neon(x - 7, x + 7, 8.6, 9, z - 0.3, z + 0.3, home.Trim)
	signGui(board, Enum.NormalId.Front, home.Name, "FOR SALE · " .. HouseBuilder.Money(home.Price), P.White, P.Gold)
	self.out.sign = board
	return board
end

-- Plants and props (lot and inside) ----------------------------------------------------------------------

local BARK = rgb(128, 110, 88)
local FROND = rgb(64, 108, 58)

-- A palm at (x, z) on a ground at y (default 0): the city art's palm mesh (ServerStorage.ArtAssets
-- .PalmTree) on an invisible trunk post that is its collision, kept under 13.5 studs across; without the
-- mesh, six drooping fronds and two coconuts on a wooden trunk.
function Kit:Palm(x, z, height, yaw, y)
	local base = self.cf * CFrame.new(x, (y or 0) + 0.2, z)
	local trunk = self:Part("Part", "PalmTrunk", Vector3.new(height, 1.6, 1.6), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		BARK, M.Wood, { Shape = Enum.PartType.Cylinder })
	local assets = ServerStorage:FindFirstChild("ArtAssets")
	local template = assets and assets:FindFirstChild("PalmTree")
	yaw = yaw or self.rng:NextNumber(0, math.pi * 2)
	if template and template:IsA("BasePart") then
		trunk.Transparency = 1
		local mesh = template:Clone()
		mesh.Name = "PalmTree"
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CastShadow = true
		mesh.Size = template.Size * math.min(height / 22, 13.5 / math.max(template.Size.X, template.Size.Z))
		mesh.CFrame = base * CFrame.new(0, mesh.Size.Y / 2, 0) * CFrame.Angles(0, yaw, 0)
		mesh.Parent = self.parent
		self.stats.parts += 1
		return trunk
	end
	local top = base * CFrame.new(0, height, 0)
	for i = 0, 5 do
		self:Part("Part", "PalmLeaf", Vector3.new(2.4, 0.3, 9),
			top * CFrame.Angles(0, yaw + math.rad(i * 60 + 15), 0) * CFrame.Angles(math.rad(-28), 0, 0) * CFrame.new(0, 0, -4.2),
			FROND, M.Grass, DETAIL)
	end
	for _, a in ipairs({ 40, 200 }) do
		self:Part("Part", "Coconut", Vector3.new(1, 1, 1), top * CFrame.Angles(0, math.rad(a), 0) * CFrame.new(0, -0.7, -0.9),
			rgb(92, 66, 40), M.SmoothPlastic, merge(DETAIL, { Shape = Enum.PartType.Ball }))
	end
	return trunk
end

-- Another generated art mesh from ServerStorage.ArtAssets (TropicalBush, CypressTree, FlamingoStatue,
-- Yacht...), scaled, standing on y at (x, z), looks only. Returns nil when the place doesn't have it.
function Kit:Asset(name, x, z, scale, yaw, y)
	local assets = ServerStorage:FindFirstChild("ArtAssets")
	local template = assets and assets:FindFirstChild(name)
	if not template then
		return nil
	end
	local c = template:Clone()
	local base = self.cf * CFrame.new(x, y or 0, z) * CFrame.Angles(0, math.rad(yaw or self.rng:NextNumber(0, 360)), 0)
	local parts = c:IsA("BasePart") and { c } or c:GetDescendants()
	for _, d in ipairs(parts) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = scale > 0.5
			self.stats.parts += 1
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	if c:IsA("BasePart") then
		c.Size = c.Size * scale
		c.CFrame = base * CFrame.new(0, c.Size.Y / 2, 0)
	elseif c:IsA("Model") then
		pcall(function()
			c:ScaleTo(scale)
		end)
		local cf, size = c:GetBoundingBox()
		local bottom = cf * CFrame.new(0, -size.Y / 2, 0)
		c:PivotTo(base * bottom:ToObjectSpace(c:GetPivot()))
	end
	c.Parent = self.parent
	return c
end

-- A round bush (looks only) and a clipped hedge (collides).
function Kit:Bush(x, z, d, color, y)
	return self:Ball("Bush", x, (y or 0) + d * 0.38, z, d, color or P.Leaf, M.Grass, SHADE)
end
function Kit:Hedge(x0, x1, z0, z1, h, color)
	return self:Box("Hedge", x0, x1, 0, h or 4, z0, z1, color or P.Hedge, M.Grass)
end

-- A row of flowers on a bed: bushes with hibiscus blooms (looks only).
function Kit:FlowerBed(x0, x1, z, colors)
	self:Box("Bed", x0, x1, 0, 0.6, z - 1.3, z + 1.3, rgb(96, 72, 52), M.Ground, DETAIL)
	local n = math.max(2, math.floor((x1 - x0) / 3.2))
	for i = 0, n - 1 do
		local x = x0 + 1.6 + i * (x1 - x0 - 3.2) / math.max(1, n - 1)
		self:Ball("Bush", x, 1.4, z, 2.2, P.Leaf, M.Grass, DETAIL)
		self:Ball("Flower", x + 0.4, 2.4, z - 0.6, 0.8, (colors or { rgb(196, 52, 64), rgb(232, 190, 60) })[i % 2 + 1], M.SmoothPlastic, DETAIL)
	end
end

-- Bollard lights (warm after dark) at each (x, z).
function Kit:Bollards(list)
	for _, p in ipairs(list) do
		self:Box("Bollard", p[1] - 0.6, p[1] + 0.6, 0.2, 3, p[2] - 0.6, p[2] + 0.6, P.DarkMetal, M.Metal, { CastShadow = false })
		self:Lamp("BollardLight", p[1] - 0.6, p[1] + 0.6, 3, 3.5, p[2] - 0.6, p[2] + 0.6, P.Warm, self.lot and 12 or nil, 0.8)
	end
end

-- A wall lantern on a wall whose face looks -Z of this frame, at (x, y, z) on that face: a dark back
-- plate and a lamp in front of it.
function Kit:WallLamp(x, y, z, color, range)
	self:Deco("LampBack", x - 0.5, x + 0.5, y - 1, y + 1.2, z - 0.3, z, P.DarkMetal, M.Metal)
	return self:Lamp("WallLight", x - 0.35, x + 0.35, y - 0.8, y + 1, z - 0.7, z - 0.3, color or P.Warm, range, 0.8)
end

-- A trim strip on a wall face (plinths, floor bands, cornices): along X from a to b (BandX, between the
-- depths d0..d1) or along Z (BandZ, between x = d0..d1), y0..y1, skipping the `gaps` ({ g0, g1 } along
-- the run: doors). Looks only.
local function band(self, alongX, a, b, y0, y1, d0, d1, color, material, gaps)
	local cuts = table.clone(gaps or {})
	table.sort(cuts, function(p, q)
		return p[1] < q[1]
	end)
	local cursor = a
	local function piece(s0, s1)
		if s1 - s0 > 0.05 then
			if alongX then
				self:Deco("Band", s0, s1, y0, y1, d0, d1, color, material)
			else
				self:Deco("Band", d0, d1, y0, y1, s0, s1, color, material)
			end
		end
	end
	for _, g in ipairs(cuts) do
		piece(cursor, g[1])
		cursor = math.max(cursor, g[2])
	end
	piece(cursor, b)
end
function Kit:BandX(a, b, y0, y1, d0, d1, color, material, gaps)
	band(self, true, a, b, y0, y1, d0, d1, color, material, gaps)
end
function Kit:BandZ(a, b, y0, y1, d0, d1, color, material, gaps)
	band(self, false, a, b, y0, y1, d0, d1, color, material, gaps)
end
-- The same strip round all four outer faces of x0..x1, z0..z1, `out` studs proud of them; gaps per side
-- ({ front = {...}, back = ..., left = ..., right = ... }).
function Kit:Ring(x0, x1, z0, z1, y0, y1, out, color, material, gaps)
	gaps = gaps or {}
	self:BandX(x0 - out, x1 + out, y0, y1, z0 - out, z0, color, material, gaps.front)
	self:BandX(x0 - out, x1 + out, y0, y1, z1, z1 + out, color, material, gaps.back)
	self:BandZ(z0, z1, y0, y1, x0 - out, x0, color, material, gaps.left)
	self:BandZ(z0, z1, y0, y1, x1, x1 + out, color, material, gaps.right)
end

-- Furniture (inside only; each drawn in its own frame: front = -Z, standing on y = 0) ------------------------

local function seatAt(self, x, y, z, w, d, exitDist, exitX)
	local s = self:Part("Seat", "Seat", Vector3.new(w, 0.4, d), self.cf * CFrame.new(x, y, z),
		P.White, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CastShadow = false })
	-- EXIT stands you in front of the seat (VehicleService: a home's model is no car to step out of), or
	-- at exitX level with it (rows too close together to stand between: off the end of the row).
	local spot = exitX and CFrame.new(exitX, 3.2, z) or CFrame.new(x, 3.2, z - d / 2 - (exitDist or 2.6))
	s:SetAttribute("ExitAt", (self.cf * spot).Position)
	return s
end

-- A sofa w wide (seat at -Z, back at +Z), o.seats = how many seats (0 for none), o.l = an L end on +X,
-- o.exitSide = -1 / 1: getting up steps off that end of the sofa instead of in front of it.
function Kit:Sofa(x, y, z, yaw, w, color, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	local mat = o.mat or M.Fabric
	f:Box("Sofa", -w / 2, w / 2, 0, 2, -1.8, 1.8, color, mat)
	f:Box("SofaBack", -w / 2, w / 2, 2, 4.6, 0.9, 1.8, color, mat)
	f:Box("SofaArm", -w / 2 - 0.9, -w / 2, 0, 3.2, -1.8, 1.8, color, mat)
	if o.l then
		f:Box("Sofa", w / 2, w / 2 + 3.6, 0, 2, -1.8 - o.l, 1.8, color, mat)
		f:Box("SofaBack", w / 2 + 2.7, w / 2 + 3.6, 2, 4.6, -1.8 - o.l, 1.8, color, mat)
	else
		f:Box("SofaArm", w / 2, w / 2 + 0.9, 0, 3.2, -1.8, 1.8, color, mat)
	end
	if o.pillows then
		f:Deco("Pillow", -w / 2 + 0.5, -w / 2 + 2.3, 2, 3.8, 0.2, 0.9, o.pillows, M.Fabric)
		f:Deco("Pillow", w / 2 - 2.3, w / 2 - 0.5, 2, 3.8, 0.2, 0.9, o.pillows, M.Fabric)
	end
	local n = o.seats or math.max(1, math.floor(w / 5))
	local exitX = o.exitSide and o.exitSide * (w / 2 + 0.9 + 2) or nil
	for i = 1, n do
		seatAt(f, -w / 2 + w * (i - 0.5) / n, 2.2, -0.3, 3.4, 3, 2.8, exitX)
	end
end

function Kit:Armchair(x, y, z, yaw, color, material, seat)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Chair", -1.8, 1.8, 0, 2, -1.7, 1.7, color, material or M.Fabric)
	f:Box("ChairBack", -1.8, 1.8, 2, 4.4, 0.9, 1.7, color, material or M.Fabric)
	f:Deco("ChairArm", -2.3, -1.8, 0, 3, -1.7, 1.7, color, material or M.Fabric)
	f:Deco("ChairArm", 1.8, 2.3, 0, 3, -1.7, 1.7, color, material or M.Fabric)
	if seat ~= false then
		seatAt(f, 0, 2.2, -0.3, 2.8, 2.6, 2.8)
	end
end

function Kit:Table(x, y, z, yaw, w, d, h, color, material, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	if o.round then
		f:Cyl("TableTop", 0, 0, h - 0.3, h, math.max(w, d), color, material or M.Wood)
		f:Cyl("TableLeg", 0, 0, 0, h - 0.3, 1, o.leg or color, o.legMat or material or M.Wood, DETAIL)
		return
	end
	f:Box("TableTop", -w / 2, w / 2, h - 0.3, h, -d / 2, d / 2, color, material or M.Wood, o.top)
	if o.glass then
		f:Deco("TableBase", -w / 2 + 0.8, w / 2 - 0.8, 0, h - 0.3, -0.3, 0.3, o.leg or P.Steel, M.Metal)
	else
		for _, lx in ipairs({ -w / 2 + 0.4, w / 2 - 0.4 }) do
			for _, lz in ipairs({ -d / 2 + 0.4, d / 2 - 0.4 }) do
				f:Deco("TableLeg", lx - 0.25, lx + 0.25, 0, h - 0.3, lz - 0.25, lz + 0.25, o.leg or color, o.legMat or material or M.Wood)
			end
		end
	end
end

-- A dining chair (seat and back), facing -Z.
function Kit:Chair(x, y, z, yaw, color, material)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Chair", -0.9, 0.9, 1.6, 2, -0.9, 0.9, color, material or M.Wood, DETAIL)
	f:Deco("ChairBack", -0.9, 0.9, 2, 4.4, 0.6, 0.9, color, material or M.Wood)
	for _, lx in ipairs({ -0.7, 0.7 }) do
		for _, lz in ipairs({ -0.7, 0.7 }) do
			f:Deco("ChairLeg", lx - 0.12, lx + 0.12, 0, 1.6, lz - 0.12, lz + 0.12, color, material or M.Wood)
		end
	end
end

-- A dining set: a table w x d with n chairs a side (and one at each end with o.ends).
function Kit:Dining(x, y, z, yaw, w, d, n, tableColor, chairColor, o)
	if not self.inside then
		return
	end
	o = o or {}
	self:Table(x, y, z, yaw, w, d, 3.2, tableColor, o.mat, o)
	local f = self:Sub(x, y, z, yaw)
	for i = 1, n do
		local cx = -w / 2 + w * (i - 0.5) / n
		f:Chair(cx, 0, -d / 2 - 1.2, 180, chairColor, o.chairMat)
		f:Chair(cx, 0, d / 2 + 1.2, 0, chairColor, o.chairMat)
	end
	if o.ends then
		f:Chair(-w / 2 - 1.2, 0, 0, -90, chairColor, o.chairMat)
		f:Chair(w / 2 + 1.2, 0, 0, 90, chairColor, o.chairMat)
	end
	if o.lamp then
		f:Lamp("Pendant", -1, 1, 10, 11, -1, 1, P.Warm, 18, 0.5)
	end
end

function Kit:Rug(x, y, z, yaw, w, d, color, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	if o.round then
		return f:Cyl("Rug", 0, 0, 0, 0.1, w, color, M.Fabric, DETAIL)
	end
	return f:Deco("Rug", -w / 2, w / 2, 0, 0.1, -d / 2, d / 2, color, o.mat or M.Fabric)
end

-- The TV picture: an evening sky over the sea under the channel's name (a screen stays lit by day).
local function tvScreen(part, title, sub)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Screen"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BorderSizePixel = 0
	bg.BackgroundColor3 = Color3.new(1, 1, 1)
	bg.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(30, 46, 96)), -- evening sky
		ColorSequenceKeypoint.new(0.55, rgb(226, 128, 76)), -- sunset on the horizon
		ColorSequenceKeypoint.new(0.6, rgb(40, 76, 104)), -- the sea
		ColorSequenceKeypoint.new(1, rgb(20, 40, 60)),
	})
	grad.Rotation = 90
	grad.Parent = bg
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.05, 0.22)
	t.Size = UDim2.fromScale(0.9, 0.34)
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Text = title or "MIAMI COAST TV"
	t.Parent = bg
	local s = Instance.new("TextLabel")
	s.BackgroundTransparency = 1
	s.Position = UDim2.fromScale(0.08, 0.6)
	s.Size = UDim2.fromScale(0.84, 0.16)
	s.Font = Enum.Font.GothamMedium
	s.TextScaled = true
	s.TextColor3 = Color3.new(1, 1, 1)
	s.Text = sub or "Cartoons, races and car shows all day!"
	s.Parent = bg
	gui.Parent = part
end

-- A flat TV w wide, its screen facing -Z: on a low cabinet, or o.wall = hung at height o.at. o.glow =
-- the backlight's neon colour (after dark).
function Kit:TV(x, y, z, yaw, w, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	local h = w * 0.56
	local base = o.at or 4.6
	if not o.wall then
		f:Box("TVStand", -w / 2 - 1, w / 2 + 1, 0, 2.6, -1.2, 1.2, o.cabinet or P.Walnut, M.Wood)
		base = 3.4
	end
	local tv = f:Box("TV", -w / 2, w / 2, base, base + h, 0.6, 1, rgb(14, 14, 20), M.SmoothPlastic, DETAIL)
	tvScreen(tv, o.title, o.sub)
	if o.glow then
		f:Neon(-w / 2, w / 2, base - 0.4, base, 0.7, 1.2, o.glow)
	end
	return tv
end

-- A bed w wide and l long, the headboard at +Z.
function Kit:Bed(x, y, z, yaw, w, l, frame, sheet, blanket, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("BedFrame", -w / 2, w / 2, 0, 1.6, -l / 2, l / 2, frame, o.frameMat or M.Wood)
	f:Box("Mattress", -w / 2 + 0.2, w / 2 - 0.2, 1.6, 3, -l / 2 + 0.2, l / 2 - 0.3, sheet, M.Fabric, DETAIL)
	f:Deco("Blanket", -w / 2 + 0.1, w / 2 - 0.1, 2.4, 3.2, -l / 2 + 0.1, l / 2 - 3.6, blanket, M.Fabric)
	f:Deco("Pillow", -w / 2 + 0.6, -0.3, 3, 3.9, l / 2 - 3, l / 2 - 0.9, o.pillow or P.White, M.Fabric)
	f:Deco("Pillow", 0.3, w / 2 - 0.6, 3, 3.9, l / 2 - 3, l / 2 - 0.9, o.pillow or P.White, M.Fabric)
	f:Box("Headboard", -w / 2 - 0.2, w / 2 + 0.2, 0, o.head or 6.5, l / 2 - 0.3, l / 2 + 0.5, o.headColor or frame, o.headMat or o.frameMat or M.Wood)
	if o.reading then
		f:Neon(-w / 2, w / 2, (o.head or 6.5), (o.head or 6.5) + 0.3, l / 2 - 0.3, l / 2 + 0.5, o.reading)
	end
end

function Kit:BunkBed(x, y, z, yaw, frame, a, b)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("BedFrame", -2.4, 2.4, 0, 1.2, -4.2, 4.2, frame, M.Wood)
	f:Deco("Mattress", -2.2, 2.2, 1.2, 2.2, -4, 4, a, M.Fabric)
	f:Box("BedFrame", -2.4, 2.4, 5.6, 6.4, -4.2, 4.2, frame, M.Wood)
	f:Deco("Mattress", -2.2, 2.2, 6.4, 7.3, -4, 4, b, M.Fabric)
	for _, cx in ipairs({ -2.4, 2.4 }) do
		for _, cz in ipairs({ -4.2, 4.2 }) do
			f:Deco("BedPost", cx - 0.25, cx + 0.25, 0, 8.4, cz - 0.25, cz + 0.25, frame, M.Wood)
		end
	end
	for i = 1, 4 do
		f:Deco("Rung", 2.4, 2.7, i * 1.5, i * 1.5 + 0.2, -3, -1.6, frame, M.Wood)
	end
end

-- A nightstand with a little lamp (lit after dark).
function Kit:Nightstand(x, y, z, yaw, color)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Nightstand", -1.2, 1.2, 0, 2.6, -1.1, 1.1, color or P.Walnut, M.Wood)
	f:Lamp("BedsideLamp", -0.6, 0.6, 2.6, 4, -0.6, 0.6, P.Warm, 12, 0.5)
end

-- A kitchen run w long along X (2.8 deep, its back at +Z): cabinets, a stone worktop, sink and hob,
-- o.upper wall cabinets, o.hood a cooker hood.
function Kit:Kitchen(x, y, z, yaw, w, cab, top, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Cabinets", -w / 2, w / 2, 0, 3.2, -1.4, 1.4, cab, o.cabMat or M.Wood)
	f:Deco("Worktop", -w / 2 - 0.1, w / 2 + 0.1, 3.2, 3.6, -1.6, 1.4, top, o.topMat or M.Marble)
	f:Deco("Sink", -w / 4 - 1.2, -w / 4 + 1.2, 3.55, 3.65, -1, 0.6, P.Steel, M.Metal)
	f:Deco("Tap", -w / 4 - 0.15, -w / 4 + 0.15, 3.6, 5, 0.6, 0.9, P.Steel, M.Metal)
	f:Deco("Hob", w / 4 - 1.4, w / 4 + 1.4, 3.55, 3.7, -1, 0.8, P.Black, M.Glass)
	for i = 0, math.floor(w / 3) - 1 do
		local hx = -w / 2 + 1.5 + i * 3
		f:Deco("Handle", hx - 0.6, hx + 0.6, 2.6, 2.8, -1.5, -1.4, P.Steel, M.Metal)
	end
	if o.upper then
		f:Box("UpperCabinets", -w / 2, w / 2, 7.4, 10, 0.2, 1.4, o.upper, o.cabMat or M.Wood, DETAIL)
		f:Lamp("UnderLight", -w / 2 + 0.3, w / 2 - 0.3, 7.2, 7.4, 0.4, 1.2, P.Warm)
	end
	if o.hood then
		f:Box("Hood", w / 4 - 1.6, w / 4 + 1.6, 7.6, 9.4, -0.4, 1.4, o.hood, M.Metal, DETAIL)
	end
	if o.splash then
		f:Deco("Splashback", -w / 2, w / 2, 3.6, 7.4, 1.25, 1.4, o.splash, M.CeramicTiles)
	end
end

function Kit:Fridge(x, y, z, yaw, color)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Fridge", -1.8, 1.8, 0, 8, -1.5, 1.5, color or P.Steel, M.Metal)
	f:Deco("Handle", 0.9, 1.1, 2.8, 6, -1.65, -1.5, P.DarkMetal, M.Metal)
	f:Deco("Handle", -1.1, -0.9, 2.8, 6, -1.65, -1.5, P.DarkMetal, M.Metal)
end

-- A kitchen island w long with stools on its -Z side (n of them).
function Kit:Island(x, y, z, yaw, w, cab, top, stool, n)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Island", -w / 2, w / 2, 0, 3.4, -1.6, 1.6, cab, M.Wood)
	f:Deco("IslandTop", -w / 2 - 0.3, w / 2 + 0.3, 3.4, 3.8, -2.4, 1.8, top, M.Marble)
	for i = 1, (n or 0) do
		local sx = -w / 2 + w * (i - 0.5) / n
		f:Cyl("Stool", sx, -3.4, 2.6, 3, 1.8, stool, M.Leather, DETAIL)
		f:Cyl("StoolLeg", sx, -3.4, 0, 2.6, 0.35, P.Steel, M.Metal, DETAIL)
	end
end

function Kit:Bookshelf(x, y, z, yaw, w, h, color, books)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Shelf", -w / 2, w / 2, 0, h, -0.8, 0.8, color, M.Wood)
	local cols = books or { rgb(160, 52, 60), rgb(52, 90, 150), rgb(210, 176, 80), rgb(70, 110, 80) }
	local rows = math.max(2, math.floor(h / 2.6))
	for r = 1, rows do
		local yy = h * r / (rows + 1)
		f:Deco("Books", -w / 2 + 0.3, w / 2 - 0.3, yy, yy + 1.5, -0.95, -0.8, cols[(r - 1) % #cols + 1], M.SmoothPlastic)
	end
end

-- A potted plant (o.tall for an indoor palm).
function Kit:Plant(x, y, z, pot, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, 0)
	f:Cyl("Pot", 0, 0, 0, 2.4, 2.6, pot or rgb(170, 100, 70), M.Concrete)
	if o.tall then
		f:Cyl("Stem", 0, 0, 2.4, 6, 0.4, P.Walnut, M.Wood, DETAIL)
		f:Ball("Leaves", 0, 7, 0, 4.4, o.leaf or P.Leaf, M.Grass, DETAIL)
	else
		f:Ball("Leaves", 0, 3.8, 0, 3.6, o.leaf or P.Leaf, M.Grass, DETAIL)
	end
end

function Kit:FloorLamp(x, y, z, color)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, 0)
	f:Deco("LampFoot", -0.8, 0.8, 0, 0.3, -0.8, 0.8, P.DarkMetal, M.Metal)
	f:Deco("LampPole", -0.15, 0.15, 0.3, 8, -0.15, 0.15, P.DarkMetal, M.Metal)
	f:Lamp("LampShade", -1.3, 1.3, 8, 10, -1.3, 1.3, color or P.Warm, 20, 0.6)
end

-- A picture on a wall (this frame's -Z is the room): a frame and a canvas, o.neon = a neon line round
-- the canvas after dark.
function Kit:Art(x, y, z, yaw, w, h, frame, canvas, neon)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Deco("ArtFrame", -w / 2, w / 2, -h / 2, h / 2, -0.15, 0.15, frame, M.Wood)
	f:Deco("Canvas", -w / 2 + 0.3, w / 2 - 0.3, -h / 2 + 0.3, h / 2 - 0.3, -0.25, -0.15, canvas, M.SmoothPlastic)
	if neon then
		f:Neon(-w / 2 + 0.6, w / 2 - 0.6, -h / 2 + 0.6, -h / 2 + 0.8, -0.3, -0.25, neon)
	end
end

function Kit:Desk(x, y, z, yaw, color, chair, glow)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Desk", -3, 3, 3, 3.4, -1.6, 1.6, color, M.Wood)
	f:Deco("DeskLeg", -2.8, -2.3, 0, 3, -1.4, 1.4, color, M.Wood)
	f:Deco("DeskLeg", 2.3, 2.8, 0, 3, -1.4, 1.4, color, M.Wood)
	f:Deco("Monitor", -1.6, 1.6, 3.8, 5.8, 0.6, 0.8, P.Black, M.SmoothPlastic)
	f:Deco("Screen", -1.45, 1.45, 3.95, 5.65, 0.5, 0.6, glow or rgb(80, 200, 255), M.Neon)
	f:Deco("DeskChair", -1.1, 1.1, 0, 2.4, -3.4, -1.8, chair, M.Leather)
	f:Deco("DeskChairBack", -1.1, 1.1, 2.4, 5, -3.4, -3.1, chair, M.Leather)
end

-- A bathroom run along X (its back at +Z), 12 long (x -6..6): tub, toilet and vanity with a mirror; or
-- o.shower = a glass shower instead of the tub (10 long, x -5..5). o.tile = the tiles on the back wall.
function Kit:Bath(x, y, z, yaw, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	local x0, x1 = -6, 6
	if o.shower then
		x0, x1 = -5, 5
		f:Deco("ShowerTray", -5, -1.4, 0, 0.3, -1.6, 1.6, P.White, M.Marble)
		f:Box("ShowerGlass", -5, -1.4, 0.3, 8, -1.7, -1.5, P.ClearGlass, M.Glass, { Transparency = 0.6, CanQuery = false })
		f:Box("ShowerGlass", -1.6, -1.4, 0.3, 8, -1.5, 1.6, P.ClearGlass, M.Glass, { Transparency = 0.6, CanQuery = false })
		f:Deco("ShowerHead", -3.6, -2.6, 7.4, 7.7, 0.9, 1.6, P.Steel, M.Metal)
		f:Box("Toilet", -0.6, 1.2, 0, 1.9, -0.4, 1.6, P.White, M.Marble)
		f:Deco("Cistern", -0.6, 1.2, 1.9, 3.6, 1, 1.6, P.White, M.Marble)
		f:Box("Vanity", 1.9, 5, 0, 3.2, -0.1, 1.6, o.vanity or P.Walnut, M.Wood)
		f:Deco("Basin", 2.6, 4.3, 3.2, 3.5, 0.1, 1.2, P.White, M.Marble)
		f:Deco("Mirror", 2.2, 4.7, 4.4, 7.6, 1.45, 1.6, rgb(214, 232, 246), M.Glass, { Reflectance = 0.35 })
	else
		f:Box("Tub", -6, 0, 0, 2.6, -1.6, 1.6, P.White, M.Marble)
		f:Deco("TubWater", -5.6, -0.4, 1.9, 2.65, -1.2, 1.2, P.PoolWater, M.Glass, { Transparency = 0.3 })
		f:Box("Toilet", 0.8, 2.6, 0, 1.9, -0.4, 1.6, P.White, M.Marble)
		f:Deco("Cistern", 0.8, 2.6, 1.9, 3.6, 1, 1.6, P.White, M.Marble)
		f:Box("Vanity", 3.2, 6, 0, 3.2, -0.1, 1.6, o.vanity or P.Walnut, M.Wood)
		f:Deco("Basin", 3.8, 5.4, 3.2, 3.5, 0.1, 1.2, P.White, M.Marble)
		f:Deco("Mirror", 3.4, 5.8, 4.4, 7.6, 1.45, 1.6, rgb(214, 232, 246), M.Glass, { Reflectance = 0.35 })
	end
	if o.tile then
		f:Deco("Tiles", x0, x1, 0, 7, 1.6, 1.7, o.tile, M.CeramicTiles)
	end
end

-- A fireplace against a wall (its back at +Z): a stone surround, glowing embers, a wooden mantel.
function Kit:Fireplace(x, y, z, yaw, stone, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Fireplace", -4, 4, 0, o.h or 12, -0.8, 1, stone, o.mat or M.Slate)
	f:Deco("Hearth", -4.6, 4.6, 0, 0.5, -2, 1, stone, o.mat or M.Slate)
	f:Deco("Firebox", -2.2, 2.2, 0.5, 3.6, -0.85, 0.4, P.Black, M.SmoothPlastic)
	f:Deco("Embers", -1.6, 1.6, 0.6, 1.4, -0.9, 0.2, rgb(255, 120, 40), M.Neon)
	f:Deco("Mantel", -4.8, 4.8, 5, 5.6, -1.6, 1, o.mantel or P.Walnut, M.Wood)
end

-- An arcade cabinet (its screen faces -Z) with a HIGH SCORE screen in `color`.
function Kit:Arcade(x, y, z, yaw, color)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Arcade", -1.8, 1.8, 0, 8, -1.6, 1.6, rgb(34, 34, 40), M.SmoothPlastic)
	local screen = f:Deco("ArcadeScreen", -1.4, 1.4, 4.4, 7, -1.7, -1.6, rgb(16, 16, 24), M.SmoothPlastic)
	signGui(screen, Enum.NormalId.Front, "HIGH SCORE", "YOU!", color, P.Gold)
	f:Deco("ArcadeButtons", -1.4, 1.4, 3.4, 3.8, -2.4, -1.6, rgb(44, 44, 50), M.SmoothPlastic)
	f:Neon(-1.8, 1.8, 7.6, 8.1, -1.7, -1.6, color)
end

function Kit:PoolTable(x, y, z, yaw, felt)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("PoolTable", -3, 3, 1, 3, -5.4, 5.4, P.Walnut, M.Wood)
	f:Deco("Felt", -2.6, 2.6, 3, 3.1, -5, 5, felt or rgb(30, 110, 70), M.Fabric)
	for _, lx in ipairs({ -2.5, 2.5 }) do
		for _, lz in ipairs({ -4.8, 4.8 }) do
			f:Deco("TableLeg", lx - 0.35, lx + 0.35, 0, 1, lz - 0.35, lz + 0.35, P.Walnut, M.Wood)
		end
	end
	f:Lamp("PoolLamp", -1.2, 1.2, 9.5, 10.2, -3.5, 3.5, P.Warm, 16, 0.5)
end

-- A bar counter w long (the bartender's side at +Z) with stools on -Z and a lit shelf of bottles behind
-- it at +Z + 3 (o.back = false: no back shelf).
function Kit:Counter(x, y, z, yaw, w, wood, top, neon, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Bar", -w / 2, w / 2, 0, 3.8, -1.2, 1.2, wood, M.Wood)
	f:Deco("BarTop", -w / 2 - 0.3, w / 2 + 0.3, 3.8, 4.2, -1.8, 1.4, top, M.Marble)
	if neon then
		f:Neon(-w / 2, w / 2, 0.4, 0.7, -1.3, -1.2, neon)
	end
	local n = math.max(2, math.floor(w / 3))
	for i = 1, n do
		local sx = -w / 2 + w * (i - 0.5) / n
		f:Cyl("Stool", sx, -3, 2.8, 3.2, 1.8, o.stool or P.DarkMetal, M.Leather, DETAIL)
		f:Cyl("StoolLeg", sx, -3, 0, 2.8, 0.35, P.Steel, M.Metal, DETAIL)
	end
	if o.back ~= false then
		f:Deco("BackShelf", -w / 2, w / 2, 4, 4.3, 3, 4.2, wood, M.Wood)
		f:Deco("BackShelf", -w / 2, w / 2, 6.4, 6.7, 3, 4.2, wood, M.Wood)
		local colors = { rgb(120, 60, 30), rgb(40, 110, 60), rgb(200, 180, 120), rgb(80, 40, 90) }
		for i = 0, math.floor(w / 1.2) - 1 do
			local bx = -w / 2 + 0.6 + i * 1.2
			for _, yy in ipairs({ 4.3, 6.7 }) do
				f:Cyl("Bottle", bx, 3.6, yy, yy + 1.6, 0.5, colors[(i + math.floor(yy)) % #colors + 1], M.Glass, DETAIL)
			end
		end
		if neon then
			f:Neon(-w / 2, w / 2, 8.6, 8.9, 3.9, 4.2, neon)
		end
	end
end

-- A grand piano (looks only, its keyboard at -Z) and a bench.
function Kit:Piano(x, y, z, yaw)
	if not self.inside then
		return
	end
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box("Piano", -2.6, 2.6, 2.4, 4, -2.2, 3.8, P.Black, M.SmoothPlastic)
	f:Deco("PianoLid", -2.5, 2.5, 4, 4.2, -1.8, 3.6, P.Black, M.SmoothPlastic, { CFrame = f.cf * CFrame.new(0, 5.6, 1) * CFrame.Angles(math.rad(-25), 0, 0) })
	f:Deco("Keys", -2.4, 2.4, 3.2, 3.5, -3, -2.2, P.White, M.SmoothPlastic)
	for _, lx in ipairs({ -2.2, 2.2 }) do
		f:Deco("PianoLeg", lx - 0.3, lx + 0.3, 0, 2.4, -1.6, -1, P.Black, M.SmoothPlastic)
	end
	f:Deco("PianoLeg", -0.3, 0.3, 0, 2.4, 3, 3.6, P.Black, M.SmoothPlastic)
	f:Box("Bench", -1.6, 1.6, 0, 2, -5.2, -4, P.Black, M.Leather)
end

-- Outdoor furniture (lot and inside) -------------------------------------------------------------------------

function Kit:Lounger(x, y, z, yaw, cushion, frame)
	local f = self:In("Yard"):Sub(x, y, z, yaw)
	f:Box("Lounger", -1.4, 1.4, 0, 1.2, -3.4, 2.4, frame or P.White, M.SmoothPlastic)
	f:Deco("Cushion", -1.3, 1.3, 1.2, 1.5, -3.3, 1.4, cushion, M.Fabric)
	f:Part("Part", "Backrest", Vector3.new(2.6, 0.4, 3.2), f.cf * CFrame.new(0, 2.4, 2.4) * CFrame.Angles(math.rad(40), 0, 0), cushion, M.Fabric, DETAIL)
	if self.inside then
		local s = seatAt(f, 0, 1.6, 0.5, 2.4, 2.4, 3.2)
		s:SetAttribute("ExitAt", (f.cf * CFrame.new(2.8, 3.2, 0)).Position)
	end
end

function Kit:Umbrella(x, y, z, color, d)
	local f = self:In("Yard"):Sub(x, y, z, 0)
	f:Cyl("UmbrellaPole", 0, 0, 0, 8, 0.35, P.White, M.Metal, DETAIL)
	f:Part("Part", "Umbrella", Vector3.new(0.4, d or 8, d or 8), f.cf * CFrame.new(0, 8, 0) * CFrame.Angles(0, 0, math.rad(90)), color, M.Fabric,
		merge(SHADE, { Shape = Enum.PartType.Cylinder }))
end

-- A barrel grill with glowing coals and a side shelf (facing -Z).
function Kit:BBQ(x, y, z, yaw)
	local f = self:In("Yard"):Sub(x, y, z, yaw)
	for _, lx in ipairs({ -1.6, 1.6 }) do
		f:Deco("GrillLeg", lx - 0.2, lx + 0.2, 0, 3, -0.2, 0.2, P.Black, M.Metal)
	end
	f:Pipe("Grill", true, -2.1, 2.1, 3.6, 0, 2.4, P.Black, M.Metal)
	f:Deco("Coals", -1.8, 1.8, 4.6, 4.8, -0.9, 0.9, rgb(255, 110, 40), M.Neon)
	f:Deco("SideShelf", 2.1, 3.8, 3.4, 3.6, -0.8, 0.8, P.Steel, M.Metal)
end

function Kit:FirePit(x, y, z, stone)
	local f = self:In("Yard"):Sub(x, y, z, 0)
	f:Cyl("FirePit", 0, 0, 0, 1.4, 6, stone or rgb(120, 110, 100), M.Slate)
	f:Cyl("Embers", 0, 0, 1.4, 1.5, 4.2, rgb(255, 120, 40), M.Neon, DETAIL)
	f:Ball("Flame", 0, 2, 0, 2.2, rgb(255, 170, 60), M.Neon, merge(DETAIL, { Transparency = 0.35 }))
end

function Kit:Hammock(x, y, z, yaw, color, len)
	len = len or 10
	local f = self:In("Yard"):Sub(x, y, z, yaw)
	for _, s in ipairs({ -1, 1 }) do
		f:Box("HammockPost", s * len / 2 - 0.3, s * len / 2 + 0.3, 0, 6, -0.3, 0.3, P.Walnut, M.Wood)
	end
	f:Deco("Hammock", -len / 2 + 1.5, len / 2 - 1.5, 2.6, 2.9, -1.4, 1.4, color, M.Fabric)
	f:Bar("HammockRope", -len / 2, 5, 0, -len / 2 + 1.5, 2.9, 0, 0.15, P.Cream, M.Fabric)
	f:Bar("HammockRope", len / 2, 5, 0, len / 2 - 1.5, 2.9, 0, 0.15, P.Cream, M.Fabric)
end

-- A string of party bulbs from (x0, y0, z0) to (x1, y1, z1), sagging a little, lit after dark.
function Kit:StringLights(x0, y0, z0, x1, y1, z1, n, color)
	n = n or 8
	local prev
	for i = 0, n do
		local t = i / n
		local x, z = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
		local y = y0 + (y1 - y0) * t - math.sin(t * math.pi) * 1.4
		if prev then
			self:Bar("Wire", prev[1], prev[2], prev[3], x, y, z, 0.08, P.Black, M.SmoothPlastic)
		end
		if i > 0 and i < n then
			self:Lamp("Bulb", x - 0.25, x + 0.25, y - 0.6, y - 0.1, z - 0.25, z + 0.25, color or P.Warm)
		end
		prev = { x, y, z }
	end
end

-- Gameplay pieces --------------------------------------------------------------------------------------------

-- The front door: a panel w x h in the doorway whose bottom middle is the lot's Door spot (Config.Housing,
-- on the front wall's outer face), facing the street (-Z), `th` = the wall's thickness, in a casing,
-- with a narrow glass light and a brass knob. Lot: HousingService puts the HomeDoor prompt on it. Inside:
-- the same door is the way out (LeavePrompt), with a lit EXIT sign over it on the room side. o.at puts
-- it somewhere else (a penthouse's way out is its elevator), o.glass = false leaves the glass light out.
function Kit:FrontDoor(w, h, th, color, material, casing, casingMat, o)
	o = o or {}
	local d = o.at or self.door
	local x, y, z = d.X, d.Y, d.Z
	local door = self:Box("FrontDoor", x - w / 2, x + w / 2, y, y + h, z - 0.3, z + th, color, material)
	self:Deco("DoorFrame", x - w / 2 - 0.8, x - w / 2, y, y + h + 0.8, z - 0.5, z + th + 0.1, casing, casingMat)
	self:Deco("DoorFrame", x + w / 2, x + w / 2 + 0.8, y, y + h + 0.8, z - 0.5, z + th + 0.1, casing, casingMat)
	self:Deco("DoorFrame", x - w / 2, x + w / 2, y + h, y + h + 0.8, z - 0.5, z + th + 0.1, casing, casingMat)
	if o.glass ~= false then
		self:Deco("DoorGlass", x - w / 2 + 1.1, x - w / 2 + 1.9, y + 2.2, y + h - 1.6, z - 0.4, z - 0.3, P.Glass, M.Glass, { Reflectance = 0.1 })
	end
	self:Deco("Knob", x + w / 2 - 1.2, x + w / 2 - 0.6, y + 4.6, y + 5.2, z - 0.6, z - 0.3, P.Brass, M.Metal)
	if self.inside then
		self:Deco("Knob", x + w / 2 - 1.2, x + w / 2 - 0.6, y + 4.6, y + 5.2, z + th, z + th + 0.3, P.Brass, M.Metal)
		local sign = self:Box("ExitSign", x - 1.6, x + 1.6, y + h + 1.2, y + h + 2.4, z + th, z + th + 0.2, rgb(20, 110, 60), M.SmoothPlastic, DETAIL)
		signGui(sign, Enum.NormalId.Back, "EXIT", nil, Color3.new(1, 1, 1), nil, 30)
		self.out.exit = door
	else
		self.out.door = door
	end
	return door
end

-- Where the owner appears inside: (x, z) on a floor at y, facing `yaw` degrees (0 = the street side).
function Kit:Spawn(x, y, z, yaw)
	self.out.spawn = self.cf * CFrame.new(x, y + 3.5, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

-- A parking bay (inside only): a 12 x 18 concrete pad on the floor at y, its centre (x, z), the car's
-- nose toward -Z of the bay's own frame (yaw), white side lines on top, EMPTY BAY painted on it.
function Kit:Bay(x, y, z, yaw)
	if not self.inside then
		return
	end
	local f = self:In("Garage"):Sub(x, y, z, yaw)
	local pad = f:Box("Bay", -6, 6, 0, 0.06, -9, 9, rgb(100, 100, 100), M.Concrete)
	f:Deco("BayLine", -6, -5.7, 0.06, 0.08, -9, 9, rgb(232, 232, 226), M.SmoothPlastic)
	f:Deco("BayLine", 5.7, 6, 0.06, 0.08, -9, 9, rgb(232, 232, 226), M.SmoothPlastic)
	local text = signGui(pad, Enum.NormalId.Top, "EMPTY BAY", nil, rgb(200, 200, 196))
	text.Parent.Enabled = not self.show
	table.insert(self.out.bays, { cf = f.cf * CFrame.new(0, 0.06, 0), pad = pad })
	return pad
end

-- The garage sign (inside): "MY GARAGE" over the count (HousingService fills the sub line), or on a show
-- copy "GARAGE" over "Room for N cars". On this frame's -Z face at (x, y, z), w x h.
function Kit:GarageSign(x, y, z, yaw, w, h)
	if not self.inside then
		return
	end
	local f = self:In("Garage"):Sub(x, y, z, yaw)
	local n = self.home.GarageSlots
	local board = f:Box("GarageSign", -w / 2, w / 2, -h / 2, h / 2, -0.2, 0.2, P.Dark, M.Metal, DETAIL)
	local title, sub = signGui(board, Enum.NormalId.Front, self.show and "GARAGE" or "MY GARAGE",
		self.show and string.format("Room for %d cars", n) or "", self.home.Theme, P.White)
	f:Neon(-w / 2, w / 2, h / 2, h / 2 + 0.25, -0.2, 0.2, self.home.Theme)
	self.out.garageTitle, self.out.signSub = title, sub
end

-- The wardrobe (inside): an oak closet with two painted doors and hat boxes on top, its back at +Z of
-- its own frame (yaw), a mirror in a lit frame (after dark) beside it (on +X, or -X with o.mirror = -1),
-- a WARDROBE sign above and a mat in front. o.w = the closet's width (10). Keep it 12 studs from the exit
-- door and the garage bays (their prompts use E too) and leave room in front for WardrobeUI's camera.
-- HousingService adds the "Change look" prompt (never on a show copy).
function Kit:Closet(x, y, z, yaw, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	local oak, door = P.Oak, rgb(226, 222, 214)
	local w = (o.w or 10) / 2
	local closet = f:Box("Wardrobe", -w, w, 0, 11, -1.5, 1.5, oak, M.WoodPlanks)
	f:Deco("ClosetDoor", -w + 0.3, -0.1, 0.4, 10.6, -1.7, -1.5, door, M.WoodPlanks)
	f:Deco("ClosetDoor", 0.1, w - 0.3, 0.4, 10.6, -1.7, -1.5, door, M.WoodPlanks)
	f:Deco("Knob", -0.6, -0.2, 5, 6.2, -2, -1.7, P.Brass, M.Metal)
	f:Deco("Knob", 0.2, 0.6, 5, 6.2, -2, -1.7, P.Brass, M.Metal)
	f:Neon(-w, w, 10.6, 11, -1.8, -1.5, P.Warm)
	f:Cyl("HatBox", -w / 2, 0, 11, 12.6, 2.4, rgb(226, 214, 190), M.Fabric, DETAIL)
	f:Cyl("HatBox", w / 2, 0, 11, 12.2, 2, self.home.Theme:Lerp(rgb(120, 116, 110), 0.45), M.Fabric, DETAIL)
	local side = o.mirror or 1
	local m0, m1 = w + 1, w + 5
	if side < 0 then
		m0, m1 = -w - 5, -w - 1
	end
	f:Deco("Mirror", m0, m1, 1.2, 10.2, 1.2, 1.5, rgb(214, 232, 246), M.Glass, { Reflectance = 0.35 })
	f:Neon(m0 - 0.4, m1 + 0.4, 0.8, 1.2, 1.1, 1.5, P.Warm)
	f:Neon(m0 - 0.4, m1 + 0.4, 10.2, 10.6, 1.1, 1.5, P.Warm)
	f:Neon(m0 - 0.4, m0, 1.2, 10.2, 1.1, 1.5, P.Warm)
	f:Neon(m1, m1 + 0.4, 1.2, 10.2, 1.1, 1.5, P.Warm)
	local sign = f:Box("WardrobeSign", math.min(-w, m0), math.max(w, m1), 12.8, 15.4, 1.3, 1.5, P.Dark, M.Metal, DETAIL)
	signGui(sign, Enum.NormalId.Front, "WARDROBE", nil, self.home.Theme)
	f:Deco("WardrobeMat", -w + 1, w - 1, 0, 0.1, -7, -2, rgb(88, 80, 72), M.Fabric)
	self.out.closet = closet
	return closet
end

-- A show copy's FOR SALE stand at (x, z) on a floor at y, facing (fx, fz) (its "Buy this home" prompt
-- opens the buy card: HousingService), and the "Your cars park here" sign in the garage.
function Kit:SaleStand(x, y, z, fx, fz)
	if not (self.inside and self.show) then
		return
	end
	local f = self:In("ForSale")
	f.cf = self.cf * CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(fx, y, fz))
	local board = f:Stand(6, 3.6, 3.4, "FOR SALE", HouseBuilder.Money(self.home.Price), P.Gold, self.home.Theme, true)
	self.out.saleBoard = board
	self.out.saleAt = (f.cf * CFrame.new(0, 3, 0)).Position
end
function Kit:ParkStand(x, y, z, fx, fz)
	if not (self.inside and self.show) then
		return
	end
	local f = self:In("ForSale")
	f.cf = self.cf * CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(fx, y, fz))
	f:Stand(5, 2.4, 2, "YOUR CARS PARK HERE", string.format("%d bays", self.home.GarageSlots), self.home.Theme, self.home.Theme)
end

-- Invisible walls (inside): a ring round x0..x1, z0..z1 from y0 up to y1, so nobody walks or jumps off
-- the owner's copy.
function Kit:Bounds(x0, x1, z0, z1, y0, y1)
	if not self.inside then
		return
	end
	local f = self:In("Bounds")
	f:Box("Bound", x0 - 1, x1 + 1, y0, y1, z0 - 1, z0, P.White, M.SmoothPlastic, GHOST)
	f:Box("Bound", x0 - 1, x1 + 1, y0, y1, z1, z1 + 1, P.White, M.SmoothPlastic, GHOST)
	f:Box("Bound", x0 - 1, x0, y0, y1, z0, z1, P.White, M.SmoothPlastic, GHOST)
	f:Box("Bound", x1, x1 + 1, y0, y1, z0, z1, P.White, M.SmoothPlastic, GHOST)
end

-- The neighbourhood round the owner's copy (inside only), so the windows look out on something: the
-- ground past the lot, the street out front, and per `kind` ("suburb", "docks", "city", "marina", "beach")
-- a few neighbours, water or towers. Lot space, with the lot's own ground (x -60..60, z -40..40) left to
-- the style module. Looks only (no collisions), except the ground.
function Kit:Backdrop(kind, o)
	if not self.inside then
		return
	end
	o = o or {}
	local f = self:In("Backdrop")
	local ground = o.ground or (kind == "beach" and P.Sand) or ((kind == "docks" or kind == "city") and rgb(150, 148, 142)) or P.Lawn
	local gmat = (kind == "beach" and M.Sand) or ((kind == "docks" or kind == "city") and M.Concrete) or M.Grass
	-- Ground round the lot, then the far ground out to the horizon (haze hides the edge).
	f:Box("Ground", -600, 600, -1, 0, -600, -40, ground, gmat)
	f:Box("Ground", -600, 600, -1, 0, 40, 600, ground, gmat)
	f:Box("Ground", -600, -60, -1, 0, -40, 40, ground, gmat)
	f:Box("Ground", 60, 600, -1, 0, -40, 40, ground, gmat)
	-- The street in front: sidewalk, kerb, asphalt with a centre line, and street lamps (lit after dark).
	if kind ~= "city" then
		f:Deco("Sidewalk", -600, 600, 0, 0.3, -58, -44, P.Paving, M.Pavement)
		f:Deco("Kerb", -600, 600, 0, 0.4, -59, -58, P.Concrete, M.Concrete)
		f:Deco("Road", -600, 600, 0, 0.12, -90, -59, P.Asphalt, M.Asphalt)
		f:Deco("Line", -600, 600, 0.12, 0.14, -75, -74.4, rgb(214, 170, 60), M.SmoothPlastic)
		f:Deco("Kerb", -600, 600, 0, 0.4, -91, -90, P.Concrete, M.Concrete)
		f:Deco("Sidewalk", -600, 600, 0, 0.3, -104, -91, P.Paving, M.Pavement)
		for _, x in ipairs({ -150, -70, 10, 90, 170 }) do
			f:Deco("LampPost", x - 0.4, x + 0.4, 0, 16, -56.4, -55.6, P.DarkMetal, M.Metal)
			f:Deco("LampArm", x - 0.3, x + 0.3, 15.5, 16, -60, -55.6, P.DarkMetal, M.Metal)
			f:Lamp("StreetLamp", x - 0.8, x + 0.8, 15, 15.5, -61, -59, P.Warm)
		end
	end
	local rng = Random.new(#kind * 31 + self.home.Price % 101)
	-- A house shape: a box of wall with a pitched or flat roof and two dark windows (looks only).
	local function neighbour(cx, cz, w, d, h, wall, roof, flat)
		f:Shade("Neighbour", cx - w / 2, cx + w / 2, 0, h, cz - d / 2, cz + d / 2, wall, M.Plaster)
		if flat then
			f:Shade("NeighbourRoof", cx - w / 2 - 0.6, cx + w / 2 + 0.6, h, h + 0.8, cz - d / 2 - 0.6, cz + d / 2 + 0.6, roof, M.Concrete)
		else
			f:Wedge("NeighbourRoof", cx - w / 2 - 1, cx + w / 2 + 1, h, h + d * 0.28, cz - d / 2 - 1, cz, roof, M.ClayRoofTiles, "-Z", SHADE)
			f:Wedge("NeighbourRoof", cx - w / 2 - 1, cx + w / 2 + 1, h, h + d * 0.28, cz, cz + d / 2 + 1, roof, M.ClayRoofTiles, "+Z", SHADE)
		end
		for _, s in ipairs({ -1, 1 }) do
			f:Deco("NeighbourWindow", cx + s * w / 4 - 2.5, cx + s * w / 4 + 2.5, h * 0.35, h * 0.35 + 5, cz - d / 2 - 0.2, cz - d / 2, P.Glass, M.Glass)
		end
	end
	local pastel = { rgb(232, 214, 190), rgb(206, 222, 214), rgb(236, 206, 196), rgb(220, 214, 232), rgb(238, 226, 196) }
	if kind == "suburb" or kind == "marina" or kind == "beach" then
		for i, spot in ipairs({ { -100, 0 }, { 100, 0 }, { -100, 90 }, { 0, 100 }, { 100, 90 }, { -40, -140 }, { 60, -140 }, { -150, -140 } }) do
			-- (By the marina or the beach the back stays open: nothing between the yard and the water.)
			if not (o.open and o.open(spot[1], spot[2])) and not (kind ~= "suburb" and spot[2] > 40) then
				local w, d = rng:NextNumber(36, 54), rng:NextNumber(30, 40)
				neighbour(spot[1], spot[2], w, d, (i % 3 == 0) and 24 or 13, pastel[i % #pastel + 1], P.Tile:Lerp(rgb(150, 140, 130), (i % 2) * 0.4), kind == "beach" and i % 2 == 0)
			end
		end
		for _, p in ipairs({ { -70, -36 }, { 72, -38 }, { -72, 44 }, { 76, 46 }, { -130, 50 }, { 140, 30 } }) do
			if not (o.open and o.open(p[1], p[2])) then
				f:Palm(p[1], p[2], rng:NextNumber(18, 24))
			end
		end
	end
	if kind == "docks" then
		for _, b in ipairs({ { -110, 10, 60, 50, 30 }, { 110, 0, 60, 46, 26 }, { -20, 120, 120, 40, 34 }, { -40, -150, 90, 40, 28 }, { 80, -150, 70, 40, 22 } }) do
			f:Shade("Warehouse", b[1] - b[3] / 2, b[1] + b[3] / 2, 0, b[5], b[2] - b[4] / 2, b[2] + b[4] / 2, rgb(140, 82, 64), M.Brick)
			f:Shade("WarehouseRoof", b[1] - b[3] / 2 - 0.5, b[1] + b[3] / 2 + 0.5, b[5], b[5] + 1, b[2] - b[4] / 2 - 0.5, b[2] + b[4] / 2 + 0.5, rgb(70, 68, 72), M.Metal)
		end
		-- The harbour behind the warehouses, a crane and a stack of containers.
		f:Deco("Harbour", -600, 600, 0.2, 0.3, 160, 600, P.Sea, M.Glass, { Transparency = 0.1, Reflectance = 0.15 })
		local crane = rgb(196, 120, 40)
		f:Shade("CraneLeg", 58, 62, 0, 60, 150, 154, crane, M.Metal)
		f:Shade("CraneLeg", 78, 82, 0, 60, 150, 154, crane, M.Metal)
		f:Shade("CraneBoom", 40, 100, 60, 64, 140, 190, crane, M.Metal)
		local cols = { rgb(170, 60, 50), rgb(40, 90, 140), rgb(60, 120, 80), rgb(200, 150, 40) }
		for i = 0, 5 do
			f:Shade("Container", 120 + (i % 3) * 13, 132 + (i % 3) * 13, (i >= 3 and 8 or 0), (i >= 3 and 16 or 8), 60, 84, cols[i % 4 + 1], M.CorrodedMetal)
		end
	end
	if kind == "marina" then
		-- The quay just past the back wall, the water and the jetties with their yachts.
		f:Deco("Marina", -600, 600, 0.2, 0.3, 58, 600, P.Sea, M.Glass, { Transparency = 0.1, Reflectance = 0.15 })
		f:Deco("Quay", -600, 600, 0, 0.5, 42, 58, P.Paving, M.Limestone)
		for i, x in ipairs({ -60, 10, 80 }) do
			f:Deco("Jetty", x - 3, x + 3, 0.2, 0.9, 58, 108, rgb(150, 112, 78), M.WoodPlanks)
			if not f:Asset("Yacht", x + 14, 88, 0.9, 180 + i * 4, -2) then
				f:Shade("Boat", x + 8, x + 20, 0.3, 4, 70, 106, P.White, M.SmoothPlastic)
			end
		end
	end
	if kind == "beach" then
		f:Deco("Sea", -600, 600, 0.05, 0.15, 110, 600, P.Sea, M.Glass, { Transparency = 0.1, Reflectance = 0.15 })
		f:Deco("Surf", -600, 600, 0.1, 0.2, 104, 110, rgb(220, 236, 236), M.SmoothPlastic, { Transparency = 0.3 })
		for _, x in ipairs({ -80, 70, 140 }) do
			self:In("Backdrop"):Umbrella(x, 0, 80, ({ rgb(236, 120, 150), rgb(60, 170, 190), rgb(240, 200, 80) })[(x % 3) + 1])
		end
	end
	if kind == "city" then
		-- Towers all round (the penthouse is up at o.level): glass and stucco, lit windows after dark.
		local towerCols = { rgb(196, 190, 210), rgb(214, 204, 186), rgb(170, 186, 196), rgb(222, 210, 214), rgb(150, 160, 172) }
		local spots = {
			{ -150, -40, 60, 50, 110 }, { -140, 60, 50, 60, 140 }, { -40, 150, 70, 50, 120 }, { 70, 150, 50, 50, 96 },
			{ 160, 60, 60, 50, 150 }, { 150, -60, 50, 60, 104 }, { -60, -170, 60, 50, 90 }, { 70, -180, 70, 50, 128 },
			{ -260, -160, 70, 70, 170 }, { 260, 160, 80, 70, 180 }, { 270, -120, 60, 60, 120 }, { -270, 140, 60, 60, 130 },
		}
		for i, t in ipairs(spots) do
			local cx, cz, w, d, h = t[1], t[2], t[3], t[4], t[5]
			f:Shade("Tower", cx - w / 2, cx + w / 2, 0, h, cz - d / 2, cz + d / 2, towerCols[i % #towerCols + 1], i % 2 == 0 and M.Glass or M.Plaster,
				i % 2 == 0 and { Reflectance = 0.15 } or nil)
			f:Shade("TowerTop", cx - w / 2 + 3, cx + w / 2 - 3, h, h + 3, cz - d / 2 + 3, cz + d / 2 - 3, rgb(120, 120, 126), M.Concrete)
			-- Window bands on the face toward the penthouse, some lit after dark.
			local face = (math.abs(cx) > math.abs(cz)) and (cx > 0 and "-X" or "+X") or (cz > 0 and "-Z" or "+Z")
			for k = 1, math.floor(h / 14) - 1 do
				local y0 = k * 14 - 5
				local band
				if face == "-X" then
					band = f:Deco("TowerWindows", cx - w / 2 - 0.2, cx - w / 2, y0, y0 + 5, cz - d / 2 + 4, cz + d / 2 - 4, P.Glass, M.Glass)
				elseif face == "+X" then
					band = f:Deco("TowerWindows", cx + w / 2, cx + w / 2 + 0.2, y0, y0 + 5, cz - d / 2 + 4, cz + d / 2 - 4, P.Glass, M.Glass)
				elseif face == "-Z" then
					band = f:Deco("TowerWindows", cx - w / 2 + 4, cx + w / 2 - 4, y0, y0 + 5, cz - d / 2 - 0.2, cz - d / 2, P.Glass, M.Glass)
				else
					band = f:Deco("TowerWindows", cx - w / 2 + 4, cx + w / 2 - 4, y0, y0 + 5, cz + d / 2, cz + d / 2 + 0.2, P.Glass, M.Glass)
				end
				if band and litAt(i * 5 + k) then
					nightNeon(band, P.RoomGlow:Lerp(rgb(255, 236, 200), (k % 3) * 0.2))
				end
			end
			if i % 3 == 0 then
				f:Neon(cx - w / 2, cx + w / 2, h + 3, h + 3.6, cz - d / 2, cz - d / 2 + 0.6, ({ rgb(34, 225, 255), rgb(255, 62, 165), rgb(255, 214, 10) })[i % 3 + 1])
			end
		end
		-- Streets far below.
		for _, x in ipairs({ -95, 95 }) do
			f:Deco("Road", x - 14, x + 14, 0, 0.2, -600, 600, P.Asphalt, M.Asphalt)
		end
		for _, z in ipairs({ -105, 95 }) do
			f:Deco("Road", -600, 600, 0, 0.25, z - 14, z + 14, P.Asphalt, M.Asphalt)
		end
		f:Deco("Sea", 330, 900, 0.1, 0.3, -600, 600, P.Sea, M.Glass, { Transparency = 0.1, Reflectance = 0.15 })
	end
end

-- Building ---------------------------------------------------------------------------------------------------

local styles = {}
local function styleOf(name)
	if styles[name] == nil then
		local folder = script.Parent:FindFirstChild("Houses")
		local module = folder and folder:FindFirstChild(name)
		local ok, fn = false, nil
		if module then
			ok, fn = pcall(require, module)
			if not ok then
				warn("[HouseBuilder] couldn't load house style " .. name .. ": " .. tostring(fn))
			end
		end
		styles[name] = (ok and type(fn) == "function") and fn or false
	end
	return styles[name] or nil
end

-- Does this home have a build of its own? (HousingService keeps its old Classic shell for any that don't.)
function HouseBuilder.Has(home)
	return styleOf(home.Style or "") ~= nil
end

local function build(home, frame, mode, model, opts)
	local fn = styleOf(home.Style or "")
	assert(fn, "no house style " .. tostring(home.Style))
	local k = newKit(model, frame, mode, home, opts)
	k.door = (home.Layout and home.Layout.Door) or Vector3.new(-18, 0, -10)
	fn(k:In("Shell"), home)
	local out = k.out
	out.parts, out.lights = k.stats.parts, k.stats.lights
	return out, k
end

-- The house on its lot (Workspace.Homes.Home_<Id>, attribute HomeId), parented to `parent`. out.door is
-- the front door part (it must exist: the HomeDoor prompt goes on it) and out.sign the street sign.
function HouseBuilder.Lot(home, parent)
	local model = Instance.new("Model")
	model.Name = "Home_" .. home.Id
	model:SetAttribute("HomeId", home.Id)
	local frame = CFrame.lookAt(home.Position, home.Position + home.Facing)
	local out = build(home, frame, "Lot", model)
	assert(out.door, home.Id .. ": no front door")
	model.PrimaryPart = out.ground or out.door
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the whole house streams in at once
	end)
	model.Parent = parent
	return out
end

-- The owner's (or a visitor's show) copy at `frame` (no turn: lot space = world axes there, so pool water
-- lines up with the 4-stud grid when the frame's origin is on it). opts.show, opts.ownerId. Not parented:
-- HousingService parents it, adds the prompts and fills the water.
function HouseBuilder.Inside(home, frame, opts)
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = "Home_" .. tostring(opts.ownerId or 0)
	model:SetAttribute("OwnerUserId", opts.ownerId)
	model:SetAttribute("HomeId", home.Id)
	model:SetAttribute("Show", opts.show or nil)
	local out, k = build(home, frame, "Inside", model, opts)
	assert(out.exit, home.Id .. ": no way out")
	assert(out.spawn, home.Id .. ": no spawn")
	assert(#out.bays == home.GarageSlots, string.format("%s: %d bays for %d cars", home.Id, #out.bays, home.GarageSlots))
	local cars = Instance.new("Folder")
	cars.Name = "GarageCars"
	cars.Parent = model
	out.cars = cars
	model.PrimaryPart = out.ground or out.exit
	out.kit = k
	return out
end

return HouseBuilder
