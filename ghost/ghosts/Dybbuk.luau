local Dybbuk = {Name = "Dybbuk", Index = 5}

function Dybbuk.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Dybbuk requires Traffic")
	local processor = {}
	processor.Disconnect = Traffic:Receive("Dybbuk", function(signal, payload)
		if processor.Resolved or signal ~= "MusicBoxStun" or type(payload) ~= "table"
			or payload.Qualified ~= true then return end
		processor.Resolved = true
		Traffic("Support", {
			Ghost = "Dybbuk", Perk = "Music Box stun", Confidence = 95,
			Reason = "first Music Box play caused a deep speed drop and a three-second recovery",
		}):SendTo("Verdict")
	end)
	function processor:Destroy() self.Disconnect() end
	return processor
end

return Dybbuk
