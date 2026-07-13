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
	local distanceFromPositionToInstance: any = assert(dependencies.DistanceFromPositionToInstance, "round-automation requires DistanceFromPositionToInstance")
	local characterIsFullyInsideRoom: any = assert(dependencies.CharacterIsFullyInsideRoom, "round-automation requires CharacterIsFullyInsideRoom")
	local worldItemIsFullyInsideRoom: any = assert(dependencies.WorldItemIsFullyInsideRoom, "round-automation requires WorldItemIsFullyInsideRoom")
	local worldItemIsInsideRoomBounds: any = assert(
		dependencies.WorldItemIsInsideRoomBounds,
		"round-automation requires WorldItemIsInsideRoomBounds"
	)
	local worldItemIsBurntCross: any = assert(dependencies.WorldItemIsBurntCross, "round-automation requires WorldItemIsBurntCross")
	local findExitDoorDescriptors: any = assert(dependencies.FindExitDoorDescriptors, "round-automation requires FindExitDoorDescriptors")
	local instanceBelongsToExitDoor: any = assert(dependencies.InstanceBelongsToExitDoor, "round-automation requires InstanceBelongsToExitDoor")
	local teleportToRoomBoundingBoxCenter: any = assert(dependencies.TeleportToRoom, "round-automation requires TeleportToRoom")
	local teleportToBaseCamp: any = assert(dependencies.TeleportToBaseCamp, "round-automation requires TeleportToBaseCamp")
	local teleportToFavouriteRoom: any = assert(dependencies.TeleportToFavouriteRoom, "round-automation requires TeleportToFavouriteRoom")
	local placeItemsInFavouriteRoom: any = assert(dependencies.PlaceItemsInFavouriteRoom, "round-automation requires PlaceItemsInFavouriteRoom")
	local doRoundState: any = assert(dependencies.State, "round-automation requires State")
	local perkTrackerState: any = assert(dependencies.PerkTrackerState, "round-automation requires PerkTrackerState")
	local roomItemPlacementState: any = assert(dependencies.RoomItemPlacementState, "round-automation requires RoomItemPlacementState")
	local GhostSession: any = assert(dependencies.GhostSession, "round-automation requires GhostSession")
	local getGhostSessionInput: any = assert(
		dependencies.GetGhostSessionInput,
		"round-automation requires GetGhostSessionInput"
	)
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
local ROUND_DOOR_MAX_PLAYER_DISTANCE = 2
local ROUND_DOOR_STAND_DISTANCE = 1.9
local ROUND_PLACEMENT_MAX_PLAYER_DISTANCE = 2
local ROUND_PICKUP_MAX_DISTANCE = 8
local ROUND_CHARACTER_FACING_DOT = 0.995
local ROUND_CAMERA_FACING_DOT = 0.995
local ROUND_WIDE_AXIS_DOT_MAX = 0.05
local ROUND_PREVIEW_AXIS_DOT = 0.995
local ROUND_PLACEMENT_SETTLE_SECONDS = 0.35
local ROUND_PLACEMENT_SETTLE_RENDER_PASSES = 5
local ROUND_PLACEMENT_SETTLE_HEARTBEATS = 3
local ROUND_PLACEMENT_PREVIEW_DRIFT = 0.12
local ROUND_PLACEMENT_ROOT_DRIFT = 0.08
local ROUND_PLACEMENT_DOOR_DRIFT = 0.05
local roundDoorFacingLockSequence = 0

local function normalizeRoundItemName(value)
	local normalized = string.lower(tostring(value or ""))
		:match("^%s*(.-)%s*$")
		:gsub("%s+", " ")
	if normalized == "holyoil" or normalized == "hoil oil" then
		return "holy oil"
	end
	return normalized
end

local function roundItemName(model)
	return model and (model:GetAttribute("ItemName") or model.Name) or nil
end

local function roundWorkspaceItemName(model)
	local items = workspace:FindFirstChild("Items")
	if not items
		or not model
		or model.Parent ~= items
		or not model:IsA("Model") then
		return nil
	end
	local storedName = model:GetAttribute("ItemName")
	if typeof(storedName) ~= "string" or storedName == "" then
		return nil
	end
	return storedName
end

local roundInventory: any = {}
local roundActionIsSafe
local roundUnsafeReason

roundInventory.IsBurntCross = function(model)
	return worldItemIsBurntCross(model)
end

roundInventory.DirectModels = function(container, itemName, includeBurntCross)
	local matches = {}
	local normalized = itemName and normalizeRoundItemName(itemName) or nil
	if not container then
		return matches
	end
	for _, child in ipairs(container:GetChildren()) do
		local storedName = child:IsA("Model") and child:GetAttribute("ItemName")
		if typeof(storedName) == "string"
			and storedName ~= ""
			and (not normalized
				or normalizeRoundItemName(storedName) == normalized)
			and (includeBurntCross == true
				or not roundInventory.IsBurntCross(child)) then
			table.insert(matches, child)
		end
	end
	return matches
end

roundInventory.ObjectMatchesSlotValue = function(model, slotValue)
	if not model
		or slotValue == nil
		or slotValue == false
		or tostring(slotValue) == "" then
		return false
	end
	local target = tostring(slotValue)
	if tostring(model.Name) == target then
		return true
	end
	for _, value in pairs(model:GetAttributes()) do
		if (typeof(value) == "string" or typeof(value) == "number")
			and tostring(value) == target then
			return true
		end
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if tostring(descendant.Name) == target then
			return true
		end
		for _, value in pairs(descendant:GetAttributes()) do
			if (typeof(value) == "string" or typeof(value) == "number")
				and tostring(value) == target then
				return true
			end
		end
	end
	return false
end

roundInventory.ModelSlot = function(model)
	if not model then
		return nil
	end
	for _, attributeName in ipairs({
		"InvSlot",
		"InventorySlot",
		"Slot",
		"SlotNumber",
	}) do
		local value = model:GetAttribute(attributeName)
		local slotNumber = tonumber(tostring(value or ""):match("%d+"))
		if slotNumber and slotNumber >= 1 and slotNumber <= 3 then
			return slotNumber
		end
	end
	local equippedObject = player:GetAttribute("EquippedObject")
	for slotNumber = 1, 3 do
		local slotValue = player:GetAttribute("InvSlot" .. tostring(slotNumber))
		if roundInventory.ObjectMatchesSlotValue(model, slotValue)
			or (player.Character
				and model:IsDescendantOf(player.Character)
				and equippedObject ~= nil
				and slotValue == equippedObject) then
			return slotNumber
		end
	end
	return nil
end

roundInventory.LabeledSlot = function(itemName)
	local normalized = normalizeRoundItemName(itemName)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hotbar = playerGui and playerGui:FindFirstChild("Hotbar")
	local slots = hotbar and hotbar:FindFirstChild("Slots")
	if not slots then
		return nil
	end
	for slotNumber = 1, 3 do
		local slot = slots:FindFirstChild("InvSlot" .. tostring(slotNumber))
		local label = slot and slot:FindFirstChild("ItemName")
		if label and label:IsA("TextLabel")
			and normalizeRoundItemName(label.Text) == normalized then
			return slotNumber
		end
	end
	return nil
end

roundInventory.SlotCandidates = function(itemName)
	local normalized = normalizeRoundItemName(itemName)
	local matchingModels = {}
	for _, container in ipairs({
		player.Character,
		player:FindFirstChild("ToolsHolder"),
	}) do
		for _, model in ipairs(roundInventory.DirectModels(container, normalized, false)) do
			table.insert(matchingModels, model)
		end
	end
	if #matchingModels == 0 then
		return {}
	end

	local candidates = {}
	local added = {}
	local function add(slotNumber)
		if slotNumber and slotNumber >= 1 and slotNumber <= 3
			and not added[slotNumber] then
			added[slotNumber] = true
			table.insert(candidates, slotNumber)
		end
	end
	for _, model in ipairs(matchingModels) do
		add(roundInventory.ModelSlot(model))
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hotbar = playerGui and playerGui:FindFirstChild("Hotbar")
	local slots = hotbar and hotbar:FindFirstChild("Slots")
	if slots then
		for slotNumber = 1, 3 do
			local slot = slots:FindFirstChild("InvSlot" .. tostring(slotNumber))
			local label = slot and slot:FindFirstChild("ItemName")
			if label and label:IsA("TextLabel")
				and normalizeRoundItemName(label.Text) == normalized then
				add(slotNumber)
			end
		end
	end
	-- Opaque slot identifiers cannot always be joined to the model. Try
	-- replicated occupied slots before blank/stale slots; callers confirm the
	-- actual Character model after every equip attempt.
	for slotNumber = 1, 3 do
		local value = player:GetAttribute("InvSlot" .. tostring(slotNumber))
		if value ~= nil and value ~= false and tostring(value) ~= "" then
			add(slotNumber)
		end
	end
	for slotNumber = 1, 3 do
		add(slotNumber)
	end
	return candidates
end

local function findRoundHotbarSlot(itemName)
	return roundInventory.SlotCandidates(itemName)[1]
end

local function getRoundEquippedItem(itemName)
	local character = player.Character
	if not character then
		return nil
	end
	return roundInventory.DirectModels(character, itemName, false)[1]
end

