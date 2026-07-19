return function(package: any)
	local dependencies: any = assert(package.Dependencies, "round phase requires Dependencies")
	local Pre: any = assert(package.Pre, "round phase requires Pre")
	local Post: any = assert(package.Post, "round phase requires Post")
	local Services: any = assert(dependencies.Services, "round phase requires Services")
	local player: any = assert(dependencies.Player, "round phase requires Player")
	local getGhostModel: any = assert(dependencies.GetGhostModel, "round phase requires GetGhostModel")
	local findRoomsFolder: any = assert(dependencies.FindRoomsFolder, "round phase requires FindRoomsFolder")
	local findFavouriteRoom: any = assert(dependencies.FindFavouriteRoom, "round phase requires FindFavouriteRoom")
	local getInstanceWorldPosition: any = assert(dependencies.GetInstanceWorldPosition, "round phase requires GetInstanceWorldPosition")
	local teleportToRoomBoundingBoxCenter: any = assert(dependencies.TeleportToRoom, "round phase requires TeleportToRoom")
	local teleportToBaseCamp: any = assert(dependencies.TeleportToBaseCamp, "round phase requires TeleportToBaseCamp")
	local teleportToFavouriteRoom: any = assert(dependencies.TeleportToFavouriteRoom, "round phase requires TeleportToFavouriteRoom")
	local placeItemsInFavouriteRoom: any = assert(dependencies.PlaceItemsInFavouriteRoom, "round phase requires PlaceItemsInFavouriteRoom")
	local instanceIsInsideRoom: any = assert(dependencies.InstanceIsInsideRoom, "round phase requires InstanceIsInsideRoom")
	local doRoundState: any = assert(dependencies.State, "round phase requires State")
	local perkTrackerState: any = assert(dependencies.PerkTrackerState, "round phase requires PerkTrackerState")
	local roomItemPlacementState: any = assert(dependencies.RoomItemPlacementState, "round phase requires RoomItemPlacementState")
	local presenter: any = dependencies.Presenter
	local placeRoomItemsButton: any = assert(dependencies.PlaceRoomItemsButton, "round phase requires PlaceRoomItemsButton")
	local COPY: any = assert(dependencies.Copy, "round phase requires Copy")
	local COLORS: any = assert(dependencies.Colors, "round phase requires Colors")
	local refreshAutoSpiritBoxEnabled: any = assert(dependencies.RefreshAutoSpiritBoxEnabled, "round phase requires RefreshAutoSpiritBoxEnabled")
	local setDoRoundStatus: any = assert(dependencies.SetDoRoundStatus, "round phase requires SetDoRoundStatus")
	local DROPPED_ROOM_ITEMS = Pre.DroppedRoomItems
	local POWERED_ROOM_ITEMS = Pre.PoweredRoomItems
	local normalizeRoundItemName = Pre.NormalizeItemName
	local roundItemName = Pre.ItemName
	local roundItemIsBurntCross = Pre.ItemIsBurntCross
	local getRoundInventoryItem = Pre.GetInventoryItem
	local findRoundHotbarSlot = Pre.FindHotbarSlot
	local getRoundEquippedItem = Pre.GetEquippedItem
	local roundApproachPositions = Pre.ApproachPositions
	local roundWorldItemIsInsideRoom = Pre.WorldItemIsInsideRoom
	local roundIsHunting = Pre.IsHunting
	local roundIdentityIsCurrent = Pre.IdentityIsCurrent
	local roundActionIsSafe = Pre.ActionIsSafe
	local doRoundOperationActive = Pre.OperationActive
	local doRoundWait = Pre.Wait
	local beginAutomationMutation = Pre.BeginMutation
	local teleportNearRoundTarget = Pre.TeleportNearTarget
	local roundTeleportOptions = Pre.TeleportOptions
	local playerIsInsideRoundBaseCamp = Pre.PlayerIsInsideBaseCamp
	local ROUND_PICKUP_MAX_DISTANCE = Pre.PickupMaxDistance
	local ROUND_REMOTE_SAFETY_DELAY = Pre.RemoteSafetyDelay
	local ROUND_ITEM_OUTSIDE_GRACE = Pre.ItemOutsideGrace
	local ROUND_MAINTENANCE_INTERVAL = Pre.MaintenanceInterval
	local ROUND_MAINTENANCE_RETRY_BACKOFF = Pre.MaintenanceRetryBackoff
	local ROUND_BASE_CAMP_RETRY_MIN = Pre.BaseCampRetryMin
	local ROUND_BASE_CAMP_RETRY_MAX = Pre.BaseCampRetryMax
	local createHuntEscape: any = assert(
		dependencies.CreateHuntEscape,
		"round phase requires CreateHuntEscape"
	)
	local waitForRoundHuntEnd = createHuntEscape({
		Workspace = Services.Workspace,
		State = doRoundState,
		GetGhost = getGhostModel,
		OperationActive = doRoundOperationActive,
		SetStatus = setDoRoundStatus,
		TeleportToBase = teleportToBaseCamp,
		TeleportOptions = roundTeleportOptions,
		PlayerInsideBase = playerIsInsideRoundBaseCamp,
		Wait = doRoundWait,
		RetryMin = ROUND_BASE_CAMP_RETRY_MIN,
		RetryMax = ROUND_BASE_CAMP_RETRY_MAX,
	})

	local createItemGhostRoom: any = assert(
		dependencies.CreateItemGhostRoom,
		"round phase requires CreateItemGhostRoom"
	)
	local itemGhostRoom: any = createItemGhostRoom({
		Services = Services,
		Player = player,
		Workspace = Services.Workspace,
		State = doRoundState,
		RoomItemPlacementState = roomItemPlacementState,
		DroppedRoomItems = DROPPED_ROOM_ITEMS,
		NormalizeItemName = normalizeRoundItemName,
		ItemName = roundItemName,
		ItemIsBurntCross = roundItemIsBurntCross,
		GetInventoryItem = getRoundInventoryItem,
		FindHotbarSlot = findRoundHotbarSlot,
		GetEquippedItem = getRoundEquippedItem,
		ApproachPositions = roundApproachPositions,
		WorldItemIsInsideRoom = roundWorldItemIsInsideRoom,
		IsHunting = roundIsHunting,
		IdentityIsCurrent = roundIdentityIsCurrent,
		ActionIsSafe = roundActionIsSafe,
		OperationActive = doRoundOperationActive,
		Wait = doRoundWait,
		BeginMutation = beginAutomationMutation,
		TeleportNearTarget = teleportNearRoundTarget,
		TeleportToRoom = teleportToRoomBoundingBoxCenter,
		TeleportToBaseCamp = teleportToBaseCamp,
		TeleportOptions = roundTeleportOptions,
		GetInstanceWorldPosition = getInstanceWorldPosition,
		PlaceItemsInFavouriteRoom = placeItemsInFavouriteRoom,
		GetGhostModel = getGhostModel,
		WaitForHuntEnd = waitForRoundHuntEnd,
		SetStatus = setDoRoundStatus,
		PickupMaxDistance = ROUND_PICKUP_MAX_DISTANCE,
		RemoteSafetyDelay = ROUND_REMOTE_SAFETY_DELAY,
	})
	local captureRoundRoomItems = itemGhostRoom.Capture
	local roundItemEnabledObject = itemGhostRoom.EnabledObject
	local restoreRoundItemToRoom = itemGhostRoom.Restore
	local performRoundRoomItemSetup = itemGhostRoom.PerformSetup
	local resetRoundRoomItemTracking = itemGhostRoom.Reset

	local createMaintainItem: any = assert(
		dependencies.CreateMaintainItem,
		"round phase requires CreateMaintainItem"
	)
	local maintainRoundRoomItems = createMaintainItem({
		Services = Services,
		Player = player,
		Workspace = Services.Workspace,
		State = doRoundState,
		DroppedItems = DROPPED_ROOM_ITEMS,
		PoweredItems = POWERED_ROOM_ITEMS,
		NormalizeItemName = normalizeRoundItemName,
		ItemIsBurntCross = roundItemIsBurntCross,
		ItemIsInsideRoom = roundWorldItemIsInsideRoom,
		ActionIsSafe = roundActionIsSafe,
		ApproachPositions = roundApproachPositions,
		TeleportNearTarget = teleportNearRoundTarget,
		TeleportToBaseCamp = teleportToBaseCamp,
		TeleportOptions = roundTeleportOptions,
		GetPosition = getInstanceWorldPosition,
		BeginMutation = beginAutomationMutation,
		Wait = doRoundWait,
		SetStatus = setDoRoundStatus,
		CaptureItems = captureRoundRoomItems,
		EnabledObjectFor = roundItemEnabledObject,
		RestoreItem = restoreRoundItemToRoom,
		OutsideGrace = ROUND_ITEM_OUTSIDE_GRACE,
		Interval = ROUND_MAINTENANCE_INTERVAL,
		RetryBackoff = ROUND_MAINTENANCE_RETRY_BACKOFF,
		RemoteDelay = ROUND_REMOTE_SAFETY_DELAY,
	})

	local setEnabled

	local function runDoRound(generation)
	local success, failure = xpcall(function()
		local phase = Pre.Run(generation, {
			CurrentIdentification = Post.CurrentIdentification,
			Complete = Post.Complete,
			WaitForHuntEnd = waitForRoundHuntEnd,
			PerformRoomItemSetup = performRoundRoomItemSetup,
			CaptureRoomItems = captureRoundRoomItems,
		})
		if not phase then
			return
		end
		local ghost = phase.Ghost
		local favouriteRoom = phase.FavouriteRoom

		waitForRoundHuntEnd(generation)
		teleportToFavouriteRoom(roundTeleportOptions(generation))
		doRoundState.questionsActive = true
		while doRoundOperationActive(generation) do
			ghost = getGhostModel()
			if workspace:FindFirstChild("Map") ~= doRoundState.roundMap then
				error("the round map changed", 0)
			end
			if not ghost then
				waitForRoundHuntEnd(generation)
				continue
			end
			if ghost ~= doRoundState.roundGhost then
				error("the round ghost changed", 0)
			end
			local rooms = findRoomsFolder()
			local currentFavourite = findFavouriteRoom(
				rooms,
				ghost:GetAttribute("FavoriteRoom")
			)
			if currentFavourite and currentFavourite ~= favouriteRoom then
				favouriteRoom = currentFavourite
				doRoundState.lastFavouriteRoom = favouriteRoom
				doRoundState.questionsActive = false
				resetRoundRoomItemTracking()
				setDoRoundStatus("Relocating room items")
				local relocated, relocationReason =
					performRoundRoomItemSetup(generation)
				if not relocated and presenter and presenter.Notify then
					presenter:Notify(
						relocationReason
							or "Room item relocation failed; continuing with available items"
					)
				end
				captureRoundRoomItems(favouriteRoom)
				doRoundState.itemsDirty = true
				doRoundState.nextMaintenanceAt = 0
				continue
			end
			if roundIsHunting() then
				doRoundState.questionsActive = false
				waitForRoundHuntEnd(generation)
				if favouriteRoom then
					teleportToRoomBoundingBoxCenter(
						favouriteRoom,
						roundTeleportOptions(generation)
					)
				end
				doRoundState.questionsActive = true
				continue
			end

			local character = player.Character
			doRoundState.questionsActive = true
			if favouriteRoom and character
				and not instanceIsInsideRoom(character, favouriteRoom) then
				setDoRoundStatus("Returning to ghost room")
				teleportToRoomBoundingBoxCenter(
					favouriteRoom,
					roundTeleportOptions(generation)
				)
			else
				setDoRoundStatus("Asking questions")
			end
			if favouriteRoom then
				maintainRoundRoomItems(favouriteRoom, generation)
			end
			doRoundWait(generation, 0.35)
		end
	end, debug.traceback)
	if not success and doRoundOperationActive(generation) then
		local message = tostring(failure):match("^[^\n]+") or "Do-Round failed"
		if presenter and presenter.Notify then
			presenter:Notify(message)
		end
		if Pre.ReturnToBase(generation) then
			setEnabled(false, "Stopped")
		end
	end
