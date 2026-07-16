local GHOSTS = {
	"Aswang", "Banshee", "Demon", "Dullahan", "Dybbuk",
	"Entity", "Ghoul", "Keres", "Leviathan", "Nightmare",
	"Oni", "Phantom", "Ravager", "Revenant", "Shadow",
	"Siren", "Skinwalker", "Specter", "Spirit", "Umbra",
	"Vesper", "Vex", "Wendigo", "Wisp", "Wraith",
}

return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "verdict requires Traffic")
	local Verdict = {
		Lists = table.clone(GHOSTS),
		Selected = nil,
		RuledOut = {},
		Confidence = {},
		Reasons = {},
	}
	local indexes = {}
	for index, name in ipairs(GHOSTS) do indexes[name] = index end

	local function selectBest()
		local bestIndex
		local bestConfidence = -math.huge
		for index, name in ipairs(GHOSTS) do
			local confidence = Verdict.Confidence[index]
			if not Verdict.RuledOut[index]
				and confidence ~= nil
				and confidence > bestConfidence then
				bestIndex = index
				bestConfidence = confidence
			end
		end
		Verdict.Selected = bestIndex
	end

	function Verdict:Support(ghost, confidence, reason)
		local index = indexes[ghost]
		if not index or self.RuledOut[index] then return false end
		confidence = tonumber(confidence) or 0
		self.Confidence[index] = math.max(self.Confidence[index] or 0, confidence)
		self.Reasons[index] = reason
		selectBest()
		return true
	end

	function Verdict:RuleOut(ghost, confidence, reason)
		local index = indexes[ghost]
		if not index then return false end
		self.RuledOut[index] = true
		self.Confidence[index] = nil
		self.Reasons[index] = reason
		selectBest()
		return true
	end

	function Verdict:Reset()
		table.clear(self.RuledOut)
		table.clear(self.Confidence)
		table.clear(self.Reasons)
		self.Selected = nil
	end

	function Verdict:Snapshot()
		local ruledOut = {}
		for index in pairs(self.RuledOut) do table.insert(ruledOut, index) end
		table.sort(ruledOut)
		return {
			Lists = table.clone(self.Lists),
			Selected = self.Selected,
			["ruled-out"] = ruledOut,
			Confidence = table.clone(self.Confidence),
			Reasons = table.clone(self.Reasons),
		}
	end

	Traffic:Receive("Verdict", function(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "Support" then
			Verdict:Support(payload.Ghost, payload.Confidence, payload.Reason)
		elseif signal == "RuleOut" then
			Verdict:RuleOut(payload.Ghost, payload.Confidence, payload.Reason)
		end
	end)

	return Verdict
end
