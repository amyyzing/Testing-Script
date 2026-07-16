return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "7-pair requires Traffic")
	local Tracker = {
		Kind = "filter",
		Running = true,
		Active = false,
		Resolved = false,
		Pairs = {},
		Pending = nil,
	}

	local function reset(active)
		Tracker.Active = active == true
		Tracker.Resolved = false
		Tracker.Pairs = {}
		Tracker.Pending = nil
	end

	local function distinctPairCount(pairs)
		local distinct = {}
		for _, pair in ipairs(pairs) do
			local found = false
			for _, other in ipairs(distinct) do
				if pair.v == other.v and pair.i == other.i then
					found = true
					break
				end
			end
			if not found then table.insert(distinct, pair) end
		end
		return #distinct
	end

	local function finish()
		Tracker.Resolved = true
		Traffic("SevenPairResult", {
			Pairs = table.clone(Tracker.Pairs),
			DistinctPairs = distinctPairCount(Tracker.Pairs),
		}):SendTo("Dullahan")
	end

	local function addPoint(payload)
		if Tracker.Resolved then return end
		local point = type(payload) == "table" and payload.Point
		local speed = type(point) == "table" and tonumber(point.s)
		if not speed or type(point.v) ~= "boolean" then return end
		if not Tracker.Active then reset(true) end

		local source = payload.Source
		if source == "speed" then
			if Tracker.Pending and Tracker.Pending.v == point.v then
				Tracker.Pending.s = speed
			end
			return
		end
		if source ~= nil and source ~= "state" and source ~= "visibility" then return end

		if not Tracker.Pending then
			Tracker.Pending = {s = speed, v = point.v}
		elseif Tracker.Pending.v == point.v then
			Tracker.Pending.s = speed
		else
			local first = Tracker.Pending
			table.insert(Tracker.Pairs, first.v
				and {v = first.s, i = speed}
				or {v = speed, i = first.s})
			Tracker.Pending = nil
			if #Tracker.Pairs == 7 then finish() end
		end
	end

	Tracker.Disconnect = Traffic:Receive("SevenPair", function(signal, payload)
		if signal == "HuntingState" then
			local hunting = type(payload) == "table" and payload.Hunting == true
			if hunting then
				if not Tracker.Active then reset(true) end
			else
				reset(false)
			end
		elseif signal == "HuntSpeedSample" then
			addPoint(payload)
		end
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
		table.clear(self.Pairs)
		self.Pending = nil
	end

	return Tracker
end
