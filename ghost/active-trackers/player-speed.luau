return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "player-speed requires Traffic")
	local Players = dependencies.Players or game:GetService("Players")
	local clock = dependencies.Clock or os.clock
	local epsilon = tonumber(dependencies.SpeedEpsilon) or 0.01
	local normalSpeeds = {8, 10, 12, 14, 16}
	local Tracker = {
		Kind = "active",
		Running = true,
		Hunting = false,
		States = setmetatable({}, {__mode = "k"}),
		Connections = {},
	}

	local function remember(connection)
		table.insert(Tracker.Connections, connection)
	end

	local function near(first, second)
		return math.abs(first - second) <= epsilon
	end

	local function learn(state, speed)
		if not state.BaseSpeed then
			for _, candidate in ipairs(normalSpeeds) do
				if near(speed, candidate) then
					state.BaseSpeed = candidate
					state.SprintSpeed = candidate * 1.6
					return
				end
			end
		elseif near(speed, state.BaseSpeed * 1.6) then
			state.SprintSpeed = speed
			state.SprintObserved = true
		end
	end

	local function rawPoint(state)
		local speed = state.Humanoid and tonumber(state.Humanoid.WalkSpeed)
		if not speed then return nil end
		return {s = speed}
	end

	local function append(state, point)
		table.insert(state.Samples, point)
		while #state.Samples > 40 do table.remove(state.Samples, 1) end
	end

	local function send(state, completed)
		if not state.BeforeLOS or not state.BaseSpeed then return end
		Traffic("PlayerLOSSpeed", {
			Player = state.Player,
			BaseSpeed = state.BaseSpeed,
			SprintSpeed = state.SprintSpeed or state.BaseSpeed * 1.6,
			beforeLOS = state.BeforeLOS,
			afterLOS = state.AfterLOS,
			Duration = math.max(0, clock() - state.StartedAt),
			Hunting = Tracker.Hunting,
			completed = completed == true,
		}):SendTo("LOSSpeed")
	end

	local function clearTrial(state)
		state.InLOS = false
		state.BeforeLOS, state.AfterLOS, state.StartedAt = nil, nil, nil
	end

	local function sample(state)
		local point = rawPoint(state)
		if not point then return end
		if not Tracker.Hunting then learn(state, point.s) end
		append(state, point)
		if not Tracker.Hunting or not state.InLOS or not state.BaseSpeed then return end
		if not state.BeforeLOS then
			state.BeforeLOS = table.clone(state.Samples)
			state.AfterLOS = {point}
			state.StartedAt = clock()
		else
			table.insert(state.AfterLOS, point)
		end
		send(state, false)
	end

	local function bindCharacter(state, character)
		state.Character = character
		state.Humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
		state.Samples = {}
		state.BaseSpeed, state.SprintSpeed, state.SprintObserved = nil, nil, false
		clearTrial(state)
		if not state.Humanoid then return end
		local initial = rawPoint(state)
		if initial then
			if not Tracker.Hunting then learn(state, initial.s) end
			append(state, initial)
		end
		remember(state.Humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			if Tracker.Running and Tracker.States[state.Player] == state then sample(state) end
		end))
	end

	local function track(player)
		local state = {Player = player, Samples = {}, InLOS = false}
		Tracker.States[player] = state
		bindCharacter(state, player.Character)
		remember(player.CharacterAdded:Connect(function(character)
			bindCharacter(state, character)
		end))
	end

	for _, player in ipairs(Players:GetPlayers()) do track(player) end
	remember(Players.PlayerAdded:Connect(track))
	remember(Players.PlayerRemoving:Connect(function(player)
		Tracker.States[player] = nil
	end))

	Tracker.Disconnect = Traffic:Receive("PlayerSpeed", function(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "HuntingState" then
			Tracker.Hunting = payload.Hunting == true
			for _, state in pairs(Tracker.States) do
				clearTrial(state)
				if not Tracker.Hunting then sample(state) end
			end
			return
		end
		if signal ~= "PlayerLineOfSight" or not Tracker.Hunting then return end
		local state = Tracker.States[payload.Player]
		if not state then return end
		if payload.LineOfSight == true then
			state.InLOS = true
			sample(state)
		elseif state.InLOS then
			local point = rawPoint(state)
			if point and state.BeforeLOS then
				append(state, point)
				table.insert(state.AfterLOS, point)
				send(state, true)
			end
			clearTrial(state)
		end
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
		table.clear(self.States)
	end

	return Tracker
end
