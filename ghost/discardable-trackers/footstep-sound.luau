return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "footstep-sound requires Traffic")
	local Ghost = assert(dependencies.Ghost, "footstep-sound requires Ghost")
	local RunService = dependencies.RunService or game:GetService("RunService")
	local Tracker = {Kind = "active", Running = true, Accumulator = 0, MissingFor = 0}
	function Tracker:Sample(delta)
		local root = Ghost:FindFirstChild("HumanoidRootPart")
		if not root then
			self.LastRoot, self.MissingFor = root, 0
			return
		end
		for _, sound in ipairs(root:GetDescendants()) do
			if sound:IsA("Sound") and sound.Name == "CurrentSound" then
				Traffic("FootstepPresence", {Present = true}):SendTo("Umbra")
				self:Destroy()
				return
			end
		end
		if self.LastRoot == root and delta <= 0.5 then
			self.MissingFor += math.min(delta, 0.25)
		else
			self.MissingFor = 0
		end
		self.LastRoot = root
		if self.MissingFor >= 2 and not self.ReportedMissing then
			self.ReportedMissing = true
			Traffic("FootstepPresence", {Present = false, MissingFor = self.MissingFor}):SendTo("Umbra")
		end
	end
	function Tracker:Destroy()
		self.Running = false
		if self.Connection then self.Connection:Disconnect() end
	end
	Tracker.Connection = RunService.Heartbeat:Connect(function(delta)
		if not Tracker.Running then return end
		Tracker.Accumulator += delta
		if Tracker.Accumulator < 0.1 then return end
		local elapsed = Tracker.Accumulator
		Tracker.Accumulator = 0
		Tracker:Sample(elapsed)
	end)
	return Tracker
end
