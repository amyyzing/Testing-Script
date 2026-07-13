local NAME = "Spirit"

local function createObserver(api)
	local state = {Destroyed = false, Models = {}, EvidenceIds = {}}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" or (event.Type or event.Kind) ~= "HolyOilColor" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Hunting ~= true or event.Burning ~= true or event.Qualified ~= true or event.Stable ~= true then return true end
		local id = event.ModelId or "default"
		if event.Blue == true then
			if state.Models[id] == "Blue" then return true end
			state.Models[id] = "Blue"
			local previous = state.EvidenceIds[id]
			local entry
			if previous and api and type(api.Supersede) == "function" then
				entry = api:Supersede(NAME, previous, "Positive", event.Reason or "eligible burning Holy Oil produced a stable blue fire color", 99, event)
			elseif api and type(api.Positive) == "function" then
				entry = api:Positive(NAME, event.Reason or "eligible burning Holy Oil produced a stable blue fire color", 99, event)
			end
			state.EvidenceIds[id] = type(entry) == "table" and entry.Id or previous
		elseif event.Blue == false and state.Models[id] == nil then
			state.Models[id] = "NotBlue"
			local entry = api and type(api.RuleOut) == "function"
				and api:RuleOut(NAME, event.Reason or "eligible burning Holy Oil produced a stable non-blue fire color", 99, event)
				or nil
			state.EvidenceIds[id] = type(entry) == "table" and entry.Id or nil
		end
		return true
	end
	function observer:Reset() state.Models, state.EvidenceIds = {}, {} end
	function observer:Snapshot() return {Destroyed = state.Destroyed, Models = state.Models} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"GhostWriting", "Handprints", "SpiritBox"},
	ObservationEvents = {"HolyOilColor"},
	Perks = { ["Pretty Sure"] = {"Eligible stable Holy Oil fire is blue."}, Maybe = {}, Idk = {"An unlit or transitioning effect is not a negative."} },
	CreateObserver = createObserver,
}
