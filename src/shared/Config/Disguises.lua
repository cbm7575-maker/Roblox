-- Disguises (ModuleScript, ReplicatedStorage.Shared.Config.Disguises)
-- Hats and masks you can swap at a hideout wardrobe. Your "look" (hat + mask) is what store cameras
-- and cops put on your Suspect Card; changing it while cops can't see you shakes them off.
-- Parts are welded to the head; offsets are for a standard R15 head (about 1.2 studs).

local Disguises = {}

Disguises.Hats = {
	{ Id = "none", Name = "No hat" },
	{ Id = "cap_pink", Name = "Pink cap", Color = Color3.fromRGB(255, 62, 165), Kind = "cap" },
	{ Id = "cap_cyan", Name = "Cyan cap", Color = Color3.fromRGB(34, 225, 255), Kind = "cap" },
	{ Id = "cap_black", Name = "Black cap", Color = Color3.fromRGB(28, 28, 34), Kind = "cap" },
	{ Id = "bucket_white", Name = "White bucket hat", Color = Color3.fromRGB(240, 240, 235), Kind = "bucket" },
}

Disguises.Masks = {
	{ Id = "none", Name = "No mask" },
	{ Id = "bandana_red", Name = "Red bandana", Color = Color3.fromRGB(220, 40, 60), Kind = "bandana" },
	{ Id = "bandana_black", Name = "Black bandana", Color = Color3.fromRGB(28, 28, 34), Kind = "bandana" },
	{ Id = "shades", Name = "Neon shades", Color = Color3.fromRGB(123, 47, 255), Kind = "shades" },
}

local function index(list)
	local map = {}
	for _, x in ipairs(list) do
		map[x.Id] = x
	end
	return map
end
Disguises.HatById = index(Disguises.Hats)
Disguises.MaskById = index(Disguises.Masks)

-- Words for the Suspect Card, e.g. "pink cap, red bandana" or "no disguise".
function Disguises.Describe(hatId, maskId)
	local parts = {}
	local hat = Disguises.HatById[hatId or "none"]
	local mask = Disguises.MaskById[maskId or "none"]
	if hat and hat.Id ~= "none" then
		table.insert(parts, string.lower(hat.Name))
	end
	if mask and mask.Id ~= "none" then
		table.insert(parts, string.lower(mask.Name))
	end
	return #parts > 0 and table.concat(parts, ", ") or "no disguise"
end

return Disguises
