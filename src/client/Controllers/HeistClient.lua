-- HeistClient (ModuleScript, StarterPlayerScripts.Controllers.HeistClient)
-- Client side of heists, in the flat "street" look (Shared.Util.Theme):
--   * Rob prompts show only for robbers, and only while the site is Robbable (local-only toggle of
--     Enabled; the server re-checks everything when a robbery finishes). A prompt that streams in right
--     next to you is switched at once, not on the next pass (the server leaves it on for everybody).
--     A Rob prompt you are holding when its store leaves the rotation stays up until that hold ends
--     (stores shut for new holds only; the server pays a hold that began while the store was open).
--   * Sitting in a car (any seat) you can't rob: PromptGate hides the Rob and prep prompts the moment you
--     sit and brings them back when you stand up. It does that with MaxActivationDistance and this file
--     only ever sets Enabled, text and hold time, so the two never undo each other (nothing here looks at
--     the seat). InteractClient's "Get out to rob" hint asks HeistClient.NearestRob for the nearest spot
--     you could use on foot right now.
--   * Site signs (the server's BillboardGui over each pad, restyled on this device the first time it is
--     seen): the name in white Display, the state after it in the colour that means it, and a thin rule
--     in that colour under the words. "GLOW MART  OPEN" (green: cash to take), "GLOW MART  CLOSED 2:10"
--     (all dim; the same seated or on foot: the store is open, you just have to get out), and for cops
--     "GLOW MART  ALARM" blinking red while the alarm runs.
--   * Rank-locked heists (MinRank, e.g. the Coastal Bank at free-roam rank 3) say so up front for
--     players below it: the sign reads "COASTAL BANK / RANK 3 NEEDED (you're 1)" in purple, the prompts
--     read "Rank 3 needed" (a tap asks the server, which explains), and the first time you walk up to
--     one a stamp (the place over RANK 3 NEEDED) + toast tell you how to rank up.
--   * Prep panels (fuse box, yacht panel) with a live prep read "Done (1:05 left)" for the crew that
--     did it and "Taken (free in 0:32)" for everyone else while it's protected (PrepLockUntil); a tap
--     asks the server, which explains. Otherwise they show the server's own text and hold time.
--   * Holding a Rob prompt (ScreenGui "HeistUI", frame "Rob", in the Subtitle zone, or standing on top
--     of whatever else is using that zone): the place's name, the take so far counting up in green
--     ("$420 ...": the store's base payout times how far the hold has got; the real figure, with night /
--     crew / VIP bonuses and a big heist's crew split, comes with the result stamp) and a slim white bar
--     that thumps like a heartbeat, faster as the hold nears its end. The camera eases in up to 1.4 studs
--     while you hold and back out when you let go (moved after Roblox's camera each frame, so nothing
--     else's FOV or camera offset is touched). A prep panel's hold gets the same bar with a percentage
--     instead of cash.
--   * The alarm trips (the site's AlarmUntil starts, 10 s after the robbery): two quick red pulses round
--     the edge of the screen (frame "Alarm") for the robber and for anyone within 150 studs of the site.
--   * Result stamp (HUDController.Stamp, gold): "GLOW MART  ·  IN YOUR BAG" over ROBBERY COMPLETE (HEIST
--     COMPLETE for a big heist, CAR DELIVERED for a hot car), the reward line "+$1,200   +40 XP", then
--     "Lose the cops, then bank it at the Hideout (GPS set)" under it and the GPS pointed at the Hideout
--     through ObjectiveClient. A finished prep: STEP 1 DONE, green.
--   * Crew cuts (big heists only, HeistService): a robber who split the take (result Crew > 1) reads
--     "Split with 2 crewmates." before the next step. A crewmate who helped gets YOUR CUT (result Cut)
--     over the same place line, with the cash but no XP (the server gives the heist XP to the robber).
--   * Bag full: a toast with the cash left behind, and the Big Duffel offer is queued (OfferClient
--     shows it later, once the player isn't wanted or speeding).
--   * Big heists (Coastal Bank / Sea Dream, yours or your crew's: attribute BigHeists) say what they
--     count toward: "Big heist 1/3 toward the Riptide R", or which heist-locked ride just unlocked.
--   HeistClient.NearestRob(pos, range)  studs from pos to the nearest Rob point or prep panel within
--                                       range that this player could use on foot right now, or nil
-- Constants are fields of K and the HUD pieces fields of ui (a script's top level holds 200 locals at most).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Heists = require(ReplicatedStorage.Shared.Config.Heists)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local HeistClient = {}

local C = Theme.Color
local K = {}
K.EXPLAIN_RANGE = 90 -- studs from a locked site's pad before we explain the lock
K.PASS_EVERY = 0.33 -- seconds between passes over every site
K.PROMPT_NAMES = { "RobPrompt", "PrepPrompt" }
-- Signs: colour by meaning (as rich-text hex). Green = cash to take, dim = shut, purple = "not yet,
-- rank up first" (DealerClient's heist locks use the same), red = the alarm.
K.HEX_OPEN, K.HEX_SHUT, K.HEX_LOCKED = C.Cash:ToHex(), C.Dim:ToHex(), C.Purple:ToHex()
K.HEX_ALARM, K.HEX_TEXT = C.Danger:ToHex(), C.Text:ToHex()
K.SIGN_BIG = UDim2.fromOffset(300, 64) -- the locked sign has two lines, so it gets a bigger board
K.SIGN_RULE = 64 -- pixels: the thin rule under a sign's words
-- The rob bar
K.ROB_W, K.ROB_W_TOUCH = 360, 300 -- its width (never wider than the Subtitle zone)
K.ROB_H = 36 -- name and take (26 px) over the bar
K.BAR_H = 5 -- the bar at rest...
K.BEAT_SWELL = 3 -- ...and how many pixels thicker it gets on a heartbeat
K.BEAT_SLOW, K.BEAT_FAST = 1.1, 2.1 -- heartbeats a second as the hold starts / as it ends
K.TAKE_STEP = 20 -- the take counts up in steps of this many dollars
K.REPLACE_EVERY = 0.25 -- seconds between looks at what else is using the Subtitle zone
-- Pieces of other controllers that use the Subtitle zone now and then (paths under PlayerGui, the way
-- NotifyController lists them): the bar stands on top of one that is showing there.
K.SUBTITLE_PIECES = { { "Tutorial", "Next" }, { "Mission", "Step" }, { "ImpactFx", "KnockedDown" } }
-- The camera's slow push-in while you hold
K.PUSH = 1.4 -- studs closer by the end of the hold
K.PUSH_KEEP = 5 -- never when that would bring the camera closer to you than this (and at most half the spare room)
K.PUSH_SPEED = 5 -- per second: how fast it follows (and eases back when you let go)
K.STEP_NAME = "NC_HeistRob" -- our render step, bound only while a hold runs or the camera eases back
-- The alarm flash
K.ALARM_RANGE = 150 -- studs from the site's pad: bystanders this close see it too
K.ALARM_FRESH = 3 -- seconds: only an alarm that started this recently flashes (not one already ringing as the site streams in)
K.FLASH_SECONDS = 1 -- two pulses in this long
K.FLASH_ALPHA = 0.5 -- how solid the red gets at the very edge
K.FLASH_EDGE = 0.16 -- how far in it reaches: this share of the screen's shorter side (40-130 px)

-- The HUD pieces (build sets them once): gui, rob (the frame), robName, robTake, robNameShadow,
-- robTakeShadow, robBar, robFill, alarm (the frame), alarmEdges = { { frame, across } x 4 }
local ui = {}
local rob = {
	active = false, -- a Rob / prep hold is running
	prompt = nil, -- the prompt being held
	began = 0, -- os.clock() the hold began
	hold = 1, -- its length in seconds
	take = nil, -- dollars the place pays at least (nil for a prep step: no cash there)
	p = 0, -- how far the hold has got (0-1)
	shown = nil, -- the number the take label shows now
	phase = 0, -- where the heartbeat is in its cycle (0-1)
	push = 0, -- studs the camera is pushed in right now
	bound = false, -- our render step is hooked up
	token = 0, -- bumps whenever the bar is shown or sent away (a stale "hide it now" does nothing)
	fades = {}, -- the bar's running fade tweens
	placedAt = 0, -- os.clock() the bar was last placed
	flashToken = 0, -- bumps with every alarm flash (a newer one takes over)
}

local siteFolder = nil -- Workspace.Heists (set in Init)
-- Where this player could start a robbery on foot right now: the parents of the Rob / prep prompts that
-- are showing unlocked. Each pass fills the spare list and then swaps the two (no new tables), so
-- NearestRob always reads a finished one.
local robSpots, robCount = {}, 0
local fillSpots, fillCount = {}, 0

local promptDefaults = setmetatable({}, { __mode = "k" }) -- [prompt] = the server's text and hold time
local explained = {} -- [heist type] = true once this player has been told how to unlock it
local alarmSeen = {} -- [site] = the AlarmUntil we have already looked at
local lastBigHeists -- the BigHeists count we last saw (nil until the save has loaded)

local function now()
	return Workspace:GetServerTimeNow()
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Plain words inside rich text: keep "&", "<" and ">" from being read as tags ("Sparkle & Co.").
local function escape(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function tint(hex, text)
	return string.format('<font color="#%s">%s</font>', hex, text)
end

-- The free-roam rank this site needs, if the local player doesn't have it yet (else nil).
local function rankLock(site)
	if player:GetAttribute("Side") ~= "Civilian" then
		return nil
	end
	local def = Heists.Types[site:GetAttribute("HeistId")]
	local need = site:GetAttribute("MinRank") or (def and def.MinRank)
	local rank = player:GetAttribute("CivRank") or 1
	if type(need) == "number" and rank < need then
		return need, rank
	end
	return nil
end

-- The prep panel's lock text while a prep is live, or nil when anyone may do it now.
local function prepLabel(site)
	local t = now()
	local untilAt = site:GetAttribute("PrepUntil") or 0
	if untilAt <= t then
		return nil
	end
	local by = site:GetAttribute("PrepBy")
	if by ~= nil and (by == player:GetAttribute("Crew") or by == "u" .. player.UserId) then
		return "Done (" .. clock(untilAt - t) .. " left)"
	end
	local lockUntil = site:GetAttribute("PrepLockUntil") or 0
	if lockUntil > t then
		return "Taken (free in " .. clock(lockUntil - t) .. ")"
	end
	return nil
end

-- Locked (text given, e.g. "Rank 3 needed"): no hold, and a tap asks the server, which explains
-- (BankNeedsRank, PrepTaken...). Unlocked (nil): back to the server's own text and hold time.
local function labelPrompt(prompt, text)
	local d = promptDefaults[prompt]
	if not d then
		d = { ActionText = prompt.ActionText, HoldDuration = prompt.HoldDuration }
		promptDefaults[prompt] = d
	end
	local action = text or d.ActionText
	local hold = text and 0 or d.HoldDuration
	if prompt.ActionText ~= action then
		prompt.ActionText = action
	end
	if prompt.HoldDuration ~= hold then
		prompt.HoldDuration = hold
	end
end

------------------------------------------------------------------ site signs

-- The server builds each sign as one scaled label with a hard outline. The first time this device
-- sees it: the Display face, white, a soft shadow instead of the outline, room for a thin rule under
-- the words, and its normal size kept on the board itself (the locked sign is bigger). Returns the rule.
local function styleSign(gui, label)
	local rule = gui:FindFirstChild("Rule")
	if rule then
		return rule
	end
	gui:SetAttribute("NormalSize", gui.Size)
	label.FontFace = Theme.Font.Display
	label.RichText = true
	label.TextColor3 = C.Text
	label.TextStrokeTransparency = 1
	Theme.Shadow(label, 2)
	label.Size = UDim2.new(1, 0, 1, -6)
	rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0.5, 1)
	rule.Position = UDim2.new(0.5, 0, 1, -1)
	rule.Size = UDim2.fromOffset(K.SIGN_RULE, 2)
	rule.BackgroundColor3 = C.Text
	rule.BorderSizePixel = 0
	rule.Parent = gui
	return rule
end

-- The locked sign has two lines, so it gets a bigger board.
local function sizeSign(gui, big)
	local normal = gui:GetAttribute("NormalSize")
	local want = big and K.SIGN_BIG or normal
	if typeof(want) == "UDim2" and gui.Size ~= want then
		gui.Size = want
	end
end

-- First time near a locked heist: say what it needs and how to get there.
local function explainLock(site, need, rank)
	local typeId = site:GetAttribute("HeistId")
	if explained[typeId] then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pad = site.PrimaryPart
	if not root or not pad or (root.Position - pad.Position).Magnitude > K.EXPLAIN_RANGE then
		return
	end
	explained[typeId] = true
	local name = site:GetAttribute("Display") or site.Name
	HUDController.Stamp("RANK " .. need .. " NEEDED", "Unlocks at free-roam rank " .. need .. " (you're rank " .. rank .. ")",
		C.Purple, string.upper(name))
	NotifyController.Show("Earn XP by robbing stores, racing, stunts, taxi/courier jobs and missions. Check PHONE > GOALS.",
		C.Gold, "info")
end

------------------------------------------------------------------ the alarm flash

-- Two quick red pulses round the edge of the screen (the second softer). Labels and frames only: it
-- never takes a touch. A newer flash takes over from one still running.
local function flashAlarm()
	if not ui.alarm or player:GetAttribute("TitleScreen") == true then
		return
	end
	rob.flashToken += 1
	local token = rob.flashToken
	local view = ui.gui.AbsoluteSize
	local edge = math.clamp(math.floor(math.min(view.X, view.Y) * K.FLASH_EDGE), 40, 130)
	for _, e in ipairs(ui.alarmEdges) do
		e.frame.Size = e.across and UDim2.new(1, 0, 0, edge) or UDim2.new(0, edge, 1, 0)
		e.frame.BackgroundTransparency = 1
	end
	ui.alarm.Visible = true
	task.spawn(function()
		local t0 = os.clock()
		while rob.flashToken == token do
			local x = (os.clock() - t0) / K.FLASH_SECONDS
			if x >= 1 then
				break
			end
			local strength = math.abs(math.sin(x * math.pi * 2)) * (x < 0.5 and 1 or 0.65)
			local alpha = 1 - K.FLASH_ALPHA * strength
			for _, e in ipairs(ui.alarmEdges) do
				e.frame.BackgroundTransparency = alpha
			end
			RunService.RenderStepped:Wait()
		end
		if rob.flashToken == token then
			ui.alarm.Visible = false
		end
	end)
end

-- Has this site's alarm just gone off? Each alarm (each new AlarmUntil) is looked at once.
local function watchAlarm(site, t)
	local untilAt = site:GetAttribute("AlarmUntil") or 0
	if untilAt <= t or alarmSeen[site] == untilAt then
		return
	end
	alarmSeen[site] = untilAt
	if untilAt - t < Heists.AlarmSeconds - K.ALARM_FRESH then
		return -- it has been ringing for a while (we just arrived, or the site just streamed in)
	end
	-- The robber wherever they have got to, and anyone standing at the scene.
	if site:GetAttribute("LastRobbedBy") ~= player.UserId then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local pad = site.PrimaryPart
		if not root or not pad or (root.Position - pad.Position).Magnitude > K.ALARM_RANGE then
			return
		end
	end
	flashAlarm()
end

------------------------------------------------------------------ every site, three times a second

-- collect: this is the regular pass, so note the site's usable spots for NearestRob.
local function updateSite(site, collect)
	local robbable = site:GetAttribute("Robbable") == true
	local civilian = player:GetAttribute("Side") == "Civilian"
	local need, rank = rankLock(site)
	for _, name in ipairs(K.PROMPT_NAMES) do
		local prompt = site:FindFirstChild(name, true)
		if prompt then
			local text = need and ("Rank " .. need .. " needed") or (name == "PrepPrompt" and prepLabel(site)) or nil
			labelPrompt(prompt, text)
			-- A locked prompt shows even while the site is closed, so walking up to it tells you why.
			-- Only Enabled is switched here, and never for the seat: PromptGate keeps both prompts out of
			-- sight while we sit (through MaxActivationDistance), so the two can't flicker against each other.
			local show = civilian and (robbable or need ~= nil)
			-- The store left the rotation while we were holding its Rob prompt: it shuts for new holds
			-- only, so ours stays up until the hold ends (switching it off here made the bar vanish with
			-- nothing paid; the server pays a hold that began while the place was open). Not for a hold
			-- under a second old (the server may have shut before it saw that one begin), and not when
			-- somebody else emptied the place first (its ReopenAt is running: nothing left to take).
			local held = not show and civilian and name == "RobPrompt" and rob.active and rob.prompt == prompt
				and os.clock() - rob.began >= 1 and now() >= (site:GetAttribute("ReopenAt") or 0)
			if prompt.Enabled ~= (show or held) then
				prompt.Enabled = show or held
			end
			-- Showing and not locked: a spot we could use on foot right now.
			if collect and show and text == nil and prompt.Parent then
				fillCount += 1
				fillSpots[fillCount] = prompt.Parent
			end
		end
	end
	if need then
		explainLock(site, need, rank)
	end
	local t = now()
	watchAlarm(site, t)
	local pad = site.PrimaryPart
	local gui = pad and pad:FindFirstChildOfClass("BillboardGui")
	local label = gui and gui:FindFirstChildOfClass("TextLabel")
	if not label then
		return
	end
	local rule = styleSign(gui, label)
	local name = escape(string.upper(site:GetAttribute("Display") or site.Name))
	local alarm = t < (site:GetAttribute("AlarmUntil") or 0)
	local words, color
	if alarm and player:GetAttribute("Side") == "Cop" then
		local lit = math.floor(t * 3) % 2 == 0 -- (blinks from one pass to the next)
		color = lit and C.Danger or C.Text
		words = name .. "  " .. tint(lit and K.HEX_ALARM or K.HEX_TEXT, "ALARM")
	elseif need then
		color = C.Purple
		words = name .. "\n" .. tint(K.HEX_LOCKED, "RANK " .. need .. " NEEDED (you're " .. rank .. ")")
	elseif robbable then
		color = C.Cash
		words = name .. "  " .. tint(K.HEX_OPEN, "OPEN")
	elseif site:GetAttribute("TypeOpen") then
		color = C.Dim
		words = tint(K.HEX_SHUT, name .. "  CLOSED " .. clock((site:GetAttribute("ReopenAt") or 0) - t))
	else
		color = C.Dim
		words = tint(K.HEX_SHUT, name .. "  CLOSED")
	end
	if label.Text ~= words then
		label.Text = words
	end
	if rule.BackgroundColor3 ~= color then
		rule.BackgroundColor3 = color
	end
	sizeSign(gui, need ~= nil)
end

------------------------------------------------------------------ holding a Rob prompt

-- Put the bar in the Subtitle zone, sitting on its bottom edge; if another piece is using the zone (the
-- tutorial's help line, a mission step, KNOCKED DOWN) the bar stands on top of that piece instead.
local function placeRob()
	local view = ui.gui.AbsoluteSize
	if view.X <= 0 or view.Y <= 0 then
		return
	end
	local touch = Theme.IsTouch()
	local z = Theme.Zone("Subtitle", touch)
	local zw = z.Size.X.Scale * view.X + z.Size.X.Offset
	local zh = z.Size.Y.Scale * view.Y + z.Size.Y.Offset
	local zx = z.Pos.X.Scale * view.X + z.Pos.X.Offset - z.Anchor.X * zw
	local zy = z.Pos.Y.Scale * view.Y + z.Pos.Y.Offset - z.Anchor.Y * zh
	local bottom = zy + zh
	local playerGui = player:FindFirstChild("PlayerGui")
	for _, path in ipairs(K.SUBTITLE_PIECES) do
		local sg = playerGui and playerGui:FindFirstChild(path[1])
		local obj = sg and sg:FindFirstChild(path[2])
		if obj and obj:IsA("GuiObject") and obj.Visible and sg:IsA("ScreenGui") and sg.Enabled then
			-- (measured from that gui's own corner: AbsolutePosition starts under the top bar. The
			-- tutorial's frame is also its goal strip at the top of the screen: only one down here counts.)
			local top = obj.AbsolutePosition.Y - sg.AbsolutePosition.Y
			if top < zy + zh and top + obj.AbsoluteSize.Y > zy - K.ROB_H then
				bottom = math.min(bottom, top - 6)
			end
		end
	end
	ui.rob.Position = UDim2.fromOffset(math.floor(zx + zw / 2), math.floor(bottom))
	ui.rob.Size = UDim2.fromOffset(math.floor(math.min(zw, touch and K.ROB_W_TOUCH or K.ROB_W)), K.ROB_H)
	rob.placedAt = os.clock()
end

-- Fade the bar in (shown) or out, after `pause` seconds. A new fade takes over from one still running.
local function fadeRob(shown, seconds, pause)
	for _, t in ipairs(rob.fades) do
		t:Cancel()
	end
	table.clear(rob.fades)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, pause or 0)
	local function go(inst, prop, value)
		local t = TweenService:Create(inst, info, { [prop] = value })
		table.insert(rob.fades, t)
		t:Play()
	end
	local text, shadow = shown and 0 or 1, shown and 0.45 or 1
	go(ui.robName, "TextTransparency", text)
	go(ui.robTake, "TextTransparency", text)
	go(ui.robNameShadow, "Transparency", shadow)
	go(ui.robTakeShadow, "Transparency", shadow)
	go(ui.robBar, "BackgroundTransparency", shown and 0.35 or 1)
	go(ui.robFill, "BackgroundTransparency", text)
end

-- The hold is over. done = it ran its full length (the server pays, or says why not): the bar fills
-- and stays a moment, the result stamp is on its way. Let go early: it just fades.
local function endRob(done)
	if not rob.active then
		return
	end
	rob.active = false
	rob.prompt = nil
	rob.token += 1
	local token = rob.token
	ui.robBar.Size = UDim2.new(1, 0, 0, K.BAR_H)
	if done then
		ui.robFill.Size = UDim2.fromScale(1, 1)
		ui.robTake.Text = rob.take and HUDController.Money(rob.take) or "100%"
	end
	local pause, seconds = done and 0.3 or 0, done and 0.45 or 0.25
	fadeRob(false, seconds, pause)
	task.delay(pause + seconds + 0.05, function()
		if rob.token == token then
			ui.rob.Visible = false
		end
	end)
end

-- Every frame while a hold runs, and after it until the camera is back where it belongs. Bound right
-- after Roblox's camera, so the push below is added to wherever that put the camera this frame.
local function robStep(dt)
	local t = os.clock()
	if rob.active then
		local prompt = rob.prompt
		local p = math.clamp((t - rob.began) / rob.hold, 0, 1)
		rob.p = p
		if not prompt.Parent or not prompt.Enabled or t - rob.began > rob.hold + 1 then
			-- The prompt went away under the thumb (the store shut, we were moved), or its end never
			-- reached us: no bar may be left hanging.
			endRob(p >= 1)
		else
			ui.robFill.Size = UDim2.fromScale(p, 1)
			-- The heartbeat: a strong thump and a softer one after it, faster as the end nears.
			rob.phase = (rob.phase + dt * (K.BEAT_SLOW + (K.BEAT_FAST - K.BEAT_SLOW) * p)) % 1
			local x = rob.phase
			local beat = math.exp(-((x - 0.1) / 0.055) ^ 2) + 0.55 * math.exp(-((x - 0.32) / 0.07) ^ 2)
			ui.robBar.Size = UDim2.new(1, 0, 0, K.BAR_H + K.BEAT_SWELL * beat)
			-- The take so far (a prep step has no cash: how far it has got).
			local shown = rob.take and math.floor(rob.take * p / K.TAKE_STEP) * K.TAKE_STEP or math.floor(p * 100)
			if shown ~= rob.shown then
				rob.shown = shown
				ui.robTake.Text = rob.take and (HUDController.Money(shown) .. " ...") or (shown .. "%")
			end
			if t - rob.placedAt >= K.REPLACE_EVERY then
				placeRob() -- (the tutorial's help line may have come or gone)
			end
		end
	end
	-- The camera creeps in while you hold (most of it early on) and eases back out afterwards.
	local want = rob.active and K.PUSH * (1 - (1 - rob.p) ^ 2) or 0
	rob.push += (want - rob.push) * math.min(1, dt * K.PUSH_SPEED)
	local cam = Workspace.CurrentCamera
	if cam and rob.push > 0.005 and cam.CameraType == Enum.CameraType.Custom then
		local cf = cam.CFrame
		local spare = (cam.Focus.Position - cf.Position).Magnitude - K.PUSH_KEEP -- (first person: none)
		local d = math.min(rob.push, spare * 0.5)
		if d > 0.005 then
			cam.CFrame = cf + cf.LookVector * d
		end
	end
	if not rob.active and rob.push <= 0.005 then
		rob.push = 0
		rob.bound = false
		RunService:UnbindFromRenderStep(K.STEP_NAME)
	end
end

-- A Rob or prep hold has begun on this device.
local function startRob(prompt, site)
	local def = Heists.Types[site:GetAttribute("HeistId")]
	local prep = prompt.Name == "PrepPrompt"
	rob.token += 1
	rob.active = true
	rob.prompt = prompt
	rob.began = os.clock()
	rob.hold = math.max(prompt.HoldDuration, 0.1)
	rob.take = (not prep and def and def.Payout and def.Payout[1]) or nil
	rob.p, rob.phase, rob.shown = 0, 0, nil
	local name
	if prep then
		name = (def and def.Prep and def.Prep.Object) or prompt.ObjectText
	else
		name = site:GetAttribute("Display") or site.Name
	end
	ui.robName.Text = string.upper(tostring(name))
	ui.robTake.Text = ""
	ui.robTake.TextColor3 = rob.take and C.Cash or C.Text
	ui.robFill.Size = UDim2.fromScale(0, 1)
	placeRob()
	ui.rob.Visible = true
	fadeRob(true, 0.2)
	if not rob.bound then
		rob.bound = true
		RunService:BindToRenderStep(K.STEP_NAME, Enum.RenderPriority.Camera.Value + 2, robStep)
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "HeistUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- the zone map's coordinates (y = 0 is the very top of the screen)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	ui.gui = gui

	-- The rob bar: [GLOW MART ............ $420 ...] over a slim bar. Built hidden (fadeRob brings it in).
	local frame = Instance.new("Frame")
	frame.Name = "Rob"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Size = UDim2.fromOffset(K.ROB_W, K.ROB_H)
	frame.BackgroundTransparency = 1
	frame.Active = false
	frame.Visible = false
	frame.Parent = gui
	ui.rob = frame
	local name = Instance.new("TextLabel")
	name.Name = "Name"
	name.AnchorPoint = Vector2.new(0, 1)
	name.Position = UDim2.new(0, 0, 1, -(K.BAR_H + 5))
	name.Size = UDim2.new(0.6, 0, 0, 18)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.Text = ""
	Theme.Text(name, 13, "Bold")
	name.TextColor3 = C.Dim
	name.TextTransparency = 1
	name.Parent = frame
	ui.robName = name
	ui.robNameShadow = Theme.Shadow(name)
	ui.robNameShadow.Transparency = 1
	local take = Instance.new("TextLabel")
	take.Name = "Take"
	take.AnchorPoint = Vector2.new(1, 1)
	take.Position = UDim2.new(1, 0, 1, -(K.BAR_H + 3))
	take.Size = UDim2.new(0.6, 0, 0, 26)
	take.TextXAlignment = Enum.TextXAlignment.Right
	take.Text = ""
	Theme.Text(take, 22, "Display")
	take.TextTransparency = 1
	take.Parent = frame
	ui.robTake = take
	ui.robTakeShadow = Theme.Shadow(take)
	ui.robTakeShadow.Transparency = 1
	ui.robBar, ui.robFill = Theme.Bar(frame, C.Text)
	ui.robBar.AnchorPoint = Vector2.new(0.5, 1)
	ui.robBar.Position = UDim2.fromScale(0.5, 1)
	ui.robBar.Size = UDim2.new(1, 0, 0, K.BAR_H)
	ui.robBar.BackgroundTransparency = 1
	ui.robFill.Size = UDim2.fromScale(0, 1)
	ui.robFill.BackgroundTransparency = 1

	-- The alarm flash: four red edges, each fading out toward the middle of the screen.
	local alarm = Instance.new("Frame")
	alarm.Name = "Alarm"
	alarm.Size = UDim2.fromScale(1, 1)
	alarm.BackgroundTransparency = 1
	alarm.Active = false
	alarm.Visible = false
	alarm.Parent = gui
	ui.alarm = alarm
	ui.alarmEdges = {}
	-- name, anchor (also where it sits), runs across the screen?, gradient turn, solid end last?
	local edges = {
		{ "Top", 0.5, 0, true, 90, false }, { "Bottom", 0.5, 1, true, 90, true },
		{ "Left", 0, 0.5, false, 0, false }, { "Right", 1, 0.5, false, 0, true },
	}
	for i, e in ipairs(edges) do
		local f = Instance.new("Frame")
		f.Name = e[1]
		f.AnchorPoint = Vector2.new(e[2], e[3])
		f.Position = UDim2.fromScale(e[2], e[3])
		f.BackgroundColor3 = C.Danger
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Active = false
		local fall = Instance.new("UIGradient")
		fall.Rotation = e[5]
		fall.Transparency = e[6] and NumberSequence.new(1, 0) or NumberSequence.new(0, 1)
		fall.Parent = f
		f.Parent = alarm
		ui.alarmEdges[i] = { frame = f, across = e[4] }
	end
end

------------------------------------------------------------------ results

-- Point the GPS at the Hideout through ObjectiveClient (it clears the route once you've banked).
local function routeToHideout()
	local module = script.Parent:FindFirstChild("ObjectiveClient")
	if not module then
		return false
	end
	local ok, Objective = pcall(require, module)
	if not ok or type(Objective) ~= "table" or not Objective.RouteTo then
		return false
	end
	local routed
	ok, routed = pcall(Objective.RouteTo, "Hideout")
	return ok and routed == true
end

-- A big heist (ours or our crew's) just counted: say which heist-locked ride it unlocked, or how far
-- along the next one is. The first value (the save loading) is only remembered.
local function onBigHeists()
	local n = player:GetAttribute("BigHeists")
	local before = lastBigHeists
	lastBigHeists = n
	if type(n) ~= "number" or type(before) ~= "number" or n <= before then
		return
	end
	local unlocked, nextDef
	for _, def in ipairs(Vehicles.List) do
		local need = def.UnlockHeists
		if need and not def.Hidden then
			if need > before and need <= n and not unlocked then
				unlocked = def
			elseif need > n and (not nextDef or need < nextDef.UnlockHeists) then
				nextDef = def
			end
		end
	end
	if unlocked then
		NotifyController.Show("Big heist! The " .. (unlocked.DisplayName or unlocked.Id) .. " is unlocked: buy it at "
			.. (unlocked.Boat and "Marina Boat Sales." or "AutoNeon Motors."), C.Gold, "success")
	elseif nextDef then
		NotifyController.Show("Big heist " .. n .. "/" .. nextDef.UnlockHeists .. " toward the "
			.. (nextDef.DisplayName or nextDef.Id) .. " (" .. (nextDef.Boat and "Marina Boat Sales" or "AutoNeon Motors") .. ").",
			C.Gold, "info")
	end
end

-- The Big Duffel offer (OfferClient waits for a calm moment before it shows it).
local function offerBiggerBag(leftBehind)
	local module = script.Parent:FindFirstChild("OfferClient")
	if module then
		pcall(function()
			require(module).Queue("BagFull", { LeftBehind = leftBehind })
		end)
	end
end

-- A robbery (or a delivered hot car) paid into the bag: the stamp says what to do next, and the GPS
-- is routed there.
local function onResult(result)
	if type(result) ~= "table" then
		return
	end
	local payout = tonumber(result.Payout) or 0
	local wanted = result.Wanted
	if wanted == nil then
		wanted = (player:GetAttribute("Heat") or 0) > 0
	end
	local gps = routeToHideout() and " (GPS set)" or ""
	local nextStep = wanted and ("Lose the cops, then bank it at the Hideout" .. gps)
		or ("Bank it at the Hideout" .. gps)
	if payout > 0 then
		local def = Heists.Types[result.Type]
		local boost = result.Type == "CarBoost"
		local from = def and string.upper(def.Display) or (boost and "HOT CAR" or nil)
		local kicker = from and (from .. "  ·  IN YOUR BAG") or "IN YOUR BAG"
		if result.Cut == true then
			-- A crewmate robbed it and we helped: our share of the pot, no XP (ProgressService gives the
			-- heist XP to the robber alone).
			HUDController.Stamp("YOUR CUT", nextStep, C.Gold, kicker, { Cash = payout, XP = nil })
		else
			-- The headline, the place and the bag on top, then the cash and XP (ProgressService: Heist XP x
			-- the tier, CarBoost XP for a hot car) and what to do next (after who it was split with, if anyone).
			local title = boost and "CAR DELIVERED" or (def and def.Tier >= Heists.BigTier and "HEIST COMPLETE")
				or "ROBBERY COMPLETE"
			local xp = boost and Progression.XP.CarBoost or (def and Progression.XP.Heist * math.max(def.Tier, 1)) or nil
			local helpers = math.floor(tonumber(result.Crew) or 1) - 1
			local sub = nextStep
			if helpers > 0 then
				sub = "Split with " .. helpers .. (helpers == 1 and " crewmate. " or " crewmates. ") .. nextStep
			end
			HUDController.Stamp(title, sub, C.Gold, kicker, { Cash = payout, XP = xp })
		end
	end
	if result.BagFull then
		local left = math.max(0, math.floor(tonumber(result.LeftBehind) or 0)) -- hot cars don't send it
		NotifyController.Show("Bag full!" .. (left > 0 and (" " .. HUDController.Money(left) .. " left behind.") or "")
			.. " Bank your cash at the Hideout before you rob again.", C.Danger, "warning")
		offerBiggerBag(left)
	end
end

-- The heist site a prompt (or anything else) belongs to: its ancestor directly under Workspace.Heists.
local function siteOf(inst)
	local site = inst
	while site and site.Parent ~= siteFolder do
		site = site.Parent
	end
	if site and site:GetAttribute("HeistId") then
		return site
	end
	return nil
end

-- Studs from `pos` to the nearest spot within `range` where this player could start a robbery on foot
-- right now (a Rob point or prep panel whose prompt is showing unlocked), or nil. Seated players are
-- told to get out there (InteractClient, 25 studs: from the street that's mostly an ATM kiosk, since
-- store tills sit 22+ studs behind their shop fronts); the list is at most one pass old.
function HeistClient.NearestRob(pos, range)
	local best
	for i = 1, robCount do
		local spot = robSpots[i]
		if spot and spot.Parent then
			local at = spot:IsA("Attachment") and spot.WorldPosition or (spot:IsA("BasePart") and spot.Position)
			if at then
				local d = (at - pos).Magnitude
				if d <= range and (not best or d < best) then
					best = d
				end
			end
		end
	end
	return best
end

function HeistClient.Init()
	local heists = Workspace:WaitForChild("Heists")
	siteFolder = heists
	build()
	task.spawn(function()
		while true do
			fillCount = 0
			for _, site in ipairs(heists:GetChildren()) do
				if site:GetAttribute("HeistId") then
					local ok, err = pcall(updateSite, site, true)
					if not ok then
						warn("[HeistClient] " .. tostring(err))
					end
				end
			end
			for i = #fillSpots, fillCount + 1, -1 do
				fillSpots[i] = nil -- left over from a longer list two passes ago
			end
			robSpots, fillSpots = fillSpots, robSpots
			robCount = fillCount
			task.wait(K.PASS_EVERY)
		end
	end)
	-- A Rob / prep prompt streaming in is switched right away: the server leaves it on for everybody, so
	-- until the next pass it could show to a cop, or at a closed store, for a moment.
	heists.DescendantAdded:Connect(function(inst)
		if inst:IsA("ProximityPrompt") and (inst.Name == "RobPrompt" or inst.Name == "PrepPrompt") then
			local site = siteOf(inst)
			if site then
				pcall(updateSite, site, false)
			end
		end
	end)
	-- The hold itself (E, gamepad X or a thumb on the prompt): the bar, the take and the camera.
	-- A locked prompt has no hold (a tap asks the server why), so it never starts one.
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		if (prompt.Name == "RobPrompt" or prompt.Name == "PrepPrompt") and prompt.HoldDuration > 0 then
			local site = siteOf(prompt)
			if site then
				startRob(prompt, site)
			end
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt == rob.prompt then
			endRob(true)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		if prompt == rob.prompt then
			endRob(os.clock() - rob.began >= rob.hold - 0.1)
		end
	end)
	Remotes.OnClient("HeistPrep", function(info)
		HUDController.Stamp("STEP 1 DONE", type(info) == "table" and info.Text or nil, C.Cash)
	end)
	Remotes.OnClient("HeistResult", onResult)
	lastBigHeists = player:GetAttribute("BigHeists")
	player:GetAttributeChangedSignal("BigHeists"):Connect(onBigHeists)
end

return HeistClient
