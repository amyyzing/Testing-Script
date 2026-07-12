return function(dependencies)
	dependencies = dependencies or {}
	local Services = assert(dependencies.Services, "logic/logic.luau requires Services")
	local player = dependencies.Player or Services.Players.LocalPlayer
	local environment = dependencies.Environment or ((getgenv and getgenv()) or _G)
	local generation = dependencies.Generation
	local GhostModule = assert(dependencies.GhostModule, "logic/logic.luau requires GhostModule")
	local view = assert(dependencies.View, "logic/logic.luau requires View")
	local presenter = dependencies.Presenter

	local COLORS = view.Colors
	local COPY = view.Copy
	local gui = view.Gui
	local evidenceLabels = view.EvidenceLabels
	local speedValue = view.SpeedValue
	local sliderFill = view.SliderFill
	local sliderKnob = view.SliderKnob
	local huntEscapeButton = view.Buttons.HuntEscape
	local ghostEspButton = view.Buttons.GhostEsp
	local itemEspButton = view.Buttons.ItemEsp
	local fullBrightButton = view.Buttons.FullBright
	local placeRoomItemsButton = view.Buttons.PlaceRoomItems
	local autoSpiritBoxButton = view.Buttons.AutoSpiritBox
	local randomLightsButton = view.Buttons.RandomLights
	local toggleFuseBoxButton = view.Buttons.ToggleFuseBox
local walkSpeedForcerButton = view.Buttons.WalkSpeedForcer
	local function new(className, properties)
		local object = Instance.new(className)
		for property, value in pairs(properties or {}) do
			object[property] = value
		end
		return object
	end
	local function setEvidenceLabel(key, text, color)
		if presenter and presenter.SetEvidenceLabel then
			presenter:SetEvidenceLabel(key, text, color)
			return
		end
		local label = evidenceLabels[key]
		if label then
			if text ~= nil then
				label.Text = text
			end
			if color ~= nil then
				label.TextColor3 = color
			end
		end
	end
local connections = {}
local generatedObjects = {}
local closed = false
local function runtimeIsActive()
	return not closed
		and (generation == nil or environment.DemonologyGeneration == generation)
end
local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end
local oldLighting = {
	Ambient = Services.Lighting.Ambient,
	OutdoorAmbient = Services.Lighting.OutdoorAmbient,
	Brightness = Services.Lighting.Brightness,
	GlobalShadows = Services.Lighting.GlobalShadows,
	FogEnd = Services.Lighting.FogEnd,
}
local baseWalkSpeed = 10
local speed = 10
local fullBrightEnabled = false
local ghostEspEnabled = false
local huntEscapeEnabled = false
local huntEscapeTriggered = false
local itemEspEnabled = false
local roomItemPlacementState = {
	busy = false,
	generation = 0,
	thread = nil,
}
local ghostBillboard
local ghostDirectHighlight
local ghostHighlight
local ghostProxyModel
local ghostProxyParts = {}
local ghostEspTarget
local favouriteRoomBillboard
local favouriteRoomBillboardLabel
local favouriteRoomBillboardTarget
local freezingEvidenceFound = false
local spiritBoxTentative = false
local speedLockConnection
local perkDetections = {}
local resetEvidenceState = function() end
local evidenceRoundGhost
local ghoulRuledOut = false
local trackedItemsFolder
local itemsDescendantAddedConnection
local itemEnabledTracked = setmetatable({}, {__mode = "k"})
local itemEnabledStates = setmetatable({}, {__mode = "k"})
local lastDeepEvidenceScan = -math.huge
local ghostProxyDirty = false
local ghostProxyAddedConnection
local ghostProxyRemovingConnection
local observeWalkSpeedChange = function() end
local perkTrackerState = {
	ghost = nil,
	evidenceMode = "Normal",
	speedForcerEnabled = true,
	speedForceAccumulator = 0,
	visualModelChecked = false,
	sampleAccumulator = 0,
	slowScanAccumulator = 0,
	analysisAccumulator = 0,
	lastPosition = nil,
	lastSampleTime = nil,
	lastHunting = nil,
	motionSamples = {},
	losSamples = {},
	energySamples = {},
	transparencyTransitions = {},
	transparencyIntervals = {},
	lastTransparencyState = nil,
	lastTransparencyTransitionTime = nil,
	vexLastValue = nil,
	updateVexState = function() end,
	wendigoSnapshots = {},
	wendigoNextSnapshotAt = 0,
	wendigoSnapshotRandom = Random.new(),
	nonHuntWalkSpeedSamples = {},
	transparencyAttributeConnection = nil,
	specterInitialized = false,
	specterInFavourite = false,
	specterEntryAt = nil,
	specterSawMovement = false,
	specterStationaryCandidateAt = nil,
	specterIdleSince = nil,
	specterStationaryArmed = false,
	specterSuccessCount = 0,
	specterTrackedFavouriteName = nil,
	specterRoomChangePause = false,
	specterRoomChangeSettleSince = nil,
	previousDead = {},
	pendingKill = nil,
	keresKillDecreaseCount = 0,
	aswangKillIncreaseCount = 0,
	killSpeedProcessedPlayers = setmetatable({}, {__mode = "k"}),
	huntStartedAt = nil,
	pendingWispStart = nil,
	wispHuntResults = {},
	wispFavouriteHuntCount = 0,
	umbraSamples = {},
	umbraLastLightStateByRoom = {},
	umbraLightTransitionsByRoom = {},
	umbraRootSoundAbsentTime = 0,
	umbraRootSoundPresentTime = 0,
	umbraLitMatch = nil,
	brokenGlassInitialized = false,
	brokenGlassSeen = {},
	brokenGlassEvents = {},
	sirenSlowEvents = {},
	sirenLosExposure = 0,
	sirenSlowObservedThisHunt = false,
	lastLosLightingKey = nil,
	lastLosTarget = nil,
	dullahanBaselineSpeed = nil,
	dullahanLastSpeed = nil,
	dullahanIncreaseEvents = {},
	dullahanSawLineOfSight = false,
	dullahanHuntSampleCount = 0,
	dullahanLosSampleCount = 0,
	dullahanLosBaseline = nil,
	dullahanMaxLosSpeed = nil,
	dullahanCompletedNoIncreaseHunt = false,
	dybbukMaybeReady = false,
	leviathanToggleEvents = {},
	leviathanLightStates = setmetatable({}, {__mode = "k"}),
	leviathanLastFlickerAt = -math.huge,
	leviathanLastLightOffAt = -math.huge,
	leviathanLightScanAccumulator = 0,
	leviathanTagTrackerInitialized = false,
	suppressItemDisableUntil = 0,
	suppressLeviathanLightsUntil = 0,
	ravagerTrackedObjects = setmetatable({}, {__mode = "k"}),
	ravagerMotionEvents = {},
	ravagerScanAccumulator = 0,
	saltTrackerInitialized = false,
	saltFolder = nil,
	saltTrackedLines = setmetatable({}, {__mode = "k"}),
	saltPendingTouches = setmetatable({}, {__mode = "k"}),
	saltOverlapAccumulator = 0,
	wraithRuledOut = false,
	holyOilFolder = nil,
	holyOilTrackerInitialized = false,
	holyOilTrackedModels = setmetatable({}, {__mode = "k"}),
	holyOilPendingContacts = setmetatable({}, {__mode = "k"}),
	holyOilOverlapAccumulator = 0,
	holyOilFireObserved = false,
	holyOilBurnStartedAt = setmetatable({}, {__mode = "k"}),
	holyOilColorStates = setmetatable({}, {__mode = "k"}),
	evaluateHolyOilAtHuntStart = function() end,
	flashButton = function() end,
	itemEspChildConnection = nil,
	leviathanEligibleItemNames = {
		["laser projector"] = true,
		["emf reader"] = true,
		["spirit box"] = true,
		["blacklight"] = true,
		["flashlight"] = true,
	},
	entityTrackerInitialized = false,
	entitySmokeHolders = setmetatable({}, {__mode = "k"}),
	entitySmokeObserved = false,
	lastSmokeAddedAt = -math.huge,
	objectTeleportTrackerInitialized = false,
	objectTeleportObjects = setmetatable({}, {__mode = "k"}),
	objectTeleportAccumulator = 0,
	pendingObjectTeleports = {},
	recentSmokeEffects = {},
	teleportTrackingStartedAt = 0,
	lastObservedRoom = nil,
	pendingGhostTeleport = nil,
	lastGhostTeleportAt = nil,
	teleportResolvedGhost = nil,
	spiritBoxVoiceSubtitles = {},
	spiritBoxVoiceFolder = nil,
	spiritBoxRemoteBound = false,
	autoSpiritBoxEnabled = false,
	autoSpiritBoxAccumulator = 0,
	autoSpiritBoxQuestionIndex = 0,
	journalGhostTypesContainer = nil,
	journalEvent = nil,
	lastJournalSelectedGhost = nil,
	lastJournalVisualGhost = nil,
	journalDesiredApplicability = {},
	journalMutationBusy = false,
	currentGhostGuess = nil,
	currentGhostGuessScore = 0,
	currentGhostGuessCertain = false,
	syncJournal = function() end,
	orbObserved = false,
	lidarVisibleObserved = false,
	crossItemsFolder = nil,
	crossTrackedModels = setmetatable({}, {__mode = "k"}),
	crossParticleStates = setmetatable({}, {__mode = "k"}),
	activeCrossBurns = setmetatable({}, {__mode = "k"}),
	demonRuledOut = false,
	demonMotionObserved = false,
	ruledOutGhosts = {},
	refreshIdentification = function() end,
}
local evidenceFound = {
	Print = false,
	SpiritBox = false,
	Orb = false,
	Inscription = false,
	Laser = false,
	Wither = false,
}
local highestEMF = 1
local GHOST_PROFILES = GhostModule.Profiles
local PERK_CONFIDENCE = GhostModule.PerkConfidence
local PERK_TTL = GhostModule.PerkTTL
local function confidenceTier(score)
	local tier, name = GhostModule.ConfidenceTier(score)
	local color = tier >= 3 and COLORS.gold
		or tier == 2 and COLORS.orangeGold
		or tier == 1 and COLORS.red
		or COLORS.muted
	return tier, name, color
end
local function setGhostIdentificationLabel(ghostName, score, certain)
	local _, suffix, color = confidenceTier(score)
	if presenter and presenter.SetGhostIdentification then
		presenter:SetGhostIdentification(ghostName, suffix, certain)
		return
	end
	if certain then
		evidenceLabels.Ghost.Text = "Ghost: " .. tostring(ghostName) .. " (Certain)"
		evidenceLabels.Ghost.TextColor3 = COLORS.green
		return
	end
	evidenceLabels.Ghost.Text = "Ghost: " .. tostring(ghostName) .. " (" .. suffix .. ")"
	evidenceLabels.Ghost.TextColor3 = color
end
local function recordPerkDetection(ghostName, reason, confidence)
	if not PERK_CONFIDENCE[ghostName] then
		return
	end
	local now = os.clock()
	local score = confidence or PERK_CONFIDENCE[ghostName]
	local ttl = PERK_TTL[ghostName]
	local persistent = score >= 80
	local existing = perkDetections[ghostName]
	if not existing or score > (existing.Confidence or 0) then
		perkDetections[ghostName] = {
			Confidence = score,
			Reason = reason,
			DetectedAt = now,
			ExpiresAt = if persistent then nil elseif ttl then now + ttl else nil,
			Tentative = true,
			Persistent = persistent,
		}
		return
	end
	if score == (existing.Confidence or 0) then
		existing.Reason = reason or existing.Reason
		existing.DetectedAt = now
		if persistent or existing.Persistent
			or (existing.Confidence or 0) >= 80 then
			existing.Persistent = true
			existing.ExpiresAt = nil
		elseif ttl then
			existing.ExpiresAt = now + ttl
		end
		return
	end
	if existing.Persistent
		or (existing.Confidence or 0) >= 80 then
		existing.Persistent = true
		existing.ExpiresAt = nil
	elseif ttl then
		existing.ExpiresAt = now + ttl
	end
end
local function clearPerkDetection(ghostName)
	perkDetections[ghostName] = nil
end
local function clearAllPerkDetections()
	for ghostName in pairs(perkDetections) do
		perkDetections[ghostName] = nil
	end
end
perkTrackerState.ruleOutGhost = function(ghostName, reason, confidence)
	confidence = tonumber(confidence) or 0
	if confidence < 80 then
		return false
	end
	local existing = perkTrackerState.ruledOutGhosts[ghostName]
	if existing and existing.Confidence >= confidence then
		return false
	end
	perkTrackerState.ruledOutGhosts[ghostName] = {
		Confidence = confidence,
		Reason = reason,
		At = os.clock(),
	}
	clearPerkDetection(ghostName)
	perkTrackerState.refreshIdentification()
	return true
end
perkTrackerState.clearGhostRuleOut = function(ghostName)
	if perkTrackerState.ruledOutGhosts[ghostName] then
		perkTrackerState.ruledOutGhosts[ghostName] = nil
		return true
	end
	return false
end
perkTrackerState.isGhostRuledOut = function(ghostName)
	return perkTrackerState.ruledOutGhosts[ghostName] ~= nil
end
local function getConfirmedEvidence()
	return {
		EMFLevel5 = highestEMF >= 5,
		SpiritBox = evidenceFound.SpiritBox,
		GhostWriting = evidenceFound.Inscription,
		FreezingTemperatures = freezingEvidenceFound,
		GhostOrb = evidenceFound.Orb,
		Handprints = evidenceFound.Print,
		LaserProjector = evidenceFound.Laser,
		Wither = evidenceFound.Wither,
	}
end
local function getObservedEvidence()
	local observed = getConfirmedEvidence()
	if spiritBoxTentative then
		observed.SpiritBox = true
	end
	if perkTrackerState.orbObserved then
		observed.GhostOrb = true
	end
	return observed
end
local function countConfirmedEvidence(confirmed)
	local count = 0
	for _, found in pairs(confirmed) do
		if found then
			count = count + 1
		end
	end
	return count
end
local function findGhostProfile(ghostName)
	return GhostModule.Find(ghostName)
end
local function evidenceSetForProfile(profile)
	local evidenceSet = {}
	for _, evidenceName in ipairs(profile.Evidence) do
		evidenceSet[evidenceName] = true
	end
	return evidenceSet
end
local function ghostSupportsConfirmedEvidence(
	ghostName,
	confirmed,
	ignoreRuleOut
)
	if not ignoreRuleOut then
		if perkTrackerState.isGhostRuledOut(ghostName) then
			return false
		end
		if ghostName == "Ghoul" and ghoulRuledOut then
			return false
		end
		if ghostName == "Demon" and perkTrackerState.demonRuledOut then
			return false
		end
		if ghostName == "Wraith" and perkTrackerState.wraithRuledOut then
			return false
		end
	end

	local profile = findGhostProfile(ghostName)
	if not profile then
		return false
	end

	local mimicry =
		perkTrackerState.evidenceMode == "Mimicry"
	local allowed = evidenceSetForProfile(profile)

	if not mimicry and ghostName == "Skinwalker" then
		allowed.GhostOrb = true
	end

	for evidenceName, found in pairs(confirmed) do
		if found then
			if mimicry and allowed[evidenceName] then
				return false
			elseif not mimicry and not allowed[evidenceName] then
				return false
			end
		end
	end

	local orbObserved =
		evidenceFound.Orb or perkTrackerState.orbObserved
	if orbObserved then
		if mimicry and allowed.GhostOrb then
			return false
		elseif not mimicry
			and ghostName ~= "Skinwalker"
			and not allowed.GhostOrb then
			return false
		end
	end

	return true
end
perkTrackerState.getRemainingCandidates = function(ignoreRuleOut)
	local confirmed = getConfirmedEvidence()
	if perkTrackerState.evidenceMode ~= "Mimicry" then
		local candidateEvidence = {}
		for evidenceName, found in pairs(confirmed) do
			candidateEvidence[evidenceName] = found
		end
		if perkTrackerState.orbObserved then
			candidateEvidence.GhostOrb = true
		end
		local ruleOuts = {}
		if ignoreRuleOut ~= true then
			for ghostName in pairs(perkTrackerState.ruledOutGhosts) do
				ruleOuts[ghostName] = true
			end
		end
		if ignoreRuleOut ~= true then
			if ghoulRuledOut then
				ruleOuts.Ghoul = true
			end
			if perkTrackerState.demonRuledOut then
				ruleOuts.Demon = true
			end
			if perkTrackerState.wraithRuledOut then
				ruleOuts.Wraith = true
			end
		end
		return GhostModule.FilterCandidates(candidateEvidence, ruleOuts, {
			NamesOnly = true,
			IncludeFalseEvidence = true,
		})
	end
	local candidates = {}
	for _, profile in ipairs(GHOST_PROFILES) do
		local ghostName = profile.Name
		if ghostSupportsConfirmedEvidence(
			ghostName,
			confirmed,
			ignoreRuleOut == true
		) then
			table.insert(candidates, ghostName)
		end
	end
	return candidates
end
perkTrackerState.candidateSupportsEvidence = function(ghostName, evidenceName)
	return GhostModule.SupportsEvidence(ghostName, evidenceName, {
		IncludeFalseEvidence = true,
	}) == true
end
perkTrackerState.updateOrbEvidence = function()
	if perkTrackerState.evidenceMode == "Mimicry" then
		return
	end
	if not perkTrackerState.orbObserved or evidenceFound.Orb then
		return
	end
	local confirmed = getConfirmedEvidence()
	local skinwalkerAllowed = {
		FreezingTemperatures = true,
		GhostWriting = true,
		SpiritBox = true,
		GhostOrb = true,
	}
	for evidenceName, found in pairs(confirmed) do
		if found and not skinwalkerAllowed[evidenceName] then
			evidenceFound.Orb = true
			return
		end
	end
end
perkTrackerState.updateEvidenceStatuses = function()
	local candidates = perkTrackerState.getRemainingCandidates(false)
	if #candidates == 0 then
		candidates = perkTrackerState.getRemainingCandidates(true)
	end
	local possible = {}
	for _, ghostName in ipairs(candidates) do
		for _, evidenceName in ipairs({
			"EMFLevel5",
			"SpiritBox",
			"GhostWriting",
			"FreezingTemperatures",
			"GhostOrb",
			"Handprints",
			"LaserProjector",
			"Wither",
		}) do
			local supports = perkTrackerState.candidateSupportsEvidence(
				ghostName,
				evidenceName
			)
			if perkTrackerState.evidenceMode == "Mimicry" then
				supports = not GhostModule.SupportsEvidence(
					ghostName,
					evidenceName,
					{RealOnly = true}
				)
			end
			if supports then
				possible[evidenceName] = true
			end
		end
	end
	local confirmed = getConfirmedEvidence()
	local rows = {
		Print = {COPY.Evidence.Print, "Handprints"},
		SpiritBox = {COPY.Evidence.SpiritBox, "SpiritBox"},
		Orb = {COPY.Evidence.Orb, "GhostOrb"},
		Inscription = {COPY.Evidence.Inscription, "GhostWriting"},
		Laser = {COPY.Evidence.Laser, "LaserProjector"},
		Wither = {COPY.Evidence.Wither, "Wither"},
	}
	for key, row in pairs(rows) do
		local displayName = row[1]
		local evidenceName = row[2]
		local isConfirmed = confirmed[evidenceName] == true
		local isMaybe =
			(key == "Orb" and perkTrackerState.orbObserved)
			or (key == "SpiritBox" and spiritBoxTentative)
		if isConfirmed then
			if perkTrackerState.evidenceMode == "Mimicry" then
				setEvidenceLabel(key, displayName .. ": Fake", COLORS.orangeGold)
			else
				setEvidenceLabel(key, displayName .. ": Yes", COLORS.green)
			end
		elseif isMaybe then
			setEvidenceLabel(
				key,
				displayName .. (perkTrackerState.evidenceMode == "Mimicry" and ": Fake?" or ": Maybe"),
				COLORS.orangeGold
			)
		elseif not possible[evidenceName] then
			setEvidenceLabel(key, displayName .. ": Impossible", COLORS.red)
		else
			setEvidenceLabel(key, displayName .. ": Unknown", COLORS.muted)
		end
	end
	if highestEMF >= 5 then
		if perkTrackerState.evidenceMode == "Mimicry" then
			setEvidenceLabel("EMF", "EMF-5 (Fake)", COLORS.orangeGold)
		else
			setEvidenceLabel("EMF", "EMF-5", COLORS.green)
		end
	elseif not possible.EMFLevel5 then
		setEvidenceLabel("EMF", "EMF-" .. tostring(highestEMF) .. " (Impossible)", COLORS.red)
	else
		setEvidenceLabel("EMF", "EMF-" .. tostring(highestEMF), COLORS.muted)
	end
	if freezingEvidenceFound then
		setEvidenceLabel(
			"Temperature",
			nil,
			perkTrackerState.evidenceMode == "Mimicry" and COLORS.orangeGold or COLORS.green
		)
	elseif not possible.FreezingTemperatures then
		setEvidenceLabel("Temperature", nil, COLORS.red)
	else
		setEvidenceLabel("Temperature", nil, COLORS.text)
	end
end
perkTrackerState.updateOrbLabel = function()
	perkTrackerState.updateEvidenceStatuses()
end
local function getBestPerkDetection(confirmed)
	local now = os.clock()
	for ghostName, detection in pairs(perkDetections) do
		local score = detection.Confidence or 0
		if score >= 80 or detection.Persistent then
			detection.Persistent = true
			detection.ExpiresAt = nil
		elseif detection.ExpiresAt
			and now > detection.ExpiresAt then
			perkDetections[ghostName] = nil
			continue
		end
	end
	local ranked = GhostModule.RankDetections(perkDetections, {}, {}, {Now = now})
	local candidates = {}
	for _, candidate in ipairs(ranked) do
		if not perkTrackerState.isGhostRuledOut(candidate.Ghost)
			and ghostSupportsConfirmedEvidence(candidate.Ghost, confirmed) then
			table.insert(candidates, candidate)
		end
	end
	if #candidates == 0 then
		return nil, nil
	end
	local top = candidates[1]
	local tiedNames = {top.Ghost}
	for index = 2, #candidates do
		local candidate = candidates[index]
		if candidate.Tier ~= top.Tier then
			break
		end
		if top.Tier < 3
			and math.abs(candidate.Score - top.Score) >= 10 then
			break
		end
		table.insert(tiedNames, candidate.Ghost)
	end
	if #tiedNames > 1 then
		table.sort(tiedNames)
		return table.concat(tiedNames, " / "), {
			Confidence = top.Score,
			Reason =
				"multiple compatible detections had the same confidence tier",
			Tentative = true,
			Persistent = top.Score >= 80,
		}
	end
	return top.Ghost, top.Detection
end
local function profileMatches(profile, confirmed)
	if profile.Name == "Demon" and perkTrackerState.demonRuledOut then
		return false
	end
	for _, evidenceName in ipairs(profile.Evidence) do
		if not confirmed[evidenceName] then
			return false
		end
	end
	return true
end
local function isExactEvidenceSet(confirmed, names)
	if countConfirmedEvidence(confirmed) ~= #names then
		return false
	end
	for _, evidenceName in ipairs(names) do
		if not confirmed[evidenceName] then
			return false
		end
	end
	return true
end
local function identifyGhostFromEvidence()
	if perkTrackerState.evidenceMode == "Mimicry" then
		return nil
	end
	local confirmed = getConfirmedEvidence()
	local confirmedCount = countConfirmedEvidence(confirmed)
	if isExactEvidenceSet(confirmed, {
		"FreezingTemperatures",
		"GhostWriting",
		"SpiritBox",
	}) or isExactEvidenceSet(confirmed, {
		"FreezingTemperatures",
		"GhostWriting",
		"SpiritBox",
		"GhostOrb",
	}) then
		return "Skinwalker"
	end
	if confirmedCount == 3 then
		for _, profile in ipairs(GHOST_PROFILES) do
			if profileMatches(profile, confirmed) then
				return profile.Name
			end
		end
	end
	return nil
end
local function identifyTentativeGhostFromEvidence()
	if perkTrackerState.evidenceMode == "Mimicry" then
		return nil
	end
	local confirmed = getConfirmedEvidence()
	local observed = getObservedEvidence()
	local observedCount = countConfirmedEvidence(observed)
	if spiritBoxTentative and not evidenceFound.SpiritBox
		and isExactEvidenceSet(observed, {
			"FreezingTemperatures",
			"GhostWriting",
			"SpiritBox",
			"GhostOrb",
		}) then
		return "Skinwalker", 35
	end
	if isExactEvidenceSet(observed, {
		"FreezingTemperatures",
		"GhostOrb",
		"SpiritBox",
	}) then
		return ghoulRuledOut and "Skinwalker" or "Ghoul / Skinwalker", 35
	end
	if spiritBoxTentative and not evidenceFound.SpiritBox and observedCount == 3 then
		for _, profile in ipairs(GHOST_PROFILES) do
			if profileMatches(profile, observed) then
				if profile.Name == "Ghoul" and ghoulRuledOut then
					return "Skinwalker", 60
				end
				return profile.Name, 60
			end
		end
	end
	if perkTrackerState.orbObserved
		and not evidenceFound.Orb
		and observedCount == 3 then
		for _, profile in ipairs(GHOST_PROFILES) do
			if profileMatches(profile, observed) then
				if profile.Name == "Ghoul" then
					return ghoulRuledOut and "Skinwalker" or "Ghoul / Skinwalker", 35
				end
				return profile.Name, 35
			end
		end
	end
	if observedCount == 3 and observed.GhostOrb then
		local skinwalkerRealEvidence = {
			FreezingTemperatures = true,
			GhostWriting = true,
			SpiritBox = true,
		}
		local matchingRealEvidence = 0
		for evidenceName, found in pairs(observed) do
			if found and evidenceName ~= "GhostOrb" then
				if not skinwalkerRealEvidence[evidenceName] then
					return nil
				end
				matchingRealEvidence = matchingRealEvidence + 1
			end
		end
		if matchingRealEvidence == 2 then
			return "Skinwalker", 35
		end
	end
	if countConfirmedEvidence(confirmed) >= 3 then
		return nil
	end
	return nil
end
perkTrackerState.resolveTeleportEvidence = function(confirmed)
	if perkTrackerState.teleportResolvedGhost == "Entity" then
		return "Entity"
	end
	if perkTrackerState.teleportResolvedGhost ~= "Ambiguous" then
		return nil
	end
	local hasEvidence = false
	local skinwalkerCompatible = true
	local skinwalkerSpecificSupport = false
	local skinwalkerAllowed = {
		FreezingTemperatures = true,
		GhostWriting = true,
		SpiritBox = true,
		GhostOrb = true,
	}
	local entityNormalEvidence = {
		Handprints = true,
		LaserProjector = true,
		SpiritBox = true,
	}
	for evidenceName, found in pairs(confirmed) do
		if found then
			hasEvidence = true
			if not skinwalkerAllowed[evidenceName] then
				skinwalkerCompatible = false
			end
			if skinwalkerAllowed[evidenceName] and not entityNormalEvidence[evidenceName] then
				skinwalkerSpecificSupport = true
			end
		end
	end
	if hasEvidence and not skinwalkerCompatible then
		return "Entity"
	end
	if skinwalkerSpecificSupport then
		return "Skinwalker"
	end
	return nil
end
local function updateGhostIdentification(ghost)
	local evidenceGhost = identifyGhostFromEvidence()
	if evidenceGhost then
		perkTrackerState.currentGhostGuess = evidenceGhost
		perkTrackerState.currentGhostGuessScore = 100
		perkTrackerState.currentGhostGuessCertain = true
		setGhostIdentificationLabel(evidenceGhost, 100, true)
		perkTrackerState.updateEvidenceStatuses()
		perkTrackerState.syncJournal()
		return
	end
	local confirmed = getConfirmedEvidence()
	local observed = getObservedEvidence()
	local candidates = perkTrackerState.getRemainingCandidates(false)
	local perkGhost, perkDetection = getBestPerkDetection(confirmed)
	local tentativeEvidenceGhost, tentativeEvidenceScore =
		identifyTentativeGhostFromEvidence()
	local teleportEvidenceGhost =
		perkTrackerState.resolveTeleportEvidence(observed)
	local selectedGhost = perkGhost
	local selectedScore =
		perkDetection and perkDetection.Confidence or 0
	local strongPerkLocked =
		perkDetection
		and (perkDetection.Confidence or 0) >= 80
		or false
	local function consider(ghostName, score)
		if not ghostName then
			return
		end
		local compatibleNames = {}
		for name in string.gmatch(
			tostring(ghostName),
			"[^/]+"
		) do
			name = string.gsub(name, "^%s+", "")
			name = string.gsub(name, "%s+$", "")
			if findGhostProfile(name)
				and ghostSupportsConfirmedEvidence(
					name,
					confirmed,
					false
				) then
				table.insert(compatibleNames, name)
			end
		end
		if #compatibleNames == 0 then
			return
		end
		ghostName = table.concat(compatibleNames, " / ")
		local selectedTier = confidenceTier(selectedScore)
		local newTier = confidenceTier(score)
		if strongPerkLocked and score < 80 then
			return
		end
		if not selectedGhost
			or newTier > selectedTier
			or (newTier == selectedTier and score > selectedScore) then
			selectedGhost = ghostName
			selectedScore = score
		elseif newTier == selectedTier
			and math.abs(score - selectedScore) < 10
			and not string.find(
				selectedGhost,
				ghostName,
				1,
				true
			) then
			selectedGhost = selectedGhost .. " / " .. ghostName
		end
	end
	consider(teleportEvidenceGhost, 65)
	consider(tentativeEvidenceGhost, tentativeEvidenceScore or 0)
	if #candidates == 1 then
		consider(candidates[1], 90)
	elseif not selectedGhost and #candidates > 1 and #candidates <= 3 then
		table.sort(candidates)
		selectedGhost = table.concat(candidates, " / ")
		selectedScore = 35
	end
	if selectedGhost then
		perkTrackerState.currentGhostGuess = selectedGhost
		perkTrackerState.currentGhostGuessScore = selectedScore
		perkTrackerState.currentGhostGuessCertain = false
		setGhostIdentificationLabel(
			selectedGhost,
			selectedScore,
			false
		)
	else
		perkTrackerState.currentGhostGuess = nil
		perkTrackerState.currentGhostGuessScore = 0
		perkTrackerState.currentGhostGuessCertain = false
		if presenter and presenter.SetGhostIdentification then
			presenter:SetGhostIdentification(nil)
		else
			setEvidenceLabel("Ghost", "Ghost: Unknown (Idk)", COLORS.muted)
		end
	end
	perkTrackerState.updateEvidenceStatuses()
	perkTrackerState.syncJournal()
