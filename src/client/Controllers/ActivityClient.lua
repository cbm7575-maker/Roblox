-- ActivityClient (ModuleScript, StarterPlayerScripts.Controllers.ActivityClient)
-- Client side of races, stunt jumps, the drift zone and taxi / courier shifts.
-- Positions come from Config.Activities; the server decides everything, this file only shows the way.
-- Look and motion follow a console open-world game, not a simulator: see-through checkpoint walls with
-- a chevron sign over them, a ring that bursts outward as you pass it, HUD text that drops in with a
-- short pop (UIScale) and fades out instead of blinking off. Every HUD piece has the flat "street" look
-- (Shared.Util.Theme: white Display / Body text with soft shadows, flat dark panels, colour only where
-- it means something) and sits in a Theme zone; placeHud re-places them when the screen or the device
-- changes.
--   * Race (ScreenGui "ActivityUI"):
--       - the countdown (frame "Countdown", Theme's Stamp zone), cinematic like HUDController's stamps:
--         the race's name small and gold on top, 3 - 2 - 1 large in white Display on a soft dark band,
--         a thin rule under it. Each number settles from a little bigger while the rule draws out; GO
--         is green, then it all fades;
--       - the time ("Timer", Display) with "CHECKPOINT 3 / 8" under it ("Checkpoint", small and gold,
--         pops at every checkpoint), straight on the screen in Theme's Banner zone;
--       - the finish card (frame "Finish", Theme's Stamp zone), cinematic: the race's name, FINISH, a
--         thin gold rule, then TIME, BEST and REWARD side by side, each a small word over a big value
--         (the words turn gold and read UNDER PAR / NEW BEST / WITH BONUS when that is the news; the
--         reward is green). It fades in piece by piece, stays 4.5 s and fades out. It waits (up to 3 s)
--         for a HUDController stamp that is up, and steps down under one that comes up while it shows.
--         A new countdown sends it away. Labels only: it never takes a tap.
--   * Race guidance (so you always know where to go):
--       - a line of big cyan chevrons on the road from your car through the NEXT checkpoint and on to
--         the one after it (GPSClient.SetPath draws it; it follows the roads, straight lines on water,
--         where it is white: cyan is lost on the turquoise sea), redrawn at every checkpoint and
--         re-planned from where you are if you leave it. Road routes run on the centre line; a race
--         with LineOffset (Highway 1 Loop) has its line moved that far into the racer's own lanes,
--         clear of the stunt ramps parked in the oncoming ones. The line also gives the minimap the
--         next checkpoint (GPSClient.MapGoal: its number, a flag for the finish);
--       - a missed checkpoint (a boat that went round the ring: on a road the ring is wider than the
--         road): once you are well past it and the server has not counted it, a toast says so and the
--         line is planned back to that ring only (not on to the next one, which would not count), so
--         WRONG WAY follows if you keep going;
--       - the next checkpoint is a see-through gold wall ring (brightest at the road and fading upward,
--         as wide as what the server counts) with a thin light beam. Over it stands a cyan chevron sign
--         facing you like a road sign, pointing the way you go AFTER it: one chevron for straight on or
--         a gentle bend (pointing up or leaning, sliding that way), two for a turn, three for a hairpin
--         (lighting up one after another toward the turn). The checkpoint after it is a much fainter
--         ring; the last one is a white ring under a chequered FINISH gate. A passed ring bursts
--         outward and fades;
--       - a turn cue under the Banner zone (three chevrons + LEFT / RIGHT) when the line bends more
--         than 35 degrees within the next 120-260 studs (further ahead the faster you go), and WRONG
--         WAY after 2 seconds of driving against the line;
--       - stopped on a start pad (under 8 studs/s, within 22 studs of its centre; the pad is 30 x 30)
--         the route shows as a faint line on the road and on the minimap. Those two only reach the
--         first few blocks, so a small card (frame "RacePreview", at the top of the Banner zone) shows
--         the WHOLE track as a little drawing (north up, a white dot at the start, a gold one at the
--         finish) next to the time to beat and the reward.
--         Only for someone who could start a race right now (free roam, not wanted, no mission or
--         shift: RaceService refuses everyone else), so a cop's or a mission's own GPS route is never
--         covered. The card stays hidden where it would sit on the minimap, the Buttons zone or
--         DriveUI's EXIT / FLIP (small phones; all measured for the screen in use); the BEST TIMES
--         board carries the same facts.
--   * Drift zone (DriftService scores; player attributes DriftScore / DriftCombo, optional DriftCash and
--     InDriftZone): a one-line toast the first time you come near it each session. Then ONE top-centre
--     row shows one thing at a time, in this order:
--       - a running chain: "DRIFT 1,240 x3 $49" (score, multiplier, the cash it is worth so far; it pops
--         when the multiplier goes up);
--       - a chain that just ended: a small "+$36 DRIFT" stamp (NEW BEST / CRASHED), or "TOO SHORT" when
--         it paid nothing. It waits while a HUDController stamp (RANK UP) covers the row, then fades out;
--       - in a car on the pad: the DRIFT ZONE banner with the how-to under its title, key caps from
--         the last input used ("Steer + [SPACE] then hold [W] + steer"; [X] / [RT] on a gamepad; the
--         phone's [DRIFT] / [GAS] buttons). It comes up as soon as you drive on, on every device, stays
--         until a chain has paid, and on a later visit (after 10 s off the pad) comes back for 6 s.
--         On keyboard / gamepad DriveUI's key strip (bottom of the screen) carries the same drift row
--         for its first seconds in the zone: while that strip is up the banner is its title alone, and
--         it grows its own how-to row when the strip has gone, so one how-to is on screen at a time.
--     The row sits at y 150 on a PC and y 104 on a phone (well above the car), moves down under any
--     top-centre panel across it (K.DRIFT_CLEAR, measured live; its bottom never past the middle of the
--     screen), and narrows / slides sideways to stay off the side columns that share its rows: the
--     minimap, toasts and right-hand buttons (Theme zones), DriveUI's EXIT / FLIP (measured live), and
--     the status / pills zones while that still leaves room. It is never narrower than the how-to row
--     needs (ui.howNeed, worked out from the words and the caps showing), short of the screen itself.
--   * Stunts: a STUNT JUMP stamp (HUDController.Stamp, gold: the jump's name on top, the distance, the
--     pay and how many are found under it); "slow-motion" camera while InStunt (DriveController).
--   * Race leaderboards: a BEST TIMES board over each race start pad, next to its RACE label (a
--     BillboardGui "RaceBoard_<Id>"): a flat dark panel, the title in gold Display over a thin rule,
--     the race's checkpoints (or laps), par and full reward, then the top 5 from RaceService's
--     "RaceBoard_<Id>" attribute (names in Body, times in Display, the leader in gold).
--   * Races with others (RaceService runs them; see its header):
--       - the lobby banner (label "Lobby", Theme's Banner zone, under the route preview card when that
--         shows): "OCEAN DRIVE SPRINT  starts in 9 · press Race on the pad to join" for a citizen who
--         could race, within K.LOBBY_SHOW studs of the pad; "... · 2 racers · you're in" for a member
--         (ReplicatedStorage attributes RaceLobby_<Id> / RaceLobbyN_<Id>, player attribute RaceLobby);
--       - POS 2/4 left of the time and LAP 1/2 right of it (labels "Position" and "Lap"), each only while
--         it means something (others in the race / more than one lap); both pop when they change;
--       - laps: the race's checkpoints are laid out once per lap (raceView), so everything that follows
--         a race (rings, line, finish gate) works through every lap unchanged; the checkpoint count and
--         the minimap's numbers restart each lap;
--       - the finish card's title says the place ("2ND PLACE") in a race with others, and FINISH alone;
--       - the standings panel (frame "Standings") hangs under the finish card: RESULTS, then everyone in
--         order with their times (NPCs dimmer, "..." while still racing, DNF), you in gold with a pink
--         bar. It updates as the others finish and goes K.STAND_SECONDS after its last update.
--   * Race challenges (RaceService, remote "RaceChallenge"):
--       - CHALLENGE (button "Challenge"): while you drive your own car as a free citizen (no race,
--         lobby, mission, shift or Big Score) with another such driver within K.CHALLENGE_SHOW studs (a
--         car whose DriverUserId is its owner). It sits in the side column under the Buttons zone
--         (LawClient.SideSlot, the slot END SHIFT would use: a shift rules challenges out): on a PC a
--         wider button, right-aligned with the slot, with its key cap ([K] on a keyboard, [R3] on a
--         gamepad); on a phone the slot's tile (VS over CHALLENGE). It waits while DriveUI's FLIP or key
--         strip or InteractClient's car card is on its spot. K / R3 / a tap challenges the nearest one;
--         it then hides until an answer comes (or the challenge lapses);
--       - the challenge card (ScreenGui "RaceChallenge", over the HUD like CrewClient's invite and in
--         the same band: under the Banner zone, centred on the Stamp zone): "<name> challenges you to a
--         race!" with ACCEPT / DECLINE; it goes after the challenge's seconds or when the server says so;
--       - a challenge race is a race like any other here (its route comes in "Countdown" Def and is put
--         in racesById under its own id); its card says YOU WIN / YOU LOST with both times and the gap,
--         and the standings panel shows the two of you with REMATCH (a new challenge, the other way)
--         while the server allows it.
--   * Shifts (JobService): the pick-up / drop-off marker (the same ring and beam); the shift's line
--     (frame "Job", Theme's Banner zone): a flat strip with a thin gold edge, a gold TAXI / COURIER tag
--     and what to do ("PICK UP MARIA"; a phone shows those words alone, in gold), the seconds left for
--     the tip or the fast bonus in green, and the distance in Display at the right. It steps aside for
--     a HUDController stamp that reaches into the zone (phones) and for a race. END SHIFT is a Theme
--     tile in the side column under the HUD's Buttons zone (LawClient.SideSlot). FARE PAID / DELIVERED
--     are green HUDController stamps.
-- Needs GPSClient (required here; it builds itself on first use, so it may start after us) and
-- LawClient (SideSlot / PlaceSlots: it starts before us in ClientMain's ORDER and never requires us).
-- Constants are fields of the table K and the HUD pieces fields of the table ui, not locals of their
-- own: the top level of a script is one Luau function, and a function holds at most 200 locals (this
-- file had passed that). Put new constants in K and new HUD pieces in ui.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Activities = require(ReplicatedStorage.Shared.Config.Activities)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))
local GPSClient = require(script.Parent:WaitForChild("GPSClient"))
local LawClient = require(script.Parent:WaitForChild("LawClient")) -- (starts before us; never requires us: no cycle)

local player = Players.LocalPlayer

local ActivityClient = {}

local C = Theme.Color
local K = {} -- every constant of this file (see the note at the top)
-- World markers only (rings, beams, the chevron sign, the finish gate): out on a sunlit road they need
-- to be brighter than the HUD's colours. Everything on the HUD takes its colours from Theme (C).
K.GOLD = Color3.fromRGB(255, 214, 10)
K.CYAN = Color3.fromRGB(34, 225, 255)
K.WHITE = Color3.new(1, 1, 1)
K.BLACK = Color3.fromRGB(16, 16, 20)

-- Race line
K.LINE, K.PREVIEW = "Race", "RacePreview" -- GPSClient path names
-- Studs of each leg used to round a corner of the line. The rounded line passes at most half of this
-- from the corner itself, so it always stays well inside a checkpoint's radius (32).
K.CORNER_ROAD, K.CORNER_WATER = 22, 36
K.CORNER_COS = math.cos(math.rad(25)) -- corners gentler than this are left alone
K.WATER_LINE_Y = -1 -- the sea's surface is at -1.5
-- The line on water: cyan chevrons are lost on the turquoise sea (Terrain.WaterColor 18, 150, 170),
-- white reads on it (and matches the finish ring). The minimap draws the line in the same colour.
K.WATER_LINE_COLOR = K.WHITE
K.OFF_ROAD, K.OFF_WATER = 70, 160 -- studs off the line before it is re-planned from the car
K.OFF_SECONDS = 0.6
K.REPLAN_EVERY = 1.5
-- A checkpoint is missed once the car is this many studs past it (along the line, plus how far off the
-- line it is) beyond the ring's own radius, for this long. The time is for the server's "Checkpoint"
-- to arrive after a good pass at full speed: only then is the car really past it uncounted.
K.MISS_PAST, K.MISS_SECONDS = 20, 0.6
K.TURN_LOOK_MIN, K.TURN_LOOK_MAX = 120, 260 -- how far ahead a bend is called (grows with speed)
K.TURN_LOOK_SECONDS = 1.8
K.TURN_DEGREES = 35
K.TURN_HOLD = 0.8 -- seconds the cue stays after the bend was last seen ahead
K.WRONG_SPEED = 15
K.WRONG_AFTER = 2
-- Route preview: only for someone who has stopped ON a start pad (30 x 30, so 22 reaches its corners).
-- Pads sit on the road: anyone rolling across one, or turning at a crossing beside it, is just driving.
K.PREVIEW_IN, K.PREVIEW_OUT = 22, 60 -- studs from a start pad's centre: route preview on / off
K.PREVIEW_SPEED = 8 -- studs/s: stopped (or standing on it on foot)
K.CARD_W, K.CARD_H = 300, 42 -- the route preview card (it hangs from the top of Theme's Banner zone: ui.cardY)
-- The card's drawing of the whole track: its box at the card's left, the most bars it may be made of,
-- and how far the line must turn off the bar being drawn before a new bar starts.
K.SHAPE_X, K.SHAPE_W, K.SHAPE_H = 8, 56, 34
K.SHAPE_BARS = 40
K.SHAPE_BEND = math.cos(math.rad(8))
K.CARD_TEXT_X = 72 -- the title and the facts start right of the drawing
-- What the card must never sit on: DriveUI's EXIT and FLIP (paths under PlayerGui, measured where
-- DriveUI has them now), and the Theme zones a centred card can reach on a small phone.
K.CARD_CLEAR = { { "DriveUI", "Exit" }, { "DriveUI", "Flip" } }
K.CARD_ZONES = { "Minimap", "Buttons" }

-- Checkpoint markers
K.ROAD_Y, K.WATER_Y = 0.1, -1.5 -- the road surface and the sea: where a ring stands
-- A ring is see-through tube walls stacked into a soft fade upward, the way a console race marks its
-- checkpoints (Alpha = transparency at full strength). Hollow, so it never fills the crossing.
K.CORONA = {
	{ Y = 0, H = 6, Alpha = 0.45 },
	{ Y = 6, H = 5, Alpha = 0.66 },
	{ Y = 11, H = 5, Alpha = 0.84 },
}
K.CORONA_H = 16
K.CORONA_WALL = 1.2 -- studs thick
K.UPRIGHT = CFrame.Angles(math.rad(90), 0, 0) -- a handle cylinder runs along its Z: stand it up
K.NEXT_STRENGTH = 0.35 -- the checkpoint after the next one is this much as visible
K.BEAM_W, K.BEAM_H = 3, 160 -- a thin light over the ring, seen from a few blocks away
K.BEAM_ALPHA, K.BEAM_NEXT_ALPHA = 0.72, 0.9
K.BURST_GROW = 1.35 -- a passed ring swells to this size while it fades
K.BURST = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- The chevron sign over the next ring stands upright (a road sign facing the driver), centred this high:
-- even pointing up, its lowest tip clears a car's roof.
K.ARROW_Y = 20
K.CHEV_ARM = Vector3.new(3.2, 2, 14) -- one arm of a chevron: width, thickness (toward the driver), length
K.CHEV_TURN = math.rad(45) -- each arm's lean off the way it points
K.CHEV_STEP = 9 -- studs between chevrons
K.CHEV_X = K.CHEV_ARM.Z / 2 * math.sin(K.CHEV_TURN)
-- Each arm relative to a CFrame looking the way the sign points (the two meet at the tip, ahead).
K.ARM_LEFT = CFrame.new(-K.CHEV_X, 0, 0) * CFrame.Angles(0, -K.CHEV_TURN, 0)
K.ARM_RIGHT = CFrame.new(K.CHEV_X, 0.02, 0) * CFrame.Angles(0, K.CHEV_TURN, 0) -- 0.02 off: no flicker at the tip
-- One chevron under a 25 degree bend, three past 100 (a hairpin), two in between.
K.GENTLE_COS, K.SHARP_COS = math.cos(math.rad(25)), math.cos(math.rad(100))
K.ARROW_ALPHA, K.ARROW_DIM = 0.05, 0.5
K.GATE_COLS, K.GATE_TILE = 12, 5 -- the finish banner: 12 x 2 tiles of 5 studs
K.GATE_CLEAR = 14 -- its underside (cars and boats pass under)

-- HUD motion
K.POP = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
K.FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
K.GO_SHOW = 0.7 -- seconds "GO" stays before it fades

-- The countdown and the finish card: cinematic, like HUDController's stamps (they fill the same Stamp
-- zone: 164 px tall on a PC, 120 on a phone). Their lines, in pixels from the zone's top: where each
-- one starts and its text size. Rule = how wide the thin rule draws out; Col = one column of the
-- finish card's three (time, best, reward).
K.BIG = {
	Desktop = { KickerY = 8, Kicker = 15, NumY = 24, Num = 88, RuleY = 122, Rule = 120 },
	Touch = { KickerY = 4, Kicker = 13, NumY = 18, Num = 62, RuleY = 88, Rule = 90 },
}
K.FINISH = {
	Desktop = { KickerY = 6, Kicker = 15, TitleY = 24, Title = 44, RuleY = 76, Rule = 260, CapY = 86, Cap = 13,
		ValueY = 102, Value = 30, Col = 170 },
	Touch = { KickerY = 2, Kicker = 13, TitleY = 17, Title = 30, RuleY = 52, Rule = 180, CapY = 58, Cap = 13,
		ValueY = 74, Value = 24, Col = 130 },
}
K.BAND_ALPHA = 0.5 -- the soft dark band behind them
K.BIG_IN = TweenInfo.new(0.15) -- the countdown fades in...
K.POP_BIG = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- ...and each number settles (from 1.25 x)
K.RULE_OUT = TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out) -- a rule drawing out from the middle
K.FINISH_IN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
K.FINISH_OUT = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
K.FINISH_SECONDS = 4.5 -- the finish card stays this long before it fades
K.FINISH_WAIT = 3 -- the longest it waits for a HUDController stamp to clear first
K.STEP_DOWN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- it moves under a stamp that comes up

-- The shift's line (Theme's Banner zone): room at its right for the distance ("12.3 km" in Display) and,
-- left of that, for the tip's seconds ("BONUS 12s"; a phone shows the seconds alone).
K.JOB_DIST_W, K.JOB_DIST_W_TOUCH = 78, 66
K.JOB_BONUS_W, K.JOB_BONUS_W_TOUCH = 82, 36
-- The BEST TIMES boards over the start pads (pixels: a BillboardGui)
K.BOARD_W, K.BOARD_H = 190, 134

