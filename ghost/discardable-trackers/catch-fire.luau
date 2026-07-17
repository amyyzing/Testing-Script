return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "catch-fire requires Traffic")
	local Ghost = assert(dependencies.Ghost, "catch-fire requires Ghost")
	local delay = dependencies.DelayTask or task and task.delay
	assert(type(delay) == "function", "catch-fire requires task.delay")
	local probeSeconds = tonumber(dependencies.ProbeSeconds) or 0.5
	local Tracker = {Kind = "discardable", Running = true, Connections = {}}

	local function isFire(object)
		return object.Name == "Fire" and object:IsA("ParticleEmitter")
	end

	local function hasFire()
		for _, object in ipairs(Ghost:GetDescendants()) do
			if isFire(object) then return true end
		end
		return false
	end

	local function stop(result)
		if not Tracker.Running then return end
		Tracker.Running = false
		Tracker.Result = result
		Tracker.Disconnect()
		for _, connection in ipairs(Tracker.Connections) do connection:Disconnect() end
		table.clear(Tracker.Connections)
	end

	local function finish(caughtFire, payload)
		if not Tracker.Running then return end
		stop(caughtFire)
		Traffic("HolyOilFireResult", {
			HolyOil = payload.HolyOil,
			CaughtFire = caughtFire,
		}):SendTo("Wisp", "Skinwalker")
	end

	local function probe(payload)
		if Tracker.Pending then return end
		Tracker.Pending = true
		if hasFire() then finish(true, payload) return end
		table.insert(Tracker.Connections, Ghost.DescendantAdded:Connect(function(object)
			if Tracker.Running and isFire(object) then finish(true, payload) end
		end))
		delay(probeSeconds, function()
			if Tracker.Running then finish(hasFire(), payload) end
		end)
	end

	Tracker.Disconnect = Traffic:Receive("CatchFire", function(signal, payload)
		if signal == "WispCollisionConfirmed" then
			stop("unneeded")
		elseif signal == "HolyOilPassed" and type(payload) == "table"
			and payload.Passed == true then
			probe(payload)
		end
	end)

	function Tracker:Destroy() stop("destroyed") end
	return Tracker
end
