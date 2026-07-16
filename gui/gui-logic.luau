local GuiLogic = {}

local function viewportSize()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1920, 1080)
end

function GuiLogic.new(dependencies)
	local services = assert(dependencies.Services, "gui-logic requires Services")
	local view = assert(dependencies.View, "gui-logic requires View")
	local inputService = assert(services.UserInputService, "gui-logic requires UserInputService")
	local presenter = {Connections = {}, View = view}
	local dragging, resizing = false, false
	local dragInput, dragStart, positionStart
	local resizeInput, resizeStart, sizeStart
	local function isMovement(input, startedWith)
		return startedWith and (
			(startedWith.UserInputType == Enum.UserInputType.Touch and input == startedWith)
			or (startedWith.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement)
		)
	end

	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(presenter.Connections, connection)
		return connection
	end

	connect(view.CloseButton.MouseButton1Click, function()
		view.Main.Visible = false
		view.OpenButton.Visible = true
	end)

	connect(view.OpenButton.MouseButton1Click, function()
		view.Main.Visible = true
		view.OpenButton.Visible = false
	end)

	connect(view.TitleBar.InputBegan, function(input)
		if resizing or (input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch) then return end
		dragging = true
		dragInput = input
		dragStart = input.Position
		positionStart = view.Main.AbsolutePosition
	end)

	connect(view.ResizeHandle.InputBegan, function(input)
		if dragging or (input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch) then return end
		resizing = true
		resizeInput = input
		resizeStart = input.Position
		sizeStart = view.Main.AbsoluteSize
	end)

	connect(inputService.InputChanged, function(input)
		if dragging and isMovement(input, dragInput) then
			local delta = input.Position - dragStart
			local viewport = viewportSize()
			local x = math.clamp(positionStart.X + delta.X, 0, math.max(0, viewport.X - 40))
			local y = math.clamp(positionStart.Y + delta.Y, 0, math.max(0, viewport.Y - 34))
			view.Main.Position = UDim2.fromOffset(x, y)
		elseif resizing and isMovement(input, resizeInput) then
			local delta = input.Position - resizeStart
			local viewport = viewportSize()
			local position = view.Main.AbsolutePosition
			local maxWidth = math.max(260, viewport.X - position.X)
			local maxHeight = math.max(180, viewport.Y - position.Y)
			view.Main.Size = UDim2.fromOffset(
				math.clamp(sizeStart.X + delta.X, 260, maxWidth),
				math.clamp(sizeStart.Y + delta.Y, 180, maxHeight)
			)
		end
	end)

	connect(inputService.InputEnded, function(input)
		if input == dragInput then dragging, dragInput = false, nil end
		if input == resizeInput then resizing, resizeInput = false, nil end
	end)

	function presenter:Bind()
		-- Feature controls are intentionally owned by modules under /logic.
	end

	function presenter:Destroy()
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
	end

	return presenter
end

return GuiLogic
