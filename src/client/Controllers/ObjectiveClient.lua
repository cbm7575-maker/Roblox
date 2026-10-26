-- ObjectiveClient (ModuleScript, StarterPlayerScripts.Controllers.ObjectiveClient)
-- One "what do I do now?" strip for crime moments, and it points the GPS for you. It follows your
-- state, most urgent first:
--   1. In prison                 -> "Find the vent in the yard" (GPS to the vent)
--   2. Wanted (Heat > 0)         -> "Lose the cops", what comes after it (bank the bag, deliver the hot
--                                   car), and an escape line: whether they can see you, the patrols'
--                                   head start (PoliceETA from AIPoliceService) or how long to stay
--                                   hidden (EscapeAt from HeatService; a guess, "ABOUT 0:32", without
--                                   it). The GPS is left alone, so a Hideout or Chop Shop route set by
--                                   the robbery / theft stays up.
--   3. Cash in your bag          -> "Bank $X at the Hideout" (GPS to the Hideout)
--   4. Driving a boosted hot car -> "Take it to the Chop Shop" (GPS to the Chop Shop)
--   5. Driving a jacked car      -> "Joyride, or sell it" (no GPS of its own: it only keeps the
--                                   suggested Chop Shop route while you drive it), or just "Joyride"
--                                   for a car the Chop Shop won't buy (JackSellable = false: taken
--                                   right by the Chop Shop)
-- The words are kept short enough for one line each on a 667 px-wide phone (about 26 characters for a
-- title after its tag, 38 for a second line): the strip never wraps and cuts the rest with "...".
-- Also: whenever you steal a hot car (BoostStolenAt changes, CarBoostService sets it on every theft)
-- a stamp says where to take it and the GPS is set. Jacking a car (Carjacked from CarjackService)
-- stamps "CAR JACKED" (or "CAR ALARM", in red) with its Chop Shop price, and routes the GPS to the Chop
-- Shop only as a suggestion: never over a target the player picked themselves, never over the route of
-- the objective on screen (e.g. the Hideout for a bag), never with cash in the bag, and not for a car
-- the Chop Shop won't buy.
-- Hidden during races, job shifts and missions (they have their own banners), for cops, and while the
-- first-join title screen is up (local attribute TitleScreen, set by TeamUI). Hidden too while you're on
-- the Big Score's roster (player attribute BigScore): BigScoreClient draws that heist's strip in this same
-- Goal zone, so Active() stays true meanwhile and the tutorial's goal keeps out of its way as well. Not in
-- prison, though (a prisoner stays on that roster): the vent strip comes first there.
-- Look and place ("street" HUD, Theme; re-placed when the screen size or input type changes):
--   * Frame "Banner" (the name MinimapClient / SoundClient look for) sits in the GOAL zone, top centre:
--     a slim flat dark strip with a thin colour bar at its left edge, a small Display tag in the colour
--     that means something (PRISON orange; WANTED white, red and blinking while a cop can see you; BAG,
--     HOT CAR and JACKED gold: a goal with a reward), one line of white words (bag cash and car values in
--     gold) and a dim second line. TutorialClient's goal / guide steps aside while it shows (Changed).
--   * Frame "Escape" (only while wanted) sits in the BANNER zone under it: text straight on the screen
--     with a soft shadow, a small word and a big Display value, both in the colour that means
--     something: "STAY HIDDEN 0:32" (dim word, white time), "PATROLS ARRIVE IN 0:12" (police blue),
--     "SEEN  BREAK LINE OF SIGHT" (red). The stars themselves are HUDController's (Status zone), so
--     they aren't repeated here.
--   Each steps aside while a HUDController stamp would draw over it (HUDController.StampTop; on phones
--   the Stamp zone reaches into the Banner zone, so the escape line steps aside for every stamp there),
--   then comes back; `active` stays true meanwhile. StampTop is in zone coordinates (y = 0 at the very
--   top of the screen), so the pieces are measured from this ScreenGui's own corner.
-- GPS rule: a target this module set is cleared when its objective ends; a target the player picked
-- themselves (GPSClient.Target() isn't the name we set) is never cleared.
-- Must start after HUDController and GPSClient in ClientMain's ORDER.
--   ObjectiveClient.Active() -> true while there is an objective (shown, or stepped aside for a stamp),
--     or the Big Score's strip has the Goal zone
--   ObjectiveClient.Changed  -> event(active), fired when that flips (TutorialClient listens)
--   ObjectiveClient.RouteTo(placeName) -> point the GPS at a place from MapService's "Places" list,
--     as ours; returns true if the route is set (HeistClient: "bank it at the Hideout (GPS set)").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local GPSClient = require(script.Parent:WaitForChild("GPSClient"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))

local player = Players.LocalPlayer

local ObjectiveClient = {}

local C = Theme.Color

local UPDATE_EVERY = 0.25
local HOLLOW_AFTER = 8 -- HeatService: stars go hollow 8 s after the last sighting
local HOT_CAR_NEAR = 300 -- a parked hot car of ours this close still counts ("get back in")
local GPS_SKIP = 60 -- no route to a place you're already standing next to
local VENT_NAME = "Prison vent"
local HIDEOUT = "Hideout"
local CHOP_SHOP = "Chop Shop"

-- Inside the strip (pixels): the colour bar, then the words.
local ACCENT_X, ACCENT_W = 7, 3
local TEXT_X = 18

local changed = Instance.new("BindableEvent")
ObjectiveClient.Changed = changed.Event

local gui, banner, accent, titleLabel, detailLabel
local escape, escWord, escValue
local tagSize = 17 -- the Display tag's text size (place() sets it from the words' size)
local active = false
local current -- the objective on screen (table) or nil
local mine -- name of the GPS target this module set (nil = none of ours)
local setAt = 0 -- os.clock() when we last set it
local retried = false -- already put back a route that got wiped right after we set it
local pending -- GPS place name waiting for a position (the vent streams in a moment later)
local lastSeenAt = 0 -- os.clock() guess of when the cops last saw us
local lastHeat = 0
local blink = false
local ventPart, ventSearchAt = nil, 0
local placesRaw, placesList = nil, {}

