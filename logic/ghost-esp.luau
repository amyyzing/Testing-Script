return function(dependencies)
	local ghost = assert(dependencies.Ghost, "ghost-esp requires Ghost")
	local button = dependencies.Button
	local createHighlight = dependencies.CreateHighlight or function()
		return Instance.new("Highlight")
	end
	local controller = {Enabled = false, Highlight = nil}
	local disabledColor = button and button.BackgroundColor3
	local enabledColor = dependencies.EnabledColor or disabledColor

	local function render()
		if not button then return end
		button.Text = controller.Enabled and "GHOST ESP: ON" or "GHOST ESP: OFF"
		button.BackgroundColor3 = controller.Enabled and enabledColor or disabledColor
	end

	local function removeHighlight()
		if controller.Highlight then
			controller.Highlight:Destroy()
			controller.Highlight = nil
		end
	end

	function controller:SetEnabled(enabled)
		self.Enabled = enabled == true
		removeHighlight()
		if self.Enabled then
			local highlight = createHighlight()
			highlight.Name = "DemonologyGhostESP"
			highlight.Adornee = ghost
			highlight.DepthMode = dependencies.DepthMode or Enum.HighlightDepthMode.AlwaysOnTop
			highlight.FillColor = dependencies.FillColor or Color3.fromRGB(210, 66, 82)
			highlight.FillTransparency = 0.65
			highlight.OutlineColor = dependencies.OutlineColor or Color3.fromRGB(255, 255, 255)
			highlight.OutlineTransparency = 0
			highlight.Parent = ghost
			self.Highlight = highlight
		end
		render()
		return self.Enabled
	end

	function controller:Toggle()
		return self:SetEnabled(not self.Enabled)
	end

	function controller:Destroy()
		self.Enabled = false
		removeHighlight()
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
