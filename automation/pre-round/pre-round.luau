return function(dependencies: any)
	local Services: any = assert(dependencies.Services, "round-automation requires Services")
	local player: any = assert(dependencies.Player, "round-automation requires Player")
	local runtimeIsActive: any = assert(dependencies.RuntimeIsActive, "round-automation requires RuntimeIsActive")
	local getGhostModel: any = assert(dependencies.GetGhostModel, "round-automation requires GetGhostModel")
	local findRoomsFolder: any = assert(dependencies.FindRoomsFolder, "round-automation requires FindRoomsFolder")
	local findFavouriteRoom: any = assert(dependencies.FindFavouriteRoom, "round-automation requires FindFavouriteRoom")
	local getInstanceWorldPosition: any = assert(dependencies.GetInstanceWorldPosition, "round-automation requires GetInstanceWorldPosition")
	local getRoomBoundingParts: any = assert(dependencies.GetRoomBoundingParts, "round-automation requires GetRoomBoundingParts")
	local pointIsInsidePart: any = assert(dependencies.PointIsInsidePart, "round-automation requires PointIsInsidePart")
	local teleportToRoomBoundingBoxCenter: any = assert(dependencies.TeleportToRoom, "round-automation requires TeleportToRoom")
	local teleportToBaseCamp: any = assert(dependencies.TeleportToBaseCamp, "round-automation requires TeleportToBaseCamp")
	local teleportToFavouriteRoom: any = assert(dependencies.TeleportToFavouriteRoom, "round-automation requires TeleportToFavouriteRoom")
	local placeItemsInFavouriteRoom: any = assert(dependencies.PlaceItemsInFavouriteRoom, "round-automation requires PlaceItemsInFavouriteRoom")
	local instanceIsInsideRoom: any = assert(dependencies.InstanceIsInsideRoom, "round-automation requires InstanceIsInsideRoom")
	local doRoundState: any = assert(dependencies.State, "round-automation requires State")
	local perkTrackerState: any = assert(dependencies.PerkTrackerState, "round-automation requires PerkTrackerState")
	local roomItemPlacementState: any = assert(dependencies.RoomItemPlacementState, "round-automation requires RoomItemPlacementState")
	local perkDetections: any = assert(dependencies.PerkDetections, "round-automation requires PerkDetections")
	local GHOST_PROFILES: any = assert(dependencies.GhostProfiles, "round-automation requires GhostProfiles")
	local GhostModule: any = assert(dependencies.GhostModule, "round-automation requires GhostModule")
	local presenter: any = dependencies.Presenter
	local placeRoomItemsButton: any = assert(dependencies.PlaceRoomItemsButton, "round-automation requires PlaceRoomItemsButton")
	local COPY: any = assert(dependencies.Copy, "round-automation requires Copy")
	local COLORS: any = assert(dependencies.Colors, "round-automation requires Colors")
	local refreshAutoSpiritBoxEnabled: any = assert(dependencies.RefreshAutoSpiritBoxEnabled, "round-automation requires RefreshAutoSpiritBoxEnabled")
	local setDoRoundStatus: any = assert(dependencies.SetDoRoundStatus, "round-automation requires SetDoRoundStatus")
	local setGhostIdentificationLabel: any = assert(dependencies.SetGhostIdentificationLabel, "round-automation requires SetGhostIdentificationLabel")
	local releasePlayerMovement: any = assert(dependencies.ReleasePlayerMovement, "round-automation requires ReleasePlayerMovement")
	local requestItemUnequip: any = assert(dependencies.RequestItemUnequip, "round-automation requires RequestItemUnequip")
	local publishRoundStarted: any = dependencies.MarkRoundStarted
	local prepareTeleport: any = dependencies.PrepareTeleport
	if type(prepareTeleport) ~= "function" then
		prepareTeleport = function()
			return true
		end
	end
