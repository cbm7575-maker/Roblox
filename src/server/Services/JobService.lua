-- JobService (ModuleScript, ServerScriptService.Services.JobService)
-- Honest work for citizens: the taxi shift (delivery jobs reuse the same flow later).
--   * Drive your own car onto the Taxi Stand (Workspace.Activities.TaxiStand) and press E.
--   * A passenger waits beside a road 250-800 studs away. Stop next to them (within 18 studs, under
--     6 studs/s) and they hop in.
--   * Drive them to their stop (500-1400 studs away) and stop there: paid Base + PerStud x route length,
--     plus a Tip if you beat the estimate (Config.Activities.Jobs; about $500 a minute). The next fare
--     comes automatically.
--   * The shift ends if you leave your car for 10 s, become wanted, stop being a civilian (switch to
--     cop, get arrested), or press END SHIFT.
-- Courier shifts (Courier Depot at Marina Row, built here if missing) use the same flow with packages:
-- pick one up from a shop, deliver it (Activities.Jobs.Courier rates).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Activities = require(ReplicatedStorage.Shared.Config.Activities)
local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local JobService = {}

local PICKUP_MIN, PICKUP_MAX = 250, 800
local DROP_MIN, DROP_MAX = 500, 1400
local STOP_RADIUS, DROP_RADIUS = 18, 22
local STOP_SPEED = 6
local LEAVE_GRACE = 10
local NAMES = { "Rosa", "Marcus", "Priya", "Tony", "Lena", "Jamal", "Sofia", "Ben", "Aisha", "Carlos", "Mia", "Dev" }
local SHOPS = { "Sunny Side Donuts", "Palmetto Pets", "Taco Wave", "Coco's Coconuts", "Shell Shocked Seafood",
	"Glow-Up Nails", "Deke's Bait & Tackle", "Frozen Flamingo", "Seashell Suds", "Barnacle Bob's" }
local DEPOT_POS = Vector3.new(560, 0, 640)

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

-- A roadside spot between minD and maxD studs from `from`.
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
				local dir = (nodes[neighbours[rng:NextInteger(1, #neighbours)]] - n)
				if dir.Magnitude > 1 then
					dir = dir.Unit
					local side = Vector3.new(-dir.Z, 0, dir.X)
					return n + dir * 25 + side * 26
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
	end
	jobEvent:FireClient(player, "Pickup", { Pos = spot, Name = s.name, Kind = s.kind })
end

local function startShift(player, kind)
	kind = kind == "Courier" and "Courier" or "Taxi"
	if not RateLimit.Allow(player, "JobStart", 0.5, 1) or shifts[player] then
		return
	end
	if player:GetAttribute("Side") ~= "Civilian" or (player:GetAttribute("Heat") or 0) > 0 then
		return
	end
	local car = ownCar(player)
	if not car then
		Remotes.Event("Notify"):FireClient(player, "RaceNeedCar")
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
		elseif player:GetAttribute("Side") ~= "Civilian" then
			endShift(player, "Side") -- switched to cop (the 10 s out-of-car grace must not carry a shift over)
		elseif (player:GetAttribute("Heat") or 0) > 0 then
			endShift(player, "Wanted")
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
						local rates = Activities.Jobs[courier and "Courier" or "Taxi"]
						local tip = took <= s.est and rates.Tip or 0
						local pay = math.floor(rates.Base + s.length * rates.PerStud) + tip
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
	-- Courier Depot (built here if the place doesn't have one).
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
		depot.Color = Color3.fromRGB(255, 138, 61)
		depot.Material = Enum.Material.Neon
		depot.Transparency = 0.6
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(220, 40)
		gui.StudsOffset = Vector3.new(0, 12, 0)
		gui.MaxDistance = 700
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = depot.Color
		label.TextStrokeTransparency = 0.3
		label.Text = "COURIER DEPOT"
		label.Parent = gui
		gui.Parent = depot
		depot.Parent = acts
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
