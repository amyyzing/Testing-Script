local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createFootstepSound = require("../discardable-trackers/footstep-sound")
local Umbra = require("../ghosts/Umbra")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function object(name, className)
	return {
		Name = name,
		IsA = function(_, kind) return className == kind end,
	}
end

local function run(children)
	local root = {GetChildren = function() return children end}
	local Ghost = {
		FindFirstChild = function(_, name)
			return name == "HumanoidRootPart" and root or nil
		end,
	}
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local processor = Umbra.new({Traffic = Traffic})
	local tracker = createFootstepSound({Traffic = Traffic, Ghost = Ghost})
	processor:Destroy()
	return Verdict, tracker
end

local silentVerdict, silentTracker = run({object("Hunting", "Sound"), object("RootRigAttachment", "Attachment")})
expect(silentTracker.HasOtherSound == false and silentVerdict.Confidence[20] == 95,
	"Hunting alone should support Umbra after the one immediate scan")

local audibleVerdict, audibleTracker = run({object("Hunting", "Sound"), object("Footsteps", "Sound")})
expect(audibleTracker.HasOtherSound == true and table.find(audibleVerdict.RuledOut, 20),
	"a direct HRP Sound other than Hunting should rule Umbra out")

local nestedVerdict, nestedTracker = run({object("FootstepContainer", "Folder")})
expect(nestedTracker.HasOtherSound == false and nestedVerdict.Confidence[20] == 95,
	"the scan should inspect only direct children of HumanoidRootPart")

print("umbra.spec: one-shot HumanoidRootPart Sound scan passed")
