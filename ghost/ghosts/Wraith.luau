local Wraith = {Name = "Wraith", Index = 25}

function Wraith.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Wraith requires Traffic")
	local Processor = {Resolved = false}

	local function verdict(signal, reason)
		if Processor.Resolved then return end
		Processor.Resolved = true
		Traffic(signal, {
			Ghost = "Wraith",
			Confidence = 99,
			Reason = reason,
		}):SendTo("Verdict")
	end

	Processor.Disconnect = Traffic:Receive("Wraith", function(signal, payload)
		if Processor.Resolved or signal ~= "SaltStateAfterHit"
			or type(payload) ~= "table" then return end
		if payload.State == "disturbed" then
			verdict("RuleOut", "a directly observed salt hit produced disturbed salt")
		elseif payload.State == "undisturbed" and payload.GraceComplete == true then
			verdict("Support",
				"a directly observed salt hit remained undisturbed after the four-second creation grace")
		end
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Wraith
