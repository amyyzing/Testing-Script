local Vex = {Name = "Vex", Index = 22}

function Vex.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Vex requires Traffic")
	local Processor = {Checked = false}
	Processor.Disconnect = Traffic:Receive("Vex", function(signal, payload)
		if Processor.Checked or signal ~= "LidarState" or type(payload) ~= "table"
			or type(payload.Exists) ~= "boolean" then return end
		Processor.Checked = true
		Traffic(payload.Exists and "Support" or "RuleOut", {
			Ghost = "Vex",
			Confidence = 99,
			Reason = payload.Exists
				and "the InvisibleOnLIDAR replicated member exists, regardless of its value"
				or "the InvisibleOnLIDAR replicated member does not exist",
		}):SendTo("Verdict")
	end)
	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Vex
