local Events = require("../events")
local Ledger = require("../evidence-ledger")
local Resolver = require("../resolver")
local Coordinator = require("../coordinator")({Events = Events, EvidenceLedger = Ledger, Resolver = Resolver})
local HuntState = require("../trackers/active/hunt-state")({Events = Events})
local SpeedPairs = require("../trackers/dormant/speed-pairs")({Events = Events})
local SpeedProbe = require("../trackers/dormant/speed-probe")({Events = Events})
local SpeedPattern = require("../analyzers/speed-pattern")({Events = Events})
local SpeedMath = require("../analyzers/speed-math")({Events = Events})
local AswangProfile = require("../Aswang")
local DullahanProfile = require("../Dullahan")
local OniProfile = require("../Oni")
local PhantomProfile = require("../Phantom")
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
	Definitions = {DullahanProfile, PhantomProfile},
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
expect(coordinator:Resolve({"Phantom"}).Phantom.Confidence == 99,
	"an absolute-base-valid repeated A/B window should identify Phantom")
coordinator:Emit({
	Type = Events.Types.NonPhantomPattern,
	HuntId = 1,
	Hunting = true,
	Qualified = true,
	Completed = true,
	PairCount = 7,
	RequiredPairs = 7,
	Outcome = "NoisyContradiction",
})
expect(coordinator:Resolve({"Phantom"}).Phantom.Confidence == 99
	and coordinator:Resolve({"Phantom"}).Phantom.RuledOut == false,
	"one later contradictory seven-pair window must not erase a confirmed unique Phantom match")

coordinator:Reset()
now = 0
table.clear(jobs)
local ratioOnlySpeeds = {}
for _ = 1, 7 do
	table.insert(ratioOnlySpeeds, 13.5 * 1.1)
	table.insert(ratioOnlySpeeds, 11 * 1.1)
end
visibilityWindow(ratioOnlySpeeds, 1)
expect(findEvent(coordinator, Events.Types.PhantomPattern) == nil,
	"a correct Phantom ratio at unsupported absolute bases must not identify Phantom")
local ratioOnlyResult = findEvent(coordinator, Events.Types.NonPhantomPattern)
expect(ratioOnlyResult and ratioOnlyResult.Outcome == "StableInvalidAB",
	"an absolute-base-invalid stable A/B window should emit one clean non-Phantom result")
expect(coordinator:Resolve({"Phantom"}).Phantom.RuledOut == true,
	"the invalid absolute-base window must rule Phantom out")
expect(coordinator:Resolve({"Dullahan"}).Dullahan.Status == "Unknown",
	"a stable invalid A/B window with no upward tracked interval is inconclusive for Dullahan")

coordinator:Reset()
now = 0
table.clear(jobs)
local invalidRisingAB = {}
for _ = 1, 7 do
	table.insert(invalidRisingAB, 10)
	table.insert(invalidRisingAB, 12)
end
visibilityWindow(invalidRisingAB, 1)
local invalidRiseResult = findEvent(coordinator, Events.Types.NonPhantomPattern)
local invalidRiseDullahan = findEvent(coordinator, Events.Types.DullahanPattern)
expect(invalidRiseResult and invalidRiseResult.Outcome == "StableInvalidAB",
	"an invalid stable A/B rise must still produce the clean Phantom negative")
expect(invalidRiseDullahan and invalidRiseDullahan.UpwardStepCount == 7,
	"an invalid stable A/B window must not bypass its seven nonzero Dullahan rises")
expect(coordinator:Resolve({"Dullahan"}).Dullahan.Confidence == 99,
	"after Phantom is excluded, the stable invalid A/B rise should identify Dullahan")

coordinator:Reset()
now = 0
table.clear(jobs)
local mappedDifficultySpeeds = {}
for _ = 1, 7 do
	table.insert(mappedDifficultySpeeds, 13.5 * 1.5 * 1.05)
	table.insert(mappedDifficultySpeeds, 11 * 1.5 * 1.05)
