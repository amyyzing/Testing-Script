return function(package: any)
	local dependencies: any = assert(package.Dependencies, "round phase requires Dependencies")
	local Pre: any = assert(package.Pre, "round phase requires Pre")
	local Post: any = assert(package.Post, "round phase requires Post")
	local Services: any = assert(dependencies.Services, "round phase requires Services")
	local player: any = assert(dependencies.Player, "round phase requires Player")
	local runtimeIsActive: any = assert(dependencies.RuntimeIsActive, "round phase requires RuntimeIsActive")
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

local function captureRoundRoomItems(room)
	local items = workspace:FindFirstChild("Items")
	if not items or not room then
		return
	end
	local candidatesByName = {}
	for _, model in ipairs(items:GetChildren()) do
		if model:IsA("Model") and not roundItemIsBurntCross(model) then
			local attributeName = model:GetAttribute("ItemName")
			if typeof(attributeName) == "string" and attributeName ~= "" then
				local normalized = normalizeRoundItemName(attributeName)
				local candidates = candidatesByName[normalized]
				if not candidates then
					candidates = {}
					candidatesByName[normalized] = candidates
				end
				table.insert(candidates, model)
			end
		end
	end
	local now = os.clock()
	for _, itemName in ipairs(DROPPED_ROOM_ITEMS) do
		local normalized = normalizeRoundItemName(itemName)
		local existing = doRoundState.roomItems[normalized]
		if existing and roundWorldItemIsInsideRoom(existing, room) then
			continue
		end
		local inside
		local fallback
		for _, model in ipairs(candidatesByName[normalized] or {}) do
			if roundWorldItemIsInsideRoom(model, room) then
				inside = model
				break
			end
			local retryAt = doRoundState.maintenanceBackoff
				and doRoundState.maintenanceBackoff[model]
				or 0
			if not fallback and now >= retryAt then
				fallback = model
			end
		end
		local existingRetryAt = existing and doRoundState.maintenanceBackoff
			and doRoundState.maintenanceBackoff[existing]
			or 0
		local existingAvailable = existing and existing.Parent
			and not roundItemIsBurntCross(existing)
			and now >= existingRetryAt
		doRoundState.roomItems[normalized] = inside
			or (existingAvailable and existing)
			or fallback
			or getRoundEquippedItem(itemName)
			or getRoundInventoryItem(itemName)
	end
end

local function findRoundWorldItemInRoom(itemName, room)
	local items = workspace:FindFirstChild("Items")
	if not items then
		return nil
	end
	local normalized = normalizeRoundItemName(itemName)
	for _, model in ipairs(items:GetChildren()) do
		if model:IsA("Model")
			and normalizeRoundItemName(model:GetAttribute("ItemName"))
				== normalized
			and not roundItemIsBurntCross(model)
			and roundWorldItemIsInsideRoom(model, room) then
			return model
		end
	end
	return nil
end

local function roundItemEnabledObject(model)
	if not model then
		return nil
	end
	if model:GetAttribute("Enabled") ~= nil then
		return model
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:GetAttribute("Enabled") ~= nil then
			return descendant
		end
	end
	return nil
end

local function countRoundInventorySlots()
	local count = 0
	local seen = setmetatable({}, {__mode = "k"})
	for _, container in ipairs({
		player:FindFirstChild("ToolsHolder"),
		player.Character,
	}) do
		if container then
			for _, model in ipairs(container:GetChildren()) do
				if model:IsA("Model")
					and roundItemName(model) ~= nil
					and not seen[model] then
					seen[model] = true
					count = count + 1
				end
			end
		end
	end
	if count > 0 then
		return math.min(count, 3)
	end
	for slotNumber = 1, 3 do
		local value = player:GetAttribute("InvSlot" .. tostring(slotNumber))
		if value ~= nil and value ~= false and tostring(value) ~= "" then
			count = count + 1
		end
	end
	return count
end

