local NAME = "Revenant"

local function createObserver(api)
	local state = {Destroyed = false, LastOutcome = nil, Processed = {}}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "KillHuntOutcome" and kind ~= "HuntEndedAfterDeath" and kind ~= "HuntContinuedAfterDeath" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.ValidMultiplayerKill ~= true or (tonumber(event.OtherAlive) or 0) <= 0 then return true end
		local id = event.DeathEventId or event.DeathId or event.PlayerId or tostring(event.Time or "default")
		if state.Processed[id] then return true end
		local elapsed = tonumber(event.Elapsed)
		if elapsed == nil then return true end
		if (kind == "HuntEndedAfterDeath" or event.HuntStopped == true) and elapsed <= 1.5 then
			state.Processed[id], state.LastOutcome = true, "Stopped"
			if api and type(api.Positive) == "function" then api:Positive(NAME, event.Reason or "the hunt ended within 1.5 seconds of a valid multiplayer kill", 85, event) end
		elseif (kind == "HuntContinuedAfterDeath" or event.Hunting == true) and elapsed >= 1.5 then
			state.Processed[id], state.LastOutcome = true, "Continued"
			if api and type(api.RuleOut) == "function" then api:RuleOut(NAME, event.Reason or "the hunt continued for at least 1.5 seconds after a valid multiplayer kill", 99, event) end
		end
		return true
	end
	function observer:Reset() state.LastOutcome, state.Processed = nil, {} end
	function observer:Snapshot() return {Destroyed = state.Destroyed, LastOutcome = state.LastOutcome, Processed = state.Processed} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "FreezingTemperatures", "GhostWriting"},
	ObservationEvents = {"KillHuntOutcome", "HuntEndedAfterDeath", "HuntContinuedAfterDeath"},
	Perks = { ["Pretty Sure"] = {"The hunt ends within 1.5 seconds after a valid multiplayer kill."}, Maybe = {}, Idk = {"If the hunt continues, Aswang/Keres may use the subsequent speed probe."} },
	CreateObserver = createObserver,
}
