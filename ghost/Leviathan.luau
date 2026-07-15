local NAME = "Leviathan"

local function createObserver(api)
	local specification = api and type(api.Specification) == "function"
		and api:Specification() or {}
	local leviathanSpec = type(specification.Leviathan) == "table"
		and specification.Leviathan or {}
	local required = tonumber(leviathanSpec.RequiredToggles) or 7
	local maximumWindow = tonumber(leviathanSpec.WindowSeconds) or 2.5
	local state = {Destroyed = false, Matched = false, ToggleCount = 0, Duration = nil}
	local observer = {}

	function observer:OnEvent(event)
		if state.Destroyed or type(event) ~= "table"
			or (event.Type or event.Kind) ~= "DeviceToggleBurst" then return false end
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		local count = tonumber(event.ToggleCount or event.Count) or 0
		local duration = tonumber(event.Duration or event.Window) or math.huge
		state.ToggleCount, state.Duration = count, duration
		local clean = event.Clean == true
			and event.Alternating == true
			and event.Rapid == true
		if not state.Matched and event.Qualified == true
			and event.SingleDevice == true and clean
			and event.PlayerCaused ~= true
			and event.AutomationCaused ~= true
			and event.FuseCaused ~= true
			and count >= required and duration <= maximumWindow then
			state.Matched = true
			if api and type(api.Positive) == "function" then
				api:Positive(
					NAME,
					event.Reason or ("one eligible device cleanly toggled "
						.. tostring(count) .. " times within " .. tostring(duration) .. " seconds"),
					99,
					event
				)
			end
		end
		return true
	end

	function observer:Reset() state.Matched, state.ToggleCount, state.Duration = false, 0, nil end
	function observer:Snapshot()
		return {Destroyed = state.Destroyed, Matched = state.Matched, ToggleCount = state.ToggleCount, Duration = state.Duration}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"GhostOrb", "GhostWriting", "Handprints"},
	ObservationEvents = {"DeviceToggleBurst"},
	PersistentFindings = true,
	Perks = {
		["Pretty Sure"] = {"One Spirit Box, Laser Projector, or Blacklight cleanly toggles at least seven times within 2.5 seconds."},
		Maybe = {},
		Idk = {"Room-light shutoffs and ordinary hunt flicker are not Leviathan observations."},
	},
	CreateObserver = createObserver,
}
