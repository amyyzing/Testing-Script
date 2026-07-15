local NAME = "Dullahan"

local function specification(api)
	local all = api and type(api.Specification) == "function" and api:Specification() or {}
	return type(all.SpeedPairs) == "table" and all.SpeedPairs or {}
end

local function createObserver(api)
	local requiredPairs = tonumber(specification(api).RequiredPairs) or 7
	local state = {
		Destroyed = false,
		Outcome = nil,
		DifferentPairs = 0,
		UpwardSteps = 0,
		EvidenceId = nil,
	}
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
		if kind ~= "DullahanPattern" and kind ~= "DullahanPatternAbsent" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Hunting ~= true or event.Qualified ~= true or event.Completed ~= true
			or (tonumber(event.PairCount) or 0) ~= requiredPairs then return true end
		state.DifferentPairs = tonumber(
			event.PatternChangeCount or event.DifferentPairCount or event.DifferentPairs
		) or 0
		state.UpwardSteps = tonumber(event.UpwardStepCount) or 0
		if kind == "DullahanPattern" and event.PhantomExcluded == true
			and state.UpwardSteps > 0 then
			state.Outcome = "Matched"
			conclude(
				"Positive",
				event.Reason or "after Phantom and flat speed were excluded, the seven-pair hunt window contained a nonzero upward speed step",
				event
			)
		elseif kind == "DullahanPatternAbsent" then
			-- Valid Phantom and exactly-flat windows are hard negatives, but a
			-- previously confirmed upward ramp remains the unique stronger tell.
			if state.Outcome == "Matched" then return true end
			state.Outcome = "Rejected"
			conclude(
				"RuleOut",
				event.Reason or "the complete hunt window was a valid Phantom pattern or exactly flat",
				event
			)
		end
		return true
	end

	function observer:Reset()
		state.Outcome, state.DifferentPairs, state.UpwardSteps, state.EvidenceId = nil, 0, 0, nil
	end
	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			Outcome = state.Outcome,
			DifferentPairs = state.DifferentPairs,
			UpwardSteps = state.UpwardSteps,
		}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"FreezingTemperatures", "LaserProjector", "Wither"},
	ObservationEvents = {"DullahanPattern", "DullahanPatternAbsent"},
	Perks = {
		["Pretty Sure"] = {"After valid Phantom and exactly-flat patterns are excluded, any nonzero upward speed step in the complete seven-pair hunt window identifies Dullahan."},
		Maybe = {},
		Idk = {"Decreases and resets are ignored. A complete sequence with no upward interval is inconclusive, including a stable invalid A/B window whose tracked direction only decreases."},
	},
	CreateObserver = createObserver,
}
