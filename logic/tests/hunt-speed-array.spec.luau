local createTraffic = require("../../ghost/traffic")
local createHuntSpeedArray = require("../hunt-speed-array")

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
	Title = {},
	List = {},
	Layout = layout,
	Empty = {Visible = true},
	Template = template,
}
local controller = createHuntSpeedArray({
	Traffic = Traffic,
	View = view,
	TextColor = "text",
	AccentColor = "accent",
	CanvasSize = function(x, y) return {X = x, Y = y} end,
	Defer = function(callback) callback() end,
})

Traffic("HuntSpeedReset", {}):SendTo("SpeedArrayLog")
Traffic("HuntSpeedSample", {Index = 1, Point = {s = 11, v = true}}):SendTo("SpeedArrayLog")
Traffic("HuntSpeedMarker", {Index = 1, Label = "SALT SPLIT"}):SendTo("SpeedArrayLog")
Traffic("HuntSpeedEnded", {Count = 1}):SendTo("SpeedArrayLog")

expect(#entries == 2 and string.find(entries[1].Text, "s = 11.000", 1, true),
	"speed samples should render the compact array point")
expect(entries[2].TextColor3 == "accent" and string.find(entries[2].Text, "SALT SPLIT", 1, true),
	"salt split should render as an accent marker")
expect(string.find(view.Title.Text, "ENDED", 1, true), "hunt end should retain and label the array")

controller:Destroy()
expect(entries[1].Destroyed and entries[2].Destroyed, "destroy should remove generated rows")

print("hunt-speed-array.spec: live samples, salt marker, and retention passed")
