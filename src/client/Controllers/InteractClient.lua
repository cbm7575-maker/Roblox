-- InteractClient (ModuleScript, StarterPlayerScripts.Controllers.InteractClient)
-- Getting in and out of cars (and taking other people's), made obvious:
--   * On foot within 12 studs of your own empty car (or the hot car or jacked car you stole): a big GET IN
--     button (bottom centre-right, clear of the phone jump button), the F key, the E key (while no "E"
--     bubble is up) and gamepad X get you in. Your own car's "Drive" bubble is held back on this device
--     (PromptGate.Hold: its reach stays 0, seated or on foot), so E is this same get-in and not an instant
--     seat; when a prompt that uses X is on screen (a shop...), X is left to that prompt. Not while knocked
--     over or tasered, with the phone out, or in the dressing room (WardrobeUI: E is its MASKS tab there).
--   * Getting in is a physical action, about 1.2-1.6 s from beside the car (about 0.9 s when you were
--     sprinting or are wanted; up to a second more when the walk has to go round the car), acted out on
--     this device. The server still does the seating: RequestEnterCar, checked by ImpactService exactly
--     as before.
--       1. Walk to the door on your side of the car: the chassis' DriverDoor / PassengerDoor attachment
--          (CarBuilder.AddBodyJoint; worked out from the seat on a car without them). From in front of the
--          car or behind it the walk goes round the body's corner first, never through it (routeStep).
--          Put there if the walk takes too long (0.8-2.4 s, by how far it is). A door spot with a wall in
--          the way is skipped for the other one (round the car); neither free (or the car on its side, or
--          a boat): no walk, straight to step 4 from where you stand.
--       2. Turn to the car, one hand out to the handle (0.25 s; skipped in a hurry). VehicleFeel.Overlay
--          draws the arm and the lean (PoseClient's reach if that controller has one).
--       3. The door opens (0.3 s, 0.15 in a hurry): the handle sound (SOUNDS.DoorOpen, our own table).
--       4. The character arcs into the seat (0.5 s, 0.36 in a hurry), ducking, carried along if the car
--          rolls. Your own car is a real, solid thing that the server moves while it stands empty, so
--          the character must never be put inside it before the seat's weld exists (the server would
--          shove the car aside): the request goes out as the arc starts, the character only leans in as
--          far as the sill (K.SILL studs from the car's solid box), and the moment the weld arrives the
--          rest of the arc is played on that weld's C0, on this device only (the character is part of
--          the car by then, so nothing is pushed, and you can already drive). A traffic car is only a
--          picture on this device: there the arc goes all the way, and RequestCarjack is sent about a
--          round trip before it ends, so the real car's seat takes over as you land.
--          During the arc cars can't push the character (collision group "Ghost" on this device only, as
--          ImpactClient does) and it can't trip. SoundClient's door thunk, the engine and the radio
--          follow from the seat as before, plus a short starter sound (SOUNDS.EngineStart).
--     Moving the stick calls it off (the push you pressed the button with only counts once you steer it
--     somewhere else, away from the car), and so do being knocked over or tasered, the car going, or
--     ending up 24 studs away. Pressing the key or the button again skips ahead to step 4; for half a
--     second after you sit, that same key does not get you out again (DriveController.NoExitUntil). No
--     answer from the server within a second of the arc's end: you're put back on your feet at the door.
--     LocomotionClient (the on-foot feel, if that controller is there) keeps working during the walk, so
--     a sprint stays a sprint; from the door on it is held off with its Suspend("GetIn", ...), so
--     nothing else walks or leans the character.
--     Getting out is as instant as ever (DriveController.Exit; the server steps you out): SoundClient's
--     door sound, and the character straightens up from a stoop over K.RISE_TIME while you already walk.
--     InteractClient.IsEntering() -> bool says whether the get-in is running (it moves the character).
--   * The car's name: the moment you sit down to drive, DriveUI.ShowCarName(display name, class from
--     Config.Vehicles) is asked for. DriveUI owns that piece of the screen and draws it (its "CarName"
--     frame knows about the controls strip, the area card and the phone layout); nothing is drawn here.
--   * Next to a hot car you can steal: a STEAL button you hold, just like the "Pick lock" prompt. It
--     holds that very prompt for you (ProximityPrompt:InputHoldBegin), so the server's 4 s timing and
--     checks (CarBoostService) don't change. Holding F does the same, E (and gamepad X, through the
--     prompt itself) still works, and the button fills up while the lock is being picked. If the hold
--     doesn't start, a toast says to hold E.
--   * Next to a parked car in a car park: a BREAK IN button, held the same way on CarjackService's
--     "Break in" prompt (also named PickLockPrompt, tagged "BreakInPrompt"). Those prompts only show for
--     citizens on foot: they're switched off here for everyone else.
--   * Citizens on foot next to a slow traffic car (TrafficClient.FindJackable: within 9 studs of its
--     driver's door, or 6 of its body): a pink JACK button, F or gamepad X. TrafficClient.Jack stops the
--     car and you walk to the door on your side of it, round its nose and not through it
--     (TrafficClient.JackSpots; where you stand, if both are walled off). The door opens and the driver
--     comes out (TrafficClient.PullDriver: kid-friendly, they stumble out with a "HEY!" and run off to the
--     pavement; 0.5 s, 0.3 when you're wanted or sprinting). Then you hop in while RequestCarjack asks
--     CarjackService for the real car (its checks are unchanged, and it seats you). Walking off before
--     the door opens calls it off: the car drives on and JACK is back in 1 s. No JACK again for 8.5 s
--     after the server was asked (its own cooldown is 8, counted from then; the button already goes at
--     the press), unless the server refuses ("CarjackRefused"): then you're back on your feet at the
--     door and JACK is back in 1 s.
--     When several of these apply, the nearest wins, so your own car's GET IN shows whenever it's closer.
--   * Sitting in a car (driver or passenger) you can't take another one or rob anything: the server needs
--     you on foot (its "GetOutFirst" toast says so if you try). PromptGate hides every on-foot prompt the
--     moment you sit (and the Pick lock (LawClient) and Break in (here) prompts are switched off as well),
--     so there is no "hold E" to try. Instead a small hint shows next to the EXIT button (drivers and
--     passengers both have one): a key cap (F on a keyboard, B on a gamepad, EXIT on touch) and three
--     words, in the flat street look (Theme). Where exactly is DriveUI's call (DriveUI.HintSpot: FLIP's
--     place, right above EXIT on a PC and left of the Buttons row on a phone; the hint needs the car
--     upright and FLIP needs it on its roof, so they never meet). The hint is a button too: a tap or click
--     on it gets you out, just like EXIT (on touch it's a full Theme.Touch tall, so the "EXIT" cap really
--     is a thumb-sized button). It only ever shows while EXIT does, and it's dropped the moment your seat
--     changes, so when you stand up it goes on the same frame as EXIT does.
--     One hint at a time; the nearest reason wins:
--       "Get out first"   a car you might want is close by: your own or a hot car within 20 studs, while
--                         under 25 studs/s; or, for citizens nearly stopped and seated for 2 s, a street
--                         car you could jack or a parked car you could break into, a few steps from your
--                         seat. Not within 8.5 s of your last jack or break-in ("Carjacked"): the server
--                         would refuse another one that soon anyway, and a car you just broke into sits
--                         in a stall right next to the others.
--                         Or, nearly stopped after driving somewhere (the car has been 30 studs or more
--                         from where you sat down), any other bubble PromptGate is holding back that would
--                         be up on foot (PromptGate.NearestHidden: a display car at the dealership, a
--                         front door, a dropped bag, the gun shop counter, a show car's Like, a treasure
--                         spot), so a hidden bubble never leaves you guessing. Not a crewmate's Ride
--                         (crews stop side by side all the time), and not before you've driven off: what
--                         you were standing at when you got in had its bubble on screen then (your front
--                         door most of all, where you spawn and call your car).
--       "Get out to rob"  nearly stopped within 25 studs of a Rob point (store till, ATM, bank vault) or
--                         prep panel you could rob on foot right now (HeistClient.NearestRob: open, your
--                         rank is enough, you're a citizen). 25 is about where the Rob prompt itself would
--                         have shown, so from the street this is mostly an ATM kiosk's plaza (store tills
--                         sit 22+ studs inside). Not during a job shift, race or mission: robbing makes
--                         you wanted, and that ends all three.
--     "Nearly stopped" = under 10 studs/s for half a second, and it lasts until over 14 (no blinking while
--     you ease in or creep along). On foot, STEAL / BREAK IN are only offered for a prompt PromptGate
--     isn't holding back, so the button never asks for a hold the prompt can't start. (PromptGate is
--     required softly: if the module is missing or doesn't load, nothing is held back, and this file
--     neither waits for it nor fails with it.)
--   * Car alarms: a car with CarAlarmUntil (server time, set by CarjackService) rings on its chassis for
--     everyone nearby until then.
-- F while driving belongs to DriveController (get out); F as a passenger to VehicleVisuals.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local DriveController = require(script.Parent:WaitForChild("DriveController"))
local DriveUI = require(script.Parent:WaitForChild("DriveUI"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))
local PhoneUI = require(script.Parent:WaitForChild("PhoneUI"))
local ImpactClient = require(script.Parent:WaitForChild("ImpactClient"))
local SoundClient = require(script.Parent:WaitForChild("SoundClient"))
local TrafficClient = require(script.Parent:WaitForChild("TrafficClient"))
local HeistClient = require(script.Parent:WaitForChild("HeistClient"))
-- PromptGate is soft: if the module is missing, doesn't load, or is an older one without what we call, an
-- inert stand-in (nothing held back), so this file (GET IN!) and every controller ClientMain starts after
-- it still start instead of waiting on it forever or failing with it.
local PromptGate = nil
do
	local module = script.Parent:WaitForChild("PromptGate", 5)
	local ok, mod = false, nil
	if module then
		ok, mod = pcall(require, module)
		if not ok then
			warn("[InteractClient] PromptGate didn't load: " .. tostring(mod))
		end
	end
	if ok and type(mod) == "table" and mod.IsHidden and mod.NearestHidden and mod.Hold then
		PromptGate = mod
	else
		PromptGate = {
			IsHidden = function()
				return false
			end,
			NearestHidden = function()
				return nil
			end,
			Hold = function(prompt)
				if prompt.MaxActivationDistance ~= 0 then
					prompt.MaxActivationDistance = 0
				end
			end,
		}
	end
end
-- VehicleFeel is soft too: it only draws the reach and the duck of getting in (its Overlay table). Without
-- it the character still walks to the door and hops in, just with no pose on top.
local VehicleFeel = nil
do
	local module = script.Parent:WaitForChild("VehicleFeel", 5)
	if module then
		local ok, mod = pcall(require, module)
		if ok and type(mod) == "table" and type(mod.Overlay) == "table" then
			VehicleFeel = mod
		else
			warn("[InteractClient] VehicleFeel didn't load: " .. tostring(mod))
		end
	end
end
local OVERLAY = VehicleFeel and VehicleFeel.Overlay or { Reach = 0, Side = 1, Duck = 0 }

local player = Players.LocalPlayer

local InteractClient = {}

-- Constants are fields of K, the screen pieces fields of ui and what changes fields of S: the top level
-- of a script is one Luau function, and a function holds at most 200 locals (this file was at 182).
local K = {}
K.MINT = Color3.fromRGB(110, 242, 196)
K.GOLD = Color3.fromRGB(255, 214, 10)
K.PINK = Color3.fromRGB(255, 62, 165)
K.DARK = Color3.fromRGB(18, 14, 30)
K.FONT = Enum.Font.FredokaOne

K.ENTER_RANGE = 12 -- studs from the driver's seat
K.STEAL_RANGE = 11 -- a little inside the Pick lock prompt's 12, so the prompt is showing too
K.BREAKIN_RANGE = 9 -- a little inside the Break in prompt's 10
K.JACK_DOOR_RANGE = 9 -- studs from a traffic car's driver's door...
K.JACK_BOX_RANGE = 6 -- ...or from anywhere around its body (a car stopped for you ends 4 from you)
K.JACK_COOLDOWN = 8.5
K.JACK_RETRY = 1 -- seconds before JACK comes back after the server refused one
K.HINT_RANGE = 20
K.HINT_MAX_SPEED = 25 -- studs/s: no hint while cruising past parked cars
K.HINT_STOP_SPEED = 10 -- studs/s: street and parked cars are everywhere, so for them only when nearly stopped
K.HINT_TAKE_RANGE = 14 -- studs from your seat to a street car's driver's door or a parked car's Break in spot...
K.HINT_TAKE_BOX = 10 -- ...or from your seat to anywhere around a street car's body
K.HINT_SETTLE = 2 -- seconds seated before those count (no "get out" the moment you get in)
K.HINT_SLOW_HOLD = 0.5 -- seconds under HINT_STOP_SPEED before "nearly stopped" counts (not while still rolling in)
K.HINT_SLOW_EXIT = 14 -- studs/s: "nearly stopped" only ends above this, so creeping at about 10 doesn't blink the hint
-- Studs from your seat to a Rob point or prep panel: about where its prompt (12 studs) would have shown.
-- From the street that's an ATM kiosk's plaza, or a car driven in through a shop doorway: store tills sit
-- 22-58 studs behind their shop fronts, so a car parked outside a store is out of reach (as is the prompt).
K.HINT_ROB_RANGE = 25
-- Studs from where you sat down that the car must have got to (at any point since) before any other
-- held-back bubble counts (PromptGate.NearestHidden): that hint stands in for a bubble you'd have seen on
-- driving up. What you were standing at when you got in had its bubble on screen already, and getting in
-- was your answer: your front door, where you spawn and call your car; the display car you just looked
-- at. Once you've been away, coming back to it counts. (More than any prompt's reach, 16 at most.)
K.HINT_DROVE = 30
-- Held-back prompts that catch-all leaves alone, by Name:
K.HINT_NOT_FOR = {
	RobPrompt = true, -- "Get out to rob" has its own rules (open, rank, no shift / race / mission)
	PrepPrompt = true, -- same
	PickLockPrompt = true, -- cars are the searches' above (whose car, the cooldown after a jack or break-in)
	DrivePrompt = true, -- same: your own empty car already counts from 20 studs
	RidePrompt = true, -- a crewmate's free seat: crews stop side by side all the time (lights, race starts)
}
K.HINT_CAR, K.HINT_ROB = "Get out first", "Get out to rob"
K.HINT_HEIGHT = 32 -- pixels, keyboard / gamepad (touch: Theme.Touch, it's a button you tap)
K.REFRESH = 0.1
K.ALARM_CHECK = 0.5
K.BUTTON_POS = UDim2.new(0.72, 0, 1, -22) -- right of Roblox's on-foot hotbar (fists / blaster)

-- Getting in (see the header). Seconds, unless said otherwise.
K.GETIN_STEP = "NC_GetIn" -- render step name; runs after Roblox's control scripts, so our walk wins
-- Walking to the door takes no longer than the way there at WALK_PACE plus a moment to get going, kept
-- between these two: then you're put there (a last resort: something was in the way).
K.APPROACH_MIN, K.APPROACH_MAX = 0.8, 2.4
K.WALK_PACE = 14 -- studs/s
K.ARRIVE = 1.3 -- studs from the door spot (flat) that count as being at the door
K.DOOR_OUT = 1.9 -- studs from a body's side to its door spot (as CarBuilder and TrafficClient place them)
K.ROUND = 1.6 -- studs clear of a car's bumper when the walk goes round its corner (routeStep)
K.REACH_TIME = 0.25 -- the hand going out to the handle (skipped in a hurry)
K.DOOR_TIME, K.DOOR_TIME_FAST = 0.3, 0.15 -- the door swinging open
K.TUG_TIME, K.TUG_TIME_FAST = 0.5, 0.3 -- a jack: the driver coming out before you get in
K.HOP_TIME, K.HOP_TIME_FAST = 0.5, 0.36 -- the arc into the seat
K.HOP_ARC = 0.7 -- studs the arc rises over the sill (more for a long way, a boat from the dock)
K.HOP_WAIT, K.HOP_WAIT_JACK = 1, 1.8 -- waiting for the server once the arc's time is up, before giving up (a jack builds a car first)
-- How near a real car's solid box (its chassis) the character's root part may come before the seat's
-- weld exists. A root part is 1 stud from its middle to its side: this leaves a hand's width of air.
K.SILL = 1.25
K.SETTLE_MIN = 0.2 -- the shortest the rest of the arc takes once the weld has us (settleStep)
K.EXIT_LOCK = 0.5 -- after sitting down this way, the get-out key does nothing for this long
K.GETIN_MAX_DIST = 24 -- studs from the door: further than this it's called off
K.SEAT_UP = 1.3 -- a seated character's root part above the seat's top
K.SPRINTING = 20 -- studs/s on foot when you press: faster than this (or wanted) and it's the hurried version
K.STICK_HOLD = 0.2 -- a push on the stick this long calls the get-in off
K.GHOST_GROUP = "Ghost" -- never collides with cars (CarBuilder.EnsureGroups; ImpactClient uses it the same way)
K.RISE_TIME = 0.35 -- straightening up after stepping out

-- Sounds only getting in uses, played here (Config.Sounds belongs to SoundClient). Both are
-- ProSoundEffects "(SFX)" assets from the Creator Store, found with the asset search on 2026-10-05 and not
-- yet listened to in game. Length: only that many seconds from the start are played. Id = 0 silences one.
local SOUNDS = {
	-- Vehicle Door Grab 10 (SFX): a hand working a car door's handle, outdoors (1.9 s of grabs: the first).
	DoorOpen = { Id = 9120373449, Volume = 0.55, Length = 0.7 },
	-- "... Failed Starts Engine S (SFX)": a starter turning over before the engine catches (3.6 s; the rest
	-- of the asset's name is a real car, so it is left out here). Only the first cranks, quietly, under
	-- SoundClient's engine loop as that comes in.
	EngineStart = { Id = 9125657723, Volume = 0.35, Length = 1.2, Pitch = 1.08 },
}

-- The screen pieces, set once by build(): gui, button, buttonStroke, fill, mainLabel, keyLabel (the
-- contextual button) and hint, hintKey, hintLabel (the seated hint).
local ui = {}
local S = {
	entering = nil, -- the get-in that is running (see "getting in, step by step"), else nil
	settling = nil, -- the last of a get-in's arc, played on the seat's weld (beginSettle), else nil
	controls = nil, -- Roblox's ControlModule, found on first use (false: not there)
	locomotion = nil, -- LocomotionClient, looked for on first use (false: not there)
	wardrobe = nil, -- WardrobeUI, looked for on first use (false: not there); refresh asks its IsOpen
	effectsGroup = nil, -- SettingsClient's "Effects" SoundGroup, found on first use (false: none)
	seatNow = nil, -- the seat this character sat in at its last seat change (seatChanged)
	riseAt = nil, -- os.clock() we stepped out of a car (straightening up until K.RISE_TIME later)
	target = nil, -- { kind = "enter" | "steal" | "jack", car, prompt, breakIn, dist } while on foot
	hintText = nil, -- K.HINT_CAR / K.HINT_ROB while the seated hint should show (nil: no hint)
	satIn = nil, satAt = 0, -- the seat we're sitting in (nil on foot) and os.clock() when we sat in it
	satPos = nil, drove = false, -- where we were when we sat in it, and whether we've been K.HINT_DROVE away since
	slowSince = nil, -- os.clock() since the seat's car went under K.HINT_STOP_SPEED (nil: not nearly stopped)
	holding = nil, holdSource = nil, holdAskedAt = 0, holdWarned = false, -- the prompt we hold for the player, and how
	holdInput = nil, holdInputConn = nil,
	breakInsOn = nil, -- whether the Break in prompts (breakIns) are switched on here right now
	seatConn = nil, -- the current character's "seat changed" connection (watchSeat)
	lastEnter = 0, lastHelp = 0,
	lastJack = -math.huge, -- os.clock() of our last JACK: the press, then again when the server is asked (send)
	lastTake = -math.huge, -- os.clock() of our last jack or break-in the server carried out (for the hint only)
	accum = 0, alarmAccum = 0,
}
local holdBegan = setmetatable({}, { __mode = "k" }) -- [prompt] = os.clock() the hold started
local shownPrompts = setmetatable({}, { __mode = "k" }) -- [prompt] = true while it's on screen
local breakIns = {} -- [prompt] = true: parked cars' Break in prompts streamed in on this device
local ringing = setmetatable({}, { __mode = "k" }) -- [car] = its alarm Sound (or true) while it rings

local function corner(obj, scale)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or 0.5, 0)
	c.Parent = obj
end

local function stroke(obj, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness or 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

local function label(parent, name)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.BackgroundTransparency = 1
	l.Font = K.FONT
	l.TextScaled = true
	l.ZIndex = 2
	l.Parent = parent
	return l
end

-- "touch", "gamepad" or "keyboard": decides which key names the button and hint show.
local function inputMode()
	if DriveUI.IsTouch and DriveUI.IsTouch() then
		return "touch"
	end
	local last = UserInputService:GetLastInputType()
	if string.sub(last.Name, 1, 7) == "Gamepad" then
		return "gamepad"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	end
	return "keyboard"
end

local function build()
	ui.gui = Instance.new("ScreenGui")
	ui.gui.Name = "Interact"
	ui.gui.ResetOnSpawn = false
	ui.gui.IgnoreGuiInset = true -- same coordinates as DriveUI, so the hint can line up with EXIT
	ui.gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ui.gui.Parent = player:WaitForChild("PlayerGui")

	-- The contextual button: sized from the screen height so it's thumb-sized on phones.
	ui.button = Instance.new("TextButton")
	ui.button.Name = "Action"
	-- Flat street look, in the HUD's Action zone (Theme): a dark panel, a thin line in the action's
	-- colour along the bottom, the word in Display font and the key under it.
	ui.button.AutoButtonColor = false
	ui.button.Text = ""
	ui.button.Visible = false
	Theme.Panel(ui.button, 0.3)
	Theme.Place(ui.button, "Action", Theme.IsTouch())
	ui.button.Parent = ui.gui
	-- (kept as a UIStroke so render() can colour it; thin and quiet)
	ui.buttonStroke = stroke(ui.button, K.MINT, 1)
	ui.buttonStroke.Transparency = 0.35

	-- Lock-picking progress, filling from the left.
	ui.fill = Instance.new("Frame")
	ui.fill.Name = "Progress"
	ui.fill.Size = UDim2.fromScale(0, 1)
	ui.fill.BackgroundColor3 = K.GOLD
	ui.fill.BackgroundTransparency = 0.55
	ui.fill.BorderSizePixel = 0
	ui.fill.Visible = false
	ui.fill.Parent = ui.button
	corner(ui.fill)

	ui.mainLabel = label(ui.button, "Main")
	ui.mainLabel.Size = UDim2.fromScale(0.86, 0.5)
	ui.mainLabel.FontFace = Theme.Font.Display
	ui.keyLabel = label(ui.button, "Key")
	ui.keyLabel.Size = UDim2.fromScale(0.86, 0.26)
	ui.keyLabel.Position = UDim2.fromScale(0.5, 0.76)
	ui.keyLabel.FontFace = Theme.Font.Bold
	ui.keyLabel.TextColor3 = Theme.Color.Dim

	-- "Get out first" / "Get out to rob" hint (while seated), in the flat street look: a dark panel as
	-- wide as its words, a key cap and white text. It's also a button that does what EXIT does: on a
	-- phone the cap reads "EXIT" and looks tappable, so a tap must work (and must not fall through to the
	-- free-look drag behind it). Its height follows the device in render(). Not selectable: gamepads
	-- have B. (TutorialClient finds it by name to keep its goal pill out from under it.)
	ui.hint = Instance.new("TextButton")
	ui.hint.Name = "GetOutHint"
	ui.hint.Text = ""
	ui.hint.AutoButtonColor = false
	ui.hint.Selectable = false
	ui.hint.AnchorPoint = Vector2.new(1, 0) -- held by its right edge, so it grows to the left (render places it)
	ui.hint.Size = UDim2.fromOffset(0, K.HINT_HEIGHT)
	ui.hint.AutomaticSize = Enum.AutomaticSize.X
	ui.hint.Visible = false
	Theme.Panel(ui.hint)
	ui.hint.Parent = ui.gui
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 7)
	row.Parent = ui.hint
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 10)
	pad.Parent = ui.hint
	ui.hintKey = Theme.Key(ui.hint, "F")
	ui.hintKey.LayoutOrder = 1
	ui.hintLabel = Instance.new("TextLabel")
	ui.hintLabel.Name = "Text"
	ui.hintLabel.LayoutOrder = 2
	ui.hintLabel.Size = UDim2.fromOffset(0, 22)
	ui.hintLabel.AutomaticSize = Enum.AutomaticSize.X
	ui.hintLabel.Text = K.HINT_CAR
	Theme.Text(ui.hintLabel, 15, "Bold")
	ui.hintLabel.Parent = ui.hint
