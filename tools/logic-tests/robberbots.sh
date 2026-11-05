#!/bin/bash
# RobberBotService logic tests (NPC robbers for cops to chase): prelude + a stand-in world (a road grid, four
# heist sites, a clerk, cops and citizens as plain parts, kinematic stand-ins for RaceAIService's driving and
# for Humanoid:MoveTo) + Shared.Util.RobberBots and RobberBotService sources (as functions) + scenario.
# Checks the decisions (when bots exist, what they do, how they're caught, what the cop is paid), not the
# looks or the handling: Studio does those (launch/14-ROBBER-BOTS.md). Every line should read PASS.
H="$(cd "$(dirname "$0")" && pwd)"
L="${LUAU:-luau}" # the Luau CLI (github.com/luau-lang/luau releases); set LUAU to its path
SRC="${1:-$H/../../src/server/Services/RobberBotService.lua}" # another copy of RobberBotService.lua to test, if given
UTIL="$H/../../src/shared/Util/RobberBots.lua"
OUT="${TMPDIR:-${TEMP:-/tmp}}/theft-logic-tests"
mkdir -p "$OUT"

read -r -d '' STUBS <<'EOF'
math.randomseed(11)

------------------------------------------------------------------ maths
local V = {}
Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end
V.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return Vector3.new(0, 0, 0)
		end
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return rawget(V, k)
end
V.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then
		a, b = b, a
	end
	if type(b) == "table" then
		return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	return Vector3.new(a.X * b, a.Y * b, a.Z * b)
end
V.__div = function(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
V.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
V.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V.Dot = function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
V.Cross = function(a, b) return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
V.__type = "Vector3"
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.zAxis = Vector3.new(0, 0, 1)

-- CFrame: position + rotation columns (right, up, back); LookVector = -back, as Roblox.
local CF = {}
CFrame = {}
local function mk(p, r, u, b)
	return setmetatable({ p = p, r = r, u = u, b = b }, CF)
end
CF.__index = function(cf, k)
	if k == "Position" then
		return cf.p
	elseif k == "LookVector" then
		return -cf.b
	elseif k == "RightVector" then
		return cf.r
	elseif k == "UpVector" then
		return cf.u
	end
	return rawget(CF, k)
end
CF.__type = "CFrame"
local function rot(cf, v)
	return cf.r * v.X + cf.u * v.Y + cf.b * v.Z
end
CF.__mul = function(a, b)
	if getmetatable(b) == V then
		return a.p + rot(a, b)
	end
	return mk(a.p + rot(a, b.p), rot(a, b.r), rot(a, b.u), rot(a, b.b))
end
function CF.PointToObjectSpace(cf, v)
	local d = v - cf.p
	return Vector3.new(d:Dot(cf.r), d:Dot(cf.u), d:Dot(cf.b))
end
function CF.VectorToWorldSpace(cf, v)
	return rot(cf, v)
end
function CF.PointToWorldSpace(cf, v)
	return cf.p + rot(cf, v)
end
function CFrame.new(x, y, z)
	local p = type(x) == "table" and x or Vector3.new(x or 0, y or 0, z or 0)
	return mk(p, Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1))
end
function CFrame.lookAt(at, target)
	local look = (target - at).Unit
	if look.Magnitude < 0.5 then
		look = Vector3.new(0, 0, -1)
	end
	local right = look:Cross(Vector3.new(0, 1, 0)).Unit
	if right.Magnitude < 0.5 then
		right = Vector3.new(1, 0, 0)
	end
	local up = right:Cross(look)
	return mk(at, right, up, -look)
end
function CFrame.Angles(rx, ry, rz)
	-- yaw only is all the service turns by (runDirection); pitch/roll are ignored here
	local c, s = math.cos(ry), math.sin(ry)
	return mk(Vector3.zero, Vector3.new(c, 0, -s), Vector3.new(0, 1, 0), Vector3.new(s, 0, c))
end

Color3 = { fromRGB = function(r, g, b) return { R = r / 255, G = g / 255, B = b / 255 } end }
UDim = { new = function() return {} end }
UDim2 = { new = function() return {} end, fromOffset = function() return {} end, fromScale = function() return {} end }
Enum = setmetatable({}, { __index = function(_, cat)
	return setmetatable({}, { __index = function(_, item) return cat .. "." .. item end })
end })
RaycastParams = { new = function() return {} end }
OverlapParams = { new = function() return {} end }
Random = { new = function()
	return {
		NextNumber = function(_, a, b)
			a, b = a or 0, b or 1
			return a + math.random() * (b - a)
		end,
		NextInteger = function(_, a, b) return math.random(a, b) end,
	}
end }

------------------------------------------------------------------ instances
local Inst = {}
local function setParent(self, parent)
	local old = rawget(self, "_parent")
	if old then
		local kids = rawget(old, "_kids")
		for i, c in ipairs(kids) do
			if c == self then
				table.remove(kids, i)
				break
			end
		end
	end
	rawset(self, "_parent", parent)
	if parent then
		table.insert(rawget(parent, "_kids"), self)
	end
