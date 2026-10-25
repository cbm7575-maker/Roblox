-- VehicleService (ModuleScript, ServerScriptService.Services.VehicleService)
-- Spawns and despawns cars, seats drivers and passengers, and hands each car's physics to its driver's
-- device. One car per player, from the cars they own (GarageService; starters are free for everyone).
-- In Studio tests any car can be spawned.
--   * New characters find their last (or starter) car on the nearest free pad for their role.
--   * RequestSpawnCar (CAR button / phone Garage): not while Wanted, rate-limited, cooldown (3 s in Studio).
--     A boat launched within 60 studs of its pad puts you straight on it.
--   * Spawned cars wear their owner's paint, rims and underglow (GarageService.ApplyCustom).
--   * Cars in water for 2 s, out of the world, or idle 10 minutes (every seat empty) are removed.
--     Whoever sits in a car that goes away (or whose owner leaves) is put out beside it first.
--   * Player attribute LastCar = the last land car spawned (the HUD CAR button sends it back);
--     LastBoat = the last boat.
--   * Only the owner drives. Crewmates and the owner's Roblox friends ride (one Ride prompt, the free
--     passenger seat nearest them): same side only, never prisoners, not through walls, not while tased.
--   * Nobody gets in while tased (StunnedUntil). Getting out picks a free spot beside the door, then
--     the other side, the front, the back, and finally the roof, never through a wall.
--   * Getting out (RequestExitCar, F / EXIT, drivers and passengers alike) finds your seat even if the
--     server's Humanoid.SeatPart has lost it, removes every joint holding you to it, and answers with
--     ExitedCar (spot CFrame or nil) so your device lets go too.
--   * A cop's siren switches off when the driver gets out.
--   * Boats float past the end of the docks: their Drive / Ride prompts reach CarBuilder.BoatReach.
--
--   VehicleService.Spawn(player, id, opts) -> car | nil, reason ("unknown car" | "cooldown" | "no room")
--     opts.At = CFrame: spawn exactly there (the chassis centre, i.e. the car's pivot, nose along the
--       CFrame's LookVector; about 3.2 studs above the floor for land cars, like the pads). The space
--       check still runs (other cars, characters, City buildings) with a tight box: car size +0.6 wide,
--       +1 long. Works for boats too (no "boat delivered" GPS then).
--     opts.Sit = true: seat the player once it's there. opts.IgnoreCooldown = true: no spawn cooldown
--       (and it doesn't use one up). opts.PadSide = role: the nearest free pad for that role.
--   VehicleService.Despawn(userId), GetCar(player), CanDrive(side, id)
--   VehicleService.PassengerSeats(car) -> { Seat } (front passenger first)
--   VehicleService.SeatNPC(car, model) -> seat | nil: a non-player rider (taxi fares) sits visibly in the
--     first free passenger seat: its Humanoid makes way for an AnimationController (no physics, no
--     name tag), parts massless and non-colliding, welded to the seat, sitting pose; the seat gets
--     attribute NPCRider = true. ReleaseNPC(model, seat) unwelds it (the caller moves or removes it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Teams = require(ReplicatedStorage.Shared.Config.Teams)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local CarBuilder = require(ServerStorage.Tools.CarBuilder)

local VehicleService = {}

local SPAWN_COOLDOWN = RunService:IsStudio() and 3 or 30
local REQUEST_GAP = 1 -- minimum seconds between spawn requests of any kind (spam guard)
local IDLE_DESPAWN = 600
local BOAT_AUTO_BOARD = 60 -- a boat launched this close to you seats you on it

local carsByUser = {} -- [userId] = model
local lastSpawn = {} -- [userId] = os.clock() of the last successful spawn
local lastRequest = {} -- [userId] = os.clock() of the last request
local idleSince = setmetatable({}, { __mode = "k" }) -- [model] = os.clock() it became empty
local sunkFor = setmetatable({}, { __mode = "k" }) -- [model] = seconds in water

local npcRider = setmetatable({}, { __mode = "k" }) -- [seat] = the taxi fare sitting there
local notify, exitedEvent

-- Tased (ArrestService sets StunnedUntil in server time): no getting into cars.
local function stunned(player)
	return (player:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow()
end

-- Close enough to the seat to really be at the car (prompt triggers are client claims). Boats float off
-- the dock ends, so their prompts (and this check) reach further.
local SEAT_REACH = 20
local BOAT_REACH = CarBuilder.BoatReach + 6
local function reachOf(car)
	return car:GetAttribute("Boat") and BOAT_REACH or SEAT_REACH
end
local function nearSeat(character, seat, reach)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (root.Position - seat.Position).Magnitude <= reach
end

local function template(id)
	local t = ServerStorage.VehicleTemplates:FindFirstChild(id)
	if t then
		return t:Clone()
	end
	return CarBuilder.Build(id)
end

-- Every seat a passenger can use, front passenger first (CarBuilder marks them Passenger = true).
function VehicleService.PassengerSeats(car)
	local list = {}
	for _, d in ipairs(car:GetChildren()) do
		if d:IsA("Seat") and (d:GetAttribute("Passenger") or d.Name == "PassengerSeat") then
			table.insert(list, d)
		end
	end
	table.sort(list, function(a, b)
		return (a.Name == "PassengerSeat" and 0 or 1) < (b.Name == "PassengerSeat" and 0 or 1)
			or ((a.Name == "PassengerSeat") == (b.Name == "PassengerSeat") and a.Name < b.Name)
	end)
	return list
end

-- A rider who died in the seat (or whose character is gone) doesn't count as sitting there.
local function stale(seat)
	local occ = seat.Occupant
	return occ ~= nil and (occ.Health <= 0 or not occ:IsDescendantOf(Workspace))
end

local function seatFree(seat)
	return (seat.Occupant == nil or stale(seat)) and not seat:GetAttribute("NPCRider")
end

-- Is anyone (player or taxi fare) in any seat of this car?
local function occupied(car)
	for _, d in ipairs(car:GetChildren()) do
		if (d:IsA("Seat") or d:IsA("VehicleSeat")) and not seatFree(d) then
			return true
		end
	end
	return false
end

-- Is there room for a car of `size` at `cf`? Checks other cars, characters, buildings and houses.
local clearParams = OverlapParams.new()
clearParams.FilterType = Enum.RaycastFilterType.Include
local function isClear(cf, size, margin)
	local list = { Workspace.Vehicles }
	local city = Workspace:FindFirstChild("City")
	for _, name in ipairs({ "Buildings", "Art", "Landmarks" }) do
		if city and city:FindFirstChild(name) then
			table.insert(list, city[name])
		end
	end
	local houses = Workspace:FindFirstChild("Properties")
	if houses then
		table.insert(list, houses) -- never spawn a car inside someone's house
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	clearParams.FilterDescendantsInstances = list
	local box = size + (margin or Vector3.new(2, 4, 3))
	-- Flat things under the wheels (boardwalk planks, kerbs, road paint) don't block a spawn.
	local bottom = cf.Y - size.Y / 2
	for _, p in ipairs(Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 1.5, 0), box, clearParams)) do
		local top = p.Position.Y + p.Size.Y / 2
		if top > bottom + 0.8 or p.Size.Y > 3 then
			return false
		end
	end
	return true
end

-- Ground in front of the player: only roads or open ground, never roofs or people, near foot level.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
local function spawnCFrame(player, size)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local city = Workspace:FindFirstChild("City")
	if not root or not city then
		return nil
	end
	groundParams.FilterDescendantsInstances = { city:FindFirstChild("Roads"), city:FindFirstChild("Ground") }
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	for _, dist in ipairs({ 14, 20, 10 }) do
		local probe = root.Position + look * dist
		local hit = Workspace:Raycast(probe + Vector3.new(0, 20, 0), Vector3.new(0, -40, 0), groundParams)
		if hit and hit.Normal.Y > 0.8 and math.abs(hit.Position.Y - (root.Position.Y - 3)) < 8 then
			local pos = hit.Position + Vector3.new(0, 3.2, 0)
			local cf = CFrame.lookAt(pos, pos + look)
			if isClear(cf, size) then
				return cf
			end
		end
	end
	return nil
end

-- The nearest free car pad (or boat pad on the water, for boats) for this role.
local function padCFrame(side, size, near, boat)
	local pads = {}
	for _, p in ipairs(Workspace.Spawns:GetChildren()) do
		if p.Name == (boat and "BoatPad" or "CarPad") and p:GetAttribute("Side") == side then
			table.insert(pads, p)
		end
	end
	table.sort(pads, function(a, b)
		return (a.Position - near).Magnitude < (b.Position - near).Magnitude
	end)
	for _, pad in ipairs(pads) do
		local yaw = math.rad(pad:GetAttribute("FacingYaw") or 0)
		local cf = CFrame.new(pad.Position + Vector3.new(0, boat and 2.5 or 3.2, 0)) * CFrame.Angles(0, yaw, 0)
		if isClear(cf, size) then
			return cf
		end
	end
	return nil
end

------------------------------------------------------------------ getting out

-- Where to stand after getting out: beside your door, else the other side, the front, the back
-- (each must be reachable from the seat without crossing a wall, with room to stand and ground or
-- water below), else on the roof. Returns a CFrame for the HumanoidRootPart, facing the car's way.
local exitRay = RaycastParams.new()
exitRay.FilterType = Enum.RaycastFilterType.Exclude
exitRay.RespectCanCollide = true
exitRay.IgnoreWater = true
local groundRay = RaycastParams.new()
groundRay.FilterType = Enum.RaycastFilterType.Exclude
groundRay.RespectCanCollide = true
local roomParams = OverlapParams.new()
roomParams.FilterType = Enum.RaycastFilterType.Exclude
roomParams.RespectCanCollide = true
local ROOT_HEIGHT = 3.1 -- HumanoidRootPart centre above the feet
local BODY_CHECKS = { -1.6, 0.2, 1.9 } -- knees, waist, head (relative to the root)

-- Would a standing body at `root` be inside something solid? (Checked against each part's own box,
-- so rotated buildings near the spot don't block it. Terrain is skipped: water is fine to stand in.)
local function noRoom(root)
	for _, p in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(root + Vector3.new(0, 0.2, 0)), Vector3.new(2, 4.2, 2), roomParams)) do
		if p:IsA("Terrain") then
			continue
		end
		local half = p.Size / 2 + Vector3.new(1, 1, 1)
		for _, dy in ipairs(BODY_CHECKS) do
			local rel = p.CFrame:PointToObjectSpace(root + Vector3.new(0, dy, 0))
			if math.abs(rel.X) < half.X and math.abs(rel.Y) < half.Y and math.abs(rel.Z) < half.Z then
				return true
			end
		end
	end
	return false
end

local function exitSpot(car, seat, character)
	local chassis = car.PrimaryPart
	local ignore = { car, character }
	local smoke = Workspace:FindFirstChild("Smoke")
	if smoke then
		table.insert(ignore, smoke)
	end
	local npcs = Workspace:FindFirstChild("NPCs")
	if npcs then
		table.insert(ignore, npcs) -- taxi fares riding along
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character) -- people move; never let them block the door
		end
	end
	exitRay.FilterDescendantsInstances = ignore
	groundRay.FilterDescendantsInstances = ignore
	roomParams.FilterDescendantsInstances = ignore
	local look = chassis.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local frame = CFrame.lookAt(chassis.Position, chassis.Position + look) -- yaw only
	local half = chassis.Size / 2
	local seatLocal = frame:PointToObjectSpace(seat.Position)
	local side = seatLocal.X > 0.1 and 1 or -1 -- your own door: driver and left seats left, the rest right
	local from = seat.Position + Vector3.new(0, 1.5, 0)
	local y = from.Y - chassis.Position.Y
	local tries = {
		Vector3.new(side * (half.X + 2.4), y, seatLocal.Z),
		Vector3.new(-side * (half.X + 2.4), y, seatLocal.Z),
		Vector3.new(0, y, -(half.Z + 2.6)),
		Vector3.new(0, y, half.Z + 2.6),
	}
	local low = Vector3.new(0, -1.2, 0) -- a second sight line at seat height, for low walls and fences
	local fallback
	for _, offset in ipairs(tries) do
		local spot = frame * offset
		if not Workspace:Raycast(from, spot - from, exitRay) and not Workspace:Raycast(from + low, spot - from, exitRay) then
			-- Stand on whatever is below (kerb, road, slope); water counts (you'll swim).
			local ground = Workspace:Raycast(spot + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), groundRay)
			local root = ground and ground.Position + Vector3.new(0, ROOT_HEIGHT, 0) or spot
			if not noRoom(root) then
				if ground then
					return CFrame.lookAt(root, root + look)
				end
				fallback = fallback or root -- a drop below (a bridge edge): only if nothing better
			end
		end
	end
	if fallback then
		return CFrame.lookAt(fallback, fallback + look)
	end
	-- Boxed in: climb out onto the roof.
	local _, size = car:GetBoundingBox()
	local roof = chassis.Position + Vector3.new(0, math.max(size.Y / 2, half.Y + 2) + ROOT_HEIGHT, 0)
	return CFrame.lookAt(roof, roof + look)
