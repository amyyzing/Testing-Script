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

controller:Destroy()
expect(entries[1].Destroyed and entries[2].Destroyed, "destroy should remove every generated log")

print("ghost-pattern-log.spec: unique positive and negative observations passed")
