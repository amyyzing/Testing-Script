local Events = require("../events")
local RoomTemperature = require("../trackers/dormant/room-temperature")({Events = Events})

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local now = 0
local currentRoom = "Library"
local temperatures = {Library = 12, Hallway = 18}
local emitted = {}
local tracker = RoomTemperature.new()
tracker:Start({
	Clock = function() return now end,
	ReadCurrentRoom = function() return currentRoom end,
	ReadRoomTemperature = function(roomName) return temperatures[roomName] end,
	Emit = function(event) table.insert(emitted, event) end,
})

local function tick(delta)
	now = now + (delta or 0.25)
	tracker:OnEvent({Type = Events.Types.Tick, Time = now})
end

local function reset(roomName, temperature)
	tracker:Reset()
	table.clear(emitted)
	now = 0
	currentRoom = roomName
	temperatures[roomName] = temperature
	tick(0)
end

reset("Library", 12)
for index = 1, 20 do
	if index == 6 then
		temperatures.Library = temperatures.Library + 0.4
	else
		temperatures.Library = temperatures.Library - 0.049999
	end
	tick(0.25)
end

expect(#emitted == 1, "a five-second same-room window should emit once")
local shadow = emitted[1].Payload
expect(shadow.RoomName == "Library" and shadow.SameRoom == true,
	"the window must retain the ghost's current room")
expect(shadow.SampleCount == 20 and shadow.ResidenceSeconds >= 5,
	"the window must require 20 samples and five seconds")
expect(shadow.AverageDecrease < 0.05 and shadow.AverageDecrease > 0.049,
	"the exact unrounded average below 0.05 should be retained")
expect(shadow.ShadowPatternObserved == true and shadow.RuleOutPatternObserved == false,
	"an exact strict-decrease average below 0.05 must identify Shadow")
expect(shadow.IgnoredIncreaseCount == 1 and shadow.IncreasesIgnored == true,
	"temperature increases must be excluded from the cooling average")
expect(shadow.Unrounded == true, "the event must explicitly retain unrounded statistics")

reset("Library", 10)
for _ = 1, 10 do
	temperatures.Library = temperatures.Library - 0.049999
	tick(0.25)
end
currentRoom = "Hallway"
temperatures.Hallway = 18
tick(0.25)
for _ = 1, 19 do
	temperatures.Hallway = temperatures.Hallway - 0.049999
	tick(0.25)
end
expect(#emitted == 0,
	"changing rooms must discard the previous room's residence and samples")
temperatures.Hallway = temperatures.Hallway - 0.049999
tick(0.25)
expect(#emitted == 1 and emitted[1].Payload.RoomName == "Hallway",
	"only the new room may complete its own five-second window")
expect(emitted[1].Payload.ShadowPatternObserved == true,
	"the new room's exact sub-0.05 average should identify Shadow")

reset("Library", 5.5)
local sparseDrops = {
	[5] = 0.072,
	[10] = 0.054,
	[15] = 0.053,
}
for index = 1, 20 do
	temperatures.Library = temperatures.Library - (sparseDrops[index] or 0)
	tick(0.25)
end
local sparse = emitted[1].Payload
local expectedSparseAverage = (0.072 + 0.054 + 0.053) / 3
expect(sparse.DecreaseCount == 3 and sparse.IgnoredUnchangedCount == 16,
	"only the three strict cooling pairs should enter the sparse-window average")
expect(math.abs(sparse.AverageDecrease - expectedSparseAverage) <= 1e-9,
	"unchanged pairs must not dilute 0.072, 0.054, and 0.053 below their true average")
expect(sparse.AverageDecrease > 0.059 and sparse.AverageDecrease < 0.06,
	"the reproduced three-pair average should remain about 0.059666 without truncation")
expect(sparse.ShadowPatternObserved == false
	and sparse.RuleOutPatternObserved == false,
	"the reproduced 0.05-to-0.06 average must remain inconclusive")

reset("Library", 30)
for _ = 1, 20 do
	temperatures.Library = temperatures.Library - 0.060001
	tick(0.25)
end
local normal = emitted[1].Payload
expect(normal.AverageDecrease > 0.06 and normal.AverageDecrease < 0.061,
	"the exact unrounded average above 0.06 should be retained")
expect(normal.MinimumDecrease + 1e-9 >= 0.05,
	"every normal-ghost cooling sample must satisfy the 0.05 minimum guard")
expect(normal.RuleOutPatternObserved == true and normal.ShadowPatternObserved == false,
	"an average above 0.06 with no sub-0.05 sample must rule Shadow out")

reset("Library", 40)
for index = 1, 20 do
	local decrease = index == 6 and 0.049999 or 0.07
	temperatures.Library = temperatures.Library - decrease
	tick(0.25)
end
local guarded = emitted[1].Payload
expect(guarded.AverageDecrease > 0.06 and guarded.MinimumDecrease < 0.05,
	"the guard window should preserve both its high average and exact small sample")
expect(guarded.RuleOutPatternObserved == false and guarded.ShadowPatternObserved == false,
	"one cooling sample below 0.05 must block a Shadow rule-out")

reset("Library", 50)
for _ = 1, 20 do
	temperatures.Library = temperatures.Library - 0.06
	tick(0.25)
end
local boundary = emitted[1].Payload
expect(math.abs(boundary.AverageDecrease - 0.06) <= 1e-9,
	"the exact 0.06 boundary should be preserved")
expect(boundary.ShadowPatternObserved == false
	and boundary.RuleOutPatternObserved == false,
	"exactly 0.06 must remain inconclusive")

reset("Library", 60)
for _ = 1, 20 do
	temperatures.Library = temperatures.Library - 0.05
	tick(0.25)
end
local shadowBoundary = emitted[1].Payload
expect(math.abs(shadowBoundary.AverageDecrease - 0.05) <= 1e-9,
	"the exact 0.05 boundary should be preserved")
expect(shadowBoundary.ShadowPatternObserved == false
	and shadowBoundary.RuleOutPatternObserved == false,
	"exactly 0.05 must remain inconclusive")

print("core-room-temperature.spec: exact strict-decrease Shadow averages passed")
