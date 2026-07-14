local NAME = "Aswang"

local function read(event, key)
	if event[key] ~= nil then return event[key] end
	if type(event.Payload) == "table" then return event.Payload[key] end
	return nil
end

local function triggerKind(event)
	return string.lower(tostring(read(event, "Trigger") or read(event, "Cause") or ""))
end

local function qualifiedSaltContact(event)
	local huntingAtContact = read(event, "HuntingAtContact")
	if huntingAtContact == nil then
		huntingAtContact = read(event, "Hunting")
	end
	if huntingAtContact ~= true or read(event, "DirectContact") ~= true
		or read(event, "SaltDisturbed") ~= true then
		return false
	end
	local contactId = read(event, "ContactId") or read(event, "SaltId")
	local disturbedId = read(event, "DisturbedContactId") or read(event, "DisturbedSaltId")
	return contactId ~= nil and disturbedId ~= nil and tostring(contactId) == tostring(disturbedId)
end

local function call(api, method, reason, confidence, event)
	local handler = api and api[method]
	if type(handler) == "function" then
		if method == "Record" then
			return handler(api, NAME, event)
		end
		return handler(api, NAME, reason, confidence, event)
	end
	return nil
end

local function createObserver(api)
	local state = {Destroyed = false, SaltOutcome = nil, KillOutcome = nil, KillMatched = false, EvidenceIds = {}}
	local observer = {}
	local function conclude(domain, polarity, reason, confidence, event)
		local previous = state.EvidenceIds[domain]
		local entry
		if previous and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, previous, polarity, reason, confidence, event)
		else
			entry = call(api, polarity, reason, confidence, event)
		end
		state.EvidenceIds[domain] = type(entry) == "table" and entry.Id or previous
	end

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "SaltContactSpeed" and kind ~= "KillSpeedChange"
			and kind ~= "SpeedProbeResult" and kind ~= "SpeedProbeRecovery" then return false end
		call(api, "Record", nil, nil, event)

		if kind == "SpeedProbeResult" or kind == "SpeedProbeRecovery" then
			local trigger = triggerKind(event)
			local baseline = tonumber(read(event, "BaselineSpeed"))
			local current = tonumber(read(event, "CurrentSpeed") or read(event, "EventSpeed"))
			local recovery = tonumber(read(event, "RecoverySpeed"))
			local delta = tonumber(read(event, "Delta"))
			if delta == nil and baseline and current then delta = current - baseline end
			if string.find(trigger, "salt", 1, true) then
				if not qualifiedSaltContact(event) then return true end
				if kind == "SpeedProbeRecovery" and baseline and current and recovery
					and current < baseline and recovery > current
					and recovery >= baseline * 0.95 then
					state.SaltOutcome = "Matched"
					conclude("Salt", "Positive", read(event, "Reason") or "a salt-triggered speed probe measured a temporary hunting slowdown followed by recovery", 99, event)
				elseif kind == "SpeedProbeResult" and delta and delta < 0 then
					if state.SaltOutcome == "Matched" then return true end
					state.SaltOutcome = "Provisional"
					conclude("Salt", "Positive", read(event, "Reason") or "a salt-triggered hunting speed probe measured a slowdown; recovery is pending", 80, event)
				elseif kind == "SpeedProbeResult" and read(event, "Completed") == true
					and delta and delta >= 0 then
					if state.SaltOutcome == "Matched" then return true end
					state.SaltOutcome = "Rejected"
					conclude("Salt", "RuleOut", read(event, "Reason") or "a qualified salt-triggered hunting speed probe measured no slowdown", 99, event)
				end
			elseif string.find(trigger, "death", 1, true) or string.find(trigger, "kill", 1, true) then
				if read(event, "Hunting") ~= true or read(event, "Unique") ~= true or read(event, "Qualified") ~= true then return true end
				state.KillOutcome = delta and (delta > 0 and "Increase" or (delta < 0 and "Decrease" or "Stable")) or nil
				if delta and delta > 0 then
					state.KillMatched = true
					conclude("Kill", "Positive", read(event, "Reason") or "stable hunting speed increased after a unique player death", 99, event)
				elseif delta ~= nil then
					if not state.KillMatched then
						conclude("Kill", "RuleOut", read(event, "Reason") or "stable hunting speed did not rise after a qualified unique player death", 99, event)
					end
				end
			end
		elseif kind == "SaltContactSpeed" then
			if event.Hunting == nil then event.Hunting = event.HuntingAtTouch end
			if not qualifiedSaltContact(event) then return true end
			local outcome = event.Outcome
			if outcome == "TemporaryDropRecovered"
				or outcome == "SlowRecovered"
				or (event.TemporaryDrop == true and event.Recovered == true) then
				state.SaltOutcome = "Matched"
				conclude("Salt", "Positive", event.Reason or "direct hunting salt contact caused a temporary speed reduction followed by recovery", 99, event)
			elseif outcome == "Slow" or event.TemporaryDrop == true then
				if state.SaltOutcome == "Matched" then return true end
				state.SaltOutcome = "Provisional"
				conclude("Salt", "Positive", event.Reason or "direct hunting salt contact produced a temporary speed reduction; recovery is not sampled yet", 80, event)
			elseif event.Completed == true and (outcome == "NoDrop" or event.TemporaryDrop == false) then
				if state.SaltOutcome == "Matched" then return true end
				state.SaltOutcome = "Rejected"
				conclude("Salt", "RuleOut", event.Reason or "a qualified hunting salt contact produced no temporary speed reduction", 99, event)
			end
		else
			if event.Unique ~= true or event.Hunting ~= true or event.Qualified ~= true then return true end
			local direction = event.Direction
			state.KillOutcome = direction
			if direction == "Increase" then
				state.KillMatched = true
				conclude("Kill", "Positive", event.Reason or "stable hunting speed increased after a unique player kill", 99, event)
			elseif event.Completed == true and (direction == "Stable" or direction == "Decrease" or direction == "NoChange") then
				if not state.KillMatched then
					conclude("Kill", "RuleOut", event.Reason or "stable hunting speed did not rise after a qualified unique player kill", 99, event)
				end
			end
		end
		return true
	end

	function observer:Reset() state.SaltOutcome, state.KillOutcome, state.KillMatched, state.EvidenceIds = nil, nil, false, {} end
	function observer:Snapshot() return {Destroyed = state.Destroyed, SaltOutcome = state.SaltOutcome, KillOutcome = state.KillOutcome} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "GhostWriting", "Wither"},
	ObservationEvents = {"SaltContactSpeed", "KillSpeedChange", "SpeedProbeResult", "SpeedProbeRecovery"},
	Perks = {
		["Pretty Sure"] = {"Hunting salt contact causes a temporary speed loss followed by recovery."},
		Maybe = {"Stable speed rises after each unique player kill."},
		Idk = {"Salt disturbance alone and contact outside a hunt are not Aswang tells."},
	},
	CreateObserver = createObserver,
}
