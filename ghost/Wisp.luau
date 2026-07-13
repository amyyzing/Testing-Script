local NAME = "Wisp"

local function emit(api, method, reason, confidence, event)
	local fn = api and api[method]
	if type(fn) == "function" then
		if method == "Record" then fn(api, NAME, event) else fn(api, NAME, reason, confidence, event) end
	end
end

local function createObserver(api)
	local state = {Destroyed = false, OilModels = {}, OilEvidenceIds = {}, LastRoomRelation = nil}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "HolyOilCollision" and kind ~= "HuntRoomRelation" then return false end
		emit(api, "Record", nil, nil, event)
		if kind == "HuntRoomRelation" then
			if event.Hunting ~= true or event.Qualified ~= true then return true end
			state.LastRoomRelation = event.InFavouriteRoom == true and "Favourite" or "Other"
			if event.InFavouriteRoom == false then
				emit(api, "Negative", event.Reason or "the hunting ghost was confirmed outside its favourite room", 95, event)
			end
			return true
		end

		if event.Hunting ~= true or event.Burning ~= true or event.Qualified ~= true then return true end
		local id = event.ModelId or "default"
		if kind == "HolyOilCollision" and type(event.CanCollide) == "boolean" then
			local prior = state.OilModels[id]
			if event.CanCollide == false then
				if prior == "Passed" then return true end
				state.OilModels[id] = "Passed"
				local previousId = state.OilEvidenceIds[id]
				local entry
				if previousId and api and type(api.Supersede) == "function" then
					entry = api:Supersede(NAME, previousId, "Positive", event.Reason or "while hunting and Holy Oil was Burning, GhostWall.CanCollide was false", 99, event)
				elseif api and type(api.Positive) == "function" then
					entry = api:Positive(NAME, event.Reason or "while hunting and Holy Oil was Burning, GhostWall.CanCollide was false", 99, event)
				end
				state.OilEvidenceIds[id] = type(entry) == "table" and entry.Id or previousId
			elseif prior == nil then
				state.OilModels[id] = "Blocked"
				local entry = api and type(api.RuleOut) == "function"
					and api:RuleOut(NAME, event.Reason or "while hunting and Holy Oil was Burning, GhostWall.CanCollide was true", 99, event)
					or nil
				state.OilEvidenceIds[id] = type(entry) == "table" and entry.Id or nil
			end
		end
		return true
	end
	function observer:Reset() state.OilModels, state.OilEvidenceIds, state.LastRoomRelation = {}, {}, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, OilModels = state.OilModels, LastRoomRelation = state.LastRoomRelation} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"GhostOrb", "LaserProjector", "Wither"},
	ObservationEvents = {"HolyOilCollision", "HuntRoomRelation"},
	Perks = { ["Pretty Sure"] = {"Only while hunting with Burning Holy Oil, GhostWall.CanCollide is false."}, Maybe = {}, Idk = {"A hunt outside the favourite room is a high negative; favourite-room hunting alone is not support. Any ghost may pass through oil outside a hunt."} },
	CreateObserver = createObserver,
}
