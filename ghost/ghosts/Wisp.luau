local Wisp = {Name = "Wisp", Index = 24}

function Wisp.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Wisp requires Traffic")
	local Processor = {FavouriteHunts = 0, RuledOut = false}

	local function verdict(signal, confidence, perk, reason)
		if signal == "RuleOut" then Processor.RuledOut = true end
		Traffic(signal, {
			Ghost = "Wisp",
			Confidence = confidence,
			Perk = perk,
			Reason = reason,
		}):SendTo("Verdict")
	end

	Processor.Disconnect = Traffic:Receive("Wisp", function(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if Processor.RuledOut then return end
		if signal == "HolyOilCollidable" then
			if type(payload.CanCollide) ~= "boolean" then return end
			if payload.CanCollide then
				verdict("RuleOut", 99, "Passes through Holy Oil", "burning Holy Oil's GhostWall is collidable")
			else
				verdict("Support", 99, "Passes through Holy Oil", "burning Holy Oil's GhostWall is non-collidable")
			end
		elseif signal == "FavouriteHuntRoom" then
			if payload.InFavourite == false then
				verdict("RuleOut", 99, "Hunts from favourite room", "the ghost started a hunt outside its favourite room")
			elseif payload.InFavourite == true and Processor.FavouriteHunts < 9 then
				Processor.FavouriteHunts += 1
				local count = Processor.FavouriteHunts
				verdict("Support", math.min(95, 5 + count * 10), "Hunts from favourite room",
					"the ghost started a hunt in its favourite room (" .. count
						.. (count == 1 and " time)" or " times)"))
			end
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Wisp
