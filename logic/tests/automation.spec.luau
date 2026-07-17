local createAutomation = require("../automation")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local callback
	return {
		Connect = function(_, value)
			callback = value
			return {Disconnect = function() callback = nil end}
		end,
		Fire = function(_, ...) if callback then callback(...) end end,
	}
end

local function toggle(enabled)
	return {
		Enabled = enabled,
		SetEnabled = function(self, value)
			self.Enabled = value == true
		end,
	}
end

local now = 0
local active = true
local order = {}
local click = signal()
local autoSpirit = toggle(false)
local escapeHunt = toggle(false)
local verdict = {
	Lists = {"Aswang", "Skinwalker", "Specter"},
	Confidence = {[1] = 60},
	NegativeConfidence = {},
	RuledOut = {},
	ForceSelect = function(_, name)
		table.insert(order, "select:" .. name)
		return true
	end,
}
local controller = createAutomation({
	Services = {Workspace = {}},
	Player = {},
	Ghost = {GetAttribute = function() return false end},
	Verdict = verdict,
	Remotes = {
		RequestReturnToLobby = function()
			table.insert(order, "lobby")
			active = false
		end,
	},
	Button = {MouseButton1Click = click, BackgroundColor3 = "off"},
	EnabledColor = "on",
	AutoSpirit = autoSpirit,
	EscapeHunt = escapeHunt,
	TeleportToBaseCamp = function()
		expect(not escapeHunt.Enabled, "Hunt Escape must release before the Base Camp return")
		table.insert(order, "base")
	end,
	PrepareReturn = function() table.insert(order, "queue:return") return true end,
	Clock = function() return now end,
	Wait = function(seconds) now += seconds end,
	Spawn = function(callback) callback() end,
	RuntimeIsActive = function() return active end,
	PlaceRoomItems = function() error("preidentified round placed room items") end,
	PlaceDoorTools = function() error("preidentified round placed door tools") end,
	OpenExitDoor = function() error("preidentified round opened the exit") end,
})

click:Fire()
expect(order[1] == "select:Aswang" and order[2] == "base"
	and order[3] == "queue:return" and order[4] == "lobby",
	"selection and return handoff must finish before the lobby request")
expect(autoSpirit.Enabled and not escapeHunt.Enabled,
	"automation should keep Auto Spirit but release Hunt Escape for the Base Camp return")
controller:SetEnabled(false)
expect(not autoSpirit.Enabled and not escapeHunt.Enabled,
	"disabling automation should restore the previous toggle states")
controller:Destroy()

now, active, order = 0, true, {}
local fallback = {
	Lists = {"Keres", "Skinwalker", "Specter"},
	Confidence = {[1] = 25, [2] = 35, [3] = 35},
	NegativeConfidence = {},
	RuledOut = {},
	ForceSelect = function(_, name)
		table.insert(order, "select:" .. name)
		return true
	end,
}
createAutomation({
	Services = {Workspace = {}},
	Player = {},
	Ghost = {GetAttribute = function() return false end},
	Verdict = fallback,
	Remotes = {RequestReturnToLobby = function() active = false end},
	AutoSpirit = toggle(false),
	EscapeHunt = toggle(false),
	TeleportToBaseCamp = function() end,
	Clock = function() return now end,
	Wait = function(seconds) now += seconds end,
	Spawn = function(callback) callback() end,
	RuntimeIsActive = function() return active end,
	TimeoutSeconds = 0,
	PlaceRoomItems = function() table.insert(order, "items") end,
	PlaceDoorTools = function() table.insert(order, "doors") end,
	OpenExitDoor = function() table.insert(order, "exit") end,
}):SetEnabled(true)
expect(table.concat(order, ",") == "items,doors,exit,select:Specter",
	"timeout should run setup in order and choose the strongest non-Skinwalker tie")

print("automation.spec: manual start, setup order, selection lock, and lobby finish passed")
