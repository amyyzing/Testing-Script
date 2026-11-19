local Keres = {Name = "Keres", Index = 8}

function Keres.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Keres requires Traffic")
	local epsilon = tonumber(dependencies.SpeedEpsilon) or 0.01
	local Processor = {}

	Processor.Disconnect = Traffic:Receive("Keres", function(signal, data)
		if Processor.RuledOut or type(data) ~= "table" then return end
		if signal == "ModelGender" then
			if data.Gender ~= "Male" then return end
			Processor.RuledOut = true
			Traffic("RuleOut", {
				Ghost = "Keres",
				Perk = "Female model", Observation = "Male model",
				Confidence = 99,
				Reason = "the ghost uses a male VisualModel",
			}):SendTo("Verdict")
			return
		end
		if signal ~= "KillSpeed" then return end
		if type(data.SpeedChange) == "number" and math.abs(data.SpeedChange) <= 0.05 then return end
		local before = data.beforeKill
		local after = data.afterKill or {}
		if type(before) ~= "table" or #after < 3 then return end

		local baselines, observed = {}, {}
		for _, point in ipairs(before) do
			if type(point.v) == "boolean" and type(point.s) == "number" and point.s > 0 then
				baselines[point.v] = point.s
			end
		end
		local baseline = data.baselineKill
		if type(baseline) == "table" and type(baseline.v) == "boolean"
			and type(baseline.s) == "number" and baseline.s > 0 then
			baselines[baseline.v] = baseline.s
		end
		if type(data.baselinesKill) == "table" then
			for _, state in ipairs({true, false}) do
				local speed = data.baselinesKill[state]
				if type(speed) ~= "number" or speed <= 0 then return end
				baselines[state] = speed
			end
		end
		for index = 2, #after do
			local point = after[index]
			if type(point.v) == "boolean" and type(point.s) == "number" and point.s > 0 then
				observed[point.v] = math.max(observed[point.v] or 0, point.s)
			end
		end
		if not baselines[true] or not baselines[false] or not observed[true] or not observed[false] then return end
		local dropped = observed[true] < baselines[true] - epsilon
			and observed[false] < baselines[false] - epsilon
		if dropped then
			Traffic("Support", {
				Ghost = "Keres",
				Perk = "Speed drops after kill",
				Observation = "Slowed after kill",
				Confidence = 99,
				Reason = "stable speed dropped after a unique player kill",
			}):SendTo("Verdict")
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Keres
