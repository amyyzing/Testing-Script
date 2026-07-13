local NAME = "Banshee"

local function createObserver(api)
	local state = {Destroyed = false, LastCount = 0}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" or (event.Type or event.Kind) ~= "BrokenGlassBurst" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		local count, window = tonumber(event.Count) or 0, tonumber(event.Window) or math.huge
		state.LastCount = count
		if event.Qualified == true and count >= 2 and window <= 2.5 and api and type(api.Positive) == "function" then
			api:Positive(NAME, event.Reason or "at least two new BrokenGlass models appeared within 2.5 seconds", 85, event)
		end
		return true
	end
	function observer:Reset() state.LastCount = 0 end
	function observer:Snapshot() return {Destroyed = state.Destroyed, LastCount = state.LastCount} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"FreezingTemperatures", "GhostOrb", "Handprints"},
	ObservationEvents = {"BrokenGlassBurst"},
	Perks = { ["Pretty Sure"] = {"Two or more distinct new BrokenGlass models form one short burst."}, Maybe = {}, Idk = {"One glass break is not diagnostic."} },
	CreateObserver = createObserver,
}
