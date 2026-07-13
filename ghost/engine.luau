-- Demonology ghost catalogue and evidence helpers.  The concrete ghost
-- definitions are loaded separately so this engine remains data-driven.
--
-- Internal evidence keys intentionally retain the names used by the original
-- monolith. DisplayName and CurrentName expose the current in-game/wiki names.

return function(rawDefinitions)
if type(rawDefinitions) ~= "table" then
	error("ghost/engine.luau requires an ordered definition array", 2)
end

local GhostModule = {}

local EVIDENCE_ORDER = {
	"EMFLevel5",
	"SpiritBox",
	"GhostWriting",
	"FreezingTemperatures",
	"GhostOrb",
	"Handprints",
	"LaserProjector",
	"Wither",
}

local EVIDENCE = {
	EMFLevel5 = {
		Key = "EMFLevel5",
		CurrentName = "EMF Level 5",
		DisplayName = "EMF Level 5",
		Aliases = {"EMF 5", "EMF5", "EMF Level 5"},
	},
	SpiritBox = {
		Key = "SpiritBox",
		CurrentName = "Spirit Box",
		DisplayName = "Spirit Box",
		Aliases = {"Spirit Box"},
	},
	GhostWriting = {
		Key = "GhostWriting",
		CurrentName = "Inscription",
		DisplayName = "Inscription",
		LegacyName = "Ghost Writing",
		Aliases = {"Inscription", "Ghost Writing", "Writing", "Spirit Book"},
	},
	FreezingTemperatures = {
		Key = "FreezingTemperatures",
		CurrentName = "Freezing Temperatures",
		DisplayName = "Freezing Temperatures",
		Aliases = {"Freezing", "Freezing Temps", "Freezing Temperatures"},
	},
	GhostOrb = {
		Key = "GhostOrb",
		CurrentName = "Ghost Orb",
		DisplayName = "Ghost Orb",
		Aliases = {"Orb", "Orbs", "Ghost Orb", "Ghost Orbs"},
	},
	Handprints = {
		Key = "Handprints",
		CurrentName = "Prints",
		DisplayName = "Prints",
		LegacyName = "Handprints",
		Aliases = {"Print", "Prints", "Handprint", "Handprints", "Fingerprint", "Fingerprints"},
	},
	LaserProjector = {
		Key = "LaserProjector",
		CurrentName = "Laser Projector",
		DisplayName = "Laser Projector",
		Aliases = {"Laser", "Laser Projector", "Projector", "LIDAR Projection"},
	},
	Wither = {
		Key = "Wither",
		CurrentName = "Wither",
		DisplayName = "Wither",
		Aliases = {"Wither", "Withering", "Decay"},
	},
}

local function normalizedToken(value)
	if value == nil then
		return nil
	end
	return string.lower(tostring(value)):gsub("[^%w]", "")
end

local evidenceAliases = {}
for _, evidenceKey in ipairs(EVIDENCE_ORDER) do
	local definition = EVIDENCE[evidenceKey]
	evidenceAliases[normalizedToken(evidenceKey)] = evidenceKey
	evidenceAliases[normalizedToken(definition.CurrentName)] = evidenceKey
	evidenceAliases[normalizedToken(definition.DisplayName)] = evidenceKey
	if definition.LegacyName then
		evidenceAliases[normalizedToken(definition.LegacyName)] = evidenceKey
	end
	for _, alias in ipairs(definition.Aliases) do
		evidenceAliases[normalizedToken(alias)] = evidenceKey
	end
end

local function normalizeEvidence(evidence)
	if type(evidence) == "table" then
		evidence = evidence.Key or evidence.Name or evidence.DisplayName or evidence.CurrentName
	end
	return evidenceAliases[normalizedToken(evidence)]
end

local function shallowCopy(source)
	local result = {}
	if type(source) == "table" then
		for key, value in pairs(source) do
			result[key] = value
		end
	end
	return result
end

local function copyArray(source)
	local result = {}
	if type(source) == "table" then
		for index, value in ipairs(source) do
			result[index] = value
		end
	end
	return result
end

local REQUIRED_GHOST_COUNT = 25
local PERK_TIERS = {"Pretty Sure", "Maybe", "Idk"}

