return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "item-orbit requires Traffic")
	local World = dependencies.Workspace or workspace
	local Ghost = assert(dependencies.Ghost, "item-orbit requires Ghost")
	local RunService = assert(dependencies.RunService, "item-orbit requires RunService")
	local clock = dependencies.Clock or os.clock
	local interval = tonumber(dependencies.SampleInterval) or 0.1
	local scanRadius = tonumber(dependencies.ScanRadius) or 45
	local minimumRadius = tonumber(dependencies.MinimumRadius) or 2.5
	local maximumRadius = tonumber(dependencies.MaximumRadius) or 40
	local radiusTolerance = tonumber(dependencies.RadiusTolerance) or 0.18
	local minimumDuration = tonumber(dependencies.MinimumDuration) or 0.5
	local minimumSteps = tonumber(dependencies.MinimumSteps) or 5
	local minimumRotation = tonumber(dependencies.MinimumRotation) or math.rad(60)
	local minimumAngleStep = tonumber(dependencies.MinimumAngleStep) or math.rad(0.5)
	local maximumAngleStep = tonumber(dependencies.MaximumAngleStep) or math.rad(100)
	local activeWindow = tonumber(dependencies.ActiveWindow) or 0.3
	local requiredObjects = tonumber(dependencies.RequiredObjects) or 3
	local Tracker = {
		Kind = "dormant",
		Running = true,
		Active = false,
		Reported = false,
		Accumulator = 0,
		Objects = setmetatable({}, {__mode = "k"}),
		States = setmetatable({}, {__mode = "k"}),
		Representatives = setmetatable({}, {__mode = "k"}),
		Containers = setmetatable({}, {__mode = "k"}),
		Connections = {},
	}

	local function distance(first, second)
		local x, y, z = first.X - second.X, first.Y - second.Y, first.Z - second.Z
		return math.sqrt(x * x + y * y + z * z)
	end

	local function ghostPosition()
		if Ghost:IsA("BasePart") then return Ghost.Position end
		return Ghost:GetPivot().Position
	end

	local function usablePart(part)
		return part and part:IsA("BasePart") and part.Anchored ~= true
			and (tonumber(part.Transparency) or 0) < 1
	end

	local function resolveObject(object)
		local part = Tracker.Representatives[object]
		if part and (not part.Parent or not usablePart(part)) then part = nil end
		if not part then
			if usablePart(object) then
				part = object
			elseif object:IsA("Model") then
				part = usablePart(object.PrimaryPart) and object.PrimaryPart or nil
				if not part then
					for _, descendant in ipairs(object:GetDescendants()) do
						if usablePart(descendant) then part = descendant break end
					end
				end
			end
			Tracker.Representatives[object] = part
		end
		return part and part.Position or nil, part and (part.AssemblyRootPart or part) or nil
	end

	local function resetState(object, current, assembly, center, now)
		local x, z = current.X - center.X, current.Z - center.Z
		local radius = math.sqrt(x * x + z * z)
		Tracker.States[object] = {
			X = x,
			Z = z,
			Angle = math.atan2(z, x),
			Radius = radius,
			MinRadius = radius,
			MaxRadius = radius,
			Time = now,
			Direction = 0,
			Rotation = 0,
			Steps = 0,
			Assembly = assembly,
		}
	end

	local function observe(object, current, assembly, center, now)
		local state = Tracker.States[object]
		if not state then
			resetState(object, current, assembly, center, now)
			return
		end
		local x, z = current.X - center.X, current.Z - center.Z
		local radius = math.sqrt(x * x + z * z)
		local angle = math.atan2(z, x)
		local elapsed = now - state.Time
		local delta = math.atan2(math.sin(angle - state.Angle), math.cos(angle - state.Angle))
		local direction = delta >= 0 and 1 or -1
		local minimum = math.min(state.MinRadius, radius)
		local maximum = math.max(state.MaxRadius, radius)
		local meanRadius = (minimum + maximum) * 0.5
		local variation = (maximum - minimum) / math.max(meanRadius, 0.001)
		local invalid = elapsed <= 0 or elapsed > interval * 2.5
			or radius < minimumRadius or radius > maximumRadius
			or variation > radiusTolerance
			or math.abs(delta) > maximumAngleStep
			or state.Direction ~= 0 and math.abs(delta) >= minimumAngleStep
				and direction ~= state.Direction
		if invalid then
			resetState(object, current, assembly, center, now)
			return
		end
		state.X, state.Z, state.Angle, state.Radius = x, z, angle, radius
		state.MinRadius, state.MaxRadius, state.Time = minimum, maximum, now
		state.Assembly = assembly
		if math.abs(delta) < minimumAngleStep then return end
		state.Direction = direction
		state.Rotation += math.abs(delta)
		state.Steps += 1
		state.StartedAt = state.StartedAt or now - elapsed
		state.LastProgress = now
		state.Duration = now - state.StartedAt
		state.RadiusVariation = variation
		state.Qualified = state.Duration >= minimumDuration
			and state.Steps >= minimumSteps
			and state.Rotation >= minimumRotation
	end

	function Tracker:Track(object)
		if object:IsA("Model") or object:IsA("BasePart") then self.Objects[object] = true end
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
			self.Representatives[object] = nil
		end))
	end

	function Tracker:Sample()
		if not self.Active or self.Reported then return end
		local center = ghostPosition()
		local now = clock()
		if self.LastCenter and self.LastSampleAt and now - self.LastSampleAt <= interval * 2
			and distance(center, self.LastCenter) > 8 then
			table.clear(self.States)
		end
		self.LastCenter, self.LastSampleAt = center, now
		for object in pairs(self.Objects) do
			local current, assembly = resolveObject(object)
			if not current or not assembly or distance(current, center) > scanRadius then
				self.States[object] = nil
			else
				observe(object, current, assembly, center, now)
			end
		end

		local matches = {[1] = {}, [-1] = {}}
		local assemblies = {[1] = {}, [-1] = {}}
		for object, state in pairs(self.States) do
			if state.Qualified and state.LastProgress
				and now - state.LastProgress <= activeWindow
				and not assemblies[state.Direction][state.Assembly] then
				assemblies[state.Direction][state.Assembly] = true
				table.insert(matches[state.Direction], {Object = object, State = state})
			end
		end
		local matching = #matches[1] >= requiredObjects and matches[1]
			or #matches[-1] >= requiredObjects and matches[-1]
		if not matching then return end
		local objects = {}
		local duration, steps, rotation = math.huge, math.huge, math.huge
		local maximumVariation = 0
		for _, result in ipairs(matching) do
			table.insert(objects, result.Object)
			duration = math.min(duration, result.State.Duration)
			steps = math.min(steps, result.State.Steps)
			rotation = math.min(rotation, result.State.Rotation)
			maximumVariation = math.max(maximumVariation, result.State.RadiusVariation)
		end
		self.Reported = true
		Traffic("ItemOrbit", {
			Objects = objects,
			Count = #objects,
			Duration = duration,
			Steps = steps,
			Rotation = rotation,
			MaximumRadiusVariation = maximumVariation,
			Direction = matching[1].State.Direction,
			Mode = "NearPerfect",
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
		Tracker.LastCenter, Tracker.LastSampleAt = nil, nil
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

	local function findContainers(parent)
		if not parent then return end
		for _, name in ipairs({"Items", "Interactables"}) do
			local container = parent:FindFirstChild(name)
			if container then Tracker:BindContainer(container) end
		end
	end
	findContainers(World)
	findContainers(World:FindFirstChild("Map"))
	local added = World.DescendantAdded or World.ChildAdded
	if added then
		table.insert(Tracker.Connections, added:Connect(function(container)
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
		table.clear(self.Representatives)
	end

	return Tracker
end
