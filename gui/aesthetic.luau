local Aesthetic = {}

local COLORS = {
	Background = Color3.fromRGB(18, 20, 26),
	Title = Color3.fromRGB(24, 27, 35),
	Control = Color3.fromRGB(35, 39, 49),
	Accent = Color3.fromRGB(72, 96, 196),
	Danger = Color3.fromRGB(210, 66, 82),
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
		Size = UDim2.new(1, -58, 1, 0),
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

	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 1, -34),
	}, main)

	local status = create("TextLabel", {
		Name = "EmptyState",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(16, 16),
		Size = UDim2.new(1, -32, 0, 22),
		Text = "Aswang tracker test",
		TextColor3 = COLORS.Muted,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, content)

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
		OpenButton = openButton,
		ResizeHandle = resizeHandle,
		Status = status,
		Colors = COLORS,
	}
end

return Aesthetic
