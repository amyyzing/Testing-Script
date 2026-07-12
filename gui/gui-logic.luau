local GuiLogic = {}
GuiLogic.__index = GuiLogic

local function isPrimaryInput(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isPointerMovement(input)
	return input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
end

function GuiLogic.new(dependencies)
	dependencies = dependencies or {}
	local self = setmetatable({}, GuiLogic)
	self.Services = assert(dependencies.Services, "GuiLogic.new requires Services")
	self.View = assert(dependencies.View, "GuiLogic.new requires View")
	self.Player = dependencies.Player or self.Services.Players.LocalPlayer
	self.TweenService = self.Services.TweenService or game:GetService("TweenService")
	self.OnClose = dependencies.OnClose
	self.Bound = false
	self.Minimized = false
	self.Visible = true
	self.ExpandedSize = self.View.MainFrame.Size
	self.DraggingSlider = false
	self.DragTargetRatio = nil
	self.SliderFillTween = nil
	self.SliderKnobTween = nil
	self.PerkLogOpen = false
	self.PerkLogDrawerTween = nil
	self.PerkLogTabTween = nil
	return self
end

function GuiLogic:SetButtonEnabled(button, enabled)
	local colors = self.View.Colors
	button.BackgroundColor3 = enabled and colors.accentDark or colors.cardHover
	button.TextColor3 = enabled and Color3.new(1, 1, 1) or colors.text
end

function GuiLogic:FlashButton(button, text)
	if not button or not button.Parent then
		return
	end
	local original = button:GetAttribute("DefaultText") or button.Text
	button:SetAttribute("DefaultText", original)
	local token = (button:GetAttribute("FlashToken") or 0) + 1
	button:SetAttribute("FlashToken", token)
	button.Text = text or self.View.Copy.Actions.Fired
	task.delay(1, function()
		if button.Parent and button:GetAttribute("FlashToken") == token then
			button.Text = button:GetAttribute("DefaultText") or original
		end
	end)
end

function GuiLogic:SetEvidenceLabel(key, text, color)
	local label = self.View.EvidenceLabels[key]
	if not label then
		return
	end
	if text ~= nil then
		label.Text = text
	end
	if color ~= nil then
		label.TextColor3 = color
	end
end

function GuiLogic:AnimateSlider(ratio, duration)
	ratio = math.clamp(tonumber(ratio) or 0, 0, 1)
	duration = math.max(tonumber(duration) or 0.14, 0)

	if self.SliderFillTween then
		self.SliderFillTween:Cancel()
	end
	if self.SliderKnobTween then
		self.SliderKnobTween:Cancel()
	end

	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)
	self.SliderFillTween = self.TweenService:Create(
		self.View.SliderFill,
		tweenInfo,
		{Size = UDim2.fromScale(ratio, 1)}
	)
	self.SliderKnobTween = self.TweenService:Create(
		self.View.SliderKnob,
		tweenInfo,
		{Position = UDim2.fromScale(ratio, 0.5)}
	)
	self.SliderFillTween:Play()
	self.SliderKnobTween:Play()
end

function GuiLogic:SetSpeed(value)
	local numeric = math.clamp(tonumber(value) or 0, 0, 100)
	local rounded = math.floor(numeric + 0.5)
	local ratio = self.DraggingSlider and self.DragTargetRatio
		or rounded / 100
	self.View.SpeedValue.Text = tostring(rounded)
	self:AnimateSlider(ratio, self.DraggingSlider and 0.065 or 0.14)
end

