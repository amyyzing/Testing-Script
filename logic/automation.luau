return function(dependencies)
	local Services = assert(dependencies.Services, "automation requires Services")
	local player = assert(dependencies.Player, "automation requires Player")
	local ghost = assert(dependencies.Ghost, "automation requires Ghost")
	local Verdict = assert(dependencies.Verdict, "automation requires Verdict")
	local movement = assert(dependencies.Movement, "automation requires Movement")
	local createRoundAutomation = assert(
		dependencies.CreateRoundAutomation,
		"automation requires CreateRoundAutomation"
	)
	local createRoomItemSetup = assert(
		dependencies.CreateRoomItemSetup,
		"automation requires CreateRoomItemSetup"
	)
	local runtimeIsActive = dependencies.RuntimeIsActive or function() return true end
	local button = dependencies.Button
	local enabledColor = dependencies.EnabledColor
	local disabledColor = button and button.BackgroundColor3
	local autoSpirit = dependencies.AutoSpirit
	local onEnabledChanged = dependencies.OnEnabledChanged
	local confidenceNeeded = tonumber(dependencies.ConfidenceNeeded) or 80
	local world = Services.Workspace
	local stopped = false

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
		facingLocks = setmetatable({}, {__mode = "k"}),
	}
	local roomItemPlacementState = {
		busy = false,
		generation = 0,
		thread = nil,
		owner = nil,
		lastResult = nil,
		lastError = nil,
		lastCompletedGeneration = 0,
	}
	local ghostProfiles = {}
	local ghostIndexes = {}
	for index, name in ipairs(Verdict.Lists) do
		ghostProfiles[index] = {Name = name}
		ghostIndexes[name] = index
	end

	local function isRuledOut(index)
		return table.find(Verdict.RuledOut, index) ~= nil
	end

	local function score(index)
		return math.max(0,
			(tonumber(Verdict.Confidence[index]) or 0)
				- (tonumber(Verdict.NegativeConfidence[index]) or 0))
	end

	local function bestGuess(candidates)
		local allowed
		if type(candidates) == "table" then
			allowed = {}
			for _, name in ipairs(candidates) do allowed[name] = true end
		end
		local bestName, bestScore
		for index, name in ipairs(Verdict.Lists) do
			if not isRuledOut(index) and (not allowed or allowed[name]) then
				local candidateScore = score(index)
				if bestName == nil or candidateScore > bestScore
					or (candidateScore == bestScore
						and bestName == "Skinwalker" and name ~= "Skinwalker") then
					bestName, bestScore = name, candidateScore
				end
			end
		end
		return bestName, bestScore or 0
	end

	local perkBacking = {
		evidenceMode = "Normal",
		orbObserved = false,
		journalMutationBusy = false,
		journalForcedGhost = nil,
		lastJournalSelectedGhost = nil,
		lastJournalVisualGhost = nil,
		suppressItemDisableUntil = 0,
	}
	local perkTrackerState = setmetatable(perkBacking, {
		__index = function(_, key)
			if key == "currentGhostGuess" then return bestGuess() end
			if key == "currentGhostGuessScore" then return select(2, bestGuess()) end
			if key == "currentGhostGuessCertain" then
				local _, currentScore = bestGuess()
				return currentScore >= 100
			end
			return nil
		end,
	})

	function perkTrackerState.isGhostRuledOut(name)
		local index = ghostIndexes[name]
		return index == nil or isRuledOut(index)
	end

	function perkTrackerState.getGhostNegativeConfidence(name)
		local index = ghostIndexes[name]
		return index and (Verdict.NegativeConfidence[index] or 0) or 0
	end

	function perkTrackerState.getRemainingCandidates()
		local result = {}
		for index, name in ipairs(Verdict.Lists) do
			if not isRuledOut(index) then table.insert(result, name) end
		end
		return result
	end

	function perkTrackerState.getConfirmedEvidence()
		return {}
	end

	function perkTrackerState.findJournalGhostTypes()
		return Verdict:FindJournalGhostTypes()
	end

	function perkTrackerState.readJournalRowState(frame)
		return Verdict:ReadJournalRowState(frame)
	end

	function perkTrackerState.expectedJournalState(name, forcedGhost)
		return Verdict:ExpectedJournalState(name, forcedGhost)
	end

	function perkTrackerState.syncJournal(forcedGhost)
		if type(forcedGhost) ~= "string" then return false end
		if perkTrackerState.journalMutationBusy then return false end
		perkTrackerState.journalMutationBusy = true
		local syncedCall, synced = pcall(Verdict.SyncJournal, Verdict, forcedGhost)
		perkTrackerState.journalMutationBusy = false
		if syncedCall and synced == true then
			perkTrackerState.lastJournalSelectedGhost = forcedGhost
			perkTrackerState.lastJournalVisualGhost = forcedGhost
		end
		return syncedCall and synced == true
	end

	local perkDetections = {}
	for index, name in ipairs(Verdict.Lists) do
		perkDetections[name] = setmetatable({Persistent = false}, {
			__index = function(_, key)
				if key == "Confidence" then
					return tonumber(Verdict.Confidence[index]) or 0
				end
				return nil
			end,
		})
	end

	local GhostModule = dependencies.GhostModule
	if type(GhostModule) == "table" and type(GhostModule.Profiles) == "table" then
		ghostProfiles = GhostModule.Profiles
	else
		GhostModule = {}
		function GhostModule.Find(name)
			return ghostIndexes[name] and ghostProfiles[ghostIndexes[name]] or nil
		end
		function GhostModule.ConfidenceTier(value)
			value = tonumber(value) or 0
			if value >= 100 then return 4, "Certain" end
			if value >= confidenceNeeded then return 3, "Pretty Sure" end
			if value >= 35 then return 2, "Maybe" end
			return 1, "Idk"
		end
		function GhostModule.SelectHighestConfidenceGuess(options)
			local name = bestGuess(options and options.Candidates)
			return name
		end
	end

	perkTrackerState.findBaseCampRoom = movement.FindBaseCampRoom
	perkTrackerState.teleportToRoomBoundingBoxCenter = movement.TeleportToRoom
	perkTrackerState.teleportToBaseCamp = movement.TeleportToBaseCamp
	perkTrackerState.teleportToFavouriteRoom = movement.TeleportToFavouriteRoom

	local dummyItemButton = {Text = "", BackgroundColor3 = disabledColor}
	local COPY = {
		Actions = {
			PlacingRoomItems = "Placing room items",
			WaitingForHunt = "Waiting for hunt",
		},
		Controls = {PlaceRoomItems = "Place Room Items"},
	}
	local COLORS = {accentDark = disabledColor, cardHover = disabledColor}
	local placeItemsInFavouriteRoom = createRoomItemSetup({
		Services = Services,
		Player = player,
		RuntimeIsActive = runtimeIsActive,
		GetGhostModel = function() return world:FindFirstChild("Ghost") end,
		FindRoomsFolder = movement.FindRoomsFolder,
		FindFavouriteRoom = movement.FindFavouriteRoom,
		GetRoomBoundingParts = movement.GetRoomBoundingParts,
		InstanceIsInsideRoom = movement.InstanceIsInsideRoom,
		State = roomItemPlacementState,
		PerkTrackerState = perkTrackerState,
		Button = dummyItemButton,
		Copy = COPY,
		Colors = COLORS,
	})

	local function render()
		if not button then return end
		local elapsed = doRoundState.startedAt
			and math.max(0, os.clock() - doRoundState.startedAt)
			or doRoundState.lastElapsed or 0
		button.Text = doRoundState.enabled
			and ("AUTOMATION: ON %d:%02d\n%s"):format(
				math.floor(elapsed / 60),
				math.floor(elapsed % 60),
				tostring(doRoundState.phase or "Running")
			)
			or "AUTOMATION: OFF\nReady"
		button.BackgroundColor3 = doRoundState.enabled
			and (enabledColor or disabledColor) or disabledColor
	end

	local function setDoRoundStatus(value)
		doRoundState.phase = tostring(value or doRoundState.phase or "Off")
		render()
	end

	local autoSpiritBeforeAutomation
	local function refreshAutoSpiritBoxEnabled()
		if not autoSpirit or type(autoSpirit.SetEnabled) ~= "function" then return false end
		if doRoundState.autoSpiritBoxLease then
			if autoSpiritBeforeAutomation == nil then
				autoSpiritBeforeAutomation = autoSpirit.Enabled == true
			end
			autoSpirit.ShouldAsk = function()
				return doRoundState.enabled
					and doRoundState.questionsActive
					and ghost:GetAttribute("Hunting") ~= true
			end
			autoSpirit:SetEnabled(true)
			return true
		end
		autoSpirit.ShouldAsk = nil
		local restore = autoSpiritBeforeAutomation == true
		autoSpiritBeforeAutomation = nil
		autoSpirit:SetEnabled(restore)
		return restore
	end

	local function releasePlayerMovement(force)
		if doRoundState.enabled and force ~= true then return false end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not root or not humanoid
			or humanoid.Health <= 0 or player:GetAttribute("Dead") == true then
			return false
		end
		pcall(function()
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
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

	local presenter = {}
	function presenter:Notify(message)
		pcall(function()
			game:GetService("StarterGui"):SetCore("SendNotification", {
				Title = "Demonology Assistant",
				Text = tostring(message),
				Duration = 5,
			})
		end)
	end
	function presenter:SetGhostIdentificationLock() end

	local legacy = createRoundAutomation({
		Services = Services,
		Player = player,
		RuntimeIsActive = runtimeIsActive,
		GetGhostModel = function() return world:FindFirstChild("Ghost") end,
		FindRoomsFolder = movement.FindRoomsFolder,
		FindFavouriteRoom = movement.FindFavouriteRoom,
		FindBaseCampRoom = movement.FindBaseCampRoom,
		GetInstanceWorldPosition = movement.GetInstanceWorldPosition,
		GetRoomBoundingParts = movement.GetRoomBoundingParts,
		PointIsInsidePart = movement.PointIsInsidePart,
		TeleportToRoom = movement.TeleportToRoom,
		TeleportToBaseCamp = movement.TeleportToBaseCamp,
		TeleportToFavouriteRoom = movement.TeleportToFavouriteRoom,
		PlaceItemsInFavouriteRoom = placeItemsInFavouriteRoom,
		InstanceIsInsideRoom = movement.InstanceIsInsideRoom,
		State = doRoundState,
		PerkTrackerState = perkTrackerState,
		RoomItemPlacementState = roomItemPlacementState,
		PerkDetections = perkDetections,
		GhostProfiles = ghostProfiles,
		GhostModule = GhostModule,
		Presenter = presenter,
		PlaceRoomItemsButton = dummyItemButton,
		Copy = COPY,
		Colors = COLORS,
		RefreshAutoSpiritBoxEnabled = refreshAutoSpiritBoxEnabled,
		SetDoRoundStatus = setDoRoundStatus,
		SetGhostIdentificationLabel = function() end,
		ReleasePlayerMovement = releasePlayerMovement,
		PrepareTeleport = dependencies.PrepareReturn,
	})

	local controller = {
		Enabled = false,
		State = doRoundState,
		TeleportToBaseCamp = movement.TeleportToBaseCamp,
	}
	local lastEnabled = false

	local function synchronizeEnabled()
		local enabled = doRoundState.enabled == true
		controller.Enabled = enabled
		if enabled ~= lastEnabled then
			lastEnabled = enabled
			if type(onEnabledChanged) == "function" then onEnabledChanged(enabled) end
		end
		render()
	end

	function controller:SetEnabled(enabled)
		if stopped then return false end
		if enabled == true and doRoundState.enabled ~= true then
			rawset(perkTrackerState, "currentGhostGuess", nil)
			rawset(perkTrackerState, "currentGhostGuessScore", nil)
			rawset(perkTrackerState, "currentGhostGuessCertain", nil)
		end
		legacy.SetEnabled(enabled == true)
		synchronizeEnabled()
		return self.Enabled
	end

	function controller:Toggle()
		return self:SetEnabled(not doRoundState.enabled)
	end

	function controller:Destroy()
		if stopped then return end
		legacy.SetEnabled(false)
		stopped = true
		releasePlayerMovement(true)
		if self.ButtonConnection then self.ButtonConnection:Disconnect() end
		if self.RenderConnection then self.RenderConnection:Disconnect() end
	end

	if button then
		controller.ButtonConnection = button.MouseButton1Click:Connect(function()
			controller:Toggle()
		end)
	end
	if Services.RunService and Services.RunService.Heartbeat then
		local elapsed = 0
		controller.RenderConnection = Services.RunService.Heartbeat:Connect(function(delta)
			if stopped then return end
			elapsed += math.max(0, tonumber(delta) or 0)
			if elapsed >= 0.25 then
				elapsed = 0
				synchronizeEnabled()
			end
		end)
	end
	render()
	return controller
end
