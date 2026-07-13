local SOURCE = "https://demonology.fandom.com/wiki/Keres"
local FEMALE_MODELS = {Abaddon = true, Leech = true, Rattle = true, Watcher = true}

local PRE_WINDOW_START = -0.9
local PRE_WINDOW_END = -0.05
local POST_WINDOW_START = 0.08
local EARLIEST_CLASSIFICATION = 0.65
local STABLE_NO_DECREASE_AT = 1.25
local PENDING_EXPIRY = 2.5
local SAMPLE_RETENTION = 4
local MIN_SAMPLE_COUNT = 3
local DECREASE_RATIO = -0.07
local INCREASE_RATIO = 0.14
local NO_DECREASE_RATIO = -0.03

local function median(values)
	if #values == 0 then
		return nil
	end
	local sorted = {}
	for index, value in ipairs(values) do
		sorted[index] = value
	end
	table.sort(sorted)
	local middle = math.floor((#sorted + 1) / 2)
	if #sorted % 2 == 1 then
		return sorted[middle]
	end
	return (sorted[middle] + sorted[middle + 1]) / 2
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

local function sampleStatistics(samples, startTime, endTime, huntSerial)
	local values = {}
	for _, sample in ipairs(samples) do
		if sample.Time >= startTime
			and sample.Time <= endTime
			and sample.Hunting == true
			and (huntSerial == nil or sample.HuntSerial == huntSerial) then
			table.insert(values, sample.Speed)
		end
	end
	return median(values), #values, standardDeviation(values)
end

local function stableMedian(value, deviation)
	return value ~= nil
		and deviation ~= nil
		and deviation <= math.max(0.1, math.abs(value) * 0.012)
end

local function deathIdentity(event, time)
	local playerId = event.PlayerId or event.UserId
	if playerId ~= nil then
		return "player-id:" .. tostring(playerId)
	end
	local player = event.Player or event.TargetPlayer or event.Target
	if player ~= nil then
		return player
	end
	local deathId = event.DeathId or event.KillId
	if deathId ~= nil then
		return "death-id:" .. tostring(deathId)
	end
	return "death-time:"
		.. tostring(event.HuntSerial or "unknown")
		.. ":"
		.. string.format("%.6f", time)
end

local function createObserver(api)
	local state = {
		KillDecreaseCount = 0,
		LastKillDirection = nil,
		LastKillReason = nil,
		LastFemaleReason = nil,
		SpeedSamples = {},
		LatestSampleTime = nil,
		PendingKill = nil,
		ProcessedDeaths = {},
		ProcessedDeathCount = 0,
		LastRawOutcome = nil,
		LastPreSpeed = nil,
		LastPostSpeed = nil,
		LastRelativeChange = nil,
	}
	local observer = {}

	local function strongAswangSaltFinding()
		local detection = api:GetDetection("Aswang")
		if type(detection) ~= "table"
			or (tonumber(detection.Confidence) or 0) < 94 then
			return false
		end
		return detection.Source == "SaltContact"
			or string.find(
				string.lower(tostring(detection.Reason or "")),
				"salt",
				1,
				true
			) ~= nil
	end

	function observer:Reset()
		state.KillDecreaseCount = 0
		state.LastKillDirection = nil
		state.LastKillReason = nil
		state.LastFemaleReason = nil
		state.SpeedSamples = {}
		state.LatestSampleTime = nil
		state.PendingKill = nil
		state.ProcessedDeaths = {}
		state.ProcessedDeathCount = 0
		state.LastRawOutcome = nil
		state.LastPreSpeed = nil
		state.LastPostSpeed = nil
		state.LastRelativeChange = nil
	end

	function observer:OnKillSpeed(event)
		if type(event) ~= "table" then
			return
		end
		local direction = event.Direction
		state.LastKillDirection = direction
		state.LastKillReason = event.Reason
		if direction == "Decrease" then
			if strongAswangSaltFinding() then
				return
			end
			local count = tonumber(event.Count)
				or state.KillDecreaseCount + 1
			state.KillDecreaseCount = math.max(1, count)
			api:ClearRuleOut("Keres")
			api:Detect(
				"Keres",
				event.Reason
					or (
						"Ghost Humanoid WalkSpeed fell by roughly 10% after "
						.. tostring(state.KillDecreaseCount)
						.. " verified player kill"
						.. (state.KillDecreaseCount == 1 and "" or "s")
					),
				tonumber(event.Confidence)
					or (state.KillDecreaseCount >= 2 and 99 or 97),
				event.Source
			)
			api:RuleOut(
				"Aswang",
				"the death-linked speed change was downward rather than upward",
				94
			)
		elseif direction == "Increase" then
			api:RuleOut(
				"Keres",
				"the death-linked speed change was upward rather than downward",
				94
			)
		elseif direction == "StableNoDecrease" then
			api:RuleOut(
				"Keres",
				event.Reason
					or "a verified player kill produced no persistent WalkSpeed decrease",
				92
			)
		else
			return
		end
		api:Refresh()
	end

	local function evaluatePendingKill(now, hunting, huntSerial)
		local pending = state.PendingKill
		if not pending or type(now) ~= "number" then
			return
		end

		local elapsed = now - pending.Time
		if elapsed >= PENDING_EXPIRY then
			state.PendingKill = nil
			state.LastRawOutcome = "Expired"
			return
		end
		if hunting ~= true or elapsed < EARLIEST_CLASSIFICATION then
			return
		end
		if pending.HuntSerial ~= nil
			and huntSerial ~= nil
			and pending.HuntSerial ~= huntSerial then
			return
		end

		local postSpeed, postCount, postDeviation = sampleStatistics(
			state.SpeedSamples,
			pending.Time + POST_WINDOW_START,
			now,
			pending.HuntSerial
		)
		pending.PostSampleCount = postCount
		pending.PostDeviation = postDeviation
		if postCount < MIN_SAMPLE_COUNT
			or not stableMedian(postSpeed, postDeviation) then
			return
		end

		local relativeChange = (postSpeed - pending.PreSpeed)
			/ math.max(math.abs(pending.PreSpeed), 0.01)
		state.LastPostSpeed = postSpeed
		state.LastRelativeChange = relativeChange
		local direction
		if relativeChange <= DECREASE_RATIO then
			direction = "Decrease"
		elseif relativeChange >= INCREASE_RATIO then
			direction = "Increase"
		elseif elapsed >= STABLE_NO_DECREASE_AT
			and relativeChange > NO_DECREASE_RATIO then
			direction = "StableNoDecrease"
		end
		if not direction then
			return
		end

		state.PendingKill = nil
		state.LastRawOutcome = direction
		observer:OnKillSpeed({
			Direction = direction,
			Reason = pending.Reason,
			Source = pending.Source or "KillSpeed",
		})
	end

	-- Raw generic speed samples are retained here so the Keres observer owns
	-- both sides of the death comparison. The adapter only reports facts.
	function observer:OnSpeedSample(event)
		if type(event) ~= "table" then
			return
		end
		local time = tonumber(event.Time or event.Timestamp)
		local speed = tonumber(
			event.Speed or event.GhostWalkSpeed or event.WalkSpeed
		)
		if not time or not speed or speed <= 0 then
			return
		end

		table.insert(state.SpeedSamples, {
			Time = time,
			Speed = speed,
			Hunting = event.Hunting == true,
			HuntSerial = event.HuntSerial,
		})
		table.sort(state.SpeedSamples, function(left, right)
			return left.Time < right.Time
		end)
		state.LatestSampleTime = math.max(state.LatestSampleTime or time, time)
		local cutoff = state.LatestSampleTime - SAMPLE_RETENTION
		while state.SpeedSamples[1]
			and state.SpeedSamples[1].Time < cutoff do
			table.remove(state.SpeedSamples, 1)
		end

		evaluatePendingKill(time, event.Hunting, event.HuntSerial)
	end

	-- Raw death facts initiate one comparison window. Player identity is
	-- preferred for deduplication; DeathId/KillId or hunt+timestamp is accepted
	-- when an adapter cannot provide a player object.
	function observer:OnPlayerDeath(event)
		if type(event) ~= "table" then
			return
		end
		local time = tonumber(event.Time or event.Timestamp)
		local otherAlive = tonumber(event.OtherAlive)
		local huntAge = tonumber(event.HuntAge)
		if not time
			or event.Hunting ~= true
			or not otherAlive
			or otherAlive <= 0
			or not huntAge
			or huntAge < 0.5
			or event.Unique == false
			or event.UniqueKill == false
			or event.UniqueSpeedKill == false then
			return
		end

		local identity = deathIdentity(event, time)
		if state.ProcessedDeaths[identity] then
			return
		end
		state.ProcessedDeaths[identity] = true
		state.ProcessedDeathCount = state.ProcessedDeathCount + 1
		state.PendingKill = nil
		state.LastPreSpeed = nil
		state.LastPostSpeed = nil
		state.LastRelativeChange = nil

		local preSpeed, preCount, preDeviation = sampleStatistics(
			state.SpeedSamples,
			time + PRE_WINDOW_START,
			time + PRE_WINDOW_END,
			event.HuntSerial
		)
		if preCount < MIN_SAMPLE_COUNT
			or not stableMedian(preSpeed, preDeviation) then
			state.LastRawOutcome = "UnstablePre"
			return
		end

		state.LastPreSpeed = preSpeed
		state.LastRawOutcome = "Pending"
		state.PendingKill = {
			Time = time,
			PreSpeed = preSpeed,
			PreSampleCount = preCount,
			PreDeviation = preDeviation,
			PostSampleCount = 0,
			HuntSerial = event.HuntSerial,
			Reason = event.Reason,
			Source = event.Source,
		}
	end

	function observer:Tick(event)
		if type(event) ~= "table" then
			return
		end
		evaluatePendingKill(
			tonumber(event.Time or event.Timestamp),
			event.Hunting,
			event.HuntSerial
		)
	end

	function observer:OnFemaleIndicator(event)
		event = type(event) == "table" and event or {}
		if event.Model ~= nil and not FEMALE_MODELS[tostring(event.Model)] then
			return
		end
		local reason = event.Reason
		if reason == nil and event.Model ~= nil then
			reason = "VisualModel "
				.. tostring(event.Model)
				.. " is one of the female Keres/Siren ghost models"
		end
		state.LastFemaleReason = reason
		api:Detect(
			"Keres",
			reason
				or "the ghost used one of the female Keres/Siren indicators",
			35,
			event.Source
		)
		api:MarkPersistent("Keres")
		api:Refresh()
	end

	function observer:Snapshot()
		local pending = state.PendingKill
		return {
			KillDecreaseCount = state.KillDecreaseCount,
			LastKillDirection = state.LastKillDirection,
			LastKillReason = state.LastKillReason,
			LastFemaleReason = state.LastFemaleReason,
			SpeedSampleCount = #state.SpeedSamples,
			ProcessedDeathCount = state.ProcessedDeathCount,
			LastRawOutcome = state.LastRawOutcome,
			LastPreSpeed = state.LastPreSpeed,
			LastPostSpeed = state.LastPostSpeed,
			LastRelativeChange = state.LastRelativeChange,
			PendingKill = pending and {
				Time = pending.Time,
				PreSpeed = pending.PreSpeed,
				PreSampleCount = pending.PreSampleCount,
				PreDeviation = pending.PreDeviation,
				PostSampleCount = pending.PostSampleCount,
				PostDeviation = pending.PostDeviation,
				HuntSerial = pending.HuntSerial,
			} or nil,
		}
	end

	return observer
end

return {
	Name = "Keres",
	Evidence = {"Handprints", "SpiritBox", "Wither"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 95,
	ObservationKeys = {"FemaleVisualModel", "FemaleSpiritBoxVoice", "KillSpeedChange"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "A controlled hunt targets the lowest-energy hunter while ignoring higher-energy hunters; solo it ignores a hunter at or above 90% energy.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
			{
				Text = "Movement speed drops about 10% after each unique hunter kill.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Weakness",
			},
		},
		["Maybe"] = {
			{
				Text = "It appears to prioritize the party member with the least energy.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "A feminine model or Spirit Box voice only narrows the ghost to Keres or Siren.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Model",
			},
		},
	},
}
