return function(dependencies)
	local Services = assert(dependencies.Services, "room-item-setup requires Services")
	local player = assert(dependencies.Player, "room-item-setup requires Player")
	local runtimeIsActive = assert(dependencies.RuntimeIsActive, "room-item-setup requires RuntimeIsActive")
	local getGhostModel = assert(dependencies.GetGhostModel, "room-item-setup requires GetGhostModel")
	local findRoomsFolder = assert(dependencies.FindRoomsFolder, "room-item-setup requires FindRoomsFolder")
	local findFavouriteRoom = assert(dependencies.FindFavouriteRoom, "room-item-setup requires FindFavouriteRoom")
	local getRoomBoundingParts = assert(dependencies.GetRoomBoundingParts, "room-item-setup requires GetRoomBoundingParts")
	local instanceIsInsideRoom = assert(dependencies.InstanceIsInsideRoom, "room-item-setup requires InstanceIsInsideRoom")
	local roomItemPlacementState = assert(dependencies.State, "room-item-setup requires State")
	local perkTrackerState = assert(dependencies.PerkTrackerState, "room-item-setup requires PerkTrackerState")
	local closed = false
	local placeRoomItemsButton = dependencies.Button or {Text = "", BackgroundColor3 = nil}
	local COPY = dependencies.Copy or {
		Actions = {PlacingRoomItems = "Placing room items", WaitingForHunt = "Waiting for hunt"},
		Controls = {PlaceRoomItems = "Place Room Items"},
	}
	local COLORS = dependencies.Colors or {accentDark = nil, cardHover = nil}

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
			assertOperationActive()
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
			assertOperationActive()
			character:PivotTo(
				itemCFrame * CFrame.new(0, 3.5, 0)
			)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			Services.RunService.Heartbeat:Wait()
			if operationIsActive() then
				root.Anchored = originalAnchored
				humanoid.PlatformStand = originalPlatformStand
				humanoid.AutoRotate = originalAutoRotate
			else
				root.Anchored = false
				humanoid.PlatformStand = false
				humanoid.AutoRotate = true
				return false
			end
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


	return perkTrackerState.placeItemsInFavouriteRoom
end
