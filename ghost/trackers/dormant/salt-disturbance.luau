return function(dependencies)
	dependencies = type(dependencies) == "table" and dependencies or {}
	local Events = assert(dependencies.Events, "SaltDisturbance requires Events")
	local SaltDisturbance = {}
	SaltDisturbance.__index = SaltDisturbance

	local function disconnect(connection)
		if connection and type(connection.Disconnect) == "function" then
			connection:Disconnect()
		end
	end

	local function isModel(instance)
		if instance == nil then return false end
		if type(instance.IsA) == "function" then
			local ok, result = pcall(instance.IsA, instance, "Model")
			if ok then return result == true end
		end
		return instance.ClassName == "Model"
	end

	function SaltDisturbance.new(options)
		options = type(options) == "table" and options or {}
		return setmetatable({
			Name = options.Name or "SaltDisturbance",
			Category = "Dormant",
			Status = "Idle",
			_context = nil,
			_workspace = nil,
			_folder = nil,
			_workspaceConnection = nil,
			_folderConnection = nil,
			_modelConnections = setmetatable({}, {__mode = "k"}),
			_resolved = false,
			_disturbedModel = nil,
		}, SaltDisturbance)
	end

	SaltDisturbance.New = SaltDisturbance.new

	function SaltDisturbance:_disconnectFolder()
		disconnect(self._folderConnection)
		self._folderConnection = nil
		for _, connection in pairs(self._modelConnections) do
			disconnect(connection)
		end
		self._modelConnections = setmetatable({}, {__mode = "k"})
		self._folder = nil
	end

	function SaltDisturbance:_disconnectAll()
		self:_disconnectFolder()
		disconnect(self._workspaceConnection)
		self._workspaceConnection = nil
	end

	function SaltDisturbance:_resolve(model)
		if self._resolved then return end
		self._resolved = true
		self._disturbedModel = model
		self.Status = "Resolved"
		local hunting = false
		if type(self._context.ReadHunting) == "function" then
			local ok, result = pcall(self._context.ReadHunting)
			hunting = ok and result == true
		end
		if type(self._context.Emit) == "function" then
			self._context.Emit({
				Type = Events.Types.SaltDisturbed,
				ContactId = model,
				DisturbedContactId = model,
				DirectContact = false,
				Disturbed = true,
				SaltDisturbed = true,
				Hunting = hunting,
				HuntingAtContact = false,
				Qualified = true,
				Source = self.Name,
				Reason = "DisturbedSaltLine exists in Workspace.SaltPiles",
			})
		end
		self:_disconnectAll()
	end

	function SaltDisturbance:_watchModel(model)
		if self._resolved or not isModel(model) then return end
		if model.Name == "DisturbedSaltLine" then
			self:_resolve(model)
			return
		end
		if self._modelConnections[model] ~= nil
			or type(model.GetPropertyChangedSignal) ~= "function" then return end
		local ok, signal = pcall(model.GetPropertyChangedSignal, model, "Name")
		if not ok or signal == nil or type(signal.Connect) ~= "function" then return end
		self._modelConnections[model] = signal:Connect(function()
			if model.Name == "DisturbedSaltLine" then
				self:_resolve(model)
			end
		end)
	end

	function SaltDisturbance:_bindFolder(folder)
		if self._resolved or folder == nil or folder.Name ~= "SaltPiles" then return end
		self:_disconnectFolder()
		self._folder = folder
		self.Status = "Watching"
		local descendantAdded = folder.DescendantAdded or folder.ChildAdded
		if descendantAdded and type(descendantAdded.Connect) == "function" then
			self._folderConnection = descendantAdded:Connect(function(instance)
				self:_watchModel(instance)
			end)
		end
		local descendants = {}
		if type(folder.GetDescendants) == "function" then
			local ok, result = pcall(folder.GetDescendants, folder)
			if ok and type(result) == "table" then descendants = result end
		elseif type(folder.GetChildren) == "function" then
			local ok, result = pcall(folder.GetChildren, folder)
			if ok and type(result) == "table" then descendants = result end
		end
		for _, instance in ipairs(descendants) do
			self:_watchModel(instance)
			if self._resolved then break end
		end
	end

	function SaltDisturbance:Start(context)
		self:_disconnectAll()
		self._context = context or {}
		self._workspace = self._context.Workspace or self._context.WorldRoot
		self._resolved = false
		self._disturbedModel = nil
		self.Status = "Dormant"
		local world = self._workspace
		if world == nil then return end
		if world.ChildAdded and type(world.ChildAdded.Connect) == "function" then
			self._workspaceConnection = world.ChildAdded:Connect(function(child)
				if child.Name == "SaltPiles" then self:_bindFolder(child) end
			end)
		end
		local folder = nil
		if type(world.FindFirstChild) == "function" then
			local ok, result = pcall(world.FindFirstChild, world, "SaltPiles")
			if ok then folder = result end
		end
		if folder then self:_bindFolder(folder) end
	end

	function SaltDisturbance:OnEvent()
		return false
	end

	function SaltDisturbance:Stop()
		self:_disconnectAll()
		self.Status = "Stopped"
	end

	function SaltDisturbance:Reset()
		self:_disconnectAll()
		self._context = nil
		self._workspace = nil
		self._resolved = false
		self._disturbedModel = nil
		self.Status = "Idle"
	end

	function SaltDisturbance:Destroy()
		self:Reset()
		self.Status = "Destroyed"
	end

	function SaltDisturbance:Snapshot()
		return {
			Name = self.Name,
			Category = self.Category,
			Status = self.Status,
			Resolved = self._resolved,
			DisturbedModel = self._disturbedModel,
		}
	end

	return SaltDisturbance
end
