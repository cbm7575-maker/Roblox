-- ArrestService (ModuleScript, ServerScriptService.Services.ArrestService)
-- Police tools and arrests. Only WANTED citizens (heat > 0) can be tased, spiked or arrested, so
-- cops can't grief innocent players.
--   Taser  (RequestTaser): cop on foot, target on foot within 32 studs with line of sight -> 3 s stun.
--   Cuffs  (CuffPrompt on each character, CuffDriver on each car seat; hold 1.5 s, only cops see them):
--          target stunned, or on foot and slow (< 10 studs/s), or in a car going < 5 studs/s.
--   Spikes (RequestSpike): drops a strip 28 studs ahead; 2 charges, +1 every 30 s; a car carrying a
--          wanted player (driver or passenger) that crosses it gets flat tyres for 12 s (tougher cars
--          recover sooner). The check sweeps each car's path since the last check, so fast cars can't
--          skip over a strip. ArrestService.PlaceSpike(cf, width, owner, lifetime) lays one for
--          other services (roadblocks: no owner).
--   Arrest: robber loses the bag; cop earns $500 per star + 25% of the bag; robber goes to prison.
--   Dying while wanted (reset, falling off the map) counts as an arrest: the bounty goes to the nearest
--          cop who saw them in the last 20 s and is within 300 studs (if any).
--   Patrol pay: $80 per minute to cops who moved 150+ studs that minute or were near a wanted player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Shop = require(ReplicatedStorage.Shared.Config.Shop)
local Police = require(ReplicatedStorage.Shared.Config.Police)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local HeatService = require(ServerScriptService.Services.HeatService)

local ArrestService = {}

local TASER_RANGE = 32
local STUN_SECONDS = 3
local CUFF_RANGE = 12
local SPIKE_AHEAD = 28
local SPIKE_LIFETIME = 25
local SPIKE_RECHARGE = 30
local FLAT_SECONDS = 12
local PATROL_PAY = Police.PatrolPay

local notify, feed, caught, bountyEarned, taserFx
local spikes = {} -- { part, owner, hit = {[car]=true} }
local stunRestore = {} -- [humanoid] = { WalkSpeed, JumpHeight }

local function now()
	return Workspace:GetServerTimeNow()
end

local function aliveRoot(player)
	local char = player and player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart"), hum
end

local function isCop(player)
	return player:GetAttribute("Side") == "Cop"
end

local function isWanted(player)
	return player:GetAttribute("Side") == "Civilian" and (player:GetAttribute("Heat") or 0) > 0
end

local function prison()
	return require(ServerScriptService.Services.PrisonService)
end

-- The arrest itself: bag gone, heat cleared, bounty to the cop (if any), off to prison.
local function jail(target, cop)
	local heat = HeatService.GetHeat(target)
	local bounty = HeatService.Bounty(target)
	EconomyService.TakeCarried(target, "arrested")
	HeatService.Clear(target, "arrested")
	if cop then
		if cop:GetAttribute("Pass_VIP") then
			bounty = math.floor(bounty * (1 + Shop.VIPCashBonus))
		end
		EconomyService.AddCash(cop, bounty, "bounty")
		require(game:GetService("ServerScriptService").Services.ProgressService).Event(cop, "Arrest", heat)
		require(ServerScriptService.Services.Telemetry).Custom(cop, "Arrest", heat)
		cop:SetAttribute("Arrests", (cop:GetAttribute("Arrests") or 0) + 1)
		bountyEarned:FireClient(cop, { Amount = bounty, Name = target.DisplayName })
	end
	target:SetAttribute("TimesCaught", (target:GetAttribute("TimesCaught") or 0) + 1)
	caught:FireClient(target, { Heat = heat, By = cop and cop.DisplayName or "Police" })
	feed:FireAllClients("Arrest", { Name = target.DisplayName, Cop = cop and cop.DisplayName or "an AI patrol" })
	prison().Jail(target, heat)
end

