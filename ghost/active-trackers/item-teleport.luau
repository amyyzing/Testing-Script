return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "item-teleport requires Traffic")
	local World = dependencies.Workspace or workspace
	local RunService = assert(dependencies.RunService, "item-teleport requires RunService")
	local clock = dependencies.Clock or os.clock
	local interval = tonumber(dependencies.SampleInterval) or 0.4
	local maximumElapsed = tonumber(dependencies.MaximumElapsed) or 0.65
	local minimumDistance = tonumber(dependencies.MinimumDisplacement) or 25
	local minimumDistanceSquared = minimumDistance * minimumDistance
	local customRoomAt = dependencies.RoomAt
	local Tracker = {
		Kind = "active",
		Running = true,
		Previous = setmetatable({}, {__mode = "k"}),
		Objects = setmetatable({}, {__mode = "k"}),
		BoundContainers = setmetatable({}, {__mode = "k"}),
		Connections = {},
		Accumulator = 0,
		NextId = 0,
	}

	local function position(object)
		if object:IsA("BasePart") then return object.Position end
		if not object:IsA("Model") then return nil end
		return object:GetPivot().Position
	end

	local function distanceSquared(first, second)
		local dx = first.X - second.X
		local dy = first.Y - second.Y
		local dz = first.Z - second.Z
		return dx * dx + dy * dy + dz * dz
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
		for _, object in ipairs(container:GetChildren()) do self.Objects[object] = true end
		table.insert(self.Connections, container.ChildAdded:Connect(function(object)
			self.Objects[object] = true
			self.Previous[object] = nil
		end))
		table.insert(self.Connections, container.ChildRemoved:Connect(function(object)
			self.Objects[object] = nil
			self.Previous[object] = nil
		end))
	end

	function Tracker:Sample()
		local now = clock()
		for object in pairs(self.Objects) do
			local current = position(object)
			if not current then
				self.Previous[object] = nil
			else
				local previous = self.Previous[object]
				if previous then
					local sampleElapsed = now - previous.Time
					local displacementSquared = distanceSquared(current, previous.Position)
					if displacementSquared <= 0.000001 then
						previous.Position, previous.Time = current, now
						continue
					end
					local currentRoom = roomAt(current, previous.Room)
					if sampleElapsed > 0 and sampleElapsed <= maximumElapsed
						and displacementSquared >= minimumDistanceSquared
						and previous.Room and currentRoom
						and previous.Room ~= currentRoom then
						self.NextId += 1
						Traffic("ItemTeleported", {
							EventId = "item-teleport-" .. self.NextId,
							Item = object,
							From = previous.Position,
							To = current,
							Distance = math.sqrt(displacementSquared),
							Elapsed = sampleElapsed,
							FromRoom = previous.Room,
							ToRoom = currentRoom,
							Time = now,
						}):SendTo("SmokeHolder")
					end
					previous.Position, previous.Room, previous.Time = current, currentRoom, now
				else
					local currentRoom = roomAt(current)
					self.Previous[object] = {Position = current, Room = currentRoom, Time = now}
				end
			end
		end
	end

	for _, containerName in ipairs({"Items", "Interactables"}) do
		local container = World:FindFirstChild(containerName)
		if container then Tracker:BindContainer(container) end
	end
	if World.ChildAdded then
		table.insert(Tracker.Connections, World.ChildAdded:Connect(function(container)
			if container.Name == "Items" or container.Name == "Interactables" then
				Tracker:BindContainer(container)
			end
		end))
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
		table.clear(self.Objects)
	end

	return Tracker
end
