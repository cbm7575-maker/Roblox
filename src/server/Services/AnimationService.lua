-- AnimationService (ModuleScript, ServerScriptService.Services.AnimationService)
-- Which walk / run / idle set every character moves with (ids in Shared.Config.Animations).
--   * Every player character (R15) gets Animations.PlayerSet by rewriting the AnimationIds inside its
--     Animate script (idle Animation1 / Animation2, walk WalkAnim, run RunAnim, jump JumpAnim, fall
--     FallAnim, climb ClimbAnim, swim Swim, swimidle SwimIdle). The stock Animate script reloads a value
--     the moment it changes, and the change replicates to every device, so no client work is needed.
--     A slot the set doesn't have is left as it is (the stock R15 animation).
--   * Applying a HumanoidDescription (the wardrobe, disguises, a player's own animation pack) rebuilds
--     those values. Every Animate value is watched: any change or rebuild schedules a re-apply 0.15 s
--     later (changes in one burst are handled once). Two moments can't wait that long, because the body
--     is sent to every device right after them and the Animate script keeps playing whatever idle it
--     started with: the avatar finishing loading (CharacterAppearanceLoaded) and the body arriving in the
--     Workspace. There the set is written AT ONCE, and the delayed pass still follows as a safety net. A
--     re-apply only writes values that differ, so our own writes settle at once; and if something keeps
--     fighting (more than 12 re-applies with changes in 10 s) we back off for 10 s at a time and warn
--     once for that character, rather than loop.
--   * Which set: the character's own override (SetCharacterSet), else the player's (SetPlayerSet, kept
--     across respawns), else Animations.SideSets[player attribute "Side"], else Animations.PlayerSet.
--     The chosen name is mirrored to the character attribute "AnimSet" (other code may read it).
-- API (works any time after Init):
--   AnimationService.SetPlayerSet(player, setName?)      nil = back to the default rules
--   AnimationService.SetCharacterSet(model, setName?)    this character only, until it respawns
--   AnimationService.ApplyTo(model, setName)             any R15 rig with a Humanoid and an Animate script
--                                                        (server NPCs); watched until it is destroyed
--   AnimationService.Refresh(model)                      re-apply now
--   AnimationService.SetOf(model) -> setName?
-- Client-side walkers (PedClient) have no Animate script: they pick with Animations.Pick and load
-- Animations.Asset themselves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animations = require(ReplicatedStorage.Shared.Config.Animations)

local AnimationService = {}

local REAPPLY_DELAY = 0.15
local FIGHT_LIMIT, FIGHT_WINDOW = 12, 10 -- re-applies that changed something, within this many seconds

local watched = {} -- [Model] = state (see watch)
local playerSets = {} -- [Player] = set name chosen by SetPlayerSet

local function numericId(s)
	if type(s) ~= "string" then
		return nil
	end
	return tonumber(string.match(s, "(%d+)%D*$"))
end

-- Which set this character should wear right now.
local function setFor(state)
	if state.override and Animations.Has(state.override) then
		return state.override
	end
	local player = state.player
	if player then
		local chosen = playerSets[player]
		if chosen and Animations.Has(chosen) then
			return chosen
		end
		local bySide = Animations.SideSets[player:GetAttribute("Side") or ""]
		if bySide and Animations.Has(bySide) then
			return bySide
		end
		return Animations.PlayerSet
	end
	return state.npcSet or Animations.PlayerSet
end

-- The Animation children of one Animate value folder, in a fixed order (by name: Animation1 first).
local function animationsIn(folder)
	local list = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Animation") then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function setWeight(anim, value)
	local w = anim:FindFirstChild("Weight")
	if w and not w:IsA("NumberValue") then
		return false -- (someone else's object with that name: leave it)
	end
	if not w then
		w = Instance.new("NumberValue")
		w.Name = "Weight"
		w.Value = value
		w.Parent = anim
		return true
	end
	if w.Value ~= value then
		w.Value = value
		return true
	end
	return false
end

-- Write the set into the Animate script; returns true if anything had to change.
local function writeAnimate(animate, setName)
	local ids = Animations.Resolve(setName)
	local changed = false
	for _, path in ipairs(Animations.AnimatePaths) do
		local first = ids[path.Slots[1]]
		if first then
			local folder = animate:FindFirstChild(path.Folder)
			if folder and not folder:IsA("StringValue") then
				folder = nil -- (not an Animate value: leave it alone)
			elseif not folder then
				-- Missing entirely: build it whole, then parent it, so the Animate script reads it once.
				local fresh = Instance.new("StringValue")
				fresh.Name = path.Folder
				for i, childName in ipairs(path.Children) do
					local anim = Instance.new("Animation")
					anim.Name = childName
					anim.AnimationId = ids[path.Slots[i]] or first
					anim.Parent = fresh
				end
				fresh.Parent = animate
				folder = fresh
				changed = true
			end
			if folder then
				local list = animationsIn(folder)
				-- Make sure every expected child exists (an empty or half-built folder after a rebuild).
				for i = #list + 1, #path.Children do
					local anim = Instance.new("Animation")
					anim.Name = path.Children[i]
					anim.AnimationId = ids[path.Slots[i]] or first
					anim.Parent = folder
					changed = true
				end
				list = animationsIn(folder)
				for i, anim in ipairs(list) do
					-- Slot i of this folder, or its last slot for any extra children (a pack's third idle).
					local want = ids[path.Slots[math.min(i, #path.Slots)]] or first
					if numericId(anim.AnimationId) ~= numericId(want) then
						anim.AnimationId = want
						changed = true
					end
					if path.Folder == "idle" then
						local weight = Animations.IdleWeights[i] or Animations.IdleWeights[#Animations.IdleWeights]
						if weight and setWeight(anim, weight) then
							changed = true
						end
					end
				end
			end
		end
	end
	return changed
end

local schedule -- (defined below; apply uses it to try again after backing off)

local function apply(model)
	local state = watched[model]
	if not state or state.gaveUp then
		return
	end
	-- (No check that the body is in the Workspace yet: a new character gets its values while it is still
	-- being put together, and they are simply there when it arrives.)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local animate = model:FindFirstChild("Animate")
	if not hum or not animate or hum.RigType ~= Enum.HumanoidRigType.R15 then
		return -- (R6 rigs can't play R15 sets; no Animate script: nothing to set)
	end
	local setName = setFor(state)
	if model:GetAttribute("AnimSet") ~= setName then
		model:SetAttribute("AnimSet", setName)
	end
	local ok, changed = pcall(writeAnimate, animate, setName)
	if not ok then
		warn("[AnimationService] " .. tostring(changed))
		return
	end
	if changed then
		local now = os.clock()
		local log = state.changes
		table.insert(log, now)
		while log[1] and now - log[1] > FIGHT_WINDOW do
			table.remove(log, 1)
		end
		if #log > FIGHT_LIMIT then
			-- Something keeps putting other animations back (or someone is flicking through outfits very
			-- fast). Step back for a while instead of looping, then set them once more.
			state.gaveUp = true
			if not state.warned then
				state.warned = true
				warn("[AnimationService] something keeps resetting the animations of " .. model:GetFullName()
					.. "; backing off for " .. FIGHT_WINDOW .. " s at a time")
			end
			task.delay(FIGHT_WINDOW, function()
				if watched[model] == state and state.gaveUp then
					state.gaveUp = false
					state.changes = {}
					schedule(model)
				end
			end)
		end
	end
end

schedule = function(model)
	local state = watched[model]
	if not state or state.pending or state.gaveUp then
		return
	end
	state.pending = true
	task.delay(REAPPLY_DELAY, function()
		if watched[model] ~= state then
			return
		end
		state.pending = false
		apply(model)
	end)
end

local function track(state, conn)
	local conns = state.conns
	-- Every outfit change swaps the Animation objects we were listening to. Drop the dead connections
	-- now and then so the list doesn't grow all session.
	if #conns >= 96 then
		local kept = {}
		for _, c in ipairs(conns) do
			if c.Connected then
				table.insert(kept, c)
			end
		end
		conns = kept
		state.conns = kept
	end
	table.insert(conns, conn)
end

-- Watch one Animate script: any value added, removed or changed schedules a re-apply.
local function hookAnimate(model, state, animate)
	if state.hooked[animate] then
		return
	end
	state.hooked[animate] = true
	local function watchAnim(obj)
		if obj:IsA("Animation") and not state.hooked[obj] then
			state.hooked[obj] = true
			track(state, obj:GetPropertyChangedSignal("AnimationId"):Connect(function()
				schedule(model)
			end))
		end
	end
	for _, d in ipairs(animate:GetDescendants()) do
		watchAnim(d)
	end
	track(state, animate.DescendantAdded:Connect(function(d)
		watchAnim(d)
		schedule(model)
	end))
	track(state, animate.DescendantRemoving:Connect(function(d)
		state.hooked[d] = nil
		schedule(model)
	end))
end

local function unwatch(model)
	local state = watched[model]
	if not state then
		return
	end
	watched[model] = nil
	for _, conn in ipairs(state.conns) do
		conn:Disconnect()
	end
end

local function watch(model, player, npcSet)
	local state = watched[model]
	if state then
		state.npcSet = npcSet or state.npcSet
		state.gaveUp = false
		state.changes = {}
		schedule(model)
		return state
	end
	state = {
		player = player,
		npcSet = npcSet,
		override = nil,
		conns = {},
		hooked = setmetatable({}, { __mode = "k" }),
		changes = {},
		pending = false,
		gaveUp = false,
	}
	watched[model] = state
	local animate = model:FindFirstChild("Animate")
	if animate then
		hookAnimate(model, state, animate)
	end
	-- A new Animate script (some avatar loads replace it) is hooked too.
	track(state, model.ChildAdded:Connect(function(child)
		if child.Name == "Animate" then
			hookAnimate(model, state, child)
			schedule(model)
		end
	end))
	track(state, model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unwatch(model)
		else
			-- It has just been put in the world and is about to be sent to every device: write the set now
			-- (a delayed write arrives after the Animate script has already started the old idle), and
			-- look once more a moment later.
			apply(model)
			schedule(model)
		end
	end))
	track(state, model.Destroying:Connect(function()
		unwatch(model)
	end))
	schedule(model)
	return state
end

local function onCharacter(player, char)
	-- Clear out watchers of this player's old bodies (respawns can leave the old model parented a moment).
	for model, state in pairs(watched) do
		if state.player == player and model ~= char then
			unwatch(model)
		end
	end
	watch(char, player)
	-- The Animate script usually arrives with the body; when it comes late, ChildAdded catches it.
	task.spawn(function()
		local animate = char:WaitForChild("Animate", 10)
		if animate and watched[char] then
			schedule(char)
		end
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	-- The avatar (and any animation pack in it) finishes loading after CharacterAdded and puts its own
	-- ids back; the body goes into the Workspace right after this. Write ours at once, so it is sent
	-- out with the right set, and check once more a moment later.
	player.CharacterAppearanceLoaded:Connect(function(char)
		if watched[char] then
			apply(char)
			schedule(char)
		end
	end)
	player:GetAttributeChangedSignal("Side"):Connect(function()
		local char = player.Character
		if char and watched[char] then
			schedule(char)
		end
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

------------------------------------------------------------------ API

function AnimationService.SetPlayerSet(player, setName)
	if setName ~= nil and not Animations.Has(setName) then
		warn("[AnimationService] unknown animation set " .. tostring(setName))
		return
	end
	playerSets[player] = setName
	local char = player.Character
	local state = char and watched[char]
	if state then
		state.gaveUp = false
		state.changes = {}
		schedule(char)
	end
end

function AnimationService.SetCharacterSet(model, setName)
	if setName ~= nil and not Animations.Has(setName) then
		warn("[AnimationService] unknown animation set " .. tostring(setName))
		return
	end
	local state = watched[model]
	if not state then
		local player = Players:GetPlayerFromCharacter(model)
		state = watch(model, player, nil)
	end
	state.override = setName
	state.gaveUp = false
	state.changes = {}
	schedule(model)
end

function AnimationService.ApplyTo(model, setName)
	if not Animations.Has(setName) then
		warn("[AnimationService] unknown animation set " .. tostring(setName))
		return
	end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		AnimationService.SetCharacterSet(model, setName)
		return
	end
	watch(model, nil, setName)
end

function AnimationService.Refresh(model)
	local state = watched[model]
	if state then
		state.gaveUp = false
		state.changes = {}
		apply(model)
	end
end

function AnimationService.SetOf(model)
	local state = watched[model]
	return state and setFor(state) or nil
end

function AnimationService.Init()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayer, player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		playerSets[player] = nil
		for model, state in pairs(watched) do
			if state.player == player then
				unwatch(model)
			end
		end
	end)
end

return AnimationService
