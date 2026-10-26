-- TeamUI (ModuleScript, StarterPlayerScripts.Controllers.TeamUI)
-- The title screen and the role line ("street" look, Theme). Free roam only: everyone joins as a
-- citizen, and police is an optional job taken from the phone (PHONE > JOBS: GO ON DUTY).
--   * First join (HasPicked not set): a title screen. The camera drifts slowly round the street you spawned
--     on (round a home's front door for a returning owner, who spawns there: HousingService), the rest
--     of the HUD is hidden (local player attribute "TitleScreen" = true meanwhile, for HUD layers that
--     switch themselves back on), the logo sits top-left, and one big PLAY button at the bottom (a tap
--     anywhere else, Enter / Space or gamepad A / Start too) starts the game: it asks the server for
--     free roam (RequestTeam "Civilian": TeamService sets HasPicked, which the tutorial, the daily
--     reward, GET IN and the friends' join wait for) and hands the camera back. No respawn: you play
--     on from where you stand. Inside a home (InHome) the camera circles close and stays in the room.
--   * The logo (built from UI, no image, so a new name is a one-line change: LOGO_WORDS): THEFT / MIAMI /
--     COAST stacked in Theme.Font.Logo (extra-heavy italic) filled with Theme.Sunset, a thick Theme.Ink
--     outline and drop shadow, over a striped synthwave sun, then a pink rule and "PORT SOLANA  ·  OPEN
--     WORLD". Our own mark: no numeral, no other game's lettering or layout. Top-left on a PC; top centre
--     on a phone (Roblox's buttons own the top-left corner there, and PLAY needs the bottom).
--   * The role line ("CITIZEN", "COP", "PRISONER") is a small quiet button in the HUD's Status zone
--     (Theme.Zone), bottom row, right-aligned. Tapping it opens PHONE > JOBS (police duty).
-- The server decides; this only asks (RequestTeam).
--   TeamUI.Open()    open PHONE > JOBS, where police duty is (not for prisoners)
--   TeamUI.Badge     the role line button (other HUD pieces may read its place)
--   TeamUI.IsTitle() true while the first-join title screen is up
-- CombatClient reads the overlay frame's name ("Picker"): no gun is out while it shows.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local Theme = require(ReplicatedStorage.Shared.Util.Theme)

local player = Players.LocalPlayer

local TeamUI = {}

local COLOR = { Civilian = Theme.Color.Brand, Cop = Theme.Color.Police, Prisoner = Theme.Color.Orange }
local LABEL = { Civilian = "CITIZEN", Cop = "COP", Prisoner = "PRISONER" }
local CAMERA_STEP = "NC_TitleCamera"
local LOGO_WORDS = { "THEFT", "MIAMI", "COAST" } -- the game's name, one line each
local LOGO_ASPECT = 1.45 -- the logo's width / height (three lines of five letters)
-- The sun's stripes, as shares of its height from the top: a solid cap, then bands with growing gaps.
local SUN_BANDS = { { 0, 0.52 }, { 0.56, 0.64 }, { 0.68, 0.75 }, { 0.79, 0.85 }, { 0.885, 0.93 }, { 0.955, 0.985 } }

local START_KEYS = { -- keys that press PLAY on the title screen
	[Enum.KeyCode.Return] = true, [Enum.KeyCode.KeypadEnter] = true, [Enum.KeyCode.Space] = true,
	[Enum.KeyCode.ButtonA] = true, [Enum.KeyCode.ButtonStart] = true,
}
local HOME_ORBIT = 9 -- studs: the title camera's circle inside a home (pulled in front of any wall)

local gui, overlay, badge, logo, play
local logoInk = {} -- the logo's outlines and drop shadows: { stroke = UIStroke } / { drop = label, x, y }
local requestTeam
local title = false -- the first-join title screen is showing
local hidden = {} -- [ScreenGui] = true: HUD layers switched off for the title screen
local started = false -- PLAY was pressed (once a session)

local function label(parent, str, size, pos, kind, color, anchor)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.AnchorPoint = anchor or Vector2.new(0, 0)
	l.Text = str
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	Theme.Text(l, nil, kind)
	l.TextScaled = true
	if color then
		l.TextColor3 = color
	end
	l.Parent = parent
	return l
end

-- The role line's words and colour.
local function refresh()
	local side = player:GetAttribute("Side") or "Civilian"
	badge.Text = LABEL[side] or LABEL.Civilian
	badge.TextColor3 = COLOR[side] or COLOR.Civilian
end

-- The title camera: a slow circle round the spawn street, a little above head height, looking across it.
-- It follows the character, so a returning owner whom HousingService has moved to their front door sees
-- their home. Inside a home (InHome: the inside is a room far off the map) it circles close instead and
-- is pulled in front of any wall, so it never shows the room from outside.
local function titleCamera()
	local t0 = os.clock()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value + 2, function()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local camera = Workspace.CurrentCamera
		if not root or not camera then
			return
		end
		local a = (os.clock() - t0) * 0.05 + 0.6
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 60
		if player:GetAttribute("InHome") == true then
			local centre = root.Position + Vector3.new(0, 2, 0)
			local want = Vector3.new(math.cos(a) * HOME_ORBIT, 3, math.sin(a) * HOME_ORBIT)
			params.FilterDescendantsInstances = { player.Character }
			local hit = Workspace:Raycast(centre, want, params)
			local eye = hit and (centre + want.Unit * math.max(hit.Distance - 0.6, 0.5)) or (centre + want)
			camera.CFrame = CFrame.lookAt(eye, centre)
			return
		end
		local centre = root.Position + Vector3.new(0, 16, 0)
		local eye = centre + Vector3.new(math.cos(a) * 70, 14 + math.sin(a * 0.7) * 5, math.sin(a) * 70)
		camera.CFrame = CFrame.lookAt(eye, centre + Vector3.new(0, 6, 0))
	end)
end

-- While the title screen is up, every other HUD layer is off (checked a few times a second, because
-- most of them are built after this controller starts).
local function hideHud()
	while title do
		for _, g in ipairs(player.PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g ~= gui and g.Enabled and g.Name ~= "Freecam" then
				hidden[g] = true
				g.Enabled = false
			end
		end
		task.wait(0.2)
	end
	for g in pairs(hidden) do
		if g.Parent then
			g.Enabled = true -- layers that hide themselves (the drive HUD, the phone) do so again on their next update
		end
	end
	table.clear(hidden)
end

local function setTitle(on)
	if on == title then
		return
	end
	title = on
	-- HUD layers that switch themselves on every update check this (local-only attribute).
	player:SetAttribute("TitleScreen", on or nil)
	logo.Visible = on
	overlay.Visible = on
	badge.Visible = not on
	if on then
		titleCamera()
		task.spawn(hideHud)
	else
		RunService:UnbindFromRenderStep(CAMERA_STEP)
		local camera = Workspace.CurrentCamera
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if camera and not (hum and hum.SeatPart) then
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			if hum then
				camera.CameraSubject = hum
			end
		end
	end
end

-- The striped sun: each band is a clipped slice of one disc filled sun-yellow to pink, so the stripes
-- line up into a single circle.
local function buildSun(parent)
	local sun = Instance.new("Frame")
	sun.Name = "Sun"
	sun.BackgroundTransparency = 1
	sun.Parent = parent
	for i, b in ipairs(SUN_BANDS) do
		local h = b[2] - b[1]
		local slice = Instance.new("Frame")
		slice.Name = "Band" .. i
		slice.BackgroundTransparency = 1
		slice.ClipsDescendants = true
		slice.Position = UDim2.fromScale(0, b[1])
		slice.Size = UDim2.fromScale(1, h)
		slice.Parent = sun
		local disc = Instance.new("Frame")
		disc.BorderSizePixel = 0
		disc.BackgroundColor3 = Color3.new(1, 1, 1)
		disc.Position = UDim2.fromScale(0, -b[1] / h)
		disc.Size = UDim2.fromScale(1, 1 / h)
		disc.Parent = slice
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = disc
		local fill = Instance.new("UIGradient")
		fill.Rotation = 90
		fill.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90), Color3.fromRGB(255, 60, 150))
		fill.Parent = disc
	end
	return sun
end

-- One word of the logo: a drop shadow behind, the sunset-filled word with its outline on top.
local function logoWord(parent, word, y, h)
	local drop = Instance.new("TextLabel")
	drop.Name = word .. "Drop"
	drop.BackgroundTransparency = 1
	drop.FontFace = Theme.Font.Logo
	drop.TextScaled = true
	drop.TextXAlignment = Enum.TextXAlignment.Left
	drop.Text = word
	drop.TextColor3 = Theme.Ink
	drop.Size = UDim2.fromScale(0.9, h)
	drop.ZIndex = 2
	drop.Parent = parent
	local dropEdge = Instance.new("UIStroke")
	dropEdge.Color = Theme.Ink
	dropEdge.LineJoinMode = Enum.LineJoinMode.Round
	dropEdge.Parent = drop
	table.insert(logoInk, { stroke = dropEdge })
	table.insert(logoInk, { drop = drop, y = y })
	local w = drop:Clone()
	w.Name = word
	w.TextColor3 = Color3.new(1, 1, 1)
	w.Position = UDim2.fromScale(0, y)
	w.ZIndex = 3
	w.Parent = parent
	local fill = Instance.new("UIGradient")
	fill.Rotation = 90
	fill.Color = Theme.Sunset
	fill.Parent = w
	table.insert(logoInk, { stroke = w:FindFirstChildOfClass("UIStroke") })
	return w
end

local function buildLogo(parent)
	local f = Instance.new("Frame")
	f.Name = "Logo"
	f.BackgroundTransparency = 1
	f.Visible = false
	f.Parent = parent
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = LOGO_ASPECT
	aspect.DominantAxis = Enum.DominantAxis.Width
	aspect.Parent = f
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(640, 640 / LOGO_ASPECT)
	limit.Parent = f
	-- The sun sits behind the right half of the words.
	local sun = buildSun(f)
	sun.AnchorPoint = Vector2.new(0.5, 0)
	sun.Position = UDim2.fromScale(0.68, 0.02)
	sun.Size = UDim2.fromScale(0.74 / LOGO_ASPECT, 0.74)
	sun.ZIndex = 1
	-- The lines share the top 77% of the logo, each overlapping the one above a little.
	local lineH = 0.77 / (#LOGO_WORDS - 0.12 * (#LOGO_WORDS - 1))
	for i, word in ipairs(LOGO_WORDS) do
		logoWord(f, word, 0.01 + (i - 1) * lineH * 0.88, lineH)
	end
	local line = Instance.new("Frame")
	line.Name = "Rule"
	line.Position = UDim2.fromScale(0.005, 0.81)
	line.Size = UDim2.new(0.22, 0, 0, 3)
	line.BackgroundColor3 = Theme.Color.Brand
	line.BorderSizePixel = 0
	line.ZIndex = 3
	line.Parent = f
	local tag = label(f, "PORT SOLANA   ·   OPEN WORLD", UDim2.fromScale(0.8, 0.09), UDim2.fromScale(0.005, 0.86), "Display")
	tag.ZIndex = 3
	-- Outline and shadow sizes follow the logo's size on screen.
	local function ink()
		local h = f.AbsoluteSize.Y
		for _, item in ipairs(logoInk) do
			if item.stroke then
				item.stroke.Thickness = math.max(2, math.floor(h * 0.022 + 0.5))
			elseif item.drop then
				item.drop.Position = UDim2.new(0, math.max(2, math.floor(h * 0.022)), item.y, math.max(3, math.floor(h * 0.03)))
			end
		end
	end
	f:GetPropertyChangedSignal("AbsoluteSize"):Connect(ink)
	ink()
	return f
end

-- PC: top-left, under Roblox's top bar. Phone: small, top centre (Roblox's buttons sit top-left there),
-- so it stays clear of PLAY along the bottom.
local function placeLogo()
	if not logo then
		return
	end
	local touch = Theme.IsTouch()
	logo.AnchorPoint = Vector2.new(touch and 0.5 or 0, 0)
	logo.Position = touch and UDim2.new(0.5, 0, 0, 8) or UDim2.new(0.05, 0, 0, Theme.TopBar + 10)
	logo.Size = UDim2.fromScale(touch and 0.2 or 0.34, 1)
end

-- The role line: bottom row of the HUD's Status zone, right-aligned (ProgressClient's RANK sits on its left).
local function placeBadge()
	if not badge then
		return
	end
	local touch = Theme.IsTouch()
	local z = Theme.Zone("Status", touch)
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(z.Pos.X.Scale, z.Pos.X.Offset, z.Pos.Y.Scale, z.Pos.Y.Offset + z.Size.Y.Offset - 22)
	badge.Size = UDim2.fromOffset(120, 22)
	badge.TextSize = touch and 13 or 14