local function places()
	local raw = ReplicatedStorage:GetAttribute("Places")
	if raw ~= placesRaw then
		placesRaw = raw
		local ok, list = pcall(function()
			return HttpService:JSONDecode(raw or "[]")
		end)
		placesList = (ok and type(list) == "table") and list or {}
	end
	return placesList
end

local function myPos()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- The nearest place with this name from MapService's list (works even when it isn't streamed in).
local function placePos(name)
	local here = myPos()
	local best, bestD
	for _, p in ipairs(places()) do
		local x, z = tonumber(p.x), tonumber(p.z)
		if p.n == name and x and z then
			local pos = Vector3.new(x, 0, z)
			local d = here and flatDistance(pos, here) or 0
			if not bestD or d < bestD then
				best, bestD = pos, d
			end
		end
	end
	return best
end

-- The breakout vent (Workspace.City.Landmarks.PrisonVent), once it's streamed in.
local function ventPos()
	if ventPart and ventPart.Parent then
		return ventPart.Position
	end
	ventPart = nil
	if os.clock() < ventSearchAt then
		return nil
	end
	ventSearchAt = os.clock() + 2 -- the deep search below isn't free: at most every 2 s
	local city = Workspace:FindFirstChild("City")
	local landmarks = city and city:FindFirstChild("Landmarks")
	local found = landmarks and landmarks:FindFirstChild("PrisonVent")
	if not found and city then
		found = city:FindFirstChild("PrisonVent", true)
	end
	if found and found:IsA("BasePart") then
		ventPart = found
		return found.Position
	end
	return nil
end

local function gpsPos(name)
	if name == VENT_NAME then
		return ventPos()
	end
	return placePos(name)
end

local function setGps(name, pos)
	GPSClient.SetTarget(name, pos)
	mine = name
	setAt = os.clock()
end

-- Clear the GPS only if the target on it is still the one we set.
local function clearMine()
	if mine and GPSClient.Target() == mine then
		GPSClient.Clear()
	end
	mine = nil
