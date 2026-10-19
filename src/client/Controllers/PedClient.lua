-- PedClient (ModuleScript, StarterPlayerScripts.Controllers.PedClient)
-- Pedestrians on the sidewalks around you, simulated on your own device (like TrafficClient):
--   * Up to MAX_PEDS walkers cloned from ReplicatedStorage.PedTemplates (PedService), strolling
--     beside the roads of the RoadGraph (a sidewalk offset from each road edge), turning at corners.
--   * They dive out of the way of fast cars, and anyone who gets bumped just falls over and gets back
--     up. No damage, nothing gory: this is a kid-friendly game.
--   * Far-away walkers are recycled near the camera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)

local player = Players.LocalPlayer

local PedClient = {}

local MAX_PEDS = 12
local SPAWN_MIN, SPAWN_MAX = 60, 230
local DESPAWN = 320
local WALK_ANIM = "rbxassetid://507777826" -- Roblox's default R15 walk
local ROAD_TOP = 0.1

local folder
local peds = {}
local ready = false
local walkAnim

local function neighbours(i)
	local list = {}
	for j in pairs(RoadGraph.Edges[i] or {}) do
		table.insert(list, j)
	end
	return list
end

-- A point on the sidewalk beside the road a->b, t studs along it, on `side` (+1 right, -1 left).
local function sidewalk(a, b, t, side)
	local na, nb = RoadGraph.Nodes[a], RoadGraph.Nodes[b]
	local dir = (nb - na)
	local len = dir.Magnitude
	dir = len > 0 and dir / len or Vector3.new(0, 0, 1)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local off = RoadGraph.Width(a, b) / 2 + 5
	local p = na + dir * math.clamp(t, 0, len) + right * off * side
	return Vector3.new(p.X, ROAD_TOP + 3, p.Z), len
end

local function focus()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or Workspace.CurrentCamera.Focus.Position
end

local function spawnPed()
	local templates = ReplicatedStorage:FindFirstChild("PedTemplates")
	local list = templates and templates:GetChildren() or {}
	if #list == 0 then
		return
	end
	local here = focus()
	local flat = Vector3.new(here.X, 0, here.Z)
	local nodes = RoadGraph.Nodes
	for _ = 1, 10 do
		local i = math.random(#nodes)
		local nb = neighbours(i)
		if #nb > 0 then
			local j = nb[math.random(#nb)]
			local _, len = sidewalk(i, j, 0, 1)
			local t = math.random() * len
			local side = math.random(2) == 1 and 1 or -1
			local pos = sidewalk(i, j, t, side)
			local d = (Vector3.new(pos.X, 0, pos.Z) - flat).Magnitude
			-- Only where the ground is actually there (streamed in) and not right on top of the player.
			local ground = Workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -40, 0))
			if d > SPAWN_MIN and d < SPAWN_MAX and ground then
				local model = list[math.random(#list)]:Clone()
				local hum = model:FindFirstChildOfClass("Humanoid")
				local root = model:FindFirstChild("HumanoidRootPart")
				if not hum or not root then
					model:Destroy()
					return
				end
				hum.WalkSpeed = 5 + math.random() * 3
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanQuery = false
						part.CastShadow = false
						-- "Traffic" group: players' cars pass through (react() handles the bump).
						part.CollisionGroup = "Traffic"
					end
				end
				model:PivotTo(CFrame.new(ground.Position + Vector3.new(0, 3, 0)))
				model.Parent = folder
				local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
				local track = animator:LoadAnimation(walkAnim)
				track.Looped = true
				track:Play()
				local ped = { model = model, hum = hum, root = root, a = i, b = j, t = t, side = side, track = track }
				-- Walk to the end of this stretch.
				ped.target = sidewalk(i, j, len, side)
				hum:MoveTo(ped.target)
				table.insert(peds, ped)
				return
			end
		end
	end
end

local function nextLeg(ped)
	local options = {}
	for _, k in ipairs(neighbours(ped.b)) do
		if k ~= ped.a then
			table.insert(options, k)
		end
	end
	local k = #options > 0 and options[math.random(#options)] or ped.a
	ped.a, ped.b = ped.b, k
	local _, len = sidewalk(ped.a, ped.b, 0, ped.side)
	ped.target = sidewalk(ped.a, ped.b, len, ped.side)
	ped.hum:MoveTo(ped.target)
end

local function removePed(i)
	local ped = peds[i]
	ped.model:Destroy()
	table.remove(peds, i)
end

-- Fast cars nearby: jump aside. Bumped: fall over, get up after a moment.
local function react(ped, now)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles or (ped.busyUntil and now < ped.busyUntil) then
		return
	end
	for _, car in ipairs(vehicles:GetChildren()) do
		local chassis = car.PrimaryPart
		if chassis then
			local rel = ped.root.Position - chassis.Position
			local vel = chassis.AssemblyLinearVelocity
			local dist = rel.Magnitude
			if dist < 7 and vel.Magnitude > 8 then
				ped.hum:ChangeState(Enum.HumanoidStateType.FallingDown)
				ped.root.AssemblyLinearVelocity = vel * 0.5 + Vector3.new(0, 25, 0)
				ped.busyUntil = now + 2.5
				task.delay(2.2, function()
					if ped.hum.Parent then
						ped.hum:ChangeState(Enum.HumanoidStateType.GettingUp)
						ped.hum:MoveTo(ped.target)
					end
				end)
				return
			elseif dist < 26 and vel.Magnitude > 30 and vel.Unit:Dot(rel.Unit) > 0.7 then
				-- Dive sideways out of the car's path.
				local side = vel.Unit:Cross(Vector3.yAxis)
				if side:Dot(rel) < 0 then
					side = -side
				end
				ped.hum.Jump = true
				ped.hum:MoveTo(ped.root.Position + side * 10)
				ped.busyUntil = now + 1.2
				task.delay(1.3, function()
					if ped.hum.Parent then
						ped.hum:MoveTo(ped.target)
					end
				end)
				return
			end
		end
	end
end

local function step()
	if not ready then
		return
	end
	local here = focus()
	local flat = Vector3.new(here.X, 0, here.Z)
	local now = os.clock()
	for i = #peds, 1, -1 do
		local ped = peds[i]
		if not ped.model.Parent or (Vector3.new(ped.root.Position.X, 0, ped.root.Position.Z) - flat).Magnitude > DESPAWN
			or ped.root.Position.Y < -20 then
			removePed(i)
		else
			if not (ped.busyUntil and now < ped.busyUntil) then
				local toTarget = (ped.target - ped.root.Position) * Vector3.new(1, 0, 1)
				if toTarget.Magnitude < 4 then
					nextLeg(ped)
				elseif now - (ped.lastMove or 0) > 6 then
					-- Humanoid:MoveTo gives up after 8 s; keep nudging it.
					ped.lastMove = now
					ped.hum:MoveTo(ped.target)
				end
			end
			react(ped, now)
		end
	end
	local perf = require(script.Parent:WaitForChild("SettingsClient")).Get("Performance")
	if #peds < (perf and 5 or MAX_PEDS) then
		spawnPed()
	elseif perf and #peds > 5 then
		removePed(#peds)
	end
end

function PedClient.Init()
	folder = Instance.new("Folder")
	folder.Name = "Peds"
	folder.Parent = Workspace
	walkAnim = Instance.new("Animation")
	walkAnim.AnimationId = WALK_ANIM
	task.spawn(function()
		for _ = 1, 60 do
			if RoadGraph.LoadPublished() and #RoadGraph.Nodes > 0 then
				ready = true
				return
			end
			task.wait(1)
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			step()
		end
	end)
end

return PedClient
