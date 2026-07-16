return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "7-pair requires Traffic")
	local Ghost = assert(dependencies.Ghost, "7-pair requires Ghost")
	local Humanoid = dependencies.Humanoid or Ghost:FindFirstChildOfClass("Humanoid")
	local delay = dependencies.Delay or task and task.delay
	assert(type(delay) == "function", "7-pair requires task.delay")
	local startDelay = tonumber(dependencies.StartDelay) or 1
	local Tracker = {
		Kind = "filter",
		Running = true,
		Active = false,
		Resolved = false,
		Pairs = {},
		Pending = nil,
		LastVisibility = nil,
		SampleCount = 0,
		Generation = 0,
	}

	local function stopSampling()
		if not Tracker.Connection then return end
		Tracker.Connection:Disconnect()
		Tracker.Connection = nil
	end

	local function reset(active)
		stopSampling()
		Tracker.Generation += 1
		Tracker.Active = active == true
		Tracker.Resolved = false
		Tracker.Pairs = {}
		Tracker.Pending = nil
		Tracker.LastVisibility = nil
		Tracker.SampleCount = 0
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
			Samples = Tracker.SampleCount,
		}):SendTo("Dullahan", "SpeedFilter", "SpeedArrayLog")
	end

	local function sample()
		local speed = Humanoid and tonumber(Humanoid.WalkSpeed)
		if not speed then return end
		local transparency = Ghost:GetAttribute("Transparency")
		local visible
		if type(transparency) == "boolean" then
			visible = not transparency
		elseif type(transparency) == "number" then
			visible = transparency < 0.5
		else
			return
		end
		if Tracker.LastVisibility == visible then return end
		Tracker.LastVisibility = visible
		Tracker.SampleCount += 1
		local point = {s = speed, v = visible}
		Traffic("HuntSpeedSample", {
			Index = Tracker.SampleCount,
			Point = {s = point.s, v = point.v},
		}):SendTo("SpeedArrayLog", "SpeedTracker")
		if not Tracker.Pending then
			Tracker.Pending = point
		else
			local first = Tracker.Pending
			local pair
			if first.v ~= point.v then
				pair = first.v
					and {v = first.s, i = point.s}
					or {v = point.s, i = first.s}
				pair.MixedVisibility = true
			else
				pair = {
					v = first.s,
					i = point.s,
					MixedVisibility = false,
				}
			end
			pair.a = first
			pair.b = point
			table.insert(Tracker.Pairs, pair)
			Tracker.Pending = nil
			if #Tracker.Pairs == 7 then finish() end
		end
	end

	local function startSampling()
		if Tracker.Connection then return end
		Tracker.Connection = Ghost:GetAttributeChangedSignal("Transparency"):Connect(function()
			if not Tracker.Active or Tracker.Resolved then return end
			sample()
		end)
		sample()
	end

	Tracker.Disconnect = Traffic:Receive("SevenPair", function(signal, payload)
		if signal ~= "HuntingState" then return end
		local hunting = type(payload) == "table" and payload.Hunting == true
		if hunting then
			if not Tracker.Active then
				reset(true)
				local generation = Tracker.Generation
				delay(startDelay, function()
					if Tracker.Running and Tracker.Active
						and Tracker.Generation == generation then
						startSampling()
					end
				end)
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
