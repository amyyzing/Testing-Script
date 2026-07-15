return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "SpeedMath requires Events")
	local Specification = type(dependencies.Specification) == "table"
		and dependencies.Specification or {}
	local PairSpec = type(Specification.SpeedPairs) == "table"
		and Specification.SpeedPairs or {}
	local MathSpec = type(Specification.SpeedMath) == "table"
		and Specification.SpeedMath or {}
	local WendigoSpec = type(Specification.Wendigo) == "table"
		and Specification.Wendigo or {}

	local SpeedMath = {}
	SpeedMath.__index = SpeedMath

	local DEFAULT_MULTIPLIERS = {0.5, 0.75, 1, 1.25, 1.5, 2}
	local MAP_FACTORS = {Small = 1, Medium = 1.05, Large = 1.1}

	local function validMultipliers(input)
		local result = {}
		for _, value in ipairs(type(input) == "table" and input or DEFAULT_MULTIPLIERS) do
			local number = tonumber(value)
			if number and number > 0 and math.abs(number - 1.75) > 0.0001 then
				table.insert(result, number)
			end
		end
		if #result == 0 then
			for _, number in ipairs(DEFAULT_MULTIPLIERS) do
				table.insert(result, number)
			end
		end
		return result
	end

	local function mapFactor(event, context)
		local explicit = tonumber(Events.Read(event, "MapFactor"))
			or tonumber(type(context) == "table" and context.MapFactor)
		if explicit and explicit > 0 then
			return explicit
		end
		return MAP_FACTORS[tostring(
			Events.Read(event, "MapSize")
				or (type(context) == "table" and context.MapSize)
		)] or 1
	end

	local function closestFit(normalizedSpeed, base, multipliers, baseTolerance)
		local best = nil
		baseTolerance = math.max(0, tonumber(baseTolerance) or 0.1)
		for _, multiplier in ipairs(multipliers) do
			local expected = base * multiplier
			local observedBase = normalizedSpeed / multiplier
			local candidate = {
				Base = base,
				Multiplier = multiplier,
				Expected = expected,
				Error = math.abs(normalizedSpeed - expected),
				ObservedBase = observedBase,
				BaseError = math.abs(observedBase - base),
				BaseTolerance = baseTolerance,
			}
			candidate.Tolerance = baseTolerance * multiplier
			candidate.Qualified = candidate.BaseError <= baseTolerance
			candidate.Matched = candidate.Qualified
			candidate.Fits = candidate.Qualified
			if not best or candidate.BaseError < best.BaseError then
				best = candidate
			end
		end
		return best
	end

	local function copyArray(values)
		local result = {}
		for index, value in ipairs(values) do
			result[index] = Events.Copy(value)
		end
		return result
	end

	function SpeedMath.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "SpeedMath",
			Category = "Analyzer",
			Status = "Idle",
			RequiredTransitions = math.max(2, math.floor(
				tonumber(options.RequiredTransitions)
					or tonumber(WendigoSpec.RequiredTransitions)
					or 2
			)),
			MinimumSanitySpread = tonumber(options.MinimumSanitySpread)
				or tonumber(WendigoSpec.MinimumSanitySpread) or 0.5,
			WendigoBaseIntercept = tonumber(options.WendigoBaseIntercept)
				or tonumber(WendigoSpec.BaseIntercept) or 14,
			WendigoSanitySlope = tonumber(options.WendigoSanitySlope)
				or tonumber(WendigoSpec.SanitySlope) or 0.05,
			WendigoNonHuntMultiplier = tonumber(options.WendigoNonHuntMultiplier)
				or tonumber(WendigoSpec.NonHuntMultiplier) or 1.75,
			_context = nil,
			transitionSnapshots = {},
			lastMath = nil,
			lastCurveSignature = nil,
			startupNonHuntObserved = false,
		}, SpeedMath)
	end

	SpeedMath.New = SpeedMath.new

	function SpeedMath:Start(context)
		self._context = context or {}
		self.Status = "Active"
	end

	function SpeedMath:_emit(event)
		if type(self._context.Emit) == "function" then
			self._context.Emit(event)
		end
	end

	function SpeedMath:_flat(event)
		local speed = tonumber(Events.Read(event, "Speed"))
		if not speed or speed <= 0 then
			return
		end
		local factor = mapFactor(event, self._context)
		local normalized = speed / factor
		local multipliers = validMultipliers(Events.Read(event, "ValidMultipliers"))
		local fitTolerance = tonumber(MathSpec.FlatBaseTolerance) or 0.1
		local fits = {
			Normal = closestFit(
				normalized,
				tonumber(PairSpec.NormalHuntingBase) or 11,
				multipliers,
				fitTolerance
			),
			Oni = closestFit(
				normalized,
				tonumber(PairSpec.OniHuntingBase) or 13.5,
				multipliers,
				fitTolerance
			),
		}
		local bestName
		local best
		for name, fit in pairs(fits) do
			if not best or fit.Error < best.Error then
				bestName = name
				best = fit
			end
		end
		local payload = {
			Speed = speed,
			PairCount = tonumber(Events.Read(event, "PairCount")),
			RequiredPairs = tonumber(Events.Read(event, "RequiredPairs")),
			MapFactor = factor,
			NormalizedSpeed = normalized,
			Fits = fits,
			Best = bestName,
			Qualified = best and best.Qualified or false,
			Completed = true,
			BaseSpeed = best and best.Base or nil,
			PhaseDependent = false,
			ValidMultipliers = multipliers,
		}
		self.lastMath = payload
		self:_emit({
			Type = Events.Types.HuntSpeedMathResult,
			HuntId = event.HuntId,
			Hunting = true,
			Source = self.Name,
			Payload = payload,
		})
	end

	function SpeedMath:_nonHunt(event)
		local speed = tonumber(
			Events.Read(event, "Speed")
				or Events.Read(event, "WalkSpeed")
		)
		if not speed or speed <= 0 then return end
		local factor = mapFactor(event, self._context)
		local normalized = speed / factor
		local base = tonumber(PairSpec.NormalNonHuntingBase) or 11
		local multiplier = tonumber(PairSpec.NonHuntingMultiplier) or 1.75
		local fit = closestFit(
			normalized,
			base,
			{multiplier},
			tonumber(MathSpec.FlatBaseTolerance) or 0.1
		)
		self:_emit({
			Type = Events.Types.NonHuntSpeedMathResult,
			HuntId = event.HuntId,
			Hunting = false,
			Source = self.Name,
			Payload = {
				Speed = speed,
				MapFactor = factor,
				NormalizedSpeed = normalized,
				BaseSpeed = base,
				Multiplier = multiplier,
				Fit = fit,
				Matched = fit ~= nil and fit.Qualified == true,
				Qualified = true,
				Completed = true,
				Reason = fit ~= nil and fit.Qualified == true
					and "settled non-hunting speed fit base 11"
					or "settled non-hunting speed did not fit base 11",
			},
		})
	end

	function SpeedMath:_transition(event)
		local sanity = tonumber(Events.Read(event, "AverageSanity"))
		local speed = tonumber(
			Events.Read(event, "BaselineSpeed")
				or Events.Read(event, "Speed")
				or Events.Read(event, "WalkSpeed")
		)
		if not sanity or not speed or speed <= 0 or type(event.Hunting) ~= "boolean" then
			return
		end
		local previous = self.transitionSnapshots[#self.transitionSnapshots]
		if previous and previous.Hunting == event.Hunting then
			self.transitionSnapshots[#self.transitionSnapshots] = nil
		end
		table.insert(self.transitionSnapshots, {
			Time = event.Time,
			Hunting = event.Hunting,
			HuntId = event.HuntId,
			AverageSanity = math.clamp(sanity, 0, 100),
			Speed = speed,
			MapFactor = mapFactor(event, self._context),
			ValidMultipliers = validMultipliers(Events.Read(event, "ValidMultipliers")),
		})
		while #self.transitionSnapshots > self.RequiredTransitions do
			table.remove(self.transitionSnapshots, 1)
		end
		if #self.transitionSnapshots < self.RequiredTransitions then
			return
		end

		local lowest = 101
		local highest = -1
		local matchedMultiplier = nil
		local matched = true
		local reason = tostring(self.RequiredTransitions)
			.. " alternating hunt-state snapshots matched the Wendigo sanity curve"
		for _, snapshot in ipairs(self.transitionSnapshots) do
			lowest = math.min(lowest, snapshot.AverageSanity)
			highest = math.max(highest, snapshot.AverageSanity)
			local normalized = snapshot.Speed / snapshot.MapFactor
			local base = self.WendigoBaseIntercept
				- snapshot.AverageSanity * self.WendigoSanitySlope
			-- 175% is the known non-hunting state factor, not a valid hunting
			-- difficulty. Fit it only for non-hunt transition snapshots.
			local fit = closestFit(
				normalized,
				base,
				snapshot.Hunting and snapshot.ValidMultipliers
					or {self.WendigoNonHuntMultiplier},
				tonumber(MathSpec.WendigoBaseTolerance) or 0.02
			)
			if not fit or not fit.Qualified then
				matched = false
				reason = "a transition speed did not fit the Wendigo sanity curve"
				break
			end
			if snapshot.Hunting and matchedMultiplier
				and math.abs(matchedMultiplier - fit.Multiplier) > 0.001 then
				matched = false
				reason = "hunting transition speeds required different difficulty multipliers"
				break
			end
			if snapshot.Hunting then
				matchedMultiplier = fit.Multiplier
			end
		end
		local spread = highest - lowest
		local discriminated = spread + 1e-6 >= self.MinimumSanitySpread
		local qualified = not matched or discriminated
		local outcome
		if not matched then
			-- A mathematically impossible curve is a qualified negative even when
			-- sanity barely moved. Sanity spread is only needed to prove a match.
			outcome = "Rejected"
		elseif discriminated then
			outcome = "Matched"
		else
			outcome = "Inconclusive"
			reason = "the curve fit, but transition sanity had not changed enough to distinguish Wendigo"
		end
		local signature = tostring(self.transitionSnapshots[1].Time)
			.. ":" .. tostring(
				self.transitionSnapshots[#self.transitionSnapshots].Time
			)
		if signature == self.lastCurveSignature then
			return
		end
		self.lastCurveSignature = signature
		self:_emit({
			Type = Events.Types.WendigoCurveResult,
			HuntId = event.HuntId,
			Hunting = event.Hunting,
			Source = self.Name,
			Payload = {
				Matched = matched and discriminated,
				CurveFit = matched,
				Outcome = outcome,
				Qualified = qualified,
				Completed = true,
				Snapshots = copyArray(self.transitionSnapshots),
				Multiplier = matchedMultiplier,
				NonHuntMultiplier = self.WendigoNonHuntMultiplier,
				RequiredTransitions = self.RequiredTransitions,
				SanitySpread = spread,
				MinimumSanitySpread = self.MinimumSanitySpread,
				Reason = reason,
			},
		})
	end

	function SpeedMath:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or type(event) ~= "table" then
			return
		end
		local kind = event.Type or event.Kind
		if kind == Events.Types.FlatHuntSpeed then
			self:_flat(event)
		elseif kind == Events.Types.HuntTransitionSettled then
			if event.Hunting == false then self:_nonHunt(event) end
			self:_transition(event)
		elseif kind == Events.Types.WalkSpeedChanged
			and event.Hunting == false
			and self.startupNonHuntObserved ~= true
			and string.find(tostring(event.Source or ""), "Startup", 1, true) then
			self.startupNonHuntObserved = true
			self:_nonHunt(event)
		end
	end

	function SpeedMath:Stop()
		self.Status = "Stopped"
	end

	function SpeedMath:Reset()
		table.clear(self.transitionSnapshots)
		self.lastMath = nil
		self.lastCurveSignature = nil
		self.startupNonHuntObserved = false
		self.Status = "Idle"
	end

	function SpeedMath:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function SpeedMath:Snapshot()
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			TransitionSnapshots = copyArray(self.transitionSnapshots),
			RequiredTransitions = self.RequiredTransitions,
			MinimumSanitySpread = self.MinimumSanitySpread,
			LastMath = Events.Copy(self.lastMath),
		}
	end

	return SpeedMath
end
