-- VehicleService (ModuleScript, ServerScriptService.Services.VehicleService)
-- Spawns and despawns cars, seats drivers, and hands each car's physics to its driver's device.
-- One car per player, from the cars they own (GarageService; starters are free for everyone).
-- In Studio tests any car can be spawned.
--   * New characters find their last (or starter) car on the nearest free pad for their role.
--   * RequestSpawnCar (CAR button / phone Garage): not while Wanted, rate-limited, cooldown (3 s in Studio).
--   * Spawned cars wear their owner's paint, rims and underglow (GarageService.ApplyCustom).
--   * Cars in water for 2 s, out of the world, or idle 10 minutes are removed.
--   * Player attribute LastCar = the last land car spawned (the HUD CAR button sends it back);
--     LastBoat = the last boat.
--   * Nobody gets in while tased (StunnedUntil). Getting out picks a free spot beside the door, then
--     the other side, the front, the back, and finally the roof, never through a wall.
--   * A cop's siren switches off when the driver gets out.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Teams = require(ReplicatedStorage.Shared.Config.Teams)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local CarBuilder = require(ServerStorage.Tools.CarBuilder)

local VehicleService = {}

local SPAWN_COOLDOWN = RunService:IsStudio() and 3 or 30
local REQUEST_GAP = 1 -- minimum seconds between spawn requests of any kind (spam guard)
local IDLE_DESPAWN = 600

local carsByUser = {} -- [userId] = model
local lastSpawn = {} -- [userId] = os.clock() of the last successful spawn
local lastRequest = {} -- [userId] = os.clock() of the last request
local idleSince = setmetatable({}, { __mode = "k" }) -- [model] = os.clock() it became empty
local sunkFor = setmetatable({}, { __mode = "k" }) -- [model] = seconds in water

local notify

