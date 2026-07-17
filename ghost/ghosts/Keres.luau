local Keres = {Name = "Keres", Index = 8}

function Keres.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Keres requires Traffic")
	local epsilon = tonumber(dependencies.SpeedEpsilon) or 0.01
	local Processor = {}

	Processor.Disconnect = Traffic:Receive("Keres", function(signal, data)
		if type(data) ~= "table" then return end
		if signal == "ModelGender" then
			if data.Gender ~= "Female" and data.Gender ~= "Male" then return end
			local female = data.Gender == "Female"
			Traffic(female and "Support" or "RuleOut", {
				Ghost = "Keres",
				Confidence = female and 25 or 99,
				Reason = female and "the ghost uses a female VisualModel"
					or "the ghost uses a male VisualModel",
			}):SendTo("Verdict")
			return
		end
		if signal ~= "KillSpeed" then return end
		local before = data.baselineKill or data.beforeKill and data.beforeKill[#data.beforeKill]
		local after = data.afterKill or {}
		if not before or #after < 3 then return end
		local a, b = after[#after - 1], after[#after]
		local dropped = a.s < before.s - epsilon and b.s < before.s - epsilon
			and math.abs(a.s - b.s) <= epsilon
		if dropped or data.completed then
			Traffic(dropped and "Support" or "RuleOut", {
				Ghost = "Keres",
				Confidence = 99,
				Reason = dropped and "stable speed permanently dropped after a unique player kill"
					or "stable speed did not permanently drop after a unique player kill",
			}):SendTo("Verdict")
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Keres
