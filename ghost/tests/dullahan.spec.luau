local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createSevenPair = require("../filter/7-pair")
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

local heartbeat = signal()
local Humanoid = {WalkSpeed = 22}
local Model = {Transparency = 0}
function Model:GetAttribute() return self.Transparency end
local Ghost = {}
function Ghost:FindFirstChild() return nil end
function Ghost:FindFirstChildOfClass() return Humanoid end

local Traffic = createTraffic()
local Verdict = createVerdict({Traffic = Traffic})
local dullahan = Dullahan.new({Traffic = Traffic})
local filter = createSevenPair({
	Traffic = Traffic,
	Ghost = Ghost,
	GhostModel = Model,
	Humanoid = Humanoid,
	RunService = {Heartbeat = heartbeat},
	Interval = 0.1,
})
local lastResult
Traffic:Receive("Dullahan", function(signalName, payload)
	if signalName == "SevenPairResult" then lastResult = payload end
end)

local function sample(speed, visible)
	Humanoid.WalkSpeed = speed
	Model.Transparency = visible and 0 or 1
	heartbeat:Fire(0.1)
end

local function sendPair(visible, invisible)
	sample(visible, true)
	sample(invisible, false)
end

Traffic("HuntingState", {Hunting = true}):SendTo("SevenPair")
expect(heartbeat:Count() == 1, "hunting should start one paced sampler")
for _ = 1, 7 do sendPair(22, 27) end
expect(lastResult and #lastResult.Pairs == 7 and lastResult.DistinctPairs == 1,
	"the repeated Phantom-style pair should remain one distinct pair")
expect(lastResult.Pairs[1].MixedVisibility == true,
	"a visible/invisible pair should preserve its state structure for the speed filter")
expect(lastResult.Pairs[1].a.v == true and lastResult.Pairs[1].b.v == false,
	"each pair should retain both original speed and visibility samples")
expect(lastResult.Samples == 14 and filter.SampleCount == 14,
	"exactly fourteen paced samples should form the seven pairs")
expect(Verdict:Snapshot()["ruled-out"][1] == 4,
	"seven repeated visible/invisible pairs should rule out Dullahan")
expect(heartbeat:Count() == 0,
	"the sampler should disconnect immediately after exactly seven pairs")
for _ = 1, 10 do sample(30, true) end
expect(filter.SampleCount == 14, "no samples should be taken after the seventh pair")

Traffic("HuntingState", {Hunting = false}):SendTo("SevenPair")
Traffic("HuntingState", {Hunting = true}):SendTo("SevenPair")
Verdict:Reset()
lastResult = nil
sendPair(22, 22.3)
sample(24, true)
sample(22, true) -- same-visibility and decreasing still forms the second pair
sendPair(22.9, 23.1)
for _ = 1, 4 do sendPair(22, 22.3) end
expect(lastResult and lastResult.DistinctPairs == 3,
	"every two paced samples must form a pair regardless of visibility or decrease")
expect(Verdict:Snapshot().Selected[1] == 4,
	"three distinct pairs should support Dullahan")

Traffic("HuntingState", {Hunting = false}):SendTo("SevenPair")
Traffic("HuntingState", {Hunting = true}):SendTo("SevenPair")
Verdict:Reset()
lastResult = nil
for _ = 1, 6 do sendPair(22, 22.3) end
Traffic("HuntingState", {Hunting = false}):SendTo("SevenPair")
expect(lastResult == nil and #Verdict:Snapshot().Selected == 0
	and #Verdict:Snapshot()["ruled-out"] == 0,
	"an incomplete set of seven pairs should not produce a verdict")
expect(heartbeat:Count() == 0, "hunt end should stop an incomplete sampler")

filter:Destroy()
dullahan:Destroy()
print("dullahan.spec: paced seven-pair Dullahan comparison passed")
