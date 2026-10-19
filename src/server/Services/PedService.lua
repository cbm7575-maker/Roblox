-- PedService (ModuleScript, ServerScriptService.Services.PedService)
-- Makes a handful of pedestrian looks at start-up (R15 rigs from HumanoidDescriptions: skin tones,
-- pastel "shirts" and "shorts" as body colours) into ReplicatedStorage.PedTemplates. Each client then
-- runs its own pedestrians from these (PedClient), so they cost the server nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PedService = {}

local SKIN = {
	Color3.fromRGB(255, 220, 185), Color3.fromRGB(234, 192, 150), Color3.fromRGB(205, 160, 120),
	Color3.fromRGB(160, 110, 75), Color3.fromRGB(110, 75, 55),
}
local SHIRTS = {
	Color3.fromRGB(255, 120, 190), Color3.fromRGB(110, 242, 196), Color3.fromRGB(255, 214, 10),
	Color3.fromRGB(34, 225, 255), Color3.fromRGB(255, 138, 61), Color3.fromRGB(190, 170, 255),
	Color3.fromRGB(245, 245, 250), Color3.fromRGB(255, 90, 90),
}
local SHORTS = {
	Color3.fromRGB(40, 60, 120), Color3.fromRGB(245, 235, 215), Color3.fromRGB(60, 60, 70),
	Color3.fromRGB(120, 200, 230), Color3.fromRGB(200, 90, 160),
}

local TEMPLATES = 10

function PedService.Init()
	local folder = ReplicatedStorage:FindFirstChild("PedTemplates") or Instance.new("Folder")
	folder.Name = "PedTemplates"
	folder.Parent = ReplicatedStorage
	task.spawn(function()
		local rng = Random.new()
		for i = 1, TEMPLATES do
			local ok, model = pcall(function()
				local desc = Instance.new("HumanoidDescription")
				local skin = SKIN[rng:NextInteger(1, #SKIN)]
				local shirt = SHIRTS[rng:NextInteger(1, #SHIRTS)]
				local shorts = SHORTS[rng:NextInteger(1, #SHORTS)]
				desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = skin, skin, skin
				desc.TorsoColor = shirt
				desc.LeftLegColor, desc.RightLegColor = shorts, shorts
				return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
			end)
			if ok and model then
				model.Name = "Ped" .. i
				-- Clients animate them themselves; scripts inside wouldn't run anyway.
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BaseScript") then
						d:Destroy()
					end
				end
				local hum = model:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					hum.WalkSpeed = 7
				end
				model.Parent = folder
			end
		end
	end)
end

return PedService
