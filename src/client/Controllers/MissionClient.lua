-- MissionClient (ModuleScript, StarterPlayerScripts.Controllers.MissionClient)
-- Phone missions on screen: a banner with the current step and time left, a QUIT button, the GPS
-- routed to the current target, glowing markers for "collect" points, and DONE / FAILED stamps.
-- Started from the phone's JOBS app (RequestMission "Start"); the server runs everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Missions = require(ReplicatedStorage.Shared.Config.Missions)
local Remotes = require(ReplicatedStorage.Shared.Util.Remotes)
local GPSClient = require(script.Parent:WaitForChild("GPSClient"))
local HUDController = require(script.Parent:WaitForChild("HUDController"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

local player = Players.LocalPlayer

local MissionClient = {}

local MINT = Color3.fromRGB(110, 242, 196)
local GOLD = Color3.fromRGB(255, 214, 10)
local DARK = Color3.fromRGB(18, 14, 30)
local FONT = Enum.Font.FredokaOne

local banner, bannerText, quit
local markers = {}
local state -- decoded "Mission" attribute
local lastTarget

local function clearMarkers()
	for _, m in ipairs(markers) do
		m:Destroy()
	end
	table.clear(markers)
end

local function marker(pos)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(3, 3, 3)
	p.Material = Enum.Material.Neon
	p.Color = MINT
	p.Position = Vector3.new(pos.X, 2.5, pos.Z)
	p.Parent = Workspace.CurrentCamera
	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Size = Vector3.new(1.2, 60, 1.2)
	beam.Material = Enum.Material.Neon
	beam.Color = MINT
	beam.Transparency = 0.5
	beam.Position = Vector3.new(pos.X, 32, pos.Z)
	beam.Parent = Workspace.CurrentCamera
	table.insert(markers, p)
	table.insert(markers, beam)
end

local function refresh()
	local raw = player:GetAttribute("Mission")
	if not raw then
		state = nil
		banner.Visible = false
		clearMarkers()
		if lastTarget then
			lastTarget = nil
			GPSClient.Clear()
		end
		return
	end
	local ok, s = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not ok then
		return
	end
	state = s
	banner.Visible = true
	local m = Missions.ById[s.id]
	local step = m and m.Steps[s.step]
	if not step then
		return
	end
	clearMarkers()
	local target
	if step.Kind == "Collect" then
		local got = {}
		for _, i in ipairs(s.got or {}) do
			got[i] = true
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local best, bestD
		for i, p in ipairs(step.Points) do
			if not got[i] then
				marker(p)
				local d = root and (p - root.Position).Magnitude or 0
				if not bestD or d < bestD then
					best, bestD = p, d
				end
			end
		end
		target = best
	else
		target = step.Pos
		marker(step.Pos)
	end
	if target and target ~= lastTarget then
		lastTarget = target
		GPSClient.SetTarget(m.Name, target)
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Mission"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")
	banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 98)
	banner.Size = UDim2.new(1, -420, 0, 40)
	banner.BackgroundColor3 = DARK
	banner.BackgroundTransparency = 0.15
	banner.Visible = false
	banner.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = banner
	local st = Instance.new("UIStroke")
	st.Color = MINT
	st.Thickness = 2
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = banner
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(520, 40)
	limit.Parent = banner
	bannerText = Instance.new("TextLabel")
	bannerText.BackgroundTransparency = 1
	bannerText.Position = UDim2.fromOffset(16, 7)
	bannerText.Size = UDim2.new(1, -100, 0, 26)
	bannerText.Font = FONT
	bannerText.TextScaled = true
	bannerText.TextColor3 = Color3.new(1, 1, 1)
	bannerText.TextXAlignment = Enum.TextXAlignment.Left
	bannerText.RichText = true
	bannerText.Parent = banner
	quit = Instance.new("TextButton")
	quit.Name = "Quit"
	quit.AnchorPoint = Vector2.new(1, 0.5)
	quit.Position = UDim2.new(1, -8, 0.5, 0)
	quit.Size = UDim2.fromOffset(70, 28)
	quit.BackgroundColor3 = Color3.fromRGB(90, 70, 130)
	quit.Font = FONT
	quit.TextScaled = true
	quit.TextColor3 = Color3.new(1, 1, 1)
	quit.Text = "QUIT"
	quit.Parent = banner
	local qc = Instance.new("UICorner")
	qc.CornerRadius = UDim.new(0.5, 0)
	qc.Parent = quit
	local qp = Instance.new("UIPadding")
	qp.PaddingTop, qp.PaddingBottom = UDim.new(0, 5), UDim.new(0, 5)
	qp.Parent = quit
	quit.Activated:Connect(function()
		Remotes.Event("RequestMission"):FireServer("Quit")
	end)
end

function MissionClient.Init()
	build()
	refresh()
	player:GetAttributeChangedSignal("Mission"):Connect(refresh)
	task.spawn(function()
		Remotes.OnClient("CarMeetResult", function(info)
		if info.Favourite then
			HUDController.Stamp("CROWD FAVOURITE!", "Best ride at the car meet  +" .. HUDController.Money(info.Bonus), GOLD)
		end
	end)
	Remotes.OnClient("MissionEvent", function(kind, info)
			if kind == "Started" then
				HUDController.Stamp("MISSION: " .. string.upper(info.Name), info.Text, MINT)
			elseif kind == "Step" then
				NotifyController.Show("Next: " .. info.Text, MINT)
			elseif kind == "Done" then
				HUDController.Stamp("MISSION COMPLETE", "+" .. HUDController.Money(info.Cash) .. "  +" .. info.XP .. " XP"
					.. (info.First and "" or "  (repeat pay)"), GOLD)
			elseif kind == "Failed" then
				HUDController.Stamp("MISSION FAILED", info.Reason, Color3.fromRGB(255, 90, 90))
			end
		end)
	end)
	-- Banner text + countdown.
	RunService.Heartbeat:Connect(function()
		if not state then
			return
		end
		local m = Missions.ById[state.id]
		local step = m and m.Steps[state.step]
		if not step then
			return
		end
		local left = math.max(0, state.deadline - Workspace:GetServerTimeNow())
		local extra = ""
		if step.Kind == "Collect" then
			extra = string.format(" (%d/%d)", #(state.got or {}), #step.Points)
		end
		bannerText.Text = string.format('<font color="#6EF2C4">%s</font>  %s%s  ·  %d:%02d', string.upper(m.Name), step.Text, extra,
			left // 60, left % 60)
	end)
end

return MissionClient
