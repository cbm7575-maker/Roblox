-- JobService (ModuleScript, ServerScriptService.Services.JobService)
-- Honest work for citizens: the taxi shift (delivery jobs reuse the same flow later).
--   * Drive your own car onto the Taxi Stand (Workspace.Activities.TaxiStand) and press E.
--   * A passenger waits beside a road 250-800 studs away. Stop inside their ring (within 32 studs, under
--     6 studs/s) and they hop in.
--   * Drive them to their stop (500-1400 studs away) and stop there: paid $150 + 35 cents a stud, and a
--     $100 tip if you beat the estimate. The next fare comes automatically.
--   * The shift ends if you leave your car for 10 s, become wanted, change sides, or press END SHIFT.
-- Courier shifts (Courier Depot at Marina Row, built here if missing) use the same flow with packages:
-- pick one up from a shop, deliver it: $120 + 40 cents a stud, +$120 for a fast delivery.
-- The depot's look follows Look 3.0 (Tools.Look3): the CourierDepot trigger is invisible over an asphalt
-- yard with a painted yellow loading bay; on its east side stands a corrugated-metal parcel shed (two
-- roll-up doors with yellow guard posts, a hazard-striped apron, a canopy, a dark sign board with white
-- letters, pallets of parcels). Its lamps only light after dark (tag "NightLamp") and the orange strip
-- under the sign only glows after dark (tag "NightNeon"): SkyClient switches them. Everything stays inside
-- the depot's reserved lot (Restyle.RUNTIME_LOTS: 23 studs either side of DEPOT_POS); only the shed is solid.
-- Pickup and drop spots are on the kerb beside a road (outside its lanes, on solid ground, not water).
-- Free-roam citizens only, not wanted and not on a phone mission; a refusal says why (Notify).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Textures = require(ReplicatedStorage.Shared.Config.Textures)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local JobService = {}