end
perkTrackerState.refreshIdentification = function()
	updateGhostIdentification(perkTrackerState.ghost)
end
perkTrackerState.findJournalGhostTypes = function()
	local cached = perkTrackerState.journalGhostTypesContainer
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if cached
		and cached.Parent
		and playerGui
		and cached:IsDescendantOf(playerGui) then
		return cached
	end
	perkTrackerState.journalGhostTypesContainer = nil
	if not playerGui then
		return nil
	end
	local journal = playerGui:FindFirstChild("Journal")
	if not journal then
		return nil
	end
	local holder = journal:FindFirstChild("Holder")
	local pages = holder and holder:FindFirstChild("Pages")
	local page4 = pages and pages:FindFirstChild("Page4")
	local right = page4 and page4:FindFirstChild("Right")
	local page = right and right:FindFirstChild("Page")
	local direct = page and page:FindFirstChild("GhostTypes")
	if direct then
		perkTrackerState.journalGhostTypesContainer = direct
		return direct
	end
	for _, descendant in ipairs(journal:GetDescendants()) do
		if descendant.Name == "GhostTypes" then
			local matchingFrames = 0
			for _, child in ipairs(descendant:GetChildren()) do
				if child:IsA("Frame")
					and child:FindFirstChild("Highlight")
					and child:FindFirstChild("Strikethrough") then
					matchingFrames = matchingFrames + 1
				end
			end
			if matchingFrames >= 5 then
				perkTrackerState.journalGhostTypesContainer =
					descendant
				return descendant
			end
		end
	end
	return nil
end
perkTrackerState.readJournalRowState = function(frame)
	if not frame then
		return nil
	end
	local highlight = frame:FindFirstChild("Highlight")
	local strike = frame:FindFirstChild("Strikethrough")
	if highlight and highlight:IsA("GuiObject")
		and highlight.Visible then
		return true
	end
	if strike and strike:IsA("GuiObject")
		and strike.Visible then
		return false
	end
	return nil
end
perkTrackerState.triggerJournalClick = function(frame)
	local button = frame and frame:FindFirstChild("Detection")
	if not button or not button:IsA("GuiButton") then
		return false
	end
	local fired = false
	pcall(function()
		if typeof(firesignal) == "function" then
			firesignal(button.MouseButton1Click)
			fired = true
		end
	end)
	if not fired then
		pcall(function()
			if typeof(getconnections) == "function" then
				local connections =
					getconnections(button.MouseButton1Click)
				for _, connection in ipairs(connections) do
					local callback = connection.Function
					if typeof(callback) == "function" then
						callback()
						fired = true
					end
				end
			end
		end)
	end
	if not fired then
		pcall(function()
			button:Activate()
			fired = true
		end)
	end
	return fired
end
perkTrackerState.applyJournalRowState = function(frame, desiredState)
	local current =
		perkTrackerState.readJournalRowState(frame)
	if current == desiredState then
		return true
	end
	for _ = 1, 2 do
		if not perkTrackerState.triggerJournalClick(frame) then
			break
		end
		task.wait(0.03)
		current = perkTrackerState.readJournalRowState(frame)
		if current == desiredState then
			return true
		end
	end
	return current == desiredState
end
perkTrackerState.syncJournal = function()
	if closed or perkTrackerState.journalMutationBusy then
		return
	end
	local candidates =
		perkTrackerState.getRemainingCandidates(false)
	local candidateSet = {}
	for _, ghostName in ipairs(candidates) do
		candidateSet[ghostName] = true
	end
	local selectedGhost
	local guess = perkTrackerState.currentGhostGuess
	local score = perkTrackerState.currentGhostGuessScore or 0
	if guess
		and score >= 80
		and not string.find(guess, "/", 1, true)
		and candidateSet[guess] then
		selectedGhost = guess
	end
	local ghostTypes =
		perkTrackerState.findJournalGhostTypes()
	if ghostTypes then
		perkTrackerState.journalMutationBusy = true
		for _, profile in ipairs(GHOST_PROFILES) do
			local ghostName = profile.Name
			local applicable = candidateSet[ghostName] == true
			local previous =
				perkTrackerState.journalDesiredApplicability[
					ghostName
				]
			if previous == nil then
				previous = true
			end
			if previous ~= applicable then
				local frame =
					ghostTypes:FindFirstChild(ghostName)
				if frame and frame:IsA("Frame") then
					local current =
						perkTrackerState.readJournalRowState(frame)
					if applicable then
						if current == false then
							perkTrackerState.applyJournalRowState(
								frame,
								nil
							)
						end
					else
						perkTrackerState.applyJournalRowState(
							frame,
							false
						)
					end
					perkTrackerState.journalDesiredApplicability[
						ghostName
					] = applicable
				end
			end
		end
		if selectedGhost
			~= perkTrackerState.lastJournalVisualGhost then
			local selectedFrame =
				selectedGhost
				and ghostTypes:FindFirstChild(selectedGhost)
			local selectedApplied = false
			if selectedFrame
				and selectedFrame:IsA("Frame") then
				selectedApplied =
					perkTrackerState.applyJournalRowState(
						selectedFrame,
						true
					)
			end
			if selectedApplied then
				perkTrackerState.lastJournalSelectedGhost =
					selectedGhost
				perkTrackerState.lastJournalVisualGhost =
					selectedGhost
			elseif selectedGhost then
				local events =
					Services.ReplicatedStorage:FindFirstChild("Events")
				local event =
					events and events:FindFirstChild(
						"EvidenceMarkedInJournal"
					)
				if event and event:IsA("RemoteEvent") then
					pcall(function()
						event:FireServer(selectedGhost)
					end)
				end
			end
		end
		perkTrackerState.journalMutationBusy = false
		return
	end
	if selectedGhost
		and selectedGhost
			~= perkTrackerState.lastJournalSelectedGhost then
		local events =
			Services.ReplicatedStorage:FindFirstChild("Events")
		local event =
			events and events:FindFirstChild(
				"EvidenceMarkedInJournal"
			)
		if event and event:IsA("RemoteEvent") then
			local sent = pcall(function()
				event:FireServer(selectedGhost)
			end)
			if sent then
				perkTrackerState.lastJournalSelectedGhost =
					selectedGhost
			end
		end
	end
end
perkTrackerState.getAutoSpiritBoxQuestion = function()
	local questions = {}
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local questionGui =
		playerGui
		and playerGui:FindFirstChild("SpiritBoxQuestions")
	local holder =
		questionGui and questionGui:FindFirstChild("Holder")
	if holder then
		for _, categoryName in ipairs({
			"Aggression",
			"Location",
			"Age",
		}) do
			local category = holder:FindFirstChild(categoryName)
			local detection =
				category and category:FindFirstChild("Detection")
			local question
			pcall(function()
				question = detection and detection.Text
			end)
			if typeof(question) == "string"
				and question ~= "" then
				table.insert(questions, question)
			end
		end
	end
	if #questions == 0 then
		table.insert(
			questions,
			"Are you in the room with me?"
		)
	end
	perkTrackerState.autoSpiritBoxQuestionIndex =
		(perkTrackerState.autoSpiritBoxQuestionIndex
			% #questions)
		+ 1
	return questions[
		perkTrackerState.autoSpiritBoxQuestionIndex
	]
end
perkTrackerState.updateAutoSpiritBox = function(deltaTime)
	if closed or not perkTrackerState.autoSpiritBoxEnabled then
		return
	end
	perkTrackerState.autoSpiritBoxAccumulator =
		perkTrackerState.autoSpiritBoxAccumulator
		+ deltaTime
	if perkTrackerState.autoSpiritBoxAccumulator < 2.05 then
		return
	end
	perkTrackerState.autoSpiritBoxAccumulator = 0
	local events =
		Services.ReplicatedStorage:FindFirstChild("Events")
	local remote =
		events and events:FindFirstChild("AskSpiritBoxFromUI")
	if not remote or not remote:IsA("RemoteEvent") then
		return
	end
	local question =
		perkTrackerState.getAutoSpiritBoxQuestion()
	pcall(function()
		remote:FireServer(question)
	end)
end
perkTrackerState.getTrackedWorldItemModel = function(object)
	local current = object
	while current and current ~= workspace do
		if current:IsA("Model") and current:IsDescendantOf(workspace) then
			if Services.CollectionService:HasTag(current, "Item") then
				return current
			end
			if trackedItemsFolder and current.Parent == trackedItemsFolder then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end
local function leviathanWorldPosition(instance)
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		local ok, pivot = pcall(instance.GetPivot, instance)
		if ok then
			return pivot.Position
		end
	end
	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end
local function leviathanGhostLikelyCause(ghost, target, maxDistance)
	if not ghost or not ghost:IsA("Model") then
		return false
	end
	local targetPosition = leviathanWorldPosition(target)
	local ghostPosition = leviathanWorldPosition(ghost)
	if not targetPosition or not ghostPosition then
		return false
	end
	local ghostDistance = (ghostPosition - targetPosition).Magnitude
	if ghostDistance > (maxDistance or 45) then
		return false
	end
	local nearestPlayerDistance = math.huge
	for _, targetPlayer in ipairs(Services.Players:GetPlayers()) do
		if targetPlayer:GetAttribute("Dead") ~= true then
			local root = targetPlayer.Character
				and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
			if root then
				nearestPlayerDistance = math.min(
					nearestPlayerDistance,
					(root.Position - targetPosition).Magnitude
				)
			end
		end
	end
	return nearestPlayerDistance > 12 or ghostDistance + 3 < nearestPlayerDistance
end
perkTrackerState.recordLeviathanClue = function(kind, reason, now)
	now = now or os.clock()
	if kind == "Flicker" then
		perkTrackerState.leviathanLastFlickerAt = now
	elseif kind == "LightOff" then
		perkTrackerState.leviathanLastLightOffAt = now
	end
	local corroborated = now - perkTrackerState.leviathanLastFlickerAt <= 12
		and now - perkTrackerState.leviathanLastLightOffAt <= 12
	local skinwalkerPossible = ghostSupportsConfirmedEvidence(
		"Skinwalker",
		getConfirmedEvidence()
	)
	local confidence = corroborated and 99 or 60
	local suffix = corroborated
		and "; both out-of-hunt equipment flicker and a room light shutoff were observed"
		or "; this single ability is not unique"
	recordPerkDetection("Leviathan", reason .. suffix, confidence)
	if not corroborated and skinwalkerPossible then
		recordPerkDetection(
			"Skinwalker",
			"Skinwalker may mimic one Leviathan light or equipment ability",
			60
		)
	end
	updateGhostIdentification(nil)
end
perkTrackerState.recordLeviathanToggle = function(object, previous, current)
	if typeof(previous) ~= "boolean"
		or typeof(current) ~= "boolean"
		or previous == current then
		return
	end
	local model = perkTrackerState.getTrackedWorldItemModel(object)
	if not model then
		return
	end
	local itemName = string.lower(
		tostring(model:GetAttribute("ItemName") or "")
	)
	if not perkTrackerState.leviathanEligibleItemNames[itemName] then
		return
	end
	local now = os.clock()
	local ghost = workspace:FindFirstChild("Ghost")
	if not ghost
		or not ghost:IsA("Model")
		or ghost:GetAttribute("Hunting") == true
		or now < perkTrackerState.suppressItemDisableUntil then
		return
	end
	table.insert(perkTrackerState.leviathanToggleEvents, {
		Time = now,
		Model = model,
		State = current,
	})
	local modelEvents = {}
	for index = #perkTrackerState.leviathanToggleEvents, 1, -1 do
		local event = perkTrackerState.leviathanToggleEvents[index]
		if now - event.Time > 3.0 then
			table.remove(
				perkTrackerState.leviathanToggleEvents,
				index
			)
		elseif event.Model == model then
			table.insert(modelEvents, 1, event)
		end
	end
	if #modelEvents < 9 then
		return
	end
	local alternatingCount = 1
	local largestGap = 0
	local firstTime = modelEvents[1].Time
	local lastTime = firstTime
	local lastState = modelEvents[1].State
	for index = 2, #modelEvents do
		local event = modelEvents[index]
		local gap = event.Time - lastTime
		largestGap = math.max(largestGap, gap)
		if event.State ~= lastState then
			alternatingCount = alternatingCount + 1
		else
			alternatingCount = 1
			firstTime = event.Time
		end
		lastState = event.State
		lastTime = event.Time
	end
	local sequenceDuration = lastTime - firstTime
	if alternatingCount >= 9
		and sequenceDuration >= 0.55
		and sequenceDuration <= 3.0
		and largestGap <= 0.75 then
		if not leviathanGhostLikelyCause(ghost, model, 40) then
			return
		end
		perkTrackerState.recordLeviathanClue(
			"Flicker",
			(itemName ~= "" and itemName or "eligible electronic item")
				.. " produced "
				.. tostring(alternatingCount)
				.. " clean alternating toggles within "
				.. string.format("%.2f", sequenceDuration)
				.. " seconds",
			now
		)
	end
end
perkTrackerState.updateLeviathanLightTracker = function(ghost, hunting, deltaTime, now)
	perkTrackerState.leviathanLightScanAccumulator =
		perkTrackerState.leviathanLightScanAccumulator + deltaTime
	if perkTrackerState.leviathanLightScanAccumulator < 0.2 then
		return
	end
	perkTrackerState.leviathanLightScanAccumulator = 0
	local map = workspace:FindFirstChild("Map")
	local rooms = map and map:FindFirstChild("Rooms")
	if not ghost or not rooms then
		return
	end
	for _, room in ipairs(rooms:GetChildren()) do
		local current = room:GetAttribute("LightsOn")
		if typeof(current) == "boolean" then
			local previous = perkTrackerState.leviathanLightStates[room]
			perkTrackerState.leviathanLightStates[room] = current
			if previous == true
				and current == false
				and not hunting
				and room:GetAttribute("LightsBroken") ~= true
				and now >= perkTrackerState.suppressLeviathanLightsUntil then
				local lightSwitch = room:FindFirstChild("LightSwitch", true)
				if lightSwitch and leviathanGhostLikelyCause(ghost, lightSwitch, 45) then
					perkTrackerState.recordLeviathanClue(
						"LightOff",
						"room " .. tostring(room.Name) .. " switched its lights off outside a hunt",
						now
					)
				end
			end
		end
	end
end
local function bindGhoulRuleOutItem(object)
	if not object or itemEnabledTracked[object] then
		return
	end
	local inItemsFolder =
		trackedItemsFolder
		and object:IsDescendantOf(trackedItemsFolder)
	local model = perkTrackerState.getTrackedWorldItemModel(object)
	local itemName = model
		and string.lower(
			tostring(model:GetAttribute("ItemName") or "")
		)
	local leviathanEligible =
		model
		and perkTrackerState.leviathanEligibleItemNames[itemName]
	if not inItemsFolder and not leviathanEligible then
		return
	end
	if object:GetAttribute("Enabled") == nil then
		return
	end
	itemEnabledTracked[object] = true
	itemEnabledStates[object] = object:GetAttribute("Enabled")
	connect(object:GetAttributeChangedSignal("Enabled"), function()
		if closed or object.Parent == nil then
			return
		end
		local previous = itemEnabledStates[object]
		local current = object:GetAttribute("Enabled")
		itemEnabledStates[object] = current
		perkTrackerState.recordLeviathanToggle(
			object,
			previous,
			current
		)
		if trackedItemsFolder
			and object:IsDescendantOf(trackedItemsFolder)
			and previous == true
			and current == false
			and os.clock()
				>= perkTrackerState.suppressItemDisableUntil then
			local ghost = workspace:FindFirstChild("Ghost")
			if ghost and not ghost:IsA("Model") then
				ghost = nil
			end
			local itemPosition
			local itemTarget = model or object
			if itemTarget and itemTarget:IsA("BasePart") then
				itemPosition = itemTarget.Position
			elseif itemTarget and itemTarget:IsA("Model") then
				local ok, pivot = pcall(function()
					return itemTarget:GetPivot()
				end)
				if ok then
					itemPosition = pivot.Position
				end
			end
			local ghostPosition =
				ghost and ghost:GetPivot().Position or nil
			if ghostPosition and itemPosition then
				local ghostDistance =
					(ghostPosition - itemPosition).Magnitude
				local nearestPlayerDistance = math.huge
				for _, targetPlayer in ipairs(
					Services.Players:GetPlayers()
				) do
					if targetPlayer:GetAttribute("Dead") ~= true then
						local root = targetPlayer.Character
							and targetPlayer.Character:FindFirstChild(
								"HumanoidRootPart"
							)
						if root then
							nearestPlayerDistance = math.min(
								nearestPlayerDistance,
								(root.Position - itemPosition).Magnitude
							)
						end
					end
				end
				local ghostWasLikelyCause =
					ghost:GetAttribute("Hunting") == true
					and ghostDistance <= 40
					and (
						nearestPlayerDistance > 12
						or ghostDistance + 3
							< nearestPlayerDistance
					)
				if ghostWasLikelyCause then
					ghoulRuledOut = true
					perkTrackerState.ruleOutGhost(
						"Ghoul",
						"a world electronic was disabled near the ghost while no player was the nearer cause",
						98
					)
				end
			end
		end
	end)
end
perkTrackerState.bindLeviathanTaggedItem = function(model)
	if closed
		or not model
		or not model:IsA("Model")
		or not model:IsDescendantOf(workspace)
		or not Services.CollectionService:HasTag(model, "Item") then
		return
	end
	local itemName = string.lower(
		tostring(model:GetAttribute("ItemName") or "")
	)
	if not perkTrackerState.leviathanEligibleItemNames[itemName] then
		return
	end
	bindGhoulRuleOutItem(model)
	for _, object in ipairs(model:GetDescendants()) do
		if object:GetAttribute("Enabled") ~= nil then
			bindGhoulRuleOutItem(object)
		end
	end
end
local function rebaselineGhoulItemTracker()
	for object in pairs(itemEnabledTracked) do
		if object.Parent ~= nil then
			itemEnabledStates[object] = object:GetAttribute("Enabled")
		end
	end
end
local function ensureGhoulItemTracker()
	if not perkTrackerState.leviathanTagTrackerInitialized then
		perkTrackerState.leviathanTagTrackerInitialized = true
		for _, model in ipairs(
			Services.CollectionService:GetTagged("Item")
		) do
			perkTrackerState.bindLeviathanTaggedItem(model)
		end
		connect(
			Services.CollectionService:GetInstanceAddedSignal("Item"),
			function(model)
				task.defer(function()
					perkTrackerState.bindLeviathanTaggedItem(model)
				end)
			end
		)
		connect(workspace.DescendantAdded, function(object)
			task.defer(function()
				if closed or object.Parent == nil then
					return
				end
				local model =
					perkTrackerState.getTrackedWorldItemModel(object)
				if not model
					or not Services.CollectionService:HasTag(
						model,
						"Item"
					) then
					return
				end
				if object == model then
					perkTrackerState.bindLeviathanTaggedItem(model)
				elseif object:GetAttribute("Enabled") ~= nil then
					bindGhoulRuleOutItem(object)
				end
			end)
		end)
	end
	local items = workspace:FindFirstChild("Items")
	if items == trackedItemsFolder then
		return
	end
	if itemsDescendantAddedConnection
		and itemsDescendantAddedConnection.Connected then
		itemsDescendantAddedConnection:Disconnect()
	end
	itemsDescendantAddedConnection = nil
	trackedItemsFolder = items
	perkTrackerState.leviathanToggleEvents = {}
	if not items then
		return
	end
	for _, object in ipairs(items:GetChildren()) do
		bindGhoulRuleOutItem(object)
	end
	for _, object in ipairs(items:GetDescendants()) do
		if object:GetAttribute("Enabled") ~= nil then
			bindGhoulRuleOutItem(object)
		end
	end
	itemsDescendantAddedConnection =
		connect(items.DescendantAdded, function(object)
			task.defer(function()
				if closed
					or trackedItemsFolder ~= items
					or object.Parent == nil then
					return
				end
				if object.Parent == items
					or object:GetAttribute("Enabled") ~= nil then
					bindGhoulRuleOutItem(object)
				end
			end)
		end)
end
local function getCharacterHumanoid()
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end
local function applyForcedWalkSpeed()
	if not perkTrackerState.speedForcerEnabled then
		return
	end

	local humanoid = getCharacterHumanoid()
	if humanoid
		and humanoid.Health > 0
		and humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
end

local function setSpeed(value)
	speed = math.clamp(math.floor((tonumber(value) or 0) + 0.5), 0, 100)

	if presenter and presenter.SetSpeed then
		presenter:SetSpeed(speed)
	else
		speedValue.Text = tostring(speed)
		local ratio = speed / 100
		sliderFill.Size = UDim2.fromScale(ratio, 1)
		sliderKnob.Position = UDim2.fromScale(ratio, 0.5)
	end

	if perkTrackerState.speedForcerEnabled then
		applyForcedWalkSpeed()
	end
end

local function bindSpeedLock(humanoid)
	if not runtimeIsActive() then
		return
	end

	if speedLockConnection and speedLockConnection.Connected then
		speedLockConnection:Disconnect()
	end
	speedLockConnection = nil

	if not humanoid then
		return
	end

	baseWalkSpeed = humanoid.WalkSpeed

	-- Observe game-applied speed changes immediately, but do not overwrite them
	-- here. The optional forcer reapplies the chosen value every 0.25 seconds.
	speedLockConnection = connect(
		humanoid:GetPropertyChangedSignal("WalkSpeed"),
		function()
			if closed or humanoid.Parent == nil then
				return
			end

			local attemptedSpeed = humanoid.WalkSpeed
			if attemptedSpeed ~= speed then
				pcall(observeWalkSpeedChange, humanoid, attemptedSpeed)
			end
		end
	)

	if perkTrackerState.speedForcerEnabled then
		applyForcedWalkSpeed()
	end
end

local function setButtonEnabled(button, enabled)
	if presenter and presenter.SetButtonEnabled then
		presenter:SetButtonEnabled(button, enabled)
		return
	end
	button.BackgroundColor3 = enabled and COLORS.accentDark or COLORS.cardHover
	button.TextColor3 = enabled and Color3.new(1, 1, 1) or COLORS.text
end

perkTrackerState.flashButton = function(button)
	if presenter and presenter.FlashButton then
		presenter:FlashButton(button)
		return
	end
	if not button or not button.Parent then
		return
	end
	local original =
		button:GetAttribute("DefaultText") or button.Text
	button:SetAttribute("DefaultText", original)
	local token =
		(button:GetAttribute("FlashToken") or 0) + 1
	button:SetAttribute("FlashToken", token)
	button.Text = "Fired!"
	task.delay(1, function()
		if button.Parent
			and button:GetAttribute("FlashToken") == token then
			button.Text =
				button:GetAttribute("DefaultText") or original
		end
	end)
end
local function setEvidence(name, found)
	if found then
		evidenceFound[name] = true
	end
end
resetEvidenceState = function()
	ghoulRuledOut = false
	rebaselineGhoulItemTracker()
	for evidenceName in pairs(evidenceFound) do
		evidenceFound[evidenceName] = false
	end
	freezingEvidenceFound = false
	highestEMF = 1
	spiritBoxTentative = false
	perkTrackerState.orbObserved = false
	perkTrackerState.lidarVisibleObserved = false
	perkTrackerState.dullahanHuntSampleCount = 0
	perkTrackerState.dullahanLosSampleCount = 0
	perkTrackerState.dullahanLosBaseline = nil
	perkTrackerState.dullahanMaxLosSpeed = nil
	perkTrackerState.dullahanCompletedNoIncreaseHunt = false
	perkTrackerState.dybbukMaybeReady = false
	perkTrackerState.leviathanToggleEvents = {}
	perkTrackerState.leviathanLightStates = setmetatable({}, {__mode = "k"})
	perkTrackerState.leviathanLastFlickerAt = -math.huge
	perkTrackerState.leviathanLastLightOffAt = -math.huge
	perkTrackerState.leviathanLightScanAccumulator = 0
	perkTrackerState.suppressItemDisableUntil = 0
	perkTrackerState.suppressLeviathanLightsUntil = 0
	perkTrackerState.saltPendingTouches = setmetatable({}, {__mode = "k"})
	perkTrackerState.saltOverlapAccumulator = 0
	perkTrackerState.wraithRuledOut = false
	perkTrackerState.holyOilPendingContacts =
		setmetatable({}, {__mode = "k"})
	perkTrackerState.holyOilOverlapAccumulator = 0
	perkTrackerState.holyOilFireObserved = false
	perkTrackerState.ruledOutGhosts = {}
	perkTrackerState.currentGhostGuess = nil
	perkTrackerState.currentGhostGuessScore = 0
	perkTrackerState.currentGhostGuessCertain = false
	perkTrackerState.objectTeleportObjects =
		setmetatable({}, {__mode = "k"})
	perkTrackerState.pendingObjectTeleports = {}
	perkTrackerState.recentSmokeEffects = {}
	perkTrackerState.objectTeleportAccumulator = 0
	lastDeepEvidenceScan = -math.huge
	if presenter and presenter.ResetEvidence then
		presenter:ResetEvidence()
	else
		local names = {
			Print = COPY.Evidence.Print,
			SpiritBox = COPY.Evidence.SpiritBox,
			Orb = COPY.Evidence.Orb,
			Inscription = COPY.Evidence.Inscription,
			Laser = COPY.Evidence.Laser,
			Wither = COPY.Evidence.Wither,
		}
		for key, displayName in pairs(names) do
			setEvidenceLabel(key, displayName .. ": Unknown", COLORS.muted)
		end
		setEvidenceLabel("EMF", "EMF-1", COLORS.muted)
		setEvidenceLabel("Temperature", "--.-°C", COLORS.text)
		setEvidenceLabel("FavouriteRoom", "Favourite Room: ...")
		setEvidenceLabel("Ghost", "Ghost: Unknown (Idk)", COLORS.muted)
	end
end
local function getGhostModel()
	local ghost = workspace:FindFirstChild("Ghost")
	if ghost and ghost:IsA("Model") then
		return ghost
	end
	return nil
end
local function getGhostPart(ghost)
	if not ghost then
		return nil
	end
	return ghost.PrimaryPart or ghost:FindFirstChildWhichIsA("BasePart", true)
end
local function destroyGhostEsp()
	if ghostProxyAddedConnection then
		ghostProxyAddedConnection:Disconnect()
		ghostProxyAddedConnection = nil
	end
	if ghostProxyRemovingConnection then
		ghostProxyRemovingConnection:Disconnect()
		ghostProxyRemovingConnection = nil
	end
	for _, object in ipairs({ghostBillboard, ghostDirectHighlight, ghostHighlight, ghostProxyModel}) do
		if object then
			object:Destroy()
		end
	end
	ghostBillboard = nil
	ghostDirectHighlight = nil
	ghostHighlight = nil
	ghostProxyModel = nil
	ghostProxyParts = {}
	ghostEspTarget = nil
	ghostProxyDirty = false
end
local function configureGhostProxyPart(proxyPart)
	proxyPart.Anchored = true
	proxyPart.CanCollide = false
	proxyPart.CanTouch = false
	proxyPart.CanQuery = false
	proxyPart.CastShadow = false
	proxyPart.Massless = true
	proxyPart.Locked = true
	proxyPart.Transparency = 0.99
	proxyPart.LocalTransparencyModifier = 0
	proxyPart.Reflectance = 0
	proxyPart.AssemblyLinearVelocity = Vector3.zero
	proxyPart.AssemblyAngularVelocity = Vector3.zero
end
local function cloneGhostPartForProxy(sourcePart)
	local originalArchivable = sourcePart.Archivable
	sourcePart.Archivable = true
	local cloneSucceeded, proxyPart = pcall(function()
		return sourcePart:Clone()
	end)
	sourcePart.Archivable = originalArchivable
	if not cloneSucceeded or not proxyPart or not proxyPart:IsA("BasePart") then
		proxyPart = Instance.new("Part")
		if sourcePart:IsA("Part") then
			proxyPart.Shape = sourcePart.Shape
		end
	end
	for _, descendant in ipairs(proxyPart:GetDescendants()) do
		if not descendant:IsA("DataModelMesh") then
			descendant:Destroy()
		end
	end
	proxyPart.Name = sourcePart.Name
	proxyPart.Color = COLORS.red
	proxyPart.Size = sourcePart.Size
	proxyPart.CFrame = sourcePart.CFrame
	configureGhostProxyPart(proxyPart)
	return proxyPart
end
local function updateGhostProxy(ghost)
	if not ghost or ghost ~= ghostEspTarget or not ghostProxyModel then
		return false
	end
	local transparency = ghost:GetAttribute("Transparency")
	local proxyNeeded = transparency == true
		or (typeof(transparency) == "number" and transparency >= 0.5)
	if transparency == nil then
		proxyNeeded = true
		for sourcePart in pairs(ghostProxyParts) do
			if sourcePart:IsDescendantOf(ghost) and sourcePart.Transparency < 0.95 then
				proxyNeeded = false
				break
			end
		end
	end
	local visualParent = workspace.CurrentCamera or workspace
	ghostProxyModel.Parent = proxyNeeded and visualParent or nil
	if ghostHighlight then
		ghostHighlight.Enabled = proxyNeeded and ghostEspEnabled
	end
	for sourcePart, proxyPart in pairs(ghostProxyParts) do
		if not sourcePart:IsDescendantOf(ghost) or not proxyPart.Parent then
			ghostProxyDirty = true
			return false
		end
		if proxyPart.Size ~= sourcePart.Size then
			proxyPart.Size = sourcePart.Size
		end
		proxyPart.CFrame = sourcePart.CFrame
		if not proxyPart.Anchored
			or proxyPart.CanCollide
			or proxyPart.CanTouch
			or proxyPart.CanQuery
			or proxyPart.CastShadow
			or proxyPart.Transparency ~= 0.99 then
			configureGhostProxyPart(proxyPart)
		end
	end
	return true
end
local function ghostProxyNeedsRebuild(ghost)
	return ghostProxyDirty or not ghostProxyModel or ghost ~= ghostEspTarget
end
local function createGhostEsp()
	destroyGhostEsp()
	local ghost = getGhostModel()
	local ghostPart = getGhostPart(ghost)
	if not ghost or not ghostPart then
		return false
	end
	ghostEspTarget = ghost
	ghostBillboard = new("BillboardGui", {
		Name = "UntitledGhostBillboard",
		Parent = gui.Parent,
		Adornee = ghostPart,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(90, 30),
		StudsOffset = Vector3.new(0, 3.2, 0),
		Enabled = true,
	})
	new("TextLabel", {
		Parent = ghostBillboard,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "GHOST",
		TextColor3 = COLORS.red,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.15,
		TextScaled = true,
	})
	ghostDirectHighlight = new("Highlight", {
		Name = "UntitledGhostDirectHighlight",
		Parent = ghost,
		Adornee = ghost,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		FillColor = COLORS.red,
		FillTransparency = 0.78,
		OutlineColor = Color3.new(1, 1, 1),
		OutlineTransparency = 0,
		Enabled = true,
	})
	ghostProxyModel = new("Model", {
		Name = "UntitledGhostHighlightProxy",
		Parent = nil,
		Archivable = false,
	})
	ghostProxyModel:SetAttribute("VisualOnlyProxy", true)
	local proxyHumanoid = new("Humanoid", {
		Name = "HighlightProxyHumanoid",
		Parent = ghostProxyModel,
		DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None,
		HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff,
		NameDisplayDistance = 0,
		HealthDisplayDistance = 0,
		AutoRotate = false,
		BreakJointsOnDeath = false,
		RequiresNeck = false,
		PlatformStand = true,
		WalkSpeed = 0,
		JumpPower = 0,
		MaxHealth = 1,
		Health = 1,
	})
	for _, state in ipairs({
		Enum.HumanoidStateType.Jumping,
		Enum.HumanoidStateType.Running,
		Enum.HumanoidStateType.RunningNoPhysics,
		Enum.HumanoidStateType.Climbing,
		Enum.HumanoidStateType.Swimming,
		Enum.HumanoidStateType.Freefall,
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.GettingUp,
		Enum.HumanoidStateType.Seated,
		Enum.HumanoidStateType.Physics,
	}) do
		pcall(function()
			proxyHumanoid:SetStateEnabled(state, false)
		end)
	end
	for _, descendant in ipairs(ghost:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local proxyPart = cloneGhostPartForProxy(descendant)
			proxyPart.Parent = ghostProxyModel
			ghostProxyParts[descendant] = proxyPart
		end
	end
	ghostProxyDirty = false
	ghostProxyAddedConnection = ghost.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			ghostProxyDirty = true
		end
	end)
	ghostProxyRemovingConnection = ghost.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			ghostProxyDirty = true
		end
	end)
	if not next(ghostProxyParts) then
		destroyGhostEsp()
		return false
	end
	ghostHighlight = new("Highlight", {
		Name = "UntitledGhostHighlight",
		Parent = ghostProxyModel,
		Adornee = ghostProxyModel,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		FillColor = COLORS.red,
		FillTransparency = 0.72,
		OutlineColor = Color3.new(1, 1, 1),
		OutlineTransparency = 0,
		Enabled = true,
	})
	updateGhostProxy(ghost)
	return true
