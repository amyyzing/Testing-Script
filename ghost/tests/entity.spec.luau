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

local function smokeAt(x, name)
	return {Name = name or "SmokeHolder", Position = {X = x, Y = 0, Z = 0},
		IsA = function(_, class) return class == "BasePart" end}
end

local now = 0
local heartbeat, descendantAdded = signal(), signal()
local item = {Current = {X = 0, Y = 0, Z = 0}}
function item:IsA(class) return class == "Model" end
function item:GetPivot() return {Position = self.Current} end
local itemScans = 0
local items = {ChildAdded = signal(), ChildRemoved = signal()}
function items:GetChildren()
	itemScans += 1
	return {item}
end
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
	FindRoom = function(point) return point.X < 10 and "RoomA" or "RoomB" end,
})

item.Current = {X = 25, Y = 0, Z = 0}
now = 0.4
heartbeat:Fire(0.4)
expect(#teleports == 1 and teleports[1].Distance == 25,
	"a qualifying position jump should emit regardless of calculated speed")
expect(teleports[1].FromRoom == "RoomA" and teleports[1].ToRoom == "RoomB",
	"a teleport must cross between two known room bounding boxes")
local firstDelay = table.remove(delayed, 1)
expect(firstDelay.Seconds == 3, "Entity should wait three seconds for its Smoke Holder")
firstDelay.Callback()
expect(Verdict.NegativeConfidence[6] == 50 and not table.find(Verdict.RuledOut, 6),
	"a smoke-free teleport should be a 50% Entity negative, not a rule-out")
