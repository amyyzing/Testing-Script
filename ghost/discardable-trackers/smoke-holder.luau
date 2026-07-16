return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "smoke-holder requires Traffic")
	local World = dependencies.Workspace or workspace
	local clock = dependencies.Clock or os.clock
	local delay = dependencies.Delay or task.delay
	local window = tonumber(dependencies.Window) or 3
	local Tracker = {
		Kind = "discardable",
		Running = true,
		Active = {},
		Completed = {},
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

	local function finish(id, found, smoke)
		local probe = Tracker.Active[id]
		if not probe then return end
		Tracker.Active[id] = nil
		Tracker.Completed[id] = true
		Traffic("SmokeHolderResult", {
			EventId = id,
			Teleport = probe.Teleport,
			Found = found,
			SmokeHolder = smoke,
		}):SendTo("Entity")
	end

	Tracker.DisconnectTraffic = Traffic:Receive("SmokeHolder", function(signal, payload)
		if signal ~= "ItemTeleported" or type(payload) ~= "table" then return end
		local id = payload.EventId
		if not id or Tracker.Active[id] or Tracker.Completed[id] then return end
		Tracker.Active[id] = {Teleport = payload, Started = clock()}
		local smoke = existingSmoke()
		if not smoke and Tracker.LastSmokeAt
			and clock() - Tracker.LastSmokeAt <= window then smoke = Tracker.LastSmoke end
		if smoke then
			finish(id, true, smoke)
		else
			delay(window, function()
				if not Tracker.Running or not Tracker.Active[id] then return end
				local finalSmoke = existingSmoke()
				finish(id, finalSmoke ~= nil, finalSmoke)
			end)
		end
	end)

	Tracker.Connection = World.DescendantAdded:Connect(function(object)
		if not Tracker.Running or not isSmoke(object) then return end
		Tracker.LastSmoke, Tracker.LastSmokeAt = object, clock()
		for id in pairs(Tracker.Active) do finish(id, true, object) end
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.DisconnectTraffic()
		self.Connection:Disconnect()
		table.clear(self.Active)
		table.clear(self.Completed)
	end

	return Tracker
end
