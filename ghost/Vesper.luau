local SOURCE = "https://demonology.fandom.com/wiki/Vesper"

return {
	Name = "Vesper",
	Evidence = {"GhostWriting", "Handprints", "Wither"},
	Source = SOURCE,
	SourceStatus = "wiki-recent-stub",
	ObservationKeys = {},
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "A controlled silent/still test is followed by a sound that immediately causes tracking through a wall.",
				Source = SOURCE,
				Status = "wiki-recent-stub",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Maybe"] = {
			{
				Text = "It repeatedly tracks noisy equipment or hunters through walls.",
				Source = SOURCE,
				Status = "wiki-recent-stub",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "It simply failed to path toward a stationary hunter; this test is easy to misread.",
				Source = SOURCE,
				Status = "wiki-recent-stub",
				Mimickable = false,
				Kind = "Caveat",
			},
		},
	},
}
