return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "BrokenGlass requires Events")
	local Specification = type(dependencies.Specification) == "table"
		and dependencies.Specification or {}
	local BansheeSpec = type(Specification.Banshee) == "table"
		and Specification.Banshee or {}

	local BrokenGlass = {}
	BrokenGlass.__index = BrokenGlass

	local function disconnect(connection)
		if connection and type(connection.Disconnect) == "function" then
			pcall(connection.Disconnect, connection)
		end
	end

	local function connect(signal, callback)
		if signal == nil then return nil end
		local ok, connection = pcall(function()
			return signal:Connect(callback)
		end)
		return ok and connection or nil
	end

	local function call(object, method, ...)
		local callback = object and object[method]
		if type(callback) ~= "function" then return nil end
		local ok, result = pcall(callback, object, ...)
		return ok and result or nil
	end

	local function isBrokenGlassModel(object)
		return object ~= nil
			and object.Name == "BrokenGlass"
			and call(object, "IsA", "Model") == true
	end

	function BrokenGlass.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "BrokenGlass",
			Category = "Dormant",
			Status = "Idle",
			RequiredCount = math.max(
				1,
				math.floor(tonumber(options.RequiredCount)
					or tonumber(BansheeSpec.RequiredBrokenGlass) or 2)
			),
			WindowSeconds = math.max(
				0,
				tonumber(options.WindowSeconds)
					or tonumber(BansheeSpec.WindowSeconds) or 5
			),
			_context = nil,
			_connections = {},
			_boundFolders = setmetatable({}, {__mode = "k"}),
			_seen = setmetatable({}, {__mode = "k"}),
			_events = {},
			_armed = true,
			_burstSerial = 0,
			_lastBurst = nil,
		}, BrokenGlass)
	end

	BrokenGlass.New = BrokenGlass.new

	function BrokenGlass:_now(event)
		return tonumber(event and event.Time)
			or (self._context.Clock and self._context.Clock() or os.clock())
	end

	function BrokenGlass:_remember(connection)
		if connection then table.insert(self._connections, connection) end
		return connection
	end

	function BrokenGlass:_trim(now)
		local cutoff = now - self.WindowSeconds
		while self._events[1] and self._events[1].Time < cutoff do
			table.remove(self._events, 1)
		end
		if #self._events < self.RequiredCount then
			self._armed = true
		end
	end

	function BrokenGlass:_emitBurst(now)
		self._burstSerial = self._burstSerial + 1
		local firstIndex = math.max(1, #self._events - self.RequiredCount + 1)
		local first = self._events[firstIndex]
		local models = {}
		for index = firstIndex, #self._events do
			table.insert(models, self._events[index].Model)
		end
		local duration = first and math.max(0, now - first.Time) or 0
		self._lastBurst = {
			BurstId = self._burstSerial,
			Count = #self._events,
			Duration = duration,
			Time = now,
		}
		if type(self._context.Emit) == "function" then
			self._context.Emit({
				Type = Events.Types.BrokenGlassBurst,
				Time = now,
				Source = self.Name,
				Payload = {
					BurstId = self._burstSerial,
					Qualified = true,
					Completed = true,
					Count = #self._events,
					RequiredCount = self.RequiredCount,
					Window = self.WindowSeconds,
					Duration = duration,
					Models = models,
				},
			})
		end
	end

	function BrokenGlass:_record(object, event)
		if not isBrokenGlassModel(object) or self._seen[object] then
			return false
		end
		self._seen[object] = true
		local now = self:_now(event)
		self:_trim(now)
		table.insert(self._events, {Time = now, Model = object})
		self.Status = "Monitoring"
		if self._armed and #self._events >= self.RequiredCount then
			self._armed = false
			self.Status = "Resolved"
			self:_emitBurst(now)
		end
		return true
	end

	function BrokenGlass:_baseline(folder)
		for _, object in ipairs(call(folder, "GetDescendants") or {}) do
			if isBrokenGlassModel(object) then self._seen[object] = true end
		end
		for _, object in ipairs(call(folder, "GetChildren") or {}) do
			if isBrokenGlassModel(object) then self._seen[object] = true end
		end
	end

	function BrokenGlass:_bindFolder(folder)
		if folder == nil or self._boundFolders[folder] then return false end
		self._boundFolders[folder] = true
		self:_baseline(folder)
		self:_remember(connect(folder.DescendantAdded, function(object)
			self:_record(object, {Time = self:_now()})
		end))
		return true
	end

	function BrokenGlass:Start(context)
		if self.Status ~= "Idle" and self.Status ~= "Stopped" then return end
		self._context = context or {}
		self.Status = "Dormant"
		local workspace = self._context.Workspace
		self:_bindFolder(
			self._context.BrokenGlassFolder
				or call(workspace, "FindFirstChild", "BrokenGlass")
		)
		self:_remember(connect(workspace and workspace.ChildAdded, function(child)
			if child.Name == "BrokenGlass" then self:_bindFolder(child) end
		end))
	end

	function BrokenGlass:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or self._context == nil or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind == "BrokenGlassAdded" then
			return self:_record(
				Events.Read(event, "Model") or Events.Read(event, "Object"),
				event
			)
		elseif kind == Events.Types.Tick then
			self:_trim(self:_now(event))
			if self.Status == "Resolved" and self._armed then
				self.Status = "Monitoring"
			end
			return true
		end
		return false
	end

	function BrokenGlass:Stop()
		for _, connection in ipairs(self._connections) do disconnect(connection) end
		table.clear(self._connections)
		-- Start may be called again without a round Reset.  Connections have been
		-- torn down, so folders must be eligible for binding again.
		self._boundFolders = setmetatable({}, {__mode = "k"})
		self.Status = "Stopped"
	end

	function BrokenGlass:Reset()
		self:Stop()
		self._boundFolders = setmetatable({}, {__mode = "k"})
		self._seen = setmetatable({}, {__mode = "k"})
		table.clear(self._events)
		self._armed = true
		self._burstSerial = 0
		self._lastBurst = nil
		self.Status = "Idle"
	end

	function BrokenGlass:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function BrokenGlass:Snapshot()
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			RequiredCount = self.RequiredCount,
			WindowSeconds = self.WindowSeconds,
			EventCount = #self._events,
			Armed = self._armed,
			BurstCount = self._burstSerial,
			LastBurst = Events.Copy(self._lastBurst),
			ConnectionCount = #self._connections,
		}
	end

	return BrokenGlass
end
