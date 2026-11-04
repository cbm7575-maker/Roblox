-- RideService (ModuleScript, ServerScriptService.Services.RideService)
-- Riding with someone who isn't your crewmate or Roblox friend. Those two hop in at once
-- (CrewService.MayRide); anyone else gets in through a card the other player answers. There are two ways:
--   * HOP IN at a stranger's passenger door (InteractClient's button, F, or the car's bubble).
--     VehicleService's tryRide checks every other riding rule (on foot, same side, not a prisoner, the seat
--     free, within reach, no wall between) and then calls RideService.Ask(rider, owner, car). The owner
--     gets a "let them in?" card (Kind "Ask") if they sit at the wheel of that car or stand within
--     OWNER_NEAR studs of it; otherwise the rider hears that the owner isn't near their car.
--   * INVITE from the driver's seat (RideClient's tile, key I): remote "RideInvite" ("Invite", userId).
--     The owner sits at the wheel of their own car with the passenger seat free. The invited player is on
--     foot within INVITE_REACH studs of the car, on the same side, not a prisoner, and can't hop in already.
--     They get a "hop in?" card (Kind "Invite").
--   * A YES ("RideInvite" "Answer", fromUserId, true) puts the rider on the owner's "RideIds" attribute
--     (",id,id,"; CrewService.MayRide and every device's VehicleVisuals read it) for the rest of the
--     session: from then on that rider hops in at once, like a friend. They're also sat in the passenger
--     seat right away if they're within ACCEPT_REACH studs with no wall between (VehicleService.TryRide);
--     otherwise they walk to the door and press HOP IN.
--   * A NO, no answer within EXPIRE seconds, or either player leaving closes the card and tells the asker.
--     The same ask (the same two players, the same way round) is then refused for COOLDOWN seconds.
--   One card may wait on a player at a time, and each player may have one ask out at a time.
-- Remote "RideInvite", server -> client:
--   "Card" { Kind = "Ask" | "Invite", FromUserId, FromName, Expires }   show the card
--   "Gone" { FromUserId }                                                close it (lapsed, or the asker left)
--   "Toast" { Key, Name }                                                RideClient says it in words (see there)
-- Client -> server: ("Invite", userId), ("Answer", fromUserId, yes).
-- Leaving the server drops every card, ask and "let in" involving that player.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local RateLimit = require(ReplicatedStorage.Shared.Util.RateLimit)

local RideService = {}

local EXPIRE = 15 -- seconds a card waits for an answer
local COOLDOWN = 60 -- seconds before the same player may ask the same player again after a no / no answer
local OWNER_NEAR = 60 -- studs: a stranger may ask an owner who stands this close to their car (or drives it)
local INVITE_REACH = 45 -- studs from the car to the player invited (RideClient shows INVITE within 35)
local ACCEPT_REACH = 45 -- studs from the passenger seat: within this, a yes sits the rider down at once

local S = {
	cards = {}, -- [target] = { from = player, kind = "Ask" | "Invite", car = Model, serial = n }
	outgoing = {}, -- [asker] = the player their card waits on
	refused = setmetatable({}, { __mode = "k" }), -- [asker] = { [userId] = os.clock() of the no / lapse }
	allowed = {}, -- [owner] = { [userId] = true }: who the owner has let in this session
	serial = 0,
}

local event -- the "RideInvite" remote

local function toast(p, key, name)
	if p and p.Parent == Players then
		event:FireClient(p, "Toast", { Key = key, Name = name })
	end
end

-- Toasts a player can trigger over and over (pressing HOP IN again): at most one every 2 s.
local function toastSoft(p, key, name)
	if RateLimit.Allow(p, "RideToast", 0.5, 1) then
		toast(p, key, name)
	end
end

local function aliveRoot(p)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and root and hum.Health > 0 then
		return root, hum
	end
	return nil
end

local function vehicles()
	return Workspace:FindFirstChild("Vehicles")
end

-- The passenger seat of `car` when it's free for a player (no one in it, no taxi fare), else nil.
local function freeSeat(car)
	local seat = car:FindFirstChild("PassengerSeat")
	if seat and seat:IsA("Seat") and seat.Occupant == nil and seat:GetAttribute("NPCRider") ~= true then
		return seat
	end
	return nil
end

-- The car `owner` sits at the wheel of, if it's their own; else nil.
local function drivingOwnCar(owner)
	local _, hum = aliveRoot(owner)
	local seat = hum and hum.SeatPart
	local car = seat and seat.Name == "DriverSeat" and seat.Parent
	if car and car:IsA("Model") and car.Parent == vehicles() and car:GetAttribute("OwnerUserId") == owner.UserId then
		return car
	end
	return nil
end

-- Is the owner with their car: at its wheel, or standing within OWNER_NEAR studs of it?
local function ownerNear(owner, car)
	if drivingOwnCar(owner) == car then
		return true
	end
	local root = aliveRoot(owner)
	local chassis = car.PrimaryPart
	return root ~= nil and chassis ~= nil and (root.Position - chassis.Position).Magnitude <= OWNER_NEAR
end

local function mayRide(rider, owner)
	local okCrew, crew = pcall(require, script.Parent:FindFirstChild("CrewService"))
	return okCrew and type(crew) == "table" and type(crew.MayRide) == "function" and crew.MayRide(rider, owner) == true
end

-- Did `target` say no to `asker` (or not answer) less than COOLDOWN seconds ago?
local function coolingDown(asker, target)
	local t = S.refused[asker] and S.refused[asker][target.UserId]
	return t ~= nil and os.clock() - t < COOLDOWN
end

local function publish(owner)
	local ids = {}
	for id in pairs(S.allowed[owner] or {}) do
		table.insert(ids, tostring(id))
	end
	table.sort(ids)
	if owner.Parent == Players then
		owner:SetAttribute("RideIds", #ids > 0 and ("," .. table.concat(ids, ",") .. ",") or nil)
	end
end

local function allow(owner, rider)
	S.allowed[owner] = S.allowed[owner] or {}
	S.allowed[owner][rider.UserId] = true
	publish(owner)
end

-- Close the card waiting on `target`. why: "No" | "Expired" (the asker is told and has to wait
-- COOLDOWN before asking again), "Off" (the target left: the asker is told), "Gone" (the asker left).
local function close(target, why)
	local c = S.cards[target]
	if not c then
		return
	end
	S.cards[target] = nil
	if S.outgoing[c.from] == target then
		S.outgoing[c.from] = nil
	end
	if target.Parent == Players then
		event:FireClient(target, "Gone", { FromUserId = c.from.UserId })
	end
	if why == "No" or why == "Expired" then
		S.refused[c.from] = S.refused[c.from] or {}
		S.refused[c.from][target.UserId] = os.clock()
		toast(c.from, why == "No" and "Declined" or "Expired", target.DisplayName)
	elseif why == "Off" then
		toast(c.from, "Off", target.DisplayName)
	end
end

-- Can a card go from `asker` to `target` now? Says why not to the asker when it can't.
local function canSend(asker, target)
	local waiting = S.outgoing[asker]
	if waiting then
		toastSoft(asker, "Pending", waiting.DisplayName)
		return false
	end
	if coolingDown(asker, target) then
		toastSoft(asker, "Cooldown", target.DisplayName)
		return false
	end
	if S.cards[target] then
		toastSoft(asker, "Busy", target.DisplayName)
		return false
	end
	return true
end

local function send(target, from, kind, car)
	S.serial += 1
	local serial = S.serial
	S.cards[target] = { from = from, kind = kind, car = car, serial = serial }
	S.outgoing[from] = target
	event:FireClient(target, "Card", { Kind = kind, FromUserId = from.UserId, FromName = from.DisplayName, Expires = EXPIRE })
	toast(from, kind == "Ask" and "AskSent" or "InviteSent", target.DisplayName)
	task.delay(EXPIRE, function()
		local c = S.cards[target]
		if c and c.serial == serial then
			close(target, "Expired")
		end
	end)
end

-- (see the header) A stranger at the door of `owner`'s car asks to hop in. VehicleService.tryRide has
-- checked every other riding rule already.
function RideService.Ask(rider, owner, car)
	if not event or not RateLimit.Allow(rider, "RideAsk", 1, 2) then
		return
	end
	if rider == owner or owner.Parent ~= Players or typeof(car) ~= "Instance" or car.Parent ~= vehicles() then
		return
	end
	if not ownerNear(owner, car) then
		toastSoft(rider, "Away", owner.DisplayName)
		return
	end
	if S.outgoing[rider] == owner then
		toastSoft(rider, "Pending", owner.DisplayName)
		return
	end
	if canSend(rider, owner) then
		send(owner, rider, "Ask", car)
	end
end

-- INVITE: `owner`, at the wheel of their own car, offers player `userId` the passenger seat.
local function invite(owner, userId)
	if typeof(userId) ~= "number" or not RateLimit.Allow(owner, "RideInvite", 1, 2) then
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	local car = drivingOwnCar(owner)
	if not target or target == owner or not car or not car.PrimaryPart or not freeSeat(car) then
		return
	end
	local side = owner:GetAttribute("Side")
	local root, hum = aliveRoot(target)
	if not root or hum.SeatPart or side == "Prisoner" or target:GetAttribute("Side") ~= side
		or (root.Position - car.PrimaryPart.Position).Magnitude > INVITE_REACH then
		return
	end
	if mayRide(target, owner) then
		return -- (they can hop in already: their HOP IN button is up)
	end
	if canSend(owner, target) then
		send(target, owner, "Invite", car)
	end
end

-- A card's answer. `target` is the one the card waited on.
local function answer(target, fromUserId, yes)
	local c = S.cards[target]
	if not c or c.from.UserId ~= fromUserId then
		return
	end
	if yes ~= true then
		close(target, "No")
		return
	end
	S.cards[target] = nil
	if S.outgoing[c.from] == target then
		S.outgoing[c.from] = nil
	end
	local owner, rider = c.from, target
	if c.kind == "Ask" then
		owner, rider = target, c.from
	end
	if owner.Parent ~= Players or rider.Parent ~= Players then
		return
	end
	allow(owner, rider)
	local car = c.car
	if not (car and car.Parent == vehicles() and car:GetAttribute("OwnerUserId") == owner.UserId) then
		car = drivingOwnCar(owner) -- (the owner has swapped cars since: their new one)
	end
	local seated = false
	if car and freeSeat(car) then
		local okVehicles, VehicleService = pcall(require, script.Parent:FindFirstChild("VehicleService"))
		if okVehicles and type(VehicleService) == "table" and type(VehicleService.TryRide) == "function" then
			seated = VehicleService.TryRide(rider, car, ACCEPT_REACH) == true
		end
	end
	if seated then
		toast(owner, "RiderSeated", rider.DisplayName)
		if c.kind == "Ask" then
			toast(rider, "LetInSeated", owner.DisplayName)
		end
	else
		toast(owner, "RiderComing", rider.DisplayName)
		toast(rider, c.kind == "Ask" and "LetIn" or "WalkOver", owner.DisplayName)
	end
end

local function onLeave(p)
	close(p, "Off")
	for target, c in pairs(S.cards) do
		if c.from == p then
			close(target, "Gone")
		end
	end
	S.outgoing[p] = nil
	S.allowed[p] = nil
	for owner, set in pairs(S.allowed) do
		if set[p.UserId] then
			set[p.UserId] = nil
			publish(owner)
		end
	end
end

function RideService.Init()
	event = Remotes.Event("RideInvite")
	event.OnServerEvent:Connect(function(player, action, a, b)
		if action == "Invite" then
			invite(player, a)
		elseif action == "Answer" and typeof(a) == "number" then
			if RateLimit.Allow(player, "RideAnswer", 2, 3) then
				answer(player, a, b == true)
			end
		end
	end)
	Players.PlayerRemoving:Connect(onLeave)
end

return RideService
