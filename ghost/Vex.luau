local SOURCE = "https://demonology.fandom.com/wiki/Vex"

return {
	Name = "Vex",
	Evidence = {"FreezingTemperatures", "GhostOrb", "Wither"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 95,
	TTL = 2,
	ObservationKeys = {"InvisibleOnLIDAR"},
	CreateObserver = function(api)
		local observer = {}

		function observer:OnLidarState(event)
			if not event then
				return
			end
			if event.Invisible == true then
				api:ClearRuleOut("Vex")
				api:ClearDetection("Dybbuk")
				api:Detect(
					"Vex",
					event.Reason
						or "replicated InvisibleOnLIDAR property was true",
					99
				)
			else
				api:ClearDetection("Vex")
				api:RuleOut(
					"Vex",
					event.Reason
						or (event.Invisible == false
							and "replicated InvisibleOnLIDAR property was false"
							or "replicated InvisibleOnLIDAR property was not found"),
					99
				)
			end
			api:Refresh()
		end

		return observer
	end,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "It passes through a wall and repeatedly remains absent from LIDAR while its location is independently known.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Trait",
				Conditions = "Skinwalker may copy wall-walking but is not documented to copy LIDAR invisibility.",
			},
		},
		["Maybe"] = {
			{
				Text = "It visibly walks through a wall, indicating Vex or a mimicking Skinwalker.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Idk"] = {
			{
				Text = "Cutting a corner or missing from one scan without confirmed range is weak evidence.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Caveat",
			},
		},
	},
}
