-- FeedController (ModuleScript, StarterPlayerScripts.Controllers.FeedController)
-- The Coast Feed: short, auto-written posts about what's happening in this server.
-- The server sends event keys + data (never player-typed text), this file turns them into words.
-- Every post goes to the phone's FEED app (FeedController.History, newest last). Only posts that
-- matter to you also pop up as a toast: near you (under NEAR studs, when the post has a Position /
-- Pos), involving you (your name or UserId in it), police dispatch for cops, and the bank vault for
-- citizens who are allowed to rob it. Everything else waits quietly in the FEED app.
--   FeedController.OnPost(fn)  fn(entry) after each post (the phone refreshes its FEED page)
--   FeedController.Unread      posts since the FEED app was last opened; MarkRead() resets it

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
local MINT = Color3.fromRGB(110, 242, 196)

local NEAR = 600 -- studs: closer posts pop up as toasts
local KEEP = 40 -- posts kept for the FEED app

FeedController.History = {} -- { Text, Color, Time (os.time) }, newest last
FeedController.Unread = 0

local listeners = {}

function FeedController.OnPost(fn)
	table.insert(listeners, fn)
end

function FeedController.MarkRead()
	FeedController.Unread = 0
end

local function display(typeId)
	local def = Heists.Types[typeId]
	return def and def.Display or tostring(typeId)
end

-- Is this post near me or about me?
local function relevant(d)
	if d.UserId == player.UserId or d.CopUserId == player.UserId then
		return true
	end
	if d.Name == player.DisplayName or d.Cop == player.DisplayName then
		return true
	end
	local pos = d.Position or d.Pos
	if typeof(pos) == "Vector3" then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude < NEAR then
			return true
		end
	end
	return false
end

local function post(text, color, toast)
	local entry = { Text = text, Color = color, Time = os.time() }
	table.insert(FeedController.History, entry)
	if #FeedController.History > KEEP then
		table.remove(FeedController.History, 1)
	end
	FeedController.Unread += 1
	if toast then
		NotifyController.Show(text, color)
	end
	for _, fn in ipairs(listeners) do
		task.spawn(fn, entry)
	end
end

local function isCop()
	return player:GetAttribute("Side") == "Cop"
end

local HANDLERS = {
	HeistOpen = function(d)
		if player:GetAttribute("Side") == "Civilian" then
			-- Worth a toast for anyone free to act on it (not while already on the run).
			post("@CoastFeed: " .. display(d.Type) .. " just opened for business...", ORANGE,
				relevant(d) or (player:GetAttribute("Heat") or 0) <= 0)
		end
	end,
	HeistAlarm = function(d)
		if isCop() then
			post("DISPATCH: alarm at " .. display(d.Type) .. "! Respond now.", CYAN, true)
		else
			post("@CoastFeed: alarms ringing at " .. display(d.Type) .. "!", PINK, relevant(d))
		end
	end,
	BankSoon = function(d)
		local rank = Heists.Types.CoastalBank and Heists.Types.CoastalBank.MinRank or 0
		local mine = player:GetAttribute("Side") == "Civilian" and (player:GetAttribute("CivRank") or 1) >= rank
		post("@CoastFeed: the Coastal Bank vault unlocks in 60 seconds...", GOLD, mine or relevant(d))
	end,
	BankOpen = function(d)
		local rank = Heists.Types.CoastalBank and Heists.Types.CoastalBank.MinRank or 0
		local mine = player:GetAttribute("Side") == "Civilian" and (player:GetAttribute("CivRank") or 1) >= rank
		post("@CoastFeed: the Coastal Bank vault is OPEN. Crews, go!", GOLD, mine or isCop() or relevant(d))
	end,
	Arrest = function(d)
		post("@CoastFeed: " .. tostring(d.Name) .. " was just cuffed by " .. tostring(d.Cop) .. ".", CYAN, relevant(d))
	end,
	Escaped = function(d)
		post("@CoastFeed: " .. tostring(d.Name) .. " gave the cops the slip!", PINK, relevant(d))
	end,
	TrackerPing = function(d)
		if isCop() then
			post("DISPATCH: stolen " .. tostring(d.Model) .. " tracker is pinging. Check your map!", CYAN, true)
		end
	end,
	CarDelivered = function(d)
		post("@CoastFeed: somebody's " .. tostring(d.Model) .. " just vanished at the Docks...", ORANGE, relevant(d))
	end,
	Breakout = function(d)
		post("@CoastFeed: BREAKOUT at Saltmarsh Prison! " .. tostring(d.Name) .. " is on the run.", ORANGE,
			isCop() or relevant(d))
	end,
	-- Florida moments (EventService)
	Event = function(d)
		-- Florida moments and car meet calls are server-wide invitations (a few minutes apart): always toast.
		post("@CoastFeed: " .. tostring(d.Text), MINT, true)
	end,
	EventDone = function(d)
		post("@CoastFeed: " .. tostring(d.Name) .. " " .. tostring(d.Text) .. "!", MINT, relevant(d))
	end,
}

function FeedController.Init()
	Remotes.OnClient("Feed", function(kind, data)
		local h = HANDLERS[kind]
		if h then
			local ok, err = pcall(h, type(data) == "table" and data or {})
			if not ok then
				warn("[FeedController] " .. tostring(err))
			end
		end
	end)
end

return FeedController
