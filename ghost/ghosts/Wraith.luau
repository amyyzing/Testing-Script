local Wraith = {Name = "Wraith", Index = 25}

function Wraith.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Wraith requires Traffic")
	local Processor = {Resolved = false}

	local function verdict(signal, reason)
		if Processor.RuledOut or Processor.Resolved and signal ~= "RuleOut" then return end
		if signal == "RuleOut" then Processor.RuledOut = true end
		Processor.Resolved = true
		Traffic(signal, {
			Ghost = "Wraith",
			Perk = "Undisturbed salt",
			Observation = signal == "Support" and "Salt undisturbed" or "Salt disturbed",
			Confidence = 99,
			Reason = reason,
		}):SendTo("Verdict")
	end

	Processor.Disconnect = Traffic:Receive("Wraith", function(signal, payload)
		if signal ~= "SaltStateAfterHit"
			or type(payload) ~= "table" then return end
		if payload.State == "disturbed" then
			verdict("RuleOut", "a directly observed salt hit produced disturbed salt")
		elseif payload.State == "undisturbed" and payload.GraceComplete == true
			and payload.HuntingAtHit == true then
			verdict("Support",
				"a hunting ghost crossed mature salt and it remained undisturbed")
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Wraith
