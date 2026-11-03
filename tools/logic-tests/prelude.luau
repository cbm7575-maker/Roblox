-- Minimal Roblox stand-ins with a virtual clock, for logic tests of DataService and ShopService.
local now = 0
local queue = {}
local function schedule(at, co, ...)
	table.insert(queue, { at = at, co = co, args = table.pack(...) })
end
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		print("ERROR in coroutine: " .. tostring(err))
		ERRORS = (ERRORS or 0) + 1
	end
end
task = {}
function task.wait(s)
	s = s or 0.03
	local co = coroutine.running()
	schedule(now + s, co, s)
	return coroutine.yield()
end
function task.spawn(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.delay(s, fn, ...)
	local co = coroutine.create(fn)
	schedule(now + s, co, ...)
	return co
end
-- Run the scheduler until `until_` (virtual seconds).
function runUntil(until_)
	while true do
		table.sort(queue, function(a, b)
			return a.at < b.at
		end)
		local item = queue[1]
		if not item or item.at > until_ then
			break
		end
		table.remove(queue, 1)
		now = item.at
		resume(item.co, table.unpack(item.args, 1, item.args.n))
	end
	now = math.max(now, until_)
end
function clock()
	return now
end
local realOs = os
os = setmetatable({
	time = function()
		return 1700000000 + math.floor(now)
	end,
	clock = function()
		return now
	end,
}, { __index = realOs })
LOG = {}
function warn(...)
	local parts = {}
	for _, v in ipairs({ ... }) do
		table.insert(parts, tostring(v))
	end
	table.insert(LOG, table.concat(parts, " "))
end

local function signal()
	local s = { fns = {} }
	function s:Connect(fn)
		table.insert(self.fns, fn)
		return { Disconnect = function() end }
	end
	function s:Fire(...)
		for _, fn in ipairs(self.fns) do
			task.spawn(fn, ...)
		end
	end
	return s
end
newSignal = signal

local function attrs(obj)
	obj._attrs = {}
	function obj:GetAttribute(k)
		return self._attrs[k]
	end
	function obj:SetAttribute(k, v)
		self._attrs[k] = v
	end
	return obj
end

-- Players
Players = attrs({ PlayerAdded = signal(), PlayerRemoving = signal(), list = {} })
function Players:GetPlayers()
	local out = {}
	for _, p in ipairs(self.list) do
		table.insert(out, p)
	end
	return out
end
function Players:GetPlayerByUserId(id)
	for _, p in ipairs(self.list) do
		if p.UserId == id then
			return p
		end
	end
	return nil
end
function newPlayer(id)
	local p = attrs({ UserId = id, Name = "P" .. id, Parent = Players, kicked = nil })
	function p:Kick(msg)
		self.kicked = msg
	end
	function p:FindFirstChild()
		return nil
	end
	return p
end
function join(p)
	table.insert(Players.list, p)
	Players.PlayerAdded:Fire(p)
end
function leave(p)
	for i, q in ipairs(Players.list) do
		if q == p then
			table.remove(Players.list, i)
		end
	end
	p.Parent = nil
	Players.PlayerRemoving:Fire(p)
end

-- A DataStore with per-call latency, scripted failures and a write log.
local function deepcopy(t)
	if type(t) ~= "table" then
		return t
	end
	local c = {}
	for k, v in pairs(t) do
		c[k] = deepcopy(v)
	end
	return c
end
STORE = { data = {}, writes = {}, failNext = 0, latency = 0.2 }
function STORE:UpdateAsync(key, fn)
	task.wait(self.latency)
	if self.failNext > 0 then
		self.failNext -= 1
		error("DataStore request failed (scripted)")
	end
	local new = fn(deepcopy(self.data[key]))
	if new ~= nil then
		self.data[key] = deepcopy(new)
		table.insert(self.writes, { key = key, t = now, lock = new.lock and new.lock.job or "released", cash = new.cash })
	end
	return deepcopy(self.data[key])
end
function STORE:GetAsync(key)
	return deepcopy(self.data[key])
end

local closeFns = {}
function runClose()
	for _, fn in ipairs(closeFns) do
		task.spawn(fn)
	end
end

local services = {}
local function svc(name, t)
	services[name] = t
	return t
end
svc("Players", Players)
svc("DataStoreService", { GetDataStore = function()
	return STORE
end })
svc("HttpService", { GenerateGUID = function()
	return "guid"
end })
svc("ReplicatedStorage", attrs({}))
svc("RunService", { IsStudio = function()
	return false
end })
ECON = { __module = true }
function ECON.GetCash(p)
	return p:GetAttribute("Cash") or 0
end
function ECON.SetCash(p, v)
	p:SetAttribute("Cash", v)
end
function ECON.AddCash(p, n, reason)
	p:SetAttribute("Cash", (p:GetAttribute("Cash") or 0) + n)
	return n
end
svc("ServerScriptService", { Services = { EconomyService = ECON } })
svc("MarketplaceService", {})
svc("Workspace", attrs({}))
game = {
	JobId = "jobA",
	GetService = function(_, name)
		return services[name]
	end,
	BindToClose = function(_, fn)
		table.insert(closeFns, fn)
	end,
}
require = function(m)
	if type(m) == "table" then
		return m
	end
	error("unexpected require")
end

function check(name, cond, detail)
	print((cond and "PASS " or "FAIL ") .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
	if not cond then
		FAILS = (FAILS or 0) + 1
	end
end
