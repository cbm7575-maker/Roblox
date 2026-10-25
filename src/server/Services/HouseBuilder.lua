-- HouseBuilder (ModuleScript, ServerScriptService.Services.HouseBuilder)
-- Builds the buyable houses (Config.Properties) from parts at server start. PropertyService calls
-- HouseBuilder.Build(def, folder) once per property; the style module named by def.Style
-- (ServerScriptService.Services.Houses.<Style>) lays the house out with the Kit below.
--
-- Kit coordinates: every house is drawn in its lot's own frame. Origin = the lot centre on the
-- ground (y = 0 is the land surface), -Z = the front (toward the street), +Y up. Kit:Sub(x, y, z, yaw)
-- makes a child frame (furniture is drawn in its own frame, its front facing -Z).
-- Heights used by every style: driveway and garage floors top out at 0.5 (flush with the roads),
-- ground floors at 1 (one 0.5 step up), storeys 13 apart, stairs rise 1 stud a step or less.
--
-- Rules the kit enforces: everything anchored and CanTouch off; decoration never collides or
-- answers raycasts; only walls, floors, roofs, stairs and big furniture collide; small parts never
-- cast shadows; at most MAX_LIGHTS PointLights a house, Shadows off.
--
-- Build(def, parent) returns a table:
--   model      the house Model (Workspace.Properties.<Id>), attribute PropId
--   door       CFrame on the front door's floor, LookVector = out (the street side)
--   blocker    the front door's invisible blocker (see "owner-open parts")
--   spawn      CFrame for a character's HumanoidRootPart in the living room
--   bays       { CFrame } garage bay floor centres, LookVector = out through the garage door
--   pad        the BankPad part (in the garage); pads = every BankPad (the Mansion has two)
--   sign       the FOR SALE board (BasePart); labels = { TextLabel "Status" }, owners = { TextLabel "Owners" }
--   center     Vector3, the lot centre
--   parts      number of BaseParts built
-- Owner-open parts (HouseClient opens them on owners' screens only; the server keeps them shut):
--   attribute OwnerOpen = true. A part that collides (door blockers, garage doors, gates) stops
--   colliding for owners; one with ClosedCF / OpenCF (CFrame attributes) also moves to OpenCF.
--   Parts named "InsideZone" (invisible boxes) mark the inside of the house: a player standing in
--   one always gets the doors open, so nobody is ever shut in.
-- Pools use Terrain water (Workspace.Terrain:FillBlock) inside raised basins; water blocks sit on
-- the 4-stud voxel grid (lots are centred on multiples of 4 and pools drawn on multiples of 4).

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local HouseBuilder = {}

HouseBuilder.MAX_LIGHTS = 6
HouseBuilder.Budget = { S = 250, M = 350, L = 500, XL = 700, Mansion = 900 }

local M = Enum.Material
HouseBuilder.M = M

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end
HouseBuilder.rgb = rgb

-- Shared colours (styles bring their own palettes on top).
local C = {
	White = rgb(245, 245, 240),
	Black = rgb(22, 22, 26),
	Glass = rgb(150, 200, 225),
	DarkGlass = rgb(40, 56, 84),
	Wood = rgb(150, 110, 70),
	DarkWood = rgb(96, 70, 48),
	LightWood = rgb(205, 170, 120),
	Concrete = rgb(196, 190, 186),
	Asphalt = rgb(70, 70, 78),
	Steel = rgb(120, 128, 140),
	Leaf = rgb(70, 170, 90),
	Grass = rgb(110, 180, 90),
	Water = rgb(60, 170, 220),
	Pool = rgb(70, 190, 230),
	Warm = rgb(255, 214, 160),
	Gold = rgb(212, 175, 55),
}
HouseBuilder.C = C

local Kit = {}
Kit.__index = Kit

-- "$1,200,000"
function HouseBuilder.Money(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end

local function newKit(model, cf, seed)
	local k = setmetatable({}, Kit)
	k.model = model
	k.parent = model
	k.cf = cf
	k.root = cf
	k.stats = { parts = 0, lights = 0 }
	k.out = { bays = {}, water = {}, zones = {} }
	k.rng = Random.new(seed)
	return k
end
-- Other builders (WeaponService's gun store) draw with the same kit: NewKit(model, lotCFrame, seed).
HouseBuilder.NewKit = newKit

-- A child frame at (x, y, z), turned `yaw` degrees (its -Z is the new front).
function Kit:Sub(x, y, z, yaw)
	local k = setmetatable({}, Kit)
	for key, v in pairs(self) do
		k[key] = v
	end
	k.cf = self.cf * CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	return k
end

-- The same frame, but new parts go into a Folder named `name` (made once per house).
function Kit:In(name)
	local k = setmetatable({}, Kit)
	for key, v in pairs(self) do
		k[key] = v
	end
	local f = self.model:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = self.model
	end
	k.parent = f
	return k
end

function Kit:World(x, y, z)
	return self.cf * CFrame.new(x, y, z)
end

-- Core part maker. size, centre (x, y, z) in this frame. o (all optional):
--   n name, c collide (default false), q CanQuery (default = c), t transparency, s cast shadow,
--   shape "Cylinder" | "Ball", wedge (WedgePart), rot (extra CFrame rotation), refl reflectance.
function Kit:Part(size, x, y, z, color, mat, o)
	o = o or {}
	local p = Instance.new(o.wedge and "WedgePart" or "Part")
	p.Name = o.n or "Part"
	p.Anchored = true
	p.Size = size
	local cf = self.cf * CFrame.new(x, y, z)
	if o.rot then
		cf = cf * o.rot
	end
	p.CFrame = cf
	p.Color = color or C.White
	p.Material = mat or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.shape == "Cylinder" then
		p.Shape = Enum.PartType.Cylinder
	elseif o.shape == "Ball" then
		p.Shape = Enum.PartType.Ball
	end
	local collide = o.c == true
	p.CanCollide = collide
	p.CanTouch = false
	if o.q ~= nil then
		p.CanQuery = o.q
	else
		p.CanQuery = collide
	end
	p.Transparency = o.t or 0
	if o.refl then
		p.Reflectance = o.refl
	end
	-- Only big solid shapes (walls, roofs) cast shadows; furniture and trim never do.
	local big = math.max(size.X, size.Y, size.Z)
	p.CastShadow = o.s == true or (o.s == nil and collide and big >= 10 and (o.t or 0) < 0.5)
	p.Parent = self.parent
	self.stats.parts += 1
	return p
end

-- Box between two corners (any order) in this frame.
function Kit:Box(x0, y0, z0, x1, y1, z1, color, mat, o)
	local ax, bx = math.min(x0, x1), math.max(x0, x1)
	local ay, by = math.min(y0, y1), math.max(y0, y1)
	local az, bz = math.min(z0, z1), math.max(z0, z1)
	return self:Part(Vector3.new(bx - ax, by - ay, bz - az), (ax + bx) / 2, (ay + by) / 2, (az + bz) / 2, color, mat, o)
end

-- A collidable box (walls, floors, steps): you walk on it or into it.
function Kit:Solid(x0, y0, z0, x1, y1, z1, color, mat, o)
	o = o or {}
	o.c = true
	return self:Box(x0, y0, z0, x1, y1, z1, color, mat, o)
end

-- Cylinder standing upright (Roblox cylinders run along X, so it is turned on its side).
function Kit:Post(x, y0, z, y1, d, color, mat, o)
	o = o or {}
	o.shape = "Cylinder"
	o.rot = CFrame.Angles(0, 0, math.rad(90))
	return self:Part(Vector3.new(y1 - y0, d, d), x, (y0 + y1) / 2, z, color, mat, o)
end

-- Flat disc (a cylinder lying flat): rugs, tables, trampolines.
function Kit:Disc(x, y, z, d, h, color, mat, o)
	return self:Post(x, y, z, y + h, d, color, mat, o)
end

function Kit:Ball(x, y, z, d, color, mat, o)
	o = o or {}
	o.shape = "Ball"
	return self:Part(Vector3.new(d, d, d), x, y, z, color, mat, o)
end

-- WedgePart: its low edge faces this frame's -Z after turning `yaw` degrees (Roblox wedges rise
-- from the front to the back).
function Kit:Wedge(sx, sy, sz, x, y, z, yaw, color, mat, o)
	o = o or {}
	o.wedge = true
	o.rot = CFrame.Angles(0, math.rad(yaw or 0), 0) * (o.rot or CFrame.new())
	return self:Part(Vector3.new(sx, sy, sz), x, y, z, color, mat, o)
end

-- Walls ------------------------------------------------------------------------------------------------

-- A straight wall along X or Z from (x0, z0) to (x1, z1), from height y0 to y1, `th` thick (centred
-- on the line). holes: list of { a, b, lo, hi, glass = colour or true, n = name, mull = bars }, with
-- a..b measured along the wall from its start and lo..hi as heights. Glass holes get a pane that
-- collides; the rest are open doorways. o.trim = colour adds a sill under each window.
function Kit:Wall(x0, z0, x1, z1, y0, y1, th, color, mat, holes, o)
	o = o or {}
	local alongX = math.abs(z1 - z0) < 0.01
	local len = alongX and math.abs(x1 - x0) or math.abs(z1 - z0)
	local dir = alongX and (x1 >= x0 and 1 or -1) or (z1 >= z0 and 1 or -1)
	local h2 = th / 2
	local function seg(a, b, lo, hi, col, m, opts)
		if b - a < 0.05 or hi - lo < 0.05 then
			return nil
		end
		if alongX then
			return self:Box(x0 + dir * a, lo, z0 - h2, x0 + dir * b, hi, z0 + h2, col, m, opts)
		end
		return self:Box(x0 - h2, lo, z0 + dir * a, x0 + h2, hi, z0 + dir * b, col, m, opts)
	end
	local list = {}
	for _, hole in ipairs(holes or {}) do
		table.insert(list, hole)
	end
	table.sort(list, function(p, q)
		return p[1] < q[1]
	end)
	local wallOpts = { c = true, n = o.n or "Wall", s = o.s }
	-- The solid part of the wall is cut into as few boxes as possible: split it into horizontal
	-- bands at every hole's top and bottom, find the solid stretches of each band, and stack bands
	-- whose stretches match into one box.
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
			local free, cursor = {}, 0
			for _, hole in ipairs(list) do
				if hole[3] < mid and hole[4] > mid then
					if hole[1] > cursor then
						table.insert(free, { cursor, hole[1] })
					end
					cursor = math.max(cursor, hole[2])
				end
			end
			if cursor < len then
				table.insert(free, { cursor, len })
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
			seg(iv[1], iv[2], row.lo, row.hi, color, mat, wallOpts)
		end
	end
	for _, hole in ipairs(list) do
		local a, b, lo, hi = hole[1], hole[2], hole[3], hole[4]
		if hole.glass then
			local g = hole.glass == true and C.Glass or hole.glass
			local pane = th * 0.3
			if alongX then
				self:Box(x0 + dir * a, lo, z0 - pane / 2, x0 + dir * b, hi, z0 + pane / 2, g, M.Glass,
					{ c = true, q = false, t = hole.t or 0.55, n = "Window" })
			else
				self:Box(x0 - pane / 2, lo, z0 + dir * a, x0 + pane / 2, hi, z0 + dir * b, g, M.Glass,
					{ c = true, q = false, t = hole.t or 0.55, n = "Window" })
			end
			-- Mullions: thin bars across factory and French windows.
			local bars = hole.mull or 0
			for i = 1, bars do
				local m = a + (b - a) * i / (bars + 1)
				seg(m - 0.15, m + 0.15, lo, hi, o.frame or C.Black, M.Metal, { n = "Mullion", s = false })
			end
			if o.trim and lo > y0 + 0.5 then
				local out = th / 2 + 0.25
				if alongX then
					self:Box(x0 + dir * (a - 0.3), lo - 0.4, z0 - out, x0 + dir * (b + 0.3), lo, z0 + out, o.trim, M.SmoothPlastic, { n = "Sill" })
				else
					self:Box(x0 - out, lo - 0.4, z0 + dir * (a - 0.3), x0 + out, lo, z0 + dir * (b + 0.3), o.trim, M.SmoothPlastic, { n = "Sill" })
				end
			end
		end
	end
end

-- Four walls round the room (x0, z0)-(x1, z1) with tidy corners. holes = { front = {...}, back = {...},
-- left = {...}, right = {...} } (Wall holes): front is the z0 wall and back the z1 wall, both measured
-- from x0; left is the x0 wall and right the x1 wall, both measured from z0. false leaves a side out.
function Kit:Walls4(x0, z0, x1, z1, y0, y1, th, color, mat, holes, o)
	holes = holes or {}
	local h2 = th / 2
	local function shift(list, d)
		local out = {}
		for i, hole in ipairs(list or {}) do
			local c = table.clone(hole)
			c[1], c[2] = hole[1] + d, hole[2] + d
			out[i] = c
		end
		return out
	end
	-- A side set to false is left out (it is another building's wall).
	if holes.front ~= false then
		self:Wall(x0 - h2, z0, x1 + h2, z0, y0, y1, th, color, mat, shift(holes.front, h2), o)
	end
	if holes.back ~= false then
		self:Wall(x0 - h2, z1, x1 + h2, z1, y0, y1, th, color, mat, shift(holes.back, h2), o)
	end
	if holes.left ~= false then
		self:Wall(x0, z0 + h2, x0, z1 - h2, y0, y1, th, color, mat, shift(holes.left, -h2), o)
	end
	if holes.right ~= false then
		self:Wall(x1, z0 + h2, x1, z1 - h2, y0, y1, th, color, mat, shift(holes.right, -h2), o)
	end
end

-- A bar from point a to point b (handrails, rods, beams, wires), `th` thick.
function Kit:Beam(x0, y0, z0, x1, y1, z1, th, color, mat, o)
	o = o or {}
	local a, b = Vector3.new(x0, y0, z0), Vector3.new(x1, y1, z1)
	local len = (b - a).Magnitude
	local mid = (a + b) / 2
	local cf = CFrame.lookAt(mid, b)
	if math.abs((b - a).Unit.Y) > 0.999 then
		cf = CFrame.new(mid) * CFrame.Angles(math.rad(90), 0, 0)
	end
	local p = Instance.new("Part")
	p.Name = o.n or "Beam"
	p.Anchored = true
	p.Size = Vector3.new(o.w or th, th, len)
	p.CFrame = self.cf * cf
	p.Color = color
	p.Material = mat or M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = o.c == true
	p.CanQuery = o.c == true
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = self.parent
	self.stats.parts += 1
	return p
end

-- Evenly spaced windows for Wall holes: n windows of width w along a wall of length len.
function HouseBuilder.Windows(len, n, w, lo, hi, glass, extra)
	local holes = {}
	local gap = (len - n * w) / (n + 1)
	for i = 1, n do
		local a = gap * i + w * (i - 1)
		local hole = { a, a + w, lo, hi, glass = glass or true }
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

-- A floor slab from (x0, z0) to (x1, z1), y0..y1, with an optional rectangular hole
-- { x0, z0, x1, z1 } (a stairwell) cut out of it.
function Kit:Slab(x0, z0, x1, z1, y0, y1, color, mat, hole, o)
	o = o or {}
	o.c = true
	o.n = o.n or "Floor"
	local ax, bx, az, bz = math.min(x0, x1), math.max(x0, x1), math.min(z0, z1), math.max(z0, z1)
	if not hole then
		return self:Box(ax, y0, az, bx, y1, bz, color, mat, o)
	end
	local hx0, hx1 = math.max(ax, math.min(hole[1], hole[3])), math.min(bx, math.max(hole[1], hole[3]))
	local hz0, hz1 = math.max(az, math.min(hole[2], hole[4])), math.min(bz, math.max(hole[2], hole[4]))
	if hz0 > az then
		self:Box(ax, y0, az, bx, y1, hz0, color, mat, o)
	end
	if hz1 < bz then
		self:Box(ax, y0, hz1, bx, y1, bz, color, mat, o)
	end
	if hx0 > ax then
		self:Box(ax, y0, hz0, hx0, y1, hz1, color, mat, o)
	end
	if hx1 < bx then
		self:Box(hx1, y0, hz0, bx, y1, hz1, color, mat, o)
	end
	return nil
end

-- A slab (decks, terraces) with several rectangular holes { x0, z0, x1, z1 } cut out of it, built
-- from as few boxes as the holes allow.
function Kit:Deck(x0, z0, x1, z1, y0, y1, color, mat, holes, o)
	o = o or {}
	o.c = true
	o.n = o.n or "Deck"
	local ax, bx, az, bz = math.min(x0, x1), math.max(x0, x1), math.min(z0, z1), math.max(z0, z1)
	local xs, zs = { ax, bx }, { az, bz }
	for _, h in ipairs(holes) do
		table.insert(xs, math.clamp(h[1], ax, bx))
		table.insert(xs, math.clamp(h[3], ax, bx))
		table.insert(zs, math.clamp(h[2], az, bz))
		table.insert(zs, math.clamp(h[4], az, bz))
	end
	table.sort(xs)
	table.sort(zs)
	local function solid(cx, cz)
		for _, h in ipairs(holes) do
			if cx > math.min(h[1], h[3]) and cx < math.max(h[1], h[3]) and cz > math.min(h[2], h[4]) and cz < math.max(h[2], h[4]) then
				return false
			end
		end
		return true
	end
	-- Row by row: runs of solid cells; a run identical to the one below grows that box instead.
	local open = {} -- [key "xa,xb"] = { xa, xb, za }
	local function flush(keep, zEnd)
		for key, r in pairs(open) do
			if not keep[key] then
				self:Box(r[1], y0, r[3], r[2], y1, zEnd, color, mat, table.clone(o))
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
end

-- A straight flight of stairs climbing from y0 to y1. Starts at (x, z) and climbs along `dir`
-- ("+X", "-X", "+Z", "-Z"), `w` wide (centred on the start point across the climb). Each step
-- rises at most 1 stud (o.tread deep, default 1.5) and is solid down to y0. Returns the run length.
function Kit:Stairs(x, z, dir, w, y0, y1, color, mat, o)
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
		local bottom = o.thin and (top - (o.thin or 0.6)) or y0
		if sx ~= 0 then
			self:Box(x + sx * a, bottom, z - w / 2, x + sx * b, top, z + w / 2, color, mat, { c = true, n = "Step" })
		else
			self:Box(x - w / 2, bottom, z + sz * a, x + w / 2, top, z + sz * b, color, mat, { c = true, n = "Step" })
		end
	end
	return n * tread
end

-- Railing along X or Z from (x0, z0) to (x1, z1): a top rail at height `h` above y, with posts every
-- `every` studs, or (o.glass) one glass panel. It collides (you lean on it, you don't fall off).
function Kit:Rail(x0, z0, x1, z1, y, h, color, o)
	o = o or {}
	local alongX = math.abs(z1 - z0) < 0.01
	if o.glass then
		self:Box(x0 - (alongX and 0 or 0.15), y, z0 - (alongX and 0.15 or 0), x1 + (alongX and 0 or 0.15), y + h, z1 + (alongX and 0.15 or 0),
			C.Glass, M.Glass, { c = true, q = false, t = 0.6, n = "GlassRail" })
		self:Box(x0 - (alongX and 0 or 0.2), y + h, z0 - (alongX and 0.2 or 0), x1 + (alongX and 0 or 0.2), y + h + 0.25,
			z1 + (alongX and 0.2 or 0), color, M.Metal, { n = "RailTop" })
		return
	end
	self:Box(x0 - (alongX and 0 or 0.2), y + h - 0.3, z0 - (alongX and 0.2 or 0), x1 + (alongX and 0 or 0.2), y + h,
		z1 + (alongX and 0.2 or 0), color, o.mat or M.Wood, { c = true, n = "Rail" })
	local len = alongX and math.abs(x1 - x0) or math.abs(z1 - z0)
	local n = math.max(1, math.floor(len / (o.every or 6)))
	for i = 0, n do
		local t = i / n
		local px, pz = x0 + (x1 - x0) * t, z0 + (z1 - z0) * t
		self:Box(px - 0.2, y, pz - 0.2, px + 0.2, y + h - 0.3, pz + 0.2, color, o.mat or M.Wood, { n = "Baluster" })
	end
	if o.mid then
		self:Box(x0 - (alongX and 0 or 0.1), y + h * 0.45, z0 - (alongX and 0.1 or 0), x1 + (alongX and 0 or 0.1), y + h * 0.45 + 0.2,
			z1 + (alongX and 0.1 or 0), color, o.mat or M.Wood, { n = "MidRail" })
	end
end

-- Roofs -------------------------------------------------------------------------------------------------

-- Gable roof over the rectangle (x0, z0)-(x1, z1) with its eaves at height y and the ridge `rise`
-- above, the ridge along X (ridgeAlongX) or Z. Two sloped panels (with `over` studs of overhang)
-- and the two triangular gable ends (wedges) filled in `endColor`.
function Kit:Gable(x0, z0, x1, z1, y, rise, ridgeAlongX, color, mat, endColor, endMat, o)
	o = o or {}
	local over = o.over or 1.5
	local th = o.th or 0.8
	local f = self
	local ax, bx, az, bz = math.min(x0, x1), math.max(x0, x1), math.min(z0, z1), math.max(z0, z1)
	if not ridgeAlongX then
		-- Draw it in a frame turned 90 degrees so the ridge runs along that frame's X.
		local cx, cz = (ax + bx) / 2, (az + bz) / 2
		f = self:Sub(cx, 0, cz, 90)
		ax, bx, az, bz = -(bz - az) / 2, (bz - az) / 2, -(bx - ax) / 2, (bx - ax) / 2
	end
	local len = bx - ax
	local half = (bz - az) / 2
	local cz = (az + bz) / 2
	local cx = (ax + bx) / 2
	local slope = math.atan2(rise, half)
	local dist = math.sqrt(half * half + rise * rise)
	local along = (dist + over) / 2 -- the panel's centre, measured down the slope from the ridge
	for _, side in ipairs({ 1, -1 }) do
		-- Each panel's underside lies on the line from the ridge to the eave and runs `over` past it.
		local py = y + rise - math.sin(slope) * along + math.cos(slope) * th / 2
		local pz = cz + side * (math.cos(slope) * along + math.sin(slope) * th / 2)
		f:Part(Vector3.new(len + over * 2, th, dist + over), cx, py, pz, color, mat,
			{ c = true, s = true, n = "Roof", rot = CFrame.Angles(side * slope, 0, 0) })
	end
	if o.cap then
		f:Box(ax - over, y + rise - 0.2, cz - 0.6, bx + over, y + rise + th + 0.2, cz + 0.6, o.cap, mat, { n = "Ridge" })
	end
	if endColor then
		for _, gx in ipairs({ ax + 0.2, bx - 0.2 }) do
			for _, side in ipairs({ 1, -1 }) do
				-- Each half of the gable end is a wedge whose low edge faces the eave.
				f:Wedge(o.endTh or 0.6, rise, half, gx, y + rise / 2, cz + side * half / 2, side == 1 and 180 or 0, endColor, endMat,
					{ c = true, n = "Gable" })
			end
		end
	end
end

-- Mono-pitch (shed) roof: high along the -Z edge at y + rise, low along +Z at y (o.flip swaps).
function Kit:Shed(x0, z0, x1, z1, y, rise, color, mat, o)
	o = o or {}
	local over = o.over or 1.2
	local th = o.th or 0.7
	local ax, bx, az, bz = math.min(x0, x1), math.max(x0, x1), math.min(z0, z1), math.max(z0, z1)
	local depth = bz - az
	local slope = math.atan2(rise, depth)
	local len = math.sqrt(depth * depth + rise * rise) + over * 2
	local side = o.flip and -1 or 1
	self:Part(Vector3.new(bx - ax + over * 2, th, len), (ax + bx) / 2, y + rise / 2 + th / 2, (az + bz) / 2, color, mat,
		{ c = true, s = true, n = "Roof", rot = CFrame.Angles(side * slope, 0, 0) })
end

-- Flat roof slab with a parapet wall around it.
function Kit:FlatRoof(x0, z0, x1, z1, y, color, mat, parapet, pColor, pMat, o)
	o = o or {}
	local ax, bx, az, bz = math.min(x0, x1), math.max(x0, x1), math.min(z0, z1), math.max(z0, z1)
	local over = o.over or 0
	self:Box(ax - over, y, az - over, bx + over, y + 1, bz + over, color, mat, { c = true, s = true, n = "Roof" })
	if parapet and parapet > 0 then
		local t = o.pth or 0.8
		local top = y + 1 + parapet
		self:Solid(ax - over, y + 1, az - over, bx + over, top, az - over + t, pColor, pMat, { n = "Parapet" })
		self:Solid(ax - over, y + 1, bz + over - t, bx + over, top, bz + over, pColor, pMat, { n = "Parapet" })
		self:Solid(ax - over, y + 1, az - over + t, ax - over + t, top, bz + over - t, pColor, pMat, { n = "Parapet" })
		self:Solid(bx + over - t, y + 1, az - over + t, bx + over, top, bz + over - t, pColor, pMat, { n = "Parapet" })
	end
end

-- Neon strip (decoration, glows at night): a thin box between two corners.
function Kit:Neon(x0, y0, z0, x1, y1, z1, color)
	return self:Box(x0, y0, z0, x1, y1, z1, color, M.Neon, { n = "Neon" })
end

-- Lights (max MAX_LIGHTS a house) -------------------------------------------------------------------------

-- A glowing fixture with a PointLight (no shadows). Returns the fixture part, or nil past the cap
-- (the fixture is still built, unlit).
function Kit:Light(x, y, z, color, range, brightness, o)
	o = o or {}
	local size = o.size or Vector3.new(1.2, 0.4, 1.2)
	local fixture = self:Part(size, x, y, z, color or C.Warm, M.Neon, { n = o.n or "Lamp", shape = o.shape })
	if self.stats.lights >= HouseBuilder.MAX_LIGHTS then
		return fixture
	end
	self.stats.lights += 1
	local light = Instance.new("PointLight")
	light.Color = color or C.Warm
	light.Range = range or 18
	light.Brightness = brightness or 1.2
	light.Shadows = false
	light.Parent = fixture
	return fixture
end

-- Doors, garage, markers ------------------------------------------------------------------------------------

-- An exterior door in a wall hole: (x, z) = the doorway centre on the wall line, y = its floor,
-- `yaw` turns the frame so its -Z is outside. w x h opening in a wall `th` thick.
-- Builds the visible panel (o.style "swing" | "slide" | "none"; it never collides and opens on
-- owners' screens) and the invisible blocker that stops everyone else. o.main marks the front door;
-- o.mirror hinges it on the +X side; o.noBlock leaves the blocker out (balcony doors, reached only
-- from inside, so nobody can be shut out on a balcony).
function Kit:Door(x, y, z, yaw, w, h, th, o)
	o = o or {}
	local f = self:In("Doors"):Sub(x, y, z, yaw)
	local style = o.style or "swing"
	if style ~= "none" then
		local ph = h - 0.1
		local panel = f:Part(Vector3.new(w - 0.2, ph, 0.3), 0, ph / 2, 0, o.color or C.DarkWood, o.mat or M.Wood,
			{ n = "DoorPanel", t = o.t })
		local open
		if style == "slide" then
			open = f.cf * CFrame.new(w - 0.4, ph / 2, 0.45) -- slides inside, past the jamb
		elseif o.mirror then -- hinged on the +X side (the right leaf of a double door or gate)
			open = f.cf * CFrame.new(w / 2 - 0.3, ph / 2, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(-(w - 0.2) / 2, 0, 0)
		else
			open = f.cf * CFrame.new(-w / 2 + 0.3, ph / 2, 0) * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.new((w - 0.2) / 2, 0, 0)
		end
		panel:SetAttribute("OwnerOpen", true)
		panel:SetAttribute("ClosedCF", panel.CFrame)
		panel:SetAttribute("OpenCF", open)
	end
	if o.noBlock then
		return nil -- a door you can only reach from inside (balconies): just the panel
	end
	local blocker = f:Part(Vector3.new(w, h, th + 0.6), 0, h / 2, 0, C.Black, M.SmoothPlastic, { n = "DoorBlocker", c = true, q = false, t = 1 })
	blocker:SetAttribute("OwnerOpen", true)
	if o.main then
		self.out.door = f.cf
		self.out.blocker = blocker
	end
	return blocker
end

-- Overhead garage door in a w x h opening (frame -Z = outside). It collides for everyone but owners
-- (whose screens tilt it up under the ceiling). o.glass for a glass showroom door.
function Kit:GarageDoor(x, y, z, yaw, w, h, color, mat, o)
	o = o or {}
	local f = self:In("Doors"):Sub(x, y, z, yaw)
	local door = f:Part(Vector3.new(w, h, 0.4), 0, h / 2, 0, color, mat, { n = "GarageDoor", c = true, t = o.t })
	door.CastShadow = false
	door:SetAttribute("OwnerOpen", true)
	door:SetAttribute("ClosedCF", door.CFrame)
	door:SetAttribute("OpenCF", f.cf * CFrame.new(0, h - 0.3, h / 2 + 0.6) * CFrame.Angles(math.rad(90), 0, 0))
	return door
end

-- Records a garage bay: floor centre (x, y, z), `yaw` so the frame's -Z points out of the garage.
function Kit:Bay(x, y, z, yaw)
	table.insert(self.out.bays, self.cf * CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw or 0), 0))
end

-- The bank pad (stand on it with no heat to stash your bag), w x d on a floor at height y.
function Kit:BankPad(x, y, z, w, d, color)
	local pad = self:Part(Vector3.new(w, 0.2, d), x, y + 0.1, z, color or C.Gold, M.Neon, { n = "BankPad", t = 0.35 })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.MaxDistance = 80
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = "STASH 💰"
	label.Parent = gui
	gui.Parent = pad
	self.out.pad = self.out.pad or pad
	self.out.pads = self.out.pads or {}
	table.insert(self.out.pads, pad) -- the Mansion has one per garage wing
	return pad
end

-- Where a character appears when they spawn at home (HumanoidRootPart height above the floor y).
function Kit:Spawn(x, y, z, yaw)
	self.out.spawn = self.cf * CFrame.new(x, y + 3.2, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

-- An invisible box marking the inside of the house (see the header).
function Kit:Zone(x0, y0, z0, x1, y1, z1)
	local z = self:In("Zones"):Box(x0, y0, z0, x1, y1, z1, C.White, M.SmoothPlastic, { n = "InsideZone", t = 1 })
	table.insert(self.out.zones, z)
	return z
end

-- Terrain water for a pool, a hot tub or a fountain: the box (x0, z0)-(x1, z1), y0..y1, snapped to the
-- 4-stud voxel grid. The basin around it must be built separately.
function Kit:Water(x0, y0, z0, x1, y1, z1)
	local a = self.cf * Vector3.new(x0, y0, z0)
	local b = self.cf * Vector3.new(x1, y1, z1)
	local function snap(v)
		return math.floor(v / 4 + 0.5) * 4
	end
	local lo = Vector3.new(snap(math.min(a.X, b.X)), snap(math.min(a.Y, b.Y)), snap(math.min(a.Z, b.Z)))
	local hi = Vector3.new(snap(math.max(a.X, b.X)), snap(math.max(a.Y, b.Y)), snap(math.max(a.Z, b.Z)))
	table.insert(self.out.water, { cf = CFrame.new((lo + hi) / 2), size = hi - lo })
end

-- A pool basin: liner floor, water, and an inner tile wall up to the deck at `top` (the deck around
-- it is the style's job). Corners on multiples of 4; water from y = 0 to top - 0.5.
function Kit:Pool(x0, z0, x1, z1, top, o)
	o = o or {}
	local ax, bx, az, bz = math.min(x0, x1), math.max(x0, x1), math.min(z0, z1), math.max(z0, z1)
	local tile = o.tile or C.Pool
	self:Box(ax, -0.4, az, bx, 0.05, bz, tile, M.CeramicTiles, { n = "PoolFloor" })
	local wt = 0.6
	self:Solid(ax - wt, 0, az - wt, bx + wt, top, az, tile, M.CeramicTiles, { n = "PoolWall" })
	self:Solid(ax - wt, 0, bz, bx + wt, top, bz + wt, tile, M.CeramicTiles, { n = "PoolWall" })
	self:Solid(ax - wt, 0, az, ax, top, bz, tile, M.CeramicTiles, { n = "PoolWall" })
	self:Solid(bx, 0, az, bx + wt, top, bz, tile, M.CeramicTiles, { n = "PoolWall" })
	-- Coping round the edge.
	local cp = o.coping or C.White
	local cw = 1.2
	self:Box(ax - cw, top, az - cw, bx + cw, top + 0.25, az, cp, M.Limestone, { n = "Coping", c = true })
	self:Box(ax - cw, top, bz, bx + cw, top + 0.25, bz + cw, cp, M.Limestone, { n = "Coping", c = true })
	self:Box(ax - cw, top, az, ax, top + 0.25, bz, cp, M.Limestone, { n = "Coping", c = true })
	self:Box(bx, top, az, bx + cw, top + 0.25, bz, cp, M.Limestone, { n = "Coping", c = true })
	-- A step bench at one end so swimmers can climb out.
	if o.step ~= false then
		self:Solid(ax, 0, az, ax + 2.5, top - 2.2, bz, tile, M.CeramicTiles, { n = "PoolStep" })
	end
	if o.glow then
		self:Neon(ax + 0.5, 1.4, az + 0.05, bx - 0.5, 1.7, az + 0.25, o.glow)
		self:Neon(ax + 0.5, 1.4, bz - 0.25, bx - 0.5, 1.7, bz - 0.05, o.glow)
	end
	self:Water(ax, 0, az, bx, top - 0.5, bz)
end

-- FOR SALE sign on two posts at (x, z), board facing the frame's -Z after `yaw` (toward the street).
function Kit:SaleSign(x, z, yaw, def)
	local f = self:In("Sign"):Sub(x, 0, z, yaw)
	local dark = rgb(24, 18, 40)
	for _, px in ipairs({ -4.6, 4.6 }) do
		f:Box(px - 0.3, 0, -0.3, px + 0.3, 6.4, 0.3, C.White, M.SmoothPlastic, { n = "SignPost" })
	end
	local board = f:Part(Vector3.new(10, 4.2, 0.4), 0, 5.2, 0, dark, M.SmoothPlastic, { n = "Sign" })
	f:Box(-5.1, 3.0, -0.25, 5.1, 3.2, 0.25, def.Color, M.Neon, { n = "Neon" })
	f:Box(-5.1, 7.2, -0.25, 5.1, 7.4, 0.25, def.Color, M.Neon, { n = "Neon" })
	local labels, owners = {}, {}
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.LightInfluence = 0
		gui.Brightness = 2
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 24
		gui.MaxDistance = 300
		local top = Instance.new("TextLabel")
		top.Name = "Status"
		top.BackgroundTransparency = 1
		top.Position = UDim2.fromScale(0.03, 0.04)
		top.Size = UDim2.fromScale(0.94, 0.42)
		top.Font = Enum.Font.FredokaOne
		top.TextScaled = true
		top.TextColor3 = Color3.new(1, 1, 1)
		top.TextStrokeTransparency = 0.4
		top.Text = "FOR SALE  " .. HouseBuilder.Money(def.Price)
		top.Parent = gui
		local name = Instance.new("TextLabel")
		name.Name = "PlaceName"
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromScale(0.03, 0.48)
		name.Size = UDim2.fromScale(0.94, 0.28)
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextColor3 = def.Color
		name.Text = def.Name
		name.Parent = gui
		local who = Instance.new("TextLabel")
		who.Name = "Owners"
		who.BackgroundTransparency = 1
		who.Position = UDim2.fromScale(0.03, 0.78)
		who.Size = UDim2.fromScale(0.94, 0.18)
		who.Font = Enum.Font.GothamBold
		who.TextScaled = true
		who.TextColor3 = rgb(220, 210, 255)
		who.Text = def.Features or ""
		who.Parent = gui
		gui.Parent = board
		table.insert(labels, top)
		table.insert(owners, who)
	end
	self.out.sign = board
	self.out.labels = labels
	self.out.owners = owners
	return board
end

-- A board with glowing text on its front (-Z after `yaw`): shop-style signs on the houses.
function Kit:Banner(x, y, z, yaw, w, h, text, color, o)
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	local board = f:Part(Vector3.new(w, h, 0.2), 0, 0, 0, o.back or C.Black, M.SmoothPlastic, { n = "Banner", t = o.back and 0 or 1 })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.MaxDistance = 400
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = o.font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.Text = text
	label.Parent = gui
	gui.Parent = board
	return board
end

-- Furniture and props (each drawn in its own frame: front = -Z, standing on y = 0) --------------------------

-- Sofa w wide. o.l = L-shaped extension length on the +X end (a sectional).
function Kit:Sofa(x, y, z, yaw, w, color, o)
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	local mat = o.mat or M.Fabric
	f:Box(-w / 2, 0, -1.6, w / 2, 1.5, 1.6, color, mat, { c = true, n = "Sofa" })
	f:Box(-w / 2, 1.5, 0.8, w / 2, 3.6, 1.6, color, mat, { n = "SofaBack" })
	f:Box(-w / 2 - 0.8, 0, -1.6, -w / 2, 2.4, 1.6, color, mat, { n = "SofaArm" })
	if o.l then
		f:Box(w / 2, 0, -1.6 - o.l, w / 2 + 3.2, 1.5, 1.6, color, mat, { c = true, n = "Sofa" })
		f:Box(w / 2 + 2.4, 1.5, -1.6 - o.l, w / 2 + 3.2, 3.6, 1.6, color, mat, { n = "SofaBack" })
	else
		f:Box(w / 2, 0, -1.6, w / 2 + 0.8, 2.4, 1.6, color, mat, { n = "SofaArm" })
	end
	if o.pillows then
		f:Box(-w / 2 + 0.6, 1.5, 0.1, -w / 2 + 2.2, 2.9, 0.8, o.pillows, M.Fabric, { n = "Pillow" })
		f:Box(w / 2 - 2.2, 1.5, 0.1, w / 2 - 0.6, 2.9, 0.8, o.pillows, M.Fabric, { n = "Pillow" })
	end
end

function Kit:Armchair(x, y, z, yaw, color, mat)
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-1.6, 0, -1.5, 1.6, 1.5, 1.5, color, mat or M.Fabric, { c = true, n = "Chair" })
	f:Box(-1.6, 1.5, 0.8, 1.6, 3.8, 1.5, color, mat or M.Fabric, { n = "ChairBack" })
end

function Kit:Table(x, y, z, yaw, w, d, h, color, mat, o)
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-w / 2, h - 0.3, -d / 2, w / 2, h, d / 2, color, mat or M.Wood, { c = true, n = "TableTop" })
	if o.round then
		f:Post(0, 0, 0, h - 0.3, 1, o.leg or color, mat or M.Wood, { n = "TableLeg" })
	else
		f:Box(-w / 2 + 0.5, 0, -d / 2 + 0.5, w / 2 - 0.5, h - 0.3, d / 2 - 0.5, o.leg or color, o.legMat or mat or M.Wood,
			{ n = "TableBase", t = o.legT })
	end
end

-- Dining chair (seat + back), facing -Z.
function Kit:Chair(x, y, z, yaw, color, mat)
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-0.9, 0, -0.9, 0.9, 1.8, 0.9, color, mat or M.Wood, { n = "Chair" })
	f:Box(-0.9, 1.8, 0.6, 0.9, 4.2, 0.9, color, mat or M.Wood, { n = "ChairBack" })
end

-- Dining set: a table with n chairs a side.
function Kit:DiningSet(x, y, z, yaw, w, d, n, tableColor, chairColor, o)
	o = o or {}
	self:Table(x, y, z, yaw, w, d, 3, tableColor, o.mat, o)
	local f = self:Sub(x, y, z, yaw)
	for i = 1, n do
		local cx = -w / 2 + w * (i - 0.5) / n
		f:Chair(cx, 0, -d / 2 - 1.1, 180, chairColor, o.chairMat)
		f:Chair(cx, 0, d / 2 + 1.1, 0, chairColor, o.chairMat)
	end
	if o.ends then
		f:Chair(-w / 2 - 1.1, 0, 0, 270, chairColor, o.chairMat)
		f:Chair(w / 2 + 1.1, 0, 0, 90, chairColor, o.chairMat)
	end
end

function Kit:Rug(x, y, z, yaw, w, d, color, o)
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	if o.round then
		return f:Disc(0, 0, 0, w, 0.08, color, M.Fabric, { n = "Rug" })
	end
	return f:Box(-w / 2, 0, -d / 2, w / 2, 0.08, d / 2, color, o.mat or M.Fabric, { n = "Rug" })
end

-- TV on a low cabinet; the screen faces -Z. o.wall = mounted (no cabinet), o.glow = screen colour.
function Kit:TV(x, y, z, yaw, w, o)
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	local h = w * 0.56
	local base = 0
	if not o.wall then
		f:Box(-w / 2 - 0.5, 0, -0.9, w / 2 + 0.5, 2, 0.9, o.cabinet or C.DarkWood, o.cabMat or M.Wood, { c = true, n = "TVStand" })
		base = 2.6
	else
		base = o.at or 4
	end
	f:Box(-w / 2, base, 0.1, w / 2, base + h, 0.5, C.Black, M.SmoothPlastic, { n = "TV" })
	f:Box(-w / 2 + 0.25, base + 0.25, 0.05, w / 2 - 0.25, base + h - 0.25, 0.1, o.glow or rgb(60, 110, 200), M.Neon, { n = "Screen" })
end

-- Bed w wide, l long; the headboard is at +Z.
function Kit:Bed(x, y, z, yaw, w, l, frame, sheet, blanket, o)
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-w / 2, 0, -l / 2, w / 2, 1.2, l / 2, frame, o.frameMat or M.Wood, { c = true, n = "BedFrame" })
	f:Box(-w / 2 + 0.2, 1.2, -l / 2 + 0.2, w / 2 - 0.2, 2.2, l / 2 - 0.2, sheet, M.Fabric, { n = "Mattress" })
	f:Box(-w / 2 + 0.1, 2.2, -l / 2 + 0.1, w / 2 - 0.1, 2.5, l / 2 - 3.2, blanket, M.Fabric, { n = "Blanket" })
	f:Box(-w / 2 + 0.6, 2.2, l / 2 - 2.6, w / 2 - 0.6, 3.0, l / 2 - 0.8, o.pillow or C.White, M.Fabric, { n = "Pillow" })
	f:Box(-w / 2, 0, l / 2, w / 2, o.head or 5, l / 2 + 0.6, o.headColor or frame, o.headMat or o.frameMat or M.Wood, { n = "Headboard" })
end

-- Bunk bed (kids' room): two decks and a ladder.
function Kit:BunkBed(x, y, z, yaw, frame, a, b)
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-2.2, 0, -4, 2.2, 1, 4, frame, M.Wood, { c = true, n = "BedFrame" })
	f:Box(-2, 1, -3.8, 2, 1.9, 3.8, a, M.Fabric, { n = "Mattress" })
	f:Box(-2.2, 5, -4, 2.2, 5.8, 4, frame, M.Wood, { n = "BedFrame" })
	f:Box(-2, 5.8, -3.8, 2, 6.6, 3.8, b, M.Fabric, { n = "Mattress" })
	for _, cx in ipairs({ -2.2, 2.2 }) do
		for _, cz in ipairs({ -4, 4 }) do
			f:Box(cx - 0.25, 0, cz - 0.25, cx + 0.25, 7.6, cz + 0.25, frame, M.Wood, { n = "BedPost" })
		end
	end
	f:Box(-2.3, 1, -4.2, -2.1, 7, -3.4, frame, M.Wood, { n = "Ladder" })
end

-- Nightstand with a little lamp (unlit shade).
function Kit:Nightstand(x, y, z, yaw, color, shade)
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-1, 0, -1, 1, 2.2, 1, color, M.Wood, { n = "Nightstand" })
	f:Box(-0.5, 2.2, -0.5, 0.5, 3.6, 0.5, shade or C.Warm, M.Neon, { n = "LampShade", t = 0.2 })
end

-- Kitchen run along X (w long, 2.6 deep, back at +Z): cabinets, worktop, sink and hob.
function Kit:Kitchen(x, y, z, yaw, w, cab, top, o)
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-w / 2, 0, -1.3, w / 2, 3, 1.3, cab, o.cabMat or M.Wood, { c = true, n = "Cabinets" })
	f:Box(-w / 2 - 0.1, 3, -1.45, w / 2 + 0.1, 3.4, 1.3, top, o.topMat or M.Marble, { n = "Worktop" })
	f:Box(-w / 4 - 1.2, 3.35, -0.9, -w / 4 + 1.2, 3.45, 0.6, C.Steel, M.Metal, { n = "Sink" })
	f:Box(w / 4 - 1.4, 3.35, -1, w / 4 + 1.4, 3.5, 0.8, C.Black, M.SmoothPlastic, { n = "Hob" })
	if o.upper then
		f:Box(-w / 2, 7, 0.1, w / 2, 9.5, 1.3, o.upper, o.cabMat or M.Wood, { n = "UpperCabinets" })
	end
	if o.hood then
		f:Box(w / 4 - 1.5, 7.5, -0.2, w / 4 + 1.5, 9, 1.3, o.hood, M.Metal, { n = "Hood" })
	end