end
Inst.__index = function(self, k)
	if k == "Parent" then
		return rawget(self, "_parent")
	elseif k == "CFrame" and rawget(self, "_part") then
		return rawget(self, "_cf")
	elseif k == "Position" and rawget(self, "_part") then
		return rawget(self, "_cf").p
	end
	local m = rawget(Inst, k)
	if m ~= nil then
		return m
	end
	for _, c in ipairs(rawget(self, "_kids")) do
		if c.Name == k then
			return c
		end
	end
	return nil
end
Inst.__newindex = function(self, k, v)
	if k == "Parent" then
		setParent(self, v)
	elseif k == "CFrame" and rawget(self, "_part") then
		rawset(self, "_cf", v) -- (CFrame and Position live in _cf, so every write comes through here)
	elseif k == "Position" and rawget(self, "_part") then
		local cf = rawget(self, "_cf")
		rawset(self, "_cf", setmetatable({ p = v, r = cf.r, u = cf.u, b = cf.b }, getmetatable(cf)))
	else
		rawset(self, k, v)
	end
end
Inst.__type = "Instance"
local SIGNAL = newSignal
function new(class, props)
	local o = setmetatable({ _kids = {}, _attrs = {}, ClassName = class, Name = class, _sigs = {} }, Inst)
	if class == "Part" or class == "Seat" or class == "VehicleSeat" then
		rawset(o, "_part", true)
		rawset(o, "Size", Vector3.new(2, 2, 2))
		rawset(o, "_cf", CFrame.new())
		rawset(o, "AssemblyLinearVelocity", Vector3.zero)
		rawset(o, "AssemblyAngularVelocity", Vector3.zero)
		rawset(o, "Color", Color3.fromRGB(128, 128, 128))
	elseif class == "Humanoid" then
		rawset(o, "Health", 100)
		rawset(o, "WalkSpeed", 16)
		rawset(o, "HipHeight", 2)
		rawset(o, "Died", SIGNAL())
	elseif class == "ProximityPrompt" then
		rawset(o, "Enabled", true)
	end
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	return o
end
Instance = { new = function(class, parent)
	local o = new(class)
	if parent then
		o.Parent = parent
	end
	return o
end }
function Inst:IsA(c)
	local cl = self.ClassName
	if c == cl then
		return true
	end
	if c == "BasePart" then
		return rawget(self, "_part") == true
	end
	if c == "BaseScript" then
		return cl == "Script" or cl == "LocalScript"
	end
	if c == "Seat" then
		return cl == "Seat"
	end
	return false
