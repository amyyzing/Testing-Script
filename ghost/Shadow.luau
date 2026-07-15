local NAME = "Shadow"

local function read(event, key)
	if event[key] ~= nil then return event[key] end
	return type(event.Payload) == "table" and event.Payload[key] or nil
end

local function createObserver(api)
	local spec = api and type(api.Specification) == "function" and api:Specification() or {}
	local temperatureSpec = type(spec.RoomTemperature) == "table"
		and spec.RoomTemperature or {}
	local requiredChanges = tonumber(temperatureSpec.RequiredCoolingChanges) or 7
	local threshold = tonumber(temperatureSpec.ShadowThreshold) or 0.08
	local comparisonEpsilon = tonumber(temperatureSpec.ComparisonEpsilon) or 1e-9
	local residenceRequired = tonumber(temperatureSpec.ResidenceSeconds) or 5
	local state = {
		Destroyed = false,
		Outcome = nil,
		LastRoom = nil,
		LastAverageDecrease = nil,
		LastDecreaseCount = 0,
	}
	local observer = {}

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table"
			or (event.Type or event.Kind) ~= "RoomTemperatureWindow" then return false end
		state.LastRoom = read(event, "RoomName")
		state.LastAverageDecrease = tonumber(read(event, "AverageDecrease"))
		state.LastDecreaseCount = tonumber(read(event, "DecreaseCount")) or 0
		if state.Outcome or read(event, "Qualified") ~= true
			or read(event, "Completed") ~= true or read(event, "SameRoom") ~= true
			or (tonumber(read(event, "ResidenceSeconds")) or 0) < residenceRequired
			or state.LastDecreaseCount < requiredChanges
			or state.LastAverageDecrease == nil then return true end

		-- Recompute the one exact boundary from the raw arithmetic average instead
		-- of trusting stale flags produced by an older tracker version.
		if state.LastAverageDecrease < threshold - comparisonEpsilon then
			state.Outcome = "Matched"
			if api and type(api.Positive) == "function" then
				api:Positive(
					NAME,
					event.Reason or ("seven raw cooling changes in "
						.. tostring(state.LastRoom or "one room")
						.. " averaged " .. tostring(state.LastAverageDecrease)
						.. ", below the Shadow boundary " .. tostring(threshold)),
					99,
					event
				)
			end
		else
			state.Outcome = "Rejected"
			if api and type(api.RuleOut) == "function" then
				api:RuleOut(
					NAME,
					event.Reason or ("seven raw cooling changes in "
						.. tostring(state.LastRoom or "one room")
						.. " averaged " .. tostring(state.LastAverageDecrease)
						.. ", at or above the Shadow boundary " .. tostring(threshold)),
					99,
					event
				)
			end
		end
		return true
	end

	function observer:Reset()
		state.Outcome, state.LastRoom, state.LastAverageDecrease = nil, nil, nil
		state.LastDecreaseCount = 0
	end
	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			Outcome = state.Outcome,
			LastRoom = state.LastRoom,
			LastAverageDecrease = state.LastAverageDecrease,
			LastDecreaseCount = state.LastDecreaseCount,
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
		["Pretty Sure"] = {"After round start and five seconds in one room, seven raw cooling changes averaging below 0.08 identify Shadow."},
		Maybe = {},
		Idk = {"An average at or above 0.08 rules Shadow out; increases and unchanged readings are excluded, but cooling outliers remain in the arithmetic average."},
	},
	CreateObserver = createObserver,
}
