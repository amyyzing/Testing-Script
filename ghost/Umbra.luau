local SOURCE = "https://demonology.fandom.com/wiki/Umbra"

return {
	Name = "Umbra",
	Evidence = {"GhostOrb", "Handprints", "LaserProjector"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 95,
	TTL = 60,
	ObservationKeys = {"HumanoidRootPartSound"},
	CreateObserver = function(api)
		local observer = {}
		local checked = false

		function observer:Reset()
			checked = false
		end

		function observer:OnRootSoundScan(event)
			event = event or {}
			if checked or type(event.HasOtherSound) ~= "boolean" then
				return
			end
			checked = true
			if event.HasOtherSound then
				api:ClearDetection("Umbra")
				api:RuleOut(
					"Umbra",
					event.Reason
						or "HumanoidRootPart contained a Sound other than Hunting on the immediate check",
					99
				)
			else
				api:ClearRuleOut("Umbra")
				api:Detect(
					"Umbra",
					event.Reason
						or "HumanoidRootPart contained no Sound other than Hunting on the immediate check",
					95
				)
			end
			api:Refresh()
		end

		function observer:Snapshot()
			return {Checked = checked}
		end

		return observer
	end,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "After Skinwalker is excluded, hunt footsteps are completely silent and movement slows in lit rooms.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Maybe"] = {
			{
				Text = "Either silent hunt footsteps or a controlled lit-room slowdown was observed.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "Footsteps were merely difficult to hear over other sounds.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Caveat",
			},
		},
	},
}
