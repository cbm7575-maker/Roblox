-- Teams (ModuleScript, ReplicatedStorage.Shared.Config.Teams)
-- Open-world roles (direction change 2026-09-28): everyone is a Civilian free to roam; committing
-- a crime gives heat (Wanted) without changing role. Cop is a job you choose. Arrested Wanted
-- players become Prisoners until released or they break out.
-- "Side" is the name code uses everywhere (player attribute "Side").

local Teams = {}

Teams.List = {
	{ Side = "Civilian", TeamName = "Citizens", Color = BrickColor.new("Hot pink"), Starter = "Palmetto",
		Label = "FREE ROAM", Pitch = "Drive, race, explore... and rob if you dare." },
	{ Side = "Cop", TeamName = "Police", Color = BrickColor.new("Cyan"), Starter = "SunrayPatrol",
		Label = "POLICE", Pitch = "Chase wanted players. Earn bounties." },
	{ Side = "Prisoner", TeamName = "Prisoners", Color = BrickColor.new("Deep orange"), Starter = nil,
		Label = "PRISONER", Pitch = "Break out or wait it out." },
}

Teams.BySide = {}
for _, t in ipairs(Teams.List) do
	Teams.BySide[t.Side] = t
end

-- About 1 cop for every 2 other players; there's always room for at least one cop.
function Teams.MaxCops(playerCount)
	return math.max(1, math.floor(playerCount / 3))
end

Teams.SwitchCooldown = 10 -- seconds between role switches

return Teams
