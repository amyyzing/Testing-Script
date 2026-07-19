return function(dependencies)
	local Services = assert(dependencies.Services, "movement requires Services")
	local player = assert(dependencies.Player, "movement requires Player")
	local runtimeIsActive = assert(dependencies.RuntimeIsActive, "movement requires RuntimeIsActive")
	local createRoomTeleport = assert(dependencies.CreateRoomTeleport, "movement requires CreateRoomTeleport")
	local getGhostModel = dependencies.GetGhostModel or function()
		return Services.Workspace:FindFirstChild("Ghost")
	end
	local workspace = Services.Workspace

local function findRoomsFolder()
	local map = workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Rooms") or nil
end
local function findFavouriteRoom(roomsFolder, roomName)
	if not roomsFolder or not roomName then
		return nil
	end
	local direct = roomsFolder:FindFirstChild(tostring(roomName))
	if direct then
		return direct
	end
	local target = string.lower(tostring(roomName))
	for _, room in ipairs(roomsFolder:GetChildren()) do
		if string.lower(room.Name) == target then
			return room
		end
	end
	return nil
end

local function pointIsInsidePart(part, position)
	local localPosition = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end
local function getInstanceWorldPosition(instance)
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end
local roomBoundingPartsCache = setmetatable({}, {__mode = "k"})
local function getRoomBoundingParts(room)
	if not room then
		return {}
	end
	local cached = roomBoundingPartsCache[room]
	if cached and #cached > 0 then
		local valid = true
		for _, part in ipairs(cached) do
			if not part.Parent or not part:IsDescendantOf(room) then
				valid = false
				break
			end
		end
		if valid then
			return cached
		end
	end
	local parts = {}
	local seen = setmetatable({}, {__mode = "k"})
	local boundingBoxes = {}
	local direct = room:FindFirstChild("BoundingBox")
	if direct then
		table.insert(boundingBoxes, direct)
	end
	for _, descendant in ipairs(room:GetDescendants()) do
		if descendant.Name == "BoundingBox" and descendant ~= direct then
			table.insert(boundingBoxes, descendant)
		end
	end
	local function addPart(part)
		if part and part:IsA("BasePart") and not seen[part] then
			seen[part] = true
			table.insert(parts, part)
		end
	end
	for _, boundingBox in ipairs(boundingBoxes) do
		if boundingBox:IsA("BasePart") then
			addPart(boundingBox)
		else
			local countBeforeBoundingBox = #parts
			for _, child in ipairs(boundingBox:GetChildren()) do
				if child:IsA("BasePart") and child.Name == "Part" then
					addPart(child)
				end
			end
			if #parts == countBeforeBoundingBox then
				for _, child in ipairs(boundingBox:GetChildren()) do
					if child:IsA("BasePart") then
						addPart(child)
					end
				end
			end
			if #parts == countBeforeBoundingBox then
				for _, descendant in ipairs(boundingBox:GetDescendants()) do
					if descendant:IsA("BasePart") then
						addPart(descendant)
					end
				end
			end
		end
	end
	if #parts > 0 then
		roomBoundingPartsCache[room] = parts
	else
		roomBoundingPartsCache[room] = nil
	end
	return parts
end
local function instanceIsInsideRoom(instance, room)
	local position = getInstanceWorldPosition(instance)
	if not position then
		return false
	end
	for _, part in ipairs(getRoomBoundingParts(room)) do
		if pointIsInsidePart(part, position) then
			return true
		end
	end
	return false
end

	local teleportControl = {}
	local teleportToRoom = createRoomTeleport({
		Services = Services,
		Player = player,
		RuntimeIsActive = runtimeIsActive,
		GetRoomBoundingParts = getRoomBoundingParts,
		GetGhostModel = getGhostModel,
		Control = teleportControl,
	})
	local perkTrackerState = {
		teleportSequence = 0,
		teleportToRoomBoundingBoxCenter = teleportToRoom,
	}

perkTrackerState.findBaseCampRoom = function()
	local roomsFolder = findRoomsFolder()
	if not roomsFolder then
		return nil
	end
	return roomsFolder:FindFirstChild("Base Camp")
		or roomsFolder:FindFirstChild("BaseCamp")
		or findFavouriteRoom(roomsFolder, "Base Camp")
end

local baseCampEscapePivot
local function rememberBaseCampEscapePivot(character)
	if not character or type(character.GetPivot) ~= "function" then
		return baseCampEscapePivot
	end
	local ok, pivot = pcall(character.GetPivot, character)
	if ok and pivot ~= nil then
		baseCampEscapePivot = pivot
	end
	return baseCampEscapePivot
end

