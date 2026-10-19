-- DistrictClient (ModuleScript, StarterPlayerScripts.Controllers.DistrictClient)
-- Neighbourhood titles: when you cross into a different district of Port Solana (the ground tiles in
-- Workspace.City.Ground, published by MapService as ReplicatedStorage attribute "Districts"), a small
-- title fades in at the top centre for about 2.5 s, like "SOLANA HEIGHTS / Downtown". It never takes
-- input, waits while a big HUD stamp is showing, and tells SoundClient where you are so the ambience
-- (city hum, surf) fits the district.
--   DistrictClient.Current() -> the district key you're in (e.g. "FlamingoBeach"), or nil.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local DistrictClient = {}

local PINK = Color3.fromRGB(255, 62, 165)
local MINT = Color3.fromRGB(110, 242, 196)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

local CHECK = 0.5 -- seconds between position checks
local SHOW_FOR = 2.5

-- Title and subtitle per district (ground part name). Glades tiles all count as Gator Glades.
local NAMES = {
	SolanaHeights = { "SOLANA HEIGHTS", "Downtown" },
	PalmHills = { "PALM HILLS", "Suburbs & strip malls" },
	FlamingoBeach = { "FLAMINGO BEACH", "Boardwalk & pier" },
	GatorGlades = { "GATOR GLADES", "Swamp country" },
	RustwaterDocks = { "RUSTWATER DOCKS", "Port & warehouses" },
	MarinaRow = { "MARINA ROW", "Yachts & seafood" },
	SaltmarshIsland = { "SALTMARSH ISLAND", "State prison" },
	LighthouseKey = { "LIGHTHOUSE KEY", "Drift club & lighthouse" },
}
local ALIASES = { GladesSouth = "GatorGlades", GladesSouthEast = "GatorGlades", GladesSouthWest = "GatorGlades" }

local tiles = {} -- { key, cx, cz, hx, hz, cos, sin, area }
local current
local gui, frame, title, subtitle, titleStroke, subStroke
local showToken = 0

local function keyFor(name)
	return ALIASES[name] or name
end

-- "SomeNewPlace" -> "SOME NEW PLACE" for districts this file doesn't know yet.
local function prettify(key)
	return string.upper((string.gsub(key, "(%l)(%u)", "%1 %2")))
end

local function addTile(name, x, z, sx, sz, yawDeg)
	local yaw = math.rad(yawDeg or 0)
	table.insert(tiles, {
		key = keyFor(name), cx = x, cz = z, hx = sx / 2, hz = sz / 2, cos = math.cos(yaw), sin = math.sin(yaw),
		area = sx * sz,
	})
end

local function loadTiles()
	table.clear(tiles)
	local ok, list = pcall(function()
		return HttpService:JSONDecode(ReplicatedStorage:GetAttribute("Districts") or "[]")
	end)
	if ok and type(list) == "table" then
		for _, d in ipairs(list) do
			if type(d) == "table" and type(d.n) == "string" and type(d.x) == "number" and type(d.z) == "number"
				and type(d.sx) == "number" and type(d.sz) == "number" then
				addTile(d.n, d.x, d.z, d.sx, d.sz, tonumber(d.r))
			end
		end
	end
	if #tiles == 0 then
		-- Older server: read whatever ground has streamed in.
		local city = Workspace:FindFirstChild("City")
		local ground = city and city:FindFirstChild("Ground")
		for _, p in ipairs(ground and ground:GetChildren() or {}) do
			if p:IsA("BasePart") then
				local _, yaw = p.CFrame:ToEulerAnglesYXZ()
				addTile(p.Name, p.Position.X, p.Position.Z, p.Size.X, p.Size.Z, math.deg(yaw))
			end
		end
	end
end

-- The district under a point (the smallest tile that contains it), or nil out at sea.
local function districtAt(pos)
	local best, bestArea
	for _, t in ipairs(tiles) do
		local dx, dz = pos.X - t.cx, pos.Z - t.cz
		-- Into the tile's own axes (rotated by its yaw).
		local lx = dx * t.cos - dz * t.sin
		local lz = dx * t.sin + dz * t.cos
		if math.abs(lx) <= t.hx and math.abs(lz) <= t.hz and (not bestArea or t.area < bestArea) then
			best, bestArea = t.key, t.area
		end
	end
	return best
end