-- Drift
K.DRIFT_Y = 150 -- PC: pixels from the top, under Theme's Goal and Banner zones (they end at y 104)
K.DRIFT_Y_TOUCH = 104 -- phone: under the Banner zone (54-90), well above the car
-- The row's width, and the least it shrinks to. The score line and the stamp scale their text to fit;
-- the how-to row can't, so the row is also never narrower than that needs (ui.howNeed, worked out in
-- refreshDriftKeys from the words and the caps showing: about 300 on a phone, 280 with a keyboard).
K.DRIFT_W, K.DRIFT_MIN_W = 300, 240
K.TEACH_H, K.SCORE_H, K.STAMP_H = 68, 40, 34 -- the how-to panel, the score line, the stamp
K.TITLE_H = 40 -- the how-to panel while it is its title alone (DriveUI's key strip has the how-to)
K.HOW_TEXT, K.HOW_GAP, K.HOW_PAD = 15, 6, 8 -- the how-to row: text size, pixels between its pieces, room at each end
K.DRIFT_GAP = 8 -- pixels kept free beside the side columns
K.DRIFT_LOWEST = 0.5 -- pushed down by other panels, the row's bottom never passes this share of the height
K.TOAST_REACH = 0.4 -- a toast stack is taken to reach this share of the screen height from its end
-- Top-centre pieces the row stays under (paths under PlayerGui, the way SoundClient's TITLE.CLEAR lists
-- them). A piece that is missing or hidden is skipped.
K.DRIFT_CLEAR = { { "Tutorial", "Next" }, { "Objective", "Banner" }, { "Objective", "Escape" },
	{ "Mission", "Banner" }, { "GPS", "Route" }, { "BigScore", "Goal" }, { "BigScore", "Status" } }
-- Side columns the row fits between where they share its rows: Theme zones it never overlaps, zones of
-- right-aligned text it keeps clear of while it still fits (its least width: placeDrift), and buttons
-- measured live.
K.DRIFT_SIDE_ZONES = { "Minimap", "Toasts", "Buttons" }
K.DRIFT_SIDE_SOFT = { "Status", "Pills" }
K.DRIFT_SIDE_LIVE = { { "DriveUI", "Exit" }, { "DriveUI", "Flip" } }
K.TEACH_SECONDS = 6
K.TEACH_DELAY = 0.4 -- seconds on the pad before the banner shows (DriveUI's key strip gets there first)
K.REVISIT_AFTER = 10 -- seconds off the pad before driving back on counts as a new visit
K.DRIFT_NEAR = 160 -- studs from the pad's edge: the "what is this" toast
K.STAMP_SECONDS = 2.2 -- the drift stamp stays this long, then fades
K.STAMP_WAIT = 5.5 -- the longest it waits for a HUDController stamp to clear (about two of them)
K.HEX_DIM, K.HEX_GOLD, K.HEX_CASH = C.Dim:ToHex(), C.Gold:ToHex(), C.Cash:ToHex()

-- Races with others and race challenges (see the header)
K.RULES = Activities.RaceRules or {}
K.DUEL = Activities.Challenge or {}
K.LOBBY_SHOW = K.RULES.LobbyShow or 150 -- studs from a pad: citizens this close see its lobby banner
K.LOBBY_W, K.LOBBY_H = 440, 26 -- the lobby banner (never wider than the Banner zone)
K.TIMER_W, K.TIMER_W_TOUCH = 140, 110 -- the race time; POS and LAP stand either side of it
K.SIDE_W = 100 -- the POS and LAP boxes
K.ORDINAL = { "1ST", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH", "8TH" }
K.STAND_W, K.STAND_W_TOUCH = 300, 250 -- the standings panel
K.ROW_H, K.ROW_H_TOUCH = 19, 16 -- one racer's row in it
K.STAND_HEAD = 26 -- its title row
K.STAND_ROWS = 8 -- the most rows it shows
K.STAND_SECONDS = 10 -- it goes this long after its last update
-- Pixels from the finish card's top to just under its values (K.FINISH: ValueY + Value + 4, and a margin):
-- the standings hang there.
K.CARD_DOWN, K.CARD_DOWN_TOUCH = 142, 104
K.REMATCH_H = 36 -- PC (a phone's is Theme.Touch tall)
K.CHALLENGE_SHOW = K.DUEL.ShowReach or 60 -- studs: another free driver this close shows CHALLENGE
K.CHALLENGE_EXPIRE = K.DUEL.Expire or 15
K.CHALLENGE_W = 150 -- PC: the CHALLENGE button's width (a phone uses the side column's tile)
K.CHALLENGE_KEY, K.CHALLENGE_PAD = Enum.KeyCode.K, Enum.KeyCode.ButtonR3
K.CHALLENGE_CLEAR = { { "DriveUI", "Flip" }, { "DriveUI", "ControlsHint" }, { "Interact", "CarCard" } }
K.INVITE_W, K.INVITE_W_TOUCH, K.INVITE_MIN_TOUCH = 320, 380, 330 -- the challenge card (CrewClient's sizes)
K.ACCEPT_W, K.DECLINE_W = 72, 84 -- its buttons on a phone
-- Why a race was called off ("Cancelled" Reason).
K.WHY = {
	LeftCar = "Race cancelled: you left your car.",
	Wanted = "Race off: the cops are after you!",
	TooSlow = "Race cancelled: out of time.",
	CarLost = "Race cancelled: your car is gone.",
	Died = "Race over: you went down.",
	Arrested = "Race over: you got arrested.",
	Opponent = "Race off: your rival dropped out.",
	DuelTimeUp = "Race over: you didn't reach the finish in time.",
	Ended = "Race over.",
	Invalid = "Race cancelled.",
}

local racesById = {}
for _, r in ipairs(Activities.Races) do
	racesById[r.Id] = r
end

-- The HUD pieces (see the note at the top). build() sets them once; Init adds END SHIFT:
--   gui, timerLabel, cpLabel
--   big (the frame "Countdown"), bigKicker, bigLabel (the number), bigRule, bigScale
--   bigSet: everything of the countdown that fades (fadeSet); bigFading; bigRuleW (the rule's full width)
--   finish (the frame "Finish"), finishKicker, finishTitle, finishRule, finishRuleW
--   finishHead: the fade set of its band, name, title and rule
--   finishStats: [1..3] = { set, cap, value }: the time, best and reward columns
--   finishToken: bumps with every card shown or sent away (a stale one stops)
--   cpScale, cueScale, wrongScale: UIScales for the pops
--   turnCue, cueWord, wrongLabel
--   previewCard, previewTitle, previewLine; cardY: the card's top on this screen (placeHud)
--   shapes: [race id] = { frame, final }, the track drawings on the preview card (trackShape)
--   driftTeach, driftHowRow, driftScoreLabel, driftStampLabel
--   howWords, howNeed: pixels the how-to row's words take, and the whole row with its caps and margins
--   teachScale, scoreScale, stampScale, stampShadow
--   job (the frame "Job": the shift's line), jobTitle, jobDist, jobBonus
--   jobTouch, jobDistW, jobBonusW: the layout the line was last placed for (placeHud)
--   endShiftButton
--   posLabel, lapLabel (beside the time), posScale, lapScale; sideSize: their text size now (placeHud)
--   lobby (the lobby banner)
--   standings (the frame "Standings"), standTitle, standRows (the rows' holder), rematch (REMATCH)
--   challenge (CHALLENGE), challengeRow (PC: key cap + word), challengeKey (the cap), challengeTile (phone)
--   inviteGui (ScreenGui "RaceChallenge": the challenge card's)
local ui = { cardY = 64, finishToken = 0, bigFading = false }
local ring, beam -- the next checkpoint (also the shift marker); ring = { part, bands }
local ring2, beam2 -- the checkpoint after it, fainter
local burst -- { part, tube, tween }: the ring that swells and fades where a checkpoint was passed
local hollow = true -- CylinderHandleAdornment.InnerRadius works here (else the walls are solid cylinders)
-- The chevron sign: count (0 = hidden), lit (the chevron lit now, 0 = all), pos, dir = where it
-- points, face = the way the driver arrives (its flat side faces them), arms[i] = { left, right } parts.
local arrow = { on = false, count = 0, lit = 0, pos = Vector3.zero, dir = Vector3.yAxis, face = Vector3.zAxis, arms = {} }
local gate -- the chequered finish (Model, parented only while it shows)
local cueSets = {} -- Left / Right = { frame, bars = { { upper, lower } x 3, tail first } }
local driftKeys = {} -- the two key caps in the how-to row
local current -- { race, index, startAt, laps, pos, of, run, duel } + what the guide keeps on it (see guideTick)
-- Races with others and challenges: views = races with their laps laid out (raceView); lastRun = the run
-- (RaceService's Run) we last finished, whose standings may show; standUntil = os.clock() when the
-- standings go; standBase = their height without REMATCH; pending = os.clock() until which our own
-- challenge waits for an answer (CHALLENGE hides); rival = who CHALLENGE would challenge now; invite =
-- the challenge card while it shows; rematch = { userId, untilAt } while REMATCH may be pressed;
-- duelIds = the challenge routes put in racesById (only the latest is kept); hinted = CHALLENGE was explained.
local RS = { views = {}, standUntil = 0, standBase = 0, pending = 0, duelIds = {}, hinted = false }

local function now()
	return Workspace:GetServerTimeNow()
end

local function fmt(t)
	t = math.max(0, t)
	return string.format("%d:%04.1f", t // 60, t % 60)
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function rootPart()
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end

-- Run a repeating step without letting one error stop the loop; say so once.
local warned = {}
local function safely(name, fn)
	local ok, err = pcall(fn)
	if not ok and not warned[name] then
		warned[name] = true
		warn("[ActivityClient] " .. name .. ": " .. tostring(err))
	end
end

-- A HUD piece drops in: it starts a little bigger and settles (its UIScale).
local function pop(scale, from, info)
	scale.Scale = from or 1.2
	TweenService:Create(scale, info or K.POP, { Scale = 1 }):Play()
end

local function scaler(obj)
	local s = Instance.new("UIScale")
	s.Parent = obj
	return s
end

-- Things that fade together (the countdown, the parts of the finish card).
-- set = { tweens = {}, { instance, property, its shown value }, ... }; gone is always 1.
-- info = nil: at once. A new fade takes over from one still running.
local function fadeSet(set, shown, info)
	for _, t in ipairs(set.tweens) do
		t:Cancel()
	end
	table.clear(set.tweens)
	for _, row in ipairs(set) do
		local goal = shown and row[3] or 1
		if info then
			local t = TweenService:Create(row[1], info, { [row[2]] = goal })
			table.insert(set.tweens, t)
			t:Play()
		else
			row[1][row[2]] = goal
		end
	end
end

-- Put a label (with its soft shadow) or a plain frame into a fade set, as it looks now.
local function fades(set, obj)
	if obj:IsA("TextLabel") then
		table.insert(set, { obj, "TextTransparency", 0 })
		local shadow = obj:FindFirstChild("Shadow")
		if shadow then
			table.insert(set, { shadow, "Transparency", shadow.Transparency })
		end
	else
		table.insert(set, { obj, "BackgroundTransparency", obj.BackgroundTransparency })
	end
	return obj
end

-- Race routes ----------------------------------------------------------------------------------------

-- Round every sharp corner of a polyline: the corner point becomes three points cutting it (a small
-- curve). Returns the new list and, for each old index, where that point ended up.
local function roundCorners(points, radius)
	local out, map = {}, {}
	for i, v in ipairs(points) do
		local a, b = points[i - 1], points[i + 1]
		if a and b then
			local inLen, outLen = (v - a).Magnitude, (b - v).Magnitude
			if inLen > 0.5 and outLen > 0.5 then
				local d1, d2 = (v - a) / inLen, (b - v) / outLen
				if d1:Dot(d2) < K.CORNER_COS then
					local r = math.min(radius, inLen * 0.45, outLen * 0.45)
					local p1, p2 = v - d1 * r, v + d2 * r
					table.insert(out, p1)
					table.insert(out, p1 * 0.25 + v * 0.5 + p2 * 0.25)
					map[i] = #out
					table.insert(out, p2)
					continue
				end
			end
		end
		table.insert(out, v)
		map[i] = #out
	end
	return out, map
end

-- The point `dist` studs along the polyline from points[i], forward (step 1) or back (step -1).
local function along(points, i, dist, step)
	local p = points[i]
	local j = i + step
	while points[j] do
		local d = (points[j] - p).Magnitude
		if d >= dist and d > 0 then
			return p + (points[j] - p) * (dist / d)
		end
		dist -= d
		p = points[j]
		j += step
	end
	return p
end

-- Studs along the polyline from points[a] to points[b].
local function span(points, a, b)
	local len = 0
	for k = a, b - 1 do
		len += (points[k + 1] - points[k]).Magnitude
	end
	return len
end

-- Road routes run along the centre line. A race laid out in its own lanes (race.LineOffset = studs
-- right of the centre line) gets its line moved that far to the right of the way it runs, so following
-- the chevrons keeps the car in those lanes (Highway 1 Loop: clear of the stunt ramps parked in the
-- oncoming lanes, and off the divider). Point for point, so indexes into the list stay valid.
local function keepRight(points, offset)
	if not offset or offset == 0 then
		return points
	end
	local out = {}
	for i, p in ipairs(points) do
		local d = (points[i + 1] or p) - (points[i - 1] or p)
		-- (-dz, 0, dx) is the right-hand side of travel along d: facing +X, +Z is on the right.
		out[i] = d.Magnitude > 0.01 and (p + Vector3.new(-d.Z, 0, d.X).Unit * offset) or p
	end
	return out
end

-- The whole route of a race as one polyline: { points, cp = index of each checkpoint in points,
-- onRoads }. Road races follow the road graph leg by leg; boat races (and road races before the graph
-- has arrived) go straight from checkpoint to checkpoint. Kept once it is final.
local routes = {}
local function routeFor(race)
	local route = routes[race.Id]
	if route then
		return route
	end
	local onRoads = race.Boat ~= true and GPSClient.GraphReady()
	local raw, cpRaw = {}, {}
	local prev = flat(race.Start)
	for k, cp in ipairs(race.Checkpoints) do
		local to = flat(cp)
		local leg = onRoads and GPSClient.RoadRoute(prev, to) or nil
		if not leg then
			leg = { prev, to }
		end
		for _, p in ipairs(leg) do
			local last = raw[#raw]
			if not last or (p - last).Magnitude > 3 then -- a leg starts where the last one ended
				table.insert(raw, p)
			end
		end
		cpRaw[k] = #raw -- the leg's last point stands for the checkpoint
		prev = to
	end
	if #raw < 2 then
		return nil
	end
	if onRoads then
		-- (only the road line: the straight fallback already runs checkpoint to checkpoint, in the lanes)
		raw = keepRight(raw, race.LineOffset)
	end
	local points, map = roundCorners(raw, race.Boat and K.CORNER_WATER or K.CORNER_ROAD)
	local cps = {}
	for k, i in ipairs(cpRaw) do
		cps[k] = map[i]
	end
	route = { points = points, cp = cps, onRoads = onRoads }
	if onRoads or race.Boat then
		routes[race.Id] = route
	end
	return route
end

-- GPSClient options for a line: faint for the preview; on water a fixed height and its own colour.
-- The race line also names its next checkpoint (index) for the minimap: its number, or a chequered
-- flag for the finish.
local function lineOpts(race, faint, index)
	local opts = { Faint = faint }
	if race.Boat then
		opts.Height, opts.Color = K.WATER_LINE_Y, K.WATER_LINE_COLOR
	end
	local goal = index and race.Checkpoints[index]
	if goal then
		opts.Goal = goal
		local per = race.PerLap or #race.Checkpoints -- (the numbers start again each lap)
		opts.GoalText = index == #race.Checkpoints and "🏁" or tostring((index - 1) % per + 1)
	end
	return opts
end

-- Which way the route arrives at checkpoint k, and which way it leaves (nil at the finish).
local function legDirs(race, route, k)
	local cps = race.Checkpoints
	local here = flat(cps[k])
	local dirIn, dirOut
	if route and route.cp[k] then
		local i = route.cp[k]
		local p = route.points[i]
		local before = p - along(route.points, i, 70, -1)
		local after = along(route.points, i, 70, 1) - p
		dirIn = before.Magnitude > 1 and before.Unit or nil
		dirOut = after.Magnitude > 1 and after.Unit or nil
	end
	if not dirIn then
		local d = here - flat(cps[k - 1] or race.Start)
		dirIn = d.Magnitude > 1 and d.Unit or Vector3.zAxis
	end
	if not dirOut and cps[k + 1] then
		local d = flat(cps[k + 1]) - here
		dirOut = d.Magnitude > 1 and d.Unit or dirIn
	end
	return dirIn, dirOut
end

-- The line for where the race is now: from the last checkpoint passed (or the start), through the
-- next one, on to the one after it. current.cpAlong = how far along that line the next checkpoint
-- sits (guideTick compares it with GPSClient.PathProgress to tell a checkpoint that was driven past).
local function showLine()
	local race = current.race
	local route = routeFor(race)
	if not route then
		return
	end
	local i, n = current.index, #race.Checkpoints
	local from = i > 1 and route.cp[i - 1] or 1
	local to = route.cp[math.min(i + 1, n)]
	current.cpAlong = span(route.points, from, route.cp[i])
	current.pastSince = nil
	GPSClient.SetPath(K.LINE, table.move(route.points, from, to, 1, {}), lineOpts(race, false, i))
end

-- Off the line (a missed turn, a shortcut) or past a checkpoint that didn't count: plan again from the
-- car to the next checkpoint, then on along the planned route to the one after it.
local function replan(pos)
	local race = current.race
	local i, n = current.index, #race.Checkpoints
	local cp = flat(race.Checkpoints[i])
	local points = race.Boat ~= true and GPSClient.RoadRoute(pos, cp) or nil
	if points then
		points = keepRight(points, race.LineOffset)
	else
		points = { pos, cp } -- water, or no road graph yet
	end
	local cpAt = #points -- the checkpoint is the last point so far
	local route = routeFor(race)
	-- A checkpoint that was driven past gets the way back to it and nothing more: the way on from it
	-- runs right where the car is now, so the two would lie over each other pointing opposite ways,
	-- and the car would count as "on the line" while it carries on the wrong way.
	if route and i < n and current.missed ~= i then
		for j = route.cp[i] + 1, route.cp[i + 1] do
			local p = route.points[j]
			if (p - points[#points]).Magnitude > 3 then
				table.insert(points, p)
			end
		end
	end
	if #points < 2 then
		return
	end
	local rounded, map = roundCorners(points, race.Boat and K.CORNER_WATER or K.CORNER_ROAD)
	current.cpAlong = span(rounded, 1, map[cpAt])
	current.pastSince = nil
	GPSClient.SetPath(K.LINE, rounded, lineOpts(race, false, i))
end

-- World markers ----------------------------------------------------------------------------------------

local function worldPart(name, size, color)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 1
	return p
end

-- One see-through tube wall standing on `anchor`, from y up to y + h.
local function tube(anchor, y, h)
	local t = Instance.new("CylinderHandleAdornment")
	t.Name = "Band"
	t.Adornee = anchor
	t.Height = h
	t.CFrame = CFrame.new(0, y + h / 2, 0) * K.UPRIGHT
	t.Radius = 32
	if hollow then
		-- (checked once: without it the walls would be solid cylinders, still readable)
		hollow = pcall(function()
			t.InnerRadius = 32 - K.CORONA_WALL
		end)
	end
	t.Color3 = K.GOLD
	t.Transparency = 1
	t.Parent = anchor
	return t
end

local function setRadius(t, r)
	t.Radius = r
	if hollow then
		t.InnerRadius = r - K.CORONA_WALL
	end
end

-- A checkpoint ring: an invisible anchor part (it keeps the old part name) carrying the K.CORONA bands.
local function buildRing(name, camera)
	local anchor = worldPart(name, Vector3.new(1, 1, 1), K.GOLD)
	local bands = {}
	for i, band in ipairs(K.CORONA) do
		bands[i] = tube(anchor, band.Y, band.H)
	end
	anchor.Parent = camera
	return { part = anchor, bands = bands }
end

local function buildGate()
	local model = Instance.new("Model")
	model.Name = "FinishGate"
	local function piece(name, size, cf, color, material)
		local p = worldPart(name, size, color)
		p.Material = material
		p.Transparency = 0
		p.CFrame = cf
		p.Parent = model
		return p
	end
	-- The gate is built around the origin, facing -Z, and moved as one with PivotTo.
	local base = piece("Root", Vector3.new(1, 1, 1), CFrame.new(), K.WHITE, Enum.Material.SmoothPlastic)
	base.Transparency = 1
	model.PrimaryPart = base
	local half = K.GATE_COLS * K.GATE_TILE / 2
	local top = K.GATE_CLEAR + 2 * K.GATE_TILE
	for _, x in ipairs({ -half - 1, half + 1 }) do
		piece("Post", Vector3.new(2, top, 2), CFrame.new(x, top / 2, 0), K.BLACK, Enum.Material.SmoothPlastic)
	end
	for col = 1, K.GATE_COLS do
		for row = 1, 2 do
			local white = (col + row) % 2 == 0
			piece("Tile", Vector3.new(K.GATE_TILE, K.GATE_TILE, 1),
				CFrame.new(-half + (col - 0.5) * K.GATE_TILE, K.GATE_CLEAR + (row - 0.5) * K.GATE_TILE, 0),
				white and K.WHITE or K.BLACK, white and Enum.Material.Neon or Enum.Material.SmoothPlastic)
		end
	end
	return model
end

local function buildWorld()
	local camera = Workspace.CurrentCamera
	local function pillar(name, width)
		local p = worldPart(name, Vector3.new(width, K.BEAM_H, width), K.GOLD)
		p.Parent = camera
		return p
	end
	ring, beam = buildRing("CheckpointRing", camera), pillar("CheckpointBeam", K.BEAM_W)
	ring2, beam2 = buildRing("CheckpointRingNext", camera), pillar("CheckpointBeamNext", K.BEAM_W - 1)
	burst = { part = worldPart("CheckpointBurst", Vector3.new(1, 1, 1), K.GOLD) }
	burst.tube = tube(burst.part, 0, K.CORONA_H)
	burst.part.Parent = camera
	for i = 1, 3 do
		local pair = { worldPart("CheckpointArrow", K.CHEV_ARM, K.CYAN), worldPart("CheckpointArrow", K.CHEV_ARM, K.CYAN) }
		pair[1].Parent, pair[2].Parent = camera, camera
		arrow.arms[i] = pair
	end
	gate = buildGate()
end

-- Place the sign's chevrons `offset` studs along its direction from its spot (one chevron slides that
-- way, over and over). The parts' thin axis (their Y) points along `face`, so the sign's flat side faces
-- the driver coming in: a sign lying flat over the road is seen edge-on from the chase camera.
local function placeArrow(offset)
	local n = arrow.count
	for i = 1, n do
		-- Chevron 1 is the tail, chevron n the front; together they sit centred on the spot.
		local at = arrow.pos + arrow.dir * (offset + (i - (n + 1) / 2) * K.CHEV_STEP)
		local base = CFrame.lookAt(at, at + arrow.dir, arrow.face)
		local pair = arrow.arms[i]
		pair[1].CFrame = base * K.ARM_LEFT
		pair[2].CFrame = base * K.ARM_RIGHT
	end
end

-- lit = the chevron shown brightest (0 = all of them); chevrons past the count are hidden.
local function lightArrow(lit)
	arrow.lit = lit
	for i, pair in ipairs(arrow.arms) do
		local alpha = i > arrow.count and 1 or ((lit == 0 or i == lit) and K.ARROW_ALPHA or K.ARROW_DIM)
		pair[1].Transparency, pair[2].Transparency = alpha, alpha
	end
end

-- dirIn: the way the route arrives at the checkpoint; dirOut: the way it leaves (both flat). The sign
-- shows the turn as the arriving driver sees it: right or left for a real turn, up for straight on,
-- leaning in between for a gentle bend; more chevrons the sharper it is. setArrow(nil) hides it.
local function setArrow(pos, dirIn, dirOut)
	local n = 0
	if pos and dirIn and dirOut then
		local c = math.clamp(dirOut:Dot(dirIn), -1, 1)
		n = c < K.SHARP_COS and 3 or (c < K.GENTLE_COS and 2 or 1)
		local side = dirOut - dirIn * c -- the sideways part of the way out
		local point = side + Vector3.yAxis * math.max(c, 0)
		-- Both parts are square to dirIn, so `face` (dirIn) is never along `dir` and lookAt is well defined.
		arrow.pos, arrow.face = pos, dirIn
		arrow.dir = point.Magnitude > 0.2 and point.Unit or Vector3.yAxis
	end
	arrow.on, arrow.count = n > 0, n
	lightArrow(0)
	if n > 0 then
		placeArrow(0)
	end
end

local function placeRing(r, pillar, cp, size, color, strength, beamAlpha, y)
	r.part.CFrame = CFrame.new(cp.X, y, cp.Z)
	for i, t in ipairs(r.bands) do
		setRadius(t, size / 2)
		t.Color3 = color
		t.Transparency = 1 - (1 - K.CORONA[i].Alpha) * strength
	end
	pillar.CFrame = CFrame.new(cp.X, y + K.BEAM_H / 2, cp.Z)
	pillar.Color = color
	pillar.Transparency = beamAlpha
end

local function hideRing(r, pillar)
	for _, t in ipairs(r.bands) do
		t.Transparency = 1
	end
	pillar.Transparency = 1
end

-- The ring of a checkpoint just passed swells outward and fades (one at a time: a newer one restarts it).
local function burstAt(cp, size, color, y)
	local r = size / 2
	local t = burst.tube
	if burst.tween then
		burst.tween:Cancel()
	end
	burst.part.CFrame = CFrame.new(cp.X, y, cp.Z)
	setRadius(t, r)
	t.Color3 = color
	t.Transparency = 0.15
	local goal = { Radius = r * K.BURST_GROW, Transparency = 1 }
	if hollow then
		goal.InnerRadius = r * K.BURST_GROW - K.CORONA_WALL
	end
	burst.tween = TweenService:Create(t, K.BURST, goal)
	burst.tween:Play()
end

-- A race's rings: as wide as what the server counts, standing on the road or on the water.
local function ringSize(race)
	return (race.Radius or Activities.CheckRadius or 32) * 2
end

local function ringBase(race)
	return race.Boat and K.WATER_Y or K.ROAD_Y
end

-- HUD ------------------------------------------------------------------------------------------------

local function text(name, pos, size, px, kind, color)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = pos
	l.Size = size
	l.Text = ""
	Theme.Text(l, px, kind)
	if color then
		l.TextColor3 = color
	end
	l.Visible = false
	l.Parent = ui.gui
	return l
end

-- Text that shrinks to fit when the row narrows on a small phone (never above maxSize).
local function fitText(label, maxSize)
	label.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 11
	limit.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)
	pad.Parent = label
end

-- Three chevrons made of two slanted bars each (no font or image needed), and the word under them.
local function buildCue()
	ui.turnCue = Instance.new("Frame")
	ui.turnCue.Name = "TurnCue"
	ui.turnCue.AnchorPoint = Vector2.new(0.5, 0)
	ui.turnCue.Position = UDim2.new(0.5, 0, 0, 112)
	ui.turnCue.Size = UDim2.fromOffset(160, 62)
	ui.turnCue.BackgroundTransparency = 1
	ui.turnCue.Visible = false
	ui.turnCue.Parent = ui.gui
	ui.cueScale = scaler(ui.turnCue)
	for _, side in ipairs({ "Left", "Right" }) do
		local dir = side == "Right" and 1 or -1
		local set = Instance.new("Frame")
		set.Name = side
		set.AnchorPoint = Vector2.new(0.5, 0)
		set.Position = UDim2.fromScale(0.5, 0)
		set.Size = UDim2.fromOffset(96, 40)
		set.BackgroundTransparency = 1
		set.Visible = false
		set.Parent = ui.turnCue
		local bars = {}
		for i = 1, 3 do
			-- Tail first: left to right for a right turn, right to left for a left turn.
			local x = (dir == 1 and (i - 1) or (3 - i)) * 32 + 16
			local pair = {}
			for _, sign in ipairs({ -1, 1 }) do -- the upper bar, then the lower one
				local bar = Instance.new("Frame")
				bar.Name = "Bar"
				bar.AnchorPoint = Vector2.new(0.5, 0.5)
				bar.Position = UDim2.fromOffset(x, 20 + sign * 8)
				bar.Size = UDim2.fromOffset(28, 8)
				bar.Rotation = -sign * dir * 35 -- ">" is "\" over "/"; "<" is "/" over "\"
				bar.BackgroundColor3 = C.BrandAlt
				bar.BorderSizePixel = 0
				Theme.Corners(bar, 2)
				local edge = Instance.new("UIStroke")
				edge.Color = C.Shadow
				edge.Thickness = 1.5
				edge.Transparency = 0.5
				edge.Parent = bar
				bar.Parent = set
				table.insert(pair, bar)
			end
			bars[i] = pair
		end
		cueSets[side] = { frame = set, bars = bars }
	end
	ui.cueWord = Instance.new("TextLabel")
	ui.cueWord.Name = "Word"
	ui.cueWord.Position = UDim2.fromOffset(0, 42)
	ui.cueWord.Size = UDim2.new(1, 0, 0, 20)
	ui.cueWord.Text = ""
	Theme.Text(ui.cueWord, 18, "Display")
	ui.cueWord.Parent = ui.turnCue

	ui.wrongLabel = text("WrongWay", UDim2.new(0.5, 0, 0, 116), UDim2.fromOffset(200, 40), 24, "Display")
	ui.wrongLabel.Text = "WRONG WAY"
	ui.wrongLabel.BackgroundColor3 = C.Danger
	ui.wrongLabel.BackgroundTransparency = 0.15
	ui.wrongLabel.BorderSizePixel = 0
	Theme.Corners(ui.wrongLabel)
	ui.wrongScale = scaler(ui.wrongLabel)
end

local cueShown -- "Left" | "Right" | nil
local function setCue(side)
	if side ~= cueShown then
		cueShown = side
		ui.turnCue.Visible = side ~= nil
		for name, set in pairs(cueSets) do
			set.frame.Visible = name == side
		end
		if side then
			ui.cueWord.Text = side == "Left" and "LEFT" or "RIGHT"
			pop(ui.cueScale, 1.25)
		end
	end
	if side then
		-- The chevrons light up one after another, toward the turn.
		local lit = math.floor(os.clock() * 6) % 3 + 1
		for i, pair in ipairs(cueSets[side].bars) do
			local alpha = i == lit and 0 or 0.5
			pair[1].BackgroundTransparency = alpha
			pair[2].BackgroundTransparency = alpha
		end
	end
end

local function setWrong(on)
	if ui.wrongLabel.Visible ~= on then
		ui.wrongLabel.Visible = on
		if on then
			pop(ui.wrongScale, 1.25)
		end
	end
	if on then
		ui.wrongLabel.BackgroundTransparency = 0.15 + 0.3 * (math.floor(os.clock() * 4) % 2) -- a slow blink
	end
end

-- Pieces of the countdown and the finish card ------------------------------------------------------

-- The soft dark band behind the words (it fades out at both ends), `share` of the piece wide.
local function softBand(parent, share)
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.5)
	band.Size = UDim2.fromScale(share, 1)
	band.BackgroundColor3 = C.Shadow
	band.BackgroundTransparency = K.BAND_ALPHA
	band.BorderSizePixel = 0
	band.Active = false
	local ends = Instance.new("UIGradient")
	ends.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0),
		NumberSequenceKeypoint.new(0.7, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	ends.Parent = band
	band.Parent = parent
	return band
end

-- One centred line: Theme text that shrinks to fit its box (setLine gives it a place and a size).
local function stampLine(parent, name, kind, color)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Text = ""
	Theme.Text(l, nil, kind)
	l.TextScaled = true
	l.TextColor3 = color
	l.ZIndex = 2
	l.Active = false
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 13
	limit.MaxTextSize = 13
	limit.Parent = l
	l.Parent = parent
	return l
end

-- Place one of those lines: its middle `dx` pixels off the piece's middle, `y` from its top, `w` wide
-- (0 = the whole piece), `h` tall, its text at most `size` px.
local function setLine(l, dx, y, w, h, size)
	l.Position = UDim2.new(0.5, dx, 0, y)
	l.Size = w > 0 and UDim2.fromOffset(w, h) or UDim2.new(1, -16, 0, h)
	l:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = size
end

-- A thin rule: it draws out from the middle when the piece comes up.
local function thinRule(parent, color)
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Size = UDim2.fromOffset(0, 2)
	rule.BackgroundColor3 = color
	rule.BorderSizePixel = 0
	rule.ZIndex = 2
	rule.Active = false
	rule.Parent = parent
	return rule
end

-- The countdown (see the header): the race's name, the number, the rule, on a band.
local function buildCountdown()
	ui.big = Instance.new("Frame")
	ui.big.Name = "Countdown"
	ui.big.BackgroundTransparency = 1
	ui.big.Active = false
	ui.big.Visible = false
	ui.big.Parent = ui.gui
	ui.bigSet = { tweens = {} }
	fades(ui.bigSet, softBand(ui.big, 0.6))
	ui.bigKicker = fades(ui.bigSet, stampLine(ui.big, "Race", "Bold", C.Gold))
	ui.bigLabel = stampLine(ui.big, "Number", "Display", C.Text)
	ui.bigLabel.AnchorPoint = Vector2.new(0.5, 0.5) -- centred on its spot, so it settles in place as it shrinks
	Theme.Shadow(ui.bigLabel, 3)
	fades(ui.bigSet, ui.bigLabel)
	ui.bigScale = scaler(ui.bigLabel)
	ui.bigRule = fades(ui.bigSet, thinRule(ui.big, C.Gold))
end

-- Each new number settles from a little bigger while the rule under it draws out; GO is green.
local function setBig(word)
	if ui.bigLabel.Text ~= word or not ui.big.Visible then
		local go = word == "GO"
		ui.bigLabel.Text = word
		ui.bigLabel.TextColor3 = go and C.Cash or C.Text
		ui.bigRule.BackgroundColor3 = go and C.Cash or C.Gold
		ui.bigFading = false
		if ui.big.Visible then
			fadeSet(ui.bigSet, true) -- (the next number: all of it stays up)
		else
			fadeSet(ui.bigSet, false)
			ui.big.Visible = true
			fadeSet(ui.bigSet, true, K.BIG_IN)
		end
		pop(ui.bigScale, 1.25, K.POP_BIG)
		ui.bigRule.Size = UDim2.fromOffset(0, 2)
		TweenService:Create(ui.bigRule, K.RULE_OUT, { Size = UDim2.fromOffset(ui.bigRuleW or 100, 2) }):Play()
	end
end

local function fadeBig()
	if ui.big.Visible and not ui.bigFading then
		ui.bigFading = true
		fadeSet(ui.bigSet, false, K.FADE)
	end
end

-- The finish card (see the header): the race's name, FINISH, the rule, then three columns, each a small
-- word over a big value. showFinish fills it in.
local function buildFinish()
	ui.finish = Instance.new("Frame")
	ui.finish.Name = "Finish"
	ui.finish.AnchorPoint = Vector2.new(0.5, 0) -- (hung from its top: it can step down under a stamp)
	ui.finish.BackgroundTransparency = 1
	ui.finish.Active = false
	ui.finish.Visible = false
	ui.finish.Parent = ui.gui
	ui.finishHead = { tweens = {} }
	fades(ui.finishHead, softBand(ui.finish, 1.2))
	ui.finishKicker = fades(ui.finishHead, stampLine(ui.finish, "Race", "Bold", C.Gold))
	ui.finishTitle = stampLine(ui.finish, "Title", "Display", C.Text)
	ui.finishTitle.Text = "FINISH"
	Theme.Shadow(ui.finishTitle, 2)
	fades(ui.finishHead, ui.finishTitle)
	ui.finishRule = fades(ui.finishHead, thinRule(ui.finish, C.Gold))
	ui.finishStats = {}
	for i, name in ipairs({ "Time", "Best", "Reward" }) do
		local set = { tweens = {} }
		ui.finishStats[i] = {
			set = set,
			cap = fades(set, stampLine(ui.finish, name .. "Word", "Bold", C.Dim)),
			value = fades(set, stampLine(ui.finish, name, "Display", C.Text)),
		}
	end
end

-- The shift's line (see the header): [| TAXI  PICK UP MARIA ........ TIP 12s   240 m]. updateJobUI
-- writes it, placeHud places it.
local function buildJob()
	ui.job = Instance.new("Frame")
	ui.job.Name = "Job"
	Theme.Panel(ui.job)
	ui.job.Active = false
	ui.job.Visible = false
	ui.job.Parent = ui.gui
	local edge = Instance.new("Frame") -- a thin gold line down the left edge: paid work
	edge.Name = "Edge"
	edge.Position = UDim2.fromOffset(6, 7)
	edge.Size = UDim2.new(0, 3, 1, -14)
	edge.BackgroundColor3 = C.Gold
	edge.BorderSizePixel = 0
	Theme.Corners(edge, 1)
	edge.Parent = ui.job
	ui.jobTitle = Instance.new("TextLabel")
	ui.jobTitle.Name = "Title"
	ui.jobTitle.Position = UDim2.fromOffset(16, 0)
	ui.jobTitle.Size = UDim2.new(1, -110, 1, 0)
	ui.jobTitle.Text = ""
	ui.jobTitle.RichText = true
	ui.jobTitle.TextXAlignment = Enum.TextXAlignment.Left
	ui.jobTitle.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.Text(ui.jobTitle, 14, "Bold")
	ui.jobTitle.Parent = ui.job
	ui.jobDist = Instance.new("TextLabel")
	ui.jobDist.Name = "Distance"
	ui.jobDist.AnchorPoint = Vector2.new(1, 0)
	ui.jobDist.Text = ""
	ui.jobDist.TextXAlignment = Enum.TextXAlignment.Right
	Theme.Text(ui.jobDist, 22, "Display")
	ui.jobDist.Parent = ui.job
	ui.jobBonus = Instance.new("TextLabel")
	ui.jobBonus.Name = "Bonus"
	ui.jobBonus.AnchorPoint = Vector2.new(1, 0)
	ui.jobBonus.Text = ""
	ui.jobBonus.TextXAlignment = Enum.TextXAlignment.Right
	Theme.Text(ui.jobBonus, 13, "Bold")
	ui.jobBonus.TextColor3 = C.Cash -- green: it is worth cash
	ui.jobBonus.Visible = false
	ui.jobBonus.Parent = ui.job
end

local function buildPreviewCard()
	ui.previewCard = Instance.new("Frame")
	ui.previewCard.Name = "RacePreview"
	ui.previewCard.AnchorPoint = Vector2.new(0.5, 0)
	ui.previewCard.Position = UDim2.new(0.5, 0, 0, ui.cardY)
	ui.previewCard.Size = UDim2.fromOffset(K.CARD_W, K.CARD_H)
	Theme.Panel(ui.previewCard)
	ui.previewCard.Visible = false
	ui.previewCard.Parent = ui.gui
	ui.shapes = {} -- [race id] = { frame, final }: the track drawings (trackShape), at the card's left
	-- The title and the facts stand right of the drawing, left-aligned beside it.
	ui.previewTitle = Instance.new("TextLabel")
	ui.previewTitle.Name = "Title"
	ui.previewTitle.Position = UDim2.fromOffset(K.CARD_TEXT_X, 3)
	ui.previewTitle.Size = UDim2.new(1, -K.CARD_TEXT_X - 8, 0, 20)
	ui.previewTitle.Text = ""
	Theme.Text(ui.previewTitle, 17, "Display")
	ui.previewTitle.TextXAlignment = Enum.TextXAlignment.Left
	ui.previewTitle.Parent = ui.previewCard
	ui.previewLine = Instance.new("TextLabel")
	ui.previewLine.Name = "Line"
	ui.previewLine.Position = UDim2.fromOffset(K.CARD_TEXT_X, 22)
	ui.previewLine.Size = UDim2.new(1, -K.CARD_TEXT_X - 8, 0, 17) -- (tall enough for 12 px text once it scales)
	ui.previewLine.Text = ""
	Theme.Text(ui.previewLine, 12, "Body")
	ui.previewLine.TextColor3 = C.Dim
	ui.previewLine.TextXAlignment = Enum.TextXAlignment.Left
	-- (the longest line, "beat 1:50 · $1,200 + $1,000 bonus", is about 210 px of the 220 here; a bigger
	-- reward shrinks the text a little instead of running out of the card)
	ui.previewLine.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 12
	limit.MinTextSize = 9
	limit.Parent = ui.previewLine
	ui.previewLine.Parent = ui.previewCard
end

-- The two key caps in "Steer + [SPACE] then hold [W] + steer", from the last input used: the handbrake
-- swings the tail out, then the throttle holds the slide (CarPhysics; DriveUI's key strip says the same).
-- The phone's DRIFT and GAS buttons show on the same test DriveUI uses for its pedals.
local function driftKeyWords()
	if string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad" then
		return "X", "RT"
	elseif UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		return "DRIFT", "GAS"
	end
	return "SPACE", "W"
end

local function refreshDriftKeys()
	local kick, hold = driftKeyWords()
	if driftKeys[1] and driftKeys[1].Text == kick then
		return
	end
	for _, cap in ipairs(driftKeys) do
		cap:Destroy()
	end
	driftKeys[1] = Theme.Key(ui.driftHowRow, kick)
	driftKeys[1].LayoutOrder = 2
	driftKeys[2] = Theme.Key(ui.driftHowRow, hold)
	driftKeys[2].LayoutOrder = 4
	-- How wide the row is with these caps, room at each end included: three words, two caps, four
	-- gaps. placeDrift never makes the panel narrower than this (the row would hang out of it).
	ui.howNeed = math.ceil(ui.howWords + driftKeys[1].Size.X.Offset + driftKeys[2].Size.X.Offset
		+ 4 * K.HOW_GAP + 2 * K.HOW_PAD)
end

local function buildDrift()
	ui.driftTeach = Instance.new("Frame")
	ui.driftTeach.Name = "DriftTeach"
	ui.driftTeach.AnchorPoint = Vector2.new(0.5, 0)
	ui.driftTeach.Position = UDim2.new(0.5, 0, 0, K.DRIFT_Y)
	ui.driftTeach.Size = UDim2.fromOffset(K.DRIFT_W, K.TEACH_H)
	Theme.Panel(ui.driftTeach)
	ui.driftTeach.Visible = false
	ui.driftTeach.Parent = ui.gui
	ui.teachScale = scaler(ui.driftTeach)
	local accent = Instance.new("Frame") -- a thin line in the zone's own purple
	accent.Name = "Accent"
	accent.AnchorPoint = Vector2.new(0.5, 0)
	accent.Position = UDim2.new(0.5, 0, 0, 34)
	accent.Size = UDim2.fromOffset(60, 2)
	accent.BackgroundColor3 = C.Purple
	accent.BorderSizePixel = 0
	accent.Parent = ui.driftTeach
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(0, 5)
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Text = "DRIFT ZONE"
	Theme.Text(title, 24, "Display")
	title.Parent = ui.driftTeach
	ui.driftHowRow = Instance.new("Frame")
	ui.driftHowRow.Name = "How"
	ui.driftHowRow.Position = UDim2.fromOffset(0, 40)
	ui.driftHowRow.Size = UDim2.new(1, 0, 0, 22)
	ui.driftHowRow.BackgroundTransparency = 1
	ui.driftHowRow.Parent = ui.driftTeach
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, K.HOW_GAP)
	list.Parent = ui.driftHowRow
	-- The words' widths are measured as they are made (GothamMedium is the face of Theme.Font.Body):
	-- the row can't scale its text the way the score line does, so placeDrift has to know how wide it
	-- is (ui.howNeed) instead of guessing.
	local TextService = game:GetService("TextService")
	ui.howWords = 0
	for order, word in pairs({ [1] = "Steer +", [3] = "then hold", [5] = "+ steer" }) do
		local l = Instance.new("TextLabel")
		l.Name = "Word"
		l.LayoutOrder = order
		l.Size = UDim2.fromOffset(0, 22)
		l.AutomaticSize = Enum.AutomaticSize.X
		l.Text = word
		Theme.Text(l, K.HOW_TEXT, "Body")
		l.Parent = ui.driftHowRow
		local ok, size = pcall(TextService.GetTextSize, TextService, word, K.HOW_TEXT, Enum.Font.GothamMedium, Vector2.new(1000, 22))
		ui.howWords += ok and size.X or #word * 8 -- (8 px a letter is on the wide side)
	end
	refreshDriftKeys()

	-- The score line and the stamp take the same row as the how-to (placeDrift moves all three).
	ui.driftScoreLabel = text("DriftScore", UDim2.new(0.5, 0, 0, K.DRIFT_Y), UDim2.fromOffset(K.DRIFT_W, K.SCORE_H), 24, "Display")
	ui.driftScoreLabel.RichText = true
	Theme.Panel(ui.driftScoreLabel)
	fitText(ui.driftScoreLabel, 24)
	ui.scoreScale = scaler(ui.driftScoreLabel)
	ui.driftStampLabel = text("DriftStamp", UDim2.new(0.5, 0, 0, K.DRIFT_Y), UDim2.fromOffset(K.DRIFT_W, K.STAMP_H), 20, "Display")
	ui.driftStampLabel.RichText = true
	Theme.Panel(ui.driftStampLabel)
	fitText(ui.driftStampLabel, 20)
	ui.stampScale = scaler(ui.driftStampLabel)
	ui.stampShadow = Theme.Shadow(ui.driftStampLabel) -- (Theme.Text made it: this hands it back)
end

-- The standings panel (see the header): RESULTS, one row per racer (showStandings fills them), REMATCH.
local function buildStandings()
	local panel = Instance.new("Frame")
	panel.Name = "Standings"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Size = UDim2.fromOffset(K.STAND_W, K.STAND_HEAD)
	Theme.Panel(panel, 0.3)
	panel.Active = true -- (REMATCH lives on it: taps on the panel don't reach the world)
	panel.Visible = false
	panel.Parent = ui.gui
	ui.standings = panel
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(12, 4)
	title.Size = UDim2.new(1, -24, 0, 18)
	title.Text = "RESULTS"
	Theme.Text(title, 15, "Display")
	title.TextColor3 = C.Gold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel
	ui.standTitle = title
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(0, K.STAND_HEAD)
	rows.Size = UDim2.new(1, 0, 0, 0)
	rows.Parent = panel
	ui.standRows = rows
	local rematch = Instance.new("TextButton")
	rematch.Name = "Rematch"
	rematch.AnchorPoint = Vector2.new(0.5, 1)
	rematch.Position = UDim2.new(0.5, 0, 1, -8)
	rematch.Size = UDim2.new(1, -24, 0, K.REMATCH_H)
	Theme.Button(rematch, "Primary")
	rematch.TextSize = 15
	rematch.Text = "REMATCH"
	rematch.Visible = false
	rematch.Parent = panel
	ui.rematch = rematch
end

-- CHALLENGE (see the header): a PC button (key cap + word, the cap added by refreshChallengeKey) and a
-- phone tile (VS over CHALLENGE); challengeTick shows the one for this device.
local function buildChallenge()
	local b = Instance.new("TextButton")
	b.Name = "Challenge"
	b.Text = ""
	Theme.Button(b, "Quiet")
	b.Size = UDim2.fromOffset(K.CHALLENGE_W, 44)
	b.Visible = false
	b.Parent = ui.gui
	ui.challenge = b
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	row.Parent = b
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = row
	local word = Instance.new("TextLabel")
	word.Name = "Word"
	word.LayoutOrder = 2
	word.Size = UDim2.fromOffset(0, 22)
	word.AutomaticSize = Enum.AutomaticSize.X
	word.Text = "CHALLENGE"
	Theme.Text(word, 17, "Display")
	word.Parent = row
	ui.challengeRow = row
	local tile = Instance.new("Frame")
	tile.Name = "Tile"
	tile.BackgroundTransparency = 1
	tile.Size = UDim2.fromScale(1, 1)
	tile.Visible = false
	tile.Parent = b
	local vs = Instance.new("TextLabel")
	vs.Name = "VS"
	vs.Position = UDim2.fromOffset(0, 3)
	vs.Size = UDim2.new(1, 0, 0, 20)
	vs.Text = "VS"
	Theme.Text(vs, 18, "Display")
	vs.TextColor3 = C.Gold
	vs.Parent = tile
	local small = Instance.new("TextLabel")
	small.Name = "Word"
	small.Position = UDim2.new(0, 2, 1, -18)
	small.Size = UDim2.new(1, -4, 0, 14)
	small.Text = "CHALLENGE"
	Theme.Text(small, nil, "Display")
	small.TextScaled = true -- (Oswald is narrow: about 10 px fits a 52 px tile)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 11
	limit.MinTextSize = 7
	limit.Parent = small
	small.Parent = tile
	ui.challengeTile = tile
end

local function build()
	ui.gui = Instance.new("ScreenGui")
	ui.gui.Name = "ActivityUI"
	ui.gui.ResetOnSpawn = false
	ui.gui.IgnoreGuiInset = true
	ui.gui.Parent = player:WaitForChild("PlayerGui")
	-- Theme's Banner zone, top centre: the time, and the checkpoint count under it. The cue hangs under
	-- the zone. (placeHud puts them all in their places for this screen.)
	ui.timerLabel = text("Timer", UDim2.new(0.5, 0, 0, 64), UDim2.fromOffset(K.TIMER_W, 26), 26, "Display")
	ui.cpLabel = text("Checkpoint", UDim2.new(0.5, 0, 0, 90), UDim2.fromOffset(260, 14), 13, "Bold", C.Gold)
	ui.cpScale = scaler(ui.cpLabel)
	-- Either side of the time: the place and the lap (refreshRaceHud writes them, placeHud places them).
	ui.posLabel = text("Position", UDim2.new(0.5, -(K.TIMER_W / 2 + 6), 0, 64), UDim2.fromOffset(K.SIDE_W, 26), 22, "Display")
	ui.posLabel.AnchorPoint = Vector2.new(1, 0)
	ui.posLabel.TextXAlignment = Enum.TextXAlignment.Right
	ui.posLabel.RichText = true
	ui.posScale = scaler(ui.posLabel)
	ui.lapLabel = text("Lap", UDim2.new(0.5, K.TIMER_W / 2 + 6, 0, 64), UDim2.fromOffset(K.SIDE_W, 26), 22, "Display")
	ui.lapLabel.AnchorPoint = Vector2.new(0, 0)
	ui.lapLabel.TextXAlignment = Enum.TextXAlignment.Left
	ui.lapLabel.RichText = true
	ui.lapScale = scaler(ui.lapLabel)
	-- The lobby banner: a flat strip in the Banner zone (lobbyTick writes and places it).
	ui.lobby = text("Lobby", UDim2.new(0.5, 0, 0, 64), UDim2.fromOffset(K.LOBBY_W, K.LOBBY_H), 14, "Bold")
	ui.lobby.RichText = true
	Theme.Panel(ui.lobby)
	fitText(ui.lobby, 14)
	buildStandings()
	buildChallenge()
	buildCountdown()
	buildFinish()
	buildCue()
	buildPreviewCard()
	buildDrift()
	buildJob()
	buildWorld()
end

-- Screen layout helpers ---------------------------------------------------------------------------------

-- A piece of another ScreenGui (path under PlayerGui) while it shows: x, y, w, h in our own gui's
-- pixels (both ignore the top inset; measured from our corner anyway, like NotifyController does).
local function liveBox(playerGui, path, origin)
	local sg = playerGui and playerGui:FindFirstChild(path[1])
	local obj = sg and sg:FindFirstChild(path[2])
	if obj and obj:IsA("GuiObject") and obj.Visible and sg:IsA("ScreenGui") and sg.Enabled then
		local p, s = obj.AbsolutePosition, obj.AbsoluteSize
		return p.X - origin.X, p.Y - origin.Y, s.X, s.Y
	end
	return nil
end

-- A Theme zone's box on a W x H screen (IgnoreGuiInset pixels). A toast stack has no height of its
-- own: it is taken to reach K.TOAST_REACH of the screen from its fixed end.
local function zoneBox(name, touch, W, H)
	local z = Theme.Zone(name, touch)
	local w = z.Size.X.Scale * W + z.Size.X.Offset
	local h = z.Size.Y.Scale * H + z.Size.Y.Offset
	local x = z.Pos.X.Scale * W + z.Pos.X.Offset - z.Anchor.X * w
	local y = z.Pos.Y.Scale * H + z.Pos.Y.Offset - z.Anchor.Y * h
	if z.Grow == "Down" then
		h = H * K.TOAST_REACH
	elseif z.Grow == "Up" then
		h = H * K.TOAST_REACH
		y -= h
	end
	return x, y, w, h
end

-- Narrow the free band [left, right] by a side piece that shares the rows top .. top + rows.
local function narrow(left, right, top, rows, mid, x, y, w, h)
	if x and w > 0 and h > 0 and y < top + rows and y + h > top then
		if x + w / 2 < mid then
			left = math.max(left, x + w + K.DRIFT_GAP)
		else
			right = math.min(right, x - K.DRIFT_GAP)
		end
	end
	return left, right
end

-- Does the card's spot stay clear of DriveUI's EXIT and FLIP (measured where they are now) and of the
-- minimap and the Buttons zone? On a small phone it may not: the card stays hidden there, and the faint
-- line and the minimap still show the start of the route.
local function cardFits()
	local playerGui = player:FindFirstChild("PlayerGui")
	local origin = ui.gui.AbsolutePosition
	local size = ui.gui.AbsoluteSize
	local left = size.X / 2 - K.CARD_W / 2
	local top = ui.cardY
	local function hits(x, y, w, h) -- (x is nil for a piece that isn't showing)
		return x ~= nil and x < left + K.CARD_W + 8 and x + w > left - 8 and y < top + K.CARD_H + 8 and y + h > top - 8
	end
	for _, path in ipairs(K.CARD_CLEAR) do
		if hits(liveBox(playerGui, path, origin)) then
			return false
		end
	end
	local touch = Theme.IsTouch()
	for _, name in ipairs(K.CARD_ZONES) do
		if hits(zoneBox(name, touch, size.X, size.Y)) then
			return false
		end
	end
	return true
end

-- HUDController's big moment stamp while one shows: its top and bottom in pixels from the top of the
-- screen (its gui ignores the top inset like ours), else nil. The band fills Theme's Stamp zone.
local function stampBand()
	local top, bottom
	if HUDController.StampTop then
		top, bottom = HUDController.StampTop()
	end
	if type(top) ~= "number" then
		return nil
	end
	if type(bottom) ~= "number" then
		local z = Theme.Zone("Stamp", Theme.IsTouch())
		bottom = top + z.Size.Y.Scale * ui.gui.AbsoluteSize.Y + z.Size.Y.Offset
	end
	return top, bottom
end

-- Every race and shift piece into its Theme zone, sized for this screen and device (the drift row has
-- its own placeDrift; END SHIFT is placed by updateJobUI).
local function placeHud()
	local touch = Theme.IsTouch()
	local size = ui.gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		local camera = Workspace.CurrentCamera -- (not laid out yet: the camera knows the screen)
		size = camera and camera.ViewportSize or Vector2.new(844, 390)
	end
	-- The Banner zone: the time over the checkpoint count. The cue and WRONG WAY hang under the zone;
	-- the route card and the shift's line take the zone itself.
	local _, top, bannerW, h = zoneBox("Banner", touch, size.X, size.Y)
	top, h = math.floor(top), math.floor(h)
	local timeH = h - 14
	local timeW = touch and K.TIMER_W_TOUCH or K.TIMER_W
	ui.timerLabel.Position = UDim2.new(0.5, 0, 0, top)
	ui.timerLabel.Size = UDim2.fromOffset(timeW, timeH)
	ui.timerLabel.TextSize = math.min(timeH, 28)
	-- POS on the left of the time, LAP on its right, a little smaller.
	ui.sideSize = math.min(timeH, touch and 18 or 22)
	for _, l in ipairs({ ui.posLabel, ui.lapLabel }) do
		l.Size = UDim2.fromOffset(K.SIDE_W, timeH)
		l.TextSize = ui.sideSize
	end
	ui.posLabel.Position = UDim2.new(0.5, -(timeW / 2 + 6), 0, top)
	ui.lapLabel.Position = UDim2.new(0.5, timeW / 2 + 6, 0, top)
	ui.lobby.Size = UDim2.fromOffset(math.min(K.LOBBY_W, math.max(200, math.floor(bannerW))), K.LOBBY_H)
	ui.cpLabel.Position = UDim2.new(0.5, 0, 0, top + timeH)
	ui.turnCue.Position = UDim2.new(0.5, 0, 0, top + h + 8)
	ui.wrongLabel.Position = UDim2.new(0.5, 0, 0, top + h + 12)
	ui.cardY = top
	ui.previewCard.Position = UDim2.new(0.5, 0, 0, top)
	Theme.Place(ui.job, "Banner", touch)
	ui.jobTouch = touch
	ui.jobDistW = touch and K.JOB_DIST_W_TOUCH or K.JOB_DIST_W
	ui.jobBonusW = touch and K.JOB_BONUS_W_TOUCH or K.JOB_BONUS_W
	ui.jobTitle.TextSize = touch and 13 or 14
	ui.jobDist.TextSize = touch and 20 or 22
	ui.jobDist.Position = UDim2.new(1, -10, 0, 0)
	ui.jobDist.Size = UDim2.new(0, ui.jobDistW, 1, 0)
	ui.jobBonus.Position = UDim2.new(1, -(10 + ui.jobDistW + 6), 0, 0)
	ui.jobBonus.Size = UDim2.new(0, ui.jobBonusW, 1, 0)

	-- The Stamp zone: the countdown fills it; the finish card hangs from its top edge.
	local big = touch and K.BIG.Touch or K.BIG.Desktop
	Theme.Place(ui.big, "Stamp", touch)
	setLine(ui.bigKicker, 0, big.KickerY, 0, big.Kicker + 2, big.Kicker)
	setLine(ui.bigLabel, 0, big.NumY + (big.Num + 4) / 2, 0, big.Num + 4, big.Num) -- (anchored at its middle)
	ui.bigRule.Position = UDim2.new(0.5, 0, 0, big.RuleY)
	ui.bigRuleW = big.Rule
	local _, stampY = zoneBox("Stamp", touch, size.X, size.Y)
	ui.finish.Position = UDim2.new(0.5, 0, 0, math.floor(stampY))
	ui.finish.Size = Theme.Zone("Stamp", touch).Size
	local fin = touch and K.FINISH.Touch or K.FINISH.Desktop
	setLine(ui.finishKicker, 0, fin.KickerY, 0, fin.Kicker + 2, fin.Kicker)
	setLine(ui.finishTitle, 0, fin.TitleY, 0, fin.Title + 4, fin.Title)
	ui.finishRule.Position = UDim2.new(0.5, 0, 0, fin.RuleY)
	ui.finishRuleW = fin.Rule
	for i, stat in ipairs(ui.finishStats) do
		local dx = (i - 2) * fin.Col
		setLine(stat.cap, dx, fin.CapY, fin.Col - 10, fin.Cap + 2, fin.Cap)
		setLine(stat.value, dx, fin.ValueY, fin.Col - 10, fin.Value + 4, fin.Value)
	end
end

-- Shifts and checkpoints share the ring and beam ---------------------------------------------------------

local job -- { stage, pos, name }

local function showJobMarker()
	if not job or not job.pos then
		hideRing(ring, beam)
		return
	end
	-- 64 across: the 32 studs JobService counts for a pick-up and a drop-off (STOP_RADIUS / DROP_RADIUS).
	-- Keep the two the same: a car stopped inside the ring that does not count has no way to know why.
	placeRing(ring, beam, job.pos, 64, job.stage == "pickup" and K.CYAN or K.GOLD, 1, K.BEAM_ALPHA, K.ROAD_Y)
end

local function showCheckpoint()
	setArrow(nil)
	hideRing(ring2, beam2)
	gate.Parent = nil
	if not current then
		ui.cpLabel.Visible = false
		showJobMarker()
		return
	end
	local race = current.race
	local n = #race.Checkpoints
	local cp = race.Checkpoints[current.index]
	if not cp then
		return
	end
	local size, y = ringSize(race), ringBase(race)
	local last = current.index == n
	local dirIn, dirOut = legDirs(race, routeFor(race), current.index)
	placeRing(ring, beam, cp, size, last and K.WHITE or K.GOLD, 1, K.BEAM_ALPHA, y)
	if last then
		-- The finish: a chequered gate across the way in.
		local base = Vector3.new(cp.X, y, cp.Z)
		gate:PivotTo(CFrame.lookAt(base, base + dirIn))
		gate.Parent = Workspace.CurrentCamera
	else
		-- Which way after this one, and the one after it (fainter).
		setArrow(Vector3.new(cp.X, y + K.ARROW_Y, cp.Z), dirIn, dirOut)
		local nextCp = race.Checkpoints[current.index + 1]
		placeRing(ring2, beam2, nextCp, size, current.index + 1 == n and K.WHITE or K.GOLD, K.NEXT_STRENGTH, K.BEAM_NEXT_ALPHA, y)
	end
	local per = race.PerLap or n -- (counted per lap; the LAP label says which)
	local label = last and "FINISH LINE" or string.format("CHECKPOINT %d / %d", (current.index - 1) % per + 1, per)
	if ui.cpLabel.Text ~= label or not ui.cpLabel.Visible then
		ui.cpLabel.Text = label
		ui.cpLabel.Visible = true
		pop(ui.cpScale, 1.3)
	end
end

-- Races ----------------------------------------------------------------------------------------------

local previewRace, previewOnRoads -- the race whose route is previewed (stopped on its start pad)
local offSince, wrongSince -- os.clock() since we left the line / drove against it
local lastPlan = 0
local cueSide, cueUntil = nil, 0

local function hidePreview()
	if previewRace then
		previewRace = nil
		ui.previewCard.Visible = false
		GPSClient.ClearPath(K.PREVIEW)
	end
end

-- The whole track as a little drawing for the preview card: the faint line on the road and the minimap
-- only reach the first few blocks, so this is what shows where the race goes. North is up (as on the
-- minimap when you face north); thin bars, one per straight stretch; a white dot at the start and a
-- gold one at the finish. Built once per race and kept (again if the first one was drawn from straight
-- lines, before the road graph arrived).
local function trackShape(race, route)
	local final = route.onRoads or race.Boat == true
	local known = ui.shapes[race.Id]
	if known and (known.final or not final) then
		return known.frame
	end
	if known then
		known.frame:Destroy()
	end
	local pts = route.points
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(pts) do
		minX, maxX = math.min(minX, p.X), math.max(maxX, p.X)
		minZ, maxZ = math.min(minZ, p.Z), math.max(maxZ, p.Z)
	end
	-- One scale for both ways (the shape keeps its proportions), centred, 3 px clear of the box's edge
	-- for the dots. A race that is one straight run counts as 1 stud wide here: a single bar.
	local scale = math.min((K.SHAPE_W - 6) / math.max(maxX - minX, 1), (K.SHAPE_H - 6) / math.max(maxZ - minZ, 1))
	local ox = (K.SHAPE_W - (maxX - minX) * scale) / 2
	local oy = (K.SHAPE_H - (maxZ - minZ) * scale) / 2
	local function px(p)
		return Vector2.new(ox + (p.X - minX) * scale, oy + (p.Z - minZ) * scale)
	end
	-- Keep only the points where the line really turns (a road is many short stretches in a row) and
	-- that are at least `step` pixels from the last one kept; a coarser step while that is too many bars.
	local line
	local step = 2
	repeat
		line = { px(pts[1]) }
		for i = 2, #pts - 1 do
			local q = px(pts[i])
			local a, b = q - line[#line], px(pts[i + 1]) - q
			if a.Magnitude >= step and b.Magnitude > 0.01 and a.Unit:Dot(b.Unit) < K.SHAPE_BEND then
				table.insert(line, q)
			end
		end
		table.insert(line, px(pts[#pts]))
		step *= 2
	until #line - 1 <= K.SHAPE_BARS or step > 16

	local frame = Instance.new("Frame")
	frame.Name = "Shape_" .. race.Id
	frame.Position = UDim2.fromOffset(K.SHAPE_X, (K.CARD_H - K.SHAPE_H) // 2)
	frame.Size = UDim2.fromOffset(K.SHAPE_W, K.SHAPE_H)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	-- (positions as shares of the box: a UDim's pixel part is a whole number, a share is not)
	local function at(obj, p)
		obj.AnchorPoint = Vector2.new(0.5, 0.5)
		obj.Position = UDim2.fromScale(p.X / K.SHAPE_W, p.Y / K.SHAPE_H)
		obj.BorderSizePixel = 0
		obj.Parent = frame
	end
	for i = 1, math.min(#line - 1, K.SHAPE_BARS) do
		local d = line[i + 1] - line[i]
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.Size = UDim2.fromOffset(math.ceil(d.Magnitude) + 2, 2) -- 1 px past each end: the joints close
		bar.Rotation = math.deg(math.atan2(d.Y, d.X))
		bar.BackgroundColor3 = C.BrandAlt
		at(bar, (line[i] + line[i + 1]) / 2)
	end
	for _, spot in ipairs({ { line[#line], 4, C.Gold }, { line[1], 6, C.Text } }) do -- the start goes on top
		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.Size = UDim2.fromOffset(spot[2], spot[2])
		dot.BackgroundColor3 = spot[3]
		dot.ZIndex = 2
		Theme.Corners(dot, spot[2])
		at(dot, spot[1])
	end
	frame.Parent = ui.previewCard
	ui.shapes[race.Id] = { frame = frame, final = final }
	return frame
end

local function showPreview(race)
	local route = routeFor(race)
	if not route or not GPSClient.SetPath(K.PREVIEW, route.points, lineOpts(race, true)) then
		return
	end
	previewRace, previewOnRoads = race, route.onRoads or race.Boat == true
	local shape
	safely("track drawing", function() -- (the card still shows its words if the drawing ever fails)
		shape = trackShape(race, route)
	end)
	for _, known in pairs(ui.shapes) do
		known.frame.Visible = known.frame == shape
	end
	ui.previewTitle.Text = string.upper(race.Name)
	local laps = race.Laps or 1
	ui.previewLine.Text = string.format("%sbeat %s  ·  %s + %s bonus", laps > 1 and (laps .. " laps  ·  ") or "",
		clock(race.Par), HUDController.Money(race.Reward), HUDController.Money(race.ParBonus))
	ui.previewCard.Visible = cardFits()
end

-- Could this player start a race right now? RaceService refuses everyone else (side, heat, a mission
-- or a taxi / courier shift), so they get no preview: a cop's, a wanted player's or a mission's own GPS
-- route is never covered by one, and a shift's job line (y 60) never sits under the card.
local function canRace()
	return player:GetAttribute("Side") == "Civilian" and (player:GetAttribute("Heat") or 0) <= 0
		and player:GetAttribute("Mission") == nil and player:GetAttribute("JobKind") == nil
		and player:GetAttribute("TitleScreen") ~= true -- (nothing of the HUD shows over the first-join title screen)
end

-- Stopped on a start pad: show where the race goes before it starts.
local function previewTick()
	if current then
		if previewRace then -- the race line took the preview's place
			previewRace = nil
			ui.previewCard.Visible = false
		end
		return
	end
	local root = rootPart()
	if not root then
		return
	end
	if not canRace() then
		hidePreview() -- also when they become wanted or start a shift right on the pad
		return
	end
	local pos = flat(root.Position)
	if previewRace then
		if (pos - flat(previewRace.Start)).Magnitude > K.PREVIEW_OUT then
			hidePreview()
		elseif not previewOnRoads and GPSClient.GraphReady() then
			showPreview(previewRace) -- drawn as straight lines before the road graph arrived: redo it
		else
			ui.previewCard.Visible = cardFits() -- EXIT comes and goes as they get in and out
		end
		return
	end
	-- Only stopping on the pad means "I want to race": a car rolling across it or turning at the
	-- crossing beside it (and someone following their GPS) keeps the road as it was.
	local v = root.AssemblyLinearVelocity
	if v.X * v.X + v.Z * v.Z > K.PREVIEW_SPEED * K.PREVIEW_SPEED then
		return
	end
	for _, race in ipairs(Activities.Races) do
		if (pos - flat(race.Start)).Magnitude <= K.PREVIEW_IN then
			showPreview(race)
			return
		end
	end
end

-- Ten times a second while racing: re-plan when off the line or past a checkpoint that didn't count,
-- WRONG WAY, and the turn cue. current also carries: cpAlong (showLine / replan), pastSince = os.clock()
-- since the car has been past the checkpoint uncounted, touched / missed = the checkpoint index the
-- car was seen inside of / was told it missed.
local function guideTick()
	local c = current
	if not c or now() < c.startAt then
		setCue(nil)
		setWrong(false)
		offSince, wrongSince, cueSide = nil, nil, nil
		return
	end
	local root = rootPart()
	local off, dir, _, along = GPSClient.PathProgress()
	if not root or not off or GPSClient.PathName() ~= K.LINE then
		return
	end
	local t = os.clock()
	local pos = flat(root.Position)
	local vel = flat(root.AssemblyLinearVelocity)
	local speed = vel.Magnitude
	local n = #c.race.Checkpoints
	local radius = ringSize(c.race) / 2
	-- Well inside the ring right now (the server measures from the car's middle, we from the driver:
	-- hence the 4 studs): its "Checkpoint" is on its way, however late, so this one is not missed.
	if (pos - flat(c.race.Checkpoints[c.index])).Magnitude <= radius - 4 then
		c.touched = c.index
	end
	-- Off the line: a missed turn, a shortcut.
	local lost = off > (c.race.Boat and K.OFF_WATER or K.OFF_ROAD)
	offSince = lost and (offSince or t) or nil
	-- Past the next checkpoint and the server has not counted it (a boat that went round the ring).
	-- The line leads on from there to the ring after it, which would not count either, and the car is
	-- still "on the line", so nothing above would ever notice.
	local past = c.cpAlong ~= nil and along ~= nil and c.touched ~= c.index and along >= c.cpAlong - 1
		and along - c.cpAlong + off > radius + K.MISS_PAST
	c.pastSince = past and (c.pastSince or t) or nil
	local missed = past and t - c.pastSince >= K.MISS_SECONDS
	if (missed or (lost and t - offSince >= K.OFF_SECONDS)) and t - lastPlan >= K.REPLAN_EVERY then
		lastPlan = t
		if missed and c.missed ~= c.index then
			-- Say it once, then the line (replan) and WRONG WAY do the pointing.
			c.missed = c.index
			if c.index == n then
				NotifyController.Show(NotifyController.Messages.RaceMissedFinish
					or "You missed the finish! Turn back to the white ring.", C.Orange, "warning")
			else
				NotifyController.Show(NotifyController.Messages.RaceMissed
					or "You missed a checkpoint! Turn back to the gold ring.", C.Orange, "warning")
			end
		end
		replan(pos)
		off, dir = GPSClient.PathProgress()
		if not off then
			return
		end
	end
	-- Driving against the line (a re-planned line may well start behind you: turn around).
	if speed > K.WRONG_SPEED and vel:Dot(dir) < -0.35 * speed then
		wrongSince = wrongSince or t
	else
		wrongSince = nil
	end
	local wrong = wrongSince ~= nil and t - wrongSince >= K.WRONG_AFTER
	setWrong(wrong)
	if not wrong then
		local side = GPSClient.PathTurn(math.clamp(speed * K.TURN_LOOK_SECONDS, K.TURN_LOOK_MIN, K.TURN_LOOK_MAX), K.TURN_DEGREES)
		if side then
			cueSide, cueUntil = side, t + K.TURN_HOLD
		end
	end
	setCue((not wrong and cueSide and t < cueUntil) and cueSide or nil)
end

-- POS and LAP beside the time (see the header). popPos / popLap: pop the one that just changed.
local function refreshRaceHud(popPos, popLap)
	local c = current
	local small = math.floor((ui.sideSize or 22) * 0.62)
	local showPos = c ~= nil and type(c.of) == "number" and c.of > 1 and type(c.pos) == "number"
	if showPos then
		local words = string.format('<font size="%d">POS </font>%d<font size="%d">/%d</font>', small, c.pos, small, c.of)
		if ui.posLabel.Text ~= words then
			ui.posLabel.Text = words
			if popPos and ui.posLabel.Visible then
				pop(ui.posScale, 1.3)
			end
		end
	end
	ui.posLabel.Visible = showPos
	local laps = c and c.laps or 1
	local showLap = c ~= nil and laps > 1
	if showLap then
		local per = c.race.PerLap or #c.race.Checkpoints
		local lap = math.clamp((c.index - 1) // per + 1, 1, laps)
		local words = string.format('<font size="%d">LAP </font>%d<font size="%d">/%d</font>', small, lap, small, laps)
		if ui.lapLabel.Text ~= words then
			ui.lapLabel.Text = words
			if popLap and ui.lapLabel.Visible then
				pop(ui.lapScale, 1.3)
			end
		end
	end
	ui.lapLabel.Visible = showLap
end

local function endRace()
	current = nil
	GPSClient.ClearPath(K.LINE)
	ui.timerLabel.Visible = false
	ui.big.Visible = false
	ui.bigLabel.Text = ""
	setCue(nil)
	setWrong(false)
	showCheckpoint()
	refreshRaceHud(false, false)
end

-- A race as it is driven: with more than one lap its checkpoints repeat once per lap (the server counts
-- one list through every lap too) and PerLap says how many make a lap. Kept per race and lap count.
local function raceView(race, laps)
	if laps <= 1 then
		return race
	end
	local key = race.Id .. "x" .. laps
	local view = RS.views[key]
	if not view then
		view = table.clone(race)
		view.Id = key
		view.Laps = laps
		view.PerLap = #race.Checkpoints
		view.Checkpoints = {}
		for _ = 1, laps do
			for _, cp in ipairs(race.Checkpoints) do
				table.insert(view.Checkpoints, cp)
			end
		end
		RS.views[key] = view
	end
	return view
end

-- A challenge's route ("Countdown" Def) as a race of its own, under its own id. Only the latest is kept
-- (with its drawn route). nil if it doesn't look like a route.
local function registerDuel(id, def)
	if type(id) ~= "string" or type(def) ~= "table" or type(def.Checkpoints) ~= "table" then
		return nil
	end
	if typeof(def.Start) ~= "Vector3" or typeof(def.Heading) ~= "Vector3" then
		return nil
	end
	local cps = {}
	for i, v in ipairs(def.Checkpoints) do
		if typeof(v) ~= "Vector3" or i > 100 then
			return nil
		end
		cps[i] = v
	end
	if #cps == 0 then
		return nil
	end
	for _, old in ipairs(RS.duelIds) do
		racesById[old] = nil
		routes[old] = nil
	end
	table.clear(RS.duelIds)
	local race = {
		Id = id,
		Name = type(def.Name) == "string" and def.Name or "Street Duel",
		Start = def.Start,
		Heading = def.Heading,
		Checkpoints = cps,
		Par = type(def.Par) == "number" and def.Par or 60,
		Reward = 0,
		ParBonus = 0,
		Duel = true,
	}
	racesById[id] = race
	table.insert(RS.duelIds, id)
	return race
end

-- The finish card (see the header): kicker over the title, then three columns, each
-- { cap, cap colour, value, value colour } (a street race: time, best, reward; a challenge: both times
-- and the gap).
local function showFinish(kicker, title, titleColor, cols)
	ui.finishToken += 1
	local token = ui.finishToken
	local stats = ui.finishStats
	ui.finishKicker.Text = kicker
	ui.finishTitle.Text = title
	ui.finishTitle.TextColor3 = titleColor or C.Text
	for i, stat in ipairs(stats) do
		local col = cols[i] or { "", C.Dim, "", C.Text }
		stat.cap.Text = col[1]
		stat.cap.TextColor3 = col[2] or C.Dim
		stat.value.Text = col[3]
		stat.value.TextColor3 = col[4] or C.Text
	end
	task.spawn(function()
		-- Never on top of a HUDController stamp (RANK UP can land in the same moment): wait for it a
		-- little, and if stamps keep coming, show under them.
		local waited = 0
		while stampBand() and waited < K.FINISH_WAIT do
			waited += task.wait(0.1)
		end
		if ui.finishToken ~= token then
			return
		end
		placeHud() -- (back to the top of the Stamp zone, wherever the last card ended up)
		local _, stampBottom = stampBand()
		local under = stampBottom ~= nil
		if under then
			ui.finish.Position = UDim2.new(0.5, 0, 0, stampBottom + 6)
		end
		-- In: the band, the race's name and the title first (the title rising into place, the rule
		-- drawing out), then the three columns one after another.
		fadeSet(ui.finishHead, false)
		for _, stat in ipairs(stats) do
			fadeSet(stat.set, false)
		end
		local rest = ui.finishTitle.Position
		ui.finishTitle.Position = rest + UDim2.fromOffset(0, 10)
		ui.finishRule.Size = UDim2.fromOffset(0, 2)
		ui.finish.Visible = true
		fadeSet(ui.finishHead, true, K.FINISH_IN)
		TweenService:Create(ui.finishTitle, K.RULE_OUT, { Position = rest }):Play()
		TweenService:Create(ui.finishRule, K.RULE_OUT, { Size = UDim2.fromOffset(ui.finishRuleW, 2) }):Play()
		for i, stat in ipairs(stats) do
			fadeSet(stat.set, true, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.15 + 0.15 * i))
		end
		local shownFor = 0
		while shownFor < K.FINISH_SECONDS do
			shownFor += task.wait(0.1)
			if ui.finishToken ~= token then
				return -- a new countdown (or a newer card) took over
			end
			if not under then
				-- A stamp came up over the card: step down under its band, once (never back up).
				local _, bottom = stampBand()
				if bottom then
					under = true
					TweenService:Create(ui.finish, K.STEP_DOWN, { Position = UDim2.new(0.5, 0, 0, bottom + 6) }):Play()
				end
			end
		end
		fadeSet(ui.finishHead, false, K.FINISH_OUT)
		for _, stat in ipairs(stats) do
			fadeSet(stat.set, false, K.FINISH_OUT)
		end
		task.wait(K.FINISH_OUT.Time + 0.05)
		if ui.finishToken == token then
			ui.finish.Visible = false
		end
	end)
end

-- A street race's finish card. d = RaceService's "Finished": Time, Par, Reward (the par bonus included
-- when it was earned: Bonus), NewBest, Best, Place, Of.
local function streetFinish(race, d)
	local underPar = d.Time <= d.Par
	local bonus = d.Bonus
	if bonus == nil then
		bonus = underPar -- (a server from before places: every finish under par had the bonus)
	end
	local place, of = tonumber(d.Place), tonumber(d.Of)
	local title, color = "FINISH", C.Text
	if place and of and of > 1 then
		title = (K.ORDINAL[place] or (place .. "TH")) .. " PLACE"
		color = place == 1 and C.Gold or C.Text
	end
	showFinish(string.upper(race.Name), title, color, {
		{ underPar and "UNDER PAR" or "TIME", underPar and C.Gold or C.Dim, fmt(d.Time), C.Text },
		{ d.NewBest and "NEW BEST" or "BEST", d.NewBest and C.Gold or C.Dim,
			fmt(type(d.Best) == "number" and d.Best or d.Time), d.NewBest and C.Gold or C.Text },
		-- (short words: a phone's column is 120 px; green = cash)
		{ bonus and "WITH BONUS" or "REWARD", bonus and C.Gold or C.Dim, "+" .. HUDController.Money(d.Reward), C.Cash },
	})
end

-- A challenge's card: YOU WIN / YOU LOST, both times and the gap. mine / theirs = { Name, Time }; a
-- missing time is "..." while they may still finish (waiting) and DNF once it's over.
local function duelCard(win, mine, theirs, waiting)
	local function shown(row)
		return type(row.Time) == "number" and fmt(row.Time) or (waiting and "..." or "DNF")
	end
	local gap = "-"
	if type(mine.Time) == "number" and type(theirs.Time) == "number" then
		gap = string.format("%s%.2fs", mine.Time <= theirs.Time and "-" or "+", math.abs(mine.Time - theirs.Time))
	end
	showFinish("STREET DUEL", win and "YOU WIN" or "YOU LOST", win and C.Gold or C.Orange, {
		{ "YOUR TIME", C.Dim, shown(mine), win and C.Gold or C.Text },
		{ string.upper(tostring(theirs.Name or "RIVAL")), C.Dim, shown(theirs), C.Text },
		{ "GAP", C.Dim, gap, win and C.Cash or C.Orange },
	})
end

-- The standings hang under the finish card, wherever that is now (it can step down under a stamp).
local function placeStandings()
	local touch = Theme.IsTouch()
	ui.standings.Position = UDim2.new(0.5, 0, 0, ui.finish.Position.Y.Offset + (touch and K.CARD_DOWN_TOUCH or K.CARD_DOWN) + 6)
end

-- One cell of a standings row.
local function standCell(line, name, x, w, words, kind, align, size, color)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = x
	l.Size = w
	l.Text = words
	Theme.Text(l, size, kind)
	l.TextColor3 = color
	l.TextXAlignment = align
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = line
	return l
end

-- Fill and show the standings (see the header). rows = RaceService's { Name, Time, Out, Npc, UserId }.
local function showStandings(rows, title)
	local touch = Theme.IsTouch()
	local rowH = touch and K.ROW_H_TOUCH or K.ROW_H
	local size = touch and 13 or 14
	ui.standRows:ClearAllChildren()
	ui.standTitle.Text = title
	local n = 0
	for i, row in ipairs(rows) do
		if i > K.STAND_ROWS then
			break
		end
		if type(row) == "table" then
			n += 1
			local me = row.UserId == player.UserId
			local line = Instance.new("Frame")
			line.Name = "Row" .. n
			line.BackgroundTransparency = 1
			line.Position = UDim2.fromOffset(0, (n - 1) * rowH)
			line.Size = UDim2.new(1, 0, 0, rowH)
			line.Parent = ui.standRows
			if me then
				local bar = Instance.new("Frame") -- a thin pink bar: this one is you
				bar.Name = "You"
				bar.Position = UDim2.fromOffset(4, 2)
				bar.Size = UDim2.new(0, 2, 1, -4)
				bar.BackgroundColor3 = C.Brand
				bar.BorderSizePixel = 0
				bar.Parent = line
			end
			local color = me and C.Gold or (row.Npc and C.Dim or C.Text)
			local timed = type(row.Time) == "number"
			standCell(line, "Place", UDim2.fromOffset(12, 0), UDim2.new(0, 22, 1, 0), tostring(n), "Display",
				Enum.TextXAlignment.Left, size + 2, color)
			standCell(line, "Name", UDim2.fromOffset(36, 0), UDim2.new(1, -36 - 82, 1, 0), tostring(row.Name or "?"), "Body",
				Enum.TextXAlignment.Left, size, color)
			standCell(line, "Time", UDim2.new(1, -80, 0, 0), UDim2.new(0, 68, 1, 0),
				timed and fmt(row.Time) or (row.Out and "DNF" or "..."), "Display", Enum.TextXAlignment.Right, size + 2,
				timed and color or C.Dim)
		end
	end
	local buttonH = touch and Theme.Touch or K.REMATCH_H
	RS.standBase = K.STAND_HEAD + n * rowH + 8
	local w = touch and K.STAND_W_TOUCH or K.STAND_W
	ui.standings.Size = UDim2.fromOffset(w, RS.standBase + (RS.rematch and (buttonH + 8) or 0))
	ui.rematch.Size = UDim2.new(1, -24, 0, buttonH)
	ui.rematch.Visible = RS.rematch ~= nil
	placeStandings()
	ui.standings.Visible = true
end

-- Five times a second: REMATCH's seconds, and the panel goes when its time is up or a race starts.
local function standingsTick()
	if not ui.standings.Visible then
		return
	end
	local t = os.clock()
	local m = RS.rematch
	if m then
		local left = math.ceil(m.untilAt - t)
		if left <= 0 then
			RS.rematch = nil
			ui.rematch.Visible = false
			ui.standings.Size = UDim2.fromOffset(ui.standings.Size.X.Offset, RS.standBase)
		else
			local words = "REMATCH  " .. left
			if ui.rematch.Text ~= words then
				ui.rematch.Text = words
			end
		end
	end
	if current or (not RS.rematch and t > RS.standUntil) or player:GetAttribute("TitleScreen") == true then
		ui.standings.Visible = false
		RS.rematch = nil
		return
	end
	placeStandings()
end

local function pressRematch()
	local m = RS.rematch
	if not m then
		return
	end
	RS.rematch = nil
	ui.rematch.Visible = false
	ui.standings.Size = UDim2.fromOffset(ui.standings.Size.X.Offset, RS.standBase)
	RS.pending = os.clock() + 3 -- (ChallengeSent makes it the challenge's own time)
	task.spawn(function()
		Remotes.Event("RaceChallenge"):FireServer("Rematch", m.userId)
	end)
end

-- Five times a second: the lobby banner (see the header) for the lobby a member is in, or one open
-- near a citizen who could join it.
local function lobbyTick()
	local words
	if not current and player:GetAttribute("TitleScreen") ~= true and not ui.job.Visible then
		local mine = player:GetAttribute("RaceLobby")
		local root = rootPart()
		local pos = root and flat(root.Position)
		local free = canRace()
		local t = now()
		for _, race in ipairs(Activities.Races) do
			local startsAt = ReplicatedStorage:GetAttribute("RaceLobby_" .. race.Id)
			local member = mine == race.Id
			if type(startsAt) == "number" and startsAt > t
				and (member or (free and pos ~= nil and (pos - flat(race.Start)).Magnitude <= K.LOBBY_SHOW)) then
				local n = ReplicatedStorage:GetAttribute("RaceLobbyN_" .. race.Id)
				n = type(n) == "number" and n or 0
				local tail
				if member then
					tail = n > 1 and string.format("%d racers  ·  you're in", n) or "you're in"
				elseif n >= (K.RULES.MaxRacers or 6) then
					tail = "full"
				else
					tail = "press Race on the pad to join"
				end
				words = string.format('<font color="#%s">%s</font>  starts in %d  ·  %s', K.HEX_GOLD, string.upper(race.Name),
					math.max(1, math.ceil(startsAt - t)), tail)
				break
			end
		end
	end
	ui.lobby.Visible = words ~= nil
	if words then
		if ui.lobby.Text ~= words then
			ui.lobby.Text = words
		end
		-- Under the route preview card while that shows (a member stopped on the pad sees both).
		ui.lobby.Position = UDim2.new(0.5, 0, 0, ui.cardY + (ui.previewCard.Visible and (K.CARD_H + 6) or 0))
	end
end

-- Race challenges ----------------------------------------------------------------------------------

-- Could this player race a challenge now (the server checks the same)?
local function freeToDuel(p)
	return p:GetAttribute("Side") == "Civilian" and (p:GetAttribute("Heat") or 0) <= 0
		and p:GetAttribute("Mission") == nil and p:GetAttribute("JobKind") == nil and not p:GetAttribute("BigScore")
		and p:GetAttribute("RacingId") == nil and p:GetAttribute("RaceLobby") == nil and p:GetAttribute("InHome") ~= true
end

-- The nearest other free driver at the wheel of their own car (not a boat) within K.CHALLENGE_SHOW
-- studs of ours, while we sit at the wheel of ours; else nil. Who drives which car comes from
-- VehicleService's DriverUserId attribute (it replicates; another body's seat doesn't always).
local function challengeRival()
	if player:GetAttribute("TitleScreen") == true or not freeToDuel(player) then
		return nil
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.Health > 0 and hum.SeatPart
	local mine = seat and seat.Name == "DriverSeat" and seat.Parent
	if not mine or mine:GetAttribute("OwnerUserId") ~= player.UserId or mine:GetAttribute("Boat") == true or not mine.PrimaryPart then
		return nil
	end
	local here = flat(mine.PrimaryPart.Position)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	local best, bestD
	for _, car in ipairs(vehicles and vehicles:GetChildren() or {}) do
		local id = car:GetAttribute("DriverUserId")
		if car ~= mine and id ~= nil and id == car:GetAttribute("OwnerUserId") and car:GetAttribute("Boat") ~= true and car.PrimaryPart then
			local p = Players:GetPlayerByUserId(id)
			if p and p ~= player and freeToDuel(p) then
				local d = (flat(car.PrimaryPart.Position) - here).Magnitude
				if d <= K.CHALLENGE_SHOW and (not bestD or d < bestD) then
					best, bestD = p, d
				end
			end
		end
	end
	return best
end

-- The key for CHALLENGE from the last input used: "K", "R3", or nil after a touch.
local function challengeKeyWord()
	local name = UserInputService:GetLastInputType().Name
	if string.sub(name, 1, 7) == "Gamepad" then
		return "R3"
	elseif Theme.IsTouch() or name == "Touch" then
		return nil
	end
	return "K"
end

-- The key cap on the PC button (none after a touch).
local function refreshChallengeKey()
	local word = challengeKeyWord()
	local cap = ui.challengeKey
	if cap and cap.Text == word then
		return
	end
	if cap then
		cap:Destroy()
		ui.challengeKey = nil
	end
	if word then
		ui.challengeKey = Theme.Key(ui.challengeRow, word)
		ui.challengeKey.LayoutOrder = 1
	end
end

-- Into the side column's slot (see the header).
local function placeChallenge()
	local touch = Theme.IsTouch()
	local pos, size = LawClient.SideSlot(ui.gui, LawClient.PlaceSlots(), touch)
	local b = ui.challenge
	if touch then
		b.Position = UDim2.fromOffset(pos.X, pos.Y)
		b.Size = UDim2.fromOffset(size.X, size.Y)
	else
		b.Position = UDim2.fromOffset(pos.X + size.X - K.CHALLENGE_W, pos.Y)
		b.Size = UDim2.fromOffset(K.CHALLENGE_W, 44)
	end
	ui.challengeRow.Visible = not touch
	ui.challengeTile.Visible = touch
end

-- Is one of K.CHALLENGE_CLEAR on the button's spot right now?
local function challengeCovered()
	local playerGui = player:FindFirstChild("PlayerGui")
	local origin = ui.gui.AbsolutePosition
	local b = ui.challenge
	local x, y, w, h = b.Position.X.Offset, b.Position.Y.Offset, b.Size.X.Offset, b.Size.Y.Offset
	for _, path in ipairs(K.CHALLENGE_CLEAR) do
		local ox, oy, ow, oh = liveBox(playerGui, path, origin)
		if ox and ox < x + w and ox + ow > x and oy < y + h and oy + oh > y then
			return true
		end
	end
	return false
end

-- Five times a second: CHALLENGE shows while there is somebody to challenge (and no answer is awaited).
local function challengeTick()
	local rival = nil
	if not current and os.clock() >= RS.pending then
		rival = challengeRival()
	end
	RS.rival = rival
	local show = rival ~= nil
	if show then
		placeChallenge()
		refreshChallengeKey()
		show = not challengeCovered()
	end
	if ui.challenge.Visible ~= show then
		ui.challenge.Visible = show
		if show and not RS.hinted then
			RS.hinted = true
			local key = challengeKeyWord()
			local how = key and ("press " .. key .. " (or click CHALLENGE)") or "tap CHALLENGE"
			NotifyController.Show("Another driver is right next to you: " .. how .. " to race them!", C.Gold, "info")
		end
	end
end

local function sendChallenge()
	local rival = RS.rival
	if not rival or not ui.challenge.Visible then
		return
	end
	RS.pending = os.clock() + 3 -- (ChallengeSent makes it the challenge's own time)
	ui.challenge.Visible = false
	local userId = rival.UserId
	task.spawn(function()
		Remotes.Event("RaceChallenge"):FireServer("Challenge", userId)
	end)
end

-- The challenge card (see the header), laid out like CrewClient's invite card.
local function fitInvite()
	local card = RS.invite
	local gui = ui.inviteGui
	if not card or not gui then
		return
	end
	local screen = gui.AbsoluteSize
	if screen.X < 1 then
		return
	end
	local W, H = screen.X, screen.Y
	local touch = Theme.IsTouch()
	local pad = touch and 8 or 10
	local buttonH = touch and Theme.Touch or 32
	local h = touch and (pad + buttonH + pad) or (pad + 18 + 36 + 6 + buttonH + pad)
	-- Across: right of the left column (feed; minimap on phones), left of the Status column.
	local lx, _, lw = zoneBox(touch and "Minimap" or "Feed", touch, W, H)
	local left = lx + lw + 8
	local right = zoneBox("Status", touch, W, H) - 8
	local least = touch and K.INVITE_MIN_TOUCH or K.INVITE_W
	if right - left < least then
		left = 12 -- too tight (small phones): cover the minimap rather than squash the words
	end
	local w = math.min(touch and K.INVITE_W_TOUCH or K.INVITE_W, math.max(least, right - left), W - 24)
	local x = math.clamp(W / 2, left + w / 2, math.max(left + w / 2, right - w / 2))
	-- Down: centred on the Stamp zone, under the Banner zone and above the Subtitle zone (phones: Action).
	local _, sy, _, sh = zoneBox("Stamp", touch, W, H)
	local _, by, _, bh = zoneBox("Banner", touch, W, H)
	local _, ly = zoneBox(touch and "Action" or "Subtitle", touch, W, H)
	local minTop = by + bh + 4
	local y = math.clamp(sy + sh / 2 - h / 2, minTop, math.max(minTop, ly - 4 - h))
	card.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	card.Size = UDim2.fromOffset(w, h)
	local tag, line = card:FindFirstChild("Tag"), card:FindFirstChild("Line")
	local accept, decline = card:FindFirstChild("Accept"), card:FindFirstChild("Decline")
	if not (tag and line and accept and decline) then
		return
	end
	if touch then
		-- One row: [RACE CHALLENGE / <name> challenges you...] .... [ACCEPT] [DECLINE]
		local reserved = 14 + 10 + K.ACCEPT_W + 6 + K.DECLINE_W + 8
		tag.TextSize = 13
		tag.Position = UDim2.fromOffset(14, 6)
		tag.Size = UDim2.new(1, -reserved, 0, 14)
		line.TextSize = 13
		line.Position = UDim2.fromOffset(14, 22)
		line.Size = UDim2.new(1, -reserved, 0, 32)
		decline.AnchorPoint = Vector2.new(1, 0.5)
		decline.Position = UDim2.new(1, -8, 0.5, 0)
		decline.Size = UDim2.fromOffset(K.DECLINE_W, buttonH)
		accept.AnchorPoint = Vector2.new(1, 0.5)
		accept.Position = UDim2.new(1, -(8 + K.DECLINE_W + 6), 0.5, 0)
		accept.Size = UDim2.fromOffset(K.ACCEPT_W, buttonH)
	else
		tag.TextSize = 14
		tag.Position = UDim2.fromOffset(16, pad)
		tag.Size = UDim2.new(1, -32, 0, 16)
		line.TextSize = 15
		line.Position = UDim2.fromOffset(16, pad + 18)
		line.Size = UDim2.new(1, -32, 0, 36)
		for _, b in ipairs({ accept, decline }) do
			b.AnchorPoint = Vector2.new(0, 1)
			b.Size = UDim2.new(0.5, -(16 + 4), 0, buttonH)
			b.Position = UDim2.new(b == accept and 0 or 0.5, b == accept and 16 or 4, 1, -pad)
		end
	end
end

local function closeInvite()
	if RS.invite then
		RS.invite:Destroy()
		RS.invite = nil
	end
end

local function inviteButton(card, name, words, kind, action)
	local b = Instance.new("TextButton")
	b.Name = name
	Theme.Button(b, kind)
	if kind == "Quiet" then
		b.BackgroundColor3 = C.PanelLight
		b.BackgroundTransparency = 0.15
	end
	b.TextSize = 14
	b.Text = words
	b.Parent = card
	b.Activated:Connect(function()
		local from = card:GetAttribute("From") -- (whose challenge this card is: the server checks it)
		closeInvite()
		task.spawn(function()
			Remotes.Event("RaceChallenge"):FireServer(action, from)
		end)
	end)
	return b
end

-- The card shows unless a stamp uses its spot or the title screen is up (it keeps its time meanwhile).
local function inviteWanted()
	return player:GetAttribute("TitleScreen") ~= true and stampBand() == nil
end

-- d = RaceService's "Challenge": FromName, Expires, Rematch.
local function showInvite(d)
	closeInvite()
	local card = Instance.new("Frame")
	card.Name = "RaceChallenge"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Active = true -- taps on the card don't reach the world behind it
	Theme.Panel(card, 0.2)
	card.Parent = ui.inviteGui
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(0, 8)
	accent.Size = UDim2.new(0, 2, 1, -16)
	accent.BackgroundColor3 = C.Gold
	accent.BorderSizePixel = 0
	accent.Parent = card
	local tag = Instance.new("TextLabel")
	tag.Name = "Tag"
	Theme.Text(tag, 14, "Display")
	tag.TextColor3 = C.Gold
	tag.TextXAlignment = Enum.TextXAlignment.Left
	tag.Size = UDim2.new(1, -32, 0, 16)
	tag.Text = d.Rematch and "REMATCH" or "RACE CHALLENGE"
	tag.Parent = card
	if type(d.FromUserId) == "number" then
		card:SetAttribute("From", d.FromUserId)
	end
	local line = Instance.new("TextLabel")
	line.Name = "Line"
	Theme.Text(line, 15, "Body")
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextYAlignment = Enum.TextYAlignment.Top
	line.TextWrapped = true
	line.TextTruncate = Enum.TextTruncate.AtEnd
	line.Size = UDim2.new(1, -32, 0, 36)
	line.Text = tostring(d.FromName or "Someone") .. (d.Rematch and " wants a rematch!" or " challenges you to a race!")
	line.Parent = card
	inviteButton(card, "Accept", "ACCEPT", "Primary", "Accept")
	inviteButton(card, "Decline", "DECLINE", "Quiet", "Decline")
	RS.invite = card
	fitInvite()
	card.Visible = inviteWanted()
	local seconds = math.clamp(tonumber(d.Expires) or K.CHALLENGE_EXPIRE, 1, 60)
	task.delay(seconds, function()
		if RS.invite == card then
			closeInvite()
		end
	end)
end

local function inviteTick()
	local card = RS.invite
	if card then
		local want = inviteWanted()
		if card.Visible ~= want then
			card.Visible = want
		end
	end
end

-- A challenge's result (RaceService's "DuelResult"): the card, the two rows and REMATCH.
local function onDuelResult(d)
	if type(d.Rows) ~= "table" then
		return
	end
	if current and current.duel and current.run == d.Run then
		endRace() -- (the one who crossed second: the race ends here with the result)
	elseif current then
		return -- (a late result from an earlier challenge while already in a new race: never over it)
	end
	local mine, theirs
	for _, row in ipairs(d.Rows) do
		if type(row) == "table" then
			if row.UserId == player.UserId then
				mine = row
			else
				theirs = row
			end
		end
	end
	if not mine or not theirs then
		return
	end
	RS.lastRun = d.Run
	duelCard(d.Win == true, mine, theirs, false)
	local rematch = math.clamp(tonumber(d.Rematch) or 0, 0, 60)
	RS.rematch = (rematch > 0 and type(d.OpponentUserId) == "number") and { userId = d.OpponentUserId, untilAt = os.clock() + rematch } or nil
	RS.standUntil = os.clock() + math.max(K.STAND_SECONDS, rematch)
	ui.rematch.Text = "REMATCH"
	showStandings(d.Rows, "STREET DUEL")
end

local function onRace(kind, d)
	if type(d) ~= "table" then
		return
	end
	if kind == "Countdown" then
		local base
		if d.Def ~= nil then
			base = registerDuel(d.Id, d.Def)
		else
			base = racesById[d.Id]
		end
		if not base or type(d.StartAt) ~= "number" then
			return
		end
		local laps = math.clamp(math.floor(tonumber(d.Laps) or 1), 1, 9)
		local race = raceView(base, laps)
		current = {
			race = race, index = 1, startAt = d.StartAt, laps = laps, pos = tonumber(d.Grid), of = tonumber(d.Of),
			run = d.Run, duel = base.Duel == true,
		}
		previewRace = nil
		ui.previewCard.Visible = false
		ui.finishToken += 1 -- (a finish card still up makes way for the countdown)
		ui.finish.Visible = false
		ui.standings.Visible = false
		RS.rematch = nil
		RS.pending = 0
		closeInvite()
		ui.bigKicker.Text = string.upper(current.duel and ("vs " .. tostring(d.Opponent or "your rival")) or race.Name)
		showCheckpoint()
		showLine()
		ui.timerLabel.Visible = true
		refreshRaceHud(false, false)
		if current.duel then
			NotifyController.Show(string.format("Race vs %s: first across the finish line wins!", tostring(d.Opponent or "your rival")),
				C.Gold, "info")
		else
			local field = {}
			if (current.of or 1) > 1 then
				table.insert(field, current.of .. " cars")
			end
			if laps > 1 then
				table.insert(field, laps .. " laps")
			end
			local goal = (current.of or 1) > 1 and ("Win under " .. clock(race.Par)) or ("Beat " .. clock(race.Par))
			NotifyController.Show(string.format("%s: %s%s for the bonus!", race.Name,
				#field > 0 and (table.concat(field, ", ") .. ". ") or "", goal), C.Gold, "info")
		end
	elseif kind == "Checkpoint" and current then
		local race = current.race
		if type(d.Index) ~= "number" or not race.Checkpoints[d.Index] then
			return
		end
		local passed = race.Checkpoints[d.Index - 1]
		if passed then
			burstAt(passed, ringSize(race), K.GOLD, ringBase(race))
		end
		current.index = d.Index
		showCheckpoint()
		showLine()
		refreshRaceHud(false, true)
		local per = race.PerLap
		if per and current.laps > 1 and d.Index == (current.laps - 1) * per + 1 then
			NotifyController.Show("Final lap!", C.Gold, "info")
		end
	elseif kind == "Position" and current then
		local pos, of = tonumber(d.Pos), tonumber(d.Of)
		if pos and of then
			local moved = current.pos ~= pos
			current.pos, current.of = pos, of
			refreshRaceHud(moved, false)
		end
	elseif kind == "Finished" then
		local race = current and current.race or racesById[d.Id]
		if current and race then
			burstAt(race.Checkpoints[#race.Checkpoints], ringSize(race), K.WHITE, ringBase(race))
		end
		endRace()
		RS.lastRun = d.Run
		if d.Duel then
			if type(d.Time) == "number" then
				duelCard(true, { Time = d.Time }, { Name = d.Opponent }, true) -- (the rival's time comes with DuelResult)
			end
		elseif race and type(d.Time) == "number" and type(d.Par) == "number" and type(d.Reward) == "number" then
			streetFinish(race, d)
		end
	elseif kind == "Standings" then
		-- Only for the run we just finished (a later race of ours, or one we're in now, wins).
		if not current and d.Run ~= nil and d.Run == RS.lastRun and type(d.Rows) == "table" and #d.Rows > 1 then
			RS.standUntil = os.clock() + K.STAND_SECONDS
			showStandings(d.Rows, "RESULTS")
		end
	elseif kind == "DuelResult" then
		onDuelResult(d)
	elseif kind == "DuelLead" then
		NotifyController.Show(string.format("%s crossed the line first! Finish within %d s for your time.",
			tostring(d.Name or "Your rival"), tonumber(d.Grace) or 30), C.Orange, "warning")
	elseif kind == "Cancelled" then
		endRace()
		NotifyController.Show(K.WHY[d.Reason] or "Race cancelled.", C.Orange, "warning")
	elseif kind == "Lobby" then
		local race = racesById[d.Id]
		local left = type(d.StartsAt) == "number" and math.max(1, math.ceil(d.StartsAt - now())) or nil
		if race and left then
			NotifyController.Show(string.format("You're in! %s starts in %d s. Others can join at the pad.", race.Name, left), C.Gold, "info")
		end
	elseif kind == "LobbyJoin" then
		NotifyController.Show(tostring(d.Name or "Someone") .. " joined the race!", C.Gold, "info")
	elseif kind == "Challenge" then
		showInvite(d)
	elseif kind == "ChallengeGone" then
		closeInvite()
	elseif kind == "ChallengeSent" then
		RS.pending = os.clock() + (tonumber(d.Expires) or K.CHALLENGE_EXPIRE) + 1
		NotifyController.Show(string.format("Race challenge sent to %s. Waiting for an answer...", tostring(d.Name or "them")), C.Gold, "info")
	elseif kind == "ChallengeAnswer" then
		RS.pending = 0
		local name = tostring(d.Name or "They")
		if d.Answer == "Declined" then
			NotifyController.Show(name .. " declined your race challenge.", nil, "info")
		elseif d.Answer == "Expired" then
			NotifyController.Show(name .. " didn't answer your race challenge.", nil, "info")
		else
			NotifyController.Show("The race challenge with " .. name .. " is off.", C.Orange, "warning")
		end
	end
end

-- Stunts ---------------------------------------------------------------------------------------------

local function onStunt(d)
	if d.Failed then
		if d.Crashed then
			NotifyController.Show(d.Name .. ": crashed the landing!", C.Orange, "warning")
		else
			NotifyController.Show(string.format("%s: %d ft - need %d ft. Faster!", d.Name, d.Distance, d.Need), C.Orange, "warning")
		end
		return
	end
	-- Gold: a reward. The jump's name on top, then the distance, the pay and how many are found.
	local sub = string.format("%d ft", d.Distance)
	if d.Pay > 0 then
		sub ..= "  ·  +" .. HUDController.Money(d.Pay)
	end
	HUDController.Stamp("STUNT JUMP", sub .. string.format("  ·  %d / %d", d.Done, d.Total), C.Gold, d.Name)
end

-- Drift zone -------------------------------------------------------------------------------------------

local drift = {
	inZone = false, -- driving inside the pad right now
	enteredAt = 0, -- os.clock() when they last drove onto it
	scored = false, -- a chain has paid this session: they can drift now
	teachUntil = 0, -- os.clock() until the how-to hides (math.huge = until the first paid chain)
	leftAt = -math.huge, -- os.clock() when they last drove off the pad
	chain = false, -- a chain is running (DriftScore is set)
	lastScore = 0, -- the running chain's last score
	lastCombo = 1, -- ...and its multiplier
	lastPaidAt = 0, -- os.clock() of the last DriftEvent
	stampOn = false, -- the stamp is showing (or fading out)
	hinted = false, -- the "what is this" toast was shown
	titleOnly = false, -- the how-to panel is its title alone (DriveUI's key strip has the how-to)
}
local stampToken = 0 -- a newer stamp (or a new chain) retires an older one
local stampFade, shadowFade -- the stamp's fade-out (text + panel, its shadow) while it plays
local driftY, driftX, driftW = K.DRIFT_Y, nil, K.DRIFT_W -- where the row sits now (placeDrift)

-- Find the row's spot: under any top-centre panel that hangs across it from above (the HUD is laid out
-- per screen and still being restyled, so it is measured live, like NotifyController's topY), its
-- bottom never past K.DRIFT_LOWEST of the screen; then as wide as the side columns sharing those rows
-- allow, centred when it can be. All three pieces share the spot (only one shows at a time).
local function placeDrift()
	local size = ui.gui.AbsoluteSize
	local W, H = size.X, size.Y
	if W <= 0 or H <= 0 then
		return
	end
	local touch = Theme.IsTouch()
	local base = touch and K.DRIFT_Y_TOUCH or K.DRIFT_Y
	local mid = W / 2
	local playerGui = player:FindFirstChild("PlayerGui")
	local origin = ui.gui.AbsolutePosition
	-- The least the row may be: the how-to row as it is now (its text can't shrink), never under
	-- K.DRIFT_MIN_W; and the most: K.DRIFT_W, or that least where it is more (a phone's long caps).
	-- (One width for all three pieces, so the row doesn't jump when the piece changes.)
	local need = math.max(K.DRIFT_MIN_W, ui.howNeed or 0)
	local full = math.max(K.DRIFT_W, need)
	local top = base
	for _, path in ipairs(K.DRIFT_CLEAR) do
		local x, y, w, h = liveBox(playerGui, path, origin)
		-- Only a piece across our width that hangs down from above our spot (moving down can't help
		-- with one that starts lower, like a help line at the bottom of a short screen).
		if x and x < mid + full / 2 and x + w > mid - full / 2 and y < base then
			top = math.max(top, math.floor(y + h) + 6)
		end
	end
	top = math.max(base, math.min(top, math.floor(H * K.DRIFT_LOWEST) - K.TEACH_H))
	-- Sideways: the minimap, the toasts and the right-hand buttons come close on a phone.
	local left, right = 0, W
	for _, name in ipairs(K.DRIFT_SIDE_ZONES) do
		local x, y, w, h = zoneBox(name, touch, W, H)
		left, right = narrow(left, right, top, K.TEACH_H, mid, x, y, w, h)
	end
	for _, path in ipairs(K.DRIFT_SIDE_LIVE) do
		local x, y, w, h = liveBox(playerGui, path, origin)
		left, right = narrow(left, right, top, K.TEACH_H, mid, x, y, w, h)
	end
	-- The status column and its pills are right-aligned text: their zones are kept clear only while
	-- that still leaves the row its least width.
	local softLeft, softRight = left, right
	for _, name in ipairs(K.DRIFT_SIDE_SOFT) do
		local x, y, w, h = zoneBox(name, touch, W, H)
		softLeft, softRight = narrow(softLeft, softRight, top, K.TEACH_H, mid, x, y, w, h)
	end
	if softRight - softLeft >= need then
		left, right = softLeft, softRight
	end
	local w = math.floor(math.min(full, right - left))
	if w < need then
		w = math.floor(math.min(need, W - 2 * K.DRIFT_GAP)) -- a very small screen: something gets overlapped
	end
	local lo, hi = left + w / 2, right - w / 2
	local cx = math.floor(hi >= lo and math.clamp(mid, lo, hi) or (left + right) / 2)
	if top ~= driftY or cx ~= driftX or w ~= driftW then
		driftY, driftX, driftW = top, cx, w
		local pos = UDim2.fromOffset(cx, top)
		ui.driftTeach.Position, ui.driftScoreLabel.Position, ui.driftStampLabel.Position = pos, pos, pos
		ui.driftTeach.Size = UDim2.fromOffset(w, drift.titleOnly and K.TITLE_H or K.TEACH_H)
		ui.driftScoreLabel.Size = UDim2.fromOffset(w, K.SCORE_H)
		ui.driftStampLabel.Size = UDim2.fromOffset(w, K.STAMP_H)
	end
end

-- Is a HUDController stamp ("RANK UP" after a paid chain) drawn across the row now?
local function hudStampOver(top)
	local stampTop, stampBottom = stampBand()
	return stampTop ~= nil and stampTop < top + K.TEACH_H and stampBottom > top
end

-- DriveUI's key strip (keyboard / gamepad) is up: it has the same drift row, so our own row waits
-- (the banner shows its title alone meanwhile).
local function driveStripUp()
	local playerGui = player:FindFirstChild("PlayerGui")
	local sg = playerGui and playerGui:FindFirstChild("DriveUI")
	local strip = sg and sg:IsA("ScreenGui") and sg.Enabled and sg:FindFirstChild("ControlsHint")
	return strip and strip:IsA("GuiObject") and strip.Visible or false
end

-- Show or hide a piece; one that comes on drops in.
local function setShown(obj, on, scale, from)
	if obj.Visible ~= on then
		obj.Visible = on
		if on then
			pop(scale, from)
		end
	end
end

-- Which piece the row shows now: the running chain, else a stamp, else the DRIFT ZONE banner (all step
-- aside while a HUDController stamp covers the row).
local function driftView()
	local t = os.clock()
	local scoring = drift.chain
	local stamped = drift.stampOn and not scoring
	local teach = drift.inZone and t < drift.teachUntil and t - drift.enteredAt >= K.TEACH_DELAY
		and not scoring and not stamped
	-- The banner announces the zone at once on every device. While DriveUI's key strip is up (keyboard /
	-- gamepad, its first seconds in the zone) that strip is the how-to, so the banner is its title
	-- alone; when the strip has gone the banner grows its own how-to row. One how-to at a time.
	local titleOnly = teach and driveStripUp()
	if titleOnly ~= drift.titleOnly then
		drift.titleOnly = titleOnly
		ui.driftHowRow.Visible = not titleOnly
		ui.driftTeach.Size = UDim2.fromOffset(driftW, titleOnly and K.TITLE_H or K.TEACH_H)
		if teach and not titleOnly and ui.driftTeach.Visible then
			pop(ui.teachScale, 1.08) -- the how-to row just joined a banner that was already up: a small nudge
		end
	end
	local covered = (scoring or stamped or teach) and hudStampOver(driftY)
	setShown(ui.driftScoreLabel, scoring and not covered, ui.scoreScale, 1.15)
	setShown(ui.driftStampLabel, stamped and not covered, ui.stampScale, 1.3)
	setShown(ui.driftTeach, teach and not covered, ui.teachScale, 1.08)
end

-- 0 on the pad, else studs from its edge. Uses the real part while it is streamed in.
local function driftZoneAway(pos)
	local acts = Workspace:FindFirstChild("Activities")
	local zone = acts and acts:FindFirstChild("DriftZone")
	local rel, half
	if zone and zone:IsA("BasePart") then
		rel, half = zone.CFrame:PointToObjectSpace(pos), zone.Size / 2
	else
		local cfg = Activities.DriftZone
		rel, half = pos - cfg.Center, cfg.Size / 2
	end
	local dx = math.max(math.abs(rel.X) - half.X, 0)
	local dz = math.max(math.abs(rel.Z) - half.Z, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- What a chain of `score` points pays (DriftService's rule; it can also publish DriftCash itself).
local function driftCash(score)
	local published = player:GetAttribute("DriftCash")
	if type(published) == "number" then
		return published
	end
	local rule = Activities.Drift
	if score < rule.MinScore then
		return 0
	end
	return math.min(rule.MaxPayout, score // rule.PointsPerDollar)
end

-- The stamp after a chain: it waits while a HUDController stamp covers the row (then gives up: the
-- cash counter has said it already), drops in, stays K.STAMP_SECONDS and fades out.
local function driftStamp(rich)
	stampToken += 1
	local token = stampToken
	task.spawn(function()
		local waited = 0
		while hudStampOver(driftY) and waited < K.STAMP_WAIT do
			waited += task.wait(0.2)
		end
		if stampToken ~= token or drift.chain or hudStampOver(driftY) then
			return
		end
		if stampFade then
			stampFade:Cancel()
			shadowFade:Cancel()
		end
		ui.driftStampLabel.TextTransparency = 0
		ui.driftStampLabel.BackgroundTransparency = Theme.PanelAlpha
		ui.stampShadow.Transparency = 0.45
		ui.driftStampLabel.Text = rich
		placeDrift()
		drift.stampOn = true
		driftView()
		task.wait(K.STAMP_SECONDS)
		if stampToken ~= token then
			return
		end
		stampFade = TweenService:Create(ui.driftStampLabel, K.FADE, { TextTransparency = 1, BackgroundTransparency = 1 })
		shadowFade = TweenService:Create(ui.stampShadow, K.FADE, { Transparency = 1 })
		stampFade:Play()
		shadowFade:Play()
		task.wait(K.FADE.Time)
		if stampToken == token then
			drift.stampOn = false
			driftView()
		end
	end)
end

-- DriftScore / DriftCombo / DriftCash changed: the live line, or the end of a chain.
local function refreshDrift()
	local score = player:GetAttribute("DriftScore")
	if type(score) == "number" then
		if not drift.chain then
			-- A new chain: it retires any stamp still up and finds its spot first. (The first tick of a
			-- slide is worth a few points: that alone doesn't retire the how-to. A paid chain does, in onDrift.)
			drift.chain = true
			drift.lastCombo = 1
			stampToken += 1
			drift.stampOn = false
			placeDrift()
		end
		drift.lastScore = score
		local combo = player:GetAttribute("DriftCombo")
		combo = type(combo) == "number" and combo or 1
		local cash = driftCash(score)
		ui.driftScoreLabel.Text = string.format('<font color="#%s">DRIFT</font>  %s  <font color="#%s">x%d</font>  <font color="#%s">%s</font>',
			K.HEX_DIM, string.sub(HUDController.Money(score), 2), K.HEX_GOLD, combo,
			cash > 0 and K.HEX_CASH or K.HEX_DIM, HUDController.Money(cash))
		if combo > drift.lastCombo and ui.driftScoreLabel.Visible then
			pop(ui.scoreScale, 1.2) -- the multiplier went up
		end
		drift.lastCombo = combo
		driftView()
		return
	end
	local ended = drift.chain and drift.lastScore or 0
	drift.chain = false
	drift.lastScore = 0
	driftView()
	-- The chain just ended. A paid one gets its stamp from DriftEvent; a short one paid nothing, so
	-- say why (after a moment, in case the stamp is still on its way).
	if ended > 0 and ended < Activities.Drift.MinScore then
		task.delay(0.4, function()
			if os.clock() - drift.lastPaidAt > 1 and not drift.chain then
				driftStamp(string.format('TOO SHORT  <font color="#%s">hold the slide longer</font>', K.HEX_DIM))
			end
		end)
	end
end

local function onDrift(d)
	if type(d) ~= "table" or type(d.Pay) ~= "number" then
		return
	end
	-- A paid chain: they can drift now, so the how-to has done its job (later visits get a reminder).
	drift.scored = true
	drift.teachUntil = 0
	drift.lastPaidAt = os.clock()
	driftView()
	local note = d.Best and "NEW BEST" or (d.Reason == "crash" and "CRASHED") or (d.Reason == "max" and "MAXED") or nil
	driftStamp(string.format('<font color="#%s">+%s</font> DRIFT%s', K.HEX_CASH, HUDController.Money(d.Pay),
		note and string.format('  <font color="#%s">%s</font>', K.HEX_GOLD, note) or ""))
end

-- Five times a second: the first-visit toast, whether we are driving on the pad, and the row.
local function driftTick()
	local root = rootPart()
	if not root then
		return
	end
	local hum = player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local driving = seat ~= nil and seat.Name == "DriverSeat"
	local away = driftZoneAway(root.Position)
	if not drift.hinted and away < K.DRIFT_NEAR then
		drift.hinted = true
		NotifyController.Show(NotifyController.Messages.DriftZoneNear
			or "Drift zone ahead! Slide your car sideways on the pad to earn cash.", C.Purple, "info")
	end
	-- The server's word when it gives one (InDriftZone), else our own check: the how-to must show even
	-- if that attribute is late.
	local inZone = player:GetAttribute("InDriftZone") == true or (driving and away == 0)
	if inZone ~= drift.inZone then
		local t = os.clock()
		drift.inZone = inZone
		if not inZone then
			drift.leftAt = t
		else
			drift.enteredAt = t
			if not drift.scored then
				drift.teachUntil = math.huge -- until the first paid chain
			elseif t - drift.leftAt > K.REVISIT_AFTER then
				-- A real new visit, not a slide that crossed the pad's edge and came back: a short reminder.
				drift.teachUntil = t + K.TEACH_SECONDS
			end
		end
	end
	if drift.inZone or drift.chain or drift.stampOn then
		placeDrift()
	end
	driftView()
end

-- Shifts ---------------------------------------------------------------------------------------------

-- The road route to the pick-up or the drop-off: GPSClient's target (dashes along the roads, the line and
-- the star on the minimap). The owner, on a taxi shift: "it says go pick up so-and-so, I don't know where
-- she is": a light beam alone gets lost among the towers. Dropped again only while it is still ours (the
-- player may have set the phone's GPS to somewhere else since).
local function routeJob()
	if job and job.pos and type(GPSClient.SetTarget) == "function" then
		local label = job.stage == "pickup" and (job.courier and ("Pick-up: " .. tostring(job.name)) or ("Pick up " .. tostring(job.name)))
			or (job.courier and "Deliver the package" or ("Drop off " .. tostring(job.name)))
		GPSClient.SetTarget(label, job.pos)
		job.routed = job.pos
	end
end
local function unrouteJob(old)
	if old and old.routed and GPSClient.TargetPos() == old.routed then
		GPSClient.Clear()
	end
end

local function onJob(kind, d)
	local courier = d.Kind == "Courier"
	if kind == "Pickup" then
		unrouteJob(job)
		job = { stage = "pickup", pos = d.Pos, name = d.Name, courier = courier }
		routeJob()
		NotifyController.Show(courier and ("COURIER: pick up a package from " .. d.Name .. ". Follow the route!")
			or ("TAXI: " .. d.Name .. " needs a ride. Follow the route!"), nil, "info")
	elseif kind == "Dropoff" then
		unrouteJob(job)
		job = { stage = "dropoff", pos = d.Pos, name = d.Name, est = d.Est, since = os.clock(), courier = courier }
		routeJob()
		NotifyController.Show(courier and "Package loaded! Deliver it fast for a bonus."
			or (d.Name .. " hopped in. Get them there fast for a tip!"), C.Gold, "info")
	elseif kind == "Paid" then
		unrouteJob(job)
		if job then
			job.stage, job.pos, job.routed = "waiting", nil, nil
		end
		-- Green: cash in the wallet. The kind of shift on top, the pay and XP as the reward line (JobService
		-- reports every fare as TaxiFare XP), why it is more under it.
		HUDController.Stamp(courier and "DELIVERED" or "FARE PAID", d.Tip > 0 and (courier and "Fast bonus" or "Tip included") or nil,
			C.Cash, courier and "COURIER" or "TAXI", { Cash = d.Pay, XP = Progression.XP.TaxiFare })
	elseif kind == "Ended" then
		unrouteJob(job)
		job = nil
		local why = { LeftCar = "Shift over: you left your car.", Wanted = "Shift over: you're wanted!", Player = "Shift over.", NoFares = "No fares right now." }
		local trouble = d.Reason == "LeftCar" or d.Reason == "Wanted" -- (orange: it ended on you; else just news)
		NotifyController.Show((why[d.Reason] or "Shift over.") .. string.format(" %d fares, %s earned.", d.Fares, HUDController.Money(d.Earned)),
			trouble and C.Orange or nil, trouble and "warning" or "info")
	end
	showCheckpoint()
end

-- Five times a second: END SHIFT in its slot, and the shift's line (each label is only written when
-- its words change).
local function updateJobUI()
	local active = job ~= nil
	ui.endShiftButton.Visible = active
	if active then
		-- The side column under the HUD's Buttons zone (LawClient.SideSlot), after LEAVE HOME / WARDROBE.
		local pos, size = LawClient.SideSlot(ui.gui, LawClient.PlaceSlots(), Theme.IsTouch())
		ui.endShiftButton.AnchorPoint = Vector2.zero
		ui.endShiftButton.Position = UDim2.fromOffset(pos.X, pos.Y)
		ui.endShiftButton.Size = UDim2.fromOffset(size.X, size.Y)
	end
	local touch = ui.jobTouch == true
	local lineOn = active and job.pos ~= nil and not current and player:GetAttribute("TitleScreen") ~= true
	if lineOn then
		-- A phone's Stamp zone reaches up into the Banner zone: FARE PAID and the rest get the room.
		local stampTop = stampBand()
		if stampTop then
			local view = ui.gui.AbsoluteSize
			local _, y, _, h = zoneBox("Banner", touch, view.X, view.Y)
			lineOn = stampTop >= y + h
		end
	end
	if ui.job.Visible ~= lineOn then
		ui.job.Visible = lineOn
	end
	if not lineOn then
		return
	end
	local root = rootPart()
	local dist = root and GPSClient.FormatDistance((flat(root.Position) - flat(job.pos)).Magnitude) or ""
	local name = string.upper(tostring(job.name or ""))
	local words, bonus
	if job.stage == "pickup" then
		words = (job.courier and "PICK UP AT " or "PICK UP ") .. name
	else
		words = job.courier and "DELIVER THE PACKAGE" or ("DROP OFF " .. name)
		local left = job.est and math.max(0, math.floor(job.est - (os.clock() - job.since))) or 0
		if left > 0 then
			-- Seconds left to earn the tip (a fare) or the fast bonus (a package). Phones: the seconds alone.
			bonus = touch and (left .. "s") or ((job.courier and "BONUS " or "TIP ") .. left .. "s")
		end
	end
	-- (names come from the config: keep "&" and "<" from being read as rich text)
	words = string.gsub(string.gsub(words, "&", "&amp;"), "<", "&lt;")
	-- A gold Display tag, then the words; a phone has room for the words alone, so they are the gold ones.
	local gold = K.HEX_GOLD
	local title
	if touch then
		title = string.format('<font face="Oswald" weight="bold" size="15" color="#%s">%s</font>', gold, words)
	else
		title = string.format('<font face="Oswald" weight="bold" size="16" color="#%s">%s</font>   %s', gold,
			job.courier and "COURIER" or "TAXI", words)
	end
	if ui.jobTitle.Text ~= title then
		ui.jobTitle.Text = title
	end
	if ui.jobDist.Text ~= dist then
		ui.jobDist.Text = dist
	end
	if ui.jobBonus.Visible ~= (bonus ~= nil) then
		ui.jobBonus.Visible = bonus ~= nil
	end
	if bonus and ui.jobBonus.Text ~= bonus then
		ui.jobBonus.Text = bonus
	end
	-- The words get all the room the distance (and the seconds, while they show) leave.
	local taken = 16 + 8 + (ui.jobDistW or K.JOB_DIST_W) + 10 + (bonus and ((ui.jobBonusW or K.JOB_BONUS_W) + 6) or 0)
	if ui.jobTitle.Size.X.Offset ~= -taken then
		ui.jobTitle.Size = UDim2.new(1, -taken, 1, 0)
	end
end

-- A BEST TIMES board over each race start pad (local-only; placed from Config.Activities, so it
-- doesn't depend on the pad being streamed in). It shares the pad label's anchor and is pushed a
-- little over a board's height off it, so the two never overlap at any distance. A flat dark panel:
-- the title in gold Display over a thin rule, the race's facts (checkpoints, par, full reward: on a
-- narrow phone the preview card can't show them), then the five best: place and name on the left,
-- the time in Display on the right, the leader in gold.
local function buildBoards()
	local playerGui = player:WaitForChild("PlayerGui")
	for _, race in ipairs(Activities.Races) do
		local anchor = Instance.new("Part")
		anchor.Name = "RaceBoardAnchor"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.CFrame = CFrame.new(race.Start.X, race.Boat and -1.4 or 0.24, race.Start.Z) -- the pad's centre
		anchor.Parent = Workspace.CurrentCamera
		local board = Instance.new("BillboardGui")
		board.Name = "RaceBoard_" .. race.Id
		board.Adornee = anchor
		board.ResetOnSpawn = false
		board.Size = UDim2.fromOffset(K.BOARD_W, K.BOARD_H)
		board.StudsOffset = Vector3.new(0, 14, 0) -- the pad's "RACE: name" label sits here (40 px tall)
		board.SizeOffset = Vector2.new(0, -(0.5 + 24 / K.BOARD_H)) -- shift a board's height + 24 px off it
		board.MaxDistance = 250
		board.LightInfluence = 0 -- (as bright at night as by day)
		local bg = Instance.new("Frame")
		bg.Name = "Panel"
		bg.Size = UDim2.fromScale(1, 1)
		Theme.Panel(bg, 0.3)
		bg.Parent = board
		-- One line of the board: Theme text in a box `right` px short of the board's right edge.
		local function line(name, y, h, size, kind, color, align, right)
			local l = Instance.new("TextLabel")
			l.Name = name
			l.Position = UDim2.fromOffset(8, y)
			l.Size = UDim2.new(1, -(8 + right), 0, h)
			l.Text = ""
			Theme.Text(l, size, kind)
			l.TextColor3 = color
			l.TextXAlignment = align
			l.TextTruncate = Enum.TextTruncate.AtEnd
			l.Parent = bg
			return l
		end
		local title = line("Title", 4, 22, 19, "Display", C.Gold, Enum.TextXAlignment.Center, 8)
		title.Text = "BEST TIMES"
		local rule = Instance.new("Frame")
		rule.Name = "Rule"
		rule.AnchorPoint = Vector2.new(0.5, 0)
		rule.Position = UDim2.new(0.5, 0, 0, 28)
		rule.Size = UDim2.fromOffset(44, 2)
		rule.BackgroundColor3 = C.Gold
		rule.BorderSizePixel = 0
		rule.Parent = bg
		local facts = line("Facts", 33, 15, 13, "Bold", C.Dim, Enum.TextXAlignment.Center, 8)
		local laps = race.Laps or 1
		facts.Text = string.format("%s  ·  PAR %s  ·  %s", laps > 1 and (laps .. " LAPS") or (#race.Checkpoints .. " CP"),
			clock(race.Par), HUDController.Money(race.Reward + race.ParBonus))
		local rows = {} -- [i] = { name, time }
		for i = 1, 5 do
			local y = 51 + (i - 1) * 16
			local color = i == 1 and C.Gold or C.Text
			rows[i] = {
				name = line("Name" .. i, y, 16, 13, "Body", color, Enum.TextXAlignment.Left, 66),
				time = line("Time" .. i, y, 16, 15, "Display", color, Enum.TextXAlignment.Right, 8),
			}
		end
		local key = "RaceBoard_" .. race.Id
		local function refresh()
			local ok, list = pcall(function()
				return HttpService:JSONDecode(ReplicatedStorage:GetAttribute(key) or "[]")
			end)
			list = ok and type(list) == "table" and list or {}
			for i, r in ipairs(rows) do
				local e = list[i]
				if type(e) == "table" and type(e.time) == "number" then
					r.name.Text = string.format("%d  %s", i, tostring(e.name or "?"))
					r.time.Text = fmt(e.time)
				else
					r.name.Text = (i == 1 and #list == 0) and "No times yet" or ""
					r.time.Text = ""
				end
			end
		end
		refresh()
		ReplicatedStorage:GetAttributeChangedSignal(key):Connect(refresh)
		board.Parent = playerGui
	end
end

function ActivityClient.Init()
	build()
	buildBoards()
	placeHud()
	ui.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeHud)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(placeHud)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(placeHud)
	ui.endShiftButton = Instance.new("TextButton")
	ui.endShiftButton.Name = "EndShift"
	ui.endShiftButton.Size = UDim2.fromOffset(52, 52)
	Theme.Button(ui.endShiftButton, "Quiet")
	ui.endShiftButton.FontFace = Theme.Font.Display
	ui.endShiftButton.TextSize = 13
	ui.endShiftButton.TextWrapped = true
	ui.endShiftButton.TextColor3 = Theme.Color.Gold
	ui.endShiftButton.Text = "END SHIFT"
	ui.endShiftButton.Visible = false
	ui.endShiftButton.Parent = ui.gui
	ui.endShiftButton.Activated:Connect(function()
		Remotes.Event("RequestJob"):FireServer("End")
	end)
	-- Race challenges: the card's own ScreenGui over the HUD (like CrewClient's invite), CHALLENGE and its
	-- key (K on a keyboard, R3 on a gamepad: neither is bound anywhere else), REMATCH.
	ui.inviteGui = Instance.new("ScreenGui")
	ui.inviteGui.Name = "RaceChallenge"
	ui.inviteGui.ResetOnSpawn = false
	ui.inviteGui.IgnoreGuiInset = true -- (the zone map's coordinates)
	ui.inviteGui.DisplayOrder = 8
	ui.inviteGui.Parent = player:WaitForChild("PlayerGui")
	ui.inviteGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitInvite)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(fitInvite)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(fitInvite)
	ui.challenge.Activated:Connect(sendChallenge)
	ui.rematch.Activated:Connect(pressRematch)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return -- (typing in the chat, a text box)
		end
		if (input.KeyCode == K.CHALLENGE_KEY or input.KeyCode == K.CHALLENGE_PAD) and ui.challenge.Visible then
			sendChallenge()
		end
	end)
	Remotes.OnClient("JobEvent", onJob)
	Remotes.OnClient("RaceEvent", onRace)
	Remotes.OnClient("StuntEvent", onStunt)
	Remotes.OnClient("DriftEvent", onDrift)
	for _, attribute in ipairs({ "DriftScore", "DriftCombo", "DriftCash" }) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			safely("drift score", refreshDrift)
		end)
	end
	UserInputService.LastInputTypeChanged:Connect(refreshDriftKeys)
	task.spawn(function()
		while true do
			task.wait(0.2)
			safely("shift line", updateJobUI)
			safely("route preview", previewTick)
			safely("race lobby", lobbyTick)
			safely("race standings", standingsTick)
			safely("race challenge", challengeTick)
			safely("challenge card", inviteTick)
			safely("drift zone", driftTick)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			safely("race guide", guideTick)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not current then
			return
		end
		local t = now()
		if t < current.startAt then
			setBig(tostring(math.ceil(current.startAt - t)))
			ui.timerLabel.Text = fmt(0)
		else
			local since = t - current.startAt
			if since < K.GO_SHOW then
				setBig("GO")
			elseif since < K.GO_SHOW + K.FADE.Time + 0.05 then
				fadeBig()
			elseif ui.big.Visible then
				ui.big.Visible = false
			end
			ui.timerLabel.Text = fmt(since)
		end
		if arrow.on then
			local c = os.clock()
			if arrow.count == 1 then
				placeArrow((c * 1.1 % 1) * 6 - 3) -- one chevron slides the way to go, over and over
			else
				-- Two or three light up one after another, tail to tip, toward the turn.
				local lit = math.floor(c * 5) % arrow.count + 1
				if lit ~= arrow.lit then
					lightArrow(lit)
				end
			end
		end
	end)
end

return ActivityClient
