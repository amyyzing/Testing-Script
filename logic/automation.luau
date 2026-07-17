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
	}

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

	local function pause(generation, seconds)
		local deadline = clock() + seconds
		repeat
			if not alive(generation) then return false end
			wait(math.min(0.1, math.max(0, deadline - clock())))
		until clock() >= deadline
		return alive(generation)
	end

	local function remote(name, ...)
		local ok, callable = pcall(function() return Remotes[name] end)
		if not ok or type(callable) ~= "function" then return false end
		ok = pcall(callable, ...)
		wait(0.1)
		return ok
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
		for _, object in ipairs(model:GetDescendants()) do
			if object:IsA("BasePart") then
				for _, box in ipairs(boxes) do
					if insidePart(box, object.Position) then return true end
				end
			end
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
		for _, box in ipairs(boxes) do
			local halfX = math.max(0, box.Size.X * 0.5 - 2)
			local halfZ = math.max(0, box.Size.Z * 0.5 - 2)
			for radius = 0, math.max(halfX, halfZ), 2 do
				for _, offset in ipairs(radius == 0 and {Vector2.zero} or {
					Vector2.new(radius, 0), Vector2.new(-radius, 0),
					Vector2.new(0, radius), Vector2.new(0, -radius),
				}) do
					if math.abs(offset.X) <= halfX and math.abs(offset.Y) <= halfZ then
						local center = box.CFrame:PointToWorldSpace(Vector3.new(offset.X, 0, offset.Y))
						local ray = World:Raycast(center + Vector3.new(0, box.Size.Y * 0.5, 0),
							Vector3.new(0, -box.Size.Y - 8, 0), rayParams)
						if ray then return ray.Position + Vector3.new(0, root.Size.Y * 0.5 + 0.3, 0) end
					end
				end
			end
		end
		return nil
	end

	local function worldItems()
		local folder = World:FindFirstChild("Items")
		return folder and folder:GetChildren() or {}
	end

	local function findWorldItem(wanted, room)
		for _, model in ipairs(worldItems()) do
			if normalize(itemName(model)) == normalize(wanted)
				and (not room or modelInsideRoom(model, room)) then return model end
		end
		return nil
	end

	local function findStoredItem(wanted)
		for _, container in ipairs({Player.Character, Player:FindFirstChild("ToolsHolder")}) do
			if container then
				for _, model in ipairs(container:GetChildren()) do
					if normalize(itemName(model)) == normalize(wanted) then return model end
				end
			end
		end
		return nil
	end

	local function hotbarSlot(wanted)
		local gui = Player:FindFirstChildOfClass("PlayerGui")
		local slots = gui and gui:FindFirstChild("Hotbar")
		slots = slots and slots:FindFirstChild("Slots")
		for number = 1, 3 do
			local slot = slots and slots:FindFirstChild("InvSlot" .. number)
			local label = slot and slot:FindFirstChild("ItemName")
			if label and normalize(label.Text) == normalize(wanted) then return number end
		end
		local stored = findStoredItem(wanted)
		return stored and tonumber(stored:GetAttribute("Slot") or stored:GetAttribute("SlotNumber")) or nil
	end

	local function acquire(wanted, generation)
		local stored = findStoredItem(wanted)
		if stored then return stored end
		local model = findWorldItem(wanted)
		local position = objectPosition(model)
		if not model or not position then return nil end
		if not alive(generation) or Ghost:GetAttribute("Hunting") == true then return nil end
		moveTo(position + Vector3.new(2, 2.5, 0), position)
		remote("RequestItemPickup", model)
		for _ = 1, 12 do
			stored = findStoredItem(wanted)
			if stored then return stored end
			if not pause(generation, 0.1) then break end
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

	local function defaultPlaceRoomItems(generation)
		local room = findRoom()
		if not room then return false end
		for _, wanted in ipairs(DROPPED_ITEMS) do
			if not alive(generation) or identified() then return false end
			while Ghost:GetAttribute("Hunting") == true do
				phase("Waiting for hunt to end")
				if not pause(generation, 0.25) then return false end
			end
			local placed = findWorldItem(wanted, room)
			if not placed then
				phase("Placing " .. wanted)
				local _, slot = equip(wanted, generation)
				local position = roomPosition(room)
				if slot and position and moveTo(position) then
					remote("RequestItemDrop", "InvSlot" .. slot)
					for _ = 1, 15 do
						placed = findWorldItem(wanted, room)
						if placed then break end
						if not pause(generation, 0.1) then return false end
					end
				end
			end
			if placed and POWERED_ITEMS[normalize(wanted)] and placed:GetAttribute("Enabled") ~= true then
				local position = objectPosition(placed)
				if position then moveTo(position + Vector3.new(2, 2.5, 0), position) end
				remote("ToggleItemState", placed)
			end
		end
		return true
	end

	local function doorReference(model)
		local container = model:FindFirstChild("Door") or model
		local reference = container:FindFirstChild("DoorUnion", true)
			or container:FindFirstChildWhichIsA("BasePart", true)
		return container, reference
	end

	local function doorClosed(model, container)
		local value = model:GetAttribute("DoorClosed")
		if value == nil then value = container:GetAttribute("DoorClosed") end
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
		if doorClosed(model, container) ~= false then return true end
		local moved = false
		for _, side in ipairs({1, -1}) do
			local position, center = doorPosition(reference, side)
			if positionOpen(position, model) and moveTo(position, center) then moved = true break end
		end
		if not moved then return false end
		remote("ClientChangeDoorState", container)
		for _ = 1, 12 do
			if doorClosed(model, container) ~= false then return true end
			if not pause(generation, 0.1) then return false end
		end
		return false
	end

	local function placementCount(folderName)
		local folder = World:FindFirstChild(folderName)
		return folder and #folder:GetChildren() or 0
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
		if distance > 3 then return false end
		if preview:IsA("BasePart") then
			local previewWide = preview.Size.X >= preview.Size.Z and preview.CFrame.RightVector or preview.CFrame.LookVector
			local doorWide = reference.Size.X >= reference.Size.Z and reference.CFrame.RightVector or reference.CFrame.LookVector
			return math.abs(previewWide:Dot(doorWide)) >= 0.9
		end
		return true
	end

	local function placeTool(wanted, model, generation)
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
				pause(generation, 0.2)
				moveTo(position, center)
				local camera = World.CurrentCamera
				if camera then camera.CFrame = CFrame.lookAt(camera.CFrame.Position, center) end
				pause(generation, 0.2)
				if previewReady(wanted, reference, root) then positioned = true break end
			end
		end
		if not positioned then return false end
		local folder = wanted == "Salt Canister" and "SaltPiles" or "HolyOil"
		local beforeCount = placementCount(folder)
		local beforeUses = tonumber(tool:GetAttribute("Uses"))
		local fired = remote("UseItem")
		for attempt = 1, 15 do
			local afterUses = tonumber(tool:GetAttribute("Uses"))
			if placementCount(folder) > beforeCount
				or beforeUses and afterUses and afterUses < beforeUses then return true end
			if attempt == 6 and fired then
				remote(wanted == "Salt Canister" and "LaySaltPile" or "PourHolyOil")
			end
			if not pause(generation, 0.1) then return false end
		end
		return false
	end

	local function defaultPlaceDoorTools(generation)
		local room = findRoom()
		local doors = World:FindFirstChild("Doors")
		if not room or not doors then return false end
		local center = objectPosition(room) or (bounds(room)[1] and bounds(room)[1].Position)
		local candidates = {}
		for _, model in ipairs(doors:GetChildren()) do
			local _, reference = doorReference(model)
			if normalize(model.Name) ~= "exitdoor" and reference then table.insert(candidates, model) end
		end
		table.sort(candidates, function(a, b)
			local _, ar = doorReference(a)
			local _, br = doorReference(b)
			return center and (ar.Position - center).Magnitude < (br.Position - center).Magnitude
				or a.Name < b.Name
		end)
		local used, usedNames = {}, {}
		for _, wanted in ipairs({"Salt Canister", "Holy Oil"}) do
			local placed = 0
			local tried = {}
			while Ghost:GetAttribute("Hunting") == true do
				phase("Waiting for hunt to end")
				if not pause(generation, 0.25) then return false end
			end
			if not acquire(wanted, generation) then
				phase(wanted .. " unavailable")
				continue
			end
			for namePass = 1, 2 do
				for _, model in ipairs(candidates) do
					if placed >= 3 then break end
					if not alive(generation) or identified() then return false end
					if not used[model] and not tried[model]
						and (namePass == 2 or not usedNames[normalize(model.Name)]) then
						tried[model] = true
						while Ghost:GetAttribute("Hunting") == true do
							phase("Waiting for hunt to end")
							if not pause(generation, 0.25) then return false end
						end
						phase(("Placing %s %d/3"):format(wanted, placed + 1))
						if placeTool(wanted, model, generation) then
							used[model], usedNames[normalize(model.Name)] = true, true
							placed += 1
						end
					end
				end
				if placed >= 3 then break end
			end
		end
		return true
	end

	local function defaultOpenExit(generation)
		if roundStarted and roundStarted.Started then return true end
		local doors = World:FindFirstChild("Doors")
		if not doors then return false end
		for _, model in ipairs(doors:GetChildren()) do
			if normalize(model.Name) == "exitdoor" then
				local container, reference = doorReference(model)
				if doorClosed(model, container) == false then return true end
				if reference then
					local position, center = doorPosition(reference, 1)
					moveTo(position, center)
					for _ = 1, 3 do
						if doorClosed(model, container) == false then return true end
						remote("ClientChangeDoorState", container)
						if not pause(generation, 0.35) then return false end
					end
				end
			end
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
		pause(generation, 0.35)
		phase("Returning to Base Camp")
		if type(teleportBaseCamp) == "function" then pcall(teleportBaseCamp) end
		local earliest = roundStarted and roundStarted.StartedAt
		earliest = (tonumber(earliest) or controller.StartedAt) + 30
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
			phase("Checking Ghost Room")
			if not dependencies.PlaceRoomItems and not findRoom() then phase("Ghost Room unavailable") end
			if alive(generation) then placeRoomItems(generation) end
			high, name = identified()
		end
		if not high and alive(generation) then
			phase("Placing door tools")
			placeDoorTools(generation)
			high, name = identified()
		end
		if not high and alive(generation) then
			phase("Opening exit door")
			while Ghost:GetAttribute("Hunting") == true and alive(generation) do
				phase("Waiting for hunt to end")
				pause(generation, 0.25)
			end
			openExitDoor(generation)
		end
		local lastRoomCheck = -math.huge
		while alive(generation) do
			high, name = identified()
			local reference = roundStarted and roundStarted.StartedAt or controller.StartedAt
			if high or clock() - (tonumber(reference) or controller.StartedAt) >= timeoutSeconds then break end
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
		if enabled then
			self.StartedAt = clock()
			self.Phase = "Starting"
			self.PreviousAutoSpirit = autoSpirit and autoSpirit.Enabled
			self.PreviousEscapeHunt = escapeHunt and escapeHunt.Enabled
			if autoSpirit and autoSpirit.SetEnabled then autoSpirit:SetEnabled(true) end
			if escapeHunt and escapeHunt.SetEnabled then escapeHunt:SetEnabled(true) end
			local generation = self.Generation
			spawn(function() run(generation) end)
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
