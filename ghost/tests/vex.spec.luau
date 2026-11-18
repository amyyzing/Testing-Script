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
	and presentVerdict.Confidence[22] == nil,
	"a present false InvisibleOnLIDAR attribute must not identify Vex")

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

print("vex.spec: one-shot InvisibleOnLIDAR existence check passed")
