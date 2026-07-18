return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "salt-state-after-hit requires Traffic")
	local delaySeconds = tonumber(dependencies.Delay) or 1.25
	local graceSeconds = tonumber(dependencies.CreationGrace) or 4
	local delay = dependencies.DelayTask or task.delay
	local clock = dependencies.Clock or os.clock
	local Tracker = {Kind = "discardable", Running = true, Active = {}}

	local function isDisturbed(object)
		if object:GetAttribute("Disturbed") == true then return true end
		local name = string.lower(object.Name):gsub("[^%w]", "")
		return string.find(name, "disturbedsalt", 1, true) ~= nil
	end

	local function isSaltDisturbed(salt)
		if not salt then return false end
		if isDisturbed(salt) then return true end
		for _, object in ipairs(salt:GetDescendants()) do
			if isDisturbed(object) then return true end
		end
		return false
	end

	local function finish(id, disturbed, graceComplete)
		local probe = Tracker.Active[id]
		if not probe then return end
		Tracker.Active[id] = nil
		for _, connection in ipairs(probe.Connections) do connection:Disconnect() end
		Traffic("SaltStateAfterHit", {
			ContactId = id,
			Salt = probe.Payload.Salt,
			HuntingAtHit = probe.Payload.Hunting == true,
			State = disturbed and "disturbed" or "undisturbed",
			ObservedFor = disturbed and math.max(0, clock() - probe.StartedAt)
				or probe.WaitSeconds,
			GraceComplete = graceComplete == true,
		}):SendTo("SpeedTracker", "Wraith")
	end

	local function watch(id, object)
		local probe = Tracker.Active[id]
		if not probe or probe.Watched[object] then return end
		probe.Watched[object] = true
		local function changed()
			if isDisturbed(object) then finish(id, true, false) end
		end
		table.insert(probe.Connections, object:GetPropertyChangedSignal("Name"):Connect(changed))
		table.insert(probe.Connections, object:GetAttributeChangedSignal("Disturbed"):Connect(changed))
	end

	local function runOnce(payload)
		local id, salt = payload.ContactId, payload.Salt
		if Tracker.Active[id] then return end
		local now = clock()
		local createdAt = tonumber(payload.SaltCreatedAt) or now
		local waitSeconds = math.max(delaySeconds, createdAt + graceSeconds - now)
		Tracker.Active[id] = {
			Payload = payload,
			StartedAt = now,
			WaitSeconds = waitSeconds,
			Connections = {},
			Watched = setmetatable({}, {__mode = "k"}),
		}
		if isSaltDisturbed(salt) then
			finish(id, true, false)
			return
		end
		watch(id, salt)
		for _, object in ipairs(salt:GetDescendants()) do watch(id, object) end
		table.insert(Tracker.Active[id].Connections, salt.DescendantAdded:Connect(function(object)
			watch(id, object)
			if isDisturbed(object) then finish(id, true, false) end
		end))
		delay(waitSeconds, function()
			if Tracker.Running and Tracker.Active[id] then
				local disturbed = isSaltDisturbed(salt)
				finish(id, disturbed, not disturbed)
			end
		end)
	end

	Tracker.Disconnect = Traffic:Receive("SaltStateAfterHit", function(signal, payload)
		if signal == "SaltHit" and payload and payload.ContactId then runOnce(payload) end
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
		for _, probe in pairs(self.Active) do
			for _, connection in ipairs(probe.Connections) do connection:Disconnect() end
		end
		table.clear(self.Active)
	end

	return Tracker
end
