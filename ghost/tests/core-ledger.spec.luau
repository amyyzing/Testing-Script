local Events = require("../events")
local Ledger = require("../evidence-ledger")
local Resolver = require("../resolver")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local now = 10
local ledger = Ledger.new({Clock = function() return now end})
local resolver = Resolver.new(ledger)

local positive = ledger:Positive("Phantom", "visibility-linked ratio", 95, {
	Id = "source-1",
	Source = "SpeedPattern",
})
ledger:Negative("Phantom", "flat phase speed", 60, {
	Id = "source-2",
	Source = "SpeedPattern",
})

local conflicted = resolver:ResolveGhost("Phantom")
expect(conflicted.Status == "Conflicted", "opposing qualified evidence must remain visibly conflicted")
expect(#conflicted.Positives == 1 and #conflicted.Negatives == 1, "both sides of a conflict must remain available")
expect(#ledger:Entries() == 2, "recording a conflict must not delete its earlier observation")

local corrected = ledger:RuleOut("Phantom", "corrected settled sample", 99, {
	Id = "source-3",
	Source = "SpeedPattern",
	Supersedes = positive.Id,
})
expect(corrected.Supersedes == positive.Id, "explicit corrections should retain their supersession link")
expect(#ledger:Entries() == 3, "supersession must append rather than mutate history")
expect(#ledger:EffectiveEntries("Phantom") == 2, "superseded evidence should leave the effective view only")

local ruledOut = resolver:ResolveGhost("Phantom")
expect(ruledOut.Status == "RuledOut", "an effective rule-out without positive support should rule out the ghost")
expect(ruledOut.Confidence == 0 and ruledOut.NegativeConfidence == 99, "resolver should report positive and negative strength separately")

local rankingLedger = Ledger.new()
local rankingResolver = Resolver.new(rankingLedger)
rankingLedger:Positive("Keres", "strong but contradicted support", 99)
rankingLedger:Negative("Keres", "qualified opposition", 80)
rankingLedger:Positive("Specter", "unopposed support", 35)
local ranked = rankingResolver:Rank({"Keres", "Specter"})
expect(
	ranked[1].Ghost == "Specter" and ranked[1].Score == 35,
	"ghost ranking must use net confidence so contradicted raw support cannot override the actual leader"
)

local normalized = Events.Normalize({
	Type = "Example",
	Payload = {Qualified = true, Count = 3},
}, {Time = 20, Source = "test"})
expect(normalized.Qualified == true and normalized.Count == 3, "normalization must expose payload fields to remote profile observers")
expect(normalized.Payload.Qualified == true, "normalization must preserve the payload representation")

ledger:Reset()
expect(#ledger:Entries() == 0, "round reset should clear the round-scoped ledger")
expect(ledger:Snapshot().Round == 2, "round reset should advance the ledger round")

print("core-ledger.spec: append-only evidence, conflicts, supersession, and reset passed")
