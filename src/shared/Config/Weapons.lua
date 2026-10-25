-- Weapons (ModuleScript, ReplicatedStorage.Shared.Config.Weapons)
-- Guns, the gun store and the PASSIVE rules. WeaponService (server) and WeaponClient (client) read this.
-- Every name here is made up for Neon Coast (no real gun makers or models).
--
-- Who can hurt whom (WeaponService.CanDamage decides, the client only draws):
--   * PASSIVE players can't shoot and can't be shot. PASSIVE turns off by itself when you get heat,
--     and police on duty are never passive.
--   * Police on duty carry the Duty Pistol only, and it only hurts WANTED citizens.
--   * Citizens (not passive) can shoot other citizens and police (not passive). Hitting a player is a
--     crime: +1 star (at most once per AssaultCooldown), +1 more for a takedown.
--   * Nobody is hurt for SpawnShield seconds after spawning (ends early if they fire).
--   * Prisoners have no guns and can't be shot. Pedestrians are never hit: bullets pass through them.
--   * Going down while wanted counts as an arrest (ArrestService), as it always has: a cop who shot
--     you in the last TakedownMemory seconds gets the bounty.
--
-- Gun fields:
--   Id, Name, Kind (shown in the store), Price, MinRank (citizen rank to buy), CopOnly (never sold:
--   police on duty get it), Damage per bullet, HeadMult (x damage on a head hit), Rate (shots a
--   second), Auto (hold to keep firing), Mag (shots before a reload), Reload (seconds), Range (studs),
--   Spread (degrees of random aim), Pellets (bullets per shot, shotguns), Color (the gun's neon
--   accent and tracer), Sound (Config.Sounds effect key), Blurb (store text).

local Weapons = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

Weapons.List = {
	{
		Id = "Coral9", Name = "Coral 9", Kind = "Pistol", Price = 750, MinRank = 1,
		Damage = 20, HeadMult = 1.5, Rate = 3.5, Auto = false, Mag = 12, Reload = 1.4, Range = 260,
		Spread = 0.6, Pellets = 1, Color = rgb(255, 62, 165), Sound = "PistolShot",
		Blurb = "Light and forgiving. Everyone's first.",
	},
	{
		Id = "Riptide", Name = "Riptide SMG", Kind = "SMG", Price = 6500, MinRank = 3,
		Damage = 11, HeadMult = 1.5, Rate = 9, Auto = true, Mag = 30, Reload = 2.0, Range = 190,
		Spread = 2.2, Pellets = 1, Color = rgb(34, 225, 255), Sound = "SMGShot",
		Blurb = "Hold to spray. Best up close.",
	},
	{
		Id = "Breaker", Name = "Breaker Shotgun", Kind = "Shotgun", Price = 9500, MinRank = 5,
		Damage = 10, HeadMult = 1.25, Rate = 1.1, Auto = false, Mag = 6, Reload = 2.4, Range = 90,
		Spread = 5.5, Pellets = 7, Color = rgb(255, 138, 61), Sound = "ShotgunShot",
		Blurb = "Seven pellets a shot. Brutal at short range.",
	},
	{
		Id = "Longshore", Name = "Longshore Rifle", Kind = "Rifle", Price = 16000, MinRank = 8,
		Damage = 45, HeadMult = 2, Rate = 1.2, Auto = false, Mag = 5, Reload = 2.6, Range = 600,
		Spread = 0.15, Pellets = 1, Color = rgb(255, 214, 10), Sound = "RifleShot",
		Blurb = "Long range, big hits, slow to fire.",
	},
	{
		Id = "DutyPistol", Name = "Duty Pistol", Kind = "Police pistol", Price = 0, MinRank = 1, CopOnly = true,
		Damage = 18, HeadMult = 1.5, Rate = 3.5, Auto = false, Mag = 15, Reload = 1.3, Range = 260,
		Spread = 0.6, Pellets = 1, Color = rgb(80, 140, 255), Sound = "PistolShot",
		Blurb = "Police issue. Only hurts wanted suspects.",
	},
}

Weapons.ById = {}
for i, def in ipairs(Weapons.List) do
	def.Order = i
	Weapons.ById[def.Id] = def
end

Weapons.CopWeapon = "DutyPistol"
Weapons.StarterWeapon = "Coral9" -- the tutorial's "buy your first gun" step points at this one

-- The gun store. Position = the lot centre on the ground; Yaw turns the building (0 = its door faces
-- north, -Z). 90: the door faces west, toward the downtown spawn, on the plaza by Solana Ave.
Weapons.Store = {
	Name = "Shoreline Arms",
	Kind = "Gun store",
	Position = Vector3.new(-4, 0, 40),
	Yaw = 90,
	Reach = 16, -- studs from the counter prompt the server accepts a purchase from
}

Weapons.MaxHealth = 100
Weapons.RegenDelay = 6 -- seconds without being hurt before health comes back
Weapons.RegenPerSecond = 8
Weapons.SpawnShield = 6 -- seconds nobody can hurt you after you spawn (ends early if you fire)
Weapons.PassiveCooldown = 30 -- seconds after any PASSIVE switch before you can turn it on again
Weapons.CombatLock = 15 -- can't turn PASSIVE on within this long of firing or being hit
Weapons.AssaultHeat = 1 -- stars for hitting a player...
Weapons.AssaultCooldown = 12 -- ...at most once per this many seconds
Weapons.TakedownHeat = 1 -- extra stars for taking a player down
Weapons.TakedownMemory = 10 -- seconds a hit counts toward the takedown (kill feed, cop bounty)
Weapons.CarDamage = 1 -- car Health (0-100) per bullet that hits a car (pellets count 0.4 each)
Weapons.CopCarHeat = 1 -- stars for shooting a police car...
Weapons.CopCarCooldown = 15 -- ...at most once per this many seconds

-- Server-side sanity checks on a shot (the shooter's device finds the hit; the server checks it).
Weapons.MaxOriginOffset = 9 -- studs between the shot's start and the shooter's head
Weapons.HitSlack = 7 -- studs between the reported hit point and the part it says it hit
Weapons.RateSlack = 1.15 -- x Rate allowed (network jitter bunches shots together)

return Weapons
