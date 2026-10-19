-- PropertyService (ModuleScript, ServerScriptService.Services.PropertyService)
-- Safehouses players can buy (Config.Properties). Ownership is per player and never exclusive.
--   * At start-up each property gets a neon door frame, a glowing pad in front and a sign
--     (Workspace.Properties.<Id>). The door's floor is found by raycast; a blocked spot is nudged.
--     The sign reads "FOR SALE $25,000" or "<DisplayName>'s place" when someone in the server owns it.
--   * Door ProximityPrompts (in person only; the server re-checks distance, side and money):
--       Buy (E)          civilians, free-roam rank >= MinRank, EconomyService.Spend(Price)
--       Set as home (Q)  an owned property becomes your home (the first one bought is automatic)
--       Collect rent (X) rent accrues at Rent dollars an hour, up to Properties.RentCapHours, into Cash
--     Prompts carry attributes PropId and PropAction ("Buy" | "SetHome" | "Collect") so a client can
--     hide the ones that don't apply to its player.
--   * Perks: civilians with a home respawn at its door (not prisoners, cops or wanted players);
--     standing on the pad of a property you own with Heat 0 banks your bag like the hideout
--     (EconomyService.BankCarried + the "Banked" event); rent.
--   * Remote RequestProperty("SetHome", id): the phone may only set an owned property as home.
--   * Remote PropertyEvent (server -> client): "Bought" { Id, Name, Price, Home }, "Rent" { Id, Amount },
--     "Home" { Id }.
-- Saved (created lazily): data.props = { owned = { [id] = true }, home = id or nil, rentAt = { [id] = os.time() } }.
-- Player attributes (phone HOMES app): OwnedProps (comma list of ids), HomeId, Rent_<id> (uncollected
-- dollars, refreshed every 30 s for owned properties).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Properties = require(ReplicatedStorage.Shared.Config.Properties)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local Telemetry = require(ServerScriptService.Services.Telemetry)

local PropertyService = {}

local CHECK_EVERY = 0.5 -- home banking
local RENT_REFRESH = 30 -- Rent_<id> attributes
local PAD = 12 -- pad size (studs), in front of the door
local SPAWN_OUT = 7 -- respawn spot: studs in front of the door
local FRESH_SPAWN = 8 -- a character this new (s) is still moved home when the save loads late
local WARN_EVERY = 6

local doors = {} -- [id] = { def, cf (door on the floor, LookVector = out), pad, spawn, tops = { TextLabel } }
local spawnedAt = {} -- [player] = os.clock() of their latest character
local lastWarn = {} -- [player] = os.clock() of the last "lose your heat" toast
local notify, banked, propertyEvent

local function money(n)
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return "$" .. out
end

-- The player's data.props (made the first time `create` is set), sanitised for older or odd saves.
local function props(player, create)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local p = data.props
	if type(p) ~= "table" then
		if not create then
			return nil
		end
		p = {}
		data.props = p
	end
	if type(p.owned) ~= "table" then
		p.owned = {}
	end
	if type(p.rentAt) ~= "table" then
		p.rentAt = {}
	end
	if p.home ~= nil and not (Properties.ById[p.home] and p.owned[p.home]) then
		p.home = nil
	end
	return p
end

function PropertyService.Owns(player, id)
	local p = props(player)
	return p ~= nil and p.owned[id] == true
end

function PropertyService.HomeOf(player)
	local p = props(player)
	return p and p.home or nil
end

-- Attributes for the phone.
local function mirror(player)
	local p = props(player)
	local list = {}
	local t = os.time()
	for _, def in ipairs(Properties.List) do
		local mine = p ~= nil and p.owned[def.Id] == true
		local due = nil
		if mine then
			table.insert(list, def.Id)
			if type(p.rentAt[def.Id]) ~= "number" then
				p.rentAt[def.Id] = t
			end
			due = Properties.RentDue(def, p.rentAt[def.Id], t)
		end
		if player:GetAttribute("Rent_" .. def.Id) ~= due then
			player:SetAttribute("Rent_" .. def.Id, due)
		end
	end
	local owned = table.concat(list, ",")
	if player:GetAttribute("OwnedProps") ~= owned then
		player:SetAttribute("OwnedProps", owned)
	end
	local home = p and p.home or nil
	if player:GetAttribute("HomeId") ~= home then
		player:SetAttribute("HomeId", home)
	end
end

