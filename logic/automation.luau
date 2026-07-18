local DROPPED_ITEMS = {
	"Spirit Box", "Laser Projector", "Video Camera", "Blacklight",
	"EMF Reader", "Cross", "Flower Pot",
}
local POWERED_ITEMS = {
	["spiritbox"] = true,
	["laserprojector"] = true,
	["blacklight"] = true,
	["emfreader"] = true,
}
local DOOR_MAX_DISTANCE = 2
local DOOR_MIN_DISTANCE = 1.35
local PLACEMENT_MAX_DISTANCE = 2
local REMOTE_DELAY = 0.1
local PLACEMENT_SETTLE = 0.35
local FACING_DOT = 0.995
local WIDE_AXIS_DOT_MAX = 0.05

local function normalize(value)
	return string.lower(tostring(value or "")):gsub("%s+", "")
end

local function itemName(model)
	if not model then return nil end
	local value = model:GetAttribute("ItemName")
	if type(value) == "string" and value ~= "" then return value end
	for _, object in ipairs(model:GetDescendants()) do
		value = object:GetAttribute("ItemName")
		if type(value) == "string" and value ~= "" then return value end
	end
	return nil
end

local function itemDepleted(model)
	local uses = model and tonumber(model:GetAttribute("Uses"))
	return uses ~= nil and uses <= 0
end

local function burntCross(model)
	if normalize(itemName(model)) ~= "cross" then return false end
	for _, object in ipairs({model, table.unpack(model:GetDescendants())}) do
		if object:GetAttribute("Burned") == true or object:GetAttribute("Burnt") == true
			or object:GetAttribute("Consumed") == true or object:GetAttribute("Used") == true
			or tonumber(object:GetAttribute("Uses")) == 0 then return true end
	end
	return false
end