expect(#Verdict.Selected == 0, "a soft negative alone must not select Entity")

Verdict:Reset()
item.Current = {X = 0, Y = 0, Z = 0}
now = 0.8
heartbeat:Fire(0.4)
local smoke = smokeAt(25, "Smoke Holder")
World.Smoke = smoke
descendantAdded:Fire(smoke)
expect((Verdict.Confidence[6] == 65 and Verdict.SourceConfidence[6] == 99) and Verdict.Selected[1] == 6,
	"a teleport followed by a Smoke Holder should support and select Entity")
if delayed[1] then table.remove(delayed, 1).Callback() end
expect((Verdict.Confidence[6] == 65 and Verdict.SourceConfidence[6] == 99),
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
item.Current = {X = 0, Y = 0, Z = 0}
now = 4.6
heartbeat:Fire(0.4)
expect(#teleports == 3 and delayed[1], "a later teleport should begin another smoke probe")
World.Smoke = smokeAt(120)
table.remove(delayed, 1).Callback()
expect((Verdict.Confidence[6] == 65 and Verdict.SourceConfidence[6] == 99) and not Verdict.NegativeConfidence[6],
	"the final recursive scan should find a Smoke Holder even without DescendantAdded")

item.Current = {X = -30, Y = 0, Z = 0}
now = 5
heartbeat:Fire(0.4)
expect(#teleports == 3,
	"a large movement that remains inside the same room must not count as a teleport")
expect(itemScans == 1,
	"the item container should be indexed once instead of rescanned on every sample")

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

-- Observations must survive without another script retaining their Lua values.
local retentionNow, retainedTeleports = 0, 0
local retentionHeartbeat = signal()
local retentionTraffic = createTraffic()
retentionTraffic:Receive("SmokeHolder", function(name)
	if name == "ItemTeleported" then retainedTeleports += 1 end
end)
local function streamedItem()
	return {
		Current = {X = 0, Y = 0, Z = 0},
		IsA = function(_, class) return class == "Model" end,
		GetPivot = function(self) return {Position = self.Current} end,
	}
end
local retentionWorld = {FindFirstChild = function(_, name)
	if name ~= "Items" then return nil end
	return {
		ChildAdded = signal(), ChildRemoved = signal(),
		GetChildren = function() return {streamedItem()} end,
	}
end}
local retained = createItemTeleport({
	Traffic = retentionTraffic, Workspace = retentionWorld,
	RunService = {Heartbeat = retentionHeartbeat},
	Clock = function() return retentionNow end,
	FindRoom = function(point) return point.X < 10 and "RoomA" or "RoomB" end,
})
collectgarbage("collect")
local retainedContainer = next(retained.BoundContainers)
local retainedItem = next(retained.Objects)
expect(retainedContainer and retainedItem,
	"observed containers and items must survive collection without unrelated Lua owners")
retainedItem.Current = {X = 30, Y = 0, Z = 0}
retentionNow = 0.4
retentionHeartbeat:Fire(0.4)
expect(retainedTeleports == 1, "a retained streamed item must still report its teleport")
retainedContainer.ChildRemoved:Fire(retainedItem)
expect(not retained.Objects[retainedItem] and not retained.Previous[retainedItem],
	"removing an item must release its observation and position history")
retainedItem = nil
retainedContainer.ChildAdded:Fire(streamedItem())
collectgarbage("collect")
retainedItem = next(retained.Objects)
expect(retainedItem, "newly streamed items must also survive collection before sampling")
retentionNow = 0.8
retentionHeartbeat:Fire(0.4)
retainedItem.Current = {X = 30, Y = 0, Z = 0}
retentionNow = 1.2
retentionHeartbeat:Fire(0.4)
expect(retainedTeleports == 2, "new streamed items must retain their next position change")
retained:Destroy()
expect(next(retained.Objects) == nil and next(retained.BoundContainers) == nil,
	"destroying the tracker must release retained instances")
print("entity.spec: streamed observation survives GC and releases on removal")

local function relocationHarness(roomAt)
	local state = {Now = 0, Delayed = {}}
	local frame, added = signal(), signal()
	local object = streamedItem()
	local container = {ChildAdded = signal(), ChildRemoved = signal(), GetChildren = function() return {object} end}
	local world = {DescendantAdded = added}
	function world:FindFirstChild(name)
		if name == "Items" then return container end
		if self.Smoke and name == self.Smoke.Name then return self.Smoke end
	end
	local traffic = createTraffic()
	state.Verdict = createVerdict({Traffic = traffic})
	local processor = Entity.new({Traffic = traffic})
	local smokeObserver = createSmokeHolder({Traffic = traffic, Workspace = world,
		Clock = function() return state.Now end,
		Delay = function(_, callback) table.insert(state.Delayed, callback) end})
	local motion = createItemTeleport({Traffic = traffic, Workspace = world,
		RunService = {Heartbeat = frame}, Clock = function() return state.Now end,
		FindRoom = roomAt or function() return "Blue Bedroom" end})
	function state:Move(x, time)
		self.Now, object.Current = time, {X = x, Y = 0, Z = 0}
		frame:Fire(0.4)
	end
	function state:Smoke(x, time)
		self.Now, world.Smoke = time, smokeAt(x)
		added:Fire(world.Smoke)
	end
	function state:Finish(time)
		self.Now = time
		for _, callback in ipairs(self.Delayed) do callback() end
		table.clear(self.Delayed)
	end
	function state:Destroy() motion:Destroy() smokeObserver:Destroy() processor:Destroy() end
	return state
end

local short = relocationHarness()
short:Move(14.58278465, 0.4)
short:Smoke(0, 0.5)
expect((short.Verdict.Confidence[6] == 65 and short.Verdict.SourceConfidence[6] == 99),
	"the native 14.6-stud same-room relocation must qualify with smoke at its departure point")
short:Destroy()

local reversed = relocationHarness()
reversed:Smoke(0, 0.2)
reversed:Move(14.6, 0.4)
expect((reversed.Verdict.Confidence[6] == 65 and reversed.Verdict.SourceConfidence[6] == 99), "smoke arriving before the replicated movement must also qualify")
reversed:Destroy()

local unmapped = relocationHarness(function(point) return point.X > 10 and "Garage" or nil end)
unmapped:Move(72.12242648, 0.4)
unmapped:Smoke(0, 0.5)
expect((unmapped.Verdict.Confidence[6] == 65 and unmapped.Verdict.SourceConfidence[6] == 99),
	"matching native origin smoke must qualify when the departure room is unmapped")
unmapped:Destroy()

local unrelated = relocationHarness()
unrelated:Smoke(100, 0.2)
unrelated:Move(14.6, 0.4)
unrelated:Finish(4)
expect(not unrelated.Verdict.Confidence[6] and not unrelated.Verdict.NegativeConfidence[6],
	"ordinary short movement and unrelated smoke must stay inconclusive")
unrelated:Destroy()

local expired = relocationHarness()
expired:Move(14.6, 0.4)
expired:Smoke(0, 4)
expect(not expired.Verdict.Confidence[6], "late smoke must not corroborate an expired movement")
expired:Destroy()

local wrongOrigin = relocationHarness(function(point) return point.X < 10 and "RoomA" or "RoomB" end)
wrongOrigin:Move(30, 0.4)
wrongOrigin:Smoke(100, 0.5)
wrongOrigin:Finish(3.4)
expect(not wrongOrigin.Verdict.Confidence[6] and wrongOrigin.Verdict.NegativeConfidence[6] == 50,
	"even a large cross-room movement needs smoke at the matching departure point")
wrongOrigin:Destroy()

local corrected = relocationHarness(function(point) return point.X < 10 and "RoomA" or "RoomB" end)
corrected:Move(30, 0.4)
corrected:Finish(3.4)
expect(corrected.Verdict.NegativeConfidence[6] == 50, "an initial unmatched long jump remains a soft negative")
corrected:Move(30, 3.4)
corrected:Move(0, 3.8)
corrected:Smoke(30, 3.9)
corrected.Verdict:Support("Aswang", 60, "comparison candidate")
expect(corrected.Verdict.Selected[1] == 6,
	"a matching native smoke signature must supersede earlier smoke-free movement")
corrected:Move(0, 4)
corrected:Move(30, 4.4)
corrected:Finish(7.4)
expect(corrected.Verdict.Selected[1] == 6,
	"later ordinary smoke-free movement must not undo an already confirmed signature")
corrected:Destroy()
print("entity.spec: native short relocation and spatial/temporal smoke checks passed")
