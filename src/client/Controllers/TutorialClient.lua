-- TutorialClient (ModuleScript, StarterPlayerScripts.Controllers.TutorialClient)
-- The tutorial bar for new players (Config.Tutorial, run by TutorialService): what to do next in two
-- readable lines (the top bar slot, HUDController.TopBar). SHOW ME, or tapping the words, routes the
-- GPS; the small ✕ at the left skips, but only after a second tap ("Tap ✕ again to skip").
--   * Text follows the device: "tap" on touch, "press E" on keyboard, "press X" on a gamepad.
--   * When a step with a Show target starts and no GPS route is set, it routes there by itself.
--   * Reports what only this device sees (sitting in a driver seat, the phone open); the server
--     re-checks. Rob, escape and bank are the server's to judge.
--   * The first heat during the tutorial gets a WANTED! stamp saying how to lose the cops.
-- Citizens only, and out of the way during races, job shifts and missions.
-- TutorialClient.IsShowing() -> true while the bar is on screen (ObjectiveClient shares the slot).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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
local RED = Color3.fromRGB(230, 60, 70)
local LAVENDER = Color3.fromRGB(160, 150, 190)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

local SKIP_CONFIRM = 3 -- seconds the second tap on ✕ is waited for
local AUTO_EVERY = 3 -- seconds between automatic route attempts (a store may open in a moment)
local CAR_NEAR = 50 -- studs: your car is right there, no route needed

-- Beginner heists when MapService's places don't carry Tier / MinRank / NeedsPrep (ATMs too).
local BEGINNER_NAMES = { ["Glow Mart"] = true, ["Fuel Stop"] = true }

local STEP_INDEX = {}
for i, def in ipairs(Tutorial.Steps) do
	STEP_INDEX[def.Id] = i
end

local bar, showButton, skipButton
local lastSent = {} -- [step id] = os.clock() it was last reported
local skipArmedAt = -math.huge
local routedFor -- step id the GPS was routed for automatically (cleared when the step changes)
local lastAuto = 0
local wantedShown = false
local lastDevice

local function places()
	local ok, list = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("Places") or "[]")
	end)
	return ok and type(list) == "table" and list or {}
end

-- "Touch" | "Keyboard" | "Gamepad": the player's preferred input, else the last one used.
local function device()
	local kind
	pcall(function()
		local pref = UserInputService.PreferredInput
		if pref == Enum.PreferredInput.Touch then
			kind = "Touch"
		elseif pref == Enum.PreferredInput.Gamepad then
			kind = "Gamepad"
		elseif pref == Enum.PreferredInput.KeyboardAndMouse then
			kind = "Keyboard"
		end
	end)
	if kind then
		return kind
	end
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "Touch"
	elseif string.find(last.Name, "Gamepad") then
		return "Gamepad"
	elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	return "Keyboard"
end

local function textFor(def)
	local t = def.Text
	if type(t) == "table" then
		t = t[device()] or t.Touch or ""
	end
	return (string.gsub(t, "{bag}", HUDController.Money(player:GetAttribute("Carried") or 0)))
end

local function currentDef()
	local i = STEP_INDEX[player:GetAttribute("TutorialStep") or ""]
	return i and Tutorial.Steps[i] or nil
end

local function doneSet()
	local set, n = {}, 0
	for id in string.gmatch(player:GetAttribute("TutorialSteps") or "", "[^,]+") do
		set[id] = true
		n += 1
	end
	return set, n
end

local function myCar()
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return nil
	end
	for _, car in ipairs(folder:GetChildren()) do
		if car:IsA("Model") and car.PrimaryPart and car:GetAttribute("OwnerUserId") == player.UserId then
			return car
		end
	end
	return nil
end

-- A heist the tutorial may send a new player to: tier 1, no rank and no prep needed.
local function isBeginner(p)
	if p.Tier ~= nil or p.MinRank ~= nil or p.NeedsPrep ~= nil then
		return (tonumber(p.Tier) or 1) <= 1 and (tonumber(p.MinRank) or 0) <= (player:GetAttribute("CivRank") or 1)
			and not p.NeedsPrep
	end
	local name = tostring(p.n)
	return BEGINNER_NAMES[name] == true or string.sub(name, 1, 4) == "ATM "
end

