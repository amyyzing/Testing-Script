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
positive.Traffic("PlayerKilled", {Time = 0.2}):SendTo("Revenant")
expect(positive.Delayed[1].Seconds == 1.5,
	"a hunting player kill should start the 1.5-second continuation probe")
positive.Traffic("HuntingState", {Hunting = false, Time = 1}):SendTo("Revenant")
expect(positive.Verdict.Selected[1] == 14 and positive.Verdict.Confidence[14] == 99,
	"hunt stop after a kill should support Revenant")
positive.Revenant:Destroy()

local negative = harness()
negative.Traffic("HuntingState", {Hunting = true, Time = 0}):SendTo("Revenant")
negative.Traffic("PlayerKilled", {Time = 0.1}):SendTo("Revenant")
negative.SetTime(1.6)
negative.Delayed[1].Callback()
expect(table.find(negative.Verdict.RuledOut, 14),
	"a hunt continuing for 1.5 seconds after a kill should rule out Revenant")
negative.Revenant:Destroy()

local laterStop = harness()
laterStop.Traffic("HuntingState", {Hunting = true, Time = 0}):SendTo("Revenant")
laterStop.Traffic("PlayerKilled", {Time = 0.1}):SendTo("Revenant")
laterStop.Traffic("HuntingState", {Hunting = false, Time = 1.3}):SendTo("Revenant")
expect(laterStop.Verdict.Selected[1] == 14,
	"any observed hunt stop after the tracked kill should support Revenant")
laterStop.Revenant:Destroy()

local reversed = harness()
reversed.Traffic("HuntingState", {Hunting = true, Time = 0}):SendTo("Revenant")
reversed.Traffic("HuntingState", {Hunting = false, Time = 0.5}):SendTo("Revenant")
reversed.Traffic("PlayerKilled", {Time = 0.52}):SendTo("Revenant")
expect(reversed.Verdict.Selected[1] == 14,
	"a kill signal arriving just after hunt-end should still support Revenant")
reversed.Revenant:Destroy()

local ignored = harness()
ignored.Traffic("PlayerKilled", {Time = 0.1}):SendTo("Revenant")
expect(#ignored.Delayed == 0 and #ignored.Verdict.Selected == 0
	and #ignored.Verdict.RuledOut == 0,
	"a player death unrelated to a hunt must not produce a Revenant verdict")
ignored.Revenant:Destroy()

print("revenant.spec: kill and hunt-state timing correlation passed")
