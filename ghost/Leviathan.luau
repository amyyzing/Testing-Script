local SOURCE = "https://demonology.fandom.com/wiki/Leviathan"

local SKINWALKER_MIMIC_REASON =
	"Skinwalker may mimic one Leviathan light or equipment ability"

local ITEM_EVENT_WINDOW = 3
local MIN_ITEM_TOGGLES = 9
local MIN_FLICKER_DURATION = 0.55
local MAX_FLICKER_DURATION = 3
local MAX_TOGGLE_GAP = 0.75
local LIGHT_BATCH_WINDOW = 0.6
local CORROBORATION_WINDOW = 12
local ELIGIBLE_ITEM_NAMES = {
	["spirit box"] = true,
	["laser projector"] = true,
	["blacklight"] = true,
	["emf reader"] = true,
	["video camera"] = true,
	["flashlight"] = true,
}

local function appendOnce(reason, suffix)
	if string.find(reason, suffix, 1, true) then
		return reason
	end
	return reason .. suffix
end

local function eventTime(event)
	return tonumber(event.Time or event.Timestamp) or os.clock()
end

local function booleanField(event, names)
	for _, name in ipairs(names) do
		local value = event[name]
		if type(value) == "boolean" then
			return value
		end
	end
	return nil
end

local function createObserver(api)
	local state = {
		LastKind = nil,
		LastReason = nil,
		LastCorroborated = false,
		LastConfidence = nil,
		LastFlickerAt = -math.huge,
		LastLightOffAt = -math.huge,
		ItemToggleEvents = {},
		PendingLightOffEdges = {},
		RoomLightObservations = {},
	}
	local observer = {}

	local function skinwalkerPossible(event)
		if type(event.SkinwalkerPossible) == "boolean" then
			return event.SkinwalkerPossible
		end
		local possible = api:SupportsConfirmedEvidence("Skinwalker") == true
		if api:Mode() == "Mimicry" and not api:IsRuledOut("Skinwalker") then
			possible = true
		end
		return possible
	end

	function observer:Reset()
		state.LastKind = nil
		state.LastReason = nil
		state.LastCorroborated = false
		state.LastConfidence = nil
		state.LastFlickerAt = -math.huge
		state.LastLightOffAt = -math.huge
		state.ItemToggleEvents = {}
		state.PendingLightOffEdges = {}
		state.RoomLightObservations = {}
	end

	function observer:OnClue(event)
		if type(event) ~= "table"
			or (event.Kind ~= "Flicker" and event.Kind ~= "LightOff") then
			return
		end
		local kind = event.Kind
		local now = eventTime(event)
		if kind == "Flicker" then
			state.LastFlickerAt = now
		else
			state.LastLightOffAt = now
		end
		local computedCorroboration = now - state.LastFlickerAt
			<= CORROBORATION_WINDOW
			and now - state.LastLightOffAt <= CORROBORATION_WINDOW
		local corroborated = if type(event.Corroborated) == "boolean"
			then event.Corroborated
			else computedCorroboration
		local reason = event.Reason
		if reason == nil and kind == "LightOff" and event.Room ~= nil then
			reason = "room "
				.. tostring(event.Room)
				.. " switched its lights off outside a hunt"
		elseif reason == nil and kind == "Flicker" then
			local itemName = tostring(event.ItemName or "eligible electronic item")
			local toggleCount = tonumber(event.ToggleCount)
			local duration = tonumber(event.Duration)
			if toggleCount and duration then
				reason = itemName
					.. " produced "
					.. tostring(toggleCount)
					.. " clean alternating toggles within "
					.. string.format("%.2f", duration)
					.. " seconds"
			end
		end
		reason = reason
			or (kind == "LightOff"
				and "a room switched its lights off outside a hunt"
				or "eligible electronic equipment produced a clean out-of-hunt flicker")
		state.LastKind = kind
		state.LastCorroborated = corroborated

		if kind == "LightOff" then
			reason = appendOnce(
				reason,
				"; an out-of-hunt room-light shutoff was directly observed"
			)
			state.LastConfidence = 99
			api:Detect("Leviathan", reason, 99, event.Source)
			api:MarkPersistent("Leviathan")
			local skinwalkerDetection = api:GetDetection("Skinwalker")
			if type(skinwalkerDetection) == "table"
				and skinwalkerDetection.Reason == SKINWALKER_MIMIC_REASON then
				api:ClearDetection("Skinwalker")
			end
		else
			local confidence = tonumber(event.Confidence)
				or (corroborated and 99 or 60)
			local suffix = corroborated
				and "; both out-of-hunt equipment flicker and a room light shutoff were observed"
				or "; this single ability is not unique"
			reason = appendOnce(reason, suffix)
			state.LastConfidence = confidence
			api:Detect("Leviathan", reason, confidence, event.Source)
			api:MarkPersistent("Leviathan")
			if not corroborated and skinwalkerPossible(event) then
				api:Detect(
					"Skinwalker",
					SKINWALKER_MIMIC_REASON,
					60,
					event.Source
				)
				api:MarkPersistent("Skinwalker")
			end
		end
		state.LastReason = reason
		api:Refresh()
	end

	-- Raw equipment policy. Each item owns an independent three-second rolling
	-- sequence; only the last event needs to establish that the nearby ghost was
	-- a more plausible cause than an alive player.
	function observer:OnItemToggle(event)
		if type(event) ~= "table"
			or event.Hunting ~= false
			or event.AutomationSuppressed == true
			or event.Suppressed == true
			or event.Eligible == false then
			return
		end
		local itemName = string.lower(tostring(event.ItemName or ""))
		if not ELIGIBLE_ITEM_NAMES[itemName] then
			return
		end
		local previous = booleanField(event, {
			"Previous",
			"PreviousState",
			"PreviousEnabled",
		})
		local current = booleanField(event, {
			"Current",
			"CurrentState",
			"Enabled",
			"State",
		})
		if previous == nil or current == nil or previous == current then
			return
		end

		local itemId = event.ItemId or event.Item or event.Model or event.Object
		if itemId == nil then
			return
		end
		local now = eventTime(event)
		local events = state.ItemToggleEvents[itemId]
		if not events then
			events = {}
			state.ItemToggleEvents[itemId] = events
		end
		table.insert(events, {
			Time = now,
			State = current,
		})
		table.sort(events, function(left, right)
			return left.Time < right.Time
		end)
		while events[1] and now - events[1].Time > ITEM_EVENT_WINDOW do
			table.remove(events, 1)
		end
		if #events < MIN_ITEM_TOGGLES then
			return
		end

		local alternatingCount = 1
		local largestGap = 0
		local firstTime = events[1].Time
		local lastTime = firstTime
		local lastState = events[1].State
		for index = 2, #events do
			local toggle = events[index]
			local gap = toggle.Time - lastTime
			largestGap = math.max(largestGap, gap)
			if toggle.State ~= lastState then
				alternatingCount = alternatingCount + 1
			else
				alternatingCount = 1
				firstTime = toggle.Time
			end
			lastState = toggle.State
			lastTime = toggle.Time
		end
		local duration = lastTime - firstTime
		if alternatingCount < MIN_ITEM_TOGGLES
			or duration < MIN_FLICKER_DURATION
			or duration > MAX_FLICKER_DURATION
			or largestGap > MAX_TOGGLE_GAP then
			return
		end

		local ghostDistance = tonumber(event.GhostDistance)
		local nearestPlayerDistance = tonumber(event.NearestPlayerDistance)
		if not ghostDistance
			or not nearestPlayerDistance
			or ghostDistance > 40
			or not (
				nearestPlayerDistance > 12
				or ghostDistance + 3 < nearestPlayerDistance
			) then
			return
		end

		self:OnClue({
			Kind = "Flicker",
			Time = now,
			ItemName = event.ItemName,
			ToggleCount = alternatingCount,
			Duration = duration,
			SkinwalkerPossible = event.SkinwalkerPossible,
			Source = event.Source,
		})
	end

	local function causeIsEligible(event, requireDistances)
		if event.FuseEnabled ~= true
			or event.SwitchPresent == false
			or event.LightsBroken == true then
			return false
		end
		local ghostDistance = tonumber(event.GhostDistance)
		local nearestPlayerDistance = tonumber(event.NearestPlayerDistance)
		if not ghostDistance or not nearestPlayerDistance then
			return not requireDistances
		end
		return ghostDistance <= 45
			and (
				nearestPlayerDistance > 12
				or ghostDistance + 3 < nearestPlayerDistance
			)
	end

	local function queueRawRoomEdge(event)
		local roomId = event.RoomId or event.RoomObject
		if roomId == nil then
			return false
		end
		local lightsOn = booleanField(event, {"LightsOn", "RoomLightsOn"})
		local switchState = booleanField(event, {"SwitchState", "LightSwitchState"})
		if lightsOn == nil and switchState == nil then
			return false
		end

		local now = eventTime(event)
		local roomState = state.RoomLightObservations[roomId]
		if not roomState then
			roomState = {}
			state.RoomLightObservations[roomId] = roomState
		end
		local allowed = event.Hunting == false
			and event.AutomationSuppressed ~= true
			and event.Suppressed ~= true
		local edge = {
			Time = now,
			Allowed = allowed,
			Room = event.Room or event.RoomName,
			FuseEnabled = event.FuseEnabled == true,
			SwitchPresent = event.SwitchPresent ~= false,
			LightsBroken = event.LightsBroken == true,
			GhostDistance = tonumber(event.GhostDistance),
			NearestPlayerDistance = tonumber(event.NearestPlayerDistance),
			Source = event.Source,
		}
		if lightsOn ~= nil then
			if roomState.LightsOn == true and lightsOn == false
				and event.LightsBroken ~= true then
				roomState.LightEdge = edge
			end
			roomState.LightsOn = lightsOn
		end
		if switchState ~= nil then
			if roomState.SwitchState == true and switchState == false then
				roomState.SwitchEdge = edge
			end
			roomState.SwitchState = switchState
		end

		local lightEdge = roomState.LightEdge
		local switchEdge = roomState.SwitchEdge
		if lightEdge and now - lightEdge.Time > LIGHT_BATCH_WINDOW then
			roomState.LightEdge = nil
			lightEdge = nil
		end
		if switchEdge and now - switchEdge.Time > LIGHT_BATCH_WINDOW then
			roomState.SwitchEdge = nil
			switchEdge = nil
		end
		if lightEdge and switchEdge
			and math.abs(lightEdge.Time - switchEdge.Time) <= LIGHT_BATCH_WINDOW then
			local resolved = switchEdge.Time >= lightEdge.Time
				and switchEdge
				or lightEdge
			resolved.Time = math.max(lightEdge.Time, switchEdge.Time)
			resolved.Allowed = lightEdge.Allowed and switchEdge.Allowed
			resolved.FuseEnabled = lightEdge.FuseEnabled
				and switchEdge.FuseEnabled
			roomState.LightEdge = nil
			roomState.SwitchEdge = nil
			if resolved.Allowed and causeIsEligible(resolved, true) then
				table.insert(state.PendingLightOffEdges, resolved)
				table.sort(state.PendingLightOffEdges, function(left, right)
					return left.Time < right.Time
				end)
			end
		end
		return true
	end

	-- Raw room/switch snapshots are correlated here so the game adapter never
	-- decides whether a light pattern belongs to Leviathan.
	function observer:OnLightToggle(event)
		if type(event) ~= "table" then
			return
		end
		if event.RawObservation == true then
			queueRawRoomEdge(event)
			return
		end
		if event.Hunting ~= false
			or event.AutomationSuppressed == true
			or event.Suppressed == true
			or event.Eligible ~= true
			or event.LightsBroken == true then
			return
		end
		local previous = booleanField(event, {
			"Previous",
			"PreviousState",
			"PreviousLightsOn",
		})
		local current = booleanField(event, {
			"Current",
			"CurrentState",
			"LightsOn",
			"State",
		})
		local offEdge = event.OffEdge == true
			or (previous == true and current == false)
		if not offEdge then
			return
		end
		if not causeIsEligible(event, false) then
			return
		end
		table.insert(state.PendingLightOffEdges, {
			Time = eventTime(event),
			Room = event.Room or event.RoomName,
			FuseEnabled = event.FuseEnabled == true,
			Source = event.Source,
		})
		table.sort(state.PendingLightOffEdges, function(left, right)
			return left.Time < right.Time
		end)
	end

	function observer:OnTick(event)
		event = type(event) == "table" and event or {}
		local now = eventTime(event)
		while state.PendingLightOffEdges[1]
			and now - state.PendingLightOffEdges[1].Time
				>= LIGHT_BATCH_WINDOW do
			local oldestTime = state.PendingLightOffEdges[1].Time
			local batch = {}
			local remaining = {}
			for _, edge in ipairs(state.PendingLightOffEdges) do
				if edge.Time <= oldestTime + LIGHT_BATCH_WINDOW then
					table.insert(batch, edge)
				else
					table.insert(remaining, edge)
				end
			end
			state.PendingLightOffEdges = remaining

			local edge = batch[1]
			local fuseEnabled = event.FuseEnabled
			if type(fuseEnabled) ~= "boolean" then
				fuseEnabled = edge and edge.FuseEnabled == true
			end
			if #batch == 1 and fuseEnabled == true then
				self:OnClue({
					Kind = "LightOff",
					Time = edge.Time,
					Room = edge.Room,
					Source = edge.Source,
				})
			end
		end
	end

	-- Runtime:Tick dispatches the hook name "Tick"; retain the explicit OnTick
	-- method too for direct/raw hosts.
	observer.Tick = observer.OnTick

	function observer:Snapshot()
		return {
			LastKind = state.LastKind,
			LastReason = state.LastReason,
			LastCorroborated = state.LastCorroborated,
			LastConfidence = state.LastConfidence,
			LastFlickerAt = state.LastFlickerAt,
			LastLightOffAt = state.LastLightOffAt,
			TrackedItemCount = (function()
				local count = 0
				for _ in pairs(state.ItemToggleEvents) do
					count = count + 1
				end
				return count
			end)(),
			PendingLightCount = #state.PendingLightOffEdges,
			TrackedRoomCount = (function()
				local count = 0
				for _ in pairs(state.RoomLightObservations) do
					count = count + 1
				end
				return count
			end)(),
		}
	end

	return observer
end

return {
	Name = "Leviathan",
	Evidence = {"GhostOrb", "GhostWriting", "Handprints"},
	Source = SOURCE,
	SourceStatus = "wiki-stub",
	Confidence = 95,
	TTL = 30,
	ObservationKeys = {"OutOfHuntEquipmentFlicker", "OutOfHuntRoomLightOff"},
	CreateObserver = createObserver,
	Perks = {
		["Pretty Sure"] = {
			{
				Text = "A room's light switch shut the lights off while the ghost was not hunting, with no player, automation, or fuse-box outage responsible.",
				Source = SOURCE,
				Status = "wiki-stub",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Maybe"] = {
			{
				Text = "Nearby equipment produced a clean rapid flicker outside a hunt; by itself this can overlap with Skinwalker mimicry.",
				Source = SOURCE,
				Status = "wiki-stub",
				Mimickable = true,
				Kind = "Ability",
			},
		},
		["Idk"] = {
			{
				Text = "A broken fuse box or general power outage is explicitly not the Leviathan tell.",
				Source = SOURCE,
				Status = "wiki-stub",
				Mimickable = true,
				Kind = "Caveat",
			},
		},
	},
}