end

function Kit:Fridge(x, y, z, yaw, color)
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-1.6, 0, -1.4, 1.6, 7.4, 1.4, color or C.Steel, M.Metal, { c = true, n = "Fridge" })
	f:Box(0.9, 2.6, -1.55, 1.1, 5.6, -1.4, C.Black, M.Metal, { n = "Handle" })
end

-- Kitchen island with stools on its -Z side.
function Kit:Island(x, y, z, yaw, w, cab, top, stool, n)
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-w / 2, 0, -1.6, w / 2, 3, 1.6, cab, M.Wood, { c = true, n = "Island" })
	f:Box(-w / 2 - 0.3, 3, -2.2, w / 2 + 0.3, 3.4, 1.8, top, M.Marble, { n = "IslandTop" })
	for i = 1, (n or 0) do
		local sx = -w / 2 + w * (i - 0.5) / n
		f:Disc(sx, 2.4, -3.2, 1.6, 0.4, stool, M.Leather, { n = "Stool" })
		f:Post(sx, 0, -3.2, 2.4, 0.4, C.Steel, M.Metal, { n = "StoolLeg" })
	end
end

function Kit:Bookshelf(x, y, z, yaw, w, h, color, o)
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-w / 2, 0, -0.6, w / 2, h, 0.8, color, M.Wood, { c = true, n = "Shelf" })
	local cols = o.books or { rgb(200, 60, 70), rgb(60, 120, 200), rgb(230, 190, 80) }
	for i, col in ipairs(cols) do
		local yy = h * i / (#cols + 1)
		f:Box(-w / 2 + 0.4, yy, -0.75, w / 2 - 0.4, yy + 1.3, -0.6, col, M.SmoothPlastic, { n = "Books" })
	end
end

-- Potted plant (o.tall for a palm-ish indoor tree).
function Kit:Plant(x, y, z, pot, o)
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, 0)
	f:Post(0, 0, 0, 1.6, 1.8, pot or rgb(200, 120, 80), M.SmoothPlastic, { n = "Pot" })
	if o.tall then
		f:Post(0, 1.6, 0, 5, 0.4, C.DarkWood, M.Wood, { n = "Stem" })
		f:Ball(0, 6, 0, 3.4, o.leaf or C.Leaf, M.Grass, { n = "Leaves" })
	else
		f:Ball(0, 2.6, 0, 2.4, o.leaf or C.Leaf, M.Grass, { n = "Leaves" })
	end
