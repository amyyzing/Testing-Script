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
for index = 1, 14 do
	Traffic("HuntSpeedSample", {
		Index = index,
		Point = {s = 27, v = index % 2 == 0},
	}):SendTo("SpeedArrayLog")
end
Traffic("HuntSpeedMarker", {Index = 4, Label = "SALT SPLIT"}):SendTo("SpeedArrayLog")
Traffic("SevenPairResult", {Samples = 14}):SendTo("SpeedArrayLog")
Traffic("HuntSpeedSample", {Index = 15, Point = {s = 99, v = true}}):SendTo("SpeedArrayLog")
Traffic("HuntSpeedEnded", {Count = 2}):SendTo("SpeedArrayLog")

expect(#entries == 15 and string.find(entries[14].Text, "P14", 1, true),
	"all fourteen paced samples should render before completion")
expect(entries[15].TextColor3 == "accent"
	and string.find(entries[15].Text, "SALT SPLIT", 1, true),
	"event markers should remain visible beside the paced array")
expect(#entries == 15, "speed rows should stop after the seven-pair result")
expect(string.find(view.Title.Text, "ENDED - 7 PAIRS", 1, true),
	"hunt end should retain the completed seven-pair label")

controller:Destroy()
expect(entries[1].Destroyed and entries[2].Destroyed, "destroy should remove generated rows")

print("hunt-speed-array.spec: live samples, salt marker, and retention passed")
