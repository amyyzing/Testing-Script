return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "HuntRoom requires Events")

	local HuntRoom = {}
	HuntRoom.__index = HuntRoom

	local function call(object, method, ...)
		local callback = object and object[method]
		if type(callback) ~= "function" then return nil end
		local ok, result = pcall(callback, object, ...)
		return ok and result or nil
	end

	local function roomName(value)
		if value == nil then return nil end
		if type(value) == "table" or type(value) == "userdata" then
			value = value.Name
		end
		value = tostring(value)
		if value == "" then return nil end
		return value
	end

	function HuntRoom.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "HuntRoom",
			Category = "Dormant",
			Status = "Idle",
			_context = nil,
			_resolvedHunts = {},
			_pendingHunt = nil,
			MaxRetryAttempts = math.max(1, math.floor(tonumber(options.MaxRetryAttempts) or 8)),
			MaxRetrySeconds = math.max(0, tonumber(options.MaxRetrySeconds) or 2),
			_lastRelation = nil,
		}, HuntRoom)
	end

	HuntRoom.New = HuntRoom.new

	function HuntRoom:Start(context)
		self._context = context or {}
		self.Status = "Dormant"
	end

	function HuntRoom:_currentRoom(event)
		-- Physical containment is authoritative. When its resolver is present but
		-- temporarily returns nil, keep this hunt pending instead of accepting a
		-- stale event, replicated attribute, or ReadCurrentRoom cache.
		if type(self._context.ReadPhysicalCurrentRoom) == "function" then
			local ok, value = pcall(self._context.ReadPhysicalCurrentRoom)
			return ok and roomName(value) or nil
		end
		local value = Events.Read(event, "CurrentRoom")
		if value == nil and type(self._context.ReadCurrentRoom) == "function" then
			local ok, result = pcall(self._context.ReadCurrentRoom)
			if ok then value = result end
		end
		if value == nil then
			value = call(self._context.GhostModel, "GetAttribute", "CurrentRoom")
		end
		return roomName(value)
	end

	function HuntRoom:_favouriteRoom(event)
		local value = Events.Read(event, "FavouriteRoom")
			or Events.Read(event, "FavoriteRoom")
		if value == nil and type(self._context.ReadFavouriteRoom) == "function" then
			local ok, result = pcall(self._context.ReadFavouriteRoom)
			if ok then value = result end
		end
		if value == nil then
			value = call(self._context.GhostModel, "GetAttribute", "FavoriteRoom")
				or call(self._context.GhostModel, "GetAttribute", "FavouriteRoom")
		end
		return roomName(value)
	end

	function HuntRoom:_now(event)
		return tonumber(event and event.Time)
			or (self._context.Clock and self._context.Clock() or os.clock())
	end

	function HuntRoom:_tryResolve(event)
		local pending = self._pendingHunt
		if not pending or self._resolvedHunts[pending.HuntId] then return false end
		pending.Attempts = pending.Attempts + 1
		local current = self:_currentRoom(event)
		local favourite = self:_favouriteRoom(event)
		if current == nil or favourite == nil then
			local expired = pending.Attempts >= self.MaxRetryAttempts
				or self:_now(event) - pending.StartedAt >= self.MaxRetrySeconds
			if expired then
				self._pendingHunt = nil
				self.Status = "Dormant"
			else
				self.Status = "WaitingForRooms"
			end
			return false
		end
		local matches = string.lower(current) == string.lower(favourite)
		self._resolvedHunts[pending.HuntId] = true
		self._lastRelation = {
			HuntId = pending.HuntId,
			CurrentRoom = current,
			FavouriteRoom = favourite,
			InFavouriteRoom = matches,
		}
		self._pendingHunt = nil
		self.Status = "Resolved"
		if type(self._context.Emit) == "function" then
			self._context.Emit({
				Type = Events.Types.HuntRoomRelation,
				Time = event.Time,
				HuntId = pending.HuntId,
				Hunting = true,
				Source = self.Name,
				Payload = {
					Qualified = true,
					Completed = true,
					CurrentRoom = current,
					FavouriteRoom = favourite,
					InFavouriteRoom = matches,
				},
			})
		end
		return true
	end

	function HuntRoom:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind == Events.Types.HuntEnded then
			if self._pendingHunt == nil
				or event.HuntId == nil
				or event.HuntId == self._pendingHunt.HuntId then
				self._pendingHunt = nil
			end
			self.Status = "Dormant"
			return true
		end
		if kind == Events.Types.Tick then
			local hadPending = self._pendingHunt ~= nil
			if hadPending then self:_tryResolve(event) end
			return hadPending
		end
		if kind ~= Events.Types.HuntStarted then return false end
		local huntId = event.HuntId or tostring(event.Time or "hunt")
		if self._resolvedHunts[huntId] then return true end
		self._pendingHunt = {
			HuntId = huntId,
			StartedAt = self:_now(event),
			Attempts = 0,
		}
		self.Status = "WaitingForRooms"
		self:_tryResolve(event)
		return true
	end

	function HuntRoom:Stop() self.Status = "Stopped" end
	function HuntRoom:Reset()
		table.clear(self._resolvedHunts)
		self._pendingHunt = nil
		self._lastRelation = nil
		self.Status = "Idle"
	end
	function HuntRoom:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end
	function HuntRoom:Snapshot()
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			PendingHunt = Events.Copy(self._pendingHunt),
			LastRelation = Events.Copy(self._lastRelation),
		}
	end

	return HuntRoom
end
