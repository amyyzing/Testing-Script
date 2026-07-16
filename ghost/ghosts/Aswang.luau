local Aswang = {Name = "Aswang", Index = 1}

function Aswang.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Aswang requires Traffic")
	local epsilon = tonumber(dependencies.SpeedEpsilon) or 0.01
	local Processor = {}

	Processor.Disconnect = Traffic:Receive("Aswang", function(signal, data)
		data = type(data) == "table" and data or {}
		if signal == "SaltSpeed" and data.saltState == "disturbed" then
			local before = data.beforeSalt and data.beforeSalt[#data.beforeSalt]
			if not before then return end
			local after = data.afterSalt or {}
			local dropIndex
			for index, point in ipairs(after) do
				if point.s < before.s - epsilon then
					dropIndex = index
					break
				end
			end
			local recovered = false
			if dropIndex then
				for index = dropIndex + 1, #after do
					if after[index].s >= before.s - epsilon then
						recovered = true
						break
					end
				end
			end
			if recovered or data.completed and not dropIndex then
				Traffic(recovered and "Support" or "RuleOut", {
					Ghost = "Aswang",
					Confidence = 99,
					Reason = recovered and "hunting disturbed-salt contact temporarily reduced speed, then recovered"
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