end

function ObjectiveClient.RouteTo(name)
	local pos = gpsPos(name)
	if not pos then
		return false
	end
	local here = myPos()
	if here and flatDistance(pos, here) < GPS_SKIP then
		return false -- already there
	end
	return (pcall(setGps, name, pos))
end

function ObjectiveClient.Active()
	return active
end

local function isMyHotCar(car)
	return car ~= nil and car:GetAttribute("HotCar") == true and car:GetAttribute("ThiefUserId") == player.UserId
end

-- "driving" at the wheel of our stolen hot car, "jacked" at the wheel of a car we jacked (CarjackService
-- marks it Jacked), "nearby" when our hot car is parked close by, else nil.
local function hotCarState()
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local car = seat and seat.Parent
	if seat and seat.Name == "DriverSeat" and isMyHotCar(car) then
		return car:GetAttribute("Jacked") == true and "jacked" or "driving", car
	end
	if player:GetAttribute("BoostDelivery") ~= true then
		return nil
	end
	local here = myPos()
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not here or not vehicles then
		return nil
	end
	for _, c in ipairs(vehicles:GetChildren()) do
		if isMyHotCar(c) and c:GetAttribute("Jacked") ~= true and c.PrimaryPart
			and flatDistance(c.PrimaryPart.Position, here) < HOT_CAR_NEAR then
			return "nearby", c
		end
	end
	return nil
end

-- On the Big Score's roster, out of prison: BigScoreClient's strip has the Goal zone.
local function bigScore()
	return player:GetAttribute("BigScore") ~= nil and player:GetAttribute("Side") ~= "Prisoner"
end

-- Races, job shifts, missions and the Big Score have their own banners.
local function busy()
	return player:GetAttribute("RacingId") ~= nil or player:GetAttribute("JobKind") ~= nil
		or player:GetAttribute("Mission") ~= nil or bigScore()
end

local function colorText(color, text)
	return string.format('<font color="#%s">%s</font>', color:ToHex(), text)
end

-- A small tag in the condensed Display face, inside rich text.
local function tagText(color, text)
	return string.format('<font face="Oswald" weight="bold" size="%d" color="#%s">%s</font>', tagSize,
		color:ToHex(), text)
end

local function clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Guess when the cops last saw us, for the "stay hidden" countdown when HeatService hasn't published
-- EscapeAt (it drops the heat 30 + 10 x stars seconds after the last sighting).
local function trackSightings()
	local heat = player:GetAttribute("Heat") or 0
	if heat <= 0 then
		lastHeat = 0
		return
	end
	if player:GetAttribute("HeatSpotted") == true or heat > lastHeat then
		lastSeenAt = os.clock() -- seen right now, or a new crime was just reported
	end
	lastHeat = heat
end

