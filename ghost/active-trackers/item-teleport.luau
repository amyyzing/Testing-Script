return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "item-teleport requires Traffic")
	local World = dependencies.Workspace or workspace
	local RunService = assert(dependencies.RunService, "item-teleport requires RunService")
	local clock = dependencies.Clock or os.clock
	local interval = tonumber(dependencies.SampleInterval) or 0.4
	local maximumElapsed = tonumber(dependencies.MaximumElapsed) or 0.65
	local minimumDistance = tonumber(dependencies.MinimumDisplacement) or 25
	local minimumSpeed = tonumber(dependencies.MinimumSpeed) or 80
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
					if previous then
						local elapsed = now - previous.Time
						local displacement = distance(current, previous.Position)
						if elapsed > 0 and elapsed <= maximumElapsed
							and displacement >= minimumDistance
							and displacement / elapsed >= minimumSpeed then
							self.NextId += 1
							Traffic("ItemTeleported", {
								EventId = "item-teleport-" .. self.NextId,
								Item = object,
								From = previous.Position,
								To = current,
								Distance = displacement,
								Elapsed = elapsed,
								Time = now,
							}):SendTo("SmokeHolder")
						end
					end
					self.Previous[object] = {Position = current, Time = now}
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
