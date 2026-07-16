local GuiLogic = {}

local function viewportSize()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1920, 1080)
end

function GuiLogic.new(dependencies)
	local services = assert(dependencies.Services, "gui-logic requires Services")
	local view = assert(dependencies.View, "gui-logic requires View")
	local inputService = assert(services.UserInputService, "gui-logic requires UserInputService")
	local tweenService = assert(services.TweenService, "gui-logic requires TweenService")
	local onClose = dependencies.OnClose
	local presenter = {Connections = {}, View = view, Minimized = false, TweenToken = 0}
	local dragging, resizing = false, false
	local dragInput, dragStart, positionStart
	local resizeInput, resizeStart, sizeStart
	local savedPosition, savedSize

	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(presenter.Connections, connection)
		return connection
	end

	local function movement(input, startedWith)
		return startedWith and (
			(startedWith.UserInputType == Enum.UserInputType.Touch and input == startedWith)
			or (startedWith.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement)
		)
	end

	local function tweenTo(position, size)
		presenter.TweenToken += 1
		if presenter.Tween then presenter.Tween:Cancel() end
		presenter.Tween = tweenService:Create(
			view.Main,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Position = position, Size = size}
		)
		presenter.Tween:Play()
		return presenter.TweenToken
	end

	connect(view.CloseButton.MouseButton1Click, function()
		if type(onClose) == "function" then onClose() else view.Gui:Destroy() end
	end)

	connect(view.MinimizeButton.MouseButton1Click, function()
		if presenter.Minimized then return end
		presenter.Minimized = true
		savedPosition = UDim2.fromOffset(view.Main.AbsolutePosition.X, view.Main.AbsolutePosition.Y)
		savedSize = UDim2.fromOffset(view.Main.AbsoluteSize.X, view.Main.AbsoluteSize.Y)
		local token = tweenTo(UDim2.fromOffset(12, 12), UDim2.fromOffset(92, 32))
		task.delay(0.2, function()
			if presenter.Minimized and presenter.TweenToken == token and view.Gui.Parent then
				view.Main.Visible = false
				view.OpenButton.Visible = true
			end
		end)
	end)

	connect(view.OpenButton.MouseButton1Click, function()
		if not presenter.Minimized then return end
		presenter.Minimized = false
		view.OpenButton.Visible = false
		view.Main.Position = UDim2.fromOffset(12, 12)
		view.Main.Size = UDim2.fromOffset(92, 32)
		view.Main.Visible = true
		tweenTo(savedPosition or UDim2.fromOffset(120, 120), savedSize or UDim2.fromOffset(420, 360))
	end)

	connect(view.TitleBar.InputBegan, function(input)
		if presenter.Minimized or resizing or (input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch) then return end
		dragging, dragInput, dragStart = true, input, input.Position
		positionStart = view.Main.AbsolutePosition
	end)

	connect(view.ResizeHandle.InputBegan, function(input)
		if presenter.Minimized or dragging or (input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch) then return end
		resizing, resizeInput, resizeStart = true, input, input.Position
		sizeStart = view.Main.AbsoluteSize
	end)

	connect(inputService.InputChanged, function(input)
		if dragging and movement(input, dragInput) then
			local delta, viewport = input.Position - dragStart, viewportSize()
			view.Main.Position = UDim2.fromOffset(
				math.clamp(positionStart.X + delta.X, 0, math.max(0, viewport.X - 40)),
				math.clamp(positionStart.Y + delta.Y, 0, math.max(0, viewport.Y - 34))
			)
		elseif resizing and movement(input, resizeInput) then
			local delta, viewport = input.Position - resizeStart, viewportSize()
			local position = view.Main.AbsolutePosition
			view.Main.Size = UDim2.fromOffset(
				math.clamp(sizeStart.X + delta.X, 260, math.max(260, viewport.X - position.X)),
				math.clamp(sizeStart.Y + delta.Y, 180, math.max(180, viewport.Y - position.Y))
			)
		end
	end)

	connect(inputService.InputEnded, function(input)
		if input == dragInput then dragging, dragInput = false, nil end
		if input == resizeInput then resizing, resizeInput = false, nil end
	end)

	function presenter:Bind() end

	function presenter:Destroy()
		self.TweenToken += 1
		if self.Tween then self.Tween:Cancel() end
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
	end

	return presenter
end

return GuiLogic
