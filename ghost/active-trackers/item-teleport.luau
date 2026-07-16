return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "item-teleport requires Traffic")
	local World = dependencies.Workspace or workspace
	local RunService = assert(dependencies.RunService, "item-teleport requires RunService")
	local clock = dependencies.Clock or os.clock
	local interval = tonumber(dependencies.SampleInterval) or 0.4
	local maximumElapsed = tonumber(dependencies.MaximumElapsed) or 0.65
	local minimumDistance = tonumber(dependencies.MinimumDisplacement) or 25
	local customRoomAt = dependencies.RoomAt
	local Tracker = {
		Kind = "active",
		Running = true,
		Previous = setmetatable({}, {__mode = "k"}),
		BoundContainers = setmetatable({}, {__mode = "k"}),
		Connections = {},
		Accumulator = 0,
		NextId = 0,
	}

	local function position(object)
		if object:IsA("BasePart") then return object.Position end
		if not object:IsA("Model") then return nil end
		local ok, pivot = pcall(object.GetPivot, object)
		return ok and pivot.Position or nil
	end

	local function distance(first, second)
		local dx = first.X - second.X
		local dy = first.Y - second.Y
		local dz = first.Z - second.Z
		return math.sqrt(dx * dx + dy * dy + dz * dz)
	end

	local roomParts = setmetatable({}, {__mode = "k"})
	local function boundingParts(room)
		if roomParts[room] then return roomParts[room] end
		local parts = {}
		for _, object in ipairs(room:GetDescendants()) do
			if object:IsA("BasePart") then
				local parent = object
				while parent and parent ~= room and parent.Name ~= "BoundingBox" do
					parent = parent.Parent
				end
				if object.Name == "BoundingBox" or parent and parent.Name == "BoundingBox" then
					table.insert(parts, object)
				end
			end
		end
		if #parts > 0 then roomParts[room] = parts end
		return parts
	end

	local cachedRooms
	local function roomsFolder()
		if cachedRooms and cachedRooms.Parent then return cachedRooms end
		local map = World:FindFirstChild("Map")
		cachedRooms = map and map:FindFirstChild("Rooms")
		return cachedRooms
	end

	local function insideRoom(room, point)
		for _, part in ipairs(boundingParts(room)) do
			local localPoint = part.CFrame:PointToObjectSpace(point)
			local half = part.Size * 0.5
			if math.abs(localPoint.X) <= half.X
				and math.abs(localPoint.Y) <= half.Y
				and math.abs(localPoint.Z) <= half.Z then return true end
		end
		return false
	end

	local function roomAt(point, previousRoom)
		if customRoomAt then return customRoomAt(point) end
		local rooms = roomsFolder()
		if not rooms then return nil end
		local previous = previousRoom and rooms:FindFirstChild(previousRoom)
		if previous and insideRoom(previous, point) then return previous.Name end
		for _, room in ipairs(rooms:GetChildren()) do
			if room ~= previous and insideRoom(room, point) then return room.Name end
		end
		return nil
	end

	function Tracker:BindContainer(container)
		if self.BoundContainers[container] then return end
		self.BoundContainers[container] = true
		for _, signal in ipairs({container.ChildAdded, container.ChildRemoved}) do
			if signal then
				table.insert(self.Connections, signal:Connect(function(object)
					self.Previous[object] = nil
				end))
			end
		end
	end

	function Tracker:Sample()
		local now = clock()
		local seen = setmetatable({}, {__mode = "k"})
		for _, containerName in ipairs({"Items", "Interactables"}) do
			local container = World:FindFirstChild(containerName)
			if container then self:BindContainer(container) end
			for _, object in ipairs(container and container:GetChildren() or {}) do
				local current = position(object)
				if current then
					seen[object] = true
					local previous = self.Previous[object]
					local currentRoom = roomAt(current, previous and previous.Room)
					if previous then
						local elapsed = now - previous.Time
						local displacement = distance(current, previous.Position)
						if elapsed > 0 and elapsed <= maximumElapsed
							and displacement >= minimumDistance
							and previous.Room and currentRoom
							and previous.Room ~= currentRoom then
							self.NextId += 1
							Traffic("ItemTeleported", {
								EventId = "item-teleport-" .. self.NextId,
								Item = object,
								From = previous.Position,
								To = current,
								Distance = displacement,
								Elapsed = elapsed,
								FromRoom = previous.Room,
								ToRoom = currentRoom,
								Time = now,
							}):SendTo("SmokeHolder")
						end
					end
					self.Previous[object] = {Position = current, Room = currentRoom, Time = now}
				end
			end
		end
		for object in pairs(self.Previous) do
			if not seen[object] then self.Previous[object] = nil end
		end
	end

	Tracker:Sample()
	Tracker.Connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not Tracker.Running then return end
		Tracker.Accumulator += math.max(0, tonumber(deltaTime) or 0)
		if Tracker.Accumulator < interval then return end
		Tracker.Accumulator %= interval
		Tracker:Sample()
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Connection:Disconnect()
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
		table.clear(self.Previous)
	end

	return Tracker
end
