local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local Keres = require("../ghosts/Keres")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local Traffic = createTraffic()
local Verdict = createVerdict({Traffic = Traffic})
local keres = Keres.new({Traffic = Traffic})

Traffic("KillSpeed", {
	baselineKill = {s = 11, v = true},
	afterKill = {{s = 11, v = true}, {s = 9, v = false}, {s = 9, v = true}},
}):SendTo("Keres")
expect(Verdict:Snapshot().Selected[1] == 8,
	"two stable lower post-kill samples should support Keres")

Traffic("KillSpeed", {
	baselineKill = {s = 11, v = true},
	afterKill = {
		{s = 11, v = true}, {s = 9, v = false}, {s = 9, v = true},
		{s = 11, v = false}, {s = 11, v = true},
	},
	completed = true,
}):SendTo("Keres")
expect(Verdict:Snapshot()["ruled-out"][1] == 8,
	"a recovered speed should invalidate a provisional Keres decrease")

Verdict:Reset()
Traffic("KillSpeed", {
	baselineKill = {s = 11, v = true},
	afterKill = {{s = 11, v = true}, {s = 9, v = false}},
	completed = true,
}):SendTo("Keres")
local insufficient = Verdict:Snapshot()
expect(#insufficient.Selected == 0 and #insufficient["ruled-out"] == 0,
	"one lower post-kill sample should not produce a Keres verdict")

Traffic("KillSpeed", {
	baselineKill = {s = 11, v = true},
	afterKill = {{s = 11, v = true}, {s = 9, v = false}, {s = 8, v = true}},
	completed = true,
}):SendTo("Keres")
expect(Verdict:Snapshot()["ruled-out"][1] == 8,
	"an unstable completed decrease should rule out a permanent Keres drop")

Verdict:Reset()
Traffic("KillSpeed", {
	baselineKill = {s = 11, v = true},
	afterKill = {{s = 11, v = true}, {s = 11, v = false}, {s = 11, v = true}},
	completed = true,
}):SendTo("Keres")
expect(Verdict:Snapshot()["ruled-out"][1] == 8,
	"a completed kill section without a speed drop should rule out Keres")

keres:Destroy()
print("keres.spec: permanent post-kill speed decrease passed")
