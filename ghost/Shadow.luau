local NAME = "Shadow"

local function read(event, key)
	if event[key] ~= nil then return event[key] end
	if type(event.Payload) == "table" then return event.Payload[key] end
	return nil
end

local function createObserver(api)
	local state = {
		Destroyed = false,
		Outcome = nil,
		LastRoom = nil,
		LastAverageDecrease = nil,
		LastMinimumDecrease = nil,
		LastSampleCount = 0,
	}
	local observer = {}

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		if (event.Type or event.Kind) ~= "RoomTemperatureWindow" then return false end
		state.LastRoom = read(event, "RoomName")
		state.LastAverageDecrease = tonumber(read(event, "AverageDecrease"))
		state.LastMinimumDecrease = tonumber(read(event, "MinimumDecrease"))
		state.LastSampleCount = tonumber(read(event, "SampleCount")) or 0
		if state.Outcome
			or read(event, "Qualified") ~= true
			or read(event, "SameRoom") ~= true
			or (tonumber(read(event, "ResidenceSeconds")) or 0) < 5
			or state.LastSampleCount < 20
			or not state.LastAverageDecrease then return true end

		local shadowThreshold = tonumber(read(event, "ShadowAverageThreshold")) or 0.06
		local ruleOutThreshold = tonumber(read(event, "RuleOutAverageThreshold")) or 0.06
		local minimumRuleOutDecrease = tonumber(read(event, "MinimumRuleOutDecrease")) or 0.05
		local shadowObserved = read(event, "ShadowPatternObserved") == true
			or state.LastAverageDecrease < shadowThreshold - 1e-9
		local noSmallDecrease = read(event, "NoDecreaseBelowMinimum") == true
			or (state.LastMinimumDecrease ~= nil
				and state.LastMinimumDecrease + 1e-9 >= minimumRuleOutDecrease)
		local ruleOutObserved = read(event, "RuleOutPatternObserved") == true
			or (state.LastAverageDecrease > ruleOutThreshold + 1e-9
				and noSmallDecrease)

		if shadowObserved then
			state.Outcome = "Matched"
			if api and type(api.Positive) == "function" then
				api:Positive(
					NAME,
					event.Reason
						or ("the ghost stayed in "
							.. tostring(state.LastRoom or "one room")
							.. " and its exact average cooling change was "
							.. tostring(state.LastAverageDecrease)
							.. "°C per sample (Shadow is below "
							.. tostring(shadowThreshold)
							.. "°C)"),
					99,
					event
				)
			end
		elseif ruleOutObserved and noSmallDecrease then
			state.Outcome = "Rejected"
			if api and type(api.RuleOut) == "function" then
				api:RuleOut(
					NAME,
					event.Reason
						or ("the ghost stayed in "
							.. tostring(state.LastRoom or "one room")
							.. ", its exact average cooling change was "
							.. tostring(state.LastAverageDecrease)
							.. "°C per sample, and no cooling sample was below "
							.. tostring(minimumRuleOutDecrease)
							.. "°C"),
					99,
					event
				)
			end
		end
		return true
	end

	function observer:Reset()
		state.Outcome = nil
		state.LastRoom = nil
		state.LastAverageDecrease = nil
		state.LastMinimumDecrease = nil
		state.LastSampleCount = 0
	end

	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			Outcome = state.Outcome,
			LastRoom = state.LastRoom,
			LastAverageDecrease = state.LastAverageDecrease,
			LastMinimumDecrease = state.LastMinimumDecrease,
			LastSampleCount = state.LastSampleCount,
		}
	end

	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "GhostWriting", "LaserProjector"},
	BehaviorStatus = "Observed",
	ObservationEvents = {"RoomTemperatureWindow"},
	Perks = {
		["Pretty Sure"] = {
			"After 20 samples in the ghost's current room, an exact average cooling change below 0.06°C per sample identifies Shadow at 99%.",
		},
		Maybe = {},
		Idk = {
			"An exact average above 0.06°C rules Shadow out only when no cooling sample in the set is below 0.05°C; exactly 0.06°C is inconclusive.",
			"Temperature increases are excluded from the cooling average; samples from any room the ghost is not currently in are discarded.",
		},
	},
	CreateObserver = createObserver,
}
