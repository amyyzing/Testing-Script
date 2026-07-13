local GhostModule = require("../ghost-module")

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
for _, profile in ipairs(GhostModule.Profiles) do
	expect(#profile.Evidence == 3, profile.Name .. " should have three real evidence types")
	expect(type(profile.Perks["Pretty Sure"]) == "table", profile.Name .. " needs Pretty Sure notes")
	expect(type(profile.Perks.Maybe) == "table", profile.Name .. " needs Maybe notes")
	expect(type(profile.Perks.Idk) == "table", profile.Name .. " needs Idk notes")
	local exact = GhostModule.FilterCandidates(profile.Evidence, {}, {
		NamesOnly = true,
		RealOnly = true,
	})
	expect(#exact == 1 and exact[1] == profile.Name, profile.Name .. " evidence should be unique")
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

local compositeCurrentGuess = GhostModule.SelectHighestConfidenceGuess({
	Candidates = {"Leviathan", "Skinwalker", "Wisp"},
	Detections = {
		Wisp = {Confidence = 65},
		Demon = {Confidence = 100},
	},
	CurrentGuess = "Leviathan / Skinwalker / Demon",
	CurrentScore = 95,
	RandomIndex = function(count)
		expect(count == 2, "only allowed composite names should tie")
		return 2
	end,
})
expect(
	compositeCurrentGuess == "Skinwalker",
	"current composite score should apply to each allowed parsed name"
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

print("ghost-module.spec: catalog, filtering, ranking, clone, and timeout guess assertions passed")
