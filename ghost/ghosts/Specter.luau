local Specter = {Name = "Specter", Index = 18}

function Specter.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Specter requires Traffic")
	local Processor = {ResidenceCount = 0, Trials = {}, RuledOut = false}

	Processor.Disconnect = Traffic:Receive("Specter", function(signal, payload)
		if signal ~= "SpecterTrial" or type(payload) ~= "table"
			or payload.Qualified ~= true or payload.Completed ~= true
			or payload.FavouriteRoomUnchanged ~= true
			or (tonumber(payload.ArmedSeconds) or 0) < 5 then return end
		local trialId = tostring(payload.TrialId or "default")
		if Processor.Trials[trialId] then return end
		Processor.Trials[trialId] = payload.Outcome
		if payload.Outcome == "Residence" and not Processor.RuledOut then
			Processor.ResidenceCount += 1
			local count = Processor.ResidenceCount
			Traffic("Support", {
				Ghost = "Specter",
				Confidence = count >= 2 and 65 or 35,
				Reason = "the ghost remained stationary in its unchanged favourite room from the five-second arm point until hunt start ("
					.. count .. (count == 1 and " time)" or " times)"),
			}):SendTo("Verdict")
		elseif payload.Outcome == "Departure" then
			Processor.RuledOut = true
			Traffic("RuleOut", {
				Ghost = "Specter",
				Confidence = 95,
				Reason = "the non-hunting ghost left its unchanged favourite room after the five-second arm point",
			}):SendTo("Verdict")
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Specter
