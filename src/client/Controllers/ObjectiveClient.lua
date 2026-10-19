-- ObjectiveClient (ModuleScript, StarterPlayerScripts.Controllers.ObjectiveClient)
-- One line of "what now" in the top bar slot (HUDController.TopBar) whenever no tutorial step and no
-- mission is showing, for citizens with something to finish:
--   a bag, no heat   "Bank your $1,200 at the Hideout · 1.2 km"  (or at a home you own, if nearer)
--   wanted + a bag   "Lose the cops, then bank your $1,200"
--   wanted, no bag   "Lose the cops: break line of sight"
-- Tap it: the GPS routes to the nearest place to bank (or, with no bag, a tip on hiding).
-- Hidden during races, job shifts and missions, and for cops and prisoners. Updates twice a second.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local GPSClient = require(script.Parent:WaitForChild("GPSClient"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))
local TutorialClient = require(script.Parent:WaitForChild("TutorialClient"))

local player = Players.LocalPlayer

local ObjectiveClient = {}

local PINK = Color3.fromRGB(255, 62, 165)
local GOLD = Color3.fromRGB(255, 214, 10)

local bar
local placesRaw, hideouts -- cached decode of the "Places" attribute

local function properties()
	local m = ReplicatedStorage.Shared.Config:FindFirstChild("Properties")
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, mod = pcall(require, m)
	return ok and type(mod) == "table" and type(mod.ById) == "table" and mod or nil
end

local function hideoutSpots()
	local raw = ReplicatedStorage:GetAttribute("Places") or "[]"
	if raw ~= placesRaw then
		placesRaw, hideouts = raw, {}
		local ok, list = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		for _, p in ipairs(ok and type(list) == "table" and list or {}) do
			if p.n == "Hideout" and p.x and p.z then
				table.insert(hideouts, { name = "Hideout", pos = Vector3.new(p.x, 0, p.z) })
			end
		end
	end
	return hideouts
end

-- The nearest place to bank: the Hideout, or (with no heat: their pads need it) a home you own.
local function bankSpot(wanted)
	local spots = table.clone(hideoutSpots())
	local P = not wanted and properties()
	if P then
		for id in string.gmatch(player:GetAttribute("OwnedProps") or "", "[^,]+") do
			local def = P.ById[id]
			if def and typeof(def.Pos) == "Vector3" then
				table.insert(spots, { name = tostring(def.Name), pos = def.Pos })
			end
		end
	end
	local best, bestD
	for _, s in ipairs(spots) do
		local d = GPSClient.Distance(s.pos) or 0
		if not bestD or d < bestD then
			best, bestD = s, d
		end
	end
	return best, bestD
end

local function busy()
	return player:GetAttribute("Mission") ~= nil or player:GetAttribute("RacingId") ~= nil
		or player:GetAttribute("JobKind") ~= nil
end

local function update()
	local carried = player:GetAttribute("Carried") or 0
	local wanted = (player:GetAttribute("Heat") or 0) > 0
	local show = player:GetAttribute("Side") == "Civilian" and player:GetAttribute("HasPicked") == true
		and (carried > 0 or wanted) and not busy() and not TutorialClient.IsShowing()
	bar.Frame.Visible = show
	if not show then
		return
	end
	local text
	if wanted and carried > 0 then
		text = "Lose the cops, then bank your " .. HUDController.Money(carried)
	elseif wanted then
		text = "Lose the cops: break line of sight"
	else
		local spot, d = bankSpot(false)
		local where = spot and (spot.name == "Hideout" and " at the Hideout" or (" at " .. spot.name)) or ""
		text = "Bank your " .. HUDController.Money(carried) .. where .. (d and ("  ·  " .. GPSClient.FormatDistance(d)) or "")
	end
	local full = '<font color="#FFD60A">NOW</font>  ' .. text
	bar.SetText(full)
	bar.Stroke.Color = wanted and PINK or GOLD
end

local function onTap()
	local carried = player:GetAttribute("Carried") or 0
	local wanted = (player:GetAttribute("Heat") or 0) > 0
	if carried <= 0 then
		NotifyController.Show("Get out of sight: behind buildings, under bridges. Hollow stars = they lost you.", PINK)
		return
	end
	local spot = bankSpot(wanted)
	if spot then
		GPSClient.SetTarget(spot.name, spot.pos)
	else
		NotifyController.Show("Can't find the Hideout yet. Try again in a moment!", GOLD)
	end
end

function ObjectiveClient.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Objective"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	bar = HUDController.TopBar(gui, "Objective", GOLD)
	bar.SetInsets(18, 18)
	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 3
	tap.Parent = bar.Frame
	tap.Activated:Connect(onTap)
	task.spawn(function()
		while true do
			local ok, err = pcall(update)
			if not ok then
				warn("[ObjectiveClient] " .. tostring(err))
			end
			task.wait(0.5)
		end
	end)
end

return ObjectiveClient
