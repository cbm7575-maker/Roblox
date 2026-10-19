-- ArrestService (ModuleScript, ServerScriptService.Services.ArrestService)
-- Police tools and arrests. Only WANTED citizens (heat > 0) can be tased, spiked or arrested, so
-- cops can't grief innocent players.
--   Taser  (RequestTaser): cop on foot, target on foot within 32 studs with line of sight -> 3 s stun.
--   Cuffs  (CuffPrompt on each character, CuffDriver on each car seat; hold 1.5 s, only cops see them):
--          target stunned, or on foot and slow (< 10 studs/s), or in a car going < 5 studs/s.
--   Spikes (RequestSpike): drops a strip 28 studs ahead; 2 charges, +1 every 30 s; wanted drivers
--          who cross it get flat tyres for 12 s (tougher cars recover sooner).
--   Arrest: robber loses the bag; cop earns $500 per star + 25% of the bag; robber goes to prison.
--   Patrol pay: every cop earns $80 per minute on duty.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Shop = require(ReplicatedStorage.Shared.Config.Shop)
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
local PATROL_PAY = 80

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
	local folder = Workspace:FindFirstChild("Spikes") or Instance.new("Folder")
	folder.Name = "Spikes"
	folder.Parent = Workspace
	local strip = Instance.new("Part")
	strip.Name = "SpikeStrip"
	strip.Anchored = true
	strip.CanCollide = false
	strip.CanQuery = false
	strip.CanTouch = false
	strip.Size = Vector3.new(20, 0.4, 3)
	strip.CFrame = CFrame.lookAt(hit.Position + Vector3.new(0, 0.2, 0), hit.Position + Vector3.new(0, 0.2, 0) + look)
	strip.Color = Color3.fromRGB(40, 40, 48)
	strip.Material = Enum.Material.DiamondPlate
	local teeth = Instance.new("Part")
	teeth.Name = "Teeth"
	teeth.Anchored = true
	teeth.CanCollide = false
	teeth.CanQuery = false
	teeth.CanTouch = false
	teeth.Size = Vector3.new(19.6, 0.3, 0.6)
	teeth.CFrame = strip.CFrame * CFrame.new(0, 0.3, 0)
	teeth.Color = Color3.fromRGB(34, 225, 255)
	teeth.Material = Enum.Material.Neon
	teeth.Parent = strip
	strip.Parent = folder
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
	table.insert(spikes, { part = strip, owner = cop, hit = setmetatable({}, { __mode = "k" }), expires = os.clock() + SPIKE_LIFETIME })
end

-- Check wanted drivers against every strip, 10 times a second.
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
		return
	end
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return
	end
	for _, car in ipairs(folder:GetChildren()) do
		local driverId = car:GetAttribute("DriverUserId")
		local driver = driverId and Players:GetPlayerByUserId(driverId)
		local chassis = car.PrimaryPart
		if driver and chassis and isWanted(driver) then
			for _, s in ipairs(spikes) do
				if not s.hit[car] then
					local rel = s.part.CFrame:PointToObjectSpace(chassis.Position)
					if math.abs(rel.X) <= 10 + chassis.Size.X / 2 and math.abs(rel.Z) <= 1.5 + chassis.Size.Z / 2 and math.abs(rel.Y) < 6 then
						s.hit[car] = true
						if s.owner and s.owner.Parent then
							require(game:GetService("ServerScriptService").Services.ProgressService).Event(s.owner, "SpikeHit")
						end
						local toughness = car:GetAttribute("Toughness") or 2
						local seconds = FLAT_SECONDS - (toughness - 1) * 1.5
						car:SetAttribute("FlatUntil", now() + seconds)
						notify:FireClient(driver, "TiresPopped")
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
	-- Spike recharge and patrol pay.
	task.spawn(function()
		local minute = 0
		while true do
			task.wait(SPIKE_RECHARGE)
			minute += SPIKE_RECHARGE
			for _, p in ipairs(Players:GetPlayers()) do
				if isCop(p) then
					local max = p:GetAttribute("SpikeMax") or 2
					p:SetAttribute("SpikeCharges", math.min(max, (p:GetAttribute("SpikeCharges") or 0) + 1))
					if minute >= 60 then
						EconomyService.AddCash(p, PATROL_PAY, "patrol")
						require(game:GetService("ServerScriptService").Services.ProgressService).Event(p, "PatrolMinute")
					end
				end
			end
			if minute >= 60 then
				minute = 0
			end
		end
	end)
end

return ArrestService
