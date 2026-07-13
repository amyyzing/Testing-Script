local NAME = "Demon"

local function createObserver(api)
	local state = {Destroyed = false, Trials = {}}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" or (event.Type or event.Kind) ~= "CrossMotion" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		local id = event.TrialId or event.ObservationId or "default"
		if state.Trials[id] or event.Eligible ~= true or event.Completed ~= true then return true end
		state.Trials[id] = event.FloatedAndRotated == true and "Matched" or "Rejected"
		if event.FloatedAndRotated == true then
			if api and type(api.Positive) == "function" then api:Positive(NAME, event.Reason or "an activated Cross floated and rotated", 99, event) end
		elseif api and type(api.RuleOut) == "function" then
			api:RuleOut(NAME, event.Reason or "an eligible activated Cross did not float and rotate", 99, event)
		end
		return true
	end
	function observer:Reset() state.Trials = {} end
	function observer:Snapshot() return {Destroyed = state.Destroyed, Trials = state.Trials} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "FreezingTemperatures", "Handprints"},
	ObservationEvents = {"CrossMotion"},
	Perks = { ["Pretty Sure"] = {"An activated Cross floats and rotates."}, Maybe = {}, Idk = {"An unused or unobserved Cross cannot rule out Demon."} },
	CreateObserver = createObserver,
}
