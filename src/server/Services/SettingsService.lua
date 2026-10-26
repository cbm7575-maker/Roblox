-- SettingsService (ModuleScript, ServerScriptService.Services.SettingsService)
-- Saves each player's phone SETTINGS (music / effects volume, performance mode, passive mode) and the
-- offer cards they hid, in their profile (data.settings) so they follow them to any device. Mirrored to
-- the player attribute "Settings" (JSON).
-- Remote SaveSettings(table): only known keys with valid values are kept.
--   Passive (bool) is not simply stored: CombatService decides whether it may change right now (heat,
--   bag, fights, cooldowns), saves it and sets the player attribute "Passive" (the real state).
--   HideOffer_<key> (bool, one per Config.Shop.Offers key): "Don't show again" on an offer card
--   (OfferClient). Keys for offers that don't exist are ignored.
-- SettingsService.Mirror(player): re-write the "Settings" attribute after data.settings changed.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shop = require(ReplicatedStorage.Shared.Config.Shop)
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

function SettingsService.Mirror(player)
	local data = DataService.Get(player)
	if data then
		player:SetAttribute("Settings", HttpService:JSONEncode(data.settings or {}))
	end
end

-- Passive mode belongs to CombatService (it starts after us, so it's found when the request comes).
local function requestPassive(player, on)
	local module = ServerScriptService.Services:FindFirstChild("CombatService")
	local ok, combat = pcall(require, module)
	if ok and type(combat) == "table" and combat.RequestPassive then
		combat.RequestPassive(player, on)
	end
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
		-- Car radio (SoundClient): "off" sticks, and the last station comes back.
		if type(tbl.RadioOff) == "boolean" then
			data.settings.RadioOff = tbl.RadioOff or nil -- on is the default: don't keep it in the save
		end
		local radioStation = tbl.RadioStation
		if type(radioStation) == "number" and radioStation == math.floor(radioStation) and radioStation >= 1 and radioStation <= 16 then
			data.settings.RadioStation = radioStation
		end
		for offerKey in pairs(Shop.Offers) do
			local k = "HideOffer_" .. offerKey
			if type(tbl[k]) == "boolean" then
				data.settings[k] = tbl[k] or nil -- false is the default: don't keep it in the save
			end
		end
		if type(tbl.Passive) == "boolean" then
			requestPassive(player, tbl.Passive)
		end
		SettingsService.Mirror(player)
	end)
	DataService.OnLoaded(function(player, data)
		player:SetAttribute("Settings", HttpService:JSONEncode(data.settings or {}))
	end)
end

return SettingsService
