local createTraffic = require("../traffic")
local createSaltHit = require("../active-trackers/salt-hit")
local createSpeedTracker = require("../active-trackers/speed-tracker")
local createVerdict = require("../verdict")
local Aswang = require("../ghosts/Aswang")

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

local function instance(name, class, parent)
	local object = {
		Name = name,
		ClassName = class,
		Parent = parent,
		Descendants = {},
		Touched = signal(),
		AttributeSignals = {},
		PropertySignals = {},
	}
	function object:IsA(expected) return self.ClassName == expected end
	function object:GetAttribute(attribute) return self[attribute] end
	function object:GetAttributeChangedSignal(attribute)
		self.AttributeSignals[attribute] = self.AttributeSignals[attribute] or signal()
		return self.AttributeSignals[attribute]
	end
	function object:GetPropertyChangedSignal(property)
		self.PropertySignals[property] = self.PropertySignals[property] or signal()
		return self.PropertySignals[property]
	end
	function object:Rename(name)
		self.Name = name
		self:GetPropertyChangedSignal("Name"):Fire()
	end
	function object:GetDescendants() return self.Descendants end
	function object:IsDescendantOf(ancestor)
		local current = self.Parent
		while current do
			if current == ancestor then return true end
			current = current.Parent
		end
		return false
	end
	return object
end

local SaltFolder = instance("SaltPiles", "Folder")
SaltFolder.DescendantAdded = signal()
local salt = instance("SaltPile", "Model", SaltFolder)
local saltPart = instance("Salt", "BasePart", salt)
salt.Descendants = {saltPart}
SaltFolder.Descendants = {salt, saltPart}

local Ghost = instance("Ghost", "Model")
Ghost.Hunting = true
Ghost.Transparency = 0
local speedChanged = signal()
local Humanoid = {WalkSpeed = 22}
function Humanoid:GetPropertyChangedSignal() return speedChanged end
function Ghost:FindFirstChildOfClass() return Humanoid end
function Ghost:FindFirstChild() return nil end
local RunService = {Heartbeat = signal()}
local Traffic = createTraffic()
local Verdict = createVerdict({Traffic = Traffic})
local aswang = Aswang.new({Traffic = Traffic})
local speedTracker = createSpeedTracker({Traffic = Traffic, Ghost = Ghost})
local received = {}
local spatialQueries = 0
Traffic:Receive("SpeedTracker", function(name, payload)
	table.insert(received, {name = name, payload = payload})
end)

local tracker = createSaltHit({
	Traffic = Traffic,
	Ghost = Ghost,
	SaltFolder = SaltFolder,
	Workspace = {},
	RunService = RunService,
	NewOverlapParams = function() return {} end,
	IncludeFilterType = "Include",
	QueryGhostOverlap = function()
		spatialQueries += 1
		return false
	end,
	Clock = function() return 12 end,
})

local cleanSalt = instance("SaltPile2", "Model", SaltFolder)
local cleanPartA = instance("SaltA", "BasePart", cleanSalt)
local cleanPartB = instance("SaltB", "BasePart", cleanSalt)
cleanSalt.Descendants = {cleanPartA, cleanPartB}
SaltFolder.DescendantAdded:Fire(cleanSalt)
SaltFolder.DescendantAdded:Fire(cleanPartA)
SaltFolder.DescendantAdded:Fire(cleanPartB)
RunService.Heartbeat:Fire(0.1)
expect(spatialQueries == 2,
	"spatial contact fallback should query once per salt pile, not once per part")

Humanoid.WalkSpeed = 16.5
speedChanged:Fire()
salt:Rename("DisturbedSaltLine")

expect(#received == 2, "a disturbed salt model should emit a contact and its disturbed state")
expect(received[1].name == "SaltHit", "disturbed salt should start the speed split")
expect(received[1].payload.SaltCreatedAt == 12,
	"salt hits should retain the salt model's workspace creation timestamp")
expect(received[2].name == "SaltStateAfterHit" and received[2].payload.State == "disturbed",
	"disturbed salt should immediately confirm the split state")
expect(received[1].payload.ContactId == received[2].payload.ContactId,
	"the contact and disturbed state must use the same id")
expect(Verdict:Snapshot().Selected[1] == 1,
	"a raw 22 to 16.5 drop followed by disturbed salt should reach Aswang's verdict")

salt:Rename("DisturbedSaltLine")
expect(#received == 2, "the same disturbed salt should only be reported once")

local disturbedPile = instance("DisturbedSaltPile", "Model", SaltFolder)
SaltFolder.DescendantAdded:Fire(disturbedPile)
expect(#received == 4 and received[3].name == "SaltHit"
	and received[4].payload.State == "disturbed",
	"a newly replicated DisturbedSaltPile should use the same signal path")

tracker:Destroy()
speedTracker:Destroy()
aswang:Destroy()
print("salt-hit.spec: DisturbedSaltLine rename reaches the Aswang verdict")
