return function(dependencies)
	local Traffic = assert(dependencies.Traffic, "cross-animation requires Traffic")
	local RunService = assert(dependencies.RunService, "cross-animation requires RunService")
	local clock = dependencies.Clock or os.clock
	local Tracker = {
		Kind = "discardable",
		Running = true,
		Active = setmetatable({}, {__mode = "k"}),
	}

	local function findPart(cross)
		local part = cross and cross:FindFirstChild("Cross", true)
		return part and part:IsA("BasePart") and part or nil
	end

	local function finish(cross, animated)
		Tracker.Active[cross] = nil
		Traffic("CrossAnimation", {
			Cross = cross,
			Animated = animated,
		}):SendTo("Demon")
	end

	Tracker.DisconnectTraffic = Traffic:Receive("CrossAnimation", function(signal, payload)
		if signal ~= "CrossBurn" or not payload or payload.EquipDisabled ~= true then return end
		local cross, part = payload.Cross, findPart(payload.Cross)
		if not cross or not part or Tracker.Active[cross] then return end
		Tracker.Active[cross] = {
			Part = part,
			Started = clock(),
			StartPosition = part.Position,
			LastCFrame = part.CFrame,
			Angle = 0,
			Rise = 0,
			Horizontal = 0,
		}
	end)

	Tracker.Connection = RunService.Heartbeat:Connect(function()
		if not Tracker.Running then return end
		local now = clock()
		for cross, observation in pairs(Tracker.Active) do
			local part = observation.Part
			if not cross.Parent or not part.Parent then
				finish(cross, false)
			else
				local current = part.CFrame
				local relative = observation.LastCFrame.Rotation:ToObjectSpace(current.Rotation)
				local _, angle = relative:ToAxisAngle()
				angle = math.abs(angle)
				if angle <= math.rad(100) then observation.Angle += angle end
				local dx = current.Position.X - observation.StartPosition.X
				local dy = current.Position.Y - observation.StartPosition.Y
				local dz = current.Position.Z - observation.StartPosition.Z
				observation.Rise = math.max(observation.Rise, dy)
				observation.Horizontal = math.max(observation.Horizontal, math.sqrt(dx * dx + dz * dz))
				observation.LastCFrame = current
				local animated = observation.Rise >= 0.45
					and observation.Angle >= math.rad(45)
					and observation.Horizontal <= 5
				if animated then
					finish(cross, true)
				elseif now - observation.Started >= 4 then
					finish(cross, false)
				end
			end
		end
	end)

	function Tracker:Destroy()
		if not self.Running then return end
		self.Running = false
		self.DisconnectTraffic()
		self.Connection:Disconnect()
		table.clear(self.Active)
	end

	return Tracker
end
