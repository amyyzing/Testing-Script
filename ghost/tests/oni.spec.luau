local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createSevenPair = require("../filter/7-pair")
local createSpeedFilter = require("../filter/speed-filter")
local Oni = require("../ghosts/Oni")

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

local function run(rawSpeed, sameVisibilityPair)
	local heartbeat = signal()
	local Humanoid = {WalkSpeed = rawSpeed}
	local Model = {Transparency = 0}
	function Model:GetAttribute() return self.Transparency end
	local Ghost = {}
	function Ghost:FindFirstChild() return nil end
	function Ghost:FindFirstChildOfClass() return Humanoid end
	local Map = {MapSize = "Medium"}
	function Map:GetAttribute(name) return name == "MapSize" and self.MapSize or nil end
	local World = {}
	function World:FindFirstChild(name) return name == "Map" and Map or nil end

	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local oni = Oni.new({Traffic = Traffic})
	local speedFilter = createSpeedFilter({Traffic = Traffic, Workspace = World})
	local sevenPair = createSevenPair({
		Traffic = Traffic,
		Ghost = Ghost,
		GhostModel = Model,
		Humanoid = Humanoid,
		RunService = {Heartbeat = heartbeat},
		Interval = 0.1,
	})
	local filtered
	Traffic:Receive("Oni", function(signalName, payload)
		if signalName == "SpeedFilterResult" then filtered = payload end
	end)

	local function sample(speed, visible)
		Humanoid.WalkSpeed = speed
		Model.Transparency = visible and 0 or 1
		heartbeat:Fire(0.1)
	end
	Traffic("HuntingState", {Hunting = true}):SendTo("SevenPair")
	for index = 1, 7 do
		local speed = type(rawSpeed) == "table" and rawSpeed[index] or rawSpeed
		sample(speed, true)
		sample(speed, index == sameVisibilityPair)
	end

	local snapshot = Verdict:Snapshot()
	sevenPair:Destroy()
	speedFilter:Destroy()
	oni:Destroy()
	return snapshot, filtered
end

local oniSnapshot, oniFilter = run(13.5 * 1.05 * 2)
expect(oniSnapshot.Selected[1] == 11 and oniFilter.Identical
	and oniFilter.BaseSpeed == 13.5 and oniFilter.CustomMultiplier == 2
	and oniFilter.MapMultiplier == 1.05,
	"seven identical 13.5-base visible/invisible pairs should support Oni after scaling")

local normalSnapshot, normalFilter = run(11 * 1.05 * 2)
expect(table.find(normalSnapshot["ruled-out"], 11) and normalFilter.BaseSpeed == 11,
	"seven identical normal 11-base hunting pairs should rule out Oni")

local stateSnapshot, stateFilter = run(13.5 * 1.05, 4)
expect(table.find(stateSnapshot["ruled-out"], 11) and stateFilter.Identical == false,
	"a pair without both visibility states should rule out Oni")

local invalidSnapshot, invalidFilter = run(13.5 * 1.05 * 1.75)
expect(table.find(invalidSnapshot["ruled-out"], 11) and invalidFilter.BaseSpeed == nil,
	"the unsupported 175 percent custom speed must not pass the speed filter")

print("oni.spec: seven-pair map and custom-speed filtering passed")
