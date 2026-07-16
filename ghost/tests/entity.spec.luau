local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createItemTeleport = require("../active-trackers/item-teleport")
local createSmokeHolder = require("../discardable-trackers/smoke-holder")
local Entity = require("../ghosts/Entity")

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

local now = 0
local heartbeat, descendantAdded = signal(), signal()
local item = {Current = {X = 0, Y = 0, Z = 0}}
function item:IsA(class) return class == "Model" end
function item:GetPivot() return {Position = self.Current} end
local items = {ChildAdded = signal(), ChildRemoved = signal()}
function items:GetChildren() return {item} end
local World = {DescendantAdded = descendantAdded, Smoke = nil}
function World:FindFirstChild(name)
	if name == "Items" then return items end
	if (name == "SmokeHolder" or name == "Smoke Holder") and self.Smoke then return self.Smoke end
	return nil
end

local delayed = {}
local Traffic = createTraffic()
local Verdict = createVerdict({Traffic = Traffic})
local entity = Entity.new({Traffic = Traffic})
local smokeTracker = createSmokeHolder({
	Traffic = Traffic,
	Workspace = World,
	Clock = function() return now end,
	Delay = function(seconds, callback)
		table.insert(delayed, {Seconds = seconds, Callback = callback})
	end,
})
local teleports = {}
Traffic:Receive("SmokeHolder", function(signalName, payload)
	if signalName == "ItemTeleported" then table.insert(teleports, payload) end
end)
local teleportTracker = createItemTeleport({
	Traffic = Traffic,
	Workspace = World,
	RunService = {Heartbeat = heartbeat},
	Clock = function() return now end,
})

item.Current = {X = 40, Y = 0, Z = 0}
now = 0.4
heartbeat:Fire(0.4)
expect(#teleports == 1 and teleports[1].Distance == 40,
	"a 40-stud single-sample jump should emit one item teleport")
local firstDelay = table.remove(delayed, 1)
expect(firstDelay.Seconds == 3, "Entity should wait three seconds for its Smoke Holder")
firstDelay.Callback()
expect(Verdict.NegativeConfidence[6] == 50 and not table.find(Verdict.RuledOut, 6),
	"a smoke-free teleport should be a 50% Entity negative, not a rule-out")
expect(#Verdict.Selected == 0, "a soft negative alone must not select Entity")

Verdict:Reset()
item.Current = {X = 80, Y = 0, Z = 0}
now = 0.8
heartbeat:Fire(0.4)
local smoke = {Name = "Smoke Holder"}
World.Smoke = smoke
descendantAdded:Fire(smoke)
expect(Verdict.Confidence[6] == 99 and Verdict.Selected[1] == 6,
	"a teleport followed by a Smoke Holder should support and select Entity")
if delayed[1] then table.remove(delayed, 1).Callback() end
expect(Verdict.Confidence[6] == 99,
	"the expired no-smoke callback must not overwrite a completed smoke result")

item.Current = {X = 120, Y = 0, Z = 0}
items.ChildRemoved:Fire(item)
items.ChildAdded:Fire(item)
now = 1.2
heartbeat:Fire(0.4)
expect(#teleports == 2,
	"an item removed and re-added between samples should receive a new baseline")

World.Smoke = nil
now = 4.2
heartbeat:Fire(0.4)
Verdict:Reset()
item.Current = {X = 160, Y = 0, Z = 0}
now = 4.6
heartbeat:Fire(0.4)
expect(#teleports == 3 and delayed[1], "a later teleport should begin another smoke probe")
World.Smoke = {Name = "SmokeHolder"}
table.remove(delayed, 1).Callback()
expect(Verdict.Confidence[6] == 99 and not Verdict.NegativeConfidence[6],
	"the final recursive scan should find a Smoke Holder even without DescendantAdded")

Verdict:Reset()
Traffic("Support", {Ghost = "Entity", Confidence = 99}):SendTo("Verdict")
Traffic("Negative", {Ghost = "Entity", Confidence = 50}):SendTo("Verdict")
Traffic("Support", {Ghost = "Aswang", Confidence = 60}):SendTo("Verdict")
expect(Verdict.Selected[1] == 1 and not table.find(Verdict.RuledOut, 6),
	"selection should rank positive confidence minus soft negative confidence")

teleportTracker:Destroy()
smokeTracker:Destroy()
entity:Destroy()
print("entity.spec: item teleport, Smoke Holder, and soft-negative verdict passed")
