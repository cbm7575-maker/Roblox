-- RoadGraph (ModuleScript, ReplicatedStorage.Shared.Util.RoadGraph)
-- A graph of Port Solana's roads, built from the road parts in Workspace.City.Roads:
-- nodes at every road end and crossing, edges along the roads. Used by the AI police now, and later
-- by GPS routes, ambient traffic and taxi jobs.
--   Server: RoadGraph.BuildFromWorld() once, then RoadGraph.Publish() (JSON on ReplicatedStorage).
--   Client: RoadGraph.LoadPublished() (roads far away may not be streamed in, so build on the server).
--   RoadGraph.Path(fromPos, toPos) -> { Vector3 } waypoints along roads (A*), or nil.
--   RoadGraph.Nearest(pos) -> node index, distance.
--   RoadGraph.Width(i, j) -> width in studs of the road between two linked nodes (for traffic lanes).
-- Helpers for the AI police (read-only maths over the graph; the published graph is unchanged):
--   RoadGraph.Samples(spacing) -> { { pos, dir, width, a, b, node? } } points every ~spacing studs along
--     every road (nodes included), cached until the graph is rebuilt.
--   RoadGraph.Within(center, maxR, minR, spacing) -> the samples in that ring (flat distance).
--   RoadGraph.NearestEdge(pos, heading) -> i, j, point, distance (the road under pos).
--   RoadGraph.Ahead(pos, heading, minDist, maxDist) -> road spots that far ahead along the roads,
--     straightest routes first: { { pos, dir, width, node?, bend } }.

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

local samplesCache = {} -- [spacing] = list (see RoadGraph.Samples)

function RoadGraph.BuildFromWorld()
	RoadGraph.Nodes, RoadGraph.Edges, RoadGraph.Widths = {}, {}, {}
	samplesCache = {}
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
	samplesCache = {}
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

-- Points every ~spacing studs along every road, plus every node. Each: { pos (y = 0), dir (unit, along
-- the road a -> b), width, a, b, node = index for nodes }.
function RoadGraph.Samples(spacing)
	spacing = spacing or 60
	local cached = samplesCache[spacing]
	if cached then
		return cached
	end
	local list = {}
	local nodes = RoadGraph.Nodes
	for i, edges in pairs(RoadGraph.Edges) do
		local first, widest = nil, 0
		for j, len in pairs(edges) do
			first = first or j
			widest = math.max(widest, RoadGraph.Width(i, j))
			if i < j and len > 1 then
				local a = nodes[i]
				local dir = (nodes[j] - a) / len
				local n = math.max(1, math.floor(len / spacing + 0.5))
				for k = 1, n - 1 do
					table.insert(list, { pos = a + dir * (len * k / n), dir = dir, width = RoadGraph.Width(i, j), a = i, b = j })
				end
			end
		end
		if first and (nodes[first] - nodes[i]).Magnitude > 0.01 then
			table.insert(list, { pos = nodes[i], dir = (nodes[first] - nodes[i]).Unit, width = widest, a = i, b = first, node = i })
		end
	end
	samplesCache[spacing] = list
	return list
end

-- Samples between minR and maxR studs (flat) from center.
function RoadGraph.Within(center, maxR, minR, spacing)
	local out = {}
	local cx, cz = center.X, center.Z
	local hi, lo = maxR * maxR, (minR or 0) * (minR or 0)
	for _, s in ipairs(RoadGraph.Samples(spacing)) do
		local dx, dz = s.pos.X - cx, s.pos.Z - cz
		local d2 = dx * dx + dz * dz
		if d2 <= hi and d2 >= lo then
			table.insert(out, s)
		end
	end
	return out
end

-- The road edge nearest to pos: i, j (i < j), the closest point on it (y = 0) and the distance.
-- With a heading (flat unit vector), roads running that way win at crossings.
function RoadGraph.NearestEdge(pos, heading)
	local nodes = RoadGraph.Nodes
	local best, bi, bj, bp, bd
	local px, pz = pos.X, pos.Z
	for i, edges in pairs(RoadGraph.Edges) do
		for j, len in pairs(edges) do
			if i < j and len > 1 then
				local a, b = nodes[i], nodes[j]
				local abx, abz = b.X - a.X, b.Z - a.Z
				local t = math.clamp(((px - a.X) * abx + (pz - a.Z) * abz) / (len * len), 0, 1)
				local qx, qz = a.X + abx * t, a.Z + abz * t
				local d = math.sqrt((px - qx) ^ 2 + (pz - qz) ^ 2)
				local score = d
				if heading then
					score += (1 - math.abs((abx * heading.X + abz * heading.Z) / len)) * 20
				end
				if not best or score < best then
					best, bi, bj, bp, bd = score, i, j, Vector3.new(qx, 0, qz), d
				end
			end
		end
	end
	return bi, bj, bp, bd
end

-- Road spots minDist..maxDist studs of driving ahead of someone at pos heading along `heading` (flat
-- unit vector): follows their road, then every branch that doesn't turn back. Crossings in that band
-- come back as nodes; a long road through the band gives a point on it. Straightest routes first.
-- Each: { pos (y = 0), dir (unit, the way they would be driving), width, node = index or nil, bend }.
function RoadGraph.Ahead(pos, heading, minDist, maxDist)
	local out = {}
	local i, j, p = RoadGraph.NearestEdge(pos, heading)
	if not i or not j or not p then
		return out
	end
	local nodes, edges = RoadGraph.Nodes, RoadGraph.Edges
	local from, to = i, j
	if (nodes[j] - nodes[i]):Dot(heading) < 0 then
		from, to = j, i
	end
	local mid = (minDist + maxDist) / 2
	local seen = {}
	-- `startD`/`endD`: driving distance at the start and end of the edge prev -> node.
	local function walk(prev, node, startD, endD, dir, bend, depth)
		if endD > maxDist then
			-- The band ends inside this edge: a point on the road, clear of the crossing it starts at
			-- (that crossing is already in the list when it's in the band).
			local lo = math.max(minDist, startD + 25)
			if lo <= maxDist then
				local at = math.clamp(mid, lo, maxDist)
				table.insert(out, { pos = nodes[node] - dir * (endD - at), dir = dir, width = RoadGraph.Width(prev, node), bend = bend })
			end
			return
		end
		if endD >= minDist and not seen[node] then
			seen[node] = true
			table.insert(out, { pos = nodes[node], dir = dir, width = RoadGraph.Width(prev, node), node = node, bend = bend })
		end
		if depth >= 8 then
			return
		end
		for nb, len in pairs(edges[node]) do
			if nb ~= prev and len > 1 then
				local d = (nodes[nb] - nodes[node]) / len
				local turn = d:Dot(dir)
				if turn > -0.2 then
					walk(node, nb, endD, endD + len, d, bend + (1 - turn), depth + 1)
				end
			end
		end
	end
	local first = nodes[to] - nodes[from]
	if first.Magnitude < 1 then
		return out
	end
	walk(from, to, 0, (nodes[to] - p).Magnitude, first.Unit, 0, 0)
	table.sort(out, function(a, b)
		return a.bend < b.bend
	end)
	return out
end

return RoadGraph
