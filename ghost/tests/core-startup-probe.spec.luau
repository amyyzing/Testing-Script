local Events = require("../events")
local Ledger = require("../evidence-ledger")
local Resolver = require("../resolver")
local Coordinator = require("../coordinator")({
	Events = Events,
	EvidenceLedger = Ledger,
	Resolver = Resolver,
})
local HuntState = require("../trackers/active/hunt-state")({Events = Events})
local SpeedProbe = require("../trackers/dormant/speed-probe")({Events = Events})

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local now = 0
local nextJobId = 0
local jobs = {}
local function schedule(delaySeconds, callback)
	nextJobId = nextJobId + 1
	local job = {
		Id = nextJobId,
		At = now + delaySeconds,
		Callback = callback,
		Cancelled = false,
	}
	table.insert(jobs, job)
	return function() job.Cancelled = true end
end

local function sortJobs()
	table.sort(jobs, function(left, right)
		if left.At ~= right.At then return left.At < right.At end
		return left.Id < right.Id
	end)
end

local function runNextJob()
	sortJobs()
	local job = table.remove(jobs, 1)
	expect(job ~= nil, "expected one scheduled job")
	now = math.max(now, job.At)
	if not job.Cancelled then job.Callback() end
end

local function runAllJobs()
	while #jobs > 0 do runNextJob() end
end

local function trackerSnapshot(coordinator, name)
	for _, snapshot in ipairs(coordinator:Snapshot().Trackers) do
		if snapshot.Name == name then return snapshot end
	end
	return nil
end

local function findEvent(coordinator, kind, predicate)
	for _, event in ipairs(coordinator:Snapshot().Events) do
		if event.Type == kind and (predicate == nil or predicate(event)) then
			return event
		end
	end
	return nil
end

local speedReadCount = 0
local function readWalkSpeed()
	speedReadCount = speedReadCount + 1
	if speedReadCount == 1 then return nil end
	if speedReadCount == 2 then return 0 end
	if speedReadCount <= 4 then return 11 end
	return 9
end

local huntState = HuntState.new({SettleDelay = 0.1})
local speedProbe = SpeedProbe.new({SettleDelay = 0.1, MinimumHuntAge = 0.5})
local coordinator = Coordinator.new({
	Clock = function() return now end,
	Schedule = schedule,
	Trackers = {huntState, speedProbe},
})
coordinator:Start({
	InitialHunting = true,
	Clock = function() return now end,
	Schedule = schedule,
	ReadWalkSpeed = readWalkSpeed,
	ReadAverageSanity = function() return 55 end,
	MapFactor = 1,
})

local history = coordinator:Snapshot().Events
expect(history[1] and history[1].Type == Events.Types.HuntStarted, "initial-active Start must dispatch HuntStarted only after every tracker has started")
local waiting = trackerSnapshot(coordinator, "SpeedProbe")
expect(waiting and waiting.Hunting == true and waiting.HuntId == 1, "SpeedProbe must receive the synthetic initial HuntStarted")
expect(waiting.Status == "WaitingForBaseline", "SpeedProbe should arm in baseline-waiting state before the settled read")

coordinator:Emit({
	Type = Events.Types.PlayerDeath,
	Time = 0.1,
	HuntId = 1,
	Hunting = true,
	Unique = true,
	Qualified = true,
	ValidMultiplayerKill = true,
	OtherAlive = 1,
	PlayerId = 7,
	HuntAge = 0.1,
	SettledSpeed = 12,
})
local afterEarlyDeath = trackerSnapshot(coordinator, "SpeedProbe")
expect(afterEarlyDeath.PendingDeathCount == 0 and afterEarlyDeath.QueuedProbeCount == 0, "death before MinimumHuntAge must not arm or queue a speed probe")

coordinator:Emit({
	Type = Events.Types.SaltContact,
	Time = 0.11,
	HuntId = 1,
	Hunting = true,
	SettledSpeed = 9,
	DirectContact = true,
	SaltDisturbed = true,
	ContactId = "startup-salt",
	DisturbedContactId = "startup-salt",
})
expect(trackerSnapshot(coordinator, "SpeedProbe").QueuedProbeCount == 1, "qualified event arriving before baseline must be retained")

runNextJob()
expect(speedReadCount == 1 and trackerSnapshot(coordinator, "SpeedProbe").QueuedProbeCount == 1, "first invalid settled read must retain the queued probe")
runNextJob()
expect(speedReadCount == 2 and trackerSnapshot(coordinator, "SpeedProbe").QueuedProbeCount == 1, "second invalid settled read must retry without dropping the queued probe")
runAllJobs()

expect(speedReadCount == 5,
	"baseline retry should require two stable valid reads, then the queued salt probe should take one fresh live read")
local armed = trackerSnapshot(coordinator, "SpeedProbe")
expect(armed.Status == "Armed" and armed.BaselineSpeed == 11 and armed.QueuedProbeCount == 0, "valid retry must arm SpeedProbe and flush its queue")
local saltResult = findEvent(coordinator, Events.Types.SpeedProbeResult, function(event)
	return event.Trigger == Events.Types.SaltContact
end)
expect(saltResult ~= nil, "queued salt event must produce a probe result after baseline recovery")
expect(saltResult.BaselineSpeed == 11 and saltResult.CurrentSpeed == 9 and saltResult.Delta == -2,
	"flushed probe must compare the recovered hunt baseline with a fresh delayed WalkSpeed read")
expect(saltResult.DirectContact == true and saltResult.SaltDisturbed == true, "flushed probe must retain event-time salt qualifiers")

expect(findEvent(coordinator, Events.Types.SpeedProbeResult, function(event)
	return event.Trigger == Events.Types.PlayerDeath
end) == nil, "early death must never produce a delayed speed result")
expect(findEvent(coordinator, Events.Types.HuntEndedAfterDeath) == nil, "early death must never arm Revenant correlation")
expect(findEvent(coordinator, Events.Types.HuntContinuedAfterDeath) == nil, "early death must never emit a continued-hunt outcome")

coordinator:Destroy()

print("core-startup-probe.spec: initial-active queueing, settled retry, queued probe flush, and early-death rejection passed")
