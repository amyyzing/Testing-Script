return function(dependencies)
	local player = assert(dependencies.Player, "teleport-base-camp requires Player")
	local world = dependencies.Workspace or workspace
	local yield = dependencies.Wait or task.wait

	local function findBaseCamp()
		local map = world:FindFirstChild("Map")
		local rooms = map and map:FindFirstChild("Rooms")
		return rooms and (rooms:FindFirstChild("Base Camp") or rooms:FindFirstChild("BaseCamp"))
			or world:FindFirstChild("Base Camp")
			or world:FindFirstChild("BaseCamp")
	end

	local function boundingParts(room)
		local parts, seen, containers = {}, {}, {}
		local direct = room:FindFirstChild("BoundingBox")
		if direct then table.insert(containers, direct) end
		for _, object in ipairs(room:GetDescendants()) do
			if object.Name == "BoundingBox" and object ~= direct then table.insert(containers, object) end
		end
		local function add(part)
			if part and part:IsA("BasePart") and not seen[part] then
				seen[part] = true
				table.insert(parts, part)
			end
		end
		for _, container in ipairs(containers) do
			if container:IsA("BasePart") then
				add(container)
			else
				local before = #parts
				for _, child in ipairs(container:GetChildren()) do
					if child:IsA("BasePart") and child.Name == "Part" then add(child) end
				end
				if #parts == before then for _, child in ipairs(container:GetChildren()) do add(child) end end
				if #parts == before then for _, child in ipairs(container:GetDescendants()) do add(child) end end
			end
		end
		return parts
	end

	local function pivotPosition(object)
		if not object then return nil end
		if object:IsA("BasePart") then return object.Position end
		if object:IsA("Model") then return object:GetPivot().Position end
		local part = object:FindFirstChildWhichIsA("BasePart", true)
		return part and part.Position or nil
	end

	return function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local room = findBaseCamp()
		if not root or not humanoid then return false end
		local baseModel = world:FindFirstChild("BaseCamp") or world:FindFirstChild("Base Camp")
		local truck = baseModel and baseModel:FindFirstChild("Truck", true)
			or world:FindFirstChild("Truck", true)
		local truckPosition = pivotPosition(truck)
		local map = world:FindFirstChild("Map")
		local rooms = map and map:FindFirstChild("Rooms")
		if truckPosition and rooms and (not room or #boundingParts(room) == 0) then
			local bestRoom, bestDistance
			for _, candidate in ipairs(rooms:GetChildren()) do
				for _, part in ipairs(boundingParts(candidate)) do
					local localPoint = part.CFrame:PointToObjectSpace(truckPosition)
					local half = part.Size * 0.5
					local dx = math.max(math.abs(localPoint.X) - half.X, 0)
					local dz = math.max(math.abs(localPoint.Z) - half.Z, 0)
					local distance = math.sqrt(dx * dx + dz * dz)
					if not bestDistance or distance < bestDistance then
						bestRoom, bestDistance = candidate, distance
					end
				end
			end
			room = bestRoom or room
		end
		if not room then return false end

		local bounds = boundingParts(room)
		truckPosition = truckPosition or pivotPosition(room:FindFirstChild("Truck", true))
		if truckPosition then
			table.sort(bounds, function(a, b)
				return (a.Position - truckPosition).Magnitude < (b.Position - truckPosition).Magnitude
			end)
		end

		local function teleport(position)
			local targetRoot = CFrame.new(position) * root.CFrame.Rotation
			character:PivotTo(targetRoot * root.CFrame:ToObjectSpace(character:GetPivot()))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			return true
		end

		local excluded = {character}
		for _, part in ipairs(bounds) do table.insert(excluded, part) end
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = excluded
		rayParams.IgnoreWater = true
		pcall(function() rayParams.RespectCanCollide = true end)
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = excluded

		local candidates = {}
		local standingOffset = humanoid.HipHeight + root.Size.Y * 0.5 + 0.12
		local bodySize = Vector3.new(math.max(root.Size.X + 0.72, 2.3),
			math.max(root.Size.Y + humanoid.HipHeight + 2.35, 5.1),
			math.max(root.Size.Z + 0.72, 2.3))
		local inspected = 0
		for _, bound in ipairs(bounds) do
			local half = bound.Size * 0.5
			local inset = math.sqrt((root.Size.X * 0.5 + 0.22) ^ 2
				+ (root.Size.Z * 0.5 + 0.22) ^ 2) + 0.18
			local halfX = math.max(0, half.X - inset)
			local halfZ = math.max(0, half.Z - inset)
			local step = math.max(2, math.min(4, halfX, halfZ))
			local radius = 0
			while radius <= math.max(halfX, halfZ) do
				local offsets = {}
				if radius == 0 then
					table.insert(offsets, Vector2.zero)
				else
					for x = -radius, radius, step do
						for z = -radius, radius, step do
							if math.max(math.abs(x), math.abs(z)) >= radius - 0.01 then
								table.insert(offsets, Vector2.new(x, z))
							end
						end
					end
				end
				for _, offset in ipairs(offsets) do
					inspected += 1
					if inspected % 24 == 0 then yield() end
					if math.abs(offset.X) <= halfX and math.abs(offset.Y) <= halfZ then
						local center = bound.CFrame:PointToWorldSpace(Vector3.new(offset.X, 0, offset.Y))
						local ray = world:Raycast(
							Vector3.new(center.X, bound.Position.Y + half.Y + 2, center.Z),
							Vector3.new(0, -bound.Size.Y - 8, 0),
							rayParams
						)
						if ray and ray.Normal.Y >= 0.62 then
							local position = ray.Position + Vector3.new(0, standingOffset, 0)
							local localRoot = bound.CFrame:PointToObjectSpace(position)
							if math.abs(localRoot.X) <= halfX and math.abs(localRoot.Z) <= halfZ
								and localRoot.Y >= -half.Y - 0.35 and localRoot.Y <= half.Y - 0.1 then
								local blockerCount = 0
								for _, part in ipairs(world:GetPartBoundsInBox(
									CFrame.new(position.X, ray.Position.Y + 0.12 + bodySize.Y * 0.5, position.Z),
									bodySize, overlapParams
								)) do
									if part ~= ray.Instance and part.CanCollide then blockerCount += 1 end
								end
								table.insert(candidates, {
									Position = position,
									Blockers = blockerCount,
									Distance = truckPosition and (position - truckPosition).Magnitude or #candidates,
								})
							end
						end
					end
				end
				radius += step
			end
		end

		if #candidates > 0 then
			table.sort(candidates, function(a, b)
				local aOpen, bOpen = a.Blockers == 0, b.Blockers == 0
				if aOpen ~= bOpen then return aOpen end
				if a.Blockers ~= b.Blockers then return a.Blockers < b.Blockers end
				return a.Distance < b.Distance
			end)
			return teleport(candidates[1].Position)
		end

		if #bounds == 0 and truckPosition then
			local truckFallback
			for radius = 3, 12, 3 do
				local diagonal = radius / math.sqrt(2)
				for _, offset in ipairs({
					Vector2.new(radius, 0), Vector2.new(-radius, 0),
					Vector2.new(0, radius), Vector2.new(0, -radius),
					Vector2.new(diagonal, diagonal), Vector2.new(diagonal, -diagonal),
					Vector2.new(-diagonal, diagonal), Vector2.new(-diagonal, -diagonal),
				}) do
					local center = truckPosition + Vector3.new(offset.X, 8, offset.Y)
					local ray = world:Raycast(center, Vector3.new(0, -18, 0), rayParams)
					if ray and ray.Normal.Y >= 0.62 then
						local position = ray.Position + Vector3.new(0, standingOffset, 0)
						truckFallback = truckFallback or position
						local blocked = false
						for _, part in ipairs(world:GetPartBoundsInBox(
							CFrame.new(position.X, ray.Position.Y + 0.12 + bodySize.Y * 0.5, position.Z),
							bodySize, overlapParams
						)) do
							if part ~= ray.Instance and part.CanCollide then
								blocked = true
								break
							end
						end
						if not blocked then return teleport(position) end
					end
				end
			end
			if truckFallback then return teleport(truckFallback) end
		end
		return false
	end
end
