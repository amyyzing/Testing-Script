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

local function cool(amount, count)
	for _ = 1, count do
		temperatures[currentRoom] = temperatures[currentRoom] - amount
		tick(0.25)
	end
end

reset("Library", 12)
cool(0.049999, 20)
expect(#emitted == 1, "20 actual cooling changes over five seconds should complete one window")
local shadow = emitted[1].Payload
expect(shadow.RoomName == "Library" and shadow.SameRoom == true,
	"the window must retain the ghost's current room")
expect(shadow.SampleCount == 20 and shadow.DecreaseCount == 20 and shadow.ResidenceSeconds >= 5,
	"a completed window must contain 20 actual cooling changes after five seconds")
expect(#shadow.CoolingChanges == 20 and shadow.ReadingCount == 21,
	"the payload must preserve the complete cooling set and baseline reading")
expect(shadow.AverageDecrease < 0.05 and shadow.AverageDecrease > 0.049,
	"the exact unrounded arithmetic average below 0.05 should be retained")
expect(shadow.ShadowPatternObserved == true and shadow.RuleOutPatternObserved == false,
	"an exact full-window average below 0.05 must identify Shadow")
expect(shadow.Outcome == "Shadow" and tracker:Snapshot().Resolved == true,
	"the tracker should resolve only after its full cooling window")

reset("Library", 15)
cool(0.049999, 10)
temperatures.Library = temperatures.Library + 0.4
tick(0.25)
tick(0.25)
tick(0.25)
expect(#emitted == 0, "increases and unchanged readings must not count toward the 20-change window")
cool(0.049999, 9)
expect(#emitted == 0, "19 actual cooling changes must not complete a window")
cool(0.049999, 1)
expect(#emitted == 1, "the twentieth actual cooling change must complete the window")
local ignored = emitted[1].Payload
expect(ignored.DecreaseCount == 20 and ignored.IgnoredIncreaseCount == 1,
	"the average set must exclude the temperature increase")
expect(ignored.IgnoredUnchangedCount == 2 and ignored.AverageDecrease < 0.05,
	"unchanged readings must be counted as ignored without diluting the average")

reset("Library", 10)
cool(0.049999, 10)
currentRoom = "Hallway"
temperatures.Hallway = 18
tick(0.25)
cool(0.049999, 19)
expect(#emitted == 0, "changing rooms must discard the previous room's cooling changes")
cool(0.049999, 1)
expect(#emitted == 1 and emitted[1].Payload.RoomName == "Hallway",
	"only the new room may complete its own 20-change window")

reset("Library", 20)
cool(0.055, 20)
local middle = emitted[1].Payload
expect(middle.AverageDecrease > 0.05 and middle.AverageDecrease < 0.06,
	"the full 0.05-to-0.06 average must be preserved without truncation")
expect(middle.Outcome == "Inconclusive" and tracker:Snapshot().Resolved == false,
	"a middle-band window must remain inconclusive and continue monitoring")

reset("Library", 30)
cool(0.060001, 20)
local firstHigh = emitted[1].Payload
expect(firstHigh.Outcome == "RuleOutCandidate" and firstHigh.RuleOutStreak == 1,
	"one high-average window must only create a rule-out candidate")
expect(firstHigh.RuleOutPatternObserved == false and tracker:Snapshot().Resolved == false,
	"the first high window must not permanently rule Shadow out")
cool(0.060001, 20)
local secondHigh = emitted[2].Payload
expect(secondHigh.Outcome == "RuleOut" and secondHigh.RuleOutStreak == 2,
	"two consecutive independent high-average windows must rule Shadow out")
expect(secondHigh.RuleOutPatternObserved == true and tracker:Snapshot().Resolved == true,
	"the confirmed two-window rule-out should resolve the tracker")

reset("Library", 40)
cool(0.04, 19)
cool(0.5, 1)
local abnormal = emitted[1].Payload
expect(abnormal.AverageDecrease > 0.06 and abnormal.MaximumDecrease == 0.5,
	"an abnormal value must remain in the complete arithmetic average")
expect(abnormal.Outcome == "RuleOutCandidate" and tracker:Snapshot().Resolved == false,
	"one abnormal high-average window must not permanently rule Shadow out")
cool(0.04, 20)
expect(emitted[2].Payload.Outcome == "Shadow" and emitted[2].Payload.RuleOutStreak == 0,
	"a following Shadow window must reset the candidate and identify Shadow")

reset("Library", 50)
cool(0.060001, 20)
cool(0.055, 20)
expect(emitted[2].Payload.Outcome == "Inconclusive" and emitted[2].Payload.RuleOutStreak == 0,
	"a non-high second window must reset the rule-out streak")
cool(0.060001, 20)
expect(emitted[3].Payload.Outcome == "RuleOutCandidate" and emitted[3].Payload.RuleOutStreak == 1,
	"a high average after a reset must begin a new candidate streak")

reset("Library", 60)
cool(0.06, 20)
expect(math.abs(emitted[1].Payload.AverageDecrease - 0.06) <= 1e-9,
	"the exact 0.06 boundary should be preserved")
expect(emitted[1].Payload.Outcome == "Inconclusive",
	"exactly 0.06 must remain inconclusive")

reset("Library", 70)
cool(0.05, 20)
expect(math.abs(emitted[1].Payload.AverageDecrease - 0.05) <= 1e-9,
	"the exact 0.05 boundary should be preserved")
expect(emitted[1].Payload.Outcome == "Inconclusive",
	"exactly 0.05 must remain inconclusive")

print("core-room-temperature.spec: full-window Shadow averages passed")