local createRoundUtilities: any = assert(
	dependencies.CreateRoundUtilities,
	"round-automation requires CreateRoundUtilities"
)
local roundUtilities: any = createRoundUtilities(dependencies)
	local DROPPED_ROOM_ITEMS = roundUtilities.DroppedRoomItems
	local POWERED_ROOM_ITEMS = roundUtilities.PoweredRoomItems
	local ROUND_HELD_ITEMS = roundUtilities.HeldItems
	local normalizeRoundItemName = roundUtilities.NormalizeItemName
	local roundItemName = roundUtilities.ItemName
	local roundItemIsBurntCross = roundUtilities.ItemIsBurntCross
	local getRoundInventoryItem = roundUtilities.GetInventoryItem
	local findRoundHotbarSlot = roundUtilities.FindHotbarSlot
	local getRoundEquippedItem = roundUtilities.GetEquippedItem
	local equipRoundItem = roundUtilities.EquipItem
	local roundApproachPositions = roundUtilities.ApproachPositions
	local roundDoorReference = roundUtilities.ResolveDoorReference
	local roundDoorGeometry = roundUtilities.DoorGeometry
	local roundDoorApproaches = roundUtilities.DoorApproaches
	local roundDoorClosedState = roundUtilities.DoorIsClosed
	local prepareRoundDoorForPlacement = roundUtilities.PrepareDoor
	local teleportNearRoundTarget = roundUtilities.TeleportNearTarget
	local teleportToRoundDoorFace = roundUtilities.TeleportToDoorFace
	local facePlayerTowardRoundDoor = roundUtilities.FacePlayerToDoor
	local shuffleRoundList = roundUtilities.Shuffle
	local roundIsHunting = roundUtilities.IsHunting
	local roundIdentityIsCurrent = roundUtilities.IdentityIsCurrent
	local roundActionIsSafe = roundUtilities.ActionIsSafe
	local roundUnsafeReason = roundUtilities.UnsafeReason
	local doRoundOperationActive = roundUtilities.OperationActive
	local doRoundWait = roundUtilities.Wait
	local settleRoundDoorInteraction = roundUtilities.SettleDoorInteraction
	local beginAutomationMutation = roundUtilities.BeginMutation
	local waitForRoundPlacementXZDistance =
		roundUtilities.PlacementXZDistance
	local repairRoundHeldPreview = roundUtilities.RepairHeldPreview
	local fireRoundPlaceable = roundUtilities.FirePlaceable
	local roundWorldItemIsInsideRoom = roundUtilities.WorldItemIsInsideRoom
	local ROUND_PICKUP_MAX_DISTANCE = roundUtilities.PickupMaxDistance
	local ROUND_REMOTE_SAFETY_DELAY = roundUtilities.RemoteSafetyDelay
	local ROUND_DOOR_ATTEMPT_LIMIT = roundUtilities.DoorAttemptLimit
	local ROUND_LOBBY_RETRY_SECONDS = roundUtilities.LobbyRetrySeconds
	local ROUND_MINIMUM_LEAVE_AGE = roundUtilities.MinimumLeaveAge
	local ROUND_BASE_CAMP_SETTLE_SECONDS = roundUtilities.BaseCampSettleSeconds
	local ROUND_JOURNAL_SETTLE_SECONDS = roundUtilities.JournalSettleSeconds
	local ROUND_SALT_PLACEMENT_LIMIT = roundUtilities.SaltPlacementLimit
	local ROUND_HOLY_OIL_PLACEMENT_LIMIT = roundUtilities.HolyOilPlacementLimit
	local ROUND_ITEM_OUTSIDE_GRACE = roundUtilities.ItemOutsideGrace
	local ROUND_MAINTENANCE_INTERVAL = roundUtilities.MaintenanceInterval
	local ROUND_MAINTENANCE_RETRY_BACKOFF =
		roundUtilities.MaintenanceRetryBackoff
	local ROUND_MISSING_TOOL_RETRY_LIMIT =
		roundUtilities.MissingToolRetryLimit
	local ROUND_MISSING_USES_RETRY_LIMIT =
		roundUtilities.MissingUsesRetryLimit
	local ROUND_DOOR_RETRY_PASS_LIMIT =
		roundUtilities.DoorRetryPassLimit
	local ROUND_BASE_CAMP_RETRY_MIN = roundUtilities.BaseCampRetryMin
	local ROUND_BASE_CAMP_RETRY_MAX = roundUtilities.BaseCampRetryMax
	local function roundTeleportOptions(generation)
		return {
			ReleaseMovementOnCancel = true,
			ForcePreferredPosition = true,
			IsActive = function()
				return doRoundOperationActive(generation)
			end,
		}
	end
	local function roundBaseCampRoom()
		local rooms = findRoomsFolder()
		if not rooms then
			return nil
		end
		return rooms:FindFirstChild("Base Camp")
			or rooms:FindFirstChild("BaseCamp")
			or findFavouriteRoom(rooms, "Base Camp")
	end
	local function roundPlayerRoot()
		local character = player.Character
		local root = character
			and character:FindFirstChild("HumanoidRootPart")
		return root and root:IsA("BasePart") and root or nil
	end
	local function playerIsInsideRoundBaseCamp()
		local room = roundBaseCampRoom()
		local root = roundPlayerRoot()
		return room ~= nil
			and root ~= nil
			and instanceIsInsideRoom(root, room)
	end
	local function waitForRoundBaseCampSettle(generation)
		releasePlayerMovement(true)
		local stableRoot
		local stableSince
		while doRoundOperationActive(generation) do
			local root = roundPlayerRoot()
			local humanoid = player.Character
				and player.Character:FindFirstChildOfClass("Humanoid")
			local stable = root ~= nil
				and humanoid ~= nil
				and humanoid.Health > 0
				and root.Anchored == false
				and playerIsInsideRoundBaseCamp()
			if stable then
				if stableRoot ~= root then
					stableRoot = root
					stableSince = os.clock()
				elseif os.clock() - (stableSince or os.clock())
					>= ROUND_BASE_CAMP_SETTLE_SECONDS then
					return true
				end
			else
				stableRoot = nil
				stableSince = nil
			end
			Services.RunService.Heartbeat:Wait()
		end
		return false
	end
	local function returnRoundToBase(generation)
		local failedAttempts = 0
		while doRoundOperationActive(generation) do
			setDoRoundStatus("Returning to Base Camp")
			local teleported = teleportToBaseCamp(
				roundTeleportOptions(generation)
			)
			if teleported then
				Services.RunService.Heartbeat:Wait()
			end
			if teleported and playerIsInsideRoundBaseCamp()
				and waitForRoundBaseCampSettle(generation) then
				return true
			end
			failedAttempts = failedAttempts + 1
			local retryDelay = math.min(
				ROUND_BASE_CAMP_RETRY_MAX,
				ROUND_BASE_CAMP_RETRY_MIN * (2 ^ math.min(failedAttempts - 1, 3))
			)
			doRoundWait(generation, retryDelay)
		end
		return false
	end

