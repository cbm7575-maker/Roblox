-- PedClient (ModuleScript, StarterPlayerScripts.Controllers.PedClient)
-- Pedestrians on the sidewalks around you, simulated on your own device (like TrafficClient):
--   * Up to MAX_PEDS walkers cloned from ReplicatedStorage.PedTemplates (PedService), strolling
--     beside the roads of the RoadGraph (a sidewalk offset from each road edge). At a turn they walk
--     round the corner where the two sidewalks meet, so they only step into a road to cross it at a
--     junction; turning back, they stay on their own side.
--   * A mixed crowd: each walker gets a walk / run / idle set from Config.Animations picked for the
--     district they appear in (Animations.Pick), and their own pace and build (Animations.PedVariation:
--     track speed, body height and width).
--   * Never in the water: spawn spots and the next stretch of sidewalk must be over dry ground
--     (the Causeway and Prison Bridge sidewalks hang over the sea).
--   * PedClient.Positions() -> { Vector3 }: where they are (TrafficClient stops for them).
--   * They dive out of the way of fast cars, and anyone who gets bumped just falls over and gets back
--     up. No damage, nothing gory: this is a kid-friendly game. A fall is the shared limp body
--     (Shared.Util.Ragdoll: proper elbow and knee limits, a cap on how many at once); when that says no
--     (the cap) or isn't there, a simpler loose-jointed fall made here.
--   * Far-away walkers are recycled near the camera.
--   * Fights (numbers in Config.Combat.Ped). CombatClient calls the first two only for the local
--     citizen's own swing or shot:
--       PedClient.KnockNear(position, lookVector) -> bool: a punch. The nearest walker within 7 studs in
--         front falls over for 2 s, then runs off, and drops a wallet.
--       PedClient.ShotAt(origin, dir, maxDistance) -> hitPos or nil: a bullet. Walkers can't be seen by
--         raycasts (CanQuery is off), so this finds the nearest one standing within HitRadius of the shot's
--         line, no farther than maxDistance (where the shot ends). They fall along the shot, run off and
--         drop a wallet. Returns where the shot met them, so the tracer can stop there.
--       PedClient.Scare(position): gunfire (anyone's: it only makes them react). Every walker within
--         ScareRange who is on their feet does one of three things, and the same walker always the same
--         one: most sprint away (45 studs), arms thrown over their heads (PoseClient "Brace" held for the
--         run); some drop into a crouch where they stand with their arms over their heads (PoseClient
--         "Cower"); a few who are at least 25 studs from the shot stop, turn to it and hold a phone up
--         (PoseClient "PhoneLook") until it comes closer.
--       PedClient.AimedAt(origin, dir): a raised gun points along dir (CombatClient, twice a second
--         while the local player aims). Up to three walkers within 20 studs and close to that line stop,
--         turn and put their hands up (PoseClient "HandsUp"); the nervous ones run instead. When the gun
--         moves off them they hurry away.
--     Poses are only for walkers within 70 studs of the camera, six at a time; the rest just run. Without
--     PoseClient everyone just runs (or stands), arms as the animation has them.
--   * Wallets: a little billfold prop (Workspace.Peds.PedWallet, this device only) where a walker fell,
--     gone after WalletLife seconds. Walk within PickupRange on foot and the server is asked
--     ("PedLoot", position; one question at a time, given up after 3 s). PedService decides and answers:
--       "Paid", amount, stars   the prop goes, "+$N" pops up, the cash sound plays (the money is in your bag)
--       "Empty"                 the street has gone quiet: every wallet goes, none drop for QuietFor seconds
--       "No"                    not now (too soon, bag full, safe zone...): it stays, asked again in 2.5 s
--     Nothing here pays anything: the wallet is only a prop until the server says "Paid".
--   * PedClient.Flee(position, direction) -> bool: a carjacked driver (TrafficClient) jumps out at
--     `position` and sprints off along `direction` for a few seconds, then is gone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Animations = require(ReplicatedStorage.Shared.Config.Animations)
local Combat = require(ReplicatedStorage.Shared.Config.Combat)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)

local player = Players.LocalPlayer

local PedClient = {}

local MAX_PEDS = 16 -- (Look 4.0: busier sidewalks; performance mode keeps 5)
local SPAWN_MIN, SPAWN_MAX = 60, 230
local DESPAWN = 320
local WALK_ANIM = "rbxassetid://507777826" -- Roblox's default R15 walk (when Config.Animations has nothing)
local RUN_ANIM = "rbxassetid://507767714" -- Roblox's default R15 run (the walk's pair)
local IDLE_ANIM = "rbxassetid://507766388" -- Roblox's default R15 idle
local ROAD_TOP = 0.1

