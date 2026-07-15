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
		LastWindow = 0,
	}
	local observer = {}

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		if (event.Type or event.Kind) ~= "RoomTemperatureWindow" then return false end
		state.LastRoom = read(event, "RoomName")
		state.LastAverageDecrease = tonumber(read(event, "AverageDecrease"))
		state.LastDecreaseCount = tonumber(read(event, "DecreaseCount")) or 0
		state.LastWindow = tonumber(read(event, "Window")) or 0
		if state.Outcome
			or read(event, "Qualified") ~= true
			or read(event, "Completed") ~= true
			or read(event, "SameRoom") ~= true
			or (tonumber(read(event, "ResidenceSeconds")) or 0) < 5
			or not state.LastAverageDecrease then return true end

		local requiredCoolingChanges = math.max(
			7,
			math.floor(tonumber(read(event, "RequiredCoolingChanges")) or 7)
		)
		if state.LastDecreaseCount < requiredCoolingChanges then return true end
		local outcome = tostring(read(event, "Outcome") or "Inconclusive")
		local shadowThreshold = tonumber(read(event, "ShadowAverageThreshold")) or 0.06
		local ruleOutThreshold = tonumber(read(event, "RuleOutAverageThreshold")) or 0.08

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
		state.LastWindow = 0
	end

	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			Outcome = state.Outcome,
			LastRoom = state.LastRoom,
			LastAverageDecrease = state.LastAverageDecrease,
			LastDecreaseCount = state.LastDecreaseCount,
			LastWindow = state.LastWindow,
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
			"After the exit door opens, seven actual cooling changes in the ghost's current room with an exact average below 0.06°C identify Shadow at 99%.",
		},
		Maybe = {},
		Idk = {
			"One qualified seven-change average above 0.08°C rules Shadow out as a normal-cooling ghost.",
			"Setup-phase temperatures are discarded. Every post-opening cooling change is normalized to the configured sample interval before averaging; increases and unchanged readings are excluded.",
		},
	},
	CreateObserver = createObserver,
}