local function normalizeRoundObjectName(value)
	return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function resolveRoundExitDoorModels()
	local folder = workspace:FindFirstChild("Doors")
	local exitSet = setmetatable({}, {__mode = "k"})
	local exits = {}
	if not folder then
		return exits, exitSet
	end
	local function directDoorContainer(object)
		local current = object
		while current and current.Parent ~= folder do
			current = current.Parent
		end
		return current and current.Parent == folder and current or nil
	end
	local function mark(object)
		local container = directDoorContainer(object)
		if container and not exitSet[container] then
			exitSet[container] = true
			table.insert(exits, container)
		end
	end
	-- This is the game's canonical path. Mark it first and do not require it
	-- to be a Model; some map revisions wrap Door in a Folder-like container.
	mark(folder:FindFirstChild("ExitDoor"))
	for _, object in ipairs(folder:GetDescendants()) do
		local normalized = normalizeRoundObjectName(object.Name)
		local doorType = normalizeRoundObjectName(
			object:GetAttribute("DoorType") or object:GetAttribute("Type")
		)
		if normalized == "exitdoor"
			or string.find(normalized, "exitdoor", 1, true) ~= nil
			or object:GetAttribute("IsExitDoor") == true
			or object:GetAttribute("ExitDoor") == true
			or doorType == "exit"
			or doorType == "exitdoor" then
			mark(object)
		end
	end
	for _, container in ipairs(folder:GetChildren()) do
		if container:IsA("Model") or container:IsA("Folder") then
			local normalized = normalizeRoundObjectName(container.Name)
			if string.find(normalized, "exitdoor", 1, true) ~= nil then
				mark(container)
			end
		end
	end
	return exits, exitSet
end

local eligibleRoundDoors: any = function(includeExit)
	local folder = workspace:FindFirstChild("Doors")
	local doors: any = {}
	if not folder then
		return doors
	end
	local exitDoors, exitSet = resolveRoundExitDoorModels()
	if includeExit then
		return exitDoors
	end
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model")
			and not exitSet[model]
			and (model:FindFirstChild("Door")
				or roundDoorReference(model)) then
			table.insert(doors, model)
		end
	end
	return shuffleRoundList(doors)
end

local function roundDoorDistanceToRoom(doorModel, room)
	local doorContainer = doorModel:FindFirstChild("Door") or doorModel
	local doorReference = roundDoorReference(doorContainer) or doorContainer
	local geometry = roundDoorGeometry(doorReference)
	local doorPosition = geometry and geometry.Center
		or getInstanceWorldPosition(doorReference)
	if not doorPosition then
		return math.huge
	end
	local bestDistance = math.huge
	for _, bounds in ipairs(getRoomBoundingParts(room)) do
		if bounds:IsA("BasePart") then
			local localPoint = bounds.CFrame:PointToObjectSpace(doorPosition)
			local xOutside = math.max(
				math.abs(localPoint.X) - bounds.Size.X * 0.5,
				0
			)
			local zOutside = math.max(
				math.abs(localPoint.Z) - bounds.Size.Z * 0.5,
				0
			)
			bestDistance = math.min(
				bestDistance,
				Vector2.new(xOutside, zOutside).Magnitude
			)
		end
	end
	if bestDistance < math.huge then
		return bestDistance
	end
	local roomPosition = getInstanceWorldPosition(room)
	if roomPosition then
		local offset = doorPosition - roomPosition
		return Vector2.new(offset.X, offset.Z).Magnitude
	end
	return math.huge
end

local function acquireRoundHeldTool(itemName, generation)
	if getRoundEquippedItem(itemName)
		or getRoundInventoryItem(itemName)
		or findRoundHotbarSlot(itemName) then
		return true
	end
	local itemsFolder = workspace:FindFirstChild("Items")
	if not itemsFolder then
		return false, "Workspace.Items was unavailable"
	end
	local normalized = normalizeRoundItemName(itemName)
	local candidates = {}
	for _, model in ipairs(itemsFolder:GetChildren()) do
		if model:IsA("Model")
			and normalizeRoundItemName(roundItemName(model)) == normalized
			and tonumber(model:GetAttribute("Uses")) ~= 0 then
			table.insert(candidates, model)
		end
	end
	if #candidates == 0 then
		return false, itemName .. " was not found in Workspace.Items"
	end
	local root = player.Character
		and player.Character:FindFirstChild("HumanoidRootPart")
	table.sort(candidates, function(first, second)
		local firstPosition = getInstanceWorldPosition(first)
		local secondPosition = getInstanceWorldPosition(second)
		local origin = root and root.Position or Vector3.zero
		local firstDistance = firstPosition
			and (firstPosition - origin).Magnitude
			or math.huge
		local secondDistance = secondPosition
			and (secondPosition - origin).Magnitude
			or math.huge
		return firstDistance < secondDistance
	end)
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local pickup = events and events:FindFirstChild("RequestItemPickup")
	if not pickup or not pickup:IsA("RemoteEvent") then
		return false, "RequestItemPickup RemoteEvent was not found"
	end
	local lastReason = itemName .. " could not be approached for pickup"
	for _, model in ipairs(candidates) do
		if not roundActionIsSafe(generation) then
			return false, roundUnsafeReason(generation)
		end
		for _, approach in ipairs(roundApproachPositions(model, 3.5)) do
			if not roundActionIsSafe(generation) then
				return false, roundUnsafeReason(generation)
			end
			if teleportNearRoundTarget(model, approach, generation) then
				root = player.Character
					and player.Character:FindFirstChild("HumanoidRootPart")
				local itemPosition = getInstanceWorldPosition(model)
				if root and itemPosition
					and (root.Position - itemPosition).Magnitude
						<= ROUND_PICKUP_MAX_DISTANCE then
					beginAutomationMutation(4)
					doRoundWait(generation, ROUND_REMOTE_SAFETY_DELAY)
					if not roundActionIsSafe(generation) then
						return false, roundUnsafeReason(generation)
					end
					if pcall(pickup.FireServer, pickup, model) then
						local deadline = os.clock() + 2
						repeat
							if getRoundEquippedItem(itemName)
								or getRoundInventoryItem(itemName)
								or findRoundHotbarSlot(itemName) then
								return true
							end
							doRoundWait(generation, 0.05)
						until os.clock() >= deadline
						lastReason = itemName .. " pickup was not confirmed"
					else
						lastReason = "RequestItemPickup failed for " .. itemName
					end
					break
				end
			end
		end
	end
	return false, lastReason
