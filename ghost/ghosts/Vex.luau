local Vex = {Name = "Vex", Index = 22}

function Vex.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Vex requires Traffic")
	local Processor = {Checked = false}
	Processor.Disconnect = Traffic:Receive("Vex", function(signal, payload)
		if Processor.Checked or signal ~= "LidarState" or type(payload) ~= "table"
			or type(payload.Exists) ~= "boolean" then return end
		if payload.Exists ~= true or payload.Value ~= true then return end
		Processor.Checked = true
		Traffic("Support", {
			Ghost = "Vex",
			Confidence = 99,
			Reason = "the replicated InvisibleOnLIDAR flag is true",
		}):SendTo("Verdict")
	end)
	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Vex
