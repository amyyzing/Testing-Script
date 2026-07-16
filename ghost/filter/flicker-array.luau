return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "flicker-array requires Traffic")
	local window = tonumber(dependencies.Window) or 1
	local requiredSwitches = tonumber(dependencies.RequiredSwitches) or 2
	local Tracker = {
		Kind = "filter",
		Running = true,
		Resolved = false,
		Arrays = setmetatable({}, {__mode = "k"}),
	}

	Tracker.Disconnect = Traffic:Receive("FlickerArray", function(signal, payload)
		if not Tracker.Running or Tracker.Resolved or signal ~= "ItemStateChanged"
			or type(payload) ~= "table" or payload.Item == nil
			or type(payload.Previous) ~= "boolean" or type(payload.Current) ~= "boolean"
			or payload.Previous == payload.Current then return end
		local now = tonumber(payload.Time)
		if not now then return end
		local switches = Tracker.Arrays[payload.Item]
		if not switches then
			switches = {}
			Tracker.Arrays[payload.Item] = switches
		end
		while switches[1] and now - switches[1].t >= window do table.remove(switches, 1) end
		local last = switches[#switches]
		if last and last.v == payload.Current then return end
		table.insert(switches, {t = now, v = payload.Current})
		local duration = switches[#switches].t - switches[1].t
		Traffic("FlickerArrayUpdate", {
			Item = payload.Item,
			ItemName = payload.ItemName,
			Switches = table.clone(switches),
			Count = #switches,
			RequiredSwitches = requiredSwitches,
			Window = window,
			Duration = duration,
			Completed = #switches >= requiredSwitches,
		}):SendTo("FlickerArrayLog")
		if #switches < requiredSwitches then return end
		Tracker.Resolved = true
		Traffic("FlickerArrayResult", {
			Item = payload.Item,
			ItemName = payload.ItemName,
			Switches = table.clone(switches),
			Count = #switches,
			RequiredSwitches = requiredSwitches,
			Window = window,
			Duration = duration,
		}):SendTo("Leviathan")
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
		table.clear(self.Arrays)
	end

	return Tracker
end
