return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "RuntimeSignals requires Events")

	local RuntimeSignals = {}
	RuntimeSignals.__index = RuntimeSignals

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

	local function isA(object, className)
		return call(object, "IsA", className) == true
	end

	local function readAttribute(object, name)
		return call(object, "GetAttribute", name)
	end

	function RuntimeSignals.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "RuntimeSignals",
			Category = "Active",
			Status = "Idle",
			_context = nil,
			_ghost = nil,
			_connections = {},
			_transparencyParts = setmetatable({}, {__mode = "k"}),
			_players = setmetatable({}, {__mode = "k"}),
			_deathSeen = setmetatable({}, {__mode = "k"}),
			_humanoid = nil,
			_lastTransparency = nil,
			_eventCount = 0,
		}, RuntimeSignals)
	end

	RuntimeSignals.New = RuntimeSignals.new

	function RuntimeSignals:_emit(event)
		if self.Status ~= "Active" or type(self._context.Emit) ~= "function" then
			return
		end
		self._eventCount = self._eventCount + 1
		self._context.Emit(event)
	end

	function RuntimeSignals:_remember(connection)
		if connection then table.insert(self._connections, connection) end
		return connection
	end

	function RuntimeSignals:_readHunting()
		if type(self._context.ReadHunting) == "function" then
			local ok, value = pcall(self._context.ReadHunting)
			if ok then return value == true end
		end
		return readAttribute(self._ghost, "Hunting") == true
	end

	function RuntimeSignals:_readTransparency()
		if type(self._context.ReadTransparency) == "function" then
			local ok, value = pcall(self._context.ReadTransparency)
			if ok then return value end
		end
		return readAttribute(self._ghost, "Transparency")
	end

	function RuntimeSignals:_readSanity()
		if type(self._context.ReadAverageSanity) ~= "function" then return nil end
		local ok, value = pcall(self._context.ReadAverageSanity)
		return ok and tonumber(value) or nil
	end

	function RuntimeSignals:_readSpeed()
		if type(self._context.ReadWalkSpeed) == "function" then
			local ok, value = pcall(self._context.ReadWalkSpeed)
			if ok and tonumber(value) then return tonumber(value) end
		end
		return self._humanoid and tonumber(self._humanoid.WalkSpeed) or nil
	end

	function RuntimeSignals:_emitHunting()
		local hunting = self:_readHunting()
		self:_emit({
			Type = Events.Types.HuntingStateChanged,
			Hunting = hunting,
			Source = "Ghost.Hunting",
			Payload = {
				Hunting = hunting,
				AverageSanity = self:_readSanity(),
				MapFactor = self._context.MapFactor,
				MapSize = self._context.MapSize,
				ValidMultipliers = self._context.ValidMultipliers,
				Transparency = self:_readTransparency(),
			},
		})
	end

	function RuntimeSignals:_emitTransparency(source)
		local value = self:_readTransparency()
		local qualified = Events.IsBinaryTransparency(value)
		if not qualified or value == self._lastTransparency then return end
		self._lastTransparency = value
		self:_emit({
			Type = Events.Types.TransparencyChanged,
			Hunting = self:_readHunting(),
			Source = source or "Ghost.Transparency",
			Payload = {Transparency = value},
		})
	end

	function RuntimeSignals:_emitWalkSpeed(source)
		local speed = self:_readSpeed()
		if not speed then return end
		self:_emit({
			Type = Events.Types.WalkSpeedChanged,
			Hunting = self:_readHunting(),
			Source = source or "GhostHumanoid.WalkSpeed",
			Payload = {CurrentSpeed = speed, WalkSpeed = speed},
		})
	end

	function RuntimeSignals:_bindPart(part)
		if part == nil or self._transparencyParts[part]
			or not isA(part, "BasePart") or part.Name == "HumanoidRootPart" then
			return
		end
		self._transparencyParts[part] = true
		local signal = call(part, "GetPropertyChangedSignal", "Transparency")
		self:_remember(connect(signal, function()
			self:_emitTransparency("GhostVisual.Transparency")
		end))
	end

	function RuntimeSignals:_bindHumanoid(humanoid)
		if humanoid == nil or humanoid == self._humanoid or not isA(humanoid, "Humanoid") then
			return
		end
		self._humanoid = humanoid
		local signal = call(humanoid, "GetPropertyChangedSignal", "WalkSpeed")
		self:_remember(connect(signal, function()
			self:_emitWalkSpeed("GhostHumanoid.WalkSpeed")
		end))
	end

	function RuntimeSignals:_aliveOtherPlayers(deadPlayer)
		local players = self._context.Players or self._context.PlayersService
		local list = call(players, "GetPlayers") or {}
		local count = 0
		for _, player in ipairs(type(list) == "table" and list or {}) do
			if player ~= deadPlayer and readAttribute(player, "Dead") ~= true then
				count = count + 1
			end
		end
		return count
	end

	function RuntimeSignals:_bindPlayer(player)
		if player == nil or self._players[player] then return end
		self._players[player] = true
		local signal = call(player, "GetAttributeChangedSignal", "Dead")
		self:_remember(connect(signal, function()
			if readAttribute(player, "Dead") ~= true or self._deathSeen[player] then
				return
			end
			self._deathSeen[player] = true
			local hunting = self:_readHunting()
			local otherAlive = self:_aliveOtherPlayers(player)
			local qualified = hunting and otherAlive > 0
			self:_emit({
				Type = Events.Types.PlayerDeath,
				Hunting = hunting,
				Source = "Player.Dead",
				Payload = {
					PlayerId = player.UserId,
					Unique = true,
					OtherAlive = otherAlive,
					Qualified = qualified,
					ValidMultiplayerKill = qualified,
				},
			})
		end))
	end

	function RuntimeSignals:Start(context)
		if self.Status == "Active" then return end
		self._context = context or {}
		self._ghost = assert(self._context.GhostModel, "RuntimeSignals requires the fixed GhostModel")
		self.Status = "Active"
		self._lastTransparency = nil

		local huntingSignal = call(self._ghost, "GetAttributeChangedSignal", "Hunting")
		self:_remember(connect(huntingSignal, function() self:_emitHunting() end))
		local transparencySignal = call(self._ghost, "GetAttributeChangedSignal", "Transparency")
		self:_remember(connect(transparencySignal, function()
			self:_emitTransparency("Ghost.Transparency")
		end))

		for _, descendant in ipairs(call(self._ghost, "GetDescendants") or {}) do
			self:_bindPart(descendant)
			self:_bindHumanoid(descendant)
		end
		self:_bindHumanoid(call(self._ghost, "FindFirstChildOfClass", "Humanoid"))
		self:_remember(connect(self._ghost.DescendantAdded, function(descendant)
			self:_bindPart(descendant)
			self:_bindHumanoid(descendant)
		end))

		local players = self._context.Players or self._context.PlayersService
		for _, player in ipairs(call(players, "GetPlayers") or {}) do
			self:_bindPlayer(player)
		end
		self:_remember(connect(players and players.PlayerAdded, function(player)
			self:_bindPlayer(player)
		end))
		-- Reconcile all three live streams once. This gives consumers a startup
		-- non-hunt speed sample and makes attachment timing irrelevant.
		self:_emitHunting()
		self:_emitTransparency("Ghost.Startup")
		self:_emitWalkSpeed("GhostHumanoid.Startup")
	end

	function RuntimeSignals:OnEvent() end

	function RuntimeSignals:Stop()
		for _, connection in ipairs(self._connections) do disconnect(connection) end
		table.clear(self._connections)
		self._humanoid = nil
		self._lastTransparency = nil
		self._transparencyParts = setmetatable({}, {__mode = "k"})
		self._players = setmetatable({}, {__mode = "k"})
		self.Status = "Stopped"
	end

	function RuntimeSignals:Reset()
		self:Stop()
		self._ghost = nil
		self._humanoid = nil
		self._lastTransparency = nil
		self._eventCount = 0
		self._transparencyParts = setmetatable({}, {__mode = "k"})
		self._players = setmetatable({}, {__mode = "k"})
		self._deathSeen = setmetatable({}, {__mode = "k"})
		self.Status = "Idle"
	end

	function RuntimeSignals:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function RuntimeSignals:Snapshot()
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			ConnectionCount = #self._connections,
			EventCount = self._eventCount,
			HasGhost = self._ghost ~= nil,
			HasHumanoid = self._humanoid ~= nil,
		}
	end

	return RuntimeSignals
end
