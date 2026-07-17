local Ravager = {Name = "Ravager", Index = 13}

function Ravager.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Ravager requires Traffic")
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Ravager", function(signal, payload)
		if Processor.Resolved or signal ~= "ItemOrbit" or type(payload) ~= "table"
			or payload.Mode ~= "NearPerfect"
			or (tonumber(payload.Count) or 0) < 3 then return end
		Processor.Resolved = true
		Traffic("Support", {
			Ghost = "Ravager",
			Confidence = 99,
			Reason = "at least three item or interactable models followed near-circular paths around the moving hunting ghost",
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Ravager
