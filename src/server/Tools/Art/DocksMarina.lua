-- DocksMarina (ModuleScript, ServerStorage.Tools.Art.DocksMarina). Studio-only art for Rustwater Docks
-- (x -900..450, z 600..2000) and Marina Row (x 450..1500, z 600..2000, plus the piers over the sea).
--   Docks:  RUSTWATER DOCKS gate over Solana Ave, the fenced Solana Terminal container yard with a
--           straddle crane (x 84..246, z 1328..1436), small yards in any warehouse lot left empty,
--           Gus the Gator murals on warehouse fronts, forklifts, crate piles, Highway 1 billboards.
--   Marina: floating slips with moored boats off the three piers, the Sea Dream yacht beside its heist
--           deck (1720, 1300), a cargo quay with two quay cranes and a barge (south end), Shell Shocked
--           Seafood, the MARINA ROW office, a palm promenade along z = 1000, rope posts, Jet Ski Rentals,
--           Barnacle Bob's boatyard.
-- Gameplay spots (hideout block, Mari, chop shop, Spray & Go, ATM3, stunt ramps) are left open.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local Art = {}

local WATER_Y = -1.5
local MAX_LIGHTS = 20
local MAX_CONTAINERS = 230
local PIERS = { 1100, 1300, 1650 } -- pier roads: x 1440..1680, 18 wide, top y 0.1
-- The yacht is moored alongside the boarding deck under the Sea Dream pad (not on top of it), so the pad
-- and its RobPoint stay reachable. Nudge these if the mesh sits too high or low in the water.
local YACHT_SCALE = 2
local YACHT_CENTER = Vector3.new(1718, 0, 1348)
local YACHT_DRAFT = 0.2 -- share of the yacht's height below the waterline

-- Rectangles (x0, x1, z0, z1) nothing of ours may touch: gameplay spots and other builders' plots.
local RESERVED = {
	{ -660, -290, 890, 1310 }, -- hideout block: pad (-475, 1100), car pads (z 1060), Mari the Fence (-560, 1020)
	{ -880, -670, 1460, 1650 }, -- Chop Shop (-780, 1580)
	{ 70, 430, 740, 900 }, -- Spray & Go (250, 820)
	{ 160, 240, 1445, 1515 }, -- ATM3 kiosk (200, 1480)
	{ 8, 68, 1365, 1435 }, -- Solana Avenue Air ramp (38, 1400)
	{ -235, -165, 1805, 1870 }, -- Rustwater Rocket ramp (-200, 1838)
	{ 1690, 1750, 1270, 1330 }, -- Sea Dream heist pad
}