end

------------------------------------------------------------------ finding a car

-- Can this Pick lock / Break in prompt be held right now? seated: asked for the hint, where a prompt
-- counts although it's switched off (LawClient / syncBreakIns) and held back (PromptGate) while we sit.
-- On foot it must be both switched on and let go by the gate, or the hold would never start.
local function promptReady(prompt, seated)
	return seated or (prompt.Enabled and not PromptGate.IsHidden(prompt))
end

-- The nearest car we could get into or steal, measured to its driver's seat. skipCar: the car
-- we're sitting in. seated: for the hint (see promptReady).
local function findTarget(pos, skipCar, enterRange, stealRange, seated)
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then
		return nil
	end
	local civilian = player:GetAttribute("Side") == "Civilian"
	local best, bestDist
	for _, car in ipairs(folder:GetChildren()) do
		local seat = car ~= skipCar and car:FindFirstChild("DriverSeat")
		if seat and seat:IsA("VehicleSeat") and not seat.Occupant then
			local kind, prompt, range
			if car:GetAttribute("OwnerUserId") == player.UserId then
				kind, range = "enter", enterRange
				-- Our own car's "Drive" bubble would seat us at once, skipping the walk to the door: it's
				-- held back for good on this device (its reach at 0; Enabled is left to VehicleVisuals),
				-- and E gets us in through the same steps as F (see Init). Asked of PromptGate, which owns
				-- prompt reach here: if it hid this bubble first (the car streamed in while we sat in
				-- another one), standing up next to it must not bring the bubble back for a moment.
				local drive = seat:FindFirstChild("DrivePrompt")
				if drive and drive:IsA("ProximityPrompt") then
					PromptGate.Hold(drive)
				end
			elseif car:GetAttribute("HotCar") then
				-- (jacked street cars are HotCars too: their thief gets back in the same way)
				local thief = car:GetAttribute("ThiefUserId")
				if thief == player.UserId and civilian then
					kind, range = "enter", enterRange
				elseif thief == nil and civilian then
					prompt = seat:FindFirstChild("PickLockPrompt")
					if prompt and prompt:IsA("ProximityPrompt") and promptReady(prompt, seated) then
						kind, range = "steal", stealRange
					end
				end
			end
			if kind then
				local d = (seat.Position - pos).Magnitude
				if d <= range and (not bestDist or d < bestDist) then
					best = { car = car, kind = kind, prompt = prompt, dist = d }
					bestDist = d
				end
			end
		end
	end
	return best
