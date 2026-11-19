return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "holy-oil-collidable requires Traffic")
	local Ghost = assert(dependencies.Ghost, "holy-oil-collidable requires Ghost")
	local World = dependencies.Workspace or workspace
	local delay = dependencies.DelayTask or (task and task.delay)
	assert(type(delay) == "function", "holy-oil-collidable requires task.delay")
	local Tracker = {Kind = "discardable", Running = true, Connections = {}, Bound = {}}

	local function stop()
		if not Tracker.Running then return end
		Tracker.Running = false
		Tracker.Disconnect()
		for _, connection in ipairs(Tracker.Connections) do connection:Disconnect() end
		table.clear(Tracker.Connections)
		table.clear(Tracker.Bound)
	end

	local function evaluate(oil, state)
		state.Revision += 1
		if not Tracker.Running or not oil:IsDescendantOf(World)
			or Ghost:GetAttribute("Hunting") ~= true or oil:GetAttribute("Burning") ~= true
			or not state.Wall:IsDescendantOf(oil) then return end
		local revision, canCollide = state.Revision, state.Wall.CanCollide
		delay(tonumber(dependencies.StableSeconds) or 0.5, function()
			if not Tracker.Running or state.Revision ~= revision
				or not oil:IsDescendantOf(World) or Ghost:GetAttribute("Hunting") ~= true
				or oil:GetAttribute("Burning") ~= true or not state.Wall:IsDescendantOf(oil)
				or state.Wall.CanCollide ~= canCollide then return end
			Tracker.Result = canCollide
			Traffic("HolyOilCollidable", {
				HolyOil = oil, GhostWall = state.Wall, CanCollide = canCollide,
				Hunting = true, Burning = true,
			}):SendTo("Wisp")
			stop()
		end)
	end

	Tracker.Disconnect = Traffic:Receive("HolyOilCollidable", function(signal, payload)
		if signal ~= "HolyOilActivated" or type(payload) ~= "table" then return end
		local oil = payload.HolyOil
		if not oil or not oil.Parent then return end
		local wall = oil and oil:FindFirstChild("GhostWall", true)
		if not wall or not wall.Parent or not wall:IsA("BasePart") then return end
		if Tracker.Bound[oil] then return end
		local state = {Wall = wall, Revision = 0}
		Tracker.Bound[oil] = state
		local function changed() evaluate(oil, state) end
		table.insert(Tracker.Connections, wall:GetPropertyChangedSignal("CanCollide"):Connect(changed))
		table.insert(Tracker.Connections, wall.AncestryChanged:Connect(changed))
		table.insert(Tracker.Connections, oil.AncestryChanged:Connect(changed))
		table.insert(Tracker.Connections, oil:GetAttributeChangedSignal("Burning"):Connect(changed))
		changed()
	end)
	table.insert(Tracker.Connections, Ghost:GetAttributeChangedSignal("Hunting"):Connect(function()
		for oil, state in pairs(Tracker.Bound) do evaluate(oil, state) end
	end))

	function Tracker:Destroy() stop() end
	return Tracker
end
