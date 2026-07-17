local FEMALE_MODELS = {Abaddon = true, Leech = true, Rattle = true, Watcher = true}

return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "model-gender requires Traffic")
	local Ghost = assert(dependencies.Ghost, "model-gender requires Ghost")
	local gender = Ghost:GetAttribute("Sex") or Ghost:GetAttribute("Gender")
	local visualModel = Ghost:GetAttribute("VisualModel")
	if gender ~= "Female" and gender ~= "Male" then
		gender = type(visualModel) == "string" and visualModel ~= ""
			and (FEMALE_MODELS[visualModel] and "Female" or "Male") or nil
	end
	local Tracker = {
		Kind = "discardable",
		Running = false,
		Gender = gender,
		VisualModel = visualModel,
	}
	if gender then
		Traffic("ModelGender", {
			Gender = gender,
			VisualModel = visualModel,
		}):SendTo("Keres", "Siren")
	end
	function Tracker:Destroy() end
	return Tracker
end
