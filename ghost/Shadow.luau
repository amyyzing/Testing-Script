local SOURCE = "https://demonology.fandom.com/wiki/Shadow"

return {
	Name = "Shadow",
	Evidence = {"EMFLevel5", "GhostWriting", "LaserProjector"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	ObservationKeys = {},
	Perks = {
		["Pretty Sure"] = {},
		["Maybe"] = {
			{
				Text = "A confirmed ghost room changes temperature only by small decimal steps and stays unusually warm.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
			{
				Text = "A controlled light-on versus light-off comparison shows reduced activity in the lit room.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Weakness",
			},
		},
		["Idk"] = {
			{
				Text = "A quiet ghost or a room that is difficult to locate is only absence-based evidence.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Caveat",
			},
		},
	},
}
