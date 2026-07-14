local Events = {}

Events.Types = {
	HuntingStateChanged = "HuntingStateChanged",
	HuntStarted = "HuntStarted",
	HuntEnded = "HuntEnded",
	HuntTransitionSettled = "HuntTransitionSettled",
	TransparencyChanged = "TransparencyChanged",
	SpeedPairSample = "SpeedPairSample",
	SpeedPairWindow = "SpeedPairWindow",
	DullahanPattern = "DullahanPattern",
	DullahanPatternAbsent = "DullahanPatternAbsent",
	PhantomPattern = "PhantomPattern",
	FlatHuntSpeed = "FlatHuntSpeed",
	HuntSpeedMathResult = "HuntSpeedMathResult",
	WendigoCurveResult = "WendigoCurveResult",
	SpeedProbeResult = "SpeedProbeResult",
	SpeedProbeRecovery = "SpeedProbeRecovery",
	PlayerDeath = "PlayerDeath",
	HuntEndedAfterDeath = "HuntEndedAfterDeath",
	HuntContinuedAfterDeath = "HuntContinuedAfterDeath",
	SaltContact = "SaltContact",
	SaltDisturbed = "SaltDisturbed",
	RoomTemperatureWindow = "RoomTemperatureWindow",
	WalkSpeedChanged = "WalkSpeedChanged",
	Tick = "Tick",
}

Events.CompatibilityAliases = {
	DullahanPattern = {"HuntSpeedSteps"},
	DullahanPatternAbsent = {"HuntSpeedStepsAbsent"},
	FlatHuntSpeed = {"StableHuntSpeed"},
	HuntSpeedMathResult = {"HuntingSpeedMath"},
	WendigoCurveResult = {"SanitySpeedCurve"},
	HuntEndedAfterDeath = {"KillHuntOutcome"},
	HuntContinuedAfterDeath = {"KillHuntOutcome"},
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

local function readDefault(defaults, key)
	if type(defaults) ~= "table" then
		return nil
	end
	local value = defaults[key]
	if type(value) == "function" then
		return value()
	end
	return value
end

function Events.Copy(value)
	return copy(value)
end

function Events.Read(event, key, fallback)
	if type(event) ~= "table" then
		return fallback
	end
	if event[key] ~= nil then
		return event[key]
	end
	if type(event.Payload) == "table" and event.Payload[key] ~= nil then
		return event.Payload[key]
	end
	return fallback
end

function Events.Normalize(event, defaults)
	assert(type(event) == "table", "event must be a table")
	local kind = event.Type or event.Kind
	assert(type(kind) == "string" and kind ~= "", "event.Type or event.Kind is required")

	local normalized = copy(event)
	normalized.Type = kind
	normalized.Kind = kind
	normalized.Time = tonumber(event.Time or event.Timestamp)
		or tonumber(readDefault(defaults, "Time"))
		or os.clock()
	normalized.Source = event.Source or readDefault(defaults, "Source") or "Unknown"
	normalized.Payload = copy(type(event.Payload) == "table" and event.Payload or {})
	-- Remote profile modules historically consumed both event.Field and
	-- event.Payload.Field. Mirror payload values without overwriting explicit
	-- top-level fields so one normalized event supports both contracts.
	for key, value in pairs(normalized.Payload) do
		if normalized[key] == nil then
			normalized[key] = copy(value)
		end
	end
	local aliases = event.Aliases or Events.CompatibilityAliases[kind]
	if type(aliases) == "table" then
		normalized.Aliases = copy(aliases)
		normalized.Payload.Aliases = copy(aliases)
	end
	if kind == Events.Types.SpeedProbeResult then
		local trigger = normalized.Trigger or normalized.Payload.Trigger
		if trigger == Events.Types.SaltContact then
			normalized.Aliases = {"SaltContactSpeed"}
		elseif trigger == Events.Types.PlayerDeath then
			normalized.Aliases = {"KillSpeedChange"}
		end
		normalized.Payload.Aliases = copy(normalized.Aliases)
	end

	if normalized.HuntId == nil then
		normalized.HuntId = readDefault(defaults, "HuntId")
	end
	if normalized.Hunting == nil then
		normalized.Hunting = readDefault(defaults, "Hunting")
	end
	if normalized.ParentId == nil then
		normalized.ParentId = readDefault(defaults, "ParentId")
	end
	-- Preserve collector qualifiers in durable event/ledger metadata. Runtime
	-- observers accept top-level fields, while the ledger stores Payload.
	for key, value in pairs(normalized) do
		if key ~= "Payload" and normalized.Payload[key] == nil then
			normalized.Payload[key] = copy(value)
		end
	end
	return normalized
end

function Events.IsBinaryTransparency(value)
	if type(value) == "boolean" then
		return true, value
	end
	if type(value) == "number" and (value == 0 or value == 1) then
		return true, value == 1
	end
	return false, nil
end

function Events.MakeIdFactory(prefix)
	local nextId = 0
	return function()
		nextId = nextId + 1
		return tostring(prefix or "event-") .. tostring(nextId)
	end
end

return Events