function GuiLogic:SetGhostIdentification(ghostName, tier, certain)
	local label = self.View.EvidenceLabels.Ghost
	if not ghostName then
		label.Text = self.View.Copy.Evidence.Ghost .. ": Unknown (" .. self.View.Copy.States.Idk .. ")"
		label.TextColor3 = self.View.Colors.muted
		return
	end
	if certain then
		label.Text = self.View.Copy.Evidence.Ghost
			.. ": "
			.. tostring(ghostName)
			.. " ("
			.. self.View.Copy.States.Certain
			.. ")"
		label.TextColor3 = self.View.Colors.green
		return
	end
	local colorsByTier = {
		["Pretty Sure"] = self.View.Colors.gold,
		Maybe = self.View.Colors.orangeGold,
		Idk = self.View.Colors.red,
	}
	label.Text = self.View.Copy.Evidence.Ghost
		.. ": "
		.. tostring(ghostName)
		.. " ("
		.. tostring(tier or self.View.Copy.States.Idk)
		.. ")"
	label.TextColor3 = colorsByTier[tier] or self.View.Colors.muted
end

function GuiLogic:SetFavouriteRoom(roomName)
	self.View.EvidenceLabels.FavouriteRoom.Text = roomName and tostring(roomName) ~= ""
		and (self.View.Copy.Evidence.FavouriteRoom .. ": " .. tostring(roomName))
		or (self.View.Copy.Evidence.FavouriteRoom .. ": ...")
end

function GuiLogic:SetTemperature(value, freezing)
	local label = self.View.EvidenceLabels.Temperature
	local displayed = typeof(value) == "number"
		and string.format("%.1f°C", value)
		or "--.-°C"
	label.Text = self.View.Copy.Evidence.Temperature .. ": " .. displayed
	label.TextColor3 = freezing and self.View.Colors.green or self.View.Colors.text
end

function GuiLogic:SetPerkLogs(positiveEntries, negativeEntries)
	local function render(list, placeholder, entries, color)
		for _, child in ipairs(list:GetChildren()) do
			if child:GetAttribute("PerkLogRow") then
				child:Destroy()
			end
		end
		table.sort(entries, function(left, right)
			local leftAt = tonumber(left.At) or 0
			local rightAt = tonumber(right.At) or 0
			if leftAt == rightAt then
				return tostring(left.Ghost) < tostring(right.Ghost)
			end
			return leftAt > rightAt
		end)
		placeholder.Visible = #entries == 0
		for index, entry in ipairs(entries) do
			local confidence = math.floor((tonumber(entry.Confidence) or 0) + 0.5)
			local row = Instance.new("TextLabel")
			row.Name = tostring(entry.Ghost or "Unknown")
			row.Parent = list
			row.LayoutOrder = index + 1
			row.Size = UDim2.new(1, -4, 0, 40)
			row.AutomaticSize = Enum.AutomaticSize.Y
			row.BackgroundColor3 = self.View.Colors.cardHover
			row.BorderSizePixel = 0
			row.Font = Enum.Font.Gotham
			row.Text = tostring(entry.Ghost or "Unknown")
				.. " ["
				.. tostring(confidence)
				.. "%]\n"
				.. tostring(entry.Reason or "No reason recorded")
			row.TextColor3 = color
			row.TextSize = 11
			row.TextWrapped = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextYAlignment = Enum.TextYAlignment.Top
			row.ZIndex = 43
			row:SetAttribute("PerkLogRow", true)
			local padding = Instance.new("UIPadding")
			padding.Parent = row
			padding.PaddingTop = UDim.new(0, 7)
			padding.PaddingBottom = UDim.new(0, 7)
			padding.PaddingLeft = UDim.new(0, 8)
			padding.PaddingRight = UDim.new(0, 8)
			local stroke = Instance.new("UIStroke")
			stroke.Parent = row
			stroke.Color = self.View.Colors.stroke
			stroke.Transparency = 0.35
			stroke.Thickness = 1
			stroke.LineJoinMode = Enum.LineJoinMode.Miter
		end
	end
	render(
		self.View.PositivePerkLog,
		self.View.PositivePerkPlaceholder,
		positiveEntries or {},
		self.View.Colors.green
	)
	render(
		self.View.NegativePerkLog,
		self.View.NegativePerkPlaceholder,
		negativeEntries or {},
		self.View.Colors.red
	)
end