end

-- The nearest parked car's Break in prompt within `range` (held like STEAL), or nil. seated: for the
-- hint (see promptReady).
local function findBreakIn(pos, range, seated)
	local best, bestDist
	for prompt in pairs(breakIns) do
		local spot = prompt.Parent
		if promptReady(prompt, seated) and spot and spot:IsA("Attachment") then
			local d = (spot.WorldPosition - pos).Magnitude
			if d <= range and (not bestDist or d < bestDist) then
				best, bestDist = prompt, d
			end
		end
	end
	return best and { kind = "steal", prompt = best, breakIn = true, dist = bestDist } or nil
end

-- Break in prompts only for citizens on foot (the server checks too): switched on or off here. (Enabled
-- only. PromptGate also hides them while we sit, its own way, so the two agree and never undo each other.)
local function syncBreakIns(on)
	if on == S.breakInsOn then
		return
	end
	S.breakInsOn = on
	for prompt in pairs(breakIns) do
		prompt.Enabled = on
	end
end

local function trackBreakIn(prompt)
	if prompt:IsA("ProximityPrompt") then
		breakIns[prompt] = true
		prompt.Enabled = S.breakInsOn == true
	end
end

------------------------------------------------------------------ sounds and the car's name

-- One of SOUNDS, in the world: where = a BasePart or a Vector3. Gone again when it has played.
local function playLocal(key, where)
	local def = SOUNDS[key]
	if not def or type(def.Id) ~= "number" or def.Id <= 0 then
		return
	end
	if S.effectsGroup == nil then
		local ok, group = pcall(function()
			return require(script.Parent:WaitForChild("SettingsClient", 2)).Group("Effects")
		end)
		S.effectsGroup = ok and typeof(group) == "Instance" and group or false
	end
	local holder = nil
	local parent = where
	if typeof(where) == "Vector3" then
		holder = Instance.new("Attachment")
		holder.Name = "NCSoundSpot"
		holder.Parent = Workspace.Terrain
		holder.WorldPosition = where
		parent = holder
	elseif not (typeof(where) == "Instance" and where:IsA("BasePart")) then
		return
	end
	local pitch = def.Pitch or 1
	local s = Instance.new("Sound")
	s.Name = "NC" .. key
	s.SoundId = "rbxassetid://" .. def.Id
	s.Volume = def.Volume or 0.5
	s.PlaybackSpeed = pitch
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = 140
	if S.effectsGroup then
		s.SoundGroup = S.effectsGroup
	end
	if def.Length then
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = NumberRange.new(0, def.Length)
	end
	s.Parent = parent
	s:Play()
	task.delay((def.Length or 3) / pitch + 0.6, function()
		s:Destroy()
		if holder then
			holder:Destroy()
		end
	end)
end

-- The name of the car we just sat down to drive: its display name, and its class from Config.Vehicles.
-- DriveUI owns that piece of the screen and draws it (it knows what else stands there: the controls
-- strip, the area card, the phone's top-centre pieces). Asking for it here, at the very moment we sit,
-- also keeps DriveUI from showing the same name by itself a moment later.
local function nameCar(car)
	if type(DriveUI.ShowCarName) ~= "function" then
		return
	end
	local id = car:GetAttribute("VehicleId")
	local def = type(id) == "string" and Vehicles.ById[id] or nil
	local name = car:GetAttribute("DisplayName")
	if type(name) ~= "string" or name == "" then
		name = def and def.DisplayName or nil
	end
	if type(name) == "string" and name ~= "" then
		DriveUI.ShowCarName(name, def and def.Class)
	end
end

------------------------------------------------------------------ getting in, step by step

-- One get-in at a time lives in S.entering:
--   kind       "enter" (your own / stolen car, a real model) or "jack" (a traffic car, TrafficClient's record)
--   car, char, hum, root, params (rays that ignore the car and people)
--   chassis    the real car's chassis ("enter"); origin: the traffic car's pivot, a fixed CFrame ("jack").
--              Every spot below is in that frame, so a car that rolls carries the whole act along.
--   doorLocal  where we stand to open the door (nil: no walk, straight in), side (-1 driver's, 1 passenger's),
--              handle (the point the hand reaches for), seatLocal (where the arc ends)
--   halfLen    half the length of the car's body, for walking round it (nil: straight to the door)
--   approachMax  seconds the walk may take before we're put at the door
--   phase      "approach" -> "reach" -> "door" -> "hop"; phaseAt, startedAt
--   fast       the hurried version (sprinting or wanted when it began)
--   released   the stick has been let go since the press; heldDir: where it pushed at the press
--   sent       the server has been asked (sendAt: seconds into the hop when that happens)
--   hopFrom, hopArc: the arc; hopStop: how far along it (0-1 of its time) the character may go before the
--              seat has it; drawn, drawnS: where the arc last put the root part (in the car's frame) and
--              how far along that was

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- A heading from a flat look vector: 0 looks along -Z, growing to the left (CFrame.Angles(0, yaw, 0)
-- looks that way).
local function yawOf(look)
	return math.atan2(-look.X, -look.Z)
end

-- a - b, the short way round (-pi..pi)
local function angleDiff(a, b)
	return (a - b + math.pi) % (2 * math.pi) - math.pi
end

-- The stick, keys or phone thumbstick as Roblox's control scripts read them (x right, z back, as held),
-- or zero when those scripts can't be reached (then only time and distance end a get-in).
local function moveVector()
	if S.controls == nil then
		local ok, c = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 1)):GetControls()
		end)
		S.controls = ok and c or false
	end
	if S.controls then
		local ok, v = pcall(S.controls.GetMoveVector, S.controls)
		if ok and typeof(v) == "Vector3" then
			return v
		end
	end
	return Vector3.zero
end

-- Where a push on the stick points in the world (flat, length 1), or nil when that can't be told.
local function pushDir(v)
	local camera = Workspace.CurrentCamera
	local world = camera and flat(camera.CFrame:VectorToWorldSpace(v)) or Vector3.zero
	return world.Magnitude > 0.05 and world.Unit or nil
end

