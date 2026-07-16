return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "ghost-pattern-log requires Traffic")
	local view = assert(dependencies.View, "ghost-pattern-log requires View")
	local positiveColor = assert(dependencies.PositiveColor, "ghost-pattern-log requires PositiveColor")
	local negativeColor = assert(dependencies.NegativeColor, "ghost-pattern-log requires NegativeColor")
	local canvasSize = dependencies.CanvasSize or UDim2.fromOffset
	local defer = dependencies.Defer or task.defer
	local controller = {Seen = {}, Entries = {}, Count = 0}

	local function updateCanvas()
		view.List.CanvasSize = canvasSize(0, view.Layout.AbsoluteContentSize.Y + 8)
	end

	local function record(signal, payload)
		if signal ~= "Support" and signal ~= "RuleOut" then return end
		payload = type(payload) == "table" and payload or {}
		local ghost = tostring(payload.Ghost or "Unknown")
		local reason = tostring(payload.Reason or "pattern observed")
		local key = table.concat({signal, ghost, reason}, "|")
		if controller.Seen[key] then return end
		controller.Seen[key] = true
		controller.Count += 1

		local entry = view.Template:Clone()
		entry.Name = "Pattern" .. controller.Count
		entry.LayoutOrder = controller.Count
		entry.Text = string.format(
			"%s  %s  [%s%%]\n%s",
			signal == "Support" and "POSITIVE" or "NEGATIVE",
			ghost,
			tostring(tonumber(payload.Confidence) or 0),
			reason
		)
		entry.TextColor3 = signal == "Support" and positiveColor or negativeColor
		entry.Visible = true
		entry.Parent = view.List
		view.Empty.Visible = false
		table.insert(controller.Entries, entry)
		defer(updateCanvas)
	end

	controller.DisconnectTraffic = Traffic:Receive("Verdict", record)
	controller.LayoutConnection = view.Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
	updateCanvas()

	function controller:Destroy()
		self.DisconnectTraffic()
		self.LayoutConnection:Disconnect()
		for _, entry in ipairs(self.Entries) do entry:Destroy() end
		table.clear(self.Entries)
	end

	return controller
end