end

setEnabled = function(enabled, finalPhase)
	enabled = enabled == true
	if doRoundState.enabled == enabled then
		if not enabled then
			Post.CancelTask("timeoutThread")
			Post.CancelTask("identificationThread")
			Pre.ReleaseMovement()
		end
		if finalPhase then
			setDoRoundStatus(finalPhase)
		end
		return enabled
	end
	doRoundState.generation = doRoundState.generation + 1
	doRoundState.enabled = enabled
	if enabled then
		Post.CancelTask("timeoutThread")
		Post.CancelTask("identificationThread")
		perkTrackerState.journalForcedGhost = nil
		if presenter and presenter.SetGhostIdentificationLock then
			presenter:SetGhostIdentificationLock(nil)
		end
		for _, power in pairs(doRoundState.itemPower) do
			if power.Connection and power.Connection.Connected then
				power.Connection:Disconnect()
			end
		end
		for _, connection in ipairs(doRoundState.automationConnections or {}) do
			if connection.Connected then
				connection:Disconnect()
			end
		end
		doRoundState.startedAt = os.clock()
		doRoundState.exitOpenedAt = nil
		doRoundState.completionClaimed = false
		doRoundState.completionGhost = nil
		doRoundState.completionScore = nil
		doRoundState.completionCertain = nil
		doRoundState.lastElapsed = 0
		doRoundState.phase = "Checking ghost room"
		doRoundState.roundMap = nil
		doRoundState.roundGhost = nil
		doRoundState.usedDoorNames = {}
		doRoundState.usedSaltDoorModels = setmetatable({}, {__mode = "k"})
		doRoundState.usedSaltDoorNames = {}
		doRoundState.usedHolyOilDoorModels = setmetatable({}, {__mode = "k"})
		doRoundState.usedHolyOilDoorNames = {}
		doRoundState.reservedDoorModels = setmetatable({}, {__mode = "k"})
		doRoundState.reservedDoorNames = {}
		doRoundState.completedDoorTools = {}
		doRoundState.doorToolPlacements = {}
		doRoundState.doorToolUses = {}
		doRoundState.lastDoorName = nil
		doRoundState.roomItems = {}
		doRoundState.itemPower = setmetatable({}, {__mode = "k"})
		doRoundState.outsideSince = setmetatable({}, {__mode = "k"})
		doRoundState.maintenanceBackoff = setmetatable({}, {__mode = "k"})
		doRoundState.itemsDirty = true
		doRoundState.nextMaintenanceAt = 0
		doRoundState.automationConnections = {}
		local items = workspace:FindFirstChild("Items")
		if items then
			table.insert(
				doRoundState.automationConnections,
				items.ChildAdded:Connect(function()
					if doRoundState.enabled then
						doRoundState.itemsDirty = true
					end
				end)
			)
			table.insert(
				doRoundState.automationConnections,
				items.ChildRemoved:Connect(function()
					if doRoundState.enabled then
						doRoundState.itemsDirty = true
					end
				end)
			)
		end
		doRoundState.autoSpiritBoxLease = true
		doRoundState.questionsActive = false
		refreshAutoSpiritBoxEnabled()
		setDoRoundStatus(doRoundState.phase)
		local generation = doRoundState.generation
		Post.StartIdentificationWatchdog(generation)
		Post.StartTimeoutWatchdog(generation)
		doRoundState.thread = task.spawn(function()
			runDoRound(generation)
		end)
	else
		Post.CancelTask("timeoutThread")
		Post.CancelTask("identificationThread")
		if presenter and presenter.SetGhostIdentificationLock then
			presenter:SetGhostIdentificationLock(nil)
		end
		for _, power in pairs(doRoundState.itemPower) do
			if power.Connection and power.Connection.Connected then
				power.Connection:Disconnect()
			end
		end
		for _, connection in ipairs(doRoundState.automationConnections or {}) do
			if connection.Connected then
				connection:Disconnect()
			end
		end
		doRoundState.automationConnections = {}
		if doRoundState.startedAt then
			doRoundState.lastElapsed = math.max(
				0,
				os.clock() - doRoundState.startedAt
			)
		end
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
		Pre.ReleaseMovement()
		doRoundState.autoSpiritBoxLease = false
		doRoundState.questionsActive = false
		refreshAutoSpiritBoxEnabled()
		doRoundState.thread = nil
		doRoundState.completionClaimed = false
		doRoundState.completionGhost = nil
		doRoundState.completionScore = nil
		doRoundState.completionCertain = nil
		doRoundState.startedAt = nil
		doRoundState.exitOpenedAt = nil
		doRoundState.roundMap = nil
		doRoundState.roundGhost = nil
		setDoRoundStatus(finalPhase or "Off")
	end
	return doRoundState.enabled
end

Post:SetDisable(function(finalPhase)
	return setEnabled(false, finalPhase)
end)

return {
	SetEnabled = setEnabled,
}
end