function ArrestService.Arrest(target, cop)
	local root, hum = aliveRoot(target)
	if not root or not isWanted(target) then
		return
	end
	-- Out of the car first.
	local seat = hum.SeatPart
	if seat then
		local sw = seat:FindFirstChild("SeatWeld")
		if sw then
			sw:Destroy()
		end
		hum.Sit = false
	end
	jail(target, cop)
end

-- A wanted player's character died or vanished (reset, fell off the map): that's an arrest too, or
-- resetting would shake the cops and keep the bag. The bounty goes to the nearest cop who saw them
-- in the last 20 s and is within 300 studs.
local leaving = setmetatable({}, { __mode = "k" }) -- [player] = true once they're leaving the game

local function caughtDown(player, where)
	if leaving[player] or player.Parent ~= Players or not isWanted(player) then
		return
	end
	where = where or player:GetAttribute("LastSeen")
	local best, bestD
	for _, cop in ipairs(Players:GetPlayers()) do
		local copRoot = isCop(cop) and aliveRoot(cop)
		if copRoot and HeatService.SeenAgo(player, cop) <= Police.DeathBountyMemory then
			local d = typeof(where) == "Vector3" and (copRoot.Position - where).Magnitude or math.huge
			if d <= Police.DeathBountyRange and (not bestD or d < bestD) then
				best, bestD = cop, d
			end
		end
	end
	jail(player, best)
end

-- Can `cop` cuff `target` right now?
local function canCuff(cop, target)
	if not isCop(cop) or not isWanted(target) or cop == target then
		return false
	end
	local copRoot = aliveRoot(cop)
	local root, hum = aliveRoot(target)
	if not copRoot or not root or (copRoot.Position - root.Position).Magnitude > CUFF_RANGE then
		return false
	end
	if (target:GetAttribute("StunnedUntil") or 0) > now() then
		return true
	end
	if hum.SeatPart then
		local car = hum.SeatPart.Parent
		local chassis = car and car.PrimaryPart
		return chassis ~= nil and chassis.AssemblyLinearVelocity.Magnitude < 5
	end
	return root.AssemblyLinearVelocity.Magnitude < 10
end

local function addCuffPrompt(parent, name, objectText)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = "Cuff"
	prompt.ObjectText = objectText
	prompt.HoldDuration = 1.5
	prompt.MaxActivationDistance = CUFF_RANGE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.Q
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.Parent = parent
	return prompt
end

local function onCharacter(player, char)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
	if hum and hum:IsA("Humanoid") then
		hum.Died:Connect(function()
			local r = char:FindFirstChild("HumanoidRootPart")
			caughtDown(player, r and r:IsA("BasePart") and r.Position or nil)
		end)
	end
	local prompt = addCuffPrompt(root, "CuffPrompt", player.DisplayName)
	prompt.Triggered:Connect(function(cop)
		if canCuff(cop, player) then
			ArrestService.Arrest(player, cop)
		end
	end)
end

local function onCar(car)
	local seat = car:WaitForChild("DriverSeat", 5)
	if not seat then
		return
	end
	local prompt = addCuffPrompt(seat, "CuffDriver", "Driver")
	prompt.Triggered:Connect(function(cop)
		local occupant = seat.Occupant
		local target = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
		if target and canCuff(cop, target) then
			ArrestService.Arrest(target, cop)
		end
	end)
end

local function stun(target)
	local _, hum = aliveRoot(target)
	if not hum or hum.SeatPart then
		return
	end
	target:SetAttribute("StunnedUntil", now() + STUN_SECONDS)
	if not stunRestore[hum] then
		stunRestore[hum] = { hum.WalkSpeed, hum.JumpHeight }
	end
	hum.WalkSpeed = 0
	hum.JumpHeight = 0
	task.delay(STUN_SECONDS, function()
		local saved = stunRestore[hum]
		if saved and hum.Parent and (target:GetAttribute("StunnedUntil") or 0) <= now() + 0.05 then
			hum.WalkSpeed, hum.JumpHeight = saved[1], saved[2]
			stunRestore[hum] = nil
		end
	end)
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude

