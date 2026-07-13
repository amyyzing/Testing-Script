return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "Coordinator requires Events")
	local EvidenceLedger = assert(dependencies.EvidenceLedger, "Coordinator requires EvidenceLedger")
	local Resolver = assert(dependencies.Resolver, "Coordinator requires Resolver")

	local Coordinator = {}
	Coordinator.__index = Coordinator
	local TRANSIENT_EVENTS = {
		[Events.Types.Tick] = true,
		[Events.Types.WalkSpeedChanged] = true,
		[Events.Types.TransparencyChanged] = true,
		[Events.Types.SpeedPairSample] = true,
	}

	local function values(input)
		local result = {}
		if type(input) ~= "table" then
			return result
		end
		for _, value in pairs(input) do
			table.insert(result, value)
		end
		return result
	end

	local function callSafely(self, owner, method, ...)
		local callback = owner and owner[method]
		if type(callback) ~= "function" then
			return true, nil
		end
		local ok, result = pcall(callback, owner, ...)
		if not ok then
			local failure = {
				Owner = owner.Name or tostring(owner),
				Method = method,
				Error = tostring(result),
				Time = self._clock(),
			}
			table.insert(self._errors, failure)
			if type(self._onError) == "function" then
				self._onError(failure)
			end
		end
		return ok, result
	end

	local function evidenceEvent(event)
		event = type(event) == "table" and event or {}
		return {
			Time = event.Time,
			Source = event.Source,
			EventId = event.Id or event.EventId,
			HuntId = event.HuntId,
			Supersedes = event.Supersedes,
			Tags = event.Tags,
			Details = event.Payload or event.Details,
		}
	end

	function Coordinator.new(options)
		options = type(options) == "table" and options or {}
		local ledger = options.Ledger or EvidenceLedger.new({
			Clock = options.Clock,
			Round = options.Round,
		})
		local self = setmetatable({
			Name = options.Name or "GhostCoordinator",
			Status = "Idle",
			_clock = options.Clock or os.clock,
			_schedule = options.Schedule,
			_onError = options.OnError,
			_onChanged = options.OnChanged,
			_recordEvents = options.RecordEvents ~= false,
			_recordTransientEvents = options.RecordTransientEvents == true,
			_historyLimit = math.max(0, math.floor(tonumber(options.HistoryLimit) or 512)),
			_ledger = ledger,
			_resolver = options.ResolverInstance or Resolver.new(ledger, {Catalog = options.Catalog}),
			_trackers = values(options.Trackers),
			_analyzers = values(options.Analyzers),
			_definitions = values(options.Definitions or options.Profiles),
			_observers = {},
			_eventHistory = {},
			_errors = {},
			_queue = {},
			_dispatching = false,
			_currentEvent = nil,
			_nextEventId = Events.MakeIdFactory("ghost-event-"),
			_hunting = false,
			_huntId = 0,
			_runtimeContext = nil,
			_started = false,
			_destroyed = false,
		}, Coordinator)
		self:_createObservers()
		return self
	end

	Coordinator.New = Coordinator.new

	function Coordinator:_observerApi()
		local coordinator = self
		local api = {}

		function api:Record(name, event)
			local result = coordinator._ledger:Record(name, event)
			coordinator:_notify("Evidence", result)
			return result
		end

		function api:Positive(name, reason, confidence, event)
			local result = coordinator._ledger:Positive(name, reason, confidence, event)
			coordinator:_notify("Evidence", result)
			return result
		end

		function api:Negative(name, reason, confidence, event)
			local result = coordinator._ledger:Negative(name, reason, confidence, event)
			coordinator:_notify("Evidence", result)
			return result
		end

		function api:RuleOut(name, reason, confidence, event)
			local result = coordinator._ledger:RuleOut(name, reason, confidence, event)
			coordinator:_notify("Evidence", result)
			return result
		end

		function api:Supersede(name, previousEvidenceId, polarity, reason, confidence, event)
			event = Events.Copy(type(event) == "table" and event or {})
			event.Supersedes = previousEvidenceId
			if polarity == "Positive" then
				return self:Positive(name, reason, confidence, event)
			elseif polarity == "Negative" then
				return self:Negative(name, reason, confidence, event)
			elseif polarity == "RuleOut" then
				return self:RuleOut(name, reason, confidence, event)
			end
			event.Polarity = polarity or "Observation"
			event.Reason = reason
			event.Confidence = confidence
			return self:Record(name, event)
		end

		function api:Emit(event)
			return coordinator:Emit(event)
		end

		function api:Resolve(name)
			return coordinator._resolver:ResolveGhost(name)
		end

		function api:IsHunting()
			return coordinator._hunting
		end

		function api:HuntId()
			return coordinator._huntId
		end

		return api
	end

	function Coordinator:_notify(kind, payload)
		if type(self._onChanged) ~= "function" then
			return
		end
		local ok, failure = pcall(self._onChanged, kind, Events.Copy(payload), self)
		if not ok then
			table.insert(self._errors, {
				Owner = self.Name,
				Method = "OnChanged",
				Error = tostring(failure),
				Time = self._clock(),
			})
		end
	end

	function Coordinator:_createObservers()
		table.clear(self._observers)
		local api = self:_observerApi()
		for _, definition in ipairs(self._definitions) do
			if type(definition) == "table" and type(definition.CreateObserver) == "function" then
				local ok, observer = pcall(definition.CreateObserver, api)
				if ok and type(observer) == "table" then
					observer.Name = observer.Name or definition.Name
					table.insert(self._observers, observer)
				else
					table.insert(self._errors, {
						Owner = definition.Name or "UnknownProfile",
						Method = "CreateObserver",
						Error = tostring(observer),
						Time = self._clock(),
					})
				end
			end
		end
	end

	function Coordinator:_trackerContext(runtimeContext)
		local context = {}
		for key, value in pairs(type(runtimeContext) == "table" and runtimeContext or {}) do
			context[key] = value
		end
		context.Clock = context.Clock or self._clock
		context.Schedule = context.Schedule or self._schedule
		context.Emit = function(event)
			event = Events.Copy(event)
			if event.ParentId == nil and self._currentEvent then
				event.ParentId = self._currentEvent.Id
			end
			return self:Emit(event)
		end
		return context
	end

	function Coordinator:Start(runtimeContext)
		assert(not self._destroyed, "coordinator has been destroyed")
		if self._started then
			return
		end
		self._runtimeContext = runtimeContext or {}
		self._started = true
		self.Status = "Active"
		local context = self:_trackerContext(self._runtimeContext)
		-- Hold events emitted by one Start() call until every tracker and analyzer
		-- has entered its lifecycle. This keeps discardable one-shot facts visible
		-- to components registered later in the list.
		self._dispatching = true
		for _, tracker in ipairs(self._trackers) do
			callSafely(self, tracker, "Start", context)
		end
		for _, analyzer in ipairs(self._analyzers) do
			callSafely(self, analyzer, "Start", context)
		end
		self._dispatching = true
		while #self._queue > 0 do
			local nextEvent = table.remove(self._queue, 1)
			self:_dispatch(nextEvent)
		end
		self._dispatching = false
	end

	function Coordinator:_normalize(event)
		local normalized = Events.Normalize(event, {
			Time = self._clock,
			HuntId = self._huntId > 0 and self._huntId or nil,
			Hunting = self._hunting,
			ParentId = self._currentEvent and self._currentEvent.Id or nil,
		})
		normalized.Id = normalized.Id or self._nextEventId()
		return normalized
	end

	function Coordinator:_recordNormalizedEvent(event)
		if not self._recordEvents then
			return
		end
		local metadata = evidenceEvent(event)
		self._ledger:Record({
			Polarity = "Observation",
			Reason = event.Type,
			Source = metadata.Source,
			Time = metadata.Time,
			EventId = metadata.EventId,
			HuntId = metadata.HuntId,
			Details = {
				Type = event.Type,
				Aliases = event.Aliases,
				Payload = event.Payload,
			},
		})
	end

	function Coordinator:_shouldRecordEvent(event)
		if not self._recordEvents then
			return false
		end
		if self._recordTransientEvents then
			return true
		end
		return TRANSIENT_EVENTS[event.Type] ~= true
	end

	function Coordinator:_updateHuntState(event)
		if event.Type == Events.Types.HuntStarted then
			self._hunting = true
			self._huntId = tonumber(event.HuntId) or (self._huntId + 1)
			event.HuntId = self._huntId
			event.Hunting = true
		elseif event.Type == Events.Types.HuntEnded then
			event.HuntId = event.HuntId or self._huntId
			event.Hunting = false
			self._hunting = false
		end
	end

	function Coordinator:_dispatch(event)
		self:_updateHuntState(event)
		local recordEvent = self:_shouldRecordEvent(event)
		if recordEvent then
			table.insert(self._eventHistory, Events.Copy(event))
			while #self._eventHistory > self._historyLimit do
				table.remove(self._eventHistory, 1)
			end
			self:_recordNormalizedEvent(event)
		end
		self._currentEvent = event
		for _, tracker in ipairs(self._trackers) do
			callSafely(self, tracker, "OnEvent", event)
		end
		for _, analyzer in ipairs(self._analyzers) do
			callSafely(self, analyzer, "OnEvent", event)
		end
		for _, observer in ipairs(self._observers) do
			callSafely(self, observer, "OnEvent", event)
		end
		self._currentEvent = nil
		if recordEvent then
			self:_notify("Event", event)
		end
	end

	function Coordinator:Emit(event)
		assert(not self._destroyed, "coordinator has been destroyed")
		local normalized = self:_normalize(event)
		table.insert(self._queue, normalized)
		if self._dispatching then
			return normalized.Id
		end
		self._dispatching = true
		while #self._queue > 0 do
			local nextEvent = table.remove(self._queue, 1)
			self:_dispatch(nextEvent)
		end
		self._dispatching = false
		return normalized.Id
	end

	Coordinator.Receive = Coordinator.Emit

	function Coordinator:Resolve(names)
		return self._resolver:Resolve(names)
	end

	function Coordinator:Rank(names, options)
		return self._resolver:Rank(names, options)
	end

	function Coordinator:Ledger()
		return self._ledger
	end

	function Coordinator:Reset(options)
		assert(not self._destroyed, "coordinator has been destroyed")
		local restart = self._started
		for _, tracker in ipairs(self._trackers) do
			callSafely(self, tracker, "Reset")
		end
		for _, analyzer in ipairs(self._analyzers) do
			callSafely(self, analyzer, "Reset")
		end
		for _, observer in ipairs(self._observers) do
			callSafely(self, observer, "Reset")
		end
		self._ledger:Reset(options)
		table.clear(self._eventHistory)
		table.clear(self._errors)
		table.clear(self._queue)
		self._dispatching = false
		self._currentEvent = nil
		self._hunting = false
		self._huntId = 0
		self._nextEventId = Events.MakeIdFactory("ghost-event-")
		self._started = false
		self.Status = "Idle"
		if restart then
			self:Start(self._runtimeContext)
		end
		self:_notify("Reset", {Round = self._ledger:Snapshot().Round})
	end

	function Coordinator:Destroy()
		if self._destroyed then
			return
		end
		for _, tracker in ipairs(self._trackers) do
			callSafely(self, tracker, "Destroy")
		end
		for _, analyzer in ipairs(self._analyzers) do
			callSafely(self, analyzer, "Destroy")
		end
		for _, observer in ipairs(self._observers) do
			callSafely(self, observer, "Destroy")
		end
		table.clear(self._queue)
		self._currentEvent = nil
		self._runtimeContext = nil
		self._started = false
		self._destroyed = true
		self.Status = "Destroyed"
	end

	function Coordinator:Snapshot()
		local trackers = {}
		for _, tracker in ipairs(self._trackers) do
			local ok, snapshot = callSafely(self, tracker, "Snapshot")
			table.insert(trackers, ok and snapshot or {Name = tracker.Name, Status = "SnapshotFailed"})
		end
		local analyzers = {}
		for _, analyzer in ipairs(self._analyzers) do
			local ok, snapshot = callSafely(self, analyzer, "Snapshot")
			table.insert(analyzers, ok and snapshot or {Name = analyzer.Name, Status = "SnapshotFailed"})
		end
		local observers = {}
		for _, observer in ipairs(self._observers) do
			local ok, snapshot = callSafely(self, observer, "Snapshot")
			table.insert(observers, ok and snapshot or {Name = observer.Name, Status = "SnapshotFailed"})
		end
		return {
			Name = self.Name,
			Status = self.Status,
			Hunting = self._hunting,
			HuntId = self._huntId,
			Events = Events.Copy(self._eventHistory),
			Errors = Events.Copy(self._errors),
			Ledger = self._ledger:Snapshot(),
			Resolver = self._resolver:Snapshot(),
			Trackers = trackers,
			Analyzers = analyzers,
			Observers = observers,
		}
	end

	return Coordinator
end
