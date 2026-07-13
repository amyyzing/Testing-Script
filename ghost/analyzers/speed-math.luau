return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "SpeedMath requires Events")

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

	local function mapFactor(event)
		local explicit = tonumber(Events.Read(event, "MapFactor"))
		if explicit and explicit > 0 then
			return explicit
		end
		return MAP_FACTORS[tostring(Events.Read(event, "MapSize"))] or 1
	end

	local function closestFit(normalizedSpeed, base, multipliers)
		local best = nil
		for _, multiplier in ipairs(multipliers) do
			local expected = base * multiplier
			local candidate = {
				Base = base,
				Multiplier = multiplier,
				Expected = expected,
				Error = math.abs(normalizedSpeed - expected),
			}
			candidate.Tolerance = math.max(0.18, expected * 0.02)
			candidate.Qualified = candidate.Error <= candidate.Tolerance
			candidate.Matched = candidate.Qualified
			candidate.Fits = candidate.Qualified
			if not best or candidate.Error < best.Error then
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
			MinimumSanitySpread = tonumber(options.MinimumSanitySpread) or 8,
			_context = nil,
			transitionSnapshots = {},
			lastMath = nil,
			lastCurveSignature = nil,
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
		local factor = mapFactor(event)
		local normalized = speed / factor
		local sanity = tonumber(Events.Read(event, "AverageSanity"))
		local multipliers = validMultipliers(Events.Read(event, "ValidMultipliers"))
		local fits = {
			Normal = closestFit(normalized, 11, multipliers),
			Oni = closestFit(normalized, 13.5, multipliers),
		}
		if sanity then
			fits.Wendigo = closestFit(normalized, 14 - math.clamp(sanity, 0, 100) * 0.05, multipliers)
		end
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
			MapFactor = factor,
			NormalizedSpeed = normalized,
			AverageSanity = sanity,
			Fits = fits,
			Best = bestName,
			Qualified = best and best.Qualified or false,
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
			MapFactor = mapFactor(event),
			ValidMultipliers = validMultipliers(Events.Read(event, "ValidMultipliers")),
		})
		while #self.transitionSnapshots > 3 do
			table.remove(self.transitionSnapshots, 1)
		end
		if #self.transitionSnapshots < 3 then
			return
		end

		local lowest = 101
		local highest = -1
		local matchedMultiplier = nil
		local matched = true
		local reason = "three alternating hunt-state snapshots matched the Wendigo sanity curve"
		for _, snapshot in ipairs(self.transitionSnapshots) do
			lowest = math.min(lowest, snapshot.AverageSanity)
			highest = math.max(highest, snapshot.AverageSanity)
			local normalized = snapshot.Speed / snapshot.MapFactor
			local base = 14 - snapshot.AverageSanity * 0.05
			-- 175% is the known non-hunting state factor, not a valid hunting
			-- difficulty. Fit it only for non-hunt transition snapshots.
			local fit = closestFit(
				normalized,
				base,
				snapshot.Hunting and snapshot.ValidMultipliers or {1.75}
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
		if spread < self.MinimumSanitySpread then
			matched = false
			reason = "transition sanity spread was too small to qualify the Wendigo curve"
		end
		local signature = tostring(self.transitionSnapshots[1].Time)
			.. ":" .. tostring(self.transitionSnapshots[3].Time)
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
				Matched = matched,
				Outcome = matched and "Matched" or "Rejected",
				Qualified = spread >= self.MinimumSanitySpread,
				Completed = true,
				Snapshots = copyArray(self.transitionSnapshots),
				Multiplier = matchedMultiplier,
				NonHuntMultiplier = 1.75,
				SanitySpread = spread,
				Reason = reason,
			},
		})
	end

	function SpeedMath:OnEvent(event)
		if type(event) ~= "table" then
			return
		end
		local kind = event.Type or event.Kind
		if kind == Events.Types.FlatHuntSpeed then
			self:_flat(event)
		elseif kind == Events.Types.HuntTransitionSettled then
			self:_transition(event)
		end
	end

	function SpeedMath:Stop()
		self.Status = "Stopped"
	end

	function SpeedMath:Reset()
		table.clear(self.transitionSnapshots)
		self.lastMath = nil
		self.lastCurveSignature = nil
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
			LastMath = Events.Copy(self.lastMath),
		}
	end

	return SpeedMath
end
