local Events = require("../events")
local SpecterTrial = require("../trackers/dormant/specter-trial")({Events = Events})

local function expect(condition, message)
	if not condition then error(message, 2) end
end

local function harness()
	local state = {
		Now = 0,
		Hunting = false,
		Favourite = "Library",
		Current = "Library",
		Speed = 0,
	}
	local emitted = {}
	local tracker = SpecterTrial.new()
	tracker:Start({
		Clock = function() return state.Now end,
		ReadHunting = function() return state.Hunting end,
		ReadFavouriteRoom = function() return state.Favourite end,
		ReadPhysicalCurrentRoom = function() return state.Current end,
		ReadGhostMovementSpeed = function() return state.Speed end,
		Emit = function(event) table.insert(emitted, event) end,
	})
	local function tick(time)
		state.Now = time
		tracker:OnEvent({
			Type = Events.Types.Tick,
			Time = time,
			Hunting = state.Hunting,
		})
	end
	local function settle(fromTime, throughTime)
		local time = fromTime
		while time <= throughTime + 1e-6 do
			tick(time)
			time = time + 0.2
		end
	end
	return state, emitted, tracker, tick, settle
end

-- Five stationary seconds in the unchanged favourite room arm one trial. The
-- next hunt start completes that same TrialId as Residence.
do
	local state, emitted, tracker, _, settle = harness()
	settle(0, 5)
	expect(tracker:Snapshot().Armed == true,
		"five settled seconds must arm the Specter residence trial")
	local trialId = tracker:Snapshot().ActiveTrialId
	state.Hunting = true
	tracker:OnEvent({
		Type = Events.Types.HuntStarted,
		Hunting = true,
		Time = 5.1,
	})
	expect(#emitted == 1
		and emitted[1].Type == Events.Types.SpecterTrial
		and emitted[1].Payload.TrialId == trialId
		and emitted[1].Payload.Outcome == "Residence"
		and emitted[1].Payload.ArmedSeconds >= 5,
		"hunt start after an armed unchanged-room trial must emit Residence")
	expect(tracker:Snapshot().Armed == false,
		"hunt start must consume the armed trial")
	tracker:Destroy()
end

-- Leaving the unchanged favourite room after arming consumes the TrialId as a
-- Departure, and a later hunt cannot emit a second outcome for it.
do
	local state, emitted, tracker, tick, settle = harness()
	settle(0, 5)
	local trialId = tracker:Snapshot().ActiveTrialId
	state.Current = "Hall"
	tick(5.2)
	expect(#emitted == 1
		and emitted[1].Payload.TrialId == trialId
		and emitted[1].Payload.Outcome == "Departure",
		"leaving the favourite room after arming must emit one Departure")
	state.Hunting = true
	tracker:OnEvent({Type = Events.Types.HuntStarted, Hunting = true, Time = 5.3})
	expect(#emitted == 1,
		"one Specter TrialId must never terminate as both Departure and Residence")
	tracker:Destroy()
end

-- A favourite-room change discards the old candidate, waits for two settled
-- seconds in the new room, then starts a fresh five-second arm window.
do
	local state, emitted, tracker, tick, settle = harness()
	settle(0, 1)
	state.Favourite = "Study"
	state.Current = "Study"
	tick(1.2)
	expect(tracker:Snapshot().RoomChangePaused == true,
		"a favourite-room change must pause the trial")
	settle(1.4, 3.2)
	expect(tracker:Snapshot().Armed == false,
		"the two-second room-change settle period must not count toward arming")
	settle(3.4, 8.2)
	expect(tracker:Snapshot().Armed == true,
		"a fresh five-second window after room-change settlement must arm")
	state.Hunting = true
	tracker:OnEvent({Type = Events.Types.HuntStarted, Hunting = true, Time = 8.3})
	expect(#emitted == 1 and emitted[1].Payload.Outcome == "Residence",
		"the post-settle trial must complete normally")
	tracker:Destroy()
end

-- A hunt before the five-second arm boundary is inconclusive.
do
	local state, emitted, tracker, _, settle = harness()
	settle(0, 4.8)
	state.Hunting = true
	tracker:OnEvent({Type = Events.Types.HuntStarted, Hunting = true, Time = 4.9})
	expect(#emitted == 0,
		"an unarmed pre-five-second hunt must not score or rule out Specter")
	tracker:Destroy()
end

-- The hunt transition itself must re-read the room and movement. A heartbeat
-- can occur just before the ghost departs, so stale armed state cannot be
-- converted into a contradictory Residence result.
do
	local state, emitted, tracker, _, settle = harness()
	settle(0, 5)
	state.Current = "Hall"
	state.Hunting = true
	tracker:OnEvent({Type = Events.Types.HuntStarted, Hunting = true, Time = 5.01})
	expect(#emitted == 1 and emitted[1].Payload.Outcome == "Departure",
		"a last-moment room departure must not emit Specter residence")
	tracker:Destroy()
end

do
	local state, emitted, tracker, _, settle = harness()
	settle(0, 5)
	state.Speed = 1
	state.Hunting = true
	tracker:OnEvent({Type = Events.Types.HuntStarted, Hunting = true, Time = 5.01})
	expect(#emitted == 1 and emitted[1].Payload.Outcome == "Departure",
		"last-moment movement must not emit Specter residence")
	tracker:Destroy()
end

do
	local state, emitted, tracker, _, settle = harness()
	settle(0, 5)
	state.Favourite = "Study"
	state.Current = "Study"
	state.Hunting = true
	tracker:OnEvent({Type = Events.Types.HuntStarted, Hunting = true, Time = 5.01})
	expect(#emitted == 0,
		"a favourite-room change at hunt start must discard the old trial")
	tracker:Destroy()
end

print("core-specter-trial.spec: Specter arming, room change, and terminal outcomes passed")
