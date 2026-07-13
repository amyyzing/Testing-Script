local SignalBridge = {}
SignalBridge.__index = SignalBridge

local function disconnect(connection)
	if type(connection) == "function" then
		connection()
	elseif connection ~= nil and type(connection.Disconnect) == "function" then
		pcall(connection.Disconnect, connection)
	end
end

function SignalBridge.new(sources, options)
	options = type(options) == "table" and options or {}
	return setmetatable({
		Name = options.Name or "SignalBridge",
		Category = "Active",
		Status = "Idle",
		_sources = type(sources) == "table" and sources or {},
		_connections = {},
		_context = nil,
		_emitted = 0,
	}, SignalBridge)
end

SignalBridge.New = SignalBridge.new

function SignalBridge:Start(context)
	self._context = context or {}
	self.Status = "Active"
	for _, source in ipairs(self._sources) do
		local descriptor = type(source) == "table" and source or {}
		local signal = descriptor.Signal or source
		local connect = signal and signal.Connect
		if type(connect) == "function" then
			local callback = function(...)
				if self.Status ~= "Active" then
					return
				end
				local event = type(descriptor.Transform) == "function"
					and descriptor.Transform(...)
					or select(1, ...)
				if type(event) == "table" and type(self._context.Emit) == "function" then
					event.Source = event.Source or descriptor.Name or self.Name
					self._emitted = self._emitted + 1
					self._context.Emit(event)
				end
			end
			local ok, connection
			if descriptor.Signal ~= nil or type(source) ~= "table" then
				ok, connection = pcall(connect, signal, callback)
			else
				-- Wrapper Connect functions use Connect(callback); raw signals should
				-- be provided directly or through descriptor.Signal.
				ok, connection = pcall(connect, callback)
			end
			if ok then
				table.insert(self._connections, connection)
			end
		end
	end
end

function SignalBridge:OnEvent() end

function SignalBridge:Stop()
	for _, connection in ipairs(self._connections) do
		disconnect(connection)
	end
	table.clear(self._connections)
	self.Status = "Stopped"
end

function SignalBridge:Reset()
	self:Stop()
	self._emitted = 0
	self.Status = "Idle"
end

function SignalBridge:Destroy()
	self:Stop()
	self._context = nil
	self.Status = "Destroyed"
end

function SignalBridge:Snapshot()
	return {
		Name = self.Name,
		Category = self.Category,
		Status = self.Status,
		ConnectionCount = #self._connections,
		Emitted = self._emitted,
	}
end

return SignalBridge
