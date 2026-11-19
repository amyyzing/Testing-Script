local Aswang = {Name = "Aswang", Index = 1}

function Aswang.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Aswang requires Traffic")
	local epsilon = tonumber(dependencies.SpeedEpsilon) or 0.01
	local Processor = {LastVerdict = {}}
	local function report(signal, payload, observation)
		local previous = Processor.LastVerdict[payload.Perk]
		if previous and previous.Signal == signal and previous.Observation == observation then return end
		Processor.LastVerdict[payload.Perk] = {Signal = signal, Observation = observation}
		Traffic(signal, payload):SendTo("Verdict")
	end

	Processor.Disconnect = Traffic:Receive("Aswang", function(signal, data)
		data = type(data) == "table" and data or {}
		if signal == "SaltSpeed" and data.saltState == "disturbed" then
			if Processor.SaltConfirmed then return end
			local before = data.beforeSalt or {}
			local after = data.afterSalt or {}
			local baseline = {}
			for _, point in ipairs(before) do
				local speed = baseline[point.v]
				if not speed or point.s > speed then baseline[point.v] = point.s end
			end
			local comparedAfterSplit, dropped = false, false
			for index, point in ipairs(after) do
				local speed = baseline[point.v]
				if speed and index > 1 then comparedAfterSplit = true end
				if speed and speed > 0 and math.abs(point.s / speed - 0.75) <= 0.02 then
					dropped = true
					break
				end
			end
			if dropped or data.completed and comparedAfterSplit and (tonumber(data.Duration) or 0) >= 4 then
				if dropped then Processor.SaltConfirmed = true end
				report(dropped and "Support" or "RuleOut", {
					Ghost = "Aswang",
					Perk = "Salt slowdown",
					Observation = dropped and "Slowed on salt" or "No salt slowdown",
					Confidence = 99,
					Reason = dropped and "hunting disturbed-salt contact reduced speed by 25 percent"
						or "hunting salt contact caused no speed reduction",
				}, before)
			end
		elseif signal == "KillSpeed" then
			-- These small steps also fit the measured Dullahan ramp, not a discrete kill effect.
			if type(data.SpeedChange) == "number" and math.abs(data.SpeedChange) <= 0.05 then return end
			local before = data.beforeKill or {}
			local after = data.afterKill or {}
			if #after < 3 then return end
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
			for index = 2, #after do
				local point = after[index]
				if type(point.v) == "boolean" and type(point.s) == "number" and point.s > 0 then
					observed[point.v] = point.s
				end
			end
			if not baselines[true] or not baselines[false] or not observed[true] or not observed[false] then return end
			local rose = observed[true] > baselines[true] + epsilon
				and observed[false] > baselines[false] + epsilon
			if rose or data.completed then
				report(rose and "Support" or "RuleOut", {
					Ghost = "Aswang",
					Perk = "Speed rises after kill",
					Observation = rose and "Sped up after kill" or "No speed gain after kill",
					Confidence = 99,
					Reason = rose and "stable speed rose after a unique player kill"
						or "stable speed did not rise after a unique player kill",
				}, before)
			end
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Aswang
