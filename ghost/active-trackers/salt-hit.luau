return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "salt-hit requires Traffic")
	local Ghost = assert(dependencies.Ghost, "salt-hit requires Ghost")
	local SaltFolder = assert(dependencies.SaltFolder, "salt-hit requires SaltFolder")
	local World = dependencies.Workspace or workspace
	local RunService = assert(dependencies.RunService, "salt-hit requires RunService")
	local Tracker = {
		Kind = "active",
		Running = true,
		Connections = {},
		Bound = setmetatable({}, {__mode = "k"}),
		Touched = setmetatable({}, {__mode = "k"}),
		NextContactId = 0,
	}

	local function saltObject(part)
		local current = part
		while current and current.Parent ~= SaltFolder do
			current = current.Parent
		end
		return current or part
	end

	local function isDisturbed(salt)
		if salt:GetAttribute("Disturbed") == true then return true end
		local name = string.lower(salt.Name):gsub("[^%w]", "")
		return string.find(name, "disturbedsalt", 1, true) ~= nil
	end

	function Tracker:Report(part)
		local salt = saltObject(part)
		if self.Touched[salt] then return end
		self.Touched[salt] = true
		self.NextContactId += 1
		local payload = {
			ContactId = self.NextContactId,
			Salt = salt,
			Hunting = Ghost:GetAttribute("Hunting") == true,
			Time = os.clock(),
		}
		Traffic("SaltHit", payload):SendTo("SaltStateAfterHit", "SpeedTracker")
	end

	function Tracker:Bind(part)
		if not part:IsA("BasePart") or self.Bound[part] then return end
		if isDisturbed(saltObject(part)) then return end
		self.Bound[part] = true
		table.insert(self.Connections, part.Touched:Connect(function(hit)
			if self.Running and hit and hit:IsDescendantOf(Ghost) then
				self:Report(part)
			end
		end))
	end

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = {Ghost}
	overlap.MaxParts = 1
	local elapsed = 0
	table.insert(Tracker.Connections, RunService.Heartbeat:Connect(function(deltaTime)
		if not Tracker.Running then return end
		elapsed += deltaTime
		if elapsed < 0.1 then return end
		elapsed = 0
		for part in pairs(Tracker.Bound) do
			if part.Parent and not Tracker.Touched[saltObject(part)] then
				local touching = World:GetPartBoundsInBox(
					part.CFrame,
					part.Size + Vector3.new(0.6, 1, 0.6),
					overlap
				)
				if #touching > 0 then Tracker:Report(part) end
			end
		end
	end))

	for _, object in ipairs(SaltFolder:GetDescendants()) do Tracker:Bind(object) end
	table.insert(Tracker.Connections, SaltFolder.DescendantAdded:Connect(function(object)
		Tracker:Bind(object)
	end))

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
	end

	return Tracker
end
