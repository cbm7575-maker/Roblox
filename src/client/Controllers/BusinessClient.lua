-- BusinessClient (ModuleScript, StarterPlayerScripts.Controllers.BusinessClient)
-- The client side of Empire, player businesses (Config.Businesses; BusinessService on the server decides
-- everything and checks every request again). Does nothing at all while ReplicatedStorage attribute
-- BusinessesOn isn't true (the launch switch: see Config.Businesses.Live).
--
-- THE CARDS (ScreenGui "Business", DisplayOrder 9, the flat "street" look of HouseClient's buy card; frame
-- "Card"). Opened by the server's BusinessCard (the door prompt). On a PC: top-left under Roblox's top bar,
-- Roblox's chat window hidden while it's open; on a phone: centred, Theme.Touch-tall buttons, CLOSE / CANCEL
-- on the left (the thumb side). Walking off the lot (the server's Reach) or sitting down closes it. Keys: X / gamepad B
-- close it, Enter / gamepad Y press its first button (never while seated or from behind Roblox's menu).
--   * BUY card (not yours): the name and price, the job in one line with its pay, the register (trickle a
--     minute and its size), the blurb, the level-5 picture in words; BUY (NEED $X MORE / EMPIRE n NEEDED) and
--     CANCEL.
--   * MANAGE card (yours): the name and LEVEL n, five level pips, the trickle (+25% while a crewmate is here),
--     the register filling live with its bar, what the next level adds and costs; COLLECT $X | START JOB,
--     UPGRADE $X | CLOSE. START JOB turns the buttons into the business's jobs (Config Jobs: WASH A CAR |
--     DELIVER A CAR at the Car Wash), BACK | CLOSE; with only one job (Palm Grind's RUSH ORDERS) it starts it.
--   * CREW card (a crewmate owns it): "<Owner>'s Suds & Shine", their level, what working here pays both of
--     you; its jobs (WASH A CAR | DELIVER A CAR, or RUSH ORDERS), BUY YOUR OWN | CLOSE.
--   The card counts as a panel: BusinessClient.IsOpen() (CombatClient lowers the gun, InteractClient offers
--   no E / F behind it). The wash mini-game counts too while a car is in the bay.
--
-- THE WASH BAY (BusinessJob "Wash"): the customer car exists only on this device (a ReplicatedStorage
-- TrafficModels body in a random paint, or a greybox car, in Workspace "BizLocal"): it rolls into the bay
-- the server picked, with 4-6 mud spots on it. SPRAY: hold the HOLD button (Theme's Action zone; F on a
-- keyboard, RT on a gamepad) until it fills, soapy water from the bay's nozzle, foam on the car. SCRUB: tap
-- each spot's round SCRUB button (BillboardGuis in PlayerGui, over the car) ScrubTaps times. RINSE: hold
-- again; the foam goes and the car sparkles. Every step goes to the server (RequestBusiness "Step"); its
-- "WashStep" answer puts the game back where the server is when a step didn't count (a hold let go early).
-- Paid ("WashPaid"): a toast with the pay and tip, and the AFTER panel: NEXT CAR | DELIVER | END.
-- DETAIL DELIVERY ("Detail"): the GPS routes to the customer's address, a gold ring and beam mark it, the
-- strip counts down the tip; "Dent" toasts; "DetailPaid" stamps DELIVERED and says to call your car (CAR).
-- RUSH ORDERS (Palm Grind, M2; BusinessJob "Rush" / "RushStep" / "RushLeg" / "RushPaid"): at the counter, the
-- HOLD button shows within K.GRAB_RANGE of the RUSH ORDERS shelf (on foot): hold it (F / RT / mouse / finger)
-- for Config.Rush.GrabHold to grab an order (RequestBusiness "Step" GrabOn / GrabOff; the server times it and
-- answers "RushStep" Again when it didn't count). Each address ("RushLeg"): the ring and beam, the GPS, and the
-- strip's "DELIVER TO <NAME> (1/3)" with the clock counting down on the right (the tip it would pay now on a
-- PC: Businesses.RushTip, the server's own maths; LATE once it runs out). "RushPaid": a toast per address and
-- an ORDER DELIVERED stamp after the last; then the GPS back to the café ("BACK TO PALM GRIND...").
-- The job's line (frame "Strip", Theme's Banner zone: a gold tag and what to do, the distance or the tip on
-- the right) and END JOB (a tile in the side column under the Buttons zone, LawClient.SideSlot) show for the
-- whole job. "Ended" says why and the shift's total.
--
-- COLD BREW (BusinessResult "ColdBrew"): a toast with what it does; another when it wears off (player
-- attribute ColdBrewUntil, server time; LocomotionClient reads the same attribute for the stamina).
--
-- PER-DEVICE LEVEL PROPS: every part tagged "BizProp" (attributes BizId, MinLevel, MaxLevel) is shown only
-- while the level this device shows for that business is within MinLevel..MaxLevel; else it's made fully
-- see-through and its gui, lights, decals and textures are switched off on this device only (nothing
-- replicates). The level shown: your own if you own it; else your crewmate's (the highest crewmate owner in
-- the server, from ReplicatedStorage "BizOwners"); else the featured owner's; else 1. The owner plate under
-- the roof sign says "★ YOUR SUDS & SHINE ★", "<Crewmate>'s Suds & Shine", "<Featured>'s Suds & Shine" or
-- FOR SALE · $25,000. Door prompts read Manage / Work here / View / Buy $X; the shine prompt only shows while
-- you drive your own car (not a boat); a customer car's "Drive" prompt only to its driver.
--
-- SHINE SPARKLE: cars (Workspace.Vehicles) within K.SHINE_RANGE of the camera whose owner's ShineUntil is in
-- the future get a sparkle emitter on their chassis and glossier paint, on this device (at most K.SHINE_MAX).
--
-- BREAK-INS: BusinessResult "BreakIn" (yours or a crewmate's): a toast, a GPS route to the business, the
-- strip's red BREAK-IN line with the time left (when no other job line is up), the map icon flashing red
-- (player attribute BizAlarm). A gun pointed at a robber (CombatClient.Aiming, within K.SCARE_REACH and
-- K.SCARE_CONE, once a second) asks the server to scare it off; punches and shots go through CombatService
-- as usual. Robbers' poses (model attribute Pose) play here with PoseClient, like HeistClient's clerks.
--
-- TOASTS AND STAMPS (BusinessResult): bought (a stamp), upgraded (LEVEL n, what it adds), collected, register
-- full, a customer ("Player2 got a shine at your Car Wash +$70", "...a cold brew at your Coffee Shop +$42"),
-- shined, cold brew, crew cut, break-in, stopped, lost, EMPIRE RANK n (a stamp, with what it unlocks), and
-- every refusal in words (K.MSG).
--
-- API (PhoneUI's EMPIRE app, MinimapClient, MapClient, CombatClient, InteractClient):
--   BusinessClient.On() -> the feature runs in this server
--   BusinessClient.IsOpen() -> a card, the wash mini-game, or the rush orders' GRAB hold at the shelf is up
--   BusinessClient.Owned() -> { { Id, Name, Short, Level, Register (live), Cap, Rate, Busy, Next, Lifetime,
--     JobsDone, Pos } } in config order
--   BusinessClient.ForSale() -> { { Id, Name, Price, Unlock, Locked, Pos, JobLine, Trickle } } (Enabled, not yours)
--   BusinessClient.ComingSoon() -> { { Id, Name, Price, Unlock, JobLine, Kind } } (not Enabled yet)
--   BusinessClient.Empire() -> { Rank, XP, Share, Into, Need, Next (the next unlock's words), Title, RemoteCollect }
--   BusinessClient.RouteTo(id) -> GPS to its door; BusinessClient.Collect(id) -> remote collect (Empire 5+)
--   BusinessClient.MapBlips() -> { { Id, Name, Pos, Letter, Color, Owned, Alarm } } (Enabled businesses)
-- Studio: the phone layout follows PreviewTouch like every HUD piece; BizTestCrew (Workspace attribute) makes
-- every other player count as a crewmate here too.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Businesses = require(ReplicatedStorage.Shared.Config.Businesses)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local RobloxMenu = require(ReplicatedStorage.Shared.Util.RobloxMenu)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))
local GPSClient = require(script.Parent:WaitForChild("GPSClient"))

local player = Players.LocalPlayer

local BusinessClient = {}

local C = Theme.Color
local money = HUDController.Money
local WASH = Businesses.Wash
local E = Businesses.Empire

-- Every number and word this file uses (balance lives in Config.Businesses).
local K = {
	DISPLAY_ORDER = 9, -- as HouseClient's card
	CARD_PAD = 18,
	CARD_W = 392, -- PC; a phone: 46% of the width, 300-380
	SCARE_REACH = 22, -- studs: a gun this close on a robber asks the server (it allows Config's ScareReach)
	SCARE_CONE = 0.94, -- cosine from the crosshair's line
	SCARE_GAP = 1, -- seconds between two asks
	SHINE_RANGE = 160, -- studs from the camera a shiny car sparkles
	SHINE_MAX = 8,
	HOLD_EXTRA = 0.15, -- seconds a hold is kept past the server's hold time before letting go (lag)
	SCRUB_GAP = WASH.ScrubGap + 0.04, -- this device counts a tap no sooner than the server does
	RING = 64, -- the drop ring's size (studs across): Config.Detail.StopRadius x 2 (and Config.Rush's)
	GRAB_RANGE = 7, -- studs (flat) from the RUSH ORDERS shelf the GRAB hold shows (the server allows Config.Rush.GrabRange)
	BREW = Color3.fromRGB(196, 128, 70), -- the GRAB hold's fill: coffee
	PAINTS = {
		Color3.fromRGB(196, 54, 54), Color3.fromRGB(230, 230, 236), Color3.fromRGB(28, 30, 36), Color3.fromRGB(40, 92, 160),
		Color3.fromRGB(150, 156, 164), Color3.fromRGB(240, 196, 44), Color3.fromRGB(64, 120, 80), Color3.fromRGB(120, 60, 150),
	},
	MUD = Color3.fromRGB(96, 72, 48),
	FOAM = Color3.fromRGB(245, 248, 255),
	SPRAY = Color3.fromRGB(150, 210, 255),
	RINSE = Color3.fromRGB(220, 240, 255),
	SPARKLE = "rbxasset://textures/particles/sparkles_main.dds",
	-- BusinessResult "No" reasons, in words.
	MSG = {
		TooFar = "Get closer to the business first.",
		Owned = "You already own this business.",
		Locked = "Reach a higher Empire rank to buy this one.",
		Empty = "The register is empty.",
		MaxLevel = "Fully upgraded already!",
		NotYours = "Only its owners and their crew can work here.",
		BaysBusy = "Every bay is busy right now. Try again in a moment, or deliver a car.",
		JobElsewhere = "You're working at another business. END JOB first.",
		OnDelivery = "Finish the delivery first (or END JOB).",
		OnRush = "You're on rush orders. Finish them first (or END JOB).",
		PickupBlocked = "Something's on the PICK-UP box. Clear it and try again.",
		NoAddress = "No customer is home right now. Try again in a moment.",
		NoCar = "No customer car is ready. Try again in a moment.",
		RemoteRank = "Collecting from the phone unlocks at Empire rank " .. E.RemoteCollect .. ".",
		ShineOwnCar = "Drive your own car under the gantry for a shine.",
		ShineStop = "Stop under the gantry first.",
		ShineAlready = "Your car is still sparkling!",
		ColdBrewOnFoot = "Walk up to the counter to order.",
		ColdBrewAlready = "You've still got a cold brew going!",
	},
	-- BusinessJob "Ended" reasons, in words (nil: nothing more to say).
	ENDED = {
		Player = "Job over.",
		Wanted = "Job over: you're wanted. Lose the cops first.",
		Side = "Job over.",
		Died = "Job over.",
		OwnerLeft = "Job over: the owner left the server.",
		LeftBay = "Job over: you walked away from the bay.",
		LeftCar = "Job over: you left the customer's car.",
		CarGone = "Job over: the customer's car is gone.",
		Invalid = "Job over.",
		LeftOwnCar = "Job over: you left your car with the order.",
		NoCarYet = "Job over: get in your own car after you grab an order (tap CAR to call it).",
		Idle = "Job over: no order picked up for a while.",
		Busy = "Job over.",
	},
}

local ui = {} -- the screen pieces (build): gui, card and its parts, strip, hold, after, endJob; marker, beam
local S = {
	on = false,
	state = nil, -- the last BusinessState
	owners = {}, -- ReplicatedStorage "BizOwners", decoded
	card = nil, -- { id, mode = "Buy" | "Manage" | "Crew", sub = "main" | "job", owner, ownerName, level }
	actions = {}, -- [button index] = what it does now
	chatHidden = false,
	wash = nil, -- the wash mini-game (see Wash below)
	job = nil, -- { kind = "Wash" | "Detail" | "Rush", id, ... } (Rush: see Rush below)
	brewUntil = nil, -- server time your cold brew wears off (for the "wore off" toast)
	alarm = {}, -- [id] = { untilT (server time), ownerName, mine }
	props = setmetatable({}, { __mode = "k" }), -- [part] = its look before we hid it
	hidden = setmetatable({}, { __mode = "k" }), -- [part] = true while hidden here
	shine = {}, -- [car] = { emitter, paint = { [part] = reflectance } }
	lazy = {},
	lastScare = 0,
	gpsName = nil :: string?, -- the GPS target we set (cleared only if it's still ours)
	robberPoses = setmetatable({}, { __mode = "k" }), -- [model] = { name, handle }
}

local Card, Job, Wash, Fx, Rush = {}, {}, {}, {}, {} -- the pieces of this file, as tables (keeps the top level small)

------------------------------------------------------------------ small helpers

local function other(name)
	local m = S.lazy[name]
	if m == nil then
		local module = script.Parent:FindFirstChild(name)
		local ok, res = false, nil
		if module then
			ok, res = pcall(require, module)
		end
		m = (ok and type(res) == "table") and res or false
		S.lazy[name] = m
	end
	return m or nil
end

local function sound(name)
	task.spawn(function()
		local s = other("SoundClient")
		if s and type(s.Play) == "function" then
			pcall(s.Play, name)
		end
	end)
end

local function request(...)
	Remotes.Event("RequestBusiness"):FireServer(...)
end

local function serverNow()
	return Workspace:GetServerTimeNow()
end

local function myRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function myHum()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function defOf(id)
	return Businesses.ById[id or ""]
end

-- Another player in your crew (or, in Studio with BizTestCrew, anyone else).
local function isCrewmate(p)
	if not p or p == player then
		return false
	end
	if RunService:IsStudio() and Workspace:GetAttribute("BizTestCrew") == true then
		return true
	end
	local crew = player:GetAttribute("Crew")
	return crew ~= nil and crew == p:GetAttribute("Crew")
end

local function inputMode()
	local name = UserInputService:GetLastInputType().Name
	if string.sub(name, 1, 7) == "Gamepad" then
		return "gamepad"
	elseif name == "Touch" or Theme.IsTouch() then
		return "touch"
	end
	return "keyboard"
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function rich(s)
	return (string.gsub(string.gsub(tostring(s), "&", "&amp;"), "<", "&lt;"))
end

------------------------------------------------------------------ state

-- Your entry for a business (the last BusinessState), or nil.
local function mine(id)
	local list = S.state and S.state.List
	return type(list) == "table" and list[id] or nil
end

-- The register now: the last number plus what has trickled in since (the server's own maths, x its scale).
local function liveRegister(id)
	local e = mine(id)
	if not e then
		return 0
	end
	local since = math.max(0, serverNow() - (tonumber(S.state.At) or serverNow())) * (tonumber(S.state.Scale) or 1)
	return math.min(tonumber(e.Cap) or 0, (tonumber(e.Register) or 0) + (tonumber(e.Rate) or 0) / 60 * since)
end

local function empireXP()
	return tonumber(player:GetAttribute("EmpireXP")) or (S.state and tonumber(S.state.XP)) or 0
end

local function empireRank()
	return Businesses.RankFor(empireXP())
end

-- The level this device shows for a business, and whose it is ("mine" | "crew" | "featured" | nil), with a name.
local function shownOwner(id)
	local e = mine(id)
	if e then
		return Businesses.ClampLevel(e.Level), "mine", player.DisplayName
	end
	local info = S.owners[id]
	if type(info) == "table" then
		local best, bestName
		for uid, lvl in pairs(type(info.o) == "table" and info.o or {}) do
			local p = Players:GetPlayerByUserId(tonumber(uid) or 0)
			if p and isCrewmate(p) and (not best or (tonumber(lvl) or 1) > best) then
				best, bestName = tonumber(lvl) or 1, p.DisplayName
			end
		end
		if best then
			return Businesses.ClampLevel(best), "crew", bestName
		end
		if info.f and info.l then
			return Businesses.ClampLevel(info.l), "featured", tostring(info.n or "")
		end
	end
	return 1, nil, nil
end

------------------------------------------------------------------ level props, plates and prompts (per device)

-- Show or hide one level prop on this device only.
-- Shown, it takes its own look back from the part's BizT attribute (BusinessService stamps it when it builds the
-- prop); hidden, it's fully see-through. Always set from that, never from a remembered copy: the Nov 4 Studio test
-- found every prop stuck see-through after a level change (a remembered "own look" of 1 had gone stale).
function Fx.setProp(part, show)
	local base = part:GetAttribute("BizT")
	if type(base) ~= "number" then
		local rec = S.props[part]
		if not rec then
			rec = { t = part.Transparency < 1 and part.Transparency or 0, kids = {} }
			S.props[part] = rec
		end
		base = rec.t
	end
	S.hidden[part] = (not show) or nil
	local want = show and base or 1
	if part.Transparency ~= want then
		part.Transparency = want
	end
	local night = Workspace:GetAttribute("IsNight") == true
	local glow = CollectionService:HasTag(part, "NightNeon") or CollectionService:HasTag(part, "NightLamp")
	for _, d in ipairs(part:GetChildren()) do
		if d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			d.Enabled = show
		elseif d:IsA("Light") then
			d.Enabled = show and (not glow or night)
		elseif d:IsA("ParticleEmitter") or d:IsA("Beam") then
			d.Enabled = show
		elseif d:IsA("Decal") or d:IsA("Texture") then
			local t = d:GetAttribute("BizT")
			d.Transparency = show and (type(t) == "number" and t or 0) or 1
		end
	end
end

function Fx.propWanted(part)
	local id = part:GetAttribute("BizId")
	local minL = tonumber(part:GetAttribute("MinLevel")) or 1
	local maxL = tonumber(part:GetAttribute("MaxLevel")) or Businesses.MaxLevel
	local level = shownOwner(id)
	return level >= minL and level <= maxL
end

function Fx.applyProps()
	for _, part in ipairs(CollectionService:GetTagged("BizProp")) do
		if part:IsA("BasePart") then
			Fx.setProp(part, Fx.propWanted(part))
		end
	end
end

-- The owner plate, the door prompt and the shine prompt's words for one building (when it is streamed in).
function Fx.dressSite(model)
	local def = defOf(model:GetAttribute("BusinessId"))
	if not def then
		return
	end
	local _, whose, name = shownOwner(def.Id)
	local plate = model:FindFirstChild("OwnerPlate", true)
	local gui = plate and plate:FindFirstChild("SignGui")
	local title = gui and gui:FindFirstChild("Title")
	if title then
		local text, color
		if whose == "mine" then
			text, color = "★ YOUR " .. string.upper(def.Brand or def.Name) .. " ★", Color3.fromRGB(110, 242, 196)
		elseif whose == "crew" or whose == "featured" then
			text, color = tostring(name) .. "'s " .. (def.Brand or def.Name), whose == "crew" and C.Purple or C.Gold
		else
			text, color = "FOR SALE · " .. money(def.Price), C.Gold
		end
		if title.Text ~= text then
			title.Text = text
		end
		title.TextColor3 = color
	end
	local door = model:FindFirstChild("BusinessDoor", true)
	if door and door:IsA("ProximityPrompt") then
		local words = (whose == "mine" and "Manage") or (whose == "crew" and "Work here") or ("View / Buy " .. money(def.Price))
		if door.ActionText ~= words then
			door.ActionText = words
		end
	end
end

function Fx.dressAll()
	local shops = Workspace:FindFirstChild("Shops")
	for _, m in ipairs(shops and shops:GetChildren() or {}) do
		if m:IsA("Model") and m:GetAttribute("BusinessId") then
			Fx.dressSite(m)
		end
	end
	Fx.applyProps()
end

-- Four times a second: the shine prompt (only while driving your own car) and customer cars' Drive prompt.
function Fx.prompts()
	local hum = myHum()
	local seat = hum and hum.SeatPart
	local car = seat and seat.Name == "DriverSeat" and seat.Parent
	local driving = car ~= nil and car:GetAttribute("OwnerUserId") == player.UserId and car:GetAttribute("Boat") ~= true
	local shops = Workspace:FindFirstChild("Shops")
	for _, m in ipairs(shops and shops:GetChildren() or {}) do
		local p = m:GetAttribute("BusinessId") and m:FindFirstChild("BizShinePrompt", true)
		if p and p:IsA("ProximityPrompt") and p.Enabled ~= driving then
			p.Enabled = driving
		end
	end
	local vehicles = Workspace:FindFirstChild("Vehicles")
	for _, v in ipairs(vehicles and vehicles:GetChildren() or {}) do
		if v:GetAttribute("BizCar") == true then
			local s = v:FindFirstChild("DriverSeat")
			local p = s and s:FindFirstChild("BizDrivePrompt")
			if p and p:IsA("ProximityPrompt") then
				local show = v:GetAttribute("BizDriverUserId") == player.UserId and s.Occupant == nil and not (hum and hum.SeatPart)
				if p.Enabled ~= show then
					p.Enabled = show
				end
			end
		end
	end
end

------------------------------------------------------------------ shine sparkle (every device)

function Fx.unshine(car)
	local rec = S.shine[car]
	S.shine[car] = nil
	if not rec then
		return
	end
	if rec.emitter then
		rec.emitter:Destroy()
	end
	for part, refl in pairs(rec.paint) do
		if part.Parent then
			part.Reflectance = refl
		end
	end
end

function Fx.shineTick()
	local cam = Workspace.CurrentCamera
	local at = cam and cam.CFrame.Position or Vector3.zero
	local now = serverNow()
	local keep = {}
	local count = 0
	local vehicles = Workspace:FindFirstChild("Vehicles")
	for _, car in ipairs(vehicles and vehicles:GetChildren() or {}) do
		local chassis = car:IsA("Model") and car.PrimaryPart
		local owner = chassis and Players:GetPlayerByUserId(car:GetAttribute("OwnerUserId") or 0)
		local untilT = owner and owner:GetAttribute("ShineUntil")
		if chassis and type(untilT) == "number" and untilT > now and car:GetAttribute("Boat") ~= true
			and (chassis.Position - at).Magnitude <= K.SHINE_RANGE and count < K.SHINE_MAX then
			count += 1
			keep[car] = true
			if not S.shine[car] then
				local e = Instance.new("ParticleEmitter")
				e.Name = "BizShine"
				e.Texture = K.SPARKLE
				e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 230, 255))
				e.LightEmission = 1
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 0) })
				e.Lifetime = NumberRange.new(0.5, 0.9)
				e.Rate = 7
				e.Speed = NumberRange.new(0.5, 1.5)
				e.SpreadAngle = Vector2.new(180, 180)
				e.Shape = Enum.ParticleEmitterShape.Box
				e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
				e.Parent = chassis
				local paint = {}
				for _, d in ipairs(car:GetDescendants()) do
					if d:IsA("BasePart") and d:GetAttribute("BodyPaint") then
						paint[d] = d.Reflectance
						d.Reflectance = math.min(0.6, d.Reflectance + 0.25)
					end
				end
				S.shine[car] = { emitter = e, paint = paint }
			end
		end
	end
	for car in pairs(S.shine) do
		if not keep[car] then
			Fx.unshine(car)
		end
	end
