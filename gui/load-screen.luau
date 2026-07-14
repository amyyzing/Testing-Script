local LoadScreen = {}
LoadScreen.__index = LoadScreen

local function new(className, properties)
	local object = Instance.new(className)
	for property, value in pairs(properties or {}) do
		object[property] = value
	end
	return object
end

local function parentGui(gui, services, player)
	if services.RunService:IsStudio() then
		gui.Parent = player:WaitForChild("PlayerGui")
		return
	end
	if gethui then
		local ok, hiddenGui = pcall(gethui)
		if ok and hiddenGui then
			gui.Parent = hiddenGui
			return
		end
	end
	gui.Parent = services.CoreGui
end

function LoadScreen.new(options)
	options = options or {}
	local services = options.Services or {
		Players = game:GetService("Players"),
		RunService = game:GetService("RunService"),
		CoreGui = game:GetService("CoreGui"),
	}
	local player = options.Player or services.Players.LocalPlayer
	local environment = options.Environment or ((getgenv and getgenv()) or _G)
	local generation = options.Generation
	local function isCurrent()
		return generation == nil or environment.DemonologyGeneration == generation
	end
	if not isCurrent() then
		error("__DEMONOLOGY_SUPERSEDED__", 0)
	end

	if environment.DemonologyLoadScreen then
		pcall(function()
			environment.DemonologyLoadScreen:Destroy()
		end)
	end

	local gui = new("ScreenGui", {
		Name = "DemonologyLoadScreen",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 1_000_000,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	parentGui(gui, services, player)
	if not isCurrent() then
		gui:Destroy()
		error("__DEMONOLOGY_SUPERSEDED__", 0)
	end

	local shade = new("Frame", {
		Parent = gui,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(8, 10, 14),
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
	})

	local card = new("Frame", {
		Parent = shade,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(390, 166),
		BackgroundColor3 = Color3.fromRGB(22, 25, 32),
		BorderSizePixel = 0,
	})
	new("UIStroke", {
		Parent = card,
		Color = Color3.fromRGB(55, 62, 75),
		Transparency = 0.15,
		Thickness = 1,
		LineJoinMode = Enum.LineJoinMode.Miter,
	})

	new("TextLabel", {
		Parent = card,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 18),
		Size = UDim2.new(1, -44, 0, 28),
		Font = Enum.Font.GothamSemibold,
		Text = options.Title or "Demonology Assistant",
		TextColor3 = Color3.fromRGB(232, 235, 241),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local status = new("TextLabel", {
		Parent = card,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 54),
		Size = UDim2.new(1, -44, 0, 24),
		Font = Enum.Font.GothamMedium,
		Text = options.Status or "Preparing module loader…",
		TextColor3 = Color3.fromRGB(151, 158, 174),
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local track = new("Frame", {
		Parent = card,
		Position = UDim2.fromOffset(22, 94),
		Size = UDim2.new(1, -44, 0, 9),
		BackgroundColor3 = Color3.fromRGB(49, 55, 68),
		BorderSizePixel = 0,
	})
	local fill = new("Frame", {
		Parent = track,
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(93, 126, 255),
		BorderSizePixel = 0,
	})
	local detail = new("TextLabel", {
		Parent = card,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 117),
		Size = UDim2.new(1, -44, 0, 28),
		Font = Enum.Font.Code,
		Text = "0%",
		TextColor3 = Color3.fromRGB(93, 126, 255),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	local self = setmetatable({
		Gui = gui,
		Card = card,
		StatusLabel = status,
		Track = track,
		DetailLabel = detail,
		Fill = fill,
		Environment = environment,
		Generation = generation,
		Destroyed = false,
	}, LoadScreen)
	environment.DemonologyLoadScreen = self
	return self
end

function LoadScreen:SetProgress(progress, message)
	if self.Destroyed then
		return
	end
	progress = math.clamp(tonumber(progress) or 0, 0, 1)
	self.Fill.Size = UDim2.fromScale(progress, 1)
	self.DetailLabel.Text = string.format("%d%%", math.floor(progress * 100 + 0.5))
	if message then
		self.StatusLabel.Text = tostring(message)
	end
end

function LoadScreen:SetStage(message, current, total)
	local denominator = math.max(tonumber(total) or 1, 1)
	self:SetProgress((tonumber(current) or 0) / denominator, message)
end

function LoadScreen:Fail(message)
	if self.Destroyed then
		return
	end
	self.Card.Size = UDim2.fromOffset(420, 230)
	self.StatusLabel.Size = UDim2.new(1, -44, 0, 92)
	self.StatusLabel.TextTruncate = Enum.TextTruncate.None
	self.StatusLabel.TextWrapped = true
	self.StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
	self.Track.Position = UDim2.fromOffset(22, 166)
	self.DetailLabel.Position = UDim2.fromOffset(22, 185)
	self.Fill.BackgroundColor3 = Color3.fromRGB(239, 89, 101)
	self.DetailLabel.Text = "FAILED"
	self.DetailLabel.TextColor3 = Color3.fromRGB(239, 89, 101)
	self.StatusLabel.Text = tostring(message or "A module failed to load")
	self.StatusLabel.TextColor3 = Color3.fromRGB(239, 89, 101)
end

function LoadScreen:Destroy()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	if self.Gui then
		self.Gui:Destroy()
	end
	if self.Environment.DemonologyLoadScreen == self then
		self.Environment.DemonologyLoadScreen = nil
	end
end

return LoadScreen
