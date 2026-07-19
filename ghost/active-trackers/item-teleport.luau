return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "item-teleport requires Traffic")
	local World = dependencies.Workspace or workspace
	local RunService = assert(dependencies.RunService, "item-teleport requires RunService")
	local clock = dependencies.Clock or os.clock
	local interval = tonumber(dependencies.SampleInterval) or 0.4
	local maximumElapsed = tonumber(dependencies.MaximumElapsed) or 0.65
	local minimumDistance = tonumber(dependencies.MinimumDisplacement) or 25
	local minimumDistanceSquared = minimumDistance * minimumDistance
	local findRoom = assert(dependencies.FindRoom, "item-teleport requires FindRoom")
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

	local function roomAt(point, previousRoom)
		local room = findRoom(point, previousRoom)
		return type(room) == "string" and room or room and room.Name or nil
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
