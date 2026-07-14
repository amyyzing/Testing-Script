local Events = require("../events")
local Ledger = require("../evidence-ledger")
local Resolver = require("../resolver")
local Coordinator = require("../coordinator")({Events = Events, EvidenceLedger = Ledger, Resolver = Resolver})
local HuntState = require("../trackers/active/hunt-state")({Events = Events})
local SpeedPairs = require("../trackers/dormant/speed-pairs")({Events = Events})
local SpeedProbe = require("../trackers/dormant/speed-probe")({Events = Events})
local SpeedPattern = require("../analyzers/speed-pattern")({Events = Events})
local SpeedMath = require("../analyzers/speed-math")({Events = Events})
local DullahanProfile = require("../Dullahan")
local WendigoProfile = require("../Wendigo")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local now = 0
local jobs = {}
local function schedule(delaySeconds, callback)
	local job = {At = now + delaySeconds, Callback = callback, Cancelled = false}
	table.insert(jobs, job)
	return function() job.Cancelled = true end
end
local function runJobs()
	table.sort(jobs, function(left, right) return left.At < right.At end)
	while #jobs > 0 do
		local job = table.remove(jobs, 1)
		now = math.max(now, job.At)
		if not job.Cancelled then job.Callback() end
		table.sort(jobs, function(left, right) return left.At < right.At end)
	end
end

local function findEvent(coordinator, kind, predicate)
	for _, event in ipairs(coordinator:Snapshot().Events) do
		if event.Type == kind and (predicate == nil or predicate(event)) then
			return event
		end
	end
	return nil
end

local pair = SpeedPairs.new()
local pattern = SpeedPattern.new()
local mathAnalyzer = SpeedMath.new()
local coordinator = Coordinator.new({
	Clock = function() return now end,
	Schedule = schedule,
	Trackers = {pair},
	Analyzers = {pattern, mathAnalyzer},
	Definitions = {DullahanProfile},
})
coordinator:Start({Clock = function() return now end, Schedule = schedule})

local function visibilityWindow(speeds, mapFactor, initialInvisible)
	initialInvisible = initialInvisible == true
	coordinator:Emit({
		Type = Events.Types.HuntStarted,
		HuntId = 1,
		Hunting = true,
		Payload = {
			Transparency = initialInvisible and 1 or 0,
			AverageSanity = 50,
			MapFactor = mapFactor,
		},
	})
	local invisible = not initialInvisible
	for _, speed in ipairs(speeds) do
		coordinator:Emit({
			Type = Events.Types.TransparencyChanged,
			HuntId = 1,
			Hunting = true,
			Payload = {Transparency = invisible and 1 or 0, SettledSpeed = speed},
		})
		runJobs()
		invisible = not invisible
	end
end

local phantomSpeeds = {}
for _ = 1, 7 do
	table.insert(phantomSpeeds, 13.5)
	table.insert(phantomSpeeds, 11)
end
visibilityWindow(phantomSpeeds, 1)
local phantom = findEvent(coordinator, Events.Types.PhantomPattern)
expect(phantom ~= nil, "seven repeated x/y visibility pairs should emit PhantomPattern")
expect(math.abs(phantom.Ratio - 13.5 / 11) < 0.001, "PhantomPattern should expose its settled ratio at top level")
expect(phantom.PairCount == 7, "PhantomPattern should preserve the complete seven-pair window")
expect(pair:Snapshot().WindowCount == 1, "fourteen transitions should create one seven-pair window, not a 0.1-second sample stream")
for _, invisible in ipairs({true, false, true, false}) do
	coordinator:Emit({
		Type = Events.Types.TransparencyChanged,
		HuntId = 1,
		Hunting = true,
		Payload = {Transparency = invisible and 1 or 0, SettledSpeed = invisible and 13.5 or 11},
	})
	runJobs()
end
expect(findEvent(coordinator, Events.Types.DullahanPattern) == nil, "repeated Phantom x/y cycles must not accumulate into a false Dullahan step pattern")
expect(coordinator:Resolve({"Dullahan"}).Dullahan.RuledOut == true, "a complete repeating Phantom window should rule Dullahan out immediately")

