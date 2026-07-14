local NAME = "Wendigo"

local function read(event, key)
	if event[key] ~= nil then return event[key] end
	if type(event.Payload) == "table" then return event.Payload[key] end
	return nil
end

local function fitMatched(fit)
	return type(fit) == "table"
		and (fit.Matched == true or fit.Qualified == true or fit.Fits == true)
end

local function createObserver(api)
	local state = {
		Destroyed = false,
		LastOutcome = nil,
		TransitionCount = 0,
		PairMathCount = 0,
		EvidenceId = nil,
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

	local function consumePairMath(event)
		state.PairMathCount = state.PairMathCount + 1
		if read(event, "Hunting") == false or read(event, "Qualified") ~= true then return end
		local requiredPairs = math.max(7, math.floor(tonumber(read(event, "RequiredPairs")) or 7))
		if math.floor(tonumber(read(event, "PairCount")) or 0) < requiredPairs then return end
		local fits = read(event, "Fits")
		if type(fits) ~= "table" then return end
		local wendigoMatched = fitMatched(fits.Wendigo)
		local normalMatched = fitMatched(fits.Normal)
		local oniMatched = fitMatched(fits.Oni)
		local best = read(event, "Best")
		if best == NAME and wendigoMatched and not normalMatched and not oniMatched then
			state.LastOutcome = "Matched"
			conclude(
				"Positive",
				event.Reason
					or "seven flat hunt-speed pairs uniquely matched the switch-time average-sanity Wendigo curve",
				99,
				event
			)
		elseif not wendigoMatched and (normalMatched or oniMatched) then
			if state.LastOutcome == "Matched" then return end
			state.LastOutcome = "Rejected"
			conclude(
				"RuleOut",
				event.Reason
					or "seven flat hunt-speed pairs matched Normal/Oni math but not the switch-time Wendigo curve",
				99,
				event
			)
		end
	end

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "HuntTransitionSpeedCurve"
			and kind ~= "WendigoCurveResult"
			and kind ~= "HuntSpeedMathResult" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if kind == "HuntSpeedMathResult" then
			consumePairMath(event)
			return true
		end
		if read(event, "Qualified") ~= true then return true end
		if kind == "HuntTransitionSpeedCurve"
			and (read(event, "SanityAtTransition") == nil
				or read(event, "SpeedAtTransition") == nil) then return true end
		state.TransitionCount = state.TransitionCount + 1
		if read(event, "Outcome") == "Matched" or read(event, "Matched") == true then
			state.LastOutcome = "Matched"
			conclude(
				"Positive",
				event.Reason
					or "hunt-transition speed matched the average-sanity curve at one valid multiplier",
				99,
				event
			)
		elseif (read(event, "Outcome") == "Rejected" or read(event, "Matched") == false)
			and (kind == "WendigoCurveResult" or read(event, "Completed") == true) then
			if state.LastOutcome == "Matched" then return true end
			state.LastOutcome = "Rejected"
			conclude(
				"RuleOut",
				event.Reason
					or "qualified hunt-transition speeds could not match the average-sanity curve",
				99,
				event
			)
		end
		return true
	end

	function observer:Reset()
		state.LastOutcome = nil
		state.TransitionCount = 0
		state.PairMathCount = 0
		state.EvidenceId = nil
	end

	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			LastOutcome = state.LastOutcome,
			TransitionCount = state.TransitionCount,
			PairMathCount = state.PairMathCount,
		}
	end

	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"GhostOrb", "GhostWriting", "LaserProjector"},
	ObservationEvents = {
		"HuntTransitionSpeedCurve",
		"WendigoCurveResult",
		"HuntSpeedMathResult",
	},
	Perks = {
		["Pretty Sure"] = {
			"Seven flat hunting pairs uniquely match the hunt-start average-sanity curve, or three transitions match it after at least two sanity points of change.",
		},
		Maybe = {},
		Idk = {
			"A mathematically invalid three-transition curve rules Wendigo out even when sanity spread is small.",
			"Overlapping Normal, Oni, and Wendigo speed fits remain inconclusive.",
		},
	},
	CreateObserver = createObserver,
}
