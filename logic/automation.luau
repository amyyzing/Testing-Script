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

	local function fireRemote(callable, ...)
		if not callable then return false end
		local ok = pcall(callable, ...)
		wait(0.1)
		return ok
	end

	local function remote(name, ...)
		return fireRemote(getRemote(name), ...)
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

	local function bounds(room)
		local result = {}
		if not room then return result end
		if room:IsA("BasePart") and room.Name == "BoundingBox" then table.insert(result, room) end
		for _, object in ipairs(room:GetDescendants()) do
			if object:IsA("BasePart") then
				local parent = object
				while parent and parent ~= room and parent.Name ~= "BoundingBox" do parent = parent.Parent end
				if object.Name == "BoundingBox" or parent and parent.Name == "BoundingBox" then
					table.insert(result, object)
				end
			end
		end
		return result
	end

	local function insidePart(part, position)
		local point = part.CFrame:PointToObjectSpace(position)
		local half = part.Size * 0.5
		return math.abs(point.X) <= half.X + 0.75
			and math.abs(point.Y) <= half.Y + 0.75
			and math.abs(point.Z) <= half.Z + 0.75
	end

	local function modelInsideRoom(model, room)
		local boxes = bounds(room)
		local objects = model:IsA("BasePart") and {model} or model:GetDescendants()
		for _, object in ipairs(objects) do
			if object:IsA("BasePart") then
				for _, box in ipairs(boxes) do
					if insidePart(box, object.Position) then return true end
				end
			end
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
		return World:FindFirstChild("Base Camp") or World:FindFirstChild("BaseCamp")
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

	local function roomPosition(room)
		local character = Player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return nil end
		local boxes = bounds(room)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character, table.unpack(boxes)}
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = {character, table.unpack(boxes)}
		local fallback
		for _, box in ipairs(boxes) do
			local halfX = math.max(0, box.Size.X * 0.5 - 2)
			local halfZ = math.max(0, box.Size.Z * 0.5 - 2)
			for radius = 0, math.max(halfX, halfZ), 2 do
				for _, offset in ipairs(radius == 0 and {Vector2.zero} or {
					Vector2.new(radius, 0), Vector2.new(-radius, 0),
					Vector2.new(0, radius), Vector2.new(0, -radius),
					Vector2.new(radius, radius), Vector2.new(radius, -radius),
					Vector2.new(-radius, radius), Vector2.new(-radius, -radius),
				}) do
					if math.abs(offset.X) <= halfX and math.abs(offset.Y) <= halfZ then
						local center = box.CFrame:PointToWorldSpace(Vector3.new(offset.X, 0, offset.Y))
						local ray = World:Raycast(center + Vector3.new(0, box.Size.Y * 0.5, 0),
							Vector3.new(0, -box.Size.Y - 8, 0), rayParams)
						if ray then
							local position = ray.Position + Vector3.new(0, root.Size.Y * 0.5 + 0.3, 0)
							fallback = fallback or position
							local blocked = false
							for _, part in ipairs(World:GetPartBoundsInBox(
								CFrame.new(position), root.Size + Vector3.new(0.5, 0.1, 0.5), overlapParams
							)) do
								if part ~= ray.Instance and part.CanCollide then blocked = true break end
							end
							if not blocked then return position end
						end
					end
				end
			end
		end
		return fallback
	end

	local function nearbyPosition(origin, maximumDistance)
		local character = Player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not origin then return nil end
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character}
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = {character}
		local fallback
		for radius = 2, maximumDistance, 2 do
			local diagonal = radius / math.sqrt(2)
			for _, offset in ipairs({
				Vector2.new(radius, 0), Vector2.new(-radius, 0),
				Vector2.new(0, radius), Vector2.new(0, -radius),
				Vector2.new(diagonal, diagonal), Vector2.new(diagonal, -diagonal),
				Vector2.new(-diagonal, diagonal), Vector2.new(-diagonal, -diagonal),
			}) do
				local flat = origin + Vector3.new(offset.X, 0, offset.Y)
				local ray = World:Raycast(flat + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), rayParams)
				if ray then
					local position = ray.Position + Vector3.new(0, root.Size.Y * 0.5 + 0.3, 0)
					fallback = fallback or position
					local blocked = false
					for _, part in ipairs(World:GetPartBoundsInBox(
						CFrame.new(position), root.Size + Vector3.new(0.5, 0.1, 0.5), overlapParams
					)) do
						if part ~= ray.Instance and part.CanCollide then blocked = true break end
					end
					if not blocked then return position end
				end
			end
		end
		return fallback
	end

	local function worldItems()
		local folder = World:FindFirstChild("Items")
		return folder and folder:GetChildren() or {}
	end

	local function findWorldItem(wanted, room)
		for _, model in ipairs(worldItems()) do
			if normalize(itemName(model)) == normalize(wanted)
				and not burntCross(model) and not itemDepleted(model)
				and (not room or modelInsideRoom(model, room)) then return model end
		end
		return nil
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

	local function acquire(wanted, generation)
		local stored = findStoredItem(wanted)
		if stored then return stored end
		local depleted = findStoredItem(wanted, true)
		if depleted and itemDepleted(depleted) then
			local slot = hotbarSlot(wanted, depleted)
			if slot then remote("RequestItemDrop", "InvSlot" .. slot) pause(generation, 0.2) end
		end
		local model = findWorldItem(wanted)
		local position = objectPosition(model)
		if not model or not position then return nil end
		if not alive(generation) or Ghost:GetAttribute("Hunting") == true then return nil end
		local target = nearbyPosition(position, 8)
		if not target or not moveTo(target, position) then return nil end
		remote("RequestItemPickup", model)
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
		remote("RequestItemEquip", "InvSlot" .. slot)
		pause(generation, 0.2)
		return findStoredItem(wanted), slot
	end

	local function ensurePowered(model, generation)
		if model:GetAttribute("Enabled") == true then return true end
		local changes = 0
		local connection = model:GetAttributeChangedSignal("Enabled"):Connect(function()
			changes += 1
		end)
		local waited = pause(generation, 2)
		connection:Disconnect()
		if not waited or timedOut() or Ghost:GetAttribute("Hunting") == true then return false end
		if model:GetAttribute("Enabled") == true or changes >= 2 then return true end
		local position = objectPosition(model)
		local target = nearbyPosition(position, 8)
		if not target or not moveTo(target, position) then return false end
		return remote("ToggleItemState", model)
	end

	local function defaultPlaceRoomItems(generation)
		local room = findRoom()
		if not room then return false end
		local complete = true
		for _, wanted in ipairs(DROPPED_ITEMS) do
			if not alive(generation) or identified() or timedOut() then return false end
			while Ghost:GetAttribute("Hunting") == true do
				phase("Waiting for hunt to end")
				if timedOut() or not pause(generation, 0.25) then return false end
			end
			local placed = findWorldItem(wanted, room)
			if not placed then
				phase("Placing " .. wanted)
				local _, slot = equip(wanted, generation)
				local position = roomPosition(room)
				if slot and position and moveTo(position) then
					if Ghost:GetAttribute("Hunting") == true then return false end
					remote("RequestItemDrop", "InvSlot" .. slot)
					for _ = 1, 15 do
						placed = findWorldItem(wanted, room)
						if placed then break end
						if timedOut() or not pause(generation, 0.1) then return false end
					end
				end
			end
			if not placed then complete = false end
			if placed and POWERED_ITEMS[normalize(wanted)] and placed:GetAttribute("Enabled") ~= true then
				if not ensurePowered(placed, generation) then complete = false end
			end
		end
		return complete
	end

	local function doorReference(model)
		local container = model:FindFirstChild("Door") or model
		local union = container:FindFirstChild("DoorUnion", true)
		local reference = container:IsA("BasePart") and container
			or union and union:IsA("BasePart") and union
			or container:FindFirstChildWhichIsA("BasePart", true)
		return container, reference
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

	local function doorClosed(model, container)
		local value = model:GetAttribute("DoorClosed")
		if value == nil then value = container:GetAttribute("DoorClosed") end
		if value == nil then
			for _, object in ipairs(model:GetDescendants()) do
				value = object:GetAttribute("DoorClosed")
				if value ~= nil then break end
			end
		end
		return value
	end

	local function doorPosition(reference, side)
		local wideIsX = reference.Size.X >= reference.Size.Z
		local normal = wideIsX and reference.CFrame.LookVector or reference.CFrame.RightVector
		normal = Vector3.new(normal.X, 0, normal.Z).Unit * side
		local center = reference.Position
		return Vector3.new(center.X, center.Y - reference.Size.Y * 0.5 + 3, center.Z)
			+ normal * 1.75, center
	end

	local function positionOpen(position, doorModel)
		local character = Player.Character
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = {character, doorModel}
		for _, part in ipairs(World:GetPartBoundsInBox(CFrame.new(position), Vector3.new(2, 5, 2), params)) do
			if part.CanCollide then return false end
		end
		return true
	end

	local function closeDoor(model, container, reference, generation)
		if timedOut() then return false end
		local state = doorClosed(model, container)
		if state == true then return true end
		if state ~= false then return false end
		local moved = false
		for _, side in ipairs({1, -1}) do
			local position, center = doorPosition(reference, side)
			if positionOpen(position, model) and moveTo(position, center) then moved = true break end
		end
		if not moved then return false end
		for _ = 1, 3 do
			container, reference = doorReference(model)
			if doorClosed(model, container) == true then return true end
			remote("ClientChangeDoorState", container)
			for _ = 1, 6 do
				if doorClosed(model, container) == true then return true end
				if timedOut() or not pause(generation, 0.1) then return false end
			end
		end
		return false
	end

	local function placementSnapshot(folderName)
		local folder = World:FindFirstChild(folderName)
		local snapshot = {}
		if folder then
			for _, object in ipairs(folder:GetDescendants()) do snapshot[object] = true end
		end
		return snapshot
	end

	local function newValidPlacement(folderName, before, root)
		local folder = World:FindFirstChild(folderName)
		if not folder then return nil end
		for _, object in ipairs(folder:GetDescendants()) do
			if not before[object] and (object:IsA("Model") or object:IsA("BasePart")) then
				local placement = object
				while placement.Parent and placement.Parent ~= folder do placement = placement.Parent end
				local position = objectPosition(placement)
				if position then
					local distance = (Vector3.new(position.X, 0, position.Z)
						- Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
					local params = RaycastParams.new()
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = {placement, Player.Character}
					local floor = World:Raycast(position + Vector3.new(0, 1, 0), Vector3.new(0, -6, 0), params)
					if distance <= 2.75 and floor and modelInsideAnyRoom(placement) then return placement end
				end
			end
		end
		return nil
	end

	local function previewReady(wanted, reference, root)
		local camera = World.CurrentCamera
		local preview = wanted == "Salt Canister"
			and camera and camera:FindFirstChild("SaltLine")
			or camera and camera:FindFirstChild("HolyOil")
		preview = preview and (preview:FindFirstChild(wanted == "Salt Canister" and "Salt" or "Center", true) or preview)
		local position = objectPosition(preview)
		if not position then return true end
		local distance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
		if distance > 2 then return false end
		if preview:IsA("BasePart") then
			local previewWide = preview.Size.X >= preview.Size.Z and preview.CFrame.RightVector or preview.CFrame.LookVector
			local doorWide = reference.Size.X >= reference.Size.Z and reference.CFrame.RightVector or reference.CFrame.LookVector
			return math.abs(previewWide:Dot(doorWide)) >= 0.9
		end
		return true
	end

	local function placeTool(wanted, model, generation)
		if timedOut() then return false end
		local useItem = getRemote("UseItem")
		local fallback = getRemote(wanted == "Salt Canister" and "LaySaltPile" or "PourHolyOil")
		if not useItem and not fallback then return false end
		local tool = equip(wanted, generation)
		if not tool then return false end
		local uses = tonumber(tool:GetAttribute("Uses"))
		if uses ~= nil and uses <= 0 then return false end
		local container, reference = doorReference(model)
		if not reference or not closeDoor(model, container, reference, generation) then return false end
		container, reference = doorReference(model)
		local character = Player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return false end
		local positioned = false
		for _, side in ipairs({1, -1}) do
			local position, center = doorPosition(reference, side)
			if positionOpen(position, model) and moveTo(position, center) then
				if timedOut() or not pause(generation, 0.35) then return false end
				moveTo(position, center)
				local camera = World.CurrentCamera
				if camera then camera.CFrame = CFrame.lookAt(camera.CFrame.Position, center) end
				if timedOut() or not pause(generation, 0.35) then return false end
				if previewReady(wanted, reference, root) then positioned = true break end
			end
		end
		if not positioned then return false end
		if Ghost:GetAttribute("Hunting") == true then return false end
		local folder = wanted == "Salt Canister" and "SaltPiles" or "HolyOil"
		local before = placementSnapshot(folder)
		local fired = fireRemote(useItem)
		for attempt = 1, 15 do
			if newValidPlacement(folder, before, root) then return true end
			if attempt == 6 and not fired then
				fireRemote(fallback)
			end
			if timedOut() or not pause(generation, 0.1) then return false end
		end
		return false
	end

	local function defaultPlaceDoorTools(generation)
		local room = findRoom()
		local doors = World:FindFirstChild("Doors")
		if not room or not doors then return false end
		local roomBounds = bounds(room)
		local candidates, candidateOrder = {}, {}
		for index, model in ipairs(doors:GetChildren()) do
			local _, reference = doorReference(model)
			if not isExitDoor(model) and reference then
				table.insert(candidates, model)
				candidateOrder[model] = index
			end
		end
		local function distanceToRoom(model)
			local _, reference = doorReference(model)
			local best
			for _, box in ipairs(roomBounds) do
				local distance = (reference.Position - box.Position).Magnitude
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
		local complete = true
		for _, wanted in ipairs({"Salt Canister", "Holy Oil"}) do
			local key = normalize(wanted)
			local placed = controller.DoorPlacements[key] or 0
			local tried = {}
			if placed >= 3 then continue end
			while Ghost:GetAttribute("Hunting") == true do
				phase("Waiting for hunt to end")
				if timedOut() or not pause(generation, 0.25) then return false end
			end
			if not acquire(wanted, generation) then
				phase(wanted .. " unavailable")
				complete = false
				continue
			end
			for namePass = 1, 2 do
				for _, model in ipairs(candidates) do
					if placed >= 3 then break end
					if not alive(generation) or identified() or timedOut() then return false end
					if not controller.UsedDoorModels[model] and not tried[model]
						and (namePass == 2 or not controller.UsedDoorNames[normalize(model.Name)]) then
						tried[model] = true
						while Ghost:GetAttribute("Hunting") == true do
							phase("Waiting for hunt to end")
							if timedOut() or not pause(generation, 0.25) then return false end
						end
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
			if placed < 3 then complete = false end
		end
		return complete
	end

	local function markRoundStarted()
		controller.RoundStartedAt = roundStartTime() or controller.RoundStartedAt or clock()
		render()
	end

	local function defaultOpenExit(generation)
		if timedOut() then return false end
		if roundStarted and roundStarted.Started then markRoundStarted() return true end
		local doors = World:FindFirstChild("Doors")
		if not doors then return false end
		for _ = 1, 3 do
			for _, model in ipairs(doors:GetChildren()) do
				if timedOut() then return false end
				if isExitDoor(model) then
					local container, reference = doorReference(model)
					if doorClosed(model, container) == false then markRoundStarted() return true end
					if reference then
						local moved, fallback
						for _, side in ipairs({1, -1}) do
							local position, center = doorPosition(reference, side)
							fallback = fallback or {position, center}
							if positionOpen(position, model) and moveTo(position, center) then
								moved = true
								break
							end
						end
						if not moved and fallback then moved = moveTo(fallback[1], fallback[2]) end
						if moved then
							local root = Player.Character
								and Player.Character:FindFirstChild("HumanoidRootPart")
							if root and (root.Position - reference.Position).Magnitude <= 10 then
								for _ = 1, 3 do
									container, reference = doorReference(model)
									if doorClosed(model, container) == false then
										markRoundStarted()
										return true
									end
									remote("ClientChangeDoorState", container)
									if not pause(generation, 0.35) then return false end
								end
							end
						end
					end
				end
			end
			if not pause(generation, 0.35) then return false end
		end
		return false
	end

	local placeRoomItems = dependencies.PlaceRoomItems or defaultPlaceRoomItems
	local placeDoorTools = dependencies.PlaceDoorTools or defaultPlaceDoorTools
	local openExitDoor = dependencies.OpenExitDoor or defaultOpenExit

	local function finish(generation, name)
		if not name or not alive(generation) then return end
		phase("Selecting " .. name)
		if type(Verdict.ForceSelect) ~= "function" or not Verdict:ForceSelect(name) then
			phase("Ghost selection failed")
			return
		end
		if not pause(generation, 0.35) then return end
		phase("Returning to Base Camp")
		if escapeHunt and escapeHunt.SetEnabled then escapeHunt:SetEnabled(false) end
		local atBaseCamp = false
		while alive(generation) and not atBaseCamp do
			local called, result = pcall(teleportBaseCamp)
			if called and result == true and pause(generation, 1.25) then
				atBaseCamp = playerAtBaseCamp()
			end
			if not atBaseCamp then
				phase("Retrying Base Camp teleport")
				if not pause(generation, 0.5) then return end
			end
		end
		if not atBaseCamp then return end
		if type(prepareReturn) == "function" then pcall(prepareReturn) end
		local earliest = (roundStartTime() or controller.StartedAt) + 30
		while alive(generation) and clock() < earliest do
			phase("Waiting to leave")
			pause(generation, math.min(0.25, earliest - clock()))
		end
		while alive(generation) do
			phase("Returning to lobby")
			remote("RequestReturnToLobby")
			if not pause(generation, 4) then break end
		end
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
				while Ghost:GetAttribute("Hunting") == true and alive(generation) do
					phase("Waiting for hunt to end")
					if timedOut() or not pause(generation, 0.25) then break end
				end
				if not alive(generation) then return end
				if timedOut() then break end
				if openExitDoor(generation) == true then markRoundStarted() break end
				high, name = identified()
				if not high and not timedOut() then
					phase("Exit door did not open; retrying")
					if not pause(generation, 0.75) then return end
				end
			end
		end
		local lastRoomCheck, lastMaintenance = -math.huge, clock()
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
					if root and insidePart(box, root.Position) then inRoom = true break end
				end
				if room and not inRoom then moveTo(roomPosition(room)) end
			end
			if not hunting and clock() - lastMaintenance >= 8 then
				lastMaintenance = clock()
				phase("Maintaining room items")
				placeRoomItems(generation)
			end
			if not pause(generation, 0.25) then return end
		end
		if alive(generation) then
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
			self.StartedAt = clock()
			self.RoundStartedAt = roundStarted and tonumber(roundStarted.StartedAt) or nil
			self.DoorPlacements = {}
			self.UsedDoorModels = {}
			self.UsedDoorNames = {}
			self.Phase = "Starting"
			self.PreviousAutoSpirit = autoSpirit and autoSpirit.Enabled
			self.PreviousEscapeHunt = escapeHunt and escapeHunt.Enabled
			if autoSpirit and autoSpirit.SetEnabled then autoSpirit:SetEnabled(true) end
			if escapeHunt and escapeHunt.SetEnabled then escapeHunt:SetEnabled(true) end
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
		else
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
