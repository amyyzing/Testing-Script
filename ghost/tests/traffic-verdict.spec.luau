local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local Aswang = require("../ghosts/Aswang")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local Traffic = createTraffic()
local Verdict = createVerdict({Traffic = Traffic})
local aswang = Aswang.new({Traffic = Traffic})

Traffic("SaltSpeed", {
	saltState = "disturbed",
	beforeSalt = {{s = 11, v = true}, {s = 11, v = false}},
	afterSalt = {{s = 11, v = false}, {s = 9, v = true}, {s = 11, v = false}},
}):SendTo("Aswang")
expect(Verdict:Snapshot().Selected[1] == 1, "hunting salt slowdown and recovery should select Aswang")

Verdict:Reset()
Traffic("SaltSpeed", {
	saltState = "disturbed",
	beforeSalt = {
		{s = 22, v = true}, {s = 22, v = false},
		{s = 16.5, v = true}, {s = 16.5, v = false},
	},
	afterSalt = {{s = 16.5, v = true}, {s = 16.5, v = false}},
	completed = true,
}):SendTo("Aswang")
expect(Verdict:Snapshot().Selected[1] == 1,
	"a clear salt slowdown should select Aswang even when the hunt ends before recovery")

Verdict:Reset()
Traffic("SaltSpeed", {
	saltState = "disturbed",
	beforeSalt = {{s = 11, v = true}},
	afterSalt = {{s = 11, v = true}, {s = 9, v = false}},
	completed = true,
}):SendTo("Aswang")
local noRecovery = Verdict:Snapshot()
expect(#noRecovery.Selected == 0 and #noRecovery["ruled-out"] == 0,
	"an unmatched visibility sample should not produce a salt verdict")

Verdict:Reset()
Traffic("KillSpeed", {
	beforeKill = {{s = 11, v = true}, {s = 11, v = false}},
	afterKill = {{s = 11, v = false}, {s = 12, v = true}, {s = 12, v = false}},
}):SendTo("Aswang")
expect(Verdict:Snapshot().Selected[1] == 1, "two stable higher kill samples should select Aswang")

Verdict:Reset()
Traffic("KillSpeed", {
	baselineKill = {s = 22, v = false},
	beforeKill = {{s = 22, v = false}, {s = 24, v = false}, {s = 24, v = false}},
	afterKill = {{s = 24, v = false}, {s = 24, v = false}, {s = 24, v = false}},
}):SendTo("Aswang")
expect(Verdict:Snapshot().Selected[1] == 1,
	"a pre-signal speed rise should compare against the retained kill baseline")

Verdict:Reset()
Traffic("SaltSpeed", {
	saltState = "disturbed",
	beforeSalt = {{s = 11, v = true}, {s = 11, v = false}},
	afterSalt = {{s = 11, v = true}, {s = 11, v = false}},
	completed = true,
}):SendTo("Aswang")
expect(Verdict:Snapshot()["ruled-out"][1] == 1,
	"completed salt section with no slowdown should rule Aswang out")

Verdict:Reset()
Traffic("KillSpeed", {
	beforeKill = {{s = 11, v = true}},
	afterKill = {{s = 11, v = true}, {s = 11, v = false}, {s = 11, v = true}},
	completed = true,
}):SendTo("Aswang")
expect(Verdict:Snapshot()["ruled-out"][1] == 1,
	"completed kill section with no increase should rule Aswang out")

Verdict:Reset()
Traffic("KillSpeed", {
	beforeKill = {{s = 11, v = true}},
	afterKill = {{s = 11, v = true}, {s = 12, v = false}},
	completed = true,
}):SendTo("Aswang")
local insufficient = Verdict:Snapshot()
expect(#insufficient.Selected == 0 and #insufficient["ruled-out"] == 0,
	"insufficient post-kill samples should not produce a verdict")

aswang:Destroy()
print("traffic-verdict.spec: Aswang salt and kill verdicts passed")