coordinator:Reset()
now = 0
table.clear(jobs)
local driftingPhantomSpeeds = {}
for _, scale in ipairs({1, 0.97, 1.03, 0.96, 1.04, 0.98, 1.02}) do
	-- Start visible in each BA-ordered cycle to verify that phase order does not
	-- matter. Absolute speeds drift, but each local B:A ratio stays Phantom.
	table.insert(driftingPhantomSpeeds, 11 * scale)
	table.insert(driftingPhantomSpeeds, 13.5 * scale)
end
visibilityWindow(driftingPhantomSpeeds, 1, true)
local pairedPhantom = findEvent(coordinator, Events.Types.PhantomPattern)
expect(pairedPhantom and pairedPhantom.MatchedPairCount == 7,
	"seven local blink/non-blink AB ratios should identify Phantom despite absolute drift")
expect(pairedPhantom.Pairs[1].FirstInvisible == false,
	"Phantom pair math must work when the visible state arrives first")
for _, pairRatio in ipairs(pairedPhantom.PairRatios) do
	expect(math.abs(pairRatio - 13.5 / 11) < 0.001,
		"each Phantom decision must preserve its local AB ratio")
end
expect(findEvent(coordinator, Events.Types.DullahanPattern) == nil,
	"pairwise Phantom ratios must take priority over unequal Dullahan pairs")

coordinator:Reset()
now = 0
table.clear(jobs)
visibilityWindow({
	22, 22.3,
	22.2, 22.4,
	22, 22.2,
	22.5, 22.7,
	22.1, 22.3,
	22.4, 22.6,
	22.2, 22.5,
}, 1)
local dullahan = findEvent(coordinator, Events.Types.DullahanPattern)
expect(dullahan and dullahan.DifferentPairCount == 7,
	"seven unequal pairs should emit DullahanPattern immediately")
expect(dullahan.PairCount == 7 and dullahan.SampleCount == 14, "Dullahan should resolve from exactly seven complete settled pairs")
expect(dullahan.Pairs[2].FirstSpeed < dullahan.Pairs[1].SecondSpeed,
	"the relationship between separate pairs must not affect Dullahan classification")

coordinator:Reset()
now = 0
table.clear(jobs)
visibilityWindow({
	22, 22.000001,
	24, 23.999999,
	20, 20.0000001,
	25, 24.9999999,
	19, 19.000002,
	23, 22.999998,
	21, 21.000003,
}, 1)
local anyDifferenceDullahan = findEvent(coordinator, Events.Types.DullahanPattern)
expect(anyDifferenceDullahan and anyDifferenceDullahan.DifferentPairCount == 7,
	"any exact difference in all seven pairs must identify Dullahan without a minimum size")
expect(anyDifferenceDullahan.Pairs[2].SecondSpeed
	< anyDifferenceDullahan.Pairs[2].FirstSpeed,
	"a within-pair decrease must count as a different Dullahan pair")

coordinator:Reset()
now = 0
table.clear(jobs)
visibilityWindow({
	22, 22.3,
	22.2, 22.4,
	22, 22.2,
	22.5, 22.7,
	22.1, 22.3,
	22.4, 22.6,
	22.2, 22.2,
}, 1)
expect(findEvent(coordinator, Events.Types.DullahanPattern) == nil,
	"six unequal pairs and one equal pair must not identify Dullahan")
expect(findEvent(coordinator, Events.Types.DullahanPatternAbsent) ~= nil,
	"a complete inconsistent seven-pair window should rule Dullahan out immediately")

coordinator:Reset()
now = 0
table.clear(jobs)
local oniSpeeds = {}
for _ = 1, 14 do table.insert(oniSpeeds, 28.35) end
visibilityWindow(oniSpeeds, 1.05)
local speedMath = findEvent(coordinator, Events.Types.HuntSpeedMathResult)
expect(speedMath and speedMath.Best == "Oni", "28.35 on a Medium map should normalize to Oni base 13.5 at 200%")
expect(speedMath.PairCount == 7, "flat speed math must be backed by all seven pairs")
for _, multiplier in ipairs(speedMath.ValidMultipliers) do
	 expect(multiplier ~= 1.75, "175% must never enter hunting speed math")
