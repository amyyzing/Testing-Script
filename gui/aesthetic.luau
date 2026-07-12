local Aesthetic = {}

Aesthetic.Copy = {
	Title = "Demonology Assistant",
	Subtitle = "Evidence and behavior tracker",
	Evidence = {
		Print = "Prints",
		SpiritBox = "Spirit Box",
		Orb = "Ghost Orb",
		Inscription = "Inscription",
		Laser = "Laser Projector",
		Wither = "Wither",
		EMF = "EMF Level",
		Temperature = "Temperature",
		FavouriteRoom = "Favourite Room",
		Ghost = "Ghost",
	},
	Controls = {
		HuntEscape = "Hunt Escape",
		GhostEsp = "Ghost ESP",
		ItemEsp = "Item ESP",
		FullBright = "Full Bright",
		TeleportBaseCamp = "Teleport to Base Camp",
		TeleportFavouriteRoom = "Teleport to Favourite Room",
		PlaceRoomItems = "Place Room Items",
		AutoSpiritBox = "Auto Spirit Box",
		RandomLights = "Random Lights Toggle",
		ToggleFuseBox = "Toggle Fuse Box",
		EvidenceMode = "Evidence Mode",
		Speed = "Speed",
	},
	EvidenceModes = {
		Normal = "Normal",
		Mimicry = "Mimicry",
	},
	States = {
		Unknown = "Unknown",
		Certain = "Certain",
		PrettySure = "Pretty Sure",
		Maybe = "Maybe",
		Idk = "Idk",
		Impossible = "Impossible",
		Fake = "Fake",
	},
	Actions = {
		PlacingRoomItems = "Placing...",
		WaitingForHunt = "Waiting for Hunt...",
		Fired = "Fired!",
	},
	Descriptions = {
		EvidenceMode = "Normal treats observed evidence as real; Mimicry treats selected evidence as fake.",
		Confidence = "Pretty Sure is a strong controlled tell, Maybe is suggestive, and Idk is a weak clue.",
		VisibilityHotkey = "Right Control toggles the overlay.",
	},
}

function Aesthetic.Create(dependencies)
	dependencies = dependencies or {}
	local Services = assert(dependencies.Services, "Aesthetic.Create requires Services")
	local player = dependencies.Player or Services.Players.LocalPlayer
	local environment = dependencies.Environment or ((getgenv and getgenv()) or _G)
	local generation = dependencies.Generation
	local function assertCurrent()
		if generation ~= nil and environment.DemonologyGeneration ~= generation then
			error("__DEMONOLOGY_SUPERSEDED__", 0)
		end
	end
	assertCurrent()
