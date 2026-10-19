-- TrafficClient (ModuleScript, StarterPlayerScripts.Controllers.TrafficClient)
-- Ambient traffic, simulated on each player's own device (it costs the server nothing):
--   * Up to MAX_CARS pastel cars drive the RoadGraph around the camera, keeping right, two lanes
--     each way on Highway 1. They slow for corners and for the car ahead, and stop for anyone in
--     their lane.
--   * They're anchored and in collision group "Traffic", which doesn't collide with "Vehicles"
--     (players' cars), so a player's car never hits an immovable wall: when any car ploughs into one
--     above RAM_SPEED it gets knocked flying (unanchored, local physics) and fades away. Your own car
--     loses a little speed.
--   * Cars far from the camera are recycled into fresh spots out of sight.
--   * Headlights glow at night.
-- If ReplicatedStorage.TrafficModels has models (pivot at the bottom centre, front facing -Z), bodies
-- are cloned from those; otherwise simple greybox cars are built here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)

local player = Players.LocalPlayer

local TrafficClient = {}

local MAX_CARS = 14
local SPAWN_MIN, SPAWN_MAX = 160, 380 -- studs from the camera focus
local DESPAWN = 480
local STREET_SPEED, HIGHWAY_SPEED = 42, 68 -- studs/s
local RAM_SPEED = 25
local ROAD_TOP = 0.1

local PASTELS = {
	Color3.fromRGB(255, 180, 210), Color3.fromRGB(150, 230, 210), Color3.fromRGB(255, 214, 150),
	Color3.fromRGB(190, 170, 255), Color3.fromRGB(245, 245, 250), Color3.fromRGB(150, 200, 255),
	Color3.fromRGB(255, 150, 130), Color3.fromRGB(60, 60, 75), Color3.fromRGB(200, 60, 80),
}

local folder
local cars = {} -- list of car records
local ready = false
local night = false

------------------------------------------------------------------ car bodies