end
expect(coordinator:Resolve({"Dullahan"}).Dullahan.RuledOut == true, "qualified completed flat window should rule Dullahan out without waiting for HuntEnded")

coordinator:Reset()
now = 0
table.clear(jobs)
local ordinarySpeeds = {}
for _ = 1, 14 do table.insert(ordinarySpeeds, 11) end
visibilityWindow(ordinarySpeeds, 1)
local ordinaryMath = findEvent(coordinator, Events.Types.HuntSpeedMathResult)
expect(ordinaryMath and ordinaryMath.Best == "Normal",
	"seven flat base-speed pairs should classify the normal hunting-speed pattern")

coordinator:Reset()
now = 0
table.clear(jobs)
local incompleteSpeeds = {}
for _ = 1, 6 do
	table.insert(incompleteSpeeds, 22)
	table.insert(incompleteSpeeds, 22.3)
end
visibilityWindow(incompleteSpeeds, 1)
expect(findEvent(coordinator, Events.Types.DullahanPattern) == nil,
	"six pairs must not identify Dullahan")
expect(findEvent(coordinator, Events.Types.DullahanPatternAbsent) == nil,
	"six pairs must not rule Dullahan out")
coordinator:Emit({Type = Events.Types.HuntEnded, HuntId = 1, Hunting = false})
expect(findEvent(coordinator, Events.Types.DullahanPatternAbsent) == nil,
	"HuntEnded must not turn an incomplete six-pair window into a negative")

local wendigoMath = SpeedMath.new()
local wendigoCoordinator = Coordinator.new({
	Clock = function() return now end,
	Analyzers = {wendigoMath},
	Definitions = {WendigoProfile},
})
wendigoCoordinator:Start({Clock = function() return now end})

wendigoCoordinator:Emit({
	Type = Events.Types.FlatHuntSpeed,
	Hunting = true,
	Payload = {
		Speed = 11.65,
		AverageSanity = 47,
		MapFactor = 1,
		PairCount = 7,
		RequiredPairs = 7,
		Qualified = true,
		ValidMultipliers = {0.5, 0.75, 1, 1.25, 1.5, 2},
	},
})
local wendigoPairMath = findEvent(wendigoCoordinator, Events.Types.HuntSpeedMathResult)
expect(wendigoPairMath and wendigoPairMath.Best == "Wendigo",
	"seven flat pairs should expose a unique switch-time Wendigo speed fit")
expect(wendigoCoordinator:Resolve({"Wendigo"}).Wendigo.Status == "Supported",
	"a unique seven-pair Wendigo fit should select Wendigo")

wendigoCoordinator:Reset()
wendigoCoordinator:Emit({
	Type = Events.Types.FlatHuntSpeed,
	Hunting = true,
	Payload = {
		Speed = 11,
		AverageSanity = 47,
		MapFactor = 1,
		PairCount = 7,
		RequiredPairs = 7,
		Qualified = true,
		ValidMultipliers = {0.5, 0.75, 1, 1.25, 1.5, 2},
	},
})
expect(wendigoCoordinator:Resolve({"Wendigo"}).Wendigo.RuledOut == true,
	"a unique Normal fit that excludes the sanity curve should rule Wendigo out")

local function emitWendigoTransition(hunting, sanity, speed, time)
	wendigoCoordinator:Emit({
		Type = Events.Types.HuntTransitionSettled,
		Time = time,
		HuntId = hunting and 2 or 1,
		Hunting = hunting,
		Payload = {
			AverageSanity = sanity,
			Speed = speed,
			MapFactor = 1,
			ValidMultipliers = {0.5, 0.75, 1, 1.25, 1.5, 2},
		},
	})
end

wendigoCoordinator:Reset()
emitWendigoTransition(true, 60, 11, 1)
emitWendigoTransition(false, 59.5, 5, 2)
emitWendigoTransition(true, 59, 11.05, 3)
local lowSpreadReject = findEvent(wendigoCoordinator, Events.Types.WendigoCurveResult)
expect(lowSpreadReject and lowSpreadReject.Qualified == true
	and lowSpreadReject.Outcome == "Rejected",
	"a mathematically invalid curve must be a qualified negative despite low sanity spread")
