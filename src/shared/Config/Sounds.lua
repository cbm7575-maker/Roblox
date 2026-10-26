-- Sounds (ModuleScript, ReplicatedStorage.Shared.Config.Sounds)
-- Every sound the game plays, as asset IDs (all free, Roblox-licensed unless noted). Used by SoundClient.
-- Every Id below was checked with MarketplaceService:GetProductInfo on 2026-09-28: all are Audio, public
-- domain / free, and made by ProSoundEffects, APMOfficial (APM Music) or Roblox Resources. None come from other creators.
-- (The chase cues, the Big Score sounds and Sounds.PoliceChatter were checked the same way on 2026-10-14.)
-- Durations are taken from the asset descriptions / AssetService:SearchAudio.
-- Optional Pitch (PlaybackSpeed, default 1) lets one checked asset serve as a second, different cue.
-- Other optional fields on an effect: PitchVar (each play is pitched up or down by up to this share, so
-- a cue played many times in a row doesn't sound like a machine), MinDistance / MaxDistance (3D roll-off
-- in studs, default 25 / 400), Group = "Music" (it follows the settings' Music slider, like the car
-- radio, instead of Effects: for score that plays under the action, HeistMusic).
-- Id = 0 means "no asset picked yet": SoundClient.Play and SoundClient.Loop do nothing for that key,
-- without a warning (so setting an Id to 0 is also the way to silence a cue).
--   Sounds.Effects       one-shots and loops, by key
--   Sounds.PoliceChatter short police radio clips: SoundClient plays one now and then, quiet and
--                        squeezed like a radio, while you are wanted (an Id of 0 is skipped)
--   Sounds.Engine        how every engine behaves (gears, shifts, idle burble, launch)
--   Sounds.Exhausts      the engine voices a car can have (car attribute "Exhaust"), Sounds.ExhaustOrder
--                        lists their keys in menu order (Config.Garage.Exhausts uses the same keys)
--   Sounds.Radio         the car radio stations. Each song has a Length in seconds (from the asset
--                        description): SoundClient uses it to keep a station "live" while you aren't
--                        listening. A song with no Length still plays; the station just can't move on
--                        past it while you're away.
local Sounds = {}

