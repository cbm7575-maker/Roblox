-- HeistClient (ModuleScript, StarterPlayerScripts.Controllers.HeistClient)
-- Client side of heists:
--   * Rob prompts show only for citizens on foot, and only while the site is Robbable (local-only
--     toggle; the server re-checks everything when a robbery finishes and refuses seated players, so
--     a prompt in the car would only waste a long hold).
--   * Site signs read "OPEN" or "CLOSED 2:10"; alarms flash red for cops.
--   * Result toasts ("+$1,200 in your bag").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local HeistClient = {}

local ORANGE = Color3.fromRGB(255, 138, 61)
local GREY = Color3.fromRGB(170, 170, 185)
local RED = Color3.fromRGB(255, 60, 60)

local function now()
	return Workspace:GetServerTimeNow()
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function onFoot()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.SeatPart == nil
end

local function updateSite(site, canRob)
	local robbable = site:GetAttribute("Robbable") == true
	for _, name in ipairs({ "RobPrompt", "PrepPrompt" }) do
		local prompt = site:FindFirstChild(name, true)
		if prompt and prompt:IsA("ProximityPrompt") then
			local show = robbable and canRob
			if prompt.Enabled ~= show then
				prompt.Enabled = show
			end
		end
	end
	local pad = site.PrimaryPart
	local gui = pad and pad:FindFirstChildOfClass("BillboardGui")
	local label = gui and gui:FindFirstChildOfClass("TextLabel")
	if not label then
		return
	end
	local name = site:GetAttribute("Display") or site.Name
	local alarm = now() < (site:GetAttribute("AlarmUntil") or 0)
	if alarm and player:GetAttribute("Side") == "Cop" then
		label.Text = name .. "  ALARM!"
		label.TextColor3 = (math.floor(now() * 3) % 2 == 0) and RED or Color3.new(1, 1, 1)
	elseif robbable then
		label.Text = name .. "  OPEN"
		label.TextColor3 = ORANGE
	elseif site:GetAttribute("TypeOpen") then
		label.Text = name .. "  CLOSED " .. clock((site:GetAttribute("ReopenAt") or 0) - now())
		label.TextColor3 = GREY
	else
		label.Text = name .. "  CLOSED"
		label.TextColor3 = GREY
	end
end

function HeistClient.Init()
	local heists = Workspace:WaitForChild("Heists")
	task.spawn(function()
		while true do
			local canRob = player:GetAttribute("Side") == "Civilian" and onFoot()
			for _, site in ipairs(heists:GetChildren()) do
				if site:GetAttribute("HeistId") then
					local ok, err = pcall(updateSite, site, canRob)
					if not ok then
						warn("[HeistClient] " .. tostring(err))
					end
				end
			end
			task.wait(0.33)
		end
	end)
	Remotes.OnClient("HeistPrep", function(info)
		require(script.Parent:WaitForChild("HUDController")).Stamp("STEP 1 DONE", info.Text, Color3.fromRGB(110, 242, 196))
	end)
	Remotes.OnClient("HeistResult", function(result)
		if result.Payout > 0 then
			NotifyController.Show("+" .. HUDController.Money(result.Payout) .. " in your bag! Get to the hideout.", ORANGE)
		end
		if result.BagFull then
			NotifyController.Show("Bag full! Bank your cash at the hideout.", RED)
		end
	end)
end

return HeistClient
