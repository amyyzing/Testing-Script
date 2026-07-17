local Wisp = {Name = "Wisp", Index = 24}

function Wisp.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Wisp requires Traffic")
	local Processor = {FavouriteHunts = 0, RuledOut = false}

	local function verdict(signal, confidence, reason)
		if signal == "RuleOut" then Processor.RuledOut = true end
		Traffic(signal, {
			Ghost = "Wisp",
			Confidence = confidence,
			Reason = reason,
		}):SendTo("Verdict")
	end

	Processor.Disconnect = Traffic:Receive("Wisp", function(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if Processor.RuledOut then return end
		if signal == "HolyOilCollidable" then
			if type(payload.CanCollide) ~= "boolean" then return end
			Processor.CanCollide = payload.CanCollide == true
			if Processor.CanCollide then
				verdict("RuleOut", 99, "burning Holy Oil's GhostWall remained collidable")
			else
				verdict("Support", 99, "burning Holy Oil's GhostWall became non-collidable")
			end
		elseif signal == "FavouriteHuntRoom" then
			if payload.InFavourite == false then
				verdict("RuleOut", 99, "the ghost started a hunt outside its favourite room")
			elseif payload.InFavourite == true and Processor.FavouriteHunts < 9 then
				Processor.FavouriteHunts += 1
				local count = Processor.FavouriteHunts
				verdict("Support", math.min(95, 5 + count * 10),
					"the ghost started a hunt in its favourite room (" .. count
						.. (count == 1 and " time)" or " times)"))
			end
		elseif signal == "HolyOilFireResult" then
			if payload.CaughtFire == false then
				verdict("RuleOut", 99, "the ghost passed through burning Holy Oil without catching fire")
			elseif payload.CaughtFire == true and Processor.CanCollide ~= true then
				verdict("Support", 99, "the ghost caught fire after passing through burning Holy Oil")
			end
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Wisp
