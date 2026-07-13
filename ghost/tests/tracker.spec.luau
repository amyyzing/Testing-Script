local profiles = {
	Aswang = {Name = "Aswang"},
	Specter = {Name = "Specter"},
	Wisp = {Name = "Wisp"},
}

local aliases = {
	["aswang"] = profiles.Aswang,
	["specter"] = profiles.Specter,
	["the specter"] = profiles.Specter,
	["wisp"] = profiles.Wisp,
}

local Catalog = {
	PerkConfidence = {
		Aswang = 95,
		Specter = 35,
		Wisp = 60,
	},
	PerkTTL = {
		Specter = 5,
		Wisp = 8,
	},
}

function Catalog.Find(value)
	if type(value) == "table" then
		value = value.Name
	end
	return aliases[string.lower(tostring(value or ""))]
end

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

local function expectEqual(actual, expected, message)
	if actual ~= expected then
		error(("%s (expected %s, received %s)"):format(
			message,
			tostring(expected),
			tostring(actual)
		), 2)
	end
end

local now = 10
local changes = {}
local callbackTracker
local createTracker = require("../tracker")
local tracker = createTracker({
	Catalog = Catalog,
	Clock = function()
		return now
	end,
	OnChanged = function(change, changedTracker)
		table.insert(changes, change)
		callbackTracker = changedTracker
	end,
})

local detectionsReference = tracker.Detections
local ruleOutsReference = tracker.RuleOuts
expect(type(detectionsReference) == "table", "Detections should be public")
expect(type(ruleOutsReference) == "table", "RuleOuts should be public")

