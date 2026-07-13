local SOURCE = "https://demonology.fandom.com/wiki/Dullahan"

local MATCH_REASON = "Ghost WalkSpeed increased in at least three short intervals across five hunting samples; decreases were ignored"
local RULE_OUT_REASON = "five or more 0.1-second hunt samples contained fewer than three WalkSpeed increases"

local MIN_SAMPLE_INTERVAL = 0.07
local MAX_SAMPLE_INTERVAL = 0.3
local MIN_WINDOW_DURATION = 0.28
local MAX_WINDOW_DURATION = 0.65
local MAX_SAMPLE_AGE = 0.7
local MIN_SPEED_INCREASE = 0.001

local function readSample(sample, fallbackTime)
	if type(sample) == "number" then
		return fallbackTime, sample
	end
	if type(sample) ~= "table" then
		return nil, nil
	end
	local time = tonumber(sample.Time or sample.Timestamp)
	local speed = tonumber(
		sample.Speed or sample.GhostWalkSpeed or sample.WalkSpeed
	)
	return time or fallbackTime, speed
end

local function buildCurrentSampleSegment(rawSamples, sampleInterval)
	local samples = {}
	local interval = tonumber(sampleInterval) or 0.1
	for index, rawSample in ipairs(type(rawSamples) == "table" and rawSamples or {}) do
		local time, speed = readSample(rawSample, (index - 1) * interval)
		if time and speed and speed > 0 then
			local previous = samples[#samples]
			local elapsed = previous and time - previous.Time or nil
			if elapsed and elapsed < MIN_SAMPLE_INTERVAL then
				continue
			end
			if elapsed and elapsed > MAX_SAMPLE_INTERVAL then
				table.clear(samples)
			end
			table.insert(samples, {Time = time, Speed = speed})
		end
	end

	local latest = samples[#samples]
	while latest and samples[1]
		and latest.Time - samples[1].Time > MAX_SAMPLE_AGE do
		table.remove(samples, 1)
	end
	return samples
end

local function analyzeSamples(rawSamples, sampleInterval)
	local samples = buildCurrentSampleSegment(rawSamples, sampleInterval)
	if #samples < 5 then
		return {
			Qualified = false,
			SampleCount = #samples,
			IncreaseCount = 0,
		}
	end

	local firstIndex = #samples - 4
	local duration = samples[#samples].Time - samples[firstIndex].Time
	local qualified = duration >= MIN_WINDOW_DURATION
		and duration <= MAX_WINDOW_DURATION
	if qualified then
		for index = firstIndex + 1, #samples do
			local elapsed = samples[index].Time - samples[index - 1].Time
			if elapsed < MIN_SAMPLE_INTERVAL or elapsed > MAX_SAMPLE_INTERVAL then
				qualified = false
				break
			end
		end
	end

	local increaseCount = 0
	if qualified then
		for index = firstIndex + 1, #samples do
			if samples[index].Speed - samples[index - 1].Speed
				>= MIN_SPEED_INCREASE then
				increaseCount = increaseCount + 1
			end
		end
	end

	return {
		Qualified = qualified,
		SampleCount = 5,
		IncreaseCount = increaseCount,
		Duration = duration,
		Matched = qualified and increaseCount >= 3,
	}
end

local function createObserver(api)
	local state = {
		PatternDetected = false,
		PatternObservedThisHunt = false,
		HadQualifiedWindow = false,
		CompletedNoIncreaseHunt = false,
		LastSampleCount = 0,
		LastIncreaseCount = 0,
		LastDuration = nil,
		RawHuntClosed = false,
	}
	local observer = {}

	function observer:Reset(options)
		local preserveFindings = type(options) == "table"
			and options.PreserveFindings == true
		state.PatternDetected = preserveFindings
			and api:GetDetection("Dullahan") ~= nil
		state.PatternObservedThisHunt = false
		state.HadQualifiedWindow = false
		state.CompletedNoIncreaseHunt = false
		state.LastSampleCount = 0
		state.LastIncreaseCount = 0
		state.LastDuration = nil
		state.RawHuntClosed = false
	end

	local function beginRawHuntIfNeeded(event)
		if event.HuntStarted == true or state.RawHuntClosed then
			state.PatternObservedThisHunt = false
			state.HadQualifiedWindow = false
			state.CompletedNoIncreaseHunt = false
			state.LastSampleCount = 0
			state.LastIncreaseCount = 0
			state.LastDuration = nil
			state.RawHuntClosed = false
		end
	end

	function observer:OnHuntSpeedWindow(event)
		if type(event) ~= "table" then
			return
		end

		state.LastSampleCount = tonumber(event.SampleCount) or 0
		state.LastIncreaseCount = tonumber(event.IncreaseCount) or 0
		state.LastDuration = tonumber(event.Duration)
		local qualified = event.Qualified
		if qualified == nil then
			qualified = state.LastSampleCount >= 5
		end
		if qualified == true then
			state.HadQualifiedWindow = true
		end

		if event.Matched ~= true then
			return
		end

		state.PatternDetected = true
		state.PatternObservedThisHunt = true
		state.CompletedNoIncreaseHunt = false
		api:ClearRuleOut("Dullahan")
		api:ClearDetection("Dybbuk")
		api:ClearDetection("Oni")
		api:ClearDetection("Wendigo")
		api:Detect("Dullahan", event.Reason or MATCH_REASON, 99, event.Source)
		api:Refresh()
	end

	function observer:OnCompletedHunt(event)
		event = type(event) == "table" and event or {}
		local hadQualifiedWindow = event.HadQualifiedWindow
		if hadQualifiedWindow == nil then
			hadQualifiedWindow = state.HadQualifiedWindow
		end
		local patternObserved = event.PatternObserved
		if patternObserved == nil then
			patternObserved = state.PatternDetected
				or state.PatternObservedThisHunt
		end

		state.HadQualifiedWindow = hadQualifiedWindow == true
		state.PatternObservedThisHunt = patternObserved == true
		state.CompletedNoIncreaseHunt = hadQualifiedWindow == true
			and patternObserved ~= true
		if state.CompletedNoIncreaseHunt then
			state.PatternDetected = false
			api:ClearDetection("Dullahan")
			api:RuleOut("Dullahan", event.Reason or RULE_OUT_REASON, 92)
			api:Refresh()
		end
		api:Emit({
			Type = "Dispatch",
			Hook = "OnDullahanEvaluation",
			Event = {
				CompletedNoIncreaseHunt = state.CompletedNoIncreaseHunt,
				PatternDetected = state.PatternDetected
					or state.PatternObservedThisHunt,
				HadQualifiedWindow = state.HadQualifiedWindow,
			},
		})
	end

	-- Raw hook: callers provide hunting WalkSpeed samples and this observer owns
	-- the interval/window decision.  The legacy outcome hooks above remain for
	-- compatibility with older hosts during the modular migration.
	function observer:OnHuntSpeedSamples(event)
		if type(event) ~= "table" then
			return
		end
		beginRawHuntIfNeeded(event)

		local result = analyzeSamples(event.Samples, event.SampleInterval)
		self:OnHuntSpeedWindow({
			SampleCount = result.SampleCount,
			IncreaseCount = result.IncreaseCount,
			Duration = result.Duration,
			Qualified = result.Qualified,
			Matched = result.Matched,
			Reason = event.MatchReason or event.Reason or MATCH_REASON,
			Source = event.Source,
		})

		if event.HuntEnded == true or event.Completed == true then
			self:OnCompletedHunt({
				HadQualifiedWindow = state.HadQualifiedWindow,
				PatternObserved = state.PatternDetected
					or state.PatternObservedThisHunt,
				Reason = event.RuleOutReason or RULE_OUT_REASON,
			})
			state.RawHuntClosed = true
		end
	end

	function observer:GetState()
		return {
			PatternDetected = state.PatternDetected,
			PatternObservedThisHunt = state.PatternObservedThisHunt,
			HadQualifiedWindow = state.HadQualifiedWindow,
			CompletedNoIncreaseHunt = state.CompletedNoIncreaseHunt,
			LastSampleCount = state.LastSampleCount,
			LastIncreaseCount = state.LastIncreaseCount,
			LastDuration = state.LastDuration,
			RawHuntClosed = state.RawHuntClosed,
		}
	end

	observer.Snapshot = observer.GetState
	return observer
end

return {
	Name = "Dullahan",
	Evidence = {"FreezingTemperatures", "LaserProjector", "Wither"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 99,
	TTL = 25,
	ObservationKeys = {"HuntSpeedSteps"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "A clear Photo Camera image shows it without a head.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Weakness",
			},
			{
				Text = "During a hunt, WalkSpeed rises in several short intervals; line of sight is not required and intervening decreases do not invalidate the pattern.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Maybe"] = {
			{
				Text = "At least three upward WalkSpeed steps appear across five roughly 0.1-second hunting samples.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "A fast ghost or a naturally partial-head model can be mistaken for this tell.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Caveat",
			},
		},
	},
}
