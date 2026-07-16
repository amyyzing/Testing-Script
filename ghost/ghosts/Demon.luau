local Demon = {Name = "Demon", Index = 3}

function Demon.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Demon requires Traffic")
	local Processor = {}

	Processor.Disconnect = Traffic:Receive("Demon", function(signal, payload)
		if signal ~= "CrossAnimation" or type(payload) ~= "table" then return end
		local animated = payload.Animated == true
		Traffic(animated and "Support" or "RuleOut", {
			Ghost = "Demon",
			Confidence = 99,
			Reason = animated and "an activated Cross floated and rotated"
				or "an activated Cross did not float and rotate",
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Demon
