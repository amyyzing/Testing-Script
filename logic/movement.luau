return function(dependencies)
	local Services = assert(dependencies.Services, "movement requires Services")
	local player = assert(dependencies.Player, "movement requires Player")
	local runtimeIsActive = assert(dependencies.RuntimeIsActive, "movement requires RuntimeIsActive")
	local createRoomTeleport = assert(dependencies.CreateRoomTeleport, "movement requires CreateRoomTeleport")
	local getGhostModel = dependencies.GetGhostModel or function()
		return Services.Workspace:FindFirstChild("Ghost")
	end
	local workspace = Services.Workspace
	local closed = false

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

	local teleportToRoom = createRoomTeleport({
		Services = Services,
		Player = player,
		RuntimeIsActive = runtimeIsActive,
		GetRoomBoundingParts = getRoomBoundingParts,
		GetGhostModel = getGhostModel,
	})
	local perkTrackerState = {
		baseCampTeleportBusy = false,
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

perkTrackerState.teleportToBaseCamp = function(options)
	local room = perkTrackerState.findBaseCampRoom()
	if not room then
		return false, "Base Camp room was not found"
	end
	options = table.clone(options or {})
	local function alreadyInsideBaseCamp()
		local character = player.Character
		return character ~= nil and instanceIsInsideRoom(character, room)
	end
	if alreadyInsideBaseCamp() then
		return true, nil
	end
	while perkTrackerState.baseCampTeleportBusy do
		if closed
			or (type(options.IsActive) == "function"
				and options.IsActive() ~= true) then
			return false, "teleport was cancelled"
		end
		Services.RunService.Heartbeat:Wait()
	end
	if alreadyInsideBaseCamp() then
		return true, nil
	end

	perkTrackerState.baseCampTeleportBusy = true
	local succeeded, teleported, reason = pcall(function()
		if type(options.PreferredPositions) ~= "table"
			or #options.PreferredPositions == 0 then
			local baseCamp = workspace:FindFirstChild("BaseCamp")
				or workspace:FindFirstChild("Base Camp")
			local truck = baseCamp and baseCamp:FindFirstChild("Truck", true)
				or room:FindFirstChild("Truck", true)
				or workspace:FindFirstChild("Truck", true)
			local preferredPosition = getInstanceWorldPosition(truck)
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
							if preferredPosition then
								break
							end
						end
					end
				end
			end
			if preferredPosition then
				-- Candidate safety still wins; among open, grounded Base Camp
				-- destinations prefer the point nearest Truck. The exit is only a
				-- fallback when this map does not expose BaseCamp.Truck.
				options.PreferredPositions = {preferredPosition}
			end
		end
		return perkTrackerState.teleportToRoomBoundingBoxCenter(room, options)
	end)
	perkTrackerState.baseCampTeleportBusy = false
	if not succeeded then
		return false, tostring(teleported):match("^[^\n]+")
	end
	return teleported, reason
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
		TeleportToFavouriteRoom = perkTrackerState.teleportToFavouriteRoom,
	}
end
