return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "HuntState requires Events")
	local HuntState = {}
	HuntState.__index = HuntState

	local function schedule(context, delaySeconds, callback)
		if type(context.Schedule) == "function" then
			return context.Schedule(delaySeconds, callback)
		end
		if task and type(task.delay) == "function" then
			local cancelled = false
			task.delay(delaySeconds, function()
				if not cancelled then callback() end
			end)
			return function() cancelled = true end
		end
		callback()
		return function() end
	end

local function read(event, key)
	return Events.Read(event, key)
end

function HuntState.new(options)
	options = type(options) == "table" and options or {}
		return setmetatable({
		Name = options.Name or "HuntState",
			Category = "Active",
			Status = "Idle",
			SettleDelay = tonumber(options.SettleDelay) or 0.095,
			MaxSettleAttempts = math.max(1, math.floor(tonumber(options.MaxSettleAttempts) or 8)),
			StableSpeedTolerance = tonumber(options.StableSpeedTolerance) or 0.01,
		_context = nil,
		_hunting = false,
		_huntId = 0,
		_huntStartedAt = nil,
			_lastTransition = nil,
			_transitionToken = 0,
			_cancelSettled = nil,
	}, HuntState)
end

HuntState.New = HuntState.new

function HuntState:Start(context)
	self._context = context or {}
	self.Status = "Active"
	local initial = self._context.InitialHunting
	if initial == nil and type(self._context.ReadHunting) == "function" then
		initial = self._context.ReadHunting()
	end
	self._hunting = false
	self._huntStartedAt = nil
	if initial == true then
		local initialTransparency = self._context.Transparency
		if type(self._context.ReadTransparency) == "function" then
			local observed = self._context.ReadTransparency()
			if observed ~= nil then initialTransparency = observed end
		end
		-- Joining while a hunt is already active must arm every dormant tracker.
		self:OnEvent({
			Type = Events.Types.HuntingStateChanged,
			Time = self._context.Clock and self._context.Clock() or os.clock(),
			Hunting = true,
			Payload = {
				AverageSanity = self._context.AverageSanity,
				MapFactor = self._context.MapFactor,
				MapSize = self._context.MapSize,
				ValidMultipliers = self._context.ValidMultipliers,
				Transparency = initialTransparency,
			},
		})
	end
end

function HuntState:_readAverageSanity(event)
	local sanity = tonumber(read(event, "AverageSanity"))
	if sanity == nil and type(self._context.ReadAverageSanity) == "function" then
		sanity = tonumber(self._context.ReadAverageSanity())
	end
	return sanity
end

	function HuntState:_readSpeed(event)
		local speed = tonumber(read(event, "SettledSpeed"))
		local explicit = speed ~= nil
		if speed == nil and type(self._context.ReadWalkSpeed) == "function" then
			speed = tonumber(self._context.ReadWalkSpeed())
		end
		return speed, explicit
	end

function HuntState:_emit(event)
	if type(self._context.Emit) == "function" then
		self._context.Emit(event)
	end
end

