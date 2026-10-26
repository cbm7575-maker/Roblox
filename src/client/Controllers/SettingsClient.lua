-- SettingsClient (ModuleScript, StarterPlayerScripts.Controllers.SettingsClient)
-- The player's settings (saved on the server by SettingsService, player attribute "Settings"):
--   Music        0..1  car radio and score       (SoundGroup "NCMusic"; also Config.Sounds effects with
--                      Group = "Music", e.g. HeistMusic)
--   Effects      0..1  every other sound         (SoundGroup "NCEffects")
--   Performance  bool  fewer traffic cars and pedestrians and no night window glow (SkyClient), for
--                      older phones (on by default on touch screens until the player chooses)
--   Passive      bool  can't punch or zap, can't be punched or zapped. The server decides (it refuses
--                      while you're wanted, carrying a bag, mid-fight or on cooldown), so Get reads the
--                      player attribute "Passive" and Set only asks; the attribute changes when it's done.
--   HideOffer_<key> bool "Don't show again" on that offer card (OfferClient; keys from Config.Shop.Offers).
--                      Unset = offers show.
--   RadioOff     bool  the car radio is switched off (SoundClient). Unset = on.
--   RadioStation 1..n  the station the radio was last on (index into Config.Sounds.Radio).
-- SettingsClient.Get(key), SettingsClient.Set(key, value), SettingsClient.Group("Music"|"Effects").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)

local player = Players.LocalPlayer

local SettingsClient = {}

local DEFAULTS = {
	Music = 0.75,
	Effects = 1,
	Performance = UserInputService.TouchEnabled and not UserInputService.MouseEnabled,
}

local values = {}
local groups = {}

function SettingsClient.Group(name)
	local g = groups[name]
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = "NC" .. name
		g.Parent = SoundService
		groups[name] = g
	end
	return g
end

function SettingsClient.Get(key)
	if key == "Passive" then
		return player:GetAttribute("Passive") == true
	end
	local v = values[key]
	if v == nil then
		return DEFAULTS[key]
	end
	return v
end

local function apply()
	SettingsClient.Group("Music").Volume = SettingsClient.Get("Music")
	SettingsClient.Group("Effects").Volume = SettingsClient.Get("Effects")
end

function SettingsClient.Set(key, value)
	if key == "Passive" then
		-- Only a request: never kept in `values`, so later volume saves can't re-send an old answer.
		task.spawn(function()
			Remotes.Event("SaveSettings"):FireServer({ Passive = value == true })
		end)
		return
	end
	values[key] = value
	apply()
	Remotes.Event("SaveSettings"):FireServer(values)
end

local function load()
	local ok, t = pcall(function()
		return HttpService:JSONDecode(player:GetAttribute("Settings") or "{}")
	end)
	if ok and type(t) == "table" then
		for k, v in pairs(t) do
			if k ~= "Passive" then -- the attribute "Passive" is the real state
				values[k] = v
			end
		end
	end
	apply()
end

function SettingsClient.Init()
	load()
	player:GetAttributeChangedSignal("Settings"):Connect(load)
end

return SettingsClient
