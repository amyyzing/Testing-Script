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
local roundUtilities: any = (function()
local DROPPED_ROOM_ITEMS = {
	"Spirit Box",
	"Laser Projector",
	"Video Camera",
	"Blacklight",
	"EMF Reader",
	"Cross",
	"Flower Pot",
}
local POWERED_ROOM_ITEMS = {
	["spirit box"] = true,
	["laser projector"] = true,
	["blacklight"] = true,
	["emf reader"] = true,
}
local ROUND_HELD_ITEMS = {"Salt Canister", "Holy Oil"}

local function normalizeRoundItemName(value)
	return string.lower(tostring(value or ""))
		:match("^%s*(.-)%s*$")
		:gsub("%s+", " ")
end

local function roundItemName(model)
	return model and (model:GetAttribute("ItemName") or model.Name) or nil
end

local function findRoundHotbarSlot(itemName)
	local normalized = normalizeRoundItemName(itemName)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hotbar = playerGui and playerGui:FindFirstChild("Hotbar")
	local slots = hotbar and hotbar:FindFirstChild("Slots")
	if slots then
		for slotNumber = 1, 3 do
			local slot = slots:FindFirstChild("InvSlot" .. tostring(slotNumber))
			local label = slot and slot:FindFirstChild("ItemName")
			if label and label:IsA("TextLabel")
				and normalizeRoundItemName(label.Text) == normalized then
				return slotNumber
			end
		end
	end
	return nil
end

local function getRoundEquippedItem(itemName)
	local character = player.Character
	local normalized = normalizeRoundItemName(itemName)
	if not character then
		return nil
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Model")
			and normalizeRoundItemName(roundItemName(child)) == normalized then
			return child
		end
	end
	return nil
end

local equipRoundItem: any = function(itemName, timeout, generation)
	local equipped = getRoundEquippedItem(itemName)
	if equipped then
		return equipped
	end
	local slotNumber = findRoundHotbarSlot(itemName)
	if not slotNumber then
		return nil, itemName .. " is not in the hotbar"
	end
	if generation ~= nil
		and (not runtimeIsActive()
			or not doRoundState.enabled
			or doRoundState.generation ~= generation) then
		return nil, "Do-Round cancelled"
	end
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local remote = events and events:FindFirstChild("RequestItemEquip")
	if not remote or not remote:IsA("RemoteEvent") then
		return nil, "RequestItemEquip RemoteEvent was not found"
	end
	local fired = pcall(
		remote.FireServer,
		remote,
		"InvSlot" .. tostring(slotNumber)
	)
	if not fired then
		return nil, "RequestItemEquip failed"
	end
	local deadline = os.clock() + (timeout or 1.5)
	repeat
		equipped = getRoundEquippedItem(itemName)
		if equipped then
			return equipped
		end
		task.wait(0.05)
	until os.clock() >= deadline or not runtimeIsActive()
	return nil, itemName .. " could not be equipped"
end

local function roundTargetCFrame(target)
	if not target then
		return nil, nil
	end
	if target:IsA("BasePart") then
		return target.CFrame, target.Size
	end
	if target:IsA("Model") then
		local ok, frame, size = pcall(target.GetBoundingBox, target)
		if ok then
			return frame, size
		end
		local pivotOk, pivot = pcall(target.GetPivot, target)
		if pivotOk then
			return pivot, Vector3.new(4, 4, 1)
		end
	end
	local part = target:FindFirstChildWhichIsA("BasePart", true)
	return part and part.CFrame or nil, part and part.Size or nil
end

local function roundApproachPositions(target, distance)
	local frame, size = roundTargetCFrame(target)
	if not frame then
		return {}, nil
	end
	local horizontalSize = size and math.max(size.X, size.Z) or 2
	local offset = distance
		or math.clamp(horizontalSize * 0.5 + 3.25, 4.25, 6.5)
	local center = frame.Position
	local right = Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z)
	local look = Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z)
	if right.Magnitude < 0.05 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	else
		look = look.Unit
	end
	return {
		center + look * offset,
		center - look * offset,
		center + right * offset,
		center - right * offset,
	}, center
end

