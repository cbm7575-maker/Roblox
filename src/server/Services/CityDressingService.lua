-- CityDressingService (ModuleScript, ServerScriptService.Services.CityDressingService)
-- Look 4.0 city dressing, built at server start: image billboards over the streets, worn roads (cracks, oil,
-- patches, skids, manholes, storm drains) and tall royal palms along the boulevards. All of it comes from
-- ServerStorage.Tools.Look4 (deterministic: every server gets the same city) with the images in
-- Config.Textures (Billboards, RoadWear) and the palm template ServerStorage.Props.TallPalm.
-- It runs here rather than once in Edit mode because the lots it has to keep clear of are built at start-up
-- (HousingService's homes, BigScoreService's lots, ApartmentService's tower entrances), so it must start after
-- them in Main's ORDER. A failure only costs the dressing: it is caught and logged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Textures = require(ReplicatedStorage.Shared.Config.Textures)

local CityDressingService = {}

function CityDressingService.Init()
	local tools = ServerStorage:FindFirstChild("Tools")
	local look4 = tools and tools:FindFirstChild("Look4")
	if not look4 then
		warn("[CityDressing] ServerStorage.Tools.Look4 is missing: no billboards, road wear or tall palms")
		return
	end
	local props = ServerStorage:FindFirstChild("Props")
	local t0 = os.clock()
	local ok, res = pcall(function()
		return require(look4).Run({
			Billboards = Textures.Billboards,
			Decals = Textures.RoadWear,
			PalmTemplate = props and props:FindFirstChild("TallPalm") or nil,
		})
	end)
	if ok then
		print(string.format("[CityDressing] %s (%.2f s)", tostring(res), os.clock() - t0))
	else
		warn("[CityDressing] failed: " .. tostring(res))
	end
end

return CityDressingService
