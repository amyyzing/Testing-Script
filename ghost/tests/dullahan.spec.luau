local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createSevenPair = require("../filter/7-pair")
local createSpeedFilter = require("../filter/speed-filter")
local Dullahan = require("../ghosts/Dullahan")

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
		Count = function() return #callbacks end,
	}
end

local visibility = signal()
local Humanoid = {WalkSpeed = 22}
local Ghost = {Transparency = nil}
function Ghost:GetAttribute() return self.Transparency end
function Ghost:GetAttributeChangedSignal(name)
	expect(name == "Transparency", "seven-pair should observe Workspace.Ghost Transparency")
	return visibility
end
function Ghost:FindFirstChild() return nil end
function Ghost:FindFirstChildOfClass() return Humanoid end

local Traffic = createTraffic()
local Verdict = createVerdict({Traffic = Traffic})
local dullahan = Dullahan.new({Traffic = Traffic})
local World = {}
function World:FindFirstChild() return nil end
local speedFilter = createSpeedFilter({Traffic = Traffic, Workspace = World})
local delayedStart
local filter = createSevenPair({
	Traffic = Traffic,
	Ghost = Ghost,
	Humanoid = Humanoid,
	Delay = function(seconds, callback)
		expect(seconds == 3, "seven-pair should wait three seconds after hunt start")
		delayedStart = callback
	end,
})
local lastResult
local displayedSamples = {}
Traffic:Receive("Dullahan", function(signalName, payload)
	if signalName == "SpeedFilterResult" then lastResult = payload end
end)
Traffic:Receive("SpeedArrayLog", function(signalName, payload)
	if signalName == "HuntSpeedSample" then table.insert(displayedSamples, payload) end
end)

local function sample(speed, visible)
	Humanoid.WalkSpeed = speed
	Ghost.Transparency = not visible
	visibility:Fire()
end

local function sendPair(visible, invisible)
	sample(visible, true)
	sample(invisible, false)
end

local function beginDelayedSampling()
	local callback = delayedStart
	delayedStart = nil
	expect(type(callback) == "function", "hunt start should schedule seven-pair sampling")
	callback()
end

Traffic("HuntingState", {Hunting = true}):SendTo("SevenPair")
expect(visibility:Count() == 0, "seven-pair must not sample during its three-second start delay")
beginDelayedSampling()
expect(visibility:Count() == 1, "hunting should start one visibility sampler")
expect(filter.SampleCount == 0,
	"a missing Workspace.Ghost Transparency attribute must not become a false invisible sample")
for _ = 1, 7 do sendPair(22, 27) end
expect(lastResult and #lastResult.Pairs == 7 and lastResult.DistinctPairs == 1,
	"the repeated Phantom-style pair should remain one distinct pair")
expect(lastResult.Pairs[1].MixedVisibility == true,
	"a visible/invisible pair should preserve its state structure for the speed filter")
expect(lastResult.Pairs[1].a.v == true and lastResult.Pairs[1].b.v == false,
	"each pair should retain both original speed and visibility samples")
expect(lastResult.Samples == 14 and filter.SampleCount == 14,
	"exactly fourteen visibility samples should form the seven pairs")
expect(#displayedSamples == 14 and displayedSamples[14].Index == 14,
	"the speed log should receive all fourteen visibility samples before completion")
expect(Verdict:Snapshot()["ruled-out"][1] == 4,
	"seven repeated visible/invisible pairs should rule out Dullahan")
expect(visibility:Count() == 0,
	"the sampler should disconnect immediately after exactly seven pairs")
for _ = 1, 10 do sample(30, true) end
expect(filter.SampleCount == 14, "no samples should be taken after the seventh pair")

Traffic("HuntingState", {Hunting = false}):SendTo("SevenPair")
Ghost.Transparency = nil
Traffic("HuntingState", {Hunting = true}):SendTo("SevenPair")
beginDelayedSampling()
Verdict:Reset()
lastResult = nil
sendPair(22, 22.3)
sendPair(24, 22) -- a decreasing pair still counts as a distinct pair
sendPair(22.9, 23.1)
for _ = 1, 4 do sendPair(22, 22.3) end
expect(lastResult and lastResult.DistinctPairs == 3,
	"seven visibility pairs should retain distinct speeds regardless of decreases")
expect(Verdict:Snapshot().Selected[1] == 4,
	"three distinct pairs should support Dullahan")

Traffic("HuntingState", {Hunting = false}):SendTo("SevenPair")
Ghost.Transparency = nil
Traffic("HuntingState", {Hunting = true}):SendTo("SevenPair")
beginDelayedSampling()
Verdict:Reset()
lastResult = nil
for _ = 1, 6 do sendPair(22, 22.3) end
Traffic("HuntingState", {Hunting = false}):SendTo("SevenPair")
expect(lastResult == nil and #Verdict:Snapshot().Selected == 0
	and #Verdict:Snapshot()["ruled-out"] == 0,
	"an incomplete set of seven pairs should not produce a verdict")
expect(visibility:Count() == 0, "hunt end should stop an incomplete sampler")

Traffic("HuntingState", {Hunting = true}):SendTo("SevenPair")
local cancelledStart = delayedStart
Traffic("HuntingState", {Hunting = false}):SendTo("SevenPair")
cancelledStart()
expect(visibility:Count() == 0,
	"a hunt ending during the three-second delay must cancel seven-pair sampling")

filter:Destroy()
speedFilter:Destroy()
dullahan:Destroy()
print("dullahan.spec: visibility-driven seven-pair Dullahan comparison passed")
