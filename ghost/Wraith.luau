local NAME = "Wraith"
local UNDISTURBED_GRACE = 4

local function read(event, key)
	if event[key] ~= nil then return event[key] end
	if type(event.Payload) == "table" then return event.Payload[key] end
	return nil
end

local function createObserver(api)
	local state = {
		Destroyed = false,
		Contacts = {},
		LastOutcome = nil,
		DecisionEvidenceId = nil,
		DisturbedSaltSeen = false,
	}
	local observer = {}
	local function resolve(id, outcome, event)
		local contact = state.Contacts[id]
		if type(contact) ~= "table" then
			contact = {
				Time = tonumber(read(event, "Time")) or os.clock(),
				EventId = event.Id or event.EventId,
			}
			state.Contacts[id] = contact
		end
		if contact.Resolved and contact.Outcome == outcome then return end
		-- A replicated disturbance is authoritative and may correct an earlier
		-- timeout; the reverse correction is never allowed.
		if contact.Resolved and contact.Outcome == "Disturbed" then return end
		contact.Resolved, contact.Outcome = true, outcome
		state.LastOutcome = outcome
		local now = tonumber(read(event, "Time")) or os.clock()
		local elapsed = math.max(0, now - (contact.Time or now))
		local conclusion = {
			Type = "SaltContactResult",
			Time = now,
			Source = "WraithObserver",
			ParentId = contact.EventId,
			ContactId = id,
			DirectContact = true,
			Disturbed = outcome == "Disturbed",
			Completed = true,
			Elapsed = elapsed,
			Payload = {
				ContactId = id,
				DirectContact = true,
				Disturbed = outcome == "Disturbed",
				Completed = true,
				Elapsed = elapsed,
				TriggerEventId = contact.EventId,
			},
		}
		local entry
		if outcome == "Disturbed" then
			-- One disturbed pile disproves Wraith globally. Keep every salt contact
			-- on the same evidence chain so a different ContactId cannot leave an
			-- older positive effective or resurrect Wraith later.
			if state.DisturbedSaltSeen then return end
			state.DisturbedSaltSeen = true
			if state.DecisionEvidenceId and api and type(api.Supersede) == "function" then
				entry = api:Supersede(NAME, state.DecisionEvidenceId, "RuleOut", read(event, "Reason") or "a DisturbedSaltLine exists, so the ghost can touch salt", 99, conclusion)
			elseif api and type(api.RuleOut) == "function" then
				entry = api:RuleOut(NAME, read(event, "Reason") or "a DisturbedSaltLine exists, so the ghost can touch salt", 99, conclusion)
			end
		else
			if state.DisturbedSaltSeen or state.DecisionEvidenceId ~= nil then return end
			if api and type(api.Positive) == "function" then entry = api:Positive(NAME, read(event, "Reason") or "the directly touched salt pile remained undisturbed for four seconds", 99, conclusion) end
		end
		state.DecisionEvidenceId = type(entry) == "table" and entry.Id
			or state.DecisionEvidenceId
	end

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "SaltContactResult" and kind ~= "SaltContact" and kind ~= "SaltDisturbed" and kind ~= "Tick" then return false end
		if kind == "Tick" then
			local now = tonumber(read(event, "Time")) or os.clock()
			for id, contact in pairs(state.Contacts) do
				if type(contact) == "table" and not contact.Resolved and now - contact.Time >= UNDISTURBED_GRACE then
					resolve(id, "Undisturbed", event)
				end
			end
			return true
		end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		local id = read(event, "ContactId") or read(event, "SaltId") or read(event, "ModelId") or "default"
		if kind == "SaltContact" then
			if read(event, "DirectContact") ~= true then return true end
			if state.Contacts[id] == nil then
				state.Contacts[id] = {
					Time = tonumber(read(event, "Time")) or os.clock(),
					EventId = event.Id or event.EventId,
					Resolved = false,
				}
			end
			if read(event, "Disturbed") == true then resolve(id, "Disturbed", event) end
		elseif kind == "SaltDisturbed" then
			-- The DisturbedSaltLine world transition remains conclusive even when
			-- Roblox did not deliver the original SaltLine.Touched callback.
			resolve(id, "Disturbed", event)
		else
			if read(event, "DirectContact") ~= true then return true end
			local elapsed = tonumber(read(event, "Elapsed")) or 0
			if read(event, "Disturbed") == true then
				resolve(id, "Disturbed", event)
			elseif read(event, "Disturbed") == false and read(event, "Completed") == true and elapsed >= UNDISTURBED_GRACE then
				resolve(id, "Undisturbed", event)
			end
		end
		return true
	end
	function observer:Reset()
		state.Contacts, state.LastOutcome = {}, nil
		state.DecisionEvidenceId, state.DisturbedSaltSeen = nil, false
	end
	function observer:Snapshot()
		return {
			Destroyed = state.Destroyed,
			Contacts = state.Contacts,
			LastOutcome = state.LastOutcome,
			DecisionEvidenceId = state.DecisionEvidenceId,
			DisturbedSaltSeen = state.DisturbedSaltSeen,
		}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "LaserProjector", "SpiritBox"},
	ObservationEvents = {"SaltContactResult", "SaltContact", "SaltDisturbed", "Tick"},
	Perks = { ["Pretty Sure"] = {"A directly touched salt pile remains undisturbed for four seconds, regardless of hunt state."}, Maybe = {}, Idk = {"Untouched salt is not evidence; preserve the exact ContactId."} },
	CreateObserver = createObserver,
}
