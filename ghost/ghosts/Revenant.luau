local Revenant = {Name = "Revenant", Index = 14}

function Revenant.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Revenant requires Traffic")
	local clock = dependencies.Clock or os.clock
	local delay = dependencies.Delay or task and task.delay
	assert(type(delay) == "function", "Revenant requires task.delay")
	local Processor = {
		Resolved = false,
		Hunting = false,
		Generation = 0,
	}

	local function verdict(supported, reason)
		if Processor.Resolved then return end
		Processor.Resolved = true
		Processor.PendingKill = nil
		Processor.Generation += 1
		Traffic(supported and "Support" or "RuleOut", {
			Ghost = "Revenant",
			Confidence = 99,
			Reason = reason,
		}):SendTo("Verdict")
	end

	local function beginProbe(killTime)
		if Processor.PendingKill or Processor.Resolved then return end
		Processor.PendingKill = killTime
		Processor.Generation += 1
		local generation = Processor.Generation
		delay(1.5, function()
			if not Processor.Resolved and Processor.PendingKill == killTime
				and Processor.Generation == generation then
				verdict(not Processor.Hunting, Processor.Hunting
					and "the hunt remained active after a player kill"
					or "the hunt stopped after a player kill")
			end
		end)
	end

	Processor.Disconnect = Traffic:Receive("Revenant", function(signal, payload)
		if Processor.Resolved or type(payload) ~= "table" then return end
		local eventTime = tonumber(payload.Time) or clock()
		if signal == "HuntingState" then
			local hunting = payload.Hunting == true
			local wasHunting = Processor.Hunting
			Processor.Hunting = hunting
			if hunting then
				Processor.LastHuntEnd = nil
			elseif wasHunting then
				Processor.LastHuntEnd = eventTime
				if Processor.PendingKill then
					verdict(true, "the hunt stopped after a player kill")
				end
			end
		elseif signal == "PlayerKilled" then
			if Processor.Hunting then
				beginProbe(eventTime)
			elseif Processor.LastHuntEnd
				and math.abs(eventTime - Processor.LastHuntEnd) <= 1.5 then
				verdict(true, "the hunt ended immediately before the player kill signal arrived")
			end
		end
	end)

	function Processor:Destroy()
		self.Generation += 1
		self.Disconnect()
	end
	return Processor
end

return Revenant
