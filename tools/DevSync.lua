-- DevSync (ModuleScript, ServerStorage.Tools.DevSync). Studio-only helper.
-- Pulls scripts from the local project folder (python http.server on 127.0.0.1:34999)
-- using manifest.json, and creates or updates each script. Never deletes anything.
-- Usage from the MCP: require(game.ServerStorage.Tools.DevSync).Run()

local HttpService = game:GetService("HttpService")

local BASE = "http://127.0.0.1:34999/"
local DevSync = {}

local function resolve(path)
	local node = game
	for seg in string.gmatch(path, "[^%.]+") do
		local child = node:FindFirstChild(seg)
		if not child then
			if node == game then
				child = game:GetService(seg)
			else
				child = Instance.new("Folder")
				child.Name = seg
				child.Parent = node
			end
		end
		node = child
	end
	return node
end

function DevSync.Run(only)
	local manifest = HttpService:JSONDecode(HttpService:GetAsync(BASE .. "manifest.json", true))
	local report = {}
	for _, e in ipairs(manifest) do
		if not only or string.find(e.file, only, 1, true) then
			local parent = resolve(e.parent)
			local script = parent:FindFirstChild(e.name)
			if script and script:GetAttribute("SyncSha") == e.sha then
				continue
			end
			local source = HttpService:GetAsync(BASE .. e.file, true)
			if script and script.ClassName ~= e.class then
				table.insert(report, "SKIP (class mismatch) " .. e.file)
				continue
			end
			local created = false
			if not script then
				script = Instance.new(e.class)
				script.Name = e.name
				created = true
			end
			script.Source = source
			script:SetAttribute("SyncSha", e.sha)
			script.Parent = parent
			table.insert(report, (created and "NEW " or "UPD ") .. e.parent .. "." .. e.name)
		end
	end
	if #report == 0 then
		return "Nothing changed"
	end
	return table.concat(report, "\n")
end

return DevSync
