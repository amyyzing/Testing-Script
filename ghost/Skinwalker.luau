local NAME = "Skinwalker"

local function createObserver(api)
	local state = {
		Destroyed = false,
		FalseOrb = false,
		Mimics = {},
		Humming = false,
		ModelSex = nil,
		HummingMaleResolved = false,
	}
	local observer = {}
	local function positive(reason, confidence, event)
		if api and type(api.Positive) == "function" then api:Positive(NAME, reason, confidence, event) end
	end
	local function resolveHummingMaleModel(event)
		if state.Humming and state.ModelSex == "Male" and not state.HummingMaleResolved then
			state.HummingMaleResolved = true
			positive(
				"Spirit Box humming paired with a male VisualModel identifies a Skinwalker mimicking Siren",
				99,
				event
			)
		end
	end
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "FalseOrb" and kind ~= "MimickedAbility"
			and kind ~= "SpiritBoxResponse" and kind ~= "GhostModelSex" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Qualified ~= true then return true end
		if kind == "FalseOrb" and (event.FourthEvidence == true or event.ImpossibleCombination == true or event.RealEvidenceDisabled == true) then
			state.FalseOrb = true
			positive(event.Reason or "Ghost Orb formed a fourth or impossible evidence combination", 100, event)
		elseif kind == "MimickedAbility" and type(event.Ability) == "string" and event.Ability ~= "" then
			state.Mimics[event.Ability] = true
			positive(event.Reason or ("a qualified " .. event.Ability .. " ability may have been mimicked"), tonumber(event.Confidence) or 65, event)
		elseif kind == "SpiritBoxResponse" and event.Response == "- HUMMING -" then
			state.Humming = true
			resolveHummingMaleModel(event)
		elseif kind == "GhostModelSex" then
			state.ModelSex = event.Sex
			resolveHummingMaleModel(event)
		end
		return true
	end
	function observer:Reset()
		state.FalseOrb, state.Mimics, state.Humming, state.ModelSex, state.HummingMaleResolved = false, {}, false, nil, false
	end
	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			FalseOrb = state.FalseOrb,
			Mimics = state.Mimics,
			Humming = state.Humming,
			ModelSex = state.ModelSex,
			HummingMaleResolved = state.HummingMaleResolved,
		}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"FreezingTemperatures", "GhostWriting", "SpiritBox"},
	FalseEvidence = {"GhostOrb"},
	ObservationEvents = {"FalseOrb", "MimickedAbility", "SpiritBoxResponse", "GhostModelSex"},
	PersistentFindings = true,
	Perks = { ["Pretty Sure"] = {"An Orb is the fourth/impossible evidence, or Siren humming is paired with a male VisualModel."}, Maybe = {"One mimickable ability keeps Skinwalker beside the original ghost."}, Idk = {"An Orb with fewer than three total observations is not enough; GhostFireEffect=false is not a Skinwalker negative."} },
	CreateObserver = createObserver,
}
