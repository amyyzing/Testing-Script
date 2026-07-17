local createTeleportLoop = require("../teleport-loop")

local queued
local environment = {}
local loop = createTeleportLoop({
	Environment = environment,
	LoaderUrl = "https://example.test/logic.luau",
	QueueOnTeleport = function(source) queued = source end,
})

assert(not loop:Queue("AttemptStart"), "disabled loop should not queue")
loop:SetEnabled(true)
assert(loop:Queue("AttemptStart"), "enabled loop should queue")
assert(queued:find('Context = "AttemptStart"', 1, true), "context was not handed off")
assert(queued:find("task.wait(4)", 1, true), "queued execution must wait four seconds")
assert(queued:find("DemonologyLoopEnabled", 1, true), "queued source must remain cancellable")

print("teleport-loop.spec: cancellable four-second cross-place handoff passed")
