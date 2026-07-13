local NAME = "Wraith"

local function read(event, key)
	if event[key] ~= nil then return event[key] end
	if type(event.Payload) == "table" then return event.Payload[key] end
	return nil
end

local function createObserver(api)
	local state = {Destroyed = false, Contacts = {}, LastOutcome = nil}
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
		if contact.Resolved then return end
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
		if outcome == "Disturbed" then
			if api and type(api.RuleOut) == "function" then api:RuleOut(NAME, read(event, "Reason") or "the same directly touched salt pile became disturbed", 99, conclusion) end
		else
			if api and type(api.Positive) == "function" then api:Positive(NAME, read(event, "Reason") or "the directly touched salt pile remained undisturbed for 1.25 seconds", 99, conclusion) end
		end
	end

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind ~= "SaltContactResult" and kind ~= "SaltContact" and kind ~= "SaltDisturbed" and kind ~= "Tick" then return false end
		if kind == "Tick" then
			local now = tonumber(read(event, "Time")) or os.clock()
			for id, contact in pairs(state.Contacts) do
				if type(contact) == "table" and not contact.Resolved and now - contact.Time >= 1.25 then
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
			if state.Contacts[id] ~= nil or read(event, "DirectContact") == true then resolve(id, "Disturbed", event) end
		else
			if read(event, "DirectContact") ~= true then return true end
			local elapsed = tonumber(read(event, "Elapsed")) or 0
			if read(event, "Disturbed") == true then
				resolve(id, "Disturbed", event)
			elseif read(event, "Disturbed") == false and read(event, "Completed") == true and elapsed >= 1.25 then
				resolve(id, "Undisturbed", event)
			end
		end
		return true
	end
	function observer:Reset() state.Contacts, state.LastOutcome = {}, nil end
	function observer:Snapshot() return {Destroyed = state.Destroyed, Contacts = state.Contacts, LastOutcome = state.LastOutcome} end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"EMFLevel5", "LaserProjector", "SpiritBox"},
	ObservationEvents = {"SaltContactResult", "SaltContact", "SaltDisturbed", "Tick"},
	Perks = { ["Pretty Sure"] = {"A directly touched salt pile remains undisturbed for 1.25 seconds, regardless of hunt state."}, Maybe = {}, Idk = {"Untouched salt is not evidence; preserve the exact ContactId."} },
	CreateObserver = createObserver,
}
