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
		local ok, first, second = xpcall(callback, debug.traceback)
		lease:Release()
		if not ok then
			restoreSnapshot(snapshot)
			return false, tostring(first):match("^[^\n]+")
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
			local insideCount = 0
			local distance = math.huge
			for _, boundingPart in ipairs(getRoomBoundingParts(room)) do
				for _, position in ipairs(preferredPositions or {}) do
					if pointIsInsidePart(boundingPart, position) then
						insideCount = insideCount + 1
					end
				end
				for _, position in ipairs(distancePositions) do
					local localPosition = boundingPart.CFrame:PointToObjectSpace(position)
					local half = boundingPart.Size * 0.5
					local dx = math.max(math.abs(localPosition.X) - half.X, 0)
					local dz = math.max(math.abs(localPosition.Z) - half.Z, 0)
					distance = math.min(distance, math.sqrt(dx ^ 2 + dz ^ 2))
				end
			end
			if insideCount > bestInsideCount
				or (insideCount == bestInsideCount and distance < bestDistance) then
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
