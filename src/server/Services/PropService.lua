-- PropService (ModuleScript, ServerScriptService.Services.PropService)
-- Street furniture a car can plow through. Hydrants, bins, news boxes, benches, lamp posts and signal
-- poles used to be anchored walls: a car that touched one stopped dead (or sat wedged against it).
-- Now cars drive through them, and one hit at speed knocks the thing over for everybody.
--   * Collision group "Props": never collides with "Vehicles" (every CarBuilder car) or "Traffic"
--     (ambient cars and walkers), still collides with everything else, so people stand on a bench and
--     walk into a pole as before. Every part of every breakable prop is put in it at start-up.
--   * What counts (Workspace.City.Art, by the names the art tools give them): Models Hydrant, TrashCan,
--     Bench, PlazaBench, TrafficSignal, StreetLight and Parts NewsBox. Billboards, palms, parked cars and
--     shop signs stay solid. An instance with the attribute Unbreakable = true is left alone.
--     Each prop gets the tag "Breakable" and the attribute Kind ("Hydrant", "TrashCan", "NewsBox",
--     "Bench", "TrafficSignal", "StreetLight"). Models also get their main part as PrimaryPart (Body, Can,
--     Seat or Pole) and stream to each device whole (ModelStreamingMode Atomic).
--     A beach bench stands on a loose block (a sibling Part "BenchBase", Art/Beach): at start-up that
--     block is moved into its bench's Model, so it goes down with the bench instead of staying behind
--     as a wall. Nothing else in the map is moved.
--   * Remote "PropHit", both ways:
--       device -> server (prop, the car's velocity): "my car just drove through this". The driver's
--         device owns its car, so it spots the hit (PropClient). We check it: rate limit, the prop is
--         Breakable and standing, the sender really is driving a moving car within about 25 studs of it
--         (more for a fast car: the two sides see slightly old positions), and the speed makes sense.
--       server -> every device (prop, BrokenUntil, velocity, SpoutUntil or nil): it went down. Each
--         device hides the standing prop and throws its own loose copy (PropClient).
--   * Prop attributes, for devices the prop reaches later (streaming, late joiners). Times are server
--     time (Workspace:GetServerTimeNow):
--       BrokenUntil  knocked over until then (45 s); a time in the past means it is standing
--       HitVel       the flat velocity of the car that hit it
--       SpoutUntil   hydrants only: water sprays out of the ground until then (12 s)
--     Nothing is cleaned up when the time passes: an old time simply means "standing again".
--   * No punishment: no heat, no cost. Each prop knocked over reports
--     ProgressService.Event(player, "PropSmash", 1) (no XP today; there for future goals).
--   * Car spawn checks (VehicleService / CarjackService SOLID_PROPS) still keep new cars off props.
--     That is harmless now and is left as it is.
--   * Only the car's body passes through by itself. Rays aimed down at the ground (CarPhysics' wheel
--     rays) and the bodies of the people sitting in the car still meet a standing prop: the driver's
--     device takes care of both for its own car (PropClient makes the props around it pass-through).
-- Public:
--   PropService.Register(inst, kind?) -> bool   make one more Model / Part breakable (kind: one of the
--                                               Kind names above; left out, the instance's Name decides)
--   PropService.Break(prop, velocity) -> bool   knock a standing prop over for everyone (no checks on
--                                               who did it: for other services)
--   PropService.IsDown(prop) -> bool

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)

local PropService = {}

