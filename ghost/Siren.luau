local NAME = "Siren"

local function createObserver(api)
	local state = {
		Destroyed = false,
		Humming = false,
		ModelSex = nil,
		LosOutcome = nil,
		EvidenceId = nil,
		Confidence = 0,
		LockedNegative = false,
	}
	local observer = {}

	local function conclude(polarity, reason, confidence, event)
		if state.LockedNegative and polarity == "Positive" then return end
		if polarity == "Positive" and confidence <= state.Confidence then return end
		local entry
		if state.EvidenceId and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, state.EvidenceId, polarity, reason, confidence, event)
		elseif api and type(api[polarity]) == "function" then
			entry = api[polarity](api, NAME, reason, confidence, event)
		end
		state.EvidenceId = type(entry) == "table" and entry.Id or state.EvidenceId
		state.Confidence = confidence
		if polarity ~= "Positive" then state.LockedNegative = true end
	end

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "SpiritBoxResponse" and kind ~= "GhostModelSex"
			and kind ~= "LineOfSightPlayerSpeed" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Qualified ~= true then return true end
		if kind == "SpiritBoxResponse" and event.Response == "- HUMMING -" then
			state.Humming = true
			conclude("Positive", event.Reason or "Spirit Box returned - HUMMING -", 99, event)
		elseif kind == "GhostModelSex" then
			state.ModelSex = event.Sex
			if event.Sex == "Female" then
				conclude("Positive", event.Reason or "the ghost uses a female VisualModel", 25, event)
			elseif event.Sex == "Male" then
				conclude("Negative", event.Reason or "the ghost uses a male VisualModel", 99, event)
			end
		elseif kind == "LineOfSightPlayerSpeed" and event.Hunting == true then
			if event.Slowed == true then
				state.LosOutcome = "Slowed"
				conclude("Positive", event.Reason or "a sprinting player slowed during qualified ghost line of sight", 99, event)
			elseif event.Completed == true and event.Sprinting == true
				and event.Slowed == false then
				state.LosOutcome = "NotSlowed"
				conclude("RuleOut", event.Reason or "a qualified sprinting line-of-sight trial produced no slowdown", 99, event)
			end
		end
		return true
	end

	function observer:Reset()
		state.Humming, state.ModelSex, state.LosOutcome = false, nil, nil
		state.EvidenceId, state.Confidence, state.LockedNegative = nil, 0, false
	end
	function observer:Snapshot()
		return {Destroyed = state.Destroyed, Humming = state.Humming, ModelSex = state.ModelSex, LosOutcome = state.LosOutcome}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "SpiritBox", "Wither"},
	ObservationEvents = {"SpiritBoxResponse", "GhostModelSex", "LineOfSightPlayerSpeed"},
	Perks = {
		["Pretty Sure"] = {"Spirit Box returns - HUMMING -, or a sprinting player slows during qualified line of sight."},
		Maybe = {"A female VisualModel is weak support."},
		Idk = {"A male VisualModel is a 99% negative; a non-sprinting player cannot form the LOS negative."},
	},
	CreateObserver = createObserver,
}