local function newPart(name, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false -- traffic stops for people instead; nothing can bump into it and get jolted
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.CollisionGroup = "Traffic"
	if shape then
		p.Shape = shape
	end
	return p
end

-- Returns model, list of { part, offset CFrame } for BulkMoveTo, half-size (Vector3).
local function buildCar()
	local W, H, L = 6.6, 1.8, 13
	local model = Instance.new("Model")
	model.Name = "TrafficCar"
	local color = PASTELS[math.random(#PASTELS)]
	local parts = {}
	local function add(part, offset)
		part.Parent = model
		table.insert(parts, { part = part, offset = offset })
		return part
	end
	local templates = ReplicatedStorage:FindFirstChild("TrafficModels")
	local list = templates and templates:GetChildren() or {}
	if #list > 0 then
		local body = list[math.random(#list)]:Clone()
		local _, ext = body:GetBoundingBox()
		W, H, L = ext.X, ext.Y * 0.45, ext.Z
		local pivot = body:GetPivot()
		for _, d in ipairs(body:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.CollisionGroup = "Traffic"
				if d:GetAttribute("BodyPaint") then
					d.Color = color
				end
				local rel = pivot:ToObjectSpace(d.CFrame)
				d.Parent = model
				table.insert(parts, { part = d, offset = rel })
			end
		end
		body:Destroy()
	else
		add(newPart("Body", Vector3.new(W, H, L), color), CFrame.new(0, H / 2 + 1.1, 0))
		add(newPart("Cabin", Vector3.new(W - 1.2, 2.2, L * 0.45), Color3.fromRGB(40, 50, 70), Enum.Material.Glass),
			CFrame.new(0, H + 1.1 + 1.1, L * 0.05)).Transparency = 0.3
		add(newPart("Roof", Vector3.new(W - 1.3, 0.25, L * 0.4), color), CFrame.new(0, H + 1.1 + 2.3, L * 0.05))
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				add(newPart("Wheel", Vector3.new(1, 2.4, 2.4), Color3.fromRGB(28, 28, 32), nil, Enum.PartType.Cylinder),
					CFrame.new(sx * (W / 2 - 0.3), 1.2, sz * (L / 2 - 2.4)))
			end
			add(newPart("Headlight", Vector3.new(1.3, 0.5, 0.2), Color3.fromRGB(255, 250, 220), Enum.Material.SmoothPlastic),
				CFrame.new(sx * (W / 2 - 1.1), H / 2 + 1.2, -L / 2 - 0.05))
			add(newPart("Taillight", Vector3.new(1.3, 0.5, 0.2), Color3.fromRGB(255, 40, 60), Enum.Material.Neon),
				CFrame.new(sx * (W / 2 - 1.1), H / 2 + 1.2, L / 2 + 0.05))
		end
	end
	model.Parent = folder
	return model, parts, Vector3.new(W / 2, H, L / 2)
end

local WARM = Color3.fromRGB(255, 244, 210)
local function setLights(car)
	for _, rec in ipairs(car.parts) do
		local part = rec.part
		if part.Name == "Headlight" then
			rec.baseColor = rec.baseColor or part.Color
			rec.baseMat = rec.baseMat or part.Material
			part.Material = night and Enum.Material.Neon or rec.baseMat
			part.Color = night and WARM or rec.baseColor
		end
	end
end

------------------------------------------------------------------ driving on the graph

local function neighbours(i)
	local list = {}
	for j in pairs(RoadGraph.Edges[i] or {}) do
		table.insert(list, j)
	end
	return list
end

-- Lateral offset from the road centre (to the right of travel) for a lane.
local function laneOffset(width, lane)
	if width >= 50 then
		return lane == 2 and width * 0.36 or width * 0.13
	end
	return width * 0.24
end

local function edgeInfo(a, b)
	local na, nb = RoadGraph.Nodes[a], RoadGraph.Nodes[b]
	local dir = nb - na
	local len = dir.Magnitude
	dir = len > 0 and dir / len or Vector3.new(0, 0, 1)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	return na, nb, dir, right, len
end

local function lanePos(car, t)
	local na, _, dir, right = edgeInfo(car.a, car.b)
	return na + dir * t + right * car.off
end

local function enterEdge(car, a, b, t)
	car.a, car.b, car.t = a, b, t or 0
	local width = RoadGraph.Width(a, b)
	if width < 50 then
		car.lane = 1
	elseif not car.lane then
		car.lane = math.random(2)
	end
	car.off = laneOffset(width, car.lane)
	local _, _, _, _, len = edgeInfo(a, b)
	car.len = len
	car.cruise = (width >= 50 and HIGHWAY_SPEED or STREET_SPEED) * (0.85 + math.random() * 0.3)
	-- Choose the next edge now, so we know how hard the turn at the end is.
	local options = {}
	for _, j in ipairs(neighbours(b)) do
		if j ~= a then
			table.insert(options, j)
		end
	end
	car.nextB = #options > 0 and options[math.random(#options)] or a
	local _, _, d1 = edgeInfo(a, b)
	local _, _, d2 = edgeInfo(b, car.nextB)
	car.turnDot = d1:Dot(d2) -- 1 straight, 0 right angle, -1 U-turn
end

local function focus()
	local cam = Workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or cam.Focus.Position
end

local function spawnCar()
	local here = focus()
	local flat = Vector3.new(here.X, 0, here.Z)
	local look = Workspace.CurrentCamera.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0 and look.Unit or Vector3.new(0, 0, -1)
	local nodes = RoadGraph.Nodes
	for _ = 1, 12 do
		local i = math.random(#nodes)
		local toNode = nodes[i] - flat
		local d = toNode.Magnitude
		-- Don't pop cars in right in front of the camera.
		local inView = d < 300 and toNode.Unit:Dot(look) > 0.4
		if d > SPAWN_MIN and d < SPAWN_MAX and not inView then
			local nb = neighbours(i)
			if #nb > 0 then
				local j = nb[math.random(#nb)]
				local model, parts, half = buildCar()
				local car = { model = model, parts = parts, half = half, speed = 0 }
				enterEdge(car, i, j, 0)
				car.t = math.random() * car.len * 0.6
				car.pos = lanePos(car, car.t)
				car.heading = select(3, edgeInfo(i, j))
				setLights(car)
				table.insert(cars, car)
				return
			end
		end
	end
end

local function removeCar(index)
	local car = cars[index]
	car.model:Destroy()
	table.remove(cars, index)
end

-- Something in this car's lane just ahead? Returns the gap (studs) or nil.
local blockParams = OverlapParams.new()
blockParams.FilterType = Enum.RaycastFilterType.Include
local function obstacleGap(car, cf)
	local best
	-- Other traffic on the same edge and lane.
	for _, other in ipairs(cars) do
		if other ~= car and not other.wrecked and other.a == car.a and other.b == car.b and other.lane == car.lane then
			local gap = other.t - car.t
			if gap > 0 and (not best or gap < best) then
				best = gap
			end
		end
	end
	-- Players (on foot or in cars) in a box ahead.
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local rel = cf:PointToObjectSpace(root.Position)
			if rel.Z < -car.half.Z and rel.Z > -car.half.Z - 26 and math.abs(rel.X) < car.half.X + 3 and math.abs(rel.Y) < 12 then
				local gap = -rel.Z - car.half.Z
				if not best or gap < best then
					best = gap
				end
			end
		end
	end
	return best
end

-- A car (player or AI) ploughing into this one? Knock it flying.
local function checkRam(car, cf)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return
	end
	for _, v in ipairs(vehicles:GetChildren()) do
		local chassis = v.PrimaryPart
		if chassis then
			local rel = cf:PointToObjectSpace(chassis.Position)
			local size = chassis.Size
			if math.abs(rel.X) < car.half.X + size.X / 2 - 0.5 and math.abs(rel.Z) < car.half.Z + size.Z / 2 - 0.5
				and math.abs(rel.Y) < 6 then
				local vel = chassis.AssemblyLinearVelocity
				if vel.Magnitude > RAM_SPEED then
					car.wrecked = os.clock()
					require(script.Parent:WaitForChild("SoundClient")).Play("Crash", cf.Position)
					-- A scripted tumble (no loose physics parts to fling anyone): a ballistic arc away
					-- from the hit with a spin, then a fade (see step()).
					local away = (cf.Position - chassis.Position) * Vector3.new(1, 0, 1)
					away = away.Magnitude > 0 and away.Unit or vel.Unit
					car.fly = {
						from = cf,
						vel = vel * 0.6 + away * 22 + Vector3.new(0, 32, 0),
						spin = Vector3.new(math.random(-5, 5), math.random(-7, 7), math.random(-5, 5)),
					}
					-- Our own car pays a little for it.
					if v:GetAttribute("DriverUserId") == player.UserId then
						chassis.AssemblyLinearVelocity = vel * 0.8
					end
					return
				end
			end
		end
	end
end

local moveParts, moveCFrames = {}, {}

local function step(dt)
	if not ready then
		return
	end
	local here = focus()
	local flat = Vector3.new(here.X, 0, here.Z)
	-- Recycle far or long-wrecked cars; top up.
	for i = #cars, 1, -1 do
		local car = cars[i]
		local far = (Vector3.new(car.pos.X, 0, car.pos.Z) - flat).Magnitude > DESPAWN
		if far or (car.wrecked and os.clock() - car.wrecked > 2.8) then
			removeCar(i)
		end
	end
	-- Performance mode (phone SETTINGS) keeps fewer cars around.
	local perf = require(script.Parent:WaitForChild("SettingsClient")).Get("Performance")
	if #cars < (perf and 6 or MAX_CARS) then
		spawnCar()
	elseif perf and #cars > 6 then
		removeCar(#cars)
	end

	table.clear(moveParts)
	table.clear(moveCFrames)
	for _, car in ipairs(cars) do
		if car.wrecked then
			local f = car.fly
			if f then
				local t = os.clock() - car.wrecked
				local pos = f.from.Position + f.vel * t + Vector3.new(0, -60, 0) * t * t
				pos = Vector3.new(pos.X, math.max(pos.Y, ROAD_TOP + 1), pos.Z)
				local rot = CFrame.Angles(f.spin.X * t, f.spin.Y * t, f.spin.Z * t)
				local cfw = CFrame.new(pos) * (f.from - f.from.Position) * rot
				local fade = math.clamp((t - 1.6) / 1, 0, 1)
				for _, rec in ipairs(car.parts) do
					table.insert(moveParts, rec.part)
					table.insert(moveCFrames, cfw * rec.offset)
					if fade > 0 then
						rec.part.LocalTransparencyModifier = fade
					end
				end
			end
			continue
		end
		-- Target speed: cruise, slower into sharp turns, stop behind obstacles.
		local target = car.cruise
		local toEnd = car.len - car.t
		if toEnd < 40 and car.turnDot < 0.7 then
			target = math.min(target, 16 + 20 * math.max(car.turnDot, 0))
		end
		local cf = CFrame.lookAt(car.pos, car.pos + car.heading)
		local gap = obstacleGap(car, cf + Vector3.new(0, ROAD_TOP + 2, 0))
		if gap then
			target = math.min(target, math.max(0, (gap - 8) * 1.5))
		end
		local accel = target > car.speed and 14 or 40
		car.speed += math.clamp(target - car.speed, -accel * dt, accel * dt)
		car.t += car.speed * dt
		if car.t >= car.len then
			local over = car.t - car.len
			local a, b = car.b, car.nextB
			enterEdge(car, a, b, over)
		end
		-- Blend smoothly into the new lane position after a turn.
		local want = lanePos(car, car.t)
		local newPos = car.pos:Lerp(want, math.clamp(dt * 8, 0, 1))
		local moved = newPos - car.pos
		if moved.Magnitude > 0.01 then
			car.heading = car.heading:Lerp(moved.Unit, math.clamp(dt * 10, 0, 1)).Unit
		end
		car.pos = newPos
		cf = CFrame.lookAt(car.pos, car.pos + car.heading) + Vector3.new(0, ROAD_TOP, 0)
		checkRam(car, cf + Vector3.new(0, 2, 0))
		if not car.wrecked then
			for _, rec in ipairs(car.parts) do
				table.insert(moveParts, rec.part)
				table.insert(moveCFrames, cf * rec.offset)
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function TrafficClient.Count()
	return #cars
end

function TrafficClient.Init()
	folder = Instance.new("Folder")
	folder.Name = "Traffic"
	folder.Parent = Workspace
	night = Workspace:GetAttribute("IsNight") == true
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		night = Workspace:GetAttribute("IsNight") == true
		for _, car in ipairs(cars) do
			setLights(car)
		end
	end)
	task.spawn(function()
		for _ = 1, 60 do
			if RoadGraph.LoadPublished() and #RoadGraph.Nodes > 0 then
				ready = true
				return
			end
			task.wait(1)
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return TrafficClient
