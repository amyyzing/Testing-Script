return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "SpeedProbe requires Events")
	local Specification = type(dependencies.Specification) == "table"
		and dependencies.Specification or {}
	local SaltSpec = type(Specification.Salt) == "table" and Specification.Salt or {}
	local RevenantSpec = type(Specification.Revenant) == "table"
		and Specification.Revenant or {}
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

local function speedFrom(context, event, preferLive)
	local speed
	if preferLive and type(context.ReadWalkSpeed) == "function" then
		speed = tonumber(context.ReadWalkSpeed())
	end
	if speed == nil then
		speed = tonumber(
			Events.Read(event, "SettledSpeed")
				or Events.Read(event, "CurrentSpeed")
		)
	end
	if speed == nil and type(context.ReadWalkSpeed) == "function" then
		speed = tonumber(context.ReadWalkSpeed())
	end
	if speed == nil then
		speed = tonumber(Events.Read(event, "Speed") or Events.Read(event, "WalkSpeed"))
	end
	return speed
end

-- A HuntEnded event normally arrives before the active hunt-state tracker has
-- completed its settled non-hunting read. Tests and other trusted producers may
-- provide that settled read directly, but a generic CurrentSpeed is not enough:
-- it may still be the hunting speed or an in-flight hunt-state reset.
local function explicitPostHuntSpeed(event)
	return tonumber(
		Events.Read(event, "PostHuntBaselineSpeed")
			or Events.Read(event, "SettledSpeed")
			or Events.Read(event, "SpeedAtTransition")
	)
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
		DeathRequiredStableReads = math.max(2, math.floor(
			tonumber(options.DeathRequiredStableReads)
				or tonumber((Specification.SpeedProbe or {}).DeathRequiredStableReads)
				or 3
		)),
		DeathInitialDelay = tonumber(options.DeathInitialDelay)
			or tonumber((Specification.SpeedProbe or {}).DeathInitialDelay) or 0.35,
		DeathSampleInterval = tonumber(options.DeathSampleInterval)
			or tonumber((Specification.SpeedProbe or {}).DeathSampleInterval) or 0.2,
		DeathProbeWindow = tonumber(options.DeathProbeWindow)
			or tonumber((Specification.SpeedProbe or {}).DeathProbeWindow) or 1.4,
		DeathStableTolerance = tonumber(options.DeathStableTolerance)
			or tonumber((Specification.SpeedProbe or {}).DeathStableTolerance) or 0.01,
		RevenantWindow = tonumber(options.RevenantWindow)
			or tonumber(RevenantSpec.NegativeMinSeconds) or 1.5,
		MinimumHuntAge = tonumber(options.MinimumHuntAge) or 0.5,
		RecoveryTolerance = tonumber(options.RecoveryTolerance) or 0.03,
		RecoveryTimeout = tonumber(options.RecoveryTimeout) or 4,
		PostHuntSaltGrace = tonumber(options.PostHuntSaltGrace)
			or tonumber(SaltSpec.PostHuntProbeGrace) or 1.25,
		_context = nil,
		_hunting = false,
		_huntId = nil,
		_huntStartedAt = nil,
		_baseline = nil,
		_pendingReads = {},
		_queuedProbes = {},
		_pendingDeaths = {},
		_deathSpeedProbes = {},
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
	table.clear(self._deathSpeedProbes)
	table.clear(self._saltWindows)
	table.clear(self._queuedProbes)
	self._recentEndedHunt = nil
	self.Status = self._baseline and "Armed" or "WaitingForBaseline"
end

function SpeedProbe:_endHunt(event)
	local now = self:_now(event)
	local endedHuntId = self._huntId
	local endedBaseline = self._baseline
	local endSpeed = explicitPostHuntSpeed(event)
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
		PostHuntBaseline = endSpeed,
		PostHuntBaselineSource = endSpeed and "HuntEndedExplicit" or nil,
	}
	for _, window in pairs(self._saltWindows) do
		if window.HuntId == endedHuntId then
			window.HuntEndedAt = now
			window.HuntEndSpeed = endSpeed
			window.ExpiresAt = now + self.PostHuntSaltGrace
			window.PostHuntBaseline = endSpeed
			window.PostHuntBaselineSource = endSpeed and "HuntEndedExplicit" or nil
			window.PostHuntBaselineAt = endSpeed and now or nil
		end
	end
	self:_cancelPendingReads()
	table.clear(self._deathSpeedProbes)
	self._hunting = false
	self._huntId = nil
	self._huntStartedAt = nil
	self._baseline = nil
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
		and contactId == disturbedContactId
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
	if trigger == Events.Types.PlayerDeath then
		local key = deathKey(event)
		if self._deathSpeedProbes[key] == nil then
			self._deathSpeedProbes[key] = {
				Key = key,
				Event = Events.Copy(event),
				EventId = event.Id,
				HuntId = probeHuntId,
				Baseline = probeBaseline,
				StartedAt = now,
				NextSampleAt = now + self.DeathInitialDelay,
				Deadline = now + self.DeathProbeWindow,
				LastSpeed = nil,
				StableReads = 0,
			}
		end
		return
	end
	local delaySeconds = self.SettleDelay
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
			PostHuntBaseline = recentSalt and recent.PostHuntBaseline or nil,
			PostHuntBaselineSource = recentSalt and recent.PostHuntBaselineSource or nil,
			PostHuntBaselineAt = recentSalt and recent.EndedAt or nil,
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
			self:_sampleSaltWindows(eventCopy, key, true)
			return
		end
		if not self._hunting
			or self._huntId ~= probeHuntId then
			return
		end
		local current = speedFrom(self._context, eventCopy, true)
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
				Completed = true,
				Stable = true,
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

