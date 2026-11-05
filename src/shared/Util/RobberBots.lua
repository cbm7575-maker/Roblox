-- RobberBots (ModuleScript, ReplicatedStorage.Shared.Util.RobberBots)
-- The NPC robbers' public face (RobberBotService runs them; owner, Nov 4: "a bot playing the game, stealing
-- something" so cops always have someone to chase). What every device can read about them:
--   * ReplicatedStorage.RobberBots: one Configuration per bot (named by its id, never streamed out), with
--     the attributes a wanted player carries, so the police HUD treats both alike:
--       DisplayName ("Gator Gus"), Heat (0-5), HeatSpotted, LastSeen (Vector3), SuspectCar, SuspectOutfit,
--       WantedSince (server time), and OnFoot (true while it's out of its car).
--   * Its car: a model in Workspace.Vehicles with the attribute RobberBot = the id (RaceAIService drives it).
--   * Its body on foot: a model in Workspace.RobberBots with the attribute RobberBot = the id, and the model
--     attribute Pose ("HandsUp" while it gives up; LawClient plays it with PoseClient).
-- The car and the body are streamed like anything else, so they can be nil on a device far away; the
-- Configuration's attributes are always there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RobberBots = {}

RobberBots.FOLDER = "RobberBots" -- in ReplicatedStorage (records) and in Workspace (bodies on foot)
RobberBots.ATTR = "RobberBot" -- on the car and the body: the bot's id

local EMPTY = {}

-- Every bot's record (Configuration), in no set order.
function RobberBots.List()
	local folder = ReplicatedStorage:FindFirstChild(RobberBots.FOLDER)
	return folder and folder:GetChildren() or EMPTY
end

function RobberBots.Get(id)
	local folder = ReplicatedStorage:FindFirstChild(RobberBots.FOLDER)
	return folder and type(id) == "string" and folder:FindFirstChild(id) or nil
end

function RobberBots.IsWanted(rec)
	return rec ~= nil and (rec:GetAttribute("Heat") or 0) > 0
end

-- The bot's car, if this device has it.
function RobberBots.Car(rec)
	local vehicles = Workspace:FindFirstChild("Vehicles")
	if not rec or not vehicles then
		return nil
	end
	for _, car in ipairs(vehicles:GetChildren()) do
		if car:GetAttribute(RobberBots.ATTR) == rec.Name then
			return car
		end
	end
	return nil
end

-- The bot's body on foot (only while it's out of its car), if this device has it.
function RobberBots.Body(rec)
	local folder = Workspace:FindFirstChild(RobberBots.FOLDER)
	if not rec or not folder or rec:GetAttribute("OnFoot") ~= true then
		return nil
	end
	for _, m in ipairs(folder:GetChildren()) do
		if m:GetAttribute(RobberBots.ATTR) == rec.Name then
			return m
		end
	end
	return nil
end

-- The part to follow for this bot right now (its body's root on foot, else its car's chassis), or nil.
function RobberBots.Root(rec)
	local body = RobberBots.Body(rec)
	local root = body and body:FindFirstChild("HumanoidRootPart")
	if root then
		return root
	end
	local car = RobberBots.Car(rec)
	return car and car:IsA("Model") and car.PrimaryPart or nil
end

-- The record of the bot a car or a body belongs to (nil for anything else).
function RobberBots.Of(model)
	return typeof(model) == "Instance" and RobberBots.Get(model:GetAttribute(RobberBots.ATTR)) or nil
end

return RobberBots
