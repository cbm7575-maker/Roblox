-- VehicleService (ModuleScript, ServerScriptService.Services.VehicleService)
-- Spawns and despawns cars, seats drivers, and hands each car's physics to its driver's device.
-- One car per player, from the cars they own (GarageService; starters are free for everyone).
-- In Studio tests any car can be spawned.
--   * New characters find their last (or starter) car on the nearest free pad for their role, or, for
--     free-roam home owners, on their home's driveway (HousingService.DrivewayFor). On join this waits
--     up to VehicleService.JoinWait seconds for the save to load so the car goes to the right place.
--   * The last land car you picked is saved, one per side (data.lastCar for civilians, data.lastCopCar
--     for police cars), and is your starter car next time, if you still own it and can drive it on your
--     side. The automatic starter car (opts.Auto) is never saved, so it can't replace your favourite.
--     The last land car spawned is mirrored to the player attribute "LastCar" (the CAR button's
--     choice); boats never are, so CAR after a boat trip still brings a car.
--   * Drive (owner) and Ride prompts: not while tasered or knocked over, and not while you already sit
--     somewhere (a "GetOutFirst" toast says so, at most one every 3 s). A boat's prompts reach
--     CarBuilder.BoatReach (boats moor off the end of the docks); launching one while you stand on foot
--     within that reach of its pad sits you straight in it.
--   * Who rides with whom (Ride prompt, and RequestRide(car) from InteractClient's RIDE button / F): the
--     owner's crewmates and Roblox friends (CrewService.MayRide; Studio's test players count as friends),
--     on the owner's side (cops with cops, citizens with citizens), never a prisoner, from within reach
--     with no wall between, into a free passenger seat (not one a taxi fare sits in).
--   * Taxi fares (JobService): VehicleService.SeatNPC(car, model) sits a non-player rider in the free
--     passenger seat for everyone to see (a posed statue: no Humanoid, massless, parented into the car;
--     seat attribute NPCRider = true), VehicleService.ReleaseNPC(model) lets it go again.
--   * Getting out (RequestExitCar from F / E / B / EXIT, any seat): the seat is Humanoid.SeatPart, or, when
--     the server has lost track of that while a weld still holds the body, the seat a weld joins to the
--     root part. Every joint between the body and the seat goes, and any SeatWeld a rider who is gone left
--     behind (this place keeps a dead body's joints, CharacterBreakJointsOnDeath off, so resetting in a
--     seat used to leave its weld there; the next rider's F then destroyed that old weld instead of their
--     own and stayed in). The reply is CarExitSpot(spot): the client stands the body there. With no seat
--     to find the reply is CarExitSpot(nil, reason) (the client names it in Studio's Output).
--     Riders are also put out beside the car before it is removed (despawn, a new car, sinking).
--     Leftover SeatWelds are swept from players' cars every second and when a character is removed.
--   * Every SeatWeld in Workspace.Vehicles is fitted to its rider (CarBuilder.FitRider): an avatar too
--     tall for that roof sinks into the seat and leans back instead of poking its head out.
--   * RequestSpawnCar (CAR button / phone Garage): not while Wanted, not inside your home (use its
--     garage), not on a home tour or in a penthouse room (CarNoRoom), rate-limited, cooldown (3 s in
--     Studio). Asked from a seat (the phone opens while you
--     drive): for a boat you stay seated; for a car you are stepped out first, as RequestExitCar does,
--     unless you sit in a boat or the car is still rolling (then a "GetOutFirst" toast).
--   * A launched boat waits at its pad (waitingBoats) and the vehicle you came in stays, so you can drive
--     to the water. Sitting in the boat makes it your one vehicle and the other one goes. Until then
--     GetCar answers with whichever of the two you stand nearer to.
--   * Spawn opts.At: a CFrame or a list of them to try first (the home driveway).
--   * Where a car may appear (isClear): not on other cars, people, buildings, homes or showrooms. Street
--     furniture that cars drive through (PropService's "Props" collision group: hydrants, bins, benches,
--     news boxes, lamp posts, signal poles) is not in the way; a piece that is still solid for cars is.
--   * Spawned cars wear their owner's paint, rims and underglow, and their owner's tune
--     (GarageService.ApplyCustom: the tuned MaxSpeed / Accel / Brake / Grip / TireFriction / NitroSeconds
--     go onto the car's attributes, plus "Exhaust" and "TuneStage").
--   * Every spawned land car then gets its body joint and door spots (CarBuilder.AddBodyJoint: BodyRoot /
--     BodyJoint for the body lean VehicleFeel draws on each device, and the DriverDoor / PassengerDoor
--     attachments InteractClient walks you to before you get in). Boats get neither.
--   * Getting in is acted out on the player's own device (InteractClient: walk to the door, open it, hop
--     in); the seating itself still happens here and in ImpactService, with the same checks as before.
--   * Cars in water for 2 s, out of the world, or idle 10 minutes (nobody, not even a taxi fare, in any
--     seat) are removed.

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

-- Seconds after a new character appears that its starter car waits for the save to load. HousingService
-- uses the same window for the home spawn, so the player and their car always end up in the same place.
VehicleService.JoinWait = 15

local SPAWN_COOLDOWN = RunService:IsStudio() and 3 or 30
local REQUEST_GAP = 1 -- minimum seconds between spawn requests of any kind (spam guard)
local IDLE_DESPAWN = 600

local carsByUser = {} -- [userId] = model
-- [userId] = a boat launched at its pad that its owner hasn't sat in yet. Launching used to delete the car
-- the player stood next to, leaving the boat at a marina they could only walk to; now the car stays until
-- they take the boat (onOccupantChanged).
local waitingBoats = {}
local lastSpawn = {} -- [userId] = os.clock() of the last successful spawn
local lastRequest = {} -- [userId] = os.clock() of the last request
local idleSince = setmetatable({}, { __mode = "k" }) -- [model] = os.clock() it became empty
local sunkFor = setmetatable({}, { __mode = "k" }) -- [model] = seconds in water
local npcRider = setmetatable({}, { __mode = "k" }) -- [seat] = the taxi fare (a model) sitting there

local STUDIO = RunService:IsStudio()
local RIDE_REACH = 18 -- studs from the passenger seat (its prompt reaches 14; a little slack for lag)
local BOAT_REACH = CarBuilder.BoatReach + 6 -- boats: their prompts reach CarBuilder.BoatReach
local NPC_SEAT_UP = 1.3 -- a seated R15 rider's root part above the seat's top (as InteractClient's K.SEAT_UP)

local notify, exitSpot

local function template(id)
	local t = ServerStorage.VehicleTemplates:FindFirstChild(id)
	if t then
		return t:Clone()
	end
	return CarBuilder.Build(id)
end

-- Is there room for a car of `size` at `cf`? Checks other cars, characters, buildings, homes and dealerships.
-- `ignore` (optional): a model that doesn't count (the player's own car, about to be replaced).
-- Street furniture (Restyle, ArtKit): short, but a car spawned on a solid piece gets flung or wedged.
-- PropService makes these pass-through for cars (collision group PROPS_GROUP), and then they are not in
-- the way at all; the names only still count for a piece it left solid (Unbreakable, or no PropService).
local SOLID_PROPS = { Hydrant = true, TrashCan = true, Bench = true, NewsBox = true }
local PROPS_GROUP = "Props" -- PropService: never collides with "Vehicles"
local clearParams = OverlapParams.new()
clearParams.FilterType = Enum.RaycastFilterType.Include
local function isClear(cf, size, ignore)
	local list = { Workspace.Vehicles }
	local city = Workspace:FindFirstChild("City")
	for _, name in ipairs({ "Buildings", "Art", "Landmarks" }) do
		if city and city:FindFirstChild(name) then
			table.insert(list, city[name])
		end
	end
	local homes = Workspace:FindFirstChild("Homes") -- HousingService's houses
	if homes then
		table.insert(list, homes)
	end
	local dealers = Workspace:FindFirstChild("Dealerships") -- showroom walls, display cars, the boat kiosk
	if dealers then
		table.insert(list, dealers)
	end
	local shops = Workspace:FindFirstChild("Shops") -- the Zap Shack
	if shops then
		table.insert(list, shops)
	end
	-- The apartment towers' street entrances (ApartmentService) and the Big Score's lots (BigScoreService).
	for _, name in ipairs({ "Apartments", "BigScore" }) do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	clearParams.FilterDescendantsInstances = list
	local box = size + Vector3.new(2, 4, 3)
	-- Flat things under the wheels (boardwalk planks, kerbs, road paint, lawns) don't block a spawn,
	-- but short solid street furniture does, whatever its height. Furniture cars drive through (lamp
	-- posts and signal poles too, tall as they are) doesn't: a car can't get stuck on it any more.
	local bottom = cf.Y - size.Y / 2
	for _, p in ipairs(Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 1.5, 0), box, clearParams)) do
		if p.CollisionGroup ~= PROPS_GROUP then
			local top = p.Position.Y + p.Size.Y / 2
			local prop = p.Parent and SOLID_PROPS[p.Parent.Name]
			if (prop or top > bottom + 0.8 or p.Size.Y > 3) and not (ignore and p:IsDescendantOf(ignore)) then
				return false
			end
		end
	end
	return true