end

-- PLAY (or any tap, Enter / Space, gamepad A / Start on the title screen): free roam, and the game starts.
local function start()
	if not title or started then
		return
	end
	started = true
	requestTeam:FireServer("Civilian") -- TeamService sets HasPicked (no respawn: we're a citizen already)
	TeamUI.Close()
	-- Everything that waits for HasPicked (GET IN, the tutorial, the daily reward) hangs on that answer:
	-- ask again if it hasn't come (TeamService ignores a second ask within a second, never a later one).
	task.spawn(function()
		for _ = 1, 3 do
			task.wait(3)
			if player:GetAttribute("HasPicked") == true or player.Parent == nil then
				return
			end
			requestTeam:FireServer("Civilian")
		end
	end)
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "TeamUI"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The title screen ("Picker": CombatClient keeps guns away while it shows).
	overlay = Instance.new("Frame")
	overlay.Name = "Picker"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundTransparency = 1
	overlay.Visible = false
	overlay.Parent = gui

	-- A tap anywhere starts too: a see-through button under everything else on the title screen.
	local anywhere = Instance.new("TextButton")
	anywhere.Name = "TapToStart"
	anywhere.Size = UDim2.fromScale(1, 1)
	anywhere.BackgroundTransparency = 1
	anywhere.Text = ""
	anywhere.AutoButtonColor = false
	anywhere.Selectable = false
	anywhere.ZIndex = 0
	anywhere.Parent = overlay
	anywhere.Activated:Connect(start)

	-- A soft dark band along the bottom so PLAY and its line read over any street.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.AnchorPoint = Vector2.new(0, 1)
	band.Position = UDim2.fromScale(0, 1)
	band.Size = UDim2.fromScale(1, 0.55)
	band.BackgroundColor3 = Color3.new(0, 0, 0)
	band.BorderSizePixel = 0
	band.Parent = overlay
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.6, 0.45), NumberSequenceKeypoint.new(1, 0.15) })
	fade.Parent = band

	-- The logo, top-left (top centre on a phone).
	logo = buildLogo(overlay)
	placeLogo()

	-- PLAY: one clear way in. It breathes a little so it reads as the thing to press.
	play = Instance.new("TextButton")
	play.Name = "Play"
	play.AnchorPoint = Vector2.new(0.5, 1)
	play.Position = UDim2.new(0.5, 0, 1, -58)
	play.Size = UDim2.fromOffset(240, 56)
	play.Text = "PLAY"
	Theme.Button(play, "Primary")
	play.FontFace = Theme.Font.Display
	play.TextSize = 28
	play.Parent = overlay
	play.Activated:Connect(start)
	local scale = Instance.new("UIScale")
	scale.Parent = play
	task.spawn(function()
		local t = 0
		while play.Parent do
			t += task.wait()
			scale.Scale = (overlay.Visible and title) and (1 + 0.03 * math.sin(t * 3)) or 1
		end
	end)
	-- One line on what kind of game this is (the old FREE ROAM / POLICE choice, as a sentence).
	local line = label(overlay, "Free roam: drive, explore, rob if you dare. Police is an optional job on your PHONE.",
		UDim2.new(0.92, 0, 0, 18), UDim2.new(0.5, 0, 1, -24), "Body", Theme.Color.Dim, Vector2.new(0.5, 1))
	line.Name = "Line"
	line.TextXAlignment = Enum.TextXAlignment.Center

	-- The role line: bottom row of the Status zone (top-right), right-aligned, quiet.
	badge = Instance.new("TextButton")
	badge.Name = "TeamBadge"
	badge.BackgroundTransparency = 1
	badge.AutoButtonColor = false
	badge.FontFace = Theme.Font.Bold
	badge.TextXAlignment = Enum.TextXAlignment.Right
	badge.Parent = gui
	Theme.Shadow(badge)
	TeamUI.Badge = badge
	badge.Activated:Connect(TeamUI.Open)
