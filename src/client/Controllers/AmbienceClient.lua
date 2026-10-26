-- AmbienceClient (ModuleScript, StarterPlayerScripts.Controllers.AmbienceClient)
-- A city that feels alive. Everything here is local to this device and cheap; the settings are in
-- Config.Ambience.
--   * Area name card. Walk or drive into a new area (Config.Ambience.Districts) and its name shows in a
--     script face, with a small street-type line under it ("Solana Heights" / DOWNTOWN). It fades in, holds
--     and fades out over about 4 s. At most one area card every Card.Cooldown (20) s, and only after
--     Card.Settle s inside the new area, so a border never flickers. Never on the first-join title screen
--     (player attribute TitleScreen) or inside a home (InHome), and not for Card.AfterJump s after a
--     teleport (a respawn, an arrest), while the screen is busy with that.
--     Where it goes: the first of these spots that is free of the HUD pieces in CARD_CLEAR (the cop's
--     TASER / SPIKES tiles, the END SHIFT and OUTFIT tiles, the open phone, the car's name on getting in,
--     the touch gun buttons, banners and stamps...) at that moment:
--       PC / gamepad: bottom-right, its right edge in line with the car cluster and Card.Gap px above
--         Theme's Corner zone; else the same height, left of the Buttons zone and the side column under it
--         (also in a window too short for the card between the Buttons zone and the cluster).
--       Phone / tablet: right-aligned under Theme's Buttons zone when there is room down to the jump
--         button or the driving pedals; else top centre, under the Banner zone (a phone with the pedals up).
--     With no spot free the area card waits and tries again; a card somebody asked for (ShowCard) takes
--     the first spot anyway. ScreenGui "AreaName" (DisplayOrder -1: it draws under the other HUD layers,
--     so it can never hide a button or a stamp that appears while it shows), frame "Card".
--   * Sound by place and time. One bed loop at a time (Areas[..].Beds Day / Night), cross-faded over
--     Mix.BedFade and quieter in a storm. Downtown, the beach, Lighthouse Key and the sea have no bed of
--     ours, because SoundClient already plays the city hum, the surf and the beach gulls there, and we
--     never double those (nor its rain). Distant 3D one-shots (sirens, far horns, gulls, a ship's horn
--     from the cargo ship's side) are placed far from the camera. The sirens are very quiet and never
--     play while you are wanted (player attribute Heat), so a siren in a chase is always a real police
--     car. Fixed emitters: a beach speaker by day, muffled club bass at night; their music runs on the
--     server clock, so coming back you walk into the middle of the song, not its first bar. Everything
--     goes quiet inside a home and plays through SettingsClient's "Effects" group.
--   * Background life on fixed loops, built from plain parts (no assets). The planes, the boats and the
--     pelicans are placed from the server clock, so every player sees them in the same place (the
--     helicopter's flight in and out and the flocks are this device's own):
--       - a commuter plane circling high over the city, with nav lights and strobes at night
--       - a small plane towing a banner up and down the beach by day
--       - a news helicopter that flies in at dusk, circles downtown with a searchlight beam and flies off
--         at dawn (white and gold with no police lights, on purpose: it is there every night, and must
--         not look as if it were hunting you)
--       - a cargo ship far offshore and a speedboat looping off the beach
--       - pelicans gliding in a V along the shore by day
--       - bird flocks (gulls, pelicans, pigeons, egrets) at a few roosts. They burst into the air when you
--         come within Scatter.Radius (12) studs, or while a fast car is still Scatter.CarLead seconds
--         away, circle, and settle back later.
--     Caps are in Config.Ambience.Life (fewer birds in Performance mode). Every part is anchored,
--     CanCollide / CanQuery / CanTouch off, and moved with one BulkMoveTo a frame (far movers every third
--     frame; nothing moves while you are inside a home).
-- API (safe to call before Init; nothing here yields):
--   AmbienceClient.Duck(volume, seconds)    lower all of OUR ambience to volume (0..1) for seconds, then
--     bring it back (the deepest duck still running wins)
--   AmbienceClient.Level() -> number        the duck level now (0..1), for other sounds that want to follow it
--   AmbienceClient.DuskOrder(position) -> seconds   how long after IsNight turns true this spot's night
--     lights should come on: soonest around the downtown plaza, up to Dusk.Spread (6) at the far edges,
--     a whole block at a time, with a steady per-block offset (Dusk.Jitter) so neighbouring blocks don't
--     switch as one. Pure maths, the same on every device, every night.
--   AmbienceClient.DuskWave(parts, switch) -> stop   the neon wave itself: calls switch(part) for every
--     BasePart in the array `parts`, each when its DuskOrder delay has passed (one loop, a few parts a
--     frame; parts that have gone meanwhile are skipped). stop() ends it early, leaving the parts it had
--     not reached alone. SkyClient's night lights use it.
--   AmbienceClient.AreaAt(position) -> key, area    the Config.Ambience.Areas entry at a world position
--     (nil, nil off the map). AmbienceClient.CurrentArea() -> key, area: where your character is now.
--   AmbienceClient.ShowCard(title, subtitle, hold) -> bool   the same card for something else (a car's
--     name and class when you get in). hold = seconds fully shown (default Card.Hold, 0.5..15). The area
--     card waits until it has gone. false while the title screen is up or before Init.
--   AmbienceClient.Scatter(position, radius, from)  birds on the ground within radius (default 30) of
--     position take off (a gunshot, a crash), flying away from `from` (default: position)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config.Ambience)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)

local player = Players.LocalPlayer

local AmbienceClient = {}

local CARD = Config.Card
local MIX = Config.Mix
local LIFE = Config.Life
local SCATTER = LIFE.Scatter

local TAU = math.pi * 2
local AUDIO_STEP = 1 / 15 -- seconds between sound updates (fades, ducks, one-shot timers, bird scares)
local LOGIC_STEP = 0.25 -- seconds between area checks and flock (de)activation
local JUMP = 250 -- studs moved between two area checks that can only be a teleport (no car does 1000 studs/s)
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- lays a Cylinder (axis X) along the forward axis
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- stands a Cylinder (axis X) upright
local NEON = Enum.Material.Neon
local PLAIN = Enum.Material.SmoothPlastic

local night = false -- Workspace attribute IsNight
local raining = false -- Workspace attribute Raining (read at every sound update)
local indoors = false -- player attribute InHome (read at every sound update)
local perf = false -- SettingsClient "Performance"
local initialised = false

local function rand(range)
	return range[1] + math.random() * (range[2] - range[1])
end

