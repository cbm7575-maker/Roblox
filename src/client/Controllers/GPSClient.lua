-- GPSClient (ModuleScript, StarterPlayerScripts.Controllers.GPSClient)
-- The phone's GPS, and the line a race is driven along. Everything here is local to this player
-- (parts live under the camera). Two things can be drawn on the road:
--   * a TARGET (the phone's GPS): pick a place and a route follows the roads to it (A* over the
--     published RoadGraph), drawn as a line of slim white-gold dashes lying on the road (each one
--     points along it; the line thins out toward its far end), with a thin light pillar standing on a
--     flat disc at the destination. Within 40 studs of it a toast says you have arrived and the target
--     is dropped.
--     Its readout (ScreenGui "GPS", frame "Route", the name other controllers look for) sits in Theme's
--     Banner zone, flat "street" look: a dark panel as wide as its words (a long name is cut off with
--     dots before it grows past the zone), a small white arrow that turns to show which way the place
--     is from where the camera looks (up = straight ahead), the place's name in white Display capitals
--     and the distance in gold. It never takes a tap. It gives way to the other Banner pieces (a
--     mission's banner, the escape countdown, the prison timer, a shift's job line) and to
--     HUDController's big stamp where that reaches into the zone (phones), and never shows in prison or
--     on the first-join title screen (player attribute TitleScreen).
--   * a PATH (ActivityClient's race line and route preview): a ready-made polyline drawn as big flat
--     chevrons that point the way: one every 14 studs for the first 170 studs ahead of you, every
--     other one out to 520 studs, nothing behind you. Chevrons stay put on the road as you drive (only
--     the window moves), so the line never swims. A path WINS over a target: the dashes, pillar and
--     readout hide while it is up and come back when it is cleared (the target itself is kept).
-- Routes follow the roads from the nearest point of the nearest road, not from the nearest crossing,
-- so a route never starts by doubling back to a crossing behind you.
--   GPSClient.SetTarget(name, position)   start a route
--   GPSClient.Clear()                     drop the target (a path stays)
--   GPSClient.Target() -> name or nil; TargetPos()
--   GPSClient.RoutePoints() -> polyline for the minimap: the path if one is up, else the target's
--     route. The first point is skipped by the minimap ("where you are").
--   GPSClient.RouteColor() -> the path's colour while one is up (the minimap draws the path in it),
--     else nil (the minimap's own route colour)
--   GPSClient.MapGoal() -> position, glyph: the point the minimap pins as the goal. While a path is up
--     that is the path's own goal (the race's next checkpoint, with its number or a flag; nil for the
--     route preview), never the GPS target, which hides with the rest of the target. Otherwise the
--     target's position (glyph nil: the minimap's star).
--   GPSClient.SetPath(name, points, opts) -> true if it is showing. points = { Vector3 } (2 or more);
--     opts.Faint (a quiet preview line), opts.Color, opts.Height (fixed y, for water: no ground check),
--     opts.Goal (Vector3) + opts.GoalText (short string) for MapGoal.
--   GPSClient.ClearPath(name)             clears the path if it has this name (nil = whatever is up)
--   GPSClient.PathName() -> name or nil
--   GPSClient.PathProgress() -> studs off the line, the line's direction there (unit Vector3), the
--     nearest point on it, and how far along the path that point is (studs from the path's first
--     point); nil while there is no path (or no character). Refreshed about 12 x a second.
--   GPSClient.PathTurn(lookAhead, degrees) -> "Left" | "Right" | nil, studs to the bend: does the path
--     bend more than `degrees` (default 35) away from where it points now within `lookAhead` studs?
--   GPSClient.RoadRoute(from, to) -> { Vector3 } along the road centre lines (y = 0), or nil while the
--     road graph hasn't arrived / there is no way. Ends more than 25 studs off a road are kept as
--     they are (joined by a straight bit); closer ones are snapped onto the centre line.
--   GPSClient.GraphReady() -> true once the road graph is loaded
--   GPSClient.Distance(pos), GPSClient.FormatDistance(studs)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local GPSClient = {}

