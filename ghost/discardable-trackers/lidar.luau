return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "lidar requires Traffic")
	local Ghost = assert(dependencies.Ghost, "lidar requires Ghost")
	local Tracker = {Kind = "active", Running = true, Connections = {}}
	local function scan()
		if not Tracker.Running then return end
		local value = Ghost:GetAttribute("InvisibleOnLIDAR")
		local exists = value ~= nil
		for _, object in ipairs(type(value) ~= "boolean" and Ghost:GetDescendants() or {}) do
			local attribute = object:GetAttribute("InvisibleOnLIDAR")
			local member = object.Name == "InvisibleOnLIDAR" and object:IsA("ValueBase")
			local observed = attribute
			if member then observed = object.Value end
			if attribute ~= nil or member then
				exists = true
				if type(observed) == "boolean" then
					value = observed
					if observed == false then break end
				end
			end
		end
		Tracker.Exists, Tracker.Value = exists, value
		Traffic("LidarState", {Exists = exists, Value = value}):SendTo("Vex")
	end
	local function connect(signal)
		if signal then table.insert(Tracker.Connections, signal:Connect(scan)) end
	end
	local function bind(object)
		if object.GetAttributeChangedSignal then
			connect(object:GetAttributeChangedSignal("InvisibleOnLIDAR"))
		end
		if object.Name == "InvisibleOnLIDAR" and object:IsA("ValueBase")
			and object.GetPropertyChangedSignal then
			connect(object:GetPropertyChangedSignal("Value"))
		end
	end
	bind(Ghost)
	for _, object in ipairs(Ghost:GetDescendants()) do bind(object) end
	if Ghost.DescendantAdded then
		table.insert(Tracker.Connections, Ghost.DescendantAdded:Connect(function(object)
			bind(object)
			scan()
		end))
	end
	scan()
	function Tracker:Destroy()
		self.Running = false
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
	end
	return Tracker
end
