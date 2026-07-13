local NAME = "Siren"

local function emit(api, method, reason, confidence, event)
	local fn = api and api[method]
	if type(fn) == "function" then
		if method == "Record" then fn(api, NAME, event) else fn(api, NAME, reason, confidence, event) end
	end
end

local function createObserver(api)
	local state = {Destroyed = false, Humming = false, LosOutcome = nil, ModelSex = nil, VoiceSex = nil}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "SpiritBoxResponse" and kind ~= "LineOfSightPlayerSpeed"
			and kind ~= "GhostModelSex" and kind ~= "GhostVoiceSex" then return false end
		emit(api, "Record", nil, nil, event)
		if kind == "SpiritBoxResponse" and event.Qualified == true and event.Response == "- HUMMING -" then
			state.Humming = true
			emit(api, "Positive", event.Reason or "Spirit Box returned - HUMMING -", event.MimicPossible == true and 60 or 99, event)
		elseif kind == "LineOfSightPlayerSpeed" and event.Hunting == true and event.Qualified == true then
			if event.Slowed == true then
				state.LosOutcome = "Slowed"
				emit(api, "Positive", event.Reason or "the player slowed during sustained line of sight", 99, event)
			elseif event.Completed == true and event.Slowed == false then
				state.LosOutcome = "NotSlowed"
				emit(api, "RuleOut", event.Reason or "a qualified sustained line-of-sight trial produced no player slowdown", 99, event)
			end
		elseif kind == "GhostVoiceSex" and event.Qualified == true then
			state.VoiceSex = event.Sex
			if event.Sex == "Female" then
				emit(api, "Positive", event.Reason or "Spirit Box used a female voice category", 35, event)
			end
		elseif kind == "GhostModelSex" and event.Qualified == true then
			state.ModelSex = event.Sex
			if event.Sex == "Female" then emit(api, "Positive", event.Reason or "the ghost uses a female VisualModel", 25, event)
			elseif event.Sex == "Male" then emit(api, "Negative", event.Reason or "the ghost uses a male VisualModel", 25, event) end
		end
		return true
	end
	function observer:Reset() state.Humming, state.LosOutcome, state.ModelSex, state.VoiceSex = false, nil, nil, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, Humming = state.Humming, LosOutcome = state.LosOutcome, ModelSex = state.ModelSex, VoiceSex = state.VoiceSex} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "SpiritBox", "Wither"},
	ObservationEvents = {"SpiritBoxResponse", "LineOfSightPlayerSpeed", "GhostModelSex", "GhostVoiceSex"},
	Perks = { ["Pretty Sure"] = {"Spirit Box humming or a qualified line-of-sight player slowdown."}, Maybe = {"A female VisualModel is weak support."}, Idk = {"Humming is mimickable; central resolution retains Skinwalker too."} },
	CreateObserver = createObserver,
}
