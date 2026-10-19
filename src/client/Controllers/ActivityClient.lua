-- ActivityClient (ModuleScript, StarterPlayerScripts.Controllers.ActivityClient)
-- Client side of races and stunt jumps:
--   * Race: 3-2-1-GO countdown, a timer, the next checkpoint as a glowing ring with a light beam,
--     "CHECKPOINT 3/8", and a FINISH stamp with time, reward and personal best.
--   * Stunts: STUNT JUMP stamp with the distance; "slow-motion" camera while InStunt.
-- Positions come from Config.Activities; the server decides everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Activities = require(ReplicatedStorage.Shared.Config.Activities)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local ActivityClient = {}

local GOLD = Color3.fromRGB(255, 214, 10)
local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local ORANGE = Color3.fromRGB(255, 138, 61)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

local racesById = {}
for _, r in ipairs(Activities.Races) do
	racesById[r.Id] = r
end

local gui, timerLabel, cpLabel, bigLabel
local ring, beam
local current -- { race, index, startAt }

local function now()
	return Workspace:GetServerTimeNow()
end

local function fmt(t)
	t = math.max(0, t)
	return string.format("%d:%04.1f", t // 60, t % 60)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "ActivityUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	local function text(name, pos, size, color)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = pos
		l.Size = size
		l.BackgroundTransparency = 1
		l.Font = FONT
		l.TextScaled = true
		l.TextColor3 = color
		l.Visible = false
		local s = Instance.new("UIStroke")
		s.Color = DARK
		s.Thickness = 2
		s.Parent = l
		l.Parent = gui
		return l
	end
	timerLabel = text("Timer", UDim2.new(0.5, 0, 0, 56), UDim2.fromScale(0.18, 0.07), Color3.new(1, 1, 1))
	cpLabel = text("Checkpoint", UDim2.new(0.5, 0, 0, 56), UDim2.fromScale(0.3, 0.045), GOLD)
	cpLabel.Position = UDim2.new(0.5, 0, 0.1, 56)
	bigLabel = text("Countdown", UDim2.fromScale(0.5, 0.25), UDim2.fromScale(0.3, 0.2), GOLD)

	-- Checkpoint marker (local-only parts)
	ring = Instance.new("Part")
	ring.Name = "CheckpointRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(1, 64, 64)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = GOLD
	ring.Transparency = 1
	ring.Parent = Workspace.CurrentCamera
	beam = Instance.new("Part")
	beam.Name = "CheckpointBeam"
	beam.Size = Vector3.new(6, 400, 6)
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = GOLD
	beam.Transparency = 1
	beam.Parent = Workspace.CurrentCamera
end

local job -- { stage, pos, name }
local jobLabel, endShiftButton

local function showJobMarker()
	if not job or not job.pos then
		ring.Transparency, beam.Transparency = 1, 1
		return
	end
	ring.CFrame = CFrame.new(job.pos.X, 0.4, job.pos.Z) * CFrame.Angles(0, 0, math.rad(90))
	beam.CFrame = CFrame.new(job.pos.X, 200, job.pos.Z)
	ring.Color = job.stage == "pickup" and CYAN or GOLD
	beam.Color = ring.Color
	ring.Transparency, beam.Transparency = 0.55, 0.65
end

-- Checkpoints sit under the race timer; the drift score sits just above DriveUI's speed gauge and
-- car-health bar (their top is at about 0.834 of the screen height minus 22 px), clear of the top bar.
local function placeLabel(drift)
	cpLabel.AnchorPoint = Vector2.new(0.5, drift and 1 or 0)
	cpLabel.Position = drift and UDim2.new(0.5, 0, 0.83, -28) or UDim2.new(0.5, 0, 0.1, 56)
end

local function showCheckpoint()
	if not current then
		ring.Transparency, beam.Transparency = 1, 1
		cpLabel.Visible = false
		showJobMarker()
		return
	end
	local race = current.race
	local cp = race.Checkpoints[current.index]
	if not cp then
		return
	end
	ring.CFrame = CFrame.new(cp.X, 0.4, cp.Z) * CFrame.Angles(0, 0, math.rad(90))
	beam.CFrame = CFrame.new(cp.X, 200, cp.Z)
	ring.Transparency, beam.Transparency = 0.55, 0.65
	local last = current.index == #race.Checkpoints
	ring.Color = last and PINK or GOLD
	beam.Color = ring.Color
	placeLabel(false)
	cpLabel.Visible = true
	cpLabel.Text = last and "FINAL CHECKPOINT" or string.format("CHECKPOINT %d / %d", current.index, #race.Checkpoints)
end

local function endRace()
	current = nil
	timerLabel.Visible = false
	bigLabel.Visible = false
	showCheckpoint()
end

local function onRace(kind, d)
	if kind == "Countdown" then
		current = { race = racesById[d.Id], index = 1, startAt = d.StartAt }
		showCheckpoint()
		timerLabel.Visible = true
		NotifyController.Show(current.race.Name .. ": beat " .. current.race.Par .. "s for the bonus!", GOLD)
	elseif kind == "Checkpoint" and current then
		current.index = d.Index
		showCheckpoint()
	elseif kind == "Finished" then
		local par = d.Time <= d.Par
		local sub = fmt(d.Time) .. "  +" .. HUDController.Money(d.Reward) .. (d.NewBest and "  NEW BEST!" or ("  best " .. fmt(d.Best or d.Time)))
		if d.Repeat then
			sub ..= string.format("  (repeat: %d%%)", math.floor((Activities.RaceRepeatShare or 0.3) * 100 + 0.5))
		end
		endRace()
		HUDController.Stamp(par and "FINISH! UNDER PAR" or "FINISH!", sub, GOLD)
	elseif kind == "Cancelled" then
		endRace()
		local why = {
			LeftCar = "Race cancelled: you left your car.",
			Wanted = "Race cancelled: the cops are after you!",
			TooSlow = "Race cancelled: out of time.",
			CarLost = "Race cancelled: your car is gone.",
			Invalid = "Race cancelled.",
		}
		NotifyController.Show(why[d.Reason] or "Race cancelled.", ORANGE)
	end
end

local function onStunt(d)
	if d.Failed then
		if d.Crashed then
			NotifyController.Show(d.Name .. ": crashed the landing!", ORANGE)
		else
			NotifyController.Show(string.format("%s: %d ft - need %d ft. Faster!", d.Name, d.Distance, d.Need), ORANGE)
		end
		return
	end
	local sub = string.format("%s  %d ft", d.Name, d.Distance)
	if d.Pay > 0 then
		sub ..= "  +" .. HUDController.Money(d.Pay)
	end
	HUDController.Stamp("STUNT JUMP!", sub .. string.format("  (%d/%d)", d.Done, d.Total), CYAN)
end

local function refreshDrift()
	local score = player:GetAttribute("DriftScore")
	if score then
		placeLabel(true)
		cpLabel.Visible = true
		cpLabel.TextColor3 = Color3.fromRGB(123, 47, 255)
		cpLabel.Text = string.format("DRIFT %s  x%d", HUDController.Money(score):sub(2), player:GetAttribute("DriftCombo") or 1)
	elseif not current then
		cpLabel.Visible = false
		cpLabel.TextColor3 = GOLD
	end
end

local function onJob(kind, d)
	local courier = d.Kind == "Courier"
	if kind == "Pickup" then
		job = { stage = "pickup", pos = d.Pos, name = d.Name, courier = courier }
		NotifyController.Show(courier and ("COURIER: pick up a package from " .. d.Name .. ". Follow the beam!")
			or ("TAXI: " .. d.Name .. " needs a ride. Follow the blue beam!"), CYAN)
	elseif kind == "Dropoff" then
		job = { stage = "dropoff", pos = d.Pos, name = d.Name, est = d.Est, since = os.clock(), courier = courier }
		NotifyController.Show(courier and "Package loaded! Deliver it fast for a bonus."
			or (d.Name .. " hopped in. Get them there fast for a tip!"), GOLD)
	elseif kind == "Paid" then
		if job then
			job.stage, job.pos = "waiting", nil
		end
		HUDController.Stamp(courier and "DELIVERED" or "FARE PAID", "+" .. HUDController.Money(d.Pay)
			.. (d.Tip > 0 and (courier and "  (fast bonus!)" or "  (tip!)") or ""), GOLD)
	elseif kind == "Ended" then
		job = nil
		local why = { LeftCar = "Shift over: you left your car.", Wanted = "Shift over: you're wanted!", Player = "Shift over.", NoFares = "No fares right now." }
		NotifyController.Show((why[d.Reason] or "Shift over.") .. string.format(" %d fares, %s earned.", d.Fares, HUDController.Money(d.Earned)), GOLD)
	end
	showCheckpoint()
end

local function updateJobUI()
	local active = job ~= nil
	endShiftButton.Visible = active
	jobLabel.Visible = active and job.pos ~= nil and not current
	if jobLabel.Visible then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local dist = root and math.floor((Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(job.pos.X, 0, job.pos.Z)).Magnitude) or 0
		if job.stage == "pickup" then
			jobLabel.Text = string.format(job.courier and "PICK UP AT %s  -  %d ft" or "PICK UP %s  -  %d ft", string.upper(job.name), dist)
		else
			local left = job.est and math.max(0, math.floor(job.est - (os.clock() - job.since))) or 0
			jobLabel.Text = job.courier and string.format("DELIVER THE PACKAGE  -  %d ft  -  bonus %ds", dist, left)
				or string.format("DROP OFF %s  -  %d ft  -  tip %ds", string.upper(job.name), dist, left)
		end
	end
end

function ActivityClient.Init()
	build()
	jobLabel = Instance.new("TextLabel")
	jobLabel.Name = "Job"
	jobLabel.AnchorPoint = Vector2.new(0.5, 0)
	jobLabel.Position = UDim2.new(0.5, 0, 0, 60)
	jobLabel.Size = UDim2.fromScale(0.45, 0.05)
	jobLabel.BackgroundTransparency = 1
	jobLabel.Font = FONT
	jobLabel.TextScaled = true
	jobLabel.TextColor3 = GOLD
	jobLabel.Visible = false
	local js = Instance.new("UIStroke")
	js.Color = DARK
	js.Thickness = 2
	js.Parent = jobLabel
	jobLabel.Parent = gui
	endShiftButton = Instance.new("TextButton")
	endShiftButton.Name = "EndShift"
	endShiftButton.Position = UDim2.new(0, 16, 0, 284)
	endShiftButton.Size = UDim2.fromOffset(150, 38)
	endShiftButton.BackgroundColor3 = DARK
	endShiftButton.Font = FONT
	endShiftButton.TextScaled = true
	endShiftButton.TextColor3 = GOLD
	endShiftButton.Text = "END SHIFT"
	endShiftButton.Visible = false
	endShiftButton.Parent = gui
	local ec = Instance.new("UICorner")
	ec.CornerRadius = UDim.new(0.5, 0)
	ec.Parent = endShiftButton
	endShiftButton.Activated:Connect(function()
		Remotes.Event("RequestJob"):FireServer("End")
	end)
	Remotes.OnClient("JobEvent", onJob)
	task.spawn(function()
		while true do
			pcall(updateJobUI)
			task.wait(0.2)
		end
	end)
	Remotes.OnClient("RaceEvent", onRace)
	Remotes.OnClient("StuntEvent", onStunt)
	player:GetAttributeChangedSignal("DriftScore"):Connect(refreshDrift)
	player:GetAttributeChangedSignal("DriftCombo"):Connect(refreshDrift)
	Remotes.OnClient("DriftEvent", function(d)
		local sub = HUDController.Money(d.Score):sub(2) .. " pts  +" .. HUDController.Money(d.Pay) .. (d.Best and "  NEW BEST!" or "")
			.. (d.Reduced and "  (reduced pay today)" or "")
		HUDController.Stamp(d.Reason == "crash" and "DRIFT (CRASHED)" or "DRIFT!", sub, Color3.fromRGB(123, 47, 255))
	end)
	RunService.RenderStepped:Connect(function()
		if not current then
			return
		end
		local t = now()
		if t < current.startAt then
			bigLabel.Visible = true
			bigLabel.Text = tostring(math.ceil(current.startAt - t))
			timerLabel.Text = fmt(0)
		else
			if t - current.startAt < 0.8 then
				bigLabel.Visible = true
				bigLabel.Text = "GO!"
			else
				bigLabel.Visible = false
			end
			timerLabel.Text = fmt(t - current.startAt)
		end
		-- Spin the ring a little so it reads as "go here".
		ring.CFrame = ring.CFrame * CFrame.Angles(math.rad(1), 0, 0)
	end)
end

return ActivityClient
