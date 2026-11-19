local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createSaltState = require("../discardable-trackers/salt-state-after-hit")
local Wraith = require("../ghosts/Wraith")

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

local function salt(name)
	local object = {
		Name = name,
		Parent = {},
		AncestryChanged = signal(),
		DescendantAdded = signal(),
		NameChanged = signal(),
		DisturbedChanged = signal(),
	}
	function object:GetAttribute() return false end
	function object:GetDescendants() return {} end
	function object:GetPropertyChangedSignal() return self.NameChanged end
	function object:GetAttributeChangedSignal() return self.DisturbedChanged end
	function object:SetName(value)
		self.Name = value
		self.NameChanged:Fire()
	end
	return object
end

local function harness()
	local now = 0
	local delayed = {}
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local wraith = Wraith.new({Traffic = Traffic})
	local tracker = createSaltState({
		Traffic = Traffic,
		Clock = function() return now end,
		DelayTask = function(seconds, callback)
			table.insert(delayed, {Seconds = seconds, Callback = callback})
		end,
	})
	return {
		Traffic = Traffic,
		Verdict = Verdict,
		Delayed = delayed,
		SetTime = function(value) now = value end,
		Destroy = function()
			tracker:Destroy()
			wraith:Destroy()
		end,
	}
end

local positive = harness()
local clean = salt("SaltPile")
positive.Traffic("SaltHit", {
	ContactId = 1,
	Salt = clean,
	SaltCreatedAt = 0,
}):SendTo("SaltStateAfterHit")
expect(#positive.Delayed == 1 and positive.Delayed[1].Seconds == 4
	and positive.Verdict.Confidence[25] == nil,
	"an undisturbed hit must not support Wraith before the creation grace ends")
positive.SetTime(4)
positive.Delayed[1].Callback()
expect((positive.Verdict.Confidence[25] == 65 and positive.Verdict.SourceConfidence[25] == 99)
	and positive.Verdict.Selected[1] == 25,
	"a directly hit salt remaining undisturbed through the grace should support Wraith")
positive.Traffic("SaltStateAfterHit", {State = "disturbed", ContactId = 1}):SendTo("Wraith")
expect(table.find(positive.Verdict.RuledOut, 25),
	"a later native disturbance must correct a provisional undisturbed-salt match")
positive.Traffic("SaltStateAfterHit", {State = "undisturbed", GraceComplete = true, ContactId = 2}):SendTo("Wraith")
expect(table.find(positive.Verdict.RuledOut, 25),
	"another undisturbed contact must not resurrect a contradicted Wraith match")
positive.Destroy()

local negative = harness()
local disturbed = salt("SaltPile")
negative.Traffic("SaltHit", {
	ContactId = 2,
	Salt = disturbed,
	SaltCreatedAt = 0,
}):SendTo("SaltStateAfterHit")
disturbed:SetName("DisturbedSaltPile")
expect(table.find(negative.Verdict.RuledOut, 25),
	"a direct salt hit becoming disturbed should rule Wraith out immediately")
negative.Destroy()

local missing = harness()
local removed = salt("SaltPile")
missing.Traffic("SaltHit", {ContactId = 3, Salt = removed, SaltCreatedAt = 0}):SendTo("SaltStateAfterHit")
removed.Parent = nil
removed.AncestryChanged:Fire()
missing.SetTime(4)
missing.Delayed[1].Callback()
expect(missing.Verdict.Confidence[25] == nil and not table.find(missing.Verdict.RuledOut, 25),
	"losing the observed pile cannot support or exclude Wraith")
missing.Destroy()

print("wraith.spec: direct salt hit and four-second creation grace passed")
