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
			Type = Events.Types.NonPhantomPattern,
			Hunting = true,
			Qualified = true,
			Completed = true,
			PairCount = 7,
			RequiredPairs = 7,
			Outcome = "Flat",
		},
		Match = {
			Type = Events.Types.PhantomPattern,
			Hunting = true,
			Qualified = true,
			Completed = true,
			PairCount = 7,
			RequiredPairs = 7,
			VisibleSpeed = 11,
			InvisibleSpeed = 13.5,
			Ratio = 13.5 / 11,
			AbsoluteBaseFit = true,
			Multiplier = 1,
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
			Completed = true,
			PhantomExcluded = true,
			DifferentPairCount = 7,
			DifferentPairs = 7,
			UpwardStepCount = 1,
			PairCount = 7,
			RequiredPairs = 7,
			SampleCount = 14,
		},
	},
	{
		Name = "Oni",
		LaterRejectSupersedes = true,
		Reject = {
			Type = Events.Types.HuntSpeedMathResult,
			Hunting = true,
			Qualified = true,
			Completed = true,
			PairCount = 7,
			RequiredPairs = 7,
			Best = "Ordinary",
			BaseSpeed = 11,
			Fits = {Oni = {Base = 13.5, Matched = false}},
		},
		Match = {
			Type = Events.Types.HuntSpeedMathResult,
			Hunting = true,
			Qualified = true,
			Completed = true,
			PairCount = 7,
			RequiredPairs = 7,
			Best = "Oni",
			BaseSpeed = 13.5,
			Fits = {Oni = {Base = 13.5, Matched = true}},
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
	if scenario.LaterRejectSupersedes then
		local corrected = scoredEntries(coordinator, scenario.Name)
		expect(
			persistent.RuledOut == true and persistent.Conflicted == false,
			scenario.Name .. " must allow a later complete contradictory hunt to correct its result"
		)
		expect(
			#corrected == 3 and corrected[3].Supersedes == corrected[2].Id,
			scenario.Name .. " later correction must extend one explicit supersession chain"
		)
	else
		expect(persistent.Status == "Supported" and persistent.Conflicted == false, scenario.Name .. " unique positive must survive a later contradictory sample")
		expect(#scoredEntries(coordinator, scenario.Name) == 2, scenario.Name .. " later noise must not append a contradictory scored decision")
	end

	coordinator:Destroy()
end

do
	local coordinator = Coordinator.new({Definitions = {profiles.Wraith}})
	coordinator:Start({})
	coordinator:Emit({
		Type = Events.Types.SaltContactResult,
		ContactId = "late-disturbance",
		DirectContact = true,
		Disturbed = false,
		Completed = true,
		Elapsed = 1.25,
	})
	expect(
		coordinator:Resolve({"Wraith"}).Wraith.Status == "Supported",
		"Wraith should resolve only from the salt tracker's completed undisturbed result"
	)
	coordinator:Emit({
		Type = Events.Types.SaltDisturbed,
		ContactId = "late-disturbance",
		Disturbed = true,
		DirectContact = false,
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

do
	local coordinator = Coordinator.new({Definitions = {profiles.Wraith}})
	coordinator:Start({})
	coordinator:Emit({
		Type = Events.Types.SaltContactResult,
		ContactId = "salt-a",
		DirectContact = true,
		Disturbed = false,
		Completed = true,
		Elapsed = 1.25,
	})
	coordinator:Emit({
		Type = Events.Types.SaltDisturbed,
		ContactId = "salt-b",
		Disturbed = true,
	})
	local globallyRejected = coordinator:Resolve({"Wraith"}).Wraith
	local decisions = scoredEntries(coordinator, "Wraith")
	expect(
		globallyRejected.RuledOut == true and globallyRejected.Conflicted == false,
		"disturbed salt B must globally disprove a Wraith positive from salt A"
	)
	expect(
		#decisions == 2 and decisions[2].Supersedes == decisions[1].Id,
		"different salt contacts must share one Wraith supersession chain"
	)
	coordinator:Emit({
		Type = Events.Types.SaltContactResult,
		ContactId = "salt-c",
		DirectContact = true,
		Disturbed = false,
		Completed = true,
		Elapsed = 1.25,
	})
	expect(
		#scoredEntries(coordinator, "Wraith") == 2,
		"later undisturbed salt must not resurrect Wraith after any disturbance"
	)
	coordinator:Destroy()
end

do
	local coordinator = Coordinator.new({Definitions = {require("../Siren")}})
	coordinator:Start({})
	coordinator:Emit({
		Type = "SpiritBoxResponse",
		Qualified = true,
		Response = "- HUMMING -",
	})
	coordinator:Emit({Type = "GhostModelSex", Qualified = true, Sex = "Male"})
	local siren = coordinator:Resolve({"Siren"}).Siren
	local decisions = scoredEntries(coordinator, "Siren")
	expect(
		siren.RuledOut == true and siren.Conflicted == false,
		"male model plus humming must supersede Siren support without residue"
	)
	expect(
		#decisions == 2 and decisions[2].Supersedes == decisions[1].Id,
		"the Siren contradiction must be one explicit supersession chain"
	)
	coordinator:Destroy()
end

do
	local coordinator = Coordinator.new({Definitions = {require("../Aswang")}})
	coordinator:Start({})
	coordinator:Emit({
		Type = Events.Types.SpeedProbeResult,
		Trigger = Events.Types.SaltContact,
		Hunting = true,
		DirectContact = true,
		SaltDisturbed = true,
		ContactId = "aswang-salt",
		DisturbedContactId = "aswang-salt",
		BaselineSpeed = 11,
		CurrentSpeed = 8,
		Delta = -3,
	})
	local provisional = coordinator:Resolve({"Aswang"}).Aswang
	expect(
		provisional.Status == "Supported" and provisional.Confidence == 60,
		"an Aswang slowdown without recovery must remain below Pretty Sure"
	)
	coordinator:Emit({
		Type = Events.Types.SpeedProbeRecovery,
		Trigger = Events.Types.SaltContact,
		Hunting = true,
		DirectContact = true,
		SaltDisturbed = true,
		ContactId = "aswang-salt",
		DisturbedContactId = "aswang-salt",
		BaselineSpeed = 11,
		EventSpeed = 8,
		RecoverySpeed = 11,
	})
	expect(
		coordinator:Resolve({"Aswang"}).Aswang.Confidence == 99,
		"only a recovered temporary slowdown may upgrade Aswang to 99%"
	)
	coordinator:Destroy()
end

do
	local coordinator = Coordinator.new({Definitions = {require("../Leviathan")}})
	coordinator:Start({})
	coordinator:Emit({
		Type = "DeviceToggleBurst",
		Hunting = false,
		Qualified = true,
		SingleDevice = true,
		Count = 7,
		Duration = 2.5,
		Clean = true,
		PlayerCaused = false,
		AutomationCaused = false,
		FuseCaused = false,
	})
	expect(
		coordinator:Resolve({"Leviathan"}).Leviathan.Status == "Unknown",
		"a partially qualified burst must not identify Leviathan"
	)
	coordinator:Emit({
		Type = "DeviceToggleBurst",
		Hunting = false,
		Qualified = true,
		SingleDevice = true,
		Count = 7,
		Duration = 2.5,
		Clean = true,
		Alternating = true,
		Rapid = true,
		PlayerCaused = false,
		AutomationCaused = true,
		FuseCaused = false,
	})
	expect(
		coordinator:Resolve({"Leviathan"}).Leviathan.Status == "Unknown",
		"an automation-caused burst must not identify Leviathan"
	)
	coordinator:Emit({
		Type = "DeviceToggleBurst",
		Hunting = false,
		Qualified = true,
		SingleDevice = true,
		Count = 6,
		Duration = 2,
		Rapid = true,
		PlayerCaused = false,
		AutomationCaused = false,
		FuseCaused = false,
	})
	expect(
		coordinator:Resolve({"Leviathan"}).Leviathan.Status == "Unknown",
		"fewer than seven eligible device toggles must remain inconclusive"
	)
	coordinator:Emit({
		Type = "DeviceToggleBurst",
		Hunting = false,
		Qualified = true,
		SingleDevice = true,
		Count = 7,
		Duration = 2.5,
		Clean = true,
		Alternating = true,
		Rapid = true,
		PlayerCaused = false,
		AutomationCaused = false,
		FuseCaused = false,
	})
	local leviathan = coordinator:Resolve({"Leviathan"}).Leviathan
	local decisions = scoredEntries(coordinator, "Leviathan")
	expect(
		leviathan.Status == "Supported" and leviathan.Confidence == 99,
		"seven clean toggles on one eligible device within 2.5 seconds must identify Leviathan"
	)
	expect(
		#decisions == 1 and decisions[1].Polarity == "Positive",
		"incomplete, partial, and suppressed Leviathan bursts must not leave scored residue"
	)
	coordinator:Destroy()
end

do
	local coordinator = Coordinator.new({Definitions = {require("../Specter")}})
	coordinator:Start({})
	local function trial(id, outcome)
		coordinator:Emit({
			Type = "SpecterTrial",
			TrialId = id,
			Qualified = true,
			Completed = true,
			FavouriteRoomUnchanged = true,
			ArmedSeconds = 5,
			Outcome = outcome,
		})
	end

	trial("residence-1", "Residence")
	local supported = coordinator:Resolve({"Specter"}).Specter
	expect(
		supported.Status == "Supported" and supported.Confidence == 35,
		"one Specter residence should produce one effective 35% positive"
	)

	trial("departure-1", "Departure")
	local rejected = coordinator:Resolve({"Specter"}).Specter
	local decisions = scoredEntries(coordinator, "Specter")
	expect(
		rejected.RuledOut == true and rejected.Conflicted == false,
		"a Specter departure must supersede the stale residence positive"
	)
	expect(
		#decisions == 2 and decisions[2].Supersedes == decisions[1].Id,
		"the Specter rule-out must explicitly supersede its prior positive"
	)

	trial("residence-after-rule-out", "Residence")
	expect(
		#scoredEntries(coordinator, "Specter") == 2
			and coordinator:Resolve({"Specter"}).Specter.RuledOut == true,
		"later residence noise must not resurrect a ruled-out Specter"
	)
	coordinator:Destroy()
end

do
	local coordinator = Coordinator.new({Definitions = {require("../Specter")}})
	coordinator:Start({})
	for index = 1, 2 do
		coordinator:Emit({
			Type = "SpecterTrial",
			TrialId = "residence-upgrade-" .. tostring(index),
			Qualified = true,
			Completed = true,
			FavouriteRoomUnchanged = true,
			ArmedSeconds = 5,
			Outcome = "Residence",
		})
	end
	local upgraded = coordinator:Resolve({"Specter"}).Specter
	local decisions = scoredEntries(coordinator, "Specter")
	expect(
		upgraded.Status == "Supported" and upgraded.Confidence == 65,
		"two Specter residences should expose the upgraded 65% decision"
	)
	expect(
		#decisions == 2 and decisions[2].Supersedes == decisions[1].Id,
		"the 65% Specter decision must replace rather than duplicate 35%"
	)
	coordinator:Destroy()
end

do
	local coordinator = Coordinator.new({Definitions = {require("../Wisp")}})
	coordinator:Start({})
	coordinator:Emit({
		Type = "HolyOilCollision",
		ModelId = "oil-a",
		Hunting = true,
		Burning = true,
		Qualified = true,
		CanCollide = true,
	})
	expect(
		coordinator:Resolve({"Wisp"}).Wisp.RuledOut == true,
		"one qualified blocking oil may initially rule Wisp out"
	)
	coordinator:Emit({
		Type = "HolyOilCollision",
		ModelId = "oil-b",
		Hunting = true,
		Burning = true,
		Qualified = true,
		CanCollide = false,
	})
	local corrected = coordinator:Resolve({"Wisp"}).Wisp
	local decisions = scoredEntries(coordinator, "Wisp")
	expect(
		corrected.Status == "Supported" and corrected.Conflicted == false,
		"a qualified Wisp pass on another oil must supersede the earlier blocking model"
	)
	expect(
		#decisions == 2 and decisions[2].Supersedes == decisions[1].Id,
		"all Holy Oil models must share one Wisp decision chain"
	)
	coordinator:Emit({
		Type = "HolyOilCollision",
		ModelId = "oil-c",
		Hunting = true,
		Burning = true,
		Qualified = true,
		CanCollide = true,
	})
	expect(
		#scoredEntries(coordinator, "Wisp") == 2
			and coordinator:Resolve({"Wisp"}).Wisp.Status == "Supported",
		"a different unused blocking oil must not resurrect a Wisp rule-out"
	)
	coordinator:Destroy()
end

do
	local coordinator = Coordinator.new({Definitions = {require("../Wisp")}})
	coordinator:Start({})
	coordinator:Emit({
		Type = "HuntRoomRelation",
		HuntId = "outside-first",
		Hunting = true,
		Qualified = true,
		Completed = true,
		InFavouriteRoom = false,
	})
	expect(
		coordinator:Resolve({"Wisp"}).Wisp.RuledOut == true,
		"a hunt starting outside the favourite room must create a hard historical Wisp negative"
	)
	for index = 1, 2 do
		coordinator:Emit({
			Type = "HuntRoomRelation",
			HuntId = "favourite-later-" .. tostring(index),
			Hunting = true,
			Qualified = true,
			Completed = true,
			InFavouriteRoom = true,
		})
	end
	local roomDecisions = scoredEntries(coordinator, "Wisp")
	expect(
		#roomDecisions == 1
			and roomDecisions[1].Polarity == "Negative"
			and coordinator:Resolve({"Wisp"}).Wisp.RuledOut == true,
		"later ordinary favourite-room hunts must not supersede or erase the outside-room Wisp negative"
	)
	coordinator:Emit({
		Type = "HolyOilCollision",
		ModelId = "oil-after-room-negative",
		Hunting = true,
		Burning = true,
		Qualified = true,
		CanCollide = false,
	})
	local separatedDomains = scoredEntries(coordinator, "Wisp")
	expect(
		#separatedDomains == 2
			and separatedDomains[1].Polarity == "Negative"
			and separatedDomains[2].Supersedes == nil
			and separatedDomains[2].Polarity == "Positive"
			and separatedDomains[1].Id ~= separatedDomains[2].Id,
		"Holy Oil evidence must remain separate without superseding the historical hunt-room negative"
	)
	coordinator:Destroy()
end

do
	local coordinator = Coordinator.new({Definitions = {require("../Spirit")}})
	coordinator:Start({})
	coordinator:Emit({
		Type = "HolyOilColor",
		ModelId = "oil-a",
		Hunting = true,
		Burning = true,
		Qualified = true,
		Stable = true,
		Blue = false,
	})
	expect(
		coordinator:Resolve({"Spirit"}).Spirit.RuledOut == true,
		"one qualified stable non-blue oil may initially rule Spirit out"
	)
	coordinator:Emit({
		Type = "HolyOilColor",
		ModelId = "oil-b",
		Hunting = true,
		Burning = true,
		Qualified = true,
		Stable = true,
		Blue = true,
	})
	local corrected = coordinator:Resolve({"Spirit"}).Spirit
	local decisions = scoredEntries(coordinator, "Spirit")
	expect(
		corrected.Status == "Supported" and corrected.Conflicted == false,
		"a qualified blue flame on another oil must supersede the earlier non-blue model"
	)
	expect(
		#decisions == 2 and decisions[2].Supersedes == decisions[1].Id,
		"all Holy Oil models must share one Spirit decision chain"
	)
	coordinator:Emit({
		Type = "HolyOilColor",
		ModelId = "oil-c",
		Hunting = true,
		Burning = true,
		Qualified = true,
		Stable = true,
		Blue = false,
	})
	expect(
		#scoredEntries(coordinator, "Spirit") == 2
			and coordinator:Resolve({"Spirit"}).Spirit.Status == "Supported",
		"a different non-blue oil must not resurrect a Spirit rule-out after blue was observed"
	)
	coordinator:Destroy()
end

print("core-profile-supersession.spec: real coordinator supersession, persistent positives, and durable qualifiers passed")
