return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "SpeedProbe requires Events")
	local SpeedProbe = {}
	SpeedProbe.__index = SpeedProbe

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

local function speedFrom(context, event)
	local speed = tonumber(
		Events.Read(event, "SettledSpeed")
			or Events.Read(event, "CurrentSpeed")
	)
	if speed == nil and type(context.ReadWalkSpeed) == "function" then
		speed = tonumber(context.ReadWalkSpeed())
	end
	if speed == nil then
		speed = tonumber(Events.Read(event, "Speed") or Events.Read(event, "WalkSpeed"))
	end
	return speed
end

local function deathKey(event)
	return tostring(
		Events.Read(event, "DeathId")
			or Events.Read(event, "PlayerId")
			or Events.Read(event, "UserId")
			or event.Id
			or event.Time
	)
end

function SpeedProbe.new(options)
	options = type(options) == "table" and options or {}
	return setmetatable({
		Name = options.Name or "SpeedProbe",
		Category = "Dormant",
		Status = "Idle",
		SettleDelay = tonumber(options.SettleDelay) or 0.095,
		DeathSettleDelay = tonumber(options.DeathSettleDelay) or 0.65,
		RevenantWindow = tonumber(options.RevenantWindow) or 1.5,
		MinimumHuntAge = tonumber(options.MinimumHuntAge) or 0.5,
		RecoveryTolerance = tonumber(options.RecoveryTolerance) or 0.03,
		RecoveryTimeout = tonumber(options.RecoveryTimeout) or 4,
		_context = nil,
		_hunting = false,
		_huntId = nil,
		_huntStartedAt = nil,
		_baseline = nil,
		_pendingReads = {},
		_queuedProbes = {},
		_pendingDeaths = {},
		_pendingRecoveries = {},
		_lastResult = nil,
	}, SpeedProbe)
end

SpeedProbe.New = SpeedProbe.new

function SpeedProbe:Start(context)
	self._context = context or {}
	self.Status = "Dormant"
end

function SpeedProbe:_now(event)
	return tonumber(event and event.Time)
		or (self._context.Clock and self._context.Clock() or os.clock())
end

function SpeedProbe:_emit(event)
	if type(self._context.Emit) == "function" then
		self._context.Emit(event)
	end
end

function SpeedProbe:_cancelPendingReads()
	for _, cancel in pairs(self._pendingReads) do
		if type(cancel) == "function" then
			cancel()
		end
	end
	table.clear(self._pendingReads)
end

function SpeedProbe:_beginHunt(event)
	self:_cancelPendingReads()
	self._hunting = true
	self._huntId = event.HuntId
	self._huntStartedAt = self:_now(event)
		self._baseline = tonumber(
			Events.Read(event, "BaselineSpeed")
		)
	table.clear(self._pendingDeaths)
	table.clear(self._pendingRecoveries)
	table.clear(self._queuedProbes)
	self.Status = self._baseline and "Armed" or "WaitingForBaseline"
end

function SpeedProbe:_endHunt(event)
	local now = self:_now(event)
	for key, pending in pairs(self._pendingDeaths) do
		local elapsed = now - pending.Time
		if elapsed >= 0 and elapsed <= self.RevenantWindow then
			self:_emit({
				Type = Events.Types.HuntEndedAfterDeath,
				HuntId = pending.HuntId,
				Hunting = false,
				Source = self.Name,
				Payload = {
					DeathEventId = pending.EventId,
					PlayerId = pending.PlayerId,
					OtherAlive = pending.OtherAlive,
					Elapsed = elapsed,
					Stopped = true,
					ValidMultiplayerKill = true,
				},
			})
		elseif elapsed > self.RevenantWindow then
			-- If the scheduler was delayed, the end transition itself still proves
			-- that this hunt continued beyond the Revenant cutoff.
			self:_emit({
				Type = Events.Types.HuntContinuedAfterDeath,
				HuntId = pending.HuntId,
				Hunting = true,
				Source = self.Name,
				Payload = {
					DeathEventId = pending.EventId,
					PlayerId = pending.PlayerId,
					OtherAlive = pending.OtherAlive,
					Elapsed = elapsed,
					Stopped = false,
					ValidMultiplayerKill = true,
				},
			})
		end
		self._pendingDeaths[key] = nil
	end
	self:_cancelPendingReads()
	self._hunting = false
	self._huntId = nil
	self._huntStartedAt = nil
	self._baseline = nil
	table.clear(self._pendingRecoveries)
	table.clear(self._queuedProbes)
	self.Status = "Dormant"
end