local function roomForRoundTarget(target, preferredPositions)
	local rooms = findRoomsFolder()
	if not rooms then
		return nil
	end
	local targetPosition = getInstanceWorldPosition(target)
	local distancePositions = preferredPositions
	if not distancePositions or #distancePositions == 0 then
		distancePositions = targetPosition and {targetPosition} or {}
	end
	local bestRoom
	local bestInsideCount = -1
	local bestDistance = math.huge
	for _, room in ipairs(rooms:GetChildren()) do
		local insideCount = 0
		local distance = math.huge
		for _, boundingPart in ipairs(getRoomBoundingParts(room)) do
			for _, position in ipairs(preferredPositions or {}) do
				if pointIsInsidePart(boundingPart, position) then
					insideCount = insideCount + 1
				end
			end
			for _, referencePosition in ipairs(distancePositions) do
				local localPosition =
					boundingPart.CFrame:PointToObjectSpace(referencePosition)
				local half = boundingPart.Size * 0.5
				local dx = math.max(math.abs(localPosition.X) - half.X, 0)
				local dz = math.max(math.abs(localPosition.Z) - half.Z, 0)
				distance = math.min(distance, math.sqrt(dx ^ 2 + dz ^ 2))
			end
		end
		if insideCount > bestInsideCount
			or (insideCount == bestInsideCount and distance < bestDistance) then
			bestRoom = room
			bestInsideCount = insideCount
			bestDistance = distance
		end
	end
	return bestRoom
end

local function teleportNearRoundTarget(target, preferredPosition, generation)
	local positions, center = roundApproachPositions(target)
	if not center then
		return false, "target has no world position"
	end
	local preferred = preferredPosition and {preferredPosition} or positions
	local room = roomForRoundTarget(target, preferred)
	if not room then
		return false, "no room bounding box was found near the target"
	end
	return teleportToRoomBoundingBoxCenter(room, {
		PreferredPositions = preferred,
		TargetPosition = center,
		MaximumTargetDistance = 9.25,
		LookAtPosition = center,
		RequireStrict = true,
		IsActive = function()
			return generation == nil
				or (runtimeIsActive()
					and doRoundState.enabled
					and doRoundState.generation == generation)
		end,
	})
end

local function shuffleRoundList(list)
	local copy = {}
	for index, value in ipairs(list) do
		copy[index] = value
	end
	for index = #copy, 2, -1 do
		local swap = math.random(index)
		copy[index], copy[swap] = copy[swap], copy[index]
	end
	return copy
end

local function roundIsHunting()
	local ghost = getGhostModel()
	return ghost and ghost:GetAttribute("Hunting") == true or false
end

local function roundIdentityIsCurrent()
	return doRoundState.roundMap ~= nil
		and workspace:FindFirstChild("Map") == doRoundState.roundMap
		and doRoundState.roundGhost ~= nil
		and getGhostModel() == doRoundState.roundGhost
end

local function roundActionIsSafe(generation)
	return (generation == nil
			or (runtimeIsActive()
				and doRoundState.enabled
				and doRoundState.generation == generation))
		and roundIdentityIsCurrent()
		and doRoundState.roundGhost:GetAttribute("Hunting") ~= true
		and player:GetAttribute("Dead") ~= true
end

local function roundUnsafeReason(generation)
	if generation ~= nil
		and (not runtimeIsActive()
			or not doRoundState.enabled
			or doRoundState.generation ~= generation) then
		return "Do-Round cancelled"
	end
	if not roundIdentityIsCurrent() then
		return "round changed"
	end
	if player:GetAttribute("Dead") == true then
		return "player is dead"
	end
	return "hunt started"
end

local function doRoundOperationActive(generation)
	return runtimeIsActive()
		and doRoundState.enabled
		and doRoundState.generation == generation
end

local function doRoundWait(generation, seconds)
	local deadline = os.clock() + seconds
	repeat
		if not doRoundOperationActive(generation) then
			error("Do-Round cancelled", 0)
		end
		task.wait(math.min(0.05, math.max(0, deadline - os.clock())))
	until os.clock() >= deadline
end

