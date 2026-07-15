return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "ObjectTeleport requires Events")
	local Specification = type(dependencies.Specification) == "table"
		and dependencies.Specification or {}
	local EntitySpec = type(Specification.Entity) == "table"
		and Specification.Entity or {}

	local ObjectTeleport = {}
	ObjectTeleport.__index = ObjectTeleport

	local CONTAINER_NAMES = {
		Items = true,
		Interactable = true,
		Interactables = true,
	}

	local function disconnect(connection)
		if connection and type(connection.Disconnect) == "function" then
			pcall(connection.Disconnect, connection)
		end
	end

	local function connect(signal, callback)
		if signal == nil then return nil end
		local ok, connection = pcall(function()
			return signal:Connect(callback)
		end)
		return ok and connection or nil
	end

	local function call(object, method, ...)
		local callback = object and object[method]
		if type(callback) ~= "function" then return nil end
		local ok, first, second, third = pcall(callback, object, ...)
		if not ok then return nil end
		return first, second, third
	end

	local function xyz(value)
		if type(value) == "number" then return value, 0, 0 end
		if value == nil then return nil end
		local ok, x, y, z = pcall(function()
			return value.X, value.Y, value.Z
		end)
		if not ok then return nil end
		x, y, z = tonumber(x), tonumber(y), tonumber(z)
		if x == nil or z == nil then return nil end
		return x, y or 0, z
	end

	local function distance(first, second)
		local ax, ay, az = xyz(first)
		local bx, by, bz = xyz(second)
		if ax == nil or bx == nil then return nil end
		local dx, dy, dz = ax - bx, ay - by, az - bz
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	local function isTrackable(object)
		return object ~= nil and (
			call(object, "IsA", "Model") == true
			or call(object, "IsA", "BasePart") == true
		)
	end

	function ObjectTeleport.new(options)
		options = type(options) == "table" and options or {}
		local smokeCorrelationWindow = tonumber(options.SmokeCorrelationWindow)
			or tonumber(EntitySpec.SmokeCorrelationWindow) or 1.8
		-- A negative Entity result cannot be finalized while a qualifying
		-- SmokeHolder could still arrive inside the correlation window.
		local resolveDelay = math.max(
			tonumber(options.ResolveDelay)
				or tonumber(EntitySpec.ResolveDelay) or 1.4,
			smokeCorrelationWindow
		)
		return setmetatable({
			Name = options.Name or "ObjectTeleport",
			Category = "Dormant",
			Status = "Idle",
			SampleInterval = tonumber(options.SampleInterval)
				or tonumber(EntitySpec.SampleInterval) or 0.4,
			MaximumElapsed = tonumber(options.MaximumElapsed)
				or tonumber(EntitySpec.MaximumElapsed) or 0.65,
			MinimumDisplacement = tonumber(options.MinimumDisplacement)
				or tonumber(EntitySpec.MinimumDisplacement) or 25,
			MinimumSpeed = tonumber(options.MinimumSpeed)
				or tonumber(EntitySpec.MinimumSpeed) or 80,
			ResolveDelay = resolveDelay,
			SmokeCorrelationWindow = smokeCorrelationWindow,
			SmokeRetention = tonumber(options.SmokeRetention)
				or tonumber(EntitySpec.SmokeRetention) or 3,
			_context = nil,
			_connections = {},
			_boundContainers = setmetatable({}, {__mode = "k"}),
			_objects = setmetatable({}, {__mode = "k"}),
			_previous = setmetatable({}, {__mode = "k"}),
			_pending = {},
			_pendingByObject = setmetatable({}, {__mode = "k"}),
			_recentSmoke = {},
			_mutationActive = false,
			_accumulator = 0,
			_lastTick = nil,
			_heartbeatBound = false,
			_episodeSerial = 0,
			_resolvedCount = 0,
			_lastResult = nil,
		}, ObjectTeleport)
	end

	ObjectTeleport.New = ObjectTeleport.new

	function ObjectTeleport:_now(event)
		return tonumber(event and event.Time)
			or (self._context.Clock and self._context.Clock() or os.clock())
	end

	function ObjectTeleport:_remember(connection)
		if connection then table.insert(self._connections, connection) end
		return connection
	end

	function ObjectTeleport:_emit(event)
		if type(self._context.Emit) == "function" then self._context.Emit(event) end
	end

	function ObjectTeleport:_position(object)
		for _, name in ipairs({"ReadObjectPosition", "ReadPosition"}) do
			local callback = self._context[name]
			if type(callback) == "function" then
				local ok, value = pcall(callback, object)
				if ok and value ~= nil then return value end
			end
		end
		if object == nil then return nil end
		local positionOk, directPosition = pcall(function()
			return object.Position
		end)
		if positionOk and directPosition ~= nil then return directPosition end
		local pivot = call(object, "GetPivot")
		if pivot ~= nil then return pivot.Position end
		local part = call(object, "FindFirstChildWhichIsA", "BasePart", true)
		return part and part.Position or nil
	end

	function ObjectTeleport:_room(object, position)
		if type(self._context.ReadObjectRoom) == "function" then
			local ok, value = pcall(self._context.ReadObjectRoom, object, position)
			if ok then return value end
		end
		for _, name in ipairs({"ReadRoomAtPosition", "ReadPhysicalRoomAtPosition"}) do
			local callback = self._context[name]
			if type(callback) == "function" then
				local ok, value = pcall(callback, position, object)
				if ok then return value end
			end
		end
		return nil
	end

	function ObjectTeleport:_suppressed(event)
		if Events.Read(event, "AutomationCaused") == true
			or Events.Read(event, "Suppressed") == true then return true end
		for _, name in ipairs({
			"IsObjectTeleportSuppressed",
			"IsObjectMotionSuppressed",
			"IsAutomationMutationActive",
			"IsRoomItemPlacementBusy",
		}) do
			local callback = self._context[name]
			if type(callback) == "function" then
				local ok, value = pcall(callback, event)
				if ok and value == true then return true end
			end
		end
		return false
	end

	function ObjectTeleport:_bindObject(object)
		if not isTrackable(object) then return false end
		self._objects[object] = true
		local position = self:_position(object)
		if position ~= nil then
			local now = self:_now()
			self._previous[object] = {
				Position = position,
				Time = now,
				Room = self:_room(object, position),
			}
		end
		return true
	end

	function ObjectTeleport:_bindContainer(container)
		if container == nil or self._boundContainers[container] then return false end
		self._boundContainers[container] = true
		for _, child in ipairs(call(container, "GetChildren") or {}) do
			self:_bindObject(child)
		end
		self:_remember(connect(container.ChildAdded, function(child)
			self:_bindObject(child)
		end))
		self:_remember(connect(container.ChildRemoved, function(child)
			self._objects[child] = nil
			self._previous[child] = nil
			local pending = self._pendingByObject[child]
			if pending ~= nil then pending.Cancelled = true end
			self._pendingByObject[child] = nil
		end))
		return true
	end

	function ObjectTeleport:_inspectContainer(candidate)
		if candidate ~= nil and CONTAINER_NAMES[candidate.Name] then
			self:_bindContainer(candidate)
		end
	end

	function ObjectTeleport:_discoverContainers()
		local workspace = self._context.Workspace
		local map = workspace and call(workspace, "FindFirstChild", "Map")
		for _, parent in ipairs({workspace, map}) do
			if parent ~= nil then
				for name in pairs(CONTAINER_NAMES) do
					self:_inspectContainer(call(parent, "FindFirstChild", name))
				end
			end
		end
		for _, container in ipairs(
			type(self._context.ObjectTeleportContainers) == "table"
				and self._context.ObjectTeleportContainers or {}
		) do
			self:_bindContainer(container)
		end
	end

	function ObjectTeleport:_listObjects()
		if type(self._context.ReadTeleportObjects) == "function" then
			local ok, objects = pcall(self._context.ReadTeleportObjects)
			if ok and type(objects) == "table" then
				for _, object in ipairs(objects) do
					if self._previous[object] == nil then self:_bindObject(object) end
				end
				return objects
			end
		end
		local objects = {}
		for object in pairs(self._objects) do
			if object.Parent ~= nil then table.insert(objects, object) end
		end
		return objects
	end

	function ObjectTeleport:_clearPending()
		table.clear(self._pending)
		self._pendingByObject = setmetatable({}, {__mode = "k"})
	end

	function ObjectTeleport:_rebaseline(now)
		local seen = setmetatable({}, {__mode = "k"})
		for _, object in ipairs(self:_listObjects()) do
			local position = self:_position(object)
			if position ~= nil then
				seen[object] = true
				self._previous[object] = {
					Position = position,
					Time = now,
					Room = self:_room(object, position),
				}
			end
		end
		for object in pairs(self._previous) do
			if not seen[object] then self._previous[object] = nil end
		end
	end

	function ObjectTeleport:_recordSmoke(object, event)
		if object == nil or object.Name ~= "SmokeHolder" then return false end
		local now = self:_now(event)
		table.insert(self._recentSmoke, {Object = object, Time = now})
		self:_resolvePending(now)
		return true
	end

	function ObjectTeleport:_trimSmoke(now)
		for index = #self._recentSmoke, 1, -1 do
			if now - self._recentSmoke[index].Time > self.SmokeRetention then
				table.remove(self._recentSmoke, index)
			end
		end
	end

	function ObjectTeleport:_matchingSmoke(pending, now)
		for _, smoke in ipairs(self._recentSmoke) do
			if math.abs(smoke.Time - pending.Time) <= self.SmokeCorrelationWindow then
				return true, smoke.Object
			end
		end
		-- Entity's qualifying companion is a SmokeHolder anywhere in Workspace.
		-- It may predate this tracker's connection, so a DescendantAdded-only
		-- correlation would incorrectly report a smoke-free teleport.
		local workspace = self._context.Workspace
		local existing = call(workspace, "FindFirstChild", "SmokeHolder", true)
		if existing ~= nil then return true, existing end
		local callback = self._context.ReadMatchingSmokeHolder
		if type(callback) == "function" then
			local ok, result = pcall(
				callback,
				pending,
				now,
				self.SmokeCorrelationWindow
			)
			if ok and result then return true, result end
		end
		return false, nil
	end

	function ObjectTeleport:_finish(pending, smokeFound, smokeObject, now)
		self._pendingByObject[pending.Object] = nil
		self._resolvedCount = self._resolvedCount + 1
		self._lastResult = {
			EventId = pending.EventId,
			TeleportId = pending.Object,
			SmokeFound = smokeFound,
			SmokeHolder = smokeObject,
			FromPosition = pending.FromPosition,
			ToPosition = pending.ToPosition,
			FromRoom = pending.FromRoom,
			ToRoom = pending.ToRoom,
			Displacement = pending.Displacement,
			Elapsed = pending.Elapsed,
			Speed = pending.Speed,
			Time = now,
		}
		self:_emit({
			Type = Events.Types.ObjectTeleportResult,
			Time = now,
			Source = self.Name,
			Payload = {
				EventId = pending.EventId,
				EpisodeId = pending.EventId,
				TeleportId = pending.Object,
				ConfirmedTeleport = true,
				Completed = true,
				Qualified = true,
				SmokeFound = smokeFound,
				SmokeHolder = smokeObject,
				FromPosition = pending.FromPosition,
				ToPosition = pending.ToPosition,
				FromRoom = pending.FromRoom,
				ToRoom = pending.ToRoom,
				Displacement = pending.Displacement,
				Elapsed = pending.Elapsed,
				Speed = pending.Speed,
			},
		})
		self.Status = #self._pending > 0 and "Monitoring" or "Dormant"
	end

	function ObjectTeleport:_resolvePending(now)
		self:_trimSmoke(now)
		for index = #self._pending, 1, -1 do
			local pending = self._pending[index]
			if pending.Cancelled then
				table.remove(self._pending, index)
			elseif self._pendingByObject[pending.Object] ~= pending then
				table.remove(self._pending, index)
			else
				local smokeFound, smokeObject = self:_matchingSmoke(pending, now)
				if smokeFound or now >= pending.ResolveAt then
					table.remove(self._pending, index)
					self:_finish(pending, smokeFound, smokeObject, now)
				end
			end
		end
	end

	function ObjectTeleport:_sample(now, event)
		self:_discoverContainers()
		if self:_suppressed(event) then
			self:_clearPending()
			table.clear(self._recentSmoke)
			self._mutationActive = true
			self:_rebaseline(now)
			self.Status = "Dormant"
			return false
		end
		if self._mutationActive then
			self._mutationActive = false
			self:_rebaseline(now)
			return false
		end

		local seen = setmetatable({}, {__mode = "k"})
		for _, object in ipairs(self:_listObjects()) do
			local position = self:_position(object)
			if position ~= nil then
				seen[object] = true
				local previous = self._previous[object]
				if previous ~= nil then
					local elapsed = now - previous.Time
					local displacement = distance(position, previous.Position) or 0
					local speed = elapsed > 0 and displacement / elapsed or 0
					local room = displacement >= self.MinimumDisplacement
						and self:_room(object, position) or previous.Room
					if self._pendingByObject[object] == nil
						and elapsed > 0 and elapsed <= self.MaximumElapsed
						and displacement >= self.MinimumDisplacement
						and speed >= self.MinimumSpeed then
						self._episodeSerial = self._episodeSerial + 1
						local pending = {
							EventId = "object-teleport-" .. tostring(self._episodeSerial),
							Object = object,
							Time = now,
							ResolveAt = now + self.ResolveDelay,
							FromPosition = previous.Position,
							ToPosition = position,
							FromRoom = previous.Room,
							ToRoom = room,
							Displacement = displacement,
							Elapsed = elapsed,
							Speed = speed,
						}
						self._pendingByObject[object] = pending
						table.insert(self._pending, pending)
						self.Status = "Monitoring"
					end
					self._previous[object] = {
						Position = position,
						Time = now,
						Room = room,
					}
				else
					self._previous[object] = {
						Position = position,
						Time = now,
						Room = self:_room(object, position),
					}
				end
			end
		end
		for object in pairs(self._previous) do
			if not seen[object] then self._previous[object] = nil end
		end
		self:_resolvePending(now)
		return true
	end

	function ObjectTeleport:Start(context)
		if self.Status ~= "Idle" and self.Status ~= "Stopped" then return end
		self._context = context or {}
		self.Status = "Dormant"
		self:_discoverContainers()
		local now = self:_now()
		self._lastTick = now
		self:_rebaseline(now)
		local workspace = self._context.Workspace
		self:_remember(connect(workspace and workspace.DescendantAdded, function(object)
			if object.Name == "SmokeHolder" then
				self:_recordSmoke(object, {Time = self:_now()})
			elseif CONTAINER_NAMES[object.Name] then
				self:_inspectContainer(object)
			end
		end))
		local heartbeat = self._context.Heartbeat
			or (self._context.RunService and self._context.RunService.Heartbeat)
		local heartbeatConnection = connect(heartbeat, function(deltaTime)
			if self.Status == "Stopped" or self.Status == "Destroyed" then return end
			self._accumulator = self._accumulator
				+ math.max(0, tonumber(deltaTime) or 0)
			if self._accumulator + 1e-9 < self.SampleInterval then
				self:_resolvePending(self:_now())
				return
			end
			self._accumulator = self._accumulator % self.SampleInterval
			self:_sample(self:_now(), nil)
		end)
		if heartbeatConnection ~= nil then
			self._heartbeatBound = true
			self:_remember(heartbeatConnection)
		end
	end

	function ObjectTeleport:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or self._context == nil or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind == Events.Types.Tick then
			local now = self:_now(event)
			self:_resolvePending(now)
			if self._heartbeatBound then return true end
			if self._lastTick == nil then self._lastTick = now end
			self._accumulator = self._accumulator
				+ math.max(0, now - self._lastTick)
			self._lastTick = now
			if self._accumulator + 1e-9 < self.SampleInterval then return true end
			self._accumulator = self._accumulator % self.SampleInterval
			return self:_sample(now, event)
		elseif kind == "SmokeHolderAdded" then
			return self:_recordSmoke(
				Events.Read(event, "Object") or Events.Read(event, "SmokeHolder"),
				event
			)
		elseif kind == "ObjectTeleportSample" then
			return self:_sample(self:_now(event), event)
		end
		return false
	end

	function ObjectTeleport:Stop()
		for _, connection in ipairs(self._connections) do disconnect(connection) end
		table.clear(self._connections)
		self._heartbeatBound = false
		self:_clearPending()
		table.clear(self._recentSmoke)
		-- Container listeners were disconnected. Make Start rebuild them and
		-- rebaseline only objects that still exist after the stopped interval.
		self._boundContainers = setmetatable({}, {__mode = "k"})
		self._objects = setmetatable({}, {__mode = "k"})
		self._previous = setmetatable({}, {__mode = "k"})
		self._mutationActive = false
		self._accumulator = 0
		self._lastTick = nil
		self.Status = "Stopped"
	end

	function ObjectTeleport:Reset()
		self:Stop()
		self._boundContainers = setmetatable({}, {__mode = "k"})
		self._objects = setmetatable({}, {__mode = "k"})
		self._previous = setmetatable({}, {__mode = "k"})
		self._pendingByObject = setmetatable({}, {__mode = "k"})
		self._mutationActive = false
		self._episodeSerial = 0
		self._resolvedCount = 0
		self._lastResult = nil
		self.Status = "Idle"
	end

	function ObjectTeleport:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function ObjectTeleport:Snapshot()
		local objectCount = 0
		for _ in pairs(self._previous) do objectCount = objectCount + 1 end
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			ObjectCount = objectCount,
			PendingCount = #self._pending,
			RecentSmokeCount = #self._recentSmoke,
			MutationActive = self._mutationActive,
			HeartbeatBound = self._heartbeatBound,
			ResolvedCount = self._resolvedCount,
			LastResult = Events.Copy(self._lastResult),
			ConnectionCount = #self._connections,
		}
	end

	return ObjectTeleport
end
