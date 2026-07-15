local NAME = "Revenant"

local function createObserver(api)
	local spec = api and type(api.Specification) == "function" and api:Specification() or {}
	local revenantSpec = type(spec.Revenant) == "table" and spec.Revenant or {}
	local positiveMax = tonumber(revenantSpec.PositiveMaxSeconds) or 1
	local negativeMin = tonumber(revenantSpec.NegativeMinSeconds) or 1.5
	local state = {Destroyed = false, LastOutcome = nil, Processed = {}}
	local observer = {}

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "HuntEndedAfterDeath" and kind ~= "HuntContinuedAfterDeath" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.ValidMultiplayerKill ~= true or (tonumber(event.OtherAlive) or 0) <= 0 then return true end
		local elapsed = tonumber(event.Elapsed)
		if elapsed == nil then return true end
		local id = event.DeathEventId or event.PlayerId or event.Id or tostring(event.Time or "death")
		if state.Processed[id] then return true end
		if kind == "HuntEndedAfterDeath" and elapsed <= positiveMax then
			state.Processed[id], state.LastOutcome = true, "Stopped"
			if api and type(api.Positive) == "function" then
				api:Positive(NAME, event.Reason or "the hunt ended within one second of a valid multiplayer kill", 99, event)
			end
		elseif kind == "HuntContinuedAfterDeath" and elapsed >= negativeMin then
			state.Processed[id], state.LastOutcome = true, "Continued"
			if api and type(api.RuleOut) == "function" then
				api:RuleOut(NAME, event.Reason or "the hunt continued for at least 1.5 seconds after a valid multiplayer kill", 99, event)
			end
		end
		return true
	end

	function observer:Reset() state.LastOutcome, state.Processed = nil, {} end
	function observer:Snapshot()
		return {Destroyed = state.Destroyed, LastOutcome = state.LastOutcome, Processed = state.Processed}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "FreezingTemperatures", "GhostWriting"},
	ObservationEvents = {"HuntEndedAfterDeath", "HuntContinuedAfterDeath"},
	Perks = {
		["Pretty Sure"] = {"A hunt ends within one second of a valid multiplayer kill."},
		Maybe = {},
		Idk = {"A hunt still active at 1.5 seconds rules Revenant out; an end between 1.0 and 1.5 seconds is inconclusive."},
	},
	CreateObserver = createObserver,
}
