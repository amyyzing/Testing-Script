local Aesthetic = {}

local COLORS = {
	Background = Color3.fromRGB(18, 20, 26),
	Title = Color3.fromRGB(24, 27, 35),
	Control = Color3.fromRGB(35, 39, 49),
	Accent = Color3.fromRGB(72, 96, 196),
	Danger = Color3.fromRGB(210, 66, 82),
	Positive = Color3.fromRGB(74, 210, 149),
	Text = Color3.fromRGB(235, 237, 243),
	Muted = Color3.fromRGB(157, 163, 178),
}

local function parentFor(services, player)
	if type(gethui) == "function" then return gethui() end
	return services.CoreGui or player:WaitForChild("PlayerGui")
end

local function create(className, properties, parent)
	local object = Instance.new(className)
	for property, value in pairs(properties) do object[property] = value end
	object.Parent = parent
	return object
end

function Aesthetic.Create(dependencies)
	local services = assert(dependencies.Services, "aesthetic requires Services")
	local player = assert(dependencies.Player, "aesthetic requires Player")
	local environment = dependencies.Environment or _G

	local gui = create("ScreenGui", {
		Name = "DemonologyAssistant",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, parentFor(services, player))

	local main = create("Frame", {
		Name = "Main",
		BackgroundColor3 = COLORS.Background,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, -210, 0.5, -180),
		Size = UDim2.fromOffset(420, 360),
	}, gui)

	local titleBar = create("Frame", {
		Name = "TitleBar",
		Active = true,
		BackgroundColor3 = COLORS.Title,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 34),
	}, main)

	create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -92, 1, 0),
		Text = "Demonology Assistant",
		TextColor3 = COLORS.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, titleBar)

	local closeButton = create("TextButton", {
		Name = "Close",
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.Danger,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -34, 0, 0),
		Size = UDim2.fromOffset(34, 34),
		Text = "X",
		TextColor3 = COLORS.Text,
		TextSize = 18,
	}, titleBar)

	local minimizeButton = create("TextButton", {
		Name = "Minimize",
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.Control,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -68, 0, 0),
		Size = UDim2.fromOffset(34, 34),
		Text = "-",
		TextColor3 = COLORS.Text,
		TextSize = 18,
	}, titleBar)

	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
	}, main)

	local huntEscapeButton = create("TextButton", {
		Name = "HuntEscape",
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.Control,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.new(1, -32, 0, 34),
		Text = "HUNT ESCAPE: OFF",
		TextColor3 = COLORS.Text,
		TextSize = 12,
	}, content)

	local brightButton = create("TextButton", {
		Name = "FullBright",
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.Control,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(16, 58),
		Size = UDim2.new(1, -32, 0, 34),
		Text = "FULL BRIGHT: OFF",
		TextColor3 = COLORS.Text,
		TextSize = 12,
	}, content)

	local ghostEspButton = create("TextButton", {
		Name = "GhostESP",
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.Control,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(16, 100),
		Size = UDim2.new(1, -32, 0, 34),
		Text = "GHOST ESP: OFF",
		TextColor3 = COLORS.Text,
		TextSize = 12,
	}, content)

	local drawerClip = create("Frame", {
		Name = "PatternDrawerClip",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(0, 360),
	}, gui)

	local drawer = create("Frame", {
		Name = "PatternDrawer",
		BackgroundColor3 = COLORS.Background,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(300, 360),
	}, drawerClip)

	local drawerTitle = create("TextLabel", {
		Name = "Title",
		BackgroundColor3 = COLORS.Title,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Size = UDim2.new(1, 0, 0, 34),
		Text = "  UNIQUE GHOST PATTERNS",
		TextColor3 = COLORS.Text,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, drawer)

	local logList = create("ScrollingFrame", {
		Name = "Logs",
		Active = true,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		Position = UDim2.fromOffset(8, 42),
		ScrollBarImageColor3 = COLORS.Accent,
		ScrollBarThickness = 3,
		Size = UDim2.new(1, -16, 1, -50),
	}, drawer)

	create("UIPadding", {
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 4),
		PaddingTop = UDim.new(0, 4),
	}, logList)
	local logLayout = create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, logList)
	local emptyLog = create("TextLabel", {
		Name = "Empty",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.Control,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, 34),
		Text = "No unique patterns observed.",
		TextColor3 = COLORS.Muted,
		TextSize = 12,
		TextWrapped = true,
	}, logList)
	local logTemplate = create("TextLabel", {
		Name = "Template",
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = COLORS.Control,
		BorderSizePixel = 0,
		Font = Enum.Font.Gotham,
		Size = UDim2.new(1, 0, 0, 44),
		Text = "",
		TextColor3 = COLORS.Text,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
	}, logList)
	create("UIPadding", {
		PaddingBottom = UDim.new(0, 7),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 7),
	}, logTemplate)

	local drawerHandle = create("TextButton", {
		Name = "PatternDrawerHandle",
		Active = true,
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.Accent,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(24, 84),
		Text = "L\nO\nG\nS\n›",
		TextColor3 = COLORS.Text,
		TextSize = 10,
		ZIndex = 5,
	}, gui)

	local resizeHandle = create("TextButton", {
		Name = "ResizeHandle",
		Active = true,
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.Accent,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -14, 1, -14),
		Size = UDim2.fromOffset(14, 14),
		Text = "",
		ZIndex = 3,
	}, main)

	local openButton = create("TextButton", {
		Name = "Open",
		AutoButtonColor = false,
		BackgroundColor3 = COLORS.Accent,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.fromOffset(92, 32),
		Text = "OPEN GUI",
		TextColor3 = COLORS.Text,
		TextSize = 12,
		Visible = false,
	}, gui)

	environment.UntitledGuiInstance = gui
	return {
		Gui = gui,
		Main = main,
		TitleBar = titleBar,
		Content = content,
		CloseButton = closeButton,
		MinimizeButton = minimizeButton,
		OpenButton = openButton,
		ResizeHandle = resizeHandle,
		PatternDrawer = {
			Clip = drawerClip,
			Panel = drawer,
			Handle = drawerHandle,
			List = logList,
			Layout = logLayout,
			Empty = emptyLog,
			Template = logTemplate,
			Width = 300,
		},
		Buttons = {
			HuntEscape = huntEscapeButton,
			Bright = brightButton,
			GhostESP = ghostEspButton,
		},
		Colors = COLORS,
	}
end

return Aesthetic