end

-- Ground in front of the player: only roads or open ground, never roofs or people, near foot level.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
-- `ignore` (optional): the player's own vehicle, about to be replaced. Stepped out of it a moment ago
-- (a car asked for from its seat), it would otherwise be what's "in the way" of the new one.
local function spawnCFrame(player, size, ignore)
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
			if isClear(cf, size, ignore) then
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

-- The player's saved profile, or nil (DataService starts after this service, so require it late).
local function profileOf(player)
	local ok, data = pcall(function()
		return require(script.Parent.DataService).Get(player)
	end)
	return ok and data or nil
end

-- Where a car's "last car" is saved: police cars (cop side) and everything else (civilian) are kept
-- apart, so a patrol shift never replaces a civilian's favourite.
local function savedKey(police)
	return police and "lastCopCar" or "lastCar"
end

-- The saved last car for this side, or nil.
function VehicleService.LastCarFor(player, side)
	local data = profileOf(player)
	local id = data and data[savedKey(side == "Cop")]
	return type(id) == "string" and Vehicles.ById[id] and id or nil
end

-- Wait (at most `timeout` seconds) until the player's save has loaded. Returns right away if it has.
local function waitForData(player, timeout)
	if player:GetAttribute("DataLoaded") or player.Parent ~= Players then
		return
	end
	local signal = Instance.new("BindableEvent")
	local done = false
	local function finish()
		if not done then
			done = true
			signal:Fire()
		end
	end
	local conn = player:GetAttributeChangedSignal("DataLoaded"):Connect(finish)
	task.delay(timeout, finish)
	signal.Event:Wait()
	conn:Disconnect()
end

-- Driveway spots of the player's home, if they own one and roam free (HousingService); else nil.
local function homeDriveway(player)
	local module = script.Parent:FindFirstChild("HousingService")
	if not module then
		return nil
	end
	local ok, spots = pcall(function()
		return require(module).DrivewayFor(player)
	end)
	return ok and spots or nil
