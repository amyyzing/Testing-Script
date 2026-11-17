local Leviathan = {Name = "Leviathan", Index = 9}

function Leviathan.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Leviathan requires Traffic")
	local Processor = {Resolved = false}

	Processor.Disconnect = Traffic:Receive("Leviathan", function(signal, payload)
		if Processor.Resolved or type(payload) ~= "table" then return end
		if signal == "NativeGlitch" and type(payload.Token) == "number" and payload.Token > 0 then
			Processor.Resolved = true
			Traffic("Support", {
				Ghost = "Leviathan", Confidence = 99,
				Reason = "an electronic item received the native LeviathanGlitch attribute",
			}):SendTo("Verdict")
			return
		end
		if signal ~= "FlickerArrayResult" or (tonumber(payload.Count) or 0) < 7
			or (tonumber(payload.Duration) or math.huge)
				>= (tonumber(payload.Window) or 2) then return end
		Traffic("Support", {
			Ghost = "Leviathan",
			Confidence = 35,
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
