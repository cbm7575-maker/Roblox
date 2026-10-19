-- PedClient (ModuleScript, StarterPlayerScripts.Controllers.PedClient)
-- Pedestrians around you, simulated on your own device (like TrafficClient), from the looks in
-- ReplicatedStorage.PedTemplates (PedService):
--   * Walkers (MAX_PEDS, fewer in Performance mode and late at night) stroll the sidewalks beside the
--     RoadGraph. Each stretch stops short of the crossing street, then a corner waypoint, so they turn
--     on the pavement and cross streets straight; at dead ends they turn back or cross over. Far-away
--     walkers are recycled near the camera. In the rain they hurry.
--   * They react (checked ~10 times a second): a wanted player (Heat > 0) close by, a siren (a cop car
--     with Siren on, or an AI police car on a chase), or a fast car heading their way makes them panic
--     and run away along the sidewalk
--     for a few seconds. A car on course to hit them is dodged early (time to closest approach), at a
--     run; if one still overlaps, they hop aside and fade out (and a fresh walker appears elsewhere).
--     Nobody is ever knocked down, hurt or launched: this is a kid-friendly game.
--   * Hangout peds: anchored and cheap (no physics, no MoveTo), sitting at bus stops and benches, lying
--     on loungers, standing round the Solana Plaza fountain and watching the car meet. Spots come from
--     MapService (ReplicatedStorage attribute "HangoutSpots").
--   * Speech bubbles with lines from Config.PedLines (panic, sirens, rain, night, nice cars, the car
--     meet...): TextChatService bubbles (a BillboardGui fallback), at most one every 4 s, within 60 studs.
--   * Event peds from EventService (Models in Workspace.Events with attributes Anim and Lines) are
--     animated here and chat too.
-- Walkers' root parts are handed to TrafficClient (TrafficClient.PedSource) so traffic stops for them.

local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local PedLines = require(ReplicatedStorage.Shared.Config.PedLines)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local TrafficClient = require(script.Parent:WaitForChild("TrafficClient"))

local player = Players.LocalPlayer

local PedClient = {}

local MAX_PEDS, PERF_PEDS = 12, 5
local SPAWN_MIN, SPAWN_MAX = 60, 230
local DESPAWN = 320
local MAX_HANG, PERF_HANG = 10, 5
local HANG_RANGE = 140 -- hangout peds exist within this many studs of you
local HANG_POP = 55 -- ...and never pop in on screen closer than this
local ROAD_TOP = 0.1
local BUBBLE_GAP = 4 -- seconds between speech bubbles (all peds together)
local BUBBLE_RANGE = 60
local PANIC_PLAYER, PANIC_SIREN = 40, 70 -- studs
local DODGE_HORIZON = 1.6 -- seconds of look-ahead for cars on course to hit a walker
local RUN_SPEED = { 18, 22 }
local SIT_LIFT = 1.45 -- root above the seat top, for a HipHeight-2 rig (scaled by HipHeight)

-- Roblox's default R15 animations (from the stock Animate script).
local ANIMS = {
	walk = "rbxassetid://507777826",
	run = "rbxassetid://507767714",
	idle = "rbxassetid://507766388",
	sit = "rbxassetid://2506281703",
	dance = "rbxassetid://507771019",
	dance2 = "rbxassetid://507776043",
	dance3 = "rbxassetid://507777268",
	cheer = "rbxassetid://507770677",
	wave = "rbxassetid://507770239",
	point = "rbxassetid://507770453",
	laugh = "rbxassetid://507770818",
}

-- Share of hangout spots with someone on them (percent), by group.
local OCCUPANCY = { Bench = 40, BusStop = 55, Lounger = 40, Plaza = 60, CarMeet = 75 }

local folder, idleFolder
local peds = {} -- walkers
local ready = false
local animations = {} -- [name] = Animation

------------------------------------------------------------------ helpers

local function anim(name)
	local a = animations[name]
	if not a and ANIMS[name] then
		a = Instance.new("Animation")
		a.AnimationId = ANIMS[name]
		animations[name] = a
	end
	return a
end

local function loadTrack(hum, name, looped)
	local a = anim(name)
	if not a then
		return nil
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(a)
	end)
	if not ok or not track then
		return nil
	end
	track.Looped = looped ~= false
	return track
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function focus()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or Workspace.CurrentCamera.Focus.Position
end

