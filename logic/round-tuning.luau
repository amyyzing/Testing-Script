return function(dependencies)
	local World = dependencies.Workspace or workspace
	local Game = dependencies.Game or game
	local Storage = assert(dependencies.ReplicatedStorage, "round-tuning requires ReplicatedStorage")
	local Player = assert(dependencies.Player, "round-tuning requires Player")
	local Teleport = assert(dependencies.TeleportService, "round-tuning requires TeleportService")
	local load = dependencies.Require or require
	local now = dependencies.Now or os.time
	local key = "DemonologyRoundTuning"
	local controller = {}
	local modules = Storage:FindFirstChild("Modules")
	local native = modules and modules:FindFirstChild("CustomDifficulty")
	if not native then
		local ok, data = pcall(Teleport.GetTeleportSetting, Teleport, key)
		if ok and type(data) == "table" and data.GameId == Game.GameId
			and type(data.Time) == "number" and now() - data.Time >= 0 and now() - data.Time < 600 then
			controller.Data = data
		end
		pcall(Teleport.SetTeleportSetting, Teleport, key, false)
	end
	function controller:Capture()
		if not native then return end
		local mode = dependencies.ReadDifficulty and dependencies.ReadDifficulty()
		if mode ~= "Custom" then
			self.Data = nil
			pcall(Teleport.SetTeleportSetting, Teleport, key, false)
			return
		end
		local ok, definition = pcall(load, native)
		local gui = Player:FindFirstChildOfClass("PlayerGui")
		local computer = gui and gui:FindFirstChild("ComputerScreen")
		local list = computer and computer:FindFirstChild("SettingsList", true)
		if not ok or type(definition) ~= "table" or not list then return end
		local data = {GameId = Game.GameId, Time = now(), Source = "NativeLobby"}
		for _, option in ipairs(definition.Options or {}) do
			if option.ID == "GhostWalkSpeedMultiplier" or option.ID == "GhostLowerTemperatureRange" then
				local row = list:FindFirstChild(option.ID)
				local index = row and row:GetAttribute("Index")
				local toggle = type(index) == "number" and option.Toggles[index]
				if toggle then data[option.ID] = option.Values and option.Values[toggle] or toggle end
			end
		end
		if type(data.GhostWalkSpeedMultiplier) == "number" then
			self.Data = data
			pcall(Teleport.SetTeleportSetting, Teleport, key, data)
		end
	end
	function controller:GetScale()
		local map = World:FindFirstChild("Map")
		local size = map and map:GetAttribute("MapSize")
		local custom = self.Data and self.Data.GhostWalkSpeedMultiplier
		local mapFactor = size == "Large" and 1.1 or size == "Medium" and 1.05 or 1
		return {CustomMultiplier = custom, MapMultiplier = mapFactor,
			Known = type(custom) == "number" and size == "Small",
			TemperatureMode = self.Data and self.Data.GhostLowerTemperatureRange}
	end
	if native and Player.OnTeleport then
		controller.Connection = Player.OnTeleport:Connect(function(state)
			if tostring(state) == "Enum.TeleportState.Started" then controller:Capture() end
		end)
	end
	function controller:Destroy()
		if self.Connection then self.Connection:Disconnect() end
	end
	return controller
end
