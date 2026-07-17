local Umbra = {Name = "Umbra", Index = 20}

function Umbra.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Umbra requires Traffic")
	local Processor = {Checked = false}
	Processor.Disconnect = Traffic:Receive("Umbra", function(signal, payload)
		if Processor.Checked or signal ~= "FootstepSound" or type(payload) ~= "table"
			or type(payload.HasOtherSound) ~= "boolean" then return end
		Processor.Checked = true
		Traffic(payload.HasOtherSound and "RuleOut" or "Support", {
			Ghost = "Umbra",
			Confidence = payload.HasOtherSound and 99 or 95,
			Reason = payload.HasOtherSound
				and "HumanoidRootPart contained a Sound other than Hunting on the immediate check"
				or "HumanoidRootPart contained no Sound other than Hunting on the immediate check",
		}):SendTo("Verdict")
	end)
	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Umbra
