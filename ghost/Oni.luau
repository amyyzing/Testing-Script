local SOURCE = "https://demonology.fandom.com/wiki/Oni"

local DEFAULT_SPEED_MULTIPLIERS = {0.5, 0.75, 1, 1.25, 1.5, 2}

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

local function standardDeviation(values)
	if #values < 2 then
		return math.huge
	end
	local total = 0
	for _, value in ipairs(values) do
		total = total + value
	end
	local mean = total / #values
	local variance = 0
	for _, value in ipairs(values) do
		variance = variance + (value - mean) ^ 2
	end
	return math.sqrt(variance / #values)
end

local function validMultipliers(input)
	local result = {}
	for _, value in ipairs(type(input) == "table" and input or DEFAULT_SPEED_MULTIPLIERS) do
		local multiplier = tonumber(value)
		if multiplier and multiplier > 0 then
			table.insert(result, multiplier)
		end
	end
	if #result == 0 then
		for _, multiplier in ipairs(DEFAULT_SPEED_MULTIPLIERS) do
			table.insert(result, multiplier)
		end
	end
	return result
end

local function visibleHuntSpeeds(event)
	local values = {}
	local rawSamples = event.Samples or event.Speeds
	local now = tonumber(event.Now or event.Time or event.Timestamp)
	local window = tonumber(event.Window) or 1.4
	for _, sample in ipairs(type(rawSamples) == "table" and rawSamples or {}) do
		if type(sample) == "number" then
			if sample > 0 then
				table.insert(values, sample)
			end
		elseif type(sample) == "table"
			and sample.Hunting ~= false
			and sample.Invisible == false then
			local speed = tonumber(
				sample.GhostWalkSpeed or sample.Speed or sample.WalkSpeed
			)
			local time = tonumber(sample.Time or sample.Timestamp)
			if speed and speed > 0
				and (not now or not time or time >= now - window) then
				table.insert(values, speed)
			end
		end
	end
	return values
end

local function closestBaseMode(mapNormalizedSpeed, baseSpeed, multipliers)
	local bestMultiplier = 1
	local bestBase = mapNormalizedSpeed
	local bestError = math.huge
	for _, multiplier in ipairs(multipliers) do
		local inferredBase = mapNormalizedSpeed / multiplier
		local errorAmount = math.abs(inferredBase - baseSpeed)
		if errorAmount < bestError then
			bestError = errorAmount
			bestMultiplier = multiplier
			bestBase = inferredBase
		end
	end
	return bestError, bestMultiplier, bestBase
end

local function createObserver(api)
	local state = {
		LastOutcome = nil,
		LastReason = nil,
		LastConfidence = nil,
		PatternHunts = 0,
		PatternRecordedThisHunt = false,
		RawHuntClosed = false,
		LastMedian = nil,
		LastStable = nil,
	}
	local observer = {}

	function observer:Reset(options)
		state.LastOutcome = nil
		state.LastReason = nil
		state.LastConfidence = nil
		if type(options) ~= "table" or options.PreserveFindings ~= true then
			state.PatternHunts = 0
		end
		state.PatternRecordedThisHunt = false
		state.RawHuntClosed = false
		state.LastMedian = nil
		state.LastStable = nil
	end

	local function beginRawHuntIfNeeded(event)
		if event.HuntStarted == true or state.RawHuntClosed then
			state.PatternRecordedThisHunt = false
			state.RawHuntClosed = false
		end
	end

	function observer:OnVisibleHuntSpeed(event)
		if type(event) ~= "table" then
			return
		end
		if api:GetDetection("Wendigo") or api:GetDetection("Dullahan") then
			return
		end
		local outcome = event.Outcome
		state.LastOutcome = outcome
		state.LastReason = event.Reason
		state.LastConfidence = tonumber(event.Confidence)
		if outcome == "Matched" then
			api:ClearRuleOut("Oni")
			api:Detect(
				"Oni",
				event.Reason,
				state.LastConfidence or 97,
				event.Source
			)
			api:Refresh()
		elseif outcome == "Ordinary" then
			api:ClearDetection("Oni")
			api:RuleOut("Oni", event.Reason, 95)
			api:Refresh()
		end
	end

	-- Raw hook: removes the map-size factor, tries only the configured valid
	-- difficulty multipliers, and compares the resulting 13.5 and 11 base modes.
	-- OnVisibleHuntSpeed remains available for compatibility with older hosts.
	function observer:OnVisibleHuntSpeedSamples(event)
		if type(event) ~= "table" then
			return
		end
		beginRawHuntIfNeeded(event)

		local speeds = visibleHuntSpeeds(event)
		if #speeds < 3 then
			if event.HuntEnded == true or event.Completed == true then
				state.RawHuntClosed = true
			end
			return
		end

		local huntMedian = median(speeds)
		if not huntMedian then
			return
		end
		local mapFactor = tonumber(event.MapFactor) or 1
		mapFactor = math.max(mapFactor, 0.001)
		local mapNormalizedSpeed = huntMedian / mapFactor
		local multipliers = validMultipliers(event.ValidMultipliers)
		local oniError, oniMultiplier, oniBase = closestBaseMode(
			mapNormalizedSpeed,
			13.5,
			multipliers
		)
		local normalError, normalMultiplier, normalBase = closestBaseMode(
			mapNormalizedSpeed,
			11,
			multipliers
		)
		oniBase = tonumber(oniBase) or mapNormalizedSpeed
		normalBase = tonumber(normalBase) or mapNormalizedSpeed
		local stable = standardDeviation(speeds)
			<= math.max(0.16, huntMedian * 0.022)
		state.LastMedian = huntMedian
		state.LastStable = stable

		if event.RivalSpeedPattern ~= true
			and stable
			and oniError <= 0.34
			and normalError - oniError >= 0.15 then
			if not state.PatternRecordedThisHunt then
				state.PatternRecordedThisHunt = true
				state.PatternHunts = state.PatternHunts + 1
			end
			local confidence = state.PatternHunts >= 2 and 99 or 95
			self:OnVisibleHuntSpeed({
				Outcome = "Matched",
				Reason = event.MatchReason
					or "visible hunting WalkSpeed "
						.. string.format("%.2f", huntMedian)
						.. " normalized to base "
						.. string.format("%.2f", oniBase)
						.. " at the valid "
						.. tostring(math.floor(oniMultiplier * 100 + 0.5))
						.. "% setting, matching Oni's 13.5 hunt mode across "
						.. tostring(state.PatternHunts)
						.. " qualified hunt"
						.. (state.PatternHunts == 1 and "" or "s"),
				Confidence = confidence,
				Source = event.Source,
			})
		elseif #speeds >= 4
			and stable
			and normalError <= 0.28
			and oniError - normalError >= 0.15 then
			state.PatternHunts = 0
			state.PatternRecordedThisHunt = false
			self:OnVisibleHuntSpeed({
				Outcome = "Ordinary",
				Reason = event.OrdinaryReason
					or "visible hunting WalkSpeed "
						.. string.format("%.2f", huntMedian)
						.. " normalized to base "
						.. string.format("%.2f", normalBase)
						.. " at the valid "
						.. tostring(math.floor(normalMultiplier * 100 + 0.5))
						.. "% setting, matching the normal 11 hunt mode rather than Oni's 13.5",
				Confidence = 95,
				Source = event.Source,
			})
		end

		if event.HuntEnded == true or event.Completed == true then
			state.RawHuntClosed = true
		end
	end

	function observer:GetState()
		return {
			LastOutcome = state.LastOutcome,
			LastReason = state.LastReason,
			LastConfidence = state.LastConfidence,
			PatternHunts = state.PatternHunts,
			PatternRecordedThisHunt = state.PatternRecordedThisHunt,
			RawHuntClosed = state.RawHuntClosed,
			LastMedian = state.LastMedian,
			LastStable = state.LastStable,
		}
	end

	observer.Snapshot = observer.GetState
	return observer
end

return {
	Name = "Oni",
	Evidence = {"FreezingTemperatures", "LaserProjector", "SpiritBox"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 97,
	TTL = 25,
	ObservationKeys = {"VisibleHuntSpeed"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "Visible hunting WalkSpeed resolves to base 13.5 after removing the map bonus and one valid 50%, 75%, 100%, 125%, 150%, or 200% difficulty multiplier; ordinary ghosts resolve to base 11.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Maybe"] = {
			{
				Text = "Rapid or high-pitched footsteps accompany unusually frequent visible manifestations.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "One fast hunt or one manifestation is a risky relative-speed/activity tell.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Caveat",
			},
		},
	},
}