local function requireNonEmptyString(value, label)
	if type(value) ~= "string" or value == "" then
		error(label .. " must be a non-empty string", 3)
	end
	return value
end

local function normalizeStringArray(rawValues, label, allowEquivalentTokens)
	rawValues = rawValues or {}
	if type(rawValues) ~= "table" then
		error(label .. " must be an array", 3)
	end
	local result = {}
	local seen = {}
	local entryCount = 0
	for key in pairs(rawValues) do
		if type(key) ~= "number"
			or key % 1 ~= 0
			or key < 1
			or key > #rawValues then
			error(label .. " must be a dense array", 3)
		end
		entryCount = entryCount + 1
	end
	if entryCount ~= #rawValues then
		error(label .. " must be a dense array", 3)
	end
	for index, value in ipairs(rawValues) do
		requireNonEmptyString(value, ("%s[%d]"):format(label, index))
		local token = normalizedToken(value)
		if not token or token == "" then
			error(("%s[%d] must contain letters or numbers"):format(label, index), 3)
		end
		if seen[token] and not allowEquivalentTokens then
			error(("%s repeats %q"):format(label, value), 3)
		end
		seen[token] = true
		result[index] = value
	end
	return result
end

local function normalizeNote(rawNote, definition, tierName, noteIndex)
	if type(rawNote) ~= "table" then
		error(("%s Perks[%q][%d] must be a table"):format(
			definition.Name,
			tierName,
			noteIndex
		), 3)
	end
	local result = shallowCopy(rawNote)
	result.Text = requireNonEmptyString(
		rawNote.Text,
		("%s Perks[%q][%d].Text"):format(definition.Name, tierName, noteIndex)
	)
	local source = rawNote.Source
		or rawNote.SourceUrl
		or rawNote.SourceURL
		or definition.Source
		or definition.SourceUrl
		or definition.SourceURL
	requireNonEmptyString(
		source,
		("%s Perks[%q][%d].Source"):format(
			definition.Name,
			tierName,
			noteIndex
		)
	)
	result.Source = source
	result.SourceUrl = source
	result.SourceURL = source
	result.Status = rawNote.Status or definition.SourceStatus or "wiki-documented"
	result.Mimickable = rawNote.Mimickable == true
	result.Kind = rawNote.Kind or "Trait"
	return result
end

local function normalizePerks(rawPerks, definition)
	if type(rawPerks) ~= "table" then
		error(definition.Name .. ".Perks must be a table", 3)
	end
	local result = {}
	for _, tierName in ipairs(PERK_TIERS) do
		local rawNotes = rawPerks[tierName]
		if type(rawNotes) ~= "table" then
			error(("%s.Perks[%q] must be a table"):format(
				definition.Name,
				tierName
			), 3)
		end
		local notes = {}
		for noteIndex, rawNote in ipairs(rawNotes) do
			notes[noteIndex] = normalizeNote(
				rawNote,
				definition,
				tierName,
				noteIndex
			)
		end
		result[tierName] = notes
	end
	return result
end

local function normalizeEvidenceList(rawEvidence, definitionName, fieldName, expectedCount)
	if type(rawEvidence) ~= "table" then
		error(("%s.%s must be an array"):format(definitionName, fieldName), 3)
	end
	if expectedCount and #rawEvidence ~= expectedCount then
		error(("%s.%s must contain exactly %d evidence keys"):format(
			definitionName,
			fieldName,
			expectedCount
		), 3)
	end
	local result = {}
	local seen = {}
	for index, rawKey in ipairs(rawEvidence) do
		local evidenceKey = normalizeEvidence(rawKey)
		if not evidenceKey then
			error(("%s.%s[%d] is not a recognized evidence key"):format(
				definitionName,
				fieldName,
				index
			), 3)
		end
		if seen[evidenceKey] then
			error(("%s.%s repeats evidence %s"):format(
				definitionName,
				fieldName,
				evidenceKey
			), 3)
		end
		seen[evidenceKey] = true
		result[index] = evidenceKey
	end
	return result, seen
end

