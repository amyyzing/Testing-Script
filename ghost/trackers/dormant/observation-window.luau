local ObservationWindow = {}
ObservationWindow.__index = ObservationWindow

local function asSet(values)
	local result = {}
	for _, value in ipairs(type(values) == "table" and values or {}) do
		result[value] = true
	end
	return result
end

function ObservationWindow.new(options)
	options = type(options) == "table" and options or {}
	return setmetatable({
		Name = options.Name or "ObservationWindow",
		Category = "Dormant",
		Status = "Idle",
		Duration = tonumber(options.Duration) or 1,
		TriggerTypes = asSet(options.TriggerTypes),
		WatchTypes = asSet(options.WatchTypes),
		Qualify = options.Qualify,
		Reduce = options.Reduce,
		Complete = options.Complete,
		BuildResult = options.BuildResult,
		ResultType = options.ResultType or "ObservationWindowResult",
		_context = nil,
		_windows = {},
		_serial = 0,
	}, ObservationWindow)
end

ObservationWindow.New = ObservationWindow.new

function ObservationWindow:Start(context)
	self._context = context or {}
	self.Status = "Dormant"
end

function ObservationWindow:_now(event)
	return tonumber(event.Time) or (self._context.Clock and self._context.Clock() or os.clock())
end

function ObservationWindow:_emit(event)
	if type(self._context.Emit) == "function" then
		self._context.Emit(event)
	end
end

function ObservationWindow:_open(event)
	if type(self.Qualify) == "function" and self.Qualify(event) ~= true then
		return
	end
	self._serial = self._serial + 1
	local id = tostring(event.Id or self.Name .. ":" .. tostring(self._serial))
	self._windows[id] = {
		Id = id,
		Trigger = event,
		OpenedAt = self:_now(event),
		HuntId = event.HuntId,
		State = {},
	}
	self.Status = "Active"
end

function ObservationWindow:_close(id, outcome, event)
	local window = self._windows[id]
	if not window then
		return
	end
	self._windows[id] = nil
	local payload = type(self.BuildResult) == "function"
		and self.BuildResult(window, outcome, event)
		or {
			WindowId = id,
			Outcome = outcome,
			State = window.State,
			TriggerEventId = window.Trigger.Id,
		}
	self:_emit({
		Type = self.ResultType,
		HuntId = window.HuntId,
		Source = self.Name,
		Payload = payload,
	})
	if next(self._windows) == nil then
		self.Status = "Dormant"
	end
end

function ObservationWindow:_tick(event)
	local now = self:_now(event)
	local expired = {}
	for id, window in pairs(self._windows) do
		if now - window.OpenedAt >= self.Duration then
			table.insert(expired, id)
		end
	end
	for _, id in ipairs(expired) do
		self:_close(id, "Expired", event)
	end
end

function ObservationWindow:OnEvent(event)
	if type(event) ~= "table" then
		return
	end
	local kind = event.Type or event.Kind
	if self.TriggerTypes[kind] then
		self:_open(event)
	end
	if self.WatchTypes[kind] then
		local completed = {}
		for id, window in pairs(self._windows) do
			if window.HuntId == nil or event.HuntId == nil or window.HuntId == event.HuntId then
				if type(self.Reduce) == "function" then
					self.Reduce(window, event)
				end
				if type(self.Complete) == "function" and self.Complete(window, event) == true then
					table.insert(completed, id)
				end
			end
		end
		for _, id in ipairs(completed) do
			self:_close(id, "Completed", event)
		end
	end
	if kind == "Tick" then
		self:_tick(event)
	end
end

function ObservationWindow:Stop()
	table.clear(self._windows)
	self.Status = "Stopped"
end

function ObservationWindow:Reset()
	table.clear(self._windows)
	self._serial = 0
	self.Status = "Idle"
end

function ObservationWindow:Destroy()
	self:Reset()
	self._context = nil
	self.Status = "Destroyed"
end

function ObservationWindow:Snapshot()
	local count = 0
	for _ in pairs(self._windows) do
		count = count + 1
	end
	return {
		Name = self.Name,
		Category = self.Category,
		Status = self.Status,
		OpenWindowCount = count,
	}
end

return ObservationWindow