-- Route the GPS for a step's Show target. auto = the bar did it by itself: stay quiet, no car calls.
-- Returns true when nothing more is needed.
local function showMe(target, auto)
	if target == "MyCar" then
		local car = myCar()
		if car then
			local pos = car:GetPivot().Position
			if auto and (GPSClient.Distance(pos) or 0) < CAR_NEAR then
				return true
			end
			GPSClient.SetTarget("Your car", pos)
			return true
		end
		if not auto then
			-- Not around (or not streamed in): bring it, like the CAR button.
			Remotes.Event("RequestSpawnCar"):FireServer(player:GetAttribute("LastCar") or "Palmetto")
			NotifyController.Show("Calling your car... look for it nearby!", MINT)
		end
		return false
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local here = root and root.Position or Vector3.zero
	local open = {}
	for id in string.gmatch(ReplicatedStorage:GetAttribute("OpenHeists") or "", "[^,]+") do
		open[id] = true
	end
	local best, bestD
	for _, p in ipairs(places()) do
		local match
		if target == "Beginner" then
			match = p.c == "Heist" and open[p.id] and isBeginner(p)
		else
			match = p.n == target
		end
		if match and p.x and p.z then
			local d = (Vector3.new(p.x, 0, p.z) - Vector3.new(here.X, 0, here.Z)).Magnitude
			if not bestD or d < bestD then
				best, bestD = p, d
			end
		end
	end
	if best then
		GPSClient.SetTarget(best.n, Vector3.new(best.x, 0, best.z))
		return true
	end
	if not auto then
		NotifyController.Show(target == "Beginner" and "No beginner store is open right now. Check again in a moment!"
			or "Can't find that place yet. Try again in a moment!", GOLD)
	end
	return false
end

