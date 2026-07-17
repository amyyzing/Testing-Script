return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "room-temperature requires Traffic")
	local threshold = tonumber(dependencies.Threshold) or 0.08
	local requiredChanges = tonumber(dependencies.RequiredChanges) or 7
	local readTemperature = dependencies.ReadTemperature
	local Tracker = {
		Kind = "dormant",
		Running = true,
		Active = false,
		Resolved = false,
		Changes = {},
	}

	local function disconnectRoom()
		if not Tracker.RoomConnection then return end
		Tracker.RoomConnection:Disconnect()
		Tracker.RoomConnection = nil
	end

	local function temperature(room)
		if readTemperature then return tonumber(readTemperature(room)) end
		return room and tonumber(room:GetAttribute("Temperature")) or nil
	end

	function Tracker:Sample()
		if not self.Active or self.Resolved then return end
		local current = temperature(self.Room)
		if current == nil then
			self.Previous = nil
			return
		end
		if self.Previous ~= nil then
			local decrease = self.Previous - current
			if decrease > 0 then table.insert(self.Changes, decrease) end
		end
		self.Previous = current
		if #self.Changes < requiredChanges then return end

		local sum = 0
		for _, change in ipairs(self.Changes) do sum += change end
		local average = sum / #self.Changes
		Traffic("RoomTemperatureAverage", {
			Room = self.Room,
			RoomName = self.Room and self.Room.Name or nil,
			Changes = table.clone(self.Changes),
			Average = average,
			Threshold = threshold,
			Complete = true,
		}):SendTo("Shadow")
		if average < threshold or average > threshold then
			self.Resolved = true
			self.Active = false
			disconnectRoom()
		else
			table.clear(self.Changes)
		end
	end

	local function setRoom(room)
		if room == Tracker.Room or Tracker.Resolved then return end
		disconnectRoom()
		Tracker.Room = room
		Tracker.Active = room ~= nil
		Tracker.Previous = temperature(room)
		table.clear(Tracker.Changes)
		if Tracker.Active then
			Tracker.RoomConnection = room:GetAttributeChangedSignal("Temperature"):Connect(function()
				Tracker:Sample()
			end)
		end
	end

	Tracker.Disconnect = Traffic:Receive("RoomTemperature", function(signal, payload)
		if signal ~= "GhostRoom" or type(payload) ~= "table" then return end
		setRoom(payload.Room)
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Active = false
		self.Disconnect()
		disconnectRoom()
	end

	return Tracker
end
