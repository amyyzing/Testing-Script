local Dybbuk = {Name = "Dybbuk", Index = 5}

function Dybbuk.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Dybbuk requires Traffic")
	local processor = {}
	processor.Disconnect = Traffic:Receive("Dybbuk", function(signal, payload)
		if processor.Resolved or signal ~= "MusicBoxStun" or type(payload) ~= "table"
			or payload.Qualified ~= true then return end
		if payload.Stunned == false and payload.InRange ~= true then return end
		processor.Resolved = true
		local stunned = payload.Stunned ~= false
		Traffic(stunned and "Support" or "RuleOut", {
			Ghost = "Dybbuk", Perk = "Music Box stun", Confidence = 95,
			Observation = stunned and "Music Box stun" or "No Music Box stun",
			Reason = stunned and "first Music Box play caused a deep speed drop and a three-second recovery"
				or "a qualified close-range first play caused no stun",
		}):SendTo("Verdict")
	end)
	function processor:Destroy() self.Disconnect() end
	return processor
end

return Dybbuk
