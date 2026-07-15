local NAME = "Phantom"
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
		if kind ~= "PhantomPattern" and kind ~= "FlatHuntSpeed"
			and kind ~= "DullahanPattern" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Hunting == false or event.Qualified == false then return true end
		if kind == "PhantomPattern" or kind == "FlatHuntSpeed"
			or kind == "DullahanPattern" then
			local requiredPairs = math.max(7, math.floor(tonumber(event.RequiredPairs) or 7))
			if math.floor(tonumber(event.PairCount) or 0) < requiredPairs then return true end
		end
		state.LastRatio = tonumber(event.Ratio)
		if kind == "PhantomPattern" then
			state.Outcome = "Matched"
			conclude("Positive", event.Reason or "settled invisible speed repeatedly exceeded visible speed by the Phantom ratio", 99, event)
		else
			if state.Outcome == "Matched" then return true end
			state.Outcome = "Rejected"
			conclude(
				"RuleOut",
				event.Reason or (kind == "DullahanPattern"
					and "all seven qualified visibility pairs followed a differing Dullahan pattern instead of the Phantom ratio"
					or "qualified invisible and visible hunting speeds remained equal"),
				99,
				event
			)
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
	ObservationEvents = {"PhantomPattern", "FlatHuntSpeed", "DullahanPattern"},
	PersistentFindings = true,
	Perks = { ["Pretty Sure"] = {"Each of seven local blink/non-blink AB pairs has a Transparency 1 versus Transparency 0 speed ratio of about 13.5/11; absolute drift between pairs is allowed."}, Maybe = {"Fewer than seven settled AB pairs are provisional."}, Idk = {"Pair by blink state after the replication edge instead of grouping all visible and invisible samples globally."} },
	CreateObserver = createObserver,
}
