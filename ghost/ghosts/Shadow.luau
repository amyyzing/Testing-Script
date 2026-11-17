local Shadow = {Name = "Shadow", Index = 15}

function Shadow.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Shadow requires Traffic")
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Shadow", function(signal, payload)
		if Processor.Resolved or signal ~= "RoomTemperatureAverage"
			or type(payload) ~= "table" or payload.Complete ~= true then return end
		local average = tonumber(payload.Average)
		local threshold = tonumber(payload.Threshold) or 0.08
		if not average then return end
		Processor.Resolved = true
		local supported = average < threshold - 0.000001
		if not supported then return end
		Traffic("Support", {
			Ghost = "Shadow",
			Confidence = 35,
			Reason = string.format(
				"room temperature changes averaged %.4f, %s %.4f; room conditions are uncontrolled",
				average,
				supported and "below" or "at or above", threshold
			),
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Shadow
