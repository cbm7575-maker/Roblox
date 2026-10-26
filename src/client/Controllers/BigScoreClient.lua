-- BigScoreClient (ModuleScript, StarterPlayerScripts.Controllers.BigScoreClient)
-- The Big Score on screen: the crew heist on the Solana Gold Reserve, in the flat "street" look (Theme;
-- re-placed when the screen size or input type changes). BigScoreService runs all of it; this only draws
-- what its "BigScoreEvent" says to the players on its roster (player attribute BigScore = the step, 1..6).
-- Started from the phone's CREW app (PhoneUI: THE BIG SCORE, RequestBigScore "Start" / "Quit").
-- While you're on the roster:
--   * Goal zone (top centre), frame "Goal": a slim flat dark strip with a gold bar down its left edge, a
--     small gold Display tag (BIG SCORE and the step "2/6"; phones: just the step, in gold), the step's
--     words in white and the server's hint as a dim second line ("You've got a bar: load it at the van's
--     back doors" instead while you carry one). ObjectiveClient's strip, which uses the same zone, stays
--     hidden meanwhile (and counts as active, so the tutorial's goal keeps out of the way too).
--   * Banner zone (under it), frame "Status": what the van holds ("VAN $32,000   GOLD 4/12"; before the
--     first bar, what the vault holds) and the time left on the right in Display (red for the last
--     minute). At the gate (step 3): each console's state and the sync countdown ("CONSOLE A DONE
--     CONSOLE B NOW! 2.4s"). At the vault (step 4): DRILL 42% over a thin gold bar along the strip's foot,
--     or "PAUSED: stay by the drill" in orange while nobody stands by it (the bar turns orange too).
--     The GPS readout (ScreenGui "GPS", frame "Route") gives way to this line while it shows (GPSClient's
--     BANNER_OWNERS), as it does to a mission's banner; the marker carries the distance.
--   * PC only, frame "Checklist" at the left edge, half way down (the Coast Feed comes down from the top
--     and the toasts come up over the minimap; the list steps aside while one of their cards reaches over
--     it): THE BIG SCORE in gold, the six steps (done = dim, with a green tick drawn from two frames: the
--     fonts have no tick glyph; the current one in white with a gold box; later ones dim) and the crew.
--   Every piece steps aside while a HUDController stamp would draw over it (HUDController.StampTop, in
--   zone coordinates, so each piece is measured from this ScreenGui's own corner), then comes back.
--   * In the world (local parts under the camera): MissionClient's marker look at the current target (a
--     slim gold light column, a gold chevron and the distance over it, through buildings); while you carry
--     a bar it stands at the van's back doors instead and follows the van. The GPS is routed to each new
--     target (GPSClient.SetTarget with the step's TargetName), except when you're already within
--     K.GPS_SKIP studs of it (the marker shows it; the GPS would only say "arrived"). Our route is cleared
--     at the end only if it is still ours (GPSClient.TargetPos()), never one the player picked.
--   * Prompts: the Big Score's prompts (in Workspace.BigScore, and on the van: its HackPrompt, the
--     LoadPoint's prompt and the Drive / Ride prompts on its seats) show only to roster members in free
--     roam, and only for the step being played: 1 the van's "Hack the lock"; 2 on, the seats' prompts while
--     the seat is free; 3 both gate consoles (the one already held drops out until its sync window is
--     over); 4 the drill, until it has been started (after that it runs, or waits for someone to stand by
--     it); 5 "Grab gold bar" at the pile, or "Load gold" at the van while you carry one. Nobody else sees
--     any of them. Only Enabled is set here, on this device (a prompt that streams in is switched at once):
--     PromptGate hides on-foot prompts while you sit through MaxActivationDistance and never touches
--     Enabled, so the two never undo each other. The server checks everything again.
--   * Sounds (SoundClient, looked up softly; a key with no asset, or a SoundClient without Loop, stays
--     quiet): PhoneText on every new step, GateOpen as the gate slides, GoldClink as a bar is loaded.
--     Loops: Drill at the drill while it runs, VaultAlarm at the vault while its alarm rings (bystanders
--     hear it too, when the Coast Feed reports it, for its AlarmSeconds or until the run ends: the sound's
--     roll-off keeps it to the neighbourhood), and HeistMusic (flat, quiet) from step 2 on. Not played
--     here, so nothing plays twice: the Failed sting (HUDController plays it for every red stamp, HEIST
--     FAILED too), CashIn (SoundClient plays it when the banked Cash goes up: the cut) and StarUp /
--     LostCops (SoundClient plays them for every heat change).
--   * Stamps (HUDController.Stamp): THE BIG SCORE with the first step as it starts; HEIST COMPLETE in gold
--     with your cut and the XP ("Split evenly between 3 crew"); HEIST FAILED in red with the reason. A gold
--     toast for every bar loaded ("+$8,000 gold loaded (5/12)") and "Next: ..." for every new step.
-- In prison (a prisoner stays on the roster) the prison's own HUD has the screen: these pieces, the marker,
-- the loops and the prompts go until you're out. Hidden on the first-join title screen (attribute
-- TitleScreen) and gone the moment the BigScore attribute clears.
-- Constants are fields of K, the HUD pieces fields of ui and the state fields of S (a script's top level
-- holds 200 locals at most).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Heists = require(ReplicatedStorage.Shared.Config.Heists)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local GPSClient = require(script.Parent:WaitForChild("GPSClient"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local BigScoreClient = {}

local C = Theme.Color
local money = HUDController.Money
local BS = Heists.BigScore or {} -- (the fallbacks in K only matter if the config entry were ever missing)

local K = {}
K.STEPS = 6
-- The checklist's short names for the six steps (the strip shows BigScoreService's own words for the
-- current one).
K.STEP_NAMES = {
	"Hack the armored van", "Drive it to the Gold Reserve", "Open the gate together",
	"Drill the vault", "Load the gold", "Get it to the Hideout",
}
K.BARS = BS.Bars or 12
K.BAR_VALUE = BS.BarValue or 8000
K.SYNC = BS.ConsoleSync or 3 -- seconds (the server sends its own SyncWindow; this is only a stand-in)
K.DRILL_TIME = BS.DrillTime or 30
K.HURRY = 60 -- seconds left when the timer turns red
K.TIMER_W, K.TIMER_W_TOUCH = 64, 50 -- room for "20:00" in Display (22 px on a PC, 20 on phones)
K.COLUMN_H = 60 -- studs: the light column over the target
K.MARK_EVERY = 0.25 -- seconds between distance updates on the marker (and moves, when it follows the van)
K.PASS_EVERY = 0.25 -- seconds between passes over the prompts, the loops and the cards near the checklist
K.GPS_SKIP = 60 -- no route to a target you're already this close to
-- Inside the Goal strip (pixels, ObjectiveClient's): the colour bar, then the words.
K.ACCENT_X, K.ACCENT_W, K.TEXT_X = 7, 3, 18
K.DRILL_BAR_H = 3
-- The checklist (PC)
K.LIST_X, K.LIST_W = 20, 230
K.HEAD_H, K.ROW_H, K.CREW_H = 30, 22, 26
-- Card stacks that can reach the checklist (paths under PlayerGui): every card showing counts.
K.CARD_STACKS = { { "Toasts", "Holder" }, { "CoastFeed", "Holder" } }
K.ALARM_SECONDS = BS.AlarmSeconds or 60 -- how long a bystander's copy of the vault alarm rings (BigScoreService: AlarmUntil = now + this)
-- Where BigScoreService builds things, for a 3D sound while the part isn't streamed in (design spots
-- moved by the reserve's real CFrame, Config.Heists BigScore.ReserveCF).
K.RESERVE_CF = BS.ReserveCF or CFrame.new()
K.DRILL_AT = (K.RESERVE_CF * CFrame.new(266, 3, -1578)).Position
K.GATE_AT = (K.RESERVE_CF * CFrame.new(372, 4.5, -1578)).Position
K.VAULT_AT = (K.RESERVE_CF * CFrame.new(262, 6, -1578)).Position
-- Our prompts by the part they sit on (Workspace.BigScore, and the van's LoadPoint). The van's
-- HackPrompt is known by its own name; any other prompt on one of the van's seats is a way in ("Board":
-- BigScoreService's VanDrivePrompt / VanRidePrompt), except VehicleService's own, which VehicleVisuals
-- switches (two controllers setting one Enabled would fight).
K.PROMPT_PARTS = { ConsoleA = "ConsoleA", ConsoleB = "ConsoleB", Drill = "Drill", GoldPile = "Grab", LoadPoint = "Load" }
-- The van's own boarding prompts (BigScoreService adds them after the hack). Every other prompt on its
-- seats belongs to someone else and is left alone: VehicleService's DrivePrompt / RidePrompt
-- (VehicleVisuals switches those), ArrestService's CuffDriver (LawClient shows it to cops).
K.BOARD = { VanDrivePrompt = true, VanRidePrompt = true }

-- The HUD pieces (build sets them): gui, goal, title, detail, status, info, timer, bar, fill,
-- list, rows = { { ring, tick, dot, label } x 6 }, crew; and the text sizes place() picked: titleSize,
-- infoSize.
local ui = {}

local S = {
	state = nil, -- the last "State" from BigScoreService (nil = no run of ours on screen)
	stateAt = 0, -- os.clock() it came
	lastStep = nil, -- the step the last State had (a new one pings, toasts and maybe slides the gate)
	active = false, -- on the roster with a State, and not in prison: the pieces are ours to show
	touch = false, -- the phone layout is in use (place)
	lastTimer = nil, -- what the labels say now (only rewritten when it changes)
	lastInfo = nil,
	cardsOver = false, -- a toast or a feed post reaches over the checklist (the last pass)
	marker = nil, -- { part, label, pos } at the target
	markKey = nil, -- which target the marker stands at
	follow = nil, -- the van's LoadPoint while the marker follows it
	markAccum = 0,
	routedKey = nil, -- the target the GPS was last pointed at (or deliberately not)
	gpsPos = nil, -- the position of the GPS target we set (nil = none of ours)
	van = nil, -- the armored van (Workspace.Vehicles, attribute BigScoreVan) and its DescendantAdded hook
	vanConn = nil,
	vanLookAt = 0, -- os.clock() before which we don't look for a missing van again
	-- [prompt] = "Hack" | "Board" | "ConsoleA" | "ConsoleB" | "Drill" | "Grab" | "Load". A plain table, not
	-- a weak one: an Instance's Lua wrapper can be collected while the prompt still stands, and a prompt
	-- dropped from here would keep whatever Enabled it last had (no gold to grab). Pruned as prompts leave
	-- the Workspace (syncPrompts).
	prompts = {},
	loops = {}, -- [sound key] = the looping Sound while it plays
	sound = nil, -- SoundClient once found (false: not there)
	alarmUntil = 0, -- server time a bystander's vault alarm stops
	drillStarted = false, -- this run's drill has been started (State: Drilling, Drill > 0 or the alarm)
}

local function now()
	return Workspace:GetServerTimeNow()
end

local function clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- The gate consoles' sync countdown: tenths under 10 s ("2.4s"), m:ss above (Studio's solo window is 45 s).
local function syncClock(seconds)
	seconds = math.max(0, seconds)
	if seconds < 10 then
		return string.format("%.1fs", seconds)
	end
	return clock(seconds)
end

-- Plain words from the server inside rich text: keep "&", "<" and ">" from being read as tags.
local function escape(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function tint(color, text)
	return string.format('<font color="#%s">%s</font>', color:ToHex(), text)
end

-- Words in the condensed Display face, inside rich text (a size up from the label's: Oswald is condensed).
local function display(color, text, size)
	return string.format('<font face="Oswald" weight="bold" size="%d" color="#%s">%s</font>', size, color:ToHex(), text)
end

local function carrying()
	return player:GetAttribute("CarryingGold") == true
end

------------------------------------------------------------------ sounds

-- SoundClient, found on first use (false: not there).
local function sounds()
	if S.sound == nil then
		local module = script.Parent:FindFirstChild("SoundClient")
		local ok, found = false, nil
		if module then
			ok, found = pcall(require, module)
		end
		S.sound = ok and type(found) == "table" and found or false
	end
	return S.sound or nil
end

local function play(key, where)
	local snd = sounds()
	if snd and type(snd.Play) == "function" then
		pcall(snd.Play, key, where)
	end
end

-- A piece of the Big Score's world (Workspace.BigScore) for a 3D sound to sit on: the part itself, a
-- model's pivot, or the fallback (where BigScoreService builds it) while it isn't streamed in.
local function worldSpot(name, fallback)
	local folder = Workspace:FindFirstChild("BigScore")
	local found = folder and folder:FindFirstChild(name, true)
	if found and found:IsA("BasePart") then
		return found
	elseif found and found:IsA("Model") then
		return found:GetPivot().Position
	end
	return fallback
end

local function drillSpot()
	return worldSpot("Drill", K.DRILL_AT)
end

local function vaultSpot()
	return worldSpot("VaultDoor", K.VAULT_AT)
end

-- Start or stop one of the looping sounds. spot (optional) gives its place when it starts (nil = flat).
-- SoundClient.Loop hands back the Sound; we stop it with :Destroy().
local function setLoop(key, want, spot, volume)
	local s = S.loops[key]
	if s and not s.Parent then
		s = nil -- (cleaned up under us, e.g. the part it sat on streamed out: start it again)
		S.loops[key] = nil
	end
	if want and not s then
		local snd = sounds()
		if snd and type(snd.Loop) == "function" then
			local ok, made = pcall(snd.Loop, key, spot and spot() or nil, volume)
			if ok and typeof(made) == "Instance" then
				S.loops[key] = made
			end
		end
	elseif not want and s then
		s:Destroy()
		S.loops[key] = nil
	end
end

local function stopLoops()
	for key in pairs(S.loops) do
		setLoop(key, false)
	end
end

------------------------------------------------------------------ the van and the prompts

local function loadPoint()
	local van = S.van
	local p = van and van.Parent and van:FindFirstChild("LoadPoint", true)
	return p and p:IsA("BasePart") and p or nil
end

-- Which Big Score prompt this is, from the part it sits on (or, for the van's lock, its own name; a
-- prompt on one of the van's seats is "Board"); nil for anything else, which is left alone.
local function promptKind(prompt)
	if prompt.Name == "HackPrompt" then
		return "Hack"
	end
	local at = prompt.Parent
	while at and at ~= Workspace do
		local kind = K.PROMPT_PARTS[at.Name]
		if kind then
			return kind
		end
		if at:GetAttribute("BigScoreVan") == true then
			local seat = prompt.Parent
			if seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat")) and K.BOARD[prompt.Name] then
				return "Board"
			end
			return nil
		end
		if at.Name == "BigScore" then
			return nil
		end
		at = at.Parent
	end
	return nil
end

-- Should a Big Score prompt of this kind show to this player right now?
local function promptOn(kind)
	local s = S.state
	if not S.active or not s or player:GetAttribute("Side") ~= "Civilian" then
		return false
	end
	local step = s.Step
	if kind == "Board" then
		-- (the van's lock is open from step 2 on; syncPrompt also wants the seat free). Not while you carry a
		-- bar: at the van's back doors E has to mean "Load gold", and sitting down would drop the bar.
		return step >= 2 and player:GetAttribute("CarryingGold") ~= true
	end
	if step == 1 then
		return kind == "Hack"
	elseif step == 3 then
		if kind == "ConsoleA" or kind == "ConsoleB" then
			-- The console already held drops out until its sync window is over (then it needs holding again).
			local done = s[kind]
			return not (type(done) == "number" and now() - done <= (tonumber(s.SyncWindow) or K.SYNC))
		end
	elseif step == 4 then
		-- Once started the drill runs by itself (BigScoreService refuses a second start): its prompt stays
		-- gone while it waits for someone to stand by it, too.
		return kind == "Drill" and not S.drillStarted
	elseif step == 5 then
		if carrying() then
			return kind == "Load"
		end
		return kind == "Grab" and (tonumber(s.Bars) or 0) < (tonumber(s.BarsTotal) or K.BARS)
	end
	return false
end

-- Is a bar left on the pile for a grab? BigScoreService hides a pile bar (parts "Bar1".."Bar12" on the
-- GoldPile, Transparency 1) while it is carried or loaded, and switches its own Grab prompt off while
-- none is left; this keeps ours from switching it back on. (No bars found at all: don't hide it.)
local function pileHasGold(pile)
	local seen = false
	for _, bar in ipairs(pile and pile:GetChildren() or {}) do
		if bar:IsA("BasePart") and string.sub(bar.Name, 1, 3) == "Bar" then
			seen = true
			if bar.Transparency < 1 then
				return true
			end
		end
	end
	return not seen
end

local function syncPrompt(prompt, kind)
	local on = promptOn(kind)
	if on and kind == "Board" then
		local seat = prompt.Parent
		on = not (seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat")) and seat.Occupant ~= nil)
	elseif on and kind == "Grab" then
		on = pileHasGold(prompt.Parent)
	end
	if prompt.Enabled ~= on then
		prompt.Enabled = on
	end
end

-- (A prompt that left the Workspace, destroyed or streamed out, is dropped; one that comes back is
-- tracked again as it arrives.)
local function syncPrompts()
	for prompt, kind in pairs(S.prompts) do
		if prompt:IsDescendantOf(Workspace) then
			syncPrompt(prompt, kind)
		else
			S.prompts[prompt] = nil
		end
	end
end

-- A prompt arriving (built, or streamed in): switched at once, since the server switches it for everybody.
local function track(inst)
	if inst:IsA("ProximityPrompt") and S.prompts[inst] == nil then
		local kind = promptKind(inst)
		if kind then
			S.prompts[inst] = kind
			syncPrompt(inst, kind)
		end
	end
end

local function watchFolder(folder)
	folder.DescendantAdded:Connect(track)
	for _, d in ipairs(folder:GetDescendants()) do
		track(d)
	end
end

-- This is the armored van now: its prompts are tracked, and the ones that stream in later.
local function hookVan(car)
	if S.vanConn then
		S.vanConn:Disconnect()
	end
	S.van = car
	S.vanConn = car.DescendantAdded:Connect(track)
	for _, d in ipairs(car:GetDescendants()) do
		track(d)
	end
end

-- Keep hold of the armored van (looked for at most once a second while there is none) and its prompts.
local function watchVan()
	local van = S.van
	if van and van.Parent then
		return
	end
	if S.vanConn then
		S.vanConn:Disconnect()
		S.vanConn = nil
	end
	S.van = nil
	if os.clock() < S.vanLookAt then
		return
	end
	S.vanLookAt = os.clock() + 1
	local vehicles = Workspace:FindFirstChild("Vehicles")
	for _, car in ipairs(vehicles and vehicles:GetChildren() or {}) do
		if car:GetAttribute("BigScoreVan") == true then
			hookVan(car)
			return
		end
	end
end

------------------------------------------------------------------ the target in the world

local function clearMarker()
	if S.marker then
		S.marker.part:Destroy()
		S.marker = nil
	end
	S.markKey, S.follow = nil, nil
end

-- One stroke of the chevron (two make a "V").
local function stroke(parent, x, angle)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, x, 0, 9)
	f.Size = UDim2.fromOffset(13, 3)
	f.Rotation = angle
	f.BackgroundColor3 = C.Gold
	f.BorderSizePixel = 0
	f.Parent = parent
	Theme.Corners(f, 1)
end

-- MissionClient's target look: a slim, see-through gold column, and over it (on top of everything, so
-- it reads through buildings) a small gold chevron with the distance under it.
local function marker(pos)
	if S.marker then
		S.marker.part:Destroy()
	end
	local column = Instance.new("Part")
	column.Name = "BigScoreMarker"
	column.Anchored = true
	column.CanCollide = false
	column.CanQuery = false
	column.CanTouch = false
	column.CastShadow = false
	column.Size = Vector3.new(0.6, K.COLUMN_H, 0.6)
	column.Material = Enum.Material.Neon
	column.Color = C.Gold
	column.Transparency = 0.6
	column.Position = Vector3.new(pos.X, pos.Y + K.COLUMN_H / 2, pos.Z)
	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.Size = UDim2.fromOffset(80, 36)
	tag.StudsOffsetWorldSpace = Vector3.new(0, 8 - K.COLUMN_H / 2, 0) -- 8 studs up, not halfway up the column
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.Parent = column
	stroke(tag, -4, 40)
	stroke(tag, 4, -40)
	local distance = Instance.new("TextLabel")
	distance.Name = "Distance"
	Theme.Text(distance, 13, "Body")
	distance.AnchorPoint = Vector2.new(0.5, 0)
	distance.Position = UDim2.new(0.5, 0, 0, 16)
	distance.Size = UDim2.new(1, 0, 0, 16)
	distance.Text = ""
	distance.Parent = tag
	column.Parent = Workspace.CurrentCamera
	S.marker = { part = column, label = distance, pos = pos }
end

-- The distance under the chevron; a marker that follows the van moves with it.
local function updateMarker()
	local m = S.marker
	if not m then
		return
	end
	local follow = S.follow
	if follow and follow.Parent then
		local pos = follow.Position
		if (pos - m.pos).Magnitude > 0.5 then
			m.pos = pos
			m.part.Position = Vector3.new(pos.X, pos.Y + K.COLUMN_H / 2, pos.Z)
		end
	end
	local d = GPSClient.Distance(m.pos)
	m.label.Text = d and GPSClient.FormatDistance(d) or ""
end

-- Drop the GPS target only if it is still the one we set (a place the player picked stays).
local function clearOurRoute()
	if S.gpsPos and GPSClient.TargetPos() == S.gpsPos then
		GPSClient.Clear()
	end
	S.gpsPos = nil
end

-- Route the GPS to the step's target, once per target. Not when we're already close to it (the marker
-- shows the spot and the GPS would only say "arrived"): then our route to the last target goes instead.
local function route(pos, name)
	local key = tostring(name) .. "|" .. math.floor(pos.X / 8) .. "|" .. math.floor(pos.Z / 8)
	if key == S.routedKey then
		return
	end
	local d = GPSClient.Distance(pos)
	if d and d < K.GPS_SKIP then
		S.routedKey = key
		clearOurRoute()
		return
	end
	-- (pcall: if GPSClient hasn't built its pillar yet the call errors; the next State tries again)
	if pcall(GPSClient.SetTarget, type(name) == "string" and name or "The Big Score", pos) then
		S.routedKey = key
		S.gpsPos = pos
	end
end

------------------------------------------------------------------ the pieces

local function textLabel(parent, name, size, kind)
	local l = Instance.new("TextLabel")
	l.Name = name
	Theme.Text(l, size, kind)
	l.RichText = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = ""
	l.Parent = parent
	return l
end

-- One stroke of a checklist tick, centred on (x, y) inside its box.
local function tickStroke(parent, x, y, length, angle)
	local f = Instance.new("Frame")
	f.Name = "Stroke"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(length, 2)
	f.Rotation = angle
	f.BackgroundColor3 = C.Cash
	f.BorderSizePixel = 0
	f.Parent = parent
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BigScore"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- the zone map's coordinates (y = 0 is the very top of the screen)
	gui.Parent = player:WaitForChild("PlayerGui")
	ui.gui = gui

	-- Goal zone: [| BIG SCORE  2/6   Drive the van to the Gold Reserve ]
	--            [|                  The cops know about the van...     ]
	local goal = Instance.new("Frame")
	goal.Name = "Goal"
	goal.Visible = false
	Theme.Panel(goal)
	goal.Parent = gui
	ui.goal = goal
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(K.ACCENT_X, 7)
	accent.Size = UDim2.new(0, K.ACCENT_W, 1, -14)
	accent.BackgroundColor3 = C.Gold
	accent.BorderSizePixel = 0
	accent.Parent = goal
	Theme.Corners(accent, 1)
	ui.title = textLabel(goal, "Title", 15, "Bold")
	ui.detail = textLabel(goal, "Detail", 13, "Body")
	ui.detail.TextColor3 = C.Dim
	ui.detail.AnchorPoint = Vector2.new(0, 1)

	-- Banner zone: [VAN $32,000   GOLD 4/12 ............ 12:41] with the drill bar along its foot.
	local status = Instance.new("Frame")
	status.Name = "Status"
	status.Visible = false
	Theme.Panel(status)
	status.Parent = gui
	ui.status = status
	ui.info = textLabel(status, "Info", 14, "Bold")
	ui.info.Position = UDim2.fromOffset(12, 0)
	local timer = textLabel(status, "Timer", 22, "Display")
	timer.RichText = false
	timer.TextXAlignment = Enum.TextXAlignment.Right
	timer.TextTruncate = Enum.TextTruncate.None
	timer.AnchorPoint = Vector2.new(1, 0.5)
	timer.Position = UDim2.new(1, -12, 0.5, 0)
	ui.timer = timer
	ui.bar, ui.fill = Theme.Bar(status, C.Gold)
	ui.bar.AnchorPoint = Vector2.new(0.5, 1)
	ui.bar.Position = UDim2.new(0.5, 0, 1, -4)
	ui.bar.Size = UDim2.new(1, -24, 0, K.DRILL_BAR_H)
	ui.bar.BackgroundColor3 = C.Dim -- the empty part: dim grey
	ui.bar.BackgroundTransparency = 0.7
	ui.bar.Visible = false
	ui.fill.Size = UDim2.fromScale(0, 1)

	-- The checklist (PC): a dark panel at the left edge, half way down.
	local list = Instance.new("Frame")
	list.Name = "Checklist"
	list.AnchorPoint = Vector2.new(0, 0.5)
	list.Position = UDim2.new(0, K.LIST_X, 0.5, 0)
	list.Size = UDim2.fromOffset(K.LIST_W, K.HEAD_H + K.STEPS * K.ROW_H + K.CREW_H)
	Theme.Panel(list)
	list.Active = false
	list.Visible = false
	list.Parent = gui
	ui.list = list
	local head = textLabel(list, "Head", 16, "Display")
	head.RichText = false
	head.Position = UDim2.fromOffset(12, 6)
	head.Size = UDim2.new(1, -24, 0, 20)
	head.TextColor3 = C.Gold
	head.Text = "THE BIG SCORE"
	ui.rows = {}
	for i = 1, K.STEPS do
		local row = Instance.new("Frame")
		row.Name = "Step" .. i
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromOffset(12, K.HEAD_H + (i - 1) * K.ROW_H)
		row.Size = UDim2.new(1, -24, 0, K.ROW_H)
		row.Parent = list
		-- The box: a thin ring; a green tick drawn from two strokes once the step is done, a small gold
		-- square in it for the step being played.
		local box = Instance.new("Frame")
		box.Name = "Box"
		box.AnchorPoint = Vector2.new(0, 0.5)
		box.Position = UDim2.fromScale(0, 0.5)
		box.Size = UDim2.fromOffset(14, 14)
		box.BackgroundTransparency = 1
		box.BorderSizePixel = 0
		box.Parent = row
		Theme.Corners(box, 3)
		local ring = Instance.new("UIStroke")
		ring.Thickness = 1.5
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Color = C.Dim
		ring.Parent = box
		local tick = Instance.new("Frame")
		tick.Name = "Tick"
		tick.BackgroundTransparency = 1
		tick.Size = UDim2.fromScale(1, 1)
		tick.Visible = false
		tick.Parent = box
		tickStroke(tick, 4, 9, 5.5, 45) -- the short arm, down to the bottom of the tick...
		tickStroke(tick, 8.5, 7, 10.5, -49) -- ...and the long one up to the right
		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Size = UDim2.fromOffset(6, 6)
		dot.BackgroundColor3 = C.Gold
		dot.BorderSizePixel = 0
		dot.Visible = false
		dot.Parent = box
		Theme.Corners(dot, 1)
		local label = textLabel(row, "Text", 13, "Body")
		label.RichText = false
		label.Position = UDim2.fromOffset(22, 0)
		label.Size = UDim2.new(1, -22, 1, 0)
		label.TextColor3 = C.Dim
		ui.rows[i] = { ring = ring, tick = tick, dot = dot, label = label }
	end
	local crew = textLabel(list, "Crew", 12, "Body")
	crew.RichText = false
	crew.Position = UDim2.fromOffset(12, K.HEAD_H + K.STEPS * K.ROW_H + 2)
	crew.Size = UDim2.new(1, -24, 0, K.CREW_H - 8)
	crew.TextColor3 = C.Dim
	ui.crew = crew
end

-- The strip's words: the gold tag and the step, the step's words, and the hint under them.
local function drawGoal(s)
	local size = (ui.titleSize or 15) + 2 -- (Oswald is condensed: a size up reads as the same height)
	local count = tostring(s.Step) .. "/" .. tostring(tonumber(s.Total) or K.STEPS)
	local tag = S.touch and display(C.Gold, count, size)
		or (display(C.Gold, "BIG SCORE", size) .. "  " .. display(C.Text, count, size))
	ui.title.Text = tag .. "   " .. escape(s.Text or K.STEP_NAMES[s.Step] or "")
	local hint = s.Step == 5 and carrying() and "You've got a bar: load it at the van's back doors" or escape(s.Hint or "")
	ui.detail.Text = hint
end

-- The checklist: done steps dim with a tick, the current one white with a gold box, later ones dim.
local function drawChecklist(s)
	for i, row in ipairs(ui.rows) do
		local done, here = i < s.Step, i == s.Step
		row.tick.Visible = done
		row.dot.Visible = here
		row.ring.Color = here and C.Gold or (done and C.Cash or C.Dim)
		row.ring.Transparency = here and 0 or 0.45
		local words = K.STEP_NAMES[i]
		if i == 5 and s.Step >= 5 then
			words ..= " (" .. tostring(tonumber(s.Bars) or 0) .. "/" .. tostring(tonumber(s.BarsTotal) or K.BARS) .. ")"
		end
		row.label.Text = words
		row.label.FontFace = here and Theme.Font.Bold or Theme.Font.Body
		row.label.TextColor3 = here and C.Text or C.Dim
		row.label.TextTransparency = done and 0.35 or 0
	end
	local names = {}
	for _, m in ipairs(type(s.Members) == "table" and s.Members or {}) do
		if type(m) == "table" and m.Name then
			table.insert(names, tostring(m.Name))
		end
	end
	ui.crew.Text = #names > 0 and ("Crew: " .. table.concat(names, ", ")) or ""
end

-- How far the drill has got (0-1): the server's figure, run on between its once-a-second updates while
-- it drills (never more than a second and a half ahead of it).
local function drillShare(s)
	local share = tonumber(s.Drill) or 0
	if s.Drilling == true then
		share += math.min(os.clock() - S.stateAt, 1.5) / K.DRILL_TIME
	end
	return math.clamp(share, 0, 1)
end

-- One gate console's state: DONE (green), NOW! with the time left to match the other one (red), or
-- WAITING (dim).
local function consoleWord(prefix, letter, done, other, window, t)
	if done then
		return prefix .. letter .. " " .. tint(C.Cash, "DONE")
	elseif other then
		return prefix .. letter .. " " .. tint(C.Danger, "NOW! " .. syncClock(other + window - t))
	end
	return prefix .. letter .. " " .. tint(C.Dim, "WAITING")
end

-- The status line's words (rich text) for this moment.
local function statusWords(s, t)
	local size = (ui.infoSize or 14) + 2
	if s.Step == 3 then
		local window = tonumber(s.SyncWindow) or K.SYNC
		local a = type(s.ConsoleA) == "number" and t - s.ConsoleA <= window and s.ConsoleA or nil
		local b = type(s.ConsoleB) == "number" and t - s.ConsoleB <= window and s.ConsoleB or nil
		local prefix = S.touch and "" or tint(C.Dim, "CONSOLE ") -- (phones: no room for the word)
		return consoleWord(prefix, "A", a, b, window, t) .. "    " .. consoleWord(prefix, "B", b, a, window, t)
	elseif s.Step == 4 then
		local pct = math.floor(drillShare(s) * 100)
		if s.Drilling ~= true and (pct > 0 or S.drillStarted) then
			return tint(C.Orange, "PAUSED: stay by the drill") .. "   " .. tint(C.Dim, pct .. "%")
		end
		return tint(C.Dim, "DRILL ") .. display(C.Text, pct .. "%", size)
	end
	local total = tonumber(s.BarsTotal) or K.BARS
	local bars = tonumber(s.Bars) or 0
	if bars <= 0 then
		-- Nothing loaded yet: what the vault holds.
		local each = tonumber(s.BarValue) or K.BAR_VALUE
		return tint(C.Dim, "VAULT ") .. display(C.Gold, money(total * each), size)
			.. "   " .. tint(C.Dim, "GOLD ") .. display(C.Text, "0/" .. total, size)
	end
	return tint(C.Dim, "VAN ") .. display(C.Gold, money(tonumber(s.VanValue) or 0), size)
		.. "   " .. tint(C.Dim, "GOLD ") .. display(C.Text, bars .. "/" .. total, size)
end

-- Would a stamp in the band top..bottom (HUDController.StampTop: zone coordinates, y = 0 at the very top)
-- draw over this piece? AbsolutePosition starts under the top bar whatever IgnoreGuiInset says, so the
-- piece is measured from our ScreenGui's corner.
local function covered(frame, top, bottom)
	if top == nil then
		return false
	end
	local y = frame.AbsolutePosition.Y - ui.gui.AbsolutePosition.Y
	return top < y + frame.AbsoluteSize.Y and (bottom == nil or bottom > y)
end

-- Is a toast or a Coast Feed post reaching over the checklist? (Each card is measured from its own
-- ScreenGui's corner.)
local function cardsOver(frame)
	local origin = ui.gui.AbsolutePosition
	local top = frame.AbsolutePosition.Y - origin.Y
	local bottom = top + frame.AbsoluteSize.Y
	local right = frame.AbsolutePosition.X - origin.X + frame.AbsoluteSize.X
	local playerGui = player:FindFirstChild("PlayerGui")
	for _, path in ipairs(K.CARD_STACKS) do
		local sg = playerGui and playerGui:FindFirstChild(path[1])
		local holder = sg and sg:FindFirstChild(path[2])
		if holder and sg:IsA("ScreenGui") and sg.Enabled then
			for _, card in ipairs(holder:GetChildren()) do
				if card:IsA("GuiObject") and card.Visible then
					local y = card.AbsolutePosition.Y - sg.AbsolutePosition.Y
					local x = card.AbsolutePosition.X - sg.AbsolutePosition.X
					if y < bottom and y + card.AbsoluteSize.Y > top and x < right then
						return true
					end
				end
			end
		end
	end
	return false
end

local function hidePieces()
	ui.goal.Visible = false
	ui.status.Visible = false
	ui.list.Visible = false
end

-- Show or step aside, every frame (only written when it changes).
local function showPieces()
	local on = S.active and player:GetAttribute("TitleScreen") ~= true
	local top, bottom
	if HUDController.StampTop then
		top, bottom = HUDController.StampTop()
	end
	local goalOn = on and not covered(ui.goal, top)
	local statusOn = on and not covered(ui.status, top)
	local listOn = on and not S.touch and not S.cardsOver and not covered(ui.list, top, bottom)
	if ui.goal.Visible ~= goalOn then
		ui.goal.Visible = goalOn
	end
	if ui.status.Visible ~= statusOn then
		ui.status.Visible = statusOn
	end
	if ui.list.Visible ~= listOn then
		ui.list.Visible = listOn
	end
end

-- Put the pieces in their zones and size the words for this screen (phones: the smaller layout).
local function place()
	local touch = Theme.IsTouch()
	S.touch = touch
	Theme.Place(ui.goal, "Goal", touch)
	Theme.Place(ui.status, "Banner", touch)
	local titleSize, detailSize = touch and 14 or 15, 13
	ui.titleSize = titleSize
	ui.title.TextSize = titleSize
	ui.title.Position = UDim2.fromOffset(K.TEXT_X, touch and 3 or 5)
	ui.title.Size = UDim2.new(1, -(K.TEXT_X + 10), 0, titleSize + 4)
	ui.detail.TextSize = detailSize
	ui.detail.Position = UDim2.new(0, K.TEXT_X, 1, touch and -3 or -5)
	ui.detail.Size = UDim2.new(1, -(K.TEXT_X + 10), 0, detailSize + 3)
	local timerW = touch and K.TIMER_W_TOUCH or K.TIMER_W
	ui.infoSize = touch and 13 or 14
	ui.info.TextSize = ui.infoSize
	ui.info.Size = UDim2.new(1, -(12 + 8 + timerW + 12), 1, 0)
	ui.timer.TextSize = touch and 20 or 22
	ui.timer.Size = UDim2.new(0, timerW, 1, 0)
	S.lastTimer, S.lastInfo = nil, nil -- the next frame rewrites both
	if S.active and S.state then
		drawGoal(S.state) -- (phones drop the BIG SCORE tag)
	end
end

------------------------------------------------------------------ the run

-- Draw a new State: the strip, the checklist, the marker and the GPS.
local function refresh()
	local s = S.state
	if not S.active or not s then
		return
	end
	drawGoal(s)
	drawChecklist(s)
	S.lastTimer, S.lastInfo = nil, nil
	-- The marker: the step's target, or the van's back doors while you carry a bar (it follows the van).
	local target = typeof(s.Target) == "Vector3" and s.Target or nil
	local follow = s.Step == 5 and carrying() and loadPoint() or nil
	local pos = follow and follow.Position or target
	local key = pos and (s.Step .. "|" .. (follow and "van" or (math.floor(pos.X / 4) .. "|" .. math.floor(pos.Z / 4))))
	if key ~= S.markKey then
		if pos then
			marker(pos)
		else
			clearMarker()
		end
		S.markKey = key
	end
	S.follow = follow
	updateMarker()
	if target then
		route(target, s.TargetName)
	end
end

-- On the roster with a State and out of prison: the pieces are ours. Called whenever one of those changes.
local function update()
	local on = player:GetAttribute("BigScore") ~= nil and S.state ~= nil and player:GetAttribute("Side") ~= "Prisoner"
	if on ~= S.active then
		S.active = on
		if on then
			S.routedKey = nil -- route to the target again (GPSClient clears it on every Side change)
			refresh()
		else
			hidePieces()
			clearMarker()
			S.routedKey = nil
			setLoop("HeistMusic", false)
			setLoop("Drill", false)
		end
	end
	syncPrompts()
end

-- The BigScore attribute cleared: the run is over for us (passed, failed or quit).
local function endRun()
	S.state, S.lastStep = nil, nil
	S.drillStarted = false
	update()
	clearOurRoute()
	stopLoops()
end

local function onState(s)
	if type(s) ~= "table" or type(s.Step) ~= "number" then
		return
	end
	local before = S.lastStep
	S.state = s
	S.stateAt = os.clock()
	-- The drill counts as started from the first sign of it (it turning, any progress, the alarm) until
	-- the step is over: the State has no flag of its own for it.
	if s.Step ~= 4 then
		S.drillStarted = false
	elseif s.Drilling == true or (tonumber(s.Drill) or 0) > 0 or type(s.AlarmUntil) == "number" then
		S.drillStarted = true
	end
	update()
	if s.Step ~= before then
		S.lastStep = s.Step
		play("PhoneText")
		if before == nil then
			HUDController.Stamp("THE BIG SCORE", type(s.Text) == "string" and s.Text or nil, C.Text, "CREW HEIST")
		else
			if type(s.Text) == "string" then
				NotifyController.Show("Next: " .. s.Text, C.Gold, "info")
			end
			if before == 3 and s.Step >= 4 then
				play("GateOpen", worldSpot("Gate", K.GATE_AT))
			end
		end
	end
	refresh()
	syncPrompts()
end

local function onEvent(kind, info)
	if type(info) ~= "table" then
		info = {}
	end
	if kind == "State" then
		onState(info)
	elseif kind == "Loaded" then
		local s = S.state
		local bars = tonumber(info.Bars) or 0
		local total = s and tonumber(s.BarsTotal) or K.BARS
		local each = s and tonumber(s.BarValue) or K.BAR_VALUE
		if s then
			s.Bars = bars
			s.VanValue = tonumber(info.VanValue) or s.VanValue
		end
		local by = info.By
		local mine = by == nil or by == player.Name or by == player.DisplayName
		NotifyController.Show("+" .. money(each) .. " gold loaded" .. (mine and "" or (" by " .. tostring(by)))
			.. " (" .. bars .. "/" .. total .. ")", C.Gold, "money")
		play("GoldClink", loadPoint())
		refresh()
	elseif kind == "Done" then
		-- (the stamp's reward line plays the Passed sting, and SoundClient the register as the cut is banked)
		local crew = tonumber(info.Crew) or 1
		HUDController.Stamp("HEIST COMPLETE", crew > 1 and ("Split evenly between " .. crew .. " crew") or "All yours: no split",
			C.Gold, "THE BIG SCORE", { Cash = tonumber(info.Cut), XP = tonumber(info.XP) })
	elseif kind == "Failed" then
		-- (HUDController plays the Failed sting for a red stamp)
		HUDController.Stamp("HEIST FAILED", type(info.Reason) == "string" and info.Reason or nil, C.Danger, "THE BIG SCORE")
	end
end

-- Every frame while a run of ours is on screen: show or step aside, the countdown, the status words and
-- the drill bar (labels only change when the words do), and the marker four times a second.
local function tick(dt)
	local s = S.state
	if not S.active or not s then
		return
	end
	showPieces()
	local t = now()
	local left = (tonumber(s.EndsAt) or t) - t
	local timer = clock(left)
	if timer ~= S.lastTimer then
		S.lastTimer = timer
		ui.timer.Text = timer
		ui.timer.TextColor3 = left <= K.HURRY and C.Danger or C.Text
	end
	local words = statusWords(s, t)
	if words ~= S.lastInfo then
		S.lastInfo = words
		ui.info.Text = words
	end
	local drilling = s.Step == 4
	if ui.bar.Visible ~= drilling then
		ui.bar.Visible = drilling
	end
	if drilling then
		ui.fill.Size = UDim2.fromScale(drillShare(s), 1)
		ui.fill.BackgroundColor3 = (s.Drilling == true or (tonumber(s.Drill) or 0) <= 0) and C.Gold or C.Orange
	end
	S.markAccum += dt
	if S.markAccum >= K.MARK_EVERY then
		S.markAccum = 0
		updateMarker()
	end
end

-- Four times a second: the van and the prompts, the looping sounds and the cards near the checklist.
local function pass()
	watchVan()
	syncPrompts()
	local s = S.state
	local on = S.active and s ~= nil
	local t = now()
	setLoop("HeistMusic", on and s.Step >= 2)
	setLoop("Drill", on and s.Step == 4 and s.Drilling == true, drillSpot)
	local alarm = (on and type(s.AlarmUntil) == "number" and s.AlarmUntil > t) or S.alarmUntil > t
	setLoop("VaultAlarm", alarm, vaultSpot)
	if on then
		S.cardsOver = not S.touch and cardsOver(ui.list)
	end
end

-- The Coast Feed: the reserve's alarm rings for everyone else too (its roll-off keeps it local), until
-- the heist is over (a run that fails or is dropped: Init's BigScoreBusy hook).
local function onFeed(kind)
	if kind == "BigScoreAlarm" and player:GetAttribute("BigScore") == nil then
		S.alarmUntil = now() + K.ALARM_SECONDS
	elseif kind == "BigScoreDone" then
		S.alarmUntil = 0
	end
end

function BigScoreClient.Init()
	build()
	place()
	-- The world's prompts (the folder is built by the server at start; parts may stream in later).
	local world = Workspace:FindFirstChild("BigScore")
	if world then
		watchFolder(world)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "BigScore" then
			watchFolder(child)
		end
	end)
	-- A new van is picked up the moment it's parked (not at the next once-a-second look), so its lock
	-- prompt never shows to the wrong player in between. The newest one wins: the last run's van can
	-- still be standing (it goes a few seconds after the end) when another crew starts.
	task.spawn(function()
		local vehicles = Workspace:WaitForChild("Vehicles", 30)
		if vehicles then
			vehicles.ChildAdded:Connect(function(car)
				if car:GetAttribute("BigScoreVan") == true then
					hookVan(car)
				end
			end)
		end
	end)
	player:GetAttributeChangedSignal("BigScore"):Connect(function()
		if player:GetAttribute("BigScore") == nil then
			endRun()
		else
			update()
		end
	end)
	-- Deferred: GPSClient clears the GPS on every Side change, and our route out of prison must come after.
	player:GetAttributeChangedSignal("Side"):Connect(function()
		task.defer(update)
	end)
	player:GetAttributeChangedSignal("TitleScreen"):Connect(function()
		if S.active then
			showPieces()
		end
	end)
	-- Picking up or loading a bar: the hint, the marker (pile or van) and the prompts change at once.
	-- (Stars going up or all going: SoundClient plays StarUp / LostCops for every heat change itself.)
	player:GetAttributeChangedSignal("CarryingGold"):Connect(function()
		refresh()
		syncPrompts()
	end)
	-- Re-place when the screen changes size or the device's input changes (phone layout or not).
	ui.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(place)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(place)
	Remotes.OnClient("BigScoreEvent", onEvent)
	Remotes.OnClient("Feed", onFeed)
	-- A run that ends without a pass sends no feed post: a bystander's alarm stops with BigScoreBusy too.
	ReplicatedStorage:GetAttributeChangedSignal("BigScoreBusy"):Connect(function()
		if ReplicatedStorage:GetAttribute("BigScoreBusy") ~= true then
			S.alarmUntil = 0
		end
	end)
	RunService.Heartbeat:Connect(tick)
	task.spawn(function()
		local lastWarn = 0
		while true do
			task.wait(K.PASS_EVERY)
			local ok, err = pcall(pass)
			if not ok and os.clock() - lastWarn > 5 then
				lastWarn = os.clock()
				warn("[BigScoreClient] " .. tostring(err))
			end
		end
	end)
end

return BigScoreClient
