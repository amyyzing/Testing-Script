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

local stateSeen, perkStateSeen, detectionsSeen
local huntSignal = signal()
local ghost = {Hunting = false}
function ghost:GetAttribute(name)
	return name == "Hunting" and self.Hunting or false
end
function ghost:GetAttributeChangedSignal(name)
	expect(name == "Hunting", "automation should only bind the Hunting signal")
	return huntSignal
end
local fastEscapes = 0
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
	FastTeleportToBaseCamp = function()
		fastEscapes += 1
		return true
	end,
	TeleportToFavouriteRoom = function() return true end,
}
local autoSpirit = {
	Enabled = false,
	SetEnabled = function(self, enabled) self.Enabled = enabled == true end,
}
local enabledChanges = {}
local click = signal()
local createPreRound = function() end
local createLaySalt = function() end
local createPourHolyOil = function() end
local createRound = function() end
local createPostRound = function() end
local createRoundUtilities = function() end
local createHuntEscape = function() end
local createItemGhostRoom = function() end
local createMaintainItem = function() end
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
	Ghost = ghost,
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
	FastTeleportToBaseCamp = movement.FastTeleportToBaseCamp,
	RoundStarted = roundStarted,
	CreatePreRound = createPreRound,
	CreateLaySalt = createLaySalt,
	CreatePourHolyOil = createPourHolyOil,
	CreateRound = createRound,
	CreatePostRound = createPostRound,
	CreateRoundUtilities = createRoundUtilities,
	CreateHuntEscape = createHuntEscape,
	CreateItemGhostRoom = createItemGhostRoom,
	CreateMaintainItem = createMaintainItem,
	CreateRoomItemSetup = function(dependencies)
		expect(dependencies.PerkTrackerState ~= nil,
			"room setup must receive the legacy automation state")
		return function() return true, 1 end
	end,
	CreateRoundAutomation = function(dependencies)
		expect(dependencies.CreatePreRound == createPreRound
			and dependencies.CreateRound == createRound
			and dependencies.CreatePostRound == createPostRound
			and dependencies.CreateRoundUtilities == createRoundUtilities,
			"automation must forward all three game-round phases")
		expect(dependencies.CreateLaySalt == createLaySalt
			and dependencies.CreatePourHolyOil == createPourHolyOil,
			"automation must forward both split door-placeable modules")
		expect(dependencies.CreateHuntEscape == createHuntEscape,
			"automation must forward the split hunt escape module")
		expect(dependencies.CreateItemGhostRoom == createItemGhostRoom,
			"automation must forward the split room-item module")
		expect(dependencies.CreateMaintainItem == createMaintainItem,
			"automation must forward the split item-maintenance module")
		stateSeen = dependencies.State
		perkStateSeen = dependencies.PerkTrackerState
		detectionsSeen = dependencies.PerkDetections
		expect(dependencies.TeleportToRoom == movement.TeleportToRoom,
			"round automation must use the restored room teleport")
		expect(dependencies.TeleportToBaseCamp == movement.TeleportToBaseCamp,
			"round automation must use the shared legacy Base Camp teleport")
		expect(dependencies.FastTeleportToBaseCamp == movement.FastTeleportToBaseCamp,
			"round automation must receive the immediate cached hunt escape")
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
	EvidenceReady = function() return true end,
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
expect(detectionsSeen.Wraith.NetConfidence == 35,
	"timeout weighting should expose evidence-compatible net confidence")
ghost.Hunting = true
huntSignal:Fire()
expect(fastEscapes == 1 and stateSeen.phase == "Hunt escape",
	"automation must escape immediately from the Hunting attribute signal")

controller:SetEnabled(false)
expect(not controller.Enabled and not autoSpirit.Enabled,
	"disabling automation must stop the legacy controller and restore Auto Spirit")
expect(enabledChanges[2] == false,
	"the automation handoff must receive the disabled state")
controller:Destroy()

print("automation.spec: legacy controller wiring and shared movement assertions passed")
