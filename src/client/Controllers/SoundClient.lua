-- SoundClient (ModuleScript, StarterPlayerScripts.Controllers.SoundClient)
-- Everything you hear (IDs in Config.Sounds). All sounds are created locally on this device.
--   SoundClient.Play(name, where, volumeScale, maxLife)  one-shot: where = nil (flat), a Vector3 or a
--     BasePart (3D). maxLife = seconds before it is cut off even if still sounding (default and cap 12;
--     gunfire passes 2 so long echoes can't pile up under rapid fire).
--     Returns the Sound, or nil when nothing played. A key that isn't in Config.Sounds.Effects, or whose
--     Id is 0 (no asset picked yet), plays nothing and warns nothing. The sound cleans itself up as soon
--     as it ends, so callers must not use it after that.
--   SoundClient.Loop(name, where, volumeScale)  a loop that plays until the caller stops it with
--     :Destroy() (a Vector3's hidden attachment goes with it). where and volumeScale work as in Play.
--     Returns the Sound, or nil for a key that isn't there or whose Id is 0: callers must allow for nil.
--     It follows the same volume settings as everything else: the Effects slider, or the Music slider
--     for an effect with Group = "Music" (HeistMusic; the car radio ducks to CUE.RADIO_DUCK under one).
--     A loop on a BasePart ends when the part goes.
--   SoundClient.PreviewExhaust(key)  a short flat rev of one exhaust style (PhoneUI's TUNE page). A style
--     with one gear (Whisper) previews as one long climb, the way it sounds in the car.
--   * Engines: every driven car (players and AI) within Config.Sounds.Engine.MaxDistance of the camera
--     has one engine loop, pitched like a rev counter: it idles with a lumpy burble at rest (mostly in
--     loudness), jumps up when the gas goes down at a standstill (a launch), climbs through its gears
--     with a small drop at each shift, and is louder on the gas than coasting or braking. Reverse is one
--     whining gear that never shifts.
--     Your own car reads the real throttle (DriveController.Status.Throttle if it exists, else the
--     pedals / seat); other cars are judged by how their speed changes.
--     The car attribute "Exhaust" (a key of Config.Sounds.Exhausts, nil = Stock; GarageService sets it)
--     picks the voice: pitch range, volume, equalizer and distortion. Change it and the sound follows.
--     Boats (car attribute Boat) have no gears: the motor just revs with the speed.
--   * Sirens: AI patrols that are chasing someone, and player cop cars with the siren on (H).
--   * Horn: civilians press H; everyone nearby hears it (car attribute HonkAt, VehicleService).
--   * Your car: tyre squeal when sliding, nitro whoosh, door thunk, splash when it sinks.
--     Nitro: one whoosh per boost, started from the top when the boost starts and faded out over
--     NITRO.FADE when it ends (tank empty or button let go), never cut; a press on an empty tank (or
--     holding on once it runs dry) gives one dull click (Effects.NitroEmpty), nothing more. (Before: a new
--     3.6 s whoosh every other frame while nitro was held on an empty tank, layered into a roar.)
--   * Heist alarms ring at a site while its AlarmUntil time runs.
--   * Rain and thunder in storms; surf and gulls at the beach; a city hum downtown (rain, thunder,
--     surf, gulls and city go quiet inside a home, player attribute InHome).
--   * Car radio: three stations (Config.Sounds.Radio) while you drive. The radio row "RadioRow" (44 px
--     tall, centred on the slot) lives in DriveUI.RadioSlot (CarCluster, right above the speed readout).
--     (Only if DriveUI ever fails to give us a slot does it go in our own ScreenGui "Radio", frame
--     "RadioSlot", at bottom centre, 150 px up or higher, clear of the speed readout and controls strip.)
--       [«] [station · track] [»] [RADIO OFF]
--       « / »      previous / next station (they also turn the radio back on)
--       RADIO OFF  turns it off; the button then reads RADIO ON
--       V, or D-pad right on a gamepad: Neon FM -> Palm 99 -> Gator Radio -> off. D-pad left goes back.
--       (DriveUI's gamepad controls strip names the D-pad, so pad players know.)
--     Stations are "live": each keeps going while you aren't listening (songs need their Length in
--     Config.Sounds.Radio). Get back in, or come back to a station, and the song has moved on; the first
--     time you tune to one you land somewhere in a song. Changing station gives a short burst of static
--     (Effects.RadioTune) and the music comes up over RADIO_FADE_IN. Getting out, the song plays on from
--     the car for a few seconds, muffled, fading as you walk away (LINGER_*); get back in before it
--     stops and it just carries on.
--     On a narrow slot (DriveUI squeezes it to 180-300 px on 4:3 tablets and older phones) the row
--     drops the track name, scales the station name to fit and stacks "RADIO" over "OFF"; on the very
--     narrowest only the three buttons are left (fitRadioRow).
--     Off sticks: it is remembered for the session, and kept in the settings "RadioOff" / "RadioStation"
--     (SettingsClient) so it follows the player once SettingsService saves those two keys.
--     While a Music loop (HeistMusic, SoundClient.Loop) plays, the radio slides down to CUE.RADIO_DUCK
--     of its level, and back up when it ends.
--     When the station changes, its name fades in big at top centre (ScreenGui "Radio", frame
--     "StationTitle"), stays a moment, then fades out: the name in white Display, a thin rule under it
--     that draws out from the middle (the brand's pink; grey for RADIO OFF) and the track's name under
--     that, straight on the screen with soft shadows. (Also when you get in with the radio on, if there
--     is room and no big stamp is up; never when the music stops because you got out.) The name goes
--     under whatever else is showing at top centre (TITLE.CLEAR: banners, the tutorial pill, the race
--     and drift pieces, the race's finish card, CombatClient's stamp, and HUDController's stamp: the
--     band HUDController.StampTop gives, which is Theme's "Stamp" zone, 164 px tall on a PC and 120 on a
--     phone) and steps further down if one of them appears while it shows; the get-in name just goes
--     away when a stamp appears.
--   * Moments: cash, stamps, cuffs, taser zaps, race beeps (3, 2, 1, GO), UI clicks.
--   * SPOTTED!: a quick double beep when a cop sees you while you're wanted (HeatSpotted turns true),
--     the moment the HUD's LOSING THEM meter snaps back. At most once every 3 s.
--   * Wanted (the Heat attribute): a low hit when a star lights up (Effects.StarUp; not over the title
--     screen or while the save loads in), police radio chatter while you're wanted (Sounds.PoliceChatter:
--     one clip every 9-18 s, never two at once, flat, quiet and squeezed through a radio's equalizer and
--     a little distortion; it stops the moment the heat clears) and a relieved sting (Effects.LostCops)
--     when the heat clears without an arrest, once per chase. An arrest clears the heat a moment before
--     the "Caught" remote and the switch to Prisoner arrive, so the sting waits CUE.LOST_WAIT and checks.
--     Nor when a payout cleared it (banking in the Hideout, the Big Score paying out there): the reward
--     stamp's Passed sting is already playing, so any Cash gain that close to the clear keeps it quiet.
--   * Cash: the register (Effects.CashIn) when your banked Cash goes up by $100 or more (not the save
--     loading in, not on the title screen, at most once every 0.4 s). The coins (Cash) still play for the
--     remote moments in Init.
--   * Played by other controllers through Play / Loop: Failed (the HUD's red stamps), PhoneText,
--     GoldClink, GateOpen, Drill, VaultAlarm and HeistMusic (the Big Score).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Sounds = require(ReplicatedStorage.Shared.Config.Sounds)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)

local player = Players.LocalPlayer

local SoundClient = {}

local DriveController -- required in Init (it never requires us, but DriveUI might one day)

local flat -- folder for 2D sounds
local anchorPart -- invisible anchored part holding one-shot 3D attachments

local function effect(name)
	return Sounds.Effects[name]
end

-- Has a real asset? (Id = 0 marks a key that is still waiting for one.)
local function playable(def)
	return def ~= nil and type(def.Id) == "number" and def.Id > 0
end

local function makeSound(name, id, volume, pitch, looped, parent)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.Looped = looped
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 25
	s.RollOffMaxDistance = 400
	s.SoundGroup = require(script.Parent:WaitForChild("SettingsClient")).Group("Effects")
	s.Parent = parent
	return s
end

local function newSound(name, parent)
	local def = effect(name)
	if not playable(def) then
		return nil
	end
	local s = makeSound(name, def.Id, def.Volume or 0.5, def.Pitch or 1, def.Looped == true, parent)
	if def.Group == "Music" then
		s.SoundGroup = require(script.Parent:WaitForChild("SettingsClient")).Group("Music") -- (score: the Music slider)
	end
	if def.MinDistance then
		s.RollOffMinDistance = def.MinDistance
	end
	if def.MaxDistance then
		s.RollOffMaxDistance = def.MaxDistance
	end
	return s
end

local function ensureFolders()
	if not flat then
		flat = Instance.new("Folder")
		flat.Name = "NCSounds"
		flat.Parent = SoundService
	end
	if not anchorPart or not anchorPart.Parent then
		anchorPart = Instance.new("Part")
		anchorPart.Name = "NCSoundAnchor"
		anchorPart.Anchored = true
		anchorPart.CanCollide = false
		anchorPart.CanQuery = false
		anchorPart.CanTouch = false
		anchorPart.Transparency = 1
		anchorPart.Size = Vector3.new(1, 1, 1)
		anchorPart.CFrame = CFrame.new()
		anchorPart.Parent = Workspace.CurrentCamera
	end
end

local MAX_LIFE = 12 -- seconds: no one-shot outlives this (also the cap on a caller's maxLife)

function SoundClient.Play(name, where, volumeScale, maxLife)
	-- Storms are silent inside a home (SkyClient calls this for each lightning strike).
	if name == "Thunder" and player:GetAttribute("InHome") == true then
		return nil
	end
	-- Checked before anything is created: a key with no asset yet (the gun sounds) is asked for many
	-- times a second and must cost nothing.
	local def = effect(name)
	if not playable(def) then
		return nil
	end
	ensureFolders()
	local parent = flat
	if typeof(where) == "Vector3" then
		local att = Instance.new("Attachment")
		att.WorldPosition = where
		att.Parent = anchorPart
		parent = att
	elseif typeof(where) == "Instance" and where:IsA("BasePart") then
		parent = where
	end
	local s = newSound(name, parent)
	s.Looped = false
	if def.PitchVar then
		s.PlaybackSpeed *= 1 + (math.random() * 2 - 1) * def.PitchVar
	end
	if volumeScale then
		s.Volume *= volumeScale
	end
	s:Play()
	-- Gone as soon as it has finished (rapid fire would pile sounds up otherwise); the timer catches
	-- sounds that were stopped early or never loaded. A caller may cut it shorter with maxLife: an SMG
	-- fires 12 times a second, and a shot's 3 s echo would otherwise keep dozens of Sounds alive.
	local life = MAX_LIFE
	if type(maxLife) == "number" and maxLife > 0 then -- (NaN fails the > 0 test too)
		life = math.min(maxLife, MAX_LIFE)
	end
	local cleaned = false
	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true
		s:Destroy()
		if parent ~= flat and parent ~= where and parent.Parent then
			parent:Destroy()
		end
	end
	s.Ended:Once(cleanup)
	task.delay(life, cleanup)
	return s
end

-- The chase, money and score cues (see the header). Their settings are fields of CUE and their state
-- fields of `cue`, not locals of their own: the top level of a script is one Luau function, a function
-- holds at most 200 locals, and this file has well over 100.
local CUE = {
	STAR_LIFE = 3, -- the wanted-star hit is cut off after this long (Play's maxLife)
	STAR_GAP = 0.5, -- seconds: stars that come in a burst make one hit, not a stutter
	LOST_WAIT = 1.2, -- seconds after the heat clears before LostCops (an arrest shows itself by then)
	CASH_MIN = 100, -- dollars: smaller gains stay quiet
	CASH_GAP = 0.4, -- seconds: at most one register this often
	CHATTER_VOLUME = 0.35, -- police radio clips (Sounds.PoliceChatter), flat
	CHATTER_GAP = { 9, 18 }, -- seconds from the start of one clip to the start of the next (random in between)
	CHATTER_FIRST = 2.5, -- seconds from the first star to the first clip (the StarUp hit goes first)
	CHATTER_EQ = { -30, 3, -22 }, -- low, mid, high gains (dB): the thin middle band a radio speaker has
	CHATTER_GRIT = 0.22, -- DistortionSoundEffect.Level on the clips: a light crackle
	RADIO_DUCK = 0.3, -- the car radio plays at this share of its level while a Music loop is on...
	DUCK_SPEED = 2, -- ...sliding there and back at this rate (per second)
}
local cue = {
	heat = 0, -- the Heat attribute as last seen
	chase = false, -- a chase is on and its LostCops sting hasn't been decided yet
	starAt = -math.huge, -- os.clock() of the last StarUp
	caughtAt = -math.huge, -- os.clock() of the last "Caught" remote
	paidAt = -math.huge, -- os.clock() of the last rise in Cash (a payout's stamp plays its own sting)
	cash = nil, -- the Cash attribute as last seen
	cashAt = -math.huge, -- os.clock() of the last CashIn
	chatter = nil, -- the police radio clip playing now
	chatterAt = 0, -- os.clock() when the next clip may start
	chatterLast = nil, -- index of the last clip in Sounds.PoliceChatter (not played twice in a row)
	music = {}, -- [Sound] = true: the Music-group loops made by Loop (the car radio ducks under them)
	duck = 1, -- the share of its level the car radio plays at now
}

-- (see the header) A loop for as long as the caller wants it.
function SoundClient.Loop(name, where, volumeScale)
	local def = effect(name)
	if not playable(def) then
		return nil
	end
	ensureFolders()
	local parent = flat
	local att
	if typeof(where) == "Vector3" then
		att = Instance.new("Attachment")
		att.Name = name
		att.WorldPosition = where
		att.Parent = anchorPart
		parent = att
	elseif typeof(where) == "Instance" and where:IsA("BasePart") then
		parent = where
	end
	local s = newSound(name, parent)
	s.Looped = true
	if volumeScale then
		s.Volume *= volumeScale
	end
	if def.Group == "Music" then
		cue.music[s] = true
	end
	-- Callers only ever destroy the Sound: its attachment and its place in cue.music go with it.
	s.Destroying:Once(function()
		cue.music[s] = nil
		if att then
			task.defer(att.Destroy, att)
		end
	end)
	s:Play()
	return s
end

-- Is a Music loop from Loop playing? (One that has gone without being destroyed is forgotten here.)
local function musicLoopOn()
	for s in pairs(cue.music) do
		if not s.Parent then
			cue.music[s] = nil
		elseif s.IsPlaying then
			return true
		end
	end
	return false
end

------------------------------------------------------------------ cars: engines, sirens, horns

local ENGINE = Sounds.Engine
local EXHAUSTS = Sounds.Exhausts
local SHIFT_TIME = math.max(ENGINE.ShiftTime, 0.01)
local REVERSE_AT = 2 -- studs/s backwards before the engine counts as in reverse
-- The idle burble (Lope) moves the loudness by LOPE_VOLUME times Lope and the pitch by only LOPE_PITCH
-- times: a lumpy idle pulses, it doesn't warble like a stretched tape.
local LOPE_VOLUME = 4
local LOPE_PITCH = 0.3

-- [car] = { honkConn, siren, engine, built, exhaustRaw, def, gears, tops, accelRef, phase,
--           running, gear, rpm, load, accel, lastSpeed, shift }
-- Strong keys on purpose: Roblox may collect a car's Lua handle while the car still exists, and a weak
-- entry would then vanish with its engine still playing and its horn still hooked up. carAudio drops
-- an entry (and stops its sounds) as soon as the car is gone or has lost its chassis.
local tracked = {}
local gearTops = {} -- [number of gears] = { share of top speed where each gear ends }

local function topsFor(n)
	local tops = gearTops[n]
	if not tops then
		tops = {}
		for g = 1, n do
			tops[g] = (g / n) ^ ENGINE.GearCurve
		end
		gearTops[n] = tops
	end
	return tops
end

local function exhaustDef(key)
	return (type(key) == "string" and EXHAUSTS[key]) or EXHAUSTS.Stock
end

-- One engine loop wearing an exhaust style: the style's own asset if it has one, else the shared
-- EngineLoop, shaped by an equalizer and distortion (only made when the style needs them).
local function engineSound(def, parent)
	local id = def.Id
	if type(id) ~= "number" or id <= 0 then
		local base = effect("EngineLoop")
		id = base and base.Id
	end
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	local s = makeSound("Engine", id, 0, def.Pitch, true, parent)
	s.RollOffMaxDistance = ENGINE.MaxDistance
	local grit = def.Distortion or 0
	if grit > 0 then
		local fx = Instance.new("DistortionSoundEffect")
		fx.Level = math.clamp(grit, 0, 1)
		fx.Priority = 1 -- before the equalizer, so the equalizer shapes the gritty sound too
		fx.Parent = s
	end
	local eq = def.Eq
	if eq then
		local low, mid, high = eq.Low or eq[1] or 0, eq.Mid or eq[2] or 0, eq.High or eq[3] or 0
		if low ~= 0 or mid ~= 0 or high ~= 0 then
			local fx = Instance.new("EqualizerSoundEffect")
			fx.LowGain = math.clamp(low, -80, 10)
			fx.MidGain = math.clamp(mid, -80, 10)
			fx.HighGain = math.clamp(high, -80, 10)
			fx.Priority = 0
			fx.Parent = s
		end
	end
	return s
end

-- (Re)make a car's engine for the exhaust it has now. The old sound goes, effects and all.
local function buildEngine(car, rec, chassis, raw)
	if rec.engine then
		rec.engine:Destroy()
	end
	local def = exhaustDef(raw)
	rec.built = true
	rec.exhaustRaw = raw
	rec.def = def
	rec.engine = def and engineSound(def, chassis) or nil
	rec.running = false
	if def then
		local n = math.clamp(math.floor(def.Gears or ENGINE.Gears), 1, 8)
		if car:GetAttribute("Boat") == true then
			n = 1 -- a boat motor just revs with its speed: no gear changes (and boats can't be tuned out of them)
		end
		rec.gears = n
		rec.tops = topsFor(n)
	end
	-- Gaining speed at half the car's full acceleration already counts as "foot down".
	rec.accelRef = math.max((car:GetAttribute("Accel") or 40) * 0.5, 1)
end

-- Revs (0 = idle, 1 = flat out in top gear) at speed share f in a gear. Each gear starts ShiftDrop
-- under where the last one ended and ends a little higher than the last, so the note climbs overall.
local function revsIn(gear, n, tops, f)
	local lo = gear > 1 and tops[gear - 1] or 0
	local hi = tops[gear]
	local top = 1 - (n - gear) * ENGINE.GearStep
	local bottom = gear > 1 and (top - ENGINE.GearStep - ENGINE.ShiftDrop) or 0
	return math.max(0, bottom + (top - bottom) * math.min((f - lo) / (hi - lo), 1.3))
end

-- Your own car's gas pedal (-1..1), or nil when this device can't tell. DriveController.Status.Throttle
-- is the real one if DriveController publishes it; else the phone pedals, else the seat.
local function ownThrottle(status, car)
	local t = status.Throttle
	if type(t) == "number" then
		return t
	end
	t = DriveController.Input.Throttle
	if type(t) == "number" then
		return t
	end
	local seat = car:FindFirstChild("DriverSeat")
	if seat and seat:IsA("VehicleSeat") and seat.ThrottleFloat ~= 0 then
		return seat.ThrottleFloat
	end
	return nil -- a seat reading 0 may just be a seat the control scripts missed: judge by speed instead
end

-- One step of a running engine. own = DriveController.Status for the car you are driving, else nil.
local function engineStep(car, rec, chassis, dt, now, own)
	local engine, def = rec.engine, rec.def
	local n, tops = rec.gears, rec.tops
	local vel = chassis.AssemblyLinearVelocity
	local speed = vel.Magnitude
	local f = math.min(speed / math.max(car:GetAttribute("MaxSpeed") or 150, 1), 1.3)
	-- Reverse is one gear: the note climbs with the reverse speed (to first gear's top) and never
	-- shifts. (The same nose-vs-motion test as CarPhysics' FwdSpeed, so it works for every car.)
	-- A motor with one gear (Whisper, boats) has nothing to change: it revs with its speed either way,
	-- and squeezing its whole range into the slow reverse speed would make it scream going backwards.
	local reversing = n > 1 and chassis.CFrame.LookVector:Dot(vel) < -REVERSE_AT
	if reversing then
		f = math.min(speed / math.max(car:GetAttribute("ReverseSpeed") or 40, 1), 1) * tops[1]
	end

	if not rec.running then
		-- Just came into earshot (or got a driver): start in the right gear, with no rev sweep.
		rec.running = true
		rec.lastSpeed, rec.accel, rec.load, rec.shift = speed, 0, 0.25, 0
		local g = 1
		while g < n and f > tops[g] do
			g += 1
		end
		rec.gear = g
		rec.rpm = revsIn(g, n, tops, f)
	end

	-- Gears: up at the top of a gear, down a little under the bottom (so it can't flutter between two).
	local gear = rec.gear
	if reversing then
		gear = 1 -- (straight in, with no shift dip: nobody hears the box go into reverse)
		rec.gear = 1
	elseif gear < n and f > tops[gear] then
		gear += 1
		rec.gear = gear
		rec.shift = SHIFT_TIME
	elseif gear > 1 and f < tops[gear - 1] * ENGINE.DownshiftAt then
		gear -= 1
		rec.gear = gear
	end
	local target = revsIn(gear, n, tops, f)
	if gear == 1 and n > 1 then
		-- Gas down off the line: the note jumps up before the car gets going (clutch and wheelspin), the
		-- rev-and-go of a launch. Coasting and braking leave it at idle. (rec.load is last frame's.)
		target = math.max(target, (ENGINE.Launch or 0.5) * math.max(0, rec.load - 0.35))
	end
	rec.rpm += (target - rec.rpm) * math.min(1, dt * ENGINE.Response)
	rec.shift = math.max(0, rec.shift - dt)

	-- Load: how hard the engine is working (0 = braking, a little = coasting, 1 = foot down).
	local accel = (speed - rec.lastSpeed) / dt
	rec.lastSpeed = speed
	rec.accel += (accel - rec.accel) * math.min(1, dt * 6)
	local load
	local throttle = own and ownThrottle(own, car) or nil
	if throttle then
		local fwd = own.Speed
		if own.NitroActive then
			load = 1
		elseif math.abs(throttle) < 0.05 then
			load = 0.12 -- coasting
		elseif (throttle > 0) == (fwd >= 0) or math.abs(fwd) < 3 then
			load = 0.35 + 0.65 * math.min(math.abs(throttle), 1) -- pulling the way it is going
		else
			load = 0 -- pedal against the motion: braking
		end
	else
		-- Other cars: holding a high speed needs gas, gaining speed needs more, losing speed needs none.
		load = math.clamp(0.25 + 0.45 * f + rec.accel / rec.accelRef, 0, 1)
	end
	rec.load += (load - rec.load) * math.min(1, dt * 8)

	-- Voice: pitch from the revs (a touch higher under load), with a burble at idle. The burble is two
	-- beats that drift against each other, so it lopes unevenly instead of ticking like a metronome.
	local rpm = rec.rpm
	local pitch = def.Pitch + def.PitchRange * (rpm + 0.04 * rec.load)
	local wob = (def.Lope or ENGINE.Lope) * math.max(0, 1 - rpm * 3)
	if wob > 0 then
		wob *= 0.7 * math.sin(now * 13 + rec.phase) + 0.3 * math.sin(now * 5.1 + rec.phase * 2)
		pitch *= 1 + wob * LOPE_PITCH
	end
	engine.PlaybackSpeed = pitch
	local idle = def.Idle or ENGINE.Idle
	local body = idle + (1 - idle) * (0.4 * math.min(rpm, 1) + 0.6 * rec.load)
	engine.Volume = def.Volume * body * (1 + wob * LOPE_VOLUME) * (1 - ENGINE.ShiftDip * rec.shift / SHIFT_TIME)
	if not engine.IsPlaying then
		engine:Play()
	end
end

local function trackCar(car)
	local chassis = car.PrimaryPart
	if tracked[car] or not chassis then
		return
	end
	-- The engine is made the first time the car is driven within earshot (carAudio): parked cars and
	-- cars far away cost nothing.
	local rec = { built = false, running = false, phase = math.random() * 6.28 }
	if car:GetAttribute("Police") then
		rec.siren = newSound("Siren", chassis)
		if rec.siren then
			rec.siren.RollOffMaxDistance = 700
		end
	end
	rec.honkConn = car:GetAttributeChangedSignal("HonkAt"):Connect(function()
		SoundClient.Play("Horn", chassis)
	end)
	tracked[car] = rec
end

local function updateCars()
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return
	end
	for _, car in ipairs(vehicles:GetChildren()) do
		if car:IsA("Model") and car.PrimaryPart then
			trackCar(car)
		end
	end
end

local function carAudio(dt, now)
	dt = math.max(dt, 1 / 240)
	local camPos = Workspace.CurrentCamera.CFrame.Position
	local status = DriveController.Status
	local ownCar = status.Driving and status.Car or nil
	for car, rec in pairs(tracked) do
		local chassis = car.PrimaryPart
		if not car.Parent or not chassis then
			if rec.honkConn then
				rec.honkConn:Disconnect()
			end
			if rec.engine then
				rec.engine:Destroy()
			end
			if rec.siren then
				rec.siren:Destroy()
			end
			tracked[car] = nil
			continue
		end
		local driven = car:GetAttribute("DriverUserId") ~= nil or car:GetAttribute("AIPolice") == true
		if driven and (chassis.Position - camPos).Magnitude < ENGINE.MaxDistance then
			local raw = car:GetAttribute("Exhaust")
			if not rec.built or rec.exhaustRaw ~= raw or (rec.engine and rec.engine.Parent ~= chassis) then
				buildEngine(car, rec, chassis, raw) -- first drive, a new exhaust, or a new chassis
			end
			if rec.engine then
				engineStep(car, rec, chassis, dt, now, car == ownCar and status or nil)
			end
		elseif rec.running then
			rec.running = false
			if rec.engine then
				rec.engine:Stop()
			end
		end
		if rec.siren then
			local on = car:GetAttribute("Siren") == true or (car:GetAttribute("AIPolice") == true and car:GetAttribute("AITarget") ~= nil)
			if on and not rec.siren.IsPlaying then
				rec.siren:Play()
			elseif not on and rec.siren.IsPlaying then
				rec.siren:Stop()
			end
		end
	end
end

-- A short rev of one exhaust style, flat (not in the world): idle, up, a shift, up again. For a tuning
-- menu, where the car isn't being driven. A style with one gear (Whisper) never shifts in the car, so
-- its preview is one long climb: the player hears what they are buying. A new preview cuts the last off.
local PREVIEW_SECONDS = 2.4
local previewSound
local previewToken = 0

function SoundClient.PreviewExhaust(key)
	ensureFolders()
	previewToken += 1
	local token = previewToken
	if previewSound then
		previewSound:Destroy()
		previewSound = nil
	end
	local def = exhaustDef(key)
	local s = def and engineSound(def, flat)
	if not s then
		return
	end
	previewSound = s
	s:Play()
	local geared = math.floor(def.Gears or ENGINE.Gears) > 1 -- (the same rounding as buildEngine)
	local idle = def.Idle or ENGINE.Idle
	task.spawn(function()
		local t0 = os.clock()
		while previewToken == token do
			local t = (os.clock() - t0) / PREVIEW_SECONDS
			if t >= 1 then
				break
			end
			local rpm
			if t < 0.15 then
				rpm = 0 -- idle
			elseif not geared then
				rpm = (t - 0.15) / 0.85 -- one long climb, like the car
			elseif t < 0.5 then
				rpm = (t - 0.15) / 0.35 * 0.85
			elseif t < 0.56 then
				rpm = 0.85 - (t - 0.5) / 0.06 * ENGINE.ShiftDrop
			else
				rpm = 0.85 - ENGINE.ShiftDrop + (t - 0.56) / 0.44 * (0.15 + ENGINE.ShiftDrop)
			end
			s.PlaybackSpeed = def.Pitch + def.PitchRange * rpm
			-- As loud as the car would be: idle with no gas, then foot down (engineStep's body). Fades out
			-- over the last fifth so it doesn't end with a click.
			local body = t < 0.15 and idle or idle + (1 - idle) * (0.4 * rpm + 0.6)
			s.Volume = def.Volume * body * math.clamp((1 - t) * 5, 0, 1)
			task.wait()
		end
		if previewToken == token then
			previewSound = nil
		end
		s:Destroy()
	end)
end

------------------------------------------------------------------ your own car

local skid, lastNitro, lastSeat, sankFor = nil, false, nil, 0
-- The boost whoosh (see the header): its Sound while one plays, whether it is fading, and whether the
-- tank was empty under the button last frame. (One table: this file's top level is near the locals cap.)
local NITRO = { FADE = 0.35, sound = nil, fading = false, empty = false }

local function nitroAudio(active, chassis, dt)
	local def = effect("Nitro")
	local full = def and def.Volume or 0.6
	local s = NITRO.sound
	if s and (s.Parent == nil or s.Parent ~= chassis) then
		s:Destroy() -- another car now (or ours went): a fresh one next boost
		s, NITRO.sound, NITRO.fading = nil, nil, false
	end
	if active and not lastNitro and chassis then
		s = s or newSound("Nitro", chassis)
		NITRO.sound = s
		if s then
			s.Looped = false
			s.Volume = full
			s.TimePosition = 0
			s:Play()
		end
		NITRO.fading = false
	elseif not active and lastNitro then
		NITRO.fading = true
	end
	lastNitro = active
	if NITRO.fading and s then
		s.Volume = math.max(0, s.Volume - full * dt / NITRO.FADE)
		if s.Volume <= 0.001 then
			s:Stop()
			NITRO.fading = false
		end
	end
end

local function ownCarAudio(dt)
	local status = DriveController.Status
	local car = status.Driving and status.Car
	local chassis = car and car.PrimaryPart
	-- Tyre squeal: sliding sideways at speed.
	local sliding = false
	if chassis then
		local vel = chassis.AssemblyLinearVelocity
		local side = math.abs(vel:Dot(chassis.CFrame.RightVector))
		sliding = side > 16 and vel.Magnitude > 25
	end
	if sliding then
		if not skid then
			skid = newSound("Skid", chassis)
			if skid then
				skid:Play()
			end
		end
	elseif skid then
		skid:Destroy()
		skid = nil
	end
	-- Nitro: one whoosh per boost (faded out when it ends), one click on an empty tank.
	nitroAudio(status.NitroActive == true and chassis ~= nil, chassis, dt)
	local empty = status.NitroEmpty == true and chassis ~= nil
	if empty and not NITRO.empty then
		SoundClient.Play("NitroEmpty", chassis)
	end
	NITRO.empty = empty
	-- Door thunk getting in or out.
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	if seat ~= lastSeat and (seat and seat.Name == "DriverSeat" or lastSeat and lastSeat.Name == "DriverSeat") then
		SoundClient.Play("Door", (seat or lastSeat))
	end
	lastSeat = seat
	-- Splash when your car hits the water.
	if chassis and chassis.Position.Y < 0.5 then
		sankFor += dt
		if sankFor > 0 and sankFor - dt <= 0 then
			SoundClient.Play("Splash", chassis.Position)
		end
	else
		sankFor = 0
	end
end

------------------------------------------------------------------ heist alarms

local alarms = {} -- [site] = sound

local function updateAlarms()
	local sites = Workspace:FindFirstChild("Heists")
	if not sites then
		return
	end
	local now = Workspace:GetServerTimeNow()
	for _, site in ipairs(sites:GetChildren()) do
		local ringing = (site:GetAttribute("AlarmUntil") or 0) > now
		local s = alarms[site]
		if ringing and not s then
			local part = site:IsA("Model") and (site.PrimaryPart or site:FindFirstChildWhichIsA("BasePart", true)) or site
			if part and part:IsA("BasePart") then
				s = newSound("Alarm", part)
				if s then
					s.RollOffMaxDistance = 500
					s:Play()
					alarms[site] = s
				end
			end
		elseif not ringing and s then
			s:Destroy()
			alarms[site] = nil
		end
	end
end

------------------------------------------------------------------ chase and money cues

-- Police radio chatter while you're wanted: one clip from Sounds.PoliceChatter when it is time and
-- none is playing, flat, quiet and squeezed like a radio. Gone the moment the heat clears.
local function policeChatter(now)
	local playing = cue.chatter
	if playing and not playing.Parent then
		playing = nil -- it ended and cleaned itself up
		cue.chatter = nil
	end
	local wanted = cue.heat > 0 and player:GetAttribute("Side") == "Civilian"
		and player:GetAttribute("TitleScreen") ~= true
	if not wanted then
		if playing then
			playing:Destroy()
			cue.chatter = nil
		end
		return
	end
	local list = Sounds.PoliceChatter
	if playing or now < cue.chatterAt or type(list) ~= "table" then
		return
	end
	cue.chatterAt = now + CUE.CHATTER_GAP[1] + math.random() * (CUE.CHATTER_GAP[2] - CUE.CHATTER_GAP[1])
	-- A random clip that has an asset, not the one played last time (unless it is the only one).
	local pick, count = nil, 0
	for i, clip in ipairs(list) do
		if type(clip) == "table" and playable(clip) and i ~= cue.chatterLast then
			count += 1
			if math.random(count) == 1 then
				pick = i
			end
		end
	end
	local last = cue.chatterLast
	if not pick and last and type(list[last]) == "table" and playable(list[last]) then
		pick = last -- the only clip with an asset
	end
	if not pick then
		return -- no clip has an asset yet
	end
	cue.chatterLast = pick
	local clip = list[pick]
	ensureFolders()
	local s = makeSound("PoliceChatter", clip.Id, CUE.CHATTER_VOLUME * (tonumber(clip.Volume) or 1), 1, false, flat)
	-- A radio speaker: a little crackle, then no lows and no highs (the order engineSound uses).
	local grit = Instance.new("DistortionSoundEffect")
	grit.Level = CUE.CHATTER_GRIT
	grit.Priority = 1
	grit.Parent = s
	local band = Instance.new("EqualizerSoundEffect")
	band.LowGain, band.MidGain, band.HighGain = CUE.CHATTER_EQ[1], CUE.CHATTER_EQ[2], CUE.CHATTER_EQ[3]
	band.Priority = 0
	band.Parent = s
	s:Play()
	cue.chatter = s
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(MAX_LIFE, function()
		s:Destroy() -- (a clip that never loaded, so never ended)
	end)
end

-- StarUp, LostCops and CashIn, from the player's attributes. Init calls this once.
local function hookCues()
	cue.heat = tonumber(player:GetAttribute("Heat")) or 0
	cue.cash = player:GetAttribute("Cash")
	-- DataService sets the saved values just before DataLoaded, so the save loading in only moves the
	-- baselines; nothing plays over the first-join title screen either.
	local function settled()
		return player:GetAttribute("DataLoaded") == true and player:GetAttribute("TitleScreen") ~= true
	end
	player:GetAttributeChangedSignal("Heat"):Connect(function()
		local heat = tonumber(player:GetAttribute("Heat")) or 0
		local before = cue.heat
		cue.heat = heat
		local now = os.clock()
		if heat > before then
			if before <= 0 then
				cue.chase = true -- a new chase: the police radio starts talking shortly (policeChatter)
				cue.chatterAt = now + CUE.CHATTER_FIRST
			end
			if settled() and now - cue.starAt >= CUE.STAR_GAP then
				cue.starAt = now
				SoundClient.Play("StarUp", nil, nil, CUE.STAR_LIFE)
			end
		elseif heat <= 0 and before > 0 then
			-- Cleared. ArrestService clears the heat just before it fires "Caught" and makes you a
			-- Prisoner, so wait a beat, then play it only if it was an escape.
			task.delay(CUE.LOST_WAIT, function()
				if cue.heat > 0 or not cue.chase then
					return -- wanted again already (that chase decides for itself), or decided before
				end
				cue.chase = false
				if player:GetAttribute("Side") ~= "Civilian" or os.clock() - cue.caughtAt < CUE.LOST_WAIT + 2
					or os.clock() - cue.paidAt < CUE.LOST_WAIT + 1 then
					return -- cuffed, switched side (a cop has no heat), or paid (the reward stamp's sting plays)
				end
				SoundClient.Play("LostCops")
			end)
		end
	end)
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		local cash = player:GetAttribute("Cash")
		local before = cue.cash
		cue.cash = cash
		if typeof(cash) == "number" and typeof(before) == "number" and cash > before then
			cue.paidAt = os.clock() -- (a payout that clears the heat gets no LostCops sting)
		end
		if typeof(cash) ~= "number" or typeof(before) ~= "number" or cash - before < CUE.CASH_MIN or not settled() then
			return
		end
		local now = os.clock()
		if now - cue.cashAt >= CUE.CASH_GAP then
			cue.cashAt = now
			SoundClient.Play("CashIn")
		end
	end)
end

------------------------------------------------------------------ weather and ambience

local rain, waves, city
local nextGull = 0

local function ambience()
	local cam = Workspace.CurrentCamera.CFrame.Position
	-- Home interiors are built far out past the beach (HousingService): no rain, surf, gulls or city in there.
	local inHome = player:GetAttribute("InHome") == true
	-- Rain
	local raining = not inHome and Workspace:GetAttribute("Raining") == true
	if raining and not rain.IsPlaying then
		rain:Play()
	elseif not raining and rain.IsPlaying then
		rain:Stop()
	end
	-- Surf: strongest on the beach (x 1100-1600) and Lighthouse Key, fading inland.
	local beach = inHome and 0 or math.clamp((cam.X - 950) / 350, 0, 1)
	if cam.Z > 800 or cam.Z < -2000 then
		beach *= 0.3
	end
	waves.Volume = (effect("Waves").Volume or 0.4) * beach
	if beach > 0.05 and not waves.IsPlaying then
		waves:Play()
	elseif beach <= 0.05 and waves.IsPlaying then
		waves:Stop()
	end
	if beach > 0.5 and os.clock() > nextGull then
		nextGull = os.clock() + math.random(14, 30)
		SoundClient.Play("Seagulls", nil, 0.7)
	end
	-- City hum within ~700 studs of downtown.
	local d = (Vector3.new(cam.X, 0, cam.Z) - Vector3.new(0, 0, -250)).Magnitude
	local c = inHome and 0 or math.clamp(1 - (d - 300) / 400, 0, 1)
	city.Volume = (effect("CityAmbience").Volume or 0.25) * c
	if c > 0.05 and not city.IsPlaying then
		city:Play()
	elseif c <= 0.05 and city.IsPlaying then
		city:Stop()
	end
end

------------------------------------------------------------------ radio

local RADIO_VOLUME = 0.35
local ROW_GAP = 4 -- pixels between the pieces of the radio row
local POWER_WIDTH = 76 -- the RADIO OFF / RADIO ON button
-- DriveUI narrows its cluster (and so our slot) to 180-300 px between the phone's thumbstick and pedals
-- on 4:3 tablets and older phones. Under COMPACT_BELOW the row drops the track name, scales the station
-- name to fit and stacks the power button's two words; under LABEL_MIN the label goes (fitRadioRow).
local COMPACT_BELOW = 260 -- row width (px)
local POWER_COMPACT = 52 -- the power button in a compact row ("RADIO" over "OFF")
local LABEL_MIN = 52 -- narrowest the station label may be (px) before it is left out
local FALLBACK_UP = 150 -- our own slot (DriveUI gave us none): this far above the bottom, or higher (placeFallback)
-- The big station name. Its settings are fields of TITLE and its pieces and state fields of `title`,
-- not locals of their own: the top level of a script is one Luau function, a function holds at most
-- 200 locals, and this file is close to that.
local TITLE = {
	TOP = 146, -- under the one-line banners that live at the very top...
	GAP = 6, -- ...and this far under anything taller or lower that is showing there (titleRoom)
	HALF = 130, -- half the width the name is taken to need, either side of the middle of the screen
	LOWEST = 0.62, -- the name never reaches further down the screen than this share of its height
	RECHECK = 0.25, -- seconds between looks at whether something new has appeared under the name
	IN = 0.15, -- the name fades in over this long...
	SECONDS = 2.5, -- ...is fully shown for this long...
	FADE = 0.6, -- ...then fades out over this long
	RULE = 150, -- pixels: the thin rule under the name...
	RULE_SMALL = 110, -- ...on a phone held sideways...
	RULE_IN = 0.4, -- ...and the seconds it takes to draw out from the middle
	-- Top-centre HUD pieces the station name must never print over (paths under PlayerGui, the way
	-- MinimapClient's KEEP_OUT lists them). A piece that is missing or hidden is skipped.
	-- HUDController's big stamp ("CAR JACKED!", "FARE PAID") has no name to look up: hudStampBand asks it.
	CLEAR = {
		{ "Tutorial", "Next" }, { "Objective", "Banner" }, { "Objective", "Escape" }, { "Mission", "Banner" },
		{ "BigScore", "Goal" }, { "BigScore", "Status" },
		{ "Crew", "CrewInvite" }, { "Offer", "Card" }, { "AreaName", "Card" },
		{ "GPS", "Route" }, { "ActivityUI", "Timer" }, { "ActivityUI", "Checkpoint" }, { "ActivityUI", "Job" },
		{ "ActivityUI", "RacePreview" }, { "ActivityUI", "TurnCue" }, { "ActivityUI", "WrongWay" },
		{ "ActivityUI", "Countdown" }, { "ActivityUI", "Finish" }, { "ActivityUI", "DriftTeach" },
		{ "ActivityUI", "DriftScore" }, { "ActivityUI", "DriftStamp" }, { "CombatHUD", "Stamp" },
	},
}
local RADIO_FADE_IN = 0.35 -- seconds the music takes to come up after a get-in or a station change
local TUNE_LIFE = 0.22 -- the burst of static between stations (Effects.RadioTune) is cut off after this long
-- A station that kept going while nobody listened never starts a song closer to its end than this (a
-- Length in Config.Sounds.Radio may be a little longer than the real song).
local TRACK_TAIL = 8
-- Getting out: the car's radio plays on, muffled (as heard through the car's body), for at most
-- LINGER_SECONDS, fading out over the last LINGER_FADE. It is LINGER_LEVEL as loud as inside within
-- LINGER_NEAR studs of the camera and silent by LINGER_FAR, so walking away fades it out sooner.
local LINGER_SECONDS = 12
local LINGER_FADE = 2
local LINGER_LEVEL = 0.55
local LINGER_NEAR, LINGER_FAR = 12, 45

local radio -- the one music Sound
local radioGui -- our ScreenGui "Radio" (the station name, and the fallback slot)
local radioRow, radioLabel, powerButton, nextButton, labelPad
local rowCompact = nil -- the row is laid out narrow (fitRadioRow); nil = not laid out yet
local fallbackSlot -- our own slot for the row; nil when the row lives in DriveUI.RadioSlot
local fallbackUp = FALLBACK_UP -- how far above the bottom of the screen the fallback slot sits now
-- The station name's pieces (buildRadio sets them): holder (the frame "StationTitle"), label (the name),
-- rule (the thin line under it), sub (the track), shadow, subShadow (their soft edges).
local title = {
	untilAt = nil, -- os.clock() when the station name is gone again (nil = not showing)
	optional = false, -- the name showing now is the get-in one nobody asked for (showTitle)
	y = TITLE.TOP, -- where the station name is now (pixels from the top)
	height = 70, -- how tall it is now (smaller on a phone)
	checkAt = 0, -- os.clock() of the next look for new pieces under it
	pieces = {}, -- scratch list for titleRoom, reused so placing the name makes no new tables
	shownAt = 0, -- os.clock() when the station name started fading in
	alpha = 1, -- the fade the name is drawn with now (setTitleFade), so it is only set on a change
	ruleAt = 0, -- os.clock() when the rule started drawing out
	ruleFull = TITLE.RULE, -- how wide the rule gets on this screen...
	ruleNow = 0, -- ...and how wide it is drawn now
}
local HUDController -- found on first use (ClientMain starts it after us); false = not there
local radioOn = true
local station = 1 -- index into Sounds.Radio: the station it is on, or was on before it was turned off
local trackIndex = {} -- [station] = index of its current track
local onAir = nil -- the station the radio Sound is playing (nil = silent)
local liveAt = {} -- [station] = { track, pos, len, at }: where it was when we stopped listening (liveSpot)
local startedPos, startedAt = 0, 0 -- the song playing now was started this far in, at this os.clock()
local seekConn -- waits for a song to load so it can start part-way in (playStation)
local radioFade = 1 -- 0..1: the music coming up after a get-in or a station change
local radioCar -- the car the radio is in: the one you drive, then the one you just got out of
local lingerUntil = nil -- os.clock() when the radio heard from outside the car stops (nil = not lingering)
local muffle -- equalizer on the radio, on while it is heard from outside the car
local radioTouched = false -- the player changed the radio this session (the saved choice no longer applies)
local saveStamp = 0
local wasDriving = false

-- The station and track playing now (nil, nil while the radio is off).
local function nowPlaying()
	local s = radioOn and Sounds.Radio[station] or nil
	local t = s and s.Tracks[trackIndex[station] or 0] or nil
	return s, t
end

local function refreshRadioRow()
	local s, t = nowPlaying()
	if s then
		-- A compact row has no room for the track: the station alone (the big title names the track).
		radioLabel.Text = string.upper(s.Name) .. ((t and not rowCompact) and (" · " .. t.Name) or "")
		radioLabel.TextColor3 = Theme.Color.Text
	else
		radioLabel.Text = "RADIO IS OFF"
		radioLabel.TextColor3 = Theme.Color.Dim
	end
	-- The button says what a tap does. While the radio is off it is the bright one: the way back to music.
	-- In a compact row its two words are stacked so it can be narrower.
	powerButton.Text = "RADIO" .. (rowCompact and "\n" or " ") .. (radioOn and "OFF" or "ON")
	Theme.Button(powerButton, radioOn and "Quiet" or "Primary")
	powerButton.FontFace = Theme.Font.Display
end

-- Fit the row to its slot's width (DriveUI's slot is 180-300 px; our fallback is 300). Runs whenever
-- the row's size changes: a phone turned, a window resized, DriveUI switching between PC and touch.
local function fitRadioRow()
	local w = radioRow.AbsoluteSize.X
	if w <= 0 then
		return -- not laid out yet: the size signal brings us back when it is
	end
	local compact = w < COMPACT_BELOW
	local power = compact and POWER_COMPACT or POWER_WIDTH
	local around = (Theme.Touch + ROW_GAP) * 2 + power + ROW_GAP -- « and » and the power button, with gaps
	local showLabel = w - around >= LABEL_MIN
	if compact == rowCompact and showLabel == radioLabel.Visible then
		return
	end
	rowCompact = compact
	powerButton.Size = UDim2.new(0, power, 1, 0)
	powerButton.TextSize = compact and 13 or 15
	powerButton.LineHeight = compact and 0.9 or 1
	nextButton.Position = UDim2.new(1, -(power + ROW_GAP), 0, 0)
	radioLabel.Size = UDim2.new(1, -around, 1, 0)
	radioLabel.Visible = showLabel -- too narrow even for the station: « » and the power button are enough
	-- Compact: the station name shrinks to fit (9-15 px, UITextSizeConstraint in buildRadio) instead of
	-- being cut to "NE..."; wide: a steady 15 px, with a long track name cut off at the end.
	radioLabel.TextScaled = compact
	local pad = compact and 3 or 6
	labelPad.PaddingLeft, labelPad.PaddingRight = UDim.new(0, pad), UDim.new(0, pad)
	refreshRadioRow()
end

local function setTitleFade(a) -- 0 = fully shown, 1 = gone
	title.label.TextTransparency = a
	title.sub.TextTransparency = a
	title.rule.BackgroundTransparency = a
	title.shadow.Transparency = 0.45 + 0.55 * a
	title.subShadow.Transparency = 0.45 + 0.55 * a
end

-- Our ScreenGui covers the whole screen (IgnoreGuiInset). Until it has been laid out, ask the camera.
local function screenSize()
	local size = radioGui.AbsoluteSize
	if size.Y <= 0 then
		local camera = Workspace.CurrentCamera
		if camera then
			size = camera.ViewportSize
		end
	end
	return size
end

-- HUDController's big centre stamp ("CAR JACKED!", "FARE PAID", "STUNT JUMP") while one shows: its top
-- and bottom in pixels from the top of the screen, else nil. It is drawn with no name, so ask
-- HUDController (its ScreenGui ignores the inset too: same coordinates as ours). The stamp fills
-- Theme's "Stamp" zone: a fixed 150 px tall on a PC and 110 on a phone, NOT a share of the screen (on a
-- 390 px phone that is well over a quarter of it). StampTop gives the top and the bottom; should a
-- HUDController only give the top, the zone gives the height (the same layout test, Theme.IsTouch).
local function hudStampBand(size)
	if HUDController == nil then
		local module = script.Parent:FindFirstChild("HUDController")
		local ok, hud = false, nil
		if module then
			ok, hud = pcall(require, module)
		end
		HUDController = ok and type(hud) == "table" and hud or false
	end
	if not HUDController or type(HUDController.StampTop) ~= "function" then
		return nil
	end
	local top, bottom = HUDController.StampTop()
	if type(top) ~= "number" then
		return nil
	end
	if type(bottom) ~= "number" then
		local zone = Theme.Zone("Stamp", Theme.IsTouch())
		bottom = top + zone.Size.Y.Scale * size.Y + zone.Size.Y.Offset
	end
	return top, bottom
end

-- Any big moment stamp on screen: HUDController's, or CombatClient's (the one in TITLE.CLEAR)?
local function stampShowing(size)
	if hudStampBand(size) then
		return true
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	local combat = playerGui and playerGui:FindFirstChild("CombatHUD")
	local stamp = combat and combat:IsA("ScreenGui") and combat.Enabled and combat:FindFirstChild("Stamp")
	if not stamp then
		return false
	end
	return stamp:IsA("GuiObject") and stamp.Visible
end

-- Where the station name can go: the first gap at top centre, from `from` down, that is clear of the
-- HUD pieces showing right now (a tall tutorial pill, a squeezed objective banner, the race turn
-- arrows, the drift score, a big stamp...). Returns the y (pixels from the top of the screen) and whether
-- the name really fits there. When it doesn't (a small phone with a tall banner up), y is the lowest
-- spot allowed.
local function titleRoom(from)
	-- AbsolutePosition starts under the top bar whatever IgnoreGuiInset says: measure from our own corner.
	local origin = radioGui.AbsolutePosition
	local size = screenSize()
	local mid = size.X / 2
	local pieces, height = title.pieces, title.height
	table.clear(pieces)
	local playerGui = player:FindFirstChild("PlayerGui")
	for _, path in ipairs(TITLE.CLEAR) do
		local screen = playerGui and playerGui:FindFirstChild(path[1])
		local obj = screen and screen:IsA("ScreenGui") and screen.Enabled and screen:FindFirstChild(path[2])
		if obj and obj:IsA("GuiObject") and obj.Visible then
			-- Only pieces that reach the middle of the screen count: a banner squeezed against the left
			-- column on a wide screen is not in the name's way.
			local x0 = obj.AbsolutePosition.X - origin.X
			if x0 < mid + TITLE.HALF and x0 + obj.AbsoluteSize.X > mid - TITLE.HALF then
				table.insert(pieces, obj)
			end
		end
	end
	local top = from
	local s0, s1 = hudStampBand(size)
	-- A piece (or the stamp) can push the name down only once (the name ends up under it), so one pass
	-- per piece, plus one for the stamp, always settles.
	for _ = 1, #pieces + 1 do
		local moved = false
		for _, obj in ipairs(pieces) do
			local y0 = obj.AbsolutePosition.Y - origin.Y
			local y1 = y0 + obj.AbsoluteSize.Y
			if y0 < top + height and y1 + TITLE.GAP > top then
				top = math.ceil(y1) + TITLE.GAP
				moved = true
			end
		end
		if s0 and s0 < top + height and s1 + TITLE.GAP > top then
			top = math.ceil(s1) + TITLE.GAP
			moved = true
		end
		if not moved then
			break
		end
	end
	-- Never down into the middle of the road, and never onto our own row when it sits at bottom centre.
	local limit = size.Y * TITLE.LOWEST
	if fallbackSlot then
		limit = math.min(limit, size.Y - fallbackUp - Theme.Touch)
	end
	local lowest = math.max(TITLE.TOP, math.floor(limit) - height)
	return math.min(top, lowest), top <= lowest
end

local function hideTitle()
	title.untilAt = nil
	title.optional = false
	title.holder.Visible = false
end

-- The station's name in Display, a thin rule under it (the brand's pink: the one place it shows here;
-- grey for RADIO OFF) and the track under that.
-- optional = nobody asked for this one (the station name when you get in): it is skipped when there is
-- no free room for it, or while a big stamp is up (getting into a jacked car comes with "CAR JACKED!").
-- A change the player made always shows, in the lowest spot allowed if need be.
local function showTitle(text, sub, optional)
	local size = screenSize()
	local small = size.Y < 500 -- phones held sideways
	local line = small and 30 or 42
	title.height = line + 28 -- the name, 4 px, the rule (2), 4 px, the track (18)
	local y, fits = titleRoom(TITLE.TOP)
	if optional and (not fits or stampShowing(size)) then
		hideTitle()
		return
	end
	title.optional = optional == true
	title.y = y
	title.holder.Position = UDim2.new(0.5, 0, 0, y)
	title.holder.Size = UDim2.new(0.8, 0, 0, title.height)
	title.label.Size = UDim2.new(1, 0, 0, line)
	title.label.TextSize = small and 26 or 36
	title.label.Text = text
	title.rule.Position = UDim2.new(0.5, 0, 0, line + 4)
	title.rule.BackgroundColor3 = radioOn and Theme.Color.Brand or Theme.Color.Dim
	title.rule.Size = UDim2.fromOffset(0, 2)
	title.sub.Position = UDim2.fromOffset(0, line + 10)
	title.sub.Text = sub or ""
	local now = os.clock()
	-- Fades in, unless a name is already up (flicking through the stations): the new one just replaces it.
	if title.untilAt then
		title.shownAt = now - TITLE.IN
		title.alpha = 0
	else
		title.shownAt = now
		title.alpha = 1
	end
	-- The rule draws out from the middle, again for every new name.
	title.ruleAt = now
	title.ruleFull = small and TITLE.RULE_SMALL or TITLE.RULE
	title.ruleNow = 0
	setTitleFade(title.alpha)
	title.holder.Visible = true
	title.untilAt = now + TITLE.SECONDS + TITLE.FADE
	title.checkAt = now + TITLE.RECHECK
end

local function updateTitle(now)
	if not title.untilAt then
		return
	end
	local left = title.untilAt - now
	if left <= 0 then
		hideTitle()
		return
	end
	local shown = now - title.shownAt
	local a = 0
	if shown < TITLE.IN then
		a = 1 - shown / TITLE.IN
	elseif left < TITLE.FADE then
		a = 1 - left / TITLE.FADE
	end
	if a ~= title.alpha then
		title.alpha = a
		setTitleFade(a)
	end
	-- The rule: fast at first, easing to its full width.
	local grown = math.clamp((now - title.ruleAt) / TITLE.RULE_IN, 0, 1)
	local width = math.floor(title.ruleFull * (1 - (1 - grown) ^ 3) + 0.5)
	if width ~= title.ruleNow then
		title.ruleNow = width
		title.rule.Size = UDim2.fromOffset(width, 2)
	end
	-- Something may have appeared under the name since it was placed (a turn arrow, a drift score, the
	-- next tutorial step): step down out of its way. Only ever down, so a piece that blinks can't make
	-- the name bounce.
	if now >= title.checkAt then
		title.checkAt = now + TITLE.RECHECK
		-- The get-in name gives way to a stamp that comes up a moment later ("CAR JACKED!" arrives just
		-- after you sit down). One the player asked for steps down under it instead.
		if title.optional and stampShowing(screenSize()) then
			hideTitle()
			return
		end
		local y = titleRoom(title.y)
		if y > title.y then
			title.y = y
			title.holder.Position = UDim2.new(0.5, 0, 0, y)
		end
	end
end

-- How far into the playing song the radio is. While the song is still loading it hasn't really started:
-- it is where it will pick up from once it has (playStation's seek).
local function heardPos()
	if radio.IsLoaded then
		return radio.TimePosition
	end
	return startedPos + (os.clock() - startedAt)
end

-- We stop listening to the station on air: note where it is, so it carries on without us (liveSpot).
local function leaveStation()
	if onAir and radio.IsPlaying then
		local spot = liveAt[onAir] or {}
		spot.track = trackIndex[onAir]
		spot.pos = heardPos()
		spot.len = radio.IsLoaded and radio.TimeLength or 0
		spot.at = os.clock()
		liveAt[onAir] = spot
	end
	onAir = nil
end

-- Where station st's broadcast has got to: a song (index) and seconds into it. A station keeps going
-- while nobody listens, like a real one: come back to it and the song has moved on, or a later one is
-- playing. The first time this session you land somewhere in a random song (tuning in mid-song).
-- Walking on through the songs needs their Length (Config.Sounds.Radio); a song with none is started
-- from the top.
local function liveSpot(st)
	local tracks = Sounds.Radio[st].Tracks
	local n = #tracks
	local spot = liveAt[st]
	local idx, pos, len
	if spot and tracks[spot.track] then
		idx = spot.track
		pos = spot.pos + (os.clock() - spot.at)
		len = spot.len > 0 and spot.len or tracks[idx].Length -- the measured length beats the listed one
		if not len then
			return idx, pos -- can't tell: carry on (playStation's seek starts it over if that's past the end)
		end
	else
		idx = math.random(n)
		len = tracks[idx].Length
		pos = len and math.random() * len * 0.6 or 0
	end
	-- The whole list's length, if every song has one: an absence longer than that skips whole rounds.
	local listed = 0
	for _, t in ipairs(tracks) do
		if type(t.Length) ~= "number" then
			listed = 0
			break
		end
		listed += t.Length
	end
	for step = 1, n + 1 do
		if type(len) ~= "number" or len <= TRACK_TAIL then
			return idx, 0
		end
		if pos < len - TRACK_TAIL then
			return idx, pos
		end
		pos = math.max(0, pos - len) -- that song ended meanwhile: on to the next
		idx = idx % n + 1
		len = tracks[idx].Length
		if step == 1 and listed > 0 then
			pos %= listed
		end
	end
	return idx, 0
end

-- Put the station on: where its broadcast has got to, or (nextSong) its next song from the top because
-- the last one just ended. Silence if the radio is off or the station has no songs.
local function playStation(nextSong)
	if not nextSong then
		leaveStation() -- (the station we were on carries on without us)
	end
	if seekConn then
		seekConn:Disconnect()
		seekConn = nil
	end
	local s = radioOn and Sounds.Radio[station] or nil
	if not s or #s.Tracks == 0 then
		onAir = nil
		radio:Stop()
		return
	end
	local idx, pos
	if nextSong then
		idx, pos = (trackIndex[station] or 0) % #s.Tracks + 1, 0
	else
		idx, pos = liveSpot(station)
		liveAt[station] = nil
		radioFade = 0 -- comes up over RADIO_FADE_IN (updateRadio)
	end
	trackIndex[station] = idx
	radio.SoundId = "rbxassetid://" .. s.Tracks[idx].Id
	radio.TimePosition = pos
	radio:Play()
	onAir = station
	startedPos, startedAt = pos, os.clock()
	if pos <= 0 then
		return
	end
	-- Starting part-way in: a song that is still loading may not take the position yet, so it is set
	-- again once it has loaded (where it would be by then). Past the real end: from the top instead.
	local function seek()
		local want = startedPos + (os.clock() - startedAt)
		local len = radio.TimeLength
		radio.TimePosition = (len > 0 and want >= len - 1) and 0 or want
	end
	if radio.IsLoaded then
		seek()
	else
		local conn
		conn = radio.Loaded:Connect(function()
			conn:Disconnect()
			if seekConn == conn then
				seekConn = nil
				seek()
			end
		end)
		seekConn = conn
	end
end

-- The radio goes quiet (turned off, or out of earshot of the car you left). Its station carries on.
local function stopRadio()
	leaveStation()
	if seekConn then
		seekConn:Disconnect()
		seekConn = nil
	end
	radio:Stop()
	lingerUntil = nil
	muffle.Enabled = false
end

-- The saved choice (settings "RadioOff" / "RadioStation"), used until the player touches the radio
-- this session. Read when a drive starts: the settings have arrived from the server by then.
local function loadSaved()
	if radioTouched then
		return
	end
	local ok, SettingsClient = pcall(require, script.Parent:FindFirstChild("SettingsClient"))
	if not ok or type(SettingsClient) ~= "table" then
		return
	end
	radioOn = SettingsClient.Get("RadioOff") ~= true
	local saved = SettingsClient.Get("RadioStation")
	if type(saved) == "number" and Sounds.Radio[saved] then
		station = saved
	end
end

-- Remember the player's choice. Saved a moment after the last change, so flicking through the
-- stations sends one save, not one per press.
local function rememberRadio()
	radioTouched = true
	saveStamp += 1
	local stamp = saveStamp
	task.delay(1.5, function()
		if stamp ~= saveStamp then
			return
		end
		pcall(function()
			local SettingsClient = require(script.Parent:FindFirstChild("SettingsClient"))
			if (SettingsClient.Get("RadioOff") == true) ~= (not radioOn) then
				SettingsClient.Set("RadioOff", not radioOn)
			end
			if SettingsClient.Get("RadioStation") ~= station then
				SettingsClient.Set("RadioStation", station)
			end
		end)
	end)
end

-- The player changed something: play (or stop), redraw the row, announce it, remember it.
-- tuned = it landed on a station by stepping through them: a short burst of static, like turning a real
-- dial (the music then comes up out of it). Otherwise the power switch just clicks.
local function applyRadio(tuned)
	local tune = tuned and radioOn and SoundClient.Play("RadioTune", nil, nil, TUNE_LIFE)
	if tune then
		tune.SoundGroup = require(script.Parent:WaitForChild("SettingsClient")).Group("Music") -- (it is the radio)
	else
		SoundClient.Play("Click") -- (also when RadioTune has no asset: Id = 0)
	end
	if radioOn then
		playStation()
	else
		stopRadio()
	end
	refreshRadioRow()
	local s, t = nowPlaying()
	if s then
		showTitle(string.upper(s.Name), t and t.Name or "")
	else
		showTitle("RADIO OFF", "")
	end
	rememberRadio()
end

-- « / »: the station before / after, round and round. With the radio off they just turn it back on.
local function stepStation(dir)
	local count = #Sounds.Radio
	if not wasDriving or count == 0 then
		return
	end
	local tuned = radioOn -- (stepping from one station to another; from off it is just switched on)
	if radioOn then
		station = (station - 1 + dir) % count + 1
	else
		radioOn = true
	end
	applyRadio(tuned)
end

-- V / D-pad: the same walk with "off" as one more stop after the last station (and before the first).
local function cycleStation(dir)
	local count = #Sounds.Radio
	if not wasDriving or count == 0 then
		return
	end
	if radioOn then
		local n = station + dir
		if n < 1 or n > count then
			radioOn = false
		else
			station = n
		end
	else
		radioOn = true
		station = dir > 0 and 1 or count
	end
	applyRadio(radioOn) -- (static when it lands on a station, a click when it lands on "off")
end

local function togglePower()
	if not wasDriving or #Sounds.Radio == 0 then
		return
	end
	radioOn = not radioOn
	applyRadio()
end

local function radioButton(name, text, width)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.new(0, width, 1, 0)
	b.Text = text
	Theme.Button(b, "Quiet")
	b.FontFace = Theme.Font.Display
	b.TextSize = 15
	b.Parent = radioRow
	return b
end

-- Only for our own slot. A DriveUI without a RadioSlot draws the speed readout at bottom centre, 13% of
-- the screen height tall and 18 px up, so on a tall screen a fixed 150 px would put the row right back
-- under the MPH digits. Keyboard players also get that DriveUI's controls strip for their first 20 s
-- of driving (32 px tall, 10 px above the readout and never lower than 142 px): stay above that too.
local function placeFallback()
	local gaugeTop = math.floor(screenSize().Y * 0.13) + 18
	local up = math.max(FALLBACK_UP, gaugeTop + 10) -- (the 44 px row hangs 2 px under the 40 px slot)
	if UserInputService.KeyboardEnabled and (UserInputService.MouseEnabled or not UserInputService.TouchEnabled) then
		up = math.max(up, 180, gaugeTop + 48)
	end
	fallbackUp = up
	fallbackSlot.Position = UDim2.new(0.5, 0, 1, -up)
end

local function buildRadio()
	radio = Instance.new("Sound")
	radio.Name = "Radio"
	radio.Volume = RADIO_VOLUME
	radio.SoundGroup = require(script.Parent:WaitForChild("SettingsClient")).Group("Music")
	radio.Parent = flat
	-- Heard from outside the car (updateRadio): the body of the car swallows the highs, the bass thumps on.
	muffle = Instance.new("EqualizerSoundEffect")
	muffle.Name = "OutsideTheCar"
	muffle.LowGain, muffle.MidGain, muffle.HighGain = 3, -9, -28
	muffle.Enabled = false
	muffle.Parent = radio
	-- A song ended: the station's next one, in the car or still heard from outside it.
	radio.Ended:Connect(function()
		if radioOn and onAir and (wasDriving or lingerUntil) then
			playStation(true)
			refreshRadioRow()
		else
			onAir = nil
		end
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "Radio"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	radioGui = gui

	-- Home of the row: DriveUI's slot right above the speed readout (DriveUI only shows it while
	-- driving). No slot (an older DriveUI, or it failed to start): our own spot at bottom centre.
	local slot
	local module = script.Parent:FindFirstChild("DriveUI")
	if module then
		local ok, DriveUI = pcall(require, module)
		local s = ok and type(DriveUI) == "table" and DriveUI.RadioSlot
		if typeof(s) == "Instance" and s:IsA("GuiObject") then
			slot = s
		end
	end
	if not slot then
		slot = Instance.new("Frame")
		slot.Name = "RadioSlot"
		slot.AnchorPoint = Vector2.new(0.5, 1)
		slot.Size = UDim2.fromOffset(300, 40)
		slot.BackgroundTransparency = 1
		slot.Parent = gui
		fallbackSlot = slot
		placeFallback()
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeFallback) -- window resized, phone turned
	end

	-- The row is one touch target tall (44 px), centred on the slot. Both slots are 40 px tall, so 2 px
	-- hang over each edge (into DriveUI's 6 px list gap below): nothing may clip them.
	radioRow = Instance.new("Frame")
	radioRow.Name = "RadioRow"
	radioRow.AnchorPoint = Vector2.new(0.5, 0.5)
	radioRow.Position = UDim2.fromScale(0.5, 0.5)
	radioRow.Size = UDim2.new(1, 0, 0, Theme.Touch)
	radioRow.BackgroundTransparency = 1
	radioRow.Visible = false
	radioRow.Parent = slot

	local side = Theme.Touch
	local prev = radioButton("Prev", "«", side)
	prev.TextSize = 24
	prev.Position = UDim2.fromOffset(0, 0)
	prev.Activated:Connect(function()
		stepStation(-1)
	end)

	-- Station and track on one line; a long track name is cut off with dots. (fitRadioRow re-lays the
	-- row for narrow slots: station only, scaled to fit.)
	radioLabel = Instance.new("TextLabel")
	radioLabel.Name = "Now"
	radioLabel.Position = UDim2.fromOffset(side + ROW_GAP, 0)
	radioLabel.Size = UDim2.new(1, -(side + ROW_GAP) * 2 - (POWER_WIDTH + ROW_GAP), 1, 0)
	radioLabel.Text = ""
	radioLabel.TextXAlignment = Enum.TextXAlignment.Left
	radioLabel.TextTruncate = Enum.TextTruncate.AtEnd
	radioLabel.TextWrapped = false -- scaled text stays on one line
	Theme.Text(radioLabel, 15, "DisplayLight")
	Theme.Panel(radioLabel)
	labelPad = Instance.new("UIPadding")
	labelPad.PaddingLeft, labelPad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
	labelPad.Parent = radioLabel
	local fit = Instance.new("UITextSizeConstraint") -- only bites while TextScaled (compact row)
	fit.MinTextSize, fit.MaxTextSize = 9, 15
	fit.Parent = radioLabel
	radioLabel.Parent = radioRow

	nextButton = radioButton("Next", "»", side)
	nextButton.TextSize = 24
	nextButton.AnchorPoint = Vector2.new(1, 0)
	nextButton.Position = UDim2.new(1, -(POWER_WIDTH + ROW_GAP), 0, 0)
	nextButton.Activated:Connect(function()
		stepStation(1)
	end)

	powerButton = radioButton("Power", "RADIO OFF", POWER_WIDTH)
	powerButton.AnchorPoint = Vector2.new(1, 0)
	powerButton.Position = UDim2.fromScale(1, 0)
	powerButton.Activated:Connect(togglePower)

	-- Re-lay the row whenever its width changes (the slot follows DriveUI's cluster).
	radioRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitRadioRow)
	fitRadioRow()

	-- The big station name, top centre: the name in Display, a thin rule, the track (showTitle sizes
	-- them for the screen). Labels and a line only: it never takes a tap.
	local holder = Instance.new("Frame")
	holder.Name = "StationTitle"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, TITLE.TOP)
	holder.Size = UDim2.new(0.8, 0, 0, title.height)
	holder.BackgroundTransparency = 1
	holder.Active = false
	holder.Visible = false
	holder.Parent = gui
	title.holder = holder
	local name = Instance.new("TextLabel")
	name.Name = "Station"
	name.Size = UDim2.new(1, 0, 0, 42)
	name.Text = ""
	name.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.Text(name, 36, "Display")
	title.shadow = Theme.Shadow(name, 2)
	name.Parent = holder
	title.label = name
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, 46)
	rule.Size = UDim2.fromOffset(0, 2)
	rule.BackgroundColor3 = Theme.Color.Brand
	rule.BorderSizePixel = 0
	rule.Parent = holder
	title.rule = rule
	local track = Instance.new("TextLabel")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(0, 52)
	track.Size = UDim2.new(1, 0, 0, 18)
	track.Text = ""
	track.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.Text(track, 15, "Body")
	title.subShadow = Theme.Shadow(track)
	track.Parent = holder
	title.sub = track

	refreshRadioRow()
end

local function updateRadio(now, dt)
	local status = DriveController.Status
	local driving = status.Driving == true
	if driving then
		radioCar = status.Car or radioCar
	end
	if driving ~= wasDriving then
		wasDriving = driving
		radioRow.Visible = driving
		if driving then
			loadSaved()
			-- Back in before the song you left playing had stopped: it just carries on, inside again.
			local carryOn = lingerUntil ~= nil and radioOn and onAir == station and radio.IsPlaying
			lingerUntil = nil
			muffle.Enabled = false
			if carryOn then
				-- (up from how loud it was outside; that volume had the duck under score in it too, see below)
				radioFade = math.clamp(radio.Volume / (RADIO_VOLUME * math.max(cue.duck, 0.01)), 0, 1)
			else
				playStation() -- picks the station up where it has got to; stays silent if the radio is off
			end
			refreshRadioRow()
			local s, t = nowPlaying()
			if s then
				-- Nobody asked for this one: it only shows when there is free room for it (a new player's
				-- first drive has the tutorial's text right there).
				showTitle(string.upper(s.Name), t and t.Name or "", true)
			end
		else
			-- Got out, with no "RADIO OFF" on screen (the radio is still on for next time). The song plays
			-- on from the car for a moment, muffled, the way a car radio sounds from the street.
			hideTitle()
			if onAir and radio.IsPlaying and radioCar and radioCar.Parent then
				lingerUntil = now + LINGER_SECONDS
				muffle.Enabled = true
			else
				stopRadio()
			end
		end
	end
	-- How loud: coming up after a get-in or a station change; from outside, by the distance to the car.
	local level = 1
	if wasDriving then
		if radioFade < 1 then
			radioFade = math.min(1, radioFade + dt / RADIO_FADE_IN)
		end
		level = radioFade
	elseif lingerUntil then
		local chassis = radioCar and radioCar.Parent and radioCar.PrimaryPart
		local driver = radioCar and radioCar:GetAttribute("DriverUserId")
		local reach = 0
		if chassis and (driver == nil or driver == player.UserId) then -- (someone else drove off in it: gone)
			local d = (chassis.Position - Workspace.CurrentCamera.CFrame.Position).Magnitude
			reach = math.clamp((LINGER_FAR - d) / (LINGER_FAR - LINGER_NEAR), 0, 1)
		end
		level = LINGER_LEVEL * reach * math.clamp((lingerUntil - now) / LINGER_FADE, 0, 1)
		if level <= 0 then
			stopRadio() -- walked out of earshot, time up, or the car is gone
			level = 1
		end
	end
	-- Under score (HeistMusic) the radio slides down out of its way, and back up when it ends.
	local duckTo = musicLoopOn() and CUE.RADIO_DUCK or 1
	if cue.duck ~= duckTo then
		local step = dt * CUE.DUCK_SPEED
		cue.duck = math.clamp(duckTo, cue.duck - step, cue.duck + step)
	end
	local volume = RADIO_VOLUME * level * cue.duck
	if radio.Volume ~= volume then
		radio.Volume = volume
	end
	updateTitle(now)
end

------------------------------------------------------------------ init

function SoundClient.Init()
	DriveController = require(script.Parent:WaitForChild("DriveController"))
	ensureFolders()
	rain = newSound("Rain", flat)
	waves = newSound("Waves", flat)
	city = newSound("CityAmbience", flat)
	buildRadio()

	-- Moments from the server. Each remote is hooked up in its own thread: WaitForChild on a remote
	-- the server hasn't made yet must never hold up the other controllers.
	local function on(name, fn)
		task.spawn(function()
			Remotes.Event(name).OnClientEvent:Connect(fn)
		end)
	end
	local function cash()
		SoundClient.Play("Cash")
	end
	on("Banked", cash)
	on("BountyEarned", cash)
	on("CashPackGranted", cash)
	on("DailyReward", cash)
	on("HeistResult", cash)
	on("Caught", function()
		cue.caughtAt = os.clock() -- (the heat cleared by an arrest gets no LostCops sting: hookCues)
		SoundClient.Play("Cuffs")
	end)
	on("TaserFx", function(_, target)
		local root = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
		if root then -- far-away (streamed-out) tasers stay silent
			SoundClient.Play("Zap", root)
		end
	end)
	local raceToken = 0 -- bumped when a countdown starts or a race is called off (stale beeps stay quiet)
	on("RaceEvent", function(kind, d)
		if kind == "Countdown" then
			raceToken += 1
			local token = raceToken
			local startAt = type(d) == "table" and tonumber(d.StartAt)
			if not startAt then
				SoundClient.Play("Countdown")
				return
			end
			-- The server sends this once; ActivityClient shows 3, 2, 1 from StartAt. Beep on each number,
			-- then GO. A beep that's up to half a second late (ping) still plays.
			local now = Workspace:GetServerTimeNow()
			local function beepAt(t, name)
				local left = t - now
				if left > -0.5 then
					task.delay(math.max(0, left), function()
						if raceToken == token then
							SoundClient.Play(name)
						end
					end)
				end
			end
			for i = 3, 1, -1 do
				beepAt(startAt - i, "Countdown")
			end
			beepAt(startAt, "Checkpoint") -- GO
		elseif kind == "Cancelled" then
			raceToken += 1
		elseif kind == "Checkpoint" then
			SoundClient.Play("Checkpoint")
		elseif kind == "Finished" then
			SoundClient.Play("Success")
		end
	end)
	on("Notify", function(key)
		if key == "CarSank" then
			SoundClient.Play("Splash")
		end
	end)
	for _, name in ipairs({ "TutorialDone", "PassGranted", "GarageResult" }) do
		on(name, function()
			SoundClient.Play("Success")
		end)
	end

	-- SPOTTED!: a cop sees you while you're wanted (HeatService sets HeatSpotted). HeatSpotted only goes
	-- back to false after 8 s unseen, so this can't chatter; the 3 s gap is just a guard.
	local lastSpotted = -math.huge
	player:GetAttributeChangedSignal("HeatSpotted"):Connect(function()
		if player:GetAttribute("HeatSpotted") ~= true or (player:GetAttribute("Heat") or 0) <= 0 then
			return
		end
		if os.clock() - lastSpotted < 3 then
			return
		end
		lastSpotted = os.clock()
		-- "bip-BEEP": the first beep is cut short so the two don't smear into one.
		local first = SoundClient.Play("Spotted")
		task.delay(0.14, function()
			if first then
				first:Stop()
			end
			SoundClient.Play("Spotted")
		end)
	end)

	-- Stars up, losing the cops, money in (the police radio chatter runs in the loop below).
	hookCues()

	-- H: horn for civilians, siren toggle for cops (the server checks and replicates).
	-- V / D-pad right: next radio station, then off. D-pad left: the other way. (Only while driving; a
	-- D-pad press that moved the selection in a menu comes in as processed and is ignored. DriveUI's
	-- controls strip shows the keys: "V Radio" on a keyboard, "D-PAD Radio" on a gamepad.)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.H then
			Remotes.Event("RequestHorn"):FireServer()
		elseif key == Enum.KeyCode.V or key == Enum.KeyCode.DPadRight then
			cycleStation(1)
		elseif key == Enum.KeyCode.DPadLeft then
			cycleStation(-1)
		end
	end)

	local lastScan = 0
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		if now - lastScan > 0.5 then
			lastScan = now
			updateCars()
			updateAlarms()
			ambience()
			policeChatter(now)
		end
		carAudio(dt, now)
		ownCarAudio(dt)
		updateRadio(now, dt)
	end)
end

return SoundClient