roundInventory.CountSlots = function()
	local occupiedSlots = {}
	local directClaimedSlots = {}
	local unmappedModels = {}
	for _, container in ipairs({
		player.Character,
		player:FindFirstChild("ToolsHolder"),
	}) do
		for _, model in ipairs(
			roundInventory.DirectModels(container, nil, true)
		) do
			local slotNumber = roundInventory.ModelSlot(model)
			if slotNumber then
				occupiedSlots[slotNumber] = true
				directClaimedSlots[slotNumber] = true
			else
				table.insert(unmappedModels, model)
			end
		end
	end
	for slotNumber = 1, 3 do
		local value = player:GetAttribute("InvSlot" .. tostring(slotNumber))
		if value ~= nil and value ~= false and tostring(value) ~= "" then
			occupiedSlots[slotNumber] = true
		end
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local hotbar = playerGui and playerGui:FindFirstChild("Hotbar")
	local slots = hotbar and hotbar:FindFirstChild("Slots")
	local hotbarNames = {}
	if slots then
		for slotNumber = 1, 3 do
			local slot = slots:FindFirstChild("InvSlot" .. tostring(slotNumber))
			local label = slot and slot:FindFirstChild("ItemName")
			if label and label:IsA("TextLabel") and label.Text ~= "" then
				occupiedSlots[slotNumber] = true
				hotbarNames[slotNumber] = normalizeRoundItemName(label.Text)
			end
		end
	end
	-- Match opaque physical models to replicated slot state before counting.
	-- Character/ToolsHolder models remain authoritative without inflating the
	-- same physical tool once through the model and again through the hotbar.
	for _, model in ipairs(unmappedModels) do
		local normalized = normalizeRoundItemName(roundItemName(model))
		local reconciledSlot
		for slotNumber = 1, 3 do
			if occupiedSlots[slotNumber]
				and not directClaimedSlots[slotNumber]
				and hotbarNames[slotNumber] == normalized then
				reconciledSlot = slotNumber
				break
			end
		end
		if not reconciledSlot then
			for slotNumber = 1, 3 do
				if not occupiedSlots[slotNumber] then
					reconciledSlot = slotNumber
					occupiedSlots[slotNumber] = true
					break
				end
			end
		end
		if reconciledSlot then
			directClaimedSlots[reconciledSlot] = true
		end
	end
	local occupiedCount = 0
	for slotNumber = 1, 3 do
		if occupiedSlots[slotNumber] then
			occupiedCount = occupiedCount + 1
		end
	end
	return occupiedCount
end

local function waitAfterRoundRemote(generation)
	local deadline = os.clock() + 0.1
	repeat
		if generation ~= nil
			and (not runtimeIsActive()
				or not doRoundState.enabled
				or doRoundState.generation ~= generation) then
			return false, "Do-Round cancelled"
		end
		task.wait(math.min(0.05, math.max(0, deadline - os.clock())))
	until os.clock() >= deadline
	return true
end

local function fireRoundRemote(remote, generation, ...)
	local fired, fireError = pcall(remote.FireServer, remote, ...)
	if not fired then
		return false, tostring(fireError), false
	end
	local delayed, delayReason = waitAfterRoundRemote(generation)
	if not delayed then
		return false, delayReason, true
	end
	return true, nil, true
end

local equipRoundItem: any = function(itemName, timeout, generation)
	local equipped = getRoundEquippedItem(itemName)
	if equipped then
		local exactSlot = roundInventory.ModelSlot(equipped)
		if exactSlot then
			return equipped, nil, exactSlot
		end
	end
	local candidates = roundInventory.SlotCandidates(itemName)
	if #candidates == 0 then
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
	local deadline = os.clock() + math.max(timeout or 1.5, 3)
	local lastReason
	if equipped then
		-- Presence before a probe cannot confirm a candidate: equipping a blank
		-- slot may no-op and leave the same model in Character. Establish an
		-- attributable baseline by switching away first.
		local switchedAway = false
		for _, slotNumber in ipairs(candidates) do
			if os.clock() >= deadline then
				break
			end
			if not roundActionIsSafe(generation) then
				return nil, roundUnsafeReason(generation)
			end
			local fired, fireReason = fireRoundRemote(
				remote,
				generation,
				"InvSlot" .. tostring(slotNumber)
			)
			if not fired then
				lastReason = fireReason
				continue
			end
			local switchDeadline = math.min(deadline, os.clock() + 0.35)
			repeat
				if not roundActionIsSafe(generation) then
					return nil, roundUnsafeReason(generation)
				end
				local current = getRoundEquippedItem(itemName)
				if not current then
					switchedAway = true
					break
				end
				local resolvedSlot = roundInventory.ModelSlot(current)
				if resolvedSlot then
					return current, nil, resolvedSlot
				end
				task.wait(0.05)
			until os.clock() >= switchDeadline
			if switchedAway then
				break
			end
		end
		if not switchedAway and not getRoundEquippedItem(itemName) then
			switchedAway = true
		end
		if not switchedAway then
			-- The equipped tool remains usable for salt/oil placement, but its slot
			-- is intentionally unconfirmed so maintenance will not drop another item.
			return equipped, nil, nil
		end
		equipped = nil
	end
	for _, slotNumber in ipairs(candidates) do
		if os.clock() >= deadline then
			break
		end
		if not roundActionIsSafe(generation) then
			return nil, roundUnsafeReason(generation)
		end
		local fired, fireReason = fireRoundRemote(
			remote,
			generation,
			"InvSlot" .. tostring(slotNumber)
		)
		if fired then
			local attemptDeadline = math.min(deadline, os.clock() + 0.3)
			repeat
				if not roundActionIsSafe(generation) then
					return nil, roundUnsafeReason(generation)
				end
				equipped = getRoundEquippedItem(itemName)
				if equipped then
					return equipped, nil, slotNumber
				end
				task.wait(0.05)
			until os.clock() >= attemptDeadline or not runtimeIsActive()
		else
			lastReason = fireReason
		end
	end
	if lastReason then
		return nil, lastReason
	end
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

local function horizontalUnit(vector, fallback)
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude < 0.05 then
		return fallback
	end
	return horizontal.Unit
end

