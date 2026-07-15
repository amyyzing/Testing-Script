local NAME = "Banshee"

local function createObserver(api)
	local specification = api and type(api.Specification) == "function"
		and api:Specification() or {}
	local bansheeSpec = type(specification.Banshee) == "table"
		and specification.Banshee or {}
	local required = tonumber(bansheeSpec.RequiredBrokenGlass) or 2
	local maximumWindow = tonumber(bansheeSpec.WindowSeconds) or 5
	local state = {Destroyed = false, LastCount = 0}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" or (event.Type or event.Kind) ~= "BrokenGlassBurst" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		local count, window = tonumber(event.Count) or 0, tonumber(event.Window) or math.huge
		state.LastCount = count
		if event.Qualified == true and count >= required and window <= maximumWindow
			and api and type(api.Positive) == "function" then
			api:Positive(NAME, event.Reason or "at least two distinct new BrokenGlass models appeared within five seconds", 99, event)
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
	Perks = { ["Pretty Sure"] = {"Two or more distinct new BrokenGlass models appear within five seconds."}, Maybe = {}, Idk = {"One glass break is not diagnostic."} },
	CreateObserver = createObserver,
}
