return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "RoomTemperature requires Events")
	local RoomTemperature = {}
	RoomTemperature.__index = RoomTemperature

	local function copyChanges(changes)
		local result = {}
		for index, change in ipairs(changes) do
			result[index] = {
				Time = change.Time,
				Elapsed = change.Elapsed,
				From = change.From,
				To = change.To,
				Decrease = change.Decrease,
			}
		end
		return result
	end

	local function copyStats(stats)
		if type(stats) ~= "table" then return nil end
		local result = {}
		for key, value in pairs(stats) do
			result[key] = type(value) == "table" and copyChanges(value) or value
		end
		return result
	end

	local function windowStats(changes, ignoredIncreases, ignoredUnchanged)
		local sum = 0
		local minimum = nil
		local maximum = nil
		for _, change in ipairs(changes) do
			local decrease = change.Decrease
			sum = sum + decrease
			minimum = minimum and math.min(minimum, decrease) or decrease
			maximum = maximum and math.max(maximum, decrease) or decrease
		end
		local count = #changes
		return {
			AverageDecrease = count > 0 and sum / count or nil,
			MinimumDecrease = minimum,
			MaximumDecrease = maximum,
			DecreaseSum = sum,
			DecreaseCount = count,
			IgnoredIncreaseCount = ignoredIncreases,
			IgnoredUnchangedCount = ignoredUnchanged,
			CoolingChanges = copyChanges(changes),
		}
	end

	function RoomTemperature.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "RoomTemperature",
			Category = "Dormant",
			Status = "Idle",
			SampleInterval = tonumber(options.SampleInterval) or 0.25,
			ResidenceSeconds = tonumber(options.ResidenceSeconds) or 5,
			RequiredCoolingChanges = math.max(
				20,
				math.floor(tonumber(options.RequiredCoolingChanges) or 20)
			),
			RequiredRuleOutWindows = math.max(
				2,
				math.floor(tonumber(options.RequiredRuleOutWindows) or 2)
			),
			ShadowAverageThreshold = tonumber(options.ShadowAverageThreshold) or 0.06,
			RuleOutAverageThreshold = tonumber(options.RuleOutAverageThreshold) or 0.08,
			_context = nil,
			_roundStarted = false,
			_roomName = nil,
			_enteredAt = nil,
			_lastSampleAt = nil,
			_previousTemperature = nil,
			_previousTemperatureAt = nil,
			_readingCount = 0,
			_coolingChanges = {},
			_ignoredIncreases = 0,
			_ignoredUnchanged = 0,
			_lastStats = nil,
			_windowCount = 0,
			_ruleOutStreak = 0,
			_resolved = false,
		}, RoomTemperature)
	end

	RoomTemperature.New = RoomTemperature.new

	function RoomTemperature:Start(context)
		self._context = context or {}
		self.Status = "Dormant"
	end

	function RoomTemperature:_now(event)
		return tonumber(event and event.Time)
			or (self._context.Clock and self._context.Clock() or os.clock())
	end

	function RoomTemperature:_emit(event)
		if type(self._context.Emit) == "function" then self._context.Emit(event) end
	end

	function RoomTemperature:_resetWindow(baseline, baselineAt)
		self._previousTemperature = baseline
		self._previousTemperatureAt = baselineAt
		self._readingCount = baseline ~= nil and 1 or 0
		table.clear(self._coolingChanges)
		self._ignoredIncreases = 0
		self._ignoredUnchanged = 0
	end

	function RoomTemperature:_clearResidence(status)
		self._roomName = nil
		self._enteredAt = nil
		self._lastSampleAt = nil
		self:_resetWindow(nil, nil)
		self._lastStats = nil
		self._windowCount = 0
		self._ruleOutStreak = 0
		self._resolved = false
		self.Status = status or "Dormant"
	end

	function RoomTemperature:_beginResidence(roomName, now)
		self:_clearResidence("Sampling")
		self._roomName = roomName
		self._enteredAt = now
	end

	function RoomTemperature:_restartForMissingTemperature(now)
		self._enteredAt = now
		self._lastSampleAt = nil
		self:_resetWindow(nil, nil)
		self._lastStats = nil
		self._windowCount = 0
		self._ruleOutStreak = 0
		self._resolved = false
		self.Status = "WaitingForTemperature"
	end

	function RoomTemperature:_readRoomName(event)
		local roomName = Events.Read(event, "CurrentRoom")
		if roomName == nil and type(self._context.ReadCurrentRoom) == "function" then
			roomName = self._context.ReadCurrentRoom()
		end
		if roomName == nil or tostring(roomName) == "" then return nil end
		return tostring(roomName)
	end

	function RoomTemperature:_readTemperature(event, roomName)
		local temperature = tonumber(Events.Read(event, "RoomTemperature"))
		if temperature == nil and type(self._context.ReadRoomTemperature) == "function" then
			temperature = tonumber(self._context.ReadRoomTemperature(roomName))
		end
		return temperature
	end

	function RoomTemperature:_readRoundStarted(event)
		local started = Events.Read(event, "RoundStarted")
		if type(started) ~= "boolean"
			and type(self._context.ReadRoundStarted) == "function" then
			started = self._context.ReadRoundStarted()
		end
		return started == true
	end

	function RoomTemperature:_emitWindow(now)
		local residence = math.max(0, now - (self._enteredAt or now))
		local stats = windowStats(
			self._coolingChanges,
			self._ignoredIncreases,
			self._ignoredUnchanged
		)
		local average = stats.AverageDecrease
		local shadowObserved = average ~= nil
			and average < self.ShadowAverageThreshold - 1e-9
		local highAverage = average ~= nil
			and average > self.RuleOutAverageThreshold + 1e-9
		if highAverage then
			self._ruleOutStreak = self._ruleOutStreak + 1
		else
			self._ruleOutStreak = 0
		end
		local ruleOutObserved = highAverage
			and self._ruleOutStreak >= self.RequiredRuleOutWindows
		local outcome = shadowObserved and "Shadow"
			or (ruleOutObserved and "RuleOut"
				or (highAverage and "RuleOutCandidate" or "Inconclusive"))
		stats.Outcome = outcome
		stats.HighAverage = highAverage
		stats.RuleOutStreak = self._ruleOutStreak
		stats.RequiredRuleOutWindows = self.RequiredRuleOutWindows
		self._lastStats = stats
		self._windowCount = self._windowCount + 1
		self:_emit({
			Type = Events.Types.RoomTemperatureWindow,
			Source = self.Name,
			Payload = {
				RoomName = self._roomName,
				SameRoom = true,
				Qualified = true,
				Completed = true,
				ResidenceSeconds = residence,
				ReadingCount = self._readingCount,
				SampleCount = stats.DecreaseCount,
				CoolingChanges = stats.CoolingChanges,
				AverageDecrease = stats.AverageDecrease,
				MinimumDecrease = stats.MinimumDecrease,
				MaximumDecrease = stats.MaximumDecrease,
				DecreaseSum = stats.DecreaseSum,
				DecreaseCount = stats.DecreaseCount,
				IgnoredIncreaseCount = stats.IgnoredIncreaseCount,
				IgnoredUnchangedCount = stats.IgnoredUnchangedCount,
				RequiredCoolingChanges = self.RequiredCoolingChanges,
				RequiredRuleOutWindows = self.RequiredRuleOutWindows,
				RuleOutStreak = self._ruleOutStreak,
				HighAverage = highAverage,
				Outcome = outcome,
				ShadowPatternObserved = shadowObserved,
				RuleOutPatternObserved = ruleOutObserved,
				ShadowAverageThreshold = self.ShadowAverageThreshold,
				RuleOutAverageThreshold = self.RuleOutAverageThreshold,
				IncreasesIgnored = true,
				UnchangedIgnored = true,
				Unrounded = true,
				Window = self._windowCount,
			},
		})
		self._resolved = shadowObserved or ruleOutObserved
		if self._resolved then
			self.Status = "Resolved"
			return
		end
		local baseline = self._previousTemperature
		local baselineAt = self._previousTemperatureAt
		self:_resetWindow(baseline, baselineAt)
		self.Status = highAverage and "RuleOutCandidate" or "Monitoring"
	end

	function RoomTemperature:_sample(now, temperature)
		if self._resolved then return end
		if self._lastSampleAt
			and now - self._lastSampleAt + 1e-6 < self.SampleInterval then return end
		self._lastSampleAt = now
		self._readingCount = self._readingCount + 1
		if self._previousTemperature ~= nil then
			local decrease = self._previousTemperature - temperature
			if decrease > 0 then
				table.insert(self._coolingChanges, {
					Time = now,
					Elapsed = math.max(0, now - (self._previousTemperatureAt or now)),
					From = self._previousTemperature,
					To = temperature,
					Decrease = decrease,
				})
			elseif decrease < 0 then
				self._ignoredIncreases = self._ignoredIncreases + 1
			else
				self._ignoredUnchanged = self._ignoredUnchanged + 1
			end
		end
		self._previousTemperature = temperature
		self._previousTemperatureAt = now
		local residence = now - (self._enteredAt or now)
		if residence + 1e-6 >= self.ResidenceSeconds
			and #self._coolingChanges >= self.RequiredCoolingChanges then
			self:_emitWindow(now)
		end
	end

	function RoomTemperature:OnEvent(event)
		if type(event) ~= "table"
			or (event.Type or event.Kind) ~= Events.Types.Tick then return false end
		local now = self:_now(event)
		if not self._roundStarted then
			if not self:_readRoundStarted(event) then
				self:_clearResidence("WaitingForRoundStart")
				return true
			end
			-- Latch the first open state. Closing the exit door again must not
			-- turn a running investigation back into setup-phase sampling.
			self._roundStarted = true
		end
		local roomName = self:_readRoomName(event)
		if not roomName then
			self:_clearResidence("Dormant")
			return true
		end
		if roomName ~= self._roomName then self:_beginResidence(roomName, now) end
		local temperature = self:_readTemperature(event, roomName)
		if temperature == nil then
			self:_restartForMissingTemperature(now)
			return true
		end
		self:_sample(now, temperature)
		return true
	end

	function RoomTemperature:Stop()
		self._roundStarted = false
		self:_clearResidence("Stopped")
	end
	function RoomTemperature:Reset()
		self._roundStarted = false
		self:_clearResidence("Idle")
	end

	function RoomTemperature:Destroy()
		self._roundStarted = false
		self:_clearResidence("Destroyed")
		self._context = nil
	end

	function RoomTemperature:Snapshot()
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			RoundStarted = self._roundStarted,
			RoomName = self._roomName,
			ResidenceSeconds = self._enteredAt and math.max(
				0,
				(self._context and self._context.Clock and self._context.Clock() or os.clock())
					- self._enteredAt
			) or 0,
			ReadingCount = self._readingCount,
			CoolingChangeCount = #self._coolingChanges,
			WindowCount = self._windowCount,
			RuleOutStreak = self._ruleOutStreak,
			LastStats = copyStats(self._lastStats),
			ShadowAverageThreshold = self.ShadowAverageThreshold,
			RuleOutAverageThreshold = self.RuleOutAverageThreshold,
			RequiredCoolingChanges = self.RequiredCoolingChanges,
			RequiredRuleOutWindows = self.RequiredRuleOutWindows,
			Resolved = self._resolved,
		}
	end

	return RoomTemperature
end