local PED = Combat.Ped or {}
local WALLET_LIFE = PED.WalletLife or 20
local PICKUP_RANGE = PED.PickupRange or 6
local QUIET_FOR = PED.QuietFor or 60
local SCARE_RANGE = PED.ScareRange or 60
local HIT_RADIUS = PED.HitRadius or 2.2
local MAX_WALLETS = 6 -- props on the ground at once (the oldest goes first)
local LOOT_TIMEOUT = 3 -- seconds to wait for the server's answer
local LOOT_RETRY = 2.5 -- seconds before asking again about the same wallet
local RUN_SPEED = 18
local SCARE_TIME = 4
local WALLET_DARK = Color3.fromRGB(34, 30, 28)
-- How walkers take gunfire and a gun pointed at them (see the header). Each walker has a "nerve"
-- between 0 and 1, rolled once: it decides which of these they do, every time.
local REACT = {
	Film = 0.12, -- nerve under this: stops and films (only from FilmMin studs or more)
	Cower = 0.27, -- ...under this: cowers on the spot; everyone else runs
	Cover = 0.85, -- runners with nerve under this run with their arms over their heads
	FilmMin = 25,
	FilmTime = 6, -- seconds a phone stays up after the last shot
	CowerTime = 5,
	AimRange = 20, -- studs: a gun pointed at a walker this close counts
	AimCone = 0.95, -- dot product: how close to the gun's line they must stand (about 18 degrees)
	Hands = 0.6, -- nerve under this: hands up when aimed at; over it: runs
	HandsTime = 1.6, -- seconds the hands stay up after the gun last pointed at them
	MaxHands = 3,
	PoseRange = 70, -- studs from the camera: further away nobody is posed
	MaxPosed = 6, -- walkers posed at once
}

local folder
local peds = {}
local ready = false
local anims = {} -- [asset id] = its Animation (made once, shared by every walker)
local wallets = {} -- oldest first: { model, pos, dieAt, retryAt }
local pendingLoot -- { wallet, at }: the one question the server hasn't answered yet
local quietUntil = 0 -- os.clock(): no wallets drop before this (the server said "Empty")
local lootRemote
local downRemote -- "PedDown": one of ours went down (PedService counts them: the police come after the second)
local spawnRetryAt = 0 -- os.clock(): no new walkers before this (the last one failed to start)
local lazyPose -- PoseClient's module (required when first needed), false if this place doesn't have it
local Ragdoll = nil -- Shared.Util.Ragdoll, if this place has it (looked up below: a missing util must not stop the walkers)
do
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local util = shared and shared:FindFirstChild("Util")
	local module = util and util:FindFirstChild("Ragdoll")
	if module then
		local ok, result = pcall(require, module)
		Ragdoll = (ok and type(result) == "table") and result or nil
	end
end

-- The Animation for an asset id ("rbxassetid://..."), made the first time it is asked for.
local function animFor(id)
	local a = anims[id]
	if not a then
		a = Instance.new("Animation")
		a.AnimationId = id
		anims[id] = a
	end
	return a
end

-- PoseClient, or nil if this place doesn't have it (never an error: it starts before us and doesn't
-- need us).
local function poseClient()
	if lazyPose == nil then
		local module = script.Parent:FindFirstChild("PoseClient")
		local ok, result = pcall(require, module)
		lazyPose = (module ~= nil and ok and type(result) == "table" and type(result.Play) == "function") and result or false
	end
	return lazyPose or nil
end

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

-- The corner at b where the sidewalks of a->b and b->k meet on `side`, or nil when the roads run
-- (nearly) straight on or double back.
local function corner(a, b, k, side)
	local nodes = RoadGraph.Nodes
	local nb = nodes[b]
	local d1, d2 = nb - nodes[a], nodes[k] - nb
	if d1.Magnitude < 1 or d2.Magnitude < 1 then
		return nil
	end
	d1, d2 = d1.Unit, d2.Unit
	local cross = d1.X * d2.Z - d1.Z * d2.X
	if math.abs(cross) < 0.2 then
		return nil
	end
	local r1, r2 = Vector3.new(-d1.Z, 0, d1.X), Vector3.new(-d2.Z, 0, d2.X)
	local o1 = (RoadGraph.Width(a, b) / 2 + 5) * side
	local o2 = (RoadGraph.Width(b, k) / 2 + 5) * side
	-- Where the two sidewalk lines cross: nb + r1*o1 + d1*l = nb + r2*o2 + d2*m.
	local q = r2 * o2 - r1 * o1
	local l = (q.X * d2.Z - q.Z * d2.X) / cross
	local p = nb + r1 * o1 + d1 * l
	if (p - nb).Magnitude > 3 * math.max(math.abs(o1), math.abs(o2)) then
		return nil -- a hairpin: the lines meet too far away
	end
	return Vector3.new(p.X, ROAD_TOP + 3, p.Z)
end

-- What's under this spot: the ground hit if it's dry land, false over water (or below sea level),
-- nil if there's nothing there (not streamed in yet).
local groundParams = RaycastParams.new()
groundParams.IgnoreWater = false -- water must be hit, so it can be refused
local function dryGround(pos)
	local hit = Workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -40, 0), groundParams)
	if not hit then
		return nil
	end
	if hit.Material == Enum.Material.Water or hit.Position.Y < -1 then
		return false
	end
	return hit
end

