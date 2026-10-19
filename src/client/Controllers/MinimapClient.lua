-- MinimapClient (ModuleScript, StarterPlayerScripts.Controllers.MinimapClient)
-- Round minimap, top right under the heat stars (PRD HUD layout). Drawn from data the server
-- publishes, so it works for streamed-out areas too:
--   ground tiles + building footprints (ReplicatedStorage "MapShapes", MapService), roads (RoadGraph),
--   places (MapService "Places"/"OpenHeists"), and the GPS route (GPSClient).
-- How it's drawn: the map is a set of flat parts inside a ViewportFrame, filmed by a top-down camera
-- that turns with the player's camera (so "up" is where you're looking) and climbs when you drive
-- fast (zoom out). A ViewportFrame clips cleanly on every device. Blips are 2D labels on top,
-- placed with the same maths and pinned to the rim when they're off the map, like a compass.
-- While you're wanted: blue blips for police within ~400 studs (player cops and AI cars, pinned to the
-- rim) and your own search circle (server attributes SearchX/SearchZ/SearchR, HeatService). Roadblocks
-- (Workspace.Roadblocks) show for everyone, pinned to the rim while you're wanted.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local GPSClient = require(script.Parent:WaitForChild("GPSClient"))

local player = Players.LocalPlayer

local MinimapClient = {}

local MAX_SIZE = 170 -- pixels across
local NEAR_RADIUS = 170 -- studs shown from centre to rim when slow
local FAR_RADIUS = 330 -- when flat out
local FOV = 20

local COLORS = {
	water = Color3.fromRGB(38, 108, 160),
	grass = Color3.fromRGB(122, 186, 140),
	sand = Color3.fromRGB(236, 214, 168),
	concrete = Color3.fromRGB(170, 168, 190),
	wood = Color3.fromRGB(196, 160, 122),
	building = Color3.fromRGB(214, 200, 238),
	road = Color3.fromRGB(58, 56, 78),
	route = Color3.fromRGB(255, 62, 165),
}
local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local GOLD = Color3.fromRGB(255, 214, 10)
local MINT = Color3.fromRGB(110, 242, 196)
local DARK = Color3.fromRGB(18, 14, 30)
local BLUE = Color3.fromRGB(60, 120, 255)
local RED = Color3.fromRGB(255, 60, 60)
local POLICE_RANGE = 400

local gui, view, cam, overlay, ring, arrow, routeModel, mapModel
local staticParts = {} -- { part, pos, r } for culling
local size = MAX_SIZE
local radius = NEAR_RADIUS
local blips = {} -- [key] = { frame, pos, edge }
local routeStamp
local searchModel, searchStamp
local carKeys = setmetatable({}, { __mode = "k" }) -- [AI car] = number (stable blip keys)
local nextCarKey = 0

local function flatPart(parent, cf, sx, sz, y, color)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Size = Vector3.new(math.max(sx, 0.5), 0.2, math.max(sz, 0.5))
	p.CFrame = CFrame.new(cf.X, y, cf.Z) * (cf - cf.Position)
	p.Color = color
	p.Parent = parent
	return p
end

local function segment(parent, a, b, width, y, color)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	if len < 0.1 then
		return nil
	end
	local cf = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(b.X, 0, b.Z))
	return flatPart(parent, cf, width, len + width * 0.5, y, color)
end

local function buildStatic()
	local model = Instance.new("Model")
	model.Name = "Map"
	local ok, data = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("MapShapes") or "{}")
	end)
	if ok and data then
		for _, t in ipairs(data.t or {}) do
			flatPart(model, CFrame.new(t[1], 0, t[2]) * CFrame.Angles(0, math.rad(t[5]), 0), t[3], t[4], 0,
				COLORS[t[6]] or COLORS.grass)
		end
		for _, b in ipairs(data.b or {}) do
			flatPart(model, CFrame.new(b[1], 0, b[2]) * CFrame.Angles(0, math.rad(b[5]), 0), b[3], b[4], 0.6,
				COLORS.building)
		end
	end
	local drawn = {}
	for i, edges in pairs(RoadGraph.Edges) do
		for j in pairs(edges) do
			local key = i < j and (i .. ":" .. j) or (j .. ":" .. i)
			if not drawn[key] then
				drawn[key] = true
				segment(model, RoadGraph.Nodes[i], RoadGraph.Nodes[j], math.max(RoadGraph.Width(i, j) * 0.8, 20), 0.3,
					COLORS.road)
			end
		end
	end
	model.Parent = view
	-- Culling list: only parts near the player stay in the ViewportFrame (see cull()).
	for _, p in ipairs(model:GetChildren()) do
		table.insert(staticParts, { part = p, pos = p.Position, r = math.max(p.Size.X, p.Size.Z) / 2 * 1.42 })
	end
	mapModel = model
