return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "CrossMotion requires Events")

	local CrossMotion = {}
	CrossMotion.__index = CrossMotion

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
		local ok, result = pcall(callback, object, ...)
		return ok and result or nil
	end

	local function number(value)
		value = tonumber(value)
		return value == value and value or nil
	end

	local function positionComponents(position)
		if position == nil then return nil end
		local x = number(position.X or position.x or position[1])
		local y = number(position.Y or position.y or position[2])
		local z = number(position.Z or position.z or position[3])
		if x == nil or y == nil or z == nil then return nil end
		return x, y, z
	end

	function CrossMotion.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "CrossMotion",
			Category = "Dormant",
			Status = "Idle",
			SampleInterval = math.max(0, number(options.SampleInterval) or 0.1),
			TrialSeconds = math.max(0, number(options.TrialSeconds) or 4),
			RequiredRise = math.max(0, number(options.RequiredRise) or 0.45),
			RequiredRotation = math.max(0, number(options.RequiredRotation)
				or math.rad(45)),
			MaximumRotationStep = math.max(0, number(options.MaximumRotationStep)
				or math.rad(100)),
			MaximumHorizontalTravel = math.max(0,
				number(options.MaximumHorizontalTravel) or 5),
			_context = nil,
			_connections = {},
			_boundFolders = setmetatable({}, {__mode = "k"}),
			_boundModels = setmetatable({}, {__mode = "k"}),
			_particleStates = setmetatable({}, {__mode = "k"}),
			_active = setmetatable({}, {__mode = "k"}),
			_lastStepAt = nil,
			_motionObserved = false,
			_completedTrials = 0,
			_lastResult = nil,
		}, CrossMotion)
	end

	CrossMotion.New = CrossMotion.new

	function CrossMotion:_now(event)
		return number(event and event.Time)
			or (self._context.Clock and self._context.Clock() or os.clock())
	end

	function CrossMotion:_remember(connection)
		if connection then table.insert(self._connections, connection) end
		return connection
	end

	function CrossMotion:_isCrossModel(model)
		if type(self._context.IsCrossModel) == "function" then
			local ok, value = pcall(self._context.IsCrossModel, model)
			if ok then return value == true end
		end
		return call(model, "IsA", "Model") == true
			and call(model, "GetAttribute", "ItemName") == "Cross"
	end

	function CrossMotion:_findPart(model)
		if type(self._context.ReadCrossPart) == "function" then
			local ok, part = pcall(self._context.ReadCrossPart, model)
			if ok and part ~= nil then return part end
		end
		local part = call(model, "FindFirstChild", "Cross", true)
		return call(part, "IsA", "BasePart") == true and part or nil
	end

	function CrossMotion:_readTransform(model, part)
		if type(self._context.ReadCrossTransform) == "function" then
			local ok, transform = pcall(self._context.ReadCrossTransform, model, part)
			if ok then return transform end
		end
		local ok, transform = pcall(function() return part.CFrame end)
		return ok and transform or nil
	end

	function CrossMotion:_readPosition(transform)
		if transform == nil then return nil end
		local ok, position = pcall(function() return transform.Position end)
		if ok and position ~= nil then return position end
		if type(transform) == "table" then return transform.Position or transform end
		return nil
	end

	function CrossMotion:_rotationDelta(previous, current)
		if type(self._context.ReadCrossRotationDelta) == "function" then
			local ok, value = pcall(
				self._context.ReadCrossRotationDelta,
				previous,
				current
			)
			if ok then return math.abs(number(value) or math.huge) end
		end
		local ok, value = pcall(function()
			local relative = previous.Rotation:ToObjectSpace(current.Rotation)
			local _, angle = relative:ToAxisAngle()
			return math.abs(angle)
		end)
		return ok and number(value) or nil
	end

	function CrossMotion:_available(model, part)
		if type(self._context.CrossIsAvailable) == "function" then
			local ok, value = pcall(self._context.CrossIsAvailable, model, part)
			if ok then return value == true end
		end
		local modelOk, modelParent = pcall(function() return model.Parent end)
		local partOk, partParent = pcall(function() return part.Parent end)
		return modelOk and partOk and modelParent ~= nil and partParent ~= nil
	end

	function CrossMotion:_emit(model, floatedAndRotated, now, observation)
		self._completedTrials = self._completedTrials + 1
		self._lastResult = {
			TrialId = model,
			FloatedAndRotated = floatedAndRotated,
			Time = now,
			MaxRise = observation and observation.MaxRise or 0,
			AccumulatedAngle = observation and observation.AccumulatedAngle or 0,
			MaxHorizontalTravel = observation and observation.MaxHorizontalTravel or 0,
		}
		if type(self._context.Emit) == "function" then
			self._context.Emit({
				Type = Events.Types.CrossMotion,
				Time = now,
				Source = "CrossMotionCollector",
				Payload = {
					TrialId = model,
					Eligible = true,
					Completed = true,
					FloatedAndRotated = floatedAndRotated,
					Duration = observation
						and math.max(0, now - observation.StartTime) or 0,
					MaxRise = observation and observation.MaxRise or 0,
					AccumulatedAngle = observation
						and observation.AccumulatedAngle or 0,
					MaxHorizontalTravel = observation
						and observation.MaxHorizontalTravel or 0,
				},
			})
		end
	end

	function CrossMotion:_startTrial(model, now)
		if model == nil or self._active[model] ~= nil then return false end
		local part = self:_findPart(model)
		if part == nil then return false end
		local transform = self:_readTransform(model, part)
		local position = self:_readPosition(transform)
		local x, y, z = positionComponents(position)
		if transform == nil or x == nil then return false end
		self._active[model] = {
			Part = part,
			StartTime = now or self:_now(),
			StartX = x,
			StartY = y,
			StartZ = z,
			LastTransform = transform,
			AccumulatedAngle = 0,
			MaxRise = 0,
			MaxHorizontalTravel = 0,
		}
		self.Status = "Monitoring"
		return true
	end

	function CrossMotion:_bindParticle(model, part, particle)
		if call(particle, "IsA", "ParticleEmitter") ~= true
			or call(particle, "IsDescendantOf", part) ~= true then return end
		local ok, enabled = pcall(function() return particle.Enabled == true end)
		if not ok then return end
		self._particleStates[particle] = enabled
		local changed = call(particle, "GetPropertyChangedSignal", "Enabled")
		self:_remember(connect(changed, function()
			if self.Status == "Stopped" or self.Status == "Destroyed" then return end
			local previous = self._particleStates[particle]
			local readOk, current = pcall(function() return particle.Enabled == true end)
			if not readOk then return end
			self._particleStates[particle] = current
			if current and previous ~= true then
				self:_startTrial(model, self:_now())
			end
		end))
	end

	function CrossMotion:_bindModel(model)
		if model == nil or self._boundModels[model] or not self:_isCrossModel(model) then
			return false
		end
		local part = self:_findPart(model)
		if part == nil then return false end
		self._boundModels[model] = true
		for _, descendant in ipairs(call(model, "GetDescendants") or {}) do
			self:_bindParticle(model, part, descendant)
		end
		self:_remember(connect(model.DescendantAdded, function(descendant)
			self:_bindParticle(model, part, descendant)
		end))
		return true
	end

	function CrossMotion:_bindItems(folder)
		if folder == nil or self._boundFolders[folder] then return false end
		self._boundFolders[folder] = true
		for _, child in ipairs(call(folder, "GetChildren") or {}) do
			self:_bindModel(child)
		end
		self:_remember(connect(folder.ChildAdded, function(child)
			self:_bindModel(child)
		end))
		return true
	end

	function CrossMotion:_step(now)
		if self.Status == "Stopped" or self.Status == "Destroyed" then return false end
		now = number(now) or self:_now()
		if self._lastStepAt ~= nil
			and now - self._lastStepAt + 1e-6 < self.SampleInterval then return false end
		self._lastStepAt = now
		for model, observation in pairs(self._active) do
			local part = observation.Part
			local failedBecauseRemoved = not self:_available(model, part)
			if not failedBecauseRemoved then
				local current = self:_readTransform(model, part)
				local position = self:_readPosition(current)
				local x, y, z = positionComponents(position)
				if current == nil or x == nil then
					failedBecauseRemoved = true
				else
					local angle = self:_rotationDelta(observation.LastTransform, current)
					if angle ~= nil and angle <= self.MaximumRotationStep then
						observation.AccumulatedAngle = observation.AccumulatedAngle + angle
					end
					local rise = y - observation.StartY
					local dx, dz = x - observation.StartX, z - observation.StartZ
					observation.MaxRise = math.max(observation.MaxRise, rise)
					observation.MaxHorizontalTravel = math.max(
						observation.MaxHorizontalTravel,
						math.sqrt(dx * dx + dz * dz)
					)
					observation.LastTransform = current
					if observation.MaxRise >= self.RequiredRise
						and observation.AccumulatedAngle >= self.RequiredRotation
						and observation.MaxHorizontalTravel <= self.MaximumHorizontalTravel then
						self._motionObserved = true
						self._active[model] = nil
						self.Status = "Resolved"
						self:_emit(model, true, now, observation)
						continue
					end
				end
			end
			if failedBecauseRemoved or now - observation.StartTime >= self.TrialSeconds then
				self._active[model] = nil
				if not self._motionObserved then
					self.Status = "Resolved"
					self:_emit(model, false, now, observation)
				end
			end
		end
		return true
	end

	function CrossMotion:Start(context)
		if self.Status ~= "Idle" and self.Status ~= "Stopped" then return end
		self._context = context or {}
		self.Status = "Dormant"
		local workspace = self._context.Workspace
		self:_bindItems(
			self._context.ItemsFolder or call(workspace, "FindFirstChild", "Items")
		)
		self:_remember(connect(workspace and workspace.ChildAdded, function(child)
			if child.Name == "Items" then self:_bindItems(child) end
		end))
		local heartbeat = self._context.Heartbeat
		if heartbeat ~= nil then
			self:_remember(connect(heartbeat, function()
				self:_step(self:_now())
			end))
		elseif type(self._context.ConnectHeartbeat) == "function" then
			local ok, connection = pcall(self._context.ConnectHeartbeat, function()
				self:_step(self:_now())
			end)
			if ok then self:_remember(connection) end
		end
	end

	function CrossMotion:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or self._context == nil or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind == Events.Types.Tick then
			return self:_step(self:_now(event))
		elseif kind == "CrossActivated" then
			return self:_startTrial(
				Events.Read(event, "Model") or Events.Read(event, "Cross"),
				self:_now(event)
			)
		end
		return false
	end

	function CrossMotion:Stop()
		for _, connection in ipairs(self._connections) do disconnect(connection) end
		table.clear(self._connections)
		self._active = setmetatable({}, {__mode = "k"})
		-- All model/folder/particle listeners were disconnected, so their weak
		-- binding registries must not prevent a subsequent Start from rebinding.
		self._boundFolders = setmetatable({}, {__mode = "k"})
		self._boundModels = setmetatable({}, {__mode = "k"})
		self._particleStates = setmetatable({}, {__mode = "k"})
		self._lastStepAt = nil
		self.Status = "Stopped"
	end

	function CrossMotion:Reset()
		self:Stop()
		self._boundFolders = setmetatable({}, {__mode = "k"})
		self._boundModels = setmetatable({}, {__mode = "k"})
		self._particleStates = setmetatable({}, {__mode = "k"})
		self._motionObserved = false
		self._completedTrials = 0
		self._lastResult = nil
		self.Status = "Idle"
	end

	function CrossMotion:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function CrossMotion:Snapshot()
		local activeCount = 0
		for _ in pairs(self._active) do activeCount = activeCount + 1 end
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			ActiveTrials = activeCount,
			CompletedTrials = self._completedTrials,
			MotionObserved = self._motionObserved,
			ConnectionCount = #self._connections,
			LastResult = self._lastResult,
		}
	end

	return CrossMotion
end
