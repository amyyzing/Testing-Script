local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createGhostRoom = require("../active-trackers/ghost-room")
local createRoundStarted = require("../discardable-trackers/round-started")
local createRoomTemperature = require("../dormant-trackers/room-temperature")
local Shadow = require("../ghosts/Shadow")

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

local function room(name, initial)
	local changed = signal()
	local value = initial
	local object = {Name = name, Parent = true}
	function object:GetAttribute(attribute)
		expect(attribute == "Temperature", "room-temperature should only read Temperature")
		return value
	end
	function object:GetAttributeChangedSignal(attribute)
		expect(attribute == "Temperature", "room-temperature should only watch Temperature")
		return changed
	end
	function object:SetTemperature(nextValue)
		value = nextValue
		changed:Fire()
	end
	return object
end

local function exitDoor(closed)
	local changed = signal()
	local object = {Name = "ExitDoor"}
	function object:GetAttribute(attribute)
		if attribute == "DoorClosed" then return closed end
		return nil
	end
	function object:GetAttributeChangedSignal(attribute)
		expect(attribute == "DoorClosed", "round-started should only watch DoorClosed")
		return changed
	end
	function object:SetClosed(value)
		closed = value
		changed:Fire()
	end
	return object
end

local function harness(initialRoom)
	local heartbeat = signal()
	local currentRoom = initialRoom
	local exits = {exitDoor(true), exitDoor(true)}
	local doors = {ChildAdded = signal()}
	function doors:GetChildren() return exits end
	local world = {ChildAdded = signal()}
	function world:FindFirstChild(name)
		if name == "Doors" then return doors end
	end
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local shadow = Shadow.new({Traffic = Traffic})
	local temperature = createRoomTemperature({Traffic = Traffic})
	local ghostRoom = createGhostRoom({
		Traffic = Traffic,
		Workspace = world,
		Ghost = {},
		RunService = {Heartbeat = heartbeat},
		Position = function() return 0 end,
		FindRoom = function() return currentRoom end,
	})
	local roundStarted = createRoundStarted({Traffic = Traffic, Workspace = world})
	return {
		Traffic = Traffic,
		Verdict = Verdict,
		Shadow = shadow,
		Temperature = temperature,
		GhostRoom = ghostRoom,
		RoundStarted = roundStarted,
		ExitDoors = exits,
		Heartbeat = heartbeat,
		SetRoom = function(value) currentRoom = value end,
	}
end

local shadowRoom = room("Library", 10)
local positive = harness(shadowRoom)
expect(positive.Temperature.Room == shadowRoom and not positive.Temperature.Active
	and positive.RoundStarted.Started == false,
	"room-temperature must remember the ghost room but stay dormant before an exit opens")
shadowRoom:SetTemperature(12)
expect(#positive.Temperature.Changes == 0,
	"pre-round temperature changes must not enter the Shadow sample array")
positive.ExitDoors[2]:SetClosed(false)
expect(positive.RoundStarted.Started == true and not positive.RoundStarted.Running
	and positive.Temperature.RoundStarted and positive.Temperature.Active,
	"opening any exit door should permanently start the round and activate room-temperature")
positive.ExitDoors[2]:SetClosed(true)
expect(positive.RoundStarted.Started and positive.Temperature.RoundStarted,
	"round-started must remain true after the exit door closes again")
shadowRoom:SetTemperature(12.3)
for index = 1, 7 do shadowRoom:SetTemperature(12.3 - index * 0.05) end
expect(#positive.Temperature.Changes == 7,
	"temperature increases should be ignored while seven cooling changes are retained")
expect(positive.Verdict.Selected[1] == 15 and positive.Verdict.Confidence[15] == 99,
	"seven cooling changes averaging below 0.08 should support Shadow")
positive.GhostRoom:Destroy()
positive.RoundStarted:Destroy()
positive.Temperature:Destroy()
positive.Shadow:Destroy()

local firstRoom = room("Classroom", 15)
local secondRoom = room("Hallway", 20)
local negative = harness(firstRoom)
negative.ExitDoors[1]:SetClosed(false)
for index = 1, 3 do firstRoom:SetTemperature(15 - index * 0.04) end
negative.SetRoom(secondRoom)
negative.Heartbeat:Fire(0.25)
expect(negative.Temperature.Room == secondRoom and #negative.Temperature.Changes == 0,
	"moving to a new ghost room should reset the previous room's temperature array")
for index = 1, 7 do secondRoom:SetTemperature(20 - index * 0.1) end
expect(table.find(negative.Verdict.RuledOut, 15),
	"seven cooling changes averaging above 0.08 should rule out Shadow")
expect(firstRoom:GetAttributeChangedSignal("Temperature"):Count() == 0,
	"room-temperature should disconnect from the room the ghost left")
negative.GhostRoom:Destroy()
negative.RoundStarted:Destroy()
negative.Temperature:Destroy()
negative.Shadow:Destroy()

print("shadow.spec: exit-door round gate and dormant temperature average passed")
