local LobbySettings = {}

LobbySettings.JobSites = {
	{
		Name = "Lincoln St",
		Size = "Small",
		Description = "We received a call from a family reporting paranormal activity at their house.\n———\nMap by w4570, AlexW0ndxr, & Disgruntled_Skeleton",
	},
	{
		Name = "Fenway Drive",
		Size = "Small",
		Description = "A real estate agent called us concerned about an ominous feeling they had in one of their listings.\n———\nMap by AlexW0ndxr",
	},
	{
		Name = "Juniper Road",
		Size = "Small",
		Description = "We've had multiple reports of a haunting on Juniper Road.\n———\nMap by w4570",
	},
	{
		Name = "Bodega",
		Size = "Small",
		LevelRequirement = 6,
		Description = "The owner of this NYC Bodega believes they've seen ghostly activity.\n———\nMap by w4570 & Calilies",
	},
	{
		Name = "Lilim Lane",
		Size = "Medium",
		LevelRequirement = 4,
		Description = "A traditional Filipino home has been reported as haunted by the architect.\n———\nMap by w4570",
	},
	{
		Name = "Cafe",
		Size = "Medium",
		LevelRequirement = 8,
		Description = "Popular coffee establishment HVNLY Coffee has had a ton of customers harmed by flying furniture.\n———\nMap by w4570",
	},
	{
		Name = "Bridgewood Drive",
		Size = "Medium",
		LevelRequirement = 16,
		Description = "One of our high-end clients reported unusual activity at their mansion located in the forest.\n———\nMap by w4570",
	},
	{
		Name = "Oakbridge Estates",
		Size = "Medium",
		LevelRequirement = 25,
		Description = "A haunting has been reported somewhere on this estate, though the exact origin within the property remains unknown.\n———\nMap by w4570",
	},
	{
		Name = "Prison",
		Size = "Large",
		LevelRequirement = 9,
		Description = "The state had to shut down their prison due to several injuries caused by a ghost.\n———\nMap by w4570, Steven_Spectacle, & phazmas",
	},
	{
		Name = "School",
		Size = "Large",
		LevelRequirement = 13,
		Description = "Several students have been injured by objects thrown seemingly by nothing.\n———\nMap by w4570",
	},
	{
		Name = "Asylum",
		Size = "Large",
		LevelRequirement = 20,
		Description = "This 20th century insane asylum has long been subject of haunting rumors, and the state has decided to do something about it.\n———\nMap by w4570",
	},
}

LobbySettings.Difficulties = {"Easy", "Medium", "Hard", "Nightmare", "Custom"}

local function findPath(root, names)
	local current = root
	for _, name in ipairs(names) do
		current = current and current:FindFirstChild(name)
		if not current then
			return nil
		end
	end
	return current
end

local function readPresetNames(player, path)
	local playerGui = player and player:FindFirstChild("PlayerGui")
	local presetList = findPath(playerGui, path)
	local presets = {}
	local seen = {}
	if presetList then
		for _, child in ipairs(presetList:GetChildren()) do
			if child:IsA("Frame")
				and child:FindFirstChild("Delete", true)
				and child.Name ~= ""
				and not seen[child.Name] then
				seen[child.Name] = true
				table.insert(presets, child.Name)
			end
		end
	end
	table.sort(presets, function(left, right)
		return string.lower(left) < string.lower(right)
	end)
	return presets
end

function LobbySettings.ReadCustomPresets(player)
	return readPresetNames(player, {
		"ComputerScreen",
		"JobSite",
		"DifficultySettings",
		"PresetList",
	})
end

function LobbySettings.ReadEquipmentPresets(player)
	return readPresetNames(player, {
		"ComputerScreen",
		"Equipment",
		"PartyLog",
		"PresetList",
	})
end

function LobbySettings.ReadSelectedJobSite(player)
	local playerGui = player and player:FindFirstChild("PlayerGui")
	local locations = findPath(playerGui, {
		"ComputerScreen",
		"JobSite",
		"Content",
		"MapContainer",
		"Locations",
	})
	if not locations then
		return nil, false
	end
	local selected
	local locationCount = 0
	for _, location in ipairs(locations:GetChildren()) do
		if location:IsA("Frame") then
			locationCount = locationCount + 1
			if location:GetAttribute("Selected") == true then
				if selected then
					return nil, false
				end
				selected = location.Name
			end
		end
	end
	return selected, locationCount > 0
end