-- Head for the end of the stretch a->b: pick the road after it now, and stop at the corner where the
-- two sidewalks meet (or at the end of this sidewalk when going straight on or turning back).
local function planLeg(ped)
	local options = {}
	for _, k in ipairs(neighbours(ped.b)) do
		if k ~= ped.a then
			-- Skip roads whose sidewalk on this side is over water (bridges); not-yet-streamed ground is fine.
			local mid = sidewalk(ped.b, k, (RoadGraph.Edges[ped.b][k] or 0) / 2, ped.side)
			if dryGround(mid) ~= false then
				table.insert(options, k)
			end
		end
	end
	ped.k = #options > 0 and options[math.random(#options)] or ped.a
	local _, len = sidewalk(ped.a, ped.b, 0, ped.side)
	ped.target = (ped.k ~= ped.a and corner(ped.a, ped.b, ped.k, ped.side)) or sidewalk(ped.a, ped.b, len, ped.side)
	ped.hum:MoveTo(ped.target)
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
			-- Only where dry ground is actually there (streamed in) and not right on top of the player,
			-- and not on a stretch that runs out over the water.
			local ground = d > SPAWN_MIN and d < SPAWN_MAX and dryGround(pos)
			if ground and dryGround((sidewalk(i, j, len / 2, side))) == false then
				ground = nil
			end
			if ground then
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
				-- A mixed crowd: the walk set goes with the district, the pace and the build with the walker.
				local seed = math.random(1, 1000000000)
				local set = Animations.Pick(seed, Animations.DistrictAt(pos.X, pos.Z))
				local vary = Animations.PedVariation(seed)
				for name, value in pairs({ BodyHeightScale = vary.Height, BodyWidthScale = vary.Width }) do
					local scale = hum:FindFirstChild(name)
					if scale and scale:IsA("NumberValue") then
						scale.Value = value
					end
				end
				model:PivotTo(CFrame.new(ground.Position + Vector3.new(0, 3, 0)))
				model.Parent = folder -- (an Animator only loads animations once it is in the world)
				-- From here the walker is standing in the street: if anything below goes wrong it is taken out
				-- again, so a failed start can never leave a body there that nothing moves or removes.
				local ok, ped = pcall(function()
					local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
					local function load(slot, fallback)
						local track = animator:LoadAnimation(animFor(Animations.Asset(set, slot) or fallback))
						track.Looped = true
						return track
					end
					-- walk: the strolling speed to go back to after running away. track / run / idle: the walk,
					-- run and standing cycles (only one plays at a time: setGait), played at this walker's own
					-- pace (speed). nerve: how they take gunfire (REACT), the same every time.
					local new = { model = model, hum = hum, root = root, a = i, b = j, t = t, side = side,
						track = load("walk", WALK_ANIM), run = load("run", RUN_ANIM), idle = load("idle", IDLE_ANIM),
						walk = hum.WalkSpeed, speed = vary.Speed, nerve = math.random() }
					new.track:Play()
					new.track:AdjustSpeed(new.speed)
					-- Walk to the end of this stretch.
					planLeg(new)
					return new
				end)
				if ok and ped then
					table.insert(peds, ped)
				else
					model:Destroy()
					spawnRetryAt = os.clock() + 5 -- (not five tries, and five warnings, a second)
					warn("[PedClient] a walker failed to start: " .. tostring(ped))
				end
				return
			end
		end
	end
end

local function nextLeg(ped)
	if ped.k == ped.a then
		ped.side = -ped.side -- turning back: the road's right flips, so this keeps them on the same pavement
	end
	ped.a, ped.b = ped.b, ped.k
	planLeg(ped)
end

local function removePed(i)
	local ped = peds[i]
	ped.model:Destroy()
	table.remove(peds, i)
end

------------------------------------------------------------------ bodies

-- "walk", "run" or "idle" (standing): only one of the three cycles plays, so a scared walker really
-- runs (never the stroll at double speed) and one who stops stands like a person. nil = none (lying on
-- the ground: no legs pedalling in the air).
local function setGait(ped, gait)
	local tracks = { walk = ped.track, run = ped.run, idle = ped.idle }
	for name, track in pairs(tracks) do
		if name ~= gait and track.IsPlaying then
			track:Stop(gait and 0.25 or 0.1)
		end
	end
	local want = gait and tracks[gait]
	if want and not want.IsPlaying then
		want:Play(gait == "run" and 0.15 or 0.3)
		if gait ~= "idle" then
			want:AdjustSpeed(ped.speed or 1) -- (after Play: Play sets the speed back to 1)
		end
	end
end

-- A PoseClient pose on a walker (name = nil: none). One at a time; asking for the one already showing
-- changes nothing. Without PoseClient, or on a body it can't pose, nothing shows and nothing breaks.
local function setPose(ped, name, opts)
	local old, oldName = ped.pose, ped.poseName
	if old and name ~= nil and oldName == name and old:IsPlaying() and not (opts and opts.Duration) then
		return
	end
	ped.pose, ped.poseName = nil, nil
	if old and oldName ~= name then
		old:Stop() -- (a timed pose asked for again is just played again below: it starts its time over)
	end
	local pose = name and poseClient()
	if pose then
		local ok, handle = pcall(pose.Play, ped.model, name, opts)
		if ok and type(handle) == "table" and handle:IsPlaying() then
			ped.pose, ped.poseName = handle, name
		end
	end
end

-- How many walkers are posed right now (REACT.MaxPosed is the most).
local function posedCount()
	local n = 0
	for _, ped in ipairs(peds) do
		if ped.pose and ped.pose:IsPlaying() then
			n += 1
		end
	end
	return n
end

