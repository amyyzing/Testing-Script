return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "kill-count requires Traffic")
	local Players = dependencies.Players or game:GetService("Players")
	local Tracker = {Kind = "active", Running = true, Alive = {}, Dead = {}, Connections = {}}

	local function remove(list, value)
		local index = table.find(list, value)
		if index then table.remove(list, index) end
	end

	local function killed(player, emit)
		local id = player.UserId
		remove(Tracker.Alive, id)
		if not table.find(Tracker.Dead, id) then
			table.insert(Tracker.Dead, id)
			if emit then
				Traffic("PlayerKilled", {userId = id, Time = os.clock()}):SendTo("SpeedTracker")
			end
		end
	end

	local function update(player, emit)
		if player:GetAttribute("Dead") == true then
			killed(player, emit)
		elseif not table.find(Tracker.Alive, player.UserId) then
			table.insert(Tracker.Alive, player.UserId)
		end
	end

	local function remember(player, connection)
		if connection then table.insert(Tracker.Connections[player], connection) end
	end

	local function bindCharacter(player, character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			remember(player, humanoid.Died:Connect(function() killed(player, true) end))
			return
		end
		if not character then return end
		local connection
		connection = character.ChildAdded:Connect(function(child)
			if not child:IsA("Humanoid") then return end
			connection:Disconnect()
			remember(player, child.Died:Connect(function() killed(player, true) end))
		end)
		remember(player, connection)
	end

	local function track(player)
		Tracker.Connections[player] = {}
		update(player, false)
		remember(player, player:GetAttributeChangedSignal("Dead"):Connect(function()
			update(player, true)
		end))
		bindCharacter(player, player.Character)
		remember(player, player.CharacterAdded:Connect(function(character)
			bindCharacter(player, character)
		end))
	end

	local function untrack(player)
		remove(Tracker.Alive, player.UserId)
		for _, connection in ipairs(Tracker.Connections[player] or {}) do connection:Disconnect() end
		Tracker.Connections[player] = nil
	end

	for _, player in ipairs(Players:GetPlayers()) do track(player) end
	Tracker.PlayerAdded = Players.PlayerAdded:Connect(track)
	Tracker.PlayerRemoving = Players.PlayerRemoving:Connect(untrack)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.PlayerAdded:Disconnect()
		self.PlayerRemoving:Disconnect()
		for _, connections in pairs(self.Connections) do
			for _, connection in ipairs(connections) do connection:Disconnect() end
		end
		table.clear(self.Connections)
	end

	return Tracker
end
