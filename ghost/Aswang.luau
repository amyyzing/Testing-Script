local NAME = "Aswang"

local function read(event, key)
	if event[key] ~= nil then return event[key] end
	return type(event.Payload) == "table" and event.Payload[key] or nil
end

local function createObserver(api)
	local spec = api and type(api.Specification) == "function" and api:Specification() or {}
	local probeSpec = type(spec.SpeedProbe) == "table" and spec.SpeedProbe or {}
	local epsilon = math.max(
		tonumber(probeSpec.StableEpsilon) or 0.0001,
		tonumber(probeSpec.MinimumEventDelta) or 0.01
	)
	local state = {
		Destroyed = false,
		SaltOutcome = nil,
		KillOutcome = nil,
		EvidenceIds = {},
	}
	local observer = {}

	local function conclude(domain, polarity, reason, confidence, event)
		local previous = state.EvidenceIds[domain]
		local entry
		if previous and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, previous, polarity, reason, confidence, event)
		elseif api and type(api[polarity]) == "function" then
			entry = api[polarity](api, NAME, reason, confidence, event)
		end
		state.EvidenceIds[domain] = type(entry) == "table" and entry.Id or previous
	end

	local function qualifiedSalt(event)
		local atContact = read(event, "HuntingAtContact")
		if atContact == nil then atContact = read(event, "Hunting") end
		local contactId = read(event, "ContactId")
		local disturbedId = read(event, "DisturbedContactId")
		return atContact == true and read(event, "DirectContact") == true
			and read(event, "SaltDisturbed") == true
			and contactId ~= nil and contactId == disturbedId
	end

	local function delta(event)
		local value = tonumber(read(event, "Delta"))
		if value ~= nil then return value end
		local baseline = tonumber(read(event, "BaselineSpeed"))
		local current = tonumber(read(event, "CurrentSpeed") or read(event, "EventSpeed"))
		return baseline and current and (current - baseline) or nil
	end

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "SpeedProbeResult" and kind ~= "SpeedProbeRecovery" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		local trigger = read(event, "Trigger")

		if trigger == "SaltContact" then
			if not qualifiedSalt(event) then return true end
			local postHunt = read(event, "HuntEndedBeforeSample") == true
			if postHunt and read(event, "PostHuntReferenceQualified") ~= true then
				-- A hunt-to-non-hunt WalkSpeed reset is not an Aswang slowdown.
				-- Post-hunt decisions are accepted only when the probe explicitly
				-- compared samples within the settled non-hunting phase.
				return true
			end
			local change = delta(event)
			if kind == "SpeedProbeRecovery" then
				local baseline = tonumber(read(event, "BaselineSpeed"))
				local slowed = tonumber(read(event, "EventSpeed"))
				local recovered = tonumber(read(event, "RecoverySpeed"))
				if baseline and slowed and recovered and slowed < baseline - epsilon
					and recovered > slowed and recovered >= baseline - epsilon then
					state.SaltOutcome = "Recovered"
					conclude("Salt", "Positive", "during a hunt, direct contact with the same disturbed salt pile caused a temporary speed loss followed by recovery", 99, event)
				end
			elseif change and change < -epsilon then
				state.SaltOutcome = "Slowed"
				conclude("Salt", "Positive", "a qualified hunting salt contact caused a speed loss; recovery is pending", 60, event)
			elseif read(event, "Completed") == true
				and read(event, "Hunting") == true
				and read(event, "HuntEndedBeforeSample") ~= true
				and change and change >= -epsilon then
				state.SaltOutcome = "NoSlowdown"
				conclude("Salt", "RuleOut", "a completed qualified hunting salt contact caused no speed reduction", 99, event)
			end
		elseif trigger == "PlayerDeath" then
			if kind ~= "SpeedProbeResult" or read(event, "Hunting") ~= true
				or read(event, "Unique") ~= true or read(event, "Qualified") ~= true
				or read(event, "Completed") ~= true or read(event, "Stable") ~= true then return true end
			local change = delta(event)
			if change and change > epsilon then
				state.KillOutcome = "Increase"
				conclude("Kill", "Positive", "stable hunting speed permanently rose after a qualified unique player kill", 99, event)
			elseif change ~= nil then
				state.KillOutcome = "NoIncrease"
				conclude("Kill", "RuleOut", "stable hunting speed did not rise after a qualified unique player kill", 99, event)
			end
		end
		return true
	end

	function observer:Reset()
		state.SaltOutcome, state.KillOutcome, state.EvidenceIds = nil, nil, {}
	end
	function observer:Snapshot()
		return {Destroyed = state.Destroyed, SaltOutcome = state.SaltOutcome, KillOutcome = state.KillOutcome}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "GhostWriting", "Wither"},
	ObservationEvents = {"SpeedProbeResult", "SpeedProbeRecovery"},
	Perks = {
		["Pretty Sure"] = {"Hunting contact with disturbed salt causes a temporary speed loss and recovery; stable speed also rises after unique kills."},
		Maybe = {"A qualified salt slowdown before recovery is observed."},
		Idk = {"Salt disturbance without direct hunt-time contact is not an Aswang observation."},
	},
	CreateObserver = createObserver,
}
