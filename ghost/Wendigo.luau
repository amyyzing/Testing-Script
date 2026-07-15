local NAME = "Wendigo"

local function createObserver(api)
	local state = {Destroyed = false, Outcome = nil, TransitionCount = 0, EvidenceId = nil}
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
		if state.Destroyed or type(event) ~= "table"
			or (event.Type or event.Kind) ~= "WendigoCurveResult" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Qualified ~= true or event.Completed ~= true then return true end
		if state.Outcome == "Matched" then return true end
		local snapshots = type(event.Snapshots) == "table" and event.Snapshots or {}
		state.TransitionCount = #snapshots
		if event.Outcome == "Matched" and event.Matched == true then
			state.Outcome = "Matched"
			conclude(
				"Positive",
				event.Reason or "settled speed at alternating hunt-state transitions matched switch-time average sanity",
				event
			)
		elseif event.Outcome == "Rejected" then
			state.Outcome = "Rejected"
			conclude(
				"RuleOut",
				event.Reason or "settled transition speed did not match average sanity captured at the hunt-state switch",
				event
			)
		end
		return true
	end

	function observer:Reset()
		state.Outcome, state.TransitionCount, state.EvidenceId = nil, 0, nil
	end
	function observer:Snapshot()
		return {Destroyed = state.Destroyed, Outcome = state.Outcome, TransitionCount = state.TransitionCount}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"GhostOrb", "GhostWriting", "LaserProjector"},
	ObservationEvents = {"WendigoCurveResult"},
	Perks = {
		["Pretty Sure"] = {"At hunt/non-hunt switches, settled WalkSpeed follows average sanity captured at that exact transition."},
		Maybe = {},
		Idk = {"Blink-pair hunt math does not identify Wendigo; only transition-time sanity snapshots do."},
	},
	CreateObserver = createObserver,
}
