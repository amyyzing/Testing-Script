return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "flicker-array-log requires Traffic")
	local view = assert(dependencies.View, "flicker-array-log requires View")
	local textColor = assert(dependencies.TextColor, "flicker-array-log requires TextColor")
	local accentColor = assert(dependencies.AccentColor, "flicker-array-log requires AccentColor")
	local positiveColor = dependencies.PositiveColor or accentColor
	local canvasSize = dependencies.CanvasSize or UDim2.fromOffset
	local defer = dependencies.Defer or task.defer
	local controller = {Entries = {}, Arrays = {}, Names = {}, Order = {}}

	local function updateCanvas()
		view.List.CanvasSize = canvasSize(0, view.Layout.AbsoluteContentSize.Y + 8)
	end

	local function clearRows()
		for _, entry in ipairs(controller.Entries) do entry:Destroy() end
		table.clear(controller.Entries)
	end

	local function add(text, color, order)
		local entry = view.Template:Clone()
		entry.Name = "FlickerRow" .. order
		entry.LayoutOrder = order
		entry.Text = text
		entry.TextColor3 = color
		entry.Visible = true
		entry.Parent = view.List
		table.insert(controller.Entries, entry)
	end

	local function render(completed)
		clearRows()
		local order = 0
		for _, item in ipairs(controller.Order) do
			local data = controller.Arrays[item]
			if data then
				order += 1
				add(string.format(
					"%s  [%d/%d | %.2fs]",
					controller.Names[item],
					#data.Switches,
					data.RequiredSwitches,
					data.Duration
				), completed and positiveColor or accentColor, order)
				local firstTime = data.Switches[1] and data.Switches[1].t or 0
				for index, switch in ipairs(data.Switches) do
					order += 1
					add(string.format(
						"S%02d   {t = +%.3f, v = %s}",
						index,
						(tonumber(switch.t) or firstTime) - firstTime,
						tostring(switch.v == true)
					), textColor, order)
				end
			end
		end
		view.Empty.Visible = #controller.Entries == 0
		view.Title.Text = completed
			and "  FLICKER ARRAYS (LEVIATHAN MATCH)"
			or "  FLICKER ARRAYS (LIVE)"
		defer(updateCanvas)
	end

	controller.DisconnectTraffic = Traffic:Receive("FlickerArrayLog", function(signal, payload)
		if signal ~= "FlickerArrayUpdate" or type(payload) ~= "table"
			or payload.Item == nil or type(payload.Switches) ~= "table" then return end
		if not controller.Arrays[payload.Item] then table.insert(controller.Order, payload.Item) end
		controller.Arrays[payload.Item] = {
			Switches = payload.Switches,
			RequiredSwitches = tonumber(payload.RequiredSwitches) or 7,
			Duration = tonumber(payload.Duration) or 0,
		}
		controller.Names[payload.Item] = tostring(
			payload.ItemName or "Eligible electronic item"
		)
		render(payload.Completed == true)
	end)
	controller.LayoutConnection = view.Layout:GetPropertyChangedSignal("AbsoluteContentSize")
		:Connect(updateCanvas)
	updateCanvas()

	function controller:Destroy()
		self.DisconnectTraffic()
		self.LayoutConnection:Disconnect()
		clearRows()
		table.clear(self.Arrays)
		table.clear(self.Names)
		table.clear(self.Order)
	end

	return controller
end