local function onScreen(pos)
	local cam = Workspace.CurrentCamera
	local _, visible = cam:WorldToViewportPoint(pos)
	return visible
end

local function settings()
	local s = script.Parent:FindFirstChild("SettingsClient")
	return s and require(s)
end

local function performance()
	local s = settings()
	return s ~= nil and s.Get("Performance") == true
end

local function template()
	local templates = ReplicatedStorage:FindFirstChild("PedTemplates")
	local list = templates and templates:GetChildren() or {}
	return #list > 0 and list[math.random(#list)] or nil
end

------------------------------------------------------------------ speech bubbles

local bubbleNext = 0
local billboards = {} -- pooled fallback bubbles
local billboardIndex = 0

local function bubbleChatOn()
	local ok, on = pcall(function()
		local config = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
		return TextChatService.ChatVersion == Enum.ChatVersion.TextChatService and (config == nil or config.Enabled)
	end)
	return ok and on == true
end

local function billboardBubble(adornee, text)
	if #billboards < 3 then
		local gui = Instance.new("BillboardGui")
		gui.Name = "PedBubble"
		gui.Size = UDim2.fromOffset(190, 46)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.MaxDistance = BUBBLE_RANGE + 10
		gui.LightInfluence = 0
		gui.Enabled = false
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(250, 248, 255)
		label.BackgroundTransparency = 0.05
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextWrapped = true
		label.TextColor3 = Color3.fromRGB(30, 24, 44)
		label.Parent = gui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 12)
		c.Parent = label
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
		pad.Parent = label
		gui.Parent = player:WaitForChild("PlayerGui")
		table.insert(billboards, { gui = gui, label = label, token = 0 })
	end
	billboardIndex = billboardIndex % #billboards + 1
	local b = billboards[billboardIndex]
	b.token += 1
	local token = b.token
	b.gui.Adornee = adornee
	b.label.Text = text
	b.gui.Enabled = true
	task.delay(3.5, function()
		if b.token == token then
			b.gui.Enabled = false
			b.gui.Adornee = nil
		end
	end)
end

