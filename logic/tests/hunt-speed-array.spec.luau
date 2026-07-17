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

Traffic("WendigoEnergySnapshot", {
	Transition = 1,
	Hunting = true,
	AverageEnergy = 62,
}):SendTo("SpeedArrayLog")
Traffic("WendigoSpeedSample", {
	Transition = 1,
	Hunting = true,
	Speed = 24.5,
}):SendTo("SpeedArrayLog")
Traffic("HuntSpeedSample", {
	Index = 1,
	Point = {s = 99, v = true},
}):SendTo("SpeedArrayLog")

expect(#entries == 2, "the drawer should ignore the old hunt-array display signals")
expect(entries[1].Text == "T01  HUNTING  ENERGY 62.00%"
	and entries[1].TextColor3 == "text",
	"the transition Energy snapshot should be the first row")
expect(entries[2].Text == "T01  HUNTING  SPEED 24.500"
	and entries[2].TextColor3 == "accent",
	"the settled Wendigo speed should be the second row")
expect(entries[1].LayoutOrder < entries[2].LayoutOrder,
	"Energy should render before speed for the same transition")

controller:Destroy()
expect(entries[1].Destroyed and entries[2].Destroyed, "destroy should remove generated rows")

print("hunt-speed-array.spec: Wendigo transition Energy and speed rows passed")
