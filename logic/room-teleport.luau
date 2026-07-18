return function(dependencies)
	local Services = assert(dependencies.Services, "room-teleport requires Services")
	local player = assert(dependencies.Player, "room-teleport requires Player")
	local runtimeIsActive = assert(dependencies.RuntimeIsActive, "room-teleport requires RuntimeIsActive")
	local getRoomBoundingParts = assert(dependencies.GetRoomBoundingParts, "room-teleport requires GetRoomBoundingParts")
	local getGhostModel = assert(dependencies.GetGhostModel, "room-teleport requires GetGhostModel")
	local closed = false
	local ghostProxyModel = nil
	local perkTrackerState = {teleportSequence = 0}

perkTrackerState.teleportToRoomBoundingBoxCenter = function(room, options)
	options = options or {}
	local teleportSequence
	local function teleportOwnsCharacter()
		return teleportSequence == nil
			or perkTrackerState.teleportSequence == teleportSequence
	end
	local function teleportIsActive()
		if not teleportOwnsCharacter() then
			return false
		end
		if type(options.IsActive) ~= "function" then
			return true
		end
		local ok, active = pcall(options.IsActive)
		return ok and active == true
	end
	local character = player.Character
	local root =
		character and character:FindFirstChild("HumanoidRootPart")
	local humanoid =
		character and character:FindFirstChildOfClass("Humanoid")

	if not room or not character or not root or not humanoid
		or not teleportIsActive() then
		return false, "room or character unavailable"
	end

	local boundingParts = getRoomBoundingParts(room)
	for _ = 1, 24 do
		if #boundingParts > 0 then
			break
		end
		task.wait(0.05)
		boundingParts = getRoomBoundingParts(room)
	end

	if #boundingParts == 0 then
		return false, "no BoundingBox BasePart was found"
	end

	local boundingPartSet = setmetatable({}, {__mode = "k"})
	local excludedInstances = {character}

	for _, boundingPart in ipairs(boundingParts) do
		boundingPartSet[boundingPart] = true
		table.insert(excludedInstances, boundingPart)
	end

	local ghost = getGhostModel()
	if ghost then
		table.insert(excludedInstances, ghost)
	end
	if ghostProxyModel then
		table.insert(excludedInstances, ghostProxyModel)
	end

	local standingOffset =
		humanoid.HipHeight + root.Size.Y * 0.5 + 0.12
	local footprintHalfX = root.Size.X * 0.5 + 0.22
	local footprintHalfZ = root.Size.Z * 0.5 + 0.22
	local avatarRadius =
		math.max(footprintHalfX, footprintHalfZ) + 0.18
	local horizontalInset =
		math.sqrt(footprintHalfX ^ 2 + footprintHalfZ ^ 2) + 0.18
	local bodyHeight = math.max(
		root.Size.Y + humanoid.HipHeight + 2.35,
		5.1
	)
	local bodyProbeSize = Vector3.new(
		math.max(root.Size.X + 0.72, 2.3),
		bodyHeight,
		math.max(root.Size.Z + 0.72, 2.3)
	)
	local bodyGeometryProbe = nil
	local preferredPositions = options.PreferredPositions or {}
	local targetPosition = options.TargetPosition
	local maximumTargetDistance = tonumber(options.MaximumTargetDistance)
	local maximumPreferredDistance = tonumber(options.MaximumPreferredDistance)
	local candidateValidator = options.CandidateValidator
	local function candidatePassesCustomValidation(position)
		if type(candidateValidator) ~= "function" then
			return true
		end
		local ok, allowed = pcall(candidateValidator, position)
		return ok and allowed == true
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = excludedInstances
	overlapParams.MaxParts = 0
	pcall(function()
		overlapParams.RespectCanCollide = true
	end)

	local function safelyInsideXZ(position, boundingPart)
		local localPosition =
			boundingPart.CFrame:PointToObjectSpace(position)
		local half = boundingPart.Size * 0.5

		return math.abs(localPosition.X)
			<= math.max(0, half.X - horizontalInset)
			and math.abs(localPosition.Z)
				<= math.max(0, half.Z - horizontalInset)
	end

	local function isCollidableInstance(instance)
		if instance == workspace.Terrain then
			return true
		end
		return instance
			and instance:IsA("BasePart")
			and instance.CanCollide
	end

	local function newRaycastParams(excludes)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = excludes
		raycastParams.IgnoreWater = true
		pcall(function()
			raycastParams.RespectCanCollide = true
		end)
		return raycastParams
	end

	local function raycastFirstCollidable(
		origin,
		direction,
		additionalExcludes
	)
		local excludes = table.clone(excludedInstances)
		for _, instance in ipairs(additionalExcludes or {}) do
			if instance and instance ~= workspace.Terrain then
				table.insert(excludes, instance)
			end
		end
		local raycastParams = newRaycastParams(excludes)
		local seen = setmetatable({}, {__mode = "k"})

		for _ = 1, 12 do
			raycastParams.FilterDescendantsInstances = excludes
			local result = workspace:Raycast(
				origin,
				direction,
				raycastParams
			)
			if not result then
				return nil
			end
			if isCollidableInstance(result.Instance) then
				return result
			end
			if not result.Instance
				or result.Instance == workspace.Terrain
				or seen[result.Instance] then
				return nil
			end
			seen[result.Instance] = true
			table.insert(excludes, result.Instance)
		end

		return nil
	end

	local footprintOffsets = {
		Vector3.zero,
		Vector3.new(footprintHalfX, 0, 0),
		Vector3.new(-footprintHalfX, 0, 0),
		Vector3.new(0, 0, footprintHalfZ),
		Vector3.new(0, 0, -footprintHalfZ),
		Vector3.new(footprintHalfX, 0, footprintHalfZ),
		Vector3.new(footprintHalfX, 0, -footprintHalfZ),
		Vector3.new(-footprintHalfX, 0, footprintHalfZ),
		Vector3.new(-footprintHalfX, 0, -footprintHalfZ),
	}

	local function inspectFootprint(floorPosition)
		local supportHits = 0
		local flatSupportHits = 0
		local centerSupported = false
		local supportSet = setmetatable({}, {__mode = "k"})

		for index, offset in ipairs(footprintOffsets) do
			local result = raycastFirstCollidable(
				floorPosition + offset + Vector3.new(0, 1.35, 0),
				Vector3.new(0, -2.85, 0)
			)
			if result and result.Normal.Y >= 0.5 then
				local heightDifference = math.abs(
					result.Position.Y - floorPosition.Y
				)
				if heightDifference <= 0.9 then
					supportHits = supportHits + 1
					if index == 1 then
						centerSupported = true
					end
				end
				if heightDifference <= 0.38 then
					supportSet[result.Instance] = true
					if result.Normal.Y >= 0.62 then
						flatSupportHits = flatSupportHits + 1
					end
				end
			end
		end

		return {
			CenterSupported = centerSupported,
			SupportHits = supportHits,
			FlatSupportHits = flatSupportHits,
			SupportSet = supportSet,
		}
	end

	local function worldHalfExtents(part)
		local half = part.Size * 0.5
		local frame = part.CFrame
		return Vector3.new(
			math.abs(frame.XVector.X) * half.X
				+ math.abs(frame.YVector.X) * half.Y
				+ math.abs(frame.ZVector.X) * half.Z,
			math.abs(frame.XVector.Y) * half.X
				+ math.abs(frame.YVector.Y) * half.Y
				+ math.abs(frame.ZVector.Y) * half.Z,
			math.abs(frame.XVector.Z) * half.X
				+ math.abs(frame.YVector.Z) * half.Y
				+ math.abs(frame.ZVector.Z) * half.Z
		)
	end

	local function inspectBodyArea(candidate, floorY, supportSet)
		local probeBottom = floorY + 0.12
		local probeTop = probeBottom + bodyProbeSize.Y
		local probe = CFrame.new(
			candidate.X,
			probeBottom + bodyProbeSize.Y * 0.5,
			candidate.Z
		)
		local blockerCount = 0
		local coreBlockers = 0
		local penalty = 0
		local intersectingParts = nil
		if bodyGeometryProbe and bodyGeometryProbe.Parent then
			bodyGeometryProbe.CFrame = probe
			bodyGeometryProbe.Size = bodyProbeSize
			local exactOk, exactParts = pcall(function()
				return workspace:GetPartsInPart(
					bodyGeometryProbe,
					overlapParams
				)
			end)
			bodyGeometryProbe.CFrame = CFrame.new(0, -100000, 0)
			if exactOk then
				intersectingParts = exactParts
			end
		end
		if not intersectingParts then
			intersectingParts = workspace:GetPartBoundsInBox(
				probe,
				bodyProbeSize,
				overlapParams
			)
		end

		for _, part in ipairs(intersectingParts) do
			if part:IsA("BasePart")
				and part.CanCollide
				and part ~= bodyGeometryProbe
				and not boundingPartSet[part] then
				local halfExtents = worldHalfExtents(part)
				local partBottom = part.Position.Y - halfExtents.Y
				local partTop = part.Position.Y + halfExtents.Y
				local supportOnly = supportSet[part]
					and partTop <= floorY + 0.45
				local belowFeet = partTop <= floorY + 0.24

				if not supportOnly and not belowFeet then
					blockerCount = blockerCount + 1
					local distanceX = math.max(
						math.abs(part.Position.X - candidate.X)
							- halfExtents.X,
						0
					)
					local distanceZ = math.max(
						math.abs(part.Position.Z - candidate.Z)
							- halfExtents.Z,
						0
					)
					local horizontalDistance = math.sqrt(
						distanceX ^ 2 + distanceZ ^ 2
					)
					local verticalOverlap = math.max(
						0,
						math.min(partTop, probeTop)
							- math.max(partBottom, probeBottom)
					)
					local core = horizontalDistance
						<= avatarRadius * 0.55
					if core then
						coreBlockers = coreBlockers + 1
					end
					penalty = penalty
						+ 900
						+ verticalOverlap * 420
						+ (core and 4200 or 0)
						+ (partBottom < floorY + 1.25 and 650 or 0)
				end
			end
		end

		return {
			BlockerCount = blockerCount,
			CoreBlockers = coreBlockers,
			Penalty = penalty,
		}
	end

	local clearanceDirections = {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
		Vector3.new(1, 0, 1).Unit,
		Vector3.new(1, 0, -1).Unit,
		Vector3.new(-1, 0, 1).Unit,
		Vector3.new(-1, 0, -1).Unit,
	}

	local function horizontalClearance(candidate, floorY, supportSet)
		local supportExcludes = {}
		for instance in pairs(supportSet) do
			if instance ~= workspace.Terrain then
				table.insert(supportExcludes, instance)
			end
		end

		local minimum = 9
		for _, height in ipairs({0.75, 2.65}) do
			local origin = Vector3.new(
				candidate.X,
				floorY + height,
				candidate.Z
			)
			for _, direction in ipairs(clearanceDirections) do
				local result = raycastFirstCollidable(
					origin,
					direction * 9,
					supportExcludes
				)
				if result then
					minimum = math.min(minimum, result.Distance)
				end
			end
		end

		return minimum
	end

	local function calculateRisk(
		bodyInspection,
		footprintInspection,
		clearance
	)
		return bodyInspection.Penalty
			+ bodyInspection.CoreBlockers * 10000
			+ bodyInspection.BlockerCount * 500
			+ (#footprintOffsets
				- footprintInspection.FlatSupportHits) * 180
			+ (#footprintOffsets
				- footprintInspection.SupportHits) * 70
			+ math.max(0, 2.1 - clearance) * 120
	end

	local function assessCandidate(candidate)
		candidate.Position = candidate.FloorPosition
			+ Vector3.new(0, standingOffset, 0)
		if targetPosition and maximumTargetDistance then
			local targetOffset = Vector3.new(
				candidate.Position.X - targetPosition.X,
				0,
				candidate.Position.Z - targetPosition.Z
			)
			if targetOffset.Magnitude > maximumTargetDistance then
				return false
			end
		end
		candidate.PreferredDistance = candidate.CenterDistance
		if #preferredPositions > 0 then
			candidate.PreferredDistance = math.huge
			for _, preferred in ipairs(preferredPositions) do
				local offset = Vector3.new(
					candidate.Position.X - preferred.X,
					0,
					candidate.Position.Z - preferred.Z
				)
				candidate.PreferredDistance = math.min(
					tonumber(candidate.PreferredDistance) or math.huge,
					offset.Magnitude
				)
			end
		end
		if maximumPreferredDistance
			and candidate.PreferredDistance > maximumPreferredDistance then
			return false
		end
		if not candidatePassesCustomValidation(candidate.Position) then
			return false
		end
		if not safelyInsideXZ(
			candidate.Position,
			candidate.BoundingPart
		) then
			return false
		end

		local footprintInspection = inspectFootprint(
			candidate.FloorPosition
		)
		if not footprintInspection.CenterSupported then
			return false
		end

		local bodyInspection = inspectBodyArea(
			candidate.Position,
			candidate.FloorPosition.Y,
			footprintInspection.SupportSet
		)
		local clearance = horizontalClearance(
			candidate.Position,
			candidate.FloorPosition.Y,
			footprintInspection.SupportSet
		)

		candidate.SupportHits = footprintInspection.SupportHits
		candidate.FlatSupportHits =
			footprintInspection.FlatSupportHits
		candidate.SupportSet = footprintInspection.SupportSet
		candidate.BlockerCount = bodyInspection.BlockerCount
		candidate.CoreBlockers = bodyInspection.CoreBlockers
		candidate.BlockerPenalty = bodyInspection.Penalty
		candidate.Clearance = clearance
		candidate.StrictSafe = candidate.NormalY >= 0.62
			and candidate.FlatSupportHits == #footprintOffsets
			and candidate.BlockerCount == 0
		candidate.Risk = calculateRisk(
			bodyInspection,
			footprintInspection,
			clearance
		)
		return true
	end

	local rawCandidates = {}
	local minimumBottomByBoundingPart = setmetatable({}, {__mode = "k"})
	local function addColumnCandidates(
		boundingPart,
		localX,
		localZ,
		rippleOrder
	)
		local half = boundingPart.Size * 0.5
		local origin = boundingPart.CFrame:PointToWorldSpace(
			Vector3.new(localX, half.Y + 24, localZ)
		)
		local direction = Vector3.new(
			0,
			-(boundingPart.Size.Y + 72),
			0
		)
		local columnExcludes = table.clone(excludedInstances)
		local raycastParams = newRaycastParams(columnExcludes)
		local pierced = setmetatable({}, {__mode = "k"})

		for _ = 1, 8 do
			raycastParams.FilterDescendantsInstances = columnExcludes
			local result = workspace:Raycast(
				origin,
				direction,
				raycastParams
			)
			if not result then
				break
			end

			local instance = result.Instance
			if isCollidableInstance(instance)
				and result.Normal.Y >= 0.5 then
				local localFloor =
					boundingPart.CFrame:PointToObjectSpace(
						result.Position
					)
				local bottomDistance = localFloor.Y + half.Y
				if bottomDistance >= -1.5
					and bottomDistance
						<= boundingPart.Size.Y + 1.5 then
					local candidate = {
						FloorPosition = result.Position,
						Surface = instance,
						BoundingPart = boundingPart,
						BottomDistance = bottomDistance,
						NormalY = result.Normal.Y,
						CenterDistance = math.sqrt(
							localX ^ 2 + localZ ^ 2
						),
						RippleOrder = rippleOrder or 0,
						SampleOrder = #rawCandidates + 1,
					}
					candidate.SearchDistance = candidate.CenterDistance
					if #preferredPositions > 0 then
						candidate.SearchDistance = math.huge
						for _, preferred in ipairs(preferredPositions) do
							local offset = Vector3.new(
								result.Position.X - preferred.X,
								0,
								result.Position.Z - preferred.Z
							)
							candidate.SearchDistance = math.min(
								candidate.SearchDistance,
								offset.Magnitude
							)
						end
					end
					table.insert(rawCandidates, candidate)
					minimumBottomByBoundingPart[boundingPart] = math.min(
						minimumBottomByBoundingPart[boundingPart]
							or math.huge,
						bottomDistance
					)
				end
			end

			if not instance
				or instance == workspace.Terrain
				or pierced[instance] then
				break
			end
			pierced[instance] = true
			table.insert(columnExcludes, instance)
		end
	end

	-- Build the original adaptive coverage, but inspect it like a ripple:
	-- exact center first, then each progressively farther center ring.
	for _, boundingPart in ipairs(boundingParts) do
		local usableX =
			math.max(0, boundingPart.Size.X - horizontalInset * 2)
		local usableZ =
			math.max(0, boundingPart.Size.Z - horizontalInset * 2)

		if usableX > 0 and usableZ > 0 then
			local spacing = math.max(avatarRadius * 1.65, 2)
			local xCount = math.clamp(
				math.ceil(usableX / spacing) + 1,
				6,
				12
			)
			local zCount = math.clamp(
				math.ceil(usableZ / spacing) + 1,
				3,
				10
			)
			local samplePoints = {}
			local sampledColumns = {}
			local function queueSample(localX, localZ)
				local key = string.format("%.3f:%.3f", localX, localZ)
				if sampledColumns[key] then
					return
				end
				sampledColumns[key] = true
				table.insert(samplePoints, {
					X = localX,
					Z = localZ,
					Radius = math.sqrt(localX ^ 2 + localZ ^ 2),
					BuildOrder = #samplePoints + 1,
				})
			end

			queueSample(0, 0)
			for _, preferred in ipairs(preferredPositions) do
				local localPreferred =
					boundingPart.CFrame:PointToObjectSpace(preferred)
				if math.abs(localPreferred.X) <= usableX * 0.5 + 0.05
					and math.abs(localPreferred.Z) <= usableZ * 0.5 + 0.05 then
					queueSample(localPreferred.X, localPreferred.Z)
				end
			end
			for xIndex = 1, xCount do
				local xRatio = (xIndex - 0.5) / xCount - 0.5
				local localX = xRatio * usableX

				for zIndex = 1, zCount do
					local zRatio = (zIndex - 0.5) / zCount - 0.5
					local localZ = zRatio * usableZ
					queueSample(localX, localZ)
				end
			end
			table.sort(samplePoints, function(left, right)
				if math.abs(left.Radius - right.Radius) > 0.01 then
					return left.Radius < right.Radius
				end
				return left.BuildOrder < right.BuildOrder
			end)
			for rippleOrder, point in ipairs(samplePoints) do
				addColumnCandidates(
					boundingPart,
					point.X,
					point.Z,
					rippleOrder
				)
				if rippleOrder % 12 == 0 then
					Services.RunService.Heartbeat:Wait()
				end
			end
		end
	end

	if #rawCandidates == 0 then
		return false,
			"no grounded floor point was found inside the room"
	end

	bodyGeometryProbe = Instance.new("Part")
	bodyGeometryProbe.Name = "__DemonologyTeleportProbe"
	bodyGeometryProbe.Anchored = true
	bodyGeometryProbe.CanCollide = false
	bodyGeometryProbe.CanTouch = false
	bodyGeometryProbe.CanQuery = true
	bodyGeometryProbe.CastShadow = false
	bodyGeometryProbe.Transparency = 1
	bodyGeometryProbe.Size = bodyProbeSize
	bodyGeometryProbe.CFrame = CFrame.new(0, -100000, 0)
	bodyGeometryProbe.Parent = workspace
	table.insert(excludedInstances, bodyGeometryProbe)
	overlapParams.FilterDescendantsInstances = excludedInstances
	local function destroyBodyGeometryProbe()
		if bodyGeometryProbe then
			bodyGeometryProbe:Destroy()
			bodyGeometryProbe = nil
		end
	end

	local function surfaceLooksLikeGround(surface)
		if surface == workspace.Terrain then
			return true
		end
		if not surface
			or not surface:IsA("BasePart")
			or surface.Transparency >= 0.95 then
			return false
		end

		local name = string.lower(surface.Name)
		for _, token in ipairs({
			"boundingbox",
			"hitbox",
			"trigger",
			"region",
			"volume",
			"detector",
			"boundary",
			"roomzone",
		}) do
			if string.find(name, token, 1, true) then
				return false
			end
		end

		return true
	end

	local candidatePools = {{}, {}, {}, {}}
	for _, candidate in ipairs(rawCandidates) do
		local minimumBottom =
			minimumBottomByBoundingPart[candidate.BoundingPart]
				or candidate.BottomDistance
		local inGroundBand = candidate.BottomDistance
			<= minimumBottom + 1
		local looksLikeGround = surfaceLooksLikeGround(
			candidate.Surface
		)
		if inGroundBand then
			candidate.GroundTier = looksLikeGround and 0 or 1
		else
			candidate.GroundTier = looksLikeGround and 2 or 3
		end
		table.insert(candidatePools[candidate.GroundTier + 1], candidate)
	end

	local candidates = {}
	local evaluated = setmetatable({}, {__mode = "k"})
	local evaluationCount = 0
	local function evaluateCandidate(candidate)
		if not candidate or evaluated[candidate] then
			return
		end
		evaluated[candidate] = true
		evaluationCount = evaluationCount + 1
		if assessCandidate(candidate) then
			table.insert(candidates, candidate)
		end
		if evaluationCount % 6 == 0 then
			Services.RunService.Heartbeat:Wait()
		end
	end
	local strictCandidateCount = 0
	local function evaluatePool(pool)
		if #pool == 0 then
			return false
		end
		table.sort(pool, function(left, right)
			if math.abs(left.SearchDistance - right.SearchDistance) > 0.01 then
				return left.SearchDistance < right.SearchDistance
			end
			if left.RippleOrder ~= right.RippleOrder then
				return left.RippleOrder < right.RippleOrder
			end
			return left.SampleOrder < right.SampleOrder
		end)
		local completionRadius
		for index, candidate in ipairs(pool) do
			evaluateCandidate(candidate)
			if candidate.StrictSafe and candidate.CoreBlockers == 0 then
				strictCandidateCount = strictCandidateCount + 1
				if strictCandidateCount >= 3 and not completionRadius then
					completionRadius = candidate.SearchDistance
				end
			end
			if completionRadius
				and index < #pool
				and pool[index + 1].SearchDistance > completionRadius + 0.05 then
				return true
			end
		end
		return strictCandidateCount > 0
	end

	-- Expand from the center (or requested target) until several strict retry
	-- points are available. If no strict point exists, exhaust the ripple so
	-- the risk fallback truly is the safest assessed option.
	for _, pool in ipairs(candidatePools) do
		evaluatePool(pool)
		if strictCandidateCount >= 3 then
			break
		end
	end

	if #candidates == 0 then
		destroyBodyGeometryProbe()
		return false,
			"no grounded destination passed the detailed room checks"
	end

	table.sort(candidates, function(left, right)
		local leftCoreFree = left.CoreBlockers == 0
		local rightCoreFree = right.CoreBlockers == 0
		if leftCoreFree ~= rightCoreFree then
			return leftCoreFree
		end
		if left.GroundTier ~= right.GroundTier then
			return left.GroundTier < right.GroundTier
		end
		if left.StrictSafe ~= right.StrictSafe then
			return left.StrictSafe
		end
		if left.StrictSafe then
			if math.abs(left.PreferredDistance - right.PreferredDistance) > 0.05 then
				return left.PreferredDistance < right.PreferredDistance
			end
			local bottomDifference = math.abs(
				left.BottomDistance - right.BottomDistance
			)
			if bottomDifference > 0.25 then
				return left.BottomDistance < right.BottomDistance
			end
			if math.abs(left.Clearance - right.Clearance) > 0.1 then
				return left.Clearance > right.Clearance
			end
			return left.SampleOrder < right.SampleOrder
		end
		if left.CoreBlockers ~= right.CoreBlockers then
			return left.CoreBlockers < right.CoreBlockers
		end
		if left.BlockerCount ~= right.BlockerCount then
			return left.BlockerCount < right.BlockerCount
		end
		if math.abs(left.Risk - right.Risk) > 1 then
			return left.Risk < right.Risk
		end
		if math.abs(left.PreferredDistance - right.PreferredDistance) > 0.05 then
			return left.PreferredDistance < right.PreferredDistance
		end
		if left.FlatSupportHits ~= right.FlatSupportHits then
			return left.FlatSupportHits > right.FlatSupportHits
		end
		if left.SupportHits ~= right.SupportHits then
			return left.SupportHits > right.SupportHits
		end
		local bottomDifference = math.abs(
			left.BottomDistance - right.BottomDistance
		)
		if bottomDifference > 0.25 then
			return left.BottomDistance < right.BottomDistance
		end
		if math.abs(left.Clearance - right.Clearance) > 0.1 then
			return left.Clearance > right.Clearance
		end
		return left.SampleOrder < right.SampleOrder
	end)

	local lookTarget = options.LookAtPosition
	local fixedLook = options.LookDirection and Vector3.new(
		options.LookDirection.X,
		0,
		options.LookDirection.Z
	) or nil
	local firstCandidate = candidates[1]
	local look = fixedLook and fixedLook or (lookTarget and Vector3.new(
		lookTarget.X - firstCandidate.Position.X,
		0,
		lookTarget.Z - firstCandidate.Position.Z
	) or Vector3.new(
		root.CFrame.LookVector.X,
		0,
		root.CFrame.LookVector.Z
	))
	if look.Magnitude < 0.05 then
		look = Vector3.new(
			firstCandidate.BoundingPart.CFrame.LookVector.X,
			0,
			firstCandidate.BoundingPart.CFrame.LookVector.Z
		)
	end
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit

	perkTrackerState.teleportSequence =
		(perkTrackerState.teleportSequence or 0) + 1
	teleportSequence = perkTrackerState.teleportSequence
	local originalPivot = character:GetPivot()
	local originalAnchored = root.Anchored
	local originalAutoRotate = humanoid.AutoRotate
	local originalPlatformStand = humanoid.PlatformStand
	local disabledStates = {}

	for _, state in ipairs({
		Enum.HumanoidStateType.FallingDown,
		Enum.HumanoidStateType.Ragdoll,
		Enum.HumanoidStateType.Freefall,
	}) do
		local ok, enabled = pcall(function()
			return humanoid:GetStateEnabled(state)
		end)
		if ok then
			disabledStates[state] = enabled
			pcall(function()
				humanoid:SetStateEnabled(state, false)
			end)
		end
	end

	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	local strictTeleportAttempts = 0
	local fallbackTeleportAttempts = 0
	local function tryCandidate(candidate, requireStrict)
		if not teleportIsActive()
			or not root.Parent
			or not humanoid.Parent
			or not assessCandidate(candidate)
			or candidate.CoreBlockers > 0
			or (requireStrict and not candidate.StrictSafe) then
			return false
		end

		if requireStrict then
			if strictTeleportAttempts >= 10 then
				return false
			end
			strictTeleportAttempts = strictTeleportAttempts + 1
		else
			if fallbackTeleportAttempts >= 12 then
				return false
			end
			fallbackTeleportAttempts = fallbackTeleportAttempts + 1
		end
		local expectedRisk = candidate.Risk
		local expectedSupportHits = candidate.SupportHits
		local destinationLook = look
		if fixedLook and fixedLook.Magnitude >= 0.05 then
			destinationLook = fixedLook.Unit
		elseif lookTarget then
			local targeted = Vector3.new(
				lookTarget.X - candidate.Position.X,
				0,
				lookTarget.Z - candidate.Position.Z
			)
			if targeted.Magnitude >= 0.05 then
				destinationLook = targeted.Unit
			end
		end
		local destination = CFrame.lookAt(
			candidate.Position,
			candidate.Position + destinationLook
		)
		local moved = pcall(function()
			character:PivotTo(destination)
		end)
		if not moved then
			return false
		end

		for _ = 1, 3 do
			if not teleportIsActive() or not root.Parent then
				return false
			end
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			Services.RunService.Heartbeat:Wait()
		end

		local settledFloorPosition = Vector3.new(
			root.Position.X,
			root.Position.Y - standingOffset,
			root.Position.Z
		)
		if not candidatePassesCustomValidation(root.Position) then
			return false
		end
		local footprintInspection = inspectFootprint(
			settledFloorPosition
		)
		if not footprintInspection.CenterSupported
			or not safelyInsideXZ(
				root.Position,
				candidate.BoundingPart
			) then
			return false
		end

		local bodyInspection = inspectBodyArea(
			root.Position,
			settledFloorPosition.Y,
			footprintInspection.SupportSet
		)
		local clearance = horizontalClearance(
			root.Position,
			settledFloorPosition.Y,
			footprintInspection.SupportSet
		)
		local settledStrict = candidate.NormalY >= 0.62
			and footprintInspection.FlatSupportHits
				== #footprintOffsets
			and bodyInspection.BlockerCount == 0
			and bodyInspection.CoreBlockers == 0

		if requireStrict then
			return settledStrict
		end

		local settledRisk = calculateRisk(
			bodyInspection,
			footprintInspection,
			clearance
		)
		return bodyInspection.CoreBlockers == 0
			and footprintInspection.SupportHits
			>= math.max(1, expectedSupportHits - 1)
			and settledRisk <= expectedRisk + 750
	end

	local selected = nil
	local strictModes = options.RequireStrict and {true} or {true, false}
	for _, requireStrict in ipairs(strictModes) do
		for groundTier = 0, 3 do
			for _, candidate in ipairs(candidates) do
				if candidate.GroundTier == groundTier
					and candidate.StrictSafe == requireStrict
					and tryCandidate(candidate, requireStrict) then
					selected = candidate
					break
				end
			end
			if selected then
				break
			end
		end
		if selected then
			break
		end
	end

	if not selected then
		local ownsCharacter = teleportOwnsCharacter()
		if ownsCharacter and root.Parent and character.Parent then
			pcall(function()
				character:PivotTo(originalPivot)
			end)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			Services.RunService.Heartbeat:Wait()
		end
		local releaseMovement = options.ReleaseMovementOnCancel == true
			and not teleportIsActive()
		if ownsCharacter and root.Parent then
			root.Anchored = if releaseMovement then false else originalAnchored
		end
		if ownsCharacter and humanoid.Parent then
			humanoid.PlatformStand = if releaseMovement
				then false
				else originalPlatformStand
			humanoid.AutoRotate = if releaseMovement
				then true
				else originalAutoRotate
			for state, enabled in pairs(disabledStates) do
				pcall(function()
					humanoid:SetStateEnabled(
						state,
						releaseMovement and true or enabled
					)
				end)
			end
			if releaseMovement then
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end)
			end
		end
		destroyBodyGeometryProbe()
		return false,
			releaseMovement and "teleport was cancelled"
				or "no grounded destination remained stable during teleport"
	end
	if not teleportIsActive() then
		local releaseMovement = options.ReleaseMovementOnCancel == true
		local ownsCharacter = teleportOwnsCharacter()
		if ownsCharacter and root.Parent and character.Parent then
			pcall(function()
				character:PivotTo(originalPivot)
			end)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = if releaseMovement then false else originalAnchored
		end
		if ownsCharacter and humanoid.Parent then
			humanoid.PlatformStand = if releaseMovement
				then false
				else originalPlatformStand
			humanoid.AutoRotate = if releaseMovement
				then true
				else originalAutoRotate
			for state, enabled in pairs(disabledStates) do
				pcall(function()
					humanoid:SetStateEnabled(
						state,
						releaseMovement and true or enabled
					)
				end)
			end
			if releaseMovement then
				pcall(function()
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end)
			end
		end
		destroyBodyGeometryProbe()
		return false, "teleport was cancelled"
	end

	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = originalAnchored
	humanoid.PlatformStand = originalPlatformStand
	humanoid.AutoRotate = originalAutoRotate

	for _ = 1, 3 do
		Services.RunService.Heartbeat:Wait()
		if teleportOwnsCharacter() and root.Parent then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end

	task.delay(0.65, function()
		if perkTrackerState.teleportSequence == teleportSequence
			and player.Character == character
			and root.Parent
			and humanoid.Parent then
			for state, enabled in pairs(disabledStates) do
				pcall(function()
					humanoid:SetStateEnabled(state, enabled)
				end)
			end
		end
	end)

	destroyBodyGeometryProbe()
	return true, nil
end


	return function(room, options)
		if closed or not runtimeIsActive() then
			return false, "teleport was cancelled"
		end
		return perkTrackerState.teleportToRoomBoundingBoxCenter(room, options)
	end
end
