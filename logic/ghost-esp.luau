return function(dependencies)
	local ghost = assert(dependencies.Ghost, "ghost-esp requires Ghost")
	local runService = assert(dependencies.RunService, "ghost-esp requires RunService")
	local world = dependencies.Workspace or workspace
	local guiParent = assert(dependencies.GuiParent, "ghost-esp requires GuiParent")
	local button = dependencies.Button
	local red = dependencies.Red or Color3.fromRGB(210, 66, 82)
	local disabledColor = button and button.BackgroundColor3
	local enabledColor = dependencies.EnabledColor or disabledColor
	local controller = {
		Enabled = false,
		ProxyParts = {},
		ProxyDirty = false,
	}

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

	local function disconnectVisualConnections()
		if controller.AddedConnection then controller.AddedConnection:Disconnect() end
		if controller.RemovingConnection then controller.RemovingConnection:Disconnect() end
		controller.AddedConnection, controller.RemovingConnection = nil, nil
	end

	local function destroyVisuals()
		disconnectVisualConnections()
		if controller.TestVisual then controller.TestVisual:Destroy() end
		for _, object in ipairs({
			controller.Billboard,
			controller.DirectHighlight,
			controller.ProxyHighlight,
			controller.ProxyModel,
		}) do
			if object then object:Destroy() end
		end
		controller.TestVisual = nil
		controller.Billboard = nil
		controller.DirectHighlight = nil
		controller.ProxyHighlight = nil
		controller.ProxyModel = nil
		controller.ProxyParts = {}
		controller.ProxyDirty = false
	end

	local function configureProxyPart(part)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Massless = true
		part.Locked = true
		part.Transparency = 0.99
		part.LocalTransparencyModifier = 0
		part.Reflectance = 0
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end

	local function cloneProxyPart(source)
		local archivable = source.Archivable
		source.Archivable = true
		local ok, proxy = pcall(function() return source:Clone() end)
		source.Archivable = archivable
		if not ok or not proxy or not proxy:IsA("BasePart") then
			proxy = Instance.new("Part")
			if source:IsA("Part") then proxy.Shape = source.Shape end
		end
		for _, descendant in ipairs(proxy:GetDescendants()) do
			if not descendant:IsA("DataModelMesh") then descendant:Destroy() end
		end
		proxy.Name = source.Name
		proxy.Color = red
		proxy.Size = source.Size
		proxy.CFrame = source.CFrame
		configureProxyPart(proxy)
		return proxy
	end

	local function updateProxy()
		if not controller.ProxyModel then return false end
		controller.ProxyModel.Parent = world.CurrentCamera or world
		controller.ProxyHighlight.Enabled = controller.Enabled
		for source, proxy in pairs(controller.ProxyParts) do
			if not source:IsDescendantOf(ghost) or not proxy.Parent then
				controller.ProxyDirty = true
				return false
			end
			if proxy.Size ~= source.Size then proxy.Size = source.Size end
			proxy.CFrame = source.CFrame
			if not proxy.Anchored or proxy.CanCollide or proxy.CanTouch or proxy.CanQuery
				or proxy.CastShadow or proxy.Transparency ~= 0.99 then
				configureProxyPart(proxy)
			end
		end
		return true
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

		controller.ProxyModel = new("Model", {
			Name = "UntitledGhostHighlightProxy",
			Parent = nil,
			Archivable = false,
		})
		controller.ProxyModel:SetAttribute("VisualOnlyProxy", true)
		for _, descendant in ipairs(ghost:GetDescendants()) do
			if descendant:IsA("BasePart") then
				local proxy = cloneProxyPart(descendant)
				proxy.Parent = controller.ProxyModel
				controller.ProxyParts[descendant] = proxy
			end
		end
		if not next(controller.ProxyParts) then
			destroyVisuals()
			return false
		end
		controller.AddedConnection = ghost.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then controller.ProxyDirty = true end
		end)
		controller.RemovingConnection = ghost.DescendantRemoving:Connect(function(descendant)
			if descendant:IsA("BasePart") then controller.ProxyDirty = true end
		end)
		controller.ProxyHighlight = new("Highlight", {
			Name = "UntitledGhostHighlight",
			Parent = controller.ProxyModel,
			Adornee = controller.ProxyModel,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			FillColor = red,
			FillTransparency = 0.72,
			OutlineColor = Color3.new(1, 1, 1),
			OutlineTransparency = 0,
			Enabled = true,
		})
		controller.ProxyDirty = false
		updateProxy()
		return true
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
		local ghostPart = ghost.PrimaryPart or ghost:FindFirstChildWhichIsA("BasePart", true)
		if not ghostPart then
			destroyVisuals()
		elseif controller.ProxyDirty or not controller.Billboard
			or controller.Billboard.Adornee ~= ghostPart then
			buildVisuals()
		else
			updateProxy()
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
