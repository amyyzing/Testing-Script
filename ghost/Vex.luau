local NAME = "Vex"

local function createObserver(api)
	local state = {Destroyed = false, Checked = false, Exists = nil}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or state.Checked or type(event) ~= "table" or (event.Type or event.Kind) ~= "LidarState" then return false end
		local exists = event.Exists
		if type(exists) ~= "boolean" then exists = event.Invisible end
		if type(exists) ~= "boolean" then return true end
		state.Checked, state.Exists = true, exists
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if exists then
			if api and type(api.Positive) == "function" then api:Positive(NAME, event.Reason or "InvisibleOnLIDAR exists or resolves true", 99, event) end
		elseif api and type(api.RuleOut) == "function" then
			api:RuleOut(NAME, event.Reason or "InvisibleOnLIDAR does not exist or resolves false", 99, event)
		end
		return true
	end
	function observer:Reset() state.Checked, state.Exists = false, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, Checked = state.Checked, Exists = state.Exists} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"FreezingTemperatures", "GhostOrb", "Wither"},
	ObservationEvents = {"LidarState"},
	OneShot = true,
	Perks = { ["Pretty Sure"] = {"InvisibleOnLIDAR exists or resolves true on the immediate replicated check."}, Maybe = {}, Idk = {"A missed visual LIDAR frame is not the replicated check."} },
	CreateObserver = createObserver,
}
