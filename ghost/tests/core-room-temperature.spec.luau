local Events = require("../events")
local RoomTemperature = require("../trackers/dormant/room-temperature")({Events = Events})

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local now = 0
local currentRoom = "Library"
local roundStarted = false
local temperatures = {Library = 12, Hallway = 18}
local emitted = {}
local tracker = RoomTemperature.new()
tracker:Start({
	Clock = function() return now end,
	ReadCurrentRoom = function() return currentRoom end,
	ReadRoundStarted = function() return roundStarted end,
	ReadRoomTemperature = function(roomName) return temperatures[roomName] end,
	Emit = function(event) table.insert(emitted, event) end,
})

local function tick(delta)
	now = now + (delta or 0.25)
	tracker:OnEvent({Type = Events.Types.Tick, Time = now})
end

local function reset(roomName, temperature, started)
	tracker:Reset()
	table.clear(emitted)
	now = 0
	currentRoom = roomName
	roundStarted = started ~= false
	temperatures[roomName] = temperature
	tick(0)
end

local function cool(amount, count)
	for _ = 1, count do
		temperatures[currentRoom] = temperatures[currentRoom] - amount
		tick(0.25)
	end
end

local function settleResidence(enteredAt)
	while now - enteredAt < 5 - 1e-6 do
		tick(math.min(0.25, 5 - (now - enteredAt)))
	end
end

reset("Library", 20, false)
cool(0.2, 20)
expect(#emitted == 0 and tracker:Snapshot().RoundStarted == false,
	"all setup-phase temperature changes must be discarded before the exit door opens")
roundStarted = true
tick(0.25)
local openedAt = now
cool(0.059999, 7)
expect(#emitted == 0, "seven changes must still satisfy the five-second residence gate")
settleResidence(openedAt)
expect(#emitted == 1, "the first post-opening seven-change window should emit after five seconds")
local openedShadow = emitted[1].Payload
expect(openedShadow.AverageDecrease < 0.06 and openedShadow.Outcome == "Shadow",
	"a post-opening seven-change average below 0.06 must identify Shadow")

reset("Library", 12)
cool(0.059999, 3)
roundStarted = false
cool(0.059999, 4)
settleResidence(0)
expect(#emitted == 1 and tracker:Snapshot().RoundStarted == true,
	"the first open state must remain latched if the exit door closes again")
local shadow = emitted[1].Payload
expect(shadow.SampleCount == 7 and shadow.DecreaseCount == 7 and shadow.ResidenceSeconds >= 5,
	"a completed window must contain seven actual cooling changes after five seconds")
expect(#shadow.CoolingChanges == 7,
	"the payload must preserve the complete seven-change cooling set")
expect(shadow.AverageDecrease < 0.06 and shadow.AverageDecrease > 0.059,
	"the exact unrounded arithmetic average below 0.06 should be retained")

reset("Library", 15)
cool(0.059999, 3)
temperatures.Library = temperatures.Library + 0.4
tick(0.25)
tick(0.25)
tick(0.25)
cool(0.059999, 3)
expect(#emitted == 0, "six real decreases plus ignored readings must not complete a window")
cool(0.059999, 1)
expect(#emitted == 0, "the five-second residence gate remains required after seven changes")
settleResidence(0)
local ignored = emitted[1].Payload
expect(ignored.DecreaseCount == 7 and ignored.IgnoredIncreaseCount == 1,
	"the average set must exclude the temperature increase")
expect(ignored.IgnoredUnchangedCount >= 2 and ignored.AverageDecrease < 0.06,
	"unchanged readings must be ignored without diluting the average")

reset("Library", 10)
cool(0.059999, 3)
currentRoom = "Hallway"
temperatures.Hallway = 18
tick(0.25)
local hallwayEnteredAt = now
cool(0.059999, 6)
expect(#emitted == 0, "changing rooms must discard the previous room's cooling changes")
cool(0.059999, 1)
settleResidence(hallwayEnteredAt)
expect(#emitted == 1 and emitted[1].Payload.RoomName == "Hallway",
	"only the new room may complete its own seven-change window")

reset("Library", 20)
cool(0.07, 7)
settleResidence(0)
local middle = emitted[1].Payload
expect(middle.AverageDecrease > 0.06 and middle.AverageDecrease < 0.08,
	"the full 0.06-to-0.08 average must remain inconclusive")

reset("Library", 30)
cool(0.080001, 7)
settleResidence(0)
local firstHigh = emitted[1].Payload
expect(firstHigh.Outcome == "RuleOutCandidate" and firstHigh.RuleOutStreak == 1,
	"one seven-change normal-cooling window must only create a candidate")
cool(0.080001, 7)
expect(emitted[2].Payload.Outcome == "RuleOut" and emitted[2].Payload.RuleOutStreak == 2,
	"two consecutive seven-change averages above 0.08 must rule Shadow out")

reset("Library", 40)
cool(0.04, 6)
cool(0.33, 1)
settleResidence(0)
local abnormal = emitted[1].Payload
expect(abnormal.AverageDecrease > 0.08 and math.abs(abnormal.MaximumDecrease - 0.33) <= 1e-9,
	"an abnormal value must remain in the complete arithmetic average")
expect(abnormal.Outcome == "RuleOutCandidate" and tracker:Snapshot().Resolved == false,
	"one abnormal high-average window must not permanently rule Shadow out")
cool(0.04, 7)
expect(emitted[2].Payload.Outcome == "Shadow" and emitted[2].Payload.RuleOutStreak == 0,
	"a following Shadow window must reset the candidate and identify Shadow")

reset("Library", 50)
cool(0.080001, 7)
settleResidence(0)
cool(0.07, 7)
expect(emitted[2].Payload.Outcome == "Inconclusive" and emitted[2].Payload.RuleOutStreak == 0,
	"a middle-band second window must reset the rule-out streak")
cool(0.080001, 7)
expect(emitted[3].Payload.Outcome == "RuleOutCandidate" and emitted[3].Payload.RuleOutStreak == 1,
	"a high average after a reset must begin a new candidate streak")

reset("Library", 60)
cool(0.08, 7)
settleResidence(0)
expect(math.abs(emitted[1].Payload.AverageDecrease - 0.08) <= 1e-9
	and emitted[1].Payload.Outcome == "Inconclusive",
	"exactly 0.08 must remain inconclusive")

reset("Library", 70)
cool(0.06, 7)
settleResidence(0)
expect(math.abs(emitted[1].Payload.AverageDecrease - 0.06) <= 1e-9
	and emitted[1].Payload.Outcome == "Inconclusive",
	"exactly 0.06 must remain inconclusive")

print("core-room-temperature.spec: seven-change round-gated Shadow averages passed")
