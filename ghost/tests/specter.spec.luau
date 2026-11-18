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
local residenceResult
residence.Traffic:Receive("Verdict", function(signal, payload)
	if signal == "Support" and payload.Ghost == "Specter" then residenceResult = payload end
end)
residence:Settle(5.2)
expect(residence.Tracker.Armed,
	"five stationary seconds in the unchanged favourite room should arm Specter")
residence:SetHunting(true)
expect(residence.Verdict.Confidence[18] == nil,
	"a short residence cannot support Specter")
residence:SetHunting(false)
residence:Settle(5.2)
residence:SetHunting(true)
expect(residence.Verdict.Confidence[18] == nil and residenceResult == nil,
	"short residences separated by hunts must not accumulate support")
residence:Destroy()

local timed = harness()
local supports = 0
timed.Traffic:Receive("Verdict", function(signal, payload)
	if signal == "Support" and payload.Ghost == "Specter" then supports += 1 end
end)
timed:Settle(29.9)
expect(timed.Verdict.Confidence[18] == nil, "residence support must wait for its observation window")
timed:Settle(0.4)
expect(timed.Verdict.Confidence[18] == 35, "30 continuous seconds should provide low support")
timed:Settle(60)
expect(timed.Verdict.Confidence[18] == 60, "90 continuous seconds should provide medium support")
timed.Traffic("Support", {Ghost = "Vex", Confidence = 99, Perk = "Invisible on LIDAR"}):SendTo("Verdict")
expect(timed.Verdict.Confidence[22] == 65 and timed.Verdict.Confidence[18] == 60,
	"weak residence must remain below a strong native signature while Doppelganger fits")
timed.Verdict:RuleOut("Doppelganger", 99, "independent exclusion")
timed:Settle(180)
expect(timed.Verdict.Confidence[18] == 60 and supports == 2,
	"residence must remain medium after repetition and independent Doppelganger exclusion")
expect(timed.Verdict.Confidence[22] == 99,
	"weak residence must not suppress a stronger native signature")
timed.State.Current = "Hallway"
timed:Settle(0.8)
expect(table.find(timed.Verdict.RuledOut, 18) and timed.Verdict.Confidence[18] == nil,
	"one qualified departure must remove all residence support and fully exclude Specter")
timed.State.Current = "Library"
timed:Settle(120)
expect(timed.Verdict.Confidence[18] == nil and supports == 2,
	"later residence cannot resurrect a ruled-out Specter")
timed:Destroy()

local interrupted = harness()
interrupted:Settle(25)
interrupted.State.Current = "Hallway"
interrupted:Settle(0.2)
interrupted.State.Current = "Library"
interrupted:Settle(10)
expect(interrupted.Verdict.Confidence[18] == nil,
	"a boundary interruption must restart the continuous residence window without excluding")
interrupted.State.Current = nil
interrupted:Settle(1)
interrupted.State.Current = "Library"
interrupted:Settle(25)
expect(interrupted.Verdict.Confidence[18] == nil, "unknown-room time must not contribute to residence")
interrupted:Destroy()

local movedAtHunt = harness()
movedAtHunt:Settle(5.2)
movedAtHunt.State.Position = {X = 2, Y = 0, Z = 0}
movedAtHunt:SetHunting(true)
expect(not table.find(movedAtHunt.Verdict.RuledOut, 18),
	"movement at hunt start must not be treated as a non-hunting departure")
movedAtHunt:Destroy()

local movedBeforeHunt = harness()
movedBeforeHunt:Settle(5.2)
for _ = 1, 5 do movedBeforeHunt:Step(0.1, 1) end
expect(not table.find(movedBeforeHunt.Verdict.RuledOut, 18),
	"walking within the favourite room must not rule out Specter")
movedBeforeHunt.State.Current = "Hallway"
movedBeforeHunt:Settle(0.8)
expect(table.find(movedBeforeHunt.Verdict.RuledOut, 18),
	"a sustained known outside-room departure while not hunting must rule out Specter")
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
expect(roomChanged.Verdict.Confidence[18] == nil,
	"a short fresh unchanged-room trial cannot provide positive support")
roomChanged:Destroy()

local unknownRoom = harness()
unknownRoom:Settle(5.2)
unknownRoom.State.Current = nil
unknownRoom:Settle(1)
expect(not table.find(unknownRoom.Verdict.RuledOut, 18), "an unknown room is not an outside-room contradiction")
unknownRoom:Destroy()

local huntingOutside = harness()
huntingOutside:Settle(5.2)
huntingOutside.State.Current = "Hallway"
huntingOutside:SetHunting(true)
huntingOutside:Settle(1)
expect(not table.find(huntingOutside.Verdict.RuledOut, 18), "being outside during a hunt is permitted")
huntingOutside:Destroy()

local boundaryJitter = harness()
boundaryJitter:Settle(5.2)
boundaryJitter.State.Current = "Hallway"
boundaryJitter:Settle(0.2)
boundaryJitter.State.Current = "Library"
boundaryJitter:Settle(0.8)
expect(not table.find(boundaryJitter.Verdict.RuledOut, 18), "a brief boundary sample is not a sustained departure")
boundaryJitter:Destroy()

local delayedHunt = harness()
delayedHunt:Settle(5.2)
delayedHunt.State.Current = "Hallway"
delayedHunt:Settle(0.2)
delayedHunt.State.Hunting = true
delayedHunt:Settle(1)
delayedHunt.State.Hunting = false
delayedHunt:Settle(1)
expect(not table.find(delayedHunt.Verdict.RuledOut, 18),
	"native hunt state must invalidate the old trial even before a traffic notification")
delayedHunt:Destroy()

local catalog = require("../evidence-catalog")
local fallback = catalog.NewTracker()
fallback:RecordDetection("Specter", "Stayed in favourite room")
expect(fallback.Detections.Specter.Confidence == 0,
	"unqualified catalog defaults must not bypass timed residence checks")

print("specter.spec: residence stays low-to-medium and qualified departure excludes")
