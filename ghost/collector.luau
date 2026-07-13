-- Lifecycle-safe raw observation collection for the per-ghost runtime.
--
-- Roblox-specific adapters own Workspace scanning and feed facts into this
-- collector.  The collector normalizes, buffers, and routes those facts; it
-- deliberately contains no detect/rule-out policy.

return function(dependencies)
	dependencies = dependencies or {}

	local runtime = assert(
		dependencies.Runtime,
		"ghost/collector.luau requires Runtime"
	)
	assert(type(runtime) == "table", "Runtime must be a table")
	assert(type(runtime.Dispatch) == "function", "Runtime requires Dispatch")
	assert(type(runtime.Tick) == "function", "Runtime requires Tick")
	assert(type(runtime.Reset) == "function", "Runtime requires Reset")
	assert(type(runtime.SetMode) == "function", "Runtime requires SetMode")

	local clock = dependencies.Clock or os.clock
	local onError = dependencies.OnError
	local onEvent = dependencies.OnEvent
	local maxSpeedSamples = math.max(
		8,
		math.floor(tonumber(dependencies.MaxSpeedSamples) or 256)
	)
	local sampleInterval = tonumber(dependencies.SampleInterval) or 0.1
	local glassWindow = math.max(
		0.1,
		tonumber(dependencies.GlassWindow) or 2.5
	)
	local destroyRuntime = dependencies.DestroyRuntime ~= false

	assert(type(clock) == "function", "Clock must be a function")
	assert(onError == nil or type(onError) == "function", "OnError must be a function")
	assert(onEvent == nil or type(onEvent) == "function", "OnEvent must be a function")

	local destroyed = false
	local connections = {}
	local state = {}

	local function tracebackError(message)
		return debug.traceback(tostring(message), 2)
	end

	local function reportError(message, context)
		if not onError then
			error(message, 0)
		end

		local ok, callbackError = xpcall(function()
			onError(message, context)
		end, tracebackError)
		if not ok then
			error(callbackError, 0)
		end
	end

	local function copyValue(value, seen)
		if type(value) ~= "table" then
			return value
		end
		seen = seen or {}
		if seen[value] then
			return seen[value]
		end
		local copy = {}
		seen[value] = copy
		for key, nestedValue in pairs(value) do
			copy[copyValue(key, seen)] = copyValue(nestedValue, seen)
		end
		return copy
	end

	local function copyEvent(event)
		return copyValue(type(event) == "table" and event or {})
	end

	local function eventTime(event)
		return tonumber(event.Time or event.Timestamp) or clock()
	end

	local function resetState(options)
		options = type(options) == "table" and options or {}
		local mode = options.Mode
			or state.Mode
			or dependencies.Mode
		local hunting = options.Hunting == true
		local resetTime = tonumber(options.Time or options.Timestamp)
			or clock()
		local generation = (state.Generation or 0) + 1
		local preserveSuppression = options.PreserveSuppression == true
		local suppressionManual = preserveSuppression
			and state.AutomationSuppressionManual == true
		local suppressionUntil = preserveSuppression
			and state.AutomationSuppressedUntil
			or nil
		local suppressionReason = preserveSuppression
			and state.AutomationSuppressionReason
			or nil

		state = {
			Mode = mode,
			Generation = generation,
			Hunting = hunting,
			HuntSerial = tonumber(options.HuntSerial)
				or (hunting and 1 or 0),
			HuntStartedAt = hunting and resetTime or nil,
			LastHuntEndedAt = nil,
			LastTickAt = nil,
			LastSpeedSample = nil,
			LastTransparencySample = nil,
			HuntSpeedSamples = {},
			TransparencySpeedSamples = {},
			HuntTransitionSamples = {},
			LastRoomPresence = nil,
			LastSalt = nil,
			LastHolyOil = nil,
			LastCross = nil,
			LastItemToggle = nil,
			LastLightToggle = nil,
			LastObjectTeleport = nil,
			LastGhostTeleport = nil,
			LastGlass = nil,
			GlassTimes = {},
			LastSpiritBox = nil,
			EventCounts = {},
			IgnoredAutomationEvents = 0,
			AutomationSuppressionManual = suppressionManual,
			AutomationSuppressedUntil = suppressionUntil,
			AutomationSuppressionReason = suppressionReason,
		}
	end

	resetState({Mode = dependencies.Mode})

	local function noteEvent(hook, event)
		state.EventCounts[hook] = (state.EventCounts[hook] or 0) + 1
		if onEvent then
			local ok, callbackError = xpcall(function()
				onEvent(hook, copyEvent(event))
			end, tracebackError)
			if not ok then
				reportError(callbackError, {
					Hook = hook,
					Phase = "OnEvent",
				})
			end
		end
	end

	local function dispatch(hook, event)
		if destroyed then
			return false
		end
		local payload = copyEvent(event)
		payload.Time = eventTime(payload)
		payload.Hunting = payload.Hunting == nil
			and state.Hunting
			or payload.Hunting == true
		payload.HuntSerial = payload.HuntSerial or state.HuntSerial
		payload.Mode = payload.Mode or state.Mode
		payload.AutomationSuppressed = state.AutomationSuppressionManual == true
			or (
				state.AutomationSuppressedUntil ~= nil
				and payload.Time < state.AutomationSuppressedUntil
			)

		local ok, dispatchError = xpcall(function()
			runtime:Dispatch(hook, payload)
		end, tracebackError)
		if not ok then
			reportError(dispatchError, {
				Hook = hook,
				Event = payload,
				Phase = "Dispatch",
			})
			return false
		end

		noteEvent(hook, payload)
		return true
	end

	local function tickRuntime(event)
		if destroyed then
			return false
		end
		local payload = copyEvent(event)
		payload.Time = eventTime(payload)
		payload.DeltaTime = tonumber(payload.DeltaTime or payload.Dt)
		payload.Hunting = state.Hunting
		payload.HuntSerial = state.HuntSerial
		payload.Mode = state.Mode
		state.LastTickAt = payload.Time

		local ok, tickError = xpcall(function()
			runtime:Tick(payload)
		end, tracebackError)
		if not ok then
			reportError(tickError, {
				Hook = "Tick",
				Event = payload,
				Phase = "Tick",
			})
			return false
		end

		noteEvent("Tick", payload)
		return true
	end

	local function trimSamples(samples)
		while #samples > maxSpeedSamples do
			table.remove(samples, 1)
		end
	end

	local function appendSample(samples, sample)
		table.insert(samples, copyEvent(sample))
		trimSamples(samples)
	end

	local function upsertTimedSample(samples, sample)
		local latest = samples[#samples]
		local latestTime = latest and tonumber(latest.Time or latest.Timestamp)
		local sampleTime = tonumber(sample.Time or sample.Timestamp)
		local sameHunt = latest
			and latest.HuntSerial == sample.HuntSerial
		local sameInstant = latestTime ~= nil
			and sampleTime ~= nil
			and math.abs(latestTime - sampleTime) <= 0.0001
		if sameHunt and sameInstant then
			samples[#samples] = copyEvent(sample)
			return false
		end
		appendSample(samples, sample)
		return true
	end

	local function currentSuppressionActive(atTime)
		if state.AutomationSuppressionManual then
			return true
		end
		local untilTime = state.AutomationSuppressedUntil
		if untilTime == nil then
			return false
		end
		if atTime < untilTime then
			return true
		end
		state.AutomationSuppressedUntil = nil
		state.AutomationSuppressionReason = nil
		return false
	end

	local function shouldSuppressAutomationEvent(event)
		if event.IgnoreAutomationSuppression == true then
			return false
		end
		if not currentSuppressionActive(eventTime(event)) then
			return false
		end
		state.IgnoredAutomationEvents = state.IgnoredAutomationEvents + 1
		return true
	end

	local Collector = {}
	Collector.__index = Collector

	function Collector:Dispatch(hook, event)
		assert(type(hook) == "string" and hook ~= "", "Dispatch requires a hook name")
		return dispatch(hook, event)
	end

	function Collector:Tick(event)
		return tickRuntime(event)
	end

	function Collector:HuntTransition(eventOrHunting)
		if destroyed then
			return false
		end
		local event = if type(eventOrHunting) == "table"
			then copyEvent(eventOrHunting)
			else {Hunting = eventOrHunting == true}
		local hunting = event.Hunting
		if type(hunting) ~= "boolean" then
			hunting = event.Active
		end
		assert(type(hunting) == "boolean", "HuntTransition requires Hunting")

		local time = eventTime(event)
		local changed = hunting ~= state.Hunting
		if not changed and event.Force ~= true then
			return false
		end

		event.Time = time
		event.PreviousHunting = state.Hunting
		event.Hunting = hunting
		if hunting then
			state.Hunting = true
			state.HuntSerial = state.HuntSerial + 1
			state.HuntStartedAt = time
			state.LastSpeedSample = nil
			state.LastTransparencySample = nil
			table.clear(state.HuntSpeedSamples)
			table.clear(state.TransparencySpeedSamples)
			event.HuntStarted = true
			event.HuntSerial = state.HuntSerial
			dispatch("OnHuntTransition", event)
			dispatch("OnHuntStarted", event)
		else
			-- Flush complete sample buffers before announcing the end so raw
			-- observers can close their per-hunt state deterministically.
			local huntSerial = state.HuntSerial
			local common = {
				Time = time,
				Hunting = false,
				HuntEnded = true,
				Completed = event.Completed ~= false,
				HuntSerial = huntSerial,
				SampleInterval = event.SampleInterval or sampleInterval,
				MapFactor = event.MapFactor
					or (state.LastSpeedSample and state.LastSpeedSample.MapFactor),
				ValidMultipliers = event.ValidMultipliers
					or (state.LastSpeedSample and state.LastSpeedSample.ValidMultipliers),
				Source = event.Source,
			}
			local speedEvent = copyEvent(common)
			speedEvent.Samples = copyValue(state.HuntSpeedSamples)
			dispatch("OnHuntSpeedSamples", speedEvent)
			dispatch("OnVisibleHuntSpeedSamples", speedEvent)
			local transparencyEvent = copyEvent(common)
			transparencyEvent.Samples = copyValue(
				state.TransparencySpeedSamples
			)
			dispatch("OnTransparencySpeedSamples", transparencyEvent)

			state.Hunting = false
			state.LastHuntEndedAt = time
			event.HuntEnded = true
			event.HuntSerial = huntSerial
			dispatch("OnHuntTransition", event)
			dispatch("OnHuntEnded", event)
		end
		return true
	end

	function Collector:SpeedSample(eventOrSpeed)
		if destroyed then
			return false
		end
		local event = if type(eventOrSpeed) == "table"
			then copyEvent(eventOrSpeed)
			else {Speed = eventOrSpeed}
		local speed = tonumber(
			event.GhostWalkSpeed or event.WalkSpeed or event.Speed
		)
		if not speed or speed < 0 then
			return false
		end

		local hunting = if type(event.Hunting) == "boolean"
			then event.Hunting
			else state.Hunting
		local transparency = tonumber(event.Transparency)
		local invisible = event.Invisible
		if type(invisible) ~= "boolean" and transparency ~= nil then
			invisible = transparency >= 0.5
		end
		local sample = copyEvent(event)
		sample.Time = eventTime(event)
		sample.Speed = speed
		sample.GhostWalkSpeed = speed
		sample.Hunting = hunting
		sample.HuntSerial = state.HuntSerial
		if type(invisible) == "boolean" then
			sample.Invisible = invisible
		end
		state.LastSpeedSample = copyEvent(sample)
		dispatch("OnSpeedSample", sample)

		if hunting then
			local wasEmpty = #state.HuntSpeedSamples == 0
			appendSample(state.HuntSpeedSamples, sample)
			if type(sample.Invisible) == "boolean" then
				upsertTimedSample(state.TransparencySpeedSamples, sample)
			end

			local speedEvent = copyEvent(event)
			speedEvent.Time = sample.Time
			speedEvent.Hunting = true
			speedEvent.HuntStarted = wasEmpty
			speedEvent.HuntSerial = state.HuntSerial
			speedEvent.SampleInterval = event.SampleInterval or sampleInterval
			speedEvent.Samples = copyValue(state.HuntSpeedSamples)
			dispatch("OnHuntSpeedSamples", speedEvent)
			dispatch("OnVisibleHuntSpeedSamples", speedEvent)

			if type(sample.Invisible) == "boolean" then
				local transparencyEvent = copyEvent(speedEvent)
				transparencyEvent.Samples = copyValue(
					state.TransparencySpeedSamples
				)
				dispatch("OnTransparencySpeedSamples", transparencyEvent)
			end
		end
		return true
	end

	function Collector:TransparencySample(eventOrTransparency)
		if destroyed then
			return false
		end
		local event = if type(eventOrTransparency) == "table"
			then copyEvent(eventOrTransparency)
			else {Transparency = eventOrTransparency}
		local transparency = tonumber(event.Transparency)
		local invisible = event.Invisible
		if type(invisible) ~= "boolean" and transparency ~= nil then
			invisible = transparency >= 0.5
		end
		if type(invisible) ~= "boolean" then
			return false
		end

		local sampleTime = eventTime(event)
		local hunting = if type(event.Hunting) == "boolean"
			then event.Hunting
			else state.Hunting
		local speed = tonumber(
			event.GhostWalkSpeed or event.WalkSpeed or event.Speed
		)
		if speed == nil and state.LastSpeedSample then
			local lastSpeedTime = tonumber(state.LastSpeedSample.Time)
			local lastSpeedHunt = state.LastSpeedSample.HuntSerial
			local freshEnough = lastSpeedTime ~= nil
				and sampleTime >= lastSpeedTime
				and sampleTime - lastSpeedTime
					<= math.max(0.25, sampleInterval * 2.5)
			local sameHunt = lastSpeedHunt == state.HuntSerial
				and state.LastSpeedSample.Hunting == hunting
			if freshEnough and sameHunt then
				speed = tonumber(state.LastSpeedSample.Speed)
			end
		end
		local sample = copyEvent(event)
		sample.Time = sampleTime
		sample.Invisible = invisible
		sample.Transparency = transparency
		sample.Hunting = hunting
		sample.HuntSerial = state.HuntSerial
		if speed and speed >= 0 then
			sample.Speed = speed
			sample.GhostWalkSpeed = speed
		end
		state.LastTransparencySample = copyEvent(sample)
		dispatch("OnTransparencySample", sample)

		if hunting and sample.Speed then
			local wasEmpty = #state.TransparencySpeedSamples == 0
			upsertTimedSample(state.TransparencySpeedSamples, sample)
			local bufferedEvent = copyEvent(event)
			bufferedEvent.Time = sample.Time
			bufferedEvent.Hunting = true
			bufferedEvent.HuntStarted = wasEmpty
			bufferedEvent.HuntSerial = state.HuntSerial
			bufferedEvent.SampleInterval = event.SampleInterval or sampleInterval
			bufferedEvent.Samples = copyValue(
				state.TransparencySpeedSamples
			)
			dispatch("OnTransparencySpeedSamples", bufferedEvent)
		end
		return true
	end

	function Collector:HuntTransitionSample(event)
		if destroyed or type(event) ~= "table" then
			return false
		end
		local sanity = tonumber(event.Sanity or event.Energy)
		local speed = tonumber(event.Speed or event.GhostWalkSpeed)
		if sanity == nil or speed == nil or speed <= 0 then
			return false
		end
		local sample = copyEvent(event)
		sample.Time = eventTime(sample)
		sample.Sanity = math.max(0, math.min(100, sanity))
		sample.Speed = speed
		table.insert(state.HuntTransitionSamples, sample)
		while #state.HuntTransitionSamples > 3 do
			table.remove(state.HuntTransitionSamples, 1)
		end
		local payload = copyEvent(event)
		payload.Time = sample.Time
		payload.Snapshots = copyValue(state.HuntTransitionSamples)
		return dispatch("OnHuntTransitionSamples", payload)
	end

	function Collector:RoomPresence(event)
		if destroyed or type(event) ~= "table" then
			return false
		end
		local normalized = copyEvent(event)
		normalized.Time = eventTime(normalized)
		if normalized.InsideFavourite == nil then
			normalized.InsideFavourite = normalized.InsideFavorite
		end
		normalized.FavouriteRoom = normalized.FavouriteRoom
			or normalized.FavoriteRoom
		state.LastRoomPresence = copyEvent(normalized)
		dispatch("OnRoomPresence", normalized)

		-- These are explicit adapter classifications, not collector policy.
		if normalized.Outcome == "Residence" then
			dispatch("OnFavouriteResidence", normalized)
		elseif normalized.Outcome == "Departure" then
			dispatch("OnDeparture", normalized)
		end
		if normalized.OffFavouriteHunt == true then
			normalized.Confirmed = normalized.Confirmed ~= false
			dispatch("OnOffFavouriteHunt", normalized)
		end
		return true
	end

	function Collector:Salt(event)
		if destroyed or type(event) ~= "table" then
			return false
		end
		local normalized = copyEvent(event)
		normalized.Time = eventTime(normalized)
		state.LastSalt = copyEvent(normalized)
		dispatch("OnSaltObservation", normalized)
		if type(normalized.SpeedSamples) == "table" then
			dispatch("OnSaltSpeedSamples", normalized)
		end
		if type(normalized.Disturbed) == "boolean" then
			dispatch("OnSaltContact", normalized)
		end
		local outcome = normalized.SpeedOutcome
			or normalized.Outcome
		if outcome == "Slow" or outcome == "Recovered" or outcome == "NoDrop" then
			local speedEvent = copyEvent(normalized)
			speedEvent.Outcome = outcome
			dispatch("OnSaltSpeed", speedEvent)
		end
		return true
	end

	function Collector:HolyOil(event)
		if destroyed or type(event) ~= "table" then
			return false
		end
		local normalized = copyEvent(event)
		normalized.Time = eventTime(normalized)
		state.LastHolyOil = copyEvent(normalized)
		dispatch("OnHolyOilObservation", normalized)

		local colorKind = normalized.ColorKind
			or normalized.FlameKind
			or (
				(normalized.Kind == "Spirit" or normalized.Kind == "NonSpirit")
				and normalized.Kind
				or nil
			)
		if colorKind then
			local colorEvent = copyEvent(normalized)
			colorEvent.Kind = colorKind
			dispatch("OnHolyOilColor", colorEvent)
		end

		local wallOutcome = normalized.WallOutcome
			or (
				(normalized.Outcome == "PassThrough" or normalized.Outcome == "Blocked")
				and normalized.Outcome
				or nil
			)
		if wallOutcome then
			local wallEvent = copyEvent(normalized)
			wallEvent.Outcome = wallOutcome
			dispatch("OnHolyOilWall", wallEvent)
		end
		return true
	end

	function Collector:Cross(event)
		if destroyed or type(event) ~= "table" then
			return false
		end
		local normalized = copyEvent(event)
		normalized.Time = eventTime(normalized)
		state.LastCross = copyEvent(normalized)
		dispatch("OnCrossObservation", normalized)
		if normalized.Outcome ~= nil then
			dispatch("OnCrossMotion", normalized)
		end
		return true
	end

	local function feedToggle(kind, event)
		if destroyed or type(event) ~= "table" then
			return false
		end
		local normalized = copyEvent(event)
		normalized.Time = eventTime(normalized)
		if shouldSuppressAutomationEvent(normalized) then
			return false
		end

		if kind == "Item" then
			state.LastItemToggle = copyEvent(normalized)
			dispatch("OnItemToggle", normalized)
		else
			state.LastLightToggle = copyEvent(normalized)
			dispatch("OnLightToggle", normalized)
		end
		if normalized.ElectronicDisabled == true then
			dispatch("OnElectronicDisabled", normalized)
		end
		local clueKind = normalized.ClueKind or normalized.LeviathanClue
		if clueKind ~= nil then
			local clueEvent = copyEvent(normalized)
			clueEvent.Kind = clueKind
			dispatch("OnClue", clueEvent)
		end
		return true
	end

	function Collector:ItemToggle(event)
		return feedToggle("Item", event)
	end

	function Collector:LightToggle(event)
		return feedToggle("Light", event)
	end

	function Collector:ObjectTeleport(event)
		if destroyed or type(event) ~= "table" then
			return false
		end
		local normalized = copyEvent(event)
		normalized.Time = eventTime(normalized)
		state.LastObjectTeleport = copyEvent(normalized)
		return dispatch("OnObjectTeleport", normalized)
	end

	function Collector:GhostTeleport(event)
		if destroyed then
			return false
		end
		local normalized = copyEvent(event)
		normalized.Time = eventTime(normalized)
		state.LastGhostTeleport = copyEvent(normalized)
		return dispatch("OnGhostTeleport", normalized)
	end

	function Collector:Glass(event)
		if destroyed then
			return false
		end
		local normalized = copyEvent(event)
		local time = eventTime(normalized)
		normalized.Time = time
		state.LastGlass = copyEvent(normalized)
		table.insert(state.GlassTimes, time)
		while state.GlassTimes[1]
			and time - state.GlassTimes[1] > glassWindow do
			table.remove(state.GlassTimes, 1)
		end
		normalized.Count = tonumber(normalized.Count)
			or #state.GlassTimes
		normalized.Window = tonumber(normalized.Window) or glassWindow
		dispatch("OnGlassObservation", normalized)
		dispatch("OnBrokenGlassBurst", normalized)
		return true
	end

	function Collector:SpiritBox(event)
		if destroyed or type(event) ~= "table" then
			return false
		end
		local normalized = copyEvent(event)
		normalized.Time = eventTime(normalized)
		normalized.Kind = normalized.Kind or normalized.ResponseKind
		if normalized.Kind == nil and normalized.Humming == true then
			normalized.Kind = "Humming"
		elseif normalized.Kind == nil and normalized.Female == true then
			normalized.Kind = "Female"
		end
		state.LastSpiritBox = copyEvent(normalized)
		dispatch("OnSpiritBoxObservation", normalized)
		if normalized.Kind ~= nil then
			dispatch("OnSpiritBox", normalized)
		end
		return true
	end

	function Collector:Reset(options)
		if destroyed then
			return false
		end
		options = type(options) == "table" and options or {}
		resetState(options)
		local ok, resetError = xpcall(function()
			runtime:Reset(options)
		end, tracebackError)
		if not ok then
			reportError(resetError, {Phase = "Reset"})
			return false
		end
		return true
	end

	function Collector:SetMode(mode)
		if destroyed then
			return false
		end
		state.Mode = mode
		local ok, modeError = xpcall(function()
			runtime:SetMode(mode)
		end, tracebackError)
		if not ok then
			reportError(modeError, {Phase = "SetMode", Mode = mode})
			return false
		end
		return true
	end

	function Collector:SuppressAutomation(value, reason)
		if destroyed then
			return false
		end
		local now = clock()
		if type(value) == "table" then
			local options = value
			reason = options.Reason or reason
			if options.Enabled == false then
				value = false
			elseif tonumber(options.Until) then
				state.AutomationSuppressionManual = false
				state.AutomationSuppressedUntil = tonumber(options.Until)
				state.AutomationSuppressionReason = reason
				return true
			elseif tonumber(options.Duration) then
				value = tonumber(options.Duration)
			else
				value = options.Enabled ~= false
			end
		end

		if type(value) == "number" then
			state.AutomationSuppressionManual = false
			state.AutomationSuppressedUntil = value > 0 and now + value or nil
			state.AutomationSuppressionReason = value > 0 and reason or nil
		elseif value == true then
			state.AutomationSuppressionManual = true
			state.AutomationSuppressedUntil = nil
			state.AutomationSuppressionReason = reason
		else
			state.AutomationSuppressionManual = false
			state.AutomationSuppressedUntil = nil
			state.AutomationSuppressionReason = nil
		end
		return true
	end

	function Collector:TrackConnection(connection)
		if destroyed then
			if connection and type(connection.Disconnect) == "function" then
				pcall(function()
					connection:Disconnect()
				end)
			end
			return nil
		end
		assert(
			connection ~= nil and type(connection.Disconnect) == "function",
			"TrackConnection requires a disconnectable connection"
		)
		table.insert(connections, connection)
		return connection
	end

	function Collector:Bind(signal, handler)
		assert(not destroyed, "cannot Bind after collector destruction")
		assert(signal ~= nil and type(signal.Connect) == "function", "Bind requires a signal")
		assert(type(handler) == "function", "Bind requires a handler")
		local connection = signal:Connect(function(...)
			if destroyed then
				return
			end
			local arguments = table.pack(...)
			local ok, handlerError = xpcall(function()
				handler(self, table.unpack(arguments, 1, arguments.n))
			end, tracebackError)
			if not ok then
				reportError(handlerError, {Phase = "Connection"})
			end
		end)
		return self:TrackConnection(connection)
	end

	function Collector:Snapshot()
		local snapshot = copyValue(state)
		snapshot.Destroyed = destroyed
		snapshot.ConnectionCount = #connections
		snapshot.AutomationSuppressed = not destroyed
			and currentSuppressionActive(clock())
			or false
		if type(runtime.Snapshot) == "function" and not destroyed then
			local ok, runtimeSnapshot = xpcall(function()
				return runtime:Snapshot()
			end, tracebackError)
			if ok then
				snapshot.Runtime = copyValue(runtimeSnapshot)
			else
				reportError(runtimeSnapshot, {Phase = "Snapshot"})
			end
		end
		return snapshot
	end

	function Collector:Destroy()
		if destroyed then
			return false
		end
		destroyed = true
		for _, connection in ipairs(connections) do
			if connection and type(connection.Disconnect) == "function" then
				local ok, disconnectError = pcall(function()
					connection:Disconnect()
				end)
				if not ok and onError then
					reportError(disconnectError, {Phase = "Disconnect"})
				end
			end
		end
		table.clear(connections)
		table.clear(state.HuntSpeedSamples)
		table.clear(state.TransparencySpeedSamples)
		table.clear(state.HuntTransitionSamples)
		table.clear(state.GlassTimes)

		if destroyRuntime and type(runtime.Destroy) == "function" then
			local ok, destroyError = xpcall(function()
				runtime:Destroy()
			end, tracebackError)
			if not ok then
				reportError(destroyError, {Phase = "DestroyRuntime"})
			end
		end
		return true
	end

	-- Feed aliases make adapter intent explicit without duplicating behavior.
	Collector.FeedTick = Collector.Tick
	Collector.FeedHuntTransition = Collector.HuntTransition
	Collector.FeedSpeedSample = Collector.SpeedSample
	Collector.FeedTransparencySample = Collector.TransparencySample
	Collector.FeedHuntTransitionSample = Collector.HuntTransitionSample
	Collector.FeedRoomPresence = Collector.RoomPresence
	Collector.FeedSalt = Collector.Salt
	Collector.FeedHolyOil = Collector.HolyOil
	Collector.FeedCross = Collector.Cross
	Collector.FeedItemToggle = Collector.ItemToggle
	Collector.FeedLightToggle = Collector.LightToggle
	Collector.FeedObjectTeleport = Collector.ObjectTeleport
	Collector.FeedGhostTeleport = Collector.GhostTeleport
	Collector.FeedGlass = Collector.Glass
	Collector.FeedSpiritBox = Collector.SpiritBox

	return setmetatable({}, Collector)
end