end
visibilityWindow(mappedDifficultySpeeds, 1.05)
local mappedPhantom = findEvent(coordinator, Events.Types.PhantomPattern)
expect(mappedPhantom and mappedPhantom.Multiplier == 1.5
	and mappedPhantom.MapFactor == 1.05,
	"both Phantom bases must fit one common multiplier after map normalization")

coordinator:Reset()
now = 0
table.clear(jobs)
visibilityWindow({
	22, 21,
	21.9, 20.9,
	21.8, 20.8,
	21.7, 20.7,
	21.6, 20.6,
	21.5, 20.5,
	21.4, 20.4,
}, 1)
local decreaseOnly = findEvent(coordinator, Events.Types.NonPhantomPattern)
expect(decreaseOnly and decreaseOnly.Outcome == "DecreaseOnly"
	and decreaseOnly.UpwardStepCount == 0,
	"a complete decrease-only sequence should be classified without manufacturing a rise")
expect(findEvent(coordinator, Events.Types.DullahanPattern) == nil
	and findEvent(coordinator, Events.Types.DullahanPatternAbsent) == nil,
	"decrease-only speed changes must neither support nor rule out Dullahan")
expect(coordinator:Resolve({"Dullahan"}).Dullahan.Status == "Unknown"
	and coordinator:Resolve({"Phantom"}).Phantom.RuledOut == true,
	"decrease-only is inconclusive for Dullahan but rules Phantom out")

coordinator:Reset()
now = 0
table.clear(jobs)
visibilityWindow({
	22, 22.000000001,
	21.9, 21.8,
	21.7, 21.6,
	21.5, 21.4,
	21.3, 21.2,
	21.1, 21,
	20.9, 20.8,
}, 1)
local tinyRise = findEvent(coordinator, Events.Types.DullahanPattern)
expect(tinyRise and tinyRise.UpwardStepCount > 0,
	"an arbitrarily small but nonzero upward step must support Dullahan")

coordinator:Reset()
now = 0
table.clear(jobs)
visibilityWindow({
	11, 11,
	11.000000001, 11.000000001,
	10.9, 10.9,
	10.8, 10.8,
	10.7, 10.7,
	10.6, 10.6,
	10.5, 10.5,
}, 1)
local pairDriftRise = findEvent(coordinator, Events.Types.DullahanPattern)
expect(pairDriftRise and pairDriftRise.WithinPairDifferenceCount == 0
	and pairDriftRise.PairDriftCount > 0 and pairDriftRise.UpwardStepCount > 0,
	"a nonzero rise between corresponding phases of adjacent pairs must support Dullahan")

coordinator:Reset()
now = 0
table.clear(jobs)
local driftingPhaseSpeeds = {}
for _, scale in ipairs({1, 0.97, 1.03, 0.96, 1.04, 0.98, 1.02}) do
	-- Each local ratio resembles Phantom, but A/B itself drifts between pairs.
	-- The complete pattern is therefore Dullahan, not Phantom.
	table.insert(driftingPhaseSpeeds, 11 * scale)
	table.insert(driftingPhaseSpeeds, 13.5 * scale)
end
visibilityWindow(driftingPhaseSpeeds, 1, true)
expect(findEvent(coordinator, Events.Types.PhantomPattern) == nil,
	"Phantom requires the same repeated A/B values across all seven pairs")
local driftingDullahan = findEvent(coordinator, Events.Types.DullahanPattern)
expect(driftingDullahan and driftingDullahan.PairDriftCount > 0,
	"pair-to-pair A/B drift must classify as Dullahan after Phantom is excluded")

coordinator:Reset()
now = 0
table.clear(jobs)
visibilityWindow({
	11, 11,
	12, 12,
	10, 10,
	13, 13,
	9, 9,
	14, 14,
	8, 8,
}, 1)
local equalPairDrift = findEvent(coordinator, Events.Types.DullahanPattern)
expect(equalPairDrift and equalPairDrift.WithinPairDifferenceCount == 0
	and equalPairDrift.PairDriftCount > 0,
	"equal values inside each pair still identify Dullahan when the repeated A/A value drifts between pairs")

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
expect(anyDifferenceDullahan and anyDifferenceDullahan.DifferentPairCount == 7
	and anyDifferenceDullahan.UpwardStepCount > 0,
	"any nonzero upward step must identify Dullahan without a minimum size")
