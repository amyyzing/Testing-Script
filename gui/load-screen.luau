local LoadScreen = {}

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

function LoadScreen.new(dependencies)
	local services = assert(dependencies.Services, "load-screen requires Services")
	local player = assert(dependencies.Player, "load-screen requires Player")
	local loader = {Destroyed = false}
	local gui = create("ScreenGui", {
		Name = "DemonologyLoadScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 1000,
	}, parentFor(services, player))

	local frame = create("Frame", {
		Name = "Window",
		BackgroundColor3 = Color3.fromRGB(18, 20, 26),
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, -180, 0.5, -60),
		Size = UDim2.fromOffset(360, 120),
	}, gui)

	create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Position = UDim2.fromOffset(16, 12),
		Size = UDim2.new(1, -32, 0, 22),
		Text = dependencies.Title or "Demonology Assistant",
		TextColor3 = Color3.fromRGB(235, 237, 243),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)

	loader.Stage = create("TextLabel", {
		Name = "Stage",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.fromOffset(16, 40),
		Size = UDim2.new(1, -32, 0, 18),
		Text = "Starting…",
		TextColor3 = Color3.fromRGB(157, 163, 178),
		TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, frame)

	local track = create("Frame", {
		Name = "ProgressTrack",
		BackgroundColor3 = Color3.fromRGB(35, 39, 49),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(16, 72),
		Size = UDim2.new(1, -76, 0, 10),
	}, frame)

	loader.Fill = create("Frame", {
		Name = "Progress",
		BackgroundColor3 = Color3.fromRGB(72, 96, 196),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
	}, track)

	loader.Count = create("TextLabel", {
		Name = "Count",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Position = UDim2.new(1, -52, 0, 68),
		Size = UDim2.fromOffset(40, 18),
		Text = "0/0",
		TextColor3 = Color3.fromRGB(157, 163, 178),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, frame)

	loader.Gui = gui

	function loader:SetStage(text, current, total)
		if self.Destroyed then return end
		current, total = tonumber(current) or 0, math.max(tonumber(total) or 0, 0)
		local progress = total > 0 and math.clamp(current / total, 0, 1) or 0
		self.Stage.Text = tostring(text or "Loading…")
		self.Fill.Size = UDim2.fromScale(progress, 1)
		self.Count.Text = ("%d/%d"):format(current, total)
	end

	function loader:Fail(message)
		if self.Destroyed then return end
		self.Stage.Text = tostring(message or "Loading failed")
		self.Stage.TextColor3 = Color3.fromRGB(232, 77, 94)
		self.Fill.BackgroundColor3 = Color3.fromRGB(210, 66, 82)
		self.Count.Text = "FAILED"
	end

	function loader:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		self.Gui:Destroy()
	end

	return loader
end

return LoadScreen
