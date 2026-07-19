return function(dependencies: any)
	local Services: any = assert(dependencies.Services, "item-ghost-room requires Services")
	local player: any = assert(dependencies.Player, "item-ghost-room requires Player")
	local workspace: any = assert(dependencies.Workspace, "item-ghost-room requires Workspace")
	local doRoundState: any = assert(dependencies.State, "item-ghost-room requires State")
	local roomItemPlacementState: any = assert(dependencies.RoomItemPlacementState, "item-ghost-room requires RoomItemPlacementState")
	local DROPPED_ROOM_ITEMS: any = assert(dependencies.DroppedRoomItems, "item-ghost-room requires DroppedRoomItems")
	local normalizeRoundItemName: any = assert(dependencies.NormalizeItemName, "item-ghost-room requires NormalizeItemName")
	local roundItemName: any = assert(dependencies.ItemName, "item-ghost-room requires ItemName")
	local roundItemIsBurntCross: any = assert(dependencies.ItemIsBurntCross, "item-ghost-room requires ItemIsBurntCross")
	local getRoundInventoryItem: any = assert(dependencies.GetInventoryItem, "item-ghost-room requires GetInventoryItem")
	local findRoundHotbarSlot: any = assert(dependencies.FindHotbarSlot, "item-ghost-room requires FindHotbarSlot")
	local getRoundEquippedItem: any = assert(dependencies.GetEquippedItem, "item-ghost-room requires GetEquippedItem")
	local roundApproachPositions: any = assert(dependencies.ApproachPositions, "item-ghost-room requires ApproachPositions")
	local roundWorldItemIsInsideRoom: any = assert(dependencies.WorldItemIsInsideRoom, "item-ghost-room requires WorldItemIsInsideRoom")
	local roundIsHunting: any = assert(dependencies.IsHunting, "item-ghost-room requires IsHunting")
	local roundIdentityIsCurrent: any = assert(dependencies.IdentityIsCurrent, "item-ghost-room requires IdentityIsCurrent")
	local roundActionIsSafe: any = assert(dependencies.ActionIsSafe, "item-ghost-room requires ActionIsSafe")
	local doRoundOperationActive: any = assert(dependencies.OperationActive, "item-ghost-room requires OperationActive")
	local doRoundWait: any = assert(dependencies.Wait, "item-ghost-room requires Wait")
	local beginAutomationMutation: any = assert(dependencies.BeginMutation, "item-ghost-room requires BeginMutation")
	local teleportNearRoundTarget: any = assert(dependencies.TeleportNearTarget, "item-ghost-room requires TeleportNearTarget")
	local teleportToRoomBoundingBoxCenter: any = assert(dependencies.TeleportToRoom, "item-ghost-room requires TeleportToRoom")
	local teleportToBaseCamp: any = assert(dependencies.TeleportToBaseCamp, "item-ghost-room requires TeleportToBaseCamp")
	local roundTeleportOptions: any = assert(dependencies.TeleportOptions, "item-ghost-room requires TeleportOptions")
	local getInstanceWorldPosition: any = assert(dependencies.GetInstanceWorldPosition, "item-ghost-room requires GetInstanceWorldPosition")
	local placeItemsInFavouriteRoom: any = assert(dependencies.PlaceItemsInFavouriteRoom, "item-ghost-room requires PlaceItemsInFavouriteRoom")
	local getGhostModel: any = assert(dependencies.GetGhostModel, "item-ghost-room requires GetGhostModel")
	local waitForRoundHuntEnd: any = assert(dependencies.WaitForHuntEnd, "item-ghost-room requires WaitForHuntEnd")
	local setDoRoundStatus: any = assert(dependencies.SetStatus, "item-ghost-room requires SetStatus")
	local ROUND_PICKUP_MAX_DISTANCE = tonumber(dependencies.PickupMaxDistance) or 8
	local ROUND_REMOTE_SAFETY_DELAY = tonumber(dependencies.RemoteSafetyDelay) or 0.1

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

return {
	Capture = captureRoundRoomItems,
	FindWorldItem = findRoundWorldItemInRoom,
	EnabledObject = roundItemEnabledObject,
	Restore = restoreRoundItemToRoom,
	PerformSetup = performRoundRoomItemSetup,
	Reset = resetRoundRoomItemTracking,
}
end
