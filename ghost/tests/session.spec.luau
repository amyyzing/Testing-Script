local definitions = {
	require("../Aswang"),
	require("../Banshee"),
	require("../Demon"),
	require("../Dullahan"),
	require("../Dybbuk"),
	require("../Entity"),
	require("../Ghoul"),
	require("../Keres"),
	require("../Leviathan"),
	require("../Nightmare"),
	require("../Oni"),
	require("../Phantom"),
	require("../Ravager"),
	require("../Revenant"),
	require("../Shadow"),
	require("../Siren"),
	require("../Skinwalker"),
	require("../Specter"),
	require("../Spirit"),
	require("../Umbra"),
	require("../Vesper"),
	require("../Vex"),
	require("../Wendigo"),
	require("../Wisp"),
	require("../Wraith"),
}

local GhostModule = require("../engine")(definitions)
local Session = require("../session")(GhostModule)

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

local function expectEqual(actual, expected, message)
	if actual ~= expected then
		error(("%s (expected %s, received %s)"):format(
			message,
			tostring(expected),
			tostring(actual)
		), 2)
	end
end

local function contains(values, expected)
	for _, value in ipairs(values) do
		if value == expected then
			return true
		end
	end
	return false
end

local function ruleOutAllExcept(...)
	local allowed = {}
	for _, ghostName in ipairs({...}) do
		allowed[ghostName] = true
	end
	local ruleOuts = {}
	for _, ghostName in ipairs(GhostModule.Order) do
		if not allowed[ghostName] then
			ruleOuts[ghostName] = true
		end
	end
	return ruleOuts
end

expect(type(Session.Evaluate) == "function", "session should expose Evaluate")
expect(type(Session.GetCandidates) == "function", "session should expose candidates")
expect(
	type(Session.GetPossibleEvidence) == "function",
	"session should expose possible evidence"
)
expect(
	type(Session.GetRankedDetection) == "function",
	"session should expose ranked detection"
)
expect(
	type(Session.GetExactEvidenceGuess) == "function",
	"session should expose exact evidence guesses"
)
expect(
	type(Session.GetTentativeEvidenceGuess) == "function",
	"session should expose tentative evidence guesses"
)
expect(
	type(Session.SelectFinalGuess) == "function",
	"session should expose final guesses"
)
expect(
	type(Session.SelectTimeoutGuess) == "function",
	"session should expose timeout guesses"
)
expect(
	Session.ResolveTeleportEvidence == nil,
	"teleport-specific guess resolution should not exist in the session"
)

