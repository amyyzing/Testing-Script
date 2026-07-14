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
		local upward = math.max(0, math.floor(tonumber(
			event.UpwardPairs or event.UpwardSteps or event.IncreaseCount
		) or 0))
		state.LastUpwardSteps = upward
		local pairCount = math.max(0, math.floor(tonumber(event.PairCount) or 0))
		local requiredPairs = math.max(7, math.floor(tonumber(event.RequiredPairs) or 7))
		if (kind == "DullahanPattern" or kind == "DullahanPatternAbsent")
			and pairCount < requiredPairs then return true end
		local minimum = math.max(requiredPairs, math.floor(tonumber(
			event.RequiredUpwardPairs or event.RequiredUpwardSteps
		) or requiredPairs))
		if kind == "DullahanPattern" or upward >= minimum then
			state.Matched = true
			conclude("Positive", event.Reason or "all seven settled hunt-speed pairs showed differing short upward steps", 99, event)
		elseif kind == "DullahanPatternAbsent" or (event.Completed == true and event.PhantomExcluded == true and upward == 0) then
			if state.Matched then return true end
			state.Matched = false
			conclude("RuleOut", event.Reason or "seven settled hunt-speed pairs did not maintain Dullahan's differing upward-step pattern", 99, event)
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
	Perks = { ["Pretty Sure"] = {"All seven settled visible/invisible pairs show differing short upward speed steps; decreases between pairs are ignored."}, Maybe = {}, Idk = {"A repeating seven-pair Phantom or flat Normal/Oni pattern rules Dullahan out immediately; fewer than seven pairs are insufficient."} },
	CreateObserver = createObserver,
}
