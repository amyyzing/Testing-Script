local Ledger = {}
Ledger.__index = Ledger

local VALID_POLARITY = {
	Observation = true,
	Positive = true,
	Negative = true,
	RuleOut = true,
}

local function copy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local result = {}
	seen[value] = result
	for key, item in pairs(value) do
		result[copy(key, seen)] = copy(item, seen)
	end
	return result
end

local function clampConfidence(value)
	local confidence = tonumber(value)
	if confidence == nil then
		return nil
	end
	return math.clamp(confidence, 0, 100)
end

local function eventMetadata(event)
	event = type(event) == "table" and event or {}
	return {
		Time = tonumber(event.Time or event.Timestamp),
		Source = event.Source,
		EventId = event.EventId or event.Id,
		HuntId = event.HuntId,
		Supersedes = event.Supersedes,
		Tags = copy(event.Tags),
		Details = copy(event.Details or event.Payload),
	}
end

function Ledger.new(options)
	options = type(options) == "table" and options or {}
	return setmetatable({
		_clock = options.Clock or os.clock,
		_round = tonumber(options.Round) or 1,
		_nextId = 0,
		_entries = {},
		_byId = {},
	}, Ledger)
end

Ledger.New = Ledger.new

function Ledger:_nextEntryId()
	self._nextId = self._nextId + 1
	return "evidence-" .. tostring(self._round) .. "-" .. tostring(self._nextId)
end

function Ledger:_append(input)
	assert(type(input) == "table", "ledger entry must be a table")
	local polarity = input.Polarity or input.Outcome or "Observation"
	assert(VALID_POLARITY[polarity] == true, "unsupported evidence polarity: " .. tostring(polarity))
	if polarity ~= "Observation" then
		assert(type(input.Ghost) == "string" and input.Ghost ~= "", "scored evidence requires a ghost name")
	end

	local supersedes = input.Supersedes
	if supersedes ~= nil then
		assert(type(supersedes) == "string", "Supersedes must be an evidence id")
		local previous = self._byId[supersedes]
		assert(previous ~= nil, "Supersedes references unknown evidence: " .. supersedes)
		if input.Ghost and previous.Ghost then
			assert(input.Ghost == previous.Ghost, "evidence may only supersede an entry for the same ghost")
		end
	end

	local entry = copy(input)
	entry.Id = self:_nextEntryId()
	entry.Round = self._round
	entry.Time = tonumber(input.Time) or self._clock()
	entry.Polarity = polarity
	entry.Confidence = clampConfidence(input.Confidence)
	entry.Reason = tostring(input.Reason or input.Description or input.Type or "observation recorded")
	entry.Source = tostring(input.Source or "Unknown")

	table.insert(self._entries, entry)
	self._byId[entry.Id] = entry
	return copy(entry)
end

function Ledger:Record(ghostOrEntry, event)
	if type(ghostOrEntry) == "table" and event == nil then
		return self:_append(ghostOrEntry)
	end
	assert(type(ghostOrEntry) == "string" and ghostOrEntry ~= "", "Record requires a ghost name")
	event = type(event) == "table" and event or {}
	local metadata = eventMetadata(event)
	metadata.Ghost = ghostOrEntry
	metadata.Polarity = event.Polarity or "Observation"
	metadata.Confidence = event.Confidence
	metadata.Reason = event.Reason or event.Description or event.Type or event.Kind
	metadata.Source = event.Source
	return self:_append(metadata)
end

function Ledger:_scored(polarity, ghost, reason, confidence, event)
	assert(type(ghost) == "string" and ghost ~= "", polarity .. " requires a ghost name")
	local metadata = eventMetadata(event)
	metadata.Ghost = ghost
	metadata.Polarity = polarity
	metadata.Reason = reason
	metadata.Confidence = confidence
	return self:_append(metadata)
end

function Ledger:Positive(ghost, reason, confidence, event)
	return self:_scored("Positive", ghost, reason, confidence, event)
end

function Ledger:Negative(ghost, reason, confidence, event)
	return self:_scored("Negative", ghost, reason, confidence, event)
end

function Ledger:RuleOut(ghost, reason, confidence, event)
	return self:_scored("RuleOut", ghost, reason, confidence, event)
end

function Ledger:Get(id)
	return copy(self._byId[id])
end

function Ledger:Entries()
	return copy(self._entries)
end

function Ledger:EffectiveEntries(ghost)
	local superseded = {}
	for _, entry in ipairs(self._entries) do
		if entry.Supersedes then
			superseded[entry.Supersedes] = true
		end
	end
	local result = {}
	for _, entry in ipairs(self._entries) do
		if not superseded[entry.Id] and (ghost == nil or entry.Ghost == ghost) then
			table.insert(result, copy(entry))
		end
	end
	return result
end

function Ledger:GhostNames()
	local seen = {}
	local result = {}
	for _, entry in ipairs(self._entries) do
		if type(entry.Ghost) == "string" and not seen[entry.Ghost] then
			seen[entry.Ghost] = true
			table.insert(result, entry.Ghost)
		end
	end
	table.sort(result)
	return result
end

function Ledger:Reset(options)
	options = type(options) == "table" and options or {}
	self._round = tonumber(options.Round) or (self._round + 1)
	self._nextId = 0
	table.clear(self._entries)
	table.clear(self._byId)
end

function Ledger:Snapshot()
	return {
		Round = self._round,
		Entries = self:Entries(),
		EffectiveEntries = self:EffectiveEntries(),
	}
end

return Ledger
