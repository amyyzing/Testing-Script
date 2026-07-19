local createGhostRoomBillboard = require("../ghost-room-billboard")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			return {Disconnect = function()
				local index = table.find(callbacks, callback)
				if index then table.remove(callbacks, index) end
			end}
		end,
		Fire = function(_)
			for _, callback in ipairs(callbacks) do callback() end
		end,
	}
end

local function room(name)
	local target = {Name = "BoundingBox"}
	function target:IsA(className) return className == "BasePart" end
	function target:GetChildren() return {} end
	local value = {Name = name, Target = target}
	function value:FindFirstChild(childName)
		return childName == "BoundingBox" and self.Target or nil
	end
	function value:GetDescendants() return {self.Target} end
	return value
end

local office, kitchen = room("Office"), room("Kitchen")
local rooms = {Office = office, Kitchen = kitchen}
function rooms:FindFirstChild(name) return self[name] end
function rooms:GetChildren() return {self.Office, self.Kitchen} end
local map = {Rooms = rooms}
function map:FindFirstChild(name) return self[name] end
local world = {Map = map}
function world:FindFirstChild(name) return self[name] end

local roomChanged = signal()
local ghost = {FavoriteRoom = "Office"}
function ghost:GetAttribute(name) return name == "FavoriteRoom" and self.FavoriteRoom or nil end
function ghost:GetAttributeChangedSignal() return roomChanged end
function ghost:SetFavouriteRoom(value)
	self.FavoriteRoom = value
	roomChanged:Fire()
end

local created, destroyed = {}, 0
local controller = createGhostRoomBillboard({
	Ghost = ghost,
	Workspace = world,
	GuiParent = {},
	Accent = "accent",
	VisualFactory = function(target, roomName)
		local billboard = {Adornee = target}
		function billboard:Destroy() destroyed += 1 end
		local label = {Text = roomName}
		table.insert(created, {Target = target, Label = label})
		return billboard, label
	end,
})

expect(#created == 1 and created[1].Target == office.Target, "the initial favourite room should be marked")
expect(created[1].Label.Text == "Office", "the marker should show the room name")
ghost:SetFavouriteRoom("kitchen")
expect(#created == 2 and created[2].Target == kitchen.Target, "room changes should move the marker")
expect(destroyed == 1, "moving the marker should destroy the old billboard")
ghost:SetFavouriteRoom(nil)
expect(controller.Billboard == nil and destroyed == 2, "missing favourite rooms should remove the marker")
controller:Destroy()

print("ghost-room-billboard.spec: legacy room selection, refresh, and cleanup passed")
