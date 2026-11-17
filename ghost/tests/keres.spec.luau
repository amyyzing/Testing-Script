local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createModelGender = require("../discardable-trackers/model-gender")
local Keres = require("../ghosts/Keres")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local Traffic = createTraffic()
local Verdict = createVerdict({Traffic = Traffic})
local keres = Keres.new({Traffic = Traffic})

Traffic("KillSpeed", {
	baselineKill = {s = 11, v = true},
	beforeKill = {{s = 11, v = true}, {s = 11, v = false}},
	afterKill = {{s = 11, v = true}, {s = 9, v = false}, {s = 9, v = true}},
}):SendTo("Keres")
expect(Verdict:Snapshot().Selected[1] == 8,
	"two stable lower post-kill samples should support Keres")

Traffic("KillSpeed", {
	baselineKill = {s = 11, v = true},
	beforeKill = {{s = 11, v = true}, {s = 11, v = false}},
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
	beforeKill = {{s = 21, v = true}, {s = 27, v = false}},
	baselineKill = {s = 27, v = false},
	afterKill = {{s = 27, v = false}, {s = 21, v = true}, {s = 21, v = true}},
}):SendTo("Keres")
expect(Verdict.Confidence[8] == nil, "a Phantom blink slowdown in only one state must not support Keres")

Verdict:Reset()
Traffic("KillSpeed", {
	baselineKill = {s = 11, v = true},
	beforeKill = {{s = 11, v = true}, {s = 11, v = false}},
	afterKill = {{s = 11, v = true}, {s = 9, v = false}},
	completed = true,
}):SendTo("Keres")
local insufficient = Verdict:Snapshot()
expect(#insufficient.Selected == 0 and #insufficient["ruled-out"] == 0,
	"one lower post-kill sample should not produce a Keres verdict")

Traffic("KillSpeed", {
	baselineKill = {s = 11, v = true},
	beforeKill = {{s = 11, v = true}, {s = 11, v = false}},
	afterKill = {{s = 11, v = true}, {s = 9, v = false}, {s = 8, v = true}},
	completed = true,
}):SendTo("Keres")
expect(Verdict.Confidence[8] == 99,
	"a decrease in both visibility states should support Keres even when their absolute speeds differ")

Verdict:Reset()
Traffic("KillSpeed", {
	baselineKill = {s = 11, v = true},
	beforeKill = {{s = 11, v = true}, {s = 11, v = false}},
	afterKill = {{s = 11, v = true}, {s = 11, v = false}, {s = 11, v = true}},
	completed = true,
}):SendTo("Keres")
expect(Verdict:Snapshot()["ruled-out"][1] == 8,
	"a completed kill section without a speed drop should rule out Keres")

Verdict:Reset()
local femaleGhost = {VisualModel = "Watcher"}
function femaleGhost:GetAttribute(name) return self[name] end
createModelGender({Traffic = Traffic, Ghost = femaleGhost})
expect(Verdict.Confidence[8] == 25 and Verdict.Selected[1] == 8,
	"a female VisualModel should weakly support Keres")

Verdict:Reset()
local maleGhost = {VisualModel = "FutureModel"}
function maleGhost:GetAttribute(name) return self[name] end
createModelGender({Traffic = Traffic, Ghost = maleGhost})
expect(not table.find(Verdict.RuledOut, 8) and Verdict.Confidence[8] == nil,
	"an unfamiliar VisualModel must remain unknown instead of defaulting to male")
maleGhost.Gender = "Male"
createModelGender({Traffic = Traffic, Ghost = maleGhost})
expect(table.find(Verdict.RuledOut, 8), "an explicit male Gender should rule out Keres")

keres:Destroy()
print("keres.spec: permanent post-kill speed decrease passed")