end

local function placeRoundToolAtDoors(toolName, generation, session)
	session = session or {}
	session.RejectedDoors = session.RejectedDoors
		or setmetatable({}, {__mode = "k"})
	session.DoorInstanceIds = session.DoorInstanceIds
		or setmetatable({}, {__mode = "k"})
	local rejectedDoors = session.RejectedDoors
	local doorInstanceIds = session.DoorInstanceIds
	local equipFailures = {}
	local missingToolFailures = {}
	local missingUsesFailures = {}
	local doorRetryPasses = {}
	local currentDoors = {}
	local currentDoorFailures = {}
	local warnings = {}
	local warningKeys = {}
	local function doorInstanceKey(doorModel)
		local id = doorInstanceIds[doorModel]
		if not id then
			session.NextDoorInstanceId = (session.NextDoorInstanceId or 0) + 1
			id = session.NextDoorInstanceId
			doorInstanceIds[doorModel] = id
		end
		return normalizeRoundObjectName(doorModel.Name) .. ":" .. tostring(id)
	end
	local function addWarning(key, message)
		if message and not warningKeys[key] then
			warningKeys[key] = true
			table.insert(warnings, message)
		end
	end
	local function selectDoor(toolKey)
		local current = currentDoors[toolKey]
		if current and current.Door and current.Door.Parent
			and not doRoundState.reservedDoorModels[current.Door]
			and not doRoundState.usedSaltDoorModels[current.Door]
			and (toolKey ~= "holy oil"
				or not doRoundState.usedHolyOilDoorModels[current.Door]) then
			return current.Door, current.Key, current.InstanceKey
		end
		currentDoors[toolKey] = nil
		currentDoorFailures[toolKey] = nil
		local doors = eligibleRoundDoors(false)
		table.sort(doors, function(first, second)
			local firstDistance = roundDoorDistanceToRoom(
				first,
				doRoundState.lastFavouriteRoom
			)
			local secondDistance = roundDoorDistanceToRoom(
				second,
				doRoundState.lastFavouriteRoom
			)
			if firstDistance == secondDistance then
				return normalizeRoundObjectName(first.Name)
					< normalizeRoundObjectName(second.Name)
			end
			return firstDistance < secondDistance
		end)
		-- Prefer a door whose name has not been used yet. Some maps contain
		-- several distinct doors all named "Door"; the second pass deliberately
		-- relaxes only the name check while retaining every instance check.
		for requireUnusedName = 1, 0, -1 do
			for _, doorModel in ipairs(doors) do
				local key = normalizeRoundObjectName(doorModel.Name)
				local instanceEligible = not rejectedDoors[doorModel]
					and not doRoundState.reservedDoorModels[doorModel]
					and not doRoundState.usedSaltDoorModels[doorModel]
					and (toolKey ~= "holy oil"
						or not doRoundState.usedHolyOilDoorModels[doorModel])
				local nameEligible = requireUnusedName == 0
					or (not doRoundState.reservedDoorNames[key]
						and not doRoundState.usedSaltDoorNames[key]
						and (toolKey ~= "holy oil"
							or not doRoundState.usedHolyOilDoorNames[key]))
				if instanceEligible and nameEligible then
					local instanceKey = doorInstanceKey(doorModel)
					currentDoors[toolKey] = {
						Door = doorModel,
						Key = key,
						InstanceKey = instanceKey,
					}
					currentDoorFailures[toolKey] = 0
					return doorModel, key, instanceKey
				end
			end
		end
		return nil, nil, nil
	end
	local function rejectOrRetryCurrentDoor(toolKey, doorModel, attemptLimit)
		attemptLimit = tonumber(attemptLimit) or ROUND_DOOR_ATTEMPT_LIMIT
		local failures = (currentDoorFailures[toolKey] or 0) + 1
		currentDoorFailures[toolKey] = failures
		if doorModel and doorModel.Parent and failures < attemptLimit then
			setDoRoundStatus(
				"Retrying current door ("
					.. tostring(failures + 1)
					.. "/"
					.. tostring(attemptLimit)
					.. ")"
			)
			return true
		end
		if doorModel then
			rejectedDoors[doorModel] = true
		end
		currentDoors[toolKey] = nil
		currentDoorFailures[toolKey] = nil
		return false
	end
	local function finishCurrentDoor(toolKey)
		currentDoors[toolKey] = nil
		currentDoorFailures[toolKey] = nil
	end

	do
		local toolKey = normalizeRoundItemName(toolName)
		local placementLimit = toolKey == "salt canister"
			and ROUND_SALT_PLACEMENT_LIMIT
			or ROUND_HOLY_OIL_PLACEMENT_LIMIT
		while doRoundOperationActive(generation)
			and not doRoundState.completedDoorTools[toolKey]
			and (doRoundState.doorToolPlacements[toolKey] or 0)
				< placementLimit do
			if not roundActionIsSafe(generation) then
				return false, roundUnsafeReason(generation)
			end
			local equipped, reason = equipRoundItem(toolName, 1.5, generation)
			if not equipped then
				if reason == "hunt started"
					or reason == "ghost unavailable"
					or reason == "Do-Round cancelled" then
					return false, reason
				end
				local cachedUses = doRoundState.doorToolUses[toolKey]
				if cachedUses ~= nil and cachedUses <= 0 then
					doRoundState.completedDoorTools[toolKey] = true
					break
				end
				local stored = getRoundEquippedItem(toolName)
					or getRoundInventoryItem(toolName)
				local slot = findRoundHotbarSlot(toolName)
				if not stored and not slot then
					local acquired, acquireReason =
						acquireRoundHeldTool(toolName, generation)
					if acquired then
						equipFailures[toolKey] = 0
						continue
					end
					if acquireReason == "hunt started"
						or acquireReason == "ghost unavailable"
						or acquireReason == "Do-Round cancelled" then
						return false, acquireReason
					end
					missingToolFailures[toolKey] =
						(missingToolFailures[toolKey] or 0) + 1
					addWarning(
						toolKey .. ":missing",
						acquireReason or reason
					)
					if missingToolFailures[toolKey]
						>= ROUND_MISSING_TOOL_RETRY_LIMIT then
						doRoundState.completedDoorTools[toolKey] = true
						addWarning(
							toolKey .. ":missing-final",
							toolName
								.. " was unavailable after "
								.. tostring(ROUND_MISSING_TOOL_RETRY_LIMIT)
								.. " checks; continuing without it"
						)
						break
					end
					setDoRoundStatus("Waiting for " .. toolName)
					doRoundWait(generation, 0.75)
					continue
				end
				equipFailures[toolKey] = (equipFailures[toolKey] or 0) + 1
				if equipFailures[toolKey] >= 4 then
					return false,
						toolName
							.. " remained present but could not be equipped after four retries: "
							.. tostring(reason)
				end
				doRoundWait(generation, 0.25 * equipFailures[toolKey])
				continue
			end
			equipFailures[toolKey] = 0
			missingToolFailures[toolKey] = 0
			local uses = tonumber(equipped:GetAttribute("Uses"))
			if uses == nil then
				local usesDeadline = os.clock() + 1
				repeat
					if not roundActionIsSafe(generation) then
						return false, roundUnsafeReason(generation)
					end
					doRoundWait(generation, 0.05)
					local current = getRoundEquippedItem(toolName) or equipped
					uses = tonumber(current:GetAttribute("Uses"))
				until uses ~= nil or os.clock() >= usesDeadline
			end
			if uses == nil then
				missingUsesFailures[toolKey] =
					(missingUsesFailures[toolKey] or 0) + 1
				addWarning(
					toolKey .. ":uses",
					toolName .. " Uses attribute was unavailable"
				)
				if missingUsesFailures[toolKey]
					>= ROUND_MISSING_USES_RETRY_LIMIT then
					doRoundState.completedDoorTools[toolKey] = true
					addWarning(
						toolKey .. ":uses-final",
						toolName
							.. " never published Uses; continuing without door placement"
					)
					break
				end
				setDoRoundStatus("Waiting for " .. toolName .. " Uses")
				doRoundWait(generation, 0.5)
				continue
			end
			missingUsesFailures[toolKey] = 0
			doRoundState.doorToolUses[toolKey] = uses
			if uses <= 0 then
				finishCurrentDoor(toolKey)
				doRoundState.completedDoorTools[toolKey] = true
				break
			end
			local selectedDoor, selectedKey, selectedInstanceKey = selectDoor(toolKey)
			if not selectedDoor then
				doorRetryPasses[toolKey] = (doorRetryPasses[toolKey] or 0) + 1
				addWarning(
					toolKey .. ":doors",
					toolName
						.. " still has Uses="
						.. tostring(uses)
						.. "; retrying the non-exit doors"
				)
				if doorRetryPasses[toolKey]
					>= ROUND_DOOR_RETRY_PASS_LIMIT then
					doRoundState.completedDoorTools[toolKey] = true
					addWarning(
						toolKey .. ":doors-final",
						"No unused eligible door remained for "
							.. toolName
							.. "; continuing after "
							.. tostring(ROUND_DOOR_RETRY_PASS_LIMIT)
							.. " complete passes"
					)
					break
				end
				-- A failed pass is not successful placement. Door geometry, previews,
				-- and replicated models can become ready later, so allow another pass
				-- instead of advancing to the normal round with unused tools.
				rejectedDoors = setmetatable({}, {__mode = "k"})
				session.RejectedDoors = rejectedDoors
				setDoRoundStatus("Retrying " .. toolName .. " doors")
				doRoundWait(
					generation,
					math.min(1.5, 0.35 + doorRetryPasses[toolKey] * 0.15)
				)
				continue
			end

			setDoRoundStatus(
				"Laying " .. toolName .. " (" .. tostring(uses) .. " left)"
			)
			local door, _, prepareReason = prepareRoundDoorForPlacement(
				selectedDoor,
				generation
			)
			if not door then
				if prepareReason == "hunt started"
					or prepareReason == "ghost unavailable"
					or prepareReason == "Do-Round cancelled" then
					return false, prepareReason
				end
				local closeFailure = prepareReason == "door did not close"
					or prepareReason == "closed door geometry did not stabilize"
				local retrying = rejectOrRetryCurrentDoor(
					toolKey,
					selectedDoor,
					closeFailure and ROUND_DOOR_ATTEMPT_LIMIT * 2 or nil
				)
				if not retrying then
					addWarning(
						toolKey .. ":prepare:" .. selectedInstanceKey,
						prepareReason
					)
				end
				doRoundWait(generation, retrying and 0.35 or 0.2)
				continue
			end
			local placementDistance
			if toolKey == "salt canister" then
				local distanceReason
				placementDistance, distanceReason =
					waitForRoundPlacementXZDistance(toolName, generation)
				if not placementDistance then
					-- The working door routine used the door geometry's two-stud
					-- approach when the live preview was not ready yet. Calibration is
					-- useful when available, but must not prevent LaySaltPile entirely.
					addWarning(
						toolKey .. ":preview-distance",
						distanceReason
					)
				end
			end
			local approaches = roundDoorApproaches(
				door,
				placementDistance
			)
			local favouriteBounds = getRoomBoundingParts(
				doRoundState.lastFavouriteRoom
			)
			table.sort(approaches, function(first, second)
				local function score(approach)
					for _, candidate in ipairs(approach.CandidatePositions) do
						for _, bounds in ipairs(favouriteBounds) do
							if pointIsInsidePart(bounds, candidate) then
								return 1
							end
						end
					end
					return 0
				end
				return score(first) > score(second)
			end)
			local placed = false
			local placementReason = "no safe door-face position was found"
			local dispatched = false
			local observedUses
			for _, approach in ipairs(approaches) do
				if not roundActionIsSafe(generation) then
					return false, roundUnsafeReason(generation)
				end
				local teleported = teleportToRoundDoorFace(
					door,
					approach,
					generation
				)
				-- Preserve the working ordering: exact face teleport, immediate
				-- DoorUnion-facing rotation, then preview/facing lock. The broader
				-- interaction settle is only for close/open remotes, not placement.
				if teleported and facePlayerTowardRoundDoor(door) then
					placed, placementReason, dispatched, observedUses =
						fireRoundPlaceable(toolName, door, generation)
					if placed or dispatched then
						break
					end
				end
			end

			if observedUses ~= nil then
				doRoundState.doorToolUses[toolKey] = observedUses
				if observedUses <= 0 then
					doRoundState.completedDoorTools[toolKey] = true
				end
			end
			local useConsumed = observedUses ~= nil and observedUses < uses
			if placed or useConsumed then
				finishCurrentDoor(toolKey)
				doorRetryPasses[toolKey] = 0
				doRoundState.reservedDoorModels[selectedDoor] = true
				doRoundState.reservedDoorNames[selectedKey] = true
				doRoundState.doorToolPlacements[toolKey] =
					(doRoundState.doorToolPlacements[toolKey] or 0) + 1
				doRoundState.usedDoorNames[selectedKey] = true
				doRoundState.lastDoorName = selectedKey
				if toolKey == "salt canister" then
					doRoundState.usedSaltDoorModels[selectedDoor] = true
					doRoundState.usedSaltDoorNames[selectedKey] = true
				else
					doRoundState.usedHolyOilDoorModels[selectedDoor] = true
					doRoundState.usedHolyOilDoorNames[selectedKey] = true
				end
				if useConsumed and not placed then
					addWarning(
						toolKey .. ":confirmation:" .. selectedInstanceKey,
						placementReason
					)
				end
			elseif dispatched then
				if placementReason == "hunt started"
					or placementReason == "ghost unavailable"
					or placementReason == "Do-Round cancelled" then
					return false, placementReason
				end
				local retrying = rejectOrRetryCurrentDoor(toolKey, selectedDoor)
				if not retrying then
					addWarning(
						toolKey .. ":dispatch:" .. selectedInstanceKey,
						placementReason
					)
				end
			else
				if placementReason == "hunt started"
					or placementReason == "ghost unavailable"
					or placementReason == "Do-Round cancelled" then
					return false, placementReason
				end
				local retrying = rejectOrRetryCurrentDoor(toolKey, selectedDoor)
				if not retrying then
					addWarning(
						toolKey .. ":placement:" .. selectedInstanceKey,
						placementReason
					)
				end
			end
			if (doRoundState.doorToolPlacements[toolKey] or 0)
				>= placementLimit then
				doRoundState.completedDoorTools[toolKey] = true
			end
			if not placed and not useConsumed then
				doRoundWait(generation, 0.2)
			end
		end
	end
	if not doRoundOperationActive(generation) then
		return false, "Do-Round cancelled"
	end
	return true, #warnings > 0 and table.concat(warnings, "; ") or nil
