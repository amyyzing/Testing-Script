return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "round-started requires Traffic")
	local World = dependencies.Workspace or workspace
	local clock = dependencies.Clock or os.clock
	local Tracker = {
		Kind = "discardable",
		Running = true,
		Started = false,
		Connections = {},
	}

	local function disconnectAll()
		for _, connection in ipairs(Tracker.Connections) do connection:Disconnect() end
		table.clear(Tracker.Connections)
	end

	local function publish()
		Traffic("RoundStarted", {
			Started = Tracker.Started,
			Time = clock(),
		}):SendTo("RoomTemperature")
	end

	function Tracker:Start()
		if self.Started or not self.Running then return self.Started end
		self.Started = true
		self.StartedAt = clock()
		publish()
		self.Running = false
		disconnectAll()
		return true
	end

	local function check(door)
		if not Tracker.Running or Tracker.Started
			or door:GetAttribute("DoorClosed") ~= false then return end
		Tracker:Start()
	end

	local function bindDoor(door)
		local key = string.lower(door.Name):gsub("[^%w]", "")
		local kind = string.lower(tostring(
			door:GetAttribute("DoorType") or door:GetAttribute("Type") or ""
		)):gsub("[^%w]", "")
		local isExit = string.find(key, "exitdoor", 1, true) ~= nil
			or door:GetAttribute("IsExitDoor") == true
			or door:GetAttribute("ExitDoor") == true
			or kind == "exit" or kind == "exitdoor"
		if not Tracker.Running or not isExit then return end
		table.insert(Tracker.Connections,
			door:GetAttributeChangedSignal("DoorClosed"):Connect(function()
				check(door)
			end))
		check(door)
	end

	local function bindDoors(doors)
		for _, door in ipairs(doors:GetChildren()) do bindDoor(door) end
		if not Tracker.Running then return end
		table.insert(Tracker.Connections, doors.ChildAdded:Connect(bindDoor))
	end

	publish()
	local doors = World:FindFirstChild("Doors")
	if doors then
		bindDoors(doors)
	else
		table.insert(Tracker.Connections, World.ChildAdded:Connect(function(child)
			if child.Name == "Doors" then bindDoors(child) end
		end))
	end

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		disconnectAll()
	end

	return Tracker
end