function GuiLogic:SetPerkLogOpen(open, instant)
	open = open == true
	self.PerkLogOpen = open
	if self.PerkLogDrawerTween then
		self.PerkLogDrawerTween:Cancel()
	end
	if self.PerkLogTabTween then
		self.PerkLogTabTween:Cancel()
	end
	local drawerPosition = open
		and UDim2.new(0, 32, 0, 42)
		or UDim2.new(1, 0, 0, 42)
	local tabPosition = open
		and UDim2.new(0, 0, 0, 52)
		or UDim2.new(1, -32, 0, 52)
	self.View.PerkLogButton.Text = open and "CLOSE" or self.View.Copy.PerkLogs.Toggle
	self.View.PerkLogTab.Text = open
		and (self.View.Copy.PerkLogs.Toggle .. "\n▶")
		or (self.View.Copy.PerkLogs.Toggle .. "\n◀")
	if instant then
		self.View.PerkLogDrawer.Position = drawerPosition
		self.View.PerkLogTab.Position = tabPosition
		return
	end
	local tweenInfo = TweenInfo.new(
		0.22,
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)
	self.PerkLogDrawerTween = self.TweenService:Create(
		self.View.PerkLogDrawer,
		tweenInfo,
		{Position = drawerPosition}
	)
	self.PerkLogTabTween = self.TweenService:Create(
		self.View.PerkLogTab,
		tweenInfo,
		{Position = tabPosition}
	)
	self.PerkLogDrawerTween:Play()
	self.PerkLogTabTween:Play()
end

function GuiLogic:TogglePerkLog()
	if self.Minimized then
		return
	end
	self:SetPerkLogOpen(not self.PerkLogOpen, false)
end

function GuiLogic:ResetEvidence()
	local labels = self.View.EvidenceLabels
	local evidenceCopy = self.View.Copy.Evidence
	local names = {
		Print = evidenceCopy.Print,
		SpiritBox = evidenceCopy.SpiritBox,
		Orb = evidenceCopy.Orb,
		Inscription = evidenceCopy.Inscription,
		Laser = evidenceCopy.Laser,
		Wither = evidenceCopy.Wither,
	}
	for key, name in pairs(names) do
		labels[key].Text = name .. ": " .. self.View.Copy.States.Unknown
		labels[key].TextColor3 = self.View.Colors.muted
	end
	labels.EMF.Text = "EMF-1"
	labels.EMF.TextColor3 = self.View.Colors.muted
	self:SetTemperature(nil, false)
	self:SetFavouriteRoom(nil)
	self:SetGhostIdentification(nil)
end

function GuiLogic:Notify(message)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = self.View.Copy.Title,
			Text = tostring(message),
			Duration = 4,
		})
	end)
end

