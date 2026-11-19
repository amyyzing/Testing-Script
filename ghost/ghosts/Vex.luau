local Vex = {Name = "Vex", Index = 22}

function Vex.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Vex requires Traffic")
	local Processor = {}
	Processor.Disconnect = Traffic:Receive("Vex", function(signal, payload)
		if Processor.RuledOut or signal ~= "LidarState" or type(payload) ~= "table"
			or type(payload.Exists) ~= "boolean" then return end
		if payload.Exists ~= true or type(payload.Value) ~= "boolean" then return end
		if payload.Value and Processor.Supported then return end
		Processor.Supported = payload.Value
		Processor.RuledOut = not payload.Value
		Traffic(payload.Value and "Support" or "RuleOut", {
			Ghost = "Vex",
			Perk = "Invisible on LIDAR",
			Observation = payload.Value and "Invisible on LIDAR" or "Visible on LIDAR",
			Confidence = 99,
			Reason = "the replicated InvisibleOnLIDAR flag is " .. tostring(payload.Value),
		}):SendTo("Verdict")
	end)
	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Vex
