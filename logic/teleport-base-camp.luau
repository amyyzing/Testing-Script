return function(dependencies)
	local player = assert(dependencies.Player, "teleport-base-camp requires Player")
	local world = dependencies.Workspace or workspace

	local function findBaseCamp()
		local map = world:FindFirstChild("Map")
		local rooms = map and map:FindFirstChild("Rooms")
		return rooms and (rooms:FindFirstChild("Base Camp") or rooms:FindFirstChild("BaseCamp"))
			or world:FindFirstChild("Base Camp")
			or world:FindFirstChild("BaseCamp")
	end

	local function boundingParts(room)
		local parts = {}
		for _, object in ipairs(room:GetDescendants()) do
			if object:IsA("BasePart") then
				local container = object
				while container and container ~= room and container.Name ~= "BoundingBox" do
					container = container.Parent
				end
				if object.Name == "BoundingBox" or container and container.Name == "BoundingBox" then
					table.insert(parts, object)
				end
			end
		end
		if room:IsA("BasePart") and room.Name == "BoundingBox" then table.insert(parts, room) end
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
		local room = findBaseCamp()
		if not root or not room then return false end

		local bounds = boundingParts(room)
		if #bounds == 0 then return false end
		local truckPosition = pivotPosition(room:FindFirstChild("Truck", true))
		if truckPosition then
			table.sort(bounds, function(a, b)
				return (a.Position - truckPosition).Magnitude < (b.Position - truckPosition).Magnitude
			end)
		end

		local excluded = {character}
		for _, part in ipairs(bounds) do table.insert(excluded, part) end
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = excluded
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = excluded

		local fallback
		for _, bound in ipairs(bounds) do
			local halfX = math.max(0, bound.Size.X * 0.5 - 2)
			local halfZ = math.max(0, bound.Size.Z * 0.5 - 2)
			local step = math.max(2, math.min(4, halfX, halfZ))
			local radius = 0
			while radius <= math.max(halfX, halfZ) do
				local offsets = radius == 0 and {Vector2.zero} or {
					Vector2.new(radius, 0), Vector2.new(-radius, 0),
					Vector2.new(0, radius), Vector2.new(0, -radius),
					Vector2.new(radius, radius), Vector2.new(radius, -radius),
					Vector2.new(-radius, radius), Vector2.new(-radius, -radius),
				}
				for _, offset in ipairs(offsets) do
					if math.abs(offset.X) <= halfX and math.abs(offset.Y) <= halfZ then
						local center = bound.CFrame:PointToWorldSpace(Vector3.new(offset.X, 0, offset.Y))
						local ray = world:Raycast(
							center,
							Vector3.new(0, -bound.Size.Y * 0.5 - 6, 0),
							rayParams
						)
						if ray then
							local position = ray.Position + Vector3.new(0, root.Size.Y * 0.5 + 0.3, 0)
							fallback = fallback or position
							local blocked = false
							for _, part in ipairs(world:GetPartBoundsInBox(
								CFrame.new(position), root.Size + Vector3.new(1, 1, 1), overlapParams
							)) do
								if part ~= ray.Instance and part.CanCollide then blocked = true break end
							end
							if not blocked then
								local targetRoot = CFrame.new(position) * root.CFrame.Rotation
								character:PivotTo(targetRoot * root.CFrame:ToObjectSpace(character:GetPivot()))
								root.AssemblyLinearVelocity = Vector3.zero
								root.AssemblyAngularVelocity = Vector3.zero
								return true
							end
						end
					end
				end
				radius += step
			end
		end

		if fallback then
			local targetRoot = CFrame.new(fallback) * root.CFrame.Rotation
			character:PivotTo(targetRoot * root.CFrame:ToObjectSpace(character:GetPivot()))
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			return true
		end
		return false
	end
end
