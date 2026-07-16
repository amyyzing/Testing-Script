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

local ghost = {}
local created = {}
local button = {MouseButton1Click = signal(), BackgroundColor3 = "off"}
local controller = createGhostESP({
	Ghost = ghost,
	Button = button,
	EnabledColor = "on",
	DepthMode = "always",
	FillColor = "red",
	OutlineColor = "white",
	CreateHighlight = function()
		local highlight = {Destroyed = false}
		function highlight:Destroy() self.Destroyed = true end
		table.insert(created, highlight)
		return highlight
	end,
})

expect(button.Text == "GHOST ESP: OFF", "button should initialize off")
button.MouseButton1Click:Fire()
local first = created[1]
expect(controller.Enabled and button.Text == "GHOST ESP: ON", "button should enable ESP")
expect(first.Adornee == ghost and first.Parent == ghost, "highlight should attach to the ghost")
expect(first.DepthMode == "always" and first.FillTransparency == 0.65, "highlight should show through walls")

button.MouseButton1Click:Fire()
expect(not controller.Enabled and first.Destroyed, "disabling should destroy the highlight")
button.MouseButton1Click:Fire()
local second = created[2]
controller:Destroy()
expect(second.Destroyed and controller.Highlight == nil, "destroy should remove every ESP instance")

print("ghost-esp.spec: toggle and cleanup passed")
