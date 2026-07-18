return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "evidence-log requires Traffic")
	local view = assert(dependencies.View, "evidence-log requires View")
	local catalog = assert(dependencies.EvidenceCatalog, "evidence-log requires EvidenceCatalog")
	local unknownColor = assert(dependencies.UnknownColor, "evidence-log requires UnknownColor")
	local positiveColor = assert(dependencies.PositiveColor, "evidence-log requires PositiveColor")
	local negativeColor = assert(dependencies.NegativeColor, "evidence-log requires NegativeColor")
	local canvasSize = dependencies.CanvasSize or UDim2.fromOffset
	local defer = dependencies.Defer or task.defer
	local controller = {Rows = {}, States = {}}

	local function updateCanvas()
		view.List.CanvasSize = canvasSize(0, view.Layout.AbsoluteContentSize.Y + 8)
	end

	local function render(evidence)
		local row = controller.Rows[evidence]
		if not row then return end
		local state = controller.States[evidence]
		local definition = catalog.Evidence[evidence]
		local name = definition and (definition.DisplayName or definition.CurrentName) or evidence
		if state == true then
			row.Text = name .. ": Yes"
			row.TextColor3 = positiveColor
		elseif state == false then
			row.Text = name .. ": Impossible"
			row.TextColor3 = negativeColor
		else
			row.Text = name .. ": Unknown"
			row.TextColor3 = unknownColor
		end
	end

	for index, evidence in ipairs(catalog.EvidenceOrder) do
		local row = view.Template:Clone()
		row.Name = "EvidenceRow" .. evidence
		row.LayoutOrder = index
		row.Visible = true
		row.Parent = view.List
		controller.Rows[evidence] = row
		render(evidence)
	end
	view.Empty.Visible = false
	defer(updateCanvas)

	controller.DisconnectTraffic = Traffic:Receive("EvidenceLog", function(signal, payload)
		if signal ~= "EvidenceState" or type(payload) ~= "table" then return end
		local evidence = catalog.NormalizeEvidence(payload.Evidence)
		if not evidence or not controller.Rows[evidence] then return end
		if payload.State == true then
			controller.States[evidence] = true
		elseif payload.State == false then
			controller.States[evidence] = false
		else
			controller.States[evidence] = nil
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
	end

	return controller
end