-- Catalog defaults, TTL, canonical aliases, and confidence dominance.
expect(tracker:Detect("The Specter", "first observation"), "default detection should record")
expectEqual(
	tracker.Detections.Specter.Confidence,
	35,
	"Detect should use catalog confidence"
)
expectEqual(
	tracker.Detections.Specter.ExpiresAt,
	15,
	"weak detection should use catalog TTL"
)
expect(
	tracker.Detections.Specter.Persistent == false,
	"weak detection should not be persistent"
)
expect(callbackTracker == tracker, "OnChanged should receive the tracker")
expectEqual(changes[#changes].Ghost, "Specter", "OnChanged should use canonical name")

now = 11
expect(
	not tracker:Detect("Specter", "weaker observation", 20),
	"weaker detection should not supersede the dominant score"
)
expectEqual(
	tracker.Detections.Specter.Confidence,
	35,
	"weaker detection should retain dominant confidence"
)
expectEqual(
	tracker.Detections.Specter.Reason,
	"first observation",
	"weaker detection should retain dominant reason"
)
expectEqual(
	tracker.Detections.Specter.ExpiresAt,
	16,
	"weaker repeat should refresh the dominant TTL"
)
expectEqual(
	changes[#changes].Type,
	"RefreshDetection",
	"TTL renewal should emit a refresh change"
)

now = 12
expect(
	tracker:Detect("Specter", "equal refreshed", 35, "test"),
	"equal detection should refresh its record"
)
expectEqual(
	tracker.Detections.Specter.Reason,
	"equal refreshed",
	"equal score should refresh reason"
)
expectEqual(tracker.Detections.Specter.DetectedAt, 12, "equal score should refresh time")
expectEqual(tracker.Detections.Specter.ExpiresAt, 17, "equal score should refresh expiry")
expectEqual(tracker.Detections.Specter.Source, "test", "equal score should refresh source")

now = 13
expect(
	tracker:Detect("Specter", "stronger", 60),
	"stronger detection should replace the record"
)
expectEqual(tracker.Detections.Specter.Confidence, 60, "stronger score should win")
expectEqual(tracker.Detections.Specter.ExpiresAt, 18, "replacement should get fresh TTL")

now = 14
expect(
	tracker:Detect("Specter", "pretty sure", 80),
	"80 confidence should replace weaker detection"
)
expect(tracker.Detections.Specter.Persistent, "80 confidence should be persistent")
expectEqual(
	tracker.Detections.Specter.ExpiresAt,
	nil,
	"persistent detection should never expire"
)

-- Rule-outs require 80 confidence, clear detections, and block new detections.
expect(
	not tracker:RuleOut("Specter", "too weak", 79),
	"rule-out below 80 should be rejected"
)
expect(tracker:GetDetection("Specter") ~= nil, "rejected rule-out should keep detection")

now = 15
expect(tracker:RuleOut("Specter", "negative pattern", 90), "strong rule-out should record")
expectEqual(tracker:GetDetection("Specter"), nil, "rule-out should clear detection")
expect(tracker:IsRuledOut("The Specter"), "alias should resolve for IsRuledOut")
expectEqual(tracker.RuleOuts.Specter.At, 15, "rule-out should use injected clock")
expectEqual(
	changes[#changes].DetectionCleared,
	true,
	"atomic RuleOut change should report cleared detection"
)
expect(
	not tracker:Detect("Specter", "blocked", 99),
	"ruled-out ghost should reject detections"
)
expect(
	not tracker:RuleOut("Specter", "weaker negative", 85),
	"weaker duplicate rule-out should not replace stronger one"
)
expectEqual(
	tracker.RuleOuts.Specter.Reason,
	"negative pattern",
	"dominant rule-out reason should remain"
)
expect(tracker:ClearRuleOut("Specter"), "ClearRuleOut should remove existing entry")
expect(not tracker:IsRuledOut("Specter"), "cleared ghost should no longer be ruled out")
expect(not tracker:ClearRuleOut("Specter"), "clearing absent rule-out should be false")

-- Explicit persistence and compatibility restoration.
now = 20
expect(tracker:Detect("Wisp", "temporary"), "Wisp should use its default")
expectEqual(tracker.Detections.Wisp.ExpiresAt, 28, "Wisp should get catalog TTL")
expect(tracker:MarkPersistent("Wisp"), "MarkPersistent should succeed")
expect(tracker.Detections.Wisp.Persistent, "MarkPersistent should set flag")
expectEqual(tracker.Detections.Wisp.ExpiresAt, nil, "MarkPersistent should clear expiry")
expect(tracker:MarkPersistent("Wisp"), "MarkPersistent should be idempotent")

local restored = {
	Confidence = 65,
	Reason = "saved mode detection",
	DetectedAt = 19,
	ExpiresAt = 27,
}
expect(tracker:SetDetection("Specter", restored), "SetDetection should restore a record")
expect(tracker.Detections.Specter ~= restored, "SetDetection should copy caller record")
restored.Reason = "caller mutation"
expectEqual(
	tracker.Detections.Specter.Reason,
	"saved mode detection",
	"caller mutation should not alter restored record"
)
expect(tracker:ClearDetection("Specter"), "ClearDetection should remove existing entry")
expect(not tracker:ClearDetection("Specter"), "clearing absent detection should be false")

-- Prune expires weak records and repairs high-confidence records without
-- replacing the stable public table.
tracker:SetDetection("Specter", {
	Confidence = 35,
	DetectedAt = 20,
	ExpiresAt = 21,
})
tracker:SetDetection("Aswang", {
	Confidence = 95,
	DetectedAt = 20,
	ExpiresAt = 21,
	Persistent = false,
})
now = 30
local pruned, removedCount, normalizedCount = tracker:Prune()
expect(pruned, "Prune should report mutations")
expectEqual(removedCount, 1, "Prune should remove one expired weak detection")
expectEqual(normalizedCount, 1, "Prune should normalize one strong detection")
expectEqual(tracker.Detections.Specter, nil, "expired detection should be removed")
expect(tracker.Detections.Aswang.Persistent, "strong detection should be persistent")
expectEqual(tracker.Detections.Aswang.ExpiresAt, nil, "strong expiry should be cleared")
expect(tracker.Detections == detectionsReference, "Prune must retain Detections identity")

-- PreserveFindings keeps both maps; a normal Reset clears them in place and
-- emits one aggregate reset change.
tracker:RuleOut("Wisp", "negative", 95)
local changeCount = #changes
expect(
	not tracker:Reset({PreserveFindings = true}),
	"preserving findings should not report a reset mutation"
)
expectEqual(#changes, changeCount, "preserving findings should not notify")
expect(tracker.Detections.Aswang ~= nil, "preserve should keep detections")
expect(tracker.RuleOuts.Wisp ~= nil, "preserve should keep rule-outs")

expect(tracker:Reset(), "normal Reset should clear findings")
expectEqual(next(tracker.Detections), nil, "Reset should empty Detections")
expectEqual(next(tracker.RuleOuts), nil, "Reset should empty RuleOuts")
expect(tracker.Detections == detectionsReference, "Reset must retain Detections identity")
expect(tracker.RuleOuts == ruleOutsReference, "Reset must retain RuleOuts identity")
expectEqual(changes[#changes].Type, "Reset", "Reset should emit aggregate change")
expect(not tracker:Reset(), "resetting an empty tracker should be a no-op")

expect(not tracker:Detect("Unknown", "invalid", 99), "unknown ghost should be rejected")
expect(not tracker:RuleOut("Unknown", "invalid", 99), "unknown rule-out should be rejected")

print("ghost/tracker.spec.luau: all tests passed")