function SpeedProbe:_probe(event)
	if not self._hunting
		or event.Hunting == false
		or (event.HuntId ~= nil and event.HuntId ~= self._huntId) then
		return
	end
	if not self._baseline then
		table.insert(self._queuedProbes, Events.Copy(event))
		return
	end
	local trigger = event.Type or event.Kind
	local delaySeconds = trigger == Events.Types.PlayerDeath and self.DeathSettleDelay or self.SettleDelay
	local key = tostring(event.Id or trigger .. ":" .. tostring(event.Time))
	local eventCopy = Events.Copy(event)
	self._pendingReads[key] = schedule(self._context, delaySeconds, function()
		self._pendingReads[key] = nil
		if not self._hunting
			or eventCopy.HuntId ~= nil and eventCopy.HuntId ~= self._huntId then
			return
		end
		local current = speedFrom(self._context, eventCopy)
		if not current or not self._baseline or self._baseline <= 0 then
			return
		end
		local delta = current - self._baseline
		local relative = delta / self._baseline
		local payload = {
			Trigger = trigger,
			TriggerEventId = eventCopy.Id,
			BaselineSpeed = self._baseline,
			CurrentSpeed = current,
			Delta = delta,
			RelativeDelta = relative,
			HuntId = self._huntId,
			Hunting = true,
			Time = self:_now(eventCopy),
			DirectContact = Events.Read(eventCopy, "DirectContact") == true,
			SaltDisturbed = Events.Read(eventCopy, "SaltDisturbed") == true
				or Events.Read(eventCopy, "Disturbed") == true,
			ContactId = Events.Read(eventCopy, "ContactId"),
			DisturbedContactId = Events.Read(eventCopy, "DisturbedContactId"),
			Unique = Events.Read(eventCopy, "Unique") == true,
			Qualified = Events.Read(eventCopy, "Qualified") == true,
			ValidMultiplayerKill = Events.Read(eventCopy, "ValidMultiplayerKill") == true,
			OtherAlive = Events.Read(eventCopy, "OtherAlive"),
		}
		self._lastResult = payload
		self:_emit({
			Type = Events.Types.SpeedProbeResult,
			HuntId = self._huntId,
			Hunting = true,
			Source = self.Name,
			Payload = payload,
		})
		if trigger == Events.Types.SaltContact and relative < -self.RecoveryTolerance then
			self._pendingRecoveries[key] = {
				EventId = eventCopy.Id,
				EventSpeed = current,
				OpenedAt = self:_now(eventCopy),
				HuntId = self._huntId,
				DirectContact = payload.DirectContact,
				SaltDisturbed = payload.SaltDisturbed,
				ContactId = payload.ContactId,
				DisturbedContactId = payload.DisturbedContactId,
			}
		end
	end)
end

	function SpeedProbe:_armDeath(event)
		if event.HuntId == nil or event.HuntId ~= self._huntId
			or Events.Read(event, "Unique") ~= true
			or Events.Read(event, "Qualified") ~= true then
			return false
		end
		local now = self:_now(event)
	local huntAge = tonumber(Events.Read(event, "HuntAge"))
		or (self._huntStartedAt and now - self._huntStartedAt)
		or 0
	local otherAlive = tonumber(Events.Read(event, "OtherAlive")) or 0
		local validMultiplayerKill = Events.Read(event, "ValidMultiplayerKill") == true
			and huntAge >= self.MinimumHuntAge and otherAlive > 0
	local key = deathKey(event)
		if self._pendingDeaths[key] then
			return false
	end
		local pending = {
		EventId = event.Id,
		PlayerId = Events.Read(event, "PlayerId") or Events.Read(event, "UserId"),
		OtherAlive = otherAlive,
		Time = now,
		HuntId = self._huntId,
	}
		if not validMultiplayerKill then
			return false
		end
		self._pendingDeaths[key] = pending
	self._pendingReads["revenant:" .. key] = schedule(self._context, self.RevenantWindow, function()
		self._pendingReads["revenant:" .. key] = nil
		local current = self._pendingDeaths[key]
		if not current then
			return
		end
		if self._hunting and self._huntId == current.HuntId then
			self:_emit({
				Type = Events.Types.HuntContinuedAfterDeath,
				HuntId = current.HuntId,
				Hunting = true,
				Source = self.Name,
				Payload = {
					DeathEventId = current.EventId,
					PlayerId = current.PlayerId,
					OtherAlive = current.OtherAlive,
					Elapsed = self.RevenantWindow,
					Stopped = false,
					ValidMultiplayerKill = true,
				},
			})
		end
		self._pendingDeaths[key] = nil
	end)
		return true
end

