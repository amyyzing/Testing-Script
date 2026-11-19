local Dullahan = {Name = "Dullahan", Index = 4}

function Dullahan.new(dependencies)
	local Traffic = assert(dependencies.Traffic, "Dullahan requires Traffic")
	local processor = {}

	processor.Disconnect = Traffic:Receive("Dullahan", function(signal, payload)
		if signal == "HeadlessState" and type(payload) == "table" then
			if payload.Exists == true and payload.Value == true and not processor.HeadlessObserved then
				processor.HeadlessObserved = true
				Traffic("Support", {
					Ghost = "Dullahan", Perk = "Headless ghost",
					Observation = "Headless ghost", Confidence = 99,
					Reason = "the ghost model's native Headless attribute is true",
				}):SendTo("Verdict")
			end
			return
		end
	end)

	function processor:Destroy() self.Disconnect() end
	return processor
end

return Dullahan
