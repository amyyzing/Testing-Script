local createTeleportation = require("../teleportation")

local function expect(condition, message)
	if not condition then
		error(message, 2)
	end
end

local function position(x, z)
	return {X = x, Y = 0, Z = z}
end

local function boundingPart(centerX, centerZ, sizeX, sizeZ, parent)
	local frame = {}
	function frame:PointToObjectSpace(worldPosition)
		return {
			X = worldPosition.X - centerX,
			Y = worldPosition.Y,
			Z = worldPosition.Z - centerZ,
		}
	end
	return {
		Parent = parent == nil and true or parent,
		CFrame = frame,
		Size = {X = sizeX, Y = 8, Z = sizeZ},
	}
end

local function pointIsInsidePart(part, worldPosition)
	local localPosition = part.CFrame:PointToObjectSpace(worldPosition)
	return math.abs(localPosition.X) <= part.Size.X * 0.5
		and math.abs(localPosition.Z) <= part.Size.Z * 0.5
end

local runtimeActive = true
local rooms = {}
local boundsByRoom = {}
local roomsFolder = {}
function roomsFolder:GetChildren()
	return rooms
end

local Teleportation = createTeleportation({
	Services = {
		RunService = {
			Heartbeat = {
				Wait = function()
					error("a pure teleportation test unexpectedly waited for Heartbeat")
				end,
			},
		},
	},
	Player = {Character = nil},
	RuntimeIsActive = function()
		return runtimeActive
	end,
	FindRoomsFolder = function()
		return roomsFolder
	end,
	GetInstanceWorldPosition = function(target)
		return target and target.Position or nil
	end,
	GetRoomBoundingParts = function(room)
		return boundsByRoom[room] or {}
	end,
	PointIsInsidePart = pointIsInsidePart,
})

local overlapRoom = {Name = "Overlap"}
local coverageRoom = {Name = "Coverage"}
rooms = {overlapRoom, coverageRoom}
boundsByRoom[overlapRoom] = {
	boundingPart(0, 0, 4, 4),
	boundingPart(0, 0, 4, 4),
	boundingPart(0, 0, 4, 4),
}
boundsByRoom[coverageRoom] = {
	boundingPart(5, 0, 14, 4),
}
local selected = Teleportation.FindRoomForTarget(nil, {
	position(0, 0),
	position(10, 0),
})
expect(
	selected == coverageRoom,
	"overlapping bounds must count a preferred point only once per room"
)

local emptyRoom = {Name = "Empty"}
local invalidRoom = {Name = "Invalid"}
rooms = {emptyRoom, invalidRoom}
boundsByRoom[emptyRoom] = {}
boundsByRoom[invalidRoom] = {
	boundingPart(0, 0, 4, 4, false),
}
expect(
	Teleportation.FindRoomForTarget({Position = position(0, 0)}) == nil,
	"rooms without a live valid bounding part must never be returned"
)

local validRoom = {Name = "Valid"}
rooms = {validRoom}
boundsByRoom[validRoom] = {boundingPart(0, 0, 4, 4)}
expect(
	Teleportation.FindRoomForTarget(nil) == nil,
	"a valid bound without a target or preferred position is not finite evidence"
)

local farRoom = {Name = "Far"}
local nearRoom = {Name = "Near"}
rooms = {emptyRoom, farRoom, nearRoom}
boundsByRoom[farRoom] = {boundingPart(0, 0, 4, 4)}
boundsByRoom[nearRoom] = {boundingPart(25, 0, 4, 4)}
expect(
	Teleportation.FindRoomForTarget({Position = position(30, 0)}) == nearRoom,
	"the nearest room with finite target evidence should be selected"
)

local options = {}
runtimeActive = true
local success, reason = Teleportation.RunExclusive(options, function()
	expect(options.IsActive(), "RunExclusive must install an active runtime guard")
	runtimeActive = false
	expect(
		not options.IsActive(),
		"the injected guard must observe runtime cancellation during the callback"
	)
	return true
end)
expect(success == false, "a callback finishing after runtime cancellation must fail")
expect(reason == "movement request was cancelled", "cancellation reason should be stable")
expect(options.IsActive == nil, "RunExclusive must restore the caller's options table")

local requestActive = true
local function callerActivityGuard()
	return requestActive
end
local guardedOptions = {IsActive = callerActivityGuard}
runtimeActive = true
success, reason = Teleportation.RunExclusive(guardedOptions, function()
	expect(
		guardedOptions.IsActive ~= callerActivityGuard,
		"RunExclusive should combine rather than replace the caller's guard semantics"
	)
	requestActive = false
	expect(
		not guardedOptions.IsActive(),
		"the combined guard must preserve caller-request cancellation"
	)
	return true
end)
expect(success == false, "caller-request cancellation must fail the movement request")
expect(reason == "movement request was cancelled", "caller cancellation reason should be stable")
expect(
	guardedOptions.IsActive == callerActivityGuard,
	"RunExclusive must restore the original caller activity guard"
)

runtimeActive = true
local lease = Teleportation.Acquire({})
expect(lease ~= nil and lease:IsActive(), "an acquired movement lease should be active")
runtimeActive = false
expect(not lease:IsActive(), "a movement lease must expose runtime cancellation")
lease:Release()

print("teleportation.spec: room selection and cancellation assertions passed")
