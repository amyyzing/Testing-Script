local Wendigo = {Name = "Wendigo", Index = 23}

function Wendigo.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Wendigo requires Traffic")
	local Processor = {Supported = false, RuledOut = false}
	Processor.Disconnect = Traffic:Receive("Wendigo", function(signal, payload)
		if Processor.RuledOut or signal ~= "WendigoSpeedResult"
			or type(payload) ~= "table" or payload.Complete ~= true then return end
		if payload.Matched == true then
			if Processor.Supported then return end
			Processor.Supported = true
			Traffic("Support", {
				Ghost = "Wendigo",
				Confidence = 99,
				Reason = string.format(
					"state-change WalkSpeed %.3f matched expected %.3f at %.2f%% average Energy",
					payload.Speed, payload.ExpectedSpeed, payload.AverageEnergy
				),
			}):SendTo("Verdict")
		else
			Processor.RuledOut = true
			Traffic("RuleOut", {
				Ghost = "Wendigo",
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

return Wendigo
