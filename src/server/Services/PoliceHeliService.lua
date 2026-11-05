-- PoliceHeliService (ModuleScript, ServerScriptService.Services.PoliceHeliService)
-- The police helicopter (owner, Nov 4: "if you have 4 stars, there should be a helicopter after you.
-- With the cops." Then: "If you think the helicopters are too much for 4 stars, then make the
-- helicopters only for 5 stars ... I trust your judgment"). It comes at 5 stars: a bank or yacht job plus
-- one carjack already makes 4, so 4 stars is the usual getaway from the biggest heists, and it now
-- brings 4 patrol cars. 5 stars takes going on a rampage, and the helicopter is what tops it off.
--   * One per wanted citizen at 5 stars (STARS), at most MAX_HELIS in the server, on top of the patrol
--     cars. It comes even when player cops patrol (AIPoliceService's cars don't then): it never arrests
--     anyone, it only watches, so a player cop's bounty stays theirs and they get the sightings.
--   * It is a HeatService "eye" with a longer reach than a patrol car (SIGHT studs, from up there), so
--     while it can see you your stars stay solid. Break its line of sight (a tunnel, an overpass, a parking
--     garage, indoors) or outrun it: it flies at most SPEED_SHARE of your car's top speed (on foot counts
--     as 120, as for the patrol cars), so a fast car on an open road gets away.
--   * Seen (HeatSpotted): it follows you HOVER studs up, hanging back TRAIL studs behind a moving target.
--     Not seen: it circles the last place it saw you (not HeatService's 20 s LastSeen ping, or it would
--     always know), sweeping its searchlight round there, until you're seen again or the heat goes.
--   * Head start: it lifts off DELAY s after the chase started (WantedSince, the 5-star head start of
--     the patrol cars) and comes in from SPAWN_DIST studs away, so you hear it before it sees you. The
--     target hears about it once a chase (Notify "PoliceHeli").
--   * It flies off (gone after LEAVE_SECONDS) once its target is under 5 stars, caught, on another side
--     or gone; or after LOST_SECONDS more than LOST_RANGE away. After that a new one comes only once the
--     cops have seen them again (HeatSpotted) and RETRY_AFTER s have passed: outrunning it counts.
--   * It keeps CLEAR studs over the tallest thing under it and ahead of it (down-rays SKY_EVERY s;
--     downtown's towers are 200 studs), climbing fast and coming down slowly.
-- The server moves one invisible anchored part per helicopter that nothing touches or hits
-- (Workspace.PoliceAir, "PoliceHeli"; attributes AITarget = the target's UserId, Lock = true while it is
-- on them, Aim = where the searchlight sweeps while it searches, Leaving). Every device builds the look,
-- the rotor, the flashing lights, the searchlight and the sound itself and glides it after that part
-- (PoliceHeliClient).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local HeatService = require(ServerScriptService.Services.HeatService)

local PoliceHeliService = {}

local STARS = 5 -- stars that bring it (the top of the wanted level; see the header)
local MAX_HELIS = 2 -- in the whole server (ones flying off don't count)
local DELAY = 4 -- seconds after WantedSince before it comes (the patrol cars' 5-star head start)
local SPAWN_DIST = 700 -- studs off the target it comes in from
local SPAWN_UP = 260 -- studs over the target it comes in at
local SIGHT = 350 -- studs: its reach as an eye (a patrol car's is 250)
local HOVER = 90 -- studs over the target
local CLEAR = 35 -- studs over the tallest thing under it
local SKY_TOP = 600 -- the down-rays start this high
local LOOKAHEAD = 2.2 -- seconds of flight ahead it checks the skyline for
local SKY_EVERY = 0.1 -- seconds between skyline checks
local CLIMB, SINK = 70, 22 -- studs/s up, down
local TRAIL = 45 -- studs behind a moving target
local GAIN = 0.9 -- per second: how hard it closes in on where it wants to be
local ACCEL = 55 -- studs/s/s
local SPEED_SHARE = 0.85 -- of the target's top speed
local MIN_SPEED, MAX_SPEED = 60, 150
local ORBIT_RADIUS, ORBIT_SPEED = 85, 45 -- the search circle round the last sighting
local SWEEP = 40 -- studs the searchlight wanders round the last sighting
local YAW_RATE = 1.4 -- radians/s it can turn
local LOST_RANGE, LOST_SECONDS = 1200, 20
local RETRY_AFTER = 30
local LEAVE_SPEED, LEAVE_SECONDS = 110, 9
local AIM_EVERY = 0.15 -- seconds between Aim updates

local helis = {} -- { part, target, pos, vel, yaw, roll, seenAt, orbit, lostFor, sky, skyAt, aimAt, leaving }
local gaveUpAt = {} -- [player] = os.clock() its helicopter last lost them (RETRY_AFTER)
local toldFor = {} -- [player] = the WantedSince of the chase they heard about it in
local folder, notify
local rng = Random.new()

local skyParams = RaycastParams.new()
skyParams.FilterType = Enum.RaycastFilterType.Exclude
skyParams.IgnoreWater = true

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function wanted(p)
	return p.Parent == Players and p:GetAttribute("Side") == "Civilian" and (p:GetAttribute("Heat") or 0) >= STARS
end

-- Where the target is, how fast it moves and how fast it could go (as AIPoliceService's targetInfo).
local function targetInfo(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root then
		return nil
	end
	local seat = hum.SeatPart
	local car = seat and seat.Parent
	local chassis = car and car:IsA("Model") and car.PrimaryPart
	if chassis then
		return { pos = chassis.Position, vel = chassis.AssemblyLinearVelocity, maxSpeed = car:GetAttribute("MaxSpeed") or 120 }
	end
	return { pos = root.Position, vel = root.AssemblyLinearVelocity, maxSpeed = 120 }
end

-- The skyline rays skip everything that moves: vehicles, officers, smoke and every player.
local function setSkyFilter()
	local list = {}
	for _, name in ipairs({ "Vehicles", "NPCs", "Smoke" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(list, pl.Character)
		end
	end
	skyParams.FilterDescendantsInstances = list
end

-- The top of whatever stands at (x, z): a roof, a tree, the ground (-inf over nothing at all).
local function skyline(x, z)
	local hit = Workspace:Raycast(Vector3.new(x, SKY_TOP, z), Vector3.new(0, -SKY_TOP - 200, 0), skyParams)
	return hit and hit.Position.Y or -math.huge
end

local function heliFor(p)
	for _, h in ipairs(helis) do
		if h.target == p and not h.leaving then
			return h
		end
	end
	return nil
end

local function flyingCount()
	local n = 0
	for _, h in ipairs(helis) do
		if not h.leaving then
			n += 1
		end
	end
	return n
end

local function setAttr(part, key, value)
	if part:GetAttribute(key) ~= value then
		part:SetAttribute(key, value)
	end
end

local function remove(h)
	for i, x in ipairs(helis) do
		if x == h then
			table.remove(helis, i)
			break
		end
	end
	HeatService.UnregisterEye(h.part)
	h.part:Destroy()
end

-- Stop watching and fly off, away from where it was searching, climbing.
local function leave(h)
	if h.leaving then
		return
	end
	h.leaving = os.clock()
	HeatService.UnregisterEye(h.part)
	setAttr(h.part, "Lock", false)
	setAttr(h.part, "Leaving", true)
	local away = flat(h.pos - h.seenAt)
	if away.Magnitude < 1 then
		away = Vector3.new(-math.sin(h.yaw), 0, -math.cos(h.yaw))
	end
	h.leaveDir = away.Unit
end

local function spawnFor(p, info)
	local seen = p:GetAttribute("LastSeen")
	local at = typeof(seen) == "Vector3" and seen or info.pos
	local a = rng:NextNumber(0, math.pi * 2)
	local start = Vector3.new(at.X + math.cos(a) * SPAWN_DIST, at.Y + SPAWN_UP, at.Z + math.sin(a) * SPAWN_DIST)
	local face = flat(at - start).Unit
	local yaw = math.atan2(-face.X, -face.Z)
	local part = Instance.new("Part")
	part.Name = "PoliceHeli"
	part.Size = Vector3.new(5, 4, 11)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.CFrame = CFrame.new(start) * CFrame.Angles(0, yaw, 0)
	part:SetAttribute("AITarget", p.UserId)
	part:SetAttribute("Lock", false)
	part:SetAttribute("Aim", at)
	part.Parent = folder
	HeatService.RegisterEye(part, SIGHT)
	table.insert(helis, {
		part = part,
		target = p,
		pos = start,
		vel = Vector3.zero,
		yaw = yaw,
		roll = 0,
		seenAt = at,
		orbit = a, -- (it joins the search circle on the side it came from)
		lostFor = 0,
		sky = -math.huge,
		skyAt = 0,
		aimAt = 0,
	})
	-- Once a chase: the helicopter is coming.
	local since = p:GetAttribute("WantedSince") or 0
	if toldFor[p] ~= since then
		toldFor[p] = since
		notify:FireClient(p, "PoliceHeli")
	end
end

-- Speed up or slow down toward `want` (studs/s, flat), at most ACCEL.
local function accelerate(h, want, dt)
	local dv = want - h.vel
	local most = ACCEL * dt
	if dv.Magnitude > most then
		dv = dv.Unit * most
	end
	h.vel += dv
end

-- Point the part: nose along the flight (or at the aim point while hovering), banked into turns and
-- dipped with speed.
local function pose(h, dt, aim)
	local face
	if h.vel.Magnitude > 12 then
		face = h.vel.Unit
	elseif aim then
		local d = flat(aim - h.pos)
		face = d.Magnitude > 1 and d.Unit or nil
	end
	local turnRate = 0
	if face then
		local want = math.atan2(-face.X, -face.Z)
		local diff = (want - h.yaw + math.pi) % (math.pi * 2) - math.pi
		local turn = math.clamp(diff, -YAW_RATE * dt, YAW_RATE * dt)
		h.yaw += turn
		turnRate = dt > 0 and turn / dt or 0
	end
	local fwd = Vector3.new(-math.sin(h.yaw), 0, -math.cos(h.yaw))
	h.roll += (math.clamp(turnRate * 0.3, -0.35, 0.35) - h.roll) * math.min(1, dt * 3)
	local pitch = -math.clamp(h.vel:Dot(fwd) / MAX_SPEED, -0.5, 1) * math.rad(12)
	h.part.CFrame = CFrame.new(h.pos) * CFrame.Angles(0, h.yaw, 0) * CFrame.Angles(pitch, 0, h.roll)
end

local function step(h, dt, now)
	if not h.part.Parent then
		return remove(h)
	end
	local p = h.target
	if not h.leaving and not wanted(p) then
		leave(h)
	end
	if h.leaving then
		accelerate(h, h.leaveDir * LEAVE_SPEED, dt)
		h.pos = Vector3.new(h.pos.X + h.vel.X * dt, h.pos.Y + CLIMB * 0.5 * dt, h.pos.Z + h.vel.Z * dt)
		pose(h, dt, nil)
		if now - h.leaving > LEAVE_SECONDS then
			remove(h)
		end
		return
	end

	local info = targetInfo(p)
	local lock = info ~= nil and p:GetAttribute("HeatSpotted") == true
	local goal, aim
	if lock then
		-- On them: hang back behind a moving target, or hold where it is over a still one.
		h.seenAt = info.pos
		local v = flat(info.vel)
		local back
		if v.Magnitude > 8 then
			back = -v.Unit * TRAIL
		else
			local off = flat(h.pos - info.pos)
			back = off.Magnitude > 1 and off.Unit * TRAIL or Vector3.new(0, 0, TRAIL)
		end
		goal = info.pos + back
		aim = info.pos
	else
		-- Lost them: circle the last sighting, the searchlight wandering round it.
		local c = h.seenAt
		h.orbit += ORBIT_SPEED / ORBIT_RADIUS * dt
		goal = c + Vector3.new(math.cos(h.orbit) * ORBIT_RADIUS, 0, math.sin(h.orbit) * ORBIT_RADIUS)
		aim = c + Vector3.new(math.sin(now * 0.53) * SWEEP, 0, math.cos(now * 0.41) * SWEEP)
	end

	-- Too far behind for too long: it gives up (another can come later).
	if info and flat(info.pos - h.pos).Magnitude > LOST_RANGE then
		h.lostFor += dt
		if h.lostFor > LOST_SECONDS then
			gaveUpAt[p] = now
			return leave(h)
		end
	else
		h.lostFor = 0
	end

	-- Across: close in on the goal (matching the target's own speed while on them), never faster than
	-- its share of the target's top speed.
	local top = math.clamp((info and info.maxSpeed or 120) * SPEED_SHARE, MIN_SPEED, MAX_SPEED)
	local want = (lock and flat(info.vel) or Vector3.zero) + flat(goal - h.pos) * GAIN
	if want.Magnitude > top then
		want = want.Unit * top
	end
	accelerate(h, want, dt)

	-- Up: HOVER over the target (or the last sighting), CLEAR over the skyline under it and ahead.
	if now >= h.skyAt then
		h.skyAt = now + SKY_EVERY
		local mid, far = h.pos + h.vel * (LOOKAHEAD / 2), h.pos + h.vel * LOOKAHEAD
		h.sky = math.max(skyline(h.pos.X, h.pos.Z), skyline(mid.X, mid.Z), skyline(far.X, far.Z))
	end
	local wantY = math.max((info and info.pos.Y or h.seenAt.Y) + HOVER, h.sky + CLEAR)
	local y = h.pos.Y
	y = wantY > y and math.min(wantY, y + CLIMB * dt) or math.max(wantY, y - SINK * dt)
	h.pos = Vector3.new(h.pos.X + h.vel.X * dt, y, h.pos.Z + h.vel.Z * dt)
	pose(h, dt, aim)

	setAttr(h.part, "Lock", lock)
	if not lock and now >= h.aimAt then
		h.aimAt = now + AIM_EVERY
		local old = h.part:GetAttribute("Aim")
		if typeof(old) ~= "Vector3" or (old - aim).Magnitude > 1 then
			h.part:SetAttribute("Aim", aim)
		end
	end
end

local function manage()
	setSkyFilter()
	local t = Workspace:GetServerTimeNow()
	local clock = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		if (p:GetAttribute("Heat") or 0) <= 0 then
			gaveUpAt[p] = nil -- (a new chase starts afresh)
		elseif wanted(p) and not heliFor(p) and flyingCount() < MAX_HELIS then
			local since = p:GetAttribute("WantedSince")
			local ready = typeof(since) ~= "number" or t >= since + DELAY
			local gaveUp = gaveUpAt[p]
			local rested = gaveUp == nil or (clock - gaveUp > RETRY_AFTER and p:GetAttribute("HeatSpotted") == true)
			local info = ready and rested and targetInfo(p)
			if info then
				spawnFor(p, info)
			end
		end
	end
end

function PoliceHeliService.Count()
	return #helis
end

function PoliceHeliService.Init()
	notify = Remotes.Event("Notify")
	folder = Instance.new("Folder")
	folder.Name = "PoliceAir"
	folder.Parent = Workspace
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(manage)
			if not ok then
				warn("[PoliceHeli] " .. tostring(err))
			end
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for i = #helis, 1, -1 do
			local h = helis[i]
			if h then
				local ok, err = pcall(step, h, dt, now)
				if not ok then
					warn("[PoliceHeli] " .. tostring(err))
					remove(h)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		gaveUpAt[p] = nil
		toldFor[p] = nil
	end)
end

return PoliceHeliService
