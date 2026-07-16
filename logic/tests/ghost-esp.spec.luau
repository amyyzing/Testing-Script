local createGhostESP = require("../ghost-esp")

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
		Fire = function(_) if callback then callback() end end,
	}
end

local destroyed = false
local button = {MouseButton1Click = signal(), BackgroundColor3 = "off"}
local controller = createGhostESP({
	Ghost = {},
	RunService = {RenderStepped = signal()},
	Workspace = {},
	GuiParent = {},
	Red = "red",
	Button = button,
	EnabledColor = "on",
	VisualFactory = function()
		return {Destroy = function() destroyed = true end}
	end,
})

expect(button.Text == "GHOST ESP: OFF", "button should initialize off")
button.MouseButton1Click:Fire()
expect(controller.Enabled and button.Text == "GHOST ESP: ON", "button should enable ESP")
controller:Destroy()
expect(destroyed and controller.Enabled == false, "destroy should remove the ESP visuals")

print("ghost-esp.spec: old ESP controller toggle and cleanup passed")
