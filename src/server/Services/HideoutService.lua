-- HideoutService (ModuleScript, ServerScriptService.Services.HideoutService)
-- Hideouts (models named "Hideout" in Workspace.Spawns, with a Pad): where Wanted players bank loot.
-- A robber inside a hideout with cash in the bag banks it, as long as no cop can see them right now
-- (HeatSpotted). Banking also clears their heat: they laid low. On foot or in a car both count.
-- The client moves its own character, so the trip is sanity-checked too: banking waits until the
-- time since cash last went into the bag covers the distance from there at the fastest car's nitro
-- speed (+30%). A cheat who teleports from a robbery onto the pad still has to wait out that trip,
-- wanted, before the bag banks and the heat clears.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local HideoutService = {}

local CHECK_EVERY = 0.5
local MAX_TRIP_SPEED = Vehicles.TopSpeed * (Vehicles.Defaults.NitroSpeed or 1.2) * 1.3 -- studs/s
local TRIP_SLACK = 100 -- studs: robbing and hideout spots aren't points
local lastWarn = {}
local lootFrom = {} -- [player] = { pos, t }: where and when cash last went into their bag

local function hideouts()
	local list = {}
	for _, m in ipairs(Workspace.Spawns:GetChildren()) do
		if m:IsA("Model") and m.Name == "Hideout" and m.PrimaryPart then
			table.insert(list, m.PrimaryPart)
		end
	end
	return list
end

-- Inside the pad's footprint and within 30 studs above it.
function HideoutService.IsInside(position)
	for _, pad in ipairs(hideouts()) do
		local rel = pad.CFrame:PointToObjectSpace(position)
		if math.abs(rel.X) <= pad.Size.X / 2 and math.abs(rel.Z) <= pad.Size.Z / 2 and rel.Y > -5 and rel.Y < 30 then
			return true
		end
	end
	return false
end

-- Remember where the bag last grew (a robbery, a delivered hot car, a grabbed duffel).
local function watchBag(player)
	local last = EconomyService.GetCarried(player)
	player:GetAttributeChangedSignal("Carried"):Connect(function()
		local carried = EconomyService.GetCarried(player)
		if carried > last then
			local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if r then
				lootFrom[player] = { pos = r.Position, t = os.clock() }
			end
		end
		last = carried
	end)
end

-- Got here faster than any car could have since the bag last grew? (Flat distance: ramps and
-- bridges don't matter.)
local function arrivedTooFast(player, position)
	local from = lootFrom[player]
	if not from then
		return false
	end
	local d = position - from.pos
	local flat = Vector3.new(d.X, 0, d.Z).Magnitude
	return flat > TRIP_SLACK + MAX_TRIP_SPEED * (os.clock() - from.t)
end

local function clearHeat(player)
	local ok, HeatService = pcall(require, ServerScriptService.Services:FindFirstChild("HeatService"))
	if ok and HeatService and HeatService.Clear then
		HeatService.Clear(player, "hideout")
	else
		player:SetAttribute("Heat", 0)
		player:SetAttribute("HeatSpotted", false)
	end
end

function HideoutService.Init()
	local notify = Remotes.Event("Notify")
	local banked = Remotes.Event("Banked")
	Players.PlayerAdded:Connect(watchBag)
	for _, p in ipairs(Players:GetPlayers()) do
		watchBag(p)
	end
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			for _, player in ipairs(Players:GetPlayers()) do
				-- InHideout drives the client's WARDROBE button.
				local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local inside = r ~= nil and player:GetAttribute("Side") == "Civilian" and HideoutService.IsInside(r.Position)
				if player:GetAttribute("InHideout") ~= inside then
					player:SetAttribute("InHideout", inside)
				end
				if player:GetAttribute("Side") == "Civilian" and EconomyService.GetCarried(player) > 0 then
					local root = r
					if root and inside then
						if player:GetAttribute("HeatSpotted") then
							local t = os.clock()
							if not lastWarn[player] or t - lastWarn[player] > 6 then
								lastWarn[player] = t
								notify:FireClient(player, "ShakeCopsFirst")
							end
						elseif not arrivedTooFast(player, root.Position) then -- else wait: checked again next tick
							local amount = EconomyService.BankCarried(player, "hideout")
							clearHeat(player)
							player:SetAttribute("Escapes", (player:GetAttribute("Escapes") or 0) + 1)
							banked:FireClient(player, amount)
						end
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastWarn[p] = nil
		lootFrom[p] = nil
	end)
end

return HideoutService
