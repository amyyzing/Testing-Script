return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "salt-hit requires Traffic")
	local Ghost = assert(dependencies.Ghost, "salt-hit requires Ghost")
	local SaltFolder = assert(dependencies.SaltFolder, "salt-hit requires SaltFolder")
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
		self.Bound[part] = true
		table.insert(self.Connections, part.Touched:Connect(function(hit)
			if self.Running and hit and hit:IsDescendantOf(Ghost) then
				self:Report(part)
			end
		end))
	end

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
