return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "SpecterTrial requires Events")

	local SpecterTrial = {}
	SpecterTrial.__index = SpecterTrial

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

	local function number(value)
		value = tonumber(value)
		return value == value and value or nil
	end

	local function median(values)
		if #values == 0 then return nil end
		local sorted = {}
		for index, value in ipairs(values) do sorted[index] = value end
		table.sort(sorted)
		local middle = math.floor((#sorted + 1) / 2)
		if #sorted % 2 == 1 then return sorted[middle] end
		return (sorted[middle] + sorted[middle + 1]) / 2
	end

	local function defaultSameRoom(left, right)
		if left == nil or right == nil then return false end
		local function token(value)
			return string.lower((tostring(value):gsub("[^%w]", "")))
		end
		return token(left) == token(right)
	end

	function SpecterTrial.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "SpecterTrial",
			Category = "Dormant",
			Status = "Idle",
			SampleInterval = math.max(0, number(options.SampleInterval) or 0.1),
			AnalysisInterval = math.max(0, number(options.AnalysisInterval) or 0.2),
			SettledWindow = math.max(0, number(options.SettledWindow) or 0.8),
			StationaryThreshold = math.max(0,
				number(options.StationaryThreshold) or 0.22),
			ArmSeconds = math.max(0, number(options.ArmSeconds) or 5),
			RoomChangeSettleSeconds = math.max(0,
				number(options.RoomChangeSettleSeconds) or 2),
			_context = nil,
			_connections = {},
			_motionSamples = {},
			_lastSampleAt = nil,
			_lastAnalysisAt = nil,
			_lastHunting = nil,
			_candidateAt = nil,
			_armed = false,
			_trackedFavourite = nil,
			_roomChangePause = false,
			_roomChangeSettleAt = nil,
			_trialSequence = 0,
			_activeTrialId = nil,
			_completedTrials = 0,
			_lastOutcome = nil,
		}, SpecterTrial)
	end

	SpecterTrial.New = SpecterTrial.new

	function SpecterTrial:_now(event)
		return number(event and event.Time)
			or (self._context.Clock and self._context.Clock() or os.clock())
	end

	function SpecterTrial:_read(name, ...)
		local callback = self._context and self._context[name]
		if type(callback) ~= "function" then return nil end
		local ok, value = pcall(callback, ...)
		return ok and value or nil
	end

	function SpecterTrial:_sameRoom(left, right)
		local callback = self._context and self._context.SameRoomName
		if type(callback) == "function" then
			local ok, value = pcall(callback, left, right)
			if ok then return value == true end
		end
		return defaultSameRoom(left, right)
	end

	function SpecterTrial:_readHunting(event)
		local value = Events.Read(event, "Hunting")
		if type(value) ~= "boolean" then value = self:_read("ReadHunting") end
		return value == true
	end

	function SpecterTrial:_inFavourite(favourite)
		local direct = self:_read("ReadGhostInFavouriteRoom", favourite)
		if type(direct) == "boolean" then return direct end
		local current = self:_read("ReadPhysicalCurrentRoom")
		if current == nil then current = self:_read("ReadCurrentRoom") end
		return self:_sameRoom(current, favourite)
	end

	function SpecterTrial:_readMovementSpeed()
		return math.max(0, number(self:_read("ReadGhostMovementSpeed")) or 0)
	end

	function SpecterTrial:_emit(outcome, now)
		local trialId = self._activeTrialId
			or ("specter-" .. string.lower(outcome) .. ":" .. tostring(now))
		local armedSeconds = math.max(
			self.ArmSeconds,
			now - (self._candidateAt or now)
		)
		self._completedTrials = self._completedTrials + 1
		self._lastOutcome = {
			TrialId = trialId,
			Outcome = outcome,
			Time = now,
			ArmedSeconds = armedSeconds,
		}
		if type(self._context.Emit) == "function" then
			self._context.Emit({
				Type = Events.Types.SpecterTrial,
				Time = now,
				Source = "FavouriteRoomResidenceCollector",
				Payload = {
					TrialId = trialId,
					Qualified = true,
					Completed = true,
					FavouriteRoomUnchanged = true,
					ArmedSeconds = armedSeconds,
					Outcome = outcome,
				},
			})
		end
		self.Status = "Resolved"
	end

	function SpecterTrial:_clearTrial()
		self._candidateAt = nil
		self._armed = false
		self._activeTrialId = nil
	end

	function SpecterTrial:_huntStartOutcome()
		local favourite = self:_read("ReadFavouriteRoom")
		if favourite == nil or tostring(favourite) == ""
			or self._trackedFavourite == nil
			or not self:_sameRoom(self._trackedFavourite, favourite) then
			-- A favourite-room switch invalidates the old trial. It is neither
			-- residence nor departure from an unchanged favourite room.
			return nil
		end
		local inFavourite = self:_inFavourite(favourite)
		local stationary = self:_readMovementSpeed() <= self.StationaryThreshold
		if inFavourite and stationary then
			return "Residence"
		end
		return "Departure"
	end

	function SpecterTrial:_handleHunting(hunting, now)
		if self._lastHunting == nil then
			self._lastHunting = hunting
			return
		end
		if hunting and not self._lastHunting then
			if self._armed and not self._roomChangePause then
				local outcome = self:_huntStartOutcome()
				if outcome ~= nil then self:_emit(outcome, now) end
			end
			self:_clearTrial()
			self._roomChangePause = false
			self._roomChangeSettleAt = nil
		end
		self._lastHunting = hunting
	end

	function SpecterTrial:_sample(now, speed)
		if self._lastSampleAt ~= nil
			and now - self._lastSampleAt + 1e-6 < self.SampleInterval then return end
		self._lastSampleAt = now
		table.insert(self._motionSamples, {Time = now, Speed = speed})
		local cutoff = now - math.max(12, self.SettledWindow)
		while self._motionSamples[1] and self._motionSamples[1].Time < cutoff do
			table.remove(self._motionSamples, 1)
		end
	end

	function SpecterTrial:_settledSpeed(now, fallback)
		local values = {}
		local cutoff = now - self.SettledWindow
		for _, sample in ipairs(self._motionSamples) do
			if sample.Time >= cutoff then table.insert(values, sample.Speed) end
		end
		return median(values) or fallback
	end

	function SpecterTrial:_analyze(now, measuredSpeed)
		if self._lastAnalysisAt ~= nil
			and now - self._lastAnalysisAt + 1e-6 < self.AnalysisInterval then return end
		self._lastAnalysisAt = now
		local favourite = self:_read("ReadFavouriteRoom")
		if favourite == nil or tostring(favourite) == "" then
			self:_clearTrial()
			self.Status = "Dormant"
			return
		end
		local inFavourite = self:_inFavourite(favourite)
		local stationary = self:_settledSpeed(now, measuredSpeed)
			<= self.StationaryThreshold

		if self._trackedFavourite == nil then
			self._trackedFavourite = favourite
		elseif not self:_sameRoom(self._trackedFavourite, favourite) then
			self._trackedFavourite = favourite
			self._roomChangePause = true
			self._roomChangeSettleAt = nil
			self:_clearTrial()
		end

		if self._roomChangePause then
			if inFavourite and stationary then
				if self._roomChangeSettleAt == nil then
					self._roomChangeSettleAt = now
				elseif now - self._roomChangeSettleAt
					+ 1e-6 >= self.RoomChangeSettleSeconds then
					self._roomChangePause = false
					self._roomChangeSettleAt = nil
					self._candidateAt = now
					self.Status = "Arming"
				end
			else
				self._roomChangeSettleAt = nil
			end
			return
		end

		if not inFavourite or not stationary then
			if self._armed then self:_emit("Departure", now) end
			self:_clearTrial()
			if self.Status ~= "Resolved" then self.Status = "Monitoring" end
			return
		end

		if self._candidateAt == nil then
			self._candidateAt = now
			self.Status = "Arming"
			return
		end
		if now - self._candidateAt + 1e-6 >= self.ArmSeconds and not self._armed then
			self._trialSequence = self._trialSequence + 1
			self._activeTrialId = "specter-trial:" .. tostring(self._trialSequence)
			self._armed = true
			self.Status = "Armed"
		end
	end

	function SpecterTrial:_step(now, event)
		if self.Status == "Stopped" or self.Status == "Destroyed" then return false end
		now = number(now) or self:_now(event)
		local hunting = self:_readHunting(event)
		self:_handleHunting(hunting, now)
		if hunting then return true end
		local speed = self:_readMovementSpeed()
		self:_sample(now, speed)
		self:_analyze(now, speed)
		return true
	end

	function SpecterTrial:Start(context)
		if self.Status ~= "Idle" and self.Status ~= "Stopped" then return end
		self._context = context or {}
		self.Status = "Dormant"
		self._lastHunting = self:_readHunting()
		local heartbeat = self._context.Heartbeat
		if heartbeat ~= nil then
			local connection = connect(heartbeat, function()
				self:_step(self:_now())
			end)
			if connection then table.insert(self._connections, connection) end
		elseif type(self._context.ConnectHeartbeat) == "function" then
			local ok, connection = pcall(self._context.ConnectHeartbeat, function()
				self:_step(self:_now())
			end)
			if ok and connection then table.insert(self._connections, connection) end
		end
	end

	function SpecterTrial:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind == Events.Types.HuntStarted then
			self:_handleHunting(true, self:_now(event))
			return true
		elseif kind == Events.Types.HuntEnded then
			self:_handleHunting(false, self:_now(event))
			return true
		elseif kind == Events.Types.Tick then
			return self:_step(self:_now(event), event)
		end
		return false
	end

	function SpecterTrial:Stop()
		for _, connection in ipairs(self._connections) do disconnect(connection) end
		table.clear(self._connections)
		self.Status = "Stopped"
	end

	function SpecterTrial:Reset()
		self:Stop()
		table.clear(self._motionSamples)
		self._lastSampleAt = nil
		self._lastAnalysisAt = nil
		self._lastHunting = nil
		self._candidateAt = nil
		self._armed = false
		self._trackedFavourite = nil
		self._roomChangePause = false
		self._roomChangeSettleAt = nil
		self._trialSequence = 0
		self._activeTrialId = nil
		self._completedTrials = 0
		self._lastOutcome = nil
		self.Status = "Idle"
	end

	function SpecterTrial:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function SpecterTrial:Snapshot()
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			Armed = self._armed,
			CandidateAt = self._candidateAt,
			ActiveTrialId = self._activeTrialId,
			TrackedFavouriteRoom = self._trackedFavourite,
			RoomChangePaused = self._roomChangePause,
			MotionSampleCount = #self._motionSamples,
			CompletedTrials = self._completedTrials,
			LastOutcome = self._lastOutcome,
			ConnectionCount = #self._connections,
		}
	end

	return SpecterTrial
end
