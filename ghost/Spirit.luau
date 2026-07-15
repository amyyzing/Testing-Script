local NAME = "Spirit"

local function createObserver(api)
	local state = {Destroyed = false, Checked = false, Blue = nil, EvidenceId = nil}
	local observer = {}
	local function conclude(polarity, reason, event)
		local entry
		if state.EvidenceId and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, state.EvidenceId, polarity, reason, 99, event)
		elseif api and type(api[polarity]) == "function" then
			entry = api[polarity](api, NAME, reason, 99, event)
		end
		state.EvidenceId = type(entry) == "table" and entry.Id or state.EvidenceId
	end
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table"
			or (event.Type or event.Kind) ~= "HolyOilColor" then return false end
		if event.Burning ~= true or event.Qualified ~= true
			or event.Stable ~= true or type(event.Blue) ~= "boolean" then return true end
		if state.Blue == true and event.Blue == false then return true end
		if state.Blue == event.Blue then return true end
		state.Checked, state.Blue = true, event.Blue
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Blue then
			conclude("Positive", event.Reason or "qualified Burning Holy Oil produced blue fire", event)
		else
			conclude("RuleOut", event.Reason or "qualified Burning Holy Oil produced a non-blue fire colour", event)
		end
		return true
	end
	function observer:Reset() state.Checked, state.Blue, state.EvidenceId = false, nil, nil end
	function observer:Snapshot()
		return {Destroyed = state.Destroyed, Checked = state.Checked, Blue = state.Blue}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"GhostWriting", "Handprints", "SpiritBox"},
	ObservationEvents = {"HolyOilColor"},
	Perks = {
		["Pretty Sure"] = {"Qualified Burning Holy Oil has blue fire."},
		Maybe = {},
		Idk = {"A stable non-blue fire colour rules Spirit out; an unlit or transitioning effect is ignored."},
	},
	CreateObserver = createObserver,
}
