local NAME = "Leviathan"

local function createObserver(api)
	local state = {Destroyed = false, ToggleBursts = 0, LightOffs = 0, EvidenceId = nil}
	local observer = {}
	local function conclude(reason, confidence, event)
		local entry
		if state.EvidenceId and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, state.EvidenceId, "Positive", reason, confidence, event)
		elseif api and type(api.Positive) == "function" then
			entry = api:Positive(NAME, reason, confidence, event)
		end
		state.EvidenceId = type(entry) == "table" and entry.Id or state.EvidenceId
	end
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "DeviceToggleBurst" and kind ~= "RoomLightOff" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Hunting == true or event.Qualified ~= true or event.PlayerCaused == true or event.AutomationCaused == true or event.FuseCaused == true then return true end
		if kind == "DeviceToggleBurst" and event.SingleDevice == true and event.Rapid == true then
			state.ToggleBursts = state.ToggleBursts + 1
			if state.ToggleBursts == 1 then
				conclude(
					state.LightOffs > 0
						and "both an eligible rapid equipment flicker and a working light shutoff occurred outside hunts"
						or (event.Reason or "one eligible device produced a clean rapid toggle burst outside a hunt"),
					state.LightOffs > 0 and 99 or 60,
					event
				)
			end
		elseif kind == "RoomLightOff" and event.WorkingCircuit == true then
			state.LightOffs = state.LightOffs + 1
			if state.LightOffs == 1 then
				conclude(
					state.ToggleBursts > 0
						and "both an eligible rapid equipment flicker and a working light shutoff occurred outside hunts"
						or (event.Reason or "a working room light independently switched off outside a hunt"),
					state.ToggleBursts > 0 and 99 or 60,
					event
				)
			end
		end
		return true
	end
	function observer:Reset() state.ToggleBursts, state.LightOffs, state.EvidenceId = 0, 0, nil end
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