local function isLegacyGui(gui)
	if not gui:IsA("ScreenGui") then
		return false
	end
	if gui.Name == "UntitledGui" or gui.Name == "DemonologyPRO" then
		return true
	end
	local hasMainFrame = gui:FindFirstChild("MainFrame", true) ~= nil
	if not hasMainFrame then
		return false
	end
	for _, descendant in ipairs(gui:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			local text = string.lower(descendant.Text or "")
			if string.find(text, "demonology evicence", 1, true)
				or string.find(text, "script by ducko355", 1, true)
				or text == "untitled gui" then
				return true
			end
		end
	end
	return false
end
local function cleanGuiContainer(container)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		if isLegacyGui(child) then
			child:Destroy()
		end
	end
end
cleanGuiContainer(Services.CoreGui)
cleanGuiContainer(player:FindFirstChildOfClass("PlayerGui"))
if gethui then
	local ok, hiddenGui = pcall(gethui)
	if ok then
		cleanGuiContainer(hiddenGui)
	end
end
if environment.UntitledGuiCleanup then
	pcall(environment.UntitledGuiCleanup)
end
local COLORS = {
	window = Color3.fromRGB(16, 18, 23),
	header = Color3.fromRGB(22, 25, 32),
	card = Color3.fromRGB(26, 30, 38),
	cardHover = Color3.fromRGB(35, 40, 50),
	stroke = Color3.fromRGB(55, 62, 75),
	text = Color3.fromRGB(232, 235, 241),
	muted = Color3.fromRGB(151, 158, 174),
	accent = Color3.fromRGB(93, 126, 255),
	accentDark = Color3.fromRGB(62, 86, 184),
	green = Color3.fromRGB(65, 207, 126),
	red = Color3.fromRGB(239, 89, 101),
	track = Color3.fromRGB(49, 55, 68),
	gold = Color3.fromRGB(239, 190, 74),
	orangeGold = Color3.fromRGB(218, 137, 55),
}
local function new(className, properties)
	local object = Instance.new(className)
	for property, value in pairs(properties or {}) do
		object[property] = value
	end
	return object
end
local function addCorner(parent, radius)
	return new("UICorner", {
		Parent = parent,
		CornerRadius = UDim.new(0, radius or 8),
	})
end
local function addStroke(parent, color, transparency, thickness)
	return new("UIStroke", {
		Parent = parent,
		Color = color or COLORS.stroke,
		Transparency = transparency or 0,
		Thickness = thickness or 1,
	})
end
local gui = new("ScreenGui", {
	Name = "UntitledGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = false,
})
if Services.RunService:IsStudio() then
	gui.Parent = player:WaitForChild("PlayerGui")
else
	local parented = false
	if gethui then
		local ok, hiddenGui = pcall(gethui)
		if ok and hiddenGui then
			gui.Parent = hiddenGui
			parented = true
		end
	end
	if not parented then
		gui.Parent = Services.CoreGui
	end
end
assertCurrent()
environment.UntitledGuiInstance = gui
environment.DemonologyGuiGeneration = generation
local mainFrame = new("Frame", {
	Name = "MainFrame",
	Parent = gui,
	Active = true,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(380, 520),
	BackgroundColor3 = COLORS.window,
	BorderSizePixel = 0,
	ClipsDescendants = true,
})
addCorner(mainFrame, 11)
addStroke(mainFrame, COLORS.stroke, 0.15, 1)
local sizeConstraint = new("UISizeConstraint", {
	Parent = mainFrame,
	MinSize = Vector2.new(330, 430),
	MaxSize = Vector2.new(620, 780),
})
local titleBar = new("Frame", {
	Name = "TitleBar",
	Parent = mainFrame,
	Active = true,
	Size = UDim2.new(1, 0, 0, 42),
	BackgroundColor3 = COLORS.header,
	BorderSizePixel = 0,
})
new("TextLabel", {
	Name = "Title",
	Parent = titleBar,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(14, 0),
	Size = UDim2.new(1, -102, 1, 0),
	Font = Enum.Font.GothamSemibold,
	Text = Aesthetic.Copy.Title,
	TextColor3 = COLORS.text,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
})
local minimizeButton = new("TextButton", {
	Name = "Minimize",
	Parent = titleBar,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -45, 0.5, 0),
	Size = UDim2.fromOffset(32, 28),
	AutoButtonColor = false,
	BackgroundColor3 = COLORS.card,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "–",
	TextColor3 = COLORS.muted,
	TextSize = 18,
})
addCorner(minimizeButton, 7)
local closeButton = new("TextButton", {
	Name = "Close",
	Parent = titleBar,
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.5, 0),
	Size = UDim2.fromOffset(28, 28),
	AutoButtonColor = false,
	BackgroundColor3 = COLORS.red,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "×",
	TextColor3 = Color3.new(1, 1, 1),
	TextSize = 17,
})
addCorner(closeButton, 7)
local content = new("ScrollingFrame", {
	Name = "Content",
	Parent = mainFrame,
	Position = UDim2.fromOffset(0, 42),
	Size = UDim2.new(1, 0, 1, -42),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.fromOffset(0, 0),
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = COLORS.accent,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollingDirection = Enum.ScrollingDirection.Y,
})
new("UIPadding", {
	Parent = content,
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 18),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
})
new("UIListLayout", {
	Parent = content,
	Padding = UDim.new(0, 10),
	SortOrder = Enum.SortOrder.LayoutOrder,
})
local evidenceCard = new("Frame", {
	Name = "EvidenceCard",
	Parent = content,
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 317),
	BackgroundColor3 = COLORS.card,
	BorderSizePixel = 0,
})
addCorner(evidenceCard, 9)
addStroke(evidenceCard, COLORS.stroke, 0.3, 1)
new("UIPadding", {
	Parent = evidenceCard,
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
})
new("UIListLayout", {
	Parent = evidenceCard,
	Padding = UDim.new(0, 3),
	SortOrder = Enum.SortOrder.LayoutOrder,
})
local function createEvidenceLabel(name, text, order, color)
	return new("TextLabel", {
		Name = name,
		Parent = evidenceCard,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 27),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = color or COLORS.red,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
end
local evidenceLabels = {
	Print = createEvidenceLabel("Print", Aesthetic.Copy.Evidence.Print .. ": Unknown", 1, COLORS.muted),
	SpiritBox = createEvidenceLabel("SpiritBox", Aesthetic.Copy.Evidence.SpiritBox .. ": Unknown", 2, COLORS.muted),
	Orb = createEvidenceLabel("Orb", Aesthetic.Copy.Evidence.Orb .. ": Unknown", 3, COLORS.muted),
	Inscription = createEvidenceLabel("Inscription", Aesthetic.Copy.Evidence.Inscription .. ": Unknown", 4, COLORS.muted),
	Laser = createEvidenceLabel("Laser", Aesthetic.Copy.Evidence.Laser .. ": Unknown", 5, COLORS.muted),
	Wither = createEvidenceLabel("Wither", Aesthetic.Copy.Evidence.Wither .. ": Unknown", 6, COLORS.muted),
	EMF = createEvidenceLabel("EMF", "EMF-1", 7, COLORS.muted),
	Temperature = createEvidenceLabel("Temperature", "--.-°C", 8, COLORS.text),
	FavouriteRoom = createEvidenceLabel("FavouriteRoom", "Favourite Room: ...", 9, COLORS.accent),
	Ghost = createEvidenceLabel("Ghost", "Ghost: Unknown", 10, COLORS.muted),
}
local controlsCard = new("Frame", {
	Name = "ControlsCard",
	Parent = content,
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 292),
	BackgroundColor3 = COLORS.card,
	BorderSizePixel = 0,
})
addCorner(controlsCard, 9)
addStroke(controlsCard, COLORS.stroke, 0.3, 1)
new("UIPadding", {
	Parent = controlsCard,
	PaddingTop = UDim.new(0, 12),
	PaddingBottom = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
})
new("UIGridLayout", {
	Parent = controlsCard,
	CellPadding = UDim2.fromOffset(8, 8),
	CellSize = UDim2.new(0.5, -4, 0, 38),
	FillDirectionMaxCells = 2,
	SortOrder = Enum.SortOrder.LayoutOrder,
})
local function createToggleButton(name, text, order)
	local button = new("TextButton", {
		Name = name,
		Parent = controlsCard,
		LayoutOrder = order,
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.cardHover,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = COLORS.text,
		TextSize = 13,
	})
	addCorner(button, 7)
	addStroke(button, COLORS.stroke, 0.4, 1)
	return button
