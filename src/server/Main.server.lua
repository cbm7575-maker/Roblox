-- Main (Script, ServerScriptService.Main): starts every server service in order.
-- Each service is a ModuleScript in ServerScriptService.Services with an optional Init().

local ServerScriptService = game:GetService("ServerScriptService")

local ORDER = {
	"WorldService",
	"VehicleService",
	"VehicleGuard",
	"TeamService",
	"EconomyService",
	"DataService",
	"GarageService",
	"TutorialService",
	"ShopService",
	"DailyService",
	"ProgressService",
	"CrewService",
	"EventService",
	"MissionService",
	"PedService",
	"SettingsService",
	"HeatService",
	"HeistService",
	"HideoutService",
	"ArrestService",
	"PrisonService",
	"RobberToolsService",
	"AIPoliceService",
	"DisguiseService",
	"CarBoostService",
	"RaceService",
	"StuntService",
	"DriftService",
	"JobService",
	"CarMeetService", -- before MapService: it builds the lot MapService lists
	"MapService",
	"CollectibleService", -- after every service that builds props, so placement sees them
	"DebugService", -- Studio only
}

local services = ServerScriptService:WaitForChild("Services")
for _, name in ipairs(ORDER) do
	local module = services:WaitForChild(name, 5)
	if not module then
		warn("[Main] missing service " .. name)
		continue
	end
	local ok, err = pcall(function()
		local service = require(module)
		if service.Init then
			service.Init()
		end
	end)
	if not ok then
		warn("[Main] " .. name .. " failed to start: " .. tostring(err))
	end
end
print("[Main] server ready")
