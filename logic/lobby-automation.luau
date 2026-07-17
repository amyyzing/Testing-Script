local DIFFICULTIES = {"Easy", "Medium", "Hard", "Nightmare", "Custom"}

local function difficultyDirection(current, wanted)
	local currentIndex = table.find(DIFFICULTIES, current)
	local wantedIndex = table.find(DIFFICULTIES, wanted)
	if not currentIndex or not wantedIndex then return "Minus" end
	local plus = (wantedIndex - currentIndex) % #DIFFICULTIES
	local minus = (currentIndex - wantedIndex) % #DIFFICULTIES
	return plus <= minus and "Plus" or "Minus"
end

return function(dependencies)
	local Player = assert(dependencies.Player, "lobby-automation requires Player")
	local Remotes = assert(dependencies.Remotes, "lobby-automation requires Remotes")
	local prepareTeleport = assert(dependencies.PrepareTeleport,
		"lobby-automation requires PrepareTeleport")
	local button = dependencies.Button
	local wait = dependencies.Wait or task.wait
	local spawn = dependencies.Spawn or task.spawn
	local interval = tonumber(dependencies.Interval) or 0.75
	local settings = dependencies.Settings or {}
	local jobSite = settings.JobSite or "School"
	local difficulty = settings.Difficulty or "Custom"
	local difficultyPreset = settings.DifficultyPreset or "john4"
	local equipmentPreset = settings.EquipmentPreset or "green"
	local disabledColor = button and button.BackgroundColor3
	local enabledColor = dependencies.EnabledColor or disabledColor
	local controller = {Enabled = false, Generation = 0, Phase = "Click to start loop"}

	local function render()
		if not button then return end
		button.Text = controller.Enabled
			and "AUTOMATION: ON\n" .. controller.Phase
			or "AUTOMATION: OFF\nClick to start loop"
		button.BackgroundColor3 = controller.Enabled and enabledColor or disabledColor
	end

	local function phase(text)
		controller.Phase = text
		render()
	end

	local function active(generation)
		return controller.Enabled and controller.Generation == generation
	end

	local function pause(generation)
		wait(interval)
		return active(generation)
	end

	local function fire(name, ...)
		local ok, callable = pcall(Remotes.Get, Remotes, name)
		if not ok or type(callable) ~= "function" then return false end
		return pcall(callable, ...)
	end

	local function findPath(root, names)
		for _, name in ipairs(names) do
			root = root and root:FindFirstChild(name)
		end
		return root
	end

	local function selectedJobSite()
		if dependencies.ReadJobSite then return dependencies.ReadJobSite() end
		local gui = Player:FindFirstChildOfClass("PlayerGui")
		local locations = findPath(gui, {"ComputerScreen", "JobSite", "Content",
			"MapContainer", "Locations"})
		if not locations then return nil end
		for _, location in ipairs(locations:GetChildren()) do
			if location:GetAttribute("Selected") == true then return location.Name end
		end
		return nil
	end

	local function selectedDifficulty()
		if dependencies.ReadDifficulty then return dependencies.ReadDifficulty() end
		local gui = Player:FindFirstChildOfClass("PlayerGui")
		local label = findPath(gui, {"ComputerScreen", "JobSite", "Content",
			"BottomBar", "DifficultyLabel"})
		local text = label and tostring(label.Text or "") or ""
		return text:match("^%s*Difficulty%s*%-%s*(.-)%s*$")
	end

	local function waitForValue(reader, generation, timeout)
		local deadline = os.clock() + (timeout or 4)
		repeat
			local value = reader()
			if value ~= nil then return value end
			if not active(generation) then return nil end
			wait(0.1)
		until os.clock() >= deadline
		return nil
	end

	local function run(generation, returnedToLobby)
		if returnedToLobby then
			phase("Finishing lobby load")
			if not fire("LoadingFinished") then phase("Loading handshake failed") return end
			if not pause(generation) then return end
		end

		phase("Selecting " .. jobSite)
		local currentJobSite = waitForValue(selectedJobSite, generation)
		if not currentJobSite then phase("Job Site state unavailable") return end
		if currentJobSite ~= jobSite then
			if not fire("ChangeJobSite", jobSite) then phase("Job Site remote failed") return end
			if not pause(generation) then return end
			local confirmed = waitForValue(selectedJobSite, generation, 2)
			if confirmed ~= jobSite then phase("Job Site was not selected") return end
		end

		phase("Selecting " .. difficulty)
		local current = waitForValue(selectedDifficulty, generation)
		if not current then phase("Difficulty state unavailable") return end
		if current ~= difficulty then
			local attempts = #DIFFICULTIES + 1
			for _ = 1, attempts do
				if not fire("ChangeDifficulty", difficultyDirection(current, difficulty)) then
					phase("Difficulty remote failed")
					return
				end
				if not pause(generation) then return end
				current = selectedDifficulty()
				if current == difficulty then break end
			end
			if current ~= difficulty then phase("Difficulty was not selected") return end
		end

		if difficulty == "Custom" then
			phase("Applying " .. difficultyPreset)
			if not fire("ApplyDifficultyPreset", difficultyPreset) then
				phase("Difficulty preset failed")
				return
			end
			if not pause(generation) then return end
		end

		phase("Applying equipment")
		if not fire("ApplyEquipmentPreset", equipmentPreset) then
			phase("Equipment preset failed")
			return
		end
		if not pause(generation) then return end

		local ready = waitForValue(function()
			local value = Player:GetAttribute("IsReady")
			if type(value) == "boolean" then return value end
			return nil
		end, generation)
		if ready == nil then phase("Ready state unavailable") return end
		if not ready then
			phase("Readying player")
			if not fire("ChangeStatus") then phase("Ready remote failed") return end
			if not pause(generation) then return end
			if Player:GetAttribute("IsReady") ~= true then phase("Ready state was not confirmed") return end
		end

		if selectedJobSite() ~= jobSite then phase("Job Site changed before start") return end
		if selectedDifficulty() ~= difficulty then phase("Difficulty changed before start") return end
		phase("Starting round")
		local prepared, reason = prepareTeleport("AttemptStart")
		if not prepared then
			phase(reason or "Teleport handoff failed")
			return
		end
		if not fire("AttemptStart") then phase("Round start failed") return end
		phase("Waiting for game")
	end

	function controller:SetEnabled(enabled, returnedToLobby)
		enabled = enabled == true
		if self.Enabled == enabled then return self.Enabled end
		self.Enabled = enabled
		self.Generation += 1
		if dependencies.OnEnabledChanged then dependencies.OnEnabledChanged(enabled) end
		if enabled then
			local generation = self.Generation
			spawn(function() run(generation, returnedToLobby == true) end)
		else
			self.Phase = "Click to start loop"
		end
		render()
		return self.Enabled
	end

	function controller:Toggle()
		return self:SetEnabled(not self.Enabled, false)
	end

	function controller:Destroy()
		self:SetEnabled(false)
		if self.ButtonConnection then self.ButtonConnection:Disconnect() end
	end

	if button then
		controller.ButtonConnection = button.MouseButton1Click:Connect(function() controller:Toggle() end)
	end
	render()
	return controller
end
