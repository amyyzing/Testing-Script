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
	local prepareTeleport: any = dependencies.PrepareTeleport
	if type(prepareTeleport) ~= "function" then
		prepareTeleport = function()
			return true
		end
	end
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
local ROUND_DOOR_MIN_PLAYER_DISTANCE = 2
local ROUND_DOOR_STAND_DISTANCE = 2
local ROUND_PLACEMENT_MAX_PLAYER_DISTANCE = 2
local ROUND_PICKUP_MAX_DISTANCE = 8
local ROUND_REMOTE_SAFETY_DELAY = 0.1
local ROUND_DOOR_INTERACTION_SETTLE_SECONDS = 0.75
local ROUND_DOOR_ATTEMPT_LIMIT = 3
local ROUND_LOBBY_RETRY_SECONDS = 4
local ROUND_MINIMUM_LEAVE_AGE = 30
local ROUND_BASE_CAMP_SETTLE_SECONDS = 1.25
local ROUND_JOURNAL_SETTLE_SECONDS = 0.35
-- Salt consumes every available use. Distinct door identity, not an arbitrary
-- count, is the only placement cap; Holy Oil is capped at three placements.
local ROUND_SALT_PLACEMENT_LIMIT = math.huge
local ROUND_HOLY_OIL_PLACEMENT_LIMIT = 3
local ROUND_ROOM_HORIZONTAL_TOLERANCE = 0.75
local ROUND_ROOM_VERTICAL_TOLERANCE = 0.6
local ROUND_ITEM_OUTSIDE_GRACE = 1.75
local ROUND_MAINTENANCE_INTERVAL = 1.25
local ROUND_MAINTENANCE_RETRY_BACKOFF = 1.5
local ROUND_MISSING_TOOL_RETRY_LIMIT = 5
local ROUND_MISSING_USES_RETRY_LIMIT = 3
local ROUND_DOOR_RETRY_PASS_LIMIT = 3
local ROUND_BASE_CAMP_RETRY_MIN = 0.25
local ROUND_BASE_CAMP_RETRY_MAX = 2
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
local ROUND_PLACEMENT_DISTANCE_DRIFT = 0.05
local ROUND_PLACEMENT_CENTER_TOLERANCE = 0.35
local roundDoorFacingLockSequence = 0
local roundRoomMembershipCache = setmetatable({}, {__mode = "k"})
local roundRoomOverlapParams = OverlapParams.new()
roundRoomOverlapParams.FilterType = Enum.RaycastFilterType.Include
roundRoomOverlapParams.MaxParts = 4

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
	if not model then
		return nil
	end
	local value = model:GetAttribute("ItemName")
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		value = descendant:GetAttribute("ItemName")
		if typeof(value) == "string" and value ~= "" then
			return value
		end
	end
	return nil
end

local function roundItemIsBurntCross(model)
	if model == nil
		or normalizeRoundItemName(roundItemName(model)) ~= "cross" then
		return false
	end
	local function hasConsumedState(object)
		return object:GetAttribute("Burned") == true
			or object:GetAttribute("Burnt") == true
			or object:GetAttribute("Consumed") == true
			or object:GetAttribute("Used") == true
			or tonumber(object:GetAttribute("Uses")) == 0
	end
	if hasConsumedState(model) then
		return true
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if hasConsumedState(descendant) then
			return true
		end
	end
	return false
end

local function roundStoredItem(container, itemName)
	if not container then
		return nil
	end
	local normalized = normalizeRoundItemName(itemName)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model")
			and normalizeRoundItemName(roundItemName(child)) == normalized
			and not roundItemIsBurntCross(child) then
			return child
		end
	end
	return nil
end

local function getRoundInventoryItem(itemName)
	return roundStoredItem(player:FindFirstChild("ToolsHolder"), itemName)
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
	local stored = getRoundInventoryItem(itemName)
		or roundStoredItem(player.Character, itemName)
	if stored then
		for _, attributeName in ipairs({
			"InvSlot",
			"InventorySlot",
			"Slot",
			"SlotNumber",
		}) do
			local value = stored:GetAttribute(attributeName)
			local number = tonumber(tostring(value or ""):match("%d+"))
			if number and number >= 1 and number <= 3 then
				return number
			end
		end
		for slotNumber = 1, 3 do
			local slotValue = player:GetAttribute(
				"InvSlot" .. tostring(slotNumber)
			)
			if slotValue ~= nil and slotValue ~= false then
				local target = tostring(slotValue)
				if target == stored.Name
					or normalizeRoundItemName(target) == normalized then
					return slotNumber
				end
				for _, value in pairs(stored:GetAttributes()) do
					if tostring(value) == target then
						return slotNumber
					end
				end
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
	return roundStoredItem(character, normalized)
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
	local currentGhost = getGhostModel()
	if generation ~= nil and currentGhost
		and currentGhost:GetAttribute("Hunting") == true then
		return nil, "hunt started"
	end
	local events = Services.ReplicatedStorage:FindFirstChild("Events")
	local remote = events and events:FindFirstChild("RequestItemEquip")
	if not remote or not remote:IsA("RemoteEvent") then
		return nil, "RequestItemEquip RemoteEvent was not found"
	end
	task.wait(ROUND_REMOTE_SAFETY_DELAY)
	if generation ~= nil
		and (not runtimeIsActive()
			or not doRoundState.enabled
			or doRoundState.generation ~= generation) then
		return nil, "Do-Round cancelled"
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

