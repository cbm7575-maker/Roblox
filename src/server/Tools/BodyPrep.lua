-- BodyPrep (ModuleScript, ServerStorage.Tools.BodyPrep) - Studio edit-time tool, never runs in game.
-- Turns a generated, segmented car mesh (generate_mesh with parts body, wheels, windows, headlights,
-- taillights, bumpers) into a CarBuilder body in ServerStorage.CarBodies:
--   * parts renamed Body / Wheels / Windows / Headlight / Taillight / Trim, flattened into one model
--   * front turned to -Z (worked out from the headlights vs taillights)
--   * pivot at the point between the four wheel centres
--   * uniformly scaled so the body is a little wider than the car's chassis (Config.Vehicles size);
--     the mesh's own wheel layout is saved as attributes WheelX, WheelZ, WheelRadius so CarBuilder
--     can move the spinning visual wheels into its wheel arches
--   * box collision (the chassis does the physics; the body is visual only)
-- Usage (command bar / MCP):  require(ServerStorage.Tools.BodyPrep).Prepare(model, "Flamingo", opts)
--   opts: Turn (degrees, fix facing), Scale (extra multiplier), ExtraWidth (studs over chassis), SeatDrop
--   Boats: opts.Boat = true (no wheels; pivot at the hull bottom; scaled to the chassis length; Draft,
--   SeatY, SeatZ saved for CarBuilder)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- A fresh copy each time: this tool runs in Studio's edit session, where a plain require would keep
-- returning the config as it was when first loaded.
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles:Clone())

local BodyPrep = {}

local NAMES = {
	{ "headlight", "Headlight" }, { "taillight", "Taillight" }, { "window", "Windows" },
	{ "wheel", "Wheels" }, { "bumper", "Trim" }, { "body", "Body" },
}