function GuiLogic:Bind(controller)
	assert(not self.Bound, "GuiLogic is already bound")
	self.Bound = true
	self.Controller = controller

	local services = self.Services
	local view = self.View
	local buttons = view.Buttons
	local draggingWindow = false
	local dragStart
	local windowStartPosition

	controller:Connect(view.TitleBar.InputBegan, function(input)
		if isPrimaryInput(input) then
			draggingWindow = true
			dragStart = input.Position
			windowStartPosition = view.MainFrame.Position
		end
	end)

	controller:Connect(services.UserInputService.InputChanged, function(input)
		if draggingWindow and isPointerMovement(input) then
			local delta = input.Position - dragStart
			view.MainFrame.Position = UDim2.new(
				windowStartPosition.X.Scale,
				windowStartPosition.X.Offset + delta.X,
				windowStartPosition.Y.Scale,
				windowStartPosition.Y.Offset + delta.Y
			)
		end
	end)

	controller:Connect(services.UserInputService.InputEnded, function(input)
		if isPrimaryInput(input) then
			draggingWindow = false
		end
	end)

	local resizing = false
	local resizeStart
	local resizeStartSize
	local resizeStartPosition

	controller:Connect(view.ResizeHandle.InputBegan, function(input)
		if isPrimaryInput(input) then
			resizing = true
			resizeStart = input.Position
			resizeStartSize = view.MainFrame.AbsoluteSize
			resizeStartPosition = view.MainFrame.Position
		end
	end)

	controller:Connect(services.UserInputService.InputChanged, function(input)
		if resizing and isPointerMovement(input) then
			local delta = input.Position - resizeStart
			local width = math.clamp(resizeStartSize.X - delta.X, 330, 620)
			local height = math.clamp(resizeStartSize.Y + delta.Y, 430, 780)
			local appliedDeltaX = resizeStartSize.X - width
			local appliedDeltaY = height - resizeStartSize.Y
			view.MainFrame.Size = UDim2.fromOffset(width, height)
			view.MainFrame.Position = UDim2.new(
				resizeStartPosition.X.Scale,
				resizeStartPosition.X.Offset + appliedDeltaX / 2,
				resizeStartPosition.Y.Scale,
				resizeStartPosition.Y.Offset + appliedDeltaY / 2
			)
			self.ExpandedSize = view.MainFrame.Size
		end
	end)

	controller:Connect(services.UserInputService.InputEnded, function(input)
		if isPrimaryInput(input) then
			resizing = false
		end
	end)

	local function updateSlider(input)
		local relativeX = input.Position.X - view.SliderTrack.AbsolutePosition.X
		local ratio = math.clamp(
			relativeX / math.max(view.SliderTrack.AbsoluteSize.X, 1),
			0,
			1
		)
		self.DragTargetRatio = ratio
		controller:SetSpeed(ratio * 100)
	end

	controller:Connect(view.SliderTrack.InputBegan, function(input)
		if isPrimaryInput(input) then
			self.DraggingSlider = true
			updateSlider(input)
		end
	end)
	controller:Connect(view.SliderKnob.InputBegan, function(input)
		if isPrimaryInput(input) then
			self.DraggingSlider = true
			updateSlider(input)
		end
	end)
	controller:Connect(services.UserInputService.InputChanged, function(input)
		if self.DraggingSlider and isPointerMovement(input) then
			updateSlider(input)
		end
	end)
	controller:Connect(services.UserInputService.InputEnded, function(input)
		if self.DraggingSlider and isPrimaryInput(input) then
			self.DraggingSlider = false
			self.DragTargetRatio = nil
			self:SetSpeed(view.SpeedValue.Text)
		end
	end)

	controller:Connect(buttons.GhostEsp.MouseButton1Click, function()
		controller:ToggleGhostEsp()
	end)
	controller:Connect(view.PerkLogButton.MouseButton1Click, function()
		self:TogglePerkLog()
	end)
	controller:Connect(view.PerkLogTab.MouseButton1Click, function()
		self:TogglePerkLog()
	end)
	controller:Connect(buttons.HuntEscape.MouseButton1Click, function()
		controller:ToggleHuntEscape()
	end)
	controller:Connect(buttons.ItemEsp.MouseButton1Click, function()
		controller:ToggleItemEsp()
	end)
	controller:Connect(buttons.FullBright.MouseButton1Click, function()
		controller:ToggleFullBright()
	end)
	controller:Connect(buttons.TeleportBaseCamp.MouseButton1Click, function()
		local ok, reason = controller:TeleportToBaseCamp()
		if ok == false then
			self:Notify(reason)
		end
	end)
	controller:Connect(buttons.TeleportFavouriteRoom.MouseButton1Click, function()
		local ok, reason = controller:TeleportToFavouriteRoom()
		if ok == false then
			self:Notify(reason)
		end
	end)
	controller:Connect(buttons.PlaceRoomItems.MouseButton1Click, function()
		controller:PlaceRoomItems()
	end)
	controller:Connect(buttons.AutoSpiritBox.MouseButton1Click, function()
		controller:ToggleAutoSpiritBox()
	end)
	controller:Connect(buttons.WalkSpeedForcer.MouseButton1Click, function()
		controller:ToggleWalkSpeedForcer()
	end)
	controller:Connect(buttons.RandomLights.MouseButton1Click, function()
		local ok, reason = controller:ToggleRandomLights()
		if ok == false then
			self:Notify(reason)
		end
	end)
	controller:Connect(buttons.ToggleFuseBox.MouseButton1Click, function()
		local ok, reason = controller:ToggleFuseBox()
		if ok == false then
			self:Notify(reason)
		end
	end)

	local evidenceMode = view.EvidenceLabels.EvidenceMode
	local evidenceMenu = view.EvidenceLabels.EvidenceModeMenu
	local function positionEvidenceMenu()
		local relativePosition = evidenceMode.AbsolutePosition
			- view.DropdownLayer.AbsolutePosition
		local absoluteSize = evidenceMode.AbsoluteSize
		evidenceMenu.Position = UDim2.fromOffset(
			math.floor(relativePosition.X + 0.5),
			math.floor(relativePosition.Y + absoluteSize.Y + 4.5)
		)
		evidenceMenu.Size = UDim2.fromOffset(
			math.max(math.floor(absoluteSize.X + 0.5), 1),
			70
		)
	end
	local function repositionOpenEvidenceMenu()
		if evidenceMenu.Visible then
			positionEvidenceMenu()
		end
	end
	controller:Connect(
		evidenceMode:GetPropertyChangedSignal("AbsolutePosition"),
		repositionOpenEvidenceMenu
	)
	controller:Connect(
		evidenceMode:GetPropertyChangedSignal("AbsoluteSize"),
		repositionOpenEvidenceMenu
	)
	controller:Connect(
		view.DropdownLayer:GetPropertyChangedSignal("AbsolutePosition"),
		repositionOpenEvidenceMenu
	)
	controller:Connect(
		view.Content:GetPropertyChangedSignal("CanvasPosition"),
		function()
			evidenceMenu.Visible = false
		end
	)
	controller:Connect(evidenceMode.MouseButton1Click, function()
		if not evidenceMenu.Visible then
			positionEvidenceMenu()
		end
		evidenceMenu.Visible = not evidenceMenu.Visible
	end)
	for _, mode in ipairs({view.Copy.EvidenceModes.Normal, view.Copy.EvidenceModes.Mimicry}) do
		local option = evidenceMenu:FindFirstChild(mode)
		controller:Connect(option.MouseButton1Click, function()
			controller:SetEvidenceMode(mode)
			evidenceMode.Text = view.Copy.Controls.EvidenceMode .. ": " .. mode .. " ▼"
			evidenceMenu.Visible = false
		end)
	end

	controller:Connect(view.MinimizeButton.MouseButton1Click, function()
		self.Minimized = not self.Minimized
		evidenceMenu.Visible = false
		self:SetPerkLogOpen(false, true)
		if self.Minimized then
			self.ExpandedSize = view.MainFrame.Size
			view.Content.Visible = false
			view.ResizeHandle.Visible = false
			view.SizeConstraint.MinSize = Vector2.new(330, 42)
			view.SizeConstraint.MaxSize = Vector2.new(620, 42)
			view.MainFrame.Size = UDim2.fromOffset(math.max(view.MainFrame.AbsoluteSize.X, 330), 42)
			view.MinimizeButton.Text = "+"
		else
			view.SizeConstraint.MinSize = Vector2.new(330, 430)
			view.SizeConstraint.MaxSize = Vector2.new(620, 780)
			view.MainFrame.Size = self.ExpandedSize
			view.Content.Visible = true
			view.ResizeHandle.Visible = true
			view.MinimizeButton.Text = "–"
		end
	end)

	controller:Connect(view.CloseButton.MouseButton1Click, function()
		if self.OnClose then
			self.OnClose()
		else
			controller:Destroy()
		end
	end)
	controller:Connect(services.UserInputService.InputBegan, function(input, gameProcessed)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.RightControl then
			self.Visible = not self.Visible
			view.MainFrame.Visible = self.Visible
			if not self.Visible then
				evidenceMenu.Visible = false
			end
		end
	end)

	return self
end

return GuiLogic
