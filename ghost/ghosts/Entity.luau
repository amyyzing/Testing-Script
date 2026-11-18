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
		if found then Processor.HasSmokeSignature = true
		elseif Processor.HasSmokeSignature then return end
		Traffic(found and "Support" or "Negative", {
			Ghost = "Entity",
			Perk = "Smoke Holder",
			Confidence = found and 99 or 50,
			OverrideNegative = found,
			Reason = found and "prop relocation matched smoke at its departure point"
				or "no matching smoke at the prop's departure point",
		}):SendTo("Verdict")
	end)

	function Processor:Destroy()
		self.Disconnect()
		table.clear(self.Seen)
	end

	return Processor
end

return Entity
