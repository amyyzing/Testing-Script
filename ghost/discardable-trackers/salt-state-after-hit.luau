return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "salt-state-after-hit requires Traffic")
	local delaySeconds = tonumber(dependencies.Delay) or 1.25
	local Tracker = {Kind = "discardable", Active = {}}

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

	local function runOnce(payload)
		local id = payload.ContactId
		local probe = {Destroyed = false}
		Tracker.Active[id] = probe
		task.spawn(function()
			local disturbed = isSaltDisturbed(payload.Salt)
			local deadline = os.clock() + delaySeconds
			while not probe.Destroyed and not disturbed and os.clock() < deadline do
				task.wait(0.05)
				disturbed = isSaltDisturbed(payload.Salt)
			end
			if probe.Destroyed then return end
			Traffic("SaltStateAfterHit", {
				ContactId = id,
				Salt = payload.Salt,
				HuntingAtHit = payload.Hunting == true,
				State = disturbed and "disturbed" or "undisturbed",
				ObservedFor = delaySeconds,
			}):SendTo("SpeedTracker")
			probe.Destroyed = true
			Tracker.Active[id] = nil
		end)
	end

	Tracker.Disconnect = Traffic:Receive("SaltStateAfterHit", function(signal, payload)
		if signal == "SaltHit" and payload and payload.ContactId then runOnce(payload) end
	end)

	function Tracker:Destroy()
		self.Disconnect()
		for _, probe in pairs(self.Active) do probe.Destroyed = true end
		table.clear(self.Active)
	end

	return Tracker
end
