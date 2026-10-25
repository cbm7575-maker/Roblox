-- HouseClient (ModuleScript, StarterPlayerScripts.Controllers.HouseClient)
-- Opens the houses (Workspace.Properties, built by PropertyService/HouseBuilder) for their owners, on
-- this device only. Character and car physics run on the owner's device, so a door that stops
-- colliding here lets only this player through; the server keeps every door shut for everyone else.
--   * Owner-open parts (attribute OwnerOpen): front and patio door blockers, garage doors, the
--     mansion gate. They open while the local player owns the house (OwnedProps) and is a civilian
--     with no heat (no hiding from the cops at home), or always while standing in one of the house's
--     InsideZone boxes (nobody is ever shut in). Opening = stop colliding; parts with ClosedCF /
--     OpenCF attributes also swing or tilt open (tweened).
--   * Garage "Drive" prompts (attribute OwnerUserId) show only to that owner.
--   * The sale sign reads "YOUR HOME" / "YOU OWN THIS" for owners (the server's text says FOR SALE).
-- Streaming: parts come and go as the player moves, so they are tracked through DescendantAdded and
-- every check re-applies the state to whatever is loaded right now (a few dozen parts, 4 times a second).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local HouseClient = {}

local player = Players.LocalPlayer

local CHECK_EVERY = 0.25
local SWING = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local doors = {} -- [part] = { id, collides = server CanCollide, closed = CFrame?, open = CFrame?, isOpen }
local zones = {} -- [part] = id
local prompts = {} -- [ProximityPrompt] = true (garage Drive prompts)
local signs = {} -- [TextLabel] = { id, text = the server's text, override = showing ours }

-- The house (PropId) an instance belongs to.
local function houseOf(inst)
	local node = inst.Parent
	while node and node ~= Workspace do
		local id = node:GetAttribute("PropId")
		if node:IsA("Model") and type(id) == "string" then
			return id
		end
		node = node.Parent
	end
	return nil
end

local function register(inst)
	if inst:IsA("BasePart") then
		if inst:GetAttribute("OwnerOpen") then
			local id = houseOf(inst)
			if id then
				local closed, open = inst:GetAttribute("ClosedCF"), inst:GetAttribute("OpenCF")
				doors[inst] = {
					id = id,
					collides = inst.CanCollide,
					closed = typeof(closed) == "CFrame" and closed or nil,
					open = typeof(open) == "CFrame" and open or nil,
					isOpen = false,
				}
			end
		elseif inst.Name == "InsideZone" then
			zones[inst] = houseOf(inst)
		end
	elseif inst:IsA("ProximityPrompt") and inst:GetAttribute("OwnerUserId") then
		prompts[inst] = true
		inst.Enabled = inst:GetAttribute("OwnerUserId") == player.UserId
	elseif inst:IsA("TextLabel") and inst.Name == "Status" then
		local id = houseOf(inst)
		if id then
			signs[inst] = { id = id, text = inst.Text }
		end
	end
end

local function unregister(inst)
	doors[inst] = nil
	zones[inst] = nil
	prompts[inst] = nil
	signs[inst] = nil
end

local function setOpen(part, d, open)
	d.isOpen = open
	if d.collides then
		part.CanCollide = not open
	end
	local target = open and d.open or d.closed
	if target then
		TweenService:Create(part, SWING, { CFrame = target }):Play()
	end
end

local function insideOf(pos)
	local list = {}
	for zone, id in pairs(zones) do
		if id and zone.Parent then
			local rel = zone.CFrame:PointToObjectSpace(pos)
			local half = zone.Size / 2 + Vector3.new(1, 1, 1)
			if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
				list[id] = true
			end
		end
	end
	return list
end

local function check()
	local mine = {}
	for id in string.gmatch(player:GetAttribute("OwnedProps") or "", "[^,]+") do
		mine[id] = true
	end
	local welcome = player:GetAttribute("Side") == "Civilian" and (player:GetAttribute("Heat") or 0) <= 0
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local inside = root and insideOf(root.Position) or {}
	for part, d in pairs(doors) do
		if part.Parent then
			local open = (mine[d.id] == true and welcome) or inside[d.id] == true
			if open ~= d.isOpen then
				setOpen(part, d, open)
			elseif d.collides and part.CanCollide == open then
				part.CanCollide = not open -- re-assert (the server may have re-sent the part)
			end
		else
			doors[part] = nil
		end
	end
	for pp in pairs(prompts) do
		if pp.Parent then
			local on = pp:GetAttribute("OwnerUserId") == player.UserId
			if pp.Enabled ~= on then
				pp.Enabled = on
			end
		else
			prompts[pp] = nil
		end
	end
	local home = player:GetAttribute("HomeId")
	for label, s in pairs(signs) do
		if label.Parent then
			if mine[s.id] then
				local want = home == s.id and "🏠 YOUR HOME" or "★ YOU OWN THIS"
				if label.Text ~= want then
					if not s.override then
						s.text = label.Text -- the server's text, to put back if this ever changes
					end
					label.Text = want
					s.override = true
				end
			elseif s.override then
				label.Text = s.text
				s.override = false
			end
		else
			signs[label] = nil
		end
	end
end

function HouseClient.Init()
	task.spawn(function()
		local folder = Workspace:WaitForChild("Properties", 60)
		if not folder then
			return
		end
		folder.DescendantAdded:Connect(register)
		folder.DescendantRemoving:Connect(unregister)
		for _, d in ipairs(folder:GetDescendants()) do
			register(d)
		end
		while true do
			local ok, err = pcall(check)
			if not ok then
				warn("[HouseClient] " .. tostring(err))
			end
			task.wait(CHECK_EVERY)
		end
	end)
end

return HouseClient
