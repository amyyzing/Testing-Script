return function(dependencies)
	local ghost = assert(dependencies.Ghost, "ghost-room-billboard requires Ghost")
	local world = dependencies.Workspace or workspace
	local guiParent = assert(dependencies.GuiParent, "ghost-room-billboard requires GuiParent")
	local runService = dependencies.RunService
	local accent = dependencies.Accent or Color3.fromRGB(77, 105, 209)
	local controller = {}

	local function new(className, properties)
		local object = Instance.new(className)
		for property, value in pairs(properties) do object[property] = value end
		return object
	end

	local function findRoom(roomName)
		if not roomName then return nil end
		local map = world:FindFirstChild("Map")
		local rooms = map and map:FindFirstChild("Rooms")
		if not rooms then return nil end
		local direct = rooms:FindFirstChild(tostring(roomName))
		if direct then return direct end
		local wanted = string.lower(tostring(roomName))
		for _, room in ipairs(rooms:GetChildren()) do
			if string.lower(room.Name) == wanted then return room end
		end
		return nil
	end

	local function findTarget(room)
		if not room then return nil end
		local candidates = {}
		local direct = room:FindFirstChild("BoundingBox")
		if direct then table.insert(candidates, direct) end
		for _, descendant in ipairs(room:GetDescendants()) do
			if descendant.Name == "BoundingBox" and descendant ~= direct then
				table.insert(candidates, descendant)
			end
		end
		for _, boundingBox in ipairs(candidates) do
			if boundingBox:IsA("BasePart") then return boundingBox end
			for _, child in ipairs(boundingBox:GetChildren()) do
				if child:IsA("BasePart") and child.Name == "Part" then return child end
			end
			for _, child in ipairs(boundingBox:GetChildren()) do
				if child:IsA("BasePart") then return child end
			end
			local nested = boundingBox:FindFirstChildWhichIsA("BasePart", true)
			if nested then return nested end
		end
		return nil
	end

	local function destroyVisual()
		if controller.Billboard then controller.Billboard:Destroy() end
		controller.Billboard, controller.Label, controller.Target = nil, nil, nil
	end

	function controller:Refresh()
		local room = findRoom(ghost:GetAttribute("FavoriteRoom"))
		local target = findTarget(room)
		if not target then
			destroyVisual()
			return false
		end
		if self.Billboard and self.Target == target and self.Billboard.Adornee == target then
			if self.Label then self.Label.Text = room.Name end
			return true
		end
		destroyVisual()
		self.Target = target
		if dependencies.VisualFactory then
			self.Billboard, self.Label = dependencies.VisualFactory(target, room.Name)
			return self.Billboard ~= nil
		end
		self.Billboard = new("BillboardGui", {
			Name = "UntitledFavouriteRoomBillboard",
			Parent = guiParent,
			Adornee = target,
			AlwaysOnTop = true,
			LightInfluence = 0,
			Size = UDim2.fromOffset(170, 28),
			Enabled = true,
			StudsOffset = Vector3.new(0, 0, 0),
		})
		self.Label = new("TextLabel", {
			Parent = self.Billboard,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = room.Name,
			TextColor3 = accent,
			TextStrokeColor3 = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.2,
			TextScaled = true,
		})
		return true
	end

	function controller:Destroy()
		destroyVisual()
		if self.RoomConnection then self.RoomConnection:Disconnect() end
		if self.RefreshConnection then self.RefreshConnection:Disconnect() end
	end

	controller.RoomConnection = ghost:GetAttributeChangedSignal("FavoriteRoom"):Connect(function()
		controller:Refresh()
	end)
	if runService then
		local elapsed = 0
		controller.RefreshConnection = runService.Heartbeat:Connect(function(delta)
			elapsed += math.max(0, tonumber(delta) or 0)
			if elapsed < 0.5 then return end
			elapsed = 0
			controller:Refresh()
		end)
	end
	controller:Refresh()
	return controller
end
