-- Main (Script, ServerScriptService.Main): starts every server service in order.
-- Each service is a ModuleScript in ServerScriptService.Services with an optional Init().

local ServerScriptService = game:GetService("ServerScriptService")

local ORDER = {
	"WorldService",
	"VehicleService",
	"VehicleGuard",
	"TeamService",
	"AnimationService", -- walk / run / idle sets on every character (Config.Animations)
	"EconomyService",
	"DataService",
	"GarageService",
	"TutorialService",
	"ShopService",
	"DailyService",
	"ProgressService",
	"JourneyService", -- goal chains after the tutorial (Road to the Coast)
	"CrewService",
	"FriendsService", -- invite / join friends, co-play bonus
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
	"CarjackService", -- street carjacking (moving traffic + car-park break-ins)
	"BigScoreService", -- The Big Score crew heist: builds Workspace.BigScore, runs the armored van
	"RagdollService", -- limp falls for players + the "Pose" attribute (before ImpactService, which calls it)
	"ImpactService", -- car hits, knockdowns, GET IN
	"PropService", -- street furniture cars plow through (collision group "Props", remote PropHit)
	"CombatService", -- guns and knockouts + the Coast Arms shop (before MapService so the GPS lists the shop)
	"RaceService",
	"StuntService",
	"DriftService",
	"JobService",
	"CarMeetService", -- before MapService: it builds the lot MapService lists
	"DealershipService", -- before MapService: AutoNeon Motors + Marina Boat Sales
	"HousingService", -- homes for sale (after GarageService / VehicleService)
	"ApartmentService", -- apartment towers you can tour (after the lots it keeps clear of; MapService lists them)
	"CityDressingService", -- Look 4.0 billboards, road wear and tall palms (after every lot it keeps clear of)
	"MapService",
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