local function beginAutomationMutation(duration)
	local untilTime = os.clock() + (duration or 2.5)
	perkTrackerState.automationMutationUntil = math.max(
		perkTrackerState.automationMutationUntil or 0,
		untilTime
	)
	perkTrackerState.suppressItemDisableUntil = math.max(
		perkTrackerState.suppressItemDisableUntil or 0,
		untilTime
	)
	perkTrackerState.suppressLeviathanLightsUntil = math.max(
		perkTrackerState.suppressLeviathanLightsUntil or 0,
		untilTime
	)
end

local function previewMajorAxis(part)
	if not part or not part:IsA("BasePart") then
		return nil
	end
	local axis = part.Size.X >= part.Size.Z
		and part.CFrame.RightVector
		or part.CFrame.LookVector
	axis = Vector3.new(axis.X, 0, axis.Z)
	return axis.Magnitude >= 0.05 and axis.Unit or nil
end

local placementPreviewIsAligned: any = function(toolName, target)
	local camera = workspace.CurrentCamera
	local previewName = toolName == "Salt Canister" and "SaltLine" or "HolyOil"
	local partName = toolName == "Salt Canister" and "Salt" or "Center"
	local preview = camera and camera:FindFirstChild(previewName)
	local previewPart = preview and preview:FindFirstChild(partName, true)
	local targetFrame, targetSize = roundTargetCFrame(target)
	local root = player.Character
		and player.Character:FindFirstChild("HumanoidRootPart")
	if not previewPart or not previewPart:IsA("BasePart")
		or not targetFrame or not root then
		return false
	end
	local planarOffset = Vector3.new(
		previewPart.Position.X - targetFrame.Position.X,
		0,
		previewPart.Position.Z - targetFrame.Position.Z
	)
	if planarOffset.Magnitude > 4.25 then
		return false
	end
	local toTarget = Vector3.new(
		targetFrame.Position.X - root.Position.X,
		0,
		targetFrame.Position.Z - root.Position.Z
	)
	local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if toTarget.Magnitude < 0.05 or facing.Magnitude < 0.05
		or facing.Unit:Dot(toTarget.Unit) < 0.72 then
		return false
	end
	if toolName == "Salt Canister" then
		local previewAxis = previewMajorAxis(previewPart)
		local doorAxis = targetSize and (
			targetSize.X >= targetSize.Z
				and targetFrame.RightVector
				or targetFrame.LookVector
		) or targetFrame.RightVector
		doorAxis = Vector3.new(doorAxis.X, 0, doorAxis.Z)
		if previewAxis and doorAxis.Magnitude >= 0.05
			and math.abs(previewAxis:Dot(doorAxis.Unit)) < 0.7 then
			return false
		end
	end
	return true
end

local waitForRoundPreview: any = function(toolName, target, generation)
	local deadline = os.clock() + 1.4
	repeat
		if not roundActionIsSafe(generation) then
			return false, roundUnsafeReason(generation)
		end
		if placementPreviewIsAligned(toolName, target) then
			return true
		end
		doRoundWait(generation, 0.05)
	until os.clock() >= deadline
	return false, "placement preview did not align with the doorway"
end

