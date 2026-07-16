return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "ghost-pattern-log requires Traffic")
	local view = assert(dependencies.View, "ghost-pattern-log requires View")
	local positiveColor = assert(dependencies.PositiveColor, "ghost-pattern-log requires PositiveColor")
	local negativeColor = assert(dependencies.NegativeColor, "ghost-pattern-log requires NegativeColor")
	local eventColor = dependencies.EventColor or positiveColor
	local canvasSize = dependencies.CanvasSize or UDim2.fromOffset
	local defer = dependencies.Defer or task.defer
	local controller = {Seen = {}, Entries = {}, Count = 0, Disconnects = {}}

	local function updateCanvas()
		view.List.CanvasSize = canvasSize(0, view.Layout.AbsoluteContentSize.Y + 8)
	end

	local function add(text, color, key)
		if key and controller.Seen[key] then return end
		if key then controller.Seen[key] = true end
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
		defer(updateCanvas)
	end

	local function recordVerdict(signal, payload)
		if signal ~= "Support" and signal ~= "RuleOut" then return end
		payload = type(payload) == "table" and payload or {}
		local ghost = tostring(payload.Ghost or "Unknown")
		local reason = tostring(payload.Reason or "pattern observed")
		add(string.format(
			"%s  %s  [%s%%]\n%s",
			signal == "Support" and "POSITIVE" or "NEGATIVE",
			ghost,
			tostring(tonumber(payload.Confidence) or 0),
			reason
		), signal == "Support" and positiveColor or negativeColor,
			table.concat({signal, ghost, reason}, "|"))
	end

	local function recordTracker(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "SaltHit" then
			add(string.format("TRACK  SALT HIT  #%s\nhunting: %s",
				tostring(payload.ContactId or "?"), tostring(payload.Hunting == true)), eventColor)
		elseif signal == "PlayerKilled" then
			add("TRACK  PLAYER KILLED\nuserId: " .. tostring(payload.userId or "?"), eventColor)
		end
	end

	table.insert(controller.Disconnects, Traffic:Receive("Verdict", recordVerdict))
	table.insert(controller.Disconnects, Traffic:Receive("SpeedTracker", recordTracker))
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