local function fireEnter(car)
	task.spawn(function()
		Remotes.Event("RequestEnterCar"):FireServer(car)
	end)
end

-- LocomotionClient (the on-foot feel: speed ramps, braking steps, body lean) stands down from the door on,
-- while the get-in turns and moves the character itself (its Suspend is made for exactly this). During the
-- walk to the door it is left on: our hum:Move looks like any other push to it, so a sprint stays a sprint
-- and a standing start still builds up. Looked for the first time it's needed; without that controller
-- there is nothing to hold off.
local function holdLocomotion(on)
	if S.locomotion == nil then
		local module = script.Parent:FindFirstChild("LocomotionClient")
		local ok, mod = false, nil
		if module then
			ok, mod = pcall(require, module)
		end
		S.locomotion = ok and type(mod) == "table" and type(mod.Suspend) == "function" and mod or false
	end
	if S.locomotion then
		pcall(S.locomotion.Suspend, "GetIn", on)
	end
end

local function anchorOf(e)
	return e.chassis and e.chassis.CFrame or e.origin
end

-- For the arc into the seat: cars can't push the character (their collision group, this device only: the
-- change never replicates) and it can't trip or go into its falling pose. Put back by passThrough(e, false).
local function passThrough(e, on)
	if on then
		if e.groups then
			return
		end
		e.groups = {}
		for _, d in ipairs(e.char:GetDescendants()) do
			if d:IsA("BasePart") then
				e.groups[d] = d.CollisionGroup
				pcall(function()
					d.CollisionGroup = K.GHOST_GROUP
				end)
			end
		end
		e.states = {}
		for _, state in ipairs({ Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.FallingDown }) do
			e.states[state] = e.hum:GetStateEnabled(state)
			e.hum:SetStateEnabled(state, false)
		end
		return
	end
	if e.groups then
		for part, old in pairs(e.groups) do
			-- (a part ImpactClient made pass-through first is its to put back)
			if part.Parent and old ~= K.GHOST_GROUP and part.CollisionGroup == K.GHOST_GROUP then
				part.CollisionGroup = old
			end
		end
		e.groups = nil
	end
	if e.states then
		if e.hum.Parent then
			for state, was in pairs(e.states) do
				e.hum:SetStateEnabled(state, was)
			end
		end
		e.states = nil
	end
end

-- Standing at a door spot (world CFrame, looking at the car): on the ground under it if there is any,
-- else at the height we're at.
local function standAt(e, door)
	local pos = door.Position
	local y = e.root.Position.Y
	local hit = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), e.params)
	if hit then
		y = hit.Position.Y + e.hum.HipHeight + e.root.Size.Y / 2
	end
	local look = flat(door.LookVector)
	if look.Magnitude < 0.05 then
		look = flat(e.root.CFrame.LookVector)
	end
	return CFrame.new(pos.X, y, pos.Z) * CFrame.Angles(0, look.Magnitude > 0.05 and yawOf(look) or 0, 0)
end

-- Settling in. The seat's weld took the character before the arc was over (at your own car it had only
-- leaned in as far as the sill). The rest of the way is played on that weld's C0, on this device only:
-- the character is one body with the car by now, so nothing gets pushed; the server and everybody else
-- already see it sitting; and the car can be driven while it settles. S.settling:
--   weld, seat, hum, root; real (the weld's own C0), c1
--   from, to   the root part in the seat's frame: where the arc had it, and where the weld wants it
--   at, time, arc (studs it still rises on the way), duck (how far bent over it started)

-- Over (or called off): the weld gets its own C0 back.
local function endSettle()
	local st = S.settling
	if not st then
		return
	end
	S.settling = nil
	if st.weld.Parent then
		st.weld.C0 = st.real
	end
	if not S.riseAt and not S.entering then
		OVERLAY.Duck = 0
	end
end

-- Start it (takeSeat does). Returns the record, or nil when there is nothing to play: no weld to be found,
-- the character as good as in its place already, too far off for it to look like getting in, or a joined
-- body whose root is the character itself (a change to the weld would then move the car, not the character).
local function beginSettle(e)
	local hum, root = e.hum, e.root
	local seat = hum.SeatPart or e.seat
	local weld = seat and seat:FindFirstChild("SeatWeld")
	if not e.drawn or not weld or not weld:IsA("Weld") or weld.Part0 ~= seat or weld.Part1 ~= root
		or root.AssemblyRootPart == root then
		return nil
	end
	local real, c1 = weld.C0, weld.C1
	local to = real * c1:Inverse()
	local from = seat.CFrame:ToObjectSpace(anchorOf(e) * e.drawn)
	local gap = (from.Position - to.Position).Magnitude
	if gap < 0.25 or gap > 7 then
		return nil
	end
	local left = 1 - (e.drawnS or 1) -- the share of the arc still to go
	local st = {
		weld = weld, seat = seat, hum = hum, root = root, real = real, c1 = c1, from = from, to = to,
		at = os.clock(), time = math.clamp(e.hopTime * left, K.SETTLE_MIN, e.hopTime),
		arc = (e.hopArc or K.HOP_ARC) * left, duck = OVERLAY.Duck,
	}
	local seatWas = seat.Position
	weld.C0 = from * c1 -- back to where it was drawn a moment ago, before this frame is shown
	if (seat.Position - seatWas).Magnitude > 0.05 then
		-- (it was the car that moved after all: not this way, then)
		weld.C0 = real
		return nil
	end
	return st
end

-- Every frame while it runs: a little further in, straightening up.
local function settleStep(now)
	local st = S.settling
	if not st then
		return
	end
	local weld, seat = st.weld, st.seat
	local u = (now - st.at) / st.time
	local sitting = st.hum.SeatPart
	-- (got out again, moved to another seat, or the character is gone: the weld went with it)
	if u >= 1 or weld.Parent ~= seat or weld.Part1 ~= st.root or (sitting ~= nil and sitting ~= seat) then
		endSettle()
		return
	end
	local k = u * u * (3 - 2 * u)
	local rel = st.from:Lerp(st.to, k) + Vector3.new(0, math.sin(math.pi * u) * st.arc, 0)
	weld.C0 = rel * st.c1
	OVERLAY.Duck = st.duck * (1 - k)
end

-- The get-in is over: seated, called off, or given up. backOut: we were on our way into the seat and
-- didn't get it, so stand us back at the door (never left inside the car's body).
local function finishEnter(e, backOut)
	if S.entering ~= e then
		return
	end
	S.entering = nil
	pcall(function()
		RunService:UnbindFromRenderStep(K.GETIN_STEP)
	end)
	holdLocomotion(false)
	passThrough(e, false)
	OVERLAY.Reach, OVERLAY.Duck, OVERLAY.Target = 0, 0, nil
	local root, hum = e.root, e.hum
	if hum.Parent and not hum.SeatPart then
		hum:Move(Vector3.zero, false) -- (our walk to the door ends here; the stick takes over next frame)
	end
	if backOut and root.Parent and hum.Parent and not hum.SeatPart then
		local anchor = anchorOf(e)
		local cf = nil
		if e.doorLocal then
			cf = standAt(e, anchor * e.doorLocal)
		elseif e.hopFrom then
			cf = anchor * e.hopFrom
		end
		if cf then
			root.CFrame = cf
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

-- Called off (the stick, too far, knocked over, the car gone, no answer). A jack that hasn't been asked
-- for yet lets its traffic car drive on, and JACK is back in a moment.
local function cancelEnter(e)
	local hopping = e.phase == "hop"
	if e.kind == "jack" and not e.sent then
		pcall(TrafficClient.Release, e.car)
		S.lastJack = os.clock() - K.JACK_COOLDOWN + K.JACK_RETRY
	end
	finishEnter(e, hopping)
end

