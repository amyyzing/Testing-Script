local SOURCE = "https://demonology.fandom.com/wiki/Spirit"

local SPIRIT_FIRST = {R = 0.384314, G = 0.541216, B = 1}
local SPIRIT_LAST = {R = 0, G = 0.263333, B = 1}
local NON_SPIRIT_FIRST = {R = 1, G = 0.694118, B = 0.384314}
local NON_SPIRIT_LAST = {R = 1, G = 0.333333, B = 0}

local function close(left, right, tolerance)
	return type(left) == "number"
		and type(right) == "number"
		and math.abs(left - right) <= tolerance
end

local function colorClose(left, right)
	return type(left) == "table"
		and close(tonumber(left.R), right.R, 0.012)
		and close(tonumber(left.G), right.G, 0.012)
		and close(tonumber(left.B), right.B, 0.012)
end

local function sequenceMatches(sequence, firstColor, lastColor)
	return type(sequence) == "table"
		and close(tonumber(sequence.FirstTime), 0, 0.02)
		and close(tonumber(sequence.LastTime), 1, 0.02)
		and colorClose(sequence.First, firstColor)
		and colorClose(sequence.Last, lastColor)
end

return {
	Name = "Spirit",
	Evidence = {"GhostWriting", "Handprints", "SpiritBox"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 99,
	ObservationKeys = {"HolyOilColor"},
	CreateObserver = function(api)
		local observer = {}
		local lastKindByModel = {}

		function observer:Reset()
			table.clear(lastKindByModel)
		end

		function observer:OnHolyOilObservation(event)
			event = type(event) == "table" and event or {}
			local modelKey = event.Model or "default"
			if event.Hunting ~= true or event.Burning ~= true then
				lastKindByModel[modelKey] = nil
				return
			end
			local sequences = event.ColorSequences
			if type(sequences) ~= "table" then
				return
			end
			local spirit = sequenceMatches(sequences.Primary, SPIRIT_FIRST, SPIRIT_LAST)
				and sequenceMatches(sequences.Secondary, SPIRIT_FIRST, SPIRIT_LAST)
			local nonSpirit = sequenceMatches(sequences.Primary, NON_SPIRIT_FIRST, NON_SPIRIT_LAST)
				and sequenceMatches(sequences.Secondary, NON_SPIRIT_FIRST, NON_SPIRIT_LAST)
			local kind = spirit and "Spirit" or (nonSpirit and "NonSpirit" or nil)
			if kind == nil or lastKindByModel[modelKey] == kind then
				return
			end
			lastKindByModel[modelKey] = kind
			self:OnHolyOilColor({Kind = kind, Source = event.Source})
		end

		function observer:OnHolyOilColor(event)
			event = event or {}
			if event.Kind == "Spirit" then
				api:ClearRuleOut("Spirit")
				api:Detect(
					"Spirit",
					event.Reason
						or "burning Holy Oil Primary and Secondary matched the Spirit blue sequence",
					99
				)
			elseif event.Kind == "NonSpirit" then
				api:ClearDetection("Spirit")
				api:RuleOut(
					"Spirit",
					event.Reason
						or "burning Holy Oil Primary and Secondary matched the non-Spirit orange sequence",
					99
				)
			else
				return
			end
			api:Refresh()
		end

		function observer:Snapshot()
			local count = 0
			for _ in pairs(lastKindByModel) do
				count = count + 1
			end
			return {TrackedModels = count}
		end

		return observer
	end,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "After Skinwalker is excluded, a candle, lantern, Summoning Circle, or Holy Oil flame changes blue and remains blue after relighting.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Maybe"] = {
			{
				Text = "One blue flame was observed while Skinwalker remains possible.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Idk"] = {
			{
				Text = "Low or mostly harmless activity is not an identifying trait by itself.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Caveat",
			},
		},
	},
}
