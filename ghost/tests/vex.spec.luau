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
	and presentVerdict.Confidence[22] == 99,
	"a present false InvisibleOnLIDAR attribute should support Vex")

local member = {
	Name = "InvisibleOnLIDAR",
	Value = nil,
	GetAttribute = function() return nil end,
	IsA = function(_, kind) return kind == "ValueBase" end,
}
local memberVerdict, memberTracker = run(nil, {member})
expect(memberTracker.Exists == true and memberTracker.Value == nil
	and memberVerdict.Confidence[22] == 99,
	"a present InvisibleOnLIDAR ValueBase should support Vex even when its value is nil")

local missingVerdict, missingTracker = run(nil)
expect(missingTracker.Exists == false and table.find(missingVerdict.RuledOut, 22),
	"a genuinely absent InvisibleOnLIDAR member should rule Vex out")

print("vex.spec: one-shot InvisibleOnLIDAR existence check passed")
