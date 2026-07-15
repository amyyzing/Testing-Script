local Events = require("../events")
local Specification = require("../specification")
local ObjectTeleport = require("../trackers/dormant/object-teleport")({
	Events = Events,
	Specification = Specification,
})
local VortexOrbit = require("../trackers/dormant/vortex-orbit")({
	Events = Events,
	Specification = Specification,
})

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local object = {_listeners = {}}
	function object:Connect(callback)
		local connection = {Connected = true}
		function connection:Disconnect() self.Connected = false end
		table.insert(self._listeners, {Callback = callback, Connection = connection})
		return connection
	end
	function object:Fire(...)
		for _, listener in ipairs(self._listeners) do
			if listener.Connection.Connected then listener.Callback(...) end
		end
	end
	return object
end

local function point(x, y, z)
	return {X = x, Y = y or 0, Z = z or 0}
end

local function root(name)
	return {
		Name = name,
		Parent = {},
		IsA = function(_, className) return className == "Model" end,
	}
end

local function countType(events, kind)
	local count = 0
	for _, event in ipairs(events) do
		if event.Type == kind then count = count + 1 end
	end
	return count
end

local function lastType(events, kind)
	for index = #events, 1, -1 do
		if events[index].Type == kind then return events[index] end
	end
	return nil
end

local function newTeleportHarness(workspace, readRoomAtPosition)
	local now = 0
	local object = root("MovableItem")
	local positions = {[object] = point(0, 0, 0)}
	local emitted = {}
	local suppressed = false
	local tracker = ObjectTeleport.new()
	tracker:Start({
		Workspace = workspace,
		Clock = function() return now end,
		ReadTeleportObjects = function() return {object} end,
		ReadObjectPosition = function(candidate) return positions[candidate] end,
		ReadRoomAtPosition = readRoomAtPosition or function(position)
			return position.X < 25 and "RoomA" or "RoomB"
		end,
		IsObjectTeleportSuppressed = function() return suppressed end,
		Emit = function(event) table.insert(emitted, event) end,
	})
	return {
		Tracker = tracker,
		Object = object,
		Positions = positions,
		Events = emitted,
		SetNow = function(value) now = value end,
		SetSuppressed = function(value) suppressed = value end,
	}
end

-- Entity teleports are confirmed by the motion itself, not by crossing a room
-- boundary. Room names remain metadata for diagnostics when both are known.
do
	local smoke = {Name = "SmokeHolder"}
	local workspace = {
		FindFirstChild = function(_, name, recursive)
			return name == "SmokeHolder" and recursive == true and smoke or nil
		end,
	}
	local harness = newTeleportHarness(workspace, function() return "RoomA" end)
	harness.Positions[harness.Object] = point(40, 0, 0)
	harness.SetNow(0.4)
	harness.Tracker:OnEvent({Type = "ObjectTeleportSample", Time = 0.4})
	local result = lastType(harness.Events, Events.Types.ObjectTeleportResult)
	expect(result and result.Payload.ConfirmedTeleport == true
		and result.Payload.SmokeFound == true
		and result.Payload.FromRoom == "RoomA"
		and result.Payload.ToRoom == "RoomA",
		"a confirmed same-room object teleport must qualify while preserving room metadata")
	harness.Tracker:Destroy()
end

-- An already-replicated SmokeHolder is still "anywhere in Workspace" and
-- must not depend on this tracker observing its DescendantAdded edge.
do
	local smoke = {Name = "SmokeHolder"}
	local workspace = {
		FindFirstChild = function(_, name, recursive)
			return name == "SmokeHolder" and recursive == true and smoke or nil
		end,
	}
	local harness = newTeleportHarness(workspace)
	harness.Positions[harness.Object] = point(40, 0, 0)
	harness.SetNow(0.4)
	harness.Tracker:OnEvent({Type = "ObjectTeleportSample", Time = 0.4})
	local result = lastType(harness.Events, Events.Types.ObjectTeleportResult)
	expect(result and result.Payload.SmokeFound == true
		and result.Payload.SmokeHolder == smoke,
		"an existing recursive Workspace SmokeHolder must qualify the teleport immediately")
	harness.Tracker:Destroy()