-- Say a random line from PedLines[category] over this ped, if a bubble is due and you're close.
local function say(model, category, now)
	if now < bubbleNext or not model or not model.Parent then
		return false
	end
	local lines = PedLines[category]
	if type(lines) ~= "table" or #lines == 0 then
		return false
	end
	local head = model:FindFirstChild("Head")
	local adornee = (head and head:IsA("BasePart")) and head or model.PrimaryPart
	if not adornee or (adornee.Position - focus()).Magnitude > BUBBLE_RANGE then
		return false
	end
	bubbleNext = now + BUBBLE_GAP
	local text = lines[math.random(#lines)]
	local shown = false
	if bubbleChatOn() then
		shown = pcall(function()
			TextChatService:DisplayBubble(adornee, text)
		end)
	end
	if not shown then
		billboardBubble(adornee, text)
	end
	return true
end

------------------------------------------------------------------ sidewalk routes

local function neighbours(i)
	local list = {}
	for j in pairs(RoadGraph.Edges[i] or {}) do
		if TrafficClient.EdgeAllowed(i, j) then
			table.insert(list, j)
		end
	end
	return list
end

local function degree(i)
	local n = 0
	for _ in pairs(RoadGraph.Edges[i] or {}) do
		n += 1
	end
	return n
end

local function frame(a, b)
	local na, nb = RoadGraph.Nodes[a], RoadGraph.Nodes[b]
	local d = nb - na
	local len = d.Magnitude
	local dir = len > 0 and d / len or Vector3.new(0, 0, 1)
	return na, dir, Vector3.new(-dir.Z, 0, dir.X), len
end

-- Widest road crossing at node n, seen from the road towards `except` (the straight continuation of
-- that road doesn't count).
local function crossWidth(n, except)
	local w = 0
	local _, back = frame(n, except)
	for j in pairs(RoadGraph.Edges[n] or {}) do
		if j ~= except then
			local _, d = frame(n, j)
			if d:Dot(back) > -0.9 then
				w = math.max(w, RoadGraph.Width(n, j))
			end
		end
	end
	return w
end

-- How far along a->b the sidewalk stretch starts and ends: short of the crossing street at each end.
local function legSpan(a, b)
	local _, _, _, len = frame(a, b)
	local t0 = degree(a) <= 1 and 2 or crossWidth(a, b) / 2 + 5
	local t1 = len - (degree(b) <= 1 and 2 or crossWidth(b, a) / 2 + 5)
	if t1 < t0 then
		t0 = len / 2
		t1 = len / 2
	end
	return t0, t1, len
end

-- A point on the sidewalk beside the road a->b, t studs along it, on `side` (+1 right, -1 left).
local function sidewalk(a, b, t, side)
	local na, dir, right, len = frame(a, b)
	local off = RoadGraph.Width(a, b) / 2 + 5
	local p = na + dir * math.clamp(t, 0, len) + right * off * side
	return Vector3.new(p.X, ROAD_TOP + 3, p.Z)
end

-- Where two lines (point + direction, flat) cross, or nil if they're nearly parallel.
local function intersect(p1, d1, p2, d2)
	local denom = d1.X * d2.Z - d1.Z * d2.X
	if math.abs(denom) < 0.15 then
		return nil
	end
	local q = p2 - p1
	local u = (q.X * d2.Z - q.Z * d2.X) / denom
	return p1 + d1 * u
end

-- Plan the way from the end of the current stretch (ped.a -> ped.b) onto the next one: queue the
-- corner (when the sidewalks meet at an angle), the start of the next stretch and its end.
local function planNext(ped)
	local a, b, side = ped.a, ped.b, ped.side
	local options = {}
	for _, k in ipairs(neighbours(b)) do
		if k ~= a then
			table.insert(options, k)
		end
	end
	local deadEnd = #options == 0
	local k = deadEnd and a or options[math.random(#options)]
	local _, t1 = legSpan(a, b)
	local p1 = sidewalk(a, b, t1, side)
	local t0n, t1n = legSpan(b, k)
	local newSide
	if deadEnd then
		-- Turn back on this pavement (side flips with the direction), or cross over and walk back.
		newSide = math.random() < 0.5 and -side or side
	else
		-- The start of the next stretch that's nearest: fewest streets to cross.
		local qR, qL = sidewalk(b, k, t0n, 1), sidewalk(b, k, t0n, -1)
		newSide = (flat(qR - p1).Magnitude <= flat(qL - p1).Magnitude) and 1 or -1
	end
	local q = sidewalk(b, k, t0n, newSide)
	local queue = {}
	if not deadEnd then
		local _, d1 = frame(a, b)
		local _, d2 = frame(b, k)
		local c = intersect(flat(p1), d1, flat(q), d2)
		local nb = RoadGraph.Nodes[b]
		if c then
			c = Vector3.new(c.X, p1.Y, c.Z)
			local limit = math.max(RoadGraph.Width(a, b), RoadGraph.Width(b, k)) * 1.2 + 12
			if flat(c - nb).Magnitude < limit and (c - p1):Dot(d1) > 0.5 and (q - c):Dot(d2) > 0.5 then
				table.insert(queue, c)
			end
		end
	end
	table.insert(queue, q)
	table.insert(queue, sidewalk(b, k, t1n, newSide))
	ped.a, ped.b, ped.side = b, k, newSide
	ped.queue = queue
end

local function moveOn(ped)
	if #ped.queue == 0 then
		planNext(ped)
	end
	ped.target = table.remove(ped.queue, 1)
	ped.lastMove = os.clock()
	ped.hum:MoveTo(ped.target)
end

------------------------------------------------------------------ walkers

local function setGait(ped, running)
	if running == ped.running then
		return
	end
	ped.running = running
	if running then
		if ped.track then
			ped.track:Stop(0.2)
		end
		if ped.runTrack then
			ped.runTrack:Play(0.2)
		end
	else
		if ped.runTrack then
			ped.runTrack:Stop(0.2)
		end
		if ped.track then
			ped.track:Play(0.2)
		end
	end
end

local function applySpeed(ped, now)
	local speed = ped.baseSpeed
	local running = false
	if ped.dodgeUntil and now < ped.dodgeUntil then
		speed, running = 22, true
	elseif ped.panicUntil and now < ped.panicUntil then
		speed, running = ped.panicSpeed, true
	elseif Workspace:GetAttribute("Raining") == true then
		speed = ped.baseSpeed * 1.6 -- hurrying out of the rain
		running = speed > 11
	end
	ped.hum.WalkSpeed = speed
	setGait(ped, running)
	local track = running and ped.runTrack or ped.track
	if track then
		pcall(function()
			track:AdjustSpeed(math.clamp(speed / (running and 20 or 10), 0.6, 1.3))
		end)
	end
end

local function spawnPed()
	local look = template()
	if not look then
		return
	end
	local here = focus()
	local flatHere = flat(here)
	local nodes = RoadGraph.Nodes
	for _ = 1, 10 do
		local i = math.random(#nodes)
		local nb = neighbours(i)
		if #nb > 0 then
			local j = nb[math.random(#nb)]
			local t0, t1 = legSpan(i, j)
			local t = t0 + math.random() * (t1 - t0)
			local side = math.random(2) == 1 and 1 or -1
			local pos = sidewalk(i, j, t, side)
			local d = (flat(pos) - flatHere).Magnitude
			-- Only where the ground is actually there (streamed in) and not right on top of the player.
			local ground = d > SPAWN_MIN and d < SPAWN_MAX and Workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -40, 0))
			if ground then
				local model = look:Clone()
				local hum = model:FindFirstChildOfClass("Humanoid")
				local root = model:FindFirstChild("HumanoidRootPart")
				if not hum or not root or not root:IsA("BasePart") then
					model:Destroy()
					return
				end
				for _, part in ipairs(model:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanQuery = false
						part.CanTouch = false -- never sits in seats or sets off touch triggers
						part.CastShadow = false
						-- "Traffic" group: players' cars pass through (walkers dodge them instead).
						part.CollisionGroup = "Traffic"
					end
				end
				-- Never fall over or ragdoll, whatever bumps into them.
				for _, state in ipairs({ Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll,
					Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.PlatformStanding }) do
					hum:SetStateEnabled(state, false)
				end
				model:PivotTo(CFrame.new(ground.Position + Vector3.new(0, hum.HipHeight + root.Size.Y / 2, 0)))
				model.Parent = folder
				local ped = {
					model = model, hum = hum, root = root, a = i, b = j, side = side, queue = {},
					baseSpeed = 5 + math.random() * 3, panicSpeed = RUN_SPEED[1] + math.random() * (RUN_SPEED[2] - RUN_SPEED[1]),
				}
				ped.track = loadTrack(hum, "walk")
				ped.runTrack = loadTrack(hum, "run")
				if ped.track then
					ped.track:Play()
				end
				ped.running = false
				table.insert(ped.queue, sidewalk(i, j, t1, side))
				applySpeed(ped, os.clock())
				moveOn(ped)
				table.insert(peds, ped)
				return
			end
		end
	end
end

local function removePed(i)
	local ped = peds[i]
	ped.model:Destroy()
	table.remove(peds, i)
end

-- Run away along the sidewalk from `from` for a few seconds.
local function panic(ped, from, now, category)
	local fresh = not (ped.panicUntil and now < ped.panicUntil)
	ped.panicUntil = now + 3.5 + math.random() * 2
	if fresh then
		-- Threat ahead on this stretch? Turn round (same pavement: the side flips with the direction).
		local _, dir = frame(ped.a, ped.b)
		if (from - ped.root.Position):Dot(dir) > 0 then
			ped.a, ped.b, ped.side = ped.b, ped.a, -ped.side
			local _, t1 = legSpan(ped.a, ped.b)
			ped.queue = { sidewalk(ped.a, ped.b, t1, ped.side) }
			if ped.dodgeUntil and now < ped.dodgeUntil then
				ped.target = table.remove(ped.queue, 1) -- walk() heads there once the dodge is over
			else
				moveOn(ped)
			end
		end
		applySpeed(ped, now)
		say(ped.model, category, now)
	end
end

-- Sidestep a car on course to hit us: run perpendicular to its path, away from it.
local function dodge(ped, away, now)
	ped.dodgeUntil = now + 0.75
	applySpeed(ped, now)
	ped.hum:MoveTo(ped.root.Position + away * 10)
	ped.lastMove = now
	if not ped.saidDodge then
		ped.saidDodge = true
		task.delay(0.8, function()
			if ped.model.Parent then
				say(ped.model, "Dodge", os.clock())
			end
		end)
	end
end

-- Too late to dodge: a quick hop aside and a fade, then a fresh walker appears elsewhere.
local function hopAway(ped, away)
	if ped.leaving then
		return
	end
	ped.leaving = true
	ped.hum.WalkSpeed = 20
	ped.hum.Jump = true
	ped.hum:MoveTo(ped.root.Position + away * 8)
	setGait(ped, true)
	task.spawn(function()
		for k = 1, 8 do
			task.wait(0.05)
			if not ped.model.Parent then
				return
			end
			for _, d in ipairs(ped.model:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = k / 8
				end
			end
		end
		ped.gone = true
	end)
end

------------------------------------------------------------------ threats (10 Hz)

local movers = {} -- cars this tick: { pos, vel, halfW, siren }
local hotPlayers = {} -- positions of wanted players

local function gatherThreats()
	table.clear(movers)
	table.clear(hotPlayers)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		for _, v in ipairs(vehicles:GetChildren()) do
			local chassis = v:IsA("Model") and v.PrimaryPart
			if chassis and not v:GetAttribute("Boat") then
				-- Sirens: a cop car with the siren on, or an AI police car on a chase (the ones that wail).
				local siren = v:GetAttribute("Siren") == true or (v:GetAttribute("AIPolice") == true and v:GetAttribute("AITarget") ~= nil)
				table.insert(movers, {
					pos = chassis.Position, vel = flat(chassis.AssemblyLinearVelocity),
					halfW = math.max(chassis.Size.X, 4) / 2 + 0.8, siren = siren, model = v,
				})
			end
		end
	end
	for _, car in ipairs(TrafficClient.Cars()) do
		if not car.wrecked and car.pos and car.heading and car.speed then
			-- Ambient traffic brakes for walkers anyway: they only sidestep it, no panic.
			table.insert(movers, {
				pos = car.pos, vel = flat(car.heading * car.speed), halfW = car.half.X + 0.8, siren = false, traffic = true,
			})
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		local heat = p:GetAttribute("Heat")
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if type(heat) == "number" and heat > 0 and root and root:IsA("BasePart") then
			table.insert(hotPlayers, root.Position)
		end
	end
end

local function react(now)
	gatherThreats()
	for _, ped in ipairs(peds) do
		if ped.leaving or not ped.model.Parent then
			continue
		end
		local here = ped.root.Position
		local flatHere = flat(here)
		local threat, category
		for _, m in ipairs(movers) do
			local rel = flatHere - flat(m.pos)
			local dist2 = rel:Dot(rel)
			local speed2 = m.vel:Dot(m.vel)
			if m.siren and dist2 < PANIC_SIREN * PANIC_SIREN and math.abs(here.Y - m.pos.Y) < 20 then
				threat, category = m.pos, "Siren"
			end
			if speed2 > 64 then
				local reach = math.sqrt(speed2) * (DODGE_HORIZON + 0.4) + 12
				if dist2 < reach * reach and math.abs(here.Y - m.pos.Y) < 10 then
					-- Time to closest approach and how close the car's centre line passes.
					local tca = rel:Dot(m.vel) / speed2
					local closest = rel - m.vel * tca
					local miss = closest.Magnitude
					local horizon = m.traffic and 1 or DODGE_HORIZON
					if tca > -0.05 and tca < horizon and miss < m.halfW + 3 then
						local away = miss > 0.3 and closest / miss or Vector3.new(-m.vel.Z, 0, m.vel.X).Unit
						if tca < 0.12 and miss < m.halfW + 0.6 then
							hopAway(ped, away)
							break
						elseif not (ped.dodgeUntil and now < ped.dodgeUntil) then
							dodge(ped, away, now)
						end
						if not m.traffic then
							threat, category = threat or m.pos, category or "Panic"
						end
					elseif not m.traffic and speed2 > 900 and tca > 0 and tca < 2.5 and miss < 12 then
						-- A fast car heading our way: run.
						threat, category = threat or m.pos, category or "Panic"
					end
				end
			end
		end
		if not threat then
			for _, pos in ipairs(hotPlayers) do
				if flat(pos - here).Magnitude < PANIC_PLAYER then
					threat, category = pos, "Panic"
					break
				end
			end
		end
		if threat and not ped.leaving then
			panic(ped, threat, now, category)
		end
	end
end

------------------------------------------------------------------ walkers: the 5 Hz loop

local function walkerCap()
	local cap = performance() and PERF_PEDS or MAX_PEDS
	local clock = Lighting.ClockTime
	if clock >= 0.5 and clock < 5 then
		cap = math.max(2, math.floor(cap * 0.45)) -- the small hours: just a few night owls
	end
	return cap
end

local function walk(now)
	local flatHere = flat(focus())
	for i = #peds, 1, -1 do
		local ped = peds[i]
		local pos = ped.root.Position
		if ped.gone or not ped.model.Parent or (flat(pos) - flatHere).Magnitude > DESPAWN or pos.Y < -20 then
			removePed(i)
		elseif not ped.leaving then
			if ped.dodgeUntil and now >= ped.dodgeUntil then
				-- Dodge over: back on the route.
				ped.dodgeUntil = nil
				ped.hum:MoveTo(ped.target)
				ped.lastMove = now
			end
			if not ped.dodgeUntil then
				local toTarget = flat(ped.target - pos)
				if toTarget.Magnitude < 3 then
					moveOn(ped)
				elseif now - (ped.lastMove or 0) > 6 then
					-- Humanoid:MoveTo gives up after 8 s; keep nudging it.
					ped.lastMove = now
					ped.hum:MoveTo(ped.target)
				end
			end
			if ped.panicUntil and now >= ped.panicUntil then
				ped.panicUntil = nil
			end
			applySpeed(ped, now)
		end
	end
	local cap = walkerCap()
	if #peds < cap then
		spawnPed()
	elseif #peds > cap then
		-- Drop one that's off screen (or the farthest).
		local pick, pickD = nil, -1
		for i, ped in ipairs(peds) do
			local d = (flat(ped.root.Position) - flatHere).Magnitude
			local score = d + (onScreen(ped.root.Position) and 0 or 1000)
			if score > pickD then
				pick, pickD = i, score
			end
		end
		if pick then
			removePed(pick)
		end
	end
end

------------------------------------------------------------------ hangout peds (anchored)

local spots = {} -- { pos, yaw, kind, group, hash }
local hangs = {} -- [spot index] = { model, track }

local function loadSpots()
	local ok, list = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("HangoutSpots") or "[]")
	end)
	table.clear(spots)
	if not ok or type(list) ~= "table" then
		return
	end
	for i, s in ipairs(list) do
		if type(s) == "table" and type(s.x) == "number" and type(s.y) == "number" and type(s.z) == "number" then
			table.insert(spots, {
				pos = Vector3.new(s.x, s.y, s.z), yaw = math.rad(tonumber(s.r) or 0), kind = s.k or "stand",
				group = s.g or "Bench", hash = (i * 7919 + math.floor(s.x * 13 + s.z * 7)) % 1000,
			})
		end
	end
end

-- Is someone at this spot right now? Stable per spot, reshuffled every 5 minutes.
local function wanted(s, epoch)
	local share = OCCUPANCY[s.group] or 40
	local night = Workspace:GetAttribute("IsNight") == true
	local rain = Workspace:GetAttribute("Raining") == true
	if s.group == "CarMeet" then
		local state = Workspace:GetAttribute("CarMeetState")
		if state ~= "Live" and state ~= "Soon" then
			return false
		end
	elseif s.group == "Lounger" then
		if night or rain then
			return false
		end
	elseif s.group == "Plaza" or s.group == "Bench" then
		if rain then
			return false
		end
		if night then
			share *= 0.5
		end
	end
	return (s.hash + epoch * 37) % 100 < share
end

local function removeHang(index)
	local h = hangs[index]
	if h then
		h.model:Destroy()
		hangs[index] = nil
	end
end

local function spawnHang(index, s)
	local look = template()
	if not look then
		return
	end
	local model = look:Clone()
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") then
		model:Destroy()
		return
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.CollisionGroup = "Traffic"
		end
	end
	root.Anchored = true -- no physics at all: the animation poses the body
	local scale = hum.HipHeight / 2
	local yawCF = CFrame.Angles(0, s.yaw, 0)
	local cf
	local animName = "idle"
	if s.kind == "sit" then
		cf = CFrame.new(s.pos + Vector3.new(0, SIT_LIFT * scale, 0)) * yawCF
		animName = "sit"
	elseif s.kind == "lie" then
		-- Flat on the lounger, face up, head toward the backrest.
		local h = yawCF.LookVector
		local p = s.pos + h * 0.2 + Vector3.new(0, root.Size.Z / 2 + 0.05, 0)
		cf = CFrame.fromMatrix(p, Vector3.new(h.Z, 0, -h.X), h, Vector3.new(0, -1, 0))
	else
		cf = CFrame.new(s.pos + Vector3.new(0, hum.HipHeight + root.Size.Y / 2, 0)) * yawCF
		if s.group == "CarMeet" then
			animName = ({ "idle", "cheer", "point", "idle" })[math.random(4)]
		elseif math.random() < 0.15 then
			animName = "wave"
		end
	end
	model:PivotTo(cf)
	model.Parent = idleFolder
	local track = loadTrack(hum, animName)
	if track then
		track:Play()
		pcall(function()
			track:AdjustSpeed(0.85 + math.random() * 0.3)
		end)
	end
	hangs[index] = { model = model, track = track, kind = s.kind, group = s.group }
end

local function updateHangouts()
	if #spots == 0 then
		return
	end
	local here = focus()
	local epoch = math.floor(os.time() / 300)
	local cap = performance() and PERF_HANG or MAX_HANG
	local count = 0
	for index, h in pairs(hangs) do
		local s = spots[index]
		local d = s and (s.pos - here).Magnitude or math.huge
		local root = h.model.PrimaryPart
		-- Leave when far, or when no longer wanted (only when you can't see it go).
		if not s or not h.model.Parent or d > HANG_RANGE + 30
			or (not wanted(s, epoch) and (d > 80 or not (root and onScreen(root.Position)))) then
			removeHang(index)
		else
			count += 1
		end
	end
	if count >= cap then
		return
	end
	local candidates = {}
	for index, s in ipairs(spots) do
		if not hangs[index] then
			local d = (s.pos - here).Magnitude
			if d < HANG_RANGE and wanted(s, epoch) and (d > HANG_POP or not onScreen(s.pos)) then
				table.insert(candidates, { index = index, d = d })
			end
		end
	end
	table.sort(candidates, function(x, y)
		return x.d < y.d
	end)
	for _, c in ipairs(candidates) do
		if count >= cap then
			break
		end
		spawnHang(c.index, spots[c.index])
		count += 1
	end
end

------------------------------------------------------------------ event peds (EventService)

local eventPeds = {} -- [model] = { lines }

local function watchEventPed(model)
	if not model:IsA("Model") or eventPeds[model] or type(model:GetAttribute("Anim")) ~= "string" then
		return
	end
	eventPeds[model] = { lines = model:GetAttribute("Lines") }
	task.spawn(function()
		local hum = model:WaitForChild("Humanoid", 10)
		if not hum or not hum:IsA("Humanoid") or not model.Parent then
			return
		end
		local track = loadTrack(hum, model:GetAttribute("Anim"))
		if track and eventPeds[model] then
			track:Play()
			eventPeds[model].track = track
		end
	end)
end

local function watchEvents()
	local events = Workspace:WaitForChild("Events", 60)
	if not events then
		return
	end
	for _, d in ipairs(events:GetDescendants()) do
		watchEventPed(d)
	end
	events.DescendantAdded:Connect(watchEventPed)
	events.DescendantRemoving:Connect(function(d)
		eventPeds[d] = nil
	end)
end

------------------------------------------------------------------ chatter (1 Hz)

local complimented = setmetatable({}, { __mode = "k" }) -- [car model] = time

local function niceCar(car)
	if car:GetAttribute("Police") or car:GetAttribute("AIPolice") or car:GetAttribute("Boat") then
		return false
	end
	local ownerId = car:GetAttribute("OwnerUserId")
	local id = car:GetAttribute("VehicleId")
	if type(ownerId) ~= "number" or type(id) ~= "string" then
		return false
	end
	local def = Vehicles.ById[id]
	if def and ((def.Price or 0) >= 28000 or def.Pass ~= nil) then
		return true
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	local custom = owner and owner:GetAttribute("Custom_" .. id)
	return type(custom) == "string" and custom ~= "0,0,0"
end

local function chatter(now)
	if now < bubbleNext then
		return
	end
	local here = focus()
	-- Everyone who could talk, near you.
	local talkers = {}
	for _, ped in ipairs(peds) do
		if not ped.leaving and (ped.root.Position - here).Magnitude < BUBBLE_RANGE then
			table.insert(talkers, { model = ped.model, root = ped.root, kind = "walk" })
		end
	end
	for _, h in pairs(hangs) do
		local root = h.model.PrimaryPart
		if root and (root.Position - here).Magnitude < BUBBLE_RANGE then
			table.insert(talkers, { model = h.model, root = root, kind = h.kind, group = h.group })
		end
	end
	-- Event peds talk first (that's the show).
	for model, info in pairs(eventPeds) do
		local root = model.PrimaryPart
		if model.Parent and root and type(info.lines) == "string" and (root.Position - here).Magnitude < 45
			and math.random() < 0.6 then
			if say(model, info.lines, now) then
				return
			end
		end
	end
	if #talkers == 0 then
		return
	end
	-- A nice car rolling past someone.
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		for _, car in ipairs(vehicles:GetChildren()) do
			local chassis = car:IsA("Model") and car.PrimaryPart
			if chassis and now - (complimented[car] or -100) > 25 and (chassis.Position - here).Magnitude < BUBBLE_RANGE
				and chassis.AssemblyLinearVelocity.Magnitude < 30 and niceCar(car) then
				for _, t in ipairs(talkers) do
					if (t.root.Position - chassis.Position).Magnitude < 28 then
						complimented[car] = now
						if say(t.model, "NiceCar", now) then
							return
						end
					end
				end
			end
		end
	end
	if math.random() > 0.3 then
		return
	end
	local t = talkers[math.random(#talkers)]
	local category = "Idle"
	if t.group == "CarMeet" then
		category = "CarMeet"
	elseif Workspace:GetAttribute("Raining") == true and math.random() < 0.7 then
		category = "Rain"
	elseif Workspace:GetAttribute("IsNight") == true and math.random() < 0.5 then
		category = "Night"
	elseif (t.kind == "sit" or t.kind == "lie") and math.random() < 0.5 then
		category = "Sit"
	end
	say(t.model, category, now)
end

------------------------------------------------------------------ init

-- Walkers' root parts, for TrafficClient (it stops for them).
local pedRoots = {}
local function roots()
	table.clear(pedRoots)
	for _, ped in ipairs(peds) do
		if not ped.leaving and ped.root.Parent then
			table.insert(pedRoots, ped.root)
		end
	end
	return pedRoots
end

function PedClient.Init()
	folder = Instance.new("Folder")
	folder.Name = "Peds"
	folder.Parent = Workspace
	idleFolder = Instance.new("Folder")
	idleFolder.Name = "PedsIdle"
	idleFolder.Parent = Workspace
	TrafficClient.PedSource = roots
	task.spawn(function()
		for _ = 1, 60 do
			if RoadGraph.LoadPublished() and #RoadGraph.Nodes > 0 then
				ready = true
				return
			end
			task.wait(1)
		end
	end)
	loadSpots()
	ReplicatedStorage:GetAttributeChangedSignal("HangoutSpots"):Connect(function()
		for index in pairs(hangs) do
			removeHang(index)
		end
		loadSpots()
	end)
	task.spawn(watchEvents)
	local reactAcc, walkAcc, slowAcc = 0, 0, 0
	local lastWarn = 0
	local function guarded(fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok and os.clock() - lastWarn > 10 then
			lastWarn = os.clock()
			warn("[PedClient] " .. tostring(err))
		end
	end
	RunService.Heartbeat:Connect(function(dt)
		if not ready then
			return
		end
		local now = os.clock()
		reactAcc += dt
		walkAcc += dt
		slowAcc += dt
		if reactAcc >= 0.1 then
			reactAcc = 0
			guarded(react, now)
		end
		if walkAcc >= 0.2 then
			walkAcc = 0
			guarded(walk, now)
		end
		if slowAcc >= 1 then
			slowAcc = 0
			guarded(updateHangouts)
			guarded(chatter, now)
		end
	end)
end

return PedClient
