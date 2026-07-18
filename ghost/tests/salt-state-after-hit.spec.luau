local createTraffic = require("../traffic")
local createSaltState = require("../discardable-trackers/salt-state-after-hit")

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

local function object(name)
	local value = {
		Name = name,
		Disturbed = false,
		Descendants = {},
		DescendantAdded = signal(),
		NameChanged = signal(),
		DisturbedChanged = signal(),
	}
	function value:GetAttribute(attribute) return attribute == "Disturbed" and self.Disturbed or nil end
	function value:GetDescendants() return self.Descendants end
	function value:GetPropertyChangedSignal() return self.NameChanged end
	function value:GetAttributeChangedSignal() return self.DisturbedChanged end
	function value:SetName(newName)
		self.Name = newName
		self.NameChanged:Fire()
	end
	return value
end

local now = 0
local delayed, results = {}, {}
local Traffic = createTraffic()
Traffic:Receive("SpeedTracker", function(signalName, payload)
	if signalName == "SaltStateAfterHit" then table.insert(results, payload) end
end)
local tracker = createSaltState({
	Traffic = Traffic,
	Delay = 1.25,
	CreationGrace = 4,
	Clock = function() return now end,
	DelayTask = function(seconds, callback)
		table.insert(delayed, {Seconds = seconds, Callback = callback})
	end,
})

local salt, child = object("SaltPile"), object("Salt")
salt.Descendants = {child}
Traffic("SaltHit", {
	ContactId = 1,
	Salt = salt,
	Hunting = true,
	SaltCreatedAt = 0,
}):SendTo("SaltStateAfterHit")
expect(#results == 0 and #delayed == 1 and delayed[1].Seconds == 4,
	"a newly created clean salt should retain the full four-second grace")
child:SetName("DisturbedSaltLine")
expect(#results == 1 and results[1].State == "disturbed",
	"a disturbed descendant change should complete the probe immediately")
delayed[1].Callback()
expect(#results == 1, "the delayed fallback should not duplicate a completed probe")

local clean = object("SaltPile")
now = 4
Traffic("SaltHit", {
	ContactId = 2,
	Salt = clean,
	Hunting = false,
	SaltCreatedAt = 0,
}):SendTo("SaltStateAfterHit")
expect(delayed[2].Seconds == 1.25,
	"an older salt should retain only the normal post-hit observation window")
delayed[2].Callback()
expect(#results == 2 and results[2].State == "undisturbed"
	and results[2].GraceComplete == true,
	"the delayed check should report an undisturbed salt only after its grace")

tracker:Destroy()
print("salt-state-after-hit.spec: event-driven disturbed probe passed")
