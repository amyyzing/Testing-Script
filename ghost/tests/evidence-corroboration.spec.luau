local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local EvidenceCatalog = require("../evidence-catalog")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local Traffic = createTraffic()
local Verdict = createVerdict({
	Traffic = Traffic,
	EvidenceCatalog = EvidenceCatalog,
	ApplyJournalState = function() return true, true end,
})

local limitedTraffic = createTraffic()
local limitedVerdict = createVerdict({Traffic = limitedTraffic, EvidenceCatalog = EvidenceCatalog,
	ReadEvidenceLimit = function() return 2 end,
	ApplyJournalState = function() return true, true end})
for _, name in ipairs({"FreezingTemperatures", "SpiritBox", "GhostOrb"}) do
	limitedTraffic("EvidenceState", {Evidence = name, State = true}):SendTo("Verdict")
end
expect(limitedVerdict:GetEvidenceResolvedGhost() == nil
	and limitedVerdict:IsCompatible("Doppelganger") and limitedVerdict.Confidence[17] == 50,
	"an extra Orb remains Maybe instead of certainly resolving to either Doppelganger or Ghoul")
limitedVerdict:Reset()
for _, name in ipairs({"EMFLevel5", "SpiritBox", "GhostWriting"}) do
	limitedTraffic("EvidenceState", {Evidence = name, State = true}):SendTo("Verdict")
end
expect(limitedVerdict:GetEvidenceResolvedGhost() == nil,
	"excess evidence without Orb is contradictory, not a certain ordinary ghost")
expect(not EvidenceCatalog.ClassifyOrbCombination({"FreezingTemperatures", "SpiritBox", "GhostOrb"}, 2.5).Qualified,
	"invalid evidence limits must preserve the three-evidence default")

for key, compatible in pairs({FreezingTemperatures = true, GhostWriting = true, SpiritBox = true,
	EMFLevel5 = false, Handprints = false, LaserProjector = false, Wither = false}) do
	local v = createVerdict({Traffic = createTraffic(), EvidenceCatalog = EvidenceCatalog})
	v:SetEvidence("GhostOrb", true)
	if not compatible then v:ForceSelect("Doppelganger") end
	v:SetEvidence(key, true)
	expect(v:IsCompatible("Doppelganger") == compatible,
		key .. " must follow Doppelganger's native evidence table")
	if compatible then
		expect(v.Confidence[17] == 50 and v:GetEvidenceResolvedGhost() == nil,
			"Orb plus one compatible clue must remain Maybe")
	else
		expect(table.find(v.RuledOut, 17) and v.ForcedIndex == nil,
			"incompatible confirmed evidence must override a previous selection")
	end
end
local clearOrb = createVerdict({Traffic = createTraffic(), EvidenceCatalog = EvidenceCatalog})
clearOrb:SetEvidence("GhostOrb", true)
clearOrb:SetEvidence("GhostOrb", nil)
expect(clearOrb.Confidence[17] == nil, "removing Orb must remove its Maybe support")
clearOrb:SetEvidence("GhostOrb", true)
clearOrb:Support("Doppelganger", 60, "shared candle")
clearOrb:SetEvidence("GhostOrb", nil)
expect(clearOrb.Confidence[17] == 60, "clearing Orb must preserve independent ability support")
expect(EvidenceCatalog.SelectHighestConfidenceGuess({Candidates = {"Doppelganger", "Banshee"},
	ConfirmedEvidence = {GhostOrb = true, Handprints = true, SpiritBox = true},
	Detections = {Doppelganger = 99, Banshee = 0}, RandomIndex = function() return 1 end}) == "Banshee",
	"the timeout fallback must not revive an evidence-incompatible Doppelganger")

for _, profile in ipairs(EvidenceCatalog.Profiles) do
	local exact = EvidenceCatalog.FilterCandidates(profile.Evidence, {}, {
		NamesOnly = true,
		RealOnly = true,
		IncludeFalseEvidence = false,
	})
	expect(#exact == 1 and exact[1] == profile.Name,
		profile.Name .. " must have one unique three-evidence combination")
	local profileTraffic = createTraffic()
	local profileVerdict = createVerdict({
		Traffic = profileTraffic,
		EvidenceCatalog = EvidenceCatalog,
		ApplyJournalState = function() return true, true end,
	})
	for _, evidence in ipairs(profile.Evidence) do
		profileTraffic("EvidenceState", {
			Evidence = evidence,
			State = true,
		}):SendTo("Verdict")
	end
	if profile.Name == "Ghoul" then
		expect(profileVerdict:GetEvidenceResolvedGhost() == nil
			and profileVerdict:IsCompatible("Doppelganger"),
			"Ghoul's Orb combination must retain the compatible fake-Orb alternative")
	else
		expect(profileVerdict:GetEvidenceResolvedGhost() == profile.Name,
			profile.Name .. " traits must corroborate with its complete evidence set")
	end
