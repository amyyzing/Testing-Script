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

	local function add(text, color)
		controller.RowCount += 1
		local entry = view.Template:Clone()
		entry.Name = "WendigoRow" .. controller.RowCount
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
		local transition = tonumber(payload.Transition) or 0
		local state = payload.Hunting == true and "HUNTING" or "NON-HUNTING"
		if signal == "WendigoEnergySnapshot" then
			add(string.format(
				"T%02d  %s  ENERGY %.2f%%",
				transition,
				state,
				tonumber(payload.AverageEnergy) or 0
			), textColor)
		elseif signal == "WendigoSpeedSample" then
			add(string.format(
				"T%02d  %s  SPEED %.3f",
				transition,
				state,
				tonumber(payload.Speed) or 0
			), accentColor)
		end
	end)
	controller.LayoutConnection = view.Layout:GetPropertyChangedSignal("AbsoluteContentSize")
		:Connect(updateCanvas)
	updateCanvas()

	function controller:Destroy()
		self.DisconnectTraffic()
		self.LayoutConnection:Disconnect()
		for _, entry in ipairs(self.Entries) do entry:Destroy() end
		table.clear(self.Entries)
	end

	return controller
end
