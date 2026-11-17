local createTraffic = require("../../ghost/traffic")
local createPatternLog = require("../ghost-pattern-log")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local changedCallback
local layout = {AbsoluteContentSize = {Y = 50}}
function layout:GetPropertyChangedSignal()
	return {
		Connect = function(_, callback)
			changedCallback = callback
			return {Disconnect = function() changedCallback = nil end}
		end,
	}
end

local entries = {}
local template = {}
function template:Clone()
	local entry = {Destroyed = false}
	function entry:Destroy() self.Destroyed = true end
	table.insert(entries, entry)
	return entry
end

local Traffic = createTraffic()
local view = {
	List = {},
	Layout = layout,
	Empty = {Visible = true},
	Template = template,
}
local controller = createPatternLog({
	Traffic = Traffic,
	View = view,
	PositiveColor = "green",
	NegativeColor = "red",
	EventColor = "blue",
	CanvasSize = function(x, y) return {X = x, Y = y} end,
	Defer = function(callback) callback() end,
})

local payload = {Ghost = "Aswang", Confidence = 99, Reason = "salt reduced speed"}
Traffic("Support", payload):SendTo("Verdict")
Traffic("Support", payload):SendTo("Verdict")
expect(controller.Count == 1 and #entries == 1, "identical patterns should be logged once")
expect(entries[1].TextColor3 == "green" and view.Empty.Visible == false,
	"support should create a positive row and hide the empty message")
Traffic("Support", {Ghost = "Aswang", Confidence = 50, Reason = payload.Reason}):SendTo("Verdict")
expect(controller.Count == 1 and #entries == 1
	and string.find(entries[1].Text, "[score 50/100]", 1, true),
	"a repeated pattern should update its confidence without adding another row")
Traffic("RuleOut", payload):SendTo("Verdict")
expect(controller.Count == 2 and entries[2].TextColor3 == "red",
	"a negative result should be a distinct log")
expect(entries[2].Text:find("RULED OUT",1,true) and not entries[2].Text:find("%%"), "an exclusion must never look like an identification percentage")
Traffic("Negative", {Ghost = "Entity", Confidence = 50, Reason = "no Smoke Holder"}):SendTo("Verdict")
expect(controller.Count == 3 and entries[3].TextColor3 == "red"
	and string.find(entries[3].Text, "NEGATIVE", 1, true),
	"a soft negative should be logged without becoming a rule-out")
Traffic("SaltHit", {ContactId = 7, Hunting = true}):SendTo("SpeedTracker")
expect(controller.Count == 4 and entries[4].TextColor3 == "blue"
	and string.find(entries[4].Text, "SALT HIT", 1, true),
	"salt contacts should create tracker rows")
Traffic("PlayerKilled", {userId = 42}):SendTo("SpeedTracker")
expect(controller.Count == 5 and string.find(entries[5].Text, "PLAYER KILLED", 1, true),
	"unique player kills should create tracker rows")
Traffic("KillSpeed", {
	userId = 42,
	baselineKill = {s = 22, v = false},
	beforeKill = {{s = 22, v = false}, {s = 24, v = false}, {s = 24, v = false}},
	afterKill = {{s = 24, v = false}, {s = 24, v = false}},
}):SendTo("Aswang")
expect(controller.Count == 5 and string.find(entries[5].Text, "22.000 -> 24.000", 1, true),
	"a pre-signal speed rise should update the player-kill row from its retained baseline")
Traffic("RoomTemperatureProgress", {
	RoomName = "Library",
	Count = 1,
	Required = 7,
	Average = 0.0525,
}):SendTo("GhostPatternLog")
expect(controller.Count == 6 and string.find(entries[6].Text, "1/7", 1, true)
	and string.find(entries[6].Text, "0.0525", 1, true),
	"the first Shadow cooling change should create a live average row")
Traffic("RoomTemperatureProgress", {
	RoomName = "Library",
	Count = 2,
	Required = 7,
	Average = 0.06,
}):SendTo("GhostPatternLog")
expect(controller.Count == 6 and string.find(entries[6].Text, "2/7", 1, true)
	and string.find(entries[6].Text, "0.0600", 1, true),
	"later Shadow changes should update the existing average row")
Traffic("HuntingState", {Hunting = true}):SendTo("SpeedTracker")
expect(controller.Count == 6, "unrequested tracker events should not create rows")

Traffic("GhostSpeedObserved",{Speed=21,Hunting=true,Visible=false,AverageEnergy=0}):SendTo("GhostPatternLog")
expect(controller.Count==7 and entries[7].Text:find("21.000",1,true) and entries[7].Text:find("unconfirmed",1,true),"raw speed and unknown scale must be visible before a verdict")
Traffic("HuntSpeedReset",{}):SendTo("SpeedArrayLog")
Traffic("HuntSpeedSample",{Index=4,Point={s=21,v=true}}):SendTo("SpeedArrayLog")
expect(controller.Count==8 and entries[8].Text:find("4/14",1,true),"unconsumed speed-array samples must reach a single updating row")
Traffic("SpeedFilterResult",{Identical=true,BaseSpeed=10.5,ScaleKnown=false}):SendTo("GhostPatternLog")
expect(controller.Count==8 and entries[8].Text:find("Oni waiting",1,true),"filter summaries must explain why a ghost is waiting")
Traffic("WretchEnergySnapshot",{Transition=2,Hunting=true,AverageEnergy=30}):SendTo("SpeedArrayLog")
Traffic("WretchSpeedResult",{AverageEnergy=30,Speed=21,ExpectedSpeed=25,Stable=true,Hunting=true,ScaleKnown=false}):SendTo("GhostPatternLog")
expect(controller.Count==9 and entries[9].Text:find("three distinct Energy",1,true),"Wretch must log its measurements even without confirmation")
Traffic("FootstepProgress",{Samples=2,Hunting=true}):SendTo("GhostPatternLog")
Traffic("FootstepProgress",{Samples=3,Hunting=true}):SendTo("GhostPatternLog")
expect(controller.Count==10 and entries[10].Text:find("contradict Umbra",1,true),"qualified footsteps must update the observation row")
controller:Destroy()
for _, entry in ipairs(entries) do expect(entry.Destroyed, "destroy should remove every generated log") end

print("ghost-pattern-log.spec: unique positive and negative observations passed")