local K = {
	Tag = "Breakable",
	Group = "Props",
	PassThrough = { "Vehicles", "Traffic" }, -- groups that never collide with a prop
	DownTime = 45, -- seconds a prop stays knocked over
	SpoutTime = 12, -- seconds a broken hydrant sprays
	Reach = 25, -- studs between the car and the prop...
	LagReach = 0.3, -- ...plus this many seconds of the car's speed (the two sides see old positions)...
	LagMax = 45, -- ...but never more than this
	HeightGap = 30, -- studs up or down: a car on a bridge can't hit the lamp post under it
	MinClaim = 10, -- studs/s: PropClient breaks things from 12; slower than this is not a hit
	MaxClaim = 450, -- studs/s: faster than any car
	MinSeen = 4, -- studs/s the server must see the car doing (a parked car can't knock anything over)
	PerSecond = 6, -- hits a player may report per second...
	Burst = 10, -- ...after a burst of this many (a fast run down a row of lamp posts)
	BaseName = "BenchBase", -- the loose block a beach bench stands on (Art/Beach)...
	BaseReach = 3, -- ...and how far (studs, flat) it may be from the seat of the bench it belongs to
}

-- What can be knocked over, by the name the art tools gave it (Restyle.PROPS and signal, Look3's
-- plaza bench, ArtKit.StreetLight and ArtKit.Bench). Main = the part that carries the prop.
local KINDS = {
	Hydrant = { Kind = "Hydrant", Class = "Model", Main = "Body" },
	TrashCan = { Kind = "TrashCan", Class = "Model", Main = "Can" },
	Bench = { Kind = "Bench", Class = "Model", Main = "Seat" },
	PlazaBench = { Kind = "Bench", Class = "Model", Main = "Seat" },
	NewsBox = { Kind = "NewsBox", Class = "BasePart" },
	TrafficSignal = { Kind = "TrafficSignal", Class = "Model", Main = "Pole" },
	StreetLight = { Kind = "StreetLight", Class = "Model", Main = "Pole" },
}

local hitRemote
local ProgressService -- found on first use (it starts before us); false = not there

local function ensureGroups()
	-- "Vehicles" and "Traffic" belong to CarBuilder.EnsureGroups, which makes them the same way (only
	-- if missing), so it doesn't matter which of us runs first.
	for _, name in ipairs({ K.Group, "Vehicles", "Traffic" }) do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	for _, other in ipairs(K.PassThrough) do
		PhysicsService:CollisionGroupSetCollidable(K.Group, other, false)
	end
end

-- The part a prop is measured from: itself, or a Model's named main part (else the PrimaryPart it
-- already has, else any part).
local function mainPart(inst, def)
	if inst:IsA("BasePart") then
		return inst
	end
	local main = def.Main and inst:FindFirstChild(def.Main)
	if main and main:IsA("BasePart") then
		return main
	end
	if inst:IsA("Model") and inst.PrimaryPart then
		return inst.PrimaryPart
	end
	return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function register(inst, def)
	if CollectionService:HasTag(inst, K.Tag) then
		return false
	end
	local main = mainPart(inst, def)
	if not main then
		return false
	end
	if inst:IsA("BasePart") then
		inst.CollisionGroup = K.Group
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = K.Group
		end
	end
	if inst:IsA("Model") then
		if inst.PrimaryPart ~= main then
			inst.PrimaryPart = main
		end
		-- The whole prop reaches a device at once, so PropClient never sees half a bench.
		pcall(function()
			inst.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		end)
	end
	inst:SetAttribute("Kind", def.Kind)
	-- The tag goes on last: by the time a device hears of the prop, everything above is in place.
	CollectionService:AddTag(inst, K.Tag)
	return true
end

-- A beach bench stands on a block that is not part of its Model (a sibling Part, K.BaseName). Left
-- there it would stay behind as a wall when the bench is knocked away, and stop the car that did it.
-- Each block moves into the bench it carries (same parent, seat right above it), so it is part of the
-- prop: same collision group, hidden and thrown with the rest. found = { { inst, def }, ... }.
local function adoptBases(found, bases)
	if #bases == 0 then
		return
	end
	local benches = {} -- [parent] = { bench Models in it }
	for _, pair in ipairs(found) do
		local inst = pair[1]
		if pair[2].Kind == "Bench" and inst:IsA("Model") and inst.Parent then
			local list = benches[inst.Parent]
			if not list then
				list = {}
				benches[inst.Parent] = list
			end
			table.insert(list, inst)
		end
	end
	for _, base in ipairs(bases) do
		local best, bestGap = nil, K.BaseReach
		for _, bench in ipairs(benches[base.Parent] or {}) do
			local seat = bench:FindFirstChild("Seat")
			if seat and seat:IsA("BasePart") then
				local d = seat.Position - base.Position
				local gap = Vector3.new(d.X, 0, d.Z).Magnitude
				if gap < bestGap then
					best, bestGap = bench, gap
				end
			end
		end
		if best then
			base.Parent = best
		end
	end
end

local function scan(root)
	local found, bases = {}, {}
	for _, inst in ipairs(root:GetDescendants()) do
		local def = KINDS[inst.Name]
		if def and inst:IsA(def.Class) and inst:GetAttribute("Unbreakable") ~= true then
			table.insert(found, { inst, def })
		elseif inst.Name == K.BaseName and inst:IsA("BasePart") and inst:GetAttribute("Unbreakable") ~= true then
			table.insert(bases, inst)
		end
	end
	-- Before anything is registered: a block has to be inside its bench when the bench's parts are
	-- put in the collision group.
	local okBases, err = pcall(adoptBases, found, bases)
	if not okBases then
		warn("[PropService] bench blocks: " .. tostring(err))
	end
	local count = 0
	for _, pair in ipairs(found) do
		-- One odd prop must never cost the rest of the city theirs.
		local ok, added = pcall(register, pair[1], pair[2])
		if ok and added then
			count += 1
		end
	end
	return count
end

function PropService.Register(inst, kind)
	if typeof(inst) ~= "Instance" or not (inst:IsA("Model") or inst:IsA("BasePart")) then
		return false
	end
	local def = KINDS[inst.Name]
	if kind ~= nil then
		def = nil
		for _, d in pairs(KINDS) do
			if d.Kind == kind then
				def = { Kind = d.Kind, Main = d.Main } -- (any class: a one-part hydrant is fine too)
				break
			end
		end
	end
	if not def then
		return false
	end
	local ok, added = pcall(register, inst, def)
	return ok and added == true
