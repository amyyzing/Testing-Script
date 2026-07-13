return function(dependencies)
	dependencies = dependencies or {}
	local Services = assert(dependencies.Services, "logic/logic.luau requires Services")
	local player = dependencies.Player or Services.Players.LocalPlayer
	local environment = dependencies.Environment or ((getgenv and getgenv()) or _G)
	local generation = dependencies.Generation
	local GhostModule = assert(dependencies.GhostModule, "logic/logic.luau requires GhostModule")
	local GhostPackage = assert(dependencies.GhostPackage, "logic/logic.luau requires GhostPackage")
	local GhostSession = assert(
		GhostPackage.Session,
		"logic/logic.luau requires GhostPackage.Session"
	)
	local createGhostObservationRuntime = assert(
		GhostPackage.CreateRuntime,
		"logic/logic.luau requires GhostPackage.CreateRuntime"
	)
	local createGhostObservationCollector = assert(
		GhostPackage.CreateCollector,
		"logic/logic.luau requires GhostPackage.CreateCollector"
	)
	local createGhostTracker = assert(
		GhostPackage.CreateTracker,
		"logic/logic.luau requires GhostPackage.CreateTracker"
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
	restoreAttempts = setmetatable({}, {__mode = "k"}),
	nextRestoreAt = setmetatable({}, {__mode = "k"}),
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
local perkDetections
local resetEvidenceState = function() end
local evidenceRoundGhost
local trackedItemsFolder
local itemsDescendantAddedConnection
local itemEnabledTracked = setmetatable({}, {__mode = "k"})
local itemEnabledStates = setmetatable({}, {__mode = "k"})
local lastDeepEvidenceScan = -math.huge
local ghostProxyDirty = false
local ghostProxyAddedConnection
local ghostProxyRemovingConnection
local observeWalkSpeedChange = function() end
local ghostObservationRuntime
local perkTrackerState = {
	ghost = nil,
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
	lastLidarInvisibleValue = nil,
	updateLidarStateObservation = function() end,
	pendingHuntTransitionSamples = {},
	lastQueuedHuntState = nil,
	huntTransitionSequence = 0,
	queueHuntTransitionSample = function() end,
	rootSoundScanComplete = false,
	previousDead = {},
	killSpeedProcessedPlayers = setmetatable({}, {__mode = "k"}),
	huntStartedAt = nil,
	brokenGlassInitialized = false,
	brokenGlassSeen = {},
	lightObservationAccumulator = 0,
	itemTagTrackerInitialized = false,
	suppressItemDisableUntil = 0,
	suppressRoomLightObservationsUntil = 0,
	saltTrackerInitialized = false,
	saltFolder = nil,
	saltTrackedLines = setmetatable({}, {__mode = "k"}),
	saltPendingTouches = {},
	saltOverlapAccumulator = 0,
	holyOilFolder = nil,
	holyOilTrackerInitialized = false,
	holyOilTrackedModels = setmetatable({}, {__mode = "k"}),
	evaluateHolyOilAtHuntStart = function() end,
	flashButton = function() end,
	itemEspChildConnection = nil,
	objectTeleportTrackerInitialized = false,
	objectTeleportObjects = setmetatable({}, {__mode = "k"}),
	objectTeleportAccumulator = 0,
	lastObservedRoom = nil,
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
	ruledOutGhosts = {},
	refreshIdentification = function() end,
	automationMutationUntil = 0,
}
-- Keep spatial and automation helpers behind one explicitly dynamic table.  This
-- prevents Luau from having to infer them as part of the already-large tracker
-- state record while still avoiding a separate register for every helper.
local automationHelpers: any = {}
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
	for ghostName, detection in pairs(perkDetections) do
		if not perkTrackerState.ruledOutGhosts[ghostName] then
			table.insert(positives, {
				Ghost = ghostName,
				Reason = detection.Reason,
				Confidence = detection.Confidence,
				At = detection.DetectedAt,
			})
		end
	end
	for ghostName, ruledOut in pairs(perkTrackerState.ruledOutGhosts) do
		table.insert(negatives, {
			Ghost = ghostName,
			Reason = ruledOut.Reason,
			Confidence = ruledOut.Confidence,
			At = ruledOut.At,
		})
	end
	presenter:SetPerkLogs(positives, negatives)
end
local ghostTracker = createGhostTracker({
	Catalog = GhostModule,
	OnChanged = function()
		refreshPerkLogs()
	end,
})
perkDetections = ghostTracker.Detections
perkTrackerState.ruledOutGhosts = ghostTracker.RuleOuts
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
perkTrackerState.ruleOutGhost = function(ghostName, reason, confidence)
	local changed = ghostTracker:RuleOut(ghostName, reason, confidence)
	if changed then
		perkTrackerState.refreshIdentification()
	end
	return changed
end
perkTrackerState.clearGhostRuleOut = function(ghostName)
	return ghostTracker:ClearRuleOut(ghostName)
end
perkTrackerState.isGhostRuledOut = function(ghostName)
	return ghostTracker:IsRuledOut(ghostName)
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
local function ghostSessionInput(confirmed, now)
	return {
		Mode = perkTrackerState.evidenceMode,
		ConfirmedEvidence = confirmed or getConfirmedEvidence(),
		ObservedEvidence = getObservedEvidence(),
		SpiritBoxTentative = spiritBoxTentative,
		OrbObserved = perkTrackerState.orbObserved,
		Detections = perkDetections,
		RuleOuts = perkTrackerState.ruledOutGhosts,
		Now = now,
	}
end
local function ghostSupportsConfirmedEvidence(
	ghostName,
	confirmed,
	ignoreRuleOut
)
	return GhostSession.SupportsSessionEvidence(
		ghostName,
		ghostSessionInput(confirmed),
		ignoreRuleOut == true
	)
end
perkTrackerState.getRemainingCandidates = function(ignoreRuleOut)
	return GhostSession.GetCandidates(
		ghostSessionInput(nil, os.clock()),
		ignoreRuleOut == true
	)
end
perkTrackerState.updateEvidenceStatuses = function()
	local evaluation = GhostSession.Evaluate(ghostSessionInput(nil, os.clock()))
	local possible = evaluation.PossibleEvidence
	local confirmed = evaluation.ConfirmedEvidence
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
local function pruneExpiredPerkDetections(now)
	return ghostTracker:Prune(now)
end

local function updateGhostIdentification(ghost)
	local now = os.clock()
	pruneExpiredPerkDetections(now)
	local evaluation = GhostSession.Evaluate(ghostSessionInput(nil, now))
	local guess = evaluation.FinalGuess
	if guess then
		perkTrackerState.currentGhostGuess = guess.Ghost
		perkTrackerState.currentGhostGuessScore = guess.Confidence or 0
		perkTrackerState.currentGhostGuessCertain = guess.Certain == true
		setGhostIdentificationLabel(
			guess.Ghost,
			guess.Confidence or 0,
			guess.Certain == true
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
local function observationWorldPosition(instance)
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
local function nearestAlivePlayerDistance(target)
	local targetPosition = observationWorldPosition(target)
	if not targetPosition then
		return math.huge
	end
	local nearest = math.huge
	for _, targetPlayer in ipairs(Services.Players:GetPlayers()) do
		if targetPlayer:GetAttribute("Dead") ~= true then
			local root = targetPlayer.Character
				and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
			if root then
				nearest = math.min(nearest, (root.Position - targetPosition).Magnitude)
			end
		end
	end
	return nearest
end
local function observationDistances(ghost, target)
	local targetPosition = observationWorldPosition(target)
	local ghostPosition = observationWorldPosition(ghost)
	return targetPosition and ghostPosition
		and (ghostPosition - targetPosition).Magnitude
		or nil,
		nearestAlivePlayerDistance(target)
end
perkTrackerState.recordItemToggleObservation = function(object, previous, current)
	if typeof(previous) ~= "boolean"
		or typeof(current) ~= "boolean"
		or previous == current then
		return
	end
	local model = perkTrackerState.getTrackedWorldItemModel(object)
	if not model then
		return
	end
	local now = os.clock()
	local ghost = workspace:FindFirstChild("Ghost")
	if ghost and not ghost:IsA("Model") then
		ghost = nil
	end
	local hunting = ghost and ghost:GetAttribute("Hunting") == true
	local ghostDistance, playerDistance = observationDistances(ghost, model)
	ghostObservationRuntime:ItemToggle({
		RawObservation = true,
		Time = now,
		ItemId = model,
		ItemName = tostring(model:GetAttribute("ItemName") or ""),
		Previous = previous,
		Current = current,
		Hunting = hunting,
		Suppressed = now < perkTrackerState.suppressItemDisableUntil,
		GhostDistance = ghostDistance,
		NearestPlayerDistance = playerDistance,
		ElectronicDisabled = previous == true and current == false,
	})
end
perkTrackerState.updateRoomLightObservations = function(ghost, hunting, deltaTime, now)
	perkTrackerState.lightObservationAccumulator =
		perkTrackerState.lightObservationAccumulator + deltaTime
	if perkTrackerState.lightObservationAccumulator < 0.2 then
		return
	end
	perkTrackerState.lightObservationAccumulator = 0
	local map = workspace:FindFirstChild("Map")
	local rooms = map and map:FindFirstChild("Rooms")
	if not rooms then
		return
	end
	local fuseBox = map:FindFirstChild("FuseBox", true)
	for _, room in ipairs(rooms:GetChildren()) do
		local lightsOn = room:GetAttribute("LightsOn")
		local lightSwitch = room:FindFirstChild("LightSwitch", true)
		local switchState = lightSwitch
			and lightSwitch:GetAttribute("State")
		if typeof(lightsOn) == "boolean"
			or typeof(switchState) == "boolean" then
			local target = lightSwitch or room
			local ghostDistance, playerDistance = observationDistances(
				ghost,
				target
			)
			ghostObservationRuntime:LightToggle({
				RawObservation = true,
				Time = now,
				RoomId = room,
				Room = room.Name,
				LightsOn = typeof(lightsOn) == "boolean" and lightsOn or nil,
				SwitchState = typeof(switchState) == "boolean" and switchState or nil,
				SwitchPresent = lightSwitch ~= nil,
				LightsBroken = room:GetAttribute("LightsBroken") == true,
				FuseEnabled = fuseBox ~= nil
					and fuseBox:GetAttribute("Enabled") == true,
				Hunting = hunting == true,
				Suppressed = now
					< perkTrackerState.suppressRoomLightObservationsUntil,
				GhostDistance = ghostDistance,
				NearestPlayerDistance = playerDistance,
			})
		end
	end
end
local function bindTrackedEnabledItem(object)
	if not object or itemEnabledTracked[object] then
		return
	end
	local inItemsFolder =
		trackedItemsFolder
		and object:IsDescendantOf(trackedItemsFolder)
	local model = perkTrackerState.getTrackedWorldItemModel(object)
	if not inItemsFolder and not model then
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
		perkTrackerState.recordItemToggleObservation(
			object,
			previous,
			current
		)
	end)
end
perkTrackerState.bindTaggedEnabledItem = function(model)
	if closed
		or not model
		or not model:IsA("Model")
		or not model:IsDescendantOf(workspace)
		or not Services.CollectionService:HasTag(model, "Item") then
		return
	end
	bindTrackedEnabledItem(model)
	for _, object in ipairs(model:GetDescendants()) do
		if object:GetAttribute("Enabled") ~= nil then
			bindTrackedEnabledItem(object)
		end
	end
end
local function rebaselineItemEnabledTracker()
	for object in pairs(itemEnabledTracked) do
		if object.Parent ~= nil then
			itemEnabledStates[object] = object:GetAttribute("Enabled")
		end
	end
end
local function ensureItemEnabledTracker()
	if not perkTrackerState.itemTagTrackerInitialized then
		perkTrackerState.itemTagTrackerInitialized = true
		for _, model in ipairs(
			Services.CollectionService:GetTagged("Item")
		) do
			perkTrackerState.bindTaggedEnabledItem(model)
		end
		connect(
			Services.CollectionService:GetInstanceAddedSignal("Item"),
			function(model)
				task.defer(function()
					perkTrackerState.bindTaggedEnabledItem(model)
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
					perkTrackerState.bindTaggedEnabledItem(model)
				elseif object:GetAttribute("Enabled") ~= nil then
					bindTrackedEnabledItem(object)
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
	if not items then
		return
	end
	for _, object in ipairs(items:GetChildren()) do
		bindTrackedEnabledItem(object)
	end
	for _, object in ipairs(items:GetDescendants()) do
		if object:GetAttribute("Enabled") ~= nil then
			bindTrackedEnabledItem(object)
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
					bindTrackedEnabledItem(object)
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
resetEvidenceState = function()
	rebaselineItemEnabledTracker()
	for evidenceName in pairs(evidenceFound) do
		evidenceFound[evidenceName] = false
	end
	freezingEvidenceFound = false
	lowestRecordedTemperature = nil
	highestEMF = 1
	spiritBoxTentative = false
	perkTrackerState.orbObserved = false
	perkTrackerState.lidarVisibleObserved = false
	perkTrackerState.lightObservationAccumulator = 0
	perkTrackerState.suppressItemDisableUntil = 0
	perkTrackerState.suppressRoomLightObservationsUntil = 0
	perkTrackerState.saltPendingTouches = {}
	perkTrackerState.saltOverlapAccumulator = 0
	ghostTracker:Reset()
	perkTrackerState.currentGhostGuess = nil
	perkTrackerState.currentGhostGuessScore = 0
	perkTrackerState.currentGhostGuessCertain = false
	perkTrackerState.objectTeleportObjects =
		setmetatable({}, {__mode = "k"})
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
local function resetPerkTrackerForGhost(ghost, preserveFindings)
	local previousGhost = perkTrackerState.ghost
	local currentMap = workspace:FindFirstChild("Map")
	preserveFindings = preserveFindings == true
		and currentMap ~= nil
		and perkTrackerState.roundMap == currentMap
	if previousGhost and ghost ~= previousGhost then
		if not preserveFindings then
			resetEvidenceState()
		end
		evidenceRoundGhost = ghost
	end
	ghostTracker:Reset({PreserveFindings = preserveFindings})
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
		perkTrackerState.huntingAttributeConnection:Disconnect()
		perkTrackerState.huntingAttributeConnection = nil
	end
	local initialHunting = if ghost
		then ghost:GetAttribute("Hunting") == true
		else nil
	perkTrackerState.lastHunting = initialHunting
	perkTrackerState.motionSamples = {}
	perkTrackerState.lastLidarInvisibleValue = nil
	perkTrackerState.pendingHuntTransitionSamples = {}
	perkTrackerState.lastQueuedHuntState = initialHunting
	perkTrackerState.huntTransitionSequence = 0
	perkTrackerState.rootSoundScanComplete = false
	if ghost then
		perkTrackerState.huntingAttributeConnection = connect(
			ghost:GetAttributeChangedSignal("Hunting"),
			function()
				if closed or perkTrackerState.ghost ~= ghost then
					return
				end
				perkTrackerState.queueHuntTransitionSample(
					ghost:GetAttribute("Hunting") == true,
					os.clock()
				)
			end
		)
		task.defer(function()
			if not closed and perkTrackerState.ghost == ghost then
				perkTrackerState.updateLidarStateObservation(ghost)
			end
		end)
	end
	perkTrackerState.previousDead = {}
	perkTrackerState.killSpeedProcessedPlayers = setmetatable({}, {__mode = "k"})
	perkTrackerState.huntStartedAt = nil
	perkTrackerState.brokenGlassInitialized = false
	perkTrackerState.brokenGlassSeen = {}
	perkTrackerState.lightObservationAccumulator = 0
	perkTrackerState.suppressRoomLightObservationsUntil = 0
	perkTrackerState.saltPendingTouches = {}
	perkTrackerState.saltOverlapAccumulator = 0
	perkTrackerState.orbObserved = false
	perkTrackerState.lidarVisibleObserved = false
	perkTrackerState.objectTeleportObjects = setmetatable({}, {__mode = "k"})
	perkTrackerState.objectTeleportAccumulator = 0
	perkTrackerState.lastObservedRoom = ghost and ghost:GetAttribute("CurrentRoom") or nil
	perkTrackerState.activeCrossBurns = setmetatable({}, {__mode = "k"})
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

			if visualModel ~= "" then
				ghostObservationRuntime:Dispatch("OnFemaleIndicator", {
					Model = visualModel,
					Source = "VisualModel",
				})
			end
		end)
	end
	if ghostObservationRuntime then
		ghostObservationRuntime:Reset({
			Ghost = ghost,
			Map = currentMap,
			PreserveFindings = preserveFindings,
			Hunting = initialHunting == true,
			Time = os.clock(),
		})
	end
end
local function getGhostTransparencyState(ghost)
	local transparency = ghost and ghost:GetAttribute("Transparency") or nil
	if typeof(transparency) == "boolean" then
		return transparency
	end
	if transparency == 0 or transparency == 1 then
		return transparency == 1
	end
	-- The replicated binary attribute is the phase authority.  Skipping an
	-- absent/transitional value is safer than inferring a phase from visual
	-- parts whose replication can trail the Humanoid WalkSpeed change.
	return nil
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
perkTrackerState.queueHuntTransitionSample = function(hunting, now)
	if perkTrackerState.lastQueuedHuntState == hunting then
		return false
	end
	perkTrackerState.lastQueuedHuntState = hunting
	perkTrackerState.huntTransitionSequence =
		perkTrackerState.huntTransitionSequence + 1
	local sequence = perkTrackerState.huntTransitionSequence
	local sanity = getAverageTeamEnergy()
	if typeof(sanity) ~= "number" then
		return false
	end
	local ghost = perkTrackerState.ghost
	if not ghost then
		return false
	end
	local pending = perkTrackerState.pendingHuntTransitionSamples
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
automationHelpers.distanceFromPositionToInstance = function(position, instance)
	if not position or not instance then
		return math.huge
	end
	local closestDistance = math.huge
	local function inspectPart(part)
		local localPoint = part.CFrame:PointToObjectSpace(position)
		local half = part.Size * 0.5
		local closestLocal = Vector3.new(
			math.clamp(localPoint.X, -half.X, half.X),
			math.clamp(localPoint.Y, -half.Y, half.Y),
			math.clamp(localPoint.Z, -half.Z, half.Z)
		)
		local closestWorld = part.CFrame:PointToWorldSpace(closestLocal)
		closestDistance = math.min(
			closestDistance,
			(position - closestWorld).Magnitude
		)
	end
	if instance:IsA("BasePart") then
		inspectPart(instance)
	else
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				inspectPart(descendant)
			end
		end
	end
	if closestDistance < math.huge then
		return closestDistance
	end
	local fallback = getInstanceWorldPosition(instance)
	return fallback and (position - fallback).Magnitude or math.huge
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
automationHelpers.partBelongsToHeldCharacterItem = function(part, character)
	local current = part
	while current and current ~= character do
		if current:IsA("Accessory") then
			return true
		end
		if current:IsA("Model")
			and current:GetAttribute("ItemName") ~= nil then
			return true
		end
		if current:IsA("Model") and current.Parent == character then
			for _, descendant in ipairs(current:GetDescendants()) do
				if descendant:GetAttribute("ItemName") ~= nil then
					return true
				end
			end
		end
		current = current.Parent
	end
	return false
end
automationHelpers.instanceFullyInsideBoundingPartsXZ = function(
	instance,
	boundingParts,
	excludeHeldCharacterItems
)
	if not instance or not boundingParts or #boundingParts == 0 then
		return false
	end
	local checkedParts = 0
	local function pointInsideBounds(point)
		for _, bounds in ipairs(boundingParts) do
			if bounds and bounds:IsA("BasePart") then
				local localPoint = bounds.CFrame:PointToObjectSpace(point)
				local half = bounds.Size * 0.5
				if math.abs(localPoint.X) <= half.X + 0.03
					and math.abs(localPoint.Z) <= half.Z + 0.03 then
					return true
				end
			end
		end
		return false
	end
	local function inspectPart(part)
		if excludeHeldCharacterItems
			and automationHelpers.partBelongsToHeldCharacterItem(part, instance) then
			return true
		end
		checkedParts = checkedParts + 1
		local half = part.Size * 0.5
		for _, x in ipairs({-half.X, half.X}) do
			for _, y in ipairs({-half.Y, half.Y}) do
				for _, z in ipairs({-half.Z, half.Z}) do
					if not pointInsideBounds(
						part.CFrame:PointToWorldSpace(Vector3.new(x, y, z))
					) then
						return false
					end
				end
			end
		end
		return true
	end
	if instance:IsA("BasePart") then
		return inspectPart(instance) and checkedParts > 0
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") and not inspectPart(descendant) then
			return false
		end
	end
	return checkedParts > 0
end
automationHelpers.characterIsFullyInsideRoom = function(character, room)
	return automationHelpers.instanceFullyInsideBoundingPartsXZ(
		character,
		getRoomBoundingParts(room),
		true
	)
end
automationHelpers.worldItemIsBurntCross = function(item: any): boolean
	if not item then
		return false
	end
	local itemName = string.lower(tostring(item:GetAttribute("ItemName") or item.Name))
	if itemName ~= "cross" and not string.find(itemName, "cross", 1, true) then
		return false
	end
	local function isBurnt(object: any): boolean
		if object:GetAttribute("Burned") == true
			or object:GetAttribute("Burnt") == true
			or object:GetAttribute("Burning") == true then
			return true
		end
		if (object:IsA("ParticleEmitter")
				or object:IsA("Fire")
				or object:IsA("Smoke")
				or object:IsA("Beam")
				or object:IsA("Trail"))
			and object.Enabled == true then
			return true
		end
		local name = string.lower(tostring(object.Name))
		return string.find(name, "burned", 1, true) ~= nil
			or string.find(name, "burnt", 1, true) ~= nil
	end
	if isBurnt(item) then
		return true
	end
	for _, descendant: any in ipairs(item:GetDescendants()) do
		if isBurnt(descendant) then
			return true
		end
	end
	return false
end
automationHelpers.worldItemIsFullyInsideRoom = function(item: any, room: any): boolean
	if not item or not item.Parent or not room
		or automationHelpers.worldItemIsBurntCross(item) then
		return false
	end
	local boundingParts: any = getRoomBoundingParts(room)
	if #boundingParts == 0 then
		return false
	end
	local itemFrame: any
	local itemSize: any
	if item:IsA("BasePart") then
		itemFrame = item.CFrame
		itemSize = item.Size
	elseif item:IsA("Model") then
		local ok, frame, size = pcall(item.GetBoundingBox, item)
		if ok then
			itemFrame = frame
			itemSize = size
		end
	end
	if not itemFrame or not itemSize then
		return false
	end

	-- Require the model volume itself (not just its pivot's X/Z) to overlap the
	-- lower portion of a room bound.  Sampling its center and bottom footprint
	-- catches ordinary item-sized models without accepting roof placements.
	local half: any = itemSize * 0.5
	local samplePoints: any = {
		itemFrame.Position,
		itemFrame:PointToWorldSpace(Vector3.new(0, -half.Y, 0)),
		itemFrame:PointToWorldSpace(Vector3.new(-half.X, -half.Y, -half.Z)),
		itemFrame:PointToWorldSpace(Vector3.new(-half.X, -half.Y, half.Z)),
		itemFrame:PointToWorldSpace(Vector3.new(half.X, -half.Y, -half.Z)),
		itemFrame:PointToWorldSpace(Vector3.new(half.X, -half.Y, half.Z)),
	}
	local touchesRoomVolume: boolean = false
	for _, point: any in ipairs(samplePoints) do
		for _, bounds: any in ipairs(boundingParts) do
			local localPoint: any = bounds.CFrame:PointToObjectSpace(point)
			local boundsHalf: any = bounds.Size * 0.5
			if math.abs(localPoint.X) <= boundsHalf.X + 0.05
				and math.abs(localPoint.Y) <= boundsHalf.Y + 0.05
				and math.abs(localPoint.Z) <= boundsHalf.Z + 0.05
				and localPoint.Y <= boundsHalf.Y * 0.35 then
				touchesRoomVolume = true
				break
			end
		end
		if touchesRoomVolume then
			break
		end
	end
	if not touchesRoomVolume then
		return false
	end

	-- Reject placements intersecting collidable furniture, walls, or meshes.
	-- A supporting floor whose top is at the item's bottom is intentionally
	-- allowed; room-volume helper parts and the local character are ignored.
	local overlapParams: any = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {item, player.Character}
	overlapParams.MaxParts = 48
	local querySize: any = itemSize + Vector3.new(0.6, 0.4, 0.6)
	local itemBottom: number = itemFrame.Position.Y - itemSize.Y * 0.5
	local boundingSet: any = {}
	for _, bounds: any in ipairs(boundingParts) do
		boundingSet[bounds] = true
	end
	for _, blocker: any in ipairs(workspace:GetPartBoundsInBox(itemFrame, querySize, overlapParams)) do
		if blocker.CanCollide
			and not boundingSet[blocker] then
			local blockerTop: number = blocker.Position.Y + blocker.Size.Y * 0.5
			if blockerTop > itemBottom + 0.35 then
				return false
			end
		end
	end
	return true
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
automationHelpers.worldItemIsInsideRoomBounds = function(item: any, room: any): boolean
	local itemsFolder: any = workspace:FindFirstChild("Items")
	if not itemsFolder
		or not item
		or item.Parent ~= itemsFolder
		or not item:IsA("Model") then
		return false
	end
	local itemName: any = item:GetAttribute("ItemName")
	if typeof(itemName) ~= "string" or itemName == "" then
		return false
	end
	-- Membership is intentionally only a model-position-in-any-bound check.
	-- Collision/open-space/lower-height rules belong to prospective placement,
	-- not to deciding whether an existing Workspace.Items model is already in
	-- its favourite room.
	if instanceIsInsideRoom(item, room) then
		return true
	end
	-- Some item models use an offset pivot. The geometric center is a safe
	-- representative fallback without requiring every part/corner to fit.
	local ok: boolean, frame: any = pcall(function(): any
		return item:GetBoundingBox()
	end)
	if not ok or not frame then
		return false
	end
	for _, bounds: any in ipairs(getRoomBoundingParts(room)) do
		if pointIsInsidePart(bounds, frame.Position) then
			return true
		end
	end
	return false
end
local function findRoomContainingInstance(instance)
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
local function lightingContextKey(roomName, lit)
	if roomName == nil or lit == nil then
		return nil
	end
	return string.lower(tostring(roomName)) .. "|" .. (lit and "lit" or "dark")
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
perkTrackerState.updateLidarStateObservation = function(ghost)
	if not ghost or perkTrackerState.ghost ~= ghost then
		return
	end
	local value =
		readReplicatedGhostValue(ghost, "InvisibleOnLIDAR")
	local invisible = typeof(value) == "boolean" and value or nil
	local changed = invisible ~= perkTrackerState.lastLidarInvisibleValue
	perkTrackerState.lastLidarInvisibleValue = invisible
	ghostObservationRuntime:Dispatch("OnLidarState", {
		Invisible = invisible,
		Changed = changed,
	})
end
local function scanNewBrokenGlass()
	local brokenGlassFolder = workspace:FindFirstChild("BrokenGlass")
	if not brokenGlassFolder then
		return 0
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
		return 0
	end
	local addedCount = 0
	for object in pairs(current) do
		if not perkTrackerState.brokenGlassSeen[object] then
			addedCount = addedCount + 1
		end
	end
	perkTrackerState.brokenGlassSeen = current
	return addedCount
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
			ghostObservationRuntime:Dispatch("OnPlayerDeath", {
				Time = now,
				PlayerId = targetPlayer,
				Hunting = true,
				UniqueSpeedKill = uniqueSpeedKill,
				OtherAlive = otherAlive,
				HuntAge =
					perkTrackerState.huntStartedAt
					and now - perkTrackerState.huntStartedAt
					or 0,
			})
		end
		perkTrackerState.previousDead[targetPlayer] = dead
	end
end
local function handleHuntTransition(ghost, hunting, now)
	local previous = perkTrackerState.lastHunting
	if previous == nil then
		perkTrackerState.lastHunting = hunting
		if hunting then
			ghostObservationRuntime:HuntTransition({
				Hunting = true,
				Time = now,
				Force = true,
				MapFactor = getMapSizeSpeedFactor(),
			})
		end
		return
	end
	if hunting ~= previous then
		ghostObservationRuntime:HuntTransition({
			Hunting = hunting,
			Time = now,
			MapFactor = getMapSizeSpeedFactor(),
		})
		perkTrackerState.queueHuntTransitionSample(hunting, now)
	end
	if hunting and not previous then
		perkTrackerState.evaluateHolyOilAtHuntStart(ghost)
		perkTrackerState.huntStartedAt = now
		perkTrackerState.motionSamples = {}
	elseif not hunting and previous then
		perkTrackerState.huntStartedAt = nil
	end
	perkTrackerState.lastHunting = hunting
end
local function capturePendingHuntTransitionSample(ghost, now)
	local pendingTransitions = perkTrackerState.pendingHuntTransitionSamples
	for index = #pendingTransitions, 1, -1 do
		local pending = pendingTransitions[index]
		local wrongState = not ghost
			or pending.Ghost ~= ghost
			or pending.Sequence ~= perkTrackerState.huntTransitionSequence
			or (ghost:GetAttribute("Hunting") == true) ~= pending.Hunting
		if wrongState or now > pending.ExpiresAt then
			table.remove(pendingTransitions, index)
		elseif now >= pending.CaptureAt then
			local humanoid = ghost:FindFirstChildOfClass("Humanoid")
			local walkSpeed = humanoid and humanoid.WalkSpeed or nil
			if typeof(walkSpeed) == "number" and walkSpeed > 0 then
				ghostObservationRuntime:HuntTransitionSample({
					Time = now,
					TransitionAt = pending.TransitionAt,
					Sanity = math.clamp(tonumber(pending.Sanity) or 0, 0, 100),
					Speed = walkSpeed,
					Hunting = pending.Hunting,
					MapFactor = getMapSizeSpeedFactor(),
				})
				table.remove(pendingTransitions, index)
			end
		end
	end
end
local function feedGhostRoomPresence(ghost, hunting, now)
	if not ghost then
		return
	end
	local favouriteName = ghost:GetAttribute("FavoriteRoom")
	local currentName = ghost:GetAttribute("CurrentRoom")
	local roomsFolder = findRoomsFolder()
	local favouriteRoom = type(favouriteName) == "string"
		and findFavouriteRoom(roomsFolder, favouriteName)
		or nil
	local currentRoom = type(currentName) == "string"
		and findFavouriteRoom(roomsFolder, currentName)
		or nil
	ghostObservationRuntime:RoomPresence({
		Time = now,
		Hunting = hunting,
		CurrentRoom = currentRoom and currentRoom.Name or currentName,
		FavouriteRoom = favouriteRoom and favouriteRoom.Name or favouriteName,
		CurrentRoomContainsGhost = currentRoom ~= nil
			and instanceIsInsideRoom(ghost, currentRoom),
		FavouriteRoomContainsGhost = favouriteRoom ~= nil
			and instanceIsInsideRoom(ghost, favouriteRoom),
	})
end
perkTrackerState.dispatchResidualEvidenceObservation = function(ghost)
	if not ghost then
		return
	end
	ghostObservationRuntime:Dispatch("OnResidualEvidence", {
		Freezing = freezingEvidenceFound,
		Wither = evidenceFound.Wither,
		LidarVisible = perkTrackerState.lidarVisibleObserved,
	})
end
local function dispatchRootSoundObservation(ghost)
	if not ghost or perkTrackerState.rootSoundScanComplete then
		return
	end
	local rootHasExtraSound = ghostRootHasAnySound(ghost)
	if rootHasExtraSound == nil then
		return
	end
	perkTrackerState.rootSoundScanComplete = true

	ghostObservationRuntime:Dispatch("OnRootSoundScan", {
		HasOtherSound = rootHasExtraSound,
	})
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
perkTrackerState.ensureCrossBurnTracker = function()
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
perkTrackerState.updateCrossBurnTracker = function(now)
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
		end
		ghostObservationRuntime:Cross({
			ObservationId = model,
			Age = now - observation.StartTime,
			Failed = failedBecauseRemoved,
			AccumulatedAngle = observation.AccumulatedAngle,
			MaxRise = observation.MaxRise,
			MaxHorizontalTravel = observation.MaxHorizontalTravel,
		})
		if failedBecauseRemoved or now - observation.StartTime >= 4 then
			state.activeCrossBurns[model] = nil
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
			SawHuntingSample = false,
			HuntEnded = false,
			HuntEndedAt = nil,
			Disturbed = false,
			Phase = "AwaitDisturbance",
			Synthetic = true,
		}
	end

	if sourceModel ~= disturbedModel then
		pending[sourceModel] = nil
	end
	pending[disturbedModel] = observation
	observation.Position = disturbedPosition or observation.Position
	observation.Disturbed = true
	observation.DisturbedAt = now
	observation.SpeedSamples = observation.SpeedSamples or {}
	observation.Phase = "SeekDrop"
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
			true
	end
	local humanoid = ghost and ghost:FindFirstChildOfClass("Humanoid")
	local liveSpeed = humanoid and humanoid.WalkSpeed or nil
	if typeof(liveSpeed) == "number" and liveSpeed > 0 then
		-- Salt can be reached on the first hunting tick, before three rolling
		-- samples exist.  The live pre-contact value is still a usable baseline;
		-- a later low-then-recovery sequence independently validates it.
		return liveSpeed, 0, true
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
		SawHuntingSample = false,
		HuntEnded = false,
		HuntEndedAt = nil,
		Disturbed = false,
		Phase = "AwaitDisturbance",
		Synthetic = false,
	}
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
	local pendingSaltTouches: any = perkTrackerState.saltPendingTouches
	for saltModel: any, observation: any in pairs(pendingSaltTouches) do
		local age = now - observation.StartedAt
		ghostObservationRuntime:Salt({
			ContactId = saltModel,
			TouchObserved = true,
			SaltDisturbed = observation.Disturbed == true,
			Age = age,
			Source = "SaltContact",
		})

		-- A hunting contact also streams raw speed samples. Once that hunt ends,
		-- retain the collected samples for delayed observer evaluation.
		if observation.Ghost == ghost
			and observation.HuntingAtTouch == true then
			if hunting and not observation.HuntEnded
				and typeof(currentSpeed) == "number"
				and currentSpeed > 0
				and (
					not observation.LastSpeedSampleAt
					or now - observation.LastSpeedSampleAt >= 0.075
				) then
				observation.SawHuntingSample = true
				observation.LastSpeedSampleAt = now
				observation.SpeedSamples = observation.SpeedSamples or {}
				table.insert(observation.SpeedSamples, {
					Time = now,
					Speed = currentSpeed,
				})
			elseif not hunting and not observation.HuntEnded then
				observation.HuntEnded = true
				observation.HuntEndedAt = now
			end
		end

		if observation.Ghost == ghost
			and observation.HuntingAtTouch == true then
			ghostObservationRuntime:Salt({
				ContactId = saltModel,
				HuntingAtTouch = true,
				SaltDisturbed = observation.Disturbed == true,
				PreSpeed = observation.PreSpeed,
				BaselineReliable = observation.BaselineReliable,
				PreSampleCount = observation.PreSampleCount,
				SpeedSamples = observation.SpeedSamples or {},
				Age = age,
				HuntEnded = observation.HuntEnded == true,
				Source = "SaltContact",
			})
		end
		local observationAge = now
			- (observation.DisturbedAt or observation.StartedAt)
		local preserveActiveHunt = hunting
			and observation.HuntingAtTouch == true
			and not observation.HuntEnded
		local preserveHuntEdge = observation.HuntEndedAt
			and now - observation.HuntEndedAt < 1
		if (observationAge >= 10
			and not preserveActiveHunt
			and not preserveHuntEdge)
			or observation.Ghost ~= ghost then
			perkTrackerState.saltPendingTouches[saltModel] = nil
		end
	end
end
perkTrackerState.getHolyOilWall = function(model)
	local wall = model and model:FindFirstChild("GhostWall", true)
	return wall and wall:IsA("BasePart") and wall or nil
end

perkTrackerState.getHolyOilColorSequences = function(model)
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

	local function readSequence(emitter)
		local keypoints = emitter.Color.Keypoints
		if #keypoints < 2 then
			return nil
		end
		local first = keypoints[1]
		local last = keypoints[#keypoints]
		return {
			FirstTime = first.Time,
			LastTime = last.Time,
			First = {
				R = first.Value.R,
				G = first.Value.G,
				B = first.Value.B,
			},
			Last = {
				R = last.Value.R,
				G = last.Value.G,
				B = last.Value.B,
			},
		}
	end
	local primarySequence = readSequence(primary)
	local secondarySequence = readSequence(secondary)
	if not primarySequence or not secondarySequence then
		return nil
	end
	return {Primary = primarySequence, Secondary = secondarySequence}
end

perkTrackerState.evaluateHolyOilWallStates = function(ghost)
	ghost = ghost or getGhostModel()
	if not ghost then
		return nil
	end
	local eligibleWallCount = 0
	local nonCollidableWallCount = 0

	for model in pairs(perkTrackerState.holyOilTrackedModels) do
		if model.Parent
			and model:GetAttribute("Burning") == true then
			local wall = perkTrackerState.getHolyOilWall(model)
			if wall then
				eligibleWallCount = eligibleWallCount + 1
				if wall.CanCollide == false then
					nonCollidableWallCount = nonCollidableWallCount + 1
				end
			end
		end
	end
	ghostObservationRuntime:HolyOil({
		Hunting = ghost:GetAttribute("Hunting") == true,
		EligibleWallCount = eligibleWallCount,
		NonCollidableWallCount = nonCollidableWallCount,
	})
	return eligibleWallCount > 0
end

perkTrackerState.evaluateHolyOilColor = function(model, ghost)
	if not model
		or not model.Parent
		or not ghost
		or ghost:GetAttribute("Hunting") ~= true
		or model:GetAttribute("Burning") ~= true then
		return nil
	end

	local colorSequences = perkTrackerState.getHolyOilColorSequences(model)
	if colorSequences == nil then
		return nil
	end
	ghostObservationRuntime:HolyOil({
		Model = model,
		Hunting = ghost:GetAttribute("Hunting") == true,
		Burning = model:GetAttribute("Burning") == true,
		ColorSequences = colorSequences,
	})
	return true
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
		local ghost = getGhostModel()
		if model:GetAttribute("Burning") == true then
			if ghost
				and ghost:GetAttribute("Hunting") == true then
				perkTrackerState.evaluateHolyOilColor(model, ghost)
			end
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
				ghostObservationRuntime:HolyOil({
					Model = model,
					Hunting = true,
					Burning = false,
				})
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
perkTrackerState.pointInsideObservedRoom = function(roomName, position)
	if type(roomName) ~= "string" or roomName == "" then
		return false
	end
	local rooms = findRoomsFolder()
	local room = rooms and findFavouriteRoom(rooms, roomName)
	if not room or not position then
		return false
	end
	for _, part in ipairs(getRoomBoundingParts(room)) do
		if pointIsInsidePart(part, position) then
			return true
		end
	end
	return false
end
perkTrackerState.instanceInsideObservedRoom = function(instance, roomName)
	if type(roomName) ~= "string" or roomName == "" then
		return false
	end
	local rooms = findRoomsFolder()
	local room = rooms and findFavouriteRoom(rooms, roomName)
	return room ~= nil and instanceIsInsideRoom(instance, room) or false
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
	local now = os.clock()
	local automationActive = roomItemPlacementState.busy
		or now < (perkTrackerState.automationMutationUntil or 0)
	ghostObservationRuntime:ObjectTeleport({
		Kind = "SmokeObserved",
		Time = now,
		Position = descendant.Position,
		Object = descendant,
		Eligible = not automationActive,
		Source = "Workspace.DescendantAdded",
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
		ghostObservationRuntime:ObjectTeleport({
			Kind = "AutomationSuppressed",
			Time = now,
			Eligible = false,
		})
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
					local room = perkTrackerState.roomNameAtPosition(position)
					ghostObservationRuntime:ObjectTeleport({
						Kind = "MotionSample",
						Time = now,
						Object = object,
						ObjectName = object.Name,
						Elapsed = elapsed,
						Displacement = displacement,
						Speed = speed,
						FromPosition = previous.Position,
						ToPosition = position,
						FromRoom = previous.Room,
						ToRoom = room,
						Eligible = true,
						Source = parentName,
					})
					previous.Position = position
					previous.Time = now
					previous.Room = room
				end
			end
		end
	end
end
local function objectMotionRootPosition(rootObject)
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
local function collectObjectMotionFrame(ghost, now)
	local hunting = ghost and ghost:GetAttribute("Hunting") == true
	local suppressed = roomItemPlacementState.busy
		or now < (perkTrackerState.automationMutationUntil or 0)
	local frame = {
		Time = now,
		GhostId = ghost,
		Hunting = hunting,
		Suppressed = suppressed,
		Objects = {},
	}
	if not ghost or not hunting or suppressed then
		ghostObservationRuntime:Dispatch("OnObjectMotionFrame", frame)
		return
	end
	frame.GhostPosition = ghost:GetPivot().Position

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

	for _, folder in ipairs(folders) do
		for _, rootObject in ipairs(folder:GetChildren()) do
			local position, assembly = objectMotionRootPosition(rootObject)
			if position and assembly then
				table.insert(frame.Objects, {
					ObjectId = rootObject,
					AssemblyId = assembly,
					Position = position,
				})
			end
		end
	end
	ghostObservationRuntime:Dispatch("OnObjectMotionFrame", frame)
end

local function updateObservablePerkTrackers(deltaTime)
	local ghost = getGhostModel()
	local now = os.clock()
	local currentMap = workspace:FindFirstChild("Map")
	if not ghost and perkTrackerState.ghost then
		perkTrackerState.ghostMissingSince =
			perkTrackerState.ghostMissingSince or now
		if currentMap ~= nil
			and perkTrackerState.roundMap == currentMap then
			return false, now
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
		return false, now
	end

	-- Establish the current ghost/map generation before any observer receives a
	-- raw frame or Tick, so pending windows from a replaced model cannot resolve.
	collectObjectMotionFrame(ghost, now)
	perkTrackerState.sampleAccumulator = perkTrackerState.sampleAccumulator + deltaTime
	perkTrackerState.slowScanAccumulator = perkTrackerState.slowScanAccumulator + deltaTime
	perkTrackerState.analysisAccumulator = perkTrackerState.analysisAccumulator + deltaTime
	if perkTrackerState.sampleAccumulator < 0.1 then
		return true, now
	end
	perkTrackerState.sampleAccumulator =
		perkTrackerState.sampleAccumulator % 0.1
	dispatchRootSoundObservation(ghost)
	perkTrackerState.ensureCrossBurnTracker()
	perkTrackerState.updateCrossBurnTracker(now)
	local hunting = ghost:GetAttribute("Hunting") == true
	perkTrackerState.updateRoomLightObservations(ghost, hunting, 0.1, now)
	perkTrackerState.updateLidarStateObservation(ghost)
	perkTrackerState.updateSaltTracker(0.1, ghost, hunting, now)
	perkTrackerState.updateHolyOilTracker(0.1, ghost, now)
	perkTrackerState.updateObjectTeleportTracker(0.1, now)
	handleHuntTransition(ghost, hunting, now)
	feedGhostRoomPresence(ghost, hunting, now)
	capturePendingHuntTransitionSample(ghost, now)
	handleMultiplayerDeaths(ghost, hunting, now)
	if perkTrackerState.slowScanAccumulator >= 0.5 then
		perkTrackerState.slowScanAccumulator = 0
		for _ = 1, scanNewBrokenGlass() do
			ghostObservationRuntime:Glass({Time = now})
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
		return true, now
	end
	local elapsed = now - previousTime
	if elapsed <= 0 then
		return true, now
	end
	local displacement = (position - previousPosition).Magnitude
	local measuredSpeed = displacement / elapsed
	ghostObservationRuntime:GhostTeleport({
		Kind = "MotionSample",
		Time = now,
		Elapsed = elapsed,
		Displacement = displacement,
		Speed = measuredSpeed,
		FromPosition = previousPosition,
		ToPosition = position,
		FromRoom = previousObservedRoom,
		ToRoom = currentObservedRoom,
		CurrentRoom = currentObservedRoom,
		PreviousInside = perkTrackerState.pointInsideObservedRoom(
			previousObservedRoom,
			previousPosition
		),
		CurrentInside = perkTrackerState.instanceInsideObservedRoom(
			ghost,
			currentObservedRoom
		),
		Source = "Ghost.CurrentRoom",
	})
	if measuredSpeed > 45 then
		return true, now
	end
	local character = player.Character
	local localLineOfSight = hunting and ghostHasLineOfSightToCharacter(ghost, character) or false
	local lineOfSight, lineOfSightTarget = false, nil
	if hunting then
		lineOfSight, lineOfSightTarget =
			ghostHasLineOfSightToAnyAlivePlayer(ghost)
	end
	ghostObservationRuntime:Dispatch("OnLosExposure", {
		Hunting = hunting,
		LineOfSight = localLineOfSight,
		DeltaTime = elapsed,
	})
	local energy = getAverageTeamEnergy()
	local invisible = getGhostTransparencyState(ghost)
	local roomLit, roomName = getGhostRoomLightingState(ghost)
	local lightingKey = lightingContextKey(roomName, roomLit)
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
	if typeof(sample.GhostWalkSpeed) == "number"
		and sample.GhostWalkSpeed > 0 then
		ghostObservationRuntime:SpeedSample({
			Time = now,
			GhostWalkSpeed = sample.GhostWalkSpeed,
			Hunting = hunting,
			Invisible = invisible,
			MapFactor = getMapSizeSpeedFactor(),
		})
	end
	if perkTrackerState.analysisAccumulator >= 0.2 then
		perkTrackerState.analysisAccumulator = 0
		perkTrackerState.dispatchResidualEvidenceObservation(ghost)
	end
	return true, now
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
	ghostObservationRuntime:Dispatch("OnPlayerWalkSpeedAttempt", {
		Time = os.clock(),
		Hunting = true,
		LineOfSight = true,
		AttemptedSpeed = attemptedSpeed,
		ReferenceSpeed = baseWalkSpeed,
		LightingKey = lightingKey,
		Room = roomName,
		Lit = roomLit,
	})
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
automationHelpers.normalizedDoorToken = function(value)
	return string.lower(tostring(value or "")):gsub("[^%w]", "")
end
automationHelpers.isExitDoorMarker = function(instance)
	local token = instance
		and automationHelpers.normalizedDoorToken(instance.Name)
		or ""
	local suffix = string.sub(token, 9)
	return token == "exitdoor"
		or (string.sub(token, 1, 8) == "exitdoor"
			and (
				tonumber(suffix) ~= nil
				or suffix == "left"
				or suffix == "right"
				or suffix == "leftopen"
				or suffix == "rightopen"
				or suffix == "leftclosed"
				or suffix == "rightclosed"
				or suffix == "front"
				or suffix == "back"
				or suffix == "double"
				or suffix == "sliding"
				or suffix == "main"
				or suffix == "a"
				or suffix == "b"
				or suffix == "open"
				or suffix == "closed"
			))
end
automationHelpers.instanceBelongsToExitDoor = function(instance)
	local doors = workspace:FindFirstChild("Doors")
	local current = instance
	while current and current ~= doors and current ~= workspace do
		if automationHelpers.isExitDoorMarker(current) then
			return true
		end
		current = current.Parent
	end
	if instance then
		for _, descendant in ipairs(instance:GetDescendants()) do
			if automationHelpers.isExitDoorMarker(descendant) then
				return true
			end
		end
	end
	return false
end
automationHelpers.findExitDoorDescriptors = function(): any
	local doors: any = workspace:FindFirstChild("Doors")
	local descriptors: any = {}
	if not doors then
		return descriptors
	end
	local markers: any = {}
	for _, descendant in ipairs(doors:GetDescendants()) do
		if automationHelpers.isExitDoorMarker(descendant) then
			local ancestor = descendant.Parent
			local nestedMarker = false
			while ancestor and ancestor ~= doors do
				if automationHelpers.isExitDoorMarker(ancestor) then
					nestedMarker = true
					break
				end
				ancestor = ancestor.Parent
			end
			if not nestedMarker then
				table.insert(markers, descendant)
			end
		end
	end
	local seenContainers: any = setmetatable({}, {__mode = "k"})
	local function stateOwnerFor(container: any, marker: any): any
		local current: any = container
		while current and current ~= doors.Parent do
			if current:GetAttribute("DoorClosed") ~= nil then
				return current
			end
			if current == doors then
				break
			end
			current = current.Parent
		end
		if marker:GetAttribute("DoorClosed") ~= nil then
			return marker
		end
		return container
	end
	local function addDescriptor(marker: any, container: any)
		if not container or seenContainers[container] then
			return
		end
		seenContainers[container] = true
		local physicalReference: any = container:IsA("BasePart")
			and container
			or container:FindFirstChild("DoorUnion", true)
			or container:FindFirstChildWhichIsA("BasePart", true)
		local position: any = physicalReference
			and physicalReference:IsA("BasePart")
			and physicalReference.Position
			or nil
		if not position and container:IsA("Model") then
			local ok, frame: any = pcall(container.GetBoundingBox, container)
			if ok then
				position = frame.Position
			end
		end
		table.insert(descriptors, {
			Entry = marker,
			DoorContainer = container,
			StateOwner = stateOwnerFor(container, marker),
			Position = position or getInstanceWorldPosition(container)
				or getInstanceWorldPosition(marker),
		})
	end
	for _, marker in ipairs(markers) do
		local markerFoundDoor = false
		for _, descendant in ipairs(marker:GetDescendants()) do
			if automationHelpers.normalizedDoorToken(descendant.Name) == "door"
				and (descendant:IsA("Model")
					or descendant:IsA("Folder")
					or descendant:IsA("BasePart")) then
				local nestedBelowDoor = false
				local ancestor = descendant.Parent
				while ancestor and ancestor ~= marker do
					if automationHelpers.normalizedDoorToken(ancestor.Name) == "door" then
						nestedBelowDoor = true
						break
					end
					ancestor = ancestor.Parent
				end
				if not nestedBelowDoor then
					markerFoundDoor = true
					addDescriptor(marker, descendant)
				end
			end
		end
		if not markerFoundDoor
			and (marker:IsA("Model")
				or marker:IsA("Folder")
				or marker:IsA("BasePart"))
			and marker:FindFirstChildWhichIsA("BasePart", true) then
			addDescriptor(marker, marker)
		end
	end
	table.sort(descriptors, function(first, second)
		local firstName = first.Entry:GetFullName()
		local secondName = second.Entry:GetFullName()
		if firstName == secondName then
			return first.DoorContainer:GetFullName()
				< second.DoorContainer:GetFullName()
		end
		return firstName < secondName
	end)
	return descriptors
end
local function teleportToRoomBoundingBoxCenter(room: any, options: any): (boolean, any)
	options = options or {}
	local function teleportIsActive(): boolean
		if type(options.IsActive) ~= "function" then
			return true
		end
		local ok, active = pcall(options.IsActive)
		return ok and active == true
	end
	local character: any = player.Character
	local root: any =
		character and character:FindFirstChild("HumanoidRootPart")
	local humanoid: any =
		character and character:FindFirstChildOfClass("Humanoid")

	if not room or not character or not root or not humanoid
		or not teleportIsActive() then
		return false, "room or character unavailable"
	end

	local boundingParts: any = options.BoundingParts or getRoomBoundingParts(room)
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

	local boundingPartSet: any = setmetatable({}, {__mode = "k"})
	local excludedInstances: any = {character}

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

	local standingOffset: number =
		humanoid.HipHeight + root.Size.Y * 0.5 + 0.12
	local footprintHalfX: number = root.Size.X * 0.5
	local footprintHalfZ: number = root.Size.Z * 0.5
	for _, bodyPart in ipairs(character:GetDescendants()) do
		if bodyPart:IsA("BasePart")
			and not automationHelpers.partBelongsToHeldCharacterItem(
				bodyPart,
				character
			) then
			local half: any = bodyPart.Size * 0.5
			local relative: any = root.CFrame:ToObjectSpace(bodyPart.CFrame)
			local projectedHalfX: number =
				math.abs(relative.XVector.X) * half.X
				+ math.abs(relative.YVector.X) * half.Y
				+ math.abs(relative.ZVector.X) * half.Z
			local projectedHalfZ: number =
				math.abs(relative.XVector.Z) * half.X
				+ math.abs(relative.YVector.Z) * half.Y
				+ math.abs(relative.ZVector.Z) * half.Z
			footprintHalfX = math.max(
				footprintHalfX,
				math.abs(relative.Position.X) + projectedHalfX
			)
			footprintHalfZ = math.max(
				footprintHalfZ,
				math.abs(relative.Position.Z) + projectedHalfZ
			)
		end
	end
	footprintHalfX = footprintHalfX + 0.22
	footprintHalfZ = footprintHalfZ + 0.22
	local avatarRadius =
		math.max(footprintHalfX, footprintHalfZ) + 0.18
	local horizontalInset =
		math.sqrt(footprintHalfX ^ 2 + footprintHalfZ ^ 2) + 0.18
	local bodyHeight = math.max(
		root.Size.Y + humanoid.HipHeight + 2.35,
		5.1
	)
	local bodyProbeSize = Vector3.new(
		math.max(footprintHalfX * 2 + 0.28, 2.3),
		bodyHeight,
		math.max(footprintHalfZ * 2 + 0.28, 2.3)
	)
	local bodyGeometryProbe = nil
	local preferredPositions = options.PreferredPositions or {}
	local targetPosition = options.TargetPosition
	local maximumTargetDistance = tonumber(options.MaximumTargetDistance)
	local maximumPreferredDistance = tonumber(options.MaximumPreferredDistance)
	local candidateValidator = options.CandidateValidator
	local function candidatePassesCustomValidation(position: any): boolean
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

	local function safelyInsideXZ(position: any, boundingPart: any): boolean
		local localPosition =
			boundingPart.CFrame:PointToObjectSpace(position)
		local half = boundingPart.Size * 0.5

		return math.abs(localPosition.X)
			<= math.max(0, half.X - horizontalInset)
			and math.abs(localPosition.Z)
				<= math.max(0, half.Z - horizontalInset)
	end

	local function isCollidableInstance(instance: any): boolean
		if instance == workspace.Terrain then
			return true
		end
		return instance
			and instance:IsA("BasePart")
			and instance.CanCollide
	end

	local function newRaycastParams(excludes: any): any
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
		origin: any,
		direction: any,
		additionalExcludes: any
	): any
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

	local function inspectFootprint(floorPosition: any): any
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

	local function worldHalfExtents(part: any): any
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

	local function inspectBodyArea(candidate: any, floorY: number, supportSet: any): any
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

	local function horizontalClearance(candidate: any, floorY: number, supportSet: any): number
		local supportExcludes = {}
		for instance in pairs(supportSet) do
			if instance ~= workspace.Terrain then
				table.insert(supportExcludes, instance)
			end
		end

		local minimum: number = 9
		for _, height in ipairs({0.75, 2.65}) do
			local origin = Vector3.new(
				candidate.X,
				floorY + height,
				candidate.Z
			)
			for _, direction in ipairs(clearanceDirections) do
				local result: any = raycastFirstCollidable(
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
		bodyInspection: any,
		footprintInspection: any,
		clearance: number
	): number
		return bodyInspection.Penalty
			+ bodyInspection.CoreBlockers * 10000
			+ bodyInspection.BlockerCount * 500
			+ (#footprintOffsets
				- footprintInspection.FlatSupportHits) * 180
			+ (#footprintOffsets
				- footprintInspection.SupportHits) * 70
			+ math.max(0, 2.1 - clearance) * 120
	end

	local function assessCandidate(candidate: any): boolean
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

		local footprintInspection: any = inspectFootprint(
			candidate.FloorPosition
		)
		if not footprintInspection.CenterSupported then
			return false
		end

		local bodyInspection: any = inspectBodyArea(
			candidate.Position,
			candidate.FloorPosition.Y,
			footprintInspection.SupportSet
		)
		local clearance: number = horizontalClearance(
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
		boundingPart: any,
		localX: number,
		localZ: number,
		rippleOrder: any
	): ()
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
			local function queueSample(localX: number, localZ: number): any
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
	local function destroyBodyGeometryProbe(): ()
		if bodyGeometryProbe then
			bodyGeometryProbe:Destroy()
			bodyGeometryProbe = nil
		end
	end

	local function surfaceLooksLikeGround(surface: any): boolean
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
	local function evaluateCandidate(candidate: any): ()
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
	local function evaluatePool(pool: any): boolean
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
	local disabledStates: any = {}
	local disabledHumanoidStates: any = {
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Freefall,
	}

	for _, state: any in ipairs(disabledHumanoidStates) do
		local ok: boolean, enabled: any = pcall(function(): any
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
	local function tryCandidate(candidate: any, requireStrict: boolean): boolean
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
		local expectedRisk: number = candidate.Risk
		local expectedSupportHits: number = candidate.SupportHits
		local destinationLook = look
		if fixedLook and fixedLook.Magnitude >= 0.05 then
			destinationLook = fixedLook.Unit
		elseif options.FaceBoundingBoxCenter then
			local targeted = Vector3.new(
				candidate.BoundingPart.Position.X - candidate.Position.X,
				0,
				candidate.BoundingPart.Position.Z - candidate.Position.Z
			)
			if targeted.Magnitude >= 0.05 then
				destinationLook = targeted.Unit
			end
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
		if not automationHelpers.instanceFullyInsideBoundingPartsXZ(
			character,
			boundingParts,
			true
		) then
			return false
		end
		local footprintInspection: any = inspectFootprint(
			settledFloorPosition
		)
		if not footprintInspection.CenterSupported
			or not safelyInsideXZ(
				root.Position,
				candidate.BoundingPart
			) then
			return false
		end

		local bodyInspection: any = inspectBodyArea(
			root.Position,
			settledFloorPosition.Y,
			footprintInspection.SupportSet
		)
		local clearance: number = horizontalClearance(
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

		local settledRisk: number = calculateRisk(
			bodyInspection,
			footprintInspection,
			clearance
		)
		return bodyInspection.CoreBlockers == 0
			and footprintInspection.SupportHits
			>= math.max(1, expectedSupportHits - 1)
			and settledRisk <= expectedRisk + 750
	end

	local selected: any = nil
	local strictModes: any = options.RequireStrict and {true} or {true, false}
	for _, requireStrict: boolean in ipairs(strictModes) do
		for groundTier = 0, 3 do
			for _, candidate: any in ipairs(candidates) do
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
		if root.Parent then
			root.Anchored = originalAnchored
		end
		if humanoid.Parent then
			humanoid.PlatformStand = originalPlatformStand
			humanoid.AutoRotate = originalAutoRotate
			for state, enabled in pairs(disabledStates) do
				pcall(function()
					humanoid:SetStateEnabled(state, enabled)
				end)
			end
		end
		destroyBodyGeometryProbe()
		return false,
			"no grounded destination remained stable during teleport"
	end
	if not teleportIsActive() then
		if root.Parent and character.Parent then
			pcall(function()
				character:PivotTo(originalPivot)
			end)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = originalAnchored
		end
		if humanoid.Parent then
			humanoid.PlatformStand = originalPlatformStand
			humanoid.AutoRotate = originalAutoRotate
			for state, enabled in pairs(disabledStates) do
				pcall(function()
					humanoid:SetStateEnabled(state, enabled)
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
	if not automationHelpers.instanceFullyInsideBoundingPartsXZ(
		character,
		boundingParts,
		true
	) then
		if root.Parent and character.Parent then
			root.Anchored = true
			pcall(function()
				character:PivotTo(originalPivot)
			end)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = originalAnchored
		end
		if humanoid.Parent then
			humanoid.PlatformStand = originalPlatformStand
			humanoid.AutoRotate = originalAutoRotate
			for state, enabled in pairs(disabledStates) do
				pcall(function()
					humanoid:SetStateEnabled(state, enabled)
				end)
			end
		end
		destroyBodyGeometryProbe()
		return false, "full character drifted outside the room bounds"
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

local function teleportToBaseCamp(options: any): any
	local room: any = findBaseCampRoom()
	local map: any = workspace:FindFirstChild("Map")
	local truck: any = room and room:FindFirstChild("Truck", true)
	-- The room-bounds object and the physical Base Camp hierarchy are not
	-- necessarily the same instance. Search every explicitly named Base Camp
	-- container so an existing room can never mask the Truck fallback.
	if not truck and map then
		for _, candidate: any in ipairs(map:GetDescendants()) do
			local candidateName = automationHelpers.normalizedDoorToken(candidate.Name)
			if candidateName == "basecamp" then
				truck = candidate:FindFirstChild("Truck", true)
				if truck then
					break
				end
			end
		end
	end
	if not room and not truck then
		return false, "Base Camp room and Truck were not found"
	end
	local boundingParts: any = table.clone(getRoomBoundingParts(room))
	local exitPositions: any = {}
	for _, descriptor: any in ipairs(automationHelpers.findExitDoorDescriptors()) do
		if descriptor.Position then
			table.insert(exitPositions, descriptor.Position)
		end
	end
	local truckPosition: any = getInstanceWorldPosition(truck)
	local function distanceToReferences(part: any): number
		local references: any = #exitPositions > 0
			and exitPositions
			or (truckPosition and {truckPosition} or {})
		local best: number = math.huge
		for _, reference: any in ipairs(references) do
			local offset: any = part.Position - reference
			best = math.min(
				best,
				Vector2.new(offset.X, offset.Z).Magnitude
			)
		end
		return best
	end
	table.sort(boundingParts, function(first: any, second: any)
		local firstDistance = distanceToReferences(first)
		local secondDistance = distanceToReferences(second)
		if firstDistance == secondDistance then
			return first:GetFullName() < second:GetFullName()
		end
		return firstDistance < secondDistance
	end)
	local lastReason
	for _, boundingPart in ipairs(boundingParts) do
		local attemptOptions = table.clone(options or {})
		attemptOptions.TargetPosition = nil
		attemptOptions.MaximumTargetDistance = nil
		attemptOptions.MaximumPreferredDistance = nil
		attemptOptions.CandidateValidator = nil
		attemptOptions.LookAtPosition = nil
		attemptOptions.LookDirection = nil
		attemptOptions.PreferredPositions = nil
		attemptOptions.BoundingParts = {boundingPart}
		attemptOptions.FaceBoundingBoxCenter = true
		local teleported, reason = teleportToRoomBoundingBoxCenter(
			room,
			attemptOptions
		)
		if teleported then
			return true
		end
		lastReason = reason
	end
	if truck then
		local truckFrame
		local truckSize
		if truck:IsA("BasePart") then
			truckFrame = truck.CFrame
			truckSize = truck.Size
		elseif truck:IsA("Model") then
			local ok, frame, size = pcall(truck.GetBoundingBox, truck)
			if ok then
				truckFrame = frame
				truckSize = size
			end
		end
		if truckFrame and truckSize then
			local syntheticBounds = Instance.new("Part")
			syntheticBounds.Name = "__DemonologyBaseCampTruckBounds"
			syntheticBounds.Anchored = true
			syntheticBounds.CanCollide = false
			syntheticBounds.Transparency = 1
			syntheticBounds.CFrame = truckFrame
			syntheticBounds.Size = Vector3.new(
				math.max(truckSize.X + 14, 18),
				math.max(truckSize.Y + 10, 12),
				math.max(truckSize.Z + 14, 18)
			)
			local halfX = truckSize.X * 0.5 + 4
			local halfZ = truckSize.Z * 0.5 + 4
			local attemptOptions = table.clone(options or {})
			attemptOptions.TargetPosition = nil
			attemptOptions.MaximumTargetDistance = nil
			attemptOptions.MaximumPreferredDistance = nil
			attemptOptions.CandidateValidator = nil
			attemptOptions.LookAtPosition = nil
			attemptOptions.LookDirection = nil
			attemptOptions.BoundingParts = {syntheticBounds}
			attemptOptions.PreferredPositions = {
				truckFrame.Position + truckFrame.RightVector * halfX,
				truckFrame.Position - truckFrame.RightVector * halfX,
				truckFrame.Position + truckFrame.LookVector * halfZ,
				truckFrame.Position - truckFrame.LookVector * halfZ,
			}
			attemptOptions.FaceBoundingBoxCenter = true
			local teleported, reason = teleportToRoomBoundingBoxCenter(
				room or truck,
				attemptOptions
			)
			syntheticBounds:Destroy()
			if teleported then
				return true
			end
			lastReason = reason
		end
	end
	return false, lastReason or "no safe Base Camp or Truck destination was found"
end
local function teleportToFavouriteRoom(options)
	local ghost = getGhostModel()
	local roomsFolder = findRoomsFolder()
	local roomName = ghost and ghost:GetAttribute("FavoriteRoom") or nil
	local room = findFavouriteRoom(roomsFolder, roomName)
	if not room then
		return false, "Favourite room was not found: " .. tostring(roomName)
	end
	local attemptOptions = table.clone(options or {})
	attemptOptions.FaceBoundingBoxCenter = true
	return teleportToRoomBoundingBoxCenter(room, attemptOptions)
end
local placeItemsInFavouriteRoom: any = function(owner: any, requestedRoom: any)
	if roomItemPlacementState.busy or closed then
		return false, "room item setup is already running"
	end
	local placementTargetRoom = requestedRoom
	if not placementTargetRoom then
		local targetGhost = getGhostModel()
		placementTargetRoom = findFavouriteRoom(
			findRoomsFolder(),
			targetGhost and targetGhost:GetAttribute("FavoriteRoom") or nil
		)
	end
	if not placementTargetRoom or not placementTargetRoom.Parent then
		return false, "favourite room was not available for item setup"
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
	roomItemPlacementState.thread = task.spawn(function(): ()
		local failedItems: any = {}
		local failureSet: any = {}
		local function recordFailure(message: any): ()
			if not failureSet[message] then
				failureSet[message] = true
				table.insert(failedItems, message)
			end
		end
		local function operationIsActive(): boolean
			return not closed
				and roomItemPlacementState.busy
				and roomItemPlacementState.generation
					== operationGeneration
		end
		local function assertOperationActive(): ()
			if not operationIsActive() then
				error("Room item setup cancelled", 0)
			end
		end
		local function guardedWait(seconds: number): ()
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
		local function currentFavouriteRoom(): any
			return placementTargetRoom.Parent and placementTargetRoom or nil
		end
		local function waitForNoHunt(returnToFavouriteRoom: any): boolean
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
				local currentFavourite = currentFavouriteRoom()
				local character = player.Character
				local alreadyInRoom = currentFavourite
					and character
					and automationHelpers.characterIsFullyInsideRoom(
						character,
						currentFavourite
					)
				if not alreadyInRoom then
					local teleported, reason =
						teleportToRoomBoundingBoxCenter(
							currentFavourite,
							{FaceBoundingBoxCenter = true}
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
		local function getRemote(name: any): any
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
		local PICKUP_MAX_DISTANCE = 8
		local function fireRemote(remote: any, ...: any): ()
			assertOperationActive()
			local ok, err = pcall(remote.FireServer, remote, ...)
			if not ok then
				error("Remote call failed: " .. tostring(err), 0)
			end
			guardedWait(0.1)
		end
		local playerGui = player:FindFirstChild("PlayerGui")
		local hotbar =
			playerGui and playerGui:FindFirstChild("Hotbar")
		local hotbarSlots =
			hotbar and hotbar:FindFirstChild("Slots")
		local function normalizeItemName(value: any): string
			local normalized: string = string.lower(tostring(value or ""))
			normalized = string.match(normalized, "^%s*(.-)%s*$") or normalized
			normalized = string.gsub(normalized, "%s+", " ")
			if normalized == "holyoil"
				or normalized == "hoil oil" then
				return "holy oil"
			end
			return normalized
		end
		local function sameItemName(left: any, right: any): boolean
			return normalizeItemName(left)
				== normalizeItemName(right)
		end
		local inventorySlotCount = 3
		local function inventorySlotKey(slotNumber: any): string
			return "InvSlot" .. tostring(slotNumber)
		end
		local function inventorySlotValue(slotNumber: any): any
			return player:GetAttribute(
				inventorySlotKey(slotNumber)
			)
		end
		local function valueIsOccupied(value: any): boolean
			return value ~= nil
				and value ~= false
				and tostring(value) ~= ""
		end
		local function directStoredInventoryModels(
			itemName: any,
			includeBurntCross: any
		): any
			local matches = {}
			local requested = itemName and normalizeItemName(itemName) or nil
			for _, container in ipairs({
				player:FindFirstChild("ToolsHolder"),
				player.Character,
			}) do
				if container then
					for _, child in ipairs(container:GetChildren()) do
						local name = child:IsA("Model")
							and child:GetAttribute("ItemName")
							or nil
						if typeof(name) == "string"
							and name ~= ""
							and (not requested
								or normalizeItemName(name) == requested)
							and (includeBurntCross == true
								or not automationHelpers.worldItemIsBurntCross(child)) then
							table.insert(matches, child)
						end
					end
				end
			end
			return matches
		end
		local function scanStoredInventory(itemName: any): (any, number, number)
			local matching = itemName
				and directStoredInventoryModels(itemName, false)
				or {}
			local allStored = directStoredInventoryModels(nil, true)
			return matching[1], #matching, math.min(
				#allStored,
				inventorySlotCount
			)
		end
		local function objectMatchesSlotValue(object: any, slotValue: any): boolean
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
		local function storedObjectSlot(storedItem: any): any
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
			local current: any = storedItem
			while current
				and current ~= player
				and current ~= workspace do
				local inventoryAttributeNames: any = {
					"InvSlot",
					"InventorySlot",
					"Slot",
					"SlotNumber",
				}
				for _, attributeName: any in ipairs(inventoryAttributeNames) do
					local value: any =
						current:GetAttribute(attributeName)
					local number: any = tonumber(
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
		local function slotLabel(slot: any): any
			local label = slot and slot:FindFirstChild("ItemName")
			return label
				and label:IsA("TextLabel")
				and label.Text
				or nil
		end
		local function hotbarSlotName(slotNumber: any): any
			if not hotbarSlots then
				return nil
			end
			return slotLabel(
				hotbarSlots:FindFirstChild(
					"InvSlot" .. tostring(slotNumber)
				)
			)
		end
		local function findHotbarSlot(itemName: any): any
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
		local function inventorySlotCandidates(
			itemName: any,
			includeBurntCross: any
		): any
			local models = directStoredInventoryModels(
				itemName,
				includeBurntCross == true
			)
			if #models == 0 then
				return {}
			end
			local candidates = {}
			local added = {}
			local function add(slotNumber: any): ()
				if slotNumber
					and slotNumber >= 1
					and slotNumber <= inventorySlotCount
					and not added[slotNumber] then
					added[slotNumber] = true
					table.insert(candidates, slotNumber)
				end
			end
			for _, model in ipairs(models) do
				add(storedObjectSlot(model))
			end
			add(findHotbarSlot(itemName))
			-- If the server exposes only an opaque InvSlot token, every occupied
			-- slot is a candidate. Equip callers confirm the requested direct
			-- Character model before acting, then fall back across all three slots.
			for slotNumber = 1, inventorySlotCount do
				if valueIsOccupied(inventorySlotValue(slotNumber)) then
					add(slotNumber)
				end
			end
			for slotNumber = 1, inventorySlotCount do
				add(slotNumber)
			end
			return candidates
		end
		local function findInventorySlot(itemName: any): any
			return inventorySlotCandidates(itemName, false)[1]
		end
		local function countInventoryItem(itemName: any): number
			local _, storedCount: number =
				scanStoredInventory(itemName)
			return storedCount
		end
		local function countPhysicalInventoryItem(
			itemName: any,
			includeBurntCross: any
		): number
			return #directStoredInventoryModels(itemName, includeBurntCross)
		end
		local function inventoryHasItem(itemName: any): boolean
			return countInventoryItem(itemName) > 0
		end
		local function inventorySlotName(slotNumber: any): any
			for _, child in ipairs(directStoredInventoryModels(nil, true)) do
				if storedObjectSlot(child) == slotNumber then
					return child:GetAttribute("ItemName")
				end
			end
			local hotbarName = hotbarSlotName(slotNumber)
			if hotbarName and hotbarName ~= "" then
				return hotbarName
			end
			return nil
		end
		local function inventorySnapshot(): (any, number, any, any)
			local slots = {}
			local occupiedSlots = {}
			local directClaimedSlots = {}
			local occupiedCount = 0
			local freeSlot
			local values = {}
			local directModels = directStoredInventoryModels(nil, true)
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
					occupiedSlots[slotNumber] = true
					slots[slotNumber] =
						inventorySlotName(slotNumber)
				elseif not freeSlot then
					freeSlot = slotNumber
				end
			end
			local unmappedDirectModels = {}
			for _, storedItem in ipairs(directModels) do
				local slotNumber = storedObjectSlot(storedItem)
				if slotNumber then
					occupiedSlots[slotNumber] = true
					directClaimedSlots[slotNumber] = true
					if not slots[slotNumber] then
						slots[slotNumber] = storedItem:GetAttribute("ItemName")
					end
				else
					table.insert(unmappedDirectModels, storedItem)
				end
			end
			-- Direct Character/ToolsHolder models are authoritative. Reconcile an
			-- opaque model only with a matching hotbar label. Otherwise claim a
			-- blank slot conservatively instead of merging two different items or
			-- counting the same labeled tool twice.
			for _, storedItem in ipairs(unmappedDirectModels) do
				local itemName = storedItem:GetAttribute("ItemName")
				local reconciledSlot
				for slotNumber = 1, inventorySlotCount do
					if occupiedSlots[slotNumber]
						and not directClaimedSlots[slotNumber]
						and sameItemName(hotbarSlotName(slotNumber), itemName) then
						reconciledSlot = slotNumber
						break
					end
				end
				if not reconciledSlot then
					for slotNumber = 1, inventorySlotCount do
						if not occupiedSlots[slotNumber] then
							reconciledSlot = slotNumber
							occupiedSlots[slotNumber] = true
							break
						end
					end
				end
				if reconciledSlot then
					directClaimedSlots[reconciledSlot] = true
					slots[reconciledSlot] = slots[reconciledSlot] or itemName
				end
			end
			for slotNumber = 1, inventorySlotCount do
				if occupiedSlots[slotNumber] then
					occupiedCount = occupiedCount + 1
				end
			end
			freeSlot = nil
			if occupiedCount < inventorySlotCount then
				for slotNumber = 1, inventorySlotCount do
					if not occupiedSlots[slotNumber]
						and not valueIsOccupied(values[slotNumber])
						and not hotbarSlotName(slotNumber) then
						freeSlot = slotNumber
						break
					end
				end
			end
			return slots, occupiedCount, freeSlot, values
		end
		local function waitForHotbarSlot(itemName: any, timeout: any): any
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
		local function findItem(itemName: any): (boolean, any)
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
					and not automationHelpers.worldItemIsBurntCross(child) then
					return true, child
				end
			end
			return false, nil
		end
		local function moveNearWorldItem(model: any): boolean
			local character = player.Character
			local root = character
				and character:FindFirstChild("HumanoidRootPart")
			if not model
				or not model.Parent
				or not character
				or not root then
				return false
			end
			if automationHelpers.distanceFromPositionToInstance(root.Position, model)
				<= PICKUP_MAX_DISTANCE then
				return true
			end
			local itemPosition = getInstanceWorldPosition(model)
			local room = findRoomContainingInstance(model)
				or findBaseCampRoom()
			if not itemPosition or not room then
				return false
			end
			local preferredPositions = {
				itemPosition + Vector3.new(4.5, 0, 0),
				itemPosition + Vector3.new(-4.5, 0, 0),
				itemPosition + Vector3.new(0, 0, 4.5),
				itemPosition + Vector3.new(0, 0, -4.5),
			}
			local teleported = teleportToRoomBoundingBoxCenter(room, {
				PreferredPositions = preferredPositions,
				TargetPosition = itemPosition,
				MaximumTargetDistance = 7.75,
				LookAtPosition = itemPosition,
				RequireStrict = true,
				IsActive = operationIsActive,
			})
			return teleported
				and root.Parent ~= nil
				and automationHelpers.distanceFromPositionToInstance(root.Position, model)
					<= PICKUP_MAX_DISTANCE
		end
		local function equipItem(
			slotNumber: any,
			returnToFavouriteRoom: any,
			allowUnknownSlot: any
		): boolean
			waitForNoHunt(returnToFavouriteRoom == true)
			if not slotNumber
				or slotNumber < 1
				or slotNumber > inventorySlotCount
				or (not allowUnknownSlot
					and (
						not valueIsOccupied(
							inventorySlotValue(slotNumber)
						)
						and not inventorySlotName(slotNumber)
					)) then
				return false
			end
			fireRemote(
				requestItemEquip,
				inventorySlotKey(slotNumber)
			)
			guardedWait(0.18)
			return true
		end
		local function equipNamedItem(
			itemName: any,
			returnToFavouriteRoom: any,
			includeBurntCross: any
		): (boolean, any, any)
			local function equippedModel(): any
				local character = player.Character
				if not character then
					return nil
				end
				for _, model in ipairs(directStoredInventoryModels(
					itemName,
					includeBurntCross == true
				)) do
					if model:IsDescendantOf(character) then
						return model
					end
				end
				return nil
			end
			local alreadyEquipped = equippedModel()
			if alreadyEquipped then
				local exactSlot = storedObjectSlot(alreadyEquipped)
				if exactSlot then
					return true, exactSlot, alreadyEquipped
				end
			end
			local candidates = inventorySlotCandidates(
				itemName,
				includeBurntCross == true
			)
			if alreadyEquipped then
				-- A no-op request for a blank slot can leave the opaque target in
				-- Character, so pre-existing presence is not confirmation. Switch to
				-- another real slot first and only then probe for the target's return.
				local switchedAway = false
				for _, candidate in ipairs(candidates) do
					if equipItem(candidate, returnToFavouriteRoom, true) then
						local switchDeadline = os.clock() + 0.25
						repeat
							local current = equippedModel()
							if not current then
								switchedAway = true
								break
							end
							local resolvedSlot = storedObjectSlot(current)
							if resolvedSlot then
								return true, resolvedSlot, current
							end
							guardedWait(0.05)
						until os.clock() >= switchDeadline
					end
					if switchedAway then
						break
					end
				end
				if not switchedAway and not equippedModel() then
					switchedAway = true
				end
				if not switchedAway then
					-- The item may still be toggled/used while equipped, but callers that
					-- need to drop it must reject the deliberately unconfirmed slot.
					return true, nil, alreadyEquipped
				end
			end
			for _, candidate in ipairs(candidates) do
				if equipItem(candidate, returnToFavouriteRoom, true) then
					local confirmationDeadline = os.clock() + 0.4
					repeat
						local confirmed = equippedModel()
						if confirmed then
							return true, candidate, confirmed
						end
						guardedWait(0.05)
					until os.clock() >= confirmationDeadline
					local confirmed = equippedModel()
					if confirmed then
						return true, candidate, confirmed
					end
				end
			end
			return false, nil, nil
		end
		local function findDroppedWorldItemInRoom(
			itemName: any,
			room: any
		): any
			if not room then
				return nil
			end
			local items: any = workspace:FindFirstChild("Items")
			if not items then
				return nil
			end
			for _, worldItem: any in ipairs(items:GetChildren()) do
				local worldItemName: any = worldItem:IsA("Model")
					and worldItem:GetAttribute("ItemName")
					or nil
				if typeof(worldItemName) == "string"
					and worldItemName ~= ""
					and sameItemName(worldItemName, itemName)
					and not automationHelpers.worldItemIsBurntCross(worldItem)
					and automationHelpers.worldItemIsInsideRoomBounds(
						worldItem,
						room
					) then
					return worldItem
				end
			end
			return nil
		end
		local function confirmedDrop(
			slotNumber: any,
			itemName: any,
			returnToFavouriteRoom: any
		): boolean
			local requireRoomReturn = returnToFavouriteRoom == true
			local includeBurntCross = not requireRoomReturn
			local beforeCount = countPhysicalInventoryItem(
				itemName,
				includeBurntCross
			)
			if beforeCount == 0 then
				return true
			end
			local dropCandidates = inventorySlotCandidates(
				itemName,
				includeBurntCross
			)
			for attempt = 1, inventorySlotCount do
				local slotCandidates = dropCandidates
				local currentSlot = slotCandidates[attempt] or slotNumber
				if not currentSlot then
					return false
				end
				slotNumber = currentSlot
				local equipped, confirmedSlot = equipNamedItem(
					itemName,
					returnToFavouriteRoom,
					includeBurntCross
				)
				local _, remainingOccupiedCount = inventorySnapshot()
				if not equipped
					or (not confirmedSlot
						and (#directStoredInventoryModels(nil, true) ~= 1
							or remainingOccupiedCount ~= 1)) then
					guardedWait(0.15)
					continue
				end
				slotNumber = confirmedSlot or currentSlot
				local dropRoom: any
				if requireRoomReturn then
					waitForNoHunt(false)
					dropRoom = currentFavouriteRoom()
					local movedToOpenPosition = dropRoom
						and teleportToRoomBoundingBoxCenter(dropRoom, {
							FaceBoundingBoxCenter = true,
							RequireStrict = true,
							IsActive = operationIsActive,
						})
					if not movedToOpenPosition then
						return false
					end
					guardedWait(0.12)
					local currentGhost = getGhostModel()
					if currentGhost
						and currentGhost:GetAttribute("Hunting") == true then
						waitForNoHunt(false)
						continue
					end
					local character: any = player.Character
					if not dropRoom or not character then
						return false
					end
					local characterInsideRoom: boolean =
						automationHelpers.characterIsFullyInsideRoom(character, dropRoom)
					if not characterInsideRoom then
						return false
					end
				end
				fireRemote(
					requestItemDrop,
					inventorySlotKey(slotNumber)
				)
				local deadline = os.clock() + 1.65
				repeat
					assertOperationActive()
					if requireRoomReturn
						and findDroppedWorldItemInRoom(itemName, dropRoom) then
						return true
					end
					if not requireRoomReturn
						and countPhysicalInventoryItem(
							itemName,
							includeBurntCross
						) < beforeCount then
						return true
					end
					guardedWait(0.05)
				until os.clock() >= deadline
				if requireRoomReturn then
					return findDroppedWorldItemInRoom(itemName, dropRoom) ~= nil
				end
				local _, afterOccupiedCount = inventorySnapshot()
				if countPhysicalInventoryItem(
						itemName,
						includeBurntCross
					) < beforeCount then
					return not requireRoomReturn
				end
				if afterOccupiedCount < inventorySlotCount
					and countPhysicalInventoryItem(
						itemName,
						includeBurntCross
					) == 0 then
					return not requireRoomReturn
				end
				guardedWait(0.2)
			end
			return not requireRoomReturn
				and countPhysicalInventoryItem(
					itemName,
					includeBurntCross
				) < beforeCount
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
		local finalOrder: any = {
			{Name = "Salt Canister", Optional = true},
			{Name = "Holy Oil", Optional = true},
		}
		local function slotItemIsProtected(
			slotNumber: any,
			slotName: any,
			protectedNames: any
		): boolean
			if not protectedNames[normalizeItemName(slotName)] then
				return false
			end
			if sameItemName(slotName, "Cross") then
				-- A burning/burnt Cross occupies inventory but must never be
				-- protected for relocation into a new favourite room.
				return findInventorySlot("Cross") == slotNumber
			end
			return true
		end

		local function ensureInventorySpace(
			protectedNames: any,
			returnToFavouriteRoom: any
		): boolean
			local _, occupiedCount = inventorySnapshot()
			if occupiedCount < inventorySlotCount then
				return true
			end

			for slotNumber = 1, inventorySlotCount do
				local slotName = inventorySlotName(slotNumber)
				if slotName
					and slotName ~= ""
					and not slotItemIsProtected(
						slotNumber,
						slotName,
						protectedNames
					) then
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
			itemName: any,
			model: any,
			beforeItemCount: number,
			beforeOccupiedCount: number,
			beforeSlotValues: any,
			timeout: number
		): any
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
			itemName: any,
			model: any,
			timeout: any
		): any
			local root = player.Character
				and player.Character:FindFirstChild("HumanoidRootPart")
			if not root then
				return nil
			end
			if automationHelpers.distanceFromPositionToInstance(root.Position, model)
				> PICKUP_MAX_DISTANCE then
				if not moveNearWorldItem(model) then
					return nil
				end
				root = player.Character
					and player.Character:FindFirstChild("HumanoidRootPart")
			end
			if not root
				or automationHelpers.distanceFromPositionToInstance(root.Position, model)
					> PICKUP_MAX_DISTANCE then
				return nil
			end
			if sameItemName(itemName, "Cross")
				and automationHelpers.worldItemIsBurntCross(model) then
				return nil
			end
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
			itemName: any,
			protectedNames: any,
			optional: any,
			returnToFavouriteRoom: any
		): any
			local storedItem = scanStoredInventory(itemName)
			local existingSlot = findInventorySlot(itemName)
			if storedItem or existingSlot then
				existingSlot = existingSlot
					or waitForHotbarSlot(itemName, 2)
				return true, storedItem, existingSlot
			end

			local found: any, model: any = findItem(itemName)
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

				local stillFound: any, refreshedModel: any =
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

		local function toggleEquippedItem(itemName: any): boolean
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
			protectedNames: any,
			returnToFavouriteRoom: any
		): boolean
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
						if not slotItemIsProtected(
							slotNumber,
							slotName,
							protectedNames
						) then
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

		local function shuffledCopy(list: any): any
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

		local function shouldActivate(itemName: any): boolean
			return sameItemName(itemName, "Spirit Box")
				or sameItemName(itemName, "Laser Projector")
				or sameItemName(itemName, "Blacklight")
				or sameItemName(itemName, "EMF Reader")
		end

		local function activateBatch(batch: any): ()
			for _, itemName in ipairs(batch) do
				if shouldActivate(itemName)
					and inventoryHasItem(itemName) then
					local slotNumber: any =
						waitForHotbarSlot(itemName, 2)
						or findInventorySlot(itemName)
					if slotNumber
						and equipNamedItem(itemName, true, false) then
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

		local function dropBatch(batch: any): ()
			waitForNoHunt(true)
			activateBatch(batch)

			for _, itemName in ipairs(batch) do
				if inventoryHasItem(itemName) then
					local slotNumber: any =
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

			local remaining: any = shuffledCopy(coreOrder)

			while #remaining > 0 do
				local batch: any = {}
				local randomized: any = shuffledCopy(remaining)
				remaining = {}

				for itemIndex = 1, #randomized do
					local itemName: any = randomized[itemIndex]
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

			local retainedOrder: any = shuffledCopy(finalOrder)
			for entryIndex = 1, #retainedOrder do
				local entry: any = retainedOrder[entryIndex]
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
			roomItemPlacementState.lastResult = ok and #failedItems == 0
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
	DistanceFromPositionToInstance = automationHelpers.distanceFromPositionToInstance,
	CharacterIsFullyInsideRoom = automationHelpers.characterIsFullyInsideRoom,
	WorldItemIsFullyInsideRoom = automationHelpers.worldItemIsFullyInsideRoom,
	WorldItemIsInsideRoomBounds = automationHelpers.worldItemIsInsideRoomBounds,
	WorldItemIsBurntCross = automationHelpers.worldItemIsBurntCross,
	FindExitDoorDescriptors = automationHelpers.findExitDoorDescriptors,
	InstanceBelongsToExitDoor = automationHelpers.instanceBelongsToExitDoor,
	TeleportToRoom = teleportToRoomBoundingBoxCenter,
	TeleportToBaseCamp = teleportToBaseCamp,
	TeleportToFavouriteRoom = teleportToFavouriteRoom,
	PlaceItemsInFavouriteRoom = placeItemsInFavouriteRoom,
	InstanceIsInsideRoom = instanceIsInsideRoom,
	State = doRoundState,
	PerkTrackerState = perkTrackerState,
	RoomItemPlacementState = roomItemPlacementState,
	GhostSession = GhostSession,
	GetGhostSessionInput = function()
		return ghostSessionInput(nil, os.clock())
	end,
	Presenter = presenter,
	PlaceRoomItemsButton = placeRoomItemsButton,
	Copy = COPY,
	Colors = COLORS,
	RefreshAutoSpiritBoxEnabled = refreshAutoSpiritBoxEnabled,
	SetDoRoundStatus = setDoRoundStatus,
	SetGhostIdentificationLabel = setGhostIdentificationLabel,
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
local function scanSpiritBookWriting(items: any): boolean
	local function spiritBookHasWriting(model: any): boolean
		if not model or not model:IsA("Model") then
			return false
		end
		local itemName = string.lower(
			tostring(model:GetAttribute("ItemName") or "")
		)
		local modelName = string.lower(model.Name)
		local identifiedBook = itemName == "spirit book"
			or modelName == "spirit book"
		local canvas: any = model:FindFirstChild("Canvas", true)
		local surfaceGui: any = canvas and canvas:FindFirstChild("SurfaceGui")
		local frame: any = surfaceGui and surfaceGui:FindFirstChild("Frame")
		local imageLabel: any = frame and frame:FindFirstChild("ImageLabel")
		if imageLabel and imageLabel:IsA("ImageLabel")
			and imageLabel.Image ~= "" then
			return true
		end
		if not identifiedBook then
			return false
		end
		local descendants: any = model:GetDescendants()
		for _, descendant: any in ipairs(descendants) do
			if descendant:IsA("Decal") and descendant.Texture ~= "" then
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
	local checked: any = setmetatable({}, {__mode = "k"})
	local containers: any = {
		items,
		player:FindFirstChild("ToolsHolder"),
		player.Character,
	}
	for _, container: any in ipairs(containers) do
		if container then
			local descendants: any = container:GetDescendants()
			for _, descendant: any in ipairs(descendants) do
				if descendant:IsA("Model") and not checked[descendant] then
					checked[descendant] = true
					if spiritBookHasWriting(descendant) then
						return true
					end
				end
			end
		end
	end
	return false
end
local function scanHighestEMFReader(): number
	local best: number = highestEMF
	local checkedReaders: any = setmetatable({}, {__mode = "k"})
	local containers: any = {
		workspace:FindFirstChild("Items"),
		player:FindFirstChild("ToolsHolder"),
		player.Character,
	}
	for _, container: any in ipairs(containers) do
		if container then
			local descendants: any = container:GetDescendants()
			for _, candidate: any in ipairs(descendants) do
				if candidate:IsA("Model")
					and not checkedReaders[candidate]
					and candidate:GetAttribute("ItemName") == "EMF Reader" then
					checkedReaders[candidate] = true
					local readingObject: any = candidate:FindFirstChild(
						"ReadingLevel",
						true
					)
					local level: any = if readingObject
						and (readingObject:IsA("NumberValue")
							or readingObject:IsA("IntValue"))
						then readingObject.Value
						else candidate:GetAttribute("ReadingLevel")
					local numericLevel: number? = tonumber(level)
					if numericLevel then
						best = math.max(
							best,
							math.clamp(math.floor(numericLevel + 0.5), 1, 5)
						)
					end
				end
			end
		end
	end
	return best
end
local function scanDeepEvidence(): any
	local needPrint: boolean = not evidenceFound.Print
	local needOrb: boolean = not perkTrackerState.orbObserved

	if needPrint or needOrb then
		for _, object: any in ipairs(workspace:GetDescendants()) do
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
		highestEMF = scanHighestEMFReader()
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
	if not evidenceFound.Inscription and scanSpiritBookWriting(items) then
		evidenceFound.Inscription = true
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
	local resolvedVoiceCategory = type(voiceCategory) == "string"
		and voiceCategory ~= ""
		and voiceCategory
		or (voiceInfo.Female == true and "Female" or nil)
	ghostObservationRuntime:SpiritBox({
		Subtitle = key,
		VoiceCategory = resolvedVoiceCategory,
		Female = voiceInfo.Female == true,
	})
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
	ensureItemEnabledTracker()
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
			resetEvidenceState()
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
			resetEvidenceState()
		end
	end
	evidenceRoundGhost = ghost
	perkTrackerState.roundMap = currentMap
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
	perkTrackerState.dispatchResidualEvidenceObservation(ghost)
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

local ghostObservationApi: any = {}

function ghostObservationApi:Detect(ghostName, reason, confidence, source)
	return ghostTracker:Detect(ghostName, reason, confidence, source)
end

function ghostObservationApi:RuleOut(ghostName, reason, confidence)
	return perkTrackerState.ruleOutGhost(ghostName, reason, confidence)
end

function ghostObservationApi:ClearDetection(ghostName)
	return ghostTracker:ClearDetection(ghostName)
end

function ghostObservationApi:ClearRuleOut(ghostName)
	return perkTrackerState.clearGhostRuleOut(ghostName)
end

function ghostObservationApi:GetDetection(ghostName)
	return ghostTracker:GetDetection(ghostName)
end

function ghostObservationApi:SetDetection(ghostName, detection)
	return ghostTracker:SetDetection(ghostName, detection)
end

function ghostObservationApi:IsRuledOut(ghostName)
	return perkTrackerState.isGhostRuledOut(ghostName)
end

function ghostObservationApi:MarkPersistent(ghostName)
	return ghostTracker:MarkPersistent(ghostName)
end

function ghostObservationApi:Mode()
	return perkTrackerState.evidenceMode
end

function ghostObservationApi:SupportsConfirmedEvidence(ghostName)
	return ghostSupportsConfirmedEvidence(ghostName, getConfirmedEvidence())
end

function ghostObservationApi:Refresh(ghost)
	updateGhostIdentification(ghost or getGhostModel())
	return true
end

local function handleGhostObservationAction(action)
	if type(action) ~= "table" then
		return false
	end
	local actionType = action.Type
	if actionType == "Detect" then
		return ghostObservationApi:Detect(
			action.Ghost,
			action.Reason,
			action.Confidence,
			action.Source
		)
	elseif actionType == "RuleOut" then
		return ghostObservationApi:RuleOut(
			action.Ghost,
			action.Reason,
			action.Confidence
		)
	elseif actionType == "ClearDetection" then
		return ghostObservationApi:ClearDetection(action.Ghost)
	elseif actionType == "ClearRuleOut" then
		return ghostObservationApi:ClearRuleOut(action.Ghost)
	elseif actionType == "Refresh" then
		return ghostObservationApi:Refresh(action.GhostModel)
	elseif actionType == "Dispatch" then
		return ghostObservationRuntime:Dispatch(action.Hook, action.Event)
	end
	return false
end

local rawGhostObservationRuntime = createGhostObservationRuntime({
	Definitions = GhostPackage.Definitions,
	Api = ghostObservationApi,
	Mode = perkTrackerState.evidenceMode,
	OnAction = handleGhostObservationAction,
	OnError = function(message, context)
		print(("Ghost observer %s/%s failed: %s"):format(
			tostring(context and context.Ghost or "unknown"),
			tostring(context and context.Hook or "unknown"),
			tostring(message)
		))
	end,
})
ghostObservationRuntime = createGhostObservationCollector({
	Runtime = rawGhostObservationRuntime,
	Mode = perkTrackerState.evidenceMode,
	DestroyRuntime = true,
	OnError = function(message, context)
		print(("Ghost collector %s failed: %s"):format(
			tostring(context and (context.Hook or context.Phase) or "unknown"),
			tostring(message)
		))
	end,
})

local Controller: any = {}
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
	ghostObservationRuntime:SetMode(mode)
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

	local eligible: any = {}
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
	perkTrackerState.suppressRoomLightObservationsUntil = os.clock() + 2.5

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
			local room: any = eligible[index]
			local switch: any = room and room:FindFirstChild("LightSwitch", true)
			local beforeRoom: any = room and room:GetAttribute("LightsOn")
			local beforeSwitch: any = switch and switch:GetAttribute("State")

			if room
				and room.Parent == rooms
				and room:GetAttribute("LightsBroken") ~= true
				and (not switch or switch:GetAttribute("LightsBroken") ~= true) then
				pcall(remote.FireServer, remote, room)
				perkTrackerState.suppressRoomLightObservationsUntil = os.clock() + 2.5
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
		perkTrackerState.suppressRoomLightObservationsUntil = math.max(
			perkTrackerState.suppressRoomLightObservationsUntil,
			os.clock() + 3
		)
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
					perkTrackerState.suppressRoomLightObservationsUntil = math.max(
						perkTrackerState.suppressRoomLightObservationsUntil,
						os.clock() + 3
					)
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
			perkTrackerState.suppressRoomLightObservationsUntil = math.max(
				perkTrackerState.suppressRoomLightObservationsUntil,
				os.clock() + 2.5
			)
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
	if ghostObservationRuntime then
		ghostObservationRuntime:Destroy()
	end
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

local controller: any = setmetatable({}, Controller)
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
	lastDeepEvidenceScan = -math.huge

	local updateAccumulator = 0
	connect(Services.RunService.Heartbeat, function(deltaTime)
		if not runtimeIsActive() then
			return
		end
		local observationReady, observationTime =
			updateObservablePerkTrackers(deltaTime)
		if observationReady then
			ghostObservationRuntime:Tick({
				DeltaTime = deltaTime,
				Time = observationTime,
			})
		end
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
	return self
end

if generation == nil or environment.DemonologyGeneration == generation then
	environment.UntitledGuiCleanup = function()
		controller:Destroy()
	end
end

return controller
end
