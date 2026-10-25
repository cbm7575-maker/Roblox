-- Tutorial (ModuleScript, ReplicatedStorage.Shared.Config.Tutorial)
-- The first-session guide, in order (v2, 2026-10). Each step has an Id (saved by Id, so reordering
-- never breaks old saves) and the text the top bar shows: one string, or one per device
-- (Touch / Keyboard / Gamepad) so phones read "tap" and PCs "press E". "{bag}" becomes the bag's value.
-- Keep each under ~40 characters when the step has Show (~55 without): two lines at 14 px on a
-- 667 px-wide phone.
-- Show = where SHOW ME (and the automatic route when the step starts) points the GPS:
--   "MyCar"    the player's own car (Workspace.Vehicles, OwnerUserId)
--   "Beginner" the nearest OPEN beginner heist (tier 1, no rank or prep needed)
--   otherwise  a place name from MapService
-- ServerOnly steps can only be completed by the server (TutorialService checks the bag and heat).
-- Steps can be done early (rob before getting in the car, say): they count once reached.

local Tutorial = {}

Tutorial.Bonus = 500

Tutorial.Steps = {
	{ Id = "car", Show = "MyCar", Text = {
		Touch = "Get in your car: walk up, tap DRIVE",
		Keyboard = "Get in your car: walk up, press E",
		Gamepad = "Get in your car: walk up, press X",
	} },
	{ Id = "rob", Show = "Beginner", ServerOnly = true, Text = {
		Touch = "Rob an OPEN store: on foot, hold ROB",
		Keyboard = "Rob an OPEN store: on foot, hold E",
		Gamepad = "Rob an OPEN store: on foot, hold X",
	} },
	{ Id = "escape", ServerOnly = true,
		Text = "Lose the cops: hide! Hollow stars = they're searching" },
	{ Id = "bank", Show = "Hideout", ServerOnly = true, Text = "Bank your {bag} at the Hideout" },
	-- WeaponService completes it when any gun is bought (Config.Weapons: the Coral 9 is $750).
	{ Id = "gun", Show = "Shoreline Arms", ServerOnly = true, Text = "Buy your first gun at Shoreline Arms" },
	{ Id = "phone", Text = {
		Touch = "On foot, tap PHONE to open your phone",
		Keyboard = "Press P to open your phone",
		Gamepad = "Press D-pad down to open your phone",
	} },
}

-- The v1 tutorial saved a step NUMBER (data.flags.tutorial) in this order; TutorialService migrates it.
Tutorial.OldOrder = { "phone", "car", "rob", "bank" }

return Tutorial
