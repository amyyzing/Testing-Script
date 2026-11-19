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
	}
	if gender == "Male" then
		Traffic("ModelGender", {
			Gender = gender,
			VisualModel = visualModel,
		}):SendTo("Keres", "Siren")
	end
	local function headless()
		if not Tracker.Running then return end
		local value = Ghost:GetAttribute("Headless")
		Traffic("HeadlessState", {Exists = value ~= nil, Value = value}):SendTo("Dullahan")
	end
	if Ghost.GetAttributeChangedSignal then
		Tracker.Connection = Ghost:GetAttributeChangedSignal("Headless"):Connect(headless)
	end
	headless()
	function Tracker:Destroy()
		self.Running = false
		if self.Connection then self.Connection:Disconnect() end
	end
	return Tracker
end