end

-- Tasered or knocked over (server-time attributes from ArrestService / ImpactService)? No getting into a
-- car until back up, so the cop gets their chance to cuff (ImpactService's F / GET IN checks the same).
local function isDown(player)
	local t = Workspace:GetServerTimeNow()
	return (player:GetAttribute("StunnedUntil") or 0) > t or (player:GetAttribute("KnockedUntil") or 0) > t
end

-- Where to stand after getting out: beside your door (driver left, passenger right), worked out on a
-- level frame at the car's heading (seats may be reclined, CarBuilder.fitSeats, and the car may lie on
-- its side or its roof). A wall, fence or car in the way: the other door, then the roof. Then onto the
-- ground below. A seat with an ExitAt attribute (a world position) stands you there, facing its way.
local exitParams = RaycastParams.new()
exitParams.FilterType = Enum.RaycastFilterType.Exclude
exitParams.RespectCanCollide = true -- see-through triggers and decorations aren't walls
local function exitCFrame(seat)
	-- A seat that names its own spot (ApartmentService's furniture: its model is the whole penthouse, so
	-- every wall would count as "the car" and 4.5 studs lands on the next cushion or out through the glass).
	local at = seat:GetAttribute("ExitAt")
	if typeof(at) == "Vector3" then
		local _, seatYaw = seat.CFrame:ToEulerAnglesYXZ()
		return CFrame.new(at) * CFrame.Angles(0, seatYaw, 0)
	end
	local car = seat.Parent
	local chassis = car and car.PrimaryPart
	local _, yaw = (chassis and chassis.CFrame or seat.CFrame):ToEulerAnglesYXZ()
	local flat = CFrame.new(seat.Position) * CFrame.Angles(0, yaw, 0)
	-- People aren't walls (and never something to stand on).
	local ignore = { car }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	exitParams.FilterDescendantsInstances = ignore
	local side = seat.Name == "DriverSeat" and -1 or 1
	if chassis and chassis.CFrame.UpVector.Y < -0.3 then
		side = -side -- on its roof: the heading stays the same but your door is now on the other side
	end
	-- Measured from the car's middle, not the seat (the driver sits 1.1-2.1 left of it: with his own side
	-- blocked, 4.5 studs the other way was INSIDE the car). Both door spots end 2.2 clear of the flank,
	-- then behind the car, then in front, and only then the roof. Real cars only: any other seat (a home's
	-- couch: its model's PrimaryPart is the 51.5 x 62 floor) keeps 4.5 either side.
	local body = (chassis and car:GetAttribute("NCVehicle") == true) and chassis or nil
	local mid = body and flat:PointToObjectSpace(body.Position) or Vector3.zero
	local half = body and body.Size / 2 or Vector3.zero
	local across = math.max(half.X + 2.2, 4.5)
	local spots = { Vector3.new(mid.X + side * across, 0, 0), Vector3.new(mid.X - side * across, 0, 0) }
	if body then
		local along = half.Z + 2.5
		table.insert(spots, Vector3.new(mid.X, 0, mid.Z + along))
		table.insert(spots, Vector3.new(mid.X, 0, mid.Z - along))
	end
	for _, o in ipairs(spots) do
		local p = flat:PointToWorldSpace(o)
		if not Workspace:Raycast(seat.Position, p - seat.Position, exitParams) then
			local ground = Workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), exitParams)
			local pos = ground and ground.Position + Vector3.new(0, 3, 0) or p + Vector3.new(0, 2, 0)
			return CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		end
	end
	-- Boxed in on both sides: out through the roof, onto the highest point of the car.
	local top = seat.Position.Y + 5
	if car and car:IsA("Model") then
		local box, size = car:GetBoundingBox()
		top = box.Y + (math.abs(box.RightVector.Y) * size.X + math.abs(box.UpVector.Y) * size.Y
			+ math.abs(box.LookVector.Y) * size.Z) / 2 + 3
	end
	return CFrame.new(seat.Position.X, top, seat.Position.Z) * CFrame.Angles(0, yaw, 0)
end

------------------------------------------------------------------ seats and getting out

-- Every seat of a car (driver's and passenger's).
local function seatsOf(car)
	local list = {}
	for _, d in ipairs(car:GetChildren()) do
		if d:IsA("VehicleSeat") or d:IsA("Seat") then
			table.insert(list, d)
		end
	end
	return list
end

