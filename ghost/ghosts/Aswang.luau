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
					Confidence = 99,
					Reason = dropped and "hunting disturbed-salt contact reduced speed"
						or "hunting salt contact caused no speed reduction",
				}):SendTo("Verdict")
			end
		elseif signal == "KillSpeed" then
			local before = data.beforeKill and data.beforeKill[#data.beforeKill]
			local after = data.afterKill or {}
			if not before or #after < 3 then return end
			local a, b = after[#after - 1], after[#after]
			local rose = a.s > before.s + epsilon and b.s > before.s + epsilon
				and math.abs(a.s - b.s) <= epsilon
			if rose or data.completed then
				Traffic(rose and "Support" or "RuleOut", {
					Ghost = "Aswang",
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