end

Traffic("Support", {Ghost = "Keres", Confidence = 99}):SendTo("Verdict")
Traffic("Support", {Ghost = "Banshee", Confidence = 35}):SendTo("Verdict")
expect(Verdict.Lists[Verdict.Selected[1]] == "Keres",
	"the strongest trait should lead before evidence is known")

Traffic("EvidenceState", {Evidence = "Ghost Orb", State = true}):SendTo("Verdict")
expect(Verdict.Lists[Verdict.Selected[1]] == "Doppelganger" and Verdict.Confidence[17] == 50
	and Verdict:GetEvidenceResolvedGhost() == nil,
	"Orb should block incompatible traits and offer Doppelganger only as Maybe")

Traffic("Support", {Ghost = "Leviathan", Confidence = 60}):SendTo("Verdict")
Traffic("EvidenceState", {Evidence = "Prints", State = true}):SendTo("Verdict")
expect(Verdict.Lists[Verdict.Selected[1]] == "Leviathan",
	"trait confidence should rank only the evidence-compatible candidates")

Traffic("EvidenceState", {Evidence = "Spirit Box", State = true}):SendTo("Verdict")
expect(not Verdict:IsCompatible("Doppelganger") and table.find(Verdict.RuledOut, 17),
	"confirmed Handprints must rule Doppelganger out even in an impossible Orb combination")
expect(Verdict:GetEvidenceResolvedGhost() == nil,
	"contradictory evidence must not force a certain fake-Orb result")

Traffic("EvidenceState", {Evidence = "Spirit Box", State = nil}):SendTo("Verdict")
expect(Verdict.Lists[Verdict.Selected[1]] == "Leviathan",
	"clearing evidence should restore the strongest compatible trait")

Traffic("EvidenceState", {Evidence = "Ghost Orb", State = false}):SendTo("Verdict")
expect(Verdict.Lists[Verdict.Selected[1]] == "Keres",
	"a disproved real evidence must remove candidates that require it")
expect(Verdict.Confidence[9] == 60,
	"evidence incompatibility must not erase the underlying trait observation")

local snapshot = Verdict:Snapshot()
expect(snapshot.Evidence.Handprints == true
	and snapshot.DisprovedEvidence.GhostOrb == true,
	"the verdict snapshot should expose confirmed and disproved evidence")

local exactTraffic = createTraffic()
local exactVerdict = createVerdict({
	Traffic = exactTraffic,
	EvidenceCatalog = EvidenceCatalog,
	ApplyJournalState = function() return true, true end,
})
exactTraffic("RuleOut", {Ghost = "Spirit", Confidence = 99}):SendTo("Verdict")
for _, evidence in ipairs({"Inscription", "Prints", "Spirit Box"}) do
	exactTraffic("EvidenceState", {Evidence = evidence, State = true}):SendTo("Verdict")
end
expect(exactVerdict:GetEvidenceResolvedGhost() == "Spirit"
	and exactVerdict.Lists[exactVerdict.Selected[1]] == "Spirit"
	and table.find(exactVerdict.RuledOut, 19) == nil,
	"a complete unique evidence set should supersede a conflicting trait rule-out")
exactTraffic("RuleOut", {Ghost = "Spirit", Confidence = 99}):SendTo("Verdict")
expect(exactVerdict.Lists[exactVerdict.Selected[1]] == "Spirit"
	and table.find(exactVerdict.RuledOut, 19) == nil,
	"a later conflicting trait must not cross out a ghost confirmed by complete evidence")

local survivorTraffic = createTraffic()
local survivorVerdict = createVerdict({
	Traffic = survivorTraffic,
	EvidenceCatalog = EvidenceCatalog,
	ApplyJournalState = function() return true, true end,
})
for evidence, state in pairs({
	SpiritBox = true,
	LaserProjector = true,
	FreezingTemperatures = false,
	EMFLevel5 = false,
}) do
	survivorTraffic("EvidenceState", {Evidence = evidence, State = state}):SendTo("Verdict")
end
local survivor = survivorVerdict:Snapshot()
expect(survivor.Lists[survivor.Selected[1]] == "Entity"
	and survivorVerdict:GetEvidenceResolvedGhost() == "Entity"
	and #survivor["ruled-out"] == 24
	and #survivor.Unknown == 0,
	"the only evidence-compatible survivor must be selected immediately")

local timeoutChoice = EvidenceCatalog.SelectHighestConfidenceGuess({
	Candidates = {"Keres", "Banshee"},
	ConfirmedEvidence = {GhostOrb = true},
	Detections = {
		Keres = {NetConfidence = 99},
		Banshee = {NetConfidence = 35},
	},
	RandomIndex = function() return 1 end,
})
expect(timeoutChoice == "Banshee",
	"the timed random fallback must remove evidence-incompatible ghosts before ranking")

print("evidence-corroboration.spec: evidence gates trait selection and Journal choice")