end

------------------------------------------------------------------ the cards

local function label(parent, name, size, kind)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = ""
	Theme.Text(l, size, kind)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

function Card.build()
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Active = true
	Theme.Panel(card, 0.18)
	card.Visible = false
	card.Parent = ui.gui
	ui.card = card
	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(K.CARD_PAD, 0)
	accent.Size = UDim2.fromOffset(40, 2)
	accent.BackgroundColor3 = C.Brand
	accent.BorderSizePixel = 0
	accent.Parent = card
	ui.title = label(card, "Title", nil, "Display")
	ui.title.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MinTextSize = 15
	fit.MaxTextSize = 22
	fit.Parent = ui.title
	ui.right = label(card, "Right", 20, "Display")
	ui.right.TextXAlignment = Enum.TextXAlignment.Right
	ui.pips = Instance.new("Frame")
	ui.pips.Name = "Pips"
	ui.pips.BackgroundTransparency = 1
	ui.pips.Parent = card
	ui.pipList = {}
	for i = 1, Businesses.MaxLevel do
		local p = Instance.new("Frame")
		p.Name = "Pip" .. i
		p.BorderSizePixel = 0
		p.Size = UDim2.new(1 / Businesses.MaxLevel, -4, 1, 0)
		p.Position = UDim2.new((i - 1) / Businesses.MaxLevel, 0, 0, 0)
		Theme.Corners(p, 2)
		p.Parent = ui.pips
		ui.pipList[i] = p
	end
	ui.line1 = label(card, "Info", 14, "Body")
	ui.line1.TextColor3 = C.Dim
	ui.line1.RichText = true
	ui.line1.TextWrapped = true
	ui.line1.TextYAlignment = Enum.TextYAlignment.Top
	ui.reg = label(card, "Register", 15, "Display")
	ui.reg.RichText = true
	ui.bar, ui.fill = Theme.Bar(card, C.Cash)
	ui.blurb = label(card, "Blurb", 14, "Body")
	ui.blurb.TextWrapped = true
	ui.blurb.TextYAlignment = Enum.TextYAlignment.Top
	ui.rule = Instance.new("Frame")
	ui.rule.Name = "Rule"
	ui.rule.BackgroundColor3 = C.Text
	ui.rule.BackgroundTransparency = 0.8
	ui.rule.BorderSizePixel = 0
	ui.rule.Parent = card
	ui.note = label(card, "Note", 13, "Body")
	ui.note.TextWrapped = true
	ui.note.TextYAlignment = Enum.TextYAlignment.Top
	ui.buttons = {}
	for i = 1, 4 do
		local b = Instance.new("TextButton")
		b.Name = "Button" .. i
		b.Text = ""
		Theme.Button(b, "Quiet")
		b.FontFace = Theme.Font.Display
		b.TextScaled = true
		local bfit = Instance.new("UITextSizeConstraint")
		bfit.MinTextSize = 12
		bfit.MaxTextSize = 17
		bfit.Parent = b
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
		pad.Parent = b
		b.Parent = card
		b.Activated:Connect(function()
			local fn = S.actions[i]
			if fn then
				sound("Click")
				fn()
			end
		end)
		ui.buttons[i] = b
	end