local function normalizeDefinition(rawDefinition, index)
	if type(rawDefinition) ~= "table" then
		error(("ghost definition %d must be a table"):format(index), 3)
	end
	local name = requireNonEmptyString(
		rawDefinition.Name,
		("ghost definition %d Name"):format(index)
	)
	local evidence, evidenceSet = normalizeEvidenceList(
		rawDefinition.Evidence,
		name,
		"Evidence",
		3
	)
	local falseEvidence, falseEvidenceSet = normalizeEvidenceList(
		rawDefinition.FalseEvidence or {},
		name,
		"FalseEvidence"
	)
	for evidenceKey in pairs(falseEvidenceSet) do
		if evidenceSet[evidenceKey] then
			error(("%s lists %s as both real and false evidence"):format(
				name,
				evidenceKey
			), 3)
		end
	end
	local source = rawDefinition.Source
		or rawDefinition.SourceUrl
		or rawDefinition.SourceURL
	requireNonEmptyString(source, name .. ".Source")
	local evidenceDisplay = {}
	for evidenceIndex, evidenceKey in ipairs(evidence) do
		evidenceDisplay[evidenceIndex] = EVIDENCE[evidenceKey].DisplayName
	end
	local profile = shallowCopy(rawDefinition)
	profile.Name = name
	profile.DisplayName = requireNonEmptyString(
		rawDefinition.DisplayName or (name == "Wisp" and "The Wisp" or name),
		name .. ".DisplayName"
	)
	profile.Aliases = normalizeStringArray(
		rawDefinition.Aliases,
		name .. ".Aliases",
		true
	)
	profile.Evidence = evidence
	profile.EvidenceSet = evidenceSet
	profile.EvidenceDisplay = evidenceDisplay
	profile.DisplayEvidence = evidenceDisplay
	profile.FalseEvidence = falseEvidence
	profile.FalseEvidenceSet = falseEvidenceSet
	profile.Perks = normalizePerks(rawDefinition.Perks, rawDefinition)
	profile.Source = source
	profile.SourceUrl = source
	profile.SourceURL = source
	profile.SourceStatus = rawDefinition.SourceStatus or "wiki-documented"
	profile.ObservationKeys = normalizeStringArray(
		rawDefinition.ObservationKeys,
		name .. ".ObservationKeys"
	)
	profile.Definition = rawDefinition
	return profile
end

if #rawDefinitions ~= REQUIRED_GHOST_COUNT then
	error(("ghost engine requires exactly %d definitions; received %d"):format(
		REQUIRED_GHOST_COUNT,
		#rawDefinitions
	), 2)
end
local definitionEntryCount = 0
for key in pairs(rawDefinitions) do
	if type(key) ~= "number"
		or key % 1 ~= 0
		or key < 1
		or key > #rawDefinitions then
		error("ghost definitions must be a dense ordered array", 2)
	end
	definitionEntryCount = definitionEntryCount + 1
end
if definitionEntryCount ~= #rawDefinitions then
	error("ghost definitions must be a dense ordered array", 2)
end

local Profiles = {}
local PerkConfidence = {}
local PerkTTL = {}
local seenNames = {}
local seenEvidenceCombinations = {}
for index, rawDefinition in ipairs(rawDefinitions) do
	local ghostProfile = normalizeDefinition(rawDefinition, index)
	local nameToken = normalizedToken(ghostProfile.Name)
	if seenNames[nameToken] then
		error(("duplicate ghost definition name %q"):format(ghostProfile.Name), 2)
	end
	seenNames[nameToken] = true

	local signatureParts = copyArray(ghostProfile.Evidence)
	table.sort(signatureParts)
	local evidenceSignature = table.concat(signatureParts, "\0")
	local existingEvidenceOwner = seenEvidenceCombinations[evidenceSignature]
	if existingEvidenceOwner then
		error(("%s and %s define the same real evidence set"):format(
			existingEvidenceOwner,
			ghostProfile.Name
		), 2)
	end
	seenEvidenceCombinations[evidenceSignature] = ghostProfile.Name

	local confidence = rawDefinition.Confidence
	if confidence ~= nil then
		if type(confidence) ~= "number"
			or confidence ~= confidence
			or confidence < 0
			or confidence > 100 then
			error(ghostProfile.Name .. ".Confidence must be a number from 0 to 100", 2)
		end
		PerkConfidence[ghostProfile.Name] = confidence
	end
	local ttl = rawDefinition.TTL
	if ttl ~= nil then
		if type(ttl) ~= "number" or ttl ~= ttl or ttl <= 0 then
			error(ghostProfile.Name .. ".TTL must be a positive number", 2)
		end
		PerkTTL[ghostProfile.Name] = ttl
	end
	Profiles[index] = ghostProfile