end

-- A ViewportFrame redraws every part it holds whenever the camera moves, so keep only what's close.
local CULL = FAR_RADIUS * 1.6
local function cull(pos)
	if not mapModel then
		return
	end
	local flat = Vector3.new(pos.X, 0, pos.Z)
	for _, rec in ipairs(staticParts) do
		local d = (Vector3.new(rec.pos.X, 0, rec.pos.Z) - flat).Magnitude - rec.r
		local want = d < CULL and mapModel or nil
		if rec.part.Parent ~= want then
			rec.part.Parent = want
		end
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Minimap"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	view = Instance.new("ViewportFrame")
	view.Name = "Map"
	view.AnchorPoint = Vector2.new(1, 0)
	view.Position = UDim2.new(1, -16, 0, 60)
	view.BackgroundColor3 = COLORS.water
	view.Ambient = Color3.fromRGB(230, 230, 230)
	view.LightColor = Color3.fromRGB(140, 140, 140)
	view.LightDirection = Vector3.new(0, -1, 0)
	view.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = view
	cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = view
	view.CurrentCamera = cam
	routeModel = Instance.new("Model")
	routeModel.Name = "Route"
	routeModel.Parent = view
	searchModel = Instance.new("Model")
	searchModel.Name = "Search"
	searchModel.Parent = view

	-- Blips, arrow and rim sit on top in a same-sized frame.
	overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.AnchorPoint = view.AnchorPoint
	overlay.Position = view.Position
	overlay.BackgroundTransparency = 1
	overlay.Parent = gui
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.5, 0)
	rc.Parent = overlay
	ring = Instance.new("UIStroke")
	ring.Color = PINK
	ring.Thickness = 3
	ring.Parent = overlay

	arrow = Instance.new("TextLabel")
	arrow.Name = "You"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromScale(0.5, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBlack
	arrow.TextScaled = true
	arrow.Text = "▲"
	arrow.TextColor3 = Color3.new(1, 1, 1)
	arrow.ZIndex = 20
	arrow.Parent = overlay
	local st = Instance.new("UIStroke")
	st.Color = DARK
	st.Thickness = 2
	st.Parent = arrow
end

-- Smaller on small (phone) screens.
local function fit()
	local vp = Workspace.CurrentCamera.ViewportSize
	size = math.floor(math.clamp(vp.Y * 0.22, 110, MAX_SIZE))
	view.Size = UDim2.fromOffset(size, size)
	overlay.Size = view.Size
	arrow.Size = UDim2.fromOffset(size * 0.13, size * 0.13)
end

local function blip(key, pos, text, color, px, edge)
	local b = blips[key]
	if not b then
		local f = Instance.new("TextLabel")
		f.Name = key
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Font = Enum.Font.GothamBlack
		f.TextScaled = true
		f.TextColor3 = DARK
		f.ZIndex = 10
		f.Parent = overlay
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
		local s = Instance.new("UIStroke")
		s.Color = Color3.new(1, 1, 1)
		s.Thickness = 1.5
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
		b = { frame = f }
		blips[key] = b
	end
	b.frame.Text = text or ""
	b.frame.BackgroundColor3 = color
	b.frame.Size = UDim2.fromOffset(px, px)
	b.pos = pos
	b.edge = edge -- pin to the rim when off the map (otherwise hide it)
	b.seen = true
end

-- Police near a wanted player, and roadblocks.
local function policeBlips(me)
	local wantedMe = player:GetAttribute("Side") == "Civilian" and (player:GetAttribute("Heat") or 0) > 0
	if wantedMe then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and p:GetAttribute("Side") == "Cop" then
				local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if r and r:IsA("BasePart") and (r.Position - me).Magnitude <= POLICE_RANGE then
					local key = "cop_" .. p.UserId
					blip(key, r.Position, "", BLUE, 11, true)
					blips[key].track = r
				end
			end
		end
		local vehicles = Workspace:FindFirstChild("Vehicles")
		for _, car in ipairs(vehicles and vehicles:GetChildren() or {}) do
			local chassis = car:GetAttribute("AIPolice") == true and car:IsA("Model") and car.PrimaryPart
			if chassis and (chassis.Position - me).Magnitude <= POLICE_RANGE then
				if not carKeys[car] then
					nextCarKey += 1
					carKeys[car] = nextCarKey
				end
				local key = "ai_" .. carKeys[car]
				blip(key, chassis.Position, "", BLUE, 11, true)
				blips[key].track = chassis
			end
		end
	end
	local folder = Workspace:FindFirstChild("Roadblocks")
	for i, rb in ipairs(folder and folder:GetChildren() or {}) do
		local pos = rb:GetAttribute("Pos")
		local part = rb:IsA("Model") and rb.PrimaryPart
		pos = part and part.Position or pos
		if typeof(pos) == "Vector3" then
			blip("rb_" .. i, pos, "X", RED, 15, wantedMe)
		end
	end
end

-- Your search circle while the stars are hollow: a red ring on the map.
local function refreshSearch()
	local x, z, r = player:GetAttribute("SearchX"), player:GetAttribute("SearchZ"), player:GetAttribute("SearchR")
	local stamp = "none"
	if type(x) == "number" and type(z) == "number" and type(r) == "number" and r > 0 then
		stamp = x .. "|" .. z .. "|" .. r
	end
	if stamp == searchStamp then
		return
	end
	searchStamp = stamp
	searchModel:ClearAllChildren()
	if stamp ~= "none" then
		local n = 32
		local prev
		for i = 0, n do
			local a = i / n * math.pi * 2
			local pt = Vector3.new(x + math.cos(a) * r, 0, z + math.sin(a) * r)
			if prev then
				segment(searchModel, prev, pt, 10, 1.6, RED)
			end
			prev = pt
		end
	end
end

local function refreshBlips(me)
	for _, b in pairs(blips) do
		b.seen = false
	end
	local ok, places = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("Places") or "[]")
	end)
	local open = {}
	for id in string.gmatch(ReplicatedStorage:GetAttribute("OpenHeists") or "", "[^,]+") do
		open[id] = true
	end
	local cop = player:GetAttribute("Side") == "Cop"
	for _, p in ipairs(ok and places or {}) do
		local pos = Vector3.new(p.x, 0, p.z)
		if p.c == "Heist" and open[p.id] and not cop then
			blip("h_" .. p.id, pos, "$", GOLD, 14, false)
		elseif p.n == "Hideout" and not cop then
			blip("hideout", pos, "H", PINK, 16, true)
		elseif p.n == "Police HQ" then
			blip("police", pos, "P", CYAN, 15, cop)
		elseif p.n == "Spray & Go" and not cop then
			blip("spray", pos, "S", MINT, 13, false)
		end
	end
	local target = GPSClient.TargetPos()
	if target then
		blip("gps", target, "★", PINK, 18, true)
	end
	-- Florida moments (EventService): pinned to the rim so you can go find them.
	local okE, events = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("Events") or "[]")
	end)
	for i, e in ipairs(okE and events or {}) do
		blip("event_" .. i .. "_" .. e.x .. "_" .. e.z, Vector3.new(e.x, 0, e.z), "!", MINT, 16, true)
	end
	-- Crewmates (their position is re-read every frame below).
	local crew = player:GetAttribute("Crew")
	if crew then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and p:GetAttribute("Crew") == crew then
				-- Their character when it's streamed in (smooth), else the server's CrewPos (every 1.5 s).
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				local x, z = string.match(p:GetAttribute("CrewPos") or "", "(-?%d+),(-?%d+)")
				local pos = root and root.Position or (x and Vector3.new(tonumber(x), 0, tonumber(z)))
				if pos then
					local okC, first = pcall(function()
						return utf8.char(utf8.codepoint(p.DisplayName, 1))
					end)
					blip("crew_" .. p.UserId, pos, okC and first or "?", MINT, 14, true)
					blips["crew_" .. p.UserId].track = root
				end
			end
		end
	end
	if me then
		policeBlips(me)
	end
	for key, b in pairs(blips) do
		if not b.seen then
			b.frame:Destroy()
			blips[key] = nil
		end
	end
