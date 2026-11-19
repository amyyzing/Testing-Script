local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local catalog = require("../evidence-catalog")
local createTraits = require("../discardable-trackers/model-traits")
local Ghoul = require("../ghosts/Ghoul")

local function fixture(value)
	local callbacks = {}
	local ghost = {CantDisableElectronics = value}
	function ghost:GetAttribute(name) return self[name] end
	function ghost:GetAttributeChangedSignal(name)
		callbacks[name] = callbacks[name] or {}
		local list = callbacks[name]
		return {Connect = function(_, callback)
			list[callback] = true
			return {Disconnect = function() list[callback] = nil end}
		end}
	end
	function ghost:Change(newValue)
		self.CantDisableElectronics = newValue
		for callback in pairs(callbacks.CantDisableElectronics) do callback() end
	end
	local traffic = createTraffic()
	local verdict = createVerdict({Traffic = traffic, EvidenceCatalog = catalog})
	local processor = Ghoul.new({Traffic = traffic})
	local count = 0
	traffic:Receive("Verdict", function(signal, payload)
		if signal == "Support" and payload.Ghost == "Ghoul" then count += 1 end
	end)
	local tracker = createTraits({Traffic = traffic, Ghost = ghost})
	return ghost, traffic, verdict, tracker, processor, function() return count end
end

local ghost, traffic, verdict, tracker, processor, count = fixture(true)
assert(verdict.SourceConfidence[7] == 99 and verdict.Confidence[7] == 65
	and verdict.Lists[verdict.Selected[1]] == "Ghoul",
	"native electronics immunity supports Ghoul while retaining the copied-perk cap")
ghost:Change(true)
assert(count() == 1, "duplicate native flag updates must not duplicate the observation")
for _, clue in ipairs({"FreezingTemperatures", "SpiritBox", "GhostOrb"}) do verdict:SetEvidence(clue, true) end
assert(verdict:IsDoppelgangerPossible() and verdict.Confidence[7] == 65,
	"Ghoul's complete clue profile must not manufacture certainty against fake-Orb Doppelganger")
traffic("ItemDisabledAwayFromPlayers", {ItemName = "Spirit Box", PlayerRadius = 15}):SendTo("Ghoul")
assert(table.find(verdict.RuledOut, 7), "a later qualified contradiction must still exclude Ghoul")
ghost:Change(false) ghost:Change(true)
assert(count() == 1 and table.find(verdict.RuledOut, 7),
	"a flag update cannot resurrect a contradicted Ghoul match")
tracker:Destroy() processor:Destroy()

for _, value in ipairs({false, "true", 1}) do
	local _, _, state, watcher, detector = fixture(value)
	assert(state.SourceConfidence[7] == nil and not table.find(state.RuledOut, 7),
		"false or malformed flags neither support nor exclude Ghoul")
	watcher:Destroy() detector:Destroy()
end

local late, _, state, watcher, detector = fixture(nil)
assert(state.SourceConfidence[7] == nil, "a loading gap is inconclusive")
late:Change(true)
assert(state.SourceConfidence[7] == 99, "late native electronics immunity must be observed")
watcher:Destroy() detector:Destroy()

local stopped, _, stoppedState, stoppedWatcher, stoppedDetector = fixture(nil)
stoppedWatcher:Destroy()
stopped:Change(true)
assert(stoppedState.SourceConfidence[7] == nil, "destroyed trait watchers must disconnect")
stoppedDetector:Destroy()
print("ghoul-traits.spec: native flag, copied-perk cap, contradiction and cleanup passed")
