return function(package: any)
	local dependencies: any = assert(package.Dependencies, "post-round requires Dependencies")
	local Pre: any = assert(package.Pre, "post-round requires Pre")
	local Services: any = assert(dependencies.Services, "post-round requires Services")
	local player: any = assert(dependencies.Player, "post-round requires Player")
	local doRoundState: any = assert(dependencies.State, "post-round requires State")
	local perkTrackerState: any = assert(dependencies.PerkTrackerState, "post-round requires PerkTrackerState")
	local roomItemPlacementState: any = assert(dependencies.RoomItemPlacementState, "post-round requires RoomItemPlacementState")
	local perkDetections: any = assert(dependencies.PerkDetections, "post-round requires PerkDetections")
	local GHOST_PROFILES: any = assert(dependencies.GhostProfiles, "post-round requires GhostProfiles")
	local GhostModule: any = assert(dependencies.GhostModule, "post-round requires GhostModule")
	local presenter: any = dependencies.Presenter
	local placeRoomItemsButton: any = assert(dependencies.PlaceRoomItemsButton, "post-round requires PlaceRoomItemsButton")
	local COPY: any = assert(dependencies.Copy, "post-round requires Copy")
	local COLORS: any = assert(dependencies.Colors, "post-round requires Colors")
	local setGhostIdentificationLabel: any = assert(dependencies.SetGhostIdentificationLabel, "post-round requires SetGhostIdentificationLabel")
	local setDoRoundStatus: any = assert(dependencies.SetDoRoundStatus, "post-round requires SetDoRoundStatus")
	local prepareTeleport: any = dependencies.PrepareTeleport
	local evidenceReady: any = dependencies.EvidenceReady or function() return true end
	if type(prepareTeleport) ~= "function" then
		prepareTeleport = function() return true end
	end
	local doRoundOperationActive = Pre.OperationActive
	local doRoundWait = Pre.Wait
	local playerIsInsideRoundBaseCamp = Pre.PlayerIsInsideBaseCamp
	local returnRoundToBase = Pre.ReturnToBase
	local ROUND_REMOTE_SAFETY_DELAY = Pre.RemoteSafetyDelay
	local ROUND_LOBBY_RETRY_SECONDS = Pre.LobbyRetrySeconds
	local ROUND_MINIMUM_LEAVE_AGE = Pre.MinimumLeaveAge
	local ROUND_JOURNAL_SETTLE_SECONDS = Pre.JournalSettleSeconds
	local disable = function() return false end

local function journalSelectionMatchesFinalState(ghostName)
	local ghostTypes = perkTrackerState.findJournalGhostTypes()
	if not ghostTypes then
		return false
	end
	for _, profile in ipairs(GHOST_PROFILES) do
		local frame = ghostTypes:FindFirstChild(profile.Name)
		if not frame or not frame:IsA("Frame") then
			return false
		end
		local expected = perkTrackerState.expectedJournalState(
			profile.Name,
			ghostName
		)
		local actual = perkTrackerState.readJournalRowState(frame)
		if expected ~= nil and actual ~= expected then
			return false
		end
		if expected == nil and actual == true then
			return false
		end
	end
	return perkTrackerState.lastJournalSelectedGhost == ghostName
end

local function selectRoundJournalGhost(ghostName, generation)
	if not ghostName or string.find(tostring(ghostName), "/", 1, true) then
		return false
	end
	if not doRoundOperationActive(generation) then
		return false
	end
	-- Sync the complete Verdict state: one selected row, every RuledOut row
	-- crossed out, and unknown rows untouched. The real click path updates the
	-- Journal controller before its EvidenceMarkedInJournal remote is sent.
	local deadline = os.clock() + 8
	repeat
		if not doRoundOperationActive(generation) then
			return false
		end
		if perkTrackerState.journalMutationBusy ~= true then
			local syncedCall, synced = pcall(
				perkTrackerState.syncJournal,
				ghostName
			)
			if syncedCall and synced == true
				and journalSelectionMatchesFinalState(ghostName) then
				doRoundWait(generation, ROUND_JOURNAL_SETTLE_SECONDS)
				if journalSelectionMatchesFinalState(ghostName) then
					return true
				end
			end
		end
		task.wait(0.05)
	until not doRoundOperationActive(generation)
		or os.clock() >= deadline
	return false
end

local function cancelRoundTask(fieldName)
	local thread = doRoundState[fieldName]
	doRoundState[fieldName] = nil
	if thread and thread ~= coroutine.running() then
		pcall(task.cancel, thread)
	end
