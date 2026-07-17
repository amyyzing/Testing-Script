return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "los-speed requires Traffic")
	local epsilon = tonumber(dependencies.SpeedEpsilon) or 0.01
	local requiredExposure = tonumber(dependencies.RequiredExposure) or 4
	local Tracker = {Kind = "dormant", Running = true, Resolved = false}

	Tracker.Disconnect = Traffic:Receive("LOSSpeed", function(signal, payload)
		if not Tracker.Running or Tracker.Resolved or signal ~= "PlayerLOSSpeed"
			or type(payload) ~= "table" then return end
		local before = payload.beforeLOS or {}
		local after = payload.afterLOS or {}
		local baseline
		for _, point in ipairs(before) do
			if point.sprinting and (not baseline or point.s > baseline) then baseline = point.s end
		end
		if not baseline then return end
		local compared, dropped = 0, false
		for index = 2, #after do
			local point = after[index]
			if point.sprinting then
				compared += 1
				if point.s < baseline - epsilon then
					dropped = true
					break
				end
			end
		end
		local duration = tonumber(payload.Duration) or 0
		local ruleOut = payload.ContinuousSprinting == true
			and duration >= requiredExposure and compared > 0
		if not dropped and not ruleOut then return end
		Tracker.Resolved = true
		Traffic("LOSSpeedResult", {
			Player = payload.Player,
			Slowed = dropped,
			Completed = dropped or ruleOut,
			Duration = duration,
		}):SendTo("Siren")
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
	end

	return Tracker
end
