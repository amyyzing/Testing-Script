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

local stateSeen, perkStateSeen
local movement = {
	FindRoomsFolder = function() end,
	FindFavouriteRoom = function() end,
	FindBaseCampRoom = function() end,
	GetInstanceWorldPosition = function() end,
	GetRoomBoundingParts = function() return {} end,
	PointIsInsidePart = function() return false end,
	InstanceIsInsideRoom = function() return false end,
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
local createPreRound = function() end
local createRound = function() end
local createPostRound = function() end
local roundStartCalls = 0
local roundStarted = {
	Start = function()
		roundStartCalls += 1
		return true
	end,
}
local controller = createAutomation({
	Services = {Workspace = {}, RunService = nil},
	Player = {FindFirstChildOfClass = function() return nil end},
	Ghost = {GetAttribute = function() return false end},
	Verdict = {
		Lists = {"Aswang", "Wraith"},
		RuledOut = {},
		Confidence = {[1] = 99, [2] = 35},
		NegativeConfidence = {},
		Evidence = {GhostOrb = true},
		IsCompatible = function(_, name) return name == "Wraith" end,
		GetConfirmedEvidence = function() return {GhostOrb = true} end,
		GetEvidenceResolvedGhost = function() return "Wraith" end,
		ForceSelect = function() return true end,
	},
	Movement = movement,
	RoundStarted = roundStarted,
	CreatePreRound = createPreRound,
	CreateRound = createRound,
	CreatePostRound = createPostRound,
	CreateRoomItemSetup = function(dependencies)
		expect(dependencies.PerkTrackerState ~= nil,
			"room setup must receive the legacy automation state")
		return function() return true, 1 end
	end,
	CreateRoundAutomation = function(dependencies)
		expect(dependencies.CreatePreRound == createPreRound
			and dependencies.CreateRound == createRound
			and dependencies.CreatePostRound == createPostRound,
			"automation must forward all three game-round phases")
		stateSeen = dependencies.State
		perkStateSeen = dependencies.PerkTrackerState
		expect(dependencies.TeleportToRoom == movement.TeleportToRoom,
			"round automation must use the restored room teleport")
		expect(dependencies.TeleportToBaseCamp == movement.TeleportToBaseCamp,
			"round automation must use the shared legacy Base Camp teleport")
		expect(dependencies.MarkRoundStarted(),
			"round automation must be able to publish its confirmed exit opening")
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
expect(roundStartCalls == 1,
	"the confirmed automation exit opening must reach the round-start tracker")
expect(perkStateSeen.currentGhostGuess == "Wraith"
	and perkStateSeen.currentGhostGuessScore == 100
	and perkStateSeen.currentGhostGuessCertain == true
	and perkStateSeen.getConfirmedEvidence().GhostOrb == true,
	"automation must treat unique evidence as Certain and expose confirmed evidence")

controller:SetEnabled(false)
expect(not controller.Enabled and not autoSpirit.Enabled,
	"disabling automation must stop the legacy controller and restore Auto Spirit")
expect(enabledChanges[2] == false,
	"the automation handoff must receive the disabled state")
controller:Destroy()

print("automation.spec: legacy controller wiring and shared movement assertions passed")