end
local huntEscapeButton = createToggleButton("HuntEscape", Aesthetic.Copy.Controls.HuntEscape, 1)
local ghostEspButton = createToggleButton("GhostEsp", Aesthetic.Copy.Controls.GhostEsp, 2)
local itemEspButton = createToggleButton("ItemEsp", Aesthetic.Copy.Controls.ItemEsp, 3)
local fullBrightButton = createToggleButton("FullBright", Aesthetic.Copy.Controls.FullBright, 4)
local baseCampTeleportButton = createToggleButton("TeleportBaseCamp", Aesthetic.Copy.Controls.TeleportBaseCamp, 5)
local favouriteRoomTeleportButton = createToggleButton("TeleportFavouriteRoom", Aesthetic.Copy.Controls.TeleportFavouriteRoom, 6)
local placeRoomItemsButton = createToggleButton("PlaceRoomItems", Aesthetic.Copy.Controls.PlaceRoomItems, 7)
local autoSpiritBoxButton = createToggleButton("AutoSpiritBox", Aesthetic.Copy.Controls.AutoSpiritBox, 8)
local randomLightsButton = createToggleButton("RandomLights", Aesthetic.Copy.Controls.RandomLights, 9)
local toggleFuseBoxButton = createToggleButton("ToggleFuseBox", Aesthetic.Copy.Controls.ToggleFuseBox, 10)
evidenceLabels.EvidenceMode = createToggleButton(
	"EvidenceMode",
	Aesthetic.Copy.Controls.EvidenceMode .. ": " .. Aesthetic.Copy.EvidenceModes.Normal .. " ▼",
	11
)
evidenceLabels.EvidenceMode.ClipsDescendants = false
evidenceLabels.EvidenceModeMenu = new("Frame", {
	Name = "Options",
	Parent = evidenceLabels.EvidenceMode,
	Position = UDim2.new(0, 0, 1, 4),
	Size = UDim2.new(1, 0, 0, 70),
	BackgroundColor3 = COLORS.card,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 30,
})
addCorner(evidenceLabels.EvidenceModeMenu, 7)
addStroke(evidenceLabels.EvidenceModeMenu, COLORS.stroke, 0.2, 1)
new("UIListLayout", {
	Parent = evidenceLabels.EvidenceModeMenu,
	SortOrder = Enum.SortOrder.LayoutOrder,
})
new("TextButton", {
	Name = "Normal",
	Parent = evidenceLabels.EvidenceModeMenu,
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 35),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = Aesthetic.Copy.EvidenceModes.Normal,
	TextColor3 = COLORS.text,
	TextSize = 13,
	ZIndex = 31,
})
new("TextButton", {
	Name = "Mimicry",
	Parent = evidenceLabels.EvidenceModeMenu,
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 35),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = Aesthetic.Copy.EvidenceModes.Mimicry,
	TextColor3 = COLORS.orangeGold,
	TextSize = 13,
	ZIndex = 31,
})
local speedCard = new("Frame", {
	Name = "SpeedSlider",
	Parent = content,
	LayoutOrder = 3,
	Size = UDim2.new(1, 0, 0, 88),
	BackgroundColor3 = COLORS.card,
	BorderSizePixel = 0,
})
addCorner(speedCard, 9)
addStroke(speedCard, COLORS.stroke, 0.3, 1)
new("TextLabel", {
	Parent = speedCard,
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 7),
	Size = UDim2.new(1, -72, 0, 24),
	Font = Enum.Font.GothamMedium,
	Text = Aesthetic.Copy.Controls.Speed,
	TextColor3 = COLORS.text,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
})
local speedValue = new("TextLabel", {
	Parent = speedCard,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 7),
	Size = UDim2.fromOffset(50, 24),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamSemibold,
	Text = "10",
	TextColor3 = COLORS.accent,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Right,
})
local sliderTrack = new("Frame", {
	Name = "Track",
	Parent = speedCard,
	Active = true,
	Position = UDim2.fromOffset(14, 49),
	Size = UDim2.new(1, -28, 0, 7),
	BackgroundColor3 = COLORS.track,
	BorderSizePixel = 0,
})
addCorner(sliderTrack, 4)
local sliderFill = new("Frame", {
	Name = "Fill",
	Parent = sliderTrack,
	Size = UDim2.fromScale(0.1, 1),
	BackgroundColor3 = COLORS.accent,
	BorderSizePixel = 0,
})
addCorner(sliderFill, 4)
local sliderKnob = new("Frame", {
	Name = "Knob",
	Parent = sliderTrack,
	Active = true,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.1, 0.5),
	Size = UDim2.fromOffset(17, 17),
	BackgroundColor3 = COLORS.text,
	BorderSizePixel = 0,
})
addCorner(sliderKnob, 9)
addStroke(sliderKnob, COLORS.accentDark, 0, 2)
local resizeHandle = new("TextButton", {
	Name = "ResizeHandle",
	Parent = mainFrame,
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 3, 1, -3),
	Size = UDim2.fromOffset(20, 20),
	AutoButtonColor = false,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Text = "⌞",
	TextColor3 = COLORS.muted,
	TextSize = 16,
	ZIndex = 20,
})

	return {
		Gui = gui,
		MainFrame = mainFrame,
		SizeConstraint = sizeConstraint,
		TitleBar = titleBar,
		MinimizeButton = minimizeButton,
		CloseButton = closeButton,
		Content = content,
		EvidenceLabels = evidenceLabels,
		SpeedValue = speedValue,
		SliderTrack = sliderTrack,
		SliderFill = sliderFill,
		SliderKnob = sliderKnob,
		ResizeHandle = resizeHandle,
		Colors = COLORS,
		Copy = Aesthetic.Copy,
		Buttons = {
			HuntEscape = huntEscapeButton,
			GhostEsp = ghostEspButton,
			ItemEsp = itemEspButton,
			FullBright = fullBrightButton,
			TeleportBaseCamp = baseCampTeleportButton,
			TeleportFavouriteRoom = favouriteRoomTeleportButton,
			PlaceRoomItems = placeRoomItemsButton,
			AutoSpiritBox = autoSpiritBoxButton,
			RandomLights = randomLightsButton,
			ToggleFuseBox = toggleFuseBoxButton,
		},
	}
end

return Aesthetic
