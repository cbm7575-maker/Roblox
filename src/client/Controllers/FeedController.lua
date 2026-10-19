-- FeedController (ModuleScript, StarterPlayerScripts.Controllers.FeedController)
-- The Coast Feed: short, auto-written posts about what's happening in this server.
-- The server sends event keys + data (never player-typed text), this file turns them into words.
-- For now posts appear as toasts; the phone's Feed app (step 4.3) will list them too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Heists = require(ReplicatedStorage.Shared.Config.Heists)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local FeedController = {}

local PINK = Color3.fromRGB(255, 62, 165)
local CYAN = Color3.fromRGB(34, 225, 255)
local ORANGE = Color3.fromRGB(255, 138, 61)
local GOLD = Color3.fromRGB(255, 214, 10)

FeedController.History = {} -- newest last, for the phone Feed app

local function display(typeId)
	local def = Heists.Types[typeId]
	return def and def.Display or typeId
end

local function post(text, color)
	table.insert(FeedController.History, { Text = text, Time = os.time() })
	if #FeedController.History > 30 then
		table.remove(FeedController.History, 1)
	end
	NotifyController.Show(text, color)
end

local HANDLERS = {
	HeistOpen = function(d)
		if player:GetAttribute("Side") == "Civilian" then
			post("@CoastFeed: " .. display(d.Type) .. " just opened for business...", ORANGE)
		end
	end,
	HeistAlarm = function(d)
		if player:GetAttribute("Side") == "Cop" then
			post("DISPATCH: alarm at " .. display(d.Type) .. "! Respond now.", CYAN)
		else
			post("@CoastFeed: alarms ringing at " .. display(d.Type) .. "!", PINK)
		end
	end,
	BankSoon = function()
		post("@CoastFeed: the Coastal Bank vault unlocks in 60 seconds...", GOLD)
	end,
	BankOpen = function()
		post("@CoastFeed: the Coastal Bank vault is OPEN. Crews, go!", GOLD)
	end,
	Arrest = function(d)
		post("@CoastFeed: " .. d.Name .. " was just cuffed by " .. d.Cop .. ".", CYAN)
	end,
	Escaped = function(d)
		post("@CoastFeed: " .. d.Name .. " gave the cops the slip!", PINK)
	end,
	TrackerPing = function(d)
		if player:GetAttribute("Side") == "Cop" then
			post("DISPATCH: stolen " .. d.Model .. " tracker is pinging. Check your map!", CYAN)
		end
	end,
	CarDelivered = function(d)
		post("@CoastFeed: somebody's " .. d.Model .. " just vanished at the Docks...", ORANGE)
	end,
	Breakout = function(d)
		post("@CoastFeed: BREAKOUT at Saltmarsh Prison! " .. d.Name .. " is on the run.", ORANGE)
	end,
	-- Florida moments (EventService)
	Event = function(d)
		post("@CoastFeed: " .. d.Text, Color3.fromRGB(110, 242, 196))
	end,
	EventDone = function(d)
		post("@CoastFeed: " .. d.Name .. " " .. d.Text .. "!", Color3.fromRGB(110, 242, 196))
	end,
}

function FeedController.Init()
	Remotes.OnClient("Feed", function(kind, data)
		local h = HANDLERS[kind]
		if h then
			h(data or {})
		end
	end)
end

return FeedController