local function flatDistance(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function rootPart()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

------------------------------------------------------------------ settings

local Settings -- SettingsClient, found on first use (false = not there)

local function settings()
	if Settings == nil then
		local module = script.Parent:FindFirstChild("SettingsClient")
		local ok, found = false, nil
		if module then
			ok, found = pcall(require, module)
		end
		Settings = ok and type(found) == "table" and found or false
	end
	return Settings or nil
end

local function effectsGroup()
	local s = settings()
	if s and type(s.Group) == "function" then
		local ok, group = pcall(s.Group, "Effects")
		if ok and typeof(group) == "Instance" and group:IsA("SoundGroup") then
			return group
		end
	end
	return nil
end

local function performanceMode()
	local s = settings()
	if s and type(s.Get) == "function" then
		local ok, value = pcall(s.Get, "Performance")
		return ok and value == true
	end
	return false
end

------------------------------------------------------------------ areas

local function areaKeyAt(x, z)
	for _, d in ipairs(Config.Districts) do
		local r = d.Rect
		if x >= r[1] and x <= r[2] and z >= r[3] and z <= r[4] then
			return d.Area
		end
	end
	local sea = Config.Sea
	if sea and x >= sea.X0 and x <= sea.X1 and z >= sea.Z0 and z <= sea.Z1 then
		return sea.Area
	end
	return nil
end

function AmbienceClient.AreaAt(position)
	if typeof(position) ~= "Vector3" then
		return nil, nil
	end
	local key = areaKeyAt(position.X, position.Z)
	return key, key and Config.Areas[key] or nil
end

function AmbienceClient.CurrentArea()
	local root = rootPart()
	if not root then
		return nil, nil
	end
	return AmbienceClient.AreaAt(root.Position)
end

------------------------------------------------------------------ the neon wave

-- A steady 0..1 per block (the same on every device, every night).
local function blockNoise(bx, bz)
	local s = math.sin(bx * 12.9898 + bz * 78.233) * 43758.5453
	return s - math.floor(s)
end

function AmbienceClient.DuskOrder(position)
	if typeof(position) ~= "Vector3" then
		return 0
	end
	local dusk = Config.Dusk
	local block = math.max(dusk.Block, 1)
	local bx, bz = math.floor(position.X / block), math.floor(position.Z / block)
	-- Measured from the middle of the block, so everything in a block switches together.
	local dx = (bx + 0.5) * block - dusk.Centre.X
	local dz = (bz + 0.5) * block - dusk.Centre.Z
	local share = math.clamp(math.sqrt(dx * dx + dz * dz) / math.max(dusk.Reach, 1), 0, 1) ^ dusk.Curve
	local jitter = math.clamp(dusk.Jitter, 0, dusk.Spread)
	local delay = share * (dusk.Spread - jitter) + blockNoise(bx, bz) * jitter
	if delay ~= delay then
		return 0 -- (a NaN position: the wave sorts by this, and NaN would break the sort)
	end
	return delay
end

-- The wave itself: switch(part) for every part, each when its own delay has passed. One loop for the
-- whole city (a handful of parts a frame, which is also kinder to a phone than switching every light in
-- one frame). Returns a function that stops it early: the caller does that when night turns back to day,
-- or before starting another wave.
function AmbienceClient.DuskWave(parts, switch)
	local running = true
	local function stop()
		running = false
	end
	if type(parts) ~= "table" or type(switch) ~= "function" then
		return stop
	end
	local list = {}
	for _, part in ipairs(parts) do
		if typeof(part) == "Instance" and part:IsA("BasePart") then
			table.insert(list, { part, AmbienceClient.DuskOrder(part.Position) })
		end
	end
	table.sort(list, function(a, b)
		return a[2] < b[2]
	end)
	local count = #list
	if count == 0 then
		return stop
	end
	task.spawn(function()
		local t0 = os.clock()
		local i = 1
		local warned = false
		while running and i <= count do
			local elapsed = os.clock() - t0
			while running and i <= count and list[i][2] <= elapsed do
				local part = list[i][1]
				i += 1
				if part.Parent then -- (still there: far blocks stream out)
					local ok, err = pcall(switch, part)
					if not ok and not warned then
						warned = true -- the other lights still come on
						warn("[AmbienceClient] dusk wave: " .. tostring(err))
					end
				end
			end
			if i <= count then
				task.wait()
			end
		end
	end)
	return stop
end

------------------------------------------------------------------ ducking

local ducks = {} -- { level, until (os.clock) } of every duck still running
local duckLevel = 1

function AmbienceClient.Duck(volume, seconds)
	volume, seconds = tonumber(volume), tonumber(seconds)
	if not volume or not seconds or volume ~= volume or seconds ~= seconds then
		return
	end
	table.insert(ducks, { math.clamp(volume, 0, 1), os.clock() + math.clamp(seconds, 0, 600) })
	if #ducks > 16 then
		table.remove(ducks, 1)
	end
end

function AmbienceClient.Level()
	return duckLevel
end

-- The level the ducks ask for now (expired ones are dropped).
local function duckWanted(clock)
	local want = 1
	for i = #ducks, 1, -1 do
		local d = ducks[i]
		if clock >= d[2] then
			table.remove(ducks, i)
		elseif d[1] < want then
			want = d[1]
		end
	end
	return want
end

------------------------------------------------------------------ sounds

local soundFolder -- SoundService folder for the flat beds
local lifeFolder -- Workspace folder: every model here, and the one-shot anchor
local anchorPart -- invisible anchored part at the origin holding one-shot attachments

-- A Sound for a Config.Ambience.Sounds key (silent until the caller sets a volume), or nil.
local function makeSound(key, parent)
	local def = Config.Sounds[key]
	if not def or type(def.Id) ~= "number" or def.Id <= 0 then
		return nil, nil
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = "rbxassetid://" .. def.Id
	s.Volume = 0
	s.PlaybackSpeed = def.Pitch or 1
	s.Looped = def.Looped == true
	-- Region: only this stretch of the recording plays (and loops), for a take that isn't steady all through.
	local region = def.Region
	if type(region) == "table" and type(region[1]) == "number" and type(region[2]) == "number"
		and region[1] >= 0 and region[2] > region[1] then
		local range = NumberRange.new(region[1], region[2])
		s.PlaybackRegionsEnabled = true
		s.PlaybackRegion = range
		s.LoopRegion = range
	end
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = def.MinDistance or 25
	s.RollOffMaxDistance = def.MaxDistance or 400
	s.SoundGroup = effectsGroup()
	local eq = def.Eq
	if eq then
		local fx = Instance.new("EqualizerSoundEffect")
		fx.LowGain = math.clamp(eq.Low or 0, -80, 10)
		fx.MidGain = math.clamp(eq.Mid or 0, -80, 10)
		fx.HighGain = math.clamp(eq.High or 0, -80, 10)
		fx.Parent = s
	end
	s.Parent = parent
	return s, def
end

-- Beds: one wanted at a time; the others fade out and stop (kept for next time).
local beds = {} -- [sound key] = { sound, def, gain }
local lastSoundArea -- the last area the camera was in (kept while it crosses a gap between rectangles)
local rainMix = 1 -- how loud the beds are for the weather: 1, easing to Mix.RainBeds in a storm

local function updateBeds(dt, area, inHome)
	local want = nil
	if not inHome and area and area.Beds then
		want = night and area.Beds.Night or area.Beds.Day
	end
	if want and not beds[want] then
		local s, def = makeSound(want, soundFolder)
		if s then
			s.Looped = true
			beds[want] = { sound = s, def = def, gain = 0 }
		end
	end
	local step = dt / math.max(MIX.BedFade, 0.05)
	-- In a storm the birds and insects sit back behind SoundClient's rain (eased, so it never steps).
	local wet = raining and math.clamp(MIX.RainBeds or 1, 0, 1) or 1
	if rainMix < wet then
		rainMix = math.min(wet, rainMix + step)
	elseif rainMix > wet then
		rainMix = math.max(wet, rainMix - step)
	end
	for key, bed in pairs(beds) do
		local target = key == want and 1 or 0
		if bed.gain < target then
			bed.gain = math.min(target, bed.gain + step)
		elseif bed.gain > target then
			bed.gain = math.max(target, bed.gain - step)
		end
		if bed.gain > 0 then
			bed.sound.Volume = (bed.def.Volume or 0.3) * bed.gain * rainMix * duckLevel
			if not bed.sound.IsPlaying then
				bed.sound:Play()
			end
		elseif bed.sound.IsPlaying then
			bed.sound:Stop()
		end
	end
end

-- One-shots sounding now: { sound, holder, base, born, life, notWanted }.
local shots = {}
local shotNext = {} -- [Shots key] = os.clock() of its next play in this area
local shotArea -- the area shotNext was set up for

-- A 3D one-shot at a world position. force = play even when Mix.MaxShots are already sounding.
local function playAt(key, position, volumeScale, force)
	if not anchorPart or (not force and #shots >= MIX.MaxShots) then
		return nil
	end
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position -- (the anchor sits at the origin, unrotated: world = local)
	holder.Parent = anchorPart
	local s, def = makeSound(key, holder)
	if not s then
		holder:Destroy()
		return nil
	end
	s.Looped = false
	local base = (def.Volume or 0.4) * (volumeScale or 1)
	s.Volume = base * duckLevel
	s:Play()
	table.insert(shots, { sound = s, holder = holder, base = base, born = os.clock(), life = math.clamp(def.Life or 10, 0.5, 30) })
	return s
end

-- Fade each one-shot out over its last Mix.ShotFade seconds, and clear away the finished ones.
-- hot = you are wanted: a far-off siren still sounding (Shots NotWanted) starts its fade now.
local function updateShots(clock, hot)
	local fadeTime = math.max(MIX.ShotFade, 0.05)
	for i = #shots, 1, -1 do
		local shot = shots[i]
		local age = clock - shot.born
		if age >= shot.life or not shot.sound.Parent or (age > 1 and not shot.sound.IsPlaying) then
			shot.holder:Destroy()
			table.remove(shots, i)
		else
			if hot and shot.notWanted and shot.life - age > fadeTime then
				shot.life = age + fadeTime
			end
			shot.sound.Volume = shot.base * math.clamp((shot.life - age) / fadeTime, 0, 1) * duckLevel
		end
	end
end

local ship -- the cargo ship's rig (background life), for the ship's horn

local function fireShot(shot, cam)
	local list = shot.Sounds
	if type(list) ~= "table" or #list == 0 then
		return
	end
	local key = list[math.random(#list)]
	local d = rand(shot.Distance)
	local height = shot.Height or 6
	local position
	if shot.FromShip and ship and ship.shown and ship.lastPos then
		-- The cargo ship sounds its horn: from its side of the sky, but no further off than the shot's
		-- own distance. The ship is often a mile out, and its horn should still carry.
		local dx, dz = ship.lastPos.X - cam.X, ship.lastPos.Z - cam.Z
		local far = math.sqrt(dx * dx + dz * dz)
		if far > 1 then
			local reach = math.min(far, d) / far
			position = Vector3.new(cam.X + dx * reach, height, cam.Z + dz * reach)
		end
	end
	if not position then
		local angle
		if typeof(shot.Toward) == "Vector3" then
			angle = math.atan2(shot.Toward.Z, shot.Toward.X) + (math.random() - 0.5) * 1.2
		else
			angle = math.random() * TAU
		end
		position = Vector3.new(cam.X + math.cos(angle) * d, height, cam.Z + math.sin(angle) * d)
	end
	if playAt(key, position) and shot.NotWanted then
		shots[#shots].notWanted = true -- (playAt has just added it at the end)
	end
end

-- hot = you are wanted (player attribute Heat above 0).
local function scheduleShots(clock, area, cam, hot)
	if not area or not area.Shots then
		return
	end
	for key, rate in pairs(area.Shots) do
		local shot = Config.Shots[key]
		if shot then
			local mult = type(rate) == "number" and rate or 0
			if night then
				mult *= shot.NightRate or 1
			end
			if raining then
				mult *= shot.RainRate or 1
			end
			if hot and shot.NotWanted then
				mult = 0 -- in a chase a siren is the warning that a real police car is near: none of ours
			end
			if mult > 0 then
				local at = shotNext[key]
				if not at then
					shotNext[key] = clock + rand(shot.Every) / mult * 0.5 -- the first one comes a little sooner
				elseif clock >= at then
					shotNext[key] = clock + rand(shot.Every) / mult
					-- (Quiet: somebody else already plays this sound here; the timer runs on all the same)
					local q = shot.Quiet
					if not (q and cam.X >= q[1] and cam.X <= q[2] and cam.Z >= q[3] and cam.Z <= q[4]) then
						fireShot(shot, cam)
					end
				end
			else
				-- Not allowed right now (night, rain, wanted): a fresh timer when it is again, so no
				-- siren sounds the very moment you lose the police.
				shotNext[key] = nil
			end
		end
	end
end

-- Fixed emitters: [index into Config.Emitters] = { part, sound, def, gain }.
local emitters = {}

local function updateEmitters(dt, cam, inHome)
	for i, e in ipairs(Config.Emitters) do
		local rec = emitters[i]
		local timeOk = e.When == nil or (e.When == "Night") == night
		local want = (not inHome and timeOk and (e.At - cam).Magnitude < e.Range) and 1 or 0
		if want > 0 and not rec then
			local part = Instance.new("Part")
			part.Name = "Emitter_" .. tostring(e.Sound)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			part.Size = Vector3.new(1, 1, 1)
			part.CFrame = CFrame.new(e.At)
			part.Parent = lifeFolder
			local s, def = makeSound(e.Sound, part)
			if s then
				s.Looped = true
				rec = { part = part, sound = s, def = def, gain = 0 }
			else
				part:Destroy()
				rec = { dead = true }
			end
			emitters[i] = rec
		end
		if rec and not rec.dead then
			local s = rec.sound
			if want > 0 and not s.IsLoaded then
				want = 0 -- wait for the track: its length is needed to start it in the right place (below)
			end
			local step = dt / math.max(MIX.EmitterFade, 0.05)
			rec.gain = want > rec.gain and math.min(want, rec.gain + step) or math.max(want, rec.gain - step)
			if rec.gain > 0 then
				s.Volume = (rec.def.Volume or 0.3) * rec.gain * duckLevel
				if not s.IsPlaying then
					-- A speaker that has been playing all along: start where the song would have got to by
					-- now (the server clock, so every player hears the same bar), not from its first note
					-- every time you come back into range. (Play keeps a TimePosition set by a script.)
					local length = s.TimeLength
					if length > 1 then
						s.TimePosition = Workspace:GetServerTimeNow() % length
					end
					s:Play()
				end
			elseif s.IsPlaying then
				s:Stop()
			end
		end
	end
end

------------------------------------------------------------------ the area card

local cardGui, card, nameLabel, kindLabel, rule, nameStroke, kindStroke
local cardRest = UDim2.new() -- where the card comes to rest (layoutCard)
local cardToken = 0 -- bumped by every new card (and by hiding), so stale fade-outs do nothing
local cardBusyUntil = 0 -- os.clock() when the card showing now is gone
local cardTweens = {}
local Hud -- HUDController, found on first use (false = not there)

-- HUD pieces the card never appears on top of while they are showing (paths under PlayerGui, the way
-- SoundClient's TITLE.CLEAR and MinimapClient's KEEP_OUT list them; a missing or hidden piece is
-- skipped). Only looked at when a card is about to show.
local CARD_CLEAR = {
	-- beside and above the car cluster, and down the right edge of a phone: the side-column tiles (the
	-- cop's TASER / SPIKES, END SHIFT, OUTFIT), the open phone (it is drawn over us, and would leave only
	-- the tail of the name sticking out), the seated hint, the driving key strip, the gun buttons and
	-- ammo counter, the offer and dealer cards
	{ "LawUI", "Taser" }, { "LawUI", "Spikes" }, { "ActivityUI", "EndShift" }, { "WardrobeUI", "Open" },
	{ "Phone", "Body" }, { "Interact", "GetOutHint" }, { "DriveUI", "ControlsHint" },
	{ "CombatHUD", "Ammo" }, { "CombatHUD", "Fire" }, { "CombatHUD", "Aim" }, { "CombatHUD", "Reload" },
	{ "CombatHUD", "Weapon" }, { "CombatHUD", "GunHint" }, { "CombatHUD", "WeaponList" }, { "CombatHUD", "Stamp" },
	{ "Offer", "Card" }, { "DealerCard", "Card" },
	-- The car's name on getting in uses both of our spots (above the cluster; top centre on a phone).
	-- DriveUI steps aside for a card that is already up; the other way round, the area card waits for
	-- the name to fade, or it would knock a name that is showing out of its place. (A name still waiting
	-- for its own spot is not Visible, so the two can never wait for each other.)
	{ "DriveUI", "CarName" },
	-- top centre (the phone's second spot): the radio's station name and everything it keeps clear of
	{ "Radio", "StationTitle" }, { "Tutorial", "Next" }, { "Objective", "Banner" }, { "Objective", "Escape" },
	{ "Mission", "Banner" }, { "BigScore", "Goal" }, { "BigScore", "Status" },
	{ "Crew", "CrewInvite" }, { "GPS", "Route" }, { "ActivityUI", "Timer" },
	{ "ActivityUI", "Checkpoint" }, { "ActivityUI", "Job" }, { "ActivityUI", "RacePreview" },
	{ "ActivityUI", "TurnCue" }, { "ActivityUI", "WrongWay" }, { "ActivityUI", "Countdown" }, { "ActivityUI", "Finish" },
	{ "ActivityUI", "Finish" }, { "ActivityUI", "DriftTeach" }, { "ActivityUI", "DriftScore" },
	{ "ActivityUI", "DriftStamp" },
}

local function cardFont()
	local ok, font = pcall(function()
		return Font.new(Font.fromEnum(Enum.Font[CARD.Font]).Family, Enum.FontWeight[CARD.Weight or "Bold"])
	end)
	return ok and font or Theme.Font.Display
end

local function screenSize()
	local size = cardGui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		local camera = Workspace.CurrentCamera
		if camera then
			size = camera.ViewportSize
		end
	end
	return size
end

-- A Theme zone on this screen, in pixels from the top-left: left, top, right, bottom.
local function zoneRect(name, touch, view)
	local z = Theme.Zone(name, touch)
	local w = z.Size.X.Scale * view.X + z.Size.X.Offset
	local h = z.Size.Y.Scale * view.Y + z.Size.Y.Offset
	local left = z.Pos.X.Scale * view.X + z.Pos.X.Offset - z.Anchor.X * w
	local top = z.Pos.Y.Scale * view.Y + z.Pos.Y.Offset - z.Anchor.Y * h
	return left, top, left + w, top + h
end

-- Is this GuiObject on screen: it and everything above it visible, inside an enabled ScreenGui?
local function onScreen(obj)
	local o = obj
	while o and not o:IsA("LayerCollector") do
		if o:IsA("GuiObject") and not o.Visible then
			return false
		end
		o = o.Parent
	end
	return o ~= nil and o:IsA("ScreenGui") and o.Enabled
end

-- HUDController's big moment stamp while one shows: its top and bottom in pixels from the top of the
-- screen, else nil. It is drawn with no name to look up, so ask HUDController (as SoundClient does).
local function stampBand(view, touch)
	if Hud == nil then
		local module = script.Parent:FindFirstChild("HUDController")
		local ok, found = false, nil
		if module then
			ok, found = pcall(require, module)
		end
		Hud = ok and type(found) == "table" and found or false
	end
	if not Hud or type(Hud.StampTop) ~= "function" then
		return nil, nil
	end
	local ok, top, bottom = pcall(Hud.StampTop)
	if not ok or type(top) ~= "number" then
		return nil, nil
	end
	if type(bottom) ~= "number" then
		local z = Theme.Zone("Stamp", touch) -- (the stamp fills its zone)
		bottom = top + z.Size.Y.Scale * view.Y + z.Size.Y.Offset
	end
	return top, bottom
end

-- Is this rectangle of the screen (pixels from the top-left corner) free of everything in CARD_CLEAR
-- and of HUDController's stamp right now?
local function spotClear(left, top, right, bottom, view, touch)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		-- (AbsolutePosition starts under the top bar whatever IgnoreGuiInset says: measure from our own corner)
		local origin = cardGui.AbsolutePosition
		for _, path in ipairs(CARD_CLEAR) do
			local screen = playerGui:FindFirstChild(path[1])
			local obj = screen and screen:FindFirstChild(path[2])
			if obj and obj:IsA("GuiObject") and onScreen(obj) then
				local p, s = obj.AbsolutePosition, obj.AbsoluteSize
				local x, y = p.X - origin.X, p.Y - origin.Y
				if x < right and x + s.X > left and y < bottom and y + s.Y > top then
					return false
				end
			end
		end
	end
	local stampTop, stampBottom = stampBand(view, touch)
	if stampTop and stampTop < bottom and stampBottom > top then
		local zoneLeft, _, zoneRight = zoneRect("Stamp", touch, view)
		if zoneLeft < right and zoneRight > left then
			return false
		end
	end
	return true
end

-- Size the card for this device and find where it rests: the first spot (see the header) that is free
-- right now. force = take the first spot even when none is free (a card somebody asked for). Returns
-- false, changing nothing, when there is no room. Runs at every show, so a turned phone or a resized
-- window is always right.
local function layoutCard(force)
	local view = screenSize()
	local touch = Theme.IsTouch()
	local dims = touch and CARD.Touch or CARD.Pc
	local nameSize = dims.Name
	if dims.NameGrow and dims.NameMax then
		nameSize = math.clamp(math.floor(view.Y * dims.NameGrow), dims.Name, math.max(dims.Name, dims.NameMax))
	end
	local nameH = math.ceil(nameSize * (CARD.LineHeight or 1.5))
	local kindH = dims.Kind + 4
	local height = nameH + 6 + kindH
	local width = math.max(120, math.min(dims.Width, math.floor(view.X * 0.6)))
	local gap = CARD.Gap

	-- The spots, best first: { anchor x, anchor y, x, y (pixels from the top-left corner), text alignment }.
	local spots = {}
	if not touch then
		local _, cornerTop, cornerRight = zoneRect("Corner", false, view)
		local bLeft, bTop, _, bBottom = zoneRect("Buttons", false, view)
		local bottom = math.floor(cornerTop - gap)
		-- Above the cluster, in line with its right edge. Not in a window too short for the card between
		-- the Buttons zone (PHONE, CAR) and the cluster.
		if not (bottom - height < bBottom + gap and bottom > bTop - gap) then
			table.insert(spots, { 1, 1, math.floor(cornerRight), bottom, Enum.TextXAlignment.Right })
		end
		-- The same height, left of the Buttons zone and the side column under it (TASER, SPIKES), and of
		-- the key caps that sit 6 px to the left of those tiles (28 px wide: P, T, G).
		table.insert(spots, { 1, 1, math.floor(bLeft - 34 - gap), bottom, Enum.TextXAlignment.Right })
	else
		local _, _, bRight, bBottom = zoneRect("Buttons", true, view)
		local top = math.floor(bBottom + gap)
		local character = player.Character
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		local floor
		if hum and hum.SeatPart then
			floor = view.Y * 0.48 - 20 -- DriveUI's pedal block: a 0.52 x height square, 20 px in from the corner
		else
			floor = view.Y - (math.min(view.X, view.Y) <= 500 and 90 or 210) -- the top of Roblox's jump button
		end
		if floor - gap - top >= height then
			table.insert(spots, { 1, 0, math.floor(bRight), top, Enum.TextXAlignment.Right })
		end
		local _, _, _, bannerBottom = zoneRect("Banner", true, view)
		table.insert(spots, { 0.5, 0, math.floor(view.X / 2), math.floor(bannerBottom + gap), Enum.TextXAlignment.Center })
	end
	local spot = nil
	for _, s in ipairs(spots) do
		local left, top = s[3] - s[1] * width, s[4] - s[2] * height
		if spotClear(left, top, left + width, top + height, view, touch) then
			spot = s
			break
		end
	end
	if not spot then
		if not force then
			return false
		end
		spot = spots[1]
	end

	card.Size = UDim2.fromOffset(width, height)
	nameLabel.Size = UDim2.new(1, 0, 0, nameH)
	nameLabel.TextSize = nameSize
	kindLabel.TextSize = dims.Kind
	kindLabel.Size = UDim2.new(1, 0, 0, kindH)
	kindLabel.Position = UDim2.fromOffset(0, nameH + 6)
	local anchor, align = Vector2.new(spot[1], spot[2]), spot[5]
	cardRest = UDim2.fromOffset(spot[3], spot[4])
	card.AnchorPoint = anchor
	nameLabel.TextXAlignment = align
	kindLabel.TextXAlignment = align
	local ruleX = align == Enum.TextXAlignment.Right and 1 or 0.5
	rule.AnchorPoint = Vector2.new(ruleX, 0)
	rule.Position = UDim2.new(ruleX, 0, 0, nameH + 1)
	return true
end

local function setCardAlpha(alpha) -- 0 = fully shown, 1 = gone
	nameLabel.TextTransparency = alpha
	kindLabel.TextTransparency = 0.1 + 0.9 * alpha
	rule.BackgroundTransparency = alpha
	if nameStroke then
		nameStroke.Transparency = 0.45 + 0.55 * alpha
	end
	if kindStroke then
		kindStroke.Transparency = 0.45 + 0.55 * alpha
	end
end

local function stopCardTweens()
	for _, t in ipairs(cardTweens) do
		t:Cancel()
	end
	table.clear(cardTweens)
end

local function tweenCard(alpha, seconds)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function go(obj, props)
		local t = TweenService:Create(obj, info, props)
		table.insert(cardTweens, t)
		t:Play()
	end
	go(nameLabel, { TextTransparency = alpha })
	go(kindLabel, { TextTransparency = 0.1 + 0.9 * alpha })
	go(rule, { BackgroundTransparency = alpha })
	if nameStroke then
		go(nameStroke, { Transparency = 0.45 + 0.55 * alpha })
	end
	if kindStroke then
		go(kindStroke, { Transparency = 0.45 + 0.55 * alpha })
	end
end

local function hideCard()
	if not card then
		return
	end
	cardToken += 1
	stopCardTweens()
	card.Visible = false
	cardBusyUntil = 0
end

-- force = show it even when no spot is free (layoutCard); otherwise false means "no room right now".
local function showCard(title, subtitle, hold, force)
	if not card then
		return false
	end
	-- A card still on screen is cut off before the new one is laid out (the labels are shared).
	cardToken += 1
	local token = cardToken
	stopCardTweens()
	card.Visible = false
	cardBusyUntil = 0
	if not layoutCard(force) then
		return false
	end
	nameLabel.Text = title
	kindLabel.Text = subtitle or ""
	rule.Visible = CARD.Accent ~= false and subtitle ~= nil and subtitle ~= ""
	setCardAlpha(1)
	-- Right-aligned, it drifts in from the right as it fades in; centred, it only fades.
	local slide = card.AnchorPoint.X == 1 and CARD.Slide or 0
	card.Position = cardRest + UDim2.fromOffset(slide, 0)
	card.Visible = true
	tweenCard(0, CARD.FadeIn)
	local drift = TweenService:Create(card, TweenInfo.new(CARD.FadeIn + 0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = cardRest })
	table.insert(cardTweens, drift)
	drift:Play()
	hold = hold or CARD.Hold
	cardBusyUntil = os.clock() + CARD.FadeIn + hold + CARD.FadeOut
	task.delay(CARD.FadeIn + hold, function()
		if token ~= cardToken then
			return
		end
		stopCardTweens()
		tweenCard(1, CARD.FadeOut)
		task.delay(CARD.FadeOut, function()
			if token == cardToken then
				card.Visible = false
			end
		end)
	end)
	return true
end

function AmbienceClient.ShowCard(title, subtitle, hold)
	if type(title) ~= "string" or title == "" or player:GetAttribute("TitleScreen") == true then
		return false
	end
	if type(subtitle) ~= "string" then
		subtitle = nil
	end
	hold = tonumber(hold)
	if hold and hold == hold then
		hold = math.clamp(hold, 0.5, 15)
	else
		hold = nil
	end
	return showCard(title, subtitle, hold, true)
end

local function buildCard()
	cardGui = Instance.new("ScreenGui")
	cardGui.Name = "AreaName"
	cardGui.ResetOnSpawn = false
	cardGui.IgnoreGuiInset = true -- (Theme's zones assume it)
	-- Under the other HUD layers (as the Coast Feed's cards are): the card is only flavour, so a button,
	-- a banner or a stamp that turns up while it shows is drawn over it, never the other way round.
	cardGui.DisplayOrder = -1
	cardGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	cardGui.Parent = player:WaitForChild("PlayerGui")

	-- Labels only: the card never takes a tap or a click.
	card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundTransparency = 1
	card.Visible = false
	card.Parent = cardGui

	nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.FontFace = cardFont()
	nameLabel.TextColor3 = Theme.Color.Text
	-- A fixed size (layoutCard sets it): TextScaled drew the name tiny in a play test.
	nameLabel.TextScaled = false
	nameLabel.TextSize = CARD.Pc.Name
	nameLabel.TextWrapped = false
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = ""
	nameStroke = Theme.Shadow(nameLabel, 1.5)
	nameLabel.Parent = card

	-- A short pink rule between the two lines (the brand accent, used sparingly).
	rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.Size = UDim2.fromOffset(34, 2)
	rule.BackgroundColor3 = Theme.Color.Brand
	rule.BorderSizePixel = 0
	rule.Parent = card

	kindLabel = Instance.new("TextLabel")
	kindLabel.Name = "Kind"
	kindLabel.Text = ""
	Theme.Text(kindLabel, CARD.Pc.Kind, "Display")
	kindStroke = kindLabel:FindFirstChild("Shadow")
	kindLabel.Parent = card
	setCardAlpha(1)
end

-- Area card logic (LOGIC_STEP): a new area, settled in, cooldown over, the card free, room on the
-- screen -> show it. Anything in the way just means "not yet": it is tried again at the next step, for
-- as long as you stay in that area.
local candidate, candidateSince = nil, 0
local shownArea = nil
local nextAreaCard = 0
local lastRootPos = nil -- where you were at the last step (teleports show up as a jump)
local calmAt = 0 -- os.clock() before which no area card shows: you have just been teleported

local function areaCardTick(clock)
	local root = rootPart()
	if not root or not card then
		return
	end
	local pos = root.Position
	-- A respawn, an arrest, a home's door: the screen is busy with its own fade or stamp for a moment.
	if lastRootPos and (pos - lastRootPos).Magnitude > JUMP then
		calmAt = clock + (CARD.AfterJump or 0)
	end
	lastRootPos = pos
	local key = areaKeyAt(pos.X, pos.Z)
	if not key then
		return -- in a gap between rectangles, or far off the map (a home's inside): nothing changes
	end
	if key ~= candidate then
		candidate, candidateSince = key, clock
	end
	if candidate == shownArea or clock - candidateSince < CARD.Settle or clock < nextAreaCard
		or clock < cardBusyUntil or clock < calmAt then
		return
	end
	if player:GetAttribute("TitleScreen") == true or player:GetAttribute("InHome") == true then
		return
	end
	local hum = root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health <= 0 then
		return
	end
	local area = Config.Areas[candidate]
	if not area then
		shownArea = candidate -- (a rectangle naming an area that isn't in Config.Areas: nothing to show)
		return
	end
	if showCard(area.Name, area.Kind, nil, false) then
		shownArea = candidate
		nextAreaCard = clock + CARD.Cooldown
	end
end

------------------------------------------------------------------ background life: models

local moveParts, moveCFrames = {}, {} -- reused every frame (table.clear keeps their room)
local moveCount = 0
local frame = 0
local allRigs = {} -- every mover (not the birds): night lights, blinking, sounds
local movers = {} -- [name] = rig
local target -- the searchlight's invisible ground target (a one-part rig)
local beam, spot -- the helicopter's searchlight Beam and the SpotLight on the target
local gliders = {} -- the pelican V
local glideState = {} -- banking state shared by the V

local function newRig(name)
	local model = Instance.new("Model")
	model.Name = name
	return {
		model = model, parts = {}, offsets = {}, shown = false, settled = false,
		fresh = false, -- shown since it was last placed: its parts are still where they were left (showRig)
		lights = {}, strobes = {}, slot = math.random(0, 2),
	}
end

-- One anchored, untouchable part on a rig. offset = its place relative to the rig's root CFrame.
local function addPart(rig, name, size, offset, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or PLAIN
	p.Parent = rig.model
	local i = #rig.parts + 1
	rig.parts[i] = p
	rig.offsets[i] = offset
	return p, i
end

-- A part that glows nightColor at night (and is plain dayColor by day).
local function addLight(rig, part, nightColor)
	table.insert(rig.lights, { part = part, dayColor = part.Color, dayMaterial = part.Material, nightColor = nightColor })
end

-- A part (in its own colour) that shows for a moment every period seconds at night: a strobe, a beacon.
local function addStrobe(rig, part, period, offset)
	part.Transparency = 1
	table.insert(rig.strobes, { part = part, period = period, offset = offset, on = false })
end

local function showRig(rig, on)
	if rig.shown == on then
		return
	end
	rig.shown = on
	-- Its parts are still where they were when it was hidden (or at the world's origin, the first
	-- time): it has to be placed this very frame, however far away it is (due).
	rig.fresh = on
	rig.model.Parent = on and lifeFolder or nil
	if not on and rig.sound and rig.sound.IsPlaying then
		rig.sound:Stop()
	end
end

-- Day-only / night-only movers switch only while far from the camera, so nothing pops in or out in
-- view. The very first call (joining) switches at once.
local function setShown(rig, want, cam)
	if rig.shown == want then
		rig.settled = true
		return
	end
	if rig.settled and rig.lastPos and (rig.lastPos - cam).Magnitude < LIFE.HideBeyond then
		return
	end
	rig.settled = true
	showRig(rig, want)
end

-- Queue every part of a rig for this frame's BulkMoveTo.
local function place(rig, cf)
	local parts, offsets = rig.parts, rig.offsets
	for i = 1, #parts do
		moveCount += 1
		moveParts[moveCount] = parts[i]
		moveCFrames[moveCount] = cf * offsets[i]
	end
	rig.lastPos = cf.Position
	rig.fresh = false
end

-- Set a rig's parts right away (outside the frame's batch: a flock appearing between frames).
local function placeNow(rig, cf)
	for i, p in ipairs(rig.parts) do
		p.CFrame = cf * rig.offsets[i]
	end
	rig.lastPos = cf.Position
	rig.fresh = false
end

-- Far movers move every third frame (each on its own frame of the three). Not one that has only just
-- been shown: skipping its first frame would draw it for a frame or two where it was left.
local function due(rig, cam)
	if rig.fresh then
		return true
	end
	if rig.lastPos and (frame + rig.slot) % 3 ~= 0 and (rig.lastPos - cam).Magnitude > LIFE.FarUpdate then
		return false
	end
	return true
end

-- Lean into turns: roll toward the inside of the curve, up to maxDeg when turning at `full` radians a
-- second. Smoothed, so a path's corners never snap.
local function bankFor(rig, dir, clock, maxDeg, full)
	local prev = rig.prevDir
	local dt = clock - (rig.bankT or clock)
	rig.bankT = clock
	rig.prevDir = dir
	local want = 0
	if prev and dt > 1e-4 then
		local right = Vector3.new(-prev.Z, 0, prev.X)
		local rate = (dir - prev):Dot(right) / dt -- > 0 turning right
		want = -math.clamp(rate / full, -1, 1) * math.rad(maxDeg) -- (a negative roll dips the right wing)
	end
	local roll = rig.roll or 0
	roll += (want - roll) * math.min(1, dt * 3)
	rig.roll = roll
	return roll
end

-- Paths. ellipseAt: a point and the unit heading on an ellipse (radius = Vector2 x / z half-axes).
local function ellipseAt(centre, radius, theta)
	local c, s = math.cos(theta), math.sin(theta)
	local pos = Vector3.new(centre.X + radius.X * c, centre.Y, centre.Z + radius.Y * s)
	local dir = Vector3.new(-radius.X * s, 0, radius.Y * c).Unit
	return pos, dir
end

-- stadiumAt: a loop of two legs along Z (at xs[1] going +Z, at xs[2] going -Z) joined by half-circles at
-- zs[2] and zs[1]. s = studs along the loop (any number). Returns x, z and the unit heading dx, dz.
local function stadiumAt(xs, zs, s)
	local r = (xs[2] - xs[1]) / 2
	local leg = zs[2] - zs[1]
	local half = math.pi * r
	s = s % (2 * leg + 2 * half)
	local cx = xs[1] + r
	if s < leg then
		return xs[1], zs[1] + s, 0, 1
	end
	s -= leg
	if s < half then
		local th = math.pi - s / r
		return cx + r * math.cos(th), zs[2] + r * math.sin(th), math.sin(th), -math.cos(th)
	end
	s -= half
	if s < leg then
		return xs[2], zs[2] - s, 0, -1
	end
	s -= leg
	local th = -s / r
	return cx + r * math.cos(th), zs[1] + r * math.sin(th), math.sin(th), -math.cos(th)
end

local function ellipsePerimeter(radius) -- (Ramanujan's approximation)
	local a, b = radius.X, radius.Y
	return math.pi * (3 * (a + b) - math.sqrt((3 * a + b) * (a + 3 * b)))
end

local WHITE = Color3.fromRGB(236, 238, 242)
local DARK = Color3.fromRGB(44, 46, 52)
local GLASS = Color3.fromRGB(40, 52, 72)
local RED_DIM, RED = Color3.fromRGB(110, 40, 40), Color3.fromRGB(255, 40, 40)
local GREEN_DIM, GREEN = Color3.fromRGB(40, 100, 60), Color3.fromRGB(40, 255, 110)
local LAMP_DIM, LAMP = Color3.fromRGB(200, 200, 196), Color3.fromRGB(255, 250, 230)

-- The commuter plane (forward is -Z, root at the middle of the fuselage).
local function buildAirliner()
	local rig = newRig("Airliner")
	local stripe = Theme.Color.Brand
	local body = addPart(rig, "Fuselage", Vector3.new(40, 4.6, 4.6), ALONG_Z, WHITE, nil, Enum.PartType.Cylinder)
	addPart(rig, "Nose", Vector3.new(4.6, 4.6, 4.6), CFrame.new(0, 0, -20), WHITE, nil, Enum.PartType.Ball)
	addPart(rig, "Stripe", Vector3.new(4.7, 0.5, 34), CFrame.new(0, -0.5, 1), stripe)
	addPart(rig, "Windows", Vector3.new(4.66, 0.45, 30), CFrame.new(0, 0.9, -1), GLASS)
	addPart(rig, "Wing", Vector3.new(44, 0.6, 6), CFrame.new(0, -1.2, 1), WHITE)
	addPart(rig, "Tailplane", Vector3.new(15, 0.4, 3.4), CFrame.new(0, 0.8, 18), WHITE)
	addPart(rig, "Fin", Vector3.new(0.5, 7, 4.6), CFrame.new(0, 5.6, 17.5), stripe)
	for _, x in ipairs({ -8, 8 }) do
		addPart(rig, "Engine", Vector3.new(5.5, 2, 2), CFrame.new(x, -2.2, -1) * ALONG_Z, Color3.fromRGB(200, 204, 212), nil, Enum.PartType.Cylinder)
	end
	addLight(rig, (addPart(rig, "NavLeft", Vector3.new(0.7, 0.4, 0.7), CFrame.new(-22.2, -1.2, 1), RED_DIM)), RED)
	addLight(rig, (addPart(rig, "NavRight", Vector3.new(0.7, 0.4, 0.7), CFrame.new(22.2, -1.2, 1), GREEN_DIM)), GREEN)
	addStrobe(rig, (addPart(rig, "Strobe", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 9.4, 18.5), Color3.new(1, 1, 1), NEON)), 1.3, 0)
	addStrobe(rig, (addPart(rig, "Beacon", Vector3.new(0.7, 0.4, 0.7), CFrame.new(0, -2.5, 2), RED, NEON)), 1.0, 0.5)
	rig.sound, rig.soundDef = makeSound("Airliner", body)
	return rig
end

-- A text side of the banner (readable from that side).
local function bannerFace(part, face, text)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Banner" .. face.Name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 8
	gui.LightInfluence = 1
	gui.MaxDistance = 1400
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Theme.Font.Display
	label.TextColor3 = Theme.Color.Brand
	label.Text = text
	label.Parent = gui
	gui.Parent = part
end

-- The little banner-towing prop plane (forward is -Z).
local function buildBannerPlane()
	local rig = newRig("BannerPlane")
	local paint = Color3.fromRGB(246, 214, 92)
	local body = addPart(rig, "Fuselage", Vector3.new(13, 2.2, 2.2), ALONG_Z, paint, nil, Enum.PartType.Cylinder)
	addPart(rig, "Cowl", Vector3.new(2.2, 2.2, 2.2), CFrame.new(0, 0, -6.5), DARK, nil, Enum.PartType.Ball)
	addPart(rig, "Canopy", Vector3.new(1.9, 1.1, 2.6), CFrame.new(0, 0.9, -3.4), GLASS, Enum.Material.Glass)
	addPart(rig, "Wing", Vector3.new(17, 0.35, 2.6), CFrame.new(0, 1.3, -1.5), paint)
	addPart(rig, "Tailplane", Vector3.new(6, 0.25, 1.6), CFrame.new(0, 0.3, 6), paint)
	addPart(rig, "Fin", Vector3.new(0.3, 2.4, 1.8), CFrame.new(0, 1.5, 6), Theme.Color.Brand)
	local _, prop = addPart(rig, "Prop", Vector3.new(0.25, 3.6, 0.3), CFrame.new(0, 0, -7.7), DARK)
	rig.propIndex, rig.propBase = prop, rig.offsets[prop]
	addPart(rig, "Towline", Vector3.new(0.12, 0.12, 22), CFrame.new(0, -0.2, 17.5), DARK)
	local banner, bannerIndex = addPart(rig, "Banner", Vector3.new(0.25, 7, 56), CFrame.new(0, -0.6, 56.5), Color3.fromRGB(250, 250, 246))
	rig.bannerIndex, rig.bannerBase = bannerIndex, rig.offsets[bannerIndex]
	local text = type(LIFE.BannerPlane.Text) == "string" and LIFE.BannerPlane.Text or ""
	bannerFace(banner, Enum.NormalId.Left, text)
	bannerFace(banner, Enum.NormalId.Right, text)
	rig.sound, rig.soundDef = makeSound("SmallPlane", body)
	return rig
end

-- The news helicopter (forward is -Z) and the searchlight's ground target. White with gold trim and no
-- red / blue bar, on purpose: it circles every night whether or not anybody is wanted, and a police
-- helicopter overhead would read as "they are after me" (the real ones belong to the wanted system).
local function buildHeli()
	local rig = newRig("NewsHelicopter")
	local trim = Theme.Color.Gold
	local body = addPart(rig, "Body", Vector3.new(5, 4.6, 10), CFrame.new(), WHITE)
	local nose = addPart(rig, "Nose", Vector3.new(4.4, 3.6, 3), CFrame.new(0, 0.2, -6), GLASS, Enum.Material.Glass)
	nose.Transparency = 0.2
	addPart(rig, "Belly", Vector3.new(5.1, 1.2, 10.1), CFrame.new(0, -1.8, 0), trim)
	addPart(rig, "Boom", Vector3.new(1.3, 1.3, 11), CFrame.new(0, 0.9, 10.5), WHITE)
	addPart(rig, "Fin", Vector3.new(0.35, 3.6, 2.2), CFrame.new(0, 2.6, 15.6), trim)
	addPart(rig, "Stabiliser", Vector3.new(4.4, 0.25, 1.4), CFrame.new(0, 1, 14.6), WHITE)
	for _, x in ipairs({ -2.5, 2.5 }) do
		addPart(rig, "Skid", Vector3.new(0.45, 0.45, 11), CFrame.new(x, -3.6, 0), DARK)
	end
	for _, z in ipairs({ -3, 3 }) do
		addPart(rig, "Strut", Vector3.new(5.4, 0.35, 0.35), CFrame.new(0, -3, z), DARK)
	end
	addPart(rig, "Mast", Vector3.new(0.8, 1.2, 0.8), CFrame.new(0, 2.9, 0), DARK)
	local disc = addPart(rig, "RotorDisc", Vector3.new(0.1, 34, 34), CFrame.new(0, 3.6, 0) * UPRIGHT, DARK, nil, Enum.PartType.Cylinder)
	disc.Transparency = 0.94
	local _, a = addPart(rig, "RotorA", Vector3.new(34, 0.18, 1.1), CFrame.new(0, 3.6, 0), DARK)
	local _, b = addPart(rig, "RotorB", Vector3.new(1.1, 0.18, 34), CFrame.new(0, 3.6, 0), DARK)
	local _, t = addPart(rig, "TailRotor", Vector3.new(0.15, 3.6, 0.5), CFrame.new(0.8, 1.6, 16.2), DARK)
	rig.rotorA, rig.rotorB, rig.tailRotor = a, b, t
	rig.rotorBase, rig.tailBase = rig.offsets[a], rig.offsets[t]
	-- The lights any aircraft carries: a white strobe on the fin and a red beacon under the belly.
	addStrobe(rig, (addPart(rig, "Strobe", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 4.5, 16.6), Color3.new(1, 1, 1), NEON)), 1.1, 0.3)
	addStrobe(rig, (addPart(rig, "Beacon", Vector3.new(0.6, 0.4, 0.6), CFrame.new(0, -2.6, 2), RED, NEON)), 1.4, 0.8)
	local lamp = addPart(rig, "Searchlight", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, -2.8, -3.8), DARK)
	addLight(rig, lamp, LAMP)
	local from = Instance.new("Attachment")
	from.Name = "Lamp"
	from.Position = Vector3.new(0, -0.6, 0)
	from.Parent = lamp
	rig.sound, rig.soundDef = makeSound("Rotor", body)

	target = newRig("SearchlightTarget")
	local spotPart = addPart(target, "Target", Vector3.new(1, 1, 1), CFrame.new(), Color3.new(1, 1, 1))
	spotPart.Transparency = 1
	local ground = Instance.new("Attachment")
	ground.Name = "Ground"
	ground.Position = Vector3.new(0, -28, 0)
	ground.Parent = spotPart
	spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Range = 40
	spot.Angle = 70
	spot.Brightness = 4
	spot.Color = Color3.fromRGB(225, 236, 255)
	spot.Shadows = false
	spot.Enabled = false
	spot.Parent = spotPart

	beam = Instance.new("Beam")
	beam.Name = "Searchlight"
	beam.Attachment0 = from
	beam.Attachment1 = ground
	beam.Width0 = 1.2
	beam.Width1 = 22
	beam.FaceCamera = true
	beam.Segments = 1
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(Color3.fromRGB(230, 240, 255))
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.92) })
	beam.Enabled = false
	beam.Parent = lamp
	return rig
end

-- The cargo ship (root at the waterline, forward is -Z).
local function buildShip()
	local rig = newRig("CargoShip")
	local navy = Color3.fromRGB(40, 52, 84)
	local hull = addPart(rig, "Hull", Vector3.new(26, 12, 150), CFrame.new(0, -1, 5), navy)
	addPart(rig, "Bow", Vector3.new(18.4, 12, 18.4), CFrame.new(0, -1, -70) * CFrame.Angles(0, math.pi / 4, 0), navy)
	addPart(rig, "Waterline", Vector3.new(26.2, 1.2, 150.2), CFrame.new(0, 0.4, 5), Color3.fromRGB(150, 50, 46))
	addPart(rig, "Deck", Vector3.new(24, 0.4, 148), CFrame.new(0, 5.2, 5), Color3.fromRGB(110, 112, 116))
	local boxes = {
		Color3.fromRGB(178, 70, 52), Color3.fromRGB(52, 96, 150), Color3.fromRGB(60, 128, 84),
		Color3.fromRGB(214, 128, 48), Color3.fromRGB(130, 130, 128),
	}
	local heights = { 8, 6, 9, 7, 8 }
	for i, z in ipairs({ -52, -30, -8, 14, 36 }) do
		local h = heights[i]
		addPart(rig, "Containers", Vector3.new(22, h, 18), CFrame.new(0, 5.4 + h / 2, z), boxes[i])
	end
	addPart(rig, "Bridge", Vector3.new(22, 14, 14), CFrame.new(0, 12.4, 58), WHITE)
	addPart(rig, "BridgeWindows", Vector3.new(22.2, 2, 14.2), CFrame.new(0, 16.6, 58), GLASS)
	addPart(rig, "Funnel", Vector3.new(6, 8, 6), CFrame.new(0, 23.4, 63), DARK)
	addPart(rig, "FunnelBand", Vector3.new(6.2, 1.5, 6.2), CFrame.new(0, 24.6, 63), Theme.Color.Brand)
	addPart(rig, "Mast", Vector3.new(0.6, 14, 0.6), CFrame.new(0, 12, -72), DARK)
	addLight(rig, (addPart(rig, "MastLight", Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, 19.4, -72), LAMP_DIM)), LAMP)
	addLight(rig, (addPart(rig, "PortLight", Vector3.new(0.6, 0.6, 0.6), CFrame.new(-11.3, 15, 52), RED_DIM)), RED)
	addLight(rig, (addPart(rig, "StarboardLight", Vector3.new(0.6, 0.6, 0.6), CFrame.new(11.3, 15, 52), GREEN_DIM)), GREEN)
	addLight(rig, (addPart(rig, "SternLight", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 8, 80.4), LAMP_DIM)), LAMP)
	local wake = addPart(rig, "Wake", Vector3.new(20, 0.2, 60), CFrame.new(0, 0.1, 110), Color3.new(1, 1, 1))
	wake.Transparency = 0.55
	local bowWave = addPart(rig, "BowWave", Vector3.new(30, 0.2, 5), CFrame.new(0, 0.1, -84), Color3.new(1, 1, 1))
	bowWave.Transparency = 0.5
	rig.sound, rig.soundDef = makeSound("ShipEngine", hull)
	return rig
end

-- The speedboat (root at the waterline, forward is -Z).
local function buildSpeedboat()
	local rig = newRig("Speedboat")
	local hull = addPart(rig, "Hull", Vector3.new(5, 1.6, 13), CFrame.new(0, 0.4, 0.5), WHITE)
	addPart(rig, "Bow", Vector3.new(3.6, 1.6, 3.6), CFrame.new(0, 0.4, -6) * CFrame.Angles(0, math.pi / 4, 0), WHITE)
	addPart(rig, "Stripe", Vector3.new(5.1, 0.35, 13.1), CFrame.new(0, 0.7, 0.5), Theme.Color.Brand)
	addPart(rig, "Screen", Vector3.new(4.2, 1.1, 0.25), CFrame.new(0, 1.75, -1.5), GLASS, Enum.Material.Glass)
	addPart(rig, "Motor", Vector3.new(1.1, 2.2, 1.3), CFrame.new(0, 0.6, 7.6), DARK)
	addLight(rig, (addPart(rig, "SternLight", Vector3.new(0.4, 0.4, 0.4), CFrame.new(0, 1.5, 7), LAMP_DIM)), LAMP)
	local wake = addPart(rig, "Wake", Vector3.new(4, 0.15, 24), CFrame.new(0, -0.35, 19), Color3.new(1, 1, 1))
	wake.Transparency = 0.5
	rig.sound, rig.soundDef = makeSound("Speedboat", hull)
	return rig
end

-- Birds: six parts each (body, head, beak, two wings, legs), dressed per species (dressBird). Part
-- order matters: the wings (4, 5) and legs (6) are re-posed while flying.
local function wingCF(sp, side, flap, folded) -- side: -1 left, 1 right
	local s = sp.Size
	local span = sp.Span * s
	local shoulder = CFrame.new(side * 0.18 * s, 0.12 * s, -0.05 * s)
	if folded then
		-- Swung back along the body, drooping a little.
		return shoulder * CFrame.Angles(0, -side * 1.25, -side * 0.12) * CFrame.new(side * span * 0.42, 0, 0)
	end
	return shoulder * CFrame.Angles(0, 0, side * flap) * CFrame.new(side * span / 2, 0, 0)
end

local function buildBird()
	local rig = newRig("Bird")
	addPart(rig, "Body", Vector3.one, ALONG_Z, WHITE, nil, Enum.PartType.Cylinder)
	addPart(rig, "Head", Vector3.one, CFrame.new(), WHITE, nil, Enum.PartType.Ball)
	addPart(rig, "Beak", Vector3.one, CFrame.new(), WHITE)
	addPart(rig, "WingL", Vector3.one, CFrame.new(), WHITE)
	addPart(rig, "WingR", Vector3.one, CFrame.new(), WHITE)
	addPart(rig, "Legs", Vector3.one, CFrame.new(), WHITE)
	rig.flapPhase = math.random() * TAU
	rig.phaseOffset = math.random() * 5
	return rig
end

local function dressBird(rig, kind)
	local sp = LIFE.Birds[kind] or LIFE.Birds.Gull
	local s = sp.Size
	local p, o = rig.parts, rig.offsets
	p[1].Size = Vector3.new(1.5 * s, 0.62 * s, 0.62 * s)
	p[1].Color = sp.Body
	p[2].Size = Vector3.new(0.46 * s, 0.46 * s, 0.46 * s)
	p[2].Color = sp.Body
	o[2] = CFrame.new(0, 0.22 * s, -0.8 * s)
	if sp.LongBeak then
		p[3].Size = Vector3.new(0.22 * s, 0.16 * s, 1.1 * s)
		o[3] = CFrame.new(0, 0.12 * s, -1.45 * s)
	else
		p[3].Size = Vector3.new(0.12 * s, 0.1 * s, 0.42 * s)
		o[3] = CFrame.new(0, 0.18 * s, -1.18 * s)
	end
	p[3].Color = sp.Beak
	for i = 4, 5 do
		p[i].Size = Vector3.new(sp.Span * s, 0.07 * s, 0.55 * s)
		p[i].Color = sp.Wing
	end
	o[4], o[5] = wingCF(sp, -1, 0, true), wingCF(sp, 1, 0, true)
	local legH = sp.Legs and 1.1 * s or 0
	p[6].Size = Vector3.new(0.1 * s, math.max(legH, 0.05), 0.1 * s)
	p[6].Color = sp.Legs or sp.Body
	p[6].Transparency = sp.Legs and 0 or 1
	rig.legsPerch = CFrame.new(0, -0.31 * s - legH / 2, 0.1 * s)
	rig.legsFly = CFrame.new(0, -0.15 * s, 0.75 * s + legH / 2) * CFrame.Angles(math.pi / 2, 0, 0) -- trailing behind
	o[6] = rig.legsPerch
	rig.sp = sp
	rig.lift = 0.31 * s + legH -- ground to the middle of the body
end

local function buildLife()
	movers.Airliner = buildAirliner()
	movers.BannerPlane = buildBannerPlane()
	movers.Heli = buildHeli()
	movers.Ship = buildShip()
	movers.Speedboat = buildSpeedboat()
	ship = movers.Ship
	for _, rig in pairs(movers) do
		table.insert(allRigs, rig)
	end
	local cfg = LIFE.Gliders
	for _ = 1, math.max(cfg.Count, 0) do
		local b = buildBird()
		dressBird(b, cfg.Kind)
		b.offsets[6] = b.legsFly
		table.insert(gliders, b)
	end
end

------------------------------------------------------------------ background life: movement

local heli = { state = "off" } -- "off" | "in" | "circle" | "out", plus the legs' ends and times
local speedboatPeriod = 60

local function moveAirliner(now, clock, cam)
	local rig = movers.Airliner
	local cfg = LIFE.Airliner
	setShown(rig, true, cam)
	if not due(rig, cam) then
		return
	end
	local pos, dir = ellipseAt(cfg.Centre, cfg.Radius, TAU * ((now % cfg.Period) / cfg.Period))
	local roll = bankFor(rig, dir, clock, cfg.Bank, 0.04)
	place(rig, CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, roll))
end

local function moveBannerPlane(now, clock, cam)
	local rig = movers.BannerPlane
	local cfg = LIFE.BannerPlane
	local x, z, dx, dz = stadiumAt(cfg.X, cfg.Z, now * cfg.Speed)
	local pos = Vector3.new(x, cfg.Height, z)
	rig.lastPos = pos
	setShown(rig, not night, cam)
	if not rig.shown or not due(rig, cam) then
		return
	end
	local dir = Vector3.new(dx, 0, dz)
	local roll = bankFor(rig, dir, clock, 18, 0.25)
	rig.offsets[rig.propIndex] = rig.propBase * CFrame.Angles(0, 0, clock * 38)
	rig.offsets[rig.bannerIndex] = rig.bannerBase * CFrame.Angles(0, math.sin(clock * 2.7) * 0.04, math.sin(clock * 1.9) * 0.05)
	place(rig, CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, 0, roll))
end

local function heliCirclePos(cfg, angle)
	return Vector3.new(cfg.Centre.X + math.cos(angle) * cfg.Radius, cfg.Height, cfg.Centre.Z + math.sin(angle) * cfg.Radius)
end

local function setSearchlight(on)
	on = on == true
	if heli.lightOn ~= on then
		heli.lightOn = on
		beam.Enabled = on
	end
	local lamp = on and not perf
	if spot.Enabled ~= lamp then
		spot.Enabled = lamp
	end
end

-- The helicopter: flies in from From along the tangent that meets the circle, circles (angle growing),
-- and at dawn leaves along the tangent that runs back out to From. So it never turns sharply.
local function moveHeli(clock, cam)
	local rig = movers.Heli
	local cfg = LIFE.Heli
	if heli.state == "off" then
		if not night then
			return
		end
		local c, from = cfg.Centre, cfg.From
		local dx, dz = from.X - c.X, from.Z - c.Z
		local d = math.sqrt(dx * dx + dz * dz)
		local base = math.atan2(dz, dx)
		local off = d > cfg.Radius and math.acos(cfg.Radius / d) or 0
		heli.joinAngle, heli.leaveAngle = base + off, base - off
		heli.from, heli.to = from, heliCirclePos(cfg, heli.joinAngle)
		heli.legStart = clock
		heli.legTime = math.max((heli.to - heli.from).Magnitude / cfg.Speed, 1)
		heli.state = "in"
		showRig(rig, true)
		showRig(target, true)
	end
	local pos, dir
	if heli.state == "in" or heli.state == "out" then
		local u = (clock - heli.legStart) / heli.legTime
		if u < 1 then
			pos = heli.from:Lerp(heli.to, u)
			dir = heli.to - heli.from
		elseif heli.state == "in" then
			heli.state = "circle"
			heli.circleStart = clock
			heli.lastTurns = nil
		else
			heli.state = "off"
			setSearchlight(false)
			showRig(rig, false)
			showRig(target, false)
			return
		end
	end
	if heli.state == "circle" then
		local angle = heli.joinAngle + (cfg.Speed / cfg.Radius) * (clock - heli.circleStart)
		pos = heliCirclePos(cfg, angle)
		dir = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		if night then
			heli.lastTurns = nil
		else
			-- Dawn: leave the next time it passes the point whose tangent runs back out to From.
			local turns = (angle - heli.leaveAngle) / TAU
			if heli.lastTurns and math.floor(turns) > math.floor(heli.lastTurns) then
				heli.state = "out"
				heli.from, heli.to = pos, cfg.From
				heli.legStart = clock
				heli.legTime = math.max((heli.to - heli.from).Magnitude / cfg.Speed, 1)
			end
			heli.lastTurns = turns
		end
	end
	-- The searchlight only while circling: it sweeps the streets inside the circle, wandering slowly.
	-- It goes out at once, but comes on only on a frame that also puts its ground target in place
	-- (below), so the beam never points at where the target was left the night before.
	local circling = heli.state == "circle"
	if not circling then
		setSearchlight(false)
	end
	if not due(rig, cam) then
		return -- (far away: where it is was worked out above from the clock, so skipping frames costs nothing)
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	flat = flat.Magnitude > 1e-3 and flat.Unit or (rig.prevDir or Vector3.new(0, 0, -1))
	local roll = bankFor(rig, flat, clock, cfg.Bank, 0.08)
	rig.offsets[rig.rotorA] = rig.rotorBase * CFrame.Angles(0, clock * 21, 0)
	rig.offsets[rig.rotorB] = rig.rotorBase * CFrame.Angles(0, clock * 21 + math.pi / 2, 0)
	rig.offsets[rig.tailRotor] = rig.tailBase * CFrame.Angles(clock * 40, 0, 0)
	place(rig, CFrame.lookAt(pos, pos + flat) * CFrame.Angles(math.rad(-7), 0, roll))
	if circling then
		local c = cfg.Centre
		place(target, CFrame.new(
			pos.X + (c.X - pos.X) * 0.45 + math.sin(clock * 0.37) * 30,
			30,
			pos.Z + (c.Z - pos.Z) * 0.45 + math.cos(clock * 0.29) * 30
		))
		setSearchlight(true)
	end
end

local function moveShip(now, clock, cam)
	local rig = movers.Ship
	local cfg = LIFE.Ship
	setShown(rig, true, cam)
	if not due(rig, cam) then
		return
	end
	local x, z, dx, dz = stadiumAt(cfg.X, cfg.Z, now * cfg.Speed)
	local pos = Vector3.new(x, cfg.Water, z)
	place(rig, CFrame.lookAt(pos, pos + Vector3.new(dx, 0, dz)) * CFrame.Angles(0, 0, math.sin(clock * 0.35) * 0.012))
end

local function moveSpeedboat(now, clock, cam)
	local rig = movers.Speedboat
	local cfg = LIFE.Speedboat
	setShown(rig, true, cam)
	if not due(rig, cam) then
		return
	end
	local pos, dir = ellipseAt(cfg.Centre, cfg.Radius, TAU * ((now % speedboatPeriod) / speedboatPeriod))
	pos = Vector3.new(pos.X, cfg.Water + 0.35 + math.sin(clock * 3.1) * 0.12, pos.Z)
	local roll = bankFor(rig, dir, clock, 9, 0.2)
	-- Bow up a little as it planes, bobbing on the chop.
	place(rig, CFrame.lookAt(pos, pos + dir) * CFrame.Angles(math.rad(5 + math.sin(clock * 2.3) * 1.5), 0, roll))
end

local function moveGliders(now, clock, dt, cam)
	local cfg = LIFE.Gliders
	local x, z, dx, dz = stadiumAt(cfg.X, cfg.Z, now * cfg.Speed)
	local lead = Vector3.new(x, cfg.Height, z)
	local dir = Vector3.new(dx, 0, dz)
	local leadCF = CFrame.lookAt(lead, lead + dir)
	local roll = bankFor(glideState, dir, clock, 14, 0.4)
	-- Far from the camera the V moves every third frame, like the other movers.
	local distant = (lead - cam).Magnitude > LIFE.FarUpdate
	local skip = distant and frame % 3 ~= 0
	local flapDt = distant and dt * 3 or dt
	for i, b in ipairs(gliders) do
		b.lastPos = lead
		setShown(b, not night and (not perf or i <= cfg.PerfCount), cam)
		if b.shown and (not skip or b.fresh) then -- (fresh: just shown, so placed this frame whatever the distance)
			-- A V: the leader, then pairs further back and out on each side.
			local k = math.floor(i / 2)
			local side = i == 1 and 0 or (i % 2 == 0 and 1 or -1)
			local sp = b.sp
			-- A few strong beats now and then, gliding between (each bird on its own beat). The beat's
			-- strength eases up and down: switched in one frame, the wings would snap half open.
			local want = ((clock + i * 0.9) % 7 < 1.6) and 0.6 or 0.05
			local amp = b.amp or want
			amp += (want - amp) * math.min(1, flapDt * 5)
			b.amp = amp
			b.flapPhase += flapDt * sp.Flap * TAU
			local flap = math.sin(b.flapPhase) * amp
			b.offsets[4] = wingCF(sp, -1, flap, false)
			b.offsets[5] = wingCF(sp, 1, flap, false)
			place(b, leadCF * CFrame.new(side * k * 4.5, math.sin(clock * 0.8 + i) * 0.4, k * 5.5) * CFrame.Angles(0, 0, roll))
		end
	end
end

------------------------------------------------------------------ bird flocks

local activeFlocks = {} -- { index, roost, birds, centre, scattered, returnAt }
local flockByIndex = {} -- [roost index] = its flock while it has birds
local pool = {} -- bird rigs not in use
local activeBirds = 0

local function birdCircleAt(b, angle, t)
	return Vector3.new(
		b.centre.X + math.cos(angle) * b.radius,
		b.centre.Y + b.height + math.sin(t * 0.9 + b.phaseOffset) * 1.5,
		b.centre.Z + math.sin(angle) * b.radius
	)
end

-- The whole flock takes off, away from `from`. quiet = no burst of wings (they were already up).
local function scatterFlock(f, from, quiet)
	local clock = os.clock()
	f.scattered = true
	f.returnAt = clock + rand(SCATTER.Return)
	local any = false
	for _, b in ipairs(f.birds) do
		if b.mode == "perched" or b.mode == "landing" then
			any = true
			local wasLanding = b.mode == "landing"
			local start = wasLanding and (b.lastPos or b.spot) or (b.spot + Vector3.new(0, b.lift, 0))
			local away = Vector3.new(b.spot.X - from.X, 0, b.spot.Z - from.Z)
			if away.Magnitude < 0.1 then
				local a = math.random() * TAU
				away = Vector3.new(math.cos(a), 0, math.sin(a))
			else
				away = away.Unit
			end
			b.radius = math.max(rand(SCATTER.Circle), 4)
			b.height = rand(SCATTER.Climb)
			local turn = math.random() < 0.5 and -1 or 1 -- which way round it circles
			b.omega = turn * b.sp.Speed / b.radius
			b.centre = f.centre + Vector3.new((math.random() - 0.5) * 12, 0, (math.random() - 0.5) * 12)
			local exitX, exitZ = b.spot.X + away.X * b.radius, b.spot.Z + away.Z * b.radius
			b.angle0 = math.atan2(exitZ - b.centre.Z, exitX - b.centre.X)
			b.from = start
			b.to = birdCircleAt(b, b.angle0, 0) -- where its circle starts: on the far side from you
			b.dur = 2.2
			-- The climb (a curve from..ctrl..to) ends along the circle's own heading there and at the
			-- circling speed (a curve like this ends at 2 x |to - ctrl| / dur), so the bird runs straight
			-- into its circle with no sharp turn and no jump in speed: steeply up and away first, then
			-- levelling.
			b.ctrl = b.to - Vector3.new(-math.sin(b.angle0) * turn, 0, math.cos(b.angle0) * turn) * (b.sp.Speed * b.dur / 2)
			b.mode = "takeoff"
			b.t0 = clock + (wasLanding and 0 or math.random() * 0.35) -- not all in the same instant
			b.amp = 1 -- the burst off the ground is at full beat at once (moveBird eases every other change)
			b.landAt = nil
			b.offsets[6] = b.legsFly
		elseif b.mode == "circle" then
			b.landAt = nil -- already up: stays up
		end
	end
	if any and not quiet then
		playAt("BirdsScatter", f.centre + Vector3.new(0, 2, 0), 1, true)
	end
end

-- from = where the scare is (the birds fly away from it); default: position.
function AmbienceClient.Scatter(position, radius, from)
	if typeof(position) ~= "Vector3" then
		return
	end
	radius = tonumber(radius) or 30
	if radius ~= radius then
		return
	end
	if typeof(from) ~= "Vector3" then
		from = position
	end
	for _, f in ipairs(activeFlocks) do
		for _, b in ipairs(f.birds) do
			if (b.mode == "perched" or b.mode == "landing") and (b.spot - position).Magnitude < radius then
				scatterFlock(f, from)
				break
			end
		end
	end
end

-- You (on foot, or faster in a car) came too close to a bird on the ground (AUDIO_STEP).
local function checkScatter()
	local root = rootPart()
	if not root or #activeFlocks == 0 then
		return
	end
	local pos = root.Position
	local vel = root.AssemblyLinearVelocity
	if vel.Magnitude > 30 then
		-- A fast car is through a flock before a bird scared at CarRadius has left the ground (26 studs
		-- is a quarter of a second at 100 studs/s; the climb takes two). So what the car will reach in
		-- the next CarLead seconds is scared as well: three spheres along its path, which cover it up to
		-- top speed without scaring flocks beside the road. The birds still flee from the car itself.
		local lead = SCATTER.CarLead or 0.7
		AmbienceClient.Scatter(pos, SCATTER.CarRadius)
		AmbienceClient.Scatter(pos + vel * (lead * 0.5), SCATTER.CarRadius, pos)
		AmbienceClient.Scatter(pos + vel * lead, SCATTER.CarRadius, pos)
	else
		AmbienceClient.Scatter(pos, SCATTER.Radius)
	end
end

local function moveBird(b, clock, dt)
	local mode = b.mode
	if mode == "perched" then
		if b.dirty then
			b.dirty = false
			b.offsets[4], b.offsets[5] = wingCF(b.sp, -1, 0, true), wingCF(b.sp, 1, 0, true)
			b.offsets[6] = b.legsPerch
			place(b, CFrame.new(b.spot + Vector3.new(0, b.lift, 0)) * CFrame.Angles(0, b.yaw, 0))
		end
		return
	end
	local pos, dir, amp
	if mode == "takeoff" or mode == "landing" then
		local x = math.clamp((clock - b.t0) / b.dur, 0, 1)
		local u = x
		if mode == "landing" then
			-- Landing starts at the speed the bird was circling at and eases off to touch down at rest:
			-- u' is `ease` at the start and 0 at the end (ease = 2 is a plain ease-out; for 0.4..2,
			-- u' = (1 - x)(ease + (6 - 3 ease) x) is never negative, so the bird never backs up).
			local a = b.ease or 2
			u = a * x + (3 - 2 * a) * x * x + (a - 2) * x * x * x
		end
		local iu = 1 - u
		pos = b.from * (iu * iu) + b.ctrl * (2 * iu * u) + b.to * (u * u)
		dir = (b.ctrl - b.from) * (2 * iu) + (b.to - b.ctrl) * (2 * u)
		amp = mode == "takeoff" and 1 or 0.75
		if clock - b.t0 >= b.dur then
			if mode == "takeoff" then
				b.mode = "circle"
				b.t0 = clock
			else
				b.mode = "perched"
				b.dirty = true
				local flat = b.lastFlat or Vector3.new(0, 0, -1)
				b.yaw = math.atan2(-flat.X, -flat.Z)
			end
		end
	else -- circle
		local t = clock - b.t0
		local angle = b.angle0 + b.omega * t
		pos = birdCircleAt(b, angle, t)
		local sign = b.omega >= 0 and 1 or -1
		dir = Vector3.new(-math.sin(angle) * sign, 0, math.cos(angle) * sign)
		amp = ((clock + b.phaseOffset) % 5 < 1.2) and 0.7 or 0.12 -- flap now and then, glide between
		if b.landAt and clock >= b.landAt then
			-- Coming home: it carries on along its circle for a moment, sinking, then curves in low to
			-- its own spot (the curve starts along the heading it already has, so again no sharp turn).
			local home = b.spot
			local ahead = b.radius * 0.8
			local ground = home.Y + b.lift
			b.landAt = nil
			b.mode = "landing"
			b.from = pos
			b.ctrl = Vector3.new(pos.X + dir.X * ahead, ground + math.max(pos.Y - ground, 0) * 0.35, pos.Z + dir.Z * ahead)
			b.to = Vector3.new(home.X, ground, home.Z)
			b.t0 = clock
			b.dur = 3
			-- ...and at the speed it already has: a curve like this starts at 2 x |ctrl - from| x ease / dur.
			b.ease = math.clamp(b.sp.Speed * b.dur / math.max(2 * (b.ctrl - b.from).Magnitude, 1), 0.4, 2)
		end
	end
	-- Face along the flight; the climb or dive is clamped so a bird never points straight up or down.
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local fm = flat.Magnitude
	local climb = 0
	if fm > 1e-3 then
		climb = math.clamp(dir.Y / fm, -0.6, 0.6)
		flat = flat / fm
	else
		flat = b.lastFlat or Vector3.new(0, 0, -1)
	end
	b.lastFlat = flat
	local roll = bankFor(b, flat, clock, 22, 0.5)
	b.flapPhase += dt * b.sp.Flap * TAU
	-- The beat's strength eases between gliding and flapping: switched in one frame, the wings would
	-- snap half open or shut. (Only the burst off the ground is instant: scatterFlock sets b.amp.)
	local beat = b.amp or amp
	beat += (amp - beat) * math.min(1, dt * 6)
	b.amp = beat
	local flap = math.sin(b.flapPhase) * beat
	b.offsets[4] = wingCF(b.sp, -1, flap, false)
	b.offsets[5] = wingCF(b.sp, 1, flap, false)
	place(b, CFrame.lookAt(pos, pos + flat + Vector3.new(0, climb, 0)) * CFrame.Angles(0, 0, roll))
end

local function deactivateFlock(i)
	local f = activeFlocks[i]
	for _, b in ipairs(f.birds) do
		showRig(b, false)
		b.mode = nil
		table.insert(pool, b)
		activeBirds -= 1
	end
	table.remove(activeFlocks, i)
	flockByIndex[f.index] = nil
end

local function activateFlock(index, maxBirds, focus)
	local roost = LIFE.Roosts[index]
	if not LIFE.Birds[roost.Kind] then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- Never perch on something that will move off: us, the cars, PedClient's walkers.
	local exclude = { lifeFolder }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	for _, name in ipairs({ "Vehicles", "Peds" }) do
		local moving = Workspace:FindFirstChild(name)
		if moving then
			table.insert(exclude, moving)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true -- land on ground, roofs, decks and water, not on glows or fronds
	local down = Vector3.new(0, -260, 0)
	local rng = Random.new(index * 7919 + 17) -- the same layout every time
	local flock = { index = index, roost = roost, birds = {}, scattered = false, returnAt = 0 }
	local sumY = 0
	for _ = 1, roost.Count do
		-- (every number is drawn even when no bird is free, so the layout never shifts)
		local angle = rng:NextNumber() * TAU
		local r = math.sqrt(rng:NextNumber()) * roost.Spread
		local yaw = rng:NextNumber() * TAU
		if activeBirds < maxBirds then
			local b = table.remove(pool) or buildBird()
			local x, z = roost.At.X + math.cos(angle) * r, roost.At.Z + math.sin(angle) * r
			local origin = Vector3.new(x, roost.At.Y + 120, z)
			local hit = Workspace:Raycast(origin, down, params)
			-- Somebody standing on the spot (another player, any character with a Humanoid): perch on
			-- what is under them, or the bird is left hovering at head height when they walk off.
			for _ = 1, 3 do
				local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
				while model and not model:FindFirstChildOfClass("Humanoid") do
					model = model:FindFirstAncestorOfClass("Model")
				end
				if not model then
					break
				end
				table.insert(exclude, model)
				params.FilterDescendantsInstances = exclude
				hit = Workspace:Raycast(origin, down, params)
			end
			local y = hit and hit.Position.Y or roost.At.Y
			dressBird(b, roost.Kind)
			b.spot = Vector3.new(x, y, z)
			b.yaw = yaw
			b.mode = "perched"
			b.dirty = false
			b.landAt = nil
			b.amp = nil
			b.prevDir, b.roll, b.bankT = nil, 0, nil
			placeNow(b, CFrame.new(b.spot + Vector3.new(0, b.lift, 0)) * CFrame.Angles(0, yaw, 0))
			showRig(b, true)
			b.fresh = false -- (it was put in its place just above, before it could be seen)
			activeBirds += 1
			table.insert(flock.birds, b)
			sumY += y
		end
	end
	if #flock.birds == 0 then
		return
	end
	flock.centre = Vector3.new(roost.At.X, sumY / #flock.birds, roost.At.Z)
	table.insert(activeFlocks, flock)
	flockByIndex[index] = flock
	-- Arriving right among them (spawning there): they are already taking off.
	if focus and flatDistance(focus, flock.centre) < roost.Spread + SCATTER.Radius then
		scatterFlock(flock, focus, true)
	end
end

-- LOGIC_STEP: let far flocks go, bring scattered ones home, give the nearest free roost its birds.
local function updateFlocks(clock, focus)
	local cfg = LIFE.Flocks
	local maxFlocks = perf and cfg.PerfMax or cfg.Max
	local maxBirds = perf and cfg.PerfMaxBirds or cfg.MaxBirds
	for i = #activeFlocks, 1, -1 do
		if i > maxFlocks or flatDistance(focus, activeFlocks[i].centre) > cfg.Activate + 60 then
			deactivateFlock(i)
		end
	end
	for _, f in ipairs(activeFlocks) do
		if f.scattered then
			local up = false
			for _, b in ipairs(f.birds) do
				if b.mode ~= "perched" then
					up = true
					break
				end
			end
			if not up then
				f.scattered = false
			elseif clock >= f.returnAt then
				if flatDistance(focus, f.centre) < SCATTER.LandClear + f.roost.Spread then
					f.returnAt = clock + 6 -- you're still there: another lap
				else
					for _, b in ipairs(f.birds) do
						if b.mode == "circle" and not b.landAt then
							b.landAt = clock + math.random() * 2.5 -- one after another
						end
					end
					f.returnAt = math.huge -- (scattering again sets it anew)
				end
			end
		end
	end
	if #activeFlocks < maxFlocks and activeBirds < maxBirds then
		local best, bestD = nil, cfg.Activate
		for index, roost in ipairs(LIFE.Roosts) do
			if not flockByIndex[index] then
				local d = flatDistance(focus, roost.At)
				if d < bestD then
					best, bestD = index, d
				end
			end
		end
		if best then
			activateFlock(best, maxBirds, focus)
		end
	end
end

------------------------------------------------------------------ night lights, blinking, mover sounds

local function applyNight()
	night = Workspace:GetAttribute("IsNight") == true
	for _, rig in ipairs(allRigs) do
		for _, l in ipairs(rig.lights) do
			l.part.Material = night and NEON or l.dayMaterial
			l.part.Color = night and l.nightColor or l.dayColor
		end
		for _, s in ipairs(rig.strobes) do
			s.on = false
			s.part.Transparency = 1
		end
	end
end

local function blink(clock)
	if not night then
		return
	end
	for _, rig in ipairs(allRigs) do
		if rig.shown then
			for _, s in ipairs(rig.strobes) do
				local on = ((clock + s.offset) % s.period) < 0.09
				if on ~= s.on then
					s.on = on
					s.part.Transparency = on and 0 or 1
				end
			end
		end
	end
end

local function moverSound(rig, cam, inHome)
	local s = rig.sound
	if not s then
		return
	end
	local near = rig.shown and not inHome and rig.lastPos ~= nil
		and (rig.lastPos - cam).Magnitude < (rig.soundDef.MaxDistance or 400) * MIX.MoverRange
	if near then
		s.Volume = (rig.soundDef.Volume or 0.3) * duckLevel
		if not s.IsPlaying then
			s:Play()
		end
	elseif s.IsPlaying then
		s:Stop()
	end
end

------------------------------------------------------------------ the loops

local lastAudio = 0
local lastLogic = 0
local lifeOk, audioOk, logicOk = true, true, true -- a part that errors stops (once, with a warning) instead of spamming

local function moveLife(dt, clock, cam)
	local now = Workspace:GetServerTimeNow()
	table.clear(moveParts)
	table.clear(moveCFrames)
	moveCount = 0
	moveAirliner(now, clock, cam)
	moveBannerPlane(now, clock, cam)
	moveHeli(clock, cam)
	moveShip(now, clock, cam)
	moveSpeedboat(now, clock, cam)
	moveGliders(now, clock, dt, cam)
	for _, f in ipairs(activeFlocks) do
		for _, b in ipairs(f.birds) do
			moveBird(b, clock, dt)
		end
	end
	if moveCount > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	blink(clock)
end

local function audioTick(clock, dt, cam)
	local want = duckWanted(clock)
	if duckLevel > want then
		duckLevel = math.max(want, duckLevel - dt / math.max(MIX.DuckDown, 0.01))
	elseif duckLevel < want then
		duckLevel = math.min(want, duckLevel + dt / math.max(MIX.DuckUp, 0.01))
	end
	local inHome = player:GetAttribute("InHome") == true
	indoors = inHome
	raining = Workspace:GetAttribute("Raining") == true
	local key = areaKeyAt(cam.X, cam.Z)
	if key then
		lastSoundArea = key
	elseif not inHome then
		key = lastSoundArea -- crossing a gap between rectangles (the prison moat): keep what was playing
	end
	local area = key and Config.Areas[key] or nil
	local hot = (tonumber(player:GetAttribute("Heat")) or 0) > 0 -- wanted: no far-off sirens of ours (Shots NotWanted)
	updateBeds(dt, area, inHome)
	updateShots(clock, hot)
	if key ~= shotArea then
		table.clear(shotNext) -- a new area starts its own one-shot timers
		shotArea = key
	end
	if not inHome then
		scheduleShots(clock, area, cam, hot)
	end
	updateEmitters(dt, cam, inHome)
	for _, rig in ipairs(allRigs) do
		moverSound(rig, cam, inHome)
	end
	checkScatter()
end

local function logicTick(clock, cam)
	perf = performanceMode()
	areaCardTick(clock)
	if lifeOk then -- (birds nothing would move are worse than no birds)
		local root = rootPart()
		updateFlocks(clock, root and root.Position or cam)
	end
end

local function step(dt)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local cam = camera.CFrame.Position
	local clock = os.clock()
	frame += 1
	-- (Inside a home, far out past the map, nothing of this can be seen: everything is placed from a
	-- clock, so it is simply back in the right place the frame after you step out.)
	if lifeOk and not indoors then
		local ok, err = pcall(moveLife, dt, clock, cam)
		if not ok then
			lifeOk = false
			warn("[AmbienceClient] background life stopped: " .. tostring(err))
		end
	end
	if audioOk and clock - lastAudio >= AUDIO_STEP then
		local elapsed = math.min(clock - lastAudio, 0.5)
		lastAudio = clock
		local ok, err = pcall(audioTick, clock, elapsed, cam)
		if not ok then
			audioOk = false
			warn("[AmbienceClient] ambience sound stopped: " .. tostring(err))
		end
	end
	if logicOk and clock - lastLogic >= LOGIC_STEP then
		lastLogic = clock
		local ok, err = pcall(logicTick, clock, cam)
		if not ok then
			logicOk = false
			warn("[AmbienceClient] area names and flocks stopped: " .. tostring(err))
		end
	end
end

function AmbienceClient.Init()
	if initialised then
		return
	end
	initialised = true
	night = Workspace:GetAttribute("IsNight") == true
	perf = performanceMode()

	soundFolder = Instance.new("Folder")
	soundFolder.Name = "NCAmbience"
	soundFolder.Parent = SoundService

	lifeFolder = Instance.new("Folder")
	lifeFolder.Name = "NCAmbienceLife"
	lifeFolder.Parent = Workspace
	anchorPart = Instance.new("Part")
	anchorPart.Name = "SoundAnchor"
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.Transparency = 1
	anchorPart.Size = Vector3.new(1, 1, 1)
	anchorPart.CFrame = CFrame.new()
	anchorPart.Parent = lifeFolder

	local ok, err = pcall(buildCard)
	if not ok then
		card = nil
		warn("[AmbienceClient] no area card: " .. tostring(err))
	end
	ok, err = pcall(buildLife)
	if not ok then
		lifeOk = false
		warn("[AmbienceClient] no background life: " .. tostring(err))
	end
	speedboatPeriod = math.max(ellipsePerimeter(LIFE.Speedboat.Radius) / math.max(LIFE.Speedboat.Speed, 1), 1)
	applyNight()
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(applyNight)
	-- The title screen hides every HUD layer (TeamUI); a card already fading in goes at once.
	player:GetAttributeChangedSignal("TitleScreen"):Connect(function()
		if player:GetAttribute("TitleScreen") == true then
			hideCard()
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return AmbienceClient
