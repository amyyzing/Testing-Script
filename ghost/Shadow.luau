local NAME = "Shadow"

local function read(event, key)
	if event[key] ~= nil then return event[key] end
	if type(event.Payload) == "table" then return event.Payload[key] end
	return nil
end

local function createObserver(api)
	local state = {
		Destroyed = false,
		RuleOutEmitted = false,
		LastRoom = nil,
		LastMaxDecrease = nil,
		LastSampleCount = 0,
	}
	local observer = {}

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		if (event.Type or event.Kind) ~= "RoomTemperatureWindow" then return false end
		state.LastRoom = read(event, "RoomName")
		state.LastMaxDecrease = tonumber(read(event, "MaxDecreaseStep"))
		state.LastSampleCount = tonumber(read(event, "SampleCount")) or 0
		if state.RuleOutEmitted
			or read(event, "Qualified") ~= true
			or read(event, "SameRoom") ~= true
			or (tonumber(read(event, "ResidenceSeconds")) or 0) < 5
			or state.LastSampleCount < 20
			or read(event, "NormalDropObserved") ~= true
			or not state.LastMaxDecrease
			or state.LastMaxDecrease + 1e-6 < 0.2 then
			return true
		end
		state.RuleOutEmitted = true
		if api and type(api.RuleOut) == "function" then
			api:RuleOut(
				NAME,
				event.Reason
					or ("the ghost stayed in "
						.. tostring(state.LastRoom or "one room")
						.. " for at least five seconds and its temperature dropped "
						.. string.format("%.2f°C", state.LastMaxDecrease)
						.. " in one sampled step"),
				99,
				event
			)
		end
		return true
	end

	function observer:Reset()
		state.RuleOutEmitted = false
		state.LastRoom = nil
		state.LastMaxDecrease = nil
		state.LastSampleCount = 0
	end

	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			RuleOutEmitted = state.RuleOutEmitted,
			LastRoom = state.LastRoom,
			LastMaxDecrease = state.LastMaxDecrease,
			LastSampleCount = state.LastSampleCount,
		}
	end

	function observer:Destroy()
		state.Destroyed = true
	end

	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "GhostWriting", "LaserProjector"},
	BehaviorStatus = "Observed",
	ObservationEvents = {"RoomTemperatureWindow"},
	Perks = {
		["Pretty Sure"] = {},
		Maybe = {},
		Idk = {
			"Only temperatures from the ghost's current room count. After five continuous seconds and about 20 samples, any one-step decrease of at least 0.20°C rules Shadow out at 99%.",
			"Temperature increases are ignored; a slow window alone does not prove Shadow.",
		},
	},
	CreateObserver = createObserver,
}
