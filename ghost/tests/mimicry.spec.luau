local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local catalog = require("../evidence-catalog")

local function fixture(active)
	local state = {Active = active}
	local traffic = createTraffic()
	local verdict = createVerdict({Traffic = traffic, EvidenceCatalog = catalog,
		ReadMimicry = function() return state.Active end})
	return verdict, state, traffic
end

for _, profile in ipairs(catalog.Profiles) do
	local verdict = fixture(true)
	for _, evidence in ipairs(profile.Evidence) do verdict:SetEvidence(evidence, true) end
	local extra = {}
	for _, evidence in ipairs(catalog.EvidenceOrder) do
		if not catalog.SupportsEvidence(profile, evidence, {IncludeFalseEvidence = true}) then
			table.insert(extra, evidence)
		end
	end
	verdict:SetEvidence(extra[1], true)
	assert(verdict:IsCompatible(profile.Name), profile.Name .. " must tolerate one challenge-generated fake clue")
	verdict:SetEvidence(extra[2], true)
	assert(not verdict:IsCompatible(profile.Name), profile.Name .. " cannot explain two extra fake clues")
end

local verdict, state, traffic = fixture(true)
for _, evidence in ipairs({"EMFLevel5", "FreezingTemperatures", "Handprints"}) do
	verdict:SetEvidence(evidence, true)
end
assert(verdict:GetEvidenceResolvedGhost() == nil,
	"three observations must not use the normal exact-evidence shortcut during Mimicry")
state.Active = false
traffic("EvidenceContextChanged", {}):SendTo("Verdict")
assert(verdict:GetEvidenceResolvedGhost() == "Demon", "normal evidence rules must return when the challenge ends")
state.Active = true
traffic("EvidenceContextChanged", {}):SendTo("Verdict")
assert(verdict:GetEvidenceResolvedGhost() == nil, "late challenge replication must undo premature certainty")

local orb, orbState, orbTraffic = fixture(false)
orb:SetEvidence("GhostOrb", true)
assert(orb.Confidence[17] == 50)
orbState.Active = true
orbTraffic("EvidenceContextChanged", {}):SendTo("Verdict")
assert(orb.Confidence[17] == nil and not orb.OrbMaybe,
	"a challenge-generated Orb must not give Doppelganger a special Maybe boost")
orbTraffic("Support", {Ghost = "Wraith", Perk = "Undisturbed salt", Confidence = 99}):SendTo("Verdict")
orb:SetEvidence("EMFLevel5", true)
assert(orb:IsDoppelgangerPossible() and orb.Confidence[25] == 65,
	"one fake incompatible clue cannot release the copyable-perk cap")
orb:SetEvidence("Handprints", true)
assert(not orb:IsDoppelgangerPossible() and orb.Confidence[25] == 99,
	"two independent incompatible clues must exceed the challenge allowance")
orb:RuleOut("Wraith", 99, "actual disturbed salt")
orbState.Active = false
orbTraffic("EvidenceContextChanged", {}):SendTo("Verdict")
orbState.Active = true
orbTraffic("EvidenceContextChanged", {}):SendTo("Verdict")
assert(table.find(orb.RuledOut, 25), "challenge changes must preserve qualified behavioral negatives")

print("mimicry.spec: every ghost tolerates one fake clue without false certainty or Orb preference")