function SpeedProbe:_sampleDeathSpeedProbes(event)
	local now = self:_now(event)
	for key, probe in pairs(self._deathSpeedProbes) do
		if not self._hunting or probe.HuntId ~= self._huntId or now > probe.Deadline then
			self._deathSpeedProbes[key] = nil
		elseif now + 1e-6 >= probe.NextSampleAt then
			local current = speedFrom(self._context, event, true)
			probe.NextSampleAt = now + self.DeathSampleInterval
			if current and current > 0 then
				if probe.LastSpeed ~= nil
					and math.abs(current - probe.LastSpeed) <= self.DeathStableTolerance then
					probe.StableReads = probe.StableReads + 1
				else
					probe.LastSpeed = current
					probe.StableReads = 1
				end
				if probe.StableReads >= self.DeathRequiredStableReads then
					local delta = current - probe.Baseline
					local sourceEvent = probe.Event
					local payload = {
						Trigger = Events.Types.PlayerDeath,
						TriggerEventId = probe.EventId,
						BaselineSpeed = probe.Baseline,
						CurrentSpeed = current,
						Delta = delta,
						RelativeDelta = delta / probe.Baseline,
						Completed = true,
						Stable = true,
						StableReadCount = probe.StableReads,
						RequiredStableReads = self.DeathRequiredStableReads,
						ProbeElapsed = now - probe.StartedAt,
						HuntId = probe.HuntId,
						Hunting = true,
						Time = now,
						Unique = Events.Read(sourceEvent, "Unique") == true,
						Qualified = Events.Read(sourceEvent, "Qualified") == true,
						ValidMultiplayerKill = Events.Read(sourceEvent, "ValidMultiplayerKill") == true,
						OtherAlive = Events.Read(sourceEvent, "OtherAlive"),
					}
					self._lastResult = payload
					self:_emit({
						Type = Events.Types.SpeedProbeResult,
						HuntId = probe.HuntId,
						Hunting = true,
						Source = self.Name,
						Payload = payload,
					})
					self._deathSpeedProbes[key] = nil
				end
			end
		end
	end
end

