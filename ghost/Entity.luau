local NAME = "Entity"

local function emit(api, method, reason, confidence, event)
	local fn = api and api[method]
	if type(fn) == "function" then
		if method == "Record" then fn(api, NAME, event) else fn(api, NAME, reason, confidence, event) end
	end
end

local function createObserver(api)
	local state = {Destroyed = false, SmokeFound = nil, LastTeleport = nil}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "ObjectTeleportResult"
			and kind ~= "GhostTeleportResult" then return false end
		emit(api, "Record", nil, nil, event)
		if kind == "GhostTeleportResult" and event.ConfirmedTeleport == true
			and event.Completed == true and event.Qualified == true then
			state.LastTeleport = event.ToRoom or event.TeleportId or true
			emit(api, "Positive", event.Reason or "a verified room-to-room ghost teleport occurred", 65, event)
		elseif event.ConfirmedTeleport == true and event.Completed == true then
			state.LastTeleport = event.TeleportId or true
			if event.SmokeFound == true then
				local skinwalker = api and type(api.Resolve) == "function"
					and api:Resolve("Skinwalker") or nil
				local skinwalkerExcluded = type(skinwalker) == "table"
					and skinwalker.RuledOut == true
				emit(
					api,
					"Positive",
					event.Reason or (skinwalkerExcluded
						and "a confirmed object teleport had its associated smoke effect after Skinwalker was excluded"
						or "a confirmed object teleport had its associated smoke effect while Skinwalker remains possible"),
					skinwalkerExcluded and 99 or 60,
					event
				)
			elseif event.SmokeFound == false then
				emit(api, "Negative", event.Reason or "an object teleported without an associated SmokeHolder", 50, event)
			end
		end
		return true
	end
	function observer:Reset() state.SmokeFound, state.LastTeleport = nil, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, SmokeFound = state.SmokeFound, LastTeleport = state.LastTeleport} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"Handprints", "LaserProjector", "SpiritBox"},
	ObservationEvents = {"ObjectTeleportResult", "GhostTeleportResult"},
	Perks = { ["Pretty Sure"] = {"A SmokeHolder accompanies a confirmed object teleport after Skinwalker is excluded."}, Maybe = {"A verified room-to-room ghost teleport or smoke-correlated teleport while Skinwalker remains possible."}, Idk = {"Uncorrelated smoke or movement without a confirmed teleport is not diagnostic."} },
	CreateObserver = createObserver,
}
