local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createHumming = require("../dormant-trackers/humming")
local createModelTraits = require("../discardable-trackers/model-traits")
local createPlayerSpeed = require("../active-trackers/player-speed")
local createLOSSight = require("../dormant-trackers/los-sight")
local createLOSSpeed = require("../dormant-trackers/los-speed")
local Siren = require("../ghosts/Siren")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			return {Disconnect = function()
				local index = table.find(callbacks, callback)
				if index then table.remove(callbacks, index) end
			end}
		end,
		Fire = function(_, ...)
			for _, callback in ipairs(table.clone(callbacks)) do callback(...) end
		end,
	}
end

local function verdictHarness()
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local siren = Siren.new({Traffic = Traffic})
	return Traffic, Verdict, siren
end

local hummingTraffic, hummingVerdict, hummingSiren = verdictHarness()
local subtitle = signal()
local humming = createHumming({Traffic = hummingTraffic, RemoteSignal = subtitle})
subtitle:Fire("- HUMMING -")
expect(hummingVerdict.Confidence[16] == nil,
	"humming should remain dormant while no Spirit Box is enabled")
local spiritState = {}
hummingTraffic("SpiritBoxState", {State = spiritState, Enabled = true}):SendTo("Humming")
subtitle:Fire("  - HUMMING -  ")
expect((hummingVerdict.Confidence[16] == 65 and hummingVerdict.SourceConfidence[16] == 99) and hummingVerdict.Selected[1] == 16,
	"an enabled Spirit Box followed by the exact humming subtitle should support Siren")
humming:Destroy()
hummingSiren:Destroy()

local femaleTraffic, femaleVerdict, femaleSiren = verdictHarness()
local femaleGhost = {VisualModel = "Abaddon"}
function femaleGhost:GetAttribute(name) return self[name] end
createModelTraits({Traffic = femaleTraffic, Ghost = femaleGhost})
expect(femaleVerdict.Confidence[16] == nil and femaleVerdict.Selected[1] == nil,
	"a female VisualModel cannot positively identify Siren")
femaleSiren:Destroy()

local maleTraffic, maleVerdict, maleSiren = verdictHarness()
local maleGhost = {VisualModel = "FutureModel"}
function maleGhost:GetAttribute(name) return self[name] end
createModelTraits({Traffic = maleTraffic, Ghost = maleGhost})
expect(not table.find(maleVerdict.RuledOut, 16) and maleVerdict.Confidence[16] == nil,
	"an unfamiliar VisualModel must not rule out Siren")
maleGhost.Gender = "Male"
createModelTraits({Traffic = maleTraffic, Ghost = maleGhost})
expect(table.find(maleVerdict.RuledOut, 16), "an explicit male Gender should rule out Siren")
maleSiren:Destroy()

local function losHarness(requiredExposure, initialSpeed)
	local now = 0
	local visible = false
	local heartbeat = signal()
	local speedChanged = signal()
	local characterAdded = signal()
	local playerAdded = signal()
	local playerRemoving = signal()
	local Humanoid = {WalkSpeed = initialSpeed or 16}
	function Humanoid:GetPropertyChangedSignal(name)
		expect(name == "WalkSpeed", "player-speed should only watch Humanoid WalkSpeed")
		return speedChanged
	end
	local Character = {}
	function Character:FindFirstChildOfClass(class)
		return class == "Humanoid" and Humanoid or nil
	end
	local Player = {Character = Character, CharacterAdded = characterAdded, Dead = false}
	function Player:GetAttribute(name) return name == "Dead" and self.Dead or nil end
	local Players = {
		LocalPlayer = Player,
		PlayerAdded = playerAdded,
		PlayerRemoving = playerRemoving,
	}
	function Players:GetPlayers() return {Player} end

	local Traffic, Verdict, siren = verdictHarness()
	local losSpeed = createLOSSpeed({
		Traffic = Traffic,
		RequiredExposure = requiredExposure,
	})
	local playerSpeed = createPlayerSpeed({
		Traffic = Traffic,
		Players = Players,
		Clock = function() return now end,
	})
	local losSight = createLOSSight({
		Traffic = Traffic,
		Workspace = {},
		Ghost = {},
		Players = Players,
		RunService = {Heartbeat = heartbeat},
		Clock = function() return now end,
		HasLineOfSight = function() return visible end,
	})
	return {
		Traffic = Traffic,
		Verdict = Verdict,
		Siren = siren,
		LOSSpeed = losSpeed,
		PlayerSpeed = playerSpeed,
		LOSSight = losSight,
		Player = Player,
		Humanoid = Humanoid,
		SetVisible = function(value) visible = value end,
		SetSpeed = function(value)
			Humanoid.WalkSpeed = value
			speedChanged:Fire()
		end,
		Step = function(delta)
			now += delta
			heartbeat:Fire(delta)
		end,
	}
