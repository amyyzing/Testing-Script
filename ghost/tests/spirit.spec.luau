local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createHolyOilColour = require("../discardable-trackers/holy-oil-colour")
local Spirit = require("../ghosts/Spirit")

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
	function object:IsA(kind) return self.ClassName == kind end
	function object:IsDescendantOf(ancestor)
		local parent = self.Parent
		while parent do
			if parent == ancestor then return true end
			parent = parent.Parent
		end
		return false
	end
	function object:GetAttribute(name) return self.Attributes[name] end
	function object:GetAttributeChangedSignal(name)
		self.Signals["A:" .. name] = self.Signals["A:" .. name] or signal()
		return self.Signals["A:" .. name]
	end
	function object:GetPropertyChangedSignal(name)
		self.Signals["P:" .. name] = self.Signals["P:" .. name] or signal()
		return self.Signals["P:" .. name]
	end
	function object:SetAttribute(name, value)
		self.Attributes[name] = value
		local changed = self.Signals["A:" .. name]
		if changed then changed:Fire() end
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
	return object
end

local function colour(red, green, blue)
	return {R = red, G = green, B = blue}
end

local function sequence(first, last)
	return {Keypoints = {
		{Time = 0, Value = first},
		{Time = 1, Value = last},
	}}
end

local function harness(first, last)
	local World = node("Workspace", "Workspace")
	local folder = node("HolyOil", "Folder")
	local oil = node("HolyOil", "Model")
	local container = node("ParticleContainer", "Folder")
	local primary = node("Primary", "ParticleEmitter")
	local secondary = node("Secondary", "ParticleEmitter")
	primary.Color, secondary.Color = sequence(first, last), sequence(first, last)
	container:Add(primary)
	container:Add(secondary)
	oil:Add(container)
	folder:Add(oil)
	World:Add(folder)
	local Ghost = node("Ghost", "Model")
	Ghost.Attributes.Hunting = false
	local delayed = {}
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local processor = Spirit.new({Traffic = Traffic})
	local tracker = createHolyOilColour({
		Traffic = Traffic,
		Workspace = World,
		Ghost = Ghost,
		DelayTask = function(_, callback) table.insert(delayed, callback) end,
	})
	return {
		Ghost = Ghost,
		Oil = oil,
		Primary = primary,
		Secondary = secondary,
		Verdict = Verdict,
		Tracker = tracker,
		RunDelayed = function()
			local pending = delayed
			delayed = {}
			for _, callback in ipairs(pending) do callback() end
		end,
		RunNextDelayed = function()
			local callback = table.remove(delayed, 1)
			if callback then callback() end
		end,
		Destroy = function()
			tracker:Destroy()
			processor:Destroy()
		end,
	}
end

local blue = harness(colour(0.384314, 0.541216, 1), colour(0, 0.263333, 1))
blue.Oil:SetAttribute("Burning", true)
expect(blue.Verdict.Confidence[19] == nil, "burning oil outside a hunt must be ignored")
blue.Ghost:SetAttribute("Hunting", true)
expect(blue.Verdict.Confidence[19] == nil,
	"the initial gradient must not resolve before the stability window")
blue.RunDelayed()
expect((blue.Verdict.Confidence[19] == 65 and blue.Verdict.SourceConfidence[19] == 99) and blue.Tracker.Result == "Spirit",
	"both blue emitter sequences should support Spirit at medium confidence while Doppelganger remains possible")
blue.Destroy()

local orange = harness(colour(1, 0.694118, 0.384314), colour(1, 0.333333, 0))
orange.Ghost:SetAttribute("Hunting", true)
orange.Oil:SetAttribute("Burning", true)
orange.RunDelayed()
expect(table.find(orange.Verdict.RuledOut, 19) and orange.Tracker.Result == "Normal",
	"both orange emitter sequences should rule Spirit out at 99 percent")
orange.Destroy()

local unknown = harness(colour(0.2, 0.2, 0.2), colour(0.4, 0.4, 0.4))
unknown.Ghost:SetAttribute("Hunting", true)
unknown.Oil:SetAttribute("Burning", true)
expect(unknown.Tracker.Running and unknown.Verdict.Confidence[19] == nil
	and not table.find(unknown.Verdict.RuledOut, 19),
	"an unknown or transitioning sequence must remain inconclusive")
unknown.Primary.Color = sequence(colour(0.384314, 0.541216, 1), colour(0, 0.263333, 1))
unknown.Primary.Signals["P:Color"]:Fire()
expect(unknown.Tracker.Running, "one matching emitter must not resolve the gradient")
unknown.Secondary.Color = sequence(colour(0.384314, 0.541216, 1), colour(0, 0.263333, 1))
unknown.Secondary.Signals["P:Color"]:Fire()
unknown.RunDelayed()
expect(unknown.Tracker.Result == "Spirit",
	"the tracker should resolve once both gradients settle on the Spirit sequence")
unknown.Destroy()

local transition = harness(colour(1, 0.694118, 0.384314), colour(1, 0.333333, 0))
transition.Ghost:SetAttribute("Hunting", true)
transition.Oil:SetAttribute("Burning", true)
transition.Primary.Color = sequence(colour(0.384314, 0.541216, 1), colour(0, 0.263333, 1))
transition.Secondary.Color = sequence(colour(0.384314, 0.541216, 1), colour(0, 0.263333, 1))
transition.RunDelayed()
expect(transition.Tracker.Running,
	"a missed colour-change signal should restart rather than accept stale orange")
transition.RunDelayed()
expect(transition.Tracker.Result == "Spirit"
	and not table.find(transition.Verdict.RuledOut, 19),
	"an orange starting gradient that settles blue must resolve as Spirit")
transition.Destroy()

local gap = harness(colour(1, 0.694118, 0.384314), colour(1, 0.333333, 0))
gap.Ghost:SetAttribute("Hunting", true)
gap.Oil:SetAttribute("Burning", true)
local originalParent = gap.Oil.Parent
gap.Oil.Parent = nil
gap.Oil.AncestryChanged:Fire()
gap.Oil.Parent = originalParent
gap.Oil.AncestryChanged:Fire()
gap.RunNextDelayed()
expect(gap.Tracker.Running and not table.find(gap.Verdict.RuledOut, 19),
	"removing and restoring oil must invalidate the old pending colour observation")
gap.RunNextDelayed()
expect(table.find(gap.Verdict.RuledOut, 19), "restored oil needs a fresh complete stability window")
gap.Destroy()

local outside = harness(colour(1, 0.694118, 0.384314), colour(1, 0.333333, 0))
outside.Oil.Parent = node("Inventory", "Folder")
outside.Ghost:SetAttribute("Hunting", true)
outside.Oil:SetAttribute("Burning", true)
outside.RunDelayed()
expect(outside.Tracker.Running and not table.find(outside.Verdict.RuledOut, 19),
	"an oil model outside Workspace cannot qualify a colour observation")
outside.Destroy()

print("spirit.spec: qualified blue and normal Holy Oil sequences passed")