end

function Kit:FloorLamp(x, y, z, color)
	local f = self:In("Decor"):Sub(x, y, z, 0)
	f:Post(0, 0, 0, 6, 0.3, C.Black, M.Metal, { n = "LampPole" })
	f:Post(0, 6, 0, 7.4, 1.6, color or C.Warm, M.Neon, { n = "LampShade", t = 0.15 })
end

-- Picture on a wall (the frame's -Z is the room side): frame + canvas.
function Kit:Art(x, y, z, yaw, w, h, frame, canvas, glow)
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-w / 2, -h / 2, -0.15, w / 2, h / 2, 0.15, frame, M.Wood, { n = "ArtFrame" })
	f:Box(-w / 2 + 0.3, -h / 2 + 0.3, -0.25, w / 2 - 0.3, h / 2 - 0.3, -0.15, canvas, glow and M.Neon or M.SmoothPlastic, { n = "Canvas" })
end

function Kit:Desk(x, y, z, yaw, color, chair, glow)
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-2.6, 2.8, -1.4, 2.6, 3.1, 1.4, color, M.Wood, { c = true, n = "Desk" })
	f:Box(-2.4, 0, -1.2, -1.9, 2.8, 1.2, color, M.Wood, { n = "DeskLeg" })
	f:Box(1.9, 0, -1.2, 2.4, 2.8, 1.2, color, M.Wood, { n = "DeskLeg" })
	f:Box(-1.4, 3.1, 0.4, 1.4, 4.9, 0.6, C.Black, M.SmoothPlastic, { n = "Monitor" })
	f:Box(-1.25, 3.25, 0.35, 1.25, 4.75, 0.4, glow or rgb(80, 200, 255), M.Neon, { n = "Screen" })
	f:Box(-1, 0, -3, 1, 2, -1.8, chair, M.Leather, { n = "DeskChair" })
	f:Box(-1, 2, -1.9, 1, 4.6, -1.6, chair, M.Leather, { n = "DeskChairBack" })
