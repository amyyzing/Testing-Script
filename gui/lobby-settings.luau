local LobbySettings = {}

LobbySettings.JobSites = {
	{Name = "Lincoln St", Size = "Small", Description = "We received a call from a family reporting paranormal activity at their house.\n———\nMap by w4570, AlexW0ndxr, & Disgruntled_Skeleton"},
	{Name = "Fenway Drive", Size = "Small", Description = "A real estate agent called us concerned about an ominous feeling they had in one of their listings.\n———\nMap by AlexW0ndxr"},
	{Name = "Juniper Road", Size = "Small", Description = "We've had multiple reports of a haunting on Juniper Road.\n———\nMap by w4570"},
	{Name = "Bodega", Size = "Small", LevelRequirement = 6, Description = "The owner of this NYC Bodega believes they've seen ghostly activity.\n———\nMap by w4570 & Calilies"},
	{Name = "Lilim Lane", Size = "Medium", LevelRequirement = 4, Description = "A traditional Filipino home has been reported as haunted by the architect.\n———\nMap by w4570"},
	{Name = "Cafe", Size = "Medium", LevelRequirement = 8, Description = "Popular coffee establishment HVNLY Coffee has had a ton of customers harmed by flying furniture.\n———\nMap by w4570"},
	{Name = "Bridgewood Drive", Size = "Medium", LevelRequirement = 16, Description = "One of our high-end clients reported unusual activity at their mansion located in the forest.\n———\nMap by w4570"},
	{Name = "Oakbridge Estates", Size = "Medium", LevelRequirement = 25, Description = "A haunting has been reported somewhere on this estate, though the exact origin within the property remains unknown.\n———\nMap by w4570"},
	{Name = "Prison", Size = "Large", LevelRequirement = 9, Description = "The state had to shut down their prison due to several injuries caused by a ghost.\n———\nMap by w4570, Steven_Spectacle, & phazmas"},
	{Name = "School", Size = "Large", LevelRequirement = 13, Description = "Several students have been injured by objects thrown seemingly by nothing.\n———\nMap by w4570"},
	{Name = "Asylum", Size = "Large", LevelRequirement = 20, Description = "This 20th century insane asylum has long been subject of haunting rumors, and the state has decided to do something about it.\n———\nMap by w4570"},
}
LobbySettings.Difficulties = {"Easy", "Medium", "Hard", "Nightmare", "Custom"}

function LobbySettings.JobSiteNames()
	local names = {}
	for _, site in ipairs(LobbySettings.JobSites) do table.insert(names, site.Name) end
	return names
end

local function findPath(root, names)
	for _, name in ipairs(names) do root = root and root:FindFirstChild(name) end
	return root
end

local function presetNames(player, path)
	local list = findPath(player and player:FindFirstChild("PlayerGui"), path)
	local result = {}
	if list then
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("Frame") and child:FindFirstChild("Delete", true) then
				table.insert(result, child.Name)
			end
		end
	end
	table.sort(result, function(a, b) return string.lower(a) < string.lower(b) end)
	return result
end

function LobbySettings.ReadCustomPresets(player)
	return presetNames(player, {"ComputerScreen", "JobSite", "DifficultySettings", "PresetList"})
end

function LobbySettings.ReadEquipmentPresets(player)
	return presetNames(player, {"ComputerScreen", "Equipment", "PartyLog", "PresetList"})
end

function LobbySettings.ReadSelectedJobSite(player)
	local locations = findPath(player and player:FindFirstChild("PlayerGui"), {
		"ComputerScreen", "JobSite", "Content", "MapContainer", "Locations",
	})
	if not locations then return nil, false end
	local selected, count
	count = 0
	for _, location in ipairs(locations:GetChildren()) do
		if location:IsA("Frame") then
			count += 1
			if location:GetAttribute("Selected") == true then
				if selected then return nil, false end
				selected = location.Name
			end
		end
	end
	return selected, count > 0
end

function LobbySettings.ReadSelectedDifficulty(player)
	local label = findPath(player and player:FindFirstChild("PlayerGui"), {
		"ComputerScreen", "JobSite", "Content", "BottomBar", "DifficultyLabel",
	})
	local selected = label and tostring(label.Text or ""):match("^%s*Difficulty%s*%-%s*(.-)%s*$")
	return selected, table.find(LobbySettings.Difficulties, selected) ~= nil
