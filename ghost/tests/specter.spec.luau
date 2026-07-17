local createTraffic = require("../traffic")
local createVerdict = require("../verdict")
local createSpecterTrial = require("../dormant-trackers/specter-trial")
local Specter = require("../ghosts/Specter")

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function signal()
	local callbacks = {}
	return {
		Connect = function(_, callback)
			table.insert(callbacks, callback)
			return {Disconnect = function()
				local index = table.find(callbacks, callback)
				if index then table.remove(callbacks, index) end
			end}
		end,
		Fire = function(_, ...)
			for _, callback in ipairs(table.clone(callbacks)) do callback(...) end
		end,
	}
end

local function harness()
	local state = {
		Now = 0,
		Hunting = false,
		Favourite = "Library",
		Current = "Library",
		Position = {X = 0, Y = 0, Z = 0},
	}
	local Ghost = {}
	function Ghost:GetAttribute(name)
		if name == "Hunting" then return state.Hunting end
		if name == "FavoriteRoom" then return state.Favourite end
		if name == "CurrentRoom" then return state.Current end
	end
	local heartbeat = signal()
	local Traffic = createTraffic()
	local Verdict = createVerdict({Traffic = Traffic})
	local specter = Specter.new({Traffic = Traffic})
	local tracker = createSpecterTrial({
		Traffic = Traffic,
		Ghost = Ghost,
		RunService = {Heartbeat = heartbeat},
		Clock = function() return state.Now end,
		Position = function() return state.Position end,
		ReadCurrentRoom = function() return state.Current end,
	})
	local result = {
		State = state,
		Traffic = Traffic,
		Verdict = Verdict,
		Specter = specter,
		Tracker = tracker,
	}
	function result:Step(duration, distance)
		state.Now += duration
		state.Position = {
			X = state.Position.X + (distance or 0),
			Y = state.Position.Y,
			Z = state.Position.Z,
		}
		heartbeat:Fire(duration)
	end
	function result:Settle(duration)
		for _ = 1, math.floor(duration / 0.1 + 0.5) do self:Step(0.1) end
	end
	function result:SetHunting(hunting)
		state.Now += 0.1
		state.Hunting = hunting
		Traffic:Broadcast("HuntingState", {Hunting = hunting, Time = state.Now})
	end
	function result:Destroy()
		tracker:Destroy()
		specter:Destroy()
	end
	return result
end

local residence = harness()
residence:Settle(5.2)
expect(residence.Tracker.Armed,
	"five stationary seconds in the unchanged favourite room should arm Specter")
residence:SetHunting(true)
expect(residence.Verdict.Confidence[18] == 35 and residence.Verdict.Selected[1] == 18,
	"the first armed residence through hunt start should support Specter at 35 percent")
residence:SetHunting(false)
residence:Settle(5.2)
residence:SetHunting(true)
expect(residence.Verdict.Confidence[18] == 65,
	"a second qualified residence should raise Specter to 65 percent")
residence:Destroy()

local movedAtHunt = harness()
movedAtHunt:Settle(5.2)
movedAtHunt.State.Position = {X = 2, Y = 0, Z = 0}
movedAtHunt:SetHunting(true)
expect(table.find(movedAtHunt.Verdict.RuledOut, 18),
	"last-moment movement after arming must rule out Specter instead of using stale stationary data")
movedAtHunt:Destroy()

local movedBeforeHunt = harness()
movedBeforeHunt:Settle(5.2)
for _ = 1, 5 do movedBeforeHunt:Step(0.1, 1) end
expect(table.find(movedBeforeHunt.Verdict.RuledOut, 18),
	"sustained movement after arming but before a hunt should rule out Specter")
movedBeforeHunt:Destroy()

local earlyHunt = harness()
earlyHunt:Settle(4.5)
earlyHunt:SetHunting(true)
expect(earlyHunt.Verdict.Confidence[18] == nil
	and not table.find(earlyHunt.Verdict.RuledOut, 18),
	"a hunt before the five-second arm point should be inconclusive")
earlyHunt:Destroy()

local changedAtHunt = harness()
changedAtHunt:Settle(5.2)
changedAtHunt.State.Favourite = "Study"
changedAtHunt.State.Current = "Study"
changedAtHunt:SetHunting(true)
expect(changedAtHunt.Verdict.Confidence[18] == nil
	and not table.find(changedAtHunt.Verdict.RuledOut, 18),
	"a favourite-room change at hunt start should discard the old trial")
changedAtHunt:Destroy()

local roomChanged = harness()
roomChanged:Settle(1)
roomChanged.State.Favourite = "Study"
roomChanged.State.Current = "Study"
roomChanged:Settle(6.8)
expect(not roomChanged.Tracker.Armed,
	"a favourite-room change should discard old time and require two settled seconds first")
roomChanged:Settle(0.5)
expect(roomChanged.Tracker.Armed,
	"five fresh stationary seconds after the two-second room settle should arm Specter")
roomChanged:SetHunting(true)
expect(roomChanged.Verdict.Confidence[18] == 35,
	"the fresh unchanged-room trial should complete normally")
roomChanged:Destroy()

print("specter.spec: legacy stationary favourite-room trials passed")
