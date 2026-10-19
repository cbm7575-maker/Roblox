-- SettingsClient (ModuleScript, StarterPlayerScripts.Controllers.SettingsClient)
-- The player's settings (saved on the server by SettingsService, player attribute "Settings"):
--   Music        0..1  car radio volume          (SoundGroup "NCMusic")
--   Effects      0..1  every other sound         (SoundGroup "NCEffects")
--   Performance  bool  fewer traffic cars and pedestrians for older phones (on by default on touch
--                      screens until the player chooses)
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
			values[k] = v
		end
	end
	apply()
end

function SettingsClient.Init()
	load()
	player:GetAttributeChangedSignal("Settings"):Connect(load)
end

return SettingsClient
