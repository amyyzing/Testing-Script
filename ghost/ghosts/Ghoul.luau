local Ghoul = {Name = "Ghoul", Index = 7}

function Ghoul.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Ghoul requires Traffic")
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Ghoul", function(signal, payload)
		if Processor.Resolved or signal ~= "ItemDisabledAwayFromPlayers"
			or type(payload) ~= "table" then return end
		Processor.Resolved = true
		Traffic("RuleOut", {
			Ghost = "Ghoul",
			Confidence = 99,
			Reason = string.format(
				"%s was disabled with no living player within %d studs",
				tostring(payload.ItemName or "an electronic item"),
				tonumber(payload.PlayerRadius) or 15
			),
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Ghoul