expect(wendigoCoordinator:Resolve({"Wendigo"}).Wendigo.RuledOut == true,
	"the Wendigo observer must consume a low-spread mathematical rejection")

wendigoCoordinator:Reset()
emitWendigoTransition(true, 60, 11, 1)
emitWendigoTransition(false, 59, 11.05 * 1.75, 2)
emitWendigoTransition(true, 58, 11.1, 3)
local matchedCurve = findEvent(wendigoCoordinator, Events.Types.WendigoCurveResult)
expect(matchedCurve and matchedCurve.Qualified == true
	and matchedCurve.Outcome == "Matched",
	"a valid two-sanity-point transition curve should identify Wendigo")
expect(wendigoCoordinator:Resolve({"Wendigo"}).Wendigo.Status == "Supported",
	"the Wendigo observer must select a matched transition curve")

wendigoCoordinator:Reset()
emitWendigoTransition(true, 60, 11, 1)
emitWendigoTransition(false, 59.5, 11.025 * 1.75, 2)
emitWendigoTransition(true, 59, 11.05, 3)
local inconclusiveCurve = findEvent(wendigoCoordinator, Events.Types.WendigoCurveResult)
expect(inconclusiveCurve and inconclusiveCurve.Qualified == false
	and inconclusiveCurve.Outcome == "Inconclusive",
	"a curve fit with less than two sanity points of change must remain inconclusive")
expect(wendigoCoordinator:Resolve({"Wendigo"}).Wendigo.Status == "Unknown",
	"an inconclusive curve must neither select nor rule Wendigo out")

local probe = SpeedProbe.new()
local probeCoordinator = Coordinator.new({
	Clock = function() return now end,
	Schedule = schedule,
	Trackers = {probe},
})
probeCoordinator:Start({Clock = function() return now end, Schedule = schedule})
probeCoordinator:Emit({Type = Events.Types.HuntStarted, HuntId = 2, Hunting = true, Time = now})
probeCoordinator:Emit({
	Type = Events.Types.HuntTransitionSettled,
	HuntId = 2,
	Hunting = true,
	Payload = {BaselineSpeed = 11, Speed = 11},
})
probeCoordinator:Emit({
	Type = Events.Types.SaltContact,
	Id = "salt-1",
	HuntId = 2,
	Hunting = true,
	Payload = {
		SettledSpeed = 9,
		DirectContact = true,
		SaltDisturbed = true,
		ContactId = "contact-1",
		DisturbedContactId = "contact-1",
	},
})
runJobs()
local saltProbe = findEvent(probeCoordinator, Events.Types.SpeedProbeResult)
expect(saltProbe and saltProbe.DirectContact and saltProbe.SaltDisturbed, "salt probe must preserve strict direct-contact qualifiers")
expect(saltProbe.Delta == -2, "event-time speed should compare against the settled hunt-start baseline")

probeCoordinator:Emit({
	Type = Events.Types.WalkSpeedChanged,
	HuntId = 2,
	Hunting = true,
	Payload = {SettledSpeed = 11},
})
expect(findEvent(probeCoordinator, Events.Types.SpeedProbeRecovery) ~= nil, "event-driven return to baseline should emit one salt recovery")

probeCoordinator:Reset()
table.clear(jobs)
now = 5
probeCoordinator:Emit({Type = Events.Types.HuntStarted, HuntId = 4, Hunting = true, Time = now})
probeCoordinator:Emit({
	Type = Events.Types.HuntTransitionSettled,
	HuntId = 4,
	Hunting = true,
	Payload = {BaselineSpeed = 11},
})
probeCoordinator:Emit({
	Type = Events.Types.SaltContact,
	Id = "salt-hunt-edge-touch",
	HuntId = 4,
	Hunting = true,
	Time = now + 0.01,
	Payload = {
		CurrentSpeed = 11,
		HuntingAtContact = true,
		DirectContact = true,
		SaltDisturbed = false,
		ContactId = "edge-contact",
	},
})
probeCoordinator:Emit({
	Type = Events.Types.HuntEnded,
	HuntId = 4,
	Hunting = false,
	Time = now + 0.02,
	Payload = {CurrentSpeed = 11},
})
probeCoordinator:Emit({
	Type = Events.Types.SaltContact,
	Id = "salt-hunt-edge-disturbed",
	HuntId = 4,
	Hunting = false,
	Time = now + 0.03,
	Payload = {
		CurrentSpeed = 11,
		HuntingAtContact = true,
		DirectContact = true,
		SaltDisturbed = true,
		ContactId = "edge-contact",
		DisturbedContactId = "edge-contact",
	},
})
probeCoordinator:Emit({
	Type = Events.Types.WalkSpeedChanged,
	HuntId = 4,
	Hunting = false,
	Time = now + 0.08,
	Payload = {CurrentSpeed = 8},
})
local postHuntSaltProbe = findEvent(
	probeCoordinator,
	Events.Types.SpeedProbeResult,
	function(event)
		return event.HuntEndedBeforeSample == true
	end
)
expect(postHuntSaltProbe and postHuntSaltProbe.Delta == -3,
	"salt contact during a hunt must retain a brief probe when the slowdown arrives just after HuntEnded")
