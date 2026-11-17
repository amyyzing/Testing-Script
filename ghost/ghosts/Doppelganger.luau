local Doppelganger = {Name = "Doppelganger", Index = 17}

function Doppelganger.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Doppelganger requires Traffic")
	local processor = {}
	processor.Disconnect = Traffic:Receive("Doppelganger", function(signal, payload)
		if signal ~= "SpiritCandle" or type(payload) ~= "table" then return end
		Traffic("Support", {
			Ghost = "Doppelganger", Confidence = 60,
			Reason = "a candle received SpiritCandle; this ability is shared with Spirit",
		}):SendTo("Verdict")
	end)
	function processor:Destroy() self.Disconnect() end
	return processor
end

return Doppelganger