function SpeedProbe:_emitSaltResult(window, current, now, completed)
	local postHunt = window.HuntEndedAt ~= nil
	local reference = window.RecoveryBaseline
		or (postHunt and window.PostHuntBaseline)
		or window.Baseline
	if not reference or reference <= 0 then return end
	local delta = current - reference
	local payload = {
		Trigger = Events.Types.SaltContact,
		TriggerEventId = window.EventId,
		BaselineSpeed = reference,
		HuntBaselineSpeed = window.Baseline,
		PostHuntBaselineSpeed = postHunt and window.PostHuntBaseline or nil,
		PostHuntBaselineSource = postHunt and window.PostHuntBaselineSource or nil,
		PostHuntReferenceQualified = postHunt and window.PostHuntBaseline ~= nil or nil,
		CurrentSpeed = current,
		Delta = delta,
		RelativeDelta = delta / reference,
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

function SpeedProbe:_emitSaltRecovery(window, current, now, referenceOverride, slowedOverride)
	local postHunt = window.HuntEndedAt ~= nil
	local reference = referenceOverride
		or window.RecoveryBaseline
		or (postHunt and window.PostHuntBaseline)
		or window.Baseline
	local slowed = slowedOverride or window.EventSpeed
	if not reference or not slowed then return end
	self:_emit({
		Type = Events.Types.SpeedProbeRecovery,
		HuntId = window.HuntId,
		Hunting = not postHunt,
		Source = self.Name,
		Payload = {
			Trigger = Events.Types.SaltContact,
			TriggerEventId = window.EventId,
			BaselineSpeed = reference,
			HuntBaselineSpeed = window.Baseline,
			PostHuntBaselineSpeed = postHunt and window.PostHuntBaseline or nil,
			PostHuntBaselineSource = postHunt and window.PostHuntBaselineSource or nil,
			PostHuntReferenceQualified = postHunt and window.PostHuntBaseline ~= nil or nil,
			EventSpeed = slowed,
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

function SpeedProbe:_setPostHuntReference(window, speed, source, now)
	if not speed or speed <= 0 or window.HuntEndedAt == nil then
		return false
	end
	if window.SlowObserved then
		-- A drop was already measured against a trustworthy reference. Do not
		-- move its recovery target merely because the settled transition arrived
		-- while the temporary slowdown was still active.
		window.PostHuntSettledSpeed = speed
		window.PostHuntSettledAt = now
		return false
	end

	local previous = window.PostHuntBaseline
	local previousSource = window.PostHuntBaselineSource
	local preferred = source == "HuntTransitionSettled"
	if preferred and previous and previousSource ~= "HuntTransitionSettled"
		and speed > previous * (1 + self.RecoveryTolerance) then
		-- The explicit HuntEnded fallback was already salt-slowed. A later
		-- settled rise is the recovery itself; emit only the recovered result,
		-- never provisional support for the ordinary hunt-state reset.
		window.PostHuntBaseline = previous
		window.PostHuntBaselineSource = previousSource
		self:_emitSaltRecovery(window, speed, now, speed, previous)
		return true
	end

	if previous == nil or preferred or previousSource ~= "HuntTransitionSettled" then
		window.PostHuntBaseline = speed
		window.PostHuntBaselineSource = source
		window.PostHuntBaselineAt = now
	end
	return false
end

function SpeedProbe:_settlePostHunt(event)
	local recent = self._recentEndedHunt
	if not recent or (event.HuntId ~= nil and event.HuntId ~= recent.HuntId) then
		return
	end
	local speed = tonumber(
		Events.Read(event, "Speed")
			or Events.Read(event, "SettledSpeed")
			or Events.Read(event, "SpeedAtTransition")
	)
	if not speed or speed <= 0 then return end
	local now = self:_now(event)
	recent.PostHuntBaseline = speed
	recent.PostHuntBaselineSource = "HuntTransitionSettled"
	for key, window in pairs(self._saltWindows) do
		if window.HuntId == recent.HuntId and now <= window.ExpiresAt
			and self:_setPostHuntReference(window, speed, "HuntTransitionSettled", now) then
			self._saltWindows[key] = nil
		end
	end
end

function SpeedProbe:_sampleSaltWindows(event, onlyKey, preferLive)
	local current = speedFrom(self._context, event, preferLive)
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
				local reference = postHunt and window.PostHuntBaseline or window.Baseline
				if not reference or reference <= 0 then
					continue
				end
				local relative = (current - reference) / reference
				if not window.SlowObserved then
					local slowed = relative < -self.RecoveryTolerance
					if slowed then
						window.SlowObserved = true
						window.EventSpeed = current
						window.SlowAt = now
						window.RecoveryBaseline = reference
						self:_emitSaltResult(window, current, now, false)
					elseif postHunt and current > reference * (1 + self.RecoveryTolerance) then
						-- The first settled non-hunt reference can itself be the salt-
						-- slowed value. A material rise within the grace period proves
						-- the temporary drop without manufacturing provisional support.
						self:_emitSaltRecovery(window, current, now, current, reference)
						self._saltWindows[key] = nil
					elseif active and now >= window.ExpiresAt then
						self:_emitSaltResult(window, current, now, true)
						self._saltWindows[key] = nil
					end
				else
					local recoveryTarget = window.RecoveryBaseline or window.Baseline
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

function SpeedProbe:_tick(event)
	local now = self:_now(event)
	self:_sampleDeathSpeedProbes(event)
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
end

function SpeedProbe:OnEvent(event)
	if self.Status == "Stopped" or self.Status == "Destroyed"
		or type(event) ~= "table" then
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
		elseif kind == Events.Types.HuntTransitionSettled and event.Hunting == false then
			self:_settlePostHunt(event)
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
		self:_sampleDeathSpeedProbes(event)
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
	table.clear(self._deathSpeedProbes)
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
	local deathSpeedProbeCount = 0
	for _ in pairs(self._deathSpeedProbes) do
		deathSpeedProbeCount = deathSpeedProbeCount + 1
	end
	return {
		Name = self.Name,
		Category = self.Category,
		Status = self.Status,
		Hunting = self._hunting,
		HuntId = self._huntId,
		BaselineSpeed = self._baseline,
		PendingDeathCount = deathCount,
		PendingDeathSpeedProbeCount = deathSpeedProbeCount,
		QueuedProbeCount = #self._queuedProbes,
		LastResult = Events.Copy(self._lastResult),
	}
end

	return SpeedProbe
end
