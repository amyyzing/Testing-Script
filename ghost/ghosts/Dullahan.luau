local Dullahan = {Name = "Dullahan", Index = 4}

function Dullahan.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Dullahan requires Traffic")
	local Processor = {}

	Processor.Disconnect = Traffic:Receive("Dullahan", function(signal, payload)
		if signal ~= "SevenPairResult" or type(payload) ~= "table" then return end
		local distinct = tonumber(payload.DistinctPairs) or 0
		local supported = distinct >= 3
		Traffic(supported and "Support" or "RuleOut", {
			Ghost = "Dullahan",
			Confidence = 99,
			Reason = supported
				and "seven hunting pairs contained at least three distinct speed pairs"
				or "seven hunting pairs contained fewer than three distinct speed pairs",
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Dullahan
