return function(dependencies)
	dependencies = dependencies or {}
	local Services = assert(dependencies.Services, "logic/logic.luau requires Services")
	local player = dependencies.Player or Services.Players.LocalPlayer
	local environment = dependencies.Environment or ((getgenv and getgenv()) or _G)
	local generation = dependencies.Generation
	local GhostModule = assert(dependencies.GhostModule, "logic/logic.luau requires GhostModule")
	local GhostPackage = assert(
		dependencies.GhostPackage,
		"logic/logic.luau requires GhostPackage"
	)
	local createRoundAutomation = assert(
		dependencies.RoundAutomation,
		"logic/logic.luau requires RoundAutomation"
	)
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
	local doRoundButton = view.Buttons.DoRound
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
local huntEscapeManualEnabled = false
local huntEscapeTriggered = false
local itemEspEnabled = false
local roomItemPlacementState = {
	busy = false,
	generation = 0,
	thread = nil,
	owner = nil,
	lastResult = nil,
	lastError = nil,
	lastCompletedGeneration = 0,
}
local doRoundState = {
	enabled = false,
	generation = 0,
	thread = nil,
	startedAt = nil,
	lastElapsed = 0,
	phase = "Off",
	autoSpiritBoxLease = false,
	questionsActive = false,
	usedDoorNames = {},
	usedSaltDoorModels = setmetatable({}, {__mode = "k"}),
	completedDoorTools = {},
	doorToolPlacements = {},
	doorToolUses = {},
	lastDoorName = nil,
	roomItems = {},
	itemPower = setmetatable({}, {__mode = "k"}),
	outsideSince = setmetatable({}, {__mode = "k"}),
	maintenanceAccumulator = 0,
	lastFavouriteRoom = nil,
	roundMap = nil,
	roundGhost = nil,
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
local lowestRecordedTemperature = nil
local spiritBoxTentative = false
local speedLockConnection
local perkDetections = {}
local ghostCoordinator
local emitGhostObservation = function() end
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
local analyzePhantom = function() end
local perkTrackerState = {
	ghost = nil,
	fixedGhostModel = nil,
	ghostCoreTickAccumulator = 0,
	ghostCoreConnections = {},
	ghostCoreSyncQueued = false,
	syncingGhostCoordinator = false,
	ghostCoreDeathSeen = setmetatable({}, {__mode = "k"}),
	resetEvidenceState = function() end,
	ghostMissingSince = nil,
	roundMap = nil,
	evidenceMode = "Normal",
	speedForcerEnabled = false,
	speedForceAccumulator = 0,
	visualModelChecked = false,
	sampleAccumulator = 0,
	slowScanAccumulator = 0,
	analysisAccumulator = 0,
	lastPosition = nil,
	lastSampleTime = nil,
	lastHunting = nil,
	huntingAttributeConnection = nil,
	motionSamples = {},
	losSamples = {},
	energySamples = {},
	transparencyTransitions = {},
	transparencyIntervals = {},
	lastTransparencyState = nil,
	lastTransparencyTransitionTime = nil,
	phantomPatternHunts = 0,
	phantomNoPatternHunts = 0,
	phantomPatternRecordedThisHunt = false,
	phantomQualifiedCyclesThisHunt = 0,
	phantomMatchedCyclesThisHunt = 0,
	phantomContradictoryCyclesThisHunt = 0,
	phantomMimicrySkinwalkerClue = false,
	phantomMimicryPreviousSkinwalkerDetection = nil,
	vexLastValue = nil,
	updateVexState = function() end,
	wendigoSnapshots = {},
	wendigoPendingTransitions = {},
	wendigoLastQueuedHunting = nil,
	wendigoTransitionSequence = 0,
	queueWendigoTransition = function() end,
	wispRoomMismatchKey = nil,
	wispRoomMismatchSince = nil,
	wispRoomMismatchSamples = 0,
	wispRoomNegativeRecordedThisHunt = false,
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
	specterTrialSequence = 0,
	specterActiveTrialId = nil,
	previousDead = {},
	pendingKill = nil,
	keresKillDecreaseCount = 0,
	aswangKillIncreaseCount = 0,
	killSpeedProcessedPlayers = setmetatable({}, {__mode = "k"}),
	huntStartedAt = nil,
	umbraRootSoundChecked = false,
	brokenGlassInitialized = false,
	brokenGlassSeen = {},
	brokenGlassEvents = {},
	sirenSlowEvents = {},
	sirenLosExposure = 0,
	sirenSlowObservedThisHunt = false,
	lastLosLightingKey = nil,
	lastLosTarget = nil,
	dullahanSpeedSamples = {},
	dullahanIncreaseEvents = {},
	dullahanHadQualifiedWindow = false,
	dullahanPatternDetected = false,
	dullahanPatternObservedThisHunt = false,
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
	ravagerGhost = nil,
	ravagerLastGhostPosition = nil,
	ravagerLastGhostSampleAt = nil,
	ravagerDetectedThisHunt = false,
	saltTrackerInitialized = false,
	saltFolder = nil,
	saltTrackedLines = setmetatable({}, {__mode = "k"}),
	saltPendingTouches = {},
	saltOverlapAccumulator = 0,
	wraithRuledOut = false,
	holyOilFolder = nil,
	holyOilTrackerInitialized = false,
	holyOilTrackedModels = setmetatable({}, {__mode = "k"}),
	holyOilColorStates = setmetatable({}, {__mode = "k"}),
	holyOilBurningSince = setmetatable({}, {__mode = "k"}),
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
	autoSpiritBoxManualEnabled = false,
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
	automationMutationUntil = 0,
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
local function refreshPerkLogs()
	if not presenter or not presenter.SetPerkLogs then
		return
	end
	local positives = {}
	local negatives = {}
	local positiveByKey = {}
	local negativeByKey = {}
	local function addLog(target, byKey, entry)
		local key = table.concat({
			tostring(entry.Ghost),
			tostring(entry.Reason),
			tostring(entry.Confidence),
		}, "\0")
		local existing = byKey[key]
		if existing then
			if (tonumber(entry.At) or 0) > (tonumber(existing.At) or 0) then
				existing.At = entry.At
			end
			return
		end
		byKey[key] = entry
		table.insert(target, entry)
	end
	for ghostName, detection in pairs(perkDetections) do
		-- Coordinator projections use the net score for ranking. The append-only
		-- ledger below owns the visible raw observations and must not be duplicated.
		if detection.Source ~= "GhostCoordinator" then
			addLog(positives, positiveByKey, {
				Ghost = ghostName,
				Reason = detection.Reason,
				Confidence = detection.Confidence,
				At = detection.DetectedAt,
			})
		end
	end
	for ghostName, ruledOut in pairs(perkTrackerState.ruledOutGhosts) do
		addLog(negatives, negativeByKey, {
			Ghost = ghostName,
			Reason = ruledOut.Reason,
			Confidence = ruledOut.Confidence,
			At = ruledOut.At,
		})
	end
	if ghostCoordinator then
		for _, entry in ipairs(
			ghostCoordinator:Ledger():EffectiveEntries()
		) do
			if entry.Polarity == "Positive" then
				addLog(positives, positiveByKey, {
					Ghost = entry.Ghost,
					Reason = entry.Reason,
					Confidence = entry.Confidence,
					At = entry.Time,
				})
			elseif entry.Polarity == "Negative"
				or entry.Polarity == "RuleOut" then
				addLog(negatives, negativeByKey, {
					Ghost = entry.Ghost,
					Reason = entry.Reason,
					Confidence = entry.Confidence,
					At = entry.Time,
				})
			end
		end
	end
	presenter:SetPerkLogs(positives, negatives)
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
	-- Once the modular coordinator exists, profile observers are the only source
	-- of ghost conclusions. These legacy routines remain solely as a startup
	-- fallback and as signal collectors for the observer package.
	if ghostCoordinator and not perkTrackerState.syncingGhostCoordinator then
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
		refreshPerkLogs()
		return
	end
	if score == (existing.Confidence or 0) then
		local previousReason = existing.Reason
		local previousDetectedAt = existing.DetectedAt or -math.huge
		existing.Reason = reason or existing.Reason
		existing.DetectedAt = now
		if persistent or existing.Persistent
			or (existing.Confidence or 0) >= 80 then
			existing.Persistent = true
			existing.ExpiresAt = nil
		elseif ttl then
			existing.ExpiresAt = now + ttl
		end
		if existing.Reason ~= previousReason
			or now - previousDetectedAt >= 1 then
			refreshPerkLogs()
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
	if perkDetections[ghostName] == nil then
		return false
	end
	if perkDetections[ghostName].Source == "GhostCoordinator" then
		return false
	end
	perkDetections[ghostName] = nil
	refreshPerkLogs()
	return true
end
local function clearAllPerkDetections()
	local changed = false
	for ghostName in pairs(perkDetections) do
		perkDetections[ghostName] = nil
		changed = true
	end
	if changed then
		refreshPerkLogs()
	end
end
perkTrackerState.ruleOutGhost = function(ghostName, reason, confidence)
	confidence = tonumber(confidence) or 0
	if confidence < 80 then
		return false
	end
	if ghostCoordinator and not perkTrackerState.syncingGhostCoordinator then
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
	-- Preserve the positive observation in the log.  A later contradiction is
	-- an additional ledger fact, not permission to erase what was observed.
	refreshPerkLogs()
	perkTrackerState.refreshIdentification()
	return true
end
perkTrackerState.clearGhostRuleOut = function(ghostName)
	local existing = perkTrackerState.ruledOutGhosts[ghostName]
	if existing and existing.Source == "GhostCoordinator" then
		return false
	end
	if existing then
		perkTrackerState.ruledOutGhosts[ghostName] = nil
		refreshPerkLogs()
		return true
	end
	return false
end
perkTrackerState.isGhostRuledOut = function(ghostName)
	return perkTrackerState.ruledOutGhosts[ghostName] ~= nil
end
local function strongestEntry(entries)
	local strongest
	for _, entry in ipairs(entries or {}) do
		if not strongest
			or (tonumber(entry.Confidence) or 0)
				> (tonumber(strongest.Confidence) or 0)
			or ((tonumber(entry.Confidence) or 0)
				== (tonumber(strongest.Confidence) or 0)
				and (tonumber(entry.Time) or 0)
					> (tonumber(strongest.Time) or 0)) then
			strongest = entry
		end
	end
	return strongest
end
local function syncGhostCoordinatorResults()
	if perkTrackerState.syncingGhostCoordinator or not ghostCoordinator then
		return
	end
	perkTrackerState.syncingGhostCoordinator = true
	local resolved = ghostCoordinator:Resolve()
	for ghostName, state in pairs(resolved) do
		local positive = strongestEntry(state.Positives)
		local effectiveScore = tonumber(state.Score)
			or tonumber(state.Confidence)
			or 0
		if positive and effectiveScore > 0 then
			local existing = perkDetections[ghostName]
			if not existing
				or existing.Source == "GhostCoordinator"
				or effectiveScore > (tonumber(existing.Confidence) or 0) then
				perkDetections[ghostName] = {
					Confidence = effectiveScore,
					RawConfidence = state.Confidence,
					NegativeConfidence = state.NegativeConfidence,
					Reason = positive.Reason,
					DetectedAt = positive.Time,
					Persistent = true,
					Tentative = true,
					Source = "GhostCoordinator",
				}
			end
		elseif perkDetections[ghostName]
			and perkDetections[ghostName].Source == "GhostCoordinator" then
			perkDetections[ghostName] = nil
		end

		local ruleOut = strongestEntry(state.RuleOuts)
		local existingRuleOut = perkTrackerState.ruledOutGhosts[ghostName]
		if ruleOut and (not existingRuleOut
			or existingRuleOut.Source == "GhostCoordinator"
			or (tonumber(ruleOut.Confidence) or 0)
				> (tonumber(existingRuleOut.Confidence) or 0)) then
			perkTrackerState.ruledOutGhosts[ghostName] = {
				Confidence = ruleOut.Confidence,
				Reason = ruleOut.Reason,
				At = ruleOut.Time,
				Source = "GhostCoordinator",
			}
		elseif not ruleOut and existingRuleOut
			and existingRuleOut.Source == "GhostCoordinator" then
			perkTrackerState.ruledOutGhosts[ghostName] = nil
		end
	end
	perkTrackerState.syncingGhostCoordinator = false
	refreshPerkLogs()
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
			if ghostCoordinator then
				emitGhostObservation({
					Type = "FalseOrb",
					Qualified = true,
					ImpossibleCombination = true,
					RealEvidenceDisabled = true,
					Source = "OrbEvidenceCollector",
				})
			end
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
	local expiredDetection = false
	for ghostName, detection in pairs(perkDetections) do
		local score = detection.Confidence or 0
		if score >= 80 or detection.Persistent then
			detection.Persistent = true
			detection.ExpiresAt = nil
		elseif detection.ExpiresAt
			and now > detection.ExpiresAt then
			perkDetections[ghostName] = nil
			expiredDetection = true
			continue
		end
	end
	if expiredDetection then
		refreshPerkLogs()
	end
	local ranked = GhostModule.RankDetections(perkDetections, {}, {}, {Now = now})
	local candidates = {}
	for _, candidate in ipairs(ranked) do
		local evidenceCompatible = ghostSupportsConfirmedEvidence(
			candidate.Ghost,
			confirmed
		)
		local preserveMimicryClue =
			perkTrackerState.evidenceMode == "Mimicry"
			and candidate.Detection
			and candidate.Detection.Persistent == true
		if not perkTrackerState.isGhostRuledOut(candidate.Ghost)
			and (evidenceCompatible or preserveMimicryClue) then
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
	if ghostCoordinator then
		return nil
	end
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
	local mimicryBehaviorLocked =
		perkTrackerState.evidenceMode == "Mimicry"
		and perkDetection
		and (perkDetection.Confidence or 0) >= 50
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
	if #candidates == 1 and not mimicryBehaviorLocked then
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
	if doRoundState.autoSpiritBoxLease then
		local ghost = workspace:FindFirstChild("Ghost")
		if not doRoundState.questionsActive
			or not ghost
			or ghost:GetAttribute("Hunting") == true then
			return
		end
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
	if perkTrackerState.evidenceMode == "Mimicry"
		and not perkTrackerState.isGhostRuledOut("Skinwalker") then
		skinwalkerPossible = true
	end
	local confidence = corroborated and 99 or 60
	local suffix = corroborated
		and "; both out-of-hunt equipment flicker and a room light shutoff were observed"
		or "; this single ability is not unique"
	if ghostCoordinator then
		emitGhostObservation({
			Type = kind == "Flicker" and "DeviceToggleBurst" or "RoomLightOff",
			Hunting = false,
			Qualified = true,
			PlayerCaused = false,
			AutomationCaused = false,
			FuseCaused = false,
			SingleDevice = kind == "Flicker",
			Rapid = kind == "Flicker",
			WorkingCircuit = kind == "LightOff",
			Confidence = confidence,
			Reason = reason .. suffix,
			Source = "LightAndDeviceCollector",
		})
		if not corroborated and skinwalkerPossible then
			emitGhostObservation({
				Type = "MimickedAbility",
				Ability = "Leviathan",
				Qualified = true,
				Confidence = 60,
				Source = "LightAndDeviceCollector",
			})
		end
		return
	end
	recordPerkDetection("Leviathan", reason .. suffix, confidence)
	local leviathanDetection = perkDetections.Leviathan
	if leviathanDetection then
		leviathanDetection.Persistent = true
		leviathanDetection.ExpiresAt = nil
	end
	if not corroborated and skinwalkerPossible then
		recordPerkDetection(
			"Skinwalker",
			"Skinwalker may mimic one Leviathan light or equipment ability",
			60
		)
		local skinwalkerDetection = perkDetections.Skinwalker
		if skinwalkerDetection then
			skinwalkerDetection.Persistent = true
			skinwalkerDetection.ExpiresAt = nil
		end
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
					if ghostCoordinator then
						emitGhostObservation({
							Type = "HuntElectronicDisabled",
							Hunting = true,
							Qualified = true,
							PlayerCaused = false,
							AutomationCaused = false,
							Source = "WorldElectronicCollector",
						})
					else
						perkTrackerState.ruleOutGhost(
							"Ghoul",
							"a world electronic was disabled near the ghost while no player was the nearer cause",
							98
						)
					end
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
	if not button then
		return
	end
	if presenter and presenter.SetButtonEnabled then
		presenter:SetButtonEnabled(button, enabled)
		return
	end
	button.BackgroundColor3 = enabled and COLORS.accentDark or COLORS.cardHover
	button.TextColor3 = enabled and Color3.new(1, 1, 1) or COLORS.text
end

local function setDoRoundStatus(phase)
	doRoundState.phase = tostring(phase or doRoundState.phase or "Off")
	local elapsed = doRoundState.startedAt
		and math.max(0, os.clock() - doRoundState.startedAt)
		or doRoundState.lastElapsed
		or 0
	if presenter and presenter.SetDoRoundState then
		presenter:SetDoRoundState(
			doRoundState.enabled,
			elapsed,
			doRoundState.phase
		)
	elseif doRoundButton then
		doRoundButton.Text = string.format(
			"Do-Round %d:%02d - %s",
			math.floor(elapsed / 60),
			math.floor(elapsed % 60),
			doRoundState.phase
		)
		setButtonEnabled(doRoundButton, doRoundState.enabled)
	end
end

local function refreshAutoSpiritBoxEnabled()
	local enabled = perkTrackerState.autoSpiritBoxManualEnabled
		or doRoundState.autoSpiritBoxLease
	if enabled ~= perkTrackerState.autoSpiritBoxEnabled then
		perkTrackerState.autoSpiritBoxEnabled = enabled
		perkTrackerState.autoSpiritBoxAccumulator = enabled and 2.05 or 0
	end
	setButtonEnabled(autoSpiritBoxButton, enabled)
	return enabled
end

local function refreshHuntEscapeEnabled()
	huntEscapeEnabled = huntEscapeManualEnabled
	setButtonEnabled(huntEscapeButton, huntEscapeEnabled)
	return huntEscapeEnabled
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
perkTrackerState.resetEvidenceState = function()
	ghoulRuledOut = false
	table.clear(perkTrackerState.ghostCoreDeathSeen)
	for _, connection in ipairs(perkTrackerState.ghostCoreConnections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(perkTrackerState.ghostCoreConnections)
	if ghostCoordinator then
		ghostCoordinator:Destroy()
		ghostCoordinator = nil
	end
	perkTrackerState.fixedGhostModel = nil
	perkTrackerState.ghost = nil
	perkTrackerState.ghostCoreTickAccumulator = 0
	perkTrackerState.ghostCoreSyncQueued = false
	emitGhostObservation = function()
		return nil
	end
	rebaselineGhoulItemTracker()
	for evidenceName in pairs(evidenceFound) do
		evidenceFound[evidenceName] = false
	end
	freezingEvidenceFound = false
	lowestRecordedTemperature = nil
	highestEMF = 1
	spiritBoxTentative = false
	perkTrackerState.orbObserved = false
	perkTrackerState.lidarVisibleObserved = false
	perkTrackerState.dullahanSpeedSamples = {}
	perkTrackerState.dullahanIncreaseEvents = {}
	perkTrackerState.dullahanHadQualifiedWindow = false
	perkTrackerState.dullahanPatternDetected = false
	perkTrackerState.dullahanPatternObservedThisHunt = false
	perkTrackerState.dullahanCompletedNoIncreaseHunt = false
	perkTrackerState.dybbukMaybeReady = false
	perkTrackerState.leviathanToggleEvents = {}
	perkTrackerState.leviathanLightStates = setmetatable({}, {__mode = "k"})
	perkTrackerState.leviathanLastFlickerAt = -math.huge
	perkTrackerState.leviathanLastLightOffAt = -math.huge
	perkTrackerState.leviathanLightScanAccumulator = 0
	perkTrackerState.suppressItemDisableUntil = 0
	perkTrackerState.suppressLeviathanLightsUntil = 0
	perkTrackerState.saltPendingTouches = {}
	perkTrackerState.saltOverlapAccumulator = 0
	perkTrackerState.wraithRuledOut = false
	perkTrackerState.ruledOutGhosts = {}
	clearAllPerkDetections()
	refreshPerkLogs()
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
		setEvidenceLabel(
			"Temperature",
			COPY.Evidence.Temperature .. ": --.-°C",
			COLORS.text
		)
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
local function resetPerkTrackerForGhost(ghost, preserveFindings)
	local previousGhost = perkTrackerState.ghost
	local currentMap = workspace:FindFirstChild("Map")
	local roundChanged = previousGhost ~= nil
		and currentMap ~= perkTrackerState.roundMap
	preserveFindings = preserveFindings == true
		and currentMap ~= nil
		and perkTrackerState.roundMap == currentMap
	if previousGhost and (ghost ~= previousGhost or roundChanged) then
		if not preserveFindings then
			perkTrackerState.resetEvidenceState()
		end
		evidenceRoundGhost = ghost
	end
	if not preserveFindings then
		clearAllPerkDetections()
	end
	perkTrackerState.ghost = ghost
	perkTrackerState.ghostMissingSince = nil
	perkTrackerState.roundMap = currentMap
	perkTrackerState.visualModelChecked = false
	perkTrackerState.sampleAccumulator = 0
	perkTrackerState.slowScanAccumulator = 0
	perkTrackerState.analysisAccumulator = 0
	perkTrackerState.lastPosition = nil
	perkTrackerState.lastSampleTime = nil
	if perkTrackerState.huntingAttributeConnection then
		local connection = perkTrackerState.huntingAttributeConnection
		connection:Disconnect()
		local index = table.find(connections, connection)
		if index then
			table.remove(connections, index)
		end
		perkTrackerState.huntingAttributeConnection = nil
	end
	local initialHunting = if ghost
		then ghost:GetAttribute("Hunting") == true
		else nil
	perkTrackerState.lastHunting = initialHunting
	perkTrackerState.motionSamples = {}
	perkTrackerState.losSamples = {}
	perkTrackerState.energySamples = {}
	if perkTrackerState.transparencyAttributeConnection then
		local connection = perkTrackerState.transparencyAttributeConnection
		connection:Disconnect()
		local index = table.find(connections, connection)
		if index then
			table.remove(connections, index)
		end
		perkTrackerState.transparencyAttributeConnection = nil
	end
	perkTrackerState.transparencyTransitions = {}
	perkTrackerState.transparencyIntervals = {}
	perkTrackerState.lastTransparencyState = nil
	perkTrackerState.lastTransparencyTransitionTime = nil
	if not preserveFindings then
		perkTrackerState.phantomPatternHunts = 0
		perkTrackerState.phantomNoPatternHunts = 0
		perkTrackerState.phantomMimicrySkinwalkerClue = false
		perkTrackerState.phantomMimicryPreviousSkinwalkerDetection = nil
		perkTrackerState.phantomPatternRecordedThisHunt = false
	end
	perkTrackerState.phantomQualifiedCyclesThisHunt = 0
	perkTrackerState.phantomMatchedCyclesThisHunt = 0
	perkTrackerState.phantomContradictoryCyclesThisHunt = 0
	perkTrackerState.vexLastValue = nil
	perkTrackerState.wendigoSnapshots = {}
	perkTrackerState.wendigoPendingTransitions = {}
	perkTrackerState.wendigoLastQueuedHunting = initialHunting
	perkTrackerState.wendigoTransitionSequence = 0
	perkTrackerState.wispRoomMismatchKey = nil
	perkTrackerState.wispRoomMismatchSince = nil
	perkTrackerState.wispRoomMismatchSamples = 0
	perkTrackerState.wispRoomNegativeRecordedThisHunt = false
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
	perkTrackerState.specterTrialSequence = 0
	perkTrackerState.specterActiveTrialId = nil
	if ghost then
		perkTrackerState.huntingAttributeConnection = connect(
			ghost:GetAttributeChangedSignal("Hunting"),
			function()
				if closed or perkTrackerState.ghost ~= ghost then
					return
				end
				if not ghostCoordinator then
					perkTrackerState.queueWendigoTransition(
						ghost:GetAttribute("Hunting") == true,
						os.clock()
					)
				end
			end
		)
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
			if not closed
				and not ghostCoordinator
				and perkTrackerState.ghost == ghost then
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
	perkTrackerState.umbraRootSoundChecked = false
	perkTrackerState.brokenGlassInitialized = false
	perkTrackerState.brokenGlassSeen = {}
	perkTrackerState.brokenGlassEvents = {}
	perkTrackerState.sirenSlowEvents = {}
	perkTrackerState.sirenLosExposure = 0
	perkTrackerState.sirenSlowObservedThisHunt = false
	perkTrackerState.lastLosLightingKey = nil
	perkTrackerState.lastLosTarget = nil
	perkTrackerState.dullahanSpeedSamples = {}
	perkTrackerState.dullahanIncreaseEvents = {}
	perkTrackerState.dullahanHadQualifiedWindow = false
	perkTrackerState.dullahanPatternDetected = preserveFindings
		and perkDetections.Dullahan ~= nil
	perkTrackerState.dullahanPatternObservedThisHunt = false
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
	perkTrackerState.ravagerGhost = ghost
	perkTrackerState.ravagerLastGhostPosition = nil
	perkTrackerState.ravagerLastGhostSampleAt = nil
	perkTrackerState.ravagerDetectedThisHunt = false
	perkTrackerState.saltPendingTouches = {}
	perkTrackerState.saltOverlapAccumulator = 0
	perkTrackerState.wraithRuledOut = false
	perkTrackerState.holyOilColorStates =
		setmetatable({}, {__mode = "k"})
	perkTrackerState.holyOilBurningSince =
		setmetatable({}, {__mode = "k"})
	perkTrackerState.orbObserved = false
	perkTrackerState.lidarVisibleObserved = false
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
	if not preserveFindings then
		perkTrackerState.ruledOutGhosts = {}
		refreshPerkLogs()
	end

	if ghost then
			task.delay(0.3, function()
			if closed
				or ghostCoordinator
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
	local transparency
	if ghost then
		-- Preserve the binary false value; an and/or expression would turn it
		-- into nil and make visible samples depend on descendant rendering state.
		transparency = ghost:GetAttribute("Transparency")
	end
	if typeof(transparency) == "boolean" then
		return transparency
	end
	if typeof(transparency) == "number" then
		return transparency >= 0.5
	end
	if not ghost then
		return nil
	end
	local observedVisualPart = false
	for _, descendant in ipairs(ghost:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Name ~= "HumanoidRootPart" then
			observedVisualPart = true
			if descendant.Transparency < 0.95 then
				return false
			end
		end
	end
	return observedVisualPart and true or nil
end
local function getAverageTeamEnergy()
	local players = Services.Players:GetPlayers()
	local playerCount = #players
	if playerCount == 0 then
		return nil
	end
	local total = 0
	for _, targetPlayer in ipairs(players) do
		local energy = targetPlayer:GetAttribute("Energy")
		if typeof(energy) ~= "number" then
			return nil
		end
		total = total + energy
	end
	return total / playerCount
end
perkTrackerState.queueWendigoTransition = function(hunting, now)
	if perkTrackerState.wendigoLastQueuedHunting == hunting then
		return false
	end
	perkTrackerState.wendigoLastQueuedHunting = hunting
	perkTrackerState.wendigoTransitionSequence =
		perkTrackerState.wendigoTransitionSequence + 1
	local sequence = perkTrackerState.wendigoTransitionSequence
	local sanity = getAverageTeamEnergy()
	if typeof(sanity) ~= "number" then
		return false
	end
	local ghost = perkTrackerState.ghost
	if not ghost then
		return false
	end
	local pending = perkTrackerState.wendigoPendingTransitions
	table.insert(pending, {
		Ghost = ghost,
		Sequence = sequence,
		Sanity = sanity,
		Hunting = hunting,
		TransitionAt = now,
		CaptureAt = now + 0.1,
		ExpiresAt = now + 0.65,
	})
	while #pending > 4 do
		table.remove(pending, 1)
	end
	return true
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
			local countBeforeBoundingBox = #parts
			for _, child in ipairs(boundingBox:GetChildren()) do
				if child:IsA("BasePart") and child.Name == "Part" then
					addPart(child)
				end
			end
			if #parts == countBeforeBoundingBox then
				for _, child in ipairs(boundingBox:GetChildren()) do
					if child:IsA("BasePart") then
						addPart(child)
					end
				end
			end
			if #parts == countBeforeBoundingBox then
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
local function getMapSizeName()
	local map = workspace:FindFirstChild("Map")
	local value = map and map:GetAttribute("MapSize") or "Small"
	local normalized = string.lower(tostring(value))
	if normalized == "large" then
		return "Large"
	elseif normalized == "medium" then
		return "Medium"
	end
	return "Small"
end
local function getGhostWalkSpeed(ghost)
	local humanoid = ghost and ghost:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.WalkSpeed or nil
end
local function countOtherAlivePlayers(deadPlayer)
	local count = 0
	for _, targetPlayer in ipairs(Services.Players:GetPlayers()) do
		if targetPlayer ~= deadPlayer
			and targetPlayer:GetAttribute("Dead") ~= true then
			count = count + 1
		end
	end
	return count
end
local function startGhostCoordinator(ghost)
	if ghostCoordinator or not ghost then
		return ghostCoordinator ~= nil
	end
	perkTrackerState.fixedGhostModel = ghost
	local created
	created = GhostPackage.Create({
		Name = "DemonologyGhostCoordinator",
		Profiles = GhostPackage.Profiles,
		Catalog = GhostPackage.Profiles,
		OnChanged = function()
			if created ~= nil
				and ghostCoordinator == created
				and runtimeIsActive()
				and not perkTrackerState.ghostCoreSyncQueued then
				perkTrackerState.ghostCoreSyncQueued = true
				task.defer(function()
					if ghostCoordinator ~= created then
						return
					end
					perkTrackerState.ghostCoreSyncQueued = false
					if runtimeIsActive() then
						syncGhostCoordinatorResults()
					end
				end)
			end
		end,
		OnError = function(failure)
			print("Ghost coordinator: " .. tostring(failure and failure.Error or failure))
		end,
		RuntimeContext = {
			GhostModel = ghost,
			InitialHunting = ghost:GetAttribute("Hunting") == true,
			MapFactor = getMapSizeSpeedFactor(),
			MapSize = getMapSizeName(),
			ValidMultipliers = {0.5, 0.75, 1, 1.25, 1.5, 2},
			ReadHunting = function()
				return ghost:GetAttribute("Hunting") == true
			end,
			ReadAverageSanity = getAverageTeamEnergy,
			ReadWalkSpeed = function()
				return getGhostWalkSpeed(ghost)
			end,
			ReadTransparency = function()
				return getGhostTransparencyState(ghost)
			end,
		},
	})
	ghostCoordinator = created
	local function connectCore(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(perkTrackerState.ghostCoreConnections, connection)
		return connection
	end
	emitGhostObservation = function(event)
		if not ghostCoordinator
			or ghostCoordinator ~= created
			or not runtimeIsActive() then
			return nil
		end
		event = type(event) == "table" and event or {}
		event.Time = tonumber(event.Time) or os.clock()
		if event.Hunting == nil then
			event.Hunting = ghost:GetAttribute("Hunting") == true
		end
		return created:Emit(event)
	end

	connectCore(ghost:GetAttributeChangedSignal("Hunting"), function()
		if perkTrackerState.fixedGhostModel ~= ghost then
			return
		end
		emitGhostObservation({
			Type = GhostPackage.Events.Types.HuntingStateChanged,
			Hunting = ghost:GetAttribute("Hunting") == true,
			AverageSanity = getAverageTeamEnergy(),
			MapFactor = getMapSizeSpeedFactor(),
			MapSize = getMapSizeName(),
			ValidMultipliers = {0.5, 0.75, 1, 1.25, 1.5, 2},
			Transparency = getGhostTransparencyState(ghost),
			Source = "Ghost.Hunting",
		})
	end)
	local lastCoreTransparency = getGhostTransparencyState(ghost)
	local function emitTransparencyChange(source)
		if perkTrackerState.fixedGhostModel ~= ghost then
			return
		end
		local current = getGhostTransparencyState(ghost)
		if type(current) ~= "boolean" or current == lastCoreTransparency then
			return
		end
		lastCoreTransparency = current
		emitGhostObservation({
			Type = GhostPackage.Events.Types.TransparencyChanged,
			Transparency = current,
			Source = source,
		})
	end
	connectCore(ghost:GetAttributeChangedSignal("Transparency"), function()
		emitTransparencyChange("Ghost.Transparency")
	end)
	local transparencyParts = setmetatable({}, {__mode = "k"})
	local function bindTransparencyPart(part)
		if not part:IsA("BasePart")
			or part.Name == "HumanoidRootPart"
			or transparencyParts[part] then
			return
		end
		transparencyParts[part] = true
		connectCore(part:GetPropertyChangedSignal("Transparency"), function()
			task.defer(function()
				emitTransparencyChange("GhostVisual.Transparency")
			end)
		end)
	end
	for _, descendant in ipairs(ghost:GetDescendants()) do
		bindTransparencyPart(descendant)
	end
	connectCore(ghost.DescendantAdded, bindTransparencyPart)
	local boundHumanoid
	local function bindGhostHumanoid(humanoid)
		if not humanoid or humanoid == boundHumanoid then
			return
		end
		boundHumanoid = humanoid
		connectCore(humanoid:GetPropertyChangedSignal("WalkSpeed"), function()
			if perkTrackerState.fixedGhostModel == ghost and humanoid.Parent then
				emitGhostObservation({
					Type = GhostPackage.Events.Types.WalkSpeedChanged,
					CurrentSpeed = humanoid.WalkSpeed,
					Source = "GhostHumanoid.WalkSpeed",
				})
			end
		end)
	end
	bindGhostHumanoid(ghost:FindFirstChildOfClass("Humanoid"))
	connectCore(ghost.ChildAdded, function(child)
		if child:IsA("Humanoid") then
			bindGhostHumanoid(child)
		end
	end)

	local function bindDeathState(targetPlayer)
		connectCore(targetPlayer:GetAttributeChangedSignal("Dead"), function()
			if perkTrackerState.fixedGhostModel ~= ghost
				or targetPlayer:GetAttribute("Dead") ~= true
				or perkTrackerState.ghostCoreDeathSeen[targetPlayer] then
				return
			end
			perkTrackerState.ghostCoreDeathSeen[targetPlayer] = true
			local hunting = ghost:GetAttribute("Hunting") == true
			local otherAlive = countOtherAlivePlayers(targetPlayer)
			emitGhostObservation({
				Type = GhostPackage.Events.Types.PlayerDeath,
				PlayerId = targetPlayer.UserId,
				OtherAlive = otherAlive,
				Unique = true,
				Qualified = hunting and otherAlive > 0,
				ValidMultiplayerKill = hunting and otherAlive > 0,
				Hunting = hunting,
				Source = "Player.Dead",
			})
		end)
	end
	for _, targetPlayer in ipairs(Services.Players:GetPlayers()) do
		bindDeathState(targetPlayer)
	end
	connectCore(Services.Players.PlayerAdded, bindDeathState)
	-- Reconcile the short construction/binding window without introducing a
	-- polling stream. HuntState ignores this when the captured state is current.
	emitGhostObservation({
		Type = GhostPackage.Events.Types.HuntingStateChanged,
		Hunting = ghost:GetAttribute("Hunting") == true,
		AverageSanity = getAverageTeamEnergy(),
		MapFactor = getMapSizeSpeedFactor(),
		MapSize = getMapSizeName(),
		ValidMultipliers = {0.5, 0.75, 1, 1.25, 1.5, 2},
		Transparency = getGhostTransparencyState(ghost),
		Source = "Ghost.StartupReconcile",
	})
	emitGhostObservation({
		Type = GhostPackage.Events.Types.TransparencyChanged,
		Transparency = getGhostTransparencyState(ghost),
		Source = "Ghost.StartupReconcile",
	})
	syncGhostCoordinatorResults()
	return true
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
	if hunting ~= previous then
		if not ghostCoordinator then
			perkTrackerState.queueWendigoTransition(hunting, now)
		end
		perkTrackerState.wispRoomMismatchKey = nil
		perkTrackerState.wispRoomMismatchSince = nil
		perkTrackerState.wispRoomMismatchSamples = 0
		if hunting then
			perkTrackerState.wispRoomNegativeRecordedThisHunt = false
		end
	end
	if hunting and not previous then
		perkTrackerState.evaluateHolyOilAtHuntStart(ghost)
		if perkTrackerState.specterStationaryArmed
			and not perkTrackerState.specterRoomChangePause then
			if ghostCoordinator then
				emitGhostObservation({
					Type = "SpecterTrial",
					TrialId = perkTrackerState.specterActiveTrialId
						or ("specter-hunt:" .. tostring(now)),
					Qualified = true,
					Completed = true,
					FavouriteRoomUnchanged = true,
					ArmedSeconds = math.max(
						5,
						now - (perkTrackerState.specterStationaryCandidateAt or now)
					),
					Outcome = "Residence",
					Source = "FavouriteRoomResidenceCollector",
				})
			else
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
		end
		perkTrackerState.specterStationaryArmed = false
		perkTrackerState.specterStationaryCandidateAt = nil
		perkTrackerState.specterIdleSince = nil
		perkTrackerState.specterActiveTrialId = nil
		perkTrackerState.specterRoomChangePause = false
		perkTrackerState.specterRoomChangeSettleSince = nil
		perkTrackerState.huntStartedAt = now
		perkTrackerState.dullahanSpeedSamples = {}
		perkTrackerState.dullahanIncreaseEvents = {}
		perkTrackerState.dullahanHadQualifiedWindow = false
		perkTrackerState.dullahanPatternObservedThisHunt = false
		perkTrackerState.dullahanCompletedNoIncreaseHunt = false
		perkTrackerState.losSamples = {}
		perkTrackerState.energySamples = {}
		perkTrackerState.lastLosLightingKey = nil
		perkTrackerState.sirenSlowEvents = {}
		perkTrackerState.sirenLosExposure = 0
		perkTrackerState.sirenSlowObservedThisHunt = false
		perkTrackerState.motionSamples = {}
		perkTrackerState.transparencyTransitions = {}
		perkTrackerState.transparencyIntervals = {}
		perkTrackerState.lastTransparencyTransitionTime = nil
		perkTrackerState.phantomPatternRecordedThisHunt = false
		perkTrackerState.phantomQualifiedCyclesThisHunt = 0
		perkTrackerState.phantomMatchedCyclesThisHunt = 0
		perkTrackerState.phantomContradictoryCyclesThisHunt = 0
	elseif not hunting and previous then
		if not ghostCoordinator then
			analyzePhantom(now, true)
		end
		perkTrackerState.huntStartedAt = nil
		if not ghostCoordinator then
			if perkTrackerState.dullahanPatternDetected
				or perkTrackerState.dullahanPatternObservedThisHunt then
				perkTrackerState.dullahanCompletedNoIncreaseHunt = false
			elseif perkTrackerState.dullahanHadQualifiedWindow then
				perkTrackerState.dullahanCompletedNoIncreaseHunt = true
				perkTrackerState.ruleOutGhost(
					"Dullahan",
					"five or more 0.1-second hunt samples contained fewer than three WalkSpeed increases",
					92
				)
			end
		end
		if perkTrackerState.sirenLosExposure >= 4
			and not perkTrackerState.sirenSlowObservedThisHunt then
			if ghostCoordinator then
				emitGhostObservation({
					Type = "LineOfSightPlayerSpeed",
					Hunting = true,
					Qualified = true,
					Completed = true,
					Slowed = false,
					Source = "LineOfSightSpeedCollector",
				})
			else
				perkTrackerState.ruleOutGhost(
					"Siren",
					"the ghost maintained line of sight without attempting to slow the player",
					90
				)
			end
		end
		perkTrackerState.dullahanSpeedSamples = {}
		perkTrackerState.dullahanIncreaseEvents = {}
		perkTrackerState.dullahanHadQualifiedWindow = false
		perkTrackerState.dullahanPatternObservedThisHunt = false
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
local function capturePendingWendigoTransition(ghost, now)
	local pendingTransitions = perkTrackerState.wendigoPendingTransitions
	for index = #pendingTransitions, 1, -1 do
		local pending = pendingTransitions[index]
		local wrongState = not ghost
			or pending.Ghost ~= ghost
			or pending.Sequence ~= perkTrackerState.wendigoTransitionSequence
			or (ghost:GetAttribute("Hunting") == true) ~= pending.Hunting
		if wrongState or now > pending.ExpiresAt then
			table.remove(pendingTransitions, index)
		elseif now >= pending.CaptureAt then
			local humanoid = ghost:FindFirstChildOfClass("Humanoid")
			local walkSpeed = humanoid and humanoid.WalkSpeed or nil
			if typeof(walkSpeed) == "number" and walkSpeed > 0 then
				local snapshots = perkTrackerState.wendigoSnapshots
				table.insert(snapshots, {
					Time = now,
					TransitionAt = pending.TransitionAt,
					Sanity = math.clamp(pending.Sanity, 0, 100),
					Speed = walkSpeed,
					Hunting = pending.Hunting,
				})
				while #snapshots > 3 do
					table.remove(snapshots, 1)
				end
				table.remove(pendingTransitions, index)
			end
		end
	end
end
local function resetWispRoomMismatchCandidate()
	perkTrackerState.wispRoomMismatchKey = nil
	perkTrackerState.wispRoomMismatchSince = nil
	perkTrackerState.wispRoomMismatchSamples = 0
end
local function updateWispOffFavouriteNegative(ghost, hunting, now)
	if not ghost
		or not hunting
		or perkTrackerState.wispRoomNegativeRecordedThisHunt then
		resetWispRoomMismatchCandidate()
		return
	end
	local strongWispDetection = perkDetections.Wisp
	if strongWispDetection
		and (strongWispDetection.Confidence or 0) >= 99 then
		resetWispRoomMismatchCandidate()
		return
	end
	local favouriteName = ghost:GetAttribute("FavoriteRoom")
	local currentName = ghost:GetAttribute("CurrentRoom")
	if type(favouriteName) ~= "string"
		or favouriteName == ""
		or type(currentName) ~= "string"
		or currentName == ""
		or sameRoomName(currentName, favouriteName) then
		resetWispRoomMismatchCandidate()
		return
	end
	local roomsFolder = findRoomsFolder()
	local favouriteRoom = findFavouriteRoom(roomsFolder, favouriteName)
	local currentRoom = findFavouriteRoom(roomsFolder, currentName)
	if not favouriteRoom
		or not currentRoom
		or not instanceIsInsideRoom(ghost, currentRoom)
		or instanceIsInsideRoom(ghost, favouriteRoom) then
		resetWispRoomMismatchCandidate()
		return
	end
	local mismatchKey = string.lower(favouriteRoom.Name)
		.. "\0"
		.. string.lower(currentRoom.Name)
	if perkTrackerState.wispRoomMismatchKey ~= mismatchKey then
		perkTrackerState.wispRoomMismatchKey = mismatchKey
		perkTrackerState.wispRoomMismatchSince = now
		perkTrackerState.wispRoomMismatchSamples = 1
		return
	end
	perkTrackerState.wispRoomMismatchSamples =
		perkTrackerState.wispRoomMismatchSamples + 1
	if perkTrackerState.wispRoomMismatchSamples < 4
		or now - (perkTrackerState.wispRoomMismatchSince or now) < 0.3 then
		return
	end
	perkTrackerState.wispRoomNegativeRecordedThisHunt = true
	resetWispRoomMismatchCandidate()
	if ghostCoordinator then
		emitGhostObservation({
			Type = "HuntRoomRelation",
			Hunting = true,
			Qualified = true,
			InFavouriteRoom = false,
			FavouriteRoom = favouriteRoom.Name,
			CurrentRoom = currentRoom.Name,
			Source = "RoomBoundsCollector",
		})
	end
end
analyzePhantom = function(now, huntEnded)
	local ghost = perkTrackerState.ghost
	if not ghost then
		return
	end
	local function recordPattern(reason, confidence)
		local previousPhantom = perkDetections.Phantom
		local previousPhantomConfidence = previousPhantom
			and previousPhantom.Confidence
		local previousPhantomReason = previousPhantom
			and previousPhantom.Reason
		local previousSkinwalker = perkDetections.Skinwalker
		local previousSkinwalkerConfidence = previousSkinwalker
			and previousSkinwalker.Confidence
		local previousSkinwalkerReason = previousSkinwalker
			and previousSkinwalker.Reason
		perkTrackerState.clearGhostRuleOut("Phantom")
		recordPerkDetection("Phantom", reason, confidence)
		if perkTrackerState.evidenceMode == "Mimicry"
			and not perkTrackerState.isGhostRuledOut("Skinwalker") then
			local mimicReason =
				"Mimicry mode: Skinwalker can copy the observed Phantom blinking and invisible-speed trait"
			if previousSkinwalker
				and previousSkinwalkerReason ~= mimicReason
				and confidence > (previousSkinwalkerConfidence or 0)
				and not perkTrackerState.phantomMimicryPreviousSkinwalkerDetection then
				perkTrackerState.phantomMimicryPreviousSkinwalkerDetection =
					table.clone(previousSkinwalker)
			end
			if not previousSkinwalker
				or previousSkinwalkerReason == mimicReason
				or confidence > (previousSkinwalkerConfidence or 0) then
				recordPerkDetection(
					"Skinwalker",
					mimicReason,
					confidence
				)
			end
			local mimicDetection = perkDetections.Skinwalker
			if mimicDetection and mimicDetection.Reason == mimicReason then
				perkTrackerState.phantomMimicrySkinwalkerClue = true
			end
		end
		local currentPhantom = perkDetections.Phantom
		local currentSkinwalker = perkDetections.Skinwalker
		if (currentPhantom and (
			currentPhantom.Confidence ~= previousPhantomConfidence
				or currentPhantom.Reason ~= previousPhantomReason
		)) or (currentSkinwalker and (
			currentSkinwalker.Confidence ~= previousSkinwalkerConfidence
				or currentSkinwalker.Reason ~= previousSkinwalkerReason
		)) then
			updateGhostIdentification(ghost)
		end
	end

	local replicatedBlinkSpeed = readReplicatedGhostValue(
		ghost,
		"WalkSpeedWhileBlinking"
	)
	if typeof(replicatedBlinkSpeed) == "number"
		and math.abs(replicatedBlinkSpeed - 13.5) <= 0.05 then
		recordPattern(
			"the replicated WalkSpeedWhileBlinking flag was exactly 13.5",
			99
		)
		return
	end

	local samples = {}
	for _, sample in ipairs(perkTrackerState.motionSamples) do
		if sample.Hunting
			and typeof(sample.GhostWalkSpeed) == "number"
			and sample.GhostWalkSpeed > 0
			and typeof(sample.Invisible) == "boolean" then
			table.insert(samples, sample)
		end
	end
	if #samples < 4 then
		return
	end

	local runs = {}
	for _, sample in ipairs(samples) do
		local run = runs[#runs]
		if not run or run.Invisible ~= sample.Invisible then
			if run then
				run.EndTime = sample.Time
			end
			run = {
				Invisible = sample.Invisible,
				StartTime = sample.Time,
				EndTime = nil,
				Samples = {},
			}
			table.insert(runs, run)
		end
		table.insert(run.Samples, sample)
	end
	local lastRun = runs[#runs]
	if lastRun and now - lastRun.StartTime >= 0.18 then
		lastRun.EndTime = now
	end

	local function stablePhaseSpeed(run)
		if not run or not run.EndTime
			or run.EndTime - run.StartTime < 0.15 then
			return nil
		end
		local speeds = {}
		for _, sample in ipairs(run.Samples) do
			if sample.Time >= run.StartTime
				and sample.Time <= run.EndTime then
				table.insert(speeds, sample.GhostWalkSpeed)
			end
		end
		if #speeds < 2 then
			return nil
		end
		local phaseMedian = median(speeds)
		if not phaseMedian
			or standardDeviation(speeds)
				> math.max(0.12, phaseMedian * 0.02) then
			return nil
		end
		return phaseMedian
	end

	local absoluteQualified = 0
	local absoluteMatched = 0
	local matchedVisibleSpeed
	local matchedInvisibleSpeed
	local matchedMultiplier
	local mapFactor = getMapSizeSpeedFactor()
	for index, invisibleRun in ipairs(runs) do
		if not invisibleRun.Invisible then
			continue
		end
		local invisibleSpeed = stablePhaseSpeed(invisibleRun)
		local adjacentVisibleSpeeds = {}
		for _, adjacentIndex in ipairs({index - 1, index + 1}) do
			local visibleRun = runs[adjacentIndex]
			if visibleRun and not visibleRun.Invisible then
				local visibleSpeed = stablePhaseSpeed(visibleRun)
				if visibleSpeed then
					table.insert(adjacentVisibleSpeeds, visibleSpeed)
				end
			end
		end
		local visibleSpeed = median(adjacentVisibleSpeeds)
		if not visibleSpeed or not invisibleSpeed then
			continue
		end
		absoluteQualified = absoluteQualified + 1
		local expectedVisible, visibleError, multiplier =
			closestConfiguredBaseSpeed(visibleSpeed, 11)
		local expectedInvisible = multiplier
			and 13.5 * mapFactor * multiplier
		local ratio = invisibleSpeed / visibleSpeed
		if expectedVisible and expectedInvisible and multiplier
			and visibleError <= math.max(0.15, expectedVisible * 0.025)
			and math.abs(invisibleSpeed - expectedInvisible)
				<= math.max(0.18, expectedInvisible * 0.025)
			and math.abs(ratio - (13.5 / 11)) <= 0.04 then
			absoluteMatched = absoluteMatched + 1
			matchedVisibleSpeed = visibleSpeed
			matchedInvisibleSpeed = invisibleSpeed
			matchedMultiplier = multiplier
		end
	end
	if absoluteMatched >= 1 then
		perkTrackerState.phantomQualifiedCyclesThisHunt = absoluteQualified
		perkTrackerState.phantomMatchedCyclesThisHunt = absoluteMatched
		perkTrackerState.phantomContradictoryCyclesThisHunt = 0
		if not perkTrackerState.phantomPatternRecordedThisHunt then
			perkTrackerState.phantomPatternRecordedThisHunt = true
			perkTrackerState.phantomPatternHunts =
				perkTrackerState.phantomPatternHunts + 1
		end
		local confidence = perkTrackerState.phantomPatternHunts >= 2
			and 99
			or 95
		recordPattern(
			"a stable visible/invisible hunt pair matched the map-scaled Phantom speeds ("
				.. string.format("%.2f", matchedVisibleSpeed)
				.. " visible, "
				.. string.format("%.2f", matchedInvisibleSpeed)
				.. " invisible, "
				.. string.format("%.2fx", matchedMultiplier)
				.. " configured speed)",
			confidence
		)
		return
	end
	if #runs < 3 then
		return
	end

	local function stableRunSpeed(run)
		if not run or not run.EndTime
			or run.EndTime - run.StartTime < 0.35 then
			return nil
		end
		local speeds = {}
		for _, sample in ipairs(run.Samples) do
			if sample.Time >= run.StartTime + 0.12
				and sample.Time <= run.EndTime - 0.08 then
				table.insert(speeds, sample.GhostWalkSpeed)
			end
		end
		if #speeds < 2 then
			return nil
		end
		return median(speeds)
	end

	local qualified = 0
	local matched = 0
	local contradictory = 0
	local matchedRatios = {}
	local invisibleDurations = {}
	for index = 2, #runs - 1 do
		local invisibleRun = runs[index]
		local beforeRun = runs[index - 1]
		local afterRun = runs[index + 1]
		if invisibleRun.Invisible
			and not beforeRun.Invisible
			and not afterRun.Invisible then
			local beforeSpeed = stableRunSpeed(beforeRun)
			local invisibleSpeed = stableRunSpeed(invisibleRun)
			local afterSpeed = stableRunSpeed(afterRun)
			if beforeSpeed and invisibleSpeed and afterSpeed then
				local visibleBaseline = median({beforeSpeed, afterSpeed})
				if visibleBaseline and visibleBaseline > 0 then
					local ratio = invisibleSpeed / visibleBaseline
					qualified = qualified + 1
					table.insert(
						invisibleDurations,
						invisibleRun.EndTime - invisibleRun.StartTime
					)
					if ratio >= 1.15 and ratio <= 1.4 then
						matched = matched + 1
						table.insert(matchedRatios, ratio)
					elseif ratio <= 1.06 then
						contradictory = contradictory + 1
					end
				end
			end
		end
	end
	perkTrackerState.phantomQualifiedCyclesThisHunt = qualified
	perkTrackerState.phantomMatchedCyclesThisHunt = matched
	perkTrackerState.phantomContradictoryCyclesThisHunt = contradictory

	if matched >= 3
		and matched / math.max(qualified, 1) >= 0.75
		and contradictory <= 1 then
		if not perkTrackerState.phantomPatternRecordedThisHunt then
			perkTrackerState.phantomPatternRecordedThisHunt = true
			perkTrackerState.phantomPatternHunts =
				perkTrackerState.phantomPatternHunts + 1
		end
		local ratio = median(matchedRatios) or (13.5 / 11)
		local invisibleDuration = median(invisibleDurations)
		local confidence = perkTrackerState.phantomPatternHunts >= 2
			and 99
			or 95
		recordPattern(
			"three complete visible-invisible-visible hunt cycles showed invisible WalkSpeed about "
				.. tostring(math.floor((ratio - 1) * 100 + 0.5))
				.. "% faster than the adjacent visible baseline"
				.. (invisibleDuration
					and (", with a median invisible interval of "
						.. string.format("%.2f", invisibleDuration)
						.. "s")
					or ""),
			confidence
		)
	elseif huntEnded and qualified >= 3
		and contradictory == qualified then
		perkTrackerState.phantomNoPatternHunts =
			perkTrackerState.phantomNoPatternHunts + 1
		if perkTrackerState.phantomNoPatternHunts >= 2
			and perkTrackerState.phantomPatternHunts == 0 then
			clearPerkDetection("Phantom")
			perkTrackerState.ruleOutGhost(
				"Phantom",
				"two completed hunts each contained three mature blink cycles with no invisible-linked WalkSpeed increase",
				90
			)
			updateGhostIdentification(ghost)
		end
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
		state.specterActiveTrialId = nil
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
		state.specterActiveTrialId = nil
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
			if ghostCoordinator then
				emitGhostObservation({
					Type = "SpecterTrial",
					TrialId = state.specterActiveTrialId
						or ("specter-departure:" .. tostring(now)),
					Qualified = true,
					Completed = true,
					FavouriteRoomUnchanged = true,
					ArmedSeconds = math.max(
						5,
						now - (state.specterStationaryCandidateAt or now)
					),
					Outcome = "Departure",
					Source = "FavouriteRoomResidenceCollector",
				})
			else
				perkTrackerState.ruleOutGhost(
					"Specter",
					"after standing still for five seconds in an unchanged favourite room, the roaming ghost moved before hunting",
					95
				)
			end
		end
		state.specterStationaryCandidateAt = nil
		state.specterIdleSince = nil
		state.specterStationaryArmed = false
		state.specterActiveTrialId = nil
		return
	end

	if not state.specterStationaryCandidateAt then
		state.specterStationaryCandidateAt = now
		return
	end

	if now - state.specterStationaryCandidateAt >= 5
		and not state.specterStationaryArmed then
		state.specterTrialSequence = state.specterTrialSequence + 1
		state.specterActiveTrialId = "specter-trial:"
			.. tostring(state.specterTrialSequence)
		state.specterStationaryArmed = true
	end
end
local function analyzeDullahan(now)
	local state = perkTrackerState
	if state.dullahanPatternDetected then
		return
	end
	local ghost = state.ghost
	local humanoid = ghost and ghost:FindFirstChildOfClass("Humanoid")
	local currentSpeed = humanoid and humanoid.WalkSpeed or nil
	if typeof(currentSpeed) ~= "number" or currentSpeed <= 0 then
		return
	end

	local samples = state.dullahanSpeedSamples
	local previous = samples[#samples]
	local interval = previous and now - previous.Time or nil
	if interval and interval < 0.07 then
		return
	end
	if interval and interval > 0.3 then
		state.dullahanSpeedSamples = {}
		state.dullahanIncreaseEvents = {}
		samples = state.dullahanSpeedSamples
		previous = nil
		interval = nil
	end
	table.insert(samples, {Time = now, Speed = currentSpeed})

	while samples[1] and now - samples[1].Time > 0.7 do
		table.remove(samples, 1)
	end

	local qualifiedWindow = false
	if #samples >= 5 then
		local firstIndex = #samples - 4
		local firstSample = samples[firstIndex]
		local span = now - firstSample.Time
		qualifiedWindow = span >= 0.28 and span <= 0.65
		if qualifiedWindow then
			for index = firstIndex + 1, #samples do
				local sampleInterval = samples[index].Time
					- samples[index - 1].Time
				if sampleInterval < 0.07
					or sampleInterval > 0.3 then
					qualifiedWindow = false
					break
				end
			end
		end
	end
	if qualifiedWindow then
		state.dullahanHadQualifiedWindow = true
	end
	if not qualifiedWindow then
		return
	end

	local increaseEvents = {}
	local firstIndex = #samples - 4
	for index = firstIndex + 1, #samples do
		local before = samples[index - 1]
		local after = samples[index]
		local increase = after.Speed - before.Speed
		if increase >= 0.001 then
			table.insert(increaseEvents, {
				Time = after.Time,
				Delta = increase,
				Speed = after.Speed,
			})
		end
	end
	state.dullahanIncreaseEvents = increaseEvents
	if #increaseEvents < 3 then
		return
	end

	state.dullahanPatternDetected = true
	state.dullahanPatternObservedThisHunt = true
	state.dullahanCompletedNoIncreaseHunt = false
	state.dybbukMaybeReady = false
	perkTrackerState.clearGhostRuleOut("Dullahan")
	clearPerkDetection("Dybbuk")
	recordPerkDetection(
		"Dullahan",
		"Ghost WalkSpeed increased in at least three short intervals across five hunting samples; decreases were ignored",
		PERK_CONFIDENCE.Dullahan
	)
	updateGhostIdentification(ghost)
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
local function analyzeWendigo()
	if perkDetections.Aswang
		or perkDetections.Dullahan
		or perkTrackerState.dullahanPatternDetected then
		return
	end

	local snapshots = perkTrackerState.wendigoSnapshots
	local latest = snapshots[#snapshots]
	if not latest then
		return
	end

	local roundedSanity =
		math.floor(math.clamp(latest.Sanity, 0, 100) + 0.5)
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

		local expectedSpeed = mapFactor * baseSpeed * nearest
		local speedError = math.abs(snapshot.Speed - expectedSpeed)
		local speedTolerance = math.max(0.18, expectedSpeed * 0.02)
		if speedError > speedTolerance then
			invalidReason =
				"observed multiplier "
					.. string.format("%.4f", inferred)
					.. " was outside the allowed replication tolerance for the nearest configured 50%-200% step"
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
				.. " hunt-state transition WalkSpeed snapshot"
				.. (requiredSnapshots == 1 and "" or "s")
				.. " matched the switch-time average-sanity curve within replication tolerance at "
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
local function checkUmbraRootSoundOnce(ghost)
	if not ghost or perkTrackerState.umbraRootSoundChecked then
		return
	end
	local rootHasExtraSound = ghostRootHasAnySound(ghost)
	if rootHasExtraSound == nil then
		return
	end

	-- A valid HumanoidRootPart hierarchy is inspected exactly once.
	perkTrackerState.umbraRootSoundChecked = true
	if rootHasExtraSound then
		clearPerkDetection("Umbra")
		perkTrackerState.ruleOutGhost(
			"Umbra",
			"HumanoidRootPart contained a Sound other than Hunting on the immediate check",
			99
		)
	else
		perkTrackerState.clearGhostRuleOut("Umbra")
		recordPerkDetection(
			"Umbra",
			"HumanoidRootPart contained no Sound other than Hunting on the immediate check",
			PERK_CONFIDENCE.Umbra
		)
	end
	updateGhostIdentification(ghost)
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
				if ghostCoordinator then
					emitGhostObservation({
						Type = "CrossMotion",
						TrialId = model,
						Eligible = true,
						Completed = true,
						FloatedAndRotated = true,
						Source = "CrossMotionCollector",
					})
				else
					recordPerkDetection(
						"Demon",
						"an activated Cross rotated repeatedly and floated upward",
						99
					)
					updateGhostIdentification(state.ghost)
				end
				continue
			end
		end
		if failedBecauseRemoved or now - observation.StartTime >= 4 then
			state.activeCrossBurns[model] = nil
			if not state.demonMotionObserved then
				state.demonRuledOut = true
				if ghostCoordinator then
					emitGhostObservation({
						Type = "CrossMotion",
						TrialId = model,
						Eligible = true,
						Completed = true,
						FloatedAndRotated = false,
						Source = "CrossMotionCollector",
					})
				else
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
	local now = os.clock()
	local pending = perkTrackerState.saltPendingTouches
	local disturbedPosition = perkTrackerState.saltModelPosition(
		disturbedModel
	)
	local observation = pending[disturbedModel]
	if observation and observation.Disturbed then
		return
	end

	local sourceModel = disturbedModel
	if not observation and disturbedPosition then
		local nearestDistance = math.huge
		for saltModel, candidate in pairs(pending) do
			if candidate
				and not candidate.Disturbed
				and candidate.Position
				and now - candidate.StartedAt <= 2.0 then
				local distance = (
					disturbedPosition - candidate.Position
				).Magnitude
				if distance <= 3.5 and distance < nearestDistance then
					observation = candidate
					sourceModel = saltModel
					nearestDistance = distance
				end
			end
		end
	end

	if not observation then
		local ghost = getGhostModel()
		local ghostPosition = ghost and ghost:GetPivot().Position or nil
		local ghostOffset = ghostPosition and disturbedPosition
			and (ghostPosition - disturbedPosition)
			or nil
		if not ghost
			or not ghostPosition
			or not disturbedPosition
			or not ghostOffset
			or Vector3.new(ghostOffset.X, 0, ghostOffset.Z).Magnitude > 3.5
			or math.abs(ghostOffset.Y) > 5 then
			return
		end
		local preSpeed, preSampleCount, baselineReliable =
			perkTrackerState.recentSaltPreSpeed(ghost, now)
		observation = {
			ContactId = disturbedModel,
			DirectContact = false,
			StartedAt = now,
			TouchAt = now,
			Position = disturbedPosition,
			PreSpeed = preSpeed,
			PreSampleCount = preSampleCount,
			BaselineReliable = baselineReliable,
			SpeedSamples = {},
			LastSpeedSampleAt = nil,
			Ghost = ghost,
			HuntingAtTouch = ghost:GetAttribute("Hunting") == true,
			Disturbed = false,
			WraithResolved = false,
			AswangResolved = false,
			AswangSlowObserved = false,
			AswangSlowAt = nil,
			AswangMinimumSpeed = nil,
			Phase = "AwaitDisturbance",
			Synthetic = true,
		}
	end

	if sourceModel ~= disturbedModel then
		pending[sourceModel] = nil
	end
	pending[disturbedModel] = observation
	observation.ContactId = observation.ContactId or sourceModel
	observation.Position = disturbedPosition or observation.Position
	observation.Disturbed = true
	observation.DisturbedAt = now
	observation.SpeedSamples = observation.SpeedSamples or {}
	observation.Phase = "SeekDrop"
	observation.WraithResolved = true
	emitGhostObservation({
		Type = GhostPackage.Events.Types.SaltDisturbed,
		ContactId = observation.ContactId,
		DirectContact = observation.DirectContact == true,
		Disturbed = true,
		SaltDisturbed = true,
		DisturbedContactId = observation.ContactId,
		Hunting = observation.HuntingAtTouch == true
			and observation.Ghost:GetAttribute("Hunting") == true,
		Source = "SaltPiles.DisturbedSaltLine",
	})
	if observation.DirectContact == true
		and observation.HuntingAtTouch == true
		and observation.Ghost:GetAttribute("Hunting") == true then
		emitGhostObservation({
			Type = GhostPackage.Events.Types.SaltContact,
			ContactId = observation.ContactId,
			DirectContact = true,
			Disturbed = true,
			SaltDisturbed = true,
			DisturbedContactId = observation.ContactId,
			Qualified = true,
			Hunting = true,
			Source = "SaltPiles.QualifiedHuntingContact",
		})
	end
	if not ghostCoordinator and observation.DirectContact == true then
		perkTrackerState.wraithRuledOut = true
		perkTrackerState.ruleOutGhost(
			"Wraith",
			"the same touched SaltLine became DisturbedSaltLine",
			99
		)
		updateGhostIdentification(perkTrackerState.ghost)
	end
end
perkTrackerState.recentSaltPreSpeed = function(ghost, now)
	local recentSpeeds = {}
	local currentHunting = ghost and ghost:GetAttribute("Hunting") == true
	for index = #perkTrackerState.motionSamples, 1, -1 do
		local sample = perkTrackerState.motionSamples[index]
		if sample.Time < now - 0.9 then
			break
		end
		if typeof(sample.Hunting) == "boolean"
			and sample.Hunting ~= currentHunting then
			break
		end
		if sample.Time <= now - 0.03
			and typeof(sample.GhostWalkSpeed) == "number"
			and sample.GhostWalkSpeed > 0 then
			table.insert(recentSpeeds, sample.GhostWalkSpeed)
		end
	end
	if #recentSpeeds > 0 then
		return median(table.clone(recentSpeeds)),
			#recentSpeeds,
			#recentSpeeds >= 3
	end
	local humanoid = ghost and ghost:FindFirstChildOfClass("Humanoid")
	local liveSpeed = humanoid and humanoid.WalkSpeed or nil
	if typeof(liveSpeed) == "number" and liveSpeed > 0 then
		return liveSpeed, 0, false
	end
	return nil, 0, false
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
	if existing and now - existing.StartedAt < 3.5 then
		return
	end
	local preSpeed, preSampleCount, baselineReliable =
		perkTrackerState.recentSaltPreSpeed(ghost, now)
	perkTrackerState.saltPendingTouches[saltModel] = {
		ContactId = saltModel,
		DirectContact = true,
		StartedAt = now,
		TouchAt = now,
		Position = perkTrackerState.saltModelPosition(saltModel),
		PreSpeed = preSpeed,
		PreSampleCount = preSampleCount,
		BaselineReliable = baselineReliable,
		SpeedSamples = {},
		LastSpeedSampleAt = nil,
		Ghost = ghost,
		HuntingAtTouch = ghost:GetAttribute("Hunting") == true,
		Disturbed = false,
		WraithResolved = false,
		AswangResolved = false,
		AswangSlowObserved = false,
		AswangSlowAt = nil,
		AswangMinimumSpeed = nil,
		Phase = "AwaitDisturbance",
		Synthetic = false,
	}
	emitGhostObservation({
		Type = GhostPackage.Events.Types.SaltContact,
		ContactId = saltModel,
		DirectContact = true,
		Disturbed = false,
		SaltDisturbed = false,
		Hunting = ghost:GetAttribute("Hunting") == true,
		Source = "SaltLine.Touched",
	})
end
perkTrackerState.bindSaltLine = function(model, emitDisturbance)
	if not model or not model:IsA("Model") then
		return
	end
	if model.Name == "DisturbedSaltLine" then
		if emitDisturbance then
			perkTrackerState.markSaltDisturbed(model)
		end
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
		perkTrackerState.saltPendingTouches = {}
	end
	if not folder or perkTrackerState.saltTrackerInitialized then
		return
	end
	perkTrackerState.saltTrackerInitialized = true
	for _, child in ipairs(folder:GetChildren()) do
		perkTrackerState.bindSaltLine(child, false)
	end
	connect(folder.ChildAdded, function(child)
		task.defer(function()
			if not closed and child.Parent == folder then
				perkTrackerState.bindSaltLine(child, true)
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
		if not ghostCoordinator then
		if observation.Disturbed then
			perkTrackerState.wraithRuledOut = true
			perkTrackerState.ruleOutGhost(
				"Wraith",
				"the same touched SaltLine became DisturbedSaltLine",
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
			and observation.Disturbed
			and observation.Ghost == ghost
			and typeof(observation.HuntingAtTouch) == "boolean"
			and observation.HuntingAtTouch ~= hunting then
			observation.AswangResolved = true
		end
		if not observation.AswangResolved
			and observation.Ghost == ghost
			and hunting
			and observation.HuntingAtTouch == true
			and typeof(currentSpeed) == "number"
			and currentSpeed > 0
			and (
				not observation.LastSpeedSampleAt
				or now - observation.LastSpeedSampleAt >= 0.075
			) then
			observation.LastSpeedSampleAt = now
			observation.SpeedSamples = observation.SpeedSamples or {}
			table.insert(observation.SpeedSamples, {
				Time = now,
				Speed = currentSpeed,
				Disturbed = observation.Disturbed == true,
			})
		end
		if not observation.AswangResolved
			and observation.Disturbed
			and observation.Ghost == ghost
			and hunting
			and observation.HuntingAtTouch == true
			and observation.BaselineReliable
			and typeof(observation.PreSpeed) == "number"
			and observation.PreSpeed > 0
			and typeof(currentSpeed) == "number"
			and currentSpeed > 0 then
			local disturbedAge = now - observation.DisturbedAt
			local dropCount = 0
			local noDropCount = 0
			local latestSlowAt
			local minimumSpeed = math.huge
			for _, speedSample in ipairs(observation.SpeedSamples or {}) do
				local ratio = speedSample.Speed / observation.PreSpeed
				minimumSpeed = math.min(minimumSpeed, speedSample.Speed)
				if ratio <= 0.9 then
					dropCount = dropCount + 1
					latestSlowAt = speedSample.Time
				end
				if ratio >= 0.94 then
					noDropCount = noDropCount + 1
				end
			end
			if dropCount >= 2 and not observation.AswangSlowObserved then
				observation.AswangSlowObserved = true
				observation.AswangSlowAt = latestSlowAt
				observation.AswangMinimumSpeed = minimumSpeed
				observation.Phase = "SeekRecovery"
				perkTrackerState.clearGhostRuleOut("Aswang")
				recordPerkDetection(
					"Aswang",
					"during the same hunt, direct salt contact disturbed the pile and produced a repeated WalkSpeed drop below the pre-touch baseline",
					95
				)
				updateGhostIdentification(ghost)
			end
			if observation.AswangSlowObserved then
				local recoveryCount = 0
				local slowAt = observation.AswangSlowAt or now
				local lowSpeed = observation.AswangMinimumSpeed or minimumSpeed
				for _, speedSample in ipairs(observation.SpeedSamples or {}) do
					if speedSample.Time >= slowAt + 0.15
						and speedSample.Speed >= observation.PreSpeed * 0.95
						and speedSample.Speed >= lowSpeed * 1.08 then
						recoveryCount = recoveryCount + 1
					end
				end
				if recoveryCount >= 2 then
					observation.AswangResolved = true
					observation.Phase = "Recovered"
					perkTrackerState.clearGhostRuleOut("Aswang")
					recordPerkDetection(
						"Aswang",
						"during one hunt, the ghost touched and disturbed salt, temporarily slowed across repeated samples, then recovered to its pre-touch WalkSpeed",
						99
					)
					updateGhostIdentification(ghost)
				end
			elseif disturbedAge >= 4
				and #(observation.SpeedSamples or {}) >= 10
				and noDropCount == #(observation.SpeedSamples or {})
				and not perkDetections.Aswang then
				observation.AswangResolved = true
				clearPerkDetection("Aswang")
				perkTrackerState.ruleOutGhost(
					"Aswang",
					"a verified hunting salt contact disturbed the pile, but a full four-second sample showed no temporary WalkSpeed drop",
					90
				)
				updateGhostIdentification(ghost)
			end
		end
		else
			observation.WraithResolved = true
			observation.AswangResolved = true
		end
		local observationAge = now
			- (observation.DisturbedAt or observation.StartedAt)
		if observationAge >= 6.5
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

perkTrackerState.evaluateHolyOilWallStates = function(ghost)
	ghost = ghost or getGhostModel()
	if not ghost or ghost:GetAttribute("Hunting") ~= true then
		return nil
	end
	local sawEligibleWall = false
	local sawNonCollidable = false
	local now = os.clock()

	for model in pairs(perkTrackerState.holyOilTrackedModels) do
		if model.Parent
			and model:GetAttribute("Burning") == true
			and now - (perkTrackerState.holyOilBurningSince[model] or now)
				>= 0.12 then
			local wall = perkTrackerState.getHolyOilWall(model)
			if wall then
				sawEligibleWall = true
				emitGhostObservation({
					Type = "HolyOilCollision",
					ModelId = model,
					Hunting = true,
					Burning = true,
					Qualified = true,
					CanCollide = wall.CanCollide,
					Source = "HolyOil.GhostWall",
				})
				if wall.CanCollide == false then
					sawNonCollidable = true
				end
			end
		end
	end
	if ghostCoordinator then
		if sawNonCollidable then
			return true
		elseif sawEligibleWall then
			return false
		end
		return nil
	end

	if sawNonCollidable then
		perkTrackerState.clearGhostRuleOut("Wisp")
		recordPerkDetection(
			"Wisp",
			"while the ghost was hunting and HolyOil was Burning, that model's GhostWall.CanCollide was false",
			99
		)
		updateGhostIdentification(ghost)
		return true
	elseif sawEligibleWall then
		clearPerkDetection("Wisp")
		perkTrackerState.ruleOutGhost(
			"Wisp",
			"while the ghost was hunting and HolyOil was Burning, every eligible GhostWall remained collidable",
			99
		)
		return false
	end
	return nil
end

perkTrackerState.evaluateHolyOilColor = function(model, ghost)
	if not model
		or not model.Parent
		or not ghost
		or ghost:GetAttribute("Hunting") ~= true
		or model:GetAttribute("Burning") ~= true
		or os.clock() - (perkTrackerState.holyOilBurningSince[model] or os.clock())
			< 0.12 then
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
	emitGhostObservation({
		Type = "HolyOilColor",
		ModelId = model,
		Hunting = true,
		Burning = true,
		Qualified = true,
		Stable = true,
		Blue = kind == "Spirit",
		Source = "HolyOil.ParticleColor",
	})
	if ghostCoordinator then
		return kind
	end

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

perkTrackerState.bindHolyOilModel = function(model)
	if not model
		or not model:IsA("Model")
		or model.Name ~= "HolyOil"
		or perkTrackerState.holyOilTrackedModels[model] then
		return
	end

	perkTrackerState.holyOilTrackedModels[model] = true

	local function updateBurnState()
		perkTrackerState.holyOilColorStates[model] = nil
		local ghost = getGhostModel()
		if model:GetAttribute("Burning") == true then
			perkTrackerState.holyOilBurningSince[model] =
				perkTrackerState.holyOilBurningSince[model] or os.clock()
			if ghost
				and ghost:GetAttribute("Hunting") == true then
				perkTrackerState.evaluateHolyOilColor(model, ghost)
			end
		else
			perkTrackerState.holyOilBurningSince[model] = nil
		end
		perkTrackerState.evaluateHolyOilWallStates(ghost)
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
				function()
					perkTrackerState.evaluateHolyOilWallStates()
				end
			)
		end
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
	connect(model.DescendantRemoving, function(descendant)
		if descendant.Name == "GhostWall" then
			task.defer(function()
				if not closed then
					perkTrackerState.evaluateHolyOilWallStates()
				end
			end)
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
		perkTrackerState.holyOilBurningSince =
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

	perkTrackerState.evaluateHolyOilWallStates(ghost)

	for model in pairs(perkTrackerState.holyOilTrackedModels) do
		if model.Parent
			and model:GetAttribute("Burning") == true then
			perkTrackerState.holyOilColorStates[model] = nil
			perkTrackerState.evaluateHolyOilColor(model, ghost)
		end
	end
end

perkTrackerState.updateHolyOilTracker = function(
	_deltaTime,
	ghost,
	_now
)
	perkTrackerState.ensureHolyOilTracker()
	if not ghost or ghost:GetAttribute("Hunting") ~= true then
		return
	end
	local folder = perkTrackerState.holyOilFolder
	if not folder then
		return
	end
	perkTrackerState.evaluateHolyOilWallStates(ghost)
	for model in pairs(perkTrackerState.holyOilTrackedModels) do
		if model.Parent then
			if model:GetAttribute("Burning") == true then
				perkTrackerState.evaluateHolyOilColor(model, ghost)
			else
				perkTrackerState.holyOilColorStates[model] = nil
			end
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
	if roomItemPlacementState.busy
		or now < (perkTrackerState.automationMutationUntil or 0) then
		perkTrackerState.pendingObjectTeleports = {}
		perkTrackerState.recentSmokeEffects = {}
		for object, previous in pairs(perkTrackerState.objectTeleportObjects) do
			if object.Parent
				and (object.Parent.Name == "Items"
					or object.Parent.Name == "Interactables") then
				local position = getInstanceWorldPosition(object)
				if position then
					previous.Position = position
					previous.Time = now
					previous.Room = perkTrackerState.roomNameAtPosition(position)
				end
			end
		end
		perkTrackerState.objectTeleportAccumulator = 0
		return
	end
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
			if ghostCoordinator then
				emitGhostObservation({
					Type = "ObjectTeleportResult",
					TeleportId = pending.Object,
					ConfirmedTeleport = true,
					Completed = true,
					SmokeFound = true,
					Source = "ObjectTeleportCollector",
				})
			else
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
			end
			table.remove(
				perkTrackerState.pendingObjectTeleports,
				index
			)
		elseif now >= pending.ResolveAt then
			if ghostCoordinator then
				emitGhostObservation({
					Type = "ObjectTeleportResult",
					TeleportId = pending.Object,
					ConfirmedTeleport = true,
					Completed = true,
					SmokeFound = false,
					Source = "ObjectTeleportCollector",
				})
				emitGhostObservation({
					Type = "MimickedAbility",
					Ability = "Entity object teleport",
					Qualified = true,
					Confidence = 97,
					Source = "ObjectTeleportCollector",
				})
			else
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
			end
			table.remove(
				perkTrackerState.pendingObjectTeleports,
				index
			)
		end
	end
end
local function resetRavagerMotionState(ghost)
	perkTrackerState.ravagerTrackedObjects =
		setmetatable({}, {__mode = "k"})
	perkTrackerState.ravagerMotionEvents = {}
	perkTrackerState.ravagerScanAccumulator = 0
	perkTrackerState.ravagerGhost = ghost
	perkTrackerState.ravagerLastGhostPosition = nil
	perkTrackerState.ravagerLastGhostSampleAt = nil
	perkTrackerState.ravagerDetectedThisHunt = false
end
local function ravagerRootPosition(rootObject)
	local representative
	if rootObject:IsA("BasePart") then
		if not rootObject.Anchored and rootObject.Transparency < 1 then
			representative = rootObject
		end
	elseif rootObject:IsA("Model") then
		local primaryPart = rootObject.PrimaryPart
		if primaryPart
			and not primaryPart.Anchored
			and primaryPart.Transparency < 1 then
			representative = primaryPart
		else
			for _, descendant in ipairs(rootObject:GetDescendants()) do
				if descendant:IsA("BasePart")
					and not descendant.Anchored
					and descendant.Transparency < 1 then
					representative = descendant
					break
				end
			end
		end
	end
	if not representative then
		return nil, nil
	end
	return representative.Position, representative.AssemblyRootPart or representative
end
local function resetRavagerCandidate(tracked)
	tracked.Window = {}
	tracked.CandidateStartedAt = nil
	tracked.ConsecutiveBad = 0
end
perkTrackerState.updateRavagerTracker = function(deltaTime, ghost, now)
	local state = perkTrackerState
	local hunting = ghost and ghost:GetAttribute("Hunting") == true
	if roomItemPlacementState.busy
		or now < (state.automationMutationUntil or 0)
		or not ghost
		or not hunting then
		if state.ravagerGhost ~= ghost
			or state.ravagerLastGhostPosition ~= nil
			or state.ravagerDetectedThisHunt
			or next(state.ravagerTrackedObjects) ~= nil then
			resetRavagerMotionState(ghost)
		else
			state.ravagerScanAccumulator = 0
		end
		return
	end
	if state.ravagerGhost ~= ghost then
		resetRavagerMotionState(ghost)
	end
	if state.ravagerDetectedThisHunt then
		return
	end
	state.ravagerScanAccumulator = state.ravagerScanAccumulator + deltaTime
	if state.ravagerScanAccumulator < 0.1 then
		return
	end
	state.ravagerScanAccumulator = state.ravagerScanAccumulator % 0.1

	local ghostPosition = ghost:GetPivot().Position
	local previousGhostPosition = state.ravagerLastGhostPosition
	local previousGhostTime = state.ravagerLastGhostSampleAt
	state.ravagerLastGhostPosition = ghostPosition
	state.ravagerLastGhostSampleAt = now
	if previousGhostPosition
		and previousGhostTime
		and now - previousGhostTime <= 0.2
		and (ghostPosition - previousGhostPosition).Magnitude > 8 then
		state.ravagerTrackedObjects = setmetatable({}, {__mode = "k"})
		state.ravagerMotionEvents = {}
		return
	end

	local folders = {}
	local seenFolders = setmetatable({}, {__mode = "k"})
	local map = workspace:FindFirstChild("Map")
	for _, container in ipairs({workspace, map}) do
		if container then
			for _, folderName in ipairs({"Items", "Interactable", "Interactables"}) do
				local folder = container:FindFirstChild(folderName)
				if folder and not seenFolders[folder] then
					seenFolders[folder] = true
					table.insert(folders, folder)
				end
			end
		end
	end

	local seenRoots = setmetatable({}, {__mode = "k"})
	local qualified = {}
	for _, folder in ipairs(folders) do
		for _, rootObject in ipairs(folder:GetChildren()) do
			local position, assembly = ravagerRootPosition(rootObject)
			if position and assembly then
				seenRoots[rootObject] = true
				local relative = position - ghostPosition
				local tracked = state.ravagerTrackedObjects[rootObject]
				if not tracked then
					tracked = {
						Window = {},
						CandidateStartedAt = nil,
						ConsecutiveBad = 0,
					}
					state.ravagerTrackedObjects[rootObject] = tracked
				end
				local previousPosition = tracked.Position
				local previousRelative = tracked.Relative
				local previousTime = tracked.Time
				tracked.Position = position
				tracked.Relative = relative
				tracked.Time = now
				tracked.Assembly = assembly

				if previousPosition and previousRelative and previousTime then
					local elapsed = now - previousTime
					local oldFlat = Vector3.new(
						previousRelative.X,
						0,
						previousRelative.Z
					)
					local newFlat = Vector3.new(relative.X, 0, relative.Z)
					local oldRadius = oldFlat.Magnitude
					local newRadius = newFlat.Magnitude
					local relativeStep = (newFlat - oldFlat).Magnitude
					local geometryValid = elapsed >= 0.06
						and elapsed <= 0.2
						and oldRadius >= 2.5
						and oldRadius <= 40
						and newRadius >= 2.5
						and newRadius <= 40
						and relativeStep <= 12
					local orbitLike = false
					local signedAngle = 0
					local relativeSpeed = 0
					local worldSpeed = 0
					if geometryValid then
						local dot = oldFlat.X * newFlat.X
							+ oldFlat.Z * newFlat.Z
						local cross = oldFlat.X * newFlat.Z
							- oldFlat.Z * newFlat.X
						signedAngle = math.deg(math.atan2(cross, dot))
						local velocity = (newFlat - oldFlat) / elapsed
						relativeSpeed = velocity.Magnitude
						worldSpeed = (position - previousPosition).Magnitude / elapsed
						local radialUnit = newFlat.Unit
						local radialSpeed = math.abs(velocity:Dot(radialUnit))
						local tangentialSpeed = math.sqrt(math.max(
							relativeSpeed * relativeSpeed
								- radialSpeed * radialSpeed,
							0
						))
						local tangentialShare = tangentialSpeed
							/ math.max(relativeSpeed, 0.001)
						local radiusChange = math.abs(newRadius - oldRadius)
						local meanRadius = (oldRadius + newRadius) * 0.5
						orbitLike = worldSpeed >= 4
							and relativeSpeed >= 6
							and math.abs(signedAngle) / elapsed >= 70
							and tangentialShare >= 0.55
							and radiusChange <= math.max(2, meanRadius * 0.35)
					end

					if not geometryValid then
						resetRavagerCandidate(tracked)
					elseif orbitLike or tracked.CandidateStartedAt then
						if orbitLike and not tracked.CandidateStartedAt then
							tracked.CandidateStartedAt = previousTime
						end
						table.insert(tracked.Window, {
							StartAt = previousTime,
							Time = now,
							Good = orbitLike,
							SignedAngle = orbitLike and signedAngle or 0,
							AbsAngle = orbitLike and math.abs(signedAngle) or 0,
							Speed = orbitLike and relativeSpeed or 0,
						})
						tracked.ConsecutiveBad = orbitLike
							and 0
							or tracked.ConsecutiveBad + 1
						for index = #tracked.Window, 1, -1 do
							if now - tracked.Window[index].Time > 0.8 then
								table.remove(tracked.Window, index)
							end
						end
						if tracked.ConsecutiveBad > 2 or #tracked.Window == 0 then
							resetRavagerCandidate(tracked)
						else
							tracked.CandidateStartedAt = tracked.Window[1].StartAt
							local goodIntervals = 0
							local signedTotal = 0
							local absoluteTotal = 0
							local fastest = 0
							for _, interval in ipairs(tracked.Window) do
								if interval.Good then
									goodIntervals = goodIntervals + 1
									signedTotal = signedTotal + interval.SignedAngle
									absoluteTotal = absoluteTotal + interval.AbsAngle
									fastest = math.max(fastest, interval.Speed)
								end
							end
							local duration = now - tracked.CandidateStartedAt
							local intervalCount = #tracked.Window
							if duration >= 0.5
								and intervalCount >= 5
								and goodIntervals / intervalCount >= 0.7
								and absoluteTotal >= 45
								and math.abs(signedTotal)
									/ math.max(absoluteTotal, 0.001) >= 0.65 then
								table.insert(qualified, {
									Root = rootObject,
									Assembly = assembly,
									Direction = signedTotal >= 0 and 1 or -1,
									Duration = duration,
									Intervals = intervalCount,
									GoodShare = goodIntervals / intervalCount,
									AngularTotal = absoluteTotal,
									Speed = fastest,
								})
							end
						end
					end
				end
			end
		end
	end
	for rootObject in pairs(state.ravagerTrackedObjects) do
		if not seenRoots[rootObject] or not rootObject.Parent then
			state.ravagerTrackedObjects[rootObject] = nil
		end
	end
	state.ravagerMotionEvents = qualified

	local buckets = {
		[1] = {},
		[-1] = {},
	}
	local assemblies = {
		[1] = setmetatable({}, {__mode = "k"}),
		[-1] = setmetatable({}, {__mode = "k"}),
	}
	for _, event in ipairs(qualified) do
		local direction = event.Direction
		if not assemblies[direction][event.Assembly] then
			assemblies[direction][event.Assembly] = true
			table.insert(buckets[direction], event)
		end
	end
	for _, direction in ipairs({1, -1}) do
		local matching = buckets[direction]
		if #matching >= 3 then
			local minimumDuration = math.huge
			local minimumIntervals = math.huge
			local minimumGoodShare = math.huge
			local minimumAngle = math.huge
			for _, event in ipairs(matching) do
				minimumDuration = math.min(minimumDuration, event.Duration)
				minimumIntervals = math.min(minimumIntervals, event.Intervals)
				minimumGoodShare = math.min(minimumGoodShare, event.GoodShare)
				minimumAngle = math.min(minimumAngle, event.AngularTotal)
			end
			state.ravagerDetectedThisHunt = true
			if ghostCoordinator then
				emitGhostObservation({
					Type = "VortexPattern",
					Hunting = true,
					Qualified = true,
					DistinctObjects = #matching,
					Duration = minimumDuration,
					Intervals = minimumIntervals,
					GoodShare = minimumGoodShare,
					AccumulatedAngle = minimumAngle,
					Source = "ItemOrbitCollector",
				})
			else
				state.clearGhostRuleOut("Ravager")
				recordPerkDetection(
					"Ravager",
					tostring(#matching)
						.. " distinct items rapidly orbited the moving ghost for at least "
						.. string.format("%.2f", minimumDuration)
						.. " seconds",
					99
				)
				updateGhostIdentification(ghost)
			end
			return
		end
	end
end

local function updateObservablePerkTrackers(deltaTime)
	local ghost = getGhostModel()
	perkTrackerState.updateRavagerTracker(deltaTime, ghost, os.clock())
	perkTrackerState.sampleAccumulator = perkTrackerState.sampleAccumulator + deltaTime
	perkTrackerState.slowScanAccumulator = perkTrackerState.slowScanAccumulator + deltaTime
	perkTrackerState.analysisAccumulator = perkTrackerState.analysisAccumulator + deltaTime
	if perkTrackerState.sampleAccumulator < 0.1 then
		return
	end
	perkTrackerState.sampleAccumulator =
		perkTrackerState.sampleAccumulator % 0.1
	local now = os.clock()
	local currentMap = workspace:FindFirstChild("Map")
	if not ghost and perkTrackerState.ghost then
		perkTrackerState.ghostMissingSince =
			perkTrackerState.ghostMissingSince or now
		if currentMap ~= nil
			and perkTrackerState.roundMap == currentMap then
			return
		end
	elseif ghost then
		perkTrackerState.ghostMissingSince = nil
	end
	local mapChanged = perkTrackerState.roundMap ~= nil
		and currentMap ~= perkTrackerState.roundMap
	if mapChanged or ghost ~= perkTrackerState.ghost then
		local preserveFindings = ghost ~= nil
			and perkTrackerState.ghost ~= nil
			and not mapChanged
			and currentMap ~= nil
			and perkTrackerState.roundMap == currentMap
		resetPerkTrackerForGhost(ghost, preserveFindings)
	end
	if not ghost then
		return
	end
	if not ghostCoordinator then
		evidenceRoundGhost = ghost
		startGhostCoordinator(ghost)
	end
	if not ghostCoordinator then
		checkUmbraRootSoundOnce(ghost)
	end
	perkTrackerState.ensureCrossDemonTracker()
	perkTrackerState.updateCrossDemonTracker(now)
	local hunting = ghost:GetAttribute("Hunting") == true
	perkTrackerState.updateLeviathanLightTracker(ghost, hunting, 0.1, now)
	if not ghostCoordinator then
		perkTrackerState.updateVexState(ghost)
	end
	perkTrackerState.updateSaltTracker(0.1, ghost, hunting, now)
	perkTrackerState.updateHolyOilTracker(0.1, ghost, now)
	perkTrackerState.updateObjectTeleportTracker(0.1, now)
	handleHuntTransition(ghost, hunting, now)
	updateWispOffFavouriteNegative(ghost, hunting, now)
	if not ghostCoordinator then
		capturePendingWendigoTransition(ghost, now)
	end
	if hunting and not ghostCoordinator then
		analyzeDullahan(now)
	end
	if not ghostCoordinator then
		handleMultiplayerDeaths(ghost, hunting, now)
	end
	if not perkTrackerState.entityTrackerInitialized then
		perkTrackerState.entityTrackerInitialized = true
		perkTrackerState.ensureObjectTeleportTracker()
	end
	if perkTrackerState.slowScanAccumulator >= 0.5 then
		perkTrackerState.slowScanAccumulator = 0
		if scanBansheeGlassBurst(now) then
			if ghostCoordinator then
				emitGhostObservation({
					Type = "BrokenGlassBurst",
					Qualified = true,
					Count = #perkTrackerState.brokenGlassEvents,
					Window = 2.5,
					Source = "BrokenGlassCollector",
				})
			else
				recordPerkDetection(
					"Banshee",
					"two or more new BrokenGlass models appeared within 2.5 seconds",
					PERK_CONFIDENCE.Banshee
				)
			end
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
				if ghostCoordinator then
					emitGhostObservation({
						Type = "GhostTeleportResult",
						ConfirmedTeleport = true,
						Completed = true,
						Ambiguous = true,
						FromRoom = pendingTeleport.FromRoom,
						ToRoom = currentRoom,
						Qualified = true,
						Source = "GhostRoomTeleportCollector",
					})
					emitGhostObservation({
						Type = "MimickedAbility",
						Ability = "room-to-room ghost teleport",
						Qualified = true,
						Confidence = 65,
						Source = "GhostRoomTeleportCollector",
					})
				else
					perkTrackerState.teleportResolvedGhost = "Ambiguous"
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
	if perkTrackerState.analysisAccumulator >= 0.2 then
		perkTrackerState.analysisAccumulator = 0
		perkTrackerState.analyzeSpecter(ghost, hunting, measuredSpeed, now)
		if hunting and not ghostCoordinator then
			analyzePhantom(now)
			analyzeOni(now)
		end
		if not ghostCoordinator then
			analyzeWendigo()
		end
		if not ghostCoordinator then
			perkTrackerState.updateDybbukMaybe(ghost)
		end
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
		if ghostCoordinator then
			emitGhostObservation({
				Type = "LineOfSightPlayerSpeed",
				Hunting = true,
				Qualified = true,
				Slowed = true,
				Source = "LineOfSightSpeedCollector",
			})
		else
			perkTrackerState.clearGhostRuleOut("Siren")
			recordPerkDetection(
				"Siren",
				"player WalkSpeed was reduced in line of sight while lighting stayed "
					.. lightingDescription(roomName, roomLit)
			)
		end
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
local function teleportToRoomBoundingBoxCenter(room, options)
	options = options or {}
	local function teleportIsActive()
		if type(options.IsActive) ~= "function" then
			return true
		end
		local ok, active = pcall(options.IsActive)
		return ok and active == true
	end
	local character = player.Character
	local root =
		character and character:FindFirstChild("HumanoidRootPart")
	local humanoid =
		character and character:FindFirstChildOfClass("Humanoid")

	if not room or not character or not root or not humanoid
		or not teleportIsActive() then
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
	end

	local ghost = getGhostModel()
	if ghost then
		table.insert(excludedInstances, ghost)
	end
	if ghostProxyModel then
		table.insert(excludedInstances, ghostProxyModel)
	end

	local standingOffset =
		humanoid.HipHeight + root.Size.Y * 0.5 + 0.12
	local footprintHalfX = root.Size.X * 0.5 + 0.22
	local footprintHalfZ = root.Size.Z * 0.5 + 0.22
	local avatarRadius =
		math.max(footprintHalfX, footprintHalfZ) + 0.18
	local horizontalInset =
		math.sqrt(footprintHalfX ^ 2 + footprintHalfZ ^ 2) + 0.18
	local bodyHeight = math.max(
		root.Size.Y + humanoid.HipHeight + 2.35,
		5.1
	)
	local bodyProbeSize = Vector3.new(
		math.max(root.Size.X + 0.72, 2.3),
		bodyHeight,
		math.max(root.Size.Z + 0.72, 2.3)
	)
	local bodyGeometryProbe = nil
	local preferredPositions = options.PreferredPositions or {}
	local targetPosition = options.TargetPosition
	local maximumTargetDistance = tonumber(options.MaximumTargetDistance)
	local maximumPreferredDistance = tonumber(options.MaximumPreferredDistance)
	local candidateValidator = options.CandidateValidator
	local function candidatePassesCustomValidation(position)
		if type(candidateValidator) ~= "function" then
			return true
		end
		local ok, allowed = pcall(candidateValidator, position)
		return ok and allowed == true
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = excludedInstances
	overlapParams.MaxParts = 0
	pcall(function()
		overlapParams.RespectCanCollide = true
	end)

	local function safelyInsideXZ(position, boundingPart)
		local localPosition =
			boundingPart.CFrame:PointToObjectSpace(position)
		local half = boundingPart.Size * 0.5

		return math.abs(localPosition.X)
			<= math.max(0, half.X - horizontalInset)
			and math.abs(localPosition.Z)
				<= math.max(0, half.Z - horizontalInset)
	end

	local function isCollidableInstance(instance)
		if instance == workspace.Terrain then
			return true
		end
		return instance
			and instance:IsA("BasePart")
			and instance.CanCollide
	end

	local function newRaycastParams(excludes)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = excludes
		raycastParams.IgnoreWater = true
		pcall(function()
			raycastParams.RespectCanCollide = true
		end)
		return raycastParams
	end

	local function raycastFirstCollidable(
		origin,
		direction,
		additionalExcludes
	)
		local excludes = table.clone(excludedInstances)
		for _, instance in ipairs(additionalExcludes or {}) do
			if instance and instance ~= workspace.Terrain then
				table.insert(excludes, instance)
			end
		end
		local raycastParams = newRaycastParams(excludes)
		local seen = setmetatable({}, {__mode = "k"})

		for _ = 1, 12 do
			raycastParams.FilterDescendantsInstances = excludes
			local result = workspace:Raycast(
				origin,
				direction,
				raycastParams
			)
			if not result then
				return nil
			end
			if isCollidableInstance(result.Instance) then
				return result
			end
			if not result.Instance
				or result.Instance == workspace.Terrain
				or seen[result.Instance] then
				return nil
			end
			seen[result.Instance] = true
			table.insert(excludes, result.Instance)
		end

		return nil
	end

	local footprintOffsets = {
		Vector3.zero,
		Vector3.new(footprintHalfX, 0, 0),
		Vector3.new(-footprintHalfX, 0, 0),
		Vector3.new(0, 0, footprintHalfZ),
		Vector3.new(0, 0, -footprintHalfZ),
		Vector3.new(footprintHalfX, 0, footprintHalfZ),
		Vector3.new(footprintHalfX, 0, -footprintHalfZ),
		Vector3.new(-footprintHalfX, 0, footprintHalfZ),
		Vector3.new(-footprintHalfX, 0, -footprintHalfZ),
	}

	local function inspectFootprint(floorPosition)
		local supportHits = 0
		local flatSupportHits = 0
		local centerSupported = false
		local supportSet = setmetatable({}, {__mode = "k"})

		for index, offset in ipairs(footprintOffsets) do
			local result = raycastFirstCollidable(
				floorPosition + offset + Vector3.new(0, 1.35, 0),
				Vector3.new(0, -2.85, 0)
			)
			if result and result.Normal.Y >= 0.5 then
				local heightDifference = math.abs(
					result.Position.Y - floorPosition.Y
				)
				if heightDifference <= 0.9 then
					supportHits = supportHits + 1
					if index == 1 then
						centerSupported = true
					end
				end
				if heightDifference <= 0.38 then
					supportSet[result.Instance] = true
					if result.Normal.Y >= 0.62 then
						flatSupportHits = flatSupportHits + 1
					end
				end
			end
		end

		return {
			CenterSupported = centerSupported,
			SupportHits = supportHits,
			FlatSupportHits = flatSupportHits,
			SupportSet = supportSet,
		}
	end

	local function worldHalfExtents(part)
		local half = part.Size * 0.5
		local frame = part.CFrame
		return Vector3.new(
			math.abs(frame.XVector.X) * half.X
				+ math.abs(frame.YVector.X) * half.Y
				+ math.abs(frame.ZVector.X) * half.Z,
			math.abs(frame.XVector.Y) * half.X
				+ math.abs(frame.YVector.Y) * half.Y
				+ math.abs(frame.ZVector.Y) * half.Z,
			math.abs(frame.XVector.Z) * half.X
				+ math.abs(frame.YVector.Z) * half.Y
				+ math.abs(frame.ZVector.Z) * half.Z
		)
	end

	local function inspectBodyArea(candidate, floorY, supportSet)
		local probeBottom = floorY + 0.12
		local probeTop = probeBottom + bodyProbeSize.Y
		local probe = CFrame.new(
			candidate.X,
			probeBottom + bodyProbeSize.Y * 0.5,
			candidate.Z
		)
		local blockerCount = 0
		local coreBlockers = 0
		local penalty = 0
		local intersectingParts = nil
		if bodyGeometryProbe and bodyGeometryProbe.Parent then
			bodyGeometryProbe.CFrame = probe
			bodyGeometryProbe.Size = bodyProbeSize
			local exactOk, exactParts = pcall(function()
				return workspace:GetPartsInPart(
					bodyGeometryProbe,
					overlapParams
				)
			end)
			bodyGeometryProbe.CFrame = CFrame.new(0, -100000, 0)
			if exactOk then
				intersectingParts = exactParts
			end
		end
		if not intersectingParts then
			intersectingParts = workspace:GetPartBoundsInBox(
				probe,
				bodyProbeSize,
				overlapParams
			)
		end

		for _, part in ipairs(intersectingParts) do
			if part:IsA("BasePart")
				and part.CanCollide
				and part ~= bodyGeometryProbe
				and not boundingPartSet[part] then
				local halfExtents = worldHalfExtents(part)
				local partBottom = part.Position.Y - halfExtents.Y
				local partTop = part.Position.Y + halfExtents.Y
				local supportOnly = supportSet[part]
					and partTop <= floorY + 0.45
				local belowFeet = partTop <= floorY + 0.24

				if not supportOnly and not belowFeet then
					blockerCount = blockerCount + 1
					local distanceX = math.max(
						math.abs(part.Position.X - candidate.X)
							- halfExtents.X,
						0
					)
					local distanceZ = math.max(
						math.abs(part.Position.Z - candidate.Z)
							- halfExtents.Z,
						0
					)
					local horizontalDistance = math.sqrt(
						distanceX ^ 2 + distanceZ ^ 2
					)
					local verticalOverlap = math.max(
						0,
						math.min(partTop, probeTop)
							- math.max(partBottom, probeBottom)
					)
					local core = horizontalDistance
						<= avatarRadius * 0.55
					if core then
						coreBlockers = coreBlockers + 1
					end
					penalty = penalty
						+ 900
						+ verticalOverlap * 420
						+ (core and 4200 or 0)
						+ (partBottom < floorY + 1.25 and 650 or 0)
				end
			end
		end

		return {
			BlockerCount = blockerCount,
			CoreBlockers = coreBlockers,
			Penalty = penalty,
		}
	end

	local clearanceDirections = {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
		Vector3.new(1, 0, 1).Unit,
		Vector3.new(1, 0, -1).Unit,
		Vector3.new(-1, 0, 1).Unit,
		Vector3.new(-1, 0, -1).Unit,
	}

	local function horizontalClearance(candidate, floorY, supportSet)
		local supportExcludes = {}
		for instance in pairs(supportSet) do
			if instance ~= workspace.Terrain then
				table.insert(supportExcludes, instance)
			end
		end

		local minimum = 9
		for _, height in ipairs({0.75, 2.65}) do
			local origin = Vector3.new(
				candidate.X,
				floorY + height,
				candidate.Z
			)
			for _, direction in ipairs(clearanceDirections) do
				local result = raycastFirstCollidable(
					origin,
					direction * 9,
					supportExcludes
				)
				if result then
					minimum = math.min(minimum, result.Distance)
				end
			end
		end

		return minimum
	end

	local function calculateRisk(
		bodyInspection,
		footprintInspection,
		clearance
	)
		return bodyInspection.Penalty
			+ bodyInspection.CoreBlockers * 10000
			+ bodyInspection.BlockerCount * 500
			+ (#footprintOffsets
				- footprintInspection.FlatSupportHits) * 180
			+ (#footprintOffsets
				- footprintInspection.SupportHits) * 70
			+ math.max(0, 2.1 - clearance) * 120
	end

	local function assessCandidate(candidate)
		candidate.Position = candidate.FloorPosition
			+ Vector3.new(0, standingOffset, 0)
		if targetPosition and maximumTargetDistance then
			local targetOffset = Vector3.new(
				candidate.Position.X - targetPosition.X,
				0,
				candidate.Position.Z - targetPosition.Z
			)
			if targetOffset.Magnitude > maximumTargetDistance then
				return false
			end
		end
		candidate.PreferredDistance = candidate.CenterDistance
		if #preferredPositions > 0 then
			candidate.PreferredDistance = math.huge
			for _, preferred in ipairs(preferredPositions) do
				local offset = Vector3.new(
					candidate.Position.X - preferred.X,
					0,
					candidate.Position.Z - preferred.Z
				)
				candidate.PreferredDistance = math.min(
					tonumber(candidate.PreferredDistance) or math.huge,
					offset.Magnitude
				)
			end
		end
		if maximumPreferredDistance
			and candidate.PreferredDistance > maximumPreferredDistance then
			return false
		end
		if not candidatePassesCustomValidation(candidate.Position) then
			return false
		end
		if not safelyInsideXZ(
			candidate.Position,
			candidate.BoundingPart
		) then
			return false
		end

		local footprintInspection = inspectFootprint(
			candidate.FloorPosition
		)
		if not footprintInspection.CenterSupported then
			return false
		end

		local bodyInspection = inspectBodyArea(
			candidate.Position,
			candidate.FloorPosition.Y,
			footprintInspection.SupportSet
		)
		local clearance = horizontalClearance(
			candidate.Position,
			candidate.FloorPosition.Y,
			footprintInspection.SupportSet
		)

		candidate.SupportHits = footprintInspection.SupportHits
		candidate.FlatSupportHits =
			footprintInspection.FlatSupportHits
		candidate.SupportSet = footprintInspection.SupportSet
		candidate.BlockerCount = bodyInspection.BlockerCount
		candidate.CoreBlockers = bodyInspection.CoreBlockers
		candidate.BlockerPenalty = bodyInspection.Penalty
		candidate.Clearance = clearance
		candidate.StrictSafe = candidate.NormalY >= 0.62
			and candidate.FlatSupportHits == #footprintOffsets
			and candidate.BlockerCount == 0
		candidate.Risk = calculateRisk(
			bodyInspection,
			footprintInspection,
			clearance
		)
		return true
	end

	local rawCandidates = {}
	local minimumBottomByBoundingPart = setmetatable({}, {__mode = "k"})
	local function addColumnCandidates(
		boundingPart,
		localX,
		localZ,
		rippleOrder
	)
		local half = boundingPart.Size * 0.5
		local origin = boundingPart.CFrame:PointToWorldSpace(
			Vector3.new(localX, half.Y + 24, localZ)
		)
		local direction = Vector3.new(
			0,
			-(boundingPart.Size.Y + 72),
			0
		)
		local columnExcludes = table.clone(excludedInstances)
		local raycastParams = newRaycastParams(columnExcludes)
		local pierced = setmetatable({}, {__mode = "k"})

		for _ = 1, 8 do
			raycastParams.FilterDescendantsInstances = columnExcludes
			local result = workspace:Raycast(
				origin,
				direction,
				raycastParams
			)
			if not result then
				break
			end

			local instance = result.Instance
			if isCollidableInstance(instance)
				and result.Normal.Y >= 0.5 then
				local localFloor =
					boundingPart.CFrame:PointToObjectSpace(
						result.Position
					)
				local bottomDistance = localFloor.Y + half.Y
				if bottomDistance >= -1.5
					and bottomDistance
						<= boundingPart.Size.Y + 1.5 then
					local candidate = {
						FloorPosition = result.Position,
						Surface = instance,
						BoundingPart = boundingPart,
						BottomDistance = bottomDistance,
						NormalY = result.Normal.Y,
						CenterDistance = math.sqrt(
							localX ^ 2 + localZ ^ 2
						),
						RippleOrder = rippleOrder or 0,
						SampleOrder = #rawCandidates + 1,
					}
					candidate.SearchDistance = candidate.CenterDistance
					if #preferredPositions > 0 then
						candidate.SearchDistance = math.huge
						for _, preferred in ipairs(preferredPositions) do
							local offset = Vector3.new(
								result.Position.X - preferred.X,
								0,
								result.Position.Z - preferred.Z
							)
							candidate.SearchDistance = math.min(
								candidate.SearchDistance,
								offset.Magnitude
							)
						end
					end
					table.insert(rawCandidates, candidate)
					minimumBottomByBoundingPart[boundingPart] = math.min(
						minimumBottomByBoundingPart[boundingPart]
							or math.huge,
						bottomDistance
					)
				end
			end

			if not instance
				or instance == workspace.Terrain
				or pierced[instance] then
				break
			end
			pierced[instance] = true
			table.insert(columnExcludes, instance)
		end
	end

	-- Build the original adaptive coverage, but inspect it like a ripple:
	-- exact center first, then each progressively farther center ring.
	for _, boundingPart in ipairs(boundingParts) do
		local usableX =
			math.max(0, boundingPart.Size.X - horizontalInset * 2)
		local usableZ =
			math.max(0, boundingPart.Size.Z - horizontalInset * 2)

		if usableX > 0 and usableZ > 0 then
			local spacing = math.max(avatarRadius * 1.65, 2)
			local xCount = math.clamp(
				math.ceil(usableX / spacing) + 1,
				6,
				12
			)
			local zCount = math.clamp(
				math.ceil(usableZ / spacing) + 1,
				3,
				10
			)
			local samplePoints = {}
			local sampledColumns = {}
			local function queueSample(localX, localZ)
				local key = string.format("%.3f:%.3f", localX, localZ)
				if sampledColumns[key] then
					return
				end
				sampledColumns[key] = true
				table.insert(samplePoints, {
					X = localX,
					Z = localZ,
					Radius = math.sqrt(localX ^ 2 + localZ ^ 2),
					BuildOrder = #samplePoints + 1,
				})
			end

			queueSample(0, 0)
			for _, preferred in ipairs(preferredPositions) do
				local localPreferred =
					boundingPart.CFrame:PointToObjectSpace(preferred)
				if math.abs(localPreferred.X) <= usableX * 0.5 + 0.05
					and math.abs(localPreferred.Z) <= usableZ * 0.5 + 0.05 then
					queueSample(localPreferred.X, localPreferred.Z)
				end
			end
			for xIndex = 1, xCount do
				local xRatio = (xIndex - 0.5) / xCount - 0.5
				local localX = xRatio * usableX

				for zIndex = 1, zCount do
					local zRatio = (zIndex - 0.5) / zCount - 0.5
					local localZ = zRatio * usableZ
					queueSample(localX, localZ)
				end
			end
			table.sort(samplePoints, function(left, right)
				if math.abs(left.Radius - right.Radius) > 0.01 then
					return left.Radius < right.Radius
				end
				return left.BuildOrder < right.BuildOrder
			end)
			for rippleOrder, point in ipairs(samplePoints) do
				addColumnCandidates(
					boundingPart,
					point.X,
					point.Z,
					rippleOrder
				)
				if rippleOrder % 12 == 0 then
					Services.RunService.Heartbeat:Wait()
				end
			end
		end
	end

	if #rawCandidates == 0 then
		return false,
			"no grounded floor point was found inside the room"
	end

	bodyGeometryProbe = Instance.new("Part")
	bodyGeometryProbe.Name = "__DemonologyTeleportProbe"
	bodyGeometryProbe.Anchored = true
	bodyGeometryProbe.CanCollide = false
	bodyGeometryProbe.CanTouch = false
	bodyGeometryProbe.CanQuery = true
	bodyGeometryProbe.CastShadow = false
	bodyGeometryProbe.Transparency = 1
	bodyGeometryProbe.Size = bodyProbeSize
	bodyGeometryProbe.CFrame = CFrame.new(0, -100000, 0)
	bodyGeometryProbe.Parent = workspace
	table.insert(excludedInstances, bodyGeometryProbe)
	overlapParams.FilterDescendantsInstances = excludedInstances
	local function destroyBodyGeometryProbe()
		if bodyGeometryProbe then
			bodyGeometryProbe:Destroy()
			bodyGeometryProbe = nil
		end
	end

	local function surfaceLooksLikeGround(surface)
		if surface == workspace.Terrain then
			return true
		end
		if not surface
			or not surface:IsA("BasePart")
			or surface.Transparency >= 0.95 then
			return false
		end

		local name = string.lower(surface.Name)
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
				return false
			end
		end

		return true
	end

	local candidatePools = {{}, {}, {}, {}}
	for _, candidate in ipairs(rawCandidates) do
		local minimumBottom =
			minimumBottomByBoundingPart[candidate.BoundingPart]
				or candidate.BottomDistance
		local inGroundBand = candidate.BottomDistance
			<= minimumBottom + 1
		local looksLikeGround = surfaceLooksLikeGround(
			candidate.Surface
		)
		if inGroundBand then
			candidate.GroundTier = looksLikeGround and 0 or 1
		else
			candidate.GroundTier = looksLikeGround and 2 or 3
		end
		table.insert(candidatePools[candidate.GroundTier + 1], candidate)
	end

	local candidates = {}
	local evaluated = setmetatable({}, {__mode = "k"})
	local evaluationCount = 0
	local function evaluateCandidate(candidate)
		if not candidate or evaluated[candidate] then
			return
		end
		evaluated[candidate] = true
		evaluationCount = evaluationCount + 1
		if assessCandidate(candidate) then
			table.insert(candidates, candidate)
		end
		if evaluationCount % 6 == 0 then
			Services.RunService.Heartbeat:Wait()
		end
	end
	local strictCandidateCount = 0
	local function evaluatePool(pool)
		if #pool == 0 then
			return false
		end
		table.sort(pool, function(left, right)
			if math.abs(left.SearchDistance - right.SearchDistance) > 0.01 then
				return left.SearchDistance < right.SearchDistance
			end
			if left.RippleOrder ~= right.RippleOrder then
				return left.RippleOrder < right.RippleOrder
			end
			return left.SampleOrder < right.SampleOrder
		end)
		local completionRadius
		for index, candidate in ipairs(pool) do
			evaluateCandidate(candidate)
			if candidate.StrictSafe and candidate.CoreBlockers == 0 then
				strictCandidateCount = strictCandidateCount + 1
				if strictCandidateCount >= 3 and not completionRadius then
					completionRadius = candidate.SearchDistance
				end
			end
			if completionRadius
				and index < #pool
				and pool[index + 1].SearchDistance > completionRadius + 0.05 then
				return true
			end
		end
		return strictCandidateCount > 0
	end

	-- Expand from the center (or requested target) until several strict retry
	-- points are available. If no strict point exists, exhaust the ripple so
	-- the risk fallback truly is the safest assessed option.
	for _, pool in ipairs(candidatePools) do
		evaluatePool(pool)
		if strictCandidateCount >= 3 then
			break
		end
	end

	if #candidates == 0 then
		destroyBodyGeometryProbe()
		return false,
			"no grounded destination passed the detailed room checks"
	end

	table.sort(candidates, function(left, right)
		local leftCoreFree = left.CoreBlockers == 0
		local rightCoreFree = right.CoreBlockers == 0
		if leftCoreFree ~= rightCoreFree then
			return leftCoreFree
		end
		if left.GroundTier ~= right.GroundTier then
			return left.GroundTier < right.GroundTier
		end
		if left.StrictSafe ~= right.StrictSafe then
			return left.StrictSafe
		end
		if left.StrictSafe then
			if math.abs(left.PreferredDistance - right.PreferredDistance) > 0.05 then
				return left.PreferredDistance < right.PreferredDistance
			end
			local bottomDifference = math.abs(
				left.BottomDistance - right.BottomDistance
			)
			if bottomDifference > 0.25 then
				return left.BottomDistance < right.BottomDistance
			end
			if math.abs(left.Clearance - right.Clearance) > 0.1 then
				return left.Clearance > right.Clearance
			end
			return left.SampleOrder < right.SampleOrder
		end
		if left.CoreBlockers ~= right.CoreBlockers then
			return left.CoreBlockers < right.CoreBlockers
		end
		if left.BlockerCount ~= right.BlockerCount then
			return left.BlockerCount < right.BlockerCount
		end
		if math.abs(left.Risk - right.Risk) > 1 then
			return left.Risk < right.Risk
		end
		if math.abs(left.PreferredDistance - right.PreferredDistance) > 0.05 then
			return left.PreferredDistance < right.PreferredDistance
		end
		if left.FlatSupportHits ~= right.FlatSupportHits then
			return left.FlatSupportHits > right.FlatSupportHits
		end
		if left.SupportHits ~= right.SupportHits then
			return left.SupportHits > right.SupportHits
		end
		local bottomDifference = math.abs(
			left.BottomDistance - right.BottomDistance
		)
		if bottomDifference > 0.25 then
			return left.BottomDistance < right.BottomDistance
		end
		if math.abs(left.Clearance - right.Clearance) > 0.1 then
			return left.Clearance > right.Clearance
		end
		return left.SampleOrder < right.SampleOrder
	end)

	local lookTarget = options.LookAtPosition
	local fixedLook = options.LookDirection and Vector3.new(
		options.LookDirection.X,
		0,
		options.LookDirection.Z
	) or nil
	local firstCandidate = candidates[1]
	local look = fixedLook and fixedLook or (lookTarget and Vector3.new(
		lookTarget.X - firstCandidate.Position.X,
		0,
		lookTarget.Z - firstCandidate.Position.Z
	) or Vector3.new(
		root.CFrame.LookVector.X,
		0,
		root.CFrame.LookVector.Z
	))
	if look.Magnitude < 0.05 then
		look = Vector3.new(
			firstCandidate.BoundingPart.CFrame.LookVector.X,
			0,
			firstCandidate.BoundingPart.CFrame.LookVector.Z
		)
	end
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit

	local originalPivot = character:GetPivot()
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

	local strictTeleportAttempts = 0
	local fallbackTeleportAttempts = 0
	local function tryCandidate(candidate, requireStrict)
		if not teleportIsActive()
			or not root.Parent
			or not humanoid.Parent
			or not assessCandidate(candidate)
			or candidate.CoreBlockers > 0
			or (requireStrict and not candidate.StrictSafe) then
			return false
		end

		if requireStrict then
			if strictTeleportAttempts >= 10 then
				return false
			end
			strictTeleportAttempts = strictTeleportAttempts + 1
		else
			if fallbackTeleportAttempts >= 12 then
				return false
			end
			fallbackTeleportAttempts = fallbackTeleportAttempts + 1
		end
		local expectedRisk = candidate.Risk
		local expectedSupportHits = candidate.SupportHits
		local destinationLook = look
		if fixedLook and fixedLook.Magnitude >= 0.05 then
			destinationLook = fixedLook.Unit
		elseif lookTarget then
			local targeted = Vector3.new(
				lookTarget.X - candidate.Position.X,
				0,
				lookTarget.Z - candidate.Position.Z
			)
			if targeted.Magnitude >= 0.05 then
				destinationLook = targeted.Unit
			end
		end
		local destination = CFrame.lookAt(
			candidate.Position,
			candidate.Position + destinationLook
		)
		local moved = pcall(function()
			character:PivotTo(destination)
		end)
		if not moved then
			return false
		end

		for _ = 1, 3 do
			if not teleportIsActive() or not root.Parent then
				return false
			end
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			Services.RunService.Heartbeat:Wait()
		end

		local settledFloorPosition = Vector3.new(
			root.Position.X,
			root.Position.Y - standingOffset,
			root.Position.Z
		)
		if not candidatePassesCustomValidation(root.Position) then
			return false
		end
		local footprintInspection = inspectFootprint(
			settledFloorPosition
		)
		if not footprintInspection.CenterSupported
			or not safelyInsideXZ(
				root.Position,
				candidate.BoundingPart
			) then
			return false
		end

		local bodyInspection = inspectBodyArea(
			root.Position,
			settledFloorPosition.Y,
			footprintInspection.SupportSet
		)
		local clearance = horizontalClearance(
			root.Position,
			settledFloorPosition.Y,
			footprintInspection.SupportSet
		)
		local settledStrict = candidate.NormalY >= 0.62
			and footprintInspection.FlatSupportHits
				== #footprintOffsets
			and bodyInspection.BlockerCount == 0
			and bodyInspection.CoreBlockers == 0

		if requireStrict then
			return settledStrict
		end

		local settledRisk = calculateRisk(
			bodyInspection,
			footprintInspection,
			clearance
		)
		return bodyInspection.CoreBlockers == 0
			and footprintInspection.SupportHits
			>= math.max(1, expectedSupportHits - 1)
			and settledRisk <= expectedRisk + 750
	end

	local selected = nil
	local strictModes = options.RequireStrict and {true} or {true, false}
	for _, requireStrict in ipairs(strictModes) do
		for groundTier = 0, 3 do
			for _, candidate in ipairs(candidates) do
				if candidate.GroundTier == groundTier
					and candidate.StrictSafe == requireStrict
					and tryCandidate(candidate, requireStrict) then
					selected = candidate
					break
				end
			end
			if selected then
				break
			end
		end
		if selected then
			break
		end
	end

	if not selected then
		if root.Parent and character.Parent then
			pcall(function()
				character:PivotTo(originalPivot)
			end)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			Services.RunService.Heartbeat:Wait()
		end
		local releaseMovement = options.ReleaseMovementOnCancel == true
			and not teleportIsActive()
		if root.Parent then
			root.Anchored = if releaseMovement then false else originalAnchored
		end
		if humanoid.Parent then
			humanoid.PlatformStand = if releaseMovement
				then false
				else originalPlatformStand
			humanoid.AutoRotate = if releaseMovement
				then true
				else originalAutoRotate
			for state, enabled in pairs(disabledStates) do
				pcall(function()
					humanoid:SetStateEnabled(
						state,
						releaseMovement and true or enabled
					)
				end)
			end
			if releaseMovement then
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end)
			end
		end
		destroyBodyGeometryProbe()
		return false,
			releaseMovement and "teleport was cancelled"
				or "no grounded destination remained stable during teleport"
	end
	if not teleportIsActive() then
		local releaseMovement = options.ReleaseMovementOnCancel == true
		if root.Parent and character.Parent then
			pcall(function()
				character:PivotTo(originalPivot)
			end)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = if releaseMovement then false else originalAnchored
		end
		if humanoid.Parent then
			humanoid.PlatformStand = if releaseMovement
				then false
				else originalPlatformStand
			humanoid.AutoRotate = if releaseMovement
				then true
				else originalAutoRotate
			for state, enabled in pairs(disabledStates) do
				pcall(function()
					humanoid:SetStateEnabled(
						state,
						releaseMovement and true or enabled
					)
				end)
			end
			if releaseMovement then
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end)
			end
		end
		destroyBodyGeometryProbe()
		return false, "teleport was cancelled"
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

	destroyBodyGeometryProbe()
	return true, nil
end

local function teleportToBaseCamp(options)
	local room = findBaseCampRoom()
	if not room then
		return false, "Base Camp room was not found"
	end
	options = table.clone(options or {})
	if type(options.PreferredPositions) ~= "table"
		or #options.PreferredPositions == 0 then
		local preferredPosition
		local doors = workspace:FindFirstChild("Doors")
		if doors then
			for _, object in ipairs(doors:GetDescendants()) do
				local normalized = string.lower(object.Name):gsub("[^%w]", "")
				local doorType = string.lower(tostring(
					object:GetAttribute("DoorType")
						or object:GetAttribute("Type")
						or ""
				)):gsub("[^%w]", "")
				if string.find(normalized, "exitdoor", 1, true)
					or object:GetAttribute("IsExitDoor") == true
					or object:GetAttribute("ExitDoor") == true
					or doorType == "exit"
					or doorType == "exitdoor" then
					preferredPosition = getInstanceWorldPosition(object)
					if preferredPosition then
						break
					end
				end
			end
		end
		if not preferredPosition then
			local truck = room:FindFirstChild("Truck", true)
				or workspace:FindFirstChild("Truck", true)
			preferredPosition = getInstanceWorldPosition(truck)
		end
		if preferredPosition then
			-- Candidate safety still wins; this only chooses the safest Base Camp
			-- bound/point nearest the exit, with Truck as the requested fallback.
			options.PreferredPositions = {preferredPosition}
		end
	end
	return teleportToRoomBoundingBoxCenter(room, options)
end
local function teleportToFavouriteRoom(options)
	local ghost = getGhostModel()
	local roomsFolder = findRoomsFolder()
	local roomName = ghost and ghost:GetAttribute("FavoriteRoom") or nil
	local room = findFavouriteRoom(roomsFolder, roomName)
	if not room then
		return false, "Favourite room was not found: " .. tostring(roomName)
	end
	return teleportToRoomBoundingBoxCenter(room, options)
end
local function placeItemsInFavouriteRoom(owner)
	if roomItemPlacementState.busy or closed then
		return false, "room item setup is already running"
	end
	roomItemPlacementState.busy = true
	roomItemPlacementState.generation =
		roomItemPlacementState.generation + 1
	local operationGeneration =
		roomItemPlacementState.generation
	roomItemPlacementState.owner = owner or "Manual"
	roomItemPlacementState.lastResult = nil
	roomItemPlacementState.lastError = nil
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
			guardedWait(0.1)
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
		local function itemIsConsumedCross(object)
			if not object
				or normalizeItemName(storedItemName(object))
					~= normalizeItemName("Cross") then
				return false
			end
			local function consumed(candidate)
				return candidate:GetAttribute("Burned") == true
					or candidate:GetAttribute("Burnt") == true
					or candidate:GetAttribute("Consumed") == true
					or candidate:GetAttribute("Used") == true
					or tonumber(candidate:GetAttribute("Uses")) == 0
			end
			if consumed(object) then
				return true
			end
			for _, descendant in ipairs(object:GetDescendants()) do
				if consumed(descendant) then
					return true
				end
			end
			return false
		end
		local function currentFavouriteRoom()
			local ghost = getGhostModel()
			return findFavouriteRoom(
				findRoomsFolder(),
				ghost and ghost:GetAttribute("FavoriteRoom") or nil
			)
		end
		local roomItemOverlapParams = OverlapParams.new()
		roomItemOverlapParams.FilterType = Enum.RaycastFilterType.Include
		roomItemOverlapParams.MaxParts = 1
		local function worldItemTouchesRoom(model, room)
			if not model
				or not model:IsA("Model")
				or not model.Parent
				or not room then
				return false
			end
			local items = workspace:FindFirstChild("Items")
			if not items
				or not model:IsDescendantOf(items)
				or typeof(model:GetAttribute("ItemName")) ~= "string"
				or itemIsConsumedCross(model) then
				return false
			end
			roomItemOverlapParams.FilterDescendantsInstances = {model}
			for _, bounds in ipairs(getRoomBoundingParts(room)) do
				if bounds:IsA("BasePart") then
					local ok, overlaps = pcall(function()
						return workspace:GetPartBoundsInBox(
							bounds.CFrame,
							bounds.Size + Vector3.new(1.5, 1.2, 1.5),
							roomItemOverlapParams
						)
					end)
					if ok and #overlaps > 0 then
						return true
					end
				end
			end
			return false
		end
		local function findWorldItemInRoom(itemName, room)
			local items = workspace:FindFirstChild("Items")
			if not items or not room then
				return nil
			end
			for _, model in ipairs(items:GetChildren()) do
				if model:IsA("Model")
					and sameItemName(
						model:GetAttribute("ItemName"),
						itemName
					)
					and worldItemTouchesRoom(model, room) then
					return model
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
							and not itemIsConsumedCross(child) then
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
				local candidateName = child:GetAttribute("ItemName")
				if child:IsA("Model")
					and typeof(candidateName) == "string"
					and sameItemName(candidateName, itemName)
					and not itemIsConsumedCross(child) then
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
			local favouriteRoom = returnToFavouriteRoom
				and currentFavouriteRoom()
				or nil
			if beforeCount == 0 then
				return not favouriteRoom
					or findWorldItemInRoom(itemName, favouriteRoom) ~= nil
			end
			for attempt = 1, 2 do
				local currentSlot = findInventorySlot(itemName)
				if not currentSlot then
					if not favouriteRoom
						or findWorldItemInRoom(itemName, favouriteRoom) then
						return true
					end
					guardedWait(0.1)
					continue
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
					local leftInventory = countInventoryItem(itemName) < beforeCount
						or not inventoryHasItem(itemName)
						or inventorySlotValue(slotNumber) ~= beforeSlotValue
					local worldConfirmed = not favouriteRoom
						or findWorldItemInRoom(itemName, favouriteRoom) ~= nil
					if leftInventory and worldConfirmed then
						return true
					end
					guardedWait(0.05)
				until os.clock() >= deadline
				local _, occupiedCount = inventorySnapshot()
				if countInventoryItem(itemName) < beforeCount
					and (not favouriteRoom
						or findWorldItemInRoom(itemName, favouriteRoom)) then
					return true
				end
				if occupiedCount < inventorySlotCount
					and not inventoryHasItem(itemName)
					and (not favouriteRoom
						or findWorldItemInRoom(itemName, favouriteRoom)) then
					return true
				end
				guardedWait(0.2)
			end
			return countInventoryItem(itemName) < beforeCount
				and (not favouriteRoom
					or findWorldItemInRoom(itemName, favouriteRoom) ~= nil)
		end
		local corePlacementNames = {
			[normalizeItemName("Cross")] = true,
			[normalizeItemName("Spirit Box")] = true,
			[normalizeItemName("Laser Projector")] = true,
			[normalizeItemName("Flower Pot")] = true,
			[normalizeItemName("EMF Reader")] = true,
			[normalizeItemName("Blacklight")] = true,
			[normalizeItemName("Video Camera")] = true,
		}
		local finalRetainedNames = {
			[normalizeItemName("Salt Canister")] = true,
			[normalizeItemName("Holy Oil")] = true,
		}
		local coreOrder = {
			"Cross",
			"Spirit Box",
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
			if protectedNames == corePlacementNames then
				local alreadyPlaced = findWorldItemInRoom(
					itemName,
					currentFavouriteRoom()
				)
				if alreadyPlaced then
					return true, alreadyPlaced, nil
				end
			end
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
			return sameItemName(itemName, "Spirit Box")
				or sameItemName(itemName, "Laser Projector")
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
			roomItemPlacementState.lastCompletedGeneration =
				operationGeneration
			roomItemPlacementState.lastResult = ok
			roomItemPlacementState.lastError = not ok
				and tostring(err):match("^[^\n]+")
				or (#failedItems > 0 and table.concat(failedItems, ", ") or nil)
			roomItemPlacementState.busy = false
			roomItemPlacementState.thread = nil
			roomItemPlacementState.owner = nil
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
				message = "The seven room items were placed; Salt Canister and Holy Oil were retained when available."
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
			roomItemPlacementState.owner = nil
		end
	end)
	return true, operationGeneration
end

doRoundState.movementReleaseSequence = 0
doRoundState.releasePlayerMovement = function()
	doRoundState.movementReleaseSequence =
		(doRoundState.movementReleaseSequence or 0) + 1
	local releaseSequence = doRoundState.movementReleaseSequence
	local function restoreCurrentCharacter()
		if doRoundState.enabled or player:GetAttribute("Dead") == true then
			return false
		end
		local character = player.Character
		local root = character
			and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character
			and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not humanoid
			or humanoid.Health <= 0 then
			return false
		end
		pcall(function()
			root.Anchored = false
			humanoid.Sit = false
			humanoid.PlatformStand = false
			humanoid.AutoRotate = true
			for _, state in ipairs({
				Enum.HumanoidStateType.FallingDown,
				Enum.HumanoidStateType.Ragdoll,
				Enum.HumanoidStateType.Freefall,
			}) do
				humanoid:SetStateEnabled(state, true)
			end
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
		return true
	end
	restoreCurrentCharacter()
	task.spawn(function()
		-- A cancelled teleport can still be unwinding from a Heartbeat yield.
		-- Reassert the normal live-player state long enough for that cooperative
		-- cancellation path to finish, but stop immediately if automation restarts.
		for _ = 1, 12 do
			Services.RunService.Heartbeat:Wait()
			if releaseSequence ~= doRoundState.movementReleaseSequence
				or doRoundState.enabled
				or not runtimeIsActive() then
				return
			end
			restoreCurrentCharacter()
		end
	end)
end

local roundAutomation: any = createRoundAutomation({
	Services = Services,
	Player = player,
	RuntimeIsActive = runtimeIsActive,
	GetGhostModel = getGhostModel,
	FindRoomsFolder = findRoomsFolder,
	FindFavouriteRoom = findFavouriteRoom,
	GetInstanceWorldPosition = getInstanceWorldPosition,
	GetRoomBoundingParts = getRoomBoundingParts,
	PointIsInsidePart = pointIsInsidePart,
	TeleportToRoom = teleportToRoomBoundingBoxCenter,
	TeleportToBaseCamp = teleportToBaseCamp,
	TeleportToFavouriteRoom = teleportToFavouriteRoom,
	PlaceItemsInFavouriteRoom = placeItemsInFavouriteRoom,
	InstanceIsInsideRoom = instanceIsInsideRoom,
	State = doRoundState,
	PerkTrackerState = perkTrackerState,
	RoomItemPlacementState = roomItemPlacementState,
	PerkDetections = perkDetections,
	GhostProfiles = GHOST_PROFILES,
	GhostModule = GhostModule,
	Presenter = presenter,
	PlaceRoomItemsButton = placeRoomItemsButton,
	Copy = COPY,
	Colors = COLORS,
	RefreshAutoSpiritBoxEnabled = refreshAutoSpiritBoxEnabled,
	SetDoRoundStatus = setDoRoundStatus,
	SetGhostIdentificationLabel = setGhostIdentificationLabel,
	ReleasePlayerMovement = doRoundState.releasePlayerMovement,
	PrepareTeleport = dependencies.PrepareTeleport,
})
local function setDoRoundEnabled(enabled, finalPhase)
	return roundAutomation.SetEnabled(enabled, finalPhase)
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
		if ghostCoordinator then
			emitGhostObservation({
				Type = "SpiritBoxResponse",
				Qualified = true,
				Response = "- HUMMING -",
				MimicPossible = skinwalkerPossible,
				Source = "SpiritBoxSubtitleCollector",
			})
			if skinwalkerPossible then
				emitGhostObservation({
					Type = "MimickedAbility",
					Ability = "Siren humming",
					Qualified = true,
					Confidence = 60,
					Source = "SpiritBoxSubtitleCollector",
				})
			end
		else
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
		end
	elseif tostring(voiceCategory or "") == "Female" then
		if ghostCoordinator then
			emitGhostObservation({
				Type = "GhostVoiceSex",
				Qualified = true,
				Sex = "Female",
				Subtitle = firstArgument,
				Source = "SpiritBoxSubtitleCollector",
			})
		else
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
	local now = os.clock()
	local currentMap = workspace:FindFirstChild("Map")
	if not ghost then
		if evidenceRoundGhost then
			perkTrackerState.ghostMissingSince =
				perkTrackerState.ghostMissingSince or now
			local sameRound = currentMap ~= nil
				and perkTrackerState.roundMap == currentMap
			if sameRound then
				return
			end
			perkTrackerState.resetEvidenceState()
			evidenceRoundGhost = nil
		end
		updateFavouriteRoomEsp(nil)
		return
	end
	perkTrackerState.ghostMissingSince = nil
	local mapChanged = perkTrackerState.roundMap ~= nil
		and currentMap ~= perkTrackerState.roundMap
	if mapChanged
		or (evidenceRoundGhost and ghost ~= evidenceRoundGhost) then
		local sameRound = currentMap ~= nil
			and not mapChanged
			and perkTrackerState.roundMap == currentMap
		if not sameRound then
			perkTrackerState.resetEvidenceState()
		end
	end
	evidenceRoundGhost = ghost
	perkTrackerState.roundMap = currentMap
	if not ghostCoordinator then
		if perkTrackerState.ghost ~= ghost then
			resetPerkTrackerForGhost(ghost, false)
		end
		startGhostCoordinator(ghost)
	end
	local roomsFolder = findRoomsFolder()
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
	local currentLowestTemperature = nil
	if roomsFolder then
		for _, room in ipairs(roomsFolder:GetChildren()) do
			local temperature = room:GetAttribute("Temperature")
			if typeof(temperature) == "number" then
				currentLowestTemperature = math.min(
					currentLowestTemperature or temperature,
					temperature
				)
			end
		end
	end
	if typeof(currentLowestTemperature) == "number" then
		lowestRecordedTemperature = math.min(
			lowestRecordedTemperature or currentLowestTemperature,
			currentLowestTemperature
		)
	end
	if typeof(lowestRecordedTemperature) == "number" then
		if lowestRecordedTemperature < 0 then
			freezingEvidenceFound = true
		end
		if presenter and presenter.SetTemperature then
			presenter:SetTemperature(lowestRecordedTemperature, freezingEvidenceFound)
		else
			setEvidenceLabel(
				"Temperature",
				COPY.Evidence.Temperature
					.. ": "
					.. string.format("%.1f°C", lowestRecordedTemperature),
				freezingEvidenceFound and COLORS.green or COLORS.text
			)
		end
	else
		if presenter and presenter.SetTemperature then
			presenter:SetTemperature(nil, freezingEvidenceFound)
		else
			setEvidenceLabel(
				"Temperature",
				COPY.Evidence.Temperature .. ": --.-°C",
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
	huntEscapeManualEnabled = not huntEscapeManualEnabled
	refreshHuntEscapeEnabled()
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
	if doRoundState.enabled then
		return false, "Do-Round currently owns room item setup"
	end
	return placeItemsInFavouriteRoom("Manual")
end

function Controller:ToggleAutoSpiritBox()
	perkTrackerState.autoSpiritBoxManualEnabled =
		not perkTrackerState.autoSpiritBoxManualEnabled
	return refreshAutoSpiritBoxEnabled()
end

function Controller:ToggleDoRound()
	return setDoRoundEnabled(not doRoundState.enabled)
end

function Controller:SetEvidenceMode(mode)
	if mode ~= "Normal" and mode ~= "Mimicry" then
		return false, "Evidence mode must be Normal or Mimicry"
	end
	perkTrackerState.evidenceMode = mode
	if mode == "Normal" then
		local skinwalkerDetection = perkDetections.Skinwalker
		if skinwalkerDetection
			and skinwalkerDetection.Reason
				== "Mimicry mode: Skinwalker can copy the observed Phantom blinking and invisible-speed trait" then
			local previous =
				perkTrackerState.phantomMimicryPreviousSkinwalkerDetection
			if previous then
				perkDetections.Skinwalker = previous
				refreshPerkLogs()
			else
				clearPerkDetection("Skinwalker")
			end
		end
		perkTrackerState.phantomMimicrySkinwalkerClue = false
		perkTrackerState.phantomMimicryPreviousSkinwalkerDetection = nil
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
		DoRound = doRoundState.enabled,
		DoRoundPhase = doRoundState.phase,
		DoRoundElapsed = doRoundState.startedAt
			and math.max(0, os.clock() - doRoundState.startedAt)
			or 0,
		WalkSpeedForcer = perkTrackerState.speedForcerEnabled,
		EvidenceMode = perkTrackerState.evidenceMode,
	}
end

function Controller:Destroy()
	if closed then
		return
	end
	closed = true
	emitGhostObservation = function() end
	for _, connection in ipairs(perkTrackerState.ghostCoreConnections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	table.clear(perkTrackerState.ghostCoreConnections)
	if ghostCoordinator then
		ghostCoordinator:Destroy()
		ghostCoordinator = nil
	end
	perkTrackerState.fixedGhostModel = nil
	perkTrackerState.ghostCoreTickAccumulator = 0
	perkTrackerState.ghostCoreSyncQueued = false
	if doRoundState.enabled then
		setDoRoundEnabled(false, "Off")
	end
	ghostEspEnabled = false
	huntEscapeEnabled = false
	huntEscapeManualEnabled = false
	itemEspEnabled = false
	perkTrackerState.autoSpiritBoxEnabled = false
	perkTrackerState.autoSpiritBoxManualEnabled = false
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
	refreshAutoSpiritBoxEnabled()
	refreshHuntEscapeEnabled()
	setDoRoundStatus("Off")
	setButtonEnabled(
		walkSpeedForcerButton,
		perkTrackerState.speedForcerEnabled
	)
	evidenceRoundGhost = getGhostModel()
	if evidenceRoundGhost then
		-- Initialize and clear the compatibility/UI state before static profile
		-- facts are projected. Doing this afterward could erase the one-shot
		-- Umbra/Vex/model-sex conclusions until another observation arrived.
		resetPerkTrackerForGhost(evidenceRoundGhost, false)
	end
	startGhostCoordinator(evidenceRoundGhost)
	lastDeepEvidenceScan = -math.huge

	local updateAccumulator = 0
	connect(Services.RunService.Heartbeat, function(deltaTime)
		if not runtimeIsActive() then
			return
		end
		perkTrackerState.ghostCoreTickAccumulator =
			perkTrackerState.ghostCoreTickAccumulator + deltaTime
		if perkTrackerState.ghostCoreTickAccumulator >= 0.25 then
			perkTrackerState.ghostCoreTickAccumulator =
				perkTrackerState.ghostCoreTickAccumulator % 0.25
			emitGhostObservation({
				Type = GhostPackage.Events.Types.Tick,
				Source = "RunService.Heartbeat",
			})
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
		if doRoundState.enabled then
			setDoRoundStatus(doRoundState.phase)
		end
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
	if dependencies.AutoStart == true and not doRoundState.enabled then
		setDoRoundEnabled(true)
	end
	return self
end

if generation == nil or environment.DemonologyGeneration == generation then
	environment.UntitledGuiCleanup = function()
		controller:Destroy()
	end
end

return controller
end
