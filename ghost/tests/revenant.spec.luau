local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local Revenant = require("../ghosts/Revenant")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function harness()
	local now = 0
	local delayed = {}
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local revenant = Revenant.new({
		Traffic = Traffic,
		Clock = function() return now end,
		Delay = function(seconds, callback)
			table.insert(delayed, {Seconds = seconds, Callback = callback})
		end,
	})
	return {
		Traffic = Traffic,
		Verdict = Verdict,
		Revenant = revenant,
		Delayed = delayed,
		SetTime = function(value) now = value end,
	}
end

local positive = harness()
positive.Traffic("HuntingState", {Hunting = true, Time = 0}):SendTo("Revenant")
positive.Traffic("PlayerKilled", {AliveRemaining = 1, Time = 0.2}):SendTo("Revenant")
expect(positive.Delayed[1].Seconds == 1.5,
	"a hunting player kill should start the 1.5-second continuation probe")
positive.Traffic("HuntingState", {Hunting = false, Time = 1}):SendTo("Revenant")
positive.Delayed[1].Callback()
expect(positive.Verdict.Selected[1] == 14 and positive.Verdict.Confidence[14] == 50,
	"hunt stop after a kill should provide Maybe support only")
positive.Revenant:Destroy()

local negative = harness()
negative.Traffic("HuntingState", {Hunting = true, Time = 0}):SendTo("Revenant")
negative.Traffic("PlayerKilled", {AliveRemaining = 1, Time = 0.1}):SendTo("Revenant")
negative.SetTime(1.6)
negative.Delayed[1].Callback()
expect(not table.find(negative.Verdict.RuledOut, 14) and negative.Verdict.Confidence[14] == nil,
	"hunt continuation must stay inconclusive while setting effects are unverified")
negative.Revenant:Destroy()

local laterStop = harness()
laterStop.Traffic("HuntingState", {Hunting = true, Time = 0}):SendTo("Revenant")
laterStop.Traffic("PlayerKilled", {AliveRemaining = 1, Time = 0.1}):SendTo("Revenant")
laterStop.Traffic("HuntingState", {Hunting = false, Time = 1.3}):SendTo("Revenant")
laterStop.Delayed[1].Callback()
expect(laterStop.Verdict.Selected[1] == 14,
	"any observed hunt stop after the tracked kill should support Revenant")
laterStop.Revenant:Destroy()

local reversed = harness()
reversed.Traffic("HuntingState", {Hunting = true, Time = 0}):SendTo("Revenant")
reversed.Traffic("HuntingState", {Hunting = false, Time = 0.5}):SendTo("Revenant")
reversed.Traffic("PlayerKilled", {AliveRemaining = 1, Time = 0.52}):SendTo("Revenant")
reversed.Delayed[1].Callback()
expect(reversed.Verdict.Selected[1] == 14,
	"a kill signal arriving just after hunt-end should still support Revenant")
reversed.Revenant:Destroy()

local ignored = harness()
ignored.Traffic("PlayerKilled", {AliveRemaining = 1, Time = 0.1}):SendTo("Revenant")
expect(#ignored.Delayed == 0 and #ignored.Verdict.Selected == 0
	and #ignored.Verdict.RuledOut == 0,
	"a player death unrelated to a hunt must not produce a Revenant verdict")
ignored.Revenant:Destroy()

for _,endFirst in ipairs({false, true}) do
 local last = harness()
 last.Traffic("HuntingState", {Hunting = true, Time = 0}):SendTo("Revenant")
 if endFirst then last.Traffic("HuntingState", {Hunting = false, Time = 1}):SendTo("Revenant") end
 last.Traffic("PlayerKilled", {AliveRemaining = 0, Time = 1.01}):SendTo("Revenant")
 if not endFirst then last.Traffic("HuntingState", {Hunting = false, Time = 1.02}):SendTo("Revenant") end
 expect(#last.Verdict.Selected == 0 and #last.Verdict.RuledOut == 0 and #last.Delayed == 0,
  "a last-survivor death cannot distinguish Revenant from a round ending")
 last.Revenant:Destroy()
end

local finalKill = harness()
finalKill.Traffic("HuntingState", {Hunting = true, Time = 0}):SendTo("Revenant")
finalKill.Traffic("PlayerKilled", {AliveRemaining = 1, Time = .1}):SendTo("Revenant")
finalKill.Traffic("HuntingState", {Hunting = false, Time = .2}):SendTo("Revenant")
finalKill.Traffic("PlayerKilled", {AliveRemaining = 0, Time = .21}):SendTo("Revenant")
finalKill.Delayed[1].Callback()
expect(#finalKill.Verdict.Selected == 0 and #finalKill.Verdict.RuledOut == 0,
 "a last-survivor notification must cancel a pending probe before attribution")
finalKill.Revenant:Destroy()

local unknown = harness()
unknown.Traffic("HuntingState", {Hunting = true, Time = 0}):SendTo("Revenant")
unknown.Traffic("PlayerKilled", {Time = .1}):SendTo("Revenant")
unknown.Traffic("HuntingState", {Hunting = false, Time = .2}):SendTo("Revenant")
expect(#unknown.Delayed == 0 and #unknown.Verdict.Selected == 0,
 "a kill with unknown survivors must stay inconclusive")
unknown.Revenant:Destroy()

print("revenant.spec: kill and hunt-state timing correlation passed")