end

-- Bathroom set along X (back at +Z): tub, toilet and vanity with a mirror, 12 long (x -6..6).
-- o.shower: a glass shower instead of the tub, 9 long (x -4.5..4.5).
function Kit:Bath(x, y, z, yaw, tile, o)
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	local x0, x1 = -6, 6
	if o.shower then
		x0, x1 = -4.5, 4.5
		f:Box(-4.5, 0, -1.4, -1, 0.3, 1.6, C.White, M.Marble, { n = "ShowerTray" })
		f:Box(-4.5, 0.3, -1.5, -1, 7.5, -1.3, C.Glass, M.Glass, { n = "ShowerGlass", c = true, q = false, t = 0.6 })
		f:Box(-1.1, 0.3, -1.4, -0.9, 7.5, 1.6, C.Glass, M.Glass, { n = "ShowerGlass", c = true, q = false, t = 0.6 })
		f:Box(-3.2, 7, 1, -2.2, 7.3, 1.6, C.Steel, M.Metal, { n = "ShowerHead" })
		f:Box(-0.4, 0, 0, 1.2, 1.8, 1.6, C.White, M.Marble, { n = "Toilet" })
		f:Box(-0.4, 1.8, 1, 1.2, 3.4, 1.6, C.White, M.Marble, { n = "Cistern" })
		f:Box(2, 0, 0.2, 4.5, 3, 1.6, o.vanity or C.DarkWood, M.Wood, { n = "Vanity" })
		f:Box(2.2, 4, 1.4, 4.3, 7, 1.6, C.Glass, M.Glass, { n = "Mirror", refl = 0.3, t = 0.1 })
	else
		f:Box(-6, 0, -1.4, 0, 2.4, 1.6, C.White, M.Marble, { c = true, n = "Tub" })
		f:Box(-5.6, 1.6, -1, -0.4, 2.45, 1.2, C.Water, M.Glass, { n = "TubWater", t = 0.3 })
		f:Box(1.2, 0, 0, 2.8, 1.8, 1.6, C.White, M.Marble, { n = "Toilet" })
		f:Box(1.2, 1.8, 1, 2.8, 3.4, 1.6, C.White, M.Marble, { n = "Cistern" })
		f:Box(3.6, 0, 0.2, 6, 3, 1.6, o.vanity or C.DarkWood, M.Wood, { n = "Vanity" })
		f:Box(3.8, 4, 1.4, 5.8, 7, 1.6, C.Glass, M.Glass, { n = "Mirror", refl = 0.3, t = 0.1 })
	end
	if tile then
		f:Box(x0, 0, 1.6, x1, 6, 1.7, tile, M.CeramicTiles, { n = "Tiles" })
	end