Sounds.Effects = {
	-- Vehicles
	EngineLoop = { Id = 80317022777602, Volume = 0.5, Looped = true }, -- Car-Engine-Loop (Roblox Resources, ~9 s, made to loop). Every exhaust below plays this one loop unless it has its own Id
	Siren = { Id = 9112871822, Volume = 0.6, Looped = true }, -- Siren Composite 1 (ProSoundEffects, 56 s: several police cars wailing, steady, tagged "Loop"). Close-up alternative that has a start and stop (not seamless): Siren Wail 1, 9119165131 (26.7 s)
	Horn = { Id = 9113019382, Volume = 0.7, Looped = false }, -- "... Horn Honking 7" (ProSoundEffects, 1.0 s single honk: a plain car horn; the rest of the asset's name is a real car, so it is left out here)
	Skid = { Id = 9120397746, Volume = 0.5, Looped = true }, -- Vehicle Skid In Fast Long Skid Stop Cu 1 (ProSoundEffects, 3.7 s long tire squeal)
	Crash = { Id = 9120389194, Volume = 0.7, Looped = false }, -- Vehicle Panel Impact 7 (ProSoundEffects, 1.1 s car body panel hit)
	Nitro = { Id = 9120700771, Volume = 0.6, Looped = false }, -- Whoosh Bys Air Pass Bys Vehicle Passing 1 (ProSoundEffects, 3.6 s)
	Door = { Id = 125094987563505, Volume = 0.6, Looped = false }, -- Open-Close-Car-Door (Roblox Resources, ~1 s)
	Splash = { Id = 9119479417, Volume = 0.8, Looped = false }, -- Splashes Large Objects Thrown In Water 6 (ProSoundEffects, 3.9 s big plop + bubbles)

	-- Crime / police
	Alarm = { Id = 9113085114, Volume = 0.5, Looped = true }, -- Alarm Bell On Hard Surface 1 (ProSoundEffects, 27.2 s constant bell ring)
	Zap = { Id = 9116276051, Volume = 0.5, Looped = false }, -- Lightning Flashes Quick Electrical Bursts 11 (ProSoundEffects, 1.2 s crackle)
	Cuffs = { Id = 9114764731, Volume = 0.6, Looped = false }, -- Handcuff Movement 25 (ProSoundEffects, 1.5 s metal rattle + ratchet)
	Cash = { Id = 9113849583, Volume = 0.6, Looped = false }, -- Coin Throws 2 (ProSoundEffects, 2.4 s handful of coins)
	CashIn = { Id = 9113728049, Volume = 0.55, Looped = false }, -- Cash Register 2 (ProSoundEffects, 1.7 s electronic register drawer opened and shut): your banked cash goes up by $100 or more
	Punch = { Id = 9120419946, Volume = 0.6, Looped = false }, -- Video Game Effects 13 (ProSoundEffects, kicks and punches thud; Id from the lead's combat brief)
	Spotted = { Id = 9114636546, Volume = 0.7, Looped = false, Pitch = 1.35 }, -- a cop sees you again: the Countdown beep (Graphic Beeps 5) pitched up; SoundClient plays it twice, fast
	StarUp = { Id = 81206643711081, Volume = 0.6, Looped = false }, -- Whoosh Tonal Hit Quick (APMOfficial, ~4 s whoosh into a low tonal hit): a wanted star lights up (SoundClient cuts it off after 3 s)
	LostCops = { Id = 1848281810, Volume = 0.55, Looped = false }, -- Everything Works Out - Tag2 (APMOfficial, Spot On "POPTIMISTIC", 3 s optimistic synth-pop tag): the heat is gone and nobody cuffed you
	PhoneText = { Id = 9113750988, Volume = 0.5, Looped = false }, -- "Cell Phone Ring ... 6" (ProSoundEffects, 1.2 s electronic chirpy digital ring; the rest of the asset's name is a brand, so it is left out here): a text / new step on your phone
	Failed = { Id = 9042694697, Volume = 0.6, Looped = false }, -- Dark Meditation (sting) (APMOfficial, Ded Good "Dark City Beds", 3 s forbidding trap sting): MISSION FAILED / CUFFED / HEIST FAILED (the HUD's red stamps)

	-- The Big Score (the crew heist; its client plays these. "Loop" = SoundClient.Loop, stopped by the caller)
	GoldClink = { Id = 9116741873, Volume = 0.6, Looped = false, Pitch = 0.85, PitchVar = 0.08, MaxDistance = 80 }, -- Metal Lid Small Incense Burner 9 (ProSoundEffects, 0.7 s brass ringy "shing" hit), pitched down a little for weight: a gold bar goes into the van
	GateOpen = { Id = 9114848444, Volume = 0.7, Looped = false, MinDistance = 30, MaxDistance = 300 }, -- Huge Sliding Door 2 (ProSoundEffects, 4.6 s huge door rolling, hydraulic hiss): the reserve's gate slides open
	Drill = { Id = 9125450626, Volume = 0.45, Looped = true, MinDistance = 15, MaxDistance = 160 }, -- Construction Interior Large Power Tool Drilling 1 (ProSoundEffects, 68.4 s drilling, grinding, grating; Loop at the drill while it runs)
	VaultAlarm = { Id = 9113084849, Volume = 0.5, Looped = true, MinDistance = 30, MaxDistance = 500 }, -- Alarm Bell On Carpet Constant Ring 1 (ProSoundEffects, 34.9 s constant bell; a different bell from Alarm so the two never sound like one): Loop at the reserve while its alarm runs
	HeistMusic = { Id = 1842971508, Volume = 0.22, Looped = true, Group = "Music" }, -- Planning The Heist (APMOfficial, 138 s bed of pulsing strings and synths with steady driving percussion): Loop, flat and quiet, while you're on the crew from step 2 on

	-- Guns (CombatClient: SoundClient.Play(key, where, volume, 2): a shot is cut off after 2 s, so rapid
	-- fire can't pile up long echoes). No assets yet, so they are silent.
	GunPistol = { Id = 9117397547, Volume = 0.6, Looped = false, PitchVar = 0.06, MaxDistance = 600 }, -- Pistol Single Shots 5 (ProSoundEffects, 2.2 s close shot)
	GunSMG = { Id = 9114728793, Volume = 0.55, Looped = false, PitchVar = 0.08, MaxDistance = 600 }, -- Gun Single Shots 1 (ProSoundEffects, 1.4 s single small-automatic shot)
	GunShotgun = { Id = 9112910013, Volume = 0.75, Looped = false, PitchVar = 0.05, MaxDistance = 700 }, -- 12 Gauge Pump Action Shotgun 9 (ProSoundEffects, 2.5 s shot with the pump after)
	GunRifle = { Id = 9113177553, Volume = 0.7, Looped = false, PitchVar = 0.05, MaxDistance = 700 }, -- Assault Rifle 2 (ProSoundEffects, 1.5 s single shot)
	GunReload = { Id = 9117396164, Volume = 0.5, Looped = false, MaxDistance = 120 }, -- Pistol Clip 1 (ProSoundEffects, 1.7 s magazine loading)
	GunEmpty = { Id = 9117396156, Volume = 0.45, Looped = false, MaxDistance = 80 }, -- Pistol Clip 2 (ProSoundEffects, 0.5 s click; stands in for a dry fire)
	BulletHit = { Id = 9113632382, Volume = 0.5, Looped = false, PitchVar = 0.12, MaxDistance = 200 }, -- Bullet Impact 8 (ProSoundEffects, 0.9 s thud into a wall with debris)
	BodyArmor = { Id = 9113632382, Volume = 0.55, Looped = false, Pitch = 0.72, PitchVar = 0.08, MaxDistance = 200 }, -- a shot stopped by armor: Bullet Impact 8 (ProSoundEffects) pitched down to a dull thump
	KnockedOut = { Id = 9114344079, Volume = 0.5, Looped = false }, -- "Energy Presence 7" (3.8 s low rumble): the drone as the knocked-out screen goes grey (CombatClient)
	GunShell = { Id = 9113631210, Volume = 0.25, Looped = false, PitchVar = 0.1, MaxDistance = 60 }, -- "Bullet Drops 7" (1 s, casing on concrete): a spent casing hitting the ground (CombatClient)

	-- UI / rewards
	Click = { Id = 9119717523, Volume = 0.4, Looped = false }, -- Switch Click On Or Off Toggle Button 2 (ProSoundEffects, 0.4 s)
	Success = { Id = 9045585856, Volume = 0.6, Looped = false }, -- Prisma (sting) (APMOfficial, 5 s plucky synth sting)
	Stamp = { Id = 9125481599, Volume = 0.7, Looped = false }, -- Date Stamp Big Office Impact Squeak Reverber (ProSoundEffects, 1.5 s big stamp thump)
	Passed = { Id = 9040193225, Volume = 0.55, Looped = false }, -- SOS (sting) (APMOfficial, KPM "Vintage Radio: 1980s", 4 s glossy 80s synth-pop sting): the reward stamps (MISSION PASSED, heist cash, rank up; HUDController)
	Countdown = { Id = 9114636546, Volume = 0.6, Looped = false }, -- Graphic Beeps 5 (ProSoundEffects, 0.6 s single digital beep; play once per 3-2-1 tick)
	Checkpoint = { Id = 9126073001, Volume = 0.6, Looped = false }, -- Synth Sparkle Tone High Pitch Bell Tone Ding (ProSoundEffects, 1.2 s)
	RadioTune = { Id = 9116276051, Volume = 0.14, Looped = false, Pitch = 1.6, PitchVar = 0.1 }, -- the short burst of static when the radio changes station: the Zap crackle (Lightning Flashes Quick Electrical Bursts 11) pitched up, quiet, and cut off after 0.22 s by SoundClient. Set Id = 0 to have a plain click instead

	-- Weather / world ambience
	Rain = { Id = 9112855439, Volume = 0.4, Looped = true }, -- Rain On Water 2 (ProSoundEffects, 36 s steady heavy rainfall, tagged "Loop")
	Thunder = { Id = 9120021818, Volume = 0.6, Looped = false }, -- Thunder Sharp Striking Rumbling Crackling 1 (ProSoundEffects, 6.4 s strike + long rumble)
	Waves = { Id = 9119676058, Volume = 0.4, Looped = true }, -- Surf Cu Waves Crashing 2 (ProSoundEffects, 79.2 s steady surf)
	Seagulls = { Id = 9118858279, Volume = 0.3, Looped = false }, -- Seagull Squawks 1 (ProSoundEffects, 6.0 s; play now and then near the beach instead of looping)
	CityAmbience = { Id = 9112785210, Volume = 0.25, Looped = true }, -- Freeway Traffic 2 (ProSoundEffects, 86.1 s distant city rumble, birds, wind, tagged "Loop")
}

-- Police radio chatter while you're wanted (SoundClient: one clip every 9-18 s, never two at once, flat,
-- quiet and squeezed through a radio filter). All ProSoundEffects, category "Voices - Radio"; short
-- clips only, so a clip never runs into the next. Volume (optional) scales SoundClient's chatter volume.
Sounds.PoliceChatter = {
	-- (Only clips whose description names no real city or department: the "Line Feed" set reads out a real
	-- city's street names and "Police Radio Operators" is a real department's radio, so both are left out.)
	{ Id = 9117795877 }, -- Police Radio Dispatcher Many Officers 1 (1.9 s: one quick call)
	{ Id = 9117797611 }, -- Police Radio Dispatcher Many Officers 19 (4.3 s: dispatcher and officers)
	{ Id = 9117797573 }, -- Police Radio Dispatcher Many Officers 18 (5.9 s: back and forth, clicks)
	{ Id = 9125773804 }, -- Police Radio Call Male Voice Scratchy Static 3 (2.2 s: one short call)
	{ Id = 9117796078 }, -- Police Radio Dispatcher Many Officers 2 (3.2 s: dispatcher, clicks and pops)
	{ Id = 9117798635 }, -- Police Radio Dispatcher Many Officers 28 (2.5 s: dispatcher, scratchy)
	{ Id = 9117796105 }, -- Police Radio Dispatcher Many Officers 3 (3.8 s: dispatcher and officers)
}

-- Engines (SoundClient). One loop is pitched like a rev counter: it climbs through the gears, drops a
-- little at every shift, and gets louder when the driver is on the gas.
Sounds.Engine = {
	Gears = 5, -- default number of gears (an exhaust can set its own)
	GearCurve = 1.25, -- above 1 = short low gears, long top gear (gear g ends at (g / Gears) ^ GearCurve of top speed)
	GearStep = 0.05, -- each gear revs this much less far than the next one, so the note still climbs overall
	ShiftDrop = 0.28, -- how far the revs fall at an upshift (share of the exhaust's PitchRange)
	DownshiftAt = 0.88, -- shift down once the speed is under this share of the lower gear's top speed
	ShiftTime = 0.16, -- seconds the sound dips while changing up
	ShiftDip = 0.35, -- how much quieter it gets in that moment (0 = no dip)
	Response = 10, -- how fast the revs follow (per second); lower = lazier
	Launch = 0.5, -- gas down at a standstill (first gear): the revs jump up before the car gets going, to 0.65x this share of the range at full gas
	Idle = 0.5, -- share of an exhaust's Volume at rest with no gas
	Lope = 0.02, -- idle burble at rest: the loudness pulses by 4x this share, the pitch by only 0.3x
	MaxDistance = 400, -- studs: engines further than this from the camera are not played at all
}

-- Exhaust styles: the car attribute "Exhaust" holds one of these keys (nil or unknown = Stock).
--   Name        shown in menus
--   Pitch       PlaybackSpeed at idle
--   PitchRange  added on top at full revs
--   Volume      at full revs on the gas
--   Eq          { Low, Mid, High } gains in decibels (-80 .. 10; all 0 = no equalizer)
--   Distortion  0 .. 1 (0 = none): grit and rasp
--   Optional: Id (its own verified loop instead of EngineLoop), Gears, Idle, Lope (see Sounds.Engine).
Sounds.Exhausts = {
	Stock = { Name = "Stock", Pitch = 0.72, PitchRange = 0.8, Volume = 0.5, Eq = { Low = 0, Mid = 0, High = 0 }, Distortion = 0 },
	-- A bit brighter and keener than Stock.
	Sport = { Name = "Sport", Pitch = 0.8, PitchRange = 0.9, Volume = 0.55, Eq = { Low = -1, Mid = 2, High = 5 }, Distortion = 0.1 },
	-- Deep, loud and lumpy at idle; four long gears.
	Muscle = { Name = "Muscle", Pitch = 0.5, PitchRange = 0.62, Volume = 0.78, Eq = { Low = 8, Mid = 0, High = -5 }, Distortion = 0.22, Gears = 4, Lope = 0.05 },
	-- High, thin and raspy.
	Race = { Name = "Race", Pitch = 1, PitchRange = 1.2, Volume = 0.6, Eq = { Low = -9, Mid = 3, High = 7 }, Distortion = 0.45, Lope = 0.035 },
	-- A quiet electric whine: no gears, no rumble, nearly silent at rest.
	Whisper = { Name = "Whisper", Pitch = 1.3, PitchRange = 1.5, Volume = 0.16, Eq = { Low = -40, Mid = -6, High = 4 }, Distortion = 0, Gears = 1, Idle = 0.15, Lope = 0 },
}
Sounds.ExhaustOrder = { "Stock", "Sport", "Muscle", "Race", "Whisper" }

-- Car radio: all APM Music (creator APMOfficial), instrumental or underscore mixes. Length = the song's
-- seconds, from the asset description (SoundClient keeps stations "live" with it; see the header).
Sounds.Radio = {
	{ Name = "Neon FM", Tracks = { -- synthwave / 80s retro electronic
		{ Name = "New Rock Royalty", Id = 1837116214, Length = 224 }, -- New Rock Royalty (INST), Bibliotheque "SYNTHWAVE"
		{ Name = "New Life", Id = 1837115759, Length = 124 }, -- Bibliotheque "SYNTHWAVE"
		{ Name = "Gravity in Motion", Id = 1837116012, Length = 123 }, -- Bibliotheque "SYNTHWAVE"
		{ Name = "Tutti Allo Stadio", Id = 9042930634, Length = 164 }, -- instrumental 80s Italo-disco synth, Justement Music
		{ Name = "Prendi Un Treno Con Me", Id = 9042928028, Length = 189 }, -- instrumental 80s Italo-disco synth, Justement Music
		{ Name = "Friend in the Machine", Id = 1842960246, Length = 124 }, -- underscore version, retro synth, Francis Preve
	} },
	{ Name = "Palm 99", Tracks = { -- upbeat pop / funk / feel-good summer
		{ Name = "Happy Funk", Id = 1842203247, Length = 120 }, -- Happy Funk (a), "upbeat, friendly funky bed"
		{ Name = "Get Up Go", Id = 1840037538, Length = 124 }, -- Get Up Go (b), feel-good retro pop with brass + claps
		{ Name = "Wave Tripping", Id = 1839966347, Length = 138 }, -- 60s surf-guitar pop, Juice Music
		{ Name = "Dance With You", Id = 9042511992, Length = 172 }, -- Dance With You E, happy summer disco underscore
		{ Name = "Tropical Touch", Id = 9042464743, Length = 132 }, -- Soho "Summer Pop Party"
		{ Name = "10 Out Of 9", Id = 9045442373, Length = 142 }, -- 10 Out Of 9 - Instrumental, funky pop
	} },
	{ Name = "Gator Radio", Tracks = { -- chill lo-fi / tropical / reggae / smooth
		{ Name = "Ocean View", Id = 9044565679, Length = 130 }, -- Ocean View (c), sunset chill-hop
		{ Name = "Be Steel My Beating Drum", Id = 1837091161, Length = 200 }, -- laid-back steel-drum downtempo
		{ Name = "Sunrise Girl", Id = 9043041252, Length = 119 }, -- Sunrise Girl A, light modern reggae
		{ Name = "Bravta", Id = 9043886860, Length = 131 }, -- Bravta C, instrumental jazzy lo-fi hip hop
		{ Name = "Mid Morning", Id = 9038820833, Length = 161 }, -- Mid Morning C, relaxed hip hop underscore
		{ Name = "Balearic Beat", Id = 9042467119, Length = 162 }, -- Soho, summer-sunset chill pop
	} },
}

return Sounds
