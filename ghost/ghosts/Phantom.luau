local Phantom = {Name = "Phantom", Index = 12}

function Phantom.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Phantom requires Traffic")
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Phantom", function(signal, payload)
		if Processor.Resolved or signal ~= "SpeedFilterResult"
			or type(payload) ~= "table" or payload.Complete ~= true
			or payload.HasBothStates ~= true then return end
		Processor.Resolved = true
		local supported = payload.PhantomPattern == true
		Traffic(supported and "Support" or "RuleOut", {
			Ghost = "Phantom",
			Confidence = 99,
			Reason = supported
				and string.format(
					"seven hunting pairs repeated scaled visible 11 / invisible 13.5 speed (%d%%)",
					math.floor((payload.PhantomCustomMultiplier or 1) * 100 + 0.5)
				)
				or "seven hunting pairs did not repeat scaled visible 11 / invisible 13.5 speed",
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Phantom