end

local function requestRoundReturnToLobby(generation, ghostName)
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local remote = events and events:FindFirstChild("RequestReturnToLobby")
	if not remote or not remote:IsA("RemoteEvent") then
		return false, "RequestReturnToLobby RemoteEvent was not found"
	end
	local lastTeleportState
	local connected, teleportConnection = pcall(function()
		return player.OnTeleport:Connect(function(state)
			lastTeleportState = state
		end)
	end)
	if not connected then teleportConnection = nil end
	local function disconnectTeleportListener()
		if teleportConnection and teleportConnection.Connected then
			teleportConnection:Disconnect()
		end
	end
	local completed, returned, returnReason = xpcall(function()
		local queueWarningShown = false
		local basePositionPrepared = false
		local roundStartedAt = doRoundState.exitOpenedAt
			or doRoundState.startedAt
			or os.clock()
		local earliestReturnAt = roundStartedAt + ROUND_MINIMUM_LEAVE_AGE
		while doRoundOperationActive(generation) do
			if (not basePositionPrepared or not playerIsInsideRoundBaseCamp())
				and not returnRoundToBase(generation) then
				return false, "Do-Round cancelled before the Base Camp return"
			end
			basePositionPrepared = true
			if not playerIsInsideRoundBaseCamp() then
				doRoundWait(generation, 0.1)
				continue
			end
			local leaveWait = earliestReturnAt - os.clock()
			if leaveWait > 0 then
				setDoRoundStatus("Waiting safely until 0:30")
				doRoundWait(generation, math.min(0.25, leaveWait))
				continue
			end
			if lastTeleportState == Enum.TeleportState.Failed then
				setDoRoundStatus("Lobby return failed; retrying")
				lastTeleportState = nil
			else
				setDoRoundStatus("Returning to lobby")
			end
			if not journalSelectionMatchesFinalState(ghostName) then
				return false, "the final Journal state was lost before lobby return"
			end
			doRoundWait(generation, ROUND_REMOTE_SAFETY_DELAY)
			-- Displacement during the safety delay invalidates this attempt. Hunt
			-- state is deliberately irrelevant once identification is confident.
			if not playerIsInsideRoundBaseCamp() then
				continue
			end
			local preparedCall, prepared, prepareFailure = pcall(
				prepareTeleport,
				"ReturnToLobby"
			)
			if (not preparedCall or prepared == false)
				and not queueWarningShown
				and presenter and presenter.Notify then
				queueWarningShown = true
				presenter:Notify(
					not preparedCall
						and ("return teleport preparation failed: " .. tostring(prepared))
						or tostring(prepareFailure
							or "return teleport execution was not prepared")
				)
			end
			pcall(remote.FireServer, remote)
			-- Started/InProgress is not a terminal success signal. Teleport can still
			-- fail after either state, so retain ownership and retry every four
			-- seconds until this runtime is actually replaced or the user cancels.
			local nextFireAt = os.clock() + ROUND_LOBBY_RETRY_SECONDS
			while doRoundOperationActive(generation)
				and os.clock() < nextFireAt do
				task.wait(math.min(0.05, math.max(0, nextFireAt - os.clock())))
			end
			-- If the server rejected this attempt, generate another settled root
			-- position update before the next four-second retry.
			basePositionPrepared = false
		end
		return false, "Do-Round cancelled before returning to the lobby"
	end, debug.traceback)
	disconnectTeleportListener()
	if not completed then
		if not doRoundOperationActive(generation) then
			return false, "Do-Round cancelled before returning to the lobby"
		end
		return false,
			tostring(returned):match("^[^\n]+") or "Lobby return failed"
	end
	return returned, returnReason
end

