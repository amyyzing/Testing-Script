local Specter = {Name = "Specter", Index = 18}

function Specter.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Specter requires Traffic")
	local Processor = {RuledOut = false, ResidenceConfidence = 0}

	Processor.Disconnect = Traffic:Receive("Specter", function(signal, payload)
		if Processor.RuledOut or signal ~= "SpecterTrial" or type(payload) ~= "table"
			or payload.Qualified ~= true or payload.Completed ~= true
			or payload.FavouriteRoomUnchanged ~= true
			or (tonumber(payload.ArmedSeconds) or 0) < 5 then return end
		if payload.Outcome == "Residence" then
			if payload.Hunting ~= false or payload.Room ~= payload.FavouriteRoom then return end
			local elapsed = tonumber(payload.ArmedSeconds) or 0
			local confidence = elapsed >= 90 and 60 or elapsed >= 30 and 35 or 0
			if confidence <= Processor.ResidenceConfidence then return end
			Processor.ResidenceConfidence = confidence
			Traffic("Support", {
				Ghost = "Specter", Confidence = confidence,
				Perk = "Stays in favourite room", Observation = "Stayed in favourite room",
				Certainty = confidence >= 50 and "Medium" or "Low",
				Reason = "continued non-hunting residence is a limited lead, not unique identification",
			}):SendTo("Verdict")
		elseif payload.Outcome == "Departure" then
			Processor.RuledOut = true
			Traffic("RuleOut", {
				Ghost = "Specter",
				Perk = "Stays in favourite room",
				Observation = "Left favourite room",
				Confidence = 95,
				Reason = "the non-hunting ghost left its unchanged favourite room after the five-second arm point",
			}):SendTo("Verdict")
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Specter
