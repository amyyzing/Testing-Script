local NAME = "Specter"

local function createObserver(api)
	local state = {
		Destroyed = false,
		Trials = {},
		ResidenceCount = 0,
		LastOutcome = nil,
		DecisionEvidenceId = nil,
		RuledOut = false,
	}
	local observer = {}
	local function conclude(polarity, reason, confidence, event)
		local entry
		if state.DecisionEvidenceId
			and api and type(api.Supersede) == "function" then
			entry = api:Supersede(
				NAME,
				state.DecisionEvidenceId,
				polarity,
				reason,
				confidence,
				event
			)
		else
			local callback = api and api[polarity]
			if type(callback) == "function" then
				entry = callback(api, NAME, reason, confidence, event)
			end
		end
		state.DecisionEvidenceId = type(entry) == "table"
			and entry.Id or state.DecisionEvidenceId
	end
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" or (event.Type or event.Kind) ~= "SpecterTrial" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Qualified ~= true or event.Completed ~= true or event.FavouriteRoomUnchanged ~= true or (tonumber(event.ArmedSeconds) or 0) < 5 then return true end
		local id = event.TrialId or event.HuntId or tostring(event.StartTime or "default")
		if state.Trials[id] ~= nil then return true end
		if event.Outcome == "Residence" then
			state.Trials[id], state.LastOutcome = "Residence", "Residence"
			-- A qualified departure is conclusive. Later residence windows cannot
			-- resurrect Specter or leave a stale positive beside its rule-out.
			if state.RuledOut then return true end
			state.ResidenceCount = state.ResidenceCount + 1
			local confidence = state.ResidenceCount >= 2 and 65 or 35
			conclude(
				"Positive",
				event.Reason or "the ghost remained in its unchanged favourite room from the five-second arm point until hunt start",
				confidence,
				event
			)
		elseif event.Outcome == "Departure" then
			state.Trials[id], state.LastOutcome = "Departure", "Departure"
			state.RuledOut = true
			conclude(
				"RuleOut",
				event.Reason or "the non-hunting ghost left its unchanged favourite room after the five-second arm point",
				95,
				event
			)
		end
		return true
	end
	function observer:Reset()
		state.Trials = {}
		state.ResidenceCount = 0
		state.LastOutcome = nil
		state.DecisionEvidenceId = nil
		state.RuledOut = false
	end
	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			Trials = state.Trials,
			ResidenceCount = state.ResidenceCount,
			LastOutcome = state.LastOutcome,
			RuledOut = state.RuledOut,
		}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "FreezingTemperatures", "LaserProjector"},
	ObservationEvents = {"SpecterTrial"},
	PersistentFindings = true,
	Perks = { ["Pretty Sure"] = {"Repeated qualified trials keep the ghost in its unchanged favourite room until hunt start."}, Maybe = {}, Idk = {"One TrialId can terminate as Residence or Departure, never both."} },
	CreateObserver = createObserver,
}
