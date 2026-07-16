local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createSevenPair = require("../filter/7-pair")
local createSpeedFilter = require("../filter/speed-filter")
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

local function run(visibleSpeeds, invisibleSpeeds, mapSize)
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
	local Map = {MapSize = mapSize or "Small"}
	function Map:GetAttribute(name) return name == "MapSize" and self.MapSize or nil end
	local World = {}
	function World:FindFirstChild(name) return name == "Map" and Map or nil end

	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local phantom = Phantom.new({Traffic = Traffic})
	local speedFilter = createSpeedFilter({Traffic = Traffic, Workspace = World})
	local sevenPair = createSevenPair({
		Traffic = Traffic,
		Ghost = Ghost,
		Humanoid = Humanoid,
	})
	local filtered
	Traffic:Receive("Phantom", function(signalName, payload)
		if signalName == "SpeedFilterResult" then filtered = payload end
	end)

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
	speedFilter:Destroy()
	phantom:Destroy()
	return snapshot, filtered
end

local scaledSnapshot, scaledFilter = run(11 * 1.05 * 2, 13.5 * 1.05 * 2, "Medium")
expect(scaledSnapshot.Selected[1] == 12 and scaledFilter.PhantomPattern
	and scaledFilter.PhantomCustomMultiplier == 2,
	"repeated scaled visible 11 / invisible 13.5 pairs should support Phantom")

local sameSnapshot, sameFilter = run(22, 22, "Small")
expect(table.find(sameSnapshot["ruled-out"], 12) and sameFilter.PhantomPattern == false,
	"equal visible and invisible speeds should rule out Phantom")

local inconsistentSnapshot = run({11, 11, 12, 11, 11, 11, 11}, 13.5, "Small")
expect(table.find(inconsistentSnapshot["ruled-out"], 12),
	"a non-repeating seven-pair pattern should rule out Phantom")

print("phantom.spec: repeated visible/invisible seven-pair pattern passed")