end
local function clearItemEsp()
	if perkTrackerState.itemEspChildConnection
		and perkTrackerState.itemEspChildConnection.Connected then
		perkTrackerState.itemEspChildConnection:Disconnect()
	end
	perkTrackerState.itemEspChildConnection = nil
	for index = #generatedObjects, 1, -1 do
		local object = generatedObjects[index]
		if object then
			object:Destroy()
		end
		generatedObjects[index] = nil
	end
end
local function createItemEsp()
	clearItemEsp()
	local items = workspace:FindFirstChild("Items")
	if not items then
		return
	end
	local function addItem(object)
		if closed
			or not itemEspEnabled
			or object.Parent ~= items then
			return
		end
		local itemName = object:GetAttribute("ItemName")
		if typeof(itemName) ~= "string" or itemName == "" then
			itemName = object.Name
		end
		local adornPart
		if object:IsA("BasePart") then
			adornPart = object
		else
			adornPart =
				object:FindFirstChildWhichIsA("BasePart", true)
		end
		if not adornPart then
			return
		end
		local billboard = new("BillboardGui", {
			Name = "UntitledItemBillboard",
			Parent = gui.Parent,
			Adornee = adornPart,
			AlwaysOnTop = true,
			LightInfluence = 0,
			Size = UDim2.fromOffset(150, 28),
			StudsOffset = Vector3.new(0, 1.6, 0),
			Enabled = true,
		})
		new("TextLabel", {
			Parent = billboard,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = tostring(itemName),
			TextColor3 = COLORS.text,
			TextStrokeColor3 = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.2,
			TextScaled = true,
		})
		local adornee =
			(object:IsA("Model") or object:IsA("BasePart"))
			and object
			or adornPart
		local highlight = new("Highlight", {
			Name = "UntitledItemHighlight",
			Parent = object,
			Adornee = adornee,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			FillTransparency = 1,
			OutlineColor = Color3.fromRGB(255, 181, 74),
			OutlineTransparency = 0,
			Enabled = true,
		})
		table.insert(generatedObjects, billboard)
		table.insert(generatedObjects, highlight)
		connect(object.AncestryChanged, function()
			if object.Parent ~= items then
				if billboard.Parent then
					billboard:Destroy()
				end
				if highlight.Parent then
					highlight:Destroy()
				end
			end
		end)
	end
	for _, object in ipairs(items:GetChildren()) do
		addItem(object)
	end
	perkTrackerState.itemEspChildConnection =
		connect(items.ChildAdded, function(object)
			task.defer(function()
				addItem(object)
			end)
		end)
end
local function setFullBright(enabled)
	fullBrightEnabled = enabled
	setButtonEnabled(fullBrightButton, enabled)
	if enabled then
		Services.Lighting.Ambient = Color3.new(1, 1, 1)
		Services.Lighting.OutdoorAmbient = Color3.new(1, 1, 1)
		Services.Lighting.Brightness = 3
		Services.Lighting.GlobalShadows = false
		Services.Lighting.FogEnd = 100000
	else
		Services.Lighting.Ambient = oldLighting.Ambient
		Services.Lighting.OutdoorAmbient = oldLighting.OutdoorAmbient
		Services.Lighting.Brightness = oldLighting.Brightness
		Services.Lighting.GlobalShadows = oldLighting.GlobalShadows
		Services.Lighting.FogEnd = oldLighting.FogEnd
	end
end
local function findRoomsFolder()
	local map = workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Rooms") or nil
end
local function findFavouriteRoom(roomsFolder, roomName)
	if not roomsFolder or not roomName then
		return nil
	end
	local direct = roomsFolder:FindFirstChild(tostring(roomName))
	if direct then
		return direct
	end
	local target = string.lower(tostring(roomName))
	for _, room in ipairs(roomsFolder:GetChildren()) do
		if string.lower(room.Name) == target then
			return room
		end
	end
	return nil
end
local function destroyFavouriteRoomEsp()
	if favouriteRoomBillboard then
		favouriteRoomBillboard:Destroy()
	end
	favouriteRoomBillboard = nil
	favouriteRoomBillboardLabel = nil
	favouriteRoomBillboardTarget = nil
end
local function getFavouriteRoomEspTarget(room)
	if not room then
		return nil
	end
	local candidates = {}
	local direct = room:FindFirstChild("BoundingBox")
	if direct then
		table.insert(candidates, direct)
	end
	for _, descendant in ipairs(room:GetDescendants()) do
		if descendant.Name == "BoundingBox" and descendant ~= direct then
			table.insert(candidates, descendant)
		end
	end
	for _, boundingBox in ipairs(candidates) do
		if boundingBox:IsA("BasePart") then
			return boundingBox
		end
		for _, child in ipairs(boundingBox:GetChildren()) do
			if child:IsA("BasePart") and child.Name == "Part" then
				return child
			end
		end
		for _, child in ipairs(boundingBox:GetChildren()) do
			if child:IsA("BasePart") then
				return child
			end
		end
		local nestedPart = boundingBox:FindFirstChildWhichIsA("BasePart", true)
		if nestedPart then
			return nestedPart
		end
	end
	return nil
end
local function updateFavouriteRoomEsp(room)
	if not room then
		destroyFavouriteRoomEsp()
		return
	end
	local targetPart = getFavouriteRoomEspTarget(room)
	if not targetPart then
		destroyFavouriteRoomEsp()
		return
	end
	if favouriteRoomBillboard
		and favouriteRoomBillboardTarget == targetPart
		and favouriteRoomBillboard.Adornee == targetPart then
		if favouriteRoomBillboardLabel then
			favouriteRoomBillboardLabel.Text = room.Name
		end
		return
	end
	destroyFavouriteRoomEsp()
	favouriteRoomBillboardTarget = targetPart
	favouriteRoomBillboard = new("BillboardGui", {
		Name = "UntitledFavouriteRoomBillboard",
		Parent = gui.Parent,
		Adornee = targetPart,
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(170, 28),
		Enabled = true,
		StudsOffset = Vector3.new(0, 0, 0),
	})
	favouriteRoomBillboardLabel = new("TextLabel", {
		Parent = favouriteRoomBillboard,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = room.Name,
		TextColor3 = COLORS.accent,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.2,
		TextScaled = true,
	})
end
local function appendRollingSample(samples, sample, now, maxAge)
	table.insert(samples, sample)
	while samples[1] and now - samples[1].Time > maxAge do
		table.remove(samples, 1)
	end
end
local function _pruneTimes(times, now, maxAge)
	while times[1] and now - times[1] > maxAge do
		table.remove(times, 1)
	end
end
local function valuesFromSamples(samples, field, predicate)
	local values = {}
	for _, sample in ipairs(samples) do
		if (not predicate or predicate(sample)) and typeof(sample[field]) == "number" then
			table.insert(values, sample[field])
		end
	end
	return values
