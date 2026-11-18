local Banshee = {Name = "Banshee", Index = 2}

function Banshee.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Banshee requires Traffic")
	local processor = {}
	processor.Disconnect = Traffic:Receive("Banshee", function(signal, payload)
		if signal ~= "GlassBurst" or type(payload) ~= "table"
			or (tonumber(payload.Count) or 0) < 2 then return end
		Traffic("Support", {
			Ghost = "Banshee", Confidence = 65,
			Perk = "Glass burst", Observation = "Multiple glass breaks",
			Reason = "multiple new broken-glass models appeared within five seconds; supporting rather than unique evidence",
		}):SendTo("Verdict")
	end)
	function processor:Destroy() self.Disconnect() end
	return processor
end

return Banshee
