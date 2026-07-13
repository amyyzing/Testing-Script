local Ravager = require("../Ravager")

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

local api = {
	Detections = {},
	RuleOuts = {},
	RefreshCount = 0,
}

function api:Detect(name, reason, confidence)
	if self.RuleOuts[name] ~= nil then
		return false
	end
	self.Detections[name] = {
		Reason = reason,
		Confidence = confidence,
	}
	return true
end

function api:ClearRuleOut(name)
	local changed = self.RuleOuts[name] ~= nil
	self.RuleOuts[name] = nil
	return changed
end

function api:Refresh()
	self.RefreshCount = self.RefreshCount + 1
end

local observer = Ravager.CreateObserver(api)

local function reset()
	table.clear(api.Detections)
	table.clear(api.RuleOuts)
	api.RefreshCount = 0
	observer:Reset({Ghost = "ghost"})
end

local function position(x, z)
	return {X = x, Y = 0, Z = z}
end

local function orbitFrame(step, options)
	options = options or {}
	local ghostX = options.GhostX or 0
	local count = options.Count or 3
	local objects = {}
	for item = 1, count do
		local angle = math.rad(
			step * (options.AngleStep or 12) + (item - 1) * 100
		)
		local radius = options.Radius or 5
		table.insert(objects, {
			ObjectId = "item-" .. tostring(item),
			AssemblyId = options.SharedAssembly
				and "shared-assembly"
				or "assembly-" .. tostring(item),
			Position = position(
				ghostX + math.cos(angle) * radius,
				math.sin(angle) * radius
			),
		})
	end
	observer:OnObjectMotionFrame({
		Time = (options.TimeOffset or 0) + step * 0.05,
		GhostId = options.GhostId or "ghost",
		GhostPosition = position(ghostX, 0),
		Hunting = options.Hunting ~= false,
		Suppressed = options.Suppressed == true,
		Objects = objects,
	})
end

local function runOrbit(options, firstStep, lastStep)
	for step = firstStep or 0, lastStep or 13 do
		orbitFrame(step, options)
	end
end

-- Two objects can never establish the multi-item vortex.
reset()
runOrbit({Count = 2})
expect(api.Detections.Ravager == nil, "two orbiting objects must not detect Ravager")
expect(api.RefreshCount == 0, "an incomplete vortex must not refresh findings")

-- Separate roots from one physical assembly still count as one item.
reset()
runOrbit({SharedAssembly = true})
expect(api.Detections.Ravager == nil, "one assembly must not be counted three times")

-- Radial movement is fast, but it is not an orbit.
reset()
for step = 0, 13 do
	local objects = {}
	for item = 1, 3 do
		table.insert(objects, {
			ObjectId = "radial-item-" .. tostring(item),
			AssemblyId = "radial-assembly-" .. tostring(item),
			Position = position(4 + step * 0.4, item * 0.01),
		})
	end
	observer:OnObjectMotionFrame({
		Time = step * 0.05,
		GhostId = "ghost",
		GhostPosition = position(0, 0),
		Hunting = true,
		Objects = objects,
	})
end
expect(api.Detections.Ravager == nil, "fast radial motion must not pass the orbit classifier")

-- A real half-second, same-direction vortex owns its detection and reason.
reset()
api.RuleOuts.Ravager = {Confidence = 20}
runOrbit()
local detection = api.Detections.Ravager
expect(detection ~= nil and detection.Confidence == 99, "three raw orbit tracks should detect Ravager")
expect(api.RuleOuts.Ravager == nil, "a qualified vortex should clear a stale Ravager rule-out")
expect(
	type(detection.Reason) == "string"
		and string.find(detection.Reason, "distinct items", 1, true) ~= nil,
	"the Ravager module should author its own observation reason"
)
expect(api.RefreshCount == 1, "a vortex should refresh exactly once per hunt")

-- Automation suppression clears the partial temporal window.
reset()
runOrbit({}, 0, 7)
orbitFrame(8, {Suppressed = true})
runOrbit({}, 9, 15)
expect(api.Detections.Ravager == nil, "suppression should prevent partial windows from joining")
runOrbit({}, 16, 23)
expect(api.Detections.Ravager ~= nil, "a fresh post-suppression half-second should still detect")

-- A large instantaneous ghost displacement invalidates motion around the old centre.
reset()
runOrbit({}, 0, 7)
orbitFrame(8, {GhostX = 10})
for step = 9, 15 do
	orbitFrame(step, {GhostX = 10})
end
expect(api.Detections.Ravager == nil, "a ghost teleport should reset the orbit window")

-- No observation is a safe rule-out because the vortex ability is probabilistic.
observer:OnObjectMotionFrame({
	Time = 1,
	GhostId = "ghost",
	Hunting = false,
	Objects = {},
})
expect(api.RuleOuts.Ravager == nil, "ending a hunt without a vortex must not rule out Ravager")

print("ghost/tests/ravager.spec.luau: all tests passed")
