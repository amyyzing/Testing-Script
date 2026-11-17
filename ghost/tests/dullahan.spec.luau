local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local Dullahan = require("../ghosts/Dullahan")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function run(speeds)
	local traffic = createTraffic()
	local verdict = createVerdict({Traffic = traffic})
	local processor = Dullahan.new({Traffic = traffic})
	for index, speed in ipairs(speeds) do
		traffic("GhostSpeedObserved", {Source = "speed", Hunting = true, Time = index * 0.1, Speed = speed}):SendTo("Dullahan")
	end
	processor:Destroy()
	return verdict
end

local ramp = {}
for index = 1, 45 do table.insert(ramp, 21 + index * 0.01) end
expect(run(ramp).Confidence[4] == 95, "repeated tiny increases at the native rate should support Dullahan")

local blink = {}
for index = 1, 80 do table.insert(blink, index % 2 == 0 and 27 or 21) end
expect(run(blink).Confidence[4] == nil, "large alternating Phantom changes must not count as gradual acceleration")

local wrongRate = {}
for index = 1, 80 do table.insert(wrongRate, 21 + index * 0.03) end
expect(run(wrongRate).Confidence[4] == nil, "an unrelated drift rate must stay inconclusive")

local flat = {}
for index = 1, 80 do table.insert(flat, 21) end
expect(run(flat).Confidence[4] == nil, "flat speed must not support Dullahan")

print("dullahan.spec: timed micro-increments, alternate speed and drift rejection passed")

local duplicates = {}
for index = 1, 45 do
	table.insert(duplicates, 21 + index * 0.02)
	table.insert(duplicates, 21 + index * 0.02)
end
expect(run(duplicates).Confidence[4] == 95, "duplicate property notifications must not reset a real ramp")
