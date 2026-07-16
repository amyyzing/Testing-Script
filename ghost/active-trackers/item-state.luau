return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "item-state requires Traffic")
	local World = dependencies.Workspace or workspace
	local Players = dependencies.Players or game:GetService("Players")
	local defer = dependencies.Defer or task.defer
	local clock = dependencies.Clock or os.clock
	local radius = tonumber(dependencies.PlayerRadius) or 15
	local radiusSquared = radius * radius
	local eligible = {
		["Laser Projector"] = true,
		Blacklight = true,
		["Spirit Box"] = true,
	}
	local Tracker = {
		Kind = "active",
		Running = true,
		GhoulResolved = false,
		Connections = {},
		BoundItems = setmetatable({}, {__mode = "k"}),
		BoundStates = setmetatable({}, {__mode = "k"}),
		States = setmetatable({}, {__mode = "k"}),
	}

	local function remember(connection)
		table.insert(Tracker.Connections, connection)
	end

	local function itemPosition(item)
		if item:IsA("BasePart") then return item.Position end
		if item:IsA("Model") then return item:GetPivot().Position end
		return nil
	end

	local function playerIsNear(position)
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("Dead") ~= true then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local dx = root.Position.X - position.X
					local dy = root.Position.Y - position.Y
					local dz = root.Position.Z - position.Z
					if dx * dx + dy * dy + dz * dz <= radiusSquared then return true end
				end
			end
		end
		return false
	end

	function Tracker:BindState(item, state, allowMissing)
		if self.BoundStates[state]
			or (not allowMissing and state:GetAttribute("Enabled") == nil) then return end
		self.BoundStates[state] = true
		self.States[state] = state:GetAttribute("Enabled")
		remember(state:GetAttributeChangedSignal("Enabled"):Connect(function()
			local previous = self.States[state]
			local current = state:GetAttribute("Enabled")
			self.States[state] = current
			if not self.Running or item.Parent ~= self.Items then return end
			if type(previous) == "boolean" and type(current) == "boolean"
				and previous ~= current then
				Traffic("ItemStateChanged", {
					Item = item,
					ItemName = item:GetAttribute("ItemName"),
					Previous = previous,
					Current = current,
					Time = clock(),
				}):SendTo("FlickerArray")
			end
			if self.GhoulResolved or previous ~= true or current ~= false then return end
			local position = itemPosition(item)
			if not position or playerIsNear(position) then return end
			self.GhoulResolved = true
			Traffic("ItemDisabledAwayFromPlayers", {
				Item = item,
				ItemName = item:GetAttribute("ItemName"),
				PlayerRadius = radius,
			}):SendTo("Ghoul")
		end))
	end

	function Tracker:BindItem(item)
		if not item:IsA("Model") or self.BoundItems[item] then return end
		local function bindEligible()
			if not eligible[item:GetAttribute("ItemName")] then return end
			self:BindState(item, item, true)
			for _, object in ipairs(item:GetDescendants()) do self:BindState(item, object) end
		end
		self.BoundItems[item] = true
		remember(item:GetAttributeChangedSignal("ItemName"):Connect(bindEligible))
		remember(item.DescendantAdded:Connect(function(object)
			defer(function()
				if self.Running and item.Parent == self.Items
					and eligible[item:GetAttribute("ItemName")] then
					self:BindState(item, object)
				end
			end)
		end))
		bindEligible()
	end

	function Tracker:BindItems(items)
		if self.Items == items then return end
		self.Items = items
		for _, item in ipairs(items:GetChildren()) do self:BindItem(item) end
		remember(items.ChildAdded:Connect(function(item)
			defer(function()
				if self.Running and item.Parent == items then self:BindItem(item) end
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
		table.clear(self.States)
	end

	return Tracker
end
