return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "evidence-state requires Traffic")
	local Player = assert(dependencies.Player, "evidence-state requires Player")
	local RunService = dependencies.RunService
	local defer = dependencies.Defer or task and task.defer or function(callback) callback() end
	local tracker = {
		Connections = {},
		ContainerConnections = {},
		RowConnections = {},
		Pending = {},
		Destroyed = false,
	}

	local function connect(signal, callback, list)
		if not signal then return nil end
		local connection = signal:Connect(callback)
		table.insert(list or tracker.Connections, connection)
		return connection
	end

	local function evidenceContainer()
		local node = Player:FindFirstChildOfClass("PlayerGui")
		for _, name in ipairs({
			"Journal", "Holder", "Pages", "Page4", "Left", "Page", "EvidenceTypes",
		}) do
			node = node and node:FindFirstChild(name)
		end
		return node
	end

	local function controls(row)
		local container = row and row:FindFirstChild("Container") or row
		return container and container:FindFirstChild("Highlight"),
			container and container:FindFirstChild("CrossOut")
	end

	local function publish(row)
		if tracker.Destroyed or not row or not row.Parent
			or not tracker.RowConnections[row] then return end
		local highlight, crossOut = controls(row)
		local state
		if highlight and highlight.Visible then
			state = true
		elseif crossOut and crossOut.Visible then
			state = false
		end
		Traffic("EvidenceState", {
			Evidence = row.Name,
			State = state,
		}):SendTo("Verdict")
	end

	local function queuePublish(row)
		if tracker.Destroyed or tracker.Pending[row] then return end
		tracker.Pending[row] = true
		defer(function()
			tracker.Pending[row] = nil
			if tracker.Destroyed then return end
			publish(row)
		end)
	end

	local function bindRow(row)
		if tracker.Destroyed then return end
		local highlight, crossOut = controls(row)
		if not highlight and not crossOut then return end
		local connections = {}
		tracker.RowConnections[row] = connections
		if highlight then
			connect(highlight:GetPropertyChangedSignal("Visible"), function()
				queuePublish(row)
			end, connections)
		end
		if crossOut then
			connect(crossOut:GetPropertyChangedSignal("Visible"), function()
				queuePublish(row)
			end, connections)
		end
		queuePublish(row)
	end

	local function bindContainer(container)
		if tracker.Destroyed or tracker.Container == container then return end
		for _, connection in ipairs(tracker.ContainerConnections) do connection:Disconnect() end
		table.clear(tracker.ContainerConnections)
		for _, connections in pairs(tracker.RowConnections) do
			for _, connection in ipairs(connections) do connection:Disconnect() end
		end
		table.clear(tracker.RowConnections)
		tracker.Container = container
		for _, row in ipairs(container:GetChildren()) do bindRow(row) end
		connect(container.ChildAdded, bindRow, tracker.ContainerConnections)
		connect(container.ChildRemoved, function(row)
			local connections = tracker.RowConnections[row]
			for _, connection in ipairs(connections or {}) do connection:Disconnect() end
			tracker.RowConnections[row] = nil
		end, tracker.ContainerConnections)
	end

	function tracker:Refresh()
		if self.Destroyed then return false end
		local container = evidenceContainer()
		if container then bindContainer(container) end
		return container ~= nil
	end

	function tracker:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		for _, connection in ipairs(self.ContainerConnections) do connection:Disconnect() end
		for _, connections in pairs(self.RowConnections) do
			for _, connection in ipairs(connections) do connection:Disconnect() end
		end
		table.clear(self.Connections)
		table.clear(self.ContainerConnections)
		table.clear(self.RowConnections)
	end

	tracker:Refresh()
	if RunService and RunService.Heartbeat then
		local elapsed = 0
		connect(RunService.Heartbeat, function(delta)
			if tracker.Container and tracker.Container.Parent then return end
			elapsed += math.max(0, tonumber(delta) or 0)
			if elapsed >= 0.5 then
				elapsed = 0
				tracker:Refresh()
			end
		end)
	end
	return tracker
end
