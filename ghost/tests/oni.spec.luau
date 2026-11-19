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

local function run(rawSpeed, visibilityMode, mapSize, known, hunts, energy)
	local visibility = signal()
	local Humanoid = {WalkSpeed = rawSpeed}
	local Ghost = {Transparency = 0}
	function Ghost:GetAttribute(name)
		return name == "Transparency" and self.Transparency or nil
	end
	function Ghost:GetAttributeChangedSignal(name)
		expect(name == "Transparency", "seven-pair should observe Workspace.Ghost Transparency")
		return visibility
	end
	function Ghost:FindFirstChild() return nil end
	function Ghost:FindFirstChildOfClass() return Humanoid end
	local Map = {MapSize = mapSize or "Medium"}
	function Map:GetAttribute(name) return name == "MapSize" and self.MapSize or nil end
	local World = {GetAttribute = function() return energy or 50 end}
	function World:FindFirstChild(name) return name == "Map" and Map or nil end

	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local oni = Oni.new({Traffic = Traffic})
	local speedFilter = createSpeedFilter({Traffic = Traffic, Workspace = World, ReadScale = function() return {Known = known == true, CustomMultiplier = known and 2 or nil} end})
	local sevenPair = createSevenPair({
		Traffic = Traffic,
		Ghost = Ghost,
		Humanoid = Humanoid,
		Delay = function(_, callback) callback() end,
	})
	local filtered
	Traffic:Receive("Oni", function(signalName, payload)
		if signalName == "SpeedFilterResult" then filtered = payload end
	end)

	local function sample(speed, visible)
		Humanoid.WalkSpeed = speed
		Ghost.Transparency = visible and 0 or 1
		visibility:Fire()
	end
	for hunt = 1, hunts or 1 do
	Traffic("HuntingState", {Hunting = false}):SendTo("SevenPair")
	Traffic("HuntingState", {Hunting = true}):SendTo("SevenPair")
	for index = 1, 7 do
		local speed = type(rawSpeed) == "table" and rawSpeed[index] or rawSpeed
		sample(speed, true)
		sample(speed, visibilityMode == "all-visible" or index == visibilityMode)
	end

	end
	local snapshot = Verdict:Snapshot()
	sevenPair:Destroy()
	speedFilter:Destroy()
	oni:Destroy()
	return snapshot, filtered
end

local unknown, inferred = run(28, nil, "Small")
expect(unknown.Confidence[11] == nil and inferred.BaseSpeed == 14,
 "an inferred scale must not confirm Oni")
local first = run(28, nil, "Small", true)
expect(first.Confidence[11] == 35, "one known-scale hunt is only weak support")
local repeated = run(28, nil, "Small", true, 2)
expect((repeated.Confidence[11] == 65 and repeated.SourceConfidence[11] == 95), "two stable hunts at substantial Energy corroborate Oni")
for size, speed in pairs({Medium=29.399999618530273,Large=30.799999237060547}) do
 local scaled=run(speed,nil,size,true,2)
 expect(scaled.SourceConfidence[11]==95 and scaled.Confidence[11]==65,
  "native map scaling must corroborate Oni without bypassing the Doppelganger cap")
 local ordinary=run(10.5*(size=="Medium" and 1.05 or 1.1)*2,nil,size,true,2)
 expect(table.find(ordinary["ruled-out"],11), "ordinary scaled speed must still exclude Oni")
end
local overlap = run(28, nil, "Small", true, 2, 0)
expect(overlap.Confidence[11] == 35, "zero Energy cannot separate Oni from Wretch")
local normal, normalFilter = run(21, nil, "Small", true, 2)
expect(table.find(normal["ruled-out"], 11) and normalFilter.BaseSpeed == 10.5,
 "two complete known-scale ordinary-speed hunts exclude Oni")
local visible, visibleFilter = run(28, "all-visible", "Small", true, 2)
expect(#visible.Selected == 0 and #visible["ruled-out"] == 0 and visibleFilter == nil,
 "one visibility state cannot complete the comparison")
print("oni.spec: known scale, separate hunts and Energy overlap passed")
