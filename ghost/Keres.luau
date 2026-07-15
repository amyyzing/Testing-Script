local NAME = "Keres"
local KILL_MIN_RELATIVE_DECREASE = 0.06
local KILL_MAX_RELATIVE_DECREASE = 0.15

local function read(event, key)
	if event[key] ~= nil then return event[key] end
	if type(event.Payload) == "table" then return event.Payload[key] end
	return nil
end

local function emit(api, method, reason, confidence, event)
	local fn = api and api[method]
	if type(fn) == "function" then
		if method == "Record" then fn(api, NAME, event) else fn(api, NAME, reason, confidence, event) end
	end
end

local function createObserver(api)
	local state = {Destroyed = false, LastKillDirection = nil, ModelSex = nil, KillMatched = false, KillEvidenceId = nil}
	local observer = {}
	local function concludeKill(polarity, reason, confidence, event)
		local entry
		if state.KillEvidenceId and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, state.KillEvidenceId, polarity, reason, confidence, event)
		else
			local fn = api and api[polarity]
			if type(fn) == "function" then entry = fn(api, NAME, reason, confidence, event) end
		end
		state.KillEvidenceId = type(entry) == "table" and entry.Id or state.KillEvidenceId
	end
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "KillSpeedChange" and kind ~= "GhostModelSex"
			and kind ~= "SpeedProbeResult" then return false end
		emit(api, "Record", nil, nil, event)
		if kind == "SpeedProbeResult" then
			local trigger = string.lower(tostring(read(event, "Trigger") or ""))
			if not string.find(trigger, "death", 1, true) and not string.find(trigger, "kill", 1, true) then return true end
			if read(event, "Hunting") ~= true
				or read(event, "Unique") ~= true
				or read(event, "Qualified") ~= true
				or read(event, "HuntId") == nil then return true end
			local delta = tonumber(read(event, "Delta"))
			if delta == nil then
				local baseline, current = tonumber(read(event, "BaselineSpeed")), tonumber(read(event, "CurrentSpeed"))
				if baseline and current then delta = current - baseline end
			end
			local baseline = tonumber(read(event, "BaselineSpeed"))
			local relative = tonumber(read(event, "RelativeDelta"))
			if relative == nil and baseline and baseline > 0 and delta then
				relative = delta / baseline
			end
			state.LastKillDirection = delta and (delta < 0 and "Decrease" or (delta > 0 and "Increase" or "Stable")) or nil
			if relative and -relative >= KILL_MIN_RELATIVE_DECREASE
				and -relative <= KILL_MAX_RELATIVE_DECREASE then
				state.KillMatched = true
				concludeKill("Positive", read(event, "Reason") or "stable hunting speed decreased by the expected amount after a unique player death", 99, event)
			elseif delta ~= nil and read(event, "Completed") == true and not state.KillMatched then
				concludeKill("RuleOut", read(event, "Reason") or "a qualified unique-death probe produced no expected stable speed decrease", 99, event)
			end
		elseif kind == "GhostModelSex" then
			if event.Qualified ~= true then return true end
			state.ModelSex = event.Sex
			if event.Sex == "Female" then
				emit(api, "Positive", event.Reason or "the ghost uses a female VisualModel", 25, event)
			elseif event.Sex == "Male" then
				emit(api, "Negative", event.Reason or "the ghost uses a male VisualModel", 25, event)
			end
		elseif event.Unique == true and event.Hunting == true and event.Qualified == true then
			state.LastKillDirection = event.Direction
			local relative = tonumber(event.RelativeDelta or event.RelativeChange)
			if event.Direction == "Decrease" and relative
				and -relative >= KILL_MIN_RELATIVE_DECREASE
				and -relative <= KILL_MAX_RELATIVE_DECREASE then
				state.KillMatched = true
				concludeKill("Positive", event.Reason or "stable hunting speed decreased by the expected amount after a unique player kill", 99, event)
			elseif not state.KillMatched and event.Completed == true and relative ~= nil then
				concludeKill("RuleOut", event.Reason or "a qualified unique-kill comparison produced no stable speed decrease", 99, event)
			end
		end
		return true
	end
	function observer:Reset() state.LastKillDirection, state.ModelSex, state.KillMatched, state.KillEvidenceId = nil, nil, false, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, LastKillDirection = state.LastKillDirection, ModelSex = state.ModelSex} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"Handprints", "SpiritBox", "Wither"},
	ObservationEvents = {"KillSpeedChange", "GhostModelSex", "SpeedProbeResult"},
	Perks = { ["Pretty Sure"] = {"Stable speed decreases after a unique player kill."}, Maybe = {"A female VisualModel is weak support."}, Idk = {"Do not probe kill speed when the hunt ended; Revenant owns that result."} },
	CreateObserver = createObserver,
}