end

local function destroyLOS(harness)
	harness.LOSSight:Destroy()
	harness.PlayerSpeed:Destroy()
	harness.LOSSpeed:Destroy()
	harness.Siren:Destroy()
end

for _, base in ipairs({8, 10, 12, 14, 16}) do
	local calibrated = losHarness(4, base)
	local state = calibrated.PlayerSpeed.States[calibrated.Player]
	expect(state.BaseSpeed == base and state.SprintSpeed == base * 1.6,
		"the first non-hunting speed should set one of the five valid walk/sprint pairs")
	calibrated.SetSpeed(base * 1.6)
	expect(state.SprintObserved,
		"a second non-hunting speed equal to base times 1.6 should be marked as sprint")
	destroyLOS(calibrated)
end

local initialized = losHarness(4, 16)
initialized.SetSpeed(8)
local initializedState = initialized.PlayerSpeed.States[initialized.Player]
expect(initializedState.BaseSpeed == 8 and initializedState.SprintSpeed == 12.8,
	"the native pre-hunt speed must replace a temporary spawn-default calibration")
destroyLOS(initialized)

local slowed = losHarness(4, 16)
slowed.SetSpeed(25.6)
slowed.SetSpeed(16)
slowed.SetVisible(true)
slowed.Step(0.1)
expect(slowed.Verdict.Confidence[16] == nil,
	"line-of-sight tracking must remain dormant outside a hunt")
slowed.Traffic:Broadcast("HuntingState", {Hunting = true})
slowed.Step(0.1)
slowed.SetSpeed(12.8)
expect(slowed.Verdict.Confidence[16] == 35,
	"the 0.8x walking slowdown also observed on native Revenant must remain weak")
destroyLOS(slowed)

local sprintSlowed = losHarness(4, 10)
sprintSlowed.SetSpeed(16)
sprintSlowed.Traffic:Broadcast("HuntingState", {Hunting = true})
sprintSlowed.SetVisible(true)
sprintSlowed.Step(0.1)
sprintSlowed.SetSpeed(12.8)
expect(sprintSlowed.Verdict.Confidence[16] == 35,
	"an unqualified 0.8x sprint slowdown must not independently identify Siren")
destroyLOS(sprintSlowed)

local normalSwitch = losHarness(4, 12)
normalSwitch.SetSpeed(19.2)
normalSwitch.SetSpeed(12)
normalSwitch.Traffic:Broadcast("HuntingState", {Hunting = true})
normalSwitch.SetVisible(true)
normalSwitch.Step(0.1)
normalSwitch.SetSpeed(19.2)
normalSwitch.SetSpeed(12)
expect(#normalSwitch.Verdict.Selected == 0 and #normalSwitch.Verdict.RuledOut == 0,
	"ordinary changes between the learned walk and sprint speeds must not identify Siren")
destroyLOS(normalSwitch)

local unchanged = losHarness(0.3, 14)
unchanged.SetSpeed(22.4)
unchanged.Traffic:Broadcast("HuntingState", {Hunting = true})
unchanged.SetVisible(true)
for _ = 1, 4 do unchanged.Step(0.1) end
expect(not table.find(unchanged.Verdict.RuledOut, 16) and unchanged.Verdict.NegativeConfidence[16] == nil,
	"unchanged speed alone must remain inconclusive")
unchanged.Traffic("Humming", {Response = "- HUMMING -"}):SendTo("Siren")
expect((unchanged.Verdict.Confidence[16] == 65 and unchanged.Verdict.SourceConfidence[16] == 99) and unchanged.Verdict.NegativeConfidence[16] == nil,
	"an ambiguous speed trial must not penalize a later exact humming response")
destroyLOS(unchanged)

print("siren.spec: learned walk/sprint states and 0.8x hunting slowdown passed")
