local NAME = "Keres"

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
	local state = {Destroyed = false, KillOutcome = nil, ModelSex = nil, KillEvidenceId = nil}
	local observer = {}

	local function concludeKill(polarity, reason, event)
		local entry
		if state.KillEvidenceId and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, state.KillEvidenceId, polarity, reason, 99, event)
		elseif api and type(api[polarity]) == "function" then
			entry = api[polarity](api, NAME, reason, 99, event)
		end
		state.KillEvidenceId = type(entry) == "table" and entry.Id or state.KillEvidenceId
	end

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "SpeedProbeResult" and kind ~= "GhostModelSex" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if kind == "GhostModelSex" then
			if event.Qualified ~= true then return true end
			state.ModelSex = event.Sex
			if event.Sex == "Female" and api and type(api.Positive) == "function" then
				api:Positive(NAME, event.Reason or "the ghost uses a female VisualModel", 25, event)
			elseif event.Sex == "Male" and api and type(api.Negative) == "function" then
				api:Negative(NAME, event.Reason or "the ghost uses a male VisualModel", 99, event)
			end
			return true
		end
		if read(event, "Trigger") ~= "PlayerDeath" or read(event, "Hunting") ~= true
			or read(event, "Unique") ~= true or read(event, "Qualified") ~= true
			or read(event, "Completed") ~= true or read(event, "Stable") ~= true then return true end
		local change = tonumber(read(event, "Delta"))
		if change == nil then
			local baseline = tonumber(read(event, "BaselineSpeed"))
			local current = tonumber(read(event, "CurrentSpeed"))
			if baseline and current then change = current - baseline end
		end
		if change and change < -epsilon then
			state.KillOutcome = "Decrease"
			concludeKill("Positive", "stable hunting speed decreased after a qualified unique player kill", event)
		elseif change ~= nil then
			state.KillOutcome = "NoDecrease"
			concludeKill("RuleOut", "stable hunting speed did not decrease after a qualified unique player kill", event)
		end
		return true
	end

	function observer:Reset()
		state.KillOutcome, state.ModelSex, state.KillEvidenceId = nil, nil, nil
	end
	function observer:Snapshot()
		return {Destroyed = state.Destroyed, KillOutcome = state.KillOutcome, ModelSex = state.ModelSex}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"Handprints", "SpiritBox", "Wither"},
	ObservationEvents = {"SpeedProbeResult", "GhostModelSex"},
	Perks = {
		["Pretty Sure"] = {"Stable hunting speed decreases after a qualified unique player kill."},
		Maybe = {"A female VisualModel is weak support."},
		Idk = {"A male VisualModel is a 99% negative."},
	},
	CreateObserver = createObserver,
}
