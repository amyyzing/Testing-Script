local createTraffic = require("../../ghost/traffic")
local createFlickerArrayLog = require("../flicker-array-log")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local changedCallback
local layout = {AbsoluteContentSize = {Y = 80}}
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
local controller = createFlickerArrayLog({
	Traffic = Traffic,
	View = view,
	TextColor = "text",
	AccentColor = "accent",
	PositiveColor = "positive",
	CanvasSize = function(x, y) return {X = x, Y = y} end,
	Defer = function(callback) callback() end,
})

local item = {}
Traffic("FlickerArrayUpdate", {
	Item = item,
	ItemName = "Spirit Box",
	Switches = {{t = 5, v = false}, {t = 5.2, v = true}},
	RequiredSwitches = 5,
	Duration = 0.2,
}):SendTo("FlickerArrayLog")
expect(#controller.Entries == 3 and string.find(controller.Entries[1].Text, "Spirit Box", 1, true),
	"an item heading and its switch array should render")
expect(string.find(controller.Entries[2].Text, "t = +0.000", 1, true)
	and string.find(controller.Entries[3].Text, "v = true", 1, true),
	"switch rows should use relative time and boolean state")
local replacedRow = controller.Entries[1]

local completed = {
	{t = 10, v = false},
	{t = 10.4, v = true},
	{t = 10.8, v = false},
	{t = 11.2, v = true},
	{t = 11.6, v = false},
}
Traffic("FlickerArrayUpdate", {
	Item = item,
	ItemName = "Spirit Box",
	Switches = completed,
	RequiredSwitches = 5,
	Duration = 1.6,
	Completed = true,
}):SendTo("FlickerArrayLog")
expect(replacedRow.Destroyed and #controller.Entries == 6,
	"an updated item should replace its old rows instead of duplicating them")
expect(string.find(view.Title.Text, "LEVIATHAN MATCH", 1, true)
	and controller.Entries[1].TextColor3 == "positive",
	"a completed array should be visibly marked as a Leviathan match")

controller:Destroy()
expect(controller.Entries[1] == nil and changedCallback == nil,
	"destroy should disconnect and clear the flicker log")
print("flicker-array-log.spec: rolling item arrays render and replace speed logs")