end
function Inst:FindFirstChild(name, recursive)
	for _, c in ipairs(rawget(self, "_kids")) do
		if c.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(rawget(self, "_kids")) do
			local f = c:FindFirstChild(name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function Inst:FindFirstChildOfClass(class)
	for _, c in ipairs(rawget(self, "_kids")) do
		if c.ClassName == class then
			return c
		end
	end
	return nil
end
function Inst:GetChildren()
	local out = {}
	for _, c in ipairs(rawget(self, "_kids")) do
		table.insert(out, c)
	end
	return out
end
function Inst:GetDescendants()
	local out = {}
	local function walk(o)
		for _, c in ipairs(rawget(o, "_kids")) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function Inst:IsDescendantOf(a)
	local p = self.Parent
	while p do
		if p == a then
			return true
		end
		p = p.Parent
	end
	return false
end
function Inst:GetAttribute(k)
	return rawget(self, "_attrs")[k]
end
function Inst:SetAttribute(k, v)
	rawget(self, "_attrs")[k] = v
end
function Inst:Destroy()
	rawset(self, "_destroyed", true)
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
	self.Parent = nil
end
function Inst:Clone()
	local o = new(self.ClassName)
	for k, v in pairs(self) do
		if k ~= "_kids" and k ~= "_parent" and k ~= "_attrs" and k ~= "_sigs" and k ~= "Died" then
			rawset(o, k, v)
		end
	end
	for k, v in pairs(rawget(self, "_attrs")) do
		rawget(o, "_attrs")[k] = v
	end
	for _, c in ipairs(rawget(self, "_kids")) do
		c:Clone().Parent = o
	end
	if self.ClassName == "Model" and self.PrimaryPart then
		rawset(o, "PrimaryPart", o:FindFirstChild(self.PrimaryPart.Name))
	end
	return o
end
local function mainPart(m)
	return rawget(m, "PrimaryPart") or m:FindFirstChild("HumanoidRootPart")
end
function Inst:PivotTo(cf)
	local p = mainPart(self)
	if p then
		local old = p.CFrame
		p.CFrame = cf
		-- the rest of the model's parts follow (by position only: enough here)
		for _, d in ipairs(self:GetDescendants()) do
			if rawget(d, "_part") and d ~= p then
				d.Position = d.Position + (cf.Position - old.Position)
			end
		end
	end
end
function Inst:GetPivot()
	local p = mainPart(self)
	return p and p.CFrame or CFrame.new()
end
function Inst:SetNetworkOwner() end
function Inst:GetAttributeChangedSignal() return SIGNAL() end
-- Humanoid
function Inst:MoveTo(pos)
	rawset(self, "_moveTo", pos)
end
function Inst:UnequipTools() end
-- Animator
function Inst:LoadAnimation()
	return { Play = function() end, Stop = function() end, AdjustSpeed = function() end }
end

------------------------------------------------------------------ the world
local WS = new("Workspace")
WS.Name = "Workspace"
local Vehicles = new("Folder", { Name = "Vehicles", Parent = WS })
local NPCs = new("Folder", { Name = "NPCs", Parent = WS })
local HeistsFolder = new("Folder", { Name = "Heists", Parent = WS })
function WS:GetServerTimeNow() return clock() end
function WS:Raycast(origin, dir)
	if dir.Y < -1 and math.abs(dir.X) < 1e-6 and math.abs(dir.Z) < 1e-6 then
		if origin.Y >= 0 and origin.Y + dir.Y <= 0 then
			return { Position = Vector3.new(origin.X, 0, origin.Z), Instance = WS }
		end
		return nil
	end
	-- sight lines and running room: a wall stands along x = WALL_X (if set)
	if WALL_X and (origin.X - WALL_X) * (origin.X + dir.X - WALL_X) < 0 then
		return { Position = origin, Instance = WS }
	end
	return nil
end
function WS:GetPartBoundsInBox() return {} end
function WS:GetPartBoundsInRadius() return {} end

-- Road grid: crossings every 300 studs from -1500 to 1500, linked to their neighbours.
local RG = { Nodes = {}, Edges = {} }
local idx = {}
for x = -1500, 1500, 300 do
	for z = -1500, 1500, 300 do
		table.insert(RG.Nodes, Vector3.new(x, 0, z))
		idx[x .. "," .. z] = #RG.Nodes
		RG.Edges[#RG.Nodes] = {}
	end
end
for key, i in pairs(idx) do
	local x, z = string.match(key, "(-?%d+),(-?%d+)")
	x, z = tonumber(x), tonumber(z)
	for _, d in ipairs({ { 300, 0 }, { -300, 0 }, { 0, 300 }, { 0, -300 } }) do
		local j = idx[(x + d[1]) .. "," .. (z + d[2])]
		if j then
			RG.Edges[i][j] = 300
		end
	end
end
function RG.Width() return 40 end

-- Heist sites, 20 studs off a road.
SITES = {}
local function site(id, x, z)
	local m = new("Model", { Name = id .. "_" .. x, Parent = HeistsFolder })
	m:SetAttribute("HeistId", id)
	local point = new("Part", { Name = "RobPoint", Parent = m })
	point.Position = Vector3.new(x, 3, z)
	rawset(m, "PrimaryPart", point)
	table.insert(SITES, m)
	return m
end
site("ATM", 320, 600)
site("GlowMart", -620, -280)
site("FuelStop", 900, -920)
site("SparkleCo", -320, 1200)
-- A clerk at the Glow Mart.
local clerk = new("Model", { Name = "Clerk", Parent = NPCs })
clerk:SetAttribute("NPCKind", "Clerk")
clerk:SetAttribute("Site", SITES[2].Name)

local Heists = {
	Types = {
		GlowMart = { Display = "Glow Mart", Tier = 1, Hold = 8, Payout = { 1200, 1200 }, Heat = 1 },
		FuelStop = { Display = "Fuel Stop", Tier = 1, Hold = 10, Payout = { 1500, 1500 }, Heat = 1 },
		ATM = { Display = "ATM", Tier = 1, Hold = 12, Payout = { 900, 900 }, Heat = 1 },
		SparkleCo = { Display = "Sparkle & Co.", Tier = 2, Hold = 14, Payout = { 4000, 6000 }, Heat = 2 },
	},
	AlarmSeconds = 45,
}

------------------------------------------------------------------ services the bots use
FEED = {}
local Remotes = { Event = function(name)
	return {
		FireAllClients = function(_, kind, data)
			if name == "Feed" then
				table.insert(FEED, { kind = kind, data = data, t = clock() })
			end
		end,
		FireClient = function() end,
	}
end }
local HeatService = { ColorWord = function() return "blue" end }
PROMPTS = {} -- [root] = { onHeld, onHoldBegan }
PAID = {} -- { cop, bounty, stars, name }
ACTIVE = true -- ArrestService.IsActiveCop
local ArrestService = {
	IsActiveCop = function() return ACTIVE end,
	BotCuffPrompt = function(root, name, onHeld, onHoldBegan)
		local prompt = new("ProximityPrompt", { Name = "CuffPrompt", Parent = root })
		PROMPTS[root] = { onHeld = onHeld, onHoldBegan = onHoldBegan, prompt = prompt }
		return prompt
	end,
	RewardCop = function(cop, bounty, stars, name)
		table.insert(PAID, { cop = cop, bounty = bounty, stars = stars, name = name })
		cop:SetAttribute("Cash", (cop:GetAttribute("Cash") or 0) + bounty)
		return bounty
	end,
}
-- RaceAIService: a kinematic driver. It drives toward the end of its first leg at top x pace (instantly up
-- to speed), stops when told Done. ROUTES counts every Route call.
CARS = {}
ROUTES = 0
local Race = {}
function Race.Plan(_, start, cps)
	return { { start, cps[1] } }
end
function Race.Spawn(spec)
	local car = new("Model", { Name = "RaceBot", Parent = Vehicles })
	local chassis = new("Part", { Name = "Chassis", Parent = car })
	chassis.Size = Vector3.new(6, 3, 14)
	chassis.Color = spec.Paint or Color3.fromRGB(1, 2, 3)
	rawset(car, "PrimaryPart", chassis)
	local seat = new("VehicleSeat", { Name = "DriverSeat", Parent = car })
	seat.Size = Vector3.new(2, 1, 2)
	car:SetAttribute("RaceBot", true)
	car:SetAttribute("DisplayName", spec.Car)
	new("BillboardGui", { Name = "RacerName", Parent = chassis })
	car:PivotTo(spec.CFrame)
	seat.CFrame = chassis.CFrame * CFrame.new(-1.5, 0.5, 1)
	local bot = { car = car, chassis = chassis, top = spec.Top, pace = 1, held = true, done = false, legs = spec.Legs, maxSpeed = 124 }
	table.insert(CARS, bot)
	return bot
end
function Race.Release(b) b.held = false end
function Race.SetPace(b, f) b.pace = math.clamp(f, 0.5, 1.5) end
function Race.Done(b) b.done = true end
function Race.Route(b, legs)
	ROUTES += 1
	b.legs = legs
	b.done = false
end
function Race.SetTop(b, t) b.top = t end
function Race.Remove(b)
	b.removed = true
	b.car:Destroy()
end
local function driveCars(dt)
	for _, b in ipairs(CARS) do
		local ch = b.chassis
		if not b.removed and not b.held and not b.done and not ch.Anchored and b.legs and b.legs[1] then
			local goal = b.legs[1][#b.legs[1]]
			local to = Vector3.new(goal.X - ch.Position.X, 0, goal.Z - ch.Position.Z)
			local speed = b.top * b.pace
			if (b.car:GetAttribute("FlatUntil") or 0) > clock() then
				speed *= 0.4
			end
			if BLOCKED and BLOCKED[b] then
				speed = 0
			end
			if to.Magnitude > 1 then
				local step = math.min(to.Magnitude, speed * dt)
				local pos = ch.Position + to.Unit * step
				local cf = CFrame.lookAt(pos, pos + to.Unit)
				local seatOff = ch.CFrame:PointToObjectSpace(b.car.DriverSeat.Position)
				ch.CFrame = cf
				b.car.DriverSeat.CFrame = cf * CFrame.new(seatOff)
				ch.AssemblyLinearVelocity = to.Unit * (step / dt)
			else
				ch.AssemblyLinearVelocity = Vector3.zero
			end
		else
			ch.AssemblyLinearVelocity = Vector3.zero
		end
	end
end
-- Humanoid:MoveTo stand-in: every walking body goes straight for its goal at WalkSpeed (not while
-- stunned: RagdollStart sets _down).
local function walkBodies(dt)
	local folder = WS:FindFirstChild("RobberBots")
	for _, m in ipairs(folder and folder:GetChildren() or {}) do
		local hum = m:FindFirstChildOfClass("Humanoid")
		local root = m:FindFirstChild("HumanoidRootPart")
		local goal = hum and rawget(hum, "_moveTo")
		if root and goal and not rawget(m, "_down") then
			local to = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
			local step = math.min(to.Magnitude, hum.WalkSpeed * dt)
			if WALL_X and (root.Position.X - WALL_X) * (root.Position.X + (to.Unit * step).X - WALL_X) < 0 then
				step = 0
			end
			if to.Magnitude > 0.5 then
				root.Position = root.Position + to.Unit * step
				root.AssemblyLinearVelocity = to.Unit * (step / dt)
			else
				root.AssemblyLinearVelocity = Vector3.zero
			end
		elseif root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end
task.spawn(function()
	while true do
		task.wait(0.1)
		driveCars(0.1)
		walkBodies(0.1)
	end
end)
local Ragdoll = { Start = function(m, _, opts)
	rawset(m, "_down", true)
	task.delay(opts.Seconds or 3, function()
		rawset(m, "_down", nil)
	end)
	return true
end }
local CarBuilder = { PlayPose = function() end }
local Telemetry = { Custom = function() end }

------------------------------------------------------------------ players
local PlayersSvc = new("Players")
function PlayersSvc:GetPlayers()
	local out = {}
	for _, p in ipairs(rawget(self, "_kids")) do
		table.insert(out, p)
	end
	return out
end
function PlayersSvc:CreateHumanoidModelFromDescription()
	local m = new("Model", { Name = "Rig" })
	local root = new("Part", { Name = "HumanoidRootPart", Parent = m })
	local head = new("Part", { Name = "Head", Parent = m })
	head.Size = Vector3.new(1.2, 1.2, 1.2)
	head.Position = Vector3.new(0, 1.5, 0)
	new("Humanoid", { Name = "Humanoid", Parent = m })
	new("Script", { Name = "Animate", Parent = m })
	rawset(m, "PrimaryPart", root)
	return m
end
function person(name, side, pos)
	local p = new("Player", { Name = name, DisplayName = name, Parent = PlayersSvc })
	p:SetAttribute("Side", side)
	local char = new("Model", { Name = name })
	local root = new("Part", { Name = "HumanoidRootPart", Parent = char })
	root.Position = pos
	new("Humanoid", { Name = "Humanoid", Parent = char })
	rawset(p, "Character", char)
	return p
end
function moveTo(p, pos)
	p.Character.HumanoidRootPart.Position = pos
end

------------------------------------------------------------------ the game tree
local RS = new("ReplicatedStorage")
local SSS = new("ServerScriptService")
local SS = new("ServerStorage")
local Shared = { Config = { Heists = Heists }, Util = { Remotes = Remotes, RoadGraph = RG, Ragdoll = Ragdoll } }
rawset(RS, "Shared", Shared)
rawset(SSS, "Services", { HeatService = HeatService, ArrestService = ArrestService, RaceAIService = Race, Telemetry = Telemetry })
rawset(SS, "Tools", { CarBuilder = CarBuilder })
local PFS = { CreatePath = function()
	local path = { Status = "PathStatus.Success" }
	function path:ComputeAsync(a, b)
		self.wp = { { Position = a, Action = "PathWaypointAction.Walk" }, { Position = b, Action = "PathWaypointAction.Walk" } }
	end
	function path:GetWaypoints() return self.wp end
	return path
end }
local SERVICES = { Players = PlayersSvc, ReplicatedStorage = RS, ServerScriptService = SSS, ServerStorage = SS,
	PathfindingService = PFS, Workspace = WS }
game = { GetService = function(_, n) return SERVICES[n] end }
workspace = WS
typeof = function(v)
	local mt = getmetatable(v)
	if mt and rawget(mt, "__type") then
		return mt.__type
	end
	return type(v)
end
EOF

read -r -d '' HELPERS <<'EOF'
function sim(seconds)
	runUntil(clock() + seconds)
end
function bots()
	return Bots.Peek()
end
function count()
	local n = 0
	for _ in pairs(bots()) do
		n += 1
	end
	return n
end
function wanted()
	local list = {}
	for _, b in pairs(bots()) do
		if b.heat > 0 then
			table.insert(list, b)
		end
	end
	return list
end
function waitFor(fn, seconds)
	local stop = clock() + seconds
	while clock() < stop do
		local r = fn()
		if r then
			return r
		end
		sim(0.5)
	end
	return nil
end
function feeds(kind)
	local n = 0
	for _, f in ipairs(FEED) do
		if f.kind == kind then
			n += 1
		end
	end
	return n
end
function posOf(b)
	if b.walker then
		return b.walker.root.Position
	end
	return b.drive and b.drive.chassis.Position
end
function nearestPlayerDist(b)
	local best = math.huge
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		local r = p.Character and p.Character.HumanoidRootPart
		if r then
			best = math.min(best, (r.Position - posOf(b)).Magnitude)
		end
	end
	return best
end
EOF

scenario() {
	local name="$1" body="$2"
	local f="$OUT/robberbots_$name.luau"
	{
		cat "$H/prelude.luau"
		echo "$STUBS"
		echo 'Shared.Util.RobberBots = (function()'
		cat "$UTIL"
		echo 'end)()'
		echo 'Bots = (function()'
		cat "$SRC"
		echo 'end)()'
		echo "$HELPERS"
		echo 'Bots.Init()'
		echo 'sim(1)'
		echo "$body"
		echo 'if ERRORS then print("FAIL coroutine errors: " .. ERRORS) end'
		echo 'for _, l in ipairs(LOG) do print("WARN " .. l) end'
	} > "$f"
	echo "== $name"
	"$L" "$f" 2>&1 || echo "FAIL $name stopped with an error (above)"
}

scenario no_cop_no_bots '
local c = person("Cit", "Civilian", Vector3.new(0, 3, 0))
sim(20)
check("a citizen alone: no bots", count() == 0, count())
check("no cars built", #CARS == 0, #CARS)'

scenario cop_brings_two '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(4)
check("a cop on duty: 2 bots", count() == 2, count())
for id, b in pairs(bots()) do
	check(id .. " appeared 300+ studs from every player", nearestPlayerDist(b) >= 300, math.floor(nearestPlayerDist(b)))
	check(id .. " sits in its car", b.rider ~= nil and b.rider.Parent == b.drive.car)
	check(id .. " car tagged for clients", b.drive.car:GetAttribute("RobberBot") == id and b.drive.car:GetAttribute("RaceBot") == nil)
	check(id .. " racer name swapped for the NPC tag", b.drive.chassis:FindFirstChild("RacerName") == nil and b.drive.chassis:FindFirstChild("BotTag") ~= nil)
	check(id .. " record published", game:GetService("ReplicatedStorage").RobberBots:FindFirstChild(id) ~= nil)
end
local names = {}
for _, b in pairs(bots()) do names[b.name] = true end
local n = 0
for _ in pairs(names) do n += 1 end
check("two different names", n == 2, n)
sim(20)
check("cruising before any crime (first crime 25-45 s)", #wanted() == 0, #wanted())
check("they drive somewhere (routes planned)", ROUTES >= 2, ROUTES)'

scenario one_crime_per_cop '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(3)
Bots.Test(true)
local b = waitFor(function() return wanted()[1] end, 120)
check("a crime happens", b ~= nil, Bots.Status())
sim(60)
local busy = 0
for _, x in pairs(bots()) do
	if x.heat > 0 or x.crime then busy += 1 end
end
check("one cop: never two bots busy at once", busy <= 1, Bots.Status())'

scenario heist_crime '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(3)
Bots.Test(true)
-- only heists: drop the carjack from the menu by giving it no weight
local b
for _ = 1, 6 do
	b = waitFor(function()
		for _, x in pairs(bots()) do
			if x.crime and x.crime.kind == "Heist" and x.state == "Crime" then return x end
		end
	end, 60)
	if b then break end
end
check("a bot robs a store or ATM", b ~= nil, Bots.Status())
if b then
	local site = b.crime.site
	check("silent alarm at once", (site:GetAttribute("AlarmUntil") or 0) > clock())
	check("HeistAlarm feed (cops get DISPATCH)", feeds("HeistAlarm") >= 1, feeds("HeistAlarm"))
	check("store cooldown untouched", site:GetAttribute("ReopenAt") == nil)
	check("wanted record: Heat", (b.rec:GetAttribute("Heat") or 0) >= 1, b.rec:GetAttribute("Heat"))
	check("wanted record: LastSeen", typeof(b.rec:GetAttribute("LastSeen")) == "Vector3")
	check("wanted record: outfit clue on foot", b.rec:GetAttribute("SuspectOutfit") ~= nil, b.rec:GetAttribute("SuspectOutfit"))
	check("wanted record: OnFoot", b.rec:GetAttribute("OnFoot") == true)
	if site:GetAttribute("HeistId") == "GlowMart" then
		check("clerk hands up", clerk:GetAttribute("Pose") == "HandsUp", clerk:GetAttribute("Pose"))
	end
	local done = waitFor(function() return b.state == "Flee" or b.state == "WalkBack" end, 30)
	check("robbery done: back to the car / away", done ~= nil, b.state)
	check("bag filled", b.bag > 0, b.bag)
	check("clerk hands down again", clerk:GetAttribute("Pose") == nil)
	local fleeing = waitFor(function() return b.state == "Flee" end, 30)
	check("drives off wanted", fleeing ~= nil and b.rider ~= nil, b.state)
	check("car clue once driving", b.rec:GetAttribute("SuspectCar") ~= nil, b.rec:GetAttribute("SuspectCar"))
end'

scenario store_with_citizen_skipped '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
-- a citizen hangs around every store but the Fuel Stop
local cits = {}
for i, s in ipairs(SITES) do
	if s:GetAttribute("HeistId") ~= "FuelStop" then
		cits[i] = person("Cit" .. i, "Civilian", s.RobPoint.Position + Vector3.new(30, 0, 0))
	end
end
sim(3)
Bots.Test(true)
local seen = {}
local stop = clock() + 240
while clock() < stop do
	for _, b in pairs(bots()) do
		if b.crime and b.crime.kind == "Heist" and b.state == "Crime" then
			seen[b.crime.site:GetAttribute("HeistId")] = true
		end
	end
	sim(1)
end
local other = false
for id in pairs(seen) do
	if id ~= "FuelStop" then other = true end
end
check("never a store with a real player near it", not other, next(seen))'

scenario taser_and_cuff_on_foot '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(3)
Bots.Test(true)
local b = waitFor(function()
	for _, x in pairs(bots()) do
		if x.heat > 0 and x.walker and x.state ~= "Caught" then return x end
	end
end, 200)
check("a wanted bot on foot", b ~= nil, Bots.Status())
if b then
	local root = b.walker.root
	moveTo(cop, root.Position + Vector3.new(8, 0, 0))
	check("can be tased", Bots.CanTase(b.walker.model))
	local heat, bag = b.heat, b.bag
	Bots.Stun(b.walker.model, 3, cop)
	check("not twice in a row", not Bots.CanTase(b.walker.model))
	moveTo(cop, b.walker.root.Position + Vector3.new(5, 0, 0))
	local pr = PROMPTS[b.walker.root]
	check("its body has a Cuff prompt", pr ~= nil)
	local ok = pr.onHeld(cop)
	check("cuffed while stunned", ok == true, b.state)
	check("state Caught", b.state == "Caught", b.state)
	local paid = PAID[#PAID]
	local expect = 500 * heat + math.floor(bag * 0.25)
	check("cop paid $500 a star + 25% of the bag", paid and paid.bounty == expect, paid and (paid.bounty .. " vs " .. expect))
	check("arrest feed names the bot", feeds("Arrest") == 1 and FEED[#FEED].data.Name == b.name)
	check("record cleared", b.rec:GetAttribute("Heat") == nil)
	check("hands up while taken away", b.walker and b.walker.model:GetAttribute("Pose") == "HandsUp")
	sim(6)
	check("caught bot gone", bots()[b.id] ~= b)
	check("its record gone", b.rec.Parent == nil)
	sim(10)
	check("slot comes back (test: 6 s)", bots()[b.id] ~= nil, Bots.Status())
end'

scenario cuff_refused_while_running '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(3)
Bots.Test(true)
local b = waitFor(function()
	for _, x in pairs(bots()) do
		if x.heat > 0 and x.walker and x.state == "OnFoot" then return x end
	end
	for _, x in pairs(bots()) do
		if x.heat > 0 and x.walker and x.state == "Crime" then
			-- walk a cop in on it: it runs
			moveTo(cop, x.walker.root.Position + Vector3.new(10, 0, 0))
		end
	end
end, 240)
check("a bot running on foot", b ~= nil, Bots.Status())
if b then
	sim(0.6)
	moveTo(cop, b.walker.root.Position + Vector3.new(4, 0, 0))
	b.walker.root.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
	local ok, why = PROMPTS[b.walker.root].onHeld(cop)
	if b.state ~= "Surrender" then
		check("a runner is too fast to cuff", ok == false and why == "CuffTooFast", tostring(ok) .. " " .. tostring(why))
	else
		check("(it gave up instead: cuffable)", ok == true)
	end
	moveTo(cop, Vector3.new(5000, 3, 5000))
	local far = PROMPTS[b.walker and b.walker.root or {}]
	if far and b.state ~= "Caught" then
		check("out of reach: no cuff", far.onHeld(cop) == false)
	end
end'

scenario spike_bail_or_cuff_car '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(3)
Bots.Test(true)
local b = waitFor(function()
	for _, x in pairs(bots()) do
		if x.heat > 0 and x.state == "Flee" and x.rider then return x end
	end
end, 240)
check("a wanted bot driving away", b ~= nil, Bots.Status())
if b then
	check("its car counts as wanted for spikes", Bots.CarWanted(b.drive.car))
	moveTo(cop, b.drive.car.DriverSeat.Position + Vector3.new(3, 0, 0))
	local okFast, whyFast = Bots.CuffCar(cop, b.drive.car)
	check("not cuffable at speed (CuffTooFast)", okFast == false and whyFast == "CuffTooFast",
		tostring(whyFast) .. " at " .. math.floor(b.drive.chassis.AssemblyLinearVelocity.Magnitude))
	-- boxed in: the car stops, a cop walks up to the door
	BLOCKED = { [b.drive] = true }
	sim(0.5)
	local seat = b.drive.car.DriverSeat
	moveTo(cop, seat.Position + Vector3.new(3, 0, 0))
	local ok = Bots.CuffCar(cop, b.drive.car)
	check("stopped car: driver cuffed", ok == true, b.state)
	check("pulled out of the car, hands up", b.walker ~= nil and b.walker.model:GetAttribute("Pose") == "HandsUp")
	check("cop paid", #PAID == 1 and PAID[1].bounty >= 500, PAID[1] and PAID[1].bounty)
	BLOCKED = nil
end
-- next one: spiked with a cop close behind
local c = waitFor(function()
	for _, x in pairs(bots()) do
		if x.heat > 0 and x.state == "Flee" and x.rider then return x end
	end
end, 240)
check("another wanted driver", c ~= nil, Bots.Status())
if c then
	local bailed = false
	for _ = 1, 8 do
		moveTo(cop, c.drive.chassis.Position + Vector3.new(60, 0, 0))
		c.drive.car:SetAttribute("FlatUntil", clock() + 12)
		sim(0.5)
		if c.state == "OnFoot" then bailed = true break end
		c.drive.car:SetAttribute("FlatUntil", nil)
		sim(0.5)
		if c.state ~= "Flee" then break end
	end
	check("spiked with a cop near: it may bail out and run (60% each flat)", bailed, c.state)
	if bailed then
		check("on foot: record says so", c.rec:GetAttribute("OnFoot") == true)
		check("taser-able", Bots.CanTase(c.walker.model))
	end
end'

scenario boxed_in_bails '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(3)
Bots.Test(true)
local b = waitFor(function()
	for _, x in pairs(bots()) do
		if x.heat > 0 and x.state == "Flee" and x.rider then return x end
	end
end, 240)
check("a wanted bot driving", b ~= nil)
if b then
	BLOCKED = { [b.drive] = true }
	moveTo(cop, b.drive.chassis.Position + Vector3.new(30, 0, 0))
	sim(6)
	check("boxed in with a cop near: out and running", b.state == "OnFoot" or b.state == "Surrender", b.state)
	BLOCKED = nil
end'

scenario escape '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(3)
Bots.Test(true)
local b = waitFor(function() return wanted()[1] end, 200)
check("a wanted bot", b ~= nil)
if b then
	moveTo(cop, Vector3.new(4000, 3, 4000)) -- far out of sight
	local pings = 0
	local last = b.rec:GetAttribute("LastSeen")
	local stop = clock() + 70
	while clock() < stop and b.heat > 0 do
		sim(1)
		local now = b.rec:GetAttribute("LastSeen")
		if now and last and (now - last).Magnitude > 1 then pings += 1 end
		last = now
	end
	check("unseen: gets away (30 + 10 x stars s)", b.heat == 0, Bots.Status())
	check("Escaped feed", feeds("Escaped") >= 1)
	check("witness pings moved the search circle", pings >= 1, pings)
	check("record cleared", b.rec:GetAttribute("Heat") == nil and b.rec:GetAttribute("LastSeen") == nil)
	sim(3)
	check("cruising again after", b.state == "Cruise" or b.state == "WalkBack" or b.state == "Vanish", b.state)
end'

scenario seen_stays_solid '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(3)
Bots.Test(true)
local b = waitFor(function() return wanted()[1] end, 200)
if b then
	local stop = clock() + 60
	while clock() < stop do
		moveTo(cop, posOf(b) + Vector3.new(100, 0, 0)) -- tailing it at 100 studs
		sim(0.5)
		if b.state == "Caught" then break end
	end
	check("a cop keeps it in sight: still wanted after 60 s", b.heat > 0, Bots.Status())
	check("stars solid while seen", b.rec:GetAttribute("HeatSpotted") == true)
end'

scenario real_robbers_first '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(4)
check("2 bots", count() == 2, count())
local r1 = person("Rob1", "Civilian", Vector3.new(-3000, 3, -3000))
r1:SetAttribute("Heat", 2)
sim(3)
local live = 0
for _, b in pairs(bots()) do if b.state ~= "Leave" and b.state ~= "Vanish" then live += 1 end end
check("1 real robber wanted: 1 bot stays, 1 leaves", live == 1, Bots.Status())
sim(3)
check("the leaving one vanished out of sight", count() == 1, count())
local r2 = person("Rob2", "Civilian", Vector3.new(-3100, 3, -3000))
r2:SetAttribute("Heat", 1)
sim(5)
check("2 real robbers wanted: no bots", count() == 0, count())
r1:SetAttribute("Heat", 0)
r2:SetAttribute("Heat", 0)
sim(26)
check("robbers gone quiet: bots back (after the 20 s slot wait)", count() == 2, count())'

scenario no_cop_leave '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(4)
check("2 bots", count() == 2)
cop:SetAttribute("Side", "Civilian")
moveTo(cop, Vector3.new(5000, 3, 5000))
sim(20)
check("no cop for 20 s: idle bots still around (45 s grace)", count() == 2, count())
sim(30)
check("no cop for 50 s: idle bots gone", count() == 0, count())
check("their cars cleaned up", (function()
	for _, b in ipairs(CARS) do if not b.removed then return false end end
	return true
end)())'

scenario carjack '
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
for i, s in ipairs(SITES) do
	person("Cit" .. i, "Civilian", s.RobPoint.Position + Vector3.new(30, 0, 0)) -- (no store free: a carjack)
end
sim(3)
Bots.Test(true)
local b
local stop = clock() + 400
while clock() < stop and not b do
	for _, x in pairs(bots()) do
		if x.crime and x.crime.kind == "Carjack" and x.state == "Crime" then b = x end
	end
	sim(0.5)
end
check("a bot breaks into a parked car", b ~= nil, Bots.Status())
if b then
	local victim = b.crime.victim
	local old = b.drive
	check("car alarm rings", (victim.car:GetAttribute("CarAlarmUntil") or 0) > clock())
	check("BotCarjack feed", feeds("BotCarjack") >= 1)
	check("1 star", b.heat == 1, b.heat)
	sim(4)
	check("drives off in the stolen car", b.drive == victim and b.rider ~= nil and b.state == "Flee", b.state)
	check("stolen car tagged as the bot", victim.car:GetAttribute("RobberBot") == b.id)
	check("old car left behind, untagged", old.car:GetAttribute("RobberBot") == nil)
	check("the bag is empty (bounty = stars only)", b.bag == 0, b.bag)
end'

GIVE_UP_SETUP='
local cop = person("Cop", "Cop", Vector3.new(0, 3, 0))
sim(3)
Bots.Test(true)
local b = waitFor(function()
	for _, x in pairs(bots()) do
		if x.heat > 0 and x.walker and x.state == "Crime" then return x end
	end
end, 240)
check("a wanted bot on foot", b ~= nil, Bots.Status())
local pr
if b then
	moveTo(cop, b.walker.root.Position + Vector3.new(6, 0, 0))
	pr = PROMPTS[b.walker.root]
	for _ = 1, 30 do
		if b.state == "Surrender" then break end
		pr.onHoldBegan(cop) -- a cop starts the cuffs: 35% it gives up right there
	end
	check("it puts its hands up", b.state == "Surrender" and b.walker.model:GetAttribute("Pose") == "HandsUp", b.state)
end'

scenario gives_up_cuffed "$GIVE_UP_SETUP"'
if b and b.state == "Surrender" then
	b.walker.root.AssemblyLinearVelocity = Vector3.new(12, 0, 0) -- (a twitch: hands up still counts)
	check("hands up: cuffed", pr.onHeld(cop) == true, b.state)
	check("paid", #PAID == 1)
end'

scenario gives_up_alone "$GIVE_UP_SETUP"'
if b and b.state == "Surrender" then
	moveTo(cop, Vector3.new(5000, 3, 5000))
	sim(5)
	check("a cop still near-ish for a few s: hands stay up", b.state == "Surrender", b.state)
	sim(6)
	check("nobody came: hands down, off it goes", b.state ~= "Surrender" and (not b.walker or b.walker.model:GetAttribute("Pose") == nil), b.state)
end'
