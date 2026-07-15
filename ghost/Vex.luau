local NAME = "Vex"

local function createObserver(api)
	local state = {Destroyed = false, Checked = false, Exists = nil}
	local observer = {}
	function observer:OnEvent(event)
		if state.Destroyed or state.Checked or type(event) ~= "table"
			or (event.Type or event.Kind) ~= "LidarState" then return false end
		if event.Qualified ~= true or type(event.Exists) ~= "boolean" then return true end
		state.Checked, state.Exists = true, event.Exists
		if api and type(api.Record) == "function" then api:Record(NAME, event) end
		if event.Exists and api and type(api.Positive) == "function" then
			api:Positive(NAME, event.Reason or "the InvisibleOnLIDAR replicated member exists, regardless of its value", 99, event)
		elseif not event.Exists and api and type(api.RuleOut) == "function" then
			api:RuleOut(NAME, event.Reason or "the InvisibleOnLIDAR replicated member does not exist", 99, event)
		end
		return true
	end
	function observer:Reset() state.Checked, state.Exists = false, nil end
	function observer:Snapshot()
		return {Destroyed = state.Destroyed, Checked = state.Checked, Exists = state.Exists}
	end
	function observer:Destroy() state.Destroyed = true end
	return observer
end

return {
	Name = NAME,
	Evidence = {"FreezingTemperatures", "GhostOrb", "Wither"},
	ObservationEvents = {"LidarState"},
	OneShot = true,
	Perks = {
		["Pretty Sure"] = {"The InvisibleOnLIDAR replicated member exists, even if its value is false."},
		Maybe = {},
		Idk = {"Only explicit member absence rules Vex out."},
	},
	CreateObserver = createObserver,
}
