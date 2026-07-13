local SOURCE = "https://demonology.fandom.com/wiki/Demon"

return {
	Name = "Demon",
	Evidence = {"EMFLevel5", "FreezingTemperatures", "Handprints"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 99,
	ObservationKeys = {"CrossBurnMotion"},
	CreateObserver = function(api)
		local observer = {}
		local resolved = {}

		function observer:Reset()
			table.clear(resolved)
		end

		function observer:OnCrossObservation(event)
			event = type(event) == "table" and event or {}
			local observationId = event.ObservationId or "default"
			if resolved[observationId] then
				return
			end
			local rise = tonumber(event.MaxRise) or 0
			local angle = tonumber(event.AccumulatedAngle) or 0
			local travel = tonumber(event.MaxHorizontalTravel) or 0
			if rise >= 0.45 and angle >= math.rad(45) and travel <= 5 then
				resolved[observationId] = true
				self:OnCrossMotion({Outcome = "Matched", Source = event.Source})
		elseif event.Failed == true or (tonumber(event.Age) or 0) >= 4 then
				resolved[observationId] = true
				if not api:GetDetection("Demon") then
					self:OnCrossMotion({Outcome = "Rejected", Source = event.Source})
				end
			end
		end

		function observer:OnCrossMotion(event)
			event = event or {}
			if event.Outcome == "Matched" then
				api:ClearRuleOut("Demon")
				api:Detect(
					"Demon",
					event.Reason
						or "an activated Cross rotated repeatedly and floated upward",
					99
				)
			elseif event.Outcome == "Rejected" then
				api:ClearDetection("Demon")
				api:RuleOut(
					"Demon",
					event.Reason
						or "an activated Cross did not perform the Demon-only animation",
					92
				)
			else
				return
			end
			api:Refresh()
		end

		function observer:Snapshot()
			local count = 0
			for _ in pairs(resolved) do
				count = count + 1
			end
			return {ResolvedCrosses = count}
		end

		return observer
	end,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "A Cross visibly floats or spins while burning; Crosses also work from a larger range.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Weakness",
			},
		},
		["Maybe"] = {
			{
				Text = "It hunts consistently as soon as the 85% average-energy threshold and hunt cooldown permit.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Idk"] = {
			{
				Text = "Frequent hunts alone overlap with Revenant behavior and difficulty modifiers.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Caveat",
			},
		},
	},
}
