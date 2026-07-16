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
		return self.Enabled
	end

	function controller:Toggle()
		return self:SetEnabled(not self.Enabled)
	end

	function controller:Destroy()
		self:SetEnabled(false)
	end

	return controller
end
