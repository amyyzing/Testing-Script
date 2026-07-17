return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "los-sight requires Traffic")
	local World = dependencies.Workspace or workspace
	local Ghost = assert(dependencies.Ghost, "los-sight requires Ghost")
	local Players = dependencies.Players or game:GetService("Players")
	local RunService = assert(dependencies.RunService, "los-sight requires RunService")
	local clock = dependencies.Clock or os.clock
	local interval = tonumber(dependencies.SampleInterval) or 0.1
	local maximumDistance = tonumber(dependencies.MaximumDistance) or 120
	local customLOS = dependencies.HasLineOfSight
	local Tracker = {
		Kind = "dormant",
		Running = true,
		Active = false,
		Accumulator = 0,
		Visible = setmetatable({}, {__mode = "k"}),
	}

	local raycastParams
	local function hasLineOfSight(player)
		if customLOS then return customLOS(player) == true end
		local character = player.Character
		local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
		local ghostRoot = Ghost:FindFirstChild("HumanoidRootPart")
			or Ghost.PrimaryPart or Ghost:FindFirstChildWhichIsA("BasePart", true)
		if not playerRoot or not ghostRoot then return false end
		local direction = playerRoot.Position - ghostRoot.Position
		if direction.Magnitude > maximumDistance then return false end
		if not raycastParams then
			raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = {Ghost}
			raycastParams.IgnoreWater = true
		end
		local result = World:Raycast(ghostRoot.Position, direction, raycastParams)
		return result == nil or result.Instance:IsDescendantOf(character)
	end

	local function publish(player, visible)
		Traffic("PlayerLineOfSight", {
			Player = player,
			LineOfSight = visible,
			Time = clock(),
		}):SendTo("PlayerSpeed")
	end

	function Tracker:Sample()
		if not self.Active then return end
		local seen = {}
		for _, player in ipairs(Players:GetPlayers()) do
			seen[player] = true
			local visible = player:GetAttribute("Dead") ~= true and hasLineOfSight(player)
			if visible then
				self.Visible[player] = true
				publish(player, true)
			elseif self.Visible[player] then
				self.Visible[player] = nil
				publish(player, false)
			end
		end
		for player in pairs(self.Visible) do
			if not seen[player] then
				self.Visible[player] = nil
				publish(player, false)
			end
		end
	end

	local function stopSampling()
		if not Tracker.SampleConnection then return end
		Tracker.SampleConnection:Disconnect()
		Tracker.SampleConnection = nil
	end

	local function setActive(active)
		if Tracker.Active == active then return end
		Tracker.Active = active
		Tracker.Accumulator = 0
		if not active then
			stopSampling()
			for player in pairs(Tracker.Visible) do publish(player, false) end
			table.clear(Tracker.Visible)
			return
		end
		Tracker.SampleConnection = RunService.Heartbeat:Connect(function(deltaTime)
			if not Tracker.Running then return end
			Tracker.Accumulator += math.max(0, tonumber(deltaTime) or 0)
			if Tracker.Accumulator < interval then return end
			Tracker.Accumulator %= interval
			Tracker:Sample()
		end)
		Tracker:Sample()
	end

	Tracker.Disconnect = Traffic:Receive("LOSSight", function(signal, payload)
		if signal == "HuntingState" then
			setActive(type(payload) == "table" and payload.Hunting == true)
		end
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.Disconnect()
		setActive(false)
	end

	return Tracker
end
