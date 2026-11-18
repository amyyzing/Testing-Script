local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createHolyOilActivate = require("../dormant-trackers/holy-oil-activate")
local createHolyOilCollidable = require("../discardable-trackers/holy-oil-collidable")
local createFavouriteHuntRoom = require("../dormant-trackers/favourite-hunt-room")
local Wisp = require("../ghosts/Wisp")

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
		Fire = function(_, ...)
			for _, callback in ipairs(table.clone(callbacks)) do callback(...) end
		end,
	}
end

local function node(name, className)
	local object = {
		Name = name,
		ClassName = className,
		Children = {},
		Attributes = {},
		Signals = {},
		ChildAdded = signal(),
		DescendantAdded = signal(),
	}
	if className == "BasePart" then object.Touched = signal() end
	function object:IsA(kind)
		return self.ClassName == kind or kind == "BasePart" and self.ClassName == "BasePart"
	end
	function object:GetAttribute(attribute) return self.Attributes[attribute] end
	function object:GetAttributeChangedSignal(attribute)
		self.Signals[attribute] = self.Signals[attribute] or signal()
		return self.Signals[attribute]
	end
	function object:SetAttribute(attribute, value)
		self.Attributes[attribute] = value
		if self.Signals[attribute] then self.Signals[attribute]:Fire() end
	end
	function object:Add(child)
		child.Parent = self
		table.insert(self.Children, child)
		self.ChildAdded:Fire(child)
		local parent = self
		while parent do
			parent.DescendantAdded:Fire(child)
			parent = parent.Parent
		end
	end
	function object:GetChildren() return table.clone(self.Children) end
	function object:GetDescendants()
		local result = {}
		local function append(parent)
			for _, child in ipairs(parent.Children) do
				table.insert(result, child)
				append(child)
			end
		end
		append(self)
		return result
	end
	function object:FindFirstChild(childName, recursive)
		for _, child in ipairs(self.Children) do
			if child.Name == childName then return child end
		end
		if recursive then
			for _, child in ipairs(self:GetDescendants()) do
				if child.Name == childName then return child end
			end
		end
	end
	function object:IsDescendantOf(parent)
		local current = self.Parent
		while current do
			if current == parent then return true end
			current = current.Parent
		end
		return false
	end
	return object
end

local function oilHarness(canCollide)
	local World = node("Workspace", "Workspace")
	local folder = node("HolyOil", "Folder")
	local oil = node("HolyOil", "Model")
	local wall = node("GhostWall", "BasePart")
	wall.CanCollide = canCollide
	oil:Add(wall)
	folder:Add(oil)
	World:Add(folder)
	local Ghost = node("Ghost", "Model")
	local ghostPart = node("HumanoidRootPart", "BasePart")
	Ghost:Add(ghostPart)
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local wisp = Wisp.new({Traffic = Traffic})
	local collidable = createHolyOilCollidable({Traffic = Traffic})
	local activate = createHolyOilActivate({Traffic = Traffic, Workspace = World})
	return {
		Traffic = Traffic,
		Verdict = Verdict,
		Ghost = Ghost,
		GhostPart = ghostPart,
		Oil = oil,
		Wall = wall,
		Activate = activate,
		Collidable = collidable,
		Wisp = wisp,
		Destroy = function()
			activate:Destroy()
			collidable:Destroy()
			wisp:Destroy()
		end,
	}
end

local nonCollidable = oilHarness(false)
expect(nonCollidable.Verdict.Confidence[24] == nil,
	"the default non-collidable wall before ignition must not identify Wisp")
nonCollidable.Oil:SetAttribute("Burning", true)
expect(nonCollidable.Verdict.Confidence[24] == 99
	and nonCollidable.Collidable.Result == false,
	"non-collidable burning oil should support Wisp directly")
expect(nonCollidable.Verdict.Confidence[17] == nil,
	"the wall observation must not invent a Doppelganger verdict")
nonCollidable.Destroy()

local collidable = oilHarness(false)
collidable.Wall.CanCollide = true
collidable.Oil:SetAttribute("Burning", true)
expect(table.find(collidable.Verdict.RuledOut, 24),
	"the wall becoming collidable at ignition should rule Wisp out")
collidable.Destroy()

local roomTraffic = createTraffic()
local roomVerdict = createVerdict({Traffic = roomTraffic})
local roomWisp = Wisp.new({Traffic = roomTraffic})
local roomGhost = node("Ghost", "Model")
roomGhost.Attributes.Hunting = false
roomGhost.Attributes.FavoriteRoom = "Library"
local currentRoom = {Name = "Library"}
local roomTracker = createFavouriteHuntRoom({
	Traffic = roomTraffic,
	Ghost = roomGhost,
	ReadCurrentRoom = function() return currentRoom end,
})
for count = 1, 9 do
	roomTraffic("HuntingState", {Hunting = true, Time = count}):SendTo("FavouriteHuntRoom")
	expect(roomVerdict.Confidence[24] == 5 + count * 10,
		"favourite-room hunt confidence should rise by ten percent per hunt")
	roomTraffic("HuntingState", {Hunting = false, Time = count + 0.5}):SendTo("FavouriteHuntRoom")
end
expect(roomVerdict.Confidence[24] == 95,
	"nine favourite-room hunt starts should cap Wisp confidence at 95 percent")
currentRoom = {Name = "Hallway"}
roomTraffic("HuntingState", {Hunting = true, Time = 10}):SendTo("FavouriteHuntRoom")
expect(table.find(roomVerdict.RuledOut, 24),
	"one hunt beginning outside the favourite room should rule Wisp out")
roomTracker:Destroy()
roomWisp:Destroy()

print("wisp.spec: burning oil collision and favourite hunt-room pipelines passed")