local function onTaser(cop, target)
	if typeof(target) ~= "Instance" or not target:IsA("Player") then
		return
	end
	if not RateLimit.Allow(cop, "Taser", 0.4, 1) then
		return
	end
	if not isCop(cop) or not isWanted(target) then
		return
	end
	local copRoot, copHum = aliveRoot(cop)
	local root, hum = aliveRoot(target)
	if not copRoot or not root or copHum.SeatPart or hum.SeatPart then
		return
	end
	local offset = root.Position - copRoot.Position
	if offset.Magnitude > TASER_RANGE then
		return
	end
	losParams.FilterDescendantsInstances = { cop.Character, target.Character, Workspace:FindFirstChild("Vehicles") }
	if Workspace:Raycast(copRoot.Position, offset, losParams) then
		return
	end
	stun(target)
	taserFx:FireAllClients(cop, target)
	require(game:GetService("ServerScriptService").Services.ProgressService).Event(cop, "TaserHit")
end

local function groundBelow(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local city = Workspace:FindFirstChild("City")
	params.FilterDescendantsInstances = { city and city:FindFirstChild("Roads"), city and city:FindFirstChild("Ground") }
	return Workspace:Raycast(pos + Vector3.new(0, 15, 0), Vector3.new(0, -40, 0), params)
end

local spikeFolder

-- Lay a spike strip: `cf` is its centre on the road, facing along the road; `width` across it.
-- owner (a cop Player) may be nil (roadblocks). The strip lasts `lifetime` seconds (or until destroyed).
function ArrestService.PlaceSpike(cf, width, owner, lifetime)
	if not spikeFolder or not spikeFolder.Parent then
		spikeFolder = Workspace:FindFirstChild("Spikes") or Instance.new("Folder")
		spikeFolder.Name = "Spikes"
		spikeFolder.Parent = Workspace
	end
	local strip = Instance.new("Part")
	strip.Name = "SpikeStrip"
	strip.Anchored = true
	strip.CanCollide = false
	strip.CanQuery = false
	strip.CanTouch = false
	strip.Size = Vector3.new(width, 0.4, 3)
	strip.CFrame = cf
	strip.Color = Color3.fromRGB(40, 40, 48)
	strip.Material = Enum.Material.DiamondPlate
	local teeth = Instance.new("Part")
	teeth.Name = "Teeth"
	teeth.Anchored = true
	teeth.CanCollide = false
	teeth.CanQuery = false
	teeth.CanTouch = false
	teeth.Size = Vector3.new(width - 0.4, 0.3, 0.6)
	teeth.CFrame = cf * CFrame.new(0, 0.3, 0)
	teeth.Color = Color3.fromRGB(34, 225, 255)
	teeth.Material = Enum.Material.Neon
	teeth.Parent = strip
	strip.Parent = spikeFolder
	table.insert(spikes, { part = strip, owner = owner, hit = setmetatable({}, { __mode = "k" }), expires = os.clock() + (lifetime or SPIKE_LIFETIME) })
	return strip
end

local function onSpike(cop)
	if not RateLimit.Allow(cop, "Spike", 1, 1) or not isCop(cop) then
		return
	end
	local charges = cop:GetAttribute("SpikeCharges") or 0
	if charges < 1 then
		notify:FireClient(cop, "NoSpikes")
		return
	end
	local root, hum = aliveRoot(cop)
	if not root then
		return
	end
	local basis = hum.SeatPart and hum.SeatPart.Parent.PrimaryPart or root
	local look = basis.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, -1)
	local hit = groundBelow(basis.Position + look * SPIKE_AHEAD)
	if not hit then
		return
	end
	cop:SetAttribute("SpikeCharges", charges - 1)
	-- At most 2 strips per cop at a time: the oldest goes first.
	local mine = {}
	for i, s in ipairs(spikes) do
		if s.owner == cop then
			table.insert(mine, i)
		end
	end
	if #mine >= 2 then
		local old = table.remove(spikes, mine[1])
		old.part:Destroy()
	end
	local at = hit.Position + Vector3.new(0, 0.2, 0)
	ArrestService.PlaceSpike(CFrame.lookAt(at, at + look), 20, cop, SPIKE_LIFETIME)
