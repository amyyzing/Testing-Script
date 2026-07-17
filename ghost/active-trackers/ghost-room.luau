return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "ghost-room requires Traffic")
	local World = dependencies.Workspace or workspace
	local Ghost = assert(dependencies.Ghost, "ghost-room requires Ghost")
	local RunService = assert(dependencies.RunService, "ghost-room requires RunService")
	local clock = dependencies.Clock or os.clock
	local interval = tonumber(dependencies.SampleInterval) or 0.25
	local customFindRoom = dependencies.FindRoom
	local customPosition = dependencies.Position
	local Tracker = {
		Kind = "active",
		Running = true,
		Accumulator = 0,
	}

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
		roomParts[room] = parts
		return parts
	end

	local function inside(room, point)
		for _, part in ipairs(boundingParts(room)) do
			local localPoint = part.CFrame:PointToObjectSpace(point)
			local half = part.Size * 0.5
			if math.abs(localPoint.X) <= half.X
				and math.abs(localPoint.Y) <= half.Y
				and math.abs(localPoint.Z) <= half.Z then return true end
		end
		return false
	end

	local function position()
		if customPosition then return customPosition(Ghost) end
		if Ghost:IsA("BasePart") then return Ghost.Position end
		return Ghost:GetPivot().Position
	end

	local function findRoom(point)
		if customFindRoom then return customFindRoom(point, Tracker.Room) end
		local map = World:FindFirstChild("Map")
		local rooms = map and map:FindFirstChild("Rooms")
		if not rooms then return nil end
		if Tracker.Room and Tracker.Room.Parent and inside(Tracker.Room, point) then
			return Tracker.Room
		end
		for _, room in ipairs(rooms:GetChildren()) do
			if room ~= Tracker.Room and inside(room, point) then return room end
		end
		return nil
	end

	function Tracker:Sample()
		local room = findRoom(position())
		if room == self.Room then return end
		self.Room = room
		Traffic("GhostRoom", {
			Room = room,
			RoomName = room and room.Name or nil,
			Time = clock(),
		}):SendTo("RoomTemperature")
	end

	Tracker.Connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not Tracker.Running then return end
		Tracker.Accumulator += math.max(0, tonumber(deltaTime) or 0)
		if Tracker.Accumulator < interval then return end
		Tracker.Accumulator %= interval
		Tracker:Sample()
	end)
	Tracker:Sample()

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Connection:Disconnect()
		table.clear(roomParts)
	end

	return Tracker
end