local function restoreRoundItemToRoom(model, room, generation)
	if not model or not model.Parent or not room or roundItemIsBurntCross(model) then
		return false
	end
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local pickup = events and events:FindFirstChild("RequestItemPickup")
	local equip = events and events:FindFirstChild("RequestItemEquip")
	local drop = events and events:FindFirstChild("RequestItemDrop")
	if not pickup or not pickup:IsA("RemoteEvent")
		or not equip or not equip:IsA("RemoteEvent")
		or not drop or not drop:IsA("RemoteEvent") then
		return false
	end
	local itemName = roundItemName(model)
	if not itemName then
		return false
	end
	local itemsFolder = workspace:FindFirstChild("Items")
	local isWorldItem = itemsFolder and model:IsDescendantOf(itemsFolder)
	if isWorldItem and roundWorldItemIsInsideRoom(model, room) then
		return true
	end
	if not isWorldItem then
		model = getRoundEquippedItem(itemName)
			or getRoundInventoryItem(itemName)
			or model
		if not model.Parent or roundItemIsBurntCross(model) then
			return false
		end
		local heldSlot = findRoundHotbarSlot(itemName)
		if not heldSlot or not roundActionIsSafe(generation) then
			return false
		end
		local teleported = teleportToRoomBoundingBoxCenter(
			room,
			roundTeleportOptions(generation)
		)
		if not teleported or not roundActionIsSafe(generation) then
			return false
		end
		beginAutomationMutation(3)
		doRoundWait(generation, ROUND_REMOTE_SAFETY_DELAY)
		if not roundActionIsSafe(generation) then
			return false
		end
		pcall(equip.FireServer, equip, "InvSlot" .. tostring(heldSlot))
		doRoundWait(generation, 0.15)
		if not roundActionIsSafe(generation) then
			return false
		end
		doRoundWait(generation, ROUND_REMOTE_SAFETY_DELAY)
		if not roundActionIsSafe(generation) then
			return false
		end
		pcall(drop.FireServer, drop, "InvSlot" .. tostring(heldSlot))
		doRoundWait(generation, 0.35)
		beginAutomationMutation(3)
		return findRoundWorldItemInRoom(itemName, room) ~= nil
	end
	if countRoundInventorySlots() >= 3 then
		return false
	end
	local approaches = roundApproachPositions(model, 3.5)
	local movedNear = false
	for _, approach in ipairs(approaches) do
		if not roundActionIsSafe(generation) then
			return false
		end
		movedNear = teleportNearRoundTarget(model, approach, generation)
		if movedNear then
			break
		end
	end
	if not movedNear then
		return false
	end
	if not roundActionIsSafe(generation) then
		teleportToBaseCamp(roundTeleportOptions(generation))
		return false
	end
	local root = player.Character
		and player.Character:FindFirstChild("HumanoidRootPart")
	local itemPosition = getInstanceWorldPosition(model)
	if not root or not itemPosition
		or (root.Position - itemPosition).Magnitude > ROUND_PICKUP_MAX_DISTANCE then
		return false
	end
	beginAutomationMutation(4)
	doRoundWait(generation, ROUND_REMOTE_SAFETY_DELAY)
	if not roundActionIsSafe(generation) then
		return false
	end
	local picked = pcall(pickup.FireServer, pickup, model)
	if not picked then
		return false
	end
	local deadline = os.clock() + 1.8
	local slotNumber
	repeat
		if not roundActionIsSafe(generation) then
			teleportToBaseCamp(roundTeleportOptions(generation))
			return false
		end
		slotNumber = findRoundHotbarSlot(itemName)
		if slotNumber then
			break
		end
		doRoundWait(generation, 0.05)
	until os.clock() >= deadline
	if not slotNumber or not roundActionIsSafe(generation) then
		return false
	end
	local teleported = teleportToRoomBoundingBoxCenter(
		room,
		roundTeleportOptions(generation)
	)
	if not teleported or not roundActionIsSafe(generation) then
		return false
	end
	doRoundWait(generation, ROUND_REMOTE_SAFETY_DELAY)
	if not roundActionIsSafe(generation) then
		return false
	end
	pcall(equip.FireServer, equip, "InvSlot" .. tostring(slotNumber))
	doRoundWait(generation, 0.15)
	if not roundActionIsSafe(generation) then
		return false
	end
	doRoundWait(generation, ROUND_REMOTE_SAFETY_DELAY)
	if not roundActionIsSafe(generation) then
		return false
	end
	pcall(drop.FireServer, drop, "InvSlot" .. tostring(slotNumber))
	doRoundWait(generation, 0.35)
	beginAutomationMutation(3)
	return findRoundWorldItemInRoom(itemName, room) ~= nil
