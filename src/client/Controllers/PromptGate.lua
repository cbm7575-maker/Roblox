-- PromptGate (ModuleScript, StarterPlayerScripts.Controllers.PromptGate)
-- Nothing you can't do from a car is offered while you sit in one. While the local character sits in ANY
-- seat (driver, passenger, a couch), every ProximityPrompt that only works on foot doesn't show at all
-- (no "hold E" on a store's Rob prompt from the driver's seat), and comes back the moment they stand up.
--   * How: the prompt's MaxActivationDistance is set to 0 on this device and its real value is put back on
--     standing up. Enabled is never touched: other controllers (HeistClient, LawClient, VehicleVisuals,
--     InteractClient) and the server already switch that one, and a server change would replace ours.
--     Hidden this way a prompt goes "out of range", so ProximityPromptService.PromptHidden still fires
--     for it (DriveController and InteractClient keep track of what's on screen from that).
--   * Which: everything, except the in-car list below (IN_CAR, by prompt Name), EventService's prompts
--     (unnamed, in Workspace.Events; but not the beach treasure's "Dig", which is on foot) and any prompt
--     with the attribute "InCar" = true (a server script can set it on a new prompt; a controller calls
--     PromptGate.Allow(prompt)). A new prompt is on-foot only until someone says otherwise.
--   * Prompts are found as they stream in (Workspace.DescendantAdded) and hidden before they can show;
--     PromptShown is the safety net. Four times a second the seat is read again and, while seated, any
--     hidden prompt whose distance the server changed is re-read and hidden again.
--   * Never left behind: a prompt that leaves Workspace (destroyed, streamed out) gets its distance back
--     and is forgotten; a respawn (the old character going, the new one arriving) puts everything back,
--     and on foot nothing is ever kept hidden. A prompt only gets the remembered distance back while it
--     is still at our 0: any other value came from the server after we hid it, so that one is kept.
--   * The other way round (Race / taxi / courier prompts on foot) is left alone on purpose: the server
--     answers with a toast that says to bring your car, which is how new players learn it.
--   * A hidden prompt says nothing, so InteractClient shows a hint next to EXIT instead: "Get out to rob"
--     within 25 studs of a Rob point or prep panel you could use (HeistClient.NearestRob: from the street
--     that's mostly an ATM kiosk's plaza, since store tills sit 22+ studs inside), and "Get out first"
--     next to a car you could take (its own car search) or, once you've driven up to it, next to any
--     other bubble held back here (PromptGate.NearestHidden: a display car, a front door, a dropped bag).
--   * MaxActivationDistance on this device is ours alone: a controller that wants a bubble gone for good
--     (InteractClient: your own car's "Drive", since GET IN walks you to the door) asks PromptGate.Hold,
--     or standing up would hand that bubble its reach back for a moment.
--   PromptGate.Seated()            is the gate up right now (the character sits in a seat)?
--   PromptGate.IsHidden(prompt)    is this prompt being held at 0 right now?
--   PromptGate.Allow(prompt)       this prompt works from a seat: never hide it (shown again at once)
--   PromptGate.Hold(prompt)        this bubble never shows on this device, seated or on foot: its reach
--                                  is 0 from now on, and there is nothing to put back on standing up
--   PromptGate.NearestHidden(pos, except, notUnder)
--                                  studs from pos to the nearest prompt held back here whose bubble would
--                                  be up from there on foot (switched on, within its own reach), or nil.
--                                  except (optional): prompt Names to leave out, [name] = true.
--                                  notUnder (optional): an instance whose own prompts don't count (the
--                                  car you sit in).

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local PromptGate = {}

-- Prompts that work from a seat, by Name. Checked against each prompt's server handler: it's on this list
-- only if that handler takes a seated player. Everything else is on-foot only:
--   RobPrompt (HeistService refuses a seated robber), PrepPrompt (step 1 of the same robbery),
--   PickLockPrompt (hot cars and parked cars' Break in: CarBoostService / CarjackService answer
--   "GetOutFirst"), DrivePrompt (it would seat you a second time), RidePrompt (VehicleService:
--   "GetOutFirst"), BagGrab (CombatService: "CombatInCar"), DealerView (DealerClient: "Hop out to take a
--   closer look"), VentPrompt (prisoners have no cars), GunShopBrowse (the gun shop counter: you walk up
--   to it, and CombatClient won't open the shop for someone seated), HomeDoor (HousingService would take a
--   seated player, but you walk in through a door; and while it showed from the driver's seat, E at your
--   own front door, where you spawn and call your car, went into the house instead of getting you out),
--   LikePrompt (CarMeetService would count a like from a seat, but the meet's own flow is "park on a show
--   bay and step out", and from the seat at a bay the neighbours' Like bubbles are in reach: E, which gets
--   you out when no prompt is up, sent the next car a like instead).
local IN_CAR = {
	RacePrompt = true, -- RaceService: a race starts IN your own car on the start pad
	TaxiPrompt = true, -- JobService: a taxi shift starts in your own car on the stand
	CourierPrompt = true, -- JobService: same, at the Courier Depot
	CuffPrompt = true, -- ArrestService: a cop can cuff from the seat (only range and the suspect's speed count)
	CuffDriver = true, -- ArrestService: same, on a wanted driver who has stopped
	-- Inside your home the only seat is the couch, and none of these three reaches it today (the exit door
	-- is ~35 studs away, the wardrobe ~23, the garage further). Listed because their handlers unseat you
	-- first, so a seat added near one later doesn't hide it for no reason.
	LeavePrompt = true, -- HousingService: leaving unseats you
	WardrobePrompt = true, -- HousingService / WardrobeUI: client only, opens the dressing room
	DriveThis = true, -- HousingService: unseats you, then puts you in that car on the driveway
}
local ALLOW_ATTRIBUTE = "InCar"
local EVENTS_FOLDER = "Events" -- EventService: shoo the gator, wave at the UFO (range and travel time only)
-- ...except digging up the beach treasure: the server would take it from a seat too, but "hold E to dig"
-- from behind the wheel is exactly the kind of bubble the gate is for. Its prompt sits on a part of this
-- name (EventService names the part; the prompt itself has the default name).
local EVENT_ON_FOOT = "Treasure"
local RECHECK = 0.25 -- seconds between safety checks

local known = {} -- [prompt] = true: every ProximityPrompt in Workspace on this device right now
local hidden = {} -- [prompt] = its real MaxActivationDistance, while we hold it at 0
local seated = false
local started = false
local charConns = {}
local eventsFolder = nil

local function inCar(prompt)
	if IN_CAR[prompt.Name] or prompt:GetAttribute(ALLOW_ATTRIBUTE) == true then
		return true
	end
	local events = eventsFolder
	if not events or events.Parent ~= Workspace then
		events = Workspace:FindFirstChild(EVENTS_FOLDER)
		eventsFolder = events
	end
	if events == nil or not prompt:IsDescendantOf(events) then
		return false
	end
	local parent = prompt.Parent
	return not (parent and parent.Name == EVENT_ON_FOOT)
end

local function setDistance(prompt, distance)
	prompt.MaxActivationDistance = distance
end

local function getDistance(prompt)
	return prompt.MaxActivationDistance
end

-- Hold an on-foot prompt at 0. Its real distance is remembered the first time, and again whenever it
-- isn't 0 any more (the server changed it, and its value replaced ours).
local function gate(prompt)
	if inCar(prompt) then
		return
	end
	local distance = prompt.MaxActivationDistance
	if hidden[prompt] == nil or distance ~= 0 then
		hidden[prompt] = distance
	end
	if distance ~= 0 then
		prompt.MaxActivationDistance = 0
	end
end

-- Give a prompt its real distance back. (pcall: one that is on its way out must never stop the rest.)
-- Only while it's still at our 0: any other value is one the server set after we hid it (its change
-- replaced ours, and the next recheck hadn't come round yet), and writing the remembered one over it
-- would leave this device with a different reach from the server and everybody else.
local function release(prompt)
	local distance = hidden[prompt]
	if distance == nil then
		return
	end
	hidden[prompt] = nil
	local ok, current = pcall(getDistance, prompt)
	if ok and current == 0 then
		pcall(setDistance, prompt, distance)
	end
end

local function setSeated(now)
	if now == seated then
		return
	end
	seated = now
	if now then
		for prompt in pairs(known) do
			if prompt:IsDescendantOf(Workspace) then
				pcall(gate, prompt)
			else
				known[prompt] = nil -- (DescendantRemoving drops these: belt and braces)
			end
		end
	else
		for prompt in pairs(hidden) do
			release(prompt)
		end
	end
end

-- Sitting, alive, in any kind of seat.
local function readSeated()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and hum.SeatPart ~= nil
end

local function sync()
	setSeated(readSeated())
end

local function onAdded(inst)
	if not inst:IsA("ProximityPrompt") then
		return
	end
	known[inst] = true
	if seated then
		gate(inst) -- streamed in while we sit: hidden before it can show
	end
end

local function onRemoving(inst)
	if known[inst] then
		known[inst] = nil
		release(inst) -- if it ever comes back, it comes back with its real distance
	end
end

-- Four times a second: the seat (in case a change was missed), and while seated every hidden prompt
-- (the server may have changed its distance, which shows it again).
local function recheck()
	sync()
	if seated then
		for prompt in pairs(hidden) do
			local distance = prompt.MaxActivationDistance
			if distance ~= 0 then
				hidden[prompt] = distance
				prompt.MaxActivationDistance = 0
			end
		end
	elseif next(hidden) ~= nil then
		for prompt in pairs(hidden) do
			release(prompt) -- on foot nothing stays hidden, whatever happened
		end
	end
end

local function watchCharacter(char)
	for _, conn in ipairs(charConns) do
		conn:Disconnect()
	end
	table.clear(charConns)
	setSeated(false) -- a new character starts on its feet: everything back
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum or player.Character ~= char then
		return
	end
	table.insert(charConns, hum:GetPropertyChangedSignal("SeatPart"):Connect(sync))
	table.insert(charConns, hum.Died:Connect(sync))
	sync()
end

function PromptGate.Seated()
	return seated
end

function PromptGate.IsHidden(prompt)
	return hidden[prompt] ~= nil
end

-- Studs from `pos` to the nearest prompt we're holding back whose bubble would be up from there on foot:
-- switched on (Enabled is other code's say: a prompt that's off for this player is no reason to get
-- out) and within its own real reach. nil when there is none. InteractClient turns this into its "Get
-- out first" hint, so a hidden bubble never leaves you guessing. except: prompt Names to leave out
-- ([name] = true). notUnder: an instance whose own prompts don't count (the car we sit in).
function PromptGate.NearestHidden(pos, except, notUnder)
	if not ProximityPromptService.Enabled then
		return nil -- every bubble is off (the dressing room does that): nothing would show on foot either
	end
	local best
	for prompt, reach in pairs(hidden) do
		if prompt.Enabled and not (except and except[prompt.Name]) then
			local parent = prompt.Parent
			local at
			if parent then
				if parent:IsA("Attachment") then
					at = parent.WorldPosition
				elseif parent:IsA("BasePart") then
					at = parent.Position
				end
			end
			if at then
				local d = (at - pos).Magnitude
				if d <= reach and (best == nil or d < best) and not (notUnder and prompt:IsDescendantOf(notUnder)) then
					best = d
				end
			end
		end
	end
	return best
end

-- For a prompt that isn't on the list above but does work from a seat. Marked with an attribute on this
-- device, so nothing is kept here; a prompt that streams out and back in is a new one (call again).
function PromptGate.Allow(prompt)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then
		return
	end
	prompt:SetAttribute(ALLOW_ATTRIBUTE, true)
	release(prompt)
end

-- For a bubble another controller never wants on this device, seated or on foot (InteractClient: your
-- own car's "Drive"). Its reach is 0 from now on. If we're holding it back ourselves right now, 0 is also
-- what it gets "back" when we stand up: otherwise it would show at its old reach for a moment, until that
-- controller's next look. Cheap to call again and again (it only writes when something has to change).
function PromptGate.Hold(prompt)
	if typeof(prompt) ~= "Instance" or not prompt:IsA("ProximityPrompt") then
		return
	end
	if hidden[prompt] ~= nil then
		hidden[prompt] = 0
	end
	if prompt.MaxActivationDistance ~= 0 then
		prompt.MaxActivationDistance = 0
	end
end

function PromptGate.Init()
	if started then
		return
	end
	started = true
	-- Listen first, then look: nothing that arrives in between is missed.
	Workspace.DescendantAdded:Connect(onAdded)
	Workspace.DescendantRemoving:Connect(onRemoving)
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("ProximityPrompt") then
			known[inst] = true
		end
	end
	-- Safety net: a prompt that shows while we sit although it shouldn't is hidden on the spot.
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if not known[prompt] and prompt:IsDescendantOf(Workspace) then
			known[prompt] = true
		end
		if seated then
			gate(prompt)
		end
	end)

	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(function()
		setSeated(false)
	end)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end

	task.spawn(function()
		local lastWarn = 0
		while true do
			task.wait(RECHECK)
			local ok, err = pcall(recheck)
			if not ok and os.clock() - lastWarn > 5 then
				lastWarn = os.clock()
				warn("[PromptGate] " .. tostring(err))
			end
		end
	end)
end

return PromptGate