end

function Kit:Fireplace(x, y, z, yaw, stone, o)
	o = o or {}
	local f = self:In("Decor"):Sub(x, y, z, yaw)
	f:Box(-3.5, 0, -0.6, 3.5, 6, 1, stone, o.mat or M.Slate, { c = true, n = "Fireplace" })
	f:Box(-1.8, 0.6, -0.65, 1.8, 3.2, 0.4, rgb(255, 120, 40), M.Neon, { n = "Fire" })
	f:Box(-4, 6, -1, 4, 6.5, 1, o.mantle or C.DarkWood, M.Wood, { n = "Mantle" })
end

-- Outdoor props -------------------------------------------------------------------------------------------

function Kit:Lounger(x, y, z, yaw, color, frame)
	local f = self:In("Yard"):Sub(x, y, z, yaw)
	f:Box(-1.3, 0, -3, 1.3, 1.2, 2.2, frame or C.White, M.SmoothPlastic, { n = "Lounger" })
	f:Box(-1.2, 1.2, -2.9, 1.2, 1.5, 1.4, color, M.Fabric, { n = "Cushion" })
	f:Box(-1.2, 1.2, 1.4, 1.2, 1.5, 4.2, color, M.Fabric, { n = "Backrest", rot = CFrame.Angles(math.rad(-35), 0, 0) })
