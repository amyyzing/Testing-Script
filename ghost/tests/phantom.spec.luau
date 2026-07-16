local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createSevenPair = require("../filter/7-pair")
local Phantom = require("../ghosts/Phantom")

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
		Fire = function(_, ...)
			for _, callback in ipairs(table.clone(callbacks)) do callback(...) end
		end,
	}
end

local function run(visibleSpeeds, invisibleSpeeds)
	local visibility = signal()
	local function speed(value, index)
		return type(value) == "table" and value[index] or value
	end
	local Humanoid = {WalkSpeed = speed(visibleSpeeds, 1)}
	local Ghost = {Transparency = 0}
	function Ghost:GetAttribute(name)
		return name == "Transparency" and self.Transparency or nil
	end
	function Ghost:GetAttributeChangedSignal() return visibility end
	function Ghost:FindFirstChildOfClass() return Humanoid end
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local phantom = Phantom.new({Traffic = Traffic})
	local sevenPair = createSevenPair({
		Traffic = Traffic,
		Ghost = Ghost,
		Humanoid = Humanoid,
		Delay = function(_, callback) callback() end,
	})
	local function transition(value, visible)
		Humanoid.WalkSpeed = value
		Ghost.Transparency = visible and 0 or 1
		visibility:Fire()
	end
	Traffic("HuntingState", {Hunting = true}):SendTo("SevenPair")
	for index = 1, 7 do
		transition(speed(invisibleSpeeds, index), false)
		if index < 7 then transition(speed(visibleSpeeds, index + 1), true) end
	end

	local snapshot = Verdict:Snapshot()
	sevenPair:Destroy()
	phantom:Destroy()
	return snapshot
end

local arbitrarySnapshot = run(5, 9)
expect(arbitrarySnapshot.Selected[1] == 12,
	"any repeated alternating A / B pair should support Phantom regardless of speed")

local sameSnapshot = run(22, 22)
expect(table.find(sameSnapshot["ruled-out"], 12),
	"an A / A pattern should rule out Phantom")

local inconsistentSnapshot = run({5, 5, 6, 5, 5, 5, 5}, 9)
expect(table.find(inconsistentSnapshot["ruled-out"], 12),
	"a non-repeating seven-pair pattern should rule out Phantom")

print("phantom.spec: speed-independent alternating A / B pattern passed")
