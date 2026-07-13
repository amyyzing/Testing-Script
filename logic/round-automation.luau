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
	local minimumDistance = math.min(
		math.max(thickness * 0.5 + 2.1, 2.2),
		4.5
	)
	local maximumDistance = 4.75
	local standDistance = math.clamp(
		thickness * 0.5 + 2.85,
		minimumDistance,
		maximumDistance
	)
	return {
		Reference = reference,
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
		MaximumTargetDistance = 5,
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
			return relative.Magnitude <= 4.75
				and lateral <= 0.65
				and signedNormal * approach.Side > 0
				and math.abs(signedNormal) >= geometry.MinimumDistance - 0.1
				and math.abs(signedNormal) <= geometry.MaximumDistance + 0.1
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
	if math.abs(signedNormal) < 0.05 or rootOffset.Magnitude > 5 then
		return nil, geometry, root
	end
	local expectedFacing = geometry.NormalAxis
		* (signedNormal > 0 and -1 or 1)
	return {
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
		root.CFrame = CFrame.lookAt(
			root.Position,
			root.Position + expectedFacing
		)
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
		and facing.Unit:Dot(expectedFacing) >= 0.985
		and math.abs(
			facing.Unit:Dot(context.Geometry.WideAxis)
		) <= 0.05
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
		Connection = nil,
	}
	function lock:Enforce()
		if self.Released then
			return false
		end
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
	end
	function lock:Release()
		if self.Released then
			return
		end
		self.Released = true
		if self.Connection and self.Connection.Connected then
			self.Connection:Disconnect()
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
	local connected, connection = pcall(function()
		return Services.RunService.PreSimulation:Connect(function()
			if not lock:Enforce() then
				lock:Release()
			end
		end)
	end)
	if not connected then
		pcall(function()
			context.Humanoid.AutoRotate = lock.OriginalAutoRotate
		end)
		return nil, "player facing lock could not bind to simulation"
	end
	lock.Connection = connection
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
	if rootOffset.Magnitude > 5
		or rootLateral > 0.65
		or math.abs(rootNormal) < geometry.MinimumDistance - 0.15
		or math.abs(rootNormal) > geometry.MaximumDistance + 0.15 then
		return false, geometry, root
	end
	local facing = Vector3.new(
		root.CFrame.LookVector.X,
		0,
		root.CFrame.LookVector.Z
	)
	local expectedFacing = geometry.NormalAxis * (rootNormal > 0 and -1 or 1)
	return facing.Magnitude >= 0.05
		and facing.Unit:Dot(expectedFacing) >= 0.985
		and math.abs(facing.Unit:Dot(geometry.WideAxis)) <= 0.05,
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
	if math.abs(previewOffset:Dot(geometry.WideAxis)) > 0.9
		or math.abs(previewOffset:Dot(geometry.NormalAxis)) > 2.5 then
		return false
	end
	if toolName == "Salt Canister" then
		local previewAxis = previewMajorAxis(previewPart)
		if not previewAxis
			or math.abs(previewAxis:Dot(geometry.WideAxis)) < 0.985 then
			return false
		end
	end
	return true
end

local waitForRoundPreview: any = function(toolName, target, generation)
	local deadline = os.clock() + 2.5
	local alignedSamples = 0
	repeat
		if not roundActionIsSafe(generation) then
			return false, roundUnsafeReason(generation)
		end
		if not facePlayerTowardRoundDoor(target) then
			alignedSamples = 0
			doRoundWait(generation, 0.05)
			continue
		end
		doRoundWait(generation, 0.05)
		if facePlayerTowardRoundDoor(target)
			and placementPreviewIsAligned(toolName, target) then
			alignedSamples = alignedSamples + 1
			if alignedSamples >= 2 then
				return true
			end
		else
			alignedSamples = 0
		end
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
	local dispatchAccepted = false
	local dispatchFailure
	local facingLock, facingReason = beginRoundDoorFacingLock(target)
	if not facingLock then
		return false, facingReason
	end
	local guarded, guardedFailure = xpcall(function()
		local aligned, alignReason = waitForRoundPreview(
			toolName,
			target,
			generation
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
		if not facingLock:Enforce()
			or not placementPreviewIsAligned(toolName, target) then
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
		beginAutomationMutation(2.5)
		if not facingLock:Enforce()
			or not placementPreviewIsAligned(toolName, target) then
			dispatchFailure =
				"player facing changed before placement dispatch"
			return
		end
		local fired = pcall(remote.FireServer, remote)
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
		if uses ~= nil and currentUses ~= nil and currentUses < uses then
			confirmed = true
			break
		end
		placementFolder = workspace:FindFirstChild(folderName)
		if placementFolder then
			for _, child in ipairs(placementFolder:GetChildren()) do
				if not existingPlacements[child] then
					local position = getInstanceWorldPosition(child)
					if position and targetFrame
						and (Vector3.new(position.X, 0, position.Z)
							- Vector3.new(
								targetFrame.Position.X,
								0,
								targetFrame.Position.Z
							)).Magnitude <= 5 then
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
		NormalizeItemName = normalizeRoundItemName,
		ItemName = roundItemName,
		FindHotbarSlot = findRoundHotbarSlot,
		GetEquippedItem = getRoundEquippedItem,
		EquipItem = equipRoundItem,
		ApproachPositions = roundApproachPositions,
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
	local getRoundEquippedItem = roundUtilities.GetEquippedItem
	local equipRoundItem = roundUtilities.EquipItem
	local roundApproachPositions = roundUtilities.ApproachPositions
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
	local unavailableTools = {}
	local warnings = {}
	local warningKeys = {}
	local function addWarning(key, message)
		if message and not warningKeys[key] then
			warningKeys[key] = true
			table.insert(warnings, message)
		end
	end
	local function selectDoor()
		local doors = eligibleRoundDoors(false)
		for _, doorModel in ipairs(doors) do
			local key = string.lower(tostring(doorModel.Name))
			if not doRoundState.usedDoorNames[key]
				and not rejectedDoorNames[key] then
				return doorModel, key
			end
		end
		local reusable = {}
		for _, doorModel in ipairs(doors) do
			local key = string.lower(tostring(doorModel.Name))
			if not rejectedDoorNames[key] then
				table.insert(reusable, {Model = doorModel, Key = key})
			end
		end
		if #reusable == 0 then
			return nil, nil
		end
		-- Exhaust every distinct name before beginning another door cycle.
		doRoundState.usedDoorNames = {}
		for _, candidate in ipairs(reusable) do
			if candidate.Key ~= doRoundState.lastDoorName then
				return candidate.Model, candidate.Key
			end
		end
		return reusable[1].Model, reusable[1].Key
	end

	while doRoundOperationActive(generation) do
		local pendingTools = 0
		local passAttemptedPlacement = false
		for _, toolName in ipairs(ROUND_HELD_ITEMS) do
			local toolKey = normalizeRoundItemName(toolName)
			if doRoundState.completedDoorTools[toolKey]
				or unavailableTools[toolKey] then
				continue
			end
			pendingTools = pendingTools + 1
			if not roundActionIsSafe(generation) then
				return false, roundUnsafeReason(generation)
			end
			local equipped, reason = equipRoundItem(toolName, 1.5, generation)
			if not equipped then
				local cachedUses = doRoundState.doorToolUses[toolKey]
				if cachedUses ~= nil and cachedUses <= 0 then
					doRoundState.completedDoorTools[toolKey] = true
					continue
				end
				if not findRoundHotbarSlot(toolName) then
					if cachedUses == nil then
						unavailableTools[toolKey] = true
						addWarning(toolKey .. ":missing", reason)
					else
						addWarning(
							toolKey .. ":missing-temporary",
							toolName
								.. " temporarily left the hotbar with Uses="
								.. tostring(cachedUses)
						)
					end
					continue
				end
				addWarning(toolKey .. ":equip", reason)
				continue
			end
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
				continue
			end
			doRoundState.doorToolUses[toolKey] = uses
			if uses <= 0 then
				doRoundState.completedDoorTools[toolKey] = true
				continue
			end

			local selectedDoor, selectedKey = selectDoor()
			if not selectedDoor then
				addWarning(
					toolKey .. ":doors",
					toolName
						.. " still has Uses="
						.. tostring(uses)
						.. ", but no safe non-exit door face was available"
				)
				rejectedDoorNames = {}
				continue
			end

			setDoRoundStatus(
				"Laying " .. toolName .. " (" .. tostring(uses) .. " left)"
			)
			local door = selectedDoor:FindFirstChild("Door") or selectedDoor
			local approaches = roundDoorApproaches(door)
			local placed = false
			local placementReason
			local dispatched = false
			local observedUses
			local teleportedToDoor = false
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
					teleportedToDoor = true
					doRoundState.usedDoorNames[selectedKey] = true
					doRoundState.lastDoorName = selectedKey
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
				passAttemptedPlacement = true
				doRoundState.doorToolPlacements[toolKey] =
					(doRoundState.doorToolPlacements[toolKey] or 0) + 1
			elseif dispatched then
				passAttemptedPlacement = true
				if placementReason == "hunt started"
					or placementReason == "ghost unavailable"
					or placementReason == "Do-Round cancelled" then
					return false, placementReason
				end
				addWarning(toolKey .. ":dispatch", placementReason)
			else
				if not teleportedToDoor then
					rejectedDoorNames[selectedKey] = true
				end
				addWarning(toolKey .. ":placement", placementReason)
			end
		end

		local remaining = 0
		for _, toolName in ipairs(ROUND_HELD_ITEMS) do
			local toolKey = normalizeRoundItemName(toolName)
			if not doRoundState.completedDoorTools[toolKey]
				and not unavailableTools[toolKey] then
				remaining = remaining + 1
			end
		end
		if remaining == 0 then
			return true, #warnings > 0 and table.concat(warnings, "; ") or nil
		end
		if pendingTools == 0 or not passAttemptedPlacement then
			doRoundWait(generation, 0.2)
		end
	end
	return false, "Do-Round cancelled"
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
			local approaches, center = roundDoorApproaches(door)
			for _, approach in ipairs(shuffleRoundList(approaches)) do
				if not roundActionIsSafe(generation) then
					return false, roundUnsafeReason(generation)
				end
				local teleported = teleportToRoundDoorFace(
					door,
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
		while roomItemPlacementState.busy
			and doRoundOperationActive(generation) do
			setDoRoundStatus("Waiting for room item setup")
			doRoundWait(generation, 0.15)
		end
		local started, placementGeneration =
			placeItemsInFavouriteRoom("DoRound")
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
		doRoundState.completedDoorTools = {}
		doRoundState.doorToolPlacements = {}
		doRoundState.doorToolUses = {}
		doRoundState.lastDoorName = nil
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