return function(dependencies)
	local Services = assert(dependencies.Services, "automation requires Services")
	local Player = assert(dependencies.Player, "automation requires Player")
	local Ghost = assert(dependencies.Ghost, "automation requires Ghost")
	local Verdict = assert(dependencies.Verdict, "automation requires Verdict")
	local Remotes = assert(dependencies.Remotes, "automation requires Remotes")
	local World = Services.Workspace or workspace
	local button = dependencies.Button
	local autoSpirit = dependencies.AutoSpirit
	local escapeHunt = dependencies.EscapeHunt
	local teleportBaseCamp = dependencies.TeleportToBaseCamp
	local prepareReturn = dependencies.PrepareReturn
	local roundStarted = dependencies.RoundStarted
	local clock = dependencies.Clock or os.clock
	local wait = dependencies.Wait or task.wait
	local spawn = dependencies.Spawn or task.spawn
	local runtimeIsActive = dependencies.RuntimeIsActive or function() return true end
	local timeoutSeconds = tonumber(dependencies.TimeoutSeconds) or 180
	local confidenceNeeded = tonumber(dependencies.ConfidenceNeeded) or 60
	local disabledColor = button and button.BackgroundColor3
	local enabledColor = dependencies.EnabledColor or disabledColor
	local controller = {
		Enabled = false,
		Generation = 0,
		Phase = "Ready",
		StartedAt = 0,
		RoundStartedAt = nil,
		FacingLocks = {},
		Connections = {},
	}

	local function roundStartTime()
		return roundStarted and tonumber(roundStarted.StartedAt)
			or tonumber(controller.RoundStartedAt)
	end

	local function render()
		if not button then return end
		local elapsed = controller.Enabled and math.max(0, math.floor(clock() - controller.StartedAt)) or 0
		button.Text = controller.Enabled
			and ("AUTOMATION: ON %d:%02d\n%s"):format(math.floor(elapsed / 60), elapsed % 60, controller.Phase)
			or "AUTOMATION: OFF\nReady"
		button.BackgroundColor3 = controller.Enabled and enabledColor or disabledColor
	end

	local function phase(value)
		controller.Phase = value
		render()
	end

	local function alive(generation)
		return controller.Enabled and controller.Generation == generation and runtimeIsActive()
	end

	local function timedOut()
		return clock() - controller.StartedAt >= timeoutSeconds
	end

	local function pause(generation, seconds)
		local deadline = clock() + seconds
		repeat
			if not alive(generation) then return false end
			wait(math.min(0.1, math.max(0, deadline - clock())))
		until clock() >= deadline
		return alive(generation)
	end

	local function getRemote(name)
		local ok, callable
		if type(Remotes.Get) == "function" then
			ok, callable = pcall(Remotes.Get, Remotes, name)
		else
			ok, callable = true, Remotes[name]
		end
		return ok and type(callable) == "function" and callable or nil
	end

	local function remoteFor(generation, name, ...)
		local callable = getRemote(name)
		if not callable or not pause(generation, REMOTE_DELAY) then return false end
		if not alive(generation) or timedOut() or Ghost:GetAttribute("Hunting") == true then return false end
		return pcall(callable, ...)
	end

	local function ruledOut(index)
		return table.find(Verdict.RuledOut, index) ~= nil
	end

	local function bestGuess()
		local bestName, bestScore, bestIndex
		for index, name in ipairs(Verdict.Lists) do
			if not ruledOut(index) then
				local score = math.max(0,
					(Verdict.Confidence[index] or 0) - (Verdict.NegativeConfidence[index] or 0))
				if not bestName or score > bestScore
					or score == bestScore and bestName == "Skinwalker" and name ~= "Skinwalker" then
					bestName, bestScore, bestIndex = name, score, index
				end
			end
		end
		return bestName, bestScore or 0, bestIndex
	end

	local function identified()
		local name, score = bestGuess()
		return score >= confidenceNeeded, name, score
	end

	local roomBoundsCache = setmetatable({}, {__mode = "k"})
	local function bounds(room)
		if not room then return {} end
		local cached = roomBoundsCache[room]
		if cached and clock() - cached.At < 0.75 then
			local valid = #cached.Parts > 0
			for _, part in ipairs(cached.Parts) do
				if not part.Parent or not part:IsDescendantOf(room) then
					valid = false
					break
				end
			end
			if valid then return cached.Parts end
		end
		local result, seen, containers = {}, {}, {}
		if room:IsA("BasePart") and room.Name == "BoundingBox" then table.insert(containers, room) end
		local direct = room:FindFirstChild("BoundingBox")
		if direct then table.insert(containers, direct) end
		for _, object in ipairs(room:GetDescendants()) do
			if object.Name == "BoundingBox" and object ~= direct then table.insert(containers, object) end
		end
		local function add(part)
			if part and part:IsA("BasePart") and not seen[part] then
				seen[part] = true
				table.insert(result, part)
			end
		end
		for _, container in ipairs(containers) do
			if container:IsA("BasePart") then
				add(container)
			else
				local before = #result
				for _, child in ipairs(container:GetChildren()) do
					if child:IsA("BasePart") and child.Name == "Part" then add(child) end
				end
				if #result == before then
					for _, child in ipairs(container:GetChildren()) do add(child) end
				end
				if #result == before then
					for _, child in ipairs(container:GetDescendants()) do add(child) end
				end
			end
		end
		roomBoundsCache[room] = #result > 0 and {Parts = result, At = clock()} or nil
		return result
	end

	local function insidePart(part, position, horizontalTolerance, verticalTolerance)
		local point = part.CFrame:PointToObjectSpace(position)
		local half = part.Size * 0.5
		horizontalTolerance = horizontalTolerance or 0
		verticalTolerance = verticalTolerance or horizontalTolerance
		return math.abs(point.X) <= half.X + horizontalTolerance
			and math.abs(point.Y) <= half.Y + verticalTolerance
			and math.abs(point.Z) <= half.Z + horizontalTolerance
	end

	local function modelInsideRoom(model, room)
		local boxes = bounds(room)
		if not model or not model.Parent or #boxes == 0 then return false end
		local position = model:IsA("BasePart") and model.Position
			or model:IsA("Model") and model:GetPivot().Position
			or (function()
				local part = model:FindFirstChildWhichIsA("BasePart", true)
				return part and part.Position or nil
			end)()
		for _, box in ipairs(boxes) do
			if position and insidePart(box, position, 0.75, 0.6) then return true end
			local overlap = OverlapParams.new()
			overlap.FilterType = Enum.RaycastFilterType.Include
			overlap.FilterDescendantsInstances = {model}
			overlap.MaxParts = 1
			local ok, parts = pcall(World.GetPartBoundsInBox, World, box.CFrame,
				box.Size + Vector3.new(1.5, 1.2, 1.5), overlap)
			if ok and #parts > 0 then return true end
		end
		return false
	end

	local function modelInsideAnyRoom(model)
		local map = World:FindFirstChild("Map")
		local rooms = map and map:FindFirstChild("Rooms")
		if not rooms then return false end
		for _, room in ipairs(rooms:GetChildren()) do
			if modelInsideRoom(model, room) then return true end
		end
		return false
	end

	local function findRoom()
		local map = World:FindFirstChild("Map")
		local rooms = map and map:FindFirstChild("Rooms")
		if not rooms then return nil end
		local wanted = Ghost:GetAttribute("FavoriteRoom") or Ghost:GetAttribute("FavouriteRoom")
		if typeof(wanted) == "Instance" then return wanted end
		local key = normalize(wanted)
		for _, room in ipairs(rooms:GetChildren()) do
			if normalize(room.Name) == key then return room end
		end
		return nil
	end

	local function objectPosition(object)
		if not object then return nil end
		if object:IsA("BasePart") then return object.Position end
		if object:IsA("Model") then return object:GetPivot().Position end
		local part = object:FindFirstChildWhichIsA("BasePart", true)
		return part and part.Position or nil
	end

	local function findBaseCamp()
		local map = World:FindFirstChild("Map")
		local rooms = map and map:FindFirstChild("Rooms")
		if rooms then
			for _, room in ipairs(rooms:GetChildren()) do
				if normalize(room.Name) == "basecamp" then return room end
			end
		end
		local base = World:FindFirstChild("Base Camp") or World:FindFirstChild("BaseCamp")
		local truck = base and base:FindFirstChild("Truck", true) or World:FindFirstChild("Truck", true)
		local truckPosition = objectPosition(truck)
		if rooms and truckPosition then
			local bestRoom, bestDistance
			for _, room in ipairs(rooms:GetChildren()) do
				for _, box in ipairs(bounds(room)) do
					local point = box.CFrame:PointToObjectSpace(truckPosition)
					local half = box.Size * 0.5
					local dx = math.max(math.abs(point.X) - half.X, 0)
					local dz = math.max(math.abs(point.Z) - half.Z, 0)
					local distance = math.sqrt(dx * dx + dz * dz)
					if not bestDistance or distance < bestDistance then
						bestRoom, bestDistance = room, distance
					end
				end
			end
			if bestRoom then return bestRoom end
		end
		return base
	end

	local function defaultPlayerAtBaseCamp()
		local room = findBaseCamp()
		local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
		if not room or not root then return false end
		local boxes = bounds(room)
		for _, box in ipairs(boxes) do
			if insidePart(box, root.Position) then return true end
		end
		if #boxes > 0 then return false end
		local truck = room:FindFirstChild("Truck", true)
		local position = objectPosition(truck)
		return position ~= nil and (root.Position - position).Magnitude <= 12
	end
	local playerAtBaseCamp = dependencies.PlayerAtBaseCamp or defaultPlayerAtBaseCamp

	local function waitForNoHunt(generation)
		local escaped = false
		local failures = 0
		local nextAttempt = 0
		while alive(generation) and Ghost:GetAttribute("Hunting") == true do
			phase("Waiting for hunt to end")
			if not playerAtBaseCamp() and clock() >= nextAttempt
				and type(teleportBaseCamp) == "function" then
				local ok, moved = pcall(teleportBaseCamp)
				escaped = ok and moved == true and playerAtBaseCamp()
				if escaped then
					failures = 0
					nextAttempt = clock() + 0.15
				else
					failures += 1
					nextAttempt = clock() + math.min(2, 0.25 * 2 ^ math.min(failures - 1, 3))
				end
			end
			if timedOut() or not pause(generation, 0.15) then return false end
		end
		if escaped and not pause(generation, 0.65) then return false end
		return alive(generation) and not timedOut()
	end

	local function moveTo(position, face)
		local character = Player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not position then return false end
		local flatFace = face and Vector3.new(face.X, position.Y, face.Z)
		local target = flatFace and (flatFace - position).Magnitude > 0.05
			and CFrame.lookAt(position, flatFace)
			or CFrame.new(position) * root.CFrame.Rotation
		character:PivotTo(target * root.CFrame:ToObjectSpace(character:GetPivot()))
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		return true
	end

	local function horizontalDistanceToPart(part, position)
		local point = part.CFrame:PointToObjectSpace(position)
		local half = part.Size * 0.5
		local dx = math.max(math.abs(point.X) - half.X, 0)
		local dz = math.max(math.abs(point.Z) - half.Z, 0)
		return math.sqrt(dx * dx + dz * dz)
	end

	local function roomForTarget(target, preferred)
		local map = World:FindFirstChild("Map")
		local rooms = map and map:FindFirstChild("Rooms")
		if not rooms then return nil end
		local targetPosition = objectPosition(target)
		local references = preferred and #preferred > 0 and preferred
			or targetPosition and {targetPosition} or {}
		local bestRoom, bestInside, bestDistance
		for _, room in ipairs(rooms:GetChildren()) do
			local boxes = bounds(room)
			local insideCount, distance = 0, math.huge
			for _, position in ipairs(preferred or {}) do
				for _, box in ipairs(boxes) do
					if insidePart(box, position) then
						insideCount += 1
						break
					end
				end
			end
			for _, box in ipairs(boxes) do
				for _, position in ipairs(references) do
					distance = math.min(distance, horizontalDistanceToPart(box, position))
				end
			end
			if #boxes > 0 and (not bestRoom or insideCount > bestInside
				or insideCount == bestInside and distance < bestDistance) then
				bestRoom, bestInside, bestDistance = room, insideCount, distance
			end
		end
		return bestRoom
	end

	local function teleportInsideRoom(room, options)
		options = options or {}
		if type(options.IsActive) == "function" and options.IsActive() ~= true then
			return false
		end
		local character = Player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local boxes = bounds(room)
		if not character or not root or not humanoid or #boxes == 0 then return false end
		local preferred = type(options.PreferredPositions) == "table" and options.PreferredPositions or {}
		local candidates = {}
		local seen = {}
		local function add(position, box)
			if not position or not box then return end
			local key = ("%.3f:%.3f:%s"):format(position.X, position.Z, tostring(box))
			if not seen[key] then
				seen[key] = true
				table.insert(candidates, {Position = position, Box = box})
			end
		end
		for _, position in ipairs(preferred) do
			for _, box in ipairs(boxes) do
				local maximum = math.max(0.5, tonumber(options.MaximumPreferredDistance) or 0.5)
				for radius = 0, maximum, 0.25 do
					for _, offset in ipairs(radius == 0 and {Vector2.zero} or {
						Vector2.new(radius, 0), Vector2.new(-radius, 0),
						Vector2.new(0, radius), Vector2.new(0, -radius),
						Vector2.new(radius, radius), Vector2.new(radius, -radius),
						Vector2.new(-radius, radius), Vector2.new(-radius, -radius),
					}) do add(position + Vector3.new(offset.X, 0, offset.Y), box) end
				end
			end
		end
		if #preferred == 0 or options.RequireStrict ~= true then
			for _, box in ipairs(boxes) do
				local halfX = math.max(0, box.Size.X * 0.5 - 2)
				local halfZ = math.max(0, box.Size.Z * 0.5 - 2)
				for radius = 0, math.max(halfX, halfZ), 2 do
					for x = -radius, radius, 2 do
						for z = -radius, radius, 2 do
							if (radius == 0 or math.max(math.abs(x), math.abs(z)) >= radius - 0.01)
								and math.abs(x) <= halfX and math.abs(z) <= halfZ then
								add(box.CFrame:PointToWorldSpace(Vector3.new(x, 0, z)), box)
							end
						end
					end
				end
			end
		end
		local excluded = {character, Ghost, table.unpack(boxes)}
		local function raycastCollidable(origin, direction, additional)
			local ignores = table.clone(excluded)
			for _, object in ipairs(additional or {}) do table.insert(ignores, object) end
			for _ = 1, 12 do
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = ignores
				params.IgnoreWater = true
				pcall(function() params.RespectCanCollide = true end)
				local result = World:Raycast(origin, direction, params)
				if not result then return nil end
				if result.Instance == World.Terrain or result.Instance.CanCollide then return result end
				table.insert(ignores, result.Instance)
			end
			return nil
		end
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = excluded
		pcall(function() overlapParams.RespectCanCollide = true end)
		local footprintHalfX = root.Size.X * 0.5 + 0.22
		local footprintHalfZ = root.Size.Z * 0.5 + 0.22
		local horizontalInset = math.sqrt(footprintHalfX ^ 2 + footprintHalfZ ^ 2) + 0.18
		local standingOffset = humanoid.HipHeight + root.Size.Y * 0.5 + 0.12
		local bodySize = Vector3.new(math.max(root.Size.X + 0.72, 2.3),
			math.max(root.Size.Y + humanoid.HipHeight + 2.35, 5.1),
			math.max(root.Size.Z + 0.72, 2.3))
		local footprintOffsets = {
			Vector3.zero,
			Vector3.new(footprintHalfX, 0, 0), Vector3.new(-footprintHalfX, 0, 0),
			Vector3.new(0, 0, footprintHalfZ), Vector3.new(0, 0, -footprintHalfZ),
			Vector3.new(footprintHalfX, 0, footprintHalfZ), Vector3.new(footprintHalfX, 0, -footprintHalfZ),
			Vector3.new(-footprintHalfX, 0, footprintHalfZ), Vector3.new(-footprintHalfX, 0, -footprintHalfZ),
		}
		local function tryMove(position, box)
			local look = options.LookDirection
			local face = look and position + Vector3.new(look.X, 0, look.Z) or options.LookAtPosition
			local originalPivot = character:GetPivot()
			local originalAnchored = root.Anchored
			local originalAutoRotate = humanoid.AutoRotate
			local originalPlatformStand = humanoid.PlatformStand
			local states = {}
			for _, state in ipairs({
				Enum.HumanoidStateType.FallingDown,
				Enum.HumanoidStateType.Ragdoll,
				Enum.HumanoidStateType.Freefall,
			}) do
				local ok, enabled = pcall(humanoid.GetStateEnabled, humanoid, state)
				if ok then states[state] = enabled end
			end
			local moved = false
			local ok = xpcall(function()
				humanoid.Sit = false
				humanoid.PlatformStand = false
				humanoid.AutoRotate = false
				for state in pairs(states) do humanoid:SetStateEnabled(state, false) end
				root.Anchored = true
				moved = moveTo(position, face)
				for _ = 1, 3 do
					if type(options.IsActive) == "function" and options.IsActive() ~= true then
						moved = false
						break
					end
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					Services.RunService.Heartbeat:Wait()
				end
				moved = moved and insidePart(box, root.Position, 0, 0)
			end, debug.traceback)
			if (not ok or not moved) and character.Parent and root.Parent then
				pcall(character.PivotTo, character, originalPivot)
			end
			pcall(function()
				if root.Parent then
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					root.Anchored = originalAnchored
				end
				if humanoid.Parent then
					humanoid.PlatformStand = originalPlatformStand
					humanoid.AutoRotate = originalAutoRotate
					for state, enabled in pairs(states) do humanoid:SetStateEnabled(state, enabled) end
				end
			end)
			return ok and moved
		end
		local fallbacks = {}
		for index, candidate in ipairs(candidates) do
			if index > 1 and index % 12 == 1 then Services.RunService.Heartbeat:Wait() end
			if type(options.IsActive) == "function" and options.IsActive() ~= true then return false end
			local box = candidate.Box
			local localPoint = box.CFrame:PointToObjectSpace(candidate.Position)
			local half = box.Size * 0.5
			if math.abs(localPoint.X) <= half.X and math.abs(localPoint.Z) <= half.Z then
				local rayOrigin = Vector3.new(candidate.Position.X, box.Position.Y + half.Y + 2, candidate.Position.Z)
				local floor = raycastCollidable(rayOrigin, Vector3.new(0, -box.Size.Y - 8, 0))
				if floor and floor.Normal.Y >= 0.45 then
					local position = floor.Position + Vector3.new(0, standingOffset, 0)
					local targetPosition = options.TargetPosition
					local targetDistance = targetPosition and (Vector3.new(position.X, 0, position.Z)
						- Vector3.new(targetPosition.X, 0, targetPosition.Z)).Magnitude or 0
					local preferredDistance = math.huge
					for _, value in ipairs(preferred) do
						preferredDistance = math.min(preferredDistance, (Vector3.new(position.X, 0, position.Z)
							- Vector3.new(value.X, 0, value.Z)).Magnitude)
					end
					local validatorOk = not options.CandidateValidator or options.CandidateValidator(position)
					local rootLocal = box.CFrame:PointToObjectSpace(position)
					local fits = math.abs(rootLocal.X) <= math.max(0, half.X - horizontalInset)
						and math.abs(rootLocal.Z) <= math.max(0, half.Z - horizontalInset)
						and rootLocal.Y >= -half.Y - 0.35 and rootLocal.Y <= half.Y - 0.1
						and (not options.MaximumTargetDistance or targetDistance <= options.MaximumTargetDistance)
						and (not options.MaximumPreferredDistance or preferredDistance <= options.MaximumPreferredDistance)
						and validatorOk
					if fits then
						local support, supportHits = {}, 0
						for _, offset in ipairs(footprintOffsets) do
							local hit = raycastCollidable(floor.Position + offset + Vector3.new(0, 1.35, 0),
								Vector3.new(0, -2.85, 0))
							if hit and hit.Normal.Y >= 0.55
								and math.abs(hit.Position.Y - floor.Position.Y) <= 0.5 then
								supportHits += 1
								support[hit.Instance] = true
							end
						end
						local bodyCFrame = CFrame.new(position.X,
							floor.Position.Y + 0.12 + bodySize.Y * 0.5, position.Z)
						local blockers = 0
						for _, part in ipairs(World:GetPartBoundsInBox(bodyCFrame, bodySize, overlapParams)) do
							if part.CanCollide and not support[part] then blockers += 1 end
						end
						local strict = floor.Normal.Y >= 0.65
							and supportHits == #footprintOffsets and blockers == 0
						if strict and tryMove(position, box) then return true end
						if options.RequireStrict ~= true then
							table.insert(fallbacks, {
								Position = position,
								Box = box,
								Risk = blockers * 1000 + (#footprintOffsets - supportHits) * 100
									+ (1 - floor.Normal.Y) * 50,
								PreferredDistance = preferredDistance,
								TargetDistance = targetDistance,
							})
						end
					end
				end
			end
		end
		if options.RequireStrict ~= true then
			table.sort(fallbacks, function(a, b)
				if math.abs(a.Risk - b.Risk) > 0.001 then return a.Risk < b.Risk end
				if math.abs(a.PreferredDistance - b.PreferredDistance) > 0.001 then
					return a.PreferredDistance < b.PreferredDistance
				end
				return a.TargetDistance < b.TargetDistance
			end)
			for _, candidate in ipairs(fallbacks) do
				if tryMove(candidate.Position, candidate.Box) then return true end
			end
		end
		return false
	end

	local function teleportNearObject(object, maximumDistance, generation)
		local position = objectPosition(object)
		if not position then return false end
		local preferred = {}
		for radius = 2, maximumDistance, 2 do
			local diagonal = radius / math.sqrt(2)
			for _, offset in ipairs({
				Vector2.new(radius, 0), Vector2.new(-radius, 0),
				Vector2.new(0, radius), Vector2.new(0, -radius),
				Vector2.new(diagonal, diagonal), Vector2.new(diagonal, -diagonal),
				Vector2.new(-diagonal, diagonal), Vector2.new(-diagonal, -diagonal),
			}) do
				table.insert(preferred, position + Vector3.new(offset.X, 0, offset.Y))
			end
		end
		local room = roomForTarget(object, preferred)
		return room ~= nil and teleportInsideRoom(room, {
			PreferredPositions = preferred,
			TargetPosition = position,
			MaximumTargetDistance = maximumDistance,
			LookAtPosition = position,
			RequireStrict = true,
			IsActive = function() return alive(generation) and not timedOut() end,
		})
	end

	local function worldItems()
		local folder = World:FindFirstChild("Items")
		return folder and folder:GetChildren() or {}
	end

	local function findWorldItem(wanted, room)
		for _, model in ipairs(worldItems()) do
			if model:IsA("Model")
				and normalize(model:GetAttribute("ItemName")) == normalize(wanted)
				and not burntCross(model) and not itemDepleted(model)
				and (not room or modelInsideRoom(model, room)) then return model end
		end
		return nil
	end

	local function firstWorldItem(wanted, room)
		return room and findWorldItem(wanted, room) or findWorldItem(wanted)
	end

	local function findStoredItem(wanted, includeDepleted)
		for _, container in ipairs({Player.Character, Player:FindFirstChild("ToolsHolder")}) do
			if container then
				for _, model in ipairs(container:GetChildren()) do
					if normalize(itemName(model)) == normalize(wanted) and not burntCross(model)
						and (includeDepleted or not itemDepleted(model)) then return model end
				end
			end
		end
		return nil
	end

	local function hotbarSlot(wanted, knownItem)
		local gui = Player:FindFirstChildOfClass("PlayerGui")
		local slots = gui and gui:FindFirstChild("Hotbar")
		slots = slots and slots:FindFirstChild("Slots")
		for number = 1, 3 do
			local slot = slots and slots:FindFirstChild("InvSlot" .. number)
			local label = slot and slot:FindFirstChild("ItemName")
			if label and normalize(label.Text) == normalize(wanted) then return number end
		end
		local stored = knownItem or findStoredItem(wanted)
		if not stored then return nil end
		for _, attribute in ipairs({"InvSlot", "InventorySlot", "Slot", "SlotNumber"}) do
			local number = tonumber(stored:GetAttribute(attribute))
			if number and number >= 1 and number <= 3 then return number end
		end
		for number = 1, 3 do
			local value = Player:GetAttribute("InvSlot" .. number)
			if value ~= nil and value ~= false then
				local key = normalize(value)
				if key == normalize(stored.Name) or key == normalize(itemName(stored)) then return number end
			end
		end
		return nil
	end

	local function slotOccupied(number)
		local value = Player:GetAttribute("InvSlot" .. number)
		if value ~= nil and value ~= false and tostring(value) ~= "" then return true end
		local gui = Player:FindFirstChildOfClass("PlayerGui")
		local slots = gui and gui:FindFirstChild("Hotbar")
		slots = slots and slots:FindFirstChild("Slots")
		local slot = slots and slots:FindFirstChild("InvSlot" .. number)
		local label = slot and slot:FindFirstChild("ItemName")
		if label and tostring(label.Text or "") ~= "" then return true end
		for _, container in ipairs({Player.Character, Player:FindFirstChild("ToolsHolder")}) do
			if container then
				for _, model in ipairs(container:GetChildren()) do
					local name = itemName(model)
					if name and hotbarSlot(name, model) == number then return true end
				end
			end
		end
		return false
	end

	local function clearInventoryAtBase(generation)
		if type(teleportBaseCamp) ~= "function" then return false end
		for _ = 1, 3 do
			if not waitForNoHunt(generation) then return false end
			if not playerAtBaseCamp() then
				local ok, moved = pcall(teleportBaseCamp)
				if not ok or moved ~= true or not pause(generation, 0.15) then return false end
				if not playerAtBaseCamp() then return false end
			end
			local dropped, hadOccupied = false, false
			for number = 1, 3 do
				if slotOccupied(number) then
					hadOccupied = true
					dropped = remoteFor(generation, "RequestItemDrop", "InvSlot" .. number) or dropped
					if not pause(generation, 0.15) then return false end
				end
			end
			if not hadOccupied then return true end
			if not pause(generation, 0.2) then return false end
			if not dropped then continue end
		end
		for number = 1, 3 do
			if slotOccupied(number) then return false end
		end
		return true
	end

	local function acquire(wanted, generation)
		local stored = findStoredItem(wanted)
		if stored then return stored end
		local depleted = findStoredItem(wanted, true)
		if depleted and itemDepleted(depleted) then
			local slot = hotbarSlot(wanted, depleted)
			if slot then
				remoteFor(generation, "RequestItemDrop", "InvSlot" .. slot)
				pause(generation, 0.2)
			end
		end
		local model = firstWorldItem(wanted)
		local position = objectPosition(model)
		if not model or not position then return nil end
		if not alive(generation) or Ghost:GetAttribute("Hunting") == true then return nil end
		if not teleportNearObject(model, 8, generation) then return nil end
		if Ghost:GetAttribute("Hunting") == true then return nil end
		remoteFor(generation, "RequestItemPickup", model)
		for _ = 1, 12 do
			stored = findStoredItem(wanted)
			if stored then return stored end
			if timedOut() or not pause(generation, 0.1) then break end
		end
		return nil
	end

	local function equip(wanted, generation)
		local stored = acquire(wanted, generation)
		if not stored then return nil end
		local slot = hotbarSlot(wanted)
		if not slot then return nil end
		remoteFor(generation, "RequestItemEquip", "InvSlot" .. slot)
		pause(generation, 0.2)
		return findStoredItem(wanted), slot
	end

	local function enabledObject(model)
		if model:GetAttribute("Enabled") ~= nil then return model end
		for _, object in ipairs(model:GetDescendants()) do
			if object:GetAttribute("Enabled") ~= nil then return object end
		end
		return model
	end

	local function ensurePowered(model, generation)
		local stateObject = enabledObject(model)
		if stateObject:GetAttribute("Enabled") == true then return true end
		controller.ItemPower = controller.ItemPower or setmetatable({}, {__mode = "k"})
		local state = controller.ItemPower[stateObject]
		if not state then
			state = {Last = false, LastChangedAt = clock(), Transitions = {}}
			state.Connection = stateObject:GetAttributeChangedSignal("Enabled"):Connect(function()
				if not stateObject.Parent then return end
				local value = stateObject:GetAttribute("Enabled") == true
				if value ~= state.Last then
					state.Last = value
					state.LastChangedAt = clock()
					table.insert(state.Transitions, state.LastChangedAt)
					controller.ItemsDirty = true
				end
			end)
			controller.ItemPower[stateObject] = state
			table.insert(controller.Connections, state.Connection)
		end
		local now = clock()
		for index = #state.Transitions, 1, -1 do
			if now - state.Transitions[index] > 3 then table.remove(state.Transitions, index) end
		end
		if controller.SetupComplete then
			if #state.Transitions >= 3 then return true end
			if now - state.LastChangedAt < 3 then return true, true end
		end
		if not waitForNoHunt(generation) then return false end
		if not teleportNearObject(model, 8, generation) then return false end
		if Ghost:GetAttribute("Hunting") == true
			or not remoteFor(generation, "ToggleItemState", model) then return false end
		local deadline = clock() + 1
		repeat
			if stateObject:GetAttribute("Enabled") == true then return true end
			if not pause(generation, 0.05) then return false end
		until clock() >= deadline
		return false
	end

	local function defaultPlaceRoomItems(generation)
		local room = findRoom()
		if not room then return false end
		if controller.LastRoom ~= room then
			controller.LastRoom = room
			controller.SetupComplete = false
			controller.InventoryCleared = false
			controller.RetainedDoorTools = false
			controller.OutsideSince = {}
			controller.RoomItemFailures = {}
			controller.SkippedRoomItems = {}
			controller.PowerFailures = {}
		end
		controller.OutsideSince = controller.OutsideSince or {}
		controller.RoomItemFailures = controller.RoomItemFailures or {}
		controller.SkippedRoomItems = controller.SkippedRoomItems or {}
		controller.PowerFailures = controller.PowerFailures or {}
		if not controller.InventoryCleared then
			phase("Preparing room item inventory")
			if not clearInventoryAtBase(generation) then return false end
			controller.InventoryCleared = true
		end
		local complete, pendingGrace = true, false
		for _, wanted in ipairs(DROPPED_ITEMS) do
			local wantedKey = normalize(wanted)
			if controller.SkippedRoomItems[wantedKey] then continue end
			if not alive(generation) or identified() or timedOut() then return false end
			if not waitForNoHunt(generation) then return false end
			local placed = findWorldItem(wanted, room)
			local worldItem = placed or findWorldItem(wanted)
			if worldItem and not placed and controller.SetupComplete then
				local outsideSince = controller.OutsideSince[worldItem] or clock()
				controller.OutsideSince[worldItem] = outsideSince
				if clock() - outsideSince < 1.75 then
					pendingGrace = true
					continue
				end
			elseif placed then
				controller.OutsideSince[placed] = nil
			end
			if not placed then
				phase("Placing " .. wanted)
				local _, slot = equip(wanted, generation)
				local moved = slot and teleportInsideRoom(room, {
					RequireStrict = false,
					IsActive = function() return alive(generation) and not timedOut() end,
				})
				if slot and moved then
					if Ghost:GetAttribute("Hunting") == true then return false end
					remoteFor(generation, "RequestItemDrop", "InvSlot" .. slot)
					for _ = 1, 15 do
						placed = findWorldItem(wanted, room)
						if placed then break end
						if timedOut() or not pause(generation, 0.1) then return false end
					end
				end
			end
			if not placed then
				controller.RoomItemFailures[wantedKey] = (controller.RoomItemFailures[wantedKey] or 0) + 1
				if controller.RoomItemFailures[wantedKey] >= 5 then
					controller.SkippedRoomItems[wantedKey] = true
				else
					complete = false
				end
			else
				controller.RoomItemFailures[wantedKey] = 0
			end
			if placed and POWERED_ITEMS[normalize(wanted)]
				and enabledObject(placed):GetAttribute("Enabled") ~= true then
				local powered, waitingForStableOff = ensurePowered(placed, generation)
				pendingGrace = pendingGrace or waitingForStableOff == true
				if not powered then
					controller.PowerFailures[wantedKey] = (controller.PowerFailures[wantedKey] or 0) + 1
					controller.ItemsDirty = true
					if controller.PowerFailures[wantedKey] < 3 then complete = false end
				else
					controller.PowerFailures[wantedKey] = 0
				end
			end
		end
		if complete then
			if not controller.RetainedDoorTools then
				phase("Retaining Salt Canister and Holy Oil")
				if not clearInventoryAtBase(generation) then return false end
				acquire("Salt Canister", generation)
				acquire("Holy Oil", generation)
				controller.RetainedDoorTools = true
			end
			controller.SetupComplete = controller.RetainedDoorTools
			controller.ItemsDirty = pendingGrace
		end
		return complete and controller.RetainedDoorTools
	end

	local function targetFrame(target)
		if not target then return nil, nil end
		if target:IsA("BasePart") then return target.CFrame, target.Size end
		if target:IsA("Model") then
			local ok, frame, size = pcall(target.GetBoundingBox, target)
			if ok then return frame, size end
		end
		local part = target:FindFirstChildWhichIsA("BasePart", true)
		return part and part.CFrame or nil, part and part.Size or nil
	end

	local function resolveDoorReference(target)
		if not target then return nil end
		if target:IsA("BasePart") then return target end
		local union = target:FindFirstChild("DoorUnion", true)
		if union and union:IsA("BasePart") then return union end
		if not target:IsA("Model") then return target:FindFirstChildWhichIsA("BasePart", true) end
		local named = target:FindFirstChild("Door", true)
		if named and named:IsA("BasePart") then return named end
		if target.PrimaryPart then return target.PrimaryPart end
		local best, bestScore
		for _, part in ipairs(target:GetDescendants()) do
			if part:IsA("BasePart") then
				local wide = math.max(part.Size.X, part.Size.Z)
				local thin = math.max(math.min(part.Size.X, part.Size.Z), 0.05)
				local score = wide * math.max(part.Size.Y, 0.1) / thin
				if not bestScore or score > bestScore then best, bestScore = part, score end
			end
		end
		return best
	end

	local function doorReference(model)
		local container = model:FindFirstChild("Door") or model
		return container, resolveDoorReference(container)
	end

	local function horizontalUnit(vector, fallback)
		local flat = Vector3.new(vector.X, 0, vector.Z)
		return flat.Magnitude >= 0.05 and flat.Unit or fallback
	end

	local function doorGeometry(target)
		local reference = resolveDoorReference(target)
		local frame, size = targetFrame(reference)
		if not frame or not size then return nil end
		local right = horizontalUnit(frame.RightVector, Vector3.new(1, 0, 0))
		local look = horizontalUnit(frame.LookVector, Vector3.new(0, 0, -1))
		local wideAxis, normalAxis, thickness
		if size.X >= size.Z then
			wideAxis, normalAxis, thickness = right, look, size.Z
		else
			wideAxis, normalAxis, thickness = look, right, size.X
		end
		local minimum = math.clamp(thickness * 0.5 + 1.05, DOOR_MIN_DISTANCE, math.min(1.75, DOOR_MAX_DISTANCE))
		local stand = math.clamp(thickness * 0.5 + 1.5, minimum, math.min(1.85, DOOR_MAX_DISTANCE))
		return {
			Reference = reference, Frame = frame, Center = frame.Position,
			WideAxis = wideAxis, NormalAxis = normalAxis, Thickness = thickness,
			MinimumDistance = minimum, MaximumDistance = DOOR_MAX_DISTANCE,
			StandDistance = stand,
		}
	end

	local function doorApproaches(target, placementDistance)
		local geometry = doorGeometry(target)
		if not geometry then return {} end
		local calibrated = tonumber(placementDistance)
		if calibrated then calibrated = math.clamp(calibrated, 0.25, DOOR_MAX_DISTANCE) end
		local minimum = calibrated and math.max(0.25, calibrated - 0.2) or geometry.MinimumDistance
		local maximum = calibrated and math.min(DOOR_MAX_DISTANCE, calibrated + 0.2) or geometry.MaximumDistance
		local stand = calibrated or geometry.StandDistance
		local lateralMaximum = calibrated and 0.35 or 0.8
		local result = {}
		for _, side in ipairs({1, -1}) do
			local positions = {}
			for _, lateral in ipairs(calibrated and {0, -0.2, 0.2} or {0, -0.35, 0.35, -0.7, 0.7}) do
				for _, adjustment in ipairs({0, 0.2, -0.2}) do
					local radialMaximum = math.sqrt(math.max(0.25, DOOR_MAX_DISTANCE ^ 2 - lateral ^ 2))
					local allowedMaximum = math.min(maximum, radialMaximum)
					local allowedMinimum = math.min(minimum, allowedMaximum)
					local distance = math.clamp(stand + adjustment, allowedMinimum, allowedMaximum)
					table.insert(positions, geometry.Center + geometry.NormalAxis * side * distance
						+ geometry.WideAxis * lateral)
				end
			end
			table.insert(result, {
				Side = side, CandidatePositions = positions, Facing = geometry.NormalAxis * -side,
				Geometry = geometry, MinimumDistance = minimum, MaximumDistance = maximum,
				MaximumLateralOffset = lateralMaximum,
				MaximumPreferredDistance = calibrated and 0.35 or 0.8,
			})
		end
		return result
	end

	local function teleportToDoorFace(target, approach, generation)
		local geometry = approach and approach.Geometry
		local preferred = approach and approach.CandidatePositions
		if not geometry or not preferred or #preferred == 0 then return false end
		local room = roomForTarget(target, preferred)
		if not room then return false end
		return teleportInsideRoom(room, {
			PreferredPositions = preferred,
			TargetPosition = geometry.Center,
			MaximumTargetDistance = DOOR_MAX_DISTANCE,
			MaximumPreferredDistance = approach.MaximumPreferredDistance or 0.8,
			LookDirection = approach.Facing,
			RequireStrict = true,
			CandidateValidator = function(position)
				local relative = Vector3.new(position.X - geometry.Center.X, 0, position.Z - geometry.Center.Z)
				local lateral = math.abs(relative:Dot(geometry.WideAxis))
				local normal = relative:Dot(geometry.NormalAxis)
				return relative.Magnitude <= DOOR_MAX_DISTANCE
					and lateral <= (approach.MaximumLateralOffset or 0.8)
					and normal * approach.Side > 0
					and math.abs(normal) >= (approach.MinimumDistance or geometry.MinimumDistance)
					and math.abs(normal) <= (approach.MaximumDistance or geometry.MaximumDistance)
			end,
			IsActive = function() return alive(generation) and not timedOut() end,
		})
	end

	local function isExitDoor(model)
		local key = string.lower(tostring(model.Name or "")):gsub("[^%w]", "")
		local kind = string.lower(tostring(
			model:GetAttribute("DoorType") or model:GetAttribute("Type") or ""
		)):gsub("[^%w]", "")
		return string.find(key, "exitdoor", 1, true) ~= nil
			or model:GetAttribute("IsExitDoor") == true
			or model:GetAttribute("ExitDoor") == true
			or kind == "exit" or kind == "exitdoor"
	end

	local function resolveExitDoors()
		local folder = World:FindFirstChild("Doors")
		local exits, exitSet = {}, {}
		if not folder then return exits, exitSet end
		local function directContainer(object)
			local current = object
			while current and current.Parent ~= folder do current = current.Parent end
			return current and current.Parent == folder and current or nil
		end
		local function mark(object)
			local container = directContainer(object)
			if container and not exitSet[container] then
				exitSet[container] = true
				table.insert(exits, container)
			end
		end
		mark(folder:FindFirstChild("ExitDoor"))
		for _, object in ipairs(folder:GetDescendants()) do
			if isExitDoor(object) then mark(object) end
		end
		for _, object in ipairs(folder:GetChildren()) do
			if isExitDoor(object) then mark(object) end
		end
		return exits, exitSet
	end

	local function doorClosed(model, container)
		local objects, seen, sawClosed = {}, {}, false
		local function add(object)
			if object and not seen[object] then
				seen[object] = true
				table.insert(objects, object)
			end
		end
		add(model)
		add(container)
		local current = resolveDoorReference(container)
		while current and current ~= model do
			add(current)
			current = current.Parent
		end
		if container then
			for _, object in ipairs(container:GetDescendants()) do
				if object:GetAttribute("DoorClosed") ~= nil or normalize(object.Name) == "doorunion" then add(object) end
			end
		end
		for _, object in ipairs(objects) do
			local state = object.Parent and object:GetAttribute("DoorClosed")
			if state == false then return false end
			if state == true then sawClosed = true end
		end
		return sawClosed and true or nil
	end

	local function waitStableClosed(model, generation)
		local deadline, previous, passes = clock() + 3, nil, 0
		repeat
			if timedOut() or not alive(generation) or Ghost:GetAttribute("Hunting") == true then return nil end
			local container, reference = doorReference(model)
			if doorClosed(model, container) == true and reference then
				local snapshot = {Reference = reference, Frame = reference.CFrame, Size = reference.Size}
				local stable = previous and snapshot.Reference == previous.Reference
					and (snapshot.Frame.Position - previous.Frame.Position).Magnitude <= 0.05
					and snapshot.Frame.RightVector:Dot(previous.Frame.RightVector) >= 0.9995
					and snapshot.Frame.LookVector:Dot(previous.Frame.LookVector) >= 0.9995
					and (snapshot.Size - previous.Size).Magnitude <= 0.02
				passes = stable and passes + 1 or 1
				previous = snapshot
				if passes >= 4 then return reference end
			else
				previous, passes = nil, 0
			end
			if not pause(generation, 0.08) then return nil end
		until clock() >= deadline
		return nil
	end

	local function closeDoor(model, container, reference, generation)
		if timedOut() then return false end
		local state = doorClosed(model, container)
		if state == nil then
			local stateDeadline = clock() + 1
			repeat
				if timedOut() or not pause(generation, 0.05) then return false end
				container, reference = doorReference(model)
				state = doorClosed(model, container)
				if state ~= nil then break end
			until clock() >= stateDeadline
		end
		if state == true then return waitStableClosed(model, generation) ~= nil end
		if state ~= false then return false end
		local moved = false
		for _, approach in ipairs(doorApproaches(reference)) do
			if teleportToDoorFace(reference, approach, generation) then
				moved = true
				break
			end
		end
		if not moved then return false end
		local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
		container, reference = doorReference(model)
		if not root or not reference or (root.Position - reference.Position).Magnitude > 10 then return false end
		state = doorClosed(model, container)
		if state == nil then return false end
		local firedAt, retried
		if state == false then
			if not pause(generation, REMOTE_DELAY) then return false end
			container, reference = doorReference(model)
			local currentState = doorClosed(model, container)
			if currentState ~= false then
				return currentState == true and waitStableClosed(model, generation) ~= nil
			end
			local changeDoor = getRemote("ClientChangeDoorState")
			if not changeDoor or not pcall(changeDoor, container) then return false end
			firedAt = clock()
		end
		local deadline = clock() + 4
		repeat
			container, reference = doorReference(model)
			state = doorClosed(model, container)
			if state == true then break end
			if firedAt and not retried and clock() - firedAt >= 1.5 and state == false then
				retried = true
				root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
				if root and reference and (root.Position - reference.Position).Magnitude <= 10
					and pause(generation, REMOTE_DELAY) then
					container, reference = doorReference(model)
					if doorClosed(model, container) == false then
						local changeDoor = getRemote("ClientChangeDoorState")
						if changeDoor then pcall(changeDoor, container) end
					end
				end
			end
			if timedOut() or not pause(generation, 0.05) then return false end
		until clock() >= deadline
		if state ~= true then return false end
		if firedAt and not pause(generation, 1) then return false end
		return waitStableClosed(model, generation) ~= nil
	end

	local function placementSnapshot(folderName)
		local folder = World:FindFirstChild(folderName)
		local snapshot = {}
		if folder then
			for _, object in ipairs(folder:GetDescendants()) do snapshot[object] = true end
		end
		return snapshot
	end

	local function newValidPlacement(folderName, before, rootPosition, reference, previewPosition)
		local folder = World:FindFirstChild(folderName)
		if not folder then return nil end
		for _, object in ipairs(folder:GetDescendants()) do
			if not before[object] and (object:IsA("Model") or object:IsA("BasePart")) then
				local placement = object
				while placement.Parent and placement.Parent ~= folder do placement = placement.Parent end
				local position = objectPosition(placement)
				if position then
					local distance = (Vector3.new(position.X, 0, position.Z)
						- Vector3.new(rootPosition.X, 0, rootPosition.Z)).Magnitude
					local previewDistance = previewPosition and (Vector3.new(position.X, 0, position.Z)
						- Vector3.new(previewPosition.X, 0, previewPosition.Z)).Magnitude or math.huge
					local geometry = doorGeometry(reference)
					local doorDistance = geometry and (Vector3.new(position.X, 0, position.Z)
						- Vector3.new(geometry.Center.X, 0, geometry.Center.Z)).Magnitude or math.huge
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = {placement, Player.Character}
					local floor = World:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -6, 0), params)
					if distance <= PLACEMENT_MAX_DISTANCE + 0.75
						and previewDistance <= 1.25
						and doorDistance <= DOOR_MAX_DISTANCE and floor and floor.Normal.Y >= 0.5
						and modelInsideAnyRoom(placement) then return placement end
				end
			end
		end
		return nil
	end

	local function beginFacingLock(reference, generation)
		local character = Player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local geometry = doorGeometry(reference)
		if not character or not root or not humanoid or not geometry then return nil end
		local originalAutoRotate = humanoid.AutoRotate
		local camera = World.CurrentCamera
		if not camera then return nil end
		local originalCameraType = camera.CameraType
		local lock = {Released = false, Connections = {}, Heartbeats = 0, Renders = 0}
		local function context()
			geometry = doorGeometry(reference)
			if not geometry or Player.Character ~= character or not root.Parent or not humanoid.Parent then return nil end
			local offset = Vector3.new(root.Position.X - geometry.Center.X, 0, root.Position.Z - geometry.Center.Z)
			local normal = offset:Dot(geometry.NormalAxis)
			if offset.Magnitude > DOOR_MAX_DISTANCE or math.abs(normal) < 0.05 then return nil end
			return geometry.NormalAxis * (normal > 0 and -1 or 1)
		end
		function lock:Enforce()
			if self.Released or not alive(generation) or timedOut()
				or Ghost:GetAttribute("Hunting") == true or Player:GetAttribute("Dead") == true then return false end
			local expected = context()
			if not expected then return false end
			local ok = pcall(function()
				humanoid.AutoRotate = false
				camera.CameraType = Enum.CameraType.Scriptable
				humanoid:Move(Vector3.zero, false)
				local desired = CFrame.lookAt(root.Position, root.Position + expected)
				local pivotOffset = root.CFrame:ToObjectSpace(character:GetPivot())
				character:PivotTo(desired * pivotOffset)
				root.CFrame = desired
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				if World.CurrentCamera == camera then
					local oldLook = horizontalUnit(camera.CFrame.LookVector, expected)
					local yaw = math.atan2(oldLook:Cross(expected).Y, oldLook:Dot(expected))
					local position = camera.CFrame.Position
					camera.CFrame = CFrame.new(position) * CFrame.fromAxisAngle(Vector3.yAxis, yaw)
						* (camera.CFrame - position)
				end
			end)
			if not ok or World.CurrentCamera ~= camera then return false end
			local facing = horizontalUnit(root.CFrame.LookVector, Vector3.zero)
			local cameraFacing = horizontalUnit(camera.CFrame.LookVector, Vector3.zero)
			return facing.Magnitude >= 0.05 and cameraFacing.Magnitude >= 0.05
				and facing:Dot(expected) >= FACING_DOT
				and cameraFacing:Dot(expected) >= FACING_DOT
				and math.abs(facing:Dot(geometry.WideAxis)) <= WIDE_AXIS_DOT_MAX
				and math.abs(cameraFacing:Dot(geometry.WideAxis)) <= WIDE_AXIS_DOT_MAX
		end
		function lock:Release()
			if self.Released then return end
			self.Released = true
			for _, connection in ipairs(self.Connections) do pcall(connection.Disconnect, connection) end
			if humanoid.Parent and Player.Character == character then
				pcall(function() humanoid.AutoRotate = originalAutoRotate end)
			end
			if World.CurrentCamera == camera then
				pcall(function() camera.CameraType = originalCameraType end)
			end
			controller.FacingLocks[self] = nil
		end
		local connected, connection = pcall(function()
			return Services.RunService.Heartbeat:Connect(function()
				if lock:Enforce() then
					lock.Heartbeats += 1
					lock.Renders += 1
				else
					lock:Release()
				end
			end)
		end)
		if not connected then
			lock:Release()
			return nil
		end
		table.insert(lock.Connections, connection)
		controller.FacingLocks[lock] = true
		if not lock:Enforce() then
			lock:Release()
			return nil
		end
		return lock
	end

	local function releaseFacingLocks()
		local locks = {}
		for lock in pairs(controller.FacingLocks) do table.insert(locks, lock) end
		for _, lock in ipairs(locks) do lock:Release() end
	end

	local function releaseConnections()
		for _, connection in ipairs(controller.Connections) do pcall(connection.Disconnect, connection) end
		controller.Connections = {}
	end

	local function placementPreviewPart(wanted)
		local camera = World.CurrentCamera
		local preview = wanted == "Salt Canister"
			and camera and camera:FindFirstChild("SaltLine")
			or camera and camera:FindFirstChild("HolyOil")
		local part = preview and preview:FindFirstChild(wanted == "Salt Canister" and "Salt" or "Center", true)
		return part and part:IsA("BasePart") and part or nil
	end

	local function placementXZDistance(wanted, generation)
		local deadline, lastDistance, stablePasses = clock() + 2, nil, 0
		repeat
			Services.RunService.Heartbeat:Wait()
			if not alive(generation) or timedOut() or Ghost:GetAttribute("Hunting") == true then return nil end
			local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
			local part = placementPreviewPart(wanted)
			if root and part then
				local offset = Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z)
				local distance = offset.Magnitude
				if distance >= 0.25 and distance <= PLACEMENT_MAX_DISTANCE then
					stablePasses = lastDistance and math.abs(distance - lastDistance) <= 0.05
						and stablePasses + 1 or 1
					lastDistance = distance
					if stablePasses >= 3 then return distance end
				else
					lastDistance, stablePasses = nil, 0
				end
			else
				lastDistance, stablePasses = nil, 0
			end
		until clock() >= deadline
		return nil
	end

	local function previewReady(wanted, reference, root)
		local part = placementPreviewPart(wanted)
		local geometry = doorGeometry(reference)
		if not part or not part:IsA("BasePart") or not geometry then return false end
		local rootOffset = Vector3.new(root.Position.X - geometry.Center.X, 0, root.Position.Z - geometry.Center.Z)
		local rootNormal = rootOffset:Dot(geometry.NormalAxis)
		local rootFacing = horizontalUnit(root.CFrame.LookVector, Vector3.zero)
		local expected = geometry.NormalAxis * (rootNormal > 0 and -1 or 1)
		if rootOffset.Magnitude > DOOR_MAX_DISTANCE
			or math.abs(rootOffset:Dot(geometry.WideAxis)) > 0.8
			or math.abs(rootNormal) < 0.05
			or rootFacing.Magnitude < 0.05
			or rootFacing:Dot(expected) < FACING_DOT
			or math.abs(rootFacing:Dot(geometry.WideAxis)) > WIDE_AXIS_DOT_MAX then return false end
		local playerOffset = Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z)
		local doorOffset = Vector3.new(geometry.Center.X - root.Position.X, 0, geometry.Center.Z - root.Position.Z)
		local previewOffset = Vector3.new(part.Position.X - geometry.Center.X, 0, part.Position.Z - geometry.Center.Z)
		if playerOffset.Magnitude > PLACEMENT_MAX_DISTANCE or doorOffset.Magnitude < 0.05
			or playerOffset:Dot(doorOffset.Unit) <= 0
			or math.abs(previewOffset:Dot(geometry.WideAxis)) > 0.9
			or math.abs(previewOffset:Dot(geometry.NormalAxis))
				> math.min(math.max(geometry.Thickness * 0.5 + 0.5, 0.75), 1.25) then return false end
		if wanted == "Salt Canister" then
			local minimum = math.max(math.min(part.Size.X, part.Size.Z), 0.001)
			if math.max(part.Size.X, part.Size.Z) / minimum >= 1.15 then
				local axis = part.Size.X >= part.Size.Z and part.CFrame.RightVector or part.CFrame.LookVector
				axis = horizontalUnit(axis, Vector3.zero)
				if axis.Magnitude < 0.05 or math.abs(axis:Dot(geometry.WideAxis)) < 0.995 then return false end
			end
		end
		return true, part, geometry
	end

	local function placeTool(wanted, model, generation)
		if timedOut() then return false end
		local useItem = getRemote("UseItem")
		local fallback = getRemote(wanted == "Salt Canister" and "LaySaltPile" or "PourHolyOil")
		if not useItem and not fallback then return false end
		local tool = equip(wanted, generation)
		if not tool then return false end
		local cooldownDeadline = clock() + 6
		while tool.Parent and tool:GetAttribute("EquipDisabled") == true and clock() < cooldownDeadline do
			if timedOut() or not pause(generation, 0.05) then return false end
		end
		if tool:GetAttribute("EquipDisabled") == true then return false end
		local uses = tonumber(tool:GetAttribute("Uses"))
		local usesDeadline = clock() + 1.5
		while uses == nil and clock() < usesDeadline do
			if timedOut() or not pause(generation, 0.05) then return false end
			tool = findStoredItem(wanted, true) or tool
			uses = tonumber(tool:GetAttribute("Uses"))
		end
		if uses == nil then return false end
		if uses ~= nil and uses <= 0 then return false end
		local calibratedDistance = wanted == "Salt Canister"
			and placementXZDistance(wanted, generation) or nil
		local container, reference = doorReference(model)
		if not reference or not closeDoor(model, container, reference, generation) then return false end
		container, reference = doorReference(model)
		local character = Player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return false end
		local positioned, facingLock = false, nil
		local approaches = doorApproaches(reference, calibratedDistance)
		local favourite = findRoom()
		local favouriteBounds = bounds(favourite)
		local approachOrder = {}
		for index, approach in ipairs(approaches) do approachOrder[approach] = index end
		table.sort(approaches, function(a, b)
			local function score(approach)
				for _, position in ipairs(approach.CandidatePositions) do
					for _, box in ipairs(favouriteBounds) do
						if insidePart(box, position, 0, 0) then return 1 end
					end
				end
				return 0
			end
			local aScore, bScore = score(a), score(b)
			if aScore ~= bScore then return aScore > bScore end
			return approachOrder[a] < approachOrder[b]
		end)
		for _, approach in ipairs(approaches) do
			if teleportToDoorFace(reference, approach, generation) then
				local lock = beginFacingLock(reference, generation)
				if lock then
					local deadline, stableSince, stablePasses, baseline = clock() + 4.5, nil, 0, nil
					local startingRenders, startingHeartbeats = lock.Renders, lock.Heartbeats
					repeat
						Services.RunService.Heartbeat:Wait()
						if lock.Released or Ghost:GetAttribute("Hunting") == true
							or timedOut() or not alive(generation) then break end
						local aligned, part, geometry = previewReady(wanted, reference, root)
						if lock:Enforce() and aligned and part and geometry then
							local snapshot = {
								Preview = part.Position,
								Root = root.Position,
								Door = geometry.Center,
								Normal = geometry.NormalAxis,
							}
							local stable = not baseline
								or (snapshot.Preview - baseline.Preview).Magnitude <= 0.12
									and (snapshot.Root - baseline.Root).Magnitude <= 0.08
									and (snapshot.Door - baseline.Door).Magnitude <= 0.05
									and snapshot.Normal:Dot(baseline.Normal) >= 0.999
							if not stable then
								stableSince, stablePasses, baseline = nil, 0, nil
								startingRenders, startingHeartbeats = lock.Renders, lock.Heartbeats
							end
							baseline = baseline or snapshot
							stableSince = stableSince or clock()
							stablePasses += 1
							if stablePasses >= 5 and clock() - stableSince >= PLACEMENT_SETTLE
								and lock.Renders - startingRenders >= 5
								and lock.Heartbeats - startingHeartbeats >= 3 then
								positioned, facingLock = true, lock
								break
							end
						else
							stableSince, stablePasses, baseline = nil, 0, nil
							startingRenders, startingHeartbeats = lock.Renders, lock.Heartbeats
						end
					until clock() >= deadline
					if not positioned then lock:Release() end
				end
			end
			if positioned then break end
		end
		if not positioned then return false end
		if Ghost:GetAttribute("Hunting") == true or not facingLock:Enforce() then
			facingLock:Release()
			return false
		end
		local folder = wanted == "Salt Canister" and "SaltPiles" or "HolyOil"
		local before = placementSnapshot(folder)
		local preview = placementPreviewPart(wanted)
		local dispatchRootPosition = root.Position
		local dispatchPreviewPosition = preview and preview.Position
		if not dispatchPreviewPosition or not pause(generation, REMOTE_DELAY)
			or not facingLock:Enforce() or not previewReady(wanted, reference, root) then
			facingLock:Release()
			return false
		end
		local fired = pcall(useItem or fallback)
		facingLock:Release()
		if not fired then return false end
		local usesConfirmed, spawnConfirmed = false, false
		local confirmationDeadline = clock() + 3
		repeat
			local current = findStoredItem(wanted, true) or tool
			local currentUses = current and tonumber(current:GetAttribute("Uses"))
			usesConfirmed = usesConfirmed or currentUses ~= nil and currentUses < uses
			spawnConfirmed = spawnConfirmed or newValidPlacement(folder, before,
				dispatchRootPosition, reference, dispatchPreviewPosition) ~= nil
			if usesConfirmed and spawnConfirmed then break end
			if timedOut() or not pause(generation, 0.05) then return false end
		until clock() >= confirmationDeadline
		local postCooldown = clock() + 6
		repeat
			local current = findStoredItem(wanted, true) or tool
			if not current.Parent or current:GetAttribute("EquipDisabled") ~= true then break end
			if timedOut() or not pause(generation, 0.05) then return false end
		until clock() >= postCooldown
		local current = findStoredItem(wanted, true) or tool
		if current.Parent and current:GetAttribute("EquipDisabled") == true then return false end
		return usesConfirmed
	end

	local function defaultPlaceDoorTools(generation)
		local room = findRoom()
		local doors = World:FindFirstChild("Doors")
		if not room or not doors then return false end
		local roomBounds = bounds(room)
		local _, exitSet = resolveExitDoors()
		local candidates, candidateOrder = {}, {}
		for index, model in ipairs(doors:GetChildren()) do
			local _, reference = doorReference(model)
			if model:IsA("Model") and not exitSet[model] and reference then
				table.insert(candidates, model)
				candidateOrder[model] = index
			end
		end
		local function distanceToRoom(model)
			local _, reference = doorReference(model)
			local best
			for _, box in ipairs(roomBounds) do
				local distance = horizontalDistanceToPart(box, reference.Position)
				if not best or distance < best then best = distance end
			end
			return best or math.huge
		end
		table.sort(candidates, function(a, b)
			local aDistance, bDistance = distanceToRoom(a), distanceToRoom(b)
			if math.abs(aDistance - bDistance) > 0.001 then return aDistance < bDistance end
			local aName, bName = normalize(a.Name), normalize(b.Name)
			if aName ~= bName then return aName < bName end
			return candidateOrder[a] < candidateOrder[b]
		end)
		controller.UsedDoorModels = controller.UsedDoorModels or {}
		controller.UsedDoorNames = controller.UsedDoorNames or {}
		controller.DoorPlacements = controller.DoorPlacements or {}
		controller.CompletedDoorTools = controller.CompletedDoorTools or {}
		controller.MissingDoorTools = controller.MissingDoorTools or {}
		controller.DoorRetryPasses = controller.DoorRetryPasses or {}
		local function hasNearbyPlacement(model, folderName)
			local _, reference = doorReference(model)
			local geometry = doorGeometry(reference)
			local folder = World:FindFirstChild(folderName)
			if not geometry or not folder then return false end
			for _, placement in ipairs(folder:GetChildren()) do
				local position = objectPosition(placement)
				if position and (Vector3.new(position.X, 0, position.Z)
					- Vector3.new(geometry.Center.X, 0, geometry.Center.Z)).Magnitude <= 3 then return true end
			end
			return false
		end
		local complete = true
		for _, wanted in ipairs({"Salt Canister", "Holy Oil"}) do
			local key = normalize(wanted)
			local placed = controller.DoorPlacements[key] or 0
			local tried = {}
			if placed >= 3 or controller.CompletedDoorTools[key] then continue end
			if not waitForNoHunt(generation) then return false end
			if not acquire(wanted, generation) then
				phase(wanted .. " unavailable")
				controller.MissingDoorTools[key] = (controller.MissingDoorTools[key] or 0) + 1
				if controller.MissingDoorTools[key] >= 5 then
					controller.CompletedDoorTools[key] = true
					local stored = findStoredItem(wanted, true)
					local slot = stored and hotbarSlot(wanted, stored)
					if slot then remoteFor(generation, "RequestItemDrop", "InvSlot" .. slot) end
				else
					complete = false
				end
				continue
			end
			controller.MissingDoorTools[key] = 0
			local beforePlaced = placed
			for namePass = 1, 2 do
				for _, model in ipairs(candidates) do
					if placed >= 3 then break end
					if not alive(generation) or identified() or timedOut() then return false end
					if not controller.UsedDoorModels[model] and not tried[model]
						and (wanted ~= "Holy Oil" or not hasNearbyPlacement(model, "HolyOil"))
						and (namePass == 2 or not controller.UsedDoorNames[normalize(model.Name)]) then
						tried[model] = true
						if not waitForNoHunt(generation) then return false end
						phase(("Placing %s %d/3"):format(wanted, placed + 1))
						if placeTool(wanted, model, generation) then
							controller.UsedDoorModels[model] = true
							controller.UsedDoorNames[normalize(model.Name)] = true
							placed += 1
							controller.DoorPlacements[key] = placed
						end
					end
				end
				if placed >= 3 then break end
			end
			if placed >= 3 then
				controller.CompletedDoorTools[key] = true
			elseif placed == beforePlaced then
				controller.DoorRetryPasses[key] = (controller.DoorRetryPasses[key] or 0) + 1
				if controller.DoorRetryPasses[key] >= 3 then
					controller.CompletedDoorTools[key] = true
				else
					complete = false
				end
			else
				controller.DoorRetryPasses[key] = 0
				complete = false
			end
			if controller.CompletedDoorTools[key] then
				local stored = findStoredItem(wanted, true)
				local slot = stored and hotbarSlot(wanted, stored)
				if slot then remoteFor(generation, "RequestItemDrop", "InvSlot" .. slot) end
			end
		end
		return complete or controller.CompletedDoorTools["saltcanister"]
			and controller.CompletedDoorTools["holyoil"]
	end

	local function markRoundStarted()
		controller.RoundStartedAt = roundStartTime() or controller.RoundStartedAt or clock()
		render()
	end

	local function defaultOpenExit(generation)
		if timedOut() then return false end
		if roundStarted and roundStarted.Started then
			markRoundStarted()
			return true
		end
		local exits = select(1, resolveExitDoors())
		if #exits == 0 then return false end
		for _, model in ipairs(exits) do
			if timedOut() or not alive(generation) then return false end
			local container, reference = doorReference(model)
			local state, deadline = doorClosed(model, container), clock() + 1
			while state == nil and clock() < deadline do
				if not pause(generation, 0.05) then return false end
				container, reference = doorReference(model)
				state = doorClosed(model, container)
			end
			if state == false then
				markRoundStarted()
				return true
			end
			if state == true and reference then
				local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
				local moved = root and (root.Position - reference.Position).Magnitude <= 10
				if not moved then moved = teleportNearObject(reference, 9.25, generation) end
				if not moved then
					for _, approach in ipairs(doorApproaches(reference)) do
						if teleportToDoorFace(reference, approach, generation) then
							moved = true
							break
						end
					end
				end
				root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
				if moved and root and (root.Position - reference.Position).Magnitude <= 10
					and pause(generation, REMOTE_DELAY) then
					container, reference = doorReference(model)
					state = doorClosed(model, container)
					if state == false then
						markRoundStarted()
						return true
					end
					local changeDoor = getRemote("ClientChangeDoorState")
					if state == true and changeDoor and pcall(changeDoor, container) then
						local openDeadline = clock() + 2
						repeat
							if doorClosed(model, container) == false then
								markRoundStarted()
								return true
							end
							if timedOut() or not pause(generation, 0.05) then return false end
						until clock() >= openDeadline
					end
				end
			end
		end
		return false
	end

	local placeRoomItems = dependencies.PlaceRoomItems or defaultPlaceRoomItems
	local placeDoorTools = dependencies.PlaceDoorTools or defaultPlaceDoorTools
	local openExitDoor = dependencies.OpenExitDoor or defaultOpenExit

	local function releaseMovement()
		releaseFacingLocks()
		local character = Player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then return end
		pcall(function()
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			humanoid.Sit = false
			humanoid.PlatformStand = false
			humanoid.AutoRotate = true
			for _, state in ipairs({
				Enum.HumanoidStateType.FallingDown,
				Enum.HumanoidStateType.Ragdoll,
				Enum.HumanoidStateType.Freefall,
			}) do humanoid:SetStateEnabled(state, true) end
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end)
	end

	local function waitBaseCampSettle(generation)
		releaseMovement()
		local stableSince
		while alive(generation) do
			local character = Player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local stable = playerAtBaseCamp()
				and (not root or root.Anchored == false)
				and (not humanoid or humanoid.Health > 0)
			if stable then
				stableSince = stableSince or clock()
				if clock() - stableSince >= 1.25 then return true end
			else
				stableSince = nil
			end
			if not pause(generation, 0.05) then return false end
		end
		return false
	end

	local function finish(generation, name)
		if not name or not alive(generation) then return end
		phase("Selecting " .. name)
		if type(Verdict.ForceSelect) ~= "function" then
			phase("Ghost selection unavailable")
			return
		end
		local selected = false
		while alive(generation) and not selected do
			local ok, result = pcall(Verdict.ForceSelect, Verdict, name)
			selected = ok and result == true
			if not selected then
				phase("Retrying ghost selection")
				if not pause(generation, 0.5) then return end
			end
		end
		if not selected then return end
		if not pause(generation, 0.35) then return end
		phase("Returning to Base Camp")
		if escapeHunt and escapeHunt.SetEnabled then escapeHunt:SetEnabled(false) end
		local function returnToBaseCamp()
			local failedAttempts = 0
			while alive(generation) do
				local called, result = pcall(teleportBaseCamp)
				if called and result == true and waitBaseCampSettle(generation) then return true end
				failedAttempts += 1
				phase("Retrying Base Camp teleport")
				local retry = math.min(2, 0.25 * 2 ^ math.min(failedAttempts - 1, 3))
				if not pause(generation, retry) then return false end
			end
			return false
		end
		if not returnToBaseCamp() then return end
		local earliest = (roundStartTime() or controller.StartedAt) + 30
		while alive(generation) and clock() < earliest do
			phase("Waiting to leave")
			pause(generation, math.min(0.25, earliest - clock()))
		end
		while alive(generation) do
			phase("Returning to lobby")
			if not playerAtBaseCamp() then
				phase("Base Camp position changed; retrying")
				if not returnToBaseCamp() then return end
				continue
			end
			if type(prepareReturn) == "function" then pcall(prepareReturn) end
			if not pause(generation, REMOTE_DELAY) then break end
			if playerAtBaseCamp() then
				local requestReturn = getRemote("RequestReturnToLobby")
				if requestReturn then pcall(requestReturn) end
			end
			if not pause(generation, 4) then break end
		end
	end

	local function claimCompletion(generation, name)
		if not alive(generation) or controller.CompletionClaimed or not name then return false end
		controller.CompletionClaimed = true
		controller.Generation += 1
		local completionGeneration = controller.Generation
		releaseFacingLocks()
		task.spawn(function()
			task.wait(0.2)
			local ok, failure = xpcall(function() finish(completionGeneration, name) end, debug.traceback)
			if not ok and alive(completionGeneration) then
				controller.LastError = tostring(failure)
				local report = type(warn) == "function" and warn or print
				report(controller.LastError)
			end
		end)
		return true
	end

	local function startCompletionWatchdog(generation)
		if dependencies.Spawn ~= nil or not task or type(task.spawn) ~= "function" then return end
		task.spawn(function()
			while alive(generation) and not controller.CompletionClaimed do
				local high, name = identified()
				if high or timedOut() then
					name = high and name or select(1, bestGuess())
					claimCompletion(generation, name)
					return
				end
				task.wait(0.1)
			end
		end)
	end

	local function run(generation)
		local high, name = identified()
		if not high then
			while alive(generation) and not high and not timedOut() do
				phase("Checking Ghost Room and room items")
				if placeRoomItems(generation) == true then break end
				high, name = identified()
				if not high and not timedOut() then
					phase("Room item setup incomplete; retrying")
					if not pause(generation, 0.75) then return end
				end
			end
			high, name = identified()
		end
		if not high and alive(generation) and not timedOut() then
			while alive(generation) and not high and not timedOut() do
				phase("Placing door tools")
				if placeDoorTools(generation) == true then break end
				high, name = identified()
				if not high and not timedOut() then
					phase("Door tools incomplete; retrying")
					if not pause(generation, 0.75) then return end
				end
			end
			high, name = identified()
		end
		if not high and alive(generation) and not timedOut() then
			while alive(generation) and not high and not timedOut() do
				phase("Opening exit door")
				if not waitForNoHunt(generation) then break end
				if not alive(generation) then return end
				if timedOut() then break end
				if openExitDoor(generation) == true then
					markRoundStarted()
					break
				end
				high, name = identified()
				if not high and not timedOut() then
					phase("Exit door did not open; retrying")
					if not pause(generation, 0.75) then return end
				end
			end
		end
		local lastRoomCheck, lastMaintenance, lastPeriodicMaintenance = -math.huge, clock(), clock()
		while alive(generation) do
			high, name = identified()
			if high or timedOut() then break end
			local hunting = Ghost:GetAttribute("Hunting") == true
			phase(hunting and "Hunt escape" or "Observing ghost")
			if not hunting and clock() - lastRoomCheck >= 2 then
				lastRoomCheck = clock()
				local room = findRoom()
				local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
				local inRoom = false
				for _, box in ipairs(bounds(room)) do
					if root and insidePart(box, root.Position) then
						inRoom = true
						break
					end
				end
				if room and not inRoom then
					teleportInsideRoom(room, {
						RequireStrict = false,
						IsActive = function() return alive(generation) end,
					})
				end
			end
			if not hunting and clock() - lastMaintenance >= 1.25
				and (controller.ItemsDirty or clock() - lastPeriodicMaintenance >= 8) then
				lastMaintenance = clock()
				lastPeriodicMaintenance = clock()
				phase("Maintaining room items")
				if placeRoomItems(generation) ~= true then controller.ItemsDirty = true end
			end
			if not pause(generation, 0.25) then return end
		end
		if alive(generation) and not controller.CompletionClaimed then
			controller.CompletionClaimed = true
			name = select(1, bestGuess())
			finish(generation, name)
		end
	end

	function controller:SetEnabled(enabled)
		enabled = enabled == true
		if self.Enabled == enabled then return self.Enabled end
		self.Enabled = enabled
		self.Generation += 1
		if dependencies.OnEnabledChanged then dependencies.OnEnabledChanged(enabled) end
		if enabled then
			releaseFacingLocks()
			releaseConnections()
			self.StartedAt = clock()
			self.RoundStartedAt = roundStarted and tonumber(roundStarted.StartedAt) or nil
			self.DoorPlacements = {}
			self.UsedDoorModels = {}
			self.UsedDoorNames = {}
			self.CompletedDoorTools = {}
			self.MissingDoorTools = {}
			self.DoorRetryPasses = {}
			self.LastRoom = nil
			self.SetupComplete = false
			self.OutsideSince = {}
			self.RoomItemFailures = {}
			self.SkippedRoomItems = {}
			self.PowerFailures = {}
			self.ItemPower = setmetatable({}, {__mode = "k"})
			self.ItemsDirty = true
			self.CompletionClaimed = false
			self.Phase = "Starting"
			self.PreviousAutoSpirit = autoSpirit and autoSpirit.Enabled
			self.PreviousEscapeHunt = escapeHunt and escapeHunt.Enabled
			if autoSpirit and autoSpirit.SetEnabled then autoSpirit:SetEnabled(true) end
			if escapeHunt and escapeHunt.SetEnabled then escapeHunt:SetEnabled(true) end
			local items = type(World.FindFirstChild) == "function" and World:FindFirstChild("Items") or nil
			if items then
				for _, signal in ipairs({items.ChildAdded, items.ChildRemoved}) do
					table.insert(self.Connections, signal:Connect(function()
						self.ItemsDirty = true
						self.SkippedRoomItems = {}
					end))
				end
			end
			if Services.RunService and Services.RunService.Heartbeat then
				local lastRender = -math.huge
				table.insert(self.Connections, Services.RunService.Heartbeat:Connect(function()
					if self.Enabled and clock() - lastRender >= 0.25 then
						lastRender = clock()
						render()
					end
				end))
			end
			local generation = self.Generation
			spawn(function()
				local ok, failure = xpcall(function() run(generation) end, debug.traceback)
				if not ok and alive(generation) then
					self.LastError = tostring(failure)
					local report = type(warn) == "function" and warn or print
					report(self.LastError)
					self:SetEnabled(false)
					if button then button.Text = "AUTOMATION: OFF\nRuntime error" end
				end
			end)
			startCompletionWatchdog(generation)
		else
			releaseMovement()
			releaseConnections()
			if autoSpirit and autoSpirit.SetEnabled then autoSpirit:SetEnabled(self.PreviousAutoSpirit == true) end
			if escapeHunt and escapeHunt.SetEnabled then escapeHunt:SetEnabled(self.PreviousEscapeHunt == true) end
			self.Phase = "Ready"
		end
		render()
		return self.Enabled
	end

	function controller:Toggle()
		return self:SetEnabled(not self.Enabled)
	end

	function controller:Destroy()
		self:SetEnabled(false)
		if self.ButtonConnection then self.ButtonConnection:Disconnect() end
	end

	if button then
		controller.ButtonConnection = button.MouseButton1Click:Connect(function() controller:Toggle() end)
	end
	render()
	return controller
end