end

-- A card button: its words, look and what it does (nil = hidden).
function Card.button(i, text, kind, fn, dim)
	local b = ui.buttons[i]
	b.Visible = text ~= nil
	S.actions[i] = text and fn or nil
	if not text then
		return
	end
	b.Text = text
	Theme.Button(b, kind or "Quiet")
	b.FontFace = Theme.Font.Display
	if dim then
		b.AutoButtonColor = false
		b.TextColor3 = C.Dim
	end
end

function Card.close()
	S.card = nil
	if ui.card then
		ui.card.Visible = false
	end
	if S.chatHidden then
		S.chatHidden = false
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat, true)
	end
end

-- Lay the card out for what's showing (see the header for where it sits).
function Card.layout()
	local touch = Theme.IsTouch()
	local pad = K.CARD_PAD
	local w = K.CARD_W
	if touch then
		local vp = Workspace.CurrentCamera.ViewportSize
		w = math.clamp(math.floor(vp.X * 0.46), 300, 380)
	end
	local inner = w - pad * 2
	local btnH = touch and Theme.Touch or 40
	local y = 14
	ui.title.Position = UDim2.fromOffset(pad, y)
	ui.title.Size = UDim2.fromOffset(inner - 124, 30)
	ui.right.Position = UDim2.fromOffset(pad + inner - 120, y + 1)
	ui.right.Size = UDim2.fromOffset(120, 28)
	y += 36
	if ui.pips.Visible then
		ui.pips.Position = UDim2.fromOffset(pad, y)
		ui.pips.Size = UDim2.fromOffset(inner, 5)
		y += 12
	end
	ui.line1.Position = UDim2.fromOffset(pad, y)
	ui.line1.Size = UDim2.fromOffset(inner, 36)
	y += 40
	if ui.reg.Visible then
		ui.reg.Position = UDim2.fromOffset(pad, y)
		ui.reg.Size = UDim2.fromOffset(inner, 20)
		y += 24
		ui.bar.Position = UDim2.fromOffset(pad, y)
		ui.bar.Size = UDim2.fromOffset(inner, 6)
		y += 14
	end
	ui.bar.Visible = ui.reg.Visible
	if ui.blurb.Visible then
		ui.blurb.Position = UDim2.fromOffset(pad, y)
		ui.blurb.Size = UDim2.fromOffset(inner, 52)
		y += 56
	end
	ui.rule.Position = UDim2.fromOffset(pad, y)
	ui.rule.Size = UDim2.fromOffset(inner, 1)
	y += 9
	ui.note.Position = UDim2.fromOffset(pad, y)
	ui.note.Size = UDim2.fromOffset(inner, 34)
	y += 40
	-- Buttons: two to a row. On a phone the right-hand button of each row goes left (CLOSE under the thumb).
	local half = math.floor((inner - 8) / 2)
	local shown = {}
	for i = 1, 4 do
		if ui.buttons[i].Visible then
			table.insert(shown, i)
		end
	end
	local row = 0
	for n = 1, #shown, 2 do
		local a, b = shown[n], shown[n + 1]
		local ry = y + row * (btnH + 8)
		local leftI, rightI = a, b
		if touch and b then
			leftI, rightI = b, a
		end
		if b then
			ui.buttons[leftI].Position = UDim2.fromOffset(pad, ry)
			ui.buttons[leftI].Size = UDim2.fromOffset(half, btnH)
			ui.buttons[rightI].Position = UDim2.fromOffset(pad + half + 8, ry)
			ui.buttons[rightI].Size = UDim2.fromOffset(inner - half - 8, btnH)
		else
			ui.buttons[a].Position = UDim2.fromOffset(pad, ry)
			ui.buttons[a].Size = UDim2.fromOffset(inner, btnH)
		end
		row += 1
	end
	ui.card.Size = UDim2.fromOffset(w, y + row * (btnH + 8) - 8 + pad)
	-- In the middle of the screen on every device. (On a PC it used to sit top-left, right over the Coast Feed
	-- and the toast stack, whose words showed through it: found in the Nov 4 Studio test.)
	ui.card.AnchorPoint = Vector2.new(0.5, 0.5)
	ui.card.Position = UDim2.fromScale(0.5, touch and 0.5 or 0.47)
end

-- The live parts (four times a second): the register, its bar and the COLLECT button.
function Card.live()
	local c = S.card
	if not c or c.mode ~= "Manage" then
		return
	end
	local e = mine(c.id)
	if not e then
		return
	end
	local reg, cap = liveRegister(c.id), tonumber(e.Cap) or 1
	ui.reg.Text = string.format('REGISTER  <font color="#%s">%s</font>  <font color="#%s">/ %s</font>', C.Cash:ToHex(),
		money(reg), C.Dim:ToHex(), money(cap))
	ui.fill.Size = UDim2.fromScale(math.clamp(reg / math.max(cap, 1), 0.02, 1), 1)
	ui.fill.BackgroundColor3 = reg >= cap and C.Gold or C.Cash
	if c.sub == "main" then
		local amount = math.floor(reg)
		local text = amount > 0 and ("COLLECT " .. money(amount)) or "REGISTER EMPTY"
		if ui.buttons[1].Text ~= text then
			Card.button(1, text, amount > 0 and "Primary" or "Quiet", function()
				request("Collect", c.id)
			end, amount <= 0)
		end
	end
end

-- Buttons 1-2: the business's jobs (Config Jobs: the first one Primary). owner: the crewmate's UserId when
-- working for them (nil: your own).
function Card.jobButtons(def, owner)
	for i = 1, 2 do
		local j = def.Jobs and def.Jobs[i]
		if j then
			Card.button(i, j.Label, i == 1 and "Primary" or "Quiet", function()
				Card.close()
				request("Job", def.Id, j.Kind, owner)
			end)
		end
	end
end

-- Fill the card in for its mode (see the header).
function Card.fill()
	local c = S.card
	local def = c and defOf(c.id)
	if not def then
		Card.close()
		return
	end
	local cash = tonumber(player:GetAttribute("Cash")) or 0
	local rank = empireRank()
	ui.pips.Visible = c.mode ~= "Buy"
	ui.reg.Visible = c.mode == "Manage"
	ui.blurb.Visible = c.mode == "Buy"
	ui.right.TextColor3 = C.Gold
	for i = 1, 4 do
		Card.button(i, nil)
	end
	local level = 1
	if c.mode == "Buy" then
		local lv1 = def.Levels[1]
		ui.title.Text = def.Name
		ui.right.Text = money(def.Price)
		ui.right.TextColor3 = C.Cash
		ui.line1.Text = "<b>The job:</b> " .. rich(def.JobLine or "") .. " · " .. rich(def.JobPay or "")
		ui.blurb.Text = (def.Blurb or "") .. string.format("  Its register fills $%d a minute while you play (holds %s).", lv1.Trickle, money(lv1.Cap))
		local locked = not Businesses.Unlocked(def, rank)
		if locked then
			ui.note.Text = "Needs Empire rank " .. def.Unlock .. " (you're " .. rank .. "). Earn Empire XP running a business."
			ui.note.TextColor3 = C.Purple
		else
			ui.note.Text = "Level 5: " .. string.lower(string.sub(def.Levels[5].Adds or "", 1, 1)) .. string.sub(def.Levels[5].Adds or "", 2) .. "."
			ui.note.TextColor3 = C.Gold
		end
		local short = def.Price - cash
		if locked then
			Card.button(1, "EMPIRE " .. def.Unlock .. " NEEDED", "Quiet", function() end, true)
		elseif short > 0 then
			Card.button(1, "NEED " .. money(short) .. " MORE", "Quiet", function() end, true)
		else
			Card.button(1, "BUY " .. money(def.Price), "Primary", function()
				Card.close()
				request("Buy", def.Id)
			end)
		end
		Card.button(4, "CANCEL", "Quiet", Card.close)
	elseif c.mode == "Manage" then
		local e = mine(c.id) or {}
		level = Businesses.ClampLevel(e.Level)
		ui.title.Text = def.Name
		ui.right.Text = "LEVEL " .. level
		local rate = tonumber(e.Rate) or Businesses.Trickle(def, level, false)
		ui.line1.Text = string.format("Register +$%d a minute while you're online%s · %d jobs done", math.floor(rate + 0.5),
			e.Busy and ' <font color="#' .. C.Cash:ToHex() .. '">(+25% busy: crew here)</font>' or "", tonumber(e.JobsDone) or 0)
		local nextPrice = tonumber(e.Next) or Businesses.UpgradePrice(def, level)
		if nextPrice then
			local nxt = def.Levels[level + 1]
			ui.note.Text = string.format("Level %d: %s · +$%d/min, +%d%% job pay", level + 1, nxt.Adds or "",
				nxt.Trickle - def.Levels[level].Trickle, math.floor((nxt.JobMult - def.Levels[level].JobMult) * 100 + 0.5))
			ui.note.TextColor3 = C.Gold
		else
			ui.note.Text = "Fully grown: level " .. Businesses.MaxLevel .. ". ★"
			ui.note.TextColor3 = C.Dim
		end
		if c.sub == "job" then
			Card.jobButtons(def, nil)
			Card.button(3, "BACK", "Quiet", function()
				c.sub = "main"
				Card.fill()
			end)
		else
			ui.buttons[1].Text = "" -- (Card.live writes COLLECT)
			Card.button(1, "COLLECT", "Primary", function()
				request("Collect", def.Id)
			end)
			Card.button(2, "START JOB", "Quiet", function()
				local jobs = def.Jobs or {}
				if #jobs == 1 then
					Card.close() -- (one job: straight to it)
					request("Job", def.Id, jobs[1].Kind)
					return
				end
				c.sub = "job"
				Card.fill()
			end)
			if nextPrice and cash >= nextPrice then
				Card.button(3, "UPGRADE " .. money(nextPrice), "Quiet", function()
					request("Upgrade", def.Id)
				end)
			elseif nextPrice then
				Card.button(3, "NEED " .. money(nextPrice - cash) .. " MORE", "Quiet", function() end, true)
			else
				Card.button(3, "MAX LEVEL", "Quiet", function() end, true)
			end
		end
		Card.button(4, "CLOSE", "Quiet", Card.close)
	else -- Crew
		level = Businesses.ClampLevel(c.level)
		ui.title.Text = tostring(c.ownerName or "Your crewmate") .. "'s " .. (def.Brand or def.Name)
		ui.right.Text = "LEVEL " .. level
		ui.line1.Text = "Work here for your crewmate: you get your normal pay, and they get a "
			.. math.floor(Businesses.CrewCut * 100 + 0.5) .. "% cut on top."
		ui.note.Text = "Want your own? It's " .. money(def.Price) .. ", and the job pays you directly."
		ui.note.TextColor3 = C.Dim
		Card.jobButtons(def, c.owner)
		if not Businesses.Unlocked(def, rank) then
			Card.button(3, "EMPIRE " .. def.Unlock .. " NEEDED", "Quiet", function() end, true)
		elseif cash >= def.Price then
			Card.button(3, "BUY YOUR OWN", "Quiet", function()
				Card.close()
				request("Buy", def.Id)
			end)
		else
			Card.button(3, "NEED " .. money(def.Price - cash) .. " MORE", "Quiet", function() end, true)
		end
		Card.button(4, "CLOSE", "Quiet", Card.close)
	end
	for i = 1, Businesses.MaxLevel do
		ui.pipList[i].BackgroundColor3 = i <= level and C.Gold or C.Dim
		ui.pipList[i].BackgroundTransparency = i <= level and 0 or 0.7
	end
	Card.layout()
	Card.live()
end