-- Is a big HUD stamp on screen? (HUDController.IsStamping when it exists, else look for the stamp frame.)
local function stampShowing()
	local hudModule = script.Parent:FindFirstChild("HUDController")
	if hudModule then
		local ok, hud = pcall(require, hudModule)
		if ok and type(hud) == "table" and type(hud.IsStamping) == "function" then
			local okS, on = pcall(hud.IsStamping)
			return okS and on == true
		end
	end
	local pg = player:FindFirstChild("PlayerGui")
	local hudGui = pg and pg:FindFirstChild("HUD")
	if hudGui then
		for _, child in ipairs(hudGui:GetChildren()) do
			if child:IsA("Frame") and child:FindFirstChildOfClass("UIScale") then
				return true
			end
		end
	end
	return false
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "District"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 0
	gui.Parent = player:WaitForChild("PlayerGui")
	frame = Instance.new("Frame")
	frame.Name = "Banner"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 8) -- in the middle of the top bar, clear of the HUD below
	frame.Size = UDim2.fromOffset(240, 46)
	frame.BackgroundTransparency = 1
	frame.Active = false
	frame.Visible = false
	frame.Parent = gui
	title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = FONT
	title.TextScaled = true
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Parent = frame
	titleStroke = Instance.new("UIStroke")
	titleStroke.Color = PINK
	titleStroke.Thickness = 2
	titleStroke.Parent = title
	subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.fromOffset(0, 29)
	subtitle.Size = UDim2.new(1, 0, 0, 16)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = FONT
	subtitle.TextScaled = true
	subtitle.TextColor3 = MINT
	subtitle.Parent = frame
	subStroke = Instance.new("UIStroke")
	subStroke.Color = DARK
	subStroke.Thickness = 1.5
	subStroke.Parent = subtitle
end

local function setAlpha(a)
	title.TextTransparency = a
	subtitle.TextTransparency = a
	titleStroke.Transparency = a
	subStroke.Transparency = a
end

local function fade(to, seconds)
	local info = TweenInfo.new(seconds)
	for _, inst in ipairs({ title, subtitle }) do
		TweenService:Create(inst, info, { TextTransparency = to }):Play()
	end
	for _, inst in ipairs({ titleStroke, subStroke }) do
		TweenService:Create(inst, info, { Transparency = to }):Play()
	end
end

local function show(key)
	showToken += 1
	local token = showToken
	local names = NAMES[key]
	task.spawn(function()
		-- Wait (a little) for a big stamp to finish; a newer district wins.
		local waited = 0
		while stampShowing() and waited < 5 do
			task.wait(0.25)
			waited += 0.25
			if token ~= showToken then
				return
			end
		end
		if token ~= showToken or stampShowing() then
			return
		end
		-- Keep clear of the heat stars (top right) on narrow phones.
		local width = Workspace.CurrentCamera.ViewportSize.X
		frame.Size = UDim2.fromOffset(math.clamp(width - 460, 170, 260), 46)
		title.Text = names and names[1] or prettify(key)
		subtitle.Text = names and names[2] or ""
		setAlpha(1)
		frame.Visible = true
		fade(0, 0.3)
		task.wait(SHOW_FOR)
		if token ~= showToken then
			return
		end
		fade(1, 0.4)
		task.wait(0.45)
		if token == showToken then
			frame.Visible = false
		end
	end)
end

function DistrictClient.Current()
	return current
end

function DistrictClient.Init()
	build()
	loadTiles()
	ReplicatedStorage:GetAttributeChangedSignal("Districts"):Connect(loadTiles)
	task.spawn(function()
		task.wait(4) -- let the join screens settle first
		local pending, pendingCount = nil, 0
		while true do
			local ok, err = pcall(function()
				if #tiles == 0 then
					loadTiles()
				end
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local pos = root and root:IsA("BasePart") and root.Position or nil
				local here = pos and districtAt(pos)
				if here and here ~= current then
					-- Must hold for two checks, so a border wobble doesn't flash titles.
					if here == pending then
						pendingCount += 1
					else
						pending, pendingCount = here, 1
					end
					if pendingCount >= 2 then
						current = here
						pending, pendingCount = nil, 0
						local sound = script.Parent:FindFirstChild("SoundClient")
						if sound then
							local s = require(sound)
							if type(s.SetDistrict) == "function" then
								s.SetDistrict(current)
							end
						end
						show(current)
					end
				else
					pending, pendingCount = nil, 0
				end
			end)
			if not ok then
				warn("[DistrictClient] " .. tostring(err))
				task.wait(5)
			end
			task.wait(CHECK)
		end
	end)
end

return DistrictClient
