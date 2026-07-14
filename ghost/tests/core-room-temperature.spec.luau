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

tick(0)
for index = 1, 20 do
	if index == 6 then
		temperatures.Library = temperatures.Library + 0.4
	elseif index == 12 then
		temperatures.Library = temperatures.Library - 0.2
	else
		temperatures.Library = temperatures.Library - 0.04
	end
	tick(0.25)
end

expect(#emitted == 1, "a five-second same-room window should emit once")
local first = emitted[1].Payload
expect(first.RoomName == "Library" and first.SameRoom == true, "the window must retain the ghost's current room")
expect(first.SampleCount == 20 and first.ResidenceSeconds >= 5, "the window must require about 20 samples and five seconds")
expect(first.NormalDropObserved == true and first.MaxDecreaseStep + 1e-6 >= 0.2, "one 0.20-degree downward step should qualify")
expect(first.IncreasesIgnored == true, "temperature increases must be explicitly ignored")

tracker:Reset()
table.clear(emitted)
now = 0
currentRoom = "Library"
temperatures.Library = 10
tick(0)
for _ = 1, 10 do
	temperatures.Library = temperatures.Library - 0.03
	tick(0.25)
end
currentRoom = "Hallway"
temperatures.Hallway = 18
tick(0.25)
for _ = 1, 19 do
	temperatures.Hallway = temperatures.Hallway - 0.03
	tick(0.25)
end
expect(#emitted == 0, "changing rooms must discard the previous room's residence and samples")
temperatures.Hallway = temperatures.Hallway - 0.03
tick(0.25)
expect(#emitted == 1 and emitted[1].Payload.RoomName == "Hallway", "only the new room may complete its own five-second window")
expect(emitted[1].Payload.NormalDropObserved == false, "small drops alone must not rule Shadow out")

print("core-room-temperature.spec: room-scoped Shadow temperature sampling passed")
