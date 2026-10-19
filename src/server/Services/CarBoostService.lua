-- CarBoostService (ModuleScript, ServerScriptService.Services.CarBoostService)
-- The Car Boost job (GTA 6's car theft, kid-safe: parked cars only, never other players' cars).
--   * Up to 3 "hot cars" wait parked beside roads around the city, each with a street value.
--   * Citizens pick the lock (hold 4 s, server-timed) -> the car is theirs to drive, +1 heat.
--   * 40% carry a GPS tracker: 20 s after the theft the cops get a ping (LastSeen follows the car).
--   * Deliver it to the Chop Shop (Docks) while no cop can see you -> its value goes in your bag.
--   * Unclaimed hot cars leave after 6 minutes; stolen ones 5 minutes after being abandoned.
--   * The thief can get out and back in (Drive prompt, shown only to the thief by VehicleVisuals).
--   * Not while tased (StunnedUntil): no lock picking, no getting in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local CarBuilder = require(ServerStorage.Tools.CarBuilder)
local HeatService = require(ServerScriptService.Services.HeatService)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local CarBoostService = {}

local MAX_HOT = 3
local SPAWN_EVERY = 45 -- seconds between top-ups
local PICK_HOLD = 4
local TRACKER_CHANCE = 0.4
local TRACKER_DELAY = 20
local UNCLAIMED_LIFE = 360
local ABANDONED_LIFE = 300
local MODELS = {
	{ Id = "Flamingo", Value = { 2500, 3200 } },
	{ Id = "NightHeron", Value = { 3000, 3800 } },
	{ Id = "Voltline", Value = { 3500, 4500 } },
	{ Id = "Sandpiper", Value = { 2000, 2800 } },
	{ Id = "SolanaGT", Value = { 5000, 6500 } },
}

local hot = {} -- list of { car, value, tracker, thief, spawnedAt, emptySince }
local rng = Random.new()
local startedAt = os.clock()
local lastTopUp = 0
local notify, feed

