return function(dependencies)
	dependencies = dependencies or {}
	local Services = assert(
		dependencies.Services,
		"logic/teleportation.luau requires Services"
	)
	local player = assert(
		dependencies.Player,
		"logic/teleportation.luau requires Player"
	)
	local runtimeIsActive = assert(
		dependencies.RuntimeIsActive,
		"logic/teleportation.luau requires RuntimeIsActive"
	)
	local findRoomsFolder = assert(
		dependencies.FindRoomsFolder,
		"logic/teleportation.luau requires FindRoomsFolder"
	)
	local getInstanceWorldPosition = assert(
		dependencies.GetInstanceWorldPosition,
		"logic/teleportation.luau requires GetInstanceWorldPosition"
	)
	local getRoomBoundingParts = assert(
		dependencies.GetRoomBoundingParts,
		"logic/teleportation.luau requires GetRoomBoundingParts"
	)
	local pointIsInsidePart = assert(
		dependencies.PointIsInsidePart,
		"logic/teleportation.luau requires PointIsInsidePart"
	)

	local busy = false

	local function optionsAreActive(options)
		if not runtimeIsActive() then
			return false
		end
		if type(options.IsActive) ~= "function" then
			return true
		end
		local ok, active = pcall(options.IsActive)
		return ok and active == true
	end

	local function restoreSnapshot(snapshot)
		if not snapshot then
			return
		end
		local character = snapshot.Character
		local root = snapshot.Root
		local humanoid = snapshot.Humanoid
		if player.Character ~= character or not character.Parent then
			return
		end
		pcall(function()
			if root.Parent then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				root.Anchored = snapshot.Anchored
			end
			if humanoid.Parent then
				humanoid.PlatformStand = snapshot.PlatformStand
				humanoid.AutoRotate = snapshot.AutoRotate
				for state, enabled in pairs(snapshot.StateEnabled or {}) do
					humanoid:SetStateEnabled(state, enabled)
				end
			end
		end)
	end

	local function acquire(options)
		options = options or {}
		while busy do
			if not optionsAreActive(options) then
				return nil, "movement request was cancelled"
			end
			Services.RunService.Heartbeat:Wait()
		end
		if not optionsAreActive(options) then
			return nil, "movement request was cancelled"
		end
		busy = true
		local lease = {Released = false}
		function lease:IsActive()
			return not self.Released and optionsAreActive(options)
		end
		function lease:Release()
			if self.Released then
				return
			end
			self.Released = true
			busy = false
		end
		return lease
	end

	local function runExclusive(options, callback)
		options = options or {}
		local lease, acquireReason = acquire(options)
		if not lease then
			return false, acquireReason
		end
		local character = player.Character
		local root = character
			and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character
			and character:FindFirstChildOfClass("Humanoid")
		local stateEnabled = {}
		if humanoid then
			for _, state in ipairs({
				Enum.HumanoidStateType.FallingDown,
				Enum.HumanoidStateType.Ragdoll,
				Enum.HumanoidStateType.Freefall,
			}) do
				local ok, enabled = pcall(humanoid.GetStateEnabled, humanoid, state)
				if ok then
					stateEnabled[state] = enabled
				end
			end
		end
		local snapshot = character and root and humanoid and {
			Character = character,
			Root = root,
			Humanoid = humanoid,
			Anchored = root.Anchored,
			PlatformStand = humanoid.PlatformStand,
			AutoRotate = humanoid.AutoRotate,
			StateEnabled = stateEnabled,
		} or nil
		local callerIsActive = options.IsActive
		local function combinedIsActive()
			if not runtimeIsActive() then
				return false
			end
			if type(callerIsActive) ~= "function" then
				return true
			end
			local ok, active = pcall(callerIsActive)
			return ok and active == true
		end
		local guardInstalled = pcall(function()
			options.IsActive = combinedIsActive
		end)
		if not guardInstalled then
			lease:Release()
			return false, "movement request could not install its activity guard"
		end
		local ok, first, second = xpcall(callback, debug.traceback)
		local activeAfterCallback = combinedIsActive()
		local guardRestored = pcall(function()
			if options.IsActive == combinedIsActive then
				options.IsActive = callerIsActive
			end
		end)
		lease:Release()
		if not ok then
			restoreSnapshot(snapshot)
			return false, tostring(first):match("^[^\n]+")
		end
		if not guardRestored then
			restoreSnapshot(snapshot)
			return false, "movement request could not restore its activity guard"
		end
		if not activeAfterCallback then
			restoreSnapshot(snapshot)
			return false, "movement request was cancelled"
		end
		return first, second
	end

	local function targetCFrame(target)
		if not target then
			return nil, nil
		end
		if target:IsA("BasePart") then
			return target.CFrame, target.Size
		end
		if target:IsA("Model") then
			local ok, frame, size = pcall(target.GetBoundingBox, target)
			if ok then
				return frame, size
			end
		end
		local position = getInstanceWorldPosition(target)
		return position and CFrame.new(position) or nil, nil
	end

	local function approachPositions(target, distance)
		local frame, size = targetCFrame(target)
		if not frame then
			return {}, nil
		end
		local horizontalSize = size and math.max(size.X, size.Z) or 2
		local offset = distance
			or math.clamp(horizontalSize * 0.5 + 3.25, 4.25, 6.5)
		local center = frame.Position
		local right = Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z)
		local look = Vector3.new(frame.LookVector.X, 0, frame.LookVector.Z)
		right = right.Magnitude >= 0.05 and right.Unit or Vector3.new(1, 0, 0)
		look = look.Magnitude >= 0.05 and look.Unit or Vector3.new(0, 0, -1)
		return {
			center + look * offset,
			center - look * offset,
			center + right * offset,
			center - right * offset,
		}, center
	end

	local function finiteNumber(value)
		return type(value) == "number"
			and value == value
			and value > -math.huge
			and value < math.huge
	end

	local function validBoundingPartGeometry(boundingPart)
		if not boundingPart then
			return nil, nil
		end
		local ok, parent, frame, size, sizeX, sizeY, sizeZ = pcall(function()
			local partSize = boundingPart.Size
			return boundingPart.Parent,
				boundingPart.CFrame,
				partSize,
				partSize.X,
				partSize.Y,
				partSize.Z
		end)
		if not ok
			or not parent
			or not frame
			or not size
			or not finiteNumber(sizeX)
			or not finiteNumber(sizeY)
			or not finiteNumber(sizeZ)
			or sizeX <= 0
			or sizeY <= 0
			or sizeZ <= 0 then
			return nil, nil
		end
		return frame, size
	end

	local function horizontalDistanceToPart(
		frame: any,
		size: any,
		position: any
	): number?
		local ok, localPosition = pcall(function()
			return frame:PointToObjectSpace(position)
		end)
		if not ok or not localPosition then
			return nil
		end
		local dx = math.max(math.abs(localPosition.X) - size.X * 0.5, 0)
		local dz = math.max(math.abs(localPosition.Z) - size.Z * 0.5, 0)
		local distance = math.sqrt(dx ^ 2 + dz ^ 2)
		return finiteNumber(distance) and distance or nil
	end

	local function findRoomForTarget(target, preferredPositions)
		local rooms = findRoomsFolder()
		if not rooms then
			return nil
		end
		local targetPosition = getInstanceWorldPosition(target)
		local distancePositions = preferredPositions
		if not distancePositions or #distancePositions == 0 then
			distancePositions = targetPosition and {targetPosition} or {}
		end
		local bestRoom
		local bestInsideCount = -1
		local bestDistance = math.huge
		for _, room in ipairs(rooms:GetChildren()) do
			local boundingParts = {}
			for _, boundingPart in ipairs(getRoomBoundingParts(room) or {}) do
				local frame, size = validBoundingPartGeometry(boundingPart)
				if frame then
					table.insert(boundingParts, {
						Part = boundingPart,
						Frame = frame,
						Size = size,
					})
				end
			end
			local insideCount = 0
			local distance = math.huge
			for _, position in ipairs(preferredPositions or {}) do
				for _, bounding in ipairs(boundingParts) do
					local ok, inside = pcall(
						pointIsInsidePart,
						bounding.Part,
						position
					)
					if ok and inside then
						insideCount = insideCount + 1
						break
					end
				end
			end
			for _, bounding in ipairs(boundingParts) do
				for _, position in ipairs(distancePositions) do
					local candidateDistance = horizontalDistanceToPart(
						bounding.Frame,
						bounding.Size,
						position
					)
					if candidateDistance ~= nil then
						distance = math.min(distance, candidateDistance)
					end
				end
			end
			if #boundingParts > 0
				and finiteNumber(distance)
				and (insideCount > bestInsideCount
					or (insideCount == bestInsideCount and distance < bestDistance)) then
				bestRoom = room
				bestInsideCount = insideCount
				bestDistance = distance
			end
		end
		return bestRoom
	end

	return {
		Acquire = acquire,
		RunExclusive = runExclusive,
		ApproachPositions = approachPositions,
		FindRoomForTarget = findRoomForTarget,
	}
end
