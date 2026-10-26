-- CarjackService (ModuleScript, ServerScriptService.Services.CarjackService)
-- Car theft off the street, for citizens (kid-friendly: the driver just jumps out and runs).
--   * Moving traffic: TrafficClient runs the traffic on each device, so the server never sees those cars.
--     InteractClient's JACK button (F / gamepad X) sends RequestCarjack(kind, cframe, colour) and we check
--     it all: a citizen on foot (not seated, tasered, knocked over or in a home, and not within 8 s of
--     their last jack), the car's spot within 20 studs of them (the client offers JACK within about 15;
--     the rest is lag), right on a road surface (City.Roads, no roofs or lawns) near the road graph, in
--     plain view of the thief (no taking one through a wall), with room for the car (other cars, people,
--     buildings, homes, shops, walls and street furniture all block it), a known kind (Hatchback / Sedan /
--     Pickup) and a real colour. Then a real street car of that kind (Config.Vehicles StreetHatch /
--     StreetSedan / StreetPickup: CarBuilder puts that traffic body on it) appears right there, same
--     heading and paint, with the thief at the wheel. Every refusal after the first sanity checks is
--     answered with CarjackRefused, so the client lets go of that traffic car at once.
--   * Parked cars in the Restyle car parks (Workspace.City.Art.BlockFill, models "CarPark"): each one gets a
--     "Break in" prompt at its driver's door at start-up (hold 3 s, timed here: a hold let go early is void
--     and an old one can't be kept for later; citizens on foot only, InteractClient hides it otherwise).
--     It's named PickLockPrompt so starting the hold ends passive mode like any crime (CombatService), and
--     tagged "BreakInPrompt" so InteractClient can find it. The thief must be able to see the door. They
--     drive off in a real car wearing that very parked body (its colours too); the parked copy hides and
--     is back 5 minutes later, once its stall is empty. 35% of them have an alarm: it rings for 8 s (car
--     attribute CarAlarmUntil, server time; InteractClient plays it for everyone near).
--   * Stars: a jack off the street, or a car alarm, gives +1 star (reason "carjack": no bounty, see
--     HeatService), but only to someone with no stars yet, so jacking car after car can't stack stars to
--     farm escape XP or the "lose the cops with 2+ stars" challenge. Any star also ends passive mode
--     (CombatService watches Heat).
--   * One jacked car per player: a new one replaces the old. It's stolen, never owned: CarBoostService.Track
--     looks after it (only the thief drives it, back in with GET IN, gone 2 minutes after it's left empty,
--     or when the thief leaves, is arrested or switches sides) and the Chop Shop buys it for its street
--     value into the bag (Hatchback $250, Sedan $350, Pickup $450), unless it was taken right by the Chop
--     Shop (car attribute JackSellable = false).
--   * Every jack (street or car park) is reported to ProgressService as "Carjack" (no XP; goal chain).
--   * Carjacked (server -> thief): { Kind, Value, Alarm, Parked, Sellable }. ObjectiveClient stamps it and
--     may suggest the Chop Shop on the GPS; TrafficClient sends the driver running and drops the traffic
--     car it handed over. CarjackRefused (server -> thief, no arguments): the jack didn't happen.
-- Notify keys: JackCooldown (too soon after the last one), JackBlocked (no room for the car there, or
-- something between the thief and the car), GetOutFirst (a jack or a finished Break in hold from someone
-- sitting in a car: at most one every 3 s, shared with CarBoostService and ImpactService).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local CarBuilder = require(ServerStorage.Tools.CarBuilder)
local HeatService = require(ServerScriptService.Services.HeatService)
local CarBoostService = require(ServerScriptService.Services.CarBoostService)

local CarjackService = {}

