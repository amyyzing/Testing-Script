local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createItemOrbit = require("../dormant-trackers/item-orbit")
local Ravager = require("../ghosts/Ravager")

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

local function model(name)
	local object = {Name = name, Current = {X = 0, Y = 0, Z = 0}}
	function object:IsA(class) return class == "Model" end
	function object:GetPivot() return {Position = self.Current} end
	return object
end

local first, second, third = model("First"), model("Second"), model("Third")
local function container(children)
	local object = {ChildAdded = signal(), ChildRemoved = signal()}
	function object:GetChildren() return children end
	return object
end
local Items = container({first, second})
local Interactables = container({third})
local World = {ChildAdded = signal()}
function World:FindFirstChild(name)
	if name == "Items" then return Items end
	if name == "Interactables" then return Interactables end
end
local Ghost = model("Ghost")
local heartbeat = signal()
local now = 0
local Traffic = createTraffic()
local Verdict = createVerdict({Traffic = Traffic})
local ravager = Ravager.new({Traffic = Traffic})
local orbitEvent
Traffic:Receive("Ravager", function(signalName, payload)
	if signalName == "ItemOrbit" then orbitEvent = payload end
end)
local tracker = createItemOrbit({
	Traffic = Traffic,
	Workspace = World,
	Ghost = Ghost,
	RunService = {Heartbeat = heartbeat},
	Clock = function() return now end,
})

local objects = {first, second, third}
local phases = {0, 120, 240}
local function orbit(degrees)
	Ghost.Current = {X = degrees / 10, Y = 0, Z = -degrees / 20}
	for index, object in ipairs(objects) do
		local angle = math.rad(degrees + phases[index])
		object.Current = {
			X = Ghost.Current.X + math.cos(angle) * 10,
			Y = index,
			Z = Ghost.Current.Z + math.sin(angle) * 10,
		}
	end
	now += 0.1
	heartbeat:Fire(0.1)
end

local function radial(step)
	Ghost.Current = {X = 0, Y = 0, Z = 0}
	for index, object in ipairs(objects) do
		local angle = math.rad(phases[index])
		local radius = 8 + index + step
		object.Current = {
			X = math.cos(angle) * radius,
			Y = index,
			Z = math.sin(angle) * radius,
		}
	end
	now += 0.1
	heartbeat:Fire(0.1)
end

orbit(0)
orbit(30)
expect(orbitEvent == nil and heartbeat:Count() == 0,
	"the orbit tracker must remain disconnected while not hunting")

Traffic("HuntingState", {Hunting = true}):SendTo("ItemOrbit")
expect(heartbeat:Count() == 1, "hunting should enable exactly one orbit sampler")
for step = 0, 7 do radial(step) end
expect(orbitEvent == nil,
	"three straight radial movements must not be mistaken for a Ravager vortex")
Traffic("HuntingState", {Hunting = false}):SendTo("ItemOrbit")
Traffic("HuntingState", {Hunting = true}):SendTo("ItemOrbit")
for degrees = 0, 84, 12 do orbit(degrees) end
expect(orbitEvent and orbitEvent.Count == 3,
	"three distinct models maintaining an orbit should emit one Ravager event")
expect(orbitEvent.Duration >= 0.5 and orbitEvent.Intervals >= 5
	and orbitEvent.GoodShare >= 0.7 and orbitEvent.AccumulatedAngle >= 45,
	"the restored legacy duration, interval, geometry, and angle gates must all pass")
expect(Verdict.Selected[1] == 13 and Verdict.Confidence[13] == 99,
	"the three-model orbit should support Ravager at 99%")

Traffic("HuntingState", {Hunting = false}):SendTo("ItemOrbit")
expect(heartbeat:Count() == 0, "hunt end should immediately disable orbit sampling")

orbitEvent = nil
Traffic("HuntingState", {Hunting = true}):SendTo("ItemOrbit")
for degrees = 84, 0, -12 do orbit(degrees) end
expect(orbitEvent and orbitEvent.Count == 3,
	"clockwise and counter-clockwise model orbits should both qualify")
Traffic("HuntingState", {Hunting = false}):SendTo("ItemOrbit")

tracker:Destroy()
ravager:Destroy()
print("ravager.spec: hunting-only legacy vortex detection passed")
