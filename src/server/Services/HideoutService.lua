-- HideoutService (ModuleScript, ServerScriptService.Services.HideoutService)
-- Hideouts (models named "Hideout" in Workspace.Spawns, with a Pad): where Wanted players bank loot.
-- A civilian inside a hideout, unseen by any cop right now (HeatSpotted false), lays low:
--   * cash in the bag is banked (the "Banked" event), and
--   * any heat is cleared. That counts as an escape (ProgressService "Escape" XP and the "lose the
--     cops" challenge, the Escapes stat), with or without loot; heat from a phone mission's
--     "lose the cops" step (attribute MissionHeat) clears too but earns no escape credit.
-- While a cop can see them they get the "ShakeCopsFirst" toast instead. On foot or in a car both count.

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

-- Laying low with heat > 0 is an escape: read the stars BEFORE clearing them.
local function escape(player)
	local heat = player:GetAttribute("Heat") or 0
	if heat <= 0 then
		return
	end
	if not player:GetAttribute("MissionHeat") then
		player:SetAttribute("Escapes", (player:GetAttribute("Escapes") or 0) + 1)
	end
	-- ProgressService itself skips mission heat (no XP, no challenge).
	local ok, err = pcall(function()
		require(ServerScriptService.Services.ProgressService).Event(player, "Escape", heat)
	end)
	if not ok then
		warn("[HideoutService] " .. tostring(err))
	end
	clearHeat(player)
end

local notify, banked

local function check(player)
	-- InHideout drives the client's WARDROBE button.
	local r = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local inside = r ~= nil and player:GetAttribute("Side") == "Civilian" and HideoutService.IsInside(r.Position)
	if player:GetAttribute("InHideout") ~= inside then
		player:SetAttribute("InHideout", inside)
	end
	local carried = EconomyService.GetCarried(player)
	local heat = player:GetAttribute("Heat") or 0
	if not inside or (carried <= 0 and heat <= 0) then
		return
	end
	if player:GetAttribute("HeatSpotted") then
		local t = os.clock()
		if not lastWarn[player] or t - lastWarn[player] > 6 then
			lastWarn[player] = t
			notify:FireClient(player, "ShakeCopsFirst")
		end
		return
	end
	local amount = carried > 0 and EconomyService.BankCarried(player, "hideout") or 0
	escape(player)
	if amount > 0 then
		banked:FireClient(player, amount)
	elseif heat > 0 then
		notify:FireClient(player, "LostTheCops")
	end
end

function HideoutService.Init()
	notify = Remotes.Event("Notify")
	banked = Remotes.Event("Banked")
	task.spawn(function()
		while true do
			task.wait(CHECK_EVERY)
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(check, player)
				if not ok then
					warn("[HideoutService] " .. tostring(err))
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastWarn[p] = nil
	end)
end

return HideoutService
