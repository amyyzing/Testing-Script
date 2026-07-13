local SOURCE = "https://demonology.fandom.com/wiki/Wraith"

local function createObserver(api)
	local state = {
		LastDisturbed = nil,
		LastReason = nil,
		Contacts = {},
	}
	local observer = {}

	function observer:Reset()
		state.LastDisturbed = nil
		state.LastReason = nil
		state.Contacts = {}
	end

	function observer:OnSaltObservation(event)
		if type(event) ~= "table" or event.TouchObserved ~= true then
			return
		end
		local contactId = event.ContactId or "default"
		if state.Contacts[contactId] then
			return
		end
		if event.SaltDisturbed == true then
			state.Contacts[contactId] = true
			self:OnSaltContact({
				Disturbed = true,
				Source = event.Source,
			})
		elseif (tonumber(event.Age) or 0) >= 1.25 then
			state.Contacts[contactId] = true
			self:OnSaltContact({
				Disturbed = false,
				Source = event.Source,
			})
		end
	end

	function observer:OnSaltContact(event)
		if type(event) ~= "table" or type(event.Disturbed) ~= "boolean" then
			return
		end
		state.LastDisturbed = event.Disturbed
		state.LastReason = event.Reason
		if event.Disturbed then
			api:RuleOut(
				"Wraith",
				event.Reason
					or "the same touched SaltLine became DisturbedSaltLine",
				99
			)
		else
			api:Detect(
				"Wraith",
				event.Reason
					or "Ghost touched SaltLine without disturbing it, independent of hunt state",
				95,
				event.Source
			)
		end
		api:Refresh()
	end

	function observer:Snapshot()
		return {
			LastDisturbed = state.LastDisturbed,
			LastReason = state.LastReason,
			Contacts = state.Contacts,
		}
	end

	return observer
end

return {
	Name = "Wraith",
	Evidence = {"EMFLevel5", "LaserProjector", "SpiritBox"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 95,
	TTL = 120,
	ObservationKeys = {"SaltContactDisturbance"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "It is directly observed touching or crossing a salt line without disturbing it, whether hunting or not.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Weakness",
			},
			{
				Text = "Measured passive energy drain is roughly 0.2-0.4% per second faster than normal.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Maybe"] = {
			{
				Text = "The party's energy falls unusually quickly across a sustained sample.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "Untouched salt is not useful unless the ghost was known to cross it.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Caveat",
			},
		},
	},
}
