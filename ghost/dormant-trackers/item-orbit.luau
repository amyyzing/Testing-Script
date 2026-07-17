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
	local minimumDuration = tonumber(dependencies.MinimumDuration) or 0.5
	local minimumIntervals = tonumber(dependencies.MinimumIntervals) or 5
	local minimumGoodShare = tonumber(dependencies.MinimumGoodShare) or 0.7
	local minimumAngle = tonumber(dependencies.MinimumAngularTotal) or 45
	local minimumDirectionShare = tonumber(dependencies.MinimumDirectionShare) or 0.65
	local requiredObjects = tonumber(dependencies.RequiredObjects) or 3
	local nearRadiusTolerance = tonumber(dependencies.NearRadiusTolerance) or 0.3
	local nearMinimumRotation = tonumber(dependencies.NearMinimumRotation) or math.rad(45)
	local nearMinimumStep = tonumber(dependencies.NearMinimumAngleStep) or math.rad(0.25)
	local nearActiveWindow = tonumber(dependencies.NearActiveWindow) or 0.5
	local nearMinimumDuration = tonumber(dependencies.NearMinimumDuration) or 0.5
	local Tracker = {
		Kind = "dormant",
		Running = true,
		Active = false,
		Reported = false,
		Accumulator = 0,
		Objects = setmetatable({}, {__mode = "k"}),
		States = setmetatable({}, {__mode = "k"}),
		NearStates = setmetatable({}, {__mode = "k"}),
		Representatives = setmetatable({}, {__mode = "k"}),
		Containers = setmetatable({}, {__mode = "k"}),
		Connections = {},
	}

	local function position(object)
		if object:IsA("BasePart") then return object.Position end
		if object:IsA("Model") then return object:GetPivot().Position end
	end

	local function usablePart(part)
		return part and part:IsA("BasePart") and part.Anchored ~= true
			and (tonumber(part.Transparency) or 0) < 1
	end

	local function resolveObject(object)
		local representative = Tracker.Representatives[object]
		local outsideModel = representative and representative ~= object
			and type(representative.IsDescendantOf) == "function"
			and not representative:IsDescendantOf(object)
		if representative and (representative.Parent == nil
			or not usablePart(representative) or outsideModel) then
			representative = nil
			Tracker.Representatives[object] = nil
		end
		if not representative then
			if usablePart(object) then
				representative = object
			elseif object:IsA("Model") then
				if usablePart(object.PrimaryPart) then
					representative = object.PrimaryPart
				else
					for _, descendant in ipairs(object:GetDescendants()) do
						if usablePart(descendant) then
							representative = descendant
							break
						end
					end
				end
			end
			if representative then Tracker.Representatives[object] = representative end
		end
		if not representative then return nil, nil end
		return representative.Position, representative.AssemblyRootPart or representative
	end

	local function distance(first, second)
		local x = first.X - second.X
		local y = first.Y - second.Y
		local z = first.Z - second.Z
		return math.sqrt(x * x + y * y + z * z)
	end

	local function resetCandidate(state)
		state.Window = {}
		state.CandidateStartedAt = nil
		state.ConsecutiveBad = 0
	end

	local function qualify(state, now)
		if not state.CandidateStartedAt then return nil end
		local good, signed, absolute, fastest = 0, 0, 0, 0
		for _, sample in ipairs(state.Window) do
			if sample.Good then
				good += 1
				signed += sample.SignedAngle
				absolute += sample.AbsAngle
				fastest = math.max(fastest, sample.Speed)
			end
		end
		local duration = now - state.CandidateStartedAt
		local count = #state.Window
		local goodShare = good / math.max(count, 1)
		local directionShare = math.abs(signed) / math.max(absolute, 0.001)
		if duration < minimumDuration or count < minimumIntervals
			or goodShare < minimumGoodShare or absolute < minimumAngle
			or directionShare < minimumDirectionShare then return nil end
		return {
			Direction = signed >= 0 and 1 or -1,
			Duration = duration,
			Intervals = count,
			GoodShare = goodShare,
			AccumulatedAngle = absolute,
			Speed = fastest,
		}
	end

	local function observe(object, current, assembly, ghostPosition, now)
		local relativeX = current.X - ghostPosition.X
		local relativeZ = current.Z - ghostPosition.Z
		local state = Tracker.States[object]
		if not state then
			Tracker.States[object] = {
				Position = current,
				RelativeX = relativeX,
				RelativeZ = relativeZ,
				Time = now,
				Window = {},
				ConsecutiveBad = 0,
			}
			return nil
		end

		local oldPosition = state.Position
		local oldX, oldZ, oldTime = state.RelativeX, state.RelativeZ, state.Time
		state.Position = current
		state.RelativeX = relativeX
		state.RelativeZ = relativeZ
		state.Time = now
		local elapsed = now - oldTime
		local oldRadius = math.sqrt(oldX * oldX + oldZ * oldZ)
		local newRadius = math.sqrt(relativeX * relativeX + relativeZ * relativeZ)
		local stepX, stepZ = relativeX - oldX, relativeZ - oldZ
		local relativeStep = math.sqrt(stepX * stepX + stepZ * stepZ)
		local geometryValid = elapsed >= 0.06 and elapsed <= 0.2
			and oldRadius >= minimumRadius and oldRadius <= maximumRadius
			and newRadius >= minimumRadius and newRadius <= maximumRadius
			and relativeStep <= 12
		local orbitLike, signedAngle, relativeSpeed = false, 0, 0
		if geometryValid then
			local dot = oldX * relativeX + oldZ * relativeZ
			local cross = oldX * relativeZ - oldZ * relativeX
			signedAngle = math.deg(math.atan2(cross, dot))
			local velocityX, velocityZ = stepX / elapsed, stepZ / elapsed
			relativeSpeed = math.sqrt(velocityX * velocityX + velocityZ * velocityZ)
			local worldSpeed = distance(current, oldPosition) / math.max(elapsed, 0.001)
			local radialX = relativeX / math.max(newRadius, 0.001)
			local radialZ = relativeZ / math.max(newRadius, 0.001)
			local radialSpeed = math.abs(velocityX * radialX + velocityZ * radialZ)
			local tangentialSpeed = math.sqrt(math.max(
				relativeSpeed * relativeSpeed - radialSpeed * radialSpeed,
				0
			))
			local tangentialShare = tangentialSpeed / math.max(relativeSpeed, 0.001)
			local radiusChange = math.abs(newRadius - oldRadius)
			local meanRadius = (oldRadius + newRadius) * 0.5
			orbitLike = worldSpeed >= 4 and relativeSpeed >= 6
				and math.abs(signedAngle) / elapsed >= 70
				and tangentialShare >= 0.55
				and radiusChange <= math.max(2, meanRadius * 0.35)
		end

		if not geometryValid then
			resetCandidate(state)
		elseif orbitLike or state.CandidateStartedAt then
			if orbitLike and not state.CandidateStartedAt then
				state.CandidateStartedAt = oldTime
			end
			table.insert(state.Window, {
				StartAt = oldTime,
				Time = now,
				Good = orbitLike,
				SignedAngle = orbitLike and signedAngle or 0,
				AbsAngle = orbitLike and math.abs(signedAngle) or 0,
				Speed = orbitLike and relativeSpeed or 0,
			})
			state.ConsecutiveBad = orbitLike and 0 or state.ConsecutiveBad + 1
			for index = #state.Window, 1, -1 do
				if now - state.Window[index].Time > 0.8 then
					table.remove(state.Window, index)
				end
			end
			if state.ConsecutiveBad > 2 or #state.Window == 0 then
				resetCandidate(state)
			else
				state.CandidateStartedAt = state.Window[1].StartAt
				local result = qualify(state, now)
				if result then result.Assembly = assembly end
				return result
			end
		end
		return nil
	end

	local function observeNear(object, current, assembly, ghostPosition, now)
		local x, z = current.X - ghostPosition.X, current.Z - ghostPosition.Z
		local radius = math.sqrt(x * x + z * z)
		if radius < 1 then
			Tracker.NearStates[object] = nil
			return nil
		end
		local angle = math.atan2(z, x)
		local state = Tracker.NearStates[object]
		if not state then
			Tracker.NearStates[object] = {
				Radius = radius,
				Angle = angle,
				Direction = 0,
				Rotation = 0,
				Steps = 0,
				Assembly = assembly,
			}
			return nil
		end
		if math.abs(radius - state.Radius) > math.max(0.75, state.Radius * nearRadiusTolerance) then
			Tracker.NearStates[object] = nil
			return nil
		end
		local delta = math.atan2(math.sin(angle - state.Angle), math.cos(angle - state.Angle))
		if math.abs(delta) < nearMinimumStep then return nil end
		local direction = delta > 0 and 1 or -1
		if state.Direction ~= 0 and state.Direction ~= direction then
			state.Direction = direction
			state.Rotation = math.abs(delta)
			state.Steps = 1
			state.StartedAt = now
		else
			state.Direction = direction
			state.Rotation += math.abs(delta)
			state.Steps += 1
			state.StartedAt = state.StartedAt or now
		end
		state.Angle = angle
		state.Radius = (state.Radius * 3 + radius) / 4
		state.Assembly = assembly
		state.LastProgress = now
		state.Qualified = state.Steps >= 3
			and state.Rotation + 0.000001 >= nearMinimumRotation
			and now - state.StartedAt >= nearMinimumDuration
	end

	function Tracker:Track(object)
		if object:IsA("Model") or object:IsA("BasePart") then
			self.Objects[object] = true
		end
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
			self.NearStates[object] = nil
			self.Representatives[object] = nil
		end))
	end

	function Tracker:Sample()
		if not self.Active or self.Reported then return end
		local ghostPosition = position(Ghost)
		if not ghostPosition then return end
		local now = clock()
		if self.LastGhostPosition and self.LastGhostSampleAt
			and now - self.LastGhostSampleAt <= 0.2
			and distance(ghostPosition, self.LastGhostPosition) > 8 then
			table.clear(self.States)
			table.clear(self.NearStates)
			self.LastGhostPosition, self.LastGhostSampleAt = ghostPosition, now
			return
		end
		self.LastGhostPosition, self.LastGhostSampleAt = ghostPosition, now

		local legacy = {[1] = {}, [-1] = {}}
		local legacyAssemblies = {[1] = {}, [-1] = {}}
		for object in pairs(self.Objects) do
			local current, assembly = resolveObject(object)
			if not current or not assembly or distance(current, ghostPosition) > scanRadius then
				self.States[object] = nil
				self.NearStates[object] = nil
			else
				local result = observe(object, current, assembly, ghostPosition, now)
				observeNear(object, current, assembly, ghostPosition, now)
				if result and not legacyAssemblies[result.Direction][result.Assembly] then
					result.Object = object
					legacyAssemblies[result.Direction][result.Assembly] = true
					table.insert(legacy[result.Direction], result)
				end
			end
		end

		local near = {[1] = {}, [-1] = {}}
		local nearAssemblies = {[1] = {}, [-1] = {}}
		for object, state in pairs(self.NearStates) do
			if state.Qualified and state.LastProgress
				and now - state.LastProgress <= nearActiveWindow
				and not nearAssemblies[state.Direction][state.Assembly] then
				nearAssemblies[state.Direction][state.Assembly] = true
				table.insert(near[state.Direction], {
					Object = object,
					Direction = state.Direction,
				})
			end
		end
		local matching = #legacy[1] >= requiredObjects and legacy[1]
			or #legacy[-1] >= requiredObjects and legacy[-1]
		local mode = "Legacy"
		if not matching then
			matching = #near[1] >= requiredObjects and near[1]
				or #near[-1] >= requiredObjects and near[-1]
			mode = "NearPerfect"
		end
		if not matching then return end
		local duration, intervals, goodShare, angle
		if mode == "Legacy" then
			duration, intervals, goodShare, angle = math.huge, math.huge, math.huge, math.huge
		end
		local objects = {}
		for _, result in ipairs(matching) do
			if mode == "Legacy" then
				duration = math.min(duration, result.Duration)
				intervals = math.min(intervals, result.Intervals)
				goodShare = math.min(goodShare, result.GoodShare)
				angle = math.min(angle, result.AccumulatedAngle)
			end
			table.insert(objects, result.Object)
		end
		self.Reported = true
		Traffic("ItemOrbit", {
			Objects = objects,
			Count = #objects,
			Duration = duration,
			Intervals = intervals,
			GoodShare = goodShare,
			AccumulatedAngle = angle,
			Direction = matching[1].Direction,
			Mode = mode,
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
		Tracker.LastGhostPosition = nil
		Tracker.LastGhostSampleAt = nil
		table.clear(Tracker.States)
		table.clear(Tracker.NearStates)
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
		for _, name in ipairs({"Items", "Interactable", "Interactables"}) do
			local container = parent:FindFirstChild(name)
			if container then Tracker:BindContainer(container) end
		end
	end
	findContainers(World)
	findContainers(World:FindFirstChild("Map"))
	local added = World.DescendantAdded or World.ChildAdded
	if added then
		table.insert(Tracker.Connections, added:Connect(function(container)
			if container.Name == "Items" or container.Name == "Interactable"
				or container.Name == "Interactables" then
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
		table.clear(self.NearStates)
		table.clear(self.Representatives)
	end

	return Tracker
end