-- The seat has us (the server's weld joined the character to the car): the get-in is over. If the arc was
-- still on its way, its last part is played on that weld (beginSettle).
local function takeSeat(e)
	local st = nil
	if e.phase == "hop" then
		local ok, res = pcall(beginSettle, e)
		if ok then
			st = res
		else
			warn("[InteractClient] settling in: " .. tostring(res))
		end
	end
	finishEnter(e, false)
	if st then
		S.settling = st
		OVERLAY.Duck = st.duck
	end
	-- F and E mean "get out" from the instant we sit: a second press that was meant to skip ahead and
	-- came a moment late must not put us straight back out (DriveController.Exit looks at this).
	DriveController.NoExitUntil = os.clock() + K.EXIT_LOCK
end

-- Ask the server for the seat (the car, for a jack). Its checks are the ones it always made.
local function send(e)
	e.sent = true
	if e.kind == "enter" then
		fireEnter(e.car)
	else
		-- The server counts its 8 s between jacks from when it builds the car, which is about now and
		-- not when the button was pressed: our own wait for the next JACK starts over here, so the next
		-- one never asks too soon (a refusal or a cancel still brings JACK back early).
		S.lastJack = os.clock()
		local info = e.info
		task.spawn(function()
			Remotes.Event("RequestCarjack"):FireServer(info.Kind, info.CFrame, info.Color)
		end)
	end
end

-- Where the arc into the seat has the root part at s (0-1 of its time), in the car's frame: from where the
-- hop began to just over the seat, up over the sill on the way, turning to face forward.
local function hopAt(e, s)
	local k = s * s * (3 - 2 * s)
	return e.hopFrom:Lerp(e.seatLocal, k) + Vector3.new(0, math.sin(math.pi * s) * e.hopArc, 0)
end

-- How far along that arc (0-1 of its time) the character may go while it is still a body of its own: up
-- to where its root part comes within K.SILL studs of the car's solid box (the chassis, with the bump
-- stops under it). This device makes the character pass through cars for the arc, but the server does
-- not: there the car is solid, and while it stands empty the server moves it, so a body put inside it
-- would shove the car aside for everybody. 1 = all the way (a boat's seat is on top of its hull).
local function sillStop(e)
	local half = e.chassis.Size / 2 + Vector3.new(K.SILL, K.SILL, K.SILL)
	local steps = 24
	for i = 0, steps do
		local p = hopAt(e, i / steps).Position
		if math.abs(p.X) < half.X and math.abs(p.Y) < half.Y and math.abs(p.Z) < half.Z then
			return math.max(i - 1, 0) / steps
		end
	end
	return 1
end

-- The arc into the seat starts, from wherever the character is right now.
local function startHop(e)
	local anchor = anchorOf(e)
	e.hopFrom = anchor:ToObjectSpace(e.root.CFrame)
	local reach = (e.hopFrom.Position - e.seatLocal.Position).Magnitude
	e.hopArc = math.clamp(reach * 0.16, K.HOP_ARC, 2.2)
	if e.kind == "enter" then
		-- A real car: ask for the seat right away (the server only needs us within 16 studs of it) and
		-- lean in no further than the sill until its weld is there (sillStop; takeSeat plays the rest).
		e.sendAt = 0
		e.hopStop = sillStop(e)
	else
		-- A traffic car is only a picture on this device, and the server builds the real one and sits us
		-- in it in one step: the arc goes all the way, and the server is asked about a round trip before
		-- it ends (a little more: the car is built first), so the seat takes over just as we land.
		local lag = 0.12
		pcall(function()
			lag = math.clamp(player:GetNetworkPing() * 2 + 0.08, 0.08, 0.4)
		end)
		e.sendAt = math.max(0, e.hopTime - (lag + 0.06))
		e.hopStop = 1
	end
	e.drawn, e.drawnS = e.hopFrom, 0
	e.landedAt = nil
	e.bodyRoot = e.root.AssemblyRootPart -- (changes the moment the seat's weld joins us to the car)
	holdLocomotion(true)
	passThrough(e, true)
	e.hum:Move(Vector3.zero, false)
	e.phase, e.phaseAt = "hop", os.clock()
end

-- The door opens: the handle sound, and at a traffic car the driver comes out (TrafficClient).
local function openDoor(e)
	holdLocomotion(true) -- (a second press can bring us here straight from the walk)
	e.phase, e.phaseAt = "door", os.clock()
	if e.kind == "enter" then
		playLocal("DoorOpen", e.seat)
	else
		local anchor = anchorOf(e)
		playLocal("DoorOpen", anchor:PointToWorldSpace(e.handle or e.seatLocal.Position))
		pcall(TrafficClient.PullDriver, e.car, e.root.Position)
	end
end

-- At the door: the hand goes out first, unless we're in a hurry. From here on LocomotionClient is held
-- off (it would add a braking step past the door, and lean the body we are about to pose).
local function arrive(e)
	holdLocomotion(true)
	e.hum:Move(Vector3.zero, false)
	if e.fast then
		openDoor(e)
	else
		e.phase, e.phaseAt = "reach", os.clock()
	end
end

-- Turn the character toward the car (the door spot looks at it), quickly but not in one frame.
local function face(e, door, dt)
	local look = flat(door.LookVector)
	local mine = flat(e.root.CFrame.LookVector)
	if look.Magnitude < 0.05 or mine.Magnitude < 0.05 then
		return
	end
	local yaw = yawOf(mine)
	yaw += angleDiff(yawOf(look), yaw) * (1 - math.exp(-dt * 14))
	e.root.CFrame = CFrame.new(e.root.Position) * CFrame.Angles(0, yaw, 0)
end

-- Is the player steering away from this? to: flat vector from the character to the door. A fresh push on
-- the stick always counts. The push they pressed the button with (running along the car, the door already
-- beside or behind them) says nothing: they pressed with the stick right there. It only counts once they
-- steer it somewhere else (more than 60 degrees from where it pointed at the press) and that is away
-- from the car.
local function stickCancels(e, to, now)
	local v = moveVector()
	local m = v.Magnitude
	if m < 0.2 then
		e.released = true
		e.pushedAt = nil
		return false
	end
	if m < 0.5 then
		return false
	end
	if not e.released then
		local world = pushDir(v)
		if not world or to.Magnitude < 0.5 or world:Dot(to.Unit) > -0.3
			or (e.heldDir ~= nil and world:Dot(e.heldDir) >= 0.5) then
			e.pushedAt = nil
			return false
		end
	end
	e.pushedAt = e.pushedAt or now
	return now - e.pushedAt >= K.STICK_HOLD
end

-- Is what we're getting into still there for us?
local function stillThere(e)
	if e.kind == "enter" then
		local seat = e.seat
		return e.car.Parent ~= nil and e.chassis.Parent ~= nil and seat.Parent ~= nil
			and (seat.Occupant == nil or seat.Occupant == e.hum)
	end
	return e.sent or TrafficClient.IsHeld(e.car)
end

-- The next spot to walk to on the way to the door, in the car's frame (only X and Z matter): the door
-- spot itself when the straight line there is clear of the car's body, else round the body's corner
-- first. p: where the character is, in that frame. Returns the spot, and true when it is the door.
-- (Your car is delivered ahead of you, facing away: the usual first GET IN starts right behind it, and
-- the straight line from there goes through its rear corner. A traffic car stops with its nose at you.)
local function routeStep(e, p)
	local d = e.doorLocal.Position
	local hl = e.halfLen
	if not hl then
		return d, true
	end
	local side = d.X < 0 and -1 or 1
	local hw = math.max(math.abs(d.X) - K.DOOR_OUT, 1) -- half the body's width
	local out = side * p.X -- how far out we are on the door's side (negative: on the other side)
	if out >= hw + 1 then
		return d, true -- beside the body on the door's side already: nothing in the way
	end
	if math.abs(p.Z) >= hl + 0.3 then
		-- In front of the car or behind it: to the corner on the door's side, clear of the bumper.
		return Vector3.new(d.X, d.Y, (p.Z < 0 and -1 or 1) * (hl + K.ROUND)), false
	end
	if -out >= hw + 0.3 then
		-- Beside the body on the wrong side (this side's door is walled off): along it, a step out from
		-- it, to past whichever end is the shorter way round.
		local nose = (p.Z + d.Z < 0) and -1 or 1
		return Vector3.new(-side * math.max(-out, hw + 1.5), d.Y, nose * (hl + K.ROUND)), false
	end
	return d, true -- on the car itself (its roof, its bonnet) or squeezed against its side: straight there
end

-- How far the walk to the door is from p, going that way (studs, flat).
local function routeLength(e, p)
	local total = 0
	for _ = 1, 4 do
		local goal, last = routeStep(e, p)
		total += flat(goal - p).Magnitude
		if last then
			break
		end
		p = goal
	end
	return total
end

-- One frame of the get-in (bound to the render step while one runs).
local function enterFrame(e, dt)
	local now = os.clock()
	local hum, root = e.hum, e.root
	-- Seated, or welded to the seat (which shows a moment before SeatPart does): the server has us. Hands
	-- off the root part from here on: moving it now would move the whole car.
	if hum.SeatPart or (e.bodyRoot and root.AssemblyRootPart ~= e.bodyRoot) then
		takeSeat(e)
		return
	end
	if player.Character ~= e.char or not root.Parent or hum.Health <= 0 or not stillThere(e)
		or ImpactClient.IsKnocked() or (player:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow() then
		cancelEnter(e)
		return
	end
	local anchor = anchorOf(e)
	local phase = e.phase
	if phase ~= "hop" then
		local door = anchor * e.doorLocal
		local to = flat(door.Position - root.Position)
		local dist = to.Magnitude
		-- (once a traffic car's driver is coming out there's no walking away from it)
		local committed = e.kind == "jack" and phase == "door"
		if not committed and (dist > K.GETIN_MAX_DIST or stickCancels(e, to, now)) then
			cancelEnter(e)
			return
		end
		if phase == "approach" then
			if dist <= K.ARRIVE then
				arrive(e)
			elseif now - e.phaseAt >= (e.approachMax or K.APPROACH_MAX) then
				-- (the last resort: something kept us from walking there)
				root.CFrame = standAt(e, door)
				root.AssemblyLinearVelocity = Vector3.zero
				arrive(e)
			else
				-- Round the car's corner first if its body is in the way, then to the door.
				local walk = to
				local goal, last = routeStep(e, anchor:PointToObjectSpace(root.Position))
				if not last then
					local leg = flat(anchor:PointToWorldSpace(goal) - root.Position)
					if leg.Magnitude > 0.3 then
						walk = leg
					end
				end
				hum:Move(walk.Unit, false)
			end
			return
		end
		-- At the door: stand still, turn to the car, the hand out to the handle.
		hum:Move(Vector3.zero, false)
		face(e, door, dt)
		OVERLAY.Side = -e.side -- the handle is at the back of the door: the right hand on the driver's side
		OVERLAY.Target = e.handle and anchor:PointToWorldSpace(e.handle) or nil
		if phase == "reach" then
			local s = (now - e.phaseAt) / K.REACH_TIME
			OVERLAY.Reach = math.clamp(s, 0, 1)
			if s >= 1 then
				openDoor(e)
			end
		else
			local s = (now - e.phaseAt) / e.doorTime
			OVERLAY.Reach = e.fast and math.clamp(s * 2, 0, 1) or 1
			if s >= 1 then
				startHop(e)
			end
		end
		return
	end

	-- The arc (hopAt), in the car's own frame: all the way into a traffic car's seat, as far as the sill
	-- of a real car (e.hopStop). Held there until the seat takes over (takeSeat, above).
	local t = now - e.phaseAt
	if not e.sent and t >= e.sendAt then
		send(e)
	end
	local full = math.clamp(t / e.hopTime, 0, 1)
	local s = math.min(full, e.hopStop)
	local cf = hopAt(e, s)
	e.drawn, e.drawnS = cf, s
	root.CFrame = anchor * cf
	root.AssemblyLinearVelocity = e.chassis and e.chassis.AssemblyLinearVelocity or Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	OVERLAY.Reach = math.max(0, 1 - s * 2.5)
	OVERLAY.Duck = math.sin(math.pi * math.min(s * 1.1, 1))
	if full >= 1 then
		e.landedAt = e.landedAt or now
		if now - e.landedAt > e.waitTime then
			cancelEnter(e) -- the server never seated us (refused, or the request was lost)
		end
	end
end

local function enterStep(dt)
	local e = S.entering
	if not e then
		return
	end
	local ok, err = pcall(enterFrame, e, dt)
	if ok then
		return
	end
	-- Something broke part-way: never leave the player half in. Wind it up, and for our own car fall
	-- back on the plain request (the server seats us at once, as it always could).
	warn("[InteractClient] getting in: " .. tostring(err))
	local sent = e.sent
	pcall(cancelEnter, e)
	if S.entering == e then
		S.entering = nil
		pcall(function()
			RunService:UnbindFromRenderStep(K.GETIN_STEP)
		end)
		holdLocomotion(false)
		pcall(passThrough, e, false)
		OVERLAY.Reach, OVERLAY.Duck, OVERLAY.Target = 0, 0, nil
	end
	if e.kind == "enter" and not sent and e.car.Parent then
		fireEnter(e.car)
	end
end

local function newEntry(kind, car, char, hum, root)
	local now = os.clock()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true -- see-through triggers aren't walls
	params.IgnoreWater = true
	local ignore = { char }
	if typeof(car) == "Instance" then
		table.insert(ignore, car)
	end
	for _, name in ipairs({ "Traffic", "Peds", "Smoke" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character) -- people aren't walls, or ground to stand on
		end
	end
	params.FilterDescendantsInstances = ignore
	local vel = root.AssemblyLinearVelocity
	local fast = (player:GetAttribute("Heat") or 0) > 0 or Vector3.new(vel.X, 0, vel.Z).Magnitude > K.SPRINTING
	local push = moveVector()
	local released = push.Magnitude < 0.2 -- false: they pressed while pushing the stick...
	return {
		kind = kind, car = car, char = char, hum = hum, root = root, params = params,
		fast = fast, hopTime = fast and K.HOP_TIME_FAST or K.HOP_TIME,
		phase = "approach", phaseAt = now, startedAt = now,
		released = released,
		heldDir = not released and pushDir(push) or nil, -- ...this way (stickCancels)
		sent = false, side = -1,
	}
end

-- The door to use: the one on our side of the car, unless something solid stands between it and the
-- cabin (a wall the car is parked against) or it's on another level; then the other one. driver /
-- passenger: door spots in the frame `anchor`; from: a point inside the cabin (world). Returns the spot
-- and its side (-1 driver's, 1 passenger's), or nil when neither will do.
local function chooseDoor(e, anchor, driver, passenger, from)
	local rel = anchor:PointToObjectSpace(e.root.Position)
	local first, second, side = driver, passenger, -1
	if rel.X > 0.5 then
		first, second, side = passenger, driver, 1
	end
	for i = 1, 2 do
		local spot = i == 1 and first or second
		local world = anchor:PointToWorldSpace(spot.Position)
		if math.abs(world.Y - e.root.Position.Y) < 6 and not Workspace:Raycast(from, world - from, e.params) then
			return spot, i == 1 and side or -side
		end
	end
	return nil
end

local function setDoor(e, spot, side)
	e.doorLocal, e.side = spot, side
	-- The handle: at the body's side, toward the back of the door, about hip high.
	local p = spot.Position
	e.handle = Vector3.new(p.X - (p.X < 0 and -1 or 1) * 1.5, p.Y + 0.2, p.Z + 0.9)
end

-- A real car's two door spots in its chassis' frame: the server's attachments, else worked out here
-- (a car from before CarBuilder made them).
local function carDoors(car, chassis, seat)
	local driver, passenger
	local a, b = chassis:FindFirstChild("DriverDoor"), chassis:FindFirstChild("PassengerDoor")
	if a and a:IsA("Attachment") then
		driver = a.CFrame
	end
	if b and b:IsA("Attachment") then
		passenger = b.CFrame
	end
	if not driver or not passenger then
		local ride = car:GetAttribute("RideHeight")
		local x = chassis.Size.X / 2 + 2.6
		local y = -(type(ride) == "number" and ride or chassis.Size.Y / 2 + 1.6) + 3
		local z = chassis.CFrame:PointToObjectSpace(seat.Position).Z - 0.6
		driver = driver or CFrame.lookAt(Vector3.new(-x, y, z), Vector3.new(0, y, z))
		passenger = passenger or CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(0, y, z))
	end
	return driver, passenger
end

-- Half the length of a real car's body, bumper to bumper (what you see is a little longer than the
-- chassis under it; never trusted past 1.5 x the chassis, in case something odd is welded on).
local function halfLength(car, chassis)
	local len = chassis.Size.Z
	local ok, size = pcall(car.GetExtentsSize, car)
	if ok and typeof(size) == "Vector3" then
		len = math.clamp(size.Z, len, len * 1.5)
	end
	return len / 2
end

local function begin(e)
	-- How long the walk to the door may take: the way there (round the car if need be) at a walk, plus
	-- a moment to get going.
	if e.doorLocal then
		local ok, way = pcall(routeLength, e, anchorOf(e):PointToObjectSpace(e.root.Position))
		e.approachMax = (ok and type(way) == "number") and math.clamp(way / K.WALK_PACE + 0.4, K.APPROACH_MIN, K.APPROACH_MAX)
			or K.APPROACH_MAX
	end
	pcall(function()
		RunService:UnbindFromRenderStep(K.GETIN_STEP)
	end)
	endSettle() -- (the last get-in's final move, should it still be running)
	S.entering = e
	S.riseAt = nil
	RunService:BindToRenderStep(K.GETIN_STEP, Enum.RenderPriority.Input.Value + 10, enterStep)
end

-- Start getting into our own (or stolen) car. Returns false when it can't even begin.
local function startEnter(car)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local seat = car:FindFirstChild("DriverSeat")
	local chassis = car.PrimaryPart
	if not hum or not root or hum.Health <= 0 or hum.SeatPart or not chassis or not (seat and seat:IsA("BasePart")) then
		return false
	end
	local e = newEntry("enter", car, char, hum, root)
	e.seat, e.chassis = seat, chassis
	local cf = chassis.CFrame
	e.seatLocal = cf:ToObjectSpace(seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + K.SEAT_UP, 0))
	e.doorTime = e.fast and K.DOOR_TIME_FAST or K.DOOR_TIME
	e.waitTime = K.HOP_WAIT
	-- A boat is boarded from the dock in one jump, and a car on its side or roof has no door to walk to.
	if car:GetAttribute("Boat") ~= true and cf.UpVector.Y > 0.5 then
		local driver, passenger = carDoors(car, chassis, seat)
		local spot, side = chooseDoor(e, cf, driver, passenger, seat.Position + cf.UpVector * 1.5)
		if spot then
			setDoor(e, spot, side)
			e.halfLen = halfLength(car, chassis)
		end
	end
	begin(e)
	if not e.doorLocal then
		startHop(e)
	end
	return true
end

-- Start jacking a traffic car: it stops (TrafficClient.Jack) and we go to its door. Returns false when
-- it can't be taken any more.
local function startJack(car)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 or hum.SeatPart then
		return false
	end
	local info = TrafficClient.Jack(car)
	if not info then
		return false
	end
	S.lastJack = os.clock()
	S.target = nil
	local e = nil
	local ok, err = pcall(function()
		local origin, driver, passenger, seatLocal, halfLen = TrafficClient.JackSpots(car)
		if not origin then
			return
		end
		local entry = newEntry("jack", car, char, hum, root)
		entry.info, entry.origin, entry.seatLocal = info, origin, seatLocal
		entry.doorTime = entry.fast and K.TUG_TIME_FAST or K.TUG_TIME
		entry.waitTime = K.HOP_WAIT_JACK
		local spot, side = chooseDoor(entry, origin, driver, passenger, origin:PointToWorldSpace(seatLocal.Position))
		if spot then
			-- (a traffic car's body is no wall on this device: without this the walk would go through it)
			entry.halfLen = type(halfLen) == "number" and halfLen or nil
		else
			-- Both doors walled off: the door is opened from where we stand.
			local here, at = root.Position, origin.Position
			side = origin:PointToObjectSpace(here).X > 0 and 1 or -1
			if flat(at - here).Magnitude > 0.5 then
				spot = origin:ToObjectSpace(CFrame.lookAt(here, Vector3.new(at.X, here.Y, at.Z)))
			else
				spot = side > 0 and passenger or driver
			end
		end
		setDoor(entry, spot, side)
		e = entry
	end)
	if not ok then
		warn("[InteractClient] jack: " .. tostring(err))
	end
	if not e then
		-- The plain way: ask at once (TrafficClient sends the driver out when the real car arrives).
		task.spawn(function()
			Remotes.Event("RequestCarjack"):FireServer(info.Kind, info.CFrame, info.Color)
		end)
		return true
	end
	begin(e)
	return true
end

-- The key or the button again while a get-in runs: skip ahead. Straight to the arc for our own car (from
-- further than a few steps away the seat simply takes us, with nothing to act out); at a traffic car the
-- door opens right now, from where we stand (its driver has to come out first).
local function hurryEnter()
	local e = S.entering
	if not e or e.phase == "hop" or os.clock() - e.startedAt < 0.25 then
		return
	end
	if e.kind == "enter" then
		startHop(e)
	elseif e.phase ~= "door" then
		openDoor(e)
	end
end

------------------------------------------------------------------ actions

-- GET IN: walk to the door and get in (see "getting in, step by step"). If that can't start, the plain
-- request the server always took.
local function requestEnter(car)
	if S.entering then
		hurryEnter()
		return
	end
	-- Just got out: a second press of the same key (F and E both get you out AND in) that lands after the
	-- server has stepped us out must not walk us straight back in. The mirror of K.EXIT_LOCK. (1.2 s: at
	-- 0.6 a player pressing F a second time "to be sure" was back at the wheel before he knew he had been
	-- out, and to him F had not worked.)
	if os.clock() - (S.leftAt or 0) < 1.2 then
		return
	end
	if os.clock() - S.lastEnter < 0.4 then
		return
	end
	S.lastEnter = os.clock()
	local ok, started = pcall(startEnter, car)
	if not ok then
		warn("[InteractClient] get in: " .. tostring(started))
		if S.entering then
			pcall(cancelEnter, S.entering)
		end
	end
	if not (ok and started) then
		fireEnter(car)
	end
end

-- JACK: TrafficClient stops the traffic car, we open its door (the driver comes out) and hop in while the
-- server builds the real one and sits us in it.
local function requestJack(car)
	if S.entering then
		hurryEnter()
		return
	end
	-- Just got out (see requestEnter): the same key again must not take the nearest street car either.
	if os.clock() - (S.leftAt or 0) < 1.2 then
		return
	end
	if os.clock() - S.lastJack < K.JACK_COOLDOWN then
		return
	end
	local ok, err = pcall(startJack, car)
	if not ok then
		warn("[InteractClient] jack: " .. tostring(err))
		if S.entering then
			pcall(cancelEnter, S.entering)
		end
	end
end

-- Is the get-in running right now (it walks and moves the character)? For controllers that also do.
function InteractClient.IsEntering()
	return S.entering ~= nil
end

-- Is a proximity prompt that gamepad X triggers on screen right now? Then X is that prompt's button.
local function xPromptShowing()
	for prompt in pairs(shownPrompts) do
		-- (still really there: not switched off, and not held back by PromptGate)
		if prompt.Parent and prompt.Enabled and prompt.MaxActivationDistance > 0
			and prompt.GamepadKeyCode == Enum.KeyCode.ButtonX then
			return true
		end
	end
	return false
end

-- The same for the E key: a bubble that E triggers is on screen, so E is that bubble's key.
local function ePromptShowing()
	for prompt in pairs(shownPrompts) do
		if prompt.Parent and prompt.Enabled and prompt.MaxActivationDistance > 0
			and prompt.KeyboardKeyCode == Enum.KeyCode.E then
			return true
		end
	end
	return false
end

-- How to hold a prompt by hand ("pick the lock" / "break in"), when our hold didn't start.
local function stealHelp(prompt)
	if os.clock() - S.lastHelp < 6 then
		return
	end
	S.lastHelp = os.clock()
	local breakIn = prompt ~= nil and CollectionService:HasTag(prompt, "BreakInPrompt")
	local verb = breakIn and "break in" or "pick the lock"
	local bubble = breakIn and "Break in" or "Pick lock"
	local mode = inputMode()
	local text = "Hold E next to the car to " .. verb .. "!"
	if mode == "touch" then
		text = "Tap and hold the " .. bubble .. " bubble on the car!"
	elseif mode == "gamepad" then
		text = "Hold X next to the car to " .. verb .. "!"
	end
	NotifyController.Show(text, K.GOLD)
end

local function endHold()
	local prompt = S.holding
	S.holding, S.holdSource = nil, nil
	if S.holdInputConn then
		S.holdInputConn:Disconnect()
		S.holdInputConn = nil
	end
	S.holdInput = nil
	if prompt then
		pcall(function()
			prompt:InputHoldEnd()
		end)
	end
end

-- Hold a Pick lock / Break in prompt for the player (released by endHold).
local function beginHold(prompt, source)
	if S.holding or not prompt then
		return false
	end
	S.holding, S.holdSource, S.holdAskedAt, S.holdWarned = prompt, source, os.clock(), false
	local ok = pcall(function()
		prompt:InputHoldBegin()
	end)
	if not ok then
		endHold()
		stealHelp(prompt)
		return false
	end
	return true
end

-- Fresh look around (10 times a second).
local function refresh()
	S.target, S.hintText = nil, nil
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local civilian = player:GetAttribute("Side") == "Civilian" and player:GetAttribute("HasPicked") == true
	local inHome = player:GetAttribute("InHome") == true
	syncBreakIns(civilian and not inHome and hum ~= nil and hum.Health > 0 and not hum.SeatPart)
	local sitting = hum and hum.SeatPart
	if sitting ~= S.satIn then
		S.satIn, S.satAt = sitting, os.clock()
		S.satPos, S.drove = root and root.Position or nil, false
		S.slowSince = nil
	end
	if not hum or not root or hum.Health <= 0 or player:GetAttribute("HasPicked") ~= true
		or player:GetAttribute("Side") == "Prisoner" then
		return
	end
	local seat = hum.SeatPart
	if not seat then
		local stunned = (player:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow()
		-- The dressing room (WardrobeUI) has the keys while it is open: E is its MASKS tab, and the character
		-- is held still. Next to your car at a hideout that same E also started GET IN, which pulled you
		-- into the seat and shut the room with the new look lost. So nothing is offered from in there (E, F,
		-- gamepad X or the button). Looked for on first use, softly: without that controller nothing changes.
		if S.wardrobe == nil then
			local module = script.Parent:FindFirstChild("WardrobeUI")
			local okW, mod = false, nil
			if module then
				okW, mod = pcall(require, module)
			end
			S.wardrobe = okW and type(mod) == "table" and type(mod.IsOpen) == "function" and mod or false
		end
		local dressing = S.wardrobe ~= false and S.wardrobe.IsOpen() == true
		if not stunned and not ImpactClient.IsKnocked() and not PhoneUI.IsOpen() and not dressing then
			S.target = findTarget(root.Position, nil, K.ENTER_RANGE, K.STEAL_RANGE)
			-- Just stepped out of this car (5 s, and for as long as we hold a lock for the player after
			-- that): a car we could take in range outranks it, however near it still is (you land 4.5
			-- studs from its seat, nearer than any car you pulled up to), so the next F takes THAT car
			-- and does not put you back in the one you left.
			local left = nil
			if S.target and S.target.kind == "enter" and S.target.car == S.leftCar
				and (S.holding ~= nil or os.clock() - (S.leftAt or 0) < 5) then
				left = S.target
				S.target = findTarget(root.Position, S.leftCar, K.ENTER_RANGE, K.STEAL_RANGE) or left
			end
			if civilian and not inHome then
				-- Whichever is nearest: your own (or stolen) car, a parked car to break into, a traffic car.
				local parked = findBreakIn(root.Position, K.BREAKIN_RANGE)
				if parked and (not S.target or S.target == left or parked.dist < S.target.dist) then
					S.target = parked
				end
				if os.clock() - S.lastJack >= K.JACK_COOLDOWN then
					local car, d = TrafficClient.FindJackable(root.Position, K.JACK_DOOR_RANGE, K.JACK_BOX_RANGE)
					-- Not while we hold this target's lock for the player (F or the button): a traffic car
					-- pulling up nearer mid-pick took the button over, which let go of the lock and emptied
					-- the bar with F still held down. JACK is back the moment the lock is done or let go.
					local picking = S.holding ~= nil and S.target ~= nil and S.target.prompt == S.holding
					if car and not picking and (not S.target or S.target == left or d < S.target.dist) then
						S.target = { kind = "jack", car = car, dist = d }
					end
				end
			end
		end
	elseif seat.Name == "DriverSeat" or seat.Name == "PassengerSeat" then
		local myCar = seat.Parent
		local chassis = myCar and myCar.PrimaryPart
		local speed = chassis and chassis.AssemblyLinearVelocity.Magnitude
		local now = os.clock()
		-- "Nearly stopped": under HINT_STOP_SPEED for HINT_SLOW_HOLD, and it only ends above HINT_SLOW_EXIT
		-- (easing in, or creeping round 10 studs/s, mustn't make the hint blink under a thumb on EXIT).
		if speed and speed < K.HINT_STOP_SPEED then
			S.slowSince = S.slowSince or now
		elseif not speed or speed > K.HINT_SLOW_EXIT then
			S.slowSince = nil
		end
		-- Been anywhere since we sat down? Kept once true, at any speed: driving round the block and back to
		-- the spot we got in at is still an arrival.
		if not S.drove and S.satPos and (root.Position - S.satPos).Magnitude >= K.HINT_DROVE then
			S.drove = true
		end
		-- (upside down, FLIP sits where the hint would go)
		if speed and speed < K.HINT_MAX_SPEED and chassis.CFrame.UpVector.Y > 0.5 then
			local pos = root.Position
			local slow = S.slowSince ~= nil and now - S.slowSince >= K.HINT_SLOW_HOLD
			-- Nearly stopped beside a store, ATM, vault or prep panel we could rob on foot right now. Not on
			-- a job shift, in a race or on a mission: robbing makes you wanted, which ends all three, so the
			-- hint would be pointing at the one thing that spoils what you're doing.
			local busy = player:GetAttribute("JobKind") ~= nil or player:GetAttribute("RacingId") ~= nil
				or player:GetAttribute("Mission") ~= nil
			local robDist = slow and civilian and not busy and HeistClient.NearestRob(pos, K.HINT_ROB_RANGE) or nil
			-- One hint at a time, the nearest reason wins: with a rob spot in reach, a car only counts if
			-- it's nearer still (so every car search stops at that distance).
			local reach = robDist or math.huge
			local near = findTarget(pos, myCar, math.min(K.HINT_RANGE, reach), math.min(K.HINT_RANGE, reach), true) ~= nil
			-- Citizens nearly stopped beside a car BREAK IN or JACK would offer on foot (none of those while
			-- the last jack or break-in is still cooling down).
			if not near and civilian and not inHome and slow and now - S.satAt >= K.HINT_SETTLE
				and now - math.max(S.lastJack, S.lastTake) >= K.JACK_COOLDOWN then
				near = findBreakIn(pos, math.min(K.HINT_TAKE_RANGE, reach), true) ~= nil
					or TrafficClient.FindJackable(pos, math.min(K.HINT_TAKE_RANGE, reach), math.min(K.HINT_TAKE_BOX, reach)) ~= nil
			end
			-- Nearly stopped, having driven here, beside any other bubble PromptGate is holding back that
			-- would be up on foot (a display car, a front door, a dropped bag, the gun shop counter, a show
			-- car's Like, a treasure spot): the same words, so a hidden bubble never leaves you guessing.
			-- (Anyone, not only citizens: a cop in a cruiser has to step out for a dropped bag too.)
			if not near and slow and S.drove then
				local d = PromptGate.NearestHidden(pos, K.HINT_NOT_FOR, myCar)
				near = d ~= nil and d <= reach
			end
			if near then
				S.hintText = K.HINT_CAR
			elseif robDist then
				S.hintText = K.HINT_ROB
			end
		end
	end
	-- Walked away, got in, or someone else stole it: let go of the lock.
	if S.holding and (not S.target or S.target.prompt ~= S.holding) then
		endHold()
	end
end

-- Car alarms (twice a second): start ringing on cars whose CarAlarmUntil is still ahead, stop the rest.
local function alarms()
	local now = Workspace:GetServerTimeNow()
	local folder = Workspace:FindFirstChild("Vehicles")
	if folder then
		for _, car in ipairs(folder:GetChildren()) do
			local untilT = car:GetAttribute("CarAlarmUntil")
			if not ringing[car] and typeof(untilT) == "number" and untilT > now and car.PrimaryPart then
				ringing[car] = SoundClient.Play("Alarm", car.PrimaryPart) or true
			end
		end
	end
	for car, sound in pairs(ringing) do
		local untilT = car.Parent and car:GetAttribute("CarAlarmUntil")
		if not (typeof(untilT) == "number" and untilT > now) then
			if typeof(sound) == "Instance" then
				pcall(function()
					sound:Stop()
				end)
			end
			ringing[car] = nil
		end
	end
end

local function setText(l, text)
	if l.Text ~= text then
		l.Text = text
	end
end

-- Every frame: the button, its fill, and the hint's spot next to EXIT.
local function render()
	local t = S.target
	ui.button.Visible = t ~= nil
	if t then
		local mode = inputMode()
		local color, main, key
		if t.kind == "enter" then
			color, main = K.MINT, "GET IN"
			key = mode == "keyboard" and "F" or (mode == "gamepad" and "X" or "")
		elseif t.kind == "jack" then
			color, main = K.PINK, "JACK"
			key = mode == "keyboard" and "F" or (mode == "gamepad" and "X" or "")
			key = key .. (key ~= "" and " · " or "") .. string.upper(t.car.kind or "car")
		else
			color, main = K.GOLD, t.breakIn and "BREAK IN" or "STEAL"
			key = mode == "keyboard" and "HOLD F" or (mode == "gamepad" and "HOLD X" or "HOLD")
			local value = t.car and t.car:GetAttribute("HotValue")
			if typeof(value) == "number" then
				key = key .. " · " .. HUDController.Money(value)
			end
		end
		ui.buttonStroke.Color = color
		ui.mainLabel.TextColor3 = Theme.Color.Text -- white words; the action's colour is the thin outline
		local touchNow = mode == "touch"
		if S.actionTouch ~= touchNow then
			S.actionTouch = touchNow
			Theme.Place(ui.button, "Action", touchNow)
		end
		setText(ui.mainLabel, main)
		setText(ui.keyLabel, key)
		ui.keyLabel.Visible = key ~= ""
		ui.mainLabel.Position = key ~= "" and UDim2.fromScale(0.5, 0.36) or UDim2.fromScale(0.5, 0.5)
		-- Progress of the lock pick / break-in (the prompt's own hold, whether it came from E, F or the button).
		local began = t.prompt and holdBegan[t.prompt]
		local p = 0
		if began then
			p = math.clamp((os.clock() - began) / math.max(t.prompt.HoldDuration, 0.1), 0, 1)
		end
		ui.fill.Visible = p > 0
		ui.fill.Size = UDim2.fromScale(p, 1)
		-- We asked for a hold but the prompt never started: tell them how to do it by hand.
		if S.holding and not S.holdWarned and not holdBegan[S.holding] and os.clock() - S.holdAskedAt > 0.5 then
			S.holdWarned = true
			stealHelp(S.holding)
		end
	end

	-- The seated hint lives next to DriveUI's EXIT button (drivers and passengers both have it): no EXIT on
	-- screen, no hint. (hintText is dropped the moment the seat changes, see watchSeat; this is for any
	-- other time EXIT isn't there, so the hint never sits somewhere else on screen by itself.)
	local words = S.hintText
	local exit = words and DriveUI.ExitButton
	local exitGui = exit and exit:FindFirstAncestorOfClass("ScreenGui")
	local show = exitGui ~= nil and exitGui.Enabled and exit.Visible
	if ui.hint.Visible ~= show then
		ui.hint.Visible = show
	end
	if show then
		-- The key cap names EXIT's key for the device in hand (F / B; on touch, the button's own word).
		local mode = inputMode()
		local key = mode == "touch" and "EXIT" or (mode == "gamepad" and "B" or "F")
		if ui.hintKey.Text ~= key then
			ui.hintKey.Text = key
			ui.hintKey.Size = UDim2.fromOffset(math.max(22, 10 + #key * 9), 22) -- (as Theme.Key sizes it)
		end
		-- Thumb-sized on touch, where it gets tapped.
		local height = mode == "touch" and Theme.Touch or K.HINT_HEIGHT
		if ui.hint.Size.Y.Offset ~= height then
			ui.hint.Size = UDim2.fromOffset(0, height)
		end
		setText(ui.hintLabel, words)
		-- Where it goes is DriveUI's call, since EXIT moves with the device: HintSpot gives FLIP's place
		-- (right above EXIT on a PC, left of the Buttons row on a phone; the hint needs the car upright
		-- and FLIP needs it on its roof, so the two never meet) as an anchor and pixels from the corner of
		-- a full-screen ScreenGui, which ours is.
		local ax, ay, x, y = 1, 0, nil, nil
		if DriveUI.HintSpot then
			local anchor, sx, sy = DriveUI.HintSpot()
			if anchor then
				ax, ay, x, y = anchor.X, anchor.Y, sx, sy
			end
		end
		if not x then
			-- A DriveUI that doesn't say: right under EXIT, lined up with its right edge, or right above it
			-- when EXIT sits too low on the screen for that. (AbsolutePosition starts under the top bar,
			-- so measure from this ScreenGui's own corner: right whichever way Roblox counts it.)
			local origin = ui.gui.AbsolutePosition
			local ep, es = exit.AbsolutePosition, exit.AbsoluteSize
			x, y = ep.X - origin.X + es.X, ep.Y - origin.Y + es.Y + 8
			if y + height > ui.gui.AbsoluteSize.Y then
				ay, y = 1, ep.Y - origin.Y - 8
			end
		end
		local anchorNow = ui.hint.AnchorPoint
		if anchorNow.X ~= ax or anchorNow.Y ~= ay then
			ui.hint.AnchorPoint = Vector2.new(ax, ay)
		end
		ui.hint.Position = UDim2.fromOffset(x, y)
	end

	-- Just stepped out of a car: straighten up from a stoop (looks only; you can already walk).
	if S.riseAt then
		local s = (os.clock() - S.riseAt) / K.RISE_TIME
		if S.entering then
			S.riseAt = nil -- (a get-in owns the pose now)
		elseif s >= 1 then
			S.riseAt = nil
			OVERLAY.Duck = 0
		else
			OVERLAY.Duck = 0.85 * (1 - s) * (1 - s)
		end
	end
end

------------------------------------------------------------------ init

local function releaseButton(input)
	if input == S.holdInput and S.holdSource == "button" then
		endHold()
	end
end

-- Our seat just changed. Sat down: a get-in that was on its way ends here (takeSeat). Sat down to drive a
-- car: its name comes up (nameCar) and the starter turns over (not on boats, nor on a car with the silent
-- electric "Whisper" exhaust). Stood up out of a car: the character straightens up from a stoop (render).
local function seatChanged(hum)
	local seat = hum.SeatPart
	local was = S.seatNow
	S.seatNow = seat
	if seat then
		S.riseAt = nil
		-- Right now, not on the next frame of the get-in: the weld has just put the character in the seat,
		-- and the rest of the arc must take it back out before anything is drawn (beginSettle).
		local e = S.entering
		if e and e.hum == hum then
			local ok, err = pcall(takeSeat, e)
			if not ok then
				warn("[InteractClient] taking the seat: " .. tostring(err)) -- (enterStep winds it up next frame)
			end
		end
		local car = seat.Parent
		if seat.Name == "DriverSeat" and car and car:IsA("Model") and car:GetAttribute("NCVehicle") then
			nameCar(car)
			local chassis = car.PrimaryPart
			if chassis and car:GetAttribute("Boat") ~= true and car:GetAttribute("Exhaust") ~= "Whisper" then
				playLocal("EngineStart", chassis)
			end
		end
		return
	end
	endSettle() -- (out again before the arc was done: the weld is gone, or about to be)
	if was then
		S.leftAt = os.clock() -- (requestEnter: no getting back in for a moment)
		S.leftCar = was.Parent -- (refresh: for a few seconds a car we could take outranks this one)
	end
	if was and (was.Name == "DriverSeat" or was.Name == "PassengerSeat") and not S.entering and hum.Health > 0 then
		S.riseAt = os.clock()
	end
end

-- The hint is about the seat we were in when refresh last looked, up to 0.1 s ago. The moment the seat
-- changes (stood up, moved over) it's dropped, so it goes on the same frame as EXIT and not a few frames
-- later; the next refresh works out what the new seat needs. One connection, for the current character.
-- (The same moment ends a get-in, names the car and starts the stepping-out pose: seatChanged.)
local function watchSeat(char)
	if S.seatConn then
		S.seatConn:Disconnect()
		S.seatConn = nil
	end
	local hum = char:WaitForChild("Humanoid", 10)
	if hum and player.Character == char then
		S.seatConn = hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
			S.hintText = nil
			local ok, err = pcall(seatChanged, hum)
			if not ok then
				warn("[InteractClient] seat: " .. tostring(err))
			end
		end)
	end
end

function InteractClient.Init()
	build()
	-- VehicleFeel draws the poses of getting in. ClientMain starts it as well when it's in its list;
	-- starting it twice does nothing.
	if VehicleFeel and type(VehicleFeel.Init) == "function" then
		local ok, err = pcall(VehicleFeel.Init)
		if not ok then
			warn("[InteractClient] VehicleFeel didn't start: " .. tostring(err))
		end
	end

	-- GET IN and JACK: a tap (again while it runs: skip ahead). STEAL / BREAK IN: press and hold (each
	-- finger tracked until it lifts, like DriveUI's pedals).
	ui.button.Activated:Connect(function()
		if S.entering then
			hurryEnter()
			return
		end
		local t = S.target
		if t and t.kind == "enter" then
			requestEnter(t.car)
		elseif t and t.kind == "jack" then
			requestJack(t.car)
		end
	end)
	ui.button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local t = S.target
		if not t or t.kind ~= "steal" or S.holding then
			return
		end
		if beginHold(t.prompt, "button") then
			S.holdInput = input
			S.holdInputConn = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
				local st = input.UserInputState
				if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
					releaseButton(input)
				end
			end)
		end
	end)
	ui.button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			releaseButton(input)
		end
	end)
	-- The seated hint: a tap or click gets you out, the same call as DriveUI's EXIT (any seat).
	ui.hint.Activated:Connect(function()
		DriveController.Exit()
	end)

	-- F / gamepad X on foot: get in, or jack. Holding F also picks a lock or breaks in (X-hold does that
	-- through the prompt itself). E gets you into your own car too (its Drive bubble is held back, see
	-- findTarget), as long as no other bubble on screen wants E. Seated, these keys are handled elsewhere.
	UserInputService.InputBegan:Connect(function(input, processed)
		local key = input.KeyCode
		if processed or (key ~= Enum.KeyCode.F and key ~= Enum.KeyCode.ButtonX and key ~= Enum.KeyCode.E) then
			return
		end
		if key == Enum.KeyCode.ButtonX and xPromptShowing() then
			return -- X belongs to that prompt
		end
		if key == Enum.KeyCode.E and ePromptShowing() then
			return -- E belongs to that bubble
		end
		if S.entering then
			hurryEnter() -- the key again while getting in: skip ahead
			return
		end
		refresh()
		local t = S.target
		if not t then
			return
		end
		if key == Enum.KeyCode.E then
			if t.kind == "enter" then
				requestEnter(t.car)
			end
			return -- (E does nothing else here: jacking and lock-picking keep F / X and their own bubbles)
		end
		if t.kind == "enter" then
			requestEnter(t.car)
		elseif t.kind == "jack" then
			requestJack(t.car)
		elseif t.kind == "steal" and key == Enum.KeyCode.F and not S.holding then
			beginHold(t.prompt, "F")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.F and S.holdSource == "F" then
			endHold()
		end
	end)

	-- Track every Pick lock / Break in hold on this device (E, F or the button) for the progress fill.
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		if prompt.Name == "PickLockPrompt" then
			holdBegan[prompt] = os.clock()
			if prompt == S.holding then
				S.holdWarned = true -- our hold did start: never show the "hold E" help for it
			end
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		holdBegan[prompt] = nil
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		holdBegan[prompt] = nil
		if prompt == S.holding then
			endHold() -- lock picked: let go now, not when refresh notices we're seated
		end
	end)
	-- Which prompts are on screen, so gamepad X is left to them (xPromptShowing).
	ProximityPromptService.PromptShown:Connect(function(prompt)
		shownPrompts[prompt] = true
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		shownPrompts[prompt] = nil
	end)

	-- The server refused a jack (no room, out of reach, too soon...): JACK comes back shortly, not in 8.5 s.
	-- (If we were on our way into its seat, that's off too: back on our feet at the door.)
	Remotes.OnClient("CarjackRefused", function()
		S.lastJack = os.clock() - K.JACK_COOLDOWN + K.JACK_RETRY
		local e = S.entering
		if e and e.kind == "jack" then
			pcall(cancelEnter, e)
		end
	end)
	-- A jack or break-in went through: the seated hint leaves street and parked cars alone for 8.5 s.
	Remotes.OnClient("Carjacked", function()
		S.lastTake = os.clock()
	end)

	-- Parked cars' Break in prompts as they stream in and out.
	CollectionService:GetInstanceAddedSignal("BreakInPrompt"):Connect(trackBreakIn)
	CollectionService:GetInstanceRemovedSignal("BreakInPrompt"):Connect(function(prompt)
		breakIns[prompt] = nil
	end)
	for _, prompt in ipairs(CollectionService:GetTagged("BreakInPrompt")) do
		trackBreakIn(prompt)
	end

	player.CharacterAdded:Connect(function(char)
		endHold()
		S.target, S.hintText = nil, nil
		-- A get-in or a pose of the old character's ends with it.
		if S.entering then
			pcall(cancelEnter, S.entering)
		end
		pcall(endSettle)
		S.settling = nil
		S.seatNow, S.riseAt = nil, nil
		OVERLAY.Reach, OVERLAY.Duck, OVERLAY.Target = 0, 0, nil
		watchSeat(char) -- (waits for the Humanoid: last)
	end)
	if player.Character then
		task.spawn(watchSeat, player.Character)
	end

	local lastWarn = 0
	RunService.RenderStepped:Connect(function(dt)
		S.accum += dt
		S.alarmAccum += dt
		-- The last of a get-in's arc, on the seat's weld (by itself, so nothing below can hold it up; if
		-- it breaks, the weld gets its own place back and that is that).
		if S.settling then
			local okSettle, errSettle = pcall(settleStep, os.clock())
			if not okSettle then
				pcall(endSettle)
				S.settling = nil
				warn("[InteractClient] settling in: " .. tostring(errSettle))
			end
		end
		local ok, err = true, nil
		if S.accum >= K.REFRESH then
			S.accum = 0
			ok, err = pcall(refresh)
			if not ok then
				S.target, S.hintText = nil, nil
			end
		end
		if ok then
			ok, err = pcall(render)
		end
		if ok and S.alarmAccum >= K.ALARM_CHECK then
			S.alarmAccum = 0
			ok, err = pcall(alarms)
		end
		if not ok and os.clock() - lastWarn > 5 then
			lastWarn = os.clock()
			warn("[InteractClient] " .. tostring(err))
		end
	end)
end

return InteractClient