end

-- Does the segment a -> b (in the box's own space) touch a box of half-size hx, hy, hz at the origin?
-- (Slab test; pure maths, so fast cars that jump past a strip between checks still hit it.)
function ArrestService._SegmentHitsBox(a, b, hx, hy, hz)
	local t0, t1 = 0, 1
	for axis = 1, 3 do
		local p0 = axis == 1 and a.X or axis == 2 and a.Y or a.Z
		local p1 = axis == 1 and b.X or axis == 2 and b.Y or b.Z
		local h = axis == 1 and hx or axis == 2 and hy or hz
		local d = p1 - p0
		if math.abs(d) < 1e-6 then
			if math.abs(p0) > h then
				return false
			end
		else
			local u0, u1 = (-h - p0) / d, (h - p0) / d
			if u0 > u1 then
				u0, u1 = u1, u0
			end
			t0 = math.max(t0, u0)
			t1 = math.min(t1, u1)
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end

local lastSpikePos = setmetatable({}, { __mode = "k" }) -- [car] = { pos, clock }
local seatsOf = setmetatable({}, { __mode = "k" }) -- [car] = { seats }

-- Wanted players riding in a car (driver or passengers).
local function wantedRiders(car)
	local seats = seatsOf[car]
	if not seats then
		seats = {}
		for _, d in ipairs(car:GetChildren()) do
			if d:IsA("Seat") or d:IsA("VehicleSeat") then
				table.insert(seats, d)
			end
		end
		seatsOf[car] = seats
	end
	local list
	for _, seat in ipairs(seats) do
		local occupant = seat.Occupant
		local p = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
		if p and isWanted(p) then
			list = list or {}
			table.insert(list, p)
		end
	end
	return list
end

-- Check cars carrying wanted players against every strip, 10 times a second.
local function spikeTick()
	local t = os.clock()
	for i = #spikes, 1, -1 do
		local s = spikes[i]
		if t > s.expires or not s.part.Parent then
			s.part:Destroy()
			table.remove(spikes, i)
		end
	end
	if #spikes == 0 then
		table.clear(lastSpikePos)
		return
	end
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return
	end
	for _, car in ipairs(folder:GetChildren()) do
		local chassis = car.PrimaryPart
		if chassis and not car:GetAttribute("Police") then
			local pos = chassis.Position
			local prev = lastSpikePos[car]
			lastSpikePos[car] = { pos = pos, clock = t }
			-- The path since the last check (just this spot after a gap or a teleport).
			local from = pos
			if prev and t - prev.clock < 0.5 and (pos - prev.pos).Magnitude < 150 then
				from = prev.pos
			end
			local riders = wantedRiders(car)
			if riders then
				for _, s in ipairs(spikes) do
					if not s.hit[car] then
						local cf = s.part.CFrame
						local hx = s.part.Size.X / 2 + chassis.Size.X / 2
						local hz = 1.5 + chassis.Size.Z / 2
						if ArrestService._SegmentHitsBox(cf:PointToObjectSpace(from), cf:PointToObjectSpace(pos), hx, 6, hz) then
							s.hit[car] = true
							if s.owner and s.owner.Parent then
								require(game:GetService("ServerScriptService").Services.ProgressService).Event(s.owner, "SpikeHit")
							end
							local toughness = car:GetAttribute("Toughness") or 2
							local seconds = FLAT_SECONDS - (toughness - 1) * 1.5
							car:SetAttribute("FlatUntil", now() + seconds)
							for _, p in ipairs(riders) do
								notify:FireClient(p, "TiresPopped")
							end
						end
					end
				end
			end
		end
	end
end

function ArrestService.Init()
	notify = Remotes.Event("Notify")
	feed = Remotes.Event("Feed")
	caught = Remotes.Event("Caught")
	bountyEarned = Remotes.Event("BountyEarned")
	taserFx = Remotes.Event("TaserFx")
	Remotes.Event("RequestTaser").OnServerEvent:Connect(onTaser)
	Remotes.Event("RequestSpike").OnServerEvent:Connect(onSpike)

	local function onPlayer(player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		-- Backup for deaths the server never saw as Died (the character just went away while wanted).
		-- Our own arrests clear the heat before the respawn, so they never land here.
		player.CharacterRemoving:Connect(function(char)
			local r = char:FindFirstChild("HumanoidRootPart")
			local where = r and r:IsA("BasePart") and r.Position or nil
			task.defer(caughtDown, player, where)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
		player:GetAttributeChangedSignal("Side"):Connect(function()
			if isCop(player) then
				player:SetAttribute("SpikeCharges", 2)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		leaving[p] = true
	end)

	local vehicles = Workspace:WaitForChild("Vehicles")
	vehicles.ChildAdded:Connect(function(car)
		task.spawn(onCar, car)
	end)
	for _, car in ipairs(vehicles:GetChildren()) do
		task.spawn(onCar, car)
	end

	task.spawn(function()
		while true do
			task.wait(0.1)
			local ok, err = pcall(spikeTick)
			if not ok then
				warn("[ArrestService] " .. tostring(err))
			end
		end
	end)
	-- Spike recharge (every 30 s) and patrol pay (every minute, for cops actually on patrol: moved
	-- 150+ studs that minute or were near a wanted player). Sampled every 5 s.
	local moved = {} -- [cop] = studs this minute
	local nearWanted = {} -- [cop] = true
	local lastPos = {} -- [cop] = Vector3
	Players.PlayerRemoving:Connect(function(p)
		moved[p], nearWanted[p], lastPos[p] = nil, nil, nil
	end)
	local function sample()
		local wantedRoots = {}
		for _, q in ipairs(Players:GetPlayers()) do
			local r = isWanted(q) and aliveRoot(q)
			if r then
				table.insert(wantedRoots, r.Position)
			end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			local root = isCop(p) and aliveRoot(p)
			if root then
				local pos = root.Position
				if lastPos[p] then
					moved[p] = (moved[p] or 0) + math.min((pos - lastPos[p]).Magnitude, 400)
				end
				lastPos[p] = pos
				if not nearWanted[p] then
					for _, w in ipairs(wantedRoots) do
						if (w - pos).Magnitude <= Police.PatrolPayNearWanted then
							nearWanted[p] = true
							break
						end
					end
				end
			elseif not isCop(p) then
				moved[p], nearWanted[p], lastPos[p] = nil, nil, nil
			end
		end
	end
	task.spawn(function()
		local elapsed = 0
		while true do
			task.wait(5)
			elapsed += 5
			local ok, err = pcall(function()
				sample()
				if elapsed % SPIKE_RECHARGE == 0 then
					for _, p in ipairs(Players:GetPlayers()) do
						if isCop(p) then
							local max = p:GetAttribute("SpikeMax") or 2
							p:SetAttribute("SpikeCharges", math.min(max, (p:GetAttribute("SpikeCharges") or 0) + 1))
						end
					end
				end
				if elapsed % 60 == 0 then
					for _, p in ipairs(Players:GetPlayers()) do
						if isCop(p) and ((moved[p] or 0) >= Police.PatrolPayMinMove or nearWanted[p]) then
							EconomyService.AddCash(p, PATROL_PAY, "patrol")
							require(game:GetService("ServerScriptService").Services.ProgressService).Event(p, "PatrolMinute")
						end
					end
					table.clear(moved)
					table.clear(nearWanted)
				end
			end)
			if not ok then
				warn("[ArrestService] " .. tostring(err))
			end
		end
	end)
end

return ArrestService
