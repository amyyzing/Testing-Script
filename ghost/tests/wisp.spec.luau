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
		AncestryChanged = signal(),
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
	function object:GetPropertyChangedSignal(property)
		return self:GetAttributeChangedSignal("property:" .. property)
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
	Ghost.Attributes.Hunting = true
	local ghostPart = node("HumanoidRootPart", "BasePart")
	Ghost:Add(ghostPart)
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local wisp = Wisp.new({Traffic = Traffic})
	local clock, timers = 0, {}
	local function advance(seconds)
		local target = clock + seconds
		while true do
			table.sort(timers, function(a, b) return a.At < b.At end)
			if not timers[1] or timers[1].At > target then break end
			local timer = table.remove(timers, 1)
			clock = timer.At
			timer.Run()
		end
		clock = target
	end
	local collidable = createHolyOilCollidable({Traffic = Traffic, Ghost = Ghost, Workspace = World,
		DelayTask = function(seconds, callback) table.insert(timers, {At = clock + seconds, Run = callback}) end})
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
		Advance = advance,
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
local detached = oilHarness(true)
detached.Oil.Parent = nil
detached.Oil:SetAttribute("Burning", true)
expect(not table.find(detached.Verdict.RuledOut, 24) and detached.Collidable.Running,
	"detached oil cannot create a Wisp contradiction")
detached.Destroy()
nonCollidable.Oil:SetAttribute("Burning", true)
expect(nonCollidable.Verdict.SourceConfidence[24] == nil,
	"an ignition callback must not classify the wall before its collision state settles")
nonCollidable.Advance(0.51)
expect((nonCollidable.Verdict.Confidence[24] == 65 and nonCollidable.Verdict.SourceConfidence[24] == 99)
	and nonCollidable.Collidable.Result == false,
	"non-collidable burning oil should support Wisp directly")
expect(nonCollidable.Verdict.Confidence[17] == nil,
	"the wall observation must not invent a Doppelganger verdict")
nonCollidable.Destroy()

local collidable = oilHarness(false)
collidable.Wall.CanCollide = true
collidable.Oil:SetAttribute("Burning", true)
collidable.Advance(0.51)
expect(table.find(collidable.Verdict.RuledOut, 24),
	"the wall becoming collidable at ignition should rule Wisp out")
collidable.Destroy()

local race = oilHarness(false)
local falseSupport = false
race.Traffic:Receive("Verdict", function(kind, payload)
	if kind == "Support" and payload.Ghost == "Wisp" then falseSupport = true end
end)
race.Oil:SetAttribute("Burning", true)
race.Advance(0.1)
race.Wall.CanCollide = true
race.Wall:GetPropertyChangedSignal("CanCollide"):Fire()
race.Advance(0.41)
expect(race.Collidable.Running and not falseSupport,
	"a delayed collision update must restart qualification without transient Wisp support")
race.Advance(0.1)
expect(table.find(race.Verdict.RuledOut, 24) and not falseSupport,
	"a stable collidable wall after ignition must exclude Wisp")
race.Destroy()

local interrupted = oilHarness(false)
interrupted.Oil:SetAttribute("Burning", true)
interrupted.Advance(0.2)
interrupted.Ghost:SetAttribute("Hunting", false)
interrupted.Advance(1)
expect(interrupted.Collidable.Running and interrupted.Verdict.SourceConfidence[24] == nil,
	"burning oil outside a hunt cannot identify Wisp")
interrupted.Ghost:SetAttribute("Hunting", true)
interrupted.Advance(0.2)
interrupted.Oil:SetAttribute("Burning", false)
interrupted.Advance(1)
expect(interrupted.Collidable.Running and interrupted.Verdict.SourceConfidence[24] == nil,
	"extinguishing oil cancels its pending collision observation")
interrupted.Oil:SetAttribute("Burning", true)
interrupted.Destroy()
interrupted.Advance(1)
expect(interrupted.Verdict.SourceConfidence[24] == nil,
	"destroying the tracker cancels pending collision observations")

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
	expect(roomVerdict.Confidence[24] == nil and roomVerdict.SourceConfidence[24] == nil,
		"a favourite-room hunt cannot support Wisp, even when repeated")
	roomTraffic("HuntingState", {Hunting = false, Time = count + 0.5}):SendTo("FavouriteHuntRoom")
end
expect(roomVerdict.Confidence[24] == nil and roomVerdict.SourceConfidence[24] == nil,
	"absence of an outside-room start must not become positive support")
currentRoom = {Name = "Hallway"}
roomTraffic("HuntingState", {Hunting = true, Time = 10}):SendTo("FavouriteHuntRoom")
expect(table.find(roomVerdict.RuledOut, 24),
	"one hunt beginning outside the favourite room should rule Wisp out")
roomTracker:Destroy()
roomWisp:Destroy()

print("wisp.spec: burning oil collision and favourite hunt-room pipelines passed")
