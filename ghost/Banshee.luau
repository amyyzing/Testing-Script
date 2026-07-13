local SOURCE = "https://demonology.fandom.com/wiki/Banshee"

return {
	Name = "Banshee",
	Evidence = {"FreezingTemperatures", "GhostOrb", "Handprints"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 60,
	TTL = 30,
	ObservationKeys = {"BrokenGlassBurst"},
	CreateObserver = function(api)
		local observer = {}

		function observer:OnBrokenGlassBurst(event)
			event = event or {}
			if (tonumber(event.Count) or 0) < 2 then
				return
			end
			api:Detect(
				"Banshee",
				event.Reason
					or "two or more new BrokenGlass models appeared within 2.5 seconds",
				60
			)
			api:Refresh()
		end

		return observer
	end,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "A distinct, subtitle-supported wail occurred at the start of a hunt after Skinwalker was ruled out.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
				Conditions = "Skinwalker may mimic the wail.",
			},
		},
		["Maybe"] = {
			{
				Text = "Glass, windows, bulbs, or cups break unusually often.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "One glass break is weak evidence: any ghost can break glass and a Banshee may break none.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Caveat",
			},
		},
	},
}
