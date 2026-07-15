local NAME = "Phantom"
local function createObserver(api)
	local spec = api and type(api.Specification) == "function" and api:Specification() or {}
	local pairSpec = type(spec.SpeedPairs) == "table" and spec.SpeedPairs or {}
	local requiredBySpec = tonumber(pairSpec.RequiredPairs) or 7
	local allowedMultipliers = {}
	for _, raw in ipairs(type(pairSpec.HuntingMultipliers) == "table"
		and pairSpec.HuntingMultipliers or {0.5, 0.75, 1, 1.25, 1.5, 2}) do
		local value = tonumber(raw)
		if value then allowedMultipliers[value] = true end
	end
	local state = {
		Destroyed = false,
		LastRatio = nil,
		Outcome = nil,
		EvidenceId = nil,
		NonHuntOutcome = nil,
		NonHuntEvidenceId = nil,
		MatchLocked = false,
	}
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
	local function concludeNonHunt(polarity, reason, event)
		local entry
		if state.EvidenceId and api and type(api.Supersede) == "function" then
			entry = api:Supersede(
				NAME,
				state.EvidenceId,
				polarity,
				reason,
				polarity == "RuleOut" and 99 or 0,
				event
			)
		elseif polarity == "RuleOut" and api and type(api.RuleOut) == "function" then
			entry = api:RuleOut(NAME, reason, 99, event)
		end
		if type(entry) == "table" then
			state.EvidenceId = entry.Id
			state.NonHuntEvidenceId = entry.Id
		end
	end
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "PhantomPattern" and kind ~= "NonPhantomPattern"
			and kind ~= "NonHuntSpeedMathResult" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if kind == "NonHuntSpeedMathResult" then
			if event.Hunting ~= false or event.Qualified ~= true
				or event.Completed ~= true or type(event.Matched) ~= "boolean" then
				return true
			end
			if state.MatchLocked then return true end
			local outcome = event.Matched and "Matched" or "Rejected"
			if state.NonHuntOutcome == outcome then return true end
			state.NonHuntOutcome = outcome
			if event.Matched then
				if state.NonHuntEvidenceId then
					concludeNonHunt(
						"Observation",
						event.Reason or "settled non-hunting speed returned to base 11",
						event
					)
				end
			else
				concludeNonHunt(
					"RuleOut",
					event.Reason or "settled non-hunting speed did not return to base 11",
					event
				)
			end
			return true
		end
		if event.Hunting ~= true or event.Qualified ~= true
			or event.Completed ~= true then return true end
		if kind == "PhantomPattern" or kind == "NonPhantomPattern" then
			if math.floor(tonumber(event.PairCount) or 0) ~= requiredBySpec
				or (event.RequiredPairs ~= nil
					and math.floor(tonumber(event.RequiredPairs) or 0) ~= requiredBySpec) then
				return true
			end
		end
		state.LastRatio = tonumber(event.Ratio)
		local outcome = kind == "PhantomPattern" and "Matched" or "Rejected"
		local multiplier = tonumber(event.Multiplier)
		if outcome == "Matched"
			and (event.AbsoluteBaseFit ~= true or not allowedMultipliers[multiplier]) then
			return true
		end
		-- A confirmed absolute 11/13.5 match is the unique Phantom tell. One
		-- later noisy non-match (or any number of duplicates) cannot erase it.
		if state.MatchLocked and outcome == "Rejected" then return true end
		if state.Outcome == outcome then return true end
		state.Outcome = outcome
		if outcome == "Matched" then
			state.MatchLocked = true
			conclude("Positive", event.Reason or "seven stable A/B pairs fit Phantom's absolute 11/13.5 bases under one legal multiplier", 99, event)
		else
			conclude(
				"RuleOut",
				event.Reason or "the complete seven-pair window was not an absolute-base-valid Phantom A/B pattern",
				99,
				event
			)
		end
		return true
	end
	function observer:Reset()
		state.LastRatio, state.Outcome, state.EvidenceId = nil, nil, nil
		state.NonHuntOutcome, state.NonHuntEvidenceId = nil, nil
		state.MatchLocked = false
	end
	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			LastRatio = state.LastRatio,
			Outcome = state.Outcome,
			NonHuntOutcome = state.NonHuntOutcome,
			MatchLocked = state.MatchLocked,
		}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "GhostOrb", "Handprints"},
	ObservationEvents = {"PhantomPattern", "NonPhantomPattern", "NonHuntSpeedMathResult"},
	Perks = {
		["Pretty Sure"] = {"All seven blink pairs repeat one visible A and invisible B, and one legal hunting multiplier fits map-normalized bases 11 and 13.5."},
		Maybe = {"Fewer than exactly seven settled I/V pairs are provisional."},
		Idk = {"A matching 13.5/11 ratio alone is insufficient; both absolute bases must share one multiplier."},
	},
	CreateObserver = createObserver,
}