-- Traffic kinds (ReplicatedStorage.TrafficModels names) -> the street car it becomes and its Chop Shop value.
local KINDS = {
	Hatchback = { Car = "StreetHatch", Value = 250 },
	Sedan = { Car = "StreetSedan", Value = 350 },
	Pickup = { Car = "StreetPickup", Value = 450 },
}
local COOLDOWN = 8 -- seconds between two jacks by the same player
local REACH = 20 -- studs from the thief to a traffic car's spot (TrafficClient offers JACK within 16; our copy of them lags)
local ROAD_SLACK = 6 -- studs beyond a road graph edge's width a traffic car's spot may be (lane changes at junctions)
local ROAD_SNAP = 3 -- a traffic car's spot must be this close above or below a City.Roads surface
local EMPTY_LIFE = 120 -- seconds a jacked car may stand empty before it goes
local BREAKIN_HOLD = 3
local BREAKIN_RANGE = 10 -- the Break in prompt's reach
local BREAKIN_SLACK = 6 -- extra studs allowed here for lag
local HOLD_KEEP = 3 -- seconds past BREAKIN_HOLD a finished hold still counts (then it's stale)
local PARKED_BACK = 300 -- seconds before a parked car that was taken is back in its stall
local ALARM_CHANCE = 0.35
local ALARM_TIME = 8
local DEFAULT_PAINT = Color3.fromRGB(190, 190, 196)
-- Short street furniture a car mustn't appear on (a car on a hydrant gets flung): VehicleService's list.
local SOLID_PROPS = { Hydrant = true, TrashCan = true, Bench = true, NewsBox = true }

local lastJack = {} -- [player] = os.clock() of their last jack
local jackedCar = {} -- [player] = their current jacked car
local parked = {} -- list of { model, kind, home (its CarPark), ground (bottom centre CFrame), size, paint, spot, hiddenAt }
local awayFolder -- ServerStorage folder holding the parked cars that were taken
local rng = Random.new()
local notify, carjacked, refused

local function finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function finiteVector(v)
	return finite(v.X) and finite(v.Y) and finite(v.Z)
end

-- A colour from a client: a Color3 whose channels are real numbers, clamped to 0-1.
local function cleanColor(c)
	if typeof(c) ~= "Color3" or not (finite(c.R) and finite(c.G) and finite(c.B)) then
		return DEFAULT_PAINT
	end
	return Color3.new(math.clamp(c.R, 0, 1), math.clamp(c.G, 0, 1), math.clamp(c.B, 0, 1))
end

-- Tell the thief a traffic jack didn't happen (with a toast when there's something to say), so their
-- client lets go of the traffic car and offers JACK again.
local function refuse(player, key)
	if key then
		notify:FireClient(player, key)
	end
	refused:FireClient(player)
end

-- Can this player take a car right now? Their humanoid and root part, or nil. When sitting down (in a
-- car) is all that's in the way, the third result is true, so the caller can say "get out first".
local function thiefBody(player)
	if player:GetAttribute("Side") ~= "Civilian" or player:GetAttribute("InHome") == true then
		return nil
	end
	local t = Workspace:GetServerTimeNow()
	if (player:GetAttribute("StunnedUntil") or 0) > t or (player:GetAttribute("KnockedUntil") or 0) > t then
		return nil -- tasered or knocked over
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return nil
	end
	if hum.SeatPart then
		return nil, nil, true
	end
	return hum, root
end

-- "Get out of your car first": at most one toast every 3 s per player. The RateLimit key is shared with
-- CarBoostService and ImpactService, so trying all three at once still gives one toast.
local function getOutFirst(player)
	if RateLimit.Allow(player, "GetOutFirstToast", 1 / 3, 1) then
		notify:FireClient(player, "GetOutFirst")
	end
end

