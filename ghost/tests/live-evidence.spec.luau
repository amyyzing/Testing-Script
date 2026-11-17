local sync = require("../live-evidence")
local catalog = require("../evidence-catalog")
local function folder(children)
	return {FindFirstChild = function(_, name) return children[name] end}
end
local enums = {}
for index, key in ipairs(catalog.EvidenceOrder) do enums[key] = index end
local modules = {}
for _, profile in ipairs(catalog.Profiles) do
	local evidence = {}
	for _, key in ipairs(profile.Evidence) do table.insert(evidence, enums[key]) end
	modules[profile.Name] = {Value = {Evidence = evidence}, IsA = function(_, class) return class == "ModuleScript" end}
end
local oni = catalog.Find("Oni")
modules.Oni.Value.Evidence = {enums.EMFLevel5, enums.SpiritBox, enums.Wither}
modules.Vex.Value.Evidence = {enums.GhostOrb, 999, enums.Wither}
local oldVex = catalog.Find("Vex").Evidence
local result = sync({Catalog = catalog,
	ReplicatedStorage = folder({Modules = folder({GhostTypes = folder(modules), EvidenceTypes = {Value = enums}})}),
	Require = function(module) return module.Value end,
})
assert(#result.Updated == 24 and #result.Skipped == 1, "validate every profile before applying native evidence")
assert(oni.EvidenceSet.EMFLevel5 and oni.EvidenceSet.Wither and not oni.EvidenceSet.FreezingTemperatures,
	"changed native evidence must update filtering sets and remove stale keys")
assert(oni.EvidenceDisplay[1] == "EMF Level 5", "display evidence must update with the filter")
assert(catalog.Find("Vex").Evidence == oldVex, "unknown enum must preserve the existing complete profile")
local unavailable = sync({Catalog = catalog, ReplicatedStorage = folder({})})
assert(#unavailable.Updated == 0, "missing native modules must not break startup")
print("live-evidence.spec: current definitions and malformed-data fallback passed")
