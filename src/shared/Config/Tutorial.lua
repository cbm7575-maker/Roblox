-- Tutorial (ModuleScript, ReplicatedStorage.Shared.Config.Tutorial)
-- The first-session guide, in order. Text is what the "NEXT" pill says; Show is where its
-- SHOW ME button points the GPS ("OpenHeist" = the nearest heist that's open right now, otherwise a
-- place name from MapService). ServerOnly steps can only be completed by the server.

local Tutorial = {}

Tutorial.Bonus = 500

Tutorial.Steps = {
	{ Id = "phone", Text = "Open your PHONE (tap it or press P)" },
	{ Id = "car", Text = "Get in your car: walk up to it and press E" },
	{ Id = "rob", Text = "Rob a store with an OPEN sign: hold the ROB button", Show = "OpenHeist" },
	{ Id = "bank", Text = "Lose the cops, then bank your bag at the Hideout", Show = "Hideout", ServerOnly = true },
}

return Tutorial
