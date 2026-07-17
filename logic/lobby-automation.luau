local DIFFICULTIES = {"Easy", "Medium", "Hard", "Nightmare", "Custom"}

local function difficultyDirection(current, wanted)
	local currentIndex, wantedIndex = table.find(DIFFICULTIES, current), table.find(DIFFICULTIES, wanted)
	if not currentIndex or not wantedIndex then return "Plus" end
	local plus = (wantedIndex - currentIndex) % #DIFFICULTIES
	local minus = (currentIndex - wantedIndex) % #DIFFICULTIES
	return plus <= minus and "Plus" or "Minus"
end

return function(dependencies)
	local Player = assert(dependencies.Player, "lobby-automation requires Player")
	local Remotes = assert(dependencies.Remotes, "lobby-automation requires Remotes")
	local SettingsApi = assert(dependencies.LobbySettings, "lobby-automation requires LobbySettings")
	local settings = assert(dependencies.Settings, "lobby-automation requires Settings")
	local prepareTeleport = assert(dependencies.PrepareTeleport,
		"lobby-automation requires PrepareTeleport")
	local view = dependencies.View
	local wait = dependencies.Wait or task.wait
	local spawn = dependencies.Spawn or task.spawn
	local clock = dependencies.Clock or os.clock
	local interval = tonumber(dependencies.Interval) or 0.75
	local runtimeIsActive = dependencies.RuntimeIsActive or function() return true end
	local controller = {
		Enabled = settings.Auto == true,
		Running = false,
		Generation = 0,
		LastDispatch = -math.huge,
		AutoRevision = 0,
		ReadyRevision = 0,
	}

	local function status(text, failed)
		controller.Status = text
		if view and view.SetStatus then view:SetStatus(text, failed == true) end
	end

	local function active(generation)
		return controller.Running and controller.Generation == generation and runtimeIsActive()
	end

	local function cancelled()
		if controller.Automatic then
			if not controller.Enabled or controller.AutoRevision ~= controller.ExpectedAutoRevision then
				return true
			end
			if not controller.AcceptReadyChange
				and controller.ReadyRevision ~= controller.ExpectedReadyRevision then
				return true
			end
		end
		return false
	end

	local function sleep(generation, seconds)
		local deadline = clock() + seconds
		repeat
			if not active(generation) or cancelled() then return false end
			wait(math.min(0.1, math.max(0, deadline - clock())))
		until clock() >= deadline
		return active(generation) and not cancelled()
	end

	local function module(name)
		local ok, callable = pcall(Remotes.Get, Remotes, name)
		if not ok or callable == nil then return nil, name .. " was unavailable" end
		return callable
	end

	local function remote(name, ...)
		local callable, reason = module(name)
		if type(callable) ~= "function" then return false, reason or name .. " was not callable" end
		local fired, failure = pcall(callable, ...)
		return fired, fired and nil or tostring(failure)
	end

	local function signal(name, ...)
		local callable, reason = module(name)
		if type(callable) ~= "table" or type(callable.Signal) ~= "function" then
			return false, reason or name .. " could not be signalled"
		end
		local fired, failure = pcall(callable.Signal, ...)
		return fired, fired and nil or tostring(failure)
	end

	local function dispatch(generation, name, ...)
		local delay = controller.LastDispatch + interval - clock()
		if delay > 0 and not sleep(generation, delay) then return false, "cancelled" end
		if not active(generation) or cancelled() then return false, "cancelled" end
		local fired, reason = remote(name, ...)
		controller.LastDispatch = clock()
		return fired, reason
	end

	local function dispatchObserved(generation, name, beforeFire, ...)
		local delay = controller.LastDispatch + interval - clock()
		if delay > 0 and not sleep(generation, delay) then return false, "cancelled" end
		if not active(generation) or cancelled() then return false, "cancelled" end
		beforeFire()
		local fired, reason = remote(name, ...)
		controller.LastDispatch = clock()
		return fired, reason
	end

	local function waitUntil(generation, timeout, callback)
		local deadline = clock() + timeout
		repeat
			local done, value = callback()
			if done then return true, value end
			if not active(generation) or cancelled() then return false, "cancelled" end
			wait(0.1)
		until clock() >= deadline
		return false, "timed out"
	end

	local function observe(name, callback)
		local callable = module(name)
		if type(callable) ~= "table" or type(callable.Connect) ~= "function" then return nil end
		return callable.Connect(callback)
	end

	local function presets(reader)
		return dependencies[reader] and dependencies[reader]()
			or SettingsApi[reader](Player)
	end

	local function selectedJobSite()
		if dependencies.ReadSelectedJobSite then return dependencies.ReadSelectedJobSite() end
		return SettingsApi.ReadSelectedJobSite(Player)
	end

	local function selectedDifficulty()
		if dependencies.ReadSelectedDifficulty then return dependencies.ReadSelectedDifficulty() end
		return SettingsApi.ReadSelectedDifficulty(Player)
	end

	local function challengeStates()
		if dependencies.ReadChallengeStates then return dependencies.ReadChallengeStates() end
		return SettingsApi.ReadChallengeStates(Player)
	end

	local function presetExists(reader, name)
		return table.find(presets(reader), name) ~= nil
	end

	local function waitForLobbyState(generation)
		return waitUntil(generation, 4, function()
			local job, jobReady = selectedJobSite()
			local difficulty, difficultyReady = selectedDifficulty()
			local challenges = challengeStates()
			local challengeReady = true
			for index = 1, 3 do
				if type(challenges[index]) ~= "boolean" then challengeReady = false break end
			end
			local ready = Player:GetAttribute("IsReady")
			return jobReady and difficultyReady and challengeReady and type(ready) == "boolean", {
				JobSite = job, Difficulty = difficulty, Challenges = challenges, Ready = ready,
			}
		end)
	end

	local function run(generation, returnedToLobby)
		status("Waiting for lobby data...")
		if not sleep(generation, 4) then return false, "cancelled" end
		controller.LastDispatch = clock()
		if returnedToLobby and not controller.LoadingFinished then
			status("Finishing the lobby return...")
			local fired, reason = dispatch(generation, "LoadingFinished")
			if not fired then return false, reason end
			controller.LoadingFinished = true
		end

		status("Waiting for lobby data...")
		local ready, snapshot = waitForLobbyState(generation)
		if not ready then return false, "Lobby state did not load." end
		local jobSite = tostring(settings.JobSite or "School")
		local difficulty = tostring(settings.Difficulty or "Nightmare")
		local customPreset = tostring(settings.CustomPreset or "")
		local equipmentPreset = tostring(settings.EquipmentPreset or "")
		if difficulty ~= "Custom" then settings.GhostWalkSpeedMultiplier = nil end
		if difficulty == "Custom" then
			if customPreset == "" then return false, "Select a custom difficulty preset." end
			local loaded = waitUntil(generation, 10, function()
				return presetExists("ReadCustomPresets", customPreset)
			end)
			if not loaded then return false, "Custom preset '" .. customPreset .. "' did not load." end
		end
		if equipmentPreset == "" then return false, "Select an equipment preset." end
		local equipmentLoaded = waitUntil(generation, 10, function()
			return presetExists("ReadEquipmentPresets", equipmentPreset)
		end)
		if not equipmentLoaded then return false, "Equipment preset '" .. equipmentPreset .. "' did not load." end

		if settings.ChallengesConfigured ~= true then
			settings.Challenges = table.clone(snapshot.Challenges)
			settings.ChallengesConfigured = true
			if dependencies.OnSettingsChanged then dependencies.OnSettingsChanged(settings) end
		end

		if snapshot.JobSite ~= jobSite then
			status("Selecting " .. jobSite .. "...")
			local report, sent
			local connection = observe("UpdateJobSite", function(value)
				if sent then report = value end
			end)
			if not connection then return false, "UpdateJobSite was unavailable." end
			local fired, reason = dispatchObserved(generation, "ChangeJobSite", function()
				sent = true
			end, jobSite)
			if not fired then if connection then connection:Disconnect() end return false, reason end
			local confirmed = waitUntil(generation, 4, function()
				local selected, stateReady = selectedJobSite()
				return stateReady and selected == jobSite and (not connection or report == jobSite)
			end)
			if connection then connection:Disconnect() end
			if not confirmed then return false, "Job Site did not confirm " .. jobSite .. "." end
		end

		local current, difficultyReady = selectedDifficulty()
		if not difficultyReady then return false, "Difficulty controls were unavailable." end
		if current ~= difficulty then
			status("Selecting " .. difficulty .. "...")
			local report
			local connection = observe("UpdateDifficulty", function(value) report = tostring(value) end)
			if not connection then return false, "UpdateDifficulty was unavailable." end
			for _ = 1, #DIFFICULTIES + 1 do
				if current == difficulty then break end
				local previousReport
				local fired, reason = dispatchObserved(generation, "ChangeDifficulty", function()
					previousReport = report
				end, difficultyDirection(current, difficulty))
				if not fired then if connection then connection:Disconnect() end return false, reason end
				local changed = waitUntil(generation, 4, function()
					local selected, stateReady = selectedDifficulty()
					if report and report ~= previousReport then current = report end
					return report and report ~= previousReport and stateReady and selected == report
				end)
				if not changed then break end
			end
			if connection then connection:Disconnect() end
			if current ~= difficulty then return false, "Difficulty did not confirm " .. difficulty .. "." end
			if connection and report ~= difficulty then
				return false, "Difficulty server response did not confirm " .. difficulty .. "."
			end
		end
		local synced, syncReason = signal("UpdateDifficulty", difficulty)
		if not synced then return false, syncReason end

		local customPayload
		if difficulty == "Custom" then
			status("Applying " .. customPreset .. "...")
			local multiplier, sent
			local connection = observe("UpdateAllCustomDifficultySettings", function(payload, value)
				if sent and type(payload) == "table" and next(payload) then
					customPayload, multiplier = payload, value
				end
			end)
			if not connection and not dependencies.WaitCustomPreset then
				return false, "UpdateAllCustomDifficultySettings was unavailable."
			end
			local fired, reason = dispatchObserved(generation, "ApplyDifficultyPreset", function()
				sent = true
			end, customPreset)
			if not fired then if connection then connection:Disconnect() end return false, reason end
			if dependencies.WaitCustomPreset then
				customPayload, multiplier = dependencies.WaitCustomPreset(customPreset)
			end
			local confirmed = waitUntil(generation, 4, function()
				return type(customPayload) == "table" and next(customPayload) ~= nil
			end)
			if connection then connection:Disconnect() end
			if not confirmed then return false, "Custom preset did not publish its settings." end
			local matched = waitUntil(generation, 4, function()
				return dependencies.CustomDifficultyMatches
					and dependencies.CustomDifficultyMatches(customPayload)
					or SettingsApi.CustomDifficultyMatches(Player, customPayload)
			end)
			if not matched then return false, "Custom preset settings were not applied." end
			settings.GhostWalkSpeedMultiplier = tonumber(customPayload.GhostWalkSpeedMultiplier)
			settings.CustomMultiplier = multiplier
		end

		status("Applying equipment...")
		local equipmentFired, equipmentReason = dispatch(generation,
			"ApplyEquipmentPreset", equipmentPreset)
		if not equipmentFired then return false, equipmentReason end

		local desiredChallenges = settings.Challenges or {}
		local currentChallenges = challengeStates()
		for index = 1, 3 do
			if currentChallenges[index] ~= (desiredChallenges[index] == true) then
				status("Setting challenge " .. index .. "...")
				local fired, reason = dispatch(generation, "ToggleChallenge", index)
				if not fired then return false, reason end
			end
		end
		local challengesConfirmed = waitUntil(generation, 4, function()
			return SettingsApi.ChallengeStatesMatch(challengeStates(), desiredChallenges)
		end)
		if not challengesConfirmed then return false, "Challenge states were not confirmed." end

		local isReady = Player:GetAttribute("IsReady")
		if isReady == false then
			status("Readying player...")
			local readyRevision = controller.ReadyRevision
			controller.AcceptReadyChange = true
			local fired, reason = dispatch(generation, "ChangeStatus")
			if not fired then controller.AcceptReadyChange = false return false, reason end
			local confirmed = waitUntil(generation, 2, function()
				return Player:GetAttribute("IsReady") == true
			end)
			wait(0)
			controller.AcceptReadyChange = false
			if not confirmed or controller.ReadyRevision > readyRevision + 1 then
				return false, "Ready state was not confirmed."
			end
			controller.ExpectedReadyRevision = controller.ReadyRevision
		elseif isReady ~= true then
			return false, "Ready state was unavailable."
		end

		local finalJob, finalJobReady = selectedJobSite()
		local finalDifficulty, finalDifficultyReady = selectedDifficulty()
		if not finalJobReady or finalJob ~= jobSite then return false, "Job Site changed before start." end
		if not finalDifficultyReady or finalDifficulty ~= difficulty then
			return false, "Difficulty changed before start."
		end
		if difficulty == "Custom" and not SettingsApi.CustomDifficultyMatches(Player, customPayload) then
			return false, "Custom preset changed before start."
		end
		if not presetExists("ReadEquipmentPresets", equipmentPreset) then
			return false, "Equipment preset disappeared before start."
		end
		if not SettingsApi.ChallengeStatesMatch(challengeStates(), desiredChallenges) then
			return false, "Challenges changed before start."
		end
		if Player:GetAttribute("IsReady") ~= true then return false, "Player became unready." end

		status("Preparing round teleport...")
		if cancelled() then return false, "Lobby start was cancelled." end
		if controller.Enabled then
			local prepared, reason = prepareTeleport("AttemptStart")
			if not prepared then return false, reason or "Teleport handoff failed." end
		end
		local started, startReason = dispatch(generation, "AttemptStart")
		if not started then return false, startReason end
		return true
	end

	local function scheduleRetry(generation, seconds)
		spawn(function()
			local deadline = clock() + (seconds or 4)
			while controller.Enabled and controller.Generation == generation
				and not controller.Teleporting and runtimeIsActive() and clock() < deadline do wait(0.1) end
			if controller.Enabled and controller.Generation == generation
				and not controller.Teleporting and runtimeIsActive() then
				controller.Running = false
				controller:Start(true, true)
			end
		end)
	end

	function controller:SetLoopEnabled(enabled)
		enabled = enabled == true
		if self.Enabled ~= enabled then self.AutoRevision += 1 end
		self.Enabled = enabled
		settings.Auto = self.Enabled
		if dependencies.OnEnabledChanged then dependencies.OnEnabledChanged(self.Enabled) end
		if dependencies.OnSettingsChanged then dependencies.OnSettingsChanged(settings) end
		if not self.Enabled and self.Running then
			self.Generation += 1
			self.Running = false
			if view and view.SetBusy then view:SetBusy(false) end
			status("Automatic continuation stopped.")
		end
		return self.Enabled
	end

	function controller:Start(automatic, returnedToLobby)
		if self.Running or not runtimeIsActive() then return false end
		if automatic and not self.Enabled then return false end
		self.Running = true
		self.Automatic = automatic == true
		self.Teleporting = false
		self.Generation += 1
		self.LastDispatch = -math.huge
		self.ExpectedAutoRevision = self.AutoRevision
		self.ExpectedReadyRevision = self.ReadyRevision
		local generation = self.Generation
		if view and view.SetBusy then view:SetBusy(true) end
		spawn(function()
			local called, succeeded, reason = xpcall(function()
				return run(generation, returnedToLobby == true)
			end, debug.traceback)
			if not active(generation) then return end
			if not called then succeeded, reason = false, succeeded end
			if succeeded then
				status("Settings applied; waiting for teleport...")
				if automatic then scheduleRetry(generation, 12) end
			else
				self.Running = false
				if view and view.SetBusy then view:SetBusy(false) end
				status(tostring(reason or "Lobby start failed."), true)
				if automatic and self.Enabled then scheduleRetry(generation) end
			end
		end)
		return true
	end

	function controller:Destroy()
		self:SetLoopEnabled(false)
		self.Generation += 1
		if self.TeleportConnection then self.TeleportConnection:Disconnect() end
		if self.ReadyConnection then self.ReadyConnection:Disconnect() end
	end

	local onTeleport = Player.OnTeleport
	if onTeleport and onTeleport.Connect then
		controller.TeleportConnection = onTeleport:Connect(function(state)
			if tostring(state):find("Failed", 1, true) and controller.Running then
				controller.Teleporting = false
				local generation = controller.Generation
				controller.Running = false
				status("Teleport failed; retrying...", true)
				if controller.Enabled then scheduleRetry(generation, 4) end
			else
				controller.Teleporting = true
			end
		end)
	end
	if type(Player.GetAttributeChangedSignal) == "function" then
		controller.ReadyConnection = Player:GetAttributeChangedSignal("IsReady"):Connect(function()
			controller.ReadyRevision += 1
		end)
	end

	return controller
end