function BodyPrep.Prepare(model, carId, opts)
	opts = opts or {}
	local cfg = Vehicles.Resolve(carId)
	assert(cfg, "unknown car " .. tostring(carId))
	local parts = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local lower = p.Name:lower()
			for _, pair in ipairs(NAMES) do
				if lower:find(pair[1]) then
					p.Name = pair[2]
					break
				end
			end
			p.Anchored = true
			p.CanCollide = false
			pcall(function()
				p.CollisionFidelity = Enum.CollisionFidelity.Box
			end)
			parts[p.Name] = p
			p.Parent = model
		end
	end
	for _, c in ipairs(model:GetChildren()) do
		if c:IsA("Model") then
			c:Destroy()
		end
	end
	local body = parts.Body or model:FindFirstChildWhichIsA("BasePart")
	local wheels = parts.Wheels
	-- Car frame: up = world up, forward = taillights -> headlights (or the body's +Z if missing).
	local forward
	if parts.Headlight and parts.Taillight then
		forward = (parts.Headlight.Position - parts.Taillight.Position) * Vector3.new(1, 0, 1)
	end
	if not forward or forward.Magnitude < 0.5 then
		forward = -body.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	forward = forward.Unit
	-- Snap to the body part's own axes (generated meshes are axis-aligned in their part space).
	local rot = body.CFrame - body.CFrame.Position
	local candidates = { rot.LookVector, -rot.LookVector, rot.RightVector, -rot.RightVector }
	local best, bestDot = forward, -2
	for _, c in ipairs(candidates) do
		local flat = (c * Vector3.new(1, 0, 1))
		if flat.Magnitude > 0.5 and flat.Unit:Dot(forward) > bestDot then
			best, bestDot = flat.Unit, flat.Unit:Dot(forward)
		end
	end
	-- opts.Turn (degrees): fix a body whose lights fooled the facing check (e.g. 90 or 180).
	if opts.Turn then
		best = CFrame.Angles(0, math.rad(opts.Turn), 0):VectorToWorldSpace(best)
	end
	local frame = CFrame.lookAt(Vector3.zero, best)
	-- Wheel centres: the Wheels part's centre, or the body's bottom + a wheel radius.
	if opts.Boat then
		-- Boats: pivot at the bottom centre, scaled to the chassis length (+1).
		model.WorldPivot = frame + (model:GetBoundingBox()).Position
		model:PivotTo(CFrame.new())
		local _, raw = model:GetBoundingBox()
		local scale = (opts.Scale or 1) * (cfg.Size.Z + 1) / raw.Z
		model:ScaleTo(model:GetScale() * scale)
		model:PivotTo(CFrame.new())
		local cf2, size2 = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(cf2.Position - Vector3.new(0, size2.Y / 2, 0))
		model:PivotTo(CFrame.new())
		model:SetAttribute("Boat", true)
		for _, key in ipairs({ "Draft", "SeatY", "SeatZ" }) do
			if opts[key] then
				model:SetAttribute(key, opts[key])
			end
		end
		local folder = ServerStorage:FindFirstChild("CarBodies") or Instance.new("Folder")
		folder.Name = "CarBodies"
		folder.Parent = ServerStorage
		local old = folder:FindFirstChild(carId)
		if old and old ~= model then
			old:Destroy()
		end
		model.Name = carId
		model.Parent = folder
		return string.format("%s (boat): scale %.2f, size %.1f x %.1f x %.1f (chassis %.1f x %.1f)", carId, scale,
			size2.X, size2.Y, size2.Z, cfg.Size.X, cfg.Size.Z)
	end
	local centre, wheelX, wheelZ, radius
	if wheels then
		centre = wheels.Position
		local size = frame:VectorToObjectSpace(wheels.CFrame:VectorToWorldSpace(wheels.Size))
		local w, h, len = math.abs(size.X), math.abs(size.Y), math.abs(size.Z)
		radius = h / 2
		wheelZ = len / 2 - radius
		wheelX = w / 2 - math.min(radius * 0.45, w * 0.1)
	else
		local cf, size = model:GetBoundingBox()
		centre = cf.Position - Vector3.new(0, size.Y / 2 - size.Y * 0.12, 0)
		radius = size.Y * 0.12
		wheelZ = size.Z * 0.33
		wheelX = size.X * 0.42
	end
	model.WorldPivot = CFrame.new(centre) * frame
	model:PivotTo(CFrame.new())
	local _, raw = model:GetBoundingBox()
	local scale = (opts.Scale or 1) * (cfg.Size.X + (opts.ExtraWidth or 0.6)) / raw.X
	model:ScaleTo(model:GetScale() * scale)
	model:PivotTo(CFrame.new())
	model:SetAttribute("WheelX", wheelX * scale)
	model:SetAttribute("WheelZ", wheelZ * scale)
	model:SetAttribute("WheelRadius", radius * scale)
	if opts.SeatDrop then
		model:SetAttribute("SeatDrop", opts.SeatDrop)
	end
	local folder = ServerStorage:FindFirstChild("CarBodies") or Instance.new("Folder")
	folder.Name = "CarBodies"
	folder.Parent = ServerStorage
	local old = folder:FindFirstChild(carId)
	if old and old ~= model then
		old:Destroy()
	end
	model.Name = carId
	model.Parent = folder
	local _, size = model:GetBoundingBox()
	return string.format("%s: scale %.2f, size %.1f x %.1f x %.1f (car %.1f x %.1f), wheels x%.1f z%.1f r%.2f",
		carId, scale, size.X, size.Y, size.Z, cfg.Size.X, cfg.Size.Z, wheelX * scale, wheelZ * scale, radius * scale)
end

-- Boats, second pass: turn the prepared body by `yaw` degrees about its pivot (so the bow faces -Z),
-- then stretch it to exactly (chassis width + 1) x (chassis length + 1), height scaled by the average.
-- Mesh parts are resized along their own axes, so any 90-degree part rotation is handled.
function BodyPrep.FixBoat(model, carId, yaw)
	local cfg = Vehicles.Resolve(carId)
	model:PivotTo(CFrame.Angles(0, math.rad(yaw or 0), 0))
	model.WorldPivot = CFrame.new(model:GetPivot().Position)
	model:PivotTo(CFrame.new())
	local cf, raw = model:GetBoundingBox()
	local sx, sz = (cfg.Size.X + 1) / raw.X, (cfg.Size.Z + 1) / raw.Z
	local sy = (sx + sz) / 2
	local centre = cf.Position
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local r, u, l = p.CFrame.RightVector, p.CFrame.UpVector, p.CFrame.LookVector
			local function k(v)
				return math.abs(v.X) * sx + math.abs(v.Y) * sy + math.abs(v.Z) * sz
			end
			local rel = p.Position - centre
			local rot = p.CFrame - p.Position
			p.Size = Vector3.new(p.Size.X * k(r), p.Size.Y * k(u), p.Size.Z * k(l))
			p.CFrame = CFrame.new(centre + Vector3.new(rel.X * sx, rel.Y * sy, rel.Z * sz)) * rot
		end
	end
	local cf2, size2 = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(cf2.Position - Vector3.new(0, size2.Y / 2, 0))
	model:PivotTo(CFrame.new())
	return string.format("%s fixed: %.1f x %.1f x %.1f", carId, size2.X, size2.Y, size2.Z)
end

return BodyPrep
