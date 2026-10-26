-- Tutorial (ModuleScript, ReplicatedStorage.Shared.Config.Tutorial)
-- The first-session guide, in order: action first (car, rob, bank), the phone last (it opens on GARAGE).
-- Text is what the "NEXT" pill says; Show is where its SHOW ME button points ("OpenHeist" = the nearest
-- heist that's open right now, "Garage" = open the phone on GARAGE, otherwise a place name from
-- MapService). ShowMaxTier (with "OpenHeist"): prefer heists up to this tier; if none is open, the
-- nearest one without a prep job. ServerOnly steps can only be completed by the server.
-- Saves count finished steps (TutorialService), so changing this order needs a step in its migrate().
-- After the last step, new players carry on with the goal chain in Config.Journey.

local Tutorial = {}

Tutorial.Bonus = 500

Tutorial.Steps = {
	{ Id = "car", Text = "Get in your car: walk up to it and press F or E (or tap GET IN)" },
	-- A 1-star store first (Glow Mart, Fuel Stop, ATM), not a 2-star jewellery job.
	{ Id = "rob", Text = "Rob a store with an OPEN sign: hold the ROB button", Show = "OpenHeist", ShowMaxTier = 1 },
	{ Id = "bank", Text = "Lose the cops, then bank your bag at the Hideout", Show = "Hideout", ServerOnly = true },
	{ Id = "phone", Text = "Open your PHONE (tap it or press P): your cars live in GARAGE", Show = "Garage" },
}

return Tutorial
