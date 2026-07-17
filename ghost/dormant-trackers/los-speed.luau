return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "los-speed requires Traffic")
	local epsilon = tonumber(dependencies.SpeedEpsilon) or 0.01
	local requiredExposure = tonumber(dependencies.RequiredExposure) or 4
	local Tracker = {Kind = "dormant", Running = true, Resolved = false}

	Tracker.Disconnect = Traffic:Receive("LOSSpeed", function(signal, payload)
		if not Tracker.Running or Tracker.Resolved or signal ~= "PlayerLOSSpeed"
			or type(payload) ~= "table" then return end
		local after = payload.afterLOS or {}
		local base = tonumber(payload.BaseSpeed)
		local sprint = tonumber(payload.SprintSpeed) or (base and base * 1.6)
		if payload.Hunting ~= true or not base or not sprint then return end
		local function near(first, second)
			return math.abs(first - second) <= epsilon
		end
		local compared, slowed, unknown = 0, false, false
		local observed
		for _, point in ipairs(after) do
			local speed = tonumber(point.s)
			if speed then
				compared += 1
				if near(speed, base * 0.8) or near(speed, sprint * 0.8) then
					slowed, observed = true, speed
					break
				elseif not near(speed, base) and not near(speed, sprint) then
					unknown = true
				end
			end
		end
		local duration = tonumber(payload.Duration) or 0
		local ruleOut = duration >= requiredExposure and compared > 0 and not unknown
		if not slowed and not ruleOut then return end
		Tracker.Resolved = true
		Traffic("LOSSpeedResult", {
			Player = payload.Player,
			Slowed = slowed,
			ObservedSpeed = observed,
			BaseSpeed = base,
			SprintSpeed = sprint,
			Completed = slowed or ruleOut,
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