expect(anyDifferenceDullahan.Pairs[2].SecondSpeed
	< anyDifferenceDullahan.Pairs[2].FirstSpeed,
	"a within-pair decrease may coexist with a rise but must be ignored as support")

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
local partialDifferenceDullahan = findEvent(coordinator, Events.Types.DullahanPattern)
expect(partialDifferenceDullahan ~= nil
	and partialDifferenceDullahan.DifferentPairCount == 6,
	"after Phantom is excluded, any nonzero upward step in the complete seven-pair window identifies Dullahan")
expect(findEvent(coordinator, Events.Types.DullahanPatternAbsent) == nil,
	"only seven zero-difference pairs or a Phantom match may rule Dullahan out")

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

do
	local oniRoute = Coordinator.new({
		Analyzers = {SpeedMath.new()},
		Definitions = {OniProfile},
	})
	oniRoute:Start({})
	oniRoute:Emit({
		Type = Events.Types.FlatHuntSpeed,
		Hunting = true,
		Payload = {
			Speed = 13.5,
			MapFactor = 1,
			PairCount = 7,
			RequiredPairs = 7,
			Qualified = true,
			ValidMultipliers = {1},
		},
	})
	local routed = findEvent(oniRoute, Events.Types.HuntSpeedMathResult)
	local oni = oniRoute:Resolve({"Oni"}).Oni
	expect(routed and routed.Completed == true
		and oni.Status == "Supported" and oni.Confidence == 99,
		"SpeedMath must mark its seven-pair result completed so Oni consumes the analyzer route")
	oniRoute:Destroy()
end

do
	local phaseRoute = Coordinator.new({
		Analyzers = {SpeedMath.new()},
		Definitions = {OniProfile, PhantomProfile},
	})
	phaseRoute:Start({})
	phaseRoute:Emit({
		Type = Events.Types.HuntTransitionSettled,
		HuntId = 1,
		Hunting = false,
		Payload = {Speed = 11 * 1.05 * 1.75, MapSize = "Medium"},
	})
	local matchedNonHunt = findEvent(
		phaseRoute,
		Events.Types.NonHuntSpeedMathResult
	)
	expect(matchedNonHunt and matchedNonHunt.Matched == true,
		"a settled Medium-map non-hunt transition must normalize to base 11")
	expect(phaseRoute:Resolve({"Oni"}).Oni.RuledOut == false
		and phaseRoute:Resolve({"Phantom"}).Phantom.RuledOut == false,
		"the shared base-11 non-hunt state validates but cannot identify Oni or Phantom")
	phaseRoute:Emit({
		Type = Events.Types.HuntTransitionSettled,
		HuntId = 2,
		Hunting = false,
		Payload = {Speed = 25, MapSize = "Small"},
	})
	expect(phaseRoute:Resolve({"Oni"}).Oni.RuledOut == true
		and phaseRoute:Resolve({"Phantom"}).Phantom.RuledOut == true,
		"a qualified non-hunt transition outside base 11 must reject both speed profiles")
	phaseRoute:Destroy()
end

do
	local oniCoordinator = Coordinator.new({Definitions = {OniProfile}})
	oniCoordinator:Start({})
	oniCoordinator:Emit({
		Type = Events.Types.HuntSpeedMathResult,
		Hunting = true,
		Qualified = true,
		Completed = true,
		PairCount = 7,
		RequiredPairs = 7,
		Best = "Normal",
		BaseSpeed = 13.75,
		Fits = {
			Normal = {Base = 11, Matched = true},
			Oni = {Base = 13.5, Matched = true},
		},
	})
	local ambiguousOni = oniCoordinator:Resolve({"Oni"}).Oni
	expect(
		ambiguousOni.Status == "Supported" and ambiguousOni.Confidence == 99,
		"the independent Fits.Oni result must decide Oni even when global Best is Normal"
	)
	oniCoordinator:Destroy()
end

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
expect(wendigoPairMath and wendigoPairMath.Best ~= "Wendigo",
	"flat blink-pair math must classify only Normal/Oni and never synthesize a Wendigo fit")
