local Events = require("../events")
local Analyzer = require("../analyzers/evidence-combination")({Events = Events})

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local catalog = {
	{Name = "Banshee", Evidence = {"FreezingTemperatures", "GhostOrb", "Handprints"}},
	{Name = "Leviathan", Evidence = {"GhostOrb", "GhostWriting", "Handprints"}},
	{Name = "Skinwalker", Evidence = {"FreezingTemperatures", "GhostWriting", "SpiritBox"}},
}
local emitted = {}
local analyzer = Analyzer.new()
analyzer:Start({Catalog = catalog, Emit = function(event) table.insert(emitted, event) end})
analyzer:OnEvent({
	Type = Events.Types.EvidenceSnapshot,
	Evidence = {GhostOrb = true, Handprints = true, FreezingTemperatures = true},
})
expect(#emitted == 0, "a valid real three-evidence Orb combination must remain ordinary evidence")
analyzer:OnEvent({
	Type = Events.Types.EvidenceSnapshot,
	Evidence = {GhostOrb = true, SpiritBox = true, Handprints = true},
})
expect(#emitted == 1 and emitted[1].Payload.ImpossibleCombination == true,
	"an impossible three-evidence combination containing Orb must emit FalseOrb")
analyzer:OnEvent({
	Type = Events.Types.EvidenceSnapshot,
	Evidence = {
		GhostOrb = true,
		FreezingTemperatures = true,
		GhostWriting = true,
		SpiritBox = true,
	},
})
expect(#emitted == 2 and emitted[2].Payload.FourthEvidence == true,
	"Skinwalker's three real evidences plus Orb must emit the fourth-evidence result")
analyzer:OnEvent({
	Type = Events.Types.EvidenceSnapshot,
	Evidence = {
		GhostOrb = true,
		FreezingTemperatures = true,
		GhostWriting = true,
		SpiritBox = true,
	},
})
expect(#emitted == 2, "the same qualified evidence snapshot must not emit twice")

print("core-evidence-combination.spec: real, impossible, and fourth Orb combinations passed")
