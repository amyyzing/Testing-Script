return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "cross-burn requires Traffic")
	local World = dependencies.Workspace or workspace
	local defer = dependencies.Defer or task.defer
	local Tracker = {
		Kind = "active",
		Running = true,
		Connections = {},
		Bound = setmetatable({}, {__mode = "k"}),
		Burning = setmetatable({}, {__mode = "k"}),
	}

	local function remember(connection)
		table.insert(Tracker.Connections, connection)
	end

	function Tracker:Check(cross)
		local disabled = cross:GetAttribute("EquipDisabled") == true
		if disabled and not self.Burning[cross] then
			Traffic("CrossBurn", {
				Cross = cross,
				EquipDisabled = true,
			}):SendTo("CrossAnimation")
		end
		self.Burning[cross] = disabled
	end

	function Tracker:Bind(cross)
		if not cross:IsA("Model")
			or cross:GetAttribute("ItemName") ~= "Cross"
			or self.Bound[cross] then return end
		self.Bound[cross] = true
		remember(cross:GetAttributeChangedSignal("EquipDisabled"):Connect(function()
			if self.Running then self:Check(cross) end
		end))
		self:Check(cross)
	end

	function Tracker:BindItems(items)
		for _, child in ipairs(items:GetChildren()) do self:Bind(child) end
		remember(items.ChildAdded:Connect(function(child)
			defer(function()
				if self.Running and child.Parent == items then self:Bind(child) end
			end)
		end))
	end

	local items = World:FindFirstChild("Items")
	if items then Tracker:BindItems(items) end
	remember(World.ChildAdded:Connect(function(child)
		if Tracker.Running and child.Name == "Items" then Tracker:BindItems(child) end
	end))

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
	end

	return Tracker
end
