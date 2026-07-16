return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "kill-count requires Traffic")
	local Players = dependencies.Players or game:GetService("Players")
	local Tracker = {Kind = "active", Running = true, Alive = {}, Dead = {}, Connections = {}}

	local function remove(list, value)
		local index = table.find(list, value)
		if index then table.remove(list, index) end
	end

	local function update(player, emit)
		local id = player.UserId
		if player:GetAttribute("Dead") == true then
			remove(Tracker.Alive, id)
			if not table.find(Tracker.Dead, id) then
				table.insert(Tracker.Dead, id)
				if emit then
					Traffic("PlayerKilled", {userId = id, Time = os.clock()}):SendTo("SpeedTracker")
				end
			end
		elseif not table.find(Tracker.Alive, id) then
			table.insert(Tracker.Alive, id)
		end
	end

	local function track(player)
		update(player, false)
		Tracker.Connections[player] = player:GetAttributeChangedSignal("Dead"):Connect(function()
			update(player, true)
		end)
	end

	local function untrack(player)
		remove(Tracker.Alive, player.UserId)
		local connection = Tracker.Connections[player]
		if connection then connection:Disconnect() end
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
		for _, connection in pairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
	end

	return Tracker
end
