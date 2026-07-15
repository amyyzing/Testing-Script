local Events = require("../events")
local Ledger = require("../evidence-ledger")
local Resolver = require("../resolver")
local Specification = require("../specification")
local Coordinator = require("../coordinator")({
	Events = Events,
	EvidenceLedger = Ledger,
	Resolver = Resolver,
	Specification = Specification,
})

local Profiles = {
	Aswang = require("../Aswang"),
	Banshee = require("../Banshee"),
	Dullahan = require("../Dullahan"),
	Ghoul = require("../Ghoul"),
	Keres = require("../Keres"),
	Phantom = require("../Phantom"),
	Revenant = require("../Revenant"),
	Shadow = require("../Shadow"),
	Siren = require("../Siren"),
	Vex = require("../Vex"),
	Wendigo = require("../Wendigo"),
	Wraith = require("../Wraith"),
}

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

local function newCoordinator(names)
	local definitions = {}
	for _, name in ipairs(names) do
		local profile = assert(Profiles[name], "missing profile " .. name)
		table.insert(definitions, profile)
	end
	local coordinator = Coordinator.new({Definitions = definitions})
	coordinator:Start({})
	return coordinator
end

local function resolved(coordinator, name)
	return coordinator:Resolve({name})[name]
end

local function expectClean(coordinator, context)
	local errors = coordinator:Snapshot().Errors
	expect(#errors == 0, context .. " produced observer/coordinator errors")
end

local function destroyClean(coordinator, context)
	expectClean(coordinator, context)
	coordinator:Destroy()
end

-- Ghoul: exactly 15 studs is still within the cutoff; only a verified greater
-- distance qualifies the electronics rule-out. Hunt state is irrelevant.
do
	local coordinator = newCoordinator({"Ghoul"})
	coordinator:Emit({
		Type = Events.Types.HuntElectronicDisabled,
		Hunting = false,
		Qualified = true,
		NearestPlayerDistance = 15,
		PlayerCaused = false,
		AutomationCaused = false,
	})
	expect(
		resolved(coordinator, "Ghoul").Status == "Unknown",
		"a player exactly 15 studs away must remain inside Ghoul's cutoff"
	)
	coordinator:Emit({
		Type = Events.Types.HuntElectronicDisabled,
		Hunting = false,
		Qualified = true,
		NearestPlayerDistance = 15.001,
		PlayerCaused = false,
		AutomationCaused = false,
	})
	expect(
		resolved(coordinator, "Ghoul").RuledOut == true,
		"a verified non-hunt disable beyond 15 studs must rule Ghoul out"
	)
	destroyClean(coordinator, "Ghoul strict distance boundary")
end

-- Banshee: two distinct glass breaks in the canonical five-second window.
do
	local coordinator = newCoordinator({"Banshee"})
	coordinator:Emit({
		Type = Events.Types.BrokenGlassBurst,
		Qualified = true,
		Completed = true,
		Count = Specification.Banshee.RequiredBrokenGlass,
		Window = Specification.Banshee.WindowSeconds,
	})
	local state = resolved(coordinator, "Banshee")
	expect(
		state.Status == "Supported" and state.Confidence == 99,
		"two BrokenGlass models at exactly five seconds must support Banshee"
	)
	destroyClean(coordinator, "Banshee five-second boundary")

	coordinator = newCoordinator({"Banshee"})
	coordinator:Emit({
		Type = Events.Types.BrokenGlassBurst,
		Qualified = true,
		Completed = true,
		Count = Specification.Banshee.RequiredBrokenGlass,
		Window = Specification.Banshee.WindowSeconds + 0.001,
	})
	expect(
		resolved(coordinator, "Banshee").Status == "Unknown",
		"a BrokenGlass pair outside five seconds must not support Banshee"
	)
	destroyClean(coordinator, "Banshee outside-window boundary")
end

local function speedPairs(differences)
	local pairs = {}
	for index = 1, Specification.SpeedPairs.RequiredPairs do
		local first = 20 + index
		local difference = differences[index] or 0
		table.insert(pairs, {
			Pair = index,
			FirstSpeed = first,
			SecondSpeed = first + difference,
			FirstInvisible = index % 2 == 0,
			SecondInvisible = index % 2 ~= 0,
		})
	end
	return pairs
end

-- Dullahan: Phantom has priority; after it is excluded, any exact nonzero
-- upward step is sufficient. Seven exactly-flat pairs are the negative.
do
	local coordinator = newCoordinator({"Dullahan"})
	local differences = {0, 0, 0, 0, 0, 0, 0.000001}
	coordinator:Emit({
		Type = Events.Types.DullahanPattern,
		Hunting = true,
		Qualified = true,
		Completed = true,
		PhantomExcluded = false,
		PairCount = Specification.SpeedPairs.RequiredPairs,
		RequiredPairs = Specification.SpeedPairs.RequiredPairs,
		SampleCount = Specification.SpeedPairs.RequiredSamples,
		DifferentPairCount = 1,
		UpwardStepCount = 1,
		Pairs = speedPairs(differences),
	})
	expect(
		resolved(coordinator, "Dullahan").Status == "Unknown",
		"Dullahan must remain unknown until Phantom has been excluded"
	)
	coordinator:Emit({
		Type = Events.Types.DullahanPattern,
		Hunting = true,
		Qualified = true,
		Completed = true,
		PhantomExcluded = true,
		PairCount = Specification.SpeedPairs.RequiredPairs,
		RequiredPairs = Specification.SpeedPairs.RequiredPairs,
		SampleCount = Specification.SpeedPairs.RequiredSamples,
		DifferentPairCount = 1,
		UpwardStepCount = 1,
		Pairs = speedPairs(differences),
	})
	expect(
		resolved(coordinator, "Dullahan").Confidence == 99,
		"one nonzero upward value among seven pairs must identify Dullahan after Phantom is excluded"
	)
	destroyClean(coordinator, "Dullahan nonzero pair")

	coordinator = newCoordinator({"Dullahan"})
	coordinator:Emit({
		Type = Events.Types.DullahanPatternAbsent,
		Hunting = true,
		Qualified = true,
		Completed = true,
		PhantomExcluded = true,
		PairCount = Specification.SpeedPairs.RequiredPairs,
		RequiredPairs = Specification.SpeedPairs.RequiredPairs,
		SampleCount = Specification.SpeedPairs.RequiredSamples,
		DifferentPairCount = 0,
		Pairs = speedPairs({}),
	})
	expect(
		resolved(coordinator, "Dullahan").RuledOut == true,
		"seven zero-difference pairs must rule Dullahan out"
	)
	destroyClean(coordinator, "Dullahan zero pairs")
end

-- Phantom: seven local blink-state A/B pairs with one common absolute-base
-- multiplier, not a ratio-only or global-speed-bucket match.
do
	local coordinator = newCoordinator({"Phantom"})
	local pairs = {}
	local ratios = {}
	local expectedRatio = Specification.SpeedPairs.PhantomInvisibleBase
		/ Specification.SpeedPairs.PhantomVisibleBase
	for index = 1, Specification.SpeedPairs.RequiredPairs do
		local visible = Specification.SpeedPairs.PhantomVisibleBase
		local invisible = Specification.SpeedPairs.PhantomInvisibleBase
		table.insert(pairs, {
			Pair = index,
			FirstInvisible = index % 2 == 0,
			SecondInvisible = index % 2 ~= 0,
			VisibleSpeed = visible,
			InvisibleSpeed = invisible,
			Ratio = invisible / visible,
		})
		table.insert(ratios, invisible / visible)
	end
	coordinator:Emit({
		Type = Events.Types.PhantomPattern,
		Hunting = true,
		Qualified = true,
		Completed = true,
		PairCount = Specification.SpeedPairs.RequiredPairs,
		RequiredPairs = Specification.SpeedPairs.RequiredPairs,
		MatchedPairCount = Specification.SpeedPairs.RequiredPairs,
		Ratio = expectedRatio,
		PairRatios = ratios,
		Pairs = pairs,
		AbsoluteBaseFit = true,
		Multiplier = 1,
	})
	expect(
		resolved(coordinator, "Phantom").Confidence == 99,
		"seven stable repeated 13.5:11 AB pairs must identify Phantom"
	)
	destroyClean(coordinator, "Phantom AB ratio")
end

local function emitTemperatureDecision(coordinator, average, outcome)
	coordinator:Emit({
		Type = Events.Types.RoomTemperatureWindow,
		Qualified = true,
		Completed = true,
		SameRoom = true,
		RoundStarted = true,
		RoomName = "Contract Room",
		ResidenceSeconds = Specification.RoomTemperature.ResidenceSeconds,
		DecreaseCount = Specification.RoomTemperature.RequiredCoolingChanges,
		RequiredCoolingChanges = Specification.RoomTemperature.RequiredCoolingChanges,
		AverageDecrease = average,
		ShadowAverageThreshold = Specification.RoomTemperature.ShadowThreshold,
		RuleOutAverageThreshold = Specification.RoomTemperature.ShadowThreshold,
		Outcome = outcome,
	})
end

-- Shadow: the actual unrounded seven-change average is split at 0.08.
do
	local coordinator = newCoordinator({"Shadow"})
	emitTemperatureDecision(
		coordinator,
		Specification.RoomTemperature.ShadowThreshold - 0.001,
		"Shadow"
	)
	expect(
		resolved(coordinator, "Shadow").Confidence == 99,
		"a complete average below 0.08 must identify Shadow"
	)
	destroyClean(coordinator, "Shadow below threshold")

	coordinator = newCoordinator({"Shadow"})
	emitTemperatureDecision(
		coordinator,
		Specification.RoomTemperature.ShadowThreshold,
		"RuleOut"
	)
	expect(
		resolved(coordinator, "Shadow").RuledOut == true,
		"a complete average at or above 0.08 must rule Shadow out"
	)
	destroyClean(coordinator, "Shadow rule-out threshold")
end

-- Wraith: the salt tracker owns the placement grace. Once a direct contact has
-- remained clean for its 1.25-second result window, the profile decides; any
-- disturbed salt later supersedes that decision globally.
do
	local coordinator = newCoordinator({"Wraith"})
	coordinator:Emit({
		Type = Events.Types.SaltContactResult,
		ContactId = "salt-contract-a",
		DirectContact = true,
		Disturbed = false,
		Completed = true,
		Elapsed = Specification.Salt.UndisturbedDelay,
	})
	expect(
		resolved(coordinator, "Wraith").Confidence == 99,
		"a completed 1.25-second directly-touched undisturbed result must identify Wraith"
	)
	coordinator:Emit({
		Type = Events.Types.SaltDisturbed,
		ContactId = "salt-contract-b",
		DisturbedContactId = "salt-contract-b",
		Disturbed = true,
		SaltDisturbed = true,
	})
	local corrected = resolved(coordinator, "Wraith")
	expect(
		corrected.RuledOut == true and corrected.Conflicted == false,
		"any disturbed salt must supersede an earlier Wraith positive"
	)
	destroyClean(coordinator, "Wraith undisturbed/disturbed supersession")
end

-- Aswang: contact-time hunting remains authoritative after HuntEnded. The
-- temporary slowdown is provisional until the speed returns to baseline.
do
	local coordinator = newCoordinator({"Aswang"})
	coordinator:Emit({Type = Events.Types.HuntStarted, HuntId = 7, Hunting = true})
	coordinator:Emit({Type = Events.Types.HuntEnded, HuntId = 7, Hunting = false})
	local common = {
		Trigger = Events.Types.SaltContact,
		HuntId = 7,
		Hunting = false,
		HuntingAtContact = true,
		PostHuntReferenceQualified = true,
		Qualified = true,
		DirectContact = true,
		SaltDisturbed = true,
		ContactId = "aswang-contract-salt",
		DisturbedContactId = "aswang-contract-salt",
		BaselineSpeed = 11,
		CurrentSpeed = 8,
	}
	local ordinaryReset = Events.Copy(common)
	ordinaryReset.Type = Events.Types.SpeedProbeResult
	ordinaryReset.PostHuntReferenceQualified = nil
	ordinaryReset.BaselineSpeed = 22
	ordinaryReset.CurrentSpeed = 11
	ordinaryReset.Delta = -11
	ordinaryReset.HuntEndedBeforeSample = true
	coordinator:Emit(ordinaryReset)
	expect(
		resolved(coordinator, "Aswang").Status == "Unknown",
		"an unqualified hunt-to-non-hunt reset must not support Aswang"
	)
	local postHuntNoDrop = Events.Copy(common)
	postHuntNoDrop.Type = Events.Types.SpeedProbeResult
	postHuntNoDrop.Completed = true
	postHuntNoDrop.CurrentSpeed = 11
	postHuntNoDrop.Delta = 0
	postHuntNoDrop.HuntEndedBeforeSample = true
	coordinator:Emit(postHuntNoDrop)
	expect(
		resolved(coordinator, "Aswang").Status == "Unknown",
		"an ordinary hunt-end speed transition must not rule Aswang out"
	)
	local slowdown = Events.Copy(common)
	slowdown.Type = Events.Types.SpeedProbeResult
	slowdown.Completed = true
	slowdown.Delta = -3
	slowdown.HuntEndedBeforeSample = true
	coordinator:Emit(slowdown)
	local provisional = resolved(coordinator, "Aswang")
	expect(
		provisional.Status == "Supported" and provisional.Confidence == 60,
		"a post-hunt sample of hunting salt slowdown must remain provisional"
	)
	local recovery = Events.Copy(common)
	recovery.Type = Events.Types.SpeedProbeRecovery
	recovery.Completed = true
	recovery.EventSpeed = 8
	recovery.RecoverySpeed = 11
	recovery.HuntEndedBeforeSample = true
	coordinator:Emit(recovery)
	local confirmed = resolved(coordinator, "Aswang")
	expect(
		confirmed.Status == "Supported"
			and confirmed.Confidence == 99
			and confirmed.Conflicted == false,
		"recovery after a hunt-ending salt slowdown must confirm Aswang"
	)
	destroyClean(coordinator, "Aswang post-hunt recovery")
end

local function emitRevenant(elapsed, ended)
	local coordinator = newCoordinator({"Revenant"})
	coordinator:Emit({
		Type = ended and Events.Types.HuntEndedAfterDeath
			or Events.Types.HuntContinuedAfterDeath,
		DeathEventId = "revenant-" .. tostring(elapsed) .. "-" .. tostring(ended),
		ValidMultiplayerKill = true,
		OtherAlive = 1,
		Elapsed = elapsed,
		HuntStopped = ended,
		Hunting = not ended,
	})
	return coordinator
end

-- Revenant: <=1 second is positive, >=1.5 seconds continuing is negative, and
-- the deliberately unclassified gap must not be guessed.
do
	local coordinator = emitRevenant(Specification.Revenant.PositiveMaxSeconds, true)
	expect(
		resolved(coordinator, "Revenant").Confidence > 0,
		"a valid hunt end at one second must support Revenant"
	)
	destroyClean(coordinator, "Revenant positive boundary")

	coordinator = emitRevenant(Specification.Revenant.PositiveMaxSeconds + 0.001, true)
	expect(
		resolved(coordinator, "Revenant").Status == "Unknown",
		"a hunt end between one and 1.5 seconds must remain inconclusive"
	)
	destroyClean(coordinator, "Revenant inconclusive gap")

	coordinator = emitRevenant(Specification.Revenant.NegativeMinSeconds, false)
	expect(
		resolved(coordinator, "Revenant").RuledOut == true,
		"a hunt continuing for 1.5 seconds must rule Revenant out"
	)
	destroyClean(coordinator, "Revenant negative boundary")
end

-- Vex keys on replicated member existence. Its value may legitimately be false.
do
	local coordinator = newCoordinator({"Vex"})
	coordinator:Emit({
		Type = Events.Types.LidarState,
		Qualified = true,
		Exists = true,
		Value = false,
	})
	expect(
		resolved(coordinator, "Vex").Confidence == 99,
		"a present false InvisibleOnLIDAR member must identify Vex"
	)
	destroyClean(coordinator, "Vex false-valued member")

	coordinator = newCoordinator({"Vex"})
	coordinator:Emit({
		Type = Events.Types.LidarState,
		Qualified = true,
		Exists = false,
	})
	expect(
		resolved(coordinator, "Vex").RuledOut == true,
		"only a genuinely missing InvisibleOnLIDAR member may rule Vex out"
	)
	destroyClean(coordinator, "Vex missing member")
end

-- Keres and Siren both treat the verified male VisualModel package as a hard
-- 99% negative; the resolver must expose the same cross-out to every consumer.
do
	local coordinator = newCoordinator({"Keres", "Siren"})
	coordinator:Emit({
		Type = Events.Types.GhostModelSex,
		Qualified = true,
		Sex = "Male",
	})
	for _, name in ipairs({"Keres", "Siren"}) do
		local state = resolved(coordinator, name)
		expect(
			state.RuledOut == true
				and state.HardNegative == true
				and state.NegativeConfidence == 99,
			"male VisualModel must be a hard negative for " .. name
		)
	end
	destroyClean(coordinator, "Keres/Siren male hard negatives")
end

-- Wendigo consumes transition-time sanity math only. Hunt/blink pair math may
-- still exist for Normal/Oni but must not route into the Wendigo observer.
do
	local coordinator = newCoordinator({"Wendigo"})
	coordinator:Emit({
		Type = Events.Types.HuntSpeedMathResult,
		Hunting = true,
		Qualified = true,
		Completed = true,
		PairCount = Specification.SpeedPairs.RequiredPairs,
		Best = "Wendigo",
		Fits = {Wendigo = {Matched = true}},
	})
	expect(
		resolved(coordinator, "Wendigo").Status == "Unknown",
		"blink-pair hunt math must not identify Wendigo"
	)
	coordinator:Emit({
		Type = Events.Types.WendigoCurveResult,
		Qualified = true,
		Completed = true,
		Matched = true,
		Outcome = "Matched",
		Snapshots = {
			{Hunting = true, AverageSanity = 60, Speed = 11},
			{Hunting = false, AverageSanity = 59, Speed = 11.05 * 1.75},
			{Hunting = true, AverageSanity = 58, Speed = 11.1},
		},
	})
	expect(
		resolved(coordinator, "Wendigo").Confidence == 99,
		"a qualified completed transition-time sanity curve must identify Wendigo"
	)
	destroyClean(coordinator, "Wendigo transition-only match")

	coordinator = newCoordinator({"Wendigo"})
	coordinator:Emit({
		Type = Events.Types.WendigoCurveResult,
		Qualified = true,
		Completed = true,
		Matched = false,
		Outcome = "Rejected",
		Snapshots = {
			{Hunting = true, AverageSanity = 60, Speed = 11},
			{Hunting = false, AverageSanity = 59, Speed = 5},
			{Hunting = true, AverageSanity = 58, Speed = 11},
		},
	})
	expect(
		resolved(coordinator, "Wendigo").RuledOut == true,
		"a qualified rejected transition-time sanity curve must rule Wendigo out"
	)
	destroyClean(coordinator, "Wendigo transition-only rejection")
end

print("rewrite-contract.spec: canonical rewrite observer/coordinator contracts passed")
