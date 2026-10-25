-- PropertyService (ModuleScript, ServerScriptService.Services.PropertyService)
-- Houses players can buy (Config.Properties). Ownership is per player and never exclusive.
--   * At start-up HouseBuilder builds every house from parts (Workspace.Properties.<Id>): exterior,
--     furnished rooms, stairs, garage, driveway, yard, pool (Terrain water). The FOR SALE sign on the
--     driveway reads "FOR SALE $X" (and the rank needed); its bottom line names the owners who are in
--     the server (HouseClient shows owners "your place" instead).
--   * Doors: every outside door, garage door and gate is an owner-open part (HouseBuilder header): the
--     server keeps it shut, HouseClient opens it on the screens of owners who are civilians with no
--     heat (character physics is client-owned, so only they walk or drive in). Nothing inside pays
--     out unless the server checks ownership, so a wall-glitcher gains nothing.
--   * Prompts (in person only; the server re-checks distance, side and money):
--       Buy (E)          at the sale sign: civilians, free-roam rank >= MinRank, EconomyService.Spend(Price)
--       Set as home (Q)  at the front door: an owned house becomes your home (the first one bought is automatic)
--       Collect rent (X) at the front door: Rent dollars an hour, up to Properties.RentCapHours, into Cash
--     They carry attributes PropId and PropAction ("Buy" | "SetHome" | "Collect") so a client can hide
--     the ones that don't apply to its player.
--   * Perks: civilians with a home spawn in its living room (on join and on every respawn; never
--     prisoners, cops or wanted players); standing on the garage's STASH pad of a house you own with
--     Heat 0 banks your bag like the hideout (EconomyService.BankCarried + the "Banked" event); rent.
--   * Garage: while an owner (civilian) is within DISPLAY_RANGE studs, up to Garage-bays of their land
--     cars stand in the bays (anchored copies: CarBuilder + their paint, no prompts or scripts), last
--     driven first, then the priciest. Each has a "Drive" prompt (attribute OwnerUserId; HouseClient
--     hides it from everyone else): the copy goes and VehicleService.Spawn puts the real car in that
--     bay with the owner at the wheel. One owner's cars at a time; they go when that owner leaves.
--   * No hiding at home while wanted: a wanted citizen on foot inside any house (its InsideZones) is
--     moved out to its sale sign. Drive (garage) needs Heat 0 too.
--   * ReplicatedStorage attribute "HomeSpots": JSON { [id] = { p = {x, z} first STASH pad, s = {x, z}
--     sale sign } } for the GPS (ObjectiveClient banks at the pad; the phone routes buyers to the sign).
--   * Remote RequestProperty("SetHome", id): the phone may only set an owned property as home.
--   * Remote PropertyEvent (server -> client): "Bought" { Id, Name, Price, Home }, "Rent" { Id, Amount },
--     "Home" { Id }.
-- Saved (created lazily): data.props = { owned = { [id] = true }, home = id or nil, rentAt = { [id] = os.time() } }.
-- Player attributes (phone HOMES app): OwnedProps (comma list of ids), HomeId, Rent_<id> (uncollected
-- dollars, refreshed every 30 s for owned properties).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Properties = require(ReplicatedStorage.Shared.Config.Properties)
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local GarageService = require(ServerScriptService.Services.GarageService)
local HouseBuilder = require(ServerScriptService.Services.HouseBuilder)
local Telemetry = require(ServerScriptService.Services.Telemetry)
local VehicleService = require(ServerScriptService.Services.VehicleService)
local CarBuilder = require(ServerStorage.Tools.CarBuilder)

local PropertyService = {}

local CHECK_EVERY = 0.5 -- home banking
local RENT_REFRESH = 30 -- Rent_<id> attributes
local DISPLAY_EVERY = 1 -- garage display upkeep
local DISPLAY_RANGE = 150 -- an owner this close (studs, flat) gets their cars in the garage
local BUILDS_PER_TICK = 2 -- display cars built per upkeep tick (spreads the work)
local LAUNCH_GRACE = 8 -- s: a bay just driven out of stays empty while the real car leaves it
local LIVE_NEAR = 80 -- the owner's spawned car this close to the house is "home" (not shown twice)
local FRESH_SPAWN = 8 -- a character this new (s) is still moved home when the save loads late
local WARN_EVERY = 6

local houses = {} -- [id] = HouseBuilder result + { def, displays = { [bay] = { model, id } }, owner, launched = {} }
local spawnedAt = {} -- [player] = os.clock() of their latest character
local lastWarn = {} -- [player] = os.clock() of the last "lose your heat" toast
local notify, banked, propertyEvent