local function refresh()
	local def = currentDef()
	-- Out of the way during races, job shifts and missions (their own banners use the top of the screen).
	local busy = player:GetAttribute("RacingId") ~= nil or player:GetAttribute("JobKind") ~= nil
		or player:GetAttribute("Mission") ~= nil
	local visible = def ~= nil and player:GetAttribute("Side") == "Civilian" and player:GetAttribute("HasPicked") == true
		and not busy
	bar.Frame.Visible = visible
	if not visible or not def then
		return
	end
	if os.clock() - skipArmedAt < SKIP_CONFIRM then
		bar.SetText("Tap ✕ again to skip the tutorial (no " .. HUDController.Money(Tutorial.Bonus) .. " bonus)")
		skipButton.BackgroundColor3 = RED
		skipButton.TextColor3 = Color3.new(1, 1, 1)
		showButton.Visible = false
		bar.SetInsets(48, 18)
		return
	end
	skipButton.BackgroundColor3 = DARK
	skipButton.TextColor3 = LAVENDER
	local _, n = doneSet()
	showButton.Visible = def.Show ~= nil
	-- Room for SHOW ME only while it's there.
	bar.SetInsets(48, def.Show and 102 or 18)
	bar.SetText(string.format('<font color="#FFD60A">%d/%d</font>  %s', math.min(n + 1, #Tutorial.Steps),
		#Tutorial.Steps, textFor(def)))
end

function TutorialClient.IsShowing()
	return bar ~= nil and bar.Frame.Visible
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	bar = HUDController.TopBar(gui, "Next", GOLD)

	-- Tapping the words does what SHOW ME does (a bigger target for thumbs).
	local tap = Instance.new("TextButton")
	tap.Name = "Tap"
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 1
	tap.Parent = bar.Frame

	skipButton = Instance.new("TextButton")
	skipButton.Name = "Skip"
	skipButton.AnchorPoint = Vector2.new(0, 0.5)
	skipButton.Position = UDim2.new(0, 10, 0.5, 0)
	skipButton.Size = UDim2.fromOffset(30, 30)
	skipButton.BackgroundColor3 = DARK
	skipButton.Font = FONT
	skipButton.TextScaled = true
	skipButton.TextColor3 = LAVENDER
	skipButton.Text = "✕"
	skipButton.ZIndex = 3
	skipButton.Parent = bar.Frame
	local kc = Instance.new("UICorner")
	kc.CornerRadius = UDim.new(0.5, 0)
	kc.Parent = skipButton
	local kp = Instance.new("UIPadding")
	kp.PaddingTop, kp.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	kp.Parent = skipButton

	showButton = Instance.new("TextButton")
	showButton.Name = "ShowMe"
	showButton.AnchorPoint = Vector2.new(1, 0.5)
	showButton.Position = UDim2.new(1, -10, 0.5, 0)
	showButton.Size = UDim2.fromOffset(84, 34)
	showButton.BackgroundColor3 = MINT
	showButton.Font = FONT
	showButton.TextScaled = true
	showButton.TextColor3 = DARK
	showButton.Text = "SHOW ME"
	showButton.ZIndex = 3
	showButton.Parent = bar.Frame
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0.5, 0)
	bc.Parent = showButton
	local bp = Instance.new("UIPadding")
	bp.PaddingTop, bp.PaddingBottom = UDim.new(0, 7), UDim.new(0, 7)
	bp.PaddingLeft, bp.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
	bp.Parent = showButton

	local function onShow()
		local def = currentDef()
		if def and def.Show and os.clock() - skipArmedAt >= SKIP_CONFIRM then
			showMe(def.Show, false)
		end
	end
	showButton.Activated:Connect(onShow)
	tap.Activated:Connect(onShow)
	skipButton.Activated:Connect(function()
		if os.clock() - skipArmedAt < SKIP_CONFIRM then
			skipArmedAt = -math.huge
			Remotes.Event("TutorialStep"):FireServer("Skip")
			bar.Frame.Visible = false
			return
		end
		skipArmedAt = os.clock()
		refresh()
		task.delay(SKIP_CONFIRM + 0.05, refresh)
	end)
end

-- Steps only this device can see, checked whether or not they're next (early ones count too).
local CLIENT_CHECKS = {
	car = function()
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		return seat ~= nil and seat.Name == "DriverSeat"
	end,
	phone = function()
		local ok, open = pcall(PhoneUI.IsOpen)
		return ok and open == true
	end,
}

local function tick()
	local id = player:GetAttribute("TutorialStep")
	if not id or id == "done" or player:GetAttribute("Side") ~= "Civilian" then
		return
	end
	local done = doneSet()
	for stepId, check in pairs(CLIENT_CHECKS) do
		if not done[stepId] and os.clock() - (lastSent[stepId] or 0) > 2 and check() then
			lastSent[stepId] = os.clock()
			Remotes.Event("TutorialStep"):FireServer(stepId)
		end
	end
	-- A step with a target just started and the GPS is free: route it.
	local def = currentDef()
	if def and def.Show and routedFor ~= def.Id and bar.Frame.Visible and GPSClient.Target() == nil
		and os.clock() - lastAuto > AUTO_EVERY then
		lastAuto = os.clock()
		if showMe(def.Show, true) then
			routedFor = def.Id
		end
	end
end

function TutorialClient.Init()
	build()
	refresh()
	lastDevice = device()
	for _, a in ipairs({ "TutorialSteps", "Side", "HasPicked", "RacingId", "JobKind", "Mission", "Carried" }) do
		player:GetAttributeChangedSignal(a):Connect(refresh)
	end
	player:GetAttributeChangedSignal("TutorialStep"):Connect(function()
		routedFor = nil -- a new step: it may route by itself again
		lastAuto = 0
		refresh()
	end)
	-- Re-word the bar when the player switches device (keyboard <-> gamepad, say).
	local function onInput()
		local d = device()
		if d ~= lastDevice then
			lastDevice = d
			refresh()
		end
	end
	UserInputService.LastInputTypeChanged:Connect(onInput)
	pcall(function()
		UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(onInput)
	end)
	-- First heat in the tutorial: say what the stars mean.
	local lastHeat = player:GetAttribute("Heat") or 0
	player:GetAttributeChangedSignal("Heat"):Connect(function()
		local heat = player:GetAttribute("Heat") or 0
		local step = player:GetAttribute("TutorialStep")
		if heat > 0 and lastHeat <= 0 and not wantedShown and step and step ~= "done" then
			wantedShown = true
			HUDController.Stamp("WANTED!", "Break line of sight to lose them", PINK)
		end
		lastHeat = heat
	end)
	Remotes.OnClient("TutorialDone", function(bonus)
		HUDController.Stamp("WELCOME TO PORT SOLANA", "+" .. HUDController.Money(bonus) .. " welcome bonus", PINK)
		task.delay(3, function()
			NotifyController.Show("Try races, stunt jumps, drifting and taxi shifts: PHONE > GPS > FUN", MINT)
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			local ok, err = pcall(tick)
			if not ok then
				warn("[TutorialClient] " .. tostring(err))
			end
		end
	end)
end

return TutorialClient
