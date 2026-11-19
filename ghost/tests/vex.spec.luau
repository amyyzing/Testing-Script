local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createLidar = require("../discardable-trackers/lidar")
local Vex = require("../ghosts/Vex")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function run(attribute, descendants)
	local Ghost = {
		GetAttribute = function(_, name)
			if name == "InvisibleOnLIDAR" then return attribute end
		end,
		GetDescendants = function() return descendants or {} end,
	}
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local processor = Vex.new({Traffic = Traffic})
	local tracker = createLidar({Traffic = Traffic, Ghost = Ghost})
	processor:Destroy()
	return Verdict, tracker
end

local presentVerdict, presentTracker = run(false)
expect(presentTracker.Exists == true and presentTracker.Value == false
	and presentVerdict.Confidence[22] == nil and table.find(presentVerdict.RuledOut, 22),
	"a present false InvisibleOnLIDAR attribute must rule out Vex")

local member = {
	Name = "InvisibleOnLIDAR",
	Value = nil,
	GetAttribute = function() return nil end,
	IsA = function(_, kind) return kind == "ValueBase" end,
}
local memberVerdict, memberTracker = run(nil, {member})
expect(memberTracker.Exists == true and memberTracker.Value == nil
	and memberVerdict.Confidence[22] == nil,
	"a member without a true value must remain inconclusive")

local missingVerdict, missingTracker = run(nil)
expect(missingTracker.Exists == false and not table.find(missingVerdict.RuledOut, 22),
	"a missing replicated flag must not rule Vex out")
local trueVerdict = run(true)
expect((trueVerdict.Confidence[22] == 65 and trueVerdict.SourceConfidence[22] == 99), "a true invisibility flag should support Vex")

member.Value = true
local rootVisible = run(false, {member})
expect(table.find(rootVisible.RuledOut, 22), "a child flag must not mask explicit visibility on the ghost root")
member.Value = false
local rootInvisible = run(true, {member})
expect(rootInvisible.SourceConfidence[22] == 99, "the native root flag must remain authoritative")

print("vex.spec: one-shot InvisibleOnLIDAR existence check passed")

local traffic = createTraffic()
local verdict = createVerdict({Traffic = traffic})
local detector = Vex.new({Traffic = traffic})
traffic("LidarState", {Exists = true, Value = true}):SendTo("Vex")
traffic("LidarState", {Exists = true, Value = false}):SendTo("Vex")
assert(table.find(verdict.RuledOut,22), "a later visible state must exclude Vex after initial support")
traffic("LidarState", {Exists = true, Value = true}):SendTo("Vex")
assert(table.find(verdict.RuledOut,22), "later invisibility must not undo observed visibility")
detector:Destroy()
