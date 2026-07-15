return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "SpeedPattern requires Events")
	local Specification = type(dependencies.Specification) == "table"
		and dependencies.Specification or {}
	local PairSpec = type(Specification.SpeedPairs) == "table"
		and Specification.SpeedPairs or {}

	local SpeedPattern = {}
	SpeedPattern.__index = SpeedPattern
	local DEFAULT_MULTIPLIERS = {0.5, 0.75, 1, 1.25, 1.5, 2}
	local MAP_FACTORS = {Small = 1, Medium = 1.05, Large = 1.1}

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

	local function mapFactor(event)
		local explicit = tonumber(Events.Read(event, "MapFactor"))
		if explicit and explicit > 0 then return explicit end
		return MAP_FACTORS[tostring(Events.Read(event, "MapSize"))] or 1
	end

	local function huntingMultipliers(input)
		local allowed = type(PairSpec.HuntingMultipliers) == "table"
			and PairSpec.HuntingMultipliers or DEFAULT_MULTIPLIERS
		local permitted = {}
		for _, raw in ipairs(allowed) do
			local value = tonumber(raw)
			if value and value > 0 then permitted[value] = true end
		end
		local result = {}
		for _, raw in ipairs(type(input) == "table" and input or allowed) do
			local value = tonumber(raw)
			if value and permitted[value] then table.insert(result, value) end
		end
		if #result == 0 then
			for _, raw in ipairs(allowed) do
				local value = tonumber(raw)
				if value and value > 0 then table.insert(result, value) end
			end
		end
		return result
	end

	local function phantomFit(event, visibleSpeed, invisibleSpeed)
		local factor = mapFactor(event)
		local normalizedVisible = visibleSpeed / factor
		local normalizedInvisible = invisibleSpeed / factor
		local visibleBase = tonumber(PairSpec.PhantomVisibleBase) or 11
		local invisibleBase = tonumber(PairSpec.PhantomInvisibleBase) or 13.5
		local tolerance = math.max(0, tonumber(PairSpec.PhantomBaseTolerance) or 0.1)
		local best
		for _, multiplier in ipairs(huntingMultipliers(Events.Read(event, "ValidMultipliers"))) do
			local observedVisibleBase = normalizedVisible / multiplier
			local observedInvisibleBase = normalizedInvisible / multiplier
			local visibleError = math.abs(observedVisibleBase - visibleBase)
			local invisibleError = math.abs(observedInvisibleBase - invisibleBase)
			local candidate = {
				Multiplier = multiplier,
				MapFactor = factor,
				NormalizedVisibleSpeed = normalizedVisible,
				NormalizedInvisibleSpeed = normalizedInvisible,
				VisibleObservedBase = observedVisibleBase,
				InvisibleObservedBase = observedInvisibleBase,
				VisibleBaseError = visibleError,
				InvisibleBaseError = invisibleError,
				BaseTolerance = tolerance,
				Matched = visibleError <= tolerance and invisibleError <= tolerance,
			}
			candidate.Error = math.max(visibleError, invisibleError)
			if not best or candidate.Error < best.Error then best = candidate end
		end
		return best
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
			local invisibleSpeed = first.Invisible and tonumber(first.Speed)
				or tonumber(second.Speed)
			local visibleSpeed = first.Invisible and tonumber(second.Speed)
				or tonumber(first.Speed)
			table.insert(pairs, {
				Pair = #pairs + 1,
				FirstSpeed = tonumber(first.Speed),
				SecondSpeed = tonumber(second.Speed),
				FirstInvisible = first.Invisible,
				SecondInvisible = second.Invisible,
				InvisibleSpeed = invisibleSpeed,
				VisibleSpeed = visibleSpeed,
				Ratio = visibleSpeed and visibleSpeed > 0
					and invisibleSpeed / visibleSpeed or nil,
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
			RequiredPairs = math.max(1, math.floor(tonumber(options.RequiredPairs)
				or tonumber(PairSpec.RequiredPairs) or 7)),
			_context = nil,
			huntId = nil,
			processed = {},
			sampleCount = 0,
			pairCount = 0,
			differentPairCount = 0,
			dullahanEmitted = false,
			dullahanAbsentEmitted = false,
			phantomEmitted = false,
			nonPhantomEmitted = false,
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
		self.differentPairCount = 0
		self.dullahanEmitted = false
		self.dullahanAbsentEmitted = false
		self.phantomEmitted = false
		self.nonPhantomEmitted = false
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
				DifferentPairCount = self.differentPairCount,
				DifferentPairs = self.differentPairCount,
				RequiredDifferentPairs = 1,
				Qualified = true,
				Completed = true,
				Pairs = Events.Copy(pairs),
				Reason = reason,
			},
		})
	end

	function SpeedPattern:_emitNonPhantom(event, windowPairs, samples, outcome, reason, details)
		if self.nonPhantomEmitted or self.phantomEmitted then return end
		self.nonPhantomEmitted = true
		self.lastOutcome = Events.Types.NonPhantomPattern
		local payload = {
			Qualified = true,
			Completed = true,
			Outcome = outcome,
			PairCount = self.pairCount,
			RequiredPairs = self.RequiredPairs,
			Pairs = Events.Copy(windowPairs),
			Samples = Events.Copy(samples),
			Reason = reason,
		}
		for key, value in pairs(type(details) == "table" and details or {}) do
			payload[key] = Events.Copy(value)
		end
		self:_emit({
			Type = Events.Types.NonPhantomPattern,
			HuntId = event.HuntId,
			Hunting = true,
			Source = self.Name,
			Payload = payload,
		})
	end

	function SpeedPattern:_analyzeWindow(event)
		-- The shared classifier owns one exact seven-pair decision window. Extra
		-- reads belong to a later window/hunt and cannot move this boundary.
		local requiredPairs = self.RequiredPairs
		local samples = sampleValues(event)
		if #samples < requiredPairs * 2 then
			return
		end
		local windowSamples = {}
		for index = 1, requiredPairs * 2 do
			windowSamples[index] = samples[index]
		end
		samples = windowSamples
		local pairs = buildPairs(samples, requiredPairs)
		if #pairs ~= requiredPairs then
			return
		end
		self:_absorb(samples)
		self.pairCount = #pairs

		local invisible = {}
		local visible = {}
		local all = {}
		local pairRatios = {}
		local withinPairDifferences = 0
		local pairDriftCount = 0
		local upwardStepCount = 0
		local decreaseStepCount = 0
		local upwardSteps = {}
		local stableVisible = true
		local stableInvisible = true
		local allSamplesEqual = true
		local firstPair = pairs[1]
		local firstSpeed = firstPair and firstPair.FirstSpeed or nil
		for index, pair in ipairs(pairs) do
			table.insert(invisible, pair.InvisibleSpeed)
			table.insert(visible, pair.VisibleSpeed)
			table.insert(all, pair.FirstSpeed)
			table.insert(all, pair.SecondSpeed)
			if pair.Ratio then
				table.insert(pairRatios, pair.Ratio)
			end
			if pair.FirstSpeed ~= pair.SecondSpeed then
				withinPairDifferences = withinPairDifferences + 1
				if pair.SecondSpeed > pair.FirstSpeed then
					upwardStepCount = upwardStepCount + 1
					table.insert(upwardSteps, {
						Kind = "WithinPair",
						Pair = index,
						From = pair.FirstSpeed,
						To = pair.SecondSpeed,
						Delta = pair.SecondSpeed - pair.FirstSpeed,
					})
				else
					decreaseStepCount = decreaseStepCount + 1
				end
			end
			if pair.FirstSpeed ~= firstSpeed or pair.SecondSpeed ~= firstSpeed then
				allSamplesEqual = false
			end
			if index > 1 then
				if pair.VisibleSpeed ~= firstPair.VisibleSpeed then
					stableVisible = false
				end
				if pair.InvisibleSpeed ~= firstPair.InvisibleSpeed then
					stableInvisible = false
				end
				if pair.FirstSpeed ~= firstPair.FirstSpeed
					or pair.SecondSpeed ~= firstPair.SecondSpeed
					or pair.FirstInvisible ~= firstPair.FirstInvisible then
					pairDriftCount = pairDriftCount + 1
				end
				local previous = pairs[index - 1]
				for _, field in ipairs({"FirstSpeed", "SecondSpeed"}) do
					if pair[field] > previous[field] then
						upwardStepCount = upwardStepCount + 1
						table.insert(upwardSteps, {
							Kind = "PairDrift",
							Pair = index,
							Phase = field,
							From = previous[field],
							To = pair[field],
							Delta = pair[field] - previous[field],
						})
					elseif pair[field] < previous[field] then
						decreaseStepCount = decreaseStepCount + 1
					end
				end
			end
		end
		-- Phantom is one stable repeated A/B phase pair whose two absolute bases
		-- share one legal map-normalized difficulty multiplier. A matching ratio
		-- by itself is deliberately insufficient.
		local patternChangeCount = math.max(withinPairDifferences, pairDriftCount)
		self.differentPairCount = patternChangeCount

		local invisibleSpeed = median(invisible)
		local visibleSpeed = median(visible)
		local ratio = median(pairRatios)
		local fit = stableVisible and stableInvisible
			and phantomFit(event, visibleSpeed, invisibleSpeed) or nil

		if stableVisible and stableInvisible and not allSamplesEqual
			and fit and fit.Matched then
			self:_emitDullahanAbsent(
				event,
				pairs,
				"all seven stable blink pairs fit Phantom's absolute 11/13.5 bases with one common multiplier"
			)
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
						PairRatios = Events.Copy(pairRatios),
						MatchedPairCount = self.RequiredPairs,
						PairCount = self.pairCount,
						RequiredPairs = self.RequiredPairs,
						AbsoluteBaseFit = true,
						Multiplier = fit.Multiplier,
						MapFactor = fit.MapFactor,
						NormalizedVisibleSpeed = fit.NormalizedVisibleSpeed,
						NormalizedInvisibleSpeed = fit.NormalizedInvisibleSpeed,
						VisibleObservedBase = fit.VisibleObservedBase,
						InvisibleObservedBase = fit.InvisibleObservedBase,
						BaseTolerance = fit.BaseTolerance,
						Pairs = Events.Copy(pairs),
						Samples = Events.Copy(samples),
						Reason = "seven stable local A/B pairs fit visible base 11 and invisible base 13.5 under one legal map-normalized multiplier",
					},
				})
			end
			return
		end

		if allSamplesEqual then
			self:_emitDullahanAbsent(
				event,
				pairs,
				"all seven local AB pairs contained equal speeds"
			)
			local flatSpeed = median(all)
			if not self.flatEmitted then
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
			self:_emitNonPhantom(
				event,
				pairs,
				samples,
				"Flat",
				"all seven pairs had one identical visible and invisible speed",
				{UpwardStepCount = 0, DecreaseStepCount = 0}
			)
			return
		end

		-- A stable but absolute-base-invalid A/B pattern disproves Phantom, but it
		-- must not bypass Dullahan. If the chronological pair direction contains
		-- a genuine nonzero rise, the normal Dullahan branch below owns it;
		-- decreases and resets still contribute no support.
		if stableVisible and stableInvisible then
			self:_emitNonPhantom(
				event,
				pairs,
				samples,
				"StableInvalidAB",
				"the repeated A/B ratio did not fit Phantom's absolute 11/13.5 bases under one legal multiplier",
				{
					AbsoluteBaseFit = false,
					ClosestFit = fit,
					UpwardStepCount = upwardStepCount,
					DecreaseStepCount = decreaseStepCount,
				}
			)
		end

		-- Once valid Phantom and flat sequences are excluded, Dullahan needs one
		-- genuine upward step of any nonzero magnitude. Decreases and resets are
		-- ignored rather than treated as supporting or excluding evidence.
		if upwardStepCount > 0 and not self.dullahanEmitted then
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
					DifferentPairCount = patternChangeCount,
					DifferentPairs = patternChangeCount,
					WithinPairDifferenceCount = withinPairDifferences,
					PairDriftCount = pairDriftCount,
					PatternChangeCount = patternChangeCount,
					UpwardStepCount = upwardStepCount,
					DecreaseStepCount = decreaseStepCount,
					UpwardSteps = Events.Copy(upwardSteps),
					RequiredDifferentPairs = 1,
					PhantomExcluded = true,
					Qualified = true,
					Completed = true,
					Pairs = Events.Copy(pairs),
					Samples = Events.Copy(samples),
					Reason = "after valid Phantom and flat patterns were excluded, the complete seven-pair window contained a nonzero upward speed step",
				},
			})
			self:_emitNonPhantom(
				event,
				pairs,
				samples,
				"DullahanRise",
				"the non-Phantom sequence contained at least one upward step",
				{
					UpwardStepCount = upwardStepCount,
					DecreaseStepCount = decreaseStepCount,
					UpwardSteps = upwardSteps,
				}
			)
			return
		end

		-- A complete decrease-only/drifting sequence disproves Phantom but is not
		-- evidence for or against Dullahan.
		self:_emitNonPhantom(
			event,
			pairs,
			samples,
			"DecreaseOnly",
			"the complete non-Phantom sequence contained no upward speed step",
			{
				UpwardStepCount = 0,
				DecreaseStepCount = decreaseStepCount,
				PatternChangeCount = patternChangeCount,
			}
		)
	end

	function SpeedPattern:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or type(event) ~= "table" then
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
			DifferentPairCount = self.differentPairCount,
			DullahanEmitted = self.dullahanEmitted,
			DullahanAbsentEmitted = self.dullahanAbsentEmitted,
			PhantomEmitted = self.phantomEmitted,
			NonPhantomEmitted = self.nonPhantomEmitted,
			FlatEmitted = self.flatEmitted,
			LastOutcome = self.lastOutcome,
		}
	end

	return SpeedPattern
end