-- What should the player do right now? nil = nothing to say.
-- Fields: key, tag, color (the tag and the strip's colour bar), title (rich text), detail (rich text,
-- the dim second line), escape ({ word, value, color } for the escape line, wanted only), gps (place
-- to route to), keep (set of our GPS targets worth keeping while this shows), flash.
local function compute()
	if busy() then
		return nil
	end
	local side = player:GetAttribute("Side")
	if side == "Prisoner" then
		return {
			key = "prison", tag = "PRISON", color = C.Orange,
			title = "Find the vent in the yard",
			detail = "Pry it open, swim off. Or wait it out.",
			gps = VENT_NAME,
		}
	end
	if side ~= "Civilian" then
		return nil
	end
	local heat = player:GetAttribute("Heat") or 0
	local carried = player:GetAttribute("Carried") or 0
	local hot, car = hotCarState()
	if heat > 0 then
		local spotted = player:GetAttribute("HeatSpotted") == true
		-- (a jacked car is a joyride first: no "then the Chop Shop" push for it)
		local nextStep = (carried > 0 and "Then bank your bag at the Hideout")
			or ((hot == "driving" or hot == "nearby") and "Then take the hot car to the Chop Shop")
			or "Get out of sight and stay there"
		local line
		local eta = player:GetAttribute("PoliceETA")
		local t = Workspace:GetServerTimeNow()
		if spotted then
			line = { word = "SEEN", value = "BREAK LINE OF SIGHT", color = C.Danger }
		elseif typeof(eta) == "number" and eta > t then
			line = { word = "PATROLS ARRIVE IN", value = clock(eta - t), color = C.Police }
		else
			local escapeAt = player:GetAttribute("EscapeAt") -- HeatService's exact escape time (server time)
			local exact = typeof(escapeAt) == "number"
			local left = exact and (escapeAt - t) or (lastSeenAt + 30 + 10 * math.floor(heat) - os.clock())
			line = { word = "STAY HIDDEN", value = left > 1 and ((exact and "" or "ABOUT ") .. clock(left)) or nil,
				color = C.Dim }
		end
		return {
			key = "wanted", tag = "WANTED", color = spotted and C.Danger or C.Text, flash = spotted,
			title = "Lose the cops",
			detail = nextStep,
			escape = line,
			keep = { [HIDEOUT] = true, [CHOP_SHOP] = true },
		}
	end
	-- A jacked car the Chop Shop won't buy (taken right by it) never suggests selling it.
	local sellable = hot == "jacked" and car:GetAttribute("JackSellable") ~= false
	if carried > 0 then
		return {
			key = "bank", tag = "BAG", color = C.Gold,
			title = "Bank " .. colorText(C.Gold, HUDController.Money(carried)) .. " at the Hideout",
			detail = (hot == "driving" and "Or deliver the hot car first.")
				or (sellable and "Or sell this car at the Chop Shop.")
				or "Follow the GPS to the Hideout pad.",
			gps = HIDEOUT,
		}
	end
	if hot == "jacked" and not sellable then
		return {
			key = "joyride", tag = "JACKED", color = C.Gold,
			title = "Joyride",
			detail = "Too close to the Chop Shop to sell.",
		}
	elseif hot == "jacked" then
		local value = car:GetAttribute("HotValue")
		return {
			key = "jacked", tag = "JACKED", color = C.Gold,
			title = "Joyride, or sell it",
			detail = type(value) == "number"
				and ("Chop Shop at the Docks pays " .. colorText(C.Gold, HUDController.Money(value)))
				or "The Chop Shop is at the Docks.",
			keep = { [CHOP_SHOP] = true },
		}
	end
	if hot == "driving" then
		local value = car:GetAttribute("HotValue")
		return {
			key = "boost", tag = "HOT CAR", color = C.Gold,
			title = "Take it to the Chop Shop",
			detail = (type(value) == "number" and ("Worth " .. colorText(C.Gold, HUDController.Money(value)) .. ". ") or "")
				.. "Lose any cops first.",
			gps = CHOP_SHOP,
		}
	elseif hot == "nearby" then
		return {
			key = "boostCar", tag = "HOT CAR", color = C.Gold,
			title = "Get back in your hot car",
			detail = "Then drive it to the Chop Shop.",
			keep = { [CHOP_SHOP] = true },
		}
	end
	return nil
end

local function textLabel(parent, name, kind)
	local l = Instance.new("TextLabel")
	l.Name = name
	Theme.Text(l, 14, kind)
	l.RichText = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = parent
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Objective"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- the zone map's coordinates (y = 0 is the very top of the screen)
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The strip (Goal zone): flat dark panel, colour bar, tag + words, dim second line.
	banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Visible = false
	Theme.Panel(banner)
	banner.Parent = gui

	accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Position = UDim2.fromOffset(ACCENT_X, 7)
	accent.Size = UDim2.new(0, ACCENT_W, 1, -14)
	accent.BackgroundColor3 = C.Text
	accent.BorderSizePixel = 0
	accent.Parent = banner
	Theme.Corners(accent, 1)

	titleLabel = textLabel(banner, "Title", "Bold")
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	detailLabel = textLabel(banner, "Detail", "Body")
	detailLabel.TextColor3 = C.Dim
	detailLabel.TextTruncate = Enum.TextTruncate.AtEnd
	detailLabel.AnchorPoint = Vector2.new(0, 1)

	-- The escape line (Banner zone): words straight on the screen, centred, a small word and a big value.
	escape = Instance.new("Frame")
	escape.Name = "Escape"
	escape.BackgroundTransparency = 1
	escape.Visible = false
	escape.Parent = gui
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 10)
	row.Parent = escape
	escWord = textLabel(escape, "Word", "Bold")
	escWord.LayoutOrder = 1
	escValue = textLabel(escape, "Value", "Display")
	escValue.LayoutOrder = 2
	for _, l in ipairs({ escWord, escValue }) do
		l.RichText = false
		l.AutomaticSize = Enum.AutomaticSize.X
		l.Size = UDim2.new(0, 0, 1, 0)
	end
