-- VehicleGuard (ModuleScript, ServerScriptService.Services.VehicleGuard)
-- Server-side anti-cheat for cars. A player's device runs the physics of the car it owns, so a
-- cheater could move it impossibly. Twice a second the server checks every car a player's device
-- owns (driving or just got out) against its last GOOD position:
--   * Horizontal speed over the car's nitro top speed x 1.25 + 15, two samples in a row -> snap back
--   * Teleport: more than 300 studs sideways, or 120 studs up, in one sample -> snap back
--   * Spinning faster than 25 rad/s two samples in a row (used to fling others) -> snap back
--   * 5 flags within 5 minutes -> the car is removed ("CarRemoved"); kicks only after we confirm
--     there are no false alarms in live servers.
-- A fast sample never moves the reference point (the last GOOD position, where a snap back goes).
-- The second strike is judged over a fresh window that starts at the first fast sample, so a
-- network stall (the car frozen, then catching up in one jump) can't count twice.
-- In Studio it only logs, unless Workspace attribute GuardEnforceInStudio = true.
-- Server-side moves (teleports, resets) must call VehicleGuard.Allow(car) first; that window also
-- keeps VehicleDamageService from reading the move as a crash (VehicleGuard.Allowed(car)).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local VehicleService = require(ServerScriptService.Services.VehicleService)

local VehicleGuard = {}

local INTERVAL = 0.5
local SPEED_SLACK = 1.25
local SPEED_EXTRA = 15 -- studs/s of headroom for bumps, ramps and lag
local TELEPORT_STUDS = 300
local RISE_STUDS = 120
local SPIN_LIMIT = 25 -- rad/s
local FLAG_LIMIT = 5
local FLAG_WINDOW = 300

local last = setmetatable({}, { __mode = "k" }) -- [car] = { cf, t, strikes, spins, freshCf, freshT }
local allowUntil = setmetatable({}, { __mode = "k" })
local flags = {} -- [userId] = { times }

VehicleGuard.Log = {}

local function enforcing()
	return not RunService:IsStudio() or Workspace:GetAttribute("GuardEnforceInStudio") == true
end

local function log(msg)
	table.insert(VehicleGuard.Log, msg)
	if #VehicleGuard.Log > 50 then
		table.remove(VehicleGuard.Log, 1)
	end
	warn("[VehicleGuard] " .. msg)
end

function VehicleGuard.Allow(car, seconds)
	allowUntil[car] = os.clock() + (seconds or 2)
	last[car] = nil
end

-- Is this car inside a server move's grace window?
function VehicleGuard.Allowed(car)
	local untilT = allowUntil[car]
	return untilT ~= nil and os.clock() < untilT
end

-- Take physics away from the client, put the car back, then return control to its driver.
local function snapBack(car, cf, player)
	local chassis = car.PrimaryPart
	if not chassis then
		return
	end
	chassis:SetNetworkOwner(nil)
	car:PivotTo(cf)
	chassis.AssemblyLinearVelocity = Vector3.zero
	chassis.AssemblyAngularVelocity = Vector3.zero
	VehicleGuard.Allow(car, 1)
	task.delay(0.6, function()
		local seat = car:FindFirstChild("DriverSeat")
		local occupant = seat and seat.Occupant
		if car.Parent and player and occupant and occupant.Parent == player.Character then
			chassis:SetNetworkOwner(player)
		end
	end)
end

-- Returns true if the car was removed.
local function flag(car, player, reason)
	local userId = player.UserId
	local now = os.clock()
	local list = flags[userId] or {}
	flags[userId] = list
	table.insert(list, now)
	while list[1] and now - list[1] > FLAG_WINDOW do
		table.remove(list, 1)
	end
	log(string.format("%s: %s (%d flags in 5 min)", player.Name, reason, #list))
	if #list >= FLAG_LIMIT and enforcing() then
		log("removing car of " .. player.Name)
		flags[userId] = {}
		local ownerId = car:GetAttribute("OwnerUserId")
		if ownerId then
			VehicleService.Despawn(ownerId)
		else
			car:Destroy()
		end
		Remotes.Event("Notify"):FireClient(player, "CarRemoved")
		return true
	end
	return false
end

local function check(car, now)
	local chassis = car.PrimaryPart
	if not chassis then
		return
	end
	local owner = chassis:GetNetworkOwner()
	if not owner then
		-- The server simulates it: nothing to check, but keep the reference fresh.
		last[car] = { cf = chassis.CFrame, t = now, strikes = 0, spins = 0 }
		return
	end
	if allowUntil[car] and now < allowUntil[car] then
		return
	end
	local cf = chassis.CFrame
	local prev = last[car]
	if not prev then
		last[car] = { cf = cf, t = now, strikes = 0, spins = 0 }
		return
	end
	-- After a first fast sample, judge over the fresh window that starts there (a lag burst inflates
	-- one window only); otherwise over the window since the last good sample.
	local fromCf = prev.freshCf or prev.cf
	local fromT = prev.freshT or prev.t
	local dt = now - fromT
	if dt <= 0 then
		return
	end
	local delta = cf.Position - fromCf.Position
	local flat = Vector3.new(delta.X, 0, delta.Z).Magnitude
	local maxSpeed = (car:GetAttribute("MaxSpeed") or 150) * (car:GetAttribute("NitroSpeed") or 1.2)
	local limit = maxSpeed * SPEED_SLACK + SPEED_EXTRA

	local reason
	if flat > TELEPORT_STUDS and flat / dt > limit then
		reason = string.format("teleport %.0f studs in %.2fs", flat, dt)
	elseif delta.Y > RISE_STUDS then
		reason = string.format("rose %.0f studs in %.2fs", delta.Y, dt)
	elseif flat / dt > limit then
		prev.strikes += 1
		if prev.strikes >= 2 then
			reason = string.format("speed %.0f studs/s (limit %.0f)", flat / dt, limit)
		else
			-- Keep the last good point (for a snap back), and judge the next sample from here.
			prev.freshCf, prev.freshT = cf, now
			return
		end
	elseif chassis.AssemblyAngularVelocity.Magnitude > SPIN_LIMIT then
		prev.spins += 1
		if prev.spins >= 2 then
			reason = string.format("spinning %.0f rad/s", chassis.AssemblyAngularVelocity.Magnitude)
		end
	else
		prev.spins = 0
	end

	prev.freshCf, prev.freshT = nil, nil
	if reason then
		prev.strikes, prev.spins = 0, 0
		if flag(car, owner, reason) then
			return
		end
		if enforcing() then
			snapBack(car, prev.cf, owner)
			return
		end
	end
	prev.strikes = 0
	prev.cf = cf
	prev.t = now
end

function VehicleGuard.Init()
	task.spawn(function()
		while true do
			task.wait(INTERVAL)
			local now = os.clock()
			local folder = Workspace:FindFirstChild("Vehicles")
			if folder then
				for _, car in ipairs(folder:GetChildren()) do
					local ok, err = pcall(check, car, now)
					if not ok then
						warn("[VehicleGuard] check failed: " .. tostring(err))
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		flags[player.UserId] = nil
	end)
end

return VehicleGuard
