local Resolver = {}
Resolver.__index = Resolver

local function maximumConfidence(entries)
	local result = 0
	for _, entry in ipairs(entries) do
		result = math.max(result, tonumber(entry.Confidence) or 0)
	end
	return result
end

local function copyArray(values)
	local result = {}
	for index, value in ipairs(values) do
		result[index] = value
	end
	return result
end

function Resolver.new(ledger, options)
	assert(type(ledger) == "table" and type(ledger.EffectiveEntries) == "function", "resolver requires an evidence ledger")
	return setmetatable({
		_ledger = ledger,
		_catalog = type(options) == "table" and options.Catalog or nil,
	}, Resolver)
end

Resolver.New = Resolver.new

function Resolver:ResolveGhost(ghost)
	local positives = {}
	local negatives = {}
	local ruleOuts = {}
	local observations = {}
	for _, entry in ipairs(self._ledger:EffectiveEntries(ghost)) do
		if entry.Polarity == "Positive" then
			table.insert(positives, entry)
		elseif entry.Polarity == "Negative" then
			table.insert(negatives, entry)
		elseif entry.Polarity == "RuleOut" then
			table.insert(ruleOuts, entry)
		else
			table.insert(observations, entry)
		end
	end

	local hasSupport = #positives > 0
	local hasOpposition = #negatives > 0 or #ruleOuts > 0
	local conflicted = hasSupport and hasOpposition
	local ruledOut = #ruleOuts > 0
	local status
	if conflicted then
		status = "Conflicted"
	elseif ruledOut then
		status = "RuledOut"
	elseif hasSupport then
		status = "Supported"
	elseif #negatives > 0 then
		status = "Negative"
	else
		status = "Unknown"
	end

	local confidence = maximumConfidence(positives)
	local negativeConfidence = math.max(
		maximumConfidence(negatives),
		maximumConfidence(ruleOuts)
	)
	return {
		Ghost = ghost,
		Status = status,
		Confidence = confidence,
		NegativeConfidence = negativeConfidence,
		Score = ruledOut and 0 or math.max(0, confidence - negativeConfidence),
		RuledOut = ruledOut,
		Conflicted = conflicted,
		Eligible = not ruledOut,
		Positives = positives,
		Negatives = negatives,
		RuleOuts = ruleOuts,
		Observations = observations,
	}
end

function Resolver:_names(input)
	if type(input) == "table" then
		return copyArray(input)
	end
	if type(self._catalog) == "table" then
		local result = {}
		for _, profile in ipairs(self._catalog) do
			if type(profile) == "string" then
				table.insert(result, profile)
			elseif type(profile) == "table" and type(profile.Name) == "string" then
				table.insert(result, profile.Name)
			end
		end
		return result
	end
	return self._ledger:GhostNames()
end

function Resolver:Resolve(names)
	local result = {}
	for _, ghost in ipairs(self:_names(names)) do
		result[ghost] = self:ResolveGhost(ghost)
	end
	return result
end

function Resolver:Rank(names, options)
	options = type(options) == "table" and options or {}
	local result = {}
	for _, ghost in ipairs(self:_names(names)) do
		local state = self:ResolveGhost(ghost)
		if options.IncludeRuledOut == true or not state.RuledOut then
			table.insert(result, state)
		end
	end
	table.sort(result, function(left, right)
		if left.Score ~= right.Score then
			return left.Score > right.Score
		end
		if left.Confidence ~= right.Confidence then
			return left.Confidence > right.Confidence
		end
		if left.Conflicted ~= right.Conflicted then
			return not left.Conflicted
		end
		return left.Ghost < right.Ghost
	end)
	return result
end

function Resolver:Snapshot(names)
	return {
		ByGhost = self:Resolve(names),
		Ranked = self:Rank(names, {IncludeRuledOut = true}),
	}
end

return Resolver