end

function Kit:Umbrella(x, y, z, color, o)
	o = o or {}
	local f = self:In("Yard"):Sub(x, y, z, 0)
	f:Post(0, 0, 0, 8, 0.35, C.White, M.Metal, { n = "UmbrellaPole" })
	f:Disc(0, 8, 0, o.d or 9, 0.4, color, M.Fabric, { n = "Canopy" })
	f:Ball(0, 8.4, 0, 0.8, color, M.Fabric, { n = "Finial" })
end

-- Barrel BBQ grill with glowing coals, facing -Z.
function Kit:BBQ(x, y, z, yaw)
	local f = self:In("Yard"):Sub(x, y, z, yaw)
	for _, lx in ipairs({ -1.6, 1.6 }) do
		f:Box(lx - 0.2, 0, -0.2, lx + 0.2, 3, 0.2, C.Black, M.Metal, { n = "GrillLeg" })
	end
	f:Part(Vector3.new(4.2, 2.2, 2.2), 0, 3.6, 0, C.Black, M.Metal, { n = "Grill", shape = "Cylinder", c = true })
	f:Box(-1.8, 4.5, -0.9, 1.8, 4.75, 0.9, rgb(255, 110, 40), M.Neon, { n = "Coals" })
	f:Box(2.1, 3.4, -0.8, 3.6, 3.6, 0.8, C.Steel, M.Metal, { n = "SideShelf" })
