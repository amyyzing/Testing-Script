local NAME = "Wendigo"

local function createObserver(api)
	local state = {Destroyed = false, LastOutcome = nil, TransitionCount = 0, EvidenceId = nil}
	local observer = {}
	local function conclude(polarity, reason, confidence, event)
		local entry
		if state.EvidenceId and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, state.EvidenceId, polarity, reason, confidence, event)
		elseif api and type(api[polarity]) == "function" then
			entry = api[polarity](api, NAME, reason, confidence, event)
		end
		state.EvidenceId = type(entry) == "table" and entry.Id or state.EvidenceId
	end
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "HuntTransitionSpeedCurve" and kind ~= "WendigoCurveResult" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Qualified ~= true then return true end
		if kind == "HuntTransitionSpeedCurve" and (event.SanityAtTransition == nil or event.SpeedAtTransition == nil) then return true end
		state.TransitionCount = state.TransitionCount + 1
		if event.Outcome == "Matched" or event.Matched == true then
			state.LastOutcome = "Matched"
			conclude("Positive", event.Reason or "hunt-transition speed matched the average-sanity curve at one valid multiplier", 99, event)
		elseif (event.Outcome == "Rejected" or event.Matched == false) and (kind == "WendigoCurveResult" or event.Completed == true) then
			if state.LastOutcome == "Matched" then return true end
			state.LastOutcome = "Rejected"
			conclude("RuleOut", event.Reason or "qualified hunt-transition speeds could not match the average-sanity curve", 99, event)
		end
		return true
	end
	function observer:Reset() state.LastOutcome, state.TransitionCount, state.EvidenceId = nil, 0, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, LastOutcome = state.LastOutcome, TransitionCount = state.TransitionCount} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"GhostOrb", "GhostWriting", "LaserProjector"},
	ObservationEvents = {"HuntTransitionSpeedCurve", "WendigoCurveResult"},
	Perks = { ["Pretty Sure"] = {"Speed captured at hunt-state transitions follows average player Energy under one multiplier."}, Maybe = {}, Idk = {"Do not expect live speed to change between hunt-state transitions."} },
	CreateObserver = createObserver,
}
