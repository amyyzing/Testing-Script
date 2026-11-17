return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "ghost-pattern-log requires Traffic")
	local view = assert(dependencies.View, "ghost-pattern-log requires View")
	local positiveColor = assert(dependencies.PositiveColor, "ghost-pattern-log requires PositiveColor")
	local negativeColor = assert(dependencies.NegativeColor, "ghost-pattern-log requires NegativeColor")
	local eventColor = dependencies.EventColor or positiveColor
	local canvasSize = dependencies.CanvasSize or UDim2.fromOffset
	local defer = dependencies.Defer or task.defer
	local controller = {Seen = {}, Entries = {}, Count = 0, Disconnects = {}, KillRows = {}, RuledOut = {}}

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
		if controller.RuledOut[ghost] then return end
		if signal == "RuleOut" then controller.RuledOut[ghost] = true end
		local positive = signal == "Support"
		local heading = signal == "RuleOut" and "RULED OUT" or positive and "SUPPORT" or "AGAINST"
		add(heading .. "  " .. ghost, positive and positiveColor or negativeColor, "verdict|" .. ghost)
	end

	local function recordTracker(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "SaltHit" then
			add(payload.Hunting and "SALT HIT (HUNT)" or "SALT HIT", eventColor)
		elseif signal == "PlayerKilled" then
			local id = tostring(payload.userId or "?")
			controller.KillRows[id] = add("PLAYER KILLED", eventColor)
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
			"KILL SPEED  %s -> %s",
			before and string.format("%.2f", before) or "?",
			current and string.format("%.2f", current) or "?"
		)
		defer(updateCanvas)
	end

	local function number(value, format)
		return type(value) == "number" and string.format(format or "%.2f", value) or "?"
	end

	local function recordTemperature(signal, payload)
		if signal ~= "RoomTemperatureProgress" then return end
		local reading = number(payload.Temperature) .. " °C"
		if (payload.Count or 0) > 0 then
			reading ..= " | " .. number(-(payload.Average or 0), "%+.3f") .. " °C/s"
		end
		add("SHADOW TEMP  " .. reading, eventColor, "temperature")
	end

	local function recordSpeed(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "GhostSpeedObserved" then
			local heading = payload.Hunting and "HUNT SPEED" or "IDLE SPEED"
			add(heading .. "  " .. number(payload.Speed), eventColor, "speed")
		elseif signal == "HuntSpeedReset" then
			add("BLINK SPEED  0/14", eventColor, "pairs")
		elseif signal == "HuntSpeedSample" then
			local point = payload.Point or {}
			local visibility = point.v and "visible" or "hidden"
			add(string.format("BLINK SPEED  %d/14 | %s %s", payload.Index or 0,
				visibility, number(point.s)), eventColor, "pairs")
		elseif signal == "SpeedFilterResult" then
			local trend = payload.Identical and "steady" or "changing"
			local scale = payload.ScaleKnown and "" or " | scale unknown"
			add("BLINK SPEED  14/14 | " .. trend .. scale, eventColor, "pairs")
		elseif signal == "HuntSpeedEnded" and (payload.Count or 0) < 14 then
			add(string.format("BLINK SPEED  %d/14 | incomplete", payload.Count or 0), eventColor, "pairs")
		elseif signal == "WretchEnergySnapshot" then
			add("WRETCH  " .. number(payload.AverageEnergy, "%.0f") .. "% Energy | sampling", eventColor, "wretch")
		elseif signal == "WretchSpeedResult" then
			local status
			if not payload.Stable then
				status = "unstable"
			elseif not payload.Hunting then
				status = "idle"
			elseif not payload.ScaleKnown then
				status = "scale unknown"
			else
				status = payload.Matched and "match" or "mismatch"
			end
			add(string.format("WRETCH  %s%% Energy | %s | %s",
				number(payload.AverageEnergy, "%.0f"), number(payload.Speed), status), eventColor, "wretch")
		elseif signal == "FootstepProgress" then
			local samples = payload.Samples or 0
			local status = samples >= 3 and "heard" or payload.Hunting and "listening" or "waiting"
			add("UMBRA FOOTSTEPS  " .. status, eventColor, "footsteps")
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
