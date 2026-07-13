local SOURCE = "https://demonology.fandom.com/wiki/Phantom"

local MIMIC_REASON = "Mimicry mode: Skinwalker can copy the observed Phantom blinking and invisible-speed trait"
local EXPECTED_SPEED_RATIO = 13.5 / 11
local MATCH_TOLERANCE = 0.05
local CONTRADICTION_MAX_RATIO = 1.08
local SETTLE_DELAY = 0.095

local function median(values)
	if #values == 0 then
		return nil
	end
	local copy = {}
	for index, value in ipairs(values) do
		copy[index] = value
	end
	table.sort(copy)
	local middle = math.floor((#copy + 1) / 2)
	if #copy % 2 == 1 then
		return copy[middle]
	end
	return (copy[middle] + copy[middle + 1]) / 2
end

local function normalizeSamples(rawSamples, sampleInterval)
	local samples = {}
	local fallbackInterval = tonumber(sampleInterval) or 0.1
	for index, sample in ipairs(type(rawSamples) == "table" and rawSamples or {}) do
		if type(sample) == "table"
			and sample.Hunting ~= false
			and type(sample.Invisible) == "boolean" then
			local speed = tonumber(
				sample.GhostWalkSpeed or sample.Speed or sample.WalkSpeed
			)
			local time = tonumber(sample.Time or sample.Timestamp)
				or (index - 1) * fallbackInterval
			if speed and speed > 0 then
				table.insert(samples, {
					Time = time,
					Speed = speed,
					Invisible = sample.Invisible,
				})
			end
		end
	end
	return samples
end

local function settledPhaseSpeed(run)
	local speeds = {}
	for _, sample in ipairs(run and run.Samples or {}) do
		-- Transparency and WalkSpeed can replicate on separate frames.  The
		-- phase-edge sample is deliberately excluded from the ratio.
		if sample.Time >= run.StartTime + SETTLE_DELAY then
			table.insert(speeds, sample.Speed)
		end
	end
	if #speeds < 2 then
		return nil
	end
	return median(speeds)
end

local function analyzeTransparencySamples(rawSamples, sampleInterval)
	local samples = normalizeSamples(rawSamples, sampleInterval)
	if #samples < 4 then
		return {
			Qualified = 0,
			Matched = 0,
			Contradictory = 0,
		}
	end

	local runs = {}
	for _, sample in ipairs(samples) do
		local run = runs[#runs]
		if not run or run.Invisible ~= sample.Invisible then
			run = {
				Invisible = sample.Invisible,
				StartTime = sample.Time,
				Samples = {},
			}
			table.insert(runs, run)
		end
		table.insert(run.Samples, sample)
	end

	local result = {
		Qualified = 0,
		Matched = 0,
		Contradictory = 0,
		VisibleSpeed = nil,
		InvisibleSpeed = nil,
		Ratio = nil,
	}
	for index, invisibleRun in ipairs(runs) do
		if not invisibleRun.Invisible then
			continue
		end
		local invisibleSpeed = settledPhaseSpeed(invisibleRun)
		local adjacentVisibleSpeeds = {}
		for _, adjacentIndex in ipairs({index - 1, index + 1}) do
			local visibleRun = runs[adjacentIndex]
			if visibleRun and not visibleRun.Invisible then
				local visibleSpeed = settledPhaseSpeed(visibleRun)
				if visibleSpeed then
					table.insert(adjacentVisibleSpeeds, visibleSpeed)
				end
			end
		end
		local visibleSpeed = median(adjacentVisibleSpeeds)
		if not visibleSpeed or not invisibleSpeed then
			continue
		end

		result.Qualified = result.Qualified + 1
		local ratio = invisibleSpeed / visibleSpeed
		if math.abs(ratio - EXPECTED_SPEED_RATIO) <= MATCH_TOLERANCE then
			result.Matched = result.Matched + 1
			result.VisibleSpeed = visibleSpeed
			result.InvisibleSpeed = invisibleSpeed
			result.Ratio = ratio
		elseif ratio <= CONTRADICTION_MAX_RATIO then
			result.Contradictory = result.Contradictory + 1
		end
	end
	return result
end

local function shallowCopy(source)
	local result = {}
	if type(source) == "table" then
		for key, value in pairs(source) do
			result[key] = value
		end
	end
	return result
end

local function createObserver(api)
	local state = {
		Mode = api:Mode(),
		MimicrySkinwalkerClue = false,
		PreviousSkinwalkerDetection = nil,
		LastOutcome = nil,
		LastReason = nil,
		LastConfidence = nil,
		PatternHunts = 0,
		NoPatternHunts = 0,
		PatternRecordedThisHunt = false,
		MatchedCyclesThisHunt = 0,
		QualifiedCyclesThisHunt = 0,
		ContradictoryCyclesThisHunt = 0,
		RawHuntClosed = false,
	}
	local observer = {}

	function observer:Reset(options)
		state.LastOutcome = nil
		state.LastReason = nil
		state.LastConfidence = nil
		local preserveFindings = type(options) == "table"
			and options.PreserveFindings == true
		if not preserveFindings then
			state.MimicrySkinwalkerClue = false
			state.PreviousSkinwalkerDetection = nil
			state.PatternHunts = 0
			state.NoPatternHunts = 0
		end
		state.PatternRecordedThisHunt = false
		state.MatchedCyclesThisHunt = 0
		state.QualifiedCyclesThisHunt = 0
		state.ContradictoryCyclesThisHunt = 0
		state.RawHuntClosed = false
	end

	local function beginRawHuntIfNeeded(event)
		if event.HuntStarted == true or state.RawHuntClosed then
			state.PatternRecordedThisHunt = false
			state.MatchedCyclesThisHunt = 0
			state.QualifiedCyclesThisHunt = 0
			state.ContradictoryCyclesThisHunt = 0
			state.RawHuntClosed = false
		end
	end

	function observer:OnTransparencyPattern(event)
		if type(event) ~= "table" then
			return
		end
		local outcome = event.Outcome
		local confidence = tonumber(event.Confidence)
		state.LastOutcome = outcome
		state.LastReason = event.Reason
		state.LastConfidence = confidence

		if outcome == "Matched" then
			confidence = confidence or 95
			local previousSkinwalker = api:GetDetection("Skinwalker")
			local previousSkinwalkerConfidence = previousSkinwalker
				and tonumber(previousSkinwalker.Confidence)
				or 0
			local previousSkinwalkerReason = previousSkinwalker
				and previousSkinwalker.Reason

			api:ClearRuleOut("Phantom")
			api:Detect("Phantom", event.Reason, confidence, event.Source)

			local mode = api:Mode() or state.Mode
			state.Mode = mode
			if mode == "Mimicry" and not api:IsRuledOut("Skinwalker") then
				if previousSkinwalker
					and previousSkinwalkerReason ~= MIMIC_REASON
					and confidence > previousSkinwalkerConfidence
					and not state.PreviousSkinwalkerDetection then
					state.PreviousSkinwalkerDetection = shallowCopy(previousSkinwalker)
				end
				if not previousSkinwalker
					or previousSkinwalkerReason == MIMIC_REASON
					or confidence > previousSkinwalkerConfidence then
					api:Detect("Skinwalker", MIMIC_REASON, confidence, event.Source)
				end
				local mimicDetection = api:GetDetection("Skinwalker")
				state.MimicrySkinwalkerClue = mimicDetection ~= nil
					and mimicDetection.Reason == MIMIC_REASON
			end
			api:Refresh()
		elseif outcome == "Contradicted" then
			api:ClearDetection("Phantom")
			api:RuleOut("Phantom", event.Reason, confidence or 90)
			api:Refresh()
		end
	end

	-- Raw hook: classifies settled visible/invisible phase runs.  It owns the
	-- ratio, replication-edge exclusion, confidence escalation, and repeated
	-- completed-hunt negative.  OnTransparencyPattern remains the compatibility
	-- hook for hosts that still classify samples themselves.
	function observer:OnTransparencySpeedSamples(event)
		if type(event) ~= "table" then
			return
		end
		beginRawHuntIfNeeded(event)

		local result = analyzeTransparencySamples(
			event.Samples,
			event.SampleInterval
		)
		state.QualifiedCyclesThisHunt = result.Qualified
		state.MatchedCyclesThisHunt = math.max(
			state.MatchedCyclesThisHunt,
			result.Matched
		)
		state.ContradictoryCyclesThisHunt = result.Contradictory

		if result.Matched >= 1 then
			if not state.PatternRecordedThisHunt then
				state.PatternRecordedThisHunt = true
				state.PatternHunts = state.PatternHunts + 1
			end
			state.NoPatternHunts = 0
			local confidence = (
				state.MatchedCyclesThisHunt >= 2
				or state.PatternHunts >= 2
			) and 99 or 95
			self:OnTransparencyPattern({
				Outcome = "Matched",
				Reason = event.MatchReason
					or "settled Transparency 0/1 hunt samples showed the Phantom invisible-speed ratio ("
						.. string.format("%.2f", result.VisibleSpeed)
						.. " visible, "
						.. string.format("%.2f", result.InvisibleSpeed)
						.. " invisible, "
						.. string.format("%.3fx", result.Ratio)
						.. ")",
				Confidence = confidence,
				Source = event.Source,
			})
		elseif (event.HuntEnded == true or event.Completed == true)
			and result.Qualified >= 2
			and result.Contradictory == result.Qualified then
			state.NoPatternHunts = state.NoPatternHunts + 1
			if state.NoPatternHunts >= 2 and state.PatternHunts == 0 then
				self:OnTransparencyPattern({
					Outcome = "Contradicted",
					Reason = event.ContradictionReason
						or "two completed hunts had repeated settled Transparency 0/1 speed pairs with no invisible-linked WalkSpeed increase",
					Confidence = 90,
					Source = event.Source,
				})
			end
		end

		if event.HuntEnded == true or event.Completed == true then
			state.RawHuntClosed = true
		end
	end

	function observer:OnModeChanged(mode)
		state.Mode = mode
		if mode ~= "Normal" then
			return
		end

		local skinwalkerDetection = api:GetDetection("Skinwalker")
		if skinwalkerDetection
			and skinwalkerDetection.Reason == MIMIC_REASON then
			if state.PreviousSkinwalkerDetection then
				api:SetDetection(
					"Skinwalker",
					shallowCopy(state.PreviousSkinwalkerDetection)
				)
			else
				api:ClearDetection("Skinwalker")
			end
		end
		state.MimicrySkinwalkerClue = false
		state.PreviousSkinwalkerDetection = nil
		api:Refresh()
	end

	observer.SetMode = observer.OnModeChanged

	function observer:GetState()
		return {
			Mode = state.Mode,
			MimicrySkinwalkerClue = state.MimicrySkinwalkerClue,
			PreviousSkinwalkerDetection = state.PreviousSkinwalkerDetection
				and shallowCopy(state.PreviousSkinwalkerDetection)
				or nil,
			LastOutcome = state.LastOutcome,
			LastReason = state.LastReason,
			LastConfidence = state.LastConfidence,
			PatternHunts = state.PatternHunts,
			NoPatternHunts = state.NoPatternHunts,
			PatternRecordedThisHunt = state.PatternRecordedThisHunt,
			MatchedCyclesThisHunt = state.MatchedCyclesThisHunt,
			QualifiedCyclesThisHunt = state.QualifiedCyclesThisHunt,
			ContradictoryCyclesThisHunt = state.ContradictoryCyclesThisHunt,
			RawHuntClosed = state.RawHuntClosed,
		}
	end

	observer.Snapshot = observer.GetState
	return observer
end

return {
	Name = "Phantom",
	Evidence = {"EMFLevel5", "GhostOrb", "Handprints"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 99,
	TTL = 30,
	ObservationKeys = {"TransparencySpeedRatio"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "Within the same hunt, settled Transparency=1 WalkSpeed is about 13.5/11 times the settled Transparency=0 WalkSpeed.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Trait",
				Conditions = "Transparency is binary: 0 is visible and 1 is invisible. Retain Skinwalker as an equal possibility in Mimicry mode.",
			},
		},
		["Maybe"] = {
			{
				Text = "One settled visible/invisible speed pair shows the invisible phase clearly faster than the visible phase.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "Ignore the first replication sample after Transparency changes; compare settled samples from both binary phases.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Caveat",
			},
		},
	},
}
