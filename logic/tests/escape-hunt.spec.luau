local createEscapeHunt = require("../escape-hunt")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			return {Disconnect = function()
				local index = table.find(callbacks, callback)
				if index then table.remove(callbacks, index) end
			end}
		end,
		Fire = function(_)
			for _, callback in ipairs(callbacks) do callback() end
		end,
	}
end

local changed = signal()
local ghost = {Hunting = false}
function ghost:GetAttribute() return self.Hunting end
function ghost:GetAttributeChangedSignal() return changed end
function ghost:SetHunting(value)
	self.Hunting = value
	changed:Fire()
end

local root = {CFrame = "original"}
local character = {Parent = true, Pivot = "original", Root = root}
function character:FindFirstChild(name) return name == "HumanoidRootPart" and self.Root or nil end
function character:GetPivot() return self.Pivot end
function character:PivotTo(value) self.Pivot = value end
local player = {Character = character}
local escaped = 0
local endDuringTeleport = false
local controller = createEscapeHunt({
	Player = player,
	Ghost = ghost,
	TeleportToSafety = function()
		escaped += 1
		character.Pivot = "safe"
		if endDuringTeleport then ghost:SetHunting(false) end
		return true
	end,
})

controller:SetEnabled(true)
ghost:SetHunting(true)
expect(escaped == 1 and character.Pivot == "safe", "hunt start should escape once")
ghost:SetHunting(true)
expect(escaped == 1, "the same hunt must not escape twice")
ghost:SetHunting(false)
expect(character.Pivot == "original", "hunt end should restore the original pivot")

ghost:SetHunting(true)
controller:SetEnabled(false)
expect(character.Pivot == "original", "disabling during a hunt should restore immediately")

controller:SetEnabled(true)
endDuringTeleport = true
ghost:SetHunting(false)
ghost:SetHunting(true)
expect(character.Pivot == "original", "a hunt ending during teleport should restore after it returns")

controller:Destroy()
print("escape-hunt.spec: toggle, one-shot escape, and restoration passed")