expect(wendigoCoordinator:Resolve({"Wendigo"}).Wendigo.Status == "Unknown",
	"Wendigo must ignore flat blink-pair math")

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
expect(wendigoCoordinator:Resolve({"Wendigo"}).Wendigo.Status == "Unknown",
	"a Normal flat fit must not rule Wendigo out before transition-time sanity math")

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
local narrowMatchedCurve = findEvent(
	wendigoCoordinator,
	Events.Types.WendigoCurveResult
)
expect(narrowMatchedCurve and narrowMatchedCurve.Qualified == true
	and narrowMatchedCurve.Outcome == "Matched"
	and narrowMatchedCurve.RequiredTransitions == 2,
	"two exact switch-time fits with enough mathematically visible sanity change must identify Wendigo")
expect(wendigoCoordinator:Resolve({"Wendigo"}).Wendigo.Status == "Supported",
	"a genuine Wendigo must not wait for an undocumented third transition")

local probe = SpeedProbe.new()
local probeCoordinator = Coordinator.new({
	Clock = function() return now end,
	Schedule = schedule,
	Trackers = {probe},
	Definitions = {AswangProfile},
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
	Payload = {BaselineSpeed = 22},
})
probeCoordinator:Emit({
	Type = Events.Types.SaltContact,
	Id = "salt-ordinary-hunt-reset",
	HuntId = 4,
	Hunting = true,
	Time = now + 0.01,
	Payload = {
		CurrentSpeed = 22,
		HuntingAtContact = true,
		DirectContact = true,
		SaltDisturbed = true,
		ContactId = "ordinary-reset-contact",
		DisturbedContactId = "ordinary-reset-contact",
	},
})
probeCoordinator:Emit({
	Type = Events.Types.HuntEnded,
	HuntId = 4,
	Hunting = false,
	Time = now + 0.02,
	-- A trusted explicit settled speed is supported as a test/producer
	-- fallback when HuntTransitionSettled is unavailable.
	Payload = {SettledSpeed = 11},
})
probeCoordinator:Emit({
	Type = Events.Types.WalkSpeedChanged,
	HuntId = 4,
	Hunting = false,
	Time = now + 0.08,
	Payload = {CurrentSpeed = 11},
})
expect(findEvent(probeCoordinator, Events.Types.SpeedProbeResult) == nil
	and findEvent(probeCoordinator, Events.Types.SpeedProbeRecovery) == nil,
	"an ordinary high hunting speed to lower non-hunting reset must produce no Aswang evidence")
expect(probeCoordinator:Resolve({"Aswang"}).Aswang.Status == "Unknown",
	"an ordinary hunt-state reset must leave Aswang unresolved")

probeCoordinator:Reset()
table.clear(jobs)
now = 7
probeCoordinator:Emit({Type = Events.Types.HuntStarted, HuntId = 5, Hunting = true, Time = now})
probeCoordinator:Emit({
	Type = Events.Types.HuntTransitionSettled,
	HuntId = 5,
	Hunting = true,
	Payload = {BaselineSpeed = 22},
})
probeCoordinator:Emit({
	Type = Events.Types.SaltContact,
	Id = "salt-hunt-edge-touch",
	HuntId = 5,
	Hunting = true,
	Time = now + 0.01,
	Payload = {
		CurrentSpeed = 22,
		HuntingAtContact = true,
		DirectContact = true,
		SaltDisturbed = false,
		ContactId = "edge-contact",
	},
})
probeCoordinator:Emit({
	Type = Events.Types.HuntEnded,
	HuntId = 5,
	Hunting = false,
	Time = now + 0.02,
})
probeCoordinator:Emit({
	Type = Events.Types.HuntTransitionSettled,
	HuntId = 5,
	Hunting = false,
	Time = now + 0.025,
	Payload = {Speed = 11},
})
probeCoordinator:Emit({
	Type = Events.Types.SaltContact,
	Id = "salt-hunt-edge-disturbed",
	HuntId = 5,
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
	HuntId = 5,
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
	HuntId = 5,
	Hunting = false,
	Time = now + 0.25,
	Payload = {CurrentSpeed = 11},
})
expect(findEvent(probeCoordinator, Events.Types.SpeedProbeRecovery, function(event)
	return event.HuntEndedBeforeSample == true
end) ~= nil, "a post-hunt Aswang slowdown should still confirm its temporary recovery")
expect(probeCoordinator:Resolve({"Aswang"}).Aswang.Confidence == 99,
	"a further settled post-hunt drop and recovery must identify Aswang at 99%")

