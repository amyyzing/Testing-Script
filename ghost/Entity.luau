local SOURCE = "https://demonology.fandom.com/wiki/Entity"

local OBJECT_MAX_ELAPSED = 0.65
local OBJECT_MIN_DISPLACEMENT = 25
local OBJECT_MIN_SPEED = 80
local OBJECT_RESOLVE_DELAY = 1.4
local SMOKE_RETENTION = 3
local SMOKE_TIME_TOLERANCE = 1.8
local SMOKE_DISTANCE_TOLERANCE = 12

local GHOST_WARMUP = 2
local GHOST_MAX_ELAPSED = 0.25
local GHOST_MIN_DISPLACEMENT = 30
local GHOST_MIN_SPEED = 120
local GHOST_RESOLVE_DELAY = 1.25

local function coordinates(value)
	if value == nil then
		return nil
	end
	local ok, x, y, z = pcall(function()
		return value.X, value.Y, value.Z
	end)
	if ok then
		x, y, z = tonumber(x), tonumber(y), tonumber(z)
		if x and y and z then
			return x, y, z
		end
	end
	if type(value) == "table" then
		x = tonumber(value.x or value[1])
		y = tonumber(value.y or value[2])
		z = tonumber(value.z or value[3])
		if x and y and z then
			return x, y, z
		end
	end
	return nil
end

local function distanceBetween(left, right)
	local leftX, leftY, leftZ = coordinates(left)
	local rightX, rightY, rightZ = coordinates(right)
	if not leftX or not rightX then
		return nil
	end
	local x = leftX - rightX
	local y = leftY - rightY
	local z = leftZ - rightZ
	return math.sqrt(x * x + y * y + z * z)
end

local function validRoom(room)
	return type(room) == "string" and room ~= ""
end

