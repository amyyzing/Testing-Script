local Phantom = {Name = "Phantom", Index = 12}

function Phantom.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Phantom requires Traffic")
	local epsilon = tonumber(dependencies.SpeedEpsilon) or 0.05
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Phantom", function(signal, payload)
		if Processor.Resolved or signal ~= "SevenPairResult"
			or type(payload) ~= "table" or type(payload.Pairs) ~= "table"
			or #payload.Pairs ~= 7 then return end
		Processor.Resolved = true
		local first = payload.Pairs[1]
		local visible = first and tonumber(first.v)
		local invisible = first and tonumber(first.i)
		local supported = visible ~= nil and invisible ~= nil
			and math.abs(visible - invisible) > epsilon
		for _, pair in ipairs(payload.Pairs) do
			if not supported or pair.MixedVisibility ~= true
				or math.abs((tonumber(pair.v) or math.huge) - visible) > epsilon
				or math.abs((tonumber(pair.i) or math.huge) - invisible) > epsilon then
				supported = false
				break
			end
		end
		Traffic(supported and "Support" or "RuleOut", {
			Ghost = "Phantom",
			Confidence = 99,
			Reason = supported
				and "seven hunting pairs repeated the same alternating A / B speed pattern"
				or "seven hunting pairs did not repeat an alternating A / B speed pattern",
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Phantom
