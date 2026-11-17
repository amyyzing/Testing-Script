local Wretch = {Name = "Wretch", Index = 23}

function Wretch.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Wretch requires Traffic")
	local Processor = {Supported = false, RuledOut = false}
	Processor.Disconnect = Traffic:Receive("Wretch", function(signal, payload)
		if Processor.RuledOut or signal ~= "WretchSpeedResult"
			or type(payload) ~= "table" or payload.Complete ~= true then return end
		if payload.Matched == true then
			if Processor.Supported then return end
			Processor.Supported = true
			Traffic("Support", {
				Ghost = "Wretch",
				Confidence = 99,
				Reason = string.format(
					"state-change WalkSpeed %.3f matched expected %.3f at %.2f%% average Energy",
					payload.Speed, payload.ExpectedSpeed, payload.AverageEnergy
				),
			}):SendTo("Verdict")
		else
			Processor.RuledOut = true
			Traffic("RuleOut", {
				Ghost = "Wretch",
				Confidence = 99,
				Reason = string.format(
					"state-change WalkSpeed %.3f did not match closest expected %.3f at %.2f%% average Energy",
					payload.Speed, payload.ExpectedSpeed, payload.AverageEnergy
				),
			}):SendTo("Verdict")
		end
	end)
	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Wretch