expect(postHuntSaltProbe.Hunting == false and postHuntSaltProbe.HuntingAtContact == true,
	"post-hunt Aswang sampling must preserve contact-time hunting without misreporting the sample state")
probeCoordinator:Emit({
	Type = Events.Types.WalkSpeedChanged,
	HuntId = 4,
	Hunting = false,
	Time = now + 0.25,
	Payload = {CurrentSpeed = 11},
})
expect(findEvent(probeCoordinator, Events.Types.SpeedProbeRecovery, function(event)
	return event.HuntEndedBeforeSample == true
end) ~= nil, "a post-hunt Aswang slowdown should still confirm its temporary recovery")

probeCoordinator:Reset()
table.clear(jobs)
now = 10
probeCoordinator:Emit({Type = Events.Types.HuntStarted, HuntId = 3, Hunting = true, Time = now})
probeCoordinator:Emit({Type = Events.Types.HuntTransitionSettled, HuntId = 3, Hunting = true, Payload = {BaselineSpeed = 11}})
probeCoordinator:Emit({
	Type = Events.Types.PlayerDeath,
	Id = "death-1",
	HuntId = 3,
	Hunting = true,
	Time = now + 1,
	Payload = {
		HuntAge = 1,
		OtherAlive = 1,
		PlayerId = 7,
		Unique = true,
		Qualified = true,
		ValidMultiplayerKill = true,
		SettledSpeed = 12,
	},
})
now = now + 2
probeCoordinator:Emit({Type = Events.Types.HuntEnded, HuntId = 3, Hunting = false, Time = 12.4})
local revenant = findEvent(probeCoordinator, Events.Types.HuntEndedAfterDeath)
expect(revenant and revenant.ValidMultiplayerKill == true, "qualified multiplayer death ending the hunt inside 1.5 seconds should reach Revenant")
expect(revenant.Elapsed <= 1.5, "Revenant correlation must use the 1.5-second boundary")

local transitionEvents = {}
local transitionSpeed = 11
local transitionSanity = 60
local huntTracker = HuntState.new()
huntTracker:Start({
	InitialHunting = true,
	Clock = function() return now end,
	Schedule = schedule,
	ReadAverageSanity = function() return transitionSanity end,
	ReadWalkSpeed = function() return transitionSpeed end,
	MapFactor = 1.05,
	Emit = function(event) table.insert(transitionEvents, event) end,
})
expect(transitionEvents[1].Type == Events.Types.HuntStarted, "starting during an active hunt should synthesize HuntStarted")
expect(transitionEvents[1].Payload.AverageSanity == 60, "hunt transition must capture sanity immediately")
transitionSanity = 40
transitionSpeed = 12
runJobs()
expect(transitionEvents[2].Type == Events.Types.HuntTransitionSettled, "active-hunt startup should emit one settled transition")
expect(transitionEvents[2].Payload.AverageSanity == 60 and transitionEvents[2].Payload.Speed == 12, "settled transition must preserve switch-time sanity while delaying only speed")
expect(transitionEvents[2].Payload.MapFactor == 1.05, "transition should inherit map factor from runtime context")

print("core-speed.spec: pair patterns, map math, strict event probes, and recovery passed")
