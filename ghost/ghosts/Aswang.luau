local Aswang = {Name = "Aswang", Index = 1}

function Aswang.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Aswang requires Traffic")
	local epsilon = tonumber(dependencies.SpeedEpsilon) or 0.01
	local Processor = {}

	Processor.Disconnect = Traffic:Receive("Aswang", function(signal, data)
		data = type(data) == "table" and data or {}
		if signal == "SaltSpeed" and data.saltState == "disturbed" then
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
				if speed and point.s < speed - epsilon then
					dropped = true
					break
				end
			end
			if dropped or data.completed and comparedAfterSplit then
				Traffic(dropped and "Support" or "RuleOut", {
					Ghost = "Aswang",
					Perk = "Salt slowdown",
					Observation = dropped and "Slowed on salt" or "No salt slowdown",
					Confidence = 99,
					Reason = dropped and "hunting disturbed-salt contact reduced speed"
						or "hunting salt contact caused no speed reduction",
				}):SendTo("Verdict")
			end
		elseif signal == "KillSpeed" then
			local before = data.beforeKill or {}
			local after = data.afterKill or {}
			if #after < 3 then return end
			local baselines, observed = {}, {}
			for _, point in ipairs(before) do
				if type(point.v) == "boolean" and type(point.s) == "number" and point.s > 0 then
					baselines[point.v] = math.min(baselines[point.v] or math.huge, point.s)
				end
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
				Traffic(rose and "Support" or "RuleOut", {
					Ghost = "Aswang",
					Perk = "Speed rises after kill",
					Observation = rose and "Sped up after kill" or "No speed gain after kill",
					Confidence = 99,
					Reason = rose and "stable speed rose after a unique player kill"
						or "stable speed did not rise after a unique player kill",
				}):SendTo("Verdict")
			end
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Aswang