function LobbySettings.ReadSelectedDifficulty(player)
	local playerGui = player and player:FindFirstChild("PlayerGui")
	local label = findPath(playerGui, {
		"ComputerScreen",
		"JobSite",
		"Content",
		"BottomBar",
		"DifficultyLabel",
	})
	local text = label and tostring(label.Text or "") or ""
	local selected = string.match(text, "^%s*Difficulty%s*%-%s*(.-)%s*$")
	if selected and table.find(LobbySettings.Difficulties, selected) then
		return selected, true
	end
	return nil, false
end

function LobbySettings.CustomDifficultyMatches(player, settingsPayload)
	if type(settingsPayload) ~= "table" or next(settingsPayload) == nil then
		return false
	end
	local playerGui = player and player:FindFirstChild("PlayerGui")
	local settingsList = findPath(playerGui, {
		"ComputerScreen",
		"JobSite",
		"DifficultySettings",
		"Content",
		"SettingsList",
	})
	if not settingsList then
		return false
	end
	local compared = 0
	for settingId, expectedIndex in pairs(settingsPayload) do
		local settingFrame = settingsList:FindFirstChild(tostring(settingId))
		if settingFrame and settingFrame:IsA("Frame") then
			compared = compared + 1
			if settingFrame:GetAttribute("Index") ~= expectedIndex then
				return false
			end
		end
	end
	return compared > 0
end

function LobbySettings.ReadChallengeStates(player)
	local playerGui = player and player:FindFirstChild("PlayerGui")
	local challengeList = findPath(playerGui, {
		"ComputerScreen",
		"JobSite",
		"Challenges",
		"Content",
		"ChallengeList",
	})
	local states = {}
	for index = 1, 3 do
		local challenge = challengeList
			and challengeList:FindFirstChild("Challenge" .. tostring(index))
		local stateLabel = findPath(challenge, {"Toggle", "TextLabel"})
		local text = stateLabel and string.upper(tostring(stateLabel.Text or ""))
		if text == "ON" then
			states[index] = true
		elseif text == "OFF" then
			states[index] = false
		end
	end
	return states
end

local function new(className, properties)
	local object = Instance.new(className)
	for property, value in pairs(properties or {}) do
		object[property] = value
	end
	return object
end

local function getGuiParent(services, environment)
	local getHiddenUi = environment.gethui or environment.get_hidden_gui
	if type(getHiddenUi) == "function" then
		local ok, hiddenUi = pcall(getHiddenUi)
		if ok and hiddenUi then
			return hiddenUi
		end
	end
	return services.CoreGui
end

