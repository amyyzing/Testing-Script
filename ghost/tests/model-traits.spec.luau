local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local catalog = require("../evidence-catalog")
local createTraits = require("../discardable-trackers/model-traits")
local Dullahan = require("../ghosts/Dullahan")

local function fixture(initial)
	local callbacks = {}
	local ghost = {Headless = initial}
	function ghost:GetAttribute(name) return self[name] end
	function ghost:GetAttributeChangedSignal(name)
		assert(name == "Headless")
		return {Connect = function(_, callback)
			callbacks[callback] = true
			return {Disconnect = function() callbacks[callback] = nil end}
		end}
	end
	function ghost:Change(value)
		self.Headless = value
		for callback in pairs(callbacks) do callback() end
	end
	local traffic = createTraffic()
	local verdict = createVerdict({Traffic = traffic, EvidenceCatalog = catalog})
	local processor = Dullahan.new({Traffic = traffic})
	local count = 0
	traffic:Receive("Verdict", function(signal, payload)
		if signal == "Support" and payload.Ghost == "Dullahan" then count += 1 end
	end)
	local traits = createTraits({Traffic = traffic, Ghost = ghost})
	return ghost, verdict, traits, processor, function() return count end
end

local trueGhost, positive, traits, processor, count = fixture(true)
assert(positive.SourceConfidence[4] == 99 and positive.Confidence[4] == 65,
	"a native root flag supports Dullahan but remains medium while Doppelganger fits")
trueGhost:Change(true)
assert(count() == 1, "duplicate flag signals must not repeat the perk row")
positive:SetEvidence("Wither", true)
assert(positive.Confidence[4] == 99, "independent evidence can release the copied-perk cap")
traits:Destroy() processor:Destroy()

for _, value in ipairs({false, "true", 1}) do
	local _, verdict, tracker, detector = fixture(value)
	assert(verdict.SourceConfidence[4] == nil and not table.find(verdict.RuledOut, 4),
		"false or malformed flags must neither identify nor exclude Dullahan")
	tracker:Destroy() detector:Destroy()
end

local lateGhost, late, lateTraits, lateProcessor = fixture(nil)
assert(late.SourceConfidence[4] == nil, "missing heads or a missing flag are not native trait proof")
lateGhost:Change(true)
assert(late.SourceConfidence[4] == 99, "late replication of the root flag must be observed")
lateTraits:Destroy() lateProcessor:Destroy()
local stoppedGhost, stopped, stoppedTraits, stoppedProcessor = fixture(nil)
stoppedTraits:Destroy()
stoppedGhost:Change(true)
assert(stopped.SourceConfidence[4] == nil, "destroyed trait observation must disconnect")
stoppedProcessor:Destroy()

print("model-traits.spec: native headless flag, loading, confidence cap and cleanup passed")
