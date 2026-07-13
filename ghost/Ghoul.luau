local SOURCE = "https://demonology.fandom.com/wiki/Ghoul"

local function createObserver(api)
	local state = {
		DisabledObserved = false,
		LastReason = nil,
	}
	local observer = {}

	function observer:Reset()
		state.DisabledObserved = false
		state.LastReason = nil
	end

	function observer:OnElectronicDisabled(event)
		event = type(event) == "table" and event or {}
		if event.RawObservation == true then
			local ghostDistance = tonumber(event.GhostDistance)
			local nearestPlayerDistance = tonumber(event.NearestPlayerDistance)
			if event.Hunting ~= true
				or event.AutomationSuppressed == true
				or event.Suppressed == true
				or event.Previous ~= true
				or event.Current ~= false
				or not ghostDistance
				or not nearestPlayerDistance
				or ghostDistance > 40
				or not (
					nearestPlayerDistance > 12
					or ghostDistance + 3 < nearestPlayerDistance
				) then
				return
			end
		end
		state.DisabledObserved = true
		state.LastReason = event.Reason
		api:RuleOut(
			"Ghoul",
			event.Reason
				or "a world electronic was disabled near the ghost while no player was the nearer cause",
			98
		)
		api:Refresh()
	end

	function observer:Snapshot()
		return {
			DisabledObserved = state.DisabledObserved,
			LastReason = state.LastReason,
		}
	end

	return observer
end

return {
	Name = "Ghoul",
	Evidence = {"FreezingTemperatures", "GhostOrb", "SpiritBox"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	ObservationKeys = {"HuntElectronicDisable"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "Nearby electronics and Video Camera remain enabled and do not static during a hunt.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Weakness",
				Conditions = "The EMF Reader can still malfunction because it is not switched off.",
			},
		},
		["Maybe"] = {
			{
				Text = "Repeated Spirit Box use or talking appears to trigger a hunt below the normal energy threshold.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "Electronics looked normal without confirming the hunting ghost was nearby.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Caveat",
			},
		},
	},
}
