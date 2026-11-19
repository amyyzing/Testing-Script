return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "model-traits requires Traffic")
	local Ghost = assert(dependencies.Ghost, "model-traits requires Ghost")
	local gender = Ghost:GetAttribute("Sex") or Ghost:GetAttribute("Gender")
	local visualModel = Ghost:GetAttribute("VisualModel")
	local Tracker = {
		Kind = "active",
		Running = true,
		Gender = gender,
		VisualModel = visualModel,
		Connections = {},
	}
	if gender == "Male" then
		Traffic("ModelGender", {
			Gender = gender,
			VisualModel = visualModel,
		}):SendTo("Keres", "Siren")
	end
	local function watch(attribute, signal, target)
		local function changed()
			if not Tracker.Running then return end
			local value = Ghost:GetAttribute(attribute)
			Traffic(signal, {Exists = value ~= nil, Value = value}):SendTo(target)
		end
		if Ghost.GetAttributeChangedSignal then
			table.insert(Tracker.Connections, Ghost:GetAttributeChangedSignal(attribute):Connect(changed))
		end
		changed()
	end
	watch("Headless", "HeadlessState", "Dullahan")
	watch("CantDisableElectronics", "ElectronicsImmunityState", "Ghoul")
	function Tracker:Destroy()
		self.Running = false
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
	end
	return Tracker
end