local function stunned(player)
	return (player:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow()
end

local function chopPad()
	local m = Workspace.Spawns:FindFirstChild("ChopShop")
	return m and m.PrimaryPart
end

local function removeHot(h)
	for i, x in ipairs(hot) do
		if x == h then
			table.remove(hot, i)
			break
		end
	end
	if h.car.Parent then
		h.car:Destroy()
	end
end

-- A parking spot: a random road point, pushed to the roadside and facing along the road.
local function parkingSpot()
	local nodes = RoadGraph.Nodes
	for _ = 1, 20 do
		local i = rng:NextInteger(1, #nodes)
		local neighbours = {}
		for j in pairs(RoadGraph.Edges[i] or {}) do
			table.insert(neighbours, j)
		end
		if #neighbours > 0 then
			local a = nodes[i]
			local b = nodes[neighbours[rng:NextInteger(1, #neighbours)]]
			local along = b - a
			if along.Magnitude > 80 then
				local dir = along.Unit
				local p = a + dir * rng:NextNumber(30, along.Magnitude - 30)
				local side = Vector3.new(-dir.Z, 0, dir.X) * 12
				local pos = p + side + Vector3.new(0, 3.2, 0)
				-- not too close to anyone
				local ok = true
				for _, pl in ipairs(Players:GetPlayers()) do
					local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
					if r and (r.Position - pos).Magnitude < 60 then
						ok = false
					end
				end
				if ok and math.abs(pos.X) < 1900 and math.abs(pos.Z) < 1900 then
					return CFrame.lookAt(pos, pos + dir)
				end
			end
		end
	end
	return nil
end

local function onSeat(h, seat)
	local car = h.car
	local occupant = seat.Occupant
	local player = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
	if player and h.thief == player then
		car:SetAttribute("DriverUserId", player.UserId)
		car.PrimaryPart:SetNetworkOwner(player)
		h.emptySince = nil
	elseif occupant then
		-- Only the thief drives it.
		local sw = seat:FindFirstChild("SeatWeld")
		if sw then
			sw:Destroy()
		end
	else
		car:SetAttribute("DriverUserId", nil)
		h.emptySince = os.clock()
		task.delay(1.5, function()
			if car.Parent and seat.Occupant == nil then
				car.PrimaryPart:SetNetworkOwner(nil)
			end
		end)
	end
end

local function spawnHot()
	local cf = parkingSpot()
	if not cf then
		return
	end
	local model = MODELS[rng:NextInteger(1, #MODELS)]
	local car = CarBuilder.Build(model.Id)
	car.Name = "HotCar"
	local value = rng:NextInteger(model.Value[1], model.Value[2])
	value = math.floor(value / 50) * 50
	car:SetAttribute("HotCar", true)
	car:SetAttribute("HotValue", value)
	car:PivotTo(cf)
	local seat = car:FindFirstChild("DriverSeat")
	-- The Drive prompt stays: after the theft it lets the thief back in (clients show it only to the
	-- ThiefUserId; before the theft nobody sees it).
	local drive = seat:FindFirstChild("DrivePrompt")
	local pick = Instance.new("ProximityPrompt")
	pick.Name = "PickLockPrompt"
	pick.ActionText = "Pick lock"
	pick.ObjectText = "Hot car ($" .. value .. ")"
	pick.HoldDuration = PICK_HOLD
	pick.MaxActivationDistance = 12
	pick.RequiresLineOfSight = false
	pick.Parent = seat
	-- A sign over the car so players can spot hot cars from the street.
	local sign = Instance.new("BillboardGui")
	sign.Name = "HotSign"
	sign.Size = UDim2.fromOffset(180, 36)
	sign.StudsOffset = Vector3.new(0, 7, 0)
	sign.MaxDistance = 400
	sign.AlwaysOnTop = true
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 138, 61)
	text.TextStrokeTransparency = 0.2
	text.Text = "HOT CAR $" .. value
	text.Parent = sign
	sign.Parent = car.PrimaryPart
	car.Parent = Workspace.Vehicles
	car.PrimaryPart:SetNetworkOwner(nil)
	local h = { car = car, value = value, tracker = rng:NextNumber() < TRACKER_CHANCE, spawnedAt = os.clock() }
	table.insert(hot, h)

	local holdStart = {}
	pick.PromptButtonHoldBegan:Connect(function(p)
		holdStart[p] = os.clock()
	end)
	pick.Triggered:Connect(function(p)
		local began = holdStart[p]
		holdStart[p] = nil
		if h.thief or p:GetAttribute("Side") ~= "Civilian" or not began or os.clock() - began < PICK_HOLD - 0.4 or stunned(p) then
			return
		end
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if not hum or hum.Health <= 0 or hum.SeatPart or not root or (root.Position - seat.Position).Magnitude > 16 then
			return
		end
		h.thief = p
		car:SetAttribute("ThiefUserId", p.UserId)
		pick.Enabled = false
		local s = car.PrimaryPart:FindFirstChild("HotSign")
		if s then
			s:Destroy()
		end
		HeatService.Add(p, 1, "carboost")
		seat:Sit(hum)
		notify:FireClient(p, "CarBoosted")
		if h.tracker then
			task.delay(TRACKER_DELAY, function()
				if car.Parent and h.thief == p and (p:GetAttribute("Heat") or 0) > 0 then
					p:SetAttribute("LastSeen", car.PrimaryPart.Position)
					notify:FireClient(p, "TrackerPing")
					feed:FireAllClients("TrackerPing", { Model = car:GetAttribute("DisplayName") or "car" })
				end
			end)
		end
	end)
	if drive then
		drive.Triggered:Connect(function(p)
			if p ~= h.thief or seat.Occupant or p:GetAttribute("Side") ~= "Civilian" or stunned(p) then
				return
			end
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and not hum.SeatPart and root and (root.Position - seat.Position).Magnitude <= 20 then
				seat:Sit(hum)
			end
		end)
	end
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onSeat(h, seat)
	end)
end

local function tick()
	local now = os.clock()
	local pad = chopPad()
	for i = #hot, 1, -1 do
		local h = hot[i]
		local car = h.car
		local chassis = car.PrimaryPart
		if not car.Parent or not chassis or chassis.Position.Y < 0.2 then
			removeHot(h)
		elseif not h.thief and now - h.spawnedAt > UNCLAIMED_LIFE then
			removeHot(h)
		elseif h.thief and (h.thief.Parent ~= Players or (h.emptySince and now - h.emptySince > ABANDONED_LIFE)) then
			removeHot(h)
		elseif h.thief and pad then
			-- Delivered?
			local rel = pad.CFrame:PointToObjectSpace(chassis.Position)
			if math.abs(rel.X) <= pad.Size.X / 2 and math.abs(rel.Z) <= pad.Size.Z / 2 and rel.Y < 12 then
				local p = h.thief
				local seat = car:FindFirstChild("DriverSeat")
				local driving = seat and seat.Occupant and seat.Occupant.Parent == p.Character
				if driving and not p:GetAttribute("HeatSpotted") then
					local fits = EconomyService.AddCarried(p, h.value, "carboost")
					require(game:GetService("ServerScriptService").Services.ProgressService).Event(p, "CarBoost")
					p:SetAttribute("CarsBoosted", (p:GetAttribute("CarsBoosted") or 0) + 1)
					Remotes.Event("HeistResult"):FireClient(p, { Type = "CarBoost", Payout = fits, BagFull = fits < h.value })
					feed:FireAllClients("CarDelivered", { Model = car:GetAttribute("DisplayName") or "car" })
					local sw = seat:FindFirstChild("SeatWeld")
					if sw then
						sw:Destroy()
					end
					local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
					if hum then
						hum.Sit = false
					end
					removeHot(h)
				elseif driving then
					notify:FireClient(p, "ShakeCopsFirst")
				end
			end
		end
	end
	local unclaimed = 0
	for _, h in ipairs(hot) do
		if not h.thief then
			unclaimed += 1
		end
	end
	-- Fill up right after the server starts, then top up one car at most every SPAWN_EVERY seconds.
	local warmingUp = now - startedAt < 10
	if unclaimed < MAX_HOT and #RoadGraph.Nodes > 0 and (warmingUp or now - lastTopUp >= SPAWN_EVERY) then
		lastTopUp = now
		spawnHot()
	end
end

function CarBoostService.Init()
	notify = Remotes.Event("Notify")
	feed = Remotes.Event("Feed")
	task.spawn(function()
		task.wait(5) -- let the road graph build first
		while true do
			local ok, err = pcall(tick)
			if not ok then
				warn("[CarBoost] " .. tostring(err))
			end
			task.wait(1)
		end
	end)
end

return CarBoostService