local fireRoundPlaceable: any = function(toolName, target, generation)
	local equipped, equipReason = equipRoundItem(toolName, 1.5, generation)
	if not equipped then
		return false, equipReason
	end
	local cooldownDeadline = os.clock() + 6
	while equipped.Parent
		and equipped:GetAttribute("EquipDisabled") == true
		and os.clock() < cooldownDeadline do
		if not roundActionIsSafe(generation) then
			return false, roundUnsafeReason(generation)
		end
		doRoundWait(generation, 0.05)
	end
	if equipped:GetAttribute("EquipDisabled") == true then
		return false, toolName .. " is still on placement cooldown"
	end
	local uses = tonumber(equipped:GetAttribute("Uses")) or 0
	if uses <= 0 then
		return false, toolName .. " has no uses remaining"
	end
	local aligned, alignReason = waitForRoundPreview(
		toolName,
		target,
		generation
	)
	if not aligned then
		return false, alignReason
	end
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local remoteName = toolName == "Salt Canister"
		and "LaySaltPile"
		or "PourHolyOil"
	local remote = events and events:FindFirstChild(remoteName)
	if not remote or not remote:IsA("RemoteEvent") then
		return false, remoteName .. " RemoteEvent was not found"
	end
	if not roundActionIsSafe(generation) then
		return false, roundUnsafeReason(generation)
	end
	beginAutomationMutation(2.5)
	local fired = pcall(remote.FireServer, remote)
	if not fired then
		return false, remoteName .. " failed"
	end
	local deadline = os.clock() + 2
	local confirmed = false
	repeat
		if not doRoundOperationActive(generation) then
			return false, "Do-Round cancelled"
		end
		if not roundActionIsSafe(generation) then
			return false, roundUnsafeReason(generation)
		end
		local currentUses = tonumber(equipped:GetAttribute("Uses")) or uses
		if currentUses < uses then
			confirmed = true
			break
		end
		task.wait(0.05)
	until os.clock() >= deadline
	if not confirmed then
		return false, toolName .. " placement was not confirmed"
	end
	local equipDeadline = os.clock() + 6
	while equipped.Parent
		and equipped:GetAttribute("EquipDisabled") == true
		and os.clock() < equipDeadline do
		if not roundActionIsSafe(generation) then
			return false, roundUnsafeReason(generation)
		end
		doRoundWait(generation, 0.05)
	end
	if equipped.Parent and equipped:GetAttribute("EquipDisabled") == true then
		return false, toolName .. " placement cooldown did not clear"
	end
	return true
end
	return {
		DroppedRoomItems = DROPPED_ROOM_ITEMS,
		PoweredRoomItems = POWERED_ROOM_ITEMS,
		HeldItems = ROUND_HELD_ITEMS,
		NormalizeItemName = normalizeRoundItemName,
		ItemName = roundItemName,
		FindHotbarSlot = findRoundHotbarSlot,
		EquipItem = equipRoundItem,
		ApproachPositions = roundApproachPositions,
		TeleportNearTarget = teleportNearRoundTarget,
		Shuffle = shuffleRoundList,
		IsHunting = roundIsHunting,
		IdentityIsCurrent = roundIdentityIsCurrent,
		ActionIsSafe = roundActionIsSafe,
		UnsafeReason = roundUnsafeReason,
		OperationActive = doRoundOperationActive,
		Wait = doRoundWait,
		BeginMutation = beginAutomationMutation,
		FirePlaceable = fireRoundPlaceable,
	}
end)()

