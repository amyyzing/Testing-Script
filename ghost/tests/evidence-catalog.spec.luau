local GhostModule = require("../evidence-catalog")

local observerProfiles = {
	require("../../ghost/Aswang"), require("../../ghost/Banshee"),
	require("../../ghost/Demon"), require("../../ghost/Dullahan"),
	require("../../ghost/Dybbuk"), require("../../ghost/Entity"),
	require("../../ghost/Ghoul"), require("../../ghost/Keres"),
	require("../../ghost/Leviathan"), require("../../ghost/Nightmare"),
	require("../../ghost/Oni"), require("../../ghost/Phantom"),
	require("../../ghost/Ravager"), require("../../ghost/Revenant"),
	require("../../ghost/Shadow"), require("../../ghost/Siren"),
	require("../../ghost/Skinwalker"), require("../../ghost/Specter"),
	require("../../ghost/Spirit"), require("../../ghost/Umbra"),
	require("../../ghost/Vesper"), require("../../ghost/Vex"),
	require("../../ghost/Wendigo"), require("../../ghost/Wisp"),
	require("../../ghost/Wraith"),
}

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

expect(#GhostModule.Profiles == 25, "catalog should contain 25 ghosts")
expect(#GhostModule.Order == 25, "catalog order should contain 25 ghosts")
expect(GhostModule.NormalizeEvidence("Prints") == "Handprints", "Prints alias should normalize")
expect(GhostModule.NormalizeEvidence("Inscription") == "GhostWriting", "Inscription alias should normalize")
expect(GhostModule.Find("The Wisp").Name == "Wisp", "The Wisp alias should resolve")
local observersByName = {}
for _, observerProfile in ipairs(observerProfiles) do
	observersByName[observerProfile.Name] = observerProfile
end
for _, profile in ipairs(GhostModule.Profiles) do
	expect(#profile.Evidence == 3, profile.Name .. " should have three real evidence types")
	local observerProfile = observersByName[profile.Name]
	expect(observerProfile ~= nil, profile.Name .. " should have a modular observer profile")
	local catalogEvidence = {}
	for _, evidenceName in ipairs(profile.Evidence) do
		catalogEvidence[evidenceName] = true
	end
	local observerEvidence = {}
	for _, evidenceName in ipairs(observerProfile.Evidence) do
		observerEvidence[evidenceName] = true
	end
	for evidenceName in pairs(catalogEvidence) do
		expect(
			observerEvidence[evidenceName] == true,
			profile.Name .. " observer is missing catalog evidence " .. evidenceName
		)
	end
	for evidenceName in pairs(observerEvidence) do
		expect(
			catalogEvidence[evidenceName] == true,
			profile.Name .. " catalog is missing observer evidence " .. evidenceName
		)
	end
	expect(type(profile.Perks["Pretty Sure"]) == "table", profile.Name .. " needs Pretty Sure notes")
	expect(type(profile.Perks.Maybe) == "table", profile.Name .. " needs Maybe notes")
	expect(type(profile.Perks.Idk) == "table", profile.Name .. " needs Idk notes")
	local exact = GhostModule.FilterCandidates(profile.Evidence, {}, {
		NamesOnly = true,
		RealOnly = true,
	})
	expect(#exact == 1 and exact[1] == profile.Name, profile.Name .. " evidence should be unique")
	local falseEvidence = observerProfile.FalseEvidence or {}
	if profile.Name == "Skinwalker" then
		expect(
			#falseEvidence == 1 and falseEvidence[1] == "GhostOrb",
			"Skinwalker alone must expose Ghost Orb as a fourth/false evidence"
		)
	else
		expect(#falseEvidence == 0, profile.Name .. " must have only three real evidences")
	end
end

local allProfileNames = {}
for _, profile in ipairs(GhostModule.Profiles) do
	table.insert(allProfileNames, profile.Name)
end
for _, profile in ipairs(GhostModule.Profiles) do
	local conflictingDetections = {}
	for _, ghostName in ipairs(allProfileNames) do
		conflictingDetections[ghostName] = ghostName == profile.Name and 0 or 99
	end
	local selected = GhostModule.SelectHighestConfidenceGuess({
		Candidates = allProfileNames,
		Detections = conflictingDetections,
		ConfirmedEvidence = profile.Evidence,
		RandomIndex = function(count)
			expect(
				count == 1,
				profile.Name .. " exact evidence should leave one timeout choice"
			)
			return 1
		end,
	})
	expect(
		selected == profile.Name,
		profile.Name .. " exact evidence must beat incompatible 99% detections"
	)
end

local sirenCandidates = GhostModule.FilterCandidates({
	EMFLevel5 = true,
	SpiritBox = true,
	Wither = true,
}, {}, {NamesOnly = true})
expect(#sirenCandidates == 1 and sirenCandidates[1] == "Siren", "Siren evidence should be exact")

local skinwalkerCandidates = GhostModule.FilterCandidates({
	FreezingTemperatures = true,
	GhostWriting = true,
	SpiritBox = true,
	GhostOrb = true,
}, {}, {NamesOnly = true})
expect(
	#skinwalkerCandidates == 1 and skinwalkerCandidates[1] == "Skinwalker",
	"Skinwalker real evidence plus fake Orb should be unique"
)

local twoEvidenceOrb = GhostModule.ClassifyOrbCombination({
	GhostOrb = true,
	Handprints = true,
})
expect(
	twoEvidenceOrb.Qualified == false
		and twoEvidenceOrb.EvidenceCount == 2
		and #twoEvidenceOrb.RealCandidates == 4,
	"Orb plus one evidence must not identify Skinwalker"
)

local impossibleWithoutOrb = GhostModule.ClassifyOrbCombination({
	EMFLevel5 = true,
	Handprints = true,
	Wither = true,
})
expect(
	impossibleWithoutOrb.Qualified == false
		and impossibleWithoutOrb.OrbObserved == false,
	"an impossible combination without Orb must not identify Skinwalker"
)

local compatibleOrbTriple = GhostModule.ClassifyOrbCombination({
	GhostOrb = true,
	Handprints = true,
	LaserProjector = true,
})
expect(
	compatibleOrbTriple.Qualified == false
		and #compatibleOrbTriple.RealCandidates == 1
		and compatibleOrbTriple.RealCandidates[1] == "Umbra",
	"a valid three-evidence Orb combination must retain its normal ghost"
)

local impossibleOrbTriple = GhostModule.ClassifyOrbCombination({
	GhostOrb = true,
	Handprints = true,
	SpiritBox = true,
})
expect(
	impossibleOrbTriple.Qualified == true
		and impossibleOrbTriple.ImpossibleCombination == true
		and impossibleOrbTriple.FourthEvidence == false,
	"an impossible three-evidence Orb combination should identify Skinwalker"
)

local fourthOrbEvidence = GhostModule.ClassifyOrbCombination({
	GhostOrb = true,
	FreezingTemperatures = true,
	GhostWriting = true,
	SpiritBox = true,
})
expect(
	fourthOrbEvidence.Qualified == true
		and fourthOrbEvidence.FourthEvidence == true
		and fourthOrbEvidence.EvidenceCount == 4,
	"Skinwalker's three real evidences plus Orb should qualify as fourth evidence"
)

local impossibleOrbFinalGuess = GhostModule.SelectHighestConfidenceGuess({
	Candidates = allProfileNames,
	Detections = {Banshee = 99, Leviathan = 99, Skinwalker = 0},
	ConfirmedEvidence = {
		GhostOrb = true,
		Handprints = true,
		SpiritBox = true,
	},
})
expect(
	impossibleOrbFinalGuess == "Skinwalker",
	"an impossible Orb combination must force Skinwalker despite stronger perks"
)

local tracker = GhostModule.NewTracker()
tracker:ObserveEvidence("EMF Level 5")
tracker:ObserveEvidence("Spirit Box")
tracker:ObserveEvidence("Wither")
expect(tracker:GetCandidates({NamesOnly = true})[1] == "Siren", "tracker should derive Siren")

local ruledOut = tracker:WithRuleOut("Siren", "controlled negative", 95)
expect(#ruledOut:GetCandidates({NamesOnly = true}) == 0, "clone should apply its rule-out")
expect(#tracker:GetCandidates({NamesOnly = true}) == 1, "clone should not mutate the original tracker")

local ranked = GhostModule.RankDetections({
	Siren = {Confidence = 95, Reason = "LOS slowdown"},
	Keres = {Confidence = 35, Reason = "female model"},
}, {}, {})
expect(ranked[1].Ghost == "Siren", "higher confidence should rank first")
expect(ranked[1].TierName == "Pretty Sure", "95 confidence should be Pretty Sure")

local strictConfidenceRank = GhostModule.RankDetections({
	Specter = {Confidence = 35},
	Keres = {Confidence = 25},
}, {}, {})
local strictConfidenceTies = GhostModule.HighestConfidenceTies(strictConfidenceRank)
expect(
	#strictConfidenceTies == 1 and strictConfidenceTies[1] == "Specter",
	"35% Specter must outrank 25% Keres instead of grouping or retaining Keres"
)

local exactConfidenceRank = GhostModule.RankDetections({
	Leviathan = {Confidence = 60},
	Skinwalker = {Confidence = 60},
}, {}, {})
expect(
	#GhostModule.HighestConfidenceTies(exactConfidenceRank) == 2,
	"only equal confidence scores should remain tied"
)

local displayedConfidenceRank = GhostModule.RankDetections({
	Specter = {Confidence = 35, NetConfidence = 10},
	Keres = {Confidence = 25, NetConfidence = 25},
}, {}, {})
expect(
	displayedConfidenceRank[1].Ghost == "Specter",
	"a lower displayed confidence must not outrank a higher one"
)

local highestDetection = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Siren", "Keres", "Wisp"},
	Detections = {
		Siren = {Confidence = 95},
		Keres = 35,
		Wisp = {Score = 60},
	},
	RandomIndex = function()
		return 1
	end,
})
expect(highestDetection == "Siren", "highest candidate detection should be selected")

local certainEvidenceBeatsPerkConfidence = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Keres", "Siren", "Ghoul", "Nightmare"},
	Detections = {
		Keres = 99,
		Siren = 99,
		Ghoul = 0,
		Nightmare = 0,
	},
	ConfirmedEvidence = {
		SpiritBox = true,
		GhostOrb = true,
	},
	RandomIndex = function(count)
		expect(count == 2, "Spirit Box plus Orb should leave only Ghoul and Nightmare")
		return 1
	end,
})
expect(
	certainEvidenceBeatsPerkConfidence == "Ghoul",
	"confirmed evidence must outrank incompatible perk detections"
)

local printOrbTimeoutTie = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Banshee", "Leviathan"},
	Detections = {Banshee = 35, Leviathan = 35},
	ConfirmedEvidence = {
		Handprints = true,
		GhostOrb = true,
	},
	RandomIndex = function(count)
		expect(count == 2, "Print plus Orb should retain both supplied candidates")
		return 2
	end,
})
expect(
	printOrbTimeoutTie == "Leviathan",
	"an equal Print plus Orb timeout tie must still produce a final ghost"
)

local compositeCurrentGuess = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Leviathan", "Skinwalker", "Wisp"},
	Detections = {
		Wisp = {Confidence = 65},
		Demon = {Confidence = 100},
	},
	CurrentGuess = "Leviathan / Skinwalker / Demon",
	CurrentScore = 95,
})
expect(
	compositeCurrentGuess == "Wisp",
	"an aggregate composite score must not promote each parsed name"
)

