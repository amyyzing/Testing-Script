return function(dependencies)
	local player = assert(dependencies.Player, "auto-spirit-box requires Player")
	local RunService = assert(dependencies.RunService, "auto-spirit-box requires RunService")
	local ask = assert(dependencies.AskSpiritBox, "auto-spirit-box requires AskSpiritBox")
	local interval = tonumber(dependencies.Interval) or 2.05
	local button = dependencies.Button
	local disabledColor = button and button.BackgroundColor3
	local enabledColor = dependencies.EnabledColor or disabledColor
	local controller = {Enabled = false, Accumulator = 0, QuestionIndex = 0}

	local function questions()
		local result = {}
		local gui = player:FindFirstChild("PlayerGui")
		local box = gui and gui:FindFirstChild("SpiritBoxQuestions")
		local holder = box and box:FindFirstChild("Holder")
		for _, name in ipairs({"Aggression", "Location", "Age"}) do
			local category = holder and holder:FindFirstChild(name)
			local detection = category and category:FindFirstChild("Detection")
			local value = detection and detection.Text
			if type(value) == "string" and value ~= "" then table.insert(result, value) end
		end
		if #result == 0 then result[1] = "Are you in the room with me?" end
		return result
	end

	local function render()
		if not button then return end
		button.Text = controller.Enabled and "AUTO SPIRIT: ON" or "AUTO SPIRIT: OFF"
		button.BackgroundColor3 = controller.Enabled and enabledColor or disabledColor
	end

	local function askNext()
		local available = questions()
		controller.QuestionIndex = controller.QuestionIndex % #available + 1
		ask(available[controller.QuestionIndex])
	end

	function controller:SetEnabled(enabled)
		self.Enabled = enabled == true
		self.Accumulator = self.Enabled and interval or 0
		render()
		return self.Enabled
	end

	function controller:Toggle()
		return self:SetEnabled(not self.Enabled)
	end

	function controller:Destroy()
		self.Enabled = false
		if self.ButtonConnection then self.ButtonConnection:Disconnect() end
		if self.HeartbeatConnection then self.HeartbeatConnection:Disconnect() end
	end

	controller.HeartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not controller.Enabled then return end
		controller.Accumulator += math.max(0, tonumber(deltaTime) or 0)
		if controller.Accumulator < interval then return end
		controller.Accumulator %= interval
		askNext()
	end)
	if button then
		controller.ButtonConnection = button.MouseButton1Click:Connect(function()
			controller:Toggle()
		end)
	end
	render()
	return controller
end
