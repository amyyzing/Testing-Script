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

local function findEvent(coordinator, kind)
	for _, event in ipairs(coordinator:Snapshot().Events) do
		if event.Type == kind then return event end
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

local function visibilityCycle(speeds, mapFactor)
	coordinator:Emit({
		Type = Events.Types.HuntStarted,
		HuntId = 1,
		Hunting = true,
		Payload = {Transparency = 0, AverageSanity = 50, MapFactor = mapFactor},
	})
	for index, invisible in ipairs({true, false, true, false}) do
		coordinator:Emit({
			Type = Events.Types.TransparencyChanged,
			HuntId = 1,
			Hunting = true,
			Payload = {Transparency = invisible and 1 or 0, SettledSpeed = speeds[index]},
		})
		runJobs()
	end
end

visibilityCycle({13.5, 11, 13.5, 11}, 1)
local phantom = findEvent(coordinator, Events.Types.PhantomPattern)
expect(phantom ~= nil, "two repeated x/y visibility pairs should emit PhantomPattern")
expect(math.abs(phantom.Ratio - 13.5 / 11) < 0.001, "PhantomPattern should expose its settled ratio at top level")
expect(pair:Snapshot().WindowCount == 1, "four transitions should create one pair window, not a 0.1-second sample stream")
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

coordinator:Reset()
now = 0
table.clear(jobs)
visibilityCycle({11, 11.1, 11.2, 11.3}, 1)
local dullahan = findEvent(coordinator, Events.Types.DullahanPattern)
expect(dullahan and dullahan.IncreaseCount == 3, "a/b/c/d settled steps should emit DullahanPattern quickly")

coordinator:Reset()
now = 0
table.clear(jobs)
visibilityCycle({28.35, 28.35, 28.35, 28.35}, 1.05)
local speedMath = findEvent(coordinator, Events.Types.HuntSpeedMathResult)
expect(speedMath and speedMath.Best == "Oni", "28.35 on a Medium map should normalize to Oni base 13.5 at 200%")
for _, multiplier in ipairs(speedMath.ValidMultipliers) do
	 expect(multiplier ~= 1.75, "175% must never enter hunting speed math")
end
coordinator:Emit({Type = Events.Types.HuntEnded, HuntId = 1, Hunting = false})
expect(coordinator:Resolve({"Dullahan"}).Dullahan.RuledOut == true, "qualified completed flat hunt should reach the Dullahan observer as an explicit negative")

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
