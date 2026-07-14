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
		PostHuntSaltGrace = tonumber(options.PostHuntSaltGrace) or 1.25,
		_context = nil,
		_hunting = false,
		_huntId = nil,
		_huntStartedAt = nil,
		_baseline = nil,
		_pendingReads = {},
		_queuedProbes = {},
		_pendingDeaths = {},
		_pendingRecoveries = {},
		_saltWindows = {},
		_recentEndedHunt = nil,
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
	table.clear(self._saltWindows)
	table.clear(self._queuedProbes)
	self._recentEndedHunt = nil
	self.Status = self._baseline and "Armed" or "WaitingForBaseline"
end

function SpeedProbe:_endHunt(event)
	local now = self:_now(event)
	local endedHuntId = self._huntId
	local endedBaseline = self._baseline
	local endSpeed = speedFrom(self._context, event)
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
	self._recentEndedHunt = {
		HuntId = endedHuntId,
		Baseline = endedBaseline,
		EndedAt = now,
		EndSpeed = endSpeed,
	}
	for _, window in pairs(self._saltWindows) do
		if window.HuntId == endedHuntId then
			window.HuntEndedAt = now
			window.HuntEndSpeed = endSpeed
			window.ExpiresAt = now + self.PostHuntSaltGrace
		end
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
	local trigger = event.Type or event.Kind
	local isSalt = trigger == Events.Types.SaltContact
	local now = self:_now(event)
	local huntingAtContact = Events.Read(event, "HuntingAtContact")
	if huntingAtContact == nil then
		huntingAtContact = Events.Read(event, "Hunting")
	end
	local directContact = Events.Read(event, "DirectContact") == true
	local saltDisturbed = Events.Read(event, "SaltDisturbed") == true
		or Events.Read(event, "Disturbed") == true
	local contactId = Events.Read(event, "ContactId")
	local disturbedContactId = Events.Read(event, "DisturbedContactId")
	local qualifiedSalt = isSalt and huntingAtContact == true
		and directContact and saltDisturbed
		and contactId ~= nil and disturbedContactId ~= nil
		and tostring(contactId) == tostring(disturbedContactId)
	local activeHunt = self._hunting
		and (not isSalt and event.Hunting ~= false or qualifiedSalt)
		and (event.HuntId == nil or event.HuntId == self._huntId)
	local recent = self._recentEndedHunt
	local recentSalt = qualifiedSalt and not self._hunting and recent ~= nil
		and now - recent.EndedAt <= self.PostHuntSaltGrace
		and (event.HuntId == nil or event.HuntId == recent.HuntId)
	if isSalt then
		if not qualifiedSalt or (not activeHunt and not recentSalt) then
			return
		end
	elseif not activeHunt then
		return
	end
	local probeBaseline
	local probeHuntId
	if activeHunt then
		probeBaseline = self._baseline
		probeHuntId = self._huntId
	else
		probeBaseline = recent.Baseline
		probeHuntId = recent.HuntId
	end
	if not probeBaseline then
		if activeHunt then
			table.insert(self._queuedProbes, Events.Copy(event))
		end
		return
	end
	local delaySeconds = trigger == Events.Types.PlayerDeath and self.DeathSettleDelay or self.SettleDelay
	local key = tostring(event.Id or trigger .. ":" .. tostring(event.Time))
	local eventCopy = Events.Copy(event)
	if isSalt then
		self._saltWindows[key] = {
			EventId = eventCopy.Id,
			OpenedAt = now,
			ExpiresAt = activeHunt and (now + self.RecoveryTimeout)
				or (recent.EndedAt + self.PostHuntSaltGrace),
			HuntId = probeHuntId,
			Baseline = probeBaseline,
			HuntEndedAt = recentSalt and recent.EndedAt or nil,
			HuntEndSpeed = recentSalt and recent.EndSpeed or nil,
			DirectContact = directContact,
			SaltDisturbed = saltDisturbed,
			ContactId = contactId,
			DisturbedContactId = disturbedContactId,
			SlowObserved = false,
		}
	end
	self._pendingReads[key] = schedule(self._context, delaySeconds, function()
		self._pendingReads[key] = nil
		if isSalt then
			self:_sampleSaltWindows(eventCopy, key)
			return
		end
		if not self._hunting
			or self._huntId ~= probeHuntId then
			return
		end
		local current = speedFrom(self._context, eventCopy)
		if not current or probeBaseline <= 0 then
			return
		end
		local delta = current - probeBaseline
		local relative = delta / probeBaseline
		local payload = {
			Trigger = trigger,
			TriggerEventId = eventCopy.Id,
			BaselineSpeed = probeBaseline,
			CurrentSpeed = current,
			Delta = delta,
			RelativeDelta = relative,
			HuntId = probeHuntId,
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
			HuntId = probeHuntId,
			Hunting = true,
			Source = self.Name,
			Payload = payload,
		})
	end)
