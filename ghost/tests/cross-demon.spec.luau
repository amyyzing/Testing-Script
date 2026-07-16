local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createCrossBurn = require("../active-trackers/cross-burn")
local createCrossAnimation = require("../discardable-trackers/cross-animation")
local Demon = require("../ghosts/Demon")

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
			for _, callback in ipairs(callbacks) do callback(...) end
		end,
	}
end

local function cframe(x, y, z, angle)
	local rotation = {Angle = angle}
	function rotation:ToObjectSpace(other)
		local difference = other.Angle - self.Angle
		return {ToAxisAngle = function() return nil, difference end}
	end
	return {Position = {X = x, Y = y, Z = z}, Rotation = rotation}
end

local function run(animated)
	local heartbeat = signal()
	local now = 0
	local part = {Name = "Cross", Parent = true, CFrame = cframe(0, 0, 0, 0)}
	part.Position = part.CFrame.Position
	function part:IsA(class) return class == "BasePart" end
	local cross = {
		Name = "CrossModel",
		Parent = true,
		ItemName = "Cross",
		EquipDisabled = false,
		Changed = signal(),
	}
	function cross:IsA(class) return class == "Model" end
	function cross:GetAttribute(name) return self[name] end
	function cross:GetAttributeChangedSignal() return self.Changed end
	function cross:FindFirstChild(name) return name == "Cross" and part or nil end
	function cross:SetDisabled(value)
		self.EquipDisabled = value
		self.Changed:Fire()
	end
	local items = {Name = "Items", Parent = true, ChildAdded = signal()}
	function items:GetChildren() return {cross} end
	local World = {ChildAdded = signal()}
	function World:FindFirstChild(name) return name == "Items" and items or nil end

	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local demon = Demon.new({Traffic = Traffic})
	local animation = createCrossAnimation({
		Traffic = Traffic,
		RunService = {Heartbeat = heartbeat},
		Clock = function() return now end,
	})
	local burn = createCrossBurn({
		Traffic = Traffic,
		Workspace = World,
		Defer = function(callback) callback() end,
	})

	now = 4
	heartbeat:Fire()
	expect(Verdict.Confidence[3] == nil and not table.find(Verdict.RuledOut, 3),
		"an idle Cross must not create a Demon verdict")
	cross:SetDisabled(true)
	if animated then
		part.CFrame = cframe(0, 0.5, 0, math.rad(60))
		part.Position = part.CFrame.Position
		now = 4.1
	else
		now = 8.1
	end
	heartbeat:Fire()

	burn:Destroy()
	animation:Destroy()
	demon:Destroy()
	return Verdict
end

local positive = run(true)
expect(positive.Confidence[3] == 99 and not table.find(positive.RuledOut, 3),
	"a burning Cross that floats and rotates should support Demon")
local negative = run(false)
expect(table.find(negative.RuledOut, 3) ~= nil,
	"a burning Cross without the animation should rule out Demon")

print("cross-demon.spec: EquipDisabled burn and Cross animation verdicts passed")
