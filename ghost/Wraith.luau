local NAME = "Wraith"

local function read(event, key)
	if event[key] ~= nil then return event[key] end
	return type(event.Payload) == "table" and event.Payload[key] or nil
end

local function createObserver(api)
	local spec = api and type(api.Specification) == "function" and api:Specification() or {}
	local saltSpec = type(spec.Salt) == "table" and spec.Salt or {}
	local delay = tonumber(saltSpec.UndisturbedDelay) or 1.25
	local state = {Destroyed = false, Outcome = nil, EvidenceId = nil, Disturbed = false}
	local observer = {}

	local function conclude(polarity, reason, event)
		local entry
		if state.EvidenceId and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, state.EvidenceId, polarity, reason, 99, event)
		elseif api and type(api[polarity]) == "function" then
			entry = api[polarity](api, NAME, reason, 99, event)
		end
		state.EvidenceId = type(entry) == "table" and entry.Id or state.EvidenceId
	end

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "SaltContactResult" and kind ~= "SaltDisturbed" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if kind == "SaltDisturbed" and read(event, "Disturbed") == true then
			if not state.Disturbed then
				state.Disturbed, state.Outcome = true, "Disturbed"
				conclude("RuleOut", event.Reason or "a DisturbedSaltLine exists, so the ghost can disturb salt", event)
			end
			return true
		end
		if state.Disturbed or read(event, "DirectContact") ~= true
			or read(event, "Completed") ~= true or read(event, "Disturbed") ~= false
			or (tonumber(read(event, "Elapsed")) or 0) < delay then return true end
		if state.Outcome == nil then
			state.Outcome = "Undisturbed"
			conclude(
				"Positive",
				"a directly touched salt pile remained undisturbed for at least " .. tostring(delay) .. " seconds",
				event
			)
		end
		return true
	end

	function observer:Reset()
		state.Outcome, state.EvidenceId, state.Disturbed = nil, nil, false
	end
	function observer:Snapshot()
		return {Destroyed = state.Destroyed, Outcome = state.Outcome, Disturbed = state.Disturbed}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "LaserProjector", "SpiritBox"},
	ObservationEvents = {"SaltContactResult", "SaltDisturbed"},
	Perks = {
		["Pretty Sure"] = {"A directly observed salt touch remains undisturbed for at least 1.25 seconds, regardless of hunt state."},
		Maybe = {},
		Idk = {"Any replicated DisturbedSaltLine supersedes the undisturbed observation and rules Wraith out."},
	},
	CreateObserver = createObserver,
}
