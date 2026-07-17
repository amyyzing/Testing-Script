return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "wendigo-speed requires Traffic")
	local Players = assert(dependencies.Players, "wendigo-speed requires Players")
	local Humanoid = assert(dependencies.Humanoid, "wendigo-speed requires Humanoid")
	local delay = dependencies.DelayTask or (task and task.delay)
	assert(type(delay) == "function", "wendigo-speed requires task.delay")
	local settleDelay = tonumber(dependencies.SettleDelay) or 0.1
	local Tracker = {Kind = "dormant", Running = true, Token = 0}

	local function averageEnergy()
		local players = Players:GetPlayers()
		if #players == 0 then return nil end
		local total = 0
		for _, player in ipairs(players) do
			local energy = tonumber(player:GetAttribute("Energy"))
			if not energy then return nil end
			total += energy
		end
		return total / #players
	end

	Tracker.Disconnect = Traffic:Receive("WendigoSpeed", function(signal, payload)
		if signal ~= "HuntingState" or type(payload) ~= "table"
			or type(payload.Hunting) ~= "boolean" then return end
		local energy = averageEnergy()
		if not energy then return end
		Tracker.Token += 1
		local token = Tracker.Token
		delay(settleDelay, function()
			if not Tracker.Running or Tracker.Token ~= token then return end
			Traffic("WendigoSpeedSample", {
				Hunting = payload.Hunting,
				AverageEnergy = energy,
				Speed = Humanoid.WalkSpeed,
				TransitionTime = payload.Time,
			}):SendTo("SpeedFilter")
		end)
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Token += 1
		self.Disconnect()
	end
	return Tracker
end
