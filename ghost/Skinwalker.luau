local NAME = "Skinwalker"

local function createObserver(api)
	local state = {
		Destroyed = false,
		FalseOrb = false,
		MimicFacts = {},
		OilEvidenceId = nil,
		Humming = false,
		ModelSex = nil,
		HummingMaleResolved = false,
	}
	local observer = {}

	local function mimicCount()
		local count = 0
		for _ in pairs(state.MimicFacts) do count = count + 1 end
		return count
	end

	local function positiveMimic(key, reason, event)
		if state.MimicFacts[key] then return end
		state.MimicFacts[key] = true
		local confidence = mimicCount() >= 2 and 99 or 60
		if api and type(api.Positive) == "function" then
			api:Positive(NAME, reason, confidence, event)
		end
	end

	local function concludeOil(polarity, reason, confidence, event)
		local entry
		if state.OilEvidenceId and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, state.OilEvidenceId, polarity, reason, confidence, event)
		elseif api and type(api[polarity]) == "function" then
			entry = api[polarity](api, NAME, reason, confidence, event)
		end
		state.OilEvidenceId = type(entry) == "table" and entry.Id or state.OilEvidenceId
	end

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "FalseOrb" and kind ~= "GhostFireEffect"
			and kind ~= "RootSoundScan" and kind ~= "SpiritBoxResponse"
			and kind ~= "GhostModelSex" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Qualified ~= true then return true end

		if kind == "SpiritBoxResponse" then
			if event.Response == "- HUMMING -" then state.Humming = true end
		elseif kind == "GhostModelSex" then
			state.ModelSex = event.Sex
		elseif kind == "FalseOrb" then
			if event.FourthEvidence == true or event.ImpossibleCombination == true then
				if not state.FalseOrb and api and type(api.Positive) == "function" then
					api:Positive(NAME, event.Reason or "Ghost Orb formed a fourth or impossible evidence combination", 100, event)
				end
				state.FalseOrb = true
			end
		elseif kind == "GhostFireEffect" then
			if event.Completed ~= true or event.DirectContact ~= true
				or event.Burning ~= true or type(event.CaughtFire) ~= "boolean" then return true end
			if event.CaughtFire then
				concludeOil("RuleOut", "the ghost caught fire after directly passing through Burning Holy Oil", 99, event)
			else
				positiveMimic("NoOilFire", "the ghost passed through Burning Holy Oil without catching fire, matching a Skinwalker mimic", event)
			end
		elseif kind == "RootSoundScan" and event.HasOtherSound == false then
			positiveMimic(
				"NoRootSound",
				"the qualified HumanoidRootPart scan contained no Sound besides Hunting, matching a Skinwalker mimic",
				event
			)
		end
		if state.Humming and state.ModelSex == "Male" and not state.HummingMaleResolved then
			state.HummingMaleResolved = true
			if api and type(api.Positive) == "function" then
				api:Positive(NAME, "Spirit Box humming paired with a male VisualModel identifies a Skinwalker mimic", 99, event)
			end
		end
		return true
	end

	function observer:Reset()
		state.FalseOrb, state.MimicFacts, state.OilEvidenceId = false, {}, nil
		state.Humming, state.ModelSex, state.HummingMaleResolved = false, nil, false
	end
	function observer:Snapshot()
		return {Destroyed = state.Destroyed, FalseOrb = state.FalseOrb, MimicFacts = state.MimicFacts}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"FreezingTemperatures", "GhostWriting", "SpiritBox"},
	FalseEvidence = {"GhostOrb"},
	ObservationEvents = {"FalseOrb", "GhostFireEffect", "RootSoundScan", "SpiritBoxResponse", "GhostModelSex"},
	PersistentFindings = true,
	Perks = {
		["Pretty Sure"] = {"Orb creates a fourth/impossible evidence combination, multiple exclusive mimic facts agree, or humming pairs with a male VisualModel."},
		Maybe = {"No fire after a qualified Holy Oil passage, or a qualified root scan with no Sound besides Hunting."},
		Idk = {"Catching fire after Holy Oil is a 99% negative; Orb alone is not false evidence until its combination is impossible."},
	},
	CreateObserver = createObserver,
}
