local Phantom = {Name = "Phantom", Index = 12}

function Phantom.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Phantom requires Traffic")
	local epsilon = tonumber(dependencies.SpeedEpsilon) or 0.05
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Phantom", function(signal, payload)
		if Processor.Resolved or signal ~= "SevenPairResult"
			or type(payload) ~= "table" or type(payload.Pairs) ~= "table"
			or #payload.Pairs ~= 7 then return end
		local first = payload.Pairs[1]
		local visible = first and tonumber(first.v)
		local invisible = first and tonumber(first.i)
		if not visible or not invisible or visible <= 0 or invisible <= 0 then return end

		for _, pair in ipairs(payload.Pairs) do
			if pair.MixedVisibility ~= true
				or math.abs((tonumber(pair.v) or math.huge) - visible) > epsilon
				or math.abs((tonumber(pair.i) or math.huge) - invisible) > epsilon then
				return
			end
		end

		local supported = invisible > visible + epsilon
		Processor.Resolved = true
		Traffic(supported and "Support" or "RuleOut", {
			Ghost = "Phantom",
			Perk = "Blink speed",
			Observation = supported and "Blink speed alternated" or "No speed gain while hidden",
			Confidence = 99,
			Reason = supported
				and "seven hunting pairs repeated the same alternating A / B speed pattern"
				or "seven stable hunting pairs showed no speed gain while hidden",
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Phantom
