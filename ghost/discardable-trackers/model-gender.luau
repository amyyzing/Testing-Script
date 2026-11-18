return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "model-gender requires Traffic")
	local Ghost = assert(dependencies.Ghost, "model-gender requires Ghost")
	local gender = Ghost:GetAttribute("Sex") or Ghost:GetAttribute("Gender")
	local visualModel = Ghost:GetAttribute("VisualModel")
	local Tracker = {
		Kind = "discardable",
		Running = false,
		Gender = gender,
		VisualModel = visualModel,
	}
	if gender == "Male" then
		Traffic("ModelGender", {
			Gender = gender,
			VisualModel = visualModel,
		}):SendTo("Keres", "Siren")
	end
	function Tracker:Destroy() end
	return Tracker
end
