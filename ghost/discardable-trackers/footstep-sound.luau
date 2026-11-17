return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "footstep-sound requires Traffic")
	local Ghost = assert(dependencies.Ghost, "footstep-sound requires Ghost")
	local RunService = dependencies.RunService or game:GetService("RunService")
	local ids = dependencies.FootstepIds
	if not ids then
		ids = {}
		local storage = dependencies.ReplicatedStorage or game:GetService("ReplicatedStorage")
		local modules = storage:FindFirstChild("Modules")
		local module = modules and modules:FindFirstChild("FootstepSounds")
		local ok, sounds = pcall(function() return module and require(module) end)
		if ok and type(sounds) == "table" then
			for _, sound in pairs(sounds) do
				if type(sound) == "table" and sound.id and (tonumber(sound.volume) or 0) > 0 then
					ids[sound.id] = true
				end
			end
		end
	end
	local Tracker = {Kind = "active", Running = true, AudibleSamples = 0, Accumulator = 0}
	function Tracker:Sample()
		local root = Ghost:FindFirstChild("HumanoidRootPart")
		local audible
		if root and Ghost:GetAttribute("Hunting") == true then
			for _, sound in ipairs(root:GetDescendants()) do
				if sound:IsA("Sound") and ids[sound.SoundId] and sound.IsPlaying
					and sound.Volume > 0 then audible = sound break end
			end
		end
		local previous = self.AudibleSamples
		self.AudibleSamples = audible and self.AudibleSamples + 1 or 0
		local hunting = Ghost:GetAttribute("Hunting") == true
		if previous ~= self.AudibleSamples or self.LastHunting ~= hunting then
			Traffic("FootstepProgress", {Samples=self.AudibleSamples,Hunting=hunting}):SendTo("GhostPatternLog")
			self.LastHunting = hunting
		end
		if self.AudibleSamples >= 3 then
			Traffic("FootstepObserved", {Confirmed = true, Samples = self.AudibleSamples,
				SoundId = audible.SoundId}):SendTo("Umbra")
			self:Destroy()
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
		Tracker.Accumulator = 0
		Tracker:Sample()
	end)
	return Tracker
end
