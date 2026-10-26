-- Ambience (ModuleScript, ReplicatedStorage.Shared.Config.Ambience)
-- What makes Port Solana feel lived in, for AmbienceClient (everything is local and cheap). Our own names
-- only: no real place, brand or game names anywhere in here.
--   Ambience.Areas      per area: Name (the big script line on the area card), Kind (the small street-type
--                       line under it), Beds = { Day, Night } (keys of Ambience.Sounds; no Beds = none of
--                       ours, e.g. downtown and the beach, where SoundClient already plays the city hum and
--                       the surf) and Shots = { [key of Ambience.Shots] = rate } (distant one-shots heard
--                       there; rate 1 = as often as the shot's Every says, 0.5 = half as often).
--   Ambience.Districts  the map's rectangles { x0, x1, z0, z1 } -> area key (the first match wins). The
--                       first eleven are copied from CityGen.Districts in its order: keep the two in step.
--                       The last four are ours: the piers, the shallows and the causeway, which stand
--                       over the water east of CityGen's land but belong to the land they hang off.
--   Ambience.Sea        open water east of the beach that no rectangle covers counts as this area.
--   Ambience.Card       the area name card: font, timings, sizes, cooldown
--   Ambience.Sounds     every sound AmbienceClient plays (see the note above the table)
--   Ambience.Shots      distant one-shots: which sounds, how often, how far away, from which side
--   Ambience.Emitters   fixed sound sources in the world (a beach speaker, club bass at night)
--   Ambience.Mix        bed cross-fade, one-shot cap, duck speeds, how far beds sit back in the rain
--   Ambience.Dusk       the neon wave at dusk (AmbienceClient.DuskOrder / DuskWave)
--   Ambience.Life       the background movers (planes, news helicopter, ship, speedboat, gliding pelicans), the
--                       bird species and the roosts where flocks sit until you scare them off
-- What SoundClient already plays, so nothing here doubles it: rain and thunder, the surf (east of x 950),
-- beach gulls (east of x 1125, between z -2000 and 800) and the city hum (within 700 studs of downtown).

local Ambience = {}

Ambience.Areas = {
	Downtown = { Name = "Solana Heights", Kind = "DOWNTOWN", Shots = { Siren = 1, Horns = 1 } }, -- bed: SoundClient's city hum
	Beach = { Name = "Flamingo Beach", Kind = "BEACHFRONT", Shots = { Horns = 0.3 } }, -- beds: SoundClient's surf and gulls
	Hills = { Name = "Palm Hills", Kind = "SUBURBS", Beds = { Day = "SuburbDay", Night = "SuburbNight" }, Shots = { Horns = 0.35, Siren = 0.3 } },
	Docks = { Name = "Rustwater Docks", Kind = "PORT DISTRICT", Beds = { Day = "HarborDay", Night = "HarborNight" }, Shots = { Gulls = 1, ShipHorn = 1, Horns = 0.4 } },
	Marina = { Name = "Marina Row", Kind = "WATERFRONT", Beds = { Day = "MarinaDay", Night = "HarborNight" }, Shots = { Gulls = 1, ShipHorn = 0.8 } },
	Glades = { Name = "Gator Glades", Kind = "WETLANDS", Beds = { Day = "GladesDay", Night = "GladesNight" } },
	Island = { Name = "Saltmarsh Island", Kind = "PRISON ISLAND", Beds = { Day = "GladesDay", Night = "GladesNight" }, Shots = { Siren = 0.25 } },
	Key = { Name = "Lighthouse Key", Kind = "THE KEYS", Shots = { ShipHorn = 1 } }, -- beds: SoundClient's surf and gulls
	Sea = { Name = "Solana Bay", Kind = "OPEN WATER", Shots = { Gulls = 0.6, ShipHorn = 1 } }, -- bed: SoundClient's surf (our gulls only off the marina, see Shots.Gulls.Quiet)
}

-- CityGen.Districts, in its order, then four rows of our own: { x0, x1, z0, z1 } (studs; north is -Z).
Ambience.Districts = {
	{ Rect = { -2000, -900, -2000, 850 }, Area = "Glades" }, -- GatorGlades
	{ Rect = { -2000, -1900, 850, 2000 }, Area = "Glades" }, -- GladesSouthWest
	{ Rect = { -950, -900, 850, 2000 }, Area = "Glades" }, -- GladesSouthEast
	{ Rect = { -1900, -950, 1900, 2000 }, Area = "Glades" }, -- GladesSouth
	{ Rect = { -1750, -1100, 1000, 1700 }, Area = "Island" }, -- SaltmarshIsland
	{ Rect = { -900, 1000, -2000, -850 }, Area = "Hills" }, -- PalmHills
	{ Rect = { -900, 1000, -850, 600 }, Area = "Downtown" }, -- SolanaHeights
	{ Rect = { -900, 450, 600, 2000 }, Area = "Docks" }, -- RustwaterDocks
	{ Rect = { 450, 1500, 600, 2000 }, Area = "Marina" }, -- MarinaRow
	{ Rect = { 1000, 1500, -2000, 600 }, Area = "Beach" }, -- FlamingoBeach
	{ Rect = { 2100, 2450, -1550, -1150 }, Area = "Key" }, -- LighthouseKey
	-- Ours, not CityGen's (keep them after its eleven, in this order: the causeway crosses the shallows).
	-- CityGen's land stops at x 1500, but its roads and the art built on them run on out over the water;
	-- without these rows you would read "Solana Bay / OPEN WATER" standing under the Ferris wheel, lose
	-- the marina's bed out on its own piers, and have the bay's card use up the Key's on the way there.
	{ Rect = { 1500, 2100, -1378, -1322 }, Area = "Key" }, -- the causeway (road x 1000..2100 at z -1350, 40 wide): the Key's name as you set off over the water
	{ Rect = { 1500, 1800, -470, -330 }, Area = "Beach" }, -- the Ferris pier and its wheel plaza (x to 1786, z -458..-342)
	{ Rect = { 1500, 1625, -2000, 600 }, Area = "Beach" }, -- the sand running down into the shallows (ShoreSlope, x to 1620)
	{ Rect = { 1500, 1760, 600, 2000 }, Area = "Marina" }, -- the marina's basin: piers and slips (x to 1680), the yacht and its boarding deck (x to 1758)
}
-- The ocean (CityGen's terrain water runs x 1500..2900, z -2400..2400). Home interiors (x 12000+) are
-- outside every rectangle and this one, so they have no area.
Ambience.Sea = { X0 = 1500, X1 = 3000, Z0 = -2500, Z1 = 2500, Area = "Sea" }

Ambience.Card = {
	Font = "Kalam", -- Enum.Font name of the script face (Kalam Bold: a slanted brush-pen hand, readable small)
	Weight = "Bold", -- Enum.FontWeight name
	LineHeight = 1.5, -- the name's box is this many times its text size (a script face has tall loops and tails)
	FadeIn = 0.45, -- seconds
	Hold = 3.1, -- seconds fully shown (about 4.25 s on screen in all)
	FadeOut = 0.7, -- seconds
	Slide = 14, -- pixels the card drifts in from the right while fading in (not when centred)
	Cooldown = 20, -- seconds: at most one area card this often
	Settle = 0.8, -- seconds you must be inside a new area before its card shows (no flicker on a border)
	AfterJump = 3, -- seconds after a teleport (a respawn, an arrest, a home's door) before an area card may show: the screen is busy until then
	Gap = 12, -- pixels between the card and the HUD zone it sits next to
	Accent = true, -- a short pink rule between the name and the street-type line
	Pc = { Width = 380, Name = 42, Kind = 15 }, -- keyboard / gamepad: card width, name and line text sizes
	-- Phones and tablets: the name is NameGrow times the screen height, between Name and NameMax (22 px
	-- on a 360 px tall phone, where the card must fit between the Buttons zone and the jump button).
	Touch = { Width = 260, Name = 22, NameMax = 34, NameGrow = 0.062, Kind = 12 },
}

-- Every Id below is a free Creator Store sound by ProSoundEffects (the names end "(SFX)"), found with the
-- Studio asset search on 2026-10-05, except BeachMusic and ClubBass: two APMOfficial tracks that
-- Config.Sounds.Radio already uses. Durations are from the asset descriptions.
--   Volume       loudness at full (beds and movers) or at the start (one-shots)
--   Looped       beds, movers and emitters loop; one-shots don't
--   Pitch        PlaybackSpeed (default 1)
--   Life         one-shots: seconds until it is cut off, fading out over the last Mix.ShotFade of them.
--                Shorter than a long sound (a 30 s siren is heard driving away, then fades); longer than
--                a short one by that fade, so it plays out in full.
--   MinDistance / MaxDistance   3D roll-off in studs (default 25 / 400; beds are flat and ignore them).
--                Within MinDistance a sound is as loud as its Volume; from there it falls off quickly.
--   Eq           { Low, Mid, High } gains in decibels: distance dulls the highs
--   Region       { from, to } seconds: play (and loop) only this stretch of the recording
Ambience.Sounds = {
	-- Beds: flat loops, one at a time, cross-faded.
	GladesDay = { Id = 9112802503, Volume = 0.3, Looped = true }, -- Jungle Ambience 2 (SFX): day, distant bird chirps and whistles, crickets, loop, 63.8 s
	GladesNight = { Id = 9112809528, Volume = 0.34, Looped = true }, -- Jungle Frogs 4 (SFX): night frogs, chirping insects, wind in foliage, loop, 43.2 s
	SuburbDay = { Id = 9112835306, Volume = 0.22, Looped = true }, -- Neighborhood Birds 1 (SFX): morning chirps, distant city rumble, loop, 48 s
	SuburbNight = { Id = 9112834403, Volume = 0.26, Looped = true }, -- Neighborhood Ambience 5 (SFX): night crickets, far cars, a dog now and then, loop, 36 s
	HarborDay = { Id = 9112792352, Volume = 0.26, Looped = true }, -- Harbor Day Presence 4 (SFX): gulls, ducks, distant horns and engines, loop, 36 s
	HarborNight = { Id = 9112793211, Volume = 0.26, Looped = true }, -- Harbor Night Presence 4 (SFX): night birds, insects, distant horns, loop, 36 s
	MarinaDay = { Id = 9112829422, Volume = 0.24, Looped = true }, -- Marina Ambience 3 (SFX): rigging and hull creaks, gulls, far traffic, loop, 36 s

	-- Distant one-shots: 3D, so you hear which way they come from, placed far from the camera
	-- (Ambience.Shots). Each one's MinDistance is about its nearest placing: Volume is then how loud the
	-- nearest ones are (quiet: the city hum is 0.25), and the furthest still carry at about a third of it.
	-- The sirens are quieter still, on purpose: a real police car's siren (SoundClient: 0.6, heard to 700
	-- studs) is the chase's main warning, and ours must never pass for one a block away. At these
	-- volumes the nearest sounds like a real car some 200 studs off (see also Shots.Siren.NotWanted).
	SirenWail = { Id = 9119165140, Volume = 0.07, Life = 14, MinDistance = 260, MaxDistance = 2000, Eq = { Mid = -2, High = -12 } }, -- Siren Wail 2 (SFX): an emergency wail going away and back, 30.4 s
	SirenYelp = { Id = 9119165420, Volume = 0.06, Life = 12, MinDistance = 260, MaxDistance = 2000, Eq = { Mid = -2, High = -12 } }, -- Siren Yelp 1 (SFX): the fast yelp, away and back, 31.7 s
	HornsA = { Id = 9113208930, Volume = 0.16, Life = 9, MinDistance = 110, MaxDistance = 1200, Eq = { High = -8 } }, -- Auto Horns 1 (SFX): honks in distant traffic, 5.9 s
	HornsB = { Id = 9113209176, Volume = 0.15, Life = 8, MinDistance = 110, MaxDistance = 1200, Eq = { High = -8 } }, -- Auto Horns 4 (SFX): honks in distant traffic, 5.0 s
	ShipHorn = { Id = 9114406660, Volume = 0.2, Pitch = 0.8, Life = 14, MinDistance = 600, MaxDistance = 4000, Eq = { Low = 3, High = -8 } }, -- Ferry Boat Horn Medium Cu Clean Twice 1 (SFX): two long blasts then a distant idle, 13.8 s; pitched down into a bigger ship
	GullsA = { Id = 9118858279, Volume = 0.2, Life = 9, MinDistance = 40, MaxDistance = 500 }, -- Seagull Squawks 1 (SFX), 6.0 s (Config.Sounds' Seagulls too, which SoundClient plays flat along the beach: Shots.Gulls.Quiet)
	GullsB = { Id = 9118858259, Volume = 0.2, Life = 7, MinDistance = 40, MaxDistance = 500 }, -- Seagull Squawks 3 (SFX): three sets of calls, 3.5 s
	BirdsScatter = { Id = 9125739054, Volume = 0.55, Life = 8, MinDistance = 10, MaxDistance = 140 }, -- Pigeon Surges Sudden Bursts Of Birds Flying 12 (SFX): a flock bursting into the air, 5.3 s (played right at the flock)

	-- Movers: 3D loops riding on the moving models, so they swell as one passes and fade as it goes.
	-- Rotor: the whole 28.4 s recording is "hover, away to distant, approach in, hovering fly-by" with
	-- a pitch bend. Looped whole, the helicopter would sound as if it flew off and came back while you
	-- watch it circle steadily, so only the steady hover at its start is looped (Region: set from the
	-- asset's description, not by ear; move it if the loop's seam can be heard). No steadier helicopter
	-- loop by this publisher turned up in the search. Its Volume keeps it under the city hum downtown.
	Rotor = { Id = 9113417082, Volume = 0.26, Looped = true, Region = { 0.5, 6 }, MinDistance = 150, MaxDistance = 1000 }, -- Bell Huey Helicopter Hover Away To Distant 1 (SFX): rotor chop
	Airliner = { Id = 9113201331, Volume = 0.3, Looped = true, MinDistance = 300, MaxDistance = 1800 }, -- Atmosphere Formation 7 (SFX): a big low airy rumble ("jets passing overhead"), 37.7 s
	SmallPlane = { Id = 9112787518, Volume = 0.3, Pitch = 0.7, Looped = true, MinDistance = 150, MaxDistance = 900, Eq = { Low = 2, High = -10 } }, -- Go Kart Engine Constant 2 (SFX): a small engine, pitched down and dulled into a far-off prop plane, loop, 41.3 s
	ShipEngine = { Id = 9112750448, Volume = 0.35, Pitch = 0.7, Looped = true, MinDistance = 120, MaxDistance = 900 }, -- Bow Wash Slow Trolling Speed 1 (SFX): diesel rumble and water at the bow, loop, 36 s
	Speedboat = { Id = 9112750448, Volume = 0.3, Pitch = 1.5, Looped = true, MinDistance = 90, MaxDistance = 700 }, -- the same bow wash pitched up: a quick little motorboat

	-- Fixed emitters (Ambience.Emitters): 3D loops at one spot.
	BeachMusic = { Id = 1837091161, Volume = 0.3, Looped = true, MinDistance = 25, MaxDistance = 170, Eq = { Low = 2, Mid = -2, High = -10 } }, -- APMOfficial "Be Steel My Beating Drum" (laid-back steel drums, 200 s), dulled like a speaker down the boardwalk
	ClubBass = { Id = 1837116214, Volume = 0.4, Looped = true, MinDistance = 20, MaxDistance = 140, Eq = { Low = 6, Mid = -14, High = -40 } }, -- APMOfficial "New Rock Royalty (INST)" (synthwave, 224 s): only the thump gets out through the club's walls
}

-- Distant one-shots. An area's Shots say which of these it hears and how often.
--   Sounds     keys of Ambience.Sounds, one picked at random each time
--   Every      { min, max } seconds between two (divided by the area's rate)
--   Distance   { min, max } studs from the camera, in a random direction (or around Toward)
--   Height     world Y the sound comes from (street level for traffic, up in the air for gulls)
--   NightRate  how much more (over 1) or less (under 1) often at night; 0 = never at night
--   RainRate   the same for a storm (Workspace attribute Raining); 0 = never in the rain
--   Toward     optional direction (Vector3, Y ignored) the sound comes from, give or take 35 degrees
--   FromShip   true: from the cargo ship's side of the sky while the ship is out (no further away than
--              Distance says, so the horn still carries when the ship is a long way off)
--   Quiet      optional { x0, x1, z0, z1 }: never while the camera is inside this rectangle (somebody else
--              already plays that sound there)
--   NotWanted  true: never while you are wanted (player attribute Heat above 0), and one still sounding
--              when you get your first star fades away. A siren you hear then is always a real one.
Ambience.Shots = {
	Siren = { Sounds = { "SirenWail", "SirenYelp" }, Every = { 45, 110 }, Distance = { 280, 520 }, Height = 6, NightRate = 1.5, NotWanted = true },
	Horns = { Sounds = { "HornsA", "HornsB" }, Every = { 20, 50 }, Distance = { 120, 300 }, Height = 4, NightRate = 0.6 },
	-- (Quiet: SoundClient's own beach gulls call east of x 1125 between z -2000 and 800)
	Gulls = { Sounds = { "GullsA", "GullsB" }, Every = { 14, 32 }, Distance = { 40, 140 }, Height = 30, NightRate = 0, RainRate = 0, Quiet = { 1125, math.huge, -2000, 800 } },
	ShipHorn = { Sounds = { "ShipHorn" }, Every = { 60, 140 }, Distance = { 700, 1100 }, Height = 20, Toward = Vector3.new(1, 0, 0), FromShip = true },
}

-- Fixed sound sources. Made the first time the camera comes within Range, played only while it is.
--   When  "Day", "Night" or nil (always)
Ambience.Emitters = {
	{ Sound = "BeachMusic", At = Vector3.new(1425, 8, -440), Range = 200, When = "Day" }, -- the boardwalk by the Ferris pier
	{ Sound = "ClubBass", At = Vector3.new(1120, 8, -150), Range = 170, When = "Night" }, -- Club Nova, on the beachfront
}

Ambience.Mix = {
	BedFade = 3, -- seconds a bed takes to cross-fade in or out (also day <-> night)
	RainBeds = 0.4, -- beds play this much quieter in a storm (birds and insects sit back behind SoundClient's rain)
	EmitterFade = 1.5, -- seconds an emitter takes to fade in or out
	MaxShots = 3, -- distant one-shots sounding at once, at most
	ShotFade = 2.5, -- seconds a one-shot fades out over at the end of its Life
	DuckDown = 0.15, -- seconds AmbienceClient.Duck takes to go down...
	DuckUp = 0.8, -- ...and to come back up
	MoverRange = 1.15, -- a mover's loop plays only while the camera is within this times its MaxDistance
}

-- The neon wave: when IsNight turns true the night lights come on block by block, outward from downtown.
-- AmbienceClient.DuskOrder(position) gives each spot its delay; SkyClient switches the parts.
Ambience.Dusk = {
	Centre = Vector3.new(-15, 0, -235), -- the Solana plaza: downtown lights first
	Spread = 6, -- seconds from the first block to the last
	Reach = 2600, -- studs from the centre to the last blocks (further away still: Spread)
	Curve = 0.6, -- under 1 = blocks near downtown come on further apart, so the wave reads up close
	Block = 120, -- studs: lights in the same block switch together
	-- Seconds of steady per-block randomness (part of Spread). A device only has the blocks around the
	-- player loaded, and those are much the same distance from downtown: this is what makes them come on
	-- one after another over a couple of seconds instead of in one ring.
	Jitter = 1.5,
}

Ambience.Life = {
	HideBeyond = 1100, -- studs: a day-only or night-only mover appears or vanishes only this far from the camera
	FarUpdate = 1400, -- studs: movers further than this from the camera move every third frame
	-- A commuter plane circling high over the city (ellipse, Radius = x / z half-axes): out over the bay
	-- off the beach, over Palm Hills, the edge of the Glades and the docks. Never right over downtown,
	-- so there it is a far speck; in those four places it passes overhead with a low rumble.
	Airliner = { Centre = Vector3.new(300, 440, -200), Radius = Vector2.new(1500, 1100), Period = 120, Bank = 6 },
	-- A small plane towing a banner up and down the beach by day (a loop of two legs along Z, at X[1] and
	-- X[2], with half-circle turns at the ends).
	BannerPlane = { X = { 1650, 1950 }, Z = { -1700, 300 }, Height = 150, Speed = 40, Text = "GATOR GLADES AIRBOAT TOURS" },
	-- The night helicopter (a news crew's, not the police's: it is up there every night whether or not
	-- anybody is wanted): flies in from From, circles downtown with a searchlight, flies back out at dawn.
	-- (Downtown's tallest buildings are 200 studs.)
	Heli = { Centre = Vector3.new(-15, 0, -235), Radius = 330, Height = 240, Speed = 30, From = Vector3.new(1900, 260, -1900), Bank = 12 },
	-- A cargo ship far offshore, up and down the coast (same kind of loop as the banner plane), east of
	-- Lighthouse Key and the boat missions round its tip (x 2560 at most).
	Ship = { X = { 2660, 2820 }, Z = { -2150, 2150 }, Speed = 9, Water = -1.5 },
	-- A speedboat looping off the beach (clear of the Ferris pier and the causeway).
	Speedboat = { Centre = Vector3.new(1960, 0, -850), Radius = Vector2.new(170, 300), Speed = 36, Water = -1.5 },
	-- Pelicans gliding in a V along the shore by day: low over the water, but over the Ferris pier and the
	-- causeway they cross, clear of their lamp posts (the pier's lamp heads and the causeway's street
	-- lights, one of which stands right on their line at x 1605, all top out at about 16 studs).
	Gliders = { X = { 1540, 1600 }, Z = { -1700, 400 }, Height = 22, Speed = 16, Kind = "Pelican", Count = 5, PerfCount = 3 },

	-- Bird looks, all built from five or six small parts. Size scales the whole bird; Span is one wing's
	-- length (times Size); Flap = wing beats per second; Speed = studs/s circling; Legs = leg colour
	-- (standing birds only: egrets).
	Birds = {
		Gull = { Size = 0.9, Span = 1.5, Flap = 3.2, Speed = 18, Body = Color3.fromRGB(242, 242, 238), Wing = Color3.fromRGB(150, 158, 170), Beak = Color3.fromRGB(240, 196, 60) },
		Pelican = { Size = 1.6, Span = 1.9, Flap = 2.2, Speed = 15, LongBeak = true, Body = Color3.fromRGB(160, 150, 138), Wing = Color3.fromRGB(104, 98, 92), Beak = Color3.fromRGB(236, 172, 84) },
		Pigeon = { Size = 0.7, Span = 1.3, Flap = 5, Speed = 20, Body = Color3.fromRGB(122, 128, 142), Wing = Color3.fromRGB(96, 100, 114), Beak = Color3.fromRGB(64, 62, 66) },
		Egret = { Size = 1.1, Span = 1.7, Flap = 2.6, Speed = 15, Body = Color3.fromRGB(248, 248, 246), Wing = Color3.fromRGB(236, 236, 232), Beak = Color3.fromRGB(236, 190, 50), Legs = Color3.fromRGB(44, 42, 40) },
	},
	-- Where flocks sit. At = the middle (Y is found by a raycast), Spread = studs they spread over.
	Roosts = {
		{ Kind = "Gull", At = Vector3.new(1370, 0, -820), Count = 7, Spread = 8 }, -- the beach, south of the citizen spawn
		{ Kind = "Gull", At = Vector3.new(1395, 0, -60), Count = 6, Spread = 7 }, -- the beach, by Club Nova
		{ Kind = "Gull", At = Vector3.new(1330, 0, 380), Count = 6, Spread = 7 }, -- the beach, north end
		{ Kind = "Pelican", At = Vector3.new(1610, 0, -428), Count = 4, Spread = 5 }, -- floating beside the Ferris pier
		{ Kind = "Gull", At = Vector3.new(1560, 0, 1100), Count = 6, Spread = 6 }, -- the first marina pier
		{ Kind = "Gull", At = Vector3.new(165, 0, 1380), Count = 6, Spread = 12 }, -- the container yard's stacks
		{ Kind = "Pigeon", At = Vector3.new(-28, 0, -206), Count = 8, Spread = 6 }, -- the Solana plaza, by the arch
		{ Kind = "Pigeon", At = Vector3.new(250, 0, -1410), Count = 6, Spread = 6 }, -- by the Palm Hills citizen spawn
		{ Kind = "Egret", At = Vector3.new(-1556, 0, -596), Count = 4, Spread = 8 }, -- the Glades boardwalk pond
		{ Kind = "Egret", At = Vector3.new(-1046, 0, -872), Count = 3, Spread = 6 }, -- the bayou pond
	},
	Flocks = {
		Activate = 260, -- studs (flat) from you: a roost this close gets its birds
		Max = 2, PerfMax = 1, -- roosts with birds at once (Performance mode: PerfMax)
		MaxBirds = 16, PerfMaxBirds = 8, -- bird models in all, at most
	},
	Scatter = {
		Radius = 12, -- studs from a bird that make the flock take off (on foot)
		CarRadius = 26, -- ...when you move faster than 30 studs/s (driving)
		CarLead = 0.7, -- seconds ahead of a fast car that birds already take off (it would be through them before they left the ground)
		Return = { 30, 55 }, -- seconds in the air before they come back
		Circle = { 20, 36 }, -- studs: the circles they fly meanwhile
		Climb = { 18, 34 }, -- studs above their roost they circle at
		LandClear = 22, -- studs: they wait to land while you are this close to the roost
	},
}

return Ambience
