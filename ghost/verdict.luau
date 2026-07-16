local GHOSTS = {
	"Aswang", "Banshee", "Demon", "Dullahan", "Dybbuk",
	"Entity", "Ghoul", "Keres", "Leviathan", "Nightmare",
	"Oni", "Phantom", "Ravager", "Revenant", "Shadow",
	"Siren", "Skinwalker", "Specter", "Spirit", "Umbra",
	"Vesper", "Vex", "Wendigo", "Wisp", "Wraith",
}

return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "verdict requires Traffic")
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
		Confidence = {},
		NegativeConfidence = {},
		Reasons = {},
		JournalTouched = {},
	}
	local indexes = {}
	for index, name in ipairs(GHOSTS) do indexes[name] = index end

	local function findJournalRow(name)
		if customFindRow then return customFindRow(name) end
		local node = Player and Player:FindFirstChildOfClass("PlayerGui")
		for _, childName in ipairs({
			"Journal", "Holder", "Pages", "Page4", "Right", "Page", "GhostTypes", name,
		}) do
			node = node and node:FindFirstChild(childName)
		end
		return node
	end

	local function applyJournal(index, state)
		if customApply then
			local applied, controllerUpdated = customApply(GHOSTS[index], state)
			if applied ~= false then Verdict.JournalTouched[index] = true end
			return applied ~= false, controllerUpdated == true
		end
		local row = findJournalRow(GHOSTS[index])
		if not row then return false end
		local highlight = row:FindFirstChild("Highlight")
		local strikethrough = row:FindFirstChild("Strikethrough")
		local function current()
			if highlight and highlight.Visible then return true end
			if strikethrough and strikethrough.Visible then return false end
			return nil
		end
		if current() == state then return true, true end
		local detection = row:FindFirstChild("Detection")
		if detection and type(fireSignal) == "function" then
			for _ = 1, 2 do
				local fired = pcall(fireSignal, detection.MouseButton1Click)
				if not fired then break end
				wait(0.03)
				if current() == state then
					Verdict.JournalTouched[index] = true
					return true, true
				end
			end
		end
		if highlight then highlight.Visible = state == true end
		if strikethrough then strikethrough.Visible = state == false end
		Verdict.JournalTouched[index] = true
		return true, false
	end

	local function isRuledOut(index)
		return table.find(Verdict.RuledOut, index) ~= nil
	end

	local function score(index)
		return math.max(0,
			(Verdict.Confidence[index] or 0) - (Verdict.NegativeConfidence[index] or 0))
	end

	local function selectBest(forceJournal)
		local bestIndex
		local bestScore = -math.huge
		for index, name in ipairs(GHOSTS) do
			local confidence = Verdict.Confidence[index]
			local currentScore = score(index)
			if not isRuledOut(index)
				and confidence ~= nil
				and currentScore > bestScore then
				bestIndex = index
				bestScore = currentScore
			end
		end
		local previous = Verdict.Selected[1]
		if previous == bestIndex and not forceJournal then return end
		if previous and previous ~= bestIndex then
			if isRuledOut(previous) then
				applyJournal(previous, false)
			else
				applyJournal(previous, nil)
			end
		end
		if previous ~= bestIndex then table.clear(Verdict.Selected) end
		if bestIndex then
			Verdict.Selected[1] = bestIndex
			local _, controllerUpdated = applyJournal(bestIndex, true)
			if not controllerUpdated and markJournal then pcall(markJournal, GHOSTS[bestIndex]) end
		end
	end

	function Verdict:Support(ghost, confidence, reason)
		local index = indexes[ghost]
		if not index or isRuledOut(index) then return false end
		confidence = tonumber(confidence) or 0
		self.Confidence[index] = math.max(self.Confidence[index] or 0, confidence)
		self.Reasons[index] = reason
		selectBest()
		return true
	end

	function Verdict:Negative(ghost, confidence, reason)
		local index = indexes[ghost]
		if not index or isRuledOut(index) then return false end
		confidence = tonumber(confidence) or 0
		self.NegativeConfidence[index] = math.max(self.NegativeConfidence[index] or 0, confidence)
		self.Reasons[index] = reason
		selectBest()
		return true
	end

	function Verdict:RuleOut(ghost, confidence, reason)
		local index = indexes[ghost]
		if not index then return false end
		if not isRuledOut(index) then
			table.insert(self.RuledOut, index)
			table.sort(self.RuledOut)
		end
		self.Confidence[index] = nil
		self.Reasons[index] = reason
		applyJournal(index, false)
		selectBest(true)
		return true
	end

	function Verdict:Reset()
		for index in pairs(self.JournalTouched) do applyJournal(index, nil) end
		table.clear(self.JournalTouched)
		table.clear(self.RuledOut)
		table.clear(self.Selected)
		table.clear(self.Confidence)
		table.clear(self.NegativeConfidence)
		table.clear(self.Reasons)
	end

	function Verdict:Snapshot()
		return {
			Lists = table.clone(self.Lists),
			Selected = table.clone(self.Selected),
			["ruled-out"] = table.clone(self.RuledOut),
			Confidence = table.clone(self.Confidence),
			NegativeConfidence = table.clone(self.NegativeConfidence),
			Reasons = table.clone(self.Reasons),
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
		end
	end)

	return Verdict
end