local function roundPointInsideRoomBound(
	boundingPart,
	position,
	horizontalTolerance,
	verticalTolerance
)
	if not boundingPart or not boundingPart:IsA("BasePart") or not position then
		return false
	end
	local localPosition = boundingPart.CFrame:PointToObjectSpace(position)
	local half = boundingPart.Size * 0.5
	horizontalTolerance = horizontalTolerance
		or ROUND_ROOM_HORIZONTAL_TOLERANCE
	verticalTolerance = verticalTolerance or ROUND_ROOM_VERTICAL_TOLERANCE
	return math.abs(localPosition.X) <= half.X + horizontalTolerance
		and math.abs(localPosition.Y) <= half.Y + verticalTolerance
		and math.abs(localPosition.Z) <= half.Z + horizontalTolerance
end

local function roundInstanceOverlapsRoom(instance, room)
	if not instance or not instance.Parent or not room then
		return false
	end
	local frame, size = roundTargetCFrame(instance)
	if not frame or not size then
		return false
	end
	local now = os.clock()
	local cached = roundRoomMembershipCache[instance]
	if cached
		and cached.Room == room
		and now - cached.At <= 0.3
		and (cached.Position - frame.Position).Magnitude <= 0.04
		and (cached.Size - size).Magnitude <= 0.02 then
		return cached.Result
	end
	local verticalBottom = frame.Position.Y - size.Y * 0.5
	local verticalTop = frame.Position.Y + size.Y * 0.5
	local result = false
	roundRoomOverlapParams.FilterDescendantsInstances = {instance}
	for _, boundingPart in ipairs(getRoomBoundingParts(room)) do
		if boundingPart:IsA("BasePart") then
			if roundPointInsideRoomBound(boundingPart, frame.Position) then
				result = true
				break
			end
			local boundBottom = boundingPart.Position.Y
				- boundingPart.Size.Y * 0.5
				- ROUND_ROOM_VERTICAL_TOLERANCE
			local boundTop = boundingPart.Position.Y
				+ boundingPart.Size.Y * 0.5
				+ ROUND_ROOM_VERTICAL_TOLERANCE
			if verticalTop >= boundBottom and verticalBottom <= boundTop then
				local ok, overlaps = pcall(function()
					return workspace:GetPartBoundsInBox(
						boundingPart.CFrame,
						boundingPart.Size
							+ Vector3.new(
								ROUND_ROOM_HORIZONTAL_TOLERANCE * 2,
								ROUND_ROOM_VERTICAL_TOLERANCE * 2,
								ROUND_ROOM_HORIZONTAL_TOLERANCE * 2
							),
						roundRoomOverlapParams
					)
				end)
				if ok and #overlaps > 0 then
					result = true
					break
				end
			end
		end
	end
	roundRoomMembershipCache[instance] = {
		Room = room,
		At = now,
		Position = frame.Position,
		Size = size,
		Result = result,
	}
	return result
end

local function roundWorldItemIsInsideRoom(model, room)
	local items = workspace:FindFirstChild("Items")
	local itemName = model and model:GetAttribute("ItemName")
	return model ~= nil
		and model:IsA("Model")
		and items ~= nil
		and model:IsDescendantOf(items)
		and typeof(itemName) == "string"
		and itemName ~= ""
		and not roundItemIsBurntCross(model)
		and roundInstanceOverlapsRoom(model, room)
end

local function roundPositionInsideAnyRoom(position)
	local rooms = findRoomsFolder()
	if not rooms or not position then
		return false
	end
	for _, room in ipairs(rooms:GetChildren()) do
		for _, boundingPart in ipairs(getRoomBoundingParts(room)) do
			if roundPointInsideRoomBound(
				boundingPart,
				position,
				0.35,
				0.25
			) then
				return true, room, boundingPart
			end
		end
	end
	return false
end

local function roundInstanceInsideAnyRoom(instance)
	local rooms = findRoomsFolder()
	if not rooms or not instance then
		return false
	end
	for _, room in ipairs(rooms:GetChildren()) do
		if roundInstanceOverlapsRoom(instance, room) then
			return true, room
		end
	end
	return false
end

