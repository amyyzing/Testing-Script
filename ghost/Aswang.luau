local SOURCE = "https://demonology.fandom.com/wiki/Aswang"

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

local function observationTime(event)
	return tonumber(event.Time or event.Timestamp) or os.clock()
end

local function normalizeSpeedSamples(rawSamples)
	local samples = {}
	for index, sample in ipairs(type(rawSamples) == "table" and rawSamples or {}) do
		if type(sample) == "table" then
			local speed = tonumber(
				sample.Speed or sample.GhostWalkSpeed or sample.WalkSpeed
			)
			local time = tonumber(sample.Time or sample.Timestamp)
				or (index - 1) * 0.1
			if speed and speed > 0 then
				table.insert(samples, {Time = time, Speed = speed})
			end
		end
	end
	table.sort(samples, function(left, right)
		return left.Time < right.Time
	end)
	return samples
end

local function createObserver(api)
	local state = {
		LastSaltOutcome = nil,
		LastSaltReason = nil,
		SaltConfidence = 0,
		StrongSaltFinding = false,
		KillIncreaseCount = 0,
		LastKillDirection = nil,
		LastKillReason = nil,
		SaltContacts = {},
		LastContactId = nil,
		LastRawOutcome = nil,
		SpeedSamples = {},
		PendingDeaths = {},
		ProcessedPlayers = {},
		LastDeathOutcome = nil,
	}
	local observer = {}

	function observer:Reset(options)
		state.KillIncreaseCount = 0
		state.LastKillDirection = nil
		state.LastKillReason = nil
		state.SaltContacts = {}
		state.LastContactId = nil
		state.LastRawOutcome = nil
		state.SpeedSamples = {}
		state.PendingDeaths = {}
		state.ProcessedPlayers = {}
		state.LastDeathOutcome = nil
		if type(options) ~= "table" or options.PreserveFindings ~= true then
			state.LastSaltOutcome = nil
			state.LastSaltReason = nil
			state.SaltConfidence = 0
			state.StrongSaltFinding = false
		end
	end

	function observer:OnSaltSpeed(event)
		if type(event) ~= "table" then
			return
		end
		if event.Inferred == true and api:GetDetection("Dullahan") then
			return
		end
		local outcome = event.Outcome
		local confidence = tonumber(event.Confidence)
		state.LastSaltOutcome = outcome
		state.LastSaltReason = event.Reason

		if outcome == "Slow" then
			confidence = confidence or 95
			state.SaltConfidence = math.max(state.SaltConfidence, confidence)
			state.StrongSaltFinding = state.SaltConfidence >= 94
			api:ClearRuleOut("Aswang")
			api:Detect(
				"Aswang",
				event.Reason
					or "during the same hunt, direct salt contact produced repeated WalkSpeed samples at least 6% below the pre-touch baseline",
				confidence,
				event.Source or "SaltContact"
			)
		elseif outcome == "Recovered" then
			confidence = confidence or 99
			state.SaltConfidence = math.max(state.SaltConfidence, confidence)
			state.StrongSaltFinding = true
			api:ClearRuleOut("Aswang")
			api:Detect(
				"Aswang",
				event.Reason
					or "during one hunt, direct salt contact caused a repeated temporary WalkSpeed reduction followed by recovery",
				confidence,
				event.Source or "SaltContact"
			)
		elseif outcome == "NoDrop" then
			if state.StrongSaltFinding then
				return
			end
			state.StrongSaltFinding = false
			api:ClearDetection("Aswang")
			api:RuleOut(
				"Aswang",
				event.Reason
					or "a verified hunting salt contact had a full speed sample without a temporary WalkSpeed reduction",
				confidence or 90
			)
		else
			return
		end
		api:Refresh()
	end

	local function stableMedian(startTime, endTime)
		local values = {}
		for _, sample in ipairs(state.SpeedSamples) do
			if sample.Hunting
				and sample.Time >= startTime
				and sample.Time <= endTime then
				table.insert(values, sample.Speed)
			end
		end
		if #values < 3 then
			return nil, #values
		end
		local speed = tonumber(median(values))
		if speed == nil then
			return nil, #values
		end
		local deviation = standardDeviation(values)
		if deviation > math.max(0.1, math.abs(speed) * 0.012) then
			return nil, #values
		end
		return speed, #values
	end

	local function emitKillSpeed(event)
		-- Keres consumes the same raw feed and owns its own downward classifier.
		-- Resolve locally so one physical kill cannot increment either observer
		-- twice through a second, globally-dispatched compatibility event.
		observer:OnKillSpeed(event)
	end

	local function evaluatePendingDeaths(now, hunting)
		for playerId, pending in pairs(state.PendingDeaths) do
			local elapsed = now - pending.Time
			if elapsed > 2.5 then
				state.PendingDeaths[playerId] = nil
			elseif hunting and elapsed + 1e-6 >= 0.65 then
				local postSpeed = stableMedian(pending.Time + 0.08, now)
				if postSpeed then
					local relativeDifference = (postSpeed - pending.PreSpeed)
						/ math.max(math.abs(pending.PreSpeed), 0.01)
					if relativeDifference >= 0.14 then
						state.LastDeathOutcome = "Increase"
						state.PendingDeaths[playerId] = nil
						emitKillSpeed({
							Direction = "Increase",
							PreSpeed = pending.PreSpeed,
							PostSpeed = postSpeed,
							RelativeDifference = relativeDifference,
							Source = pending.Source or "KillSpeed",
						})
					elseif relativeDifference <= -0.07 then
						state.LastDeathOutcome = "Decrease"
						state.PendingDeaths[playerId] = nil
						emitKillSpeed({
							Direction = "Decrease",
							PreSpeed = pending.PreSpeed,
							PostSpeed = postSpeed,
							RelativeDifference = relativeDifference,
							Source = pending.Source or "KillSpeed",
						})
					end
				end
			end
		end
	end

	-- Shared raw WalkSpeed feed. The rolling buffer is intentionally retained
	-- for four seconds so one death can compare its 0.9-second pre-window with
	-- a post-window that expires after 2.5 seconds.
	function observer:OnSpeedSample(event)
		if type(event) ~= "table" then
			return
		end
		local speed = tonumber(
			event.Speed or event.GhostWalkSpeed or event.WalkSpeed
		)
		if not speed or speed <= 0 then
			return
		end
		local now = observationTime(event)
		table.insert(state.SpeedSamples, {
			Time = now,
			Speed = speed,
			Hunting = event.Hunting == true,
		})
		table.sort(state.SpeedSamples, function(left, right)
			return left.Time < right.Time
		end)
		while state.SpeedSamples[1]
			and now - state.SpeedSamples[1].Time > 4 do
			table.remove(state.SpeedSamples, 1)
		end
		evaluatePendingDeaths(now, event.Hunting == true)
	end

	-- Raw death edge. Player identity is tracked here so duplicate callbacks for
	-- one hunter can never count as multiple speed-changing kills.
	function observer:OnPlayerDeath(event)
		if type(event) ~= "table"
			or event.Hunting ~= true
			or event.Multiplayer == false
			or (tonumber(event.OtherAlive) or 0) <= 0
			or (tonumber(event.HuntAge) or 0) < 0.5
			or event.Unique == false
			or event.UniqueKill == false
			or event.UniqueSpeedKill == false then
			return
		end
		local playerId = event.PlayerId or event.Player
		if playerId == nil or state.ProcessedPlayers[playerId] then
			return
		end
		state.ProcessedPlayers[playerId] = true

		local now = observationTime(event)
		local preSpeed = stableMedian(now - 0.9, now - 0.05)
		if not preSpeed then
			return
		end
		state.PendingDeaths[playerId] = {
			Time = now,
			PreSpeed = preSpeed,
			Source = event.Source,
		}
	end

	-- Raw hook: owns the complete same-hunt salt speed classifier.  The adapter
	-- supplies contact facts and ordered samples; OnSaltSpeed remains the
	-- compatibility hook for hosts that already classified an observation.
	function observer:OnSaltSpeedSamples(event)
		if type(event) ~= "table"
			or event.HuntingAtTouch ~= true
			or event.SaltDisturbed ~= true then
			return
		end

		local contactId = event.ContactId
		if contactId == nil then
			contactId = "__default"
		end
		local contact = state.SaltContacts[contactId]
		if not contact then
			contact = {
				SlowObserved = false,
				SlowAt = nil,
				MinimumSpeed = nil,
				Resolved = false,
				Outcome = nil,
			}
			state.SaltContacts[contactId] = contact
		end
		state.LastContactId = contactId
		if contact.Resolved then
			return
		end

		local samples = normalizeSpeedSamples(event.SpeedSamples)
		local preSpeed = tonumber(event.PreSpeed)
		local baselineUsable = event.BaselineReliable == true
			and preSpeed ~= nil
			and preSpeed > 0
		local preSampleCount = math.max(
			0,
			math.floor(tonumber(event.PreSampleCount) or 0)
		)
		local minimumSpeed = math.huge
		local dropCount = 0
		local noDropCount = 0
		local latestSlowAt
		for _, sample in ipairs(samples) do
			minimumSpeed = math.min(minimumSpeed, sample.Speed)
			if baselineUsable then
				local ratio = sample.Speed / preSpeed
				if ratio <= 0.94 then
					dropCount = dropCount + 1
					latestSlowAt = sample.Time
				end
				if ratio >= 0.97 then
					noDropCount = noDropCount + 1
				end
			end
		end

		if dropCount >= 2 and not contact.SlowObserved then
			contact.SlowObserved = true
			contact.SlowAt = latestSlowAt
			contact.MinimumSpeed = minimumSpeed
			contact.Outcome = "Slow"
			state.LastRawOutcome = "Slow"
			self:OnSaltSpeed({
				Outcome = "Slow",
				Confidence = 95,
				Reason = event.SlowReason,
				Source = event.Source or "SaltContact",
			})
		end

		local recoveryCount = 0
		if contact.SlowObserved and baselineUsable then
			local slowAt = contact.SlowAt or math.huge
			local lowSpeed = contact.MinimumSpeed or minimumSpeed
			for _, sample in ipairs(samples) do
				if sample.Time >= slowAt + 0.15
					and sample.Speed >= preSpeed * 0.95
					and sample.Speed >= lowSpeed * 1.06 then
					recoveryCount = recoveryCount + 1
				end
			end
		end

		-- If the first replicated sample already contains the slowdown, infer the
		-- missing baseline from a repeated low phase followed by two recovery
		-- samples.  A Dullahan speed pattern invalidates only this inference path.
		local inferredRecoveryCount = 0
		local canInfer = not contact.SlowObserved
			and preSampleCount == 0
			and #samples >= 4
			and minimumSpeed < math.huge
		if canInfer then
			local lowSampleCount = 0
			local lastLowAt
			for _, sample in ipairs(samples) do
				if sample.Speed <= minimumSpeed * 1.02 then
					lowSampleCount = lowSampleCount + 1
					lastLowAt = sample.Time
				end
			end
			if lowSampleCount >= 2 and lastLowAt then
				for _, sample in ipairs(samples) do
					if sample.Time >= lastLowAt + 0.15
						and sample.Speed >= minimumSpeed * 1.06 then
						inferredRecoveryCount = inferredRecoveryCount + 1
					end
				end
			end
		end

		local inferred = recoveryCount < 2 and inferredRecoveryCount >= 2
		if recoveryCount >= 2 or inferred then
			contact.SlowObserved = true
			contact.MinimumSpeed = minimumSpeed
			contact.Resolved = true
			if inferred and api:GetDetection("Dullahan") then
				contact.Outcome = "SuppressedByDullahan"
				state.LastRawOutcome = contact.Outcome
				return
			end
			contact.Outcome = "Recovered"
			state.LastRawOutcome = "Recovered"
			self:OnSaltSpeed({
				Outcome = "Recovered",
				Inferred = inferred,
				Confidence = 99,
				Reason = event.RecoveryReason,
				Source = event.Source or "SaltContact",
			})
			return
		end

		local age = tonumber(event.Age) or 0
		if not contact.SlowObserved
			and baselineUsable
			and preSampleCount >= 1
			and #samples >= 10
			and noDropCount == #samples
			and (age >= 4 or event.HuntEnded == true) then
			contact.Resolved = true
			contact.Outcome = "NoDrop"
			state.LastRawOutcome = "NoDrop"
			self:OnSaltSpeed({
				Outcome = "NoDrop",
				Confidence = 90,
				Reason = event.NoDropReason,
				Source = event.Source or "SaltContact",
			})
		end
	end

	function observer:OnKillSpeed(event)
		if type(event) ~= "table" then
			return
		end
		local direction = event.Direction
		state.LastKillDirection = direction
		state.LastKillReason = event.Reason
		if direction == "Increase" then
			local count = tonumber(event.Count)
				or state.KillIncreaseCount + 1
			state.KillIncreaseCount = math.max(1, count)
			api:ClearRuleOut("Aswang")
			api:Detect(
				"Aswang",
				event.Reason
					or (
						"Ghost Humanoid WalkSpeed rose toward the expected 20% after "
						.. tostring(state.KillIncreaseCount)
						.. " verified player kill"
						.. (state.KillIncreaseCount == 1 and "" or "s")
					),
				tonumber(event.Confidence)
					or (state.KillIncreaseCount >= 2 and 99 or 97),
				event.Source or "KillSpeed"
			)
			api:RuleOut(
				"Keres",
				"the death-linked speed change was upward rather than downward",
				94
			)
		elseif direction == "Decrease" then
			if state.StrongSaltFinding then
				return
			end
			api:RuleOut(
				"Aswang",
				"the death-linked speed change was downward rather than upward",
				94
			)
		else
			return
		end
		api:Refresh()
	end

	function observer:Snapshot()
		return {
			LastSaltOutcome = state.LastSaltOutcome,
			LastSaltReason = state.LastSaltReason,
			SaltConfidence = state.SaltConfidence,
			StrongSaltFinding = state.StrongSaltFinding,
			KillIncreaseCount = state.KillIncreaseCount,
			LastKillDirection = state.LastKillDirection,
			LastKillReason = state.LastKillReason,
			LastContactId = state.LastContactId,
			LastRawOutcome = state.LastRawOutcome,
			LastDeathOutcome = state.LastDeathOutcome,
			SpeedSampleCount = #state.SpeedSamples,
			PendingDeathCount = (function()
				local count = 0
				for _ in pairs(state.PendingDeaths) do
					count = count + 1
				end
				return count
			end)(),
		}
	end

	return observer
end

return {
	Name = "Aswang",
	Evidence = {"EMFLevel5", "GhostWriting", "Wither"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 95,
	ObservationKeys = {"SaltContactSpeed", "KillSpeedChange"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "During one hunt, direct salt contact is followed by repeated lower WalkSpeed samples and then recovery toward the pre-contact speed.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
				Conditions = "The contact and temporary same-hunt slowdown are the core pattern; disturbance corroborates the contact but is not required for the speed comparison.",
			},
		},
		["Maybe"] = {
			{
				Text = "A hunting ghost touched salt and showed a repeated speed dip, but recovery has not been sampled yet.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
				Conditions = "Keep sampling through the temporary slowdown window before upgrading confidence.",
			},
			{
				Text = "Across controlled hunt-state comparisons, WalkSpeed rises by about 20% after each unique hunter kill.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
				Conditions = "Compare stable speeds before and after the kill rather than relying on one estimate.",
			},
		},
		["Idk"] = {
			{
				Text = "Disturbed salt by itself or a slowdown after contact outside a hunt is not diagnostic for Aswang.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Caveat",
			},
		},
	},
}