end

function LobbySettings.ReadChallengeStates(player)
	local list = findPath(player and player:FindFirstChild("PlayerGui"), {
		"ComputerScreen", "JobSite", "Challenges", "Content", "ChallengeList",
	})
	local result = {}
	for index = 1, 3 do
		local label = findPath(list and list:FindFirstChild("Challenge" .. index), {"Toggle", "TextLabel"})
		local text = label and string.upper(tostring(label.Text or ""))
		if text == "ON" then result[index] = true elseif text == "OFF" then result[index] = false end
	end
	return result
end

function LobbySettings.CustomDifficultyMatches(player, payload)
	if type(payload) ~= "table" or next(payload) == nil then return false end
	local list = findPath(player and player:FindFirstChild("PlayerGui"), {
		"ComputerScreen", "JobSite", "DifficultySettings", "Content", "SettingsList",
	})
	if not list then return false end
	for name, expected in pairs(payload) do
		local frame = list:FindFirstChild(tostring(name))
		if not frame or frame:GetAttribute("Index") ~= expected then return false end
	end
	return true
end

function LobbySettings.ChallengeStatesMatch(current, wanted)
	for index = 1, 3 do
		if type(current[index]) ~= "boolean" or current[index] ~= (wanted[index] == true) then return false end
	end
	return true
end

local function create(className, properties, parent)
	local object = Instance.new(className)
	for property, value in pairs(properties) do object[property] = value end
	object.Parent = parent
	return object
end

