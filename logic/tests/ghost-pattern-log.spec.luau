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
Traffic("RuleOut", payload):SendTo("Verdict")
expect(controller.Count == 2 and entries[2].TextColor3 == "red",
	"a negative result should be a distinct log")
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
Traffic("HuntingState", {Hunting = true}):SendTo("SpeedTracker")
expect(controller.Count == 5, "unrequested tracker events should not create rows")

controller:Destroy()
for _, entry in ipairs(entries) do expect(entry.Destroyed, "destroy should remove every generated log") end

print("ghost-pattern-log.spec: unique positive and negative observations passed")
