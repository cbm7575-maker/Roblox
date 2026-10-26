-- ImpactService (ModuleScript, ServerScriptService.Services.ImpactService)
-- Kid-friendly bumps between cars and people (nobody ever loses health), plus getting into your car
-- with the F key / GET IN button.
--   * ImpactHit (driver's device -> server): "my car just hit this player on foot". The driver's
--     device owns its car's physics, so it spots the hit (ImpactClient). We check it: rate limit, the
--     hitter really is driving, the car is right next to the victim, the victim is on foot and not
--     already down. Then the victim is knocked over:
--       - "Knockdown" (direction, speed, seconds) goes to the victim's device, which owns their
--         character and does the fall, the dizzy stars and getting up (ImpactClient).
--       - Player attribute KnockedUntil (server time) lets every device show the dizzy stars.
--     After getting up you can't be knocked again for a couple of seconds (no chain knock-downs).
--   * AI patrol cars are server cars, so we check them here 5 times a second: one moving fast that
--     drives into someone on foot knocks them over. Never a player any patrol is chasing (their unit
--     parks beside them; a knock-down there would turn straight into an arrest, which isn't fair).
--   * RequestEnterCar (F / GET IN / gamepad X): sits you in your own empty car, or (civilians only) in
--     the hot car you stole (its Drive prompt is gone once stolen, so this is the only way back in),
--     when you're close and not knocked over or tasered. The E prompt (VehicleService) has the same
--     knocked-over / tasered rule. Asked while sitting in another car (or another seat of that one), the
--     "GetOutFirst" toast says why nothing happened (at most one every 3 s, shared with CarjackService and
--     CarBoostService).
-- Nobody sitting in a car is ever knocked down.
-- (The body also goes limp for everyone through RagdollService.KnockDown, inside a pcall: without it the
-- fall is the stiff tip-over.)
-- Public: ImpactService.KnockDown(victim, dir, speed, seconds, reason?) -> bool. The same checks and fall as a
-- car hit, for `seconds` on the ground (CombatService knockouts use it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local VehicleService = require(ServerScriptService.Services.VehicleService)

-- Limp bodies (RagdollService). Optional on purpose: if that module is missing or fails to load, a
-- knock-down is still the stiff tip-over ImpactClient does by itself.
local RagdollService
do
	local module = ServerScriptService.Services:FindFirstChild("RagdollService")
	local ok, result = pcall(function()
		return module and require(module)
	end)
	RagdollService = (ok and type(result) == "table") and result or nil
end

local ImpactService = {}

local KNOCK_TIME = 2.5 -- seconds on the ground
local IMMUNE_AFTER = 2 -- seconds after getting up before you can be knocked again
local HIT_RANGE = 20 -- studs between the hitter's car and the victim...
local LAG_RANGE = 10 -- ...plus up to this much for fast cars (the two devices see slightly old positions)
local MIN_CAR_SPEED = 10 -- a parked car can't "hit" anyone
local AI_INTERVAL = 0.2
local AI_MIN_SPEED = 20
local AI_MARGIN = 1.5
local ENTER_RANGE = 16 -- the client offers GET IN at 12 studs; a little slack for lag

local safeUntil = {} -- [player] = os.clock() until which they can't be knocked down again
local downUntil = {} -- [player] = os.clock() until which they're on the ground
local knockRemote, notify

local function onFoot(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 or hum.SeatPart then
		return nil
	end
	return hum, root
end

-- The car this player is driving right now (driver's seat), or nil.
local function drivenCar(p)
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.Health > 0 and hum.SeatPart
	if not seat or seat.Name ~= "DriverSeat" then
		return nil
	end
	local car = seat.Parent
	local folder = Workspace:FindFirstChild("Vehicles")
	if not car or not folder or car.Parent ~= folder or car:GetAttribute("DriverUserId") ~= p.UserId then
		return nil
	end
	return car, car.PrimaryPart
end

-- Knock a player on foot over. dir: flat unit vector to push them along; speed: the car's speed;
-- seconds: time on the ground (KNOCK_TIME when left out).
local function knockDown(victim, dir, speed, seconds, reason)
	seconds = seconds or KNOCK_TIME
	local now = os.clock()
	if (safeUntil[victim] or 0) > now then
		return false
	end
	local hum = onFoot(victim)
	if not hum then
		return false
	end
	-- Tasered players are already down (LawClient keeps them there).
	if (victim:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow() then
		return false
	end
	downUntil[victim] = now + seconds
	safeUntil[victim] = now + seconds + IMMUNE_AFTER
	victim:SetAttribute("KnockedUntil", Workspace:GetServerTimeNow() + seconds)
	knockRemote:FireClient(victim, dir, speed, seconds)
	if RagdollService then
		-- The same hop ImpactClient gives the stiff body (10-22 along dir, 14 up), so the loose limbs leave with it.
		-- (6: ImpactClient stands the body up after at most that long, and the joints must be whole by then)
		local ok, err = pcall(RagdollService.KnockDown, victim, math.min(seconds, 6),
			dir * math.clamp(speed * 0.25, 10, 22) + Vector3.new(0, 14, 0), reason or "car")
		if not ok then
			warn("[ImpactService] ragdoll: " .. tostring(err))
		end
	end
	return true
end

-- Public knock-down for other services (CombatService knockouts). Same checks as a car hit: on foot,
-- not tasered, not just back up from another fall. Returns true if they went down.
function ImpactService.KnockDown(victim, dir, speed, seconds, reason)
	if not knockRemote or typeof(victim) ~= "Instance" or not victim:IsA("Player") or victim.Parent ~= Players then
		return false
	end
	local flatDir = typeof(dir) == "Vector3" and Vector3.new(dir.X, 0, dir.Z) or Vector3.zero
	-- (a NaN direction fails these comparisons too)
	local len = flatDir.Magnitude
	flatDir = (len > 0.05 and len < math.huge) and flatDir.Unit or Vector3.new(0, 0, -1)
	speed = tonumber(speed) or 30
	if speed ~= speed then
		speed = 30
	end
	seconds = tonumber(seconds) or KNOCK_TIME
	if seconds ~= seconds then
		seconds = KNOCK_TIME
	end
	return knockDown(victim, flatDir, math.clamp(speed, 0, 200), math.clamp(seconds, 0.5, 10), type(reason) == "string" and reason or "ko")
end

-- Push direction: mostly along the car's travel, a bit away from the car's centre.
local function pushDir(chassis, root, flatVel)
	local away = (root.Position - chassis.Position) * Vector3.new(1, 0, 1)
	local along = flatVel.Magnitude > 0.1 and flatVel.Unit or Vector3.zero
	local dir = along * 0.6 + (away.Magnitude > 0.1 and away.Unit or Vector3.zero) * 0.4
	if dir.Magnitude < 0.1 then
		dir = along.Magnitude > 0 and along or Vector3.new(0, 0, -1)
	end
	return dir.Unit
end

local function onHit(player, victim)
	if not RateLimit.Allow(player, "ImpactHit", 3, 4) then
		return
	end
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") or victim == player or victim.Parent ~= Players then
		return
	end
	local car, chassis = drivenCar(player)
	if not car or not chassis or car:GetAttribute("Boat") then
		return -- boats don't knock swimmers over
	end
	local _, root = onFoot(victim)
	if not root then
		return
	end
	local vel = chassis.AssemblyLinearVelocity
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local speed = flatVel.Magnitude
	if speed ~= speed or speed < MIN_CAR_SPEED then
		return
	end
	local dist = (root.Position - chassis.Position).Magnitude
	if dist > HIT_RANGE + math.min(speed * 0.12, LAG_RANGE) then
		return
	end
	knockDown(victim, pushDir(chassis, root, flatVel), speed)
end

-- AI patrols driving into people on foot (5 times a second).
local function checkAI()
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return
	end
	local now = os.clock()
	-- Everyone a patrol is chasing. None of them is knocked over by any patrol: with two wanted
	-- players close together, one's unit mustn't knock down the other right beside their own unit.
	local chased = {}
	for _, car in ipairs(folder:GetChildren()) do
		local t = car:GetAttribute("AIPolice") and car:GetAttribute("AITarget")
		if t then
			chased[t] = true
		end
	end
	local walkers = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local _, root = onFoot(p)
		if root and not chased[p.UserId] and (safeUntil[p] or 0) <= now then
			table.insert(walkers, { p, root })
		end
	end
	if #walkers == 0 then
		return
	end
	for _, car in ipairs(folder:GetChildren()) do
		local chassis = car:GetAttribute("AIPolice") and car.PrimaryPart
		if chassis then
			local vel = chassis.AssemblyLinearVelocity
			local flatVel = Vector3.new(vel.X, 0, vel.Z)
			local speed = flatVel.Magnitude
			if speed > AI_MIN_SPEED then
				local cf = chassis.CFrame
				local half = chassis.Size / 2
				local fwd = vel:Dot(cf.LookVector)
				-- Grow the box back over the road covered since the last check, so a fast car can't
				-- skip over someone between two checks. Forward is -Z, so "behind" is +Z.
				local sweep = math.abs(fwd) * AI_INTERVAL
				local shift = fwd >= 0 and sweep / 2 or -sweep / 2
				for _, w in ipairs(walkers) do
					local p, root = w[1], w[2]
					if (safeUntil[p] or 0) <= now then -- (someone knocked by an earlier car this check)
						local rel = cf:PointToObjectSpace(root.Position)
						local z = rel.Z - shift
						if math.abs(rel.X) < half.X + AI_MARGIN and math.abs(z) < half.Z + sweep / 2 + AI_MARGIN
							and rel.Y > -half.Y - 2 and rel.Y < half.Y + 6 then
							knockDown(p, pushDir(chassis, root, flatVel), speed)
						end
					end
				end
			end
		end
	end
end

-- Sitting down (alive): "Get out of your car first", at most one toast every 3 s per player. The RateLimit
-- key is shared with CarjackService and CarBoostService, so trying all three at once still gives one toast.
local function getOutFirst(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and hum.SeatPart and RateLimit.Allow(player, "GetOutFirstToast", 1 / 3, 1) then
		notify:FireClient(player, "GetOutFirst")
	end
end

local function onEnter(player, car)
	if not RateLimit.Allow(player, "EnterCar", 2, 3) then
		return
	end
	local folder = Workspace:FindFirstChild("Vehicles")
	if typeof(car) ~= "Instance" or not car:IsA("Model") or not folder or car.Parent ~= folder then
		return
	end
	local side = player:GetAttribute("Side") or "Civilian"
	if side == "Prisoner" then
		return
	end
	if (player:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow() then
		return -- tasered: the cop gets their chance to cuff
	end
	local mine = car:GetAttribute("OwnerUserId") == player.UserId and VehicleService.GetCar(player) == car
		and VehicleService.CanDrive(side, car:GetAttribute("VehicleId"))
	-- Back into a stolen hot car: civilians only, like picking the lock (not after switching to cop).
	local stolen = side == "Civilian" and car:GetAttribute("HotCar") == true and car:GetAttribute("ThiefUserId") == player.UserId
	if not mine and not stolen then
		return
	end
	local seat = car:FindFirstChild("DriverSeat")
	if not seat or not seat:IsA("VehicleSeat") or seat.Occupant then
		return
	end
	local hum, root = onFoot(player)
	if not hum then
		getOutFirst(player) -- sitting in a car already: say so (nothing to say when dead)
		return
	end
	if (downUntil[player] or 0) > os.clock() then
		return -- still dizzy on the ground
	end
	if (root.Position - seat.Position).Magnitude > ENTER_RANGE then
		return
	end
	seat:Sit(hum)
end

function ImpactService.Init()
	knockRemote = Remotes.Event("Knockdown")
	notify = Remotes.Event("Notify")
	Remotes.Event("ImpactHit").OnServerEvent:Connect(onHit)
	Remotes.Event("RequestEnterCar").OnServerEvent:Connect(onEnter)
	Players.PlayerRemoving:Connect(function(p)
		safeUntil[p] = nil
		downUntil[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(AI_INTERVAL)
			local ok, err = pcall(checkAI)
			if not ok then
				warn("[ImpactService] " .. tostring(err))
			end
		end
	end)
end

return ImpactService