local PICKUP_MIN, PICKUP_MAX = 250, 800
local DROP_MIN, DROP_MAX = 500, 1400
-- Both are the ring ActivityClient draws round the spot (showJobMarker: 64 studs across). They were 18
-- and 22: a car stopped inside the ring but in the far lane, or a little short of the beam, was never
-- counted and nothing said why. (The next spot is always 250+ studs off, so the wider ring can't fire early.)
local STOP_RADIUS, DROP_RADIUS = 32, 32
local STOP_SPEED = 6
local LEAVE_GRACE = 10
local NAMES = { "Rosa", "Marcus", "Priya", "Tony", "Lena", "Jamal", "Sofia", "Ben", "Aisha", "Carlos", "Mia", "Dev" }
local SHOPS = { "Sunny Side Donuts", "Palmetto Pets", "Taco Wave", "Coco's Coconuts", "Shell Shocked Seafood",
	"Glow-Up Nails", "Deke's Bait & Tackle", "Frozen Flamingo", "Seashell Suds", "Barnacle Bob's" }
local DEPOT_POS = Vector3.new(560, 0, 640)
-- Depot look (Look 3.0 colours).
local DEPOT_ACCENT = Color3.fromRGB(255, 138, 61) -- the depot's one brand colour
local DARK = Color3.fromRGB(58, 60, 66) -- frames and trims; also unlit neon (SkyClient's day colour)
local LAMP_DAY = Color3.fromRGB(226, 226, 220) -- a lamp lens by day (SkyClient's NightLamp day colour)
local LAMP_WARM = Color3.fromRGB(255, 226, 190)
local SAFETY = Color3.fromRGB(240, 196, 44) -- painted lines and guard posts

local shifts = {} -- [player] = { stage, passenger, pickup, drop, pickedAt, est, name, outOfCarSince }
local jobEvent
local rng = Random.new()

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function ownCar(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local car = seat and seat.Parent
	if car and seat.Name == "DriverSeat" and car:GetAttribute("OwnerUserId") == player.UserId and car.PrimaryPart then
		return car
	end
	return nil
end

-- Is there solid, dry ground at this kerbside spot? (Not water, not the road, not on top of something.)
local groundParams = RaycastParams.new()
groundParams.IgnoreWater = false
local function solidGround(spot)
	local ignore = {}
	for _, name in ipairs({ "NPCs", "Vehicles", "Events" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	groundParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(spot + Vector3.new(0, 20, 0), Vector3.new(0, -40, 0), groundParams)
	if not hit or hit.Material == Enum.Material.Water or hit.Position.Y > 2 or hit.Position.Y < -1 then
		return false
	end
	local roads = Workspace:FindFirstChild("City") and Workspace.City:FindFirstChild("Roads")
	return not (roads and hit.Instance:IsDescendantOf(roads))
end

-- A roadside spot between minD and maxD studs from `from`: part-way along a road from a node (clear of
-- the crossing road at a junction) and just past its kerb, whatever the road's width.
local function roadsideSpot(from, minD, maxD)
	local nodes = RoadGraph.Nodes
	for _ = 1, 40 do
		local i = rng:NextInteger(1, #nodes)
		local n = nodes[i]
		local d = (n - flat(from)).Magnitude
		if d >= minD and d <= maxD and math.abs(n.X) < 1850 and math.abs(n.Z) < 1850 then
			local neighbours = {}
			for j in pairs(RoadGraph.Edges[i] or {}) do
				table.insert(neighbours, j)
			end
			if #neighbours > 0 then
				local j = neighbours[rng:NextInteger(1, #neighbours)]
				local dir = (nodes[j] - n)
				if dir.Magnitude > 1 then
					local along = math.min(dir.Magnitude * 0.5, 60)
					dir = dir.Unit
					local side = Vector3.new(-dir.Z, 0, dir.X)
					local spot = n + dir * along + side * (RoadGraph.Width(i, j) / 2 + 6)
					if solidGround(spot) then
						return spot
					end
				end
			end
		end
	end
	return nil
end

local function spawnPassenger(pos, name)
	local ok, model = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		local skin = { Color3.fromRGB(255, 220, 185), Color3.fromRGB(205, 160, 120), Color3.fromRGB(140, 95, 65), Color3.fromRGB(90, 60, 45) }
		local c = skin[rng:NextInteger(1, #skin)]
		desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = c, c, c
		desc.LeftLegColor, desc.RightLegColor, desc.TorsoColor = c, c, c
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return nil
	end
	model.Name = "Passenger"
	local root = model:FindFirstChild("HumanoidRootPart")
	root.Anchored = true
	model:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0)))
	local hum = model:FindFirstChildOfClass("Humanoid")
	hum.DisplayName = name
	hum.NameDisplayDistance = 200
	local folder = Workspace:FindFirstChild("NPCs") or Instance.new("Folder")
	folder.Name = "NPCs"
	folder.Parent = Workspace
	model.Parent = folder
	return model
end

local function endShift(player, reason)
	local s = shifts[player]
	if not s then
		return
	end
	shifts[player] = nil
	if s.passenger and s.passenger.Parent then
		s.passenger:Destroy()
	end
	player:SetAttribute("JobKind", nil)
	jobEvent:FireClient(player, "Ended", { Reason = reason, Fares = s.fares or 0, Earned = s.earned or 0 })
end

local function nextFare(player, s, from)
	local spot = roadsideSpot(from, PICKUP_MIN, PICKUP_MAX)
	if not spot then
		return endShift(player, "NoFares")
	end
	s.stage = "pickup"
	s.pickup = spot
	if s.kind == "Courier" then
		s.name = SHOPS[rng:NextInteger(1, #SHOPS)]
	else
		s.name = NAMES[rng:NextInteger(1, #NAMES)]
		s.passenger = spawnPassenger(spot, s.name)
		-- Making the passenger takes a moment. If the shift ended meanwhile (END SHIFT, wanted, left the
		-- game), stop here: a "Pickup" sent now brought END SHIFT and the ring back for a shift that is
		-- gone (the button then did nothing), and the passenger stood by the road for good.
		if shifts[player] ~= s then
			if s.passenger then
				s.passenger:Destroy()
				s.passenger = nil
			end
			return
		end
	end
	jobEvent:FireClient(player, "Pickup", { Pos = spot, Name = s.name, Kind = s.kind })
end

local function startShift(player, kind)
	kind = kind == "Courier" and "Courier" or "Taxi"
	if not RateLimit.Allow(player, "JobStart", 0.5, 1) or shifts[player] then
		return
	end
	local notify = Remotes.Event("Notify")
	if player:GetAttribute("Side") ~= "Civilian" then
		notify:FireClient(player, "ActivityCivOnly")
		return
	elseif (player:GetAttribute("Heat") or 0) > 0 then
		notify:FireClient(player, "ActivityWanted")
		return
	elseif player:GetAttribute("Mission") or player:GetAttribute("RacingId") or player:GetAttribute("BigScore") then
		-- One thing at a time (MissionService and RaceService refuse the same way).
		notify:FireClient(player, "MissionBusy")
		return
	end
	local car = ownCar(player)
	if not car then
		notify:FireClient(player, "JobNeedCar")
		return
	end
	local s = { fares = 0, earned = 0, kind = kind }
	shifts[player] = s
	player:SetAttribute("JobKind", kind)
	nextFare(player, s, car.PrimaryPart.Position)
end

local function tick()
	local t = os.clock()
	for player, s in pairs(shifts) do
		if player.Parent ~= Players then
			shifts[player] = nil
			if s.passenger then
				s.passenger:Destroy()
			end
		elseif (player:GetAttribute("Heat") or 0) > 0 then
			endShift(player, "Wanted")
		elseif player:GetAttribute("Side") ~= "Civilian" then
			-- Shifts are for citizens (startShift). Someone who picked POLICE mid-shift kept the job line
			-- and END SHIFT, and was paid fares from the patrol car once they sat in it.
			endShift(player, "Player")
		else
			local car = ownCar(player)
			if not car then
				s.outOfCarSince = s.outOfCarSince or t
				if t - s.outOfCarSince > LEAVE_GRACE then
					endShift(player, "LeftCar")
				end
			else
				s.outOfCarSince = nil
				local chassis = car.PrimaryPart
				local speed = chassis.AssemblyLinearVelocity.Magnitude
				if s.stage == "pickup" then
					if (flat(chassis.Position) - flat(s.pickup)).Magnitude < STOP_RADIUS and speed < STOP_SPEED then
						if s.passenger then
							s.passenger:Destroy()
							s.passenger = nil
						end
						local drop = roadsideSpot(chassis.Position, DROP_MIN, DROP_MAX)
						if not drop then
							return endShift(player, "NoFares")
						end
						local path = RoadGraph.Path(chassis.Position, drop)
						local length = 0
						if path then
							for i = 2, #path do
								length += (path[i] - path[i - 1]).Magnitude
							end
						else
							length = (flat(drop) - flat(chassis.Position)).Magnitude * 1.4
						end
						s.stage = "dropoff"
						s.drop = drop
						s.length = length
						s.pickedAt = t
						s.est = length / 80 + 10
						jobEvent:FireClient(player, "Dropoff", { Pos = drop, Name = s.name, Est = s.est, Kind = s.kind })
					end
				elseif s.stage == "dropoff" then
					if (flat(chassis.Position) - flat(s.drop)).Magnitude < DROP_RADIUS and speed < STOP_SPEED then
						local took = t - s.pickedAt
						local courier = s.kind == "Courier"
						local tip = took <= s.est and (courier and 120 or 100) or 0
						local pay = math.floor((courier and 120 or 150) + s.length * (courier and 0.4 or 0.35)) + tip
						EconomyService.AddCash(player, pay, courier and "courier" or "taxi")
						require(game:GetService("ServerScriptService").Services.ProgressService).Event(player, "TaxiFare")
						s.fares += 1
						s.earned += pay
						player:SetAttribute("Fares", (player:GetAttribute("Fares") or 0) + 1)
						jobEvent:FireClient(player, "Paid", { Pay = pay, Tip = tip, Name = s.name, Took = took, Kind = s.kind })
						s.stage = "waiting"
						task.delay(2, function()
							if shifts[player] == s then
								local c = ownCar(player)
								nextFare(player, s, c and c.PrimaryPart.Position or s.drop)
							end
						end)
					end
				end
			end
		end
	end
end

------------------------------------------------------------------ courier depot look (Look 3.0)

-- One dressing part. Only `solid` ones collide, stop rays and cast shadows; the rest is paint, trim and
-- props you pass through.
local function dress(parent, name, size, cf, color, material, solid)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.CastShadow = solid == true
	p.Parent = parent
	return p
end

local function texture(p, face, image, u, v, color)
	local t = Instance.new("Texture")
	t.Face = face
	t.Texture = image
	t.StudsPerTileU = u
	t.StudsPerTileV = v
	if color then
		t.Color3 = color
	end
	t.Parent = p
	return t
end

-- A lamp lens: pale by day, lit after dark (tag "NightLamp", SkyClient). With a `range` it gets a
-- SpotLight out of `face`, off until SkyClient switches it on.
local function depotLamp(p, face, range)
	p.Material = Enum.Material.SmoothPlastic
	p.Color = LAMP_DAY
	p:SetAttribute("LampColor", LAMP_WARM)
	CollectionService:AddTag(p, "NightLamp")
	if range then
		local light = Instance.new("SpotLight")
		light.Name = "Lamp"
		light.Face = face
		light.Angle = 100
		light.Range = range
		light.Brightness = 2
		light.Color = LAMP_WARM
		light.Shadows = false
		light.Enabled = false
		light.Parent = p
	end
	return p
end

-- The yard and parcel shed round the CourierDepot trigger. Local frame: origin DEPOT_POS on the ground,
-- the shed on the +X side with its doors toward the bay. The trigger is 26 x 26, the reserved lot 46 x 46.
local function buildDepotYard(acts)
	local f = CFrame.new(DEPOT_POS.X, 0, DEPOT_POS.Z)
	local function at(x, y, z)
		return f * CFrame.new(x, y, z)
	end
	-- Turns a wall-mounted part so its width runs along Z and its Back face looks at the bay (-X).
	local FACING_BAY = CFrame.Angles(0, -math.pi / 2, 0)
	local m = Instance.new("Model")
	m.Name = "CourierDepotYard"

	-- Yard: asphalt laid just above the ground (cars still drive on the ground under it), a yellow bay box
	-- round the trigger, a stencil, and a hazard-striped apron along the shed.
	dress(m, "Yard", Vector3.new(44, 0.1, 44), at(0, 0, 0), Color3.fromRGB(62, 62, 66), Enum.Material.Asphalt)
	for _, x in ipairs({ -13, 13 }) do
		dress(m, "BayLine", Vector3.new(0.4, 0.05, 26.4), at(x, 0.07, 0), SAFETY)
	end
	for _, z in ipairs({ -13, 13 }) do
		dress(m, "BayLine", Vector3.new(26.4, 0.05, 0.4), at(0, 0.07, z), SAFETY)
	end
	local stencil = dress(m, "Stencil", Vector3.new(16, 0.05, 3), at(-9, 0.07, 0) * FACING_BAY, SAFETY)
	stencil.Transparency = 1
	local paint = Instance.new("SurfaceGui")
	paint.Face = Enum.NormalId.Top
	paint.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	paint.PixelsPerStud = 20
	paint.LightInfluence = 1 -- paint, not a light
	paint.MaxDistance = 250
	local word = Instance.new("TextLabel")
	word.Size = UDim2.fromScale(1, 1)
	word.BackgroundTransparency = 1
	word.Font = Enum.Font.GothamBold
	word.TextScaled = true
	word.TextColor3 = SAFETY
	word.Text = "COURIER LOADING"
	word.Parent = paint
	paint.Parent = stencil
	-- (The stripe texture repeats along the part's X, here turned to run along the shed.)
	local apron = dress(m, "HazardApron", Vector3.new(40, 0.05, 1.2), at(14, 0.07, 0) * FACING_BAY, SAFETY)
	texture(apron, Enum.NormalId.Top, Textures.Zebra, 2, 1.2, Color3.fromRGB(34, 34, 36))

	-- The shed: corrugated metal on a dark roof cap, two roof units.
	local shed = dress(m, "Shed", Vector3.new(7, 16, 42), at(18.5, 8, 0), Color3.fromRGB(190, 192, 190), Enum.Material.Metal, true)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
		texture(shed, face, Textures.Corrugated, 2, 16)
	end
	dress(m, "RoofTrim", Vector3.new(7.6, 0.8, 42.6), at(18.5, 15.7, 0), DARK, Enum.Material.Metal)
	dress(m, "RoofUnit", Vector3.new(3, 1.6, 4), at(19, 16.9, -11), Color3.fromRGB(150, 152, 156), Enum.Material.Metal)
	dress(m, "RoofVent", Vector3.new(1.6, 1.2, 1.6), at(18, 16.7, 12), Color3.fromRGB(150, 152, 156), Enum.Material.Metal)

	-- Two roll-up doors on the bay side, dark headers over them, yellow guard posts either side.
	for _, z in ipairs({ -10, 10 }) do
		local door = dress(m, "RollUpDoor", Vector3.new(10, 11, 0.3), at(14.85, 5.5, z) * FACING_BAY, Color3.fromRGB(150, 154, 160), Enum.Material.Metal)
		texture(door, Enum.NormalId.Back, Textures.RollUpDoor, 10, 11)
		dress(m, "DoorHeader", Vector3.new(11.2, 0.6, 0.5), at(14.75, 11.3, z) * FACING_BAY, DARK, Enum.Material.Metal)
		for _, side in ipairs({ -1, 1 }) do
			dress(m, "DoorGuard", Vector3.new(0.7, 3.6, 0.7), at(14.1, 1.8, z + side * 5.7), SAFETY, Enum.Material.Metal)
		end
	end
	-- Staff door (north end) with a lamp over it; office window (south end). Dark frames behind both.
	dress(m, "DoorFrame", Vector3.new(4, 7.8, 0.15), at(14.93, 3.9, 18.4) * FACING_BAY, DARK, Enum.Material.Metal)
	dress(m, "StaffDoor", Vector3.new(3.4, 7.4, 0.25), at(14.875, 3.7, 18.4) * FACING_BAY, Color3.fromRGB(70, 74, 80), Enum.Material.Metal)
	depotLamp(dress(m, "DoorLamp", Vector3.new(0.9, 0.45, 0.45), at(14.775, 8.4, 18.4), LAMP_DAY))
	dress(m, "WindowFrame", Vector3.new(4.1, 3.5, 0.15), at(14.93, 5.2, -18.4) * FACING_BAY, DARK, Enum.Material.Metal)
	local window = dress(m, "OfficeWindow", Vector3.new(3.6, 3, 0.2), at(14.9, 5.2, -18.4) * FACING_BAY, Color3.fromRGB(52, 58, 66), Enum.Material.Glass)
	window.Reflectance = 0.1

	-- Canopy over the two doors (hung on two tie rods) with lamps under it.
	local canopy = dress(m, "Canopy", Vector3.new(4, 0.4, 32), at(13, 12.2, 0), DARK, Enum.Material.Metal)
	canopy.CastShadow = true
	for _, z in ipairs({ -12, 12 }) do
		local a, b = f * Vector3.new(15, 15, z), f * Vector3.new(11.2, 12.4, z)
		dress(m, "TieRod", Vector3.new(0.15, 0.15, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), DARK, Enum.Material.Metal)
	end
	for _, z in ipairs({ -10, 10 }) do
		depotLamp(dress(m, "CanopyLamp", Vector3.new(1.2, 0.2, 1.2), at(12.8, 11.9, z), LAMP_DAY), Enum.NormalId.Bottom, 30)
	end

	-- Sign over the canopy: a dark board fixed flat to the wall (from the canopy up to the roof trim), white
	-- letters, an orange strip under its front edge that glows at night.
	local board = dress(m, "SignBoard", Vector3.new(0.3, 2.7, 22), at(14.85, 13.95, 0), Color3.fromRGB(26, 28, 32), Enum.Material.Metal)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Left -- toward the bay (-X)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	gui.Brightness = 1
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(0.92, 0.68)
	title.Position = UDim2.fromScale(0.04, 0.1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Oswald
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(245, 245, 240)
	title.Text = "COURIER DEPOT"
	title.Parent = gui
	local rule = Instance.new("Frame")
	rule.BorderSizePixel = 0
	rule.BackgroundColor3 = DEPOT_ACCENT
	rule.Size = UDim2.fromScale(0.2, 0.07)
	rule.Position = UDim2.fromScale(0.4, 0.83)
	rule.Parent = gui
	gui.Parent = board
	local strip = dress(m, "SignNeon", Vector3.new(0.2, 0.2, 22), at(14.75, 12.5, 0), DARK, Enum.Material.Metal)
	strip:SetAttribute("NeonColor", DEPOT_ACCENT)
	CollectionService:AddTag(strip, "NightNeon")

	-- Wall floodlights at the shed's top corners, aimed at the bay.
	for _, z in ipairs({ -19.6, 19.6 }) do
		local pos = f * Vector3.new(14, 14.6, z)
		local aim = CFrame.lookAt(pos, f * Vector3.new(0, 0, z * 0.3))
		dress(m, "FloodBracket", Vector3.new(1.2, 0.3, 0.3), at(14.6, 14.6, z), DARK, Enum.Material.Metal)
		dress(m, "FloodHousing", Vector3.new(1.6, 1.1, 0.9), aim, DARK, Enum.Material.Metal)
		depotLamp(dress(m, "Flood", Vector3.new(1.4, 0.9, 0.12), aim * CFrame.new(0, 0, -0.5), LAMP_DAY), Enum.NormalId.Front, 50)
	end

	-- Pallets of parcels by the office end.
	local CARDBOARD = Color3.fromRGB(176, 140, 98)
	for i, p in ipairs({ { 9.4, -18 }, { 5.2, -18.6 } }) do
		local base = at(p[1], 0, p[2])
		dress(m, "Pallet", Vector3.new(3.2, 0.5, 3.2), base * CFrame.new(0, 0.3, 0), Color3.fromRGB(150, 112, 74), Enum.Material.WoodPlanks)
		dress(m, "Parcel", Vector3.new(2.8, 1.6, 2.8), base * CFrame.new(0, 1.35, 0), CARDBOARD, Enum.Material.Cardboard)
		if i == 1 then
			dress(m, "Parcel", Vector3.new(1.8, 1.2, 2), base * CFrame.new(-0.3, 2.75, 0.2) * CFrame.Angles(0, 0.3, 0),
				CARDBOARD:Lerp(Color3.new(1, 1, 1), 0.12), Enum.Material.Cardboard)
		end
	end
	m.Parent = acts
end

function JobService.Init()
	jobEvent = Remotes.Event("JobEvent")
	local stand = Workspace:WaitForChild("Activities"):WaitForChild("TaxiStand", 10)
	if stand then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TaxiPrompt"
		prompt.ActionText = "Start taxi shift"
		prompt.ObjectText = "Taxi Stand"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 30
		prompt.RequiresLineOfSight = false
		prompt.Parent = stand
		prompt.Triggered:Connect(function(player)
			startShift(player, "Taxi")
		end)
	end
	-- Courier Depot (built here if the place doesn't have one): an invisible trigger, the yard under it
	-- shows where to park.
	local acts = Workspace:FindFirstChild("Activities")
	local depot = acts and acts:FindFirstChild("CourierDepot")
	if acts and not depot then
		depot = Instance.new("Part")
		depot.Name = "CourierDepot"
		depot.Anchored = true
		depot.CanCollide = false
		depot.CanQuery = false
		depot.Size = Vector3.new(26, 0.2, 26)
		depot.CFrame = CFrame.new(DEPOT_POS.X, 0.24, DEPOT_POS.Z)
		depot.Color = DEPOT_ACCENT
		depot.Material = Enum.Material.SmoothPlastic
		depot.Transparency = 1
		depot.CastShadow = false
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(220, 40)
		gui.StudsOffset = Vector3.new(0, 12, 0)
		gui.MaxDistance = 700
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Oswald
		label.TextScaled = true
		label.TextColor3 = DEPOT_ACCENT
		label.TextStrokeTransparency = 0.3
		label.Text = "COURIER DEPOT"
		label.Parent = gui
		gui.Parent = depot
		depot.Parent = acts
		-- The look is dressing only: if it fails, the depot still works.
		local ok, err = pcall(buildDepotYard, acts)
		if not ok then
			warn("[JobService] courier depot yard: " .. tostring(err))
		end
	end
	if depot then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CourierPrompt"
		prompt.ActionText = "Start courier shift"
		prompt.ObjectText = "Courier Depot"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 30
		prompt.RequiresLineOfSight = false
		prompt.Parent = depot
		prompt.Triggered:Connect(function(player)
			startShift(player, "Courier")
		end)
	end
	Remotes.Event("RequestJob").OnServerEvent:Connect(function(player, action)
		if action == "End" and RateLimit.Allow(player, "JobEnd", 1, 1) then
			endShift(player, "Player")
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(tick)
			if not ok then
				warn("[JobService] " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		local s = shifts[p]
		if s and s.passenger then
			s.passenger:Destroy()
		end
		shifts[p] = nil
	end)
end

return JobService
