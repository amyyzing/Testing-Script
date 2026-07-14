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

function RoomTemperature.new(options)
	options = type(options) == "table" and options or {}
	return setmetatable({
		Name = options.Name or "RoomTemperature",
		Category = "Dormant",
		Status = "Idle",
		SampleInterval = tonumber(options.SampleInterval) or 0.25,
		ResidenceSeconds = tonumber(options.ResidenceSeconds) or 5,
		RequiredSamples = math.max(2, math.floor(tonumber(options.RequiredSamples) or 20)),
		DropThreshold = tonumber(options.DropThreshold) or 0.2,
		_context = nil,
		_roomName = nil,
		_enteredAt = nil,
		_lastSampleAt = nil,
		_samples = {},
		_maxDecreaseStep = 0,
		_windowEmitted = false,
		_normalDropEmitted = false,
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
	if type(self._context.Emit) == "function" then
		self._context.Emit(event)
	end
end

function RoomTemperature:_clearResidence(status)
	self._roomName = nil
	self._enteredAt = nil
	self._lastSampleAt = nil
	table.clear(self._samples)
	self._maxDecreaseStep = 0
	self._windowEmitted = false
	self._normalDropEmitted = false
	self.Status = status or "Dormant"
end

function RoomTemperature:_beginResidence(roomName, now)
	self._roomName = roomName
	self._enteredAt = now
	self._lastSampleAt = nil
	table.clear(self._samples)
	self._maxDecreaseStep = 0
	self._windowEmitted = false
	self._normalDropEmitted = false
	self.Status = "Sampling"
end

function RoomTemperature:_restartForMissingTemperature(now)
	self._enteredAt = now
	self._lastSampleAt = nil
	table.clear(self._samples)
	self._maxDecreaseStep = 0
	self._windowEmitted = false
	self._normalDropEmitted = false
	self.Status = "WaitingForTemperature"
end

function RoomTemperature:_readRoomName(event)
	local roomName = Events.Read(event, "CurrentRoom")
	if roomName == nil and type(self._context.ReadCurrentRoom) == "function" then
		roomName = self._context.ReadCurrentRoom()
	end
	if roomName == nil or tostring(roomName) == "" then
		return nil
	end
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
	local normalDrop = self._maxDecreaseStep + 1e-6 >= self.DropThreshold
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
			MaxDecreaseStep = self._maxDecreaseStep,
			DropThreshold = self.DropThreshold,
			NormalDropObserved = normalDrop,
			IncreasesIgnored = true,
		},
	})
	self._windowEmitted = true
	if normalDrop then
		self._normalDropEmitted = true
		self.Status = "Resolved"
	else
		self.Status = "Monitoring"
	end
end

function RoomTemperature:_sample(now, temperature)
	if self._lastSampleAt
		and now - self._lastSampleAt + 1e-6 < self.SampleInterval then
		return
	end
	self._lastSampleAt = now
	local previous = self._samples[#self._samples]
	if previous then
		local decrease = previous.Temperature - temperature
		-- Positive values are temperature drops. Increases and unchanged readings
		-- are deliberately ignored rather than being treated as counter-evidence.
		if decrease > 0 then
			self._maxDecreaseStep = math.max(self._maxDecreaseStep, decrease)
		end
	end
	table.insert(self._samples, {
		Time = now,
		Temperature = temperature,
	})
	while #self._samples > self.RequiredSamples do
		table.remove(self._samples, 1)
	end

	local residence = now - (self._enteredAt or now)
	local qualified = residence + 1e-6 >= self.ResidenceSeconds
		and #self._samples >= self.RequiredSamples
	if not qualified then
		return
	end
	local normalDrop = self._maxDecreaseStep + 1e-6 >= self.DropThreshold
	if not self._windowEmitted
		or (normalDrop and not self._normalDropEmitted) then
		self:_emitWindow(now)
	end
end

function RoomTemperature:OnEvent(event)
	if type(event) ~= "table"
		or (event.Type or event.Kind) ~= Events.Types.Tick then
		return false
	end
	local now = self:_now(event)
	local roomName = self:_readRoomName(event)
	if not roomName then
		self:_clearResidence("Dormant")
		return true
	end
	if roomName ~= self._roomName then
		self:_beginResidence(roomName, now)
	end
	local temperature = self:_readTemperature(event, roomName)
	if temperature == nil then
		self:_restartForMissingTemperature(now)
		return true
	end
	self:_sample(now, temperature)
	return true
end

function RoomTemperature:Stop()
	self:_clearResidence("Stopped")
end

function RoomTemperature:Reset()
	self:_clearResidence("Idle")
end

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
		MaxDecreaseStep = self._maxDecreaseStep,
		WindowEmitted = self._windowEmitted,
		NormalDropEmitted = self._normalDropEmitted,
	}
end

return RoomTemperature
end