perkTrackerState.teleportToBaseCamp = function(options)
	local room = perkTrackerState.findBaseCampRoom()
	if not room then
		return false, "Base Camp room was not found"
	end
	options = table.clone(options or {})
	if options.MinimumOpenClearance == nil then
		options.MinimumOpenClearance = 2.1
	end
	if options.StrictSearchExpansion == nil then
		options.StrictSearchExpansion = 5
	end
	if options.PreferOpenSpace == nil then
		options.PreferOpenSpace = true
	end
	if options.PreferClosestOpenSpace == nil then
		options.PreferClosestOpenSpace = true
	end
	local preferredPosition
	if type(options.PreferredPositions) ~= "table"
		or #options.PreferredPositions == 0 then
		local baseCamp = workspace:FindFirstChild("BaseCamp")
			or workspace:FindFirstChild("Base Camp")
		local truck = baseCamp and baseCamp:FindFirstChild("Truck", true)
			or room:FindFirstChild("Truck", true)
			or workspace:FindFirstChild("Truck", true)
		preferredPosition = getInstanceWorldPosition(truck)
		if not preferredPosition then
			local doors = workspace:FindFirstChild("Doors")
			if doors then
				for _, object in ipairs(doors:GetDescendants()) do
					local normalized = string.lower(object.Name):gsub("[^%w]", "")
					local doorType = string.lower(tostring(
						object:GetAttribute("DoorType")
							or object:GetAttribute("Type")
							or ""
					)):gsub("[^%w]", "")
					if string.find(normalized, "exitdoor", 1, true)
						or object:GetAttribute("IsExitDoor") == true
						or object:GetAttribute("ExitDoor") == true
						or doorType == "exit"
						or doorType == "exitdoor" then
						preferredPosition = getInstanceWorldPosition(object)
						if preferredPosition then break end
					end
				end
			end
		end
		if preferredPosition then
			options.PreferredPositions = {preferredPosition}
		end
	else
		preferredPosition = options.PreferredPositions[1]
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local alreadyInside = root and root:IsA("BasePart")
		and instanceIsInsideRoom(root, room)
	-- Completion deliberately requests a fresh PivotTo even when the local root
	-- already appears nearby. This gives the server a real position update before
	-- RequestReturnToLobby checks whether everyone is in Base Camp.
	if alreadyInside and options.ForcePreferredPosition ~= true then
		rememberBaseCampEscapePivot(character)
		return true, nil
	end
	local succeeded, teleported, reason = pcall(function()
		return perkTrackerState.teleportToRoomBoundingBoxCenter(room, options)
	end)
	if not succeeded then
		return false, tostring(teleported):match("^[^\n]+")
	end
	if teleported and player.Character == character
		and root and instanceIsInsideRoom(root, room) then
		rememberBaseCampEscapePivot(character)
	end
	return teleported, reason
end

local function captureBaseCampEscapePivot()
	local room = perkTrackerState.findBaseCampRoom()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if room and character and root and instanceIsInsideRoom(root, room) then
		rememberBaseCampEscapePivot(character)
	end
	return baseCampEscapePivot
end

local function fastTeleportToBaseCamp()
	local room = perkTrackerState.findBaseCampRoom()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local destination = baseCampEscapePivot or captureBaseCampEscapePivot()
	if not room or not character or not root or not humanoid or not destination then
		return false, "no cached Base Camp escape position"
	end
	if type(teleportControl.Cancel) == "function" then
		teleportControl.Cancel()
	end
	local moved = pcall(function()
		character:PivotTo(destination)
		humanoid.Sit = false
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
		root.Anchored = false
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		for _, state in ipairs({
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Freefall,
		}) do
			humanoid:SetStateEnabled(state, true)
		end
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
	if not moved then
		return false, "cached Base Camp pivot failed"
	end
	Services.RunService.Heartbeat:Wait()
	if player.Character ~= character or not root.Parent then
		return false, "character changed during hunt escape"
	end
	character:PivotTo(destination)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return instanceIsInsideRoom(root, room), nil
end
perkTrackerState.teleportToFavouriteRoom = function(options)
	local ghost = getGhostModel()
	local roomsFolder = findRoomsFolder()
	local roomName = ghost and ghost:GetAttribute("FavoriteRoom") or nil
	local room = findFavouriteRoom(roomsFolder, roomName)
	if not room then
		return false, "Favourite room was not found: " .. tostring(roomName)
	end
	return perkTrackerState.teleportToRoomBoundingBoxCenter(room, options)
end

	return {
		FindRoomsFolder = findRoomsFolder,
		FindFavouriteRoom = findFavouriteRoom,
		FindBaseCampRoom = perkTrackerState.findBaseCampRoom,
		GetInstanceWorldPosition = getInstanceWorldPosition,
		GetRoomBoundingParts = getRoomBoundingParts,
		PointIsInsidePart = pointIsInsidePart,
		InstanceIsInsideRoom = instanceIsInsideRoom,
		TeleportToRoom = teleportToRoom,
		TeleportToBaseCamp = perkTrackerState.teleportToBaseCamp,
		CaptureBaseCampEscapePivot = captureBaseCampEscapePivot,
		FastTeleportToBaseCamp = fastTeleportToBaseCamp,
		TeleportToFavouriteRoom = perkTrackerState.teleportToFavouriteRoom,
	}
end