-- A SeatWeld whose rider is gone: the body was deleted (respawned after a reset in the seat: this place
-- keeps a dead body's joints, CharacterBreakJointsOnDeath = false, so the death itself left the weld) or is
-- dead. Seat.Occupant only clears once that weld goes.
local function staleWeld(j)
	local p = j.Part1
	if p == nil or not p:IsDescendantOf(Workspace) then
		return true
	end
	local hum = p.Parent and p.Parent:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health <= 0
end

-- Drop the leftover SeatWelds in a seat. Returns how many went.
local function clearStale(seat)
	local n = 0
	for _, j in ipairs(seat:GetChildren()) do
		if j:IsA("JointInstance") and j.Name == "SeatWeld" and staleWeld(j) then
			j:Destroy()
			n += 1
		end
	end
	return n
end

-- The seat holding this character: Humanoid.SeatPart, or (the server lost track of it while a weld still
-- holds the body) the seat a weld joins to the root part. Returns the seat (or nil) and, for the second
-- case, a note for Studio's Output.
local function seatOf(character, hum)
	local seat = hum and hum.SeatPart
	if seat then
		return seat, nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil, nil
	end
	for _, j in ipairs(root:GetJoints()) do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			local other = j.Part0 == root and j.Part1 or j.Part0
			if other and (other:IsA("Seat") or other:IsA("VehicleSeat")) then
				return other, "Humanoid.SeatPart was nil on the server, but a " .. j.ClassName .. " still held the body to "
					.. other:GetFullName()
			end
		end
	end
	return nil, nil
end

-- Remove every joint between this character and the seat, and any leftover SeatWeld in it (the seat's own
-- weld to the chassis stays). Destroying only the seat's first "SeatWeld" (as before) could take an old
-- rider's leftover one and leave the player's own: still seated, whatever they pressed.
local function unweld(seat, character)
	local n = 0
	for _, j in ipairs(seat:GetChildren()) do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
			local a, b = j.Part0, j.Part1
			local mine = (a ~= nil and a:IsDescendantOf(character)) or (b ~= nil and b:IsDescendantOf(character))
			if mine or (j:IsA("JointInstance") and j.Name == "SeatWeld" and staleWeld(j)) then
				j:Destroy()
				n += 1
			end
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		for _, j in ipairs(root:GetJoints()) do
			if (j:IsA("JointInstance") or j:IsA("WeldConstraint")) and (j.Part0 == seat or j.Part1 == seat) then
				j:Destroy()
				n += 1
			end
		end
	end
	return n
end

-- Put a player out of a seat (any seat) and beside it (exitCFrame), and tell their device where to stand.
-- Returns the spot.
local function stepOut(player, hum, seat)
	local character = player.Character
	local ok, target = pcall(exitCFrame, seat)
	if not ok or typeof(target) ~= "CFrame" then
		warn("[VehicleService] exit spot: " .. tostring(target))
		local _, yaw = seat.CFrame:ToEulerAnglesYXZ()
		local side = seat.Name == "DriverSeat" and -4.5 or 4.5
		target = CFrame.new((seat.CFrame * CFrame.new(side, 0, 0)).Position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, yaw, 0)
	end
	if character then
		unweld(seat, character)
	end
	hum.Sit = false
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return target
	end
	-- Step out beside your door, standing upright at the car's heading (exitCFrame).
	root.CFrame = target
	-- The player's own device runs their body, and it hears "the seat let go" and "you now stand over
	-- there" as two separate things. When the move lost that race (seen on every parked exit in a play
	-- test) the body stood up in the seat, was pushed up through the roof and stayed standing on the car:
	-- to the player, F had not got them out. So their device is told the spot and stands them there
	-- itself the moment the seat lets go (DriveController), and as a safety net, for the next second: still
	-- on the spot of the seat they left, put them beside the door again.
	if exitSpot then
		exitSpot:FireClient(player, target)
	end
	local seatAt = seat.Position
	-- A seat's own ExitAt spot (penthouse furniture) can be nearer than that: there only nearer the seat
	-- than the spot counts, else walking off along the island's stools would snap you back.
	local reach = 2.6
	if seat:GetAttribute("ExitAt") then
		local gap = target.Position - seatAt
		reach = math.min(reach, Vector3.new(gap.X, 0, gap.Z).Magnitude)
	end
	task.spawn(function()
		for _ = 1, 10 do
			task.wait(0.1)
			if not root.Parent or hum.SeatPart ~= nil or hum.Health <= 0 then
				return
			end
			local now = seat.Parent and seat.Position or seatAt
			local off = root.Position - now
			if Vector3.new(off.X, 0, off.Z).Magnitude < reach and math.abs(off.Y) < 9 then
				root.AssemblyLinearVelocity = Vector3.zero
				root.CFrame = target
			end
		end
	end)
	return target
end

-- Everyone out (players beside the car, like a normal exit), before the car goes away.
local function ejectAll(car)
	for _, seat in ipairs(seatsOf(car)) do
		local hum = seat.Occupant
		local p = hum and Players:GetPlayerFromCharacter(hum.Parent)
		if p and hum.Health > 0 then
			local ok, err = pcall(stepOut, p, hum, seat)
			if not ok then
				warn("[VehicleService] eject: " .. tostring(err))
			end
		end
	end
end

------------------------------------------------------------------ taxi fares (non-player riders)

-- Sit a non-player rider (an R15 model: JobService's taxi fare) in the car's passenger seat, for everyone
-- to see. It becomes a posed statue: its Humanoid goes (a humanoid welded into a car pushes the car about),
-- every part is massless, doesn't collide and is invisible to rays, and it plays Roblox's sit animation.
-- It is parented into the car, so it streams with it and goes with it. Returns the seat, or nil when the
-- seat is taken (a crewmate or friend rides there) or the car has none.
function VehicleService.SeatNPC(car, model)
	local seat = car and car.Parent and car:FindFirstChild("PassengerSeat")
	local root = model and model:FindFirstChild("HumanoidRootPart")
	if not seat or not seat:IsA("Seat") or not root or not root:IsA("BasePart") then
		return nil
	end
	clearStale(seat)
	if seat.Occupant or npcRider[seat] then
		return nil
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
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
	model:PivotTo(seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + NPC_SEAT_UP, 0))
	local w = Instance.new("WeldConstraint")
	w.Name = "RiderWeld"
	w.Part0 = seat
	w.Part1 = root
	w.Parent = root
	model.Parent = car
	seat:SetAttribute("NPCRider", true)
	npcRider[seat] = model
	idleSince[car] = nil
	model.Destroying:Once(function()
		-- However the fare goes (dropped off, the shift ended, the car went), the seat is free again.
		if npcRider[seat] == model then
			npcRider[seat] = nil
			if seat.Parent then
				seat:SetAttribute("NPCRider", nil)
			end
		end
	end)
	CarBuilder.PlayPose(model, "sit")
	return seat
