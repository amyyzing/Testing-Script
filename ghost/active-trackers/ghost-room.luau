return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "ghost-room requires Traffic")
	local Ghost = assert(dependencies.Ghost, "ghost-room requires Ghost")
	local RunService = assert(dependencies.RunService, "ghost-room requires RunService")
	local clock = dependencies.Clock or os.clock
	local interval = tonumber(dependencies.SampleInterval) or 0.25
	local findRoom = assert(dependencies.FindRoom, "ghost-room requires FindRoom")
	local customPosition = dependencies.Position
	local Tracker = {
		Kind = "active",
		Running = true,
		Accumulator = 0,
	}

	local function position()
		if customPosition then return customPosition(Ghost) end
		if Ghost:IsA("BasePart") then return Ghost.Position end
		return Ghost:GetPivot().Position
	end

	function Tracker:Sample()
		local room = findRoom(position(), self.Room)
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
	end

	return Tracker
end