function SpeedProbe:_checkRecovery(event)
	if not self._hunting or not self._baseline or self._baseline <= 0 then
		return
	end
	local current = speedFrom(self._context, event)
	if not current then
		return
	end
	local now = self:_now(event)
	for key, pending in pairs(self._pendingRecoveries) do
		if pending.HuntId ~= self._huntId or now - pending.OpenedAt > self.RecoveryTimeout then
			self._pendingRecoveries[key] = nil
		elseif math.abs(current - self._baseline) / self._baseline <= self.RecoveryTolerance then
			self:_emit({
				Type = Events.Types.SpeedProbeRecovery,
				HuntId = self._huntId,
				Hunting = true,
				Source = self.Name,
				Payload = {
					Trigger = Events.Types.SaltContact,
					TriggerEventId = pending.EventId,
					BaselineSpeed = self._baseline,
					EventSpeed = pending.EventSpeed,
					RecoverySpeed = current,
					Elapsed = now - pending.OpenedAt,
					Hunting = true,
					DirectContact = pending.DirectContact,
					SaltDisturbed = pending.SaltDisturbed,
					ContactId = pending.ContactId,
					DisturbedContactId = pending.DisturbedContactId,
				},
			})
			self._pendingRecoveries[key] = nil
		end
	end
end

function SpeedProbe:_tick(event)
	local now = self:_now(event)
	for key, pending in pairs(self._pendingDeaths) do
		if self._hunting and pending.HuntId == self._huntId
			and now - pending.Time >= self.RevenantWindow then
			self:_emit({
				Type = Events.Types.HuntContinuedAfterDeath,
				HuntId = pending.HuntId,
				Hunting = true,
				Source = self.Name,
				Payload = {
					DeathEventId = pending.EventId,
					PlayerId = pending.PlayerId,
					OtherAlive = pending.OtherAlive,
					Elapsed = now - pending.Time,
					Stopped = false,
					ValidMultiplayerKill = true,
				},
			})
			self._pendingDeaths[key] = nil
		end
	end
	self:_checkRecovery(event)
end

function SpeedProbe:OnEvent(event)
	if type(event) ~= "table" then
		return
	end
		local kind = event.Type or event.Kind
		if kind == Events.Types.HuntStarted then
			self:_beginHunt(event)
		elseif kind == Events.Types.HuntTransitionSettled
			and event.Hunting == true and event.HuntId == self._huntId then
			self._baseline = tonumber(Events.Read(event, "BaselineSpeed") or Events.Read(event, "Speed"))
			if self._baseline then
				self.Status = "Armed"
				local queued = self._queuedProbes
				self._queuedProbes = {}
				for _, queuedEvent in ipairs(queued) do
					self:_probe(queuedEvent)
				end
			end
	elseif kind == Events.Types.HuntEnded then
		if self._hunting and (event.HuntId == nil or event.HuntId == self._huntId) then
			self:_endHunt(event)
		end
		elseif kind == Events.Types.PlayerDeath and self._hunting then
			if self:_armDeath(event) then
				self:_probe(event)
			end
	elseif kind == Events.Types.SaltContact and self._hunting then
		self:_probe(event)
	elseif kind == Events.Types.WalkSpeedChanged then
		self:_checkRecovery(event)
	elseif kind == Events.Types.Tick then
		self:_tick(event)
	elseif Events.Read(event, "SpeedProbe") == true then
		self:_probe(event)
	end
end

function SpeedProbe:Stop()
	self:_cancelPendingReads()
	self.Status = "Stopped"
end

function SpeedProbe:Reset()
	self:_cancelPendingReads()
	self._hunting = false
	self._huntId = nil
	self._huntStartedAt = nil
	self._baseline = nil
	table.clear(self._pendingDeaths)
	table.clear(self._pendingRecoveries)
	table.clear(self._queuedProbes)
	self._lastResult = nil
	self.Status = "Idle"
end

function SpeedProbe:Destroy()
	self:Reset()
	self._context = nil
	self.Status = "Destroyed"
end

function SpeedProbe:Snapshot()
	local deathCount = 0
	for _ in pairs(self._pendingDeaths) do
		deathCount = deathCount + 1
	end
	local recoveryCount = 0
	for _ in pairs(self._pendingRecoveries) do
		recoveryCount = recoveryCount + 1
	end
	return {
		Name = self.Name,
		Category = self.Category,
		Status = self.Status,
		Hunting = self._hunting,
		HuntId = self._huntId,
		BaselineSpeed = self._baseline,
		PendingDeathCount = deathCount,
		PendingRecoveryCount = recoveryCount,
		QueuedProbeCount = #self._queuedProbes,
		LastResult = Events.Copy(self._lastResult),
	}
end

	return SpeedProbe
end
