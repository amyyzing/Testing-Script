local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local catalog = require("../evidence-catalog")
local traffic = createTraffic()
local verdict = createVerdict({Traffic = traffic, EvidenceCatalog = catalog})
local observed
traffic:Receive("Verdict", function(signal, payload)
 if signal == "Support" then observed = payload end
end)
local function support(confidence)
 traffic("Support", {Ghost = "Wraith", Perk = "Undisturbed salt", Confidence = confidence}):SendTo("Verdict")
end
support(99)
assert(verdict.Confidence[25] == 65 and observed.Certainty == "Medium" and observed.Confidence == 65,
 "a potentially copied perk must stay medium while Doppelganger fits")
verdict:SetEvidence("EMFLevel5", true)
assert(verdict.Confidence[25] == 99, "independent incompatible evidence must remove the Doppelganger cap")
verdict:SetEvidence("EMFLevel5", nil)
assert(verdict.Confidence[25] == 65, "removing that evidence must restore medium confidence")
verdict:Reset()
support(35)
assert(verdict.Confidence[25] == 35 and observed.Certainty ~= "Medium",
 "medium policy must not promote weak observations")
verdict:Reset()
support(99)
verdict:RuleOut("Doppelganger", 99, "independent exclusion")
assert(verdict.Confidence[25] == 99, "a hard independent exclusion must release the cap")
verdict:Reset()
assert(next(verdict.SourceConfidence) == nil, "reset must clear retained source confidence")
traffic("Support", {Ghost = "Vex", Perk = "Invisible on LIDAR", Confidence = 99}):SendTo("Verdict")
traffic("Support", {Ghost = "Banshee", Perk = "Glass burst", Confidence = 65}):SendTo("Verdict")
assert(verdict.Selected[1] == 22 and verdict.Confidence[22] == 65,
 "a weak burst must not outrank a stronger signature merely because both are capped at medium")
print("perk-confidence.spec: copyable traits require independent Doppelganger exclusion")
