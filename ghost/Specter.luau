local SOURCE = "https://demonology.fandom.com/wiki/Specter"

local function createObserver(api)
	local state = {
		ResidenceCount = 0,
		LastResidenceReason = nil,
		LastDepartureReason = nil,
		TrackedFavourite = nil,
		RoomChangePause = false,
		RoomChangeSettleSince = nil,
		ResidenceSince = nil,
		ResidenceArmed = false,
		DepartureArmed = false,
		AwaitingPostHuntReturn = false,
		PostHuntGraceUntil = 0,
		ReturnSeenSince = nil,
		OutsideSince = nil,
		OutsideSamples = 0,
		Hunting = false,
	}
	local observer = {}

	function observer:Reset()
		state.ResidenceCount = 0
		state.LastResidenceReason = nil
		state.LastDepartureReason = nil
		state.TrackedFavourite = nil
		state.RoomChangePause = false
		state.RoomChangeSettleSince = nil
		state.ResidenceSince = nil
		state.ResidenceArmed = false
		state.DepartureArmed = false
		state.AwaitingPostHuntReturn = false
		state.PostHuntGraceUntil = 0
		state.ReturnSeenSince = nil
		state.OutsideSince = nil
		state.OutsideSamples = 0
		state.Hunting = false
	end

	local function resetOperationalState()
		state.RoomChangePause = false
		state.RoomChangeSettleSince = nil
		state.ResidenceSince = nil
		state.ResidenceArmed = false
		state.DepartureArmed = false
		state.AwaitingPostHuntReturn = false
		state.PostHuntGraceUntil = 0
		state.ReturnSeenSince = nil
		state.OutsideSince = nil
		state.OutsideSamples = 0
	end

	function observer:OnHuntStarted(event)
		state.Hunting = true
		if state.ResidenceArmed and not state.RoomChangePause then
			self:OnFavouriteResidence({Source = event and event.Source})
		end
		state.ResidenceArmed = false
		state.ResidenceSince = nil
		state.DepartureArmed = false
		state.AwaitingPostHuntReturn = false
		state.PostHuntGraceUntil = 0
		state.ReturnSeenSince = nil
		state.OutsideSince = nil
		state.OutsideSamples = 0
		state.RoomChangePause = false
		state.RoomChangeSettleSince = nil
	end

	function observer:OnHuntEnded(event)
		state.Hunting = false
		state.ResidenceArmed = false
		state.ResidenceSince = nil
		state.DepartureArmed = false
		state.AwaitingPostHuntReturn = true
		state.PostHuntGraceUntil = (tonumber(event and event.Time) or os.clock()) + 1.5
		state.ReturnSeenSince = nil
		state.OutsideSince = nil
		state.OutsideSamples = 0
	end

	function observer:OnRoomPresence(event)
		event = type(event) == "table" and event or {}
		local now = tonumber(event.Time) or os.clock()
		local favourite = tostring(event.FavouriteRoom or "")
		local inFavourite = event.FavouriteRoomContainsGhost == true
			or event.InsideFavourite == true
			or (favourite ~= "" and string.lower(tostring(event.CurrentRoom or "")) == string.lower(favourite))
		if event.Hunting == true or state.Hunting then
			return
		end
		if favourite == "" then
			state.TrackedFavourite = nil
			resetOperationalState()
			return
		end
		if state.TrackedFavourite == nil then
			state.TrackedFavourite = favourite
		elseif string.lower(tostring(state.TrackedFavourite)) ~= string.lower(favourite) then
			state.TrackedFavourite = favourite
			resetOperationalState()
			state.RoomChangePause = true
		end

		if state.RoomChangePause then
			if inFavourite then
				state.RoomChangeSettleSince = state.RoomChangeSettleSince or now
				if now - state.RoomChangeSettleSince >= 2 then
					state.RoomChangePause = false
					state.RoomChangeSettleSince = nil
					state.ResidenceSince = now
					state.DepartureArmed = true
				end
			else
				state.RoomChangeSettleSince = nil
			end
			return
		end

		if state.AwaitingPostHuntReturn then
			state.ResidenceSince = nil
			state.ResidenceArmed = false
			state.DepartureArmed = false
			state.OutsideSince = nil
			state.OutsideSamples = 0
			if not inFavourite then
				state.ReturnSeenSince = nil
				return
			end
			state.ReturnSeenSince = state.ReturnSeenSince or now
			if now < state.PostHuntGraceUntil
				or now - state.ReturnSeenSince < 0.5 then
				return
			end
			state.AwaitingPostHuntReturn = false
			state.PostHuntGraceUntil = 0
			state.ResidenceSince = state.ReturnSeenSince
			state.ReturnSeenSince = nil
			state.DepartureArmed = true
		end

		if not inFavourite then
			state.ResidenceSince = nil
			state.ResidenceArmed = false
			if not state.DepartureArmed then
				state.OutsideSince = nil
				state.OutsideSamples = 0
				return
			end
			state.OutsideSince = state.OutsideSince or now
			state.OutsideSamples = state.OutsideSamples + 1
			if state.OutsideSamples >= 4 and now - state.OutsideSince >= 0.5 then
				state.DepartureArmed = false
				self:OnDeparture({Source = event.Source})
			end
			return
		end

		state.OutsideSince = nil
		state.OutsideSamples = 0
		state.ResidenceSince = state.ResidenceSince or now
		local residenceAge = now - state.ResidenceSince
		if residenceAge >= 0.5 then
			state.DepartureArmed = true
		end
		if residenceAge >= 5 then
			state.ResidenceArmed = true
		end
	end

	function observer:OnFavouriteResidence(event)
		event = type(event) == "table" and event or {}
		local count = tonumber(event.Count) or state.ResidenceCount + 1
		state.ResidenceCount = math.max(1, count)
		state.LastResidenceReason = event.Reason
		api:Detect(
			"Specter",
			event.Reason
				or (
					"ghost remained continuously inside its favourite room for at least five seconds until hunt start ("
					.. tostring(state.ResidenceCount)
					.. " time"
					.. (state.ResidenceCount == 1 and ")" or "s)")
				),
			tonumber(event.Confidence)
				or (state.ResidenceCount >= 2 and 65 or 35),
			event.Source
		)
		api:Refresh()
	end

	function observer:OnDeparture(event)
		event = type(event) == "table" and event or {}
		state.LastDepartureReason = event.Reason
		api:RuleOut(
			"Specter",
			event.Reason
				or "the non-hunting ghost remained outside its unchanged favourite room across multiple verified samples",
			95
		)
		api:Refresh()
	end

	function observer:Snapshot()
		return {
			ResidenceCount = state.ResidenceCount,
			LastResidenceReason = state.LastResidenceReason,
			LastDepartureReason = state.LastDepartureReason,
			TrackedFavourite = state.TrackedFavourite,
			RoomChangePause = state.RoomChangePause,
			ResidenceSince = state.ResidenceSince,
			ResidenceArmed = state.ResidenceArmed,
			DepartureArmed = state.DepartureArmed,
			AwaitingPostHuntReturn = state.AwaitingPostHuntReturn,
			OutsideSamples = state.OutsideSamples,
		}
	end

	return observer
end

return {
	Name = "Specter",
	Evidence = {"EMFLevel5", "FreezingTemperatures", "LaserProjector"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 35,
	TTL = 120,
	ObservationKeys = {"FavouriteRoomConfinement"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "Repeated position or salt tracking establishes that it never leaves the favorite room except to hunt.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Maybe"] = {
			{
				Text = "It remains fixed to its favorite room while frequently throwing one object at a time.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "Frequent throwing alone overlaps with Ravager and ordinary ghost activity.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Caveat",
			},
		},
	},
}
