local NAME = "Ghoul"

local function createObserver(api)
	local state = {Destroyed = false, DisabledObserved = false}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" or (event.Type or event.Kind) ~= "HuntElectronicDisabled" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Hunting == true and event.Qualified == true and event.PlayerCaused ~= true and event.AutomationCaused ~= true then
			state.DisabledObserved = true
			if api and type(api.RuleOut) == "function" then api:RuleOut(NAME, event.Reason or "an electronic was disabled near the hunting ghost without a nearby player cause", 99, event) end
		end
		return true
	end
	function observer:Reset() state.DisabledObserved = false end
	function observer:Snapshot() return {Destroyed = state.Destroyed, DisabledObserved = state.DisabledObserved} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"FreezingTemperatures", "GhostOrb", "SpiritBox"},
	ObservationEvents = {"HuntElectronicDisabled"},
	Perks = { ["Pretty Sure"] = {}, Maybe = {}, Idk = {"This profile currently has a qualified rule-out only."} },
	CreateObserver = createObserver,
}