end

local createLaySalt: any = assert(
	dependencies.CreateLaySalt,
	"pre-round requires CreateLaySalt"
)
local createPourHolyOil: any = assert(
	dependencies.CreatePourHolyOil,
	"pre-round requires CreatePourHolyOil"
)
local laySalt = createLaySalt({PlaceTool = placeRoundToolAtDoors})
local pourHolyOil = createPourHolyOil({PlaceTool = placeRoundToolAtDoors})

local function placeRoundToolsAtDoors(generation)
	local warnings = {}
	local session = {}
	for _, placeTool in ipairs({laySalt, pourHolyOil}) do
		local placed, warning = placeTool(generation, session)
		if not placed then
			return false, warning
		end
		if warning then
			table.insert(warnings, warning)
		end
	end
	return true, #warnings > 0 and table.concat(warnings, "; ") or nil
end

local function openRoundExitDoor(generation)
	local function markRoundStarted()
		if type(publishRoundStarted) == "function" then
			publishRoundStarted()
		end
		doRoundState.exitOpenedAt = doRoundState.exitOpenedAt or os.clock()
		return true
	end
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local remote = events and events:FindFirstChild("ClientChangeDoorState")
	if not remote or not remote:IsA("RemoteEvent") then
		return false, "ClientChangeDoorState RemoteEvent was not found"
	end
	local exitDoors = eligibleRoundDoors(true)
	if #exitDoors == 0 then
		return false, "Workspace.Doors.ExitDoor was not found"
	end
	for _, exitModel in ipairs(exitDoors) do
		local initialDoorContainer = exitModel:FindFirstChild("Door")
			or exitModel
		if not roundDoorClosedState(exitModel, initialDoorContainer) then
			return markRoundStarted()
		end
		for attempt = 1, ROUND_DOOR_ATTEMPT_LIMIT do
			if not roundActionIsSafe(generation) then
				return false, roundUnsafeReason(generation)
			end
			local doorContainer = exitModel:FindFirstChild("Door") or exitModel
			if not roundDoorClosedState(exitModel, doorContainer) then
				return markRoundStarted()
			end
			local doorReference = roundDoorReference(doorContainer) or doorContainer
			setDoRoundStatus("Teleporting to exit door")
			local approaches = roundDoorApproaches(doorReference)
			-- Always produce a fresh teleport update. Being locally inside the
			-- ten-stud radius does not prove the server has accepted that position.
			local teleported = teleportNearRoundTarget(
				doorReference,
				nil,
				generation
			)
			if teleported then
				teleported = settleRoundDoorInteraction(
					doorReference,
					10,
					generation
				)
			end
			if not teleported then
				for _, approach in ipairs(approaches) do
					if not roundActionIsSafe(generation) then
						return false, roundUnsafeReason(generation)
					end
					if teleportToRoundDoorFace(doorReference, approach, generation)
						and settleRoundDoorInteraction(
							doorReference,
							10,
							generation
						) then
						teleported = true
						break
					end
				end
			end
			if teleported then
				doorContainer = exitModel:FindFirstChild("Door") or exitModel
				doorReference = roundDoorReference(doorContainer) or doorContainer
				if not roundDoorClosedState(exitModel, doorContainer) then
					return markRoundStarted()
				end
				local root = player.Character
					and player.Character:FindFirstChild("HumanoidRootPart")
				local center = getInstanceWorldPosition(doorReference)
				if root and center and (root.Position - center).Magnitude <= 10 then
					setDoRoundStatus("Opening exit door")
					beginAutomationMutation(1.5)
					doRoundWait(generation, ROUND_REMOTE_SAFETY_DELAY)
					if not roundActionIsSafe(generation) then
						return false, roundUnsafeReason(generation)
					end
					-- Re-read immediately before firing so a replicated open cannot be
					-- toggled closed by a late retry.
					if not roundDoorClosedState(exitModel, doorContainer) then
						return markRoundStarted()
					end
					if pcall(remote.FireServer, remote, doorContainer) then
						local openDeadline = os.clock() + 1
						repeat
							if not roundDoorClosedState(exitModel, doorContainer) then
								return markRoundStarted()
							end
							doRoundWait(generation, 0.05)
						until os.clock() >= openDeadline
					end
				end
			end
			if attempt < ROUND_DOOR_ATTEMPT_LIMIT then
				setDoRoundStatus(
					"Retrying current exit door ("
						.. tostring(attempt + 1)
						.. "/"
						.. tostring(ROUND_DOOR_ATTEMPT_LIMIT)
						.. ")"
				)
				doRoundWait(generation, 0.35)
			end
		end
	end
	return false, "ExitDoor did not open"
