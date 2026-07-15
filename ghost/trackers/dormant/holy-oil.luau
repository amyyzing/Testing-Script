return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "HolyOil requires Events")
	local Specification = type(dependencies.Specification) == "table"
		and dependencies.Specification or {}
	local OilSpec = type(Specification.HolyOil) == "table"
		and Specification.HolyOil or {}

	local HolyOil = {}
	HolyOil.__index = HolyOil

	local function disconnect(connection)
		if connection and type(connection.Disconnect) == "function" then
			pcall(connection.Disconnect, connection)
		end
	end

	local function connect(signal, callback)
		if signal == nil then return nil end
		local ok, connection = pcall(function() return signal:Connect(callback) end)
		return ok and connection or nil
	end

	local function call(object, method, ...)
		local callback = object and object[method]
		if type(callback) ~= "function" then return nil end
		local ok, result = pcall(callback, object, ...)
		return ok and result or nil
	end

	local function normalized(value)
		return string.lower(tostring(value or "")):gsub("[^%w]", "")
	end

	local function isHolyOil(model)
		if model == nil or call(model, "IsA", "Model") ~= true then return false end
		local itemName = call(model, "GetAttribute", "ItemName")
		return normalized(model.Name) == "holyoil" or normalized(itemName) == "holyoil"
	end

	local function defaultWall(model)
		for _, name in ipairs({"GhostWall", "ClonedGhostWall"}) do
			local wall = call(model, "FindFirstChild", name, true)
			if call(wall, "IsA", "BasePart") == true then return wall end
		end
		return nil
	end

	local function defaultGhostHasFire(ghost)
		for _, descendant in ipairs(call(ghost, "GetDescendants") or {}) do
			if call(descendant, "IsA", "ParticleEmitter") == true
				and descendant.Name == "Fire"
				and descendant.Enabled == true then
				return true
			end
		end
		return false
	end

	local function schedule(context, delaySeconds, callback)
		if type(context.Schedule) == "function" then
			return context.Schedule(delaySeconds, callback)
		end
		if task and type(task.delay) == "function" then
			local cancelled = false
			task.delay(delaySeconds, function()
				if not cancelled then callback() end
			end)
			return function() cancelled = true end
		end
		callback()
		return function() end
	end

	function HolyOil.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "HolyOil",
			Category = "Dormant",
			Status = "Idle",
			FireProbeDelay = tonumber(options.FireProbeDelay)
				or tonumber(OilSpec.FireProbeDelay) or 0.25,
			_context = nil,
			_folder = nil,
			_connections = {},
			_models = {},
			_bound = setmetatable({}, {__mode = "k"}),
			_hunting = false,
			_fireColourResolved = false,
			_passSerial = 0,
			_lastCollision = nil,
			_lastFireEffect = nil,
		}, HolyOil)
	end

	HolyOil.New = HolyOil.new

	function HolyOil:_remember(connection)
		if connection then table.insert(self._connections, connection) end
		return connection
	end

	function HolyOil:_now(event)
		return tonumber(event and event.Time)
			or (self._context.Clock and self._context.Clock() or os.clock())
	end

	function HolyOil:_emit(event)
		if type(self._context.Emit) == "function" then self._context.Emit(event) end
	end

	function HolyOil:_readHunting(event)
		local explicit = event and Events.Read(event, "Hunting")
		if type(explicit) == "boolean" then return explicit end
		if type(self._context.ReadHunting) == "function" then
			local ok, value = pcall(self._context.ReadHunting)
			if ok then return value == true end
		end
		return call(self._context.GhostModel, "GetAttribute", "Hunting") == true
	end

	function HolyOil:_readBurning(model, event)
		local explicit = event and Events.Read(event, "Burning")
		if type(explicit) == "boolean" then return explicit end
		return call(model, "GetAttribute", "Burning") == true
	end

	function HolyOil:_wall(model)
		if type(self._context.ReadHolyOilWall) == "function" then
			local ok, wall = pcall(self._context.ReadHolyOilWall, model)
			if ok and wall ~= nil then return wall end
		end
		return defaultWall(model)
	end

	function HolyOil:_fireColour(model)
		if type(self._context.ReadHolyOilFireColour) == "function" then
			local ok, value = pcall(self._context.ReadHolyOilFireColour, model)
			if ok then return value end
		end
		return call(model, "GetAttribute", "FireColour")
			or call(model, "GetAttribute", "FireColor")
	end

	function HolyOil:_ghostHasFire()
		if type(self._context.ReadGhostFireEffect) == "function" then
			local ok, value = pcall(
				self._context.ReadGhostFireEffect,
				self._context.GhostModel
			)
			if ok and type(value) == "boolean" then return value end
		end
		return defaultGhostHasFire(self._context.GhostModel)
	end

	function HolyOil:_isGhostTouch(part)
		if type(self._context.IsGhostTouch) == "function" then
			local ok, value = pcall(
				self._context.IsGhostTouch,
				part,
				self._context.GhostModel
			)
			return ok and value == true
		end
		return self._context.GhostModel ~= nil
			and call(part, "IsDescendantOf", self._context.GhostModel) == true
	end

	function HolyOil:_readVerifiedPass(model, wall, event)
		local callback = self._context.ReadHolyOilPass
			or self._context.IsGhostPassingHolyOil
		if type(callback) ~= "function" then return nil end
		local ok, result = pcall(
			callback,
			model,
			wall,
			self._context.GhostModel,
			event
		)
		if not ok then return nil end
		if type(result) == "table" then
			if result.Qualified == false then return false end
			if type(result.Passed) == "boolean" then
				result = result.Passed
			elseif type(result.SideCrossed) == "boolean" then
				result = result.SideCrossed
			elseif type(result.Overlapping) == "boolean" then
				result = result.Overlapping
			else
				result = result.DirectContact
			end
		end
		if type(result) == "boolean" then return result end
		return nil
	end

	function HolyOil:_hasPassVerifier()
		return type(self._context.ReadHolyOilPass) == "function"
			or type(self._context.IsGhostPassingHolyOil) == "function"
	end

	function HolyOil:_state(model)
		local state = self._models[model]
		if not state then
			state = {
				Collision = nil,
				Passed = false,
				FireResolved = false,
				CancelFire = nil,
			}
			self._models[model] = state
		end
		return state
	end

	function HolyOil:_check(model, event)
		if model == nil then return false end
		local hunting = self:_readHunting(event)
		local burning = self:_readBurning(model, event)
		if not burning then return false end
		self.Status = "Armed"
		local state = self:_state(model)
		if hunting then
			local wall = Events.Read(event, "Wall") or self:_wall(model)
			local canCollide = Events.Read(event, "CanCollide")
			if type(canCollide) ~= "boolean" and wall ~= nil then
				canCollide = wall.CanCollide
			end
			if type(canCollide) == "boolean" and state.Collision ~= canCollide then
				state.Collision = canCollide
				self._lastCollision = canCollide
				self:_emit({
					Type = Events.Types.HolyOilCollision,
					Time = self:_now(event),
					Hunting = true,
					Source = self.Name,
					Payload = {
						ModelId = model,
						Burning = true,
						Qualified = true,
						CanCollide = canCollide,
					},
				})
			end
		end

		if not self._fireColourResolved then
			local colour = self:_fireColour(model)
			local blue
			if type(colour) == "boolean" then
				blue = colour
			elseif colour ~= nil then
				local name = normalized(colour)
				blue = name == "blue" or name == "spirit"
			end
			if type(blue) == "boolean" then
				self._fireColourResolved = true
				self:_emit({
					Type = Events.Types.HolyOilColor,
					Time = self:_now(event),
					Hunting = hunting,
					Source = self.Name,
					Payload = {
						ModelId = model,
						Burning = true,
						Qualified = true,
						Stable = true,
						Blue = blue,
					},
				})
			end
		end
		return true
	end

	function HolyOil:_pass(model, event)
		local hunting = self:_readHunting(event)
		local burning = self:_readBurning(model, event)
		if not self:_check(model, event) or not hunting or not burning then return false end
		local state = self:_state(model)
		if state.Passed then return false end
		state.Passed = true
		self._passSerial = self._passSerial + 1
		local passId = tostring(self._passSerial)
		self:_emit({
			Type = Events.Types.HolyOilPass,
			Time = self:_now(event),
			Hunting = true,
			Source = self.Name,
			Payload = {
				PassId = passId,
				ModelId = model,
				Burning = true,
				DirectContact = true,
				Qualified = true,
				SpeedProbe = true,
			},
		})
		state.CancelFire = schedule(self._context, self.FireProbeDelay, function()
			state.CancelFire = nil
			if self.Status == "Stopped" or self.Status == "Destroyed"
				or self._models[model] ~= state then return end
			if state.FireResolved then return end
			state.FireResolved = true
			local caughtFire = self:_ghostHasFire()
			self._lastFireEffect = caughtFire
			self:_emit({
				Type = Events.Types.GhostFireEffect,
				Time = self:_now(),
				Hunting = self:_readHunting(),
				Source = self.Name,
				Payload = {
					PassId = passId,
					ModelId = model,
					Burning = true,
					DirectContact = true,
					Qualified = true,
					Completed = true,
					CaughtFire = caughtFire,
				},
			})
		end)
		return true
	end

	function HolyOil:_bindModel(model)
		if model == nil or self._bound[model] or not isHolyOil(model) then return end
		self._bound[model] = true
		self:_state(model)
		local burningSignal = call(model, "GetAttributeChangedSignal", "Burning")
		self:_remember(connect(burningSignal, function()
			self:_check(model, {Time = self:_now()})
		end))
		for _, attributeName in ipairs({"FireColour", "FireColor"}) do
			local colourSignal = call(model, "GetAttributeChangedSignal", attributeName)
			self:_remember(connect(colourSignal, function()
				self:_check(model, {Time = self:_now()})
			end))
		end
		local function bindWall(wall)
			if wall == nil
				or (wall.Name ~= "GhostWall" and wall.Name ~= "ClonedGhostWall") then return end
			local collisionSignal = call(wall, "GetPropertyChangedSignal", "CanCollide")
			self:_remember(connect(collisionSignal, function()
				self:_check(model, {Time = self:_now(), Wall = wall})
			end))
			self:_remember(connect(wall.Touched, function(part)
				if self:_isGhostTouch(part) then
					local event = {Time = self:_now(), Wall = wall}
					local verified = self:_readVerifiedPass(model, wall, event)
					if self:_hasPassVerifier() and verified ~= true then
						self:_check(model, event)
					else
						-- No callback preserves Touched as the compatibility fallback;
						-- an injected verifier must explicitly confirm the crossing.
						self:_pass(model, event)
					end
				end
			end))
		end
		bindWall(self:_wall(model))
		self:_remember(connect(model.DescendantAdded, function(descendant)
			if descendant.Name == "GhostWall"
				or descendant.Name == "ClonedGhostWall" then bindWall(descendant) end
		end))
		self:_check(model, {Time = self:_now()})
	end

	function HolyOil:Start(context)
		if self.Status ~= "Idle" and self.Status ~= "Stopped" then return end
		self._context = context or {}
		self._hunting = self:_readHunting()
		self.Status = "Dormant"
		local workspace = self._context.Workspace
		local function bindFolder(folder)
			if folder == nil or folder == self._folder then return end
			self._folder = folder
			for _, descendant in ipairs(call(folder, "GetDescendants") or {}) do
				if isHolyOil(descendant) then self:_bindModel(descendant) end
			end
			for _, child in ipairs(call(folder, "GetChildren") or {}) do
				if isHolyOil(child) then self:_bindModel(child) end
			end
			self:_remember(connect(folder.DescendantAdded, function(descendant)
				if isHolyOil(descendant) then self:_bindModel(descendant) end
			end))
		end
		bindFolder(self._context.HolyOilFolder
			or call(workspace, "FindFirstChild", "HolyOil"))
		self:_remember(connect(workspace and workspace.ChildAdded, function(child)
			if child.Name == "HolyOil" then bindFolder(child) end
		end))
	end

	function HolyOil:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind == Events.Types.HuntStarted then
			self._hunting = true
			for model in pairs(self._models) do self:_check(model, event) end
			return true
		elseif kind == Events.Types.HuntEnded then
			self._hunting = false
			self.Status = "Dormant"
			return true
		elseif kind == Events.Types.HolyOilBurningChanged
			or kind == Events.Types.HolyOilWallChanged then
			local model = Events.Read(event, "Model") or Events.Read(event, "ModelId")
			return self:_check(model, event)
		elseif kind == Events.Types.HolyOilTouched then
			local model = Events.Read(event, "Model") or Events.Read(event, "ModelId")
			local wall = Events.Read(event, "Wall") or self:_wall(model)
			local verified = self:_readVerifiedPass(model, wall, event)
			if self:_hasPassVerifier() and verified ~= true then
				return self:_check(model, event)
			end
			return self:_pass(model, event)
		elseif kind == Events.Types.Tick then
			local consumed = false
			for model, state in pairs(self._models) do
				if self:_check(model, event) then
					consumed = true
					if not state.Passed then
						local wall = self:_wall(model)
						if self:_readVerifiedPass(model, wall, event) == true then
							self:_pass(model, event)
						end
					end
				end
			end
			return consumed
		end
		return false
	end

	function HolyOil:Stop()
		for _, state in pairs(self._models) do
			if type(state.CancelFire) == "function" then state.CancelFire() end
			state.CancelFire = nil
		end
		for _, connection in ipairs(self._connections) do disconnect(connection) end
		table.clear(self._connections)
		self._folder = nil
		self._models = {}
		self._bound = setmetatable({}, {__mode = "k"})
		self.Status = "Stopped"
	end

	function HolyOil:Reset()
		self:Stop()
		self._folder = nil
		self._models = {}
		self._bound = setmetatable({}, {__mode = "k"})
		self._hunting = false
		self._fireColourResolved = false
		self._passSerial = 0
		self._lastCollision = nil
		self._lastFireEffect = nil
		self.Status = "Idle"
	end

	function HolyOil:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function HolyOil:Snapshot()
		local modelCount = 0
		for _ in pairs(self._models) do modelCount = modelCount + 1 end
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			ModelCount = modelCount,
			FireColourResolved = self._fireColourResolved,
			LastCollision = self._lastCollision,
			LastFireEffect = self._lastFireEffect,
			ConnectionCount = #self._connections,
		}
	end

	return HolyOil
end