end

-- The seat this character is in. Humanoid.SeatPart first; if the server has lost track of it (the
-- weld is there but SeatPart isn't), the seat weld on the root says.
local function seatOf(character, hum)
	local seat = hum.SeatPart
	if seat then
		return seat
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	for _, j in ipairs(root:GetJoints()) do
		if j:IsA("JointInstance") and j.Name == "SeatWeld" then
			local other = j.Part0 == root and j.Part1 or j.Part0
			if other and (other:IsA("Seat") or other:IsA("VehicleSeat")) then
				if RunService:IsStudio() then
					warn("[VehicleService] exit: Humanoid.SeatPart was nil on the server; found the SeatWeld on " .. other:GetFullName())
				end
				return other
			end
		end
	end
	return nil
end

-- Remove every joint that holds this character to the seat, and any dead SeatWeld left behind by an
-- earlier rider (its part gone from the world). The seat's own weld to the chassis stays.
local function unweld(seat, character)
	for _, j in ipairs(seat:GetChildren()) do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			local a, b = j.Part0, j.Part1
			local mine = (a ~= nil and a:IsDescendantOf(character)) or (b ~= nil and b:IsDescendantOf(character))
			local dead = j.Name == "SeatWeld" and (b == nil or not b:IsDescendantOf(Workspace))
			if dead and not mine and RunService:IsStudio() then
				warn("[VehicleService] exit: removed a leftover SeatWeld from " .. seat:GetFullName())
			end
			if mine or dead then
				j:Destroy()
			end
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		for _, j in ipairs(root:GetJoints()) do
			if j:IsA("JointInstance") and j.Name == "SeatWeld" then
				j:Destroy()
			end
		end
	end
end

-- Drop the welds of a rider who is gone (see stale) before someone new sits down.
local function clearSeat(seat)
	for _, j in ipairs(seat:GetChildren()) do
		if j:IsA("JointInstance") and j.Name == "SeatWeld" then
			local b = j.Part1
			local occ = b and b.Parent and b.Parent:FindFirstChildOfClass("Humanoid")
			if not b or not b:IsDescendantOf(Workspace) or (occ and occ.Health <= 0) then
				j:Destroy()
			end
		end
	end
end

-- Put a player out of their seat, beside the car, and tell their device. Safe to call for any seat.
local function exitPlayer(player, hum, seat)
	local character = player.Character
	if not character then
		return
	end
	local car = seat.Parent
	local spot
	if car and car:IsA("Model") and car.PrimaryPart then
		local ok, res = pcall(exitSpot, car, seat, character)
		spot = ok and res or nil
		if not ok then
			warn("[VehicleService] exit spot: " .. tostring(res))
		end
	end
	unweld(seat, character)
	hum.Sit = false
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		spot = spot or seat.CFrame * CFrame.new(seat.Name == "DriverSeat" and -4.5 or 4.5, 1.5, 0)
		root.CFrame = spot
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	if exitedEvent then
		exitedEvent:FireClient(player, spot)
	end
end

-- Everyone out (before a car goes away), each beside the car like a normal exit.
local function ejectAll(car)
	for _, seat in ipairs(car:GetChildren()) do
		if seat:IsA("Seat") or seat:IsA("VehicleSeat") then
			local hum = seat.Occupant
			local p = hum and Players:GetPlayerFromCharacter(hum.Parent)
			if p and hum then
				local ok, err = pcall(exitPlayer, p, hum, seat)
				if not ok then
					warn("[VehicleService] eject: " .. tostring(err))
				end
			end
		end
	end
end

------------------------------------------------------------------ non-player riders (taxi fares)

function VehicleService.SeatNPC(car, model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not car.Parent then
		return nil
	end
	local seat
	for _, s in ipairs(VehicleService.PassengerSeats(car)) do
		if seatFree(s) then
			seat = s
			break
		end
	end
	if not seat then
		return nil
	end
	-- A posed statue, not a physics humanoid (a humanoid welded into a car pushes it around).
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hip = hum and hum.HipHeight or 2
	if hum then
		hum:Destroy()
	end
	if not model:FindFirstChildOfClass("AnimationController") then
		Instance.new("AnimationController").Parent = model
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end
	-- Hips on the seat like a seated player (the same lift PedClient uses for bench sitters).
	model:PivotTo(seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + 1.45 * hip / 2, 0))
	local w = Instance.new("WeldConstraint")
	w.Name = "RiderWeld"
	w.Part0 = seat
	w.Part1 = root
	w.Parent = root
	seat:SetAttribute("NPCRider", true)
	npcRider[seat] = model
	model.Destroying:Once(function()
		-- However the rider goes, the seat is free again.
		if npcRider[seat] == model then
			npcRider[seat] = nil
			seat:SetAttribute("NPCRider", nil)
		end
	end)
	CarBuilder.PlayPose(model, "sit")
	return seat
end

function VehicleService.ReleaseNPC(model, seat)
	local root = model:FindFirstChild("HumanoidRootPart")
	local w = root and root:FindFirstChild("RiderWeld")
	if w then
		w:Destroy()
	end
	if seat and npcRider[seat] == model then
		npcRider[seat] = nil
		seat:SetAttribute("NPCRider", nil)
	end
end

------------------------------------------------------------------ cars

function VehicleService.Despawn(userId)
	local car = carsByUser[userId]
	carsByUser[userId] = nil
	if car then
		idleSince[car] = nil
		sunkFor[car] = nil
		ejectAll(car)
		car:Destroy()
	end
end

function VehicleService.GetCar(player)
	return carsByUser[player.UserId]
end

-- Can this role drive this car? Cops drive police vehicles, civilians everything else.
function VehicleService.CanDrive(side, id)
	local def = Vehicles.ById[id]
	if not def or side == "Prisoner" then
		return false
	end
	return (def.Police == true) == (side == "Cop")
end

local function onOccupantChanged(car, seat)
	local humanoid = seat.Occupant
	local chassis = car.PrimaryPart
	if humanoid then
		local player = Players:GetPlayerFromCharacter(humanoid.Parent)
		if not player or car:GetAttribute("OwnerUserId") ~= player.UserId then
			-- Only the owner drives (friends and crew ride in the passenger seats).
			local sw = seat:FindFirstChild("SeatWeld")
			if sw then
				sw:Destroy()
			end
			return
		end
		idleSince[car] = nil
		car:SetAttribute("DriverUserId", player.UserId)
		chassis:SetNetworkOwner(player)
	else
		car:SetAttribute("DriverUserId", nil)
		car:SetAttribute("Siren", nil) -- a parked cop car doesn't keep wailing
		idleSince[car] = not occupied(car) and os.clock() or nil
		task.delay(1.5, function()
			if car.Parent and seat.Occupant == nil and chassis:IsDescendantOf(Workspace) then
				chassis:SetNetworkOwner(nil)
			end
		end)
	end
end

-- Ride along: crewmates and the owner's Roblox friends, same side, never prisoners, never through walls.
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.IgnoreWater = true
losParams.RespectCanCollide = true
local function canRideNow(who, car)
	local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
	local owner = Players:GetPlayerByUserId(car:GetAttribute("OwnerUserId") or 0)
	if not car.Parent or not hum or hum.Health <= 0 or hum.SeatPart or not owner or who == owner or stunned(who) then
		return nil
	end
	-- Same side only, and never out of prison (the vent is the only way out).
	local side = who:GetAttribute("Side")
	if side == "Prisoner" or side ~= owner:GetAttribute("Side") then
		return nil
	end
	return hum, owner
end

local function onRide(who, car)
	if not RateLimit.Allow(who, "Ride", 2, 2) then
		return
	end
	local hum, owner = canRideNow(who, car)
	if not hum or not owner then
		return
	end
	-- Crew, or a Roblox friend of the owner (cached; a first lookup can take a moment).
	if not require(script.Parent.CrewService).MayRide(who, owner) then
		return
	end
	hum, owner = canRideNow(who, car) -- again: the lookup may have yielded
	local root = who.Character and who.Character:FindFirstChild("HumanoidRootPart")
	if not hum or not owner or not root then
		return
	end
	-- The free passenger seat nearest the rider, within reach.
	local best, bestD
	for _, s in ipairs(VehicleService.PassengerSeats(car)) do
		local d = (root.Position - s.Position).Magnitude
		if seatFree(s) and d < reachOf(car) and (not bestD or d < bestD) then
			best, bestD = s, d
		end
	end
	if not best then
		return
	end
	clearSeat(best)
	-- No riding through walls or fences (people, smoke and taxi fares never block the door).
	local ignore = { car }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	for _, name in ipairs({ "Smoke", "NPCs" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	losParams.FilterDescendantsInstances = ignore
	if Workspace:Raycast(root.Position, best.Position - root.Position, losParams) then
		return
	end
	best:Sit(hum)
end

function VehicleService.Spawn(player, id, opts)
	opts = opts or {}
	local def = Vehicles.Resolve(id)
	if not def then
		return nil, "unknown car"
	end
	local now = os.clock()
	if not opts.IgnoreCooldown and lastSpawn[player.UserId] and now - lastSpawn[player.UserId] < SPAWN_COOLDOWN then
		return nil, "cooldown"
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local cf
	if typeof(opts.At) == "CFrame" then
		-- An exact spot (a house garage): still never on top of another car or a person.
		cf = isClear(opts.At, def.Size, Vector3.new(0.6, 3, 1)) and opts.At or nil
	elseif def.Boat then
		-- Boats launch from the nearest marina boat pad for your side, however far away it is.
		local side = player:GetAttribute("Side") == "Cop" and "Cop" or "Civilian"
		cf = root and padCFrame(side, def.Size, root.Position, true)
	elseif opts.PadSide and root then
		cf = padCFrame(opts.PadSide, def.Size, root.Position)
	end
	if not cf and opts.At == nil and not def.Boat then
		cf = spawnCFrame(player, def.Size)
	end
	if not cf then
		return nil, "no room"
	end
	if not opts.IgnoreCooldown then
		lastSpawn[player.UserId] = now -- the free starter car on a pad doesn't use up the cooldown
	end
	VehicleService.Despawn(player.UserId)

	local car = template(id)
	car:SetAttribute("OwnerUserId", player.UserId)
	car:SetAttribute("Health", 100) -- a fresh car is a repaired car (templates may lack it)
	car:SetAttribute("StallUntil", nil)
	local okCustom, err = pcall(function()
		require(script.Parent.GarageService).ApplyCustom(car, player)
	end)
	if not okCustom then
		warn("[VehicleService] custom paint failed: " .. tostring(err))
	end
	car:PivotTo(cf)
	car.Parent = Workspace.Vehicles
	carsByUser[player.UserId] = car
	idleSince[car] = now
	car.PrimaryPart:SetNetworkOwner(nil)
	-- The HUD's CAR button respawns LastCar, so it only ever holds land cars.
	player:SetAttribute(def.Boat and "LastBoat" or "LastCar", id)

	local seat = car:FindFirstChild("DriverSeat")
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onOccupantChanged(car, seat)
	end)
	local reach = reachOf(car)
	local prompt = seat:FindFirstChild("DrivePrompt")
	if prompt then
		prompt.Triggered:Connect(function(who)
			local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and not hum.SeatPart and seatFree(seat)
				and car:GetAttribute("OwnerUserId") == who.UserId and not stunned(who) and nearSeat(who.Character, seat, reach) then
				clearSeat(seat) -- never sit on top of a dead rider's leftover weld
				seat:Sit(hum)
			end
		end)
	end
	-- Passengers: one Ride prompt (on the front passenger seat) for every passenger seat.
	for _, s in ipairs(VehicleService.PassengerSeats(car)) do
		s:GetPropertyChangedSignal("Occupant"):Connect(function()
			if s.Occupant then
				idleSince[car] = nil
			elseif not occupied(car) then
				idleSince[car] = idleSince[car] or os.clock()
			end
		end)
	end
	local ride = car:FindFirstChild("RidePrompt", true)
	if ride and ride:IsA("ProximityPrompt") then
		ride.Triggered:Connect(function(who)
			onRide(who, car)
		end)
	end
	-- A boat waiting at a far-off marina: no teleport; the client routes the GPS to it.
	if def.Boat and opts.At == nil and root and (cf.Position - root.Position).Magnitude > BOAT_AUTO_BOARD then
		Remotes.Event("BoatDelivered"):FireClient(player, { Pos = cf.Position, Name = def.DisplayName })
	elseif opts.Sit and not stunned(player) then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			task.defer(function()
				if car.Parent and hum.Parent and hum.Health > 0 and not hum.SeatPart and seat.Occupant == nil then
					seat:Sit(hum)
				end
			end)
		end
	end
	return car
end

function VehicleService.Init()
	CarBuilder.EnsureGroups()
	notify = Remotes.Event("Notify")
	exitedEvent = Remotes.Event("ExitedCar")
	Remotes.Event("BoatDelivered")
	local requestSpawn = Remotes.Event("RequestSpawnCar")
	local requestExit = Remotes.Event("RequestExitCar")

	-- H key: cops toggle their siren, everyone else honks (clients play the sound from the attribute).
	local lastHorn = {}
	Remotes.Event("RequestHorn").OnServerEvent:Connect(function(player)
		local now = os.clock()
		if lastHorn[player] and now - lastHorn[player] < 0.6 then
			return
		end
		lastHorn[player] = now
		local car = carsByUser[player.UserId]
		if not car or car:GetAttribute("DriverUserId") ~= player.UserId then
			return
		end
		if car:GetAttribute("Police") and player:GetAttribute("Side") == "Cop" then
			car:SetAttribute("Siren", not car:GetAttribute("Siren"))
		else
			car:SetAttribute("HonkAt", now)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastHorn[player] = nil
	end)

	requestSpawn.OnServerEvent:Connect(function(player, id)
		local now = os.clock()
		if lastRequest[player.UserId] and now - lastRequest[player.UserId] < REQUEST_GAP then
			return
		end
		lastRequest[player.UserId] = now
		if typeof(id) ~= "string" or not Vehicles.ById[id] then
			return
		end
		local side = player:GetAttribute("Side") or "Civilian"
		if not VehicleService.CanDrive(side, id) then
			return
		end
		-- Only cars you own (every car in Studio tests).
		if not RunService:IsStudio() and not require(script.Parent.GarageService).Owns(player, id) then
			notify:FireClient(player, "CarNotOwned")
			return
		end
		-- Wanted players may swap cars only while the cops can't see them (a GTA-style shake-off).
		if (player:GetAttribute("Heat") or 0) > 0 and player:GetAttribute("HeatSpotted") then
			notify:FireClient(player, "NoCarWhileWanted")
			return
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or hum.SeatPart then
			return
		end
		-- Boats launched from close by board you straight away (they float off the dock ends).
		local car, why = VehicleService.Spawn(player, id, { Sit = RunService:IsStudio() or Vehicles.ById[id].Boat == true })
		if not car then
			notify:FireClient(player, why == "cooldown" and "CarCooldown" or "CarNoRoom")
		end
	end)

	-- F / EXIT (drivers and passengers). Never ignored for a lost SeatPart: the seat weld is found
	-- either way, and the device always gets an answer (ExitedCar) so it can let go too.
	requestExit.OnServerEvent:Connect(function(player)
		if not RateLimit.Allow(player, "ExitCar", 4, 3) then
			return
		end
		local character = player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if not hum then
			return
		end
		local seat = seatOf(character, hum)
		if seat then
			exitPlayer(player, hum, seat)
		else
			if RunService:IsStudio() then
				warn("[VehicleService] exit request from " .. player.Name .. ": the server sees no seat; the device lets go itself")
			end
			exitedEvent:FireClient(player, nil) -- the server holds no seat for you: your device lets go
		end
	end)

	-- Every new character finds its starter car on the nearest free pad (if they don't have one).
	local function onCharacter(player)
		task.wait(0.5)
		if player.Parent ~= Players or carsByUser[player.UserId] then
			return
		end
		local side = player:GetAttribute("Side") or "Civilian"
		local team = Teams.BySide[side]
		if not team or not team.Starter then
			return
		end
		local last = player:GetAttribute("LastCar")
		local id = team.Starter
		local lastDef = last and Vehicles.ById[last]
		if lastDef and not lastDef.Boat and VehicleService.CanDrive(side, last)
			and require(script.Parent.GarageService).Owns(player, last) then
			id = last
		end
		VehicleService.Spawn(player, id, { PadSide = side, IgnoreCooldown = true })
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
		if player.Character then
			task.spawn(onCharacter, player)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end

	Players.PlayerRemoving:Connect(function(player)
		VehicleService.Despawn(player.UserId) -- passengers are put out first
		lastSpawn[player.UserId] = nil
		lastRequest[player.UserId] = nil
	end)

	-- Housekeeping every second: cars in water, out of the world, or unused.
	local function housekeeping()
		local now = os.clock()
		for userId, car in pairs(carsByUser) do
			local chassis = car.PrimaryPart
			local owner = Players:GetPlayerByUserId(userId)
			if not chassis or not chassis:IsDescendantOf(Workspace) or chassis.Position.Y < -60 then
				VehicleService.Despawn(userId)
			elseif chassis.Position.Y < 0.2 and not car:GetAttribute("Boat") then
				-- On land the chassis centre never drops below +1.6, so this means water (cars float
				-- at about -2 in sea water). Two seconds in the water and the car is gone.
				sunkFor[car] = (sunkFor[car] or 0) + 1
				if sunkFor[car] >= 2 then
					VehicleService.Despawn(userId)
					if owner then
						notify:FireClient(owner, "CarSank")
					end
				end
			else
				sunkFor[car] = nil
				-- Idle = nobody in any seat (a passenger or a taxi fare keeps the car alive too).
				if occupied(car) then
					idleSince[car] = nil
				elseif not idleSince[car] then
					idleSince[car] = now
				end
				local since = idleSince[car]
				if since and now - since > IDLE_DESPAWN then
					VehicleService.Despawn(userId)
				end
			end
		end
	end
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, e = pcall(housekeeping)
			if not ok then
				warn("[VehicleService] housekeeping: " .. tostring(e))
			end
		end
	end)
end

return VehicleService
