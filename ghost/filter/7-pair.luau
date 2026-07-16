return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "7-pair requires Traffic")
	local Ghost = assert(dependencies.Ghost, "7-pair requires Ghost")
	local RunService = assert(dependencies.RunService, "7-pair requires RunService")
	local Model = dependencies.GhostModel or Ghost:FindFirstChild("GhostModel", true) or Ghost
	local Humanoid = dependencies.Humanoid or Ghost:FindFirstChildOfClass("Humanoid")
	local interval = tonumber(dependencies.Interval) or 0.1
	local Tracker = {
		Kind = "filter",
		Running = true,
		Active = false,
		Resolved = false,
		Pairs = {},
		Pending = nil,
		Accumulator = 0,
	}

	local function stopSampling()
		if not Tracker.Connection then return end
		Tracker.Connection:Disconnect()
		Tracker.Connection = nil
	end

	local function reset(active)
		stopSampling()
		Tracker.Active = active == true
		Tracker.Resolved = false
		Tracker.Pairs = {}
		Tracker.Pending = nil
		Tracker.Accumulator = 0
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
		stopSampling()
		Traffic("SevenPairResult", {
			Pairs = table.clone(Tracker.Pairs),
			DistinctPairs = distinctPairCount(Tracker.Pairs),
		}):SendTo("Dullahan")
	end

	local function sample()
		local speed = Humanoid and tonumber(Humanoid.WalkSpeed)
		if not speed then return end
		local point = {s = speed, v = Model:GetAttribute("Transparency") == 0}
		if not Tracker.Pending then
			Tracker.Pending = point
		elseif Tracker.Pending.v == point.v then
			Tracker.Pending = point
		else
			local first = Tracker.Pending
			table.insert(Tracker.Pairs, first.v
				and {v = first.s, i = point.s}
				or {v = point.s, i = first.s})
			Tracker.Pending = nil
			if #Tracker.Pairs == 7 then finish() end
		end
	end

	local function startSampling()
		if Tracker.Connection then return end
		Tracker.Connection = RunService.Heartbeat:Connect(function(deltaTime)
			if not Tracker.Active or Tracker.Resolved then return end
			Tracker.Accumulator += math.max(0, tonumber(deltaTime) or 0)
			if Tracker.Accumulator < interval then return end
			Tracker.Accumulator %= interval
			sample()
		end)
	end

	Tracker.Disconnect = Traffic:Receive("SevenPair", function(signal, payload)
		if signal ~= "HuntingState" then return end
		local hunting = type(payload) == "table" and payload.Hunting == true
		if hunting then
			if not Tracker.Active then
				reset(true)
				startSampling()
			end
		else
			reset(false)
		end
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
		reset(false)
	end

	return Tracker
end
