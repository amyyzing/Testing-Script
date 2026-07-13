local NAME = "Phantom"
local EXPECTED_RATIO = 13.5 / 11

local function createObserver(api)
	local state = {Destroyed = false, LastRatio = nil, Outcome = nil, EvidenceId = nil}
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
		if kind ~= "BlinkSpeedPattern" and kind ~= "PhantomPattern" and kind ~= "FlatHuntSpeed" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Hunting == false or event.Qualified == false then return true end
		local visible, invisible = tonumber(event.VisibleSpeed), tonumber(event.InvisibleSpeed)
		local ratio = tonumber(event.Ratio)
		if ratio == nil and visible and visible > 0 and invisible then ratio = invisible / visible end
		state.LastRatio = ratio
		local tolerance = math.max(0.01, tonumber(event.RatioTolerance) or 0.08)
		local matched = kind == "PhantomPattern" or event.Outcome == "Phantom" or event.Outcome == "PhaseDependent"
			or (event.RepeatedPhases == true and ratio and math.abs(ratio - EXPECTED_RATIO) <= tolerance)
		if matched then
			state.Outcome = "Matched"
			conclude("Positive", event.Reason or "settled invisible speed repeatedly exceeded visible speed by the Phantom ratio", 99, event)
		elseif kind == "FlatHuntSpeed" or (event.Completed == true and (event.Outcome == "Equal" or event.PhaseDependent == false)) then
			if state.Outcome == "Matched" then return true end
			state.Outcome = "Rejected"
			conclude("RuleOut", event.Reason or "qualified invisible and visible hunting speeds remained equal", 99, event)
		end
		return true
	end
	function observer:Reset() state.LastRatio, state.Outcome, state.EvidenceId = nil, nil, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, LastRatio = state.LastRatio, Outcome = state.Outcome} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "GhostOrb", "Handprints"},
	ObservationEvents = {"BlinkSpeedPattern", "PhantomPattern", "FlatHuntSpeed"},
	PersistentFindings = true,
	Perks = { ["Pretty Sure"] = {"Transparency 1 is faster than Transparency 0 by about 13.5/11 within one hunt."}, Maybe = {"One settled visible/invisible pair is provisional."}, Idk = {"Ignore the first replication-edge sample after a blink change."} },
	CreateObserver = createObserver,
}
