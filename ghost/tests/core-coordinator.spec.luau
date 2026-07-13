local Events = require("../events")
local Ledger = require("../evidence-ledger")
local Resolver = require("../resolver")
local Coordinator = require("../coordinator")({
	Events = Events,
	EvidenceLedger = Ledger,
	Resolver = Resolver,
})

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local lifecycle = {Started = 0, Reset = 0, Destroyed = 0}
local tracker = {Name = "LifecycleProbe", Category = "Active"}
function tracker:Start() lifecycle.Started = lifecycle.Started + 1 end
function tracker:OnEvent() end
function tracker:Reset() lifecycle.Reset = lifecycle.Reset + 1 end
function tracker:Destroy() lifecycle.Destroyed = lifecycle.Destroyed + 1 end
function tracker:Snapshot() return lifecycle end

local observerResets = 0
local profile = {
	Name = "TestGhost",
	CreateObserver = function(api)
		return {
			OnEvent = function(_, event)
				if event.Type == "Support" then
					api:Record("TestGhost", event)
					api:Positive("TestGhost", "supported", 90, event)
				elseif event.Type == "Oppose" then
					api:Negative("TestGhost", "opposed", 80, event)
				end
			end,
			Reset = function() observerResets = observerResets + 1 end,
			Snapshot = function() return {Resets = observerResets} end,
			Destroy = function() end,
		}
	end,
}

local changed = {}
local coordinator = Coordinator.new({
	Definitions = {profile},
	Trackers = {tracker},
	OnChanged = function(kind) table.insert(changed, kind) end,
})
coordinator:Start({})
expect(lifecycle.Started == 1, "active tracker should start once")

coordinator:Emit({Type = "Support", Source = "test"})
coordinator:Emit({Type = "Oppose", Source = "test"})
local state = coordinator:Resolve({"TestGhost"}).TestGhost
expect(state.Conflicted == true, "coordinator should expose ledger conflicts without silently clearing support")
expect(#coordinator:Snapshot().Events == 2, "coordinator should retain normalized round event history")
expect(#changed >= 4, "OnChanged should observe evidence and event mutations")

for index = 1, 600 do
	coordinator:Emit({Type = Events.Types.Tick, Time = index})
end
expect(#coordinator:Snapshot().Events == 2, "transient ticks must not grow history or trigger UI event churn")

coordinator:Reset()
expect(lifecycle.Reset == 1 and lifecycle.Started == 2, "round reset should reset and restart active tracker lifecycles")
expect(observerResets == 1, "round reset should reset every profile observer")
expect(#coordinator:Ledger():Entries() == 0, "round reset should clear all prior evidence")
expect(#coordinator:Snapshot().Events == 0, "round reset should clear event history")

coordinator:Destroy()
expect(lifecycle.Destroyed == 1 and coordinator.Status == "Destroyed", "destroy should clean up trackers exactly once")

print("core-coordinator.spec: observer API, changes, conflicts, lifecycle, and cleanup passed")