end

-- Put both pieces in their zones and size the words for this screen (phones get the smaller layout).
local function place()
	local touch = Theme.IsTouch()
	Theme.Place(banner, "Goal", touch)
	Theme.Place(escape, "Banner", touch)
	local titleSize, detailSize = touch and 14 or 15, 13
	tagSize = titleSize + 2 -- Oswald is condensed: a size up reads as the same height
	titleLabel.TextSize = titleSize
	titleLabel.Position = UDim2.fromOffset(TEXT_X, touch and 3 or 5)
	titleLabel.Size = UDim2.new(1, -(TEXT_X + 10), 0, titleSize + 4)
	detailLabel.TextSize = detailSize
	detailLabel.Position = UDim2.new(0, TEXT_X, 1, touch and -3 or -5)
	detailLabel.Size = UDim2.new(1, -(TEXT_X + 10), 0, detailSize + 3)
	escWord.TextSize = touch and 13 or 14
	escValue.TextSize = touch and 20 or 24
end

local function render(obj)
	local color = obj.color
	if obj.flash then
		blink = not blink
		color = blink and C.Text or obj.color
	end
	titleLabel.Text = tagText(color, obj.tag) .. "   " .. obj.title
	detailLabel.Text = obj.detail or ""
	accent.BackgroundColor3 = color
	local line = obj.escape
	if line then
		escWord.Text = line.word
		escWord.TextColor3 = line.color
		-- The big value carries the meaning too: red to break the line of sight, police blue for the
		-- patrols' head start; the plain "stay hidden" countdown is white beside its dim word.
		escValue.Text = line.value or ""
		escValue.TextColor3 = line.color == C.Dim and C.Text or line.color
		escValue.Visible = line.value ~= nil
	end
end

-- A new objective (or none): drop the old objective's route unless the new one wants or keeps it,
-- and queue the new one's route.
local function startObjective(obj)
	pending = nil
	retried = false
	local want = obj and obj.gps
	local keep = obj and obj.keep
	if mine and mine ~= want and not (keep and keep[mine]) then
		clearMine()
	end
	if want then
		pending = want
	end
end

local function tryPending()
	if not pending then
		return
	end
	local pos = gpsPos(pending)
	if not pos then
		return -- position not known yet (not streamed in): try again next update
	end
	local here = myPos()
	if here and flatDistance(pos, here) < GPS_SKIP then
		pending = nil
		return -- already there
	end
	-- Only drop the pending route once it's really set (if GPSClient hasn't built its pillar yet the
	-- call errors, and we try again next update instead of losing the route).
	if pcall(setGps, pending, pos) then
		pending = nil
	end
end

-- Would a stamp starting at y = stampTop draw over this piece? (Stamps sit in the upper middle.)
-- StampTop is in zone coordinates (y = 0 at the very top of the screen), but AbsolutePosition starts
-- under the top bar whatever IgnoreGuiInset says, so the piece is measured from our ScreenGui's corner
-- (right whichever way Roblox counts it, as MinimapClient and SoundClient do).
local function covered(frame, stampTop)
	if stampTop == nil then
		return false
	end
	local top = frame.AbsolutePosition.Y - gui.AbsolutePosition.Y
	return stampTop < top + frame.AbsoluteSize.Y
end

