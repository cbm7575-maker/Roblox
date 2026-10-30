-- RobloxMenu (ModuleScript, ReplicatedStorage.Shared.Util.RobloxMenu)
-- Is Roblox's own Esc / Start menu up right now (client only)?
-- Not GuiService.MenuIsOpen: that flag is raised by every built-in Roblox menu (the backpack's full
-- inventory, the emote wheel...), and one of those switched off while it is open (the hotbar goes away
-- every time you sit in a car: CombatClient) can leave it raised for the rest of the session. Keys gated
-- on it went dead for good: "F gets me out of the car for the first ten minutes, then only EXIT on the
-- screen does". GuiService.MenuOpened / MenuClosed belong to the Esc menu alone, so they're followed here.
--   RobloxMenu.IsOpen() -> boolean
--   RobloxMenu.ShutAgo() -> seconds since it last closed (math.huge if it never has)

local GuiService = game:GetService("GuiService")

local RobloxMenu = {}

local up = false
local shutAt = -math.huge

GuiService.MenuOpened:Connect(function()
	up = true
end)
GuiService.MenuClosed:Connect(function()
	up = false
	shutAt = os.clock()
end)

function RobloxMenu.IsOpen()
	return up
end

function RobloxMenu.ShutAgo()
	return os.clock() - shutAt
end

return RobloxMenu