function Card.open(info)
	local def = defOf(info.Id)
	if not def or player:GetAttribute("InHome") == true then
		return
	end
	S.card = { id = def.Id, mode = info.Mode, sub = "main", owner = info.Owner, ownerName = info.OwnerName, level = info.Level }
	Card.fill()
	ui.card.Visible = true
	if not Theme.IsTouch() and not S.chatHidden and StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat) then
		S.chatHidden = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat, false)
	end
	sound("Click")
end

------------------------------------------------------------------ the job HUD (strip, HOLD, after panel, END JOB, drop marker)

function Job.build()
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	Theme.Panel(strip, 0.25)
	strip.Visible = false
	strip.Parent = ui.gui
	ui.strip = strip
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.Size = UDim2.new(0, 3, 1, 0)
	edge.BackgroundColor3 = C.Gold
	edge.BorderSizePixel = 0
	edge.Parent = strip
	ui.stripEdge = edge
	ui.stripTitle = label(strip, "Title", 15, "Bold")
	ui.stripTitle.RichText = true
	ui.stripTitle.TextTruncate = Enum.TextTruncate.AtEnd
	ui.stripTitle.Position = UDim2.fromOffset(12, 0)
	ui.stripTitle.Size = UDim2.new(1, -110, 1, 0)
	ui.stripRight = label(strip, "Right", 16, "Display")
	ui.stripRight.TextXAlignment = Enum.TextXAlignment.Right
	ui.stripRight.AnchorPoint = Vector2.new(1, 0)
	ui.stripRight.Position = UDim2.new(1, -10, 0, 0)
	ui.stripRight.Size = UDim2.new(0, 96, 1, 0)

	-- HOLD: a big flat button in the Action zone that fills while held.
	local hold = Instance.new("TextButton")
	hold.Name = "Hold"
	hold.Text = ""
	hold.AutoButtonColor = false
	Theme.Button(hold, "Quiet")
	hold.BackgroundTransparency = 0.2
	hold.Visible = false
	hold.Parent = ui.gui
	ui.hold = hold
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = K.SPRAY
	fill.BackgroundTransparency = 0.35
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	Theme.Corners(fill)
	fill.Parent = hold
	ui.holdFill = fill
	ui.holdText = label(hold, "Words", 18, "Display")
	ui.holdText.Size = UDim2.fromScale(1, 1)
	ui.holdText.TextXAlignment = Enum.TextXAlignment.Center
	ui.holdText.ZIndex = 3
	ui.holdKey = Theme.Key(hold, "F")
	ui.holdKey.AnchorPoint = Vector2.new(0, 0.5)
	ui.holdKey.Position = UDim2.new(0, 10, 0.5, 0)
	ui.holdKey.ZIndex = 4
	-- Held with the mouse or a finger: let go anywhere ends it (UserInputService.InputEnded in start), so a
	-- finger that slides off the button still lets go.
	hold.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			Job.holdBegin(input)
		end
	end)

	-- AFTER a wash: the pay, and NEXT CAR | DELIVER | END.
	local after = Instance.new("Frame")
	after.Name = "After"
	Theme.Panel(after, 0.2)
	after.Visible = false
	after.Parent = ui.gui
	ui.after = after
	ui.afterTitle = label(after, "Title", 18, "Display")
	ui.afterTitle.TextXAlignment = Enum.TextXAlignment.Center
	ui.afterTitle.RichText = true
	ui.afterButtons = {}
	for i, spec in ipairs({ { "Next", "NEXT CAR", "Primary" }, { "Deliver", "DELIVER", "Quiet" }, { "End", "END", "Quiet" } }) do
		local b = Instance.new("TextButton")
		b.Name = spec[1]
		b.Text = spec[2]
		Theme.Button(b, spec[3])
		b.FontFace = Theme.Font.Display
		b.TextSize = 16
		b.Parent = after
		ui.afterButtons[i] = b
	end
	ui.afterButtons[1].Activated:Connect(function()
		sound("Click")
		local w = S.wash
		if w then
			ui.after.Visible = false
			request("Job", w.id, "Wash")
		end
	end)
	ui.afterButtons[2].Activated:Connect(function()
		sound("Click")
		local w = S.wash
		if w then
			ui.after.Visible = false
			request("Job", w.id, "Detail", w.owner)
		end
	end)
	ui.afterButtons[3].Activated:Connect(function()
		sound("Click")
		request("EndJob")
	end)

	-- END JOB: a tile in the side column (LawClient.SideSlot), like ActivityClient's END SHIFT.
	local endJob = Instance.new("TextButton")
	endJob.Name = "EndJob"
	endJob.Text = "END JOB"
	Theme.Button(endJob, "Quiet")
	endJob.FontFace = Theme.Font.Display
	endJob.TextSize = 13
	endJob.Visible = false
	Theme.Shadow(endJob)
	endJob.Parent = ui.gui
	ui.endJob = endJob
	endJob.Activated:Connect(function()
		sound("Click")
		request("EndJob")
	end)
end