local setDoRoundEnabled = (function()
	local DROPPED_ROOM_ITEMS = roundUtilities.DroppedRoomItems
	local POWERED_ROOM_ITEMS = roundUtilities.PoweredRoomItems
	local ROUND_HELD_ITEMS = roundUtilities.HeldItems
	local normalizeRoundItemName = roundUtilities.NormalizeItemName
	local roundItemName = roundUtilities.ItemName
	local findRoundHotbarSlot = roundUtilities.FindHotbarSlot
	local equipRoundItem = roundUtilities.EquipItem
	local roundApproachPositions = roundUtilities.ApproachPositions
	local teleportNearRoundTarget = roundUtilities.TeleportNearTarget
	local shuffleRoundList = roundUtilities.Shuffle
	local roundIsHunting = roundUtilities.IsHunting
	local roundIdentityIsCurrent = roundUtilities.IdentityIsCurrent
	local roundActionIsSafe = roundUtilities.ActionIsSafe
	local roundUnsafeReason = roundUtilities.UnsafeReason
	local doRoundOperationActive = roundUtilities.OperationActive
	local doRoundWait = roundUtilities.Wait
	local beginAutomationMutation = roundUtilities.BeginMutation
	local fireRoundPlaceable = roundUtilities.FirePlaceable
	local function roundTeleportOptions(generation)
		return {
			IsActive = function()
				return doRoundOperationActive(generation)
			end,
		}
	end
	local function returnRoundToBase(generation)
		while doRoundOperationActive(generation) do
			setDoRoundStatus("Returning to Base Camp")
			local teleported = teleportToBaseCamp(
				roundTeleportOptions(generation)
			)
			if teleported then
				return true
			end
			task.wait(0.15)
		end
		return false
	end

local eligibleRoundDoors: any = function(includeExit)
	local folder = workspace:FindFirstChild("Doors")
	local doors: any = {}
	if not folder then
		return doors
	end
	local candidates: any
	if includeExit then
		candidates = folder:GetDescendants()
	else
		candidates = folder:GetChildren()
	end
	for _, model in ipairs(candidates) do
		if model:IsA("Model") then
			local isExit = string.lower(tostring(model.Name)) == "exitdoor"
			if isExit == includeExit then
				table.insert(doors, model)
			end
		end
	end
	return shuffleRoundList(doors)
end

local function placeRoundToolsAtDoors(generation)
	local rejectedDoorNames = {}
	for _, toolName in ipairs(ROUND_HELD_ITEMS) do
		local placementCount = 0
		local maximumPlacements
		while doRoundOperationActive(generation) do
			if not roundActionIsSafe(generation) then
				return false, roundUnsafeReason(generation)
			end
			local equipped, reason = equipRoundItem(toolName, 1.5, generation)
			if not equipped then
				if presenter and presenter.Notify then
					presenter:Notify(reason)
				end
				break
			end
			local uses = tonumber(equipped:GetAttribute("Uses")) or 0
			local configuredMaximum =
				tonumber(equipped:GetAttribute("MaxUses"))
			if configuredMaximum and configuredMaximum <= 0 then
				configuredMaximum = nil
			end
			maximumPlacements = maximumPlacements
				or configuredMaximum
				or uses
			if uses <= 0 or placementCount >= maximumPlacements then
				break
			end
			local selectedDoor
			local selectedKey
			for _, doorModel in ipairs(eligibleRoundDoors(false)) do
				local key = string.lower(tostring(doorModel.Name))
				if not doRoundState.usedDoorNames[key]
					and not rejectedDoorNames[key] then
					selectedDoor = doorModel
					selectedKey = key
					break
				end
			end
			if not selectedDoor then
				return false,
					toolName
						.. " still has uses, but no unused non-exit door names remain"
			end
			setDoRoundStatus("Laying " .. toolName)
			local door = selectedDoor:FindFirstChild("Door") or selectedDoor
			local approaches = roundApproachPositions(door)
			local placed = false
			local teleportedToDoor = false
			for _, approach in ipairs(shuffleRoundList(approaches)) do
				if not roundActionIsSafe(generation) then
					return false, roundUnsafeReason(generation)
				end
				-- Equip first so the server-authoritative preview follows this move.
				equipped, reason = equipRoundItem(toolName, 1.5, generation)
				if not equipped then
					break
				end
				local teleported = teleportNearRoundTarget(door, approach, generation)
				if teleported then
					teleportedToDoor = true
					doRoundState.usedDoorNames[selectedKey] = true
					doRoundWait(generation, 0.2)
					placed = fireRoundPlaceable(
						toolName,
						door,
						generation
					)
					if placed then
						break
					end
				end
			end
			if not placed then
				if not teleportedToDoor then
					rejectedDoorNames[selectedKey] = true
				end
				doRoundWait(generation, 0.15)
			else
				placementCount = placementCount + 1
			end
		end
	end
	return true
end

local function openRoundExitDoor(generation)
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
		if exitModel:GetAttribute("DoorClosed") == false then
			return true
		end
		local door = exitModel:FindFirstChild("Door")
		if door then
			local approaches, center = roundApproachPositions(door)
			for _, approach in ipairs(shuffleRoundList(approaches)) do
				if not roundActionIsSafe(generation) then
					return false, roundUnsafeReason(generation)
				end
				local teleported = teleportNearRoundTarget(door, approach, generation)
				local root = player.Character
					and player.Character:FindFirstChild("HumanoidRootPart")
				if teleported and root and center
					and (root.Position - center).Magnitude <= 10 then
					if not roundActionIsSafe(generation) then
						teleportToBaseCamp(roundTeleportOptions(generation))
						return false, roundUnsafeReason(generation)
					end
					if exitModel:GetAttribute("DoorClosed") == false then
						return true
					end
					beginAutomationMutation(1.5)
					local fired = pcall(remote.FireServer, remote, door)
					if fired then
						doRoundWait(generation, 0.45)
						if exitModel:GetAttribute("DoorClosed") == false then
							return true
						end
					end
				end
			end
		end
	end
	return false, "ExitDoor did not open"
end

local function captureRoundRoomItems(room)
	local items = workspace:FindFirstChild("Items")
	if not items or not room then
		return
	end
	for _, itemName in ipairs(DROPPED_ROOM_ITEMS) do
		local normalized = normalizeRoundItemName(itemName)
		local existing = doRoundState.roomItems[normalized]
		if not existing or not existing.Parent then
			local fallback
			for _, model in ipairs(items:GetChildren()) do
				if normalizeRoundItemName(roundItemName(model)) == normalized then
					fallback = fallback or model
					if instanceIsInsideRoom(model, room) then
						doRoundState.roomItems[normalized] = model
						fallback = nil
						break
					end
				end
			end
			if fallback then
				doRoundState.roomItems[normalized] = fallback
			end
		end
	end
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
	for slotNumber = 1, 3 do
		local value = player:GetAttribute("InvSlot" .. tostring(slotNumber))
		if value ~= nil and value ~= false and tostring(value) ~= "" then
			count = count + 1
		end
	end
	return count
end

local function restoreRoundItemToRoom(model, room, generation)
	if not model or not model.Parent or not room then
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
	local itemsFolder = workspace:FindFirstChild("Items")
	local isWorldItem = itemsFolder and model:IsDescendantOf(itemsFolder)
	if not isWorldItem then
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
		pcall(equip.FireServer, equip, "InvSlot" .. tostring(heldSlot))
		doRoundWait(generation, 0.15)
		if not roundActionIsSafe(generation) then
			return false
		end
		pcall(drop.FireServer, drop, "InvSlot" .. tostring(heldSlot))
		doRoundWait(generation, 0.35)
		beginAutomationMutation(3)
		return itemsFolder ~= nil
			and model:IsDescendantOf(itemsFolder)
			and instanceIsInsideRoom(model, room)
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
	beginAutomationMutation(4)
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
	pcall(equip.FireServer, equip, "InvSlot" .. tostring(slotNumber))
	doRoundWait(generation, 0.15)
	if not roundActionIsSafe(generation) then
		return false
	end
	pcall(drop.FireServer, drop, "InvSlot" .. tostring(slotNumber))
	doRoundWait(generation, 0.35)
	beginAutomationMutation(3)
	return instanceIsInsideRoom(model, room)
end

local function maintainRoundRoomItems(room, generation)
	captureRoundRoomItems(room)
	local now = os.clock()
	for _, itemName in ipairs(DROPPED_ROOM_ITEMS) do
		local normalized = normalizeRoundItemName(itemName)
		local model = doRoundState.roomItems[normalized]
		if model and model.Parent then
			local itemsFolder = workspace:FindFirstChild("Items")
			local worldItem = itemsFolder
				and model:IsDescendantOf(itemsFolder)
			if not worldItem or not instanceIsInsideRoom(model, room) then
				doRoundState.outsideSince[model] =
					doRoundState.outsideSince[model] or now
				if now - doRoundState.outsideSince[model] >= 1.5 then
					setDoRoundStatus("Maintaining room items")
					if restoreRoundItemToRoom(model, room, generation) then
						doRoundState.outsideSince[model] = nil
					end
					return
				end
			else
				doRoundState.outsideSince[model] = nil
			end
			if worldItem and POWERED_ROOM_ITEMS[normalized]
				and instanceIsInsideRoom(model, room) then
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
						and now - power.LastChangedAt >= 3 then
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
								local events = Services.ReplicatedStorage:FindFirstChild("Events")
								local toggle = events and events:FindFirstChild("ToggleItemState")
								if toggle and toggle:IsA("RemoteEvent") then
									beginAutomationMutation(2.5)
									local fired = pcall(toggle.FireServer, toggle, model)
									if fired then
										power.LastChangedAt = now
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

local function selectRoundJournalGhost(ghostName, generation)
	if not ghostName or string.find(tostring(ghostName), "/", 1, true) then
		return false
	end
	if not doRoundOperationActive(generation) then
		return false
	end
	local ghostTypes = perkTrackerState.findJournalGhostTypes()
	if ghostTypes then
		local frame = ghostTypes:FindFirstChild(ghostName)
		if frame and frame:IsA("Frame")
			and perkTrackerState.applyJournalRowState(frame, true)
			and doRoundOperationActive(generation) then
			perkTrackerState.lastJournalSelectedGhost = ghostName
			perkTrackerState.lastJournalVisualGhost = ghostName
			return true
		end
	end
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local remote = events and events:FindFirstChild("EvidenceMarkedInJournal")
	if remote and remote:IsA("RemoteEvent")
		and doRoundOperationActive(generation) then
		local sent = pcall(remote.FireServer, remote, ghostName)
		if sent then
			perkTrackerState.lastJournalSelectedGhost = ghostName
		end
		return sent
	end
	return false
end

local setEnabled

local function waitForRoundHuntEnd(generation)
	local escaped = false
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
		if not escaped then
			local teleported = teleportToBaseCamp(
				roundTeleportOptions(generation)
			)
			escaped = teleported == true
		end
		doRoundWait(generation, 0.15)
	end
	if escaped then
		doRoundWait(generation, 0.65)
	end
	return escaped
end

local function runDoRound(generation)
	local success, failure = xpcall(function()
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

		waitForRoundHuntEnd(generation)
		setDoRoundStatus("Placing room items")
		local started, placementGeneration =
			placeItemsInFavouriteRoom("DoRound")
		if not started then
			error(tostring(placementGeneration), 0)
		end
		repeat
			if roundIsHunting() then
				setDoRoundStatus("Waiting for hunt")
			else
				setDoRoundStatus("Placing room items")
			end
			doRoundWait(generation, 0.15)
			if not roundIdentityIsCurrent() then
				error("the round changed during room item setup", 0)
			end
		until roomItemPlacementState.lastCompletedGeneration
			>= placementGeneration
		if roomItemPlacementState.lastResult == false then
			error(roomItemPlacementState.lastError or "room item setup failed", 0)
		end
		captureRoundRoomItems(favouriteRoom)
		local missingRoomItems = {}
		for _, itemName in ipairs(DROPPED_ROOM_ITEMS) do
			local tracked = doRoundState.roomItems[
				normalizeRoundItemName(itemName)
			]
			if not tracked or not tracked.Parent then
				table.insert(missingRoomItems, itemName)
			end
		end
		if #missingRoomItems > 0 then
			error(
				"required room items were not found: "
					.. table.concat(missingRoomItems, ", "),
				0
			)
		end
		local missingHeldItems = {}
		for _, itemName in ipairs(ROUND_HELD_ITEMS) do
			if not findRoundHotbarSlot(itemName) then
				table.insert(missingHeldItems, itemName)
			end
		end
		if #missingHeldItems > 0 then
			error(
				"required held items were not found: "
					.. table.concat(missingHeldItems, ", "),
				0
			)
		end

		local toolsDone = false
		repeat
			waitForRoundHuntEnd(generation)
			local completed, reason = placeRoundToolsAtDoors(generation)
			if completed then
				toolsDone = true
			elseif reason ~= "hunt started" then
				error(reason or "door placeables failed", 0)
			end
		until toolsDone

		local exitOpened = false
		repeat
			waitForRoundHuntEnd(generation)
			setDoRoundStatus("Opening exit door")
			local opened, reason = openRoundExitDoor(generation)
			if opened then
				exitOpened = true
			elseif reason ~= "hunt started" then
				error(reason or "exit door failed", 0)
			end
		until exitOpened

		waitForRoundHuntEnd(generation)
		teleportToFavouriteRoom(roundTeleportOptions(generation))
		doRoundState.questionsActive = true
		local qualifiedName
		local qualifiedSince
		local timeoutFallback
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
				ghost and ghost:GetAttribute("FavoriteRoom") or nil
			)
			if currentFavourite and currentFavourite ~= favouriteRoom then
				favouriteRoom = currentFavourite
				doRoundState.lastFavouriteRoom = favouriteRoom
				captureRoundRoomItems(favouriteRoom)
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
				qualifiedName = nil
				qualifiedSince = nil
				continue
			end

			local guess = perkTrackerState.currentGhostGuess
			local score = perkTrackerState.currentGhostGuessScore or 0
			local certain = perkTrackerState.currentGhostGuessCertain == true
			local singleGuess = guess
				and not string.find(guess, "/", 1, true)
			if singleGuess and (certain or score >= 80) then
				if qualifiedName ~= guess then
					qualifiedName = guess
					qualifiedSince = os.clock()
				elseif os.clock() - qualifiedSince >= 1.5 then
					if selectRoundJournalGhost(guess, generation) then
						if returnRoundToBase(generation) then
							setEnabled(false, "Identified " .. guess)
						end
						return
					end
					setDoRoundStatus("Selecting ghost guess")
				end
			else
				qualifiedName = nil
				qualifiedSince = nil
			end

			if doRoundState.startedAt
				and os.clock() - doRoundState.startedAt >= 180 then
				if not timeoutFallback then
					local timeoutCandidates =
						perkTrackerState.getRemainingCandidates(false)
					if #timeoutCandidates == 0 then
						timeoutCandidates =
							perkTrackerState.getRemainingCandidates(true)
					end
					if #timeoutCandidates == 0 then
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
					timeoutFallback = GhostModule.SelectHighestConfidenceGuess({
						Candidates = timeoutCandidates,
						Detections = perkDetections,
						CurrentGuess = guess,
						CurrentScore = score,
						RandomIndex = function(count)
							return math.random(count)
						end,
					})
				end
				if timeoutFallback then
					local fallbackDetection = perkDetections[timeoutFallback]
					local fallbackScore = fallbackDetection
						and tonumber(fallbackDetection.Confidence)
						or 0
					if guess and string.find(guess, timeoutFallback, 1, true) then
						fallbackScore = math.max(fallbackScore, score)
					end
					fallbackScore = math.max(fallbackScore, 1)
					perkTrackerState.currentGhostGuess = timeoutFallback
					perkTrackerState.currentGhostGuessScore = fallbackScore
					perkTrackerState.currentGhostGuessCertain = false
					setGhostIdentificationLabel(
						timeoutFallback,
						perkTrackerState.currentGhostGuessScore,
						false
					)
					if selectRoundJournalGhost(timeoutFallback, generation) then
						if returnRoundToBase(generation) then
							setEnabled(false, "Selected " .. timeoutFallback)
						end
						return
					end
				end
				setDoRoundStatus(timeoutFallback and "Selecting ghost guess" or "Timed out")
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
		if returnRoundToBase(generation) then
			setEnabled(false, "Stopped")
		end
	end
end

setEnabled = function(enabled, finalPhase)
	enabled = enabled == true
	if doRoundState.enabled == enabled then
		if finalPhase then
			setDoRoundStatus(finalPhase)
		end
		return enabled
	end
	doRoundState.generation = doRoundState.generation + 1
	doRoundState.enabled = enabled
	if enabled then
		for _, power in pairs(doRoundState.itemPower) do
			if power.Connection and power.Connection.Connected then
				power.Connection:Disconnect()
			end
		end
		doRoundState.startedAt = os.clock()
		doRoundState.lastElapsed = 0
		doRoundState.phase = "Checking ghost room"
		doRoundState.roundMap = nil
		doRoundState.roundGhost = nil
		doRoundState.usedDoorNames = {}
		doRoundState.roomItems = {}
		doRoundState.itemPower = setmetatable({}, {__mode = "k"})
		doRoundState.outsideSince = setmetatable({}, {__mode = "k"})
		doRoundState.autoSpiritBoxLease = true
		doRoundState.questionsActive = false
		refreshAutoSpiritBoxEnabled()
		setDoRoundStatus(doRoundState.phase)
		local generation = doRoundState.generation
		doRoundState.thread = task.spawn(function()
			runDoRound(generation)
		end)
	else
		for _, power in pairs(doRoundState.itemPower) do
			if power.Connection and power.Connection.Connected then
				power.Connection:Disconnect()
			end
		end
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
		doRoundState.autoSpiritBoxLease = false
		doRoundState.questionsActive = false
		refreshAutoSpiritBoxEnabled()
		doRoundState.thread = nil
		doRoundState.startedAt = nil
		doRoundState.roundMap = nil
		doRoundState.roundGhost = nil
		setDoRoundStatus(finalPhase or "Off")
	end
	return doRoundState.enabled
end
	return setEnabled
end)()
	return {
		SetEnabled = setDoRoundEnabled,
	}
end
