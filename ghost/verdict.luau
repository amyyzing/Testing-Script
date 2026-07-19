local GHOSTS = {
	"Aswang", "Banshee", "Demon", "Dullahan", "Dybbuk",
	"Entity", "Ghoul", "Keres", "Leviathan", "Nightmare",
	"Oni", "Phantom", "Ravager", "Revenant", "Shadow",
	"Siren", "Skinwalker", "Specter", "Spirit", "Umbra",
	"Vesper", "Vex", "Wendigo", "Wisp", "Wraith",
}

return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "verdict requires Traffic")
	local EvidenceCatalog = dependencies.EvidenceCatalog
	local Player = dependencies.Player
	local markJournal = dependencies.MarkJournal
	local customFindRow = dependencies.FindJournalRow
	local customApply = dependencies.ApplyJournalState
	local fireSignal = dependencies.FireSignal or firesignal
	local wait = dependencies.Wait or task and task.wait or function() end
	local Verdict = {
		Lists = table.clone(GHOSTS),
		Selected = {},
		RuledOut = {},
		Unknown = {},
		AbilityRuledOut = {},
		Confidence = {},
		NegativeConfidence = {},
		Reasons = {},
		Evidence = {},
		DisprovedEvidence = {},
		JournalTouched = {},
		JournalDirty = false,
		JournalRevision = 0,
	}
	local indexes = {}
	for index, name in ipairs(GHOSTS) do indexes[name] = index end

	local function findJournalGhostTypes()
		local node = Player and Player:FindFirstChildOfClass("PlayerGui")
		for _, childName in ipairs({
			"Journal", "Holder", "Pages", "Page4", "Right", "Page", "GhostTypes",
		}) do
			node = node and node:FindFirstChild(childName)
		end
		if node then return node end
		local playerGui = Player and Player:FindFirstChildOfClass("PlayerGui")
		local journal = playerGui and playerGui:FindFirstChild("Journal")
		if not journal then return nil end
		for _, descendant in ipairs(journal:GetDescendants()) do
			if descendant.Name == "GhostTypes" then
				local rows = 0
				for _, child in ipairs(descendant:GetChildren()) do
					if child:IsA("Frame")
						and child:FindFirstChild("Highlight")
						and child:FindFirstChild("Strikethrough") then
						rows += 1
					end
				end
				if rows >= 5 then return descendant end
			end
		end
		return nil
	end

	local function findJournalRow(name)
		if customFindRow then return customFindRow(name) end
		local ghostTypes = findJournalGhostTypes()
		return ghostTypes and ghostTypes:FindFirstChild(name) or nil
	end

	local function readJournalRowState(row)
		if not row then return nil end
		local highlight = row:FindFirstChild("Highlight")
		local strikethrough = row:FindFirstChild("Strikethrough")
		if highlight and highlight.Visible then return true end
		if strikethrough and strikethrough.Visible then return false end
		return nil
	end

	local function triggerJournalClick(row)
		local detection = row and row:FindFirstChild("Detection")
		if not detection then return false end
		if type(fireSignal) == "function"
			and pcall(fireSignal, detection.MouseButton1Click) then
			return true
		end
		local fired = false
		pcall(function()
			if type(getconnections) == "function" then
				for _, connection in ipairs(getconnections(detection.MouseButton1Click)) do
					if type(connection.Function) == "function" then
						connection.Function()
						fired = true
					end
				end
			end
		end)
		if fired then return true end
		return pcall(function() detection:Activate() end)
	end

	local function applyJournal(index, state)
		if customApply then
			local applied, controllerUpdated = customApply(GHOSTS[index], state)
			if applied ~= false then Verdict.JournalTouched[index] = true end
			return applied ~= false, controllerUpdated == true
		end
		local row = findJournalRow(GHOSTS[index])
		if not row then return false end
		local current = readJournalRowState(row)
		if current == state then return true, true end
		for _ = 1, 3 do
			local previous = current
			if not triggerJournalClick(row) then break end
			local deadline = os.clock() + 0.25
			repeat
				wait(0.02)
				current = readJournalRowState(row)
			until current == state or current ~= previous or os.clock() >= deadline
			if current == state then
				Verdict.JournalTouched[index] = true
				return true, true
			end
			if current == previous then break end
		end
		return false, false
	end

	local function isRuledOut(index)
		return table.find(Verdict.RuledOut, index) ~= nil
	end

	local function abilityIsRuledOut(index)
		return Verdict.AbilityRuledOut[index] == true
	end

	local function evidenceCompatible(index)
		if type(EvidenceCatalog) ~= "table" then return true end
		local ghost = GHOSTS[index]
		local orb = EvidenceCatalog.ClassifyOrbCombination(Verdict.Evidence)
		if orb.Qualified then return ghost == "Skinwalker" end
		for evidence in pairs(Verdict.Evidence) do
			if not EvidenceCatalog.SupportsEvidence(ghost, evidence, {
				IncludeFalseEvidence = true,
			}) then
				return false
			end
		end
		for evidence in pairs(Verdict.DisprovedEvidence) do
			if EvidenceCatalog.SupportsEvidence(ghost, evidence, {RealOnly = true}) then
				return false
			end
		end
		return true
	end

	local function refreshUnknown()
		table.clear(Verdict.Unknown)
		local selected = Verdict.Selected[1]
		for index in ipairs(GHOSTS) do
			if index ~= selected and not isRuledOut(index) then
				table.insert(Verdict.Unknown, index)
			end
		end
	end

	local function refreshRuledOut()
		table.clear(Verdict.RuledOut)
		for index in ipairs(GHOSTS) do
			if abilityIsRuledOut(index) or not evidenceCompatible(index) then
				table.insert(Verdict.RuledOut, index)
			end
		end
		refreshUnknown()
	end

	local function markJournalDirty()
		Verdict.JournalRevision += 1
		Verdict.JournalDirty = true
	end

	local function resolvedEvidenceIndex()
		if type(EvidenceCatalog) ~= "table" then return nil end
		local count = 0
		for _ in pairs(Verdict.Evidence) do count += 1 end
		local orb = EvidenceCatalog.ClassifyOrbCombination(Verdict.Evidence)
		if orb.Qualified then return indexes.Skinwalker end
		if count ~= 3 then return nil end
		local candidates = EvidenceCatalog.FilterCandidates(Verdict.Evidence, {}, {
			NamesOnly = true,
			RealOnly = true,
			IncludeFalseEvidence = false,
		})
		return #candidates == 1 and indexes[candidates[1]] or nil
	end

	local function score(index)
		return math.max(0,
			(Verdict.Confidence[index] or 0) - (Verdict.NegativeConfidence[index] or 0))
	end

	local function selectBest(forceJournal)
		local bestIndex = resolvedEvidenceIndex()
		local bestScore = -math.huge
		if bestIndex and isRuledOut(bestIndex) then
			bestIndex = nil
		end
		if not bestIndex and Verdict.ForcedIndex and not isRuledOut(Verdict.ForcedIndex)
			and evidenceCompatible(Verdict.ForcedIndex) then
			bestIndex = Verdict.ForcedIndex
		elseif not bestIndex then
			for index in ipairs(GHOSTS) do
				local confidence = Verdict.Confidence[index]
				local currentScore = score(index)
				if not isRuledOut(index)
					and evidenceCompatible(index)
					and confidence ~= nil
					and currentScore > bestScore then
					bestIndex = index
					bestScore = currentScore
				end
			end
		end
		local previous = Verdict.Selected[1]
		if previous == bestIndex and not forceJournal then return end
		if previous ~= bestIndex then table.clear(Verdict.Selected) end
		if bestIndex then
			Verdict.Selected[1] = bestIndex
		end
		refreshUnknown()
		markJournalDirty()
	end

	function Verdict:Support(ghost, confidence, reason)
		local index = indexes[ghost]
		if not index or abilityIsRuledOut(index) then return false end
		confidence = tonumber(confidence) or 0
		self.Confidence[index] = math.max(self.Confidence[index] or 0, confidence)
		self.Reasons[index] = reason
		selectBest()
		return true
	end

	function Verdict:Negative(ghost, confidence, reason)
		local index = indexes[ghost]
		if not index or abilityIsRuledOut(index) then return false end
		confidence = tonumber(confidence) or 0
		self.NegativeConfidence[index] = math.max(self.NegativeConfidence[index] or 0, confidence)
		self.Reasons[index] = reason
		selectBest()
		return true
	end

	function Verdict:RuleOut(ghost, confidence, reason)
		local index = indexes[ghost]
		if not index then return false end
		if self.ForcedIndex == index or resolvedEvidenceIndex() == index then return false end
		self.AbilityRuledOut[index] = true
		refreshRuledOut()
		self.Confidence[index] = nil
		self.Reasons[index] = reason
		selectBest(true)
		return true
	end

	function Verdict:SetEvidence(evidence, state)
		if type(EvidenceCatalog) ~= "table" then return false end
		local key = EvidenceCatalog.NormalizeEvidence(evidence)
		if not key then return false end
		if state ~= true and state ~= false then state = nil end
		local previous
		if self.Evidence[key] then
			previous = true
		elseif self.DisprovedEvidence[key] then
			previous = false
		end
		if previous == state then return true end
		if state == true then
			self.Evidence[key] = true
			self.DisprovedEvidence[key] = nil
		elseif state == false then
			self.Evidence[key] = nil
			self.DisprovedEvidence[key] = true
		else
			self.Evidence[key] = nil
			self.DisprovedEvidence[key] = nil
		end
		local resolved = resolvedEvidenceIndex()
		if resolved then
			self.AbilityRuledOut[resolved] = nil
		end
		refreshRuledOut()
		if self.ForcedIndex and not evidenceCompatible(self.ForcedIndex) then
			self.ForcedIndex = nil
		end
		selectBest(true)
		return true
	end

	function Verdict:IsCompatible(ghost)
		local index = indexes[ghost]
		return index ~= nil and evidenceCompatible(index)
	end

	function Verdict:GetConfirmedEvidence()
		return table.clone(self.Evidence)
	end

	function Verdict:GetDisprovedEvidence()
		return table.clone(self.DisprovedEvidence)
	end

	function Verdict:GetEvidenceResolvedGhost()
		local index = resolvedEvidenceIndex()
		return index and not isRuledOut(index) and GHOSTS[index] or nil
	end

	function Verdict:ForceSelect(ghost)
		local index = indexes[ghost]
		if not index or isRuledOut(index) or not evidenceCompatible(index) then return false end
		self.ForcedIndex = index
		selectBest(true)
		return self.Selected[1] == index
	end

	function Verdict:ExpectedJournalState(name, forcedGhost)
		local index = indexes[name]
		if not index then return nil end
		local selectedIndex = forcedGhost and indexes[forcedGhost] or self.Selected[1]
		if index == selectedIndex then return true end
		if isRuledOut(index) or not evidenceCompatible(index) then return false end
		return nil
	end

	function Verdict:FindJournalGhostTypes()
		return findJournalGhostTypes()
	end

	function Verdict:ReadJournalRowState(row)
		return readJournalRowState(row)
	end

	function Verdict:SyncJournal(forcedGhost)
		if self.JournalMutationBusy then
			self.JournalDirty = true
			return false
		end
		self.JournalMutationBusy = true
		local completed, allApplied, synchronizedRevision = pcall(function()
			if forcedGhost and not self:ForceSelect(forcedGhost) then return false end
			local revision = self.JournalRevision
			local selectedIndex = forcedGhost and indexes[forcedGhost] or self.Selected[1]
			local appliedAll = true
			-- Crossing another row can clear the Journal's current highlight. Apply
			-- every cross-out/clear first, then select the one winner last.
			for index in ipairs(GHOSTS) do
				if index ~= selectedIndex then
					local expected = self:ExpectedJournalState(GHOSTS[index], forcedGhost)
					if expected ~= nil or self.JournalTouched[index] then
						local applied = applyJournal(index, expected)
						appliedAll = applied and appliedAll
					end
				end
			end
			if selectedIndex then
				local applied, controllerUpdated = applyJournal(selectedIndex, true)
				appliedAll = applied and appliedAll
				if applied and not controllerUpdated and markJournal then
					pcall(markJournal, GHOSTS[selectedIndex])
				end
			end
			return appliedAll, revision
		end)
		self.JournalMutationBusy = false
		allApplied = completed and allApplied == true
		local synchronized = allApplied
			and self.JournalRevision == synchronizedRevision
		self.JournalDirty = not synchronized
		return synchronized
	end

	function Verdict:Reset()
		for index in pairs(self.JournalTouched) do applyJournal(index, nil) end
		table.clear(self.JournalTouched)
		table.clear(self.AbilityRuledOut)
		table.clear(self.RuledOut)
		table.clear(self.Unknown)
		table.clear(self.Selected)
		table.clear(self.Confidence)
		table.clear(self.NegativeConfidence)
		table.clear(self.Reasons)
		table.clear(self.Evidence)
		table.clear(self.DisprovedEvidence)
		self.ForcedIndex = nil
		self.JournalDirty = false
		self.JournalMutationBusy = false
		self.JournalRevision += 1
		refreshUnknown()
	end

	function Verdict:Snapshot()
		return {
			Lists = table.clone(self.Lists),
			Selected = table.clone(self.Selected),
			["ruled-out"] = table.clone(self.RuledOut),
			Unknown = table.clone(self.Unknown),
			Confidence = table.clone(self.Confidence),
			NegativeConfidence = table.clone(self.NegativeConfidence),
			Reasons = table.clone(self.Reasons),
			Evidence = table.clone(self.Evidence),
			DisprovedEvidence = table.clone(self.DisprovedEvidence),
		}
	end

	Traffic:Receive("Verdict", function(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "Support" then
			Verdict:Support(payload.Ghost, payload.Confidence, payload.Reason)
		elseif signal == "Negative" then
			Verdict:Negative(payload.Ghost, payload.Confidence, payload.Reason)
		elseif signal == "RuleOut" then
			Verdict:RuleOut(payload.Ghost, payload.Confidence, payload.Reason)
		elseif signal == "EvidenceState" then
			Verdict:SetEvidence(payload.Evidence, payload.State)
		end
	end)

	refreshRuledOut()
	return Verdict
end
