local NAME = "Leviathan"

local function createObserver(api)
	local state = {Destroyed = false, ToggleBursts = 0, LightOffs = 0}
	local observer = {}
	local function positive(reason, confidence, event)
		if api and type(api.Positive) == "function" then api:Positive(NAME, reason, confidence, event) end
	end
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "DeviceToggleBurst" and kind ~= "RoomLightOff" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Hunting == true or event.Qualified ~= true or event.PlayerCaused == true or event.AutomationCaused == true or event.FuseCaused == true then return true end
		if kind == "DeviceToggleBurst" and event.SingleDevice == true and event.Rapid == true then
			state.ToggleBursts = state.ToggleBursts + 1
			positive(event.Reason or "one eligible device produced a clean rapid toggle burst outside a hunt", tonumber(event.Confidence) or 80, event)
		elseif kind == "RoomLightOff" and event.WorkingCircuit == true then
			state.LightOffs = state.LightOffs + 1
			positive(event.Reason or "a working room light independently switched off outside a hunt", tonumber(event.Confidence) or 80, event)
		end
		return true
	end
	function observer:Reset() state.ToggleBursts, state.LightOffs = 0, 0 end
	function observer:Snapshot() return {Destroyed = state.Destroyed, ToggleBursts = state.ToggleBursts, LightOffs = state.LightOffs} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"GhostOrb", "GhostWriting", "Handprints"},
	ObservationEvents = {"DeviceToggleBurst", "RoomLightOff"},
	PersistentFindings = true,
	Perks = { ["Pretty Sure"] = {"A working room light shuts off outside a hunt with no player, automation, or fuse cause."}, Maybe = {"One eligible device rapidly toggles outside a hunt."}, Idk = {"Do not require exactly 14 toggles or exactly 1.8 seconds."} },
	CreateObserver = createObserver,
}
