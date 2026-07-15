return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "VortexOrbit requires Events")
	local Specification = type(dependencies.Specification) == "table"
		and dependencies.Specification or {}
	local RavagerSpec = type(Specification.Ravager) == "table"
		and Specification.Ravager or {}

	local VortexOrbit = {}
	VortexOrbit.__index = VortexOrbit

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

	local function vector(x, y, z)
		return {X = x, Y = y, Z = z}
	end

	local function subtract(first, second)
		local ax, ay, az = xyz(first)
		local bx, by, bz = xyz(second)
		if ax == nil or bx == nil then return nil end
		return vector(ax - bx, ay - by, az - bz)
	end

	local function magnitude3(value)
		local x, y, z = xyz(value)
		if x == nil then return nil end
		return math.sqrt(x * x + y * y + z * z)
	end

	local function distance3(first, second)
		local difference = subtract(first, second)
		return difference and magnitude3(difference) or nil
	end

	local function isTrackableRoot(object)
		return object ~= nil and (
			call(object, "IsA", "Model") == true
			or call(object, "IsA", "BasePart") == true
		)
	end

	local function isUsablePart(part)
		return part ~= nil
			and call(part, "IsA", "BasePart") == true
			and part.Anchored ~= true
			and (tonumber(part.Transparency) or 0) < 1
	end

	function VortexOrbit.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "VortexOrbit",
			Category = "Dormant",
			Status = "Idle",
			SampleInterval = tonumber(options.SampleInterval)
				or tonumber(RavagerSpec.SampleInterval) or 0.1,
			ScanRadius = tonumber(options.ScanRadius)
				or tonumber(RavagerSpec.ScanRadius) or 45,
			MinimumRadius = tonumber(options.MinimumRadius)
				or tonumber(RavagerSpec.MinimumRadius) or 2.5,
			MaximumRadius = tonumber(options.MaximumRadius)
				or tonumber(RavagerSpec.MaximumRadius) or 40,
			MinimumDuration = tonumber(options.MinimumDuration)
				or tonumber(RavagerSpec.MinimumDuration) or 0.5,
			MinimumIntervals = math.max(1, math.floor(
				tonumber(options.MinimumIntervals)
					or tonumber(RavagerSpec.MinimumIntervals) or 5
			)),
			MinimumGoodShare = tonumber(options.MinimumGoodShare)
				or tonumber(RavagerSpec.MinimumGoodShare) or 0.7,
			MinimumAngularTotal = tonumber(options.MinimumAngularTotal)
				or tonumber(RavagerSpec.MinimumAngularTotal) or 45,
			MinimumDirectionShare = tonumber(options.MinimumDirectionShare)
				or tonumber(RavagerSpec.MinimumDirectionShare) or 0.65,
			RequiredObjects = math.max(1, math.floor(
				tonumber(options.RequiredObjects)
					or tonumber(RavagerSpec.RequiredObjects) or 3
			)),
			_context = nil,
			_connections = {},
			_boundContainers = setmetatable({}, {__mode = "k"}),
			_objects = setmetatable({}, {__mode = "k"}),
			_representatives = setmetatable({}, {__mode = "k"}),
			_tracked = setmetatable({}, {__mode = "k"}),
			_hunting = false,
			_huntId = nil,
			_detected = false,
			_lastGhostPosition = nil,
			_lastGhostSampleAt = nil,
			_accumulator = 0,
			_lastFallbackTick = nil,
			_heartbeatBound = false,
			_eventSerial = 0,
			_lastResult = nil,
		}, VortexOrbit)
	end

	VortexOrbit.New = VortexOrbit.new

	function VortexOrbit:_now(event)
		return tonumber(event and event.Time)
			or (self._context.Clock and self._context.Clock() or os.clock())
	end

	function VortexOrbit:_remember(connection)
		if connection then table.insert(self._connections, connection) end
		return connection
	end

	function VortexOrbit:_emit(event)
		if type(self._context.Emit) == "function" then self._context.Emit(event) end
	end

	function VortexOrbit:_readHunting(event)
		local explicit = Events.Read(event, "Hunting")
		if type(explicit) == "boolean" then return explicit end
		if type(self._context.ReadHunting) == "function" then
			local ok, value = pcall(self._context.ReadHunting)
			if ok then return value == true end
		end
		return call(self._context.GhostModel, "GetAttribute", "Hunting") == true
	end

	function VortexOrbit:_suppressed(event)
		if Events.Read(event, "AutomationCaused") == true
			or Events.Read(event, "Suppressed") == true then return true end
		for _, name in ipairs({
			"IsVortexSuppressed",
			"IsObjectMotionSuppressed",
			"IsAutomationMutationActive",
		}) do
			local callback = self._context[name]
			if type(callback) == "function" then
				local ok, value = pcall(callback, event)
				if ok and value == true then return true end
			end
		end
		return false
	end

	function VortexOrbit:_ghostPosition()
		if type(self._context.ReadGhostPosition) == "function" then
			local ok, value = pcall(self._context.ReadGhostPosition)
			if ok and value ~= nil then return value end
		end
		local ghost = self._context.GhostModel
		local pivot = call(ghost, "GetPivot")
		if pivot ~= nil then return pivot.Position end
		local ok, position = pcall(function()
			return ghost and ghost.Position or nil
		end)
		return ok and position or nil
	end

	function VortexOrbit:_resolveObject(root)
		local callback = self._context.ResolveVortexObject
		if type(callback) == "function" then
			local ok, first, second = pcall(callback, root)
			if ok then
				if type(first) == "table" and first.Position ~= nil then
					return first.Position, first.Assembly or first.AssemblyRoot or root
				end
				if first ~= nil then return first, second or root end
			end
		end

		local representative = self._representatives[root]
		if representative ~= nil and (
			representative.Parent == nil
			or not isUsablePart(representative)
			or (representative ~= root
				and call(representative, "IsDescendantOf", root) ~= true)
		) then
			representative = nil
			self._representatives[root] = nil
		end
		if representative == nil then
			if isUsablePart(root) then
				representative = root
			elseif call(root, "IsA", "Model") == true then
				if isUsablePart(root.PrimaryPart) then
					representative = root.PrimaryPart
				else
					for _, descendant in ipairs(call(root, "GetDescendants") or {}) do
						if isUsablePart(descendant) then
							representative = descendant
							break
						end
					end
				end
			end
			if representative ~= nil then self._representatives[root] = representative end
		end
		if representative == nil then return nil, nil end
		return representative.Position,
			representative.AssemblyRootPart or representative
	end

	function VortexOrbit:_bindRoot(root)
		if isTrackableRoot(root) then self._objects[root] = true end
	end

	function VortexOrbit:_bindContainer(container)
		if container == nil or self._boundContainers[container] then return false end
		self._boundContainers[container] = true
		for _, child in ipairs(call(container, "GetChildren") or {}) do
			self:_bindRoot(child)
		end
		self:_remember(connect(container.ChildAdded, function(child)
			self:_bindRoot(child)
		end))
		self:_remember(connect(container.ChildRemoved, function(child)
			self._objects[child] = nil
			self._tracked[child] = nil
			self._representatives[child] = nil
		end))
		return true
	end

	function VortexOrbit:_inspectContainer(candidate)
		if candidate ~= nil and CONTAINER_NAMES[candidate.Name] then
			self:_bindContainer(candidate)
		end
	end

	function VortexOrbit:_discoverContainers()
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
			type(self._context.VortexContainers) == "table"
				and self._context.VortexContainers or {}
		) do
			self:_bindContainer(container)
		end
	end

	function VortexOrbit:_roots(ghostPosition)
		if type(self._context.ReadVortexObjects) == "function" then
			local ok, roots = pcall(
				self._context.ReadVortexObjects,
				ghostPosition,
				self.ScanRadius
			)
			if ok and type(roots) == "table" then return roots end
		end
		local roots = {}
		for root in pairs(self._objects) do
			if root.Parent ~= nil then table.insert(roots, root) end
		end
		return roots
	end

	function VortexOrbit:_resetCandidate(tracked)
		tracked.Window = {}
		tracked.CandidateStartedAt = nil
		tracked.ConsecutiveBad = 0
	end

	function VortexOrbit:_resetMotion()
		self._tracked = setmetatable({}, {__mode = "k"})
		self._lastGhostPosition = nil
		self._lastGhostSampleAt = nil
		self._accumulator = 0
		self._lastFallbackTick = nil
	end

	function VortexOrbit:_setHunting(hunting, huntId)
		hunting = hunting == true
		self._hunting = hunting
		if hunting and huntId ~= nil then self._huntId = huntId end
		if not hunting then self._huntId = nil end
		if not self._detected then self.Status = "Monitoring" end
	end

	function VortexOrbit:_qualify(root, assembly, tracked, now)
		local goodIntervals = 0
		local signedTotal = 0
		local absoluteTotal = 0
		local fastest = 0
		for _, interval in ipairs(tracked.Window) do
			if interval.Good then
				goodIntervals = goodIntervals + 1
				signedTotal = signedTotal + interval.SignedAngle
				absoluteTotal = absoluteTotal + interval.AbsAngle
				fastest = math.max(fastest, interval.Speed)
			end
		end
		local duration = now - tracked.CandidateStartedAt
		local intervalCount = #tracked.Window
		local goodShare = goodIntervals / math.max(intervalCount, 1)
		local directionShare = math.abs(signedTotal)
			/ math.max(absoluteTotal, 0.001)
		if duration < self.MinimumDuration
			or intervalCount < self.MinimumIntervals
			or goodShare < self.MinimumGoodShare
			or absoluteTotal < self.MinimumAngularTotal
			or directionShare < self.MinimumDirectionShare then return nil end
		return {
			Root = root,
			Assembly = assembly,
			Direction = signedTotal >= 0 and 1 or -1,
			Duration = duration,
			Intervals = intervalCount,
			GoodShare = goodShare,
			AngularTotal = absoluteTotal,
			Speed = fastest,
		}
	end

	function VortexOrbit:_sample(now, event)
		self:_setHunting(self:_readHunting(event), Events.Read(event, "HuntId"))
		if self._detected then return false end
		if self:_suppressed(event) then
			self:_resetMotion()
			return false
		end

		self:_discoverContainers()
		local ghostPosition = self:_ghostPosition()
		if xyz(ghostPosition) == nil then
			self:_resetMotion()
			return false
		end
		local previousGhostPosition = self._lastGhostPosition
		local previousGhostTime = self._lastGhostSampleAt
		self._lastGhostPosition = ghostPosition
		self._lastGhostSampleAt = now
		if previousGhostPosition ~= nil and previousGhostTime ~= nil
			and now - previousGhostTime <= 0.2
			and (distance3(ghostPosition, previousGhostPosition) or 0) > 8 then
			self._tracked = setmetatable({}, {__mode = "k"})
			return false
		end

		local seen = setmetatable({}, {__mode = "k"})
		local qualified = {}
		for _, root in ipairs(self:_roots(ghostPosition)) do
			local position, assembly = self:_resolveObject(root)
			local separation = position and distance3(position, ghostPosition) or nil
			if position ~= nil and assembly ~= nil and separation ~= nil
				and separation <= self.ScanRadius then
				seen[root] = true
				local relative = subtract(position, ghostPosition)
				local tracked = self._tracked[root]
				if tracked == nil then
					tracked = {Window = {}, ConsecutiveBad = 0}
					self._tracked[root] = tracked
				end
				local oldPosition = tracked.Position
				local oldRelative = tracked.Relative
				local oldTime = tracked.Time
				tracked.Position = position
				tracked.Relative = relative
				tracked.Time = now
				tracked.Assembly = assembly

				if oldPosition ~= nil and oldRelative ~= nil and oldTime ~= nil then
					local elapsed = now - oldTime
					local oldX, _, oldZ = xyz(oldRelative)
					local newX, _, newZ = xyz(relative)
					local oldRadius = math.sqrt(oldX * oldX + oldZ * oldZ)
					local newRadius = math.sqrt(newX * newX + newZ * newZ)
					local stepX, stepZ = newX - oldX, newZ - oldZ
					local relativeStep = math.sqrt(stepX * stepX + stepZ * stepZ)
					local geometryValid = elapsed >= 0.06 and elapsed <= 0.2
						and oldRadius >= self.MinimumRadius
						and oldRadius <= self.MaximumRadius
						and newRadius >= self.MinimumRadius
						and newRadius <= self.MaximumRadius
						and relativeStep <= 12
					local orbitLike = false
					local signedAngle = 0
					local relativeSpeed = 0
					if geometryValid then
						local dot = oldX * newX + oldZ * newZ
						local cross = oldX * newZ - oldZ * newX
						signedAngle = math.deg(math.atan2(cross, dot))
						local velocityX = stepX / elapsed
						local velocityZ = stepZ / elapsed
						relativeSpeed = math.sqrt(
							velocityX * velocityX + velocityZ * velocityZ
						)
						local worldSpeed = (distance3(position, oldPosition) or 0)
							/ math.max(elapsed, 0.001)
						local radialX = newX / math.max(newRadius, 0.001)
						local radialZ = newZ / math.max(newRadius, 0.001)
						local radialSpeed = math.abs(
							velocityX * radialX + velocityZ * radialZ
						)
						local tangentialSpeed = math.sqrt(math.max(
							relativeSpeed * relativeSpeed
								- radialSpeed * radialSpeed,
							0
						))
						local tangentialShare = tangentialSpeed
							/ math.max(relativeSpeed, 0.001)
						local radiusChange = math.abs(newRadius - oldRadius)
						local meanRadius = (oldRadius + newRadius) * 0.5
						orbitLike = worldSpeed >= 4
							and relativeSpeed >= 6
							and math.abs(signedAngle) / elapsed >= 70
							and tangentialShare >= 0.55
							and radiusChange <= math.max(2, meanRadius * 0.35)
					end

					if not geometryValid then
						self:_resetCandidate(tracked)
					elseif orbitLike or tracked.CandidateStartedAt ~= nil then
						if orbitLike and tracked.CandidateStartedAt == nil then
							tracked.CandidateStartedAt = oldTime
						end
						table.insert(tracked.Window, {
							StartAt = oldTime,
							Time = now,
							Good = orbitLike,
							SignedAngle = orbitLike and signedAngle or 0,
							AbsAngle = orbitLike and math.abs(signedAngle) or 0,
							Speed = orbitLike and relativeSpeed or 0,
						})
						tracked.ConsecutiveBad = orbitLike
							and 0 or tracked.ConsecutiveBad + 1
						for index = #tracked.Window, 1, -1 do
							if now - tracked.Window[index].Time > 0.8 then
								table.remove(tracked.Window, index)
							end
						end
						if tracked.ConsecutiveBad > 2 or #tracked.Window == 0 then
							self:_resetCandidate(tracked)
						else
							tracked.CandidateStartedAt = tracked.Window[1].StartAt
							local result = self:_qualify(root, assembly, tracked, now)
							if result ~= nil then table.insert(qualified, result) end
						end
					end
				end
			end
		end
		for root in pairs(self._tracked) do
			if not seen[root] then self._tracked[root] = nil end
		end

		local buckets = {[1] = {}, [-1] = {}}
		local assemblies = {[1] = {}, [-1] = {}}
		for _, result in ipairs(qualified) do
			local direction = result.Direction
			if not assemblies[direction][result.Assembly] then
				assemblies[direction][result.Assembly] = true
				table.insert(buckets[direction], result)
			end
		end
		for _, direction in ipairs({1, -1}) do
			local matching = buckets[direction]
			if #matching >= self.RequiredObjects then
				local minimumDuration = math.huge
				local minimumIntervals = math.huge
				local minimumGoodShare = math.huge
				local minimumAngle = math.huge
				for _, result in ipairs(matching) do
					minimumDuration = math.min(minimumDuration, result.Duration)
					minimumIntervals = math.min(minimumIntervals, result.Intervals)
					minimumGoodShare = math.min(minimumGoodShare, result.GoodShare)
					minimumAngle = math.min(minimumAngle, result.AngularTotal)
				end
				self._detected = true
				self._eventSerial = self._eventSerial + 1
				self._lastResult = {
					EventId = "vortex-" .. tostring(self._eventSerial),
					HuntId = self._huntId,
					DistinctObjects = #matching,
					Duration = minimumDuration,
					Intervals = minimumIntervals,
					GoodShare = minimumGoodShare,
					AccumulatedAngle = minimumAngle,
					Direction = direction,
					Time = now,
				}
				self.Status = "Resolved"
				self:_emit({
					Type = Events.Types.VortexPattern,
					Time = now,
					HuntId = self._huntId,
					Hunting = self._hunting,
					Source = self.Name,
					Payload = {
						EventId = self._lastResult.EventId,
						Qualified = true,
						Completed = true,
						DistinctObjects = #matching,
						Duration = minimumDuration,
						Intervals = minimumIntervals,
						GoodShare = minimumGoodShare,
						AccumulatedAngle = minimumAngle,
						Direction = direction,
						Objects = matching,
					},
				})
				return true
			end
		end
		return false
	end

	function VortexOrbit:_heartbeat(deltaTime)
		if self.Status == "Stopped" or self.Status == "Destroyed" then return end
		self:_setHunting(self:_readHunting(), nil)
		self._accumulator = self._accumulator + math.max(0, tonumber(deltaTime) or 0)
		if self._accumulator < self.SampleInterval then return end
		self._accumulator = self._accumulator % self.SampleInterval
		self:_sample(self:_now(), nil)
	end

	function VortexOrbit:Start(context)
		if self.Status ~= "Idle" and self.Status ~= "Stopped" then return end
		self._context = context or {}
		self.Status = "Dormant"
		self:_discoverContainers()
		local workspace = self._context.Workspace
		self:_remember(connect(workspace and workspace.DescendantAdded, function(object)
			if CONTAINER_NAMES[object.Name] then self:_inspectContainer(object) end
		end))
		local heartbeat = self._context.Heartbeat
			or (self._context.RunService and self._context.RunService.Heartbeat)
		local heartbeatConnection = connect(heartbeat, function(deltaTime)
			self:_heartbeat(deltaTime)
		end)
		if heartbeatConnection ~= nil then
			self._heartbeatBound = true
			self:_remember(heartbeatConnection)
		end
		self:_setHunting(self:_readHunting(), nil)
	end

	function VortexOrbit:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or self._context == nil or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind == Events.Types.HuntStarted then
			self:_setHunting(true, Events.Read(event, "HuntId"))
			return true
		elseif kind == Events.Types.HuntEnded then
			self:_setHunting(false, Events.Read(event, "HuntId"))
			return true
		elseif kind == Events.Types.HuntingStateChanged then
			local hunting = Events.Read(event, "Current")
			if type(hunting) ~= "boolean" then hunting = self:_readHunting(event) end
			self:_setHunting(hunting, Events.Read(event, "HuntId"))
			return true
		elseif kind == Events.Types.Tick and not self._heartbeatBound then
			local now = self:_now(event)
			if self._lastFallbackTick == nil then
				self._lastFallbackTick = now
				return self:_sample(now, event)
			end
			self._accumulator = self._accumulator
				+ math.max(0, now - self._lastFallbackTick)
			self._lastFallbackTick = now
			if self._accumulator + 1e-9 < self.SampleInterval then return true end
			self._accumulator = self._accumulator % self.SampleInterval
			return self:_sample(now, event)
		end
		return false
	end

	function VortexOrbit:Stop()
		for _, connection in ipairs(self._connections) do disconnect(connection) end
		table.clear(self._connections)
		self._heartbeatBound = false
		self:_resetMotion()
		-- Start after Stop must reconnect each container and discover objects
		-- that appeared while observation was paused.
		self._boundContainers = setmetatable({}, {__mode = "k"})
		self._objects = setmetatable({}, {__mode = "k"})
		self._representatives = setmetatable({}, {__mode = "k"})
		self.Status = "Stopped"
	end

	function VortexOrbit:Reset()
		self:Stop()
		self._boundContainers = setmetatable({}, {__mode = "k"})
		self._objects = setmetatable({}, {__mode = "k"})
		self._representatives = setmetatable({}, {__mode = "k"})
		self._hunting = false
		self._huntId = nil
		self._detected = false
		self._eventSerial = 0
		self._lastResult = nil
		self.Status = "Idle"
	end

	function VortexOrbit:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function VortexOrbit:Snapshot()
		local objectCount, trackedCount = 0, 0
		for _ in pairs(self._objects) do objectCount = objectCount + 1 end
		for _ in pairs(self._tracked) do trackedCount = trackedCount + 1 end
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			Hunting = self._hunting,
			HuntId = self._huntId,
			ObjectCount = objectCount,
			TrackedCount = trackedCount,
			HeartbeatBound = self._heartbeatBound,
			Detected = self._detected,
			LastResult = Events.Copy(self._lastResult),
			ConnectionCount = #self._connections,
		}
	end

	return VortexOrbit
end