local C = Theme.Color
-- The target's route on the road: slim, clean, white-gold (the minimap draws the same route in the
-- HUD's gold). Nothing here is pink any more: the brand colour stays a thin accent on the HUD.
local ROUTE_COLOR = Color3.fromRGB(255, 236, 178)
local DOT_GAP = 14 -- studs from one route dash to the next
local DOT_COUNT = 56 -- about 780 studs of route shown ahead
local DASH = Vector3.new(0.9, 0.2, 4) -- one dash: width, thickness, length along the road
local DASH_UP = 0.35 -- studs above the road (clear of its surface and its markings)
local DASH_ALPHA = 0.2 -- the dash nearest you...
local DASH_FAR_ALPHA = 0.8 -- ...and the last one: the line thins out toward its far end
local PILLAR = Vector3.new(2.4, 400, 2.4) -- the destination's light pillar...
local PILLAR_ALPHA = 0.6
local BASE = Vector3.new(0.3, 14, 14) -- ...and the flat disc it stands on (a cylinder on its side: thickness first)
local BASE_ALPHA = 0.5
local READOUT_EVERY = 0.2 -- seconds between rewrites of the readout's distance
local ARRIVE = 40
local STUD_METERS = 0.28 -- same scale as the MPH gauge
local ROAD_SNAP = 25 -- a route end this close to a road's centre line counts as on the road

-- Path chevrons (the race line). Much bigger than the dots: a chevron is about 10 studs wide.
local CHEV_GAP = 14 -- studs between chevrons near you
local CHEV_COUNT = 40 -- pool size; must stay above (CHEV_FAR - CHEV_SKIP) / CHEV_GAP (= 37)
local CHEV_SKIP = 10 -- nothing closer ahead than this (it would sit under the car)
local CHEV_NEAR = 170 -- every chevron up to here, every other one beyond
local CHEV_FAR = 520 -- nothing further ahead than this
local CHEV_ARM = Vector3.new(2.2, 0.3, 8) -- one arm of the V
local CHEV_ANGLE = math.rad(40) -- how far each arm leans off the line
local PATH_EVERY = 0.08 -- seconds between path refreshes
local PATH_COLOR = C.BrandAlt -- cyan: nothing else on the road is (GPS dashes white-gold, rings gold)

-- Each arm relative to a CFrame that sits on the line and looks along it (the two meet at the tip).
local ARM_X = CHEV_ARM.Z / 2 * math.sin(CHEV_ANGLE)
local ARM_LEFT = CFrame.new(-ARM_X, 0, 0) * CFrame.Angles(0, -CHEV_ANGLE, 0)
local ARM_RIGHT = CFrame.new(ARM_X, 0.02, 0) * CFrame.Angles(0, CHEV_ANGLE, 0) -- 0.02 up: no flicker at the tip

local target -- { name, pos }
local lastPoints -- the target's route polyline (the minimap draws it too)
local folder, pillar, pillarBase
-- The readout's pieces (buildReadout sets them): gui, route (the frame "Route"), arrow, name, dist,
-- nameLimit (caps the name's width); hud (HUDController, found on first use; false = not there); and
-- what it says now: shownDist (the distance text), shownTurn (the arrow's angle), drawnAt (os.clock()).
local ui = { shownDist = "", shownTurn = 0, drawnAt = 0 }
local dots = {} -- the route's dashes
local chevrons = {} -- [slot] = { a, b, k = arc index it sits on, far, shown }
local chevronColor = PATH_COLOR
local graphReady = false
local lastRoute = 0

local path -- { name, points, cum, total, route, color, height, nearAlpha, farAlpha, goal, goalText }
local lastPathDraw = 0
-- Where the player is on the path (progOff nil = unknown): studs off it, the stretch, the nearest
-- point, the line's direction there, and how far along the path that point is.
local progOff, progSeg, progPoint, progDir, progAlong

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local rayRoads, rayGround -- the folders the filter holds now

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function groundY(x, z, default)
	local city = Workspace:FindFirstChild("City")
	if not city then
		return default
	end
	-- Rebuild the filter only when the folders change (it used to be a fresh table for every dot).
	local roads, ground = city:FindFirstChild("Roads"), city:FindFirstChild("Ground")
	if roads ~= rayRoads or ground ~= rayGround then
		rayRoads, rayGround = roads, ground
		local list = {}
		if roads then
			table.insert(list, roads)
		end
		if ground then
			table.insert(list, ground)
		end
		rayParams.FilterDescendantsInstances = list
	end
	local hit = Workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -120, 0), rayParams)
	return hit and hit.Position.Y or default