function LobbySettings.Create(options)
	local view = assert(options.View, "lobby-settings requires View")
	local player = assert(options.Player, "lobby-settings requires Player")
	local settings = assert(options.Settings, "lobby-settings requires Settings")
	local changed = options.OnChanged or function() end
	local connections, dropdowns = {}, {}
	local content, colors = view.Content, view.Colors
	for name, button in pairs(view.Buttons) do button.Visible = name == "Automation" end
	local autoButton = view.Buttons.Automation
	autoButton.Position = UDim2.fromOffset(16, 206)
	autoButton.Size = UDim2.new(1, -32, 0, 34)

	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(connections, connection)
		return connection
	end

	local function closeDropdowns(except)
		for _, dropdown in ipairs(dropdowns) do
			if dropdown ~= except then dropdown.List.Visible = false end
		end
	end

	local function dropdown(name, y, label, items, read, write)
		local button = create("TextButton", {
			Name = name, AutoButtonColor = false, BackgroundColor3 = colors.Control,
			BorderSizePixel = 0, Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(16, y), Size = UDim2.new(1, -32, 0, 32),
			TextColor3 = colors.Text, TextSize = 11, ZIndex = 10,
		}, content)
		local list = create("ScrollingFrame", {
			Name = name .. "List", Active = true, AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = colors.Title, BorderSizePixel = 0, CanvasSize = UDim2.new(),
			Position = UDim2.fromOffset(16, y + 32), ScrollBarThickness = 3,
			Size = UDim2.new(1, -32, 0, 140), Visible = false, ZIndex = 30,
		}, content)
		create("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}, list)
		local control = {Button = button, List = list}
		table.insert(dropdowns, control)
		function control:Refresh()
			for _, child in ipairs(list:GetChildren()) do
				if child:IsA("TextButton") then child:Destroy() end
			end
			for index, value in ipairs(items()) do
				local option = create("TextButton", {
					Name = tostring(value), AutoButtonColor = false,
					BackgroundColor3 = colors.Control, BorderSizePixel = 0,
					Font = Enum.Font.Gotham, LayoutOrder = index,
					Size = UDim2.new(1, -3, 0, 28), Text = tostring(value),
					TextColor3 = colors.Text, TextSize = 11, ZIndex = 31,
				}, list)
				connect(option.MouseButton1Click, function()
					write(value)
					list.Visible = false
					control:Render()
					changed(settings)
				end)
			end
		end
		function control:Render() button.Text = label .. ": " .. tostring(read() or "Select") .. "  v" end
		connect(button.MouseButton1Click, function()
			local opening = not list.Visible
			closeDropdowns(control)
			if opening then control:Refresh() end
			list.Visible = opening
		end)
		control:Render()
		return control
	end

	local job = dropdown("JobSite", 16, "JOB SITE", LobbySettings.JobSiteNames,
		function() return settings.JobSite end, function(value) settings.JobSite = value end)
	local difficulty = dropdown("Difficulty", 54, "DIFFICULTY", function() return LobbySettings.Difficulties end,
		function() return settings.Difficulty end, function(value) settings.Difficulty = value end)
	local custom = dropdown("CustomPreset", 92, "CUSTOM PRESET",
		function() return LobbySettings.ReadCustomPresets(player) end,
		function() return settings.CustomPreset end, function(value) settings.CustomPreset = value end)
	local equipment = dropdown("EquipmentPreset", 130, "EQUIPMENT",
		function() return LobbySettings.ReadEquipmentPresets(player) end,
		function() return settings.EquipmentPreset end, function(value) settings.EquipmentPreset = value end)

	local challengeButtons = {}
	for index = 1, 3 do
		local button = create("TextButton", {
			Name = "Challenge" .. index, AutoButtonColor = false,
			BackgroundColor3 = colors.Control, BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium, Position = UDim2.fromOffset(16 + (index - 1) * 130, 168),
			Size = UDim2.fromOffset(120, 30), TextColor3 = colors.Text, TextSize = 10,
		}, content)
		challengeButtons[index] = button
		connect(button.MouseButton1Click, function()
			settings.Challenges[index] = not settings.Challenges[index]
			settings.ChallengesConfigured = true
			button.Text = ("CHALLENGE %d: %s"):format(index, settings.Challenges[index] and "ON" or "OFF")
			button.BackgroundColor3 = settings.Challenges[index] and colors.Accent or colors.Control
			changed(settings)
		end)
	end

	local start = create("TextButton", {
		Name = "StartRound", AutoButtonColor = false, BackgroundColor3 = colors.Accent,
		BorderSizePixel = 0, Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(16, 248), Size = UDim2.new(1, -32, 0, 34),
		Text = "START ROUND", TextColor3 = colors.Text, TextSize = 12,
	}, content)
	local status = create("TextLabel", {
		Name = "LobbyStatus", BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(16, 288), Size = UDim2.new(1, -32, 0, 32),
		Text = "Choose settings, then start the round.", TextColor3 = colors.Muted,
		TextSize = 10, TextWrapped = true,
	}, content)

	local lobby = {Gui = view.Gui, Settings = settings, StartButton = start, AutoButton = autoButton}
	function lobby:Render()
		job:Render(); difficulty:Render(); custom:Render(); equipment:Render()
		custom.Button.Visible = settings.Difficulty == "Custom"
		if not custom.Button.Visible then custom.List.Visible = false end
		for index, button in ipairs(challengeButtons) do
			button.Text = ("CHALLENGE %d: %s"):format(index, settings.Challenges[index] and "ON" or "OFF")
			button.BackgroundColor3 = settings.Challenges[index] and colors.Accent or colors.Control
		end
		autoButton.Text = settings.Auto and "AUTOMATION: ON" or "AUTOMATION: OFF"
		autoButton.BackgroundColor3 = settings.Auto and colors.Accent or colors.Control
	end
	function lobby:SetStatus(text, failed)
		status.Text = tostring(text)
		status.TextColor3 = failed and colors.Danger or colors.Muted
	end
	function lobby:SetBusy(busy)
		start.Text = busy and "STARTING..." or "START ROUND"
		start.BackgroundColor3 = busy and colors.Control or colors.Accent
		self.Busy = busy
		closeDropdowns()
	end
	connect(autoButton.MouseButton1Click, function()
		settings.Auto = not settings.Auto
		changed(settings, "Auto")
		lobby:Render()
	end)
	connect(start.MouseButton1Click, function()
		if not lobby.Busy and options.OnStart then options.OnStart(settings) end
	end)
	lobby:Render()
	function lobby:Destroy()
		for _, connection in ipairs(connections) do connection:Disconnect() end
	end
	return lobby
end

return LobbySettings
