local NAME = "Wisp"

local function createObserver(api)
	local state = {
		Destroyed = false,
		OilOutcome = nil,
		OilEvidenceId = nil,
		RoomEvidenceId = nil,
		FavouriteHunts = 0,
		LastRoomRelation = nil,
		OutsideFavouriteHunt = false,
	}
	local observer = {}

	local function conclude(domain, polarity, reason, confidence, event)
		local key = domain .. "EvidenceId"
		local previous = state[key]
		local entry
		if previous and api and type(api.Supersede) == "function" then
			entry = api:Supersede(NAME, previous, polarity, reason, confidence, event)
		elseif api and type(api[polarity]) == "function" then
			entry = api[polarity](api, NAME, reason, confidence, event)
		end
		state[key] = type(entry) == "table" and entry.Id or previous
	end

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "HolyOilCollision" and kind ~= "HuntRoomRelation" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if kind == "HuntRoomRelation" then
			if event.Hunting ~= true or event.Qualified ~= true
				or event.Completed ~= true or type(event.InFavouriteRoom) ~= "boolean" then return true end
			state.LastRoomRelation = event.InFavouriteRoom and "Favourite" or "Other"
			if event.InFavouriteRoom then
				state.FavouriteHunts = state.FavouriteHunts + 1
				-- A later ordinary favourite-room hunt does not disprove the
				-- historical ability violation. Keep the first outside-room hunt as
				-- the terminal result for this evidence domain.
				if state.OutsideFavouriteHunt then return true end
				local confidence = state.FavouriteHunts >= 2 and 99 or 60
				conclude("Room", "Positive", "the hunt started inside the current favourite room", confidence, event)
			else
				if not state.OutsideFavouriteHunt then
					state.OutsideFavouriteHunt = true
					conclude("Room", "Negative", "the hunt started outside the current favourite room", 95, event)
				end
			end
			return true
		end
		if event.Hunting ~= true or event.Burning ~= true or event.Qualified ~= true
			or type(event.CanCollide) ~= "boolean" then return true end
		if event.CanCollide == false then
			state.OilOutcome = "Passed"
			conclude("Oil", "Positive", "while hunting with Burning Holy Oil, GhostWall.CanCollide was false", 99, event)
		else
			if state.OilOutcome == "Passed" then return true end
			state.OilOutcome = "Blocked"
			conclude("Oil", "RuleOut", "while hunting with Burning Holy Oil, GhostWall.CanCollide was true", 99, event)
		end
		return true
	end

	function observer:Reset()
		state.OilOutcome, state.OilEvidenceId, state.RoomEvidenceId = nil, nil, nil
		state.FavouriteHunts, state.LastRoomRelation = 0, nil
		state.OutsideFavouriteHunt = false
	end
	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			OilOutcome = state.OilOutcome,
			FavouriteHunts = state.FavouriteHunts,
			LastRoomRelation = state.LastRoomRelation,
			OutsideFavouriteHunt = state.OutsideFavouriteHunt,
		}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"GhostOrb", "LaserProjector", "Wither"},
	ObservationEvents = {"HolyOilCollision", "HuntRoomRelation"},
	Perks = {
		["Pretty Sure"] = {"During a hunt with Burning Holy Oil, GhostWall.CanCollide is false; repeated hunts start in the favourite room."},
		Maybe = {"One hunt starts in the current favourite room."},
		Idk = {"A hunt starting outside the favourite room is a 95% negative; Holy Oil outside a hunt is ignored."},
	},
	CreateObserver = createObserver,
}
