local createAutomation = require("../automation")

local function expect(value, message)
	if not value then error(message, 2) end
end

local function signal()
	local callback
	return {
		Connect = function(_, nextCallback)
			callback = nextCallback
			return {Disconnect = function() callback = nil end}
		end,
		Fire = function(_, ...)
			if callback then callback(...) end
		end,
	}
end

local stateSeen
local movement = {
	FindRoomsFolder = function() end,
	FindFavouriteRoom = function() end,
	FindBaseCampRoom = function() end,
	GetInstanceWorldPosition = function() end,
	GetRoomBoundingParts = function() return {} end,
	PointIsInsidePart = function() return false end,
	InstanceIsInsideRoom = function() return false end,
	Teleportation = {},
	TeleportToRoom = function() return true end,
	TeleportToBaseCamp = function() return true end,
	TeleportToFavouriteRoom = function() return true end,
}
local autoSpirit = {
	Enabled = false,
	SetEnabled = function(self, enabled) self.Enabled = enabled == true end,
}
local enabledChanges = {}
local click = signal()
local controller = createAutomation({
	Services = {Workspace = {}, RunService = nil},
	Player = {FindFirstChildOfClass = function() return nil end},
	Ghost = {GetAttribute = function() return false end},
	Verdict = {
		Lists = {"Aswang", "Wraith"},
		RuledOut = {},
		Confidence = {[1] = 99},
		NegativeConfidence = {},
		ForceSelect = function() return true end,
	},
	Movement = movement,
	CreateRoomItemSetup = function(dependencies)
		expect(dependencies.Teleportation == movement.Teleportation,
			"room setup must share the legacy teleport coordinator")
		return function() return true, 1 end
	end,
	CreateRoundAutomation = function(dependencies)
		stateSeen = dependencies.State
		expect(dependencies.TeleportToRoom == movement.TeleportToRoom,
			"round automation must use the shared full-containment room teleport")
		expect(dependencies.TeleportToBaseCamp == movement.TeleportToBaseCamp,
			"round automation must use the shared legacy Base Camp teleport")
		return {
			SetEnabled = function(enabled)
				dependencies.State.enabled = enabled == true
				dependencies.State.autoSpiritBoxLease = enabled == true
				dependencies.RefreshAutoSpiritBoxEnabled()
				dependencies.SetDoRoundStatus(enabled and "Checking ghost room" or "Off")
				return dependencies.State.enabled
			end,
		}
	end,
	Button = {MouseButton1Click = click, BackgroundColor3 = "off"},
	EnabledColor = "on",
	AutoSpirit = autoSpirit,
	OnEnabledChanged = function(enabled)
		table.insert(enabledChanges, enabled)
	end,
	RuntimeIsActive = function() return true end,
})

click:Fire()
expect(controller.Enabled and stateSeen.enabled,
	"the GUI button must enable the legacy round controller")
expect(autoSpirit.Enabled,
	"legacy automation must retain Auto Spirit while enabled")
expect(enabledChanges[1] == true,
	"the automation handoff must receive the enabled state")
expect(controller.TeleportToBaseCamp == movement.TeleportToBaseCamp,
	"hunt escape and automation must expose the same Base Camp movement path")

controller:SetEnabled(false)
expect(not controller.Enabled and not autoSpirit.Enabled,
	"disabling automation must stop the legacy controller and restore Auto Spirit")
expect(enabledChanges[2] == false,
	"the automation handoff must receive the disabled state")
controller:Destroy()

print("automation.spec: legacy controller wiring and shared movement assertions passed")
