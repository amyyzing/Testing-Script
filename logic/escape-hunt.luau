return function(dependencies)
	local player = assert(dependencies.Player, "escape-hunt requires Player")
	local ghost = assert(dependencies.Ghost, "escape-hunt requires Ghost")
	local teleportToSafety = assert(
		dependencies.TeleportToSafety,
		"escape-hunt requires TeleportToSafety"
	)
	local controller = {Enabled = false, Escaped = false, Busy = false, Generation = 0}
	local button = dependencies.Button
	local disabledColor = button and button.BackgroundColor3
	local enabledColor = dependencies.EnabledColor or disabledColor

	local function render()
		if not button then return end
		button.Text = controller.Enabled and "HUNT ESCAPE: ON" or "HUNT ESCAPE: OFF"
		button.BackgroundColor3 = controller.Enabled and enabledColor or disabledColor
	end

	local function restore()
		if not controller.Escaped then return false end
		local character, pivot = controller.Character, controller.OriginalPivot
		controller.Escaped, controller.Character, controller.OriginalPivot = false, nil, nil
		if character ~= player.Character or not character or not character.Parent then return false end
		character:PivotTo(pivot)
		return true
	end

	local function update()
		local hunting = ghost:GetAttribute("Hunting") == true
		if not controller.Enabled or not hunting then
			controller.Generation += 1
			if not hunting then restore() end
			return
		end
		if controller.Escaped or controller.Busy then return end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local original = character:GetPivot()
		controller.Busy = true
		controller.Generation += 1
		local generation = controller.Generation
		local ok, moved = pcall(teleportToSafety)
		controller.Busy = false
		if ok and moved ~= false then
			controller.Escaped = true
			controller.Character = character
			controller.OriginalPivot = original
			if generation ~= controller.Generation
				or not controller.Enabled
				or ghost:GetAttribute("Hunting") ~= true then
				restore()
			end
		elseif character == player.Character and character.Parent then
			character:PivotTo(original)
		end
	end

	controller.Connection = ghost:GetAttributeChangedSignal("Hunting"):Connect(update)

	function controller:SetEnabled(enabled)
		self.Enabled = enabled == true
		if self.Enabled then
			update()
		else
			self.Generation += 1
			restore()
		end
		render()
		return self.Enabled
	end

	function controller:Toggle()
		return self:SetEnabled(not self.Enabled)
	end

	function controller:Destroy()
		self.Enabled = false
		self.Generation += 1
		restore()
		self.Connection:Disconnect()
		if self.ButtonConnection then self.ButtonConnection:Disconnect() end
	end

	if button then
		controller.ButtonConnection = button.MouseButton1Click:Connect(function()
			controller:Toggle()
		end)
	end
	render()

	return controller
end
