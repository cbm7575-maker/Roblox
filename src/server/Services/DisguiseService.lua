-- DisguiseService (ModuleScript, ServerScriptService.Services.DisguiseService)
-- Shaking the cops, GTA 6 style:
--   * Wardrobe (inside a hideout, on foot): RequestDisguise(hatId, maskId) puts on a hat and mask
--     built from parts. If you're wanted and no cop can see you, a new look drops 1 star and wipes
--     the outfit clue from your Suspect Card.
--   * Spray & Go (drive onto the pad while unseen): $500 repaints your car a new colour, drops 1 star
--     and wipes the car clue. 30-second cooldown per car.
-- Your look is kept in attributes LookHat / LookMask and re-applied when you respawn.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Disguises = require(ReplicatedStorage.Shared.Config.Disguises)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local HeatService = require(ServerScriptService.Services.HeatService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local HideoutService = require(ServerScriptService.Services.HideoutService)
local CarBuilder = require(game:GetService("ServerStorage").Tools.CarBuilder)

local DisguiseService = {}

local SPRAY_COST = 500
local SPRAY_COOLDOWN = 30
local PAINTS = {
	Color3.fromRGB(255, 62, 165), Color3.fromRGB(34, 225, 255), Color3.fromRGB(123, 47, 255),
	Color3.fromRGB(255, 138, 61), Color3.fromRGB(255, 214, 10), Color3.fromRGB(110, 242, 196),
	Color3.fromRGB(240, 240, 245), Color3.fromRGB(22, 22, 28), Color3.fromRGB(220, 40, 50),
}

local notify
local sprayedAt = setmetatable({}, { __mode = "k" }) -- [car] = os.clock()
local lastWarn = {}
local rng = Random.new()

local function piece(head, name, size, offset, color, shape, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = head.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = head
	w.Part1 = p
	w.Parent = p
	p.Parent = head.Parent:FindFirstChild("NCDisguise")
	return p
end

local function apply(player)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local old = char:FindFirstChild("NCDisguise")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "NCDisguise"
	folder.Parent = char
	local s = head.Size.Y / 1.2 -- scale offsets to the head size
	local hat = Disguises.HatById[player:GetAttribute("LookHat") or "none"]
	if hat and hat.Kind == "cap" then
		piece(head, "CapCrown", Vector3.new(1.3, 0.55, 1.3) * s, CFrame.new(0, 0.62 * s, 0.02 * s), hat.Color)
		piece(head, "CapBrim", Vector3.new(1.15, 0.12, 0.7) * s, CFrame.new(0, 0.4 * s, -0.8 * s), hat.Color)
	elseif hat and hat.Kind == "bucket" then
		piece(head, "BucketTop", Vector3.new(0.6, 1.3, 1.3) * s, CFrame.new(0, 0.6 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), hat.Color, Enum.PartType.Cylinder)
		piece(head, "BucketBrim", Vector3.new(0.12, 1.9, 1.9) * s, CFrame.new(0, 0.32 * s, 0) * CFrame.Angles(0, 0, math.rad(90)), hat.Color, Enum.PartType.Cylinder)
	end
	local mask = Disguises.MaskById[player:GetAttribute("LookMask") or "none"]
	if mask and mask.Kind == "bandana" then
		piece(head, "Bandana", Vector3.new(1.28, 0.5, 0.22) * s, CFrame.new(0, -0.28 * s, -0.58 * s), mask.Color)
	elseif mask and mask.Kind == "shades" then
		piece(head, "Shades", Vector3.new(1.15, 0.26, 0.12) * s, CFrame.new(0, 0.12 * s, -0.62 * s), mask.Color, nil, Enum.Material.Neon)
	end
end

local function onDisguise(player, hatId, maskId)
	if not RateLimit.Allow(player, "Disguise", 1, 2) then
		return
	end
	if type(hatId) ~= "string" or type(maskId) ~= "string" then
		return
	end
	if not Disguises.HatById[hatId] or not Disguises.MaskById[maskId] then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or hum.SeatPart or not root or not HideoutService.IsInside(root.Position) then
		return
	end
	local changed = hatId ~= (player:GetAttribute("LookHat") or "none") or maskId ~= (player:GetAttribute("LookMask") or "none")
	player:SetAttribute("LookHat", hatId)
	player:SetAttribute("LookMask", maskId)
	apply(player)
	if changed and HeatService.GetHeat(player) > 0 and not player:GetAttribute("HeatSpotted") then
		player:SetAttribute("SuspectOutfit", nil)
		HeatService.Reduce(player, 1, "disguise")
		notify:FireClient(player, "Disguised")
	end
end

local function sprayPad()
	local m = Workspace.Spawns:FindFirstChild("SprayAndGo")
	return m and m.PrimaryPart
end

local function sprayTick()
	local pad = sprayPad()
	if not pad then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		local car = seat and seat.Parent
		local chassis = car and car.PrimaryPart
		if chassis and car:GetAttribute("NCVehicle") and HeatService.GetHeat(player) > 0 then
			local rel = pad.CFrame:PointToObjectSpace(chassis.Position)
			if math.abs(rel.X) <= pad.Size.X / 2 and math.abs(rel.Z) <= pad.Size.Z / 2 and rel.Y < 12 then
				local t = os.clock()
				if player:GetAttribute("HeatSpotted") then
					if not lastWarn[player] or t - lastWarn[player] > 6 then
						lastWarn[player] = t
						notify:FireClient(player, "ShakeCopsFirst")
					end
				elseif not sprayedAt[car] or t - sprayedAt[car] > SPRAY_COOLDOWN then
					if EconomyService.Spend(player, SPRAY_COST, "spray") then
						sprayedAt[car] = t
						local old = chassis.Color
						local new = old
						while new == old do
							new = PAINTS[rng:NextInteger(1, #PAINTS)]
						end
						CarBuilder.Paint(car, new)
						player:SetAttribute("SuspectCar", nil)
						HeatService.Reduce(player, 1, "spray")
						notify:FireClient(player, "Resprayed")
					elseif not lastWarn[player] or t - lastWarn[player] > 6 then
						lastWarn[player] = t
						notify:FireClient(player, "SprayNoCash")
					end
				end
			end
		end
	end
end

function DisguiseService.Init()
	notify = Remotes.Event("Notify")
	Remotes.Event("RequestDisguise").OnServerEvent:Connect(onDisguise)
	local function onPlayer(player)
		player.CharacterAppearanceLoaded:Connect(function()
			apply(player)
		end)
		-- The saved look can arrive after the character (DataService loads asynchronously).
		local pending = false
		local function reapply()
			if pending then
				return
			end
			pending = true
			task.defer(function()
				pending = false
				apply(player)
			end)
		end
		player:GetAttributeChangedSignal("LookHat"):Connect(reapply)
		player:GetAttributeChangedSignal("LookMask"):Connect(reapply)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		lastWarn[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(sprayTick)
			if not ok then
				warn("[DisguiseService] " .. tostring(err))
			end
		end
	end)
end

return DisguiseService