end

function PropService.IsDown(prop)
	if typeof(prop) ~= "Instance" then
		return false
	end
	local downUntil = prop:GetAttribute("BrokenUntil")
	return type(downUntil) == "number" and downUntil > Workspace:GetServerTimeNow()
end

-- Knock a standing prop over for everyone. velocity = the velocity of whatever hit it (only the flat
-- part counts; it says which way the pieces fly). Returns true if it went down.
function PropService.Break(prop, velocity)
	if typeof(prop) ~= "Instance" or not CollectionService:HasTag(prop, K.Tag) or not prop:IsDescendantOf(Workspace) then
		return false
	end
	if PropService.IsDown(prop) then
		return false
	end
	local v = typeof(velocity) == "Vector3" and Vector3.new(velocity.X, 0, velocity.Z) or Vector3.zero
	local speed = v.Magnitude
	if speed ~= speed or speed == math.huge then -- NaN or endless: no direction to speak of
		v = Vector3.zero
	elseif speed > K.MaxClaim then
		v = v.Unit * K.MaxClaim
	end
	local now = Workspace:GetServerTimeNow()
	local downUntil = now + K.DownTime
	local spoutUntil = nil
	if prop:GetAttribute("Kind") == "Hydrant" then
		spoutUntil = now + K.SpoutTime
		prop:SetAttribute("SpoutUntil", spoutUntil)
	end
	prop:SetAttribute("HitVel", v)
	prop:SetAttribute("BrokenUntil", downUntil) -- last: whoever reads it finds the other two already set
	if hitRemote then
		hitRemote:FireAllClients(prop, downUntil, v, spoutUntil)
	end
	return true
end

-- The car this player is driving right now (driver's seat), or nil. The same test as ImpactService.
local function drivenCar(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.Health > 0 and hum.SeatPart
	if not seat or seat.Name ~= "DriverSeat" then
		return nil
	end
	local car = seat.Parent
	local folder = Workspace:FindFirstChild("Vehicles")
	if not car or not folder or car.Parent ~= folder or car:GetAttribute("DriverUserId") ~= player.UserId then
		return nil
	end
	return car, car.PrimaryPart
end

local function reportSmash(player)
	if ProgressService == nil then
		local module = script.Parent:FindFirstChild("ProgressService")
		local ok, mod = false, nil
		if module then
			ok, mod = pcall(require, module)
		end
		ProgressService = ok and type(mod) == "table" and mod or false
	end
	if ProgressService and type(ProgressService.Event) == "function" then
		local ok, err = pcall(ProgressService.Event, player, "PropSmash", 1)
		if not ok then
			warn("[PropService] PropSmash: " .. tostring(err))
		end
	end
end

local function onHit(player, prop, velocity)
	if typeof(prop) ~= "Instance" or typeof(velocity) ~= "Vector3" then
		return
	end
	if not RateLimit.Allow(player, "PropHit", K.PerSecond, K.Burst) then
		return
	end
	if not CollectionService:HasTag(prop, K.Tag) or not prop:IsDescendantOf(Workspace) or PropService.IsDown(prop) then
		return
	end
	local claimed = Vector3.new(velocity.X, 0, velocity.Z)
	local claim = claimed.Magnitude
	if claim ~= claim or claim < K.MinClaim or claim > K.MaxClaim then -- (claim ~= claim: NaN)
		return
	end
	local _, chassis = drivenCar(player)
	if not chassis then
		return
	end
	local main = prop:IsA("BasePart") and prop or (prop:IsA("Model") and prop.PrimaryPart)
	if not main then
		return
	end
	-- The car has to be moving and close, as far as the server can tell.
	local seenVel = chassis.AssemblyLinearVelocity
	local seen = Vector3.new(seenVel.X, 0, seenVel.Z).Magnitude
	if seen < K.MinSeen then
		return
	end
	local gap = chassis.Position - main.Position
	if math.abs(gap.Y) > K.HeightGap
		or Vector3.new(gap.X, 0, gap.Z).Magnitude > K.Reach + math.min(seen * K.LagReach, K.LagMax) then
		return
	end
	-- Thrown no harder than the car the server sees could throw it.
	local speed = math.min(claim, seen * 1.6 + 15)
	if PropService.Break(prop, claimed.Unit * speed) then
		reportSmash(player)
	end
end

function PropService.Init()
	ensureGroups()
	hitRemote = Remotes.Event("PropHit")
	hitRemote.OnServerEvent:Connect(onHit)
	-- The city is part of the place, so this runs straight through (it only waits if the map is late).
	task.spawn(function()
		local city = Workspace:WaitForChild("City", 30)
		local art = city and city:WaitForChild("Art", 30)
		if not art then
			warn("[PropService] no Workspace.City.Art: nothing to knock over")
			return
		end
		local t0 = os.clock()
		local count = scan(art)
		print(string.format("[PropService] %d breakable props (%.0f ms)", count, (os.clock() - t0) * 1000))
	end)
end

return PropService
