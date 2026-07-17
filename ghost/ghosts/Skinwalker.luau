local Skinwalker = {Name = "Skinwalker", Index = 17}

function Skinwalker.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Skinwalker requires Traffic")
	local Processor = {}

	local function verdict(signal, reason)
		Traffic(signal, {
			Ghost = "Skinwalker",
			Confidence = 99,
			Reason = reason,
		}):SendTo("Verdict")
	end

	Processor.Disconnect = Traffic:Receive("Skinwalker", function(signal, payload)
		if signal ~= "HolyOilFireResult" or type(payload) ~= "table" then return end
		if payload.CaughtFire == true then
			verdict("RuleOut", "the ghost caught fire after passing through burning Holy Oil")
		elseif payload.CaughtFire == false then
			verdict("Support", "the ghost passed through burning Holy Oil without catching fire")
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Skinwalker
