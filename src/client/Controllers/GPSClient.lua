-- GPSClient (ModuleScript, StarterPlayerScripts.Controllers.GPSClient)
-- The phone's GPS: pick a place and a route of glowing dots follows the roads to it (A* over the
-- published RoadGraph), with a tall light pillar at the destination and a distance readout.
-- Everything here is local to this player (parts live under the camera).
--   GPSClient.SetTarget(name, position)   start a route
--   GPSClient.Clear()
--   GPSClient.Target() -> name or nil; TargetPos(); RoutePoints() -> polyline (for the minimap)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RoadGraph = require(ReplicatedStorage.Shared.Util.RoadGraph)
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))

local player = Players.LocalPlayer

local GPSClient = {}

local PINK = Color3.fromRGB(255, 62, 165)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

local DOT_GAP = 22 -- studs between route dots
local DOT_COUNT = 40 -- about 880 studs of route shown ahead
local ARRIVE = 40
local STUD_METERS = 0.28 -- same scale as the MPH gauge

local target -- { name, pos }
local lastPoints -- the current route polyline (the minimap draws it too)
local folder, pillar, label
local dots = {}
local graphReady = false
local lastRoute = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function groundY(x, z)
	local city = Workspace:FindFirstChild("City")
	if not city then
		return 1
	end
	rayParams.FilterDescendantsInstances = { city:FindFirstChild("Roads"), city:FindFirstChild("Ground") }
	local hit = Workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -120, 0), rayParams)
	return hit and hit.Position.Y or 1
end

local function build()
	folder = Instance.new("Folder")
	folder.Name = "GPSRoute"
	folder.Parent = Workspace.CurrentCamera
	for i = 1, DOT_COUNT do
		local d = Instance.new("Part")
		d.Name = "Dot"
		d.Shape = Enum.PartType.Ball
		d.Size = Vector3.new(1.8, 1.8, 1.8)
		d.Anchored = true
		d.CanCollide = false
		d.CanQuery = false
		d.CanTouch = false
		d.CastShadow = false
		d.Material = Enum.Material.Neon
		d.Color = PINK
		d.Transparency = 1
		d.Parent = folder
		dots[i] = d
	end
	pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Size = Vector3.new(8, 400, 8)
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = PINK
	pillar.Transparency = 1
	pillar.Parent = folder

	local gui = Instance.new("ScreenGui")
	gui.Name = "GPS"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	label = Instance.new("TextLabel")
	label.Name = "Route"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 58)
	label.Size = UDim2.fromOffset(300, 32)
	label.BackgroundColor3 = DARK
	label.BackgroundTransparency = 0.2
	label.Font = FONT
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Visible = false
	label.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = label
	local s = Instance.new("UIStroke")
	s.Color = PINK
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = label
	local p = Instance.new("UIPadding")
	p.PaddingTop, p.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)
	p.PaddingLeft, p.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	p.Parent = label
	-- Top row between the rank chip and the minimap (or EXIT/FLIP while driving): see HUDController.
	local function layout()
		local size = gui.AbsoluteSize
		local x, width = HUDController.TopRowRect(size.X, size.Y)
		label.Position = UDim2.fromOffset(x, 58)
		label.Size = UDim2.fromOffset(width, 32)
	end
	label.AnchorPoint = Vector2.new(0, 0)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	HUDController.OnLayout(layout)
end

local function hideRoute()
	for _, d in ipairs(dots) do
		d.Transparency = 1
	end
end

function GPSClient.Distance(pos)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	return (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
end

function GPSClient.FormatDistance(studs)
	local m = studs * STUD_METERS
	if m >= 1000 then
		return string.format("%.1f km", m / 1000)
	end
	return string.format("%d m", math.floor(m / 10 + 0.5) * 10)
end

-- Lay dots along the polyline, starting at the player.
local function drawRoute(points)
	local i = 1
	local carry = 12 -- start a little ahead of the player
	for s = 1, #points - 1 do
		local a, b = points[s], points[s + 1]
		local seg = b - a
		local len = seg.Magnitude
		local t = carry
		while t < len and i <= DOT_COUNT do
			local p = a + seg.Unit * t
			dots[i].Position = Vector3.new(p.X, groundY(p.X, p.Z) + 1.2, p.Z)
			dots[i].Transparency = 0.15
			i += 1
			t += DOT_GAP
		end
		carry = t - len
		if i > DOT_COUNT then
			break
		end
	end
	for k = i, DOT_COUNT do
		dots[k].Transparency = 1
	end
end

local function route()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not target then
		hideRoute()
		return
	end
	local here = Vector3.new(root.Position.X, 0, root.Position.Z)
	local dest = Vector3.new(target.pos.X, 0, target.pos.Z)
	local points
	if graphReady and (dest - here).Magnitude > 120 then
		local path = RoadGraph.Path(here, dest)
		if path and #path > 0 then
			points = { here }
			for _, p in ipairs(path) do
				table.insert(points, Vector3.new(p.X, 0, p.Z))
			end
			table.insert(points, dest)
		end
	end
	lastPoints = points or { here, dest }
	drawRoute(lastPoints)
end

function GPSClient.SetTarget(name, pos)
	target = { name = name, pos = pos }
	pillar.Position = Vector3.new(pos.X, 200, pos.Z)
	pillar.Transparency = 0.55
	label.Visible = true
	lastRoute = 0
end

function GPSClient.Clear()
	target = nil
	pillar.Transparency = 1
	label.Visible = false
	lastPoints = nil
	hideRoute()
end

function GPSClient.Target()
	return target and target.name or nil
end

function GPSClient.TargetPos()
	return target and target.pos or nil
end

function GPSClient.RoutePoints()
	return target and lastPoints or nil
end

function GPSClient.Init()
	build()
	player:GetAttributeChangedSignal("Side"):Connect(function()
		GPSClient.Clear()
	end)
	-- A boat called from far away waits at the marina: route there.
	task.spawn(function()
		require(ReplicatedStorage.Shared.Util.Remotes).Event("BoatDelivered").OnClientEvent:Connect(function(info)
			GPSClient.SetTarget("Your " .. (info.Name or "boat"), info.Pos)
			NotifyController.Show("Your " .. (info.Name or "boat") .. " is waiting at the marina. Follow the GPS!", PINK)
		end)
	end)
	task.spawn(function()
		for _ = 1, 60 do
			if RoadGraph.LoadPublished() then
				graphReady = true
				return
			end
			task.wait(1)
		end
	end)
	RunService.Heartbeat:Connect(function()
		if not target then
			return
		end
		local dist = GPSClient.Distance(target.pos)
		if dist then
			label.Text = "📍 " .. target.name .. "  ·  " .. GPSClient.FormatDistance(dist)
			if dist < ARRIVE then
				NotifyController.Show("You've arrived: " .. target.name, PINK)
				GPSClient.Clear()
				return
			end
		end
		if os.clock() - lastRoute > 1 then
			lastRoute = os.clock()
			route()
		end
	end)
end

return GPSClient