end

local Order = {}
local ByName = {}
local lookupByToken = {}
local orderIndex = {}
local function registerLookupName(ghostProfile, value, label)
	local token = normalizedToken(value)
	if not token or token == "" then
		error(("%s %s must contain letters or numbers"):format(
			ghostProfile.Name,
			label
		), 2)
	end
	local existing = lookupByToken[token]
	if existing and existing ~= ghostProfile then
		error(("%s %s %q collides with ghost %s"):format(
			ghostProfile.Name,
			label,
			tostring(value),
			existing.Name
		), 2)
	end
	lookupByToken[token] = ghostProfile
end
for index, ghostProfile in ipairs(Profiles) do
	ghostProfile.Index = index
	Order[index] = ghostProfile.Name
	ByName[ghostProfile.Name] = ghostProfile
	registerLookupName(ghostProfile, ghostProfile.Name, "Name")
	registerLookupName(ghostProfile, ghostProfile.DisplayName, "DisplayName")
	orderIndex[ghostProfile.Name] = index
	for _, alias in ipairs(ghostProfile.Aliases) do
		registerLookupName(ghostProfile, alias, "alias")
	end
end

local TIER_NAMES = {
	[0] = "Idk",
	[1] = "Idk",
	[2] = "Maybe",
	[3] = "Pretty Sure",
}

local function confidenceTier(score)
	score = tonumber(score) or 0
	if score >= 80 then
		return 3, "Pretty Sure"
	elseif score >= 50 then
		return 2, "Maybe"
	elseif score > 0 then
		return 1, "Idk"
	end
	return 0, "Idk"
end

local function find(name)
	if type(name) == "table" then
		if name.Name then
			name = name.Name
		elseif name.DisplayName then
			name = name.DisplayName
		else
			return nil
		end
	end
	return lookupByToken[normalizedToken(name)]
end

local function supportsEvidence(profileOrName, evidence, options)
	local ghostProfile = find(profileOrName)
	local evidenceKey = normalizeEvidence(evidence)
	if not ghostProfile or not evidenceKey then
		return false, nil
	end
	if ghostProfile.EvidenceSet[evidenceKey] then
		return true, "real"
	end
	options = options or {}
	if options.RealOnly ~= true
		and options.IncludeFalseEvidence ~= false
		and ghostProfile.FalseEvidenceSet[evidenceKey] then
		return true, "false"
	end
	return false, nil
end

local function addEvidenceValue(target, value)
	local evidenceKey = normalizeEvidence(value)
	if evidenceKey then
		target[evidenceKey] = true
	end
end

local function collectEvidence(input, options)
	options = options or {}
	local observed = {}
	local disproved = {}
	if type(input) == "string" then
		addEvidenceValue(observed, input)
	elseif type(input) == "table" then
		if type(input.Evidence) == "table" and input.Evidence ~= input then
			input = input.Evidence
		end
		for _, value in ipairs(input) do
			addEvidenceValue(observed, value)
		end
		for key, value in pairs(input) do
			if type(key) == "string" then
				local evidenceKey = normalizeEvidence(key)
				if evidenceKey then
					if value == true then
						observed[evidenceKey] = true
					elseif value == false and options.FalseMeansDisproved == true then
						disproved[evidenceKey] = true
					end
				end
			end
		end
	end
	local explicitDisproved = options.DisprovedEvidence
	if type(explicitDisproved) == "string" then
		addEvidenceValue(disproved, explicitDisproved)
	elseif type(explicitDisproved) == "table" then
		for _, value in ipairs(explicitDisproved) do
			addEvidenceValue(disproved, value)
		end
		for key, value in pairs(explicitDisproved) do
			if type(key) == "string" and value then
				addEvidenceValue(disproved, key)
			end
		end
	end
	return observed, disproved
end

