return function(dependencies)
	local Services = assert(dependencies.Services, "movement requires Services")
	local player = assert(dependencies.Player, "movement requires Player")
	local runtimeIsActive = assert(dependencies.RuntimeIsActive, "movement requires RuntimeIsActive")
	local createTeleportation = assert(dependencies.CreateTeleportation, "movement requires CreateTeleportation")
	local createRoomTeleport = assert(dependencies.CreateRoomTeleport, "movement requires CreateRoomTeleport")
	local getGhostModel = dependencies.GetGhostModel or function()
		return Services.Workspace:FindFirstChild("Ghost")
	end
	local world = Services.Workspace

	local function findRoomsFolder()
		local map = world:FindFirstChild("Map")
		return map and map:FindFirstChild("Rooms") or nil
	end

	local function findFavouriteRoom(roomsFolder, roomName)
		if not roomsFolder or not roomName then return nil end
		local direct = roomsFolder:FindFirstChild(tostring(roomName))
		if direct then return direct end
		local target = string.lower(tostring(roomName))
		for _, room in ipairs(roomsFolder:GetChildren()) do
			if string.lower(room.Name) == target then return room end
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
		if not instance then return nil end
		if instance:IsA("BasePart") then return instance.Position end
		if instance:IsA("Model") then return instance:GetPivot().Position end
		local part = instance:FindFirstChildWhichIsA("BasePart", true)
		return part and part.Position or nil
	end

	local roomBoundingPartsCache = setmetatable({}, {__mode = "k"})
	local function getRoomBoundingParts(room)
		if not room then return {} end
		local cachedEntry = roomBoundingPartsCache[room]
		local cached = cachedEntry and cachedEntry.Parts
		if cached and #cached > 0
			and os.clock() - (cachedEntry.ScannedAt or 0) < 0.75 then
			local valid = true
			for _, part in ipairs(cached) do
				if not part.Parent or not part:IsDescendantOf(room) then
					valid = false
					break
				end
			end
			if valid then return cached end
		end

		local parts = {}
		local seen = setmetatable({}, {__mode = "k"})
		local boundingBoxes = {}
		local direct = room:FindFirstChild("BoundingBox")
		if direct then table.insert(boundingBoxes, direct) end
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
				local before = #parts
				for _, child in ipairs(boundingBox:GetChildren()) do
					if child:IsA("BasePart") and child.Name == "Part" then addPart(child) end
				end
				if #parts == before then
					for _, child in ipairs(boundingBox:GetChildren()) do addPart(child) end
				end
				if #parts == before then
					for _, child in ipairs(boundingBox:GetDescendants()) do addPart(child) end
				end
			end
		end
		roomBoundingPartsCache[room] = #parts > 0 and {
			Parts = parts,
			ScannedAt = os.clock(),
		} or nil
		return parts
	end

	local function instanceIsInsideRoom(instance, room)
		local position = getInstanceWorldPosition(instance)
		if not position then return false end
		for _, part in ipairs(getRoomBoundingParts(room)) do
			if pointIsInsidePart(part, position) then return true end
		end
		return false
	end

	local teleportation = createTeleportation({
		Services = Services,
		Player = player,
		RuntimeIsActive = runtimeIsActive,
		FindRoomsFolder = findRoomsFolder,
		GetInstanceWorldPosition = getInstanceWorldPosition,
		GetRoomBoundingParts = getRoomBoundingParts,
		PointIsInsidePart = pointIsInsidePart,
	})
	local teleportToRoom = createRoomTeleport({
		Services = Services,
		Player = player,
		RuntimeIsActive = runtimeIsActive,
		GetRoomBoundingParts = getRoomBoundingParts,
		GetGhostModel = getGhostModel,
		Teleportation = teleportation,
	})

	local function findBaseCampRoom()
		local roomsFolder = findRoomsFolder()
		if not roomsFolder then return nil end
		local namedRoom = roomsFolder:FindFirstChild("Base Camp")
			or roomsFolder:FindFirstChild("BaseCamp")
			or findFavouriteRoom(roomsFolder, "Base Camp")
		if namedRoom then return namedRoom end
		local baseCamp = world:FindFirstChild("BaseCamp") or world:FindFirstChild("Base Camp")
		local truck = baseCamp and baseCamp:FindFirstChild("Truck", true)
			or world:FindFirstChild("Truck", true)
		local truckPosition = getInstanceWorldPosition(truck)
		if not truck or not truckPosition then return nil end
		return teleportation.FindRoomForTarget(truck, {truckPosition})
	end

	local function teleportToBaseCamp(options)
		local room = findBaseCampRoom()
		if not room then return false, "Base Camp room was not found" end
		options = table.clone(options or {})
		if options.MinimumOpenClearance == nil then options.MinimumOpenClearance = 2.1 end
		if options.StrictSearchExpansion == nil then options.StrictSearchExpansion = 5 end
		if options.PreferOpenSpace == nil then options.PreferOpenSpace = true end
		if options.PreferClosestOpenSpace == nil then options.PreferClosestOpenSpace = true end
		local preferredPosition
		if type(options.PreferredPositions) ~= "table" or #options.PreferredPositions == 0 then
			local baseCamp = world:FindFirstChild("BaseCamp") or world:FindFirstChild("Base Camp")
			local truck = baseCamp and baseCamp:FindFirstChild("Truck", true)
				or room:FindFirstChild("Truck", true)
				or world:FindFirstChild("Truck", true)
			preferredPosition = getInstanceWorldPosition(truck)
			if not preferredPosition then
				local doors = world:FindFirstChild("Doors")
				if doors then
					for _, object in ipairs(doors:GetDescendants()) do
						local normalized = string.lower(object.Name):gsub("[^%w]", "")
						local doorType = string.lower(tostring(object:GetAttribute("DoorType")
							or object:GetAttribute("Type") or "")):gsub("[^%w]", "")
						if string.find(normalized, "exitdoor", 1, true)
							or object:GetAttribute("IsExitDoor") == true
							or object:GetAttribute("ExitDoor") == true
							or doorType == "exit" or doorType == "exitdoor" then
							preferredPosition = getInstanceWorldPosition(object)
							if preferredPosition then break end
						end
					end
				end
			end
			if preferredPosition then options.PreferredPositions = {preferredPosition} end
		else
			preferredPosition = options.PreferredPositions[1]
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local alreadyInside = root and root:IsA("BasePart") and instanceIsInsideRoom(root, room)
		if alreadyInside and (options.ForcePreferredPosition ~= true or not preferredPosition
			or Vector3.new(root.Position.X - preferredPosition.X, 0,
				root.Position.Z - preferredPosition.Z).Magnitude <= 6) then
			return true, nil
		end
		local ok, moved, reason = pcall(teleportToRoom, room, options)
		if not ok then return false, tostring(moved):match("^[^\n]+") end
		return moved, reason
	end

	local function teleportToFavouriteRoom(options)
		local ghost = getGhostModel()
		local rooms = findRoomsFolder()
		local roomName = ghost and ghost:GetAttribute("FavoriteRoom") or nil
		local room = findFavouriteRoom(rooms, roomName)
		if not room then return false, "Favourite room was not found: " .. tostring(roomName) end
		return teleportToRoom(room, options)
	end

	return {
		FindRoomsFolder = findRoomsFolder,
		FindFavouriteRoom = findFavouriteRoom,
		FindBaseCampRoom = findBaseCampRoom,
		GetInstanceWorldPosition = getInstanceWorldPosition,
		GetRoomBoundingParts = getRoomBoundingParts,
		PointIsInsidePart = pointIsInsidePart,
		InstanceIsInsideRoom = instanceIsInsideRoom,
		Teleportation = teleportation,
		TeleportToRoom = teleportToRoom,
		TeleportToBaseCamp = teleportToBaseCamp,
		TeleportToFavouriteRoom = teleportToFavouriteRoom,
	}
end
