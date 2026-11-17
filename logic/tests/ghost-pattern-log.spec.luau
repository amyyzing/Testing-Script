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
Traffic("Support", {Ghost = "Aswang", Confidence = 50, Reason = "another observation"}):SendTo("Verdict")
expect(controller.Count == 1 and entries[1].Text == "SUPPORT  Aswang",
	"support should show one verdict without scores or details")
Traffic("RuleOut", payload):SendTo("Verdict")
Traffic("Support", payload):SendTo("Verdict")
expect(controller.Count == 1 and entries[1].Text == "RULED OUT  Aswang" and entries[1].TextColor3 == "red",
	"exclusion should replace support without a percentage")
Traffic("Negative", {Ghost = "Entity"}):SendTo("Verdict")
expect(entries[2].Text == "AGAINST  Entity", "soft evidence should stay distinct from exclusions")
Traffic("SaltHit", {Hunting = true}):SendTo("SpeedTracker")
expect(entries[3].Text == "SALT HIT (HUNT)", "salt should show hunt context")
Traffic("PlayerKilled", {userId = 42}):SendTo("SpeedTracker")
Traffic("KillSpeed", {
	userId = 42,
	baselineKill = {s = 22},
	afterKill = {{s = 24}},
}):SendTo("Aswang")
expect(entries[4].Text == "KILL SPEED  22.00 -> 24.00", "kill speed should update the same row")
Traffic("RoomTemperatureProgress", {Temperature = 2.5, Count = 0}):SendTo("GhostPatternLog")
expect(entries[5].Text == "SHADOW TEMP  2.50 °C", "initial reading should show temperature")
Traffic("RoomTemperatureProgress", {Temperature = 2.45, Count = 1, Average = 0.05}):SendTo("GhostPatternLog")
expect(entries[5].Text == "SHADOW TEMP  2.45 °C | -0.050 °C/s", "the same row should show signed change")
Traffic("GhostSpeedObserved", {Speed = 21, Hunting = true}):SendTo("GhostPatternLog")
expect(entries[6].Text == "HUNT SPEED  21.00", "raw hunt speed should be visible")
Traffic("HuntSpeedReset", {}):SendTo("SpeedArrayLog")
Traffic("HuntSpeedSample", {Index = 4, Point = {s = 21, v = true}}):SendTo("SpeedArrayLog")
expect(entries[7].Text == "BLINK SPEED  4/14 | visible 21.00", "blink samples should update one row")
Traffic("HuntSpeedEnded", {Count = 4}):SendTo("SpeedArrayLog")
expect(entries[7].Text == "BLINK SPEED  4/14 | incomplete", "a partial hunt should be marked incomplete")
Traffic("SpeedFilterResult", {Identical = true, ScaleKnown = false}):SendTo("GhostPatternLog")
expect(entries[7].Text == "BLINK SPEED  14/14 | steady | scale unknown", "the summary should show relevant uncertainty")
Traffic("WretchSpeedResult", {AverageEnergy = 30, Speed = 21, Stable = true, Hunting = true}):SendTo("GhostPatternLog")
expect(entries[8].Text == "WRETCH  30% Energy | 21.00 | scale unknown", "Wretch should show Energy and speed")
Traffic("FootstepProgress", {Samples = 3, Hunting = true}):SendTo("GhostPatternLog")
expect(entries[9].Text == "UMBRA FOOTSTEPS  heard" and controller.Count == 9, "footstep observations should stay compact")

controller:Destroy()
for _, entry in ipairs(entries) do expect(entry.Destroyed, "destroy should remove every generated log") end

print("ghost-pattern-log.spec: unique positive and negative observations passed")