local function chooseRoundTimeoutFallback()
	local guess = perkTrackerState.currentGhostGuess
	local score = perkTrackerState.currentGhostGuessScore or 0
	local timeoutCandidates = perkTrackerState.getRemainingCandidates(false)
	if #timeoutCandidates == 0 then
		-- Confirmed evidence is stronger than behavioral/perk rule-outs. If
		-- those signals conflict, relax only the rule-outs while retaining the
		-- evidence-compatible pool. This prevents a timed fallback from
		-- reintroducing ghosts that cannot have the observed evidence.
		timeoutCandidates = perkTrackerState.getRemainingCandidates(true)
	end
	if #timeoutCandidates == 0 then
		for _, profile in ipairs(GHOST_PROFILES) do
			if not perkTrackerState.isGhostRuledOut(profile.Name) then
				table.insert(timeoutCandidates, profile.Name)
			end
		end
	end
	if #timeoutCandidates == 0 then
		-- Contradictory rule-outs must not prevent a timed round from ending.
		for _, profile in ipairs(GHOST_PROFILES) do
			table.insert(timeoutCandidates, profile.Name)
		end
	end
	if perkTrackerState.evidenceMode == "Mimicry" then
		local included = {}
		for _, name in ipairs(timeoutCandidates) do
			included[name] = true
		end
		for name, detection in pairs(perkDetections) do
			if detection.Persistent
				and not perkTrackerState.isGhostRuledOut(name)
				and not included[name] then
				table.insert(timeoutCandidates, name)
				included[name] = true
			end
		end
	end
	local fallback = GhostModule.SelectHighestConfidenceGuess({
		Candidates = timeoutCandidates,
		Detections = perkDetections,
		CurrentGuess = guess,
		CurrentScore = score,
		ConfirmedEvidence = perkTrackerState.evidenceMode ~= "Mimicry"
			and perkTrackerState.getConfirmedEvidence()
			or nil,
		OrbObserved = perkTrackerState.orbObserved == true,
		RandomUnit = function()
			return math.random()
		end,
		RandomIndex = function(count)
			return math.random(count)
		end,
	})
	if not fallback then
		return nil, 0
	end
	local fallbackDetection = perkDetections[fallback]
	local fallbackScore = fallbackDetection
		and tonumber(
			fallbackDetection.NetConfidence
				or fallbackDetection.Confidence
		)
		or 0
	if guess == fallback then
		fallbackScore = math.max(fallbackScore, score)
	end
	return fallback, math.max(fallbackScore, 1)
end

local function finishRoundWithGhost(
	ghostName,
	confidence,
	certain,
	generation,
	finalPhase
)
	if doRoundState.completionGhost then
		ghostName = doRoundState.completionGhost
		confidence = doRoundState.completionScore or confidence
		certain = doRoundState.completionCertain == true
	else
		doRoundState.completionGhost = ghostName
		doRoundState.completionScore = confidence
		doRoundState.completionCertain = certain == true
	end
	-- Lock the final choice before any journal or tracker yield. Background
	-- identification refreshes must not replace a low-confidence timeout choice
	-- with the earlier multi-candidate label while completion is in progress.
	perkTrackerState.journalForcedGhost = ghostName
	perkTrackerState.currentGhostGuess = ghostName
	perkTrackerState.currentGhostGuessScore = confidence
	perkTrackerState.currentGhostGuessCertain = certain == true
	if presenter and presenter.SetGhostIdentificationLock then
		local _, tierName = GhostModule.ConfidenceTier(confidence)
		presenter:SetGhostIdentificationLock(
			ghostName,
			tierName,
			certain == true
		)
	end
	setGhostIdentificationLabel(ghostName, confidence, certain == true)
	setDoRoundStatus("Selecting ghost guess")
	local selectedCall, selected = pcall(
		selectRoundJournalGhost,
		ghostName,
		generation
	)
	if not selectedCall or selected ~= true then
		return false, "the final ghost is not selected in the Journal yet"
	end
	if not doRoundOperationActive(generation) then
		return false, "Do-Round cancelled before lobby return"
	end
	setDoRoundStatus("Identified; returning to Base Camp")
	if not returnRoundToBase(generation) then
		return false, "Do-Round cancelled before the Base Camp return"
	end
	local returned, returnReason = requestRoundReturnToLobby(
		generation,
		ghostName
	)
	if returned then
		disable(finalPhase)
		return true
	end
	return false, returnReason
end

local function cancelDoRoundSetupWork()
	if roomItemPlacementState.busy
		and roomItemPlacementState.owner == "DoRound" then
		roomItemPlacementState.generation =
			roomItemPlacementState.generation + 1
		roomItemPlacementState.busy = false
		roomItemPlacementState.thread = nil
		roomItemPlacementState.owner = nil
		placeRoomItemsButton.Text = COPY.Controls.PlaceRoomItems
		placeRoomItemsButton.BackgroundColor3 = COLORS.cardHover
	end
	doRoundState.questionsActive = false
	Pre.ReleaseMovement()
end

