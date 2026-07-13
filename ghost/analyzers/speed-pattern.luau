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
		return math.abs(left - right) <= math.max(tolerance, math.abs(scale) * 0.012)
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

	function SpeedPattern.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "SpeedPattern",
			Category = "Analyzer",
			Status = "Idle",
			ExpectedPhantomRatio = tonumber(options.ExpectedPhantomRatio) or (13.5 / 11),
			RatioTolerance = tonumber(options.RatioTolerance) or 0.05,
			EqualityTolerance = tonumber(options.EqualityTolerance) or 0.1,
			IncreaseEpsilon = tonumber(options.IncreaseEpsilon) or 0.001,
			_context = nil,
			huntId = nil,
			processed = {},
			lastSpeed = nil,
			sampleCount = 0,
			increaseCount = 0,
			dullahanEmitted = false,
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
		self.lastSpeed = nil
		self.sampleCount = 0
		self.increaseCount = 0
		self.dullahanEmitted = false
		self.phantomEmitted = false
		self.flatEmitted = false
		self.lastOutcome = nil
	end

	function SpeedPattern:_absorb(samples)
		for _, sample in ipairs(samples) do
			local key = sample.SampleId or tostring(sample.Time) .. ":" .. tostring(sample.Invisible)
			if not self.processed[key] then
				self.processed[key] = true
				local speed = tonumber(sample.Speed)
				if speed then
					self.lastSpeed = speed
					self.sampleCount = self.sampleCount + 1
				end
			end
		end
	end

	function SpeedPattern:_analyzeWindow(event)
		local samples = sampleValues(event)
		if #samples < 4 then
			return
		end
		self:_absorb(samples)
		local windowIncreaseCount = 0
		for index = 2, #samples do
			if samples[index].Speed - samples[index - 1].Speed >= self.IncreaseEpsilon then
				windowIncreaseCount = windowIncreaseCount + 1
			end
		end
		-- Preserve the strongest qualified window; a later decrease never erases
		-- it, but separated rises across an entire hunt are not accumulated.
		self.increaseCount = math.max(self.increaseCount, windowIncreaseCount)

		if windowIncreaseCount >= 3 and not self.dullahanEmitted then
			self.dullahanEmitted = true
			self.lastOutcome = Events.Types.DullahanPattern
			self:_emit({
				Type = Events.Types.DullahanPattern,
				HuntId = event.HuntId,
				Hunting = true,
				Source = self.Name,
				Payload = {
					SampleCount = self.sampleCount,
					IncreaseCount = windowIncreaseCount,
					UpwardSteps = windowIncreaseCount,
					RequiredUpwardSteps = 3,
					Qualified = true,
					Samples = Events.Copy(samples),
					Reason = "settled hunt speed rose through at least three short steps; decreases were ignored",
				},
			})
			return
		end

		local invisible = {}
		local visible = {}
		local all = {}
		for _, sample in ipairs(samples) do
			table.insert(all, sample.Speed)
			table.insert(sample.Invisible and invisible or visible, sample.Speed)
		end
		if #invisible ~= 2 or #visible ~= 2 then
			return
		end
		local invisibleSpeed = median(invisible)
		local visibleSpeed = median(visible)
		local invisibleRepeats = repeatable(invisible[1], invisible[2], invisibleSpeed, self.EqualityTolerance)
		local visibleRepeats = repeatable(visible[1], visible[2], visibleSpeed, self.EqualityTolerance)
		local ratio = visibleSpeed and visibleSpeed > 0 and invisibleSpeed / visibleSpeed or nil
		if invisibleRepeats and visibleRepeats and ratio
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
						Outcome = "PhaseDependent",
						VisibleSpeed = visibleSpeed,
						InvisibleSpeed = invisibleSpeed,
						Ratio = ratio,
						Samples = Events.Copy(samples),
						Reason = "two settled invisible/visible pairs repeated the 13.5/11 Phantom speed ratio",
					},
				})
			end
			return
		end

		local flatSpeed = median(all)
		local flat = true
		for _, speed in ipairs(all) do
			if not repeatable(speed, flatSpeed, flatSpeed, self.EqualityTolerance) then
				flat = false
				break
			end
		end
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
					Outcome = "Equal",
					PhaseDependent = false,
					Speed = flatSpeed,
					Samples = Events.Copy(samples),
					AverageSanity = Events.Read(event, "AverageSanity"),
					MapFactor = Events.Read(event, "MapFactor"),
					MapSize = Events.Read(event, "MapSize"),
					ValidMultipliers = Events.Read(event, "ValidMultipliers"),
					Reason = "two settled invisible/visible pairs shared one hunting speed",
				},
			})
		end
	end

	function SpeedPattern:OnEvent(event)
		if type(event) ~= "table" then
			return
		end
		local kind = event.Type or event.Kind
		if kind == Events.Types.HuntStarted then
			self:_clearHunt(event.HuntId)
		elseif kind == Events.Types.SpeedPairWindow then
			if self.huntId == nil or event.HuntId == self.huntId then
				self:_analyzeWindow(event)
			end
		elseif kind == Events.Types.HuntEnded and (self.huntId == nil or event.HuntId == self.huntId) then
			if self.sampleCount >= 4 and self.increaseCount < 3 and not self.dullahanEmitted then
				self:_emit({
					Type = Events.Types.DullahanPatternAbsent,
					HuntId = event.HuntId,
					-- This completed result describes samples from the just-ended
					-- hunt, so profiles should evaluate it as a hunting observation.
					Hunting = true,
					Source = self.Name,
					Payload = {
						SampleCount = self.sampleCount,
						IncreaseCount = self.increaseCount,
						UpwardSteps = self.increaseCount,
						RequiredUpwardSteps = 3,
						Qualified = true,
						Completed = true,
						Reason = "a qualified hunt ended without three settled upward speed steps",
					},
				})
			end
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
			IncreaseCount = self.increaseCount,
			DullahanEmitted = self.dullahanEmitted,
			PhantomEmitted = self.phantomEmitted,
			FlatEmitted = self.flatEmitted,
			LastOutcome = self.lastOutcome,
		}
	end

	return SpeedPattern
end
