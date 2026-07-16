local Oni = {Name = "Oni", Index = 11}

function Oni.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Oni requires Traffic")
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Oni", function(signal, payload)
		if Processor.Resolved or signal ~= "SpeedFilterResult"
			or type(payload) ~= "table" or payload.Complete ~= true then return end
		Processor.Resolved = true
		local supported = payload.Identical == true and payload.BaseSpeed == 13.5
		Traffic(supported and "Support" or "RuleOut", {
			Ghost = "Oni",
			Confidence = 99,
			Reason = supported
				and string.format(
					"all seven hunting pairs held visible and invisible speed at scaled 13.5 base (%d%%)",
					math.floor((payload.CustomMultiplier or 1) * 100 + 0.5)
				)
				or "seven hunting pairs did not hold visible and invisible speed at scaled 13.5 base",
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Oni
