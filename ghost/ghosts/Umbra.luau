local Umbra = {Name = "Umbra", Index = 20}

function Umbra.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Umbra requires Traffic")
	local Processor = {Checked = false}
	Processor.Disconnect = Traffic:Receive("Umbra", function(signal, payload)
		if Processor.Checked or signal ~= "FootstepObserved" or type(payload) ~= "table"
			or payload.Confirmed ~= true or (tonumber(payload.Samples) or 0) < 3 then return end
		Processor.Checked = true
		Traffic("RuleOut", {
			Ghost = "Umbra",
			Confidence = 99,
			Reason = "a native material-footstep sound played audibly during a hunt over three samples",
		}):SendTo("Verdict")
	end)
	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Umbra
