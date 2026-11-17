return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "ghost-pattern-log requires Traffic")
	local view = assert(dependencies.View, "ghost-pattern-log requires View")
	local positiveColor = assert(dependencies.PositiveColor, "ghost-pattern-log requires PositiveColor")
	local negativeColor = assert(dependencies.NegativeColor, "ghost-pattern-log requires NegativeColor")
	local canvasSize = dependencies.CanvasSize or UDim2.fromOffset
	local defer = dependencies.Defer or task.defer
	local controller = {Rows = {}, Count = 0}
	view.Empty.Visible = false

	local function updateCanvas()
		view.List.CanvasSize = canvasSize(0, view.Layout.AbsoluteContentSize.Y + 8)
	end

	local disconnect = Traffic:Receive("Verdict", function(signal, payload)
		if signal ~= "Support" and signal ~= "RuleOut" then return end
		if type(payload) ~= "table" or type(payload.Ghost) ~= "string"
			or type(payload.Perk) ~= "string" or (tonumber(payload.Confidence) or 0) < 80 then return end

		local key = payload.Ghost .. "|" .. payload.Perk
		local row = controller.Rows[key]
		if not row then
			controller.Count += 1
			row = view.Template:Clone()
			row.Name = "Perk" .. controller.Count
			row.LayoutOrder = controller.Count
			row.Visible = true
			row.Parent = view.List
			controller.Rows[key] = row
			view.Empty.Visible = false
		end

		local positive = signal == "Support"
		local heading = positive and "POSITIVE" or "NEGATIVE"
		row.Text = heading .. "  " .. payload.Ghost .. " | " .. (payload.Observation or payload.Perk)
		row.TextColor3 = positive and positiveColor or negativeColor
		defer(updateCanvas)
	end)
	local layoutConnection = view.Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
	updateCanvas()

	function controller:Destroy()
		disconnect()
		layoutConnection:Disconnect()
		for _, row in pairs(self.Rows) do row:Destroy() end
		table.clear(self.Rows)
	end

	return controller
end
