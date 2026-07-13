local SOURCE = "https://demonology.fandom.com/wiki/Wendigo"

local DEFAULT_SPEED_MULTIPLIERS = {0.5, 0.75, 1, 1.25, 1.5, 2}
local REQUIRED_TRANSITIONS = 3
local MIN_SANITY_SPREAD = 8

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

local function normalizeSnapshots(rawSnapshots)
	local result = {}
	for _, snapshot in ipairs(type(rawSnapshots) == "table" and rawSnapshots or {}) do
		if type(snapshot) == "table" then
			local sanity = tonumber(
				snapshot.Sanity or snapshot.Energy or snapshot.AverageSanity
			)
			local speed = tonumber(
				snapshot.Speed or snapshot.GhostWalkSpeed or snapshot.WalkSpeed
			)
			if sanity and speed and speed > 0 then
				table.insert(result, {
					Sanity = math.clamp(sanity, 0, 100),
					Speed = speed,
					Hunting = snapshot.Hunting,
					Time = tonumber(snapshot.Time or snapshot.Timestamp),
				})
			end
		end
	end
	while #result > 3 do
		table.remove(result, 1)
	end
	return result
end

local function createObserver(api)
	local state = {
		LastOutcome = nil,
		LastReason = nil,
		LastConfidence = nil,
		LastRequiredSnapshots = nil,
		LastMatchedMultiplier = nil,
		LastInvalidReason = nil,
		LastSanitySpread = nil,
		LastObservedSpeedDelta = nil,
		LastExpectedSpeedDelta = nil,
	}
	local observer = {}

	function observer:Reset()
		state.LastOutcome = nil
		state.LastReason = nil
		state.LastConfidence = nil
		state.LastRequiredSnapshots = nil
		state.LastMatchedMultiplier = nil
		state.LastInvalidReason = nil
		state.LastSanitySpread = nil
		state.LastObservedSpeedDelta = nil
		state.LastExpectedSpeedDelta = nil
	end

	function observer:OnSanitySpeedCurve(event)
		if type(event) ~= "table" then
			return
		end
		if api:GetDetection("Aswang") or api:GetDetection("Dullahan") then
			return
		end
		local outcome = event.Outcome
		state.LastOutcome = outcome
		state.LastReason = event.Reason
		state.LastConfidence = tonumber(event.Confidence)
		if outcome == "Matched" then
			api:ClearRuleOut("Wendigo")
			api:ClearDetection("Oni")
			api:Detect(
				"Wendigo",
				event.Reason,
				state.LastConfidence or 99,
				event.Source
			)
			api:Refresh()
		elseif outcome == "Rejected" then
			api:ClearDetection("Wendigo")
			api:RuleOut("Wendigo", event.Reason, 99)
			api:Refresh()
		end
	end

	-- Raw hook: checks switch-time average sanity against the Wendigo base curve
	-- (14 - sanity * 0.05), after map-size and one fixed difficulty multiplier.
	-- OnSanitySpeedCurve remains for compatibility with already-classified input.
	function observer:OnHuntTransitionSamples(event)
		if type(event) ~= "table" then
			return
		end
		if event.RivalSpeedPattern == true then
			return
		end

		local snapshots = normalizeSnapshots(event.Snapshots or event.Samples)
		local latest = snapshots[#snapshots]
		if not latest then
			return
		end
		state.LastMatchedMultiplier = nil
		state.LastInvalidReason = nil
		state.LastSanitySpread = nil
		state.LastObservedSpeedDelta = nil
		state.LastExpectedSpeedDelta = nil

		local requiredSnapshots = REQUIRED_TRANSITIONS
		state.LastRequiredSnapshots = requiredSnapshots
		if #snapshots < requiredSnapshots then
			state.LastInvalidReason = "waiting for three distinct hunt-state transitions"
			return
		end

		local highestSanitySnapshot = snapshots[1]
		local lowestSanitySnapshot = snapshots[1]
		for index, snapshot in ipairs(snapshots) do
			if type(snapshot.Hunting) ~= "boolean" then
				state.LastInvalidReason = "transition snapshots require an explicit hunt state"
				return
			end
			if index > 1
				and snapshot.Hunting == snapshots[index - 1].Hunting then
				state.LastInvalidReason = "snapshots did not represent distinct alternating hunt-state transitions"
				return
			end
			if snapshot.Sanity > highestSanitySnapshot.Sanity then
				highestSanitySnapshot = snapshot
			end
			if snapshot.Sanity < lowestSanitySnapshot.Sanity then
				lowestSanitySnapshot = snapshot
			end
		end
		local sanitySpread = highestSanitySnapshot.Sanity
			- lowestSanitySnapshot.Sanity
		state.LastSanitySpread = sanitySpread
		if sanitySpread < MIN_SANITY_SPREAD then
			state.LastInvalidReason = "sanity variation was too small to establish a speed curve"
			return
		end

		local mapFactor = math.max(tonumber(event.MapFactor) or 1, 0.001)
		local multipliers = validMultipliers(event.ValidMultipliers)
		local matchedMultiplier
		local invalidReason
		for index = #snapshots - requiredSnapshots + 1, #snapshots do
			local snapshot = snapshots[index]
			local baseSpeed = 14 - snapshot.Sanity * 0.05
			local inferred = snapshot.Speed
				/ math.max(mapFactor * baseSpeed, 0.001)
			local nearest
			local nearestError = math.huge
			for _, multiplier in ipairs(multipliers) do
				local errorAmount = math.abs(inferred - multiplier)
				if errorAmount < nearestError then
					nearestError = errorAmount
					nearest = multiplier
				end
			end

			local expectedSpeed = mapFactor * baseSpeed * nearest
			local speedError = math.abs(snapshot.Speed - expectedSpeed)
			local speedTolerance = math.max(0.18, expectedSpeed * 0.02)
			if speedError > speedTolerance then
				invalidReason = "observed multiplier "
					.. string.format("%.4f", inferred)
					.. " was outside the allowed replication tolerance for the nearest configured 50%-200% step"
				break
			end

			if matchedMultiplier
				and math.abs(matchedMultiplier - nearest) > 0.001 then
				invalidReason = "successive snapshots required different custom multipliers"
				break
			end
			matchedMultiplier = nearest
		end

		if not invalidReason and matchedMultiplier then
			local observedSpeedDelta = lowestSanitySnapshot.Speed
				- highestSanitySnapshot.Speed
			local expectedSpeedDelta = mapFactor
				* matchedMultiplier
				* 0.05
				* sanitySpread
			local deltaTolerance = math.max(
				0.22,
				expectedSpeedDelta * 0.2
			)
			state.LastObservedSpeedDelta = observedSpeedDelta
			state.LastExpectedSpeedDelta = expectedSpeedDelta
			if observedSpeedDelta <= 0
				or math.abs(observedSpeedDelta - expectedSpeedDelta)
					> deltaTolerance then
				invalidReason = "speed did not rise by the expected amount as switch-time sanity fell at one fixed multiplier"
			end
		end

		state.LastMatchedMultiplier = matchedMultiplier
		state.LastInvalidReason = invalidReason
		if invalidReason then
			self:OnSanitySpeedCurve({
				Outcome = "Rejected",
				Reason = event.RejectionReason or invalidReason,
				Confidence = 99,
				Source = event.Source,
			})
		elseif matchedMultiplier then
			self:OnSanitySpeedCurve({
				Outcome = "Matched",
				Reason = event.MatchReason
					or tostring(requiredSnapshots)
						.. " hunt-state transition WalkSpeed snapshot"
						.. (requiredSnapshots == 1 and "" or "s")
						.. " matched the switch-time average-sanity curve within replication tolerance at "
						.. tostring(math.floor(matchedMultiplier * 100 + 0.5))
						.. "% Ghost Walkspeed Multiplier",
				Confidence = 99,
				Source = event.Source,
			})
		end
	end

	function observer:GetState()
		return {
			LastOutcome = state.LastOutcome,
			LastReason = state.LastReason,
			LastConfidence = state.LastConfidence,
			LastRequiredSnapshots = state.LastRequiredSnapshots,
			LastMatchedMultiplier = state.LastMatchedMultiplier,
			LastInvalidReason = state.LastInvalidReason,
			LastSanitySpread = state.LastSanitySpread,
			LastObservedSpeedDelta = state.LastObservedSpeedDelta,
			LastExpectedSpeedDelta = state.LastExpectedSpeedDelta,
		}
	end

	observer.Snapshot = observer.GetState
	return observer
end

return {
	Name = "Wendigo",
	Evidence = {"GhostOrb", "GhostWriting", "LaserProjector"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 98,
	TTL = 20,
	ObservationKeys = {"HuntTransitionSanitySpeed"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "Controlled energy changes correlate with hunt speed, and it refuses to begin a hunt near a lit candle or lantern.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Maybe"] = {
			{
				Text = "It becomes very fast at low average energy or repeatedly avoids starting near lit flames.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "One fast hunt or a hunt starting away from fire is not distinctive.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Caveat",
			},
		},
	},
}