end

-- Let a taxi fare go from its seat (the caller moves it or removes it). Returns the seat it sat in, or nil.
function VehicleService.ReleaseNPC(model)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local w = root and root:FindFirstChild("RiderWeld")
	local seat = w and w.Part0
	if w then
		w:Destroy()
	end
	if seat and npcRider[seat] == model then
		npcRider[seat] = nil
		seat:SetAttribute("NPCRider", nil)
	end
	return seat
end

------------------------------------------------------------------ cars

-- Removes the vehicle a player has in one slot (carsByUser or waitingBoats), if any. Anyone still sitting
-- in it is put out beside it first.
local function clearSlot(slot, userId)
	local car = slot[userId]
	slot[userId] = nil
	if car then
		idleSince[car] = nil
		sunkFor[car] = nil
		local ok, err = pcall(ejectAll, car)
		if not ok then
			warn("[VehicleService] eject: " .. tostring(err))
		end
		car:Destroy()
	end
end

-- Everything the player has out: their vehicle, and a boat still waiting for them at its pad.
function VehicleService.Despawn(userId)
	clearSlot(carsByUser, userId)
	clearSlot(waitingBoats, userId)
end

function VehicleService.GetCar(player)
	local car, boat = carsByUser[player.UserId], waitingBoats[player.UserId]
	if not boat then
		return car
	end
	-- A boat waiting at its pad is "your car" as well while you stand nearer to it than to the car you
	-- came in: GET IN (ImpactService) asks this, and you need both, the car to drive there and then the
	-- boat. Measured to the driver's seat, as the player's device does when it picks which one to enter.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local carSeat, boatSeat = car and car:FindFirstChild("DriverSeat"), boat:FindFirstChild("DriverSeat")
	if not car or (root and carSeat and boatSeat
		and (boatSeat.Position - root.Position).Magnitude < (carSeat.Position - root.Position).Magnitude) then
		return boat
	end
	return car
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
			-- Only the owner drives (crewmates and friends ride in the passenger seat). That rider's own weld
			-- goes, not just the seat's first one.
			unweld(seat, humanoid.Parent)
			return
		end
		idleSince[car] = nil
		-- The owner has taken the boat that was waiting for them: from here on it is their one vehicle,
		-- and the one they came in goes (the old swap, only not before they have reached the water).
		if waitingBoats[player.UserId] == car then
			waitingBoats[player.UserId] = nil
			clearSlot(carsByUser, player.UserId)
			carsByUser[player.UserId] = car
		end
		car:SetAttribute("DriverUserId", player.UserId)
		chassis:SetNetworkOwner(player)
	else
		car:SetAttribute("DriverUserId", nil)
		local pseat = car:FindFirstChild("PassengerSeat")
		idleSince[car] = not (pseat and (pseat.Occupant or npcRider[pseat])) and os.clock() or nil
		task.delay(1.5, function()
			if car.Parent and seat.Occupant == nil and chassis:IsDescendantOf(Workspace) then
				chassis:SetNetworkOwner(nil)
			end
		end)
	end
end

-- "Get out of your car first", at most one toast every 3 s (the key is shared with ImpactService,
-- CarjackService and CarBoostService, so trying several at once still gives one toast).
local function getOutFirst(who)
	if RateLimit.Allow(who, "GetOutFirstToast", 1 / 3, 1) then
		Remotes.Event("Notify"):FireClient(who, "GetOutFirst")
	end
end