end

local function marker(name, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = ROUTE_COLOR
	p.Transparency = 1
	p.Parent = folder
	return p
end

-- The readout into the Banner zone, sized for this device. It is only as wide as its words, and never
-- wider than the zone: a long name gives way (cut off with dots), the distance never does.
local function placeReadout()
	local touch = Theme.IsTouch()
	local z = Theme.Zone("Banner", touch)
	local zoneW = z.Size.X.Scale * ui.gui.AbsoluteSize.X + z.Size.X.Offset
	ui.route.AnchorPoint = z.Anchor
	ui.route.Position = z.Pos
	ui.route.Size = UDim2.new(0, 0, z.Size.Y.Scale, z.Size.Y.Offset)
	local size = touch and 16 or 18
	ui.name.TextSize = size
	ui.dist.TextSize = size
	-- (130 px: the panel's margins, the arrow, the gaps and "12.3 km")
	ui.nameLimit.MaxSize = Vector2.new(math.max(70, zoneW - 130), math.huge)
end

-- The readout: [arrow] PLACE NAME  1.2 km on a flat dark panel. Labels and frames only: it never takes
-- a tap.
local function buildReadout()
	local gui = Instance.new("ScreenGui")
	gui.Name = "GPS"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- the zone map's coordinates (y = 0 is the very top of the screen)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	ui.gui = gui

	local panel = Instance.new("Frame")
	panel.Name = "Route"
	panel.AutomaticSize = Enum.AutomaticSize.X
	Theme.Panel(panel)
	panel.Active = false
	panel.Visible = false
	panel.Parent = gui
	ui.route = panel
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.Parent = panel

	-- The arrow, drawn from three bars (no font or image needed) pointing up. Turning the holder turns
	-- the bars with it.
	local arrow = Instance.new("Frame")
	arrow.Name = "Arrow"
	arrow.LayoutOrder = 1
	arrow.Size = UDim2.fromOffset(18, 18)
	arrow.BackgroundTransparency = 1
	arrow.Parent = panel
	ui.arrow = arrow
	local function bar(x, y, w, h, turn) -- centred on (x, y)
		local f = Instance.new("Frame")
		f.Name = "Bar"
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset(x, y)
		f.Size = UDim2.fromOffset(w, h)
		f.Rotation = turn
		f.BackgroundColor3 = C.Text
		f.BorderSizePixel = 0
		f.Parent = arrow
	end
	bar(9, 9.5, 2, 13, 0) -- the shaft
	bar(6.5, 4.5, 8, 2, -45) -- the head: "/" ...
	bar(11.5, 4.5, 8, 2, 45) -- ... and "\", meeting at the tip

	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.LayoutOrder = 2
	name.AutomaticSize = Enum.AutomaticSize.X
	name.Size = UDim2.new(0, 0, 1, 0)
	name.Text = ""
	name.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.Text(name, 18, "Display")
	name.Parent = panel
	ui.name = name
	ui.nameLimit = Instance.new("UISizeConstraint")
	ui.nameLimit.Parent = name

	local dist = Instance.new("TextLabel")
	dist.Name = "Distance"
	dist.LayoutOrder = 3
	dist.AutomaticSize = Enum.AutomaticSize.X
	dist.Size = UDim2.new(0, 0, 1, 0)
	dist.Text = ""
	Theme.Text(dist, 18, "Display")
	dist.TextColor3 = C.Gold -- gold = the goal
	dist.Parent = panel
	ui.dist = dist

	placeReadout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeReadout)
	local UserInputService = game:GetService("UserInputService")
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(placeReadout)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(placeReadout)
end

-- Safe to call more than once: ActivityClient starts before this controller and may ask for a path
-- before Init has run.
local function build()
	if folder then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "GPSRoute"
	folder.Parent = Workspace.CurrentCamera
	for i = 1, DOT_COUNT do
		dots[i] = marker("Dot", DASH) -- (the name is from when they were balls)
	end
	for i = 1, CHEV_COUNT do
		local a, b = marker("Chevron", CHEV_ARM), marker("Chevron", CHEV_ARM)
		a.Color, b.Color = chevronColor, chevronColor
		chevrons[i] = { a = a, b = b, k = nil, far = false, shown = false }
	end
	pillar = marker("Pillar", PILLAR)
	pillarBase = marker("PillarBase", BASE)
	pillarBase.Shape = Enum.PartType.Cylinder
	buildReadout()
end

local function hideRoute()
	for _, d in ipairs(dots) do
		d.Transparency = 1
	end
end

local function hidePath()
	for _, c in ipairs(chevrons) do
		if c.shown then
			c.shown = false
			c.a.Transparency = 1
			c.b.Transparency = 1
		end
		c.k = nil -- a new path must place every chevron again
	end
end

-- Pieces that own the Banner zone while they show (paths under PlayerGui): the readout gives way to
-- them (missions show distances on their own markers; the escape countdown and the prison / job timers
-- matter more).
local BANNER_OWNERS = { { "Mission", "Banner" }, { "Objective", "Escape" }, { "LawUI", "Prison" }, { "ActivityUI", "Job" },
	{ "BigScore", "Status" } }
local function bannerBusy()
	local playerGui = player:FindFirstChild("PlayerGui")
	for _, path in ipairs(BANNER_OWNERS) do
		local sg = playerGui and playerGui:FindFirstChild(path[1])
		local obj = sg and sg:FindFirstChild(path[2])
		if obj and obj:IsA("GuiObject") and obj.Visible and sg:IsA("ScreenGui") and sg.Enabled then
			return true
		end
	end
	return false
end

-- Would HUDController's big moment stamp draw over the readout right now? On a phone the Stamp zone
-- reaches up into the Banner zone. (HUDController is found on first use; the band's top is in the same
-- full-screen pixels as the zone map.)
local function stampOver()
	if ui.hud == nil then
		local module = script.Parent:FindFirstChild("HUDController")
		local ok, found = false, nil
		if module then
			ok, found = pcall(require, module)
		end
		ui.hud = ok and type(found) == "table" and found or false
	end
	local hud = ui.hud
	if not hud or type(hud.StampTop) ~= "function" then
		return false
	end
	if type(hud.IntroUp) == "function" and hud.IntroUp() then
		return true -- a mission intro's letterbox is up (HUDController.Intro)
	end
	local top = hud.StampTop()
	if type(top) ~= "number" then
		return false
	end
	local z = Theme.Zone("Banner", Theme.IsTouch())
	local viewY = ui.gui.AbsoluteSize.Y
	local height = z.Size.Y.Scale * viewY + z.Size.Y.Offset
	return top < z.Pos.Y.Scale * viewY + z.Pos.Y.Offset + (1 - z.Anchor.Y) * height
end

-- May the readout show right now? Never in prison (LawClient's release timer has the zone), on the
-- first-join title screen, under another Banner piece or under a big stamp. The dashes and the pillar
-- don't mind: they are out in the world.
local function readoutFree()
	return player:GetAttribute("Side") ~= "Prisoner" and player:GetAttribute("TitleScreen") ~= true
		and not bannerBusy() and not stampOver()
end

-- The target's dashes, pillar and readout only show while no path is up (a race line wins).
local function showTarget()
	local on = target ~= nil and path == nil
	pillar.Transparency = on and PILLAR_ALPHA or 1
	pillarBase.Transparency = on and BASE_ALPHA or 1
	local readout = on and readoutFree()
	if ui.route.Visible ~= readout then
		ui.route.Visible = readout
	end
	if not on then
		hideRoute()
	end
end

-- Which way the place is from where the camera looks, in degrees clockwise (0 = straight ahead, 90 =
-- to the right), flat on the map.
local function turnTo(pos)
	local cam = Workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not cam or not root then
		return 0
	end
	local look = cam.CFrame.LookVector
	if look.X * look.X + look.Z * look.Z < 0.01 then
		look = cam.CFrame.UpVector -- looking straight down: the top of the screen is "ahead"
	end
	local tx, tz = pos.X - root.Position.X, pos.Z - root.Position.Z
	if tx * tx + tz * tz < 1 then
		return 0 -- standing on it
	end
	-- Flat cross and dot products: facing +X, +Z is on the right.
	return math.deg(math.atan2(look.X * tz - look.Z * tx, look.X * tx + look.Z * tz))
end

-- Every frame while the readout shows: the arrow follows the camera (in 3 degree steps, so it is only
-- set when it really moved); the distance is rewritten a few times a second, when its words change.
local function drawReadout(dist)
	local turn = math.floor(turnTo(target.pos) / 3 + 0.5) * 3
	if turn ~= ui.shownTurn then
		ui.shownTurn = turn
		ui.arrow.Rotation = turn
	end
	local t = os.clock()
	if t - ui.drawnAt >= READOUT_EVERY then
		ui.drawnAt = t
		local words = GPSClient.FormatDistance(dist)
		if words ~= ui.shownDist then
			ui.shownDist = words
			ui.dist.Text = words
		end
	end
end

function GPSClient.Distance(pos)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	return (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
end

function GPSClient.FormatDistance(studs)
	local m = studs * STUD_METERS
	if m >= 1000 then
		return string.format("%.1f km", m / 1000)
	end
	return string.format("%d m", math.floor(m / 10 + 0.5) * 10)
end

-- Road routes --------------------------------------------------------------------------------------

-- The nearest point on any road's centre line: the two nodes of that stretch, the point, how far.
local function nearestEdge(pos)
	local nodes, edges = RoadGraph.Nodes, RoadGraph.Edges
	local bi, bj, bp, bd
	for i, a in ipairs(nodes) do
		local list = edges[i]
		if list then
			for j in pairs(list) do
				local b = nodes[j]
				if i < j and b then -- every stretch is listed from both ends: look at it once
					local ab = b - a
					local len2 = ab:Dot(ab)
					local t = len2 > 0 and math.clamp((pos - a):Dot(ab) / len2, 0, 1) or 0
					local p = a + ab * t
					local d = (pos - p).Magnitude
					if not bd or d < bd then
						bi, bj, bp, bd = i, j, p, d
					end
				end
			end
		end
	end
	return bi, bj, bp, bd
end

-- A* along the roads between two flat positions. Unlike RoadGraph.Path it starts and ends at the
-- nearest POINT of the nearest road (not the nearest crossing), so the way never begins or ends with
-- a trip to a crossing and back. Returns { road point by the start, crossings..., road point by the
-- goal }, the start's distance off the road, the goal's distance off the road; or nil.
local GOAL = 0 -- a made-up node id for the goal point (real ids start at 1)
local function roadPath(from, to)
	if not graphReady then
		return nil
	end
	local si, sj, sp, startOff = nearestEdge(from)
	local gi, gj, gp, goalOff = nearestEdge(to)
	if not si or not gi then
		return nil
	end
	local nodes, edges = RoadGraph.Nodes, RoadGraph.Edges
	local open, came, g, f = {}, {}, {}, {}
	-- We stand between si and sj: both are one straight bit of road away.
	for _, n in ipairs({ si, sj }) do
		g[n] = (nodes[n] - sp).Magnitude
		f[n] = g[n] + (nodes[n] - gp).Magnitude
		open[n] = true
	end
	if (si == gi and sj == gj) or (si == gj and sj == gi) then
		-- Start and goal on the same stretch: straight along it.
		g[GOAL] = (sp - gp).Magnitude
		f[GOAL] = g[GOAL]
		open[GOAL] = true
	end
	local steps = 0
	while next(open) do
		steps += 1
		if steps > 5000 then
			return nil
		end
		local current, bestF
		for n in pairs(open) do
			if not bestF or f[n] < bestF then
				current, bestF = n, f[n]
			end
		end
		if current == GOAL then
			local out = { sp }
			local function push(p)
				if (p - out[#out]).Magnitude > 3 then -- crossings right on top of an end add nothing
					table.insert(out, p)
				end
			end
			local chain = {}
			local n = came[GOAL]
			while n do
				table.insert(chain, n)
				n = came[n]
			end
			for i = #chain, 1, -1 do
				push(nodes[chain[i]])
			end
			push(gp)
			return out, startOff, goalOff
		end
		open[current] = nil
		if current == gi or current == gj then
			-- The goal sits on a stretch that ends at this crossing.
			local tentative = g[current] + (nodes[current] - gp).Magnitude
			if not g[GOAL] or tentative < g[GOAL] then
				came[GOAL] = current
				g[GOAL] = tentative
				f[GOAL] = tentative
				open[GOAL] = true
			end
		end
		for nb, len in pairs(edges[current]) do
			local tentative = g[current] + len
			if nodes[nb] and (not g[nb] or tentative < g[nb]) then
				came[nb] = current
				g[nb] = tentative
				f[nb] = tentative + (nodes[nb] - gp).Magnitude
				open[nb] = true
			end
		end
	end
	return nil
end

function GPSClient.GraphReady()
	return graphReady
end

function GPSClient.RoadRoute(fromPos, toPos)
	local from, to = flat(fromPos), flat(toPos)
	local points, startOff, goalOff = roadPath(from, to)
	if not points then
		return nil
	end
	if startOff > ROAD_SNAP then
		table.insert(points, 1, from)
	end
	if goalOff > ROAD_SNAP then
		table.insert(points, to)
	end
	return points
end

-- The target's dashes ---------------------------------------------------------------------------------

-- Lay the dashes along the polyline, starting at the player: each one flat on the road, pointing along
-- it, the line thinning out toward its far end.
local function drawRoute(points)
	local i = 1
	local carry = 12 -- start a little ahead of the player
	for s = 1, #points - 1 do
		local a, b = points[s], points[s + 1]
		local seg = b - a
		local len = seg.Magnitude
		local t = carry
		if len > 0.01 then
			local dir = seg / len
			while t < len and i <= DOT_COUNT do
				local p = a + dir * t
				local at = Vector3.new(p.X, groundY(p.X, p.Z, 0.1) + DASH_UP, p.Z)
				local far = (i - 1) / DOT_COUNT
				dots[i].CFrame = CFrame.lookAt(at, at + dir)
				dots[i].Transparency = DASH_ALPHA + (DASH_FAR_ALPHA - DASH_ALPHA) * far * far
				i += 1
				t += DOT_GAP
			end
		end
		carry = t - len
		if i > DOT_COUNT then
			break
		end
	end
	for k = i, DOT_COUNT do
		dots[k].Transparency = 1
	end
end

-- Stand the pillar and its disc on the ground at the target (looked up again with every route: the
-- ground there may only just have streamed in).
local function placeGoal()
	local pos = target.pos
	local y = groundY(pos.X, pos.Z, 0.1)
	pillar.CFrame = CFrame.new(pos.X, y + PILLAR.Y / 2, pos.Z)
	-- (a cylinder's round faces look along its X: turned to look up)
	pillarBase.CFrame = CFrame.new(pos.X, y + DASH_UP, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
end

local function route()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not target then
		hideRoute()
		return
	end
	placeGoal()
	local here = flat(root.Position)
	local dest = flat(target.pos)
	local points
	if (dest - here).Magnitude > 120 then
		local road, startOff, goalOff = roadPath(here, dest)
		if road then
			points = { here }
			for i, p in ipairs(road) do
				-- Already on a road: skip the point beside us on its centre line and head straight for
				-- the next crossing (it also keeps the minimap's route still while we drive).
				if i > 1 or startOff > ROAD_SNAP or #road == 1 then
					table.insert(points, p)
				end
			end
			if goalOff > ROAD_SNAP then
				table.insert(points, dest)
			end
		end
	end
	lastPoints = points or { here, dest }
	drawRoute(lastPoints)
end

function GPSClient.SetTarget(name, pos)
	build()
	target = { name = name, pos = pos }
	placeGoal()
	ui.name.Text = string.upper(tostring(name))
	ui.dist.Text = ""
	ui.shownDist, ui.drawnAt = "", 0 -- the next frame writes the distance
	showTarget()
	lastRoute = 0
end

function GPSClient.Clear()
	target = nil
	lastPoints = nil
	if folder then
		showTarget()
	end
end

function GPSClient.Target()
	return target and target.name or nil
end

function GPSClient.TargetPos()
	return target and target.pos or nil
end

function GPSClient.RoutePoints()
	if path then
		return path.route
	end
	return target and lastPoints or nil
end

function GPSClient.RouteColor()
	return path and path.color or nil
end

function GPSClient.MapGoal()
	if path then
		return path.goal, path.goalText
	end
	return target and target.pos or nil, nil
end

-- The path (race line) ------------------------------------------------------------------------------

-- The point `s` studs along the path and the line's direction there.
local function pointAt(p, s)
	local pts, cum = p.points, p.cum
	local lo, hi = 1, #pts - 1
	while lo < hi do -- the last stretch that starts at or before s
		local mid = (lo + hi + 1) // 2
		if cum[mid] <= s then
			lo = mid
		else
			hi = mid - 1
		end
	end
	local a, b = pts[lo], pts[lo + 1]
	local len = cum[lo + 1] - cum[lo]
	return a:Lerp(b, math.clamp((s - cum[lo]) / len, 0, 1)), (b - a) / len
end

local function drawPath()
	local p = path
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not p or not root then
		progOff = nil
		return
	end
	-- Where are we on the line? The nearest point of the nearest stretch.
	local pos = flat(root.Position)
	local pts, cum = p.points, p.cum
	local bestD, bestSeg, bestPoint, bestS
	for i = 1, #pts - 1 do
		local a = pts[i]
		local ab = pts[i + 1] - a
		local t = math.clamp((pos - a):Dot(ab) / ab:Dot(ab), 0, 1)
		local q = a + ab * t
		local d = (pos - q).Magnitude
		if not bestD or d < bestD then
			bestD, bestSeg, bestPoint, bestS = d, i, q, cum[i] + (cum[i + 1] - cum[i]) * t
		end
	end
	progOff, progSeg, progPoint, progAlong = bestD, bestSeg, bestPoint, bestS
	progDir = (pts[bestSeg + 1] - pts[bestSeg]) / (cum[bestSeg + 1] - cum[bestSeg])

	-- Chevrons sit at fixed spots along the path (every CHEV_GAP studs from its start), so they don't
	-- slide with the car; each pool slot holds the one spot in the window that maps to it. Only a slot
	-- whose spot changed is moved, which is one or two a refresh at speed.
	local kMin = math.ceil((bestS + CHEV_SKIP) / CHEV_GAP)
	local kMax = math.floor(math.min(p.total, bestS + CHEV_FAR) / CHEV_GAP)
	for slot, c in ipairs(chevrons) do
		local k = kMin + (slot - 1 - kMin) % CHEV_COUNT -- the first spot >= kMin that belongs to this slot
		local far = k * CHEV_GAP - bestS > CHEV_NEAR
		if k > kMax or (far and k % 2 == 1) then
			if c.shown then
				c.shown = false
				c.a.Transparency = 1
				c.b.Transparency = 1
			end
		else
			if c.k ~= k then
				c.k = k
				local q, dir = pointAt(p, k * CHEV_GAP)
				local y = p.height or (groundY(q.X, q.Z, 0.1) + 0.3)
				local base = CFrame.lookAt(Vector3.new(q.X, y, q.Z), Vector3.new(q.X + dir.X, y, q.Z + dir.Z))
				c.a.CFrame = base * ARM_LEFT
				c.b.CFrame = base * ARM_RIGHT
			end
			if not c.shown or c.far ~= far then
				c.shown, c.far = true, far
				local alpha = far and p.farAlpha or p.nearAlpha
				c.a.Transparency = alpha
				c.b.Transparency = alpha
			end
		end
	end
end

function GPSClient.SetPath(name, points, opts)
	if type(points) ~= "table" then
		return false
	end
	-- Our own flat copy, without points on top of each other (every stretch needs a direction).
	local pts, cum = {}, { 0 }
	for _, v in ipairs(points) do
		if typeof(v) == "Vector3" then
			local q = flat(v)
			local n = #pts
			if n == 0 then
				pts[1] = q
			elseif (q - pts[n]).Magnitude > 0.5 then
				pts[n + 1] = q
				cum[n + 1] = cum[n] + (q - pts[n]).Magnitude
			end
		end
	end
	if #pts < 2 then
		return false
	end
	build()
	local o = type(opts) == "table" and opts or {}
	local faint = o.Faint == true
	local color = typeof(o.Color) == "Color3" and o.Color or PATH_COLOR
	local goal = typeof(o.Goal) == "Vector3" and o.Goal or nil
	-- The minimap skips a route's first point ("where you are"), so the path's first point goes in twice.
	local shown = table.clone(pts)
	table.insert(shown, 1, pts[1])
	hidePath()
	path = {
		name = name,
		points = pts,
		cum = cum,
		total = cum[#pts],
		route = shown,
		color = color,
		height = type(o.Height) == "number" and o.Height or nil,
		nearAlpha = faint and 0.55 or 0.05,
		farAlpha = faint and 0.75 or 0.35,
		goal = goal,
		goalText = goal and type(o.GoalText) == "string" and o.GoalText or nil,
	}
	if color ~= chevronColor then
		chevronColor = color
		for _, c in ipairs(chevrons) do
			c.a.Color, c.b.Color = color, color
		end
	end
	showTarget() -- hides the target's dots, pillar and readout while the path is up
	lastPathDraw = os.clock()
	drawPath()
	return true
end

function GPSClient.ClearPath(name)
	if not path or (name ~= nil and path.name ~= name) then
		return
	end
	path = nil
	progOff = nil
	hidePath()
	showTarget() -- the target (if any) comes back
	lastRoute = 0
end

function GPSClient.PathName()
	return path and path.name or nil
end

function GPSClient.PathProgress()
	if not path or not progOff then
		return nil
	end
	return progOff, progDir, progPoint, progAlong
end

function GPSClient.PathTurn(lookAhead, degrees)
	local p = path
	if not p or not progOff then
		return nil
	end
	local pts = p.points
	local limit = math.cos(math.rad(degrees or 35))
	local dir = progDir
	local dist = (pts[progSeg + 1] - progPoint).Magnitude -- what is left of the stretch we are on
	local i = progSeg + 1
	while dist <= lookAhead and i < #pts do
		local step = pts[i + 1] - pts[i]
		local len = step.Magnitude
		local u = step / len
		if dir:Dot(u) < limit then
			-- Flat cross product: facing +X, +Z is on the right.
			return (dir.X * u.Z - dir.Z * u.X) > 0 and "Right" or "Left", dist
		end
		dist += len
		i += 1
	end
	return nil
end

function GPSClient.Init()
	build()
	player:GetAttributeChangedSignal("Side"):Connect(function()
		GPSClient.Clear()
	end)
	-- A boat called from far away waits at the marina: route there.
	task.spawn(function()
		require(ReplicatedStorage.Shared.Util.Remotes).Event("BoatDelivered").OnClientEvent:Connect(function(info)
			GPSClient.SetTarget("Your " .. (info.Name or "boat"), info.Pos)
			NotifyController.Show("Your " .. (info.Name or "boat") .. " is waiting at the marina. Follow the GPS!",
				C.Gold, "info")
		end)
	end)
	task.spawn(function()
		for _ = 1, 60 do
			if RoadGraph.LoadPublished() and #RoadGraph.Nodes > 0 then
				graphReady = true
				return
			end
			task.wait(1)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if path then
			-- The race line: refreshed often so it keeps up with a fast car. The target waits.
			local t = os.clock()
			if t - lastPathDraw >= PATH_EVERY then
				lastPathDraw = t
				drawPath()
			end
			return
		end
		if not target then
			return
		end
		local readout = readoutFree()
		if ui.route.Visible ~= readout then
			ui.route.Visible = readout -- a Banner-zone timer or a stamp came or went
		end
		local dist = GPSClient.Distance(target.pos)
		if dist then
			if dist < ARRIVE then
				NotifyController.Show("You've arrived: " .. tostring(target.name), C.Gold, "info")
				GPSClient.Clear()
				return
			end
			if readout then
				drawReadout(dist)
			end
		end
		if os.clock() - lastRoute > 1 then
			lastRoute = os.clock()
			route()
		end
	end)
end

return GPSClient
