-- RobberToolsService (ModuleScript, ServerScriptService.Services.RobberToolsService)
-- Tools for wanted citizens on the run (nitro lives in the car itself).
--   Smoke (RequestSmoke): while wanted and driving, lays a smoke trail behind the car for 4 s.
--     The clouds are invisible blockers plus smoke particles in Workspace.Smoke: they block cop sight
--     lines (HeatService, AI police) and tasers, but car suspension rays and cameras ignore them.
--     1 charge (SmokeCharges), refills every 30 s.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local RobberToolsService = {}

local SMOKE_RECHARGE = 30
local SMOKE_PUFFS = 6
local PUFF_GAP = 0.6
local PUFF_LIFE = 9
local PUFF_SIZE = 26

local folder

local function puff(position)
	local p = Instance.new("Part")
	p.Name = "SmokeCloud"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(PUFF_SIZE, PUFF_SIZE, PUFF_SIZE)
	p.Position = position
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true -- blocks sight-line raycasts
	p.Transparency = 1
	p.CastShadow = false
	local a = Instance.new("Attachment")
	a.Parent = p
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(230, 200, 255), Color3.fromRGB(255, 170, 220))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 16) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(3, 5)
	e.Rate = 18
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Parent = a
	p.Parent = folder
	task.delay(PUFF_LIFE - 3, function()
		e.Enabled = false
	end)
	task.delay(PUFF_LIFE, function()
		p:Destroy()
	end)
end

local function onSmoke(player)
	if not RateLimit.Allow(player, "Smoke", 1, 1) then
		return
	end
	if player:GetAttribute("Side") ~= "Civilian" or (player:GetAttribute("Heat") or 0) <= 0 then
		return
	end
	if (player:GetAttribute("SmokeCharges") or 0) < 1 then
		Remotes.Event("Notify"):FireClient(player, "NoSmoke")
		return
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local car = hum and hum.SeatPart and hum.SeatPart.Parent
	local chassis = car and car.PrimaryPart
	if not chassis or not car:GetAttribute("NCVehicle") then
		return
	end
	player:SetAttribute("SmokeCharges", 0)
	task.spawn(function()
		-- Rank 5+: a longer trail.
		for _ = 1, (player:GetAttribute("CivRank") or 1) >= 5 and SMOKE_PUFFS + 4 or SMOKE_PUFFS do
			if not chassis.Parent then
				break
			end
			puff(chassis.Position - chassis.CFrame.LookVector * 12 + Vector3.new(0, 3, 0))
			task.wait(PUFF_GAP)
		end
	end)
end

function RobberToolsService.Init()
	folder = Workspace:FindFirstChild("Smoke") or Instance.new("Folder")
	folder.Name = "Smoke"
	folder.Parent = Workspace
	Remotes.Event("RequestSmoke").OnServerEvent:Connect(onSmoke)
	local function onPlayer(p)
		p:SetAttribute("SmokeCharges", 1)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	task.spawn(function()
		while true do
			task.wait(SMOKE_RECHARGE)
			for _, p in ipairs(Players:GetPlayers()) do
				if (p:GetAttribute("SmokeCharges") or 0) < 1 then
					p:SetAttribute("SmokeCharges", 1)
				end
			end
		end
	end)
end

return RobberToolsService
