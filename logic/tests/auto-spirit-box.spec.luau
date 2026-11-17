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
	function object:GetAttribute(name) return rawget(self, name) end
	return object
end

local holder = node({
	Aggression = node({QuestionIndex = 2, Detection = {Text = "Are you angry?"}}),
	Location = node({QuestionIndex = 3, Detection = {Text = "Are you here?"}}),
	Age = node({QuestionIndex = 1, Detection = {Text = "How old are you?"}}),
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
	AskSpiritBox = function(category, index) table.insert(asked, {category, index}) end,
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
expect(#asked == 2 and asked[1][1] == "Aggression" and asked[1][2] == 2
	and asked[2][1] == "Location" and asked[2][2] == 3,
	"auto spirit must send the native category and index instead of question text")
holder.Age.QuestionIndex = 4
heartbeat:Fire(2)
expect(asked[3][1] == "Age" and asked[3][2] == 4,
	"a shuffled native question index must be read freshly")
for _, category in pairs(holder) do
	if type(category) == "table" then category.QuestionIndex = nil end
end
heartbeat:Fire(2)
expect(#asked == 3, "unreplicated question indices must not send invalid fallback requests")
click:Fire()
heartbeat:Fire(10)
expect(#asked == 3, "disabled auto spirit must stop asking questions")
controller:Destroy()
expect(not heartbeat:Connected(), "destroy should disconnect the heartbeat")

print("auto-spirit-box.spec: toggle and question cycle passed")
