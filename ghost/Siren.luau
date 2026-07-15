local NAME = "Siren"

local function emit(api, method, reason, confidence, event)
	local fn = api and api[method]
	if type(fn) == "function" then
		if method == "Record" then fn(api, NAME, event) else fn(api, NAME, reason, confidence, event) end
	end
end

local function createObserver(api)
	local state = {
		Destroyed = false,
		Humming = false,
		LosOutcome = nil,
		ModelSex = nil,
		HummingMaleResolved = false,
		HummingEvidenceId = nil,
	}
	local observer = {}
	local function resolveHummingModelConflict(event)
		if state.Humming and state.ModelSex == "Male" and not state.HummingMaleResolved then
			state.HummingMaleResolved = true
			local reason = "Spirit Box humming paired with a male VisualModel identifies a Skinwalker mimic rather than Siren"
			if state.HummingEvidenceId and api and type(api.Supersede) == "function" then
				api:Supersede(NAME, state.HummingEvidenceId, "RuleOut", reason, 99, event)
			elseif api and type(api.RuleOut) == "function" then
				api:RuleOut(NAME, reason, 99, event)
			end
		end
	end
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "SpiritBoxResponse" and kind ~= "LineOfSightPlayerSpeed"
			and kind ~= "GhostModelSex" then return false end
		emit(api, "Record", nil, nil, event)
		if kind == "SpiritBoxResponse" and event.Qualified == true and event.Response == "- HUMMING -" then
			state.Humming = true
			if state.ModelSex == "Male" then
				resolveHummingModelConflict(event)
			elseif api and type(api.Positive) == "function" then
				local entry = api:Positive(NAME, event.Reason or "Spirit Box returned - HUMMING -", event.MimicPossible == true and 60 or 99, event)
				state.HummingEvidenceId = type(entry) == "table" and entry.Id
					or state.HummingEvidenceId
			end
		elseif kind == "LineOfSightPlayerSpeed" and event.Hunting == true and event.Qualified == true then
			if event.Slowed == true then
				state.LosOutcome = "Slowed"
				emit(api, "Positive", event.Reason or "the player slowed during sustained line of sight", 99, event)
			elseif event.Completed == true and event.Slowed == false then
				state.LosOutcome = "NotSlowed"
				emit(api, "RuleOut", event.Reason or "a qualified sustained line-of-sight trial produced no player slowdown", 99, event)
			end
		elseif kind == "GhostModelSex" and event.Qualified == true then
			state.ModelSex = event.Sex
			if event.Sex == "Female" then emit(api, "Positive", event.Reason or "the ghost uses a female VisualModel", 25, event)
			elseif event.Sex == "Male" and not state.Humming then
				emit(api, "Negative", event.Reason or "the ghost uses a male VisualModel", 99, event)
			end
			resolveHummingModelConflict(event)
		end
		return true
	end
	function observer:Reset()
		state.Humming, state.LosOutcome, state.ModelSex, state.HummingMaleResolved = false, nil, nil, false
		state.HummingEvidenceId = nil
	end
	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			Humming = state.Humming,
			LosOutcome = state.LosOutcome,
			ModelSex = state.ModelSex,
			HummingMaleResolved = state.HummingMaleResolved,
			HummingEvidenceId = state.HummingEvidenceId,
		}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "SpiritBox", "Wither"},
	ObservationEvents = {"SpiritBoxResponse", "LineOfSightPlayerSpeed", "GhostModelSex"},
	Perks = { ["Pretty Sure"] = {"Spirit Box humming or a qualified line-of-sight player slowdown."}, Maybe = {"A female VisualModel is weak support."}, Idk = {"A male VisualModel is a 99% negative for Siren.", "Humming is mimickable; humming with a male VisualModel identifies Skinwalker."} },
	CreateObserver = createObserver,
}
