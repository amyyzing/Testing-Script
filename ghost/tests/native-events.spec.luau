local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createTracker = require("../active-trackers/native-events")
local Banshee = require("../ghosts/Banshee")
local Leviathan = require("../ghosts/Leviathan")
local Spirit = require("../ghosts/Spirit")
local Doppelganger = require("../ghosts/Doppelganger")
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
local added = signal()
local objects = {}
local world = {DescendantAdded = added, GetDescendants = function() return objects end}
local function object(name, parent, attrs)
	local signals = {}
	local obj = {Name = name, Parent = parent, Attrs = attrs or {}}
	function obj:IsA(kind) return kind == "Model" end
	function obj:IsDescendantOf(root) return root == world end
	function obj:GetAttribute(key) return self.Attrs[key] end
	function obj:GetAttributeChangedSignal(key)
		signals[key] = signals[key] or signal()
		return signals[key]
	end
	function obj:SetAttribute(key, value)
		self.Attrs[key] = value
		self:GetAttributeChangedSignal(key):Fire()
	end
	table.insert(objects, obj)
	return obj
end
local glassFolder = {Name = "BrokenGlass"}
object("BrokenGlass", glassFolder)
local box = object("Box", {Name = "Items"}, {ItemName = "Spirit Box"})
local traffic = createTraffic()
local verdict = createVerdict({Traffic = traffic})
local processors = {Banshee.new({Traffic = traffic}), Leviathan.new({Traffic = traffic}),
	Spirit.new({Traffic = traffic}), Doppelganger.new({Traffic = traffic})}
local now = 0
local tracker = createTracker({Traffic = traffic, Workspace = world, Clock = function() return now end})
assert(verdict.Confidence[2] == nil, "existing glass must not count as a fresh burst")
added:Fire(object("BrokenGlass", glassFolder))
assert(verdict.Confidence[2] == nil, "one new glass model is not a burst")
now = 1
added:Fire(object("BrokenGlass", glassFolder))
assert(verdict.Confidence[2] == 65, "two fresh glass models provide qualified supporting evidence")
box:SetAttribute("LeviathanGlitch", 123)
assert(verdict.Confidence[9] == 99, "native glitch must reach the Leviathan processor")
local candle = object("Lantern", {Name = "Interactables"})
added:Fire(candle)
candle:SetAttribute("SpiritCandle", true)
assert(verdict.Confidence[17] == 60 and verdict.Confidence[19] == 60,
	"shared candle ability must support both Spirit and Doppelganger")
tracker:Destroy()
for _, processor in ipairs(processors) do processor:Destroy() end
print("native-events.spec: new glass, native glitch, and shared candle observations passed")