local function collectRuleOuts(input)
	local ruledOut = {}
	if type(input) == "string" then
		local ghostProfile = find(input)
		if ghostProfile then
			ruledOut[ghostProfile.Name] = true
		end
	elseif type(input) == "table" then
		if type(input.RuleOuts) == "table" and input.RuleOuts ~= input then
			input = input.RuleOuts
		end
		for _, value in ipairs(input) do
			local ghostProfile = find(value)
			if ghostProfile then
				ruledOut[ghostProfile.Name] = true
			end
		end
		for key, value in pairs(input) do
			if type(key) == "string" and value then
				local ghostProfile = find(key)
				if ghostProfile then
					ruledOut[ghostProfile.Name] = true
				end
			end
		end
	end
	return ruledOut
end

local function candidatePool(options)
	options = options or {}
	local requested = options.Candidates or options.Profiles
	if type(requested) ~= "table" then
		return Profiles
	end
	local allowed = {}
	for _, value in ipairs(requested) do
		local ghostProfile = find(value)
		if ghostProfile then
			allowed[ghostProfile.Name] = true
		end
	end
	for key, value in pairs(requested) do
		if type(key) == "string" and value then
			local ghostProfile = find(key)
			if ghostProfile then
				allowed[ghostProfile.Name] = true
			end
		end
	end
	local result = {}
	for _, ghostProfile in ipairs(Profiles) do
		if allowed[ghostProfile.Name] then
			table.insert(result, ghostProfile)
		end
	end
	return result
end

local function filterCandidates(evidence, ruleOuts, options)
	options = options or {}
	local observed, disproved = collectEvidence(evidence, options)
	local ruledOut = collectRuleOuts(ruleOuts)
	local result = {}
	for _, ghostProfile in ipairs(candidatePool(options)) do
		local compatible = options.IgnoreRuleOuts == true or not ruledOut[ghostProfile.Name]
		if compatible then
			for evidenceKey in pairs(observed) do
				if not supportsEvidence(ghostProfile, evidenceKey, options) then
					compatible = false
					break
				end
			end
		end
		if compatible then
			for evidenceKey in pairs(disproved) do
				-- A missing fake Orb does not disprove Skinwalker, so negative
				-- evidence considers real evidence only.
				if supportsEvidence(ghostProfile, evidenceKey, {RealOnly = true}) then
					compatible = false
					break
				end
			end
		end
		if compatible then
			if options.NamesOnly == true then
				table.insert(result, ghostProfile.Name)
			else
				table.insert(result, ghostProfile)
			end
		end
	end
	return result
end

local function detectionName(detection, fallback)
	if type(detection) == "table" then
		return detection.Ghost or detection.Name or detection.GhostName or fallback
	end
	return fallback
end

local function detectionScore(detection)
	if type(detection) == "number" then
		return detection
	elseif type(detection) == "table" then
		return tonumber(detection.Confidence or detection.Score or detection.Value) or 0
	end
	return 0
end

