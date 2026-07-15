local NAME = "Ghoul"

local function createObserver(api)
	local state = {Destroyed = false, DisabledObserved = false}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" or (event.Type or event.Kind) ~= "HuntElectronicDisabled" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		local noNearbyPlayer = event.NoPlayerWithin15 == true
			or (tonumber(event.NearestPlayerDistance) or -math.huge) > 15
		if event.Qualified == true and noNearbyPlayer
			and event.PlayerCaused ~= true and event.AutomationCaused ~= true then
			state.DisabledObserved = true
			if api and type(api.RuleOut) == "function" then api:RuleOut(NAME, event.Reason or "an electronic was disabled without any player within 15 studs", 99, event) end
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
