return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "music-box-stun requires Traffic")
	local Ghost = assert(dependencies.Ghost, "music-box-stun requires Ghost")
	local RunService = assert(dependencies.RunService, "music-box-stun requires RunService")
	local humanoid = assert(Ghost:FindFirstChildOfClass("Humanoid"), "music-box-stun requires Humanoid")
	local clock = dependencies.Clock or os.clock
	local tracker = {Kind = "dormant", Running = true, Speed = humanoid.WalkSpeed,
		Hunting = Ghost:GetAttribute("Hunting") == true}
	local function isStun(speed, baseline)
		-- Native first-play probes at 0.5x and 2x both used the fixed speed 2.
		return speed >= 0 and speed <= 2.05 and speed < baseline - 0.05
	end

	local function cancel()
		tracker.Active = nil
		if tracker.Heartbeat then tracker.Heartbeat:Disconnect() tracker.Heartbeat = nil end
		if tracker.BoxConnection then tracker.BoxConnection:Disconnect() tracker.BoxConnection = nil end
	end

	local function recordSpeed(now)
		local speed = humanoid.WalkSpeed
		if speed ~= tracker.Speed then
			tracker.LastChange = {Before = tracker.Speed, After = speed, Time = now}
			tracker.Speed = speed
		end
		return speed
	end

	local function inspect(now)
		local active = tracker.Active
		if not active then return end
		if not Ghost.Parent or not humanoid.Parent or not active.Box.Parent
			or (Ghost:GetAttribute("Hunting") == true) ~= active.Hunting then cancel() return end
		local speed = recordSpeed(now)
		if not active.DropAt then
			if now - active.PlayedAt > 0.5 then cancel() return end
			if isStun(speed, active.Baseline) then
				active.DropAt, active.Slow = now, speed
			end
			return
		end
		local duration = now - active.DropAt
		if duration > 3.5 then cancel() return end
		if math.abs(speed - active.Slow) <= 0.05 then return end
		if duration >= 2.5 and math.abs(speed - active.Baseline) <= math.max(0.05, active.Baseline * 0.01) then
			local result = {Qualified = true, Duration = duration, Baseline = active.Baseline,
				SlowSpeed = active.Slow, RecoveredSpeed = speed, MusicBox = active.Box}
			tracker.Result = result
			tracker:Destroy()
			Traffic("MusicBoxStun", result):SendTo("Dybbuk")
		else
			cancel()
		end
	end

	tracker.Disconnect = Traffic:Receive("MusicBoxStun", function(signal, payload)
		if not tracker.Running or signal ~= "MusicBoxFirstPlay" or type(payload) ~= "table" then return end
		local box = payload.MusicBox
		if not box or not box.Parent then return end
		if tracker.Active then cancel() return end -- Overlapping first plays cannot isolate the cause.
		local now = clock()
		local hunting = Ghost:GetAttribute("Hunting") == true
		if hunting ~= tracker.Hunting then
			tracker.Hunting, tracker.HuntChangedAt = hunting, now
			cancel()
			return
		end
		if tracker.HuntChangedAt and now - tracker.HuntChangedAt <= 0.5 then return end
		local speed = recordSpeed(now)
		local change = tracker.LastChange
		local recentDrop = change and now - change.Time <= 0.5 and change.Before > 0
			and isStun(speed, change.Before)
		local baseline = recentDrop and change.Before or speed
		if baseline <= 0 then return end
		tracker.Active = {Box = box, PlayedAt = now, Baseline = baseline,
			Hunting = Ghost:GetAttribute("Hunting") == true,
			DropAt = recentDrop and change.Time or nil, Slow = recentDrop and speed or nil}
		tracker.BoxConnection = box.AncestryChanged:Connect(cancel)
		tracker.Heartbeat = RunService.Heartbeat:Connect(function() inspect(clock()) end)
		inspect(now)
	end)
	tracker.SpeedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		local now = clock()
		recordSpeed(now)
		inspect(now)
	end)
	tracker.GhostConnection = Ghost.AncestryChanged:Connect(cancel)
	tracker.HumanoidConnection = humanoid.AncestryChanged:Connect(cancel)
	tracker.HuntingConnection = Ghost:GetAttributeChangedSignal("Hunting"):Connect(function()
		local hunting = Ghost:GetAttribute("Hunting") == true
		if hunting == tracker.Hunting then return end
		tracker.Hunting, tracker.HuntChangedAt = hunting, clock()
		cancel()
	end)

	function tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		cancel()
		self.Disconnect()
		self.SpeedConnection:Disconnect()
		self.GhostConnection:Disconnect()
		self.HumanoidConnection:Disconnect()
		self.HuntingConnection:Disconnect()
	end
	return tracker
end