local function createObserver(api)
	local state = {
		RecentSmokeEffects = {},
		PendingObjectTeleports = {},
		PendingGhostTeleport = nil,
		TrackingStartedAt = nil,
		LastObjectSmoke = nil,
		LastObjectReason = nil,
		LastGhostTeleportReason = nil,
	}
	local observer = {}

	local function clearObjectWindows()
		table.clear(state.RecentSmokeEffects)
		table.clear(state.PendingObjectTeleports)
	end

	local function clearRawWindows()
		clearObjectWindows()
		state.PendingGhostTeleport = nil
	end

	local function classifyObjectTeleport(smoke, pending, event)
		state.LastObjectSmoke = smoke
		local reason = event and event.Reason
		if not reason and smoke then
			reason = ("an Item/Interactable teleported from %s to %s and left a SmokeHolder at its old position"):format(
				tostring(pending and pending.FromRoom or "another room"),
				tostring(pending and pending.ToRoom or "its destination")
			)
		elseif not reason then
			reason = ("an Item/Interactable teleported from %s to %s without producing an Entity SmokeHolder"):format(
				tostring(pending and pending.FromRoom or "another room"),
				tostring(pending and pending.ToRoom or "its destination")
			)
		end
		state.LastObjectReason = reason
		if smoke then
			api:Detect("Entity", reason, 99, event and event.Source)
		else
			api:RuleOut(
				"Entity",
				(event and event.EntityRuleOutReason)
					or "the teleported object produced no Entity SmokeHolder",
				95
			)
		end
		api:Refresh()
	end

	local function pruneSmoke(now)
		for index = #state.RecentSmokeEffects, 1, -1 do
			if now - state.RecentSmokeEffects[index].Time > SMOKE_RETENTION then
				table.remove(state.RecentSmokeEffects, index)
			end
		end
	end

	local function matchingSmoke(pending)
		for _, smoke in ipairs(state.RecentSmokeEffects) do
			local distance = distanceBetween(smoke.Position, pending.FromPosition)
			if math.abs(smoke.Time - pending.Time) <= SMOKE_TIME_TOLERANCE
				and distance ~= nil
				and distance <= SMOKE_DISTANCE_TOLERANCE then
				return smoke
			end
		end
		return nil
	end

	local function resolveObjectTeleports(now)
		pruneSmoke(now)
		for index = #state.PendingObjectTeleports, 1, -1 do
			local pending = state.PendingObjectTeleports[index]
			local smoke = matchingSmoke(pending)
			if smoke then
				classifyObjectTeleport(true, pending, {
					Source = pending.Source or smoke.Source,
				})
				table.remove(state.PendingObjectTeleports, index)
			elseif now >= pending.ResolveAt then
				classifyObjectTeleport(false, pending, {
					Source = pending.Source,
				})
				table.remove(state.PendingObjectTeleports, index)
			end
		end
	end

	local function classifyGhostTeleport(pending, event)
		local reason = event.Reason
		if not reason then
			reason = ("ghost moved %.1f studs from %s to %s in %.2f seconds and remained inside the destination room"):format(
				pending.Displacement,
				tostring(pending.FromRoom),
				tostring(event.CurrentRoom or event.ToRoom),
				pending.Elapsed
			)
		end
		state.LastGhostTeleportReason = reason
		api:Detect("Entity", reason, 65, pending.Source or event.Source)
		api:Refresh()
	end

	function observer:Reset(options)
		clearRawWindows()
		state.TrackingStartedAt = type(options) == "table"
			and tonumber(options.Time or options.Timestamp)
			or nil
		state.LastObjectSmoke = nil
		state.LastObjectReason = nil
		state.LastGhostTeleportReason = nil
	end

	function observer:OnObjectTeleport(event)
		if type(event) ~= "table" then
			return
		end
		if type(event.Smoke) == "boolean" then
			classifyObjectTeleport(event.Smoke, nil, event)
			return
		end
		local kind = event.Kind or event.Observation
		local now = tonumber(event.Time or event.Timestamp)
		if not now then
			return
		end
		if kind == "AutomationSuppressed"
			or event.AutomationSuppressed == true
			or event.Eligible == false then
			clearObjectWindows()
			return
		end
		if kind == "SmokeObserved" then
			if event.Position == nil then
				return
			end
			table.insert(state.RecentSmokeEffects, {
				Time = now,
				Position = event.Position,
				Source = event.Source,
			})
			resolveObjectTeleports(now)
			return
		end
		if kind ~= "MotionSample" then
			return
		end
		resolveObjectTeleports(now)
		local elapsed = tonumber(event.Elapsed)
		local displacement = tonumber(event.Displacement)
		local speed = tonumber(event.Speed)
		if not elapsed or not displacement or not speed
			or elapsed <= 0
			or elapsed > OBJECT_MAX_ELAPSED
			or displacement < OBJECT_MIN_DISPLACEMENT
			or speed < OBJECT_MIN_SPEED
			or not validRoom(event.FromRoom)
			or not validRoom(event.ToRoom)
			or event.FromRoom == event.ToRoom then
			return
		end
		table.insert(state.PendingObjectTeleports, {
			Object = event.Object,
			Time = now,
			ResolveAt = now + OBJECT_RESOLVE_DELAY,
			FromPosition = event.FromPosition,
			ToPosition = event.ToPosition,
			FromRoom = event.FromRoom,
			ToRoom = event.ToRoom,
			Displacement = displacement,
			Elapsed = elapsed,
			Speed = speed,
			Source = event.Source,
		})
	end

	function observer:OnGhostTeleport(event)
		event = type(event) == "table" and event or {}
		local kind = event.Kind or event.Observation
		if kind ~= "MotionSample" then
			state.LastGhostTeleportReason = event.Reason
			api:Detect(
				"Entity",
				event.Reason or "a verified room-to-room ghost teleport occurred",
				65,
				event.Source
			)
			api:Refresh()
			return
		end

		local now = tonumber(event.Time or event.Timestamp)
		if not now then
			return
		end
		state.TrackingStartedAt = state.TrackingStartedAt or now
		local pending = state.PendingGhostTeleport
		if pending and now >= pending.ResolveAt then
			local currentRoom = event.CurrentRoom or event.ToRoom
			if validRoom(currentRoom)
				and currentRoom ~= pending.FromRoom
				and pending.FromInside == true
				and event.CurrentInside == true then
				classifyGhostTeleport(pending, event)
			end
			state.PendingGhostTeleport = nil
		end

		local elapsed = tonumber(event.Elapsed)
		local displacement = tonumber(event.Displacement)
		local speed = tonumber(event.Speed)
		if now - state.TrackingStartedAt < GHOST_WARMUP
			or not elapsed or not displacement or not speed
			or elapsed <= 0
			or elapsed > GHOST_MAX_ELAPSED
			or displacement < GHOST_MIN_DISPLACEMENT
			or speed < GHOST_MIN_SPEED
			or not validRoom(event.FromRoom)
			or not validRoom(event.ToRoom)
			or event.FromRoom == event.ToRoom then
			return
		end
		state.PendingGhostTeleport = {
			Time = now,
			ResolveAt = now + GHOST_RESOLVE_DELAY,
			FromRoom = event.FromRoom,
			FromInside = event.PreviousInside == true,
			Displacement = displacement,
			Elapsed = elapsed,
			Speed = speed,
			Source = event.Source,
		}
	end

	function observer:Tick(event)
		local now = type(event) == "table"
			and tonumber(event.Time or event.Timestamp)
		if now then
			resolveObjectTeleports(now)
		end
	end

	function observer:Snapshot()
		return {
			LastObjectSmoke = state.LastObjectSmoke,
			LastObjectReason = state.LastObjectReason,
			LastGhostTeleportReason = state.LastGhostTeleportReason,
			PendingObjectTeleportCount = #state.PendingObjectTeleports,
			RecentSmokeCount = #state.RecentSmokeEffects,
			GhostTeleportPending = state.PendingGhostTeleport ~= nil,
		}
	end

	return observer
end

return {
	Name = "Entity",
	Evidence = {"Handprints", "LaserProjector", "SpiritBox"},
	Source = SOURCE,
	SourceStatus = "wiki-documented",
	Confidence = 95,
	TTL = 30,
	ObservationKeys = {"GhostTeleport", "ObjectTeleportSmoke"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "After Skinwalker is excluded, a witnessed teleport or an object teleport with same-colored smoke strongly identifies Entity.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Maybe"] = {
			{
				Text = "Equipment changed rooms, or salt placement implies an impossible path without teleporting.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Idk"] = {
			{
				Text = "Frequent roaming or a missed salt line does not establish teleportation.",
				Source = SOURCE,
				Status = "wiki-documented",
				Mimickable = true,
				Kind = "Caveat",
			},
		},
	},
}
