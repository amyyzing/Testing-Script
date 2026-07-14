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
		LastDecreaseCount = 0,
		LastSampleCount = 0,
	}
	local observer = {}

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		if (event.Type or event.Kind) ~= "RoomTemperatureWindow" then return false end
		state.LastRoom = read(event, "RoomName")
		state.LastAverageDecrease = tonumber(read(event, "AverageDecrease"))
		state.LastDecreaseCount = tonumber(read(event, "DecreaseCount")) or 0
		state.LastSampleCount = tonumber(read(event, "SampleCount")) or 0
		if state.Outcome
			or read(event, "Qualified") ~= true
			or read(event, "SameRoom") ~= true
			or (tonumber(read(event, "ResidenceSeconds")) or 0) < 5
			or state.LastSampleCount < 20
			or not state.LastAverageDecrease then return true end

		local minimumCoolingChanges = math.max(
			3,
			math.floor(tonumber(read(event, "MinimumCoolingChanges")) or 3)
		)
		if state.LastDecreaseCount < minimumCoolingChanges
			or read(event, "SufficientCoolingChanges") ~= true then return true end
		local outcome = tostring(read(event, "Outcome") or "Inconclusive")
		local shadowThreshold = tonumber(read(event, "ShadowAverageThreshold")) or 0.05
		local ruleOutThreshold = tonumber(read(event, "RuleOutAverageThreshold")) or 0.06

		if outcome == "Shadow" then
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
		elseif outcome == "RuleOut" then
			state.Outcome = "Rejected"
			if api and type(api.RuleOut) == "function" then
				api:RuleOut(
					NAME,
					event.Reason
						or ("the ghost stayed in "
							.. tostring(state.LastRoom or "one room")
							.. ", its exact average cooling change was "
							.. tostring(state.LastAverageDecrease)
							.. "°C per sample (Shadow is above "
							.. tostring(ruleOutThreshold)
							.. "°C)"),
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
		state.LastDecreaseCount = 0
		state.LastSampleCount = 0
	end

	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			Outcome = state.Outcome,
			LastRoom = state.LastRoom,
			LastAverageDecrease = state.LastAverageDecrease,
			LastDecreaseCount = state.LastDecreaseCount,
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
			"After 20 readings in the ghost's current room, at least three strict cooling changes with an exact average below 0.05°C identify Shadow at 99%.",
		},
		Maybe = {},
		Idk = {
			"With at least three cooling changes, an exact average above 0.06°C rules Shadow out; averages from 0.05°C through 0.06°C are inconclusive.",
			"Every decreasing change, including outliers, stays in the average. Increases and unchanged pairs are excluded, and temperatures from other rooms are discarded.",
		},
	},
	CreateObserver = createObserver,
}