-- Skinwalker's Orb is false evidence in Normal mode. It remains compatible,
-- including when all three real evidence types and the false Orb are confirmed.
local skinwalker = Session.Evaluate({
	Mode = "Normal",
	ConfirmedEvidence = {
		FreezingTemperatures = true,
		GhostWriting = true,
		SpiritBox = true,
		GhostOrb = true,
	},
})
expectEqual(#skinwalker.Candidates, 1, "Skinwalker evidence should leave one candidate")
expectEqual(skinwalker.Candidates[1], "Skinwalker", "false Orb should retain Skinwalker")
expect(skinwalker.PossibleEvidence.GhostOrb, "false Orb should remain possible")
expectEqual(
	skinwalker.ExactEvidenceGuess.Ghost,
	"Skinwalker",
	"four-piece Skinwalker evidence should be exact"
)
expectEqual(skinwalker.FinalGuess.Ghost, "Skinwalker", "exact evidence should win")
expect(skinwalker.FinalGuess.Certain, "exact evidence should be certain")

-- An observed Orb filters candidates immediately; a tentative Spirit Box does
-- not filter candidates until it is confirmed.
local orbObserved = Session.Evaluate({
	ConfirmedEvidence = {
		FreezingTemperatures = true,
		GhostWriting = true,
	},
	OrbObserved = true,
})
expectEqual(#orbObserved.Candidates, 1, "observed Orb should filter candidates")
expectEqual(orbObserved.Candidates[1], "Skinwalker", "false Orb should be accepted")

local promotedOrb = Session.Evaluate({
	ConfirmedEvidence = {EMFLevel5 = true},
	OrbObserved = true,
})
expect(
	promotedOrb.PromotedEvidence.GhostOrb == true,
	"an observed Orb should become confirmed once Skinwalker is incompatible"
)
expect(
	promotedOrb.ConfirmedEvidence.GhostOrb == true,
	"promoted Orb should participate in exact evidence policy"
)

local tentativeSpiritBox = Session.Evaluate({
	ConfirmedEvidence = {
		EMFLevel5 = true,
		GhostOrb = true,
	},
	SpiritBoxTentative = true,
})
expect(
	#tentativeSpiritBox.Candidates > 1,
	"tentative Spirit Box should not prematurely collapse candidates"
)
expectEqual(
	tentativeSpiritBox.TentativeEvidenceGuess.Ghost,
	"Nightmare",
	"tentative Spirit Box should identify Nightmare at reduced confidence"
)
expectEqual(
	tentativeSpiritBox.TentativeEvidenceGuess.Confidence,
	60,
	"tentative Spirit Box should use the existing 60% confidence"
)

-- Ghoul ambiguity now consumes the one RuleOuts map rather than a separate
-- ghoulRuledOut shadow flag.
local ghoulRuledOut = Session.Evaluate({
	ConfirmedEvidence = {
		FreezingTemperatures = true,
		GhostOrb = true,
	},
	SpiritBoxTentative = true,
	RuleOuts = {Ghoul = {Confidence = 98}},
})
expectEqual(
	ghoulRuledOut.TentativeEvidenceGuess.Ghost,
	"Skinwalker",
	"a unified Ghoul rule-out should resolve the tentative ambiguity"
)

local skinwalkerRuledOut = Session.Evaluate({
	ConfirmedEvidence = {
		FreezingTemperatures = true,
		GhostOrb = true,
	},
	SpiritBoxTentative = true,
	RuleOuts = {Skinwalker = true},
})
expectEqual(
	skinwalkerRuledOut.TentativeEvidenceGuess.Ghost,
	"Ghoul",
	"a unified Skinwalker rule-out should resolve the other side"
)

local demonRuledOut = Session.Evaluate({
	ConfirmedEvidence = {
		EMFLevel5 = true,
		FreezingTemperatures = true,
		Handprints = true,
	},
	RuleOuts = {Demon = true},
})
expect(
	demonRuledOut.ExactEvidenceGuess == nil,
	"exact evidence should respect the unified rule-out map"
)
expect(
	not contains(demonRuledOut.Candidates, "Demon"),
	"ruled-out ghosts should not remain candidates"
)

-- Mimicry inverts real-evidence compatibility. Persistent behavioral clues are
-- preserved even when fake evidence conflicts, while weaker clues are not.
expect(
	not Session.SupportsSessionEvidence("Aswang", {
		Mode = "Mimicry",
		ConfirmedEvidence = {EMFLevel5 = true},
	}),
	"a ghost's real evidence should conflict in Mimicry"
)
expect(
	Session.SupportsSessionEvidence("Banshee", {
		Mode = "Mimicry",
		ConfirmedEvidence = {EMFLevel5 = true},
	}),
	"evidence absent from a ghost's real set should be fake-compatible"
)

local persistentMimic = Session.Evaluate({
	Mode = "Mimicry",
	ConfirmedEvidence = {EMFLevel5 = true},
	Detections = {
		Aswang = {
			Confidence = 95,
			Reason = "strong behavior",
			ExpiresAt = 1,
		},
	},
	Now = 100,
})
expectEqual(
	persistentMimic.BestDetection.Ghost,
	"Aswang",
	"persistent Mimicry behavior should survive fake-evidence conflict"
)

local weakMimic = Session.Evaluate({
	Mode = "Mimicry",
	ConfirmedEvidence = {EMFLevel5 = true},
	Detections = {
		Aswang = {Confidence = 60, Reason = "weak behavior"},
	},
})
expect(
	weakMimic.BestDetection == nil,
	"weak incompatible Mimicry behavior should not override evidence"
)

-- Pretty Sure detections tie by tier, matching the prior UI behavior, even
-- when their exact scores differ. Lower tiers need scores within ten points.
local strongTie = Session.Evaluate({
	Detections = {
		Wisp = {Confidence = 90, Reason = "wisp pattern"},
		Leviathan = {Confidence = 80, Reason = "leviathan pattern"},
	},
})
expect(strongTie.BestDetection.Tied, "Pretty Sure detections should tie by tier")
expectEqual(
	strongTie.BestDetection.Ghost,
	"Leviathan / Wisp",
	"tied detection names should be deterministic"
)
expectEqual(
	#strongTie.RankedDetections,
	2,
	"both compatible detections should be returned in rank order"
)

local separatedWeakScores = Session.Evaluate({
	Detections = {
		Leviathan = {Confidence = 60},
		Wisp = {Confidence = 50},
	},
})
expectEqual(
	separatedWeakScores.BestDetection.Ghost,
	"Leviathan",
	"a ten-point gap should separate lower-tier detections"
)
expect(
	not separatedWeakScores.BestDetection.Tied,
	"separated lower-tier detections should not tie"
)

-- Evaluation never mutates caller-owned evidence, detections, or rule-outs.
local callerInput = {
	ConfirmedEvidence = {Orb = true},
	Detections = {
		Leviathan = {
			Confidence = 95,
			ExpiresAt = 5,
		},
		Wisp = {
			Confidence = 60,
			ExpiresAt = 5,
		},
	},
	RuleOuts = {Banshee = {Confidence = 95}},
	Now = 10,
}
local pureEvaluation = Session.Evaluate(callerInput)
expectEqual(
	callerInput.Detections.Leviathan.ExpiresAt,
	5,
	"persistent normalization must not mutate caller detection"
)
expectEqual(
	callerInput.Detections.Leviathan.Persistent,
	nil,
	"persistent normalization must stay inside the session copy"
)
expectEqual(
	callerInput.ConfirmedEvidence.Orb,
	true,
	"evidence aliases must not rewrite caller evidence"
)
expectEqual(
	callerInput.RuleOuts.Banshee.Confidence,
	95,
	"rule-outs must remain caller-owned"
)
expectEqual(
	pureEvaluation.BestDetection.Ghost,
	"Leviathan",
	"high-confidence detection should survive its stale caller expiry"
)
expectEqual(
	#pureEvaluation.RankedDetections,
	1,
	"expired weak detections should be omitted"
)

-- Do-Round timeout selection belongs to the session so callers only retain a
-- previous random choice while it remains among the current maximum scorers.
local retainedTimeout = Session.SelectTimeoutGuess({
	RuleOuts = ruleOutAllExcept("Leviathan", "Ravager"),
	Detections = {
		Leviathan = {Confidence = 60},
		Ravager = {Confidence = 60},
	},
}, {
	CurrentGuess = "Leviathan / Ravager",
	CurrentScore = 60,
	PreviousChoice = "Ravager",
	RandomIndex = function()
		error("a retained maximum choice must not use randomness")
	end,
	RandomUnit = function()
		error("a retained maximum choice must not use weighted randomness")
	end,
})
expectEqual(retainedTimeout.Ghost, "Ravager", "maximum tie choice should be retained")
expectEqual(retainedTimeout.Confidence, 60, "retained timeout confidence should match its score")
expectEqual(retainedTimeout.MaximumScore, 60, "timeout should expose the maximum score")
expectEqual(#retainedTimeout.Candidates, 2, "timeout should expose eligible candidates")
expectEqual(retainedTimeout.Candidates[1], "Leviathan", "candidates should keep catalog order")
expectEqual(retainedTimeout.Candidates[2], "Ravager", "candidates should keep catalog order")
expectEqual(retainedTimeout.MaximumNames[1], "Leviathan", "maximum names should be sorted")
expectEqual(retainedTimeout.MaximumNames[2], "Ravager", "maximum names should be sorted")
expectEqual(
	retainedTimeout.Signature,
	"Leviathan\0Ravager|orb=false",
	"timeout signature should identify its maximum tie and Orb state"
)
expect(not retainedTimeout.HasOrbEvidence, "timeout should report absent Orb evidence")

local invalidatedTimeout = Session.SelectTimeoutGuess({
	RuleOuts = ruleOutAllExcept("Leviathan", "Ravager"),
	Detections = {
		Leviathan = {Confidence = 60},
		Ravager = {Confidence = 60},
	},
}, {
	CurrentGuess = "Leviathan",
	CurrentScore = 70,
	PreviousChoice = "Ravager",
	RandomIndex = function()
		error("a unique maximum must not use randomness")
	end,
})
expectEqual(
	invalidatedTimeout.Ghost,
	"Leviathan",
	"a previous choice should be invalidated when it stops being maximum"
)
expectEqual(#invalidatedTimeout.MaximumNames, 1, "a unique maximum should be reported once")

local ruledOutTimeout = Session.SelectTimeoutGuess({
	RuleOuts = ruleOutAllExcept("Leviathan"),
	Detections = {
		Leviathan = {Confidence = 60},
		Ravager = {Confidence = 99, Persistent = true},
	},
}, {
	PreviousChoice = "Ravager",
})
expectEqual(ruledOutTimeout.Ghost, "Leviathan", "rule-outs should exclude timeout choices")
expectEqual(#ruledOutTimeout.Candidates, 1, "ruled-out detections should not be eligible")
expect(
	ruledOutTimeout.CandidateScores.Ravager == nil,
	"ruled-out ghosts should not receive timeout scores"
)

-- Persistent behavior remains selectable in Mimicry even when fake evidence
-- conflicts with the ghost's real evidence, but a rule-out still wins.
local persistentMimicTimeout = Session.SelectTimeoutGuess({
	Mode = "Mimicry",
	ConfirmedEvidence = {EMFLevel5 = true},
	RuleOuts = ruleOutAllExcept("Aswang", "Banshee"),
	Detections = {
		Aswang = {Confidence = 95, Persistent = true},
	},
})
expect(
	contains(persistentMimicTimeout.Candidates, "Aswang"),
	"persistent Mimicry behavior should survive evidence incompatibility at timeout"
)
expect(
	contains(persistentMimicTimeout.Candidates, "Banshee"),
	"ordinary Mimicry evidence-compatible candidates should remain eligible"
)
expectEqual(
	persistentMimicTimeout.Ghost,
	"Aswang",
	"persistent Mimicry detection should win the timeout score"
)

local ruledOutMimicTimeout = Session.SelectTimeoutGuess({
	Mode = "Mimicry",
	ConfirmedEvidence = {EMFLevel5 = true},
	RuleOuts = ruleOutAllExcept("Banshee"),
	Detections = {
		Aswang = {Confidence = 95, Persistent = true},
	},
})
expect(
	not contains(ruledOutMimicTimeout.Candidates, "Aswang"),
	"a persistent Mimicry detection should still respect its rule-out"
)
expectEqual(ruledOutMimicTimeout.Ghost, "Banshee", "remaining Mimicry candidate should win")

-- Without Orb, Skinwalker receives half its ordinary share and the removed
-- weight is redistributed. Once Orb is observed all maximum ghosts weigh alike.
local weightedTimeoutInput = {
	Mode = "Mimicry",
	RuleOuts = ruleOutAllExcept("Leviathan", "Ravager", "Skinwalker"),
	Detections = {
		Leviathan = {Confidence = 80, Persistent = true},
		Ravager = {Confidence = 80, Persistent = true},
		Skinwalker = {Confidence = 80, Persistent = true},
	},
}
local penalizedSkinwalker = Session.SelectTimeoutGuess(weightedTimeoutInput, {
	RandomUnit = function()
		return 0.7
	end,
})
expectEqual(
	penalizedSkinwalker.Ghost,
	"Ravager",
	"Skinwalker should receive half weight before Orb is observed"
)

weightedTimeoutInput.OrbObserved = true
local equalSkinwalker = Session.SelectTimeoutGuess(weightedTimeoutInput, {
	RandomUnit = function()
		return 0.7
	end,
})
expect(equalSkinwalker.HasOrbEvidence, "observed Orb should be present in timeout policy")
expectEqual(
	equalSkinwalker.Ghost,
	"Skinwalker",
	"Orb evidence should restore Skinwalker's equal timeout weight"
)
expectEqual(
	equalSkinwalker.Signature,
	"Leviathan\0Ravager\0Skinwalker|orb=true",
	"Orb state should invalidate a retained timeout signature"
)

print("ghost/session.spec.luau: all tests passed")