local specterMustBeatWeakModelPair = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Specter", "Keres", "Siren"},
	Detections = {
		Specter = {Confidence = 35},
		Keres = {Confidence = 25},
		Siren = {Confidence = 25},
	},
	CurrentGuess = "Keres / Siren",
	CurrentScore = 35,
	RandomIndex = function(count)
		expect(count == 1, "only 35% Specter should remain in the top pool")
		return 1
	end,
})
expect(
	specterMustBeatWeakModelPair == "Specter",
	"25% Keres/Siren must not inherit a stale 35% composite score"
)

local skinwalkerDeweighted = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Ravager", "Leviathan", "Skinwalker"},
	Detections = {Ravager = 60, Leviathan = 60, Skinwalker = 60},
	RandomUnit = function()
		return 0.85
	end,
})
expect(
	skinwalkerDeweighted == "Skinwalker",
	"without Orb, Skinwalker should retain half of its equal-share tie weight"
)

local skinwalkerWithOrb = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Ravager", "Leviathan", "Skinwalker"},
	Detections = {Ravager = 60, Leviathan = 60, Skinwalker = 60},
	OrbObserved = true,
	RandomIndex = function(count)
		expect(count == 3, "Orb should restore equal tie weighting")
		return 3
	end,
})
expect(skinwalkerWithOrb == "Skinwalker", "Orb should remove the Skinwalker penalty")