-- Tased (ArrestService sets StunnedUntil in server time): no getting into cars.
local function stunned(player)
	return (player:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow()
end

-- Close enough to the seat to really be at the car (prompt triggers are client claims).
local SEAT_REACH = 20
local function nearSeat(character, seat)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and (root.Position - seat.Position).Magnitude <= SEAT_REACH
end

local function template(id)
	local t = ServerStorage.VehicleTemplates:FindFirstChild(id)
	if t then
		return t:Clone()
	end
	return CarBuilder.Build(id)
end

-- Is there room for a car of `size` at `cf`? Checks other cars, characters and buildings.
local clearParams = OverlapParams.new()
clearParams.FilterType = Enum.RaycastFilterType.Include
local function isClear(cf, size)
	local list = { Workspace.Vehicles }
	local city = Workspace:FindFirstChild("City")
	for _, name in ipairs({ "Buildings", "Art", "Landmarks" }) do
		if city and city:FindFirstChild(name) then
			table.insert(list, city[name])
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	clearParams.FilterDescendantsInstances = list
	local box = size + Vector3.new(2, 4, 3)
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

function VehicleService.Despawn(userId)
	local car = carsByUser[userId]
	carsByUser[userId] = nil
	if car then
		idleSince[car] = nil
		sunkFor[car] = nil
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
			-- Only the owner drives for now (crews come with step 2.3).
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
		local pseat = car:FindFirstChild("PassengerSeat")
		idleSince[car] = not (pseat and pseat.Occupant) and os.clock() or nil
		task.delay(1.5, function()
			if car.Parent and seat.Occupant == nil and chassis:IsDescendantOf(Workspace) then
				chassis:SetNetworkOwner(nil)
			end
		end)
	end
end

-- opts: { Sit = bool, PadSide = role name (spawn on that role's nearest pad), IgnoreCooldown = bool }
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
	elseif opts.PadSide and root then
		cf = padCFrame(opts.PadSide, def.Size, root.Position)
	end
	cf = cf or (not def.Boat and spawnCFrame(player, def.Size) or nil)
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
	local prompt = seat:FindFirstChild("DrivePrompt")
	if prompt then
		prompt.Triggered:Connect(function(who)
			local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and not hum.SeatPart and seat.Occupant == nil
				and car:GetAttribute("OwnerUserId") == who.UserId and not stunned(who) and nearSeat(who.Character, seat) then
				seat:Sit(hum)
			end
		end)
	end
	-- Crewmates ride in the passenger seat.
	local pseat = car:FindFirstChild("PassengerSeat")
	local ride = pseat and pseat:FindFirstChild("RidePrompt")
	if ride then
		ride.Triggered:Connect(function(who)
			local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
			local owner = Players:GetPlayerByUserId(car:GetAttribute("OwnerUserId") or 0)
			if not hum or hum.Health <= 0 or hum.SeatPart or pseat.Occupant or not owner or who == owner or stunned(who) then
				return
			end
			if not require(script.Parent.CrewService).SameCrew(who, owner) then
				return
			end
			-- Same side only, and never out of prison (the vent is the only way out).
			local side = who:GetAttribute("Side")
			if side == "Prisoner" or side ~= owner:GetAttribute("Side") then
				return
			end
			local root = who.Character:FindFirstChild("HumanoidRootPart")
			if not root or (root.Position - pseat.Position).Magnitude >= 18 then
				return
			end
			-- No riding through walls or fences.
			local los = RaycastParams.new()
			los.FilterType = Enum.RaycastFilterType.Exclude
			los.FilterDescendantsInstances = { who.Character, car }
			if Workspace:Raycast(root.Position, pseat.Position - root.Position, los) then
				return
			end
			pseat:Sit(hum)
		end)
	end
	-- A boat waiting at a far-off marina: no teleport; the client routes the GPS to it.
	if def.Boat and root and (cf.Position - root.Position).Magnitude > 60 then
		Remotes.Event("BoatDelivered"):FireClient(player, { Pos = cf.Position, Name = def.DisplayName })
	elseif opts.Sit and not stunned(player) then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			task.defer(function()
				seat:Sit(hum)
			end)
		end
	end
	return car
end

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
-- so rotated buildings near the spot don't block it.)
local function noRoom(root)
	for _, p in ipairs(Workspace:GetPartBoundsInBox(CFrame.new(root + Vector3.new(0, 0.2, 0)), Vector3.new(2, 4.2, 2), roomParams)) do
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
	local ignore = { car, character, Workspace:FindFirstChild("Smoke") }
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
	local side = seat.Name == "DriverSeat" and -1 or 1 -- driver's door on the left
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

function VehicleService.Init()
	CarBuilder.EnsureGroups()
	notify = Remotes.Event("Notify")
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
		local car, why = VehicleService.Spawn(player, id, { Sit = RunService:IsStudio() })
		if not car then
			notify:FireClient(player, why == "cooldown" and "CarCooldown" or "CarNoRoom")
		end
	end)

	requestExit.OnServerEvent:Connect(function(player)
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if seat and (seat.Name == "DriverSeat" or seat.Name == "PassengerSeat") then
			local car = seat.Parent
			local spot
			if car and car:IsA("Model") and car.PrimaryPart then
				local ok, res = pcall(exitSpot, car, seat, player.Character)
				spot = ok and res or nil
				if not ok then
					warn("[VehicleService] exit spot: " .. tostring(res))
				end
			end
			local sw = seat:FindFirstChild("SeatWeld")
			if sw then
				sw:Destroy()
			end
			hum.Sit = false
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if root and spot then
				root.CFrame = spot
			elseif root then
				root.CFrame = seat.CFrame * CFrame.new(seat.Name == "DriverSeat" and -4.5 or 4.5, 1.5, 0)
			end
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
		VehicleService.Despawn(player.UserId)
		lastSpawn[player.UserId] = nil
		lastRequest[player.UserId] = nil
	end)

	-- Housekeeping every second: cars in water, out of the world, or unused.
	task.spawn(function()
		while true do
			task.wait(1)
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
					-- Idle = nobody in either seat (a passenger keeps the car alive too).
					local dseat, pseat = car:FindFirstChild("DriverSeat"), car:FindFirstChild("PassengerSeat")
					if (dseat and dseat.Occupant) or (pseat and pseat.Occupant) then
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
	end)
end

return VehicleService