end

-- Police duty lives in the phone's JOBS app (the role line and older callers use this). PhoneUI starts
-- after this controller, so it's looked up on use.
function TeamUI.Open()
	if title or player:GetAttribute("Side") == "Prisoner" then
		return
	end
	local module = script.Parent:FindFirstChild("PhoneUI")
	local ok, phone = pcall(function()
		return module and require(module)
	end)
	if ok and type(phone) == "table" and type(phone.Open) == "function" then
		phone.Open("Jobs")
	end
end

-- Ends the title screen (PLAY, or the server set HasPicked: a prisoner who rejoined mid-sentence).
function TeamUI.Close()
	setTitle(false)
end

function TeamUI.IsTitle()
	return title
end

function TeamUI.Init()
	requestTeam = Remotes.Event("RequestTeam")
	build()
	placeBadge()
	for _, prop in ipairs({ "TouchEnabled", "MouseEnabled" }) do
		UserInputService:GetPropertyChangedSignal(prop):Connect(placeBadge)
		UserInputService:GetPropertyChangedSignal(prop):Connect(placeLogo)
	end
	-- The Roblox player list would sit on top of the HUD's Status zone: off (the phone lists who's here).
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	setTitle(player:GetAttribute("HasPicked") ~= true)
	refresh()
	player:GetAttributeChangedSignal("Side"):Connect(refresh)
	player:GetAttributeChangedSignal("HasPicked"):Connect(function()
		if player:GetAttribute("HasPicked") then
			TeamUI.Close()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if title and not processed and START_KEYS[input.KeyCode] then
			start()
		end
	end)
end

return TeamUI
