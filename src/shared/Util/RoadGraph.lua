-- RoadGraph (ModuleScript, ReplicatedStorage.Shared.Util.RoadGraph)
-- A graph of Port Solana's roads, built from the road parts in Workspace.City.Roads:
-- nodes at every road end and crossing, edges along the roads. Used by the AI police now, and later
-- by GPS routes, ambient traffic and taxi jobs.
--   Server: RoadGraph.BuildFromWorld() once, then RoadGraph.Publish() (JSON on ReplicatedStorage).
--   Client: RoadGraph.LoadPublished() (roads far away may not be streamed in, so build on the server).
--   RoadGraph.Path(fromPos, toPos) -> { Vector3 } waypoints along roads (A*), or nil.
--   RoadGraph.Nearest(pos) -> node index, distance.
--   RoadGraph.Width(i, j) -> width in studs of the road between two linked nodes (for traffic lanes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local RoadGraph = {}

local SNAP = 10 -- studs: points closer than this merge into one node
local SKIP = { Pier = true, FerrisPier = true } -- dead-end decks, not roads

RoadGraph.Nodes = {} -- [i] = Vector3 (y = 0)
RoadGraph.Edges = {} -- [i] = { [j] = length }
RoadGraph.Widths = {} -- [i] = { [j] = road width }

local function addNode(p)
	for i, n in ipairs(RoadGraph.Nodes) do
		if (n - p).Magnitude < SNAP then
			return i
		end
	end
	table.insert(RoadGraph.Nodes, p)
	RoadGraph.Edges[#RoadGraph.Nodes] = {}
	RoadGraph.Widths[#RoadGraph.Nodes] = {}
	return #RoadGraph.Nodes
end

local function link(a, b, width)
	if a == b then
		return
	end
	local d = (RoadGraph.Nodes[a] - RoadGraph.Nodes[b]).Magnitude
	RoadGraph.Edges[a][b] = d
	RoadGraph.Edges[b][a] = d
	local w = math.max(RoadGraph.Widths[a][b] or 0, width or 30)
	RoadGraph.Widths[a][b] = w
	RoadGraph.Widths[b][a] = w
end

function RoadGraph.Width(i, j)
	return RoadGraph.Widths[i] and RoadGraph.Widths[i][j] or 30
end

-- 2D (x, z) segment intersection; returns the point or nil.
local function intersect(p1, p2, q1, q2)
	local r = Vector2.new(p2.X - p1.X, p2.Z - p1.Z)
	local s = Vector2.new(q2.X - q1.X, q2.Z - q1.Z)
	local denom = r.X * s.Y - r.Y * s.X
	if math.abs(denom) < 1e-6 then
		return nil
	end
	local qp = Vector2.new(q1.X - p1.X, q1.Z - p1.Z)
	local t = (qp.X * s.Y - qp.Y * s.X) / denom
	local u = (qp.X * r.Y - qp.Y * r.X) / denom
	local eps = 0.02
	if t < -eps or t > 1 + eps or u < -eps or u > 1 + eps then
		return nil
	end
	return Vector3.new(p1.X + r.X * t, 0, p1.Z + r.Y * t)
end

function RoadGraph.BuildFromWorld()
	RoadGraph.Nodes, RoadGraph.Edges, RoadGraph.Widths = {}, {}, {}
	local roads = Workspace:FindFirstChild("City") and Workspace.City:FindFirstChild("Roads")
	if not roads then
		return 0
	end
	local segs = {}
	for _, part in ipairs(roads:GetChildren()) do
		if part:IsA("BasePart") and not SKIP[part.Name] then
			local look = part.CFrame.LookVector * Vector3.new(1, 0, 1)
			look = look.Magnitude > 0 and look.Unit or Vector3.new(0, 0, 1)
			-- CityGen lengthens each road by half its width so joints overlap; undo that.
			local len = part.Size.Z - part.Size.X * 0.5
			local c = Vector3.new(part.Position.X, 0, part.Position.Z)
			table.insert(segs, { a = c - look * len / 2, b = c + look * len / 2, w = part.Size.X })
		end
	end
	-- Every point on each segment: its ends plus crossings with every other segment.
	for i, sg in ipairs(segs) do
		sg.points = { sg.a, sg.b }
		for j, other in ipairs(segs) do
			if i ~= j then
				local p = intersect(sg.a, sg.b, other.a, other.b)
				if p then
					table.insert(sg.points, p)
				end
			end
		end
		local dir = sg.b - sg.a
		table.sort(sg.points, function(p, q)
			return (p - sg.a):Dot(dir) < (q - sg.a):Dot(dir)
		end)
		local prev
		for _, p in ipairs(sg.points) do
			local id = addNode(p)
			if prev then
				link(prev, id, sg.w)
			end
			prev = id
		end
	end
	return #RoadGraph.Nodes
end

function RoadGraph.Publish()
	local nodes, edges, widths = {}, {}, {}
	for i, n in ipairs(RoadGraph.Nodes) do
		nodes[i] = { math.floor(n.X * 10) / 10, math.floor(n.Z * 10) / 10 }
		local list, wl = {}, {}
		for j in pairs(RoadGraph.Edges[i]) do
			table.insert(list, j)
			table.insert(wl, RoadGraph.Width(i, j))
		end
		edges[i] = list
		widths[i] = wl
	end
	ReplicatedStorage:SetAttribute("RoadGraph", HttpService:JSONEncode({ n = nodes, e = edges, w = widths }))
end

function RoadGraph.LoadPublished()
	local raw = ReplicatedStorage:GetAttribute("RoadGraph")
	if not raw then
		return false
	end
	local data = HttpService:JSONDecode(raw)
	RoadGraph.Nodes, RoadGraph.Edges, RoadGraph.Widths = {}, {}, {}
	for i, n in ipairs(data.n) do
		RoadGraph.Nodes[i] = Vector3.new(n[1], 0, n[2])
		RoadGraph.Edges[i] = {}
		RoadGraph.Widths[i] = {}
	end
	for i, list in ipairs(data.e) do
		for k, j in ipairs(list) do
			RoadGraph.Edges[i][j] = (RoadGraph.Nodes[i] - RoadGraph.Nodes[j]).Magnitude
			RoadGraph.Widths[i][j] = data.w and data.w[i] and data.w[i][k] or 30
		end
	end
	return true
end

function RoadGraph.Nearest(pos)
	local best, bestD
	local flat = Vector3.new(pos.X, 0, pos.Z)
	for i, n in ipairs(RoadGraph.Nodes) do
		local d = (n - flat).Magnitude
		if not bestD or d < bestD then
			best, bestD = i, d
		end
	end
	return best, bestD
end

-- A* over the road graph. Returns waypoints (Vector3, y = 0) from near `fromPos` to near `toPos`.
function RoadGraph.Path(fromPos, toPos)
	local start = RoadGraph.Nearest(fromPos)
	local goal = RoadGraph.Nearest(toPos)
	if not start or not goal then
		return nil
	end
	local nodes, edges = RoadGraph.Nodes, RoadGraph.Edges
	local open = { [start] = true }
	local came = {}
	local g = { [start] = 0 }
	local f = { [start] = (nodes[start] - nodes[goal]).Magnitude }
	local steps = 0
	while next(open) do
		steps += 1
		if steps > 5000 then
			return nil
		end
		local current, bestF
		for i in pairs(open) do
			if not bestF or f[i] < bestF then
				current, bestF = i, f[i]
			end
		end
		if current == goal then
			local path = { nodes[current] }
			while came[current] do
				current = came[current]
				table.insert(path, 1, nodes[current])
			end
			return path
		end
		open[current] = nil
		for nb, len in pairs(edges[current]) do
			local tentative = g[current] + len
			if not g[nb] or tentative < g[nb] then
				came[nb] = current
				g[nb] = tentative
				f[nb] = tentative + (nodes[nb] - nodes[goal]).Magnitude
				open[nb] = true
			end
		end
	end
	return nil
end

return RoadGraph