local function update()
	trackSightings()
	local obj = compute()
	if (obj and obj.key) ~= (current and current.key) then
		startObjective(obj)
	end
	current = obj
	-- GPSClient clears the route when your side changes (e.g. going to prison). If that wiped the
	-- route we set a moment ago, put it back once.
	if mine and obj and obj.gps == mine and not retried and GPSClient.Target() == nil and os.clock() - setAt < 1.5 then
		retried = true
		pending = mine
	end
	tryPending()
	if obj then
		render(obj)
	end
	local nowActive = obj ~= nil
	-- Off on the title screen; stepped aside while a big stamp ("+$900 in your bag", "HOT CAR STOLEN")
	-- draws over it. `active` stays true meanwhile, so the tutorial's goal stays hidden too.
	local shown = nowActive and player:GetAttribute("TitleScreen") ~= true
	local stampTop = HUDController.StampTop and HUDController.StampTop()
	local stripOn = shown and not covered(banner, stampTop)
	local escapeOn = shown and obj.escape ~= nil and not covered(escape, stampTop)
	if banner.Visible ~= stripOn then
		banner.Visible = stripOn
	end
	if escape.Visible ~= escapeOn then
		escape.Visible = escapeOn
	end
	-- The Big Score's strip counts too (our own strip stays hidden: compute() said nothing above).
	nowActive = nowActive or bigScore()
	if nowActive ~= active then
		active = nowActive
		changed:Fire(active)
	end
end

function ObjectiveClient.Init()
	build()
	place()
	-- Re-place when the screen changes size or the device's input changes (a mouse plugged into a tablet).
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	UserInputService:GetPropertyChangedSignal("MouseEnabled"):Connect(place)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(place)
	-- Stars go hollow 8 s after the last sighting, so that's when they last saw us.
	player:GetAttributeChangedSignal("HeatSpotted"):Connect(function()
		if player:GetAttribute("HeatSpotted") ~= true then
			lastSeenAt = os.clock() - HOLLOW_AFTER
		end
	end)
	-- Just stole a hot car: say where it goes and route there right away.
	player:GetAttributeChangedSignal("BoostStolenAt"):Connect(function()
		if player:GetAttribute("BoostStolenAt") ~= nil and player:GetAttribute("Side") == "Civilian" then
			local routed = ObjectiveClient.RouteTo(CHOP_SHOP)
			HUDController.Stamp("HOT CAR STOLEN", "Take it to the Chop Shop at the Docks" .. (routed and " (GPS set)" or ""), C.Gold)
		end
	end)
	-- Just jacked a car: stamp it, and suggest the Chop Shop on the GPS, but never over a target the player
	-- picked (then theirs stays), never over the route of the objective on screen (the Hideout for a bag,
	-- the vent...), never with cash in the bag, and not for a car the Chop Shop won't buy.
	Remotes.OnClient("Carjacked", function(info)
		if type(info) ~= "table" then
			return
		end
		local title = info.Alarm and "CAR ALARM" or "CAR JACKED"
		local color = info.Alarm and C.Danger or C.Text
		if info.Sellable == false then
			HUDController.Stamp(title, "Joyride: too close to the Chop Shop to sell it", color)
			return
		end
		local value = tonumber(info.Value)
		local sell = "sell it at the Chop Shop" .. (value and (" for " .. HUDController.Money(value)) or "")
		local gpsTarget = GPSClient.Target()
		local free = (gpsTarget == nil or gpsTarget == mine) and not (current and current.gps)
			and (player:GetAttribute("Carried") or 0) <= 0
		local routed = free and ObjectiveClient.RouteTo(CHOP_SHOP)
		HUDController.Stamp(title, "Joyride, or " .. sell .. (routed and " (GPS set)" or ""), color)
	end)
	task.spawn(function()
		while true do
			-- Wait first: the first update then runs after every controller's Init (GPS included).
			task.wait(UPDATE_EVERY)
			local ok, err = pcall(update)
			if not ok then
				warn("[ObjectiveClient] " .. tostring(err))
			end
		end
	end)
end

return ObjectiveClient