local function finishTimedRound(generation)
	if not evidenceReady() then
		return false, "waiting for evidence to settle before the final guess"
	end
	local fallback, fallbackScore = chooseRoundTimeoutFallback()
	if not fallback then
		return false, "no ghost profile was available for the timed guess"
	end
	return finishRoundWithGhost(
		fallback,
		fallbackScore,
		false,
		generation,
		"Selected " .. fallback
	)
end

local function currentConfidentRoundIdentification()
	if doRoundState.completionClaimed then
		return nil
	end
	if not evidenceReady() then return nil end
	local guess = perkTrackerState.currentGhostGuess
	local score = perkTrackerState.currentGhostGuessScore or 0
	local certain = perkTrackerState.currentGhostGuessCertain == true
	local singleGuess = guess
		and not string.find(guess, "/", 1, true)
	local eligible = false
	if singleGuess then
		for _, candidate in ipairs(
			perkTrackerState.getRemainingCandidates(certain)
		) do
			if candidate == guess then
				eligible = true
				break
			end
		end
	end
	if singleGuess and eligible and (certain or score >= 80) then
		return guess, score, certain
	end
	return nil
end

local function completeIdentifiedRound(generation, guess, score, certain)
	if not doRoundOperationActive(generation)
		or doRoundState.completionClaimed then
		return false
	end
	doRoundState.completionClaimed = true
	-- Completion takes ownership before any setup worker can pick up an item.
	-- The fresh generation invalidates all pre-round placement and door work.
	doRoundState.generation = doRoundState.generation + 1
	local completionGeneration = doRoundState.generation
	cancelRoundTask("identificationThread")
	cancelRoundTask("timeoutThread")
	cancelDoRoundSetupWork()
	while doRoundOperationActive(completionGeneration) do
		local completedCall, completed, completionFailure = xpcall(
			function()
				return finishRoundWithGhost(
					guess,
					score,
					certain,
					completionGeneration,
					"Identified " .. guess
				)
			end,
			debug.traceback
		)
		if completedCall and completed then
			return true
		end
		if not doRoundOperationActive(completionGeneration) then
			return false
		end
		if presenter and presenter.Notify then
			presenter:Notify(
				tostring(completionFailure or completed):match("^[^\n]+")
					or "Identified lobby return failed; retrying"
			)
		end
		task.wait(0.5)
	end
	return false
end

local function startRoundIdentificationWatchdog(generation)
	doRoundState.identificationThread = task.spawn(function()
		while doRoundOperationActive(generation)
			and not doRoundState.completionClaimed do
			local guess, score, certain = currentConfidentRoundIdentification()
			if guess then
				completeIdentifiedRound(generation, guess, score, certain)
				return
			end
			task.wait(0.1)
		end
		doRoundState.identificationThread = nil
	end)
end

local function startRoundTimeoutWatchdog(generation)
	doRoundState.timeoutThread = task.delay(180, function()
		if not doRoundOperationActive(generation)
			or doRoundState.completionClaimed then
			return
		end
		doRoundState.completionClaimed = true
		-- Invalidate every setup/maintenance operation immediately. The new
		-- generation belongs exclusively to timed completion, so an active hunt
		-- or a yielded placement routine cannot postpone the three-minute return.
		doRoundState.generation = doRoundState.generation + 1
		local completionGeneration = doRoundState.generation
		doRoundState.timeoutThread = nil
		cancelRoundTask("identificationThread")
		cancelDoRoundSetupWork()
		while doRoundOperationActive(completionGeneration) do
			local completedCall, completed, completionFailure = xpcall(
				function()
					return finishTimedRound(completionGeneration)
				end,
				debug.traceback
			)
			if completedCall and completed then
				return
			end
			if not doRoundOperationActive(completionGeneration) then
				return
			end
			if presenter and presenter.Notify then
				presenter:Notify(
					tostring(completionFailure or completed):match("^[^\n]+")
						or "Timed lobby return failed; retrying"
				)
			end
			task.wait(0.5)
		end
	end)
end


local API = {
	CurrentIdentification = currentConfidentRoundIdentification,
	Complete = completeIdentifiedRound,
	FinishTimed = finishTimedRound,
	CancelTask = cancelRoundTask,
	CancelSetup = cancelDoRoundSetupWork,
	StartIdentificationWatchdog = startRoundIdentificationWatchdog,
	StartTimeoutWatchdog = startRoundTimeoutWatchdog,
}

function API:SetDisable(callback)
	disable = assert(callback, "post-round requires a disable callback")
end

return API
end
