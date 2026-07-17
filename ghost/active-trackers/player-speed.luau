return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "player-speed requires Traffic")
	local Players = dependencies.Players or game:GetService("Players")
	local UserInputService = dependencies.UserInputService
	local defer = dependencies.Defer or task.defer
	local clock = dependencies.Clock or os.clock
	local customSprinting = dependencies.ReadSprinting
	local Tracker = {
		Kind = "active",
		Running = true,
		States = setmetatable({}, {__mode = "k"}),
		Connections = {},
	}

	local function remember(connection)
		table.insert(Tracker.Connections, connection)
	end

	local function sprinting(player, humanoid)
		if customSprinting then return customSprinting(player, humanoid) == true end
		for _, owner in ipairs({player, humanoid}) do
			if owner then
				for _, name in ipairs({"Sprinting", "IsSprinting", "Sprint"}) do
					local value = owner:GetAttribute(name)
					if type(value) == "boolean" then return value end
				end
			end
		end
		if player == Players.LocalPlayer and UserInputService and humanoid then
			local moving = humanoid.MoveDirection.Magnitude > 0.05
			return moving and (UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift))
		end
		return false
	end

	local function send(state, completed)
		if not state.BeforeLOS then return end
		Traffic("PlayerLOSSpeed", {
			Player = state.Player,
			beforeLOS = state.BeforeLOS,
			afterLOS = state.AfterLOS,
			ContinuousSprinting = state.ContinuousSprinting,
			Duration = math.max(0, clock() - state.StartedAt),
			completed = completed == true,
		}):SendTo("LOSSpeed")
	end

	local function rawPoint(state)
		local speed = state.Humanoid and tonumber(state.Humanoid.WalkSpeed)
		if not speed then return nil end
		return {s = speed, sprinting = sprinting(state.Player, state.Humanoid)}
	end

	local function append(state, point)
		table.insert(state.Samples, point)
		while #state.Samples > 40 do table.remove(state.Samples, 1) end
	end

	local function beginTrial(state, point)
		state.BeforeLOS = table.clone(state.Samples)
		state.AfterLOS = {point}
		state.ContinuousSprinting = true
		state.StartedAt = clock()
		send(state, false)
	end

	local function sample(state)
		local point = rawPoint(state)
		if not point then return end
		append(state, point)
		if not state.InLOS then return end
		if not state.BeforeLOS then
			if point.sprinting then beginTrial(state, point) end
			return
		end
		table.insert(state.AfterLOS, point)
		if not point.sprinting then
			state.ContinuousSprinting = false
			send(state, true)
			state.BeforeLOS, state.AfterLOS, state.StartedAt = nil, nil, nil
			return
		end
		send(state, false)
	end

	local function queueSample(state)
		if state.Pending or not Tracker.Running then return end
		state.Pending = true
		defer(function()
			state.Pending = false
			if Tracker.Running and Tracker.States[state.Player] == state then sample(state) end
		end)
	end

	local function bindCharacter(state, character)
		state.Character = character
		state.Humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
		state.Samples = {}
		state.BeforeLOS, state.AfterLOS, state.StartedAt = nil, nil, nil
		if not state.Humanoid then return end
		local initial = rawPoint(state)
		if initial then append(state, initial) end
		remember(state.Humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			queueSample(state)
		end))
		for _, name in ipairs({"Sprinting", "IsSprinting", "Sprint"}) do
			remember(state.Humanoid:GetAttributeChangedSignal(name):Connect(function()
				queueSample(state)
			end))
		end
	end

	local function track(player)
		local state = {Player = player, Samples = {}, InLOS = false}
		Tracker.States[player] = state
		for _, name in ipairs({"Sprinting", "IsSprinting", "Sprint"}) do
			remember(player:GetAttributeChangedSignal(name):Connect(function()
				queueSample(state)
			end))
		end
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
		if signal ~= "PlayerLineOfSight" or type(payload) ~= "table" then return end
		local state = Tracker.States[payload.Player]
		if not state then return end
		local visible = payload.LineOfSight == true
		if not visible then
			if state.InLOS and state.BeforeLOS then
				local point = rawPoint(state)
				if point then
					append(state, point)
					table.insert(state.AfterLOS, point)
					if not point.sprinting then state.ContinuousSprinting = false end
				end
				send(state, true)
			end
			state.InLOS = false
			state.BeforeLOS, state.AfterLOS, state.StartedAt = nil, nil, nil
			return
		end
		state.InLOS = true
		sample(state)
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
