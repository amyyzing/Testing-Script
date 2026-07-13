local localModules = {
	["ghost/Aswang.luau"] = require("../Aswang"),
	["ghost/Banshee.luau"] = require("../Banshee"),
	["ghost/Demon.luau"] = require("../Demon"),
	["ghost/Dullahan.luau"] = require("../Dullahan"),
	["ghost/Dybbuk.luau"] = require("../Dybbuk"),
	["ghost/Entity.luau"] = require("../Entity"),
	["ghost/Ghoul.luau"] = require("../Ghoul"),
	["ghost/Keres.luau"] = require("../Keres"),
	["ghost/Leviathan.luau"] = require("../Leviathan"),
	["ghost/Nightmare.luau"] = require("../Nightmare"),
	["ghost/Oni.luau"] = require("../Oni"),
	["ghost/Phantom.luau"] = require("../Phantom"),
	["ghost/Ravager.luau"] = require("../Ravager"),
	["ghost/Revenant.luau"] = require("../Revenant"),
	["ghost/Shadow.luau"] = require("../Shadow"),
	["ghost/Siren.luau"] = require("../Siren"),
	["ghost/Skinwalker.luau"] = require("../Skinwalker"),
	["ghost/Specter.luau"] = require("../Specter"),
	["ghost/Spirit.luau"] = require("../Spirit"),
	["ghost/Umbra.luau"] = require("../Umbra"),
	["ghost/Vesper.luau"] = require("../Vesper"),
	["ghost/Vex.luau"] = require("../Vex"),
	["ghost/Wendigo.luau"] = require("../Wendigo"),
	["ghost/Wisp.luau"] = require("../Wisp"),
	["ghost/Wraith.luau"] = require("../Wraith"),
	["ghost/engine.luau"] = require("../engine"),
	["ghost/runtime.luau"] = require("../runtime"),
	["ghost/collector.luau"] = require("../collector"),
	["ghost/session.luau"] = require("../session"),
	["ghost/tracker.luau"] = require("../tracker"),
}

local buildPackage = require("../")
local GhostPackage = buildPackage({
	LoadModule = function(path)
		local module = localModules[path]
		if module == nil then
			error("unexpected local ghost package path: " .. tostring(path), 2)
		end
		return module
	end,
})

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

local api = {
	Detections = {},
	RuleOuts = {},
	SupportedEvidence = {},
	CurrentMode = "Normal",
	RefreshCount = 0,
}

function api:Detect(name, reason, confidence, source)
	if self.RuleOuts[name] ~= nil then
		return false
	end
	local score = tonumber(confidence) or 0
	local previous = self.Detections[name]
	local previousScore = type(previous) == "table"
		and tonumber(previous.Confidence) or tonumber(previous) or 0
	if previous == nil or score >= previousScore then
		self.Detections[name] = {
			Ghost = name,
			Reason = reason,
			Confidence = score,
			Source = source,
		}
		return true
	end
	return false
end

function api:RuleOut(name, reason, confidence)
	self.RuleOuts[name] = {
		Reason = reason,
		Confidence = tonumber(confidence) or 0,
	}
	self.Detections[name] = nil
	return true
end

function api:ClearDetection(name)
	local changed = self.Detections[name] ~= nil
	self.Detections[name] = nil
	return changed
end

function api:ClearRuleOut(name)
	local changed = self.RuleOuts[name] ~= nil
	self.RuleOuts[name] = nil
	return changed
end

function api:GetDetection(name)
	return self.Detections[name]
end

function api:SetDetection(name, value)
	self.Detections[name] = value
	return true
end

function api:IsRuledOut(name)
	return self.RuleOuts[name] ~= nil
end

function api:MarkPersistent(name)
	local detection = self.Detections[name]
	if type(detection) ~= "table" then
		return false
	end
	detection.Persistent = true
	return true
end

function api:SupportsConfirmedEvidence(name)
	return self.SupportedEvidence[name] == true
end

function api:Mode()
	return self.CurrentMode
end

function api:Refresh()
	self.RefreshCount = self.RefreshCount + 1
end

local routedActions = {}
local runtime
runtime = GhostPackage.CreateRuntime({
	Definitions = GhostPackage.Definitions,
	Api = api,
	Mode = api.CurrentMode,
	OnAction = function(action)
		table.insert(routedActions, action)
		if action.Type == "Dispatch" then
			runtime:Dispatch(action.Hook, action.Event)
		end
	end,
})

local function reset(mode)
	table.clear(api.Detections)
	table.clear(api.RuleOuts)
	table.clear(api.SupportedEvidence)
	table.clear(routedActions)
	api.RefreshCount = 0
	api.CurrentMode = mode or "Normal"
	runtime:Reset({PreserveFindings = false})
	runtime:SetMode(api.CurrentMode)
	api.RefreshCount = 0
end

local activeObservers = {
	Aswang = true,
	Banshee = true,
	Demon = true,
	Dullahan = true,
	Dybbuk = true,
	Entity = true,
	Ghoul = true,
	Keres = true,
	Leviathan = true,
	Oni = true,
	Phantom = true,
	Ravager = true,
	Revenant = true,
	Siren = true,
	Skinwalker = true,
	Specter = true,
	Spirit = true,
	Umbra = true,
	Vex = true,
	Wendigo = true,
	Wisp = true,
	Wraith = true,
}
local definitionsByName = {}
local activeCount = 0
for _, definition in ipairs(GhostPackage.Definitions) do
	definitionsByName[definition.Name] = definition
	if definition.CreateObserver ~= nil then
		activeCount = activeCount + 1
		expect(
			activeObservers[definition.Name] == true,
			"observer coverage must be added for " .. definition.Name
		)
		expect(runtime:GetObserver(definition.Name) ~= nil, definition.Name .. " observer should load")
	end
