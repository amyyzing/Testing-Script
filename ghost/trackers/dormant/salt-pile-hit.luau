return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "SaltPileHit requires Events")
	local Specification = type(dependencies.Specification) == "table"
		and dependencies.Specification or {}
	local SaltSpec = type(Specification.Salt) == "table" and Specification.Salt or {}

	local SaltPileHit = {}
	SaltPileHit.__index = SaltPileHit

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

	local function normalizedName(object)
		return string.lower(tostring(type(object) == "string" and object or object and object.Name or ""))
			:gsub("[^%w]", "")
	end

	local function isDisturbed(object)
		local name = normalizedName(object)
		return string.find(name, "disturbedsaltline", 1, true) ~= nil
			or string.find(name, "disturbedsaltpile", 1, true) ~= nil
	end

	local function isSalt(object)
		local name = normalizedName(object)
		return string.find(name, "saltline", 1, true) ~= nil
			or string.find(name, "saltpile", 1, true) ~= nil
	end

	local function descendants(root)
		local all = call(root, "GetDescendants")
		if type(all) == "table" then return all end
		local result = {}
		local function visit(parent)
			for _, child in ipairs(call(parent, "GetChildren") or {}) do
				table.insert(result, child)
				visit(child)
			end
		end
		visit(root)
		return result
	end

	local function defaultPosition(object)
		if object == nil or type(object) == "string" then return nil end
		local positionOk, position = pcall(function()
			return object.Position
		end)
		if positionOk and position ~= nil then return position end
		local pivot = call(object, "GetPivot")
		if pivot ~= nil then return pivot.Position end
		local part = call(object, "FindFirstChildWhichIsA", "BasePart", true)
		return part and part.Position or nil
	end

	local function distance(first, second)
		if first == nil or second == nil then return nil end
		local ok, result = pcall(function() return (first - second).Magnitude end)
		return ok and tonumber(result) or nil
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
		return nil
	end

	function SaltPileHit.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "SaltPileHit",
			Category = "Dormant",
			Status = "Idle",
			PlacementGrace = tonumber(options.PlacementGrace)
				or tonumber(SaltSpec.PlacementGrace) or 4,
			UndisturbedDelay = tonumber(options.UndisturbedDelay)
				or tonumber(SaltSpec.UndisturbedDelay) or 1.25,
			MatchRadius = tonumber(options.MatchRadius)
				or tonumber(SaltSpec.MatchRadius) or 3.5,
			_context = nil,
			_folder = nil,
			_connections = {},
			_bound = setmetatable({}, {__mode = "k"}),
			_saltBound = setmetatable({}, {__mode = "k"}),
			_reportedDisturbances = {},
			_placed = {},
			_contacts = {},
			_lastResult = nil,
			_serial = 0,
		}, SaltPileHit)
	end

	SaltPileHit.New = SaltPileHit.new

	function SaltPileHit:_now(event)
		return tonumber(event and event.Time)
			or (self._context.Clock and self._context.Clock() or os.clock())
	end

	function SaltPileHit:_remember(connection)
		if connection then table.insert(self._connections, connection) end
		return connection
	end

	function SaltPileHit:_emit(event)
		if type(self._context.Emit) == "function" then self._context.Emit(event) end
	end

	function SaltPileHit:_readHunting(event)
		local explicit = event and Events.Read(event, "Hunting")
		if type(explicit) == "boolean" then return explicit end
		if type(self._context.ReadHunting) == "function" then
			local ok, value = pcall(self._context.ReadHunting)
			if ok then return value == true end
		end
		local ghost = self._context.GhostModel
		local value = call(ghost, "GetAttribute", "Hunting")
		return value == true
	end

	function SaltPileHit:_position(object)
		if type(self._context.ReadSaltPosition) == "function" then
			local ok, result = pcall(self._context.ReadSaltPosition, object)
			if ok and result ~= nil then return result end
		end
		return defaultPosition(object)
	end

	function SaltPileHit:_place(id, now, position, assumeArmed)
		if id == nil then return end
		local placedAt = assumeArmed and (now - self.PlacementGrace) or now
		if type(self._context.ReadSaltPlacedAt) == "function" then
			local ok, value = pcall(self._context.ReadSaltPlacedAt, id)
			if ok and tonumber(value) then placedAt = tonumber(value) end
		end
		self._placed[id] = {
			PlacedAt = placedAt,
			Position = position or self:_position(id),
			Armed = assumeArmed == true,
			WaitingForClear = false,
			LastOverlap = false,
			TouchedDuringGrace = false,
		}
		self.Status = "Monitoring"
	end

	function SaltPileHit:_isGhostTouch(part)
		local ghost = self._context.GhostModel
		if type(self._context.IsGhostTouch) == "function" then
			local ok, result = pcall(self._context.IsGhostTouch, part, ghost)
			return ok and result == true
		end
		return ghost ~= nil and call(part, "IsDescendantOf", ghost) == true
	end

	function SaltPileHit:_contactId(model)
		return model
	end

	function SaltPileHit:_readOverlap(model, event)
		local callback = self._context.ReadSaltGhostOverlap
			or self._context.IsGhostOverlappingSalt
		if type(callback) ~= "function" then return nil end
		local ok, result = pcall(callback, model, self._context.GhostModel, event)
		if not ok then return nil end
		if type(result) == "table" then
			if type(result.Overlapping) == "boolean" then
				result = result.Overlapping
			elseif type(result.Touching) == "boolean" then
				result = result.Touching
			else
				result = result.DirectContact
			end
		end
		if type(result) == "boolean" then return result end
		return nil
	end

	function SaltPileHit:_updateArming(model, placed, now, overlap)
		if placed.Armed == true then return true end
		if now - placed.PlacedAt < self.PlacementGrace then return false end
		if overlap == true or placed.TouchedDuringGrace == true then
			placed.WaitingForClear = true
		end
		if placed.WaitingForClear then
			if overlap == false then
				placed.WaitingForClear = false
				placed.TouchedDuringGrace = false
				placed.Armed = true
			end
		else
			placed.Armed = true
		end
		return placed.Armed == true
	end

	function SaltPileHit:_touch(model, event)
		local now = self:_now(event)
		local placed = self._placed[model]
		if placed == nil then
			self:_place(model, now, self:_position(model))
			placed = self._placed[model]
		end
		if now - placed.PlacedAt < self.PlacementGrace then
			if type(self._context.ReadSaltGhostOverlap) == "function"
				or type(self._context.IsGhostOverlappingSalt) == "function" then
				placed.TouchedDuringGrace = true
			end
			return false
		end
		if not self:_updateArming(model, placed, now, self:_readOverlap(model, event)) then
			return false
		end
		local id = Events.Read(event, "ContactId") or self:_contactId(model)
		if self._contacts[id] ~= nil then return false end
		self._serial = self._serial + 1
		local hunting = self:_readHunting(event)
		local contact = {
			Id = id,
			Model = model,
			Time = now,
			Position = placed.Position or self:_position(model),
			HuntingAtContact = hunting,
			Disturbed = false,
			Resolved = false,
			Serial = self._serial,
		}
		self._contacts[id] = contact
		self:_emit({
			Type = Events.Types.SaltContact,
			Time = now,
			Hunting = hunting,
			Source = self.Name,
			Payload = {
				ContactId = id,
				DirectContact = true,
				Disturbed = false,
				SaltDisturbed = false,
				HuntingAtContact = hunting,
				Qualified = true,
			},
		})
		contact.CancelResolve = schedule(self._context, self.UndisturbedDelay, function()
			self:_resolveUndisturbed(id, self:_now())
		end)
		return true
	end

	function SaltPileHit:_resolveUndisturbed(id, now)
		local contact = self._contacts[id]
		if not contact or contact.Resolved or contact.Disturbed then return false end
		now = tonumber(now) or self:_now()
		if now - contact.Time < self.UndisturbedDelay then return false end
		contact.Resolved = true
		self._lastResult = "Undisturbed"
		self:_emit({
			Type = Events.Types.SaltContactResult,
			Time = now,
			Hunting = self:_readHunting(),
			Source = self.Name,
			Payload = {
				ContactId = id,
				DirectContact = true,
				Disturbed = false,
				Completed = true,
				Elapsed = now - contact.Time,
				HuntingAtContact = contact.HuntingAtContact,
			},
		})
		return true
	end

	function SaltPileHit:_matchDisturbed(disturbed, event)
		local explicit = Events.Read(event, "ContactId")
		if explicit ~= nil and self._contacts[explicit] then return explicit end
		if self._contacts[disturbed] then return disturbed end
		if type(self._context.MatchDisturbedSalt) == "function" then
			local ok, result = pcall(
				self._context.MatchDisturbedSalt,
				disturbed,
				self._contacts,
				self.MatchRadius
			)
			if ok and result ~= nil and self._contacts[result] then return result end
		end
		local disturbedPosition = Events.Read(event, "Position") or self:_position(disturbed)
		local nearestId, nearestDistance
		for id, contact in pairs(self._contacts) do
			local separation = distance(disturbedPosition, contact.Position)
			if separation and separation <= self.MatchRadius
				and (nearestDistance == nil or separation < nearestDistance) then
				nearestId, nearestDistance = id, separation
			end
		end
		return nearestId
	end

	function SaltPileHit:_disturb(disturbed, event)
		if disturbed ~= nil and self._reportedDisturbances[disturbed] then return false end
		if disturbed ~= nil then self._reportedDisturbances[disturbed] = true end
		local now = self:_now(event)
		local id = self:_matchDisturbed(disturbed, event)
		local contact = id and self._contacts[id] or nil
		if contact and contact.Disturbed then return false end
		if contact then
			contact.Disturbed = true
			contact.Resolved = true
			if type(contact.CancelResolve) == "function" then contact.CancelResolve() end
		end
		self._lastResult = "Disturbed"
		local huntingAtContact = contact and contact.HuntingAtContact or false
		self:_emit({
			Type = Events.Types.SaltDisturbed,
			Time = now,
			Hunting = self:_readHunting(event),
			Source = self.Name,
			Payload = {
				ContactId = id or disturbed,
				DisturbedContactId = id or disturbed,
				DirectContact = contact ~= nil,
				Disturbed = true,
				SaltDisturbed = true,
				HuntingAtContact = huntingAtContact,
			},
		})
		if contact then
			self:_emit({
				Type = Events.Types.SaltContact,
				Time = now,
				Hunting = self:_readHunting(event),
				Source = self.Name,
				Payload = {
					ContactId = id,
					DisturbedContactId = id,
					DirectContact = true,
					Disturbed = true,
					SaltDisturbed = true,
					HuntingAtContact = contact.HuntingAtContact,
					Qualified = true,
				},
			})
		end
		return true
	end

	function SaltPileHit:_isUnderFolder(model)
		local folder = self._folder
		if model == nil or folder == nil then return false end
		if model == folder then return true end
		if type(model.IsDescendantOf) == "function" then
			local ok, result = pcall(model.IsDescendantOf, model, folder)
			if ok then return result == true end
		end
		local parent = model.Parent
		if parent ~= nil then
			local visited = {}
			while parent ~= nil and not visited[parent] do
				if parent == folder then return true end
				visited[parent] = true
				parent = parent.Parent
			end
			return false
		end
		-- Test doubles and executor wrappers may omit ancestry APIs. Objects only
		-- enter this method through the bound folder's recursive scan/signals.
		return self._bound[model] == true
	end

	function SaltPileHit:_activateSalt(model, existing)
		if not self:_isUnderFolder(model) or not isSalt(model) then return end
		if self._saltBound[model] then
			if isDisturbed(model) then self:_disturb(model, {Time = self:_now()}) end
			return
		end
		self._saltBound[model] = true
		if isDisturbed(model) then
			-- A replicated disturbed pile is authoritative even when it predates
			-- script attachment; otherwise re-execution could resurrect Wraith.
			self:_disturb(model, {Time = self:_now()})
			return
		end
		-- Existing clean piles have already survived their placement animation.
		-- Only newly-added piles receive the four-second arming delay.
		self:_place(model, self:_now(), self:_position(model), existing == true)
		local function bindPart(part)
			if call(part, "IsA", "BasePart") ~= true then return end
			self:_remember(connect(part.Touched, function(otherPart)
				if self:_isGhostTouch(otherPart) then
					self:_touch(model, {Time = self:_now()})
				end
			end))
		end
		if call(model, "IsA", "BasePart") == true then bindPart(model) end
		for _, descendant in ipairs(call(model, "GetDescendants") or {}) do bindPart(descendant) end
		self:_remember(connect(model.DescendantAdded, bindPart))
	end

	function SaltPileHit:_bindModel(model, existing)
		if model == nil then return end
		if not self._bound[model] then
			self._bound[model] = true
			local nameSignal = call(model, "GetPropertyChangedSignal", "Name")
			self:_remember(connect(nameSignal, function()
				self:_activateSalt(model, false)
			end))
		end
		self:_activateSalt(model, existing)
	end

	function SaltPileHit:Start(context)
		if self.Status ~= "Idle" and self.Status ~= "Stopped" then return end
		self._context = context or {}
		local workspace = self._context.Workspace
		self.Status = "Dormant"
		local function bindFolder(folder)
			if folder == nil or folder == self._folder then return end
			self._folder = folder
			for _, object in ipairs(descendants(folder)) do
				self:_bindModel(object, true)
			end
			local function bindTree(object)
				self:_bindModel(object, false)
				for _, descendant in ipairs(descendants(object)) do
					self:_bindModel(descendant, false)
				end
			end
			self:_remember(connect(folder.DescendantAdded, bindTree))
			-- ChildAdded is a compatibility fallback for wrappers without a
			-- DescendantAdded signal. _bound prevents duplicate subscriptions and
			-- _reportedDisturbances prevents duplicate evidence.
			self:_remember(connect(folder.ChildAdded, bindTree))
		end
		bindFolder(self._context.SaltPiles
			or call(workspace, "FindFirstChild", "SaltPiles"))
		self:_remember(connect(workspace and workspace.ChildAdded, function(child)
			if child.Name == "SaltPiles" then bindFolder(child) end
		end))
	end

	function SaltPileHit:OnEvent(event)
		if self.Status == "Stopped" or self.Status == "Destroyed"
			or type(event) ~= "table" then return false end
		local kind = event.Type or event.Kind
		if kind == Events.Types.SaltPilePlaced then
			local model = Events.Read(event, "Model") or Events.Read(event, "SaltId")
			self:_place(model, self:_now(event), Events.Read(event, "Position"))
			return true
		elseif kind == Events.Types.SaltPileTouched then
			local model = Events.Read(event, "Model") or Events.Read(event, "SaltId")
			return self:_touch(model, event)
		elseif kind == Events.Types.SaltPileDisturbed then
			local model = Events.Read(event, "Model") or Events.Read(event, "SaltId")
			return self:_disturb(model, event)
		elseif kind == Events.Types.Tick then
			local now = self:_now(event)
			for model, placed in pairs(self._placed) do
				local overlap = self:_readOverlap(model, event)
				if overlap ~= nil then
					local wasOverlapping = placed.LastOverlap == true
					local armed = self:_updateArming(model, placed, now, overlap)
					placed.LastOverlap = overlap
					if armed and overlap and not wasOverlapping then
						self:_touch(model, event)
					end
				elseif now - placed.PlacedAt >= self.PlacementGrace
					and not placed.TouchedDuringGrace then
					placed.Armed = true
				end
			end
			for id in pairs(self._contacts) do self:_resolveUndisturbed(id, now) end
			return true
		end
		return false
	end

	function SaltPileHit:Stop()
		for _, connection in ipairs(self._connections) do disconnect(connection) end
		table.clear(self._connections)
		for _, contact in pairs(self._contacts) do
			if type(contact.CancelResolve) == "function" then contact.CancelResolve() end
		end
		self._folder = nil
		self._bound = setmetatable({}, {__mode = "k"})
		self._saltBound = setmetatable({}, {__mode = "k"})
		table.clear(self._reportedDisturbances)
		table.clear(self._placed)
		table.clear(self._contacts)
		self.Status = "Stopped"
	end

	function SaltPileHit:Reset()
		self:Stop()
		self._folder = nil
		self._bound = setmetatable({}, {__mode = "k"})
		self._saltBound = setmetatable({}, {__mode = "k"})
		table.clear(self._reportedDisturbances)
		table.clear(self._placed)
		table.clear(self._contacts)
		self._lastResult = nil
		self._serial = 0
		self.Status = "Idle"
	end

	function SaltPileHit:Destroy()
		self:Reset()
		self._context = nil
		self.Status = "Destroyed"
	end

	function SaltPileHit:Snapshot()
		local contactCount = 0
		for _ in pairs(self._contacts) do contactCount = contactCount + 1 end
		local placedCount, armedCount, waitingForClearCount, overlapCount = 0, 0, 0, 0
		for _, placed in pairs(self._placed) do
			placedCount = placedCount + 1
			if placed.Armed == true then armedCount = armedCount + 1 end
			if placed.WaitingForClear == true then
				waitingForClearCount = waitingForClearCount + 1
			end
			if placed.LastOverlap == true then overlapCount = overlapCount + 1 end
		end
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			PlacementGrace = self.PlacementGrace,
			UndisturbedDelay = self.UndisturbedDelay,
			ContactCount = contactCount,
			PlacedCount = placedCount,
			ArmedCount = armedCount,
			WaitingForClearCount = waitingForClearCount,
			OverlapCount = overlapCount,
			LastResult = self._lastResult,
			ConnectionCount = #self._connections,
		}
	end

	return SaltPileHit
end
