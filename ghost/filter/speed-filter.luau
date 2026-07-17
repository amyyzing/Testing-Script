return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "speed-filter requires Traffic")
	local World = dependencies.Workspace or workspace
	local epsilon = tonumber(dependencies.SpeedEpsilon) or 0.05
	local customMultipliers = {0.5, 0.75, 1, 1.25, 1.5, 2}
	local baseSpeeds = {11, 13.5}
	local Filter = {Kind = "filter", Running = true}

	local function mapMultiplier()
		local map = World:FindFirstChild("Map")
		local size = string.lower(tostring(map and map:GetAttribute("MapSize") or "Small"))
		if size == "large" then return 1.1 end
		if size == "medium" then return 1.05 end
		return 1
	end

	local function inspect(pairs)
		local result = {
			Complete = type(pairs) == "table" and #pairs == 7,
			Identical = false,
			HasBothStates = false,
			MapMultiplier = mapMultiplier(),
		}
		if not result.Complete then return result end
		local firstSpeed
		local identical = true
		local sawVisible, sawInvisible = false, false
		local speeds = {}
		for _, pair in ipairs(pairs) do
			for _, point in ipairs({pair.a, pair.b}) do
				local speed = type(point) == "table" and tonumber(point.s)
				if not speed then return result end
				firstSpeed = firstSpeed or speed
				if math.abs(speed - firstSpeed) > epsilon then identical = false end
				sawVisible = sawVisible or point.v == true
				sawInvisible = sawInvisible or point.v == false
				table.insert(speeds, speed)
			end
		end
		result.HasBothStates = sawVisible and sawInvisible
		if not sawVisible or not sawInvisible then return result end
		if not identical then return result end
		result.Identical = true
		local bestError = math.huge
		for _, baseSpeed in ipairs(baseSpeeds) do
			for _, customMultiplier in ipairs(customMultipliers) do
				local expected = baseSpeed * result.MapMultiplier * customMultiplier
				local errorAmount = 0
				for _, speed in ipairs(speeds) do
					errorAmount = math.max(errorAmount, math.abs(speed - expected))
				end
				if errorAmount < bestError then
					bestError = errorAmount
					result.BaseSpeed = baseSpeed
					result.CustomMultiplier = customMultiplier
					result.ExpectedSpeed = expected
				end
			end
		end
		result.Error = bestError
		if bestError > epsilon then
			result.BaseSpeed = nil
			result.CustomMultiplier = nil
			result.ExpectedSpeed = nil
		end
		return result
	end

	local function inspectWendigo(payload)
		local energy = tonumber(payload.AverageEnergy)
		local speed = tonumber(payload.Speed)
		if not energy or not speed then return {Complete = false} end
		energy = math.clamp(energy, 0, 100)
		local result = {
			Complete = true,
			Hunting = payload.Hunting == true,
			AverageEnergy = energy,
			Speed = speed,
			BaseSpeed = 14 - energy * 0.05,
			MapMultiplier = mapMultiplier(),
		}
		local bestError = math.huge
		for _, multiplier in ipairs(customMultipliers) do
			local expected = result.BaseSpeed * result.MapMultiplier * multiplier
			local errorAmount = math.abs(speed - expected)
			if errorAmount < bestError then
				bestError = errorAmount
				result.Multiplier = multiplier
				result.ExpectedSpeed = expected
			end
		end
		result.Error = bestError
		result.Matched = bestError <= epsilon
		return result
	end

	Filter.Disconnect = Traffic:Receive("SpeedFilter", function(signal, payload)
		if not Filter.Running or type(payload) ~= "table" then return end
		if signal == "SevenPairResult" then
			local result = inspect(payload.Pairs)
			result.Pairs = payload.Pairs
			result.DistinctPairs = payload.DistinctPairs
			result.Samples = payload.Samples
			Traffic("SpeedFilterResult", result):SendTo("Dullahan", "Oni")
		elseif signal == "WendigoSpeedSample" then
			Traffic("WendigoSpeedResult", inspectWendigo(payload)):SendTo("Wendigo")
		end
	end)

	function Filter:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
	end

	return Filter
end
