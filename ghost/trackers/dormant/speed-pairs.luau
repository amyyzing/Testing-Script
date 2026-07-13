return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "SpeedPairs requires Events")
	local SpeedPairs = {}
	SpeedPairs.__index = SpeedPairs

local function copyArray(values)
	local result = {}
	for index, value in ipairs(values) do
		local item = {}
		for key, field in pairs(value) do
			item[key] = field
		end
		result[index] = item
	end
	return result
end

local function schedule(context, delaySeconds, callback)
	if type(context.Schedule) == "function" then
		return context.Schedule(delaySeconds, callback)
	end
	if task and type(task.delay) == "function" then
		local cancelled = false
		task.delay(delaySeconds, function()
			if not cancelled then
				callback()
			end
		end)
		return function()
			cancelled = true
		end
	end
	callback()
	return function() end
end

local function readSpeed(context, event)
	local explicit = tonumber(
		Events.Read(event, "SettledSpeed")
			or Events.Read(event, "CurrentSpeed")
	)
	if explicit then
		return explicit
	end
	if type(context.ReadWalkSpeed) == "function" then
		return tonumber(context.ReadWalkSpeed())
	end
	return tonumber(Events.Read(event, "Speed") or Events.Read(event, "WalkSpeed"))
end

function SpeedPairs.new(options)
	options = type(options) == "table" and options or {}
	return setmetatable({
		Name = options.Name or "SpeedPairs",
		Category = "Dormant",
		Status = "Idle",
		SettleDelay = tonumber(options.SettleDelay) or 0.095,
		_context = nil,
		_hunting = false,
		_huntId = nil,
		_lastInvisible = nil,
		_token = 0,
		_cancelPending = nil,
		_samples = {},
		_sampleSerial = 0,
		_windowCount = 0,
		_huntMeta = {},
	}, SpeedPairs)
end

SpeedPairs.New = SpeedPairs.new

function SpeedPairs:Start(context)
	self._context = context or {}
	self.Status = "Dormant"
end

function SpeedPairs:_emit(event)
	if type(self._context.Emit) == "function" then
		self._context.Emit(event)
	end
end

function SpeedPairs:_cancelSettledRead()
	self._token = self._token + 1
	if type(self._cancelPending) == "function" then
		self._cancelPending()
	end
	self._cancelPending = nil
end

function SpeedPairs:_beginHunt(event)
	self:_cancelSettledRead()
	self._hunting = true
	self._huntId = event.HuntId
	self.Status = "Active"
	table.clear(self._samples)
	self._sampleSerial = 0
	self._windowCount = 0
	self._huntMeta = {
		AverageSanity = Events.Read(event, "AverageSanity"),
		MapFactor = Events.Read(event, "MapFactor"),
		MapSize = Events.Read(event, "MapSize"),
		ValidMultipliers = Events.Read(event, "ValidMultipliers"),
	}
	local initial = Events.Read(event, "Transparency")
	if initial == nil and type(self._context.ReadTransparency) == "function" then
		initial = self._context.ReadTransparency()
	end
	local qualified, invisible = Events.IsBinaryTransparency(initial)
	if qualified then
		self._lastInvisible = invisible
	else
		self._lastInvisible = nil
	end
end

function SpeedPairs:_endHunt()
	self:_cancelSettledRead()
	self._hunting = false
	self._huntId = nil
	self._lastInvisible = nil
	self.Status = "Dormant"
	table.clear(self._samples)
	table.clear(self._huntMeta)
end

function SpeedPairs:_recordSample(invisible, event, token)
	if not self._hunting or token ~= self._token or invisible ~= self._lastInvisible then
		return
	end
	local speed = readSpeed(self._context, event)
	if not speed or speed <= 0 then
		return
	end
	self._sampleSerial = self._sampleSerial + 1
	local sample = {
		SampleId = tostring(self._huntId or "hunt") .. ":" .. tostring(self._sampleSerial),
		HuntId = self._huntId,
		Invisible = invisible,
		Speed = speed,
		Time = self._context.Clock and self._context.Clock() or os.clock(),
	}
	table.insert(self._samples, sample)
	self:_emit({
		Type = Events.Types.SpeedPairSample,
		HuntId = self._huntId,
		Hunting = true,
		Source = self.Name,
		Payload = sample,
	})

	if #self._samples < 4 then
		return
	end
	local startIndex = #self._samples - 3
	local window = {}
	for index = startIndex, #self._samples do
		table.insert(window, self._samples[index])
	end
	local alternating = true
	for index = 2, #window do
		if window[index].Invisible == window[index - 1].Invisible then
			alternating = false
			break
		end
	end
	if alternating then
		self._windowCount = self._windowCount + 1
		local payload = {
			Samples = copyArray(window),
			SampleCount = #window,
			Window = self._windowCount,
			AverageSanity = self._huntMeta.AverageSanity,
			MapFactor = self._huntMeta.MapFactor,
			MapSize = self._huntMeta.MapSize,
			ValidMultipliers = self._huntMeta.ValidMultipliers,
		}
		self:_emit({
			Type = Events.Types.SpeedPairWindow,
			HuntId = self._huntId,
			Hunting = true,
			Source = self.Name,
			Payload = payload,
		})
	end
	-- Retain the last pair so the next two transitions form a fresh two-cycle window.
	self._samples = {self._samples[#self._samples - 1], self._samples[#self._samples]}
end

function SpeedPairs:OnEvent(event)
	if type(event) ~= "table" then
		return
	end
	local kind = event.Type or event.Kind
	if kind == Events.Types.HuntStarted then
		self:_beginHunt(event)
		return
	elseif kind == Events.Types.HuntEnded then
		if self._hunting and (event.HuntId == nil or event.HuntId == self._huntId) then
			self:_endHunt()
		end
		return
	end
	if kind ~= Events.Types.TransparencyChanged
		or not self._hunting
		or event.Hunting == false
		or (event.HuntId ~= nil and event.HuntId ~= self._huntId) then
		return
	end

	local qualified, invisible = Events.IsBinaryTransparency(Events.Read(event, "Transparency"))
	if not qualified then
		return
	end
	if self._lastInvisible == nil then
		self._lastInvisible = invisible
		return
	end
	if invisible == self._lastInvisible then
		return
	end

	self:_cancelSettledRead()
	self._lastInvisible = invisible
	local token = self._token
	self._cancelPending = schedule(self._context, self.SettleDelay, function()
		self._cancelPending = nil
		self:_recordSample(invisible, event, token)
	end)
end

function SpeedPairs:Stop()
	self:_endHunt()
	self.Status = "Stopped"
end

function SpeedPairs:Reset()
	self:_cancelSettledRead()
	self._hunting = false
	self._huntId = nil
	self._lastInvisible = nil
	table.clear(self._samples)
	table.clear(self._huntMeta)
	self._sampleSerial = 0
	self._windowCount = 0
	self.Status = "Idle"
end

function SpeedPairs:Destroy()
	self:Reset()
	self._context = nil
	self.Status = "Destroyed"
end

function SpeedPairs:Snapshot()
	return {
		Name = self.Name,
		Category = self.Category,
		Status = self.Status,
		Hunting = self._hunting,
		HuntId = self._huntId,
		LastInvisible = self._lastInvisible,
		Samples = copyArray(self._samples),
		WindowCount = self._windowCount,
		PendingSettledRead = self._cancelPending ~= nil,
	}
end

	return SpeedPairs
end
