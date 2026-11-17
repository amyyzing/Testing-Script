return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "wretch-speed requires Traffic")
	local Players = assert(dependencies.Players, "wretch-speed requires Players")
	local Humanoid = assert(dependencies.Humanoid, "wretch-speed requires Humanoid")
	local World = dependencies.Workspace
	local delay = dependencies.DelayTask or (task and task.delay)
	assert(type(delay) == "function", "wretch-speed requires task.delay")
	local settleDelay = tonumber(dependencies.SettleDelay) or 0.3
	local Tracker = {
		Kind = "dormant",
		Running = true,
		Token = 0,
		TransitionCount = 0,
		LastHunting = nil,
		Started = false,
	}

	local function averageEnergy()
		local reported = World and tonumber(World:GetAttribute("AverageEnergy"))
		if reported then return reported end
		local players = Players:GetPlayers()
		if #players == 0 then return nil end
		local total, count = 0, 0
		for _, player in ipairs(players) do
			if player:GetAttribute("Dead") == true then continue end
			local energy = tonumber(player:GetAttribute("Energy"))
			if not energy then return nil end
			total += energy
			count += 1
		end
		return count > 0 and total / count or nil
	end

	Tracker.Disconnect = Traffic:Receive("WretchSpeed", function(signal, payload)
		if signal ~= "HuntingState" or type(payload) ~= "table"
			or type(payload.Hunting) ~= "boolean" then return end
		local hunting = payload.Hunting
		if Tracker.LastHunting == nil then
			Tracker.LastHunting = hunting
			return
		end
		if Tracker.LastHunting == hunting then return end
		Tracker.LastHunting = hunting
		if not Tracker.Started then
			if not hunting then return end
			Tracker.Started = true
		end
		local energy = averageEnergy()
		if not energy then return end
		Tracker.TransitionCount += 1
		local transition = Tracker.TransitionCount
		Traffic("WretchEnergySnapshot", {
			Transition = transition,
			Hunting = hunting,
			AverageEnergy = energy,
			TransitionTime = payload.Time,
		}):SendTo("SpeedArrayLog")
		Tracker.Token += 1
		local token = Tracker.Token
		local samples = {}
		local function sample()
			if not Tracker.Running or Tracker.Token ~= token then return end
			table.insert(samples, Humanoid.WalkSpeed)
			if #samples < 3 then delay(0.15, sample) return end
			local minimum, maximum, sum = math.huge, -math.huge, 0
			for _, speed in ipairs(samples) do minimum = math.min(minimum, speed) maximum = math.max(maximum, speed) sum += speed end
			Traffic("WretchSpeedSample", {
				Transition = transition,
				Hunting = hunting,
				AverageEnergy = energy,
				Speed = sum / #samples,
				Stable = maximum - minimum <= 0.05,
				TransitionTime = payload.Time,
			}):SendTo("SpeedFilter", "SpeedArrayLog")
		end
		delay(settleDelay, sample)
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Token += 1
		self.Disconnect()
	end
	return Tracker
end