local partialSkinwalkerOrb = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Banshee", "Ghoul", "Vex", "Skinwalker"},
	Detections = {
		Banshee = 60,
		Ghoul = 60,
		Vex = 60,
		Skinwalker = 60,
	},
	ConfirmedEvidence = {
		FreezingTemperatures = true,
		GhostOrb = true,
	},
	RandomIndex = function(count)
		expect(count == 4, "confirmed partial Orb evidence must retain an equally weighted Skinwalker")
		return 4
	end,
})
expect(
	partialSkinwalkerOrb == "Skinwalker",
	"Skinwalker must keep equal timeout weight while Orb is part of an incomplete evidence set"
)

local exactRealOrbCombination = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Banshee", "Skinwalker"},
	Detections = {Banshee = 0, Skinwalker = 99},
	ConfirmedEvidence = {
		FreezingTemperatures = true,
		GhostOrb = true,
		Handprints = true,
	},
	OrbObserved = true,
	RandomIndex = function(count)
		expect(count == 1, "a complete real evidence triple must beat Skinwalker's partial false Orb")
		return 1
	end,
})
expect(
	exactRealOrbCombination == "Banshee",
	"partial Skinwalker Orb support must not override a complete valid real evidence combination"
)

local detectionBeatsCurrent = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Siren", "Keres"},
	Detections = {Siren = 99},
	CurrentGuess = "Siren / Keres",
	CurrentScore = 50,
	RandomIndex = function()
		return 1
	end,
})
expect(
	detectionBeatsCurrent == "Siren",
	"current score should not replace a candidate's higher detection score"
)

