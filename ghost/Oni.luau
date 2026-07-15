local NAME = "Oni"

local function read(event, key)
	if event[key] ~= nil then return event[key] end
	if type(event.Payload) == "table" then return event.Payload[key] end
	return nil
end

local function createObserver(api)
	local state = {Destroyed = false, LastBaseSpeed = nil, Outcome = nil, EvidenceId = nil}
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
		if kind ~= "NormalizedHuntSpeed" and kind ~= "HuntSpeedMathResult" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if read(event, "Hunting") == false or read(event, "Qualified") == false or read(event, "PhaseDependent") == true then return true end
		if kind == "HuntSpeedMathResult" then
			local requiredPairs = math.max(7, math.floor(tonumber(read(event, "RequiredPairs")) or 7))
			if math.floor(tonumber(read(event, "PairCount")) or 0) < requiredPairs then return true end
		end
		local best = read(event, "Best")
		local base = tonumber(read(event, "BaseSpeed"))
		if base == nil and kind == "NormalizedHuntSpeed" then
			base = tonumber(read(event, "NormalizedSpeed"))
		end
		local tolerance = math.max(0.05, tonumber(event.Tolerance) or 0.3)
		state.LastBaseSpeed = base
		-- HuntSpeedMathResult can contain overlapping tolerance fits. Only its
		-- winning classification is conclusive; accepting any Oni fit made an
		-- exact Normal result such as 13.75 incorrectly identify Oni as well.
		local matched = event.Outcome == "Oni" or best == "Oni"
			or (kind == "NormalizedHuntSpeed" and base and math.abs(base - 13.5) <= tolerance)
		if matched then
			state.Outcome = "Matched"
			conclude("Positive", event.Reason or "normalized hunting WalkSpeed resolved to Oni base 13.5", 99, event)
		elseif kind == "HuntSpeedMathResult" or (event.Completed == true and (event.Outcome == "Ordinary" or event.Outcome == "Other" or base ~= nil)) then
			if state.Outcome == "Matched" then return true end
			state.Outcome = "Rejected"
			conclude("RuleOut", event.Reason or "qualified normalized hunting WalkSpeed did not resolve to base 13.5", 99, event)
		end
		return true
	end
	function observer:Reset() state.LastBaseSpeed, state.Outcome, state.EvidenceId = nil, nil, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, LastBaseSpeed = state.LastBaseSpeed, Outcome = state.Outcome} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"FreezingTemperatures", "LaserProjector", "SpiritBox"},
	ObservationEvents = {"NormalizedHuntSpeed", "HuntSpeedMathResult"},
	Perks = { ["Pretty Sure"] = {"Seven repeating flat pairs normalize to hunting base speed 13.5 after removing map and a valid difficulty multiplier."}, Maybe = {}, Idk = {"Fewer than seven pairs are insufficient, and there is no 175% hunting multiplier."} },
	CreateObserver = createObserver,
}
