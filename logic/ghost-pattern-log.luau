return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "ghost-pattern-log requires Traffic")
	local view = assert(dependencies.View, "ghost-pattern-log requires View")
	local positiveColor = assert(dependencies.PositiveColor, "ghost-pattern-log requires PositiveColor")
	local negativeColor = assert(dependencies.NegativeColor, "ghost-pattern-log requires NegativeColor")
	local eventColor = dependencies.EventColor or positiveColor
	local canvasSize = dependencies.CanvasSize or UDim2.fromOffset
	local defer = dependencies.Defer or task.defer
	local controller = {Seen = {}, Entries = {}, Count = 0, Disconnects = {}, KillRows = {}}

	local function updateCanvas()
		view.List.CanvasSize = canvasSize(0, view.Layout.AbsoluteContentSize.Y + 8)
	end

	local function add(text, color, key)
		if key and controller.Seen[key] then
			local entry = controller.Seen[key]
			entry.Text, entry.TextColor3 = text, color
			defer(updateCanvas)
			return entry
		end
		controller.Count += 1

		local entry = view.Template:Clone()
		entry.Name = "Pattern" .. controller.Count
		entry.LayoutOrder = controller.Count
		entry.Text = text
		entry.TextColor3 = color
		entry.Visible = true
		entry.Parent = view.List
		view.Empty.Visible = false
		table.insert(controller.Entries, entry)
		if key then controller.Seen[key] = entry end
		defer(updateCanvas)
		return entry
	end

	local function recordVerdict(signal, payload)
		if signal ~= "Support" and signal ~= "Negative" and signal ~= "RuleOut" then return end
		payload = type(payload) == "table" and payload or {}
		local ghost = tostring(payload.Ghost or "Unknown")
		local reason = tostring(payload.Reason or "pattern observed")
		local positive = signal == "Support"
		local heading = signal == "RuleOut" and "RULED OUT" or positive and "SUPPORT" or "NEGATIVE"
		local strength = signal == "RuleOut" and "" or string.format("  [score %d/100]", tonumber(payload.Confidence) or 0)
		add(string.format("%s  %s%s\n%s", heading, ghost, strength, reason),
			positive and positiveColor or negativeColor, table.concat({signal, ghost, reason}, "|"))
	end

	local function recordTracker(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "SaltHit" then
			add(string.format("TRACK  SALT HIT  #%s\nhunting: %s",
				tostring(payload.ContactId or "?"), tostring(payload.Hunting == true)), eventColor)
		elseif signal == "PlayerKilled" then
			local id = tostring(payload.userId or "?")
			controller.KillRows[id] = add(
				"TRACK  PLAYER KILLED\nuserId: " .. id .. " | waiting for speed",
				eventColor
			)
		end
	end

	local function maximumSpeed(points)
		local result
		for _, point in ipairs(type(points) == "table" and points or {}) do
			local speed = tonumber(point.s)
			if speed and (not result or speed > result) then result = speed end
		end
		return result
	end

	local function recordKillSpeed(signal, payload)
		if signal ~= "KillSpeed" then return end
		payload = type(payload) == "table" and payload or {}
		local id = tostring(payload.userId or "?")
		local after = type(payload.afterKill) == "table" and payload.afterKill or {}
		local current = after[#after] and tonumber(after[#after].s)
		local before = payload.baselineKill and tonumber(payload.baselineKill.s)
			or maximumSpeed(payload.beforeKill)
		local entry = controller.KillRows[id]
		if not entry then
			entry = add("", eventColor)
			controller.KillRows[id] = entry
		end
		entry.Text = string.format(
			"TRACK  PLAYER KILLED\nuserId: %s | speed: %s -> %s%s",
			id,
			before and string.format("%.3f", before) or "?",
			current and string.format("%.3f", current) or "?",
			payload.completed and " (completed)" or ""
		)
		defer(updateCanvas)
	end

	local function recordTemperature(signal, payload)
		if signal ~= "RoomTemperatureProgress" then return end
		add(string.format("TRACK  SHADOW TEMPERATURE\n%s | %.2f C | %d/%d | net cooling: %.4f C/s\n%s",
			tostring(payload.RoomName or "Waiting for room"), tonumber(payload.Temperature) or 0,
			tonumber(payload.Count) or 0, tonumber(payload.Required) or 7, tonumber(payload.Average) or 0,
			tostring(payload.Status or "Collecting temperature changes")), eventColor, "temperature")
	end

	local function number(value)
		return type(value) == "number" and string.format("%.3f", value) or "unknown"
	end

	local function recordSpeed(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "GhostSpeedObserved" then
			local scale = dependencies.ReadScale and dependencies.ReadScale() or {}
			add(string.format("TRACK  GHOST SPEED\n%s | %s | speed: %s | Energy: %s\nMap: x%s | custom: x%s | %s",
				payload.Hunting and "Hunting" or "Not hunting", payload.Visible and "Visible" or "Invisible",
				number(payload.Speed), number(payload.AverageEnergy), number(scale.MapMultiplier), number(scale.CustomMultiplier),
				scale.Known and "Scale confirmed" or "Scale unconfirmed; absolute-speed verdicts waiting"), eventColor, "speed")
		elseif signal == "HuntSpeedReset" then
			add("TRACK  PHANTOM / ONI / DULLAHAN\nWaiting for visible/invisible pairs: 0/7", eventColor, "pairs")
		elseif signal == "HuntSpeedSample" then
			local point = payload.Point or {}
			add(string.format("TRACK  PHANTOM / ONI / DULLAHAN\n%d/14 visibility samples | %s speed: %s",
				tonumber(payload.Index) or 0, point.v and "Visible" or "Invisible", number(point.s)), eventColor, "pairs")
		elseif signal == "SpeedFilterResult" then
			add(string.format("TRACK  PHANTOM / ONI / DULLAHAN\n7/7 pairs | %s | base: %s | %s",
				payload.Identical and "Flat speed" or "Changing speed", number(payload.BaseSpeed),
				payload.ScaleKnown and "Scale confirmed; checking perk behavior" or "Scale unconfirmed; Oni waiting"), eventColor, "pairs")
		elseif signal == "HuntSpeedEnded" then
			add(string.format("TRACK  HUNT WINDOW\nEnded after %d visibility samples; incomplete windows stay inconclusive",
				tonumber(payload.Count) or 0), eventColor, "hunt-end")
		elseif signal == "WretchEnergySnapshot" then
			add(string.format("TRACK  WRETCH\nTransition %s | %s | Energy: %s | waiting for stable speed",
				tostring(payload.Transition or "?"), payload.Hunting and "Hunting" or "Not hunting", number(payload.AverageEnergy)), eventColor, "wretch")
		elseif signal == "WretchSpeedResult" then
			add(string.format("TRACK  WRETCH\nEnergy: %s | speed: %s | candidate expected: %s\n%s",
				number(payload.AverageEnergy), number(payload.Speed), number(payload.ExpectedSpeed),
				not payload.Stable and "Unstable speed; trial ignored" or not payload.Hunting and "Non-hunting baseline; waiting for hunt"
				or not payload.ScaleKnown and "Scale unconfirmed; waiting for three distinct Energy levels"
				or payload.Matched and "Curve match; waiting for corroboration" or "Curve mismatch; waiting for corroboration"), eventColor, "wretch")
		elseif signal == "FootstepProgress" then
			add(string.format("TRACK  UMBRA FOOTSTEPS\n%d/3 audible native-footstep samples | %s",
				tonumber(payload.Samples) or 0, (tonumber(payload.Samples) or 0)>=3 and "Audible native footsteps contradict Umbra" or payload.Hunting and "Listening during hunt; silence is inconclusive" or "Waiting for hunt"), eventColor, "footsteps")
		end
	end

	table.insert(controller.Disconnects, Traffic:Receive("Verdict", recordVerdict))
	table.insert(controller.Disconnects, Traffic:Receive("SpeedTracker", recordTracker))
	table.insert(controller.Disconnects, Traffic:Receive("Aswang", recordKillSpeed))
	table.insert(controller.Disconnects, Traffic:Receive("GhostPatternLog", function(signal, payload)
			recordTemperature(signal, payload)
			recordSpeed(signal, payload)
		end))
	table.insert(controller.Disconnects, Traffic:Receive("SpeedArrayLog", recordSpeed))
	controller.LayoutConnection = view.Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
	updateCanvas()

	function controller:Destroy()
		for _, disconnect in ipairs(self.Disconnects) do disconnect() end
		table.clear(self.Disconnects)
		self.LayoutConnection:Disconnect()
		for _, entry in ipairs(self.Entries) do entry:Destroy() end
		table.clear(self.Entries)
	end

	return controller
end
