-- LawClient (ModuleScript, StarterPlayerScripts.Controllers.LawClient)
-- Client side of the wanted system, police tools and prison (flat "street" look, Shared.Util.Theme):
--   * Which prompts you see: Cuff (cops, on wanted players and wanted drivers), Vent (prisoners), Pick lock
--     (citizens on foot, on hot cars nobody has stolen yet; seated, InteractClient's "Get out first" hint
--     shows instead). Never the car meet's Like on your own show car (it's for everyone else).
--   * Cops: TASER (T) and SPIKES (G) tiles, flat dark squares with a small drawn glyph, a Display label
--     and, on a keyboard, the key cap on their left (no gamepad button is bound to them, so no cap
--     there). SPIKES shows its charges top-right (red at 0). TASER only shows on foot.
--   * Markers for wanted players at their LastSeen spot: a WANTED / LAST SEEN tag with white stars and
--     the suspect's clues, and a faint red search circle (150 + 50 per star) while their stars are hollow.
--   * Taser zap beams, and the stamps: CUFFED (with a mugshot headline), BOUNTY +$X (or ARRESTED when
--     the stars carried no bounty), BREAKOUT.
--   * Prisoners: the release countdown in the Banner zone (Theme.Zone), with the breakout hint under it.
-- While the first-join title screen is up (player attribute TitleScreen) none of it shows. WardrobeUI
-- switches the whole "LawUI" ScreenGui off while its dressing room is open; T and G do nothing then.
-- THE SIDE COLUMN: situational buttons live under the Buttons zone, right-aligned with it, never in a
-- zone. Slots from the top: LEAVE HOME (HouseClient, inside your home), WARDROBE (WardrobeUI, inside
-- your home or a hideout), then TASER and SPIKES. PC / gamepad: 52 px squares, one per row, wrapping
-- into another column to the left before the Corner zone. Phone: 52 x 44 tiles in one column at the
-- right edge (clear of CombatClient's FIRE / AIM cluster), starting under InteractClient's seated "Get
-- out first" hint while it hangs under EXIT there, and stopping above Roblox's jump button / the drive
-- pedals (measured; with neither showing, where Roblox puts the jump button). Tiles that don't fit
-- (always while driving) go in a row left of the Buttons zone, at its height, skipping any spot that
-- would cover the Action, Minimap or Vitals zones or a piece showing there (CombatClient's touch gun
-- buttons and ammo counter, the pedals, the hint). Re-placed every update (screen size, input, pedals).
--   LawClient.SideSlot(screenGui, index, touch) -> position, size (Vector2 pixels from the top-left of
--     that IgnoreGuiInset ScreenGui) of slot `index` (0 = top). HouseClient and WardrobeUI use it too.
--   LawClient.PlaceSlots() -> how many slots LEAVE HOME and WARDROBE hold right now (from attributes).
-- The server checks every action; this file only shows things and asks.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local LawClient = {}

local C = Theme.Color
local TASER_RANGE = 32
-- Side column tiles (see the header).
local TILE_PC = 52 -- as wide as the Buttons zone
local GAP_PC = 8
local TILE_TOUCH_W, TILE_TOUCH_H = 52, Theme.Touch
local GAP_TOUCH_X, GAP_TOUCH_Y = 8, 6
-- No jump button or pedals showing on a phone: stop where Roblox puts the jump button's top (pixels off
-- the bottom edge; 70 px button on phones, 120 px on tablets, as CombatClient's jumpRect), so the tiles
-- don't hop between the column and the row whenever it comes and goes.
local JUMP_TOP_SMALL, JUMP_TOP_BIG = 90, 210

-- Kid-safe "Florida Man" headlines for the mugshot stamp.
local HEADLINES = {
	"Local Legend Arrested for Stealing 400 Rubber Ducks",
	"Suspect Claims a Gator 'Made Them Do It'",
	"Beach Bandit Nabbed Mid-Sunburn",
	"Driver Pulled Over for Excessive Neon",
	"Getaway Foiled by Flip-Flop Malfunction",
	"Robber Caught Paying for Snacks With Stolen Cash",
	"Man Tries to Outrun Police on a Pool Noodle",
	"Suspect Blames Flamingo for Wrong Turn",
}

local gui, taserButton, spikeButton, spikeCount, prisonLabel
local keyCaps = {} -- the T and G caps beside the tiles
local markers = {} -- [player] = { beacon = Part, label, clues, circle = Part }
local markerFolder

local function now()
	return Workspace:GetServerTimeNow()
end

local function side()
	return player:GetAttribute("Side")
end

local function isWanted(p)
	return p:GetAttribute("Side") == "Civilian" and (p:GetAttribute("Heat") or 0) > 0
end

local function myRoot()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return char and char:FindFirstChild("HumanoidRootPart"), hum
end

-- Key caps only for a keyboard (no gamepad button is bound to the cop tools; touch has no keys).
local function keyboardMode()
	if Theme.IsTouch() then
		return false
	end
	local name = UserInputService:GetLastInputType().Name
	return string.sub(name, 1, 7) ~= "Gamepad" and name ~= "Touch"
end

------------------------------------------------------------------ the side column

-- Is this GuiObject on screen: it and every GuiObject above it visible, inside an enabled ScreenGui?
local function shown(obj)
	local o = obj
	while o and not o:IsA("LayerCollector") do
		if o:IsA("GuiObject") and not o.Visible then
			return false
		end
		o = o.Parent
	end
	return o ~= nil and o:IsA("ScreenGui") and o.Enabled
end

-- A zone's rectangle on a w x h screen: x, y, width, height in pixels.
local function zoneRect(name, touch, w, h)
	local z = Theme.Zone(name, touch)
	local zw = z.Size.X.Scale * w + z.Size.X.Offset
	local zh = z.Size.Y.Scale * h + z.Size.Y.Offset
	return z.Pos.X.Scale * w + z.Pos.X.Offset - z.Anchor.X * zw, z.Pos.Y.Scale * h + z.Pos.Y.Offset - z.Anchor.Y * zh, zw, zh
end

-- Something under PlayerGui by path (guiAt("Interact", "GetOutHint")); nil if any part is missing.
local function guiAt(...)
	local o = player:FindFirstChildOfClass("PlayerGui")
	for _, name in ipairs({ ... }) do
		o = o and o:FindFirstChild(name)
	end
	return o
end

-- A GuiObject's box { x, y, w, h } in `screen`'s pixels while it's on screen; nil otherwise.
-- (AbsolutePosition doesn't start at the very top of the screen, so measure from screen's own corner.)
local function boxOf(screen, obj)
	if not obj or not obj:IsA("GuiObject") or not shown(obj) then
		return nil
	end
	local p, s = obj.AbsolutePosition - screen.AbsolutePosition, obj.AbsoluteSize
	return { p.X, p.Y, s.X, s.Y }
end

local function overlaps(x, y, w, h, r)
	return x < r[1] + r[3] and x + w > r[1] and y < r[2] + r[4] and y + h > r[2]
end

-- Phones: what the overflow row left of the Buttons zone must not cover. The Action, Minimap and Vitals
-- zones (by the zone map, showing or not), and what's showing there right now: CombatClient's touch gun
-- buttons and ammo counter, the pedals (DriveUI.Touch's buttons) and the seated "Get out first" hint.
local function rowBlockers(screen, w, h)
	local list = {}
	local function add(r)
		if r then
			table.insert(list, r)
		end
	end
	for _, name in ipairs({ "Action", "Minimap", "Vitals" }) do
		add({ zoneRect(name, true, w, h) })
	end
	local combat = guiAt("CombatHUD")
	for _, name in ipairs({ "Ammo", "Fire", "Aim", "Reload", "Weapon" }) do
		add(boxOf(screen, combat and combat:FindFirstChild(name)))
	end
	local pedals = guiAt("DriveUI", "Touch")
	if pedals then
		for _, b in ipairs(pedals:GetChildren()) do
			add(boxOf(screen, b))
		end
	end
	add(boxOf(screen, guiAt("Interact", "GetOutHint")))
	return list
end

-- Phones: the highest top edge (pixels in `screen`'s space) of Roblox's jump button or DriveUI's pedal
-- block that overlaps x0..x1 and reaches below y `below`; math.huge if neither is showing there.
local function obstacleTop(screen, x0, x1, below)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return math.huge
	end
	local list = {}
	local touchGui = pg:FindFirstChild("TouchGui")
	local frame = touchGui and touchGui:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	if jump then
		table.insert(list, jump)
	end
	local drive = pg:FindFirstChild("DriveUI")
	local pedals = drive and drive:FindFirstChild("Touch")
	if pedals then
		table.insert(list, pedals)
	end
	local best = math.huge
	for _, obj in ipairs(list) do
		if obj:IsA("GuiObject") and shown(obj) then
			local p = obj.AbsolutePosition - screen.AbsolutePosition
			local s = obj.AbsoluteSize
			if p.X < x1 and p.X + s.X > x0 and p.Y + s.Y > below then
				best = math.min(best, p.Y)
			end
		end
	end
	return best
end

function LawClient.SideSlot(screen, index, touch)
	local w, h = screen.AbsoluteSize.X, screen.AbsoluteSize.Y
	local bx, by, bw, bh = zoneRect("Buttons", touch, w, h)
	local right = bx + bw
	if touch then
		-- One column hugging the right edge: CombatClient's FIRE / AIM cluster sits up and left of the
		-- jump button, so a wider block here would run into it.
		local cw, ch = TILE_TOUCH_W, TILE_TOUCH_H
		local top = by + bh + 8
		-- InteractClient's seated "Get out first" hint hangs under EXIT (in the Buttons row), right over
		-- the column's first slot while it shows: start the column under it.
		local hint = boxOf(screen, guiAt("Interact", "GetOutHint"))
		if hint and hint[1] < right and hint[1] + hint[3] > right - cw and hint[2] < top + ch and hint[2] + hint[4] > top then
			top = hint[2] + hint[4] + GAP_TOUCH_Y
		end
		local bottom = obstacleTop(screen, right - cw, right, top)
		if bottom == math.huge then
			bottom = h - (math.min(w, h) <= 500 and JUMP_TOP_SMALL or JUMP_TOP_BIG) -- (see JUMP_TOP_SMALL)
		end
		-- n tiles take n x tile + (n - 1) gaps, plus one gap above the obstacle: n x (tile + gap).
		local rows = math.max(0, math.floor((bottom - top) / (ch + GAP_TOUCH_Y)))
		if index < rows then
			return Vector2.new(right - cw, top + index * (ch + GAP_TOUCH_Y)), Vector2.new(cw, ch)
		end
		-- No room under it (driving: the pedals fill the lower right): a row left of the Buttons zone,
		-- right to left, skipping every spot that would cover something (rowBlockers).
		local blocked = rowBlockers(screen, w, h)
		local y = by + math.floor((bh - ch) / 2)
		local j = index - rows
		local x = bx - GAP_TOUCH_X - cw
		while x >= 0 do
			local free = true
			for _, r in ipairs(blocked) do
				if overlaps(x, y, cw, ch, r) then
					free = false
					break
				end
			end
			if free then
				if j == 0 then
					return Vector2.new(x, y), Vector2.new(cw, ch)
				end
				j -= 1
			end
			x -= cw + GAP_TOUCH_X
		end
		-- (no free spot anywhere in the row: the next spot along, as if nothing were there)
		j = index - rows
		return Vector2.new(bx - GAP_TOUCH_X - (j + 1) * cw - j * GAP_TOUCH_X, y), Vector2.new(cw, ch)
	end
	local s = TILE_PC
	local top = by + bh + 10
	local _, cy = zoneRect("Corner", false, w, h)
	local rows = math.max(1, math.floor((cy - 10 - top + GAP_PC) / (s + GAP_PC)))
	local col, row = index // rows, index % rows
	return Vector2.new(right - (col + 1) * s - col * GAP_PC, top + row * (s + GAP_PC)), Vector2.new(s, s)
end

function LawClient.PlaceSlots()
	local home = player:GetAttribute("InHome") == true
	local n = home and 1 or 0 -- LEAVE HOME
	if home or player:GetAttribute("InHideout") == true then
		n += 1 -- WARDROBE
	end
	return n
end

------------------------------------------------------------------ tiles and glyphs

-- One white stroke of a glyph, centred on (cx, cy) inside the glyph box, turned `rot` degrees.
local function stroke(parent, w, h, cx, cy, rot, z)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(cx, cy)
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = rot or 0
	f.BackgroundColor3 = C.Text
	f.BorderSizePixel = 0
	f.ZIndex = z or 2
	f.Parent = parent
	return f
end

-- A lightning bolt: two slanted strokes joined by a short bar.
local function boltGlyph(g)
	stroke(g, 3, 11, 12, 4.5, 28)
	stroke(g, 7, 2.5, 12, 9.5, 0)
	stroke(g, 3, 11, 11.9, 14.4, 28)
end

-- A spike strip: a base bar with three teeth (diamonds whose lower halves hide behind the bar).
local function spikeGlyph(g)
	for _, x in ipairs({ 5, 12, 19 }) do
		stroke(g, 7, 7, x, 13, 45, 2)
	end
	stroke(g, 22, 5, 12, 15.5, 0, 3)
end

-- A flat square tile for the side column: glyph on top, Display label at the bottom (the button's own
-- Text), key cap on its left (keyboard only).
local function makeTile(name, text, glyph, key)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(TILE_PC, TILE_PC)
	b.Text = text
	Theme.Button(b, "Quiet")
	b.FontFace = Theme.Font.Display
	b.TextSize = 13
	b.TextYAlignment = Enum.TextYAlignment.Bottom
	b.Visible = false
	Theme.Shadow(b)
	local pad = Instance.new("UIPadding")
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = b
	local g = Instance.new("Frame")
	g.Name = "Glyph"
	g.AnchorPoint = Vector2.new(0.5, 0)
	g.Position = UDim2.new(0.5, 0, 0, 5)
	g.Size = UDim2.fromOffset(24, 20)
	g.BackgroundTransparency = 1
	g.Parent = b
	glyph(g)
	local cap = Theme.Key(b, key)
	cap.AnchorPoint = Vector2.new(1, 0.5)
	cap.Position = UDim2.new(0, -6, 0.5, 0)
	cap.Visible = false
	table.insert(keyCaps, cap)
	b.Parent = gui
	return b
end

------------------------------------------------------------------ actions

-- Nearest wanted player on foot in range, preferring whoever is in front of the camera.
local function taserTarget()
	local root = myRoot()
	if not root then
		return nil
	end
	local camLook = Workspace.CurrentCamera.CFrame.LookVector
	local best, bestScore
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and isWanted(p) and p.Character then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
			local h = p.Character:FindFirstChildOfClass("Humanoid")
			if r and h and h.Health > 0 and not h.SeatPart then
				local offset = r.Position - root.Position
				local dist = offset.Magnitude
				if dist <= TASER_RANGE then
					local facing = offset.Unit:Dot(camLook)
					local score = dist - facing * 12
					if not bestScore or score < bestScore then
						best, bestScore = p, score
					end
				end
			end
		end
	end
	return best
end

local function fireTaser()
	-- T from the patrol car's seat (the tile is hidden there, the key isn't): the server only zaps for a
	-- cop on foot and said nothing, and the press still used up the taser's 2.5 s wait, so hopping out and
	-- pressing T again did nothing either. Say why here and ask the server for nothing.
	local _, hum = myRoot()
	if hum and hum.SeatPart then
		NotifyController.Show(NotifyController.Messages.GetOutFirst, nil, "warning")
		return
	end
	local target = taserTarget()
	if target then
		Remotes.Event("RequestTaser"):FireServer(target)
	else
		NotifyController.Show("No wanted suspect in taser range.", C.Police)
	end
end

local function dropSpikes()
	Remotes.Event("RequestSpike"):FireServer()
end

local function onAction(name, state)
	-- (LawUI is off while WardrobeUI's dressing room is open: no zapping from the closet)
	if state ~= Enum.UserInputState.Begin or side() ~= "Cop" or not gui.Enabled then
		return Enum.ContextActionResult.Pass
	end
	if name == "NC_Taser" then
		fireTaser()
	elseif name == "NC_Spike" then
		dropSpikes()
	end
	return Enum.ContextActionResult.Sink
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "LawUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- (the glyph strokes stack by ZIndex)
	gui.Parent = player:WaitForChild("PlayerGui")
	taserButton = makeTile("Taser", "TASER", boltGlyph, "T")
	spikeButton = makeTile("Spikes", "SPIKES", spikeGlyph, "G")
	taserButton.Activated:Connect(fireTaser)
	spikeButton.Activated:Connect(dropSpikes)
	-- Charges left, top-right of the SPIKES tile.
	spikeCount = Instance.new("TextLabel")
	spikeCount.Name = "Count"
	spikeCount.AnchorPoint = Vector2.new(1, 0)
	spikeCount.Position = UDim2.new(1, -4, 0, 2)
	spikeCount.Size = UDim2.fromOffset(14, 14)
	spikeCount.TextXAlignment = Enum.TextXAlignment.Right
	Theme.Text(spikeCount, 13, "Display")
	spikeCount.ZIndex = 3
	spikeCount.Parent = spikeButton

	-- Prison: release timer in the Banner zone, the breakout hint under it, a thin prisoner-orange edge.
	prisonLabel = Instance.new("TextLabel")
	prisonLabel.Name = "Prison"
	Theme.Panel(prisonLabel)
	Theme.Text(prisonLabel, 18, "Display")
	prisonLabel.BackgroundTransparency = Theme.PanelAlpha -- (Theme.Text clears the background)
	prisonLabel.TextYAlignment = Enum.TextYAlignment.Top
	prisonLabel.Visible = false
	prisonLabel.Parent = gui
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, 2)
	p.Parent = prisonLabel
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.Size = UDim2.new(0, 3, 1, 2)
	edge.Position = UDim2.fromOffset(0, -2) -- (cancels the padding)
	edge.BackgroundColor3 = C.Orange
	edge.BorderSizePixel = 0
	edge.Parent = prisonLabel
	Theme.Corners(edge, 2)
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -3)
	hint.Size = UDim2.new(1, -16, 0, 14)
	hint.Text = "Or pry open the south-wall vent and swim for it"
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	Theme.Text(hint, 13, "Body")
	hint.TextColor3 = C.Dim
	hint.Parent = prisonLabel

	markerFolder = Instance.new("Folder")
	markerFolder.Name = "WantedMarkers"
	markerFolder.Parent = Workspace.CurrentCamera -- local-only parts

	ContextActionService:BindAction("NC_Taser", onAction, false, Enum.KeyCode.T)
	ContextActionService:BindAction("NC_Spike", onAction, false, Enum.KeyCode.G)
end

------------------------------------------------------------------ wanted markers

local function marker(p)
	local m = markers[p]
	if m then
		return m
	end
	local beacon = Instance.new("Part")
	beacon.Name = "Beacon"
	beacon.Anchored = true
	beacon.CanCollide = false
	beacon.CanQuery = false
	beacon.CanTouch = false
	beacon.Transparency = 1
	beacon.Size = Vector3.new(1, 1, 1)
	beacon.Parent = markerFolder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(240, 48)
	bb.AlwaysOnTop = true
	bb.StudsOffset = Vector3.new(0, 8, 0)
	bb.MaxDistance = 2000
	-- "WANTED ★★★" in Display, the suspect's clues small under it; text straight on the world, shadowed.
	local t = Instance.new("TextLabel")
	t.Name = "Tag"
	t.Size = UDim2.new(1, 0, 0, 24)
	t.RichText = true -- the word is coloured, the stars stay white
	t.Parent = bb
	Theme.Text(t, 20, "Display")
	local clues = Instance.new("TextLabel")
	clues.Name = "Clues"
	clues.Position = UDim2.fromOffset(0, 26)
	clues.Size = UDim2.new(1, 0, 0, 18)
	clues.TextTruncate = Enum.TextTruncate.AtEnd
	clues.Parent = bb
	Theme.Text(clues, 13, "Body")
	bb.Parent = beacon
	local circle = Instance.new("Part")
	circle.Name = "SearchCircle"
	circle.Shape = Enum.PartType.Cylinder
	circle.Anchored = true
	circle.CanCollide = false
	circle.CanQuery = false
	circle.CanTouch = false
	circle.Material = Enum.Material.Neon
	circle.Color = C.Danger
	circle.Transparency = 0.85
	circle.Parent = markerFolder
	m = { beacon = beacon, label = t, clues = clues, circle = circle }
	markers[p] = m
	return m
end

local function clearMarker(p)
	local m = markers[p]
	if m then
		m.beacon:Destroy()
		m.circle:Destroy()
		markers[p] = nil
	end
end

local function updateMarkers()
	local amCop = side() == "Cop"
	for _, p in ipairs(Players:GetPlayers()) do
		local lastSeen = p:GetAttribute("LastSeen")
		if amCop and p ~= player and isWanted(p) and typeof(lastSeen) == "Vector3" then
			local m = marker(p)
			local heat = p:GetAttribute("Heat") or 1
			local spotted = p:GetAttribute("HeatSpotted") == true
			local pos = lastSeen
			-- While spotted, follow the real character if it's streamed in (smoother than LastSeen).
			if spotted and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				pos = p.Character.HumanoidRootPart.Position
			end
			m.beacon.Position = pos
			-- Suspect Card: whatever the cameras and cops have seen.
			local clues = {}
			if p:GetAttribute("SuspectCar") then
				table.insert(clues, p:GetAttribute("SuspectCar"))
			end
			if p:GetAttribute("SuspectOutfit") then
				table.insert(clues, p:GetAttribute("SuspectOutfit"))
			end
			-- The word says how fresh the sighting is (red while a cop sees them); the stars stay white.
			local word = spotted and "WANTED" or "LAST SEEN"
			m.label.Text = '<font color="#' .. (spotted and C.Danger or C.Dim):ToHex() .. '">' .. word .. "</font>  "
				.. string.rep("★", heat)
			m.clues.Text = table.concat(clues, "  ·  ")
			local radius = 150 + 50 * heat
			m.circle.Transparency = spotted and 1 or 0.85
			m.circle.Size = Vector3.new(1, radius * 2, radius * 2)
			m.circle.CFrame = CFrame.new(lastSeen.X, 0.3, lastSeen.Z) * CFrame.Angles(0, 0, math.rad(90))
		else
			clearMarker(p)
		end
	end
	for p in pairs(markers) do
		if not p.Parent then
			clearMarker(p)
		end
	end
end

------------------------------------------------------------------ prompts

local function setPrompt(prompt, show)
	if prompt and prompt.Enabled ~= show then
		prompt.Enabled = show
	end
end

local function updatePrompts()
	local amCop = side() == "Cop"
	-- Sitting in a car (driving or riding): holding Pick lock would fill the bar for nothing, since the
	-- server only lets people on foot take a car. Parked cars' Break in prompts aren't in Workspace.Vehicles:
	-- InteractClient switches those, and keeps them off while seated too.
	local _, hum = myRoot()
	local seated = hum ~= nil and hum.SeatPart ~= nil
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		setPrompt(root and root:FindFirstChild("CuffPrompt"), amCop and p ~= player and isWanted(p))
	end
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if vehicles then
		for _, car in ipairs(vehicles:GetChildren()) do
			local seat = car:FindFirstChild("DriverSeat")
			local driverId = car:GetAttribute("DriverUserId")
			local driver = driverId and Players:GetPlayerByUserId(driverId)
			setPrompt(seat and seat:FindFirstChild("CuffDriver"), amCop and driver ~= nil and driver ~= player and isWanted(driver))
			-- Hot cars: only citizens on foot can pick the lock, and only before someone has stolen it.
			setPrompt(seat and seat:FindFirstChild("PickLockPrompt"), side() == "Civilian" and not seated
				and car:GetAttribute("ThiefUserId") == nil)
			-- Car meets: a show car's "Like" bubble is for everybody else (CarMeetService ignores the owner's
			-- own press). On our own car it did nothing and still took the E key, so E no longer got us back
			-- in while the car was on show. (A new prompt every time the car goes on show: off is enough.)
			if car:GetAttribute("OwnerUserId") == player.UserId and car:IsA("Model") then
				local chassis = car.PrimaryPart
				setPrompt(chassis and chassis:FindFirstChild("LikePrompt"), false)
			end
		end
	end
	local city = Workspace:FindFirstChild("City")
	local vent = city and city:FindFirstChild("PrisonVent", true)
	-- The vent is streamed: it can be missing for a moment right after the arrest respawn.
	setPrompt(vent and vent:FindFirstChild("VentPrompt"), vent ~= nil and side() == "Prisoner" and vent:GetAttribute("Open") ~= true)