end

function Kit:PicnicTable(x, y, z, yaw, color)
	local f = self:In("Yard"):Sub(x, y, z, yaw)
	f:Box(-4, 2.6, -1.4, 4, 3, 1.4, color, M.WoodPlanks, { c = true, n = "TableTop" })
	f:Box(-3.2, 0, -0.4, 3.2, 2.6, 0.4, color, M.WoodPlanks, { n = "TableLegs" })
	for _, s in ipairs({ -1, 1 }) do
		f:Box(-4, 1.4, s * 2.4 - 0.6, 4, 1.8, s * 2.4 + 0.6, color, M.WoodPlanks, { n = "Bench" })
	end
end

function Kit:FirePit(x, y, z, stone)
	local f = self:In("Yard"):Sub(x, y, z, 0)
	f:Disc(0, 0, 0, 6, 1.2, stone or rgb(120, 110, 100), M.Slate, { n = "FirePit", c = true })
	f:Disc(0, 1.2, 0, 4, 0.1, rgb(255, 120, 40), M.Neon, { n = "Embers" })
	f:Ball(0, 1.6, 0, 2, rgb(255, 170, 60), M.Neon, { n = "Flame", t = 0.35 })
end

function Kit:Hammock(x, y, z, yaw, color, len)
	len = len or 10
	local f = self:In("Yard"):Sub(x, y, z, yaw)
	for _, s in ipairs({ -1, 1 }) do
		f:Box(s * len / 2 - 0.3, 0, -0.3, s * len / 2 + 0.3, 6, 0.3, C.DarkWood, M.Wood, { n = "HammockPost" })
	end
	f:Box(-len / 2 + 1.5, 2.6, -1.4, len / 2 - 1.5, 2.9, 1.4, color, M.Fabric, { n = "Hammock" })
	f:Box(-len / 2, 4.2, -0.1, len / 2, 4.4, 0.1, C.LightWood, M.Fabric, { n = "HammockRope" })