function Art.Build(folder, ArtKit, Layout)
	local C, N = ArtKit.Colors, ArtKit.Colors.Neon
	local Metal, Wood, Neon = Enum.Material.Metal, Enum.Material.WoodPlanks, Enum.Material.Neon
	local rng = Random.new(1906) -- own seed: the docks look the same on every rebuild
	local lights, containers = 0, 0

	local reserved = table.clone(RESERVED)
	for _, z in ipairs(PIERS) do
		table.insert(reserved, { 1300, 1500, z - 20, z + 20 }) -- keep the drive onto each pier open
	end

	-- Small helpers --------------------------------------------------------------------------------
	local function sub(name)
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = folder
		return f
	end
	local function pick(list)
		return list[rng:NextInteger(1, #list)]
	end
	local function part(parent, size, cf, color, material, opts)
		return ArtKit.Part(parent, size, cf, color, material, opts)
	end
	local function trim(parent, size, cf, color, material) -- decorative, walk-through
		return ArtKit.Part(parent, size, cf, color, material, { CanCollide = false, Name = "Trim" })
	end
	-- Upright cylinder standing on cf.
	local function post(parent, height, diameter, cf, color, material, opts)
		opts = opts or {}
		opts.Shape = Enum.PartType.Cylinder
		return ArtKit.Part(parent, Vector3.new(height, diameter, diameter), cf * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color, material, opts)
	end
	local function ball(parent, d, pos, color, material, collide)
		return ArtKit.Part(parent, Vector3.new(d, d, d), CFrame.new(pos), color, material,
			{ Shape = Enum.PartType.Ball, CanCollide = collide == true, Name = "Ball" })
	end
	-- Thin bar between two points (stays, ropes). Not for exactly vertical bars.
	local function bar(parent, a, b, thick, color, material)
		return ArtKit.Part(parent, Vector3.new(thick, thick, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, material,
			{ CanCollide = false, Name = "Bar" })
	end
	local function light(p, color, range, brightness)
		if p and lights < MAX_LIGHTS and ArtKit.Light(p, color, range or 40, brightness or 1.6) then
			lights += 1
		end
	end
	-- Text on the front face of a part; yScale/hScale place it in a horizontal strip.
	local function text(p, str, color, yScale, hScale)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.MaxDistance = 500
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.03, yScale or 0)
		t.Size = UDim2.fromScale(0.94, hScale or 1)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = color
		t.TextStrokeTransparency = 0.5
		t.Text = str
		t.Parent = gui
		gui.Parent = p
	end

	-- Placement checks -----------------------------------------------------------------------------
	-- Art already in the world (restyled warehouses, street lights, other districts' props) is avoided.
	local artRoot = folder.Parent
	local avoid = {}
	if artRoot then
		for _, f in ipairs(artRoot:GetChildren()) do
			if f ~= folder then
				table.insert(avoid, f)
			end
		end
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = avoid
	local function noArt(x, z, sx, sz)
		return #avoid == 0 or #Workspace:GetPartBoundsInBox(CFrame.new(x, 8, z), Vector3.new(sx, 16, sz), overlap) == 0
	end
	local function isReserved(x0, x1, z0, z1)
		for _, r in ipairs(reserved) do
			if x1 > r[1] and x0 < r[2] and z1 > r[3] and z0 < r[4] then
				return true
			end
		end
		return false
	end
	-- Footprint (centre x, z; size sx by sz) stays 6 studs off roads and misses gameplay spots and other art.
	local function spotOK(x, z, sx, sz)
		return not isReserved(x - sx / 2, x + sx / 2, z - sz / 2, z + sz / 2)
			and Layout.IsFree(Vector3.new(x, 0, z), math.max(sx, sz) / 2 + 6)
			and noArt(x, z, sx, sz)
	end

	-- Prop builders --------------------------------------------------------------------------------
	local BOX_COLORS = {
		C.Rust, N.Cyan, N.Orange, C.Steel,
		Color3.fromRGB(255, 120, 170), Color3.fromRGB(90, 200, 150), Color3.fromRGB(255, 200, 70), Color3.fromRGB(100, 120, 210),
	}
	local function stack(parent, cf, levels)
		for k = 0, levels - 1 do
			if containers >= MAX_CONTAINERS then
				return
			end
			ArtKit.Container(parent, cf * CFrame.new(0, k * 8.5, 0), pick(BOX_COLORS))
			containers += 1
		end
	end

	-- Container yard: groups of three stacks (long side along z), 12-stud aisles between groups, 4-stud
	-- gaps between rows. Returns the groups' centre xs and the row-gap zs (where crane legs can stand).
	local function yard(parent, x0, x1, z0, z1, maxBoxes, heights)
		heights = heights or { 1, 2, 2, 3, 3 }
		local groups, gaps, start = {}, {}, containers
		local rows = math.floor((z1 - z0 + 4) / 24)
		local gx = x0
		while gx + 26 <= x1 do
			table.insert(groups, gx + 13)
			for c = 0, 2 do
				local x = gx + 4 + c * 9
				for k = 0, rows - 1 do
					local z = z0 + k * 24 + 10
					if containers - start < maxBoxes and rng:NextNumber() > 0.12 and spotOK(x, z, 8, 20) then
						stack(parent, CFrame.new(x, 0, z), pick(heights))
					end
				end
			end
			gx += 38
		end
		for k = 0, rows - 2 do
			table.insert(gaps, z0 + k * 24 + 22)
		end
		return groups, gaps
	end

	-- Rubber-tyred straddle crane over one container group: legs in the aisles and row gaps.
	local function straddleCrane(parent, x, za, zb, color)
		local m = ArtKit.Model(parent, "YardCrane")
		local H, zc, len = 34, (za + zb) / 2, zb - za
		for _, dx in ipairs({ -19, 19 }) do
			for _, z in ipairs({ za, zb }) do
				part(m, Vector3.new(2, H, 2), CFrame.new(x + dx, H / 2, z), color, Metal, { Shadow = true, Name = "Leg" })
			end
			part(m, Vector3.new(2.6, 3, len + 2.6), CFrame.new(x + dx, H + 1.5, zc), color, Metal, { Name = "Girder" })
			part(m, Vector3.new(2.6, 2, len + 5), CFrame.new(x + dx, 1, zc), C.Asphalt, nil, { Name = "Tyres" })
		end
		for _, z in ipairs({ za, zb }) do
			part(m, Vector3.new(40.6, 2.4, 2.4), CFrame.new(x, H + 1.2, z), color, Metal, { Name = "CrossBeam" })
		end
		-- Trolley riding the cross beams, hoist cable, spreader hovering just above a 3-high stack.
		local tx = x + rng:NextNumber(-8, 8)
		part(m, Vector3.new(7, 3, len + 2.4), CFrame.new(tx, H + 3.9, zc), C.White, nil, { Name = "Trolley" })
		part(m, Vector3.new(0.4, H + 2.4 - 28.5, 0.4), CFrame.new(tx, (H + 2.4 + 28.5) / 2, zc), C.Asphalt, nil, { CanCollide = false, Name = "Cable" })
		part(m, Vector3.new(8.5, 1, 20), CFrame.new(tx, 28, zc), N.Yellow, Metal, { CanCollide = false, Name = "Spreader" })
		part(m, Vector3.new(4, 4.5, 5), CFrame.new(x - 16.5, H - 2.25, za + 8), C.Glass, Enum.Material.Glass, { Name = "Cab" })
		light(ball(m, 1.8, Vector3.new(x + 19, H + 3.9, za), N.Orange, Neon), N.Orange, 40, 2)
		return m
	end

	-- Ship-to-shore quay crane: legs straddle the quay, the boom reaches over the water (base.LookVector).
	local function quayCrane(parent, base, color)
		local m = ArtKit.Model(parent, "QuayCrane")
		local H, SPAN, W = 46, 40, 16
		for _, lz in ipairs({ -SPAN / 2, SPAN / 2 }) do
			for _, lx in ipairs({ -W / 2, W / 2 }) do
				part(m, Vector3.new(2.5, H, 2.5), base * CFrame.new(lx, H / 2, lz), color, Metal, { Shadow = true, Name = "Leg" })
			end
			part(m, Vector3.new(W + 2.5, 3, 3), base * CFrame.new(0, H - 1.5, lz), color, Metal, { Name = "TopBeam" })
			part(m, Vector3.new(W, 2, 2), base * CFrame.new(0, H - 20, lz), color, Metal, { Name = "Brace" })
		end
		for _, lx in ipairs({ -W / 2, W / 2 }) do
			part(m, Vector3.new(2.5, 3, SPAN), base * CFrame.new(lx, H - 1.5, 0), color, Metal, { Name = "Sill" })
		end
		-- Boom: local +z is landward (tail + machine house), -z reaches out over the water.
		local back, front = SPAN / 2 + 26, SPAN / 2 + 72
		local boomZ = (back - front) / 2
		part(m, Vector3.new(6, 4, back + front), base * CFrame.new(0, H + 2, boomZ), color, Metal, { Shadow = true, Name = "Boom" })
		trim(m, Vector3.new(6.2, 0.4, back + front), base * CFrame.new(0, H + 4.2, boomZ), N.Yellow, Neon)
		part(m, Vector3.new(10, 7, 14), base * CFrame.new(0, H + 7.5, back - 9), C.White, nil, { Shadow = true, Name = "MachineHouse" })
		part(m, Vector3.new(3, 22, 3), base * CFrame.new(0, H + 15, SPAN / 2), color, Metal, { Name = "Mast" })
		local top = (base * CFrame.new(0, H + 26, SPAN / 2)).Position
		bar(m, top, (base * CFrame.new(0, H + 4, -front + 3)).Position, 0.6, C.Steel, Metal)
		bar(m, top, (base * CFrame.new(0, H + 4, back - 2)).Position, 0.6, C.Steel, Metal)
		light(ball(m, 2.4, top + Vector3.new(0, 1.2, 0), N.Pink, Neon), N.Pink, 60, 2)
		-- Trolley under the boom, cable and spreader lowered toward the barge.
		local t = base * CFrame.new(0, 0, -front + 14)
		part(m, Vector3.new(7, 3, 7), t * CFrame.new(0, H - 1.5, 0), C.White, nil, { Name = "Trolley" })
		part(m, Vector3.new(0.4, H - 17, 0.4), t * CFrame.new(0, (H - 3 + 14) / 2, 0), C.Asphalt, nil, { CanCollide = false, Name = "Cable" })
		part(m, Vector3.new(20, 1.2, 8.5), t * CFrame.new(0, 13.4, 0), N.Yellow, Metal, { CanCollide = false, Name = "Spreader" })
		part(m, Vector3.new(5, 4.5, 5), base * CFrame.new(0, H - 2.25, -SPAN / 2 - 5), C.Glass, Enum.Material.Glass, { Name = "Cab" })
		return m
	end

	-- Forklift; cf = ground CFrame, forks toward LookVector.
	local function forklift(parent, cf)
		local m = ArtKit.Model(parent, "Forklift")
		for _, z in ipairs({ -1.8, 1.8 }) do
			part(m, Vector3.new(4.4, 1.8, 1.8), cf * CFrame.new(0, 0.9, z), C.Asphalt, nil, { Shape = Enum.PartType.Cylinder, Name = "Wheels" })
		end
		part(m, Vector3.new(4, 2.6, 6), cf * CFrame.new(0, 2.4, 0.2), N.Yellow, nil, { Name = "Body" })
		part(m, Vector3.new(0.4, 3.6, 0.4), cf * CFrame.new(0, 5.5, 2.6), C.Asphalt, nil, { Name = "Post" })
		part(m, Vector3.new(4, 0.4, 4.6), cf * CFrame.new(0, 7.5, 0.6), C.Asphalt, nil, { CanCollide = false, Name = "Guard" })
		part(m, Vector3.new(3.4, 7.5, 0.5), cf * CFrame.new(0, 3.95, -3.1), C.Steel, Metal, { Name = "Mast" })
		part(m, Vector3.new(3, 0.3, 4.5), cf * CFrame.new(0, 0.45, -5.6), C.Steel, Metal, { Name = "Forks" })
		ball(m, 0.8, (cf * CFrame.new(0, 8.1, 1.5)).Position, N.Orange, Neon)
		return m
	end

	-- Little pyramid of 4-6 wooden crates.
	local CRATE_SPOTS = { { -4.2, 0 }, { 0, 0 }, { 4.2, 0 }, { -2.1, 1 }, { 2.1, 1 }, { 0, 2 } }
	local function crates(parent, x, z)
		local base = CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		for i = 1, rng:NextInteger(4, 6) do
			local s = CRATE_SPOTS[i]
			part(parent, Vector3.new(4, 4, 4), base * CFrame.new(s[1], 2 + s[2] * 4, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0),
				i % 3 == 0 and C.DarkWood or C.Wood, Wood, { Name = "Crate" })
		end
	end

	-- Chain-link fence from (ax, az) to (bx, bz); gaps = { {from, to}, ... } distances along it (driveways).
	local function fence(parent, ax, az, bx, bz, gaps)
		gaps = gaps or {}
		local a, b = Vector3.new(ax, 0, az), Vector3.new(bx, 0, bz)
		local len, dir = (b - a).Magnitude, (b - a).Unit
		local function gapEnd(s)
			for _, g in ipairs(gaps) do
				if s >= g[1] and s < g[2] then
					return g[2]
				end
			end
			return nil
		end
		local s = 0
		while s < len - 0.5 do
			local skip = gapEnd(s)
			if skip then
				s = skip
			else
				local e = math.min(s + 40, len)
				for _, g in ipairs(gaps) do
					if g[1] > s and g[1] < e then
						e = g[1]
					end
				end
				local p0, p1 = a + dir * s, a + dir * e
				local mid = (p0 + p1) / 2
				part(parent, Vector3.new(0.25, 7, e - s), CFrame.lookAt(mid, mid + dir) * CFrame.new(0, 3.5, 0), C.Steel, Enum.Material.DiamondPlate,
					{ Transparency = 0.5, Name = "ChainLink" })
				post(parent, 8, 0.6, CFrame.new(p0), C.Steel, Metal, { Name = "FencePost" })
				if e >= len - 0.5 or gapEnd(e) then
					post(parent, 8, 0.6, CFrame.new(p1), C.Steel, Metal, { Name = "FencePost" })
				end
				s = e
			end
		end
	end

	-- Short promenade lamp: post, white cap, neon globe (optionally a real light).
	local function lamp(parent, x, z, color, withLight)
		post(parent, 12, 0.6, CFrame.new(x, 0, z), C.Steel, Metal, { Name = "LampPost" })
		trim(parent, Vector3.new(1.4, 0.4, 1.4), CFrame.new(x, 12.2, z), C.White)
		local globe = ball(parent, 2, Vector3.new(x, 13.4, z), color, Neon)
		if withLight then
			light(globe, color, 36, 1.4)
		end
	end

	local function planter(parent, x, z, y0)
		y0 = y0 or 0
		part(parent, Vector3.new(5, 2, 5), CFrame.new(x, y0 + 1, z), pick(C.Pastels), nil, { Name = "Planter" })
		ball(parent, 4.4, Vector3.new(x, y0 + 2.9, z), C.Leaf, nil, false)
	end

	--------------------------------------------------------------------------------------------------
	-- RUSTWATER DOCKS gate: painted sign on a steel frame over Solana Ave (x 50) where it leaves downtown
	--------------------------------------------------------------------------------------------------
	do
		local f = sub("DocksGate")
		local gz
		for _, z in ipairs({ 612, 622, 598 }) do
			if noArt(16, z, 6, 6) and noArt(84, z, 6, 6) then
				gz = z
				break
			end
		end
		if gz then
			for _, x in ipairs({ 16, 84 }) do -- pylons 10 studs off the avenue's edges
				part(f, Vector3.new(4, 40, 4), CFrame.new(x, 20, gz), C.Steel, Metal, { Shadow = true, Name = "Pylon" })
				for _, y in ipairs({ 6, 12, 18 }) do
					trim(f, Vector3.new(4.3, 1.4, 4.3), CFrame.new(x, y, gz), N.Orange, Neon) -- hazard bands
				end
				local px = x < 50 and -2 or 102
				if spotOK(px, gz, 4, 4) then
					ArtKit.Palm(f, Vector3.new(px, 0, gz), 1.6, rng:NextNumber(0, math.pi * 2))
				end
			end
			part(f, Vector3.new(72, 3, 3), CFrame.new(50, 38.5, gz), C.Steel, Metal, { Name = "Beam" })
			-- Sign hangs under the beam, 26 studs above the road; one face each way.
			for _, s in ipairs({ -1, 1 }) do
				local pos = Vector3.new(50, 31.5, gz + s * 0.4)
				local sign = ArtKit.Sign(f, CFrame.lookAt(pos, pos + Vector3.new(0, 0, s)), "RUSTWATER DOCKS", s < 0 and N.Orange or N.Cyan, 62, 11)
				if s < 0 then
					light(sign, N.Orange, 50, 1.5)
				end
			end
		end
	end

	--------------------------------------------------------------------------------------------------
	-- Parody billboards facing Highway 1 from the gaps between the warehouses south of it
	--------------------------------------------------------------------------------------------------
	do
		local f = sub("Billboards")
		local ads = {
			{ -300, "GUS THE GATOR SAYS: WEAR SUNSCREEN!", N.Mint },
			{ 50, "RUST-B-GONE: NOW 10% LESS RUSTY", N.Orange },
			{ -650, "CRATE EXPECTATIONS: WE STACK ANYTHING", N.Cyan },
		}
		for _, ad in ipairs(ads) do
			for _, z in ipairs({ 1910, 1922 }) do
				if spotOK(ad[1], z, 36, 4) then
					ArtKit.Billboard(f, CFrame.lookAt(Vector3.new(ad[1], 0, z), Vector3.new(ad[1], 0, z - 1)), ad[2], ad[3])
					break
				end
			end
		end
	end

	--------------------------------------------------------------------------------------------------
	-- Solana Terminal: fenced container yard east of Solana Ave (the lot CityGen clears around ATM3)
	--------------------------------------------------------------------------------------------------
	local docks = sub("Docks")
	if noArt(165, 1382, 150, 100) then
		local lot = ArtKit.Model(docks, "SolanaTerminal")
		local groups, gaps = yard(lot, 92, 206, 1336, 1430, 80)
		if #groups >= 2 and #gaps >= 3 then
			straddleCrane(lot, groups[2], gaps[1], gaps[3], N.Orange)
		end
		forklift(lot, CFrame.lookAt(Vector3.new(222, 0, 1352), Vector3.new(222, 0, 1340)))
		forklift(lot, CFrame.lookAt(Vector3.new(216, 0, 1420), Vector3.new(228, 0, 1420)))
		crates(lot, 233, 1386)
		crates(lot, 214, 1398)
		-- Fence round the lot; driveways on the z = 1300 street side and toward the ATM plaza.
		fence(lot, 84, 1328, 246, 1328, { { 118, 146 } })
		fence(lot, 84, 1328, 84, 1436)
		fence(lot, 246, 1328, 246, 1436)
		fence(lot, 84, 1436, 246, 1436, { { 118, 146 } })
		lamp(lot, 240, 1334, N.Orange, true)
		lamp(lot, 240, 1430, N.Cyan, true)
		table.insert(reserved, { 78, 252, 1322, 1442 })
	end

	-- Any warehouse lot CityGen left empty becomes a small container yard (at most three of them).
	do
		local dkX = { -900, -650, -300, 50, 450 }
		local dkZ = { 600, 900, 1300, 1650, 1850, 2000 }
		local made = 0
		for i = 1, #dkX - 1 do
			for j = 1, #dkZ - 1 do
				-- Same lot maths as CityGen.fillBlock (30-stud inset, lots over 160 studs split in two).
				local x0, x1, z0, z1 = dkX[i] + 30, dkX[i + 1] - 30, dkZ[j] + 30, dkZ[j + 1] - 30
				if x1 - x0 >= 30 and z1 - z0 >= 30 then
					local nx, nz = (x1 - x0) > 160 and 2 or 1, (z1 - z0) > 160 and 2 or 1
					local cw, cd = (x1 - x0) / nx, (z1 - z0) / nz
					for a = 0, nx - 1 do
						for b = 0, nz - 1 do
							local lx0, lz0 = x0 + a * cw + 6, z0 + b * cd + 6
							local lx1, lz1 = lx0 + cw - 12, lz0 + cd - 12
							local cx, cz = (lx0 + lx1) / 2, (lz0 + lz1) / 2
							if made < 3 and not isReserved(lx0 - 10, lx1 + 10, lz0 - 10, lz1 + 10) and noArt(cx, cz, lx1 - lx0, lz1 - lz0) then
								made += 1
								local m = ArtKit.Model(docks, "ContainerLot")
								yard(m, lx0 + 4, lx1 - 30, lz0 + 4, lz1 - 4, 36)
								local fx = lx1 - 14
								if spotOK(fx, cz, 6, 14) then
									forklift(m, CFrame.lookAt(Vector3.new(fx, 0, cz), Vector3.new(fx, 0, cz - 1)))
								end
								if spotOK(fx, lz1 - 12, 12, 12) then
									crates(m, fx, lz1 - 12)
								end
							end
						end
					end
				end
			end
		end
	end

	--------------------------------------------------------------------------------------------------
	-- Murals on warehouse fronts, beside the roller door: Gus the Gator, a sunset, a happy fish.
	-- Built from flat coloured panels layered a hair apart (no decals).
	--------------------------------------------------------------------------------------------------
	do
		local f = sub("Murals")
		local blds = artRoot and artRoot:FindFirstChild("Buildings")
		local list = {}
		if blds then
			for _, p in ipairs(blds:GetChildren()) do
				local q = p:IsA("BasePart") and p.Position
				if q and p.Name == "Warehouse" and p.Size.X >= 70 and p.Size.Y >= 24 and q.X > -900 and q.X < 450 and q.Z > 600 and q.Z < 2000 then
					table.insert(list, p)
				end
			end
		end
		local function layerZ(k)
			return -0.25 - 0.2 * (k - 1)
		end
		-- u, v and sizes are fractions of the mural's width W / height H; wf = mural centre on the wall.
		local function slab(wf, W, H, u, v, w, h, color, k, rot)
			part(f, Vector3.new(w * W, h * H, 0.2), wf * CFrame.new(u * W, v * H, layerZ(k)) * CFrame.Angles(0, 0, math.rad(rot or 0)), color, nil,
				{ CanCollide = false, Name = "Mural" })
		end
		local function disc(wf, W, H, u, v, d, color, k)
			part(f, Vector3.new(0.2, d * H, d * H), wf * CFrame.new(u * W, v * H, layerZ(k)) * CFrame.Angles(0, math.rad(90), 0), color, nil,
				{ Shape = Enum.PartType.Cylinder, CanCollide = false, Name = "Mural" })
		end
		local GREEN, WHITE, DARK = Color3.fromRGB(80, 190, 90), C.White, Color3.fromRGB(30, 30, 40)
		local designs = {
			gus = function(wf, W, H)
				text(part(f, Vector3.new(W, H, 0.3), wf, Color3.fromRGB(150, 225, 255), nil, { CanCollide = false, Name = "Mural" }),
					"GUS SAYS: WEAR SUNSCREEN!", N.Pink, 0.74, 0.24)
				disc(wf, W, H, 0.33, 0.28, 0.34, N.Yellow, 1) -- sun
				slab(wf, W, H, -0.1, -0.05, 0.5, 0.22, GREEN, 1) -- body
				slab(wf, W, H, -0.4, -0.1, 0.2, 0.1, GREEN, 1, 20) -- tail
				slab(wf, W, H, 0.18, 0.02, 0.14, 0.24, GREEN, 1) -- head
				slab(wf, W, H, 0.33, -0.02, 0.2, 0.12, GREEN, 1) -- snout
				slab(wf, W, H, -0.25, -0.18, 0.05, 0.1, GREEN, 1) -- legs
				slab(wf, W, H, 0.05, -0.18, 0.05, 0.1, GREEN, 1)
				slab(wf, W, H, -0.1, -0.12, 0.4, 0.07, Color3.fromRGB(215, 245, 160), 2) -- belly
				disc(wf, W, H, 0.2, 0.16, 0.14, WHITE, 2) -- eye
				slab(wf, W, H, 0.2, 0.14, 0.2, 0.06, N.Pink, 3) -- shades
				slab(wf, W, H, 0.33, -0.06, 0.14, 0.025, WHITE, 2) -- grin
			end,
			sunset = function(wf, W, H)
				text(part(f, Vector3.new(W, H, 0.3), wf, Color3.fromRGB(255, 160, 200), nil, { CanCollide = false, Name = "Mural" }),
					"PORT SOLANA", N.Yellow, 0.74, 0.24)
				disc(wf, W, H, 0.05, 0.05, 0.5, N.Orange, 1) -- sun
				for i, c in ipairs({ N.Purple, N.Cyan, N.Purple }) do -- sea stripes over the sun's lower half
					slab(wf, W, H, 0, -0.04 - i * 0.06, 1, 0.04, c, 2)
				end
				slab(wf, W, H, -0.33, 0.06, 0.03, 0.46, Color3.fromRGB(90, 60, 50), 2, 8) -- palm trunk
				for _, r in ipairs({ -25, 0, 25 }) do
					slab(wf, W, H, -0.34, 0.3, 0.18, 0.05, Color3.fromRGB(40, 140, 80), 3, r)
				end
			end,
			fish = function(wf, W, H)
				text(part(f, Vector3.new(W, H, 0.3), wf, Color3.fromRGB(170, 240, 210), nil, { CanCollide = false, Name = "Mural" }),
					"HAVE A FISH-TASTIC DAY!", N.Purple, 0.74, 0.24)
				disc(wf, W, H, 0, 0.1, 0.5, N.Orange, 1) -- body
				slab(wf, W, H, -0.4 * H / W, 0.1, 0.22 * H / W, 0.22, N.Orange, 1, 45) -- tail (diamond touching the body)
				disc(wf, W, H, 0.07, 0.2, 0.12, WHITE, 2) -- eye
				disc(wf, W, H, 0.08, 0.2, 0.06, DARK, 3)
				slab(wf, W, H, 0.09, 0.02, 0.08, 0.025, DARK, 2) -- smile
				for i, b in ipairs({ { 0.26, 0.2 }, { 0.31, 0.32 }, { 0.37, 0.43 } }) do -- bubbles
					disc(wf, W, H, b[1], b[2], 0.05 + i * 0.02, WHITE, 1)
				end
			end,
		}
		local targets = {
			{ Vector3.new(0, 0, 1050), "gus" }, -- faces Solana Ave
			{ Vector3.new(-470, 0, 1480), "sunset" },
			{ Vector3.new(300, 0, 1720), "fish" },
		}
		local used = {}
		for _, t in ipairs(targets) do
			local best, bestD
			for _, p in ipairs(list) do
				local d = (Vector3.new(p.Position.X, 0, p.Position.Z) - t[1]).Magnitude
				if not used[p] and (not bestD or d < bestD) then
					best, bestD = p, d
				end
			end
			if best then
				used[best] = true
				local w, h, d = best.Size.X, best.Size.Y, best.Size.Z
				local W, H = math.min(36, w / 2 - 16), math.min(18, h - 8)
				-- Right of the roller door (door is at most 20 wide, centred on the front wall).
				local wf = best.CFrame * CFrame.new(13 + W / 2, -h / 2 + 4 + H / 2, -d / 2 - 0.15)
				designs[t[2]](wf, W, H)
			end
		end
	end

	--------------------------------------------------------------------------------------------------
	-- Marina slips: floating finger docks off both sides of each pier, boats moored bow-in
	--------------------------------------------------------------------------------------------------
	local marina = sub("Marina")
	local FINGERS = { 1552, 1574, 1596, 1618, 1640, 1662 } -- 18-stud slips between them, all over water
	local BOAT_COLORS = { C.White, C.White, C.Pastels[1], C.Pastels[2], C.Pastels[4], C.Pastels[6], N.Cyan, N.Orange }
	do
		local slips = ArtKit.Model(marina, "Slips")
		local boats = ArtKit.Model(marina, "Boats")
		for _, pz in ipairs(PIERS) do
			for _, s in ipairs({ -1, 1 }) do -- north (-1) and south (+1) of the pier (pier edges at pz +- 9)
				for _, fx in ipairs(FINGERS) do
					part(slips, Vector3.new(4, 1.2, 26), CFrame.new(fx, -0.6, pz + s * 22), C.Wood, Wood, { Name = "Finger" })
					post(slips, 2.2, 1.2, CFrame.new(fx, 0, pz + s * 33.5), C.White, nil, { CanCollide = false, Name = "Bollard" })
				end
				for i = 1, #FINGERS - 1 do
					if rng:NextNumber() < 0.72 then
						local x = (FINGERS[i] + FINGERS[i + 1]) / 2
						local L = pick({ 14, 16, 18, 20 })
						local z = pz + s * (9 + 1.5 + L / 2)
						ArtKit.Boat(boats, CFrame.lookAt(Vector3.new(x, -0.8, z), Vector3.new(x, -0.8, pz)), L, pick(BOAT_COLORS))
					end
				end
			end
		end
	end

	--------------------------------------------------------------------------------------------------
	-- Sea Dream: boarding deck under the heist pad (joined to the 1300 pier end) + the luxury yacht
	--------------------------------------------------------------------------------------------------
	do
		local sd = ArtKit.Model(marina, "SeaDream")
		-- Deck top y 0.05: the pad (y 0.12..0.32) and its RobPoint sit on it.
		part(sd, Vector3.new(72, 1.2, 60), CFrame.new(1716, -0.55, 1300), C.Wood, Wood, { Name = "BoardingDeck" })
		for _, x in ipairs({ 1681, 1751 }) do
			for _, z in ipairs({ 1273, 1327 }) do
				post(sd, 3.6, 1.6, CFrame.new(x, -2, z), C.DarkWood, Wood, { Name = "Piling" })
			end
		end
		light(trim(sd, Vector3.new(72, 0.3, 0.6), CFrame.new(1716, 0.2, 1329.7), N.Cyan, Neon), N.Cyan, 40, 1.5)
		-- Name board at the end of the pier, facing people walking out.
		post(sd, 7, 0.6, CFrame.new(1684, 0.05, 1322), C.White, nil, { Name = "SignPost" })
		local signPos = Vector3.new(1683.6, 8.6, 1322)
		ArtKit.Sign(sd, CFrame.lookAt(signPos, signPos - Vector3.new(1, 0, 0)), "SEA DREAM", N.Pink, 12, 3.5)

		local assets = ServerStorage:FindFirstChild("ArtAssets")
		local tmpl = assets and assets:FindFirstChild("Yacht")
		if tmpl and tmpl:IsA("BasePart") then
			local y = tmpl:Clone()
			y.Anchored = true
			y.CanTouch = false
			y.CastShadow = true
			y.Size = tmpl.Size * YACHT_SCALE
			local bottom = WATER_Y - y.Size.Y * YACHT_DRAFT
			-- Native length runs along z; turn it 90 degrees so it lies alongside the deck (long side along x).
			y.CFrame = CFrame.new(YACHT_CENTER.X, bottom + y.Size.Y / 2, YACHT_CENTER.Z) * CFrame.Angles(0, math.rad(90), 0)
			y.Parent = sd
		else
			-- Part yacht fallback: white hull, two decks, glass band, neon trim.
			local c = YACHT_CENTER
			part(sd, Vector3.new(80, 8, 26), CFrame.new(c.X, WATER_Y + 1, c.Z), C.White, nil, { Shadow = true, Name = "Hull" })
			trim(sd, Vector3.new(80.4, 0.6, 26.4), CFrame.new(c.X, WATER_Y + 3.6, c.Z), N.Pink, Neon)
			part(sd, Vector3.new(58, 6, 22), CFrame.new(c.X - 4, WATER_Y + 8, c.Z), C.White, nil, { Shadow = true, Name = "Deck1" })
			part(sd, Vector3.new(58.4, 2, 22.4), CFrame.new(c.X - 4, WATER_Y + 8.5, c.Z), C.Glass, Enum.Material.Glass, { CanCollide = false, Name = "Windows" })
			part(sd, Vector3.new(34, 5, 18), CFrame.new(c.X - 8, WATER_Y + 13.5, c.Z), C.White, nil, { Shadow = true, Name = "Deck2" })
		end
		-- Gangway from the deck edge up toward the yacht's side.
		part(sd, Vector3.new(5, 0.4, 12), CFrame.new(1716, 2.1, 1335.5) * CFrame.Angles(math.rad(-20), 0, 0), C.White, nil, { Name = "Gangway" })
	end

	--------------------------------------------------------------------------------------------------
	-- Cargo quay (south end of Marina Row): two quay cranes, a barge with boxes, a tug, a small yard
	--------------------------------------------------------------------------------------------------
	do
		local quay = ArtKit.Model(marina, "CargoQuay")
		for i, zc in ipairs({ 1800, 1870 }) do
			if spotOK(1470, zc, 44, 18) then
				quayCrane(quay, CFrame.lookAt(Vector3.new(1470, 0, zc), Vector3.new(1471, 0, zc)), i == 1 and N.Orange or N.Cyan)
			end
		end
		part(quay, Vector3.new(28, 3, 110), CFrame.new(1560, WATER_Y, 1835), Color3.fromRGB(70, 80, 100), Metal, { Shadow = true, Name = "Barge" })
		trim(quay, Vector3.new(0.4, 0.6, 110), CFrame.new(1545.8, -0.6, 1835), N.Yellow, Neon)
		for _, x in ipairs({ 1552, 1566 }) do
			for _, z in ipairs({ 1792, 1816, 1840, 1864 }) do
				if rng:NextNumber() < 0.8 then
					stack(quay, CFrame.new(x, 0, z), x < 1560 and 1 or rng:NextInteger(1, 2)) -- low row stays under the spreaders
				end
			end
		end
		ArtKit.Boat(quay, CFrame.lookAt(Vector3.new(1560, -0.8, 1906), Vector3.new(1560, -0.8, 1890)), 18, N.Orange)
		yard(quay, 1330, 1422, 1700, 1830, 50, { 1, 1, 2, 2, 3 })
		if spotOK(1436, 1760, 6, 14) then
			forklift(quay, CFrame.lookAt(Vector3.new(1436, 0, 1760), Vector3.new(1436, 0, 1750)))
		end
		crates(quay, 1438, 1846)
		crates(quay, 1432, 1722)
		lamp(quay, 1440, 1700, N.Cyan, true)
		fence(quay, 1324, 1694, 1324, 1840, { { 60, 86 } })
		fence(quay, 1324, 1694, 1426, 1694, { { 70, 110 } })
	end

	--------------------------------------------------------------------------------------------------
	-- Shell Shocked Seafood: shack facing the water (east), striped awning, crab on the sign, tables
	--------------------------------------------------------------------------------------------------
	do
		local m = ArtKit.Model(marina, "ShellShockedSeafood")
		local cf = CFrame.lookAt(Vector3.new(1400, 0, 1400), Vector3.new(1401, 0, 1400))
		part(m, Vector3.new(26, 10, 16), cf * CFrame.new(0, 5, 0), Color3.fromRGB(255, 150, 140), nil, { Shadow = true, Name = "Shack" })
		part(m, Vector3.new(30, 1, 20), cf * CFrame.new(0, 10.5, 0), C.White, nil, { Shadow = true, Name = "Roof" })
		trim(m, Vector3.new(30.4, 0.5, 20.4), cf * CFrame.new(0, 10.2, 0), N.Pink, Neon)
		part(m, Vector3.new(16, 4.5, 0.3), cf * CFrame.new(0, 5.6, -8.1), C.Glass, Enum.Material.Glass, { CanCollide = false, Name = "Window" })
		part(m, Vector3.new(18, 0.8, 3), cf * CFrame.new(0, 3.4, -9.3), C.Wood, Wood, { Name = "Counter" })
		for i = 0, 3 do
			part(m, Vector3.new(4.5, 0.3, 4.5), cf * CFrame.new(-6.75 + i * 4.5, 8.4, -10) * CFrame.Angles(math.rad(-18), 0, 0),
				i % 2 == 0 and N.Pink or C.White, nil, { CanCollide = false, Name = "Awning" })
		end
		local sign = ArtKit.Sign(m, cf * CFrame.new(0, 13.6, -7), "SHELL SHOCKED SEAFOOD", N.Pink, 28, 5)
		light(sign, N.Pink, 36, 1.4)
		-- Cartoon crab perched on the sign's right end.
		local crab = cf * CFrame.new(9, 18.1, -7)
		ball(m, 4, crab.Position, N.Orange)
		for _, x in ipairs({ -2.4, 2.4 }) do
			ball(m, 1.8, (crab * CFrame.new(x, 1.2, -0.8)).Position, N.Orange)
			ball(m, 1, (crab * CFrame.new(x / 3, 1.9, -0.9)).Position, C.White)
		end
		-- Umbrella tables between the shack and the quay.
		for _, p in ipairs({ { 1428, 1390 }, { 1444, 1410 }, { 1460, 1392 } }) do
			post(m, 0.4, 4, CFrame.new(p[1], 2.8, p[2]), C.White, nil, { Name = "Table" })
			ArtKit.Umbrella(m, Vector3.new(p[1], 0, p[2]), pick({ N.Pink, N.Cyan, N.Yellow }))
		end
	end

	--------------------------------------------------------------------------------------------------
	-- Jet Ski Rentals: kiosk on the quay near (1420, 1150) + a floating ski dock with three jet skis
	--------------------------------------------------------------------------------------------------
	do
		local m = ArtKit.Model(marina, "JetSkiRentals")
		local cf = CFrame.lookAt(Vector3.new(1420, 0, 1150), Vector3.new(1421, 0, 1150))
		part(m, Vector3.new(12, 8, 9), cf * CFrame.new(0, 4, 0), C.Pastels[2], nil, { Shadow = true, Name = "Kiosk" })
		part(m, Vector3.new(15, 0.8, 12), cf * CFrame.new(0, 8.4, -0.5), N.Yellow, nil, { Name = "Roof" })
		part(m, Vector3.new(8, 3.5, 0.3), cf * CFrame.new(0, 4.6, -4.6), C.Glass, Enum.Material.Glass, { CanCollide = false, Name = "Window" })
		part(m, Vector3.new(10, 0.6, 2), cf * CFrame.new(0, 3, -5.4), C.White, nil, { Name = "Counter" })
		light(ArtKit.Sign(m, cf * CFrame.new(0, 11.1, -3), "JET SKI RENTALS", N.Cyan, 16, 4.5), N.Cyan, 30, 1.4)
		part(m, Vector3.new(64, 1, 5), CFrame.new(1532, -0.5, 1170), C.Wood, Wood, { Name = "SkiDock" })
		post(m, 2.4, 1, CFrame.new(1562, 0, 1171), C.White, nil, { CanCollide = false, Name = "Bollard" })
		for i, x in ipairs({ 1536, 1547, 1558 }) do
			local ski = CFrame.new(x, WATER_Y + 0.3, 1164.5)
			part(m, Vector3.new(6.5, 1.2, 2.6), ski, ({ N.Pink, N.Cyan, N.Yellow })[i], nil, { Name = "JetSki" })
			part(m, Vector3.new(2.6, 0.6, 1.3), ski * CFrame.new(-0.6, 0.9, 0), C.Asphalt, nil, { Name = "Seat" })
			trim(m, Vector3.new(0.4, 0.9, 2.2), ski * CFrame.new(1.6, 0.95, 0), C.White)
		end
	end

	--------------------------------------------------------------------------------------------------
	-- Marina office: pastel deco block facing the z = 1000 road, neon MARINA ROW on the roof
	--------------------------------------------------------------------------------------------------
	do
		local cf = CFrame.lookAt(Vector3.new(1230, 0, 1054), Vector3.new(1230, 0, 1000))
		local office = ArtKit.Deco(marina, cf, 44, 20, 26, { Color = C.Pastels[2], Trim = N.Cyan, Tiers = 1, Sign = "MARINA ROW", Name = "MarinaOffice" })
		part(office, Vector3.new(40, 1.2, 1), cf * CFrame.new(0, 20.6, -12.5), C.White, nil, { Name = "SignPlinth" }) -- sign sits on it
		light(office:FindFirstChild("Sign"), N.Cyan, 40, 1.6)
	end

	--------------------------------------------------------------------------------------------------
	-- Palm promenade along the north side of the z = 1000 road (split around Highway 1 at x 1000)
	--------------------------------------------------------------------------------------------------
	do
		local pf = ArtKit.Model(marina, "Promenade")
		for _, seg in ipairs({ { 472, 964 }, { 1036, 1446 } }) do
			part(pf, Vector3.new(seg[2] - seg[1], 0.3, 20), CFrame.new((seg[1] + seg[2]) / 2, 0.15, 968), Color3.fromRGB(240, 226, 200),
				Enum.Material.Pavement, { Name = "Promenade" })
		end
		local i = 0
		for x = 490, 1440, 40 do
			if spotOK(x, 962, 4, 4) then
				ArtKit.Palm(pf, Vector3.new(x, 0.3, 962), rng:NextNumber(1.3, 1.7), rng:NextNumber(0, math.pi * 2))
			end
			i += 1
			local mx = x + 20
			if mx < 1440 and spotOK(mx, 968, 7, 5) then
				if i % 2 == 1 then
					ArtKit.Bench(pf, CFrame.lookAt(Vector3.new(mx, 0.3, 972), Vector3.new(mx, 0.3, 980))) -- faces the road and marina
				else
					planter(pf, mx, 966, 0.3)
				end
			end
		end
	end

	--------------------------------------------------------------------------------------------------
	-- Waterfront: quay edge, rope posts (gap at the ski dock), iron bollards at each pier root, lamps
	--------------------------------------------------------------------------------------------------
	do
		local wf = ArtKit.Model(marina, "Waterfront")
		for _, r in ipairs({ { 612, 1088 }, { 1112, 1288 }, { 1312, 1638 }, { 1662, 1996 } }) do
			part(wf, Vector3.new(3, 0.5, r[2] - r[1]), CFrame.new(1498, 0.25, (r[1] + r[2]) / 2), C.White, Enum.Material.Concrete, { Name = "QuayEdge" })
		end
		local rope = Color3.fromRGB(225, 200, 150)
		for _, run in ipairs({ { 1122, 1154 }, { 1186, 1282 }, { 1322, 1478 } }) do
			local prev
			for z = run[1], run[2], 16 do
				post(wf, 3, 0.8, CFrame.new(1492, 0, z), C.White, nil, { CanCollide = false, Name = "RopePost" })
				local top = Vector3.new(1492, 2.6, z)
				if prev then
					bar(wf, prev, top, 0.3, rope)
				end
				prev = top
			end
		end
		for _, pz in ipairs(PIERS) do
			for _, s in ipairs({ -1, 1 }) do
				post(wf, 2.2, 1.8, CFrame.new(1496, 0, pz + s * 13), C.Asphalt, Metal, { CanCollide = false, Name = "Bollard" })
			end
		end
		for i, z in ipairs({ 1040, 1200, 1250, 1350, 1440, 1560, 1610 }) do
			if spotOK(1482, z, 2, 2) then
				lamp(wf, 1482, z, i % 2 == 0 and N.Pink or N.Cyan, i <= 5)
			end
		end
	end

	--------------------------------------------------------------------------------------------------
	-- MARINA ROW pylon at the west entrance (MarinaLink x 450 / road z 1000)
	--------------------------------------------------------------------------------------------------
	if spotOK(488, 1036, 4, 4) then
		local m = ArtKit.Model(marina, "MarinaPylon")
		post(m, 27, 1.6, CFrame.new(488, 0, 1036), C.White, nil, { Name = "Pole" })
		local face = Vector3.new(-1, 0, -1).Unit -- toward traffic coming down MarinaLink from the north-west
		local pos = Vector3.new(488, 25, 1036) + face * 1.1 -- panels in front of the pole
		local cf = CFrame.lookAt(pos, pos + face)
		ArtKit.Sign(m, cf, "MARINA ROW", N.Pink, 20, 6)
		ArtKit.Sign(m, cf * CFrame.new(0, -5.5, 0), "BOATS - SEAFOOD - SUNSETS", N.Cyan, 18, 3)
	end

	--------------------------------------------------------------------------------------------------
	-- Barnacle Bob's Boat Repair: boats up on cradles in the open lot west of the highway
	--------------------------------------------------------------------------------------------------
	do
		local by = ArtKit.Model(marina, "BarnacleBobsBoatyard")
		for _, x in ipairs({ 540, 572, 604 }) do
			if spotOK(x, 1250, 12, 30) then
				for _, dz in ipairs({ -5, 5 }) do
					part(by, Vector3.new(7, 3, 2), CFrame.new(x, 1.5, 1250 + dz), C.DarkWood, Wood, { Name = "Cradle" })
				end
				-- Hull bottom = cf.Y - 1 = 3: resting on the cradles.
				ArtKit.Boat(by, CFrame.lookAt(Vector3.new(x, 4, 1250), Vector3.new(x, 4, 1249)), pick({ 20, 22, 24 }), pick(BOAT_COLORS))
			end
		end
		if spotOK(500, 1250, 4, 22) then
			for _, dz in ipairs({ -9, 9 }) do
				post(by, 12, 0.8, CFrame.new(500, 0, 1250 + dz), C.White, nil, { Name = "SignPost" })
			end
			local pos = Vector3.new(499.6, 10, 1250)
			ArtKit.Sign(by, CFrame.lookAt(pos, pos - Vector3.new(1, 0, 0)), "BARNACLE BOB'S BOAT REPAIR", N.Orange, 20, 5)
		end
		if spotOK(636, 1232, 12, 12) then
			crates(by, 636, 1232)
		end
	end

	local parts = 0
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	print(string.format("DocksMarina: %d parts, %d lights, %d containers", parts, lights, containers))
	return parts
end

return Art
