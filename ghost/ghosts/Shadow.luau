local Shadow = {Name = "Shadow", Index = 15}

function Shadow.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Shadow requires Traffic")
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Shadow", function(signal, payload)
		if Processor.Resolved or signal ~= "RoomTemperatureAverage"
			or type(payload) ~= "table" or payload.Complete ~= true then return end
		local average = tonumber(payload.Average)
		local threshold = tonumber(payload.Threshold) or 0.08
		if not average or average == threshold then return end
		Processor.Resolved = true
		local supported = average < threshold
		Traffic(supported and "Support" or "RuleOut", {
			Ghost = "Shadow",
			Confidence = 99,
			Reason = string.format(
				"room temperature changes averaged %.4f, %s 0.08",
				average,
				supported and "below" or "above"
			),
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Shadow