local function roundPlacementHasFloor(instance, maximumDrop)
	local position = getInstanceWorldPosition(instance)
	if not position or not roundPositionInsideAnyRoom(position) then
		return false
	end
	local excludes = {}
	if instance then
		table.insert(excludes, instance)
	end
	local camera = workspace.CurrentCamera
	if camera and instance:IsDescendantOf(camera) and instance.Parent then
		table.insert(excludes, instance.Parent)
	end
	if player.Character then
		table.insert(excludes, player.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludes
	params.IgnoreWater = true
	pcall(function()
		params.RespectCanCollide = true
	end)
	local result = workspace:Raycast(
		position + Vector3.new(0, 0.75, 0),
		Vector3.new(0, -(maximumDrop or 4), 0),
		params
	)
	return result ~= nil
		and result.Normal.Y >= 0.5
		and roundPositionInsideAnyRoom(result.Position)
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
	local maximumDistance = math.min(
		thickness * 0.5 + ROUND_DOOR_STAND_DISTANCE,
		ROUND_DOOR_MAX_PLAYER_DISTANCE
	)
	local minimumDistance = math.min(
		math.max(
			thickness * 0.5 + ROUND_DOOR_MIN_PLAYER_DISTANCE,
			ROUND_DOOR_MIN_PLAYER_DISTANCE
		),
		ROUND_DOOR_MAX_PLAYER_DISTANCE
	)
	local standDistance = math.clamp(
		thickness * 0.5 + ROUND_DOOR_STAND_DISTANCE,
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

local function roundDoorApproaches(target, placementDistance)
	local geometry = roundDoorGeometry(target)
	if not geometry then
		return {}, nil, nil
	end
	local calibratedDistance = tonumber(placementDistance)
	if calibratedDistance then
		calibratedDistance = math.clamp(
			calibratedDistance,
			0.25,
			ROUND_DOOR_MAX_PLAYER_DISTANCE
		)
	end
	local minimumDistance = calibratedDistance
		and math.max(0.25, calibratedDistance - 0.2)
		or geometry.MinimumDistance
	local maximumDistance = calibratedDistance
		and math.min(
			ROUND_DOOR_MAX_PLAYER_DISTANCE,
			calibratedDistance + 0.2
		)
		or geometry.MaximumDistance
	local standDistance = calibratedDistance or geometry.StandDistance
	local maximumLateralOffset = calibratedDistance
		and ROUND_PLACEMENT_CENTER_TOLERANCE
		or 0.8
	local approaches = {}
	for _, side in ipairs({1, -1}) do
		local positions = {}
		for _, lateral in ipairs(calibratedDistance
			and {0, -0.2, 0.2}
			or {0, -0.35, 0.35, -0.7, 0.7}) do
			for _, normalAdjustment in ipairs({0, 0.2, -0.2}) do
				local distance = math.clamp(
					standDistance + normalAdjustment,
					minimumDistance,
					maximumDistance
				)
				table.insert(
					positions,
					geometry.Center
						+ geometry.NormalAxis * side * distance
						+ geometry.WideAxis * lateral
				)
			end
		end
		table.insert(approaches, {
			Side = side,
			Position = positions[1],
			CandidatePositions = positions,
			Facing = geometry.NormalAxis * -side,
			Geometry = geometry,
			MinimumDistance = minimumDistance,
			MaximumDistance = maximumDistance,
			MaximumLateralOffset = maximumLateralOffset,
			MaximumPreferredDistance = calibratedDistance and 0.35 or 0.8,
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
		ReleaseMovementOnCancel = true,
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
		MaximumPreferredDistance = approach.MaximumPreferredDistance or 0.8,
		LookDirection = approach.Facing,
		RequireStrict = true,
		ReleaseMovementOnCancel = true,
		CandidateValidator = function(position)
			local relative = Vector3.new(
				position.X - geometry.Center.X,
				0,
				position.Z - geometry.Center.Z
			)
			local lateral = math.abs(relative:Dot(geometry.WideAxis))
			local signedNormal = relative:Dot(geometry.NormalAxis)
			return relative.Magnitude <= ROUND_DOOR_MAX_PLAYER_DISTANCE
				and lateral <= (approach.MaximumLateralOffset or 0.8)
				and signedNormal * approach.Side > 0
				and math.abs(signedNormal)
					>= (approach.MinimumDistance or geometry.MinimumDistance)
				and math.abs(signedNormal)
					<= (approach.MaximumDistance or geometry.MaximumDistance)
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

local function roundActionIsSafe(generation)
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

local function settleRoundDoorInteraction(target, maximumDistance, generation)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local center = getInstanceWorldPosition(target)
	if not character or not root or not humanoid or not center
		or humanoid.Health <= 0
		or (root.Position - center).Magnitude > maximumDistance then
		return false
	end
	-- Re-applying the current pivot produces a fresh replicated position update.
	-- A local distance check alone can pass while the server still sees the
	-- character at the previous teleport destination.
	pcall(function()
		humanoid:Move(Vector3.zero, false)
		character:PivotTo(character:GetPivot())
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	local stableSince = os.clock()
	while os.clock() - stableSince < ROUND_DOOR_INTERACTION_SETTLE_SECONDS do
		if not roundActionIsSafe(generation) then
			return false
		end
		if player.Character ~= character or not character.Parent then
			return false
		end
		root = character:FindFirstChild("HumanoidRootPart")
		humanoid = character:FindFirstChildOfClass("Humanoid")
		center = getInstanceWorldPosition(target)
		if not root or not humanoid or humanoid.Health <= 0 or not center
			or root.Anchored
			or (root.Position - center).Magnitude > maximumDistance then
			return false
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		Services.RunService.Heartbeat:Wait()
	end
	return true
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

local function collectRoundDoorStateCandidates(doorModel, doorContainer)
	local candidates = {}
	local seen = setmetatable({}, {__mode = "k"})
	local function add(object)
		if object and not seen[object] then
			seen[object] = true
			table.insert(candidates, object)
		end
	end
	add(doorModel)
	add(doorContainer)
	local reference = roundDoorReference(doorContainer)
	add(reference)
	local current = reference
	while current and current ~= doorModel do
		add(current)
		current = current.Parent
	end
	if doorContainer then
		for _, descendant in ipairs(doorContainer:GetDescendants()) do
			if descendant:GetAttribute("DoorClosed") ~= nil
				or string.lower(descendant.Name) == "doorunion" then
				add(descendant)
			end
		end
	end
	return candidates
end

local function roundDoorClosedState(doorModel, doorContainer, stateCandidates)
	local modelState = doorModel and doorModel:GetAttribute("DoorClosed")
	if typeof(modelState) == "boolean" then
		return modelState
	end
	local candidates = stateCandidates
		and stateCandidates.DoorContainer == doorContainer
		and stateCandidates.Objects
		or collectRoundDoorStateCandidates(doorModel, doorContainer)
	for _, object in ipairs(candidates) do
		if object.Parent and object:GetAttribute("DoorClosed") == false then
			return false
		end
	end
	-- Several doors do not publish DoorClosed while already closed. Geometry
	-- stability remains mandatory below, so nil is accepted only after the
	-- whole relevant door hierarchy contained no authoritative false value.
	return true
end

local function waitForStableClosedDoor(doorModel, generation)
	local deadline = os.clock() + 3
	local stablePasses = 0
	local previous
	local doorContainer
	local stateCandidates
	repeat
		if not roundActionIsSafe(generation) then
			return nil, nil, roundUnsafeReason(generation)
		end
		local currentDoorContainer = doorModel:FindFirstChild("Door") or doorModel
		if currentDoorContainer ~= doorContainer then
			doorContainer = currentDoorContainer
			stateCandidates = {
				DoorContainer = doorContainer,
				Objects = collectRoundDoorStateCandidates(doorModel, doorContainer),
			}
		end
		if not roundDoorClosedState(doorModel, doorContainer, stateCandidates) then
			stablePasses = 0
			previous = nil
		else
			local reference = roundDoorReference(doorContainer)
			local geometry = roundDoorGeometry(reference)
			if geometry and geometry.Reference then
				local snapshot = {
					Reference = geometry.Reference,
					Frame = geometry.Frame,
					Size = geometry.Reference.Size,
				}
				local stable = previous ~= nil
					and snapshot.Reference == previous.Reference
					and (snapshot.Frame.Position - previous.Frame.Position).Magnitude
						<= ROUND_PLACEMENT_DOOR_DRIFT
					and snapshot.Frame.RightVector:Dot(
						previous.Frame.RightVector
					) >= 0.9995
					and snapshot.Frame.LookVector:Dot(
						previous.Frame.LookVector
					) >= 0.9995
					and (snapshot.Size - previous.Size).Magnitude <= 0.02
				stablePasses = stable and stablePasses + 1 or 1
				previous = snapshot
				if stablePasses >= 4 then
					return reference, geometry
				end
			else
				stablePasses = 0
				previous = nil
			end
		end
		doRoundWait(generation, 0.08)
	until os.clock() >= deadline
	return nil, nil, "closed door geometry did not stabilize"
end

local function prepareRoundDoorForPlacement(doorModel, generation)
	if not doorModel or not doorModel.Parent then
		return nil, nil, "door model disappeared"
	end
	local doorContainer = doorModel:FindFirstChild("Door") or doorModel
	local stateCandidates = {
		DoorContainer = doorContainer,
		Objects = collectRoundDoorStateCandidates(doorModel, doorContainer),
	}
	local reference = roundDoorReference(doorContainer)
	if not reference then
		return nil, nil, "DoorModel.Door.DoorUnion was unavailable"
	end
	if not roundDoorClosedState(doorModel, doorContainer, stateCandidates) then
		local center = getInstanceWorldPosition(reference)
		local root = player.Character
			and player.Character:FindFirstChild("HumanoidRootPart")
		local locallyInRange = root ~= nil and center ~= nil
			and (root.Position - center).Magnitude <= 10
		-- Do not trust local proximity by itself. Re-run the safe teleport even
		-- when already nearby so the server receives a current position update.
		local approached = teleportNearRoundTarget(
			reference,
			locallyInRange and root.Position or nil,
			generation
		)
		if approached then
			approached = settleRoundDoorInteraction(reference, 10, generation)
		elseif locallyInRange then
			approached = settleRoundDoorInteraction(reference, 10, generation)
		end
		local approaches = roundDoorApproaches(reference)
		if not approached then
			for _, approach in ipairs(approaches) do
				if not roundActionIsSafe(generation) then
					return nil, nil, roundUnsafeReason(generation)
				end
				if teleportToRoundDoorFace(reference, approach, generation)
					and settleRoundDoorInteraction(reference, 10, generation) then
					approached = true
					break
				end
			end
		end
		root = player.Character
			and player.Character:FindFirstChild("HumanoidRootPart")
		center = getInstanceWorldPosition(reference)
		if not approached or not root or not center
			or (root.Position - center).Magnitude > 10 then
			return nil, nil, "could not move within door-closing range"
		end
		local events = Services.ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild("ClientChangeDoorState")
		if not remote or not remote:IsA("RemoteEvent") then
			return nil, nil, "ClientChangeDoorState RemoteEvent was not found"
		end
		beginAutomationMutation(2)
		doRoundWait(generation, ROUND_REMOTE_SAFETY_DELAY)
		if not roundActionIsSafe(generation) then
			return nil, nil, roundUnsafeReason(generation)
		end
		-- The approach can take long enough for another actor to close the door.
		-- Re-read immediately before toggling so a closed door is never reopened.
		doorContainer = doorModel:FindFirstChild("Door") or doorModel
		reference = roundDoorReference(doorContainer)
		stateCandidates = {
			DoorContainer = doorContainer,
			Objects = collectRoundDoorStateCandidates(doorModel, doorContainer),
		}
		root = player.Character
			and player.Character:FindFirstChild("HumanoidRootPart")
		center = getInstanceWorldPosition(reference)
		if not root or not center or (root.Position - center).Magnitude > 10 then
			return nil, nil, "moved outside door-closing range"
		end
		local firedAt
		local firedReference = reference
		local firedFrame = reference and reference:IsA("BasePart")
			and reference.CFrame
		if not roundDoorClosedState(doorModel, doorContainer, stateCandidates) then
			local fired = pcall(remote.FireServer, remote, doorContainer)
			if not fired then
				return nil, nil, "door close interaction failed"
			end
			firedAt = os.clock()
		end
		-- Retry once only when neither replicated state nor physical geometry
		-- changed. This recovers an intermittently dropped interaction without
		-- toggling a door back open while its close animation is underway.
		local closeDeadline = os.clock() + 4
		local retried = false
		repeat
			if not roundActionIsSafe(generation) then
				return nil, nil, roundUnsafeReason(generation)
			end
			local currentDoorContainer = doorModel:FindFirstChild("Door") or doorModel
			if currentDoorContainer ~= doorContainer then
				doorContainer = currentDoorContainer
				stateCandidates = {
					DoorContainer = doorContainer,
					Objects = collectRoundDoorStateCandidates(doorModel, doorContainer),
				}
			end
			if roundDoorClosedState(doorModel, doorContainer, stateCandidates) then
				break
			end
			if firedAt and not retried and os.clock() - firedAt >= 1.5 then
				retried = true
				local currentReference = roundDoorReference(doorContainer)
				local geometryMoved = currentReference ~= firedReference
				if not geometryMoved and firedFrame and currentReference
					and currentReference:IsA("BasePart") then
					local currentFrame = currentReference.CFrame
					geometryMoved = (currentFrame.Position - firedFrame.Position).Magnitude
						> 0.03
						or currentFrame.RightVector:Dot(firedFrame.RightVector) < 0.9995
						or currentFrame.LookVector:Dot(firedFrame.LookVector) < 0.9995
				end
				root = player.Character
					and player.Character:FindFirstChild("HumanoidRootPart")
				center = getInstanceWorldPosition(currentReference)
				if not geometryMoved and root and center
					and (root.Position - center).Magnitude <= 10
					and settleRoundDoorInteraction(currentReference, 10, generation)
					and not roundDoorClosedState(
						doorModel,
						doorContainer,
						stateCandidates
					) then
					beginAutomationMutation(1)
					pcall(remote.FireServer, remote, doorContainer)
				end
			end
			doRoundWait(generation, 0.05)
		until os.clock() >= closeDeadline
		if not roundDoorClosedState(doorModel, doorContainer, stateCandidates) then
			return nil, nil, "door did not close"
		end
	end
	-- Closing rotates some doors. Always discard the pre-close reference and
	-- re-resolve the DoorUnion after closed geometry has settled.
	return waitForStableClosedDoor(doorModel, generation)
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
	local camera = context.Camera or workspace.CurrentCamera
	if not camera or workspace.CurrentCamera ~= camera then
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
	local camera = workspace.CurrentCamera
	if not camera then
		return nil, "player camera was unavailable"
	end
	context.Camera = camera
	local lock = {
		Context = context,
		OriginalAutoRotate = context.Humanoid.AutoRotate,
		OriginalCameraType = camera.CameraType,
		Released = false,
		Connections = {},
		RenderStepName = nil,
		HeartbeatPass = 0,
		RenderPass = 0,
	}
	doRoundState.facingLocks = doRoundState.facingLocks
		or setmetatable({}, {__mode = "k"})
	doRoundState.facingLocks[lock] = true
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
			self.Context.Camera.CameraType = Enum.CameraType.Scriptable
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
		if doRoundState.facingLocks then
			doRoundState.facingLocks[self] = nil
		end
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
		local camera = self.Context.Camera
		if camera and workspace.CurrentCamera == camera then
			pcall(function()
				camera.CameraType = self.OriginalCameraType
			end)
		end
	end
	local disabled = pcall(function()
		context.Humanoid.AutoRotate = false
		camera.CameraType = Enum.CameraType.Scriptable
	end)
	if not disabled then
		lock:Release()
		return nil, "player facing lock could not disable AutoRotate"
	end
	local heartbeatConnected, heartbeatConnection = pcall(function()
		return Services.RunService.Heartbeat:Connect(function()
			if lock:Enforce() then
				lock.HeartbeatPass = lock.HeartbeatPass + 1
			else
				lock:Release()
			end
		end)
	end)
	if heartbeatConnected then
		table.insert(lock.Connections, heartbeatConnection)
	end
	if not heartbeatConnected then
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
		or rootLateral > 0.8
		or math.abs(rootNormal) < 0.05 then
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

local function roundPlacementPreviewPart(toolName)
	local camera = workspace.CurrentCamera
	local previewName = toolName == "Salt Canister" and "SaltLine" or "HolyOil"
	local partName = toolName == "Salt Canister" and "Salt" or "Center"
	local preview = camera and camera:FindFirstChild(previewName)
	local previewPart = preview and preview:FindFirstChild(partName, true)
	return previewPart and previewPart:IsA("BasePart") and previewPart or nil
end

local function waitForRoundPlacementXZDistance(toolName, generation)
	local deadline = os.clock() + 2
	local lastDistance
	local stablePasses = 0
	repeat
		Services.RunService.RenderStepped:Wait()
		if not roundActionIsSafe(generation) then
			return nil, roundUnsafeReason(generation)
		end
		local root = player.Character
			and player.Character:FindFirstChild("HumanoidRootPart")
		local previewPart = roundPlacementPreviewPart(toolName)
		if root and previewPart then
			local offset = Vector3.new(
				previewPart.Position.X - root.Position.X,
				0,
				previewPart.Position.Z - root.Position.Z
			)
			local distance = offset.Magnitude
			if distance >= 0.25
				and distance <= ROUND_PLACEMENT_MAX_PLAYER_DISTANCE then
				if lastDistance
					and math.abs(distance - lastDistance)
						<= ROUND_PLACEMENT_DISTANCE_DRIFT then
					stablePasses = stablePasses + 1
				else
					stablePasses = 1
				end
				lastDistance = distance
				if stablePasses >= 3 then
					return distance
				end
			else
				lastDistance = nil
				stablePasses = 0
			end
		else
			lastDistance = nil
			stablePasses = 0
		end
	until os.clock() >= deadline
	return nil,
		toolName
			.. " preview XZ distance from the player did not settle within two studs"
end

local placementPreviewIsAligned: any = function(toolName, target)
	local previewPart = roundPlacementPreviewPart(toolName)
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
	local dispatchRootPosition
	local dispatchPreviewPosition
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
		local previewAligned, previewPart =
			placementPreviewIsAligned(toolName, target)
		if facingLock.RenderPass ~= settledRenderPass
			or not facingLock:Enforce()
			or not previewAligned
			or not previewPart then
			dispatchFailure =
				"placement preview lost door alignment before dispatch"
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
		dispatchPreviewPosition = previewPart.Position
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
		doRoundWait(generation, ROUND_REMOTE_SAFETY_DELAY)
		if not roundActionIsSafe(generation)
			or not facingLock:Enforce()
			or not placementPreviewIsAligned(toolName, target) then
			dispatchFailure = roundActionIsSafe(generation)
				and "placement alignment changed during the remote safety delay"
				or roundUnsafeReason(generation)
			return
		end
		-- Use the same client controller path as right-clicking the equipped
		-- Salt Canister/Holy Oil. Those controllers validate the equipped model,
		-- fire the correct no-argument remote, and manage their preview/cooldown.
		local playerScripts = player:FindFirstChild("PlayerScripts")
		local localEvents = playerScripts and playerScripts:FindFirstChild("Events")
		local useItem = localEvents and localEvents:FindFirstChild("UseItem")
		local fired
		if useItem and useItem:IsA("BindableEvent") then
			fired = pcall(useItem.Fire, useItem)
		else
			fired = pcall(remote.FireServer, remote)
		end
		if not fired then
			dispatchFailure = remoteName .. " failed"
			return
		end
		dispatchAccepted = true
	end, debug.traceback)
	facingLock:Release()
	if not guarded then
		error(guardedFailure, 0)
	end
	if not dispatchAccepted then
		return false, dispatchFailure or remoteName .. " failed"
	end
	local deadline = os.clock() + 3
	local usesConfirmed = false
	local spawnConfirmed = false
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
		if uses ~= nil and currentUses ~= nil and currentUses < uses then
			usesConfirmed = true
		end
		placementFolder = workspace:FindFirstChild(folderName)
		if placementFolder then
			for _, child in ipairs(placementFolder:GetChildren()) do
				if not existingPlacements[child] then
					local position = getInstanceWorldPosition(child)
					if position and targetFrame and dispatchRootPosition
						and dispatchPreviewPosition
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
							<= ROUND_PLACEMENT_MAX_PLAYER_DISTANCE + 0.75
						and (Vector3.new(position.X, 0, position.Z)
							- Vector3.new(
								dispatchPreviewPosition.X,
								0,
								dispatchPreviewPosition.Z
							)).Magnitude <= 1.25
						and roundInstanceInsideAnyRoom(child)
						and roundPlacementHasFloor(child, 5) then
						spawnConfirmed = true
						break
					end
				end
			end
			if usesConfirmed and spawnConfirmed then
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
	if not usesConfirmed or not spawnConfirmed then
		return false,
			toolName
				.. " was dispatched but confirmation was incomplete (Uses="
				.. tostring(usesConfirmed)
				.. ", world pile="
				.. tostring(spawnConfirmed)
				.. ")",
			true,
			lastObservedUses
	end
	return true, nil, true, lastObservedUses
end
	return {
		DroppedRoomItems = DROPPED_ROOM_ITEMS,
		PoweredRoomItems = POWERED_ROOM_ITEMS,
		HeldItems = ROUND_HELD_ITEMS,
		NormalizeItemName = normalizeRoundItemName,
		ItemName = roundItemName,
		ItemIsBurntCross = roundItemIsBurntCross,
		GetInventoryItem = getRoundInventoryItem,
		FindHotbarSlot = findRoundHotbarSlot,
		GetEquippedItem = getRoundEquippedItem,
		EquipItem = equipRoundItem,
		ApproachPositions = roundApproachPositions,
		ResolveDoorReference = roundDoorReference,
		DoorGeometry = roundDoorGeometry,
		DoorApproaches = roundDoorApproaches,
		DoorIsClosed = roundDoorClosedState,
		PrepareDoor = prepareRoundDoorForPlacement,
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
		SettleDoorInteraction = settleRoundDoorInteraction,
		BeginMutation = beginAutomationMutation,
		PlacementXZDistance = waitForRoundPlacementXZDistance,
		FirePlaceable = fireRoundPlaceable,
		WorldItemIsInsideRoom = roundWorldItemIsInsideRoom,
		InstanceInsideAnyRoom = roundInstanceInsideAnyRoom,
		PlacementHasFloor = roundPlacementHasFloor,
		PickupMaxDistance = ROUND_PICKUP_MAX_DISTANCE,
		RemoteSafetyDelay = ROUND_REMOTE_SAFETY_DELAY,
		DoorAttemptLimit = ROUND_DOOR_ATTEMPT_LIMIT,
		LobbyRetrySeconds = ROUND_LOBBY_RETRY_SECONDS,
		MinimumLeaveAge = ROUND_MINIMUM_LEAVE_AGE,
		BaseCampSettleSeconds = ROUND_BASE_CAMP_SETTLE_SECONDS,
		JournalSettleSeconds = ROUND_JOURNAL_SETTLE_SECONDS,
		SaltPlacementLimit = ROUND_SALT_PLACEMENT_LIMIT,
		HolyOilPlacementLimit = ROUND_HOLY_OIL_PLACEMENT_LIMIT,
		ItemOutsideGrace = ROUND_ITEM_OUTSIDE_GRACE,
		MaintenanceInterval = ROUND_MAINTENANCE_INTERVAL,
		MaintenanceRetryBackoff = ROUND_MAINTENANCE_RETRY_BACKOFF,
		MissingToolRetryLimit = ROUND_MISSING_TOOL_RETRY_LIMIT,
		MissingUsesRetryLimit = ROUND_MISSING_USES_RETRY_LIMIT,
		DoorRetryPassLimit = ROUND_DOOR_RETRY_PASS_LIMIT,
		BaseCampRetryMin = ROUND_BASE_CAMP_RETRY_MIN,
		BaseCampRetryMax = ROUND_BASE_CAMP_RETRY_MAX,
	}
end)()

local setDoRoundEnabled = (function()
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

local function placeRoundToolsAtDoors(generation)
	local rejectedDoors = setmetatable({}, {__mode = "k"})
	local doorInstanceIds = setmetatable({}, {__mode = "k"})
	local nextDoorInstanceId = 0
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
			nextDoorInstanceId += 1
			id = nextDoorInstanceId
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
	local function rejectOrRetryCurrentDoor(toolKey, doorModel)
		local failures = (currentDoorFailures[toolKey] or 0) + 1
		currentDoorFailures[toolKey] = failures
		if doorModel and doorModel.Parent and failures < ROUND_DOOR_ATTEMPT_LIMIT then
			setDoRoundStatus(
				"Retrying current door ("
					.. tostring(failures + 1)
					.. "/"
					.. tostring(ROUND_DOOR_ATTEMPT_LIMIT)
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

	for _, toolName in ipairs(ROUND_HELD_ITEMS) do
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
				local retrying = rejectOrRetryCurrentDoor(toolKey, selectedDoor)
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
			local placementReason = "no safe, settled door-face position was found"
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
				if teleported
					and settleRoundDoorInteraction(door, 2, generation)
					and facePlayerTowardRoundDoor(door) then
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

local function openRoundExitDoor(generation)
	local function markRoundStarted()
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
	for _, itemName in ipairs(DROPPED_ROOM_ITEMS) do
		local normalized = normalizeRoundItemName(itemName)
		local existing = doRoundState.roomItems[normalized]
		if existing and roundWorldItemIsInsideRoom(existing, room) then
			continue
		end
		local inside
		local fallback
		for _, model in ipairs(candidatesByName[normalized] or {}) do
			fallback = fallback or model
			if roundWorldItemIsInsideRoom(model, room) then
				inside = model
				break
			end
		end
		doRoundState.roomItems[normalized] = inside
			or fallback
			or (existing and existing.Parent and not roundItemIsBurntCross(existing)
				and existing)
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
						doRoundState.maintenanceBackoff[model] = now + 0.5
						doRoundState.itemsDirty = true
					else
						doRoundState.maintenanceBackoff[model] = now
							+ ROUND_MAINTENANCE_RETRY_BACKOFF
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

	local setEnabled
	local function cancelRoundTask(fieldName)
		local thread = doRoundState[fieldName]
		doRoundState[fieldName] = nil
		if thread and thread ~= coroutine.running() then
			pcall(task.cancel, thread)
		end
	end
	local function releaseRoundMovement()
		for lock in pairs(doRoundState.facingLocks or {}) do
			pcall(lock.Release, lock)
		end
		doRoundState.facingLocks = setmetatable({}, {__mode = "k"})
		releasePlayerMovement(true)
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
		and tonumber(fallbackDetection.Confidence)
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
		setEnabled(false, finalPhase)
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
	releaseRoundMovement()
end

local function finishTimedRound(generation)
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

local function runDoRound(generation)
	local success, failure = xpcall(function()
		local identifiedGhost, identifiedScore, identifiedCertain =
			currentConfidentRoundIdentification()
		if identifiedGhost then
			completeIdentifiedRound(
				generation,
				identifiedGhost,
				identifiedScore,
				identifiedCertain
			)
			return
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

		waitForRoundHuntEnd(generation)
		if not doRoundOperationActive(generation) then
			return
		end
		identifiedGhost, identifiedScore, identifiedCertain =
			currentConfidentRoundIdentification()
		if identifiedGhost then
			completeIdentifiedRound(
				generation,
				identifiedGhost,
				identifiedScore,
				identifiedCertain
			)
			return
		end
		setDoRoundStatus("Placing room items")
		while roomItemPlacementState.busy
			and doRoundOperationActive(generation) do
			setDoRoundStatus("Waiting for room item setup")
			doRoundWait(generation, 0.15)
		end
		if not doRoundOperationActive(generation) then
			return
		end
		local started, placementGeneration =
			placeItemsInFavouriteRoom("DoRound")
		if started then
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
		captureRoundRoomItems(favouriteRoom)
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
			local stored = getRoundEquippedItem(itemName)
				or getRoundInventoryItem(itemName)
			if not findRoundHotbarSlot(itemName) and not stored then
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
		local exitAttempts = 0
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
				exitAttempts = exitAttempts + 1
				if presenter and presenter.Notify then
					presenter:Notify(
						(reason or "Exit door failed")
							.. "; retrying ("
							.. tostring(exitAttempts)
							.. "/3)"
					)
				end
					if exitAttempts >= 3 then
						-- Exit replication and door remotes can be transiently late. Do not
						-- switch automation off at an arbitrary early timestamp; remain safe,
						-- back off, and let identification/the three-minute watchdog retain
						-- ownership of round completion.
						exitAttempts = 0
						doRoundWait(generation, 1.5)
					else
						doRoundWait(generation, 0.5)
					end
				end
		until exitOpened

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
				ghost and ghost:GetAttribute("FavoriteRoom") or nil
			)
			if currentFavourite and currentFavourite ~= favouriteRoom then
				favouriteRoom = currentFavourite
				doRoundState.lastFavouriteRoom = favouriteRoom
				captureRoundRoomItems(favouriteRoom)
				doRoundState.itemsDirty = true
				doRoundState.nextMaintenanceAt = 0
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
		if returnRoundToBase(generation) then
			setEnabled(false, "Stopped")
		end
	end
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

setEnabled = function(enabled, finalPhase)
	enabled = enabled == true
	if doRoundState.enabled == enabled then
		if not enabled then
			cancelRoundTask("timeoutThread")
			cancelRoundTask("identificationThread")
			releaseRoundMovement()
		end
		if finalPhase then
			setDoRoundStatus(finalPhase)
		end
		return enabled
	end
	doRoundState.generation = doRoundState.generation + 1
	doRoundState.enabled = enabled
	if enabled then
		cancelRoundTask("timeoutThread")
		cancelRoundTask("identificationThread")
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
		startRoundIdentificationWatchdog(generation)
		startRoundTimeoutWatchdog(generation)
		doRoundState.thread = task.spawn(function()
			runDoRound(generation)
		end)
	else
		cancelRoundTask("timeoutThread")
		cancelRoundTask("identificationThread")
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
		releaseRoundMovement()
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
	return setEnabled
end)()
	return {
		SetEnabled = setDoRoundEnabled,
	}
end
