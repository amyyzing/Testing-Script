return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "ElectronicDevices requires Events")
	local Specification = type(dependencies.Specification) == "table"
		and dependencies.Specification or {}
	local LeviathanSpec = type(Specification.Leviathan) == "table"
		and Specification.Leviathan or {}

	local ElectronicDevices = {}
	ElectronicDevices.__index = ElectronicDevices

	local ELIGIBLE_LEVIATHAN_ITEMS = {
		blacklight = true,
		laserprojector = true,
		spiritbox = true,
	}

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
		local ok, first, second, third = pcall(callback, object, ...)
		if not ok then return nil end
		return first, second, third
	end

	local function normalized(value)
		return string.lower(tostring(value or "")):gsub("[^%w]", "")
	end

	local function attribute(object, name)
		return call(object, "GetAttribute", name)
	end

	local function positionOf(context, object)
		if object == nil then return nil end
		if type(context.ReadPosition) == "function" then
			local ok, value = pcall(context.ReadPosition, object)
			if ok and value ~= nil then return value end
		end
		local positionOk, directPosition = pcall(function()
			return object.Position
		end)
		if positionOk and directPosition ~= nil then return directPosition end
		local pivot = call(object, "GetPivot")
		if pivot ~= nil then return pivot.Position end
		local part = call(object, "FindFirstChildWhichIsA", "BasePart", true)
		return part and part.Position or nil
	end

	local function distanceBetween(context, first, second)
		if first == nil or second == nil then return nil end
		if type(context.DistanceBetween) == "function" then
			local ok, value = pcall(context.DistanceBetween, first, second)
			if ok then return tonumber(value) end
		end
		if type(first) == "number" and type(second) == "number" then
			return math.abs(first - second)
		end
		local ok, value = pcall(function()
			return (first - second).Magnitude
		end)
		return ok and tonumber(value) or nil
	end

	function ElectronicDevices.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "ElectronicDevices",
			Category = "Dormant",
			Status = "Idle",
			RequiredToggles = math.max(
				1,
				math.floor(tonumber(options.RequiredToggles)
					or tonumber(LeviathanSpec.RequiredToggles) or 7)
			),
			ToggleWindow = math.max(
				0,
				tonumber(options.ToggleWindow)
					or tonumber(LeviathanSpec.WindowSeconds) or 2.5
			),
			GlobalFlickerWindow = math.max(
				0,
				tonumber(options.GlobalFlickerWindow) or 0.15
			),
			GhostRadius = tonumber(options.GhostRadius) or 40,
			LeviathanPlayerRadius = tonumber(options.LeviathanPlayerRadius) or 12,
			GhostCloserMargin = tonumber(options.GhostCloserMargin) or 3,
			GhoulPlayerRadius = tonumber(options.GhoulPlayerRadius) or 15,
			_context = nil,
			_connections = {},
			_boundObjects = setmetatable({}, {__mode = "k"}),
			_boundModels = setmetatable({}, {__mode = "k"}),
			_boundFolders = setmetatable({}, {__mode = "k"}),
			_enabledStates = setmetatable({}, {__mode = "k"}),
			_toggleWindows = setmetatable({}, {__mode = "k"}),
			_recentDeviceToggles = {},
			_leviathanEmitted = false,
			_ghoulEmitted = false,
			_lastLeviathan = nil,
			_lastGhoul = nil,
		}, ElectronicDevices)
	end

	ElectronicDevices.New = ElectronicDevices.new

	function ElectronicDevices:_now(event)
		return tonumber(event and event.Time)
			or (self._context.Clock and self._context.Clock() or os.clock())
	end

	function ElectronicDevices:_remember(connection)
		if connection then table.insert(self._connections, connection) end
		return connection
	end

	function ElectronicDevices:_emit(event)
		if type(self._context.Emit) == "function" then self._context.Emit(event) end
	end

	function ElectronicDevices:_readHunting(event)
		local explicit = Events.Read(event, "Hunting")
		if type(explicit) == "boolean" then return explicit end
		if type(self._context.ReadHunting) == "function" then
			local ok, value = pcall(self._context.ReadHunting)
			if ok then return value == true end
		end
		return attribute(self._context.GhostModel, "Hunting") == true
	end

	function ElectronicDevices:_resolveModel(object, event)
		local explicit = Events.Read(event, "Model") or Events.Read(event, "ModelId")
		if explicit ~= nil then return explicit end
		if type(self._context.ResolveItemModel) == "function" then
			local ok, model = pcall(self._context.ResolveItemModel, object)
			if ok and model ~= nil then return model end
		end
		local current = object
		local fallback
		while current ~= nil do
			if call(current, "IsA", "Model") == true then
				fallback = fallback or current
				local itemName = attribute(current, "ItemName")
				if type(itemName) == "string" and itemName ~= "" then
					return current
				end
			end
			current = current.Parent
		end
		return fallback
	end

	function ElectronicDevices:_itemName(model, event)
		return normalized(
			Events.Read(event, "ItemName")
				or attribute(model, "ItemName")
				or (model and model.Name)
		)
	end

	function ElectronicDevices:_suppression(object, model, event)
		local automation = Events.Read(event, "AutomationCaused") == true
		local fuse = Events.Read(event, "FuseCaused") == true
		local playerCaused = Events.Read(event, "PlayerCaused") == true
		if not automation and type(self._context.IsElectronicMutationSuppressed) == "function" then
			local ok, value = pcall(
				self._context.IsElectronicMutationSuppressed,
				object,
				model,
				event
			)
			automation = ok and value == true
		end
		if not fuse and type(self._context.IsFuseMutationActive) == "function" then
			local ok, value = pcall(self._context.IsFuseMutationActive, event)
			fuse = ok and value == true
		end
		return automation, fuse, playerCaused
	end

	function ElectronicDevices:_ghostDistance(model, event)
		local explicit = tonumber(Events.Read(event, "GhostDistance"))
		if explicit then return explicit end
		return distanceBetween(
			self._context,
			positionOf(self._context, model),
			positionOf(self._context, self._context.GhostModel)
		)
	end

	function ElectronicDevices:_nearestPlayerDistance(model, event)
		local explicit = tonumber(Events.Read(event, "NearestPlayerDistance"))
		if explicit then return explicit end
		local target = positionOf(self._context, model)
		if target == nil then return nil end
		local players = self._context.Players or self._context.PlayersService
		local nearest = math.huge
		for _, player in ipairs(call(players, "GetPlayers") or {}) do
			if attribute(player, "Dead") ~= true then
				local character = player.Character
				local root = character and call(character, "FindFirstChild", "HumanoidRootPart")
				local separation = distanceBetween(
					self._context,
					target,
					positionOf(self._context, root)
				)
				local numericSeparation = tonumber(separation)
				if numericSeparation ~= nil and numericSeparation < nearest then
					nearest = numericSeparation
				end
			end
		end
		return nearest
	end

	function ElectronicDevices:_ghostLikelyCause(model, event, ghostDistance)
		local explicit = Events.Read(event, "GhostLikelyCause")
		if type(explicit) == "boolean" then return explicit end
		if type(self._context.IsGhostLikelyElectronicCause) == "function" then
			local ok, value = pcall(
				self._context.IsGhostLikelyElectronicCause,
				model,
				event
			)
			if ok and type(value) == "boolean" then return value end
		end
		if ghostDistance == nil or ghostDistance > self.GhostRadius then
			return false
		end
		local nearestPlayerDistance = self:_nearestPlayerDistance(model, event)
		if nearestPlayerDistance == nil then return false end
		return nearestPlayerDistance > self.LeviathanPlayerRadius
			or ghostDistance + self.GhostCloserMargin < nearestPlayerDistance
	end

	function ElectronicDevices:_clearToggleWindow(object)
		if object ~= nil then self._toggleWindows[object] = nil end
	end

	function ElectronicDevices:_globalFlickerDetected(object, model, now, event)
		if Events.Read(event, "GlobalFlicker") == true
			or Events.Read(event, "HuntFlicker") == true
			or Events.Read(event, "RoomFlicker") == true then
			self._toggleWindows = setmetatable({}, {__mode = "k"})
			table.clear(self._recentDeviceToggles)
			return true
		end

		local recent = self._recentDeviceToggles
		local cutoff = now - self.GlobalFlickerWindow
		for index = #recent, 1, -1 do
			if recent[index].Time < cutoff then table.remove(recent, index) end
		end
		local global = false
		for _, previous in ipairs(recent) do
			-- One physical device can expose multiple Enabled attributes. Only
			-- coherent changes on distinct item models indicate global flicker.
			if previous.Model ~= model then
				global = true
				self:_clearToggleWindow(previous.Object)
			end
		end
		table.insert(recent, {Object = object, Model = model, Time = now})
		if global then self:_clearToggleWindow(object) end
		return global
	end

	function ElectronicDevices:_recordLeviathanToggle(
		object,
		model,
		current,
		now,
		event,
		ghostDistance,
		hunting
	)
		if self._leviathanEmitted then return end
		local itemName = self:_itemName(model, event)
		if not ELIGIBLE_LEVIATHAN_ITEMS[itemName]
			or not self:_ghostLikelyCause(model, event, ghostDistance) then
			self:_clearToggleWindow(object)
			return
		end
		local window = self._toggleWindows[object]
		if not window then
			window = {}
			self._toggleWindows[object] = window
		end
		table.insert(window, {Time = now, State = current})
		local cutoff = now - self.ToggleWindow
		while window[1] and window[1].Time < cutoff do table.remove(window, 1) end
		if #window < self.RequiredToggles then return end
		local firstIndex = #window - self.RequiredToggles + 1
		local first = window[firstIndex]
		local previousState = first.State
		local alternating = true
		for index = firstIndex + 1, #window do
			if window[index].State == previousState then
				alternating = false
				break
			end
			previousState = window[index].State
		end
		local duration = now - first.Time
		if not alternating or duration < 0 or duration > self.ToggleWindow then return end
		self._leviathanEmitted = true
		self._lastLeviathan = {
			Object = object,
			Model = model,
			ItemName = itemName,
			ToggleCount = #window,
			Duration = duration,
			Time = now,
		}
		self:_emit({
			Type = Events.Types.DeviceToggleBurst,
			Time = now,
			Hunting = hunting,
			Source = self.Name,
			Payload = {
				Qualified = true,
				Completed = true,
				PlayerCaused = false,
				AutomationCaused = false,
				FuseCaused = false,
				SingleDevice = true,
				Rapid = true,
				Clean = true,
				Alternating = true,
				ToggleCount = #window,
				Count = #window,
				Duration = duration,
				Window = self.ToggleWindow,
				ItemName = itemName,
				ModelId = model,
				ObjectId = object,
				GhostDistance = ghostDistance,
			},
		})
	end

	function ElectronicDevices:_recordGhoulDisable(
		object,
		model,
		now,
		event,
		ghostDistance,
		hunting
	)
		if self._ghoulEmitted then return end
		local nearest = self:_nearestPlayerDistance(model, event)
		if nearest == nil or nearest <= self.GhoulPlayerRadius then return end
		self._ghoulEmitted = true
		self._lastGhoul = {
			Object = object,
			Model = model,
			GhostDistance = ghostDistance,
			NearestPlayerDistance = nearest,
			Time = now,
		}
		self:_emit({
			Type = Events.Types.HuntElectronicDisabled,
			Time = now,
			Hunting = hunting,
			Source = self.Name,
			Payload = {
				Qualified = true,
				Completed = true,
				NearestPlayerDistance = nearest,
				NoPlayerWithin15 = nearest > self.GhoulPlayerRadius,
				PlayerCaused = false,
				AutomationCaused = false,
				FuseCaused = false,
				GhostDistance = ghostDistance,
				ModelId = model,
				ObjectId = object,
			},
		})
	end

	function ElectronicDevices:_handleToggle(object, model, previous, current, event)
		if type(previous) ~= "boolean" or type(current) ~= "boolean"
			or previous == current then return false end
		event = type(event) == "table" and event or {}
		model = model or self:_resolveModel(object, event)
		if model == nil then return false end
		object = object or model
		local now = self:_now(event)
		local automation, fuse, playerCaused = self:_suppression(object, model, event)
		if automation or fuse or playerCaused then
			self:_clearToggleWindow(object)
			return true
		end
		local hunting = self:_readHunting(event)
		local ghostDistance = self:_ghostDistance(model, event)
		if previous == true and current == false then
			self:_recordGhoulDisable(
				object,
				model,
				now,
				event,
				ghostDistance,
				hunting
			)
		end
		if not self:_globalFlickerDetected(object, model, now, event) then
			self:_recordLeviathanToggle(
				object,
				model,
				current,
				now,
				event,
				ghostDistance,
				hunting
			)
		end
		return true
	end

	function ElectronicDevices:_bindEnabledObject(object, model)
		if object == nil or self._boundObjects[object] then return false end
		local enabled = attribute(object, "Enabled")
		if type(enabled) ~= "boolean" then return false end
		self._boundObjects[object] = true
		self._enabledStates[object] = enabled
		local signal = call(object, "GetAttributeChangedSignal", "Enabled")
		self:_remember(connect(signal, function()
			local previous = self._enabledStates[object]
			local current = attribute(object, "Enabled")
			self._enabledStates[object] = current
			self:_handleToggle(
				object,
				model or self:_resolveModel(object, {}),
				previous,
				current,
				{Time = self:_now()}
			)
		end))
		return true
	end

	function ElectronicDevices:_bindModel(model)
		if model == nil then return false end
		local workspace = self._context.Workspace
		-- CollectionService also tags held/inventory tools. Those are player
		-- interactions, not world-device observations, and must never qualify.
		if workspace ~= nil and model ~= workspace
			and call(model, "IsDescendantOf", workspace) ~= true then return false end
		if not self._boundModels[model] then
			self._boundModels[model] = true
			self:_bindEnabledObject(model, model)
			for _, descendant in ipairs(call(model, "GetDescendants") or {}) do
				self:_bindEnabledObject(descendant, model)
			end
			self:_remember(connect(model.DescendantAdded, function(descendant)
				self:_bindEnabledObject(descendant, model)
			end))
		end
		return true
	end

	function ElectronicDevices:_inspect(object)
		if object == nil then return end
		local model = self:_resolveModel(object, {})
		if call(object, "IsA", "Model") == true then
			-- Nested visual Models may live below the actual ItemName Model. Bind
			-- the resolved inventory model so one physical device owns one stream.
			self:_bindModel(model or object)
		elseif model then
			self:_bindEnabledObject(object, model)
		end
	end

	function ElectronicDevices:_bindItemsFolder(folder)
		if folder == nil or self._boundFolders[folder] then return false end
		self._boundFolders[folder] = true
		for _, child in ipairs(call(folder, "GetChildren") or {}) do
			self:_inspect(child)
		end
		for _, descendant in ipairs(call(folder, "GetDescendants") or {}) do
			self:_inspect(descendant)
		end
		self:_remember(connect(folder.DescendantAdded, function(descendant)
			self:_inspect(descendant)
		end))
		return true
	end

	function ElectronicDevices:Start(context)
		if self.Status ~= "Idle" and self.Status ~= "Stopped" then return end
		self._context = context or {}
		self.Status = "Dormant"
		local workspace = self._context.Workspace
		self:_bindItemsFolder(
			self._context.ItemsFolder or call(workspace, "FindFirstChild", "Items")
		)
		self:_remember(connect(workspace and workspace.ChildAdded, function(child)
			if child.Name == "Items" then self:_bindItemsFolder(child) end
		end))

		local collection = self._context.CollectionService
		for _, model in ipairs(call(collection, "GetTagged", "Item") or {}) do
			self:_bindModel(model)
		end
		self:_remember(connect(
			call(collection, "GetInstanceAddedSignal", "Item"),
			function(model) self:_bindModel(model) end
		))
	end

	function ElectronicDevices:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or self._context == nil or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind == "ElectronicEnabledChanged" then
			local object = Events.Read(event, "Object") or Events.Read(event, "ObjectId")
			local model = self:_resolveModel(object, event)
			return self:_handleToggle(
				object,
				model,
				Events.Read(event, "Previous"),
				Events.Read(event, "Enabled"),
				event
			)
		elseif kind == Events.Types.HuntStarted or kind == Events.Types.HuntEnded then
			-- Hunt state is metadata, not a qualification boundary for either
			-- electronic observation.
			return true
		end
		return false
	end

	function ElectronicDevices:Stop()
		for _, connection in ipairs(self._connections) do disconnect(connection) end
		table.clear(self._connections)
		-- A later Start must rebuild every live connection.  A stopped interval
		-- also cannot be part of a clean rapid-toggle window.
		self._boundObjects = setmetatable({}, {__mode = "k"})
		self._boundModels = setmetatable({}, {__mode = "k"})
		self._boundFolders = setmetatable({}, {__mode = "k"})
		self._enabledStates = setmetatable({}, {__mode = "k"})
		self._toggleWindows = setmetatable({}, {__mode = "k"})
		table.clear(self._recentDeviceToggles)
		self.Status = "Stopped"
	end

	function ElectronicDevices:Reset()
		self:Stop()
		self._boundObjects = setmetatable({}, {__mode = "k"})
		self._boundModels = setmetatable({}, {__mode = "k"})
		self._boundFolders = setmetatable({}, {__mode = "k"})
		self._enabledStates = setmetatable({}, {__mode = "k"})
		self._toggleWindows = setmetatable({}, {__mode = "k"})
		table.clear(self._recentDeviceToggles)
		self._leviathanEmitted = false
		self._ghoulEmitted = false
		self._lastLeviathan = nil
		self._lastGhoul = nil
		self.Status = "Idle"
	end

	function ElectronicDevices:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function ElectronicDevices:Snapshot()
		local objectCount = 0
		for _ in pairs(self._boundObjects) do objectCount = objectCount + 1 end
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			BoundObjectCount = objectCount,
			RequiredToggles = self.RequiredToggles,
			ToggleWindow = self.ToggleWindow,
			LeviathanEmitted = self._leviathanEmitted,
			GhoulEmitted = self._ghoulEmitted,
			LastLeviathan = Events.Copy(self._lastLeviathan),
			LastGhoul = Events.Copy(self._lastGhoul),
			ConnectionCount = #self._connections,
		}
	end

	return ElectronicDevices
end