end

local function maintainRoundRoomItems(room, generation)
	local now = os.clock()
	if doRoundState.itemsDirty ~= true
		and now < (doRoundState.nextMaintenanceAt or 0) then
		return
	end
	doRoundState.itemsDirty = false
	doRoundState.nextMaintenanceAt = now + ROUND_MAINTENANCE_INTERVAL
	captureRoundRoomItems(room)
	for _, itemName in ipairs(DROPPED_ROOM_ITEMS) do
		local normalized = normalizeRoundItemName(itemName)
		local model = doRoundState.roomItems[normalized]
		if model and model.Parent then
			if roundItemIsBurntCross(model) then
				doRoundState.roomItems[normalized] = nil
				continue
			end
			local itemsFolder = workspace:FindFirstChild("Items")
			local worldItem = itemsFolder
				and model:IsDescendantOf(itemsFolder)
			local insideRoom = worldItem
				and roundWorldItemIsInsideRoom(model, room)
			if not insideRoom then
				doRoundState.outsideSince[model] =
					doRoundState.outsideSince[model] or now
				local retryAt = doRoundState.maintenanceBackoff[model] or 0
				if now - doRoundState.outsideSince[model]
						>= ROUND_ITEM_OUTSIDE_GRACE
					and now >= retryAt then
					setDoRoundStatus("Maintaining room items")
					if restoreRoundItemToRoom(model, room, generation) then
						doRoundState.outsideSince[model] = nil
						doRoundState.maintenanceBackoff[model] = nil
						doRoundState.itemsDirty = true
					else
						doRoundState.maintenanceBackoff[model] = now
							+ ROUND_MAINTENANCE_RETRY_BACKOFF
						doRoundState.outsideSince[model] = nil
						doRoundState.roomItems[normalized] = nil
						doRoundState.itemsDirty = true
					end
					return
				end
			else
				doRoundState.outsideSince[model] = nil
			end
			if insideRoom and POWERED_ROOM_ITEMS[normalized] then
				local enabledObject = roundItemEnabledObject(model)
				if enabledObject then
					local enabled = enabledObject:GetAttribute("Enabled") == true
					local power = doRoundState.itemPower[enabledObject]
					if not power then
						power = {
							Last = enabled,
							LastChangedAt = now,
							Transitions = {},
						}
						power.Connection = enabledObject
							:GetAttributeChangedSignal("Enabled")
							:Connect(function()
								if not doRoundState.enabled
									or not enabledObject.Parent then
									return
								end
								local changedAt = os.clock()
								local changed = enabledObject:GetAttribute("Enabled") == true
								if power.Last ~= changed then
									power.Last = changed
									power.LastChangedAt = changedAt
									table.insert(power.Transitions, changedAt)
									doRoundState.itemsDirty = true
								end
							end)
						doRoundState.itemPower[enabledObject] = power
					elseif power.Last ~= enabled then
						power.Last = enabled
						power.LastChangedAt = now
						table.insert(power.Transitions, now)
					end
					for index = #power.Transitions, 1, -1 do
						if now - power.Transitions[index] > 3 then
							table.remove(power.Transitions, index)
						end
					end
					local flickering = #power.Transitions >= 3
					if not enabled and not flickering
						and now - power.LastChangedAt >= 3
						and now >= (power.RetryAt or 0) then
						setDoRoundStatus("Maintaining room items")
						local approaches = roundApproachPositions(model, 4)
						for _, approach in ipairs(approaches) do
							if not roundActionIsSafe(generation) then
								return
							end
							local teleported = teleportNearRoundTarget(model, approach, generation)
							if teleported then
								if not roundActionIsSafe(generation) then
									teleportToBaseCamp(roundTeleportOptions(generation))
									return
								end
								local root = player.Character
									and player.Character:FindFirstChild(
										"HumanoidRootPart"
									)
								local itemPosition = getInstanceWorldPosition(model)
								if not root or not itemPosition
									or (root.Position - itemPosition).Magnitude > 10 then
									power.RetryAt = now
										+ ROUND_MAINTENANCE_RETRY_BACKOFF
									return
								end
								local events = Services.ReplicatedStorage:FindFirstChild("Events")
								local toggle = events and events:FindFirstChild("ToggleItemState")
								if toggle and toggle:IsA("RemoteEvent") then
									beginAutomationMutation(2.5)
									doRoundWait(
										generation,
										ROUND_REMOTE_SAFETY_DELAY
									)
									if not roundActionIsSafe(generation) then
										return
									end
									local fired = pcall(toggle.FireServer, toggle, model)
									if fired then
										power.LastChangedAt = now
										power.RetryAt = now + 2
									else
										power.RetryAt = now
											+ ROUND_MAINTENANCE_RETRY_BACKOFF
									end
								end
								break
							end
						end
						return
					end
				end
			end
		end
	end