-- Go limp for `seconds` (a bullet, a punch, a car), thrown along `push` (studs/s): every joint but the
-- root and the neck becomes a loose ball joint, so the body folds and rolls where it's sent instead of
-- tipping over stiff. Then the joints lock again, the walker gets up and `onUp` runs. Walkers live on
-- this device only, so none of this costs the server anything. Nothing gory: a fall and a get-up.
local function topple(ped, push, seconds, onUp, brace)
	local token = (ped.fallToken or 0) + 1 -- (becomes ped.fallToken once this fall has really started)
	ped.runToken = (ped.runToken or 0) + 1 -- (whatever they were doing is over: nothing puts them back to strolling mid-fall)
	ped.mood = nil
	setPose(ped, nil)
	setGait(ped, nil)
	local hum = ped.hum
	-- The shared limp body first (proper elbow and knee limits, a brace, a cap on how many at once). It
	-- says no when the cap is reached: then the simpler fall below does it. (A walker already down in
	-- the simple fall stays in it.)
	if Ragdoll and type(ped.limp) ~= "table" then
		local ok, started = pcall(Ragdoll.Start, ped.model, push, {
			Seconds = seconds,
			Brace = brace == true, -- a car coming: arms up for a moment before going limp (not for a punch or a shot)
			OnStop = function()
				if ped.fallToken ~= token then
					return
				end
				ped.limp = nil
				if ped.model.Parent and onUp then
					onUp()
				end
			end,
		})
		if ok and started then
			ped.fallToken = token
			ped.limp = true -- (everything else only asks whether it is set)
			-- Should the get-up never be reported, they are stood up anyway: nobody lies there for good.
			task.delay(seconds + 3, function()
				if ped.fallToken == token and ped.limp == true then
					ped.limp = nil
					if ped.model.Parent then
						pcall(Ragdoll.Stop, ped.model)
						if onUp then
							onUp()
						end
					end
				end
			end)
			return
		end
		if ped.limp == true then
			return -- still down in the shared fall, which wouldn't take this push: that fall's own get-up stands
		end
	end
	ped.fallToken = token
	if not ped.limp then
		local limp = { joints = {}, collide = {} }
		for _, d in ipairs(ped.model:GetDescendants()) do
			if d:IsA("Motor6D") and d.Name ~= "Root" and d.Name ~= "Neck" and d.Part0 and d.Part1 then
				local a0 = d.Part0:FindFirstChild(d.Name .. "RigAttachment")
				local a1 = d.Part1:FindFirstChild(d.Name .. "RigAttachment")
				if a0 and a1 then
					local ball = Instance.new("BallSocketConstraint")
					ball.Attachment0, ball.Attachment1 = a0, a1
					ball.LimitsEnabled = true
					ball.UpperAngle = 55
					ball.TwistLimitsEnabled = true
					ball.TwistLowerAngle, ball.TwistUpperAngle = -35, 35
					ball.Parent = d.Part1
					local apart = Instance.new("NoCollisionConstraint") -- (the two parts overlap at the joint)
					apart.Part0, apart.Part1 = d.Part0, d.Part1
					apart.Parent = d.Part1
					d.Enabled = false
					table.insert(limp.joints, { d, ball, apart })
				end
			elseif d:IsA("BasePart") and d.Parent == ped.model and d ~= ped.root then
				limp.collide[d] = d.CanCollide
				d.CanCollide = true -- limbs rest on the pavement instead of sinking into it
			end
		end
		ped.limp = limp
		hum:ChangeState(Enum.HumanoidStateType.Physics)
	end
	ped.root.AssemblyLinearVelocity = push
	local upper = ped.model:FindFirstChild("UpperTorso")
	if upper and upper:IsA("BasePart") then
		upper.AssemblyLinearVelocity = push
	end
	task.delay(seconds, function()
		if ped.fallToken ~= token or not ped.model.Parent then
			return
		end
		local limp = ped.limp
		ped.limp = nil
		if limp then
			for _, j in ipairs(limp.joints) do
				j[1].Enabled = true
				j[2]:Destroy()
				j[3]:Destroy()
			end
			for part, was in pairs(limp.collide) do
				if part.Parent then
					part.CanCollide = was
				end
			end
		end
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		if onUp then
			onUp()
		end
	end)
end

-- Fast cars nearby: jump aside. Bumped: fall over, get up after a moment.
local function react(ped, now)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return
	end
	-- Being busy (diving, scared, hands up, punched) used to switch this whole look off, and the dive
	-- itself makes them busy: cars at driving speed went straight through walkers. Now busy only stops a
	-- new dive, and a car that reaches them still knocks them over. bumpedUntil: one car knocks a walker
	-- over once, not on every look.
	local busy = ped.busyUntil ~= nil and now < ped.busyUntil
	local canBump = now >= (ped.bumpedUntil or 0)
	for _, car in ipairs(vehicles:GetChildren()) do
		local chassis = car.PrimaryPart
		if chassis then
			local rel = ped.root.Position - chassis.Position
			local vel = chassis.AssemblyLinearVelocity
			local speed = vel.Magnitude
			local dist = rel.Magnitude
			-- Bumped: touching now, or standing in the strip the car drives over before the next look
			-- (this runs five times a second: a fast car would be past them between two looks). The strip
			-- is only as wide as the car, so walkers on the pavement beside a passing car are left alone.
			local hit, along = false, 0 -- along: how many studs ahead of the car they are
			if canBump and speed > 8 then
				along = rel:Dot(vel) / speed
				hit = dist < 7 or (along > 0 and along < 7 + speed * 0.25 and (rel - vel * (along / speed)).Magnitude < 4.5)
			end
			if hit then
				ped.bumpedUntil = now + 2.5
				ped.busyUntil = math.max(ped.busyUntil or 0, now + 2.5)
				local function bump()
					if not ped.model.Parent then
						return -- (recycled while the car was on its way)
					end
					topple(ped, vel * 0.5 + Vector3.new(0, 25, 0), 2.2, function()
						-- (whatever they were busy with ended when they fell: step() takes them back now)
						ped.busyUntil = nil
						ped.hum.WalkSpeed = ped.walk
						setGait(ped, "walk")
						ped.hum:MoveTo(ped.target)
					end, true)
				end
				-- Seen from a few studs off: they fall when the car gets to them, not before it does.
				if along > 7 then
					task.delay((along - 7) / speed, bump)
				else
					bump()
				end
				return
			elseif not busy and dist < 26 and speed > 30 and vel.Unit:Dot(rel.Unit) > 0.7 then
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

