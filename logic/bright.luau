return function(dependencies)
	local lighting = assert(dependencies.Lighting, "bright requires Lighting")
	local white = dependencies.White or Color3.new(1, 1, 1)
	local original = {
		Ambient = lighting.Ambient,
		OutdoorAmbient = lighting.OutdoorAmbient,
		Brightness = lighting.Brightness,
		GlobalShadows = lighting.GlobalShadows,
		FogEnd = lighting.FogEnd,
	}
	local controller = {Enabled = false}
	local button = dependencies.Button
	local disabledColor = button and button.BackgroundColor3
	local enabledColor = dependencies.EnabledColor or disabledColor

	local function render()
		if not button then return end
		button.Text = controller.Enabled and "FULL BRIGHT: ON" or "FULL BRIGHT: OFF"
		button.BackgroundColor3 = controller.Enabled and enabledColor or disabledColor
	end

	function controller:SetEnabled(enabled)
		self.Enabled = enabled == true
		if self.Enabled then
			lighting.Ambient = white
			lighting.OutdoorAmbient = white
			lighting.Brightness = 3
			lighting.GlobalShadows = false
			lighting.FogEnd = 100000
		else
			lighting.Ambient = original.Ambient
			lighting.OutdoorAmbient = original.OutdoorAmbient
			lighting.Brightness = original.Brightness
			lighting.GlobalShadows = original.GlobalShadows
			lighting.FogEnd = original.FogEnd
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
		controller.ButtonConnection = button.MouseButton1Click:Connect(function()
			controller:Toggle()
		end)
	end
	render()

	return controller
end
