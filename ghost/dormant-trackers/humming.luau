return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "humming requires Traffic")
	local ReplicatedStorage = dependencies.ReplicatedStorage
	if not ReplicatedStorage and not dependencies.RemoteSignal
		and not dependencies.LocalSignal then
		ReplicatedStorage = game:GetService("ReplicatedStorage")
	end
	local Player = dependencies.Player
	local Tracker = {
		Kind = "dormant",
		Running = true,
		Active = false,
		Resolved = false,
		EnabledStates = setmetatable({}, {__mode = "k"}),
		Connections = {},
	}

	local function normalize(value)
		return string.lower(tostring(value or "")):gsub("%s+", "")
	end

	local function response(value)
		if not Tracker.Running or not Tracker.Active or Tracker.Resolved
			or normalize(value) ~= "-humming-" then return end
		Tracker.Resolved = true
		Traffic("Humming", {Response = "- HUMMING -"}):SendTo("Siren")
	end

	local function bind(signal)
		if not signal then return end
		table.insert(Tracker.Connections, signal:Connect(response))
	end

	if dependencies.RemoteSignal or dependencies.LocalSignal then
		bind(dependencies.RemoteSignal)
		bind(dependencies.LocalSignal)
	else
		local events = ReplicatedStorage:FindFirstChild("Events")
		local remote = events and events:FindFirstChild("ShowSubtitle")
		if remote and remote:IsA("RemoteEvent") then bind(remote.OnClientEvent) end
		local scripts = Player and Player:FindFirstChild("PlayerScripts")
		local localEvents = scripts and scripts:FindFirstChild("Events")
		local localEvent = localEvents and localEvents:FindFirstChild("ShowSubtitle")
		if localEvent and localEvent:IsA("BindableEvent") then bind(localEvent.Event) end
	end

	Tracker.Disconnect = Traffic:Receive("Humming", function(signal, payload)
		if signal ~= "SpiritBoxState" or type(payload) ~= "table" then return end
		local state = payload.State or payload.Item
		if not state then return end
		if payload.Enabled == true then Tracker.EnabledStates[state] = true
		else Tracker.EnabledStates[state] = nil end
		Tracker.Active = next(Tracker.EnabledStates) ~= nil
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
		for _, connection in ipairs(self.Connections) do connection:Disconnect() end
		table.clear(self.Connections)
		table.clear(self.EnabledStates)
	end

	return Tracker
end