end

------------------------------------------------------------------ HUD

-- Cop tiles into the side column, after the slots LEAVE HOME and WARDROBE hold (see the header).
-- While TASER is hidden (driving) SPIKES moves up into its slot.
local function placeButtons()
	local touch = Theme.IsTouch()
	local i = LawClient.PlaceSlots()
	for _, b in ipairs({ taserButton, spikeButton }) do
		if b.Visible then
			local pos, size = LawClient.SideSlot(gui, i, touch)
			b.Position = UDim2.fromOffset(pos.X, pos.Y)
			b.Size = UDim2.fromOffset(size.X, size.Y)
			i += 1
		end
	end
	local keys = keyboardMode()
	for _, cap in ipairs(keyCaps) do
		cap.Visible = keys
	end
end

local function updateUI()
	local amCop = side() == "Cop"
	local title = player:GetAttribute("TitleScreen") == true
	local _, hum = myRoot()
	local onFoot = hum ~= nil and hum.SeatPart == nil
	taserButton.Visible = amCop and onFoot and not title
	spikeButton.Visible = amCop and not title
	local charges = player:GetAttribute("SpikeCharges") or 0
	spikeCount.Text = tostring(charges)
	spikeCount.TextColor3 = charges > 0 and C.Text or C.Danger
	placeButtons()
	if side() == "Prisoner" and not title then
		local left = math.max(0, math.floor((player:GetAttribute("ReleaseAt") or 0) - now()))
		local touch = Theme.IsTouch()
		Theme.Place(prisonLabel, "Banner", touch)
		prisonLabel.TextSize = touch and 16 or 18
		prisonLabel.Visible = true
		prisonLabel.Text = string.format("RELEASE IN %d:%02d", left // 60, left % 60)
	else
		prisonLabel.Visible = false
	end
	-- Stunned: keep the character down on this device while the server's stun lasts.
	if hum then
		local stunned = (player:GetAttribute("StunnedUntil") or 0) > now()
		if hum.PlatformStand ~= stunned and not hum.SeatPart then
			hum.PlatformStand = stunned
		end
	end
end

local function zap(cop, target)
	local a = cop.Character and cop.Character:FindFirstChild("HumanoidRootPart")
	local b = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not a or not b then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Parent = a
	local a1 = Instance.new("Attachment")
	a1.Parent = b
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Color = ColorSequence.new(C.Police)
	beam.LightEmission = 1
	beam.Width0, beam.Width1 = 0.25, 0.25
	beam.CurveSize0, beam.CurveSize1 = 2, -2
	beam.FaceCamera = true
	beam.Parent = a
	task.delay(0.35, function()
		beam:Destroy()
		a0:Destroy()
		a1:Destroy()
	end)
	if target == player then
		NotifyController.Show("ZAPPED! You're stunned.", C.Police)
	end
end

function LawClient.Init()
	build()
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				updatePrompts()
				updateMarkers()
				updateUI()
			end)
			if not ok then
				warn("[LawClient] " .. tostring(err))
			end
			task.wait(0.2)
		end
	end)
	Remotes.OnClient("TaserFx", zap)
	Remotes.OnClient("Caught", function(info)
		HUDController.Stamp("CUFFED", HEADLINES[math.random(1, #HEADLINES)], C.Danger)
	end)
	Remotes.OnClient("BountyEarned", function(info)
		if (tonumber(info.Amount) or 0) > 0 then
			HUDController.Stamp("BOUNTY", "+" .. HUDController.Money(info.Amount) .. " for catching " .. info.Name, C.Cash)
		else
			-- Fight, breakout and hot-car stars carry no bounty (HeatService.PaidStars).
			HUDController.Stamp("ARRESTED", "You caught " .. info.Name .. " (no bounty on those stars)", C.Police)
		end
	end)
	Remotes.OnClient("BrokeOut", function()
		HUDController.Stamp("BREAKOUT", "You're wanted again. Run!", C.Danger)
	end)
end

return LawClient
