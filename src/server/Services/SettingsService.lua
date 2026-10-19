-- SettingsService (ModuleScript, ServerScriptService.Services.SettingsService)
-- Saves each player's phone SETTINGS (music / effects volume, performance mode) in their profile
-- (data.settings) so they follow them to any device. Mirrored to the player attribute "Settings" (JSON).
-- Remote SaveSettings(table): only known keys with valid values are kept.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)

local SettingsService = {}

-- Volumes snap to quarter steps (0, 0.25 ... 1); anything else (NaN, strings) is ignored.
local function volume(v)
	if type(v) ~= "number" or v ~= v then
		return nil
	end
	return math.clamp(math.floor(v * 4 + 0.5) / 4, 0, 1)
end

function SettingsService.Init()
	Remotes.Event("SaveSettings").OnServerEvent:Connect(function(player, tbl)
		if not RateLimit.Allow(player, "Settings", 2, 4) or type(tbl) ~= "table" then
			return
		end
		local data = DataService.Get(player)
		if not data then
			return
		end
		data.settings = data.settings or {}
		for _, key in ipairs({ "Music", "Effects" }) do
			local v = volume(tbl[key])
			if v then
				data.settings[key] = v
			end
		end
		if type(tbl.Performance) == "boolean" then
			data.settings.Performance = tbl.Performance
		end
		player:SetAttribute("Settings", HttpService:JSONEncode(data.settings))
	end)
	DataService.OnLoaded(function(player, data)
		player:SetAttribute("Settings", HttpService:JSONEncode(data.settings or {}))
	end)
end

return SettingsService
