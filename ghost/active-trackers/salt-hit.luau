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
		Watched = setmetatable({}, {__mode = "k"}),
		Touched = setmetatable({}, {__mode = "k"}),
		Disturbed = setmetatable({}, {__mode = "k"}),
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

	local function hasDisturbed(salt)
		if isDisturbed(salt) then return true end
		for _, object in ipairs(salt:GetDescendants()) do
			if isDisturbed(object) then return true end
		end
		return false
	end

	local function payloadFor(tracker, salt)
		tracker.NextContactId += 1
		return {
			ContactId = tracker.NextContactId,
			Salt = salt,
			Hunting = Ghost:GetAttribute("Hunting") == true,
			Time = os.clock(),
		}
	end

	function Tracker:Report(part)
		local salt = saltObject(part)
		if self.Touched[salt] then return end
		self.Touched[salt] = true
		local payload = payloadFor(self, salt)
		Traffic("SaltHit", payload):SendTo("SaltStateAfterHit", "SpeedTracker")
	end

	function Tracker:ReportDisturbed(object)
		local salt = saltObject(object)
		if self.Disturbed[salt] then return end
		self.Disturbed[salt] = true
		local payload = payloadFor(self, salt)
		Traffic("SaltHit", payload):SendTo("SpeedTracker")
		Traffic("SaltStateAfterHit", {
			ContactId = payload.ContactId,
			Salt = salt,
			HuntingAtHit = payload.Hunting,
			State = "disturbed",
			ObservedFor = 0,
		}):SendTo("SpeedTracker")
	end

	function Tracker:Watch(object)
		if not object:IsA("Model") or self.Watched[object] then return end
		self.Watched[object] = true
		table.insert(self.Connections, object:GetPropertyChangedSignal("Name"):Connect(function()
			if self.Running and isDisturbed(object) then self:ReportDisturbed(object) end
		end))
	end

	function Tracker:Bind(part)
		self:Watch(part)
		if not part:IsA("BasePart") or self.Bound[part] then return end
		if hasDisturbed(saltObject(part)) then
			self:ReportDisturbed(part)
			return
		end
		self.Bound[part] = true
		table.insert(self.Connections, part.Touched:Connect(function(hit)
			if self.Running and hit and hit:IsDescendantOf(Ghost) then
				self:Report(part)
			end
		end))
	end

	local overlap = (dependencies.NewOverlapParams or OverlapParams.new)()
	overlap.FilterType = dependencies.IncludeFilterType or Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = {Ghost}
	overlap.MaxParts = 1
	local elapsed = 0
	table.insert(Tracker.Connections, RunService.Heartbeat:Connect(function(deltaTime)
		if not Tracker.Running then return end
		elapsed += deltaTime
		if elapsed < 0.1 then return end
		elapsed = 0
		for part in pairs(Tracker.Bound) do
			local salt = saltObject(part)
			if part.Parent and hasDisturbed(salt) then
				Tracker:ReportDisturbed(salt)
			elseif part.Parent and not Tracker.Touched[salt] then
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
		Tracker:Watch(object)
		local salt = saltObject(object)
		if isDisturbed(object) or hasDisturbed(salt) then
			Tracker:ReportDisturbed(object)
		else
			Tracker:Bind(object)
		end
	end))

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
	end

	return Tracker
end
