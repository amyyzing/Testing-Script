return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "holy-oil-activate requires Traffic")
	local World = dependencies.Workspace or workspace
	local Tracker = {
		Kind = "dormant",
		Running = true,
		Connections = {},
		Bound = setmetatable({}, {__mode = "k"}),
		Activated = setmetatable({}, {__mode = "k"}),
	}

	local function isOil(object)
		if not object:IsA("Model") then return false end
		local itemName = object:GetAttribute("ItemName")
		return object.Name == "HolyOil" or itemName == "Holy Oil" or itemName == "HolyOil"
	end

	local function evaluate(oil)
		if not Tracker.Running or Tracker.Activated[oil]
			or oil:GetAttribute("Burning") ~= true
			or not oil:FindFirstChild("GhostWall", true) then return end
		Tracker.Activated[oil] = true
		Traffic("HolyOilActivated", {
			HolyOil = oil,
			Burning = true,
		}):SendTo("HolyOilCollidable", "HolyOilPass")
	end

	local function bindOil(oil)
		if not Tracker.Running or Tracker.Bound[oil] or not isOil(oil) then return end
		Tracker.Bound[oil] = true
		table.insert(Tracker.Connections,
			oil:GetAttributeChangedSignal("Burning"):Connect(function() evaluate(oil) end))
		table.insert(Tracker.Connections,
			oil.DescendantAdded:Connect(function() evaluate(oil) end))
		evaluate(oil)
	end

	local function bindFolder(folder)
		for _, object in ipairs(folder:GetDescendants()) do bindOil(object) end
		table.insert(Tracker.Connections,
			folder.DescendantAdded:Connect(function(object) bindOil(object) end))
	end

	local folder = World:FindFirstChild("HolyOil")
	if folder then bindFolder(folder) end
	table.insert(Tracker.Connections, World.ChildAdded:Connect(function(child)
		if child.Name == "HolyOil" then bindFolder(child) end
	end))

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
	end

	return Tracker
end
