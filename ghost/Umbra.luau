local NAME = "Umbra"

local function createObserver(api)
	local state = {Destroyed = false, Checked = false, HasOtherSound = nil}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or state.Checked or type(event) ~= "table" or (event.Type or event.Kind) ~= "RootSoundScan" then return false end
		if event.Qualified ~= true or type(event.HasOtherSound) ~= "boolean" then return true end
		state.Checked, state.HasOtherSound = true, event.HasOtherSound
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.HasOtherSound == false then
			if api and type(api.Positive) == "function" then api:Positive(NAME, event.Reason or "HumanoidRootPart contained no Sound other than Hunting on the immediate scan", 99, event) end
		elseif api and type(api.RuleOut) == "function" then
			api:RuleOut(NAME, event.Reason or "HumanoidRootPart contained a Sound other than Hunting on the immediate scan", 99, event)
		end
		return true
	end
	function observer:Reset() state.Checked, state.HasOtherSound = false, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, Checked = state.Checked, HasOtherSound = state.HasOtherSound} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"GhostOrb", "Handprints", "LaserProjector"},
	ObservationEvents = {"RootSoundScan"},
	OneShot = true,
	Perks = { ["Pretty Sure"] = {"The immediate HumanoidRootPart scan contains no Sound except Hunting."}, Maybe = {}, Idk = {"Scan once; do not wait for later sounds."} },
	CreateObserver = createObserver,
}
