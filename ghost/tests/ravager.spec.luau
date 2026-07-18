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
	local part = {
		Parent = object,
		Position = object.Current,
		Anchored = false,
		Transparency = 0,
	}
	function part:IsA(class) return class == "BasePart" end
	part.AssemblyRootPart = part
	object.PrimaryPart = part
	object.Part = part
	function object:GetDescendants() return {part} end
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
		object.Part.Position = {
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
		object.Part.Position = {
			X = math.cos(angle) * radius,
			Y = index,
			Z = math.sin(angle) * radius,
		}
	end
	now += 0.1
	heartbeat:Fire(0.1)
end

local function flyPast(step)
	Ghost.Current = {X = 0, Y = 0, Z = 0}
	for index, object in ipairs(objects) do
		object.Part.Position = {
			X = -14 + step * 2,
			Y = index * 4,
			Z = 3 + index,
		}
	end
	now += 0.1
	heartbeat:Fire(0.1)
end

local function pause(samples)
	for _ = 1, samples do
		now += 0.1
		heartbeat:Fire(0.1)
	end
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

orbitEvent = nil
Traffic("HuntingState", {Hunting = true}):SendTo("ItemOrbit")
for step = 0, 14 do flyPast(step) end
expect(orbitEvent == nil,
	"three straight fly-pasts must not be mistaken for a Ravager vortex")
Traffic("HuntingState", {Hunting = false}):SendTo("ItemOrbit")

orbitEvent = nil
Traffic("HuntingState", {Hunting = true}):SendTo("ItemOrbit")
for degrees = 0, 84, 12 do orbit(degrees) end
expect(orbitEvent == nil,
	"three short curved paths must not satisfy the sustained XZ rotation threshold")
Traffic("HuntingState", {Hunting = false}):SendTo("ItemOrbit")

orbitEvent = nil
Traffic("HuntingState", {Hunting = true}):SendTo("ItemOrbit")
for degrees = 0, 144, 12 do orbit(degrees) end
expect(orbitEvent and orbitEvent.Count == 3,
	"three distinct models circling the ghost's moving center should emit one Ravager event")
expect(orbitEvent.Mode == "XZVortex", "Ravager must require the XZ vortex classifier")
expect(orbitEvent.Duration >= 1 and orbitEvent.Steps >= 8
	and orbitEvent.Rotation >= math.rad(120),
	"the duration, step, and signed XZ rotation gates must all pass")
expect(Verdict.Selected[1] == 13 and Verdict.Confidence[13] == 99,
	"the three-model orbit should support Ravager at 99%")

Traffic("HuntingState", {Hunting = false}):SendTo("ItemOrbit")
expect(heartbeat:Count() == 0, "hunt end should immediately disable orbit sampling")

orbitEvent = nil
Traffic("HuntingState", {Hunting = true}):SendTo("ItemOrbit")
for degrees = 144, 0, -12 do orbit(degrees) end
expect(orbitEvent and orbitEvent.Count == 3,
	"clockwise and counter-clockwise model orbits should both qualify")
Traffic("HuntingState", {Hunting = false}):SendTo("ItemOrbit")

orbitEvent = nil
Traffic("HuntingState", {Hunting = true}):SendTo("ItemOrbit")
for degrees = 0, 60, 12 do orbit(degrees) end
pause(5)
for degrees = 72, 144, 12 do orbit(degrees) end
expect(orbitEvent and orbitEvent.Mode == "XZVortex" and orbitEvent.Count == 3,
	"a short collision pause must not erase an otherwise sustained XZ vortex")
Traffic("HuntingState", {Hunting = false}):SendTo("ItemOrbit")

orbitEvent = nil
Traffic("HuntingState", {Hunting = true}):SendTo("ItemOrbit")
for degrees = 0, 60, 12 do orbit(degrees) end
pause(8)
for degrees = 72, 144, 12 do orbit(degrees) end
expect(orbitEvent == nil,
	"a long interruption must split two incomplete arcs into separate episodes")
Traffic("HuntingState", {Hunting = false}):SendTo("ItemOrbit")

tracker:Destroy()
ravager:Destroy()
print("ravager.spec: strict moving-center XZ vortex detection passed")
