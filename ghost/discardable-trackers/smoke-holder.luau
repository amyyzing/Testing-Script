return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "smoke-holder requires Traffic")
	local World = dependencies.Workspace or workspace
	local clock = dependencies.Clock or os.clock
	local delay = dependencies.Delay or task.delay
	local window = tonumber(dependencies.Window) or 3
	local originTolerance = tonumber(dependencies.OriginTolerance) or 2
	local Tracker = {
		Kind = "discardable",
		Running = true,
		Active = {},
		Completed = {},
		RecentMoves = {},
		LastSmoke = nil,
		LastSmokeAt = nil,
	}

	local function isSmoke(object)
		return object and string.lower(object.Name):gsub("%s", "") == "smokeholder"
	end

	local function existingSmoke()
		return World:FindFirstChild("SmokeHolder", true)
			or World:FindFirstChild("Smoke Holder", true)
	end

	local function rememberSmoke(object)
		if not isSmoke(object) then return end
		local position = object:IsA("BasePart") and object.Position
			or object:IsA("Model") and object:GetPivot().Position
		if not position then return end
		if Tracker.LastSmoke ~= object then Tracker.LastSmokeAt = clock() end
		Tracker.LastSmoke, Tracker.LastSmokePosition = object, position
	end

	local function matchingSmoke(payload, scanExisting)
		local function matches()
			local position, origin = Tracker.LastSmokePosition, payload.From
			local age = Tracker.LastSmokeAt and clock() - Tracker.LastSmokeAt
			if not position or not origin or not age or age < 0 or age > window then return false end
			local dx, dy, dz = position.X - origin.X, position.Y - origin.Y, position.Z - origin.Z
			return dx * dx + dy * dy + dz * dz <= originTolerance * originTolerance
		end
		if Tracker.LastSmoke then rememberSmoke(Tracker.LastSmoke) end
		if matches() then return Tracker.LastSmoke end
		if not scanExisting then return nil end
		local object = existingSmoke()
		if object then rememberSmoke(object) end
		return matches() and Tracker.LastSmoke or nil
	end

	local function publish(payload, found, smoke)
		Tracker.Completed[payload.EventId] = true
		Traffic("SmokeHolderResult", {
			EventId = payload.EventId, Teleport = payload, Found = found, SmokeHolder = smoke,
		}):SendTo("Entity")
	end

	local function pruneMoves()
		for index = #Tracker.RecentMoves, 1, -1 do
			if clock() - Tracker.RecentMoves[index].At > window then table.remove(Tracker.RecentMoves, index) end
		end
		while #Tracker.RecentMoves > 128 do table.remove(Tracker.RecentMoves, 1) end
	end

	local function finish(id, found, smoke)
		local probe = Tracker.Active[id]
		if not probe then return end
		Tracker.Active[id] = nil
		publish(probe.Teleport, found, smoke)
	end

	Tracker.DisconnectTraffic = Traffic:Receive("SmokeHolder", function(signal, payload)
		if (signal ~= "ItemTeleported" and signal ~= "ItemMoved") or type(payload) ~= "table" then return end
		local id = payload.EventId
		if not id or Tracker.Active[id] or Tracker.Completed[id] then return end
		local smoke = matchingSmoke(payload, signal == "ItemTeleported")
		if signal == "ItemMoved" then
			if smoke then publish(payload, true, smoke)
			else
				table.insert(Tracker.RecentMoves, {Teleport = payload, At = clock()})
				pruneMoves()
			end
			return
		end
		Tracker.Active[id] = {Teleport = payload, Started = clock()}
		if smoke then
			finish(id, true, smoke)
		else
			delay(window, function()
				if not Tracker.Running or not Tracker.Active[id] then return end
				local finalSmoke = matchingSmoke(payload, true)
				finish(id, finalSmoke ~= nil, finalSmoke)
			end)
		end
	end)
	local initialSmoke = existingSmoke()
	if initialSmoke then rememberSmoke(initialSmoke) end

	Tracker.Connection = World.DescendantAdded:Connect(function(object)
		if not Tracker.Running or not isSmoke(object) then return end
		rememberSmoke(object)
		for id, probe in pairs(Tracker.Active) do
			local smoke = matchingSmoke(probe.Teleport)
			if smoke then finish(id, true, smoke) end
		end
		pruneMoves()
		for index = #Tracker.RecentMoves, 1, -1 do
			local payload = Tracker.RecentMoves[index].Teleport
			local smoke = matchingSmoke(payload)
			if smoke then
				table.remove(Tracker.RecentMoves, index)
				if not Tracker.Completed[payload.EventId] then publish(payload, true, smoke) end
			end
		end
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.DisconnectTraffic()
		self.Connection:Disconnect()
		table.clear(self.Active)
		table.clear(self.Completed)
		table.clear(self.RecentMoves)
		self.LastSmoke, self.LastSmokeAt, self.LastSmokePosition = nil, nil, nil
	end

	return Tracker
end