end

-- A qualifying cross-room jump and a newly appearing SmokeHolder anywhere in
-- Workspace form one Entity episode. The same object may form later episodes.
do
	local harness = newTeleportHarness()
	harness.Positions[harness.Object] = point(40, 0, 0)
	harness.SetNow(0.4)
	harness.Tracker:OnEvent({Type = "ObjectTeleportSample", Time = 0.4})
	expect(harness.Tracker:Snapshot().PendingCount == 1,
		">=25 studs, >=80 studs/s, and <=0.65s must arm one teleport")
	local smoke = {Name = "SmokeHolder"}
	harness.SetNow(0.5)
	harness.Tracker:OnEvent({Type = "SmokeHolderAdded", Object = smoke, Time = 0.5})
	local result = lastType(harness.Events, Events.Types.ObjectTeleportResult)
	expect(result ~= nil and result.Payload.SmokeFound == true
		and result.Payload.ConfirmedTeleport == true
		and result.Payload.Completed == true,
		"a SmokeHolder appearing anywhere inside the correlation window must confirm Entity")
	expect(type(result.Payload.EventId) == "string"
		and result.Payload.EventId ~= "",
		"each teleport observation must own a stable episode EventId")
	harness.Tracker:Destroy()
end

-- Stop followed by Start must rebuild the container listeners for both motion
-- collectors; otherwise objects added after a pause silently disappear.
do
	local container = {
		Name = "Items",
		ChildAdded = signal(),
		ChildRemoved = signal(),
		Children = {},
	}
	function container:GetChildren() return self.Children end
	local candidate = root("AddedAfterRestart")
	local positions = {[candidate] = point(0, 0, 0)}
	local objectTracker = ObjectTeleport.new()
	local objectContext = {
		ObjectTeleportContainers = {container},
		ReadObjectPosition = function(object) return positions[object] end,
		ReadRoomAtPosition = function() return "RoomA" end,
	}
	objectTracker:Start(objectContext)
	objectTracker:Stop()
	objectTracker:Start(objectContext)
	table.insert(container.Children, candidate)
	container.ChildAdded:Fire(candidate)
	expect(objectTracker:Snapshot().ObjectCount == 1,
		"ObjectTeleport Start-after-Stop must reconnect ChildAdded and baseline the new object")
	objectTracker:Destroy()

	container.Children = {}
	local vortexTracker = VortexOrbit.new()
	local vortexContext = {
		VortexContainers = {container},
		ReadHunting = function() return false end,
	}
	vortexTracker:Start(vortexContext)
	vortexTracker:Stop()
	vortexTracker:Start(vortexContext)
	table.insert(container.Children, candidate)
	container.ChildAdded:Fire(candidate)
	expect(vortexTracker:Snapshot().ObjectCount == 1,
		"VortexOrbit Start-after-Stop must reconnect ChildAdded for new roots")
	vortexTracker:Destroy()
end

-- The same qualified teleport without SmokeHolder cannot resolve before the
-- complete 1.8-second SmokeHolder correlation window has elapsed.
do
	local harness = newTeleportHarness()
	harness.Positions[harness.Object] = point(40, 0, 0)
	harness.SetNow(0.4)
	harness.Tracker:OnEvent({Type = "ObjectTeleportSample", Time = 0.4})
	harness.SetNow(1.8)
	harness.Tracker:OnEvent({Type = Events.Types.Tick, Time = 1.8})
	expect(lastType(harness.Events, Events.Types.ObjectTeleportResult) == nil,
		"a no-smoke Entity result must remain pending through the correlation window")
	harness.SetNow(2.2)
	harness.Tracker:OnEvent({Type = Events.Types.Tick, Time = 2.2})
	local result = lastType(harness.Events, Events.Types.ObjectTeleportResult)
	expect(result ~= nil and result.Payload.SmokeFound == false,
		"a completed 1.8-second smoke probe must emit the 50% Entity-negative result")
	harness.Tracker:Destroy()
end