local money = HouseBuilder.Money

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

-- Sign: the price always (ownership is never exclusive); the bottom line names owners who are here.
local function refreshSign(id)
	local h = houses[id]
	if not h then
		return
	end
	local names = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if PropertyService.Owns(pl, id) then
			table.insert(names, pl.DisplayName)
		end
	end
	local def = h.def
	local top = "FOR SALE  " .. money(def.Price) .. ((def.MinRank and def.MinRank > 1) and ("  ·  RANK " .. def.MinRank) or "")
	local bottom
	if #names == 0 then
		bottom = def.Features or ""
	elseif #names == 1 then
		bottom = "Home of " .. names[1]
	elseif #names == 2 then
		bottom = "Home of " .. names[1] .. " & " .. names[2]
	else
		bottom = "Home of " .. names[1] .. " & " .. (#names - 1) .. " more"
	end
	for _, label in ipairs(h.labels) do
		label.Text = top
	end
	for _, label in ipairs(h.owners) do
		label.Text = bottom
	end
end

local function refreshAllSigns()
	for id in pairs(houses) do
		refreshSign(id)
	end
end

local function rootOf(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root then
		return nil, nil
	end
	return root, hum
end

-- Is the player standing (or parked) within reach of `pos`? (Prompt triggers are client claims.)
local function near(player, pos)
	local root = rootOf(player)
	if not root then
		return false
	end
	local rel = root.Position - pos
	return Vector3.new(rel.X, 0, rel.Z).Magnitude <= Properties.DoorReach and math.abs(rel.Y) < 14
end

local function onPad(pad, pos)
	local rel = pad.CFrame:PointToObjectSpace(pos)
	return math.abs(rel.X) <= pad.Size.X / 2 + 1 and math.abs(rel.Z) <= pad.Size.Z / 2 + 1 and rel.Y > -3 and rel.Y < 12
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
	local h = houses[id]
	if not h or not RateLimit.Allow(player, "PropBuy", 1, 2) or not near(player, h.sign.Position) then
		return
	end
	local def = h.def
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
	local h = houses[id]
	if h and RateLimit.Allow(player, "PropHome", 1, 2) and near(player, h.door.Position) then
		setHome(player, id)
	end
end

local function onCollect(player, id)
	local h = houses[id]
	if not h or not RateLimit.Allow(player, "PropRent", 1, 2) or not near(player, h.door.Position) then
		return
	end
	local p = props(player)
	if not p or not p.owned[id] then
		notify:FireClient(player, "PropNotOwned")
		return
	end
	local t = os.time()
	local due = Properties.RentDue(h.def, p.rentAt[id], t)
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

-- Prompts ---------------------------------------------------------------------------------------------

-- A ProximityPrompt on an attachment at `offset` (in `part`'s space).
local function prompt(part, offset, id, action, text, object, key, pad, hold)
	local att = Instance.new("Attachment")
	att.Name = action .. "Point"
	att.Position = offset
	att.Parent = part
	local pp = Instance.new("ProximityPrompt")
	pp.Name = action .. "Prompt"
	pp.ActionText = text
	pp.ObjectText = object
	pp.HoldDuration = hold or 0
	pp.MaxActivationDistance = 10
	pp.RequiresLineOfSight = false
	pp.KeyboardKeyCode = key
	pp.GamepadKeyCode = pad
	if id then
		pp:SetAttribute("PropId", id)
		pp:SetAttribute("PropAction", action)
	end
	pp.Parent = att
	return pp
end

local function addPrompts(h)
	local def = h.def
	local name = def.Name
	-- Buy at the sign (its -Z face looks at the street), rent and home on the door's outside face.
	prompt(h.sign, Vector3.new(0, -2.6, -0.6), def.Id, "Buy", "Buy " .. money(def.Price), name, Enum.KeyCode.E, Enum.KeyCode.ButtonX, 1)
		.Triggered:Connect(function(player)
			onBuy(player, def.Id)
		end)
	local out = -(h.blocker.Size.Z / 2 + 0.4)
	prompt(h.blocker, Vector3.new(0, -1.2, out), def.Id, "SetHome", "Set as home", name, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
		.Triggered:Connect(function(player)
			onSetHomePrompt(player, def.Id)
		end)
	prompt(h.blocker, Vector3.new(0, 1.2, out), def.Id, "Collect", "Collect rent", name, Enum.KeyCode.X, Enum.KeyCode.ButtonR1)
		.Triggered:Connect(function(player)
			onCollect(player, def.Id)
		end)
end

-- Garage displays ---------------------------------------------------------------------------------------

local bayParams = OverlapParams.new()
bayParams.FilterType = Enum.RaycastFilterType.Include
local standParams = OverlapParams.new()
standParams.FilterType = Enum.RaycastFilterType.Include
standParams.RespectCanCollide = true

local function clearDisplay(h, bay)
	local d = h.displays[bay]
	h.displays[bay] = nil
	if d and d.model then
		d.model:Destroy()
	end
end

local function clearDisplays(h)
	for bay in pairs(h.displays) do
		clearDisplay(h, bay)
	end
	h.owner = nil
end

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- May this player's cars stand in this garage right now?
local function eligible(player, h)
	if player.Parent ~= Players or player:GetAttribute("Side") ~= "Civilian" or not PropertyService.Owns(player, h.def.Id) then
		return false
	end
	local root = rootOf(player)
	return root ~= nil and flatDistance(root.Position, h.center) <= DISPLAY_RANGE
end

-- The owner's land cars, the last one driven first, then the priciest.
local function showroom(player)
	local last = player:GetAttribute("LastCar")
	local list = {}
	for _, v in ipairs(Vehicles.List) do
		if not v.Boat and not v.Police and GarageService.Owns(player, v.Id) then
			table.insert(list, { id = v.Id, key = (v.Id == last) and math.huge or (v.Price or 0) })
		end
	end
	table.sort(list, function(a, b)
		if a.key ~= b.key then
			return a.key > b.key
		end
		return a.id < b.id
	end)
	local ids = {}
	for i, e in ipairs(list) do
		ids[i] = e.id
	end
	return ids
end

-- Is a real car (anyone's) standing in this bay?
local function bayTaken(h, bay)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not vehicles then
		return false
	end
	bayParams.FilterDescendantsInstances = { vehicles }
	return #Workspace:GetPartBoundsInBox(h.bays[bay] * CFrame.new(0, 3, 0), Vector3.new(7, 5, 13), bayParams) > 0
end

local function displayTemplate(id)
	local templates = ServerStorage:FindFirstChild("VehicleTemplates")
	local t = templates and templates:FindFirstChild(id)
	if t then
		return t:Clone()
	end
	return CarBuilder.Build(id)
end

local onDrive -- defined below (the Drive prompt calls it)

local function buildDisplay(h, bay, player, id)
	local model = displayTemplate(id)
	pcall(GarageService.ApplyCustom, model, player)
	model.Name = "Display_" .. id
	-- A showpiece, not a car: no systems may treat it as one, nothing to sit in or prompt.
	model:SetAttribute("NCVehicle", nil)
	model:SetAttribute("OwnerUserId", nil)
	model:SetAttribute("DisplayCar", true)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") or d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		elseif d:IsA("VehicleSeat") or d:IsA("Seat") then
			d.Disabled = true
		end
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	local bayCf = h.bays[bay]
	model:PivotTo(bayCf * CFrame.new(0, 3.2, 0))
	-- Rest it on its wheels (mesh bodies move the wheels, so measure them).
	local low
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 5) == "Wheel" then
			local bottom = d.Position.Y - d.Size.Y / 2
			low = low and math.min(low, bottom) or bottom
		end
	end
	if not low then
		local cf, size = model:GetBoundingBox()
		low = cf.Position.Y - size.Y / 2
	end
	model:PivotTo(model:GetPivot() + Vector3.new(0, bayCf.Position.Y + 0.05 - low, 0))
	local chassis = model.PrimaryPart
	if chassis then
		local def = Vehicles.ById[id]
		local pp = prompt(chassis, Vector3.new(-(chassis.Size.X / 2 + 0.5), 0.5, 0), nil, "Drive", "Drive",
			def and def.DisplayName or id, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
		pp.MaxActivationDistance = 12
		pp:SetAttribute("OwnerUserId", player.UserId)
		pp:SetAttribute("DisplayCar", id)
		pp.Triggered:Connect(function(who)
			onDrive(who, h, bay)
		end)
	end
	model.Parent = h.displayFolder
	h.displays[bay] = { model = model, id = id }
end

-- A spot beside the bay where nothing solid stands (the driver gets out of the car's way there).
local function standSpot(h, bay)
	h.stand = h.stand or {}
	if h.stand[bay] ~= nil then
		return h.stand[bay] or nil
	end
	standParams.FilterDescendantsInstances = { h.model }
	local cf = h.bays[bay]
	for _, off in ipairs({ { -6.1, 0 }, { 6.1, 0 }, { -6.1, 5 }, { 6.1, 5 }, { -6.1, -5 }, { 6.1, -5 }, { 0, 10.6 }, { 0, -10.6 } }) do
		local c = cf * CFrame.new(off[1], 3.2, off[2])
		local blocked = false
		for _, p in ipairs(Workspace:GetPartBoundsInBox(c, Vector3.new(2.2, 4.6, 2.2), standParams)) do
			if not p:IsDescendantOf(h.displayFolder) then
				blocked = true
				break
			end
		end
		if not blocked then
			h.stand[bay] = c
			return c
		end
	end
	h.stand[bay] = false
	return nil
end

onDrive = function(player, h, bay)
	local d = h.displays[bay]
	if not d or h.owner ~= player or not RateLimit.Allow(player, "HouseDrive", 1, 2) then
		return
	end
	local root, hum = rootOf(player)
	if not root or hum.SeatPart or player:GetAttribute("Side") ~= "Civilian" then
		return
	end
	local bayCf = h.bays[bay]
	if (root.Position - bayCf.Position).Magnitude > 22 then
		return
	end
	if (player:GetAttribute("StunnedUntil") or 0) > Workspace:GetServerTimeNow() then
		return
	end
	if (player:GetAttribute("Heat") or 0) > 0 then -- even unseen: a garage is no hiding place
		notify:FireClient(player, "NoCarWhileWanted")
		return
	end
	local id = d.id
	if not GarageService.Owns(player, id) or not VehicleService.CanDrive("Civilian", id) then
		return
	end
	clearDisplay(h, bay)
	h.launched[bay] = os.clock()
	-- VehicleService won't spawn a car on top of a person: step the driver out of the bay first.
	local rel = bayCf:PointToObjectSpace(root.Position)
	if math.abs(rel.X) < 5.6 and math.abs(rel.Z) < 9.6 then
		local spot = standSpot(h, bay)
		if spot then
			player.Character:PivotTo(CFrame.lookAt(spot.Position, spot.Position + bayCf.LookVector))
		end
	end
	local ok, car, why = pcall(VehicleService.Spawn, player, id, { At = bayCf * CFrame.new(0, 3.2, 0), IgnoreCooldown = true, Sit = true })
	if not ok then
		warn("[PropertyService] garage spawn: " .. tostring(car))
		car = nil
	end
	if not car then
		h.launched[bay] = nil
		notify:FireClient(player, why == "cooldown" and "CarCooldown" or "CarNoRoom")
	end
end

local function updateDisplays(h)
	local owner = h.owner
	if owner and not eligible(owner, h) then
		owner = nil
	end
	if not owner then
		local best
		for _, pl in ipairs(Players:GetPlayers()) do
			if eligible(pl, h) then
				local root = rootOf(pl)
				local dist = flatDistance(root.Position, h.center)
				if not best or dist < best then
					best, owner = dist, pl
				end
			end
		end
	end
	if owner ~= h.owner then
		clearDisplays(h)
		h.owner = owner
	end
	if not owner then
		return
	end
	-- What to show: their cars, minus the one that is out and parked at the house already.
	local live = VehicleService.GetCar(owner)
	local liveId = live and live.PrimaryPart and flatDistance(live.PrimaryPart.Position, h.center) < LIVE_NEAR
		and live:GetAttribute("VehicleId") or nil
	local want, wanted = {}, {}
	for _, id in ipairs(showroom(owner)) do
		if id ~= liveId and #want < #h.bays then
			table.insert(want, id)
			wanted[id] = true
		end
	end
	local shown = {}
	local now = os.clock()
	for bay, d in pairs(h.displays) do
		if not wanted[d.id] or shown[d.id] or bayTaken(h, bay) then
			clearDisplay(h, bay)
		else
			shown[d.id] = true
		end
	end
	local built = 0
	for _, id in ipairs(want) do
		if not shown[id] and built < BUILDS_PER_TICK then
			for bay = 1, #h.bays do
				local launched = h.launched[bay]
				if not h.displays[bay] and not (launched and now - launched < LAUNCH_GRACE) and not bayTaken(h, bay) then
					buildDisplay(h, bay, owner, id)
					built += 1
					break
				end
			end
		end
	end
end

-- Perks ----------------------------------------------------------------------------------------------

-- Civilians (not wanted) spawn in their home's living room.
local function canGoHome(player, char)
	if player.Parent ~= Players or player.Character ~= char or char.Parent == nil then
		return nil
	end
	if player:GetAttribute("Side") ~= "Civilian" or (player:GetAttribute("Heat") or 0) > 0 then
		return nil -- never cops, prisoners or wanted players
	end
	local p = props(player)
	local h = p and p.home and houses[p.home]
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not h or not hum or hum.Health <= 0 or hum.SeatPart then
		return nil
	end
	return h
end

local function sendHome(player, char)
	local h = canGoHome(player, char)
	if not h then
		return
	end
	-- Load the house on their device first, so they never land on floors that aren't there yet.
	pcall(function()
		player:RequestStreamAroundAsync(h.spawn.Position, 2)
	end)
	if canGoHome(player, char) == h then
		char:PivotTo(h.spawn)
	end
end

local function onCharacter(player, char)
	spawnedAt[player] = os.clock()
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if not root then
		return
	end
	task.wait(0.15) -- after the default spawn placement
	if player.Character == char and player.Parent == Players then
		sendHome(player, char)
	end
end

local function inZone(zone, pos)
	local rel = zone.CFrame:PointToObjectSpace(pos)
	local half = zone.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
end

-- Nobody hides from the police in a house: a wanted citizen on foot inside one is walked out to its
-- sale sign, past the doors (the doors stay open for anyone inside, so nobody is ever shut in).
local function wantedSweep(player)
	if player:GetAttribute("Side") ~= "Civilian" or (player:GetAttribute("Heat") or 0) <= 0 then
		return
	end
	local root, hum = rootOf(player)
	if not root or hum.SeatPart then
		return
	end
	for _, h in pairs(houses) do
		if (root.Position - h.center).Magnitude < 160 then
			for _, zone in ipairs(h.zones or {}) do
				if inZone(zone, root.Position) then
					local front = HouseBuilder.LotCFrame(h.def).LookVector
					local spot = h.sign.Position + front * 5
					spot = Vector3.new(spot.X, h.center.Y + 3.5, spot.Z)
					player.Character:PivotTo(CFrame.lookAt(spot, spot + front))
					notify:FireClient(player, "PropNoHiding")
					return
				end
			end
		end
	end
end

-- Bank the bag on the garage pad of any house you own, as long as you have no heat at all.
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
		local h = houses[id]
		local here = false
		for _, pad in ipairs(h and h.pads or {}) do
			here = here or onPad(pad, root.Position)
		end
		if here then
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
	for _, def in ipairs(Properties.List) do
		local ok, res = pcall(HouseBuilder.Build, def, folder)
		if ok then
			local h = res
			h.def = def
			h.displays = {}
			h.launched = {}
			h.displayFolder = Instance.new("Folder")
			h.displayFolder.Name = "Displays"
			h.displayFolder.Parent = h.model
			houses[def.Id] = h
			local okPrompts, err = pcall(addPrompts, h)
			if not okPrompts then
				warn("[PropertyService] prompts for " .. def.Id .. ": " .. tostring(err))
			end
			refreshSign(def.Id)
		else
			warn("[PropertyService] couldn't build " .. def.Id .. ": " .. tostring(res))
		end
	end
	local spots = {}
	for id, h in pairs(houses) do
		local pad = h.pads[1] or h.pad
		spots[id] = {
			p = { math.floor(pad.Position.X), math.floor(pad.Position.Z) },
			s = { math.floor(h.sign.Position.X), math.floor(h.sign.Position.Z) },
		}
	end
	ReplicatedStorage:SetAttribute("HomeSpots", HttpService:JSONEncode(spots))

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
		for _, h in pairs(houses) do
			if h.owner == player then
				clearDisplays(h)
			end
		end
		task.delay(0.5, refreshAllSigns) -- once they're gone, their name comes off the signs
	end)

	task.spawn(function()
		local sinceRent, sinceDisplay = 0, 0
		while true do
			task.wait(CHECK_EVERY)
			sinceRent += CHECK_EVERY
			sinceDisplay += CHECK_EVERY
			local refreshRent = sinceRent >= RENT_REFRESH
			if refreshRent then
				sinceRent = 0
			end
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(function()
					homeCheck(player)
					wantedSweep(player)
					if refreshRent and DataService.IsLoaded(player) then
						mirror(player)
					end
				end)
				if not ok then
					warn("[PropertyService] " .. tostring(err))
				end
			end
			if sinceDisplay >= DISPLAY_EVERY then
				sinceDisplay = 0
				for _, h in pairs(houses) do
					if #h.bays > 0 then
						local ok, err = pcall(updateDisplays, h)
						if not ok then
							warn("[PropertyService] garage " .. h.def.Id .. ": " .. tostring(err))
						end
					end
				end
			end
		end
	end)
end

return PropertyService
