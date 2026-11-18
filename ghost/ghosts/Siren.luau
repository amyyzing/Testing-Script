local Siren = {Name = "Siren", Index = 16}

function Siren.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Siren requires Traffic")
	local Processor = {}

	local function verdict(signal, confidence, perk, reason, observation)
		Traffic(signal, {
			Ghost = "Siren",
			Confidence = confidence,
			Perk = perk,
			Observation = observation,
			Reason = reason,
		}):SendTo("Verdict")
	end

	Processor.Disconnect = Traffic:Receive("Siren", function(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "Humming" and payload.Response == "- HUMMING -" then
			verdict("Support", 99, "Humming", "Spirit Box returned - HUMMING -")
		elseif signal == "ModelGender" then
			if payload.Gender == "Male" then
				verdict("RuleOut", 99, "Female model", "the ghost uses a male VisualModel", "Male model")
			end
		elseif signal == "LOSSpeedResult" then
			if payload.Slowed == true then
				verdict("Support", 35, "Slows players", "a 0.8x slowdown was observed; this also occurs on non-Siren ghosts")
			end
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Siren
