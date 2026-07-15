local NAME = "Oni"

local function createObserver(api)
	local spec = api and type(api.Specification) == "function" and api:Specification() or {}
	local pairSpec = type(spec.SpeedPairs) == "table" and spec.SpeedPairs or {}
	local requiredPairs = tonumber(pairSpec.RequiredPairs) or 7
	local oniBase = tonumber(pairSpec.OniHuntingBase) or 13.5
	local state = {
		Destroyed = false,
		Outcome = nil,
		BaseSpeed = nil,
		EvidenceId = nil,
		NonHuntOutcome = nil,
		NonHuntEvidenceId = nil,
	}
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

	local function concludeNonHunt(polarity, reason, event)
		local entry
		if state.NonHuntEvidenceId and api and type(api.Supersede) == "function" then
			entry = api:Supersede(
				NAME,
				state.NonHuntEvidenceId,
				polarity,
				reason,
				polarity == "RuleOut" and 99 or 0,
				event
			)
		elseif polarity == "RuleOut" and api and type(api.RuleOut) == "function" then
			entry = api:RuleOut(NAME, reason, 99, event)
		end
		state.NonHuntEvidenceId = type(entry) == "table"
			and entry.Id or state.NonHuntEvidenceId
	end

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "HuntSpeedMathResult"
			and kind ~= "NonHuntSpeedMathResult" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if kind == "NonHuntSpeedMathResult" then
			if event.Hunting ~= false or event.Qualified ~= true
				or event.Completed ~= true or type(event.Matched) ~= "boolean" then
				return true
			end
			local outcome = event.Matched and "Matched" or "Rejected"
			if state.NonHuntOutcome == outcome then return true end
			state.NonHuntOutcome = outcome
			if event.Matched then
				if state.NonHuntEvidenceId then
					concludeNonHunt(
						"Observation",
						event.Reason or "settled non-hunting speed returned to base 11",
						event
					)
				end
			else
				concludeNonHunt(
					"RuleOut",
					event.Reason or "settled non-hunting speed did not return to base 11",
					event
				)
			end
			return true
		end
		if event.Hunting ~= true or event.Completed ~= true
			or (tonumber(event.PairCount) or 0) < requiredPairs then return true end
		local fits = type(event.Fits) == "table" and event.Fits or {}
		local oniFit = type(fits.Oni) == "table" and fits.Oni or nil
		local matched = oniFit ~= nil and (
			oniFit.Matched == true
			or oniFit.Qualified == true
			or oniFit.Fits == true
		)
		state.BaseSpeed = tonumber(oniFit and oniFit.Base)
			or tonumber(event.BaseSpeed)
		-- Direct compatibility events without Fits may still carry the old
		-- explicit Oni base, but global Best never overrides a present Oni fit.
		if oniFit == nil then
			matched = event.Best == NAME and state.BaseSpeed ~= nil
		end
		matched = matched and state.BaseSpeed ~= nil
			and math.abs(state.BaseSpeed - oniBase) <= 0.0001
		local outcome = matched and "Matched" or "Rejected"
		if state.Outcome == outcome then return true end
		if matched then
			state.Outcome = "Matched"
			conclude("Positive", event.Reason or "the completed seven-pair flat result independently fit Oni base speed 13.5", event)
		else
			state.Outcome = "Rejected"
			conclude("RuleOut", event.Reason or "the completed seven-pair flat result did not fit Oni base speed 13.5", event)
		end
		return true
	end

	function observer:Reset()
		state.Outcome, state.BaseSpeed, state.EvidenceId = nil, nil, nil
		state.NonHuntOutcome, state.NonHuntEvidenceId = nil, nil
	end
	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			Outcome = state.Outcome,
			BaseSpeed = state.BaseSpeed,
			NonHuntOutcome = state.NonHuntOutcome,
		}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"FreezingTemperatures", "LaserProjector", "SpiritBox"},
	ObservationEvents = {"HuntSpeedMathResult", "NonHuntSpeedMathResult"},
	Perks = {
		["Pretty Sure"] = {"The Oni fit in a completed seven-pair flat result independently matches base speed 13.5 after map and valid difficulty factors are removed."},
		Maybe = {},
		Idk = {"A qualified non-hunting transition must normalize to base 11; 175% is never a hunting multiplier."},
	},
	CreateObserver = createObserver,
}