function LobbySettings.Create(options)
	options = type(options) == "table" and options or {}
	local services = assert(options.Services, "LobbySettings requires Services")
	local player = assert(options.Player, "LobbySettings requires Player")
	local environment = options.Environment or ((getgenv and getgenv()) or _G)
	local settings = assert(options.Settings, "LobbySettings requires Settings")
	local COLORS = {
		Background = Color3.fromRGB(20, 24, 32),
		Panel = Color3.fromRGB(28, 34, 45),
		Control = Color3.fromRGB(37, 45, 59),
		ControlHover = Color3.fromRGB(48, 58, 75),
		Border = Color3.fromRGB(67, 79, 101),
		Text = Color3.fromRGB(231, 235, 243),
		Muted = Color3.fromRGB(164, 174, 194),
		Accent = Color3.fromRGB(69, 94, 196),
		Positive = Color3.fromRGB(50, 205, 126),
		Negative = Color3.fromRGB(238, 80, 99),
	}
	local connections = {}
	local dropdowns = {}
	local destroyed = false
	local busy = false
	local autoMutableWhileBusy = false

	local jobByName = {}
	for _, site in ipairs(LobbySettings.JobSites) do
		jobByName[site.Name] = site
	end
	if not jobByName[settings.JobSite] then
		settings.JobSite = "School"
	end
	if not table.find(LobbySettings.Difficulties, settings.Difficulty) then
		settings.Difficulty = "Nightmare"
	end
	settings.Auto = settings.Auto == true
	if type(settings.EquipmentPreset) ~= "string" or settings.EquipmentPreset == "" then
		settings.EquipmentPreset = "green"
	end
	local rememberedChallenges = type(settings.Challenges) == "table"
		and settings.Challenges
		or {}
	local liveChallenges = settings.ChallengesConfigured ~= true
		and LobbySettings.ReadChallengeStates(player)
		or {}
	local function initialChallengeState(index)
		if type(liveChallenges[index]) == "boolean" then
			return liveChallenges[index]
		end
		return rememberedChallenges[index] == true
	end
	settings.Challenges = {
		[1] = initialChallengeState(1),
		[2] = initialChallengeState(2),
		[3] = initialChallengeState(3),
	}
	settings.ChallengesConfigured = settings.ChallengesConfigured == true
		or type(liveChallenges[1]) == "boolean"
			and type(liveChallenges[2]) == "boolean"
			and type(liveChallenges[3]) == "boolean"

	local gui = new("ScreenGui", {
		Name = "DemonologyLobbySettings",
		DisplayOrder = 999,
		IgnoreGuiInset = false,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	local parent = getGuiParent(services, environment)
	local existing = parent:FindFirstChild(gui.Name)
	if existing then
		existing:Destroy()
	end
	gui.Parent = parent

	local root = new("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(480, 680),
		BackgroundColor3 = COLORS.Background,
		BorderColor3 = COLORS.Border,
		BorderSizePixel = 1,
		ClipsDescendants = false,
		Parent = gui,
	})

	new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -32, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamSemibold,
		Text = "Demonology Lobby Settings",
		TextColor3 = COLORS.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	})
	new("Frame", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = COLORS.Border,
		BorderSizePixel = 0,
		Parent = root,
	})

	local function label(text, y)
		return new("TextLabel", {
			Position = UDim2.fromOffset(18, y),
			Size = UDim2.new(1, -36, 0, 20),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = text,
			TextColor3 = COLORS.Muted,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = root,
		})
	end

	local function connect(signal, callback)
		local connection = signal:Connect(callback)
		table.insert(connections, connection)
		return connection
	end

	local function closeDropdowns(except)
		for _, dropdown in ipairs(dropdowns) do
			if dropdown ~= except then
				dropdown:SetOpen(false)
			end
		end
	end

	local function createDropdown(config)
		if config.Label ~= "" then
			label(config.Label, config.Y)
		end
		local button = new("TextButton", {
			Name = config.Name .. "Button",
			Position = UDim2.fromOffset(18, config.Y + 22),
			Size = UDim2.new(1, -36, 0, 34),
			BackgroundColor3 = COLORS.Control,
			BorderColor3 = COLORS.Border,
			BorderSizePixel = 1,
			AutoButtonColor = false,
			Font = Enum.Font.Gotham,
			Text = "",
			TextColor3 = COLORS.Text,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
			Parent = root,
		})
		new("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
			Parent = button,
		})
		new("TextLabel", {
			Name = "Arrow",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 0),
			Size = UDim2.fromOffset(20, 34),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "v",
			TextColor3 = COLORS.Muted,
			TextSize = 12,
			ZIndex = 4,
			Parent = button,
		})
		local list = new("ScrollingFrame", {
			Name = config.Name .. "List",
			Position = UDim2.fromOffset(18, config.Y + 57),
			Size = UDim2.new(1, -36, 0, config.Height or 180),
			BackgroundColor3 = COLORS.Panel,
			BorderColor3 = COLORS.Border,
			BorderSizePixel = 1,
			CanvasSize = UDim2.fromOffset(0, 0),
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = COLORS.Accent,
			Visible = false,
			ZIndex = 50,
			Parent = root,
		})
		local layout = new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = list,
		})
		local dropdown = {Button = button, List = list, Open = false}

		function dropdown:SetOpen(open)
			self.Open = open == true
			self.List.Visible = self.Open
			self.Button.Arrow.Text = self.Open and "^" or "v"
		end

		function dropdown:Refresh()
			for _, child in ipairs(list:GetChildren()) do
				if child ~= layout then
					child:Destroy()
				end
			end
			local items = config.GetItems()
			for index, item in ipairs(items) do
				local option = new("TextButton", {
					Name = tostring(item.Value),
					Size = UDim2.new(1, 0, 0, 32),
					BackgroundColor3 = index % 2 == 0 and COLORS.Control or COLORS.Panel,
					BorderSizePixel = 0,
					AutoButtonColor = false,
					Font = Enum.Font.Gotham,
					Text = tostring(item.Text or item.Value),
					TextColor3 = COLORS.Text,
					TextSize = 12,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 51,
					Parent = list,
				})
				new("UIPadding", {PaddingLeft = UDim.new(0, 10), Parent = option})
				connect(option.MouseEnter, function()
					option.BackgroundColor3 = COLORS.ControlHover
				end)
				connect(option.MouseLeave, function()
					option.BackgroundColor3 = index % 2 == 0 and COLORS.Control or COLORS.Panel
				end)
				connect(option.Activated, function()
					config.OnSelected(item.Value)
					dropdown:SetOpen(false)
				end)
			end
			list.CanvasSize = UDim2.fromOffset(0, #items * 32)
			button.Text = tostring(config.GetText())
			return #items
		end

		connect(button.MouseEnter, function()
			button.BackgroundColor3 = COLORS.ControlHover
		end)
		connect(button.MouseLeave, function()
			button.BackgroundColor3 = COLORS.Control
		end)
		connect(button.Activated, function()
			local open = not dropdown.Open
			closeDropdowns(dropdown)
			if open then
				dropdown:Refresh()
			end
			dropdown:SetOpen(open)
		end)
		table.insert(dropdowns, dropdown)
		dropdown:Refresh()
		return dropdown
	end

	local description = new("TextLabel", {
		Name = "Description",
		Position = UDim2.fromOffset(18, 116),
		Size = UDim2.new(1, -36, 0, 116),
		BackgroundColor3 = COLORS.Panel,
		BorderColor3 = COLORS.Border,
		BorderSizePixel = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = COLORS.Muted,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = root,
	})
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		Parent = description,
	})

	local function persist()
		if type(options.OnChanged) == "function" then
			options.OnChanged(settings)
		end
	end

	local function updateDescription()
		local site = jobByName[settings.JobSite]
		local requirement = site.LevelRequirement
			and (" | Level " .. tostring(site.LevelRequirement))
			or ""
		description.Text = site.Size .. requirement .. "\n\n" .. site.Description
	end

	local jobDropdown
	jobDropdown = createDropdown({
		Name = "JobSite",
		Label = "Job Site",
		Y = 54,
		Height = 230,
		GetItems = function()
			local items = {}
			for _, site in ipairs(LobbySettings.JobSites) do
				local requirement = site.LevelRequirement
					and (" | Lv " .. tostring(site.LevelRequirement))
					or ""
				table.insert(items, {
					Value = site.Name,
					Text = site.Name .. " | " .. site.Size .. requirement,
				})
			end
			return items
		end,
		GetText = function()
			return settings.JobSite
		end,
		OnSelected = function(value)
			settings.JobSite = value
			jobDropdown.Button.Text = value
			updateDescription()
			persist()
		end,
	})
	updateDescription()

	local presetLabel = label("Custom Preset", 316)
	local presetDropdown
	local difficultyDropdown
	local function updateCustomVisibility()
		local visible = settings.Difficulty == "Custom"
		presetLabel.Visible = visible
		if presetDropdown then
			presetDropdown.Button.Visible = visible
			if not visible then
				presetDropdown:SetOpen(false)
			end
		end
	end

	difficultyDropdown = createDropdown({
		Name = "Difficulty",
		Label = "Difficulty",
		Y = 246,
		Height = 160,
		GetItems = function()
			local items = {}
			for _, name in ipairs(LobbySettings.Difficulties) do
				table.insert(items, {Value = name, Text = name})
			end
			return items
		end,
		GetText = function()
			return settings.Difficulty
		end,
		OnSelected = function(value)
			settings.Difficulty = value
			difficultyDropdown.Button.Text = value
			updateCustomVisibility()
			persist()
		end,
	})

	presetDropdown = createDropdown({
		Name = "CustomPreset",
		Label = "",
		Y = 316,
		Height = 128,
		GetItems = function()
			local items = {}
			for _, name in ipairs(LobbySettings.ReadCustomPresets(player)) do
				table.insert(items, {Value = name, Text = name})
			end
			return items
		end,
		GetText = function()
			return settings.CustomPreset or "Select a saved preset"
		end,
		OnSelected = function(value)
			settings.CustomPreset = value
			presetDropdown.Button.Text = value
			persist()
		end,
	})
	updateCustomVisibility()
	task.spawn(function()
		local previousSignature
		local deadline = os.clock() + 10
		while not destroyed and os.clock() < deadline do
			local names = LobbySettings.ReadCustomPresets(player)
			local signature = table.concat(names, "\0")
			if signature ~= previousSignature then
				previousSignature = signature
				presetDropdown:Refresh()
			end
			if #names > 0 then
				break
			end
			task.wait(0.25)
		end
	end)

	local equipmentDropdown
	equipmentDropdown = createDropdown({
		Name = "EquipmentPreset",
		Label = "Equipment Preset",
		Y = 392,
		Height = 128,
		GetItems = function()
			local items = {}
			for _, name in ipairs(LobbySettings.ReadEquipmentPresets(player)) do
				table.insert(items, {Value = name, Text = name})
			end
			return items
		end,
		GetText = function()
			return settings.EquipmentPreset or "Select a saved preset"
		end,
		OnSelected = function(value)
			settings.EquipmentPreset = value
			equipmentDropdown.Button.Text = value
			persist()
		end,
	})

	label("Daily Challenges", 466)
	local challengeButtons = {}
	local function renderChallenge(index)
		local enabled = settings.Challenges[index] == true
		local button = challengeButtons[index]
		button.Text = ("Challenge %d: %s"):format(index, enabled and "ON" or "OFF")
		button.BackgroundColor3 = enabled and COLORS.Positive or COLORS.Control
	end
	for index = 1, 3 do
		local button = new("TextButton", {
			Name = "Challenge" .. tostring(index),
			Position = UDim2.fromOffset(18 + (index - 1) * 152, 488),
			Size = UDim2.fromOffset(140, 34),
			BackgroundColor3 = COLORS.Control,
			BorderColor3 = COLORS.Border,
			BorderSizePixel = 1,
			AutoButtonColor = false,
			Font = Enum.Font.GothamMedium,
			Text = "",
			TextColor3 = COLORS.Text,
			TextSize = 11,
			Parent = root,
		})
		challengeButtons[index] = button
		renderChallenge(index)
		connect(button.Activated, function()
			if busy then
				return
			end
			settings.Challenges[index] = not settings.Challenges[index]
			settings.ChallengesConfigured = true
			renderChallenge(index)
			persist()
		end)
	end

	local autoButton = new("TextButton", {
		Name = "AutoToggle",
		Position = UDim2.fromOffset(18, 536),
		Size = UDim2.new(1, -36, 0, 38),
		BackgroundColor3 = COLORS.Control,
		BorderColor3 = COLORS.Border,
		BorderSizePixel = 1,
		AutoButtonColor = false,
		Font = Enum.Font.GothamSemibold,
		TextColor3 = COLORS.Text,
		TextSize = 13,
		Parent = root,
	})
	local function renderAuto()
		autoButton.Text = settings.Auto and "Automation: ON" or "Automation: OFF"
		autoButton.BackgroundColor3 = settings.Auto and COLORS.Positive or COLORS.Control
	end
	renderAuto()
	connect(autoButton.Activated, function()
		if busy and not autoMutableWhileBusy then
			return
		end
		settings.Auto = not settings.Auto
		renderAuto()
		persist()
	end)

	local status = new("TextLabel", {
		Name = "Status",
		Position = UDim2.fromOffset(18, 586),
		Size = UDim2.new(1, -36, 0, 38),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = settings.Auto and "Auto is enabled; saved settings will continue after lobby returns." or "Choose settings, then start the round.",
		TextColor3 = COLORS.Muted,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = root,
	})

	local startButton = new("TextButton", {
		Name = "StartRound",
		Position = UDim2.fromOffset(18, 634),
		Size = UDim2.new(1, -36, 0, 34),
		BackgroundColor3 = COLORS.Accent,
		BorderColor3 = COLORS.Border,
		BorderSizePixel = 1,
		AutoButtonColor = false,
		Font = Enum.Font.GothamSemibold,
		Text = "Start Round",
		TextColor3 = COLORS.Text,
		TextSize = 13,
		Parent = root,
	})

	local view = {Gui = gui, Settings = settings}
	function view:SetStatus(text, isError)
		if destroyed then
			return
		end
		status.Text = tostring(text or "")
		status.TextColor3 = isError and COLORS.Negative or COLORS.Muted
	end
	function view:SetBusy(value, allowAutoChange)
		busy = value == true
		autoMutableWhileBusy = busy and allowAutoChange == true
		startButton.Text = busy and "Starting..." or "Start Round"
		startButton.BackgroundColor3 = busy and COLORS.Control or COLORS.Accent
	end
	function view:RefreshCustomPresets()
		if presetDropdown then
			presetDropdown:Refresh()
		end
	end
	function view:RefreshEquipmentPresets()
		if equipmentDropdown then
			equipmentDropdown:Refresh()
		end
	end
	function view:Destroy()
		if destroyed then
			return
		end
		destroyed = true
		for _, connection in ipairs(connections) do
			if connection.Connected then
				connection:Disconnect()
			end
		end
		gui:Destroy()
	end

	connect(startButton.Activated, function()
		if busy then
			return
		end
		local equipmentPresets = LobbySettings.ReadEquipmentPresets(player)
		if not settings.EquipmentPreset
			or not table.find(equipmentPresets, settings.EquipmentPreset) then
			view:SetStatus("Select a saved equipment preset before starting.", true)
			equipmentDropdown:Refresh()
			return
		end
		closeDropdowns()
		view:SetBusy(true)
		persist()
		if type(options.OnStart) == "function" then
			options.OnStart(settings)
		end
	end)

	persist()
	return view
end

return LobbySettings