probeCoordinator:Reset()
table.clear(jobs)
now = 9
probeCoordinator:Emit({Type = Events.Types.HuntStarted, HuntId = 6, Hunting = true, Time = now})
probeCoordinator:Emit({
	Type = Events.Types.HuntTransitionSettled,
	HuntId = 6,
	Hunting = true,
	Payload = {BaselineSpeed = 22},
})
probeCoordinator:Emit({
	Type = Events.Types.SaltContact,
	Id = "salt-slow-at-hunt-end",
	HuntId = 6,
	Hunting = true,
	Time = now + 0.01,
	Payload = {
		CurrentSpeed = 22,
		HuntingAtContact = true,
		DirectContact = true,
		SaltDisturbed = true,
		ContactId = "end-speed-contact",
		DisturbedContactId = "end-speed-contact",
	},
})
probeCoordinator:Emit({
	Type = Events.Types.HuntEnded,
	HuntId = 6,
	Hunting = false,
	Time = now + 0.02,
})
probeCoordinator:Emit({
	Type = Events.Types.HuntTransitionSettled,
	HuntId = 6,
	Hunting = false,
	Time = now + 0.03,
	Payload = {Speed = 8},
})
local slowedAtHuntEnd = findEvent(probeCoordinator, Events.Types.SpeedProbeResult, function(event)
	return event.TriggerEventId == "salt-slow-at-hunt-end"
		and event.HuntEndedBeforeSample == true
end)
expect(
	slowedAtHuntEnd == nil,
	"a first settled post-hunt speed must not create provisional Aswang support from the hunt-state reset"
)
probeCoordinator:Emit({
	Type = Events.Types.WalkSpeedChanged,
	HuntId = 6,
	Hunting = false,
	Time = now + 0.1,
	Payload = {CurrentSpeed = 8.2},
})
expect(findEvent(probeCoordinator, Events.Types.SpeedProbeRecovery, function(event)
	return event.TriggerEventId == "salt-slow-at-hunt-end"
end) == nil, "a small rise from a slowed HuntEnded speed must not consume the pending recovery")
probeCoordinator:Emit({
	Type = Events.Types.WalkSpeedChanged,
	HuntId = 6,
	Hunting = false,
	Time = now + 0.2,
	Payload = {CurrentSpeed = 11},
})
expect(findEvent(probeCoordinator, Events.Types.SpeedProbeRecovery, function(event)
	return event.TriggerEventId == "salt-slow-at-hunt-end"
end) ~= nil, "a slowdown already present at HuntEnded must remain eligible for recovery confirmation")
expect(probeCoordinator:Resolve({"Aswang"}).Aswang.Confidence == 99,
	"an already-slow first settled post-hunt speed followed by recovery must identify Aswang at 99%")

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

-- Kill-trigger speed changes are permanent-pattern probes, not one delayed
-- read. Drift resets the streak; only three matching settled reads complete it.
probeCoordinator:Reset()
table.clear(jobs)
now = 20
probeCoordinator:Emit({Type = Events.Types.HuntStarted, HuntId = 6, Hunting = true, Time = now})
probeCoordinator:Emit({
	Type = Events.Types.HuntTransitionSettled,
	HuntId = 6,
	Hunting = true,
	Time = now + 0.1,
	Payload = {BaselineSpeed = 11},
})
now = 20.6
probeCoordinator:Emit({
	Type = Events.Types.PlayerDeath,
	Id = "stable-death",
	HuntId = 6,
	Hunting = true,
	Time = now,
	Payload = {
		HuntAge = 0.6,
		OtherAlive = 1,
		PlayerId = 8,
		Unique = true,
		Qualified = true,
		ValidMultiplayerKill = true,
	},
})
local function deathSpeedTick(time, speed)
	now = time
	probeCoordinator:Emit({
		Type = Events.Types.Tick,
		HuntId = 6,
		Hunting = true,
		Time = time,
		Payload = {CurrentSpeed = speed},
	})