function HuntState:OnEvent(event)
	if self.Status ~= "Active" or type(event) ~= "table" then
		return
	end
	if (event.Type or event.Kind) ~= Events.Types.HuntingStateChanged then
		return
	end
	local hunting = read(event, "Hunting")
	if type(hunting) ~= "boolean" or hunting == self._hunting then
		return
	end

		local now = tonumber(event.Time) or (self._context.Clock and self._context.Clock() or os.clock())
		local previousStart = self._huntStartedAt
		local sanityAtTransition = self:_readAverageSanity(event)
		self._hunting = hunting
	if hunting then
		self._huntId = self._huntId + 1
		self._huntStartedAt = now
	else
		self._huntStartedAt = nil
	end
	self._lastTransition = now

		local transitionTransparency = read(event, "Transparency")
		if transitionTransparency == nil and type(self._context.ReadTransparency) == "function" then
			transitionTransparency = self._context.ReadTransparency()
		end
		if transitionTransparency == nil then
			transitionTransparency = self._context.Transparency
		end
		local payload = {
			AverageSanity = sanityAtTransition,
			SanityAtTransition = sanityAtTransition,
		HuntAge = not hunting and previousStart and math.max(0, now - previousStart) or 0,
		MapFactor = read(event, "MapFactor") or self._context.MapFactor,
		MapSize = read(event, "MapSize") or self._context.MapSize,
		ValidMultipliers = read(event, "ValidMultipliers") or self._context.ValidMultipliers,
		Transparency = transitionTransparency,
	}
		self:_emit({
		Type = hunting and Events.Types.HuntStarted or Events.Types.HuntEnded,
		Time = now,
		HuntId = self._huntId,
		Hunting = hunting,
		Source = self.Name,
			Payload = payload,
		})

		-- Sanity belongs to the exact switch instant. WalkSpeed is accepted only
		-- after two matching delayed live reads, preventing the previous hunt phase
		-- from being paired with the new switch-time sanity. This is a bounded
		-- transition probe, not a continuous speed stream.
		self._transitionToken = self._transitionToken + 1
		local token = self._transitionToken
		if type(self._cancelSettled) == "function" then self._cancelSettled() end
		local attempts = 0
		local previousSpeed
		local stableReads = 0
		local function captureSettledSpeed()
			self._cancelSettled = nil
			if token ~= self._transitionToken or self._hunting ~= hunting then return end
			attempts = attempts + 1
			local settledSpeed, explicit = self:_readSpeed(event)
			if not settledSpeed or settledSpeed <= 0 then
				if attempts < self.MaxSettleAttempts then
					self._cancelSettled = schedule(
						self._context,
						self.SettleDelay,
						captureSettledSpeed
					)
				end
				return
			end
			if not explicit then
				if previousSpeed ~= nil
					and math.abs(settledSpeed - previousSpeed)
						<= self.StableSpeedTolerance then
					stableReads = stableReads + 1
				else
					previousSpeed = settledSpeed
					stableReads = 1
				end
				if stableReads < 2 and attempts < self.MaxSettleAttempts then
					self._cancelSettled = schedule(
						self._context,
						self.SettleDelay,
						captureSettledSpeed
					)
					return
				end
				if stableReads < 2 then return end
			end
			self:_emit({
				Type = Events.Types.HuntTransitionSettled,
				Time = self._context.Clock and self._context.Clock() or os.clock(),
				HuntId = self._huntId,
				Hunting = hunting,
				Source = self.Name,
				Payload = {
					TransitionTime = now,
					AverageSanity = sanityAtTransition,
					SanityAtTransition = sanityAtTransition,
					Speed = settledSpeed,
					SpeedAtTransition = settledSpeed,
					BaselineSpeed = hunting and settledSpeed or nil,
					MapFactor = payload.MapFactor,
					MapSize = payload.MapSize,
					ValidMultipliers = payload.ValidMultipliers,
				},
			})
		end
		self._cancelSettled = schedule(
			self._context,
			self.SettleDelay,
			captureSettledSpeed
		)
	end

function HuntState:Stop()
	self._transitionToken = self._transitionToken + 1
	if type(self._cancelSettled) == "function" then self._cancelSettled() end
	self._cancelSettled = nil
	self.Status = "Stopped"
end

	function HuntState:Reset()
		self._transitionToken = self._transitionToken + 1
		if type(self._cancelSettled) == "function" then self._cancelSettled() end
		self._cancelSettled = nil
	self._hunting = false
	self._huntId = 0
	self._huntStartedAt = nil
	self._lastTransition = nil
	self.Status = "Idle"
end

function HuntState:Destroy()
	self:Reset()
	self._context = nil
	self.Status = "Destroyed"
end

function HuntState:Snapshot()
	return {
		Name = self.Name,
		Category = self.Category,
		Status = self.Status,
		Hunting = self._hunting,
		HuntId = self._huntId,
		HuntStartedAt = self._huntStartedAt,
		LastTransition = self._lastTransition,
		PendingSettledTransition = self._cancelSettled ~= nil,
	}
end

	return HuntState
end
