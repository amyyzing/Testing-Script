local createMovement = require("../movement")

local Vector = {}
Vector.__index = Vector
function Vector.new(x, y, z)
	return setmetatable({X = x, Y = y, Z = z}, Vector)
end
function Vector.__mul(left, right)
	if type(left) == "number" then left, right = right, left end
	return Vector.new(left.X * right, left.Y * right, left.Z * right)
end

local rootPosition = Vector.new(0, 0, 0)
local room
local boundingPart = {
	Name = "BoundingBox",
	Parent = true,
	Size = Vector.new(40, 20, 40),
	CFrame = {PointToObjectSpace = function(_, position) return position end},
	IsA = function(_, class) return class == "BasePart" end,
	IsDescendantOf = function(_, ancestor) return ancestor == room end,
}
room = {
	FindFirstChild = function(_, name)
		if name == "BoundingBox" then return boundingPart end
	end,
	GetDescendants = function() return {} end,
}
local rooms = {
	FindFirstChild = function(_, name)
		if name == "Base Camp" then return room end
	end,
	GetChildren = function() return {room} end,
}
local map = {FindFirstChild = function(_, name) if name == "Rooms" then return rooms end end}
local truckPosition = Vector.new(3, 0, 4)
local truck = {
	Position = truckPosition,
	IsA = function(_, class) return class == "BasePart" end,
}
local baseCamp = {
	FindFirstChild = function(_, name) if name == "Truck" then return truck end end,
}
local workspace = {
	FindFirstChild = function(_, name)
		if name == "Map" then return map end
		if name == "BaseCamp" then return baseCamp end
	end,
}
local root = {
	Position = rootPosition,
	IsA = function(_, class) return class == "BasePart" end,
}
local character = {
	FindFirstChild = function(_, name) if name == "HumanoidRootPart" then return root end end,
}
local calls = 0
local capturedOptions
local movement = createMovement({
	Services = {Workspace = workspace},
	Player = {Character = character},
	RuntimeIsActive = function() return true end,
	CreateRoomTeleport = function()
		return function(_, options)
			calls += 1
			capturedOptions = options
			return true
		end
	end,
})

assert(movement.TeleportToBaseCamp({}), "an already-contained player should be accepted")
assert(calls == 0, "ordinary Base Camp checks should not move an already-contained root")
assert(movement.TeleportToBaseCamp({ForcePreferredPosition = true}),
	"completion should force a fresh Base Camp placement")
assert(calls == 1, "forced completion must call the real room teleport")
assert(capturedOptions.PreferredPositions[1] == truckPosition,
	"the forced placement should prefer the Truck position")

print("movement.spec: forced Base Camp placement and Truck preference passed")