end


local function releaseRoundMovement()
	for lock in pairs(doRoundState.facingLocks or {}) do
		pcall(lock.Release, lock)
	end
	doRoundState.facingLocks = setmetatable({}, {__mode = "k"})
	releasePlayerMovement(true)
end

local function runPreRound(generation, hooks)
	local identifiedGhost, identifiedScore, identifiedCertain =
		hooks.CurrentIdentification()
	if identifiedGhost then
		hooks.Complete(
			generation,
			identifiedGhost,
			identifiedScore,
			identifiedCertain
		)
		return nil, "completed"
	end
	setDoRoundStatus("Checking ghost room")
	local ghost
	local favouriteRoom
	repeat
		ghost = getGhostModel()
		local rooms = findRoomsFolder()
		favouriteRoom = findFavouriteRoom(
			rooms,
			ghost and ghost:GetAttribute("FavoriteRoom") or nil
		)
		if not favouriteRoom then
			doRoundWait(generation, 0.2)
		end
	until favouriteRoom and ghost
	doRoundState.lastFavouriteRoom = favouriteRoom
	doRoundState.roundMap = workspace:FindFirstChild("Map")
	doRoundState.roundGhost = ghost
	if not doRoundState.roundMap then
		error("Map was not found", 0)
	end

	hooks.WaitForHuntEnd(generation)
	if not doRoundOperationActive(generation) then
		return nil, "cancelled"
	end
	identifiedGhost, identifiedScore, identifiedCertain =
		hooks.CurrentIdentification()
	if identifiedGhost then
		hooks.Complete(
			generation,
			identifiedGhost,
			identifiedScore,
			identifiedCertain
		)
		return nil, "completed"
	end
	setDoRoundStatus("Placing room items")
	local setupCompleted, setupReason = hooks.PerformRoomItemSetup(generation)
	if not setupCompleted and presenter and presenter.Notify then
		presenter:Notify(
			setupReason
				or "Room item setup failed; continuing with available items"
		)
	end
	hooks.CaptureRoomItems(favouriteRoom)
	doRoundState.itemsDirty = true
	local missingRoomItems = {}
	for _, itemName in ipairs(DROPPED_ROOM_ITEMS) do
		local tracked = doRoundState.roomItems[
			normalizeRoundItemName(itemName)
		]
		if not tracked or not tracked.Parent then
			table.insert(missingRoomItems, itemName)
		end
	end
	if #missingRoomItems > 0 and presenter and presenter.Notify then
		presenter:Notify(
			"Missing room items: "
				.. table.concat(missingRoomItems, ", ")
				.. "; continuing"
		)
	end
	local missingHeldItems = {}
	for _, itemName in ipairs(ROUND_HELD_ITEMS) do
		local stored = getRoundEquippedItem(itemName)
			or getRoundInventoryItem(itemName)
		if not findRoundHotbarSlot(itemName) and not stored then
			table.insert(missingHeldItems, itemName)
		end
	end
	if #missingHeldItems > 0 and presenter and presenter.Notify then
		presenter:Notify(
			"Missing held items: "
				.. table.concat(missingHeldItems, ", ")
				.. "; continuing"
		)
	end

	local toolsDone = false
	repeat
		hooks.WaitForHuntEnd(generation)
		local completed, reason = placeRoundToolsAtDoors(generation)
		if completed then
			toolsDone = true
			if reason and presenter and presenter.Notify then
				presenter:Notify(reason)
			end
		elseif reason ~= "hunt started"
			and reason ~= "ghost unavailable" then
			error(reason or "door placeables failed", 0)
		end
	until toolsDone

	local exitOpened = false
	local exitAttempts = 0
	repeat
		hooks.WaitForHuntEnd(generation)
		setDoRoundStatus("Opening exit door")
		local opened, reason = openRoundExitDoor(generation)
		if opened then
			exitOpened = true
		elseif reason ~= "hunt started"
			and reason ~= "ghost unavailable" then
			exitAttempts += 1
			if presenter and presenter.Notify then
				presenter:Notify(
					(reason or "Exit door failed")
						.. "; retrying ("
						.. tostring(exitAttempts)
						.. "/3)"
				)
			end
			if exitAttempts >= 3 then
				exitAttempts = 0
				doRoundWait(generation, 1.5)
			else
				doRoundWait(generation, 0.5)
			end
		end
	until exitOpened

	return {
		Ghost = ghost,
		FavouriteRoom = favouriteRoom,
	}