------------------------------------------------------------------ wallets

local dropParams = RaycastParams.new()
dropParams.FilterType = Enum.RaycastFilterType.Exclude
dropParams.IgnoreWater = false -- (a wallet never lands on the sea)

local function removeWallet(w)
	local i = table.find(wallets, w)
	if i then
		table.remove(wallets, i)
	end
	if pendingLoot and pendingLoot.wallet == w then
		pendingLoot = nil
	end
	w.model:Destroy()
end

local function clearWallets()
	for i = #wallets, 1, -1 do
		removeWallet(wallets[i])
	end
end

local function propPart(parent, name, size, cf, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- A wallet on the ground near where a walker fell. Only citizens get one (the server pays nobody
-- else), and none while the street is quiet.
local function dropWallet(pos)
	if not folder or os.clock() < quietUntil or player:GetAttribute("Side") ~= "Civilian" then
		return
	end
	local a = math.random() * math.pi * 2
	local spot = pos + Vector3.new(math.cos(a) * 1.5, 0, math.sin(a) * 1.5)
	-- Onto the ground, not onto a car roof, a dropped bag or our own head. (Built with insert: a missing
	-- one must not leave a hole in the list.)
	local ignore = { folder }
	for _, inst in ipairs({ player.Character or false, Workspace:FindFirstChild("Vehicles") or false, Workspace:FindFirstChild("DroppedBags") or false }) do
		if inst then
			table.insert(ignore, inst)
		end
	end
	dropParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(spot + Vector3.new(0, 3, 0), Vector3.new(0, -14, 0), dropParams)
	if not hit or hit.Material == Enum.Material.Water then
		return
	end
	while #wallets >= MAX_WALLETS do
		removeWallet(wallets[1])
	end
	local at = hit.Position
	local m = Instance.new("Model")
	m.Name = "PedWallet"
	local base = CFrame.new(at + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local body = propPart(m, "Wallet", Vector3.new(1.1, 0.18, 0.75), base, WALLET_DARK)
	m.PrimaryPart = body
	propPart(m, "Strip", Vector3.new(1.12, 0.2, 0.16), base * CFrame.new(0, 0, 0.1), Theme.Color.Cash)
	-- A small "$" over it, so it can be found in the grass.
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromOffset(26, 26)
	tag.StudsOffset = Vector3.new(0, 1.4, 0)
	tag.MaxDistance = 70
	tag.LightInfluence = 0
	local sign = Instance.new("TextLabel")
	sign.Size = UDim2.fromScale(1, 1)
	sign.Text = "$"
	Theme.Text(sign, 22, "Display")
	sign.TextColor3 = Theme.Color.Cash
	sign.Parent = tag
	tag.Parent = body
	m.Parent = folder
	local now = os.clock()
	table.insert(wallets, { model = m, pos = at, dieAt = now + WALLET_LIFE, retryAt = now + 0.4 })
end

-- "+$45" floating up from where the wallet was.
local function payPop(pos, amount, stars)
	local anchor = propPart(folder, "WalletPop", Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos + Vector3.new(0, 1.5, 0)), WALLET_DARK)
	anchor.Transparency = 1
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(150, 34)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "+$" .. tostring(amount) .. (stars > 0 and "  +★" or "")
	Theme.Text(label, 26, "Display")
	label.TextColor3 = Theme.Color.Cash
	label.Parent = bb
	bb.Parent = anchor
	TweenService:Create(bb, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 2.5, 0) }):Play()
	task.delay(0.7, function()
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		local shadow = label:FindFirstChild("Shadow")
		if shadow then
			TweenService:Create(shadow, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		end
	end)
	task.delay(1.1, function()
		anchor:Destroy()
	end)
end

-- The wallet nearest to the local player (for an answer that came after we stopped waiting for it).
local function nearestWallet()
	local here = focus()
	local best, bestDist
	for _, w in ipairs(wallets) do
		local d = (w.pos - here).Magnitude
		if not bestDist or d < bestDist then
			best, bestDist = w, d
		end
	end
	return best
end

-- PedService's answer to our last "PedLoot".
local function onLoot(result, amount, stars)
	local asked = pendingLoot and pendingLoot.wallet or nil
	pendingLoot = nil
	if result == "Paid" then
		local w = asked or nearestWallet()
		amount = math.floor(tonumber(amount) or 0)
		if w then
			if amount > 0 then
				payPop(w.pos, amount, tonumber(stars) or 0)
			end
			removeWallet(w)
		end
		task.spawn(function()
			pcall(function()
				require(script.Parent:WaitForChild("SoundClient")).Play("Cash")
			end)
		end)
	elseif result == "Empty" then
		-- The street has gone quiet (the server's toast says so): wallets are empty for a while.
		quietUntil = os.clock() + QUIET_FOR
		clearWallets()
	elseif asked then
		asked.retryAt = os.clock() + LOOT_RETRY
	end
end

-- Five times a second: old wallets go; on foot next to one, ask the server for it.
local function checkWallets(now)
	if #wallets == 0 then
		return
	end
	for i = #wallets, 1, -1 do
		local w = wallets[i]
		if now >= w.dieAt or not w.model.Parent then
			removeWallet(w)
		end
	end
	if pendingLoot then
		if now - pendingLoot.at < LOOT_TIMEOUT then
			return
		end
		pendingLoot.wallet.retryAt = now + LOOT_RETRY -- no answer: stop waiting, try again in a moment
		pendingLoot = nil
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not lootRemote or not hum or not root or hum.Health <= 0 or hum.SeatPart
		or player:GetAttribute("Side") ~= "Civilian" or player:GetAttribute("Passive") == true then
		return
	end
	local here = root.Position
	for _, w in ipairs(wallets) do
		if now >= w.retryAt then
			local rel = w.pos - here
			if math.abs(rel.Y) < 6 and Vector3.new(rel.X, 0, rel.Z).Magnitude <= PICKUP_RANGE then
				pendingLoot = { wallet = w, at = now }
				lootRemote:FireServer(w.pos)
				return
			end
		end
	end
end

------------------------------------------------------------------ the loop

local function step()
	local now = os.clock()
	checkWallets(now)
	if not ready then
		return
	end
	local here = focus()
	local flat = Vector3.new(here.X, 0, here.Z)
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

-- Where the walkers are (TrafficClient stops for them when they cross in front of a car).
function PedClient.Positions()
	local list = {}
	for _, ped in ipairs(peds) do
		if ped.model.Parent then
			table.insert(list, ped.root.Position)
		end
	end
	return list
end

------------------------------------------------------------------ fights

-- Back to strolling, once whatever they were doing is over. Only the latest scare (or fall) does it:
-- token is ped.runToken as it was when that one began, so an older one never ends a newer one early.
local function settle(ped, token)
	if not ped.hum.Parent or ped.runToken ~= token or ped.limp then
		return
	end
	ped.mood = nil
	-- (a run can now end before its busy time does: step() takes them back from here, or one who
	-- reached the end of their stretch early would stand there walking on the spot)
	ped.busyUntil = nil
	setPose(ped, nil)
	ped.hum.WalkSpeed = ped.walk
	setGait(ped, "walk")
	ped.hum:MoveTo(ped.target)
end

-- Sprint away from `from` for `seconds` (no longer than the run itself takes), then go back to
-- strolling. cover: run with both arms thrown over the head (PoseClient's "Brace" held for the whole
-- run: arms and a hunch only, the legs keep running).
local function runFrom(ped, from, seconds, fallback, cover)
	local away = ped.root.Position - from
	away = Vector3.new(away.X, 0, away.Z)
	away = away.Magnitude > 0.1 and away.Unit or fallback
	-- They run 45 studs, which takes 2.5 s. With a longer timer they got there, stopped, and stood
	-- sprinting on the spot with their arms over their heads until it ran out: the run ends on arrival.
	local far = 45
	seconds = math.min(seconds, far / RUN_SPEED)
	local token = (ped.runToken or 0) + 1
	ped.runToken = token
	ped.mood = "flee"
	ped.hum.WalkSpeed = RUN_SPEED
	setGait(ped, "run")
	if cover then
		setPose(ped, "Brace", { Duration = seconds, FadeIn = 0.15, FadeOut = 0.3 })
	else
		setPose(ped, nil)
	end
	ped.hum:MoveTo(ped.root.Position + away * far)
	task.delay(seconds, function()
		settle(ped, token)
	end)
end

-- Stop where they are for `seconds` in a pose (cowering, hands up, filming), turned toward `toward` if
-- given. Afterwards they stroll on, or, with fleeFrom, hurry away from that spot first. Asked again
-- while it lasts, the time simply starts over.
local function freeze(ped, mood, poseName, seconds, toward, fleeFrom)
	local token = (ped.runToken or 0) + 1
	ped.runToken = token
	local here = ped.root.Position
	if ped.mood ~= mood then
		ped.mood = mood
		ped.hum.WalkSpeed = ped.walk
		ped.hum:MoveTo(here) -- (stops them)
		setGait(ped, "idle")
		if toward then
			local look = Vector3.new(toward.X - here.X, 0, toward.Z - here.Z)
			if look.Magnitude > 0.5 then
				ped.root.CFrame = CFrame.lookAt(here, here + look)
			end
		end
	end
	setPose(ped, poseName)
	ped.moodUntil = os.clock() + seconds
	task.delay(seconds, function()
		if fleeFrom and ped.hum.Parent and ped.runToken == token and not ped.limp then
			runFrom(ped, fleeFrom, 3, Vector3.new(0, 0, 1), false)
		else
			settle(ped, token)
		end
	end)
end

-- A walker is hit (a punch or a bullet, coming from `from`): they go limp along `dir` (flat unit vector)
-- for 2 s, then get up, run away (45 studs) and go back to strolling. A wallet drops where they fell.
local function knockDown(ped, dir, from)
	local now = os.clock()
	ped.busyUntil = now + 5 -- step() leaves it alone until then, and it won't dive (a car can still bump it)
	ped.punchedUntil = now + 2.5 -- on the ground for 2 s, half a second to stand: then a punch or a bullet counts again (was 5: three seconds on their feet that nothing could touch)
	topple(ped, dir * 16 + Vector3.new(0, 10, 0), 2, function()
		runFrom(ped, from, 3, dir, ped.nerve < REACT.Cover and posedCount() < REACT.MaxPosed)
	end)
	dropWallet(ped.root.Position)
	if downRemote then
		downRemote:FireServer()
	end
end

-- A punch thrown at `position` facing `lookVector`: the nearest walker within 7 studs in front (who
-- isn't already down) falls over for 2 s, then runs away for a few seconds and goes back to strolling.
function PedClient.KnockNear(position, lookVector)
	if typeof(position) ~= "Vector3" or typeof(lookVector) ~= "Vector3" then
		return false
	end
	local look = Vector3.new(lookVector.X, 0, lookVector.Z)
	if look.Magnitude < 0.05 then
		return false
	end
	look = look.Unit
	local now = os.clock()
	local best, bestDist
	for _, ped in ipairs(peds) do
		if ped.model.Parent and not (ped.punchedUntil and now < ped.punchedUntil) then
			local rel = ped.root.Position - position
			local flatRel = Vector3.new(rel.X, 0, rel.Z)
			local d = flatRel.Magnitude
			if d <= 7 and math.abs(rel.Y) < 6 and (d < 0.5 or flatRel.Unit:Dot(look) > 0.35) and (not bestDist or d < bestDist) then
				best, bestDist = ped, d
			end
		end
	end
	if not best then
		return false
	end
	knockDown(best, look, position)
	return true
end

-- The walker under the crosshair: the nearest one on their feet whose body the line from `origin` along
-- `dir` passes through (a column from their feet to just over their head, a little wider far away),
-- no further than maxDistance. Returns the middle of their body, or nil.
-- CombatClient aims the bullet there. Walkers can't be seen by raycasts, so the crosshair's own ray went
-- straight through them to the wall behind, and the bullet (it starts at the shooter's head, 2.4 studs
-- to the side of the camera's line) then passed just outside HitRadius: in an open street a shot with the
-- crosshair dead on a walker MISSED, and the owner found it "takes a long time" to drop anyone.
function PedClient.Under(origin, dir, maxDistance)
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or type(maxDistance) ~= "number" or dir.Magnitude < 0.05 then
		return nil
	end
	dir = dir.Unit
	local now = os.clock()
	local best, bestAlong
	for _, ped in ipairs(peds) do
		if ped.model.Parent and not (ped.punchedUntil and now < ped.punchedUntil) then
			local centre = ped.root.Position
			local along = (centre - origin):Dot(dir)
			if along > 0 and along <= maxDistance and (not bestAlong or along < bestAlong) then
				local off = origin + dir * along - centre -- where the line passes them, from their middle
				if Vector3.new(off.X, 0, off.Z).Magnitude <= 1.7 + along * 0.012 and off.Y >= -3.4 and off.Y <= 2.8 then
					best, bestAlong = ped, along
				end
			end
		end
	end
	return best and best.root.Position or nil
end

-- A bullet from `origin` along `dir` that ends maxDistance studs away (at a wall, or at the end of the
-- gun's range). The nearest standing walker within HitRadius of that line falls. Returns the point on
-- the line where the shot met them, or nil when it met nobody.
function PedClient.ShotAt(origin, dir, maxDistance)
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or type(maxDistance) ~= "number" or dir.Magnitude < 0.05 then
		return nil
	end
	dir = dir.Unit
	local now = os.clock()
	local best, bestAlong
	for _, ped in ipairs(peds) do
		if ped.model.Parent and not (ped.punchedUntil and now < ped.punchedUntil) then
			local to = ped.root.Position - origin
			local along = to:Dot(dir) -- how far down the shot they are
			if along > 0 and along <= maxDistance and (to - dir * along).Magnitude <= HIT_RADIUS
				and (not bestAlong or along < bestAlong) then
				best, bestAlong = ped, along
			end
		end
	end
	if not best then
		return nil
	end
	local push = Vector3.new(dir.X, 0, dir.Z)
	push = push.Magnitude > 0.05 and push.Unit or Vector3.new(0, 0, -1)
	knockDown(best, push, origin)
	return origin + dir * bestAlong
end

-- May this walker react to something right now? (In the world, on their feet, not just knocked over.)
local function canReact(ped, now)
	return ped.model.Parent ~= nil and not ped.limp and not (ped.punchedUntil and now < ped.punchedUntil)
end

-- Gunfire at `position`: every walker within ScareRange who is on their feet reacts (see the header):
-- most sprint away (45 studs) with their arms over their heads, some cower where they stand, a few far
-- enough away stop and film it. Which one is the walker's own nerve, so they do the same every time.
-- Poses only near the camera and only REACT.MaxPosed at once; everyone else simply runs.
function PedClient.Scare(position)
	if typeof(position) ~= "Vector3" then
		return
	end
	local now = os.clock()
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or position
	local posed = posedCount()
	for _, ped in ipairs(peds) do
		local here = ped.root.Position
		local dist = (here - position).Magnitude
		if canReact(ped, now) and dist <= SCARE_RANGE then
			ped.busyUntil = math.max(ped.busyUntil or 0, now + SCARE_TIME)
			local mayPose = ped.pose ~= nil or (posed < REACT.MaxPosed and (here - camPos).Magnitude <= REACT.PoseRange)
			local nerve = ped.nerve or 1
			local before = ped.pose
			if mayPose and nerve < REACT.Film and dist >= REACT.FilmMin then
				ped.busyUntil = math.max(ped.busyUntil, now + REACT.FilmTime)
				freeze(ped, "film", "PhoneLook", REACT.FilmTime, position)
			elseif mayPose and nerve >= REACT.Film and nerve < REACT.Cower then
				ped.busyUntil = math.max(ped.busyUntil, now + REACT.CowerTime)
				freeze(ped, "cower", "Cower", REACT.CowerTime)
			else
				-- (someone filming who now finds the shots too close runs like everybody else)
				runFrom(ped, position, SCARE_TIME, Vector3.new(0, 0, 1), mayPose and nerve < REACT.Cover)
			end
			if ped.pose and not before then
				posed += 1
			end
		end
	end
end

-- A raised gun points along `dir` from `origin` (CombatClient calls this about twice a second while
-- the local player aims). Walkers within REACT.AimRange who stand close to that line stop, turn to the
-- gun and put their hands up, REACT.MaxHands of them at most; the nervous ones run instead. The hands
-- stay up while the gun stays on them, and when it moves away they hurry off.
function PedClient.AimedAt(origin, dir)
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" or dir.Magnitude < 0.05 then
		return
	end
	dir = dir.Unit
	local now = os.clock()
	local hands = 0
	for _, ped in ipairs(peds) do
		if ped.mood == "hands" then
			hands += 1
		end
	end
	local posed = posedCount()
	for _, ped in ipairs(peds) do
		local to = ped.root.Position - origin
		local dist = to.Magnitude
		if canReact(ped, now) and dist > 2 and dist <= REACT.AimRange and to.Unit:Dot(dir) > REACT.AimCone then
			local after = REACT.HandsTime + 3 -- (the hands, then the run)
			if ped.mood == "hands" then
				ped.busyUntil = math.max(ped.busyUntil or 0, now + after)
				freeze(ped, "hands", "HandsUp", REACT.HandsTime, origin, origin) -- still on them: the time starts over
			elseif ped.mood == nil then
				ped.busyUntil = math.max(ped.busyUntil or 0, now + after)
				if (ped.nerve or 1) < REACT.Hands and hands < REACT.MaxHands and posed < REACT.MaxPosed then
					hands += 1
					posed += 1
					freeze(ped, "hands", "HandsUp", REACT.HandsTime, origin, origin)
				else
					runFrom(ped, origin, 3, Vector3.new(0, 0, 1), false)
				end
			end
		end
	end
end

-- A driver thrown out of their car by a carjacking: a walker (not one of the strolling peds) who jumps out
-- at `position`, runs off along `direction` and fades away after FLEE_TIME seconds.
local FLEE_TIME = 4
function PedClient.Flee(position, direction)
	if typeof(position) ~= "Vector3" or typeof(direction) ~= "Vector3" or not folder then
		return false
	end
	local templates = ReplicatedStorage:FindFirstChild("PedTemplates")
	local list = templates and templates:GetChildren() or {}
	if #list == 0 then
		return false
	end
	local dir = Vector3.new(direction.X, 0, direction.Z)
	dir = dir.Magnitude > 0.05 and dir.Unit or Vector3.new(0, 0, 1)
	local model = list[math.random(#list)]:Clone()
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not hum or not root then
		model:Destroy()
		return false
	end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanQuery = false
			part.CastShadow = false
			part.CollisionGroup = "Traffic"
		end
	end
	model:PivotTo(CFrame.lookAt(position, position + dir))
	model.Parent = folder
	-- A real run cycle (never the stroll played fast). A failed load only costs the animation.
	pcall(function()
		local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
		local track = animator:LoadAnimation(animFor(Animations.Asset("Default", "run") or RUN_ANIM))
		track.Looped = true
		track:Play()
		track:AdjustSpeed(1.15)
	end)
	hum.WalkSpeed = 20
	hum.Jump = true -- a panicked hop out of the door
	hum:MoveTo(position + dir * 80)
	task.delay(FLEE_TIME, function()
		for i = 1, 10 do
			if not model.Parent then
				return
			end
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") then
					part.LocalTransparencyModifier = i / 10
				end
			end
			task.wait(0.05)
		end
		model:Destroy()
	end)
	return true
end

function PedClient.Init()
	folder = Instance.new("Folder")
	folder.Name = "Peds"
	folder.Parent = Workspace
	groundParams.FilterDescendantsInstances = { folder }
	-- Wallet pickups: the server decides (PedService). Each remote is fetched in its own thread, so a
	-- remote the server hasn't made yet never holds up the other controllers.
	task.spawn(function()
		lootRemote = Remotes.Event("PedLoot")
	end)
	task.spawn(function()
		downRemote = Remotes.Event("PedDown")
	end)
	Remotes.OnClient("PedLoot", onLoot)
	-- A new character starts with a clean street (a side switch respawns you: cops get no wallets).
	player.CharacterAdded:Connect(clearWallets)
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