end

local function waitForRoundHuntEnd(generation)
	local escaped = false
	local escapeFailures = 0
	local nextEscapeAttemptAt = 0
	while doRoundOperationActive(generation) do
		if workspace:FindFirstChild("Map") ~= doRoundState.roundMap then
			error("the round map changed", 0)
		end
		local currentGhost = getGhostModel()
		if currentGhost and currentGhost ~= doRoundState.roundGhost then
			error("the round ghost changed", 0)
		end
		if currentGhost and currentGhost:GetAttribute("Hunting") ~= true then
			break
		end
		doRoundState.questionsActive = false
		setDoRoundStatus(currentGhost and "Hunt escape" or "Waiting for ghost")
		if not escaped and os.clock() >= nextEscapeAttemptAt then
			local teleported = teleportToBaseCamp(
				roundTeleportOptions(generation)
			)
			-- Confirm the same Base Camp containment used by completion. A moved
			-- root whose room state has not settled yet must be retried.
			escaped = teleported == true and playerIsInsideRoundBaseCamp()
			if not escaped then
				escapeFailures = escapeFailures + 1
				nextEscapeAttemptAt = os.clock() + math.min(
					ROUND_BASE_CAMP_RETRY_MAX,
					ROUND_BASE_CAMP_RETRY_MIN
						* (2 ^ math.min(escapeFailures - 1, 3))
				)
			end
		end
		doRoundWait(generation, 0.15)
	end
	if escaped then
		doRoundWait(generation, 0.65)
	end
	return escaped
end

local function performRoundRoomItemSetup(generation)
	while roomItemPlacementState.busy
		and doRoundOperationActive(generation) do
		setDoRoundStatus("Waiting for room item setup")
		doRoundWait(generation, 0.15)
	end
	if not doRoundOperationActive(generation) then
		return false, "Do-Round cancelled"
	end
	local started, placementGeneration = placeItemsInFavouriteRoom("DoRound")
	if not started then
		return false, tostring(placementGeneration)
	end
	repeat
		if roundIsHunting() then
			setDoRoundStatus("Waiting for hunt")
			waitForRoundHuntEnd(generation)
		else
			setDoRoundStatus("Placing room items")
		end
		doRoundWait(generation, 0.15)
		local currentGhost = getGhostModel()
		if not roundIdentityIsCurrent()
			or (currentGhost and currentGhost ~= doRoundState.roundGhost) then
			error("the round changed during room item setup", 0)
		end
	until roomItemPlacementState.lastCompletedGeneration >= placementGeneration
	return roomItemPlacementState.lastResult ~= false,
		roomItemPlacementState.lastError
end

local function resetRoundRoomItemTracking()
	for _, power in pairs(doRoundState.itemPower or {}) do
		if power.Connection and power.Connection.Connected then
			power.Connection:Disconnect()
		end
	end
	doRoundState.roomItems = {}
	doRoundState.itemPower = setmetatable({}, {__mode = "k"})
	doRoundState.outsideSince = setmetatable({}, {__mode = "k"})
	doRoundState.maintenanceBackoff = setmetatable({}, {__mode = "k"})
	doRoundState.itemsDirty = true
	doRoundState.nextMaintenanceAt = 0
end

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
