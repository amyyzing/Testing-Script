local Ghoul = {Name = "Ghoul", Index = 7}

function Ghoul.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Ghoul requires Traffic")
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Ghoul", function(signal, payload)
		if Processor.Resolved or type(payload) ~= "table" then return end
		if signal == "ElectronicsImmunityState" then
			if payload.Value ~= true or Processor.FlagReported then return end
			Processor.FlagReported = true
			Traffic("Support", {
				Ghost = "Ghoul", Perk = "Electronics immunity",
				Observation = "Electronics interference disabled", Confidence = 99,
				Reason = "the native ghost has CantDisableElectronics enabled",
			}):SendTo("Verdict")
			return
		end
		if signal ~= "ItemDisabledAwayFromPlayers" then return end
		Processor.Resolved = true
		Traffic("RuleOut", {
			Ghost = "Ghoul",
			Perk = "Electronics disabled at a distance",
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
