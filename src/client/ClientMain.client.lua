-- ClientMain (LocalScript, StarterPlayerScripts.ClientMain): starts every client controller.
-- In Studio only, number keys spawn test cars: 1-9, 0, -, = map to the 12 vehicles in Config order.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local controllers = script.Parent:WaitForChild("Controllers")

local ORDER = {
	"DriveController",
	"VehicleVisuals",
	"DriveUI",
	"NotifyController",
	"SettingsClient",
	"SoundClient",
	"TeamUI",
	"HUDController",
	"HeistClient",
	"FeedController",
	"LawClient",
	"WardrobeUI",
	"ActivityClient",
	"SkyClient",
	"GPSClient",
	"PhoneUI",
	"TrafficClient",
	"TutorialClient",
	"ShopClient",
	"MinimapClient",
	"ProgressClient",
	"CollectibleClient",
	"CrewClient",
	"MissionClient",
	"ObjectiveClient",
	"PedClient",
	"DistrictClient",
}

for _, name in ipairs(ORDER) do
	local module = controllers:WaitForChild(name, 5)
	if not module then
		warn("[ClientMain] missing controller " .. name)
		continue
	end
	local ok, err = pcall(function()
		local c = require(module)
		if c.Init then
			c.Init()
		end
	end)
	if not ok then
		warn("[ClientMain] " .. name .. " failed to start: " .. tostring(err))
	end
end

if RunService:IsStudio() then
	local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
	local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
	local spawnCar = Remotes.Event("RequestSpawnCar")
	local keys = {
		Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
		Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine, Enum.KeyCode.Zero, Enum.KeyCode.Minus, Enum.KeyCode.Equals,
	}
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		for i, key in ipairs(keys) do
			if input.KeyCode == key and Vehicles.List[i] then
				spawnCar:FireServer(Vehicles.List[i].Id)
			end
		end
	end)
	print("[ClientMain] Studio test keys: 1-9, 0, -, = spawn cars; E enters, F exits, Space drifts, Shift nitro, R flips")
end
print("[ClientMain] client ready for " .. Players.LocalPlayer.Name)