-- Where the job pieces sit now (the zones, the side slot); a few times a second while a job is on.
function Job.place()
	local touch = Theme.IsTouch()
	Theme.Place(ui.strip, "Banner", touch)
	local z = Theme.Zone("Action", touch)
	ui.hold.AnchorPoint = z.Anchor
	ui.hold.Position = z.Pos
	ui.hold.Size = touch and UDim2.fromOffset(220, 64) or UDim2.fromOffset(280, 52)
	ui.holdKey.Visible = inputMode() ~= "touch"
	if ui.holdKey.Visible then
		ui.holdKey.Text = inputMode() == "gamepad" and "RT" or "F"
		ui.holdKey.Size = UDim2.fromOffset(math.max(22, 10 + #ui.holdKey.Text * 9), 22)
	end
	-- AFTER: centred above the Action zone.
	local w = touch and 340 or 420
	local btnH = touch and Theme.Touch or 40
	ui.after.AnchorPoint = Vector2.new(0.5, 1)
	if touch then
		-- Low and a little right of centre: clear of the thumbstick (lower left) and the Banner zone.
		ui.after.Position = UDim2.new(0.56, 0, 1, -20)
	else
		ui.after.Position = z.Pos
	end
	ui.after.Size = UDim2.fromOffset(w, 12 + 26 + 8 + btnH + 12)
	ui.afterTitle.Position = UDim2.fromOffset(12, 10)
	ui.afterTitle.Size = UDim2.new(1, -24, 0, 26)
	local third = math.floor((w - 24 - 16) / 3)
	for i, b in ipairs(ui.afterButtons) do
		b.Position = UDim2.fromOffset(12 + (i - 1) * (third + 8), 12 + 26 + 8)
		b.Size = UDim2.fromOffset(third, btnH)
	end
	if ui.endJob.Visible then
		local law = other("LawClient")
		local ok, pos, size = false, nil, nil
		if law and type(law.SideSlot) == "function" then
			local okSlots, index = pcall(law.PlaceSlots)
			ok, pos, size = pcall(law.SideSlot, ui.gui, okSlots and tonumber(index) or 0, touch)
		end
		if not ok or typeof(pos) ~= "Vector2" or typeof(size) ~= "Vector2" then
			local s = ui.gui.AbsoluteSize
			pos, size = Vector2.new(s.X - 72, s.Y * 0.5 + 66), Vector2.new(52, 52)
		end
		ui.endJob.Position = UDim2.fromOffset(pos.X, pos.Y)
		ui.endJob.Size = UDim2.fromOffset(size.X, size.Y)
	end
end

-- The drop's ring and beam (local parts under the camera).
function Job.marker(pos)
	if ui.ring then
		ui.ring:Destroy()
		ui.ring = nil
	end
	if ui.beam then
		ui.beam:Destroy()
		ui.beam = nil
	end
	if not pos then
		return
	end
	local function part(name, size, cf, transparency)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = C.Gold
		p.Size = size
		p.CFrame = cf
		p.Transparency = transparency
		p.Parent = Workspace.CurrentCamera
		return p
	end
	ui.ring = part("BizDropRing", Vector3.new(0.3, K.RING, K.RING), CFrame.new(pos.X, 0.35, pos.Z) * CFrame.Angles(0, 0, math.rad(90)), 0.6)
	ui.ring.Shape = Enum.PartType.Cylinder
	ui.beam = part("BizDropBeam", Vector3.new(1.4, 160, 1.4), CFrame.new(pos.X, 80, pos.Z), 0.72)
end

function Job.setGPS(name, pos)
	S.gpsName = name
	GPSClient.SetTarget(name, pos)
end

function Job.clearGPS()
	if S.gpsName and GPSClient.Target() == S.gpsName then
		GPSClient.Clear()
	end
	S.gpsName = nil
end

-- The strip's words (five times a second): the job's, else a break-in's.
function Job.strip()
	local touch = Theme.IsTouch()
	local job = S.job
	local title, right, edge = nil, "", C.Gold
	local tag
	if job and job.kind == "Wash" and S.wash then
		local w = S.wash
		tag = "CAR WASH"
		local left = 0
		for _, m in ipairs(w.mud or {}) do
			if m.taps < WASH.ScrubTaps then
				left += 1
			end
		end
		local words = ({
			arrive = "CAR PULLING IN...",
			spray = "HOLD TO SPRAY THE CAR",
			scrub = "SCRUB THE DIRTY SPOTS (" .. left .. " LEFT)",
			rinse = "HOLD TO RINSE IT OFF",
			wait = "SHINING...",
			paid = "NEXT CAR, DELIVER ONE, OR END",
		})[w.stage] or ""
		title = words
		right = (job.earned or 0) > 0 and money(job.earned) or ("BAY " .. tostring(w.bay))
		-- Out of reach of the bay: say where to go (and keep HOLD hidden until there; Job.strip runs every frame).
		if w.stage ~= "paid" and not w.holding then
			local near, d = Wash.near(w)
			if not near then
				title = "WALK TO BAY " .. tostring(w.bay) -- (the distance is on the right; a longer line was cut off)
				right = GPSClient.FormatDistance(d)
			end
			local holding = w.stage == "spray" or w.stage == "rinse"
			if ui.hold.Visible ~= (holding and near) then
				ui.hold.Visible = holding and near
			end
		end
	elseif job and job.kind == "Detail" and job.pos then
		tag = "DETAIL"
		title = "DELIVER THE " .. string.upper(tostring(job.car or "CAR")) .. " TO " .. string.upper(tostring(job.name or ""))
		local root = myRoot()
		local dist = root and GPSClient.FormatDistance(flat(root.Position - job.pos).Magnitude) or ""
		local left = job.est and math.max(0, math.floor(job.est - (os.clock() - job.since))) or 0
		right = left > 0 and ((touch and "" or "TIP ") .. left .. "s") or dist
	elseif job and job.kind == "Rush" then
		tag, title, right = Rush.line(touch)
	else
		local bestId, best
		for id, a in pairs(S.alarm) do
			if a.untilT > serverNow() and (not best or a.untilT < best.untilT) then
				bestId, best = id, a
			end
		end
		local busyElsewhere = player:GetAttribute("JobKind") ~= nil
		if best and not busyElsewhere then
			local def = defOf(bestId)
			tag = "BREAK-IN"
			edge = C.Danger
			title = "STOP THE ROBBERS AT " .. string.upper(def and (best.mine and "YOUR " or (tostring(best.ownerName) .. "'S ")) .. (def.Short or def.Name) or "THE BUSINESS")
			right = clock(best.untilT - serverNow())
		end
	end
	local on = title ~= nil and player:GetAttribute("TitleScreen") ~= true
	if on then
		local stampTop = HUDController.StampTop and HUDController.StampTop()
		if stampTop then
			local absY = ui.strip.AbsolutePosition.Y + ui.strip.AbsoluteSize.Y
			on = stampTop >= absY
		end
	end
	ui.strip.Visible = on
	if not on then
		return
	end
	ui.stripEdge.BackgroundColor3 = edge
	local hex = edge:ToHex()
	local text
	if touch then
		text = string.format('<font face="Oswald" weight="bold" size="15" color="#%s">%s</font>', hex, rich(title))
	else
		text = string.format('<font face="Oswald" weight="bold" size="16" color="#%s">%s</font>   %s', hex, tag, rich(title))
	end
	if ui.stripTitle.Text ~= text then
		ui.stripTitle.Text = text
	end
	if ui.stripRight.Text ~= right then
		ui.stripRight.Text = right
	end
	ui.stripRight.TextColor3 = (edge == C.Danger and C.Danger) or (job and job.kind == "Rush" and job.late and C.Orange) or C.Text
end

function Job.finish(info)
	local job = S.job
	S.job = nil
	Wash.clear(true)
	Job.marker(nil)
	Job.clearGPS()
	ui.endJob.Visible = false
	ui.hold.Visible = false
	ui.after.Visible = false
	local reason = type(info) == "table" and info.Reason or nil
	local words = K.ENDED[reason or ""]
	local jobs, earned = tonumber(info and info.Jobs) or 0, tonumber(info and info.Earned) or 0
	if reason == "Delivered" or reason == "Left" then
		return
	end
	if words or jobs > 0 then
		local summary = jobs > 0 and string.format(" %d job%s, %s.", jobs, jobs == 1 and "" or "s", money(earned)) or ""
		NotifyController.Show((words or "Job over.") .. summary, nil, (reason == "Wanted" and "police") or "info")
	end
	if job and job.kind == "Detail" then
		Job.marker(nil)
	end
end

------------------------------------------------------------------ the wash mini-game (this device only)

-- The customer car: a TrafficModels body (pivot at its bottom middle, front facing -Z) in a random paint, or a
-- greybox car. Every part anchored, never solid. Returns the model.
function Wash.buildCar(seed)
	local rng = Random.new(seed)
	local paint = K.PAINTS[rng:NextInteger(1, #K.PAINTS)]
	local templates = ReplicatedStorage:FindFirstChild("TrafficModels")
	local list = {}
	for _, t in ipairs(templates and templates:GetChildren() or {}) do
		if t:IsA("Model") then
			table.insert(list, t)
		end
	end
	local model
	if #list > 0 then
		model = list[rng:NextInteger(1, #list)]:Clone()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = true -- (until the mud is placed: see Wash.placeMud)
				if d:GetAttribute("BodyPaint") then
					d.Color = paint
					d.Reflectance = 0.05
				end
			elseif d:IsA("BaseScript") then
				d:Destroy()
			end
		end
	else
		model = Instance.new("Model")
		local function add(name, size, cf, color, material, shape)
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.CanCollide, p.CanTouch, p.CastShadow = false, false, true
			p.Size = size
			p.CFrame = cf
			p.Color = color
			p.Material = material or Enum.Material.SmoothPlastic
			if shape then
				p.Shape = shape
			end
			p.Parent = model
			if name == "Body" or name == "Roof" then
				p:SetAttribute("BodyPaint", true)
			end
			return p
		end
		local body = add("Body", Vector3.new(6.6, 1.8, 13), CFrame.new(0, 2, 0), paint)
		model.PrimaryPart = body
		add("Cabin", Vector3.new(5.6, 1.6, 6), CFrame.new(0, 3.7, 0.6), Color3.fromRGB(40, 50, 70), Enum.Material.Glass).Transparency = 0.3
		add("Roof", Vector3.new(5.5, 0.25, 5.8), CFrame.new(0, 4.6, 0.6), paint)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				add("Wheel", Vector3.new(1, 2.4, 2.4), CFrame.new(sx * 3, 1.2, sz * 4.2), Color3.fromRGB(28, 28, 32), nil, Enum.PartType.Cylinder)
			end
		end
		model.WorldPivot = CFrame.new()
	end
	model.Name = "BizCustomerCar"
	return model
end

function Wash.folder()
	local f = Workspace:FindFirstChild("BizLocal")
	if not f then
		f = Instance.new("Folder")
		f.Name = "BizLocal" -- (made on this device: nothing here replicates)
		f.Parent = Workspace
	end
	return f
end

-- The car's place in the bay (its pivot on the bay floor, nose into the bay) and where it pulls in from.
function Wash.spots(w)
	local def = defOf(w.id)
	local bay = def and Businesses.BayCFrame(def, w.bay)
	if not bay then
		return nil, nil
	end
	local inBay = bay * CFrame.new(0, 0.3, 0)
	local b = def.Layout.Bays[w.bay]
	local mouth = Businesses.Frame(def) * CFrame.new(b.X, 0.2, def.Layout.BayMouth) * CFrame.Angles(0, math.pi, 0)
	return inBay, mouth
end

-- Tween a model's pivot (a CFrameValue drives it: models can't be tweened directly).
function Wash.slide(model, from, to, seconds, fadeOut)
	local v = Instance.new("CFrameValue")
	v.Value = from
	model:PivotTo(from)
	v.Changed:Connect(function(cf)
		if model.Parent then
			model:PivotTo(cf)
		end
	end)
	local tween = TweenService:Create(v, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = to })
	tween:Play()
	tween.Completed:Connect(function()
		v:Destroy()
	end)
	if fadeOut then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				TweenService:Create(d, TweenInfo.new(seconds), { Transparency = 1 }):Play()
			end
		end
	end
	return tween
end

-- The mud: Spots discs on the body (side doors, hood, roof), each with its SCRUB button.
function Wash.placeMud(w)
	local car = w.car
	local cf, size = car:GetBoundingBox()
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local rng = Random.new(w.seed + 7)
	-- Candidate spots in the car's box space: a point outside the body and the way in toward it.
	local candidates = {
		{ Vector3.new(-hx - 2, -hy * 0.1, -hz * 0.25), Vector3.new(1, 0, 0) },
		{ Vector3.new(-hx - 2, -hy * 0.1, hz * 0.3), Vector3.new(1, 0, 0) },
		{ Vector3.new(hx + 2, -hy * 0.1, -hz * 0.25), Vector3.new(-1, 0, 0) },
		{ Vector3.new(hx + 2, -hy * 0.1, hz * 0.3), Vector3.new(-1, 0, 0) },
		{ Vector3.new(0, hy + 2, -hz * 0.62), Vector3.new(0, -1, 0) },
		{ Vector3.new(rng:NextNumber(-0.3, 0.3) * hx, hy + 2, hz * 0.1), Vector3.new(0, -1, 0) },
	}
	for i = #candidates, 2, -1 do
		local j = rng:NextInteger(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { car }
	w.mud = {}
	for n = 1, math.min(w.spots, #candidates) do
		local c = candidates[n]
		local from = cf:PointToWorldSpace(c[1])
		local dir = cf:VectorToWorldSpace(c[2]) * (math.max(size.X, size.Y) + 4)
		local hit = Workspace:Raycast(from, dir, params)
		local pos, normal
		if hit then
			pos, normal = hit.Position, hit.Normal
		else
			pos = cf:PointToWorldSpace(c[1] + c[2] * 2)
			normal = cf:VectorToWorldSpace(-c[2])
		end
		local disc = Instance.new("Part")
		disc.Name = "Mud"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = Vector3.new(0.12, 1.9, 1.9)
		disc.CFrame = CFrame.lookAt(pos + normal * 0.06, pos + normal * 2) * CFrame.Angles(0, math.rad(90), 0)
		disc.Color = K.MUD
		disc.Material = Enum.Material.Sand
		disc.Anchored = true
		disc.CanCollide, disc.CanQuery, disc.CanTouch, disc.CastShadow = false, false, false, false
		disc.Parent = car
		local m = { part = disc, taps = 0, normal = normal, pos = pos }
		w.mud[n] = m
		Wash.scrubButton(w, n, m)
	end
	for _, d in ipairs(car:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanQuery = false
		end
	end
end

-- One spot's round SCRUB button over the car (a BillboardGui in PlayerGui: guis only take taps there).
function Wash.scrubButton(w, n, m)
	local touch = Theme.IsTouch()
	local px = touch and 66 or 54
	local bb = Instance.new("BillboardGui")
	bb.Name = "BizScrub" .. n
	bb.Adornee = m.part
	bb.Size = UDim2.fromOffset(px, px)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 70
	bb.ResetOnSpawn = false
	bb.Active = true
	bb.Enabled = false
	bb.Parent = player:WaitForChild("PlayerGui")
	local b = Instance.new("TextButton")
	b.Name = "Scrub"
	b.Size = UDim2.fromScale(1, 1)
	b.BackgroundColor3 = Color3.fromRGB(120, 90, 60)
	b.BackgroundTransparency = 0.1
	b.AutoButtonColor = true
	b.FontFace = Theme.Font.Display
	b.TextColor3 = C.Text
	b.TextScaled = true
	b.Text = "SCRUB"
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = b
	local ring = Instance.new("UIStroke")
	ring.Color = C.Text
	ring.Thickness = 2
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0.14, 0), UDim.new(0.14, 0)
	pad.Parent = b
	b.Parent = bb
	b.Activated:Connect(function()
		Wash.scrub(n)
	end)
	m.gui, m.button = bb, b
end

-- Foam over the car after the spray (white blobs on the mud spots and the roof).
function Wash.foam(w, on)
	for _, f in ipairs(w.foam or {}) do
		f:Destroy()
	end
	w.foam = {}
	if not on or not w.car then
		return
	end
	local cf, size = w.car:GetBoundingBox()
	local spots = {}
	for _, m in ipairs(w.mud or {}) do
		table.insert(spots, { m.pos + m.normal * 0.3, 2.6 })
	end
	for _, z in ipairs({ -0.15, 0.2 }) do
		table.insert(spots, { cf:PointToWorldSpace(Vector3.new(0, size.Y / 2, size.Z * z)), 3.4 })
	end
	for _, s in ipairs(spots) do
		local p = Instance.new("Part")
		p.Name = "Foam"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(s[2], s[2], s[2])
		p.CFrame = CFrame.new(s[1])
		p.Color = K.FOAM
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = 0.2
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
		p.Parent = w.car
		table.insert(w.foam, p)
	end
end

-- Water from above the bay at the car while a hold is on (kind "spray" soapy blue, "rinse" clear).
function Wash.water(w, kind)
	if w.nozzle then
		w.nozzle:Destroy()
		w.nozzle = nil
	end
	if not kind or not w.car then
		return
	end
	local cf, size = w.car:GetBoundingBox()
	local a = Instance.new("Part")
	a.Name = "Nozzle"
	a.Size = Vector3.new(size.X, 0.2, size.Z * 0.8)
	a.CFrame = cf * CFrame.new(0, size.Y / 2 + 5, 0)
	a.Transparency = 1
	a.Anchored = true
	a.CanCollide, a.CanQuery, a.CanTouch = false, false, false
	a.Parent = Wash.folder()
	local e = Instance.new("ParticleEmitter")
	e.Texture = K.SPARKLE
	e.Color = ColorSequence.new(kind == "spray" and K.SPRAY or K.RINSE)
	e.LightEmission = 0.3
	e.Transparency = NumberSequence.new(0.25)
	e.Size = NumberSequence.new(kind == "spray" and 0.55 or 0.35)
	e.Squash = NumberSequence.new(-2)
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Speed = NumberRange.new(26, 34)
	e.Lifetime = NumberRange.new(0.2, 0.3)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Rate = 140
	e.Parent = a
	w.nozzle = a
	sound("Splash")
end

function Wash.sparkle(w)
	if not w.car then
		return
	end
	local _, size = w.car:GetBoundingBox()
	local core = w.car.PrimaryPart or w.car:FindFirstChildWhichIsA("BasePart", true)
	if not core then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Texture = K.SPARKLE
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = core
	e:Emit(math.floor(math.clamp(size.Magnitude * 2, 20, 60)))
	for _, d in ipairs(w.car:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("BodyPaint") then
			d.Reflectance = 0.3
		end
	end
end

-- Is the worker close enough to their bay for a hold or a tap to count (the server's BayRange)? (Found in the
-- Nov 4 Studio test: START JOB is pressed at the door, ~46 studs from bay 1, and nothing said where to go.)
function Wash.near(w)
	local def = defOf(w.id)
	local bay = def and Businesses.BayCFrame(def, w.bay)
	local root = myRoot()
	if not bay or not root then
		return true, 0 -- (can't tell: don't hide anything)
	end
	local d = flat(root.Position - bay.Position).Magnitude
	return d <= WASH.BayRange - 2, d
end

-- Show the stage's controls: HOLD for spray / rinse, the SCRUB buttons for the spots left.
function Wash.show()
	local w = S.wash
	if not w then
		Rush.show() -- (the HOLD button is the rush orders' GRAB, or nothing)
		return
	end
	local holding = w.stage == "spray" or w.stage == "rinse"
	ui.hold.Visible = holding and (w.holding ~= nil or (Wash.near(w)))
	if holding and not w.holding then
		ui.holdFill.Size = UDim2.fromScale(0, 1)
		ui.holdFill.BackgroundColor3 = w.stage == "spray" and K.SPRAY or K.RINSE
		ui.holdText.Text = w.stage == "spray" and "HOLD TO SPRAY" or "HOLD TO RINSE"
	end
	for _, m in ipairs(w.mud or {}) do
		if m.gui then
			m.gui.Enabled = w.stage == "scrub" and m.taps < WASH.ScrubTaps
		end
	end
	ui.after.Visible = w.stage == "paid"
end

-- pointer: the mouse or touch InputObject holding it (nil: a key).
function Wash.startHold(pointer)
	local w = S.wash
	if not w or w.holding or (w.stage ~= "spray" and w.stage ~= "rinse") or os.clock() < w.readyClock then
		return
	end
	w.holding = { at = os.clock(), kind = w.stage, pointer = pointer }
	request("Step", w.stage == "spray" and "SprayOn" or "RinseOn")
	Wash.water(w, w.stage)
end

-- Let go: early (the server will say "Again") or at the end of the hold (done = true).
function Wash.endHold(done)
	local w = S.wash
	local h = w and w.holding
	if not h then
		return
	end
	w.holding = nil
	Wash.water(w, nil)
	request("Step", h.kind == "spray" and "SprayOff" or "RinseOff")
	if done then
		-- On to the next stage at once (the server's WashStep puts it back if the hold didn't count).
		if h.kind == "spray" then
			w.stage = "scrub"
			Wash.foam(w, true)
		else
			w.stage = "wait"
		end
		sound("Success")
	else
		ui.holdFill.Size = UDim2.fromScale(0, 1)
		if not w.toldHold then
			w.toldHold = true
			NotifyController.Show("Hold it until the bar is full! (Letting go early loses the tip.)", nil, "info")
		end
	end
	Wash.show()
end

function Wash.scrub(n)
	local w = S.wash
	local m = w and w.mud and w.mud[n]
	if not m or w.stage ~= "scrub" or m.taps >= WASH.ScrubTaps or os.clock() - (w.lastTap or 0) < K.SCRUB_GAP then
		return
	end
	w.lastTap = os.clock()
	m.taps += 1
	request("Step", "Scrub", n)
	sound("Click")
	local left = WASH.ScrubTaps - m.taps
	m.part.Transparency = math.min(1, m.taps / WASH.ScrubTaps)
	if m.button then
		m.button.Text = left > 0 and ("SCRUB ×" .. left) or "✓"
	end
	-- A puff of suds where it was scrubbed.
	local e = Instance.new("ParticleEmitter")
	e.Texture = K.SPARKLE
	e.Color = ColorSequence.new(K.FOAM)
	e.Size = NumberSequence.new(0.5)
	e.Lifetime = NumberRange.new(0.3, 0.5)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(90, 90)
	e.Rate = 0
	e.Parent = m.part
	e:Emit(8)
	local done = true
	for _, x in ipairs(w.mud) do
		if x.taps < WASH.ScrubTaps then
			done = false
		end
	end
	if done then
		w.stage = "rinse"
	end
	Wash.show()
end

-- Every frame while a hold is on: the bar, and letting go by itself when it's full.
function Wash.step()
	local w = S.wash
	local h = w and w.holding
	if not h then
		return
	end
	local need = (h.kind == "spray" and WASH.SprayHold or WASH.RinseHold) + K.HOLD_EXTRA
	local share = (os.clock() - h.at) / need
	ui.holdFill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	if share >= 1 then
		Wash.endHold(true)
	end
end

-- Remove the car and every piece of the mini-game. driveOff: the car backs out first.
function Wash.clear(driveOff)
	local w = S.wash
	S.wash = nil
	if not w then
		return
	end
	Wash.water(w, nil)
	for _, m in ipairs(w.mud or {}) do
		if m.gui then
			m.gui:Destroy()
		end
	end
	local car = w.car
	if car and car.Parent then
		local _, mouth = Wash.spots(w)
		if driveOff and mouth then
			Wash.slide(car, car:GetPivot(), mouth * CFrame.new(0, 0, 6), WASH.DepartTime, true)
			task.delay(WASH.DepartTime + 0.1, function()
				car:Destroy()
			end)
		else
			car:Destroy()
		end
	end
end

-- BusinessJob "Wash": a new customer (the last one pulls out first).
function Wash.start(info)
	local old = S.wash
	if old then
		Wash.clear(true)
	end
	local w = {
		id = info.Id, bay = tonumber(info.Bay) or 1, spots = tonumber(info.Spots) or 4, seed = tonumber(info.Seed) or 1,
		owner = info.Owner, stage = "arrive", readyClock = os.clock() + (tonumber(info.Ready) or WASH.ArriveTime),
	}
	S.wash = w
	S.job = S.job and S.job.id == w.id and S.job or { kind = "Wash", id = w.id, earned = 0 }
	S.job.kind = "Wash"
	local inBay, mouth = Wash.spots(w)
	if not inBay then
		return
	end
	local startIn = math.max(0, w.readyClock - os.clock() - WASH.ArriveTime)
	task.delay(startIn, function()
		if S.wash ~= w then
			return
		end
		local car = Wash.buildCar(w.seed)
		car:PivotTo(mouth)
		car.Parent = Wash.folder()
		w.car = car
		Wash.slide(car, mouth, inBay, math.max(0.5, w.readyClock - os.clock()))
		task.delay(math.max(0.5, w.readyClock - os.clock()) + 0.05, function()
			if S.wash ~= w or not car.Parent then
				return
			end
			car:PivotTo(inBay)
			Wash.placeMud(w)
			w.stage = "spray"
			Wash.show()
		end)
	end)
	ui.endJob.Visible = true
	ui.after.Visible = false
	Wash.show()
	Job.place()
end

-- BusinessJob "WashStep": the server's stage (and the taps it counted).
function Wash.onStep(info)
	local w = S.wash
	if not w or type(info) ~= "table" then
		return
	end
	local stage = info.Stage
	if stage ~= "spray" and stage ~= "scrub" and stage ~= "rinse" then
		return
	end
	if w.holding and w.holding.kind ~= stage then
		w.holding = nil
		Wash.water(w, nil)
	end
	if type(info.Taps) == "table" then
		for i, m in ipairs(w.mud or {}) do
			local t = tonumber(info.Taps[i]) or 0
			if t ~= m.taps then
				m.taps = t
				m.part.Transparency = math.min(1, t / WASH.ScrubTaps)
				if m.button then
					local left = WASH.ScrubTaps - t
					m.button.Text = left > 0 and (t > 0 and ("SCRUB ×" .. left) or "SCRUB") or "✓"
				end
			end
		end
	end
	if stage == "spray" then
		Wash.foam(w, false)
	elseif stage == "scrub" and w.stage ~= "scrub" then
		Wash.foam(w, true)
	end
	w.stage = stage
	Wash.show()
end

-- BusinessJob "WashPaid".
function Wash.onPaid(info)
	local w = S.wash
	if w then
		w.stage = "paid"
		Wash.foam(w, false)
		Wash.sparkle(w)
	end
	if S.job then
		S.job.earned = tonumber(info.Earned) or S.job.earned
	end
	local pay, tip = tonumber(info.Pay) or 0, tonumber(info.Tip) or 0
	if info.Refused then
		-- (the server's MinTime: faster than a human can wash; that car isn't paid, the job goes on)
		NotifyController.Show("Too fast: that car wasn't paid. Take your time with the next one.", nil, "warning")
		ui.afterTitle.Text = '<font color="#' .. C.Danger:ToHex() .. '">NOT PAID</font>  <font size="14">TOO FAST</font>'
		Wash.show()
		Job.place()
		return
	end
	sound("CashIn")
	NotifyController.Show(string.format("Car washed: +%s%s", money(pay + tip), info.Clean and (" (clean finish tip " .. money(tip) .. ")") or ""),
		C.Cash, "money")
	ui.afterTitle.Text = string.format('<font color="#%s">+%s</font>%s', C.Cash:ToHex(), money(pay + tip),
		info.Clean and '  <font size="14">CLEAN FINISH</font>' or "")
	Wash.show()
	Job.place()
end

------------------------------------------------------------------ rush orders (Palm Grind)

-- The HOLD button belongs to whichever job is on: the wash's SPRAY / RINSE, or the rush orders' GRAB.
function Job.holdBegin(pointer)
	if S.wash then
		Wash.startHold(pointer)
	else
		Rush.startHold(pointer)
	end
end

function Job.holdEnd(done)
	if S.wash and S.wash.holding then
		Wash.endHold(done)
	elseif S.job and S.job.kind == "Rush" and S.job.holding then
		Rush.endHold(done)
	end
end

-- The hold that's on now (the wash's or the rush job's), or nil.
function Job.holding()
	return (S.wash and S.wash.holding) or (S.job and S.job.kind == "Rush" and S.job.holding) or nil
end

-- In the driver's seat of your own land car (the rush job's rule, as the server's)?
function Rush.inOwnCar()
	local hum = myHum()
	local seat = hum and hum.SeatPart
	local car = seat and seat.Name == "DriverSeat" and seat.Parent
	return car ~= nil and car:GetAttribute("OwnerUserId") == player.UserId and car:GetAttribute("Boat") ~= true
end

-- Waiting for an order, on foot, at the RUSH ORDERS shelf: the GRAB hold can show.
function Rush.canGrab()
	local job = S.job
	if not job or job.kind ~= "Rush" or job.stage ~= "pickup" or (job.waitUntil and os.clock() < job.waitUntil) then
		return false -- (waitUntil: a full GRAB was just sent; the order is on its way)
	end
	if S.alarm[job.id] then
		return false -- (robbers at the counter: the gun comes first, and the HOLD would count as a panel and lower it)
	end
	local def = defOf(job.id)
	local root, hum = myRoot(), myHum()
	if not def or not def.Layout.Orders or not root or not hum or hum.SeatPart or hum.Health <= 0 then
		return false
	end
	local spot = Businesses.At(def, def.Layout.Orders)
	return flat(root.Position - spot).Magnitude <= K.GRAB_RANGE and math.abs(root.Position.Y - spot.Y) < 12
end

-- The HOLD button for GRAB (shown at the shelf, and for as long as a hold is on).
function Rush.show()
	local job = S.job
	local show = Rush.canGrab() or (job ~= nil and job.kind == "Rush" and job.holding ~= nil)
	ui.hold.Visible = show == true
	if show and not job.holding then
		ui.holdFill.Size = UDim2.fromScale(0, 1)
		ui.holdFill.BackgroundColor3 = K.BREW
		ui.holdText.Text = "HOLD TO GRAB THE ORDER"
	end
end

-- pointer: the mouse or touch InputObject holding it (nil: a key).
function Rush.startHold(pointer)
	local job = S.job
	if not job or job.kind ~= "Rush" or job.holding or not Rush.canGrab() then
		return
	end
	job.holding = { at = os.clock(), pointer = pointer }
	ui.holdFill.BackgroundColor3 = K.BREW
	request("Step", "GrabOn")
	sound("Click")
end

-- Let go: early (the server says "RushStep" Again) or at the end of the hold (done = true).
function Rush.endHold(done)
	local job = S.job
	local h = job and job.holding
	if not h then
		return
	end
	job.holding = nil
	request("Step", "GrabOff")
	ui.holdFill.Size = UDim2.fromScale(0, 1)
	if done then
		job.waitUntil = os.clock() + 1.5
		sound("Success")
	elseif not job.toldHold then
		job.toldHold = true
		NotifyController.Show("Hold it until the bar is full to grab the order.", nil, "info")
	end
	Rush.show()
end

-- Every frame while GRAB is held: the bar, and letting go by itself when it's full.
function Rush.step()
	local job = S.job
	local h = job and job.kind == "Rush" and job.holding
	if not h then
		return
	end
	local share = (os.clock() - h.at) / (Businesses.Rush.GrabHold + K.HOLD_EXTRA)
	ui.holdFill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	if share >= 1 then
		Rush.endHold(true)
	end
end

-- Five times a second while on rush orders: the HOLD button, and our GPS back to the café cleared on arrival.
function Rush.tick()
	local job = S.job
	if not job or job.kind ~= "Rush" then
		return
	end
	if not S.wash then
		Rush.show()
	end
	local def = defOf(job.id)
	local root = myRoot()
	if job.stage == "pickup" and def and root and S.gpsName == (def.Brand or def.Name)
		and flat(root.Position - def.Position).Magnitude <= Businesses.Reach then
		Job.clearGPS()
	end
end

-- The strip: tag, what to do, and the right-hand words (the clock, and the tip it would pay now on a PC).
function Rush.line(touch)
	local job = S.job
	local def = defOf(job.id)
	if job.stage ~= "drive" or not job.pos then
		job.late = false
		local root = myRoot()
		local right = (job.earned or 0) > 0 and money(job.earned) or ""
		if root and def and flat(root.Position - def.Position).Magnitude <= Businesses.Reach then
			-- (short enough for the PC strip: the longer "GRAB AN ORDER AT THE RUSH ORDERS SHELF" was cut off)
			return "RUSH ORDER", Rush.canGrab() and "HOLD TO GRAB THE ORDER" or "STAND ON THE YELLOW PICK-UP MAT", right
		end
		local dist = (root and def) and GPSClient.FormatDistance(flat(root.Position - Businesses.DoorPosition(def)).Magnitude) or ""
		return "RUSH ORDER", "BACK TO " .. string.upper(def and (def.Brand or def.Name) or "THE CAFÉ") .. " FOR THE NEXT ORDER", dist
	end
	local left = (job.endsAt or serverNow()) - serverNow()
	job.late = left <= 0
	local title = (job.vip and ("VIP ORDER · " .. string.upper(tostring(job.name or ""))) or ("DELIVER TO " .. string.upper(tostring(job.name or ""))))
		.. ((job.of or 1) > 1 and string.format(" (%d/%d)", job.leg or 1, job.of) or "")
	if not Rush.inOwnCar() then
		title = "GET IN YOUR CAR · " .. title
	end
	if job.late then
		return "RUSH ORDER", title, "LATE"
	end
	local tip = def and Businesses.RushTip(def, job.level or 1, (job.timer or 0) - left, job.timer or 1, job.vip) or 0
	return "RUSH ORDER", title, touch and clock(left) or (money(tip) .. "  " .. clock(left))
end

-- BusinessJob "Rush": at the counter (a new job, or back from an order).
function Rush.onStart(info)
	Card.close()
	Wash.clear(true)
	ui.after.Visible = false
	local old = S.job
	local fresh = not old or old.kind ~= "Rush" or old.id ~= info.Id
	S.job = { kind = "Rush", id = info.Id, stage = "pickup", level = tonumber(info.Level) or 1, earned = tonumber(info.Earned) or 0,
		count = tonumber(info.Count) or 0, toldHold = not fresh and old.toldHold or nil }
	Job.marker(nil)
	local def = defOf(info.Id)
	if info.Back and def then
		Job.setGPS(def.Brand or def.Name, Businesses.DoorPosition(def))
	end
	if fresh then
		NotifyController.Show("Rush orders: hold GRAB at the RUSH ORDERS shelf, then drive the order over in your own car. The faster you get there, the bigger the tip.",
			nil, "info")
	end
	ui.endJob.Visible = true
	Rush.show()
	Job.place()
end

-- BusinessJob "RushStep": the GRAB didn't count (let go early, or not at the shelf).
function Rush.onStep(info)
	local job = S.job
	if not job or job.kind ~= "Rush" then
		return
	end
	job.holding, job.waitUntil = nil, nil
	ui.holdFill.Size = UDim2.fromScale(0, 1)
	if info.Far then
		NotifyController.Show("Stand at the RUSH ORDERS shelf (the yellow mat) to grab an order.", nil, "info")
	elseif not job.toldHold then
		job.toldHold = true
		NotifyController.Show("Hold it until the bar is full to grab the order.", nil, "info")
	end
	Rush.show()
end

-- BusinessJob "RushLeg": the next address (the order's first one says what the order is).
function Rush.onLeg(info)
	local job = S.job
	if not job or job.kind ~= "Rush" then
		job = { kind = "Rush", id = info.Id, earned = 0, count = 0 }
		S.job = job
	end
	Card.close()
	job.holding = nil
	job.stage = "drive"
	job.pos = typeof(info.Pos) == "Vector3" and info.Pos or nil
	job.name, job.who, job.vip = info.Name, info.Who, info.Vip == true
	job.leg, job.of = tonumber(info.Leg) or 1, tonumber(info.Of) or 1
	job.timer = tonumber(info.Timer) or 30
	job.endsAt = tonumber(info.Ends) or (serverNow() + job.timer)
	job.level = tonumber(info.Level) or job.level or 1
	job.earned = tonumber(info.Earned) or job.earned
	ui.hold.Visible = false
	ui.endJob.Visible = true
	if job.pos then
		Job.marker(job.pos)
		Job.setGPS(tostring(info.Name or "Customer"), job.pos)
	end
	local where = job.vip and (tostring(info.Who or "a VIP") .. " at " .. tostring(info.Name or "a big home")) or tostring(info.Name or "the customer")
	if info.First then
		sound("Success")
		local more = job.of > 1 and string.format(" (then %d more stop%s)", job.of - 1, job.of > 2 and "s" or "") or ""
		NotifyController.Show(string.format("Order up! Take it to %s%s. Get in your car: the clock is running (%s).", where, more, clock(job.timer)),
			C.Gold, "info")
	elseif job.vip then
		NotifyController.Show("Last stop: a VIP order for " .. where .. ". VIPs tip big!", C.Gold, "info")
	end
	Job.place()
end

-- BusinessJob "RushPaid": one address delivered (an ORDER DELIVERED stamp after the order's last).
function Rush.onPaid(info)
	local job = S.job
	local pay, tip = tonumber(info.Pay) or 0, tonumber(info.Tip) or 0
	if job and job.kind == "Rush" then
		job.earned = tonumber(info.Earned) or job.earned
		job.count = tonumber(info.Count) or job.count
	end
	sound("CashIn")
	local tipWords = info.Late and " (late: no tip)" or (tip > 0 and (" (tip " .. money(tip) .. ")") or "")
	NotifyController.Show(string.format("%s to %s: +%s%s", info.Vip and "VIP order delivered" or "Delivered", tostring(info.Name or "the customer"),
		money(pay + tip), tipWords), C.Cash, "money")
	if info.Last then
		Job.marker(nil)
		local stops = tonumber(info.Of) or 1
		HUDController.Stamp("ORDER DELIVERED", money(tonumber(info.Order) or (pay + tip)) .. string.format(" · %d stop%s", stops, stops == 1 and "" or "s"),
			C.Cash, "RUSH ORDER")
	end
end

------------------------------------------------------------------ server events

local function onJob(kind, info)
	if type(info) ~= "table" then
		info = {}
	end
	if kind == "Wash" then
		Card.close()
		Wash.start(info)
	elseif kind == "WashStep" then
		Wash.onStep(info)
	elseif kind == "WashPaid" then
		Wash.onPaid(info)
	elseif kind == "Detail" then
		Card.close()
		Wash.clear(true)
		ui.hold.Visible = false
		ui.after.Visible = false
		local earned = S.job and S.job.earned or 0
		S.job = { kind = "Detail", id = info.Id, pos = typeof(info.Pos) == "Vector3" and info.Pos or nil, name = info.Name,
			car = info.Car, est = tonumber(info.Est), since = os.clock(), earned = earned }
		if S.job.pos then
			Job.marker(S.job.pos)
			Job.setGPS(tostring(info.Name or "Customer"), S.job.pos)
		end
		ui.endJob.Visible = true
		Job.place()
		NotifyController.Show("Drive the " .. tostring(info.Car or "car") .. " to " .. tostring(info.Name or "its owner")
			.. ". Fast and clean pays the full tip: every dent costs you.", nil, "info")
	elseif kind == "Dent" then
		sound("Crash")
		NotifyController.Show(string.format("Dent! -%s off the tip (%d so far).", money(Businesses.Detail.DentCost), tonumber(info.Dents) or 1),
			C.Orange, "warning")
	elseif kind == "DetailPaid" then
		local pay, tip = tonumber(info.Pay) or 0, tonumber(info.Tip) or 0
		sound("CashIn")
		HUDController.Stamp("DELIVERED", money(pay + tip) .. (tip > 0 and (" · tip " .. money(tip)) or " · no tip"), C.Cash)
		NotifyController.Show("Need a ride back? Tap CAR to call yours.", nil, "info")
	elseif kind == "Rush" then
		Rush.onStart(info)
	elseif kind == "RushStep" then
		Rush.onStep(info)
	elseif kind == "RushLeg" then
		Rush.onLeg(info)
	elseif kind == "RushPaid" then
		Rush.onPaid(info)
	elseif kind == "Ended" then
		Job.finish(info)
	end
end

local function onResult(info)
	if type(info) ~= "table" then
		return
	end
	local def = defOf(info.Id)
	local short = def and def.Short or "business"
	local k = info.Kind
	if k == "Bought" and def then
		Card.close()
		sound("Success")
		HUDController.Stamp("YOU OWN IT", "The " .. def.Name .. " is yours", C.Gold, "EMPIRE")
		NotifyController.Show(def.Hint or "Press Manage at the door: START JOB to work there. The register fills while you play.", nil, "info")
	elseif k == "Upgraded" and def then
		sound("Success")
		local lv = def.Levels[Businesses.ClampLevel(info.Level)]
		HUDController.Stamp("LEVEL " .. tostring(info.Level), lv and lv.Adds or def.Name, C.Gold, string.upper(short))
	elseif k == "Collected" then
		sound("CashIn")
		NotifyController.Show("+" .. money(tonumber(info.Amount) or 0) .. " from your " .. short .. " register.", C.Cash, "money")
	elseif k == "Full" and def then
		NotifyController.Show("Your " .. short .. " register is full. Collect it!", C.Gold, "money")
	elseif k == "Customer" then
		sound("CashIn")
		NotifyController.Show(string.format("%s got %s at your %s +%s", tostring(info.Buyer or "Someone"), tostring(info.Service or "a shine"), short,
			money(tonumber(info.Amount) or 0)), C.Cash, "money")
	elseif k == "Shined" then
		sound("Success")
		NotifyController.Show("Sparkling clean for 30 minutes! (-" .. money(tonumber(info.Price) or 0) .. ")"
			.. (info.Owner and (" " .. tostring(info.Owner) .. " says thanks.") or ""), C.Cash, "success")
	elseif k == "ColdBrew" then
		sound("Success")
		local CB = Businesses.ColdBrew
		S.brewUntil = tonumber(info.Until) or S.brewUntil
		NotifyController.Show(string.format("Cold brew! +%d%% sprint stamina for %d minutes. (-%s)%s", math.floor(CB.Stamina * 100 + 0.5),
			math.floor(CB.Seconds / 60), money(tonumber(info.Price) or 0), info.Owner and (" " .. tostring(info.Owner) .. " says thanks.") or ""),
			C.Cash, "success")
	elseif k == "CrewCut" then
		sound("Cash")
		NotifyController.Show(string.format("%s worked your %s: +%s crew cut", tostring(info.Worker or "A crewmate"), short,
			money(tonumber(info.Amount) or 0)), C.Cash, "crew")
	elseif k == "BreakIn" and def then
		local untilT = tonumber(info.Until) or (serverNow() + Businesses.BreakIn.Time)
		local isMine = info.Owner == player.UserId
		S.alarm[def.Id] = { untilT = untilT, ownerName = info.OwnerName, mine = isMine }
		sound("Spotted")
		local where = isMine and ("your " .. short) or (tostring(info.OwnerName) .. "'s " .. short)
		NotifyController.Show(string.format("Someone's breaking into %s! Get there in %s: point a gun at them or knock them down.",
			where, clock(untilT - serverNow())), C.Danger, "police")
		if not S.job then
			Job.setGPS("Break-in: " .. (def.Brand or def.Name), Businesses.DoorPosition(def))
		end
	elseif k == "RobberStopped" then
		sound("CashIn")
		local left = tonumber(info.Left) or 0
		NotifyController.Show("Robber stopped! +" .. money(tonumber(info.Reward) or 0) .. (left > 0 and (" (" .. left .. " left)") or ""), C.Cash, "success")
	elseif k == "BreakInStopped" and def then
		S.alarm[def.Id] = nil
		if S.gpsName and string.sub(S.gpsName, 1, 9) == "Break-in:" then
			Job.clearGPS()
		end
		HUDController.Stamp("BREAK-IN STOPPED", info.Owner == player.UserId and ("Your " .. short .. " is safe") or
			(tostring(info.OwnerName) .. "'s " .. short .. " is safe"), C.Cash)
	elseif k == "BreakInLost" and def then
		S.alarm[def.Id] = nil
		if S.gpsName and string.sub(S.gpsName, 1, 9) == "Break-in:" then
			Job.clearGPS()
		end
		local amount = money(tonumber(info.Amount) or 0)
		NotifyController.Show(info.Owner == player.UserId and ("The robbers got away with " .. amount .. " from your " .. short .. " register.")
			or ("The robbers got away with " .. amount .. " from " .. tostring(info.OwnerName) .. "'s " .. short .. "."), C.Orange, "warning")
	elseif k == "RankUp" then
		sound("Success")
		HUDController.Stamp("EMPIRE RANK " .. tostring(info.Rank), info.Unlock and ("Unlocked: " .. tostring(info.Unlock)) or "Keep building your empire", C.Gold, "EMPIRE")
	elseif k == "No" then
		local text = K.MSG[info.Reason or ""]
		if info.Reason == "Locked" and def then
			text = "Reach Empire rank " .. def.Unlock .. " to buy the " .. def.Name .. "."
		end
		if text then
			NotifyController.Show(text, nil, "warning")
		end
		Wash.show() -- (NEXT CAR / DELIVER refused after a wash: the AFTER panel comes back)
	end
	local phone = other("PhoneUI")
	if phone and type(phone.Refresh) == "function" then
		pcall(phone.Refresh, "Empire")
	end
end

local function onState(info)
	if type(info) ~= "table" then
		return
	end
	S.state = info
	if S.card then
		Card.fill()
	end
	Fx.dressAll()
	local phone = other("PhoneUI")
	if phone and type(phone.Refresh) == "function" then
		pcall(phone.Refresh, "Empire")
	end
end

local function readOwners()
	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("BizOwners") or "{}")
	end)
	S.owners = (ok and type(decoded) == "table") and decoded or {}
	Fx.dressAll()
end

------------------------------------------------------------------ robbers (poses, and a gun pointed at one)

function Fx.robbers()
	local npcs = Workspace:FindFirstChild("NPCs")
	if not npcs then
		return
	end
	local combat = other("CombatClient")
	local aiming, from, look, gunAt = false, nil, nil, nil
	if combat and type(combat.Aiming) == "function" then
		local ok, a, f, l, g = pcall(combat.Aiming)
		if ok then
			aiming, from, look, gunAt = a, f, l, g
		end
	end
	for _, m in ipairs(npcs:GetChildren()) do
		if m.Name == "BizRobber" and m:IsA("Model") then
			-- The pose (PoseClient, if it's there).
			local want = m:GetAttribute("Pose")
			local shown = S.robberPoses[m]
			if (shown and shown.name or nil) ~= want then
				if shown and shown.handle then
					pcall(function()
						shown.handle:Stop()
					end)
				end
				local handle
				local pose = want and other("PoseClient")
				if pose then
					pcall(function()
						handle = pose.Play(m, want)
					end)
				end
				S.robberPoses[m] = want and { name = want, handle = handle } or nil
			end
			-- A gun on it: ask the server to scare it off (it checks it's yours or your crewmate's).
			local head = m:FindFirstChild("Head")
			if aiming and head and m:GetAttribute("NPCKind") == "BizRobber" and look and os.clock() - S.lastScare >= K.SCARE_GAP then
				local owner = Players:GetPlayerByUserId(m:GetAttribute("BizOwner") or 0)
				local to = head.Position - (from or head.Position)
				local reach = (head.Position - (gunAt or head.Position)).Magnitude
				if (owner == player or isCrewmate(owner)) and reach <= K.SCARE_REACH and to.Magnitude > 1 and to.Unit:Dot(look) > K.SCARE_CONE then
					S.lastScare = os.clock()
					request("Scare", nil, m)
				end
			end
		end
	end
end

------------------------------------------------------------------ public

function BusinessClient.On()
	return S.on
end

-- A card, or the wash mini-game while a car is in the bay (CombatClient and InteractClient ask).
function BusinessClient.IsOpen()
	if S.card ~= nil and ui.card ~= nil and ui.card.Visible then
		return true
	end
	-- Only while you're actually washing: the AFTER panel (NEXT CAR / DELIVER / END, stage "paid") and waiting for
	-- a car ("wait", "arrive") don't count, so F still gets you into your car and a gun still comes up for a
	-- break-in (the review found both blocked).
	-- The rush orders' GRAB hold, while it shows at the shelf (its F is ours, and a gun stays down there).
	if S.job ~= nil and S.job.kind == "Rush" and ui.hold ~= nil and ui.hold.Visible then
		return true
	end
	local w = S.wash
	return w ~= nil and w.stage ~= "arrive" and w.stage ~= "paid" and w.stage ~= "wait"
end

function BusinessClient.Owned()
	local list = {}
	for _, def in ipairs(Businesses.List) do
		local e = def.Enabled and mine(def.Id)
		if e then
			table.insert(list, {
				Id = def.Id, Name = def.Name, Short = def.Short, Level = Businesses.ClampLevel(e.Level), Register = liveRegister(def.Id),
				Cap = tonumber(e.Cap) or 0, Rate = tonumber(e.Rate) or 0, Busy = e.Busy == true, Next = tonumber(e.Next),
				Lifetime = tonumber(e.Lifetime) or 0, JobsDone = tonumber(e.JobsDone) or 0, Pos = Businesses.DoorPosition(def),
			})
		end
	end
	return list
end

function BusinessClient.ForSale()
	local list = {}
	local rank = empireRank()
	for _, def in ipairs(Businesses.List) do
		if def.Enabled and def.Position and not mine(def.Id) then
			table.insert(list, {
				Id = def.Id, Name = def.Name, Price = def.Price, Unlock = def.Unlock or 1, Locked = not Businesses.Unlocked(def, rank),
				Pos = Businesses.DoorPosition(def), JobLine = def.JobLine, Trickle = def.Levels[1].Trickle,
			})
		end
	end
	return list
end

function BusinessClient.ComingSoon()
	local list = {}
	for _, def in ipairs(Businesses.List) do
		if not def.Enabled then
			table.insert(list, { Id = def.Id, Name = def.Name, Price = def.Price, Unlock = def.Unlock or 1, JobLine = def.JobLine, Kind = def.Kind })
		end
	end
	return list
end

function BusinessClient.Empire()
	local xp = empireXP()
	local rank, share, into, need = Businesses.RankProgress(xp)
	local nextUnlock
	for r = rank + 1, E.MaxRank do
		if E.Unlocks[r] then
			nextUnlock = "Rank " .. r .. ": " .. E.Unlocks[r]
			break
		end
	end
	return { Rank = rank, XP = math.floor(xp), Share = share, Into = math.floor(into), Need = need, Next = nextUnlock,
		Title = player:GetAttribute("EmpireTitle"), RemoteCollect = rank >= E.RemoteCollect, RemoteRank = E.RemoteCollect }
end

function BusinessClient.RouteTo(id)
	local def = defOf(id)
	if not def or not def.Position then
		return false
	end
	GPSClient.SetTarget(def.Name, Businesses.DoorPosition(def))
	return true
end

function BusinessClient.Collect(id)
	request("Collect", id, "Remote")
end

-- The businesses' map blips (MinimapClient, MapClient): your own get a gold ring, a break-in flashes red.
function BusinessClient.MapBlips()
	local list = {}
	if not S.on then
		return list
	end
	local alarms = {}
	for id in string.gmatch(player:GetAttribute("BizAlarm") or "", "[^,]+") do
		alarms[id] = true
	end
	for _, def in ipairs(Businesses.List) do
		if def.Enabled and def.Position then
			table.insert(list, {
				Id = def.Id, Name = def.Name, Pos = Businesses.DoorPosition(def), Letter = def.MapLetter or "$",
				Color = def.MapColor or C.Gold, Owned = mine(def.Id) ~= nil, Alarm = alarms[def.Id] == true,
			})
		end
	end
	return list
end

------------------------------------------------------------------ start

local function build()
	ui.gui = Instance.new("ScreenGui")
	ui.gui.Name = "Business"
	ui.gui.ResetOnSpawn = false
	ui.gui.IgnoreGuiInset = true
	ui.gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	ui.gui.DisplayOrder = K.DISPLAY_ORDER
	ui.gui.Parent = player:WaitForChild("PlayerGui")
	Card.build()
	Job.build()
end

local function start()
	S.on = true
	build()
	Remotes.OnClient("BusinessCard", function(info)
		if type(info) == "table" then
			Card.open(info)
		end
	end)
	Remotes.OnClient("BusinessState", onState)
	Remotes.OnClient("BusinessResult", onResult)
	Remotes.OnClient("BusinessJob", onJob)
	request("State")
	readOwners()
	ReplicatedStorage:GetAttributeChangedSignal("BizOwners"):Connect(readOwners)
	-- Crews change who counts as "your crewmate" for the props and the plates.
	ReplicatedStorage:GetAttributeChangedSignal("Crews"):Connect(Fx.dressAll)
	player:GetAttributeChangedSignal("Crew"):Connect(Fx.dressAll)
	Workspace:GetAttributeChangedSignal("BizTestCrew"):Connect(Fx.dressAll)
	player:GetAttributeChangedSignal("Cash"):Connect(function()
		if S.card then
			Card.fill()
		end
	end)
	player:GetAttributeChangedSignal("EmpireXP"):Connect(function()
		local phone = other("PhoneUI")
		if phone and type(phone.Refresh) == "function" then
			pcall(phone.Refresh, "Empire")
		end
	end)
	player:GetAttributeChangedSignal("InHome"):Connect(function()
		if player:GetAttribute("InHome") == true then
			Card.close()
		end
	end)
	-- Level props as they stream in, and again after SkyClient switches the night lights (it would light a
	-- hidden prop's lamp).
	CollectionService:GetInstanceAddedSignal("BizProp"):Connect(function(part)
		if part:IsA("BasePart") then
			Fx.setProp(part, Fx.propWanted(part))
		end
	end)
	Workspace:GetAttributeChangedSignal("IsNight"):Connect(function()
		task.delay(0.3, Fx.applyProps)
		task.delay(8, Fx.applyProps) -- (after the dusk wave)
	end)
	task.spawn(function()
		local shops = Workspace:WaitForChild("Shops", 60)
		if shops then
			shops.DescendantAdded:Connect(function(d)
				if d:IsA("Model") and d:GetAttribute("BusinessId") then
					task.defer(Fx.dressSite, d)
				elseif d.Name == "OwnerPlate" or d.Name == "BusinessDoor" then
					local m = d:FindFirstAncestorWhichIsA("Model")
					while m and not m:GetAttribute("BusinessId") do
						m = m:FindFirstAncestorWhichIsA("Model")
					end
					if m then
						task.defer(Fx.dressSite, m)
					end
				end
			end)
			Fx.dressAll()
		end
	end)
	-- Re-place for a new screen size or kind of input (the phone layout).
	local function replace()
		if S.card then
			Card.layout()
		end
		Job.place()
	end
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(replace)
	UserInputService.LastInputTypeChanged:Connect(replace)
	player:GetAttributeChangedSignal("PreviewTouch"):Connect(replace)
	-- Keys: the card (X / B close, Enter / Y its first button) and HOLD (F / RT).
	UserInputService.InputBegan:Connect(function(input, processed)
		local key = input.KeyCode
		local hum = myHum()
		local seated = hum ~= nil and hum.SeatPart ~= nil
		if S.card and not seated then
			if key == Enum.KeyCode.ButtonB or (key == Enum.KeyCode.X and not processed) then
				Card.close()
				return
			end
			if not processed and not RobloxMenu.IsOpen()
				and (key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter or key == Enum.KeyCode.ButtonY) then
				local fn = S.actions[1]
				if fn and ui.buttons[1].Visible then
					fn()
				end
				return
			end
		end
		if (S.wash or Rush.canGrab()) and not seated and not processed and (key == Enum.KeyCode.F or key == Enum.KeyCode.ButtonR2) then
			Job.holdBegin()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local h = Job.holding()
		if not h then
			return
		end
		if h.pointer then
			if input == h.pointer or input.UserInputType == Enum.UserInputType.MouseButton1 and h.pointer.UserInputType == Enum.UserInputType.MouseButton1 then
				Job.holdEnd()
			end
		elseif input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonR2 then
			Job.holdEnd()
		end
	end)
	-- The cold brew's "wore off" toast (the attribute is the server's).
	player:GetAttributeChangedSignal("ColdBrewUntil"):Connect(function()
		local untilT = player:GetAttribute("ColdBrewUntil")
		S.brewUntil = type(untilT) == "number" and untilT or nil
	end)
	-- Every frame: the hold bar. Four / five times a second: the card, the strip, prompts, robbers.
	RunService.RenderStepped:Connect(function()
		Wash.step()
		Rush.step()
	end)
	local lastFast, lastSlow = 0, 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastFast >= 0.2 then
			lastFast = now
			local ok, err = pcall(function()
				local c = S.card
				if c then
					local root = myRoot()
					local hum = myHum()
					local def = defOf(c.id)
					-- (the server's own rule for the buttons: within Reach of the lot's middle; a little inside it)
					local d = root and (root.Position - def.Position)
					if not root or not def or (hum and hum.SeatPart) or math.abs(d.Y) > 25
						or flat(d).Magnitude > Businesses.Reach - 2 then
						Card.close()
					else
						Card.live()
					end
				end
				for id, a in pairs(S.alarm) do
					if a.untilT < serverNow() - 2 then
						S.alarm[id] = nil
					end
				end
				Rush.tick()
				Job.strip()
				if S.job then
					Job.place()
				end
				Fx.prompts()
				Fx.robbers()
			end)
			if not ok then
				warn("[BusinessClient] " .. tostring(err))
			end
		end
		if now - lastSlow >= 1 then
			lastSlow = now
			local ok, err = pcall(Fx.shineTick)
			if not ok then
				warn("[BusinessClient] shine: " .. tostring(err))
			end
			if S.brewUntil and serverNow() >= S.brewUntil then
				S.brewUntil = nil
				NotifyController.Show("Your cold brew wore off.", nil, "info")
			end
			-- The EMPIRE app's registers keep filling while it's open: redraw it every few seconds.
			S.appTick = (S.appTick or 0) + 1
			if S.appTick % 5 == 0 and next(S.state and S.state.List or {}) ~= nil then
				local phone = other("PhoneUI")
				if phone and type(phone.Refresh) == "function" then
					pcall(phone.Refresh, "Empire")
				end
			end
		end
	end)
	-- A new character: the wash's local car and buttons go (the server ends the job too).
	player.CharacterAdded:Connect(function()
		Card.close()
	end)
end

function BusinessClient.Init()
	-- Off until the server says the feature runs here (the launch switch).
	-- (No timeout: a slow server start used to leave this device without businesses for the session.)
	local started = false
	local function tryStart()
		if started or ReplicatedStorage:GetAttribute("BusinessesOn") ~= true then
			return
		end
		started = true
		local ok, err = pcall(start)
		if not ok then
			warn("[BusinessClient] failed to start: " .. tostring(err))
		end
	end
	ReplicatedStorage:GetAttributeChangedSignal("BusinessesOn"):Connect(tryStart)
	tryStart()
end

return BusinessClient