end
deathSpeedTick(20.95, 12)
deathSpeedTick(21.15, 12.2)
deathSpeedTick(21.35, 12)
deathSpeedTick(21.55, 12)
expect(findEvent(probeCoordinator, Events.Types.SpeedProbeResult) == nil,
	"two matching reads after drift must remain provisional")
deathSpeedTick(21.75, 12)
local stableDeathProbe = findEvent(probeCoordinator, Events.Types.SpeedProbeResult)
expect(stableDeathProbe and stableDeathProbe.StableReadCount == 3
	and stableDeathProbe.Delta == 1,
	"three matching post-death reads must emit one stable completed speed probe")

probeCoordinator:Reset()
table.clear(jobs)
now = 30
probeCoordinator:Emit({Type = Events.Types.HuntStarted, HuntId = 7, Hunting = true, Time = now})
probeCoordinator:Emit({
	Type = Events.Types.HuntTransitionSettled,
	HuntId = 7,
	Hunting = true,
	Time = now + 0.1,
	Payload = {BaselineSpeed = 11},
})
now = 30.6
probeCoordinator:Emit({
	Type = Events.Types.PlayerDeath,
	Id = "drifting-death",
	HuntId = 7,
	Hunting = true,
	Time = now,
	Payload = {
		HuntAge = 0.6,
		OtherAlive = 1,
		PlayerId = 9,
		Unique = true,
		Qualified = true,
		ValidMultiplayerKill = true,
	},
})
for index, speed in ipairs({12, 12.2, 11.9, 12.1, 11.8}) do
	now = 30.75 + index * 0.2
	probeCoordinator:Emit({
		Type = Events.Types.Tick,
		HuntId = 7,
		Hunting = true,
		Time = now,
		Payload = {CurrentSpeed = speed},
	})
end
now = 32.01
probeCoordinator:Emit({
	Type = Events.Types.Tick,
	HuntId = 7,
	Hunting = true,
	Time = now,
	Payload = {CurrentSpeed = 12},
})
expect(findEvent(probeCoordinator, Events.Types.SpeedProbeResult) == nil,
	"a continuously drifting post-death speed must expire inconclusively")

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

-- A paired WalkSpeed signal must settle its matching blink phase immediately.
-- This protects short phases that end before the conservative delayed read.
table.clear(jobs)
local quickPair = SpeedPairs.new()
local quickPattern = SpeedPattern.new()
local quickCoordinator = Coordinator.new({
	Clock = function() return now end,
	Schedule = schedule,
	Trackers = {quickPair},
	Analyzers = {quickPattern},
	Definitions = {PhantomProfile},
})
quickCoordinator:Start({Clock = function() return now end, Schedule = schedule})
quickCoordinator:Emit({
	Type = Events.Types.HuntStarted,
	HuntId = 99,
	Hunting = true,
	Payload = {Transparency = 0, MapFactor = 1},
})
local quickInvisible = true
for _ = 1, 14 do
	quickCoordinator:Emit({
		Type = Events.Types.TransparencyChanged,
		HuntId = 99,
		Hunting = true,
		Payload = {Transparency = quickInvisible and 1 or 0},
	})
	quickCoordinator:Emit({
		Type = Events.Types.WalkSpeedChanged,
		HuntId = 99,
		Hunting = true,
		Payload = {CurrentSpeed = quickInvisible and 13.5 or 11},
	})
	quickInvisible = not quickInvisible
end
expect(findEvent(quickCoordinator, Events.Types.PhantomPattern) ~= nil,
	"fourteen quick transparency/speed edges should resolve without waiting for delayed jobs")
expect(quickPair:Snapshot().WindowCount == 1,
	"the immediate phase path should still emit exactly one seven-pair window")

print("core-speed.spec: pair patterns, map math, strict event probes, and recovery passed")
