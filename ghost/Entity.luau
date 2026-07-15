local NAME = "Entity"

local function createObserver(api)
	local state = {Destroyed = false, LastOutcome = nil, Processed = {}}
	local observer = {}

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table"
			or (event.Type or event.Kind) ~= "ObjectTeleportResult" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Qualified ~= true or event.ConfirmedTeleport ~= true
			or event.Completed ~= true
			or type(event.SmokeFound) ~= "boolean" then return true end
		-- The same world object can teleport more than once. Deduplicate the
		-- observation episode/event, never the reused object instance.
		local id = event.EventId or event.Id or event.EpisodeId
			or (tostring(event.TeleportId or "teleport")
				.. ":" .. tostring(event.Time or "unknown"))
		if state.Processed[id] then return true end
		state.Processed[id] = true
		if event.SmokeFound then
			state.LastOutcome = "Smoke"
			if api and type(api.Positive) == "function" then
				api:Positive(NAME, event.Reason or "a confirmed object teleport coincided with a SmokeHolder anywhere in Workspace", 99, event)
			end
		else
			state.LastOutcome = "NoSmoke"
			if api and type(api.Negative) == "function" then
				api:Negative(NAME, event.Reason or "a confirmed object teleport completed without any SmokeHolder", 50, event)
			end
		end
		return true
	end

	function observer:Reset() state.LastOutcome, state.Processed = nil, {} end
	function observer:Snapshot()
		return {Destroyed = state.Destroyed, LastOutcome = state.LastOutcome, Processed = state.Processed}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"Handprints", "LaserProjector", "SpiritBox"},
	ObservationEvents = {"ObjectTeleportResult"},
	Perks = {
		["Pretty Sure"] = {"A confirmed Item/Interactable teleport coincides with a SmokeHolder anywhere in Workspace."},
		Maybe = {},
		Idk = {"A confirmed object teleport without SmokeHolder is a 50% negative, not a hard rule-out."},
	},
	CreateObserver = createObserver,
}
