-- DriftService (ModuleScript, ServerScriptService.Services.DriftService)
-- The drift zone on Lighthouse Key (part Workspace.Activities.DriftZone).
-- Scored on the server 10 times a second while you drive inside the zone:
--   * Drifting = moving over 30 studs/s with the car sliding 15-80 degrees off its nose.
--   * Points += 10 x speed x sin(slide angle) x combo multiplier per second; the multiplier climbs
--     x1 -> x5 the longer you keep drifting (a clean 3 s drift is roughly 900 points, about $36).
--   * The chain ends after 0.8 s without drifting, leaving the zone, or a big crash (lost 40% speed):
--     you're paid $1 per 25 points (max $600 a chain). Best chain is saved.
-- The client shows DriftScore / DriftCombo (player attributes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local DataService = require(ServerScriptService.Services.DataService)

local DriftService = {}

local TICK = 0.1
local MIN_SPEED = 30
local MIN_ANGLE, MAX_ANGLE = math.rad(15), math.rad(80)
local BREAK_AFTER = 0.8
local POINTS_PER_DOLLAR = 25
local MAX_PAYOUT = 600

local chains = {} -- [player] = { score, combo, driftTime, idle, lastSpeed }
local driftEvent

local function inZone(zone, pos)
	local rel = zone.CFrame:PointToObjectSpace(pos)
	return math.abs(rel.X) <= zone.Size.X / 2 and math.abs(rel.Z) <= zone.Size.Z / 2 and rel.Y < 20 and rel.Y > -5
end

local function bank(player, c, reason)
	chains[player] = nil
	player:SetAttribute("DriftScore", nil)
	player:SetAttribute("DriftCombo", nil)
	local score = math.floor(c.score)
	if score < 100 then
		return
	end
	local pay = math.min(MAX_PAYOUT, math.floor(score / POINTS_PER_DOLLAR))
	EconomyService.AddCash(player, pay, "drift")
	require(game:GetService("ServerScriptService").Services.ProgressService).Event(player, "Drift", score)
	local data = DataService.Get(player)
	local best = false
	if data then
		data.drift = data.drift or 0
		if score > data.drift then
			data.drift = score
			best = true
		end
	end
	driftEvent:FireClient(player, { Score = score, Pay = pay, Best = best, Reason = reason })
end

local function tick(zone)
	for _, player in ipairs(Players:GetPlayers()) do
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local car = hum and hum.SeatPart and hum.SeatPart.Name == "DriverSeat" and hum.SeatPart.Parent -- drivers only (not passengers)
		local chassis = car and car.PrimaryPart
		local c = chains[player]
		if not chassis or not car:GetAttribute("NCVehicle") or not inZone(zone, chassis.Position) then
			if c then
				bank(player, c, "left")
			end
		else
			local vel = chassis.AssemblyLinearVelocity
			local flatVel = Vector3.new(vel.X, 0, vel.Z)
			local speed = flatVel.Magnitude
			local look = Vector3.new(chassis.CFrame.LookVector.X, 0, chassis.CFrame.LookVector.Z)
			local angle = 0
			if speed > 1 and look.Magnitude > 0.1 then
				angle = math.acos(math.clamp(flatVel.Unit:Dot(look.Unit), -1, 1))
			end
			local drifting = speed > MIN_SPEED and angle >= MIN_ANGLE and angle <= MAX_ANGLE
			if drifting then
				c = c or { score = 0, combo = 1, driftTime = 0, idle = 0, lastSpeed = speed }
				chains[player] = c
				-- A big crash ends the chain.
				if speed < c.lastSpeed * 0.6 and c.lastSpeed > 60 then
					bank(player, c, "crash")
				else
					c.idle = 0
					c.driftTime += TICK
					c.combo = math.min(5, 1 + math.floor(c.driftTime / 2))
					c.score += speed * math.sin(angle) * TICK * c.combo * 10
					c.lastSpeed = speed
					player:SetAttribute("DriftScore", math.floor(c.score))
					player:SetAttribute("DriftCombo", c.combo)
				end
			elseif c then
				c.idle += TICK
				c.lastSpeed = speed
				if c.idle >= BREAK_AFTER then
					bank(player, c, "ended")
				end
			end
		end
	end
end

function DriftService.Init()
	driftEvent = Remotes.Event("DriftEvent")
	local zone = Workspace:WaitForChild("Activities"):WaitForChild("DriftZone", 10)
	if not zone then
		warn("[DriftService] no DriftZone")
		return
	end
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick, zone)
			if not ok then
				warn("[DriftService] " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		chains[p] = nil
	end)
end

return DriftService