local function roundDoorReference(target)
	if not target then
		return nil
	end
	if target:IsA("BasePart") then
		return target
	end
	local doorUnion = target:FindFirstChild("DoorUnion", true)
	if doorUnion and doorUnion:IsA("BasePart") then
		return doorUnion
	end
	if not target:IsA("Model") then
		return target:FindFirstChildWhichIsA("BasePart", true)
	end
	local named = target:FindFirstChild("Door", true)
	if named and named:IsA("BasePart") then
		return named
	end
	if target.PrimaryPart then
		return target.PrimaryPart
	end
	local bestPart
	local bestScore = -math.huge
	for _, descendant in ipairs(target:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local wide = math.max(descendant.Size.X, descendant.Size.Z)
			local thin = math.max(math.min(descendant.Size.X, descendant.Size.Z), 0.05)
			local score = wide * math.max(descendant.Size.Y, 0.1) / thin
			if score > bestScore then
				bestScore = score
				bestPart = descendant
			end
		end
	end
	return bestPart
end

local function roundDoorGeometry(target)
	local reference = roundDoorReference(target)
	local frame, size = roundTargetCFrame(reference)
	if not frame or not size then
		return nil
	end
	local right = horizontalUnit(frame.RightVector, Vector3.new(1, 0, 0))
	local look = horizontalUnit(frame.LookVector, Vector3.new(0, 0, -1))
	local wideAxis
	local normalAxis
	local wideLength
	local thickness
	local usesDoorUnionOrientation = string.lower(reference.Name)
		== "doorunion"
	if size.X >= size.Z then
		wideAxis = right
		normalAxis = look
		wideLength = size.X
		thickness = size.Z
	else
		wideAxis = look
		normalAxis = right
		wideLength = size.Z
		thickness = size.X
	end
	local maximumDistance = ROUND_DOOR_STAND_DISTANCE
	local minimumDistance = math.min(
		math.max(thickness * 0.5 + 1.1, 1.25),
		maximumDistance
	)
	local standDistance = math.clamp(
		thickness * 0.5 + 1.55,
		minimumDistance,
		maximumDistance
	)
	return {
		Reference = reference,
		DoorUnionOrientation = usesDoorUnionOrientation
			and reference.Orientation
			or nil,
		Frame = frame,
		Center = frame.Position,
		WideAxis = wideAxis,
		NormalAxis = normalAxis,
		WideLength = wideLength,
		Thickness = thickness,
		StandDistance = standDistance,
		MinimumDistance = minimumDistance,
		MaximumDistance = maximumDistance,
	}
end

local function roundDoorApproaches(target)
	local geometry = roundDoorGeometry(target)
	if not geometry then
		return {}, nil, nil
	end
	local approaches = {}
	for _, side in ipairs({1, -1}) do
		local positions = {}
		for _, adjustment in ipairs({0, -0.45, 0.45, -0.9, 0.9}) do
			local distance = math.clamp(
				geometry.StandDistance + adjustment,
				geometry.MinimumDistance,
				geometry.MaximumDistance
			)
			table.insert(
				positions,
				geometry.Center + geometry.NormalAxis * side * distance
			)
		end
		table.insert(approaches, {
			Side = side,
			Position = positions[1],
			CandidatePositions = positions,
			Facing = geometry.NormalAxis * -side,
			Geometry = geometry,
		})
	end
	return approaches, geometry.Center, geometry
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

local function teleportNearRoundTarget(
	target,
	preferredPosition,
	generation,
	maximumTargetDistance
)
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
		MaximumTargetDistance = maximumTargetDistance or 9.25,
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

local function teleportToRoundDoorFace(target, approach, generation)
	local geometry = approach and approach.Geometry
	local preferred = approach and approach.CandidatePositions
	if not geometry or not preferred or #preferred == 0 then
		return false, "door face geometry was unavailable"
	end
	local room = roomForRoundTarget(target, preferred)
	if not room then
		return false, "no room bounding box was found at the door face"
	end
	return teleportToRoomBoundingBoxCenter(room, {
		PreferredPositions = preferred,
		TargetPosition = geometry.Center,
		MaximumTargetDistance = ROUND_DOOR_MAX_PLAYER_DISTANCE,
		MaximumPreferredDistance = 0.95,
		LookDirection = approach.Facing,
		RequireStrict = true,
		CandidateValidator = function(position)
			local relative = Vector3.new(
				position.X - geometry.Center.X,
				0,
				position.Z - geometry.Center.Z
			)
			local lateral = math.abs(relative:Dot(geometry.WideAxis))
			local signedNormal = relative:Dot(geometry.NormalAxis)
			return relative.Magnitude <= ROUND_DOOR_MAX_PLAYER_DISTANCE
				and lateral <= 0.65
				and signedNormal * approach.Side > 0
				and math.abs(signedNormal) >= geometry.MinimumDistance - 0.1
				and math.abs(signedNormal) <= geometry.MaximumDistance
		end,
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
	local currentGhost = getGhostModel()
	return doRoundState.roundMap ~= nil
		and workspace:FindFirstChild("Map") == doRoundState.roundMap
		and doRoundState.roundGhost ~= nil
		and (currentGhost == nil or currentGhost == doRoundState.roundGhost)
end

roundActionIsSafe = function(generation)
	local currentGhost = getGhostModel()
	return (generation == nil
			or (runtimeIsActive()
				and doRoundState.enabled
				and doRoundState.generation == generation))
		and roundIdentityIsCurrent()
		and currentGhost == doRoundState.roundGhost
		and currentGhost:GetAttribute("Hunting") ~= true
		and player:GetAttribute("Dead") ~= true
end

roundUnsafeReason = function(generation)
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
	if getGhostModel() == nil then
		return "ghost unavailable"
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
	perkTrackerState.suppressRoomLightObservationsUntil = math.max(
		perkTrackerState.suppressRoomLightObservationsUntil or 0,
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
	local minimumSize = math.max(math.min(part.Size.X, part.Size.Z), 0.001)
	local aspectRatio = math.max(part.Size.X, part.Size.Z) / minimumSize
	return axis.Magnitude >= 0.05 and axis.Unit or nil, aspectRatio
end

local function roundDoorFacingContext(target)
	local geometry = roundDoorGeometry(target)
	local character = player.Character
	local root = character
		and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character
		and character:FindFirstChildOfClass("Humanoid")
	if not geometry or not character or not root or not humanoid then
		return nil, geometry, root
	end
	local rootOffset = Vector3.new(
		root.Position.X - geometry.Center.X,
		0,
		root.Position.Z - geometry.Center.Z
	)
	local signedNormal = rootOffset:Dot(geometry.NormalAxis)
	if math.abs(signedNormal) < 0.05
		or rootOffset.Magnitude > ROUND_DOOR_MAX_PLAYER_DISTANCE then
		return nil, geometry, root
	end
	local expectedFacing = geometry.NormalAxis
		* (signedNormal > 0 and -1 or 1)
	return {
		Target = target,
		Character = character,
		Root = root,
		Humanoid = humanoid,
		Geometry = geometry,
		ExpectedFacing = expectedFacing,
	}, geometry, root
end

local function enforceRoundDoorFacing(context)
	if not context
		or player.Character ~= context.Character
		or not context.Character.Parent
		or not context.Root.Parent
		or not context.Humanoid.Parent then
		return false
	end
	local root = context.Root
	local expectedFacing = context.ExpectedFacing
	local turned = pcall(function()
		local desiredRoot = CFrame.lookAt(
			root.Position,
			root.Position + expectedFacing
		)
		local pivotOffset = root.CFrame:ToObjectSpace(
			context.Character:GetPivot()
		)
		context.Humanoid:Move(Vector3.zero, false)
		context.Character:PivotTo(desiredRoot * pivotOffset)
		root.CFrame = desiredRoot
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	if not turned then
		return false
	end
	local facing = Vector3.new(
		root.CFrame.LookVector.X,
		0,
		root.CFrame.LookVector.Z
	)
	return facing.Magnitude >= 0.05
		and facing.Unit:Dot(expectedFacing) >= ROUND_CHARACTER_FACING_DOT
		and math.abs(
			facing.Unit:Dot(context.Geometry.WideAxis)
		) <= ROUND_WIDE_AXIS_DOT_MAX
end

local function enforceRoundDoorCameraFacing(context)
	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end
	local oldLook = camera.CFrame.LookVector
	local oldHorizontal = Vector3.new(oldLook.X, 0, oldLook.Z)
	local expected = context.ExpectedFacing
	if oldHorizontal.Magnitude < 0.05 or expected.Magnitude < 0.05 then
		return false
	end
	oldHorizontal = oldHorizontal.Unit
	expected = expected.Unit
	local yawDelta = math.atan2(
		oldHorizontal:Cross(expected).Y,
		oldHorizontal:Dot(expected)
	)
	local position = camera.CFrame.Position
	local rotationOnly = camera.CFrame - position
	local rotated = pcall(function()
		camera.CFrame = CFrame.new(position)
			* CFrame.fromAxisAngle(Vector3.yAxis, yawDelta)
			* rotationOnly
	end)
	if not rotated then
		return false
	end
	local newLook = camera.CFrame.LookVector
	local newHorizontal = Vector3.new(newLook.X, 0, newLook.Z)
	return newHorizontal.Magnitude >= 0.05
		and newHorizontal.Unit:Dot(expected) >= ROUND_CAMERA_FACING_DOT
		and math.abs(
			newHorizontal.Unit:Dot(context.Geometry.WideAxis)
		) <= ROUND_WIDE_AXIS_DOT_MAX
end

local function facePlayerTowardRoundDoor(target)
	local context, geometry, root = roundDoorFacingContext(target)
	return enforceRoundDoorFacing(context), geometry, root
end

local function beginRoundDoorFacingLock(target)
	local context = roundDoorFacingContext(target)
	if not context then
		return nil, "player could not face the door"
	end
	local lock = {
		Context = context,
		OriginalAutoRotate = context.Humanoid.AutoRotate,
		Released = false,
		Connections = {},
		RenderStepName = nil,
		HeartbeatPass = 0,
		RenderPass = 0,
	}
	function lock:Enforce()
		if self.Released then
			return false
		end
		local refreshed = roundDoorFacingContext(self.Context.Target)
		if not refreshed
			or refreshed.Character ~= self.Context.Character
			or refreshed.Root ~= self.Context.Root
			or refreshed.Humanoid ~= self.Context.Humanoid then
			return false
		end
		self.Context.Geometry = refreshed.Geometry
		self.Context.ExpectedFacing = refreshed.ExpectedFacing
		local contextIsCurrent = player.Character == self.Context.Character
			and self.Context.Character.Parent
			and self.Context.Root.Parent
			and self.Context.Humanoid.Parent
		if not contextIsCurrent then
			return false
		end
		local disabled = pcall(function()
			self.Context.Humanoid.AutoRotate = false
		end)
		if not disabled then
			return false
		end
		return enforceRoundDoorFacing(self.Context)
			and enforceRoundDoorCameraFacing(self.Context)
	end
	function lock:Release()
		if self.Released then
			return
		end
		self.Released = true
		for _, connection in ipairs(self.Connections) do
			if connection.Connected then
				connection:Disconnect()
			end
		end
		if self.RenderStepName then
			pcall(function()
				Services.RunService:UnbindFromRenderStep(
					self.RenderStepName
				)
			end)
		end
		local humanoid = self.Context.Humanoid
		if humanoid.Parent
			and player.Character == self.Context.Character then
			pcall(function()
				humanoid.AutoRotate = self.OriginalAutoRotate
			end)
		end
	end
	local disabled = pcall(function()
		context.Humanoid.AutoRotate = false
	end)
	if not disabled then
		return nil, "player facing lock could not disable AutoRotate"
	end
	local preSimulationConnected, preSimulationConnection = pcall(function()
		return Services.RunService.PreSimulation:Connect(function()
			if not lock:Enforce() then
				lock:Release()
			end
		end)
	end)
	local heartbeatConnected, heartbeatConnection = pcall(function()
		return Services.RunService.Heartbeat:Connect(function()
			if lock:Enforce() then
				lock.HeartbeatPass = lock.HeartbeatPass + 1
			else
				lock:Release()
			end
		end)
	end)
	if preSimulationConnected then
		table.insert(lock.Connections, preSimulationConnection)
	end
	if heartbeatConnected then
		table.insert(lock.Connections, heartbeatConnection)
	end
	if not preSimulationConnected or not heartbeatConnected then
		lock:Release()
		return nil, "player facing lock could not bind to simulation"
	end
	roundDoorFacingLockSequence = roundDoorFacingLockSequence + 1
	lock.RenderStepName = "DemonologyDoorFacing_"
		.. tostring(roundDoorFacingLockSequence)
	local renderBound = pcall(function()
		Services.RunService:BindToRenderStep(
			lock.RenderStepName,
			Enum.RenderPriority.Camera.Value + 1,
			function()
				if lock:Enforce() then
					lock.RenderPass = lock.RenderPass + 1
				else
					lock:Release()
				end
			end
		)
	end)
	if not renderBound then
		lock:Release()
		return nil, "player facing lock could not bind after the camera"
	end
	if not lock:Enforce() then
		lock:Release()
		return nil, "player facing lock could not rotate the character"
	end
	return lock
end

local function playerHasDoorPlacementGeometry(target)
	local geometry = roundDoorGeometry(target)
	local root = player.Character
		and player.Character:FindFirstChild("HumanoidRootPart")
	if not geometry or not root then
		return false, geometry, root
	end
	local rootOffset = Vector3.new(
		root.Position.X - geometry.Center.X,
		0,
		root.Position.Z - geometry.Center.Z
	)
	local rootLateral = math.abs(rootOffset:Dot(geometry.WideAxis))
	local rootNormal = rootOffset:Dot(geometry.NormalAxis)
	if rootOffset.Magnitude > ROUND_DOOR_MAX_PLAYER_DISTANCE
		or rootLateral > 0.65
		or math.abs(rootNormal) < geometry.MinimumDistance - 0.15
		or math.abs(rootNormal) > geometry.MaximumDistance then
		return false, geometry, root
	end
	local facing = Vector3.new(
		root.CFrame.LookVector.X,
		0,
		root.CFrame.LookVector.Z
	)
	local expectedFacing = geometry.NormalAxis * (rootNormal > 0 and -1 or 1)
	return facing.Magnitude >= 0.05
		and facing.Unit:Dot(expectedFacing) >= ROUND_CHARACTER_FACING_DOT
		and math.abs(facing.Unit:Dot(geometry.WideAxis))
			<= ROUND_WIDE_AXIS_DOT_MAX,
		geometry,
		root
end

local placementPreviewIsAligned: any = function(toolName, target)
	local camera = workspace.CurrentCamera
	local previewName = toolName == "Salt Canister" and "SaltLine" or "HolyOil"
	local partName = toolName == "Salt Canister" and "Salt" or "Center"
	local preview = camera and camera:FindFirstChild(previewName)
	local previewPart = preview and preview:FindFirstChild(partName, true)
	local playerAligned, geometry, root =
		playerHasDoorPlacementGeometry(target)
	if not previewPart or not previewPart:IsA("BasePart")
		or not playerAligned or not geometry or not root then
		return false
	end
	local previewOffset = Vector3.new(
		previewPart.Position.X - geometry.Center.X,
		0,
		previewPart.Position.Z - geometry.Center.Z
	)
	local previewPlayerOffset = Vector3.new(
		previewPart.Position.X - root.Position.X,
		0,
		previewPart.Position.Z - root.Position.Z
	)
	local doorPlayerOffset = Vector3.new(
		geometry.Center.X - root.Position.X,
		0,
		geometry.Center.Z - root.Position.Z
	)
	if previewPlayerOffset.Magnitude
		> ROUND_PLACEMENT_MAX_PLAYER_DISTANCE
		or doorPlayerOffset.Magnitude < 0.05
		or previewPlayerOffset:Dot(doorPlayerOffset.Unit) <= 0 then
		return false
	end
	local maximumDoorNormalOffset = math.min(
		math.max(geometry.Thickness * 0.5 + 0.5, 0.75),
		1.25
	)
	if math.abs(previewOffset:Dot(geometry.WideAxis)) > 0.9
		or math.abs(previewOffset:Dot(geometry.NormalAxis))
			> maximumDoorNormalOffset then
		return false
	end
	local previewAxis, previewAspectRatio = previewMajorAxis(previewPart)
	if not previewAspectRatio or previewAspectRatio < 1.15 then
		previewAxis = nil
	end
	if toolName == "Salt Canister"
		and previewAspectRatio and previewAspectRatio >= 1.15 then
		if not previewAxis
			or math.abs(previewAxis:Dot(geometry.WideAxis))
				< ROUND_PREVIEW_AXIS_DOT then
			return false
		end
	end
	return true, previewPart, geometry, root, previewAxis
end

local waitForRoundPreview: any = function(
	toolName,
	target,
	generation,
	facingLock
)
	local deadline = os.clock() + 4.5
	local stableSince
	local stableRenderPasses = 0
	local stableHeartbeatPass
	local lastObservedRenderPass = -1
	local baseline
	repeat
		Services.RunService.RenderStepped:Wait()
		if not roundActionIsSafe(generation) then
			return false, roundUnsafeReason(generation)
		end
		if facingLock.Released then
			return false, "player facing lock was released before placement settled"
		end
		local renderPass = facingLock.RenderPass
		if renderPass <= lastObservedRenderPass then
			continue
		end
		lastObservedRenderPass = renderPass
		local enforced = facingLock:Enforce()
		local aligned, previewPart, geometry, root, previewAxis =
			placementPreviewIsAligned(toolName, target)
		if enforced and aligned and previewPart and geometry and root then
			local snapshot = {
				PreviewPosition = previewPart.Position,
				PreviewAxis = previewAxis,
				RootPosition = root.Position,
				DoorCenter = geometry.Center,
				DoorNormal = geometry.NormalAxis,
			}
			local remainedStable = not baseline
				or ((snapshot.PreviewPosition - baseline.PreviewPosition).Magnitude
					<= ROUND_PLACEMENT_PREVIEW_DRIFT
					and (snapshot.RootPosition - baseline.RootPosition).Magnitude
						<= ROUND_PLACEMENT_ROOT_DRIFT
					and (snapshot.DoorCenter - baseline.DoorCenter).Magnitude
						<= ROUND_PLACEMENT_DOOR_DRIFT
					and snapshot.DoorNormal:Dot(baseline.DoorNormal) >= 0.999
					and (not snapshot.PreviewAxis
						or not baseline.PreviewAxis
						or math.abs(
							snapshot.PreviewAxis:Dot(baseline.PreviewAxis)
						) >= 0.998))
			if not remainedStable then
				stableSince = nil
				stableRenderPasses = 0
				stableHeartbeatPass = nil
				baseline = nil
			end
			if not baseline then
				baseline = snapshot
				stableSince = os.clock()
				stableHeartbeatPass = facingLock.HeartbeatPass
			end
			stableRenderPasses = stableRenderPasses + 1
			if stableRenderPasses >= ROUND_PLACEMENT_SETTLE_RENDER_PASSES
				and facingLock.HeartbeatPass - stableHeartbeatPass
					>= ROUND_PLACEMENT_SETTLE_HEARTBEATS
				and os.clock() - stableSince
					>= ROUND_PLACEMENT_SETTLE_SECONDS then
				return true, nil, renderPass
			end
		else
			stableSince = nil
			stableRenderPasses = 0
			stableHeartbeatPass = nil
			baseline = nil
		end
	until os.clock() >= deadline
	return false,
		"placement preview and player rotation did not remain settled at the doorway"
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
	local uses = tonumber(equipped:GetAttribute("Uses"))
	if uses == nil then
		local usesDeadline = os.clock() + 1.5
		repeat
			if not roundActionIsSafe(generation) then
				return false, roundUnsafeReason(generation)
			end
			doRoundWait(generation, 0.05)
			equipped = getRoundEquippedItem(toolName) or equipped
			uses = tonumber(equipped:GetAttribute("Uses"))
		until uses ~= nil or os.clock() >= usesDeadline
	end
	if uses == nil then
		return false, toolName .. " Uses attribute was unavailable"
	end
	if uses ~= nil and uses <= 0 then
		return false, toolName .. " has no uses remaining"
	end
	local remoteName = toolName == "Salt Canister"
		and "LaySaltPile"
		or "PourHolyOil"
	local folderName = toolName == "Salt Canister" and "SaltPiles" or "HolyOil"
	local placementFolder
	local existingPlacements = setmetatable({}, {__mode = "k"})
	local targetFrame
	local targetRoom
	local dispatchRootPosition
	local dispatchAccepted = false
	local dispatchFailure
	local facingLock, facingReason = beginRoundDoorFacingLock(target)
	if not facingLock then
		return false, facingReason
	end
	local guarded, guardedFailure = xpcall(function()
		local aligned, alignReason, settledRenderPass = waitForRoundPreview(
			toolName,
			target,
			generation,
			facingLock
		)
		if not aligned then
			dispatchFailure = alignReason
			return
		end
		local events = Services.ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild(remoteName)
		if not remote or not remote:IsA("RemoteEvent") then
			dispatchFailure = remoteName .. " RemoteEvent was not found"
			return
		end
		if facingLock.RenderPass ~= settledRenderPass
			or not facingLock:Enforce()
			or not placementPreviewIsAligned(toolName, target) then
			dispatchFailure =
				"placement preview lost door alignment before dispatch"
			return
		end
		local previewAligned, previewPart =
			placementPreviewIsAligned(toolName, target)
		targetRoom = previewAligned
			and previewPart
			and roomForRoundTarget(target, {previewPart.Position})
			or nil
		if not targetRoom
			or not worldItemIsFullyInsideRoom(previewPart, targetRoom) then
			dispatchFailure =
				"placement preview was outside every room bounding box"
			return
		end
		local dispatchEquipped = getRoundEquippedItem(toolName)
		local dispatchUses = dispatchEquipped
			and tonumber(dispatchEquipped:GetAttribute("Uses"))
		if not dispatchEquipped or dispatchUses == nil then
			dispatchFailure =
				toolName .. " Uses could not be verified before dispatch"
			return
		end
		if dispatchUses <= 0 then
			dispatchFailure = toolName .. " has no uses remaining"
			return
		end
		equipped = dispatchEquipped
		uses = dispatchUses
		if not roundActionIsSafe(generation) then
			dispatchFailure = roundUnsafeReason(generation)
			return
		end
		placementFolder = workspace:FindFirstChild(folderName)
		if placementFolder then
			for _, child in ipairs(placementFolder:GetChildren()) do
				existingPlacements[child] = true
			end
		end
		targetFrame = roundTargetCFrame(target)
		beginAutomationMutation(2.5)
		if facingLock.RenderPass ~= settledRenderPass
			or not facingLock:Enforce()
			or not placementPreviewIsAligned(toolName, target) then
			dispatchFailure =
				"player facing changed before placement dispatch"
			return
		end
		local dispatchRoot = player.Character
			and player.Character:FindFirstChild("HumanoidRootPart")
		if not dispatchRoot then
			dispatchFailure = "player root was unavailable before placement dispatch"
			return
		end
		dispatchRootPosition = dispatchRoot.Position
		local fired, fireReason, dispatched =
			fireRoundRemote(remote, generation)
		dispatchAccepted = dispatched == true
		if not fired then
			dispatchFailure = fireReason or remoteName .. " failed"
			return
		end
	end, debug.traceback)
	facingLock:Release()
	if not guarded then
		error(guardedFailure, 0)
	end
	if not dispatchAccepted then
		return false, dispatchFailure or remoteName .. " failed"
	end
	local deadline = os.clock() + 2
	local confirmed = false
	local lastObservedUses = uses
	repeat
		if not doRoundOperationActive(generation) then
			return false, "Do-Round cancelled", true
		end
		if not roundActionIsSafe(generation) then
			return false, roundUnsafeReason(generation), true
		end
		local currentEquipped = getRoundEquippedItem(toolName) or equipped
		local currentUses = tonumber(currentEquipped:GetAttribute("Uses"))
		if currentUses ~= nil then
			lastObservedUses = currentUses
		end
		placementFolder = workspace:FindFirstChild(folderName)
		if placementFolder then
			for _, child in ipairs(placementFolder:GetChildren()) do
				if not existingPlacements[child] then
					local position = getInstanceWorldPosition(child)
					if position and targetFrame and dispatchRootPosition and targetRoom
						and worldItemIsFullyInsideRoom(child, targetRoom)
						and (Vector3.new(position.X, 0, position.Z)
							- Vector3.new(
								targetFrame.Position.X,
								0,
								targetFrame.Position.Z
							)).Magnitude <= ROUND_DOOR_MAX_PLAYER_DISTANCE
						and (Vector3.new(position.X, 0, position.Z)
							- Vector3.new(
								dispatchRootPosition.X,
								0,
								dispatchRootPosition.Z
							)).Magnitude
							<= ROUND_PLACEMENT_MAX_PLAYER_DISTANCE then
						confirmed = true
						break
					end
				end
			end
			if confirmed then
				break
			end
		end
		task.wait(0.05)
	until os.clock() >= deadline
	local postDispatchCooldownDeadline = os.clock() + 6
	local cooldownCleared = false
	repeat
		if not doRoundOperationActive(generation) then
			return false, "Do-Round cancelled", true, lastObservedUses
		end
		if not roundActionIsSafe(generation) then
			return false,
				roundUnsafeReason(generation),
				true,
				lastObservedUses
		end
		local currentEquipped = getRoundEquippedItem(toolName) or equipped
		local currentUses = tonumber(currentEquipped:GetAttribute("Uses"))
		if currentUses ~= nil then
			lastObservedUses = currentUses
		end
		if not currentEquipped.Parent
			or currentEquipped:GetAttribute("EquipDisabled") ~= true then
			cooldownCleared = true
			break
		end
		doRoundWait(generation, 0.05)
	until os.clock() >= postDispatchCooldownDeadline
	if not cooldownCleared then
		return false,
			toolName .. " placement cooldown did not clear",
			true,
			lastObservedUses
	end
	if not confirmed then
		return false,
			toolName .. " was dispatched but not confirmed",
			true,
			lastObservedUses
	end
	return true, nil, true, lastObservedUses
end
	return {
		DroppedRoomItems = DROPPED_ROOM_ITEMS,
		PoweredRoomItems = POWERED_ROOM_ITEMS,
		HeldItems = ROUND_HELD_ITEMS,
		PickupMaxDistance = ROUND_PICKUP_MAX_DISTANCE,
		NormalizeItemName = normalizeRoundItemName,
		ItemName = roundItemName,
		WorkspaceItemName = roundWorkspaceItemName,
		FindHotbarSlot = findRoundHotbarSlot,
		SlotCandidates = roundInventory.SlotCandidates,
		GetEquippedItem = getRoundEquippedItem,
		EquipItem = equipRoundItem,
		ApproachPositions = roundApproachPositions,
		TargetCFrame = roundTargetCFrame,
		ResolveDoorReference = roundDoorReference,
		DoorGeometry = roundDoorGeometry,
		DoorApproaches = roundDoorApproaches,
		TeleportNearTarget = teleportNearRoundTarget,
		TeleportToDoorFace = teleportToRoundDoorFace,
		FacePlayerToDoor = facePlayerTowardRoundDoor,
		Shuffle = shuffleRoundList,
		IsHunting = roundIsHunting,
		IdentityIsCurrent = roundIdentityIsCurrent,
		ActionIsSafe = roundActionIsSafe,
		UnsafeReason = roundUnsafeReason,
		OperationActive = doRoundOperationActive,
		Wait = doRoundWait,
		BeginMutation = beginAutomationMutation,
		FireRemote = fireRoundRemote,
		IsBurntCross = roundInventory.IsBurntCross,
		DirectInventoryModels = roundInventory.DirectModels,
		CountInventorySlots = roundInventory.CountSlots,
		FirePlaceable = fireRoundPlaceable,
	}
end)()

local setDoRoundEnabled = (function()
	local DROPPED_ROOM_ITEMS = roundUtilities.DroppedRoomItems
	local POWERED_ROOM_ITEMS = roundUtilities.PoweredRoomItems
	local ROUND_HELD_ITEMS = roundUtilities.HeldItems
	local ROUND_PICKUP_MAX_DISTANCE = roundUtilities.PickupMaxDistance
	local normalizeRoundItemName = roundUtilities.NormalizeItemName
	local roundItemName = roundUtilities.ItemName
	local roundWorkspaceItemName = roundUtilities.WorkspaceItemName
	local findRoundHotbarSlot = roundUtilities.FindHotbarSlot
	local roundSlotCandidates = roundUtilities.SlotCandidates
	local getRoundEquippedItem = roundUtilities.GetEquippedItem
	local equipRoundItem = roundUtilities.EquipItem
	local roundApproachPositions = roundUtilities.ApproachPositions
	local roundTargetCFrame = roundUtilities.TargetCFrame
	local roundDoorReference = roundUtilities.ResolveDoorReference
	local roundDoorGeometry = roundUtilities.DoorGeometry
	local roundDoorApproaches = roundUtilities.DoorApproaches
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
	local beginAutomationMutation = roundUtilities.BeginMutation
	local fireRoundRemote = roundUtilities.FireRemote
	local roundCrossIsBurnt = roundUtilities.IsBurntCross
	local roundDirectInventoryModels = roundUtilities.DirectInventoryModels
	local countRoundInventorySlots = roundUtilities.CountInventorySlots
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
	if includeExit then
		return findExitDoorDescriptors()
	end
	local folder = workspace:FindFirstChild("Doors")
	local doors: any = {}
	if not folder then
		return doors
	end
	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model")
			and not instanceBelongsToExitDoor(model) then
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

local function roundDoorClosedState(doorModel, doorContainer)
	local doors = workspace:FindFirstChild("Doors")
	local seen = setmetatable({}, {__mode = "k"})
	for _, start in ipairs({doorContainer, doorModel}) do
		local current = start
		while current and current ~= workspace and not seen[current] do
			seen[current] = true
			local value = current:GetAttribute("DoorClosed")
			if typeof(value) == "boolean" then
				return value, current
			end
			if current == doors then
				break
			end
			current = current.Parent
		end
	end
	return nil, nil
end

local function closeRoundDoor(doorModel, generation)
	local doorContainer = doorModel:FindFirstChild("Door") or doorModel
	local closed = roundDoorClosedState(doorModel, doorContainer)
	if closed == true then
		return true
	end
	if closed ~= false then
		return false, "DoorClosed state was unavailable"
	end
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local remote = events and events:FindFirstChild("ClientChangeDoorState")
	if not remote or not remote:IsA("RemoteEvent") then
		return false, "ClientChangeDoorState RemoteEvent was not found"
	end
	local doorReference = roundDoorReference(doorContainer) or doorContainer
	local approaches, center = roundDoorApproaches(doorReference)
	for _, approach in ipairs(shuffleRoundList(approaches)) do
		if not roundActionIsSafe(generation) then
			return false, roundUnsafeReason(generation)
		end
		local teleported = teleportToRoundDoorFace(
			doorReference,
			approach,
			generation
		)
		local root = player.Character
			and player.Character:FindFirstChild("HumanoidRootPart")
		if teleported and root and center
			and (root.Position - center).Magnitude <= 10 then
			closed = roundDoorClosedState(doorModel, doorContainer)
			if closed == true then
				return true
			end
			if closed ~= false then
				return false, "DoorClosed state became unavailable"
			end
			beginAutomationMutation(1.5)
			local fired, fireReason = fireRoundRemote(
				remote,
				generation,
				doorContainer
			)
			if not fired then
				return false, fireReason or "door close remote failed"
			end
			local deadline = os.clock() + 1.5
			repeat
				if not roundActionIsSafe(generation) then
					return false, roundUnsafeReason(generation)
				end
				closed = roundDoorClosedState(doorModel, doorContainer)
				if closed == true then
					doRoundWait(generation, 0.1)
					return true
				end
				if closed ~= false then
					return false, "DoorClosed state became unavailable"
				end
				doRoundWait(
					generation,
					math.min(0.05, math.max(0, deadline - os.clock()))
				)
			until os.clock() >= deadline
			return false, "door did not confirm closed"
		end
	end
	return false, "no safe door approach was available for closing"
end

local function placeRoundToolsAtDoors(generation)
	local warnings = {}
	local warningKeys = {}
	local function addWarning(key, message)
		if message and not warningKeys[key] then
			warningKeys[key] = true
			table.insert(warnings, message)
		end
	end
	local function selectDoor(toolKey, rejectedDoors)
		local doors = eligibleRoundDoors(false)
		if toolKey == "salt canister" then
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
					return string.lower(first.Name) < string.lower(second.Name)
				end
				return firstDistance < secondDistance
			end)
		end
		for _, doorModel in ipairs(doors) do
			local key = string.lower(tostring(doorModel.Name))
			if not rejectedDoors[doorModel]
				and not doRoundState.usedSaltDoorModels[doorModel]
				and not doRoundState.usedDoorNames[key] then
				return doorModel, key
			end
		end
		return nil, nil
	end

	local function processTool(toolName, maximumPlacements)
		local toolKey = normalizeRoundItemName(toolName)
		if doRoundState.completedDoorTools[toolKey] then
			return true
		end
		local rejectedDoors = setmetatable({}, {__mode = "k"})
		local successfulPlacements = 0
		local equipFailures = 0
		while doRoundOperationActive(generation) do
			if not roundActionIsSafe(generation) then
				return false, roundUnsafeReason(generation)
			end
			local equipped, reason = equipRoundItem(toolName, 1.5, generation)
			if not equipped then
				local cachedUses = doRoundState.doorToolUses[toolKey]
				if cachedUses ~= nil and cachedUses <= 0 then
					doRoundState.completedDoorTools[toolKey] = true
					return true
				end
				if not findRoundHotbarSlot(toolName) then
					addWarning(toolKey .. ":missing", reason)
					doRoundState.completedDoorTools[toolKey] = true
					return true
				end
				addWarning(toolKey .. ":equip", reason)
				equipFailures = equipFailures + 1
				if equipFailures >= 3 then
					return false,
						toolName .. " could not be equipped after three attempts: "
							.. tostring(reason)
				end
				doRoundWait(generation, 0.2)
				continue
			end
			equipFailures = 0
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
				addWarning(
					toolKey .. ":uses",
					toolName .. " Uses attribute was unavailable"
				)
				doRoundWait(generation, 0.2)
				continue
			end
			doRoundState.doorToolUses[toolKey] = uses
			if uses <= 0 then
				doRoundState.completedDoorTools[toolKey] = true
				return true
			end
			if maximumPlacements
				and successfulPlacements >= maximumPlacements then
				doRoundState.completedDoorTools[toolKey] = true
				return true
			end

			local selectedDoor, selectedKey = selectDoor(toolKey, rejectedDoors)
			if not selectedDoor then
				doRoundState.completedDoorTools[toolKey] = true
				addWarning(
					toolKey .. ":doors",
					toolName
						.. " still has Uses="
						.. tostring(uses)
						.. ", but every distinct non-exit door was already used or rejected"
				)
				return true
			end

			setDoRoundStatus(
				"Laying " .. toolName .. " (" .. tostring(uses) .. " left)"
			)
			local closed, closeReason = closeRoundDoor(selectedDoor, generation)
			if not closed then
				if closeReason == "hunt started"
					or closeReason == "ghost unavailable"
					or closeReason == "Do-Round cancelled" then
					return false, closeReason
				end
				rejectedDoors[selectedDoor] = true
				addWarning(
					toolKey .. ":close:" .. selectedKey,
					selectedDoor.Name .. " was skipped: " .. tostring(closeReason)
				)
				continue
			end
			-- Closing can rotate the DoorUnion; resolve all placement geometry again.
			local doorContainer =
				selectedDoor:FindFirstChild("Door") or selectedDoor
			local door = roundDoorReference(doorContainer) or doorContainer
			local approaches = roundDoorApproaches(door)
			local placed = false
			local placementReason
			local dispatched = false
			local observedUses
			for _, approach in ipairs(shuffleRoundList(approaches)) do
				if not roundActionIsSafe(generation) then
					return false, roundUnsafeReason(generation)
				end
				local teleported = teleportToRoundDoorFace(
					door,
					approach,
					generation
				)
				if teleported and facePlayerTowardRoundDoor(door) then
					doRoundWait(generation, 0.1)
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
			if placed then
				doRoundState.usedDoorNames[selectedKey] = true
				doRoundState.lastDoorName = selectedKey
				doRoundState.usedSaltDoorModels[selectedDoor] = true
				successfulPlacements = successfulPlacements + 1
				doRoundState.doorToolPlacements[toolKey] =
					(doRoundState.doorToolPlacements[toolKey] or 0) + 1
				if maximumPlacements
					and successfulPlacements >= maximumPlacements then
					doRoundState.completedDoorTools[toolKey] = true
					return true
				end
			elseif dispatched then
				-- A dispatched placement may replicate after a hunt/cancellation edge.
				-- Reserve the door conservatively so neither tool can double-place it.
				doRoundState.usedDoorNames[selectedKey] = true
				doRoundState.usedSaltDoorModels[selectedDoor] = true
				if maximumPlacements then
					doRoundState.completedDoorTools[toolKey] = true
				end
				if placementReason == "hunt started"
					or placementReason == "ghost unavailable"
					or placementReason == "Do-Round cancelled" then
					return false, placementReason
				end
				rejectedDoors[selectedDoor] = true
				addWarning(toolKey .. ":dispatch", placementReason)
				if maximumPlacements then
					return true
				end
			else
				if placementReason == "hunt started"
					or placementReason == "ghost unavailable"
					or placementReason == "Do-Round cancelled" then
					return false, placementReason
				end
				rejectedDoors[selectedDoor] = true
				addWarning(toolKey .. ":placement", placementReason)
			end
		end
		return false, "Do-Round cancelled"
	end

	-- Holy Oil is intentionally used once; Salt then stays equipped until its
	-- Uses reach zero or every distinct eligible door has been exhausted.
	local holyCompleted, holyReason = processTool("Holy Oil", 1)
	if not holyCompleted then
		return false, holyReason
	end
	local saltCompleted, saltReason = processTool("Salt Canister", nil)
	if not saltCompleted then
		return false, saltReason
	end
	return true, #warnings > 0 and table.concat(warnings, "; ") or nil
end

local function openRoundExitDoor(generation)
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local remote = events and events:FindFirstChild("ClientChangeDoorState")
	if not remote or not remote:IsA("RemoteEvent") then
		return false, "ClientChangeDoorState RemoteEvent was not found"
	end
	local exitDoors = eligibleRoundDoors(true)
	if #exitDoors == 0 then
		return false, "no ExitDoor marker or actionable Door container was found"
	end
	local function closedState(descriptor)
		for _, owner in ipairs({
			descriptor.StateOwner,
			descriptor.DoorContainer,
			descriptor.Entry,
		}) do
			if owner then
				local value = owner:GetAttribute("DoorClosed")
				if typeof(value) == "boolean" then
					return value
				end
			end
		end
		return nil
	end
	for _, descriptor in ipairs(exitDoors) do
		if closedState(descriptor) == false then
			return true
		end
		local doorContainer = descriptor.DoorContainer
		local doorReference = doorContainer
			and (roundDoorReference(doorContainer) or doorContainer)
		if doorContainer and doorReference then
			local approaches, center = roundDoorApproaches(doorReference)
			local dispatchAttempted = false
			for _, approach in ipairs(shuffleRoundList(approaches)) do
				if not roundActionIsSafe(generation) then
					return false, roundUnsafeReason(generation)
				end
				local teleported = teleportToRoundDoorFace(
					doorReference,
					approach,
					generation
				)
				local root = player.Character
					and player.Character:FindFirstChild("HumanoidRootPart")
				if teleported and root and center
					and (root.Position - center).Magnitude <= 10 then
					if not roundActionIsSafe(generation) then
						teleportToBaseCamp(roundTeleportOptions(generation))
						return false, roundUnsafeReason(generation)
					end
					if closedState(descriptor) == false then
						return true
					end
					local beforeFrame = roundTargetCFrame(doorReference)
					beginAutomationMutation(1.5)
					dispatchAttempted = true
					local fired = fireRoundRemote(
						remote,
						generation,
						doorContainer
					)
					if fired then
						local confirmationDeadline = os.clock() + 1.5
						repeat
							if not roundActionIsSafe(generation) then
								teleportToBaseCamp(roundTeleportOptions(generation))
								return false, roundUnsafeReason(generation)
							end
							local afterState = closedState(descriptor)
							local afterFrame = roundTargetCFrame(doorReference)
							local frameChanged = beforeFrame and afterFrame
								and ((afterFrame.Position - beforeFrame.Position).Magnitude > 0.05
									or afterFrame.LookVector:Dot(beforeFrame.LookVector) < 0.999)
							if afterState == false or frameChanged then
								return true
							end
							if os.clock() >= confirmationDeadline then
								break
							end
							doRoundWait(
								generation,
								math.min(0.05, confirmationDeadline - os.clock())
							)
						until false
					end
					break
				end
			end
			if dispatchAttempted and closedState(descriptor) == false then
				return true
			end
		end
	end
	return false, "ExitDoor did not open"
end

local function captureRoundRoomItems(room)
	local items = workspace:FindFirstChild("Items")
	if not room then
		return
	end
	for _, itemName in ipairs(DROPPED_ROOM_ITEMS) do
		local normalized = normalizeRoundItemName(itemName)
		local existing = doRoundState.roomItems[normalized]
		local existingIsPlaced = existing
			and existing.Parent
			and not roundCrossIsBurnt(existing)
			and normalizeRoundItemName(roundWorkspaceItemName(existing)) == normalized
			and worldItemIsInsideRoomBounds(existing, room)
		if not existingIsPlaced then
			doRoundState.roomItems[normalized] = nil
			local nearestFallback
			local nearestFallbackDistance = math.huge
			local candidates = items and items:GetChildren() or {}
			for _, container in ipairs({
				player.Character,
				player:FindFirstChild("ToolsHolder"),
			}) do
				for _, model in ipairs(
					roundDirectInventoryModels(container, itemName, false)
				) do
					table.insert(candidates, model)
				end
			end
			for _, model in ipairs(candidates) do
				local candidateName
				if items and model.Parent == items then
					candidateName = roundWorkspaceItemName(model)
				elseif model:IsA("Model") then
					candidateName = model:GetAttribute("ItemName")
				end
				if normalizeRoundItemName(candidateName) == normalized
					and not roundCrossIsBurnt(model) then
					if worldItemIsInsideRoomBounds(model, room) then
						doRoundState.roomItems[normalized] = model
						break
					end
					local distance = roundDoorDistanceToRoom(model, room)
					if distance < nearestFallbackDistance then
						nearestFallback = model
						nearestFallbackDistance = distance
					end
				end
			end
			doRoundState.roomItems[normalized] =
				doRoundState.roomItems[normalized] or nearestFallback
		end
	end
end

local REQUIRED_ROOM_ITEMS = {
	["spirit box"] = true,
	["laser projector"] = true,
	["flower pot"] = true,
}

local function roundRoomSetupRecoverable(targetRoom)
	if not targetRoom or not targetRoom.Parent then
		return false
	end
	local items = workspace:FindFirstChild("Items")
	for _, itemName in ipairs(DROPPED_ROOM_ITEMS) do
		local normalized = normalizeRoundItemName(itemName)
		local available = false
		local correctlyPlaced = false
		if items then
			for _, model in ipairs(items:GetChildren()) do
				if normalizeRoundItemName(roundWorkspaceItemName(model)) == normalized
					and not roundCrossIsBurnt(model) then
					available = true
					if worldItemIsInsideRoomBounds(model, targetRoom) then
						correctlyPlaced = true
					end
				end
			end
		end
		for _, container in ipairs({
			player.Character,
			player:FindFirstChild("ToolsHolder"),
		}) do
			if #roundDirectInventoryModels(container, itemName, false) > 0 then
				available = true
			end
		end
		-- Optional evidence can legitimately be absent or a Cross can already be
		-- consumed. Anything that still exists must already be in the new room's
		-- bounding boxes before the setup may advance.
		if (available or REQUIRED_ROOM_ITEMS[normalized]) and not correctlyPlaced then
			return false
		end
	end
	for _, itemName in ipairs(ROUND_HELD_ITEMS) do
		local available = false
		local retained = false
		if items then
			for _, model in ipairs(items:GetChildren()) do
				if normalizeRoundItemName(roundWorkspaceItemName(model))
					== normalizeRoundItemName(itemName) then
					local uses = tonumber(model:GetAttribute("Uses"))
					if uses == nil or uses > 0 then
						available = true
					end
				end
			end
		end
		for _, container in ipairs({
			player.Character,
			player:FindFirstChild("ToolsHolder"),
		}) do
			for _, model in ipairs(
				roundDirectInventoryModels(container, itemName, false)
			) do
				local uses = tonumber(model:GetAttribute("Uses"))
				if uses == nil or uses > 0 then
					available = true
					retained = findRoundHotbarSlot(itemName) ~= nil
				end
			end
		end
		if available and not retained then
			return false
		end
	end
	return true
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

local function snapshotRoundWorldItems(itemName)
	local snapshot = setmetatable({}, {__mode = "k"})
	local items = workspace:FindFirstChild("Items")
	if not items then
		return snapshot
	end
	local normalized = normalizeRoundItemName(itemName)
	for _, candidate in ipairs(items:GetChildren()) do
		if normalizeRoundItemName(roundWorkspaceItemName(candidate)) == normalized then
			snapshot[candidate] = true
		end
	end
	return snapshot
end

local function confirmRoundItemDropInRoom(
	originalModel,
	itemName,
	room,
	beforeWorldItems,
	generation
)
	local normalized = normalizeRoundItemName(itemName)
	local replacement
	local deadline = os.clock() + 1.25
	repeat
		local items = workspace:FindFirstChild("Items")
		if items then
			for _, candidate in ipairs(items:GetChildren()) do
				if normalizeRoundItemName(roundWorkspaceItemName(candidate)) == normalized
					and (candidate == originalModel
						or not beforeWorldItems[candidate]) then
					replacement = replacement or candidate
					if worldItemIsInsideRoomBounds(candidate, room) then
						doRoundState.roomItems[normalized] = candidate
						return true, candidate
					end
				end
			end
		end
		if os.clock() >= deadline then
			break
		end
		doRoundWait(generation, math.min(0.05, deadline - os.clock()))
	until false
	if replacement then
		-- Preserve the server-created replacement even when it landed outside so
		-- the next maintenance pass moves the real instance instead of a stale one.
		doRoundState.roomItems[normalized] = replacement
	end
	return false, replacement
end

local function dropRoundEquippedItemIntoRoom(
	originalModel,
	itemName,
	room,
	dropRemote,
	confirmedSlot,
	generation
)
	local candidates
	if confirmedSlot then
		candidates = {confirmedSlot}
	else
		local directCount = 0
		for _, container in ipairs({
			player.Character,
			player:FindFirstChild("ToolsHolder"),
		}) do
			directCount = directCount
				+ #roundDirectInventoryModels(container, nil, true)
		end
		if directCount ~= 1 or countRoundInventorySlots() ~= 1 then
			return false
		end
		-- With exactly one authoritative physical model, wrong candidates are
		-- blank/no-op slots. Probe all candidates and accept only the target's
		-- verified world replacement inside the room.
		candidates = roundSlotCandidates(itemName)
	end
	local beforeWorldItems = snapshotRoundWorldItems(itemName)
	for _, slotNumber in ipairs(candidates) do
		if not roundActionIsSafe(generation) then
			return false
		end
		beginAutomationMutation(3)
		local dropped = fireRoundRemote(
			dropRemote,
			generation,
			"InvSlot" .. tostring(slotNumber)
		)
		if not dropped then
			return false
		end
		local placed, replacement = confirmRoundItemDropInRoom(
			originalModel,
			itemName,
			room,
			beforeWorldItems,
			generation
		)
		if placed or replacement then
			return placed, replacement
		end
	end
	return false
end

local function restoreRoundItemToRoom(model, room, generation)
	if not model or not model.Parent or not room then
		return false
	end
	if roundCrossIsBurnt(model) then
		return false
	end
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local pickup = events and events:FindFirstChild("RequestItemPickup")
	local drop = events and events:FindFirstChild("RequestItemDrop")
	if not pickup or not pickup:IsA("RemoteEvent")
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
		if not characterIsFullyInsideRoom(player.Character, room) then
			return false
		end
		beginAutomationMutation(3)
		local equipped, _, confirmedSlot = equipRoundItem(itemName, 1.5, generation)
		if not equipped then
			return false
		end
		doRoundWait(generation, 0.15)
		if not roundActionIsSafe(generation) then
			return false
		end
		return dropRoundEquippedItemIntoRoom(
			model,
			itemName,
			room,
			drop,
			confirmedSlot,
			generation
		)
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
		movedNear = teleportNearRoundTarget(
			model,
			approach,
			generation,
			ROUND_PICKUP_MAX_DISTANCE - 0.25
		)
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
	if roundCrossIsBurnt(model) then
		return false
	end
	local pickupRoot = player.Character
		and player.Character:FindFirstChild("HumanoidRootPart")
	if not pickupRoot
		or distanceFromPositionToInstance(pickupRoot.Position, model)
			> ROUND_PICKUP_MAX_DISTANCE then
		return false
	end
	beginAutomationMutation(4)
	local picked = fireRoundRemote(pickup, generation, model)
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
	if not characterIsFullyInsideRoom(player.Character, room) then
		return false
	end
	local equipped, _, confirmedSlot = equipRoundItem(itemName, 1.5, generation)
	if not equipped then
		return false
	end
	doRoundWait(generation, 0.15)
	if not roundActionIsSafe(generation) then
		return false
	end
	return dropRoundEquippedItemIntoRoom(
		model,
		itemName,
		room,
		drop,
		confirmedSlot,
		generation
	)
end

local function maintainRoundRoomItems(room, generation)
	captureRoundRoomItems(room)
	local now = os.clock()
	for _, itemName in ipairs(DROPPED_ROOM_ITEMS) do
		local normalized = normalizeRoundItemName(itemName)
		local model = doRoundState.roomItems[normalized]
		if model and model.Parent then
			if roundCrossIsBurnt(model) then
				doRoundState.roomItems[normalized] = nil
				doRoundState.outsideSince[model] = nil
				doRoundState.restoreAttempts[model] = nil
				doRoundState.nextRestoreAt[model] = nil
				continue
			end
			local itemsFolder = workspace:FindFirstChild("Items")
			local worldItem = itemsFolder
				and model.Parent == itemsFolder
			if not worldItem or not worldItemIsInsideRoomBounds(model, room) then
				doRoundState.outsideSince[model] =
					doRoundState.outsideSince[model] or now
				if now - doRoundState.outsideSince[model] >= 1.5
					and now >= (doRoundState.nextRestoreAt[model] or 0) then
					setDoRoundStatus("Maintaining room items")
					local restored, trackedModel = restoreRoundItemToRoom(
						model,
						room,
						generation
					)
					local activeModel = trackedModel
						or doRoundState.roomItems[normalized]
						or model
					if restored then
						doRoundState.outsideSince[model] = nil
						doRoundState.restoreAttempts[model] = nil
						doRoundState.nextRestoreAt[model] = nil
						if activeModel ~= model then
							doRoundState.outsideSince[activeModel] = nil
							doRoundState.restoreAttempts[activeModel] = nil
							doRoundState.nextRestoreAt[activeModel] = nil
						end
					else
						local attempts = math.max(
							doRoundState.restoreAttempts[model] or 0,
							doRoundState.restoreAttempts[activeModel] or 0
						) + 1
						if activeModel ~= model then
							doRoundState.outsideSince[activeModel] =
								doRoundState.outsideSince[model] or now
							doRoundState.outsideSince[model] = nil
							doRoundState.restoreAttempts[model] = nil
							doRoundState.nextRestoreAt[model] = nil
						end
						doRoundState.restoreAttempts[activeModel] = attempts
						doRoundState.nextRestoreAt[activeModel] = os.clock()
							+ math.min(12, 1.5 * 2 ^ math.min(attempts - 1, 3))
					end
					return
				end
			else
				doRoundState.outsideSince[model] = nil
				doRoundState.restoreAttempts[model] = nil
				doRoundState.nextRestoreAt[model] = nil
			end
			if worldItem and POWERED_ROOM_ITEMS[normalized]
				and worldItemIsInsideRoomBounds(model, room) then
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
									local fired = fireRoundRemote(
										toggle,
										generation,
										model
									)
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
		local sent = fireRoundRemote(remote, generation, ghostName)
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

local function resetRoundRoomItemTracking()
	for _, power in pairs(doRoundState.itemPower) do
		if power.Connection and power.Connection.Connected then
			power.Connection:Disconnect()
		end
	end
	doRoundState.roomItems = {}
	doRoundState.itemPower = setmetatable({}, {__mode = "k"})
	doRoundState.outsideSince = setmetatable({}, {__mode = "k"})
	doRoundState.restoreAttempts = setmetatable({}, {__mode = "k"})
	doRoundState.nextRestoreAt = setmetatable({}, {__mode = "k"})
end

local function repeatRoundRoomItemSetup(generation, targetRoom)
	doRoundState.questionsActive = false
	waitForRoundHuntEnd(generation)
	while roomItemPlacementState.busy
		and doRoundOperationActive(generation) do
		setDoRoundStatus("Waiting for room item relocation")
		doRoundWait(generation, 0.15)
	end
	resetRoundRoomItemTracking()
	setDoRoundStatus("Relocating room items")
	local started, placementGeneration =
		placeItemsInFavouriteRoom("DoRound", targetRoom)
	if not started then
		if presenter and presenter.Notify then
			presenter:Notify(
				"Room item relocation did not start: "
					.. tostring(placementGeneration)
			)
		end
		return false
	end
	repeat
		if not roundIdentityIsCurrent() then
			error("the round changed during room item relocation", 0)
		end
		setDoRoundStatus(
			roundIsHunting()
				and "Waiting for hunt"
				or "Relocating room items"
		)
		doRoundWait(generation, 0.15)
	until roomItemPlacementState.lastCompletedGeneration
		>= placementGeneration
	if roomItemPlacementState.lastResult == false
		and presenter and presenter.Notify then
		presenter:Notify(
			roomItemPlacementState.lastError
				or "Room item relocation completed with missing items"
		)
	end
	return roundRoomSetupRecoverable(targetRoom)
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
		local completedPlacementRoom = favouriteRoom
		while roomItemPlacementState.busy
			and doRoundOperationActive(generation) do
			setDoRoundStatus("Waiting for room item setup")
			doRoundWait(generation, 0.15)
		end
		local started, placementGeneration =
			placeItemsInFavouriteRoom("DoRound", favouriteRoom)
		if started then
			repeat
				if roundIsHunting() then
					setDoRoundStatus("Waiting for hunt")
				else
					setDoRoundStatus("Placing room items")
				end
				doRoundWait(generation, 0.15)
				local currentGhost = getGhostModel()
				if not roundIdentityIsCurrent()
					or (currentGhost and currentGhost ~= doRoundState.roundGhost) then
					error("the round changed during room item setup", 0)
				end
				if not currentGhost then
					setDoRoundStatus("Waiting for ghost")
				end
			until roomItemPlacementState.lastCompletedGeneration
				>= placementGeneration
			if roomItemPlacementState.lastResult == false
				and presenter and presenter.Notify then
				presenter:Notify(
					roomItemPlacementState.lastError
						or "Room item setup failed; continuing with available items"
				)
			end
		elseif presenter and presenter.Notify then
			presenter:Notify(
				tostring(placementGeneration)
					.. "; continuing with available items"
			)
		end
		if not roundRoomSetupRecoverable(favouriteRoom) then
			repeat
				doRoundWait(generation, 0.2)
			until repeatRoundRoomItemSetup(generation, favouriteRoom)
		end
		local refreshedFavourite = findFavouriteRoom(
			findRoomsFolder(),
			ghost and ghost:GetAttribute("FavoriteRoom") or nil
		)
		while refreshedFavourite
			and refreshedFavourite ~= completedPlacementRoom do
			favouriteRoom = refreshedFavourite
			doRoundState.lastFavouriteRoom = favouriteRoom
			if repeatRoundRoomItemSetup(generation, favouriteRoom) then
				completedPlacementRoom = favouriteRoom
			else
				doRoundWait(generation, 0.2)
			end
			local latestGhost = getGhostModel()
			refreshedFavourite = findFavouriteRoom(
				findRoomsFolder(),
				latestGhost
					and latestGhost:GetAttribute("FavoriteRoom")
					or nil
			)
		end
		if refreshedFavourite then
			favouriteRoom = refreshedFavourite
			doRoundState.lastFavouriteRoom = refreshedFavourite
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
			if presenter and presenter.Notify then
				presenter:Notify(
					"Missing room items: "
						.. table.concat(missingRoomItems, ", ")
						.. "; continuing"
				)
			end
		end
		local missingHeldItems = {}
		for _, itemName in ipairs(ROUND_HELD_ITEMS) do
			if not findRoundHotbarSlot(itemName) then
				table.insert(missingHeldItems, itemName)
			end
		end
		if #missingHeldItems > 0 then
			if presenter and presenter.Notify then
				presenter:Notify(
					"Missing held items: "
						.. table.concat(missingHeldItems, ", ")
						.. "; continuing"
				)
			end
		end

		local toolsDone = false
		repeat
			waitForRoundHuntEnd(generation)
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
		repeat
			waitForRoundHuntEnd(generation)
			setDoRoundStatus("Opening exit door")
			local opened, reason = openRoundExitDoor(generation)
			if opened then
				exitOpened = true
			elseif reason == "hunt started"
				or reason == "ghost unavailable" then
				-- Wait for the temporary interruption, then retry the exit door.
			else
				exitOpened = true
				if presenter and presenter.Notify then
					presenter:Notify(
						(reason or "Exit door failed")
							.. "; continuing the round"
					)
				end
			end
		until exitOpened

		waitForRoundHuntEnd(generation)
		teleportToFavouriteRoom(roundTeleportOptions(generation))
		doRoundState.questionsActive = true
		local qualifiedName
		local qualifiedSince
		local timeoutFallback
		local timeoutSelectionSignature
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
				local relocationTarget = favouriteRoom
				if not repeatRoundRoomItemSetup(generation, relocationTarget) then
					-- Force the next pass to retry even if the replicated room name
					-- itself did not change while setup was unavailable.
					favouriteRoom = nil
					doRoundWait(generation, 0.2)
					continue
				end
				local latestGhost = getGhostModel()
				local latestFavourite = findFavouriteRoom(
					findRoomsFolder(),
					latestGhost
						and latestGhost:GetAttribute("FavoriteRoom")
						or nil
				)
				if latestFavourite and latestFavourite ~= relocationTarget then
					-- The favourite room changed during relocation.  Do not capture
					-- or maintain the unprepared room; the next pass runs the full
					-- setup for this newer target.
					favouriteRoom = relocationTarget
					continue
				elseif latestFavourite then
					favouriteRoom = latestFavourite
					doRoundState.lastFavouriteRoom = latestFavourite
				end
				captureRoundRoomItems(favouriteRoom)
				teleportToRoomBoundingBoxCenter(
					favouriteRoom,
					roundTeleportOptions(generation)
				)
				doRoundState.questionsActive = true
				qualifiedName = nil
				qualifiedSince = nil
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
				local input = getGhostSessionInput()
				local function selectTimeout(previousChoice)
					return GhostSession.SelectTimeoutGuess(input, {
						CurrentGuess = guess,
						CurrentScore = score,
						PreviousChoice = previousChoice,
						RandomUnit = function()
							return math.random()
						end,
						RandomIndex = function(count)
							return math.random(count)
						end,
					})
				end
				local selection = selectTimeout(timeoutFallback)
				if selection.Signature ~= timeoutSelectionSignature then
					timeoutSelectionSignature = selection.Signature
					selection = selectTimeout(nil)
				end
				timeoutFallback = selection.Ghost
				if timeoutFallback then
					local fallbackScore = math.max(
						tonumber(selection.Confidence) or 0,
						1
					)
					if selectRoundJournalGhost(timeoutFallback, generation) then
						perkTrackerState.currentGhostGuess = timeoutFallback
						perkTrackerState.currentGhostGuessScore = fallbackScore
						perkTrackerState.currentGhostGuessCertain = false
						setGhostIdentificationLabel(
							timeoutFallback,
							fallbackScore,
							false
						)
						if returnRoundToBase(generation) then
							setEnabled(false, "Selected " .. timeoutFallback)
						end
						return
					end
				end
				setDoRoundStatus(
					timeoutFallback
						and "Selecting ghost guess"
						or "No eligible ghost guess"
				)
			end

			local character = player.Character
			doRoundState.questionsActive = true
			if favouriteRoom and character
				and not characterIsFullyInsideRoom(character, favouriteRoom) then
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
		doRoundState.usedSaltDoorModels = setmetatable({}, {__mode = "k"})
		doRoundState.completedDoorTools = {}
		doRoundState.doorToolPlacements = {}
		doRoundState.doorToolUses = {}
		doRoundState.lastDoorName = nil
		doRoundState.roomItems = {}
		doRoundState.itemPower = setmetatable({}, {__mode = "k"})
		doRoundState.outsideSince = setmetatable({}, {__mode = "k"})
		doRoundState.restoreAttempts = setmetatable({}, {__mode = "k"})
		doRoundState.nextRestoreAt = setmetatable({}, {__mode = "k"})
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
