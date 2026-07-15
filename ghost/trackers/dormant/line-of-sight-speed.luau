return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "LineOfSightSpeed requires Events")
	local Specification = type(dependencies.Specification) == "table"
		and dependencies.Specification or {}
	local LineOfSightSpec = type(Specification.LineOfSight) == "table"
		and Specification.LineOfSight or {}

	local LineOfSightSpeed = {}
	LineOfSightSpeed.__index = LineOfSightSpeed

	local function disconnect(connection)
		if connection and type(connection.Disconnect) == "function" then
			pcall(connection.Disconnect, connection)
		end
	end

	local function connect(signal, callback)
		if signal == nil then return nil end
		local ok, connection = pcall(function() return signal:Connect(callback) end)
		return ok and connection or nil
	end

	local function call(object, method, ...)
		local callback = object and object[method]
		if type(callback) ~= "function" then return nil end
		local ok, result = pcall(callback, object, ...)
		return ok and result or nil
	end

	function LineOfSightSpeed.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "LineOfSightSpeed",
			Category = "Dormant",
			Status = "Idle",
			RequiredExposure = math.max(0.5, tonumber(options.RequiredExposure)
				or tonumber(LineOfSightSpec.RequiredExposure) or 4),
			SlowWindow = math.max(0.5, tonumber(options.SlowWindow) or 4),
			RequiredSlowEdges = math.max(1, math.floor(tonumber(options.RequiredSlowEdges)
				or tonumber(LineOfSightSpec.RequiredSlowEdges) or 1)),
			SlowEpsilon = math.max(0, tonumber(options.SlowEpsilon)
				or tonumber(LineOfSightSpec.SlowEpsilon) or 0.25),
			_context = nil,
			_connections = {},
			_speedConnection = nil,
			_player = nil,
			_character = nil,
			_humanoid = nil,
			_hunting = false,
			_huntId = nil,
			_exposure = 0,
			_lastTickAt = nil,
			_lastWasSprinting = false,
			_lastSpeed = nil,
			_sprintBaseline = nil,
			_persistentSlowRecorded = false,
			_slowEdges = {},
			_outcome = nil,
		}, LineOfSightSpeed)
	end

	LineOfSightSpeed.New = LineOfSightSpeed.new

	function LineOfSightSpeed:_now(event)
		return tonumber(event and event.Time)
			or (self._context.Clock and self._context.Clock() or os.clock())
	end

	function LineOfSightSpeed:_remember(connection)
		if connection then table.insert(self._connections, connection) end
		return connection
	end

	function LineOfSightSpeed:_emit(event)
		if type(self._context.Emit) == "function" then self._context.Emit(event) end
	end

	function LineOfSightSpeed:_readHunting()
		if type(self._context.ReadHunting) == "function" then
			local ok, value = pcall(self._context.ReadHunting)
			if ok then return value == true end
		end
		return call(self._context.GhostModel, "GetAttribute", "Hunting") == true
	end

	function LineOfSightSpeed:_readLineOfSight()
		if not self._character then return false end
		if type(self._context.ReadLocalPlayerLineOfSight) == "function" then
			local ok, value = pcall(
				self._context.ReadLocalPlayerLineOfSight,
				self._context.GhostModel,
				self._character,
				self._player
			)
			return ok and value == true
		end
		return false
	end

	function LineOfSightSpeed:_readSpeed()
		if type(self._context.ReadLocalPlayerSpeed) == "function" then
			local ok, value = pcall(
				self._context.ReadLocalPlayerSpeed,
				self._humanoid,
				self._player
			)
			if ok and tonumber(value) then return tonumber(value) end
		end
		return self._humanoid and tonumber(self._humanoid.WalkSpeed) or nil
	end

	function LineOfSightSpeed:_baseline()
		if type(self._context.ReadLocalPlayerBaselineSpeed) == "function" then
			local ok, value = pcall(
				self._context.ReadLocalPlayerBaselineSpeed,
				self._humanoid,
				self._player
			)
			if ok and tonumber(value) then return tonumber(value) end
		end
		return tonumber(self._context.LocalPlayerBaselineSpeed) or 10
	end

	function LineOfSightSpeed:_readSprinting()
		if type(self._context.ReadLocalPlayerSprinting) == "function" then
			local ok, value = pcall(
				self._context.ReadLocalPlayerSprinting,
				self._player,
				self._character,
				self._humanoid
			)
			if ok and type(value) == "boolean" then return value end
		end
		for _, owner in ipairs({self._player, self._humanoid}) do
			for _, name in ipairs({"Sprinting", "IsSprinting", "Sprint"}) do
				local value = call(owner, "GetAttribute", name)
				if type(value) == "boolean" then return value end
			end
		end
		local speed = self:_readSpeed()
		return speed ~= nil and speed > self:_baseline() + self.SlowEpsilon
	end

	function LineOfSightSpeed:_pruneSlowEdges(now)
		while self._slowEdges[1] and now - self._slowEdges[1] > self.SlowWindow do
			table.remove(self._slowEdges, 1)
		end
	end

	function LineOfSightSpeed:_emitPositive(now, speed, baseline)
		if self._outcome ~= nil then return end
		self._outcome = "Slowed"
		self.Status = "Resolved"
		self:_emit({
			Type = Events.Types.LineOfSightPlayerSpeed,
			Time = now,
			HuntId = self._huntId,
			Hunting = true,
			Source = self.Name,
			Payload = {
				Qualified = true,
				Completed = true,
				Sprinting = true,
				LineOfSight = true,
				Slowed = true,
				Speed = speed,
				BaselineSpeed = baseline,
				SlowEdgeCount = #self._slowEdges,
				ExposureSeconds = self._exposure,
			},
		})
	end

	function LineOfSightSpeed:_emitNegative(now)
		if self._outcome ~= nil or self._exposure < self.RequiredExposure then return end
		self._outcome = "NotSlowed"
		self.Status = "Resolved"
		self:_emit({
			Type = Events.Types.LineOfSightPlayerSpeed,
			Time = now,
			HuntId = self._huntId,
			Hunting = true,
			Source = self.Name,
			Payload = {
				Qualified = true,
				Completed = true,
				Sprinting = true,
				LineOfSight = true,
				Slowed = false,
				ExposureSeconds = self._exposure,
			},
		})
	end

	function LineOfSightSpeed:_referenceSpeed()
		local reference = self:_baseline()
		if self._sprintBaseline ~= nil then
			reference = math.max(reference, self._sprintBaseline)
		end
		if self._lastSpeed ~= nil then
			reference = math.max(reference, self._lastSpeed)
		end
		return reference
	end

	function LineOfSightSpeed:_recordSlow(now, speed, reference, persistent)
		if speed == nil or reference == nil
			or speed >= reference - self.SlowEpsilon then return false end
		if persistent and self._persistentSlowRecorded then return false end
		if persistent then self._persistentSlowRecorded = true end
		table.insert(self._slowEdges, now)
		self:_pruneSlowEdges(now)
		if #self._slowEdges >= self.RequiredSlowEdges then
			self:_emitPositive(now, speed, reference)
		end
		return true
	end

	function LineOfSightSpeed:_onSpeedChanged()
		local speed = self:_readSpeed()
		local baseline = self:_referenceSpeed()
		local now = self:_now()
		local sprinting = self:_readSprinting() or self._lastWasSprinting
		if self._hunting and self._outcome == nil and sprinting
			and self:_readLineOfSight() and speed ~= nil then
			self:_recordSlow(now, speed, baseline, false)
		end
		if sprinting and speed ~= nil
			and speed >= baseline - self.SlowEpsilon then
			if self._sprintBaseline == nil or speed > self._sprintBaseline then
				self._sprintBaseline = speed
			end
		end
		self._lastSpeed = speed
	end

	function LineOfSightSpeed:_bindCharacter(character)
		disconnect(self._speedConnection)
		self._speedConnection = nil
		self._character = character
		self._humanoid = character and call(character, "FindFirstChildOfClass", "Humanoid") or nil
		self._lastSpeed = self:_readSpeed()
		if self._humanoid then
			local signal = call(self._humanoid, "GetPropertyChangedSignal", "WalkSpeed")
			self._speedConnection = connect(signal, function() self:_onSpeedChanged() end)
		end
	end

	function LineOfSightSpeed:_beginHunt(event)
		self._hunting = true
		self._huntId = event.HuntId
		self._exposure = 0
		self._lastTickAt = self:_now(event)
		self._lastWasSprinting = false
		self._sprintBaseline = math.max(
			self:_baseline(),
			self._lastSpeed or -math.huge
		)
		self._persistentSlowRecorded = false
		table.clear(self._slowEdges)
		self._outcome = nil
		self.Status = "Active"
	end

	function LineOfSightSpeed:_endHunt(event)
		self:_emitNegative(self:_now(event))
		self._hunting = false
		self._huntId = nil
		self._lastTickAt = nil
		self._lastWasSprinting = false
		self._sprintBaseline = nil
		self._persistentSlowRecorded = false
		self.Status = "Dormant"
	end

	function LineOfSightSpeed:Start(context)
		self._context = context or {}
		local players = self._context.Players or self._context.PlayersService
		self._player = self._context.LocalPlayer or (players and players.LocalPlayer)
		self.Status = "Dormant"
		self:_bindCharacter(self._player and self._player.Character or nil)
		if self._player then
			self:_remember(connect(self._player.CharacterAdded, function(character)
				self:_bindCharacter(character)
			end))
		end
	end

	function LineOfSightSpeed:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind == Events.Types.HuntStarted then
			self:_beginHunt(event)
			return true
		elseif kind == Events.Types.HuntEnded then
			if self._hunting then self:_endHunt(event) end
			return true
		elseif kind ~= Events.Types.Tick or not self._hunting
			or self._outcome ~= nil then return false end

		if self._player and self._player.Character ~= self._character then
			self:_bindCharacter(self._player.Character)
		end
		local now = self:_now(event)
		local elapsed = self._lastTickAt and math.max(0, now - self._lastTickAt) or 0
		self._lastTickAt = now
		local sprinting = self:_readSprinting()
		local lineOfSight = self:_readLineOfSight()
		if sprinting and lineOfSight then
			local speed = self:_readSpeed()
			local baseline = self:_referenceSpeed()
			if speed ~= nil then
				if not self:_recordSlow(now, speed, baseline, true)
					and speed >= baseline - self.SlowEpsilon then
					if self._sprintBaseline == nil or speed > self._sprintBaseline then
						self._sprintBaseline = speed
					end
				end
				self._lastSpeed = speed
			end
			self._exposure = self._exposure + elapsed
			self._lastWasSprinting = true
			self:_emitNegative(now)
		else
			-- The negative is a completed continuous sprinting LOS trial.
			self._exposure = 0
			self._lastWasSprinting = false
			self._persistentSlowRecorded = false
		end
		return true
	end

	function LineOfSightSpeed:Stop()
		disconnect(self._speedConnection)
		self._speedConnection = nil
		for _, connection in ipairs(self._connections) do disconnect(connection) end
		table.clear(self._connections)
		self._hunting = false
		self.Status = "Stopped"
	end

	function LineOfSightSpeed:Reset()
		self:Stop()
		self._player, self._character, self._humanoid = nil, nil, nil
		self._huntId, self._lastTickAt, self._lastSpeed = nil, nil, nil
		self._exposure, self._lastWasSprinting = 0, false
		self._sprintBaseline = nil
		self._persistentSlowRecorded = false
		table.clear(self._slowEdges)
		self._outcome = nil
		self.Status = "Idle"
	end

	function LineOfSightSpeed:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function LineOfSightSpeed:Snapshot()
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			Hunting = self._hunting,
			HuntId = self._huntId,
			ExposureSeconds = self._exposure,
			SlowEdgeCount = #self._slowEdges,
			Outcome = self._outcome,
		}
	end

	return LineOfSightSpeed
end
