local NAME = "Dullahan"

local function createObserver(api)
	local state = {Destroyed = false, LastDifferentPairs = 0, Matched = false, EvidenceId = nil}
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
		if kind ~= "HuntSpeedSteps"
			and kind ~= "DullahanPattern" and kind ~= "DullahanPatternAbsent" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if kind ~= "DullahanPatternAbsent"
			and (event.Hunting == false or event.Qualified == false) then return true end
		local different = math.max(0, math.floor(tonumber(
			event.DifferentPairs or event.DifferentPairCount
				or event.UpwardPairs or event.UpwardSteps or event.IncreaseCount
		) or 0))
		state.LastDifferentPairs = different
		local pairCount = math.max(0, math.floor(tonumber(event.PairCount) or 0))
		local requiredPairs = math.max(7, math.floor(tonumber(event.RequiredPairs) or 7))
		if (kind == "DullahanPattern" or kind == "DullahanPatternAbsent")
			and pairCount < requiredPairs then return true end
		local minimum = math.max(requiredPairs, math.floor(tonumber(
			event.RequiredDifferentPairs
				or event.RequiredUpwardPairs or event.RequiredUpwardSteps
		) or requiredPairs))
		if kind == "DullahanPatternAbsent" then
			if state.Matched then return true end
			state.Matched = false
			conclude("RuleOut", event.Reason or "the seven local pairs matched Phantom, were flat, or included an equal pair", 99, event)
		elseif kind == "DullahanPattern" or different >= minimum then
			state.Matched = true
			conclude("Positive", event.Reason or "all seven settled hunt-speed pairs contained two different values", 99, event)
		elseif event.Completed == true and event.PhantomExcluded == true and different == 0 then
			if state.Matched then return true end
			state.Matched = false
			conclude("RuleOut", event.Reason or "at least one of seven settled hunt-speed pairs repeated the same value", 99, event)
		end
		return true
	end
	function observer:Reset() state.LastDifferentPairs, state.Matched, state.EvidenceId = 0, false, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, LastDifferentPairs = state.LastDifferentPairs, Matched = state.Matched} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"FreezingTemperatures", "LaserProjector", "Wither"},
	ObservationEvents = {"HuntSpeedSteps", "DullahanPattern", "DullahanPatternAbsent"},
	Perks = { ["Pretty Sure"] = {"Both values differ in every one of seven settled visible/invisible pairs; direction and difference size do not matter."}, Maybe = {}, Idk = {"Seven local Phantom-ratio pairs or seven equal Normal/Oni pairs rule Dullahan out immediately; fewer than seven pairs are insufficient."} },
	CreateObserver = createObserver,
}