end

-- Palm tree: the generated mesh (ServerStorage.ArtAssets.PalmTree) if present, else a few parts.
function Kit:Palm(x, z, scale, y)
	scale = scale or 1
	local yaw = self.rng:NextNumber(0, math.pi * 2)
	local pos = (self.cf * CFrame.new(x, y or 0, z)).Position
	local assets = ServerStorage:FindFirstChild("ArtAssets")
	local template = assets and assets:FindFirstChild("PalmTree")
	if template and template:IsA("BasePart") then
		local p = template:Clone()
		p.Name = "PalmTree"
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Size = template.Size * scale
		p.CFrame = CFrame.new(pos + Vector3.new(0, p.Size.Y / 2, 0)) * CFrame.Angles(0, yaw, 0)
		p.Parent = self:In("Yard").parent
		self.stats.parts += 1
		return p
	end
	local f = self:In("Yard"):Sub(x, y or 0, z, math.deg(yaw))
	f:Post(0, 0, 0, 14 * scale, 1.4 * scale, rgb(180, 140, 95), M.SmoothPlastic, { n = "Trunk" })
	for i = 1, 4 do
		f:Part(Vector3.new(2 * scale, 0.3, 9 * scale), 0, 14 * scale, 0, C.Leaf, M.SmoothPlastic,
			{ n = "Frond", rot = CFrame.Angles(0, math.rad(i * 90), 0) * CFrame.new(0, 0, -4 * scale) * CFrame.Angles(math.rad(-15), 0, 0) })
	end
	return nil
end

-- Any other generated mesh in ServerStorage.ArtAssets (CypressTree, TropicalBush, FlamingoStatue,
-- Gator), scaled; models are pivoted to stand on the ground. Returns nil when it is missing.
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
			d.CastShadow = false
			self.stats.parts += 1
		end
	end
	if c:IsA("BasePart") then
		c.Size = c.Size * scale
		c.CFrame = base * CFrame.new(0, c.Size.Y / 2, 0)
	elseif c:IsA("Model") then
		c:ScaleTo(scale)
		local cf, size = c:GetBoundingBox()
		local bottom = cf * CFrame.new(0, -size.Y / 2, 0)
		c:PivotTo(base * bottom:ToObjectSpace(c:GetPivot()))
	end
	c.Parent = self:In("Yard").parent
	return c
end

function Kit:Bush(x, z, d, color, y)
	return self:In("Yard"):Ball(x, (y or 0) + d * 0.35, z, d, color or rgb(60, 150, 80), M.Grass, { n = "Bush" })
end

-- Hedge wall (collides; 8 tall keeps people out of a yard).
function Kit:Hedge(x0, z0, x1, z1, h, color)
	return self:In("Yard"):Solid(x0, 0, z0, x1, h or 8, z1, color or rgb(58, 128, 70), M.Grass, { n = "Hedge" })
end

-- Mailbox on a post at the kerb.
function Kit:Mailbox(x, z, yaw, color)
	local f = self:In("Yard"):Sub(x, 0, z, yaw)
	f:Box(-0.2, 0, -0.2, 0.2, 3.6, 0.2, C.White, M.Wood, { n = "MailPost" })
	f:Box(-0.7, 3.6, -1.1, 0.7, 4.8, 1.1, color, M.Metal, { n = "Mailbox" })
end

-- Building -----------------------------------------------------------------------------------------------

-- The lot frame of a property: centre Lot (y ignored), turned Yaw degrees (front = -Z).
function HouseBuilder.LotCFrame(def)
	return CFrame.new(def.Lot.X, 0, def.Lot.Z) * CFrame.Angles(0, math.rad(def.Yaw or 0), 0)
end

local styles = {}
local function style(name)
	if styles[name] == nil then
		local folder = script.Parent:FindFirstChild("Houses")
		local module = folder and folder:FindFirstChild(name)
		styles[name] = module and require(module) or false
	end
	return styles[name] or nil
end

local function seedOf(id)
	local n = 7
	for i = 1, #id do
		n = (n * 31 + string.byte(id, i)) % 2147483647
	end
	return n
end

function HouseBuilder.Build(def, parent)
	local build = style(def.Style)
	assert(build, "no house style " .. tostring(def.Style))
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("PropId", def.Id)
	local k = newKit(model, HouseBuilder.LotCFrame(def), seedOf(def.Id))
	k:In("Shell") -- folder order: shell first
	build(k:In("Shell"), def)
	local out = k.out
	assert(out.door and out.blocker, def.Id .. ": no front door")
	assert(out.spawn, def.Id .. ": no spawn point")
	assert(out.pad, def.Id .. ": no bank pad")
	assert(out.sign, def.Id .. ": no sale sign")
	local budget = HouseBuilder.Budget[def.Size or "M"] or 350
	if k.stats.parts > budget then
		warn(string.format("[HouseBuilder] %s uses %d parts (budget %d)", def.Id, k.stats.parts, budget))
	end
	model:SetAttribute("Parts", k.stats.parts)
	model.Parent = parent
	local terrain = Workspace.Terrain
	for _, w in ipairs(out.water) do
		terrain:FillBlock(w.cf, w.size, M.Water)
	end
	return {
		model = model,
		door = out.door,
		blocker = out.blocker,
		spawn = out.spawn,
		bays = out.bays,
		pad = out.pad,
		pads = out.pads or { out.pad },
		sign = out.sign,
		labels = out.labels,
		owners = out.owners,
		zones = out.zones,
		center = k.root.Position,
		parts = k.stats.parts,
		lights = k.stats.lights,
	}
end

return HouseBuilder
