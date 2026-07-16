return function(dependencies)
	local player = assert(dependencies.Player, "teleport-base-camp requires Player")
	local world = dependencies.Workspace or workspace

	local function geometry(object)
		if object:IsA("Model") then return object:GetBoundingBox() end
		if object:IsA("BasePart") then return object.CFrame, object.Size end
		local part = object:FindFirstChildWhichIsA("BasePart", true)
		return part and part.CFrame or nil, part and part.Size or nil
	end

	return function()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local baseCamp = world:FindFirstChild("BaseCamp") or world:FindFirstChild("Base Camp")
		local target = baseCamp and (baseCamp:FindFirstChild("Truck", true) or baseCamp)
		if not root or not target then return false end

		local targetCFrame, targetSize = geometry(target)
		if not targetCFrame or not targetSize then return false end
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character}
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = {character}
		local directions = {
			{targetCFrame.LookVector, targetSize.Z * 0.5 + 5},
			{-targetCFrame.LookVector, targetSize.Z * 0.5 + 5},
			{targetCFrame.RightVector, targetSize.X * 0.5 + 5},
			{-targetCFrame.RightVector, targetSize.X * 0.5 + 5},
		}

		for extra = 0, 12, 4 do
			for _, option in ipairs(directions) do
				local direction = Vector3.new(option[1].X, 0, option[1].Z).Unit
				local xz = targetCFrame.Position + direction * (option[2] + extra)
				local ray = world:Raycast(xz + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), rayParams)
				if ray then
					local position = ray.Position + Vector3.new(0, root.Size.Y * 0.5 + 0.3, 0)
					local box = CFrame.new(position)
					local blocked = false
					for _, part in ipairs(world:GetPartBoundsInBox(box, root.Size + Vector3.new(2, 1, 2), overlapParams)) do
						if part ~= ray.Instance and part.CanCollide then blocked = true break end
					end
					if not blocked then
						local rootCFrame = CFrame.lookAt(position, Vector3.new(
							targetCFrame.Position.X,
							position.Y,
							targetCFrame.Position.Z
						))
						character:PivotTo(rootCFrame * root.CFrame:ToObjectSpace(character:GetPivot()))
						root.AssemblyLinearVelocity = Vector3.zero
						root.AssemblyAngularVelocity = Vector3.zero
						return true
					end
				end
			end
		end
		return false
	end
end
