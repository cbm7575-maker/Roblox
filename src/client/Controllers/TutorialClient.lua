-- TutorialClient (ModuleScript, StarterPlayerScripts.Controllers.TutorialClient)
-- The "NEXT" pill for new players (Config.Tutorial): what to do next, a SHOW ME button that routes the
-- GPS there, and a small X to skip. Watches for the steps it can see and tells the server
-- (TutorialService checks them). Free-roam players only; cops get their own hints later.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Tutorial = require(ReplicatedStorage.Shared.Config.Tutorial)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local GPSClient = require(script.Parent:WaitForChild("GPSClient"))
local PhoneUI = require(script.Parent:WaitForChild("PhoneUI"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local TutorialClient = {}

local PINK = Color3.fromRGB(255, 62, 165)
local MINT = Color3.fromRGB(110, 242, 196)
local GOLD = Color3.fromRGB(255, 214, 10)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

local pill, textLabel, showButton
local lastSent = 0

local function places()
	local ok, list = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("Places") or "[]")
	end)
	return ok and list or {}
end

local function showMe(target)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local here = root and root.Position or Vector3.zero
	local open = {}
	for id in string.gmatch(ReplicatedStorage:GetAttribute("OpenHeists") or "", "[^,]+") do
		open[id] = true
	end
	local best, bestD
	for _, p in ipairs(places()) do
		local match = (target == "OpenHeist" and p.c == "Heist" and open[p.id]) or p.n == target
		if match then
			local d = (Vector3.new(p.x, 0, p.z) - Vector3.new(here.X, 0, here.Z)).Magnitude
			if not bestD or d < bestD then
				best, bestD = p, d
			end
		end
	end
	if best then
		GPSClient.SetTarget(best.n, Vector3.new(best.x, 0, best.z))
	else
		NotifyController.Show("Nothing open right now. Check again in a moment!", GOLD)
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	pill = Instance.new("Frame")
	pill.Name = "Next"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 98)
	pill.Size = UDim2.new(1, -420, 0, 40) -- leaves room for the left column and the minimap on phones
	pill.BackgroundColor3 = DARK
	pill.BackgroundTransparency = 0.15
	pill.Visible = false
	pill.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = pill
	local s = Instance.new("UIStroke")
	s.Color = GOLD
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = pill
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(520, 40)
	limit.Parent = pill

	textLabel = Instance.new("TextLabel")
	textLabel.Name = "Text"
	textLabel.BackgroundTransparency = 1
	textLabel.Position = UDim2.fromOffset(16, 7)
	textLabel.Size = UDim2.new(1, -150, 0, 26)
	textLabel.Font = FONT
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.RichText = true
	textLabel.Parent = pill

	showButton = Instance.new("TextButton")
	showButton.Name = "ShowMe"
	showButton.AnchorPoint = Vector2.new(1, 0.5)
	showButton.Position = UDim2.new(1, -40, 0.5, 0)
	showButton.Size = UDim2.fromOffset(90, 28)
	showButton.BackgroundColor3 = MINT
	showButton.Font = FONT
	showButton.TextScaled = true
	showButton.TextColor3 = DARK
	showButton.Text = "SHOW ME"
	showButton.Parent = pill
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.5, 0)
	bc.Parent = showButton
	local bp = Instance.new("UIPadding")
	bp.PaddingTop, bp.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)
	bp.Parent = showButton

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, -8, 0.5, 0)
	skip.Size = UDim2.fromOffset(26, 26)
	skip.BackgroundTransparency = 1
	skip.Font = FONT
	skip.TextScaled = true
	skip.TextColor3 = Color3.fromRGB(160, 150, 190)
	skip.Text = "✕"
	skip.Parent = pill
	skip.Activated:Connect(function()
		Remotes.Event("TutorialStep"):FireServer("Skip")
		pill.Visible = false
	end)
end

local function step()
	return player:GetAttribute("TutorialStep")
end

local function refresh()
	local done = step()
	local side = player:GetAttribute("Side")
	local def = done and Tutorial.Steps[done + 1]
	-- Out of the way during races and job shifts (their own banners use the top of the screen).
	local busy = player:GetAttribute("RacingId") ~= nil or player:GetAttribute("JobKind") ~= nil
		or player:GetAttribute("Mission") ~= nil
	pill.Visible = def ~= nil and side == "Civilian" and player:GetAttribute("HasPicked") == true and not busy
	if not def then
		return
	end
	textLabel.Text = string.format('<font color="#FFD60A">NEXT %d/%d</font>  %s', done + 1, #Tutorial.Steps, def.Text)
	showButton.Visible = def.Show ~= nil
end

-- Is the step after `done` complete, as far as this device can tell?
local function reached(def)
	if def.Id == "phone" then
		return PhoneUI.IsOpen()
	elseif def.Id == "car" then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		return hum and hum.SeatPart and hum.SeatPart.Name == "DriverSeat"
	elseif def.Id == "rob" then
		return (player:GetAttribute("Carried") or 0) > 0
	end
	return false
end

function TutorialClient.Init()
	build()
	showButton.Activated:Connect(function()
		local done = step()
		local def = done and Tutorial.Steps[done + 1]
		if def and def.Show then
			showMe(def.Show)
		end
	end)
	refresh()
	for _, a in ipairs({ "TutorialStep", "Side", "HasPicked", "RacingId", "JobKind", "Mission" }) do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	Remotes.OnClient("TutorialDone", function(bonus)
		HUDController.Stamp("WELCOME TO PORT SOLANA", "+" .. HUDController.Money(bonus) .. " welcome bonus", PINK)
		task.delay(3, function()
			NotifyController.Show("Try races, stunt jumps, drifting and taxi shifts: PHONE > GPS > FUN", MINT)
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local done = step()
			local def = done and Tutorial.Steps[done + 1]
			if def and not def.ServerOnly and player:GetAttribute("Side") == "Civilian" and reached(def)
				and os.clock() - lastSent > 1 then
				lastSent = os.clock()
				Remotes.Event("TutorialStep"):FireServer(done + 1)
			end
		end
	end)
end

return TutorialClient
