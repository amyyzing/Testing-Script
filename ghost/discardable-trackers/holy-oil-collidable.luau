return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "holy-oil-collidable requires Traffic")
	local Tracker = {Kind = "discardable", Running = true}

	local function stop()
		if not Tracker.Running then return end
		Tracker.Running = false
		Tracker.Disconnect()
	end

	Tracker.Disconnect = Traffic:Receive("HolyOilCollidable", function(signal, payload)
		if signal ~= "HolyOilActivated" or type(payload) ~= "table" then return end
		local oil = payload.HolyOil
		local wall = oil and oil:FindFirstChild("GhostWall", true)
		if not wall or not wall:IsA("BasePart") then return end
		local canCollide = wall.CanCollide == true
		Tracker.Result = canCollide
		Traffic("HolyOilCollidable", {
			HolyOil = oil,
			GhostWall = wall,
			CanCollide = canCollide,
		}):SendTo("Wisp")
		if not canCollide then
			Traffic("WispCollisionConfirmed", {}):SendTo("HolyOilPass", "CatchFire")
		end
		stop()
	end)

	function Tracker:Destroy() stop() end
	return Tracker
end
