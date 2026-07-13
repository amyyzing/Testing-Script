local NAME = "Ravager"

local function createObserver(api)
	local state = {Destroyed = false, Matched = false, LastObjectCount = 0}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" or (event.Type or event.Kind) ~= "VortexPattern" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Hunting ~= true or event.Qualified ~= true then return true end
		local count = math.floor(tonumber(event.DistinctObjects) or 0)
		local duration = tonumber(event.Duration) or 0
		local intervals = math.floor(tonumber(event.Intervals) or 0)
		local goodShare = tonumber(event.GoodShare) or 0
		local angle = tonumber(event.AccumulatedAngle) or 0
		state.LastObjectCount = count
		if count >= 3 and duration >= 0.5 and intervals >= 5 and goodShare >= 0.7 and angle >= 35 then
			state.Matched = true
			if api and type(api.Positive) == "function" then api:Positive(NAME, event.Reason or "at least three distinct objects rapidly orbited the moving ghost for at least 0.5 seconds", 99, event) end
		end
		return true
	end
	function observer:Reset() state.Matched, state.LastObjectCount = false, 0 end
	function observer:Snapshot() return {Destroyed = state.Destroyed, Matched = state.Matched, LastObjectCount = state.LastObjectCount} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "GhostWriting", "SpiritBox"},
	ObservationEvents = {"VortexPattern"},
	Perks = { ["Pretty Sure"] = {"Three distinct item/interactable assemblies orbit the moving ghost for at least 0.5 seconds."}, Maybe = {}, Idk = {"One throw or straight-line object motion is insufficient."} },
	CreateObserver = createObserver,
}
