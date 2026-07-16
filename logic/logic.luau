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
	-- A cached top-level loadstring can briefly be older than the modules it
	-- downloads from main. Resolve the shared factory independently when that
	-- stale loader does not know about the Teleportation dependency yet.
	local createTeleportation = dependencies.Teleportation
		or environment.DemonologyTeleportationFactory
	local teleportationLoadFailure
	if type(createTeleportation) ~= "function" then
		local sourceUrl = "https://raw.githubusercontent.com/amyyzing/Testing-Script/main/logic/teleportation.luau"
			.. "?runtime="
			.. tostring(os.time())
			.. "-"
			.. tostring(math.random(100000, 999999))
		local downloaded, source = pcall(function()
			return game:HttpGet(sourceUrl, true)
		end)
		if downloaded and type(source) == "string" and type(loadstring) == "function" then
			local chunk, compileFailure = loadstring(
				source,
				"@logic/teleportation.luau"
			)
			if chunk then
				local loaded, factory = pcall(chunk)
				if loaded and type(factory) == "function" then
					createTeleportation = factory
					environment.DemonologyTeleportationFactory = factory
				else
					teleportationLoadFailure = tostring(factory)
				end
			else
				teleportationLoadFailure = tostring(compileFailure)
			end
		else
			teleportationLoadFailure = tostring(source)
		end
	end
	assert(
		type(createTeleportation) == "function",
		"logic/logic.luau could not load Teleportation: "
			.. tostring(teleportationLoadFailure or "factory unavailable")
	)
	local view = assert(dependencies.View, "logic/logic.luau requires View")
	local presenter = dependencies.Presenter
	local ghostSpecification = type(GhostPackage.Specification) == "table"
		and GhostPackage.Specification or {}
	local speedPairSpecification = type(ghostSpecification.SpeedPairs) == "table"
		and ghostSpecification.SpeedPairs or {}
	local mapSizeSpecification = type(ghostSpecification.MapSize) == "table"
		and ghostSpecification.MapSize or {}
	local mapSizeFactors = type(mapSizeSpecification.Factors) == "table"
		and mapSizeSpecification.Factors or {Small = 1, Medium = 1.05, Large = 1.1}
	local jobSiteSizes = type(mapSizeSpecification.JobSites) == "table"
		and mapSizeSpecification.JobSites or {}
	local allowedHuntingSpeedMultipliers = type(speedPairSpecification.HuntingMultipliers) == "table"
		and speedPairSpecification.HuntingMultipliers or {0.5, 0.75, 1, 1.25, 1.5, 2}

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
	timeoutThread = nil,
	identificationThread = nil,
	completionClaimed = false,
	startedAt = nil,
	exitOpenedAt = nil,
	lastElapsed = 0,
	phase = "Off",
	lastRenderedPhase = nil,
	lastRenderedSecond = nil,
	lastRenderedEnabled = nil,
	autoSpiritBoxLease = false,
	questionsActive = false,
	usedSaltDoorModels = setmetatable({}, {__mode = "k"}),
	completedDoorTools = {},
	doorToolPlacements = {},
	doorToolUses = {},
	roomItems = {},
	itemPower = setmetatable({}, {__mode = "k"}),
	outsideSince = setmetatable({}, {__mode = "k"}),
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
local lastDeepEvidenceScan = -math.huge
local ghostProxyDirty = false
local ghostProxyAddedConnection
local ghostProxyRemovingConnection
local perkTrackerState = {
	ghost = nil,
	ghostCoreTickAccumulator = 0,
	ghostCoreSyncQueued = false,
	syncingGhostCoordinator = false,
	resetEvidenceState = function() end,
	ghostMissingSince = nil,
	roundMap = nil,
	evidenceMode = "Normal",
	speedForcerEnabled = false,
	speedForceAccumulator = 0,
	suppressItemDisableUntil = 0,
	flashButton = function() end,
	itemEspChildConnection = nil,
	spiritBoxVoiceSubtitles = {},
	spiritBoxVoiceFolder = nil,
	spiritBoxRemoteBound = false,
	autoSpiritBoxEnabled = false,
	autoSpiritBoxManualEnabled = false,
	autoSpiritBoxAccumulator = 0,
	autoSpiritBoxQuestionIndex = 0,
	journalGhostTypesContainer = nil,
	lastJournalSelectedGhost = nil,
	lastJournalVisualGhost = nil,
	journalForcedGhost = nil,
	journalDesiredApplicability = {},
	journalMutationBusy = false,
	journalSyncPending = false,
	journalPendingForcedGhost = nil,
	journalRetryScheduled = false,
	coordinatorResults = {},
	currentGhostGuess = nil,
	currentGhostGuessScore = 0,
	currentGhostGuessCertain = false,
	syncJournal = function() end,
	teleportSequence = 0,
	orbObserved = false,
	skinwalkerOrbQualified = false,
	lastEvidenceSnapshotSignature = nil,
	deepEvidenceWorkspaceBound = false,
	deepEvidenceInitialScanDone = false,
	observeDeepEvidenceObject = function() end,
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
perkTrackerState.isGhostRuledOut = function(ghostName)
	return perkTrackerState.ruledOutGhosts[ghostName] ~= nil
end
perkTrackerState.getGhostNegativeConfidence = function(ghostName)
	local state = perkTrackerState.coordinatorResults[ghostName]
	return state and (tonumber(state.NegativeConfidence) or 0) or 0
end
perkTrackerState.isGhostStronglyNegative = function(ghostName)
	local state = perkTrackerState.coordinatorResults[ghostName]
	if not state then
		return false
	end
	local negative = tonumber(state.NegativeConfidence) or 0
	local positive = tonumber(state.Confidence) or 0
	return negative >= 95 and negative >= positive
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
	perkTrackerState.coordinatorResults = resolved
	for ghostName, state in pairs(resolved) do
		local positive = strongestEntry(state.Positives)
		local supportScore = tonumber(state.Confidence)
			or (positive and tonumber(positive.Confidence))
			or 0
		local netScore = tonumber(state.Score) or supportScore
		if positive and netScore > 0 then
			local existing = perkDetections[ghostName]
			if not existing
				or existing.Source == "GhostCoordinator"
				or netScore > (tonumber(existing.Confidence) or 0) then
				perkDetections[ghostName] = {
					-- Rank projections by the resolver's net result. Using only the
					-- strongest positive let contradicted, lower-confidence trackers
					-- overwrite the actual leader in the GUI and Journal.
					Confidence = netScore,
					RawConfidence = supportScore,
					NetConfidence = netScore,
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

		-- Project only the resolver's effective decision. A raw 99% RuleOut may
		-- coexist with a canonical 100% positive (for example Skinwalker's
		-- impossible/fourth-Orb result) without making that ghost ineligible.
		local ruleOut = state.RuledOut == true
			and strongestEntry(state.RuleOuts) or nil
		if state.HardNegative == true then
			local hardNegative = strongestEntry(state.Negatives)
			if hardNegative and (not ruleOut
				or (tonumber(hardNegative.Confidence) or 0)
					> (tonumber(ruleOut.Confidence) or 0)) then
				ruleOut = hardNegative
			end
		end
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
	perkTrackerState.refreshIdentification()
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
perkTrackerState.getConfirmedEvidence = function()
	local snapshot = {}
	for evidenceName, found in pairs(getConfirmedEvidence()) do
		if found then
			snapshot[evidenceName] = true
		end
	end
	return snapshot
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
		if perkTrackerState.isGhostStronglyNegative(ghostName) then
			return false
		end
	end

	local profile = findGhostProfile(ghostName)
	if not profile then
		return false
	end

	local mimicry =
		perkTrackerState.evidenceMode == "Mimicry"
	if not mimicry
		and ghostName == "Skinwalker"
		and perkTrackerState.skinwalkerOrbQualified then
		return true
	end
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
		-- A fourth/impossible Orb combination is Skinwalker's unique evidence
		-- contract. Keep every consumer on that same singleton pool instead of
		-- asking the ordinary three-evidence filter to reconcile an impossible set.
		if perkTrackerState.skinwalkerOrbQualified then
			return {"Skinwalker"}
		end
		local candidateEvidence = {}
		for evidenceName, found in pairs(confirmed) do
			candidateEvidence[evidenceName] = found
		end
		if perkTrackerState.orbObserved then
			candidateEvidence.GhostOrb = true
		end
		local orbCombination = GhostModule.ClassifyOrbCombination(
			candidateEvidence
		)
		if orbCombination.Qualified == true then
			return {"Skinwalker"}
		end
		local ruleOuts = {}
		if ignoreRuleOut ~= true then
			for ghostName in pairs(perkTrackerState.ruledOutGhosts) do
				ruleOuts[ghostName] = true
			end
			for _, profile in ipairs(GHOST_PROFILES) do
				if perkTrackerState.isGhostStronglyNegative(profile.Name) then
					ruleOuts[profile.Name] = true
				end
			end
		end
		local confirmedCount = countConfirmedEvidence(candidateEvidence)
		local realCandidates = GhostModule.FilterCandidates(
			candidateEvidence,
			{},
			{NamesOnly = true, RealOnly = true, IncludeFalseEvidence = false}
		)
		-- Skinwalker's Orb is partial false evidence only. Once three confirmed
		-- observations form a valid real trio, that trio owns the candidate pool;
		-- leaving Skinwalker neutral made the Journal disagree with a Certain row.
		local useRealCombination = confirmedCount >= 3 and #realCandidates > 0
		return GhostModule.FilterCandidates(candidateEvidence, ruleOuts, {
			NamesOnly = true,
			RealOnly = useRealCombination,
			IncludeFalseEvidence = not useRealCombination,
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
	if not perkTrackerState.orbObserved then
		return
	end
	-- A replicated GhostOrb is a confirmed observation. The ghost package owns
	-- fourth/impossible-combination classification so every consumer sees the
	-- same Skinwalker result.
	evidenceFound.Orb = true
end
perkTrackerState.publishEvidenceSnapshot = function()
	local confirmed = getConfirmedEvidence()
	local names = {}
	for _, evidenceName in ipairs(GhostModule.EvidenceOrder or {}) do
		if confirmed[evidenceName] == true then
			table.insert(names, evidenceName)
		end
	end
	local signature = table.concat(names, "|")
	if signature == perkTrackerState.lastEvidenceSnapshotSignature then
		return
	end
	perkTrackerState.lastEvidenceSnapshotSignature = signature
	emitGhostObservation({
		Type = GhostPackage.Events.Types.EvidenceSnapshot,
		Qualified = true,
		Completed = true,
		Evidence = confirmed,
		Source = "EvidenceCollector",
	})
end
perkTrackerState.updateEvidenceStatuses = function()
	local candidates = perkTrackerState.getRemainingCandidates(false)
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
	local tiedNames = GhostModule.HighestConfidenceTies(candidates)
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
	if perkTrackerState.skinwalkerOrbQualified then
		return "Skinwalker"
	end
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
		return perkTrackerState.isGhostRuledOut("Ghoul")
			and "Skinwalker" or "Ghoul / Skinwalker", 35
	end
	if spiritBoxTentative and not evidenceFound.SpiritBox and observedCount == 3 then
		for _, profile in ipairs(GHOST_PROFILES) do
			if profileMatches(profile, observed) then
				if profile.Name == "Ghoul"
					and perkTrackerState.isGhostRuledOut("Ghoul") then
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
					return perkTrackerState.isGhostRuledOut("Ghoul")
						and "Skinwalker" or "Ghoul / Skinwalker", 35
				end
				return profile.Name, 35
			end
		end
	end
	if countConfirmedEvidence(confirmed) >= 3 then
		return nil
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
	local previousGuess = perkTrackerState.currentGhostGuess
	local previousScore = perkTrackerState.currentGhostGuessScore or 0
	local candidates = perkTrackerState.getRemainingCandidates(false)
	local perkGhost, perkDetection = getBestPerkDetection(confirmed)
	local tentativeEvidenceGhost, tentativeEvidenceScore =
		identifyTentativeGhostFromEvidence()
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
			and math.abs(score - selectedScore) <= 0.0001
			and not string.find(
				selectedGhost,
				ghostName,
				1,
				true
			) then
			selectedGhost = selectedGhost .. " / " .. ghostName
		end
	end
	consider(tentativeEvidenceGhost, tentativeEvidenceScore or 0)
	if #candidates == 1 and not mimicryBehaviorLocked then
		consider(candidates[1], 90)
	elseif not selectedGhost and #candidates > 1 and #candidates <= 3 then
		table.sort(candidates)
		selectedGhost = table.concat(candidates, " / ")
		selectedScore = 35
	end
	-- Hysteresis is only for the weak multi-candidate "Idk" label. Retaining an
	-- older Maybe/Pretty Sure score after its live tracker projection was reduced
	-- or superseded made stale, lower-quality conclusions override the resolver.
	if previousGuess
		and previousScore <= 35
		and previousScore > selectedScore then
		local stillCompatible = {}
		for name in string.gmatch(tostring(previousGuess), "[^/]+") do
			name = string.gsub(name, "^%s+", "")
			name = string.gsub(name, "%s+$", "")
			if findGhostProfile(name)
				and not perkTrackerState.isGhostRuledOut(name)
				and ghostSupportsConfirmedEvidence(name, confirmed, false) then
				table.insert(stillCompatible, name)
			end
		end
		if #stillCompatible > 0 then
			selectedGhost = table.concat(stillCompatible, " / ")
			selectedScore = previousScore
		end
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
	for _ = 1, 3 do
		local previous = current
		if not perkTrackerState.triggerJournalClick(frame) then
			break
		end
		-- Journal visuals do not always update on the same frame as the click,
		-- especially after the player changed rows manually. Wait for a real
		-- state transition before deciding whether another click is required.
		local deadline = os.clock() + 0.25
		repeat
			task.wait(0.02)
			current = perkTrackerState.readJournalRowState(frame)
		until current == desiredState
			or current ~= previous
			or os.clock() >= deadline
		if current == desiredState then
			return true
		end
		if current == previous then
			break
		end
	end
	return current == desiredState
end
perkTrackerState.fireJournalGhostSelection = function(ghostName)
	if type(ghostName) ~= "string" or ghostName == "" then
		return false
	end
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local event = events and events:FindFirstChild("EvidenceMarkedInJournal")
	if not event or not event:IsA("RemoteEvent") then
		return false
	end
	local sent = pcall(event.FireServer, event, ghostName)
	if sent then
		perkTrackerState.lastJournalSelectedGhost = ghostName
	end
	return sent
end
perkTrackerState.confirmJournalGhostSelection = function(frame, ghostName)
	-- OnClientInvoke is a write-only callback member in Roblox/executor
	-- environments, so it cannot be used to query the Journal controller.
	-- Preserve the older compatible path: apply the visible row through its
	-- normal click handler and independently send the authoritative selection.
	local visualApplied = perkTrackerState.applyJournalRowState(frame, true)
	perkTrackerState.fireJournalGhostSelection(ghostName)
	-- GetSelectedGhost reads the Journal controller's local row state. Merely
	-- dispatching EvidenceMarkedInJournal does not select that row locally.
	return visualApplied
end
perkTrackerState.syncJournal = function(forcedGhost)
	if closed then
		return false
	end
	local function scheduleJournalRetry()
		if closed or perkTrackerState.journalRetryScheduled then
			return
		end
		perkTrackerState.journalRetryScheduled = true
		task.delay(0.5, function()
			perkTrackerState.journalRetryScheduled = false
			if not closed then
				perkTrackerState.syncJournal()
			end
		end)
	end
	if perkTrackerState.journalMutationBusy then
		-- Journal row clicks yield while the game's controller advances through
		-- nil/selected/crossed-out. Replay a tracker refresh that arrives during
		-- that yield instead of leaving stale markings until another event occurs.
		perkTrackerState.journalSyncPending = true
		if forcedGhost ~= nil then
			perkTrackerState.journalPendingForcedGhost = forcedGhost
		end
		return false
	end
	local function finishJournalMutation()
		perkTrackerState.journalMutationBusy = false
		if not perkTrackerState.journalSyncPending or closed then
			return
		end
		perkTrackerState.journalSyncPending = false
		local pendingForced = perkTrackerState.journalPendingForcedGhost
		perkTrackerState.journalPendingForcedGhost = nil
		task.defer(function()
			if not closed then
				perkTrackerState.syncJournal(pendingForced)
			end
		end)
	end
	local explicitlyForced = forcedGhost ~= nil
	if forcedGhost == nil then
		forcedGhost = perkTrackerState.journalForcedGhost
	end
	local forcedSelection = type(forcedGhost) == "string"
		and forcedGhost ~= ""
		and not string.find(tostring(forcedGhost), "/", 1, true)
		and GhostModule.Find(forcedGhost) ~= nil
	if forcedGhost ~= nil and not forcedSelection then
		if not explicitlyForced then
			perkTrackerState.journalForcedGhost = nil
			forcedGhost = nil
		else
			return false
		end
	end
	if explicitlyForced and forcedSelection then
		-- Preserve the final choice while evidence/UI refreshes continue in
		-- parallel with the lobby-return sequence.
		perkTrackerState.journalForcedGhost = forcedGhost
	end
	if forcedSelection then
		local ghostTypes = perkTrackerState.findJournalGhostTypes()
		local frame = ghostTypes and ghostTypes:FindFirstChild(forcedGhost)
		if not frame or not frame:IsA("Frame") then
			-- The Journal can still be cloning its rows when a very fast tracker
			-- resolves the ghost. Retain journalForcedGhost and report the local
			-- selection as incomplete so completion retries after the row exists.
			scheduleJournalRetry()
			return false
		end
		local candidates = perkTrackerState.getRemainingCandidates(false)
		local candidateSet = {}
		for _, ghostName in ipairs(candidates) do
			candidateSet[ghostName] = true
		end
		-- The completion lock owns the final row even if a soft rule-out raced the
		-- exact selection. Every other row still follows normal Journal cross-outs.
		candidateSet[forcedGhost] = true
		perkTrackerState.journalMutationBusy = true
		local mutationCall, selectedApplied, allRowsApplied = pcall(function()
			local rowsApplied = true
			for _, profile in ipairs(GHOST_PROFILES) do
				local ghostName = profile.Name
				if ghostName ~= forcedGhost then
					local applicable = candidateSet[ghostName] == true
					local desiredState = false
					if applicable then
						desiredState = nil
					end
					local otherFrame = ghostTypes:FindFirstChild(ghostName)
					if otherFrame and otherFrame:IsA("Frame") then
						if not perkTrackerState.applyJournalRowState(
							otherFrame,
							desiredState
						) then
							rowsApplied = false
						end
					end
					perkTrackerState.journalDesiredApplicability[ghostName] =
						applicable
				end
			end
			perkTrackerState.journalDesiredApplicability[forcedGhost] = true
			-- Select last because crossing another row can clear the current
			-- highlight in the game's Journal controller.
			return perkTrackerState.confirmJournalGhostSelection(
				frame,
				forcedGhost
			), rowsApplied
		end)
		finishJournalMutation()
		if mutationCall and selectedApplied then
			perkTrackerState.lastJournalSelectedGhost = forcedGhost
			perkTrackerState.lastJournalVisualGhost = forcedGhost
			perkTrackerState.journalDesiredApplicability[forcedGhost] = true
		end
		local applied = mutationCall
			and selectedApplied == true
			and allRowsApplied == true
		if not applied then
			scheduleJournalRetry()
		end
		return applied
	end
	local candidates = perkTrackerState.getRemainingCandidates(false)
	local candidateSet = {}
	for _, ghostName in ipairs(candidates) do
		candidateSet[ghostName] = true
	end
	local selectedGhost
	local guess = perkTrackerState.currentGhostGuess
	local score = perkTrackerState.currentGhostGuessScore or 0
	local exactCertainGuess = perkTrackerState.currentGhostGuessCertain == true
		and type(guess) == "string"
		and not string.find(guess, "/", 1, true)
		and GhostModule.Find(guess) ~= nil
	if exactCertainGuess then
		-- Exact three-evidence identification is the hard source of truth. A soft
		-- behavioral rule-out must not make the Journal cross out the same ghost
		-- that the GUI labels Certain.
		candidateSet[guess] = true
		selectedGhost = guess
	end
	if not selectedGhost
		and guess
		and score >= 80
		and not string.find(guess, "/", 1, true)
		and candidateSet[guess] then
		selectedGhost = guess
	end
	local ghostTypes =
		perkTrackerState.findJournalGhostTypes()
	if ghostTypes then
		perkTrackerState.journalMutationBusy = true
		local mutationCall, selectedApplied, allRowsApplied = pcall(function()
			local applied = selectedGhost == nil
			local rowsApplied = true
			local function applyProfileState(profile)
				local ghostName = profile.Name
				local applicable = candidateSet[ghostName] == true
				local desiredState = false
				if applicable then
					desiredState = nil
				end
				local frame = ghostTypes:FindFirstChild(ghostName)
				if frame and frame:IsA("Frame") then
					if not perkTrackerState.applyJournalRowState(
						frame,
						desiredState
					) then
						rowsApplied = false
					end
				end
				perkTrackerState.journalDesiredApplicability[ghostName] =
					applicable
			end
			for _, profile in ipairs(GHOST_PROFILES) do
				if profile.Name ~= selectedGhost then
					applyProfileState(profile)
				end
			end
			-- Select last. If the game's journal controller clears a highlight while
			-- another row is changed, no later cross-out click can undo the winner.
			if selectedGhost then
				local selectedProfile = GhostModule.Find(selectedGhost)
				if selectedProfile then
					local frame = ghostTypes:FindFirstChild(selectedGhost)
					if frame and frame:IsA("Frame") then
						applied = perkTrackerState.applyJournalRowState(frame, true)
					else
						applied = false
					end
					perkTrackerState.journalDesiredApplicability[selectedGhost] =
						true
				end
			end
			return applied, rowsApplied
		end)
		finishJournalMutation()
		local fullyApplied = mutationCall
			and selectedApplied == true
			and allRowsApplied == true
		if fullyApplied and selectedGhost then
			perkTrackerState.lastJournalSelectedGhost = selectedGhost
			perkTrackerState.lastJournalVisualGhost = selectedGhost
			return true
		end
		if fullyApplied and not selectedGhost then
			perkTrackerState.lastJournalVisualGhost = nil
			return true
		end
		scheduleJournalRetry()
	else
		scheduleJournalRetry()
	end
	if selectedGhost then
		return perkTrackerState.fireJournalGhostSelection(selectedGhost)
	end
	return false
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
			if current:GetAttribute("ItemName") ~= nil then
				return current
			end
			local items = workspace:FindFirstChild("Items")
			if items and current.Parent == items then
				return current
			end
		end
		current = current.Parent
	end
	return nil
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
	local elapsedSecond = math.floor(elapsed)
	if doRoundState.lastRenderedPhase == doRoundState.phase
		and doRoundState.lastRenderedSecond == elapsedSecond
		and doRoundState.lastRenderedEnabled == doRoundState.enabled then
		return
	end
	doRoundState.lastRenderedPhase = doRoundState.phase
	doRoundState.lastRenderedSecond = elapsedSecond
	doRoundState.lastRenderedEnabled = doRoundState.enabled
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
	if ghostCoordinator then
		ghostCoordinator:Destroy()
		ghostCoordinator = nil
	end
	perkTrackerState.coordinatorResults = {}
	perkTrackerState.ghost = nil
	perkTrackerState.ghostCoreTickAccumulator = 0
	perkTrackerState.ghostCoreSyncQueued = false
	emitGhostObservation = function()
		return nil
	end
	for evidenceName in pairs(evidenceFound) do
		evidenceFound[evidenceName] = false
	end
	freezingEvidenceFound = false
	lowestRecordedTemperature = nil
	highestEMF = 1
	spiritBoxTentative = false
	perkTrackerState.orbObserved = false
	perkTrackerState.skinwalkerOrbQualified = false
	perkTrackerState.lastEvidenceSnapshotSignature = nil
	perkTrackerState.deepEvidenceInitialScanDone = false
	perkTrackerState.suppressItemDisableUntil = 0
	perkTrackerState.ruledOutGhosts = {}
	clearAllPerkDetections()
	refreshPerkLogs()
	perkTrackerState.currentGhostGuess = nil
	perkTrackerState.currentGhostGuessScore = 0
	perkTrackerState.currentGhostGuessCertain = false
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
	perkTrackerState.orbObserved = false
	perkTrackerState.deepEvidenceInitialScanDone = false
	if not preserveFindings then
		perkTrackerState.skinwalkerOrbQualified = false
		perkTrackerState.lastEvidenceSnapshotSignature = nil
		perkTrackerState.ruledOutGhosts = {}
		refreshPerkLogs()
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
	local cachedEntry = roomBoundingPartsCache[room]
	local cached = cachedEntry and cachedEntry.Parts
	if cached and #cached > 0
		and os.clock() - (cachedEntry.ScannedAt or 0) < 0.75 then
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
		roomBoundingPartsCache[room] = {
			Parts = parts,
			ScannedAt = os.clock(),
		}
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
local teleportation = createTeleportation({
	Services = Services,
	Player = player,
	RuntimeIsActive = runtimeIsActive,
	FindRoomsFolder = findRoomsFolder,
	GetInstanceWorldPosition = getInstanceWorldPosition,
	GetRoomBoundingParts = getRoomBoundingParts,
	PointIsInsidePart = pointIsInsidePart,
})
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
local function sameRoomName(first, second)
	if first == nil or second == nil then
		return false
	end
	return string.lower(tostring(first)) == string.lower(tostring(second))
end
local function getMapSizeName()
	local map = workspace:FindFirstChild("Map")
	local value = map and map:GetAttribute("MapSize") or nil
	if value == nil then
		local remembered = type(environment.DemonologyLobbySettings) == "table"
			and environment.DemonologyLobbySettings or {}
		value = jobSiteSizes[tostring(remembered.JobSite or "")]
	end
	local normalized = string.lower(tostring(value))
	if normalized == "large" then
		return "Large"
	elseif normalized == "medium" then
		return "Medium"
	end
	return "Small"
end
local function getMapSizeSpeedFactor()
	return tonumber(mapSizeFactors[getMapSizeName()]) or 1
end
local function getConfiguredGhostSpeedMultipliers()
	local remembered = type(environment.DemonologyLobbySettings) == "table"
		and environment.DemonologyLobbySettings or {}
	local selectedIndex = tonumber(remembered.GhostWalkSpeedMultiplier)
	if tostring(remembered.Difficulty or "") == "Custom"
		and selectedIndex ~= nil
		and selectedIndex == math.floor(selectedIndex) then
		local configured = tonumber(allowedHuntingSpeedMultipliers[selectedIndex])
		if configured and configured > 0 then
			return {configured}
		end
	end
	local possible = {}
	for _, multiplier in ipairs(allowedHuntingSpeedMultipliers) do
		multiplier = tonumber(multiplier)
		if multiplier and multiplier > 0 then
			table.insert(possible, multiplier)
		end
	end
	return possible
end
local function getGhostWalkSpeed(ghost)
	local humanoid = ghost and ghost:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid.WalkSpeed or nil
end
local function startGhostCoordinator(ghost)
	if ghostCoordinator or not ghost then
		return ghostCoordinator ~= nil
	end
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = {ghost}
	overlapParams.MaxParts = 1
	local holyOilPassStates = setmetatable({}, {__mode = "k"})
	local movementPosition = ghost:GetPivot().Position
	local movementSampleAt = os.clock()
	local movementSpeed = 0
	local function readGhostMovementSpeed()
		local now = os.clock()
		local position = ghost:GetPivot().Position
		local elapsed = now - movementSampleAt
		if elapsed > 0 then
			movementSpeed = (position - movementPosition).Magnitude / elapsed
			movementPosition = position
			movementSampleAt = now
		end
		return movementSpeed
	end
	local function boundsFor(instance)
		if not instance or not instance.Parent then
			return nil, nil
		end
		if instance:IsA("BasePart") then
			return instance.CFrame, instance.Size
		end
		if instance:IsA("Model") then
			local ok, frame, size = pcall(instance.GetBoundingBox, instance)
			if ok then
				return frame, size
			end
		end
		local part = instance:FindFirstChildWhichIsA("BasePart", true)
		return part and part.CFrame or nil, part and part.Size or nil
	end
	local function ghostOverlaps(instance, padding)
		local frame, size = boundsFor(instance)
		if not frame or not size then
			return false
		end
		local ok, parts = pcall(
			workspace.GetPartBoundsInBox,
			workspace,
			frame,
			size + (padding or Vector3.zero),
			overlapParams
		)
		return ok and #parts > 0
	end
	local function holyOilWallSide(wall, position)
		if not wall or not position then
			return nil, nil
		end
		local localPosition = wall.CFrame:PointToObjectSpace(position)
		if wall.Size.X <= wall.Size.Z then
			return localPosition.X, wall.Size.X * 0.5
		end
		return localPosition.Z, wall.Size.Z * 0.5
	end
	local function readHolyOilPass(model, wall, targetGhost)
		targetGhost = targetGhost or ghost
		if not model or not model.Parent
			or model:GetAttribute("Burning") ~= true
			or targetGhost:GetAttribute("Hunting") ~= true then
			holyOilPassStates[model] = nil
			return false
		end
		local now = os.clock()
		local position = targetGhost:GetPivot().Position
		local inside = ghostOverlaps(model, Vector3.new(0.5, 1, 0.5))
		local side, halfThickness = holyOilWallSide(wall, position)
		local state = holyOilPassStates[model]
		if inside then
			if not state then
				local sign = side and side ~= 0 and (side > 0 and 1 or -1) or 0
				if sign == 0 and wall then
					local root = targetGhost:FindFirstChild("HumanoidRootPart")
					local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
					local normal = wall.Size.X <= wall.Size.Z
						and wall.CFrame.RightVector or wall.CFrame.LookVector
					local direction = velocity:Dot(normal)
					if math.abs(direction) > 0.05 then
						sign = direction > 0 and -1 or 1
					end
				end
				state = {
					EntrySign = sign,
					EntryPosition = position,
					HalfThickness = halfThickness,
					StartedAt = now,
				}
				holyOilPassStates[model] = state
			end
			state.WasInside = true
			return false
		end
		if not state then
			return false
		end
		if now - state.StartedAt > 4 then
			holyOilPassStates[model] = nil
			return false
		end
		local exitSign = side and side ~= 0 and (side > 0 and 1 or -1) or 0
		local crossed = state.WasInside == true and (
			wall and state.EntrySign ~= 0 and exitSign ~= 0
				and state.EntrySign ~= exitSign
				and math.abs(side or 0) >= (halfThickness or state.HalfThickness or 0) + 0.15
			or not wall and (position - state.EntryPosition).Magnitude >= 3
		)
		if crossed then
			holyOilPassStates[model] = nil
		end
		return crossed
	end
	local created
	created = GhostPackage.Create({
		Name = "DemonologyGhostCoordinator",
		Profiles = GhostPackage.Profiles,
		Catalog = GhostPackage.Profiles,
		OnChanged = function(kind, payload)
			if kind == "Event"
				and type(payload) == "table"
				and payload.Type == GhostPackage.Events.Types.FalseOrb
				and payload.Qualified == true then
				perkTrackerState.skinwalkerOrbQualified = true
			end
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
			Workspace = workspace,
			Players = Services.Players,
			LocalPlayer = player,
			CollectionService = Services.CollectionService,
			Heartbeat = Services.RunService.Heartbeat,
			RunService = Services.RunService,
			GhostModel = ghost,
			InitialHunting = ghost:GetAttribute("Hunting") == true,
			MapFactor = getMapSizeSpeedFactor(),
			MapSize = getMapSizeName(),
			-- Every expected hunting speed is evaluated as:
			-- base × map-size factor × the configured custom speed factor.
			-- When no custom handoff exists, retain all legal factors as a safe
			-- manual-execution fallback instead of inventing one.
			ValidMultipliers = getConfiguredGhostSpeedMultipliers(),
			ReadHunting = function()
				return ghost:GetAttribute("Hunting") == true
			end,
			ReadAverageSanity = getAverageTeamEnergy,
			ReadWalkSpeed = function()
				return getGhostWalkSpeed(ghost)
			end,
			ReadLocalPlayerSpeed = function(humanoid)
				return humanoid and humanoid.WalkSpeed or nil
			end,
			ReadLocalPlayerBaselineSpeed = function()
				return baseWalkSpeed
			end,
			ReadLocalPlayerLineOfSight = function(targetGhost, character)
				return ghostHasLineOfSightToCharacter(targetGhost or ghost, character)
			end,
			ReadLocalPlayerSprinting = function(targetPlayer, character, humanoid)
				for _, owner in ipairs({targetPlayer, humanoid}) do
					if owner then
						for _, attribute in ipairs({"Sprinting", "IsSprinting", "Sprint"}) do
							if owner:GetAttribute(attribute) == true then return true end
						end
					end
				end
				local moving = humanoid ~= nil
					and humanoid.MoveDirection.Magnitude > 0.05
				local shiftDown = Services.UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					or Services.UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				return moving and shiftDown
			end,
			ReadGhostMovementSpeed = readGhostMovementSpeed,
			ReadGhostInFavouriteRoom = function(favouriteName)
				local room = findFavouriteRoom(findRoomsFolder(), favouriteName)
				return room ~= nil and instanceIsInsideRoom(ghost, room)
			end,
			SameRoomName = sameRoomName,
			ResolveItemModel = function(object)
				return perkTrackerState.getTrackedWorldItemModel(object)
			end,
			ReadPosition = getInstanceWorldPosition,
			ReadObjectPosition = getInstanceWorldPosition,
			ReadRoomAtPosition = function(position)
				return perkTrackerState.roomNameAtPosition(position)
			end,
			ReadGhostPosition = function()
				return ghost:GetPivot().Position
			end,
			IsObjectMotionSuppressed = function()
				return roomItemPlacementState.busy
					or os.clock() < (perkTrackerState.automationMutationUntil or 0)
			end,
			IsElectronicMutationSuppressed = function()
				return os.clock() < perkTrackerState.suppressItemDisableUntil
			end,
			ReadTransparency = function()
				return getGhostTransparencyState(ghost)
			end,
			ReadCurrentRoom = function()
				local physical = perkTrackerState.roomNameAtPosition
					and perkTrackerState.roomNameAtPosition(
						ghost:GetPivot().Position
					)
				return physical or ghost:GetAttribute("CurrentRoom")
			end,
			ReadPhysicalCurrentRoom = function()
				return perkTrackerState.roomNameAtPosition
					and perkTrackerState.roomNameAtPosition(
						ghost:GetPivot().Position
					)
					or nil
			end,
			ReadFavouriteRoom = function()
				return ghost:GetAttribute("FavoriteRoom")
					or ghost:GetAttribute("FavouriteRoom")
			end,
			ReadHolyOilWall = function(model)
				return perkTrackerState.getHolyOilWall
					and perkTrackerState.getHolyOilWall(model) or nil
			end,
			ReadHolyOilFireColour = function(model)
				return perkTrackerState.getHolyOilColorKind
					and perkTrackerState.getHolyOilColorKind(model) or nil
			end,
			ReadSaltGhostOverlap = function(model)
				return ghostOverlaps(model, Vector3.new(0.5, 1.5, 0.5))
			end,
			ReadHolyOilPass = readHolyOilPass,
			ReadGhostFireEffect = function(targetGhost)
				for _, descendant in ipairs(
					(targetGhost or ghost):GetDescendants()
				) do
					if descendant:IsA("Fire")
						and descendant.Enabled == true then
						return true
					end
					if descendant:IsA("ParticleEmitter")
						and descendant.Name == "Fire"
						and descendant.Enabled == true then
						return true
					end
				end
				return false
			end,
			ReadRoundStarted = function()
				local doors = workspace:FindFirstChild("Doors")
				if not doors then return false end
				for _, candidate in ipairs(doors:GetChildren()) do
					local normalized = string.lower(candidate.Name):gsub("[^%w]", "")
					local doorType = string.lower(tostring(
						candidate:GetAttribute("DoorType")
							or candidate:GetAttribute("Type")
							or ""
					)):gsub("[^%w]", "")
					local isExit = string.find(normalized, "exitdoor", 1, true) ~= nil
						or candidate:GetAttribute("IsExitDoor") == true
						or candidate:GetAttribute("ExitDoor") == true
						or doorType == "exit"
						or doorType == "exitdoor"
					if isExit and candidate:GetAttribute("DoorClosed") == false then
						return true
					end
				end
				return false
			end,
			ReadRoomTemperature = function(roomName)
				local roomsFolder = findRoomsFolder()
				local room = findFavouriteRoom(roomsFolder, roomName)
				return room and room:GetAttribute("Temperature") or nil
			end,
		},
	})
	ghostCoordinator = created
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
	syncGhostCoordinatorResults()
	return true
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
	local wall = model and (
		model:FindFirstChild("GhostWall", true)
			or model:FindFirstChild("ClonedGhostWall", true)
	)
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
-- Keep late-stage helpers on existing state tables instead of allocating more
-- factory locals. Potassium's loadstring compiler rejected this factory when
-- its generated register use reached R201.
perkTrackerState.findBaseCampRoom = function()
	local roomsFolder = findRoomsFolder()
	if not roomsFolder then
		return nil
	end
	local namedRoom = roomsFolder:FindFirstChild("Base Camp")
		or roomsFolder:FindFirstChild("BaseCamp")
		or findFavouriteRoom(roomsFolder, "Base Camp")
	if namedRoom then
		return namedRoom
	end
	-- Some maps expose only the BaseCamp/Truck model while room names are still
	-- replicating. Infer the bounded room nearest the Truck instead of failing
	-- the safety return outright.
	local baseCamp = workspace:FindFirstChild("BaseCamp")
		or workspace:FindFirstChild("Base Camp")
	local truck = baseCamp and baseCamp:FindFirstChild("Truck", true)
		or workspace:FindFirstChild("Truck", true)
	local truckPosition = getInstanceWorldPosition(truck)
	if not truck or not truckPosition then
		return nil
	end
	return teleportation.FindRoomForTarget(truck, {truckPosition})
end
perkTrackerState.performRoomTeleport = function(room, options)
	options = options or {}
	local teleportSequence
	local function teleportOwnsCharacter()
		return teleportSequence == nil
			or perkTrackerState.teleportSequence == teleportSequence
	end
	local function teleportIsActive()
		if closed or not runtimeIsActive() or not teleportOwnsCharacter() then
			return false
		end
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
		if not teleportIsActive() then
			return false, "teleport was cancelled"
		end
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
	local minimumOpenClearance = math.max(
		0,
		tonumber(options.MinimumOpenClearance) or 0
	)
	local strictSearchExpansion = math.max(
		0,
		tonumber(options.StrictSearchExpansion) or 0.05
	)
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

	local function safelyInsideBounds(position, boundingPart)
		local localPosition =
			boundingPart.CFrame:PointToObjectSpace(position)
		local half = boundingPart.Size * 0.5

		return math.abs(localPosition.X)
			<= math.max(0, half.X - horizontalInset)
			and localPosition.Y >= -half.Y - 0.35
			and localPosition.Y <= half.Y - 0.1
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
		if not safelyInsideBounds(
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
			and clearance >= minimumOpenClearance
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
				if bottomDistance >= -0.6
					and bottomDistance
						<= boundingPart.Size.Y - 0.2 then
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
		if not teleportIsActive() then
			return false, "teleport was cancelled"
		end
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
					if not teleportIsActive() then
						return false, "teleport was cancelled"
					end
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
	local evaluationCancelled = false
	local function evaluateCandidate(candidate)
		if not teleportIsActive() then
			evaluationCancelled = true
			return
		end
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
			if evaluationCancelled then
				return false
			end
			if candidate.StrictSafe and candidate.CoreBlockers == 0 then
				strictCandidateCount = strictCandidateCount + 1
				if strictCandidateCount >= 3 and not completionRadius then
					completionRadius = candidate.SearchDistance
				end
			end
			if completionRadius
				and index < #pool
				and pool[index + 1].SearchDistance
					> completionRadius + strictSearchExpansion then
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
		if evaluationCancelled then
			destroyBodyGeometryProbe()
			return false, "teleport was cancelled"
		end
		if strictCandidateCount >= 3 then
			break
		end
	end

	if #candidates == 0 then
		destroyBodyGeometryProbe()
		return false,
			"no grounded destination passed the detailed room checks"
	end

	local function comparisonBand(value, width)
		return math.floor((tonumber(value) or 0) / width)
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
			if options.PreferClosestOpenSpace == true then
				local leftPreferred = comparisonBand(left.PreferredDistance, 0.05)
				local rightPreferred = comparisonBand(right.PreferredDistance, 0.05)
				if leftPreferred ~= rightPreferred then
					return leftPreferred < rightPreferred
				end
			end
			if options.PreferOpenSpace == true then
				local leftClearance = comparisonBand(left.Clearance, 0.35)
				local rightClearance = comparisonBand(right.Clearance, 0.35)
				if leftClearance ~= rightClearance then
					return leftClearance > rightClearance
				end
			end
			local leftPreferred = comparisonBand(left.PreferredDistance, 0.05)
			local rightPreferred = comparisonBand(right.PreferredDistance, 0.05)
			if leftPreferred ~= rightPreferred then
				return leftPreferred < rightPreferred
			end
			local leftBottom = comparisonBand(left.BottomDistance, 0.25)
			local rightBottom = comparisonBand(right.BottomDistance, 0.25)
			if leftBottom ~= rightBottom then
				return leftBottom < rightBottom
			end
			local leftClearance = comparisonBand(left.Clearance, 0.1)
			local rightClearance = comparisonBand(right.Clearance, 0.1)
			if leftClearance ~= rightClearance then
				return leftClearance > rightClearance
			end
			return left.SampleOrder < right.SampleOrder
		end
		if left.CoreBlockers ~= right.CoreBlockers then
			return left.CoreBlockers < right.CoreBlockers
		end
		if left.BlockerCount ~= right.BlockerCount then
			return left.BlockerCount < right.BlockerCount
		end
		local leftRisk = comparisonBand(left.Risk, 1)
		local rightRisk = comparisonBand(right.Risk, 1)
		if leftRisk ~= rightRisk then
			return leftRisk < rightRisk
		end
		local leftPreferred = comparisonBand(left.PreferredDistance, 0.05)
		local rightPreferred = comparisonBand(right.PreferredDistance, 0.05)
		if leftPreferred ~= rightPreferred then
			return leftPreferred < rightPreferred
		end
		if left.FlatSupportHits ~= right.FlatSupportHits then
			return left.FlatSupportHits > right.FlatSupportHits
		end
		if left.SupportHits ~= right.SupportHits then
			return left.SupportHits > right.SupportHits
		end
		local leftBottom = comparisonBand(left.BottomDistance, 0.25)
		local rightBottom = comparisonBand(right.BottomDistance, 0.25)
		if leftBottom ~= rightBottom then
			return leftBottom < rightBottom
		end
		local leftClearance = comparisonBand(left.Clearance, 0.1)
		local rightClearance = comparisonBand(right.Clearance, 0.1)
		if leftClearance ~= rightClearance then
			return leftClearance > rightClearance
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

	perkTrackerState.teleportSequence =
		(perkTrackerState.teleportSequence or 0) + 1
	teleportSequence = perkTrackerState.teleportSequence
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
			or not safelyInsideBounds(
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
			and clearance >= minimumOpenClearance

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
		local ownsCharacter = teleportOwnsCharacter()
		if ownsCharacter and root.Parent and character.Parent then
			pcall(function()
				character:PivotTo(originalPivot)
			end)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			Services.RunService.Heartbeat:Wait()
		end
		local releaseMovement = options.ReleaseMovementOnCancel == true
			and not teleportIsActive()
		if ownsCharacter and root.Parent then
			root.Anchored = if releaseMovement then false else originalAnchored
		end
		if ownsCharacter and humanoid.Parent then
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
		local ownsCharacter = teleportOwnsCharacter()
		if ownsCharacter and root.Parent and character.Parent then
			pcall(function()
				character:PivotTo(originalPivot)
			end)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = if releaseMovement then false else originalAnchored
		end
		if ownsCharacter and humanoid.Parent then
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
	-- Restore movement states before releasing the shared teleport lease. A
	-- following teleport must never snapshot the temporary disabled values.
	for state, enabled in pairs(disabledStates) do
		pcall(function()
			humanoid:SetStateEnabled(state, enabled)
		end)
	end

	for _ = 1, 3 do
		Services.RunService.Heartbeat:Wait()
		if teleportOwnsCharacter() and root.Parent then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end

	task.delay(0.65, function()
		if perkTrackerState.teleportSequence == teleportSequence
			and player.Character == character
			and root.Parent
			and humanoid.Parent then
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

perkTrackerState.teleportToRoomBoundingBoxCenter = function(room, options)
	options = options or {}
	return teleportation.RunExclusive(options, function()
		return perkTrackerState.performRoomTeleport(room, options)
	end)
end

perkTrackerState.teleportToBaseCamp = function(options)
	local room = perkTrackerState.findBaseCampRoom()
	if not room then
		return false, "Base Camp room was not found"
	end
	options = table.clone(options or {})
	if options.MinimumOpenClearance == nil then
		options.MinimumOpenClearance = 2.1
	end
	if options.StrictSearchExpansion == nil then
		options.StrictSearchExpansion = 5
	end
	if options.PreferOpenSpace == nil then
		options.PreferOpenSpace = true
	end
	if options.PreferClosestOpenSpace == nil then
		options.PreferClosestOpenSpace = true
	end
	local preferredPosition
	if type(options.PreferredPositions) ~= "table"
		or #options.PreferredPositions == 0 then
		local baseCamp = workspace:FindFirstChild("BaseCamp")
			or workspace:FindFirstChild("Base Camp")
		local truck = baseCamp and baseCamp:FindFirstChild("Truck", true)
			or room:FindFirstChild("Truck", true)
			or workspace:FindFirstChild("Truck", true)
		preferredPosition = getInstanceWorldPosition(truck)
		if not preferredPosition then
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
		end
		if preferredPosition then
			options.PreferredPositions = {preferredPosition}
		end
	else
		preferredPosition = options.PreferredPositions[1]
	end
	local function alreadyInsideBaseCamp()
		local character = player.Character
		local root = character
			and character:FindFirstChild("HumanoidRootPart")
		return root ~= nil
			and root:IsA("BasePart")
			and instanceIsInsideRoom(root, room)
	end
	local function alreadyAtBaseCampDestination()
		if not alreadyInsideBaseCamp() then
			return false
		end
		if options.ForcePreferredPosition ~= true or not preferredPosition then
			return true
		end
		local root = player.Character
			and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return false
		end
		local offset = Vector3.new(
			root.Position.X - preferredPosition.X,
			0,
			root.Position.Z - preferredPosition.Z
		)
		return offset.Magnitude <= 6
	end
	if alreadyAtBaseCampDestination() then
		return true, nil
	end

	local succeeded, teleported, reason = pcall(function()
		return perkTrackerState.teleportToRoomBoundingBoxCenter(room, options)
	end)
	if not succeeded then
		return false, tostring(teleported):match("^[^\n]+")
	end
	return teleported, reason
end
perkTrackerState.teleportToFavouriteRoom = function(options)
	local ghost = getGhostModel()
	local roomsFolder = findRoomsFolder()
	local roomName = ghost and ghost:GetAttribute("FavoriteRoom") or nil
	local room = findFavouriteRoom(roomsFolder, roomName)
	if not room then
		return false, "Favourite room was not found: " .. tostring(roomName)
	end
	return perkTrackerState.teleportToRoomBoundingBoxCenter(room, options)
end
perkTrackerState.placeItemsInFavouriteRoom = function(owner)
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
		local function operationTeleportOptions()
			return {
				ReleaseMovementOnCancel = true,
				IsActive = operationIsActive,
			}
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
			local nextEscapeAttemptAt = 0
			local escapeFailures = 0
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
				end
				local baseRoom = perkTrackerState.findBaseCampRoom()
				local character = player.Character
				local insideBase = baseRoom and character
					and instanceIsInsideRoom(character, baseRoom)
				if not insideBase and os.clock() >= nextEscapeAttemptAt then
					-- A failed one-shot escape used to leave the player in the ghost
					-- room for the rest of the hunt. Retry until containment confirms
					-- that the character is actually in Base Camp.
					local escaped = perkTrackerState.teleportToBaseCamp(
						operationTeleportOptions()
					)
					local escapedCharacter = player.Character
					local containmentConfirmed = escaped == true
						and baseRoom ~= nil
						and escapedCharacter ~= nil
						and instanceIsInsideRoom(escapedCharacter, baseRoom)
					if containmentConfirmed then
						escapeFailures = 0
						nextEscapeAttemptAt = os.clock() + 0.15
					else
						escapeFailures = escapeFailures + 1
						nextEscapeAttemptAt = os.clock() + math.min(
							2,
							0.25 * (2 ^ math.min(escapeFailures - 1, 3))
						)
					end
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
						perkTrackerState.teleportToFavouriteRoom(
							operationTeleportOptions()
						)
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
		local function itemRequiresPositiveUses(itemName)
			local normalized = normalizeItemName(itemName)
			return normalized == normalizeItemName("Salt Canister")
				or normalized == normalizeItemName("Holy Oil")
		end
		local function itemHasRequiredUses(object, itemName)
			if not itemRequiresPositiveUses(itemName) then
				return true
			end
			return object ~= nil
				and (tonumber(object:GetAttribute("Uses")) or 0) > 0
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
			local rawMatchingItem
			local rawMatchingCount = 0
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
							rawMatchingCount = rawMatchingCount + 1
							rawMatchingItem = rawMatchingItem or child
							if itemHasRequiredUses(child, itemName) then
								matchingCount = matchingCount + 1
								matchingItem = matchingItem or child
							end
						end
					end
				end
			end
			scanContainer(player:FindFirstChild("ToolsHolder"))
			scanContainer(player.Character)
			return matchingItem,
				matchingCount,
				math.min(totalCount, inventorySlotCount),
				rawMatchingItem,
				rawMatchingCount
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
		local function storedInventorySlot(itemName, allowEmptyUses)
			local storedItem, _, _, rawStoredItem = scanStoredInventory(itemName)
			if allowEmptyUses then
				storedItem = rawStoredItem
			end
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
			if itemRequiresPositiveUses(itemName) then
				return storedInventorySlot(itemName, false)
			end
			return findHotbarSlot(itemName)
				or storedInventorySlot(itemName, false)
		end
		local function findRawInventorySlot(itemName)
			return findHotbarSlot(itemName)
				or storedInventorySlot(itemName, true)
		end
		local function countInventoryItem(itemName)
			local _, storedCount =
				scanStoredInventory(itemName)
			if itemRequiresPositiveUses(itemName) then
				return storedCount
			end
			return math.max(
				countHotbarItem(itemName),
				storedCount
			)
		end
		local function countRawInventoryItem(itemName)
			local _, _, _, _, rawStoredCount = scanStoredInventory(itemName)
			return math.max(countHotbarItem(itemName), rawStoredCount)
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
					and not itemIsConsumedCross(child)
					and itemHasRequiredUses(child, itemName) then
					return true, child
				end
			end
			return false, nil
		end
		local function moveNearWorldItem(model)
			assertOperationActive()
			if not model or not model.Parent then
				return false
			end
			local preferred, center = teleportation.ApproachPositions(model, 3.5)
			if not center or #preferred == 0 then
				return false
			end
			local room = teleportation.FindRoomForTarget(model, preferred)
			if not room then
				return false
			end
			local options = operationTeleportOptions()
			options.PreferredPositions = preferred
			options.TargetPosition = center
			options.MaximumTargetDistance = 7.5
			options.LookAtPosition = center
			options.RequireStrict = true
			return perkTrackerState.teleportToRoomBoundingBoxCenter(room, options)
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
			local beforeCount = countRawInventoryItem(itemName)
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
				local currentSlot = findRawInventorySlot(itemName)
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
					local leftInventory = countRawInventoryItem(itemName) < beforeCount
						or countRawInventoryItem(itemName) == 0
						or inventorySlotValue(slotNumber) ~= beforeSlotValue
					local worldConfirmed = not favouriteRoom
						or findWorldItemInRoom(itemName, favouriteRoom) ~= nil
					if leftInventory and worldConfirmed then
						return true
					end
					guardedWait(0.05)
				until os.clock() >= deadline
				local _, occupiedCount = inventorySnapshot()
				if countRawInventoryItem(itemName) < beforeCount
					and (not favouriteRoom
						or findWorldItemInRoom(itemName, favouriteRoom)) then
					return true
				end
				if occupiedCount < inventorySlotCount
					and countRawInventoryItem(itemName) == 0
					and (not favouriteRoom
						or findWorldItemInRoom(itemName, favouriteRoom)) then
					return true
				end
				guardedWait(0.2)
			end
			return countRawInventoryItem(itemName) < beforeCount
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
			[normalizeItemName("Spirit Book")] = true,
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
			"Spirit Book",
		}
		local optionalCoreNames = {
			[normalizeItemName("Cross")] = true,
			[normalizeItemName("EMF Reader")] = true,
			[normalizeItemName("Blacklight")] = true,
			[normalizeItemName("Video Camera")] = true,
			[normalizeItemName("Spirit Book")] = true,
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
				perkTrackerState.teleportToBaseCamp(
					operationTeleportOptions()
				)
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
				perkTrackerState.teleportToBaseCamp(
					operationTeleportOptions()
				)
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
			perkTrackerState.teleportToBaseCamp(
				operationTeleportOptions()
			)
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
				message = "The eight room items were placed; Salt Canister and Holy Oil were retained when available."
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
doRoundState.releasePlayerMovement = function(force)
	doRoundState.movementReleaseSequence =
		(doRoundState.movementReleaseSequence or 0) + 1
	local releaseSequence = doRoundState.movementReleaseSequence
	local function restoreCurrentCharacter()
		if (doRoundState.enabled and force ~= true)
			or player:GetAttribute("Dead") == true then
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
				or (doRoundState.enabled and force ~= true)
				or not runtimeIsActive() then
				return
			end
			restoreCurrentCharacter()
		end
	end)
end

-- Continue using state fields here so the factory remains below the executor's
-- compiler register ceiling as new controller helpers are added.
doRoundState.roundAutomation = createRoundAutomation({
	Services = Services,
	Player = player,
	RuntimeIsActive = runtimeIsActive,
	GetGhostModel = getGhostModel,
	FindRoomsFolder = findRoomsFolder,
	FindFavouriteRoom = findFavouriteRoom,
	FindBaseCampRoom = perkTrackerState.findBaseCampRoom,
	GetInstanceWorldPosition = getInstanceWorldPosition,
	GetRoomBoundingParts = getRoomBoundingParts,
	PointIsInsidePart = pointIsInsidePart,
	Teleportation = teleportation,
	TeleportToRoom = perkTrackerState.teleportToRoomBoundingBoxCenter,
	TeleportToBaseCamp = perkTrackerState.teleportToBaseCamp,
	TeleportToFavouriteRoom = perkTrackerState.teleportToFavouriteRoom,
	PlaceItemsInFavouriteRoom = perkTrackerState.placeItemsInFavouriteRoom,
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
doRoundState.setEnabled = function(enabled, finalPhase)
	return doRoundState.roundAutomation.SetEnabled(enabled, finalPhase)
end
doRoundState.teleportOutside = function()
	return perkTrackerState.teleportToBaseCamp()
end
doRoundState.escapeCurrentHunt = function()
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
		if doRoundState.teleportOutside() then
			huntEscapeTriggered = true
		end
	end
end
perkTrackerState.scanDeepEvidence = function()
	if not perkTrackerState.deepEvidenceWorkspaceBound then
		perkTrackerState.deepEvidenceWorkspaceBound = true
		perkTrackerState.observeDeepEvidenceObject = function(object)
			if not runtimeIsActive()
				or not object
				or not object.Parent
				or not object:IsA("BasePart") then
				return
			end
			local objectName = object.Name
			if not evidenceFound.Print
				and (
					objectName == "Handprint1"
					or objectName == "Handprint2"
					or objectName == "Footprint"
					or objectName == "Footprint1"
				) then
				local saltPiles = workspace:FindFirstChild("SaltPiles")
				if not saltPiles or not object:IsDescendantOf(saltPiles) then
					evidenceFound.Print = true
				end
			elseif not perkTrackerState.orbObserved
				and objectName == "GhostOrb" then
				perkTrackerState.orbObserved = true
			end
		end
		connect(workspace.DescendantAdded, function(object)
			if not object:IsA("BasePart") then
				return
			end
			local objectName = object.Name
			if objectName ~= "GhostOrb"
				and objectName ~= "Handprint1"
				and objectName ~= "Handprint2"
				and objectName ~= "Footprint"
				and objectName ~= "Footprint1" then
				return
			end
			-- Some replicated effects receive their final parent one scheduler step
			-- after DescendantAdded. Observe only matching names, once settled.
			task.defer(function()
				perkTrackerState.observeDeepEvidenceObject(object)
			end)
		end)
	end

	if not perkTrackerState.deepEvidenceInitialScanDone then
		perkTrackerState.deepEvidenceInitialScanDone = true
		for _, object in ipairs(workspace:GetDescendants()) do
			perkTrackerState.observeDeepEvidenceObject(object)
			if evidenceFound.Print and perkTrackerState.orbObserved then
				break
			end
		end
	end
	local descendantSnapshots = setmetatable({}, {__mode = "k"})
	local function descendantsOf(container)
		local descendants = descendantSnapshots[container]
		if not descendants then
			descendants = container:GetDescendants()
			descendantSnapshots[container] = descendants
		end
		return descendants
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
				for _, candidate in ipairs(descendantsOf(container)) do
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
								math.clamp(level, 1, 5)
							)
						end
					end
				end
			end
		end
	end

	local items = workspace:FindFirstChild("Items")
	if items and not evidenceFound.Wither then
		for _, object in ipairs(descendantsOf(items)) do
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
			if not identifiedBook then
				return false
			end
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
				for _, descendant in ipairs(descendantsOf(container)) do
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
perkTrackerState.normalizeSpiritBoxSubtitle = function(value)
	local text = tostring(value or "")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	text = string.gsub(text, "%s+", " ")
	return string.lower(text)
end
perkTrackerState.rebuildSpiritBoxVoiceIndex = function()
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
		local key = perkTrackerState.normalizeSpiritBoxSubtitle(subtitle)
		if key ~= "" then
			state.spiritBoxVoiceSubtitles[key] = true
		end
	end
	addVoice(voices)
	for _, object in ipairs(voices:GetDescendants()) do
		addVoice(object)
	end
end
perkTrackerState.updateSpiritBoxLabel = function()
	perkTrackerState.updateEvidenceStatuses()
end
perkTrackerState.processSpiritBoxRemoteSubtitle = function(firstArgument)
	if closed or type(firstArgument) ~= "string" then
		return
	end
	local state = perkTrackerState
	if next(state.spiritBoxVoiceSubtitles) == nil then
		perkTrackerState.rebuildSpiritBoxVoiceIndex()
	end
	local key = perkTrackerState.normalizeSpiritBoxSubtitle(firstArgument)
	if key == "" or not state.spiritBoxVoiceSubtitles[key] then
		return
	end
	evidenceFound.SpiritBox = true
	spiritBoxTentative = false
	local compactKey = string.gsub(key, "%s+", "")
	emitGhostObservation({
		Type = "SpiritBoxResponse",
		Qualified = true,
		Response = compactKey == "-humming-" and "- HUMMING -" or firstArgument,
		Source = "SpiritBoxSubtitleCollector",
	})
	perkTrackerState.updateSpiritBoxLabel()
	updateGhostIdentification(getGhostModel())
end
perkTrackerState.bindSpiritBoxRemoteListeners = function()
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
	perkTrackerState.rebuildSpiritBoxVoiceIndex()
	if remote and remote:IsA("RemoteEvent") then
		connect(remote.OnClientEvent, function(firstArgument)
			perkTrackerState.processSpiritBoxRemoteSubtitle(firstArgument)
		end)
	end
	if localEvent and localEvent:IsA("BindableEvent") then
		connect(localEvent.Event, function(firstArgument)
			perkTrackerState.processSpiritBoxRemoteSubtitle(firstArgument)
		end)
	end
	local voices = state.spiritBoxVoiceFolder
	if voices then
		connect(voices.DescendantAdded, perkTrackerState.rebuildSpiritBoxVoiceIndex)
		connect(voices.DescendantRemoving, perkTrackerState.rebuildSpiritBoxVoiceIndex)
	end
end
perkTrackerState.updateEvidence = function()
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
		perkTrackerState.scanDeepEvidence()
	end
	setEvidence("Print", evidenceFound.Print)
	perkTrackerState.bindSpiritBoxRemoteListeners()
	setEvidence("Inscription", evidenceFound.Inscription)
	setEvidence("Wither", evidenceFound.Wither)
	local inLaser = ghost and ghost:GetAttribute("InLaser") == true or false
	setEvidence("Laser", inLaser)
	perkTrackerState.updateOrbEvidence()
	perkTrackerState.publishEvidenceSnapshot()
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
		doRoundState.escapeCurrentHunt()
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
	return perkTrackerState.teleportToBaseCamp()
end

function Controller:TeleportToFavouriteRoom()
	return perkTrackerState.teleportToFavouriteRoom()
end

function Controller:PlaceRoomItems()
	if doRoundState.enabled then
		return false, "Do-Round currently owns room item setup"
	end
	return perkTrackerState.placeItemsInFavouriteRoom("Manual")
end

function Controller:ToggleAutoSpiritBox()
	perkTrackerState.autoSpiritBoxManualEnabled =
		not perkTrackerState.autoSpiritBoxManualEnabled
	return refreshAutoSpiritBoxEnabled()
end

function Controller:ToggleDoRound()
	return doRoundState.setEnabled(not doRoundState.enabled)
end

function Controller:SetEvidenceMode(mode)
	if mode ~= "Normal" and mode ~= "Mimicry" then
		return false, "Evidence mode must be Normal or Mimicry"
	end
	perkTrackerState.evidenceMode = mode
	if mode == "Normal" then
		perkTrackerState.updateOrbEvidence()
	end
	perkTrackerState.publishEvidenceSnapshot()
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
			local anchor = fuseBox:FindFirstChild("PromptAnchor", true)
				or fuseBox:FindFirstChildWhichIsA("BasePart", true)

			if character and anchor and anchor:IsA("BasePart") then
				local originalPosition = character:GetPivot().Position
				local originalRoom = _findRoomContainingInstance(character)
				local succeeded, actionError = xpcall(function()
					local preferred, center = teleportation.ApproachPositions(anchor, 3.5)
					local targetRoom = teleportation.FindRoomForTarget(anchor, preferred)
					if not targetRoom or not center then
						error("No room bounds were found near the fuse box", 0)
					end
					local moved, moveReason =
						perkTrackerState.teleportToRoomBoundingBoxCenter(targetRoom, {
							PreferredPositions = preferred,
							TargetPosition = center,
							MaximumTargetDistance = 8,
							LookAtPosition = center,
							RequireStrict = true,
							ReleaseMovementOnCancel = true,
							IsActive = runtimeIsActive,
						})
					if not moved then
						error("Fuse box teleport failed: " .. tostring(moveReason), 0)
					end
					Services.RunService.Heartbeat:Wait()
					if not runtimeIsActive() or player.Character ~= character then
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
				if originalRoom and runtimeIsActive()
					and player.Character == character then
					local restored = perkTrackerState.teleportToRoomBoundingBoxCenter(
						originalRoom,
						{
							PreferredPositions = {originalPosition},
							RequireStrict = true,
							ReleaseMovementOnCancel = true,
							IsActive = runtimeIsActive,
						}
					)
					if not restored and not actionFailure then
						actionFailure = "Could not return from the fuse box safely"
					end
				end
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
	if ghostCoordinator then
		ghostCoordinator:Destroy()
		ghostCoordinator = nil
	end
	perkTrackerState.ghostCoreTickAccumulator = 0
	perkTrackerState.ghostCoreSyncQueued = false
	if doRoundState.enabled then
		doRoundState.setEnabled(false, "Off")
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
		local completionWaiting = doRoundState.completionClaimed == true
		if not completionWaiting then
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
			perkTrackerState.updateAutoSpiritBox(deltaTime)
		end
		perkTrackerState.speedForceAccumulator =
			perkTrackerState.speedForceAccumulator + deltaTime
		if perkTrackerState.speedForceAccumulator >= 0.25 then
			perkTrackerState.speedForceAccumulator = 0
			applyForcedWalkSpeed()
		end
		updateAccumulator = updateAccumulator + deltaTime
		local waitingAtCamp = doRoundState.enabled
			and (doRoundState.phase == "Hunt escape"
				or doRoundState.phase == "Waiting for hunt")
		local evidenceUpdateInterval = (completionWaiting or waitingAtCamp) and 1 or 0.5
		if updateAccumulator < evidenceUpdateInterval then
			return
		end
		updateAccumulator = updateAccumulator % evidenceUpdateInterval
		if not completionWaiting then
			perkTrackerState.updateEvidence()
			doRoundState.escapeCurrentHunt()
			if doRoundState.enabled then
				setDoRoundStatus(doRoundState.phase)
			end
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

	perkTrackerState.bindSpiritBoxRemoteListeners()
	perkTrackerState.updateEvidence()
	return self
end

if generation == nil or environment.DemonologyGeneration == generation then
	environment.UntitledGuiCleanup = function()
		controller:Destroy()
	end
end

return controller
end