end
local function median(values)
	if #values == 0 then
		return nil
	end
	local copy = {}
	for index, value in ipairs(values) do
		copy[index] = value
	end
	table.sort(copy)
	local middle = math.floor((#copy + 1) / 2)
	if #copy % 2 == 1 then
		return copy[middle]
	end
	return (copy[middle] + copy[middle + 1]) / 2
end
local function _valueRange(values)
	if #values == 0 then
		return 0
	end
	local minimum = values[1]
	local maximum = values[1]
	for index = 2, #values do
		minimum = math.min(minimum, values[index])
		maximum = math.max(maximum, values[index])
	end
	return maximum - minimum
end
local function standardDeviation(values)
	if #values < 2 then
		return math.huge
	end
	local total = 0
	for _, value in ipairs(values) do
		total = total + value
	end
	local mean = total / #values
	local variance = 0
	for _, value in ipairs(values) do
		variance = variance + (value - mean) ^ 2
	end
	return math.sqrt(variance / #values)
end
local function _linearSlope(samples, field)
	if #samples < 2 then
		return 0
	end
	local origin = samples[1].Time
	local sumX = 0
	local sumY = 0
	local sumXX = 0
	local sumXY = 0
	local count = 0
	for _, sample in ipairs(samples) do
		local value = sample[field]
		if typeof(value) == "number" then
			local x = sample.Time - origin
			sumX = sumX + x
			sumY = sumY + value
			sumXX = sumXX + x * x
			sumXY = sumXY + x * value
			count = count + 1
		end
	end
	local denominator = count * sumXX - sumX * sumX
	if count < 2 or math.abs(denominator) < 0.0001 then
		return 0
	end
	return (count * sumXY - sumX * sumY) / denominator
end
local function _pearsonCorrelation(samples, xField, yField)
	local count = 0
	local sumX = 0
	local sumY = 0
	local sumXX = 0
	local sumYY = 0
	local sumXY = 0
	for _, sample in ipairs(samples) do
		local x = sample[xField]
		local y = sample[yField]
		if typeof(x) == "number" and typeof(y) == "number" then
			count = count + 1
			sumX = sumX + x
			sumY = sumY + y
			sumXX = sumXX + x * x
			sumYY = sumYY + y * y
			sumXY = sumXY + x * y
		end
	end
	if count < 3 then
		return 0
	end
	local numerator = count * sumXY - sumX * sumY
	local denominatorX = count * sumXX - sumX * sumX
	local denominatorY = count * sumYY - sumY * sumY
	local denominator = math.sqrt(math.max(0, denominatorX * denominatorY))
	if denominator < 0.0001 then
		return 0
	end
	return numerator / denominator
end
local function resetPerkTrackerForGhost(ghost)
	local previousGhost = perkTrackerState.ghost
	if previousGhost and ghost ~= previousGhost then
		resetEvidenceState()
		evidenceRoundGhost = ghost
	end
	clearAllPerkDetections()
	perkTrackerState.ghost = ghost
	perkTrackerState.visualModelChecked = false
	perkTrackerState.sampleAccumulator = 0
	perkTrackerState.slowScanAccumulator = 0
	perkTrackerState.analysisAccumulator = 0
	perkTrackerState.lastPosition = nil
	perkTrackerState.lastSampleTime = nil
	perkTrackerState.lastHunting = ghost and ghost:GetAttribute("Hunting") == true or nil
	perkTrackerState.motionSamples = {}
	perkTrackerState.losSamples = {}
	perkTrackerState.energySamples = {}
	if perkTrackerState.transparencyAttributeConnection then
		perkTrackerState.transparencyAttributeConnection:Disconnect()
		perkTrackerState.transparencyAttributeConnection = nil
	end
	perkTrackerState.transparencyTransitions = {}
	perkTrackerState.transparencyIntervals = {}
	perkTrackerState.lastTransparencyState = nil
	perkTrackerState.lastTransparencyTransitionTime = nil
	perkTrackerState.vexLastValue = nil
	perkTrackerState.wendigoSnapshots = {}
	perkTrackerState.wendigoNextSnapshotAt = 0
	perkTrackerState.nonHuntWalkSpeedSamples = {}
	perkTrackerState.specterInitialized = false
	perkTrackerState.specterInFavourite = false
	perkTrackerState.specterEntryAt = nil
	perkTrackerState.specterSawMovement = false
	perkTrackerState.specterStationaryCandidateAt = nil
	perkTrackerState.specterIdleSince = nil
	perkTrackerState.specterStationaryArmed = false
	perkTrackerState.specterSuccessCount = 0
	perkTrackerState.specterTrackedFavouriteName = nil
	perkTrackerState.specterRoomChangePause = false
	perkTrackerState.specterRoomChangeSettleSince = nil
	if ghost then
		local initialTransparency = ghost:GetAttribute("Transparency")
		if typeof(initialTransparency) == "boolean" then
			perkTrackerState.lastTransparencyState = initialTransparency
		elseif typeof(initialTransparency) == "number" then
			perkTrackerState.lastTransparencyState = initialTransparency >= 0.5
		end
		perkTrackerState.transparencyAttributeConnection = connect(
			ghost:GetAttributeChangedSignal("Transparency"),
			function()
				if closed or perkTrackerState.ghost ~= ghost then
					return
				end
				local value = ghost:GetAttribute("Transparency")
				local invisible
				if typeof(value) == "boolean" then
					invisible = value
				elseif typeof(value) == "number" then
					invisible = value >= 0.5
				else
					return
				end
				if perkTrackerState.lastTransparencyState == nil then
					perkTrackerState.lastTransparencyState = invisible
					return
				end
				if invisible == perkTrackerState.lastTransparencyState then
					return
				end
				local transitionTime = os.clock()
				local previousTime = perkTrackerState.lastTransparencyTransitionTime
				if previousTime and transitionTime - previousTime > 0.03 then
					table.insert(perkTrackerState.transparencyIntervals, {
						Time = transitionTime,
						Interval = transitionTime - previousTime,
					})
				end
				table.insert(perkTrackerState.transparencyTransitions, transitionTime)
				perkTrackerState.lastTransparencyTransitionTime = transitionTime
				perkTrackerState.lastTransparencyState = invisible
			end
		)
		task.defer(function()
			if not closed and perkTrackerState.ghost == ghost then
				perkTrackerState.updateVexState(ghost)
			end
		end)
	end
	perkTrackerState.previousDead = {}
	perkTrackerState.pendingKill = nil
	perkTrackerState.keresKillDecreaseCount = 0
	perkTrackerState.aswangKillIncreaseCount = 0
	perkTrackerState.killSpeedProcessedPlayers = setmetatable({}, {__mode = "k"})
	perkTrackerState.huntStartedAt = nil
	perkTrackerState.pendingWispStart = nil
	perkTrackerState.wispHuntResults = {}
	perkTrackerState.wispFavouriteHuntCount = 0
	perkTrackerState.umbraSamples = {}
	perkTrackerState.umbraLastLightStateByRoom = {}
	perkTrackerState.umbraLightTransitionsByRoom = {}
	perkTrackerState.umbraRootSoundAbsentTime = 0
	perkTrackerState.umbraRootSoundPresentTime = 0
	perkTrackerState.umbraLitMatch = nil
	perkTrackerState.brokenGlassInitialized = false
	perkTrackerState.brokenGlassSeen = {}
	perkTrackerState.brokenGlassEvents = {}
	perkTrackerState.sirenSlowEvents = {}
	perkTrackerState.sirenLosExposure = 0
	perkTrackerState.sirenSlowObservedThisHunt = false
	perkTrackerState.lastLosLightingKey = nil
	perkTrackerState.lastLosTarget = nil
	perkTrackerState.dullahanBaselineSpeed = nil
	perkTrackerState.dullahanLastSpeed = nil
	perkTrackerState.dullahanIncreaseEvents = {}
	perkTrackerState.dullahanSawLineOfSight = false
	perkTrackerState.dullahanHuntSampleCount = 0
	perkTrackerState.dullahanLosSampleCount = 0
	perkTrackerState.dullahanLosBaseline = nil
	perkTrackerState.dullahanMaxLosSpeed = nil
	perkTrackerState.dullahanCompletedNoIncreaseHunt = false
	perkTrackerState.dybbukMaybeReady = false
	perkTrackerState.leviathanToggleEvents = {}
	perkTrackerState.leviathanLightStates = setmetatable({}, {__mode = "k"})
	perkTrackerState.leviathanLastFlickerAt = -math.huge
	perkTrackerState.leviathanLastLightOffAt = -math.huge
	perkTrackerState.leviathanLightScanAccumulator = 0
	perkTrackerState.suppressLeviathanLightsUntil = 0
	perkTrackerState.ravagerTrackedObjects =
		setmetatable({}, {__mode = "k"})
	perkTrackerState.ravagerMotionEvents = {}
	perkTrackerState.ravagerScanAccumulator = 0
	perkTrackerState.saltPendingTouches = setmetatable({}, {__mode = "k"})
	perkTrackerState.saltOverlapAccumulator = 0
	perkTrackerState.wraithRuledOut = false
	perkTrackerState.holyOilPendingContacts =
		setmetatable({}, {__mode = "k"})
	perkTrackerState.holyOilOverlapAccumulator = 0
	perkTrackerState.holyOilFireObserved = false
	perkTrackerState.holyOilBurnStartedAt =
		setmetatable({}, {__mode = "k"})
	perkTrackerState.holyOilColorStates =
		setmetatable({}, {__mode = "k"})
	perkTrackerState.orbObserved = false
	perkTrackerState.lidarVisibleObserved = false
	perkTrackerState.entitySmokeObserved = false
	perkTrackerState.entitySmokeHolders = setmetatable({}, {__mode = "k"})
	perkTrackerState.lastSmokeAddedAt = -math.huge
	perkTrackerState.objectTeleportObjects = setmetatable({}, {__mode = "k"})
	perkTrackerState.objectTeleportAccumulator = 0
	perkTrackerState.pendingObjectTeleports = {}
	perkTrackerState.recentSmokeEffects = {}
	perkTrackerState.teleportTrackingStartedAt = os.clock()
	perkTrackerState.lastObservedRoom = ghost and ghost:GetAttribute("CurrentRoom") or nil
	perkTrackerState.pendingGhostTeleport = nil
	perkTrackerState.lastGhostTeleportAt = nil
	perkTrackerState.teleportResolvedGhost = nil
	perkTrackerState.activeCrossBurns = setmetatable({}, {__mode = "k"})
	perkTrackerState.demonRuledOut = false
	perkTrackerState.demonMotionObserved = false
	perkTrackerState.ruledOutGhosts = {}

	if ghost then
		task.delay(0.3, function()
			if closed
				or perkTrackerState.ghost ~= ghost
				or perkTrackerState.visualModelChecked then
				return
			end

			perkTrackerState.visualModelChecked = true
			local visualModel =
				tostring(ghost:GetAttribute("VisualModel") or "")
			local femaleModel =
				visualModel == "Abaddon"
				or visualModel == "Leech"
				or visualModel == "Rattle"
				or visualModel == "Watcher"

			if femaleModel then
				recordPerkDetection(
					"Keres",
					"VisualModel "
						.. visualModel
						.. " is one of the female Keres/Siren ghost models",
					35
				)
				recordPerkDetection(
					"Siren",
					"VisualModel "
						.. visualModel
						.. " is one of the female Keres/Siren ghost models",
					35
				)

				for _, ghostName in ipairs({"Keres", "Siren"}) do
					local detection = perkDetections[ghostName]
					if detection and detection.Confidence == 35 then
						detection.Persistent = true
						detection.ExpiresAt = nil
					end
				end

				updateGhostIdentification(ghost)
			end
		end)
	end
end
local function getGhostTransparencyState(ghost)
	local transparency = ghost and ghost:GetAttribute("Transparency") or nil
	if typeof(transparency) == "boolean" then
		return transparency
	end
	if typeof(transparency) == "number" then
		return transparency >= 0.5
	end
	return nil
end
local function getPlayerEnergy(targetPlayer)
	if not targetPlayer then
		return nil
	end
	for _, attributeName in ipairs({"Energy", "Sanity"}) do
		local value = targetPlayer:GetAttribute(attributeName)
		if typeof(value) == "number" then
			return math.clamp(value, 0, 100)
		end
	end
	local replicated = targetPlayer:FindFirstChild("Replicated")
	for _, container in ipairs({targetPlayer, replicated}) do
		if container then
			for _, valueName in ipairs({"Energy", "Sanity"}) do
				local valueObject = container:FindFirstChild(valueName)
				if valueObject
					and (
						valueObject:IsA("NumberValue")
						or valueObject:IsA("IntValue")
					) then
					return math.clamp(valueObject.Value, 0, 100)
				end
			end
		end
	end
	return nil
end
local function getAverageTeamEnergy()
	local total = 0
	local count = 0
	for _, targetPlayer in ipairs(Services.Players:GetPlayers()) do
		if targetPlayer:GetAttribute("Dead") ~= true then
			local value = getPlayerEnergy(targetPlayer)
			if typeof(value) == "number" then
				total = total + value
				count = count + 1
			end
		end
	end
	if count == 0 then
		for _, targetPlayer in ipairs(Services.Players:GetPlayers()) do
			local value = getPlayerEnergy(targetPlayer)
			if typeof(value) == "number" then
				total = total + value
				count = count + 1
			end
		end
	end
	return count > 0 and total / count or nil
end
local losRaycastParams = RaycastParams.new()
losRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
losRaycastParams.IgnoreWater = true
local losFilterGhost
local function ghostHasLineOfSightToCharacter(ghost, character)
	local ghostPart = getGhostPart(ghost)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not ghostPart or not root then
		return false
	end
	local direction = root.Position - ghostPart.Position
	if direction.Magnitude > 120 then
		return false
	end
	if losFilterGhost ~= ghost then
		losFilterGhost = ghost
		losRaycastParams.FilterDescendantsInstances = {ghost}
	end
	local result = workspace:Raycast(ghostPart.Position, direction, losRaycastParams)
	return result == nil or result.Instance:IsDescendantOf(character)
end
local function ghostHasLineOfSightToAnyAlivePlayer(ghost)
	for _, targetPlayer in ipairs(Services.Players:GetPlayers()) do
		if targetPlayer:GetAttribute("Dead") ~= true
			and ghostHasLineOfSightToCharacter(ghost, targetPlayer.Character) then
			return true, targetPlayer.Name
		end
	end
	return false, nil
end
local function pointIsInsidePart(part, position)
	local localPosition = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end
local function getInstanceWorldPosition(instance)
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end
local roomBoundingPartsCache = setmetatable({}, {__mode = "k"})
local function getRoomBoundingParts(room)
	if not room then
		return {}
	end
	local cached = roomBoundingPartsCache[room]
	if cached and #cached > 0 then
		local valid = true
		for _, part in ipairs(cached) do
			if not part.Parent or not part:IsDescendantOf(room) then
				valid = false
				break
			end
		end
		if valid then
			return cached
		end
	end
	local parts = {}
	local seen = setmetatable({}, {__mode = "k"})
	local boundingBoxes = {}
	local direct = room:FindFirstChild("BoundingBox")
	if direct then
		table.insert(boundingBoxes, direct)
	end
	for _, descendant in ipairs(room:GetDescendants()) do
		if descendant.Name == "BoundingBox" and descendant ~= direct then
			table.insert(boundingBoxes, descendant)
		end
	end
	local function addPart(part)
		if part and part:IsA("BasePart") and not seen[part] then
			seen[part] = true
			table.insert(parts, part)
		end
	end
	for _, boundingBox in ipairs(boundingBoxes) do
		if boundingBox:IsA("BasePart") then
			addPart(boundingBox)
		else
			for _, child in ipairs(boundingBox:GetChildren()) do
				if child:IsA("BasePart") and child.Name == "Part" then
					addPart(child)
				end
			end
			if #parts == 0 then
				for _, child in ipairs(boundingBox:GetChildren()) do
					if child:IsA("BasePart") then
						addPart(child)
					end
				end
			end
			if #parts == 0 then
				for _, descendant in ipairs(boundingBox:GetDescendants()) do
					if descendant:IsA("BasePart") then
						addPart(descendant)
					end
				end
			end
		end
	end
	if #parts > 0 then
		roomBoundingPartsCache[room] = parts
	else
		roomBoundingPartsCache[room] = nil
	end
	return parts
end
local function instanceIsInsideRoom(instance, room)
	local position = getInstanceWorldPosition(instance)
	if not position then
		return false
	end
	for _, part in ipairs(getRoomBoundingParts(room)) do
		if pointIsInsidePart(part, position) then
			return true
		end
	end
	return false
end
local function _findRoomContainingInstance(instance)
	local roomsFolder = findRoomsFolder()
	if not roomsFolder or not instance then
		return nil
	end
	for _, room in ipairs(roomsFolder:GetChildren()) do
		if instanceIsInsideRoom(instance, room) then
			return room
		end
	end
	return nil
end
local function getGhostRoomLightingState(ghost)
	local roomName = ghost and ghost:GetAttribute("CurrentRoom") or nil
	local roomsFolder = findRoomsFolder()
	local room = findFavouriteRoom(roomsFolder, roomName)
	if not room then
		return nil, nil
	end
	if room:GetAttribute("LightsBroken") == true then
		return false, room.Name
	end
	local lightsOn = room:GetAttribute("LightsOn")
	if lightsOn == true then
		return true, room.Name
	end
	if lightsOn == false then
		return false, room.Name
	end
	return nil, room.Name
end
local function sameRoomName(first, second)
	if first == nil or second == nil then
		return false
	end
	return string.lower(tostring(first)) == string.lower(tostring(second))
end
local function lightingContextKey(roomName, lit)
	if roomName == nil or lit == nil then
		return nil
	end
	return string.lower(tostring(roomName)) .. "|" .. (lit and "lit" or "dark")
end
local function lightingDescription(roomName, lit)
	return (lit and "lit " or "dark ") .. tostring(roomName or "room")
end
local function getMapSizeSpeedFactor()
	local map = workspace:FindFirstChild("Map")
	local mapSize = map and map:GetAttribute("MapSize") or nil
	local normalized = string.lower(tostring(mapSize or "Small"))
	if normalized == "large" then
		return 1.1
	elseif normalized == "medium" then
		return 1.05
	end
	return 1
end
local function _nearestAllowedGhostSpeedMultiplier(observedScale)
	if typeof(observedScale) ~= "number" or observedScale <= 0 then
		return nil, math.huge
	end
	local bestMultiplier = nil
	local bestError = math.huge
	for step = 0, 6 do
		local multiplier = 0.5 + step * 0.165
		local errorAmount = math.abs(observedScale - multiplier)
		if errorAmount < bestError then
			bestError = errorAmount
			bestMultiplier = multiplier
		end
	end
	return bestMultiplier, bestError
end
local function closestConfiguredBaseSpeed(rawWalkSpeed, baseSpeed)
	if typeof(rawWalkSpeed) ~= "number" or rawWalkSpeed <= 0 then
		return nil, math.huge, nil
	end
	local mapFactor = getMapSizeSpeedFactor()
	local bestExpected = nil
	local bestError = math.huge
	local bestMultiplier = nil
	for step = 0, 6 do
		local multiplier = 0.5 + step * 0.25
		local expected = baseSpeed * mapFactor * multiplier
		local errorAmount = math.abs(rawWalkSpeed - expected)
		if errorAmount < bestError then
			bestError = errorAmount
			bestExpected = expected
			bestMultiplier = multiplier
		end
	end
	return bestExpected, bestError, bestMultiplier
end
local function recentNonHuntWalkSpeed(now)
	local values = valuesFromSamples(
		perkTrackerState.nonHuntWalkSpeedSamples,
		"GhostWalkSpeed",
		function(sample)
			return sample.Time >= now - 20
		end
	)
	return median(values), #values
end
local function _samplesByLightingContext(samples, predicate)
	local groups = {}
	for _, sample in ipairs(samples) do
		if sample.LightingKey and (not predicate or predicate(sample)) then
			local group = groups[sample.LightingKey]
			if not group then
				group = {
					Room = sample.Room,
					Lit = sample.Lit,
					Samples = {},
				}
				groups[sample.LightingKey] = group
			end
			table.insert(group.Samples, sample)
		end
	end
	return groups
end
local function readReplicatedGhostValue(ghost, valueName)
	if not ghost then
		return nil
	end
	local direct = ghost:GetAttribute(valueName)
	if direct ~= nil then
		return direct
	end
	for _, descendant in ipairs(ghost:GetDescendants()) do
		local attributeValue = descendant:GetAttribute(valueName)
		if attributeValue ~= nil then
			return attributeValue
		end
		if descendant.Name == valueName and descendant:IsA("ValueBase") then
			return descendant.Value
		end
	end
	return nil
end
local function checkVexMaybe(ghost)
	return readReplicatedGhostValue(ghost, "InvisibleOnLIDAR") == true
end
perkTrackerState.updateVexState = function(ghost)
	if not ghost or perkTrackerState.ghost ~= ghost then
		return
	end
	local value =
		readReplicatedGhostValue(ghost, "InvisibleOnLIDAR")
	local changed = value ~= perkTrackerState.vexLastValue
	perkTrackerState.vexLastValue = value
	if value == true then
		local needsRefresh =
			changed
			or perkTrackerState.isGhostRuledOut("Vex")
			or not perkDetections.Vex
		perkTrackerState.clearGhostRuleOut("Vex")
		perkTrackerState.dybbukMaybeReady = false
		clearPerkDetection("Dybbuk")
		recordPerkDetection(
			"Vex",
			"replicated InvisibleOnLIDAR property was true",
			99
		)
		if needsRefresh then
			updateGhostIdentification(ghost)
		end
	else
		local needsRuleOut =
			changed
			or not perkTrackerState.isGhostRuledOut("Vex")
		clearPerkDetection("Vex")
		if needsRuleOut then
			perkTrackerState.ruleOutGhost(
				"Vex",
				value == false
					and "replicated InvisibleOnLIDAR property was false"
					or "replicated InvisibleOnLIDAR property was not found",
				99
			)
		end
	end
end
local function scanBansheeGlassBurst(now)
	local brokenGlassFolder = workspace:FindFirstChild("BrokenGlass")
	if not brokenGlassFolder then
		return false
	end
	local current = {}
	for _, object in ipairs(brokenGlassFolder:GetDescendants()) do
		if object:IsA("Model") and object.Name == "BrokenGlass" then
			current[object] = true
		end
	end
	if not perkTrackerState.brokenGlassInitialized then
		perkTrackerState.brokenGlassInitialized = true
		perkTrackerState.brokenGlassSeen = current
		return false
	end
	for object in pairs(current) do
		if not perkTrackerState.brokenGlassSeen[object] then
			table.insert(perkTrackerState.brokenGlassEvents, now)
		end
	end
	perkTrackerState.brokenGlassSeen = current
	local cutoff = now - 2.5
	while perkTrackerState.brokenGlassEvents[1]
		and perkTrackerState.brokenGlassEvents[1] < cutoff do
		table.remove(perkTrackerState.brokenGlassEvents, 1)
	end
	return #perkTrackerState.brokenGlassEvents >= 2
end
local function ghostRootHasAnySound(ghost)
	local root = ghost and ghost:FindFirstChild("HumanoidRootPart", true) or nil
	if not root or not root:IsA("BasePart") then
		return nil
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Sound")
			and descendant.Name ~= "Hunting" then
			return true
		end
	end
	return false
end
local function medianSpeedWindow(startTime, endTime, huntingOnly, roomName, lit)
	local requiredLightingKey = lightingContextKey(roomName, lit)
	local values = valuesFromSamples(
		perkTrackerState.motionSamples,
		"GhostWalkSpeed",
		function(sample)
			return sample.Time >= startTime
				and sample.Time <= endTime
				and typeof(sample.GhostWalkSpeed) == "number"
				and sample.GhostWalkSpeed > 0
				and (not huntingOnly or sample.Hunting)
				and (
					not requiredLightingKey
					or sample.LightingKey == requiredLightingKey
				)
		end
	)
	return median(values), #values, standardDeviation(values)
end
local function handleMultiplayerDeaths(ghost, hunting, now)
	local currentPlayers = Services.Players:GetPlayers()
	local multiplayer = #currentPlayers > 1
	for _, targetPlayer in ipairs(currentPlayers) do
		local dead = targetPlayer:GetAttribute("Dead") == true
		local previous = perkTrackerState.previousDead[targetPlayer]
		if previous ~= nil
			and not previous
			and dead
			and hunting
			and multiplayer then
			local uniqueSpeedKill =
				perkTrackerState.killSpeedProcessedPlayers[targetPlayer] ~= true
			perkTrackerState.killSpeedProcessedPlayers[targetPlayer] = true
			local otherAlive = 0
			for _, otherPlayer in ipairs(currentPlayers) do
				if otherPlayer ~= targetPlayer
					and otherPlayer:GetAttribute("Dead") ~= true then
					otherAlive = otherAlive + 1
				end
			end
			local preSpeed, preCount, preDeviation =
				medianSpeedWindow(
					now - 0.9,
					now - 0.05,
					true,
					nil,
					nil
				)
			local stablePre =
				preSpeed ~= nil
				and preDeviation ~= nil
					and preCount >= 3
				and preDeviation
					<= math.max(0.1, math.abs(preSpeed) * 0.012)
			perkTrackerState.pendingKill = {
				Time = now,
				PreSpeed = stablePre and preSpeed or nil,
				Player = targetPlayer,
				UniqueSpeedKill = uniqueSpeedKill,
				OtherAlive = otherAlive,
				HuntAge =
					perkTrackerState.huntStartedAt
					and now - perkTrackerState.huntStartedAt
					or 0,
			}
		end
		perkTrackerState.previousDead[targetPlayer] = dead
	end
end
local function evaluatePendingKill(hunting, now)
	local pending = perkTrackerState.pendingKill
	if not pending then
		return
	end
	local elapsed = now - pending.Time
	local validKill =
		(pending.OtherAlive or 0) > 0
		and (pending.HuntAge or 0) >= 0.5
	if not hunting
		and elapsed <= 1
		and validKill then
		recordPerkDetection(
			"Revenant",
			"hunt stopped immediately after a player died",
			35
		)
		perkTrackerState.pendingKill = nil
		return
	end
	if hunting and elapsed >= 1 and validKill then
		perkTrackerState.ruleOutGhost(
			"Revenant",
			"hunt continued after a player died",
			95
		)
	end
	local preSpeed = pending.PreSpeed
	if hunting
		and elapsed >= 0.65
		and preSpeed
		and validKill
		and pending.UniqueSpeedKill then
		local postSpeed, postCount, postDeviation =
			medianSpeedWindow(
				pending.Time + 0.08,
				now,
				true,
				nil,
				nil
			)
		if postSpeed and postDeviation and postCount >= 3 then
			local confirmedPreSpeed = preSpeed :: number
			local confirmedPostSpeed = postSpeed :: number
			local confirmedDeviation = postDeviation :: number
			local difference = confirmedPostSpeed - confirmedPreSpeed
			local relativeDifference =
				difference / math.max(math.abs(confirmedPreSpeed), 0.01)
			local stable =
				confirmedDeviation
					<= math.max(0.1, math.abs(confirmedPostSpeed) * 0.012)
			if stable and relativeDifference <= -0.07 then
				perkTrackerState.keresKillDecreaseCount =
					perkTrackerState.keresKillDecreaseCount + 1
				perkTrackerState.clearGhostRuleOut("Keres")
				recordPerkDetection(
					"Keres",
					"Ghost Humanoid WalkSpeed fell by roughly 10% after "
						.. tostring(
							perkTrackerState.keresKillDecreaseCount
						)
						.. " verified player kill"
						.. (
							perkTrackerState.keresKillDecreaseCount == 1
							and ""
							or "s"
						),
					perkTrackerState.keresKillDecreaseCount >= 2
						and 99
						or 97
				)
				perkTrackerState.ruleOutGhost(
					"Aswang",
					"the death-linked speed change was downward rather than upward",
					94
				)
				updateGhostIdentification(perkTrackerState.ghost)
				perkTrackerState.pendingKill = nil
				return
			elseif stable and relativeDifference >= 0.14 then
				perkTrackerState.aswangKillIncreaseCount =
					perkTrackerState.aswangKillIncreaseCount + 1
				perkTrackerState.clearGhostRuleOut("Aswang")
				recordPerkDetection(
					"Aswang",
					"Ghost Humanoid WalkSpeed rose toward the expected 20% after "
						.. tostring(
							perkTrackerState.aswangKillIncreaseCount
						)
						.. " verified player kill"
						.. (
							perkTrackerState.aswangKillIncreaseCount == 1
							and ""
							or "s"
						),
					perkTrackerState.aswangKillIncreaseCount >= 2
						and 99
						or 97
				)
				perkTrackerState.ruleOutGhost(
					"Keres",
					"the death-linked speed change was upward rather than downward",
					94
				)
				updateGhostIdentification(perkTrackerState.ghost)
				perkTrackerState.pendingKill = nil
				return
			elseif stable and elapsed >= 1.25 and relativeDifference > -0.03 then
				perkTrackerState.ruleOutGhost(
					"Keres",
					"a verified player kill produced no persistent WalkSpeed decrease",
					92
				)
				perkTrackerState.pendingKill = nil
				return
			end
		end
	end
	if elapsed > 2.5 then
		perkTrackerState.pendingKill = nil
	end
end
local function handleHuntTransition(ghost, hunting, now)
	local previous = perkTrackerState.lastHunting
	if previous == nil then
		perkTrackerState.lastHunting = hunting
		return
	end
	if hunting and not previous then
		perkTrackerState.evaluateHolyOilAtHuntStart(ghost)
		if perkTrackerState.specterStationaryArmed
			and not perkTrackerState.specterRoomChangePause then
			perkTrackerState.specterSuccessCount =
				perkTrackerState.specterSuccessCount + 1
			local successCount = perkTrackerState.specterSuccessCount
			recordPerkDetection(
				"Specter",
				"ghost remained stationary in its favourite room from the five-second arm point until hunt start ("
					.. tostring(successCount)
					.. " time"
					.. (successCount == 1 and ")" or "s)"),
				successCount >= 2 and 65 or 35
			)
		end
		perkTrackerState.specterStationaryArmed = false
		perkTrackerState.specterStationaryCandidateAt = nil
		perkTrackerState.specterIdleSince = nil
		perkTrackerState.specterRoomChangePause = false
		perkTrackerState.specterRoomChangeSettleSince = nil
		perkTrackerState.huntStartedAt = now
		local dullahanHumanoid = ghost:FindFirstChildOfClass("Humanoid")
		perkTrackerState.dullahanBaselineSpeed = dullahanHumanoid and dullahanHumanoid.WalkSpeed or nil
		perkTrackerState.dullahanLastSpeed = perkTrackerState.dullahanBaselineSpeed
		perkTrackerState.dullahanIncreaseEvents = {}
		perkTrackerState.dullahanSawLineOfSight = false
		perkTrackerState.dullahanHuntSampleCount = 0
		perkTrackerState.dullahanLosSampleCount = 0
		perkTrackerState.dullahanLosBaseline = nil
		perkTrackerState.dullahanMaxLosSpeed = nil
		perkTrackerState.losSamples = {}
		perkTrackerState.energySamples = {}
		perkTrackerState.umbraSamples = {}
		perkTrackerState.umbraLastLightStateByRoom = {}
		perkTrackerState.umbraLightTransitionsByRoom = {}
		perkTrackerState.umbraRootSoundAbsentTime = 0
		perkTrackerState.lastLosLightingKey = nil
		perkTrackerState.sirenSlowEvents = {}
		perkTrackerState.sirenLosExposure = 0
		perkTrackerState.sirenSlowObservedThisHunt = false
		perkTrackerState.motionSamples = {}
		perkTrackerState.transparencyTransitions = {}
		perkTrackerState.transparencyIntervals = {}
		perkTrackerState.lastTransparencyTransitionTime = nil
		perkTrackerState.pendingWispStart = {
			Time = now,
			FavouriteRoom = ghost:GetAttribute("FavoriteRoom"),
		}
	elseif not hunting and previous then
		local completedHuntDuration = perkTrackerState.huntStartedAt
			and (now - perkTrackerState.huntStartedAt)
			or 0
		perkTrackerState.huntStartedAt = nil
		perkTrackerState.umbraRootSoundAbsentTime = 0
		if completedHuntDuration >= 2.5
			and perkTrackerState.dullahanSawLineOfSight
			and perkTrackerState.dullahanLosSampleCount >= 10
			and #perkTrackerState.dullahanIncreaseEvents < 3 then
			perkTrackerState.ruleOutGhost(
				"Dullahan",
				"an adequately sampled hunt had no repeated WalkSpeed increases",
				92
			)
		end
		if perkTrackerState.sirenLosExposure >= 4
			and not perkTrackerState.sirenSlowObservedThisHunt then
			perkTrackerState.ruleOutGhost(
				"Siren",
				"the ghost maintained line of sight without attempting to slow the player",
				90
			)
		end
		local dullahanHumanoid = ghost:FindFirstChildOfClass("Humanoid")
		local dullahanSpeed = dullahanHumanoid and dullahanHumanoid.WalkSpeed or nil
		if #perkTrackerState.dullahanIncreaseEvents >= 3 then
			perkTrackerState.dullahanCompletedNoIncreaseHunt = false
			perkTrackerState.dybbukMaybeReady = false
			clearPerkDetection("Dybbuk")
		elseif completedHuntDuration >= 3
			and perkTrackerState.dullahanSawLineOfSight
			and perkTrackerState.dullahanLosSampleCount >= 5 then
			perkTrackerState.dullahanCompletedNoIncreaseHunt = true
		end
		perkTrackerState.dullahanBaselineSpeed = dullahanSpeed
		perkTrackerState.dullahanLastSpeed = dullahanSpeed
		perkTrackerState.dullahanIncreaseEvents = {}
		perkTrackerState.dullahanSawLineOfSight = false
		perkTrackerState.dullahanHuntSampleCount = 0
		perkTrackerState.dullahanLosSampleCount = 0
		perkTrackerState.dullahanLosBaseline = nil
		perkTrackerState.dullahanMaxLosSpeed = nil
		local pending = perkTrackerState.pendingKill
		if pending
			and now - pending.Time <= 1.0
			and (pending.OtherAlive or 0) > 0
			and (pending.HuntAge or 0) >= 1.0 then
			recordPerkDetection(
				"Revenant",
				"hunt stopped immediately after a player died",
				35
			)
			perkTrackerState.pendingKill = nil
		end
	end
	perkTrackerState.lastHunting = hunting
end
local function evaluatePendingWispStart(ghost, now)
	local pending = perkTrackerState.pendingWispStart
	if not pending or now - pending.Time < 0.75 then
		return
	end

	perkTrackerState.pendingWispStart = nil
	local favouriteName =
		ghost:GetAttribute("FavoriteRoom")
		or pending.FavouriteRoom
	local roomsFolder = findRoomsFolder()
	local favouriteRoom =
		findFavouriteRoom(roomsFolder, favouriteName)
	local currentRoom = ghost:GetAttribute("CurrentRoom")
	local inFavourite =
		sameRoomName(currentRoom, favouriteName)
		or (
			favouriteRoom
			and instanceIsInsideRoom(ghost, favouriteRoom)
		)

	if inFavourite then
		perkTrackerState.clearGhostRuleOut("Wisp")
		perkTrackerState.wispFavouriteHuntCount =
			perkTrackerState.wispFavouriteHuntCount + 1
		local count = perkTrackerState.wispFavouriteHuntCount

		recordPerkDetection(
			"Wisp",
			"a hunt began inside the favourite room ("
				.. tostring(count)
				.. " observed)",
			count >= 5 and 65 or 35
		)

		local detection = perkDetections.Wisp
		if detection then
			detection.Persistent = true
			detection.ExpiresAt = nil
		end
		updateGhostIdentification(ghost)
		return
	end

	-- Only rule it out when CurrentRoom is a known, different room. A nil or
	-- still-replicating room value does not erase an earlier Wisp observation.
	if currentRoom ~= nil
		and favouriteName ~= nil
		and not sameRoomName(currentRoom, favouriteName) then
		perkTrackerState.wispFavouriteHuntCount = 0
		perkTrackerState.ruleOutGhost(
			"Wisp",
			"a verified hunt began outside the favourite room",
			95
		)
	end
end
local function analyzePhantom(now)
	local samples = {}
	for _, sample in ipairs(perkTrackerState.motionSamples) do
		if sample.Hunting
			and sample.Time >= now - 8
			and typeof(sample.GhostWalkSpeed) == "number"
			and sample.GhostWalkSpeed > 0
			and typeof(sample.Invisible) == "boolean" then
			table.insert(samples, sample)
		end
	end
	if #samples < 7 then
		return
	end
	local transitions = {}
	for index = 2, #samples do
		local beforeSample = samples[index - 1]
		local afterSample = samples[index]
		if beforeSample.Invisible ~= afterSample.Invisible then
			local beforeValues = {}
			local afterValues = {}
			for sampleIndex = math.max(1, index - 3), index - 1 do
				local sample = samples[sampleIndex]
				if sample.Invisible == beforeSample.Invisible then
					table.insert(
						beforeValues,
						sample.GhostWalkSpeed
					)
				end
			end
			for sampleIndex = index, math.min(#samples, index + 2) do
				local sample = samples[sampleIndex]
				if sample.Invisible == afterSample.Invisible then
					table.insert(
						afterValues,
						sample.GhostWalkSpeed
					)
				end
			end
			local beforeSpeed = median(beforeValues)
			local afterSpeed = median(afterValues)
			if beforeSpeed and afterSpeed then
				table.insert(transitions, {
					BeforeInvisible = beforeSample.Invisible,
					AfterInvisible = afterSample.Invisible,
					BeforeSpeed = beforeSpeed,
					AfterSpeed = afterSpeed,
				})
			end
		end
	end
	if #transitions < 3 then
		return
	end
	local mapFactor = getMapSizeSpeedFactor()
	local bestMatched = 0
	local bestMultiplier
	for step = 0, 6 do
		local multiplier = 0.5 + step * 0.25
		local visibleExpected =
			11 * mapFactor * multiplier
		local invisibleExpected =
			13.5 * mapFactor * multiplier
		local matched = 0
		for _, transition in ipairs(transitions) do
			local beforeExpected =
				transition.BeforeInvisible
				and invisibleExpected
				or visibleExpected
			local afterExpected =
				transition.AfterInvisible
				and invisibleExpected
				or visibleExpected
			local beforeTolerance =
				math.max(0.18, beforeExpected * 0.035)
			local afterTolerance =
				math.max(0.18, afterExpected * 0.035)
			local expectedDirection =
				afterExpected - beforeExpected
			local observedDirection =
				transition.AfterSpeed - transition.BeforeSpeed
			if math.abs(
					transition.BeforeSpeed - beforeExpected
				) <= beforeTolerance
				and math.abs(
					transition.AfterSpeed - afterExpected
				) <= afterTolerance
				and observedDirection * expectedDirection > 0 then
				matched = matched + 1
			end
		end
		if matched > bestMatched then
			bestMatched = matched
			bestMultiplier = multiplier
		end
	end
	if bestMatched >= 3 then
		perkTrackerState.clearGhostRuleOut("Phantom")
		recordPerkDetection(
			"Phantom",
			"three transparency transitions synchronized with the 11/13.5 WalkSpeed modes at "
				.. tostring(
					math.floor(bestMultiplier * 100 + 0.5)
				)
				.. "% Ghost Walkspeed Multiplier",
			99
		)
	else
		clearPerkDetection("Phantom")
		perkTrackerState.ruleOutGhost(
			"Phantom",
			"three transparency transitions failed the WalkSpeed synchronization check",
			99
		)
	end
end
perkTrackerState.analyzeSpecter = function(
	ghost,
	hunting,
	measuredSpeed,
	now
)
	local state = perkTrackerState
	if hunting then
		return
	end

	local favouriteName =
		ghost:GetAttribute("FavoriteRoom")
	if not favouriteName
		or tostring(favouriteName) == "" then
		state.specterStationaryCandidateAt = nil
		state.specterStationaryArmed = false
		return
	end

	local roomsFolder = findRoomsFolder()
	local favouriteRoom =
		findFavouriteRoom(roomsFolder, favouriteName)
	local currentRoom = ghost:GetAttribute("CurrentRoom")
	local inFavourite =
		sameRoomName(currentRoom, favouriteName)
		or (
			favouriteRoom
			and instanceIsInsideRoom(ghost, favouriteRoom)
		)

	local recentSpeeds = valuesFromSamples(
		state.motionSamples,
		"Speed",
		function(sample)
			return not sample.Hunting
				and sample.Time >= now - 0.8
		end
	)
	local settledSpeed = median(recentSpeeds) or measuredSpeed
	local stationary = settledSpeed <= 0.22

	if not state.specterTrackedFavouriteName then
		state.specterTrackedFavouriteName = favouriteName
	elseif not sameRoomName(
		state.specterTrackedFavouriteName,
		favouriteName
	) then
		-- Favourite-room changes legitimately make the ghost travel. Pause the
		-- session until it settles for two seconds in the new favourite room.
		state.specterTrackedFavouriteName = favouriteName
		state.specterRoomChangePause = true
		state.specterRoomChangeSettleSince = nil
		state.specterStationaryCandidateAt = nil
		state.specterStationaryArmed = false
	end

	if state.specterRoomChangePause then
		if inFavourite and stationary then
			if not state.specterRoomChangeSettleSince then
				state.specterRoomChangeSettleSince = now
			elseif now - state.specterRoomChangeSettleSince >= 2 then
				state.specterRoomChangePause = false
				state.specterRoomChangeSettleSince = nil
				state.specterStationaryCandidateAt = now
			end
		else
			state.specterRoomChangeSettleSince = nil
		end
		return
	end

	if not inFavourite or not stationary then
		if state.specterStationaryArmed then
			perkTrackerState.ruleOutGhost(
				"Specter",
				"after standing still for five seconds in an unchanged favourite room, the roaming ghost moved before hunting",
				95
			)
		end
		state.specterStationaryCandidateAt = nil
		state.specterIdleSince = nil
		state.specterStationaryArmed = false
		return
	end

	if not state.specterStationaryCandidateAt then
		state.specterStationaryCandidateAt = now
		return
	end

	if now - state.specterStationaryCandidateAt >= 5 then
		state.specterStationaryArmed = true
	end
end
local function analyzeDullahan(now, lineOfSight)
	local state = perkTrackerState
	state.dullahanHuntSampleCount = state.dullahanHuntSampleCount + 1
	local ghost = state.ghost
	local humanoid = ghost and ghost:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local currentSpeed = humanoid.WalkSpeed
	if typeof(currentSpeed) ~= "number" or currentSpeed <= 0 then
		return
	end
	for index = #state.dullahanIncreaseEvents, 1, -1 do
		if now - state.dullahanIncreaseEvents[index].Time > 8 then
			table.remove(state.dullahanIncreaseEvents, index)
		end
	end

	if lineOfSight then
		state.dullahanLosSampleCount = state.dullahanLosSampleCount + 1
		if not state.dullahanSawLineOfSight then
			state.dullahanSawLineOfSight = true
			state.dullahanLosBaseline = currentSpeed
			state.dullahanMaxLosSpeed = currentSpeed
			state.dullahanLastSpeed = currentSpeed
			return
		end
		local baseline = math.max(state.dullahanLosBaseline or currentSpeed, 1)
		local previousSpeed = state.dullahanLastSpeed or currentSpeed
		local change = currentSpeed - previousSpeed
		local relativeChange = change / baseline
		state.dullahanLastSpeed = currentSpeed
		state.dullahanMaxLosSpeed = math.max(state.dullahanMaxLosSpeed or currentSpeed, currentSpeed)
		if change >= math.max(0.02, baseline * 0.003)
			and relativeChange <= 0.08 then
			table.insert(state.dullahanIncreaseEvents, {
				Time = now,
				Delta = change,
				RelativeDelta = relativeChange,
				Speed = currentSpeed,
			})
		end
		return
	end

	state.dullahanLastSpeed = currentSpeed
	if not state.dullahanSawLineOfSight then
		return
	end
	local baseline = math.max(state.dullahanLosBaseline or currentSpeed, 1)
	local maximum = state.dullahanMaxLosSpeed or currentSpeed
	local rampObserved = #state.dullahanIncreaseEvents >= 3
		and maximum >= baseline * 1.08
	local resetObserved = currentSpeed <= baseline * 1.04
	if rampObserved and resetObserved and not perkDetections.Dullahan then
		perkTrackerState.clearGhostRuleOut("Dullahan")
		state.dullahanCompletedNoIncreaseHunt = false
		state.dybbukMaybeReady = false
		clearPerkDetection("Dybbuk")
		recordPerkDetection(
			"Dullahan",
			"Ghost WalkSpeed ramped through sustained line of sight and reset when line of sight broke",
			97
		)
	end
end
perkTrackerState.updateDybbukMaybe = function(ghost)
	if not ghost then
		return
	end
	if perkDetections.Dullahan or checkVexMaybe(ghost) or perkDetections.Vex then
		perkTrackerState.dybbukMaybeReady = false
		clearPerkDetection("Dybbuk")
		return
	end
	if freezingEvidenceFound
		and evidenceFound.Wither
		and perkTrackerState.lidarVisibleObserved
		and perkTrackerState.dullahanCompletedNoIncreaseHunt then
		perkTrackerState.dybbukMaybeReady = true
		recordPerkDetection(
			"Dybbuk",
			"Freezing and Wither were observed, the ghost appeared on LIDAR, and a completed hunt lacked Dullahan-style speed steps",
			60
		)
	end
end
local function analyzeWendigo(now)
	if perkDetections.Aswang
		or perkDetections.Dullahan
		or #perkTrackerState.dullahanIncreaseEvents >= 3 then
		return
	end

	local latest
	for index = #perkTrackerState.motionSamples, 1, -1 do
		local sample = perkTrackerState.motionSamples[index]
		if typeof(sample.Energy) == "number"
			and typeof(sample.GhostWalkSpeed) == "number"
			and sample.GhostWalkSpeed > 0 then
			latest = sample
			break
		end
	end
	if not latest then
		return
	end

	local snapshots = perkTrackerState.wendigoSnapshots
	for index = #snapshots, 1, -1 do
		if now - snapshots[index].Time > 6 then
			table.remove(snapshots, index)
		end
	end

	if now >= perkTrackerState.wendigoNextSnapshotAt then
		table.insert(snapshots, {
			Time = now,
			Sanity = math.clamp(latest.Energy, 0, 100),
			Speed = latest.GhostWalkSpeed,
		})
		while #snapshots > 3 do
			table.remove(snapshots, 1)
		end
		perkTrackerState.wendigoNextSnapshotAt =
			now
			+ perkTrackerState.wendigoSnapshotRandom:NextNumber(
				0.3,
				0.55
			)
	end

	local roundedSanity =
		math.floor(math.clamp(latest.Energy, 0, 100) + 0.5)
	local requiredSnapshots = 3
	if roundedSanity <= 0 then
		requiredSnapshots = 1
	elseif roundedSanity == 1 then
		requiredSnapshots = 2
	end

	if #snapshots < requiredSnapshots then
		return
	end

	local legalMultipliers = {
		0.5,
		0.75,
		1,
		1.25,
		1.5,
		1.75,
		2,
	}
	local mapFactor = getMapSizeSpeedFactor()
	local matchedMultiplier
	local invalidReason

	for index = #snapshots - requiredSnapshots + 1, #snapshots do
		local snapshot = snapshots[index]
		local baseSpeed =
			14 - snapshot.Sanity * 0.05
		local inferred =
			snapshot.Speed
			/ math.max(mapFactor * baseSpeed, 0.001)
		local nearest
		local nearestError = math.huge

		for _, multiplier in ipairs(legalMultipliers) do
			local errorAmount =
				math.abs(inferred - multiplier)
			if errorAmount < nearestError then
				nearestError = errorAmount
				nearest = multiplier
			end
		end

		if nearestError > 0.0035 then
			invalidReason =
				"observed multiplier "
				.. string.format("%.4f", inferred)
				.. " was not one of the configured 50%-200% steps"
			break
		end

		if matchedMultiplier
			and math.abs(matchedMultiplier - nearest) > 0.001 then
			invalidReason =
				"successive snapshots required different custom multipliers"
			break
		end
		matchedMultiplier = nearest
	end

	if invalidReason then
		clearPerkDetection("Wendigo")
		perkTrackerState.ruleOutGhost(
			"Wendigo",
			invalidReason,
			99
		)
		return
	end

	if matchedMultiplier then
		perkTrackerState.clearGhostRuleOut("Wendigo")
		recordPerkDetection(
			"Wendigo",
			tostring(requiredSnapshots)
				.. " WalkSpeed snapshot"
				.. (requiredSnapshots == 1 and "" or "s")
				.. " exactly matched the 9-14 sanity curve at "
				.. tostring(
					math.floor(matchedMultiplier * 100 + 0.5)
				)
				.. "% Ghost Walkspeed Multiplier",
			99
		)
		updateGhostIdentification(perkTrackerState.ghost)
	end
end
local function analyzeOni(now)
	local nonHuntSpeed, nonHuntCount =
		recentNonHuntWalkSpeed(now)
	if not nonHuntSpeed or nonHuntCount < 2 then
		return
	end
	local _, ordinaryError, customMultiplier =
		closestConfiguredBaseSpeed(nonHuntSpeed, 11)
	local baselineTolerance =
		math.max(0.16, nonHuntSpeed * 0.025)
	if not customMultiplier
		or ordinaryError > baselineTolerance then
		return
	end
	local huntVisibleSpeeds = valuesFromSamples(
		perkTrackerState.motionSamples,
		"GhostWalkSpeed",
		function(sample)
			return sample.Hunting
				and sample.Time >= now - 1.4
				and sample.Invisible ~= true
		end
	)
	if #huntVisibleSpeeds < 3 then
		return
	end
	local huntMedian = median(huntVisibleSpeeds)
	if not huntMedian then
		return
	end
	local mapFactor = getMapSizeSpeedFactor()
	local expectedOni =
		13.5 * mapFactor * customMultiplier
	local expectedNormal =
		11 * mapFactor * customMultiplier
	local oniError = math.abs(huntMedian - expectedOni)
	local normalError = math.abs(huntMedian - expectedNormal)
	local oniTolerance =
		math.max(0.2, expectedOni * 0.028)
	local stable =
		standardDeviation(huntVisibleSpeeds)
		<= math.max(0.16, expectedOni * 0.022)
	if stable
		and oniError <= oniTolerance
		and normalError - oniError
			>= math.max(0.12, expectedOni * 0.008) then
		perkTrackerState.clearGhostRuleOut("Oni")
		recordPerkDetection(
			"Oni",
			"visible hunting WalkSpeed quickly matched the scaled 13.5 Oni mode after a scaled 11 non-hunt baseline",
			99
		)
		updateGhostIdentification(perkTrackerState.ghost)
	elseif #huntVisibleSpeeds >= 4
		and stable
		and normalError <= math.max(0.18, expectedNormal * 0.025)
		and oniError - normalError >= 0.15 then
		clearPerkDetection("Oni")
		perkTrackerState.ruleOutGhost(
			"Oni",
			"visible hunting WalkSpeed stayed at the scaled normal 11 mode",
			95
		)
	end
end
local function analyzeUmbra(now)
	local cutoff = now - 25
	while perkTrackerState.umbraSamples[1]
		and perkTrackerState.umbraSamples[1].Time < cutoff do
		table.remove(perkTrackerState.umbraSamples, 1)
	end
	local byRoom = {}
	for _, sample in ipairs(perkTrackerState.umbraSamples) do
		local roomSamples = byRoom[sample.Room]
		if not roomSamples then
			roomSamples = {Lit = {}, Dark = {}}
			byRoom[sample.Room] = roomSamples
		end
		table.insert(sample.Lit and roomSamples.Lit or roomSamples.Dark, sample)
	end
	for roomName, roomSamples in pairs(byRoom) do
		if (perkTrackerState.umbraLightTransitionsByRoom[roomName] or 0) >= 1
			and #roomSamples.Lit >= 15
			and #roomSamples.Dark >= 15 then
			local litSpeeds = valuesFromSamples(roomSamples.Lit, "Speed")
			local darkSpeeds = valuesFromSamples(roomSamples.Dark, "Speed")
			local litMedian = median(litSpeeds)
			local darkMedian = median(darkSpeeds)
			local litEnergies = valuesFromSamples(roomSamples.Lit, "Energy")
			local darkEnergies = valuesFromSamples(roomSamples.Dark, "Energy")
			local litEnergy = median(litEnergies)
			local darkEnergy = median(darkEnergies)
			local energyComparable = not litEnergy
				or not darkEnergy
				or math.abs(litEnergy - darkEnergy) <= 10
			if litMedian and darkMedian and darkMedian > 4 and energyComparable then
				local ratio = litMedian / darkMedian
				local stable = standardDeviation(litSpeeds) <= 1.25
					and standardDeviation(darkSpeeds) <= 1.25
				if stable
					and ratio >= 0.74
					and ratio <= 0.86
					and darkMedian - litMedian >= 0.65 then
					perkTrackerState.umbraLitMatch = {
						Time = now,
						Reason = string.format(
							"ghost speed in lit %s was %.2fx its dark-room speed",
							roomName,
							ratio
						),
					}
					return
				end
			end
		end
	end
end
local function updateUmbraSoundSupport(
	ghost,
	hunting,
	moving,
	deltaTime,
	now
)
	if not hunting or not moving then
		perkTrackerState.umbraRootSoundPresentTime = 0
		perkTrackerState.umbraRootSoundAbsentTime = 0
		return
	end
	local rootHasSound = ghostRootHasAnySound(ghost)

	if rootHasSound == true then
		perkTrackerState.umbraRootSoundPresentTime =
			perkTrackerState.umbraRootSoundPresentTime + deltaTime
		perkTrackerState.umbraRootSoundAbsentTime = 0
		clearPerkDetection("Umbra")

		if perkTrackerState.umbraRootSoundPresentTime >= 1.5 then
			perkTrackerState.ruleOutGhost(
				"Umbra",
				"a moving hunt repeatedly exposed non-Hunting Sound objects on the ghost root",
				90
			)
		end
		return
	elseif rootHasSound == false then
		perkTrackerState.umbraRootSoundAbsentTime =
			perkTrackerState.umbraRootSoundAbsentTime + deltaTime
		perkTrackerState.umbraRootSoundPresentTime = 0
	end

	local litMatch = perkTrackerState.umbraLitMatch
	if litMatch and now - litMatch.Time > 60 then
		perkTrackerState.umbraLitMatch = nil
		litMatch = nil
	end

	local silentHuntObserved = perkTrackerState.umbraRootSoundAbsentTime >= 2
	local skinwalkerPossible = ghostSupportsConfirmedEvidence(
		"Skinwalker",
		getConfirmedEvidence()
	)
	if litMatch and silentHuntObserved and not skinwalkerPossible then
		perkTrackerState.clearGhostRuleOut("Umbra")
		recordPerkDetection(
			"Umbra",
			litMatch.Reason
				.. " and HumanoidRootPart contained no non-Hunting Sound objects",
			99
		)
	elseif silentHuntObserved then
		perkTrackerState.clearGhostRuleOut("Umbra")
		recordPerkDetection(
			"Umbra",
			"a moving hunt produced no non-Hunting Sound objects on the ghost root",
			60
		)
		if skinwalkerPossible then
			recordPerkDetection(
				"Skinwalker",
				"Skinwalker may mimic the Umbra silent-hunt ability",
				60
			)
		end
	elseif litMatch then
		recordPerkDetection(
			"Umbra",
			litMatch.Reason,
			60
		)
	end
end
perkTrackerState.findCrossPart = function(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	local crossPart = model:FindFirstChild("Cross", true)
	if crossPart and crossPart:IsA("BasePart") then
		return crossPart
	end
	return nil
end
perkTrackerState.startCrossBurnTracking = function(model)
	local state = perkTrackerState
	if not model or state.activeCrossBurns[model] then
		return
	end
	local crossPart = state.findCrossPart(model)
	if not crossPart then
		return
	end
	state.activeCrossBurns[model] = {
		Part = crossPart,
		StartTime = os.clock(),
		StartPosition = crossPart.Position,
		LastCFrame = crossPart.CFrame,
		AccumulatedAngle = 0,
		MaxRise = 0,
		MaxHorizontalTravel = 0,
	}
end
perkTrackerState.bindCrossModel = function(model)
	local state = perkTrackerState
	if not model
		or state.crossTrackedModels[model]
		or not model:IsA("Model")
		or model:GetAttribute("ItemName") ~= "Cross" then
		return
	end
	state.crossTrackedModels[model] = true
	local function bindParticle(particle)
		if not particle:IsA("ParticleEmitter") then
			return
		end
		local crossPart = state.findCrossPart(model)
		if not crossPart or not particle:IsDescendantOf(crossPart) then
			return
		end
		state.crossParticleStates[particle] = particle.Enabled == true
		connect(particle:GetPropertyChangedSignal("Enabled"), function()
			if closed or not particle.Parent then
				return
			end
			local previous = state.crossParticleStates[particle]
			local current = particle.Enabled == true
			state.crossParticleStates[particle] = current
			if current and previous ~= true then
				state.startCrossBurnTracking(model)
			end
		end)
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		bindParticle(descendant)
	end
	connect(model.DescendantAdded, bindParticle)
end
perkTrackerState.ensureCrossDemonTracker = function()
	local state = perkTrackerState
	local items = workspace:FindFirstChild("Items")
	if not items then
		return
	end
	if state.crossItemsFolder ~= items then
		state.crossItemsFolder = items
		connect(items.ChildAdded, function(child)
			task.defer(function()
				if not closed and child.Parent == items then
					state.bindCrossModel(child)
				end
			end)
		end)
	end
	for _, child in ipairs(items:GetChildren()) do
		state.bindCrossModel(child)
	end
end
perkTrackerState.updateCrossDemonTracker = function(now)
	local state = perkTrackerState
	for model, observation in pairs(state.activeCrossBurns) do
		local part = observation.Part
		local failedBecauseRemoved = not model.Parent or not part or not part.Parent
		if not failedBecauseRemoved then
			local currentCFrame = part.CFrame
			local relativeRotation = observation.LastCFrame.Rotation:ToObjectSpace(
				currentCFrame.Rotation
			)
			local _, angle = relativeRotation:ToAxisAngle()
			angle = math.abs(angle)
			if angle <= math.rad(100) then
				observation.AccumulatedAngle = observation.AccumulatedAngle + angle
			end
			local offset = currentCFrame.Position - observation.StartPosition
			observation.MaxRise = math.max(observation.MaxRise, offset.Y)
			observation.MaxHorizontalTravel = math.max(
				observation.MaxHorizontalTravel,
				Vector3.new(offset.X, 0, offset.Z).Magnitude
			)
			observation.LastCFrame = currentCFrame
			if observation.MaxRise >= 0.45
				and observation.AccumulatedAngle >= math.rad(45)
				and observation.MaxHorizontalTravel <= 5 then
				state.demonMotionObserved = true
				state.demonRuledOut = false
				state.activeCrossBurns[model] = nil
				recordPerkDetection(
					"Demon",
					"an activated Cross rotated repeatedly and floated upward",
					99
				)
				updateGhostIdentification(state.ghost)
				continue
			end
		end
		if failedBecauseRemoved or now - observation.StartTime >= 4 then
			state.activeCrossBurns[model] = nil
			if not state.demonMotionObserved then
				state.demonRuledOut = true
				perkTrackerState.ruleOutGhost(
					"Demon",
					"an activated Cross did not perform the Demon-only animation",
					92
				)
				updateGhostIdentification(state.ghost)
			end
		end
	end
end
perkTrackerState.saltModelPosition = function(model)
	if not model or not model.Parent then
		return nil
	end
	local ok, pivot = pcall(function()
		return model:GetPivot()
	end)
	if ok then
		return pivot.Position
	end
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end
perkTrackerState.markSaltDisturbed = function(disturbedModel)
	local disturbedPosition = perkTrackerState.saltModelPosition(disturbedModel)
	local nearestModel
	local nearestDistance = math.huge
	for saltModel, observation in pairs(perkTrackerState.saltPendingTouches) do
		if observation
			and not observation.Disturbed
			and disturbedPosition
			and observation.Position then
			local distance = (disturbedPosition - observation.Position).Magnitude
			if distance < nearestDistance and distance <= 10 then
				nearestModel = saltModel
				nearestDistance = distance
			end
		end
	end
	local observation = nearestModel
		and perkTrackerState.saltPendingTouches[nearestModel]
		or perkTrackerState.saltPendingTouches[disturbedModel]
	if not observation then
		local ghost = getGhostModel()
		local ghostPosition = ghost and ghost:GetPivot().Position or nil
		if ghost
			and ghostPosition
			and disturbedPosition
			and (ghostPosition - disturbedPosition).Magnitude <= 12 then
			local now = os.clock()
			local humanoid = ghost:FindFirstChildOfClass("Humanoid")
			local currentSpeed = humanoid and humanoid.WalkSpeed or nil
			local huntingAtTouch =
				ghost:GetAttribute("Hunting") == true
			observation = {
				StartedAt = now,
				Position = disturbedPosition,
				PreSpeed =
					huntingAtTouch
					and (
						perkTrackerState.recentSaltPreSpeed(
							ghost,
							now
						)
						or currentSpeed
					)
					or nil,
				MinPostSpeed =
					huntingAtTouch and currentSpeed or nil,
				HuntingAtTouch = huntingAtTouch,
				Ghost = ghost,
				Disturbed = false,
				WraithResolved = false,
				AswangResolved = false,
			}
			perkTrackerState.saltPendingTouches[disturbedModel] = observation
		else
			return
		end
	end
	observation.Disturbed = true
	observation.DisturbedAt = os.clock()
	perkTrackerState.wraithRuledOut = true
	perkTrackerState.ruleOutGhost(
		"Wraith",
		"the touched SaltLine became DisturbedSaltLine",
		99
	)
	updateGhostIdentification(perkTrackerState.ghost)
end
perkTrackerState.recentSaltPreSpeed = function(ghost, now)
	local recentSpeeds = {}
	for _, sample in ipairs(perkTrackerState.motionSamples) do
		if sample.Hunting
			and sample.Time >= now - 1.5
			and sample.Time <= now
			and typeof(sample.GhostWalkSpeed) == "number"
			and sample.GhostWalkSpeed > 0 then
			table.insert(recentSpeeds, sample.GhostWalkSpeed)
		end
	end
	local humanoid = ghost and ghost:FindFirstChildOfClass("Humanoid")
	if humanoid
		and typeof(humanoid.WalkSpeed) == "number"
		and humanoid.WalkSpeed > 0 then
		table.insert(recentSpeeds, humanoid.WalkSpeed)
	end
	local highest
	for _, speed in ipairs(recentSpeeds) do
		highest = math.max(highest or speed, speed)
	end
	return highest
end
perkTrackerState.beginSaltTouch = function(saltModel)
	if closed
		or not saltModel
		or not saltModel.Parent
		or saltModel.Name ~= "SaltLine" then
		return
	end
	local ghost = getGhostModel()
	if not ghost then
		return
	end
	local now = os.clock()
	local existing = perkTrackerState.saltPendingTouches[saltModel]
	if existing and now - existing.StartedAt < 1.5 then
		return
	end
	local humanoid = ghost:FindFirstChildOfClass("Humanoid")
	local currentSpeed = humanoid and humanoid.WalkSpeed or nil
	local huntingAtTouch =
		ghost:GetAttribute("Hunting") == true
	local preSpeed =
		huntingAtTouch
		and perkTrackerState.recentSaltPreSpeed(ghost, now)
		or nil
	perkTrackerState.saltPendingTouches[saltModel] = {
		StartedAt = now,
		Position = perkTrackerState.saltModelPosition(saltModel),
		PreSpeed =
			huntingAtTouch and (preSpeed or currentSpeed) or nil,
		MinPostSpeed =
			huntingAtTouch and currentSpeed or nil,
		HuntingAtTouch = huntingAtTouch,
		Ghost = ghost,
		Disturbed = false,
		WraithResolved = false,
		AswangResolved = false,
	}
end
perkTrackerState.bindSaltLine = function(model)
	if not model or not model:IsA("Model") then
		return
	end
	if model.Name == "DisturbedSaltLine" then
		perkTrackerState.markSaltDisturbed(model)
		return
	end
	if model.Name ~= "SaltLine" or perkTrackerState.saltTrackedLines[model] then
		return
	end
	perkTrackerState.saltTrackedLines[model] = true
	local function bindTouchPart(part)
		if not part:IsA("BasePart") then
			return
		end
		connect(part.Touched, function(otherPart)
			if closed or not otherPart or not otherPart.Parent then
				return
			end
			local ghost = getGhostModel()
			if ghost and otherPart:IsDescendantOf(ghost) then
				perkTrackerState.beginSaltTouch(model)
			end
		end)
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		bindTouchPart(descendant)
	end
	connect(model.DescendantAdded, bindTouchPart)
	connect(model:GetPropertyChangedSignal("Name"), function()
		if closed then
			return
		end
		if model.Name == "DisturbedSaltLine" then
			perkTrackerState.markSaltDisturbed(model)
		end
	end)
end
perkTrackerState.ensureSaltTracker = function()
	local folder = workspace:FindFirstChild("SaltPiles")
	if folder ~= perkTrackerState.saltFolder then
		perkTrackerState.saltFolder = folder
		perkTrackerState.saltTrackerInitialized = false
		perkTrackerState.saltTrackedLines = setmetatable({}, {__mode = "k"})
	end
	if not folder or perkTrackerState.saltTrackerInitialized then
		return
	end
	perkTrackerState.saltTrackerInitialized = true
	for _, child in ipairs(folder:GetChildren()) do
		perkTrackerState.bindSaltLine(child)
	end
	connect(folder.ChildAdded, function(child)
		task.defer(function()
			if not closed and child.Parent == folder then
				perkTrackerState.bindSaltLine(child)
			end
		end)
	end)
end
perkTrackerState.updateSaltTracker = function(deltaTime, ghost, hunting, now)
	perkTrackerState.ensureSaltTracker()
	local folder = perkTrackerState.saltFolder
	if not folder or not ghost then
		return
	end
	perkTrackerState.saltOverlapAccumulator =
		perkTrackerState.saltOverlapAccumulator + deltaTime
	if perkTrackerState.saltOverlapAccumulator >= 0.2 then
		perkTrackerState.saltOverlapAccumulator = 0
		local ghostPosition = ghost:GetPivot().Position
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Include
		overlapParams.FilterDescendantsInstances = {ghost}
		overlapParams.MaxParts = 1
		for saltModel in pairs(perkTrackerState.saltTrackedLines) do
			if saltModel.Parent
				and saltModel.Name == "SaltLine"
				and not perkTrackerState.saltPendingTouches[saltModel] then
				local saltPosition = perkTrackerState.saltModelPosition(saltModel)
				if saltPosition
					and (ghostPosition - saltPosition).Magnitude <= 12 then
					local ok, saltCFrame, saltSize = pcall(function()
						return saltModel:GetBoundingBox()
					end)
					if ok then
						local touchingParts = workspace:GetPartBoundsInBox(
							saltCFrame,
							saltSize + Vector3.new(0.5, 1.5, 0.5),
							overlapParams
						)
						if #touchingParts > 0 then
							perkTrackerState.beginSaltTouch(saltModel)
						end
					end
				end
			end
		end
	end
	local humanoid = ghost:FindFirstChildOfClass("Humanoid")
	local currentSpeed = humanoid and humanoid.WalkSpeed or nil
	for saltModel, observation in pairs(perkTrackerState.saltPendingTouches) do
		local age = now - observation.StartedAt
		if observation.Disturbed then
			perkTrackerState.wraithRuledOut = true
			perkTrackerState.ruleOutGhost(
				"Wraith",
				"the touched SaltLine became DisturbedSaltLine",
				99
			)
		elseif age >= 1.25 and not observation.WraithResolved then
			observation.WraithResolved = true
			recordPerkDetection(
				"Wraith",
				"Ghost touched SaltLine and it did not become DisturbedSaltLine",
				95
			)
		end
		if not observation.AswangResolved
			and observation.HuntingAtTouch
			and hunting
			and observation.Ghost == ghost
			and typeof(observation.PreSpeed) == "number"
			and observation.PreSpeed > 0
			and typeof(currentSpeed) == "number"
			and age <= 2.25 then
			observation.MinPostSpeed = math.min(
				observation.MinPostSpeed or currentSpeed,
				currentSpeed
			)
			local observedRatio =
				observation.MinPostSpeed / observation.PreSpeed
			if observedRatio >= 0.64 and observedRatio <= 0.86 then
				observation.AswangResolved = true
				recordPerkDetection(
					"Aswang",
					"Ghost hunting WalkSpeed fell to roughly 75% after salt contact",
					99
				)
				updateGhostIdentification(ghost)
			end
		end
		if age >= 3.5
			or not saltModel.Parent
			or observation.Ghost ~= ghost then
			perkTrackerState.saltPendingTouches[saltModel] = nil
		end
	end
end
perkTrackerState.holyOilSequenceMatches = function(
	emitter,
	firstColor,
	lastColor
)
	if not emitter
		or not emitter:IsA("ParticleEmitter")
		or (
			emitter.Name ~= "Primary"
			and emitter.Name ~= "Secondary"
		) then
		return false
	end

	local keypoints = emitter.Color.Keypoints
	if #keypoints < 2 then
		return false
	end

	local first = keypoints[1]
	local last = keypoints[#keypoints]

	local function close(left, right, tolerance)
		return math.abs(left - right) <= tolerance
	end

	local function colorClose(left, right)
		return close(left.R, right.R, 0.012)
			and close(left.G, right.G, 0.012)
			and close(left.B, right.B, 0.012)
	end

	return close(first.Time, 0, 0.02)
		and close(last.Time, 1, 0.02)
		and colorClose(first.Value, firstColor)
		and colorClose(last.Value, lastColor)
end

perkTrackerState.getHolyOilWall = function(model)
	local wall = model and model:FindFirstChild("GhostWall", true)
	return wall and wall:IsA("BasePart") and wall or nil
end

perkTrackerState.ghostHasHolyOilFire = function(ghost)
	if not ghost then
		return false
	end

	for _, descendant in ipairs(ghost:GetDescendants()) do
		if descendant:IsA("ParticleEmitter")
			and descendant.Name == "Fire"
			and descendant.Enabled == true then
			return true
		end
	end

	return false
end

perkTrackerState.getHolyOilColorKind = function(model)
	local container =
		model and model:FindFirstChild("ParticleContainer", true)
	if not container then
		return nil
	end

	local primary = container:FindFirstChild("Primary", true)
	local secondary = container:FindFirstChild("Secondary", true)
	if not primary
		or not primary:IsA("ParticleEmitter")
		or not secondary
		or not secondary:IsA("ParticleEmitter") then
		return nil
	end

	local spiritFirst = Color3.new(0.384314, 0.541216, 1)
	local spiritLast = Color3.new(0, 0.263333, 1)
	local nonSpiritFirst = Color3.new(1, 0.694118, 0.384314)
	local nonSpiritLast = Color3.new(1, 0.333333, 0)

	local primarySpirit =
		perkTrackerState.holyOilSequenceMatches(
			primary,
			spiritFirst,
			spiritLast
		)
	local secondarySpirit =
		perkTrackerState.holyOilSequenceMatches(
			secondary,
			spiritFirst,
			spiritLast
		)

	if primarySpirit and secondarySpirit then
		return "Spirit"
	end

	local primaryNonSpirit =
		perkTrackerState.holyOilSequenceMatches(
			primary,
			nonSpiritFirst,
			nonSpiritLast
		)
	local secondaryNonSpirit =
		perkTrackerState.holyOilSequenceMatches(
			secondary,
			nonSpiritFirst,
			nonSpiritLast
		)

	if primaryNonSpirit and secondaryNonSpirit then
		return "NonSpirit"
	end

	return nil
end

perkTrackerState.getHolyOilWallSide = function(wall, position)
	if not wall or not position then
		return nil, nil, nil
	end

	local localPosition =
		wall.CFrame:PointToObjectSpace(position)

	if wall.Size.X <= wall.Size.Z then
		return localPosition.X, wall.Size.X * 0.5, "X"
	end

	return localPosition.Z, wall.Size.Z * 0.5, "Z"
end

perkTrackerState.holyOilGhostInside = function(model, ghost)
	if not model or not model.Parent or not ghost then
		return false
	end

	local ok, modelCFrame, modelSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok then
		return false
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = {ghost}
	overlapParams.MaxParts = 1

	return #workspace:GetPartBoundsInBox(
		modelCFrame,
		modelSize + Vector3.new(0.5, 1, 0.5),
		overlapParams
	) > 0
end

perkTrackerState.evaluateHolyOilWallStates = function()
	local sawWall = false
	local sawNonCollidable = false

	for model in pairs(perkTrackerState.holyOilTrackedModels) do
		if model.Parent then
			local wall = perkTrackerState.getHolyOilWall(model)
			if wall then
				sawWall = true
				if wall.CanCollide == false then
					sawNonCollidable = true
					break
				end
			end
		end
	end

	if sawNonCollidable then
		perkTrackerState.clearGhostRuleOut("Wisp")
		recordPerkDetection(
			"Wisp",
			"HolyOil.GhostWall.CanCollide was false",
			99
		)
		updateGhostIdentification(getGhostModel())
	elseif sawWall then
		clearPerkDetection("Wisp")
		perkTrackerState.ruleOutGhost(
			"Wisp",
			"all observed HolyOil.GhostWall parts had CanCollide enabled",
			99
		)
	end
end

perkTrackerState.evaluateHolyOilColor = function(model, ghost)
	if not model
		or not model.Parent
		or not ghost
		or ghost:GetAttribute("Hunting") ~= true
		or model:GetAttribute("Burning") ~= true then
		return nil
	end

	local kind = perkTrackerState.getHolyOilColorKind(model)
	if kind == nil then
		return nil
	end

	if perkTrackerState.holyOilColorStates[model] == kind then
		return kind
	end
	perkTrackerState.holyOilColorStates[model] = kind

	if kind == "Spirit" then
		perkTrackerState.clearGhostRuleOut("Spirit")
		recordPerkDetection(
			"Spirit",
			"burning Holy Oil Primary and Secondary matched the Spirit blue sequence",
			99
		)
		updateGhostIdentification(ghost)
	elseif kind == "NonSpirit" then
		clearPerkDetection("Spirit")
		perkTrackerState.ruleOutGhost(
			"Spirit",
			"burning Holy Oil Primary and Secondary matched the non-Spirit orange sequence",
			99
		)
	end

	return kind
end

perkTrackerState.beginHolyOilContact = function(model)
	local ghost = getGhostModel()
	if not ghost
		or ghost:GetAttribute("Hunting") ~= true
		or not model
		or not model.Parent
		or model.Name ~= "HolyOil"
		or model:GetAttribute("Burning") ~= true then
		return
	end

	if perkTrackerState.holyOilPendingContacts[model] then
		return
	end

	local now = os.clock()
	local ghostPosition = ghost:GetPivot().Position
	local wall = perkTrackerState.getHolyOilWall(model)
	local side, halfThickness, axis =
		perkTrackerState.getHolyOilWallSide(wall, ghostPosition)
	local entrySign =
		side and side ~= 0 and (side > 0 and 1 or -1) or 0

	if entrySign == 0 and wall then
		local ghostPart = getGhostPart(ghost)
		local velocity =
			ghostPart and ghostPart.AssemblyLinearVelocity
			or Vector3.zero
		local normal =
			axis == "X"
			and wall.CFrame.RightVector
			or wall.CFrame.LookVector
		local direction = velocity:Dot(normal)
		if math.abs(direction) > 0.05 then
			entrySign = direction > 0 and -1 or 1
		end
	end

	perkTrackerState.holyOilPendingContacts[model] = {
		StartedAt = now,
		Ghost = ghost,
		Wall = wall,
		EntrySign = entrySign,
		HalfThickness = halfThickness,
		Axis = axis,
		EntryPosition = ghostPosition,
		WasInside = true,
		FireSeen =
			perkTrackerState.ghostHasHolyOilFire(ghost),
	}
end

perkTrackerState.holyOilPassedThrough = function(pending, ghost)
	local currentPosition = ghost:GetPivot().Position
	local wall =
		pending.Wall
		and pending.Wall.Parent
		and pending.Wall
		or nil

	if wall then
		local side, halfThickness =
			perkTrackerState.getHolyOilWallSide(
				wall,
				currentPosition
			)
		local exitSign =
			side and side ~= 0 and (side > 0 and 1 or -1) or 0

		return pending.EntrySign ~= 0
			and exitSign ~= 0
			and pending.EntrySign ~= exitSign
			and side ~= nil
			and math.abs(side)
				>= (halfThickness or pending.HalfThickness or 0)
					+ 0.15
	end

	return (
		currentPosition - pending.EntryPosition
	).Magnitude >= 3
end

perkTrackerState.bindHolyOilModel = function(model)
	if not model
		or not model:IsA("Model")
		or model.Name ~= "HolyOil"
		or perkTrackerState.holyOilTrackedModels[model] then
		return
	end

	perkTrackerState.holyOilTrackedModels[model] = true

	local function updateBurnState()
		if model:GetAttribute("Burning") == true then
			perkTrackerState.holyOilBurnStartedAt[model] =
				os.clock()
			perkTrackerState.holyOilColorStates[model] = nil

			local ghost = getGhostModel()
			if ghost
				and ghost:GetAttribute("Hunting") == true then
				perkTrackerState.evaluateHolyOilColor(model, ghost)
			end
		else
			perkTrackerState.holyOilBurnStartedAt[model] = nil
			perkTrackerState.holyOilColorStates[model] = nil
			perkTrackerState.holyOilPendingContacts[model] = nil
		end
	end

	connect(
		model:GetAttributeChangedSignal("Burning"),
		updateBurnState
	)
	updateBurnState()

	local function bindPart(part)
		if not part:IsA("BasePart") then
			return
		end

		if part.Name == "GhostWall" then
			connect(
				part:GetPropertyChangedSignal("CanCollide"),
				perkTrackerState.evaluateHolyOilWallStates
			)
		end

		connect(part.Touched, function(otherPart)
			if closed or not otherPart or not otherPart.Parent then
				return
			end

			local ghost = getGhostModel()
			if ghost and otherPart:IsDescendantOf(ghost) then
				perkTrackerState.beginHolyOilContact(model)
			end
		end)
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		bindPart(descendant)
	end

	connect(model.DescendantAdded, function(descendant)
		bindPart(descendant)
		if descendant.Name == "GhostWall" then
			perkTrackerState.evaluateHolyOilWallStates()
		end
	end)

	connect(model.AncestryChanged, function()
		perkTrackerState.evaluateHolyOilWallStates()
	end)

	perkTrackerState.evaluateHolyOilWallStates()
end

perkTrackerState.ensureHolyOilTracker = function()
	local folder = workspace:FindFirstChild("HolyOil")

	if folder ~= perkTrackerState.holyOilFolder then
		perkTrackerState.holyOilFolder = folder
		perkTrackerState.holyOilTrackerInitialized = false
		perkTrackerState.holyOilTrackedModels =
			setmetatable({}, {__mode = "k"})
	end

	if not folder or perkTrackerState.holyOilTrackerInitialized then
		return
	end

	perkTrackerState.holyOilTrackerInitialized = true

	for _, child in ipairs(folder:GetChildren()) do
		perkTrackerState.bindHolyOilModel(child)
	end

	connect(folder.ChildAdded, function(child)
		task.defer(function()
			if not closed and child.Parent == folder then
				perkTrackerState.bindHolyOilModel(child)
			end
		end)
	end)
end

perkTrackerState.evaluateHolyOilAtHuntStart = function(ghost)
	perkTrackerState.ensureHolyOilTracker()
	if not ghost
		or ghost:GetAttribute("Hunting") ~= true then
		return
	end

	perkTrackerState.evaluateHolyOilWallStates()

	for model in pairs(perkTrackerState.holyOilTrackedModels) do
		if model.Parent
			and model:GetAttribute("Burning") == true then
			perkTrackerState.holyOilColorStates[model] = nil
			perkTrackerState.evaluateHolyOilColor(model, ghost)
		end
	end
end

perkTrackerState.updateHolyOilTracker = function(
	deltaTime,
	ghost,
	now
)
	perkTrackerState.ensureHolyOilTracker()
	if not ghost then
		return
	end
	local hunting = ghost:GetAttribute("Hunting") == true
	if not hunting then
		perkTrackerState.holyOilPendingContacts =
			setmetatable({}, {__mode = "k"})
		perkTrackerState.holyOilOverlapAccumulator = 0
		return
	end
	local folder = perkTrackerState.holyOilFolder
	if not folder then
		return
	end
	perkTrackerState.holyOilOverlapAccumulator =
		perkTrackerState.holyOilOverlapAccumulator + deltaTime
	if perkTrackerState.holyOilOverlapAccumulator >= 0.1 then
		perkTrackerState.holyOilOverlapAccumulator = 0
		for model in pairs(
			perkTrackerState.holyOilTrackedModels
		) do
			if model.Parent then
				local burning =
					model:GetAttribute("Burning") == true
				if burning then
					local burnStarted =
						perkTrackerState.holyOilBurnStartedAt[
							model
						]
					if not burnStarted then
						burnStarted = now
						perkTrackerState.holyOilBurnStartedAt[
							model
						] = now
					end
					perkTrackerState.evaluateHolyOilColor(
						model,
						ghost
					)
				else
					perkTrackerState.holyOilBurnStartedAt[model] = nil
					perkTrackerState.holyOilColorStates[model] = nil
				end
				local inside =
					burning
					and perkTrackerState.holyOilGhostInside(
						model,
						ghost
					)
				local pending =
					perkTrackerState.holyOilPendingContacts[
						model
					]
				if inside then
					if not pending then
						perkTrackerState.beginHolyOilContact(model)
						pending =
							perkTrackerState.holyOilPendingContacts[
								model
							]
					end
					if pending then
						pending.WasInside = true
						pending.FireSeen =
							pending.FireSeen
							or perkTrackerState.ghostHasHolyOilFire(
								ghost
							)
					end
				elseif pending then
					if not burning then
						perkTrackerState.holyOilPendingContacts[
							model
						] = nil
					else
						pending.FireSeen =
							pending.FireSeen
							or perkTrackerState.ghostHasHolyOilFire(
								ghost
							)
						local fullPass =
							pending.WasInside
							and perkTrackerState.holyOilPassedThrough(
								pending,
								ghost
							)
						local wall =
							pending.Wall
							and pending.Wall.Parent
							and pending.Wall
							or nil
						local wallAllowsWisp =
							not wall
							or wall.CanCollide == false
						if fullPass
							and pending.FireSeen
							and wallAllowsWisp then
							perkTrackerState.clearGhostRuleOut(
								"Wisp"
							)
							recordPerkDetection(
								"Wisp",
								"while hunting, the ghost fully crossed burning Holy Oil and carried an enabled Fire ParticleEmitter",
								99
							)
							updateGhostIdentification(ghost)
						end
						perkTrackerState.holyOilPendingContacts[
							model
						] = nil
					end
				end
			end
		end
	end
	for model, pending in pairs(
		perkTrackerState.holyOilPendingContacts
	) do
		if not model.Parent
			or pending.Ghost ~= ghost
			or model:GetAttribute("Burning") ~= true
			or now - pending.StartedAt > 4 then
			perkTrackerState.holyOilPendingContacts[model] = nil
		end
	end
end
perkTrackerState.roomNameAtPosition = function(position)
	local rooms = findRoomsFolder()
	if not rooms or not position then
		return nil
	end
	for _, room in ipairs(rooms:GetChildren()) do
		for _, part in ipairs(getRoomBoundingParts(room)) do
			if pointIsInsidePart(part, position) then
				return room.Name
			end
		end
	end
	return nil
end
perkTrackerState.trackTeleportObject = function(object)
	if not object
		or not object.Parent
		or (
			not object:IsA("Model")
			and not object:IsA("BasePart")
		) then
		return
	end
	local position = getInstanceWorldPosition(object)
	if not position then
		return
	end
	perkTrackerState.objectTeleportObjects[object] = {
		Position = position,
		Time = os.clock(),
		Room = perkTrackerState.roomNameAtPosition(position),
	}
end
perkTrackerState.observeTeleportSmoke = function(descendant)
	if not descendant
		or not descendant:IsA("BasePart")
		or descendant.Name ~= "SmokeHolder" then
		return
	end
	table.insert(perkTrackerState.recentSmokeEffects, {
		Time = os.clock(),
		Position = descendant.Position,
		Instance = descendant,
	})
end
perkTrackerState.ensureObjectTeleportTracker = function()
	if perkTrackerState.objectTeleportTrackerInitialized then
		return
	end
	perkTrackerState.objectTeleportTrackerInitialized = true
	for _, folderName in ipairs({"Items", "Interactables"}) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				perkTrackerState.trackTeleportObject(child)
			end
		end
	end
	connect(workspace.DescendantAdded, function(descendant)
		perkTrackerState.observeTeleportSmoke(descendant)
	end)
end
perkTrackerState.updateObjectTeleportTracker = function(deltaTime, now)
	perkTrackerState.ensureObjectTeleportTracker()
	perkTrackerState.objectTeleportAccumulator =
		perkTrackerState.objectTeleportAccumulator + deltaTime
	if perkTrackerState.objectTeleportAccumulator < 0.4 then
		return
	end
	perkTrackerState.objectTeleportAccumulator = 0
	for _, folderName in ipairs({"Items", "Interactables"}) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if not perkTrackerState.objectTeleportObjects[child] then
					perkTrackerState.trackTeleportObject(child)
				end
			end
		end
	end
	for index = #perkTrackerState.recentSmokeEffects, 1, -1 do
		if now - perkTrackerState.recentSmokeEffects[index].Time > 3 then
			table.remove(perkTrackerState.recentSmokeEffects, index)
		end
	end
	for object, previous in pairs(
		perkTrackerState.objectTeleportObjects
	) do
		if not object.Parent then
			perkTrackerState.objectTeleportObjects[object] = nil
		else
			local parentName = object.Parent.Name
			if parentName == "Items"
				or parentName == "Interactables" then
				local position = getInstanceWorldPosition(object)
				if position then
					local elapsed = now - previous.Time
					local displacement =
						(position - previous.Position).Magnitude
					local speed =
						elapsed > 0 and displacement / elapsed or 0
					local room = previous.Room
					if displacement >= 25 then
						room =
							perkTrackerState.roomNameAtPosition(
								position
							)
					end
					if elapsed <= 0.65
						and displacement >= 25
						and speed >= 80
						and previous.Room
						and room
						and room ~= previous.Room then
						table.insert(
							perkTrackerState.pendingObjectTeleports,
							{
								Object = object,
								Time = now,
								ResolveAt = now + 1.4,
								FromPosition = previous.Position,
								ToPosition = position,
								FromRoom = previous.Room,
								ToRoom = room,
							}
						)
					end
					previous.Position = position
					previous.Time = now
					previous.Room = room
				end
			end
		end
	end
	for index =
		#perkTrackerState.pendingObjectTeleports,
		1,
		-1 do
		local pending =
			perkTrackerState.pendingObjectTeleports[index]
		local smokeMatched = false
		for _, smoke in ipairs(
			perkTrackerState.recentSmokeEffects
		) do
			if math.abs(smoke.Time - pending.Time) <= 1.8
				and (
					smoke.Position - pending.FromPosition
				).Magnitude <= 12 then
				smokeMatched = true
				break
			end
		end
		if smokeMatched then
			perkTrackerState.entitySmokeObserved = true
			recordPerkDetection(
				"Entity",
				"an Item/Interactable teleported rooms and left a SmokeHolder at its old position",
				99
			)
			perkTrackerState.ruleOutGhost(
				"Skinwalker",
				"the teleported object left Entity's SmokeHolder effect",
				95
			)
			table.remove(
				perkTrackerState.pendingObjectTeleports,
				index
			)
		elseif now >= pending.ResolveAt then
			recordPerkDetection(
				"Skinwalker",
				"an Item/Interactable teleported rooms without an Entity SmokeHolder",
				97
			)
			perkTrackerState.ruleOutGhost(
				"Entity",
				"the teleported object produced no Entity SmokeHolder",
				95
			)
			table.remove(
				perkTrackerState.pendingObjectTeleports,
				index
			)
		end
	end
end
perkTrackerState.updateRavagerTracker = function(
	deltaTime,
	ghost,
	now
)
	if roomItemPlacementState.busy
		or not ghost
		or ghost:GetAttribute("Hunting") ~= true then
		perkTrackerState.ravagerMotionEvents = {}
		perkTrackerState.ravagerTrackedObjects =
			setmetatable({}, {__mode = "k"})
		return
	end

	perkTrackerState.ravagerScanAccumulator =
		perkTrackerState.ravagerScanAccumulator + deltaTime
	if perkTrackerState.ravagerScanAccumulator < 0.1 then
		return
	end
	perkTrackerState.ravagerScanAccumulator = 0

	local ghostPosition = ghost:GetPivot().Position
	local seen = setmetatable({}, {__mode = "k"})

	for _, folderName in ipairs({"Items", "Interactables"}) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			for _, rootObject in ipairs(folder:GetChildren()) do
				local parts = {}

				if rootObject:IsA("BasePart") then
					table.insert(parts, rootObject)
				else
					for _, descendant in ipairs(
						rootObject:GetDescendants()
					) do
						if descendant:IsA("BasePart") then
							table.insert(parts, descendant)
						end
					end
				end

				for _, part in ipairs(parts) do
					if part.Parent
						and not part.Anchored
						and part.Transparency < 1 then
						seen[part] = true
						local position = part.Position
						local previous =
							perkTrackerState.ravagerTrackedObjects[part]

						local nextState = {
							Position = position,
							GhostPosition = ghostPosition,
							Time = now,
							RootObject = rootObject,
							OrbitStreak = 0,
							AngularTotal = 0,
							OrbitAxis = nil,
						}

						if previous then
							local elapsed = now - previous.Time
							local displacementVector =
								position - previous.Position
							local displacement =
								displacementVector.Magnitude

							if elapsed > 0
								and elapsed <= 0.3
								and displacement >= 0.45 then
								local speed = displacement / elapsed
								local oldRadial =
									previous.Position
									- previous.GhostPosition
								local newRadial =
									position - ghostPosition
								local oldRadius = oldRadial.Magnitude
								local newRadius = newRadial.Magnitude

								if oldRadius >= 3
									and oldRadius <= 34
									and newRadius >= 3
									and newRadius <= 34
									and speed >= 5.5 then
									local oldUnit = oldRadial.Unit
									local newUnit = newRadial.Unit
									local velocity =
										displacementVector / elapsed
									local radialSpeed =
										math.abs(velocity:Dot(newUnit))
									local tangentialRatio =
										math.clamp(
											1
												- radialSpeed
													/ math.max(speed, 0.001),
											0,
											1
										)
									local radiusDifference =
										math.abs(newRadius - oldRadius)
									local angularChange =
										math.deg(math.acos(math.clamp(
											oldUnit:Dot(newUnit),
											-1,
											1
										)))
									local axisVector =
										oldUnit:Cross(newUnit)
									local axis =
										axisVector.Magnitude > 0.01
										and axisVector.Unit
										or nil
									local axisConsistent =
										not previous.OrbitAxis
										or (
											axis
											and previous.OrbitAxis:Dot(axis)
												>= 0.75
										)

									local orbitLike =
										tangentialRatio >= 0.78
										and angularChange >= 2.5
										and radiusDifference
											<= math.max(
												0.9,
												(oldRadius + newRadius)
													* 0.04
											)
										and axisConsistent

									if orbitLike then
										nextState.OrbitStreak =
											(previous.OrbitStreak or 0) + 1
										nextState.AngularTotal =
											(previous.AngularTotal or 0)
											+ angularChange
										nextState.OrbitAxis =
											axis or previous.OrbitAxis

										if nextState.OrbitStreak >= 4
											and nextState.AngularTotal >= 14 then
											table.insert(
												perkTrackerState.ravagerMotionEvents,
												{
													Time = now,
													Part = part,
													RootObject = rootObject,
													Speed = speed,
													Axis =
														nextState.OrbitAxis,
													AngularTotal =
														nextState.AngularTotal,
												}
											)
										end
									end
								end
							end
						end

						perkTrackerState.ravagerTrackedObjects[part] =
							nextState
					end
				end
			end
		end
	end

	for part in pairs(perkTrackerState.ravagerTrackedObjects) do
		if not seen[part] or not part.Parent then
			perkTrackerState.ravagerTrackedObjects[part] = nil
		end
	end

	local latestByPart = setmetatable({}, {__mode = "k"})
	for index = #perkTrackerState.ravagerMotionEvents, 1, -1 do
		local event =
			perkTrackerState.ravagerMotionEvents[index]

		if now - event.Time > 0.5 then
			table.remove(
				perkTrackerState.ravagerMotionEvents,
				index
			)
		elseif not latestByPart[event.Part] then
			latestByPart[event.Part] = event
		end
	end

	local distinctParts = 0
	local distinctRoots = setmetatable({}, {__mode = "k"})
	local referenceAxis
	local alignedAxes = 0
	local totalAngular = 0
	local fastest = 0

	for _, event in pairs(latestByPart) do
		distinctParts = distinctParts + 1
		distinctRoots[event.RootObject] = true
		totalAngular =
			totalAngular + (event.AngularTotal or 0)
		fastest = math.max(fastest, event.Speed or 0)

		if event.Axis then
			if not referenceAxis then
				referenceAxis = event.Axis
				alignedAxes = alignedAxes + 1
			elseif referenceAxis:Dot(event.Axis) >= 0.65 then
				alignedAxes = alignedAxes + 1
			end
		end
	end

	local rootCount = 0
	for _ in pairs(distinctRoots) do
		rootCount = rootCount + 1
	end

	if distinctParts >= 3
		and rootCount >= 2
		and alignedAxes >= 3
		and totalAngular / math.max(distinctParts, 1) >= 15
		and fastest >= 6 then
		recordPerkDetection(
			"Ravager",
			tostring(distinctParts)
				.. " separate BaseParts sustained a near-circular orbit around the hunting ghost",
			99
		)
		updateGhostIdentification(ghost)
	end
end

local function updateObservablePerkTrackers(deltaTime)
	perkTrackerState.sampleAccumulator = perkTrackerState.sampleAccumulator + deltaTime
	perkTrackerState.slowScanAccumulator = perkTrackerState.slowScanAccumulator + deltaTime
	perkTrackerState.analysisAccumulator = perkTrackerState.analysisAccumulator + deltaTime
	if perkTrackerState.sampleAccumulator < 0.1 then
		return
	end
	perkTrackerState.sampleAccumulator = 0
	local ghost = getGhostModel()
	if ghost ~= perkTrackerState.ghost then
		resetPerkTrackerForGhost(ghost)
	end
	if not ghost then
		return
	end
	local now = os.clock()
	perkTrackerState.ensureCrossDemonTracker()
	perkTrackerState.updateCrossDemonTracker(now)
	local hunting = ghost:GetAttribute("Hunting") == true
	perkTrackerState.updateLeviathanLightTracker(ghost, hunting, 0.1, now)
	perkTrackerState.updateVexState(ghost)
	perkTrackerState.updateSaltTracker(0.1, ghost, hunting, now)
	perkTrackerState.updateHolyOilTracker(0.1, ghost, now)
	perkTrackerState.updateObjectTeleportTracker(0.1, now)
	perkTrackerState.updateRavagerTracker(0.1, ghost, now)
	handleHuntTransition(ghost, hunting, now)
	handleMultiplayerDeaths(ghost, hunting, now)
	if not perkTrackerState.entityTrackerInitialized then
		perkTrackerState.entityTrackerInitialized = true
		perkTrackerState.ensureObjectTeleportTracker()
	end
	if perkTrackerState.slowScanAccumulator >= 0.5 then
		perkTrackerState.slowScanAccumulator = 0
		if scanBansheeGlassBurst(now) then
			recordPerkDetection(
				"Banshee",
				"two or more new BrokenGlass models appeared within 2.5 seconds",
				PERK_CONFIDENCE.Banshee
			)
		end
		local pendingTeleport =
			perkTrackerState.pendingGhostTeleport
		if pendingTeleport and now >= pendingTeleport.ResolveAt then
			local currentRoom = ghost:GetAttribute("CurrentRoom")
			local roomChanged =
				pendingTeleport.FromRoom
				and currentRoom
				and currentRoom ~= pendingTeleport.FromRoom
			local roomsFolder = findRoomsFolder()
			local fromRoom =
				roomsFolder
				and findFavouriteRoom(
					roomsFolder,
					pendingTeleport.FromRoom
				)
			local toRoom =
				roomsFolder
				and findFavouriteRoom(
					roomsFolder,
					currentRoom
				)
			local fromInside = false
			if fromRoom then
				for _, boundingPart in ipairs(
					getRoomBoundingParts(fromRoom)
				) do
					if pointIsInsidePart(
						boundingPart,
						pendingTeleport.FromPosition
					) then
						fromInside = true
						break
					end
				end
			end
			local toInside =
				toRoom and instanceIsInsideRoom(ghost, toRoom)
				or false
			if roomChanged and fromInside and toInside then
				perkTrackerState.teleportResolvedGhost =
					"Ambiguous"
				recordPerkDetection(
					"Entity",
					"a verified room-to-room ghost teleport occurred",
					65
				)
				recordPerkDetection(
					"Skinwalker",
					"a verified room-to-room ghost teleport occurred",
					65
				)
			end
			perkTrackerState.pendingGhostTeleport = nil
		end
	end
	local position = ghost:GetPivot().Position
	local previousPosition = perkTrackerState.lastPosition
	local previousTime = perkTrackerState.lastSampleTime
	local currentObservedRoom = ghost:GetAttribute("CurrentRoom")
	local previousObservedRoom = perkTrackerState.lastObservedRoom
	perkTrackerState.lastPosition = position
	perkTrackerState.lastSampleTime = now
	perkTrackerState.lastObservedRoom = currentObservedRoom
	if not previousPosition or not previousTime then
		evaluatePendingKill(hunting, now)
		return
	end
	local elapsed = now - previousTime
	if elapsed <= 0 then
		return
	end
	local displacement = (position - previousPosition).Magnitude
	local measuredSpeed = displacement / elapsed
	if measuredSpeed > 45 then
		if now - perkTrackerState.teleportTrackingStartedAt >= 2
			and elapsed <= 0.25
			and measuredSpeed >= 120
			and displacement >= 30
			and previousObservedRoom
			and currentObservedRoom
			and currentObservedRoom ~= previousObservedRoom then
			perkTrackerState.pendingGhostTeleport = {
				Time = now,
				ResolveAt = now + 1.25,
				FromRoom = previousObservedRoom,
				FromPosition = previousPosition,
				ToPosition = position,
			}
			perkTrackerState.lastGhostTeleportAt = now
		end
		evaluatePendingKill(hunting, now)
		return
	end
	local character = player.Character
	local localLineOfSight = hunting and ghostHasLineOfSightToCharacter(ghost, character) or false
	local lineOfSight, lineOfSightTarget = false, nil
	if hunting then
		lineOfSight, lineOfSightTarget =
			ghostHasLineOfSightToAnyAlivePlayer(ghost)
		if localLineOfSight then
			perkTrackerState.sirenLosExposure =
				perkTrackerState.sirenLosExposure + elapsed
		end
	end
	local energy = getAverageTeamEnergy()
	local invisible = getGhostTransparencyState(ghost)
	local roomLit, roomName = getGhostRoomLightingState(ghost)
	local lightingKey = lightingContextKey(roomName, roomLit)
	if invisible ~= nil then
		if perkTrackerState.lastTransparencyState == nil then
			perkTrackerState.lastTransparencyState = invisible
		elseif invisible ~= perkTrackerState.lastTransparencyState then
			local previousTransition = perkTrackerState.lastTransparencyTransitionTime
			if not previousTransition or now - previousTransition > 0.03 then
				if previousTransition then
					table.insert(perkTrackerState.transparencyIntervals, {
						Time = now,
						Interval = now - previousTransition,
					})
				end
				table.insert(perkTrackerState.transparencyTransitions, now)
				perkTrackerState.lastTransparencyTransitionTime = now
			end
			perkTrackerState.lastTransparencyState = invisible
		end
	end
	local ghostHumanoid = ghost:FindFirstChildOfClass("Humanoid")
	local sample = {
		Time = now,
		Speed = measuredSpeed,
		GhostWalkSpeed = ghostHumanoid and ghostHumanoid.WalkSpeed or nil,
		Hunting = hunting,
		LineOfSight = lineOfSight,
		LocalLineOfSight = localLineOfSight,
		Energy = energy,
		Invisible = invisible,
		Lit = roomLit,
		Room = roomName,
		LightingKey = lightingKey,
		TargetPlayer = lineOfSightTarget,
	}
	appendRollingSample(perkTrackerState.motionSamples, sample, now, 12)
	if hunting then
		analyzeDullahan(now, lineOfSight)
	end
	if not hunting and typeof(sample.GhostWalkSpeed) == "number" and sample.GhostWalkSpeed > 0 then
		appendRollingSample(perkTrackerState.nonHuntWalkSpeedSamples, sample, now, 30)
	end
	if hunting and lineOfSight and measuredSpeed > 1 and lightingKey and lineOfSightTarget then
		if perkTrackerState.lastLosLightingKey ~= lightingKey
			or perkTrackerState.lastLosTarget ~= lineOfSightTarget then
			perkTrackerState.losSamples = {}
			perkTrackerState.energySamples = {}
			perkTrackerState.lastLosLightingKey = lightingKey
			perkTrackerState.lastLosTarget = lineOfSightTarget
		end
		appendRollingSample(perkTrackerState.losSamples, sample, now, 11)
		if energy and localLineOfSight then
			appendRollingSample(perkTrackerState.energySamples, sample, now, 10)
		end
	else
		perkTrackerState.losSamples = {}
		perkTrackerState.energySamples = {}
		perkTrackerState.lastLosLightingKey = nil
		perkTrackerState.lastLosTarget = nil
	end
	if hunting then
		if roomLit ~= nil
			and roomName
			and measuredSpeed > 3
			and measuredSpeed < 25
			and not lineOfSight
			and invisible ~= true then
			local previousLightState = perkTrackerState.umbraLastLightStateByRoom[roomName]
			if previousLightState ~= nil and previousLightState ~= roomLit then
				perkTrackerState.umbraLightTransitionsByRoom[roomName] =
					(perkTrackerState.umbraLightTransitionsByRoom[roomName] or 0) + 1
			end
			perkTrackerState.umbraLastLightStateByRoom[roomName] = roomLit
			table.insert(perkTrackerState.umbraSamples, {
				Time = now,
				Speed = measuredSpeed,
				Energy = energy,
				Lit = roomLit,
				Room = roomName,
			})
		end
	end
	evaluatePendingWispStart(ghost, now)
	if perkTrackerState.analysisAccumulator >= 0.2 then
		local analysisStep = perkTrackerState.analysisAccumulator
		perkTrackerState.analysisAccumulator = 0
		perkTrackerState.analyzeSpecter(ghost, hunting, measuredSpeed, now)
		if hunting then
			analyzeUmbra(now)
			analyzePhantom(now)
			analyzeOni(now)
		end
		analyzeWendigo(now)
		updateUmbraSoundSupport(ghost, hunting, measuredSpeed > 2, analysisStep, now)
		perkTrackerState.updateDybbukMaybe(ghost)
	end
	evaluatePendingKill(hunting, now)
end
observeWalkSpeedChange = function(humanoid, attemptedSpeed)
	if closed or not humanoid or humanoid.Health <= 0 then
		return
	end
	local ghost = getGhostModel()
	local character = player.Character
	if not ghost
		or ghost:GetAttribute("Hunting") ~= true
		or player:GetAttribute("Dead") == true
		or not ghostHasLineOfSightToCharacter(ghost, character) then
		return
	end
	local roomLit, roomName = getGhostRoomLightingState(ghost)
	local lightingKey = lightingContextKey(roomName, roomLit)
	if not lightingKey then
		return
	end
	local referenceSpeed = math.max(baseWalkSpeed, 1)
	if attemptedSpeed >= referenceSpeed - 0.25 then
		return
	end
	local now = os.clock()
	table.insert(perkTrackerState.sirenSlowEvents, {
		Time = now,
		Speed = attemptedSpeed,
		LightingKey = lightingKey,
		Room = roomName,
		Lit = roomLit,
	})
	while perkTrackerState.sirenSlowEvents[1]
		and now - perkTrackerState.sirenSlowEvents[1].Time > 4 do
		table.remove(perkTrackerState.sirenSlowEvents, 1)
	end
	local matchingEvents = 0
	for _, event in ipairs(perkTrackerState.sirenSlowEvents) do
		if event.LightingKey == lightingKey then
			matchingEvents = matchingEvents + 1
		end
	end
	if matchingEvents >= 2 then
		perkTrackerState.sirenSlowObservedThisHunt = true
		perkTrackerState.clearGhostRuleOut("Siren")
		recordPerkDetection(
			"Siren",
			"player WalkSpeed was reduced in line of sight while lighting stayed "
				.. lightingDescription(roomName, roomLit)
		)
	end
end
local function findBaseCampRoom()
	local roomsFolder = findRoomsFolder()
	if not roomsFolder then
		return nil
	end
	return roomsFolder:FindFirstChild("Base Camp")
		or roomsFolder:FindFirstChild("BaseCamp")
		or findFavouriteRoom(roomsFolder, "Base Camp")
end
local function teleportToRoomBoundingBoxCenter(room)
	local character = player.Character
	local root =
		character and character:FindFirstChild("HumanoidRootPart")
	local humanoid =
		character and character:FindFirstChildOfClass("Humanoid")

	if not room or not character or not root or not humanoid then
		return false, "room or character unavailable"
	end

	local boundingParts = getRoomBoundingParts(room)
	for _ = 1, 24 do
		if #boundingParts > 0 then
			break
		end
		task.wait(0.05)
		boundingParts = getRoomBoundingParts(room)
	end

	if #boundingParts == 0 then
		return false, "no BoundingBox BasePart was found"
	end

	local boundingPartSet = setmetatable({}, {__mode = "k"})
	local excludedInstances = {character}

	for _, boundingPart in ipairs(boundingParts) do
		boundingPartSet[boundingPart] = true
		table.insert(excludedInstances, boundingPart)

		local parent = boundingPart.Parent
		if parent and parent.Name == "BoundingBox" then
			table.insert(excludedInstances, parent)
		end
	end

	local ghost = getGhostModel()
	if ghost then
		table.insert(excludedInstances, ghost)
	end
	if ghostProxyModel then
		table.insert(excludedInstances, ghostProxyModel)
	end

	local function isHelperGeometry(part)
		if not part or not part:IsA("BasePart") then
			return true
		end
		if boundingPartSet[part] then
			return true
		end

		for _, boundingPart in ipairs(boundingParts) do
			local container = boundingPart.Parent
			if container
				and container.Name == "BoundingBox"
				and part:IsDescendantOf(container) then
				return true
			end
		end

		local name = string.lower(part.Name)
		for _, token in ipairs({
			"boundingbox",
			"hitbox",
			"trigger",
			"region",
			"volume",
			"detector",
			"boundary",
			"roomzone",
		}) do
			if string.find(name, token, 1, true) then
				return true
			end
		end

		return false
	end

	local standingOffset =
		humanoid.HipHeight + root.Size.Y * 0.5 + 0.16
	local horizontalInset =
		math.max(root.Size.X, root.Size.Z) * 0.65 + 0.55
	local bodyProbeSize = Vector3.new(
		math.max(root.Size.X + 0.8, 2.2),
		math.max(root.Size.Y + humanoid.HipHeight + 1.2, 4.2),
		math.max(root.Size.Z + 0.8, 2.2)
	)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = excludedInstances
	overlapParams.MaxParts = 80

	local function safelyInsideXZ(position, boundingPart)
		local localPosition =
			boundingPart.CFrame:PointToObjectSpace(position)
		local half = boundingPart.Size * 0.5

		return math.abs(localPosition.X)
			<= math.max(0, half.X - horizontalInset)
			and math.abs(localPosition.Z)
				<= math.max(0, half.Z - horizontalInset)
	end

	local function bodyAreaIsClear(candidate, supportingPart)
		local probe = CFrame.new(
			candidate + Vector3.new(0, bodyProbeSize.Y * 0.18, 0)
		)

		for _, part in ipairs(workspace:GetPartBoundsInBox(
			probe,
			bodyProbeSize,
			overlapParams
		)) do
			if part ~= supportingPart
				and part.CanCollide
				and not isHelperGeometry(part) then
				-- MeshPart, UnionOperation, Part, and other collidable BasePart
				-- subclasses are all rejected here.
				return false
			end
		end

		return true
	end

	local function horizontalClearance(candidate, supportingPart)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.IgnoreWater = true

		local excludes = table.clone(excludedInstances)
		table.insert(excludes, supportingPart)
		raycastParams.FilterDescendantsInstances = excludes

		local origin =
			candidate + Vector3.new(0, root.Size.Y * 0.45, 0)
		local minimum = 10
		local directions = {
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
			Vector3.new(1, 0, 1).Unit,
			Vector3.new(1, 0, -1).Unit,
			Vector3.new(-1, 0, 1).Unit,
			Vector3.new(-1, 0, -1).Unit,
		}

		for _, direction in ipairs(directions) do
			local result =
				workspace:Raycast(origin, direction * 10, raycastParams)
			if result
				and result.Instance
				and result.Instance:IsA("BasePart")
				and result.Instance.CanCollide
				and not isHelperGeometry(result.Instance) then
				minimum = math.min(minimum, result.Distance)
			end
		end

		return minimum
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludedInstances
	raycastParams.IgnoreWater = true

	local candidates = {}

	-- Exact 6 × 3 cell-centre grid.
	for _, boundingPart in ipairs(boundingParts) do
		local half = boundingPart.Size * 0.5
		local usableX =
			math.max(0, boundingPart.Size.X - horizontalInset * 2)
		local usableZ =
			math.max(0, boundingPart.Size.Z - horizontalInset * 2)

		if usableX > 0 and usableZ > 0 then
			for xIndex = 1, 6 do
				local xRatio = (xIndex - 0.5) / 6 - 0.5
				local localX = xRatio * usableX

				for zIndex = 1, 3 do
					local zRatio = (zIndex - 0.5) / 3 - 0.5
					local localZ = zRatio * usableZ
					local origin =
						boundingPart.CFrame:PointToWorldSpace(
							Vector3.new(localX, half.Y + 24, localZ)
						)
					local result = workspace:Raycast(
						origin,
						Vector3.new(0, -(boundingPart.Size.Y + 72), 0),
						raycastParams
					)

					if result
						and result.Instance
						and result.Instance:IsA("BasePart")
						and result.Instance.CanCollide
						and result.Instance.Transparency < 1
						and result.Normal.Y >= 0.62
						and not isHelperGeometry(result.Instance) then
						local localFloor =
							boundingPart.CFrame:PointToObjectSpace(
								result.Position
							)
						local bottomDistance =
							localFloor.Y + half.Y
						local candidate =
							result.Position
							+ Vector3.new(0, standingOffset, 0)

						if bottomDistance >= -1.5
							and bottomDistance <= boundingPart.Size.Y
							and safelyInsideXZ(candidate, boundingPart)
							and bodyAreaIsClear(
								candidate,
								result.Instance
							) then
							table.insert(candidates, {
								Position = candidate,
								Surface = result.Instance,
								BoundingPart = boundingPart,
								BottomDistance = bottomDistance,
								Clearance =
									horizontalClearance(
										candidate,
										result.Instance
									),
							})
						end
					end
				end
			end
		end
	end

	if #candidates == 0 then
		return false,
			"no safe floor point was found on the 6x3 room grid"
	end

	table.sort(candidates, function(left, right)
		local bottomDifference =
			math.abs(left.BottomDistance - right.BottomDistance)

		if bottomDifference > 0.25 then
			return left.BottomDistance < right.BottomDistance
		end

		return left.Clearance > right.Clearance
	end)

	local selected = candidates[1]
	if not selected
		or not safelyInsideXZ(
			selected.Position,
			selected.BoundingPart
		) then
		return false, "the selected point was outside the safe room inset"
	end

	local look = Vector3.new(
		root.CFrame.LookVector.X,
		0,
		root.CFrame.LookVector.Z
	)
	if look.Magnitude < 0.05 then
		look = Vector3.new(
			selected.BoundingPart.CFrame.LookVector.X,
			0,
			selected.BoundingPart.CFrame.LookVector.Z
		)
	end
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit

	local destination = CFrame.lookAt(
		selected.Position,
		selected.Position + look
	)

	local originalAnchored = root.Anchored
	local originalAutoRotate = humanoid.AutoRotate
	local originalPlatformStand = humanoid.PlatformStand
	local disabledStates = {}

	for _, state in ipairs({
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Freefall,
	}) do
		local ok, enabled = pcall(function()
			return humanoid:GetStateEnabled(state)
		end)
		if ok then
			disabledStates[state] = enabled
			pcall(function()
				humanoid:SetStateEnabled(state, false)
			end)
		end
	end

	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	for _ = 1, 6 do
		character:PivotTo(destination)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		Services.RunService.Heartbeat:Wait()
	end

	if not bodyAreaIsClear(
		root.Position,
		selected.Surface
	) or not safelyInsideXZ(
		root.Position,
		selected.BoundingPart
	) then
		root.Anchored = originalAnchored
		humanoid.PlatformStand = originalPlatformStand
		humanoid.AutoRotate = originalAutoRotate

		for state, enabled in pairs(disabledStates) do
			pcall(function()
				humanoid:SetStateEnabled(state, enabled)
			end)
		end

		return false,
			"the destination became obstructed during teleport settling"
	end

	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = originalAnchored
	humanoid.PlatformStand = originalPlatformStand
	humanoid.AutoRotate = originalAutoRotate

	for _ = 1, 3 do
		Services.RunService.Heartbeat:Wait()
		if root.Parent then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end

	task.delay(0.65, function()
		if humanoid.Parent then
			for state, enabled in pairs(disabledStates) do
				pcall(function()
					humanoid:SetStateEnabled(state, enabled)
				end)
			end
		end
	end)

	return true, nil
end

local function teleportToBaseCamp()
	local room = findBaseCampRoom()
	if not room then
		return false, "Base Camp room was not found"
	end
	return teleportToRoomBoundingBoxCenter(room)
end
local function teleportToFavouriteRoom()
	local ghost = getGhostModel()
	local roomsFolder = findRoomsFolder()
	local roomName = ghost and ghost:GetAttribute("FavoriteRoom") or nil
	local room = findFavouriteRoom(roomsFolder, roomName)
	if not room then
		return false, "Favourite room was not found: " .. tostring(roomName)
	end
	return teleportToRoomBoundingBoxCenter(room)
end
local function placeItemsInFavouriteRoom()
	if roomItemPlacementState.busy or closed then
		return
	end
	roomItemPlacementState.busy = true
	roomItemPlacementState.generation =
		roomItemPlacementState.generation + 1
	local operationGeneration =
		roomItemPlacementState.generation
	placeRoomItemsButton.Text = COPY.Actions.PlacingRoomItems
	placeRoomItemsButton.BackgroundColor3 = COLORS.accentDark
	roomItemPlacementState.thread = task.spawn(function()
		local failedItems = {}
		local failureSet = {}
		local function recordFailure(message)
			if not failureSet[message] then
				failureSet[message] = true
				table.insert(failedItems, message)
			end
		end
		local function operationIsActive()
			return not closed
				and roomItemPlacementState.busy
				and roomItemPlacementState.generation
					== operationGeneration
		end
		local function assertOperationActive()
			if not operationIsActive() then
				error("Room item setup cancelled", 0)
			end
		end
		local function guardedWait(seconds)
			local deadline = os.clock() + seconds
			repeat
				assertOperationActive()
				task.wait(
					math.min(
						0.05,
						math.max(0, deadline - os.clock())
					)
				)
			until os.clock() >= deadline
		end
		local function waitForNoHunt(returnToFavouriteRoom)
			local paused = false
			while operationIsActive() do
				local currentGhost = getGhostModel()
				if not currentGhost
					or currentGhost:GetAttribute("Hunting")
						~= true then
					break
				end
				if not paused then
					paused = true
					placeRoomItemsButton.Text = COPY.Actions.WaitingForHunt
					teleportToBaseCamp()
				end
				guardedWait(0.15)
			end
			assertOperationActive()
			if paused then
				guardedWait(0.8)
			end
			placeRoomItemsButton.Text = COPY.Actions.PlacingRoomItems
			if returnToFavouriteRoom then
				local currentGhost = getGhostModel()
				local currentRooms = findRoomsFolder()
				local currentFavourite = findFavouriteRoom(
					currentRooms,
					currentGhost
						and currentGhost:GetAttribute(
							"FavoriteRoom"
						)
						or nil
				)
				local character = player.Character
				local alreadyInRoom = currentFavourite
					and character
					and instanceIsInsideRoom(
						character,
						currentFavourite
					)
				if not alreadyInRoom then
					local teleported, reason =
						teleportToFavouriteRoom()
					if not teleported then
						error(
							"Favourite-room teleport failed: "
								.. tostring(
									reason or "unknown reason"
								),
							0
						)
					end
					guardedWait(0.15)
				end
			end
			return paused
		end
		local events =
			Services.ReplicatedStorage:FindFirstChild("Events")
		if not events then
			error("ReplicatedStorage.Events was not found", 0)
		end
		local function getRemote(name)
			local remote = events:FindFirstChild(name)
			if not remote or not remote:IsA("RemoteEvent") then
				error(name .. " RemoteEvent was not found", 0)
			end
			return remote
		end
		local requestItemEquip = getRemote("RequestItemEquip")
		local requestItemPickup = getRemote("RequestItemPickup")
		local requestItemDrop = getRemote("RequestItemDrop")
		local toggleItemState = getRemote("ToggleItemState")
		local function fireRemote(remote, ...)
			assertOperationActive()
			local ok, err = pcall(remote.FireServer, remote, ...)
			if not ok then
				error("Remote call failed: " .. tostring(err), 0)
			end
		end
		local playerGui = player:FindFirstChild("PlayerGui")
		local hotbar =
			playerGui and playerGui:FindFirstChild("Hotbar")
		local hotbarSlots =
			hotbar and hotbar:FindFirstChild("Slots")
		if not hotbarSlots then
			error("Hotbar.Slots was not found", 0)
		end
		local function normalizeItemName(value)
			local normalized =
				string.lower(tostring(value or ""))
					:match("^%s*(.-)%s*$")
					:gsub("%s+", " ")
			if normalized == "holyoil"
				or normalized == "hoil oil" then
				return "holy oil"
			end
			return normalized
		end
		local function sameItemName(left, right)
			return normalizeItemName(left)
				== normalizeItemName(right)
		end
		local inventorySlotCount = 3
		local function inventorySlotKey(slotNumber)
			return "InvSlot" .. tostring(slotNumber)
		end
		local function inventorySlotValue(slotNumber)
			return player:GetAttribute(
				inventorySlotKey(slotNumber)
			)
		end
		local function valueIsOccupied(value)
			return value ~= nil
				and value ~= false
				and tostring(value) ~= ""
		end
		local function storedItemName(object)
			if not object then
				return nil
			end
			local value = object:GetAttribute("ItemName")
			if typeof(value) == "string" and value ~= "" then
				return value
			end
			for _, descendant in ipairs(object:GetDescendants()) do
				value = descendant:GetAttribute("ItemName")
				if typeof(value) == "string" and value ~= "" then
					return value
				end
			end
			return nil
		end
		local function scanStoredInventory(itemName)
			local requested =
				itemName and normalizeItemName(itemName) or nil
			local matchingItem
			local matchingCount = 0
			local totalCount = 0
			local function scanContainer(container)
				if not container then
					return
				end
				for _, child in ipairs(container:GetChildren()) do
					local name = storedItemName(child)
					if name then
						totalCount = totalCount + 1
						if requested
							and normalizeItemName(name) == requested
							and not (
								requested
									== normalizeItemName("Cross")
								and child:GetAttribute("Burned")
									== true
							) then
							matchingCount = matchingCount + 1
							matchingItem = matchingItem or child
						end
					end
				end
			end
			scanContainer(player:FindFirstChild("ToolsHolder"))
			scanContainer(player.Character)
			return matchingItem, matchingCount, math.min(
				totalCount,
				inventorySlotCount
			)
		end
		local function objectMatchesSlotValue(object, slotValue)
			if not object or not valueIsOccupied(slotValue) then
				return false
			end
			local target = tostring(slotValue)
			local current = object
			while current
				and current ~= player
				and current ~= workspace do
				if tostring(current.Name) == target then
					return true
				end
				for _, value in pairs(current:GetAttributes()) do
					if (
						typeof(value) == "string"
						or typeof(value) == "number"
					)
						and tostring(value) == target then
						return true
					end
				end
				current = current.Parent
			end
			for _, descendant in ipairs(object:GetDescendants()) do
				if tostring(descendant.Name) == target then
					return true
				end
				for _, value in pairs(
					descendant:GetAttributes()
				) do
					if (
						typeof(value) == "string"
						or typeof(value) == "number"
					)
						and tostring(value) == target then
						return true
					end
				end
			end
			return false
		end
		local function storedInventorySlot(itemName)
			local storedItem = scanStoredInventory(itemName)
			if not storedItem then
				return nil
			end
			local equippedObject =
				player:GetAttribute("EquippedObject")
			if player.Character
				and storedItem:IsDescendantOf(player.Character)
				and valueIsOccupied(equippedObject) then
				for slotNumber = 1, inventorySlotCount do
					if inventorySlotValue(slotNumber)
						== equippedObject then
						return slotNumber
					end
				end
			end
			for slotNumber = 1, inventorySlotCount do
				if objectMatchesSlotValue(
					storedItem,
					inventorySlotValue(slotNumber)
				) then
					return slotNumber
				end
			end
			local current = storedItem
			while current
				and current ~= player
				and current ~= workspace do
				for _, attributeName in ipairs({
					"InvSlot",
					"InventorySlot",
					"Slot",
					"SlotNumber",
				}) do
					local value =
						current:GetAttribute(attributeName)
					local number = tonumber(
						tostring(value or ""):match("%d+")
					)
					if number
						and number >= 1
						and number <= inventorySlotCount then
						return number
					end
				end
				current = current.Parent
			end
			return nil
		end
		local function slotLabel(slot)
			local label = slot and slot:FindFirstChild("ItemName")
			return label
				and label:IsA("TextLabel")
				and label.Text
				or nil
		end
		local function hotbarSlotName(slotNumber)
			return slotLabel(
				hotbarSlots:FindFirstChild(
					"InvSlot" .. tostring(slotNumber)
				)
			)
		end
		local function countHotbarItem(itemName)
			local count = 0
			for slotNumber = 1, inventorySlotCount do
				if sameItemName(
					hotbarSlotName(slotNumber),
					itemName
				) then
					count = count + 1
				end
			end
			return count
		end
		local function findHotbarSlot(itemName)
			for slotNumber = 1, inventorySlotCount do
				if sameItemName(
					hotbarSlotName(slotNumber),
					itemName
				) then
					return slotNumber
				end
			end
			return nil
		end
		local function findInventorySlot(itemName)
			return findHotbarSlot(itemName)
				or storedInventorySlot(itemName)
		end
		local function countInventoryItem(itemName)
			local _, storedCount =
				scanStoredInventory(itemName)
			return math.max(
				countHotbarItem(itemName),
				storedCount
			)
		end
		local function inventoryHasItem(itemName)
			return countInventoryItem(itemName) > 0
		end
		local function inventorySlotName(slotNumber)
			local hotbarName = hotbarSlotName(slotNumber)
			if hotbarName and hotbarName ~= "" then
				return hotbarName
			end
			for _, container in ipairs({
				player:FindFirstChild("ToolsHolder"),
				player.Character,
			}) do
				if container then
					for _, child in ipairs(container:GetChildren()) do
						local name = storedItemName(child)
						if name
							and objectMatchesSlotValue(
								child,
								inventorySlotValue(slotNumber)
							) then
							return name
						end
					end
				end
			end
			return nil
		end
		local function inventorySnapshot()
			local slots = {}
			local occupiedCount = 0
			local freeSlot
			local values = {}
			for slotNumber = 1, inventorySlotCount do
				local value = inventorySlotValue(slotNumber)
				values[slotNumber] = value
				local occupied =
					valueIsOccupied(value)
					or (
						hotbarSlotName(slotNumber) ~= nil
						and hotbarSlotName(slotNumber) ~= ""
					)
				if occupied then
					slots[slotNumber] =
						inventorySlotName(slotNumber)
					occupiedCount = occupiedCount + 1
				elseif not freeSlot then
					freeSlot = slotNumber
				end
			end
			return slots, occupiedCount, freeSlot, values
		end
		local function waitForHotbarSlot(itemName, timeout)
			local deadline = os.clock() + (timeout or 1.5)
			repeat
				assertOperationActive()
				local slotNumber = findInventorySlot(itemName)
				if slotNumber then
					return slotNumber
				end
				guardedWait(0.05)
			until os.clock() >= deadline
			return nil
		end
		local function findItem(itemName)
			local itemFolder = workspace:FindFirstChild("Items")
			if not itemFolder then
				return false, nil
			end
			for _, child in ipairs(itemFolder:GetChildren()) do
				local candidateName =
					child:GetAttribute("ItemName")
					or child.Name
				if (
					child:IsA("Model")
					or child:IsA("BasePart")
				)
					and sameItemName(candidateName, itemName)
					and not (
						sameItemName(itemName, "Cross")
						and child:GetAttribute("Burned") == true
					) then
					return true, child
				end
			end
			return false, nil
		end
		local function moveNearWorldItem(model)
			local character = player.Character
			local root = character
				and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character
				and character:FindFirstChildOfClass("Humanoid")
			if not model
				or not model.Parent
				or not character
				or not root
				or not humanoid then
				return false
			end
			local originalAnchored = root.Anchored
			local originalAutoRotate = humanoid.AutoRotate
			local originalPlatformStand = humanoid.PlatformStand
			humanoid.Sit = false
			humanoid.PlatformStand = false
			humanoid.AutoRotate = false
			root.Anchored = true
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			local itemCFrame
			if model:IsA("BasePart") then
				itemCFrame = model.CFrame
			else
				local ok, pivot = pcall(function()
					return model:GetPivot()
				end)
				itemCFrame = ok and pivot or nil
			end
			if not itemCFrame then
				root.Anchored = originalAnchored
				humanoid.PlatformStand = originalPlatformStand
				humanoid.AutoRotate = originalAutoRotate
				return false
			end
			character:PivotTo(
				itemCFrame * CFrame.new(0, 3.5, 0)
			)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			Services.RunService.Heartbeat:Wait()
			root.Anchored = originalAnchored
			humanoid.PlatformStand = originalPlatformStand
			humanoid.AutoRotate = originalAutoRotate
			return true
		end
		local function equipItem(slotNumber, returnToFavouriteRoom)
			waitForNoHunt(returnToFavouriteRoom == true)
			if not slotNumber
				or slotNumber < 1
				or slotNumber > inventorySlotCount
				or (
					not valueIsOccupied(
						inventorySlotValue(slotNumber)
					)
					and not inventorySlotName(slotNumber)
				) then
				return false
			end
			fireRemote(
				requestItemEquip,
				inventorySlotKey(slotNumber)
			)
			guardedWait(0.18)
			return true
		end
		local function confirmedDrop(
			slotNumber,
			itemName,
			returnToFavouriteRoom
		)
			local beforeCount = countInventoryItem(itemName)
			local beforeSlotValue =
				inventorySlotValue(slotNumber)
			if beforeCount == 0 then
				return true
			end
			for attempt = 1, 2 do
				local currentSlot = findInventorySlot(itemName)
				if not currentSlot then
					return true
				end
				slotNumber = currentSlot or slotNumber
				if not equipItem(
					slotNumber,
					returnToFavouriteRoom
				) then
					guardedWait(0.15)
					continue
				end
				fireRemote(
					requestItemDrop,
					inventorySlotKey(slotNumber)
				)
				local deadline = os.clock() + 1.65
				repeat
					assertOperationActive()
					if countInventoryItem(itemName) < beforeCount
						or not inventoryHasItem(itemName)
						or inventorySlotValue(slotNumber)
							~= beforeSlotValue then
						return true
					end
					guardedWait(0.05)
				until os.clock() >= deadline
				local _, occupiedCount = inventorySnapshot()
				if countInventoryItem(itemName) < beforeCount then
					return true
				end
				if occupiedCount < inventorySlotCount and not inventoryHasItem(itemName) then
					return true
				end
				guardedWait(0.2)
			end
			return countInventoryItem(itemName) < beforeCount
		end
		local corePlacementNames = {
			[normalizeItemName("Cross")] = true,
			[normalizeItemName("Spirit Book")] = true,
			[normalizeItemName("Laser Projector")] = true,
			[normalizeItemName("Flower Pot")] = true,
			[normalizeItemName("EMF Reader")] = true,
			[normalizeItemName("Blacklight")] = true,
			[normalizeItemName("Video Camera")] = true,
		}
		local finalRetainedNames = {
			[normalizeItemName("Spirit Box")] = true,
			[normalizeItemName("Salt Canister")] = true,
			[normalizeItemName("Holy Oil")] = true,
		}
		local coreOrder = {
			"Cross",
			"Spirit Book",
			"Laser Projector",
			"Flower Pot",
			"EMF Reader",
			"Blacklight",
			"Video Camera",
		}
		local optionalCoreNames = {
			[normalizeItemName("Cross")] = true,
			[normalizeItemName("EMF Reader")] = true,
			[normalizeItemName("Blacklight")] = true,
			[normalizeItemName("Video Camera")] = true,
		}
		local finalOrder = {
			{Name = "Spirit Box", Optional = false},
			{Name = "Salt Canister", Optional = true},
			{Name = "Holy Oil", Optional = true},
		}

		local function ensureInventorySpace(
			protectedNames,
			returnToFavouriteRoom
		)
			local _, occupiedCount = inventorySnapshot()
			if occupiedCount < inventorySlotCount then
				return true
			end

			for slotNumber = 1, inventorySlotCount do
				local slotName = inventorySlotName(slotNumber)
				if slotName
					and slotName ~= ""
					and not protectedNames[
						normalizeItemName(slotName)
					] then
					if confirmedDrop(
						slotNumber,
						slotName,
						returnToFavouriteRoom == true
					) then
						local _, afterCount = inventorySnapshot()
						if afterCount < inventorySlotCount then
							return true
						end
					end
				end
			end

			local _, finalCount = inventorySnapshot()
			return finalCount < inventorySlotCount
		end

		local function waitForPickupConfirmation(
			itemName,
			model,
			beforeItemCount,
			beforeOccupiedCount,
			beforeSlotValues,
			timeout
		)
			local deadline = os.clock() + timeout
			repeat
				assertOperationActive()

				for slotNumber = 1, inventorySlotCount do
					local currentValue =
						inventorySlotValue(slotNumber)
					if valueIsOccupied(currentValue)
						and currentValue
							~= beforeSlotValues[slotNumber] then
						return slotNumber
					end
				end

				local exactSlot = findInventorySlot(itemName)
				if exactSlot
					and countInventoryItem(itemName)
						> beforeItemCount then
					return exactSlot
				end

				local storedItem = scanStoredInventory(itemName)
				local _, occupiedCount = inventorySnapshot()
				if storedItem
					and countInventoryItem(itemName)
						> beforeItemCount then
					local delayedSlot =
						findInventorySlot(itemName)
					if delayedSlot then
						return delayedSlot
					end
				end

				if model
					and model.Parent
						~= workspace:FindFirstChild("Items")
					and occupiedCount > beforeOccupiedCount then
					local delayedSlot =
						findInventorySlot(itemName)
					if delayedSlot then
						return delayedSlot
					end
				end

				guardedWait(0.05)
			until os.clock() >= deadline

			return nil
		end

		local function attemptPickupFromCurrentPosition(
			itemName,
			model,
			timeout
		)
			local beforeItemCount = countInventoryItem(itemName)
			local _, beforeOccupiedCount, _, beforeSlotValues =
				inventorySnapshot()
			fireRemote(requestItemPickup, model)
			return waitForPickupConfirmation(
				itemName,
				model,
				beforeItemCount,
				beforeOccupiedCount,
				beforeSlotValues,
				timeout
			)
		end

		local function pickupNamedItem(
			itemName,
			protectedNames,
			optional,
			returnToFavouriteRoom
		)
			local storedItem = scanStoredInventory(itemName)
			local existingSlot = findInventorySlot(itemName)
			if storedItem or existingSlot then
				existingSlot = existingSlot
					or waitForHotbarSlot(itemName, 2)
				return true, storedItem, existingSlot
			end

			local found, model = findItem(itemName)
			if not found or not model then
				storedItem = scanStoredInventory(itemName)
				if storedItem or inventoryHasItem(itemName) then
					return true,
						storedItem,
						waitForHotbarSlot(itemName, 2)
				end
				if not optional then
					recordFailure(
						itemName
							.. " was not found in workspace.Items or ToolsHolder"
					)
				end
				return false, nil, nil
			end

			waitForNoHunt(returnToFavouriteRoom == true)

			for nearAttempt = 1, 2 do
				if not ensureInventorySpace(
					protectedNames,
					returnToFavouriteRoom == true
				) then
					recordFailure(
						itemName
							.. " pickup stopped: inventory full"
					)
					return false, model, nil
				end

				local stillFound, refreshedModel =
					findItem(itemName)
				if stillFound and refreshedModel then
					model = refreshedModel
				elseif inventoryHasItem(itemName) then
					return true, model, findInventorySlot(itemName)
				else
					local delayedSlot =
						waitForHotbarSlot(itemName, 0.65)
					if delayedSlot then
						return true, model, delayedSlot
					end
					break
				end

				if not model
					or not model.Parent
					or not moveNearWorldItem(model) then
					break
				end

				guardedWait(0.25)
				local _, occupiedBeforeFire =
					inventorySnapshot()

				if occupiedBeforeFire >= inventorySlotCount
					and not inventoryHasItem(itemName) then
					waitForNoHunt(returnToFavouriteRoom == true)
					if not ensureInventorySpace(
						protectedNames,
						returnToFavouriteRoom == true
					) then
						recordFailure(
							itemName
								.. " pickup cancelled: inventory remained full"
						)
						return false, model, nil
					end
					guardedWait(0.15)
					continue
				end

				local slotNumber =
					attemptPickupFromCurrentPosition(
						itemName,
						model,
						nearAttempt == 1 and 2.25 or 1.65
					)

				waitForNoHunt(returnToFavouriteRoom == true)

				if slotNumber then
					local confirmedSlot =
						waitForHotbarSlot(itemName, 0.5)
						or slotNumber
					return true, model, confirmedSlot
				end

				local _, occupiedAfterFire =
					inventorySnapshot()
				if inventoryHasItem(itemName) then
					return true, model, findInventorySlot(itemName)
				end

				if occupiedAfterFire >= inventorySlotCount
					and not ensureInventorySpace(
						protectedNames,
						returnToFavouriteRoom == true
					) then
					recordFailure(
						itemName
							.. " retry stopped: inventory full after pickup response"
					)
					return false, model, nil
				end

				guardedWait(0.2)
			end

			waitForNoHunt(returnToFavouriteRoom == true)
			if not ensureInventorySpace(
				protectedNames,
				returnToFavouriteRoom == true
			) then
				recordFailure(
					itemName
						.. " final retry skipped: inventory full"
				)
				return false, model, nil
			end

			local finalFound, finalModel = findItem(itemName)
			if finalFound and finalModel then
				model = finalModel
				local slotNumber =
					attemptPickupFromCurrentPosition(
						itemName,
						model,
						1.25
					)
				if slotNumber then
					return true, model, slotNumber
				end
			end

			local delayedSlot = waitForHotbarSlot(itemName, 0.8)
			if delayedSlot then
				return true, model, delayedSlot
			end

			recordFailure(itemName .. " pickup was not confirmed")
			return false, model, nil
		end

		local function toggleEquippedItem(itemName)
			local character = player.Character
			if not character then
				return false
			end

			for _, child in ipairs(character:GetChildren()) do
				if child:IsA("Model")
					and sameItemName(
						child:GetAttribute("ItemName"),
						itemName
					) then
					if child:GetAttribute("Enabled") ~= true then
						perkTrackerState.suppressItemDisableUntil =
							os.clock() + 1.25
						fireRemote(toggleItemState, child)
					end
					return true
				end
			end

			return false
		end

		local function dropInventoryExcept(
			protectedNames,
			returnToFavouriteRoom
		)
			for _ = 1, 6 do
				local _, occupiedCount = inventorySnapshot()
				if occupiedCount == 0 then
					return true
				end

				local foundUnprotected = false
				local droppedSomething = false

				for slotNumber = 1, inventorySlotCount do
					local slotName =
						inventorySlotName(slotNumber)
					if slotName and slotName ~= "" then
						if not protectedNames[
							normalizeItemName(slotName)
						] then
							foundUnprotected = true
							if confirmedDrop(
								slotNumber,
								slotName,
								returnToFavouriteRoom == true
							) then
								droppedSomething = true
								guardedWait(0.12)
							else
								recordFailure(
									slotName
										.. " could not be cleared from inventory"
								)
							end
						end
					elseif valueIsOccupied(
						inventorySlotValue(slotNumber)
					) then
						recordFailure(
							inventorySlotKey(slotNumber)
								.. " item name could not be resolved"
						)
					end
				end

				if not foundUnprotected then
					return true
				end
				if not droppedSomething then
					return false
				end
			end

			return false
		end

		local function shuffledCopy(list)
			local copy = {}
			for index, value in ipairs(list) do
				copy[index] = value
			end

			for index = #copy, 2, -1 do
				local swapIndex = math.random(index)
				copy[index], copy[swapIndex] =
					copy[swapIndex], copy[index]
			end

			return copy
		end

		local function shouldActivate(itemName)
			return sameItemName(itemName, "Laser Projector")
				or sameItemName(itemName, "Blacklight")
				or sameItemName(itemName, "EMF Reader")
		end

		local function activateBatch(batch)
			for _, itemName in ipairs(batch) do
				if shouldActivate(itemName)
					and inventoryHasItem(itemName) then
					local slotNumber =
						waitForHotbarSlot(itemName, 2)
						or findInventorySlot(itemName)
					if slotNumber
						and equipItem(slotNumber, true) then
						guardedWait(0.2)
						if not toggleEquippedItem(itemName) then
							recordFailure(
								itemName .. " could not be toggled"
							)
						end
						guardedWait(0.25)
					end
				end
			end
		end

		local function dropBatch(batch)
			waitForNoHunt(true)
			activateBatch(batch)

			for _, itemName in ipairs(batch) do
				if inventoryHasItem(itemName) then
					local slotNumber =
						waitForHotbarSlot(itemName, 2.5)
						or findInventorySlot(itemName)
					if not slotNumber
						or not confirmedDrop(
							slotNumber,
							itemName,
							true
						) then
						recordFailure(
							itemName
								.. " drop was not confirmed"
						)
					end
					guardedWait(0.15)
				end
			end
		end

		local ok, err = xpcall(function()
			waitForNoHunt(false)
			local baseTeleported, baseReason =
				teleportToBaseCamp()
			if not baseTeleported then
				error(
					"Base Camp teleport failed: "
						.. tostring(baseReason or "unknown reason"),
					0
				)
			end

			guardedWait(0.2)

			-- Everything already held when the button is pressed is cleared in
			-- Base Camp, including room-placement items.
			dropInventoryExcept({}, false)

			local remaining = shuffledCopy(coreOrder)

			while #remaining > 0 do
				local batch = {}
				local randomized = shuffledCopy(remaining)
				remaining = {}

				for _, itemName in ipairs(randomized) do
					if #batch < inventorySlotCount then
						local picked = pickupNamedItem(
							itemName,
							corePlacementNames,
							optionalCoreNames[
								normalizeItemName(itemName)
							] == true,
							false
						)
						if picked then
							table.insert(batch, itemName)
						end
					else
						table.insert(remaining, itemName)
					end
				end

				if #batch == 0 then
					break
				end

				dropBatch(batch)
			end

			-- Ensure the final three pickups are exactly the retained equipment.
			waitForNoHunt(false)
			local returnedToBase, returnReason =
				teleportToBaseCamp()
			if not returnedToBase then
				error(
					"Base Camp return failed: "
						.. tostring(returnReason or "unknown reason"),
					0
				)
			end
			guardedWait(0.2)
			dropInventoryExcept({}, false)

			for _, entry in ipairs(shuffledCopy(finalOrder)) do
				local picked = pickupNamedItem(
					entry.Name,
					finalRetainedNames,
					entry.Optional,
					false
				)
				if picked
					and not inventoryHasItem(entry.Name) then
					recordFailure(
						entry.Name
							.. " retention was not confirmed"
					)
				end
				guardedWait(0.15)
			end
		end, debug.traceback)

		if operationIsActive() then
			teleportToBaseCamp()
			roomItemPlacementState.busy = false
			roomItemPlacementState.thread = nil
			placeRoomItemsButton.Text = COPY.Controls.PlaceRoomItems
			placeRoomItemsButton.BackgroundColor3 =
				COLORS.cardHover
			local message
			if not ok then
				message = "Setup failed: "
					.. tostring(err):match("^[^\n]+")
			elseif #failedItems > 0 then
				message = "Returned to Base Camp. Issues: "
					.. table.concat(failedItems, ", ")
			else
				message = "Room items were randomized and placed in three-item batches; the final pickups were Spirit Box, Salt Canister, and Holy Oil when available."
			end
			pcall(function()
				game:GetService("StarterGui"):SetCore(
					"SendNotification",
					{
						Title = "Room item setup",
						Text = message,
						Duration = 6,
					}
				)
			end)
		elseif roomItemPlacementState.generation
			== operationGeneration then
			roomItemPlacementState.busy = false
			roomItemPlacementState.thread = nil
		end
	end)
end
local function teleportOutside()
	return teleportToBaseCamp()
end
local function escapeCurrentHunt()
	local ghost = getGhostModel()
	if not ghost then
		return
	end
	local hunting = ghost:GetAttribute("Hunting") == true
	if not hunting then
		huntEscapeTriggered = false
		return
	end
	if huntEscapeEnabled and not huntEscapeTriggered then
		if teleportOutside() then
			huntEscapeTriggered = true
		end
	end
end
local function scanDeepEvidence()
	local needPrint = not evidenceFound.Print
	local needOrb = not perkTrackerState.orbObserved

	if needPrint or needOrb then
		for _, object in ipairs(workspace:GetDescendants()) do
			if needPrint
				and object:IsA("BasePart")
				and (
					object.Name == "Handprint1"
					or object.Name == "Handprint2"
					or object.Name == "Footprint"
					or object.Name == "Footprint1"
				) then
				local saltPiles =
					workspace:FindFirstChild("SaltPiles")
				if not saltPiles
					or not object:IsDescendantOf(saltPiles) then
					evidenceFound.Print = true
					needPrint = false
				end
			elseif needOrb
				and object:IsA("BasePart")
				and object.Name == "GhostOrb" then
				perkTrackerState.orbObserved = true
				needOrb = false
			end

			if not needPrint and not needOrb then
				break
			end
		end
	end

	if highestEMF < 5 then
		local checkedReaders =
			setmetatable({}, {__mode = "k"})

		for _, container in ipairs({
			workspace:FindFirstChild("Items"),
			player:FindFirstChild("ToolsHolder"),
			player.Character,
		}) do
			if container then
				for _, candidate in ipairs(
					container:GetDescendants()
				) do
					if candidate:IsA("Model")
						and not checkedReaders[candidate]
						and candidate:GetAttribute("ItemName")
							== "EMF Reader" then
						checkedReaders[candidate] = true

						local readingObject =
							candidate:FindFirstChild(
								"ReadingLevel",
								true
							)
						local level
						if readingObject
							and (
								readingObject:IsA("NumberValue")
								or readingObject:IsA("IntValue")
							) then
							level = readingObject.Value
						else
							level =
								candidate:GetAttribute("ReadingLevel")
						end

						if typeof(level) == "number" then
							highestEMF = math.max(
								highestEMF,
								math.clamp(
									math.floor(level + 0.5),
									1,
									5
								)
							)
						end
					end
				end
			end
		end
	end

	local items = workspace:FindFirstChild("Items")
	if items and not evidenceFound.Wither then
		for _, object in ipairs(items:GetDescendants()) do
			if object:IsA("BasePart")
				and object.Name == "Flower_Petals"
				and object.Color.R <= 0.03
				and object.Color.G <= 0.03
				and object.Color.B <= 0.03 then
				evidenceFound.Wither = true
				break
			end
		end
	end
	if not evidenceFound.Inscription then
		local function spiritBookHasWriting(model)
			if not model or not model:IsA("Model") then
				return false
			end
			local itemName =
				string.lower(
					tostring(
						model:GetAttribute("ItemName") or ""
					)
				)
			local modelName = string.lower(model.Name)
			local identifiedBook =
				itemName == "spirit book"
				or modelName == "spirit book"
			local canvas = model:FindFirstChild("Canvas", true)
			local surfaceGui =
				canvas and canvas:FindFirstChild("SurfaceGui")
			local frame =
				surfaceGui and surfaceGui:FindFirstChild("Frame")
			local imageLabel =
				frame and frame:FindFirstChild("ImageLabel")
			if imageLabel
				and imageLabel:IsA("ImageLabel")
				and imageLabel.Image ~= "" then
				return true
			end
			if not identifiedBook then
				return false
			end
			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("Decal")
					and descendant.Texture ~= "" then
					return true
				end
				if descendant:IsA("ImageLabel")
					and descendant.Image ~= ""
					and descendant:FindFirstAncestor("Canvas") then
					return true
				end
			end
			return false
		end
		local checked = setmetatable({}, {__mode = "k"})
		for _, container in ipairs({
			items,
			player:FindFirstChild("ToolsHolder"),
			player.Character,
		}) do
			if container then
				for _, descendant in ipairs(
					container:GetDescendants()
				) do
					if descendant:IsA("Model")
						and not checked[descendant] then
						checked[descendant] = true
						if spiritBookHasWriting(descendant) then
							evidenceFound.Inscription = true
							break
						end
					end
				end
			end
			if evidenceFound.Inscription then
				break
			end
		end
	end
end
local function normalizeSpiritBoxSubtitle(value)
	local text = tostring(value or "")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	text = string.gsub(text, "%s+", " ")
	return string.lower(text)
end
local function rebuildSpiritBoxVoiceIndex()
	local state = perkTrackerState
	table.clear(state.spiritBoxVoiceSubtitles)
	local assets = Services.ReplicatedStorage:FindFirstChild("Assets")
	local voices = assets and assets:FindFirstChild("SpiritBoxVoices")
	state.spiritBoxVoiceFolder = voices
	if not voices then
		return
	end
	local function addVoice(object)
		if not object:IsA("Sound") then
			return
		end
		local subtitle = object:GetAttribute("Subtitle")
		if type(subtitle) ~= "string" then
			return
		end
		local key = normalizeSpiritBoxSubtitle(subtitle)
		if key ~= "" then
			local voiceInfo = state.spiritBoxVoiceSubtitles[key]
			if not voiceInfo then
				voiceInfo = {
					Female = false,
				}
				state.spiritBoxVoiceSubtitles[key] = voiceInfo
			end
			local parent = object.Parent
			local grandparent = parent and parent.Parent
			if grandparent and grandparent.Name == "Female" then
				voiceInfo.Female = true
			end
		end
	end
	addVoice(voices)
	for _, object in ipairs(voices:GetDescendants()) do
		addVoice(object)
	end
end
local function updateSpiritBoxLabel()
	perkTrackerState.updateEvidenceStatuses()
end
local function processSpiritBoxRemoteSubtitle(firstArgument, priority, muted, voiceCategory)
	if closed or type(firstArgument) ~= "string" then
		return
	end
	local state = perkTrackerState
	if next(state.spiritBoxVoiceSubtitles) == nil then
		rebuildSpiritBoxVoiceIndex()
	end
	local key = normalizeSpiritBoxSubtitle(firstArgument)
	local voiceInfo = state.spiritBoxVoiceSubtitles[key]
	if key == "" or not voiceInfo then
		return
	end
	evidenceFound.SpiritBox = true
	spiritBoxTentative = false
	local compactKey = string.gsub(key, "%s+", "")
	if compactKey == "-humming-" then
		local skinwalkerPossible = ghostSupportsConfirmedEvidence(
			"Skinwalker",
			getConfirmedEvidence()
		)
		recordPerkDetection(
			"Siren",
			"Spirit Box returned the distinctive - HUMMING - subtitle",
			skinwalkerPossible and 60 or 95
		)
		if skinwalkerPossible then
			recordPerkDetection(
				"Skinwalker",
				"Skinwalker may mimic the Siren humming response",
				60
			)
		end
	elseif tostring(voiceCategory or "") == "Female" then
		recordPerkDetection(
			"Keres",
			"ShowSubtitle identified the Spirit Box voice category as Female",
			35
		)
		recordPerkDetection(
			"Siren",
			"ShowSubtitle identified the Spirit Box voice category as Female",
			35
		)

		for _, ghostName in ipairs({"Keres", "Siren"}) do
			local detection = perkDetections[ghostName]
			if detection and detection.Confidence == 35 then
				detection.Persistent = true
				detection.ExpiresAt = nil
			end
		end
	end
	updateSpiritBoxLabel()
	updateGhostIdentification(getGhostModel())
end
local function bindSpiritBoxRemoteListeners()
	local state = perkTrackerState
	if state.spiritBoxRemoteBound then
		return
	end
	local replicatedEvents = Services.ReplicatedStorage:FindFirstChild("Events")
	local remote = replicatedEvents and replicatedEvents:FindFirstChild("ShowSubtitle")
	local playerScripts = player:FindFirstChild("PlayerScripts")
	local localEvents = playerScripts and playerScripts:FindFirstChild("Events")
	local localEvent = localEvents and localEvents:FindFirstChild("ShowSubtitle")
	if not remote and not localEvent then
		return
	end
	state.spiritBoxRemoteBound = true
	rebuildSpiritBoxVoiceIndex()
	if remote and remote:IsA("RemoteEvent") then
		connect(remote.OnClientEvent, function(firstArgument, priority, muted, voiceCategory)
			processSpiritBoxRemoteSubtitle(
				firstArgument,
				priority,
				muted,
				voiceCategory
			)
		end)
	end
	if localEvent and localEvent:IsA("BindableEvent") then
		connect(localEvent.Event, function(firstArgument, priority, muted, voiceCategory)
			processSpiritBoxRemoteSubtitle(
				firstArgument,
				priority,
				muted,
				voiceCategory
			)
		end)
	end
	local voices = state.spiritBoxVoiceFolder
	if voices then
		connect(voices.DescendantAdded, rebuildSpiritBoxVoiceIndex)
		connect(voices.DescendantRemoving, rebuildSpiritBoxVoiceIndex)
	end
end
local function updateEvidence()
	ensureGhoulItemTracker()
	local ghost = getGhostModel()
	if not ghost then
		if evidenceRoundGhost then
			resetEvidenceState()
			evidenceRoundGhost = nil
		end
		updateFavouriteRoomEsp(nil)
		return
	end
	if evidenceRoundGhost and ghost ~= evidenceRoundGhost then
		resetEvidenceState()
	end
	evidenceRoundGhost = ghost
	local roomsFolder = findRoomsFolder()
	local now = os.clock()
	if now - lastDeepEvidenceScan >= 1.0 then
		lastDeepEvidenceScan = now
		scanDeepEvidence()
	end
	setEvidence("Print", evidenceFound.Print)
	bindSpiritBoxRemoteListeners()
	updateSpiritBoxLabel()
	setEvidence("Inscription", evidenceFound.Inscription)
	setEvidence("Wither", evidenceFound.Wither)
	local inLaser = ghost and ghost:GetAttribute("InLaser") == true or false
	if inLaser then
		perkTrackerState.lidarVisibleObserved = true
	end
	setEvidence("Laser", inLaser)
	perkTrackerState.updateOrbEvidence()
	perkTrackerState.updateDybbukMaybe(ghost)
	local favouriteRoomName = ghost and ghost:GetAttribute("FavoriteRoom") or nil
	if presenter and presenter.SetFavouriteRoom then
		presenter:SetFavouriteRoom(favouriteRoomName)
	elseif favouriteRoomName and tostring(favouriteRoomName) ~= "" then
		setEvidenceLabel("FavouriteRoom", "Favourite Room: " .. tostring(favouriteRoomName))
	else
		setEvidenceLabel("FavouriteRoom", "Favourite Room: ...")
	end
	local favouriteRoom = findFavouriteRoom(roomsFolder, favouriteRoomName)
	updateFavouriteRoomEsp(favouriteRoom)
	local roomTemperature = favouriteRoom and favouriteRoom:GetAttribute("Temperature") or nil
	if typeof(roomTemperature) == "number" then
		if roomTemperature < 0 then
			freezingEvidenceFound = true
		end
		if presenter and presenter.SetTemperature then
			presenter:SetTemperature(roomTemperature, freezingEvidenceFound)
		else
			setEvidenceLabel(
				"Temperature",
				string.format("%.1f°C", roomTemperature),
				freezingEvidenceFound and COLORS.green or COLORS.text
			)
		end
	else
		if presenter and presenter.SetTemperature then
			presenter:SetTemperature(nil, freezingEvidenceFound)
		else
			setEvidenceLabel(
				"Temperature",
				"--.-°C",
				freezingEvidenceFound and COLORS.green or COLORS.text
			)
		end
	end
	updateGhostIdentification(ghost)
end

local Controller = {}
Controller.__index = Controller

function Controller:Connect(signal, callback)
	return connect(signal, callback)
end

function Controller:SetSpeed(value)
	setSpeed(value)
	return speed
end

function Controller:ToggleGhostEsp()
	ghostEspEnabled = not ghostEspEnabled
	setButtonEnabled(ghostEspButton, ghostEspEnabled)
	if ghostEspEnabled then
		if not createGhostEsp() then
			ghostEspEnabled = false
			setButtonEnabled(ghostEspButton, false)
		end
	else
		destroyGhostEsp()
	end
	return ghostEspEnabled
end

function Controller:ToggleHuntEscape()
	huntEscapeEnabled = not huntEscapeEnabled
	setButtonEnabled(huntEscapeButton, huntEscapeEnabled)
	if huntEscapeEnabled then
		escapeCurrentHunt()
	end
	return huntEscapeEnabled
end

function Controller:ToggleItemEsp()
	itemEspEnabled = not itemEspEnabled
	setButtonEnabled(itemEspButton, itemEspEnabled)
	if itemEspEnabled then
		createItemEsp()
	else
		clearItemEsp()
	end
	return itemEspEnabled
end

function Controller:ToggleFullBright()
	setFullBright(not fullBrightEnabled)
	return fullBrightEnabled
end

function Controller:TeleportToBaseCamp()
	return teleportToBaseCamp()
end

function Controller:TeleportToFavouriteRoom()
	return teleportToFavouriteRoom()
end

function Controller:PlaceRoomItems()
	placeItemsInFavouriteRoom()
end

function Controller:ToggleAutoSpiritBox()
	perkTrackerState.autoSpiritBoxEnabled = not perkTrackerState.autoSpiritBoxEnabled
	perkTrackerState.autoSpiritBoxAccumulator = perkTrackerState.autoSpiritBoxEnabled and 2.05 or 0
	setButtonEnabled(autoSpiritBoxButton, perkTrackerState.autoSpiritBoxEnabled)
	return perkTrackerState.autoSpiritBoxEnabled
end

function Controller:SetEvidenceMode(mode)
	if mode ~= "Normal" and mode ~= "Mimicry" then
		return false, "Evidence mode must be Normal or Mimicry"
	end
	perkTrackerState.evidenceMode = mode
	if mode == "Normal" then
		perkTrackerState.updateOrbEvidence()
	end
	updateGhostIdentification(getGhostModel())
	return true
end

function Controller:ToggleRandomLights()
	if player:GetAttribute("Dead") == true then
		return false, "Dead players cannot use light switches"
	end
	if not runtimeIsActive() then
		return false, "The current session is closing"
	end

	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local remote = events and events:FindFirstChild("UseLightSwitch")
	local map = workspace:FindFirstChild("Map")
	local rooms = map and map:FindFirstChild("Rooms")
	if not remote or not remote:IsA("RemoteEvent") then
		return false, "UseLightSwitch RemoteEvent was not found"
	end
	if not rooms then
		return false, "Map rooms were not found"
	end

	local eligible = {}
	local seen = setmetatable({}, {__mode = "k"})
	for _, switch in ipairs(Services.CollectionService:GetTagged("LightSwitch")) do
		if switch:IsDescendantOf(rooms) and switch:GetAttribute("LightsBroken") ~= true then
			for _, room in ipairs(rooms:GetChildren()) do
				if not seen[room]
					and switch:IsDescendantOf(room)
					and room:GetAttribute("LightsBroken") ~= true then
					seen[room] = true
					table.insert(eligible, room)
					break
				end
			end
		end
	end
	if #eligible == 0 then
		return false, "No working room light switches were found"
	end
	perkTrackerState.suppressLeviathanLightsUntil = os.clock() + 2.5

	task.spawn(function()
		if not runtimeIsActive() then
			return
		end

		for index = #eligible, 2, -1 do
			local swapIndex = math.random(index)
			eligible[index], eligible[swapIndex] = eligible[swapIndex], eligible[index]
		end

		local changed = false
		local count = #eligible > 0 and math.random(1, math.min(3, #eligible)) or 0
		for index = 1, count do
			if not runtimeIsActive() then
				return
			end
			local room = eligible[index]
			local switch = room and room:FindFirstChild("LightSwitch", true)
			local beforeRoom = room and room:GetAttribute("LightsOn")
			local beforeSwitch = switch and switch:GetAttribute("State")

			if room
				and room.Parent == rooms
				and room:GetAttribute("LightsBroken") ~= true
				and (not switch or switch:GetAttribute("LightsBroken") ~= true) then
				pcall(remote.FireServer, remote, room)
				perkTrackerState.suppressLeviathanLightsUntil = os.clock() + 2.5
				task.wait(0.3)
				if not runtimeIsActive() then
					return
				end
				changed = changed
					or room:GetAttribute("LightsOn") ~= beforeRoom
					or (switch and switch:GetAttribute("State") ~= beforeSwitch)
			end
		end

		if changed and runtimeIsActive() then
			perkTrackerState.flashButton(randomLightsButton)
		elseif runtimeIsActive() and presenter and presenter.Notify then
			presenter:Notify("The selected light switches did not respond")
		end
	end)

	return true
end

function Controller:ToggleFuseBox()
	if player:GetAttribute("Dead") == true then
		return false, "Dead players cannot use the fuse box"
	end
	if not runtimeIsActive() then
		return false, "The current session is closing"
	end

	local map = workspace:FindFirstChild("Map")
	local fuseBox = map and map:FindFirstChild("FuseBox")
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local remote = events and events:FindFirstChild("ToggleFuseBox")
	if not fuseBox then
		return false, "FuseBox was not found"
	end
	if not remote or not remote:IsA("RemoteEvent") then
		return false, "ToggleFuseBox RemoteEvent was not found"
	end

	task.spawn(function()
		if not runtimeIsActive() then
			return
		end

		local before = fuseBox:GetAttribute("Enabled")
		pcall(remote.FireServer, remote)
		task.wait(0.45)
		if not runtimeIsActive() then
			return
		end
		local changed = fuseBox:GetAttribute("Enabled") ~= before
		local actionFailure

		if not changed then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local anchor = fuseBox:FindFirstChild("PromptAnchor", true)
				or fuseBox:FindFirstChildWhichIsA("BasePart", true)

			if character and root and humanoid and anchor and anchor:IsA("BasePart") then
				local original = character:GetPivot()
				local originalAnchored = root.Anchored
				local mutated = false
				local function restoreCharacter()
					if not mutated then
						return
					end
					pcall(function()
						if character.Parent and root.Parent then
							character:PivotTo(original)
							root.AssemblyLinearVelocity = Vector3.zero
							root.AssemblyAngularVelocity = Vector3.zero
							root.Anchored = originalAnchored
						end
					end)
				end

				local succeeded, actionError = xpcall(function()
					root.Anchored = true
					mutated = true
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					character:PivotTo(anchor.CFrame * CFrame.new(0, 2.5, 3))
					Services.RunService.Heartbeat:Wait()
					if not runtimeIsActive() then
						return
					end
					pcall(remote.FireServer, remote)

					for _, descendant in ipairs(fuseBox:GetDescendants()) do
						if not runtimeIsActive() then
							break
						end
						if descendant:IsA("ProximityPrompt") then
							pcall(function()
								if typeof(fireproximityprompt) == "function" then
									fireproximityprompt(descendant)
								end
							end)
						end
					end

					task.wait(0.55)
					if runtimeIsActive() then
						changed = fuseBox:GetAttribute("Enabled") ~= before
					end
				end, debug.traceback)
				restoreCharacter()
				if not succeeded then
					actionFailure = tostring(actionError):match("^[^\n]+")
				end
			end
		end

		if changed and runtimeIsActive() then
			perkTrackerState.flashButton(toggleFuseBoxButton)
		elseif runtimeIsActive() and presenter and presenter.Notify then
			presenter:Notify(actionFailure or "The fuse box did not respond")
		end
	end)

	return true
end

function Controller:ToggleWalkSpeedForcer()
	perkTrackerState.speedForcerEnabled =
		not perkTrackerState.speedForcerEnabled
	perkTrackerState.speedForceAccumulator = 0

	setButtonEnabled(
		walkSpeedForcerButton,
		perkTrackerState.speedForcerEnabled
	)

	local humanoid = getCharacterHumanoid()
	if humanoid then
		if perkTrackerState.speedForcerEnabled then
			applyForcedWalkSpeed()
		else
			humanoid.WalkSpeed = baseWalkSpeed
		end
	end

	return perkTrackerState.speedForcerEnabled
end

function Controller:GetState()
	return {
		Closed = closed,
		Speed = speed,
		GhostEsp = ghostEspEnabled,
		HuntEscape = huntEscapeEnabled,
		ItemEsp = itemEspEnabled,
		FullBright = fullBrightEnabled,
		AutoSpiritBox = perkTrackerState.autoSpiritBoxEnabled,
		WalkSpeedForcer = perkTrackerState.speedForcerEnabled,
		EvidenceMode = perkTrackerState.evidenceMode,
	}
end

function Controller:Destroy()
	if closed then
		return
	end
	closed = true
	ghostEspEnabled = false
	huntEscapeEnabled = false
	itemEspEnabled = false
	perkTrackerState.autoSpiritBoxEnabled = false
	perkTrackerState.autoSpiritBoxAccumulator = 0
	perkTrackerState.speedForcerEnabled = false
	perkTrackerState.speedForceAccumulator = 0
	roomItemPlacementState.generation = roomItemPlacementState.generation + 1
	roomItemPlacementState.busy = false
	if roomItemPlacementState.thread then
		-- Let yielded character-mutation helpers unwind and restore their
		-- anchored/humanoid state before the cooperative generation check exits.
		roomItemPlacementState.thread = nil
	end
	destroyGhostEsp()
	destroyFavouriteRoomEsp()
	clearItemEsp()
	setFullBright(false)
	local humanoid = getCharacterHumanoid()
	if humanoid then
		humanoid.WalkSpeed = baseWalkSpeed
	end
	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	if gui then
		gui:Destroy()
	end
	if generation == nil or environment.DemonologyGeneration == generation then
		environment.UntitledGuiLoaded = nil
		environment.UntitledGuiInstance = nil
		environment.UntitledGuiCleanup = nil
		environment.DemonologyUI = nil
	end
end

local controller = setmetatable({}, Controller)
function Controller:Start()
	if self.Started then
		return self
	end
	if closed then
		error("Cannot start a destroyed controller", 2)
	end
	if not runtimeIsActive() then
		error("Cannot start a superseded controller", 2)
	end
	self.Started = true

	connect(player.CharacterAdded, function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and runtimeIsActive() then
			bindSpeedLock(humanoid)
		end
	end)

	local initialHumanoid = getCharacterHumanoid()
	if initialHumanoid then
		bindSpeedLock(initialHumanoid)
	end
	setSpeed(10)
	setButtonEnabled(
		walkSpeedForcerButton,
		perkTrackerState.speedForcerEnabled
	)
	evidenceRoundGhost = getGhostModel()
	lastDeepEvidenceScan = -math.huge

	local updateAccumulator = 0
	connect(Services.RunService.Heartbeat, function(deltaTime)
		if not runtimeIsActive() then
			return
		end
		updateObservablePerkTrackers(deltaTime)
		perkTrackerState.updateAutoSpiritBox(deltaTime)
		perkTrackerState.speedForceAccumulator =
			perkTrackerState.speedForceAccumulator + deltaTime
		if perkTrackerState.speedForceAccumulator >= 0.25 then
			perkTrackerState.speedForceAccumulator = 0
			applyForcedWalkSpeed()
		end
		updateAccumulator = updateAccumulator + deltaTime
		if updateAccumulator < 0.5 then
			return
		end
		updateAccumulator = 0
		updateEvidence()
		escapeCurrentHunt()
		if ghostEspEnabled then
			local ghost = getGhostModel()
			local ghostPart = getGhostPart(ghost)
			if not ghost or not ghostPart then
				destroyGhostEsp()
			elseif not ghostBillboard
				or ghostBillboard.Adornee ~= ghostPart
				or not ghostDirectHighlight
				or ghostDirectHighlight.Adornee ~= ghost
				or not ghostHighlight
				or ghostProxyNeedsRebuild(ghost) then
				createGhostEsp()
			end
		end
	end)

	connect(Services.RunService.RenderStepped, function()
		if runtimeIsActive() and ghostEspEnabled and ghostEspTarget then
			updateGhostProxy(ghostEspTarget)
		end
	end)

	bindSpiritBoxRemoteListeners()
	updateEvidence()
	return self
end

if generation == nil or environment.DemonologyGeneration == generation then
	environment.UntitledGuiCleanup = function()
		controller:Destroy()
	end
end

return controller
end
