return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "RoomTemperature requires Events")
	local RoomTemperature = {}
	RoomTemperature.__index = RoomTemperature

local function copySamples(samples)
	local result = {}
	for index, sample in ipairs(samples) do
		result[index] = {
			Time = sample.Time,
			Temperature = sample.Temperature,
		}
	end
	return result
end

local function copyStats(stats)
	if type(stats) ~= "table" then return nil end
	local result = {}
	for key, value in pairs(stats) do result[key] = value end
	return result
end

local function windowStats(samples)
	local sum = 0
	local count = 0
	local minimum = nil
	local maximum = nil
	local ignoredIncreases = 0
	local ignoredUnchanged = 0
	for index = 2, #samples do
		local decrease = samples[index - 1].Temperature - samples[index].Temperature
		-- Only strict cooling changes belong in the average. Increasing and
		-- unchanged pairs are recorded separately and excluded from its divisor.
		if decrease > 0 then
			sum = sum + decrease
			count = count + 1
			minimum = minimum and math.min(minimum, decrease) or decrease
			maximum = maximum and math.max(maximum, decrease) or decrease
		elseif decrease < 0 then
			ignoredIncreases = ignoredIncreases + 1
		else
			ignoredUnchanged = ignoredUnchanged + 1
		end
	end
	return {
		AverageDecrease = count > 0 and sum / count or nil,
		MinimumDecrease = minimum,
		MaximumDecrease = maximum,
		DecreaseSum = sum,
		DecreaseCount = count,
		IgnoredIncreaseCount = ignoredIncreases,
		IgnoredUnchangedCount = ignoredUnchanged,
		ChangeCount = math.max(0, #samples - 1),
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
		RequiredSamples = math.max(2, math.floor(tonumber(options.RequiredSamples) or 20)),
		MinimumCoolingChanges = math.max(3, math.floor(tonumber(options.MinimumCoolingChanges) or 3)),
		ShadowAverageThreshold = tonumber(options.ShadowAverageThreshold) or 0.05,
		RuleOutAverageThreshold = tonumber(options.RuleOutAverageThreshold) or 0.06,
		_context = nil,
		_roomName = nil,
		_enteredAt = nil,
		_lastSampleAt = nil,
		_samples = {},
		_lastStats = nil,
		_windowCount = 0,
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

function RoomTemperature:_clearResidence(status)
	self._roomName = nil
	self._enteredAt = nil
	self._lastSampleAt = nil
	table.clear(self._samples)
	self._lastStats = nil
	self._windowCount = 0
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
	table.clear(self._samples)
	self._lastStats = nil
	self._windowCount = 0
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

function RoomTemperature:_emitWindow(now)
	local residence = math.max(0, now - (self._enteredAt or now))
	local stats = windowStats(self._samples)
	local average = stats.AverageDecrease
	-- Keep the full floating-point values. The epsilon only absorbs binary
	-- representation noise at the exact decimal boundaries; nothing is rounded.
	-- Decisions use only a sufficiently populated average. Individual cooling
	-- outliers remain in that average and cannot independently force or veto it.
	local sufficientCoolingChanges =
		stats.DecreaseCount >= self.MinimumCoolingChanges
	local shadowObserved = sufficientCoolingChanges and average ~= nil
		and average < self.ShadowAverageThreshold - 1e-9
	local ruleOutObserved = sufficientCoolingChanges and average ~= nil
		and average > self.RuleOutAverageThreshold + 1e-9
	local outcome = shadowObserved and "Shadow"
		or (ruleOutObserved and "RuleOut" or "Inconclusive")
	stats.ShadowPatternObserved = shadowObserved
	stats.RuleOutPatternObserved = ruleOutObserved
	stats.SufficientCoolingChanges = sufficientCoolingChanges
	stats.Outcome = outcome
	self._lastStats = stats
	self._windowCount = self._windowCount + 1
	self:_emit({
		Type = Events.Types.RoomTemperatureWindow,
		Source = self.Name,
		Payload = {
			RoomName = self._roomName,
			SameRoom = true,
			Qualified = true,
			ResidenceSeconds = residence,
			SampleCount = #self._samples,
			Samples = copySamples(self._samples),
			AverageDecrease = stats.AverageDecrease,
			MinimumDecrease = stats.MinimumDecrease,
			MaximumDecrease = stats.MaximumDecrease,
			DecreaseSum = stats.DecreaseSum,
			DecreaseCount = stats.DecreaseCount,
			ChangeCount = stats.ChangeCount,
			IgnoredIncreaseCount = stats.IgnoredIncreaseCount,
			IgnoredUnchangedCount = stats.IgnoredUnchangedCount,
			ShadowAverageThreshold = self.ShadowAverageThreshold,
			RuleOutAverageThreshold = self.RuleOutAverageThreshold,
			MinimumCoolingChanges = self.MinimumCoolingChanges,
			SufficientCoolingChanges = sufficientCoolingChanges,
			Outcome = outcome,
			ShadowPatternObserved = shadowObserved,
			RuleOutPatternObserved = ruleOutObserved,
			IncreasesIgnored = true,
			UnchangedIgnored = true,
			Unrounded = true,
			Window = self._windowCount,
		},
	})
	self._resolved = shadowObserved or ruleOutObserved
	if self._resolved then
		self.Status = "Resolved"
	else
		-- Start a fresh independent set instead of emitting a sliding window on
		-- every quarter-second tick.
		table.clear(self._samples)
		self.Status = "Monitoring"
	end
end

function RoomTemperature:_sample(now, temperature)
	if self._resolved then return end
	if self._lastSampleAt
		and now - self._lastSampleAt + 1e-6 < self.SampleInterval then return end
	self._lastSampleAt = now
	table.insert(self._samples, {Time = now, Temperature = temperature})
	while #self._samples > self.RequiredSamples do table.remove(self._samples, 1) end
	local residence = now - (self._enteredAt or now)
	if residence + 1e-6 >= self.ResidenceSeconds
		and #self._samples >= self.RequiredSamples then
		self:_emitWindow(now)
	end
end

function RoomTemperature:OnEvent(event)
	if type(event) ~= "table"
		or (event.Type or event.Kind) ~= Events.Types.Tick then return false end
	local now = self:_now(event)
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

function RoomTemperature:Stop() self:_clearResidence("Stopped") end
function RoomTemperature:Reset() self:_clearResidence("Idle") end

function RoomTemperature:Destroy()
	self:_clearResidence("Destroyed")
	self._context = nil
end

function RoomTemperature:Snapshot()
	return {
		Name = self.Name,
		Category = self.Category,
		Status = self.Status,
		RoomName = self._roomName,
		ResidenceSeconds = self._enteredAt and math.max(
			0,
			(self._context and self._context.Clock and self._context.Clock() or os.clock())
				- self._enteredAt
		) or 0,
		SampleCount = #self._samples,
		WindowCount = self._windowCount,
		LastStats = copyStats(self._lastStats),
		ShadowAverageThreshold = self.ShadowAverageThreshold,
		RuleOutAverageThreshold = self.RuleOutAverageThreshold,
		MinimumCoolingChanges = self.MinimumCoolingChanges,
		Resolved = self._resolved,
	}
end

return RoomTemperature
end
