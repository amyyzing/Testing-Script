local Leviathan = {Name = "Leviathan", Index = 9}

function Leviathan.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Leviathan requires Traffic")
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Leviathan", function(signal, payload)
		if Processor.Resolved or signal ~= "FlickerArrayResult"
			or type(payload) ~= "table" or (tonumber(payload.Count) or 0) < 10
			or (tonumber(payload.Duration) or math.huge)
				> (tonumber(payload.Window) or 2.5) then return end
		Processor.Resolved = true
		Traffic("Support", {
			Ghost = "Leviathan",
			Confidence = 99,
			Reason = string.format(
				"%s switched %d times within %.2f seconds",
				tostring(payload.ItemName or "an eligible electronic item"),
				payload.Count,
				payload.Duration
			),
		}):SendTo("Verdict")
	end)

	function Processor:Destroy() self.Disconnect() end
	return Processor
end

return Leviathan