end

-- The GPS re-plans every second with a fresh table; only redraw when the route itself changed
-- (ignoring the first point, which is just where you're standing).
local function refreshRoute()
	local points = GPSClient.RoutePoints()
	local stamp = "none"
	if points then
		stamp = #points .. "|" .. tostring(points[2]) .. "|" .. tostring(points[#points])
	end
	if stamp == routeStamp then
		return
	end
	routeStamp = stamp
	routeModel:ClearAllChildren()
	if points then
		for i = 2, #points - 1 do
			segment(routeModel, points[i], points[i + 1], 12, 1.2, COLORS.route)
		end
	end
end

function MinimapClient.Init()
	build()
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	task.spawn(function()
		for _ = 1, 60 do
			if RoadGraph.LoadPublished() and #RoadGraph.Nodes > 0 then
				break
			end
			task.wait(1)
		end
		buildStatic()
	end)
	local lastBlips = 0
	local camAcc = 0
	RunService.RenderStepped:Connect(function(dt)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local pos = root.Position
		local look = Workspace.CurrentCamera.CFrame.LookVector * Vector3.new(1, 0, 1)
		look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
		-- Zoom out with speed.
		local speed = root.AssemblyLinearVelocity.Magnitude
		local want = NEAR_RADIUS + (FAR_RADIUS - NEAR_RADIUS) * math.clamp(speed / 150, 0, 1)
		radius += (want - radius) * math.clamp(dt * 2, 0, 1)
		local height = radius / math.tan(math.rad(FOV / 2))
		local ground = Vector3.new(pos.X, 0, pos.Z)
		-- The map camera redraws the whole viewport, so move it at most 30 times a second.
		camAcc += dt
		if camAcc >= 1 / 30 then
			camAcc = 0
			cam.CFrame = CFrame.lookAt(ground + Vector3.new(0, height, 0), ground, look)
		end
		-- Arrow: where your character (or car) faces, relative to the view.
		local face = root.CFrame.LookVector
		local right = Vector3.new(-look.Z, 0, look.X)
		arrow.Rotation = math.deg(math.atan2(face:Dot(right), face:Dot(look)))
		-- Blips: same maths as the camera (up = look, right = right).
		local half = size / 2
		local pxPerStud = half / radius
		for _, b in pairs(blips) do
			if b.track and b.track.Parent then
				b.pos = b.track.Position
			end
			local rel = b.pos - ground
			local x, y = rel:Dot(right) * pxPerStud, -rel:Dot(look) * pxPerStud
			local d = math.sqrt(x * x + y * y)
			local limit = half - 8
			if d > limit then
				b.frame.Visible = b.edge == true
				if b.edge then
					x, y = x / d * limit, y / d * limit
				end
			else
				b.frame.Visible = true
			end
			b.frame.Position = UDim2.fromOffset(half + x, half + y)
		end
		if os.clock() - lastBlips > 1 then
			lastBlips = os.clock()
			refreshBlips(pos)
			refreshRoute()
			refreshSearch()
			cull(pos)
		end
		-- Wanted: the rim flashes red and blue.
		if (player:GetAttribute("Heat") or 0) > 0 then
			ring.Color = (os.clock() % 0.6 < 0.3) and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(60, 120, 255)
		else
			ring.Color = PINK
		end
		gui.Enabled = player:GetAttribute("Side") ~= "Prisoner"
	end)
end

return MinimapClient
