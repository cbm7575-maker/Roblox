-- Apartments (ModuleScript, ReplicatedStorage.Shared.Config.Apartments)
-- Apartment towers you can tour, open to everyone (ApartmentService on the server builds them; MapService
-- lists each one on the phone's GPS under PLACES). Nothing is bought or saved: walk in at the street
-- door and you come out of the elevator in a furnished glass penthouse on the tower's roof, with a pool
-- terrace and the real city round it. Anyone on foot, a citizen or a cop, who isn't wanted can go up.
--
-- Pick: which of the city's own towers get an entrance and a penthouse. At start-up ApartmentService
-- looks at every DecoBuilding model in Workspace.City.Art's Folders and keeps those whose highest Body /
-- Tier box tops out at MinTop studs or more with a flat top at least MinRoof x MinRoof, whose middle is in
-- one of Areas (Config.Ambience.Districts area keys: the first rectangle that holds it), that have no
-- hotel sign of their own (ArtGen's "Sign") and no other model's parts on the roof (a tower sign, a
-- billboard), and that stay clear (by KeepClearMargin) of every part in the KeepClear folders of
-- Workspace (heist sites, homes, showrooms, the gun shop, the Big Score) and of KeepClearRects (the Big
-- Score's two lots, in case its folder is built later). The survivors are sorted by position (x, then z)
-- and taken in that order while each new one is at least Spacing studs (flat) from every one already
-- taken, up to Count.Max. A tower is only taken with a road within RoadReach studs straight out from the
-- middle of one facade (the front first: a DecoBuilding faces its street), at least MinRoadGap studs away
-- (room for the canopy), and nothing solid in front of that door. The place's art alone decides, so
-- every server gets the same towers, in the same order, with the same Names and Styles.
--
-- Penthouse: the indoor part is a fixed 50 x 32 studs (ApartmentService lays the rooms out on it), at the
-- back of the roof, Inset studs in from the edge; the rest of the roof is terrace. That needs a roof of
-- at least 56 x 56: keep MinRoof at 56 or more. Ceiling = the indoor height (glass walls and partitions);
-- Rail = the glass railing round every roof edge; Guard = the top of the invisible wall above it (higher
-- than anyone can jump from a planter). All in studs above the roof.

local Apartments = {}

Apartments.Count = { Min = 6, Max = 8 } -- towers to pick (fewer than Min only warns: the art ran out)

-- Names in pick order, then Styles round and round (Accent = cushions, blanket, parasol; Neon = the
-- strips that glow after dark). Our own names only: no real buildings, places or brands.
Apartments.Names = {
	"Coral Tower", "Bayview Residences", "The Solana", "Palm Court", "Harbor Lofts", "Marina Point",
	"Azure Heights", "Sea Grape Towers", "Sunrise Terrace", "Pelican Point",
}
Apartments.Styles = {
	{ Accent = Color3.fromRGB(46, 128, 136), Neon = Color3.fromRGB(34, 225, 255) }, -- teal / cyan
	{ Accent = Color3.fromRGB(190, 92, 78), Neon = Color3.fromRGB(255, 62, 165) }, -- coral / pink
	{ Accent = Color3.fromRGB(186, 146, 64), Neon = Color3.fromRGB(255, 214, 10) }, -- ochre / yellow
	{ Accent = Color3.fromRGB(64, 84, 140), Neon = Color3.fromRGB(123, 47, 255) }, -- navy / purple
	{ Accent = Color3.fromRGB(70, 128, 90), Neon = Color3.fromRGB(110, 242, 196) }, -- palm green / mint
	{ Accent = Color3.fromRGB(176, 104, 58), Neon = Color3.fromRGB(255, 138, 61) }, -- terracotta / orange
}

Apartments.Kind = "Penthouse tour · open to all" -- the GPS list's line under the name

Apartments.Pick = {
	Folders = { "Buildings", "Infill", "BlockFill" }, -- under Workspace.City.Art (ArtGen, Restyle)
	MinTop = 90, -- studs: the highest part's top
	MinRoof = 56, -- studs: its flat top, both ways (the penthouse needs 56 x 56)
	Areas = { Downtown = true, Marina = true, Beach = true, Docks = true }, -- Solana Heights, Marina Row, Flamingo Beach, Rustwater Docks
	RoadReach = 45, -- studs from the entrance facade to a road
	MinRoadGap = 9, -- studs: the canopy reaches 8.4 out from the facade
	Spacing = 300, -- studs between two picked towers
	KeepClear = { "Heists", "BigScore", "Homes", "Dealerships", "Shops" }, -- Workspace folders
	-- { x1, x2, z1, z2 }: the Big Score's Ironclad depot (the port) and Solana Gold Reserve (Palm Hills),
	-- where Config.Heists puts them
	KeepClearRects = {
		require(script.Parent:WaitForChild("Heists")).BigScore.DepotRect,
		require(script.Parent:WaitForChild("Heists")).BigScore.ReserveRect,
	},
	KeepClearMargin = 12, -- studs round every keep-clear part and rect
}

Apartments.Penthouse = {
	Inset = 3, -- studs from the roof's back and side edges to the glass
	Ceiling = 14, -- indoor height
	GlassTransparency = 0.55, -- the walls: see the city through them
	Rail = 8, -- glass railing height
	Guard = 24, -- top of the invisible wall over the railing
}

-- Lights (Realistic lighting: indoor lights stay low or the rooms white out). Ceiling lights and the
-- pool light are always on; lamps (NightLamp) come on after dark.
Apartments.Lights = {
	Ceiling = 0.35, -- brightness of the recessed ceiling lights
	CeilingRange = 20,
	Lamp = 0.3, -- bedside and floor lamps, pendants
	Pool = 0.4, -- the soft light under the pool water
	Canopy = 1, -- the street door's canopy downlights (outdoors, after dark)
}

Apartments.PromptRange = 10 -- studs: the street door's "Enter" prompt
Apartments.ElevatorRange = 7 -- studs: the elevator's prompt (you arrive 8.7 from it: never at once)
Apartments.EnterRange = 14 -- studs: how close the server wants you to the door (or the elevator)
Apartments.FadeTime = 0.35 -- seconds of black screen before the move (HouseClient's HouseFade)

return Apartments
