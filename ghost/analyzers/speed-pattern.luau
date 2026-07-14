return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "SpeedPattern requires Events")

	local SpeedPattern = {}
	SpeedPattern.__index = SpeedPattern

	local function median(values)
		local sorted = {}
		for index, value in ipairs(values) do
			sorted[index] = value
		end
		table.sort(sorted)
		if #sorted == 0 then
			return nil
		end
		local middle = math.floor((#sorted + 1) / 2)
		if #sorted % 2 == 1 then
			return sorted[middle]
		end
		return (sorted[middle] + sorted[middle + 1]) / 2
	end

	local function repeatable(left, right, scale, tolerance)
		return math.abs(left - right)
			<= math.max(tolerance, math.abs(scale) * 0.006)
	end

	local function allRepeatable(values, center, tolerance)
		if not center or #values == 0 then
			return false
		end
		for _, value in ipairs(values) do
			if not repeatable(value, center, center, tolerance) then
				return false
			end
		end
		return true
	end

	local function sampleValues(event)
		local raw = Events.Read(event, "Samples")
		local samples = {}
		for _, sample in ipairs(type(raw) == "table" and raw or {}) do
			if type(sample) == "table"
				and type(sample.Invisible) == "boolean"
				and tonumber(sample.Speed) then
				table.insert(samples, sample)
			end
		end
		return samples
	end

	local function buildPairs(samples, requiredPairs)
		local pairs = {}
		for index = 1, requiredPairs * 2, 2 do
			local first = samples[index]
			local second = samples[index + 1]
			if not first or not second or first.Invisible == second.Invisible then
				return {}
			end
			table.insert(pairs, {
				Pair = #pairs + 1,
				FirstSpeed = tonumber(first.Speed),
				SecondSpeed = tonumber(second.Speed),
				FirstInvisible = first.Invisible,
				SecondInvisible = second.Invisible,
				InvisibleSpeed = first.Invisible and tonumber(first.Speed)
					or tonumber(second.Speed),
				VisibleSpeed = first.Invisible and tonumber(second.Speed)
					or tonumber(first.Speed),
			})
		end
		return pairs
	end

	function SpeedPattern.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "SpeedPattern",
			Category = "Analyzer",
			Status = "Idle",
			RequiredPairs = math.max(1, math.floor(tonumber(options.RequiredPairs) or 7)),
			ExpectedPhantomRatio = tonumber(options.ExpectedPhantomRatio) or (13.5 / 11),
			RatioTolerance = tonumber(options.RatioTolerance) or 0.05,
			EqualityTolerance = tonumber(options.EqualityTolerance) or 0.05,
			IncreaseEpsilon = tonumber(options.IncreaseEpsilon) or 0.05,
			_context = nil,
			huntId = nil,
			processed = {},
			sampleCount = 0,
			pairCount = 0,
			increaseCount = 0,
			dullahanEmitted = false,
			dullahanAbsentEmitted = false,
			phantomEmitted = false,
			flatEmitted = false,
			lastOutcome = nil,
		}, SpeedPattern)
	end

	SpeedPattern.New = SpeedPattern.new

	function SpeedPattern:Start(context)
		self._context = context or {}
		self.Status = "Active"
	end

	function SpeedPattern:_emit(event)
		if type(self._context.Emit) == "function" then
			self._context.Emit(event)
		end
	end

	function SpeedPattern:_clearHunt(huntId)
		self.huntId = huntId
		table.clear(self.processed)
		self.sampleCount = 0
		self.pairCount = 0
		self.increaseCount = 0
		self.dullahanEmitted = false
		self.dullahanAbsentEmitted = false
		self.phantomEmitted = false
		self.flatEmitted = false
		self.lastOutcome = nil
	end

	function SpeedPattern:_absorb(samples)
		for _, sample in ipairs(samples) do
			local key = sample.SampleId
				or tostring(sample.Time) .. ":" .. tostring(sample.Invisible)
			if not self.processed[key] then
				self.processed[key] = true
				self.sampleCount = self.sampleCount + 1
			end
		end
	end

	function SpeedPattern:_emitDullahanAbsent(event, pairs, reason)
		if self.dullahanEmitted or self.dullahanAbsentEmitted then
			return
		end
		self.dullahanAbsentEmitted = true
		self.lastOutcome = Events.Types.DullahanPatternAbsent
		self:_emit({
			Type = Events.Types.DullahanPatternAbsent,
			HuntId = event.HuntId,
			Hunting = true,
			Source = self.Name,
			Payload = {
				SampleCount = self.sampleCount,
				PairCount = self.pairCount,
				RequiredPairs = self.RequiredPairs,
				IncreaseCount = self.increaseCount,
				UpwardSteps = self.increaseCount,
				UpwardPairs = self.increaseCount,
				RequiredUpwardSteps = self.RequiredPairs,
				RequiredUpwardPairs = self.RequiredPairs,
				Qualified = true,
				Completed = true,
				Pairs = Events.Copy(pairs),
				Reason = reason,
			},
		})
	end

	function SpeedPattern:_analyzeWindow(event)
		local requiredPairs = math.max(
			self.RequiredPairs,
			math.floor(tonumber(Events.Read(event, "RequiredPairs")) or 0)
		)
		local samples = sampleValues(event)
		if #samples < requiredPairs * 2 then
			return
		end
		local pairs = buildPairs(samples, requiredPairs)
		if #pairs ~= requiredPairs then
			return
		end
		self.RequiredPairs = requiredPairs
		self:_absorb(samples)
		self.pairCount = #pairs

		local invisible = {}
		local visible = {}
		local all = {}
		local upwardPairs = 0
		for _, pair in ipairs(pairs) do
			table.insert(invisible, pair.InvisibleSpeed)
			table.insert(visible, pair.VisibleSpeed)
			table.insert(all, pair.FirstSpeed)
			table.insert(all, pair.SecondSpeed)
			if pair.SecondSpeed - pair.FirstSpeed + 1e-6 >= self.IncreaseEpsilon then
				upwardPairs = upwardPairs + 1
			end
		end
		-- Only within-pair rises count. A reset or decrease between two pairs is
		-- intentionally ignored, matching Dullahan's step-and-reset behavior.
		self.increaseCount = upwardPairs

		local invisibleSpeed = median(invisible)
		local visibleSpeed = median(visible)
		local invisibleRepeats = allRepeatable(
			invisible,
			invisibleSpeed,
			self.EqualityTolerance
		)
		local visibleRepeats = allRepeatable(
			visible,
			visibleSpeed,
			self.EqualityTolerance
		)
		local phasesRepeat = invisibleRepeats and visibleRepeats
		local ratio = visibleSpeed and visibleSpeed > 0
			and invisibleSpeed / visibleSpeed or nil

		if phasesRepeat then
			self:_emitDullahanAbsent(
				event,
				pairs,
				"seven settled pairs repeated stable phase speeds instead of Dullahan's differing upward-step pattern"
			)
			if ratio
				and math.abs(ratio - self.ExpectedPhantomRatio) <= self.RatioTolerance then
				if not self.phantomEmitted then
					self.phantomEmitted = true
					self.lastOutcome = Events.Types.PhantomPattern
					self:_emit({
						Type = Events.Types.PhantomPattern,
						HuntId = event.HuntId,
						Hunting = true,
						Source = self.Name,
						Payload = {
							Qualified = true,
							Completed = true,
							Outcome = "PhaseDependent",
							VisibleSpeed = visibleSpeed,
							InvisibleSpeed = invisibleSpeed,
							Ratio = ratio,
							PairCount = self.pairCount,
							RequiredPairs = self.RequiredPairs,
							RepeatedPairs = true,
							Pairs = Events.Copy(pairs),
							Samples = Events.Copy(samples),
							Reason = "seven settled pairs repeated the 13.5/11 Phantom phase ratio",
						},
					})
				end
				return
			end

			local flatSpeed = median(all)
			local flat = allRepeatable(all, flatSpeed, self.EqualityTolerance)
			if flat and not self.flatEmitted then
				self.flatEmitted = true
				self.lastOutcome = Events.Types.FlatHuntSpeed
				self:_emit({
					Type = Events.Types.FlatHuntSpeed,
					HuntId = event.HuntId,
					Hunting = true,
					Source = self.Name,
					Payload = {
						Qualified = true,
						Completed = true,
						Outcome = "Equal",
						PhaseDependent = false,
						Speed = flatSpeed,
						PairCount = self.pairCount,
						RequiredPairs = self.RequiredPairs,
						RepeatedPairs = true,
						Pairs = Events.Copy(pairs),
						Samples = Events.Copy(samples),
						AverageSanity = Events.Read(event, "AverageSanity"),
						MapFactor = Events.Read(event, "MapFactor"),
						MapSize = Events.Read(event, "MapSize"),
						ValidMultipliers = Events.Read(event, "ValidMultipliers"),
						Reason = "seven settled visible/invisible pairs shared one hunting speed",
					},
				})
			end
			return
		end

		if upwardPairs >= self.RequiredPairs and not self.dullahanEmitted then
			self.dullahanEmitted = true
			self.lastOutcome = Events.Types.DullahanPattern
			self:_emit({
				Type = Events.Types.DullahanPattern,
				HuntId = event.HuntId,
				Hunting = true,
				Source = self.Name,
				Payload = {
					SampleCount = self.sampleCount,
					PairCount = self.pairCount,
					RequiredPairs = self.RequiredPairs,
					IncreaseCount = upwardPairs,
					UpwardSteps = upwardPairs,
					UpwardPairs = upwardPairs,
					RequiredUpwardSteps = self.RequiredPairs,
					RequiredUpwardPairs = self.RequiredPairs,
					Qualified = true,
					Completed = true,
					Pairs = Events.Copy(pairs),
					Samples = Events.Copy(samples),
					Reason = "all seven settled pairs contained a short upward speed step; decreases between pairs were ignored",
				},
			})
			return
		end

		self:_emitDullahanAbsent(
			event,
			pairs,
			"seven settled pairs did not maintain Dullahan's differing upward-step pattern"
		)
	end

	function SpeedPattern:OnEvent(event)
		if type(event) ~= "table" then
			return
		end
		local kind = event.Type or event.Kind
		if kind == Events.Types.HuntStarted then
			self:_clearHunt(event.HuntId)
			self.Status = "Active"
		elseif kind == Events.Types.SpeedPairWindow then
			if self.huntId == nil or event.HuntId == self.huntId then
				self:_analyzeWindow(event)
			end
		elseif kind == Events.Types.HuntEnded
			and (self.huntId == nil or event.HuntId == self.huntId) then
			-- Fewer than seven complete pairs are insufficient. Never postpone a
			-- qualified negative until HuntEnded; the seven-pair window decides it.
			self.Status = "Dormant"
		end
	end

	function SpeedPattern:Stop()
		self.Status = "Stopped"
	end

	function SpeedPattern:Reset()
		self:_clearHunt(nil)
		self.Status = "Idle"
	end

	function SpeedPattern:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function SpeedPattern:Snapshot()
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			HuntId = self.huntId,
			SampleCount = self.sampleCount,
			PairCount = self.pairCount,
			RequiredPairs = self.RequiredPairs,
			IncreaseCount = self.increaseCount,
			DullahanEmitted = self.dullahanEmitted,
			DullahanAbsentEmitted = self.dullahanAbsentEmitted,
			PhantomEmitted = self.phantomEmitted,
			FlatEmitted = self.flatEmitted,
			LastOutcome = self.lastOutcome,
		}
	end

	return SpeedPattern
end
