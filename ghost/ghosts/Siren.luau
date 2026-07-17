local Siren = {Name = "Siren", Index = 16}

function Siren.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Siren requires Traffic")
	local Processor = {}

	local function verdict(signal, confidence, reason)
		Traffic(signal, {
			Ghost = "Siren",
			Confidence = confidence,
			Reason = reason,
		}):SendTo("Verdict")
	end

	Processor.Disconnect = Traffic:Receive("Siren", function(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "Humming" and payload.Response == "- HUMMING -" then
			verdict("Support", 99, "Spirit Box returned - HUMMING -")
		elseif signal == "ModelGender" then
			if payload.Gender == "Female" then
				verdict("Support", 25, "the ghost uses a female VisualModel")
			elseif payload.Gender == "Male" then
				verdict("RuleOut", 99, "the ghost uses a male VisualModel")
			end
		elseif signal == "LOSSpeedResult" then
			if payload.Slowed == true then
				verdict("Support", 99, "a hunting player entered the Siren's 0.8x walk or sprint speed state")
			elseif payload.Completed == true and payload.Slowed == false then
				verdict("RuleOut", 99, "a hunting line-of-sight trial stayed at the learned walk and sprint speeds")
			end
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Siren
