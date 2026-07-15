return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "EvidenceCombination requires Events")

	local EvidenceCombination = {}
	EvidenceCombination.__index = EvidenceCombination

	local function normalizedEvidence(event)
		local input = Events.Read(event, "Evidence")
		local result = {}
		for key, value in pairs(type(input) == "table" and input or {}) do
			if type(key) == "string" and value == true then result[key] = true end
		end
		return result
	end

	local function signature(evidence)
		local names = {}
		for name in pairs(evidence) do table.insert(names, name) end
		table.sort(names)
		return table.concat(names, "|")
	end

	local function evidenceSet(profile)
		local result = {}
		for _, name in ipairs(type(profile) == "table" and profile.Evidence or {}) do
			result[name] = true
		end
		return result
	end

	function EvidenceCombination.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "EvidenceCombination",
			Category = "Analyzer",
			Status = "Idle",
			_context = nil,
			_catalog = options.Catalog,
			_lastSignature = nil,
			_lastResult = nil,
		}, EvidenceCombination)
	end

	EvidenceCombination.New = EvidenceCombination.new

	function EvidenceCombination:Start(context)
		self._context = context or {}
		self._catalog = self._catalog or self._context.Catalog
		self.Status = "Active"
	end

	function EvidenceCombination:_classify(evidence)
		local count = 0
		for _ in pairs(evidence) do count = count + 1 end
		local orb = evidence.GhostOrb == true
		local realCandidates = {}
		if orb then
			for _, profile in ipairs(type(self._catalog) == "table" and self._catalog or {}) do
				local allowed = evidenceSet(profile)
				local compatible = true
				for name in pairs(evidence) do
					if not allowed[name] then
						compatible = false
						break
					end
				end
				if compatible and type(profile.Name) == "string" then
					table.insert(realCandidates, profile.Name)
				end
			end
		end
		local fourth = orb and count >= 4
		local impossible = orb and count >= 3 and #realCandidates == 0
		return {
			OrbObserved = orb,
			EvidenceCount = count,
			FourthEvidence = fourth,
			ImpossibleCombination = impossible,
			Qualified = fourth or impossible,
			RealCandidates = realCandidates,
			Evidence = evidence,
		}
	end

	function EvidenceCombination:OnEvent(event)
		if self.Status ~= "Active" or type(event) ~= "table"
			or (event.Type or event.Kind) ~= Events.Types.EvidenceSnapshot then
			return false
		end
		local evidence = normalizedEvidence(event)
		local result = self:_classify(evidence)
		self._lastResult = result
		if not result.Qualified then return true end
		local key = signature(evidence)
		if key == self._lastSignature then return true end
		self._lastSignature = key
		if type(self._context.Emit) == "function" then
			self._context.Emit({
				Type = Events.Types.FalseOrb,
				Time = event.Time,
				Source = self.Name,
				Payload = {
					Qualified = true,
					Completed = true,
					FourthEvidence = result.FourthEvidence,
					ImpossibleCombination = result.ImpossibleCombination,
					EvidenceCount = result.EvidenceCount,
					RealCandidates = result.RealCandidates,
					Evidence = result.Evidence,
					Reason = result.FourthEvidence
						and "Ghost Orb formed a fourth evidence observation; normal ghosts have exactly three"
						or "Ghost Orb completed a three-evidence combination that no normal ghost can have",
				},
			})
		end
		return true
	end

	function EvidenceCombination:Stop() self.Status = "Stopped" end
	function EvidenceCombination:Reset()
		self._lastSignature = nil
		self._lastResult = nil
		self.Status = "Idle"
	end
	function EvidenceCombination:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end
	function EvidenceCombination:Snapshot()
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			LastSignature = self._lastSignature,
			LastResult = Events.Copy(self._lastResult),
		}
	end

	return EvidenceCombination
end
