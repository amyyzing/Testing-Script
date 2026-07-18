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
	expect(profileVerdict:GetEvidenceResolvedGhost() == profile.Name,
		profile.Name .. " traits must corroborate with its complete evidence set")
end

Traffic("Support", {Ghost = "Keres", Confidence = 99}):SendTo("Verdict")
Traffic("Support", {Ghost = "Banshee", Confidence = 35}):SendTo("Verdict")
expect(Verdict.Lists[Verdict.Selected[1]] == "Keres",
	"the strongest trait should lead before evidence is known")

Traffic("EvidenceState", {Evidence = "Ghost Orb", State = true}):SendTo("Verdict")
expect(Verdict.Lists[Verdict.Selected[1]] == "Banshee",
	"confirmed evidence must block a stronger incompatible trait")

Traffic("Support", {Ghost = "Leviathan", Confidence = 60}):SendTo("Verdict")
Traffic("EvidenceState", {Evidence = "Prints", State = true}):SendTo("Verdict")
expect(Verdict.Lists[Verdict.Selected[1]] == "Leviathan",
	"trait confidence should rank only the evidence-compatible candidates")

Traffic("EvidenceState", {Evidence = "Spirit Box", State = true}):SendTo("Verdict")
expect(Verdict.Lists[Verdict.Selected[1]] == "Skinwalker",
	"an impossible three-evidence Orb combination must resolve to Skinwalker without a trait")
expect(Verdict:GetEvidenceResolvedGhost() == "Skinwalker",
	"the automation adapter should see the impossible Orb result as Certain")

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

print("evidence-corroboration.spec: evidence gates trait selection and Journal choice")