-- Sit `who` in `seat` (a car's passenger seat) if they may ride with that car's owner: the owner's
-- crewmate or Roblox friend (CrewService.MayRide), on the owner's side, never a prisoner (the vent is the
-- only way out), on foot and not knocked over or tasered, within reach, with no wall between (boats: the
-- dock's rail doesn't count), the seat free (a taxi fare sits in it, or someone else). Returns true when
-- seated. Only "get out first" is said out loud: anyone else simply sees no bubble and no RIDE button.
local function tryRide(who, car, seat)
	if typeof(car) ~= "Instance" or not car:IsA("Model") or car.Parent ~= Workspace.Vehicles
		or typeof(seat) ~= "Instance" or not seat:IsA("Seat") or seat.Parent ~= car then
		return false
	end
	local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
	local root = who.Character and who.Character:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return false
	end
	if hum.SeatPart then
		getOutFirst(who) -- sitting in another car (or this one's other seat)
		return false
	end
	local owner = Players:GetPlayerByUserId(car:GetAttribute("OwnerUserId") or 0)
	if not owner or owner == who or isDown(who) then
		return false
	end
	clearStale(seat)
	if seat.Occupant or npcRider[seat] then
		return false
	end
	local crew = require(script.Parent.CrewService)
	local may = false
	if type(crew.MayRide) == "function" then
		may = crew.MayRide(who, owner)
	else
		may = crew.SameCrew(who, owner)
	end
	local side = who:GetAttribute("Side")
	if not may or side == "Prisoner" or side ~= owner:GetAttribute("Side") then
		return false
	end
	local boat = car:GetAttribute("Boat") == true
	if (root.Position - seat.Position).Magnitude >= (boat and BOAT_REACH or RIDE_REACH) then
		return false
	end
	if not boat then
		-- No riding through walls or fences. People don't block it: a seated driver's character stays
		-- under Workspace (not the car), right across the ray from the driver's side.
		local los = RaycastParams.new()
		los.FilterType = Enum.RaycastFilterType.Exclude
		local ignore = { car }
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then
				table.insert(ignore, p.Character)
			end
		end
		los.FilterDescendantsInstances = ignore
		if Workspace:Raycast(root.Position, seat.Position - root.Position, los) then
			return false
		end
	end
	seat:Sit(hum)
	return true
end

-- opts: { Sit = bool, PadSide = role name (spawn on that role's nearest pad), IgnoreCooldown = bool,
--   At = CFrame or { CFrame, ... } (land cars: try these spots first, e.g. a home driveway; then
--   PadSide's pad nearest them, then the road in front of the player),
--   Auto = bool (the game picked this car, not the player: don't save it as their last car) }
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
	if def.Boat then
		-- Boats launch from the nearest marina boat pad for your side, however far away it is.
		local side = player:GetAttribute("Side") == "Cop" and "Cop" or "Civilian"
		cf = root and padCFrame(side, def.Size, root.Position, true)
	else
		-- The pad fallback looks near the requested spots when there are some (on join the character
		-- is still at the city spawn while HousingService moves it home), else near the player.
		local near = root and root.Position
		if opts.At then
			local spots = typeof(opts.At) == "CFrame" and { opts.At } or opts.At
			if typeof(spots[1]) == "CFrame" then
				near = spots[1].Position
			end
			for _, spot in ipairs(spots) do
				-- The player's current car doesn't count: it's replaced below.
				if typeof(spot) == "CFrame" and isClear(spot, def.Size, carsByUser[player.UserId]) then
					cf = spot
					break
				end
			end
		end
		if not cf and opts.PadSide and near then
			cf = padCFrame(opts.PadSide, def.Size, near)
		end
	end
	cf = cf or (not def.Boat and spawnCFrame(player, def.Size, carsByUser[player.UserId]) or nil)
	if not cf then
		return nil, "no room"
	end
	if not opts.IgnoreCooldown then
		lastSpawn[player.UserId] = now -- the free starter car on a pad doesn't use up the cooldown
	end
	-- A boat launches at the water, often far from here, and the player needs the car they came in to get
	-- there: so a new boat only replaces an older boat that is still waiting, and their vehicle goes once
	-- they sit in the boat (onOccupantChanged). A land car replaces their vehicle as it always did.
	local slot = def.Boat and waitingBoats or carsByUser
	clearSlot(slot, player.UserId)

	local car = template(id)
	car:SetAttribute("OwnerUserId", player.UserId)
	local okCustom, err = pcall(function()
		require(script.Parent.GarageService).ApplyCustom(car, player)
	end)
	if not okCustom then
		warn("[VehicleService] custom paint failed: " .. tostring(err))
	end
	-- The body joint and door spots (CarBuilder.AddBodyJoint): a fresh Build has them already, a clone of
	-- a saved template from before they existed gets them here. Before the car is placed, so every part
	-- still sits where it was built. Only looks: a failure never costs the player their car.
	local okJoint, errJoint = pcall(CarBuilder.AddBodyJoint, car)
	if not okJoint then
		warn("[VehicleService] body joint failed: " .. tostring(errJoint))
	end
	car:PivotTo(cf)
	car.Parent = Workspace.Vehicles
	slot[player.UserId] = car
	idleSince[car] = now
	car.PrimaryPart:SetNetworkOwner(nil)
	-- The CAR button's choice: land cars only (a boat always launches at a marina, maybe far away).
	if not def.Boat then
		player:SetAttribute("LastCar", id)
	end
	-- Saved across sessions (land cars the player chose: that's the starter car next time).
	if not def.Boat and not opts.Auto then
		local data = profileOf(player)
		if data then
			data[savedKey(def.Police)] = id
		end
	end

	local seat = car:FindFirstChild("DriverSeat")
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onOccupantChanged(car, seat)
	end)
	local prompt = seat:FindFirstChild("DrivePrompt")
	if prompt then
		prompt.Triggered:Connect(function(who)
			if isDown(who) then
				return
			end
			local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.SeatPart and hum.Health > 0 then
				-- Sitting somewhere already (another car, a passenger seat): say why nothing happens, as
				-- the Ride prompt does (they share the 3 s toast limit).
				getOutFirst(who)
				return
			end
			clearStale(seat) -- (an old rider's leftover weld would keep the seat "taken")
			if hum and hum.Health > 0 and seat.Occupant == nil and car:GetAttribute("OwnerUserId") == who.UserId then
				seat:Sit(hum)
			end
		end)
	end
	-- Crewmates and friends ride in the passenger seat (tryRide has the rules).
	local pseat = car:FindFirstChild("PassengerSeat")
	local ride = pseat and pseat:FindFirstChild("RidePrompt")
	if ride then
		ride.Triggered:Connect(function(who)
			tryRide(who, car, pseat)
		end)
	end
	-- A boat waiting at a far-off marina: no teleport; the client routes the GPS to it. Launched from the
	-- dock (on foot, within the reach of its Drive bubble): straight into its seat.
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local onFoot = hum ~= nil and hum.Health > 0 and hum.SeatPart == nil
	if def.Boat and root and (cf.Position - root.Position).Magnitude > CarBuilder.BoatReach then
		Remotes.Event("BoatDelivered"):FireClient(player, { Pos = cf.Position, Name = def.DisplayName })
	elseif hum and hum.Health > 0 and (opts.Sit or (def.Boat and onFoot)) then
		task.defer(function()
			if car.Parent and seat.Parent and seat.Occupant == nil and hum.Parent and hum.Health > 0
				and (opts.Sit or hum.SeatPart == nil) then
				seat:Sit(hum)
			end
		end)
	end
	return car
end

function VehicleService.Init()
	CarBuilder.EnsureGroups()
	notify = Remotes.Event("Notify")
	Remotes.Event("BoatDelivered")
	local requestSpawn = Remotes.Event("RequestSpawnCar")
	local requestExit = Remotes.Event("RequestExitCar")
	-- Server -> the player who just got out: the spot beside the door (a CFrame). Their own device runs
	-- their body, so it is the one that has to stand it there (DriveController); see stepOut. (nil, reason)
	-- when there was no seat to get out of, so their device can say why in Studio.
	exitSpot = Remotes.Event("CarExitSpot")
	-- Client -> server: InteractClient's RIDE (F / the button) next to a crewmate's or friend's car.
	Remotes.Event("RequestRide").OnServerEvent:Connect(function(player, car)
		if not RateLimit.Allow(player, "Ride", 2, 3) then
			return
		end
		if typeof(car) == "Instance" and car:IsA("Model") and car.Parent == Workspace.Vehicles then
			tryRide(player, car, car:FindFirstChild("PassengerSeat"))
		end
	end)
	-- Every rider is fitted to their own size the moment their seat's weld appears (CarBuilder.FitRider),
	-- whoever seated them (this service, ImpactService's GET IN, a carjack, the Big Score van).
	local function fitRider(d)
		if d.Name ~= "SeatWeld" or not d:IsA("Weld") then
			return
		end
		task.defer(function()
			if not d.Parent then
				return
			end
			local ok, drop, lean = pcall(CarBuilder.FitRider, d)
			if not ok then
				warn("[VehicleService] rider fit: " .. tostring(drop))
			elseif drop and STUDIO then
				print(string.format("[VehicleService] rider fit: %s sank %.2f studs and leaned %.0f deg more in %s",
					tostring(d.Part1 and d.Part1.Parent and d.Part1.Parent.Name), drop, lean or 0, d.Parent:GetFullName()))
			end
		end)
	end
	local vehicles = Workspace:FindFirstChild("Vehicles") or Workspace:WaitForChild("Vehicles", 5)
	if vehicles then
		vehicles.DescendantAdded:Connect(fitRider)
	else
		warn("[VehicleService] no Workspace.Vehicles: riders won't be fitted to the roofs")
	end

	-- H key: cops toggle their siren, everyone else honks (clients play the sound from the attribute).
	-- Works in whatever car you're driving: your own, or a stolen hot car (CarBoostService).
	local lastHorn = {}
	Remotes.Event("RequestHorn").OnServerEvent:Connect(function(player)
		local now = os.clock()
		if lastHorn[player] and now - lastHorn[player] < 0.6 then
			return
		end
		lastHorn[player] = now
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		local car = seat and seat.Name == "DriverSeat" and seat.Parent
		if not car or car.Parent ~= Workspace.Vehicles or car:GetAttribute("DriverUserId") ~= player.UserId then
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
		-- A show home on a tour has no garage of yours, and a penthouse room (ApartmentService) is up on a
		-- roof: no room for a car (said before anyone is stood up from a couch for nothing).
		if player:GetAttribute("Touring") or player:GetAttribute("InApartment") then
			notify:FireClient(player, "CarNoRoom")
			return
		end
		-- Inside your home (HousingService): pick a car in its garage, or step outside first.
		if player:GetAttribute("InHome") then
			notify:FireClient(player, "HomeUseGarage")
			return
		end
		-- Wanted players may swap cars only while the cops can't see them (a classic shake-off).
		if (player:GetAttribute("Heat") or 0) > 0 and player:GetAttribute("HeatSpotted") then
			notify:FireClient(player, "NoCarWhileWanted")
			return
		end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return
		end
		-- Asked from a seat (the phone's GARAGE opens while you drive): DELIVER and LAUNCH used to close the
		-- phone and do nothing, with no message.
		local seat = hum.SeatPart
		local sit = RunService:IsStudio()
		if seat and Vehicles.ById[id].Boat then
			-- A boat: stay in your car. The boat waits at the water and you drive there.
			sit = false
		elseif seat then
			-- A car: step out first, then it is delivered as usual. Not out of a boat (that's a swim, with
			-- no road for the car) and not while still rolling (the empty car would run off): say why.
			local ride = seat.Parent
			if (ride and ride:GetAttribute("Boat")) or seat.AssemblyLinearVelocity.Magnitude > 20 then
				notify:FireClient(player, "GetOutFirst")
				return
			end
			-- Still cooling down: say so before anyone is moved out of their seat for nothing.
			if lastSpawn[player.UserId] and now - lastSpawn[player.UserId] < SPAWN_COOLDOWN then
				notify:FireClient(player, "CarCooldown")
				return
			end
			-- The same steps as RequestExitCar below.
			stepOut(player, hum, seat)
			-- No Studio auto-seat this time (it would sit you down again in the very instant you stood up):
			-- the new car is on the road in front of you, as it is for everyone in a live game.
			sit = false
		end
		local car, why = VehicleService.Spawn(player, id, { Sit = sit })
		if not car then
			notify:FireClient(player, why == "cooldown" and "CarCooldown" or "CarNoRoom")
		end
	end)

	-- Getting out, from any seat (nobody is ever stuck sitting). The seat is found from the weld when
	-- Humanoid.SeatPart has lost track of it, and every joint holding the body goes (seatOf, unweld).
	requestExit.OnServerEvent:Connect(function(player)
		if not RateLimit.Allow(player, "ExitCar", 4, 4) then
			return
		end
		local character = player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if not hum then
			exitSpot:FireClient(player, nil, "the server has no character for you")
			return
		end
		local seat, note = seatOf(character, hum)
		if not seat then
			exitSpot:FireClient(player, nil, "the server sees no seat holding you (Humanoid.SeatPart is nil and no weld joins you to a seat)")
			return
		end
		if note and STUDIO then
			warn("[VehicleService] exit: " .. note)
		end
		stepOut(player, hum, seat)
	end)

	-- The saved last car becomes the CAR button's choice (when this side can drive it).
	local okLoaded, errLoaded = pcall(function()
		require(script.Parent.DataService).OnLoaded(function(player, data)
			-- Older saves kept a police car in lastCar: move it to the cop slot.
			local old = type(data.lastCar) == "string" and Vehicles.ById[data.lastCar] or nil
			if old and old.Police then
				data.lastCopCar = data.lastCopCar or data.lastCar
				data.lastCar = nil
			end
			local side = player:GetAttribute("Side") or "Civilian"
			local last = VehicleService.LastCarFor(player, side)
			if last and not player:GetAttribute("LastCar") and VehicleService.CanDrive(side, last) then
				player:SetAttribute("LastCar", last)
			end
		end)
	end)
	if not okLoaded then
		warn("[VehicleService] couldn't hook saved cars: " .. tostring(errLoaded))
	end

	-- Every new character finds its starter car on the nearest free pad (if they don't have one), or
	-- on its home's driveway.
	local function onCharacter(player)
		local t0 = os.clock()
		task.wait(0.5)
		-- On join the save may still be loading: wait for it, so the saved car goes to the saved home.
		-- The window is counted from the moment the character appeared (as HousingService does).
		waitForData(player, math.max(0, VehicleService.JoinWait - (os.clock() - t0)))
		if player.Parent ~= Players or carsByUser[player.UserId] then
			return
		end
		local side = player:GetAttribute("Side") or "Civilian"
		local team = Teams.BySide[side]
		if not team or not team.Starter then
			return
		end
		local last = VehicleService.LastCarFor(player, side) or player:GetAttribute("LastCar")
		local id = team.Starter
		local lastDef = type(last) == "string" and Vehicles.ById[last] or nil
		if lastDef and not lastDef.Boat and VehicleService.CanDrive(side, last)
			and require(script.Parent.GarageService).Owns(player, last) then
			id = last
		end
		-- Auto: the game picked this car, so it never replaces the player's saved favourite.
		VehicleService.Spawn(player, id, { At = homeDriveway(player), PadSide = side, IgnoreCooldown = true, Auto = true })
	end
	local function onPlayer(player)
		player.CharacterAdded:Connect(function()
			onCharacter(player)
		end)
		-- A body that goes while it sits (a respawn after a reset in the seat, a team change) takes its seat
		-- weld with it, so the seat is free at once (see staleWeld).
		player.CharacterRemoving:Connect(function(character)
			local hum = character:FindFirstChildOfClass("Humanoid")
			local seat = hum and seatOf(character, hum)
			if seat then
				pcall(unweld, seat, character)
			end
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
		VehicleService.Despawn(player.UserId)
		lastSpawn[player.UserId] = nil
		lastRequest[player.UserId] = nil
	end)

	-- Housekeeping every second: cars in water, out of the world, or unused.
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			-- Leftover seat welds (see staleWeld) in the cars nobody owns as well: hot and jacked cars, the
			-- Big Score van (their services' own exits destroy a seat's first SeatWeld only).
			local folder = Workspace:FindFirstChild("Vehicles")
			for _, car in ipairs(folder and folder:GetChildren() or {}) do
				if car:IsA("Model") and car:GetAttribute("OwnerUserId") == nil then
					for _, seat in ipairs(seatsOf(car)) do
						clearStale(seat)
					end
				end
			end
			-- Every player vehicle: the one they have out, and a boat still waiting for them at its pad.
			-- Each is judged alone, so a car lost on the way to the water doesn't take the boat with it.
			local all = {}
			for userId, car in pairs(carsByUser) do
				table.insert(all, { carsByUser, userId, car })
			end
			for userId, boat in pairs(waitingBoats) do
				table.insert(all, { waitingBoats, userId, boat })
			end
			for _, entry in ipairs(all) do
				local slot, userId, car = entry[1], entry[2], entry[3]
				local chassis = car.PrimaryPart
				local owner = Players:GetPlayerByUserId(userId)
				if not chassis or not chassis:IsDescendantOf(Workspace) or chassis.Position.Y < -60 then
					clearSlot(slot, userId)
				elseif chassis.Position.Y < 0.2 and not car:GetAttribute("Boat") then
					-- On land the chassis centre never drops below +1.6, so this means water (cars float
					-- at about -2 in sea water). Two seconds in the water and the car is gone.
					sunkFor[car] = (sunkFor[car] or 0) + 1
					if sunkFor[car] >= 2 then
						clearSlot(slot, userId)
						if owner then
							notify:FireClient(owner, "CarSank")
						end
					end
				else
					sunkFor[car] = nil
					-- Idle = nobody in any seat (a passenger or a taxi fare keeps the car alive too). A seat
					-- whose rider is gone has its leftover weld swept here (see staleWeld), so it reads empty.
					local used = false
					for _, seat in ipairs(seatsOf(car)) do
						if clearStale(seat) > 0 and STUDIO then
							warn("[VehicleService] removed a leftover SeatWeld (its rider is gone) from " .. seat:GetFullName())
						end
						if seat.Occupant or npcRider[seat] then
							used = true
						end
					end
					if used then
						idleSince[car] = nil
					elseif not idleSince[car] then
						idleSince[car] = now
					end
					local since = idleSince[car]
					if since and now - since > IDLE_DESPAWN then
						clearSlot(slot, userId)
					end
				end
			end
		end
	end)
end

return VehicleService
