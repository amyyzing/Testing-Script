return function(dependencies)
	local player = assert(dependencies.Player, "anti-idle requires Player")
	local virtualUser = assert(dependencies.VirtualUser, "anti-idle requires VirtualUser")
	local World = dependencies.Workspace or workspace
	local controller = {Destroyed = false}

	controller.Connection = player.Idled:Connect(function()
		if controller.Destroyed then return end
		pcall(function()
			local camera = World.CurrentCamera
			virtualUser:Button2Down(Vector2.zero, camera and camera.CFrame or CFrame.new())
			task.wait(0.1)
			virtualUser:Button2Up(Vector2.zero, camera and camera.CFrame or CFrame.new())
		end)
	end)

	function controller:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		if self.Connection then self.Connection:Disconnect() end
	end

	return controller
end