end

return {
	Run = runPreRound,
	DroppedRoomItems = DROPPED_ROOM_ITEMS,
	PoweredRoomItems = POWERED_ROOM_ITEMS,
	HeldItems = ROUND_HELD_ITEMS,
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
	UnsafeReason = roundUnsafeReason,
	OperationActive = doRoundOperationActive,
	Wait = doRoundWait,
	BeginMutation = beginAutomationMutation,
	TeleportNearTarget = teleportNearRoundTarget,
	InstanceInsideAnyRoom = roundInstanceInsideAnyRoom,
	PickupMaxDistance = ROUND_PICKUP_MAX_DISTANCE,
	RemoteSafetyDelay = ROUND_REMOTE_SAFETY_DELAY,
	ItemOutsideGrace = ROUND_ITEM_OUTSIDE_GRACE,
	MaintenanceInterval = ROUND_MAINTENANCE_INTERVAL,
	MaintenanceRetryBackoff = ROUND_MAINTENANCE_RETRY_BACKOFF,
	LobbyRetrySeconds = ROUND_LOBBY_RETRY_SECONDS,
	MinimumLeaveAge = ROUND_MINIMUM_LEAVE_AGE,
	BaseCampSettleSeconds = ROUND_BASE_CAMP_SETTLE_SECONDS,
	JournalSettleSeconds = ROUND_JOURNAL_SETTLE_SECONDS,
	BaseCampRetryMin = ROUND_BASE_CAMP_RETRY_MIN,
	BaseCampRetryMax = ROUND_BASE_CAMP_RETRY_MAX,
	TeleportOptions = roundTeleportOptions,
	PlayerIsInsideBaseCamp = playerIsInsideRoundBaseCamp,
	ReturnToBase = returnRoundToBase,
	ReleaseMovement = releaseRoundMovement,
}
end
