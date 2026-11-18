return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "ghost-pattern-log requires Traffic")
	local view = assert(dependencies.View, "ghost-pattern-log requires View")
	local positiveColor = assert(dependencies.PositiveColor, "ghost-pattern-log requires PositiveColor")
	local negativeColor = assert(dependencies.NegativeColor, "ghost-pattern-log requires NegativeColor")
	local canvasSize = dependencies.CanvasSize or UDim2.fromOffset
	local defer = dependencies.Defer or task.defer
	local controller = {Rows = {}, Results = {}, Count = 0}
	local readRisk = dependencies.DoppelgangerPossible
	view.Empty.Visible = false

	local function updateCanvas()
		view.List.CanvasSize = canvasSize(0, view.Layout.AbsoluteContentSize.Y + 8)
	end

	local function isMedium(result)
		if not result.Positive or not result.Copyable or result.SourceConfidence < 50 then return false end
		if readRisk then return result.SourceConfidence < 80 or readRisk() == true end
		return result.Certainty == "Medium"
	end
	local function isLow(result)
		return result.Positive and result.Certainty == "Low"
			and result.SourceConfidence > 0 and result.SourceConfidence < 50
	end

	local function render(key, result)
		local row = controller.Rows[key]
		local heading = isLow(result) and "LOW" or isMedium(result) and "MEDIUM"
			or result.Positive and "POSITIVE" or "NEGATIVE"
		row.Text = heading .. "  " .. result.Text
		row.TextColor3 = result.Positive and positiveColor or negativeColor
	end

	local disconnect = Traffic:Receive("Verdict", function(signal, payload)
		for key, result in pairs(controller.Results) do render(key, result) end
		if signal ~= "Support" and signal ~= "RuleOut" then return end
		if type(payload) ~= "table" or type(payload.Ghost) ~= "string"
			or type(payload.Perk) ~= "string" then return end
		local confidence = tonumber(payload.Confidence) or 0
		local result = {
			Positive = signal == "Support",
			Copyable = payload.Copyable ~= false,
			SourceConfidence = tonumber(payload.SourceConfidence) or confidence,
			Certainty = payload.Certainty,
			Text = payload.Ghost .. " | " .. (payload.Observation or payload.Perk),
		}
		if confidence < 80 and not isMedium(result) and not isLow(result) then return end

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

		controller.Results[key] = result
		render(key, result)
		defer(updateCanvas)
	end)
	local layoutConnection = view.Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
	updateCanvas()

	function controller:Destroy()
		disconnect()
		layoutConnection:Disconnect()
		for _, row in pairs(self.Rows) do row:Destroy() end
		table.clear(self.Rows)
		table.clear(self.Results)
	end

	return controller
end
