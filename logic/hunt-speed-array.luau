return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "hunt-speed-array requires Traffic")
	local view = assert(dependencies.View, "hunt-speed-array requires View")
	local textColor = assert(dependencies.TextColor, "hunt-speed-array requires TextColor")
	local accentColor = assert(dependencies.AccentColor, "hunt-speed-array requires AccentColor")
	local canvasSize = dependencies.CanvasSize or UDim2.fromOffset
	local defer = dependencies.Defer or task.defer
	local controller = {Entries = {}, RowCount = 0}

	local function updateCanvas()
		view.List.CanvasSize = canvasSize(0, view.Layout.AbsoluteContentSize.Y + 8)
	end

	local function clear()
		for _, entry in ipairs(controller.Entries) do entry:Destroy() end
		table.clear(controller.Entries)
		controller.RowCount = 0
		view.Empty.Visible = true
		view.Empty.Text = "Hunt started; waiting for speed samples."
	end

	local function add(text, color)
		controller.RowCount += 1
		local entry = view.Template:Clone()
		entry.Name = "SpeedRow" .. controller.RowCount
		entry.LayoutOrder = controller.RowCount
		entry.Text = text
		entry.TextColor3 = color
		entry.Visible = true
		entry.Parent = view.List
		view.Empty.Visible = false
		table.insert(controller.Entries, entry)
		defer(updateCanvas)
	end

	controller.DisconnectTraffic = Traffic:Receive("SpeedArrayLog", function(signal, payload)
		payload = type(payload) == "table" and payload or {}
		if signal == "HuntSpeedReset" then
			clear()
			view.Title.Text = "  HUNT SPEED ARRAY (LIVE)"
			updateCanvas()
		elseif signal == "HuntSpeedSample" then
			local point = type(payload.Point) == "table" and payload.Point or {}
			add(string.format(
				"P%02d   {s = %.3f, v = %s}",
				tonumber(payload.Index) or 0,
				tonumber(point.s) or 0,
				tostring(point.v == true)
			), textColor)
		elseif signal == "HuntSpeedMarker" then
			add(string.format(
				"--- %s @ P%02d ---",
				tostring(payload.Label or "MARKER"),
				tonumber(payload.Index) or 0
			), accentColor)
		elseif signal == "HuntSpeedEnded" then
			view.Title.Text = string.format(
				"  HUNT SPEED ARRAY (ENDED — %d)",
				tonumber(payload.Count) or #controller.Entries
			)
		end
	end)
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