local allZero = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Demon", "Wraith", "Umbra"},
	Detections = {NotAllowed = 100},
	CurrentGuess = "AlsoNotAllowed",
	CurrentScore = 100,
	RandomIndex = function(count)
		expect(count == 3, "all zero-score candidates should be eligible")
		return 3
	end,
})
expect(allZero == "Umbra", "all-zero candidates should use the random chooser")

local strongNegativeLoses = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Specter", "Keres"},
	Detections = {},
	NegativeConfidence = {Keres = 99},
	CurrentGuess = "Keres",
	CurrentScore = 35,
	RandomIndex = function(count)
		expect(count == 1, "a 99% negative must not remain tied with an unopposed ghost")
		return 1
	end,
})
expect(
	strongNegativeLoses == "Specter",
	"negative confidence must affect the final timeout choice and stale current guess"
)

local netDetectionIsNotDoublePenalized = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Specter", "Entity"},
	Detections = {
		Specter = {Confidence = 35, NetConfidence = 35},
		Entity = 20,
	},
	NegativeConfidence = {Specter = 60},
	RandomIndex = function(count)
		expect(count == 1, "stored net confidence must not be penalized a second time")
		return 1
	end,
})
expect(netDetectionIsNotDoublePenalized == "Specter", "net scores must remain authoritative")

local deduplicated = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Siren", "Siren", Keres = true},
	Detections = {Siren = 80, Keres = 80},
	RandomIndex = function(count)
		expect(count == 2, "duplicate candidates should be ignored")
		return 2
	end,
})
expect(deduplicated == "Keres", "keyed candidate names should be supported deterministically")

expect(GhostModule.SelectHighestConfidenceGuess() == nil, "missing options should return nil")
expect(
	GhostModule.SelectHighestConfidenceGuess({Candidates = {}}) == nil,
	"empty candidates should return nil"
)
expect(
	GhostModule.SelectHighestConfidenceGuess({Candidates = {false, 123}}) == nil,
	"invalid candidates should return nil"
)
expect(
	GhostModule.SelectHighestConfidenceGuess({
		Candidates = {"Siren"},
		RandomIndex = function()
			return 0
		end,
	}) == nil,
	"an invalid deterministic chooser result should return nil"
)

print("evidence-catalog.spec: catalog, filtering, ranking, clone, and timeout guess assertions passed")
