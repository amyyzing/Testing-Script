local Ravager = {Name = "Ravager", Index = 13}

function Ravager.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Ravager requires Traffic")
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Ravager", function(signal, payload)
		if Processor.Resolved or signal ~= "ItemOrbit" or type(payload) ~= "table"
			or payload.Mode ~= "XZVortex"
			or (tonumber(payload.Count) or 0) < 3 then return end
		Processor.Resolved = true
		Traffic("Support", {
			Ghost = "Ravager",
			Confidence = 99,
			Reason = "at least three item or interactable models sustained XZ rotation around the moving hunting ghost",
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Ravager
