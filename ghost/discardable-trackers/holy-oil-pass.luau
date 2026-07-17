return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "holy-oil-pass requires Traffic")
	local Ghost = assert(dependencies.Ghost, "holy-oil-pass requires Ghost")
	local Tracker = {
		Kind = "discardable",
		Running = true,
		Connections = {},
		Bound = setmetatable({}, {__mode = "k"}),
	}

	local function stop(result)
		if not Tracker.Running then return end
		Tracker.Running = false
		Tracker.Result = result
		Tracker.Disconnect()
		for _, connection in ipairs(Tracker.Connections) do connection:Disconnect() end
		table.clear(Tracker.Connections)
	end

	local function bind(oil)
		local wall = oil and oil:FindFirstChild("GhostWall", true)
		if not wall or not wall:IsA("BasePart") or Tracker.Bound[wall] then return end
		Tracker.Bound[wall] = true
		table.insert(Tracker.Connections, wall.Touched:Connect(function(hit)
			if not Tracker.Running or oil:GetAttribute("Burning") ~= true or not hit then return end
			local touchedGhost = hit == Ghost
				or hit.IsDescendantOf and hit:IsDescendantOf(Ghost)
			if not touchedGhost then return end
			Traffic("HolyOilPassed", {
				HolyOil = oil,
				GhostWall = wall,
				Passed = true,
			}):SendTo("CatchFire")
			stop("passed")
		end))
	end

	Tracker.Disconnect = Traffic:Receive("HolyOilPass", function(signal, payload)
		if signal == "WispCollisionConfirmed" then
			stop("unneeded")
		elseif signal == "HolyOilActivated" and type(payload) == "table" then
			bind(payload.HolyOil)
		end
	end)

	function Tracker:Destroy() stop("destroyed") end
	return Tracker
end