end
expect(activeCount == 22, "all 22 active observers should be loaded")
for _, name in ipairs({"Nightmare", "Shadow", "Vesper"}) do
	expect(#definitionsByName[name].ObservationKeys == 0, name .. " should remain metadata-only")
	expect(definitionsByName[name].CreateObserver == nil, name .. " should not define an observer")
	expect(runtime:GetObserver(name) == nil, name .. " should not create a runtime observer")
end

-- Aswang: a verified salt contact can reject or strongly identify it, while
-- opposing kill-speed directions remain reversible observations.
reset()
runtime:Dispatch("OnSaltSpeed", {Outcome = "NoDrop", Reason = "no temporary slowdown"})
expect(api.RuleOuts.Aswang.Confidence == 90, "a complete no-drop salt sample should rule out Aswang")
runtime:Dispatch("OnSaltSpeed", {Outcome = "Recovered", Reason = "temporary salt slowdown recovered"})
expect(api.RuleOuts.Aswang == nil, "a recovered salt slowdown should clear Aswang's rule-out")
expect(api.Detections.Aswang.Confidence == 99, "a recovered salt slowdown should detect Aswang")
reset()
runtime:Dispatch("OnKillSpeed", {Direction = "Decrease", Reason = "death speed decreased"})
expect(api.RuleOuts.Aswang.Confidence == 94, "a death-linked decrease should rule out Aswang")
runtime:Dispatch("OnKillSpeed", {Direction = "Increase", Count = 1, Reason = "death speed increased"})
expect(api.RuleOuts.Aswang == nil and api.Detections.Aswang.Confidence == 97, "a death-linked increase should detect Aswang")
expect(api.RuleOuts.Keres.Confidence == 94, "an Aswang increase should rule out Keres")

local function saltSpeedSamples(values)
	local samples = {}
	for index, speed in ipairs(values) do
		table.insert(samples, {
			Time = (index - 1) * 0.1,
			Speed = speed,
		})
	end
	return samples
end

-- Aswang owns the raw same-hunt salt classifier: two 6% drops are tentative,
-- and two settled recovery samples upgrade the same contact to certain.
reset()
runtime:Dispatch("OnSaltSpeedSamples", {
	ContactId = "outside-hunt",
	HuntingAtTouch = false,
	SaltDisturbed = true,
	PreSpeed = 10,
	BaselineReliable = true,
	PreSampleCount = 3,
	SpeedSamples = saltSpeedSamples({10, 9.39, 9.3}),
})
expect(api.Detections.Aswang == nil, "salt speed samples outside a hunt must not identify Aswang")
runtime:Dispatch("OnSaltSpeedSamples", {
	ContactId = "undisturbed-contact",
	HuntingAtTouch = true,
	SaltDisturbed = false,
	PreSpeed = 10,
	BaselineReliable = true,
	PreSampleCount = 3,
	SpeedSamples = saltSpeedSamples({10, 9.39, 9.3, 9.3, 10, 10.1}),
})
expect(api.Detections.Aswang == nil, "an undisturbed salt pile must not identify Aswang")
runtime:Dispatch("OnSaltSpeedSamples", {
	ContactId = "verified-contact",
	HuntingAtTouch = true,
	SaltDisturbed = true,
	PreSpeed = 10,
	BaselineReliable = true,
	PreSampleCount = 3,
	SpeedSamples = saltSpeedSamples({10, 9.39, 9.3}),
})
expect(api.Detections.Aswang.Confidence == 95, "two raw 6% salt drops should tentatively detect Aswang")
runtime:Dispatch("OnSaltSpeedSamples", {
	ContactId = "verified-contact",
	HuntingAtTouch = true,
	SaltDisturbed = true,
	PreSpeed = 10,
	BaselineReliable = true,
	PreSampleCount = 3,
	SpeedSamples = saltSpeedSamples({10, 9.39, 9.3, 9.3, 10, 10.1}),
})
expect(api.Detections.Aswang.Confidence == 99, "two raw post-drop recovery samples should confirm Aswang")

-- When the pre-contact baseline was missed, a repeated low phase followed by
-- recovery is valid unless Dullahan has already supplied the speed pattern.
reset()
local inferredSaltEvent = {
	ContactId = "inferred-contact",
	HuntingAtTouch = true,
	SaltDisturbed = true,
	PreSpeed = 9.4,
	BaselineReliable = true,
	PreSampleCount = 0,
	SpeedSamples = saltSpeedSamples({9.4, 9.45, 10, 10.1, 10.2}),
}
runtime:Dispatch("OnSaltSpeedSamples", inferredSaltEvent)
expect(api.Detections.Aswang.Confidence == 99, "a repeated low-then-recovery sequence should infer Aswang without pre-samples")
reset()
api.Detections.Dullahan = {Confidence = 99}
inferredSaltEvent.ContactId = "dullahan-conflict"
runtime:Dispatch("OnSaltSpeedSamples", inferredSaltEvent)
expect(api.Detections.Aswang == nil, "Dullahan should suppress only the inferred Aswang salt pattern")

-- A reliable hunting contact with ten stable no-drop samples is a qualified
-- negative once four seconds pass (or the hunt ends).
reset()
runtime:Dispatch("OnSaltSpeedSamples", {
	ContactId = "no-drop-contact",
	HuntingAtTouch = true,
	SaltDisturbed = true,
	PreSpeed = 10,
	BaselineReliable = true,
	PreSampleCount = 3,
	SpeedSamples = saltSpeedSamples({10, 10, 10, 10, 10, 10, 10, 10, 10, 10}),
	Age = 4,
})
expect(api.RuleOuts.Aswang.Confidence == 90, "ten verified raw no-drop samples should rule out Aswang")
reset()
runtime:Dispatch("OnSaltSpeedSamples", {
	ContactId = "hunt-ended-no-drop",
	HuntingAtTouch = true,
	SaltDisturbed = true,
	PreSpeed = 10,
	BaselineReliable = true,
	PreSampleCount = 3,
	SpeedSamples = saltSpeedSamples({10, 10, 10, 10, 10, 10, 10, 10, 10, 10}),
	Age = 1,
	HuntEnded = true,
})
expect(api.RuleOuts.Aswang.Confidence == 90, "hunt end should complete a verified ten-sample Aswang negative before four seconds")

local function aswangSpeedSample(time, speed, hunting)
	runtime:Dispatch("OnSpeedSample", {
		Time = time,
		Speed = speed,
		Hunting = hunting ~= false,
	})
end

local function aswangPreKillSamples(deathTime, speeds)
	local offsets = {-0.8, -0.5, -0.2}
	for index, speed in ipairs(speeds or {10, 10, 10}) do
		aswangSpeedSample(deathTime + offsets[index], speed, true)
	end
end

-- Aswang owns the raw death-linked speed classifier. It waits through the
-- 0.65-second settling window, then broadcasts the existing Increase outcome
-- only after stable pre- and post-kill medians cross the 14% threshold.
reset()
aswangPreKillSamples(10, {10, 10.02, 9.98})
runtime:Dispatch("OnPlayerDeath", {
	Time = 10,
	PlayerId = "aswang-increase",
	Hunting = true,
	Multiplayer = true,
	OtherAlive = 1,
	HuntAge = 1,
	Unique = true,
})
aswangSpeedSample(10.1, 11.5, true)
aswangSpeedSample(10.3, 11.5, true)
aswangSpeedSample(10.5, 11.5, true)
expect(api.Detections.Aswang == nil, "raw death speed must wait 0.65 seconds before classifying")
expect(runtime:Snapshot().Observers.Aswang.PendingDeathCount == 1, "a qualified raw death should remain pending during settling")
aswangSpeedSample(10.65, 11.5, true)
expect(api.Detections.Aswang.Confidence == 97, "a stable 14% post-kill increase should identify Aswang")
expect(api.RuleOuts.Keres.Confidence == 94, "the raw Aswang increase should use the shared kill-speed outcome")
expect(runtime:Snapshot().Observers.Aswang.LastDeathOutcome == "Increase", "the Aswang observer should retain its raw increase outcome")
expect(runtime:Snapshot().Observers.Aswang.PendingDeathCount == 0, "a classified raw death should leave no pending window")

-- A stable fall of at least 7% takes the existing Decrease path, identifying
-- Keres and ruling out Aswang when no stronger salt result exists.
reset()
aswangPreKillSamples(20)
runtime:Dispatch("OnPlayerDeath", {
	Time = 20,
	Player = "keres-decrease",
	Hunting = true,
	OtherAlive = 2,
	HuntAge = 0.5,
})
aswangSpeedSample(20.1, 9.2, true)
aswangSpeedSample(20.3, 9.2, true)
aswangSpeedSample(20.5, 9.2, true)
aswangSpeedSample(20.66, 9.2, true)
expect(api.RuleOuts.Aswang.Confidence == 94, "a stable 7% post-kill decrease should rule out Aswang")
expect(api.Detections.Keres.Confidence == 97, "the raw decrease should reach Keres through the shared kill-speed hook")
expect(runtime:Snapshot().Observers.Aswang.LastDeathOutcome == "Decrease", "the Aswang observer should retain its raw decrease outcome")

-- A certain salt slowdown is stronger than the ambiguous downward kill-speed
-- clue, so both Aswang and Keres observers must leave that salt result intact.
reset()
runtime:Dispatch("OnSaltSpeed", {Outcome = "Recovered", Reason = "verified salt slowdown and recovery"})
aswangPreKillSamples(30)
runtime:Dispatch("OnPlayerDeath", {
	Time = 30,
	PlayerId = "salt-gated-decrease",
	Hunting = true,
	OtherAlive = 1,
	HuntAge = 1,
})
aswangSpeedSample(30.1, 9.2, true)
aswangSpeedSample(30.3, 9.2, true)
aswangSpeedSample(30.5, 9.2, true)
aswangSpeedSample(30.66, 9.2, true)
expect(api.Detections.Aswang.Confidence == 99, "a raw decrease must not override a certain Aswang salt result")
expect(api.RuleOuts.Aswang == nil and api.Detections.Keres == nil, "the strong salt gate should suppress both sides of a raw decrease")

-- Invalid, non-unique, or statistically unstable deaths never arm the raw
-- classifier. Repeated callbacks for one player keep one pending window.
reset()
aswangPreKillSamples(40)
runtime:Dispatch("OnPlayerDeath", {
	Time = 40,
	PlayerId = "solo-death",
	Hunting = true,
	OtherAlive = 0,
	HuntAge = 1,
})
runtime:Dispatch("OnPlayerDeath", {
	Time = 40,
	PlayerId = "early-death",
	Hunting = true,
	OtherAlive = 1,
	HuntAge = 0.49,
})
runtime:Dispatch("OnPlayerDeath", {
	Time = 40,
	PlayerId = "non-unique-death",
	Hunting = true,
	OtherAlive = 1,
	HuntAge = 1,
	UniqueSpeedKill = false,
})
runtime:Dispatch("OnPlayerDeath", {
	Time = 40,
	PlayerId = "duplicate-death",
	Hunting = true,
	OtherAlive = 1,
	HuntAge = 1,
	Unique = true,
})
runtime:Dispatch("OnPlayerDeath", {
	Time = 40,
	PlayerId = "duplicate-death",
	Hunting = true,
	OtherAlive = 1,
	HuntAge = 1,
	Unique = true,
})
expect(runtime:Snapshot().Observers.Aswang.PendingDeathCount == 1, "duplicate player death callbacks should arm only one raw window")
reset()
aswangPreKillSamples(50, {9, 10, 11})
runtime:Dispatch("OnPlayerDeath", {
	Time = 50,
	PlayerId = "unstable-baseline",
	Hunting = true,
	OtherAlive = 1,
	HuntAge = 1,
})
expect(runtime:Snapshot().Observers.Aswang.PendingDeathCount == 0, "an unstable three-sample pre-kill median must not arm Aswang")

-- An unresolved raw death expires after 2.5 seconds without inventing an
-- outcome, even when a later hunting sample arrives.
reset()
aswangPreKillSamples(60)
runtime:Dispatch("OnPlayerDeath", {
	Time = 60,
	PlayerId = "expired-death",
	Hunting = true,
	OtherAlive = 1,
	HuntAge = 1,
})
aswangSpeedSample(62.51, 10, true)
expect(runtime:Snapshot().Observers.Aswang.PendingDeathCount == 0, "an unresolved Aswang death window should expire after 2.5 seconds")
expect(runtime:Snapshot().Observers.Aswang.LastDeathOutcome == nil, "death-window expiry should not create an Aswang outcome")
expect(api.Detections.Aswang == nil and api.RuleOuts.Aswang == nil, "death-window expiry should not change Aswang confidence")

-- Dybbuk: the residual evidence combination is a reversible tentative clue.
reset()
runtime:Dispatch("OnCompletedHunt", {
	HadQualifiedWindow = true,
	PatternObserved = false,
})
runtime:Dispatch("OnResidualEvidence", {Qualified = true, Reason = "residual combination"})
expect(api.Detections.Dybbuk.Confidence == 60, "qualified residual evidence should detect Dybbuk")
runtime:Dispatch("OnResidualEvidence", {Qualified = false})
expect(api.Detections.Dybbuk == nil, "an invalidated residual combination should clear Dybbuk")

-- Entity/Skinwalker own the complete raw room-jump and SmokeHolder windows.
-- A fast, long room-to-room object movement remains pending until either a
-- nearby smoke fact arrives or the observer-owned 1.4-second window expires.
reset()
runtime:Dispatch("OnObjectTeleport", {
	Kind = "MotionSample",
	Time = 10,
	Object = "laser-a",
	Elapsed = 0.4,
	Displacement = 40,
	Speed = 100,
	FromPosition = {X = 0, Y = 0, Z = 0},
	ToPosition = {X = 40, Y = 0, Z = 0},
	FromRoom = "Classroom",
	ToRoom = "Storage",
})
expect(api.Detections.Entity == nil and api.Detections.Skinwalker == nil, "raw object motion should wait for its smoke window")
runtime:Dispatch("OnObjectTeleport", {
	Kind = "SmokeObserved",
	Time = 10.2,
	Position = {X = 8, Y = 0, Z = 0},
})
expect(api.Detections.Entity.Confidence == 99, "nearby raw SmokeHolder evidence should detect Entity")
expect(api.RuleOuts.Skinwalker.Confidence == 95, "nearby raw SmokeHolder evidence should rule out Skinwalker")
expect(string.find(api.Detections.Entity.Reason, "Classroom to Storage", 1, true) ~= nil, "Entity should own its measured teleport reason")

reset()
runtime:Dispatch("OnObjectTeleport", {
	Kind = "MotionSample",
	Time = 20,
	Object = "emf-a",
	Elapsed = 0.4,
	Displacement = 40,
	Speed = 100,
	FromPosition = {X = 0, Y = 0, Z = 0},
	ToPosition = {X = 40, Y = 0, Z = 0},
	FromRoom = "Classroom",
	ToRoom = "Storage",
})
runtime:Tick({Time = 21.39})
expect(api.Detections.Skinwalker == nil and api.RuleOuts.Entity == nil, "no-smoke classification must not resolve early")
runtime:Tick({Time = 21.41})
expect(api.Detections.Skinwalker.Confidence == 97, "an expired raw no-smoke window should detect Skinwalker")
expect(api.RuleOuts.Entity.Confidence == 95, "an expired raw no-smoke window should rule out Entity")

-- Sub-threshold movement and automation relocation are raw adapter facts, not
-- teleport conclusions. Neither may leak into a later observer tick.
reset()
runtime:Dispatch("OnObjectTeleport", {
	Kind = "MotionSample",
	Time = 30,
	Object = "camera-a",
	Elapsed = 0.4,
	Displacement = 24.9,
	Speed = 100,
	FromPosition = {X = 0, Y = 0, Z = 0},
	ToPosition = {X = 24.9, Y = 0, Z = 0},
	FromRoom = "Classroom",
	ToRoom = "Storage",
})
runtime:Tick({Time = 32})
expect(api.Detections.Entity == nil and api.Detections.Skinwalker == nil, "short object movement should not qualify as a teleport")
runtime:Dispatch("OnObjectTeleport", {
	Kind = "MotionSample",
	Time = 33,
	Object = "camera-a",
	Elapsed = 0.4,
	Displacement = 40,
	Speed = 100,
	FromPosition = {X = 0, Y = 0, Z = 0},
	ToPosition = {X = 40, Y = 0, Z = 0},
	FromRoom = "Classroom",
	ToRoom = "Storage",
})
runtime:Dispatch("OnObjectTeleport", {Kind = "AutomationSuppressed", Time = 33.1, Eligible = false})
runtime:Tick({Time = 35})
expect(api.RuleOuts.Entity == nil and api.Detections.Skinwalker == nil, "automation suppression should cancel pending object teleport windows")

-- Ghost teleport thresholds, warmup, delayed room confirmation, and reasons
-- are likewise observer-owned. Both ghosts remain possible for this shared
-- ability observation.
reset()
runtime:Dispatch("OnGhostTeleport", {
	Kind = "MotionSample",
	Time = 40,
	Elapsed = 0.1,
	Displacement = 1,
	Speed = 10,
	FromRoom = "Classroom",
	ToRoom = "Classroom",
	CurrentRoom = "Classroom",
	PreviousInside = true,
	CurrentInside = true,
})
runtime:Dispatch("OnGhostTeleport", {
	Kind = "MotionSample",
	Time = 42.1,
	Elapsed = 0.2,
	Displacement = 30,
	Speed = 150,
	FromRoom = "Classroom",
	ToRoom = "Storage",
	CurrentRoom = "Storage",
	PreviousInside = true,
	CurrentInside = true,
})
expect(api.Detections.Entity == nil and api.Detections.Skinwalker == nil, "raw ghost jump should wait for destination confirmation")
runtime:Dispatch("OnGhostTeleport", {
	Kind = "MotionSample",
	Time = 43.36,
	Elapsed = 0.1,
	Displacement = 0,
	Speed = 0,
	FromRoom = "Storage",
	ToRoom = "Storage",
	CurrentRoom = "Storage",
	PreviousInside = true,
	CurrentInside = true,
})
expect(api.Detections.Entity.Confidence == 65, "confirmed raw ghost teleport should retain Entity")
expect(api.Detections.Skinwalker.Confidence == 65, "confirmed raw ghost teleport should retain Skinwalker")
expect(string.find(api.Detections.Entity.Reason, "30.0 studs", 1, true) ~= nil, "ghost observer should own its measured reason")

reset()
runtime:Dispatch("OnGhostTeleport", {
	Kind = "MotionSample",
	Time = 50,
	Elapsed = 0.1,
	Displacement = 1,
	Speed = 10,
	FromRoom = "Classroom",
	ToRoom = "Classroom",
	CurrentRoom = "Classroom",
	PreviousInside = true,
	CurrentInside = true,
})
runtime:Dispatch("OnGhostTeleport", {
	Kind = "MotionSample",
	Time = 52.1,
	Elapsed = 0.2,
	Displacement = 40,
	Speed = 200,
	FromRoom = "Classroom",
	ToRoom = "Storage",
	CurrentRoom = "Storage",
	PreviousInside = false,
	CurrentInside = true,
})
runtime:Dispatch("OnGhostTeleport", {
	Kind = "MotionSample",
	Time = 53.36,
	Elapsed = 0.1,
	Displacement = 0,
	Speed = 0,
	FromRoom = "Storage",
	ToRoom = "Storage",
	CurrentRoom = "Storage",
	PreviousInside = true,
	CurrentInside = true,
})
expect(api.Detections.Entity == nil and api.Detections.Skinwalker == nil, "a jump starting outside its stated room bounds should be rejected")

-- Ghoul: a hunting electronic shutoff near the ghost is its implemented high
-- negative; unrelated gameplay produces no observer event.
reset()
runtime:Dispatch("OnElectronicDisabled", {Reason = "nearby electronic disabled"})
expect(api.RuleOuts.Ghoul.Confidence == 98, "a verified electronic shutoff should rule out Ghoul")
reset()
runtime:Dispatch("OnElectronicDisabled", {
	RawObservation = true,
	Previous = true,
	Current = false,
	Hunting = false,
	GhostDistance = 4,
	NearestPlayerDistance = 20,
})
expect(api.RuleOuts.Ghoul == nil, "a non-hunt raw item shutoff should not rule out Ghoul")
runtime:Dispatch("OnElectronicDisabled", {
	RawObservation = true,
	Previous = true,
	Current = false,
	Hunting = true,
	GhostDistance = 4,
	NearestPlayerDistance = 20,
})
expect(api.RuleOuts.Ghoul.Confidence == 98, "the Ghoul observer should classify a raw nearby hunt shutoff")

-- Keres: kill-speed direction provides the positive/negative pair and female
-- indicators remain persistent low-confidence support.
reset()
runtime:Dispatch("OnKillSpeed", {Direction = "Increase", Reason = "upward death speed"})
expect(api.RuleOuts.Keres.Confidence == 94, "an upward death speed should rule out Keres")
reset()
runtime:Dispatch("OnKillSpeed", {Direction = "Decrease", Count = 1, Reason = "downward death speed"})
expect(api.Detections.Keres.Confidence == 97, "a downward death speed should detect Keres")
expect(api.RuleOuts.Aswang.Confidence == 94, "a Keres decrease should rule out Aswang")
reset()
runtime:Dispatch("OnFemaleIndicator", {Reason = "female model or voice"})
expect(api.Detections.Keres.Confidence == 35 and api.Detections.Keres.Persistent == true, "female indicator should persist Keres support")
expect(api.Detections.Siren.Confidence == 35 and api.Detections.Siren.Persistent == true, "female indicator should persist Siren support")

local function keresSpeed(time, speed, huntSerial, hunting)
	runtime:Dispatch("OnSpeedSample", {
		Time = time,
		Speed = speed,
		Hunting = hunting ~= false,
		HuntSerial = huntSerial,
	})
end

local function keresPreSamples(deathTime, speed, huntSerial)
	keresSpeed(deathTime - 0.8, speed, huntSerial)
	keresSpeed(deathTime - 0.45, speed, huntSerial)
	keresSpeed(deathTime - 0.1, speed, huntSerial)
end

local function keresDeath(deathTime, playerId, huntSerial, overrides)
	local event = {
		Time = deathTime,
		PlayerId = playerId,
		Hunting = true,
		OtherAlive = 1,
		HuntAge = 1,
		HuntSerial = huntSerial,
	}
	for key, value in pairs(overrides or {}) do
		event[key] = value
	end
	runtime:Dispatch("OnPlayerDeath", event)
end

local function keresState()
	return runtime:Snapshot().Observers.Keres
end

-- Keres owns the raw rolling window and its repeated-kill count. Three stable
-- pre/post samples with an 8% drop resolve at +0.65 seconds.
reset()
keresPreSamples(101, 10, 11)
keresDeath(101, 1011, 11)
keresSpeed(101.1, 9.2, 11)
keresSpeed(101.35, 9.2, 11)
expect(api.Detections.Keres == nil, "two post-death samples should not classify Keres")
keresSpeed(101.66, 9.2, 11)
expect(api.Detections.Keres.Confidence == 97, "a stable 8% raw post-kill drop should detect Keres")
expect(keresState().KillDecreaseCount == 1, "Keres should own its raw decrease count")
expect(keresState().LastRawOutcome == "Decrease", "the raw Keres outcome should be inspectable")

-- Repeating the same player's death cannot open another window. A second
-- unique player in the same round raises the module-owned confidence count.
keresPreSamples(103, 9.2, 11)
keresDeath(103, 1011, 11)
keresSpeed(103.1, 8.4, 11)
keresSpeed(103.35, 8.4, 11)
keresSpeed(103.66, 8.4, 11)
expect(keresState().KillDecreaseCount == 1, "a duplicate player death should be ignored")
expect(keresState().ProcessedDeathCount == 1, "a duplicate death should not increase the unique count")
keresPreSamples(105, 9.2, 11)
keresDeath(105, 1012, 11)
keresSpeed(105.1, 8.4, 11)
keresSpeed(105.35, 8.4, 11)
keresSpeed(105.66, 8.4, 11)
expect(api.Detections.Keres.Confidence == 99, "a second unique raw kill drop should confirm Keres")
expect(keresState().KillDecreaseCount == 2, "the second raw drop should increment Keres once")
expect(keresState().ProcessedDeathCount == 2, "Keres should count unique processed deaths")

-- A valid raw kill must be hunting, multiplayer, at least 0.5 seconds into the
-- hunt, and explicitly unique when the adapter says otherwise.
for _, invalid in ipairs({
	{Hunting = false},
	{OtherAlive = 0},
	{HuntAge = 0.49},
	{UniqueSpeedKill = false},
}) do
	reset()
	keresPreSamples(201, 10, 21)
	keresDeath(201, 2021, 21, invalid)
	keresSpeed(201.1, 9, 21)
	keresSpeed(201.35, 9, 21)
	keresSpeed(201.66, 9, 21)
	expect(api.Detections.Keres == nil, "an unqualified raw death must not detect Keres")
	expect(keresState().ProcessedDeathCount == 0, "unqualified deaths should not consume a unique kill")
end

-- The pre-death baseline requires three in-window stable samples. A sample in
-- the final 0.05-second replication gap is excluded, and noisy baselines fail.
reset()
keresSpeed(300.2, 10, 31)
keresSpeed(300.55, 10, 31)
keresSpeed(300.97, 10, 31)
keresDeath(301, 3031, 31)
expect(keresState().PendingKill == nil, "a final-gap sample should not complete the pre-death baseline")
expect(keresState().LastRawOutcome == "UnstablePre", "an incomplete baseline should be recorded")
reset()
keresSpeed(310.2, 9, 32)
keresSpeed(310.55, 10, 32)
keresSpeed(310.9, 11, 32)
keresDeath(311, 3032, 32)
expect(keresState().PendingKill == nil, "a noisy pre-death median should be rejected")

-- A stable 15% increase is the opposing raw observation and the Keres module
-- resolves only its local compatibility hook.
reset()
keresPreSamples(401, 10, 41)
keresDeath(401, 4041, 41)
keresSpeed(401.1, 11.5, 41)
keresSpeed(401.35, 11.5, 41)
keresSpeed(401.66, 11.5, 41)
expect(api.RuleOuts.Keres.Confidence == 94, "a stable raw 15% kill increase should rule out Keres")
expect(keresState().LastRawOutcome == "Increase", "the raw increase should resolve once")

-- A stable non-decrease cannot rule Keres out before +1.25 seconds, but it
-- resolves from a Tick once that deadline is reached.
reset()
keresPreSamples(501, 10, 51)
keresDeath(501, 5051, 51)
keresSpeed(501.1, 10, 51)
keresSpeed(501.35, 10, 51)
keresSpeed(501.66, 10, 51)
runtime:Tick({Time = 502.24, Hunting = true, HuntSerial = 51})
expect(api.RuleOuts.Keres == nil, "a stable speed should not rule out Keres before +1.25")
runtime:Tick({Time = 502.26, Hunting = true, HuntSerial = 51})
expect(api.RuleOuts.Keres.Confidence == 92, "a stable no-decrease should rule out Keres by +1.25")
expect(keresState().LastRawOutcome == "StableNoDecrease", "stable raw outcome should be retained")

-- Samples earlier than +0.08 never count toward the post window, and an
-- unstable unresolved window expires at 2.5 seconds without a finding.
reset()
keresPreSamples(601, 10, 61)
keresDeath(601, 6061, 61)
keresSpeed(601.01, 9.2, 61)
keresSpeed(601.04, 9.2, 61)
keresSpeed(601.07, 9.2, 61)
keresSpeed(601.1, 9.2, 61)
keresSpeed(601.35, 9.2, 61)
keresSpeed(601.66, 9.2, 61)
expect(api.Detections.Keres.Confidence == 97, "only three samples after +0.08 should classify")
reset()
keresPreSamples(701, 10, 71)
keresDeath(701, 7071, 71)
keresSpeed(701.1, 8, 71)
keresSpeed(701.35, 12, 71)
keresSpeed(701.66, 10, 71)
runtime:Tick({Time = 703.49, Hunting = true, HuntSerial = 71})
expect(keresState().PendingKill ~= nil, "an unstable post window should remain pending before expiry")
runtime:Tick({Time = 703.5, Hunting = true, HuntSerial = 71})
expect(keresState().PendingKill == nil, "an unresolved raw Keres window should expire at 2.5 seconds")
expect(keresState().LastRawOutcome == "Expired", "expiry should be observable without a finding")
expect(api.Detections.Keres == nil and api.RuleOuts.Keres == nil, "expiry should not create a Keres finding")

-- Leviathan: a single flicker pairs the mimicking Skinwalker possibility;
-- the unique out-of-hunt light-off clue upgrades Leviathan and removes that pair.
reset()
runtime:Dispatch("OnClue", {Kind = "Fuse", Reason = "not a supported clue"})
expect(api.RefreshCount == 0, "unsupported Leviathan clue kinds should be ignored")
runtime:Dispatch("OnClue", {
	Kind = "Flicker",
	Corroborated = false,
	SkinwalkerPossible = true,
	Reason = "rapid equipment flicker",
})
expect(api.Detections.Leviathan.Confidence == 60, "one flicker should tentatively detect Leviathan")
expect(api.Detections.Leviathan.Persistent == true, "Leviathan flicker should persist")
expect(api.Detections.Skinwalker.Confidence == 60, "one flicker should retain Skinwalker mimicry")
runtime:Dispatch("OnClue", {Kind = "LightOff", Reason = "room light shut off"})
expect(api.Detections.Leviathan.Confidence == 99, "room light-off should strongly detect Leviathan")
expect(api.Detections.Skinwalker == nil, "the unique light-off clue should clear the one-clue Skinwalker pair")

local function dispatchLeviathanItemSequence(options)
	options = options or {}
	local state = false
	for index = 1, (options.Count or 9) do
		local nextState = not state
		runtime:Dispatch("OnItemToggle", {
			ItemId = options.ItemId or "laser-a",
			ItemName = options.ItemName or "Laser Projector",
			Previous = state,
			Current = nextState,
			Time = (options.StartTime or 100) + (index - 1) * (options.Interval or 0.1),
			Hunting = options.Hunting == true,
			AutomationSuppressed = options.AutomationSuppressed == true,
			Eligible = options.Eligible ~= false,
			GhostDistance = options.GhostDistance or 6,
			NearestPlayerDistance = options.NearestPlayerDistance or 10,
			SkinwalkerPossible = options.SkinwalkerPossible,
		})
		state = nextState
	end
end

-- Raw per-item toggles own the rolling alternation, timing, and ghost/player
-- causality checks. Eight toggles are insufficient; the ninth qualifies.
reset()
api.SupportedEvidence.Skinwalker = true
dispatchLeviathanItemSequence({Count = 8, SkinwalkerPossible = true})
expect(api.Detections.Leviathan == nil, "eight raw item toggles should not identify Leviathan")
runtime:Dispatch("OnItemToggle", {
	ItemId = "laser-a",
	ItemName = "Laser Projector",
	Previous = false,
	Current = true,
	Time = 100.8,
	Hunting = false,
	Eligible = true,
	GhostDistance = 6,
	NearestPlayerDistance = 10,
	SkinwalkerPossible = true,
})
expect(api.Detections.Leviathan.Confidence == 60, "nine clean raw toggles should support Leviathan")
expect(string.find(api.Detections.Leviathan.Reason, "9 clean alternating toggles", 1, true) ~= nil, "raw Leviathan reason should include its measured toggle count")
expect(api.Detections.Skinwalker.Confidence == 60, "one raw flicker should retain Skinwalker mimicry")

-- A single eligible room-light off edge resolves after 0.6 seconds and
-- corroborates the recent flicker within the module-owned 12-second window.
runtime:Dispatch("OnLightToggle", {
	Room = "Classroom",
	Previous = true,
	Current = false,
	Time = 105,
	Hunting = false,
	Eligible = true,
	FuseEnabled = true,
})
runtime:Tick({Time = 105.59, FuseEnabled = true})
expect(api.Detections.Leviathan.Confidence == 60, "a raw room-light edge should wait the full 0.6 seconds")
runtime:Tick({Time = 105.61, FuseEnabled = true})
expect(api.Detections.Leviathan.Confidence == 99, "one resolved raw room-light edge should strongly detect Leviathan")
expect(string.find(api.Detections.Leviathan.Reason, "room Classroom", 1, true) ~= nil, "raw light reason should name the affected room")
expect(runtime:Snapshot().Observers.Leviathan.LastCorroborated == true, "raw flicker and light observations within 12 seconds should corroborate")

-- Hunt/automation events never enter the item window. Multiple simultaneous
-- room edges and a disabled fuse are rejected as non-unique power events.
reset()
dispatchLeviathanItemSequence({Hunting = true})
dispatchLeviathanItemSequence({ItemId = "suppressed", AutomationSuppressed = true})
expect(api.Detections.Leviathan == nil, "hunting or suppressed raw item toggles should be ignored")
runtime:Dispatch("OnLightToggle", {
	Room = "Classroom",
	OffEdge = true,
	Time = 200,
	Hunting = false,
	Eligible = true,
	FuseEnabled = true,
})
runtime:Dispatch("OnLightToggle", {
	Room = "Storage",
	OffEdge = true,
	Time = 200.2,
	Hunting = false,
	Eligible = true,
	FuseEnabled = true,
})
runtime:Tick({Time = 200.7, FuseEnabled = true})
expect(api.Detections.Leviathan == nil, "two raw room off edges in one batch should not identify Leviathan")
runtime:Dispatch("OnLightToggle", {
	Room = "Hallway",
	OffEdge = true,
	Time = 210,
	Hunting = false,
	Eligible = true,
	FuseEnabled = false,
})
runtime:Tick({Time = 210.7, FuseEnabled = false})
expect(api.Detections.Leviathan == nil, "a raw room edge while the fuse is disabled should be ignored")

-- The game adapter can provide unclassified room/switch snapshots. Leviathan
-- owns the transition pairing, causality distances, and 0.6-second batch.
reset()
runtime:Dispatch("OnLightToggle", {
	RawObservation = true,
	RoomId = "raw-classroom",
	Room = "Classroom",
	LightsOn = true,
	SwitchState = true,
	Time = 220,
	Hunting = false,
	FuseEnabled = true,
	SwitchPresent = true,
	GhostDistance = 5,
	NearestPlayerDistance = 20,
})
runtime:Dispatch("OnLightToggle", {
	RawObservation = true,
	RoomId = "raw-classroom",
	Room = "Classroom",
	LightsOn = false,
	SwitchState = true,
	Time = 221,
	Hunting = false,
	FuseEnabled = true,
	SwitchPresent = true,
	GhostDistance = 5,
	NearestPlayerDistance = 20,
})
runtime:Dispatch("OnLightToggle", {
	RawObservation = true,
	RoomId = "raw-classroom",
	Room = "Classroom",
	LightsOn = false,
	SwitchState = false,
	Time = 221.2,
	Hunting = false,
	FuseEnabled = true,
	SwitchPresent = true,
	GhostDistance = 5,
	NearestPlayerDistance = 20,
})
runtime:Tick({Time = 221.81})
expect(api.Detections.Leviathan.Confidence == 99, "Leviathan should classify a clean raw room/switch snapshot sequence")

-- Revenant: whether the hunt stopped immediately after a kill is the direct
-- positive/negative split.
reset()
runtime:Dispatch("OnKillHuntOutcome", {Stopped = true, Reason = "hunt stopped on kill"})
expect(api.Detections.Revenant.Confidence == 35, "hunt stop on kill should support Revenant")
runtime:Dispatch("OnKillHuntOutcome", {Stopped = false, Reason = "hunt continued"})
expect(api.Detections.Revenant == nil and api.RuleOuts.Revenant.Confidence == 95, "continued hunt should rule out Revenant")

-- Revenant owns the raw multiplayer death timing window. Invalid deaths never
-- arm it, a continuing hunt resolves after one second, and a prompt hunt end
-- resolves the same pending death as its weakness.
reset()
runtime:Dispatch("OnPlayerDeath", {
	Time = 1,
	Hunting = false,
	OtherAlive = 1,
	HuntAge = 2,
})
runtime:Dispatch("OnPlayerDeath", {
	Time = 2,
	Hunting = true,
	OtherAlive = 0,
	HuntAge = 2,
})
runtime:Dispatch("OnPlayerDeath", {
	Time = 3,
	Hunting = true,
	OtherAlive = 1,
	HuntAge = 0.4,
})
runtime:Tick({Time = 5, Hunting = true})
expect(api.Detections.Revenant == nil and api.RuleOuts.Revenant == nil, "invalid raw deaths should not arm Revenant")

runtime:Dispatch("OnPlayerDeath", {
	Time = 10,
	Hunting = true,
	OtherAlive = 1,
	HuntAge = 2,
	ContinueReason = "verified hunt continued for one second",
})
expect(runtime:Snapshot().Observers.Revenant.PendingKill.Time == 10, "a valid hunting multiplayer death should become pending")
runtime:Tick({Time = 10.99, Hunting = true})
expect(api.RuleOuts.Revenant == nil, "a pending kill should wait the full continuation window")
runtime:Tick({Time = 11, Hunting = true})
expect(api.RuleOuts.Revenant.Confidence == 95, "one continued hunting second should rule out Revenant")
expect(runtime:Snapshot().Observers.Revenant.PendingKill == nil, "continued-hunt resolution should clear the pending kill")

reset()
runtime:Dispatch("OnPlayerDeath", {
	Time = 20,
	Hunting = true,
	OtherAlive = 2,
	HuntAge = 1.5,
	StopReason = "verified hunt ended promptly after the kill",
})
runtime:Dispatch("OnHuntEnded", {Time = 20.8})
expect(api.Detections.Revenant.Confidence == 35, "hunt end within one second should support Revenant")
expect(runtime:Snapshot().Observers.Revenant.PendingKill == nil, "hunt-end resolution should clear the pending kill")

reset()
runtime:Dispatch("OnPlayerDeath", {
	Time = 30,
	Hunting = true,
	OtherAlive = 1,
	HuntAge = 1,
})
runtime:Tick({Time = 32.6, Hunting = false})
expect(runtime:Snapshot().Observers.Revenant.PendingKill == nil, "an unresolved pending kill should expire after 2.5 seconds")
expect(api.Detections.Revenant == nil and api.RuleOuts.Revenant == nil, "expiry should not invent a Revenant outcome")

-- Siren: humming/female responses provide paired clues, while controlled LOS
-- slow and no-slow outcomes are opposing high-confidence observations.
reset()
runtime:Dispatch("OnSpiritBox", {
	Kind = "Humming",
	SkinwalkerPossible = true,
	Reason = "humming response",
})
expect(api.Detections.Siren.Confidence == 60, "mimickable humming should support Siren")
expect(api.Detections.Skinwalker.Confidence == 60, "mimickable humming should support Skinwalker")
reset()
runtime:Dispatch("OnSpiritBoxObservation", {
	Subtitle = "indexed response",
	Female = true,
})
expect(api.Detections.Keres.Confidence == 35 and api.Detections.Siren.Confidence == 35, "indexed female metadata should support Keres and Siren")
reset()
runtime:Dispatch("OnSpiritBox", {Kind = "Female", Reason = "female response"})
expect(api.Detections.Keres.Confidence == 35 and api.Detections.Siren.Confidence == 35, "female voice should support Keres and Siren")
api.RuleOuts.Siren = {Confidence = 90}
runtime:Dispatch("OnLosSlow", {Reason = "player slowed in LOS", Confidence = 95})
expect(api.RuleOuts.Siren == nil and api.Detections.Siren.Confidence == 95, "LOS slowdown should detect Siren")
runtime:Dispatch("OnHuntLosNegative", {Reason = "no slowdown during sustained LOS"})
expect(api.Detections.Siren == nil and api.RuleOuts.Siren.Confidence == 90, "sustained LOS without slowdown should rule out Siren")

-- Skinwalker: generic mimic clues can be persistent in addition to the paired
-- teleport hooks exercised above.
reset()
runtime:Dispatch("OnMimicClue", {
	Reason = "copied ghost ability",
	Confidence = 65,
	Persistent = true,
})
expect(api.Detections.Skinwalker.Confidence == 65, "mimic clue should detect Skinwalker")
expect(api.Detections.Skinwalker.Persistent == true, "persistent mimic clue should be marked")

-- Specter: repeated favourite-room residence is positive; verified departure
-- outside a hunt is the opposing high negative.
reset()
runtime:Dispatch("OnFavouriteResidence", {Count = 2, Reason = "two stable residences"})
expect(api.Detections.Specter.Confidence == 65, "repeated residence should support Specter")
runtime:Dispatch("OnDeparture", {Reason = "left favourite room outside hunt"})
expect(api.Detections.Specter == nil and api.RuleOuts.Specter.Confidence == 95, "non-hunt departure should rule out Specter")

-- Banshee: a single break is ignored; a burst records the positive.
reset()
runtime:Dispatch("OnBrokenGlassBurst", {Count = 1})
expect(api.Detections.Banshee == nil and api.RefreshCount == 0, "one glass break should be ignored")
runtime:Dispatch("OnBrokenGlassBurst", {Count = 2, Reason = "glass burst"})
expect(api.Detections.Banshee.Confidence == 60, "Banshee burst should detect at 60")
expect(api.Detections.Banshee.Reason == "glass burst", "Banshee should preserve the event reason")

-- Demon: rejected Cross motion rules it out; matched motion clears that negative.
reset()
runtime:Dispatch("OnCrossMotion", {Outcome = "Rejected", Reason = "cross stayed still"})
expect(api.RuleOuts.Demon.Confidence == 92, "rejected Cross motion should rule out Demon")
runtime:Dispatch("OnCrossMotion", {Outcome = "Matched", Reason = "cross floated"})
expect(api.RuleOuts.Demon == nil, "matched Cross motion should clear the Demon rule-out")
expect(api.Detections.Demon.Confidence == 99, "matched Cross motion should detect Demon")

-- Dullahan: a completed qualified negative is reversible by a later step pattern.
reset()
runtime:Dispatch("OnHuntSpeedWindow", {
	SampleCount = 5,
	IncreaseCount = 2,
	Duration = 0.4,
	Matched = false,
})
expect(api.Detections.Dullahan == nil, "an insufficient speed window should not detect Dullahan")
runtime:Dispatch("OnCompletedHunt", {
	HadQualifiedWindow = true,
	PatternObserved = false,
	Reason = "no short speed steps",
})
expect(api.RuleOuts.Dullahan.Confidence == 92, "a qualified negative hunt should rule out Dullahan")
api.Detections.Dybbuk = {Confidence = 60}
api.Detections.Oni = {Confidence = 95}
api.Detections.Wendigo = {Confidence = 99}
runtime:Dispatch("OnHuntSpeedWindow", {
	SampleCount = 5,
	IncreaseCount = 3,
	Duration = 0.4,
	Matched = true,
	Reason = "three rapid increases",
})
expect(api.RuleOuts.Dullahan == nil, "a matched speed window should clear Dullahan's rule-out")
expect(api.Detections.Dullahan.Confidence == 99, "a matched speed window should detect Dullahan")
expect(api.Detections.Dybbuk == nil and api.Detections.Oni == nil, "Dullahan should clear rival detections")
expect(api.Detections.Wendigo == nil, "definitive Dullahan steps should clear an earlier Wendigo speed result")

-- Dullahan's raw observer owns the five-sample timing and increase count. A
-- decrease in the middle does not invalidate three distinct upward steps.
reset()
runtime:Dispatch("OnHuntSpeedSamples", {
	Samples = {
		{Time = 0.0, Speed = 11.0},
		{Time = 0.1, Speed = 11.2},
		{Time = 0.2, Speed = 11.1},
		{Time = 0.3, Speed = 11.3},
		{Time = 0.4, Speed = 11.4},
	},
})
expect(api.Detections.Dullahan.Confidence == 99, "raw Dullahan steps should detect without a precomputed outcome")
reset()
runtime:Dispatch("OnHuntSpeedSamples", {
	Samples = {
		{Time = 0.0, Speed = 11.0},
		{Time = 0.1, Speed = 11.2},
		{Time = 0.2, Speed = 11.1},
		{Time = 0.3, Speed = 11.3},
		{Time = 0.4, Speed = 11.3},
	},
	HuntEnded = true,
})
expect(api.RuleOuts.Dullahan.Confidence == 92, "a completed qualified raw hunt with only two increases should rule out Dullahan")

-- Oni: its 13.5 base mode detects; a stable ordinary 11 base mode rules it out.
reset()
api.RuleOuts.Oni = {Confidence = 95}
runtime:Dispatch("OnVisibleHuntSpeed", {
	Outcome = "Matched",
	Reason = "13.5 base mode",
	Confidence = 99,
})
expect(api.RuleOuts.Oni == nil and api.Detections.Oni.Confidence == 99, "Oni match should replace its negative")
runtime:Dispatch("OnVisibleHuntSpeed", {Outcome = "Ordinary", Reason = "11 base mode"})
expect(api.Detections.Oni == nil and api.RuleOuts.Oni.Confidence == 95, "ordinary speed should rule out Oni")

-- Oni's raw observer normalizes map size and tests only the six valid hunting
-- multipliers. Medium-map 200% samples distinguish 13.5 from ordinary 11.
reset()
runtime:Dispatch("OnVisibleHuntSpeedSamples", {
	Speeds = {28.35, 28.35, 28.35},
	MapFactor = 1.05,
	HuntEnded = true,
})
expect(api.Detections.Oni.Confidence == 95, "raw 13.5-base Oni samples should detect on a medium map")
runtime:Dispatch("OnVisibleHuntSpeedSamples", {
	Speeds = {28.35, 28.35, 28.35},
	MapFactor = 1.05,
	HuntEnded = true,
})
expect(api.Detections.Oni.Confidence == 99, "a second qualified raw Oni hunt should raise confidence")
reset()
runtime:Dispatch("OnVisibleHuntSpeedSamples", {
	Speeds = {23.1, 23.1, 23.1, 23.1},
	MapFactor = 1.05,
})
expect(api.RuleOuts.Oni.Confidence == 95, "23.1 at medium-map 200% should normalize to ordinary base 11")
reset()
runtime:Dispatch("OnVisibleHuntSpeedSamples", {
	Samples = {
		{Time = 1.0, GhostWalkSpeed = 23.1, Hunting = true},
		{Time = 1.1, GhostWalkSpeed = 23.1, Hunting = true},
		{Time = 1.2, GhostWalkSpeed = 23.1, Hunting = true},
		{Time = 1.3, GhostWalkSpeed = 23.1, Hunting = true},
	},
	Time = 1.3,
	MapFactor = 1.05,
})
expect(api.Detections.Oni == nil and api.RuleOuts.Oni == nil, "unknown transparency samples must not count as visible Oni data")
reset()
runtime:Dispatch("OnVisibleHuntSpeedSamples", {
	Samples = {
		{Time = 0, GhostWalkSpeed = 40, Hunting = true, Invisible = false},
		{Time = 4.0, GhostWalkSpeed = 28.35, Hunting = true, Invisible = false},
		{Time = 4.1, GhostWalkSpeed = 28.35, Hunting = true, Invisible = false},
		{Time = 4.2, GhostWalkSpeed = 28.35, Hunting = true, Invisible = false},
	},
	Time = 4.2,
	MapFactor = 1.05,
})
expect(api.Detections.Oni.Confidence == 95, "Oni should use the recent rolling window instead of an old speed outlier")

-- Phantom: Mimicry pairs Skinwalker, Normal restores the prior detection, and
-- a contradicted settled pattern rules Phantom out.
reset("Mimicry")
api.Detections.Skinwalker = {
	Reason = "pre-existing Skinwalker clue",
	Confidence = 60,
	Marker = "restore-me",
}
runtime:Dispatch("OnTransparencyPattern", {
	Outcome = "Matched",
	Reason = "settled invisible-speed ratio",
	Confidence = 95,
})
expect(api.Detections.Phantom.Confidence == 95, "Phantom ratio should record Phantom")
expect(
	string.find(api.Detections.Skinwalker.Reason, "Mimicry mode", 1, true) == 1,
	"Mimicry should pair the Phantom observation with Skinwalker"
)
api.CurrentMode = "Normal"
runtime:SetMode("Normal")
expect(api.Detections.Skinwalker.Marker == "restore-me", "Normal mode should restore the prior Skinwalker clue")
runtime:Dispatch("OnTransparencyPattern", {
	Outcome = "Contradicted",
	Reason = "no invisible speed increase",
	Confidence = 90,
})
expect(api.Detections.Phantom == nil, "a contradicted Phantom pattern should clear its detection")
expect(api.RuleOuts.Phantom.Confidence == 90, "a contradicted Phantom pattern should rule it out")

-- Phantom's raw observer discards phase-edge replication samples and compares
-- settled binary Transparency phases directly.
local function phantomCycleSpeeds(invisibleSpeed)
	local samples = {}
	local phases = {
		{Invisible = false, Speed = 11},
		{Invisible = true, Speed = invisibleSpeed},
		{Invisible = false, Speed = 11},
		{Invisible = true, Speed = invisibleSpeed},
		{Invisible = false, Speed = 11},
	}
	local time = 0
	for _, phase in ipairs(phases) do
		for _ = 1, 3 do
			table.insert(samples, {
				Time = time,
				GhostWalkSpeed = phase.Speed,
				Invisible = phase.Invisible,
				Hunting = true,
			})
			time = time + 0.1
		end
	end
	return samples
end

reset()
runtime:Dispatch("OnTransparencySpeedSamples", {
	Samples = phantomCycleSpeeds(13.5),
	HuntEnded = true,
})
expect(api.Detections.Phantom.Confidence == 99, "two settled raw Phantom cycles should detect at high confidence")
reset()
runtime:Dispatch("OnTransparencySpeedSamples", {
	Samples = phantomCycleSpeeds(11),
	HuntEnded = true,
})
expect(api.RuleOuts.Phantom == nil, "one contradictory raw Phantom hunt should not rule it out")
runtime:Dispatch("OnTransparencySpeedSamples", {
	Samples = phantomCycleSpeeds(11),
	HuntEnded = true,
})
expect(api.RuleOuts.Phantom.Confidence == 90, "two contradictory raw Phantom hunts should rule it out")

-- Ravager receives raw positions; its module owns the orbit classifier.
reset()
for step = 0, 13 do
	local objects = {}
	for item = 1, 3 do
		local angle = math.rad(step * 12 + (item - 1) * 100)
		table.insert(objects, {
			ObjectId = "ravager-item-" .. tostring(item),
			AssemblyId = "ravager-assembly-" .. tostring(item),
			Position = {X = math.cos(angle) * 5, Y = 0, Z = math.sin(angle) * 5},
		})
	end
	runtime:Dispatch("OnObjectMotionFrame", {
		Time = step * 0.05,
		GhostId = "ravager-ghost",
		GhostPosition = {X = 0, Y = 0, Z = 0},
		Hunting = true,
		Objects = objects,
	})
end
expect(api.Detections.Ravager.Confidence == 99, "a raw qualified vortex should detect Ravager")

-- Spirit: blue and orange Holy Oil sequences are opposing observations.
reset()
runtime:Dispatch("OnHolyOilColor", {Kind = "Spirit", Reason = "blue sequence"})
expect(api.Detections.Spirit.Confidence == 99, "blue Holy Oil should detect Spirit")
runtime:Dispatch("OnHolyOilColor", {Kind = "NonSpirit", Reason = "orange sequence"})
expect(api.Detections.Spirit == nil and api.RuleOuts.Spirit.Confidence == 99, "orange Holy Oil should rule out Spirit")

-- Umbra: no extra root sound is positive; another sound is a decisive negative.
reset()
runtime:Dispatch("OnRootSoundScan", {HasOtherSound = false, Reason = "only Hunting sound"})
expect(api.Detections.Umbra.Confidence == 95, "silent root scan should detect Umbra")
reset()
runtime:Dispatch("OnRootSoundScan", {HasOtherSound = true, Reason = "extra footstep sound"})
expect(api.Detections.Umbra == nil and api.RuleOuts.Umbra.Confidence == 99, "extra root sound should rule out Umbra")

-- Vex: replicated LIDAR invisibility detects and clears Dybbuk; visibility rules out.
reset()
api.Detections.Dybbuk = {Confidence = 60}
runtime:Dispatch("OnLidarState", {Invisible = true, Reason = "LIDAR invisible"})
expect(api.Detections.Vex.Confidence == 99, "LIDAR invisibility should detect Vex")
expect(api.Detections.Dybbuk == nil, "Vex should clear the Dybbuk fallback")
runtime:Dispatch("OnLidarState", {Invisible = false, Reason = "LIDAR visible"})
expect(api.Detections.Vex == nil and api.RuleOuts.Vex.Confidence == 99, "LIDAR visibility should rule out Vex")

-- Wendigo: a sanity curve clears Oni; a rejected curve rules Wendigo out.
reset()
api.RuleOuts.Wendigo = {Confidence = 99}
api.Detections.Oni = {Confidence = 95}
runtime:Dispatch("OnSanitySpeedCurve", {
	Outcome = "Matched",
	Reason = "switch-time sanity curve",
	Confidence = 99,
})
expect(api.RuleOuts.Wendigo == nil, "a matched curve should clear Wendigo's rule-out")
expect(api.Detections.Wendigo.Confidence == 99, "a matched curve should detect Wendigo")
expect(api.Detections.Oni == nil, "a matched Wendigo curve should clear Oni")
runtime:Dispatch("OnSanitySpeedCurve", {Outcome = "Rejected", Reason = "curve mismatch"})
expect(api.Detections.Wendigo == nil and api.RuleOuts.Wendigo.Confidence == 99, "a rejected curve should rule out Wendigo")

-- Wendigo's raw observer derives the switch-time curve from average sanity and
-- requires one consistent map-adjusted multiplier across the needed snapshots.
reset()
api.RuleOuts.Wendigo = {Confidence = 99}
api.Detections.Oni = {Confidence = 95}
runtime:Dispatch("OnHuntTransitionSamples", {
	Snapshots = {
		{Sanity = 50, Speed = 18.1125, Hunting = true},
		{Sanity = 40, Speed = 18.9, Hunting = false},
		{Sanity = 30, Speed = 19.6875, Hunting = true},
	},
	MapFactor = 1.05,
})
expect(api.RuleOuts.Wendigo == nil and api.Detections.Wendigo.Confidence == 99, "raw switch-time sanity samples should detect Wendigo")
expect(api.Detections.Oni == nil, "a raw Wendigo curve should clear Oni")
reset()
runtime:Dispatch("OnHuntTransitionSamples", {
	Snapshots = {{Sanity = 0, Speed = 13.75, Hunting = true}},
	MapFactor = 1,
})
expect(api.Detections.Wendigo == nil and api.RuleOuts.Wendigo == nil, "one low-sanity transition is too ambiguous to identify or rule out Wendigo")
runtime:Dispatch("OnHuntTransitionSamples", {
	Snapshots = {
		{Sanity = 60, Speed = 11, Hunting = true},
		{Sanity = 60, Speed = 11, Hunting = false},
		{Sanity = 60, Speed = 11, Hunting = true},
	},
	MapFactor = 1,
})
expect(api.Detections.Wendigo == nil and api.RuleOuts.Wendigo == nil, "equal-sanity transitions cannot establish a Wendigo curve")
runtime:Dispatch("OnHuntTransitionSamples", {
	Snapshots = {
		{Sanity = 50, Speed = 11.7, Hunting = true},
		{Sanity = 40, Speed = 12, Hunting = false},
		{Sanity = 30, Speed = 12.3, Hunting = true},
	},
	MapFactor = 1,
})
expect(api.RuleOuts.Wendigo.Confidence == 99, "individually plausible samples with the wrong speed delta should reject the Wendigo curve")

-- Wisp: Holy Oil wall pass/block outcomes oppose one another. A confirmed
-- off-favourite hunt is a high negative unless the decisive wall tell exists.
reset()
runtime:Dispatch("OnHolyOilWall", {Outcome = "Blocked", Reason = "wall stayed collidable"})
expect(api.RuleOuts.Wisp.Confidence == 99, "blocked Holy Oil should rule out Wisp")
runtime:Dispatch("OnHolyOilWall", {Outcome = "PassThrough", Reason = "wall became non-collidable"})
expect(api.RuleOuts.Wisp == nil and api.Detections.Wisp.Confidence == 99, "Holy Oil pass-through should detect Wisp")
runtime:Dispatch("OnOffFavouriteHunt", {
	Confirmed = true,
	CurrentRoom = "Storage Room",
	FavouriteRoom = "Classroom",
})
expect(api.RuleOuts.Wisp == nil, "the decisive Holy Oil tell should resist a weaker room negative")
api:ClearDetection("Wisp")
local refreshBeforeIgnoredRoom = api.RefreshCount
runtime:Dispatch("OnOffFavouriteHunt", {Confirmed = false})
expect(api.RefreshCount == refreshBeforeIgnoredRoom, "an unconfirmed room mismatch should be ignored")
runtime:Dispatch("OnOffFavouriteHunt", {
	Confirmed = true,
	CurrentRoom = "Storage Room",
	FavouriteRoom = "Classroom",
})
expect(api.RuleOuts.Wisp.Confidence == 95, "a confirmed off-favourite hunt should rule out Wisp")

-- Wraith: known salt contact without disturbance is positive; the same
-- contact producing disturbed salt is decisive negative evidence.
reset()
runtime:Dispatch("OnSaltContact", {Disturbed = false, Reason = "salt stayed intact"})
expect(api.Detections.Wraith.Confidence == 95, "undisturbed known salt contact should detect Wraith")
runtime:Dispatch("OnSaltContact", {Disturbed = true, Reason = "salt became disturbed"})
expect(api.Detections.Wraith == nil and api.RuleOuts.Wraith.Confidence == 99, "disturbed salt should rule out Wraith")

expect(#routedActions == 0, "direct observer policies should not emit unexpected routed actions")
local snapshot = runtime:Snapshot()
expect(type(snapshot.Observers.Dullahan) == "table", "Dullahan should expose private observer state")
expect(type(snapshot.Observers.Phantom) == "table", "Phantom should expose private observer state")
expect(type(snapshot.Observers.Oni) == "table", "Oni should expose private observer state")
expect(type(snapshot.Observers.Wendigo) == "table", "Wendigo should expose private observer state")
expect(runtime:Destroy() == true, "runtime should destroy once")
expect(runtime:Destroy() == false, "runtime destroy should be idempotent")

print("observers.spec: every active observer positive and negative policy assertion passed")
