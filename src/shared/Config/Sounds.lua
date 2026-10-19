-- Sounds (ModuleScript, ReplicatedStorage.Shared.Config.Sounds)
-- Every sound the game plays, as asset IDs (all free, Roblox-licensed unless noted). Used by SoundClient.
-- Every Id below was checked with MarketplaceService:GetProductInfo on 2026-09-28: all are Audio, public
-- domain / free, and made by ProSoundEffects, APMOfficial (APM Music) or Roblox Resources. None come from other creators.
-- Durations are taken from the asset descriptions / AssetService:SearchAudio.
local Sounds = {}

Sounds.Effects = {
	-- Vehicles
	EngineLoop = { Id = 80317022777602, Volume = 0.5, Looped = true }, -- Car-Engine-Loop (Roblox Resources, ~9 s, made to loop)
	Siren = { Id = 9112871822, Volume = 0.6, Looped = true }, -- Siren Composite 1 (ProSoundEffects, 56 s: several police cars wailing, steady, tagged "Loop"). Close-up alternative that has a start and stop (not seamless): Siren Wail 1, 9119165131 (26.7 s)
	Horn = { Id = 9113019382, Volume = 0.7, Looped = false }, -- 2007 Dodge Charger Horn Honking 7 (ProSoundEffects, 1.0 s single honk; the car model is only in the asset name, the sound is a plain horn)
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

	-- UI / rewards
	Click = { Id = 9119717523, Volume = 0.4, Looped = false }, -- Switch Click On Or Off Toggle Button 2 (ProSoundEffects, 0.4 s)
	Success = { Id = 9045585856, Volume = 0.6, Looped = false }, -- Prisma (sting) (APMOfficial, 5 s plucky synth sting)
	Stamp = { Id = 9125481599, Volume = 0.7, Looped = false }, -- Date Stamp Big Office Impact Squeak Reverber (ProSoundEffects, 1.5 s big stamp thump)
	Countdown = { Id = 9114636546, Volume = 0.6, Looped = false }, -- Graphic Beeps 5 (ProSoundEffects, 0.6 s single digital beep; play once per 3-2-1 tick)
	Checkpoint = { Id = 9126073001, Volume = 0.6, Looped = false }, -- Synth Sparkle Tone High Pitch Bell Tone Ding (ProSoundEffects, 1.2 s)

	-- Weather / world ambience
	Rain = { Id = 9112855439, Volume = 0.4, Looped = true }, -- Rain On Water 2 (ProSoundEffects, 36 s steady heavy rainfall, tagged "Loop")
	Thunder = { Id = 9120021818, Volume = 0.6, Looped = false }, -- Thunder Sharp Striking Rumbling Crackling 1 (ProSoundEffects, 6.4 s strike + long rumble)
	Waves = { Id = 9119676058, Volume = 0.4, Looped = true }, -- Surf Cu Waves Crashing 2 (ProSoundEffects, 79.2 s steady surf)
	Seagulls = { Id = 9118858279, Volume = 0.3, Looped = false }, -- Seagull Squawks 1 (ProSoundEffects, 6.0 s; play now and then near the beach instead of looping)
	CityAmbience = { Id = 9112785210, Volume = 0.25, Looped = true }, -- Freeway Traffic 2 (ProSoundEffects, 86.1 s distant city rumble, birds, wind, tagged "Loop")
}

-- Car radio: all APM Music (creator APMOfficial), instrumental or underscore mixes.
Sounds.Radio = {
	{ Name = "Neon FM", Tracks = { -- synthwave / 80s retro electronic
		{ Name = "New Rock Royalty", Id = 1837116214 }, -- New Rock Royalty (INST), Bibliotheque "SYNTHWAVE", 224 s
		{ Name = "New Life", Id = 1837115759 }, -- Bibliotheque "SYNTHWAVE", 124 s
		{ Name = "Gravity in Motion", Id = 1837116012 }, -- Bibliotheque "SYNTHWAVE", 123 s
		{ Name = "Tutti Allo Stadio", Id = 9042930634 }, -- instrumental 80s Italo-disco synth, Justement Music, 164 s
		{ Name = "Prendi Un Treno Con Me", Id = 9042928028 }, -- instrumental 80s Italo-disco synth, Justement Music, 189 s
		{ Name = "Friend in the Machine", Id = 1842960246 }, -- underscore version, retro synth, Francis Preve, 124 s
	} },
	{ Name = "Palm 99", Tracks = { -- upbeat pop / funk / feel-good summer
		{ Name = "Happy Funk", Id = 1842203247 }, -- Happy Funk (a), "upbeat, friendly funky bed", 120 s
		{ Name = "Get Up Go", Id = 1840037538 }, -- Get Up Go (b), feel-good retro pop with brass + claps, 124 s
		{ Name = "Wave Tripping", Id = 1839966347 }, -- 60s surf-guitar pop, Juice Music, 138 s
		{ Name = "Dance With You", Id = 9042511992 }, -- Dance With You E, happy summer disco underscore, 172 s
		{ Name = "Tropical Touch", Id = 9042464743 }, -- Soho "Summer Pop Party", 132 s
		{ Name = "10 Out Of 9", Id = 9045442373 }, -- 10 Out Of 9 - Instrumental, funky pop, 142 s
	} },
	{ Name = "Gator Radio", Tracks = { -- chill lo-fi / tropical / reggae / smooth
		{ Name = "Ocean View", Id = 9044565679 }, -- Ocean View (c), sunset chill-hop, 130 s
		{ Name = "Be Steel My Beating Drum", Id = 1837091161 }, -- laid-back steel-drum downtempo, 200 s
		{ Name = "Sunrise Girl", Id = 9043041252 }, -- Sunrise Girl A, light modern reggae, 119 s
		{ Name = "Bravta", Id = 9043886860 }, -- Bravta C, instrumental jazzy lo-fi hip hop, 131 s
		{ Name = "Mid Morning", Id = 9038820833 }, -- Mid Morning C, relaxed hip hop underscore, 161 s
		{ Name = "Balearic Beat", Id = 9042467119 }, -- Soho, summer-sunset chill pop, 162 s
	} },
}

-- Florida moments (EventService) play one of the radio tracks above at the scene: a looped 3D sound on
-- the prop, made by SoundClient (Music volume). Same asset ids as the radio, nothing new.
Sounds.EventMusic = {
	Performer = 1837091161, -- "Be Steel My Beating Drum" (Gator Radio): steel drums for the street drummer
	BeachParty = 9042511992, -- "Dance With You" (Palm 99): summer disco for the beach party
}

return Sounds
