local SOURCE = "https://demonology.fandom.com/wiki/Revenant"
local MIN_HUNT_AGE = 0.5
local CONTINUED_AFTER = 1
local MAX_PENDING_AGE = 2.5

local function copyPending(pending)
	if type(pending) ~= "table" then
		return nil
	end
	local copy = {}
	for key, value in pairs(pending) do
		copy[key] = value
	end
	return copy
end

local function createObserver(api)
	local state = {
		LastStopped = nil,
		LastReason = nil,
		PendingKill = nil,
		LastDeathTime = nil,
	}
	local observer = {}

	function observer:Reset()
		state.LastStopped = nil
		state.LastReason = nil
		state.PendingKill = nil
		state.LastDeathTime = nil
	end

	function observer:OnKillHuntOutcome(event)
		if type(event) ~= "table" or type(event.Stopped) ~= "boolean" then
			return
		end
		state.PendingKill = nil
		state.LastStopped = event.Stopped
		state.LastReason = event.Reason
		if event.Stopped then
			api:Detect(
				"Revenant",
				event.Reason or "hunt stopped immediately after a player died",
				35,
				event.Source
			)
		else
			api:RuleOut(
				"Revenant",
				event.Reason or "hunt continued after a player died",
				95
			)
		end
		api:Refresh()
	end

	function observer:OnPlayerDeath(event)
		if type(event) ~= "table" or event.Hunting ~= true then
			return
		end
		local time = tonumber(event.Time or event.Timestamp)
		local otherAlive = tonumber(event.OtherAlive) or 0
		local huntAge = tonumber(event.HuntAge) or 0
		if time == nil
			or otherAlive <= 0
			or huntAge < MIN_HUNT_AGE then
			return
		end

		state.LastDeathTime = time
		state.PendingKill = {
			Time = time,
			OtherAlive = otherAlive,
			HuntAge = huntAge,
			Source = event.Source,
			StopReason = event.StopReason,
			ContinueReason = event.ContinueReason,
		}
	end

	local function pendingElapsed(event)
		local pending = state.PendingKill
		local now = type(event) == "table"
			and tonumber(event.Time or event.Timestamp)
			or nil
		if not pending or now == nil then
			return nil, pending
		end
		return now - pending.Time, pending
	end

	function observer:Tick(event)
		local elapsed, pending = pendingElapsed(event)
		if elapsed == nil or not pending or elapsed < 0 then
			return
		end
		if elapsed > MAX_PENDING_AGE then
			state.PendingKill = nil
			return
		end
		if event.Hunting == true and elapsed >= CONTINUED_AFTER then
			self:OnKillHuntOutcome({
				Stopped = false,
				Reason = pending.ContinueReason,
				Source = pending.Source,
			})
		end
	end

	observer.OnTick = observer.Tick

	function observer:OnHuntEnded(event)
		local elapsed, pending = pendingElapsed(event)
		if elapsed == nil or not pending or elapsed < 0 then
			return
		end
		if elapsed <= CONTINUED_AFTER then
			self:OnKillHuntOutcome({
				Stopped = true,
				Reason = pending.StopReason,
				Source = pending.Source,
			})
		elseif elapsed > MAX_PENDING_AGE then
			state.PendingKill = nil
		end
	end

	function observer:Snapshot()
		return {
			LastStopped = state.LastStopped,
			LastReason = state.LastReason,
			PendingKill = copyPending(state.PendingKill),
			LastDeathTime = state.LastDeathTime,
		}
	end

	return observer
end

return {
	Name = "Revenant",
	Evidence = {"EMFLevel5", "FreezingTemperatures", "GhostWriting"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 35,
	ObservationKeys = {"HuntEndAfterKill"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "The hunt ends immediately after it kills a hunter.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Weakness",
				Conditions = "This is clearest outside Easy and Medium difficulty.",
			},
		},
		["Maybe"] = {
			{
				Text = "The cooldown between hunts is short but less mechanically consistent than a Demon.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Trait",
			},
		},
		["Idk"] = {
			{
				Text = "Frequent hunts alone overlap with Demon behavior and difficulty settings.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = false,
				Kind = "Caveat",
			},
		},
	},
}
