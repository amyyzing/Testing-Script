local NAME = "Dullahan"

local function createObserver(api)
	local state = {Destroyed = false, LastUpwardSteps = 0, Matched = false, EvidenceId = nil}
	local observer = {}
	local function conclude(polarity, reason, confidence, event)
		local entry
		if state.EvidenceId and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, state.EvidenceId, polarity, reason, confidence, event)
		elseif api and type(api[polarity]) == "function" then
			entry = api[polarity](api, NAME, reason, confidence, event)
		end
		state.EvidenceId = type(entry) == "table" and entry.Id or state.EvidenceId
	end
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "HuntSpeedSteps" and kind ~= "BlinkSpeedPattern"
			and kind ~= "DullahanPattern" and kind ~= "DullahanPatternAbsent" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if kind ~= "DullahanPatternAbsent"
			and (event.Hunting == false or event.Qualified == false) then return true end
		local upward = math.max(0, math.floor(tonumber(event.UpwardSteps or event.IncreaseCount) or 0))
		state.LastUpwardSteps = upward
		local minimum = math.max(2, math.floor(tonumber(event.RequiredUpwardSteps) or 2))
		if kind == "DullahanPattern" or upward >= minimum then
			state.Matched = true
			conclude("Positive", event.Reason or "multiple short upward WalkSpeed steps occurred during the hunt", 99, event)
		elseif kind == "DullahanPatternAbsent" or (event.Completed == true and event.PhantomExcluded == true and upward == 0) then
			if state.Matched then return true end
			state.Matched = false
			conclude("RuleOut", event.Reason or "a qualified short hunting probe contained no upward WalkSpeed steps", 99, event)
		end
		return true
	end
	function observer:Reset() state.LastUpwardSteps, state.Matched, state.EvidenceId = 0, false, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, LastUpwardSteps = state.LastUpwardSteps, Matched = state.Matched} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"FreezingTemperatures", "LaserProjector", "Wither"},
	ObservationEvents = {"HuntSpeedSteps", "BlinkSpeedPattern", "DullahanPattern", "DullahanPatternAbsent"},
	Perks = { ["Pretty Sure"] = {"WalkSpeed rises in several short hunting intervals; line of sight is irrelevant and decreases are ignored."}, Maybe = {}, Idk = {"Classify Phantom phase changes before a Dullahan negative."} },
	CreateObserver = createObserver,
}
