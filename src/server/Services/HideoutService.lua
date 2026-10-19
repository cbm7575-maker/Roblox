-- HideoutService (ModuleScript, ServerScriptService.Services.HideoutService)
-- Hideouts (models named "Hideout" in Workspace.Spawns, with a Pad): where Wanted players bank loot.
-- A robber inside a hideout with cash in the bag banks it, as long as no cop can see them right now
-- (HeatSpotted). Banking also clears their heat: they laid low. On foot or in a car both count.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local EconomyService = require(ServerScriptService.Services.EconomyService)

local HideoutService = {}

local CHECK_EVERY = 0.5
local lastWarn = {}

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
						else
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
	end)
end

return HideoutService