local function selectHighestConfidenceGuess(options)
	if type(options) ~= "table" or type(options.Candidates) ~= "table" then
		return nil
	end

	local candidates = {}
	local allowed = {}
	local function addCandidate(value)
		if type(value) ~= "string" then
			return
		end
		local name = value:match("^%s*(.-)%s*$")
		if name == "" or allowed[name] then
			return
		end
		allowed[name] = true
		table.insert(candidates, name)
	end

	for _, value in ipairs(options.Candidates) do
		addCandidate(value)
	end
	local keyedCandidates = {}
	for key, value in pairs(options.Candidates) do
		if type(key) == "string" and value then
			table.insert(keyedCandidates, key)
		end
	end
	table.sort(keyedCandidates)
	for _, name in ipairs(keyedCandidates) do
		addCandidate(name)
	end
	if #candidates == 0 then
		return nil
	end

	local scores = {}
	local detections = type(options.Detections) == "table" and options.Detections or {}
	for _, name in ipairs(candidates) do
		local score = detectionScore(detections[name])
		if score ~= score or score < 0 then
			score = 0
		end
		scores[name] = score
	end

	local currentScore = options.CurrentScore
	if type(currentScore) == "number" and currentScore == currentScore and currentScore > 0
		and type(options.CurrentGuess) == "string" then
		for name in string.gmatch(options.CurrentGuess, "[^/]+") do
			name = name:match("^%s*(.-)%s*$")
			if allowed[name] then
				scores[name] = math.max(scores[name], currentScore)
			end
		end
	end

	local maximumScore = 0
	for _, name in ipairs(candidates) do
		maximumScore = math.max(maximumScore, scores[name])
	end
	local tied = {}
	for _, name in ipairs(candidates) do
		if scores[name] == maximumScore then
			table.insert(tied, name)
		end
	end
	if #tied == 1 then
		return tied[1]
	end

	local hasSkinwalker = false
	for _, name in ipairs(tied) do
		if name == "Skinwalker" then
			hasSkinwalker = true
			break
		end
	end
	local useSkinwalkerWeights = options.SkinwalkerHalfWeight == true
		and hasSkinwalker
		and #tied > 1

	local function getRandomUnit()
		if options.RandomUnit == nil then
			return math.random()
		end
		if type(options.RandomUnit) ~= "function" then
			return nil
		end
		local ok, value = pcall(options.RandomUnit)
		if not ok or type(value) ~= "number" or value ~= value
			or value < 0 or value >= 1 then
			return nil
		end
		return value
	end

	if useSkinwalkerWeights then
		-- Halving Skinwalker's original 1/N share and distributing the removed
		-- half equally keeps the total weight at N. For three tied ghosts this
		-- produces 1/6 for Skinwalker and 5/12 for each other ghost.
		local unit = getRandomUnit()
		if unit == nil then
			return nil
		end
		local totalWeight = #tied
		local otherWeight = 1 + 0.5 / (#tied - 1)
		local target = unit * totalWeight
		local cumulative = 0
		for _, name in ipairs(tied) do
			cumulative = cumulative
				+ (name == "Skinwalker" and 0.5 or otherWeight)
			if target < cumulative then
				return name
			end
		end
		return tied[#tied]
	end

	local index
	if options.RandomIndex ~= nil then
		if type(options.RandomIndex) ~= "function" then
			return nil
		end
		local ok, selected = pcall(options.RandomIndex, #tied)
		if not ok or type(selected) ~= "number" or selected ~= math.floor(selected)
			or selected < 1 or selected > #tied then
			return nil
		end
		index = selected
	elseif options.RandomUnit ~= nil then
		local unit = getRandomUnit()
		if unit == nil then
			return nil
		end
		index = math.floor(unit * #tied) + 1
	else
		index = math.random(#tied)
	end
	return tied[index]
end

local function selectTimeoutGuess(options)
	options = shallowCopy(options or {})
	-- Skinwalker only keeps its full timeout weight once Orb has actually been
	-- observed.  Keeping this policy in the ghost package prevents automation
	-- callers from embedding ghost-specific weighting rules.
	options.SkinwalkerHalfWeight = options.HasOrbEvidence ~= true
	options.HasOrbEvidence = nil
	return selectHighestConfidenceGuess(options)
end

local function rankDetections(detections, evidence, ruleOuts, options)
	options = options or {}
	local candidateOptions = shallowCopy(options)
	candidateOptions.NamesOnly = true
	local compatibleNames = filterCandidates(evidence, ruleOuts, candidateOptions)
	local compatible = {}
	for _, ghostName in ipairs(compatibleNames) do
		compatible[ghostName] = true
	end

	local bestByName = {}
	local function consider(detection, fallbackName, insertionIndex)
		local ghostProfile = find(detectionName(detection, fallbackName))
		if not ghostProfile or not compatible[ghostProfile.Name] then
			return
		end
		local score = detectionScore(detection)
		if score < (tonumber(options.MinimumConfidence) or 0) then
			return
		end
		local source = type(detection) == "table" and shallowCopy(detection) or {Confidence = score}
		local persistent = source.Persistent == true or score >= 80
		local expiresAt = tonumber(source.ExpiresAt)
		local detectedAt = tonumber(source.DetectedAt or source.At)
		local ttl = tonumber(source.TTL or PerkTTL[ghostProfile.Name])
		if not expiresAt and detectedAt and ttl and not persistent then
			expiresAt = detectedAt + ttl
		end
		local expired = options.Now ~= nil
			and expiresAt ~= nil
			and tonumber(options.Now) ~= nil
			and tonumber(options.Now) > expiresAt
		if expired and options.IncludeExpired ~= true then
			return
		end
		local tier, tierName = confidenceTier(score)
		local ranked = {
			Ghost = ghostProfile.Name,
			Name = ghostProfile.Name,
			Profile = ghostProfile,
			Detection = source,
			Confidence = score,
			Score = score,
			Tier = tier,
			TierName = tierName,
			Reason = source.Reason,
			Persistent = persistent,
			ExpiresAt = expiresAt,
			Expired = expired == true,
			InsertionIndex = insertionIndex,
		}
		local previous = bestByName[ghostProfile.Name]
		if not previous or ranked.Score > previous.Score then
			bestByName[ghostProfile.Name] = ranked
		elseif ranked.Score == previous.Score
			and insertionIndex < previous.InsertionIndex then
			bestByName[ghostProfile.Name] = ranked
		end
	end

	if type(detections) == "table" then
		local insertionIndex = 0
		for _, detection in ipairs(detections) do
			insertionIndex = insertionIndex + 1
			consider(detection, nil, insertionIndex)
		end
		local mapKeys = {}
		for key in pairs(detections) do
			if type(key) == "string" then
				table.insert(mapKeys, key)
			end
		end
		table.sort(mapKeys)
		for _, key in ipairs(mapKeys) do
			insertionIndex = insertionIndex + 1
			consider(detections[key], key, insertionIndex)
		end
	end

	local result = {}
	for _, ranked in pairs(bestByName) do
		table.insert(result, ranked)
	end
	table.sort(result, function(left, right)
		if left.Tier ~= right.Tier then
			return left.Tier > right.Tier
		elseif left.Score ~= right.Score then
			return left.Score > right.Score
		end
		return (orderIndex[left.Ghost] or math.huge) < (orderIndex[right.Ghost] or math.huge)
	end)
	for _, ranked in ipairs(result) do
		ranked.InsertionIndex = nil
	end
	return result
end

local Tracker = {}
Tracker.__index = Tracker

local function copyNestedMap(source)
	local result = {}
	if type(source) == "table" then
		for key, value in pairs(source) do
			result[key] = type(value) == "table" and shallowCopy(value) or value
		end
	end
	return result
end

local function newTracker(initial)
	initial = initial or {}
	local tracker = setmetatable({
		Evidence = {},
		DisprovedEvidence = {},
		RuleOuts = {},
		Detections = {},
	}, Tracker)

	local initialEvidence = initial.Evidence or initial.ObservedEvidence
	local observed, disproved = collectEvidence(initialEvidence, {
		FalseMeansDisproved = initial.FalseMeansDisproved == true,
		DisprovedEvidence = initial.DisprovedEvidence,
	})
	tracker.Evidence = observed
	tracker.DisprovedEvidence = disproved
	tracker.RuleOuts = copyNestedMap(initial.RuleOuts or initial.RuledOut)
	tracker.Detections = copyNestedMap(initial.Detections)
	return tracker
end

function Tracker:SetEvidence(evidence, value)
	local evidenceKey = normalizeEvidence(evidence)
	if not evidenceKey then
		return false
	end
	if value == true then
		self.Evidence[evidenceKey] = true
		self.DisprovedEvidence[evidenceKey] = nil
	elseif value == false then
		self.Evidence[evidenceKey] = nil
		self.DisprovedEvidence[evidenceKey] = true
	else
		self.Evidence[evidenceKey] = nil
		self.DisprovedEvidence[evidenceKey] = nil
	end
	return true
end

function Tracker:ObserveEvidence(evidence)
	return self:SetEvidence(evidence, true)
end

function Tracker:DisproveEvidence(evidence)
	return self:SetEvidence(evidence, false)
end

function Tracker:ClearEvidence(evidence)
	return self:SetEvidence(evidence, nil)
end

function Tracker:RuleOut(ghostName, reason, confidence)
	local ghostProfile = find(ghostName)
	if not ghostProfile then
		return false
	end
	self.RuleOuts[ghostProfile.Name] = {
		Reason = reason,
		Confidence = tonumber(confidence) or 100,
	}
	return true
end

function Tracker:ClearRuleOut(ghostName)
	local ghostProfile = find(ghostName)
	if not ghostProfile or self.RuleOuts[ghostProfile.Name] == nil then
		return false
	end
	self.RuleOuts[ghostProfile.Name] = nil
	return true
end

function Tracker:IsRuledOut(ghostName)
	local ghostProfile = find(ghostName)
	return ghostProfile ~= nil and self.RuleOuts[ghostProfile.Name] ~= nil
end

function Tracker:RecordDetection(ghostName, reasonOrDetection, confidence)
	local ghostProfile = find(ghostName)
	if not ghostProfile then
		return false
	end
	local detection
	if type(reasonOrDetection) == "table" then
		detection = shallowCopy(reasonOrDetection)
	else
		detection = {
			Reason = reasonOrDetection,
			Confidence = tonumber(confidence) or PerkConfidence[ghostProfile.Name] or 0,
		}
	end
	detection.Ghost = ghostProfile.Name
	detection.Confidence = detectionScore(detection)
	local existing = self.Detections[ghostProfile.Name]
	if not existing or detection.Confidence >= detectionScore(existing) then
		self.Detections[ghostProfile.Name] = detection
		return true
	end
	return false
end

function Tracker:ClearDetection(ghostName)
	local ghostProfile = find(ghostName)
	if not ghostProfile or self.Detections[ghostProfile.Name] == nil then
		return false
	end
	self.Detections[ghostProfile.Name] = nil
	return true
end

function Tracker:GetCandidates(options)
	options = shallowCopy(options)
	options.DisprovedEvidence = self.DisprovedEvidence
	return filterCandidates(self.Evidence, self.RuleOuts, options)
end

Tracker.Candidates = Tracker.GetCandidates

function Tracker:Rank(options)
	options = shallowCopy(options)
	options.DisprovedEvidence = self.DisprovedEvidence
	return rankDetections(self.Detections, self.Evidence, self.RuleOuts, options)
end

Tracker.RankDetections = Tracker.Rank

function Tracker:Snapshot()
	return {
		Evidence = shallowCopy(self.Evidence),
		DisprovedEvidence = shallowCopy(self.DisprovedEvidence),
		RuleOuts = copyNestedMap(self.RuleOuts),
		Detections = copyNestedMap(self.Detections),
		Candidates = self:GetCandidates({NamesOnly = true}),
		Ranked = self:Rank(),
	}
end

function Tracker:Clone()
	return newTracker(self:Snapshot())
end

function Tracker:WithEvidence(evidence, value)
	local clone = self:Clone()
	clone:SetEvidence(evidence, value)
	return clone
end

function Tracker:WithRuleOut(ghostName, reason, confidence)
	local clone = self:Clone()
	clone:RuleOut(ghostName, reason, confidence)
	return clone
end

function Tracker:WithDetection(ghostName, reasonOrDetection, confidence)
	local clone = self:Clone()
	clone:RecordDetection(ghostName, reasonOrDetection, confidence)
	return clone
end

function Tracker:Reset()
	self.Evidence = {}
	self.DisprovedEvidence = {}
	self.RuleOuts = {}
	self.Detections = {}
	return self
end

GhostModule.Order = Order
GhostModule.Profiles = Profiles
GhostModule.ByName = ByName
GhostModule.Evidence = EVIDENCE
GhostModule.EvidenceOrder = EVIDENCE_ORDER
GhostModule.PerkConfidence = PerkConfidence
GhostModule.PerkTTL = PerkTTL
GhostModule.TierNames = TIER_NAMES
GhostModule.ConfidenceTier = confidenceTier
GhostModule.Find = find
GhostModule.NormalizeEvidence = normalizeEvidence
GhostModule.SupportsEvidence = supportsEvidence
GhostModule.FilterCandidates = filterCandidates
GhostModule.RankDetections = rankDetections
GhostModule.SelectHighestConfidenceGuess = selectHighestConfidenceGuess
GhostModule.SelectTimeoutGuess = selectTimeoutGuess
GhostModule.NewTracker = newTracker

return GhostModule
end
