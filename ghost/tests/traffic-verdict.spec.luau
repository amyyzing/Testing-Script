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
	afterSalt = {{s = 11, v = false}, {s = 8.25, v = true}, {s = 11, v = false}},
}):SendTo("Aswang")
expect(Verdict:Snapshot().Selected[1] == 1, "hunting salt slowdown and recovery should select Aswang")

aswang:Destroy()
aswang = Aswang.new({Traffic = Traffic})
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

aswang:Destroy()
aswang = Aswang.new({Traffic = Traffic})
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

aswang:Destroy()
aswang = Aswang.new({Traffic = Traffic})
Verdict:Reset()
Traffic("KillSpeed", {
	beforeKill = {{s = 11, v = true}, {s = 11, v = false}},
	afterKill = {{s = 11, v = false}, {s = 12, v = true}, {s = 12, v = false}},
}):SendTo("Aswang")
expect(Verdict:Snapshot().Selected[1] == 1, "two stable higher kill samples should select Aswang")

aswang:Destroy()
aswang = Aswang.new({Traffic = Traffic})
Verdict:Reset()
Traffic("KillSpeed", {
	baselineKill = {s = 22, v = false},
	beforeKill = {{s = 22, v = false}, {s = 24, v = false}, {s = 24, v = false}},
	afterKill = {{s = 24, v = false}, {s = 24, v = false}, {s = 24, v = false}},
}):SendTo("Aswang")
expect(Verdict.Confidence[1] == nil,
	"a single visibility state cannot confirm a permanent kill-speed increase")

aswang:Destroy()
aswang = Aswang.new({Traffic = Traffic})
Verdict:Reset()
Traffic("SaltSpeed", {
	saltState = "disturbed",
	beforeSalt = {{s = 11, v = true}, {s = 11, v = false}},
	afterSalt = {{s = 11, v = true}, {s = 11, v = false}},
	completed = true,
	Duration = 5,
}):SendTo("Aswang")
expect(Verdict:Snapshot()["ruled-out"][1] == 1,
	"completed salt section with no slowdown should rule Aswang out")

aswang:Destroy()
aswang = Aswang.new({Traffic = Traffic})
Verdict:Reset()
Traffic("KillSpeed", {
	beforeKill = {{s = 11, v = true}, {s = 11, v = false}},
	afterKill = {{s = 11, v = true}, {s = 11, v = false}, {s = 11, v = true}},
	completed = true,
}):SendTo("Aswang")
expect(Verdict:Snapshot()["ruled-out"][1] == 1,
	"completed kill section with no increase should rule Aswang out")

aswang:Destroy()
aswang = Aswang.new({Traffic = Traffic})
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
aswang = Aswang.new({Traffic = Traffic})
Verdict:Reset()
Traffic("KillSpeed", {
	beforeKill = {{s = 21, v = true}, {s = 27, v = false}},
	baselineKill = {s = 21, v = true},
	afterKill = {{s = 21, v = true}, {s = 27, v = false}, {s = 27, v = false}},
}):SendTo("Aswang")
expect(Verdict.Confidence[1] == nil, "a Phantom hidden-speed transition must not confirm Aswang")

aswang:Destroy()
aswang = Aswang.new({Traffic = Traffic})
Verdict:Reset()
Traffic("KillSpeed", {
	beforeKill = {{s = 21, v = true}, {s = 21, v = false}},
	afterKill = {{s = 21, v = true}, {s = 23, v = false}, {s = 23, v = true},
		{s = 21, v = false}, {s = 21, v = true}},
	completed = true,
}):SendTo("Aswang")
expect(table.find(Verdict.RuledOut, 1), "a recovered temporary increase must not remain a permanent kill perk")

aswang:Destroy()

aswang = Aswang.new({Traffic = Traffic})
Verdict:Reset()
Traffic("KillSpeed", {
	baselineKill = {s = 21, v = false},
	beforeKill = {{s = 2, v = true}, {s = 2, v = false},
		{s = 21, v = true}, {s = 21, v = false}},
	afterKill = {{s = 21, v = false}, {s = 21, v = true}, {s = 21, v = false}},
	completed = true,
}):SendTo("Aswang")
expect(Verdict.SourceConfidence[1] == nil and table.find(Verdict.RuledOut, 1),
	"an earlier temporary slowdown cannot masquerade as a permanent post-kill speed increase")
aswang:Destroy()
print("traffic-verdict.spec: Aswang salt and kill verdicts passed")
