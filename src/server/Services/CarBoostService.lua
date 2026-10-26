-- CarBoostService (ModuleScript, ServerScriptService.Services.CarBoostService)
-- The Car Boost job (kid-safe car theft: parked cars only, never other players' cars).
--   * Up to 3 "hot cars" wait parked beside roads around the city, each with a street value.
--   * Citizens pick the lock (hold 4 s, server-timed) -> the car is theirs to drive, +1 heat.
--     The car gets ThiefUserId; the thief gets the player attribute BoostDelivery = true until the
--     car is delivered or gone, and BoostStolenAt (server time) on every theft, so a second theft
--     still tells the client (ObjectiveClient stamps "take it to the Chop Shop" and sets the GPS).
--   * 40% carry a GPS tracker: 20 s after the theft the cops get a ping (LastSeen follows the car).
--   * Deliver it to the Chop Shop (Docks) while no cop can see you -> its value goes in your bag.
--     Every Chop Shop sale (hot car or jacked car) is reported to ProgressService as "ChopSale".
--   * Unclaimed hot cars leave after 6 minutes; stolen ones 5 minutes after being abandoned.
--   * The thief arrested, or switching sides in any way: the job's off and the car goes at once.
--   * Carjacked street cars (CarjackService) join the same list through CarBoostService.Track: already
--     stolen (car attributes HotCar, Jacked, HotValue, ThiefUserId), so only the thief drives them and gets
--     back in with GET IN, and they go when left empty for their own time (2 minutes), or with the thief
--     as above. The Chop Shop buys them too, for their street value into the bag, but no XP, no boost
--     count and no BoostDelivery (they're a joyride first, not a job): only one per player every
--     JACK_SALE_GAP seconds, and only if taken at least JACK_MIN_TRIP studs from the Chop Shop (so a car
--     jacked outside can't be flipped on the spot; car attribute JackSellable = false on those, and
--     CarBoostService.CanSellFrom(pos) says so up front). CarBoostService.Remove(car) takes one away.
--   * Pick lock holds are timed here: a hold let go early is void, and an old one can't be kept for later.
--     Only people on foot can pick a lock (LawClient hides the prompt from anyone seated); a hold that
--     finishes while seated gets the "GetOutFirst" toast (at most one every 3 s, see getOutFirst).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
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
local JACK_SALE_GAP = 120 -- seconds between two jacked-car sales by the same player
local JACK_MIN_TRIP = 250 -- studs (flat) between where a jacked car was taken and the Chop Shop pad
local MODELS = {
	{ Id = "Flamingo", Value = { 2500, 3200 } },
	{ Id = "NightHeron", Value = { 3000, 3800 } },
	{ Id = "Voltline", Value = { 3500, 4500 } },
	{ Id = "Sandpiper", Value = { 2000, 2800 } },
	{ Id = "SolanaGT", Value = { 5000, 6500 } },
}

-- list of { car, value, tracker, thief, spawnedAt, emptySince, sideConn }, plus for carjacked cars
-- jacked = true, life (seconds empty before it goes) and from (where it was taken)
local hot = {}
local rng = Random.new()
local startedAt = os.clock()
local lastTopUp = 0
local lastWarn = {} -- [player] = os.clock() of the last warning toast at the Chop Shop
local lastJackSale = {} -- [userId] = os.clock() of their last jacked-car sale (kept across rejoins)
local notify, feed

local function chopPad()
	local m = Workspace.Spawns:FindFirstChild("ChopShop")
	return m and m.PrimaryPart
end

-- "Get out of your car first": at most one toast every 3 s per player. The RateLimit key is shared with
-- CarjackService and ImpactService, so trying all three at once still gives one toast.
local function getOutFirst(p)
	if RateLimit.Allow(p, "GetOutFirstToast", 1 / 3, 1) then
		notify:FireClient(p, "GetOutFirst")
	end
end

-- BoostDelivery = true while this player has a stolen hot car waiting to be delivered (carjacked
-- street cars don't count: they're not a job).
local function markThief(p)
	if not p or p.Parent ~= Players then
		return
	end
	local has = false
	for _, x in ipairs(hot) do
		if x.thief == p and not x.jacked then
			has = true
			break
		end
	end
	if (p:GetAttribute("BoostDelivery") == true) ~= has then
		p:SetAttribute("BoostDelivery", has or nil)
	end
end

local function removeHot(h)
	for i, x in ipairs(hot) do
		if x == h then
			table.remove(hot, i)
			break
		end
	end
	if h.sideConn then
		h.sideConn:Disconnect()
		h.sideConn = nil
	end
	if h.car.Parent then
		h.car:Destroy()
	end
	markThief(h.thief)
end

-- Arrested (Prisoner) or any other switch off Civilian: the claim ends and the car goes, so it can't be
-- climbed back into and delivered after prison.
local function watchSide(h, p)
	h.sideConn = p:GetAttributeChangedSignal("Side"):Connect(function()
		if p:GetAttribute("Side") ~= "Civilian" and table.find(hot, h) then
			removeHot(h)
		end
	end)
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
	local drive = seat:FindFirstChild("DrivePrompt")
	if drive then
		drive:Destroy()
	end
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
	text.Font = Enum.Font.Oswald
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
	-- Let go early: that hold is void. A finished hold still counts, whichever event arrives first.
	pick.PromptButtonHoldEnded:Connect(function(p)
		local b = holdStart[p]
		if b and os.clock() - b < PICK_HOLD - 0.4 then
			holdStart[p] = nil
		end
	end)
	pick.Triggered:Connect(function(p)
		local began = holdStart[p]
		holdStart[p] = nil
		local held = began and os.clock() - began
		if h.thief or p:GetAttribute("Side") ~= "Civilian" or not held or held < PICK_HOLD - 0.4 or held > PICK_HOLD + 3 then
			return
		end
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if not hum or hum.Health <= 0 or not root or (root.Position - seat.Position).Magnitude > 16 then
			return
		end
		if hum.SeatPart then
			-- Sitting in a car (a hold started just before sitting down, or lag): say so, not nothing.
			getOutFirst(p)
			return
		end
		h.thief = p
		car:SetAttribute("ThiefUserId", p.UserId)
		pick.Enabled = false
		local s = car.PrimaryPart:FindFirstChild("HotSign")
		if s then
			s:Destroy()
		end
		watchSide(h, p)
		HeatService.Add(p, 1, "carboost")
		seat:Sit(hum)
		-- ObjectiveClient sees BoostStolenAt change: it stamps where to take the car and sets the GPS
		-- (that replaces the old "CarBoosted" toast). BoostDelivery alone stays true across a second
		-- theft, so it can't be the signal.
		markThief(p)
		p:SetAttribute("BoostStolenAt", Workspace:GetServerTimeNow())
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
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		onSeat(h, seat)
	end)
end

-- A warning toast at the Chop Shop: tick runs every second, so one every 6 s is plenty.
local function warnAt(p, key, now)
	if not lastWarn[p] or now - lastWarn[p] > 6 then
		lastWarn[p] = now
		notify:FireClient(p, key)
	end
end

-- Will the Chop Shop buy a jacked car taken at `pos`? Not one taken within JACK_MIN_TRIP studs (flat) of
-- its pad. True when there's no pad or no spot to go on.
function CarBoostService.CanSellFrom(pos)
	local pad = chopPad()
	if not pad or typeof(pos) ~= "Vector3" then
		return true
	end
	return Vector3.new(pos.X - pad.Position.X, 0, pos.Z - pad.Position.Z).Magnitude >= JACK_MIN_TRIP
end

-- Why the Chop Shop won't take this carjacked car right now (a Notify key), or nil.
local function jackRefusal(h, p, now)
	if h.from and not CarBoostService.CanSellFrom(h.from) then
		return "JackTooClose"
	end
	local last = lastJackSale[p.UserId]
	if last and now - last < JACK_SALE_GAP then
		return "JackSaleCooldown"
	end
	return nil
end

-- Sold: the car's value goes in the thief's bag, the thief steps out and the car is gone.
local function deliver(h, p, seat, now)
	local car = h.car
	local fits = EconomyService.AddCarried(p, h.value, h.jacked and "carjack" or "carboost")
	if h.jacked then
		lastJackSale[p.UserId] = now
	else
		require(ServerScriptService.Services.ProgressService).Event(p, "CarBoost")
		p:SetAttribute("CarsBoosted", (p:GetAttribute("CarsBoosted") or 0) + 1)
	end
	task.spawn(function() -- the goal chain counts either kind (own thread: the sale below always finishes)
		require(ServerScriptService.Services.ProgressService).Event(p, "ChopSale", 1)
	end)
	Remotes.Event("HeistResult"):FireClient(p, {
		Type = "CarBoost", Payout = fits, BagFull = fits < h.value, Wanted = (p:GetAttribute("Heat") or 0) > 0,
	})
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
		elseif h.thief and (h.thief.Parent ~= Players or (h.emptySince and now - h.emptySince > (h.life or ABANDONED_LIFE))) then
			removeHot(h)
		elseif h.thief and pad then
			-- Delivered?
			local rel = pad.CFrame:PointToObjectSpace(chassis.Position)
			if math.abs(rel.X) <= pad.Size.X / 2 and math.abs(rel.Z) <= pad.Size.Z / 2 and rel.Y < 12 then
				local p = h.thief
				local seat = car:FindFirstChild("DriverSeat")
				local driving = seat and seat.Occupant and seat.Occupant.Parent == p.Character
				if driving then
					local refusal = (p:GetAttribute("HeatSpotted") and "ShakeCopsFirst") or (h.jacked and jackRefusal(h, p, now))
					if refusal then
						warnAt(p, refusal, now)
					else
						deliver(h, p, seat, now)
					end
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

-- A carjacked street car (CarjackService), taken by `thief` and worth `value` at the Chop Shop. Call it
-- once the car is in Workspace.Vehicles and before seating the thief. opts: Life = seconds it may stand
-- empty before it goes (default ABANDONED_LIFE), From = where it was taken (Vector3; also sets the car's
-- JackSellable attribute: false when the Chop Shop won't buy it, see CanSellFrom).
function CarBoostService.Track(car, thief, value, opts)
	opts = opts or {}
	car:SetAttribute("HotCar", true)
	car:SetAttribute("Jacked", true)
	car:SetAttribute("HotValue", value)
	car:SetAttribute("ThiefUserId", thief.UserId)
	car:SetAttribute("JackSellable", CarBoostService.CanSellFrom(opts.From))
	-- Counts as empty until the thief sits in it (so a car nobody got into still goes).
	local h = { car = car, value = value, thief = thief, jacked = true, life = opts.Life, from = opts.From,
		spawnedAt = os.clock(), emptySince = os.clock() }
	table.insert(hot, h)
	watchSide(h, thief)
	local seat = car:FindFirstChild("DriverSeat")
	if seat then
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			onSeat(h, seat)
		end)
	end
end

-- Take a car away now (CarjackService: a player's previous jacked car). Untracked cars are just destroyed.
function CarBoostService.Remove(car)
	for _, h in ipairs(hot) do
		if h.car == car then
			removeHot(h)
			return
		end
	end
	if car.Parent then
		car:Destroy()
	end
end

function CarBoostService.Init()
	notify = Remotes.Event("Notify")
	feed = Remotes.Event("Feed")
	Players.PlayerRemoving:Connect(function(p)
		lastWarn[p] = nil
	end)
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
