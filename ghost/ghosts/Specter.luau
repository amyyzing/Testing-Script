local Specter = {Name = "Specter", Index = 18}

function Specter.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Specter requires Traffic")
	local Processor = {RuledOut = false}

	Processor.Disconnect = Traffic:Receive("Specter", function(signal, payload)
		if Processor.RuledOut or signal ~= "SpecterTrial" or type(payload) ~= "table"
			or payload.Qualified ~= true or payload.Completed ~= true
			or payload.FavouriteRoomUnchanged ~= true
			or (tonumber(payload.ArmedSeconds) or 0) < 5 then return end
		if payload.Outcome == "Departure" then
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
