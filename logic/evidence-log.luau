return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "evidence-log requires Traffic")
	local view = assert(dependencies.View, "evidence-log requires View")
	local catalog = assert(dependencies.EvidenceCatalog, "evidence-log requires EvidenceCatalog")
	local unknownColor = assert(dependencies.UnknownColor, "evidence-log requires UnknownColor")
	local positiveColor = assert(dependencies.PositiveColor, "evidence-log requires PositiveColor")
	local negativeColor = assert(dependencies.NegativeColor, "evidence-log requires NegativeColor")
	local canvasSize = dependencies.CanvasSize or UDim2.fromOffset
	local defer = dependencies.Defer or task.defer
	local controller = {Rows = {}, States = {}, Details = {}, Displays = {}}

	local function updateCanvas()
		view.List.CanvasSize = canvasSize(0, view.Layout.AbsoluteContentSize.Y + 8)
	end

	local function render(evidence)
		local row = controller.Rows[evidence]
		if not row then return end
		local state = controller.States[evidence]
		local impossible = controller.Displays[evidence] == true
		local definition = catalog.Evidence[evidence]
		local name = definition and (definition.DisplayName or definition.CurrentName) or evidence
		local detail = controller.Details[evidence]
		if detail then
			row.Text = detail
			row.TextColor3 = state == true and positiveColor
				or (state == false or impossible) and negativeColor
				or unknownColor
			return
		end
		if state == true then
			row.Text = name .. ": Yes"
			row.TextColor3 = positiveColor
		elseif state == false or impossible then
			row.Text = name .. ": Impossible"
			row.TextColor3 = negativeColor
		else
			row.Text = name .. ": Unknown"
			row.TextColor3 = unknownColor
		end
	end

	local function createRow(key, order)
		local row = view.Template:Clone()
		row.Name = "EvidenceRow" .. key
		row.LayoutOrder = order
		row.Visible = true
		row.Parent = view.List
		controller.Rows[key] = row
		return row
	end

	for index, evidence in ipairs(catalog.EvidenceOrder) do
		createRow(evidence, index)
		render(evidence)
	end
	for index, key in ipairs({"FavouriteRoom", "Ghost"}) do
		local row = createRow(key, #catalog.EvidenceOrder + index)
		row.Text = key == "FavouriteRoom" and "Favourite Room: ..." or "Ghost: Unknown (Idk)"
		row.TextColor3 = unknownColor
	end
	view.Empty.Visible = false
	defer(updateCanvas)

	controller.DisconnectTraffic = Traffic:Receive("EvidenceLog", function(signal, payload)
		if type(payload) ~= "table" then return end
		if signal == "EvidenceMetric" then
			local row = controller.Rows[payload.Key]
			if not row or type(payload.Text) ~= "string" then return end
			row.Text = payload.Text
			row.TextColor3 = payload.State == true and positiveColor
				or payload.State == false and negativeColor or unknownColor
			return
		end
		local evidence = catalog.NormalizeEvidence(payload.Evidence)
		if not evidence or not controller.Rows[evidence] then return end
		if signal == "EvidenceDetail" then
			controller.Details[evidence] = payload.Text
		elseif signal == "EvidenceDisplay" then
			controller.Displays[evidence] = payload.Impossible == true
		elseif signal == "EvidenceState" then
			if payload.State == true then
				controller.States[evidence] = true
			elseif payload.State == false then
				controller.States[evidence] = false
			else
				controller.States[evidence] = nil
			end
		else
			return
		end
		render(evidence)
	end)
	controller.LayoutConnection = view.Layout:GetPropertyChangedSignal("AbsoluteContentSize")
		:Connect(updateCanvas)
	updateCanvas()

	function controller:Destroy()
		self.DisconnectTraffic()
		self.LayoutConnection:Disconnect()
		for _, row in pairs(self.Rows) do row:Destroy() end
		table.clear(self.Rows)
		table.clear(self.States)
		table.clear(self.Details)
		table.clear(self.Displays)
	end

	return controller
end
