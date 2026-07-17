local createAutoSpiritBox = require("../auto-spirit-box")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local callback
	return {
		Connect = function(_, value)
			callback = value
			return {Disconnect = function() callback = nil end}
		end,
		Fire = function(_, ...) if callback then callback(...) end end,
		Connected = function() return callback ~= nil end,
	}
end

local function node(children)
	local object = children or {}
	function object:FindFirstChild(name) return rawget(self, name) end
	return object
end

local holder = node({
	Aggression = node({Detection = {Text = "Are you angry?"}}),
	Location = node({Detection = {Text = "Are you here?"}}),
	Age = node({Detection = {Text = "How old are you?"}}),
})
local player = node({
	PlayerGui = node({SpiritBoxQuestions = node({Holder = holder})}),
})
local heartbeat = signal()
local click = signal()
local button = {MouseButton1Click = click, BackgroundColor3 = "off"}
local asked = {}
local controller = createAutoSpiritBox({
	Player = player,
	RunService = {Heartbeat = heartbeat},
	AskSpiritBox = function(question) table.insert(asked, question) end,
	Button = button,
	EnabledColor = "on",
	Interval = 2,
})

expect(not controller.Enabled and button.Text == "AUTO SPIRIT: OFF",
	"auto spirit should initialize off")
click:Fire()
expect(controller.Enabled and button.Text == "AUTO SPIRIT: ON",
	"the button should enable auto spirit")
heartbeat:Fire(0)
heartbeat:Fire(2)
expect(#asked == 2 and asked[1] == "Are you angry?" and asked[2] == "Are you here?",
	"auto spirit should immediately begin and cycle the visible questions")
click:Fire()
heartbeat:Fire(10)
expect(#asked == 2, "disabled auto spirit must stop asking questions")
controller:Destroy()
expect(not heartbeat:Connected(), "destroy should disconnect the heartbeat")

print("auto-spirit-box.spec: toggle and question cycle passed")
