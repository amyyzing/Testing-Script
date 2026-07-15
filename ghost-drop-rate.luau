if not game:IsLoaded() then
	game.Loaded:Wait()
end

local CoreGui = game:GetService("CoreGui")
local guiParent = type(gethui) == "function" and gethui()
	or CoreGui

local previous = guiParent:FindFirstChild("GhostDropRate")
if previous then
	previous:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GhostDropRate"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 1000
screenGui.Parent = guiParent

local label = Instance.new("TextLabel")
label.Name = "AverageDropRate"
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.fromScale(0.5, 0.03)
label.Size = UDim2.fromOffset(330, 38)
label.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
label.BackgroundTransparency = 0.1
label.BorderSizePixel = 0
label.Font = Enum.Font.GothamMedium
label.TextColor3 = Color3.fromRGB(235, 238, 245)
label.TextSize = 16
label.Text = "Average drop rate: -- °C/sample"
label.Parent = screenGui

local currentRoomName
local previousTemperature
local decreaseSum = 0
local decreaseCount = 0

local function findRoom(rooms, roomName)
	if not rooms or type(roomName) ~= "string" or roomName == "" then
		return nil
	end
	local direct = rooms:FindFirstChild(roomName)
	if direct then
		return direct
	end
	local wanted = string.lower(roomName)
	for _, room in ipairs(rooms:GetChildren()) do
		if string.lower(room.Name) == wanted then
			return room
		end
	end
	return nil
end

local function reset(roomName, temperature)
	currentRoomName = roomName
	previousTemperature = temperature
	decreaseSum = 0
	decreaseCount = 0
	label.Text = "Average drop rate: -- °C/sample"
end

while screenGui.Parent do
	local ghost = workspace:FindFirstChild("Ghost")
	local map = workspace:FindFirstChild("Map")
	local rooms = map and map:FindFirstChild("Rooms")
	local roomName = ghost and ghost:GetAttribute("CurrentRoom") or nil
	local room = findRoom(rooms, roomName)
	local temperature = room and room:GetAttribute("Temperature") or nil

	if typeof(temperature) ~= "number" then
		reset(roomName, nil)
	elseif roomName ~= currentRoomName or previousTemperature == nil then
		reset(roomName, temperature)
	else
		local decrease = previousTemperature - temperature
		previousTemperature = temperature
		if decrease > 0 then
			decreaseSum = decreaseSum + decrease
			decreaseCount = decreaseCount + 1
			label.Text = string.format(
				"Average drop rate: %.6f °C/sample",
				decreaseSum / decreaseCount
			)
		end
	end

	task.wait(0.25)
end
