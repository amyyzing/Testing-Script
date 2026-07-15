local Events = require("../events")
local Ledger = require("../evidence-ledger")
local Resolver = require("../resolver")
local Coordinator = require("../coordinator")({
	Events = Events,
	EvidenceLedger = Ledger,
	Resolver = Resolver,
})

local profiles = {
	Phantom = require("../Phantom"),
	Dullahan = require("../Dullahan"),
	Oni = require("../Oni"),
	Wendigo = require("../Wendigo"),
	Wraith = require("../Wraith"),
}

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function scoredEntries(coordinator, ghost)
	local result = {}
	for _, entry in ipairs(coordinator:Ledger():Entries()) do
		if entry.Ghost == ghost and entry.Polarity ~= "Observation" then
			table.insert(result, entry)
		end
	end
	return result
end

local scenarios = {
	{
		Name = "Phantom",
		Reject = {
			Type = Events.Types.FlatHuntSpeed,
			Hunting = true,
			Qualified = true,
			Completed = true,
			PairCount = 7,
			RequiredPairs = 7,
			Outcome = "Equal",
		},
		Match = {
			Type = Events.Types.PhantomPattern,
			Hunting = true,
			Qualified = true,
			PairCount = 7,
			RequiredPairs = 7,
			VisibleSpeed = 11,
			InvisibleSpeed = 13.5,
			Ratio = 13.5 / 11,
		},
	},
	{
		Name = "Dullahan",
		Reject = {
			Type = Events.Types.DullahanPatternAbsent,
			Hunting = true,
			Qualified = true,
			Completed = true,
			DifferentPairCount = 0,
			PairCount = 7,
			RequiredPairs = 7,
		},
		Match = {
			Type = Events.Types.DullahanPattern,
			Hunting = true,
			Qualified = true,
			DifferentPairCount = 7,
			DifferentPairs = 7,
			PairCount = 7,
			RequiredPairs = 7,
			SampleCount = 14,
		},
	},
	{
		Name = "Oni",
		Reject = {
			Type = Events.Types.HuntSpeedMathResult,
			Hunting = true,
			Qualified = true,
			Completed = true,
			PairCount = 7,
			RequiredPairs = 7,
			Best = "Ordinary",
			BaseSpeed = 11,
		},
		Match = {
			Type = Events.Types.HuntSpeedMathResult,
			Hunting = true,
			Qualified = true,
			PairCount = 7,
			RequiredPairs = 7,
			Best = "Oni",
			BaseSpeed = 13.5,
			Fits = {Oni = {Matched = true}},
		},
	},
	{
		Name = "Wendigo",
		Reject = {
			Type = Events.Types.WendigoCurveResult,
			Qualified = true,
			Completed = true,
			Matched = false,
			Outcome = "Rejected",
		},
		Match = {
			Type = Events.Types.WendigoCurveResult,
			Qualified = true,
			Completed = true,
			Matched = true,
			Outcome = "Matched",
		},
	},
}

for _, scenario in ipairs(scenarios) do
	local coordinator = Coordinator.new({Definitions = {profiles[scenario.Name]}})
	coordinator:Start({})

	coordinator:Emit(scenario.Reject)
	local rejected = coordinator:Resolve({scenario.Name})[scenario.Name]
	expect(rejected.RuledOut == true, scenario.Name .. " should initially accept a qualified rule-out")
	local firstScored = scoredEntries(coordinator, scenario.Name)
	expect(#firstScored == 1 and firstScored[1].Polarity == "RuleOut", scenario.Name .. " should have one initial scored rule-out")

	local match = Events.Copy(scenario.Match)
	match.CollectorQualifier = "top-level-only"
	match.QualificationToken = scenario.Name .. "-qualified"
	coordinator:Emit(match)

	local supported = coordinator:Resolve({scenario.Name})[scenario.Name]
	expect(supported.Status == "Supported" and supported.Conflicted == false, scenario.Name .. " positive must supersede its earlier rule-out")
	local superseded = scoredEntries(coordinator, scenario.Name)
	expect(#superseded == 2, scenario.Name .. " supersession must append exactly one scored entry")
	expect(superseded[2].Polarity == "Positive", scenario.Name .. " correction should be positive")
	expect(superseded[2].Supersedes == superseded[1].Id, scenario.Name .. " positive must link to the rule-out it supersedes")
	expect(superseded[2].Details.CollectorQualifier == "top-level-only", scenario.Name .. " top-level qualifiers must survive in ledger Details")
	expect(superseded[2].Details.QualificationToken == scenario.Name .. "-qualified", scenario.Name .. " qualification identity must survive normalization")
	expect(superseded[2].Details.Qualified == true, scenario.Name .. " Qualified must remain durable evidence metadata")

	coordinator:Emit(scenario.Reject)
	local persistent = coordinator:Resolve({scenario.Name})[scenario.Name]
	expect(persistent.Status == "Supported" and persistent.Conflicted == false, scenario.Name .. " unique positive must survive a later contradictory sample")
	expect(#scoredEntries(coordinator, scenario.Name) == 2, scenario.Name .. " later noise must not append a contradictory scored decision")

	coordinator:Destroy()
end

do
	local coordinator = Coordinator.new({Definitions = {profiles.Wraith}})
	coordinator:Start({})
	coordinator:Emit({
		Type = Events.Types.SaltContact,
		ContactId = "late-disturbance",
		DirectContact = true,
		Time = 10,
	})
	coordinator:Emit({Type = Events.Types.Tick, Time = 14.1})
	expect(
		coordinator:Resolve({"Wraith"}).Wraith.Status == "Supported",
		"Wraith should resolve only after the four-second undisturbed grace"
	)
	coordinator:Emit({
		Type = Events.Types.SaltDisturbed,
		ContactId = "late-disturbance",
		DirectContact = false,
		Time = 14.2,
	})
	local corrected = coordinator:Resolve({"Wraith"}).Wraith
	local entries = scoredEntries(coordinator, "Wraith")
	expect(
		corrected.RuledOut == true and corrected.Conflicted == false,
		"a replicated disturbance must supersede an earlier Wraith timeout"
	)
	expect(
		#entries == 2 and entries[2].Supersedes == entries[1].Id,
		"the Wraith correction must append an explicit supersession"
	)
	coordinator:Destroy()
end

print("core-profile-supersession.spec: real coordinator supersession, persistent positives, and durable qualifiers passed")
