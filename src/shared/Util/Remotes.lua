-- Remotes (ModuleScript, ReplicatedStorage.Shared.Util.Remotes)
-- The server creates remotes on first use; clients wait for them.
-- Every remote is a request the server validates, never an order.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local folder = ReplicatedStorage:WaitForChild("Remotes")

local function get(className, name)
	local r = folder:FindFirstChild(name)
	if r then
		return r
	end
	if RunService:IsServer() then
		r = Instance.new(className)
		r.Name = name
		r.Parent = folder
		return r
	end
	return folder:WaitForChild(name)
end

function Remotes.Event(name)
	return get("RemoteEvent", name)
end

-- Client: listen to a server event without blocking the caller (the wait for the remote runs in its
-- own thread, so one missing remote can never stop the other controllers from starting).
function Remotes.OnClient(name, fn)
	task.spawn(function()
		get("RemoteEvent", name).OnClientEvent:Connect(fn)
	end)
end

function Remotes.Function(name)
	return get("RemoteFunction", name)
end

return Remotes
