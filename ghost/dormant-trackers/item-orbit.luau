return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "item-orbit requires Traffic")
	local World = dependencies.Workspace or workspace
	local Ghost = assert(dependencies.Ghost, "item-orbit requires Ghost")
	local RunService = assert(dependencies.RunService, "item-orbit requires RunService")
	local clock = dependencies.Clock or os.clock
	local interval = tonumber(dependencies.SampleInterval) or 0.1
	local radiusTolerance = tonumber(dependencies.RadiusTolerance) or 0.3
	local minimumRotation = tonumber(dependencies.MinimumRotation) or math.rad(90)
	local minimumStep = tonumber(dependencies.MinimumAngleStep) or math.rad(0.25)
	local activeWindow = tonumber(dependencies.ActiveWindow) or 0.5
	local minimumObjects = tonumber(dependencies.MinimumObjects) or 3
	local Tracker = {
		Kind = "dormant",
		Running = true,
		Active = false,
		Reported = false,
		Accumulator = 0,
		Objects = setmetatable({}, {__mode = "k"}),
		States = setmetatable({}, {__mode = "k"}),
		Containers = setmetatable({}, {__mode = "k"}),
		Connections = {},
	}

	local function position(object)
		if object:IsA("BasePart") then return object.Position end
		if object:IsA("Model") then return object:GetPivot().Position end
	end

	local function resetState(radius, angle)
		return {
			Radius = radius,
			Angle = angle,
			Direction = 0,
			Rotation = 0,
			Steps = 0,
		}
	end

	local function observe(object, centre, now)
		local point = position(object)
		if not point then
			Tracker.States[object] = nil
			return
		end
		local x, z = point.X - centre.X, point.Z - centre.Z
		local radius = math.sqrt(x * x + z * z)
		if radius < 1 then
			Tracker.States[object] = nil
			return
		end
		local angle = math.atan2(z, x)
		local state = Tracker.States[object]
		if not state then
			Tracker.States[object] = resetState(radius, angle)
			return
		end
		if math.abs(radius - state.Radius) > math.max(0.75, state.Radius * radiusTolerance) then
			Tracker.States[object] = resetState(radius, angle)
			return
		end
		local delta = math.atan2(math.sin(angle - state.Angle), math.cos(angle - state.Angle))
		if math.abs(delta) < minimumStep then return end
		local direction = delta > 0 and 1 or -1
		if state.Direction ~= 0 and state.Direction ~= direction then
			state = resetState(radius, angle)
			state.Direction = direction
			state.Rotation = math.abs(delta)
			state.Steps = 1
			Tracker.States[object] = state
		else
			state.Direction = direction
			state.Rotation += math.abs(delta)
			state.Steps += 1
			state.Angle = angle
			state.Radius = (state.Radius * 3 + radius) / 4
		end
		state.LastProgress = now
		state.Qualified = state.Steps >= 3 and state.Rotation + 0.000001 >= minimumRotation
	end

	function Tracker:Track(object)
		if object:IsA("Model") then self.Objects[object] = true end
	end

	function Tracker:BindContainer(container)
		if self.Containers[container] then return end
		self.Containers[container] = true
		for _, object in ipairs(container:GetChildren()) do self:Track(object) end
		table.insert(self.Connections, container.ChildAdded:Connect(function(object)
			self:Track(object)
		end))
		table.insert(self.Connections, container.ChildRemoved:Connect(function(object)
			self.Objects[object] = nil
			self.States[object] = nil
		end))
	end

	function Tracker:Sample()
		if not self.Active or self.Reported then return end
		local centre = position(Ghost)
		if not centre then return end
		local now = clock()
		for object in pairs(self.Objects) do observe(object, centre, now) end
		local orbiting = {}
		for object, state in pairs(self.States) do
			if state.Qualified and state.LastProgress
				and now - state.LastProgress <= activeWindow then
				table.insert(orbiting, object)
			end
		end
		if #orbiting < minimumObjects then return end
		self.Reported = true
		Traffic("ItemOrbit", {
			Objects = orbiting,
			Count = #orbiting,
			Time = now,
		}):SendTo("Ravager")
	end

	local function stopSampling()
		if not Tracker.SampleConnection then return end
		Tracker.SampleConnection:Disconnect()
		Tracker.SampleConnection = nil
	end

	local function setHunting(hunting)
		stopSampling()
		Tracker.Active = hunting == true
		Tracker.Reported = false
		Tracker.Accumulator = 0
		table.clear(Tracker.States)
		if not Tracker.Active then return end
		Tracker.SampleConnection = RunService.Heartbeat:Connect(function(deltaTime)
			if not Tracker.Running then return end
			Tracker.Accumulator += math.max(0, tonumber(deltaTime) or 0)
			if Tracker.Accumulator < interval then return end
			Tracker.Accumulator %= interval
			Tracker:Sample()
		end)
	end

	for _, name in ipairs({"Items", "Interactables"}) do
		local container = World:FindFirstChild(name)
		if container then Tracker:BindContainer(container) end
	end
	if World.ChildAdded then
		table.insert(Tracker.Connections, World.ChildAdded:Connect(function(container)
			if container.Name == "Items" or container.Name == "Interactables" then
				Tracker:BindContainer(container)
			end
		end))
	end
	Tracker.Disconnect = Traffic:Receive("ItemOrbit", function(signal, payload)
		if signal == "HuntingState" then
			setHunting(type(payload) == "table" and payload.Hunting == true)
		end
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
		stopSampling()
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
		table.clear(self.Objects)
		table.clear(self.States)
	end

	return Tracker
end
