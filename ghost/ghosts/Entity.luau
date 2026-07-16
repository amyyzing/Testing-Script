local Entity = {Name = "Entity", Index = 6}

function Entity.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Entity requires Traffic")
	local Processor = {Seen = {}}

	Processor.Disconnect = Traffic:Receive("Entity", function(signal, payload)
		if signal ~= "SmokeHolderResult" or type(payload) ~= "table" then return end
		local id = payload.EventId
		if id and Processor.Seen[id] then return end
		if id then Processor.Seen[id] = true end
		local found = payload.Found == true
		Traffic(found and "Support" or "Negative", {
			Ghost = "Entity",
			Confidence = found and 99 or 50,
			Reason = found and "a teleported object coincided with a Smoke Holder"
				or "a teleported object had no Smoke Holder",
		}):SendTo("Verdict")
	end)

	function Processor:Destroy()
		self.Disconnect()
		table.clear(self.Seen)
	end

	return Processor
end

return Entity