end

function SpeedProbe:_emitSaltResult(window, current, now, completed)
	local postHunt = window.HuntEndedAt ~= nil
	local delta = current - window.Baseline
	local payload = {
		Trigger = Events.Types.SaltContact,
		TriggerEventId = window.EventId,
		BaselineSpeed = window.Baseline,
		CurrentSpeed = current,
		Delta = delta,
		RelativeDelta = delta / window.Baseline,
		HuntId = window.HuntId,
		Hunting = not postHunt,
		HuntingAtContact = true,
		HuntEndedBeforeSample = postHunt,
		Completed = completed == true,
		Time = now,
		DirectContact = window.DirectContact,
		SaltDisturbed = window.SaltDisturbed,
		ContactId = window.ContactId,
		DisturbedContactId = window.DisturbedContactId,
	}
	self._lastResult = payload
	self:_emit({
		Type = Events.Types.SpeedProbeResult,
		HuntId = window.HuntId,
		Hunting = not postHunt,
		Source = self.Name,
		Payload = payload,
	})
end

function SpeedProbe:_emitSaltRecovery(window, current, now)
	local postHunt = window.HuntEndedAt ~= nil
	self:_emit({
		Type = Events.Types.SpeedProbeRecovery,
		HuntId = window.HuntId,
		Hunting = not postHunt,
		Source = self.Name,
		Payload = {
			Trigger = Events.Types.SaltContact,
			TriggerEventId = window.EventId,
			BaselineSpeed = window.Baseline,
			EventSpeed = window.EventSpeed,
			RecoverySpeed = current,
			Elapsed = now - (window.SlowAt or window.OpenedAt),
			Hunting = not postHunt,
			HuntingAtContact = true,
			HuntEndedBeforeSample = postHunt,
			DirectContact = window.DirectContact,
			SaltDisturbed = window.SaltDisturbed,
			ContactId = window.ContactId,
			DisturbedContactId = window.DisturbedContactId,
		},
	})
end

function SpeedProbe:_sampleSaltWindows(event, onlyKey)
	local current = speedFrom(self._context, event)
	if not current then
		return
	end
	local now = self:_now(event)
	for key, window in pairs(self._saltWindows) do
		if onlyKey == nil or key == onlyKey then
			local active = self._hunting and window.HuntId == self._huntId
			local postHunt = window.HuntEndedAt ~= nil
				and now <= window.ExpiresAt
			if not active and not postHunt then
				if window.HuntEndedAt ~= nil or now >= window.ExpiresAt then
					self._saltWindows[key] = nil
				end
			elseif window.Baseline and window.Baseline > 0 then
				local relative = (current - window.Baseline) / window.Baseline
				if not window.SlowObserved then
					local slowed = relative < -self.RecoveryTolerance
					if postHunt and window.HuntEndSpeed then
						slowed = slowed and current
							< window.HuntEndSpeed * (1 - self.RecoveryTolerance)
					end
					if slowed then
						window.SlowObserved = true
						window.EventSpeed = current
						window.SlowAt = now
						self:_emitSaltResult(window, current, now, false)
					elseif active and now >= window.ExpiresAt then
						self:_emitSaltResult(window, current, now, true)
						self._saltWindows[key] = nil
					end
				else
					local recoveryTarget = postHunt
						and window.HuntEndSpeed or window.Baseline
					if recoveryTarget
						and current > window.EventSpeed
						and current >= recoveryTarget * (1 - self.RecoveryTolerance) then
						self:_emitSaltRecovery(window, current, now)
						self._saltWindows[key] = nil
					elseif postHunt and now >= window.ExpiresAt then
						self._saltWindows[key] = nil
					end
				end
			end
		end
	end
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
	self:_sampleSaltWindows(event)
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
	elseif kind == Events.Types.SaltContact then
		self:_probe(event)
	elseif kind == Events.Types.WalkSpeedChanged then
		self:_sampleSaltWindows(event)
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
	table.clear(self._saltWindows)
	table.clear(self._queuedProbes)
	self._recentEndedHunt = nil
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
