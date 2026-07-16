return function(dependencies)
	local ghost = assert(dependencies.Ghost, "ghost-esp requires Ghost")
	local runService = assert(dependencies.RunService, "ghost-esp requires RunService")
	local guiParent = assert(dependencies.GuiParent, "ghost-esp requires GuiParent")
	local button = dependencies.Button
	local red = dependencies.Red or Color3.fromRGB(210, 66, 82)
	local disabledColor = button and button.BackgroundColor3
	local enabledColor = dependencies.EnabledColor or disabledColor
	local controller = {Enabled = false, Adornments = {}}

	local function new(className, properties)
		local object = Instance.new(className)
		for property, value in pairs(properties) do object[property] = value end
		return object
	end

	local function render()
		if not button then return end
		button.Text = controller.Enabled and "GHOST ESP: ON" or "GHOST ESP: OFF"
		button.BackgroundColor3 = controller.Enabled and enabledColor or disabledColor
	end

	local function addAdornment(part)
		if controller.Adornments[part] or not part:IsA("BasePart") then return end
		controller.Adornments[part] = new("BoxHandleAdornment", {
			Name = "UntitledGhostPartAdornment",
			Parent = guiParent,
			Adornee = part,
			AlwaysOnTop = true,
			Color3 = red,
			Size = part.Size,
			Transparency = 0.65,
			ZIndex = 10,
		})
	end

	local function removeAdornment(part)
		local adornment = controller.Adornments[part]
		if adornment then adornment:Destroy() end
		controller.Adornments[part] = nil
	end

	local function destroyVisuals()
		if controller.TestVisual then controller.TestVisual:Destroy() end
		if controller.AddedConnection then controller.AddedConnection:Disconnect() end
		if controller.RemovingConnection then controller.RemovingConnection:Disconnect() end
		if controller.Billboard then controller.Billboard:Destroy() end
		if controller.DirectHighlight then controller.DirectHighlight:Destroy() end
		for part in pairs(controller.Adornments) do removeAdornment(part) end
		controller.TestVisual = nil
		controller.AddedConnection, controller.RemovingConnection = nil, nil
		controller.Billboard, controller.DirectHighlight = nil, nil
	end

	local function buildVisuals()
		destroyVisuals()
		if dependencies.VisualFactory then
			controller.TestVisual = dependencies.VisualFactory(ghost)
			return controller.TestVisual ~= nil
		end

		local ghostPart = ghost.PrimaryPart or ghost:FindFirstChildWhichIsA("BasePart", true)
		if not ghostPart then return false end
		controller.Billboard = new("BillboardGui", {
			Name = "UntitledGhostBillboard",
			Parent = guiParent,
			Adornee = ghostPart,
			AlwaysOnTop = true,
			LightInfluence = 0,
			Size = UDim2.fromOffset(90, 30),
			StudsOffset = Vector3.new(0, 3.2, 0),
			Enabled = true,
		})
		new("TextLabel", {
			Parent = controller.Billboard,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "GHOST",
			TextColor3 = red,
			TextStrokeColor3 = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.15,
			TextScaled = true,
		})
		controller.DirectHighlight = new("Highlight", {
			Name = "UntitledGhostDirectHighlight",
			Parent = ghost,
			Adornee = ghost,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			FillColor = red,
			FillTransparency = 0.78,
			OutlineColor = Color3.new(1, 1, 1),
			OutlineTransparency = 0,
			Enabled = true,
		})
		for _, descendant in ipairs(ghost:GetDescendants()) do addAdornment(descendant) end
		controller.AddedConnection = ghost.DescendantAdded:Connect(addAdornment)
		controller.RemovingConnection = ghost.DescendantRemoving:Connect(removeAdornment)
		return next(controller.Adornments) ~= nil
	end

	function controller:SetEnabled(enabled)
		self.Enabled = enabled == true
		if self.Enabled and not buildVisuals() then self.Enabled = false end
		if not self.Enabled then destroyVisuals() end
		render()
		return self.Enabled
	end

	function controller:Toggle()
		return self:SetEnabled(not self.Enabled)
	end

	function controller:Destroy()
		self.Enabled = false
		destroyVisuals()
		if self.RenderConnection then self.RenderConnection:Disconnect() end
		if self.ButtonConnection then self.ButtonConnection:Disconnect() end
	end

	controller.RenderConnection = runService.RenderStepped:Connect(function()
		if not controller.Enabled or dependencies.VisualFactory then return end
		for part, adornment in pairs(controller.Adornments) do
			if not part:IsDescendantOf(ghost) then
				removeAdornment(part)
			elseif adornment.Size ~= part.Size then
				adornment.Size = part.Size
			end
		end
	end)
	if button then
		controller.ButtonConnection = button.MouseButton1Click:Connect(function()
			controller:Toggle()
		end)
	end
	render()
	return controller
end
