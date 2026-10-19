-- Police (ModuleScript, ReplicatedStorage.Shared.Config.Police)
-- Tunables for the wanted system and the AI police (HeatService, AIPoliceService, ArrestService).
-- Distances are studs, times seconds, speeds studs/s. Read-only at runtime.
--   Dispatch: AI units per wanted player = UnitsByHeat[heat] - engaged player cops (never below 0;
--     at FloorStars+ stars at least 1 if no cop is engaged). MaxTotal caps every AI car in the server,
--     ambient patrols included; pursuits always come first.
--   Escape: once the stars go hollow, the unseen window is EscapeBase + EscapePerStar x heat seconds,
--     counted OutsideRate times faster outside the search circle (SearchBase + SearchPerStar x heat).

local Police = {}

-- Dispatch
Police.UnitsByHeat = { 1, 1, 2, 3, 4 } -- AI pursuit units per wanted player, by stars
Police.FloorStars = 3 -- at this many stars keep at least 1 AI unit when no player cop is engaged
Police.MaxTotal = 8 -- every AI police car in the server, patrols included
Police.EngageRange = 400 -- a player cop this close to the suspect counts as engaged...
Police.EngageMemory = 20 -- ...or one who saw them in the last this-many seconds
Police.SpawnMin, Police.SpawnMax = 250, 450 -- pursuit spawn ring around the last-seen spot
Police.SpawnGap = 4 -- seconds between spawns for the same suspect
Police.VanishSight = 350 -- a car leaves only when no player this close can see it
Police.LeaveTimeout = 40 -- ...or after this long trying

-- Ambient patrols (no siren, no target; cop eyes for HeatService)
Police.Patrols = 3
Police.PatrolRange = 700 -- patrols exist only this close to some player
Police.PatrolSpawnMin, Police.PatrolSpawnMax = 260, 600
Police.PatrolSpeed = 0.6 -- share of the car's top speed
Police.PatrolSpawnAvoid = 200 -- keep away from spawn points, pads and the hideout
Police.PatrolDispatch = 900 -- a free patrol this close to the last-seen spot answers the call

-- Driving
Police.SpeedVsTarget = 0.95 -- never faster than this share of the suspect's car
Police.SearchSpeed = 0.8 -- extra speed share while searching (hollow stars)
Police.DirectRange = 140 -- steer straight at a suspect this close (and in sight)

-- Arrests by AI units
Police.ArrestRange = 22
Police.ArrestHeight = 6 -- max height difference (no arrests through floors)
Police.ArrestSeconds = 3

-- Sight and escape (HeatService)
Police.SightRange = 250
Police.HollowAfter = 8 -- unseen this long -> hollow stars (search mode)
Police.EscapeBase = 25
Police.EscapePerStar = 10
Police.SearchBase = 150
Police.SearchPerStar = 50
Police.OutsideRate = 2 -- the escape countdown runs this much faster outside the search circle
Police.PingEvery = 20 -- at PingStars+ stars, the helicopter re-centres the search circle this often
Police.PingStars = 4

-- Crimes
Police.RamSpeed = 45 -- closing speed for ramming a police car
Police.RamCooldown = 20
Police.EvadeSeconds = 60 -- continuous seen-and-moving chase time per extra star...
Police.EvadeMaxStars = 4 -- ...up to this many stars
Police.EvadeMinSpeed = 15

-- Roadblocks (4+ star suspects seen recently)
Police.Roadblock = {
	MinStars = 4,
	Every = 25, -- seconds between roadblocks for the same suspect
	SeenWithin = 6, -- only while the suspect was seen this recently
	AheadMin = 350,
	AheadMax = 500,
	Life = 30,
	FarRange = 900, -- removed early when the suspect is this far away
	MaxActive = 2, -- per server
	Gap = 10, -- the gap between the two cars (with a spike strip in it)
}

-- Tutorial chaser (player attribute TutorialChase = true during a new player's first escape)
Police.Tutorial = {
	SpawnMin = 150,
	SpawnMax = 250,
	SpeedCap = 0.85, -- share of the player's car top speed
	NoArrestSeconds = 25,
}

-- Player cops (ArrestService)
Police.PatrolPay = 80 -- per minute on duty...
Police.PatrolPayMinMove = 150 -- ...for cops who moved this far that minute...
Police.PatrolPayNearWanted = 400 -- ...or were this close to a wanted player
Police.DeathBountyRange = 300 -- a wanted player who dies: bounty to the nearest cop this close...
Police.DeathBountyMemory = 20 -- ...who saw them in the last this-many seconds

function Police.EscapeWindow(heat)
	return Police.EscapeBase + Police.EscapePerStar * math.max(1, heat)
end

function Police.SearchRadius(heat)
	return Police.SearchBase + Police.SearchPerStar * math.max(1, heat)
end

return Police
