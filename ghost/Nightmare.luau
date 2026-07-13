local SOURCE = "https://demonology.fandom.com/wiki/Nightmare"

return {
	Name = "Nightmare",
	Evidence = {"EMFLevel5", "GhostOrb", "SpiritBox"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	ObservationKeys = {},
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "After Skinwalker is excluded, corroboration proves an auditory cue had no matching real interaction.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Maybe"] = {
			{
				Text = "It hunts more often while its current room is dark.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "An unexplained noise or general activity in darkness is not enough by itself.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Caveat",
			},
		},
	},
}