local function refreshSign(id)
	local d = doors[id]
	if not d then
		return
	end
	local names = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if PropertyService.Owns(pl, id) then
			table.insert(names, pl.DisplayName)
		end
	end
	local def = d.def
	local top
	if #names == 0 then
		top = "FOR SALE  " .. money(def.Price) .. ((def.MinRank and def.MinRank > 1) and ("  ·  RANK " .. def.MinRank) or "")
	elseif #names == 1 then
		top = names[1] .. "'s place"
	elseif #names == 2 then
		top = names[1] .. " & " .. names[2] .. "'s place"
	else
		top = names[1] .. " & " .. (#names - 1) .. " more"
	end
	for _, label in ipairs(d.tops) do
		label.Text = top
	end
end

local function refreshAllSigns()
	for id in pairs(doors) do
		refreshSign(id)
	end
end

-- Is the player standing (or parked) at this property's door?
local function atDoor(player, d)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root then
		return false
	end
	local rel = root.Position - d.cf.Position
	return Vector3.new(rel.X, 0, rel.Z).Magnitude <= Properties.DoorReach and math.abs(rel.Y) < 12
end

local function onPad(d, pos)
	local rel = d.pad.CFrame:PointToObjectSpace(pos)
	return math.abs(rel.X) <= PAD / 2 + 1 and math.abs(rel.Z) <= PAD / 2 + 1 and rel.Y > -3 and rel.Y < 15
end

local function setHome(player, id)
	local p = props(player)
	if not p or not p.owned[id] then
		notify:FireClient(player, "PropNotOwned")
		return
	end
	p.home = id
	mirror(player)
	notify:FireClient(player, "PropHomeSet")
	propertyEvent:FireClient(player, "Home", { Id = id })
end

local function onBuy(player, id)
	local d = doors[id]
	if not d or not RateLimit.Allow(player, "PropBuy", 1, 2) or not atDoor(player, d) then
		return
	end
	local def = d.def
	if player:GetAttribute("Side") ~= "Civilian" then
		notify:FireClient(player, "PropCiviliansOnly")
		return
	end
	if not DataService.Get(player) then
		return -- save still loading
	end
	if PropertyService.Owns(player, id) then
		notify:FireClient(player, "PropAlreadyOwned")
		return
	end
	if def.MinRank and (player:GetAttribute("CivRank") or 1) < def.MinRank then
		notify:FireClient(player, "PropNeedsRank_" .. def.MinRank)
		return
	end
	if not EconomyService.Spend(player, def.Price, "property:" .. id) then
		notify:FireClient(player, "NotEnoughCash")
		return
	end
	local p = props(player, true)
	if not p then
		return
	end
	p.owned[id] = true
	p.rentAt[id] = os.time()
	local firstHome = p.home == nil
	if firstHome then
		p.home = id
	end
	mirror(player)
	refreshSign(id)
	notify:FireClient(player, "PropBought")
	propertyEvent:FireClient(player, "Bought", { Id = id, Name = def.Name, Price = def.Price, Home = firstHome })
	local ok, err = pcall(function()
		require(ServerScriptService.Services.ProgressService).Event(player, "PropertyBought")
	end)
	if not ok then
		warn("[PropertyService] " .. tostring(err))
	end
	Telemetry.Custom(player, "Property_" .. id, def.Price)
	task.spawn(DataService.SaveNow, player) -- a big purchase: save it right away
end

local function onSetHomePrompt(player, id)
	local d = doors[id]
	if d and RateLimit.Allow(player, "PropHome", 1, 2) and atDoor(player, d) then
		setHome(player, id)
	end
end

local function onCollect(player, id)
	local d = doors[id]
	if not d or not RateLimit.Allow(player, "PropRent", 1, 2) or not atDoor(player, d) then
		return
	end
	local p = props(player)
	if not p or not p.owned[id] then
		notify:FireClient(player, "PropNotOwned")
		return
	end
	local t = os.time()
	local due = Properties.RentDue(d.def, p.rentAt[id], t)
	if due < 1 then
		notify:FireClient(player, "PropNoRent")
		return
	end
	-- Never move the clock back (a server whose clock runs behind must not let rent be paid twice).
	p.rentAt[id] = math.max(type(p.rentAt[id]) == "number" and p.rentAt[id] or t, t)
	EconomyService.AddCash(player, due, "rent:" .. id)
	mirror(player)
	notify:FireClient(player, "PropRentCollected")
	propertyEvent:FireClient(player, "Rent", { Id = id, Amount = due })
end

-- Building ------------------------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude

local function excludeList(folder)
	local list = { folder }
	for _, name in ipairs({ "Vehicles", "NPCs", "Smoke" }) do
		local f = Workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

-- The floor under a spot: the first surface below knee height (awnings and trees above don't count).
local function floorAt(x, z)
	local hit = Workspace:Raycast(Vector3.new(x, 6, z), Vector3.new(0, -30, 0), rayParams)
	return hit and hit.Position.Y or 0
end

-- Is something solid where the door frame would stand (8 wide, 2 deep, knee height to lintel)?
local function blocked(cf)
	for _, p in ipairs(Workspace:GetPartBoundsInBox(cf * CFrame.new(0, 6, 0), Vector3.new(8, 9, 2), overlap)) do
		if p.CanCollide and p.Transparency < 1 then
			return true
		end
	end
	return false
end

-- Door CFrame on the floor, LookVector = out toward the road; nudged out or sideways if blocked.
local function placeDoor(def, face)
	local side = Vector3.new(-face.Z, 0, face.X)
	local base = Vector3.new(def.Pos.X, 0, def.Pos.Z)
	local first
	for _, off in ipairs({ { 0, 0 }, { 3, 0 }, { 6, 0 }, { 0, 4 }, { 0, -4 }, { 3, 4 }, { 3, -4 }, { 9, 0 }, { 12, 0 } }) do
		local p = base + face * off[1] + side * off[2]
		local pos = Vector3.new(p.X, floorAt(p.X, p.Z), p.Z)
		local cf = CFrame.lookAt(pos, pos + face)
		first = first or cf
		if not blocked(cf) then
			if off[1] ~= 0 or off[2] ~= 0 then
				warn(string.format("[PropertyService] %s door nudged %d,%d studs", def.Id, off[1], off[2]))
			end
			return cf
		end
	end
	warn("[PropertyService] " .. def.Id .. " door spot is blocked; building it anyway")
	return first
end

local function part(parent, name, size, cf, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	-- Purely visual: never blocks cars, sight lines (HeatService), cameras or wheel rays.
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function signFace(board, face, def)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.MaxDistance = 300
	local top = Instance.new("TextLabel")
	top.Name = "Status"
	top.BackgroundTransparency = 1
	top.Position = UDim2.fromScale(0.03, 0.05)
	top.Size = UDim2.fromScale(0.94, 0.55)
	top.Font = Enum.Font.FredokaOne
	top.TextScaled = true
	top.TextColor3 = Color3.new(1, 1, 1)
	top.TextStrokeTransparency = 0.4
	top.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Name = "PlaceName"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0.03, 0.62)
	sub.Size = UDim2.fromScale(0.94, 0.32)
	sub.Font = Enum.Font.FredokaOne
	sub.TextScaled = true
	sub.TextColor3 = def.Color
	sub.Text = def.Name
	sub.Parent = gui
	gui.Parent = board
	return top
end

local function prompt(door, id, action, y, text, object, key, pad, hold)
	local att = Instance.new("Attachment")
	att.Name = action .. "Point"
	att.Position = Vector3.new(0, y, -0.4) -- front side of the door panel
	att.Parent = door
	local pp = Instance.new("ProximityPrompt")
	pp.Name = action .. "Prompt"
	pp.ActionText = text
	pp.ObjectText = object
	pp.HoldDuration = hold or 0
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = key
	pp.GamepadKeyCode = pad
	pp:SetAttribute("PropId", id)
	pp:SetAttribute("PropAction", action)
	pp.Parent = att
	return pp
end

local function build(def, folder)
	local face = Vector3.new(def.Face and def.Face.X or 0, 0, def.Face and def.Face.Z or 1)
	face = face.Magnitude > 0.1 and face.Unit or Vector3.new(0, 0, 1)
	local cf = placeDoor(def, face)
	local model = Instance.new("Model")
	model.Name = def.Id
	model:SetAttribute("PropId", def.Id)
	local dark = Color3.fromRGB(24, 18, 40)
	local door = part(model, "Door", Vector3.new(6, 9, 0.4), cf * CFrame.new(0, 4.6, 0), dark, Enum.Material.Glass, 0.15)
	model.PrimaryPart = door
	for _, x in ipairs({ -3.6, 3.6 }) do
		part(model, "Post", Vector3.new(0.8, 10, 0.8), cf * CFrame.new(x, 5, 0), def.Color, Enum.Material.Neon)
	end
	part(model, "Lintel", Vector3.new(8, 0.8, 0.8), cf * CFrame.new(0, 10.4, 0), def.Color, Enum.Material.Neon)
	local board = part(model, "Sign", Vector3.new(11, 3.2, 0.4), cf * CFrame.new(0, 12.8, 0), dark, Enum.Material.SmoothPlastic)
	local tops = { signFace(board, Enum.NormalId.Front, def), signFace(board, Enum.NormalId.Back, def) }
	local padCf = cf * CFrame.new(0, 0.12, -(PAD / 2 + 1))
	local pad = part(model, "Pad", Vector3.new(PAD, 0.2, PAD), padCf, def.Color, Enum.Material.Neon, 0.6)
	local light = Instance.new("PointLight")
	light.Color = def.Color
	light.Range = 16
	light.Brightness = 1.5
	light.Parent = door
	-- Respawn spot on the pad, facing the street.
	local out = cf.Position + face * SPAWN_OUT
	local spawnPos = Vector3.new(out.X, floorAt(out.X, out.Z) + 3.2, out.Z)
	local d = {
		def = def, cf = cf, pad = pad, tops = tops,
		spawn = CFrame.lookAt(spawnPos, spawnPos + face),
	}
	local name = def.Name
	prompt(door, def.Id, "Buy", -1.2, "Buy " .. money(def.Price), name, Enum.KeyCode.E, Enum.KeyCode.ButtonX, 1)
		.Triggered:Connect(function(player)
			onBuy(player, def.Id)
		end)
	prompt(door, def.Id, "SetHome", 1.2, "Set as home", name, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
		.Triggered:Connect(function(player)
			onSetHomePrompt(player, def.Id)
		end)
	prompt(door, def.Id, "Collect", 3.6, "Collect rent", name, Enum.KeyCode.X, Enum.KeyCode.ButtonR1)
		.Triggered:Connect(function(player)
			onCollect(player, def.Id)
		end)
	model.Parent = folder
	doors[def.Id] = d
	refreshSign(def.Id)
end

-- Perks ----------------------------------------------------------------------------------------------

-- Civilians (not wanted) respawn at their home's door.
local function sendHome(player, char)
	if player:GetAttribute("Side") ~= "Civilian" or (player:GetAttribute("Heat") or 0) > 0 then
		return
	end
	local p = props(player)
	local d = p and p.home and doors[p.home]
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not d or not hum or hum.Health <= 0 or hum.SeatPart then
		return
	end
	char:PivotTo(d.spawn)
end

local function onCharacter(player, char)
	spawnedAt[player] = os.clock()
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if not root then
		return
	end
	task.wait(0.15) -- after the default spawn placement, before VehicleService picks the nearest car pad
	if player.Character == char and player.Parent == Players then
		sendHome(player, char)
	end
end

-- Bank the bag on the pad of any property you own, as long as you have no heat at all.
local function homeCheck(player)
	if player:GetAttribute("Side") ~= "Civilian" or EconomyService.GetCarried(player) <= 0 then
		return
	end
	local p = props(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not p or not root then
		return
	end
	for id in pairs(p.owned) do
		local d = doors[id]
		if d and onPad(d, root.Position) then
			if (player:GetAttribute("Heat") or 0) > 0 then
				local t = os.clock()
				if not lastWarn[player] or t - lastWarn[player] > WARN_EVERY then
					lastWarn[player] = t
					notify:FireClient(player, "PropHotNoBank")
				end
			else
				local amount = EconomyService.BankCarried(player, "home:" .. id)
				if amount > 0 then
					banked:FireClient(player, amount)
				end
			end
			return
		end
	end
end

function PropertyService.Init()
	notify = Remotes.Event("Notify")
	banked = Remotes.Event("Banked")
	propertyEvent = Remotes.Event("PropertyEvent")

	local folder = Workspace:FindFirstChild("Properties")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "Properties"
	folder.Parent = Workspace
	local exclude = excludeList(folder)
	rayParams.FilterDescendantsInstances = exclude -- terrain still counts as a floor
	local noTerrain = table.clone(exclude)
	table.insert(noTerrain, Workspace.Terrain)
	overlap.FilterDescendantsInstances = noTerrain
	for _, def in ipairs(Properties.List) do
		local ok, err = pcall(build, def, folder)
		if not ok then
			warn("[PropertyService] couldn't build " .. def.Id .. ": " .. tostring(err))
		end
	end
	-- Keep later floor raycasts (respawn spots are fixed now) from hitting characters.
	rayParams.FilterDescendantsInstances = { folder }

	Remotes.Event("RequestProperty").OnServerEvent:Connect(function(player, action, id)
		if not RateLimit.Allow(player, "PropRemote", 1, 3) then
			return
		end
		if action ~= "SetHome" or type(id) ~= "string" or not Properties.ById[id] then
			return
		end
		setHome(player, id)
	end)

	local function onPlayer(player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			spawnedAt[player] = os.clock()
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	DataService.OnLoaded(function(player)
		mirror(player)
		refreshAllSigns()
		-- The save often loads just after the first character spawned: still send them home.
		local char = player.Character
		if char and spawnedAt[player] and os.clock() - spawnedAt[player] < FRESH_SPAWN then
			sendHome(player, char)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		spawnedAt[player] = nil
		lastWarn[player] = nil
		task.delay(0.5, refreshAllSigns) -- once they're gone, their name comes off the signs
	end)

	task.spawn(function()
		local sinceRent = 0
		while true do
			task.wait(CHECK_EVERY)
			sinceRent += CHECK_EVERY
			local refreshRent = sinceRent >= RENT_REFRESH
			if refreshRent then
				sinceRent = 0
			end
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(function()
					homeCheck(player)
					if refreshRent and DataService.IsLoaded(player) then
						mirror(player)
					end
				end)
				if not ok then
					warn("[PropertyService] " .. tostring(err))
				end
			end
		end
	end)
end

return PropertyService