-- Automation movement is rebaselined and can never become a teleport episode.
do
	local harness = newTeleportHarness()
	harness.SetSuppressed(true)
	harness.Positions[harness.Object] = point(40, 0, 0)
	harness.SetNow(0.4)
	harness.Tracker:OnEvent({Type = "ObjectTeleportSample", Time = 0.4})
	harness.SetSuppressed(false)
	harness.Positions[harness.Object] = point(0, 0, 0)
	harness.SetNow(0.8)
	harness.Tracker:OnEvent({Type = "ObjectTeleportSample", Time = 0.8})
	expect(harness.Tracker:Snapshot().PendingCount == 0
		and #harness.Events == 0,
		"automation placement and its first post-mutation frame must only rebaseline")
	harness.Tracker:Destroy()
end

local function newVortexHarness()
	local now = 0
	local hunting = false
	local ghostPosition = point(0, 0, 0)
	local roots = {root("Item1"), root("Item2"), root("Interactable1")}
	local positions = {}
	local assemblies = {}
	for _, object in ipairs(roots) do assemblies[object] = {} end
	local emitted = {}
	local tracker = VortexOrbit.new()
	tracker:Start({
		Clock = function() return now end,
		ReadHunting = function() return hunting end,
		ReadGhostPosition = function() return ghostPosition end,
		ReadVortexObjects = function() return roots end,
		ResolveVortexObject = function(object)
			return {Position = positions[object], Assembly = assemblies[object]}
		end,
		Emit = function(event) table.insert(emitted, event) end,
	})
	return {
		Tracker = tracker,
		Roots = roots,
		Positions = positions,
		Events = emitted,
		SetNow = function(value) now = value end,
		SetHunting = function(value) hunting = value end,
		SetGhost = function(value) ghostPosition = value end,
	}
end

-- Three distinct assemblies orbit a moving center in one direction. Subtracting
-- the current ghost position each sample is what keeps this qualified.
do
	local harness = newVortexHarness()
	for sample = 0, 7 do
		local time = 0.1 + sample * 0.1
		local center = point(sample * 0.5, 0, sample * 0.2)
		harness.SetNow(time)
		harness.SetGhost(center)
		local angle = math.rad(sample * 12)
		for index, object in ipairs(harness.Roots) do
			local radius = 8 + index
			harness.Positions[object] = point(
				center.X + math.cos(angle) * radius,
				0,
				center.Z + math.sin(angle) * radius
			)
		end
		harness.Tracker:OnEvent({
			Type = Events.Types.Tick,
			Hunting = false,
			Time = time,
		})
	end
	local result = lastType(harness.Events, Events.Types.VortexPattern)
	expect(result ~= nil and result.Payload.Qualified == true
		and result.Payload.DistinctObjects == 3,
		"three distinct same-direction assemblies must qualify one Ravager vortex")
	expect(result.Payload.Duration >= 0.5
		and result.Payload.Intervals >= 5
		and result.Payload.GoodShare >= 0.7
		and result.Payload.AccumulatedAngle >= 45,
		"the vortex collector must preserve all legacy duration/interval/geometry gates")
	expect(countType(harness.Events, Events.Types.VortexPattern) == 1,
		"one round must emit at most one VortexPattern")
	harness.Tracker:Destroy()
end

-- Ordinary straight radial motion is not an orbit even with three fast objects.
do
	local harness = newVortexHarness()
	for sample = 0, 7 do
		local time = 0.1 + sample * 0.1
		local center = point(0, 0, 0)
		harness.SetNow(time)
		harness.SetGhost(center)
		for index, object in ipairs(harness.Roots) do
			harness.Positions[object] = point(5 + index + sample, 0, 0)
		end
		harness.Tracker:OnEvent({
			Type = Events.Types.Tick,
			Hunting = false,
			Time = time,
		})
	end
	expect(countType(harness.Events, Events.Types.VortexPattern) == 0,
		"three straight-line throws must not be mistaken for a Ravager vortex")
	harness.Tracker:Destroy()
end

print("core-object-motion-trackers.spec: Entity and Ravager lifecycle collectors passed")
