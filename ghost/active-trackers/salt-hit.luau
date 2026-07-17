return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "salt-hit requires Traffic")
	local Ghost = assert(dependencies.Ghost, "salt-hit requires Ghost")
	local SaltFolder = assert(dependencies.SaltFolder, "salt-hit requires SaltFolder")
	local World = dependencies.Workspace or workspace
	local RunService = assert(dependencies.RunService, "salt-hit requires RunService")
	local clock = dependencies.Clock or os.clock
	local Tracker = {
		Kind = "active",
		Running = true,
		Connections = {},
		Bound = setmetatable({}, {__mode = "k"}),
		Watched = setmetatable({}, {__mode = "k"}),
		PendingSpatial = setmetatable({}, {__mode = "k"}),
		Touched = setmetatable({}, {__mode = "k"}),
		Disturbed = setmetatable({}, {__mode = "k"}),
		CreatedAt = setmetatable({}, {__mode = "k"}),
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
		tracker.CreatedAt[salt] = tracker.CreatedAt[salt] or clock()
		return {
			ContactId = tracker.NextContactId,
			Salt = salt,
			Hunting = Ghost:GetAttribute("Hunting") == true,
			Time = clock(),
			SaltCreatedAt = tracker.CreatedAt[salt],
		}
	end

	function Tracker:Report(part)
		local salt = saltObject(part)
		if self.Touched[salt] then return end
		self.Touched[salt] = true
		self.PendingSpatial[salt] = nil
		local payload = payloadFor(self, salt)
		Traffic("SaltHit", payload):SendTo("SaltStateAfterHit", "SpeedTracker")
	end

	function Tracker:ReportDisturbed(object)
		local salt = saltObject(object)
		if self.Disturbed[salt] then return end
		self.Disturbed[salt] = true
		self.PendingSpatial[salt] = nil
		local payload = payloadFor(self, salt)
		Traffic("SaltHit", payload):SendTo("SpeedTracker")
		Traffic("SaltStateAfterHit", {
			ContactId = payload.ContactId,
			Salt = salt,
			HuntingAtHit = payload.Hunting,
			State = "disturbed",
			ObservedFor = 0,
			GraceComplete = false,
		}):SendTo("SpeedTracker", "Wraith")
	end

	function Tracker:Watch(object)
		local salt = saltObject(object)
		self.CreatedAt[salt] = self.CreatedAt[salt] or clock()
		if self.Watched[object] then return end
		self.Watched[object] = true
		table.insert(self.Connections, object:GetPropertyChangedSignal("Name"):Connect(function()
			if self.Running and isDisturbed(object) then self:ReportDisturbed(object) end
		end))
		table.insert(self.Connections, object:GetAttributeChangedSignal("Disturbed"):Connect(function()
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
		local salt = saltObject(part)
		self.PendingSpatial[salt] = self.PendingSpatial[salt] or part
		table.insert(self.Connections, part.Touched:Connect(function(hit)
			if self.Running and hit and hit:IsDescendantOf(Ghost) then
				self:Report(part)
			end
		end))
	end

	local queryGhost = dependencies.QueryGhostOverlap
	if not queryGhost then
		local overlap = (dependencies.NewOverlapParams or OverlapParams.new)()
		overlap.FilterType = dependencies.IncludeFilterType or Enum.RaycastFilterType.Include
		overlap.FilterDescendantsInstances = {Ghost}
		overlap.MaxParts = 1
		queryGhost = function(salt, part)
			local cframe, size = part.CFrame, part.Size
			if salt:IsA("Model") then cframe, size = salt:GetBoundingBox() end
			return #World:GetPartBoundsInBox(
				cframe,
				size + Vector3.new(0.6, 1, 0.6),
				overlap
			) > 0
		end
	end

	local function replacementPart(salt)
		if salt:IsA("BasePart") then return salt end
		for _, object in ipairs(salt:GetDescendants()) do
			if object:IsA("BasePart") then return object end
		end
		return nil
	end

	local elapsed = 0
	table.insert(Tracker.Connections, RunService.Heartbeat:Connect(function(deltaTime)
		if not Tracker.Running then return end
		elapsed += deltaTime
		if elapsed < 0.1 then return end
		elapsed = 0
		for salt, part in pairs(Tracker.PendingSpatial) do
			if not salt.Parent or Tracker.Touched[salt] or Tracker.Disturbed[salt] then
				Tracker.PendingSpatial[salt] = nil
			else
				if not part.Parent then
					part = replacementPart(salt)
					Tracker.PendingSpatial[salt] = part
				end
				if part and queryGhost(salt, part) then Tracker:Report(part) end
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
		table.clear(self.CreatedAt)
	end

	return Tracker
end
