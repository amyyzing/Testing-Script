local Events = require("../events")
local Specification = require("../specification")
local BrokenGlass = require("../trackers/dormant/broken-glass")({
	Events = Events,
	Specification = Specification,
})

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function glass(name)
	return {
		Name = name or "BrokenGlass",
		IsA = function(_, className) return className == "Model" end,
	}
end

local function countType(events, kind)
	local count = 0
	for _, event in ipairs(events) do
		if event.Type == kind then count = count + 1 end
	end
	return count
end

-- Only distinct, newly observed BrokenGlass Models form the rolling burst.
do
	local now = 0
	local emitted = {}
	local tracker = BrokenGlass.new()
	tracker:Start({
		Clock = function() return now end,
		Emit = function(event) table.insert(emitted, event) end,
	})
	local first, second = glass(), glass()
	tracker:OnEvent({Type = "BrokenGlassAdded", Model = first, Time = 0})
	tracker:OnEvent({Type = "BrokenGlassAdded", Model = first, Time = 1})
	tracker:OnEvent({Type = "BrokenGlassAdded", Model = glass("NotBrokenGlass"), Time = 2})
	expect(#emitted == 0, "duplicates and unrelated Models must not satisfy Banshee")
	tracker:OnEvent({Type = "BrokenGlassAdded", Model = second, Time = 5})
	expect(countType(emitted, Events.Types.BrokenGlassBurst) == 1,
		"two distinct new glass Models at the inclusive five-second boundary must emit once")
	local burst = emitted[1]
	expect(burst.Payload.Qualified == true and burst.Payload.Count == 2
		and burst.Payload.Duration == 5,
		"the Banshee burst must preserve its exact count and duration")
	tracker:OnEvent({Type = "BrokenGlassAdded", Model = glass(), Time = 5})
	expect(#emitted == 1, "one still-active rolling burst must not spam observations")

	-- Once the old burst ages out, the tracker rearms for a later independent one.
	now = 11
	tracker:OnEvent({Type = Events.Types.Tick, Time = now})
	tracker:OnEvent({Type = "BrokenGlassAdded", Model = glass(), Time = 11})
	tracker:OnEvent({Type = "BrokenGlassAdded", Model = glass(), Time = 15.9})
	expect(#emitted == 2 and tracker:Snapshot().BurstCount == 2,
		"an expired burst must rearm without repeating the previous finding")

	tracker:Stop()
	expect(tracker:OnEvent({Type = "BrokenGlassAdded", Model = glass(), Time = 16}) == false,
		"a stopped tracker must ignore input")
	tracker:Start({Clock = function() return now end, Emit = function(event) table.insert(emitted, event) end})
	expect(tracker:Snapshot().Status == "Dormant",
		"Start after Stop must rebuild the lifecycle instead of retaining stale bindings")
	tracker:Destroy()
end

print("core-broken-glass.spec: distinct rolling Banshee bursts passed")