-- One jack every COOLDOWN seconds (a toast says so when it's too soon).
local function ready(player)
	local last = lastJack[player]
	if last and os.clock() - last < COOLDOWN then
		notify:FireClient(player, "JackCooldown")
		return false
	end
	return true
end

-- Within ROAD_SLACK studs of a road graph edge's edge (flat)? The road graph's nodes sit at y = 0.
local function nearRoad(pos)
	local p = Vector3.new(pos.X, 0, pos.Z)
	local nodes = RoadGraph.Nodes
	for i, a in ipairs(nodes) do
		for j in pairs(RoadGraph.Edges[i] or {}) do
			if i < j and nodes[j] then
				local ab = nodes[j] - a
				local len2 = ab:Dot(ab)
				local t = len2 > 0 and math.clamp((p - a):Dot(ab) / len2, 0, 1) or 0
				if (p - (a + ab * t)).Magnitude <= RoadGraph.Width(i, j) / 2 + ROAD_SLACK then
					return true
				end
			end
		end
	end
	return false
end

-- The road surface right under a traffic car's spot (its pivot sits on the road), or nil when there's no
-- City.Roads surface within ROAD_SNAP studs above or below it (a roof, a lawn, mid-air, inside a house).
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
local function roadHeight(pos)
	local city = Workspace:FindFirstChild("City")
	local roads = city and city:FindFirstChild("Roads")
	if not roads then
		return nil
	end
	groundParams.FilterDescendantsInstances = { roads }
	local hit = Workspace:Raycast(pos + Vector3.new(0, ROAD_SNAP, 0), Vector3.new(0, -2 * ROAD_SNAP, 0), groundParams)
	return hit and hit.Position.Y or nil
end

-- Everything in the world a car can't appear inside (a traffic car's spot comes from a client).
local function solidFolders()
	local list = {}
	local city = Workspace:FindFirstChild("City")
	for _, name in ipairs({ "Buildings", "Art", "Landmarks", "Walls" }) do
		local f = city and city:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, name in ipairs({ "Homes", "Dealerships", "Shops", "Heists", "Activities" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	return list
end

-- Room for a car of `size` (X, Z) standing on `ground`? Other cars and other people always block it (the
-- thief stands beside it; their old jacked car is about to go anyway). `solid`: the world too, like
-- VehicleService's spawn check: anything solid standing more than 0.8 above the road, and short street
-- furniture (triggers, kerbs and road paint don't count). A parked car's stall is known to be free of it.
local clearParams = OverlapParams.new()
clearParams.FilterType = Enum.RaycastFilterType.Include
local function roomFor(ground, size, thief, oldCar, solid)
	-- From 0.6 to 4.6 studs above the road.
	local box = ground * CFrame.new(0, 2.6, 0)
	local extent = Vector3.new(size.X + 0.4, 4, size.Z + 0.4)
	local list = {}
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		table.insert(list, vehicles)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= thief and p.Character then
			table.insert(list, p.Character)
		end
	end
	clearParams.FilterDescendantsInstances = list
	for _, part in ipairs(Workspace:GetPartBoundsInBox(box, extent, clearParams)) do
		if not (oldCar and part:IsDescendantOf(oldCar)) then
			return false
		end
	end
	if solid then
		clearParams.FilterDescendantsInstances = solidFolders()
		for _, part in ipairs(Workspace:GetPartBoundsInBox(box, extent, clearParams)) do
			local top = part.Position.Y + part.Size.Y / 2
			local prop = part.Parent and SOLID_PROPS[part.Parent.Name]
			if part.CanCollide and part.CollisionGroup ~= "Props" and (prop or top > ground.Y + 0.8 or part.Size.Y > 3) then
				return false
			end
		end
	end
	return true
end

-- Can the thief see `target` from `from`? No taking a car through a wall or a floor: only a solid part at
-- least 4 studs across in two directions blocks. People, cars, parked cars, triggers (not solid), poles
-- and posts, and small props you could reach over don't.
local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.IgnoreWater = true
local function inView(from, target)
	local list = {}
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		table.insert(list, vehicles)
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, rec in ipairs(parked) do
		table.insert(list, rec.model)
	end
	for _ = 1, 8 do
		sightParams.FilterDescendantsInstances = list
		local hit = Workspace:Raycast(from, target - from, sightParams)
		if not hit then
			return true
		end
		local part = hit.Instance
		if part:IsA("Terrain") then
			return false
		end
		local s = part.Size
		local middle = s.X + s.Y + s.Z - math.max(s.X, s.Y, s.Z) - math.min(s.X, s.Y, s.Z) -- its second-longest side
		if part.CanCollide and middle >= 4 then
			return false
		end
		table.insert(list, part) -- look past it
	end
	return true
end

-- +1 star (reason "carjack": no bounty), only for someone with no stars yet (see the header).
local function report(player)
	if HeatService.GetHeat(player) <= 0 then
		HeatService.Add(player, 1, "carjack") -- the driver (or the alarm) calls the cops
	end
end

-- Build the jacked car standing on `ground` (bottom centre on the road, facing its heading) and sit the
-- thief in it. `body`: a parked car's copy to wear (nil: a fresh traffic body painted `paint`).
-- Returns the car, or nil and a Notify key for the thief (nil key: nothing worth saying).
local function spawnJacked(player, hum, info, ground, paint, body, solid)
	local ok, car = pcall(CarBuilder.Build, info.Car, { Paint = paint, Body = body })
	if not ok or not car or not car.PrimaryPart then
		warn("[CarjackService] couldn't build " .. info.Car .. ": " .. tostring(car))
		return nil
	end
	local old = jackedCar[player]
	if old and not old.Parent then
		old = nil
	end
	if not roomFor(ground, car.PrimaryPart.Size, player, old, solid) then
		car:Destroy()
		return nil, "JackBlocked"
	end
	if old then
		CarBoostService.Remove(old) -- one jacked car each
	end
	car.Name = "JackedCar"
	-- Nobody's car: no owner's Drive prompt, no crewmate's Ride prompt (the thief gets back in with GET IN).
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	-- A hair above its resting height, so it settles onto its springs.
	car:PivotTo(ground * CFrame.new(0, (car:GetAttribute("RideHeight") or 2.4) + 0.2, 0))
	car.Parent = Workspace.Vehicles
	car.PrimaryPart:SetNetworkOwner(nil)
	jackedCar[player] = car
	lastJack[player] = os.clock()
	CarBoostService.Track(car, player, info.Value, { Life = EMPTY_LIFE, From = ground.Position })
	local seat = car:FindFirstChild("DriverSeat")
	if seat then
		seat:Sit(hum)
	end
	-- Off the street or out of a car park, it counts for the goal chain (no XP: a joyride, not a job).
	-- Own thread, so nothing there can stop the stars and the Carjacked message that follow.
	task.spawn(function()
		require(ServerScriptService.Services.ProgressService).Event(player, "Carjack", 1)
	end)
	return car
end

------------------------------------------------------------------ moving traffic

local function onRequest(player, kind, cf, color)
	if not RateLimit.Allow(player, "Carjack", 1, 2) then
		return
	end
	local info = type(kind) == "string" and KINDS[kind]
	if not info or typeof(cf) ~= "CFrame" or not finiteVector(cf.Position) or not finiteVector(cf.LookVector) then
		return -- (only a broken or hacked client sends these)
	end
	-- From here on every refusal is answered.
	local hum, root, seated = thiefBody(player)
	if seated then
		getOutFirst(player) -- (InteractClient only offers JACK on foot: this is a race with sitting down)
	end
	if not hum or not ready(player) then
		return refuse(player)
	end
	local pos = cf.Position
	-- Only the heading counts (the car stands level on the road).
	local look = cf.LookVector * Vector3.new(1, 0, 1)
	local roadY = roadHeight(pos)
	if not roadY or look.Magnitude < 0.3 or (pos - root.Position).Magnitude > REACH or #RoadGraph.Nodes == 0
		or not nearRoad(pos) then
		return refuse(player)
	end
	local at = Vector3.new(pos.X, roadY, pos.Z)
	if not inView(root.Position, at + Vector3.new(0, 3, 0)) then
		return refuse(player, "JackBlocked")
	end
	local car, why = spawnJacked(player, hum, info, CFrame.lookAt(at, at + look.Unit), cleanColor(color), nil, true)
	if not car then
		return refuse(player, why)
	end
	report(player)
	carjacked:FireClient(player, { Kind = kind, Value = info.Value, Alarm = false, Parked = false,
		Sellable = car:GetAttribute("JackSellable") ~= false })
end

------------------------------------------------------------------ parked cars

-- The parts Restyle painted on a parked car (its body panels).
local function isPainted(d)
	return d:IsA("BasePart") and (d.Name == "Body" or (d:IsA("MeshPart") and d.Size.Magnitude > 8 and d.Name ~= "Wheels"))
end

local function paintOf(model)
	for _, d in ipairs(model:GetDescendants()) do
		if isPainted(d) then
			return d.Color
		end
	end
	return DEFAULT_PAINT
end

local function breakIn(rec, player, began)
	if rec.hiddenAt or not began then
		return
	end
	local held = os.clock() - began
	if held < BREAKIN_HOLD - 0.4 or held > BREAKIN_HOLD + HOLD_KEEP then
		return -- not held long enough, or an old hold saved up for later
	end
	local hum, root, seated = thiefBody(player)
	if seated then
		getOutFirst(player) -- (InteractClient hides Break in from anyone seated: a hold begun just before sitting)
		return
	end
	if not hum or (root.Position - rec.spot.WorldPosition).Magnitude > BREAKIN_RANGE + BREAKIN_SLACK or not ready(player) then
		return
	end
	if not inView(root.Position, rec.spot.WorldPosition) then
		notify:FireClient(player, "JackBlocked")
		return
	end
	local info = KINDS[rec.kind]
	-- The thief drives off in this very car: a copy wearing its colours (painted parts marked BodyPaint, so a
	-- Spray & Go respray still works), while the parked one hides.
	local body = rec.model:Clone()
	for _, d in ipairs(body:GetDescendants()) do
		if d.Name == "BreakInSpot" then
			d:Destroy()
		elseif isPainted(d) then
			d:SetAttribute("BodyPaint", true)
		end
	end
	local car, why = spawnJacked(player, hum, info, rec.ground, rec.paint, body, false)
	if not car then
		if why then
			notify:FireClient(player, why)
		end
		return
	end
	rec.hiddenAt = os.clock()
	rec.model.Parent = awayFolder
	local alarm = rng:NextNumber() < ALARM_CHANCE
	if alarm then
		car:SetAttribute("CarAlarmUntil", Workspace:GetServerTimeNow() + ALARM_TIME)
		report(player)
	end
	carjacked:FireClient(player, { Kind = rec.kind, Value = info.Value, Alarm = alarm, Parked = true,
		Sellable = car:GetAttribute("JackSellable") ~= false })
end

local function everyPart()
	return true
end

-- A Break in prompt at a parked car's driver's door (front is -Z, the driver on the left, -X).
local function setupParked(model)
	local lo, hi = CarBuilder.Bounds(model, everyPart)
	local anchor, biggest
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and (not biggest or d.Size.Magnitude > biggest) then
			anchor, biggest = d, d.Size.Magnitude
		end
	end
	if not lo or not anchor then
		return false
	end
	local pivot = model:GetPivot()
	local rec = {
		model = model, kind = model.Name, home = model.Parent, paint = paintOf(model),
		ground = pivot * CFrame.new((lo.X + hi.X) / 2, lo.Y, (lo.Z + hi.Z) / 2),
		size = hi - lo,
	}
	local spot = Instance.new("Attachment")
	spot.Name = "BreakInSpot"
	spot.CFrame = anchor.CFrame:ToObjectSpace(pivot * CFrame.new(lo.X - 0.3, math.min(lo.Y + 2.6, hi.Y), (lo.Z + hi.Z) / 2))
	spot.Parent = anchor
	rec.spot = spot
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickLockPrompt" -- a crime prompt: starting the hold ends passive mode (CombatService)
	prompt.ActionText = "Break in"
	prompt.ObjectText = model.Name .. " ($" .. KINDS[model.Name].Value .. ")"
	prompt.HoldDuration = BREAKIN_HOLD
	prompt.MaxActivationDistance = BREAKIN_RANGE
	prompt.RequiresLineOfSight = false -- (the parked body itself would hide it; breakIn checks the view)
	CollectionService:AddTag(prompt, "BreakInPrompt")
	prompt.Parent = spot
	-- The hold is timed here (a client can't skip it).
	local holdStart = setmetatable({}, { __mode = "k" })
	prompt.PromptButtonHoldBegan:Connect(function(p)
		holdStart[p] = os.clock()
	end)
	-- Let go early: that hold is void. A finished hold still counts, whichever event arrives first.
	prompt.PromptButtonHoldEnded:Connect(function(p)
		local b = holdStart[p]
		if b and os.clock() - b < BREAKIN_HOLD - 0.4 then
			holdStart[p] = nil
		end
	end)
	prompt.Triggered:Connect(function(p)
		local began = holdStart[p]
		holdStart[p] = nil
		breakIn(rec, p, began)
	end)
	table.insert(parked, rec)
	return true
end

local function setupCarParks()
	local city = Workspace:WaitForChild("City", 30)
	local art = city and city:WaitForChild("Art", 10)
	local fill = art and art:WaitForChild("BlockFill", 10)
	if not fill then
		warn("[CarjackService] no Workspace.City.Art.BlockFill: parked cars can't be broken into")
		return
	end
	local count = 0
	for _, lot in ipairs(fill:GetDescendants()) do
		if lot:IsA("Model") and lot.Name == "CarPark" then
			for _, m in ipairs(lot:GetChildren()) do
				if m:IsA("Model") and KINDS[m.Name] and setupParked(m) then
					count += 1
				end
			end
		end
	end
	if RunService:IsStudio() then
		print(string.format("[CarjackService] %d parked cars can be broken into", count))
	end
end

-- Taken parked cars come back after PARKED_BACK seconds, once nobody and no car is in their stall.
local function restoreParked()
	local now = os.clock()
	for _, rec in ipairs(parked) do
		if rec.hiddenAt and now - rec.hiddenAt >= PARKED_BACK and rec.home.Parent and roomFor(rec.ground, rec.size) then
			rec.hiddenAt = nil
			rec.model.Parent = rec.home
		end
	end
end

function CarjackService.Init()
	notify = Remotes.Event("Notify")
	carjacked = Remotes.Event("Carjacked")
	refused = Remotes.Event("CarjackRefused")
	Remotes.Event("RequestCarjack").OnServerEvent:Connect(onRequest)
	awayFolder = Instance.new("Folder")
	awayFolder.Name = "TakenParkedCars"
	awayFolder.Parent = ServerStorage
	Players.PlayerRemoving:Connect(function(p)
		lastJack[p] = nil
		jackedCar[p] = nil -- (CarBoostService removes the car itself when its thief leaves)
	end)
	task.spawn(function()
		local ok, err = pcall(setupCarParks)
		if not ok then
			warn("[CarjackService] car parks: " .. tostring(err))
		end
		while true do
			task.wait(10)
			local ok2, err2 = pcall(restoreParked)
			if not ok2 then
				warn("[CarjackService] " .. tostring(err2))
			end
		end
	end)
end

return CarjackService
