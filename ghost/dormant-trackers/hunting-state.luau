return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "hunting-state requires Traffic")
	local Ghost = assert(dependencies.Ghost, "hunting-state requires Ghost")
	local Tracker = {Kind = "active", Running = true}

	local function publish()
		Traffic:Broadcast("HuntingState", {
			Hunting = Ghost:GetAttribute("Hunting") == true,
			Time = os.clock(),
		})
	end

	Tracker.Connection = Ghost:GetAttributeChangedSignal("Hunting"):Connect(publish)
	publish()

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Connection:Disconnect()
	end

	return Tracker
end
