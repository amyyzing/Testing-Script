local Spirit = {Name = "Spirit", Index = 19}

function Spirit.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Spirit requires Traffic")
	local Processor = {}
	Processor.Disconnect = Traffic:Receive("Spirit", function(signal, payload)
		if signal ~= "HolyOilColour" or type(payload) ~= "table" then return end
		if payload.Kind == "Spirit" then
			Traffic("Support", {
				Ghost = "Spirit",
				Confidence = 99,
				Reason = "burning Holy Oil matched the blue Spirit colour sequence",
			}):SendTo("Verdict")
		elseif payload.Kind == "Normal" then
			Traffic("RuleOut", {
				Ghost = "Spirit",
				Confidence = 99,
				Reason = "burning Holy Oil matched the normal orange colour sequence",
			}):SendTo("Verdict")
		end
	end)
	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Spirit
